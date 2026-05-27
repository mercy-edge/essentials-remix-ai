#===============================================================================
# Overhead quest indicators (PNG above NPCs).
#-------------------------------------------------------------------------------
# When you add a new quest — full checklist lives in Plugins/Quest Journal/QuestJournal.rb
# right above DEFINITIONS (IDs, offer_npc_handlers / turnin_npc_handlers,
# turn_in_ready?, offer_available?, Script :symbol or dispatch registry, PNGs).
#
# Rule: linking NPCs is done ONCE on each entry in QuestJournal::DEFINITIONS:
#   • offer_npc_handlers — Script symbol(s) whose dialogue can ACCEPT this quest:
#           quest_available icon while QuestJournal.offer_available?(quest_id).
#   • turnin_npc_handlers — NPC turns in an active quest:
#           question_complete / quest_waiting (see marker_graphics_kind).
#
# Matching an event: Script call NorthshireAbbeyEvents.run(:deputy_willem).
# Works as one Script row or split across several Script rows (RM merges 355/655 like Interpreter).
# The scanner concatenates those rows before matching marker rules from DEFINITIONS.
#
# Fallbacks (generic maps / legacy):
# • Event Name: questoffer(ID) / questturnin(ID)
# • QuestJournal::EXTRA_QUEST_MAP_MARKERS (map_id, event_id, mode)
#
# If you use NorthshireAbbeyEvents.dispatch_from_interpreter only, set
# NorthshireAbbeyEvents::DISPATCH_MARKER_EVENT_HANDLERS in NorthshireAbbey_Events.rb.
#
# GRAPHICS — no extension in code; Essentials loads .png / .gif via AnimatedBitmap.
# Basenames (place under Graphics/Icons or Graphics/icons; first match wins):
#   quest_available.png   — new quest pickup (!)
#   question_complete.png OR quest_complete.png — turn-in ready (?)
#   quest_waiting.png     — active, objectives incomplete
# Resolution uses pbResolveBitmap on each path (RTP + mkxp-friendly).
# With no PNG, a colored placeholder badge is drawn so NPCs wired to quests still show a marker.

#
# Priority (one icon): question_complete → quest_available → quest_waiting.
# All three use the same sprite class, screen anchor math, bob, z, and PNG/placeholder fallback.
#===============================================================================

