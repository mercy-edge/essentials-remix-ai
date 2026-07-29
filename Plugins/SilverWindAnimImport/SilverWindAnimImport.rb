#===============================================================================
# Import custom Silver Wind battle animation into PkmnAnimations.rxdata
# using in-game save_data (RGSS-safe).
#
# Do NOT use Battle animation editor > Import Anim for external .anm files
# created by tools/ — they use Ruby 3 Marshal and will fail to load.
#
# Debug > Other editors... > Import Silver Wind animation
#===============================================================================
module SilverWindAnimImport
  module_function

  def apply!
    slot = AnimationData::SLOT
    animations = pbLoadBattleAnimations
    if !animations
      pbMessage(_INTL("Could not load battle animations."))
      return false
    end
    if slot < 0 || slot >= animations.length
      pbMessage(_INTL("Animation slot {1} is out of range.", slot))
      return false
    end
    anim = AnimationData.build_animation
    animations[slot] = anim
    save_data(animations, "Data/PkmnAnimations.rxdata")
    $game_temp.battle_animations_data = nil
    # Write a valid RGSS .anm the editor CAN import later (optional backup).
    begin
      path = "Move_SILVERWIND_imported.anm"
      File.open(path, "wb") { |f| f.write(BattleAnimationEditor.dumpBase64Anim(anim)) }
      pbMessage(_INTL("Imported {1} into slot {2}.\r\n\r\nAlso saved {3} (valid for Import Anim).\r\n\r\nDo not use silverwind-anim.anm or other files from tools/ — those are invalid.", anim.name, slot, path))
    rescue
      pbMessage(_INTL("Imported {1} into slot {2}.", anim.name, slot))
    end
    return true
  rescue => e
    pbMessage(_INTL("Import failed: {1}", e.message))
    return false
  end
end

MenuHandlers.add(:debug_menu, :import_silverwind_anim, {
  "name"        => _INTL("Import Silver Wind animation"),
  "parent"      => :editors_menu,
  "description" => _INTL("Apply the custom Move:SILVERWIND animation (slot 243)."),
  "effect"      => proc {
    SilverWindAnimImport.apply!
  }
})
