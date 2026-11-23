#===============================================================================
# Player level (internal)
#-------------------------------------------------------------------------------
# High-water mark of the highest level any Pokémon the player has ever owned
# has reached. It is saved on the player and never decreases.
#
# Read it from scripts or event Script conditions with any of:
#   pbPLV
#   pbPlayerLevel
#   $player.plv
#   $player.player_level
# Example condition: pbPLV >= 10
#
# Updated from two hooks, not from scattered call sites:
#   1. Pokemon#level= and Pokemon#exp= when that Pokémon is currently in the
#      party, PC, or daycare (battle Exp, Rare Candy, Exp Candy, daycare steps,
#      debug edits, and any other setter).
#   2. Adding a Pokémon to the party or a PC box (catch, gift, trade-in, egg,
#      hatch result, withdraw, deposit into storage).
#===============================================================================

module PlayerLevel
  def self.noting?
    @suppress_depth.to_i <= 0 && !@noting_level
  end

  def self.suppress_notes
    @suppress_depth = @suppress_depth.to_i + 1
    yield
  ensure
    @suppress_depth = @suppress_depth.to_i - 1
  end

  # @param current [Integer, nil]
  # @param candidate [Integer, nil]
  # @return [Integer] the higher of the two, treating an unset current as 0
  def self.raise_to(current, candidate)
    base = (current.is_a?(Integer) && current > 0) ? current : 0
    level = candidate.is_a?(Integer) ? candidate : 0
    return base if level <= base
    level
  end

  def self.apply_high_water!(player, candidate)
    return 0 if !player
    updated = raise_to(player.instance_variable_get(:@player_level), candidate)
    player.instance_variable_set(:@player_level, updated)
    updated
  end

  def self.note_pokemon(pkmn)
    return if !noting?
    return if !$player || !pkmn.is_a?(Pokemon)
    @noting_level = true
    begin
      level = pkmn.level
    ensure
      @noting_level = false
    end
    return if !level.is_a?(Integer)
    apply_high_water!($player, level)
  end

  def self.note_if_owned(pkmn)
    return if !owned?(pkmn)
    note_pokemon(pkmn)
  end

  def self.owned?(pkmn)
    return false if !$player || !pkmn.is_a?(Pokemon)
    if $player.party
      $player.party.each { |other| return true if other.equal?(pkmn) }
    end
    each_stored_pokemon { |other| return true if other.equal?(pkmn) }
    each_daycare_pokemon { |other| return true if other.equal?(pkmn) }
    false
  end

  def self.max_owned_level
    max = 0
    if $player && $player.party
      $player.party.each do |pkmn|
        next if !pkmn.is_a?(Pokemon)
        max = raise_to(max, pkmn.level)
      end
    end
    each_stored_pokemon { |pkmn| max = raise_to(max, pkmn.level) }
    each_daycare_pokemon { |pkmn| max = raise_to(max, pkmn.level) }
    max
  end

  # Old saves have no @player_level. On every load, keep the saved mark and
  # raise it to the highest level currently in the party, PC, or daycare.
  # A released Pokémon's old level stays, because this never writes a lower value.
  def self.migrate_on_load!
    return if !$player
    apply_high_water!($player, max_owned_level)
    return if $player.party.is_a?(PartyArray)
    $player.instance_variable_set(:@party, copy_party($player.party))
  end

  def self.copy_party(party)
    return party if party.is_a?(PartyArray)
    wrapped = PartyArray.new
    if party
      suppress_notes do
        party.each { |pkmn| wrapped.push(pkmn) }
      end
    end
    wrapped
  end

  def self.each_stored_pokemon
    return if !defined?($PokemonStorage)
    storage = $PokemonStorage
    return if !storage || !storage.respond_to?(:boxes) || !storage.boxes
    storage.boxes.each do |box|
      next if !box || !box.respond_to?(:each)
      box.each { |pkmn| yield pkmn if pkmn.is_a?(Pokemon) }
    end
  end

  def self.each_daycare_pokemon
    return if !defined?($PokemonGlobal)
    global = $PokemonGlobal
    return if !global || !global.respond_to?(:day_care)
    day_care = global.day_care
    return if !day_care || !day_care.respond_to?(:slots) || !day_care.slots
    day_care.slots.each do |slot|
      next if !slot || !slot.respond_to?(:pokemon)
      yield slot.pokemon if slot.pokemon.is_a?(Pokemon)
    end
  end

  # Player's party only. NPC parties stay plain Arrays, so their Pokémon
  # never move this mark.
  class PartyArray < Array
    def []=(*args)
      result = super
      if PlayerLevel.noting?
        if args.length > 2 && args.last.is_a?(Array)
          args.last.each { |entry| PlayerLevel.note_pokemon(entry) }
        else
          PlayerLevel.note_pokemon(args.last)
        end
      end
      result
    end

    def push(*values)
      super
      note_added(values)
      self
    end

    def <<(value)
      super
      note_added([value])
      self
    end

    def unshift(*values)
      super
      note_added(values)
      self
    end

    def insert(index, *values)
      super
      note_added(values)
      self
    end

    def concat(*others)
      super
      others.each { |other| note_added(other) }
      self
    end

    def replace(other)
      super
      note_added(other)
      self
    end

    # Array#append and Array#prepend alias the original methods, so overriding
    # push/unshift does not redirect them. Define both explicitly.
    def append(*values)
      push(*values)
    end

    def prepend(*values)
      unshift(*values)
    end

    private

    def note_added(values)
      return if !PlayerLevel.noting? || !values
      values.each { |value| PlayerLevel.note_pokemon(value) }
    end
  end
