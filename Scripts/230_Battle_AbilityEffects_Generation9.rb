#===============================================================================
# Gen 9 ability handlers (Supplemental — loads after 230_Battle_AbilityEffects.rb)
# Notes:
# - Commander (Tatsugiri + Dondozo positioning) is not simulated (Essentials lacks that mechanic).
# - Booster Energy grants Paradox boosts only if item :BOOSTERENERGY exists in items.txt.
#===============================================================================
module Battle::Gen9AbilityEffects
  RUIN_MULT = 0.75

  module_function

  def ruin_bearer(battle, ability_id)
    battle.allBattlers.find { |b| !b.fainted? && b.hasActiveAbility?(ability_id) && b.abilityActive? }
  end

  def apply_ruin_multipliers(move, user, target, mults, type)
    return if !user || !target
    b_tab = ruin_bearer(move.battle, :TABLETSOFRUIN)
    if b_tab && user.index != b_tab.index && move.physicalMove?(type)
      mults[:attack_multiplier] *= RUIN_MULT
    end
    b_ves = ruin_bearer(move.battle, :VESSELOFRUIN)
    if b_ves && user.index != b_ves.index && move.specialMove?(type)
      mults[:attack_multiplier] *= RUIN_MULT
    end
    b_sw = ruin_bearer(move.battle, :SWORDOFRUIN)
    if b_sw && target.index != b_sw.index && move.physicalMove?(type)
      mults[:defense_multiplier] *= RUIN_MULT
    end
    b_bead = ruin_bearer(move.battle, :BEADSOFRUIN)
    if b_bead && target.index != b_bead.index && move.specialMove?(type)
      mults[:defense_multiplier] *= RUIN_MULT
    end
  end

  def paradox_boost_active?(battler, ability_id)
    return false unless battler&.hasActiveAbility?(ability_id) && battler.abilityActive?
    if ability_id == :PROTOSYNTHESIS
      return true if [:Sun, :HarshSun].include?(battler.effectiveWeather)
    elsif ability_id == :QUARKDRIVE
      return true if battler.battle.field.terrain == :Electric && battler.affectedByTerrain?
    end
    return true if GameData::Item.exists?(:BOOSTERENERGY) && battler.hasActiveItem?(:BOOSTERENERGY)
    false
  end

  def highest_battle_stat(battler)
    {
      :ATTACK => battler.attack,
      :DEFENSE => battler.defense,
      :SPECIAL_ATTACK => battler.spatk,
      :SPECIAL_DEFENSE => battler.spdef,
      :SPEED => battler.speed
    }.max_by { |_k, v| v }[0]
  end
end

class Battle
  def suppress_opportunist_depth
    @suppress_opportunist_depth ||= 0
  end

  def suppress_opportunist_depth=(v)
    @suppress_opportunist_depth = v
  end

  def suppress_opportunist?
    suppress_opportunist_depth > 0
  end

  def suppress_opportunist
    self.suppress_opportunist_depth += 1
    yield
  ensure
    self.suppress_opportunist_depth -= 1
  end

  def pbTryOpportunistAfterStatGain(gainer, stat, increment)
    return if suppress_opportunist?
    return if increment <= 0
    suppress_opportunist do
      allBattlers.each do |b|
        next if b.fainted?
        next unless b.hasActiveAbility?(:OPPORTUNIST) && b.abilityActive?
        next unless gainer.opposes?(b)
        b.pbRaiseStatStage(stat, increment, b)
      end
    end
  end
end

#-------------------------------------------------------------------------------
Battle::AbilityEffects::SpeedCalc.add(:PROTOSYNTHESIS,
  proc { |ability, battler, mult|
    next mult unless Battle::Gen9AbilityEffects.paradox_boost_active?(battler, :PROTOSYNTHESIS)
    next mult * 1.3 if Battle::Gen9AbilityEffects.highest_battle_stat(battler) == :SPEED
    next mult
  }
)

Battle::AbilityEffects::SpeedCalc.add(:QUARKDRIVE,
  proc { |ability, battler, mult|
    next mult unless Battle::Gen9AbilityEffects.paradox_boost_active?(battler, :QUARKDRIVE)
    next mult * 1.3 if Battle::Gen9AbilityEffects.highest_battle_stat(battler) == :SPEED
    next mult
  }
)

