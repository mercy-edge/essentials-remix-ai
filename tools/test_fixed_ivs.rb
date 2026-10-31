#!/usr/bin/env ruby
# Checks Oak's lab starter IVs (all 5) and wild IVs (all 0), including that
# stats are recalculated with the game's own calcHP/calcStat/calc_stats.
# Does not boot the game or run map events.
ROOT = File.expand_path("..", __dir__)

failures = []

def check(failures, label)
  yield
rescue StandardError => e
  failures << "#{label}: #{e.message}"
end

module Settings
  DISABLE_IVS_AND_EVS = false
  SHINY_WILD_POKEMON_SWITCH = 31
  LEGENDARIES_HAVE_SOME_PERFECT_IVS = false
end

module GameData
  class Stat
    attr_reader :id

    IDS = [:HP, :ATTACK, :DEFENSE, :SPECIAL_ATTACK, :SPECIAL_DEFENSE, :SPEED].freeze

    def initialize(id)
      @id = id
    end

    def self.each_main
      IDS.each { |id| yield new(id) }
    end
  end

  class Species
    def self.get(id)
      sym = id.to_sym
      obj = Object.new
      obj.define_singleton_method(:id) { sym }
      obj.define_singleton_method(:species) { sym }
      obj
    end

    def self.exists?(id)
      true
    end
  end

  module GrowthRate
    def self.max_level
      100
    end
  end
end

module EventHandlers
  def self.added
    @added ||= Hash.new { |h, k| h[k] = [] }
  end

  def self.add(event, key, pr)
    added[event] << [key, pr]
  end

  def self.trigger(event, *args)
    added[event].each { |_key, pr| pr.call(*args) }
  end

  def self.keys_for(event)
    added[event].map(&:first)
  end
end

class FakeMap
  attr_accessor :map_id

  def metadata
    nil
  end
end

class FakeNature
  def initialize(changes)
    @changes = changes
  end

  def stat_changes
    @changes
  end
end

class Pokemon
  def self.===(other)
    other.is_a?(Pokemon) || other.is_a?(TestPokemon)
  end
end

class TestPokemon
  IV_STAT_LIMIT = 31
  attr_accessor :iv, :ev, :ivMaxed, :hp, :totalhp
  attr_accessor :attack, :defense, :spatk, :spdef, :speed
  attr_accessor :level, :species, :base_stats, :nature_for_stats
  attr_accessor :obtain_method, :item, :ability_index, :ability, :gender
  attr_accessor :shiny, :super_shiny, :nature, :happiness, :name, :poke_ball, :form
  attr_accessor :egg

  def initialize
    @iv = {}
    @ev = {}
    @ivMaxed = {}
    @moves = []
    @hp = 1
    @totalhp = 1
    @egg = false
    GameData::Stat.each_main do |s|
      @iv[s.id] = 0
      @ev[s.id] = 0
    end
  end

  def egg?
    @egg
  end

  def baseStats
    @base_stats
  end

  def moves
    @moves
  end

  def reset_moves
  end

  def learn_move(move)
    @moves << move
  end

  def form_simple=(value)
    @form = value
  end

  def ivs
    GameData::Stat::IDS.map { |id| @iv[id] }
  end
end

pokemon_src = File.read(File.join(ROOT, "Scripts/274_Pokemon.rb"))
calc_start = pokemon_src.index("  def calcIV")
calc_finish = pokemon_src.index("  # Pokémon creation", calc_start)
raise "could not slice stat formulas" unless calc_start && calc_finish

TestPokemon.class_eval(pokemon_src[calc_start...calc_finish])

def _INTL(msg, *_args)
  msg
end

$game_switches = {}
$game_map = FakeMap.new
$game_map.map_id = 4
$player = Object.new

load File.join(ROOT, "Scripts/260_Overworld_EncounterModifiers.rb")
load File.join(ROOT, "Scripts/364_Utilities_Pokemon.rb")

CHARMANDER = {
  :HP => 39, :ATTACK => 52, :DEFENSE => 43,
  :SPEED => 65, :SPECIAL_ATTACK => 60, :SPECIAL_DEFENSE => 50
}.freeze
FLAT = {
  :HP => 100, :ATTACK => 100, :DEFENSE => 100,
  :SPEED => 100, :SPECIAL_ATTACK => 100, :SPECIAL_DEFENSE => 100
}.freeze

def make_pokemon(species, level, bases, iv)
  pkmn = TestPokemon.new
  pkmn.species = species
  pkmn.level = level
  pkmn.base_stats = bases
  GameData::Stat.each_main { |s| pkmn.iv[s.id] = iv }
  pkmn.calc_stats
  pkmn
