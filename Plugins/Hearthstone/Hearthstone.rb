#===============================================================================
# Hearthstone (key item)  -  teleport to bound overworld coordinates
#-------------------------------------------------------------------------------
# PBS: PBS/items.txt [HEARTHSTONE]  -  compile data after editing PBS.
#
# Stored in $PokemonGlobal.hearthstone_spot as [map_id, tile_x, tile_y, facing]
# Facing matches $game_player.direction (typically 2,4,6,8).
#
# pbBindHearthstoneToCurrentLocation   -  callable from NPC (innkeeper) dialogs
# pbGiveNewGameHearthstoneSilent        -  grants key item once (no fanfare); call after name entry
#
# Original bind: first time the player enters a map overworld spot with no bind yet,
# hearthstone_spot is set automatically (typically first step after Oak intro transfer).
#
# Blacks out toward hearthstone_spot instead of Pokémon Center/home when binding exists.
#
# Depends on Scripts loading before this plugin (alias pbStartOver).
#===============================================================================

if defined?(PokemonGlobalMetadata)
  class PokemonGlobalMetadata
    # [Integer map_id, Integer x, Integer y, Integer facing] or nil if never set
    attr_accessor :hearthstone_spot
    attr_accessor :hearthstone_new_game_item_given
  end
end

def pbHearthstoneValidDestination?(spot)
  return false if !spot || !spot.is_a?(Array)
  map_id = spot[0].to_i
  return false if map_id < 1 || !pbRgssExists?(sprintf("Data/Map%03d.rxdata", map_id))
  return false if spot[1].nil? || spot[2].nil?
  true
rescue StandardError
  false
end

def pbEnsureHearthstoneInitialBindFromFirstSpawn
  return if !$PokemonGlobal || !$game_map || !$game_player || !$player
  # Only auto-bind once: first map entry while still unset (captures spawn after Oak transfer).
  return if !$PokemonGlobal.hearthstone_spot.nil?

  # Scripted intro starts on INTRO_MAP_ID then transfers elsewhere; first :on_enter_map is still
  # the intro map  -  binding there sends Hearthstone into wrong tiles ("void"). Post-intro bind is explicit.
  if defined?(EssentialsRemixIntro) && EssentialsRemixIntro::USE_SCRIPTED_INTRO &&
     $game_map.map_id == EssentialsRemixIntro::INTRO_MAP_ID
    return
  end

  spot = [$game_map.map_id, $game_player.x, $game_player.y, $game_player.direction]
  return if !pbHearthstoneValidDestination?(spot)

  $PokemonGlobal.hearthstone_spot = spot
end

EventHandlers.add(:on_enter_map, :hearthstone_initial_bind_once,
  proc { |_old_map|
    pbEnsureHearthstoneInitialBindFromFirstSpawn rescue nil
  }
)

# Sets hearthstone destination without requiring the player to stand there (e.g. after scripted transfer).
def pbSetHearthstoneSpotExplicit(map_id, x, y, facing = 2)
  $PokemonGlobal = PokemonGlobalMetadata.new if !$PokemonGlobal
  spot = [map_id.to_i, x.to_i, y.to_i, facing.to_i]
  return false if !pbHearthstoneValidDestination?(spot)
  $PokemonGlobal.hearthstone_spot = spot
  true
end

def pbBindHearthstoneToCurrentLocation
  $PokemonGlobal = PokemonGlobalMetadata.new if !$PokemonGlobal
  spot = [$game_map.map_id, $game_player.x, $game_player.y, $game_player.direction]
  if !pbHearthstoneValidDestination?(spot)
    pbMessage(_INTL("You can't bind your Hearthstone here."))
    return false
  end
  $PokemonGlobal.hearthstone_spot = spot
  true
end

