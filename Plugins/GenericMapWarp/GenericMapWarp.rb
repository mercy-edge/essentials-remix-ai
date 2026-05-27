#===============================================================================
# Generic door-style map warp by map name or numeric ID.
#-------------------------------------------------------------------------------
# Typical event  -  Script (single line):
#   pbDoorWarpTo("Northshire Abbey Indoor 1F", 1, 7)
#
# By map ID (RPG Maker Map Properties ID, e.g. 32):
#   pbDoorWarpTo(32, 1, 7)
#
# Options (keywords):
#   facing: 2 4 6 8  OR  :down :left :right :up  OR  :preserve (keep current facing)
#   fade:   true/false   (default true  -  screen fade like Transfer Player with fade)
#   se:     "Exit Door" or nil/false to skip sound (Essentials default door SE name)
#
# Also available:
#   pbResolveMapIdFromName("Some Map")  → Integer or nil
#===============================================================================

def pbNormalizeDoorFacing(facing)
  return ($game_player&.direction || 2) if facing.nil? || facing == :preserve || facing == :keep
  case facing
  when :down  then 2
  when :left  then 4
  when :right then 6
  when :up    then 8
  else
    i = facing.to_i
    (i >= 2 && i <= 8 && [2, 4, 6, 8].include?(i)) ? i : 2
  end
end

# Resolves Integer IDs, digit strings, RPG Maker map names (MapInfos), or PBS Name (GameData::MapMetadata real_name).
def pbResolveMapIdFromName(name_or_id)
  return nil if name_or_id.nil?

  if name_or_id.is_a?(Integer)
    id = name_or_id.to_i
    return id if id > 0 && pbRgssExists?(sprintf("Data/Map%03d.rxdata", id))
    return nil
  end

  s = name_or_id.to_s.strip
  return nil if s.empty?

  if s =~ /\A\d+\z/
    id = s.to_i
    return id if id > 0 && pbRgssExists?(sprintf("Data/Map%03d.rxdata", id))
  end

  map_file_ok = proc { |map_id|
    map_id.to_i > 0 && pbRgssExists?(sprintf("Data/Map%03d.rxdata", map_id.to_i))
  }

  mapinfos = pbLoadMapInfos rescue nil
  if mapinfos
    want_down = s.downcase
    mapinfos.each_key do |id|
      info = mapinfos[id]
      next unless info&.name

      nm = info.name.to_s
      next unless nm == s || nm.downcase == want_down
      return id if map_file_ok.call(id)
    end
  end

  if defined?(GameData::MapMetadata)
    want_down = s.downcase
    GameData::MapMetadata.each do |meta|
      rn = meta&.real_name.to_s.strip
      next if rn.empty?
      next unless rn == s || rn.downcase == want_down
      return meta.id if map_file_ok.call(meta.id)
    end
  end

  nil
end

# Door-style warp: Exit Door SE (same as Essentials compiled door transfers), vehicles/followers cleanup, optional fade.
def pbDoorWarpTo(map_name_or_id, x, y, facing: 2, fade: true, se: "Exit Door")
  map_id = pbResolveMapIdFromName(map_name_or_id)
  unless map_id
    num = map_name_or_id.to_s =~ /\A\d+\z/ || map_name_or_id.is_a?(Integer)
    hint = if num
             _INTL("Create that map in RPG Maker XP and save  -  you need Data/Map{1}.rxdata.", sprintf("%03d", map_name_or_id.to_i))
           else
             _INTL("Use the exact RPG Maker map name, or a map ID whose .rxdata file exists.")
           end
    pbMessage(_INTL("Can't find that map ({1}).\\n{2}", map_name_or_id.to_s, hint))
    return false
  end

  map_file = sprintf("Data/Map%03d.rxdata", map_id)
  unless pbRgssExists?(map_file)
    pbMessage(_INTL(
      "That destination uses map ID {1}, but\\n{2}\\nis missing.\\n\\n" \
      "Create the map in RPG Maker XP (or fix the map ID in your script / PBS), then save the project.",
      map_id,
      map_file
    ))
    return false
  end

  dir = pbNormalizeDoorFacing(facing)
  xi = x.to_i
  yi = y.to_i

  if se && !se.to_s.empty?
    pbSEPlay(se) rescue pbSEPlay("Door enter") rescue nil
  end

  run_transfer = proc {
    pbCancelVehicles(map_id) rescue pbCancelVehicles
    Followers.clear if defined?(Followers)
    $game_temp.player_new_map_id    = map_id
    $game_temp.player_new_x         = xi
    $game_temp.player_new_y         = yi
    $game_temp.player_new_direction = dir
    pbDismountBike rescue nil
    $scene.transfer_player if $scene.is_a?(Scene_Map)
  }

  if fade
    pbFadeOutIn(&run_transfer)
  else
    run_transfer.call
  end
  true
end

unless defined?(pbTransferToMapByName)
  alias pbTransferToMapByName pbDoorWarpTo
end
