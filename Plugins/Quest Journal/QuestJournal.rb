#===============================================================================
# Quest Journal  -  accepted / completed quests (save-safe), pause menu UI
#-------------------------------------------------------------------------------
# Globals: @quest_active[id] tracks open quests shown in Quest Log.
# @quest_completed[id] is only used for NPC/world scripting (quests do not appear
# here once turned in  -  they disappear from this menu).
# @quest_counters[id]  -  optional counters (e.g. kobold trainers defeated).
#-------------------------------------------------------------------------------
class PokemonGlobalMetadata
  attr_accessor :quest_active
  attr_accessor :quest_completed
  attr_accessor :quest_counters
  # Legacy save field; quick-offer menu is controlled by QuestJournal::USE_QUICK_QUEST_OFFER_MENU.
  attr_accessor :quest_debug_quick_offer
end

#===============================================================================
#
#===============================================================================
module QuestJournal
  # First Northshire quest chain: Start: Deputy Willem, End: Marshal McBride.
  ID_MARSHAL_MEET = 1
  # “Kobold Camp Cleanup”; unlocked after Quest 1 completes (Marshal gives it).
  ID_KOBOLD_CLEANUP = 2
  # Unlocked together after Kobold Camp Cleanup (Marshal offers Echo Ridge to everyone;
  # humans also get one class letter).
  ID_INVESTIGATE_ECHO_RIDGE = 3
  ECHO_RIDGE_WORKERS_REQUIRED = 5
  # Human class letters (IDs match PLAYER_CLASS_NAMES order: Warrior...Warlock).
  ID_SIMPLE_LETTER       = 4   # Warrior → Llane Beshere
  ID_CONSECRATED_LETTER  = 5   # Paladin → Brother Sammuel
  ID_ENCRYPTED_LETTER    = 6   # Rogue → Jorik Kerridan
  ID_HALLOWED_LETTER     = 7   # Priest → Priestess Anetta
  ID_GLYPHIC_LETTER      = 8   # Mage → Khelden Bremen
  ID_TAINTED_LETTER      = 9   # Warlock → Drusilla La Salle

  LETTER_QUEST_IDS = [
    ID_SIMPLE_LETTER, ID_CONSECRATED_LETTER, ID_ENCRYPTED_LETTER,
    ID_HALLOWED_LETTER, ID_GLYPHIC_LETTER, ID_TAINTED_LETTER
  ].freeze

  KOBOLD_TRAINERS_REQUIRED = 4
  # Lowest kobold scout NPC: one Lv.1 Pokémon chosen at battle start from this pool.
  KOBOLD_VERMIN_SPECIES_POOL = [
    :RATTATA,
    :POOCHYENA,
    :NIDORANmA,
    :NIDORANfE,
    :CATERPIE
  ].freeze

  # ----- Overhead markers: checklist for EVERY NEW QUEST ---------------------------------
  #
  #  (1) Add a Quest ID constant (e.g. ID_MY_QUEST = 3) and plug it into DEFINITIONS.
  #
  #  (2) DEFINITIONS[your_id]:
  #        • offer_npc_handlers  [:handler_symbol]  -  shows quest_available (“!”) whenever
  #          QuestJournal.offer_available?(your_id) is true. Omit if no NPC offers this quest.
  #        • turnin_npc_handlers [:same_or_other]  -  shows quest_waiting / question_complete
  #          above return NPC while active. Omit only if nobody turns this in on the map UI.
  #        • turn_in_ready?  -  proc that returns true when objectives are done (needed for the
  #          gold “complete” bubble on the turn-in NPC). Omit only if unused.
  #
  #  (3) offer_available?(quest_id)  -  add `when YOUR_ID ...` logic if the pickup has prereqs or
  #      gated rules (see ID_KOBOLD_CLEANUP vs ID_MARSHAL_MEET). Default `else false` hides the
  #      pickup icon unless you explicitly allow it here.
  #
  #  (4) RPG Maker event tied to pickup/turn-in: put ONE Script line, full line only:
  #        NorthshireAbbeyEvents.run(:handler_symbol)
  #      and implement that handler in Plugins/NorthshireAbbey/NorthshireAbbey_Events.rb via
  #      `NorthshireAbbeyEvents.run` + `when :handler_symbol`.
  #
  #  If the event uses `NorthshireAbbeyEvents.dispatch_from_interpreter` instead, add map 076’s
  #  event ID → :handler_symbol inside NorthshireAbbeyEvents::DISPATCH_MARKER_EVENT_HANDLERS.
  #
  #  (5) Fallbacks without Script scan: Event Name tokens `questoffer(ID)` / `questturnin(ID)`,
  #      or QuestJournal::EXTRA_QUEST_MAP_MARKERS.push([[map_id, event_id], :offer|:active_turnin, id]).
  #
  #  (6) Assets (same for all quests once): PNGs readable by pbResolveBitmap, basename
  #      quest_available, question_complete, quest_waiting  -  e.g. Graphics/Pictures/...
  #
  # Optional rewards on pbQuestComplete: completion_party_exp, completion_money, completion_items [[:ITEM, qty], ...]
  #
  #------------------------------------------------------------------------------------------------

  DEFINITIONS = {
    ID_MARSHAL_MEET => {
      name:        proc { _INTL("A Threat Within") },
      objective:   proc { _INTL("Speak with Marshal McBride.") },
      description: proc {
        c = (defined?(pbGetPlayerClassDisplayName) ? pbGetPlayerClassDisplayName : _INTL("traveler"))
        _INTL(
          "I hope you strapped your belt on tight, young {1}, because there is work to do here in Northshire.\n" \
          "And I don't mean farming.\n" \
          "The Stormwind guards are hard pressed to keep the peace here, with so many of us in distant lands " \
          "and so many threats pressing close. And so we're enlisting the aid of anyone willing to defend " \
          "their home. And their alliance.\n" \
          "If you're here to answer the call, then speak with my superior, Marshal McBride. " \
          "He's inside the abbey behind me.",
          c
        )
      },
      giver:       proc { _INTL("Deputy Willem") },
      turnin:      proc { _INTL("Marshal McBride") },
      # Overhead markers: NPC must use Script `NorthshireAbbeyEvents.run(:symbol)` matching these.
      offer_npc_handlers:  [:deputy_willem],
      turnin_npc_handlers: [:marshal_mcbride],
      # Spoken by Marshal when the quest turns in (active → completed).
      completion:  proc {
        _INTL(
          "Ah, good. Another volunteer. We're getting a lot of you these days.\n" \
          "I hope it's enough.\n" \
          "The lands are threatened from without, and so many of our forces have been marshaled abroad. " \
          "This, in turn, leaves room for corrupt and lawless groups to thrive within our borders.\n" \
          "It is a many-fronted battle we wage. Gird yourself for a long campaign."
        )
      },
      # Exp. Points each Pokémon in the party receives when this quest is turned in (0 or omit for none).
      completion_party_exp: 50,
      # Map marker: objectives satisfied  -  show question_complete above turn-in NPC.
      turn_in_ready?: proc { true }
    },
    ID_KOBOLD_CLEANUP => {
      name: proc { _INTL("Kobold Camp Cleanup") },
      objective: proc {
        pbQuestEnsureGlobals
        n = $PokemonGlobal.quest_counters[QuestJournal::ID_KOBOLD_CLEANUP].to_i
        cap = QuestJournal::KOBOLD_TRAINERS_REQUIRED
        _INTL("Defeat {1} / {2} kobold trainers.", [n, cap].min, cap)
      },
      description: proc {
        _INTL(
          "Your first task is one of cleansing. A clan of kobolds have infested the woods nearby. " \
          "Seek out their trainers, defeat {1} of them in battle, then report back to Marshal McBride.\n" \
          "Reduce their numbers so that we may one day drive them from Northshire.",
          QuestJournal::KOBOLD_TRAINERS_REQUIRED
        )
      },
      giver:  proc { _INTL("Marshal McBride") },
      turnin: proc { _INTL("Marshal McBride") },
      marshal_offer: proc {
        _INTL(
          "Your orders are cleansing. Kobold camps choke the outskirts - challenge their scouts in battle. " \
          "I need you to defeat {1} of their trainers, then come back and report.",
          QuestJournal::KOBOLD_TRAINERS_REQUIRED
        )
      },
      progress_talk: proc {
        _INTL(
          "How goes the hunt? Have you found and battled those scouts? Victory by victory, we blunt their strength."
        )
      },
      completion: proc {
        _INTL(
          "Well done, citizen. Those kobolds are thieves and cowards, but in large numbers they pose a threat to us.\n" \
          "And the humans of Stormwind do not need another threat.\n" \
          "For defeating them, you have my gratitude."
        )
      },
      completion_party_exp: 50,
      completion_money: 25,
      completion_items: [[:POKEBALL, 5]],
      offer_npc_handlers:  [:marshal_mcbride],
      turnin_npc_handlers: [:marshal_mcbride],
      turn_in_ready?: proc {
        QuestJournal.kobold_trainers_defeated >= QuestJournal::KOBOLD_TRAINERS_REQUIRED
      }
    },
    ID_INVESTIGATE_ECHO_RIDGE => {
      name:        proc { _INTL("Investigate Echo Ridge") },
      objective:   proc {
        pbQuestEnsureGlobals
        n = $PokemonGlobal.quest_counters[QuestJournal::ID_INVESTIGATE_ECHO_RIDGE].to_i
        cap = QuestJournal::ECHO_RIDGE_WORKERS_REQUIRED
        _INTL("Defeat {1} / {2} kobold workers near Echo Ridge Mine.", [n, cap].min, cap)
      },
      description: proc {
        _INTL(
          "My scouts tell me that the kobold infestation is larger than we had thought. " \
          "A group of kobold workers has camped near the Echo Ridge Mine to the north.\n" \
          "Go to the mine and remove them. We know there are at least {1}. " \
          "Cut them down, see if there are more, then report back to me.",
          QuestJournal::ECHO_RIDGE_WORKERS_REQUIRED
        )
      },
      giver:       proc { _INTL("Marshal McBride") },
      turnin:      proc { _INTL("Marshal McBride") },
      marshal_offer: proc {
        _INTL(
          "The Echo Ridge Mine needs clearing - kobold workers have dug in to the north. " \
          "Put down at least {1} of them and report when the ridge is quieter.",
          QuestJournal::ECHO_RIDGE_WORKERS_REQUIRED
        )
      },
      progress_talk: proc {
        _INTL("Have you been to the mines? Thin those workers - we need Echo Ridge back.")
      },
      completion: proc {
        _INTL(
          "I don't like hearing of all these kobolds in our mine. No good can come of this. " \
          "Here's something for your trouble - and when you're ready, we'll speak again about the ridge."
        )
      },
      completion_party_exp: 75,
      completion_money: 40,
      offer_npc_handlers:  [:marshal_mcbride],
      turnin_npc_handlers: [:marshal_mcbride],
      turn_in_ready?: proc {
        QuestJournal.echo_ridge_workers_defeated >= QuestJournal::ECHO_RIDGE_WORKERS_REQUIRED
      }
    },
    ID_SIMPLE_LETTER => {
      name:        proc { _INTL("Simple Letter") },
      objective:   proc { _INTL("Read the Simple Letter and speak to Llane Beshere in Northshire Abbey.") },
      description: proc {
        _INTL(
          "I was asked to bring this to your attention as soon as you returned from dealing with the kobold camps. " \
          "It appears to be a letter sealed with the insignia of Llane, our local warrior trainer. " \
          "I wouldn't hesitate to read it before you go about any other business here in the Abbey."
        )
      },
      giver:       proc { _INTL("Marshal McBride") },
      turnin:      proc { _INTL("Llane Beshere") },
      marshal_offer: proc {
        _INTL("Llane Beshere asked me to pass this sealed letter to you - the warrior trainer has words before you go.")
      },
      completion: proc {
        _INTL(
          "Ah, you got my letter... good.\n" \
          "There's been an influx of warriors in Elwynn recently - which is good for Stormwind, bad for the orcs in the area.\n" \
          "Get yourself squared away, learn the layout of the land, and come back whenever you need training. I'll be here night or day."
        )
      },
      completion_party_exp: 65,
      offer_npc_handlers:  [:marshal_mcbride],
      turnin_npc_handlers: [:llane_beshere],
      turn_in_ready?: proc { true }
    },
    ID_CONSECRATED_LETTER => {
      name:        proc { _INTL("Consecrated Letter") },
      objective:   proc { _INTL("Read the Consecrated Letter and speak to Brother Sammuel in Northshire Abbey.") },
      description: proc {
        _INTL(
          "I was asked to bring this to your attention as soon as you returned from dealing with the kobold camps. " \
          "It appears to be a letter sealed with the insignia of Brother Sammuel, our local paladin trainer. " \
          "I wouldn't hesitate to read it before you go about any other business here in the Abbey."
        )
      },
      giver:       proc { _INTL("Marshal McBride") },
      turnin:      proc { _INTL("Brother Sammuel") },
      marshal_offer: proc {
        _INTL("Brother Sammuel sent this consecrated letter - read it before you take on anything else here.")
      },
      completion: proc {
        _INTL(
          "In the meantime, you should know one or two other things. You are a symbol to many here - act accordingly. " \
          "The Holy Light shines within you, and it will be obvious to both your allies and your enemies.\n" \
          "When you've gained experience in Northshire, come back and I'll teach you what you're ready to learn. Good luck... paladin!"
        )
      },
      completion_party_exp: 65,
      offer_npc_handlers:  [:marshal_mcbride],
      turnin_npc_handlers: [:brother_sammuel],
      turn_in_ready?: proc { true }
    },
    ID_ENCRYPTED_LETTER => {
      name:        proc { _INTL("Encrypted Letter") },
      objective:   proc { _INTL("Read the Encrypted Letter and speak to Jorik Kerridan by the stables behind Northshire Abbey.") },
      description: proc {
        _INTL(
          "I was asked to bring this to your attention as soon as you returned from dealing with the kobold camps. " \
          "It appears to be a letter sealed with the insignia of Jorik, one of our local trainers. " \
          "I wouldn't hesitate to read it before you go about any other business here in the Abbey."
        )
      },
      giver:       proc { _INTL("Marshal McBride") },
      turnin:      proc { _INTL("Jorik Kerridan") },
      marshal_offer: proc {
        _INTL("Jorik Kerridan left this encrypted letter for you - best read it before you vanish into the forest.")
      },
      completion: proc {
        _INTL(
          "You're gonna find a number of outfits that covet our skills... but you remember this: you're your own. " \
          "Don't let anybody bully you into something you don't want to do!\n" \
          "I'm here if you need training. Come by anytime."
        )
      },
      completion_party_exp: 65,
      offer_npc_handlers:  [:marshal_mcbride],
      turnin_npc_handlers: [:jorik_kerridan],
      turn_in_ready?: proc { true }
    },
    ID_HALLOWED_LETTER => {
      name:        proc { _INTL("Hallowed Letter") },
      objective:   proc { _INTL("Read the Hallowed Letter and speak to Priestess Anetta in Northshire Abbey.") },
      description: proc {
        _INTL(
          "I was asked to bring this to your attention as soon as you returned from dealing with the kobold camps. " \
          "It appears to be a letter sealed with the insignia of Priestess Anetta, our local priest trainer. " \
          "I wouldn't hesitate to read it before you go about any other business here in the Abbey."
        )
      },
      giver:       proc { _INTL("Marshal McBride") },
      turnin:      proc { _INTL("Priestess Anetta") },
      marshal_offer: proc {
        _INTL("Priestess Anetta's seal is on this hallowed letter - she asked that you read it before other business.")
      },
      completion: proc {
        _INTL(
          "As you grow in experience, return to me and I will impart what I can. Until then, go with compassion in your heart, " \
          "and let wisdom be your guide. Remember, the world only becomes a better place if you make it so."
        )
      },
      completion_party_exp: 65,
      offer_npc_handlers:  [:marshal_mcbride],
      turnin_npc_handlers: [:priestess_anetta],
      turn_in_ready?: proc { true }
    },
    ID_GLYPHIC_LETTER => {
      name:        proc { _INTL("Glyphic Letter") },
      objective:   proc { _INTL("Read the Glyphic Letter and speak to Khelden Bremen in the abbey library.") },
      description: proc {
        _INTL(
          "I was asked to bring this to your attention as soon as you returned from dealing with the kobold camps. " \
          "It appears to be a letter sealed with the insignia of Khelden, our local mage trainer. " \
          "I wouldn't hesitate to read it before you go about any other business here in the Abbey."
        )
      },
      giver:       proc { _INTL("Marshal McBride") },
      turnin:      proc { _INTL("Khelden Bremen") },
      marshal_offer: proc {
        _INTL("Khelden Bremen sealed this glyphic letter - your mage trainer wants a word before you press on.")
      },
      completion: proc {
        _INTL(
          "Hah - I knew my note wouldn't dissuade you. So you're prepared to challenge anything that stands before you " \
          "in the pursuit of knowledge and power?\n" \
          "You will be feared as much as respected. Seek me out when you need training as you grow stronger."
        )
      },
      completion_party_exp: 65,
      offer_npc_handlers:  [:marshal_mcbride],
      turnin_npc_handlers: [:khelden_bremen],
      turn_in_ready?: proc { true }
    },
    ID_TAINTED_LETTER => {
      name:        proc { _INTL("Tainted Letter") },
      objective:   proc { _INTL("Read the Tainted Letter and speak to Drusilla La Salle beside Northshire Abbey.") },
      description: proc {
        _INTL(
          "I was asked to bring this to your attention as soon as you returned from dealing with the kobold camps. " \
          "It appears to be a letter sealed with the insignia of Drusilla, one of our local trainers. " \
          "I wouldn't hesitate to read it before you go about any other business here in the Abbey."
        )
      },
      giver:       proc { _INTL("Marshal McBride") },
      turnin:      proc { _INTL("Drusilla La Salle") },
      marshal_offer: proc {
        _INTL("Drusilla La Salle's mark is on this tainted letter - read it before you dabble further.")
      },
      completion: proc {
        _INTL(
          "As you grow in power, you will be tempted - you must remember to control yourself. Corruption can come to any practitioner " \
          "of the arcane, especially one who deals with creatures from the Nether.\n" \
          "Return to me when you're ready to learn more."
        )
      },
      completion_party_exp: 65,
      offer_npc_handlers:  [:marshal_mcbride],
      turnin_npc_handlers: [:drusilla_la_salle],
      turn_in_ready?: proc { true }
    }
  }.freeze

  # Class index 0..5 matches PLAYER_CLASS_NAMES (Warrior, Paladin, Rogue, Priest, Mage, Warlock).
  def self.letter_quest_id_for_class_index(class_index)
    case class_index.to_i
    when 0 then ID_SIMPLE_LETTER
    when 1 then ID_CONSECRATED_LETTER
    when 2 then ID_ENCRYPTED_LETTER
    when 3 then ID_HALLOWED_LETTER
    when 4 then ID_GLYPHIC_LETTER
    when 5 then ID_TAINTED_LETTER
    else nil
    end
  end

  # Humans only (race 0); non-human races get no class letter from this chain.
  def self.letter_quest_id_for_current_player
    return nil if !defined?(pbGetPlayerRace) || pbGetPlayerRace != 0
    return nil if !defined?(pbGetPlayerCharacterId)
    return nil if !defined?(character_id_to_class_index)

    cid = pbGetPlayerCharacterId
    return nil if cid.nil?

    idx = character_id_to_class_index(cid)
    letter_quest_id_for_class_index(idx)
  end

  # Quest IDs Marshal may still offer after Kobold Camp Cleanup (pick one at a time in the hub menu).
  def self.marshal_hub_pickup_quest_ids
    out = []
    out.push(ID_INVESTIGATE_ECHO_RIDGE) if offer_available?(ID_INVESTIGATE_ECHO_RIDGE)
    lq = letter_quest_id_for_current_player
    out.push(lq) if lq && offer_available?(lq)
    out
  end

  def self.marshal_hub_has_pending_pickups?
    marshal_hub_pickup_quest_ids.any?
  end

  def self.[](id); DEFINITIONS[id]; end

  def self.description_text(id)
    ent = DEFINITIONS[id]
    return nil if !ent || !ent[:description]
    c = ent[:description]
    c.respond_to?(:call) ? c.call : c
  end

  def self.completion_text(id)
    ent = DEFINITIONS[id]
    return nil if !ent || !ent[:completion]
    c = ent[:completion]
    c.respond_to?(:call) ? c.call : c
  end

  def self.marshal_offer_text(id)
    ent = DEFINITIONS[id]
    return nil if !ent || !ent[:marshal_offer]
    m = ent[:marshal_offer]
    m.respond_to?(:call) ? m.call : m
  end

  def self.progress_talk_text(id)
    ent = DEFINITIONS[id]
    return nil if !ent || !ent[:progress_talk]
    m = ent[:progress_talk]
    m.respond_to?(:call) ? m.call : m
  end

  def self.kobold_trainers_defeated
    pbQuestEnsureGlobals
    $PokemonGlobal.quest_counters ||= {}
    $PokemonGlobal.quest_counters[ID_KOBOLD_CLEANUP].to_i
  end

  def self.echo_ridge_workers_defeated
    pbQuestEnsureGlobals
    $PokemonGlobal.quest_counters ||= {}
    $PokemonGlobal.quest_counters[ID_INVESTIGATE_ECHO_RIDGE].to_i
  end

  # True when this quest can still be picked up (map ! icon on giver NPCs).
  # New quests: add a `when YOUR_ID` branch if pickup is gated; else the default is false.
  def self.offer_available?(quest_id)
    return false if !DEFINITIONS[quest_id]
    return false if pbQuestDone?(quest_id) || pbQuestActive?(quest_id)
    case quest_id
    when ID_MARSHAL_MEET
      true
    when ID_KOBOLD_CLEANUP
      pbQuestDone?(ID_MARSHAL_MEET)
    when ID_INVESTIGATE_ECHO_RIDGE
      pbQuestDone?(ID_KOBOLD_CLEANUP)
    when ID_SIMPLE_LETTER, ID_CONSECRATED_LETTER, ID_ENCRYPTED_LETTER,
         ID_HALLOWED_LETTER, ID_GLYPHIC_LETTER, ID_TAINTED_LETTER
      pbQuestDone?(ID_KOBOLD_CLEANUP) && letter_quest_id_for_current_player == quest_id
    else
      false
    end
  end

  # True when player has accepted this quest but not turned it in (map icon on NPC to return to).
  def self.turnin_marker_available?(quest_id)
    pbQuestActive?(quest_id) && !pbQuestDone?(quest_id)
  end

  # True when an active turn-in NPC may complete the quest (objectives satisfied). Uses DEFINITIONS :turn_in_ready? if present; else conservative false for unknown quests.
  def self.turn_in_ready?(quest_id)
    return false if !DEFINITIONS[quest_id]
    return false unless turnin_marker_available?(quest_id)

    chk = DEFINITIONS[quest_id][:turn_in_ready?]
    return !!chk.call if chk.respond_to?(:call)

    false
  end

  # Symbols used in RPG Maker Script: NorthshireAbbeyEvents.run(:deputy_willem).
  # Matches after merging consecutive Script commands (355 / 655), same as the Interpreter.
  NPC_RUN_SCRIPT_PATTERN = /NorthshireAbbeyEvents\.run\s*\(\s*:(\w+)/

  EVENT_SCRIPT_COMMAND_CODES = [355, 655].freeze

  def self.npc_offer_handlers(quest_entry)
    raw = quest_entry[:offer_npc_handlers] || quest_entry[:offer_npc_handler]
    npc_handlers_normalized(raw)
  end

  def self.npc_turnin_handlers(quest_entry)
    raw = quest_entry[:turnin_npc_handlers] || quest_entry[:turnin_npc_handler]
    npc_handlers_normalized(raw)
  end

  def self.npc_handlers_normalized(raw)
    return [] if raw.nil?

    ary = raw.is_a?(Array) ? raw : [raw]
    ary.flatten.compact.map(&:to_sym)
  end

  # All { mode:, qid: } bindings for one Script symbol (:deputy_willem, etc.).
  def self.marker_specs_for_npc_script_handler(handler_sym)
    s = handler_sym.to_sym
    specs = []
    DEFINITIONS.each do |qid, ent|
      specs.push({ mode: :offer, qid: qid })         if npc_offer_handlers(ent).include?(s)
      specs.push({ mode: :active_turnin, qid: qid }) if npc_turnin_handlers(ent).include?(s)
    end
    specs
  end

  # Scan every event page for NorthshireAbbeyEvents.run(:symbol).
  # RPG Maker splits multi-line Script into several 355/655 commands; merge those blobs first.
  def self.extract_npc_script_symbols_from_game_event(game_event)
    return [] if !defined?(Game_Event) || !game_event.is_a?(Game_Event)

    rm = game_event.instance_variable_get(:@event) rescue nil
    return [] if !rm || !rm.pages

    found = []
    rm.pages.each do |page|
      next if !page || !page.list

      list = page.list
      i = 0
      while i < list.length
        cmd = list[i]
        unless EVENT_SCRIPT_COMMAND_CODES.include?(cmd.code)
          i += 1
          next
        end

        blob = +''
        while i < list.length && EVENT_SCRIPT_COMMAND_CODES.include?(list[i].code)
          blob << list[i].parameters[0].to_s
          blob << "\n" # matches Interpreter command_355 chaining
          i += 1
        end
        blob.scan(NPC_RUN_SCRIPT_PATTERN) { |cap| found << cap[0].to_sym }
      end
    end
    found.uniq
  end

  # Extend via QuestMapMarkers.rb or at runtime  -  each row: `[ [ map_id, event_id ], mode, quest_id ]`
  # Example: QuestJournal::EXTRA_QUEST_MAP_MARKERS.push([[76, 12], :offer, 1])
  EXTRA_QUEST_MAP_MARKERS = []

  def self.quest_title(id)
    ent = DEFINITIONS[id]
    return "" if !ent || !ent[:name]
    v = ent[:name]
    (v.respond_to?(:call) ? v.call : v).to_s
  end

  def self.quest_objective_line(id)
    ent = DEFINITIONS[id]
    return "" if !ent || !ent[:objective]
    v = ent[:objective]
    (v.respond_to?(:call) ? v.call : v).to_s
  end

  # When true, picking up a quest shows title/objective + Auto-accept / Full dialog / Back (see pbQuestDebugOfferChoice).
  USE_QUICK_QUEST_OFFER_MENU = true

  # Legacy: was $DEBUG or save flag; quick menu is now default for all players when USE_QUICK_QUEST_OFFER_MENU.
  def self.debug_offer_ui_enabled?
    return true if USE_QUICK_QUEST_OFFER_MENU
    return true if $DEBUG
    pbQuestEnsureGlobals
    ($PokemonGlobal.quest_debug_quick_offer == true)
  end

  # Stand-in for PokemonPartyScreen; pbChangeExp requires pbRefresh/pbUpdate.
  class CompletionExpScene
    def pbRefresh; end
    def pbUpdate; pbUpdateSceneMap; end
  end
  COMPLETION_EXP_SCENE = CompletionExpScene.new

  # Two top-right stat sheets (deltas, then totals) with a tiny party icon just outside the upper-left corner.
  def self.pbQuestCompletionTopRightWindowPairWithIcon(pkmn, scene, text1, text2)
    viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    viewport.z = 99998
    icon     = nil
    icon_box = nil
    border_w = 2
    inner_pad = 4

    begin
      icon = PokemonIconSprite.new(pkmn, viewport)
      icon.z = 99999
      icon.setOffset(PictureOrigin::TOP_LEFT)
      icon.zoom_x = 0.68
      icon.zoom_y = 0.68
      icon.update
    rescue StandardError
      icon&.dispose
      icon = nil
    end

    stat_win_w = 198
    win_left = Graphics.width - stat_win_w

    if icon && icon.src_rect.width > 0
      iw = (icon.src_rect.width * icon.zoom_x).ceil
      ih = (icon.src_rect.height * icon.zoom_y).ceil
      box_w = border_w * 2 + inner_pad * 2 + iw
      box_h = border_w * 2 + inner_pad * 2 + ih
      bmp = Bitmap.new(box_w, box_h)
      white = Color.new(255, 255, 255)
      edge  = Color.new(72, 72, 72)
      bmp.fill_rect(0, 0, box_w, box_h, white)
      bmp.fill_rect(0, 0, box_w, border_w, edge)
      bmp.fill_rect(0, box_h - border_w, box_w, border_w, edge)
      bmp.fill_rect(0, 0, border_w, box_h, edge)
      bmp.fill_rect(box_w - border_w, 0, border_w, box_h, edge)

      icon_box = Sprite.new(viewport)
      icon_box.bitmap = bmp
      icon_box.z = 99998
      icon_box.x = win_left - box_w - 4
      icon_box.y = 4
      icon_box.x = 4 if icon_box.x < 4

      icon.x = icon_box.x + border_w + inner_pad
      icon.y = icon_box.y + border_w + inner_pad
    end

    [text1, text2].each do |text|
      window = Window_AdvancedTextPokemon.new(text)
      window.width = stat_win_w
      window.x     = win_left
      window.y     = 0
      window.z     = 99999
      pbPlayDecisionSE
      loop do
        Graphics.update
        Input.update
        icon&.update
        window.update
        scene&.pbUpdate
        break if Input.trigger?(Input::USE)
      end
      window.dispose
    end
    icon&.dispose
    icon_box&.bitmap&.dispose
    icon_box&.dispose
    viewport.dispose
  end

  # Same rules as pbChangeExp (gain only), but no lower-third pbMessage spam  -  Exp is summarized once in the quest rewards popup.
  # On level-up: name/lvl message first, then stat panels with icon (learn move / evolution unchanged).
  def self.pbApplyExpGainQuiet(pkmn, new_exp)
    new_exp = new_exp.clamp(0, pkmn.growth_rate.maximum_exp)
    return if pkmn.exp == new_exp

    old_level           = pkmn.level
    old_total_hp        = pkmn.totalhp
    old_attack          = pkmn.attack
    old_defense         = pkmn.defense
    old_special_attack  = pkmn.spatk
    old_special_defense = pkmn.spdef
    old_speed           = pkmn.speed

    difference = new_exp - pkmn.exp
    return if difference <= 0

    pkmn.exp = new_exp
    pkmn.changeHappiness("vitamin")
    pkmn.calc_stats
    COMPLETION_EXP_SCENE.pbRefresh
    return if pkmn.level == old_level

    total_hp_diff        = pkmn.totalhp - old_total_hp
    attack_diff          = pkmn.attack - old_attack
    defense_diff         = pkmn.defense - old_defense
    special_attack_diff  = pkmn.spatk - old_special_attack
    special_defense_diff = pkmn.spdef - old_special_defense
    speed_diff           = pkmn.speed - old_speed

    pbSEPlay("Pkmn level up") rescue nil
    pbMessage(_INTL("{1} grew to Lv. {2}!", pkmn.name, pkmn.level))

    t1 = _INTL("Max. HP<r>+{1}\nAttack<r>+{2}\nDefense<r>+{3}\nSp. Atk<r>+{4}\nSp. Def<r>+{5}\nSpeed<r>+{6}",
               total_hp_diff, attack_diff, defense_diff, special_attack_diff, special_defense_diff, speed_diff)
    t2 = _INTL("Max. HP<r>{1}\nAttack<r>{2}\nDefense<r>{3}\nSp. Atk<r>{4}\nSp. Def<r>{5}\nSpeed<r>{6}",
               pkmn.totalhp, pkmn.attack, pkmn.defense, pkmn.spatk, pkmn.spdef, pkmn.speed)
    pbQuestCompletionTopRightWindowPairWithIcon(pkmn, COMPLETION_EXP_SCENE, t1, t2)

    movelist = pkmn.getMoveList
    movelist.each do |i|
      next if i[0] <= old_level || i[0] > pkmn.level
      pbLearnMove(pkmn, i[1], true) { COMPLETION_EXP_SCENE.pbUpdate }
    end
    new_species = pkmn.check_evolution_on_level_up
    return if !new_species

    pbFadeOutInWithMusic do
      evo = PokemonEvolutionScene.new
      evo.pbStartScreen(pkmn, new_species)
      evo.pbEvolution
      evo.pbEndScreen
    end
  end

  # Award flat Exp to each eligible party member when a quest is completed (see DEFINITIONS :completion_party_exp).
  def self.award_completion_party_exp(quest_id)
    return if !$player
    entry = DEFINITIONS[quest_id]
    return if !entry
    amt = entry[:completion_party_exp]
    return if amt.nil? || amt < 1
    $player.party.each do |pkmn|
      next if !pkmn
      next if pkmn.egg?
      next if pkmn.shadowPokemon?
      next if pkmn.level >= GameData::GrowthRate.max_level ||
              pkmn.exp >= pkmn.growth_rate.maximum_exp
      new_exp = pkmn.growth_rate.add_exp(pkmn.exp, amt)
      pbApplyExpGainQuiet(pkmn, new_exp)
    end
  end

  # Human-readable lines for the quest completion reward popup (no grants).
  def self.completion_reward_summary_lines(quest_id)
    entry = DEFINITIONS[quest_id]
    return [] if !entry

    lines = []
    exp = entry[:completion_party_exp]
    lines.push(_INTL("{1} Exp for each party Pokémon", exp)) if exp && exp >= 1

    money = entry[:completion_money]
    lines.push(_INTL("${1}", money.to_s_formatted)) if money && money >= 1

    items = entry[:completion_items]
    if items.is_a?(Array)
      items.each do |row|
        next if !row.is_a?(Array) || row.length < 2

        qty = row[1].to_i
        next if qty < 1

        item = GameData::Item.try_get(row[0])
        next if !item

        port = (qty > 1) ? item.portion_name_plural : item.portion_name
        lines.push(_INTL("{1} x {2}", qty, port))
      end
    end
    lines
  end

  def self.grant_completion_money(quest_id)
    return if !$player
    entry = DEFINITIONS[quest_id]
    return if !entry
    amt = entry[:completion_money]
    return if amt.nil? || amt < 1

    $player.money += amt
  end

  # Adds items without pbReceiveItem dialogs (summary shown separately).
  def self.grant_completion_items(quest_id)
    return if !$player
    entry = DEFINITIONS[quest_id]
    return if !entry
    items = entry[:completion_items]
    return if !items.is_a?(Array)

    items.each do |row|
      next if !row.is_a?(Array) || row.length < 2

      qty = row[1].to_i
      next if qty < 1

      item = GameData::Item.try_get(row[0])
      next if !item

      unless $bag.add(item, qty)
        pbMessage(_INTL("Your Bag is full - you couldn't receive all quest rewards."))
        break
      end
    end
  end

  # Upper-left quest name + objective before NPC intro dialogue. Skipped when
  # pbQuestDebugOfferChoice just ran (choice non-nil)  -  that menu already lists title/objective.
  def self.pbBeginQuestOfferIntro(quest_id, debug_choice_result = nil)
    return if !DEFINITIONS[quest_id]
    return if debug_choice_result != nil

    pbShowQuestOfferSummaryUpperLeft(quest_id)
  end

  def self.pbShowQuestOfferSummaryUpperLeft(quest_id)
    title = quest_title(quest_id)
    obj   = quest_objective_line(quest_id)
    return if title.to_s.strip.empty? && obj.to_s.strip.empty?

    max_panel_w = [(Graphics.width * 52 / 100).to_i, 420].min
    text        = _INTL("\\c[1]{1}\\c[0]\\n\\n{2}", title, obj)
    window      = Window_AdvancedTextPokemon.new(text)
    window.resizeToFit(text, max_panel_w)
    window.text = text
    window.x    = 8
    window.y    = 8
    window.z    = 99_999
    loop do
      Graphics.update
      Input.update
      window.update
      pbUpdateSceneMap
      break if Input.trigger?(Input::USE)
    end
    window.dispose
  end

  # Upper-right summary (not lower-third Message system). Uses Item get ME.
  def self.pbShowQuestRewardsPopup(lines)
    return if !lines || lines.empty?

    max_panel_w = [(Graphics.width * 52 / 100).to_i, 420].min
    body        = lines.join("\n")
    text        = _INTL("Quest rewards {1}", body)
    pbMEPlay("Item get") rescue nil
    window = Window_AdvancedTextPokemon.new(text)
    window.resizeToFit(text, max_panel_w)
    window.text = text
    window.x = Graphics.width - window.width - 8
    window.y = 8
    window.z = 99_999
    loop do
      Graphics.update
      Input.update
      window.update
      pbUpdateSceneMap
      break if Input.trigger?(Input::USE)
    end
    window.dispose
  end

  # Show the recap popup first so level-up / stat windows from party Exp never appear above it;
  # money, items, and Exp apply after the player dismisses the rewards screen.
  def self.apply_completion_rewards(quest_id)
    return if !$player

    lines = completion_reward_summary_lines(quest_id)
    pbShowQuestRewardsPopup(lines) if lines.any?

    award_completion_party_exp(quest_id)
    grant_completion_money(quest_id)
    grant_completion_items(quest_id)
  end
end

#-------------------------------------------------------------------------------
# Kobold scouts use Essentials AI skill 0 (same tier as wild Pokémon): no ScoreMoves /
# PredictMoveFailure / PreferMultiTargetMoves  -  moves are chosen almost uniformly among valid picks.
# Still a trainer battle (OW NPC); sprite/name stay tied to trainer_type (:KOBOLD).
#-------------------------------------------------------------------------------
class KoboldVerminTrainer < NPCTrainer
  def skill_level
    0
  end

  # Omit PBS trainer-type skill flags so nothing overrides wild-style defaults.
  def flags
    []
  end
end

#-------------------------------------------------------------------------------
# Kobold Cleanup: call once from each defeated kobold **trainer NPC** Script (after you win).
#-------------------------------------------------------------------------------
def pbReportKoboldTrainerDefeat
  pbQuestEnsureGlobals
  qid = QuestJournal::ID_KOBOLD_CLEANUP
  return if !pbQuestActive?(qid)
  $PokemonGlobal.quest_counters ||= {}
  prev = $PokemonGlobal.quest_counters[qid].to_i
  cap  = QuestJournal::KOBOLD_TRAINERS_REQUIRED
  # Avoid double-counting if the Script runs twice without a reload
  $PokemonGlobal.quest_counters[qid] = [prev + 1, cap].min
  n = $PokemonGlobal.quest_counters[qid]
  if n >= cap
    pbMessage(_INTL("You've defeated enough kobold trainers. Report back to Marshal McBride at the abbey."))
  end
end

#-------------------------------------------------------------------------------
# Echo Ridge Mine: call from kobold worker battles (or map events) while the quest is active.
#-------------------------------------------------------------------------------
def pbReportEchoRidgeWorkerDefeat
  pbQuestEnsureGlobals
  qid = QuestJournal::ID_INVESTIGATE_ECHO_RIDGE
  return if !pbQuestActive?(qid)
  $PokemonGlobal.quest_counters ||= {}
  prev = $PokemonGlobal.quest_counters[qid].to_i
  cap  = QuestJournal::ECHO_RIDGE_WORKERS_REQUIRED
  $PokemonGlobal.quest_counters[qid] = [prev + 1, cap].min
  n = $PokemonGlobal.quest_counters[qid]
  if n >= cap
    pbMessage(_INTL("You've culled enough kobold workers. Report to Marshal McBride."))
  end
end

#-------------------------------------------------------------------------------
# Echo Ridge kobold workers: same class of fight as kobold vermin — TrainerBattle with
# KoboldVerminTrainer (skill_level 0, no trainer flags). One rolled party member; no catch UI.
# Call from NorthshireAbbeyEvents.kobold_worker while Investigate Echo Ridge is active.
#-------------------------------------------------------------------------------
def pbBattleEchoRidgeKoboldWorker
  qid = QuestJournal::ID_INVESTIGATE_ECHO_RIDGE
  unless pbQuestActive?(qid)
    pbMessage(_INTL("Work work…"))
    return false
  end

  species, level = case rand(4)
                   when 0 then [:SPINARAK, rand(1..2)]
                   when 1 then [:POOCHYENA, 2]
                   when 2 then [:RATTATA, 2]
                   else         [:PIDGEY, rand(1..2)]
                   end

  trainer = KoboldVerminTrainer.new(_INTL("Kobold Worker"), :KOBOLD, 0)
  trainer.party.push(Pokemon.new(species, level, trainer))
  won = TrainerBattle.start(trainer)
  pbReportEchoRidgeWorkerDefeat if won
  won
end

#-------------------------------------------------------------------------------
# Echo Ridge Mine interior (map 033): kobold laborers — 1–2 Pokémon at level 3.
# Script: NorthshireAbbeyEvents.run(:kobold_laborer)
#-------------------------------------------------------------------------------
def pbBattleEchoRidgeMineLaborer
  pool = [:DIGLETT, :ZUBAT, :RATTATA, :SPINARAK]
  n = rand(2) + 1
  trainer = KoboldVerminTrainer.new(_INTL("Kobold Laborer"), :KOBOLD, 0)
  n.times do
    trainer.party.push(Pokemon.new(pool.sample, 3, trainer))
  end
  TrainerBattle.start(trainer)
end

#-------------------------------------------------------------------------------
# Lowest kobold trainer ("Kobold Vermin"): random Lv.1 from KOBOLD_VERMIN_SPECIES_POOL.
# Uses KoboldVerminTrainer (wild-style AI). NPC Script: pbBattleKoboldVerminTrainer
# Returns true if the player won.
#-------------------------------------------------------------------------------
def pbBattleKoboldVerminTrainer
  trainer = KoboldVerminTrainer.new(_INTL("Kobold Vermin"), :KOBOLD, 0)
  species = QuestJournal::KOBOLD_VERMIN_SPECIES_POOL.sample
  trainer.party.push(Pokemon.new(species, 1, trainer))
  won = TrainerBattle.start(trainer)
  if won
    pbReportKoboldTrainerDefeat
    # Mark the calling event as defeated; its Page 2 (gated on Self Switch A) takes over.
    if pbMapInterpreterRunning?
      ev = pbMapInterpreter.get_self
      if ev.respond_to?(:id) && ev.id && $game_map
        $game_self_switches[[$game_map.map_id, ev.id, "A"]] = true
        $game_map.need_refresh = true
      end
    end
  end
  won
end

#-------------------------------------------------------------------------------
# Generic wander helper. Call from a Custom Move Route Script line:
#   pbWanderInArea(self, X, Y, 3, 3)
# X / Y is the top-left tile of the area (inclusive); W / H are tile dimensions.
#-------------------------------------------------------------------------------
def pbWanderInArea(event, x_min, y_min, w = 2, h = 2)
  return if !event
  return if event.moving? || event.jumping?
  [2, 4, 6, 8].shuffle.each do |d|
    nx = event.x + ((d == 6) ? 1 : (d == 4) ? -1 : 0)
    ny = event.y + ((d == 2) ? 1 : (d == 8) ? -1 : 0)
    next if nx < x_min || nx > x_min + w - 1
    next if ny < y_min || ny > y_min + h - 1
    next if !event.passable?(event.x, event.y, d)
    case d
    when 2 then event.move_down
    when 4 then event.move_left
    when 6 then event.move_right
    when 8 then event.move_up
    end
    return
  end
end

#===============================================================================
#
#===============================================================================
def pbQuestEnsureGlobals
  $PokemonGlobal = PokemonGlobalMetadata.new if !$PokemonGlobal
  $PokemonGlobal.quest_active ||= {}
  $PokemonGlobal.quest_completed ||= {}
  $PokemonGlobal.quest_counters ||= {}
end

def pbQuestDone?(id)
  pbQuestEnsureGlobals
  $PokemonGlobal.quest_completed[id] == true
end

def pbQuestActive?(id)
  pbQuestEnsureGlobals
  $PokemonGlobal.quest_active[id] == true && !pbQuestDone?(id)
end

def pbQuestAccept(id)
  pbQuestEnsureGlobals
  return false if pbQuestDone?(id)
  return false if pbQuestActive?(id)
  $PokemonGlobal.quest_active[id] = true
  if id == QuestJournal::ID_KOBOLD_CLEANUP
    $PokemonGlobal.quest_counters[QuestJournal::ID_KOBOLD_CLEANUP] = 0
  elsif id == QuestJournal::ID_INVESTIGATE_ECHO_RIDGE
    $PokemonGlobal.quest_counters[QuestJournal::ID_INVESTIGATE_ECHO_RIDGE] = 0
  end
  true
end

# Completes quest if it is active; returns true if newly completed now.
def pbQuestComplete(id)
  pbQuestEnsureGlobals
  return false if pbQuestDone?(id)
  return false unless $PokemonGlobal.quest_active[id]
  $PokemonGlobal.quest_active[id] = false
  $PokemonGlobal.quest_completed[id] = true
  QuestJournal.apply_completion_rewards(id)
  true
end

def pbJournalVisibleQuestIds
  pbQuestEnsureGlobals
  QuestJournal::DEFINITIONS.keys.sort.select { |qid| pbQuestActive?(qid) }
end

def pbBeginQuestOfferIntro(quest_id, debug_choice_result = nil)
  QuestJournal.pbBeginQuestOfferIntro(quest_id, debug_choice_result)
end

#-------------------------------------------------------------------------------
# Quick quest-offer menu (default for all players when QuestJournal::USE_QUICK_QUEST_OFFER_MENU).
# Shows quest title + objective, then:
#   Accept now  -  skip NPC flavor text; your Script should pbQuestAccept then exit.
#   Hear them out  -  run the rest of the event (full dialogue then accept prompt).
#   Not now  -  exit without accepting.
# Returns :auto_accept, :full, :cancel, or nil if unknown quest id / no DEFINITIONS entry.
#-------------------------------------------------------------------------------
def pbQuestDebugOfferChoice(quest_id)
  return nil unless QuestJournal.debug_offer_ui_enabled?
  return nil unless QuestJournal::DEFINITIONS[quest_id]

  title = QuestJournal.quest_title(quest_id)
  obj   = QuestJournal.quest_objective_line(quest_id)
  prompt = _INTL("How do you want to proceed?")
  body   = _INTL("\\c[1]{1}\\c[0]\\n\\n{2}\\n\\n{3}", title, obj, prompt)
  cmds = [
    _INTL("Accept now (skip dialogue)"),
    _INTL("Hear them out"),
    _INTL("Not now")
  ]
  r = pbMessage(body, cmds, 3, nil, 0)
  case r
  when 0 then :auto_accept
  when 1 then :full
  else :cancel
  end
end

#-----------------------------------------------------------------------------
# Multi-offer: quest giver lists several available pickups; player picks which
# to negotiate first. Returns chosen quest id, or nil if cancelled / none.
#-----------------------------------------------------------------------------
def pbQuestOfferChooseQuestId(available_ids)
  ids = available_ids.select { |qid| QuestJournal.offer_available?(qid) }
  return nil if ids.empty?

  cmds = ids.map { |qid| QuestJournal.quest_title(qid) }
  cmds.push(_INTL("Never mind"))
  # pbShowCommands(msgwindow, commands, cmdIfCancel, defaultCmd)  -  max 4 args in Essentials v21
  r = pbShowCommands(nil, cmds, cmds.length, 0)
  return nil if r.nil? || r >= ids.length

  ids[r]
end

# Standard NPC offer (quick menu + optional Marshal-style flavor + accept prompt).
# Uses :marshal_offer when present, else :description. Returns true if quest was accepted.
def pbQuestOfferSingleQuestFromNpc(quest_id, accept_label: nil, decline_label: nil)
  return false if !QuestJournal::DEFINITIONS[quest_id]
  return false unless QuestJournal.offer_available?(quest_id)

  dbg = pbQuestDebugOfferChoice(quest_id)
  return false if dbg == :cancel
  pbBeginQuestOfferIntro(quest_id, dbg)
  if dbg == :auto_accept
    if pbQuestAccept(quest_id)
      pbMessage(_INTL("It's in your quest log."))
      return true
    end
    return false
  end

  ent = QuestJournal::DEFINITIONS[quest_id]
  flavor = QuestJournal.marshal_offer_text(quest_id)
  flavor ||= QuestJournal.description_text(quest_id)
  pbMessage(flavor) if flavor

  accept_label  ||= _INTL("I'll do it.")
  decline_label ||= _INTL("Not right now.")
  cmd = pbShowCommands(nil, [accept_label, decline_label], 2)
  if cmd == 0 && pbQuestAccept(quest_id)
    pbMessage(_INTL("It's in your quest log."))
    return true
  end
  false
end

# Legacy opt-in before USE_QUICK_QUEST_OFFER_MENU defaulted on; still toggles save flag for older scripts.
def pbQuestDebugQuickOffer(enabled = true)
  pbQuestEnsureGlobals
  $PokemonGlobal.quest_debug_quick_offer = !!enabled
end

#===============================================================================
# Pause menu opens this UI
#===============================================================================
class PokemonQuestJournal_Scene
  def pbRefreshDescription
    idx = @sprites["list"].index
    qid = @row_ids[idx]
    if !qid
      txt = _INTL("You have no quests in your quest log yet. Accept quests from people in the world.")
    else
      d = QuestJournal::DEFINITIONS[qid]
      if !d
        txt = ""
      else
        obj = d[:objective]
        obj = obj.call if obj.respond_to?(:call)
        desc = d[:description]
        desc = desc.call if desc.respond_to?(:call)
        gvr = d[:giver]
        gvr = gvr.call if gvr.respond_to?(:call)
        fin = d[:turnin]
        fin = fin.call if fin.respond_to?(:call)
        parts = []
        parts.push(_INTL("{1}: {2}", _INTL("Objective"), obj.to_s)) if obj && !obj.to_s.empty?
        parts.push(desc.to_s)
        parts.push(_INTL("{1}: {2}", _INTL("Start"), gvr.to_s))
        parts.push(_INTL("{1}: {2}", _INTL("End"), fin.to_s)) if fin && !fin.to_s.empty?
        txt = parts.join("\\n")
      end
    end
    @sprites["detail"].text = txt
    @sprites["detail"].baseColor   = MessageConfig::LIGHT_TEXT_MAIN_COLOR
    @sprites["detail"].shadowColor = MessageConfig::LIGHT_TEXT_SHADOW_COLOR
    @sprites["detail"].refresh
  end

  def pbUpdate
    i = @sprites["list"].index
    pbUpdateSpriteHash(@sprites)
    if @sprites["list"].index != i
      pbRefreshDescription
    end
  end

  def pbStartScene
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @sprites = {}
    addBackgroundPlane(@sprites, "bg", "Party/bg", @viewport)
    cmds = []
    @row_ids = []
    pbJournalVisibleQuestIds.each do |qid|
      d = QuestJournal::DEFINITIONS[qid]
      next if !d
      name = d[:name]
      name = name.call if name.respond_to?(:call)
      label = name
      cmds.push(label)
      @row_ids.push(qid)
    end
    if cmds.empty?
      cmds.push(_INTL("(No quests yet.)"))
      @row_ids.push(nil)
    end
    @sprites["caption"] = Window_UnformattedTextPokemon.newWithSize(
      _INTL("Quest Log"), 12, -8, 200, 64, @viewport
    )
    @sprites["caption"].windowskin = nil
    lw = Graphics.width - 48
    list_panel_h = [[cmds.length * 34 + 40, Graphics.height / 2 - 32].max, Graphics.height / 2].min
    detail_y = 48 + list_panel_h + 4
    detail_h = Graphics.height - detail_y - 16
    @sprites["list"] = Window_CommandPokemon.newWithSize(
      cmds, 24, 48, lw, list_panel_h, @viewport
    )
    @sprites["detail"] = Window_AdvancedTextPokemon.newWithSize(
      "", 24, detail_y, lw, detail_h.clamp(64, Graphics.height),
      @viewport
    )
    pbRefreshDescription
    pbFadeInAndShow(@sprites) { pbUpdate }
  end

  def pbMain
    pbSEPlay("GUI menu open") rescue nil
    loop do
      Graphics.update
      Input.update
      pbUpdateSceneMap
      pbUpdate
      if Input.trigger?(Input::BACK) || Input.trigger?(Input::ACTION)
        pbPlayCloseMenuSE
        break
      end
    end
  end

  def pbEndScene
    pbFadeOutAndHide(@sprites) { pbUpdate }
    pbDisposeSpriteHash(@sprites)
    @viewport.dispose
  end
end

class PokemonQuestJournalScreen
  def initialize(scene); @scene = scene; end

  def pbScreen
    @scene.pbStartScene
    @scene.pbMain
    @scene.pbEndScene
  end
end

MenuHandlers.add(:pause_menu, :quest_journal, {
  "name"      => _INTL("Quest Log"),
  "order"     => 43,
  "condition" => proc { next !$player.nil? },
  "effect"    => proc { |menu|
    pbPlayDecisionSE
    pbFadeOutIn do
      scene = PokemonQuestJournal_Scene.new
      PokemonQuestJournalScreen.new(scene).pbScreen
      menu.pbRefresh
    end
    next false
  }
})