def pbGiveNewGameHearthstoneSilent
  return false if !$player
  $PokemonGlobal = PokemonGlobalMetadata.new if !$PokemonGlobal
  return false if $PokemonGlobal.hearthstone_new_game_item_given
  return false if !defined?(GameData::Item)
  item_id = nil
  begin
    item_id = :HEARTHSTONE
    item_id = nil if !GameData::Item.exists?(item_id)
  rescue StandardError
    item_id = nil
  end
  return false if !item_id
  ok = ($bag.has?(item_id) ) ? true : $bag.add(item_id, 1)
  return false unless ok
  $PokemonGlobal.hearthstone_new_game_item_given = true
  true
end

def pbHearthstoneCanUseFromField?
  return false if !$game_map
  return false if !$PokemonGlobal&.hearthstone_spot || !pbHearthstoneValidDestination?($PokemonGlobal.hearthstone_spot)
  return false if !$game_player.can_map_transfer_with_follower?
  true
rescue StandardError
  false
end

if defined?(ItemHandlers)
  ItemHandlers::UseText.add(:HEARTHSTONE, proc { |_item|
    next pbHearthstoneCanUseFromField? ? _INTL("Travel home") : _INTL("Use")
  })

  ItemHandlers::UseFromBag.add(:HEARTHSTONE, proc { |_item|
    $PokemonGlobal = PokemonGlobalMetadata.new if !$PokemonGlobal
    if !$game_player.can_map_transfer_with_follower?
      pbMessage(_INTL("It can't be used when you have someone with you."))
      next 0
    end
    unless pbHearthstoneValidDestination?($PokemonGlobal&.hearthstone_spot)
      pbMessage(_INTL("Your Hearthstone hasn't attuned anywhere yet.\nExplore a bit - or ask an innkeeper to set a resting place."))
      next 0
    end
    next 2
  })

  ItemHandlers::ConfirmUseInField.add(:HEARTHSTONE, proc { |_item|
    next false unless pbHearthstoneCanUseFromField?
    mapname = pbGetMapNameFromId($PokemonGlobal.hearthstone_spot[0])
    next pbConfirmMessage(_INTL("Warp to near {1}?", mapname))
  })

  ItemHandlers::UseInField.add(:HEARTHSTONE, proc { |_item|
    place = ($PokemonGlobal && $PokemonGlobal.hearthstone_spot) ? $PokemonGlobal.hearthstone_spot : nil
    if !pbHearthstoneValidDestination?(place)
      pbMessage(_INTL("Can't use it here yet."))
      next false
    end
    if !$game_player.can_map_transfer_with_follower?
      pbMessage(_INTL("It can't be used when you have someone with you."))
      next false
    end
    pbToneChangeAll(Tone.new(-255, -255, -255, 0), 5) rescue nil
    Graphics.update
    Input.update
    pbSEPlay("Battle jump") rescue pbSEPlay("Fly") rescue nil
    8.times do
      Graphics.update
      Input.update
    end
    pbFadeOutIn do
      pbSEPlay("Heal machine") rescue pbSEPlay("Elevator") rescue nil
      pbWait(6)
      pbToneChangeAll(Tone.new(0, 0, 0, 0), 10) rescue nil
      pbCancelVehicles rescue nil
      Followers.clear if defined?(Followers)
      $game_temp.player_new_map_id    = place[0]
      $game_temp.player_new_x        = place[1]
      $game_temp.player_new_y        = place[2]
      $game_temp.player_new_direction = place[3] || 2
      pbDismountBike rescue nil
      $scene.transfer_player if $scene.is_a?(Scene_Map)
      $game_map&.autoplay
      $game_map&.refresh
    end
    next true
  })
end

#-------------------------------------------------------------------------------
# Blackout routing (wraps Essentials pbStartOver)
#-------------------------------------------------------------------------------
def pbUseHearthstoneForBlackout?(gameover)
  return nil if !$PokemonGlobal
  spot = $PokemonGlobal.hearthstone_spot
  return nil if !spot || spot.length < 4
  return nil if !pbHearthstoneValidDestination?(spot)
  spot
