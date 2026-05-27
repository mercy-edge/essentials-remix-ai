#===============================================================================
# Generation 9 move effects (Scarlet/Violet–era). See PBS moves.txt entries.
#===============================================================================

#-------------------------------------------------------------------------------
# Weather
#-------------------------------------------------------------------------------
class Battle::Move::StartSnowWeather < Battle::Move::WeatherMove
  def initialize(battle, move)
    super
    @weatherType = :Snow
  end
end

class Battle::Move::StartSnowWeatherSwitchOutUser < Battle::Move::SwitchOutUserStatusMove
  def pbEffectGeneral(user)
    return super if user.wild?
    @battle.pbStartWeather(user, :Snow, true, false)
  end
end

#-------------------------------------------------------------------------------
# Protect variants
#-------------------------------------------------------------------------------
class Battle::Move::ProtectUserBurningBulwark < Battle::Move::ProtectMove
  def initialize(battle, move)
    super
    @effect = PBEffects::BurningBulwark
  end
end

class Battle::Move::ProtectUserSilkTrap < Battle::Move::ProtectMove
  def initialize(battle, move)
    super
    @effect = PBEffects::SilkTrap
  end
end

#-------------------------------------------------------------------------------
# Misc attack patterns
#-------------------------------------------------------------------------------
class Battle::Move::Gen9BypassProtectDamaging < Battle::Move
  def pbBypassProtect?; return true; end
end

class Battle::Move::Gen9FailsIfLastMoveWasSame < Battle::Move
  def pbMoveFailed?(user, targets)
    if user.lastRegularMoveUsed == @id
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end
end

class Battle::Move::Gen9CollisionElectroBoost < Battle::Move
  def pbModifyDamage(damageMult, user, target)
    tm = target.damageState.typeMod
    return damageMult if !tm || tm <= Effectiveness::NORMAL_EFFECTIVE_MULTIPLIER
    return damageMult * (5461 / 4096.0)
  end
end

class Battle::Move::Gen9ElectroShot < Battle::Move::TwoTurnAttackChargeRaiseUserSpAtk1
  def pbIsChargingTurn?(user)
    ret = super
    if !user.effects[PBEffects::TwoTurnAttack] &&
       [:Rain, :HeavyRain].include?(user.effectiveWeather)
      @powerHerb = false
      @chargingTurn = true
      @damagingTurn = true
      return false
    end
    return ret
  end
end

class Battle::Move::Gen9AxeKick < Battle::Move::CrashDamageIfFailsUnusableInGravity
  def pbAdditionalEffect(user, target)
    return if target.damageState.substitute
    target.pbConfuse(user) if target.pbCanConfuse?(user, false, self) &&
                             @battle.pbRandom(100) < 30
  end
end

class Battle::Move::Gen9FlowerTrick < Battle::Move
  def pbCritialOverride(_user, _target); return 1; end

  def pbAccuracyCheck(user, target)
    return true
  end
end

class Battle::Move::Gen9IceSpinner < Battle::Move
  def pbEffectAfterAllHits(user, target)
    return if user.fainted? || target.damageState.unaffected
    return if @battle.field.terrain == :None
    @battle.pbStartTerrain(user, :None)
  end
end

class Battle::Move::Gen9IvyCudgel < Battle::Move
  def pbBaseType(user)
    case user.form
    when 1 then return :WATER if GameData::Type.exists?(:WATER)
    when 2 then return :FIRE if GameData::Type.exists?(:FIRE)
    when 3 then return :ROCK if GameData::Type.exists?(:ROCK)
    end
    return super
  end
end

class Battle::Move::Gen9RagingBull < Battle::Move::RemoveScreens
  def pbBaseType(user)
    return :WATER if user.form == 1 && GameData::Type.exists?(:WATER)
    return :FIRE if user.form == 2 && GameData::Type.exists?(:FIRE)
    return super
  end
end

