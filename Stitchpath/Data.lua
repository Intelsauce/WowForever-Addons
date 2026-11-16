-- Stitchpath: Forever tailoring route, ranks, trainers and item IDs.
-- Route from Wowhead's WoW Forever Tailoring Leveling Guide 1-300
-- (wowhead.com/forever/profession-leveling-guides/tailoring, updated Nov 4 2026).
-- Wowhead doesn't list counts for 205-234; those reagents come from
-- wow-professions.com's Forever guide and the counts are estimates.
-- Stitchpath also reads your real recipes and their live colours from the game.

local _, ns = ...
ns = ns or {}
StitchpathNS = ns

ns.SKILL_LINE = 197 -- Tailoring

ns.ITEMS = {
    linen = 2589, boltlinen = 2996, coarsethread = 2320,
    wool = 2592, boltwool = 2997, finethread = 2321,
    silk = 4306, boltsilk = 4305, bluedye = 6260, spidersilk = 3182, bleach = 2324,
    reddye = 2604, silkenthread = 4291,
    mageweave = 4338, boltmageweave = 4339, orangedye = 6261, heavysilkenthread = 8343,
    eleearth = 7067, elewater = 7070, elefire = 7068, eleair = 7069,
    runecloth = 14047, boltrunecloth = 14048, runethread = 14341, ironweb = 14227, ruggedleather = 8170,
    essenceearth = 7076, livingessence = 12803, essenceair = 7082, brilliantshard = 14343,
}
local I = ns.ITEMS

-- Bolts are made from cloth: how much cloth per bolt
ns.CONVERT = {
    [I.boltlinen] = { [I.linen] = 2 },
    [I.boltwool] = { [I.wool] = 3 },
    [I.boltsilk] = { [I.silk] = 4 },
    [I.boltmageweave] = { [I.mageweave] = 5 },
    [I.boltrunecloth] = { [I.runecloth] = 4 },
}

-- Threads, dyes and bleach come from Tailoring Supplies vendors. These are
-- starting guesses; Stitchpath learns the real price at the vendor.
ns.VENDOR_GUESS = {
    [I.coarsethread] = 10, [I.finethread] = 100, [I.silkenthread] = 300, [I.heavysilkenthread] = 1600,
    [I.runethread] = 5000, [I.bluedye] = 50, [I.reddye] = 50, [I.orangedye] = 2500, [I.bleach] = 25,
}