rescue StandardError
  nil
end

def pbTeleportPlayerToHearthstoneBlackout(place, gameover)
  return if !pbHearthstoneValidDestination?(place)

  $stats.blacked_out_count += 1
  $player.heal_party
  if gameover
    pbMessage("\\w[]\\wm\\c[8]\\l[3]" +
              _INTL("After the defeat, warmth guides you toward the place your Hearthstone remembers..."))
  else
    pbMessage("\\w[]\\wm\\c[8]\\l[3]" +
              _INTL("You stumble back toward warmth, fading back to familiar ground..."))
  end

  pbToneChangeAll(Tone.new(-255, -255, -255, 0), 12) rescue nil
  Graphics.update
  Input.update
  pbSEPlay("Flying cry") rescue pbSEPlay("Fly") rescue nil
  pbWait(8)
  pbCancelVehicles
  Followers.clear if defined?(Followers)
  $game_switches[Settings::STARTING_OVER_SWITCH] = true
  $game_temp.player_new_map_id    = place[0]
  $game_temp.player_new_x         = place[1]
  $game_temp.player_new_y         = place[2]
  $game_temp.player_new_direction = place[3] || 2
  pbDismountBike rescue nil
  $scene.transfer_player if $scene.is_a?(Scene_Map)
  $game_map&.autoplay
  $game_map&.refresh
  pbEraseEscapePoint rescue nil
  pbToneChangeAll(Tone.new(0, 0, 0, 0), 10) rescue nil
end

alias hearthstone_original_pbStartOver pbStartOver

def pbStartOver(gameover = false)
  # Bug Contest / Safari: keep vanilla behavior entirely
  if pbInBugContest?
    return hearthstone_original_pbStartOver(gameover)
  end
  hs = pbUseHearthstoneForBlackout?(gameover)
  if hs
    pbTeleportPlayerToHearthstoneBlackout(hs, gameover)
    return
  end
  hearthstone_original_pbStartOver(gameover)
end

#-------------------------------------------------------------------------------
# Innkeeper NPC  -  Script line (single line if possible): pbInnkeeperInteract
# Or: NorthshireAbbeyEvents.run(:innkeeper) when that handler skips map gating.
#-------------------------------------------------------------------------------
# Same healing rules as Pokémon Center (party vs stored per Settings), registers last heal spot.
# No screen fade  -  Nurse Joy–style overworld heal (optional SE + wait only).
def pbHealPartyLikePokemonCenter
  pbSEPlay("Heal machine") rescue pbSEPlay("Elevator") rescue nil
  pbWait(16)
  if Settings::HEAL_STORED_POKEMON
    $player.heal_party
  else
    pbEachPokemon { |pkmn, _box| pkmn.heal }
  end
  pbSetPokemonCenter
  pbToneChangeAll(Tone.new(0, 0, 0, 0), 8) rescue nil
end

def pbInnkeeperInteract
  pbMessage(_INTL("Welcome. Need a bed for your stone - or a tune-up for your partners?"))
  cmd = pbShowCommands(nil,
                       [_INTL("Bind Hearthstone here."), _INTL("Heal my Pokémon."), _INTL("No thanks.")],
                       3)
  return if cmd.nil? || cmd == 2

  if cmd == 0
    pbMessage(_INTL("Will you bind your \\c[1]Hearthstone\\c[0] here?\nYou'll return when you're knocked out - or when you channel it from the Bag."))
    sub = pbShowCommands(nil, [_INTL("Yes - this is home."), _INTL("Not now.")], 2)
    return unless sub && sub.zero?
    unless pbBindHearthstoneToCurrentLocation
      return
    end
    pbMessage(_INTL("There. Your hearthstone remembers this place warmly."))
    return
  end

  # Heal branch (Pokémon Center–style)
  pbHealPartyLikePokemonCenter
  pbMessage(_INTL("We hope to see you again!"))
end
