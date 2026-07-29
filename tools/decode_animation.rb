#!/usr/bin/env ruby
# Decodes a Pokemon Essentials battle animation from PkmnAnimations.rxdata to JSON.
# Usage: ruby tools/decode_animation.rb SILVERWIND
#        ruby tools/decode_animation.rb "Move:SILVERWIND"
#        ruby tools/decode_animation.rb 250

require "json"

ROOT = File.expand_path("..", __dir__)

class Color
  def initialize(r = 0, g = 0, b = 0, a = 255); end
  def self.white; new(255, 255, 255); end
end

class AnimFrame
  X = 0; Y = 1; ZOOMX = 2; ANGLE = 3; MIRROR = 4; BLENDTYPE = 5
  VISIBLE = 6; PATTERN = 7; OPACITY = 8; ZOOMY = 11
  COLORRED = 12; COLORGREEN = 13; COLORBLUE = 14; COLORALPHA = 15
  TONERED = 16; TONEGREEN = 17; TONEBLUE = 18; TONEGRAY = 19
  LOCKED = 20; FLASHRED = 21; FLASHGREEN = 22; FLASHBLUE = 23
  FLASHALPHA = 24; PRIORITY = 25; FOCUS = 26
end

class PBAnimTiming
  attr_accessor :frame, :name, :volume, :pitch, :bgX, :bgY, :opacity
  attr_accessor :colorRed, :colorGreen, :colorBlue, :colorAlpha
  attr_accessor :flashScope, :flashColor, :flashDuration
  attr_writer :timingType, :duration
  def timingType; @timingType || 0; end
  def duration; @duration || 5; end
end

class PBAnimations < Array
  attr_reader :array
  attr_accessor :selected
  def initialize(*); @array = []; @selected = 0; end
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

FOCUS_NAMES = { 1 => "target", 2 => "user", 3 => "user_and_target", 4 => "screen" }
POSITION_NAMES = { 1 => "target", 2 => "user", 3 => "user_and_target", 4 => "screen" }
PRIORITY_NAMES = { 0 => "back", 1 => "front", 2 => "behind_focus", 3 => "above_focus" }
PATTERN_NAMES = { -1 => "user_sprite", -2 => "target_sprite" }

def cel_to_hash(cel)
  return nil if !cel
  pattern = cel[AnimFrame::PATTERN]
  {
    "x" => cel[AnimFrame::X],
    "y" => cel[AnimFrame::Y],
    "pattern" => PATTERN_NAMES[pattern] || pattern,
    "focus" => FOCUS_NAMES[cel[AnimFrame::FOCUS]] || cel[AnimFrame::FOCUS],
    "zoom_x" => cel[AnimFrame::ZOOMX],
    "zoom_y" => cel[AnimFrame::ZOOMY],
    "angle" => cel[AnimFrame::ANGLE],
    "mirror" => cel[AnimFrame::MIRROR] != 0,
    "opacity" => cel[AnimFrame::OPACITY],
    "blend_type" => cel[AnimFrame::BLENDTYPE],
    "visible" => cel[AnimFrame::VISIBLE] == 1,
    "locked" => cel[AnimFrame::LOCKED] != 0,
    "priority" => PRIORITY_NAMES[cel[AnimFrame::PRIORITY]] || cel[AnimFrame::PRIORITY]
  }
end

def timing_to_hash(t)
  return nil if !t
  type = t.timingType
  h = {
    "frame" => t.frame + 1,
    "type" => ["play_se", "set_bg", "change_bg", "set_fg", "change_fg"][type] || type
  }
  h["name"] = t.name if t.name && t.name != ""
  h["volume"] = t.volume if type == 0
  h["pitch"] = t.pitch if type == 0
  h["flash_scope"] = t.flashScope if t.flashScope && t.flashScope != 0
  h["flash_duration"] = t.flashDuration if t.flashDuration
  h
end

def anim_to_hash(anim, index)
  frames = []
  anim.length.times do |i|
    frame = anim[i]
    next if !frame
    cels = []
    frame.length.times do |j|
      c = cel_to_hash(frame[j])
      cels << c if c
    end
    frames << { "frame" => i + 1, "cels" => cels } if cels.any?
  end
  {
    "index" => index,
    "name" => anim.name,
    "graphic" => anim.graphic,
    "hue" => anim.hue,
    "position" => POSITION_NAMES[anim.position] || anim.position,
    "speed" => anim.speed,
    "frame_count" => anim.length,
    "timings" => anim.timing.map { |t| timing_to_hash(t) }.compact,
    "frames" => frames
  }
end

def find_animation(data, query)
  if query =~ /^\d+$/
    idx = query.to_i
    return [idx, data[idx]] if data[idx]
    return nil
  end
  name = query
  name = "Move:#{name}" if !name.include?(":")
  data.each_with_index { |anim, i| return [i, anim] if anim && anim.name == name }
  data.each_with_index { |anim, i| return [i, anim] if anim && anim.name&.upcase&.include?(query.upcase) }
  nil
end

query = ARGV[0] || "SILVERWIND"
data = Marshal.load(File.binread(File.join(ROOT, "Data/PkmnAnimations.rxdata")))
result = find_animation(data, query)
if !result
  puts "Animation not found: #{query}"
  exit 1
end

idx, anim = result
out_name = anim.name.gsub(/\W+/, "_")
out_dir = File.join(ROOT, "Animations_decoded")
Dir.mkdir(out_dir) rescue nil
out_path = File.join(out_dir, "#{out_name}.json")
File.write(out_path, JSON.pretty_generate(anim_to_hash(anim, idx)))
puts "Wrote #{out_path}"
puts "Index: #{idx}, Name: #{anim.name}, Frames: #{anim.length}, Graphic: #{anim.graphic}"
