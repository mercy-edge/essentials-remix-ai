#!/usr/bin/env ruby
# PBS schema check and scripted battle-logic check for the Paladin moves.
# Does not boot RPG Maker. Run from the repo root:
#   ruby tools/check_paladin_moves.rb

ROOT = File.expand_path("..", __dir__)
ERRORS = []

def fail(msg)
  ERRORS << msg
end

def assert(cond, msg)
  fail(msg) unless cond
end

def parse_pbs(path)
  sections = {}
  order = []
  current = nil
  File.readlines(path, chomp: true).each_with_index do |line, idx|
    if line =~ /^\[(.+)\]$/
      current = $1
      fail("#{path}: duplicate section #{current} at line #{idx + 1}") if sections.key?(current)
      sections[current] = {}
      order << current
      next
    end
    next if current.nil? || line.strip.empty? || line.strip.start_with?("#")
    unless line =~ /^([A-Za-z0-9_]+)\s*=\s*(.*)$/
      fail("#{path}: bad line #{idx + 1}: #{line}")
      next
    end
    sections[current][$1] = $2
  end
  [sections, order]
end

moves, _move_order = parse_pbs(File.join(ROOT, "PBS/moves.txt"))
items, _item_order = parse_pbs(File.join(ROOT, "PBS/items.txt"))

TYPES = %w[NORMAL FIGHTING FLYING POISON GROUND ROCK BUG GHOST STEEL FIRE WATER GRASS ELECTRIC PSYCHIC ICE DRAGON DARK FAIRY].freeze
CATEGORIES = %w[Physical Special Status].freeze
TARGETS = %w[None User NearAlly UserOrNearAlly AllAllies UserAndAllies NearFoe RandomNearFoe AllNearFoes Foe AllFoes NearOther AllNearOthers Other AllBattlers UserSide FoeSide BothSides].freeze

function_class_set = {}
Dir.glob(File.join(ROOT, "{Scripts,Plugins}/**/*.rb")).each do |path|
  File.read(path).scan(/class Battle::Move::([A-Za-z0-9_]+)/) { function_class_set[$1] = true }
end

moves.each do |id, row|
  type = row["Type"]
  fail("#{id}: missing or unknown Type #{type.inspect}") unless TYPES.include?(type)
  cat = row["Category"]
  fail("#{id}: missing or unknown Category #{cat.inspect}") unless CATEGORIES.include?(cat)
  target = row["Target"]
  fail("#{id}: missing or unknown Target #{target.inspect}") unless TARGETS.include?(target)
  pp = row["TotalPP"]
  fail("#{id}: TotalPP must be a positive integer") unless pp =~ /^\d+$/ && pp.to_i > 0
  if row.key?("Accuracy")
    fail("#{id}: Accuracy must be an integer") unless row["Accuracy"] =~ /^\d+$/
  end
  if row.key?("Power")
    fail("#{id}: Power must be an integer") unless row["Power"] =~ /^\d+$/
    fail("#{id}: status move should omit Power") if cat == "Status" && row["Power"] != "0"
  end
  if row.key?("Priority")
    fail("#{id}: Priority must be an integer") unless row["Priority"] =~ /^-?\d+$/
  end
  if row.key?("EffectChance")
    # Stock moves use values above 100 for combined riders (Thunder Fang is 101).
    fail("#{id}: EffectChance must be an integer") unless row["EffectChance"] =~ /^\d+$/
  end
  fail("#{id}: missing Description") if row["Description"].to_s.strip.empty?
  code = row["FunctionCode"] || "None"
  next if code == "None"
  fail("#{id}: FunctionCode #{code} has no Battle::Move::#{code} class") unless function_class_set[code]
end

