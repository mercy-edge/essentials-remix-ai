# Install Gen 9 Pack into Essentials Remix AI and dedupe PBS sections
# that already exist in base PBS files.

require 'fileutils'

ROOT = File.expand_path('..', __dir__)
PACK = File.join(ROOT, '_downloads', 'gen9_pack')
raise "Missing pack at #{PACK}" unless File.directory?(PACK)

def robocopy(src, dest)
  FileUtils.mkdir_p(dest)
  # Use robocopy on Windows for speed/merge
  cmd = %(robocopy "#{src}" "#{dest}" /E /XO /NFL /NDL /NJH /NJS /nc /ns /np)
  system(cmd)
  code = $?.exitstatus
  # robocopy 0-7 = success-ish
  raise "robocopy failed #{src} -> #{dest} (#{code})" if code >= 8
end

def copy_tree(src, dest)
  FileUtils.mkdir_p(File.dirname(dest))
  FileUtils.rm_rf(dest) if File.exist?(dest)
  FileUtils.cp_r(src, dest)
end

puts '== Plugins =='
copy_tree(
  File.join(PACK, 'Plugins', 'Generation 9 Pack Scripts'),
  File.join(ROOT, 'Plugins', 'Generation 9 Pack Scripts')
)

puts '== PBS Gen 9 files =='
%w[
  abilities_Gen_9_Pack.txt
  items_Gen_9_Pack.txt
  moves_Gen_9_Pack.txt
  pokemon_base_Gen_9_Pack.txt
  pokemon_forms_Gen_9_Pack.txt
  pokemon_metrics_Gen_9_Pack.txt
].each do |f|
  src = File.join(PACK, 'PBS', f)
  dest = File.join(ROOT, 'PBS', f)
  FileUtils.cp(src, dest)
  puts "  copied #{f}"
end

# Full metrics file from pack optionally merges Gen6-9 - pack also has pokemon_metrics.txt
# Don't overwrite base pokemon_metrics.txt wholesale; Gen_9_Pack metrics file is enough.

puts '== PBS Gen 9 backup =='
copy_tree(File.join(PACK, 'PBS', 'Gen 9 backup'), File.join(ROOT, 'PBS', 'Gen 9 backup'))

puts '== Graphics =='
robocopy(File.join(PACK, 'Graphics'), File.join(ROOT, 'Graphics'))

puts '== Audio =='
robocopy(File.join(PACK, 'Audio'), File.join(ROOT, 'Audio'))

# Also copy Credits into project docs folder for attribution
FileUtils.cp(File.join(PACK, 'Credits.txt'), File.join(ROOT, 'PBS', 'Gen 9 backup', 'Credits.txt')) rescue nil
FileUtils.cp(File.join(PACK, 'Gen 9 PBS Guide.txt'), File.join(ROOT, 'PBS', 'Gen 9 backup', 'Gen 9 PBS Guide.txt')) rescue nil

def section_ids(path)
  ids = {}
  File.foreach(path) do |line|
    if line =~ /\A\[([^\]]+)\]/
      ids[Regexp.last_match(1)] = true
    end
  end
  ids
end

def strip_duplicate_sections!(pack_path, base_path, label)
  return unless File.file?(pack_path) && File.file?(base_path)

  base_ids = section_ids(base_path)
  out = []
  skipping = false
  removed = []
  current = nil
  File.foreach(pack_path) do |line|
    if line =~ /\A\[([^\]]+)\]/
      current = Regexp.last_match(1)
      if base_ids[current]
        skipping = true
        removed << current
        next
      else
        skipping = false
      end
    elsif line =~ /\A#---/ && !skipping
      # keep separators when not skipping
    end
    next if skipping
    out << line
  end
  File.write(pack_path, out.join)
  puts "  #{label}: removed #{removed.size} duplicate sections already in base"
  removed.first(10).each { |id| puts "    - #{id}" }
  puts "    ... +#{removed.size - 10} more" if removed.size > 10
end

puts '== Dedupe Gen 9 Pack PBS vs base =='
strip_duplicate_sections!(
  File.join(ROOT, 'PBS', 'moves_Gen_9_Pack.txt'),
  File.join(ROOT, 'PBS', 'moves.txt'),
  'moves'
)
strip_duplicate_sections!(
  File.join(ROOT, 'PBS', 'abilities_Gen_9_Pack.txt'),
  File.join(ROOT, 'PBS', 'abilities.txt'),
  'abilities'
)
strip_duplicate_sections!(
  File.join(ROOT, 'PBS', 'items_Gen_9_Pack.txt'),
  File.join(ROOT, 'PBS', 'items.txt'),
  'items'
)

puts 'DONE'
