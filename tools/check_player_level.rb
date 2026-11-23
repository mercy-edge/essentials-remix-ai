#!/usr/bin/env ruby
# Checks the internal player level (pbPLV / $player.plv).
# The mark is the highest level any Pokémon the player has ever owned.
# It never decreases. Run from the repo root: ruby tools/check_player_level.rb

require "English"

ROOT = File.expand_path("..", __dir__)
PLUGIN = File.join(ROOT, "Plugins", "PlayerLevel", "PlayerLevel.rb")
META = File.join(ROOT, "Plugins", "PlayerLevel", "meta.txt")

failures = []

def check(failures, name)
  yield
rescue StandardError => e
  failures << "#{name}: #{e.message}"
end

check(failures, "plugin files exist") do
  raise "missing #{PLUGIN}" unless File.file?(PLUGIN)
  raise "missing #{META}" unless File.file?(META)
  meta = File.read(META)
  raise "blank Link is not allowed" if meta.match?(/^\s*Link\s*=\s*$/i)
  raise "meta is missing Name" unless meta.include?("Name =")
  syntax = IO.popen(["ruby", "-c", PLUGIN], err: [:child, :out], &:read)
  raise syntax unless $CHILD_STATUS.success?
end

check(failures, "docs name pbPLV and $player.plv") do
  source = File.read(PLUGIN)
  ["pbPLV", "$player.plv", "pbPlayerLevel", "player_level", "def level=", "def exp=",
   "migrate_on_load!"].each do |token|
    raise "plugin source is missing #{token}" unless source.include?(token)
  end
end

# Stubs stand in for Essentials so the plugin can be loaded outside the game.
class Trainer
  attr_accessor :party

  def initialize(*)
    @party = []
  end
end

class Player < Trainer
end

class Pokemon
  attr_reader :level
  attr_accessor :pending_level

  def initialize(level)
    @level = level
  end

  def level=(value)
    @level = value.to_i
  end

  def exp=(value)
    @exp = value
    @level = @pending_level if @pending_level
  end
end

class PokemonBox
  def initialize
    @pokemon = []
  end

  def []=(index, value)
    @pokemon[index] = value
  end

  def each
    @pokemon.each { |pkmn| yield pkmn }
  end

  def silent_set(index, value)
    @pokemon[index] = value
  end
end

class PokemonStorage
  attr_reader :boxes

  def initialize
    @boxes = [PokemonBox.new]
  end
end

class DayCareSlotStub
  attr_accessor :pokemon
end

class DayCareStub
  attr_reader :slots

  def initialize
    @slots = [DayCareSlotStub.new, DayCareSlotStub.new]
  end
end

class GlobalStub
  attr_accessor :day_care
end

module SaveData
  def self.load_all_values(_save_data)
    @load_calls = @load_calls.to_i + 1
  end

  def self.load_calls
    @load_calls.to_i
  end
end

load PLUGIN

def boot_player
  $player = Player.new("Red", :TRAINER)
  $PokemonStorage = PokemonStorage.new
  $PokemonGlobal = GlobalStub.new
  $PokemonGlobal.day_care = DayCareStub.new
end

def assert_plv(expected)
  raise "pbPLV is #{pbPLV.inspect}, expected #{expected}" unless pbPLV == expected
  raise "pbPLV is not an Integer" unless pbPLV.is_a?(Integer)
  raise "$player.plv is #{ $player.plv.inspect }, expected #{expected}" unless $player.plv == expected
  unless $player.player_level == expected && pbPlayerLevel == expected
    raise "long names diverged from pbPLV (#{pbPlayerLevel.inspect} / #{$player.player_level.inspect})"
  end
end

check(failures, "new player starts at 0 and pbPLV matches $player.plv") do
  boot_player
  assert_plv(0)
  raise "party was not wrapped" unless $player.party.is_a?(PlayerLevel::PartyArray)
end

check(failures, "level set before ownership does not count; adding to the party does") do
  boot_player
  pkmn = Pokemon.new(1)
  pkmn.level = 12
  assert_plv(0)
  $player.party.push(pkmn)
  assert_plv(12)
end

check(failures, "pbPLV never decreases when a lower Pokémon is obtained or a level drops") do
  boot_player
  high = Pokemon.new(10)
  $player.party << high
  $player.party[$player.party.length] = Pokemon.new(4)
  assert_plv(10)
  high.level = 2
  assert_plv(10)
  $player.party.clear
  assert_plv(10)
end