end

#-------------------------------------------------------------------------------
# API: pbPLV / pbPlayerLevel / $player.plv / $player.player_level
#-------------------------------------------------------------------------------
class Player < Trainer
  unless method_defined?(:player_level_initialize)
    alias_method :player_level_initialize, :initialize
  end

  def initialize(*args)
    player_level_initialize(*args)
    @player_level = 0 if !@player_level.is_a?(Integer)
    @party = PlayerLevel.copy_party(@party)
  end

  # @return [Integer] highest level any owned Pokémon has ever reached
  def player_level
    value = @player_level
    return 0 if !value.is_a?(Integer) || value < 0
    value
  end
  alias_method :plv, :player_level

  def party=(value)
    @party = PlayerLevel.copy_party(value)
    return if !@party
    @party.each { |pkmn| PlayerLevel.note_pokemon(pkmn) }
  end
end

def pbPlayerLevel
  return 0 if !$player
  $player.player_level
end

# Short handle for scripts and event Script conditions, e.g. pbPLV >= 10.
def pbPLV
  pbPlayerLevel
end

#-------------------------------------------------------------------------------
# Level and Exp changes on a Pokémon the player currently holds.
#-------------------------------------------------------------------------------
class Pokemon
  unless method_defined?(:player_level_set_level)
    alias_method :player_level_set_level, :level=
  end

  def level=(value)
    player_level_set_level(value)
    PlayerLevel.note_if_owned(self)
  end

  unless method_defined?(:player_level_set_exp)
    alias_method :player_level_set_exp, :exp=
  end

  def exp=(value)
    player_level_set_exp(value)
    PlayerLevel.note_if_owned(self)
  end
end

#-------------------------------------------------------------------------------
# PC box deposits (pbStoreCaught, moves, and direct storage writes).
#-------------------------------------------------------------------------------
class PokemonBox
  unless method_defined?(:player_level_box_assign)
    alias_method :player_level_box_assign, :[]=
  end

  def []=(index, value)
    player_level_box_assign(index, value)
    PlayerLevel.note_pokemon(value)
  end
end

#-------------------------------------------------------------------------------
# Existing saves: fill @player_level after the player, PC, and daycare load.
#-------------------------------------------------------------------------------
module SaveData
  class << self
    unless method_defined?(:player_level_load_all_values)
      alias_method :player_level_load_all_values, :load_all_values
    end
  end

  def self.load_all_values(save_data)
    player_level_load_all_values(save_data)
    PlayerLevel.migrate_on_load!
  end
end