end

# ---------------------------------------------------------------------------
check(failures, "stat formulas were not edited") do
  forbidden = [
    "Scripts/274_Pokemon.rb",
    "Scripts/137_Trainer.rb",
    "Scripts/248_Overworld_DayCare.rb"
  ]
  diff = `git -C #{ROOT} diff --name-only HEAD`.split("\n")
  hit = forbidden & diff
  raise "unexpected edits: #{hit.join(', ')}" unless hit.empty?
  raise "IV randomization removed from Pokemon#initialize" unless pokemon_src.include?("@iv[s.id]       = rand(IV_STAT_LIMIT + 1)")
  raise "DISABLE_IVS_AND_EVS is on, so IV edits would not change stats" unless File.read(File.join(ROOT, "Scripts/001_Settings.rb")).include?("DISABLE_IVS_AND_EVS                 = false")
end

check(failures, "trainer and egg IV code left in place") do
  trainer = File.read(File.join(ROOT, "Scripts/137_Trainer.rb"))
  daycare = File.read(File.join(ROOT, "Scripts/248_Overworld_DayCare.rb"))
  raise "trainer IV formula missing" unless trainer.include?("pkmn.iv[s.id] = [pkmn_data[:level] / 2, Pokemon::IV_STAT_LIMIT].min")
  raise "trainer file calls the wild IV helper" if trainer.include?("pbApplyWildPokemonIVs") || trainer.include?("pbSetAllIVs")
  raise "egg IV inheritance missing" unless daycare.include?("egg.iv[stat] = new_stat")
  raise "daycare calls the wild IV helper" if daycare.include?("pbApplyWildPokemonIVs") || daycare.include?("pbSetAllIVs")
end

check(failures, "Oak lab starters get 5 IVs and recalculated stats") do
  $game_map.map_id = 4
  pkmn = make_pokemon(:CHARMANDER, 5, CHARMANDER, 31)
  raise "setup HP #{pkmn.totalhp}" unless pkmn.totalhp == 20
  pkmn.nature_for_stats = FakeNature.new([[:ATTACK, 10]])
  pbApplyOakLabStarterIVs(pkmn)
  raise "IVs #{pkmn.ivs.inspect}" unless pkmn.ivs == [5, 5, 5, 5, 5, 5]
  # +10% Attack nature, EV 0. HP/Def/Spe/SpA/SpD are neutral.
  raise "HP #{pkmn.totalhp} hp #{pkmn.hp}" unless pkmn.totalhp == 19 && pkmn.hp == 19
  raise "Atk #{pkmn.attack}" unless pkmn.attack == 11
  raise "Def #{pkmn.defense}" unless pkmn.defense == 9
  raise "SpA #{pkmn.spatk}" unless pkmn.spatk == 11
  raise "SpD #{pkmn.spdef}" unless pkmn.spdef == 10
  raise "Spe #{pkmn.speed}" unless pkmn.speed == 11

  [:BULBASAUR, :SQUIRTLE].each do |species|
    other = make_pokemon(species, 5, CHARMANDER, 31)
    pbApplyOakLabStarterIVs(other)
    raise "#{species} IVs #{other.ivs.inspect}" unless other.ivs == [5, 5, 5, 5, 5, 5]
    raise "#{species} HP stayed at the IV-31 value" unless other.totalhp == 19
  end
end

