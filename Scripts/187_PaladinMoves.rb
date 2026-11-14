#===============================================================================
# Paladin moves.
#
# Seal items are not in the game yet. JUDGEMENT_SEALS is the hook they will
# use. Leave it empty until those items exist. With no matching Seal, Judgement
# stays Normal and has no secondary effect.
#===============================================================================
module PaladinMoves
  # item_id => [type, effect]
  # type is a type symbol such as :ELECTRIC, :WATER, or :GROUND.
  # effect is the 20% rider, or nil for a type change only:
  #   :BURN, :PARALYZE, :POISON, :SLEEP, :FROSTBITE, :FLINCH, :CONFUSE
  # An unknown effect is ignored so a bad entry cannot crash a battle.
  JUDGEMENT_SEALS = {
    # :SEALOFJUSTICE => [:ELECTRIC, :PARALYZE]
  }.freeze

  CONSECRATION_TERRAIN_TURNS = 5

  # Abilities that absorb an Electric move. Holy Shock's ally heal ignores
  # these. Lightning Rod still redirects first; a redirected hit is an attack.
  HOLY_SHOCK_IGNORED_ABSORBS = [:VOLTABSORB, :MOTORDRIVE, :LIGHTNINGROD].freeze

  def self.judgement_seal(item_id, item_active)
    return nil if !item_active || !item_id
    entry = JUDGEMENT_SEALS[item_id]
    return nil if !entry.is_a?(Array) || entry.empty?
    type = entry[0]
    return nil if !type || !GameData::Type.exists?(type)
    return [type, entry[1]]
  end

  # redirected: the target changed after Lightning Rod, Storm Drain, Follow Me,
  # or Spotlight. A redirected Holy Shock is always an attack.
  def self.holy_shock_heals?(redirected, target_is_ally)
    return false if redirected
    return target_is_ally ? true : false
  end

  # :heal, :damage, or nil. Grounded allies of the setter heal. Grounded foes
  # that can take indirect damage are seared. Anyone else is skipped.
  def self.consecration_tick(same_side, grounded, can_heal, takes_indirect)
    return nil if !grounded
    return :heal if same_side && can_heal
    return :damage if !same_side && takes_indirect
    return nil
  end
end

#===============================================================================
# Normal by default. A held Seal (see PaladinMoves::JUDGEMENT_SEALS) sets the
# type and the 20% secondary effect. Category follows the user's higher Attack
# or Special Attack, including stat stages, same as Photon Geyser. Ties stay
# special.
#===============================================================================
class Battle::Move::CustomJudgement < Battle::Move::CustomCategoryByHigherAttack
  def pbJudgementSeal(user)
    return nil if !user
    return PaladinMoves.judgement_seal(user.item_id, user.itemActive?)
  end

  def pbBaseType(user)
    seal = pbJudgementSeal(user)
    ret = (seal) ? seal[0] : :NORMAL
    if ret && user.abilityActive?
      modified = Battle::AbilityEffects.triggerModifyMoveBaseType(user.ability, user, self, ret)
      ret = modified if modified
    end
    return ret
  end

  # No Seal means no rider, so Sheer Force does not treat the move as having one.
  def pbAdditionalEffectChance(user, target, effectChance = 0)
    seal = pbJudgementSeal(user)
    return 0 if !seal || !seal[1]
    return super
  end

  def pbAdditionalEffect(user, target)
    return if target.damageState.substitute
    seal = pbJudgementSeal(user)
    return if !seal
    case seal[1]
    when :BURN
      target.pbBurn(user) if target.pbCanBurn?(user, false, self)
    when :PARALYZE
      target.pbParalyze(user) if target.pbCanParalyze?(user, false, self)
    when :POISON
      target.pbPoison(user) if target.pbCanPoison?(user, false, self)
    when :SLEEP
      target.pbSleep(user) if target.pbCanSleep?(user, false, self)
    when :FROSTBITE
      target.pbFrostbite(user) if target.pbCanFrostbite?(user, false, self)
    when :FLINCH
      target.pbFlinch(user)
    when :CONFUSE
      target.pbConfuse(user) if target.pbCanConfuse?(user, false, self)
    end
  end
end