Battle::AbilityEffects::PriorityBracketChange.add(:MYCELIUMMIGHT,
  proc { |ability, battler, battle|
    move = battle.choices[battler.index][2]
    next -1 if move&.statusMove?
    next 0
  }
)

Battle::AbilityEffects::MoveBlocking.copy(:DAZZLING, :ARMORTAIL)

#-------------------------------------------------------------------------------
# Move immunity
#-------------------------------------------------------------------------------
Battle::AbilityEffects::MoveImmunity.add(:GOODASGOLD,
  proc { |ability, user, target, move, _type, battle, show_message|
    next false if user.index == target.index || !move.statusMove?
    if show_message
      battle.pbShowAbilitySplash(target)
      if Battle::Scene::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("It doesn't affect {1}...", target.pbThis(true)))
      else
        battle.pbDisplay(_INTL("{1}'s {2} avoided the move!", target.pbThis, target.abilityName))
      end
      battle.pbHideAbilitySplash(target)
    end
    next true
  }
)

Battle::AbilityEffects::MoveImmunity.add(:EARTHEATER,
  proc { |ability, user, target, move, type, battle, show_message|
    next target.pbMoveImmunityHealingAbility(user, move, type, :GROUND, show_message)
  }
)

Battle::AbilityEffects::MoveImmunity.add(:WELLBAKEDBODY,
  proc { |ability, user, target, move, type, battle, show_message|
    next false if user.index == target.index || move.statusMove?
    next false if type != :FIRE
    if show_message
      battle.pbShowAbilitySplash(target)
      if target.pbCanRaiseStatStage?(:DEFENSE, target)
        target.pbRaiseStatStageByAbility(:DEFENSE, 2, target, false)
      elsif Battle::Scene::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("It doesn't affect {1}...", target.pbThis(true)))
      else
        battle.pbDisplay(_INTL("{1}'s {2} made the attack harmless!", target.pbThis, target.abilityName))
      end
      battle.pbHideAbilitySplash(target)
    end
    next true
  }
)

Battle::AbilityEffects::MoveImmunity.add(:WINDRIDER,
  proc { |ability, user, target, move, type, battle, show_message|
    next false if user.index == target.index || move.statusMove?
    next false if !move.windMove? || !move.damagingMove?
    if show_message
      battle.pbShowAbilitySplash(target)
      target.pbRaiseStatStageByAbility(:ATTACK, 1, target, false)
      if Battle::Scene::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("It doesn't affect {1}...", target.pbThis(true)))
      else
        battle.pbDisplay(_INTL("{1}'s {2} made the attack harmless!", target.pbThis, target.abilityName))
      end
      battle.pbHideAbilitySplash(target)
    end
    next true
  }
)

Battle::AbilityEffects::OnBeingHit.copy(:MUMMY, :LINGERINGAROMA)

Battle::AbilityEffects::OnBeingHit.add(:ELECTROMORPHOSIS,
  proc { |ability, user, target, move, battle|
    next if !move.damagingMove?
    next if target.damageState.substitute
    target.effects[PBEffects::ElectromorphosisCharge] = true
    battle.pbShowAbilitySplash(target)
    battle.pbDisplay(_INTL("{1} became charged with electricity!", target.pbThis))
    battle.pbHideAbilitySplash(target)
  }
)

Battle::AbilityEffects::OnBeingHit.add(:WINDPOWER,
  proc { |ability, user, target, move, battle|
    next if !move.damagingMove? || !move.windMove?
    next if target.damageState.substitute
    target.effects[PBEffects::WindPowerCharge] = true
    battle.pbShowAbilitySplash(target)
    battle.pbDisplay(_INTL("{1} became charged with electricity!", target.pbThis))
    battle.pbHideAbilitySplash(target)
  }
)

Battle::AbilityEffects::OnBeingHit.add(:SEEDSOWER,
  proc { |ability, user, target, move, battle|
    next if !move.damagingMove?
    next if target.damageState.substitute
    next if battle.field.terrain == :Grassy
    battle.pbStartTerrain(target, :Grassy)
  }
)

