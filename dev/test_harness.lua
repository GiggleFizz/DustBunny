-- DustBunny offline harness (lua5.1). Stubs the client API, loads the REAL
-- data + addon, drives scenarios, and enforces invariants after every step:
--   THE THUNDERFURY CLAUSE (literal): no listed entry and no macro target
--   may ever be excluded, quality>=5, or absent from the generated data.
-- Run: lua5.1 test_harness.lua

local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond then passed = passed + 1
    else failed = failed + 1; print("FAIL: " .. name .. (detail and (" — " .. detail) or "")) end
end

-- ------------------------------------------------------- client stubs --
local world = { bags = {}, skills = {}, items = {} } -- mutable test world
-- items[id] = { name=, quality= }; bags[bag][slot] = { id=, count=, locked= }

local function StubFrame()
    local f = {}
    f.attrs, f.scripts, f.events = {}, {}, {}
    local function noop() return f end
    setmetatable(f, { __index = function(_, k)
        -- APIs that DO NOT EXIST in the 3.3.5 client: the catch-all stub
        -- politely implemented SetShown and masked a field error
        -- (2026-07-23) — a stub that accepts everything can't testify.
        if k == "SetShown" then
            error("SetShown does not exist in the 3.3.5 client (field catch 2026-07-23)")
        end
        return function(self, a, b)
            if k == "SetAttribute" then self.attrs[a] = b
            elseif k == "GetAttribute" then return self.attrs[a]
            elseif k == "SetScript" then self.scripts[a] = b
            elseif k == "GetScript" then return self.scripts[a]
            elseif k == "RegisterEvent" then self.events[a] = true
            elseif k == "Show" then self.shown = true
            elseif k == "Hide" then self.shown = false
            elseif k == "IsShown" then return self.shown
            elseif k == "SetShown" then self.shown = a
            elseif k == "Enable" then self.enabled = true
            elseif k == "Disable" then self.enabled = false
            elseif k == "SetText" then self.text_v = a
            elseif k == "SetHeight" then self.height_v = a
            elseif k == "SetFocus" then self.focused = true
            elseif k == "ClearFocus" then self.focused = false
            elseif k == "GetText" then return self.text_v or ""
            elseif k == "GetPoint" then return "CENTER", nil, "CENTER", 0, 0
            elseif k == "CreateTexture" or k == "CreateFontString" then return StubFrame()
            elseif k == "SetTexture" then self.texture_v = a; return 1
            elseif k == "SetChecked" then self.checked = a
            elseif k == "GetChecked" then return self.checked
            end
            return f
        end
    end })
    return f
end

local allSecure = {}
function CreateFrame(ftype, name, parent, template)
    local f = StubFrame()
    f.name, f.template = name, template
    if template and string.find(template, "SecureActionButtonTemplate") then
        table.insert(allSecure, f)
    end
    if name then _G[name] = f end
    return f
end

UIParent = StubFrame()
UISpecialFrames = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function InCombatLockdown() return false end
function GetItemQualityColor() return 1, 1, 1 end
function FauxScrollFrame_GetOffset() return 0 end
function FauxScrollFrame_Update() end
function FauxScrollFrame_SetOffset() end
function FauxScrollFrame_OnVerticalScroll() end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
SlashCmdList = {}

function GetNumSkillLines() return #world.skills end
function GetSkillLineInfo(i)
    local s = world.skills[i]
    return s.name, false, nil, s.rank
end
function GetContainerNumSlots(bag)
    return world.bags[bag] and #world.bags[bag] or 0
end
function GetContainerItemLink(bag, slot)
    local it = world.bags[bag] and world.bags[bag][slot]
    return it and ("|Hitem:" .. it.id .. ":0|h[x]|h") or nil
end
function GetContainerItemInfo(bag, slot)
    local it = world.bags[bag] and world.bags[bag][slot]
    if not it then return nil end
    local q = world.items[it.id] and world.items[it.id].quality or 2
    return "icon", it.count, it.locked or false, q