class Battle::Move::Gen9HardPress < Battle::Move
  def pbBaseDamage(baseDmg, user, target)
    mult = target.hp.to_f / [target.totalhp, 1].max
    return [(baseDmg * mult).round, 1].max
  end
end

class Battle::Move::Gen9HydroSteam < Battle::Move
  # Cancels Sun's usual Water penalty and boosts this move like Gen 9 Hydro Steam.
  def pbModifyDamage(damageMult, user, target)
    damageMult *= 3 if [:Sun, :HarshSun].include?(user.effectiveWeather)
    return damageMult
  end
end

class Battle::Move::Gen9Psyblade < Battle::Move
  def pbBaseDamage(baseDmg, user, target)
    ret = baseDmg
    ret = (ret * 1.5).round if @battle.field.terrain == :Electric && user.affectedByTerrain?
    return ret
  end
end

class Battle::Move::Gen9LastRespects < Battle::Move
  def pbBaseDamage(baseDmg, user, target)
    count = 0
    @battle.pbParty(user.index).each do |pkmn|
      next if !pkmn
      count += 1 if pkmn.fainted?
    end
    return baseDmg + (50 * count)
  end
end

class Battle::Move::Gen9RageFist < Battle::Move
  def pbBaseDamage(baseDmg, user, target)
    hits = user.effects[PBEffects::RageFistHits]
    hits = [hits, 6].min
    return baseDmg + (50 * hits)
  end
end

class Battle::Move::Gen9TemperFlare < Battle::Move
  def pbBaseDamage(baseDmg, user, target)
    return baseDmg * 2 if user.effects[PBEffects::HadStatLoweredThisBattle]
    return baseDmg
  end
end

class Battle::Move::Gen9GlaiveRush < Battle::Move
  def pbEffectWhenDealingDamage(user, target)
    user.effects[PBEffects::GlaiveRushVulnerable] = true
    @battle.pbDisplay(_INTL("{1} became vulnerable to attacks!", user.pbThis))
  end
end

class Battle::Move::Gen9FickleBeam < Battle::Move
  def pbModifyDamage(damageMult, user, target)
    damageMult *= 2 if @battle.pbRandom(100) < 30
    return damageMult
  end
end

class Battle::Move::Gen9Thunderclap < Battle::Move
  def pbPriority(user); return 1; end

  def pbFailsAgainstTarget?(user, target, show_message)
    if @battle.choices[target.index][0] != :UseMove
      @battle.pbDisplay(_INTL("But it failed!")) if show_message
      return true
    end
    oppMove = @battle.choices[target.index][2]
    if !oppMove || oppMove.statusMove? || target.movedThisRound?
      @battle.pbDisplay(_INTL("But it failed!")) if show_message
      return true
    end
    return false
  end
end

class Battle::Move::Gen9UpperHand < Battle::Move
  def pbPriority(user); return 3; end

  def pbFailsAgainstTarget?(user, target, show_message)
    if @battle.choices[target.index][0] != :UseMove
      @battle.pbDisplay(_INTL("But it failed!")) if show_message
      return true
    end
    oppMove = @battle.choices[target.index][2]
    pri = oppMove ? oppMove.pbPriority(target) : 0
    if !oppMove || pri <= 0 || target.movedThisRound?
      @battle.pbDisplay(_INTL("But it failed!")) if show_message
      return true
    end
    return false
  end
end

class Battle::Move::Gen9PopulationBomb < Battle::Move
  def multiHitMove?; return true; end

  def successCheckPerHit?
    return @accCheckPerHit
  end

  def pbOnStartUse(user, targets)
    @accCheckPerHit = !user.hasActiveAbility?(:SKILLLINK)
  end

  def pbNumHits(user, targets)
    return 10 if user.hasActiveAbility?(:SKILLLINK)
    return 1 + @battle.pbRandom(10)
  end
end

class Battle::Move::Gen9SaltCure < Battle::Move
  def pbEffectAgainstTarget(user, target)
    target.effects[PBEffects::SaltCure] = user.index
  end
end

