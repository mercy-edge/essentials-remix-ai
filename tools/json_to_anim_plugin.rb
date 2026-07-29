#!/usr/bin/env ruby
# Generates Plugins/SilverWindAnimImport/animation_data.rb from decoded JSON.
require "json"
require "fileutils"

ROOT = File.expand_path("..", __dir__)
JSON_PATH = File.join(ROOT, "Animations_decoded", "Move_SILVERWIND.json")
OUT_PATH = File.join(ROOT, "Plugins", "SilverWindAnimImport", "animation_data.rb")

FOCUS = { "target" => 1, "user" => 2, "user_and_target" => 3, "screen" => 4 }
PRIORITY = { "back" => 0, "front" => 1, "behind_focus" => 2, "above_focus" => 3 }
TYPE = { "play_se" => 0, "set_bg" => 1, "change_bg" => 2, "set_fg" => 3, "change_fg" => 4 }

data = JSON.parse(File.read(JSON_PATH))

lines = []
lines << "# Auto-generated from #{File.basename(JSON_PATH)} — do not edit by hand."
lines << "module SilverWindAnimImport"
lines << "  module AnimationData"
lines << "    SLOT = #{data['index']}"
lines << "    NAME = #{data['name'].inspect}"
lines << ""
lines << "    def self.build_animation"
lines << "      anim = PBAnimation.new"
lines << "      anim.name = #{data['name'].inspect}"
lines << "      anim.graphic = #{data['graphic'].inspect}"
lines << "      anim.hue = #{data['hue']}"
lines << "      anim.position = #{FOCUS.fetch(data['position'], 1)}"
lines << "      anim.instance_variable_set(:@speed, #{data['speed']})"
lines << "      anim.array.clear"
lines << "      anim.timing.clear"
lines << ""

data["timings"].each do |t|
  tt = TYPE.fetch(t["type"], 0)
  lines << "      t = PBAnimTiming.new(#{tt})"
  lines << "      t.frame = #{t['frame'] - 1}"
  if t["name"] && !t["name"].empty?
    lines << "      t.name = #{t['name'].inspect}"
  end
  lines << "      t.volume = #{t['volume']}" if t["volume"]
  lines << "      t.pitch = #{t['pitch']}" if t["pitch"]
  if t["color"]
    c = t["color"]
    lines << "      t.colorRed = #{c['r']}"
    lines << "      t.colorGreen = #{c['g']}"
    lines << "      t.colorBlue = #{c['b']}"
    lines << "      t.colorAlpha = #{c['a']}"
  end
  lines << "      t.opacity = #{t['opacity']}" if t.key?("opacity")
  lines << "      t.duration = #{t['duration']}" if t["duration"]
  lines << "      anim.timing << t"
  lines << ""
end

data["frames"].each_with_index do |frame, fi|
  lines << "      frame = []"
  frame["cels"].each_with_index do |cel, ci|
    pattern = cel["pattern"]
    pattern = -1 if pattern == "user_sprite"
    pattern = -2 if pattern == "target_sprite"
    focus = FOCUS.fetch(cel["focus"], 1)
    priority = PRIORITY.fetch(cel["priority"], 1)
    lines << "      c = pbCreateCel(#{cel['x']}, #{cel['y']}, #{pattern}, #{focus})"
    lines << "      c[AnimFrame::ZOOMX] = #{cel['zoom_x']}"
    lines << "      c[AnimFrame::ZOOMY] = #{cel['zoom_y'] || cel['zoom_x']}"
    lines << "      c[AnimFrame::ANGLE] = #{cel['angle'] || 0}"
    lines << "      c[AnimFrame::MIRROR] = #{cel['mirror'] ? 1 : 0}"
    lines << "      c[AnimFrame::OPACITY] = #{cel['opacity']}"
    lines << "      c[AnimFrame::BLENDTYPE] = #{cel['blend_type'] || 0}"
    lines << "      c[AnimFrame::VISIBLE] = #{cel['visible'] == false ? 0 : 1}"
    lines << "      c[AnimFrame::LOCKED] = #{cel['locked'] ? 1 : 0}"
    lines << "      c[AnimFrame::PRIORITY] = #{priority}"
    lines << "      frame[#{ci}] = c"
  end
  lines << "      anim.array[#{fi}] = frame"
  lines << ""
end

lines << "      return anim"
lines << "    end"
lines << "  end"
lines << "end"

FileUtils.mkdir_p(File.dirname(OUT_PATH))
File.write(OUT_PATH, lines.join("\n"))
puts "Wrote #{OUT_PATH}"
