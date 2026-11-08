#==============================================================================#
# Northshire Abbey (map 076): event logic edited here instead of bulky event lists
#==============================================================================#
# HOW TO CONNECT FROM RPG MAKER XP
#
# Script... may be one line or several Script rows (Enter splits into 355/655 chunks).
# The game merges chunks when running; Quest markers merge them too when scanning.
#
# Option A  -  route every event automatically by RPG Maker ID (recommended when
# migrating many NPCs): use the numeric ID shown in the event dialog title.
#
#   NorthshireAbbeyEvents.dispatch_from_interpreter
#
# Then edit the `case` in `dispatch_by_event_id` below (add one `when` per ID).
#
# Innkeepers on any map:
#
#   NorthshireAbbeyEvents.run(:innkeeper)
#
# (Handled before the MAP_ID gate.) Or call straight Script: pbInnkeeperInteract
#
# Outdoor door → Northshire Abbey Indoor 1F (Map ID 032 in RPG Maker  -  IDs are fixed when created),
# stand on (29,16) walking east:
#   New event at (29, 16), Trigger: Player Touch, Script: pbNorthAbbeyOutdoorToIndoorWarp
#   (Only fires when facing direction 6 / entered from the left. Or Transfer Player to map 32, X=1 Y=7.)
#
# Option B  -  name each scene explicitly (good for a few scripted moments):
#
#   NorthshireAbbeyEvents.run(:deputy_willem)
#
# Overhead markers: link :deputy_willem etc. from QuestJournal::DEFINITIONS
# (:offer_npc_handlers / :turnin_npc_handlers). Full “new quest” checklist  - 
# Plugins/Quest Journal/QuestJournal.rb, comment block above DEFINITIONS.
#
#==============================================================================#

