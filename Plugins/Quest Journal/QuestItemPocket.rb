#===============================================================================
# Quest Items bag pocket (pocket 9) — save-safe pocket arrays.
#
# Settings::bag_pocket_names includes "Quest Items" as pocket 9.
# Quest items in PBS/items.txt use Pocket = 9. Mark undiscardable ones with
# Flags = KeyItem (and ShowQuantity = true when stacks matter).
#===============================================================================

class PokemonBag
  # Old saves only have pockets 0..8; ensure new Quest Items pocket exists.
  def ensure_quest_item_pocket!
    needed = PokemonBag.pocket_count
    @pockets ||= []
    (0..needed).each { |i| @pockets[i] ||= [] }
    @last_pocket_selections ||= []
    (0..needed).each { |i| @last_pocket_selections[i] ||= 0 }
    if @last_viewed_pocket.nil? || @last_viewed_pocket < 1 ||
       @last_viewed_pocket > needed
      @last_viewed_pocket = 1
    end
  end

  alias __quest_pocket_quantity quantity
  def quantity(item)
    ensure_quest_item_pocket!
    __quest_pocket_quantity(item)
  end

  alias __quest_pocket_can_add? can_add?
  def can_add?(item, qty = 1)
    ensure_quest_item_pocket!
    __quest_pocket_can_add?(item, qty)
  end

  alias __quest_pocket_add add
  def add(item, qty = 1)
    ensure_quest_item_pocket!
    __quest_pocket_add(item, qty)
  end

  alias __quest_pocket_remove remove
  def remove(item, qty = 1)
    ensure_quest_item_pocket!
    __quest_pocket_remove(item, qty)
  end
end
