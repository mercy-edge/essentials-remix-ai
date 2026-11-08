#!/usr/bin/env ruby
# Exports project content (maps, encounters, trainers, quests, map battles)
# to CSV files for Google Sheets import.
#
# Usage (from game root or tools/):
#   ruby tools/export_content_tracker.rb
#
# Output: ContentTracker/*.csv

require "csv"
require "fileutils"
require "json"

ROOT = File.expand_path("..", __dir__)
OUT  = File.join(ROOT, "ContentTracker")
PBS  = File.join(ROOT, "PBS")

FileUtils.mkdir_p(OUT)

def csv_escape_row(fields)
  fields.map { |f| f.nil? ? "" : f.to_s }
end

def write_csv(name, headers, rows)
  path = File.join(OUT, name)
  CSV.open(path, "w", force_quotes: false) do |csv|
    csv << headers
    rows.each { |r| csv << csv_escape_row(r) }
  end
  puts "  wrote #{name} (#{rows.size} rows)"
  path
end

def region_for_map(map_id, comment_name, display_name)
  n = "#{comment_name} #{display_name}".downcase
  return "Elwynn / Northshire" if n =~ /northshire|elwynn|goldshire|echo ridge|eastvale|stormwind|vineyard|abbey|forest edge|stone cairn|crystal lake|jerod|maclure|stonefield|fargodeep|jasperlode/
  return "Battle Frontier" if n =~ /battle (tower|palace|arena|factory|hall|castle)|frontier/
  return "Dungeon" if n =~ /dungeon/
  "Essen (stock)"
end

