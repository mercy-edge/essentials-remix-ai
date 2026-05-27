#===============================================================================
# Player Race, Gender & Class Selection
#===============================================================================
# Intro flow: 1) Name  2) Race (pbChoosePlayerRace)  3) Gender  4) Class (pbChoosePlayerClass)
#
# Race is chosen first (Human, Dwarf, Gnome, Night Elf), stored in $PokemonGlobal.player_race (0-3).
# Then gender: call pbChangePlayer(1 + race_offset) for male or pbChangePlayer(2 + race_offset) for female,
#   where race_offset = $PokemonGlobal.player_race * 12  (or use pbChangePlayerForGender(1) / (2)).
# Then call pbChoosePlayerClass(1) or pbChoosePlayerClass(2) — race is read from $PokemonGlobal.
#===============================================================================

# Allow storing chosen race (0 = Human, 1 = Dwarf, 2 = Gnome, 3 = Night Elf)
# player_character_id = last character ID passed to pbChangePlayer (1–48); used for class/race lookups
if defined?(PokemonGlobalMetadata)
  class PokemonGlobalMetadata
    attr_accessor :player_race
    attr_accessor :player_character_id
    # Set by PlayerClassSelection_IntroSequence after the scripted intro finishes.
    attr_accessor :intro_sequence_complete
    # True after race/class starter was added (one-time per save; prevents duplicates).
    attr_accessor :race_class_starter_given
  end
end

PLAYER_RACE_NAMES = ["Human", "Dwarf", "Gnome", "Night Elf"]

# Races that are currently available (only Human by default; add 1,2,3 when Dwarf/Gnome/Night Elf are ready)
PLAYER_RACE_AVAILABLE = [0]  # 0 = Human only

def pbChoosePlayerRace
  $PokemonGlobal = PokemonGlobalMetadata.new if !$PokemonGlobal
  commands = PLAYER_RACE_NAMES.map { |name| _INTL(name) }
  msg = _INTL("Choose your race.")
  loop do
    pbMessage(msg)
    if defined?(pbShowCommands)
      cmd = pbShowCommands(nil, commands)
    else
      cmd = pbMessage(msg, commands, -1) rescue -1
    end
    cmd = 0 if cmd.nil? || cmd < 0
    if PLAYER_RACE_AVAILABLE.include?(cmd)
      $PokemonGlobal.player_race = cmd
      return cmd
    end
    pbMessage(_INTL("That race is not available yet. Please choose another."))
  end
end

# Returns the race index (0-3) for character ID math; default 0 (Human) if not set
def pbGetPlayerRace
  return 0 if !$PokemonGlobal || $PokemonGlobal.player_race.nil?
  r = $PokemonGlobal.player_race.to_i
  r = 0 if r < 0 || r >= PLAYER_RACE_NAMES.size
  return r
end

# Call after gender choice: gender_id 1 = male, 2 = female. Uses current race to set player character.
def pbChangePlayerForGender(gender_id)
  race = pbGetPlayerRace
  race_offset = race * 12
  base = (gender_id == 2) ? 2 : 1
  character_id = base + race_offset
  pbChangePlayer(character_id)
  $PokemonGlobal = PokemonGlobalMetadata.new if !$PokemonGlobal
  $PokemonGlobal.player_character_id = character_id
end

# List of class names (must match character ID pairs 1–2, 3–4, … 11–12 per race in metadata.txt).
# Order is the single class menu order (index 0..5 maps to those ID pairs).
PLAYER_CLASS_NAMES = ["Warrior", "Paladin", "Rogue", "Priest", "Mage", "Warlock"]

# One entry per class (same order as PLAYER_CLASS_NAMES). Shown in the class menu as you move the cursor.
# Edit these strings for your game; favored types from PLAYER_CLASS_SPECIALIZED_TYPES are appended automatically.
PLAYER_CLASS_DESCRIPTIONS = [
  "Frontline bruiser - high physical pressure and staying power.",
  "Armored champion - balances defense with searing, draconic strikes.",
  "Skirmisher - speed, tricks, and punishing single-target damage.",
  "Support and sustain - shields allies and exploits holy lightning.",
  "Elemental caster - ranged burst and control with fire, ice, and mind.",
  "Dark summoner - afflictions, ghosts, and overwhelming shadow pressure."
]

