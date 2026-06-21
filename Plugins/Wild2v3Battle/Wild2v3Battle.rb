#===============================================================================
# Wild 2v3 battles: up to two player Pokémon vs three event-scripted wild
# Pokémon at once. Uses 1v3 if the player only has one able Pokémon.
#
# Event example (species + level):
#   setBattleRule("cannotRun")
#   setBattleRule("canLose")
#   pbCreatureEncounter_set_rank(:BOSS)
#   pbWild2v3Battle(:CHARIZARD, 30, :BLASTOISE, 30, :VENUSAUR, 30)
#
# Event example (custom Pokémon):
#   boss = pbCreateEventPokemon(:GYARADOS, 35, {
#     :moves => [:DRAGONDANCE, :WATERFALL, :EARTHQUAKE, :ICEFANG],
#     :ability => :INTIMIDATE,
#     :item => :WACSBERRY
#   })
#   pbWild2v3Battle(boss, boss2, boss3)
#===============================================================================
module Wild2v3Battle
  FOE_COUNT = 3
  PLAYER_SIDE_SIZE = 2

  module_function

  # Creates a Pokémon for scripted battles without wild encounter randomizers
  # (held items, shiny rolls, Pokérus, lead-ability effects, etc.).
  # Options hash keys:
  #   :form, :moves, :ability, :ability_index, :item, :gender, :nature,
  #   :shiny, :super_shiny, :name, :iv, :ev, :happiness, :poke_ball
  def create_event_pokemon(species, level, options = {})
    species_id = GameData::Species.get(species).species
    pkmn = Pokemon.new(species_id, level, $player, false)
    pkmn.obtain_method = 4   # Fateful encounter
    pkmn.form_simple = options[:form] if options[:form]
    pkmn.item = options[:item] if options[:item]
    if options[:moves] && !options[:moves].empty?
      pkmn.moves.clear
      options[:moves].each { |move| pkmn.learn_move(move) }
    else
      pkmn.reset_moves
    end
    pkmn.ability_index = options[:ability_index] if options[:ability_index]
    pkmn.ability = options[:ability] if options[:ability]
    pkmn.gender = options[:gender] if !options[:gender].nil?
    pkmn.shiny = options[:shiny] ? true : false if !options[:shiny].nil?
    pkmn.super_shiny = options[:super_shiny] ? true : false if !options[:super_shiny].nil?
    pkmn.nature = options[:nature] if options[:nature]
    if options[:iv]
      GameData::Stat.each_main { |s| pkmn.iv[s.id] = options[:iv][s.id] if options[:iv][s.id] }
    end
    if options[:ev]
      GameData::Stat.each_main { |s| pkmn.ev[s.id] = options[:ev][s.id] if options[:ev][s.id] }
    end
    pkmn.happiness = options[:happiness] if options[:happiness]
    pkmn.name = options[:name] if options[:name] && !options[:name].empty?
    pkmn.poke_ball = options[:poke_ball] if options[:poke_ball]
    pkmn.calc_stats
    return pkmn
  end

  def resolve_foes(*args)
    foes = WildBattle.generate_foes(*args)
    if foes.length != FOE_COUNT
      raise _INTL("Wild 2v3 battles require exactly {1} opposing Pokémon (got {2}).",
                  FOE_COUNT, foes.length)
    end
    return foes
  end

  def prepare_rules(intro_text = nil)
    if $game_temp.battle_rules["size"].nil?
      player_size = ($player.able_pokemon_count >= 2) ? 2 : 1
      setBattleRule("#{player_size}v3")
    end
    setBattleRule("noPartner")
    $game_temp.wild_2v3_battle = true
    $game_temp.wild_2v3_intro = intro_text if intro_text && !intro_text.to_s.empty?
  end

  # Starts a wild battle vs three foes (2v3 or 1v3 depending on party size).
  # Pass three Pokémon (Pokemon objects) or three species/level pairs.
  # Optional keyword args:
  #   :intro => custom text shown when the battle begins (nil = default message)
  # Returns true if the player did not lose or draw (same as WildBattle.start).
  def start(*args, intro: nil)
    if args.last.is_a?(Hash) && args.last.key?(:intro)
      intro = args.pop[:intro]
    end
    prepare_rules(intro)
    foes = resolve_foes(*args)
    outcome = WildBattle.start_core(*foes)
    return outcome != 2 && outcome != 5
  end
