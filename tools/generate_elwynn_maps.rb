# Generate Elwynn Forest map PBS stubs + MapEvents JSON (run once from game root).
# Does NOT write rxdata (already copied).

require 'fileutils'
require 'json'

ROOT = File.expand_path('..', __dir__)
EVENTS_DIR = File.join(ROOT, 'PBS', 'MapEvents')
FileUtils.mkdir_p(EVENTS_DIR)

# id => [name, kind, parent_id_or_nil, map_position "region,x,y", battle_back, environment]
# kind: :outdoor, :indoor, :cave
MAPS = {
  77 => ['Goldshire',              :outdoor, nil, '0,20,12', 'field', 'Grass'],
  78 => ["Lion's Pride Inn",       :indoor,  77,  '0,20,12', 'indoor1', nil],
  79 => ['Brackwell Pumpkin Patch',:outdoor, nil, '0,21,14', 'field', 'Grass'],
  80 => ['Crystal Lake',           :outdoor, nil, '0,20,13', 'field', 'Grass'],
  81 => ['Eastvale Logging Camp',  :outdoor, nil, '0,22,12', 'field', 'Grass'],
  82 => ['Fargodeep Mine',         :cave,    83,  '0,19,12', 'cave1', 'Cave'],
  83 => ["Forest's Edge",          :outdoor, nil, '0,19,12', 'field', 'Grass'],
  84 => ["Heroes' Vigil",          :outdoor, nil, '0,19,11', 'field', 'Grass'],
  85 => ['Jasperlode Mine',        :cave,    81,  '0,22,12', 'cave1', 'Cave'],
  86 => ["Jerod's Landing",        :outdoor, nil, '0,18,13', 'field', 'Grass'],
  87 => ['The Maclure Vineyards',  :outdoor, nil, '0,19,14', 'field', 'Grass'],
  88 => ['Mirror Lake',            :outdoor, nil, '0,20,11', 'field', 'Grass'],
  89 => ['Mirror Lake Orchard',    :outdoor, nil, '0,20,10', 'field', 'Grass'],
  90 => ['Ridgepoint Tower',       :outdoor, nil, '0,22,11', 'field', 'Grass'],
  91 => ['Stone Cairn Lake',       :outdoor, nil, '0,23,12', 'field', 'Grass'],
  92 => ['The Stonefield Farm',    :outdoor, nil, '0,20,14', 'field', 'Grass'],
  93 => ['Stormwind City',         :outdoor, nil, '0,17,13', 'city',  nil],
  94 => ['Thunder Falls',          :outdoor, nil, '0,23,11', 'field', 'Grass'],
  95 => ['Tower of Azora',         :outdoor, nil, '0,21,12', 'field', 'Grass'],
  96 => ['Westbrook Garrison',     :outdoor, nil, '0,18,12', 'field', 'Grass'],
  # Existing — metadata refreshed only
  33 => ['Echo Ridge Mine',        :cave,    nil, '0,12,11', 'cave1', 'Cave']
}.freeze

def msg_event(id, name, x, y, graphic, lines, opts = {})
  list = []
  script = opts[:script] || (lines.length == 1 && lines[0] =~ /\A(pb[A-Z]|[A-Za-z0-9_]+Events\.|pbDoorWarpTo)/)
  if script
    lines.each_with_index do |line, i|
      list << [i.zero? ? 355 : 655, 0, [line]]
    end
  else
    list << [355, 0, ['pbMessage(_INTL(']]
    list << [655, 0, ["\"#{lines[0]}\""]]
    list << [655, 0, ['))']]
  end
  list << [0, 0, []]
  {
    'id' => id,
    'name' => name,
    'x' => x,
    'y' => y,
    'pages' => [{
      'graphic' => {
        'character_name' => graphic,
        'character_hue' => opts.fetch(:hue, 0),
        'direction' => opts.fetch(:dir, 2),
        'pattern' => 0
      },
      'trigger' => opts.fetch(:trigger, 0),
      'walk_anime' => opts.fetch(:walk_anime, graphic != ''),
      'step_anime' => false,
      'direction_fix' => opts.fetch(:direction_fix, false),
      'through' => false,
      'always_on_top' => false,
      'list' => list
    }]
  }
end

def write_events(map_id, events_hash, note)
  doc = {
    'format' => 'map_events_v1',
    'format_version' => 1,
    'map_id' => map_id,
    'force_import' => true,
    'merge_events' => false,
    'exported' => true,
    'exported_note' => note,
    'events' => {}
  }
  events_hash.each { |eid, ev| doc['events'][eid.to_s] = ev }
  path = File.join(EVENTS_DIR, format('map%03d.json', map_id))
  File.write(path, JSON.pretty_generate(doc) + "\n")
  puts "Wrote #{path}"
