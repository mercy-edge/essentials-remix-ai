#===============================================================================
# Elwynn Forest map stubs (maps 77–96 + Echo Ridge Mine 33).
#
# Maps exist for scripting / editing. No edge connections or door warps yet —
# add those later. Indoor/caves only nest under parents in MapInfos (editor tree).
#
# Nesting (MapInfos parent only):
#   Lion's Pride Inn (78) → Goldshire (77)
#   Fargodeep Mine (82) → Forest's Edge (83)
#   Jasperlode Mine (85) → Eastvale Logging Camp (81)
#
# Debug → Elwynn Forest warps… / Warp to Goldshire
#===============================================================================

module ElwynnForestEvents
  # [id, name, kind, parent_id or nil, warp_x, warp_y]
  MAPS = [
    [77, 'Goldshire', :outdoor, nil, 13, 11],
    [78, "Lion's Pride Inn", :indoor, 77, 8, 10],
    [79, 'Brackwell Pumpkin Patch', :outdoor, nil, 13, 11],
    [80, 'Crystal Lake', :outdoor, nil, 13, 11],
    [81, 'Eastvale Logging Camp', :outdoor, nil, 13, 11],
    [82, 'Fargodeep Mine', :cave, 83, 9, 12],
    [83, "Forest's Edge", :outdoor, nil, 13, 11],
    [84, "Heroes' Vigil", :outdoor, nil, 13, 11],
    [85, 'Jasperlode Mine', :cave, 81, 9, 12],
    [86, "Jerod's Landing", :outdoor, nil, 13, 11],
    [87, 'The Maclure Vineyards', :outdoor, nil, 13, 11],
    [88, 'Mirror Lake', :outdoor, nil, 13, 11],
    [89, 'Mirror Lake Orchard', :outdoor, nil, 13, 11],
    [90, 'Ridgepoint Tower', :outdoor, nil, 13, 11],
    [91, 'Stone Cairn Lake', :outdoor, nil, 13, 11],
    [92, 'The Stonefield Farm', :outdoor, nil, 13, 11],
    [93, 'Stormwind City', :outdoor, nil, 13, 11],
    [94, 'Thunder Falls', :outdoor, nil, 13, 11],
    [95, 'Tower of Azora', :outdoor, nil, 13, 11],
    [96, 'Westbrook Garrison', :outdoor, nil, 13, 11],
    [33, 'Echo Ridge Mine', :cave, nil, 9, 12] # existing Northshire cave
  ].freeze

  module_function

  def map_entry(map_id)
    MAPS.find { |row| row[0].to_i == map_id.to_i }
  end

  def elwynn_map?(map_id)
    !map_entry(map_id).nil?
  end

  def map_file_ok?(map_id)
    path = sprintf('Data/Map%03d.rxdata', map_id.to_i)
    pbRgssExists?(path) || FileTest.exist?(path)
  end

  # Rename MAP### entries and set parent_id for nested indoor/caves.
  def ensure_mapinfos!
    return false unless $DEBUG

    mapinfos = pbLoadMapInfos
    return false unless mapinfos

    changed = false
    max_order = 0
    mapinfos.each_value { |info| max_order = [max_order, info.order.to_i].max if info }

    MAPS.each do |id, name, kind, parent, _wx, _wy|
      next unless map_file_ok?(id)

      info = mapinfos[id]
      unless info
        info = RPG::MapInfo.new
        max_order += 1
        info.order = max_order
        mapinfos[id] = info
        changed = true
      end

      if info.name.to_s != name
        info.name = name
        changed = true
      end

      want_parent = parent ? parent.to_i : 0
      if info.respond_to?(:parent_id) && info.parent_id.to_i != want_parent
        if want_parent == 0 || map_file_ok?(want_parent)
          info.parent_id = want_parent
          changed = true
        end
      end

      if info.respond_to?(:expanded=) && want_parent == 0
        info.expanded = true
      end
    end

    return false unless changed

    save_data(mapinfos, 'Data/MapInfos.rxdata')
    $game_temp.map_infos = nil if $game_temp
    echoln('[ElwynnForest] MapInfos names/parents updated') if $DEBUG
    true
  rescue StandardError => e
    echoln("[ElwynnForest] ensure_mapinfos! failed: #{e.message}") if $DEBUG
    false
  end

  def run(sym)
    case sym.to_sym
    when :goldshire_townsfolk, :townsfolk
      pbMessage(_INTL("Quiet days in Goldshire… until the Defias show up again."))
    when :innkeeper
      pbMessage(_INTL("Welcome to the Lion's Pride Inn! Rest as long as you like."))
    when :kobold
      pbMessage(_INTL('You no take candle!'))
    when :marshal_dughan
      marshal_dughan
    else
      pbMessage(_INTL('ElwynnForestEvents: unknown action {1}.', sym))
    end
  end

  def marshal_dughan
    q = QuestJournal::ID_REPORT_TO_GOLDSHIRE
    if pbQuestActive?(q)
      if QuestJournal.turn_in_ready?(q)
        pbMessage(_INTL(
          "You have word from McBride? Northshire is a garden compared to Elwynn Forest, " \
          "but I wonder what Marshal McBride has to report.\nHere, let me have his papers..."
        ))
        cmsg = QuestJournal.completion_text(q)
        pbMessage(cmsg) if cmsg
        pbQuestComplete(q)
      else
        pbMessage(_INTL("McBride said he'd send papers with you. Don't lose them on the road."))
      end
      return
    end
    if pbQuestDone?(q)
      pbMessage(_INTL("Acting Deputy Status suits you. Elwynn won't protect itself."))
    else
      pbMessage(_INTL("If McBride sent you, finish his work in Northshire first."))
    end
  end

  def warp_to!(map_id, x = nil, y = nil, facing = 2)
    ensure_mapinfos!
    entry = map_entry(map_id)
    unless entry
      pbMessage(_INTL('Unknown Elwynn map ID {1}.', map_id))
      return false
    end
    wx = x.nil? ? entry[4] : x
    wy = y.nil? ? entry[5] : y
    pbDoorWarpTo(map_id.to_i, wx, wy, facing: facing, se: false)
  end

  def debug_warp_menu
    ensure_mapinfos!
    names = MAPS.map { |id, name, _kind, parent, _wx, _wy|
      nest = parent ? format(' (in %s)', map_entry(parent)&.[](1) || parent) : ''
      format('%03d %s%s', id, name, nest)
    }
    cmd = pbMessage(_INTL('Warp to which Elwynn map?'), names, -1)
    return if cmd < 0

    row = MAPS[cmd]
    warp_to!(row[0])
  end