module NorthshireAbbeyEvents
  MAP_ID = 76

  # Must match Map Properties: same name as in RPG Maker; ID is the number in the map tree (e.g. 032).
  INDOOR_1F_MAP_ID   = 32
  INDOOR_1F_MAP_NAME = "Northshire Abbey Indoor 1F"

  # Echo Ridge Mine (indoor cave under Northshire). Map ID must match Data/Map033.rxdata + PBS Name.
  ECHO_RIDGE_MINE_MAP_ID   = 33
  ECHO_RIDGE_MINE_MAP_NAME = "Echo Ridge Mine"

  # Script handlers (Marshal, Deputy, etc.) run on outdoor Northshire, abbey indoor, and Echo Ridge Mine.
  def self.northshire_area_map?(map_id)
    m = map_id.to_i
    m == MAP_ID || m == INDOOR_1F_MAP_ID || m == ECHO_RIDGE_MINE_MAP_ID
  end
  OUTDOOR_DOOR_X   = 29
  OUTDOOR_DOOR_Y   = 16
  INDOOR_1F_X      = 1
  INDOOR_1F_Y      = 7
  # RPG Maker direction 6 = east / walking to the right onto the door tile from the west.
  INDOOR_ARRIVE_FACING = 2 # face down after entering (adjust if your doorway graphic needs another facing)

  # If an event runs Script `dispatch_from_interpreter` instead of `.run(:symbol)`,
  # map RPG Maker event IDs (title bar number) → the SAME handler symbol used in
  # QuestJournal::DEFINITIONS offer_npc_handlers / turnin_npc_handlers.
  #
  # Example (edit the HASH literal below; do not mutate after `.freeze`):
  #     DISPATCH_MARKER_EVENT_HANDLERS = { 19 => :marshal_mcbride }.freeze
  DISPATCH_MARKER_EVENT_HANDLERS = {
    # Event ID here => Script symbol wired in QuestJournal quests
    # 19 => :marshal_mcbride,
  }.freeze

  # Used by QuestMapMarkers when building marker_rules_for_event.
  def self.marker_specs_for_dispatch_registry(map_id, event_id)
    return [] unless northshire_area_map?(map_id)

    tok = DISPATCH_MARKER_EVENT_HANDLERS[event_id.to_i]
    return [] if tok.nil?

    syms = tok.is_a?(Array) ? tok : [tok]
    out = []
    syms.flatten.each do |s|
      out.concat(QuestJournal.marker_specs_for_npc_script_handler(s.to_sym))
    end
    out
  end

  # Single entrypoint for Script... when you migrate by RPG Maker event ID.
  # Ignores calls when not on Northshire outdoor or abbey indoor (see northshire_area_map?).
  def self.dispatch_from_interpreter
    return unless northshire_area_map?($game_map&.map_id)

    interp = pbMapInterpreter
    return unless interp

    dispatch_by_event_id(interp.get_self&.id)
  end

  #---------------------------------------------------------------------------
  # Paste each event ID from RPG Maker XP (event editor header), then move the
  # Ruby from "Script..." / Show Text / Control Switches equivalents here.
  #---------------------------------------------------------------------------

  def self.dispatch_by_event_id(event_id)
    return if !event_id

    case event_id.to_i
    # when 12 then monk_at_well
    # when 37 then bell_switch
    when 0
      # Placeholder branch: RPG Maker event IDs never use 0, so Ruby requires at
      # least one `when` before `else`  -  add real IDs above instead of this.
      nil
    else
      echoln(sprintf("NorthshireAbbeyEvents: missing handler for map %03d event %s", $game_map&.map_id.to_i, event_id.inspect)) if $DEBUG
    end
  end

  # Explicit names when you prefer Script... NorthshireAbbeyEvents.run(:symbol)
  # Takes *args so a mistaken newline (run on one line, symbol on next) yields 0 args
  # instead of crashing with ArgumentError.
  def self.run(*args)
    if args.length == 0
      pbMessage(_INTL("Script setup error:\\nPut the full call on ONE line:" \
                      "\\nNorthshireAbbeyEvents.run(:deputy_willem)"))
      return
    end

    key = args[0]
    ks = key.to_sym
    if ks == :innkeeper
      pbInnkeeperInteract
      return
    end

    return unless northshire_area_map?($game_map&.map_id)

    case ks
    when :deputy_willem   then deputy_willem
    when :marshal_mcbride then marshal_mcbride
    when :inn_hearthstone then inn_hearthstone
    when :kobold_worker   then kobold_worker
    when :kobold_laborer  then kobold_laborer
    when :defias_thug     then defias_thug
    when :garrick_padfoot then garrick_padfoot
    when :harvest_crate   then harvest_crate
    when :milly_osworth   then milly_osworth
    when :brother_neals   then brother_neals
    when :reinforcement_test_trainer then reinforcement_test_trainer
    when :llane_beshere,
         :brother_sammuel,
         :jorik_kerridan,
         :priestess_anetta,
         :khelden_bremen,
         :drusilla_la_salle
      letter_trainer_turn_in(ks)
    else
      echoln(sprintf("NorthshireAbbeyEvents.run: unknown key %p", key)) if $DEBUG
    end
  end

  # Script (from MapEventInjector example): NorthshireAbbeyEvents.run(:kobold_worker)
  # While "Investigate Echo Ridge" is active, starts a random single-Pokémon battle (quest objective).
  def self.kobold_worker
    pbBattleEchoRidgeKoboldWorker
  end

  # Echo Ridge Mine (map 033): challengeable kobold NPCs, Lv.3 teams of 1–2 Pokémon.
  def self.kobold_laborer
    pbBattleEchoRidgeMineLaborer
  end

  def self.defias_thug
    pbBattleDefiasThug
  end

  def self.garrick_padfoot
    pbBattleGarrickPadfoot
  end

  def self.harvest_crate
    pbCollectMillyHarvestCrate
  end

  # Script: NorthshireAbbeyEvents.run(:reinforcement_test_trainer)
  # Outdoor Northshire (map 076): 1v1 → 1v2 trainer battle with delayed partners.
  def self.reinforcement_test_trainer
    unless GameData::Trainer.exists?(:YOUNGSTER, "Ben", 2)
      pbMessage(_INTL("Reinforcement test trainer is missing. Compile PBS/trainers.txt."))
      return
    end
    pbMessage(_INTL(
      "I'm Ben! I start with my main team of three, but Ekans joins after three turns " \
      "and Pidgey shows up once two of my main Pokémon have fainted. Ready?"
    ))
    cmd = pbShowCommands(nil, [_INTL("Let's battle!"), _INTL("Not now.")], 2)
    return unless cmd && cmd.zero?
    setBattleRule("canLose")
    won = TrainerBattle.start(:YOUNGSTER, "Ben", 2)
    if won
      pbMessage(_INTL("Whoa, you handled my reinforcements!"))
    else
      pbMessage(_INTL("My backup squad turned the fight around!"))
    end
  end

  # Script: NorthshireAbbeyEvents.run(:inn_hearthstone)
  # Inn NPC: optionally rebind hearthstone to this inn's tiles.
  def self.inn_hearthstone
    pbMessage(_INTL("Will you bind your \\c[1]Hearthstone\\c[0] to this inn?\nYou'll return here when you're knocked out - or when you channel it from the Bag."))
    cmd = pbShowCommands(nil,
                          [_INTL("Make this inn my hearthstone."), _INTL("Not now.")],
                          2)
    return unless cmd && cmd.zero?
    unless pbBindHearthstoneToCurrentLocation
      return
    end
    pbMessage(_INTL("There. Your hearthstone remembers this place warmly."))
  end

  # --------------------------------------------------------------------------
  # Script: NorthshireAbbeyEvents.run(:deputy_willem)
  def self.deputy_willem
    qid = QuestJournal::ID_MARSHAL_MEET
    q_bro = QuestJournal::ID_BROTHERHOOD_OF_THIEVES
    q_gar = QuestJournal::ID_BOUNTY_GARRICK
    cname = pbGetPlayerClassDisplayName

    if pbQuestActive?(qid)
      pbMessage(_INTL("{1}, Marshal McBride is still expecting you. Don't keep him waiting.", cname))
      return
    end

    if !pbQuestDone?(qid) && QuestJournal.offer_available?(qid)
      dbg = pbQuestDebugOfferChoice(qid)
      return if dbg == :cancel
      pbBeginQuestOfferIntro(qid, dbg)
      if dbg == :auto_accept
        pbQuestAccept(qid)
        pbMessage(_INTL("It's in your quest log. Good hunting."))
        return
      end
      dtext = QuestJournal.description_text(qid)
      pbMessage(dtext) if dtext
      cmd = pbShowCommands(nil, [_INTL("I'll go see him."), _INTL("Maybe later.")], 2)
      if cmd == 0 && pbQuestAccept(qid)
        pbMessage(_INTL("It's in your quest log. Good hunting."))
      end
      return
    end

    # Active Defias turn-ins
    if pbQuestActive?(q_bro)
      if QuestJournal.turn_in_ready?(q_bro)
        cmsg = QuestJournal.completion_text(q_bro)
        pbMessage(cmsg) if cmsg
        pbQuestComplete(q_bro)
        deputy_post_brotherhood_hub
        return
      end
      pt = QuestJournal.progress_talk_text(q_bro)
      pbMessage(pt) if pt
      return
    end

    if pbQuestActive?(q_gar)
      if QuestJournal.turn_in_ready?(q_gar)
        cmsg = QuestJournal.completion_text(q_gar)
        pbMessage(cmsg) if cmsg
        pbQuestComplete(q_gar)
        return
      end
      pt = QuestJournal.progress_talk_text(q_gar)
      pbMessage(pt) if pt
      return
    end

    return if deputy_try_offer_brotherhood

    if QuestJournal.deputy_hub_has_pending_pickups?
      pbMessage(_INTL("There's more work against the Defias if you're willing, {1}.", cname))
      deputy_hub_loop
      return
    end

    if pbQuestDone?(q_bro)
      pbMessage(_INTL("Thanks again for helping with the Defias, {1}. Stormwind remembers.", cname))
    elsif pbQuestDone?(qid)
      pbMessage(_INTL("Thanks again for seeing Marshal McBride, {1}. Stormwind remembers.", cname))
    else
      pbMessage(_INTL("If you're looking for work, speak with me once you've reported to the Marshal."))
    end
  end

  def self.deputy_try_offer_brotherhood
    q_bro = QuestJournal::ID_BROTHERHOOD_OF_THIEVES
    return false unless QuestJournal.offer_available?(q_bro)

    dbg = pbQuestDebugOfferChoice(q_bro)
    return false if dbg == :cancel
    pbBeginQuestOfferIntro(q_bro, dbg)
    if dbg == :auto_accept
      if pbQuestAccept(q_bro)
        pbMessage(_INTL("It's in your quest log. Bring me those bandanas."))
      end
      return true
    end
    offer = QuestJournal.marshal_offer_text(q_bro)
    offer ||= QuestJournal.description_text(q_bro)
    pbMessage(offer) if offer
    cmd = pbShowCommands(nil, [_INTL("I'll handle it."), _INTL("Not right now.")], 2)
    if cmd == 0 && pbQuestAccept(q_bro)
      pbMessage(_INTL("It's in your quest log. Bring me those bandanas."))
    end
    true
  end

  def self.deputy_post_brotherhood_hub
    pbMessage(_INTL(
      "With the Defias marked, I've got more for you - Milly needs hands by the stables, " \
      "and there's a bounty on Garrick Padfoot."
    ))
    deputy_hub_loop
  end

  def self.deputy_hub_loop
    loop do
      ids = QuestJournal.deputy_hub_pickup_quest_ids
      return if ids.empty?

      pick = pbQuestOfferChooseQuestId(ids)
      return if pick.nil?

      pbQuestOfferSingleQuestFromNpc(pick,
                                     accept_label: _INTL("I'll handle it."),
                                     decline_label: _INTL("Another task first."))
    end
  end

  # Script: NorthshireAbbeyEvents.run(:marshal_mcbride)
  def self.marshal_mcbride
    q1 = QuestJournal::ID_MARSHAL_MEET
    q2 = QuestJournal::ID_KOBOLD_CLEANUP
    q_echo = QuestJournal::ID_INVESTIGATE_ECHO_RIDGE
    q_skirmish = QuestJournal::ID_SKIRMISH_ECHO_RIDGE
    q_gold = QuestJournal::ID_REPORT_TO_GOLDSHIRE

    if pbQuestActive?(q1)
      cmsg = QuestJournal.completion_text(q1)
      pbMessage(cmsg) if cmsg
      pbQuestComplete(q1)
      marshal_try_offer_kobold_quest
      return
    end

    if pbQuestActive?(q2)
      cap = QuestJournal::KOBOLD_TRAINERS_REQUIRED
      if QuestJournal.kobold_trainers_defeated >= cap
        cmsg2 = QuestJournal.completion_text(q2)
        pbMessage(cmsg2) if cmsg2
        pbQuestComplete(q2)
        marshal_post_kobold_intro_and_hub
      else
        pt = QuestJournal.progress_talk_text(q2)
        pbMessage(pt) if pt
      end
      return
    end

    if pbQuestActive?(q_echo)
      if QuestJournal.turn_in_ready?(q_echo)
        cmsg_e = QuestJournal.completion_text(q_echo)
        pbMessage(cmsg_e) if cmsg_e
        pbQuestComplete(q_echo)
        marshal_try_offer_skirmish
      else
        pt_e = QuestJournal.progress_talk_text(q_echo)
        pbMessage(pt_e) if pt_e
      end
      return
    end

    if pbQuestActive?(q_skirmish)
      if QuestJournal.turn_in_ready?(q_skirmish)
        cmsg_s = QuestJournal.completion_text(q_skirmish)
        pbMessage(cmsg_s) if cmsg_s
        pbQuestComplete(q_skirmish)
        marshal_try_offer_report_goldshire
      else
        pt_s = QuestJournal.progress_talk_text(q_skirmish)
        pbMessage(pt_s) if pt_s
      end
      return
    end

    if pbQuestActive?(q_gold)
      pt_g = QuestJournal.progress_talk_text(q_gold)
      pbMessage(pt_g) if pt_g
      return
    end

    return if marshal_try_offer_kobold_quest
    return if marshal_try_offer_skirmish
    return if marshal_try_offer_report_goldshire

    if QuestJournal.marshal_hub_has_pending_pickups?
      pbMessage(_INTL("There's still work - the ridge, Goldshire orders, or sealed letters. What do you need?"))
      marshal_post_kobold_hub_loop
      return
    end

    if pbQuestDone?(q_gold)
      pbMessage(_INTL("Dughan has your orders now. Elwynn needs you, {1}.", pbGetPlayerClassDisplayName))
    elsif pbQuestDone?(q2)
      pbMessage(_INTL("Stormwind appreciates your vigilance, {1}. Keep your guard up.", pbGetPlayerClassDisplayName))
    elsif !pbQuestDone?(q1)
      pbMessage(_INTL("If you're looking for work, Deputy Willem assigns bounties at the abbey."))
    end
  end

  # After Kobold Camp Cleanup: Echo Ridge (all races) + class letter (humans only).
  def self.marshal_post_kobold_intro_and_hub
    if QuestJournal.letter_quest_id_for_current_player
      pbMessage(_INTL(
        "Those scouts won't trouble us for a while. I have two things for you - clear Echo Ridge Mine, " \
        "and read the sealed letter from your trainer before anything else in the abbey."
      ))
    else
      pbMessage(_INTL(
        "Those scouts won't trouble us for a while. Kobold workers crowd Echo Ridge Mine to the north - thin them out."
      ))
    end
    marshal_post_kobold_hub_loop
  end

  # Pick which pickup to negotiate first; repeat until none left or player backs out.
  def self.marshal_post_kobold_hub_loop
    loop do
      ids = QuestJournal.marshal_hub_pickup_quest_ids
      return if ids.empty?

      pick = pbQuestOfferChooseQuestId(ids)
      return if pick.nil?

      pbQuestOfferSingleQuestFromNpc(pick,
                                     accept_label: _INTL("I'll handle it."),
                                     decline_label: _INTL("Another task first."))
    end
  end

  def self.marshal_try_offer_skirmish
    q = QuestJournal::ID_SKIRMISH_ECHO_RIDGE
    return false unless QuestJournal.offer_available?(q)

    dbg = pbQuestDebugOfferChoice(q)
    return false if dbg == :cancel
    pbBeginQuestOfferIntro(q, dbg)
    if dbg == :auto_accept
      if pbQuestAccept(q)
        pbMessage(_INTL("It's in your quest log. Clear those laborers."))
      end
      return true
    end
    offer = QuestJournal.marshal_offer_text(q)
    pbMessage(offer) if offer
    cmd = pbShowCommands(nil, [_INTL("I'll handle it."), _INTL("Not right now.")], 2)
    if cmd == 0 && pbQuestAccept(q)
      pbMessage(_INTL("It's in your quest log. Clear those laborers."))
    end
    true
  end

  def self.marshal_try_offer_report_goldshire
    q = QuestJournal::ID_REPORT_TO_GOLDSHIRE
    return false unless QuestJournal.offer_available?(q)

    dbg = pbQuestDebugOfferChoice(q)
    return false if dbg == :cancel
    pbBeginQuestOfferIntro(q, dbg)
    if dbg == :auto_accept
      if pbQuestAccept(q)
        pbMessage(_INTL("Take my documents to Marshal Dughan in Goldshire."))
      end
      return true
    end
    offer = QuestJournal.marshal_offer_text(q)
    pbMessage(offer) if offer
    cmd = pbShowCommands(nil, [_INTL("I'll deliver them."), _INTL("Not right now.")], 2)
    if cmd == 0 && pbQuestAccept(q)
      pbMessage(_INTL("Take my documents to Marshal Dughan in Goldshire."))
    end
    true
  end

  # Script: NorthshireAbbeyEvents.run(:milly_osworth)
  def self.milly_osworth
    q_meet = QuestJournal::ID_MILLY_OSWORTH
    q_harv = QuestJournal::ID_MILLYS_HARVEST
    q_grape = QuestJournal::ID_GRAPE_MANIFEST

    if pbQuestActive?(q_meet)
      cmsg = QuestJournal.completion_text(q_meet)
      pbMessage(cmsg) if cmsg
      pbQuestComplete(q_meet)
      milly_try_offer_harvest
      return
    end

    if pbQuestActive?(q_harv)
      if QuestJournal.turn_in_ready?(q_harv)
        cmsg = QuestJournal.completion_text(q_harv)
        pbMessage(cmsg) if cmsg
        pbQuestComplete(q_harv)
        milly_try_offer_grape_manifest
      else
        pt = QuestJournal.progress_talk_text(q_harv)
        pbMessage(pt) if pt
      end
      return
    end

    if pbQuestActive?(q_grape)
      pt = QuestJournal.progress_talk_text(q_grape)
      pbMessage(pt) if pt
      return
    end

    return if milly_try_offer_harvest
    return if milly_try_offer_grape_manifest

    if pbQuestDone?(q_grape)
      pbMessage(_INTL("Thank you again for saving my harvest!"))
    elsif pbQuestDone?(q_meet)
      pbMessage(_INTL("Those Defias won't leave my vines alone for long..."))
    else
      pbMessage(_INTL("If Deputy Willem sent you, he'll have a word first."))
    end
  end

  def self.milly_try_offer_harvest
    q = QuestJournal::ID_MILLYS_HARVEST
    return false unless QuestJournal.offer_available?(q)

    dbg = pbQuestDebugOfferChoice(q)
    return false if dbg == :cancel
    pbBeginQuestOfferIntro(q, dbg)
    if dbg == :auto_accept
      if pbQuestAccept(q)
        pbMessage(_INTL("Please - those crates are all I have left!"))
      end
      return true
    end
    offer = QuestJournal.marshal_offer_text(q)
    offer ||= QuestJournal.description_text(q)
    pbMessage(offer) if offer
    cmd = pbShowCommands(nil, [_INTL("I'll get them."), _INTL("Not right now.")], 2)
    if cmd == 0 && pbQuestAccept(q)
      pbMessage(_INTL("Please - those crates are all I have left!"))
    end
    true
  end

  def self.milly_try_offer_grape_manifest
    q = QuestJournal::ID_GRAPE_MANIFEST
    return false unless QuestJournal.offer_available?(q)

    dbg = pbQuestDebugOfferChoice(q)
    return false if dbg == :cancel
    pbBeginQuestOfferIntro(q, dbg)
    if dbg == :auto_accept
      if pbQuestAccept(q)
        pbMessage(_INTL("Brother Neals is in the abbey bell tower."))
      end
      return true
    end
    offer = QuestJournal.marshal_offer_text(q)
    offer ||= QuestJournal.description_text(q)
    pbMessage(offer) if offer
    cmd = pbShowCommands(nil, [_INTL("I'll take it."), _INTL("Not right now.")], 2)
    if cmd == 0 && pbQuestAccept(q)
      pbMessage(_INTL("Brother Neals is in the abbey bell tower."))
    end
    true
  end

  # Script: NorthshireAbbeyEvents.run(:brother_neals)
  def self.brother_neals
    q = QuestJournal::ID_GRAPE_MANIFEST
    if pbQuestActive?(q)
      if QuestJournal.turn_in_ready?(q)
        cmsg = QuestJournal.completion_text(q)
        pbMessage(cmsg) if cmsg
        pbQuestComplete(q)
      else
        pbMessage(_INTL("You look to be in fine spirits! Come! Have a seat, and have a drink!"))
      end
      return
    end
    if pbQuestDone?(q)
      pbMessage(_INTL("May the Light keep Northshire's cellars full."))
    else
      pbMessage(_INTL("You look to be in fine spirits! Come! Have a seat, and have a drink!"))
    end
  end

  # Script symbols must match QuestJournal letter quests :turnin_npc_handlers.
  def self.letter_trainer_turn_in(handler_sym)
    h = handler_sym.to_sym
    pair = QuestJournal::DEFINITIONS.find do |_qid, ent|
      QuestJournal.npc_turnin_handlers(ent).include?(h)
    end
    return if !pair

    qid = pair[0]
    return unless pbQuestActive?(qid)
    return unless QuestJournal.turn_in_ready?(qid)

    cmsg = QuestJournal.completion_text(qid)
    pbMessage(cmsg) if cmsg
    pbQuestComplete(qid)
  end

  # Returns true if Marshal offered the Kobold quest dialog (eligible + shown).
  def self.marshal_try_offer_kobold_quest
    q1 = QuestJournal::ID_MARSHAL_MEET
    q2 = QuestJournal::ID_KOBOLD_CLEANUP
    return false if !pbQuestDone?(q1)
    return false if pbQuestActive?(q2) || pbQuestDone?(q2)

    dbg = pbQuestDebugOfferChoice(q2)
    return false if dbg == :cancel
    pbBeginQuestOfferIntro(q2, dbg)
    if dbg == :auto_accept
      if pbQuestAccept(q2)
        pbMessage(_INTL("It's in your quest log. Thin their ranks - we're counting on you."))
      end
      return true
    end

    offer = QuestJournal.marshal_offer_text(q2)
    pbMessage(offer) if offer
    cmd = pbShowCommands(nil, [_INTL("I'll handle it."), _INTL("Not right now.")], 2)
    if cmd == 0 && pbQuestAccept(q2)
      pbMessage(_INTL("It's in your quest log. Thin their ranks - we're counting on you."))
    end
    true
  end

  # --------------------------------------------------------------------------
  # Named handlers  -  define as `def self.xxx` ... `end`
  # Example:
  #
  # def self.monk_at_well
  #   pbMessage(_INTL("\\f[PortraitName]Peace be upon you."))
  # end
  # --------------------------------------------------------------------------

  # Called from a map event on Northshire Abbey (076), tile (29,16), Trigger: Player Touch.
  # Optional Script row (same page): pbNorthAbbeyOutdoorToIndoorWarp
  # Only warps if the player stepped on the tile walking east (from x=28), so other approaches do nothing.
  def self.outdoor_to_indoor_warp
    return if !$game_map || $game_map.map_id != MAP_ID
    return unless $game_player.x == OUTDOOR_DOOR_X && $game_player.y == OUTDOOR_DOOR_Y
    return unless $game_player.direction == 6

    if defined?(pbDoorWarpTo)
      # By map name so it tracks MapInfos even if the map is ever reordered in RM (name must stay in sync).
      pbDoorWarpTo(INDOOR_1F_MAP_NAME, INDOOR_1F_X, INDOOR_1F_Y, facing: INDOOR_ARRIVE_FACING)
      return
    end

    pbCancelVehicles rescue nil
    Followers.clear if defined?(Followers)
    pbFadeOutIn do
      $game_temp.player_new_map_id    = INDOOR_1F_MAP_ID
      $game_temp.player_new_x         = INDOOR_1F_X
      $game_temp.player_new_y         = INDOOR_1F_Y
      $game_temp.player_new_direction = INDOOR_ARRIVE_FACING
      pbDismountBike rescue nil
      $scene.transfer_player if $scene.is_a?(Scene_Map)
    end
  end
end

def pbNorthAbbeyOutdoorToIndoorWarp
  NorthshireAbbeyEvents.outdoor_to_indoor_warp
end