end

# --- Per-map starter events ---
write_events(77, {
  1 => msg_event(1, 'Welcome Sign', 12, 10, 'NPC 08',
                 ['Welcome to Goldshire.\\nElwynn Forest\'s quiet heart.'],
                 direction_fix: true, walk_anime: false),
  2 => msg_event(2, 'Townsfolk', 14, 12, 'NPC 01',
                 ['ElwynnForestEvents.run(:goldshire_townsfolk)']),
  3 => msg_event(3, "Lion's Pride Door", 16, 10, '',
                 ['pbDoorWarpTo(78, 8, 11, facing: 8)'],
                 trigger: 0, walk_anime: false)
}, 'Goldshire hub — door to Lion\'s Pride Inn (78).')

write_events(78, {
  1 => msg_event(1, 'Inn Exit', 8, 12, '',
                 ['pbDoorWarpTo(77, 16, 11, facing: 2)'],
                 trigger: 1, walk_anime: false),
  2 => msg_event(2, 'Innkeeper', 8, 7, 'NPC 02',
                 ['ElwynnForestEvents.run(:innkeeper)'])
}, "Lion's Pride Inn — nested under Goldshire.")

write_events(79, {
  1 => msg_event(1, 'Sign', 12, 10, 'NPC 08',
                 ['Brackwell Pumpkin Patch.\\nWatch for Defias among the vines.'],
                 direction_fix: true, walk_anime: false)
}, 'Brackwell Pumpkin Patch')

write_events(80, {
  1 => msg_event(1, 'Sign', 12, 10, 'NPC 08',
                 ['Crystal Lake.\\nClear water under Elwynn pines.'],
                 direction_fix: true, walk_anime: false)
}, 'Crystal Lake')

write_events(81, {
  1 => msg_event(1, 'Sign', 12, 10, 'NPC 08',
                 ['Eastvale Logging Camp.'],
                 direction_fix: true, walk_anime: false),
  2 => msg_event(2, 'Jasperlode Entrance', 18, 4, '',
                 ['pbDoorWarpTo(85, 9, 13, facing: 8)'],
                 trigger: 0, walk_anime: false)
}, 'Eastvale — warp into Jasperlode Mine.')

write_events(82, {
  1 => msg_event(1, 'Mine Exit', 9, 14, '',
                 ['pbDoorWarpTo(83, 10, 5, facing: 2)'],
                 trigger: 1, walk_anime: false),
  2 => msg_event(2, 'Kobold', 6, 9, 'NPC 18',
                 ['ElwynnForestEvents.run(:kobold)'],
                 hue: 250)
}, 'Fargodeep Mine — nested under Forest\'s Edge.')

write_events(83, {
  1 => msg_event(1, 'Sign', 12, 10, 'NPC 08',
                 ["Forest's Edge.\\nWest toward Westbrook Garrison."],
                 direction_fix: true, walk_anime: false),
  2 => msg_event(2, 'Fargodeep Entrance', 10, 4, '',
                 ['pbDoorWarpTo(82, 9, 13, facing: 8)'],
                 trigger: 0, walk_anime: false)
}, "Forest's Edge — warp into Fargodeep Mine.")

write_events(84, {
  1 => msg_event(1, 'Memorial', 12, 10, 'NPC 08',
                 ["Heroes' Vigil.\\nA quiet place for the fallen."],
                 direction_fix: true, walk_anime: false)
}, "Heroes' Vigil")

write_events(85, {
  1 => msg_event(1, 'Mine Exit', 9, 14, '',
                 ['pbDoorWarpTo(81, 18, 5, facing: 2)'],
                 trigger: 1, walk_anime: false),
  2 => msg_event(2, 'Kobold', 6, 9, 'NPC 18',
                 ['ElwynnForestEvents.run(:kobold)'],
                 hue: 250)
}, 'Jasperlode Mine — nested under Eastvale.')

write_events(86, {
  1 => msg_event(1, 'Sign', 12, 10, 'NPC 08',
                 ["Jerod's Landing.\\nBoats for Stormwind."],
                 direction_fix: true, walk_anime: false)
}, "Jerod's Landing")

write_events(87, {
  1 => msg_event(1, 'Sign', 12, 10, 'NPC 08',
                 ['The Maclure Vineyards.'],
                 direction_fix: true, walk_anime: false)
}, 'The Maclure Vineyards')

write_events(88, {
  1 => msg_event(1, 'Sign', 12, 10, 'NPC 08',
                 ['Mirror Lake.'],
                 direction_fix: true, walk_anime: false)
}, 'Mirror Lake')

write_events(89, {
  1 => msg_event(1, 'Sign', 12, 10, 'NPC 08',
                 ['Mirror Lake Orchard.'],
                 direction_fix: true, walk_anime: false)
}, 'Mirror Lake Orchard')

