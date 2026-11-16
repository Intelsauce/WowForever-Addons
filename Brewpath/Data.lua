-- Brewpath: Forever alchemy route, ranks, trainers and item IDs.
-- Route and craft counts from Wowhead's WoW Forever Alchemy Leveling Guide 1-300
-- planner (wowhead.com/forever/profession-leveling-guides/alchemy, updated Nov 3 2026).
-- Brewpath also reads your real recipes and their live colours from the game,
-- so if Forever changes a recipe, the "Craft now" list still tells the truth.

local _, ns = ...
ns = ns or {}
BrewpathNS = ns

ns.ALCHEMY_SKILL_LINE = 171

-- Herbs, vials and other reagents
ns.ITEMS = {
    peacebloom = 2447, silverleaf = 765, earthroot = 2449, mageroyal = 785, briarthorn = 2450,
    swiftthistle = 2452, bruiseweed = 2453, stranglekelp = 3820, wildsteelbloom = 3355,
    kingsblood = 3356, liferoot = 3357, fadeleaf = 3818, goldthorn = 3821, khadgars = 3358,
    firefin = 6359, fireoil = 6371, arthastears = 8836, sungrass = 8838, blindweed = 8839,
    ghostmushroom = 8845, gromsblood = 8846, dreamfoil = 13463, goldensansam = 13464,
    silversage = 13465, plaguebloom = 13466, stonescale = 13423,
    purplelotus = 8831, firebloom = 4625, ironbar = 3575, blackvitriol = 9262,
    murloceye = 730, worgheart = 3164,
    emptyvial = 3371, leadedvial = 3372, crystalvial = 8925, imbuedvial = 18256,
}
local I = ns.ITEMS

-- Vials are sold by vendors. These are starting guesses; Brewpath learns the
-- real price the first time you open a vendor that sells them.
ns.VENDOR_GUESS = {
    [I.emptyvial] = 4, [I.leadedvial] = 40, [I.crystalvial] = 400, [I.imbuedvial] = 3200,
}

-- Ranks: you can train the next one from `trainAt` skill (and character level);
-- you're stuck at `cap` until you do.
ns.RANKS = {
    { name = "Apprentice", cap = 75,  trainAt = 0,   level = 1,
      where = { Horde = "any Alchemy trainer", Alliance = "any Alchemy trainer" } },
    { name = "Journeyman", cap = 150, trainAt = 50,  level = 10,
      where = { Horde = "Yelmak (Orgrimmar), Doctor Marsh (Undercity), Bena Winterhoof (Thunder Bluff)",
                Alliance = "Lilyssia Nightbreeze (Stormwind), Tally Berryfizz (Ironforge), Sylvanna Forestmoon (Darnassus)" } },
    { name = "Expert",     cap = 225, trainAt = 125, level = 20,
      where = { Horde = "Doctor Herbert Halsey (Undercity)", Alliance = "Ainethil (Darnassus)" } },
    { name = "Artisan",    cap = 300, trainAt = 200, level = 35,
      where = { Horde = "Rogvar (Stonard, Swamp of Sorrows)", Alliance = "Kylanna Windwhisper (Feathermoon, Feralas)" } },
}

