#===============================================================================
# MapYamlBridge — edit map EVENTS as text; tiles stay in Map###.rxdata.
#
# Rxdata is Ruby Marshal binary — not editable in Cursor. This plugin keeps:
#   PBS/MapEvents/map076.json / map033.json   ← editable (events only)
#   Data/Map076.rxdata          ← tiles + merged events (game & RPG Maker read this)
#
# JSON: uses Ruby stdlib 'json' when present; otherwise pure_json.rb (MKXP has neither).
# Installing gems on your PC does not add stdlib to the game EXE — copy stdlib into the
# game folder only if you maintain a custom Ruby next to mkxp; usually unnecessary.
# YAML: optional require 'yaml' for .yml files when your runtime includes it.
#
# Workflow:
#   1) Export events from .rxdata → JSON:
#      Play Test → F9 → Debug → Files options... → Export all map events to JSON
#      (Registered from Scripts/387_Debug_MenuCommands.rb — Essentials v21 has no Eval Script.)
#      Or single map: pbExportMapEventsYaml(76) from any Ruby eval context you have.
#      Bulk Ruby method: pbExportAllMapEventsJson  → every Data/Map###.rxdata → map###.json
#   2) Edit the JSON in Cursor. Save.
#   3) Run the game: JSON merges into .rxdata at boot if newer (or force_import: true).
#
#===============================================================================
# Plugin code is eval'd with a fake __FILE__ (see PluginManager), so never use
# File.dirname(__FILE__) for requires. Load helpers from the real plugin folder.
_pj = File.expand_path(File.join('Plugins', 'MapYamlBridge', 'pure_json.rb'))
unless File.file?(_pj)
  raise LoadError, "MapYamlBridge: missing pure_json.rb (expected at #{_pj})"
end
load _pj

def map_yaml_bridge_stdlib?(name)
  $LOAD_PATH.any? { |dir| File.file?(File.join(dir, "#{name}.rb")) }
end

JSON_IMPL = if map_yaml_bridge_stdlib?('json')
  require 'json'
  :stdlib
else
  :pure
end

YAML_AVAILABLE = false
if map_yaml_bridge_stdlib?('yaml')
  begin
    require 'yaml'
    YAML_AVAILABLE = true
  rescue LoadError
    YAML_AVAILABLE = false
  end
end