write_events(90, {
  1 => msg_event(1, 'Sign', 12, 10, 'NPC 08',
                 ['Ridgepoint Tower.'],
                 direction_fix: true, walk_anime: false)
}, 'Ridgepoint Tower')

write_events(91, {
  1 => msg_event(1, 'Sign', 12, 10, 'NPC 08',
                 ['Stone Cairn Lake.'],
                 direction_fix: true, walk_anime: false)
}, 'Stone Cairn Lake')

write_events(92, {
  1 => msg_event(1, 'Sign', 12, 10, 'NPC 08',
                 ['The Stonefield Farm.'],
                 direction_fix: true, walk_anime: false)
}, 'The Stonefield Farm')

write_events(93, {
  1 => msg_event(1, 'Sign', 12, 10, 'NPC 08',
                 ['Stormwind City.\\n(Placeholder map — rebuild later.)'],
                 direction_fix: true, walk_anime: false)
}, 'Stormwind City placeholder')

write_events(94, {
  1 => msg_event(1, 'Sign', 12, 10, 'NPC 08',
                 ['Thunder Falls.'],
                 direction_fix: true, walk_anime: false)
}, 'Thunder Falls')

write_events(95, {
  1 => msg_event(1, 'Sign', 12, 10, 'NPC 08',
                 ['Tower of Azora.\\nHome of a peculiar wizard.'],
                 direction_fix: true, walk_anime: false)
}, 'Tower of Azora')

write_events(96, {
  1 => msg_event(1, 'Sign', 12, 10, 'NPC 08',
                 ['Westbrook Garrison.'],
                 direction_fix: true, walk_anime: false)
}, 'Westbrook Garrison')

# Metadata block for clipboard/append
meta_lines = ["#-------------------------------"]
MAPS.keys.sort.each do |id|
  next if id == 33 # already in file; skip duplicate append for 33 unless we replace
  name, kind, _parent, pos, bb, env = MAPS[id]
  meta_lines << format('[%03d]   # %s', id, name)
  meta_lines << "Name = #{name}"
  if kind == :outdoor
    meta_lines << 'Outdoor = true'
    meta_lines << 'ShowArea = true'
  end
  meta_lines << "MapPosition = #{pos}"
  meta_lines << "BattleBack = #{bb}" if bb
  meta_lines << "Environment = #{env}" if env
  meta_lines << '#-------------------------------'
end

meta_path = File.join(ROOT, 'PBS', '_elwynn_map_metadata_snippet.txt')
File.write(meta_path, meta_lines.join("\n") + "\n")
puts "Wrote #{meta_path}"

conn = <<~CONN
  #===============================================================================
  # Elwynn Forest cluster (isolated from Northshire / rest of region map)
  #===============================================================================
  # West–east spine
  96,E,0,83,W,0
  83,E,0,77,W,0
  77,E,0,95,W,0
  95,E,0,81,W,0
  81,E,0,91,W,0
  # North of Goldshire
  89,S,0,88,N,0
  88,S,0,77,N,0
  84,E,0,88,W,0
  # South of Goldshire
  77,S,0,80,N,0
  80,S,0,92,N,0
  87,E,0,92,W,0
  92,E,0,79,W,0
  # Stormwind approach (west)
  93,E,0,86,W,0
  86,E,0,96,W,0
  # Northeast extras
  81,N,0,90,S,0
  91,N,0,94,S,0
CONN
conn_path = File.join(ROOT, 'PBS', '_elwynn_map_connections_snippet.txt')
File.write(conn_path, conn)
puts "Wrote #{conn_path}"

# Dump MAPS as Ruby for the plugin to require conceptually — write plugin data file
data_rb = File.join(ROOT, 'Plugins', 'ElwynnForest', 'elwynn_maps.rb')
FileUtils.mkdir_p(File.dirname(data_rb))
File.open(data_rb, 'w') do |f|
  f.puts '# Auto-generated map registry for Elwynn Forest. Edit with care.'
  f.puts 'module ElwynnForestEvents'
  f.puts '  # [id, name, kind, parent_id or nil, warp_x, warp_y]'
  f.puts '  MAPS = ['
  MAPS.each do |id, (name, kind, parent, _pos, _bb, _env)|
    next if id == 33
    wx, wy = case kind
             when :indoor then [8, 10]
             when :cave then [9, 12]
             else [13, 11]
             end
    f.puts "    [#{id}, #{name.inspect}, :#{kind}, #{parent.inspect}, #{wx}, #{wy}],"
  end
  f.puts "    [33, 'Echo Ridge Mine', :cave, nil, 9, 12], # existing"
  f.puts '  ].freeze'
  f.puts 'end'
end
puts "Wrote #{data_rb}"
