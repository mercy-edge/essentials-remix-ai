#===============================================================================
# Flight Paths — WoW-style flight masters
#-------------------------------------------------------------------------------
# Talk to a flight master to discover that node. Choose another discovered node
# to fly there (standard bird field-move animation + Fly SE + warp).
#
# Map event Script (one line):
#   FlightPaths.talk(:goldshire)
#   FlightPaths.talk(:eastvale)
#
# Landing tiles are one step in front of the master (facing toward them).
# Unlock data: $PokemonGlobal.flight_paths_unlocked  (Hash of node_id => true)
#===============================================================================

if defined?(PokemonGlobalMetadata)
  class PokemonGlobalMetadata
    # { :goldshire => true, :eastvale => true, ... }
    attr_accessor :flight_paths_unlocked
  end
end

module FlightPaths
  # Species used for the Fly field-move banner when the party has no flyer.
  DISPLAY_BIRD = :PIDGEOT

  # node_id => {
  #   name: display name,
  #   map_id: Integer,
  #   master_x:, master_y:  — flight master event tile
  #   land_x:, land_y:      — player stands here after flight (in front of master)
  #   facing:               — direction after landing (face the master)
  # }
  NODES = {
    goldshire: {
      name:     'Goldshire',
      map_id:   77,
      master_x: 10,
      master_y: 8,
      land_x:   10,
      land_y:   9,
      facing:   8   # look north at master
    },
    eastvale: {
      name:     'Eastvale Logging Camp',
      map_id:   81,
      master_x: 14,
      master_y: 8,
      land_x:   14,
      land_y:   9,
      facing:   8
    }
  }.freeze

  module_function

  def ensure_store!
    $PokemonGlobal = PokemonGlobalMetadata.new if !$PokemonGlobal
    $PokemonGlobal.flight_paths_unlocked ||= {}
  end

  def unlocked?(node_id)
    ensure_store!
    h = $PokemonGlobal.flight_paths_unlocked
    id = node_id.to_sym
    h[id] == true || h[id.to_s] == true
  end

  def unlock!(node_id)
    ensure_store!
    id = node_id.to_sym
    return false unless NODES[id]
    return false if unlocked?(id)

    $PokemonGlobal.flight_paths_unlocked[id] = true
    $PokemonGlobal.flight_paths_unlocked.delete(id.to_s)
    true
  end

  def node(node_id)
    NODES[node_id.to_sym]
  end

  def unlocked_nodes
    ensure_store!
    NODES.keys.select { |id| unlocked?(id) }
  end

  def destinations_from(from_id)
    unlocked_nodes.reject { |id| id == from_id.to_sym }
  end

  # Always use Pidgeot for the Fly field-move banner.
  def animation_bird
    begin
      return Pokemon.new(DISPLAY_BIRD, 50)
    rescue StandardError
      begin
        return Pokemon.new(:PIDGEY, 20)
      rescue StandardError
        return nil
      end
    end
  end

  def play_flight_animation
    bird = animation_bird
    if bird && defined?(pbHiddenMoveAnimation)
      pbHiddenMoveAnimation(bird)
    else
      name = $player ? $player.name : _INTL('You')
      pbMessage(_INTL('{1} takes flight!', name))
    end
  end

  def can_transfer?
    return false if !$game_player
    return true if !$game_player.respond_to?(:can_map_transfer_with_follower?)
    $game_player.can_map_transfer_with_follower?
  end

  def transfer_to_node!(dest_id)
    dest = node(dest_id)
    return false unless dest

    path = sprintf('Data/Map%03d.rxdata', dest[:map_id])
    unless pbRgssExists?(path) || FileTest.exist?(path)
      pbMessage(_INTL('That flight path is not ready yet.'))
      return false
    end

    play_flight_animation
    pbFadeOutIn do
      pbSEPlay('Fly') rescue nil
      pbCancelVehicles rescue nil
      Followers.clear if defined?(Followers)
      $game_temp.player_new_map_id    = dest[:map_id]
      $game_temp.player_new_x         = dest[:land_x]
      $game_temp.player_new_y         = dest[:land_y]
      $game_temp.player_new_direction = dest[:facing] || 2
      pbDismountBike rescue nil
      $scene.transfer_player if $scene.is_a?(Scene_Map)
      $game_map.autoplay if $game_map
      $game_map.refresh if $game_map
      pbWait(0.25) if defined?(pbWait)
    end
    true
  end

  # Main NPC entry: discover this node, then offer flights to other unlocked nodes.
  def talk(node_id)
    id = node_id.to_sym
    data = node(id)
    unless data
      pbMessage(_INTL('FlightPaths: unknown node {1}.', node_id))
      return
    end

    first_time = unlock!(id)
    if first_time
      pbMessage(_INTL("Flight path discovered:\\n\\c[1]{1}\\c[0]!", data[:name]))
    else
      pbMessage(_INTL("Where would you like to fly?"))
    end

    dests = destinations_from(id)
    if dests.empty?
      pbMessage(_INTL("You haven't discovered any other flight paths yet.\\nSeek out more Flight Masters."))
      return
    end

    unless can_transfer?
      pbMessage(_INTL("You can't fly with someone with you."))
      return
    end

    names = dests.map { |d| node(d)[:name] }
    names.push(_INTL('Never mind.'))
    cmd = pbShowCommands(nil, names, names.length - 1)
    return if cmd < 0 || cmd >= dests.length

    dest_id = dests[cmd]
    dest = node(dest_id)
    unless pbConfirmMessage(_INTL('Fly to {1}?', dest[:name]))
      return
    end

    transfer_to_node!(dest_id)
  end

  # Debug helper: unlock every registered node.
  def unlock_all!
    NODES.each_key { |id| unlock!(id) }
  end
end

# Debug → unlock all flight paths / fly test
MenuHandlers.add(:debug_menu, :flight_paths_unlock_all, {
  'name'        => _INTL('Unlock all flight paths'),
  'parent'      => :field_menu,
  'description' => _INTL('Mark every FlightPaths node as discovered.'),
  'effect'      => proc {
    FlightPaths.unlock_all!
    pbMessage(_INTL('All flight paths unlocked.'))
  }
})
