class Table
  def self._load(data); obj = allocate; obj.send(:marshal_load, data); obj; end
  def marshal_load(data); @xsize, @ysize, @zsize, @data = *data.unpack("LLLLL*"); end
  attr_reader :xsize
  def [](x,y=0,z=0); @data[x + y * @xsize + z * @xsize * @ysize]; end
end
module RPG; class Map; attr_accessor :tileset_id; end; end
Dir.glob("d:/Pokemon Essentials v21.1 2023-07-30/Essentials Remix AI/Data/Map*.rxdata").sort.each do |f|
  map = Marshal.load(File.binread(f)) rescue next
  next if !map
  tid = map.tileset_id
  next unless [1,2].include?(tid)
  num = f[/Map(\d+)/,1]
  puts "Map #{num}: tileset_id=#{tid}"
end