Battle::AbilityEffects::OnBeingHit.add(:TOXICDEBRIS,
  proc { |ability, user, target, move, battle|
    next if !move.damagingMove? || !move.physicalMove?(move.calcType)
    next if target.damageState.substitute
    side = user.pbOwnSide
    next if side.effects[PBEffects::ToxicSpikes] >= 2
    battle.pbShowAbilitySplash(target)
    side.effects[PBEffects::ToxicSpikes] += 1
    battle.pbDisplay(_INTL("Poison spikes were scattered all around {1}'s feet!",
       battle.pbGetTeamNames(user.idxOwnSide)[0]))
    battle.pbHideAbilitySplash(target)
  }
)

Battle::AbilityEffects::OnBeingHit.add(:THERMALEXCHANGE,
  proc { |ability, user, target, move, battle|
    next if move.calcType != :FIRE || !move.damagingMove?
    next if target.damageState.substitute
    target.pbRaiseStatStageByAbility(:ATTACK, 1, target)
  }
)

#-------------------------------------------------------------------------------
# Status immunity
#-------------------------------------------------------------------------------
Battle::AbilityEffects::StatusImmunity.add(:THERMALEXCHANGE,
  proc { |ability, battler, status|
    next true if status == :BURN
  }
)

Battle::AbilityEffects::StatusImmunity.add(:PURIFYINGSALT,
  proc { |ability, battler, status|
    next true if [:SLEEP, :POISON, :BURN, :PARALYSIS, :FROZEN].include?(status)
  }
)

#-------------------------------------------------------------------------------
# Switch-in
#-------------------------------------------------------------------------------
Battle::AbilityEffects::OnSwitchIn.add(:COSTAR,
  proc { |ability, battler, battle, switch_in|
    next if battle.pbSideBattlerCount(battler.index) < 2
    ally = battler.allAllies.find { |a| !a.fainted? }
    next if !ally
    battle.pbShowAbilitySplash(battler)
    GameData::Stat.each_battle { |s| battler.stages[s.id] = ally.stages[s.id] }
    battle.pbDisplay(_INTL("{1} copied its ally's stat changes!", battler.pbThis))
    battle.pbHideAbilitySplash(battler)
  }
)

Battle::AbilityEffects::OnSwitchIn.add(:HOSPITALITY,
  proc { |ability, battler, battle, switch_in|
    healed = false
    battler.allAllies.each do |ally|
      next if ally.fainted? || !ally.canHeal?
      amt = (ally.totalhp / 4.0).floor
      next if amt <= 0
      battle.pbShowAbilitySplash(battler) unless healed
      healed = true
      ally.pbRecoverHP(amt)
      battle.pbDisplay(_INTL("{1}'s HP was restored.", ally.pbThis))
    end
    battle.pbHideAbilitySplash(battler) if healed
  }
)

Battle::AbilityEffects::OnSwitchIn.add(:EMBODYASPECT,
  proc { |ability, battler, battle, switch_in|
    next unless battler.isSpecies?(:OGERPON)
    stat = case battler.form
           when 0 then :SPEED
           when 1 then :SPECIAL_DEFENSE
           when 2 then :ATTACK
           when 3 then :DEFENSE
           end
    next if !stat
    battler.pbRaiseStatStageByAbility(stat, 1, battler)
  }
)

Battle::AbilityEffects::OnSwitchIn.add(:SUPERSWEETSYRUP,
  proc { |ability, battler, battle, switch_in|
    battle.pbShowAbilitySplash(battler)
    battle.allOtherSideBattlers(battler.index).each do |foe|
      next if foe.fainted?
      foe.pbLowerStatStage(:EVASION, 1, battler)
    end
    battle.pbHideAbilitySplash(battler)
  }
)

Battle::AbilityEffects::OnSwitchIn.add(:TERAFORMZERO,
  proc { |ability, battler, battle, switch_in|
    clear_weather = battle.field.weather != :None
    clear_terrain = battle.field.terrain != :None
    next if !clear_weather && !clear_terrain
    battle.pbShowAbilitySplash(battler)
    if clear_weather
      battle.field.weather = :None
      battle.field.weatherDuration = -1
      battle.pbDisplay(_INTL("The weather faded away!"))
      battle.allBattlers.each { |b| b.pbCheckFormOnWeatherChange }
    end
    if clear_terrain
      battle.field.terrain = :None
      battle.field.terrainDuration = -1
      battle.pbDisplay(_INTL("The terrain disappeared!"))
      battle.allBattlers.each { |b| b.pbAbilityOnTerrainChange }
    end
    battle.pbHideAbilitySplash(battler)
  }
)

