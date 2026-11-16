-- Snapcast: recommended macros by class and role.
-- Every entry is built from blocks, so it opens in the editor and can be changed.
-- role: "tank", "healer", "dps" or "any" (comma-separated for several).

local _, ns = ...
ns = ns or SnapcastNS

local function C(name, unit) return { kind = "cast", what = "spell", name = name, unit = unit or "default" } end
local function I(name, unit) return { kind = "cast", what = "item", name = name, unit = unit or "default" } end
local function K(key, unit) return { key = key, unit = unit } end
local function B(conds, body) return { conds = conds, body = body } end
local function If(branches, elseBody) return { kind = "if", branches = branches, elseBody = elseBody } end
local function Stop() return { kind = "stop" } end
local function Attack() return { kind = "attack" } end
local function Chat(ch, text) return { kind = "chat", channel = ch, text = text } end
local function Raw(text) return { kind = "raw", text = text } end
local function Seq(reset, ...)
    local s = {}
    for i, n in ipairs({ ... }) do s[i] = { name = n } end
    return { kind = "seq", reset = reset, spells = s }
end

local function MO() return { K("help", "mouseover"), K("nodead", "mouseover") } end

-- Common patterns ------------------------------------------------------
-- heal the living friend under the mouse, else the target
local function MouseoverHeal(spell)
    return { If({ B(MO(), { C(spell) }) }, { C(spell) }) }
end
-- ...and hold Alt to cast it on yourself
local function MouseoverHealAlt(spell)
    return { If({ B(MO(), { C(spell) }), B({ K("mod:alt") }, { C(spell, "player") }) }, { C(spell) }) }
end
-- hold Shift to use it on your focus
local function FocusShift(spell, stopFirst)
    local t = {}
    if stopFirst then t[1] = Stop() end
    t[#t + 1] = If({ B({ K("mod:shift"), K("exists", "focus") }, { C(spell, "focus") }) }, { C(spell) })
    return t
end
-- one button, two spells
local function ShiftSwap(shiftSpell, normal)
    return { If({ B({ K("mod:shift") }, { C(shiftSpell) }) }, { C(normal) }) }
end
local function WithAttack(spell) return { Attack(), C(spell) } end

local function E(role, name, desc, make) return { role = role, name = name, desc = desc, make = make } end

ns.CLASS_NAMES = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
    SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}
ns.CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