module MapYamlBridge
  DIR             = "PBS/MapEvents"
  FORMAT_VERSION  = 1
  FORCE_FILE_FLAG = 'force_import'

  module_function

  def parse_json_text(text)
    if JSON_IMPL == :stdlib
      JSON.parse(text)
    else
      PureJson.parse(text)
    end
  end

  def pretty_json_text(obj)
    if JSON_IMPL == :stdlib
      JSON.pretty_generate(obj)
    else
      PureJson.pretty_generate(obj)
    end
  end

  def enabled?
    File.directory?(DIR)
  end

  def path_for_map(map_id)
    File.join(DIR, sprintf("map%03d.json", map_id.to_i))
  end

  def legacy_yml_path(map_id)
    File.join(DIR, sprintf("map%03d.yml", map_id.to_i))
  end

  def event_file_for_map(map_id)
    pjson = path_for_map(map_id)
    pyml  = legacy_yml_path(map_id)
    return pjson if FileTest.exist?(pjson)
    return pyml if FileTest.exist?(pyml)

    nil
  end

  def map_rx_path(map_id)
    sprintf("Data/Map%03d.rxdata", map_id.to_i)
  end

  def load_map_document(path)
    text = File.open(path, 'r:UTF-8', &:read)
    ext = File.extname(path).downcase
    if ext == '.json'
      return parse_json_text(text)
    end
    if %w[.yml .yaml].include?(ext)
      unless YAML_AVAILABLE
        mid = File.basename(path)[/^map(\d+)/i, 1].to_i
        raise _INTL(
          "Found {1} but this Ruby has no 'yaml' library. Use map{2}.json instead.",
          path, sprintf('%03d', mid)
        )
      end
      return YAML.load(text)
    end

    parse_json_text(text)
  end

  #---------------------------------------------------------------------------
  # Export — rxdata → JSON (events only; tiles unchanged in rxdata)
  #---------------------------------------------------------------------------
  def build_map_events_document(map_id)
    path_rx = map_rx_path(map_id)
    unless pbRgssExists?(path_rx) || FileTest.exist?(path_rx)
      raise _INTL("No map file: {1}", path_rx)
    end

    map = load_data(path_rx)
    h   = {
      'format'         => 'map_events_v1',
      'format_version' => FORMAT_VERSION,
      'map_id'         => map_id.to_i,
      'exported'       => true,
      'exported_note'  => _INTL("Generated from {1}. Edit events below; save; run game to merge.", path_rx),
      'events'         => {}
    }

    map.events.each do |eid, ev|
      next unless ev

      h['events'][eid.to_s] = event_to_hash(ev)
    end
    h
  end

  def export_map_events!(map_id)
    Dir.mkdir(DIR) unless File.directory?(DIR)

    h = build_map_events_document(map_id)
    outpath = path_for_map(map_id)
    File.open(outpath, 'w:UTF-8') do |f|
      f.write(pretty_json_text(h))
      f.write("\n")
    end
    echoln("[MapYamlBridge] Wrote #{outpath}") if $DEBUG
    outpath
  end

  # Map IDs that have a per-map rxdata file (excludes MapInfos.rxdata, etc.)
  def rxdata_map_ids
    ids = []
    Dir.glob(File.join('Data', 'Map*.rxdata')).each do |path|
      bn = File.basename(path)
      next unless bn =~ /\AMap(\d+)\.rxdata\z/i

      ids << Regexp.last_match(1).to_i
    end
    ids.sort.uniq
  end

  # Export events for every map → PBS/MapEvents/mapNNN.json (used by import_all_if_stale).
  # Returns { ok: Integer, errors: Array<[map_id, message]> }
  def export_all_map_events!
    Dir.mkdir(DIR) unless File.directory?(DIR)
    ok = 0
    errs = []
    rxdata_map_ids.each do |mid|
      export_map_events!(mid)
      ok += 1
    rescue StandardError => e
      errs.push([mid, e.message])
    end
    { ok: ok, errors: errs }
  end

  def event_to_hash(ev)
    {
      'id'    => ev.id,
      'name'  => ev.name.to_s,
      'x'     => ev.x,
      'y'     => ev.y,
      'pages' => ev.pages.map { |pg| page_to_hash(pg) }
    }
  end

  def page_to_hash(page)
    out = {
      'graphic' => graphic_to_hash(page.graphic),
      'trigger' => page.trigger,
      'walk_anime' => page.walk_anime,
      'step_anime' => page.step_anime,
      'direction_fix' => page.direction_fix,
      'through' => page.through,
      'always_on_top' => page.always_on_top,
      'list' => page.list.map do |cmd|
        [cmd.code, cmd.indent, normalize_parameters(cmd.parameters)]
      end
    }
    out['condition_b64'] = [Marshal.dump(page.condition)].pack('m0')
    out
  end

  def graphic_to_hash(g)
    return {} unless g

    h = {
      'character_name' => g.character_name.to_s,
      'character_hue' => g.character_hue.to_i,
      'direction' => g.direction.to_i,
      'pattern' => g.pattern.to_i
    }
    h['character_index'] = g.character_index.to_i if g.respond_to?(:character_index)
    h
  end

  def normalize_parameters(params)
    return [] if params.nil?

    params.map do |p|
      case p
      when Numeric, String, TrueClass, FalseClass, NilClass
        p
      when Array
        normalize_parameters(p)
      when Tone
        { '_tone' => [p.red, p.green, p.blue, p.gray] }
      else
        { '_marshal64' => [Marshal.dump(p)].pack('m0') }
      end
    end
  end

  #---------------------------------------------------------------------------
  # Import — JSON/YAML → merge events into rxdata
  #---------------------------------------------------------------------------
  def import_map_events!(map_id, opts = {})
    path = event_file_for_map(map_id)
    return false unless path

    data = load_map_document(path)
    return false unless data.is_a?(Hash)

    if data['exported'] == false && !opts[:force] && data[FORCE_FILE_FLAG] != true
      echoln("[MapYamlBridge] Skip #{path} (exported: false — run pbExportMapEventsYaml or set force_import: true)") if $DEBUG
      return false
    end

    path_rx = map_rx_path(map_id)
    unless pbRgssExists?(path_rx) || FileTest.exist?(path_rx)
      raise _INTL("Cannot import: missing {1}", path_rx)
    end

    map = load_data(path_rx)
    rebuild_events_from_yaml!(map, data)
    save_data(map, path_rx)
    echoln("[MapYamlBridge] Imported events → #{path_rx}") if $DEBUG
    true
  end

  def rebuild_events_from_yaml!(map, data)
    evs = data['events']
    raise _INTL("Map events file missing 'events' hash") unless evs.is_a?(Hash)

    # Default true: only upsert events listed in file (safe for hand-written patches).
    # Set merge_events: false to replace the entire map.events hash from file only.
    merge = data['merge_events'] != false
    map.events = {} unless merge

    evs.each do |eid_str, eh|
      next unless eh.is_a?(Hash)

      eid = (eh['id'] || eid_str).to_i
      ev  = RPG::Event.new(eh['x'].to_i, eh['y'].to_i)
      ev.id   = eid
      ev.name = eh['name'].to_s
      ev.pages = []
      (eh['pages'] || []).each do |ph|
        ev.pages.push(hash_to_page(ph))
      end
      map.events[eid] = ev
    end
  end

  def hash_to_page(ph)
    page = RPG::Event::Page.new
    g = page.graphic
    gh = ph['graphic'] || {}
    g.character_name = gh['character_name'].to_s
    g.character_hue  = gh['character_hue'].to_i
    g.direction      = gh['direction'].to_i
    g.pattern        = gh['pattern'].to_i
    if g.respond_to?(:character_index=) && gh.key?('character_index')
      g.character_index = gh['character_index'].to_i
    end

    page.trigger       = ph['trigger'].to_i if ph.key?('trigger')
    page.walk_anime    = ph['walk_anime'] != false
    page.step_anime    = ph['step_anime'] == true
    page.direction_fix = ph['direction_fix'] == true
    page.through       = ph['through'] == true
    page.always_on_top = ph['always_on_top'] == true

    if ph['condition_b64'].to_s != ''
      page.condition = Marshal.load(ph['condition_b64'].unpack('m0')[0])
    end

    apply_page_movement!(page, ph)

    page.list = []
    (ph['list'] || []).each do |row|
      code, indent, params = parse_command_row(row)
      params = denormalize_parameters(params)
      page.list.push(RPG::EventCommand.new(code, indent, params))
    end
    page
  end

  # Optional movement: "wander" builds a repeating move_route that calls move_random_range(x,y)
  # (same pattern as bounded NPCs). move_route accepts raw RPG move route hashes for experts.
  def apply_page_movement!(page, ph)
    if ph['wander'].is_a?(Hash)
      w = ph['wander']
      xr = w.key?('range_x') ? w['range_x'].to_i : 1
      yr = w.key?('range_y') ? w['range_y'].to_i : 1
      script = sprintf('move_random_range(%d, %d)', xr, yr)
      page.move_type = 3
      page.move_speed = w.key?('speed') ? w['speed'].to_i : 2
      page.move_frequency = w.key?('frequency') ? w['frequency'].to_i : 2
      page.move_route = build_repeat_script_route(script)
    elsif ph['move_route'].is_a?(Hash)
      page.move_type = ph.fetch('move_type', 3).to_i
      page.move_speed = ph.fetch('move_speed', 3).to_i
      page.move_frequency = ph.fetch('move_frequency', 3).to_i
      page.move_route = hash_to_move_route_from_json(ph['move_route'])
    else
      page.move_type       = ph['move_type'].to_i       if ph.key?('move_type')
      page.move_speed      = ph['move_speed'].to_i      if ph.key?('move_speed')
      page.move_frequency  = ph['move_frequency'].to_i  if ph.key?('move_frequency')
    end
  end

  def build_repeat_script_route(script_string)
    route = RPG::MoveRoute.new
    route.repeat    = true
    route.skippable = true
    route.list.clear
    script_code = 45
    script_code = PBMoveRoute::SCRIPT if defined?(PBMoveRoute) && PBMoveRoute.const_defined?(:SCRIPT)
    route.list.push(RPG::MoveCommand.new(script_code, [script_string]))
    route.list.push(RPG::MoveCommand.new(0))
    route
  end

  # Each entry: [code] or [code, parameters] where parameters is an array (e.g. script string).
  def hash_to_move_route_from_json(h)
    route = RPG::MoveRoute.new
    route.repeat    = h['repeat'] != false
    route.skippable = h['skippable'] != false
    route.list.clear
    (h['list'] || []).each do |row|
      next unless row.is_a?(Array)

      code = row[0].to_i
      params = row[1]
      if params.nil?
        route.list.push(RPG::MoveCommand.new(code))
      else
        par = denormalize_parameters(params)
        route.list.push(RPG::MoveCommand.new(code, par))
      end
    end
    route.list.push(RPG::MoveCommand.new(0)) if route.list.empty? || route.list[-1].code != 0
    route
  end

  def parse_command_row(row)
    return [0, 0, []] if row.nil?

    if row.is_a?(Array) && row.length >= 3
      return [row[0].to_i, row[1].to_i, row[2]]
    end
    if row.is_a?(Hash)
      return [row['code'].to_i, row['indent'].to_i, row['parameters'] || []]
    end

    [0, 0, []]
  end

  def denormalize_parameters(params)
    return [] if params.nil?

    params.map do |p|
      case p
      when Hash
        if p['_tone']
          a = p['_tone']
          Tone.new(a[0], a[1], a[2], a[3])
        elsif p['_marshal64']
          Marshal.load(p['_marshal64'].unpack('m0')[0])
        else
          p
        end
      when Array
        denormalize_parameters(p)
      else
        p
      end
    end
  end

  def collect_map_event_paths
    out = {}
    Dir.glob(File.join(DIR, 'map*.json')).each do |path|
      id = File.basename(path)[/^map(\d+)/i, 1]
      out[id] = path if id
    end
    Dir.glob(File.join(DIR, 'map*.yml')).each do |path|
      id = File.basename(path)[/^map(\d+)/i, 1]
      next unless id
      out[id] ||= path
    end
    out
  end

  # Import when map*.json (or map*.yml) is newer than rxdata (or force_import in file)
  def import_all_if_stale
    return unless enabled?

    collect_map_event_paths.each_value do |path|
      id = File.basename(path)[/^map(\d+)/i, 1]
      next unless id

      map_id = id.to_i
      rx     = map_rx_path(map_id)
      next unless FileTest.exist?(rx)

      data = load_map_document(path)
      next unless data.is_a?(Hash)

      force = data[FORCE_FILE_FLAG] == true
      next if data['exported'] == false && !force

      fmt = File.mtime(path)
      rmt = File.mtime(rx)
      next if !force && fmt <= rmt

      import_map_events!(map_id, force: force)
    rescue StandardError => e
      echoln("[MapYamlBridge] #{path}: #{e.message}") if $DEBUG
      pbPrintException(e) if $DEBUG
    end
  end
