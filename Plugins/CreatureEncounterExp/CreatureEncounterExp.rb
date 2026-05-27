#===============================================================================
# Reward Exp for wild AND trainer battles: scripted formula + same reward
# for every able party member regardless of who participated.
#
# Helpers: CreatureEncounterFormula::* (getBaseXP, getLevelScaling, etc.)
# Rank: CreatureRank::* — set encounter rank via pbCreatureEncounter_set_rank(...)
#--------------------------------------------------------------------------------
module CreatureRank
  NORMAL     = :NORMAL
  ELITE      = :ELITE
  RARE       = :RARE
  RARE_ELITE = :RARE_ELITE
  BOSS       = :BOSS
  SYMBOLS    = [NORMAL, ELITE, RARE, RARE_ELITE, BOSS].freeze
end

module CreatureEncounterFormula
  # Global flat multiplier on every creature-kill Exp award. 1.0 = formula baseline.
  XP_MULTIPLIER = 1.5

  module_function

  def getZeroDifference(playerLevel)
    lvl = playerLevel.to_i
    return 0.20 if lvl <= 7
    return 0.15 if lvl <= 9
    return 0.10 if lvl <= 11
    return 0.08 if lvl <= 15
    return 0.07 if lvl <= 19
    return 0.06 if lvl <= 29
    return 0.05 if lvl <= 39
    return 0.04 if lvl <= 44
    return 0.03 if lvl <= 49
    return 0.02 if lvl <= 54
    return 0.015 if lvl <= 59
    return 0.01
  end

  def getGrayLevel(playerLevel)
    pl = playerLevel.to_i
    return 0 if pl <= 5
    (pl - 5 - (pl / 10).floor).to_i
  end

  def getBaseXP(playerLevel)
    pl = playerLevel.to_i
    45 + (5 * pl)
  end

  def getLevelScaling(playerLevel, mobLevel)
    pl = playerLevel.to_i
    ml = mobLevel.to_i
    if ml >= pl
      diff = ml - pl
      diff = 4 if diff > 4
      return 1.0 + (0.05 * diff)
    end
    gray = getGrayLevel(pl)
    return 0.0 if ml <= gray
    zd = getZeroDifference(pl)
    diff = pl - ml
    [1.0 - (zd * diff), 0.0].max
  end

  def getRankMultiplier(rank)
    r =
      case rank
      when Symbol then rank
      when String then rank.to_sym
      when nil then CreatureRank::NORMAL
      else rank.respond_to?(:to_sym) ? rank.to_sym : CreatureRank::NORMAL
      end
    case r
    when CreatureRank::NORMAL, :NORMAL     then 1.0
    when CreatureRank::ELITE, :ELITE       then 2.0
    when CreatureRank::RARE, :RARE         then 1.0
    when CreatureRank::RARE_ELITE, :RARE_ELITE then 2.0
    when CreatureRank::BOSS, :BOSS         then 2.0
    else 1.0
    end
  end

  def getDamageContributionFactor(playerDamage, totalDamage)
    td = totalDamage.to_f
    return 0.0 if td <= 0
    contrib = [playerDamage.to_f / td, 1.0].min
    return 0.0 if contrib < 0.05
    contrib
  end

  def calculate_mob_xp(player_level, mob_level, creature_rank, is_rested,
                       player_damage, total_damage, is_tapped_by_player)
    return 0 unless is_tapped_by_player

    xp = getBaseXP(player_level).to_f * getLevelScaling(player_level, mob_level)
    return 0 if xp.zero? || xp.negative?

    xp *= getRankMultiplier(creature_rank)

    contrib = getDamageContributionFactor(player_damage, total_damage)
    return 0 if contrib.zero?

    xp *= contrib
    xp *= 2.0 if is_rested
    xp *= XP_MULTIPLIER

    xp = xp.floor
    xp = [xp, 0].max
    xp
  end
end

