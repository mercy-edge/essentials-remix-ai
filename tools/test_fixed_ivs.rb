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
  IV_POWER_ANCHOR_LOW = [1, 5, 2]
  IV_POWER_ANCHOR_HIGH = [20, 31, 4]
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

    def self.get(id)
      new(id.to_sym)
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
  IV_STAT_LIMIT = 31

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
check(failures, "trainer and daycare IV assignment was not rewritten") do
  forbidden = [
    "Scripts/137_Trainer.rb",
    "Scripts/248_Overworld_DayCare.rb"
  ]
  diff = `git -C #{ROOT} diff --name-only HEAD`.split("\n")
  hit = forbidden & diff
  raise "unexpected edits: #{hit.join(', ')}" unless hit.empty?
  raise "IV randomization removed from Pokemon#initialize" unless pokemon_src.include?("@iv[s.id]       = rand(IV_STAT_LIMIT + 1)")
  raise "DISABLE_IVS_AND_EVS is on, so IV edits would not change stats" unless File.read(File.join(ROOT, "Scripts/001_Settings.rb")).include?("DISABLE_IVS_AND_EVS                 = false")
  raise "IV power anchors missing" unless File.read(File.join(ROOT, "Scripts/001_Settings.rb")).include?("IV_POWER_ANCHOR_LOW")
end

check(failures, "trainer and egg IV code left in place") do
  trainer = File.read(File.join(ROOT, "Scripts/137_Trainer.rb"))
  daycare = File.read(File.join(ROOT, "Scripts/248_Overworld_DayCare.rb"))
  raise "trainer IV formula missing" unless trainer.include?("pkmn.iv[s.id] = [pkmn_data[:level] / 2, Pokemon::IV_STAT_LIMIT].min")
  raise "trainer file calls the wild IV helper" if trainer.include?("pbApplyWildPokemonIVs") || trainer.include?("pbSetAllIVs")
  raise "egg IV inheritance missing" unless daycare.include?("egg.iv[stat] = new_stat")
  raise "daycare calls the wild IV helper" if daycare.include?("pbApplyWildPokemonIVs") || daycare.include?("pbSetAllIVs")
end

def stats_of(pkmn)
  [pkmn.totalhp, pkmn.attack, pkmn.defense, pkmn.spatk, pkmn.spdef, pkmn.speed]
end

def legacy_hp(base, level)
  return 1 if base == 1
  ((base * 2) * level / 100) + level + 10
end

def legacy_stat(base, level, nat = 100)
  inner = (base * 2) * level / 100
  ((inner + 5) * nat) / 100
end

check(failures, "Oak lab starters get 5 IVs and recalculated stats") do
  $game_map.map_id = 4
  plain = make_pokemon(:CHARMANDER, 5, CHARMANDER, 0)
  pkmn = make_pokemon(:CHARMANDER, 5, CHARMANDER, 31)
  boosted_hp = pkmn.totalhp
  pkmn.nature_for_stats = FakeNature.new([[:ATTACK, 10]])
  pbApplyOakLabStarterIVs(pkmn)
  raise "IVs #{pkmn.ivs.inspect}" unless pkmn.ivs == [5, 5, 5, 5, 5, 5]
  raise "starter HP did not change" unless pkmn.totalhp != boosted_hp
  raise "starter is not stronger than IV 0" unless pkmn.totalhp > plain.totalhp
  neutral = make_pokemon(:CHARMANDER, 5, CHARMANDER, 5)
  raise "nature did not raise Attack (#{pkmn.attack} vs #{neutral.attack})" unless pkmn.attack > neutral.attack
  raise "nature changed HP" unless pkmn.totalhp == neutral.totalhp

  [:BULBASAUR, :SQUIRTLE].each do |species|
    other = make_pokemon(species, 5, CHARMANDER, 31)
    before = other.totalhp
    pbApplyOakLabStarterIVs(other)
    raise "#{species} IVs #{other.ivs.inspect}" unless other.ivs == [5, 5, 5, 5, 5, 5]
    raise "#{species} stats were not recalculated" unless other.totalhp != before
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
  raise "setup" unless pkmn.totalhp > 100
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
  raise "EV field was dropped" unless pkmn.ev[:HP] == 252
  raise "ability dropped" unless pkmn.ability == :INTIMIDATE
  # Level 35, base 100, IV 0. EVs are stored but do not change stats (HP 115, Attack 75).
  raise "HP #{pkmn.totalhp} hp #{pkmn.hp}" unless pkmn.totalhp == 115 && pkmn.hp == 115
  raise "Atk #{pkmn.attack}" unless pkmn.attack == 75
end

check(failures, "bug contest contestants are zeroed before the HP roll") do
  contest = File.read(File.join(ROOT, "Scripts/340_BugContest.rb"))
  snippet = contest[/pokemon = Pokemon\.new\(enc\[0\], enc\[1\]\).*?pbBugContestScore/m]
  raise "contestant generation snippet missing" unless snippet
  raise "contestants are not given wild IVs" unless snippet.include?("pbApplyWildPokemonIVs(pokemon)")
  raise "HP is rolled before IVs are applied" unless snippet.index("pbApplyWildPokemonIVs") < snippet.index("pokemon.hp")
end

def same_stats?(a, b)
  stats_of(a) == stats_of(b)
end