ns.LIBRARY = {
    WARRIOR = {
        E("any", "Charge / Intercept", "Charge in Battle Stance, Intercept in Berserker Stance: one gap-closer button.",
            function() return { If({ B({ K("stance:1") }, { C("Charge") }), B({ K("stance:3") }, { C("Intercept") }) }) } end),
        E("tank", "Taunt + call it out", "Taunts your target and tells your party, so healers know the threat moved.",
            function() return { C("Taunt"), Chat("p", "Taunted %t!") } end),
        E("tank", "Shield Block + Revenge", "Shield Block is off the global cooldown, so one press fires both.",
            function() return { C("Shield Block"), C("Revenge") } end),
        E("tank", "Sunder + Heroic Strike", "Queues Heroic Strike on your next swing (no global cooldown) and Sunders in the same press.",
            function() return { C("Heroic Strike"), C("Sunder Armor") } end),
        E("tank,dps", "Interrupt by stance", "Pummel in Berserker Stance, Shield Bash otherwise.",
            function() return { If({ B({ K("stance:3") }, { C("Pummel") }) }, { C("Shield Bash") }) } end),
        E("tank", "Thunder Clap (Shift: Demo Shout)", "Thunder Clap normally, Demoralizing Shout while Shift is held.",
            function() return ShiftSwap("Demoralizing Shout", "Thunder Clap") end),
        E("dps", "Mortal Strike + attack", "Turns on auto-attack and uses Mortal Strike (Arms).",
            function() return WithAttack("Mortal Strike") end),
        E("dps", "Bloodthirst + attack", "Turns on auto-attack and uses Bloodthirst (Fury).",
            function() return WithAttack("Bloodthirst") end),
        E("dps", "Overpower + attack", "Turns on auto-attack and Overpowers after a dodge.",
            function() return WithAttack("Overpower") end),
        E("dps", "Hamstring + attack", "Turns on auto-attack and slows your target.",
            function() return WithAttack("Hamstring") end),
    },
    PALADIN = {
        E("healer", "Mouseover Holy Light", "Heals the friend under your mouse, otherwise your target. Hold Alt to heal yourself.",
            function() return MouseoverHealAlt("Holy Light") end),
        E("healer", "Mouseover Flash of Light", "Fast heal on the friend under your mouse, otherwise your target. Alt heals you.",
            function() return MouseoverHealAlt("Flash of Light") end),
        E("healer", "Mouseover Cleanse", "Cleanses the friend under your mouse, otherwise your target.",
            function() return MouseoverHeal("Cleanse") end),
        E("healer", "Mouseover Blessing of Protection", "Bubbles the friend under your mouse, otherwise your target.",
            function() return MouseoverHeal("Blessing of Protection") end),
        E("any", "Mouseover Lay on Hands", "Emergency heal on the friend under your mouse, otherwise your target.",
            function() return MouseoverHeal("Lay on Hands") end),
        E("dps,tank", "Judgement + attack", "Turns on auto-attack and Judges.",
            function() return WithAttack("Judgement") end),
        E("dps", "Seal (Shift: Crusader)", "Seal of Righteousness normally, Seal of the Crusader while Shift is held.",
            function() return ShiftSwap("Seal of the Crusader", "Seal of Righteousness") end),
        E("any", "Hammer of Justice (Shift: focus)", "Stuns your target, or your focus while Shift is held.",
            function() return FocusShift("Hammer of Justice") end),
        E("tank", "Consecration + attack", "Turns on auto-attack and drops Consecration.",
            function() return WithAttack("Consecration") end),
        E("any", "Bubble hearth", "Divine Shield, then Hearthstone out while you're immune.",
            function() return { C("Divine Shield"), I("Hearthstone") } end),
    },
    HUNTER = {
        E("dps", "Mark + send pet", "Hunter's Mark on your target and sends your pet in.",
            function() return { C("Hunter's Mark"), Raw("/petattack") } end),
        E("dps", "Arcane Shot (Shift: Multi-Shot)", "Arcane Shot normally, Multi-Shot while Shift is held.",
            function() return ShiftSwap("Multi-Shot", "Arcane Shot") end),
        E("dps", "Opening sequence", "Each press: Hunter's Mark, Serpent Sting, Arcane Shot. Starts over on a new target.",
            function() return { Seq("target", "Hunter's Mark", "Serpent Sting", "Arcane Shot") } end),
        E("any", "Pet care", "Revives a dead pet, calls it if you have none, otherwise heals it.",
            function() return { If({ B({ K("dead", "pet") }, { C("Revive Pet") }), B({ K("nopet") }, { C("Call Pet") }) }, { C("Mend Pet") }) } end),
        E("any", "Feign Death", "Stops your cast first so Feign Death goes off instantly.",
            function() return { Stop(), C("Feign Death") } end),
        E("dps", "Melee: Raptor Strike + Wing Clip", "Turns on auto-attack, queues Raptor Strike and Wing Clips (Survival melee).",
            function() return { Attack(), C("Raptor Strike"), C("Wing Clip") } end),
        E("any", "Aspect (Shift: Monkey)", "Aspect of the Hawk normally, Aspect of the Monkey while Shift is held.",
            function() return ShiftSwap("Aspect of the Monkey", "Aspect of the Hawk") end),
        E("any", "Scatter Shot (Shift: focus)", "Scatters your target, or your focus while Shift is held.",
            function() return FocusShift("Scatter Shot") end),
        E("any", "Freezing Trap + warn", "Drops a Freezing Trap and asks your party not to break it.",
            function() return { C("Freezing Trap"), Chat("p", "Trap down - don't break it!") } end),
        E("any", "Tranquilizing Shot + call it", "Removes an enrage and tells your party.",
            function() return { C("Tranquilizing Shot"), Chat("p", "Tranq'd %t!") } end),
    },
    ROGUE = {
        E("dps", "Cheap Shot / Sinister Strike", "From stealth: Cheap Shot. Otherwise: auto-attack and Sinister Strike.",
            function() return { If({ B({ K("stealth") }, { C("Cheap Shot") }) }, { Attack(), C("Sinister Strike") }) } end),
        E("dps", "Ambush / Backstab", "From stealth: Ambush. Otherwise: auto-attack and Backstab.",
            function() return { If({ B({ K("stealth") }, { C("Ambush") }) }, { Attack(), C("Backstab") }) } end),
        E("any", "Safe Stealth", "Only enters Stealth, never knocks you out of it by accident.",
            function() return { If({ B({ K("nostealth") }, { C("Stealth") }) }) } end),
        E("any", "Kick (Shift: focus)", "Interrupts your target, or your focus while Shift is held.",
            function() return FocusShift("Kick") end),
        E("dps", "Eviscerate (Shift: Slice and Dice)", "Finisher button: Eviscerate, or Slice and Dice while Shift is held.",
            function() return ShiftSwap("Slice and Dice", "Eviscerate") end),
        E("any", "Sap (Shift: focus)", "Saps your target, or your focus while Shift is held.",
            function() return FocusShift("Sap") end),
        E("dps", "Pick Pocket + Ambush", "Picks their pocket (no global cooldown), then Ambushes in the same press.",
            function() return { C("Pick Pocket"), C("Ambush") } end),
        E("dps", "Cold Blood + Eviscerate", "Pops Cold Blood (off the global cooldown) and Eviscerates for a guaranteed crit.",
            function() return { C("Cold Blood"), C("Eviscerate") } end),
        E("any", "Blind (Shift: focus)", "Blinds your target, or your focus while Shift is held.",
            function() return FocusShift("Blind") end),
        E("any", "Gouge (Shift: Kidney Shot)", "Gouge normally, Kidney Shot while Shift is held.",
            function() return ShiftSwap("Kidney Shot", "Gouge") end),
    },
    PRIEST = {
        E("healer", "Mouseover Flash Heal", "Heals the friend under your mouse, otherwise your target. Hold Alt to heal yourself.",
            function() return MouseoverHealAlt("Flash Heal") end),
        E("healer", "Mouseover Renew", "Renews the friend under your mouse, otherwise your target. Alt for yourself.",
            function() return MouseoverHealAlt("Renew") end),
        E("healer", "Mouseover Power Word: Shield", "Shields the friend under your mouse, otherwise your target. Alt for yourself.",
            function() return MouseoverHealAlt("Power Word: Shield") end),
        E("healer", "Mouseover Greater Heal", "Big heal on the friend under your mouse, otherwise your target. Alt for yourself.",
            function() return MouseoverHealAlt("Greater Heal") end),
        E("healer", "Mouseover Dispel Magic", "Dispels the friend under your mouse, otherwise your target (friend or enemy).",
            function() return MouseoverHeal("Dispel Magic") end),
        E("healer", "Mouseover Cure Disease", "Cures the friend under your mouse, otherwise your target.",
            function() return MouseoverHeal("Cure Disease") end),
        E("dps", "Shadow sequence", "Each press: Shadow Word: Pain, Mind Blast, Mind Flay. Starts over on a new target.",
            function() return { Seq("target", "Shadow Word: Pain", "Mind Blast", "Mind Flay") } end),
        E("any", "Psychic Scream", "Stops your cast first so the fear goes off instantly.",
            function() return { Stop(), C("Psychic Scream") } end),
        E("any", "Mouseover Fortitude", "Buffs the friend under your mouse, otherwise your target.",
            function() return MouseoverHeal("Power Word: Fortitude") end),
        E("dps", "Wand", "Starts or stops shooting your wand.",
            function() return { C("Shoot") } end),
    },
    SHAMAN = {
        E("healer", "Mouseover Healing Wave", "Heals the friend under your mouse, otherwise your target. Hold Alt to heal yourself.",
            function() return MouseoverHealAlt("Healing Wave") end),
        E("healer", "Mouseover Lesser Healing Wave", "Fast heal on the friend under your mouse, otherwise your target. Alt heals you.",
            function() return MouseoverHealAlt("Lesser Healing Wave") end),
        E("healer", "Mouseover Chain Heal", "Chain Heal starting on the friend under your mouse, otherwise your target.",
            function() return MouseoverHeal("Chain Heal") end),
        E("any", "Earth Shock interrupt (Shift: focus)", "Stops your cast, then interrupts your target, or your focus with Shift.",
            function() return FocusShift("Earth Shock", true) end),
        E("any", "Totem drop", "Each press drops the next totem: Strength of Earth, Searing, Mana Spring, Windfury. Starts over after combat.",
            function() return { Seq("combat", "Strength of Earth Totem", "Searing Totem", "Mana Spring Totem", "Windfury Totem") } end),
        E("dps", "Stormstrike + attack", "Turns on auto-attack and Stormstrikes (Enhancement).",
            function() return WithAttack("Stormstrike") end),
        E("dps", "Lightning Bolt (Shift: Chain Lightning)", "Lightning Bolt normally, Chain Lightning while Shift is held.",
            function() return ShiftSwap("Chain Lightning", "Lightning Bolt") end),
        E("dps,tank", "Flame Shock (Shift: Frost Shock)", "Flame Shock normally, Frost Shock while Shift is held.",
            function() return ShiftSwap("Frost Shock", "Flame Shock") end),
        E("healer", "Mouseover Cure Poison (Shift: Disease)", "Cures poison on the friend under your mouse; hold Shift to cure disease instead.",
            function() return { If({ B({ K("mod:shift"), K("help", "mouseover") }, { C("Cure Disease") }),
                                     B({ K("help", "mouseover") }, { C("Cure Poison") }),
                                     B({ K("mod:shift") }, { C("Cure Disease") }) }, { C("Cure Poison") }) } end),
        E("any", "Mouseover Purge", "Purges the enemy under your mouse, otherwise your target.",
            function() return { If({ B({ K("harm", "mouseover") }, { C("Purge") }) }, { C("Purge") }) } end),
    },
    MAGE = {
        E("any", "Polymorph (Shift: focus)", "Sheeps your target, or your focus while Shift is held.",
            function() return FocusShift("Polymorph") end),
        E("any", "Counterspell (Shift: focus)", "Stops your cast, then counters your target, or your focus with Shift.",
            function() return FocusShift("Counterspell", true) end),
        E("dps", "Blizzard at cursor (Shift: Flamestrike)", "Drops Blizzard where your mouse is, or Flamestrike with Shift. No extra click.",
            function() return { If({ B({ K("mod:shift") }, { C("Flamestrike", "cursor") }) }, { C("Blizzard", "cursor") }) } end),
        E("any", "Frost Nova (Shift: Blink)", "Stops your cast, then Frost Nova, or Blink with Shift.",
            function() local t = ShiftSwap("Blink", "Frost Nova"); table.insert(t, 1, Stop()); return t end),
        E("any", "Conjure Water (Shift: Food)", "Conjures water, or food while Shift is held.",
            function() return ShiftSwap("Conjure Food", "Conjure Water") end),
        E("any", "Mouseover Arcane Intellect", "Buffs the friend under your mouse, otherwise your target.",
            function() return MouseoverHeal("Arcane Intellect") end),
        E("any", "Mouseover Remove Lesser Curse", "Decurses the friend under your mouse, otherwise your target.",
            function() return MouseoverHeal("Remove Lesser Curse") end),
        E("dps", "Frostbolt (Shift: Fire Blast)", "Frostbolt normally, Fire Blast while Shift is held.",
            function() return ShiftSwap("Fire Blast", "Frostbolt") end),
        E("dps", "Fireball (Shift: Pyroblast)", "Fireball normally, Pyroblast while Shift is held.",
            function() return ShiftSwap("Pyroblast", "Fireball") end),
        E("dps", "Arcane Explosion (Shift: Cone of Cold)", "AoE button: Arcane Explosion, or Cone of Cold with Shift.",
            function() return ShiftSwap("Cone of Cold", "Arcane Explosion") end),
    },
    WARLOCK = {
        E("dps", "DoT sequence", "Each press: Corruption, Curse of Agony, Immolate. Starts over on a new target.",
            function() return { Seq("target", "Corruption", "Curse of Agony", "Immolate") } end),
        E("any", "Fear (Shift: focus)", "Fears your target, or your focus while Shift is held.",
            function() return FocusShift("Fear") end),
        E("dps", "Send pet + Shadow Bolt", "Sends your pet in and casts Shadow Bolt.",
            function() return { Raw("/petattack"), C("Shadow Bolt") } end),
        E("any", "Death Coil", "Stops your cast first so Death Coil goes off instantly.",
            function() return { Stop(), C("Death Coil") } end),
        E("any", "Banish (Shift: focus)", "Banishes your target, or your focus while Shift is held.",
            function() return FocusShift("Banish") end),
        E("dps", "Curse of Agony (Shift: Recklessness)", "Curse of Agony normally, Curse of Recklessness while Shift is held.",
            function() return ShiftSwap("Curse of Recklessness", "Curse of Agony") end),
        E("any", "Summon Imp (Shift: Voidwalker)", "Summons your Imp, or your Voidwalker while Shift is held.",
            function() return ShiftSwap("Summon Voidwalker", "Summon Imp") end),
        E("dps", "Drain Life (Shift: Drain Soul)", "Drain Life normally, Drain Soul (for shards) while Shift is held.",
            function() return ShiftSwap("Drain Soul", "Drain Life") end),
        E("dps", "Searing Pain (Shift: Shadowburn)", "Searing Pain normally, Shadowburn while Shift is held.",
            function() return ShiftSwap("Shadowburn", "Searing Pain") end),
        E("any", "Pet: come back", "Calls your pet back to you.",
            function() return { Raw("/petfollow") } end),
    },
    DRUID = {
        E("healer", "Mouseover Rejuvenation", "Rejuvenates the friend under your mouse, otherwise your target. Alt for yourself.",
            function() return MouseoverHealAlt("Rejuvenation") end),
        E("healer", "Mouseover Healing Touch (Shift: Regrowth)", "Heals the friend under your mouse, otherwise your target. Shift casts Regrowth.",
            function() return { If({ B({ K("mod:shift"), K("help", "mouseover"), K("nodead", "mouseover") }, { C("Regrowth") }),
                                     B(MO(), { C("Healing Touch") }),
                                     B({ K("mod:shift") }, { C("Regrowth") }) }, { C("Healing Touch") }) } end),
        E("tank,dps", "One attack button for every form", "Bear: Maul. Cat: Claw. Caster: Wrath. Auto-attack in forms.",
            function() return { If({ B({ K("stance:1") }, { Attack(), C("Maul") }), B({ K("stance:3") }, { Attack(), C("Claw") }) }, { C("Wrath") }) } end),
        E("dps", "Ravage / Shred", "From Prowl: Ravage. Otherwise: auto-attack and Shred.",
            function() return { If({ B({ K("stealth") }, { C("Ravage") }) }, { Attack(), C("Shred") }) } end),
        E("healer", "Mouseover Innervate", "Innervates the friend under your mouse, otherwise your target. Alt for yourself.",
            function() return MouseoverHealAlt("Innervate") end),
        E("healer", "Mouseover Remove Curse (Shift: Poison)", "Removes a curse from the friend under your mouse; Shift for Abolish Poison.",
            function() return { If({ B({ K("mod:shift"), K("help", "mouseover") }, { C("Abolish Poison") }),
                                     B({ K("help", "mouseover") }, { C("Remove Curse") }),
                                     B({ K("mod:shift") }, { C("Abolish Poison") }) }, { C("Remove Curse") }) } end),
        E("any", "Entangling Roots (Shift: focus)", "Roots your target, or your focus while Shift is held.",
            function() return FocusShift("Entangling Roots") end),
        E("dps", "Starfire (Shift: Moonfire)", "Starfire normally, Moonfire while Shift is held.",
            function() return ShiftSwap("Moonfire", "Starfire") end),
        E("any", "Faerie Fire in any form", "Faerie Fire (Feral) in Bear or Cat form, normal Faerie Fire otherwise.",
            function() return { If({ B({ K("stance:1/3") }, { C("Faerie Fire (Feral)") }) }, { C("Faerie Fire") }) } end),
        E("tank", "Growl + call it out", "Growls and tells your party, so healers know the threat moved.",
            function() return { C("Growl"), Chat("p", "Growled %t!") } end),
    },
}