EXPECTED = {
  "JUDGEMENT" => {
    "Name" => "Judgement", "Type" => "NORMAL", "Category" => "Special",
    "Power" => "60", "Accuracy" => "100", "TotalPP" => "10", "Target" => "NearOther",
    "FunctionCode" => "CustomJudgement", "EffectChance" => "20",
    "Flags" => "CanProtect,CanMirrorMove"
  },
  "CONSECRATION" => {
    "Name" => "Consecration", "Type" => "GROUND", "Category" => "Status",
    "Accuracy" => "0", "TotalPP" => "10", "Target" => "BothSides",
    "FunctionCode" => "CustomConsecration"
  },
  "HAMMEROFJUSTICE" => {
    "Name" => "Hammer of Justice", "Type" => "GROUND", "Category" => "Physical",
    "Power" => "40", "Accuracy" => "100", "TotalPP" => "15", "Target" => "NearOther",
    "Priority" => "1", "FunctionCode" => "FlinchTarget", "EffectChance" => "30",
    "Flags" => "Contact,CanProtect,CanMirrorMove"
  },
  "LAYONHANDS" => {
    "Name" => "Lay on Hands", "Type" => "WATER", "Category" => "Status",
    "Accuracy" => "0", "TotalPP" => "5", "Target" => "User",
    "FunctionCode" => "CustomLayOnHands"
  },
  "REDEMPTION" => {
    "Name" => "Redemption", "Type" => "WATER", "Category" => "Status",
    "Accuracy" => "0", "TotalPP" => "1", "Target" => "User",
    "FunctionCode" => "Gen9RevivalBlessing", "Flags" => "CannotMetronome"
  },
  "DIVINESHIELD" => {
    "Name" => "Divine Shield", "Type" => "ELECTRIC", "Category" => "Status",
    "Accuracy" => "0", "TotalPP" => "5", "Target" => "User", "Priority" => "4",
    "FunctionCode" => "CustomDivineShield"
  },
  "HOLYSHOCK" => {
    "Name" => "Holy Shock", "Type" => "ELECTRIC", "Category" => "Special",
    "Power" => "90", "Accuracy" => "100", "TotalPP" => "15", "Target" => "NearOther",
    "FunctionCode" => "CustomHolyShock", "Flags" => "CanProtect,CanMirrorMove"
  },
  "HOLYLIGHT" => {
    "Name" => "Holy Light", "Type" => "ELECTRIC", "Category" => "Status",
    "Accuracy" => "0", "TotalPP" => "5", "Target" => "User",
    "FunctionCode" => "HealUserHalfOfTotalHP", "Flags" => "Snatch"
  }
}.freeze

EXPECTED.each do |id, want|
  row = moves[id]
  fail("missing move #{id}") && next if !row
  absent = {
    "CONSECRATION" => %w[Power Priority EffectChance Flags],
    "LAYONHANDS" => %w[Power Priority EffectChance Flags],
    "REDEMPTION" => %w[Power Priority EffectChance],
    "DIVINESHIELD" => %w[Power EffectChance Flags],
    "HOLYLIGHT" => %w[Power Priority EffectChance]
  }[id] || []
  if id == "JUDGEMENT"
    absent = %w[Priority]
  end
  want.each do |key, value|
    fail("#{id}: #{key} is #{row[key].inspect}, expected #{value.inspect}") if row[key] != value
  end
  absent.each do |key|
    fail("#{id}: #{key} should be omitted, found #{row[key].inspect}") if row.key?(key)
  end
end

# Stock moves this change must not retune.
{
  "REVIVALBLESSING" => "Gen9RevivalBlessing",
  "HEALINGWISH" => "UserFaintsHealAndCureReplacement",
  "POLLENPUFF" => "HealAllyOrDamageFoe",
  "ICEBLOCK" => "CustomIceBlock"
}.each do |id, code|
  row = moves[id]
  fail("stock move #{id} missing") && next if !row
  fail("stock #{id} FunctionCode changed to #{row["FunctionCode"]}") if row["FunctionCode"] != code
end

tm_by_move = {}
items.each do |id, row|
  next unless id =~ /^TM(\d+)$/
  num = $1.to_i
  fail("#{id}: FieldUse must be TR") if row["FieldUse"] != "TR"
  fail("#{id}: Pocket must be 4") if row["Pocket"] != "4"
  fail("#{id}: Price must be a positive integer") unless row["Price"] =~ /^\d+$/ && row["Price"].to_i > 0
  fail("#{id}: BPPrice must be a positive integer") unless row["BPPrice"] =~ /^\d+$/ && row["BPPrice"].to_i > 0
  move = row["Move"]
  fail("#{id}: Move #{move} is not a move") unless moves.key?(move)
  (tm_by_move[move] ||= []) << id
