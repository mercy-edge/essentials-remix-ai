#!/usr/bin/env ruby
# Extend Silver Wind animation frames 10-18 with drifting wind particles (pattern 12).
#
# SAFE: writes .anm only (never Data/PkmnAnimations.rxdata).
# After running: restart game > Debug > Import Silver Wind animation
#
require "json"
require "zlib"
require "fileutils"

ROOT = File.expand_path("..", __dir__)

module Battle
  class Scene
    FOCUSUSER_X = 128
    FOCUSUSER_Y = 224
    FOCUSTARGET_X = 384
    FOCUSTARGET_Y = 96
  end
end

class Color
  def initialize(*); end
  def self.white; new; end
end

class AnimFrame
  X = 0; Y = 1; ZOOMX = 2; ANGLE = 3; MIRROR = 4; BLENDTYPE = 5
  VISIBLE = 6; PATTERN = 7; OPACITY = 8; ZOOMY = 11
  LOCKED = 20; PRIORITY = 25; FOCUS = 26
end

class PBAnimTiming
  attr_accessor :frame, :name, :volume, :pitch, :flashScope, :flashDuration
  attr_writer :timingType
  def timingType; @timingType || 0; end
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

def pbResetCel(frame)
  frame[AnimFrame::ZOOMX] = 100
  frame[AnimFrame::ZOOMY] = 100
  frame[AnimFrame::BLENDTYPE] = 0
  frame[AnimFrame::VISIBLE] = 1
  frame[AnimFrame::ANGLE] = 0
  frame[AnimFrame::MIRROR] = 0
  frame[AnimFrame::OPACITY] = 255
  frame[AnimFrame::PRIORITY] = 1
  (12..19).each { |i| frame[i] = 0 }
  (21..24).each { |i| frame[i] = 0 }
end

def pbCreateCel(x, y, pattern, focus = 1)
  frame = []
  frame[AnimFrame::X] = x
  frame[AnimFrame::Y] = y
  frame[AnimFrame::PATTERN] = pattern
  frame[AnimFrame::FOCUS] = focus
  frame[AnimFrame::LOCKED] = 0
  pbResetCel(frame)
  frame
end

def dump_anm(anim, path)
  data = [Zlib::Deflate.deflate(Marshal.dump(anim))].pack("m0")
  File.write(path, data)
end

def load_anm(path)
  raw = File.read(path).gsub(/\r\n/, "")
  Marshal.restore(Zlib::Inflate.inflate(raw.unpack("m")[0]))
end

WIND_PATTERN = 12
FOCUS_TARGET = 1
MAX_PARTICLES = 16
DRIFT_X = 44

SPAWNS = [
  [168, -10], [96, 30], [136, -42], [104, 6], [152, 94],
  [128, 46], [168, -26], [96, -10], [184, -34], [88, 166]
]

Y_DRIFT = [6, -4, 8, -6, 2, 10, -8, 4, -2]

def wind_particle(x, y)
  cel = pbCreateCel(x, y, WIND_PATTERN, FOCUS_TARGET)
  cel[AnimFrame::ZOOMX] = 20
  cel[AnimFrame::ZOOMY] = 20
  cel
end

def battler_cels(source_frame)
  [source_frame[0].dup, source_frame[1].dup]
end

def collect_wind_cels(frame)
  cels = []
  return cels if !frame
  frame.each do |cel|
    next if !cel || cel[AnimFrame::PATTERN] != WIND_PATTERN
    cels << cel.dup
  end
  cels
end

def wrap_particle(cel, frame_num, particle_idx)
  x = cel[AnimFrame::X]
  y = cel[AnimFrame::Y]
  if x > 720 || y > 250 || y < -60
    cel[AnimFrame::X] = 72 + (particle_idx * 37 + frame_num * 11) % 96
    cel[AnimFrame::Y] = -28 + (particle_idx * 29 + frame_num * 13) % 140
  end
  cel
end

def advance_particles(particles, frame_num)
  particles.each_with_index do |cel, i|
    cel[AnimFrame::X] += DRIFT_X + (i % 3) * 6
    cel[AnimFrame::Y] += Y_DRIFT[(frame_num + i) % Y_DRIFT.length]
    wrap_particle(cel, frame_num, i)
  end
  particles
end

