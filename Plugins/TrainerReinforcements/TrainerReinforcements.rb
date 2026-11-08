#===============================================================================
# Trainer reinforcements
#
# Enemy trainers can hold Pokémon back until a trigger fires, then send them
# out as a double-battle partner (1v1 becomes 1v2). Define per Pokémon in
# PBS/trainers.txt:
#
#   Pokemon = SPEAROW, 16
#       Reinforcement = 5              # after 5 completed turns
#   Pokemon = PIDGEY, 14
#       Reinforcement = Fainted, 2     # after 2 non-reinforcement party members faint
#
# Reinforcement Pokémon are not part of the trainer's main party: they are held
# back from the opening send-out and from normal switches. Faint triggers count
# only main-party faints. Once every main-party Pokémon has fainted, no further
# reinforcements are sent (queued ones are ignored). If a reinforcement is already
# on the field, later reinforcements wait until it faints, then arrive at end of
# turn. The battle continues until every released reinforcement is defeated.
#
# Supported Reinforcement values:
#   N                  -> after N turns
#   Turns, N           -> after N turns
#   Fainted, N         -> after N party members on that team have fainted
#   AfterTurns, N      -> alias for Turns
#   AfterFainted, N    -> alias for Fainted
#===============================================================================
module TrainerReinforcements
  TRIGGER_TURN_ALIASES  = ["turns", "afterturns"].freeze
  TRIGGER_FAINT_ALIASES = ["fainted", "afterfainted", "faint", "knockedout"].freeze

  module_function

  def parse_trigger(value)
    return nil if nil_or_empty?(value)
    raw = value.to_s.strip
    if raw =~ /\A(\d+)\z/
      return { :type => :turns, :count => $~[1].to_i }
    end
    parts = raw.split(/\s*,\s*/)
    if parts.length == 1
      return { :type => :turns, :count => parts[0].to_i } if parts[0] =~ /\A\d+\z/
      return nil
    end
    key = parts[0].downcase
    count = parts[1].to_i
    return nil if count <= 0
    if TRIGGER_TURN_ALIASES.include?(key)
      return { :type => :turns, :count => count }
    elsif TRIGGER_FAINT_ALIASES.include?(key)
      return { :type => :fainted, :count => count }
    end
    return nil
  end

  def assign_reinforcement_to_pokemon(pkmn, value)
    return false if !pkmn || nil_or_empty?(value)
    trigger = parse_trigger(value)
    if !trigger
      raw = value.to_s.strip
      if raw =~ /\A(\d+)\z/
        trigger = { :type => :turns, :count => $~[1].to_i }
      elsif raw =~ /\A(?:fainted|afterfainted|faint|knockedout)\s*,?\s*(\d+)\z/i
        trigger = { :type => :fainted, :count => $~[1].to_i }
      end
    end
    return false if !trigger || trigger[:count] <= 0
    pkmn.reinforcement_trigger = trigger
    pkmn.reinforcement_released = false if pkmn.reinforcement_released.nil?
    return true
  end

  PBS_TRAINERS_PATH = "PBS/trainers.txt"

  def pbs_section_matches?(section_body, tr_type, tr_name, tr_version)
    parts = section_body.split(",").map { |p| p.strip }
    return false if parts.length < 2
    sec_type = parts[0].to_sym
    sec_name = parts[1]
    sec_ver  = (parts.length >= 3 && parts[2] =~ /\A\d+\z/) ? parts[2].to_i : 0
    return sec_type == tr_type.to_sym && sec_name == tr_name && sec_ver == tr_version
  end

  # Prefer PBS text over compiled trainers.dat so comma values (e.g. Fainted,2) stay intact.
  def pbs_reinforcements_for(tr_type, tr_name, tr_version = 0)
    path = PBS_TRAINERS_PATH
    return nil if !File.exist?(path)
    ret = nil
    in_section = false
    pokemon_idx = -1
    File.foreach(path) do |line|
      line = line.sub(/#.*$/, "").strip
      next if line.empty?
      if line =~ /^\[(.+)\]$/
        in_section = pbs_section_matches?($1, tr_type, tr_name, tr_version)
        ret = [] if in_section
        pokemon_idx = -1
        next
      end
      next if !in_section
      if line =~ /^Pokemon\s*=/i
        pokemon_idx += 1
        ret[pokemon_idx] = nil if ret
      elsif line =~ /^Reinforcement\s*=\s*(.+)$/i && pokemon_idx >= 0
        ret[pokemon_idx] = $1.strip
      end
    end
    return ret
  end

  def reinforcement_value_for_pokemon(tr_data, pkmn_index)
    pbs_values = pbs_reinforcements_for(tr_data.trainer_type, tr_data.real_name, tr_data.version)
    if pbs_values && !nil_or_empty?(pbs_values[pkmn_index])
      return pbs_values[pkmn_index]
    end
    return pkmn_data_reinforcement(tr_data, pkmn_index)
  end

  def pkmn_data_reinforcement(tr_data, pkmn_index)
    return nil if !tr_data || !tr_data.pokemon[pkmn_index]
    return tr_data.pokemon[pkmn_index][:reinforcement]
  end

  def gamedata_for_trainer(trainer)
    data = GameData::Trainer.try_get(trainer.trainer_type, trainer.name, trainer.version || 0)
    return data if data
    GameData::Trainer::DATA.each_value do |tr_data|
      next if tr_data.trainer_type != trainer.trainer_type
      next if tr_data.version != (trainer.version || 0)
      return tr_data
    end
    return nil
  end

  def apply_reinforcement_metadata_from_gamedata(battle)
    battle.opponent.each_with_index do |trainer, idx_trainer|
      tr_data = gamedata_for_trainer(trainer)
      next if !tr_data
      starts = battle.pbPartyStarts(1)
      start = starts[idx_trainer]
      finish = (idx_trainer < starts.length - 1) ? starts[idx_trainer + 1] : battle.pbParty(1).length
      tr_data.pokemon.each_with_index do |_pkmn_data, i|
        party_idx = start + i
        break if party_idx >= finish
        value = reinforcement_value_for_pokemon(tr_data, i)
        next if nil_or_empty?(value)
        pkmn = battle.pbParty(1)[party_idx]
        assign_reinforcement_to_pokemon(pkmn, value)
      end
    end
  end

  def trigger_to_pbs(trigger)
    return nil if !trigger
    case trigger[:type]
    when :turns   then return trigger[:count].to_s
    when :fainted then return "Fainted, #{trigger[:count]}"
    end
    return nil
  end

  def held_back?(pkmn)
    return false if !pkmn
    return reinforcement?(pkmn) && !pkmn.reinforcement_released
  end

  def reinforcement?(pkmn)
    return false if !pkmn
    return !pkmn.reinforcement_trigger.nil?
  end

  def setup_battle(battle)
    battle.reinforcement_queue = []
    battle.reinforcement_lineup_indices = nil
    return if !battle.trainerBattle? || !battle.opponent
    apply_reinforcement_metadata_from_gamedata(battle)
    lineup = []
    battle.opponent.each_with_index do |_trainer, idx_trainer|
      starts = battle.pbPartyStarts(1)
      start = starts[idx_trainer]
      finish = (idx_trainer < starts.length - 1) ? starts[idx_trainer + 1] : battle.pbParty(1).length
      (start...finish).each do |idx_party|
        pkmn = battle.pbParty(1)[idx_party]
        next if !pkmn
        if held_back?(pkmn)
          battle.reinforcement_queue.push({
            :trainer_index => idx_trainer,
            :party_index   => idx_party,
            :type          => pkmn.reinforcement_trigger[:type],
            :count         => pkmn.reinforcement_trigger[:count],
            :released      => false
          })
        else
          lineup.push(idx_party)
        end
      end
    end
    battle.reinforcement_lineup_indices = lineup if !battle.reinforcement_queue.empty?
    battle.reinforcement_lead_faint_count = 0
  end

  def reinforcement_party_indices(battle)
    return [] if !battle.reinforcement_queue
    return battle.reinforcement_queue.map { |e| e[:party_index] }
  end

  def main_party_fainted_count(battle, idx_trainer)
    count = 0
    reinf_indices = reinforcement_party_indices(battle)
    starts = battle.pbPartyStarts(1)
    start = starts[idx_trainer]
    finish = (idx_trainer < starts.length - 1) ? starts[idx_trainer + 1] : battle.pbParty(1).length
    (start...finish).each do |i|
      pkmn = battle.pbParty(1)[i]
      next if !pkmn
      next if reinf_indices.include?(i) || reinforcement?(pkmn)
      count += 1 if pkmn.fainted?
    end
    return count
  end

  def foe_partner_battler_index(battle)
    return 3 if battle.pbSideSize(1) >= 2
    return -1
  end

  # Partner slot currently occupied by a living reinforcement Pokémon.
  def partner_slot_has_living_reinforcement?(battle)
    partner = foe_partner_battler_index(battle)
    return false if partner < 0
    battler = battle.battlers[partner]
    return false if !battler || battler.fainted?
    return reinforcement_party_indices(battle).include?(battler.pokemonIndex)
  end

  # Slot is blocked for a new reinforcement (do not recall the occupant).
  def reinforcement_slot_blocked?(battle, idx_battler)
    battler = battle.battlers[idx_battler]
    return false if !battler || battler.fainted?
    return reinforcement_party_indices(battle).include?(battler.pokemonIndex)
  end

  def on_battler_fainted(battle, idx_battler)
    return if !battle.trainerBattle? || !battle.opposes?(idx_battler)
    return if !battle.reinforcement_queue || battle.reinforcement_queue.empty?
    partner = foe_partner_battler_index(battle)
    return if partner >= 0 && idx_battler == partner
    battler = battle.battlers[idx_battler]
    return if !battler
    idx_party = battler.pokemonIndex
    return if reinforcement_party_indices(battle).include?(idx_party)
    pkmn = battle.pbParty(1)[idx_party]
    return if !pkmn || reinforcement?(pkmn)
    battle.reinforcement_lead_faint_count ||= 0
    battle.reinforcement_lead_faint_count += 1
  end

  def fainted_battler_was_reinforcement?(battle, idx_battler)
    battler = battle.battlers[idx_battler]
    return false if !battler || !battler.fainted?
    idx_party = battler.pokemonIndex
    return reinforcement_party_indices(battle).include?(idx_party) if battle.reinforcement_queue
    pkmn = battle.pbParty(idx_battler)[idx_party]
    return reinforcement?(pkmn)
  end

  def main_party_able_count(battle, idx_battler)
    count = 0
    battle.pbParty(idx_battler).each_with_index do |pkmn, idx_party|
      next if !pkmn&.able?
      next if reinforcement?(pkmn)
      next if !battle.pbIsOwner?(idx_battler, idx_party)
      count += 1
    end
    return count
  end

  def main_party_defeated?(battle, idx_trainer)
    has_main = false
    battle.eachInTeam(1, idx_trainer) do |pkmn, _i|
      next if reinforcement?(pkmn)
      has_main = true
      return false if pkmn&.able?
    end
    return has_main
  end

  def opponent_main_party_defeated?(battle)
    return false if !battle.opponent
    battle.opponent.each_with_index do |_trainer, idx_trainer|
      return false if !main_party_defeated?(battle, idx_trainer)
    end
    return true
  end

  # Released reinforcements still fighting after the main party is gone.
  def released_reinforcement_able?(battle, idx_trainer = nil)
    return false if !battle.reinforcement_queue
    battle.reinforcement_queue.each do |entry|
      next if !entry[:released]
      next if idx_trainer && entry[:trainer_index] != idx_trainer
      pkmn = battle.pbParty(1)[entry[:party_index]]
      return true if pkmn&.able?
    end
    return false
  end

  # Opponent is fully defeated only when every main Pokémon and every released
  # reinforcement has fainted. Queued reinforcements are never sent once the
  # main party is out.
  def opponent_side_fully_defeated?(battle)
    return false if !battle.opponent
    battle.opponent.each_with_index do |_trainer, idx_trainer|
      battle.eachInTeam(1, idx_trainer) do |pkmn, _i|
        next if reinforcement?(pkmn)
        return false if pkmn&.able?
      end
      return false if released_reinforcement_able?(battle, idx_trainer)
    end
    return true
  end

  # Party lineup balls at the side of the field (exclude held-back reinforcements).
  def party_has_held_back_reinforcements?(party)
    return party.any? { |pkmn| held_back?(pkmn) }
  end

  def lineup_visible_party_indices(party, party_starts)
    ret = []
    party_starts.each_with_index do |start, idx_trainer|
      finish = (idx_trainer < party_starts.length - 1) ? party_starts[idx_trainer + 1] : party.length
      (start...finish).each do |i|
        pkmn = party[i]
        next if !pkmn || held_back?(pkmn)
        ret.push(i)
      end
    end
    return ret
  end

  def lineup_party_index_at_ball(party, party_starts, idx_ball)
    indices = lineup_visible_party_indices(party, party_starts)
    return indices[idx_ball] if idx_ball < indices.length
    return -1
  end

  def lineup_ball_graphic(party, idx_party)
    return "Graphics/UI/Battle/icon_ball_empty" if idx_party < 0 || !party[idx_party]
    pkmn = party[idx_party]
    if !pkmn.able?
      return "Graphics/UI/Battle/icon_ball_faint"
    elsif pkmn.status != :NONE
      return "Graphics/UI/Battle/icon_ball_status"
    else
      return "Graphics/UI/Battle/icon_ball"
    end
  end

  # Only refresh the foe lineup bar for main-party switches, never reinforcements.
  def foe_lineup_should_animate?(battle, idx_battler, idx_party)
    return true if !battle.trainerBattle? || !battle.opposes?(idx_battler)
    return true if !battle.reinforcement_lineup_indices
    return false if reinforcement_party_indices(battle).include?(idx_party)
    if battle.battlers[idx_battler]&.fainted? &&
       fainted_battler_was_reinforcement?(battle, idx_battler)
      return false
    end
    return true
  end

  def trigger_met?(battle, entry)
    case entry[:type]
    when :turns
      return battle.turnCount >= entry[:count]
    when :fainted
      return main_party_fainted_count(battle, entry[:trainer_index]) >= entry[:count]
    end
    return false
  end

  def ready_entries(battle)
    return [] if !battle.reinforcement_queue
    return [] if partner_slot_has_living_reinforcement?(battle)
    battle.reinforcement_queue.select do |entry|
      next false if entry[:released]
      next false if main_party_defeated?(battle, entry[:trainer_index])
      next false if !trigger_met?(battle, entry)
      pkmn = battle.pbParty(1)[entry[:party_index]]
      next false if !pkmn&.able?
      next false if battle.pbFindBattler(entry[:party_index], 1)
      true
    end
  end

  def check_triggers(battle)
    return if battle.decision > 0
    return if battle.reinforcement_sending
    return if opponent_main_party_defeated?(battle)
    ready = ready_entries(battle)
    ready.each { |entry| send_reinforcement(battle, entry) }
  end

  def send_reinforcement(battle, entry)
    return if battle.reinforcement_sending
    return if main_party_defeated?(battle, entry[:trainer_index])
    party = battle.pbParty(1)
    pkmn = party[entry[:party_index]]
    return if !pkmn&.able? || entry[:released]
    return if battle.pbFindBattler(entry[:party_index], 1)
    battle.reinforcement_sending = true
    begin
      trainer = battle.opponent[entry[:trainer_index]]
      lead_alive = battle.battlers[1] && !battle.battlers[1].fainted?
      needs_expand = battle.pbSideSize(1) < 2 && lead_alive
      battle.pbDisplayPaused(_INTL("Reinforcements have arrived!"))
      battle.pbReinforcementExpandFoeSide if needs_expand
      idx_battler = battle.pbReinforcementBattlerIndex
      if idx_battler < 0
        battle.reinforcement_sending = false
        return
      end
      if reinforcement_slot_blocked?(battle, idx_battler)
        battle.reinforcement_sending = false
        return
      end
      if !battle.battlers[idx_battler]
        battle.pbCreateBattler(idx_battler, pkmn, entry[:party_index])
        battle.scene.pbReinforcementEnsureBattlerSprites(idx_battler) if battle.scene
        battle.pbDisplayBrief(_INTL("{1} sent out {2}!", trainer.full_name, pkmn.name))
        battle.pbSendOut([[idx_battler, pkmn]])
      else
        battle.pbRecallAndReplace(idx_battler, entry[:party_index])
      end
      battle.pbRegisterAIBattler(idx_battler)
      battle.pbCalculatePriority(true)
      battle.pbOnBattlerEnteringBattle([idx_battler])
      pkmn.reinforcement_released = true
      entry[:released] = true
    ensure
      battle.reinforcement_sending = false
    end
  end
end

#-------------------------------------------------------------------------------
# PBS schema + trainer loading
#-------------------------------------------------------------------------------
module GameData
  class Trainer
    # "q" keeps commas intact (e.g. "Fainted,2"); plain "s" would truncate at the comma.
    SUB_SCHEMA["Reinforcement"] = [:reinforcement, "q"]

    alias trainer_reinforcements_to_trainer to_trainer
    def to_trainer
      trainer = trainer_reinforcements_to_trainer
      pbs_values = TrainerReinforcements.pbs_reinforcements_for(@trainer_type, @real_name, @version)
      @pokemon.each_with_index do |pkmn_data, i|
        value = (pbs_values && !nil_or_empty?(pbs_values[i])) ? pbs_values[i] : pkmn_data[:reinforcement]
        next if nil_or_empty?(value)
        TrainerReinforcements.assign_reinforcement_to_pokemon(trainer.party[i], value)
      end
      return trainer
    end

    alias trainer_reinforcements_get_pokemon_property_for_PBS get_pokemon_property_for_PBS
    def get_pokemon_property_for_PBS(key, index = 0)
      ret = trainer_reinforcements_get_pokemon_property_for_PBS(key, index)
      if key == "Reinforcement" && @pokemon[index][:reinforcement]
        ret = TrainerReinforcements.trigger_to_pbs(
          TrainerReinforcements.parse_trigger(@pokemon[index][:reinforcement])
        )
      end
      return ret
    end
  end
end

class Pokemon
  attr_accessor :reinforcement_trigger
  attr_accessor :reinforcement_released
end

class Battle::Battler
  alias trainer_reinforcements_pbFaint pbFaint
  def pbFaint(showMessage = true)
    was_already_fainted = @fainted
    trainer_reinforcements_pbFaint(showMessage)
    return if was_already_fainted
    TrainerReinforcements.on_battler_fainted(@battle, @index)
  end
end

#-------------------------------------------------------------------------------
# Battle mechanics
#-------------------------------------------------------------------------------
class Battle
  attr_accessor :reinforcement_queue
  attr_accessor :reinforcement_lineup_indices
  attr_accessor :reinforcement_lead_faint_count
  attr_accessor :trainer_reinforcements_setup
  attr_accessor :reinforcement_sending

  alias trainer_reinforcements_pbSetUpSides pbSetUpSides
  def pbSetUpSides
    @trainer_reinforcements_setup = true
    ret = trainer_reinforcements_pbSetUpSides
    @trainer_reinforcements_setup = false
    return ret
  end

  alias trainer_reinforcements_eachInTeam eachInTeam
  def eachInTeam(side, idx_trainer)
    if @trainer_reinforcements_setup && side == 1 && trainerBattle?
      party = pbParty(side)
      party_starts = pbPartyStarts(side)
      idx_party_start = party_starts[idx_trainer]
      idx_party_end = (idx_trainer < party_starts.length - 1) ? party_starts[idx_trainer + 1] : party.length
      party.each_with_index do |pkmn, i|
        next if !pkmn || i < idx_party_start || i >= idx_party_end
        next if TrainerReinforcements.held_back?(pkmn)
        yield pkmn, i
      end
    else
      trainer_reinforcements_eachInTeam(side, idx_trainer) { |pkmn, i| yield pkmn, i }
    end
  end

  alias trainer_reinforcements_pbStartBattleCore pbStartBattleCore
  def pbStartBattleCore
    @reinforcement_sending = false
    TrainerReinforcements.setup_battle(self) if trainerBattle?
    trainer_reinforcements_pbStartBattleCore
  end

  alias trainer_reinforcements_pbCanSwitchIn? pbCanSwitchIn?
  def pbCanSwitchIn?(idx_battler, idx_party, party_scene = nil)
    ret = trainer_reinforcements_pbCanSwitchIn?(idx_battler, idx_party, party_scene)
    if ret && trainerBattle? && opposes?(idx_battler) &&
       TrainerReinforcements.reinforcement_party_indices(self).include?(idx_party)
      return false
    end
    return ret
  end

  alias trainer_reinforcements_pbCanChooseNonActive? pbCanChooseNonActive?
  def pbCanChooseNonActive?(idx_battler)
    if trainerBattle? && opposes?(idx_battler) && @battlers[idx_battler]&.fainted?
      partner = TrainerReinforcements.foe_partner_battler_index(self)
      return false if partner >= 0 && idx_battler == partner
      return false if TrainerReinforcements.fainted_battler_was_reinforcement?(self, idx_battler)
    end
    return trainer_reinforcements_pbCanChooseNonActive?(idx_battler)
  end

  alias trainer_reinforcements_pbAllFainted? pbAllFainted?
  def pbAllFainted?(idx_battler = 0)
    if trainerBattle? && opposes?(idx_battler) && reinforcement_queue && !reinforcement_queue.empty?
      return TrainerReinforcements.opponent_side_fully_defeated?(self)
    end
    return trainer_reinforcements_pbAllFainted?(idx_battler)
  end

  def pbReinforcementBattlerIndex
    idx_lead = 1
    if @battlers[idx_lead] && !@battlers[idx_lead].fainted?
      return 3
    end
    return idx_lead
  end

  def pbReinforcementExpandFoeSide
    return if pbSideSize(1) >= 2
    @sideSizes[1] = 2
    @scene.pbReinforcementAnimateSideExpansion(1) if @scene
  end

  def pbRegisterAIBattler(idx_battler)
    ai = instance_variable_get(:@battleAI)
    ai&.register_battler(idx_battler)
  end

  alias trainer_reinforcements_pbRecallAndReplace pbRecallAndReplace
  def pbRecallAndReplace(idxBattler, idxParty, randomReplacement = false, batonPass = false)
    idx_side = idxBattler & 1
    animate_lineup = pbSideSize(idxBattler) == 1
    refresh_party_idx = -1
    if trainerBattle? && opposes?(idxBattler) && reinforcement_lineup_indices
      animate_lineup = false if !TrainerReinforcements.foe_lineup_should_animate?(self, idxBattler, idxParty)
      if !animate_lineup && pbSideSize(idxBattler) >= 2 && @battlers[idxBattler]&.fainted? &&
         TrainerReinforcements.foe_lineup_should_animate?(self, idxBattler, idxParty)
        refresh_party_idx = @battlers[idxBattler].pokemonIndex
      end
    end
    @scene.pbRecall(idxBattler) if !@battlers[idxBattler].fainted?
    @battlers[idxBattler].pbAbilitiesOnSwitchOut
    @scene.pbShowPartyLineup(idx_side) if animate_lineup && @scene
    if refresh_party_idx >= 0 && @scene
      @scene.pbReinforcementRefreshLineupBall(idx_side, refresh_party_idx)
    end
    pbMessagesOnReplace(idxBattler, idxParty) if !randomReplacement
    pbReplace(idxBattler, idxParty, batonPass)
  end
end

# Ensure mid-battle reinforcement battlers have AI objects before command selection.
class Battle::AI
  def register_battler(idx_battler)
    @battlers ||= []
    return if !@battle.battlers[idx_battler]
    @battlers[idx_battler] = Battle::AI::AIBattler.new(self, idx_battler)
  end

  alias trainer_reinforcements_set_up set_up
  def set_up(idx_battler)
    register_battler(idx_battler) if !@battlers&.dig(idx_battler) && @battle.battlers[idx_battler]
    trainer_reinforcements_set_up(idx_battler)
  end
end

class Battle
  alias trainer_reinforcements_pbBattleLoop pbBattleLoop
  def pbBattleLoop
    @turnCount = 0
    loop do
      PBDebug.log("")
      PBDebug.log_header("===== Round #{@turnCount + 1} =====")
      if @debug && @turnCount >= 100
        @decision = pbDecisionOnTime
        PBDebug.log("")
        PBDebug.log("***Undecided after 100 rounds, aborting***")
        pbAbort
        break
      end
      PBDebug.log("")
      PBDebug.logonerr { pbCommandPhase }
      break if @decision > 0
      PBDebug.logonerr { pbAttackPhase }
      break if @decision > 0
      PBDebug.logonerr { pbEndOfRoundPhase }
      break if @decision > 0
      @turnCount += 1
      TrainerReinforcements.check_triggers(self) if trainerBattle?
      break if @decision > 0
    end
    pbEndOfBattle
  end
end

#-------------------------------------------------------------------------------
# Battle scene layout updates when reinforcements expand the foe side
#-------------------------------------------------------------------------------
class Battle::Scene::Animation::ReinforcementSideExpand < Battle::Scene::Animation
  SLIDE_DURATION = 18   # 18/20 seconds (~0.9s)

  def initialize(sprites, viewport, battle, side)
    @battle = battle
    @side   = side
    super(sprites, viewport)
  end

  def createProcesses
    @battle.battlers.each_with_index do |battler, i|
      next if !battler
      next if (i & 1) != @side
      pbAnimateBattlerSprite(@sprites["pokemon_#{i}"], i) if @sprites["pokemon_#{i}"]&.visible
      pbAnimateBattlerSprite(@sprites["shadow_#{i}"], i, true) if @sprites["shadow_#{i}"]&.visible
    end
  end

  def pbAnimateBattlerSprite(sprite, idx_battler, is_shadow = false)
    return if !sprite
    return if !is_shadow && !sprite.pkmn
    return if is_shadow && !sprite.bitmap
    new_side_size = @battle.pbSideSize(idx_battler)
    old_side_size = sprite.instance_variable_get(:@sideSize) || new_side_size
    return if old_side_size >= new_side_size
    start_x, start_y = animation_sprite_xy(sprite, is_shadow)
    end_x, end_y = target_sprite_xy(sprite, idx_battler, new_side_size, is_shadow)
    return if start_x == end_x && start_y == end_y
    origin = is_shadow ? PictureOrigin::CENTER : PictureOrigin::BOTTOM
    picture = addSprite(sprite, origin)
    picture.moveDelta(0, SLIDE_DURATION, end_x - start_x, end_y - start_y)
  end

  def animation_sprite_xy(sprite, is_shadow)
    if is_shadow
      return sprite.x, sprite.y
    end
    return sprite.instance_variable_get(:@spriteX) || sprite.x,
           sprite.instance_variable_get(:@spriteY) || sprite.y
  end

  # Compute destination coords without leaving the sprite on the new layout.
  def target_sprite_xy(sprite, idx_battler, side_size, is_shadow)
    old_size = sprite.instance_variable_get(:@sideSize)
    if is_shadow
      sprite.instance_variable_set(:@sideSize, side_size)
      sprite.pbSetPosition if sprite.bitmap
      tx = sprite.x
      ty = sprite.y
      sprite.instance_variable_set(:@sideSize, old_size)
      sprite.pbSetPosition if sprite.bitmap && old_size
      return tx, ty
    end
    old_x_extra = sprite.instance_variable_get(:@spriteXExtra)
    old_y_extra = sprite.instance_variable_get(:@spriteYExtra)
    sprite.instance_variable_set(:@sideSize, side_size)
    sprite.instance_variable_set(:@spriteXExtra, 0)
    sprite.instance_variable_set(:@spriteYExtra, 0)
    sprite.pbSetPosition
    tx = sprite.instance_variable_get(:@spriteX)
    ty = sprite.instance_variable_get(:@spriteY)
    sprite.instance_variable_set(:@sideSize, old_size)
    sprite.instance_variable_set(:@spriteXExtra, old_x_extra)
    sprite.instance_variable_set(:@spriteYExtra, old_y_extra)
    sprite.pbSetPosition
    return tx, ty
  end
end

class Battle::Scene
  def pbReinforcementAnimateSideExpansion(side)
    anim = Animation::ReinforcementSideExpand.new(@sprites, @viewport, @battle, side)
    @animations.push(anim)
    while inPartyAnimation?
      pbUpdate
    end
    pbReinforcementSnapSideSprites(side)
    pbReinforcementRefreshSideLayout(side)
  end

  def pbReinforcementSnapSideSprites(side)
    @battle.battlers.each_with_index do |battler, i|
      next if !battler
      next if (i & 1) != side
      side_size = @battle.pbSideSize(i)
      bat = @sprites["pokemon_#{i}"]
      if bat
        bat.instance_variable_set(:@sideSize, side_size)
        bat.instance_variable_set(:@spriteXExtra, 0)
        bat.instance_variable_set(:@spriteYExtra, 0)
        bat.pbSetPosition if bat.pkmn
        if bat.pkmn && bat.bitmap
          bat.visible = true
          bat.instance_variable_set(:@spriteVisible, true)
        end
      end
      sha = @sprites["shadow_#{i}"]
      if sha && bat&.pkmn
        sha.instance_variable_set(:@sideSize, side_size)
        if sha.bitmap && bat.pkmn.species_data.shows_shadow?
          sha.pbSetPosition
          sha.visible = true
        end
      end
    end
  end

  def pbReinforcementRefreshSideLayout(side)
    @battle.battlers.each_with_index do |battler, i|
      next if !battler
      next if (i & 1) != side
      side_size = @battle.pbSideSize(i)
      if @sprites["dataBox_#{i}"]
        @sprites["dataBox_#{i}"].initializeDataBoxGraphic(side_size)
        @sprites["dataBox_#{i}"].update_positions
        @sprites["dataBox_#{i}"].refresh
      end
    end
    # Refresh player-side layout too when foe side expands (1v1 -> 1v2 targeting).
    if side == 1 && @battle.pbSideSize(0) < @battle.pbSideSize(1)
      pbReinforcementSnapSideSprites(0)
      @battle.battlers.each_with_index do |battler, i|
        next if !battler
        next if (i & 1) != 0
        side_size = @battle.pbSideSize(i)
        if @sprites["dataBox_#{i}"]
          @sprites["dataBox_#{i}"].initializeDataBoxGraphic(side_size)
          @sprites["dataBox_#{i}"].update_positions
          @sprites["dataBox_#{i}"].refresh
        end
      end
    end
    old_visible = @sprites["targetWindow"]&.visible
    @sprites["targetWindow"]&.dispose
    @sprites["targetWindow"] = TargetMenu.new(@viewport, 200, @battle.sideSizes)
    @sprites["targetWindow"].visible = old_visible ? true : false
  end

  alias trainer_reinforcements_pbReinforcementResizeSide pbReinforcementResizeSide if method_defined?(:pbReinforcementResizeSide)
  def pbReinforcementResizeSide(side)
    pbReinforcementRefreshSideLayout(side)
  end

  def pbReinforcementEnsureBattlerSprites(idx_battler)
    unless @sprites["pokemon_#{idx_battler}"]
      pbCreatePokemonSprite(idx_battler)
    end
    unless @sprites["dataBox_#{idx_battler}"]
      @sprites["dataBox_#{idx_battler}"] = PokemonDataBox.new(
        @battle.battlers[idx_battler], @battle.pbSideSize(idx_battler), @viewport
      )
    end
    @lastCmd ||= []
    @lastMove ||= []
    while @lastCmd.length <= idx_battler
      @lastCmd.push(0)
      @lastMove.push(0)
    end
  end
end

#-------------------------------------------------------------------------------
# Hide held-back reinforcements from the on-screen party lineup bar
#-------------------------------------------------------------------------------
class Battle::Scene
  alias trainer_reinforcements_pbShowPartyLineup pbShowPartyLineup
  def pbShowPartyLineup(side, fullAnim = false)
    lineup_indices = nil
    if side == 1 && @battle.trainerBattle? && @battle.reinforcement_lineup_indices
      lineup_indices = @battle.reinforcement_lineup_indices
    end
    @animations.push(
      Animation::LineupAppear.new(@sprites, @viewport, side,
                                  @battle.pbParty(side), @battle.pbPartyStarts(side),
                                  fullAnim, lineup_indices)
    )
    return if fullAnim
    while inPartyAnimation?
      pbUpdate
    end
  end

  # Update one main-party ball without replaying the lineup bar animation.
  def pbReinforcementRefreshLineupBall(side, idx_party)
    return if side != 1 || !@battle.reinforcement_lineup_indices
    idx_ball = @battle.reinforcement_lineup_indices.index(idx_party)
    return if idx_ball.nil?
    ball = @sprites["partyBall_#{side}_#{idx_ball}"]
    return if !ball&.visible
    graphic = TrainerReinforcements.lineup_ball_graphic(@battle.pbParty(side), idx_party)
    ball.setBitmap(graphic) rescue nil
  end
end

class Battle::Scene::Animation::LineupAppear
  alias trainer_reinforcements_lineup_init initialize
  def initialize(sprites, viewport, side, party, partyStarts, fullAnim, lineupPartyIndices = nil)
    @lineupPartyIndices = lineupPartyIndices
    trainer_reinforcements_lineup_init(sprites, viewport, side, party, partyStarts, fullAnim)
  end

  alias trainer_reinforcements_getPartyIndexFromBallIndex getPartyIndexFromBallIndex
  def getPartyIndexFromBallIndex(idx_ball)
    if @lineupPartyIndices && @side == 1
      return @lineupPartyIndices[idx_ball] if idx_ball < @lineupPartyIndices.length
      return -1
    end
    ret = trainer_reinforcements_getPartyIndexFromBallIndex(idx_ball)
    return ret if ret < 0 || @side != 1
    return -1 if TrainerReinforcements.held_back?(@party[ret])
    return ret
  end
end

if $DEBUG
  MenuHandlers.add(:debug_menu, :test_trainer_reinforcements, {
    "name"        => _INTL("Test trainer reinforcements"),
    "parent"      => :battle_menu,
    "description" => _INTL("Ben v2: 3 main Pokémon; Ekans after 3 turns, Pidgey after 2 main faints."),
    "effect"      => proc {
      setBattleRule("canLose")
      TrainerBattle.start(:YOUNGSTER, "Ben", 2)
      next false
    }
  })
end
