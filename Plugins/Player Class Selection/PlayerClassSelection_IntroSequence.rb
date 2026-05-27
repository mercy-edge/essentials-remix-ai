#===============================================================================
# Scripted new-game intro (Oak, help, Marill, race → gender → class, name, transfer)
#===============================================================================
# Runs automatically once on new game when the player enters INTRO_MAP_ID, if
# USE_SCRIPTED_INTRO is true. Remove or disable the old Autorun intro event on
# that map so it does not run twice.
#
# Edit the constants in EssentialsRemixIntro (map IDs, picture names, BGM, coords).
#
# The intro is deferred until after Scene_Map's first Graphics.transition. Running it
# inside createSpritesets (while Graphics is still frozen from Scene_Intro / load UI)
# often yields a black screen with no visible messages on RGSS/mkxp.
#===============================================================================

module EssentialsRemixIntro
  USE_SCRIPTED_INTRO = true

  INTRO_MAP_ID     = 1
  END_MAP_ID       = 76
  END_X            = 15
  END_Y            = 13
  END_DIR          = 6   # 2=down 4=left 6=right 8=up

  INTRO_BGM        = "New Start"
  FADE_BGM_SEC     = 4.0

  PIC_BG           = "introbg"
  PIC_BASE         = "introbase"
  PIC_OAK          = "introOak"
  PIC_MARILL       = "introMarill"
  PIC_BOY          = "introBoy"
  PIC_GIRL         = "introGirl"
  PIC_ADVENTURE_BG = "helpadventurebg"

  @running = false

  class << self
    attr_accessor :running

    def pbIntroUpdate
      Graphics.update
      Input.update
      $game_screen.update
      pbUpdateSceneMap
    end

    def pbIntroWaitFrames(n)
      n.times { pbIntroUpdate }
    end

    def pbIntroWaitMoveTicks(ticks)
      t = ticks / 20.0
      timer_start = System.uptime
      loop do
        pbIntroUpdate
        break if System.uptime - timer_start >= t
      end
    end

    def pbIntroPicShow(num, name, origin, x, y, zoomX = 100, zoomY = 100, opacity = 255, blendType = 0)
      $game_screen.pictures[num].show(name, origin, x, y, zoomX, zoomY, opacity, blendType)
    end

    def pbIntroPicMove(num, duration, origin, x, y, zoomX, zoomY, opacity, blendType = 0)
      $game_screen.pictures[num].move(duration, origin, x, y, zoomX, zoomY, opacity, blendType)
    end

    def pbIntroPicErase(num)
      $game_screen.pictures[num].erase
    end

    def pbIntroErasePictures(*nums)
      nums.each { |n| pbIntroPicErase(n) }
    end

    def pbIntroHelpLoop
      loop do
        pbMessage(_INTL("\\bIf you need help, I am certainly capable of giving it."))
        cmd = pbShowCommands(nil,
                             [_INTL("Controls"), _INTL("Adventure"), _INTL("No info needed")],
                             -1, 0)
        case cmd
        when 0
          pbEventScreen(ButtonEventScene)
        when 1
          pbToneChangeAll(Tone.new(-255, -255, -255, 0), 10)
          pbIntroWaitMoveTicks(10)
          pbIntroPicShow(4, PIC_ADVENTURE_BG, 0, 0, 0, 100, 100, 0, 0)
          pbIntroPicMove(4, 10, 0, 0, 0, 100, 100, 255, 0)
          pbIntroWaitMoveTicks(10)
          pbIntroWaitFrames(10)
          pbMessage(_INTL("<ac>\\c[0]\\[3]You are about to enter a world\\nwhere you will embark on a grand\\nadventure of your very own."))
          pbMessage(_INTL("<ac>\\c[0]\\[5]Speak to people and check things\\nwherever you go, be it in towns,\\nroads or caves.\\nGather information and hints from\\nevery possible source."))
          pbMessage(_INTL("<ac>\\c[0]\\[3]New paths will open to you when\\nyou help people in need, overcome\\nchallenges, and solve mysteries."))
          pbMessage(_INTL("<ac>\\c[0]\\[7]At times, you will be challenged\\nby others to a battle.\\nAt other times, wild creatures\\nmay stand in your way.\\n\\nBy overcoming such hurdles, \\nyou will gain great power."))
          pbMessage(_INTL("<ac>\\c[0]\\[2]However, your adventure is not\\nsolely about becoming powerful."))
          pbMessage(_INTL("<ac>\\c[0]\\[7]On your travels, we hope that\\nyou will meet countless people\\nand, through them, achieve\\npersonal growth.\\n\\nThis is the most important\\nobjective of this adventure."))
          pbIntroPicMove(4, 10, 0, 0, 0, 100, 100, 0, 0)
          pbIntroWaitMoveTicks(10)
          pbIntroPicErase(4)
          pbToneChangeAll(Tone.new(0, 0, 0, 0), 10)
          pbIntroWaitMoveTicks(10)
          pbMessage(_INTL("\\bWell then, without further ado..."))
        when 2
          break
        end
      end
    end

    def pbIntroMarillAndOak2
      pbIntroWaitFrames(5)
      pbIntroPicMove(3, 10, 1, 256, 172, 100, 100, 0, 0)
      pbIntroWaitMoveTicks(10)
      pbIntroPicErase(3)
      pbIntroPicShow(3, PIC_MARILL, 1, 256, 220, 100, 100, 0, 0)
      pbIntroPicMove(3, 10, 1, 256, 220, 100, 100, 255, 0)
      pbIntroWaitMoveTicks(10)
      pbIntroWaitFrames(10)
      pbMessage(_INTL("\\bThis world is inhabited by creatures we call Pokémon."))
      pbMessage(_INTL("\\bPeople and Pokémon live together by supporting each other."))
      pbMessage(_INTL("\\bSome people play with Pokémon, some battle with them."))
      pbIntroWaitFrames(5)
      pbIntroPicMove(3, 10, 1, 256, 220, 100, 100, 0, 0)
      pbIntroWaitMoveTicks(10)
      pbIntroPicErase(3)
      pbIntroPicShow(3, PIC_OAK, 1, 256, 172, 100, 100, 0, 0)
      pbIntroPicMove(3, 10, 1, 256, 172, 100, 100, 255, 0)
      pbIntroWaitMoveTicks(10)
      pbIntroWaitFrames(10)
      pbMessage(_INTL("\\bBut we don't know everything about Pokémon yet."))
      pbMessage(_INTL("\\bThere are still many mysteries to solve."))
      pbMessage(_INTL("\\bThat's why I study Pokémon every day."))
      pbIntroWaitFrames(5)
      pbIntroPicMove(2, 10, 1, 256, 256, 100, 100, 0, 0)
      pbIntroPicMove(3, 10, 1, 256, 172, 100, 100, 0, 0)
      pbIntroWaitMoveTicks(10)
      pbIntroPicErase(2)
      pbIntroPicErase(3)
      pbIntroWaitFrames(15)
    end

    def pbResolvePicture?(name)
      return false if !name || name.empty?
      return FileTest.image_exist?("Graphics/Pictures/#{name}")
    end

    def pbIntroRaceGenderClassAndPreview
      pbMessage(_INTL("\\bWhat race will you be?"))
      pbChoosePlayerRace

      pbMessage(_INTL("\\bAre you a boy or a girl?"))
      cmd_gender = pbShowCommands(nil, [_INTL("Boy"), _INTL("Girl")], -1, 0)
      cmd_gender = 0 if cmd_gender.nil? || cmd_gender < 0
      gender_id = (cmd_gender == 0) ? 1 : 2
      pbChangePlayerForGender(gender_id)

      pbChoosePlayerClass(gender_id)

      preview = (gender_id == 1) ? PIC_BOY : PIC_GIRL
      preview = PIC_BOY if !pbResolvePicture?(preview)
      pbIntroPicShow(3, preview, 1, 256, 178, 100, 100, 0, 0)
      pbIntroPicMove(3, 10, 1, 256, 178, 100, 100, 255, 0)
      pbIntroWaitMoveTicks(10)
      pbIntroWaitFrames(10)
    end

    def pbIntroNameLoop
      loop do
        pbMessage(_INTL("\\bNow what did you say your name was?"))
        pbTrainerName
        pbIntroWaitFrames(5)
        pbMessage(_INTL("\\bSo you're \\PN?"))
        yes = pbShowCommands(nil, [_INTL("Yes"), _INTL("No")], -1, 0)
        break if yes == 0
        pbMessage(_INTL("\\bWhat is your name?"))
      end
    end

    def pbIntroClosingAndTransfer
      pbMessage(_INTL("\\b\\PN, are you ready?"))
      pbMessage(_INTL("\\bYour very own Pokémon story is about to unfold."))
      pbMessage(_INTL("\\bYou'll face fun times and tough challenges."))
      pbMessage(_INTL("\\bA world of dreams and adventures with Pokémon awaits! Let's go!"))
      pbMessage(_INTL("\\bEnjoy the Starter Kit. You should give credit when using it."))
      pbBGMFade(FADE_BGM_SEC)
      pbToneChangeAll(Tone.new(-255, -255, -255, 0), 10)
      pbIntroWaitMoveTicks(10)
      pbIntroErasePictures(1, 2, 3)
      $game_temp.player_transferring = true
      $game_temp.player_new_map_id    = END_MAP_ID
      $game_temp.player_new_x         = END_X
      $game_temp.player_new_y         = END_Y
      $game_temp.player_new_direction  = END_DIR
      if $scene.is_a?(Scene_Map)
        $scene.transfer_player(false)
      end
      # Match Hearthstone to this spawn (map 76 Northshire etc.) — not intro map 001's first :on_enter_map bind.
      pbSetHearthstoneSpotExplicit(END_MAP_ID, END_X, END_Y, END_DIR) if defined?(pbSetHearthstoneSpotExplicit)
      pbToneChangeAll(Tone.new(0, 0, 0, 0), 10)
      pbIntroWaitMoveTicks(10)
    end

    def pbRunRemixIntroSequence
      return if !USE_SCRIPTED_INTRO
      $PokemonGlobal = PokemonGlobalMetadata.new if !$PokemonGlobal
      return if $PokemonGlobal.intro_sequence_complete

      pbMessage(_INTL("<ac>\\c[8]\\[3](Please refer to the\\nPokémon Essentials Wiki\\nfor documentation.)"))
      Graphics.freeze
      pbIntroPicShow(1, PIC_BG, 0, 0, 0, 100, 100, 255, 0)
      Graphics.transition(40)
      pbIntroWaitFrames(18)

      pbIntroPicShow(2, PIC_BASE, 1, 256, 256, 100, 100, 0, 0)
      pbIntroPicShow(3, PIC_OAK, 1, 256, 172, 100, 100, 0, 0)
      pbIntroPicMove(2, 15, 1, 256, 256, 100, 100, 255, 0)
      pbIntroPicMove(3, 15, 1, 256, 172, 100, 100, 255, 0)
      pbIntroWaitMoveTicks(15)
      pbIntroWaitFrames(18)

      pbBGMPlay(INTRO_BGM, 100, 100)
      pbMessage(_INTL("\\bHello! Sorry to keep you waiting!"))
      pbMessage(_INTL("\\bWelcome to the world of Pokémon."))
      pbMessage(_INTL("\\bMy name is Oak."))
      pbMessage(_INTL("\\bPeople call me the Pokémon Professor."))

      pbIntroHelpLoop
      pbIntroMarillAndOak2
      pbIntroRaceGenderClassAndPreview
      pbIntroNameLoop
      pbGiveNewGameRaceClassStarterPokemonSilent
      pbGiveNewGameHearthstoneSilent
      pbIntroClosingAndTransfer

      $PokemonGlobal.intro_sequence_complete = true
    end

    # After Scene_Map's opening Graphics.transition — see EssentialsRemixIntro_SceneMapMainDeferral.
    def pbRunRemixIntroAfterMapTransition
      return if !USE_SCRIPTED_INTRO
      return if !$game_temp&.remix_intro_pending
      $game_temp.remix_intro_pending = false
      return if !$game_temp.begun_new_game
      return if !$game_map
      $PokemonGlobal = PokemonGlobalMetadata.new if !$PokemonGlobal
      return if $PokemonGlobal.intro_sequence_complete
      return if $game_map.map_id != INTRO_MAP_ID
      return if running
      self.running = true
      begin
        pbRunRemixIntroSequence
      ensure
        self.running = false
      end
    end
  end