check(failures, "IV power anchors and EVs") do
  bases = [39, 52, 80, 100, 150]
  bases.each do |base|
    stats = { :HP => base, :ATTACK => base, :DEFENSE => base, :SPEED => base, :SPECIAL_ATTACK => base, :SPECIAL_DEFENSE => base }
    low_iv = make_pokemon(:ANCHOR, 1, stats, 5)
    low_ref = make_pokemon(:ANCHOR, 3, stats, 0)
    raise "L1 IV5 base #{base} #{stats_of(low_iv).inspect} != L3 IV0 #{stats_of(low_ref).inspect}" unless same_stats?(low_iv, low_ref)
    high_iv = make_pokemon(:ANCHOR, 20, stats, 31)
    high_ref = make_pokemon(:ANCHOR, 24, stats, 0)
    raise "L20 IV31 base #{base} #{stats_of(high_iv).inspect} != L24 IV0 #{stats_of(high_ref).inspect}" unless same_stats?(high_iv, high_ref)
    zero = make_pokemon(:ANCHOR, 20, stats, 0)
    raise "IV 0 HP #{zero.totalhp} != legacy #{legacy_hp(base, 20)}" unless zero.totalhp == legacy_hp(base, 20)
    raise "IV 0 Atk #{zero.attack} != legacy #{legacy_stat(base, 20)}" unless zero.attack == legacy_stat(base, 20)
  end

  shed = make_pokemon(:SHEDINJA, 50, { :HP => 1, :ATTACK => 90, :DEFENSE => 45, :SPEED => 40, :SPECIAL_ATTACK => 30, :SPECIAL_DEFENSE => 30 }, 31)
  raise "Shedinja HP #{shed.totalhp}" unless shed.totalhp == 1

  ev_mon = make_pokemon(:EV, 35, FLAT, 0)
  before = stats_of(ev_mon)
  ev_mon.ev[:HP] = 252
  ev_mon.ev[:ATTACK] = 252
  ev_mon.calc_stats
  raise "EVs changed stats #{stats_of(ev_mon).inspect} vs #{before.inspect}" unless stats_of(ev_mon) == before

  prev = -1
  [0, 1, 5, 15, 31].each do |iv|
    mon = make_pokemon(:CURVE, 20, FLAT, iv)
    raise "IV #{iv} went backwards (#{mon.attack} < #{prev})" if mon.attack < prev
    prev = mon.attack
  end

  puts "STAT TABLE (new vs old IV*level/100 formula), neutral nature, one base for HP and Attack"
  puts format("%-6s %-4s %-8s %-8s %-8s %-8s %-8s", "Lvl", "IV", "HP new", "HP old", "Atk new", "Atk old", "like lvl")
  [[1, 0], [1, 5], [1, 31], [5, 5], [20, 0], [20, 31], [50, 31], [60, 31], [100, 31]].each do |level, iv|
    mon = make_pokemon(:TABLE, level, { :HP => 80, :ATTACK => 80, :DEFENSE => 80, :SPEED => 80, :SPECIAL_ATTACK => 80, :SPECIAL_DEFENSE => 80 }, iv)
    old_hp = ((80 * 2 + iv) * level / 100) + level + 10
    old_atk = (((80 * 2 + iv) * level / 100) + 5)
    bonus = mon.iv_level_bonus(level, iv).to_f
    puts format("%-6d %-4d %-8d %-8d %-8d %-8d +%.2f", level, iv, mon.totalhp, old_hp, mon.attack, old_atk, bonus)
  end
end

check(failures, "feathers raise one IV and stop at 31") do
  src = File.read(File.join(ROOT, "Scripts/264_Item_Utilities.rb"))
  body = src[/^def pbRaiseIV\(.*?^end/m]
  raise "pbRaiseIV missing" unless body
  eval(body)
  low_hp = { :HP => 39, :ATTACK => 52, :DEFENSE => 43, :SPEED => 65, :SPECIAL_ATTACK => 60, :SPECIAL_DEFENSE => 50 }
  pkmn = make_pokemon(:FEATHER, 1, low_hp, 0)
  before = pkmn.totalhp
  got = pbRaiseIV(pkmn, :HP, 1)
  raise "gain #{got} iv #{pkmn.iv[:HP]}" unless got == 1 && pkmn.iv[:HP] == 1
  raise "other IVs changed #{pkmn.ivs.inspect}" unless pkmn.ivs == [1, 0, 0, 0, 0, 0]
  raise "HP was not recalculated (#{pkmn.totalhp} vs #{before})" unless pkmn.totalhp != before
  raise "Attack IV changed with a Health Feather" unless pkmn.attack == make_pokemon(:FEATHER, 1, low_hp, 0).attack
  pkmn.iv[:HP] = 31
  pkmn.calc_stats
  raise "cap still gained" unless pbRaiseIV(pkmn, :HP, 1) == 0 && pkmn.iv[:HP] == 31
  raise "pbRaiseIV does not recalc" unless body.include?("calc_stats")
  items = File.read(File.join(ROOT, "PBS/items.txt"))
  {
    "HEALTHFEATHER" => "HP IV",
    "MUSCLEFEATHER" => "Attack IV",
    "RESISTFEATHER" => "Defense IV",
    "GENIUSFEATHER" => "Sp. Atk IV",
    "CLEVERFEATHER" => "Sp. Def IV",
    "SWIFTFEATHER" => "Speed IV"
  }.each do |item, text|
    raise "#{item} missing from items.txt" unless items.include?("[#{item}]")
    raise "#{item} description does not mention #{text}" unless items.include?(text)
  end
  handlers = File.read(File.join(ROOT, "Scripts/265_Item_Effects.rb"))
  raise "Health Feather still raises EVs" if handlers.include?("pbUseEVRaisingItem(:HP, 1,")
  raise "Health Feather does not raise IVs" unless handlers.include?("pbUseIVRaisingItem(:HP, 1,")
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