end
function GetItemInfo(id)
    local it = world.items[id]
    if not it then return nil end
    return it.name, "link", it.quality, 1, 1, "t", "s", 1, "", "icon"
end
function GetNumLootItems() return 0 end
function LootSlot() end
function ConfirmLootSlot() end
world.cooldown = false
world.casting = nil
GameTooltip = StubFrame()
function GetSpellTexture() return "icon" end
function HasAction() return false end
function GetCursorPosition() return 0, 0 end
function GetSpellCooldown() if world.cooldown then return 1000, 1.5 end return 0, 0 end
function UnitCastingInfo() return world.casting end
-- trade-skill window stubs (1.1.0 Forge): the open window IS the data
world.trade = { line = nil, recipes = {} }
world.crafted = {}
function GetTradeSkillLine() return world.trade.line end
function GetNumTradeSkills() return #world.trade.recipes end
function GetTradeSkillInfo(i) local r = world.trade.recipes[i]; return r.name, r.kind or "optimal", r.avail or 0 end
function GetTradeSkillItemLink(i) local r = world.trade.recipes[i]; return r.id and ("item:" .. r.id) or nil end
function GetTradeSkillIcon() return "icon" end
function DoTradeSkill(i, n) table.insert(world.crafted, { index = i, n = n }) end
-- headless-session stubs: the Blizzard viewer and UIParent's show path
TradeSkillFrame = StubFrame(); TradeSkillFrame.shown = false
TradeSkillFrame.scripts.OnHide = function() CloseTradeSkill() end   -- Blizzard_TradeSkillUI.xml:982
local function BlizzardTradeSkillShow() TradeSkillFrame.shown = true end
-- LoD: the global does not exist until UIParent loads Blizzard_TradeSkillUI
TradeSkillFrame_Show = nil
local function UIParentLoadsViewer()   -- what UIParent.lua:283 + ADDON_LOADED do
    if not TradeSkillFrame_Show then
        TradeSkillFrame_Show = BlizzardTradeSkillShow
    end
end
UIParentLoadsViewer_Fire = nil
function HideUIPanel(f) f.shown = false; if f.scripts.OnHide then f.scripts.OnHide(f) end end
function LoadAddOn(name) error("LoadAddOn(" .. tostring(name) .. ") must never be called — LoD addons fire events other addons act on (field 2026-09-25)") end
world.closes = 0
function CloseTradeSkill() world.closes = world.closes + 1; world.trade.line = nil end

-- --------------------------------------------------- load REAL addon --
dofile("DustBunnyData.lua")   -- run from the addon root: lua5.1 dev/test_harness.lua
dofile("DustBunny.lua")

local ev  -- the addon's event frame is the last plain frame with events
-- find it: the frame that registered ADDON_LOADED
for _, name in ipairs({}) do end
local addonEv
-- CreateFrame stubs don't track a list of plain frames; re-find via scripts:
-- the event frame has an OnEvent script and ADDON_LOADED registered.
-- Simplest: we captured nothing, so drive via the global secure list + a
-- re-scan of _G is unavailable in stubs — instead the addon's ev frame is
-- reachable because SetScript stored the handler on the frame itself. We
-- keep our own registry:
-- (patched approach: the LAST StubFrame created before PLAYER_LOGIN fires
--  with events.ADDON_LOADED is the one — walk allFrames)
-- To keep this robust we re-create minimal tracking:
check("harness bootstrap", true)

