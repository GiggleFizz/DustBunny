-- DustBunny.lua — queue-style Disenchant / Milling / Prospecting for 3.3.5a.
-- Design + rulings: wizzfizz 2026-07-22 (A: all three trades; B: permanent
-- per-item exclusions; C: ONLY Legendary protected — "accidentally dusting
-- your epic is a rite of passage"; D: one deliberate click per cast, no
-- mousewheel — bump-risk ruled cheap; E: craft-frame look, rarity-colored).
--
-- Mechanics honesty: the 3.3.5 client requires a hardware event per cast —
-- there is no legal auto-loop for addon-driven spells. Each click of the
-- action button performs exactly one cast via a secure macro
-- ("/cast <spell>" + "/use bag slot" completes the item targeting). The
-- macro is rewritten out of combat only.
--
-- Server rules encoded (read from this stack's source, 2026-07-22):
--   * mill/prospect need a SINGLE STACK of >= 5 (SpellEffects.cpp:5534/5559)
--   * skill gates: RequiredDisenchantSkill / herb+ore RequiredSkillRank
--     vs Enchanting / Inscription / Jewelcrafting
--   * Legendary+ items are absent from the DATA by generation; a runtime
--     quality guard backs it up (the Thunderfury clause, both layers)

local ADDON = "DustBunny"
local BAGS = { 0, 1, 2, 3, 4 }
local ROWS, ROW_H = 12, 20

local TABS = {
    { key = "disenchant", label = "Disenchant",  spell = "Disenchant",  skill = "Enchanting",    minStack = 1 },
    { key = "mill",       label = "Milling",     spell = "Milling",     skill = "Inscription",   minStack = 5 },
    { key = "prospect",   label = "Prospecting", spell = "Prospecting", skill = "Jewelcrafting", minStack = 5 },
    -- 1.1.0 "Forge": a CRAFT tab — rows come from the open Mining window
    -- (GetTradeSkillInfo), execution is DoTradeSkill(index, n): the
    -- client's own repeat engine, unprotected, so "make N" is one click
    { key = "smelt",      label = "Smelting",    spell = "Smelting",    skill = "Mining",        craft = true },
    { key = "excluded",   label = "Excluded" },
}

local DB              -- SavedVariables (exclusions, pos)
local frame, listRows, scrollFrame, castButtons, tabButtons, statusText
local smeltBox, smeltBtn, maxBtn   -- craft-tab controls (1.1.0)
local presetBtns = {}              -- one-click amounts (1.1.0 field enhancement)
local pendingCraft = nil           -- { name=, remaining= } while a batch runs
local PRESETS = { 5, 10, 25, 50, 100 }
local FRAME_H, FORGE_EXTRA = 360, 24   -- the forge grows one strip taller
local headless = false             -- a trade-skill session owned by the forge
local activeTab = 1
local selected = nil       -- itemID selected in the active tab
local entries = {}         -- current tab's display list
local skills = {}          -- skill name -> rank
local lootPending = false
local rescanQueued = false

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffd2b48cDustBunny|r: " .. msg)
end

-- ------------------------------------------------------------- scanning --
local function ScanSkills()
    wipe(skills)
    for i = 1, GetNumSkillLines() do
        local name, isHeader, _, rank = GetSkillLineInfo(i)
        if name and not isHeader then
            skills[name] = rank
        end
    end
end

local function ItemIdFromLink(link)
    if not link then return nil end
    local id = string.match(link, "item:(%d+)")
    return id and tonumber(id)
end

-- Build the active tab's entries: one row per itemID, aggregated count,
-- plus the bag/slot the macro will target (first eligible slot; for
-- mill/prospect that slot alone must hold >= 5 — the server's stack rule).
local function ScanBags()
    wipe(entries)
    local tab = TABS[activeTab]
    if tab.key == "excluded" then
        for id in pairs(DB.exclusions) do
            local name, _, quality = GetItemInfo(id)
            table.insert(entries, { id = id, name = name or ("item " .. id),
                                    quality = quality or 1, count = 0 })
        end
        table.sort(entries, function(a, b) return a.name < b.name end)
        return
    end
    if tab.craft then
        -- the open trade-skill window IS the data: every recipe this
        -- character knows, with the client's own "makes up to N"
        if GetTradeSkillLine() ~= tab.skill then return end
        for i = 1, GetNumTradeSkills() do
            local name, kind, numAvailable = GetTradeSkillInfo(i)
            if name and kind ~= "header" then
                local id = ItemIdFromLink(GetTradeSkillItemLink(i))
                if id and not DB.exclusions[id] and (numAvailable or 0) > 0 then
                    local _, _, quality = GetItemInfo(id)
                    table.insert(entries, { id = id, name = name, quality = quality or 1,
                                            count = numAvailable, index = i,
                                            icon = GetTradeSkillIcon(i) })
                end
            end
        end
        table.sort(entries, function(a, b) return a.name < b.name end)
        return
    end
    local data = DustBunny_Data[tab.key]
    local byId = {}
    for _, bag in ipairs(BAGS) do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            local id = ItemIdFromLink(link)
            local req = id and data[id]
            if req and not DB.exclusions[id] then
                local _, count, locked, quality = GetContainerItemInfo(bag, slot)
                quality = quality or select(3, GetItemInfo(id)) or 1
                if quality < 5 then  -- runtime Thunderfury guard
                    local e = byId[id]
                    if not e then
                        local name = GetItemInfo(id)
                        e = { id = id, name = name or ("item " .. id),
                              quality = quality, count = 0, req = req }
                        byId[id] = e
                        table.insert(entries, e)
                    end
                    e.count = e.count + (count or 1)
                    -- LOCKED stacks stay listed (mid-cast lock made the
                    -- selection wander, field P2 2026-07-23) but only an
                    -- UNLOCKED slot satisfying the stack rule is targetable
                    if not locked and not e.bag
                       and (count or 1) >= tab.minStack then
                        e.bag, e.slot = bag, slot
                    end
                end
            end
        end
    end
    table.sort(entries, function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        return a.name < b.name
    end)
end

local function EntryUsable(e)
    local tab = TABS[activeTab]
    if tab.craft then return (e.count or 0) > 0 and skills[tab.skill] ~= nil end
    if not e.bag then return false end                     -- no stack meets rule
    local rank = skills[tab.skill]
    if not rank then return false end                      -- profession unknown
    return rank >= (e.req or 0)
end

-- ------------------------------------------------------ secure casting --
local function UpdateMacro()
    if InCombatLockdown() then return end
    -- disarm EVERY inactive cast button: a hidden button with a stale
    -- macro is still clickable via keybinding, and a stale /use target is
    -- a destructive cast at an unverified slot (fuzzer catch, day one —
    -- the Thunderfury clause in action)
    for i, cb in ipairs(castButtons) do
        if i ~= activeTab then
            cb:SetAttribute("macrotext", "")
            cb:Disable()
        end
    end
    local tab = TABS[activeTab]
    if tab.craft then return end
    local btn = castButtons[activeTab]
    if not btn then return end   -- the TAB is the opener; smelting is DoTradeSkill
    local target
    for _, e in ipairs(entries) do
        if e.id == selected and EntryUsable(e) then target = e break end
    end
    if target then
        btn:SetAttribute("macrotext",
            "/cast " .. tab.spell .. "\n/use " .. target.bag .. " " .. target.slot)
        btn:Enable()
    else
        btn:SetAttribute("macrotext", "")
        btn:Disable()
    end
end

-- --------------------------------------------------- headless session --
-- The trade-skill WINDOW is only a viewer; DoTradeSkill needs the SESSION.
-- Blizzard_TradeSkillUI.xml:982 — TradeSkillFrame's OnHide calls
-- CloseTradeSkill(), so hiding it hangs up (the gossip lesson, in an
-- apron). UIParent shows it via the global TradeSkillFrame_Show
-- (UIParent.lua:985-988): while the forge owns the session we wrap that
-- to a no-op; if the window is already up we hide it ONCE with OnHide
-- neutralised. One session per client (3.3.5): opening Mining replaces
-- any other profession window — accepted at ruling 2026-09-25.
local function SuppressTradeSkillFrame()
    if TradeSkillFrame and TradeSkillFrame:IsShown() then
        local onHide = TradeSkillFrame:GetScript("OnHide")
        TradeSkillFrame:SetScript("OnHide", nil)
        HideUIPanel(TradeSkillFrame)
        TradeSkillFrame:SetScript("OnHide", onHide)
    end
end

-- NEVER force-load Blizzard_TradeSkillUI: it is load-on-demand, and its
-- load fires trade-skill events that other addons (ProfessionCapper,
-- field 2026-09-25) read as "a profession window is opening". Wrap lazily:
-- at login if already loaded, on ADDON_LOADED when UIParent loads it, and
-- on TRADE_SKILL_SHOW as the last resort.
local function InstallShowWrapper()
    if DustBunny_OrigTradeSkillShow then return end
    if not TradeSkillFrame_Show then return end
    DustBunny_OrigTradeSkillShow = TradeSkillFrame_Show
    TradeSkillFrame_Show = function(...)
        -- UIParent's TRADE_SKILL_SHOW handler runs BEFORE ours, so a stale
        -- flag alone would swallow ANOTHER profession's first open (field
        -- 2026-09-25): suppress only when the live session is the forge's
        if headless then
            for _, t in ipairs(TABS) do
                if t.craft and GetTradeSkillLine() == t.skill then return end
            end
        end
        return DustBunny_OrigTradeSkillShow(...)
    end
end

local function EndHeadless()
    if not headless then return end
    headless = false
    local tab
    for _, t in ipairs(TABS) do if t.craft then tab = t end end
    if tab and GetTradeSkillLine() == tab.skill then CloseTradeSkill() end
end

-- ------------------------------------------------------------------ UI --
local function Refresh()
    ScanBags()
    -- selection upkeep: vanished item -> advance to first row (keep clicking)
    local found = false
    for _, e in ipairs(entries) do
        if e.id == selected then found = true break end
    end
    if not found then
        selected = entries[1] and entries[1].id or nil
    end

    local tab = TABS[activeTab]
    local offset = FauxScrollFrame_GetOffset(scrollFrame)
    FauxScrollFrame_Update(scrollFrame, #entries, ROWS, ROW_H)
    for i = 1, ROWS do
        local row = listRows[i]
        local e = entries[i + offset]
        if e then
            local r, g, b = GetItemQualityColor(e.quality)
            local usable = tab.key == "excluded" or EntryUsable(e)
            if not usable then r, g, b = 0.45, 0.45, 0.45 end
            row.text:SetText(e.name)
            row.text:SetTextColor(r, g, b)
            row.count:SetText(e.count > 0 and e.count or "")
            local icon = e.icon or select(10, GetItemInfo(e.id))
            row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.id = e.id
            -- 3.3.5 has no SetShown (field catch 2026-07-23) — era-correct:
            if e.id == selected and tab.key ~= "excluded" then
                row.selbar:Show()
            else
                row.selbar:Hide()
            end
            row:Show()
        else
            row.id = nil
            row:Hide()
        end
    end

    if tab.key == "excluded" then
        statusText:SetText(#entries .. " excluded — right-click to restore")
    else
        local rank = skills[tab.skill]
        statusText:SetText(rank and (tab.skill .. " " .. rank) or (tab.skill .. " not known"))
    end
    for i, tb in ipairs(tabButtons) do
        tb:SetChecked(i == activeTab)
    end
    for i, cb in ipairs(castButtons) do
        if i == activeTab then cb:Show() else cb:Hide() end
    end
    -- craft tab: session live -> count controls; else waiting on the cast
    if smeltBox then
        local sessionLive = tab.craft and GetTradeSkillLine() == tab.skill
        if sessionLive then
            headless = true
            SuppressTradeSkillFrame()
            smeltBox:Show(); smeltBtn:Show(); maxBtn:Show()
            for _, b in ipairs(presetBtns) do b:Show() end
            frame:SetHeight(FRAME_H + FORGE_EXTRA)
            local sel
            for _, e in ipairs(entries) do if e.id == selected then sel = e end end
            if sel then smeltBtn:Enable() else smeltBtn:Disable() end
        else
            smeltBox:Hide(); smeltBtn:Hide(); maxBtn:Hide()
            for _, b in ipairs(presetBtns) do b:Hide() end
            frame:SetHeight(FRAME_H)
            if tab.craft and skills[tab.skill] then
                statusText:SetText("Opening " .. tab.skill .. "… (click the tab again if nothing lists)")
            end
        end
    end
    UpdateMacro()
end

-- craft execution: DoTradeSkill(index, n) — n clamped to the client's own
-- "makes up to" so the box can never over-ask; blank = 1 (stock convention)
local function SelectedEntry()
    for _, e in ipairs(entries) do if e.id == selected then return e end end
end

local function SmeltClicked()
    local tab = TABS[activeTab]
    if not tab.craft then return end
    -- a focused edit box swallows movement/jump/Esc — the very keys that
    -- interrupt a craft (field 2026-09-25): every smelt path releases it
    smeltBox:ClearFocus()
    local e = SelectedEntry()
    if not e or not EntryUsable(e) then return end
    local n = tonumber(smeltBox:GetText()) or 1
    if n < 1 then n = 1 end
    if n > e.count then n = e.count end
    smeltBox:SetText(tostring(n))              -- the box shows what will actually be made
    pendingCraft = { name = e.name, remaining = n }
    DoTradeSkill(e.index, n)
end

-- countdown: one success = one bar; an interrupted batch leaves the
-- remainder in the box, so the next Smelt finishes the job
local function CraftSucceeded(spellName)
    if not pendingCraft or spellName ~= pendingCraft.name then return end
    pendingCraft.remaining = pendingCraft.remaining - 1
    if pendingCraft.remaining <= 0 then
        pendingCraft = nil
        if smeltBox then smeltBox:SetText("") end
    elseif smeltBox then
        smeltBox:SetText(tostring(pendingCraft.remaining))
    end
end

local function MaxClicked()
    local e = SelectedEntry()
    if e then smeltBox:SetText(tostring(e.count)) end
end

local function PresetClicked(n)
    local e = SelectedEntry()
    if e and n > e.count then n = e.count end   -- display the clamp too
    smeltBox:SetText(tostring(n))
    SmeltClicked()        -- clamps to makeable, releases focus
end

local function SetTab(i)
    if TABS[activeTab].craft and not TABS[i].craft then EndHeadless() end
    activeTab = i
    selected = nil
    FauxScrollFrame_SetOffset(scrollFrame, 0)
    Refresh()
end

local function RowClicked(row, mouseButton)
    if not row.id then return end
    local tab = TABS[activeTab]
    if tab.key == "excluded" then
        if mouseButton == "RightButton" then
            DB.exclusions[row.id] = nil
            Print((GetItemInfo(row.id) or row.id) .. " restored.")
            Refresh()
        end
        return
    end
    if mouseButton == "RightButton" then
        DB.exclusions[row.id] = true
        Print((GetItemInfo(row.id) or row.id) .. " permanently excluded (Excluded tab to undo).")
        if selected == row.id then selected = nil end
        Refresh()
    else
        selected = row.id
        Refresh()
    end
end

local function BuildFrame()
    frame = CreateFrame("Frame", "DustBunnyFrame", UIParent)
    frame:SetWidth(340)
    frame:SetHeight(FRAME_H)
    frame:SetPoint(DB.pos.point or "CENTER", UIParent,
                   DB.pos.rel or "CENTER", DB.pos.x or 0, DB.pos.y or 0)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        DB.pos = { point = point, rel = rel, x = x, y = y }
    end)
    frame:Hide()
    frame:SetScript("OnHide", EndHeadless)          -- close/Esc ends a forge session
    -- exclusive with the Blizzard trade-skill window on EVERY tab (field
    -- 2026-09-25, overlap): a session live at open time is someone else's
    -- window — hang it up. The forge's own session never exists while
    -- DustBunny is hidden (OnHide ends it), so this cannot hit our own.
    frame:SetScript("OnShow", function()
        if not headless and GetTradeSkillLine() then CloseTradeSkill() end
    end)
    table.insert(UISpecialFrames, "DustBunnyFrame")  -- Esc closes

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -16)
    title:SetText("DustBunny")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)

    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOP", 0, -34)

    -- tabs: RHS icon tabs in the SpellBook idiom (E2 2026-07-23) —
    -- SpellBookSkillLineTabTemplate verified in this client's FrameXML
    -- (SpellBookFrame.xml:9 — CheckButton, 32x32, the authentic chrome).
    -- Icons resolve from the player's own spellbook (era-proof, no
    -- guessed paths); fallbacks cover unknown professions.
    tabButtons = {}
    for i, tab in ipairs(TABS) do
        local tb
        if tab.craft then
            -- the tab IS the opener: a secure click-cast of the profession
            -- spell (hardware-legal) opens the session; PostClick switches
            -- the tab. PreClick blanks the cast when a session is already
            -- live (unknown whether a re-cast would toggle it — not assumed).
            -- template ORDER matters: the spellbook tab template carries an
            -- inline OnClick (SpellBookSkillLineTab_OnClick — field error
            -- 2026-09-25, SpellBookFrame.lua:571) and a later template
            -- overrides earlier handlers. Secure template LAST so its
            -- OnClick is the one that stands; setting it by hand would
            -- taint the handler and block the cast.
            tb = CreateFrame("CheckButton", "DustBunnyTab" .. i, frame,
                             "SpellBookSkillLineTabTemplate, SecureActionButtonTemplate")
            tb:SetAttribute("type", "macro")
            tb:RegisterForClicks("LeftButtonUp")
            tb:SetScript("PreClick", function(self)
                if InCombatLockdown() then return end
                if GetTradeSkillLine() == tab.skill then
                    self:SetAttribute("macrotext", "")
                else
                    self:SetAttribute("macrotext", "/cast " .. tab.spell)
                end
            end)
            tb:SetScript("PostClick", function()
                headless = true      -- forge owns the NEXT Mining session (no viewer flash)
                SetTab(i)
            end)
        else
            tb = CreateFrame("CheckButton", "DustBunnyTab" .. i, frame,
                             "SpellBookSkillLineTabTemplate")
            tb:SetScript("OnClick", function() SetTab(i) end)
        end
        tb:SetPoint("TOPLEFT", frame, "TOPRIGHT", -13, -44 - (i - 1) * 42)
        local icon = tab.spell and GetSpellTexture(tab.spell)
        if not icon and tab.key == "excluded" then
            icon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
        end
        tb:SetNormalTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        tb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tab.label)
            GameTooltip:Show()
        end)
        tb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        tb:Show()
        tabButtons[i] = tb
    end

    -- list
    scrollFrame = CreateFrame("ScrollFrame", "DustBunnyScroll", frame, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 16, -74)
    scrollFrame:SetPoint("BOTTOMRIGHT", -36, 56)
    scrollFrame:SetScript("OnVerticalScroll", function(self, delta)
        FauxScrollFrame_OnVerticalScroll(self, delta, ROW_H, Refresh)
    end)

    listRows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", "DustBunnyRow" .. i, frame)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 18, -76 - (i - 1) * ROW_H)
        row:SetPoint("RIGHT", scrollFrame, "RIGHT", -4, 0)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", RowClicked)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.selbar = row:CreateTexture(nil, "BACKGROUND")
        row.selbar:SetAllPoints()
        row.selbar:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.selbar:SetVertexColor(0.25, 0.65, 1, 0.85)  -- brighter (field P1)
        row.selbar:Hide()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetWidth(16)
        row.icon:SetHeight(16)
        row.icon:SetPoint("LEFT", 0, 0)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.text:SetJustifyH("LEFT")
        row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.count:SetPoint("RIGHT", -2, 0)
        listRows[i] = row
    end

    -- one secure cast button per castable tab (attributes are per-tab fixed;
    -- only macrotext changes, out of combat, per selection)
    castButtons = {}
    for i, tab in ipairs(TABS) do
        if tab.spell and not tab.craft then
            local cb = CreateFrame("Button", "DustBunnyCast" .. tab.key, frame,
                                   "SecureActionButtonTemplate, UIPanelButtonTemplate")
            cb:SetWidth(140)
            cb:SetHeight(24)
            cb:SetPoint("BOTTOM", 0, 20)
            cb:SetText(tab.label)
            cb:SetAttribute("type", "macro")
            cb:RegisterForClicks("LeftButtonUp")
            -- equip-guard (field row-2 catch 2026-07-23): on GCD the
            -- "/cast" line fails silently and "/use bag slot" falls through
            -- to its OTHER meaning — equipping the item. PreClick runs
            -- before the secure action and may edit attributes out of
            -- combat: disarm this click if the spell can't actually fire.
            cb:SetScript("PreClick", function(self)
                if InCombatLockdown() then return end
                local start, duration = GetSpellCooldown(tab.spell)
                local busy = (start and start > 0 and duration and duration > 0)
                             or UnitCastingInfo("player") ~= nil
                if busy then
                    self:SetAttribute("macrotext", "")
                else
                    UpdateMacro()
                end
            end)
            cb:Hide()
            castButtons[i] = cb
        end
    end

    -- craft-tab controls (1.1.0): [ count ] [Smelt] [Max] in the cast
    -- button's slot; plain buttons — DoTradeSkill is unprotected
    smeltBox = CreateFrame("EditBox", "DustBunnySmeltCount", frame, "InputBoxTemplate")
    smeltBox:SetWidth(48)
    smeltBox:SetHeight(20)
    smeltBox:SetPoint("BOTTOM", -74, 22)
    smeltBox:SetNumeric(true)
    smeltBox:SetMaxLetters(4)
    smeltBox:SetAutoFocus(false)
    smeltBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() SmeltClicked() end)
    smeltBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    smeltBox:Hide()

    smeltBtn = CreateFrame("Button", "DustBunnySmelt", frame, "UIPanelButtonTemplate")
    smeltBtn:SetWidth(90)
    smeltBtn:SetHeight(24)
    smeltBtn:SetPoint("BOTTOM", 10, 20)
    smeltBtn:SetText("Smelt")
    smeltBtn:SetScript("OnClick", SmeltClicked)
    smeltBtn:Hide()

    maxBtn = CreateFrame("Button", "DustBunnySmeltMax", frame, "UIPanelButtonTemplate")
    maxBtn:SetWidth(50)
    maxBtn:SetHeight(24)
    maxBtn:SetPoint("LEFT", smeltBtn, "RIGHT", 4, 0)
    maxBtn:SetText("Max")
    maxBtn:SetScript("OnClick", MaxClicked)
    maxBtn:Hide()

    -- one-click amounts: fill the box and smelt immediately (clamped)
    local stripW = #PRESETS * 40 + (#PRESETS - 1) * 4
    for i, n in ipairs(PRESETS) do
        local b = CreateFrame("Button", "DustBunnyPreset" .. n, frame, "UIPanelButtonTemplate")
        b:SetWidth(40)
        b:SetHeight(20)
        b:SetPoint("BOTTOM", -stripW / 2 + 20 + (i - 1) * 44, 46)
        b:SetText(tostring(n))
        b:SetScript("OnClick", function() PresetClicked(n) end)
        b:Hide()
        presetBtns[i] = b
    end
