#===============================================================================
# NpcHoverTooltip — overworld mouse hover: NPC name + level, colored by relation.
#
# Event page Comments (optional):
#   NPC_LEVEL:12
#   NPC_RELATION:friendly   | neutral | hostile
#
# If NPC_LEVEL is omitted, level defaults to 1. If NPC_RELATION is omitted,
# relation is inferred: sight(N)/trainer(N) in event name => hostile;
# counter(N) => neutral; "Kobold Worker" / "Kobold Vermin" / "Kobold Laborer" => neutral;
# else friendly.
#===============================================================================
module NpcHoverTooltip
  DEFAULT_LEVEL = 1

  COLORS = {
    friendly:  { accent: Color.new(72, 210, 110), shadow: Color.new(16, 72, 36) },
    neutral:   { accent: Color.new(230, 210, 72), shadow: Color.new(92, 72, 16) },
    hostile:   { accent: Color.new(235, 82, 82), shadow: Color.new(92, 24, 24) }
  }.freeze

  class << self
    attr_accessor :viewport, :sprite, :cache_key
  end

  module_function

  def self.zoom_screen_x(logical_x)
    zx = TilemapRenderer::ZOOM_X
    return logical_x if zx == 1

    ((logical_x - Graphics.width / 2) * zx) + Graphics.width / 2
  end

  def self.zoom_screen_y(logical_y)
    zy = TilemapRenderer::ZOOM_Y
    return logical_y if zy == 1

    ((logical_y - Graphics.height / 2) * zy) + Graphics.height / 2
  end

  def self.parse_comments(list)
    level = nil
    relation = nil
    return [nil, nil] if !list

    list.each do |cmd|
      next if cmd.code != 108 && cmd.code != 408

      text = cmd.parameters[0].to_s
      if (m = text.match(/^\s*NPC_LEVEL:\s*(\d+)/i))
        level = m[1].to_i
      elsif (m = text.match(/^\s*NPC_RELATION:\s*(\w+)/i))
        sym = m[1].downcase.to_sym
        relation = sym if [:friendly, :neutral, :hostile].include?(sym)
      end
    end
    [level, relation]
  end

  def self.inferred_relation(event)
    n = event.name.to_s
    return :hostile if n =~ /(?:sight|trainer)\s*\(\d+\)/i
    return :neutral if n =~ /counter\s*\(\d+\)/i
    # Talk-to-fight kobolds (Echo Ridge / Northshire) — not aggressive until engaged
    return :neutral if n =~ /\bKobold\s+(Worker|Vermin|Laborer)\b/i

    :friendly
  end

  def self.resolve_level(event)
    lv, = parse_comments(event.list)
    lv = DEFAULT_LEVEL if lv.nil?
    lv.clamp(1, 999)
  end

  def self.resolve_relation(event)
    _lv, rel = parse_comments(event.list)
    rel ||= inferred_relation(event)
    rel
  end

  def self.skip_event?(event)
    return true if !event || event.character_name.to_s == ""
    return true if event.transparent
    return true if event.name.to_s.strip == ""
    return true if event.name[/hiddenitem/i]
    return true if event.name[/reflection/i]

    false
  end

  def self.hit_character_rect(event)
    w = event.sprite_size[0]
    h = event.sprite_size[1]
    if w <= 0 || h <= 0
      w = event.width * Game_Map::TILE_WIDTH
      h = Game_Map::TILE_HEIGHT * 2
    end
    cx = event.screen_x
    bottom = event.screen_y
    top = bottom - h
    left = cx - w / 2
    right = cx + w / 2
    [left, top, right, bottom]
  end

  def self.mouse_in_rect?(mx, my, left, top, right, bottom)
    sl = zoom_screen_x(left)
    sr = zoom_screen_x(right)
    st = zoom_screen_y(top)
    sb = zoom_screen_y(bottom)
    # Normalize if zoom flips ordering (shouldn't)
    l, r = [sl, sr].minmax
    t, b = [st, sb].minmax
    mx >= l && mx <= r && my >= t && my <= b
  end

  def self.pick_event(mx, my)
    best = nil
    best_z = -999_999
    $game_map.events.each_value do |e|
      next if skip_event?(e)

      left, top, right, bottom = hit_character_rect(e)
      next if !mouse_in_rect?(mx, my, left, top, right, bottom)

      h = e.sprite_size[1]
      h = Game_Map::TILE_HEIGHT * 2 if h <= 0
      z = e.screen_z(h)
      if z > best_z
        best_z = z
        best = e
      end
    end
    best
  end

  def self.ensure_ui
    return if self.viewport && !self.viewport.disposed?

    self.viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    self.viewport.z = 999_999
    self.sprite = Sprite.new(self.viewport)
    self.sprite.z = 0
    self.cache_key = nil
  end

  def self.hide
    return if !self.sprite || self.sprite.disposed?

    self.sprite.visible = false
    self.cache_key = nil
  end

  def self.dispose_ui
    self.sprite&.dispose
    self.viewport&.dispose
    self.sprite = nil
    self.viewport = nil
    self.cache_key = nil
  end

  def self.font_main_name
    MessageConfig.pbTryFonts(MessageConfig::FONT_NAME)
  end

  def self.tooltip_font_size
    [MessageConfig::SMALL_FONT_SIZE - 4, 12].max
  end

  def self.paint_tooltip(name_str, level_str, relation, ox, oy)
    ensure_ui
    pad   = 6
    border = 2
    colors = COLORS[relation] || COLORS[:friendly]
    accent = colors[:accent]
    acc_shadow = colors[:shadow]
    lvl_base = MessageConfig::LIGHT_TEXT_MAIN_COLOR
    lvl_shade = MessageConfig::LIGHT_TEXT_SHADOW_COLOR

    old_bmp = self.sprite.bitmap
    old_bmp&.dispose
    tmp = Bitmap.new(1, 1)
    tmp.font.name = font_main_name
    tmp.font.size = tooltip_font_size
    w_name = tmp.text_size(name_str).width
    w_lvl = tmp.text_size(level_str).width
    tmp.dispose

    inner_w = [w_name, w_lvl].max + pad * 2
    line_h = tooltip_font_size + 4
    inner_h = line_h * 2 + pad * 2
    bw = inner_w + border * 2
    bh = inner_h + border * 2

    bmp = Bitmap.new(bw, bh)
    bmp.font.name = font_main_name
    bmp.font.size = tooltip_font_size

    # Border
    bmp.fill_rect(0, 0, bw, bh, accent)
    bmp.fill_rect(border, border, bw - border * 2, bh - border * 2, Color.new(16, 24, 28, 235))

    # Name (accent)
    pbDrawShadowText(bmp, border + pad, border + pad, inner_w, line_h, name_str, accent, acc_shadow, 0)
    # Level (default dialogue colors)
    pbDrawShadowText(bmp, border + pad, border + pad + line_h, inner_w, line_h, level_str, lvl_base, lvl_shade, 0)

    self.sprite.bitmap = bmp
    self.sprite.ox = 0
    self.sprite.oy = 0

    margin = 12
    x = ox + margin
    y = oy + margin
    x = x.clamp(0, Graphics.width - bw)
    y = y.clamp(0, Graphics.height - bh)
    self.sprite.x = x
    self.sprite.y = y
    self.sprite.visible = true
  end

  def self.update
    return if !$PokemonSystem || $PokemonSystem.npc_hover_tooltip == 1
    return if !$scene.is_a?(Scene_Map)
    return if $game_temp.in_menu || $game_temp.in_battle
    return if $game_temp.message_window_showing
    return if pbMapInterpreterRunning?

    mouse = Mouse.getMousePos
    if !mouse
      hide
      return
    end

    mx, my = mouse
    ev = pick_event(mx, my)
    if !ev
      hide
      return
    end

    rel = resolve_relation(ev)
    lvl = resolve_level(ev)
    name_str = ev.name.to_s
    level_str = _INTL("Lv. {1}", lvl)
    key = "#{ev.map_id}_#{ev.id}_#{name_str}_#{lvl}_#{rel}"
    if key != self.cache_key
      paint_tooltip(name_str, level_str, rel, mx, my)
      self.cache_key = key
    elsif self.sprite&.bitmap
      bw = self.sprite.bitmap.width
      bh = self.sprite.bitmap.height
      margin = 12
      self.sprite.x = (mx + margin).clamp(0, [Graphics.width - bw, 0].max)
      self.sprite.y = (my + margin).clamp(0, [Graphics.height - bh, 0].max)
    end
  end
end

EventHandlers.add(:on_frame_update, :npc_hover_tooltip_update, proc {
  NpcHoverTooltip.update
})

EventHandlers.add(:on_leave_map, :npc_hover_tooltip_hide, proc { |_id, _map|
  NpcHoverTooltip.hide
})