Battle::AbilityEffects::OnSwitchIn.add(:TERASHIFT,
  proc { |ability, battler, battle, switch_in|
    next if !battler.isSpecies?(:TERAPAGOS) || battler.form != 0
    battle.pbShowAbilitySplash(battler)
    battler.pbChangeForm(1, _INTL("{1} transformed!", battler.pbThis))
    battle.pbHideAbilitySplash(battler)
  }
)

Battle::AbilityEffects::OnSwitchIn.add(:ORICHALCUMPULSE,
  proc { |ability, battler, battle, switch_in|
    next if [:HarshSun, :HeavyRain, :StrongWinds].include?(battle.field.weather)
    battle.pbStartWeather(battler, :Sun, true)
  }
)

Battle::AbilityEffects::OnSwitchIn.add(:HADRONENGINE,
  proc { |ability, battler, battle, switch_in|
    next if battle.field.terrain == :Electric
    battle.pbStartTerrain(battler, :Electric)
  }
)

Battle::AbilityEffects::OnSwitchOut.add(:ZEROTOHERO,
  proc { |ability, battler, battle|
    next if !battler.isSpecies?(:PALAFIN) || battler.form != 0
    battler.pokemon.form = 1 if battler.pokemon
    battler.form = 1
    battle.scene&.pbChangePokemon(battler, battler.pokemon)
  }
)

#-------------------------------------------------------------------------------
Battle::AbilityEffects::ModifyMoveBaseType.add(:DRAGONIZE,
  proc { |ability, user, move, type|
    next if type != :NORMAL || !GameData::Type.exists?(:DRAGON)
    move.powerBoost = true
    next :DRAGON
  }
)
Battle::AbilityEffects::DamageCalcFromUser.copy(:AERILATE, :DRAGONIZE)

#-------------------------------------------------------------------------------
# Damage modifiers
#-------------------------------------------------------------------------------
Battle::AbilityEffects::DamageCalcFromUser.add(:PROTOSYNTHESIS,
  proc { |ability, user, target, move, mults, power, type|
    next unless Battle::Gen9AbilityEffects.paradox_boost_active?(user, :PROTOSYNTHESIS)
    hs = Battle::Gen9AbilityEffects.highest_battle_stat(user)
    mults[:attack_multiplier] *= 1.3 if hs == :ATTACK && move.physicalMove?(type)
    mults[:attack_multiplier] *= 1.3 if hs == :SPECIAL_ATTACK && move.specialMove?(type)
  }
)

Battle::AbilityEffects::DamageCalcFromUser.add(:QUARKDRIVE,
  proc { |ability, user, target, move, mults, power, type|
    next unless Battle::Gen9AbilityEffects.paradox_boost_active?(user, :QUARKDRIVE)
    hs = Battle::Gen9AbilityEffects.highest_battle_stat(user)
    mults[:attack_multiplier] *= 1.3 if hs == :ATTACK && move.physicalMove?(type)
    mults[:attack_multiplier] *= 1.3 if hs == :SPECIAL_ATTACK && move.specialMove?(type)
  }
)

Battle::AbilityEffects::DamageCalcFromTarget.add(:PROTOSYNTHESIS,
  proc { |ability, user, target, move, mults, power, type|
    next unless Battle::Gen9AbilityEffects.paradox_boost_active?(target, :PROTOSYNTHESIS)
    hs = Battle::Gen9AbilityEffects.highest_battle_stat(target)
    mults[:defense_multiplier] *= 1.3 if hs == :DEFENSE && move.physicalMove?(type)
    mults[:defense_multiplier] *= 1.3 if hs == :SPECIAL_DEFENSE && move.specialMove?(type)
  }
)

Battle::AbilityEffects::DamageCalcFromTarget.add(:QUARKDRIVE,
  proc { |ability, user, target, move, mults, power, type|
    next unless Battle::Gen9AbilityEffects.paradox_boost_active?(target, :QUARKDRIVE)
    hs = Battle::Gen9AbilityEffects.highest_battle_stat(target)
    mults[:defense_multiplier] *= 1.3 if hs == :DEFENSE && move.physicalMove?(type)
    mults[:defense_multiplier] *= 1.3 if hs == :SPECIAL_DEFENSE && move.specialMove?(type)
  }
)

