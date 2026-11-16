#!/usr/bin/env ruby
# Checks the Bleed status and Rend without booting the game.
# Run from the repo root: ruby tools/check_bleed_rend.rb

ROOT = File.expand_path("..", __dir__)
errors = []

def read(rel)
  path = File.join(ROOT, rel)
  errors_push = nil
  unless File.file?(path)
    return nil
  end
  File.read(path)
end

def fail(msg)
  $errors << msg
end

$errors = []

def must_include(text, needle, where)
  $errors << "#{where} is missing #{needle.inspect}" unless text && text.include?(needle)
end

status = read("Scripts/113_Status.rb")
battler = read("Scripts/164_Battler_Statuses.rb")
moves_pbs = read("PBS/moves.txt")
eor = read("Scripts/158_Battle_EndOfRoundPhase.rb")
effects = read("Scripts/223_PBEffects.rb")
init = read("Scripts/162_Battler_Initialize.rb")
move_fx = read("Scripts/179_MoveEffects_BattlerOther.rb")
custom = read("Scripts/186_MoveEffects_Generation9.rb")
heal = read("Scripts/163_Battler_ChangeSelf.rb")
healing_moves = read("Scripts/176_Move_BaseEffects.rb")
continue = read("Plugins/Generation 9 Pack Scripts/[001] Battle/[003] Weather and Status.rb")
ai = read("Scripts/214_AI_MoveEffects_BattlerOther.rb")
ai_hp = read("Scripts/208_AIBattler.rb")
items = read("Scripts/264_Item_Utilities.rb")
pokemon_pbs = read("PBS/pokemon.txt")

must_include(status, ":id            => :BLEED", "Scripts/113_Status.rb")
must_include(status, 'name          => _INTL("Bleed")', "Scripts/113_Status.rb")
must_include(status, "BLEED_ICON_POSITION    = 10", "Scripts/113_Status.rb")
must_include(battler, "def pbCanBleed?", "Scripts/164_Battler_Statuses.rb")
must_include(battler, "def pbBleed(", "Scripts/164_Battler_Statuses.rb")
must_include(battler, "BLEED_BLOODLESS_EGG_GROUPS = [:Amorphous, :Mineral, :Ditto]", "Scripts/164_Battler_Statuses.rb")
must_include(battler, '"{1} is bleeding!"', "Scripts/164_Battler_Statuses.rb")
must_include(battler, '"{1} is hurt by its bleeding!"', "Scripts/164_Battler_Statuses.rb")
must_include(battler, '"{1}\'s bleeding stopped!"', "Scripts/164_Battler_Statuses.rb")
must_include(continue, '"{1} is hurt by its bleeding!"', "Gen 9 pbContinueStatus")
must_include(eor, "battler.status != :BLEED", "end-of-round bleed damage")
must_include(eor, "battler.totalhp / 8", "end-of-round bleed damage")
must_include(move_fx, "class Battle::Move::BleedTarget < Battle::Move", "BleedTarget")
must_include(move_fx, "target.pbBleed(user) if target.pbCanBleed?(user, false, self)", "BleedTarget targets the foe")
must_include(custom, "class Battle::Move::CustomRend < Battle::Move::BleedTarget", "CustomRend alias")
must_include(heal, "def pbRecoverHPFromActiveHeal", "active heal helper")
must_include(healing_moves, "user.pbRecoverHPFromActiveHeal(amt)", "HealingMove")
must_include(ai, 'MoveEffectAgainstTargetScore.add("BleedTarget"', "Bleed AI score")
must_include(ai_hp, "self.status == :BLEED", "AI residual damage")
must_include(items, "pkmn.status == :BLEED", "bag HP items cure bleed")
must_include(read("Scripts/161_Battle_Battler.rb"), "def pbCanReceiveActiveHeal?", "full-HP bleed can still be healed")

# The old volatile must be gone. A comment may still mention the retired name.
if effects =~ /^\s*RendBleed\s*=/
  $errors << "PBEffects::RendBleed is still defined"
end
if init && init.include?("PBEffects::RendBleed")
  $errors << "battler init still sets RendBleed"
end
if eor && eor.include?("PBEffects::RendBleed")
  $errors << "end of round still ticks RendBleed"
end
if custom && custom.include?("PBEffects::RendBleed")
  $errors << "CustomRend still writes RendBleed"
end