class Battle::Move::Gen9SyrupBomb < Battle::Move
  def pbAdditionalEffect(user, target)
    return if target.damageState.substitute
    target.effects[PBEffects::SyrupBomb] = 3
    @battle.pbDisplay(_INTL("{1} became stuck in syrup!", target.pbThis(true)))
  end
end

class Battle::Move::Gen9PsychicNoise < Battle::Move
  def pbAdditionalEffect(user, target)
    return if target.damageState.substitute
    return if target.effects[PBEffects::HealBlock] > 0
    target.effects[PBEffects::HealBlock] = 2
    @battle.pbDisplay(_INTL("{1} was prevented from healing!", target.pbThis(true)))
  end
end

class Battle::Move::Gen9MatchaGotcha < Battle::Move::HealUserByHalfOfDamageDone
  def pbAdditionalEffect(user, target)
    return if target.damageState.substitute
    target.pbBurn(user) if target.pbCanBurn?(user, false, self) &&
                          @battle.pbRandom(100) < 20
  end
end

class Battle::Move::Gen9MakeItRain < Battle::Move::LowerUserSpAtk1
  def pbEffectAfterAllHits(user, target)
    return if target.damageState.unaffected
    if user.pbOwnedByPlayer?
      @battle.field.effects[PBEffects::PayDay] += 5 * user.level
    end
    @battle.pbDisplay(_INTL("Coins were scattered everywhere!"))
  end
end

class Battle::Move::Gen9MortalSpin < Battle::Move::RemoveUserBindingAndEntryHazards
  def pbAdditionalEffect(user, target)
    return if target.damageState.substitute
    target.pbPoison(user) if target.pbCanPoison?(user, false, self)
  end

  def pbEffectGeneral(user); end

  def pbEffectAfterAllHits(user, target)
    super(user, target)
  end
end

class Battle::Move::Gen9DoubleShock < Battle::Move
  def pbMoveFailed?(user, targets)
    if !user.pbHasType?(:ELECTRIC)
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbEffectWhenDealingDamage(user, target)
    return if user.effects[PBEffects::DoubleShock]
    user.effects[PBEffects::DoubleShock] = true
    @battle.pbDisplay(_INTL("{1} used up all its electricity!", user.pbThis))
  end
end

class Battle::Move::Gen9FilletAway < Battle::Move
  def pbMoveFailed?(user, targets)
    amt = user.totalhp / 2
    amt = [amt, 1].max
    if user.hp <= amt
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    failed = true
    [:ATTACK, :SPECIAL_ATTACK, :SPEED].each do |stat|
      next if !user.pbCanRaiseStatStage?(stat, user, self)
      failed = false
      break
    end
    if failed
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbEffectGeneral(user)
    amt = user.totalhp / 2
    amt = [amt, 1].max
    user.pbReduceHP(amt, false, false)
    user.pbItemHPHealCheck
    showAnim = true
    [:ATTACK, :SPECIAL_ATTACK, :SPEED].each do |stat|
      next if !user.pbCanRaiseStatStage?(stat, user, self)
      user.pbRaiseStatStage(stat, 2, user, showAnim)
      showAnim = false
    end
  end
end

class Battle::Move::Gen9SpicyExtract < Battle::Move
  def pbFailsAgainstTarget?(user, target, show_message)
    if !target.pbCanLowerStatStage?(:DEFENSE, user, self, false) &&
       !target.pbCanRaiseStatStage?(:ATTACK, target, self, false)
      @battle.pbDisplay(_INTL("But it failed!")) if show_message
      return true
    end
    return false
  end

  def pbEffectAgainstTarget(user, target)
    target.pbLowerStatStage(:DEFENSE, 2, user) if target.pbCanLowerStatStage?(:DEFENSE, user, self)
    target.pbRaiseStatStage(:ATTACK, 2, target, user) if target.pbCanRaiseStatStage?(:ATTACK, target, self)
  end
end