end

{
  "JUDGEMENT" => "TM007",
  "HOLYLIGHT" => "TM248",
  "HAMMEROFJUSTICE" => "TM249",
  "CONSECRATION" => "TM295",
  "LAYONHANDS" => "TM296",
  "DIVINESHIELD" => "TM297",
  "HOLYSHOCK" => "TM298"
}.each do |move_id, tm|
  list = tm_by_move[move_id] || []
  fail("#{move_id} should be taught by #{tm}, found #{list.inspect}") if list != [tm]
  row = items[tm]
  fail("#{tm} missing") && next if !row
  fail("#{tm} description drifted from the move") if row["Description"] != moves[move_id]["Description"]
  fail("#{tm} price should match the class TM pattern (3000)") if row["Price"] != "3000"
  fail("#{tm} BPPrice should match the class TM pattern (32)") if row["BPPrice"] != "32"
end

assert((tm_by_move["REDEMPTION"] || []).empty?, "REDEMPTION should not have a TM")
assert(!items.key?("TM280"), "TM280 is reserved for the unmerged priest kit")
assert(!items.key?("TM294"), "TM294 is reserved for the unmerged priest kit")
(280..294).each do |n|
  id = format("TM%03d", n)
  fail("#{id} collides with the priest TM range") if items.key?(id)
end

#-------------------------------------------------------------------------------
# Scripted battle-logic check. Stubs only what the Paladin classes touch.
#-------------------------------------------------------------------------------
def _INTL(text, *args)
  return text if args.empty?
  return sprintf(text.gsub(/\{(\d+)\}/) { format("%%%d$s", $1.to_i) }, *args)
rescue StandardError
  return text
end

module GameData
  class Type
    def self.exists?(type)
      %i[NORMAL ELECTRIC WATER GROUND FIRE FLYING].include?(type)
    end
  end
end

module Battle
  module AbilityEffects
    def self.triggerModifyMoveBaseType(ability, _user, _move, type)
      return :FLYING if ability == :AERILATE && type == :NORMAL
      return type
    end
  end

  class Battler
    STAT_STAGE_MAXIMUM = 6
    STAT_STAGE_MULTIPLIERS = [2, 2, 2, 2, 2, 2, 2, 3, 4, 5, 6, 7, 8].freeze
    STAT_STAGE_DIVISORS    = [8, 7, 6, 5, 4, 3, 2, 2, 2, 2, 2, 2, 2].freeze
  end

  class Move
    attr_reader :battle
    attr_accessor :healing

    def initialize(battle, move)
      @battle = battle
      @addlEffect = move.respond_to?(:effect_chance) ? move.effect_chance : 20
      @healing = false
    end

    def pbAdditionalEffectChance(_user, _target, _effectChance = 0)
      return @addlEffect
    end

    def pbImmunityByAbility(_user, target, _show_message)
      return target.absorbed
    end

    def pbCalcType(_user)
      return :ELECTRIC
    end
  end
end

category_src = File.read(File.join(ROOT, "Scripts/186_MoveEffects_Generation9.rb"))
start = category_src.index("class Battle::Move::CustomCategoryByHigherAttack")
fail("CustomCategoryByHigherAttack source missing") if !start
chunk = []
category_src[start..].each_line do |line|
  chunk << line
  break if line == "end\n"
end
eval(chunk.join, binding, "CustomCategoryByHigherAttack")

class Battle::Move::CustomIceBlock < Battle::Move
end

class Battle::Move::HealAllyOrDamageFoe < Battle::Move
  def pbDamagingMove?
    return false if @healing
    return true
  end
end

load File.join(ROOT, "Scripts/187_PaladinMoves.rb")