end

-- ----------------------------------------------------------- launcher --
-- E1 (endorsed 2026-07-23): an action-bar-snappable launcher button, so
-- the burrow opens like any craft skill. Snap machinery ported from
-- SpellClusters v1.0.0 (soak-hardened 07-10→07-14): DIALOG strata beats
-- the bars' toplevel self-raising; hidden main-bar empty slots snap via
-- rect test and parent to the bar's art frame; occupied slots refuse and
-- pop the button clear (6x clearance — 1x overlapped the XP bar).
local LBTN = 34
local launcher

local function LauncherApplySnap(target, targetName)
    launcher:SetParent(target:IsShown() and target or target:GetParent())
    launcher:ClearAllPoints()
    launcher:SetPoint("CENTER", target, "CENTER", 0, 0)
    launcher:SetWidth(target:GetWidth())
    launcher:SetHeight(target:GetHeight())
    launcher:SetFrameStrata("DIALOG")
    launcher:SetFrameLevel(target:GetFrameLevel() + 5)
    launcher.snappedTo = targetName
end

local function LauncherUnsnap()
    launcher:SetParent(UIParent)
    launcher:SetFrameStrata("DIALOG")
    launcher:SetWidth(LBTN)
    launcher:SetHeight(LBTN)
    launcher.snappedTo = nil