class Battle::Move::Gen9DragonCheer < Battle::Move
  def pbMoveFailed?(user, targets)
    allies = @battle.allSameSideBattlers(user).select { |b| b.pbHasType?(:DRAGON) }
    if allies.none?
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbEffectGeneral(user)
    @battle.allSameSideBattlers(user).each do |b|
      next if !b.pbHasType?(:DRAGON)
      b.effects[PBEffects::FocusEnergy] += 2 if b.effects[PBEffects::FocusEnergy] < 3
    end
    @battle.pbDisplay(_INTL("The Dragon types were rallied for critical hits!"))
  end
end

class Battle::Move::Gen9Doodle < Battle::Move
  def ignoresSubstitute?(user); return true; end

  def pbFailsAgainstTarget?(user, target, show_message)
    if !target.ability || target.ungainableAbility? ||
       [:POWEROFALCHEMY, :RECEIVER, :TRACE, :WONDERGUARD].include?(target.ability_id)
      @battle.pbDisplay(_INTL("But it failed!")) if show_message
      return true
    end
    return false
  end

  def pbEffectAgainstTarget(user, target)
    @battle.allSameSideBattlers(user).each do |b|
      next if b.unstoppableAbility?
      oldAbil = b.ability
      @battle.pbShowAbilitySplash(b, true, false)
      b.ability = target.ability
      @battle.pbReplaceAbilitySplash(b)
      @battle.pbDisplay(_INTL("{1} sketched {2}'s {3}!",
                              b.pbThis, target.pbThis(true), target.abilityName))
      @battle.pbHideAbilitySplash(b)
      b.pbOnLosingAbility(oldAbil)
      b.pbTriggerAbilityOnGainingIt
    end
  end
end

class Battle::Move::Gen9OrderUp < Battle::Move
  def pbEffectAfterAllHits(user, target)
    return if target.damageState.unaffected
    ally = user.allAllies.find { |b| b.isSpecies?(:TATSUGIRI) }
    stat = :ATTACK
    if ally
      stat = case ally.form
             when 1 then :DEFENSE
             when 2 then :SPEED
             else :ATTACK
             end
    end
    user.pbRaiseStatStage(stat, 1, user) if user.pbCanRaiseStatStage?(stat, user, self)
  end
end

class Battle::Move::Gen9RevivalBlessing < Battle::Move
  def healingMove?; return true; end

  def pbMoveFailed?(user, targets)
    party = @battle.pbParty(user.index)
    if party.none? { |p| p&.fainted? }
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbEffectGeneral(user)
    party = @battle.pbParty(user.index)
    party.each do |pkmn|
      next if !pkmn || !pkmn.fainted?
      hp = (pkmn.totalhp / 2.0).round
      hp = [hp, 1].max
      pkmn.hp = hp
      pkmn.heal_status
      @battle.pbDisplay(_INTL("{1} was revived!", pkmn.name))
      break
    end
  end
end

class Battle::Move::Gen9ShedTail < Battle::Move::SwitchOutUserStatusMove
  def pbMoveFailed?(user, targets)
    if user.effects[PBEffects::Substitute] > 0
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    @shedCost = user.totalhp / 2
    @shedCost = [@shedCost, 1].max
    if user.hp <= @shedCost
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return super
  end

  def pbOnStartUse(user, targets)
    user.pbReduceHP(@shedCost, false, false)
    user.pbItemHPHealCheck
  end

  def pbEffectGeneral(user)
    return super if user.wild?
    user.effects[PBEffects::Substitute] = [@shedCost, 1].max
    @battle.pbDisplay(_INTL("{1} shed its tail to create a decoy!", user.pbThis))
  end
end