MoveData = Struct.new(:effect_chance)
StubTarget = Struct.new(:index, :absorbed, :ability_id, :ability_on, :calls, :damageState) do
  def abilityActive?
    ability_on
  end

  def opposes?(other)
    other_index = other.respond_to?(:index) ? other.index : other
    (index & 1) != (other_index & 1)
  end

  def pbCanParalyze?(*)
    calls << :can_paralyze
    true
  end

  def pbParalyze(*)
    calls << :paralyze
  end

  def pbCanBurn?(*)
    false
  end

  def pbBurn(*)
    calls << :burn
  end
end
DamageState = Struct.new(:substitute)

class StubUser
  attr_accessor :attack, :spatk, :stages, :item_id, :item_on, :ability, :ability_on
  attr_accessor :index, :pokemon, :frozen_msg

  def initialize
    @attack = 100
    @spatk = 100
    @stages = { ATTACK: 0, SPECIAL_ATTACK: 0 }
    @item_on = false
    @ability_on = false
    @index = 0
  end

  def itemActive?
    @item_on
  end

  def abilityActive?
    @ability_on
  end

  def opposes?(other)
    other_index = other.respond_to?(:index) ? other.index : other
    (@index & 1) != (other_index & 1)
  end

  def pbFreeze(msg = nil)
    @frozen_msg = msg
  end

  def pbThis(_lower = false)
    "Paladin"
  end

  def idxOwnSide
    @index & 1
  end
end

battle = Object.new
def battle.messages
  @messages ||= []
end

def battle.pbDisplay(msg)
  messages << msg
end

def battle.pbCanChooseNonActive?(_index)
  @can_switch
end

def battle.can_switch=(value)
  @can_switch = value
end

user = StubUser.new
judgement = Battle::Move::CustomJudgement.new(battle, MoveData.new(20))

user.attack = 180
user.spatk = 90
judgement.pbOnStartUse(user, [])
assert(judgement.physicalMove?, "higher Attack should make Judgement physical")
assert(!judgement.specialMove?, "higher Attack should not leave Judgement special")

user.attack = 90
user.spatk = 180
judgement.pbOnStartUse(user, [])
assert(judgement.specialMove?, "higher Sp. Atk should make Judgement special")

user.attack = 120
user.spatk = 120
judgement.pbOnStartUse(user, [])
assert(judgement.specialMove?, "an Attack tie should stay special, matching Photon Geyser")

assert(PaladinMoves::JUDGEMENT_SEALS.empty?, "seal table must ship empty")
assert(PaladinMoves.judgement_seal(:TESTSEAL, true).nil?, "unknown item is not a Seal")
user.item_id = nil
user.item_on = false
assert(judgement.pbBaseDamage(60, user, nil) == 60, "no Seal keeps the PBS power of 60")

PaladinMoves.send(:remove_const, :JUDGEMENT_SEALS)
PaladinMoves.const_set(:JUDGEMENT_SEALS, {
  :SEALOFTHECRUSADER => [:NORMAL, nil, 100],
  :SEALOFJUSTICE => [:ELECTRIC, :PARALYZE]
})
user.item_id = :SEALOFTHECRUSADER
user.item_on = true
crusader = PaladinMoves.judgement_seal(:SEALOFTHECRUSADER, true)
assert(crusader == [:NORMAL, nil, 100], "Seal of the Crusader stays Normal at power 100, got #{crusader.inspect}")
assert(judgement.pbBaseType(user) == :NORMAL, "Seal of the Crusader does not change the type")
assert(judgement.pbBaseDamage(60, user, nil) == 100, "Seal of the Crusader raises power from 60 to 100")
assert(judgement.pbAdditionalEffectChance(user, nil) == 0, "Seal of the Crusader has no secondary effect")
justice = PaladinMoves.judgement_seal(:SEALOFJUSTICE, true)
assert(justice == [:ELECTRIC, :PARALYZE, nil], "a two-field Seal has no power override, got #{justice.inspect}")
user.item_id = :SEALOFJUSTICE
assert(judgement.pbBaseDamage(60, user, nil) == 60, "a Seal without a power field keeps 60")
PaladinMoves.send(:remove_const, :JUDGEMENT_SEALS)
PaladinMoves.const_set(:JUDGEMENT_SEALS, {}.freeze)

