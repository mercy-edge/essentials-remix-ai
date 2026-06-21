#===============================================================================
# MapEventInjector — write RPG Maker XP events into Data/Map###.rxdata from Ruby.
#
# WHY "NOTHING HAPPENED" — common causes:
#   • skip_if_position_taken was true and (28,4) already had an event → skipped.
#   • Non-debug run: you clicked "No" on the confirm dialog.
#   • RPG Maker XP had the map open and overwrote rxdata when saving the project.
#
# Run from Play Test:
#   F9 → Eval Script:  pbRunMapEventInjector
# Or Script command:   pbRunMapEventInjector
#
# After running: close RPG Maker if open, reopen project, open Map 076 — you should
# see the new event. Check Data/map_event_injector.log for [OK] / errors.
#
# Edit PATCHES below. Map ID must match the map in your tree (076 = Map076.rxdata).
#===============================================================================

module MapEventInjector
  LOG_FILE = "Data/map_event_injector.log"

  # Kobold worker @ outdoor Northshire (map 76): replaces any previous event on that tile.
  PATCHES = [
    {
      map_id:                   76,
      x:                        28,
      y:                        4,
      name:                     "Worker",
      graphic_name:             "trainer_KOBOLD",
      graphic_hue:              0,
      direction:                2,
      pattern:                  0,
      character_index:          0,
      trigger:                  0,
      skip_if_position_taken:   false,
      replace_existing_at_tile: true,
      script:                   "NorthshireAbbeyEvents.run(:kobold_worker)"
    }
  ].freeze

  module_function

  def log_line(msg)
    File.open(LOG_FILE, "a") do |f|
      f.puts("[#{Time.now}] #{msg}")
    end
  rescue StandardError
    nil
  end

  def map_path(map_id)
    sprintf("Data/Map%03d.rxdata", map_id.to_i)
  end

  def map_file_readable?(path)
    return true if pbRgssExists?(path)
    return true if FileTest.exist?(path)

    false
  end

  def push_script_commands(list, script)
    first = true
    script.to_s.split(/\n/).each do |line|
      chunk = line.gsub(/\s+$/, "")
      next if chunk.empty?

      code = first ? 355 : 655
      list.push(RPG::EventCommand.new(code, 0, [chunk]))
      first = false
    end
    list.push(RPG::EventCommand.new(0, 0, []))
    list
  end

  def next_event_id(map)
    ids = map.events.keys.map { |k| k.to_i }
    return 1 if ids.empty?

    ids.max + 1
  end

  def remove_events_at_tile!(map, x, y)
    removed = []
    map.events.keys.each do |k|
      ev = map.events[k]
      next unless ev

      if ev.x == x && ev.y == y
        map.events.delete(k)
        removed.push(k.to_i)
      end
    end
    removed
  end

  def position_taken?(map, x, y)
    map.events.each_value do |ev|
      return true if ev && ev.x == x && ev.y == y
    end
    false
  end

  def build_event(spec, event_id)
    ev = RPG::Event.new(spec[:x], spec[:y])
    ev.id   = event_id
    ev.name = spec[:name].to_s

    page = RPG::Event::Page.new
    g    = page.graphic
    g.character_name = spec[:graphic_name].to_s
    g.character_hue  = spec[:graphic_hue].to_i
    g.direction      = spec.fetch(:direction, 2).to_i
    g.pattern        = spec.fetch(:pattern, 0).to_i
    begin
      g.character_index = spec.fetch(:character_index, 0).to_i if g.respond_to?(:character_index=)
    rescue StandardError
      nil
    end

    page.trigger      = spec.fetch(:trigger, 0).to_i
    page.walk_anime   = spec.fetch(:walk_anime, true)
    page.step_anime   = spec.fetch(:step_anime, false)
    page.direction_fix = spec.fetch(:direction_fix, false)

    page.list = []
    push_script_commands(page.list, spec[:script] || 'pbMessage(_INTL("Hi."))')

    ev.pages = [page]
    ev
  end

  # Applies one patch. Returns [ok, message].
  def apply_patch(spec)
    map_id = spec[:map_id].to_i
    path   = map_path(map_id)

    unless map_file_readable?(path)
      msg = _INTL("Missing map file {1} (game working folder must contain Data/).", path)
      log_line("FAIL #{msg}")
      return [false, msg]
    end

    map = load_data(path)

    if spec[:replace_existing_at_tile]
      removed = remove_events_at_tile!(map, spec[:x].to_i, spec[:y].to_i)
      log_line("Map #{map_id}: removed events at (#{spec[:x]},#{spec[:y]}): #{removed.inspect}") unless removed.empty?
    end

    if spec[:skip_if_position_taken] && position_taken?(map, spec[:x].to_i, spec[:y].to_i)
      msg = _INTL("Skipped {1}: tile ({2},{3}) already has an event.", spec[:name], spec[:x], spec[:y])
      log_line("SKIP #{msg}")
      return [false, msg]
    end

    event_id = spec[:event_id]
    event_id = event_id.to_i if event_id
    event_id ||= next_event_id(map)

    if map.events[event_id] && !spec[:overwrite]
      msg = _INTL("Skipped {1}: event ID {2} exists (set :overwrite => true).", spec[:name], event_id)
      log_line("SKIP #{msg}")
      return [false, msg]
    end

    map.events[event_id] = build_event(spec.merge(event_id: event_id), event_id)

    save_data(map, path)

    msg = _INTL("OK: wrote {6} — map {1} event {2} \"{3}\" at ({4},{5})", map_id, event_id, spec[:name], spec[:x], spec[:y], path)
    log_line("SAVE #{msg}")
    [true, msg]
  rescue StandardError => e
    log_line("ERROR #{e.class}: #{e.message}\n#{e.backtrace&.join("\n")}")
    [false, "#{e.class}: #{e.message}"]
  end

  def apply_all!(silent = false)
    File.open(LOG_FILE, "a") { |f| f.puts("\n--- run #{Time.now} cwd=#{Dir.pwd} ---\n") }

    lines = []
    PATCHES.each do |spec|
      ok, msg = apply_patch(spec)
      lines << "#{ok ? '[OK]' : '[!!]'} #{msg}"
    end
    text = lines.join("\n")
    pbMessage(text) unless silent
    echoln(text) if $DEBUG
    lines
  end
end

def pbRunMapEventInjector(silent = false)
  unless $DEBUG
    unless pbConfirmMessage(_INTL("Inject events into Data/Map###.rxdata on disk?\\nClose RPG Maker XP first (or reload project after).\\nBackup Data/ recommended."))
      pbMessage(_INTL("Cancelled."))
      return nil
    end
  end

  MapEventInjector.apply_all!(silent)
end