module CreatureEncounterExp
  module_function

  def creature_exp_enabled?(battle)
    battle.internalBattle && battle.expGain
  end

  def pbCreatureEncounter_set_rank(rank_symbol)
    $game_temp.creature_rank = rank_symbol.to_sym
  end

  def pbCreatureEncounter_set_bonus_rested(active)
    $game_temp.creature_bonus_rested = active ? true : false
  end

  def team_damage_vs_foe(battle, foe_battler)
    arr = battle.creature_damage_to_foe && battle.creature_damage_to_foe[foe_battler.index]
    return 0 if !arr
    arr.sum { |n| n.to_i }
  end

  def max_party_level(party)
    mx = 1
    party.each do |pkmn|
      next if !pkmn || pkmn.egg?
      mx = [mx, pkmn.level].max
    end
    mx
  end

  def xp_reward_for_defeat(battle, foe_battler)
    party  = battle.pbParty(0)
    dmg    = team_damage_vs_foe(battle, foe_battler)
    foe    = foe_battler.pokemon
    denom  = [foe.totalhp, 1].max
    rested = !!battle.creature_bonus_rested
    rank   = battle.creature_rank || CreatureRank::NORMAL

    tapped = foe_battler.participants&.any? || dmg.positive? || foe_battler.captured

    dmg_for_xp = dmg.to_f
    if foe_battler.captured && dmg_for_xp < denom * 0.05
      dmg_for_xp = denom.to_f
    end

    CreatureEncounterFormula.calculate_mob_xp(
      max_party_level(party),
      foe.level,
      rank,
      rested,
      dmg_for_xp,
      denom.to_f,
      tapped
    )
  end

  def apply_exp_gain(battle, idx_party, foe_battler, raw_exp_added)
    raw_exp_added = raw_exp_added.to_i
    return if raw_exp_added <= 0

    pkmn = battle.pbParty(0)[idx_party]
    return if !pkmn&.able?

    growth_rate = pkmn.growth_rate
    show_msg    = !pkmn.shadowPokemon?

    return if pkmn.exp >= growth_rate.maximum_exp

    exp_final  = growth_rate.add_exp(pkmn.exp, raw_exp_added)
    exp_gained = exp_final - pkmn.exp
    return if exp_gained <= 0

    if show_msg
      outsider = (pkmn.owner.id != battle.pbPlayer.id ||
                 (pkmn.owner.language != 0 && pkmn.owner.language != battle.pbPlayer.language))
      if outsider
        battle.pbDisplayPaused(_INTL("{1} got a boosted {2} Exp. Points!", pkmn.name, exp_gained))
      else
        battle.pbDisplayPaused(_INTL("{1} got {2} Exp. Points!", pkmn.name, exp_gained))
      end
    end

    cur_level = pkmn.level
    new_level = growth_rate.level_from_exp(exp_final)
    if new_level < cur_level
      debug = "Levels: #{cur_level}->#{new_level} | Exp: #{pkmn.exp}->#{exp_final} | gain: #{exp_gained}"
      raise _INTL("{1}'s new level is less than its current level, which shouldn't happen.", pkmn.name) + "\n[#{debug}]"
    end

    if pkmn.shadowPokemon?
      if pkmn.heartStage <= 3
        pkmn.exp += exp_gained
        $stats.total_exp_gained += exp_gained
      end
      return
    end

    $stats.total_exp_gained += exp_gained
    temp_exp1 = pkmn.exp
    ally      = battle.pbFindBattler(idx_party)

    loop do
      level_min_exp = growth_rate.minimum_exp_for_level(cur_level)
      level_max_exp = growth_rate.minimum_exp_for_level(cur_level + 1)
      temp_exp2     = (level_max_exp < exp_final) ? level_max_exp : exp_final
      pkmn.exp = temp_exp2
      battle.scene.pbEXPBar(ally, level_min_exp, level_max_exp, temp_exp1, temp_exp2) if ally
      temp_exp1 = temp_exp2
      cur_level += 1

      if cur_level > new_level
        pkmn.calc_stats
        ally&.pbUpdate(false)
        battle.scene.pbRefreshOne(ally.index) if ally
        break
      end

      battle.pbCommonAnimation("LevelUp", ally) if ally
      old_hp    = pkmn.totalhp
      old_atk   = pkmn.attack
      old_def   = pkmn.defense
      old_satk  = pkmn.spatk
      old_sdef  = pkmn.spdef
      old_spd   = pkmn.speed
      ally.pokemon.changeHappiness("levelup") if ally&.pokemon
      pkmn.calc_stats
      ally&.pbUpdate(false)
      battle.scene.pbRefreshOne(ally.index) if ally
      battle.pbDisplayPaused(_INTL("{1} grew to Lv. {2}!", pkmn.name, cur_level)) { pbSEPlay("Pkmn level up") }
      battle.scene.pbLevelUp(pkmn, ally, old_hp, old_atk, old_def, old_satk, old_sdef, old_spd)
      movelist = pkmn.getMoveList
      movelist.each { |m| battle.pbLearnMove(idx_party, m[1]) if m[0] == cur_level }
    end
  end

  def pbGainExp_creature(battle)
    battle.scene.pbWildBattleSuccess if battle.wildBattle? && battle.pbAllFainted?(1) && !battle.pbAllFainted?(0)
    return if !battle.internalBattle || !battle.expGain


    battle.battlers.each do |b|
      next unless b&.opposes?
      next unless b.fainted? || b.captured

      dmg = team_damage_vs_foe(battle, b)
      next unless b.participants&.any? || dmg.positive? || b.captured

      xp_kill = xp_reward_for_defeat(battle, b)
      next if xp_kill <= 0

      battle.eachInTeam(0, 0) do |pkmn, i|
        next if !pkmn&.able?
        battle.pbGainEVsOne(i, b)
        apply_exp_gain(battle, i, b, xp_kill)
      end

      b.participants = []
    end
  end
