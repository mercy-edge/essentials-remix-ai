#===============================================================================
# Single global level/Exp. table for all species (ignores PBS GrowthRate).
# Cumulative thresholds follow a fixed per-level schedule; cap is Settings::MAXIMUM_LEVEL.
#===============================================================================
GameData::GrowthRate.register({
  :id          => :UnifiedLevelTable,
  :name        => _INTL("Standard"),
  :exp_values  => [
    -1,
    0,        400,      1_300,    2_700,    4_800,    7_600,    11_200,   15_700,   21_100,   27_600,
    35_200,   44_000,   54_100,   65_500,   78_400,   92_800,   108_800,  126_500,  145_900,  167_200,
    190_400,  215_600,  242_900,  272_300,  304_000,  338_000,  374_400,  413_300,  454_700,  499_000,
    546_400,  597_200,  651_700,  710_300,  773_100,  840_200,  911_800,  987_900,  1_068_700, 1_154_400,
    1_245_100, 1_340_900, 1_441_900, 1_548_200, 1_660_000, 1_777_500, 1_900_700, 2_029_800, 2_164_900, 2_306_100,
    2_453_600, 2_607_500, 2_767_900, 2_934_500, 3_107_500, 3_287_600, 3_474_700, 3_668_600, 3_869_600, 4_084_700
  ],
  # Unused while MAXIMUM_LEVEL matches the table length; placeholder for extensions.
  :exp_formula => proc { |level| 4_084_700 }
})

class Pokemon
  # Do not memoize GameData::GrowthRate on the Pokémon — it carries :exp_formula
  # Procs; Marshal.dump(save) follows ivars and would raise TypeError on save.
  def growth_rate
    GameData::GrowthRate.get(:UnifiedLevelTable)
  end
end