module QuestJournal
  ICON_BOB_RADIUS = 3
  ICON_Z_ABOVE    = 80
  # Extra pixels upward on screen (smaller self.y) so the badge clears hair/hats.
  ICON_VERTICAL_LIFT = 28
  # Add to self.y (moves marker down). Use ~3–5 so the bitmap bottom overlaps the NPC sprite top slightly.
  ICON_HEAD_OVERLAP_PX = 4

  # Bitmap search lists for marker_graphics_kind values (:question_complete = turn-in-ready art).
  def self.marker_bitmap_paths_for_kind(kind)
    case kind
    when :question_complete then resolve_question_complete_bitmap_paths
    when :quest_waiting     then resolve_quest_waiting_bitmap_paths
    else                         resolve_quest_marker_bitmap_paths
    end
  end

  # question_complete → quest_available → quest_waiting (see file header).
  def self.marker_graphics_kind(map_id, event)
    pbQuestEnsureGlobals
    specs = marker_rules_for_event(map_id, event)

    active_turnins = specs.select do |s|
      s[:mode] == :active_turnin && DEFINITIONS[s[:qid]] && turnin_marker_available?(s[:qid])
    end
    if active_turnins.any? { |s| turn_in_ready?(s[:qid]) }
      return :question_complete
    end

    if specs.any? { |s| s[:mode] == :offer && DEFINITIONS[s[:qid]] && offer_available?(s[:qid]) }
      return :quest_available
    end

    if active_turnins.any?
      return :quest_waiting
    end

    nil
  end

  def self.marker_rules_for_event(map_id, event)
    specs = []
    n = event.name.to_s
    n.scan(/questoffer\s*\(\s*(\d+)\s*\)/i) do |cap|
      specs.push({ mode: :offer, qid: cap[0].to_i })
    end
    n.scan(/questturnin\s*\(\s*(\d+)\s*\)/i) do |cap|
      specs.push({ mode: :active_turnin, qid: cap[0].to_i })
    end
    QuestJournal.extract_npc_script_symbols_from_game_event(event).each do |sym|
      specs.concat(QuestJournal.marker_specs_for_npc_script_handler(sym))
    end
    if defined?(NorthshireAbbeyEvents) &&
       NorthshireAbbeyEvents.respond_to?(:marker_specs_for_dispatch_registry)
      specs.concat(NorthshireAbbeyEvents.marker_specs_for_dispatch_registry(map_id, event.id))
    end
    QuestJournal::EXTRA_QUEST_MAP_MARKERS.each do |row|
      next if !row.is_a?(Array) || row.length < 3
      next if !row[0].is_a?(Array) || row[0].length < 2

      mid, eid = row[0][0].to_i, row[0][1].to_i
      next if mid != map_id.to_i || eid != event.id.to_i

      specs.push({ mode: row[1].to_sym, qid: row[2].to_i })
    end
    seen = {}
    specs.select do |s|
      k = "#{s[:mode]}_#{s[:qid]}"
      next false if seen[k]

      seen[k] = true
    end
  end

  def self.marker_tracked_event?(map_id, event)
    marker_rules_for_event(map_id, event).any?
  end

  def self.marker_visible_any?(map_id, event)
    !marker_graphics_kind(map_id, event).nil?
  end

  def self.resolve_quest_marker_bitmap_paths
    %w[
      Graphics/Icons/quest_available
      Graphics/icons/quest_available
      Graphics/Icon/quest_available
      Graphics/icon/quest_available
      Graphics/Pictures/quest_available
    ]
  end

  def self.resolve_question_complete_bitmap_paths
    %w[
      Graphics/Icons/question_complete
      Graphics/icons/question_complete
      Graphics/Icon/question_complete
      Graphics/icon/question_complete
      Graphics/Pictures/question_complete
      Graphics/Icons/quest_complete
      Graphics/icons/quest_complete
      Graphics/Icon/quest_complete
      Graphics/icon/quest_complete
      Graphics/Pictures/quest_complete
    ]
  end

  def self.resolve_quest_waiting_bitmap_paths
    %w[
      Graphics/Icons/quest_waiting
      Graphics/icons/quest_waiting
      Graphics/Icon/quest_waiting
      Graphics/icon/quest_waiting
      Graphics/Pictures/quest_waiting
    ]
  end

  # Shown above NPCs only when PNGs resolve to nothing — replace by adding Graphics/... files.
  def self.marker_placeholder_bitmap(kind)
    w = 22
    h = 26
    b = Bitmap.new(w, h)
    bg = Color.new(28, 28, 32)
    b.fill_rect(0, 0, w, h, bg)
    case kind
    when :question_complete
      col = Color.new(60, 200, 80)
      lbl = '?'
    when :quest_waiting
      col = Color.new(220, 185, 50)
      lbl = '!'
    else # :quest_available
      col = Color.new(228, 55, 55)
      lbl = '!'
    end
    b.fill_rect(2, 2, w - 4, h - 4, col)
    b.font.bold = true
    b.font.size = 17
    b.font.color = Color.new(248, 248, 248)
    b.draw_text(0, 0, w, h, lbl, 1)
    b
  end
end

