#!/usr/bin/env ruby
# Export a battle animation from PkmnAnimations.rxdata to Essentials .anm format.
#
# WARNING: .anm files from this tool are NOT importable in RGSS (Ruby 3 Marshal).
# Use the in-game battle animation editor export/import instead.
#
# Usage:
#   ruby tools/export_animation.rb TACKLE
#   ruby tools/export_animation.rb 100 output.anm
#   ruby tools/export_animation.rb Move:TACKLE tackle.anm

require "fileutils"
require "zlib"

ROOT = File.expand_path("..", __dir__)

class Color
  attr_accessor :red, :green, :blue, :alpha
  def initialize(r = 0, g = 0, b = 0, a = 255)
    @red = r; @green = g; @blue = b; @alpha = a
  end
  def self.white; new(255, 255, 255); end
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

def dump_anm(anim)
  # m0 = base64 with no line breaks (Essentials import accepts either format)
  [Zlib::Deflate.deflate(Marshal.dump(anim))].pack("m0")
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

query = ARGV[0] || "TACKLE"
out_arg = ARGV[1]

data = Marshal.load(File.binread(File.join(ROOT, "Data/PkmnAnimations.rxdata")))
result = find_animation(data, query)
if !result
  puts "Animation not found: #{query}"
  exit 1
end

idx, anim = result
safe_name = anim.name.gsub(/\W/, "_")
out_path = out_arg || File.join(ROOT, "#{safe_name}.anm")
out_path = File.join(ROOT, out_path) if !File.absolute_path?(out_path)

FileUtils.mkdir_p(File.dirname(out_path))
File.write(out_path, dump_anm(anim))

puts "Exported animation ##{idx} (#{anim.name})"
puts "  Frames: #{anim.length}"
puts "  Graphic: #{anim.graphic}"
puts "  Timings: #{anim.timing.length}"
puts "  File: #{out_path}"
puts
puts "NOTE: .anm files exported by external Ruby tools may NOT import in-game"
puts "(RGSS uses Ruby 1.8 Marshal; external tools use Ruby 3)."
puts "Use Debug > Import Silver Wind animation instead, or compile plugins."