check(failures, "level= and exp= update pbPLV for party, box, and daycare Pokémon only") do
  boot_player
  party_mon = Pokemon.new(5)
  $player.party.append(party_mon)
  assert_plv(5)
  party_mon.level = 9
  assert_plv(9)
  party_mon.pending_level = 11
  party_mon.exp = 500
  assert_plv(11)

  boxed = Pokemon.new(3)
  $PokemonStorage.boxes[0][0] = boxed
  assert_plv(11)
  boxed.pending_level = 16
  boxed.exp = 800
  assert_plv(16)

  daycare_mon = Pokemon.new(2)
  daycare_mon.level = 40
  assert_plv(16)
  $PokemonGlobal.day_care.slots[0].pokemon = daycare_mon
  daycare_mon.level = 18
  assert_plv(18)

  released = $player.party[0]
  $player.party.delete(released)
  released.level = 99
  released.pending_level = 100
  released.exp = 1
  assert_plv(18)

  wild = Pokemon.new(1)
  wild.level = 70
  wild.pending_level = 71
  wild.exp = 1
  assert_plv(18)

  npc_party = []
  npc_party.push(Pokemon.new(65))
  assert_plv(18)
end

check(failures, "replacing the party notes the new Pokémon and keeps the high-water mark") do
  boot_player
  $player.party.push(Pokemon.new(8))
  $player.party = [Pokemon.new(6), Pokemon.new(14)]
  assert_plv(14)
  raise "party= did not keep the noting array" unless $player.party.is_a?(PlayerLevel::PartyArray)
  $player.party = [Pokemon.new(1)]
  assert_plv(14)
end

check(failures, "save load initializes a missing mark and never lowers an existing one") do
  boot_player
  calls_before = SaveData.load_calls
  low = Pokemon.new(7)
  high = Pokemon.new(22)
  daycare = Pokemon.new(19)
  $player.instance_variable_set(:@party, [low, nil])
  $player.instance_variable_set(:@player_level, nil)
  $PokemonStorage.boxes[0].silent_set(0, high)
  $PokemonGlobal.day_care.slots[1].pokemon = daycare
  SaveData.load_all_values({})
  raise "load hook did not call the original load" unless SaveData.load_calls == calls_before + 1
  assert_plv(22)
  raise "loaded party was not wrapped" unless $player.party.is_a?(PlayerLevel::PartyArray)
  raise "loaded party lost a Pokémon" unless $player.party[0].equal?(low)
  raise "loaded party dropped an empty slot" unless $player.party[1].nil?

  $player.instance_variable_set(:@player_level, 40)
  $player.instance_variable_set(:@party, [Pokemon.new(3)])
  $PokemonStorage.boxes[0].silent_set(0, nil)
  $PokemonGlobal.day_care.slots[1].pokemon = nil
  SaveData.load_all_values({})
  assert_plv(40)

  $player.instance_variable_set(:@player_level, 4)
  $player.instance_variable_set(:@party, [Pokemon.new(9)])
  SaveData.load_all_values({})
  assert_plv(9)
end

check(failures, "pbPLV and $player.plv survive Marshal and still rise afterwards") do
  boot_player
  $player.party.push(Pokemon.new(13))
  loaded = Marshal.load(Marshal.dump($player))
  $player = loaded
  assert_plv(13)
  raise "saved party lost its noting array" unless $player.party.is_a?(PlayerLevel::PartyArray)
  $player.party.push(Pokemon.new(15))
  assert_plv(15)
end

check(failures, "event Script conditions can call pbPLV and $player.plv") do
  boot_player
  $player.party.push(Pokemon.new(10))
  raise "condition pbPLV >= 10 failed" unless eval("pbPLV >= 10")
  raise "condition $player.plv >= 10 failed" unless eval("$player.plv >= 10")
  raise "condition pbPlayerLevel >= 10 failed" unless eval("pbPlayerLevel >= 10")
  raise "lower condition should be false" if eval("pbPLV >= 11")
end

check(failures, "raise_to is a high-water mark") do
  raise "lowered" unless PlayerLevel.raise_to(10, 4) == 10
  raise "did not rise" unless PlayerLevel.raise_to(10, 12) == 12
  raise "nil current" unless PlayerLevel.raise_to(nil, 3) == 3
  raise "nil candidate" unless PlayerLevel.raise_to(5, nil) == 5
end

if failures.empty?
  puts "Player level check OK (pbPLV / $player.plv)"
else
  puts "PLAYER LEVEL CHECK FAILED:"
  failures.each { |failure| puts "  - #{failure}" }
  exit 1
end
