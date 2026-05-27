#===============================================================================
# Spell Ranks (global, per-save)
#-------------------------------------------------------------------------------
# Lets player-owned moves scale by purchased "rank". Example:
# - HEROICSTRIKE rank 1 => 40 power
# - HEROICSTRIKE rank 2 => 50 power
#
# NPC/event usage example:
#   pbOfferSpellRankUpgrade(
#     :HEROICSTRIKE, 2,
#     cost: 100,
#     required_class: "Warrior",
#     min_level: 2
#   )
#===============================================================================

if defined?(PokemonGlobalMetadata)
  class PokemonGlobalMetadata
    # Hash<Symbol move_id, Integer rank>
    attr_accessor :spell_ranks
  end
end

module SpellRanks
  # Configure rank power tables here.
  # Keys: move IDs from PBS.
  # Values: { rank_number => base_power_at_that_rank }
  MOVE_RANK_POWERS = {
    :HEROICSTRIKE => {
      1 => 40,
      2 => 50
    }
  }
end

def pbEnsureSpellRanksStore
  $PokemonGlobal = PokemonGlobalMetadata.new if !$PokemonGlobal
  $PokemonGlobal.spell_ranks ||= {}
  $PokemonGlobal.spell_ranks
end

def pbGetSpellRank(move_id)
  move_sym = move_id.to_sym
  ranks = pbEnsureSpellRanksStore
  rank = ranks[move_sym]
  return rank.to_i if rank && rank.to_i > 0
  return 1 if SpellRanks::MOVE_RANK_POWERS[move_sym]
  0
end

def pbSetSpellRank(move_id, rank)
  move_sym = move_id.to_sym
  return false if rank.to_i <= 0
  return false if !SpellRanks::MOVE_RANK_POWERS[move_sym]
  pbEnsureSpellRanksStore[move_sym] = rank.to_i
  true
end

def pbSpellRankedBasePowerForUser(move_id, base_power, user)
  return base_power if !user || !user.pbOwnedByPlayer?
  move_sym = move_id.to_sym
  rank_table = SpellRanks::MOVE_RANK_POWERS[move_sym]
  return base_power if !rank_table
  rank = pbGetSpellRank(move_sym)
  ranked_power = rank_table[rank]
  return base_power if !ranked_power || ranked_power <= 0
  ranked_power
end

def pbPlayerHighestPartyLevel
  return 1 if !$player
  party = $player.party || []
  lv = party.compact.map { |pkmn| pkmn.level.to_i }.max
  (lv && lv > 0) ? lv : 1
end

def pbOfferSpellRankUpgrade(move_id, rank_to_buy, cost: 0, required_class: nil, min_level: nil)
  move_sym = move_id.to_sym
  rank_to_buy = rank_to_buy.to_i
  return false if rank_to_buy <= 1
  rank_table = SpellRanks::MOVE_RANK_POWERS[move_sym]
  if !rank_table || !rank_table[rank_to_buy]
    pbMessage(_INTL("That spell rank isn't available."))
    return false
  end
  if required_class && defined?(pbGetPlayerClassDisplayName)
    current_class = pbGetPlayerClassDisplayName
    if current_class.to_s.downcase != required_class.to_s.downcase
      pbMessage(_INTL("Only {1}s can buy this rank.", required_class))
      return false
    end
  end
  if min_level && pbPlayerHighestPartyLevel < min_level.to_i
    pbMessage(_INTL("You need to be at least level {1}.", min_level.to_i))
    return false
  end
  current_rank = pbGetSpellRank(move_sym)
  if current_rank >= rank_to_buy
    pbMessage(_INTL("You already know that rank."))
    return false
  end
  if rank_to_buy != current_rank + 1
    pbMessage(_INTL("You must learn the next rank in order."))
    return false
  end
  move_name = (GameData::Move.exists?(move_sym)) ? GameData::Move.get(move_sym).name : move_sym.to_s
  new_power = rank_table[rank_to_buy]
  prompt = _INTL("Buy {1} Rank {2} for ${3}?\\n(New power: {4})",
                 move_name, rank_to_buy, cost.to_i.to_s_formatted, new_power)
  return false if !pbConfirmMessage(prompt)
  if cost.to_i > 0 && $player.money < cost.to_i
    pbMessage(_INTL("You don't have enough money."))
    return false
  end
  $player.money -= cost.to_i if cost.to_i > 0
  pbSetSpellRank(move_sym, rank_to_buy)
  pbMessage(_INTL("{1} is now Rank {2}!", move_name, rank_to_buy))
  true
end