class Battle::Move::Gen9TidyUp < Battle::Move
  def pbEffectGeneral(user)
    @battle.allBattlers.each do |b|
      next if b.effects[PBEffects::Substitute] <= 0
      b.effects[PBEffects::Substitute] = 0
      @battle.pbDisplay(_INTL("{1}'s substitute faded!", b.pbThis(true)))
    end
    [user.pbOwnSide, user.pbOpposingSide].each do |side|
      if side.effects[PBEffects::StealthRock]
        side.effects[PBEffects::StealthRock] = false
        @battle.pbDisplay(_INTL("Pointed stones disappeared from the battlefield!"))
      end
      if side.effects[PBEffects::Spikes] > 0
        side.effects[PBEffects::Spikes] = 0
        @battle.pbDisplay(_INTL("Spikes disappeared from the battlefield!"))
      end
      if side.effects[PBEffects::ToxicSpikes] > 0
        side.effects[PBEffects::ToxicSpikes] = 0
        @battle.pbDisplay(_INTL("Poison spikes disappeared from the battlefield!"))
      end
      if side.effects[PBEffects::StickyWeb]
        side.effects[PBEffects::StickyWeb] = false
        @battle.pbDisplay(_INTL("The sticky webs disappeared from the battlefield!"))
      end
    end
    showAnim = true
    if user.pbCanRaiseStatStage?(:ATTACK, user, self)
      user.pbRaiseStatStage(:ATTACK, 1, user, showAnim)
      showAnim = false
    end
    user.pbRaiseStatStage(:SPEED, 1, user, showAnim) if user.pbCanRaiseStatStage?(:SPEED, user, self)
    @battle.pbDisplay(_INTL("{1} tidied up!", user.pbThis))
  end
end

class Battle::Move::Gen9TeraStarstorm < Battle::Move
  # Multi-hit in Terastal battles isn’t modeled here; hits all foes like Heat Wave.
end

class Battle::Move::Gen9AlluringVoice < Battle::Move
  def pbAdditionalEffect(user, target)
    return if target.damageState.substitute
    return if !target.statsRaisedThisRound
    target.pbConfuse(user) if target.pbCanConfuse?(user, false, self)
  end
end

#-------------------------------------------------------------------------------
# Custom: Move category depends on user's higher offensive stat.
#-------------------------------------------------------------------------------
class Battle::Move::CustomCategoryByHigherAttack < Battle::Move
  def initialize(battle, move)
    super
    @calcCategory = 1
  end

  def physicalMove?(thisType = nil); return (@calcCategory == 0); end
  def specialMove?(thisType = nil);  return (@calcCategory == 1); end

  def pbOnStartUse(user, targets)
    max_stage = Battle::Battler::STAT_STAGE_MAXIMUM
    stage_mul = Battle::Battler::STAT_STAGE_MULTIPLIERS
    stage_div = Battle::Battler::STAT_STAGE_DIVISORS
    atk_stage = user.stages[:ATTACK] + max_stage
    sp_atk_stage = user.stages[:SPECIAL_ATTACK] + max_stage
    real_atk = (user.attack.to_f * stage_mul[atk_stage] / stage_div[atk_stage]).floor
    real_sp_atk = (user.spatk.to_f * stage_mul[sp_atk_stage] / stage_div[sp_atk_stage]).floor
    @calcCategory = (real_atk > real_sp_atk) ? 0 : 1
  end
end

#-------------------------------------------------------------------------------
# Custom spell move effects
#-------------------------------------------------------------------------------
class Battle::Move::CustomMoonfire < Battle::Move
  def pbAccuracyCheck(user, target); return true; end

  def pbAdditionalEffect(user, target)
    return if target.damageState.substitute
    target.pbBurn(user) if @battle.pbRandom(100) < 10 && target.pbCanBurn?(user, false, self)
  end
end

class Battle::Move::HealTargetAquaRing < Battle::Move
  def healingMove?;  return true; end
  def canMagicCoat?; return true; end

  def pbFailsAgainstTarget?(user, target, show_message)
    if target.effects[PBEffects::AquaRing]
      @battle.pbDisplay(_INTL("But it failed!")) if show_message
      return true
    end
    return false
  end

  def pbEffectAgainstTarget(user, target)
    target.effects[PBEffects::AquaRing] = true
    @battle.pbDisplay(_INTL("{1} surrounded itself with a veil of water!", target.pbThis))
  end
