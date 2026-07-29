#!/usr/bin/env ruby
ROOT = File.expand_path("..", __dir__)
%w[
  Animations/Move_SILVERWIND/Move_SILVERWIND.anm
  silverwind-anim.anm
].each do |rel|
  path = File.join(ROOT, rel)
  next unless File.exist?(path)
  text = File.read(path).gsub(/\s+/, "")
  File.write(path, text)
  puts "Fixed #{rel} (#{text.length} chars, 1 line)"
end