end

#-------------------------------------------------------------------------------
class Game_Temp
  unless method_defined?(:creature_rank)
    attr_accessor :creature_rank
    attr_accessor :creature_bonus_rested
  end
end

class Battle
  attr_accessor :creature_damage_to_foe
  attr_accessor :creature_rank
  attr_accessor :creature_bonus_rested

  alias creature_exp_orig_initialize initialize
  def initialize(scene, p1, p2, player, opponent)
    creature_exp_orig_initialize(scene, p1, p2, player, opponent)

    @creature_damage_to_foe = {}
    @creature_rank = ($game_temp&.creature_rank.nil? ? CreatureRank::NORMAL : $game_temp.creature_rank.to_sym)
    @creature_bonus_rested = $game_temp&.creature_bonus_rested ? true : false
    if $game_temp
      $game_temp.creature_rank = nil if $game_temp.respond_to?(:creature_rank=)
      $game_temp.creature_bonus_rested = nil if $game_temp.respond_to?(:creature_bonus_rested=)
    end
  end

  alias creature_exp_orig_pbGainExp pbGainExp
  def pbGainExp
    if CreatureEncounterExp.creature_exp_enabled?(self)
      CreatureEncounterExp.pbGainExp_creature(self)
    else
      creature_exp_orig_pbGainExp
    end
  end
end

class Battle::Move
  alias creature_exp_orig_pbRecordDamageLost pbRecordDamageLost
  def pbRecordDamageLost(user, target)
    creature_exp_orig_pbRecordDamageLost(user, target)
    battle = @battle
    return if !battle || !battle.internalBattle

    dmg = target.damageState.hpLost.to_i
    return if dmg <= 0
    return if !battle.pbOwnedByPlayer?(user.index)
    return if !target.opposes?(user)

    battle.creature_damage_to_foe[target.index] ||= Array.new(Settings::MAX_PARTY_SIZE, 0)
    pi = user.pokemonIndex
    return if pi.nil?
    pi = pi.to_i
    return if pi < 0 || pi >= Settings::MAX_PARTY_SIZE
    battle.creature_damage_to_foe[target.index][pi] += dmg
  end
end

def pbCreatureEncounter_set_rank(rank_symbol); CreatureEncounterExp.pbCreatureEncounter_set_rank(rank_symbol); end
def pbCreatureEncounter_set_bonus_rested(active); CreatureEncounterExp.pbCreatureEncounter_set_bonus_rested(active); end
