#!/usr/bin/env ruby
# Validates plugin meta.txt files against Essentials PluginManager rules.
require "fileutils"

ROOT = File.expand_path("..", __dir__)
errors = []

Dir.glob(File.join(ROOT, "Plugins", "*", "meta.txt")).sort.each do |meta_path|
  plugin_dir = File.dirname(meta_path)
  plugin_name = File.basename(plugin_dir)
  props = {}
  File.readlines(meta_path, chomp: true).each do |line|
    next if line.strip.empty? || line.strip.start_with?("#")
    m = line.match(/^\s*(\w+)\s*=\s*(.*)$/)
    unless m
      errors << "#{plugin_name}: bad line #{line.inspect}"
      next
    end
    key = m[1].upcase
    val = m[2].strip
    props[key] = val
  end

  errors << "#{plugin_name}: missing Name" if props["NAME"].to_s.empty?
  errors << "#{plugin_name}: missing Version" if props["VERSION"].to_s.empty?
  errors << "#{plugin_name}: empty Link (remove line or set URL)" if props.key?("LINK") && props["LINK"].to_s.empty?

  rb_files = Dir.glob(File.join(plugin_dir, "*.rb"))
  errors << "#{plugin_name}: no .rb scripts" if rb_files.empty?
  rb_files.each do |rb|
    system("ruby", "-c", rb, out: File::NULL, err: File::NULL)
    errors << "#{plugin_name}: syntax error in #{File.basename(rb)}" unless $?.success?
  end
end

rx = File.join(ROOT, "Data", "PkmnAnimations.rxdata")
errors << "PkmnAnimations.rxdata missing" unless File.exist?(rx)

if errors.empty?
  puts "Plugin validation OK (#{Dir.glob(File.join(ROOT, 'Plugins', '*', 'meta.txt')).length} plugins)"
else
  puts "VALIDATION FAILED:"
  errors.each { |e| puts "  - #{e}" }
  exit 1
end