user.item_id = :TESTSEAL
user.item_on = true
assert(judgement.pbBaseType(user) == :NORMAL, "no Seal keeps Judgement Normal")
assert(judgement.pbAdditionalEffectChance(user, nil) == 0, "no Seal means no effect chance")

def PaladinMoves.judgement_seal(item_id, item_active)
  return [:ELECTRIC, :PARALYZE, nil] if item_id == :TESTSEAL && item_active
  return [:WATER, nil, nil] if item_id == :TYPEONLY && item_active
  return [:NORMAL, nil, 100] if item_id == :SEALOFTHECRUSADER && item_active
  return nil
end

user.ability_on = true
user.ability = :AERILATE
user.item_on = false
assert(judgement.pbBaseType(user) == :FLYING, "unsealed Judgement still lets Aerilate change Normal")
user.item_on = true
user.item_id = :TESTSEAL
assert(judgement.pbBaseType(user) == :ELECTRIC, "a Seal sets the type and is not Aerilate fodder")
assert(judgement.pbAdditionalEffectChance(user, nil) == 20, "a Seal with an effect keeps the 20% chance")

target = StubTarget.new(1, false, :VOLTABSORB, true, [], DamageState.new(false))
judgement.pbAdditionalEffect(user, target)
assert(target.calls == [:can_paralyze, :paralyze], "Seal effect should attempt paralysis, got #{target.calls.inspect}")

target.damageState = DamageState.new(true)
target.calls = []
judgement.pbAdditionalEffect(user, target)
assert(target.calls.empty?, "Substitute blocks the Seal rider")

user.item_id = :TYPEONLY
assert(judgement.pbBaseType(user) == :WATER, "a type-only Seal changes type")
assert(judgement.pbAdditionalEffectChance(user, nil) == 0, "a type-only Seal has no rider")

assert(PaladinMoves::CONSECRATION_TERRAIN_TURNS == 5, "Consecration lasts 5 turns")
assert(PaladinMoves.consecration_tick(true, true, true, true) == :heal, "grounded ally heals")
assert(PaladinMoves.consecration_tick(false, true, true, true) == :damage, "grounded foe is seared")
assert(PaladinMoves.consecration_tick(true, false, true, true).nil?, "airborne ally is skipped")
assert(PaladinMoves.consecration_tick(false, false, true, true).nil?, "airborne foe is skipped")
assert(PaladinMoves.consecration_tick(true, true, false, true).nil?, "full or blocked ally does not heal")
assert(PaladinMoves.consecration_tick(false, true, false, false).nil?, "Magic Guard foe is not seared")

lay = Battle::Move::CustomLayOnHands.new(battle, MoveData.new(0))
battle.can_switch = false
assert(lay.pbMoveFailed?(user, []), "Lay on Hands fails with no switch-in")
assert(battle.messages.include?("But it failed!"), "Lay on Hands shows the failure message")
battle.can_switch = true
battle.messages.clear
assert(!lay.pbMoveFailed?(user, []), "Lay on Hands succeeds when a switch-in exists")
assert(!lay.respond_to?(:pbSelfKO) || lay.method(:pbSelfKO).owner != Battle::Move::CustomLayOnHands,
       "Lay on Hands must not faint the user")
assert(File.read(File.join(ROOT, "Scripts/187_PaladinMoves.rb")) !~ /pbReduceHP/,
       "Lay on Hands must not reduce the user's HP")

shield_user = StubUser.new
shield_user.pokemon = Struct.new(:divine_shield).new(false)
shield = Battle::Move::CustomDivineShield.new(battle, MoveData.new(0))
assert(shield.is_a?(Battle::Move::CustomIceBlock), "Divine Shield reuses the Ice Block move class")
shield.pbEffectGeneral(shield_user)
assert(shield_user.pokemon.divine_shield == true, "Divine Shield marks the Pokémon")
assert(shield_user.frozen_msg.include?("divine shield"), "Divine Shield apply message is holy, got #{shield_user.frozen_msg.inspect}")
ice_src = File.read(File.join(ROOT, "Scripts/186_MoveEffects_Generation9.rb"))
assert(ice_src.include?('user.pbFreeze(_INTL("{1} encased itself in ice!", user.pbThis))'),
       "Ice Block's apply message must stay unchanged")