# Pokemon types specialized to each class (for damage bonuses, move preferences, etc.)
# Type IDs match PBS/types.txt (e.g. GameData::Type.get("FIRE")).
PLAYER_CLASS_SPECIALIZED_TYPES = {
  "Warrior" => ["FIGHTING", "STEEL", "NORMAL", "GROUND"],
  "Paladin" => ["STEEL", "GROUND", "FIRE", "DRAGON"],
  "Rogue"   => ["DARK", "POISON", "ICE", "FIGHTING"],
  "Priest"  => ["PSYCHIC", "FAIRY", "ELECTRIC", "GHOST"],
  "Mage"    => ["FIRE", "ICE", "PSYCHIC", "WATER"],
  "Warlock" => ["DARK", "GHOST", "DRAGON", "ROCK"]
}

# Level 1 starter species for new game (race index, class index 0..5). Only Human (0) is defined; extend when more races ship.
HUMAN_CLASS_START_SPECIES = {
  0 => :MACHOP,     # Warrior
  1 => :TRAPINCH,   # Paladin
  2 => :BUDEW,      # Rogue
  3 => :PICHU,      # Priest
  4 => :CYNDAQUIL,  # Mage
  5 => :AXEW        # Warlock
}

# Returns a species symbol or nil if unconfigured for this race/class.
def pbSpeciesForRaceClassStarter(race_index, class_index)
  return nil if class_index.nil? || class_index < 0 || class_index >= PLAYER_CLASS_NAMES.size
  case race_index
  when 0
    return HUMAN_CLASS_START_SPECIES[class_index]
  else
    return nil
  end
end

# For dual-gender species only: male player (odd character ID) → male Pokémon; female → female.
# Skips single-gender / genderless species (Essentials cannot override those).
def pbApplyStarterGenderMatchPlayer!(pkmn)
  return if !pkmn.is_a?(Pokemon)
  return if pkmn.singleGendered?

  cid = pbGetPlayerCharacterId
  return if cid.nil?
  # Character IDs from pbChangePlayerForGender: 1,3,5,… = male; 2,4,6,… = female (per race block).
  if cid.odd?
    pkmn.makeMale
  else
    pkmn.makeFemale
  end
end

# Adds the race/class starter at level 1 without obtain screen. Call once after class + name are set on a new game.
def pbGiveNewGameRaceClassStarterPokemonSilent
  return false if !$player
  $PokemonGlobal = PokemonGlobalMetadata.new if !$PokemonGlobal
  return false if $PokemonGlobal.race_class_starter_given

  character_id = pbGetPlayerCharacterId
  return false if character_id.nil?
  class_idx = character_id_to_class_index(character_id)
  species = pbSpeciesForRaceClassStarter(pbGetPlayerRace, class_idx)
  return false if species.nil?
  return false if !GameData::Species.exists?(species)

  pkmn = Pokemon.new(species, 1)
  pbApplyStarterGenderMatchPlayer!(pkmn)
  ok = pbAddPokemonSilent(pkmn, 1, true)
  $PokemonGlobal.race_class_starter_given = true if ok
  ok
end

# Character ID = (gender_base + class_index*2) + race*12. Race 0 = Human (1-12), 1 = Dwarf (13-24), 2 = Gnome (25-36), 3 = Night Elf (37-48).
def player_class_to_character_id(gender_character_id, class_index, race_index = 0)
  return nil if gender_character_id != 1 && gender_character_id != 2
  return nil if class_index < 0 || class_index >= PLAYER_CLASS_NAMES.size
  race_index = 0 if race_index < 0 || race_index >= PLAYER_RACE_NAMES.size
  base = gender_character_id + (class_index * 2)
  base + (race_index * 12)