end

def pbExportMapEventsYaml(map_id)
  path = MapYamlBridge.export_map_events!(map_id)
  pbMessage(_INTL("Exported events to:\\n{1}", path))
  path
rescue StandardError => e
  pbMessage(_INTL("Export failed: {1}", e.message))
  nil
end

def pbExportAllMapEventsJson
  r = MapYamlBridge.export_all_map_events!
  msg = _INTL("Exported events for {1} map(s) to PBS/MapEvents/map###.json.", r[:ok])
  if r[:errors].any?
    detail = r[:errors].map { |id, m| sprintf("Map%03d: %s", id, m) }.join("\n")
    msg += "\n\n" + _INTL("Failures ({1}):\\n{2}", r[:errors].length, detail)
  end
  pbMessage(msg)
  r
rescue StandardError => e
  pbMessage(_INTL("Bulk export failed: {1}", e.message))
  nil
end

def pbImportMapEventsYaml(map_id)
  ok = MapYamlBridge.import_map_events!(map_id, force: true)
  rx = sprintf("Data/Map%03d.rxdata", map_id.to_i)
  pbMessage(ok ? _INTL("Imported events into {1}.", rx) : _INTL("Import skipped or failed."))
  ok
rescue StandardError => e
  pbMessage(_INTL("Import failed: {1}", e.message))
  nil
end

# Debug menu entry is registered from Scripts/387_Debug_MenuCommands.rb ( reliable even when PluginScripts.rxdata is stale).

# --- Merge JSON/YAML → rxdata at boot (debug + release; Compiler is debug-only) ---
module Game
  class << self
    unless method_defined?(:initialize_with_map_yaml_bridge)
      alias_method :initialize_with_map_yaml_bridge, :initialize
      def initialize
        MapYamlBridge.import_all_if_stale if defined?(MapYamlBridge)
        initialize_with_map_yaml_bridge
      end
    end
  end
end
