#!/usr/bin/env ruby
require "json"
require "zlib"

ROOT = File.expand_path("..", __dir__)

class Color
  def initialize(r = 0, g = 0, b = 0, a = 255); end
  def self.white; new(255, 255, 255); end
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

class PBAnimation < Array
  attr_accessor :id, :name, :graphic, :hue, :position
  attr_writer :speed
  attr_reader :array, :timing
  def speed; @speed || 20; end
  def initialize(*); @array = []; @timing = []; end
  def length; @array.length; end
  def each; @array.each { |i| yield i }; end
  def [](i); @array[i]; end
end

class PBAnimations < Array
  attr_reader :array
  def initialize(*); @array = []; end
  def length; @array.length; end
  def each; @array.each { |i| yield i }; end
  def [](i); @array[i]; end
end

def load_anm(path)
  raw = File.read(path).gsub(/\r\n/, "")
  Marshal.restore(Zlib::Inflate.inflate(raw.unpack("m")[0]))
end

def cel_sig(cel)
  return nil if !cel
  [cel[AnimFrame::X], cel[AnimFrame::Y], cel[AnimFrame::PATTERN], cel[AnimFrame::FOCUS],
   cel[AnimFrame::ZOOMX], cel[AnimFrame::ZOOMY], cel[AnimFrame::ANGLE], cel[AnimFrame::MIRROR],
   cel[AnimFrame::OPACITY], cel[AnimFrame::LOCKED], cel[AnimFrame::PRIORITY]]
end

def anim_summary(anim)
  {
    name: anim.name,
    graphic: anim.graphic,
    hue: anim.hue,
    position: anim.position,
    speed: anim.speed,
    frames: anim.length,
    timings: anim.timing.map { |t| [t.frame, t.timingType, t.name, t.volume, t.pitch] },
    cel_data: anim.length.times.map do |fi|
      frame = anim[fi]
      next [] if !frame
      frame.length.times.map { |ci| cel_sig(frame[ci]) }.compact
    end
  }
end

anm_path = File.join(ROOT, "silverwind-anim.anm")
json_path = File.join(ROOT, "Animations_decoded", "Move_SILVERWIND.json")
rxdata = Marshal.load(File.binread(File.join(ROOT, "Data/PkmnAnimations.rxdata")))
rx_anim = rxdata[243]
anm_anim = load_anm(anm_path)
json = JSON.parse(File.read(json_path))

rx = anim_summary(rx_anim)
anm = anim_summary(anm_anim)

puts "=== Source comparison ==="
puts "Rxdata slot 243 vs silverwind-anim.anm"
puts
%i[name graphic hue position speed frames].each do |k|
  same = rx[k] == anm[k]
  mark = same ? "OK" : "DIFF"
  puts sprintf("%-10s rxdata=%-20s anm=%-20s [%s]", k.to_s + ":", rx[k].inspect, anm[k].inspect, mark)
end

puts
puts "Timings:"
puts "  rxdata: #{rx[:timings].inspect}"
puts "  anm:    #{anm[:timings].inspect}"
puts "  match:  #{rx[:timings] == anm[:timings]}"

puts
frame_diffs = 0
cel_diffs = 0
rx[:cel_data].each_with_index do |rx_frame, fi|
  anm_frame = anm[:cel_data][fi] || []
  if rx_frame != anm_frame
    frame_diffs += 1
    rx_frame.each_with_index do |rx_cel, ci|
      anm_cel = anm_frame[ci]
      if rx_cel != anm_cel
        cel_diffs += 1
        puts "Frame #{fi + 1} cel #{ci}: rxdata=#{rx_cel.inspect}" if cel_diffs <= 10
        puts "                 anm   =#{anm_cel.inspect}" if cel_diffs <= 10
      end
    end
  end
end

if frame_diffs == 0
  puts "All #{rx[:frames]} frames match exactly between rxdata and .anm"
else
  puts "#{frame_diffs} frame(s) differ, #{cel_diffs} cel difference(s) total"
end

puts
puts "=== JSON vs .anm ==="
json_meta = {
  name: json["name"],
  graphic: json["graphic"],
  hue: json["hue"],
  position: json["position"],
  speed: json["speed"],
  frames: json["frame_count"]
}
anm_meta = {
  name: anm[:name],
  graphic: anm[:graphic],
  hue: anm[:hue],
  position: { 1 => "target", 2 => "user", 3 => "user_and_target", 4 => "screen" }[anm[:position]] || anm[:position],
  speed: anm[:speed],
  frames: anm[:frames]
}
json_meta.each do |k, v|
  mark = v == anm_meta[k] ? "OK" : "DIFF"
  puts sprintf("%-10s json=%-20s anm=%-20s [%s]", k.to_s + ":", v.inspect, anm_meta[k].inspect, mark)
end

# Compare first effect cel from JSON frame 1 (index 2) to raw
json_cel = json["frames"][0]["cels"][2]
raw_cel = anm[:cel_data][0][2]
puts
puts "Example cel (frame 1, effect particle):"
puts "  JSON: x=#{json_cel['x']} y=#{json_cel['y']} pattern=#{json_cel['pattern']} focus=#{json_cel['focus']} zoom=#{json_cel['zoom_x']}"
puts "  .anm: #{raw_cel.inspect}" if raw_cel