check(failures, "other gifts, eggs, and off-map starters keep their IVs") do
  $game_map.map_id = 4
  pikachu = make_pokemon(:PIKACHU, 5, FLAT, 31)
  pbApplyOakLabStarterIVs(pikachu)
  raise "Pikachu IVs changed" unless pikachu.ivs == [31, 31, 31, 31, 31, 31]

  grown = make_pokemon(:CHARMANDER, 10, CHARMANDER, 20)
  before = grown.totalhp
  pbApplyOakLabStarterIVs(grown)
  raise "level 10 Charmander IVs changed" unless grown.ivs == [20, 20, 20, 20, 20, 20]
  raise "level 10 Charmander stats changed" unless grown.totalhp == before

  level1 = make_pokemon(:CHARMANDER, 1, CHARMANDER, 12)
  pbApplyOakLabStarterIVs(level1)
  raise "level 1 Charmander IVs changed" unless level1.ivs == [12, 12, 12, 12, 12, 12]

  $game_map.map_id = 3
  celebi = make_pokemon(:CELEBI, 20, FLAT, 18)
  pbApplyOakLabStarterIVs(celebi)
  raise "map 3 gift IVs changed" unless celebi.ivs == [18, 18, 18, 18, 18, 18]

  $game_map.map_id = 26
  farfetchd = make_pokemon(:FARFETCHD, 20, FLAT, 7)
  pbApplyOakLabStarterIVs(farfetchd)
  raise "map 26 gift IVs changed" unless farfetchd.ivs == [7, 7, 7, 7, 7, 7]

  $game_map.map_id = 4
  egg = make_pokemon(:CHARMANDER, 5, CHARMANDER, 31)
  egg.egg = true
  pbApplyOakLabStarterIVs(egg)
  raise "egg IVs changed" unless egg.ivs == [31, 31, 31, 31, 31, 31]

  utilities = File.read(File.join(ROOT, "Scripts/364_Utilities_Pokemon.rb"))
  add = utilities[/^def pbAddPokemon\(.*?^end/m]
  silent = utilities[/^def pbAddPokemonSilent\(.*?^end/m]
  foreign = utilities[/^def pbAddForeignPokemon\(.*?^end/m]
  egg_m = utilities[/^def pbGenerateEgg\(.*?^end/m]
  raise "pbAddPokemon does not apply starter IVs" unless add.include?("pbApplyOakLabStarterIVs")
  raise "pbAddPokemon applies starter IVs before the Pokémon exists" unless add.index("Pokemon.new") < add.index("pbApplyOakLabStarterIVs")
  raise "silent gift path applies starter IVs" if silent.include?("pbApplyOakLabStarterIVs")
  raise "foreign gift path applies starter IVs" if foreign.include?("pbApplyOakLabStarterIVs")
  raise "egg path applies starter IVs" if egg_m.include?("pbApplyOakLabStarterIVs")
end

check(failures, "wild generation ends at 0 IVs even if a later handler rerolls") do
  pkmn = make_pokemon(:MEW, 30, FLAT, 31)
  raise "setup" unless pkmn.totalhp == 109
  EventHandlers.trigger(:on_wild_pokemon_created, pkmn)
  raise "hook left IVs #{pkmn.ivs.inspect}" unless pkmn.ivs == [0, 0, 0, 0, 0, 0]
  raise "hook did not recalculate HP (#{pkmn.totalhp})" unless pkmn.totalhp == 100 && pkmn.hp == 100

  EventHandlers.add(:on_wild_pokemon_created, :test_perfect_ivs,
    proc { |mon|
      GameData::Stat.each_main { |s| mon.iv[s.id] = 31 }
      mon.calc_stats
    }
  )
  EventHandlers.trigger(:on_wild_pokemon_created, pkmn)
  raise "late handler should have run" unless pkmn.ivs == [31, 31, 31, 31, 31, 31]
  pbApplyWildPokemonIVs(pkmn)
  raise "post-handler lock failed #{pkmn.ivs.inspect} hp #{pkmn.totalhp}" unless pkmn.ivs == [0, 0, 0, 0, 0, 0] && pkmn.totalhp == 100

  keys = EventHandlers.keys_for(:on_wild_pokemon_created)
  raise "zero handler is not after the level scaler: #{keys.inspect}" unless keys.index(:zero_wild_ivs) > keys.index(:level_depends_on_party)
  modifiers = File.read(File.join(ROOT, "Scripts/260_Overworld_EncounterModifiers.rb"))
  raise "safari/legendary reroll still present" if modifiers.include?("IV_STAT_LIMIT") || modifiers.include?("pbInSafari?")
  gen = File.read(File.join(ROOT, "Scripts/259_Overworld_WildEncounters.rb"))
  body = gen[/^def pbGenerateWildPokemon\(.*?^end/m]
  raise "pbGenerateWildPokemon missing" unless body
  raise "IV lock is not after encounter handlers" unless body.index("EventHandlers.trigger") < body.index("pbApplyWildPokemonIVs")
end

check(failures, "WildBattle.generate_foes forces 0 IVs on generated and prebuilt foes") do
  generated = 0
  define_method_missing = proc {}
  Object.send(:define_method, :pbGenerateWildPokemon) do |species, level, _roamer = false|
    generated += 1
    make_pokemon(species, level, FLAT, 31)
  end

  battle_src = File.read(File.join(ROOT, "Scripts/257_Overworld_BattleStarting.rb"))
  start = battle_src.index("  def self.generate_foes(*args)")
  marker = "    return ret\n  end"
  finish = battle_src.index(marker, start)
  raise "generate_foes not found" unless start && finish
  WildBattle = Class.new
  WildBattle.class_eval(battle_src[start, finish + marker.length - start])

  foes = WildBattle.generate_foes(:MEW, 30)
  raise "species/level did not generate" unless generated == 1
  raise "generated foe IVs #{foes[0].ivs.inspect} hp #{foes[0].totalhp}" unless foes[0].ivs == [0, 0, 0, 0, 0, 0] && foes[0].totalhp == 100

  prebuilt = make_pokemon(:DEOXYS, 30, FLAT, 31)
  array_foe_calls = generated
  foes = WildBattle.generate_foes(prebuilt, [:DEOXYS, 30])
  raise "prebuilt foe was regenerated" unless generated == array_foe_calls + 1
  raise "prebuilt IVs #{foes[0].ivs.inspect} hp #{foes[0].totalhp}" unless foes[0].ivs == [0, 0, 0, 0, 0, 0] && foes[0].totalhp == 100 && foes[0].hp == 100
  raise "array foe IVs #{foes[1].ivs.inspect}" unless foes[1].ivs == [0, 0, 0, 0, 0, 0]
  define_method_missing
end

check(failures, "Wild 2v3 event Pokémon ignore :iv and recalculate after EVs") do
  def Pokemon.new(species, level, _owner = nil, _with_moves = true)
    pkmn = TestPokemon.new
    pkmn.species = species
    pkmn.level = level
    pkmn.base_stats = FLAT
    GameData::Stat.each_main { |s| pkmn.iv[s.id] = 31 }
    pkmn.calc_stats
    pkmn
  end

  plugin = File.read(File.join(ROOT, "Plugins/Wild2v3Battle/Wild2v3Battle.rb"))
  start = plugin.index("  def create_event_pokemon")
  marker = "    return pkmn\n  end"
  finish = plugin.index(marker, start)
  raise "create_event_pokemon not found" unless start && finish
  method_src = plugin[start, finish + marker.length - start]
  raise "create_event_pokemon still applies :iv" if method_src.include?("options[:iv]")
  module Wild2v3Battle
  end
  Wild2v3Battle.module_eval(method_src)
  Wild2v3Battle.send(:module_function, :create_event_pokemon)

  ivs = {}
  GameData::Stat::IDS.each { |id| ivs[id] = 31 }
  pkmn = Wild2v3Battle.create_event_pokemon(:GYARADOS, 35, {
    :iv => ivs,
    :ev => { :HP => 252 },
    :ability => :INTIMIDATE
  })
  raise "IVs #{pkmn.ivs.inspect}" unless pkmn.ivs == [0, 0, 0, 0, 0, 0]
  raise "EV was dropped" unless pkmn.ev[:HP] == 252
  raise "ability dropped" unless pkmn.ability == :INTIMIDATE
  # Level 35, base 100, IV 0, HP EV 252 -> 137. Attack stays the IV-0 value 75
  # (IV 31 would be 85; ignoring the EV would make HP 115).
  raise "HP #{pkmn.totalhp} hp #{pkmn.hp}" unless pkmn.totalhp == 137 && pkmn.hp == 137
  raise "Atk #{pkmn.attack}" unless pkmn.attack == 75
end

check(failures, "bug contest contestants are zeroed before the HP roll") do
  contest = File.read(File.join(ROOT, "Scripts/340_BugContest.rb"))
  snippet = contest[/pokemon = Pokemon\.new\(enc\[0\], enc\[1\]\).*?pbBugContestScore/m]
  raise "contestant generation snippet missing" unless snippet
  raise "contestants are not given wild IVs" unless snippet.include?("pbApplyWildPokemonIVs(pokemon)")
  raise "HP is rolled before IVs are applied" unless snippet.index("pbApplyWildPokemonIVs") < snippet.index("pokemon.hp")
end

check(failures, "Oak lab map events call pbAddPokemon for the three starters") do
  blob = File.binread(File.join(ROOT, "Data/Map004.rxdata"))
  [":CHARMANDER, 5", ":SQUIRTLE, 5", ":BULBASAUR, 5"].each do |fragment|
    raise "Map004.rxdata missing pbAddPokemon(#{fragment})" unless blob.include?("pbAddPokemon(#{fragment}")
  end
  meta = File.read(File.join(ROOT, "PBS/map_metadata.txt"))
  raise "map 4 is not the Pokémon Lab" unless meta.include?("[004]   # Pokémon Lab")
end

if failures.empty?
  puts "fixed IV checks passed"
  exit 0
end

puts "FIXED IV CHECKS FAILED:"
failures.each { |f| puts "  - #{f}" }
exit 1