#===============================================================================
# Consecrates the ground for CONSECRATION_TERRAIN_TURNS. Replaces other
# terrain. At end of round, grounded Pokémon on the user's side heal 1/16 max
# HP, and grounded foes lose 1/16 max HP.
#===============================================================================
class Battle::Move::CustomConsecration < Battle::Move
  def pbMoveFailed?(user, targets)
    # Same-side recast fails, matching Grassy Terrain. The foe's Consecration
    # is a different effect (it sears this side), so it can be replaced.
    if @battle.field.terrain == :Consecration &&
       @battle.field.terrainSetterSide == user.idxOwnSide
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbEffectGeneral(user)
    # pbStartTerrain no-ops when the terrain symbol is unchanged, which would
    # leave the foe's setter side in place. Clear it first so the new cast
    # replaces that Consecration.
    if @battle.field.terrain == :Consecration
      @battle.field.terrain = :None
      @battle.field.terrainSetterSide = nil
    end
    @battle.pbStartTerrain(user, :Consecration, true, PaladinMoves::CONSECRATION_TERRAIN_TURNS)
  end
end

#===============================================================================
# Like Healing Wish, but the user does not faint. The user switches out and
# the replacement is fully healed. Fails when there is nobody to switch in.
# The position's HealingWish flag is what heals the replacement, so the heal
# still uses Healing Wish's entry code. The value :LAYONHANDS only changes
# the message.
#===============================================================================
class Battle::Move::CustomLayOnHands < Battle::Move
  def healingMove?; return true; end
  def canSnatch?;   return true; end

  def pbMoveFailed?(user, targets)
    if !@battle.pbCanChooseNonActive?(user.index)
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbEndOfMoveUsageEffect(user, targets, numHits, switchedBattlers)
    return if user.fainted? || numHits == 0
    return if !@battle.pbCanChooseNonActive?(user.index)
    @battle.pbDisplay(_INTL("{1} went back to {2}!", user.pbThis,
                            @battle.pbGetOwnerName(user.index)))
    @battle.pbPursuit(user.index)
    return if user.fainted?
    newPkmn = @battle.pbGetReplacementPokemonIndex(user.index)   # Owner chooses
    return if newPkmn < 0
    @battle.positions[user.index].effects[PBEffects::HealingWish] = :LAYONHANDS
    @battle.pbRecallAndReplace(user.index, newPkmn)
    @battle.pbClearChoice(user.index)   # Replacement Pokémon does nothing this round
    @battle.moldBreaker = false
    @battle.pbOnBattlerEnteringBattle(user.index)
    switchedBattlers.push(user.index)
  end
end

#===============================================================================
# Same :FROZEN Ice Block condition as CustomIceBlock. Only the messages differ.
# The marker lives on the Pokémon so it survives a forced switch and the next
# battle. Ice Block never sets it.
#===============================================================================
class Battle::Move::CustomDivineShield < Battle::Move::CustomIceBlock
  def pbEffectGeneral(user)
    user.pokemon.divine_shield = true if user.pokemon
    user.pbFreeze(_INTL("{1} wrapped itself in a divine shield!", user.pbThis))
  end
end

#===============================================================================
# Pollen Puff's heal-or-damage split, as an Electric move.
# Aimed at a foe: normal Electric rules.
# Aimed at an ally, and nothing redirects it: heal half max HP. The heal
# ignores Ground and Electric-absorbing abilities.
# Lightning Rod (and any other redirect pbChangeTargets applies) still pulls
# the move. The redirected hit is an attack, so the Lightning Rod holder is
# immune, gains its Special Attack, and nobody is healed.
#===============================================================================
class Battle::Move::CustomHolyShock < Battle::Move::HealAllyOrDamageFoe
  def initialize(battle, move)
    super
    @healing = false
    @redirect_checked = false
    @pre_redirect_index = nil
  end

  # Runs at the start of move use, before targeting, so a previous turn cannot
  # leave a stale redirect snapshot.
  def pbCalcType(user)
    @redirect_checked = false
    @pre_redirect_index = nil
    return super
  end

  # Called from pbChangeTargets before Lightning Rod, Storm Drain, Follow Me,
  # and Spotlight change the target. If those return early, this never runs
  # and the move is not treated as redirected.
  def pbModifyTargets(targets, user)
    @redirect_checked = true
    @pre_redirect_index = targets[0].index if targets[0]
  end

  def pbOnStartUse(user, targets)
    redirected = false
    target_is_ally = false
    if targets.length > 0 && targets[0]
      redirected = @redirect_checked && targets[0].index != @pre_redirect_index
      target_is_ally = !user.opposes?(targets[0])
    end
    @redirect_checked = false
    @pre_redirect_index = nil
    @healing = PaladinMoves.holy_shock_heals?(redirected, target_is_ally)
  end

  def pbImmunityByAbility(user, target, show_message)
    if @healing && target.abilityActive? &&
       PaladinMoves::HOLY_SHOCK_IGNORED_ABSORBS.include?(target.ability_id)
      return false
    end
    return super
  end
end