-- Ranks (from wow-professions.com's Forever tailoring guide)
ns.RANKS = {
    { name = "Apprentice", cap = 75,  trainAt = 0,   level = 1,
      where = { Horde = "Bowen Brisboise (Cold Hearth Manor, Tirisfal), Snang (Orgrimmar), Victor Ward (Undercity), Vhan (Thunder Bluff)",
                Alliance = "Eldrin (Eastvale, Elwynn), Lawrence Schneider (Stormwind), Uthrar Threx (Ironforge), Trianna (Darnassus)" } },
    { name = "Journeyman", cap = 150, trainAt = 50,  level = 10,
      where = { Horde = "Magar (Orgrimmar), Rhiannon Davis (Undercity), Tepa (Thunder Bluff)",
                Alliance = "Sellandus (Stormwind), Jormund Stonebrow (Ironforge), Me'lynn (Darnassus)" } },
    { name = "Expert",     cap = 225, trainAt = 125, level = 20,
      where = { Horde = "Josef Gregorian (Undercity)", Alliance = "Georgio Bolero (Stormwind)" } },
    { name = "Artisan",    cap = 300, trainAt = 200, level = 35,
      where = { Horde = "Daryl Stack (Tarren Mill, Hillsbrad Foothills)", Alliance = "Timothy Worthington (Theramore Isle, Dustwallow Marsh)" } },
}

-- The route. `per` = reagents per craft (from Wowhead's totals), `makesItem` =
-- the bolt a step produces (used by later steps).
ns.ROUTE = {
    { from = 1, to = 43, recipe = "Bolt of Linen Cloth", crafts = 54, makesItem = I.boltlinen,
      per = { [I.linen] = 2 }, source = "Known when you learn Tailoring",
      note = "Keep the bolts: the next steps use them." },
    { from = 43, to = 45, recipe = "Brown Linen Vest", crafts = 2,
      per = { [I.boltlinen] = 1, [I.coarsethread] = 1 }, source = "Trainer" },
    { from = 45, to = 70, recipe = "Linen Belt", crafts = 33,
      per = { [I.boltlinen] = 1, [I.coarsethread] = 1 }, source = "Trainer" },
    { from = 70, to = 75, recipe = "Reinforced Linen Cape", crafts = 7,
      per = { [I.boltlinen] = 2, [I.coarsethread] = 3 }, source = "Trainer",
      note = "Train Journeyman before 75, or you stop getting points." },
    { from = 75, to = 81, recipe = "Bolt of Woolen Cloth", crafts = 12, makesItem = I.boltwool,
      per = { [I.wool] = 3 }, source = "Trainer" },
    { from = 81, to = 100, recipe = "Woolen Cape", crafts = 28,
      per = { [I.boltwool] = 1, [I.finethread] = 1 }, source = "Trainer" },
    { from = 100, to = 110, recipe = "Bolt of Silk Cloth", crafts = 10, makesItem = I.boltsilk,
      per = { [I.silk] = 4 }, source = "Trainer" },
    { from = 110, to = 125, recipe = "Double-stitched Woolen Shoulders", crafts = 19,
      per = { [I.boltwool] = 3, [I.finethread] = 2 }, source = "Trainer" },
    { from = 125, to = 132, recipe = "Azure Silk Hood", crafts = 7,
      per = { [I.boltsilk] = 2, [I.bluedye] = 2, [I.finethread] = 1 }, source = "Trainer" },
    { from = 132, to = 139, recipe = "Lesser Wizard's Robe", crafts = 8,
      per = { [I.boltsilk] = 2, [I.finethread] = 2, [I.spidersilk] = 2 }, source = "Trainer" },
    { from = 139, to = 140, recipe = "Formal White Shirt", crafts = 1,
      per = { [I.boltsilk] = 3, [I.bleach] = 2, [I.finethread] = 1 }, source = "Trainer" },
    { from = 140, to = 149, recipe = "Bolt of Mageweave", crafts = 11, makesItem = I.boltmageweave,
      per = { [I.mageweave] = 5 }, source = "Trainer" },
    { from = 149, to = 160, recipe = "Earthen Vest", crafts = 11,
      per = { [I.boltsilk] = 3, [I.eleearth] = 1, [I.finethread] = 2 }, source = "Trainer" },
    { from = 160, to = 170, recipe = "Robe of Power", crafts = 10,
      per = { [I.boltmageweave] = 2, [I.eleearth] = 2, [I.elewater] = 2, [I.elefire] = 2, [I.eleair] = 2, [I.silkenthread] = 2 },
      source = "Trainer", alt = "Expensive in elementals: check the Craft now tab for a cheaper yellow recipe." },
    { from = 170, to = 180, recipe = "Black Mageweave Vest", crafts = 10,
      per = { [I.boltmageweave] = 2, [I.silkenthread] = 3 }, source = "Trainer" },
    { from = 180, to = 190, recipe = "Orange Mageweave Shirt", crafts = 11,
      per = { [I.boltmageweave] = 1, [I.orangedye] = 1, [I.heavysilkenthread] = 1 }, source = "Trainer" },
    { from = 190, to = 205, recipe = "Black Mageweave Gloves", crafts = 17,
      per = { [I.boltmageweave] = 2, [I.heavysilkenthread] = 2 }, source = "Trainer" },
    { from = 205, to = 214, recipe = "Bolt of Runecloth", crafts = 11, makesItem = I.boltrunecloth,
      per = { [I.runecloth] = 4 }, source = "Trainer",
      note = "Wowhead doesn't list counts here: estimate. Bolts stop giving points at 225, so make the rest whenever." },
    { from = 214, to = 234, recipe = "Runecloth Belt", crafts = 30,
      per = { [I.boltrunecloth] = 3, [I.runethread] = 1 }, source = "Trainer",
      note = "Wowhead doesn't list counts here: estimate." },
    { from = 234, to = 250, recipe = "Runecloth Cloak", crafts = 18,
      per = { [I.boltrunecloth] = 4, [I.ironweb] = 1, [I.runethread] = 1 },
      source = "Pattern from Darnall, Nighthaven, Moonglade (bind on pickup)" },
    { from = 250, to = 260, recipe = "Runecloth Boots", crafts = 12,
      per = { [I.boltrunecloth] = 4, [I.ironweb] = 2, [I.ruggedleather] = 4, [I.runethread] = 1 },
      source = "Pattern from Darnall, Nighthaven, Moonglade (bind on pickup)" },
    { from = 260, to = 280, recipe = "Runecloth Cuffs", crafts = 25,
      per = { [I.boltrunecloth] = 5, [I.ironweb] = 1, [I.runethread] = 1 },
      source = "Pattern from Pexmit (new in Forever; guides don't list his location yet)" },
    { from = 280, to = 285, recipe = "Wisdom of the Timbermaw", crafts = 8,
      per = { [I.boltrunecloth] = 8, [I.essenceearth] = 3, [I.livingessence] = 3, [I.ironweb] = 2 },
      source = "Pattern from Meilosh, Timbermaw Hold, Felwood: needs Honored with Timbermaw Hold" },
    { from = 285, to = 292, recipe = "Venomspew Gloves", crafts = 7,
      per = { [I.boltrunecloth] = 4, [I.brilliantshard] = 1, [I.essenceair] = 3, [I.runethread] = 6 },
      source = "Pattern from Mishta, Cenarion Hold, Silithus: needs Friendly with Cenarion Circle" },
    { from = 292, to = 299, recipe = "Venomspew Cord", crafts = 9,
      per = { [I.boltrunecloth] = 6, [I.brilliantshard] = 1, [I.essenceair] = 3, [I.runethread] = 6 },
      source = "Pattern from Mishta, Cenarion Hold, Silithus: needs Honored with Cenarion Circle" },
    { from = 299, to = 300, recipe = "Venomspew Footpads", crafts = 4,
      per = { [I.boltrunecloth] = 5, [I.brilliantshard] = 1, [I.essenceair] = 3, [I.runethread] = 6 },
      source = "Pattern from Mishta, Cenarion Hold, Silithus: needs Honored with Cenarion Circle" },
}

-- Where materials come from. Cloth level ranges are from Warcraft Tavern's Forever
-- tailoring overview; zone examples marked (classic) use original-game locations.
ns.WHERE = {
    [I.linen]         = { how = "Cloth drop", zones = "Humanoids level 1-19, e.g. Defias in Westfall and Elwynn, Scarlet Crusade in Tirisfal, quilboar in the Barrens (classic)" },
    [I.wool]          = { how = "Cloth drop", zones = "Humanoids level 15-30, e.g. Redridge, Duskwood, Hillsbrad, Stonetalon, Ashenvale (classic)" },
    [I.silk]          = { how = "Cloth drop", zones = "Humanoids level 26-40, e.g. Stranglethorn Vale, Arathi Highlands, Alterac Mountains, Desolace (classic)" },
    [I.mageweave]     = { how = "Cloth drop", zones = "Humanoids level 41-50, e.g. Tanaris, Feralas, The Hinterlands, Badlands, Searing Gorge (classic)" },
    [I.runecloth]     = { how = "Cloth drop", zones = "Humanoids level 51-60, e.g. Winterspring, the Plaguelands, Burning Steppes, Felwood, Silithus (classic)" },
    [I.coarsethread]  = { how = "Vendor", zones = "Tailoring Supplies vendors near trainers; in Brill buy it from Abigail Shiel" },
    [I.finethread]    = { how = "Vendor", zones = "Tailoring Supplies vendors near trainers" },
    [I.silkenthread]  = { how = "Vendor", zones = "Tailoring Supplies vendors near trainers" },
    [I.heavysilkenthread] = { how = "Vendor", zones = "Tailoring Supplies vendors near trainers" },
    [I.runethread]    = { how = "Vendor", zones = "Tailoring Supplies vendors, including Darnall in Nighthaven, Moonglade" },
    [I.bluedye]       = { how = "Vendor", zones = "Tailoring Supplies vendors near trainers" },
    [I.reddye]        = { how = "Vendor", zones = "Tailoring Supplies vendors near trainers" },
    [I.orangedye]     = { how = "Vendor", zones = "Tailoring Supplies vendors near trainers" },
    [I.bleach]        = { how = "Vendor", zones = "Tailoring Supplies vendors near trainers" },
    [I.spidersilk]    = { how = "Mob drop", zones = "Spiders around level 20-30, e.g. Duskwood, the Wetlands, Ashenvale (classic)" },
    [I.ironweb]       = { how = "Mob drop", zones = "Spiders level 50+, e.g. Winterspring, Western Plaguelands, Burning Steppes (classic)" },
    [I.ruggedleather] = { how = "Skinning", zones = "Skinning level 50+ beasts, or the auction house" },
    [I.eleearth]      = { how = "Mob drop / AH", zones = "Earth elementals, e.g. rock elementals in the Badlands (classic), or the auction house" },
    [I.elewater]      = { how = "Mob drop / AH", zones = "Water elementals (classic), or the auction house" },
    [I.elefire]       = { how = "Mob drop / AH", zones = "Fire elementals, e.g. Searing Gorge (classic), or the auction house" },
    [I.eleair]        = { how = "Mob drop / AH", zones = "Air elementals, e.g. Arathi Highlands (classic), or the auction house" },
    [I.essenceearth]  = { how = "Mob drop / AH", zones = "High-level earth elementals, e.g. Silithus (classic), or the auction house" },
    [I.essenceair]    = { how = "Mob drop / AH", zones = "High-level air elementals, e.g. Silithus and Winterspring (classic), or the auction house" },
    [I.livingessence] = { how = "Mob drop / AH", zones = "High-level plant creatures, e.g. Un'Goro Crater and Felwood (classic), or the auction house" },
    [I.brilliantshard] = { how = "Enchanting / AH", zones = "Disenchanting level 51-60 blue items, or the auction house" },
    [I.boltlinen]     = { how = "You make it", zones = "2 Linen Cloth each" },
    [I.boltwool]      = { how = "You make it", zones = "3 Wool Cloth each" },
    [I.boltsilk]      = { how = "You make it", zones = "4 Silk Cloth each" },
    [I.boltmageweave] = { how = "You make it", zones = "5 Mageweave Cloth each" },
    [I.boltrunecloth] = { how = "You make it", zones = "Runecloth (estimated 4 each)" },
}

-- Patterns you can't get from a trainer
ns.RECIPE_VENDORS = {
    { recipe = "Runecloth Cloak (220) and Runecloth Boots (235)", skill = 220, step = 234,
      vendors = "Darnall, Nighthaven, Moonglade. Bind on pickup: buy on the tailor. He also sells Rune Thread." },
    { recipe = "Runecloth Cuffs (250, new in Forever)", skill = 250, step = 260,
      vendors = "Pexmit, per Wowhead. Guides don't list where he is yet." },
    { recipe = "Wisdom of the Timbermaw (255)", skill = 255, step = 280,
      vendors = "Meilosh, in the Timbermaw Hold tunnel in Felwood, under the bridge where the three tunnels meet. Needs Honored with Timbermaw Hold." },
    { recipe = "Venomspew Gloves (285), Cord (290), Footpads (295)", skill = 285, step = 285,
      vendors = "Mishta, Cenarion Hold, Silithus: across from the inn and up the hill by the wagon. Gloves need Friendly, Cord and Footpads need Honored with Cenarion Circle." },
}

ns.SOURCE_NOTE = "Route from Wowhead's WoW Forever Tailoring guide (Nov 4 2026). 205-234 counts are estimates. Hover a step for details."