#-------------------------------------------------------------------------------
# Maps
#-------------------------------------------------------------------------------
def parse_map_metadata
  path = File.join(PBS, "map_metadata.txt")
  maps = []
  current = nil
  File.foreach(path, chomp: true) do |line|
    next if line.strip.empty? || line.start_with?("# See")
    if line =~ /^\[(\d+)\]\s*(?:#\s*(.*))?$/
      maps << current if current
      current = {
        "id" => $1.to_i,
        "comment" => ($2 || "").strip,
        "name" => "",
        "outdoor" => false,
        "show_area" => false,
        "map_position" => "",
        "healing_spot" => "",
        "battle_back" => "",
        "flags" => ""
      }
      next
    end
    next unless current
    if line =~ /^(\w+)\s*=\s*(.*)$/
      key, val = $1, $2.strip
      case key
      when "Name" then current["name"] = val
      when "Outdoor" then current["outdoor"] = (val.downcase == "true")
      when "ShowArea" then current["show_area"] = (val.downcase == "true")
      when "MapPosition" then current["map_position"] = val
      when "HealingSpot" then current["healing_spot"] = val
      when "BattleBack" then current["battle_back"] = val
      when "Flags" then current["flags"] = val
      end
    end
  end
  maps << current if current
  maps
end

#-------------------------------------------------------------------------------
# Encounters
#-------------------------------------------------------------------------------
def parse_encounters
  path = File.join(PBS, "encounters.txt")
  rows = []
  map_id = nil
  version = 0
  map_name = ""
  enc_type = nil
  density = ""

  File.foreach(path, chomp: true) do |line|
    next if line.strip.empty? || line.start_with?("# See") || line.start_with?("#---")
    if line =~ /^\[(\d+)(?:,(\d+))?\]\s*(?:#\s*(.*))?$/
      map_id = $1.to_i
      version = ($2 || "0").to_i
      map_name = ($3 || "").strip
      enc_type = nil
      density = ""
      next
    end
    next unless map_id
    stripped = line.strip
    # Encounter type header: Land,21  or  OldRod
    if stripped =~ /^([A-Za-z]+)(?:,(\d+))?$/ && !stripped.include?(" ")
      # Heuristic: encounter types don't look like SPECIES (all caps with digits rare as sole word + optional number)
      # But SPECIES lines are "chance,SPECIES,min,max". Type lines have no commas except optional density.
      enc_type = $1
      density = $2 || ""
      next
    end
    if stripped =~ /^(\d+),([A-Z0-9_]+),(\d+)(?:,(\d+))?$/
      chance, species, min_lv, max_lv = $1, $2, $3, $4 || $3
      form = ""
      if species =~ /^(.+)_(\d+)$/
        base, form_n = $1, $2
        # Keep full species id; form is the suffix for convenience
        form = form_n
      end
      rows << [
        format("%03d", map_id),
        map_name,
        version,
        enc_type,
        density,
        chance,
        species,
        form,
        min_lv,
        max_lv,
        "", # Status (manual)
        ""  # Notes (manual)
      ]
    end
  end
  rows
end

#-------------------------------------------------------------------------------
# Trainers (PBS)
#-------------------------------------------------------------------------------
def parse_trainers
  path = File.join(PBS, "trainers.txt")
  rows = []
  t_type = t_name = t_ver = nil
  lose = items = ""
  slot = 0
  mon = nil

  flush_mon = lambda do
    return unless mon && t_type
    rows << [
      t_type, t_name, t_ver, lose, items,
      mon[:slot], mon[:species], mon[:level],
      mon[:item], mon[:moves], mon[:ability], mon[:gender],
      mon[:iv], mon[:shiny], mon[:ball], mon[:shadow], mon[:reinforcement],
      "PBS", "", "" # Source, Status, Notes
    ]
  end

  File.foreach(path, chomp: true) do |line|
    next if line.strip.empty? || line.start_with?("# See") || line.start_with?("#---")
    if line =~ /^\[([A-Z0-9_]+),([^,\]]+)(?:,(\d+))?\]$/
      flush_mon.call
      mon = nil
      t_type = $1
      t_name = $2.strip
      t_ver = ($3 || "0")
      lose = ""
      items = ""
      slot = 0
      next
    end
    next unless t_type
    if line =~ /^LoseText\s*=\s*(.*)$/
      lose = $1.strip
      next
    end
    if line =~ /^Items\s*=\s*(.*)$/
      items = $1.strip
      next
    end
    if line =~ /^Pokemon\s*=\s*([A-Z0-9_]+),(\d+)/
      flush_mon.call
      slot += 1
      mon = {
        slot: slot, species: $1, level: $2,
        item: "", moves: "", ability: "", gender: "",
        iv: "", shiny: "", ball: "", shadow: "", reinforcement: ""
      }
      next
    end
    next unless mon
    case line
    when /^\s+Moves\s*=\s*(.*)$/ then mon[:moves] = $1.strip
    when /^\s+Item\s*=\s*(.*)$/ then mon[:item] = $1.strip
    when /^\s+AbilityIndex\s*=\s*(.*)$/ then mon[:ability] = $1.strip
    when /^\s+Gender\s*=\s*(.*)$/ then mon[:gender] = $1.strip
    when /^\s+IV\s*=\s*(.*)$/ then mon[:iv] = $1.strip
    when /^\s+Shiny\s*=\s*(.*)$/ then mon[:shiny] = $1.strip
    when /^\s+Ball\s*=\s*(.*)$/ then mon[:ball] = $1.strip
    when /^\s+Shadow\s*=\s*(.*)$/ then mon[:shadow] = $1.strip
    when /^\s+Reinforcement\s*=\s*(.*)$/ then mon[:reinforcement] = $1.strip
    when /^\s+Name\s*=\s*(.*)$/ then mon[:nickname] = $1.strip # unused col for now
    end
  end
  flush_mon.call
  rows
end

#-------------------------------------------------------------------------------
# Quests (static extract from Quest Journal — keep in sync with DEFINITIONS)
#-------------------------------------------------------------------------------
def quest_rows
  # Hardcoded mirror of QuestJournal::DEFINITIONS for offline export (Ruby 1.8 game
  # procs can't be evaluated here). Update when adding quests.
  [
    [1, "ID_MARSHAL_MEET", "A Threat Within",
     "Speak with Marshal McBride.",
     "Deputy Willem", "Marshal McBride",
     "— (starter)", "",
     50, "", "",
     "deputy_willem", "marshal_mcbride",
     "076 Northshire Abbey", "", ""],
    [2, "ID_KOBOLD_CLEANUP", "Kobold Camp Cleanup",
     "Defeat 4 kobold trainers (counter).",
     "Marshal McBride", "Marshal McBride",
     "Complete: A Threat Within", "4",
     50, 25, "POKEBALL x5",
     "marshal_mcbride", "marshal_mcbride",
     "076 Northshire Abbey / outskirts", "", ""],
    [3, "ID_INVESTIGATE_ECHO_RIDGE", "Investigate Echo Ridge",
     "Defeat 5 kobold workers near Echo Ridge Mine.",
     "Marshal McBride", "Marshal McBride",
     "Complete: Kobold Camp Cleanup", "5",
     75, 40, "",
     "marshal_mcbride", "marshal_mcbride",
     "032/033 Echo Ridge", "", ""],
    [4, "ID_SIMPLE_LETTER", "Simple Letter",
     "Read letter; speak to Llane Beshere (Warrior).",
     "Marshal McBride", "Llane Beshere",
     "Kobold Cleanup + Warrior class", "",
     65, "", "",
     "marshal_mcbride", "llane_beshere",
     "076 Northshire Abbey", "", ""],
    [5, "ID_CONSECRATED_LETTER", "Consecrated Letter",
     "Read letter; speak to Brother Sammuel (Paladin).",
     "Marshal McBride", "Brother Sammuel",
     "Kobold Cleanup + Paladin class", "",
     65, "", "",
     "marshal_mcbride", "brother_sammuel",
     "076 Northshire Abbey", "", ""],
    [6, "ID_ENCRYPTED_LETTER", "Encrypted Letter",
     "Read letter; speak to Jorik Kerridan (Rogue).",
     "Marshal McBride", "Jorik Kerridan",
     "Kobold Cleanup + Rogue class", "",
     65, "", "",
     "marshal_mcbride", "jorik_kerridan",
     "076 stables", "", ""],
    [7, "ID_HALLOWED_LETTER", "Hallowed Letter",
     "Read letter; speak to Priestess Anetta (Priest).",
     "Marshal McBride", "Priestess Anetta",
     "Kobold Cleanup + Priest class", "",
     65, "", "",
     "marshal_mcbride", "priestess_anetta",
     "076 Northshire Abbey", "", ""],
    [8, "ID_GLYPHIC_LETTER", "Glyphic Letter",
     "Read letter; speak to Khelden Bremen (Mage).",
     "Marshal McBride", "Khelden Bremen",
     "Kobold Cleanup + Mage class", "",
     65, "", "",
     "marshal_mcbride", "khelden_bremen",
     "076 abbey library", "", ""],
    [9, "ID_TAINTED_LETTER", "Tainted Letter",
     "Read letter; speak to Drusilla La Salle (Warlock).",
     "Marshal McBride", "Drusilla La Salle",
     "Kobold Cleanup + Warlock class", "",
     65, "", "",
     "marshal_mcbride", "drusilla_la_salle",
     "076 beside abbey", "", ""]
  ]
end

#-------------------------------------------------------------------------------
# Scripted trainers (static + MapEvents scan)
#-------------------------------------------------------------------------------
def scripted_trainer_defs
  [
    ["Kobold Vermin", "KOBOLD", "pbBattleKoboldVerminTrainer",
     "Quest Journal", "Random Lv.1 from vermin pool", "1",
     "Counts toward Kobold Camp Cleanup (need 4)", "076", ""],
    ["Kobold Worker", "KOBOLD", "pbBattleEchoRidgeKoboldWorker",
     "Quest Journal", "1 mon: Spinarak/Poochyena/Rattata/Pidgey Lv.1–2", "1–2",
     "Counts toward Investigate Echo Ridge (need 5)", "032", ""],
    ["Kobold Laborer", "KOBOLD", "pbBattleEchoRidgeMineLaborer",
     "Quest Journal", "1–2 mons from Diglett/Zubat/Rattata/Spinarak", "3",
     "Echo Ridge Mine interior; not quest counter", "033", ""]
  ]
end

def collect_script_strings(node, out = [])
  case node
  when Array
    # Event command: [code, indent, [params...]]
    if node.size >= 3 && node[0].is_a?(Integer) && node[2].is_a?(Array)
      node[2].each { |p| out << p if p.is_a?(String) }
    end
    node.each { |child| collect_script_strings(child, out) }
  when Hash
    node.each_value { |child| collect_script_strings(child, out) }
  end
  out
end

def parse_map_battles
  dir = File.join(PBS, "MapEvents")
  rows = []
  return rows unless Dir.exist?(dir)

  Dir.glob(File.join(dir, "map*.json")).sort.each do |path|
    map_id = File.basename(path)[/\d+/].to_i
    begin
      data = JSON.parse(File.read(path))
    rescue
      next
    end
    events = data["events"]
    next unless events.is_a?(Hash)

    events.each do |ev_key, ev|
      next unless ev.is_a?(Hash)
      ev_id = ev["id"] || ev_key
      ev_name = ev["name"].to_s
      scripts = collect_script_strings(ev)
      npc_level = ""
      scripts.each do |s|
        if s =~ /NPC_LEVEL:(\d+)/
          npc_level = $1
          break
        end
      end

      # Join fragments — MapYamlBridge sometimes splits long Script lines across params.
      joined = scripts.join(" ")

      joined.scan(/TrainerBattle\.start\(:([A-Z0-9_]+)\s*,\s*"([^"]+)"(?:\s*,\s*(\d+))?\)/).each do |tt, tn, ver|
        rows << [format("%03d", map_id), ev_id, ev_name, tt, tn, ver || "0", "TrainerBattle.start", npc_level, "", ""]
      end
      joined.scan(/TrainerBattle\.start\(:([A-Z0-9_]+)\s*,\s*'([^']+)'(?:\s*,\s*(\d+))?\)/).each do |tt, tn, ver|
        rows << [format("%03d", map_id), ev_id, ev_name, tt, tn, ver || "0", "TrainerBattle.start", npc_level, "", ""]
      end

      battle_aliases = {
        "pbBattleKoboldVerminTrainer" => ["KOBOLD", "Kobold Vermin", "pbBattleKoboldVerminTrainer"],
        "pbBattleEchoRidgeKoboldWorker" => ["KOBOLD", "Kobold Worker", "pbBattleEchoRidgeKoboldWorker"],
        "pbBattleEchoRidgeMineLaborer" => ["KOBOLD", "Kobold Laborer", "pbBattleEchoRidgeMineLaborer"],
        "NorthshireAbbeyEvents.run(:kobold_worker)" => ["KOBOLD", "Kobold Worker", "NorthshireAbbeyEvents.run(:kobold_worker)"],
        "NorthshireAbbeyEvents.run(:kobold_laborer)" => ["KOBOLD", "Kobold Laborer", "NorthshireAbbeyEvents.run(:kobold_laborer)"],
        "NorthshireAbbeyEvents.run(:kobold_vermin)" => ["KOBOLD", "Kobold Vermin", "NorthshireAbbeyEvents.run(:kobold_vermin)"],
        "NorthshireAbbeyEvents.run(:reinforcement_test_trainer)" => ["YOUNGSTER", "Ben (reinforcement test)", "NorthshireAbbeyEvents.run(:reinforcement_test_trainer)"]
      }
      battle_aliases.each do |needle, meta|
        next unless joined.include?(needle)
        rows << [format("%03d", map_id), ev_id, ev_name, meta[0], meta[1], "0", meta[2], npc_level, "", ""]
      end

      # Catch run(:symbol) when symbol alone is a known battle handler
      if joined =~ /NorthshireAbbeyEvents\.run\(\s*:([a-z0-9_]+)\s*\)/
        sym = $1
        if %w[kobold_worker kobold_laborer kobold_vermin reinforcement_test_trainer].include?(sym)
          # already handled via aliases when full string present
        elsif joined.include?("NorthshireAbbeyEvents.run") && ev_name =~ /kobold|worker|laborer|vermin/i
          rows << [format("%03d", map_id), ev_id, ev_name, "KOBOLD", ev_name, "0", "NorthshireAbbeyEvents.run(:#{sym})", npc_level, "", ""]
        end
      elsif joined.include?("NorthshireAbbeyEvents.run") && ev_name =~ /kobold|worker|laborer|vermin/i
        # Fragmented call: infer from event name
        label = ev_name
        script = "NorthshireAbbeyEvents.run (see event)"
        rows << [format("%03d", map_id), ev_id, ev_name, "KOBOLD", label, "0", script, npc_level, "", ""]
      end
    end
  end
  rows
end

#-------------------------------------------------------------------------------
# Dashboard summary
#-------------------------------------------------------------------------------
def write_readme(maps, enc_rows, trainer_rows, battle_rows)
  path = File.join(OUT, "GOOGLE_SHEETS_SETUP.md")
  File.write(path, <<~MD)
    # Content Tracker → Google Sheets

    Generated by `ruby tools/export_content_tracker.rb`.

    ## Quick start

    1. Open [Google Sheets](https://sheets.google.com) → **Blank** spreadsheet.
    2. Rename the workbook: **Essentials Remix AI — Content Tracker**.
    3. For each CSV below: **File → Import → Upload → Replace current sheet** (or Insert new sheet).
    4. After import, rename tabs to match the CSV names (without `.csv`).
    5. Add a **Dashboard** tab first (see below).

    ## Tabs

    | Tab | Source | Purpose |
    |-----|--------|---------|
    | Dashboard | manual | Progress counts, filters, legend |
    | Maps | `PBS/map_metadata.txt` | All maps + region + checklist |
    | Encounters | `PBS/encounters.txt` | One row per wild slot |
    | Trainers_PBS | `PBS/trainers.txt` | Defined trainer parties |
    | Trainers_Scripted | Quest Journal | Kobold battle templates |
    | Map_Battles | `PBS/MapEvents/*.json` | Placed fights on maps |
    | Quests | Quest Journal defs | Story / letter quests |

    ## Status columns (visual tracking)

    On **Maps**, **Encounters**, **Trainers_***, **Quests**, and **Map_Battles**, fill **Status**:

    | Value | Meaning | Suggested color |
    |-------|---------|-----------------|
    | `Todo` | Not designed / not placed | Light gray |
    | `Draft` | In editor, needs polish | Light yellow |
    | `Playtest` | Needs in-game check | Light orange |
    | `Done` | Locked / shipping | Light green |
    | `Cut` | Removed / deprecated | Light red |

    **Format → Conditional formatting → Text contains** each value → set fill color.

    ## Dashboard formulas (after import)

    Put these on a sheet named `Dashboard`:

    ```
    A1  Content Tracker
    A3  Metric                          B3  Count
    A4  Maps                            B4  =COUNTA(Maps!A:A)-1
    A5  Maps Done                       B5  =COUNTIF(Maps!K:K,"Done")
    A6  Encounter slots                 B6  =COUNTA(Encounters!A:A)-1
    A7  Encounter maps Done             B7  =COUNTIF(Encounters!K:K,"Done")
    A8  PBS trainer mons                B8  =COUNTA(Trainers_PBS!A:A)-1
    A9  Map battles                     B9  =COUNTA(Map_Battles!A:A)-1
    A10 Quests                          B10 =COUNTA(Quests!A:A)-1
    A11 Quests Done                     B11 =COUNTIF(Quests!O:O,"Done")
    ```

    Add a filter view on **Encounters** filtered to `Region = Elwynn / Northshire` (via Maps VLOOKUP) or map ID ≥ 076 for your custom block.

    ## Re-sync from the project

    After editing PBS or quests:

    ```bash
    ruby tools/export_content_tracker.rb
    ```

    Then in Sheets: open the tab → **File → Import → Upload** the new CSV → **Replace current sheet**.

    Manual **Status** / **Notes** columns are wiped on full replace — keep a copy of those columns, or only paste over data columns A–J.

    ## Tip: protect Status columns

    Work in two layers:
    1. **Data columns** — regenerated from this tool.
    2. **Status / Notes / Owner** — edited only in Sheets.

    Counts at last export: maps=#{maps.size}, encounter slots=#{enc_rows.size}, PBS trainer mons=#{trainer_rows.size}, map battle placements=#{battle_rows.size}, quests=#{quest_rows.size}.
  MD
  puts "  wrote GOOGLE_SHEETS_SETUP.md"
end

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------
puts "Exporting content tracker CSVs → #{OUT}"

maps = parse_map_metadata
encounter_rows = parse_encounters
enc_map_ids = encounter_rows.map { |r| r[0].to_i }.uniq

map_rows = maps.map do |m|
  id = m["id"]
  comment = m["comment"]
  name = m["name"]
  region = region_for_map(id, comment, name)
  has_enc = enc_map_ids.include?(id) ? "Yes" : "No"
  [
    format("%03d", id),
    comment,
    name,
    region,
    m["outdoor"] ? "TRUE" : "FALSE",
    m["show_area"] ? "TRUE" : "FALSE",
    m["map_position"],
    m["healing_spot"],
    m["battle_back"],
    m["flags"],
    has_enc,
    "", # Status
    ""  # Notes
  ]
end

write_csv("Maps.csv",
  %w[MapID CommentName DisplayName Region Outdoor ShowArea MapPosition HealingSpot BattleBack Flags HasEncounters Status Notes],
  map_rows)

write_csv("Encounters.csv",
  %w[MapID MapName Version EncounterType Density Chance Species Form MinLevel MaxLevel Status Notes],
  encounter_rows)

trainer_rows = parse_trainers
write_csv("Trainers_PBS.csv",
  %w[TrainerType TrainerName Version LoseText TrainerItems Slot Species Level HeldItem Moves AbilityIndex Gender IVs Shiny Ball Shadow Reinforcement Source Status Notes],
  trainer_rows)

write_csv("Trainers_Scripted.csv",
  %w[DisplayName TrainerType Script Function PartySummary Level Notes TypicalMapIDs Status],
  scripted_trainer_defs)

battle_rows = parse_map_battles
write_csv("Map_Battles.csv",
  %w[MapID EventID EventName TrainerType TrainerName Version ScriptCall NPC_Level Status Notes],
  battle_rows)

write_csv("Quests.csv",
  %w[QuestID Constant Name Objective Giver TurnIn Prerequisites CounterTarget Exp Money Items OfferHandler TurnInHandler Maps Status Notes],
  quest_rows)

# Legend / status helper sheet
write_csv("Status_Legend.csv",
  %w[Status Meaning ColorHint],
  [
    ["Todo", "Not designed or not placed yet", "Gray"],
    ["Draft", "In progress in editor", "Yellow"],
    ["Playtest", "Needs in-game verification", "Orange"],
    ["Done", "Finished / shipping", "Green"],
    ["Cut", "Removed or deprecated", "Red"]
  ])

write_readme(maps, encounter_rows, trainer_rows, battle_rows)
puts "Done."