#-------------------------------------------------------------------------------
class Sprite_QuestJournalMarker < RPG::Sprite
  # mkxp-z may query Sprite subclasses via visible?; Essentials RGSS uses `visible` / `visible=`.
  def visible?
    visible
  end

  def initialize(map, game_event, viewport)
    super(viewport)
    @map         = map
    @game_event  = game_event
    @marker_kind = nil
    @anim        = nil
    @placeholder_bm = nil
    self.z = 9999
    @frame = rand(144)
    sync_marker_graphic
  end

  def dispose
    discard_marker_graphics
    super
  end

  def discard_marker_graphics
    self.bitmap = nil
    @anim&.dispose
    @anim = nil
    @placeholder_bm&.dispose
    @placeholder_bm = nil
    @marker_kind = nil
  end

  # Uses pbResolveBitmap (RTP/archives), not pbRgssExists? — RPG Maker often cannot see Graphics otherwise.
  def find_bitmap_base(list)
    list.each do |base|
      next if base.to_s.strip.empty?

      return base if pbResolveBitmap(base)
    end
    nil
  end

  def sync_marker_graphic
    kind = QuestJournal.marker_graphics_kind(@map.map_id, @game_event)

    if kind.nil?
      discard_marker_graphics
      return
    end

    return if kind == @marker_kind && (@anim || @placeholder_bm)

    self.bitmap = nil
    @anim&.dispose
    @anim = nil
    @placeholder_bm&.dispose
    @placeholder_bm = nil
    @marker_kind = kind

    path_base = find_bitmap_base(QuestJournal.marker_bitmap_paths_for_kind(kind))
    if path_base
      @anim = AnimatedBitmap.new(path_base)
      self.bitmap = @anim.bitmap
    else
      @placeholder_bm = QuestJournal.marker_placeholder_bitmap(kind)
      self.bitmap = @placeholder_bm
    end

    self.ox = (bitmap&.width.to_i > 0) ? (bitmap.width / 2) : 0
    self.oy = (bitmap&.height.to_i > 0) ? bitmap.height : 0
  end

  # Shared placement for :question_complete, :quest_available, and :quest_waiting.
  def position_marker_above_event(bob)
    fh = (@game_event.sprite_size && @game_event.sprite_size[1]) ? @game_event.sprite_size[1] : Game_Map::TILE_HEIGHT
    if (Object.const_defined?(:ScreenPosHelper) rescue false)
      self.x = ScreenPosHelper.pbScreenX(@game_event)
      self.y = ScreenPosHelper.pbScreenY(@game_event) - (@game_event.height * Game_Map::TILE_HEIGHT / 2) -
               (bitmap ? bitmap.height : 24) / 4 - QuestJournal::ICON_VERTICAL_LIFT +
               QuestJournal::ICON_HEAD_OVERLAP_PX + bob
      self.zoom_x = ScreenPosHelper.pbScreenZoomX(@game_event)
      self.zoom_y = self.zoom_x
    else
      this_x = @game_event.screen_x
      this_x = ((this_x - (Graphics.width / 2)) * TilemapRenderer::ZOOM_X) + (Graphics.width / 2) if TilemapRenderer::ZOOM_X != 1
      this_y = @game_event.screen_y
      this_y = ((this_y - (Graphics.height / 2)) * TilemapRenderer::ZOOM_Y) + (Graphics.height / 2) if TilemapRenderer::ZOOM_Y != 1
      self.x = this_x
      self.y = this_y - (@game_event.respond_to?(:bob_height) ? @game_event.bob_height.to_i : 0) -
               [(bitmap&.height.to_i > 0) ? bitmap.height : 28, Game_Map::TILE_HEIGHT].min / 3 -
               QuestJournal::ICON_VERTICAL_LIFT + QuestJournal::ICON_HEAD_OVERLAP_PX + bob
      self.zoom_x = TilemapRenderer::ZOOM_X
      self.zoom_y = TilemapRenderer::ZOOM_Y
    end

    sz = (@game_event.screen_z(fh).to_i + QuestJournal::ICON_Z_ABOVE)
    sz += 4096 # draw above fog (z 3000) and most characters
    self.z = sz
  end

  def refresh_visibility
    return if disposed?
    sync_marker_graphic
    visible = !$game_temp&.message_window_showing &&
              QuestJournal.marker_visible_any?(@map.map_id, @game_event)
    self.visible = visible && bitmap && bitmap.width.to_i > 0
  end

  def update
    super
    return if disposed? || !$game_player

    refresh_visibility
    return unless visible?

    bob = QuestJournal::ICON_BOB_RADIUS * Math.sin((@frame * Math::PI) / 180.0)
    @frame = (@frame + 2) % 360

    position_marker_above_event(bob)
    self.opacity = (@game_event.transparent) ? 0 : 255
    if @anim
      @anim.update
      self.bitmap = @anim.bitmap
    end
    pbDayNightTint(self) rescue nil
  end
end

EventHandlers.add(:on_new_spriteset_map, :quest_journal_map_markers,
  proc { |spriteset, viewport|
    map = spriteset.map
    map.events.each_value do |event|
      next unless QuestJournal.marker_tracked_event?(map.map_id, event)

      spriteset.addUserSprite(Sprite_QuestJournalMarker.new(map, event, viewport))
    end
  }
)