end

def pbRunRemixIntroSequence
  EssentialsRemixIntro.pbRunRemixIntroSequence
end

if EssentialsRemixIntro::USE_SCRIPTED_INTRO
  class Game_Temp
    attr_accessor :remix_intro_pending
  end

  EventHandlers.add(:on_map_or_spriteset_change, :essentials_remix_intro_sequence,
    proc { |_scene, _map_changed|
      next if !$game_map
      next if !$game_temp&.begun_new_game
      next if $PokemonGlobal&.intro_sequence_complete
      next if $game_map.map_id != EssentialsRemixIntro::INTRO_MAP_ID
      next if EssentialsRemixIntro.running
      $game_temp.remix_intro_pending = true
    }
  )

  module EssentialsRemixIntro_SceneMapMainDeferral
    def main
      createSpritesets
      Graphics.transition
      EssentialsRemixIntro.pbRunRemixIntroAfterMapTransition
      loop do
        Graphics.update
        Input.update
        update
        break if $scene != self
      end
      Graphics.freeze
      dispose
      if $game_temp.title_screen_calling
        pbMapInterpreter.command_end if pbMapInterpreterRunning?
        $game_temp.last_uptime_refreshed_play_time = nil
        $game_temp.title_screen_calling = false
        pbBGMFade(1.0)
        Graphics.transition
        Graphics.freeze
      end
    end
  end

  Scene_Map.prepend(EssentialsRemixIntro_SceneMapMainDeferral)
end