end

class Game_Temp
  unless method_defined?(:wild_2v3_battle)
    attr_accessor :wild_2v3_battle
    attr_accessor :wild_2v3_intro
  end

  alias wild_2v3_orig_clear_battle_rules clear_battle_rules
  def clear_battle_rules
    wild_2v3_orig_clear_battle_rules
    @wild_2v3_battle = false
    @wild_2v3_intro = nil
  end
end

class Battle
  attr_accessor :wild_2v3_battle
  attr_accessor :wild_2v3_intro

  alias wild_2v3_orig_initialize initialize
  def initialize(scene, p1, p2, player, opponent)
    wild_2v3_orig_initialize(scene, p1, p2, player, opponent)
    @wild_2v3_battle = $game_temp&.wild_2v3_battle ? true : false
    @wild_2v3_intro = $game_temp&.wild_2v3_intro
  end

  alias wild_2v3_orig_pbStartBattleSendOut pbStartBattleSendOut
  def pbStartBattleSendOut(sendOuts)
    if wildBattle? && @wild_2v3_battle
      foe_party = pbParty(1)
      if @wild_2v3_intro && !@wild_2v3_intro.empty?
        pbDisplayPaused(@wild_2v3_intro)
      else
        pbDisplayPaused(_INTL("A wild {1}, {2} and {3} appeared!",
                              foe_party[0].name, foe_party[1].name, foe_party[2].name))
      end
      msg = ""
      to_send_out = []
      sent = sendOuts[0][0]
      case sent.length
      when 1
        msg = _INTL("Go! {1}!", @battlers[sent[0]].name)
      when 2
        msg = _INTL("Go! {1} and {2}!", @battlers[sent[0]].name, @battlers[sent[1]].name)
      when 3
        msg = _INTL("Go! {1}, {2} and {3}!", @battlers[sent[0]].name,
                    @battlers[sent[1]].name, @battlers[sent[2]].name)
      end
      to_send_out.concat(sent)
      pbDisplayBrief(msg) if msg.length > 0
      anim_send_outs = []
      to_send_out.each do |idx_battler|
        anim_send_outs.push([idx_battler, @battlers[idx_battler].pokemon])
      end
      pbSendOut(anim_send_outs, true)
      return
    end
    wild_2v3_orig_pbStartBattleSendOut(sendOuts)
  end
end

def pbCreateEventPokemon(species, level, options = {})
  Wild2v3Battle.create_event_pokemon(species, level, options)
end

def pbWild2v3Battle(*args)
  Wild2v3Battle.start(*args)
end

if $DEBUG
  MenuHandlers.add(:debug_menu, :test_wild_2v3_battle, {
    "name"        => _INTL("Test wild 2v3 battle"),
    "parent"      => :battle_menu,
    "description" => _INTL("Start a wild battle vs three foes (2v3 or 1v3)."),
    "effect"      => proc {
      pkmn = []
      3.times do |i|
        species = pbChooseSpeciesList
        break if !species
        params = ChooseNumberParams.new
        params.setRange(1, GameData::GrowthRate.max_level)
        params.setInitialValue(20)
        params.setCancelValue(0)
        level = pbMessageChooseNumber(_INTL("Set wild foe {1}'s level.", i + 1), params)
        break if level <= 0
        pkmn.push(pbCreateEventPokemon(species, level))
      end
      if pkmn.length < 3
        pbMessage(_INTL("Need three Pokémon for a wild 2v3 battle."))
        next false
      end
      setBattleRule("canLose")
      pbCreatureEncounter_set_rank(:BOSS) if defined?(pbCreatureEncounter_set_rank)
      pbWild2v3Battle(*pkmn)
      next false
    }
  })
end