-- The route. `per` = reagents per craft, `crafts` = Wowhead's estimate,
-- `alt` = an alternative if prices are bad, `source` = where the recipe comes from.
ns.ROUTE = {
    { from = 1, to = 12, recipe = "Elixir of Minor Force", crafts = 11,
      per = { [I.silverleaf] = 1, [I.emptyvial] = 1 }, source = "Known when you learn Alchemy" },
    { from = 12, to = 55, recipe = "Elixir of Minor Defense", crafts = 43,
      per = { [I.silverleaf] = 1, [I.peacebloom] = 1, [I.emptyvial] = 1 }, source = "Known when you learn Alchemy" },
    { from = 55, to = 65, recipe = "Minor Mana Potion", crafts = 10,
      per = { [I.mageroyal] = 1, [I.peacebloom] = 1, [I.emptyvial] = 1 }, source = "Trainer" },
    { from = 65, to = 90, recipe = "Elixir of Minor Fortitude", crafts = 26,
      per = { [I.earthroot] = 2, [I.peacebloom] = 1, [I.emptyvial] = 1 }, source = "Trainer" },
    { from = 90, to = 120, recipe = "Elixir of Wisdom", crafts = 30,
      per = { [I.briarthorn] = 2, [I.mageroyal] = 1, [I.emptyvial] = 1 }, source = "Trainer",
      note = "A Wowhead reader reports this may take a Leaded Vial instead of an Empty Vial: check the recipe in game." },
    { from = 120, to = 160, recipe = "Lesser Mana Potion", crafts = 43,
      per = { [I.mageroyal] = 1, [I.stranglekelp] = 1, [I.emptyvial] = 1 }, source = "Trainer" },
    { from = 160, to = 195, recipe = "Mana Potion", crafts = 38,
      per = { [I.stranglekelp] = 1, [I.kingsblood] = 1, [I.leadedvial] = 1 }, source = "Trainer" },
    { from = 195, to = 205, recipe = "Elixir of Agility", crafts = 10,
      per = { [I.stranglekelp] = 1, [I.goldthorn] = 1, [I.leadedvial] = 1 }, source = "Trainer",
      alt = "Elixir of Defense, depending on material and elixir prices" },
    { from = 205, to = 225, recipe = "Greater Mana Potion", crafts = 20,
      per = { [I.khadgars] = 1, [I.goldthorn] = 1, [I.leadedvial] = 1 }, source = "Trainer" },
    { from = 225, to = 226, recipe = "Philosopher's Stone", crafts = 1,
      per = { [I.ironbar] = 4, [I.blackvitriol] = 1, [I.purplelotus] = 4, [I.firebloom] = 4 },
      source = "Recipe from Alchemist Pestlezugg, Gadgetzan, Tanaris (50.8, 27.0), or buy the recipe item on the auction house",
      note = "A guaranteed skill point until 240. Keep the stone: every transmute needs it." },
    { from = 226, to = 240, recipe = "Greater Mana Potion", crafts = 20,
      per = { [I.khadgars] = 1, [I.goldthorn] = 1, [I.leadedvial] = 1 }, source = "Trainer" },
    { from = 240, to = 260, recipe = "Draught of Detect Undead", crafts = 23,
      per = { [I.arthastears] = 1, [I.crystalvial] = 1 }, source = "Trainer" },
    { from = 260, to = 270, recipe = "Superior Mana Potion", crafts = 10,
      per = { [I.sungrass] = 2, [I.blindweed] = 2, [I.crystalvial] = 1 },
      source = "Recipe from Ulthir (Darnassus, Alliance) or Algernon (Undercity, Horde)" },
    { from = 270, to = 300, recipe = "Major Discolored Healing Potion", crafts = 31,
      per = { [I.plaguebloom] = 1, [I.murloceye] = 1, [I.crystalvial] = 1 },
      source = "Forever questline: Odd Child in Westfall (Alliance) or Apothecary Renferrel at the Sepulcher, Silverpine (Horde)",
      alt = "If Plaguebloom is expensive, keep making Superior Mana Potion until about 280-285" },
}

