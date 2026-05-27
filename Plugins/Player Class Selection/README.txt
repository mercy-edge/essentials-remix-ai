Player Race, Gender & Class Selection - Usage
==============================================

Intro flow: 1) Name  2) Race  3) Gender  4) Class

  1. Name input (your existing intro).
  2. Script: pbChoosePlayerRace
     Shows: Human, Dwarf, Gnome, Night Elf. Stores choice in $PokemonGlobal.player_race (0-3).
  3. Gender choice (e.g. Show Choices "Boy" / "Girl").
     In the Boy branch: Script: pbChangePlayerForGender(1)
     In the Girl branch: Script: pbChangePlayerForGender(2)
  4. Script: pbChoosePlayerClass(1) in the Boy branch, or pbChoosePlayerClass(2) in the Girl branch.
     Shows: Warrior, Paladin, Mage, Warlock, Priest, Rogue. Sets final character by race + gender + class.

Intro event example (Script commands, in order):

  pbChoosePlayerRace
  --- Boy branch ---
  pbChangePlayerForGender(1)
  pbChoosePlayerClass(1)
  --- Girl branch ---
  pbChangePlayerForGender(2)
  pbChoosePlayerClass(2)

Races and character ID ranges:
  Human (0):     IDs 1-12   (male 1,3,5,7,9,11  female 2,4,6,8,10,12)
  Dwarf (1):      IDs 13-24
  Gnome (2):      IDs 25-36
  Night Elf (3):  IDs 37-48

Classes (same order for each race): Warrior, Paladin, Mage, Warlock, Priest, Rogue.

To use the chosen race elsewhere (e.g. dialogue): pbGetPlayerRace returns 0-3 (Human, Dwarf, Gnome, Night Elf).

To add or rename races/classes, edit:
  - Plugins/Player Class Selection/PlayerClassSelection.rb (PLAYER_RACE_NAMES, PLAYER_CLASS_NAMES)
  - PBS/metadata.txt (IDs 1-48; you can add race-specific WalkCharset etc. for [13]-[48])

Compiling:
  - Run the game with Ctrl (or Shift) held to recompile plugins, or delete Data/PluginScripts.rxdata and run once.
  - After changing PBS/metadata.txt, use Debug → Compile Data or run the game so PBS is recompiled.