end

# Keep GoldshireEvents working for older event scripts.
module GoldshireEvents
  MAP_ID   = 77
  MAP_NAME = 'Goldshire'
  WARP_X   = 13
  WARP_Y   = 11

  module_function

  def goldshire_map?(map_id)
    map_id.to_i == MAP_ID
  end

  def ensure_mapinfo_name!
    ElwynnForestEvents.ensure_mapinfos!
  end

  def run(sym)
    ElwynnForestEvents.run(sym)
  end

  def warp_here!(x = WARP_X, y = WARP_Y, facing = 2)
    ElwynnForestEvents.warp_to!(MAP_ID, x, y, facing)
  end
end

EventHandlers.add(:on_enter_map, :elwynn_forest_mapinfos,
                  proc { |_map_id|
                    ElwynnForestEvents.ensure_mapinfos!
                  })

MenuHandlers.add(:debug_menu, :elwynn_forest_menu, {
  'name'        => _INTL('Elwynn Forest warps…'),
  'parent'      => :field_menu,
  'description' => _INTL('Warp to Goldshire and other Elwynn Forest maps.'),
  'effect'      => proc {
    ElwynnForestEvents.debug_warp_menu
  }
})

MenuHandlers.add(:debug_menu, :warp_goldshire, {
  'name'        => _INTL('Warp to Goldshire'),
  'parent'      => :field_menu,
  'description' => _INTL('Transfer the player to Goldshire (map 77).'),
  'effect'      => proc {
    GoldshireEvents.warp_here!
  }
})
