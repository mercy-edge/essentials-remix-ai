#!/usr/bin/env ruby
require "json"
require "zlib"

ROOT = File.expand_path("..", __dir__)

class Color; def initialize(*); end; def self.white; new; end; end
class AnimFrame
  X = 0; Y = 1; PATTERN = 7; FOCUS = 26; ZOOMX = 2; ZOOMY = 11
end
class PBAnimTiming
  attr_accessor :frame, :name; attr_writer :timingType
  def timingType; @timingType || 0; end
end
class PBAnimation < Array
  attr_accessor :name, :graphic, :hue, :position
  attr_reader :array, :timing
  def initialize(*); @array = []; @timing = []; end
  def length; @array.length; end
  def [](i); @array[i]; end
end
class PBAnimations < Array
  attr_reader :array
  def initialize(*); @array = []; end
  def [](i); @array[i]; end
end

def load_anm(path)
  raw = File.read(path).gsub(/\r\n/, "")
  Marshal.restore(Zlib::Inflate.inflate(raw.unpack("m")[0]))
end

def frame_nonempty?(frame)
  return false if !frame
  frame.any? { |cel| cel && cel[AnimFrame::PATTERN] && cel[AnimFrame::PATTERN] >= 0 }
end

def effect_cel_count(frame)
  return 0 if !frame
  frame.count { |cel| cel && cel[AnimFrame::PATTERN] && cel[AnimFrame::PATTERN] >= 0 }
end

rx = Marshal.load(File.binread(File.join(ROOT, "Data/PkmnAnimations.rxdata")))[243]
anm = load_anm(File.join(ROOT, "silverwind-anim.anm"))

puts "Rxdata: #{rx.length} total slots, #{rx.length.times.count { |i| frame_nonempty?(rx[i]) }} with effect cels"
puts "Anm:    #{anm.length} total slots, #{anm.length.times.count { |i| frame_nonempty?(anm[i]) }} with effect cels"
puts

max = [rx.length, anm.length].max
max.times do |i|
  rx_f = rx[i]
  anm_f = anm[i]
  rx_e = effect_cel_count(rx_f)
  anm_e = effect_cel_count(anm_f)
  next if rx_e == anm_e && rx_e == 0
  status = (rx_e == anm_e) ? "same" : "DIFF"
  puts "Frame #{i + 1}: rxdata #{rx_e} effect cels, anm #{anm_e} effect cels [#{status}]"
end

puts
puts "Frames 10-18 in .anm (beyond rxdata length):"
(9...anm.length).each do |i|
  f = anm[i]
  next if !f
  patterns = f.map { |cel| cel ? cel[AnimFrame::PATTERN] : nil }.compact
  puts "  Frame #{i + 1}: #{patterns.length} cels, patterns=#{patterns.inspect}" if patterns.any?
end
puts "  (frames 10-18 are empty placeholders)" if (9...anm.length).none? { |i| effect_cel_count(anm[i]) > 0 }