end

class Battle::Move::CustomConcussiveShot < Battle::Move
  def pbAdditionalEffect(user, target)
    return if target.damageState.substitute
    target.pbLowerStatStage(:SPEED, 1, user) if target.pbCanLowerStatStage?(:SPEED, user, self)
    target.pbFlinch(user) if @battle.pbRandom(100) < 20
  end
end

class Battle::Move::CustomEarthShock < Battle::Move
  def pbAdditionalEffect(user, target)
    return if target.damageState.substitute
    choice = @battle.choices[target.index]
    return if !choice || choice[0] != :UseMove
    next_move = choice[2]
    return if !next_move || !next_move.statusMove?
    target.pbFlinch(user) if @battle.pbRandom(100) < 50
  end
end

class Battle::Move::CustomCorruption < Battle::Move
  def pbPriority(user); return -1; end

  def pbEffectAgainstTarget(user, target)
    target.effects[PBEffects::SaltCure] = user.index
    @battle.pbDisplay(_INTL("{1} was afflicted with corruption!", target.pbThis))
  end
end

class Battle::Move::CustomDrainSoul < Battle::Move
  def pbEffectAfterAllHits(user, target)
    if !target.damageState.unaffected && user.effects[PBEffects::Outrage] == 0
      user.effects[PBEffects::Outrage] = 2 + @battle.pbRandom(2)
      user.currentMove = @id
    end
    user.effects[PBEffects::Outrage] -= 1 if user.effects[PBEffects::Outrage] > 0
    return if user.fainted? || target.damageState.totalHPLost <= 0
    hp_gain = (target.damageState.totalHPLost / 2.0).round
    return if hp_gain <= 0 || !user.canHeal?
    user.pbRecoverHP(hp_gain)
    @battle.pbDisplay(_INTL("{1}'s HP was restored.", user.pbThis))
  end
end

class Battle::Move::CustomRend < Battle::Move
  def pbEffectWhenDealingDamage(user, target)
    user.effects[PBEffects::RendBleed] = 3
  end
end

class Battle::Move::CustomHamstring < Battle::Move
  def pbEffectAfterAllHits(user, target)
    return if target.damageState.unaffected
    user.effects[PBEffects::HamstringLock] = 3
  end
end

class Battle::Move::CustomCounterspell < Battle::Move
  def pbFailsAgainstTarget?(user, target, show_message)
    choice = @battle.choices[target.index]
    if !choice || choice[0] != :UseMove || target.movedThisRound?
      @battle.pbDisplay(_INTL("But it failed!")) if show_message
      return true
    end
    planned_move = choice[2]
    if !planned_move || !planned_move.specialMove?
      @battle.pbDisplay(_INTL("But it failed!")) if show_message
      return true
    end
    return false
  end

  def pbEffectAgainstTarget(user, target)
    planned_move = @battle.choices[target.index][2]
    return if !planned_move
    move_type = planned_move.pbCalcType(target)
    disabled_ids = []
    target.eachMove do |m|
      next if !m
      next if m.pbCalcType(target) != move_type
      disabled_ids << m.id
    end
    return if disabled_ids.empty?
    target.effects[PBEffects::Disable] = 5
    target.effects[PBEffects::DisableMove] = disabled_ids.uniq
    @battle.pbDisplay(_INTL("{1}'s moves of that type were disabled!", target.pbThis))
  end
end

#-------------------------------------------------------------------------------
# Spin Out – harshly lowers user's Speed after dealing damage.
#-------------------------------------------------------------------------------
class Battle::Move::LowerUserSpeed2Damaging < Battle::Move
  def pbEffectWhenDealingDamage(user, target)
    return if @battle.pbAllFainted?(target.idxOwnSide)
    user.pbLowerStatStage(:SPEED, 2, user) if user.pbCanLowerStatStage?(:SPEED, user, self)
  end
end