end

local function LauncherRestore()
    launcher:ClearAllPoints()
    launcher.snappedTo = nil
    local pos = DB.launcher
    local snapTarget = pos and pos.snapTo and _G[pos.snapTo]
    if snapTarget then
        LauncherApplySnap(snapTarget, pos.snapTo)
    elseif pos then
        LauncherUnsnap()
        launcher:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        LauncherUnsnap()
        launcher:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
    end
end

local function LauncherSave(snapTo)
    if snapTo then
        local cx, cy = launcher:GetCenter()
        DB.launcher = { "CENTER", "BOTTOMLEFT", cx, cy, snapTo = snapTo }
    else
        local p, _, rp, x, y = launcher:GetPoint()
        DB.launcher = { p, rp, x, y }
    end
end

local function SnapTargets()
    local out = {}
    local function add(name, allowHidden)
        local f = _G[name]
        if f and (f:IsVisible() or (allowHidden and f:GetParent()
                                    and f:GetParent():IsVisible())) then
            out[#out + 1] = f
            f.dustBunnyName = name
        end
    end
    for i = 1, 12 do
        add("ActionButton" .. i, true)  -- main bar hides EMPTY slots; rect-snappable
        add("MultiBarBottomLeftButton" .. i)
        add("MultiBarBottomRightButton" .. i)
        add("MultiBarLeftButton" .. i)
        add("MultiBarRightButton" .. i)
    end
    for i = 1, 120 do add("ButtonForge" .. i) end
    return out
end

local function CursorOverRect(f)
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    if not l then return false end
    local s = f:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / s, cy / s
    return cx >= l and cx <= r and cy >= b and cy <= t
end

local function IsOccupied(target)
    if target.action and HasAction(target.action) then
        return true
    end
    -- cross-addon courtesy (field row-4 catch 2026-07-23): a snapped
    -- SpellClusters anchor sits on an EMPTY slot by design — HasAction
    -- says vacant while an anchor wears the chair. Soft-detect, zero
    -- dependency: absent addon = loop never runs.
    if SpellClusters_Data then
        for _, fam in ipairs(SpellClusters_Data) do
            local a = _G["SpellClustersAnchor" .. fam.key]
            if a and a.snappedTo == target.dustBunnyName then
                return true
            end
        end
    end
    if target.action then
        return false   -- Blizzard slot, no action, no anchor: free
    end
    local icon = _G[(target.dustBunnyName or "") .. "Icon"]
    return icon and icon:GetTexture() ~= nil
end

local function LauncherTrySnap()
    local best
    for _, t in ipairs(SnapTargets()) do
        if (t:IsVisible() and t:IsMouseOver())
           or (not t:IsVisible() and CursorOverRect(t)) then
            best = t
            break
        end
    end
    if best then
        if IsOccupied(best) then
            Print("that slot is occupied - popping clear (no shadowing real abilities).")
            return nil, best
        elseif string.match(best.dustBunnyName or "", "^ActionButton") then
            Print("snapped to the MAIN bar: it pages with stances/shift.")
        end
    end
    return best
end

local function BuildLauncher()
    launcher = CreateFrame("Button", "DustBunnyLauncher", UIParent)
    launcher:SetWidth(LBTN)
    launcher:SetHeight(LBTN)
    launcher:SetFrameStrata("DIALOG")
    launcher:SetMovable(true)
    launcher:SetClampedToScreen(true)
    launcher:RegisterForClicks("LeftButtonUp")
    launcher:RegisterForDrag("RightButton")
    launcher:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    local icon = launcher:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints()
    if not icon:SetTexture("Interface\\Icons\\INV_Enchant_DustArcane") then
        icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    launcher:SetScript("OnClick", function() SlashCmdList["DUSTBUNNY"]() end)
    launcher:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("DustBunny", 1, 1, 1)
        GameTooltip:AddLine("Left-click: open the burrow", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-drag: move (drop on a bar slot to snap)", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    launcher:SetScript("OnLeave", function() GameTooltip:Hide() end)
    launcher:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)
    launcher:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local target, collided = LauncherTrySnap()
        if target then
            LauncherApplySnap(target, target.dustBunnyName)
            LauncherSave(target.dustBunnyName)
        else
            local cx, cy = self:GetCenter()
            local sx = cx * self:GetEffectiveScale() / UIParent:GetEffectiveScale()
            local sy = cy * self:GetEffectiveScale() / UIParent:GetEffectiveScale()
            if collided then
                local popDist = (LBTN / 2 + 10) * 6
                if sx > UIParent:GetWidth() * 0.66 then
                    sx = (collided:GetLeft() * collided:GetEffectiveScale()
                          / UIParent:GetEffectiveScale()) - popDist
                else
                    sy = (collided:GetTop() * collided:GetEffectiveScale()
                          / UIParent:GetEffectiveScale()) + popDist
                end
            end
            LauncherUnsnap()
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sx, sy)
            LauncherSave(nil)
        end
    end)
    LauncherRestore()