def build_extended_frame(prev_frame, frame_num)
  new_frame = battler_cels(prev_frame)
  particles = advance_particles(collect_wind_cels(prev_frame), frame_num)

  spawn = SPAWNS[frame_num % SPAWNS.length]
  particles.unshift(wind_particle(spawn[0], spawn[1]))

  # Keep density similar to the peak of the original animation.
  particles = particles.last(MAX_PARTICLES)

  particles.each_with_index { |cel, i| new_frame[2 + i] = cel }
  new_frame
end

def ensure_length(anim, total_frames)
  template = anim[0]
  while anim.length < total_frames
    frame = battler_cels(template)
    anim.array << frame
  end
end

def extend_animation(anim, from_frame_idx, to_frame_idx)
  ensure_length(anim, to_frame_idx + 1)
  (from_frame_idx..to_frame_idx).each do |fi|
    prev = anim[fi - 1]
    anim.array[fi] = build_extended_frame(prev, fi + 1)
  end
  anim
end

# Load from exported .anm (18 frames with empty padding).
anm_path = File.join(ROOT, "silverwind-anim.anm")
anim = load_anm(anm_path)

puts "Before: #{anim.length} frames, frame 10 effect cels: #{collect_wind_cels(anim[9]).length}"

extend_animation(anim, 9, 17)

puts "After: #{anim.length} frames"
(9..17).each do |i|
  puts "  Frame #{i + 1}: #{collect_wind_cels(anim[i]).length} wind particles"
end

dump_anm(anim, anm_path)
puts "Updated #{anm_path}"

folder_anm = File.join(ROOT, "Animations/Move_SILVERWIND/Move_SILVERWIND.anm")
FileUtils.mkdir_p(File.dirname(folder_anm)) rescue nil
dump_anm(anim, folder_anm)
puts "Updated #{folder_anm}"
puts "Import #{folder_anm} via F9 > Battle animation editor > slot 243 (do NOT edit rxdata from external Ruby)"

# Refresh decoded JSON.
FOCUS_NAMES = { 1 => "target", 2 => "user", 3 => "user_and_target", 4 => "screen" }
POSITION_NAMES = { 1 => "target", 2 => "user", 3 => "user_and_target", 4 => "screen" }
PRIORITY_NAMES = { 0 => "back", 1 => "front", 2 => "behind_focus", 3 => "above_focus" }
PATTERN_NAMES = { -1 => "user_sprite", -2 => "target_sprite" }

def cel_to_hash(cel)
  pattern = cel[AnimFrame::PATTERN]
  {
    "x" => cel[AnimFrame::X], "y" => cel[AnimFrame::Y],
    "pattern" => PATTERN_NAMES[pattern] || pattern,
    "focus" => FOCUS_NAMES[cel[AnimFrame::FOCUS]] || cel[AnimFrame::FOCUS],
    "zoom_x" => cel[AnimFrame::ZOOMX], "zoom_y" => cel[AnimFrame::ZOOMY],
    "angle" => cel[AnimFrame::ANGLE], "mirror" => cel[AnimFrame::MIRROR] != 0,
    "opacity" => cel[AnimFrame::OPACITY], "blend_type" => cel[AnimFrame::BLENDTYPE],
    "visible" => cel[AnimFrame::VISIBLE] == 1, "locked" => cel[AnimFrame::LOCKED] != 0,
    "priority" => PRIORITY_NAMES[cel[AnimFrame::PRIORITY]] || cel[AnimFrame::PRIORITY]
  }
end

frames = anim.length.times.map do |i|
  frame = anim[i]
  cels = frame.filter_map { |c| cel_to_hash(c) if c }
  { "frame" => i + 1, "cels" => cels }
end

json = {
  "index" => 243,
  "name" => anim.name,
  "graphic" => anim.graphic,
  "hue" => anim.hue,
  "position" => POSITION_NAMES[anim.position] || anim.position,
  "speed" => anim.speed,
  "frame_count" => anim.length,
  "timings" => anim.timing.map { |t| { "frame" => t.frame + 1, "type" => "play_se", "name" => t.name, "volume" => t.volume, "pitch" => t.pitch } },
  "frames" => frames
}

json_path = File.join(ROOT, "Animations_decoded", "Move_SILVERWIND.json")
File.write(json_path, JSON.pretty_generate(json))
puts "Updated #{json_path}"