Battle::AbilityEffects::DamageCalcFromUser.add(:ORICHALCUMPULSE,
  proc { |ability, user, target, move, mults, power, type|
    next unless [:Sun, :HarshSun].include?(user.effectiveWeather)
    mults[:attack_multiplier] *= 1.3 if move.physicalMove?(type)
  }
)

Battle::AbilityEffects::DamageCalcFromUser.add(:HADRONENGINE,
  proc { |ability, user, target, move, mults, power, type|
    next unless user.battle.field.terrain == :Electric && user.affectedByTerrain?
    mults[:attack_multiplier] *= 1.3 if move.specialMove?(type)
  }
)

Battle::AbilityEffects::DamageCalcFromUser.add(:MEGASOL,
  proc { |ability, user, target, move, mults, power, type|
    next if [:Sun, :HarshSun].include?(user.effectiveWeather)
    case type
    when :FIRE
      mults[:final_damage_multiplier] *= 1.5
    when :WATER
      mults[:final_damage_multiplier] /= 2
    end
  }
)

Battle::AbilityEffects::DamageCalcFromUser.add(:SUPREMEOVERLORD,
  proc { |ability, user, target, move, mults, power, type|
    party = user.battle.pbParty(user.index)
    faint_count = party.count { |p| p && !p.egg? && p.hp <= 0 }
    faint_count = [faint_count, 5].min
    next if faint_count <= 0
    mults[:final_damage_multiplier] *= (1.0 + faint_count * 0.1)
  }
)

Battle::AbilityEffects::DamageCalcFromUser.add(:SHARPNESS,
  proc { |ability, user, target, move, mults, power, type|
    mults[:power_multiplier] *= 1.5 if move.slicingMove?
  }
)

Battle::AbilityEffects::DamageCalcFromUser.add(:ROCKYPAYLOAD,
  proc { |ability, user, target, move, mults, power, type|
    mults[:attack_multiplier] *= 1.5 if type == :ROCK
  }
)

Battle::AbilityEffects::DamageCalcFromTarget.add(:PURIFYINGSALT,
  proc { |ability, user, target, move, mults, power, type|
    mults[:final_damage_multiplier] /= 2 if type == :GHOST
  }
)

Battle::AbilityEffects::DamageCalcFromTargetNonIgnorable.add(:TERASHELL,
  proc { |ability, user, target, move, mults, power, type|
    next if !move.damagingMove?
    next unless target.hp == target.totalhp
    mults[:final_damage_multiplier] /= 2
  }
)

#-------------------------------------------------------------------------------
Battle::AbilityEffects::AfterMoveUseFromTarget.add(:ANGERSHELL,
  proc { |ability, target, user, move, switched_battlers, battle|
    next if !move.damagingMove?
    next if !target.droppedBelowHalfHP
    battle.pbShowAbilitySplash(target)
    target.pbLowerStatStageByAbility(:DEFENSE, 1, target, false)
    target.pbLowerStatStageByAbility(:SPECIAL_DEFENSE, 1, target, false)
    target.pbRaiseStatStageByAbility(:ATTACK, 1, target, false)
    target.pbRaiseStatStageByAbility(:SPECIAL_ATTACK, 1, target, false)
    target.pbRaiseStatStageByAbility(:SPEED, 1, target, false)
    battle.pbHideAbilitySplash(target)
  }
)

Battle::AbilityEffects::OnDealingHit.add(:TOXICCHAIN,
  proc { |ability, user, target, move, battle|
    next if !move.damagingMove?
    next if battle.pbRandom(100) >= 30
    battle.pbShowAbilitySplash(user)
    if target.hasActiveAbility?(:SHIELDDUST) && !battle.moldBreaker
      battle.pbShowAbilitySplash(target)
      if !Battle::Scene::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1} is unaffected!", target.pbThis))
      end
      battle.pbHideAbilitySplash(target)
    elsif target.pbCanPoison?(user, Battle::Scene::USE_ABILITY_SPLASH)
      msg = nil
      if !Battle::Scene::USE_ABILITY_SPLASH
        msg = _INTL("{1}'s {2} badly poisoned {3}!", user.pbThis, user.abilityName, target.pbThis(true))
      end
      target.pbPoison(user, msg, true)
    end
    battle.pbHideAbilitySplash(user)
  }
)
