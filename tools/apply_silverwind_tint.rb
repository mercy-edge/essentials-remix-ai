#!/usr/bin/env ruby
# Add light green battle-field tint (fade in/out) to Silver Wind animation timings.
#
# SAFE: writes .anm only (never Data/PkmnAnimations.rxdata).
# After running: ruby tools/json_to_anim_plugin.rb, then in-game import.
#
require "json"
require "zlib"
require "fileutils"

ROOT = File.expand_path("..", __dir__)
SILVERWIND_INDEX = 243

class Color
  attr_accessor :red, :green, :blue, :alpha
  def initialize(r = 0, g = 0, b = 0, a = 255)
    @red = r; @green = g; @blue = b; @alpha = a
  end
  def self.white; new(255, 255, 255); end
end

class AnimFrame
  X = 0; Y = 1; PATTERN = 7; FOCUS = 26; ZOOMX = 2; ZOOMY = 11
  LOCKED = 20; PRIORITY = 25; OPACITY = 8
end

class PBAnimTiming
  attr_accessor :frame, :name, :volume, :pitch
  attr_accessor :colorRed, :colorGreen, :colorBlue, :colorAlpha, :opacity
  attr_accessor :bgX, :bgY, :flashScope, :flashColor, :flashDuration
  attr_writer :timingType, :duration

  def initialize(type = 0)
    @timingType = type
    @frame = 0
    @name = ""
    @volume = 80
    @pitch = 100
    @duration = 5
    @flashScope = 0
    @flashColor = Color.white
    @flashDuration = 5
  end

  def timingType; @timingType || 0; end
  def duration; @duration || 5; end
end

class PBAnimations < Array
  attr_reader :array
  def initialize(*); @array = []; end
  def length; @array.length; end
  def each; @array.each { |i| yield i }; end
  def [](i); @array[i]; end
  def []=(i, v); @array[i] = v; end
end

class PBAnimation < Array
  attr_accessor :id, :name, :graphic, :hue, :position
  attr_writer :speed
  attr_reader :array, :timing
  def speed; @speed || 20; end
  def initialize(*); @array = []; @timing = []; end
  def length; @array.length; end
  def each; @array.each { |i| yield i }; end
  def [](i); @array[i]; end
  def []=(i, v); @array[i] = v; end
end

def dump_anm(anim, path)
  data = [Zlib::Deflate.deflate(Marshal.dump(anim))].pack("m0")
  File.write(path, data)
end

def load_anm(path)
  raw = File.read(path).gsub(/\r\n/, "")
  Marshal.restore(Zlib::Inflate.inflate(raw.unpack("m")[0]))
end

# Light green tint color (RGB). Opacity controls strength via bgColor plane.
TINT_R = 160
TINT_G = 255
TINT_B = 160
TINT_ALPHA = 0
TINT_OPACITY = 72        # peak tint strength (~28%)
FADE_IN_FRAMES = 5       # ~0.25s at 20fps
FADE_OUT_FRAMES = 5
FADE_OUT_START = 13      # 0-based; frames 14-18 fade out after particles

def bg_set(frame, opacity)
  t = PBAnimTiming.new(1)
  t.frame = frame
  t.name = ""
  t.colorRed = TINT_R
  t.colorGreen = TINT_G
  t.colorBlue = TINT_B
  t.colorAlpha = TINT_ALPHA
  t.opacity = opacity
  t
end

def bg_fade(frame, duration, opacity)
  t = PBAnimTiming.new(2)
  t.frame = frame
  t.duration = duration
  t.colorRed = TINT_R
  t.colorGreen = TINT_G
  t.colorBlue = TINT_B
  t.colorAlpha = TINT_ALPHA
  t.opacity = opacity
  t
end

def apply_green_tint!(anim)
  # Keep sound effects; drop previous background tint timings only.
  anim.timing.reject! { |t| t.timingType == 1 || t.timingType == 2 }

  anim.timing << bg_set(0, 0)                          # transparent green overlay
  anim.timing << bg_fade(0, FADE_IN_FRAMES, TINT_OPACITY)  # fade in before particles
  anim.timing << bg_fade(FADE_OUT_START, FADE_OUT_FRAMES, 0) # fade out after particles
  anim.timing << bg_set(anim.length - 1, 0)            # clear on last frame

  anim.timing.sort_by! { |t| [t.frame, t.timingType] }
  anim