end

def pbPlayerClassSelectionHelpTexts
  # pbShowCommandsWithHelp sets Window_AdvancedTextPokemon.text directly, so RPG-style \b/\n from
  # pbMessageDisplay never runs. Use formatted tags (<b>, newline) understood by getFormattedText.
  PLAYER_CLASS_NAMES.map.with_index do |name, i|
    localized_name = _INTL(name)
    desc = _INTL(PLAYER_CLASS_DESCRIPTIONS[i] || "")
    raw_types = PLAYER_CLASS_SPECIALIZED_TYPES[name]
    type_part = if raw_types && !raw_types.empty?
      "\n\n" + _INTL("{1}: {2}", _INTL("Favored types"), raw_types.join(", "))
    else
      ""
    end
    "<b>" + localized_name + "</b>\n" + desc + type_part
  end
end

def pbChoosePlayerClass(gender_character_id = nil)
  # If gender not passed, try to infer from current player (character 1 = male, 2 = female)
  if gender_character_id.nil?
    gender_character_id = 1  # default male if called without arg; better to pass explicitly
    if defined?(pbGetPlayerCharacterIndex) && pbGetPlayerCharacterIndex
      gender_character_id = pbGetPlayerCharacterIndex
    end
  end
  gender_character_id = 1 if gender_character_id != 1 && gender_character_id != 2

  commands = PLAYER_CLASS_NAMES.map { |name| _INTL(name) }
  help_texts = pbPlayerClassSelectionHelpTexts
  pbMessage(_INTL("Choose your class."))
  if defined?(pbShowCommandsWithHelp)
    cmd = pbShowCommandsWithHelp(nil, commands, help_texts, -1, 0)
  elsif defined?(pbShowCommands)
    cmd = pbShowCommands(nil, commands)
  else
    cmd = pbMessage(_INTL("Choose your class."), commands, -1) rescue -1
  end
  cmd = -1 if cmd.nil?
  return if cmd < 0

  race_index = pbGetPlayerRace
  new_character_id = player_class_to_character_id(gender_character_id, cmd, race_index)
  return if new_character_id.nil?

  pbChangePlayer(new_character_id)
  $PokemonGlobal = PokemonGlobalMetadata.new if !$PokemonGlobal
  $PokemonGlobal.player_character_id = new_character_id
end

# Returns the current player's character ID (1–48), or nil if not set. Set by pbChangePlayerForGender / pbChoosePlayerClass.
def pbGetPlayerCharacterId
  return nil if !$PokemonGlobal || $PokemonGlobal.player_character_id.nil?
  id = $PokemonGlobal.player_character_id.to_i
  return nil if id < 1 || id > 48
  id
end

# Derives class index (0–5) from character ID. Character ID = (gender_base + class_index*2) + race*12.
def character_id_to_class_index(character_id)
  return 0 if character_id.nil? || character_id < 1 || character_id > 48
  ((character_id - 1) % 12) / 2
end

# For dialogue and any map: Warrior, Paladin, … — same strings as the class menu (_INTL for translation).
# Call this everywhere you need "{1}" in pbMessage instead of copying logic per map/plugin.
def pbGetPlayerClassDisplayName
  character_id = pbGetPlayerCharacterId
  character_id = 1 if character_id.nil? || character_id < 1 || character_id > 48
  idx = character_id_to_class_index(character_id)
  name = PLAYER_CLASS_NAMES[idx]
  return _INTL("traveler") if name.nil? || name.empty?
  _INTL(name)
end

# Returns the array of type IDs (strings) specialized to the current player's class, or [] if unknown.
def pbGetPlayerClassSpecializedTypes
  character_id = pbGetPlayerCharacterId
  character_id = 1 if character_id.nil?  # fallback: male Warrior
  class_index = character_id_to_class_index(character_id)
  class_name = PLAYER_CLASS_NAMES[class_index]
  return [] if class_name.nil?
  PLAYER_CLASS_SPECIALIZED_TYPES[class_name] || []
end