-- Where each material comes from. Herb zones follow wow-professions.com's
-- Forever herbalism guide; entries marked (classic) aren't in that guide and use
-- original-game locations, which Forever may have changed.
ns.WHERE = {
    [I.peacebloom]     = { how = "Herb", zones = "Durotar, Mulgore, Tirisfal Glades, Zephras Isle, Elwynn Forest, Dun Morogh, Teldrassil" },
    [I.silverleaf]     = { how = "Herb", zones = "Durotar, Mulgore, Tirisfal Glades, Zephras Isle, Elwynn Forest, Dun Morogh, Teldrassil" },
    [I.earthroot]      = { how = "Herb (skill 15)", zones = "Durotar, Mulgore, Tirisfal Glades, Zephras Isle, Elwynn Forest, Dun Morogh, Teldrassil" },
    [I.mageroyal]      = { how = "Herb", zones = "Silverpine Forest, Loch Modan, Darkshore" },
    [I.briarthorn]     = { how = "Herb", zones = "Silverpine Forest, Loch Modan, Darkshore" },
    [I.swiftthistle]   = { how = "Herb (bonus)", zones = "Bonus when picking Briarthorn and Mageroyal (classic)" },
    [I.bruiseweed]     = { how = "Herb", zones = "Hillsbrad Foothills, Stonetalon Mountains" },
    [I.stranglekelp]   = { how = "Herb (skill 85, underwater)", zones = "Coasts of Silverpine Forest, Loch Modan, Darkshore; also Hillsbrad and Stonetalon" },
    [I.wildsteelbloom] = { how = "Herb", zones = "Hillsbrad Foothills, Stonetalon Mountains" },
    [I.kingsblood]     = { how = "Herb (skill 125)", zones = "Hillsbrad Foothills, Stonetalon Mountains, Stranglethorn Vale, Arathi Highlands" },
    [I.liferoot]       = { how = "Herb (skill 150)", zones = "Hillsbrad Foothills, Stonetalon Mountains, Stranglethorn Vale, Arathi Highlands" },
    [I.fadeleaf]       = { how = "Herb", zones = "Stranglethorn Vale, Arathi Highlands" },
    [I.goldthorn]      = { how = "Herb", zones = "Stranglethorn Vale, Arathi Highlands" },
    [I.khadgars]       = { how = "Herb (skill 185)", zones = "Stranglethorn Vale, Arathi Highlands" },
    [I.purplelotus]    = { how = "Herb", zones = "Ashenvale, Stranglethorn Vale, Tanaris, Feralas, The Hinterlands (classic)" },
    [I.firebloom]      = { how = "Herb", zones = "Searing Gorge, Blasted Lands, Tanaris (classic)" },
    [I.arthastears]    = { how = "Herb", zones = "Western Plaguelands, Eastern Plaguelands, Felwood (classic)" },
    [I.sungrass]       = { how = "Herb", zones = "The Hinterlands, Felwood" },
    [I.blindweed]      = { how = "Herb", zones = "Swamp of Sorrows, Un'Goro Crater (classic)" },
    [I.ghostmushroom]  = { how = "Herb (skill 245)", zones = "The Hinterlands (caves)" },
    [I.gromsblood]     = { how = "Herb", zones = "Felwood" },
    [I.goldensansam]   = { how = "Herb", zones = "The Hinterlands, Felwood" },
    [I.dreamfoil]      = { how = "Herb", zones = "Felwood" },
    [I.silversage]     = { how = "Herb", zones = "Felwood" },
    [I.plaguebloom]    = { how = "Herb", zones = "Felwood" },
    [I.murloceye]      = { how = "Mob drop", zones = "Murlocs, for example along the Westfall coast, in Silverpine Forest, Loch Modan and the Wetlands" },
    [I.worgheart]      = { how = "Mob drop", zones = "Worgs in Silverpine Forest (needed for the Horde healing-potion questline)" },
    [I.ironbar]        = { how = "Smelted / AH", zones = "Smelt Iron Ore (Mining) or buy on the auction house" },
    [I.blackvitriol]   = { how = "Drop / AH", zones = "Usually easiest from the auction house; check Wowhead for drop sources" },
    [I.firefin]        = { how = "Fishing", zones = "Coastal waters such as the Wetlands, Hillsbrad and Stranglethorn coasts (classic)" },
    [I.stonescale]     = { how = "Fishing", zones = "Stonescale Eel pools off the coasts of Stranglethorn, Tanaris and Azshara (classic)" },
    [I.fireoil]        = { how = "Crafted", zones = "Made with Firefin Snapper and an Empty Vial" },
    [I.emptyvial]      = { how = "Vendor", zones = "Alchemy Supplies and Trade Supplies vendors in capital cities and most towns" },
    [I.leadedvial]     = { how = "Vendor", zones = "Alchemy Supplies and Trade Supplies vendors in capital cities and most towns" },
    [I.crystalvial]    = { how = "Vendor", zones = "Alchemy Supplies vendors in capital cities" },
    [I.imbuedvial]     = { how = "Vendor", zones = "Alchemy Supplies vendors (classic); check capital cities" },
}

-- Recipes on the route that you can't simply buy from a trainer
ns.RECIPE_VENDORS = {
    { recipe = "Philosopher's Stone", skill = 225, step = 225,
      vendors = "Alchemist Pestlezugg, Gadgetzan, Tanaris (50.8, 27.0), or the auction house. Needs 4 Iron Bar, 1 Black Vitriol, 4 Purple Lotus, 4 Firebloom." },
    { recipe = "Superior Mana Potion", skill = 260, step = 260,
      vendors = "Ulthir (Darnassus, Alliance) or Algernon (Undercity, Horde)" },
    { recipe = "Major Discolored Healing Potion (Alliance)", skill = 270, step = 270, faction = "Alliance",
      vendors = "Odd Child, in the barn in south Westfall that leads to the Deadmines. Quests: My First Alchemy Set, then My First Real Potion. Bring 5 Empty Vial, 5 Peacebloom, 5 Silverleaf, 3 Murloc Eye." },
    { recipe = "Major Discolored Healing Potion (Horde)", skill = 270, step = 270, faction = "Horde",
      vendors = "Rane Yorick in north Silverpine Forest: Wild Hearts, Return to Quinn, Wild Eyes. That unlocks Apothecary Renferrel at the Sepulcher. Bring 3 Discolored Worg Heart, 3 Murloc Eye." },
}

ns.SOURCE_NOTE = "Route from Wowhead's WoW Forever Alchemy guide (Nov 3 2026). Craft counts are averages from skill 1. Hover a step for details."