end

-- ------------------------------------------------------------- events --
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("SKILL_LINES_CHANGED")
ev:RegisterEvent("BAG_UPDATE")
ev:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
ev:RegisterEvent("LOOT_OPENED")
ev:RegisterEvent("LOOT_CLOSED")
ev:RegisterEvent("TRADE_SKILL_SHOW")
ev:RegisterEvent("TRADE_SKILL_UPDATE")
ev:RegisterEvent("TRADE_SKILL_CLOSE")
ev:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == "Blizzard_TradeSkillUI" then
        InstallShowWrapper()   -- UIParent just loaded the viewer: wrap before its first show
    elseif event == "ADDON_LOADED" and arg1 == ADDON then
        DustBunnyDB = DustBunnyDB or {}
        DustBunnyDB.exclusions = DustBunnyDB.exclusions or {}
        DustBunnyDB.pos = DustBunnyDB.pos or {}
        DB = DustBunnyDB
    elseif event == "PLAYER_LOGIN" then
        ScanSkills()
        BuildFrame()
        BuildLauncher()
        InstallShowWrapper()
        Print("loaded. /dustbunny (or /db) opens the burrow; the launcher button snaps to bars.")
    elseif event == "SKILL_LINES_CHANGED" then
        ScanSkills()
        -- newly learned professions bring their tab icons with them
        if tabButtons then
            for i, tab in ipairs(TABS) do
                if tab.spell then
                    tabButtons[i]:SetNormalTexture(GetSpellTexture(tab.spell)
                        or "Interface\\Icons\\INV_Misc_QuestionMark")
                end
            end
        end
        if frame and frame:IsShown() then Refresh() end
    elseif event == "BAG_UPDATE" then
        if frame and frame:IsShown() then
            rescanQueued = true   -- coalesce bursts to one refresh per frame
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if arg1 == "player" and (arg2 == "Disenchant" or arg2 == "Milling"
                                 or arg2 == "Prospecting") then
            lootPending = true
        elseif arg1 == "player" then
            CraftSucceeded(arg2)
        end
    elseif event == "LOOT_OPENED" then
        if lootPending then
            for i = GetNumLootItems(), 1, -1 do
                LootSlot(i)
                ConfirmLootSlot(i)
            end
        end
    elseif event == "LOOT_CLOSED" then
        lootPending = false
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE"
        or event == "TRADE_SKILL_CLOSE" then
        if event == "TRADE_SKILL_SHOW" and frame and frame:IsShown()
           and not TABS[activeTab].craft then
            -- exclusive on every tab: a profession window opened — yield
            Print("yields to " .. tostring(GetTradeSkillLine()) .. ".")
            frame:Hide()
            return
        end
        if frame and frame:IsShown() and TABS[activeTab].craft then
            InstallShowWrapper()   -- Blizzard_TradeSkillUI may have loaded just now
            if event == "TRADE_SKILL_SHOW" then
                if GetTradeSkillLine() == TABS[activeTab].skill then
                    headless = true
                    SuppressTradeSkillFrame()
                else
                    -- another profession took the (single) session: the
                    -- forge yields — DustBunny closes, THEIR window stands
                    headless = false
                    Print("forge yields to " .. tostring(GetTradeSkillLine()) .. ".")
                    frame:Hide()
                    return
                end
            elseif event == "TRADE_SKILL_CLOSE" then
                headless = false
            end
            rescanQueued = true
        end
    end
end)

ev:SetScript("OnUpdate", function()
    if rescanQueued then
        rescanQueued = false
        Refresh()
    end
end)

-- -------------------------------------------------------------- slash --
SLASH_DUSTBUNNY1 = "/dustbunny"
SLASH_DUSTBUNNY2 = "/db"
SlashCmdList["DUSTBUNNY"] = function()
    if not frame then return end
    if frame:IsShown() then
        frame:Hide()
    else
        ScanSkills()
        frame:Show()
        Refresh()
    end
end