shock = Battle::Move::CustomHolyShock.new(battle, MoveData.new(0))
ally = StubTarget.new(2, true, :VOLTABSORB, true, [], DamageState.new(false))
foe = StubTarget.new(1, true, :LIGHTNINGROD, true, [], DamageState.new(false))

shock.pbCalcType(user)
shock.pbModifyTargets([ally], user)
shock.pbOnStartUse(user, [ally])
assert(shock.instance_variable_get(:@healing), "Holy Shock heals an ally when nothing redirects")
assert(!shock.pbDamagingMove?, "an ally heal is not a damaging move")
assert(!shock.pbImmunityByAbility(user, ally, true), "Volt Absorb does not eat the ally heal")

shock.pbCalcType(user)
shock.pbModifyTargets([foe], user)
shock.pbOnStartUse(user, [foe])
assert(!shock.instance_variable_get(:@healing), "Holy Shock attacks a foe")
assert(shock.pbDamagingMove?, "a foe target is an attack")
assert(shock.pbImmunityByAbility(user, foe, true), "Lightning Rod still absorbs an attack")

shock.pbCalcType(user)
shock.pbModifyTargets([ally], user)
shock.pbOnStartUse(user, [foe])
assert(!shock.instance_variable_get(:@healing), "a redirected ally target resolves as an attack")
assert(shock.pbDamagingMove?, "redirected Holy Shock is damaging")
rod_ally = StubTarget.new(2, true, :LIGHTNINGROD, true, [], DamageState.new(false))
assert(shock.pbImmunityByAbility(user, rod_ally, true), "redirected Lightning Rod holder is not healed")

shock.pbCalcType(user)
shock.pbOnStartUse(user, [ally])
assert(shock.instance_variable_get(:@healing), "without a redirect check, an ally is healed")

ground_ally = StubTarget.new(2, false, :LEVITATE, true, [], DamageState.new(false))
shock.pbCalcType(user)
shock.pbModifyTargets([ground_ally], user)
shock.pbOnStartUse(user, [ground_ally])
assert(!shock.pbImmunityByAbility(user, ground_ally, true),
       "a non-absorb ability is not treated as an Electric absorb on the heal")

field = Struct.new(:terrain, :terrainSetterSide, :terrainDuration).new(:None, nil, 0)
battle.define_singleton_method(:field) { field }
battle.define_singleton_method(:pbStartTerrain) do |caster, new_terrain, _fixed = true, duration = nil|
  return if field.terrain == new_terrain
  field.terrain = new_terrain
  field.terrainDuration = duration
  field.terrainSetterSide = caster.idxOwnSide
end
user.index = 0
consecration = Battle::Move::CustomConsecration.new(battle, MoveData.new(0))
battle.messages.clear
assert(!consecration.pbMoveFailed?(user, []), "Consecration works when no terrain is up")
consecration.pbEffectGeneral(user)
assert(field.terrain == :Consecration, "Consecration sets the terrain")
assert(field.terrainSetterSide == 0, "Consecration records the user's side")
assert(field.terrainDuration == PaladinMoves::CONSECRATION_TERRAIN_TURNS, "duration uses the constant")
battle.messages.clear
assert(consecration.pbMoveFailed?(user, []), "the same side cannot recast Consecration")
user.index = 1
battle.messages.clear
assert(!consecration.pbMoveFailed?(user, []), "the other side can replace Consecration")
consecration.pbEffectGeneral(user)
assert(field.terrain == :Consecration && field.terrainSetterSide == 1,
       "replacing Consecration moves the setter side, got #{field.terrainSetterSide}")

if ERRORS.empty?
  puts "Paladin move check OK (#{EXPECTED.length} moves, TM295–TM298, scripted battle rules)"
  exit 0
end

warn "Paladin move check failed:"
ERRORS.each { |msg| warn "  #{msg}" }
exit 1