end

def save_all(anim)
  anm_path = File.join(ROOT, "silverwind-anim.anm")
  dump_anm(anim, anm_path)
  puts "Updated #{anm_path}"

  folder_anm = File.join(ROOT, "Animations/Move_SILVERWIND/Move_SILVERWIND.anm")
  FileUtils.mkdir_p(File.dirname(folder_anm)) rescue nil
  dump_anm(anim, folder_anm)
  puts "Updated #{folder_anm}"
  puts "Import via F9 > Battle animation editor > slot #{SILVERWIND_INDEX}"

  focus_names = { 1 => "target", 2 => "user", 3 => "user_and_target", 4 => "screen" }
  position_names = { 1 => "target", 2 => "user", 3 => "user_and_target", 4 => "screen" }
  priority_names = { 0 => "back", 1 => "front", 2 => "behind_focus", 3 => "above_focus" }
  pattern_names = { -1 => "user_sprite", -2 => "target_sprite" }
  type_names = ["play_se", "set_bg", "change_bg", "set_fg", "change_fg"]

  frames = anim.length.times.map do |i|
    frame = anim[i]
    cels = frame.filter_map do |c|
      next if !c
      pattern = c[AnimFrame::PATTERN]
      {
        "x" => c[AnimFrame::X], "y" => c[AnimFrame::Y],
        "pattern" => pattern_names[pattern] || pattern,
        "focus" => focus_names[c[AnimFrame::FOCUS]] || c[AnimFrame::FOCUS],
        "zoom_x" => c[AnimFrame::ZOOMX], "zoom_y" => c[AnimFrame::ZOOMY],
        "opacity" => c[AnimFrame::OPACITY], "locked" => c[AnimFrame::LOCKED] != 0
      }
    end
    { "frame" => i + 1, "cels" => cels }
  end

  timings = anim.timing.map do |t|
    h = { "frame" => t.frame + 1, "type" => type_names[t.timingType] || t.timingType }
    h["name"] = t.name if t.name && t.name != ""
    h["volume"] = t.volume if t.timingType == 0
    h["pitch"] = t.pitch if t.timingType == 0
    if t.timingType == 1 || t.timingType == 2
      h["color"] = { "r" => t.colorRed, "g" => t.colorGreen, "b" => t.colorBlue, "a" => t.colorAlpha }
      h["opacity"] = t.opacity
      h["duration"] = t.duration if t.timingType == 2
    end
    h
  end

  json = {
    "index" => SILVERWIND_INDEX,
    "name" => anim.name,
    "graphic" => anim.graphic,
    "hue" => anim.hue,
    "position" => position_names[anim.position] || anim.position,
    "speed" => anim.speed,
    "frame_count" => anim.length,
    "timings" => timings,
    "frames" => frames
  }

  json_path = File.join(ROOT, "Animations_decoded", "Move_SILVERWIND.json")
  File.write(json_path, JSON.pretty_generate(json))
  puts "Updated #{json_path}"
end

anm_path = File.join(ROOT, "silverwind-anim.anm")
anim = load_anm(anm_path)

# Re-add Wind8 if missing after prior timing cleanup.
unless anim.timing.any? { |t| t.timingType == 0 && t.name == "Wind8" }
  wind = PBAnimTiming.new(0)
  wind.frame = 0
  wind.name = "Wind8"
  wind.volume = 80
  wind.pitch = 100
  anim.timing << wind
end

apply_green_tint!(anim)

puts "Timings (#{anim.timing.length}):"
anim.timing.each do |t|
  if t.timingType == 0
    puts "  Frame #{t.frame + 1}: play SE #{t.name}"
  else
    puts "  Frame #{t.frame + 1}: #{t.timingType == 1 ? 'set' : 'fade'} bg " \
         "rgb(#{t.colorRed},#{t.colorGreen},#{t.colorBlue}) opacity=#{t.opacity}" \
         "#{t.timingType == 2 ? " duration=#{t.duration}" : ''}"
  end
end

save_all(anim)