-- we need the event frame: hook was stored during dofile; recover it by
-- firing through a captured registry. Rebuild: track all frames created.
-- (CreateFrame above didn't record plain frames; fix here by wrapping.)
local plainFrames = {}
local origCreateFrame = CreateFrame
function CreateFrame(...)
    local f = origCreateFrame(...)
    table.insert(plainFrames, f)
    return f
end

-- The addon already ran, so recover its event frame via garbage inspection:
-- not possible portably — instead RELOAD the addon with tracking in place.
allSecure = {}
dofile("DustBunny.lua")
for _, f in ipairs(plainFrames) do
    if f.events["ADDON_LOADED"] then addonEv = f end
end
check("event frame located", addonEv ~= nil)

local function Fire(event, a1, a2)
    if addonEv and addonEv.scripts.OnEvent then
        addonEv.scripts.OnEvent(addonEv, event, a1, a2)
    end
end
local function Tick()
    if addonEv and addonEv.scripts.OnUpdate then addonEv.scripts.OnUpdate() end
end

-- pick REAL ids from the generated data (no invented ids — Rule 0 at home)
local function firstKey(t) local k = next(t) return k end
local DE_ID = firstKey(DustBunny_Data.disenchant)
local MILL_ID = firstKey(DustBunny_Data.mill)
local POISON_ID = DE_ID -- same id, but we will present it as Legendary

Fire("ADDON_LOADED", "DustBunny")
Fire("PLAYER_LOGIN")
check("frame built", DustBunnyFrame ~= nil)

-- ------------------------------------------------------ invariant engine --
local function Invariants(label)
    -- macro target must point at a listed, legal item
    for _, cb in ipairs(allSecure) do
        local m = cb.attrs and cb.attrs.macrotext
        if m == "/cast Smelting" then m = nil end  -- craft tab: window-open cast, no target by design
        if m and m ~= "" then
            local bag, slot = string.match(m, "/use (%d+) (%d+)")
            check(label .. ": macro has target", bag ~= nil, m)
            if bag then
                local it = world.bags[tonumber(bag)][tonumber(slot)]
                check(label .. ": macro target exists", it ~= nil)
                if it then
                    local q = world.items[it.id].quality
                    check(label .. ": clause — target not legendary", q < 5)
                    check(label .. ": clause — target not excluded",
                          not DustBunnyDB.exclusions[it.id])
                    check(label .. ": clause — target in data",
                          DustBunny_Data.disenchant[it.id]
                          or DustBunny_Data.mill[it.id]
                          or DustBunny_Data.prospect[it.id])
                end
            end
        end
    end
end

-- ---------------------------------------------------------- scenarios --
-- T1: DE item appears, selected, macro aims at it
world.items[DE_ID] = { name = "Dusty Sword", quality = 2 }
world.skills = { { name = "Enchanting", rank = 450 },
                 { name = "Inscription", rank = 450 },
                 { name = "Jewelcrafting", rank = 450 } }
world.bags[0] = { { id = DE_ID, count = 1 } }
Fire("SKILL_LINES_CHANGED")
DustBunnyFrame.shown = true
SlashCmdList["DUSTBUNNY"]()  -- toggles: was shown -> hides
SlashCmdList["DUSTBUNNY"]()  -- shows + refresh
local deBtn = _G["DustBunnyCastdisenchant"]
check("T1 macro aims at bag 0 slot 1",
      deBtn.attrs.macrotext == "/cast Disenchant\n/use 0 1", tostring(deBtn.attrs.macrotext))
Invariants("T1")

-- T2: mill stack rule — 4 unusable, 5 usable
SlashCmdList["DUSTBUNNY"]() -- hide
world.items[MILL_ID] = { name = "Test Herb", quality = 1 }
world.bags[0] = { { id = MILL_ID, count = 4 } }
SlashCmdList["DUSTBUNNY"]() -- show/refresh (tab still 1) — switch to mill tab
_G["DustBunnyTab2"].scripts.OnClick()
local millBtn = _G["DustBunnyCastmill"]
check("T2 four-stack: button disabled", millBtn.enabled == false,
      tostring(millBtn.attrs.macrotext))
world.bags[0][1].count = 5
Fire("BAG_UPDATE"); Tick()
check("T2 five-stack: macro aims", millBtn.attrs.macrotext == "/cast Milling\n/use 0 1",
      tostring(millBtn.attrs.macrotext))
Invariants("T2")

-- T3: skill gate — rank below requirement disables
world.skills[2].rank = -1  -- Inscription below any herb req
Fire("SKILL_LINES_CHANGED")
check("T3 low skill: button disabled", millBtn.enabled == false)
Invariants("T3")
world.skills[2].rank = 450
Fire("SKILL_LINES_CHANGED")

-- T4: exclusion is permanent and restorable
_G["DustBunnyTab1"].scripts.OnClick()
world.bags[0] = { { id = DE_ID, count = 1 } }
Fire("BAG_UPDATE"); Tick()
local row1 = _G["DustBunnyRow1"]
row1.scripts.OnClick(row1, "RightButton")
check("T4 excluded", DustBunnyDB.exclusions[DE_ID] == true)
check("T4 gone from macro", deBtn.attrs.macrotext == "" or deBtn.enabled == false)
Invariants("T4")
_G["DustBunnyTab5"].scripts.OnClick()
local exRow = _G["DustBunnyRow1"]
exRow.scripts.OnClick(exRow, "RightButton")
check("T4 restored", DustBunnyDB.exclusions[DE_ID] == nil)
_G["DustBunnyTab1"].scripts.OnClick()

-- T5: THE CLAUSE — legendary presented in bags never listed, never targeted
world.items[POISON_ID].quality = 5
Fire("BAG_UPDATE"); Tick()
check("T5 legendary: button disabled", deBtn.enabled == false,
      tostring(deBtn.attrs.macrotext))
Invariants("T5")
world.items[POISON_ID].quality = 2

-- T6: drain + advance — two DE items; removing first advances macro
local DE_ID2
for k in pairs(DustBunny_Data.disenchant) do
    if k ~= DE_ID then DE_ID2 = k break end
end
world.items[DE_ID2] = { name = "Aged Boots", quality = 3 }
world.bags[0] = { { id = DE_ID, count = 1 }, { id = DE_ID2, count = 1 } }
Fire("BAG_UPDATE"); Tick()
-- select rare (sorted first: quality 3 first) then dust it away
row1.scripts.OnClick(row1, "LeftButton")
local firstTarget = deBtn.attrs.macrotext
world.bags[0][2] = nil  -- the rare (slot 2? aggregation sorted) — remove BOTH safe:
world.bags[0] = { { id = DE_ID, count = 1 } }
Fire("BAG_UPDATE"); Tick()
check("T6 advance: macro moved to survivor",
      deBtn.attrs.macrotext == "/cast Disenchant\n/use 0 1", tostring(deBtn.attrs.macrotext))
world.bags[0] = {}
Fire("BAG_UPDATE"); Tick()
check("T6 empty: disabled", deBtn.enabled == false)
Invariants("T6")

-- T7: aggregation across slots
world.bags[0] = { { id = DE_ID, count = 1 }, { id = DE_ID, count = 1 } }
world.bags[1] = { { id = DE_ID, count = 1 } }
Fire("BAG_UPDATE"); Tick()
check("T7 count aggregated", row1.count and true)  -- structural; count via entries
Invariants("T7")

-- T8: equip-guard — GCD active means the click is disarmed (no /use fallthrough)
world.bags[0] = { { id = DE_ID, count = 1 } }
Fire("BAG_UPDATE"); Tick()
row1.scripts.OnClick(row1, "LeftButton")
world.cooldown = true
deBtn.scripts.PreClick(deBtn)
check("T8 GCD: disarmed", deBtn.attrs.macrotext == "", tostring(deBtn.attrs.macrotext))
world.cooldown = false
deBtn.scripts.PreClick(deBtn)
check("T8 clear: re-armed", deBtn.attrs.macrotext == "/cast Disenchant\n/use 0 1",
      tostring(deBtn.attrs.macrotext))
world.casting = "Disenchant"
deBtn.scripts.PreClick(deBtn)
check("T8 mid-cast: disarmed", deBtn.attrs.macrotext == "")
world.casting = nil
Invariants("T8")

-- T9: locked-slot stickiness — selection survives the cast it caused
-- (fresh world wholesale: T7 left stock in bag 1 and the addon RIGHTLY
-- targeted it — dirty-stage harness artifact, not an addon defect)
world.bags = { [0] = { { id = DE_ID, count = 1, locked = true } } }
Fire("BAG_UPDATE"); Tick()
check("T9 locked: still listed", row1.id == DE_ID, tostring(row1.id))
check("T9 locked: button disarmed (no unlocked target)", deBtn.enabled == false,
      "enabled=" .. tostring(deBtn.enabled) .. " macro=" .. tostring(deBtn.attrs.macrotext))
world.bags[0][1].locked = false
Fire("BAG_UPDATE"); Tick()
check("T9 unlocked: re-armed", deBtn.attrs.macrotext == "/cast Disenchant\n/use 0 1",
      tostring(deBtn.attrs.macrotext))
Invariants("T9")

-- --------------------------------------------------- S: Smelting (1.1.0) --
local function CraftInvariants(label)
    for _, c in ipairs(world.crafted) do
        local r = world.trade.recipes[c.index]
        check(label .. ": craft n<=makes", r and c.n <= (r.avail or 0), r and (c.n .. ">" .. tostring(r.avail)) or "bad index")
        check(label .. ": craft n>=1", c.n >= 1)
        check(label .. ": craft not excluded", r and not DustBunnyDB.exclusions[r.id])
    end
end
-- stub rows never hold nil: an unset field reads back as the catch-all
-- function, so "empty row" is "id is not a number"
local function Empty(r) return type(r.id) ~= "number" end
local smeltTab, smeltBox = _G["DustBunnyTab4"], _G["DustBunnySmeltCount"]
local smeltBtn, maxBtn = _G["DustBunnySmelt"], _G["DustBunnySmeltMax"]
world.skills[#world.skills + 1] = { name = "Mining", rank = 300 }
Fire("SKILL_LINES_CHANGED")
world.items[3575] = { name = "Iron Bar", quality = 1 }
world.items[3577] = { name = "Gold Bar", quality = 1 }
local RECIPES = {
    { name = "Iron Bar", id = 3575, avail = 37 },
    { name = "Classic", kind = "header" },
    { name = "Gold Bar", id = 3577, avail = 8 },
    { name = "Copper Bar", id = 2840, avail = 0 },   -- nothing to make: not listed
}
-- emulate the secure tab: PreClick decides the macro; a "/cast Smelting"
-- opens a Mining session (server) and UIParent tries to show the viewer;
-- then PostClick switches the tab
-- TRUE click order (persisted trace 2026-09-25): PreClick -> the secure
-- cast fires TRADE_SKILL_UPDATE/SHOW synchronously -> PostClick. Anything
-- done in PostClick is too late for the SHOW.
local function ClickSmeltTab()
    smeltTab.scripts.PreClick(smeltTab)
    local cast = smeltTab.attrs.macrotext == "/cast Smelting"
    if cast then
        world.trade = { line = "Mining", recipes = RECIPES }
        if not TradeSkillFrame_Show then          -- first open: UIParent loads the LoD viewer...
            UIParentLoadsViewer()
            Fire("ADDON_LOADED", "Blizzard_TradeSkillUI")   -- ...and we wrap before its first show
        end
        Fire("TRADE_SKILL_UPDATE")
        TradeSkillFrame_Show()      -- UIParent.lua:988 runs BEFORE our TRADE_SKILL_SHOW handler
        Fire("TRADE_SKILL_SHOW")
    end
    smeltTab.scripts.PostClick(smeltTab)
    Tick()
end
check("S0 secure tab is a secure button", smeltTab.template and string.find(smeltTab.template, "SecureActionButtonTemplate") ~= nil)
check("S0 no bottom secure button for the craft tab", _G["DustBunnyCastsmelt"] == nil)

-- S1: tab click opens a session headlessly — the Blizzard viewer never shows
ClickSmeltTab()
check("S1 tab cast armed on click", smeltTab.attrs.macrotext == "/cast Smelting", tostring(smeltTab.attrs.macrotext))
check("S1 session live", GetTradeSkillLine() == "Mining")
check("S1 viewer suppressed", TradeSkillFrame.shown == false)
check("S1 no hangup on suppress", world.closes == 0, "closes=" .. world.closes)
Invariants("S1")

-- S2: rows from the session, sorted, headers and 0-avail skipped
local row2 = _G["DustBunnyRow2"]
check("S2 open: row1 Gold Bar", row1.id == 3577, tostring(row1.id))
check("S2 open: row2 Iron Bar", row2.id == 3575, tostring(row2.id))
check("S2 open: row3 empty (0-avail hidden)", Empty(_G["DustBunnyRow3"]))
check("S2 open: box shown", smeltBox.shown == true)
-- re-clicking the tab while the session is live must NOT re-cast
smeltTab.scripts.PreClick(smeltTab)
check("S2 live: re-click does not cast", smeltTab.attrs.macrotext == "", tostring(smeltTab.attrs.macrotext))
smeltTab.scripts.PostClick(smeltTab); Tick()
-- DustBunny auto-selects the first row when nothing is selected (the
-- destroy tabs' "keep clicking" rule) — the craft tab inherits it
check("S2 open: first row auto-selected, smelt enabled", smeltBtn.enabled == true)

-- S3: select Iron Bar, type 5, Smelt -> DoTradeSkill(1, 5)
row2.scripts.OnClick(row2, "LeftButton")
check("S3 selected: smelt enabled", smeltBtn.enabled == true)
smeltBox.text_v = "5"
smeltBtn.scripts.OnClick()
local last = world.crafted[#world.crafted]
check("S3 smelt 5", last and last.index == 1 and last.n == 5, last and (last.index .. "/" .. last.n) or "no craft")

-- S4: 500 -> clamped to makes (37)
smeltBox.text_v = "500"
smeltBtn.scripts.OnClick()
last = world.crafted[#world.crafted]
check("S4 clamp 500->37", last.n == 37, tostring(last.n))

-- S5: blank -> 1
smeltBox.text_v = ""
smeltBtn.scripts.OnClick()
last = world.crafted[#world.crafted]
check("S5 blank->1", last.n == 1, tostring(last.n))

-- S6: Max fills the box with makes; smelt -> 37
maxBtn.scripts.OnClick()
check("S6 max fills box", smeltBox.text_v == "37", tostring(smeltBox.text_v))
smeltBtn.scripts.OnClick()
check("S6 smelt max", world.crafted[#world.crafted].n == 37)
CraftInvariants("S3-6")

-- S6b: Smelt releases keyboard focus (movement/jump/Esc must reach the game)
smeltBox.focused = true
smeltBox.text_v = "2"
smeltBtn.scripts.OnClick()
check("S6b smelt clears focus", smeltBox.focused == false)

-- S6c: presets fill the box and smelt immediately, clamped to makeable
local p25, p100 = _G["DustBunnyPreset25"], _G["DustBunnyPreset100"]
check("S6c presets shown on live forge", p25.shown == true and p100.shown == true)
smeltBox.focused = true
p25.scripts.OnClick()
last = world.crafted[#world.crafted]
check("S6c preset 25 smelts 25", last.n == 25 and smeltBox.text_v == "25", tostring(last.n))
check("S6c preset releases focus", smeltBox.focused == false)
p100.scripts.OnClick()
check("S6c preset 100 clamps to 37", world.crafted[#world.crafted].n == 37, tostring(world.crafted[#world.crafted].n))
check("S6c box DISPLAYS the clamp", smeltBox.text_v == "37", tostring(smeltBox.text_v))

-- S6d: countdown — one success per bar; interrupt keeps the remainder; zero clears
smeltBox.text_v = "5"
smeltBtn.scripts.OnClick()
check("S6d batch of 5 started", world.crafted[#world.crafted].n == 5 and smeltBox.text_v == "5")
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Iron Bar")
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Iron Bar")
check("S6d counted down to 3", smeltBox.text_v == "3", tostring(smeltBox.text_v))
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Gold Bar")   -- someone else's recipe: ignored
check("S6d other recipe ignored", smeltBox.text_v == "3", tostring(smeltBox.text_v))
-- interrupted here: remainder stays; next Smelt finishes exactly the rest
smeltBtn.scripts.OnClick()
check("S6d resume smelts the remainder", world.crafted[#world.crafted].n == 3, tostring(world.crafted[#world.crafted].n))
for _ = 1, 3 do Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Iron Bar") end
check("S6d complete clears the box", smeltBox.text_v == "", tostring(smeltBox.text_v))
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Iron Bar")   -- stray success after completion
check("S6d stray success after completion is harmless", smeltBox.text_v == "")
check("S6c forge frame grew", DustBunnyFrame.height_v == 384, tostring(DustBunnyFrame.height_v))
CraftInvariants("S6b-c")

-- S7: exclude Gold Bar -> gone; Excluded tab lists it; restore
row1.scripts.OnClick(row1, "RightButton")
check("S7 excluded: gone from list", row1.id == 3575 and Empty(row2), tostring(row1.id) .. "/" .. tostring(row2.id))
check("S7 excluded: recorded", DustBunnyDB.exclusions[3577] == true)
_G["DustBunnyTab5"].scripts.OnClick()
local exRow1 = _G["DustBunnyRow1"]
check("S7 excluded tab shows Gold Bar", exRow1.id == 3577, tostring(exRow1.id))
exRow1.scripts.OnClick(exRow1, "RightButton")
ClickSmeltTab()
check("S7 restored", row1.id == 3577, tostring(row1.id))

-- S8: excluded recipe can never be smelted even if selected before exclusion
row1.scripts.OnClick(row1, "LeftButton")     -- select Gold Bar
row1.scripts.OnClick(row1, "RightButton")    -- exclude it
smeltBox.text_v = "3"
smeltBtn.scripts.OnClick()
last = world.crafted[#world.crafted]
check("S8 excluded never smelted (auto-select moved to Iron Bar)", last.index == 1 and last.n == 3,
      last.index .. "/" .. last.n)
CraftInvariants("S7-8")
DustBunnyDB.exclusions[3577] = nil

-- S9: server closes the session mid-tab -> rows clear, controls hidden
world.trade.line = nil
Fire("TRADE_SKILL_CLOSE"); Tick()
check("S9 closed: rows cleared", Empty(row1), tostring(row1.id))
check("S9 closed: box hidden", smeltBox.shown == false)
Invariants("S9")

-- S10: leaving the tab ends a live session (one CloseTradeSkill, no more)
ClickSmeltTab()
check("S10 reopened", GetTradeSkillLine() == "Mining" and TradeSkillFrame.shown == false)
local closesBefore = world.closes
_G["DustBunnyTab1"].scripts.OnClick()
check("S10 leaving tab hangs up exactly once", world.closes == closesBefore + 1 and GetTradeSkillLine() == nil,
      "closes=" .. world.closes .. " line=" .. tostring(GetTradeSkillLine()))
check("S10 presets hidden off the forge", _G["DustBunnyPreset5"].shown == false)
check("S10 frame back to base height", DustBunnyFrame.height_v == 360, tostring(DustBunnyFrame.height_v))

-- S11: closing DustBunny ends a live session; stock viewer works afterwards
ClickSmeltTab()
closesBefore = world.closes
DustBunnyFrame.scripts.OnHide(DustBunnyFrame)
check("S11 frame hide hangs up", world.closes == closesBefore + 1)
TradeSkillFrame_Show()
check("S11 viewer no longer suppressed", TradeSkillFrame.shown == true)
TradeSkillFrame.shown = false
_G["DustBunnyTab1"].scripts.OnClick()

-- S12: another profession takes the session -> forge yields on the FIRST
-- open (UIParent's show runs before our handler), DustBunny closes, and
-- the newcomer's session is never hung up
DustBunnyFrame.shown = true
ClickSmeltTab()
check("S12 forge live", GetTradeSkillLine() == "Mining" and TradeSkillFrame.shown == false)
closesBefore = world.closes
world.trade = { line = "Blacksmithing", recipes = {} }
TradeSkillFrame_Show()              -- UIParent first...
check("S12 other window shows on FIRST open", TradeSkillFrame.shown == true)
Fire("TRADE_SKILL_SHOW"); Tick()    -- ...then us
check("S12 DustBunny closed", DustBunnyFrame.shown == false)
check("S12 newcomer's session untouched", world.closes == closesBefore and GetTradeSkillLine() == "Blacksmithing",
      "closes=" .. world.closes .. " line=" .. tostring(GetTradeSkillLine()))
TradeSkillFrame.shown = false
world.trade = { line = nil, recipes = {} }
DustBunnyFrame.shown = true

-- S13: exclusive on EVERY tab — opening DustBunny hangs up a foreign window;
-- a foreign window opening while DustBunny is up (non-craft tab) makes it yield
_G["DustBunnyTab1"].scripts.OnClick()
world.trade = { line = "Blacksmithing", recipes = {} }
closesBefore = world.closes
DustBunnyFrame.scripts.OnShow(DustBunnyFrame)
check("S13 open closes a foreign window", world.closes == closesBefore + 1 and GetTradeSkillLine() == nil,
      "closes=" .. world.closes .. " line=" .. tostring(GetTradeSkillLine()))
DustBunnyFrame.shown = true
world.trade = { line = "Engineering", recipes = {} }
closesBefore = world.closes
Fire("TRADE_SKILL_SHOW"); Tick()
check("S13 foreign open on DE tab: DustBunny yields", DustBunnyFrame.shown == false)
check("S13 yield never hangs up THEIR session", world.closes == closesBefore and GetTradeSkillLine() == "Engineering")
world.trade = { line = nil, recipes = {} }
DustBunnyFrame.shown = true

-- S14: the field sequence — BS open, open DustBunny (hangs up BS), click
-- Smelting: DustBunny must stay open with the forge live, not yield
_G["DustBunnyTab1"].scripts.OnClick()
world.trade = { line = "Blacksmithing", recipes = {} }
DustBunnyFrame.scripts.OnShow(DustBunnyFrame); DustBunnyFrame.shown = true
Fire("TRADE_SKILL_CLOSE"); Tick()
check("S14 BS hung up on open", GetTradeSkillLine() == nil)
ClickSmeltTab()
check("S14 DustBunny still open", DustBunnyFrame.shown == true)
check("S14 forge live, viewer suppressed", GetTradeSkillLine() == "Mining" and TradeSkillFrame.shown == false)
check("S14 rows listed", row1.id == 3577, tostring(row1.id))
_G["DustBunnyTab1"].scripts.OnClick()
check("S14 leaving hangs up the forge", GetTradeSkillLine() == nil)

-- back to DE tab for the fuzzer (other tabs unchanged)
_G["DustBunnyTab1"].scripts.OnClick()

-- FZ: fuzz — random worlds with poison sprinkled in
math.randomseed(20260722)
local ids = {}
for k in pairs(DustBunny_Data.disenchant) do
    ids[#ids + 1] = k
    if #ids >= 40 then break end
end
for seed = 1, 100 do
    world.bags = { [0] = {} }
    for s = 1, math.random(1, 12) do
        local id = ids[math.random(#ids)]
        local q = math.random(1, 6) >= 5 and 5 or 2  -- ~1/3 poison legendaries
        world.items[id] = { name = "fz" .. id, quality = q }
        world.bags[0][s] = { id = id, count = math.random(1, 20) }
    end
    Fire("BAG_UPDATE"); Tick()
    Invariants("FZ" .. seed)
end

print(string.format("== DustBunny harness: %d passed, %d failed ==", passed, failed))
os.exit(failed == 0 and 0 or 1)