# Passive recovery must not opt into the bleed cure.
passive_files = {
  "Scripts/158_Battle_EndOfRoundPhase.rb" => [
    "Aqua Ring restored",
    "absorbed nutrients with its roots",
    "Grassy Terrain heals"
  ],
  "Scripts/231_Battle_ItemEffects.rb" => [
    "EndOfRoundHealing.add(:LEFTOVERS",
    "EndOfRoundHealing.add(:BLACKSLUDGE"
  ],
  "Scripts/230_Battle_AbilityEffects.rb" => [
    "OnSwitchOut.add(:REGENERATOR"
  ]
}
passive_files.each do |rel, markers|
  text = read(rel)
  markers.each do |marker|
    idx = text.index(marker) if text
    if idx.nil?
      $errors << "#{rel} is missing passive marker #{marker.inspect}"
      next
    end
    window = text[idx, 500]
    if window.include?("pbRecoverHPFromActiveHeal")
      $errors << "#{rel} uses active-heal cure near #{marker.inspect}"
    end
  end
end

# Drain recovery stays on the passive path.
drain = read("Scripts/163_Battler_ChangeSelf.rb")
if drain =~ /def pbRecoverHPFromDrain.*?pbRecoverHPFromActiveHeal/m
  $errors << "drain healing cures Bleed"
end

# Rend's PBS row.
rend = moves_pbs[/^\[REND\]\r?\n(.*?)(?:\r?\n#-+|\z)/m, 1]
if rend.nil?
  $errors << "PBS/moves.txt has no [REND] section"
else
  {
    "Name = Rend" => "name",
    "Type = NORMAL" => "type",
    "Category = Physical" => "category",
    "Power = 40" => "power",
    "Accuracy = 100" => "accuracy",
    "TotalPP = 20" => "pp",
    "Target = NearOther" => "target",
    "FunctionCode = BleedTarget" => "function code",
    "Flags = Contact,CanProtect,CanMirrorMove" => "flags",
    "Description = A vicious strike that makes the target bleed." => "description"
  }.each do |line, label|
    $errors << "Rend #{label} is not #{line.inspect}" unless rend.include?(line)
  end
  $errors << "Rend still uses CustomRend in PBS" if rend.include?("FunctionCode = CustomRend")
end

# Egg-group immunity, using the same group list the battle code declares.
listed = battler[/BLEED_BLOODLESS_EGG_GROUPS = \[(.*?)\]/, 1]
bloodless = listed ? listed.scan(/:(\w+)/).flatten : []
if bloodless.sort != %w[Amorphous Ditto Mineral]
  $errors << "bloodless egg groups are #{bloodless.inspect}, expected Amorphous, Mineral, Ditto"
end
if bloodless.include?("Undiscovered")
  $errors << "Undiscovered must not be bloodless"
end

def egg_groups_for(pbs, species)
  section = pbs[/^\[#{species}\]\r?\n(.*?)(?:\r?\n\[|\z)/m, 1]
  return nil unless section
  line = section[/^EggGroups = (.+)$/, 1]
  return nil unless line
  line.split(",").map(&:strip)
end

def immune?(groups, bloodless)
  return false if groups.nil? || groups.empty?
  groups.all? { |g| bloodless.include?(g) }
end

examples = {
  "MUK" => true,
  "ONIX" => true,
  "STEELIX" => true,
  "KLEFKI" => true,
  "VOLTORB" => true,
  "DITTO" => true,
  "SEVIPER" => false,
  "BULBASAUR" => false,
  "RALTS" => false,
  "STUNFISK" => false
}
examples.each do |species, should_immune|
  groups = egg_groups_for(pokemon_pbs, species)
  if groups.nil?
    $errors << "could not read EggGroups for #{species}"
    next
  end
  got = immune?(groups, bloodless)
  if got != should_immune
    $errors << "#{species} egg groups #{groups.inspect} immune=#{got}, expected #{should_immune}"
  end
end

# Placeholder icon frame exists past the fainted/Pokérus slots.
["Graphics/UI/statuses.png", "Graphics/UI/Battle/icon_statuses.png"].each do |rel|
  path = File.join(ROOT, rel)
  File.open(path, "rb") do |f|
    sig = f.read(8)
    $errors << "#{rel} is not a PNG" if sig != "\x89PNG\r\n\x1A\n".b
    f.read(8)
    w, h = f.read(8).unpack("NN")
    $errors << "#{rel} is #{w}x#{h}, need height >= 176 for icon index 10" if h < 176
  end
end

if $errors.empty?
  puts "Bleed/Rend checks passed."
  exit 0
end

puts "Bleed/Rend checks failed:"
$errors.each { |err| puts "  - #{err}" }
exit 1
