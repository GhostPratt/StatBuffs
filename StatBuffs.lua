-- StatBuffs: live window of the cumulative stat bonuses on the player's character.
-- WoW 3.3.5a (Interface 30300).
--
-- "Bonus" is everything above the character's naked base value (buffs, gear, enchants,
-- consumables are all treated the same). Only stats with a nonzero bonus are listed.

local ADDON_NAME = "StatBuffs"
local FRAME_W, MIN_H, MAX_H = 270, 60, 340
local TOP_PAD, BOTTOM_PAD = 34, 8          -- space above/below the scroll area
local ROW_H, HEADER_H = 13, 17
local COL_NAME, COL_BONUS, COL_TOTAL = 4, 140, 190
local COL_W = 48
local CONTENT_W = FRAME_W - 30

local GREEN, RED, GRAY, GOLD, WHITE = "|cff33ff33", "|cffff4040", "|cff9d9d9d", "|cffffd100", "|cffffffff"

-- Combat rating indices (FrameXML/PaperDollFrame.lua on 3.3.5; fall back to the known values).
local CR_DEFENSE_SKILL    = CR_DEFENSE_SKILL    or 2
local CR_DODGE            = CR_DODGE            or 3
local CR_PARRY            = CR_PARRY            or 4
local CR_BLOCK            = CR_BLOCK            or 5
local CR_HIT_MELEE        = CR_HIT_MELEE        or 6
local CR_HIT_RANGED       = CR_HIT_RANGED       or 7
local CR_HIT_SPELL        = CR_HIT_SPELL        or 8
local CR_CRIT_MELEE       = CR_CRIT_MELEE       or 9
local CR_CRIT_RANGED      = CR_CRIT_RANGED      or 10
local CR_CRIT_SPELL       = CR_CRIT_SPELL       or 11
local CR_CRIT_TAKEN_MELEE = CR_CRIT_TAKEN_MELEE or 15  -- resilience
local CR_HASTE_MELEE      = CR_HASTE_MELEE      or 18
local CR_HASTE_RANGED     = CR_HASTE_RANGED     or 19
local CR_HASTE_SPELL      = CR_HASTE_SPELL      or 20
local CR_EXPERTISE        = CR_EXPERTISE        or 24
local CR_ARMOR_PENETRATION = CR_ARMOR_PENETRATION or 25

local STAT_NAMES = {
    SPELL_STAT1_NAME or "Strength",
    SPELL_STAT2_NAME or "Agility",
    SPELL_STAT3_NAME or "Stamina",
    SPELL_STAT4_NAME or "Intellect",
    SPELL_STAT5_NAME or "Spirit",
}
-- Spell schools as used by GetSpellBonusDamage / UnitResistance (1 = physical).
local SCHOOL_NAMES = {
    [2] = DAMAGE_SCHOOL2 or "Holy",
    [3] = DAMAGE_SCHOOL3 or "Fire",
    [4] = DAMAGE_SCHOOL4 or "Nature",
    [5] = DAMAGE_SCHOOL5 or "Frost",
    [6] = DAMAGE_SCHOOL6 or "Shadow",
    [7] = DAMAGE_SCHOOL7 or "Arcane",
}

---------------------------------------------------------------------------
-- Frame construction
---------------------------------------------------------------------------
local frame = CreateFrame("Frame", "StatBuffsFrame", UIParent)
frame:SetWidth(FRAME_W)
frame:SetHeight(MAX_H)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
frame:SetFrameStrata("HIGH")   -- above the normal UI, below dialogs and the game menu
frame:SetToplevel(true)
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
frame:SetBackdropColor(0.05, 0.05, 0.08, 0.9)
frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
frame:Hide()
-- Deliberately NOT added to UISpecialFrames: Escape opens the game menu as usual and the
-- window stays up until the player closes it with the X button or /sb.

local function SavePosition()
    StatBuffsDB = StatBuffsDB or {}
    local point, _, relPoint, x, y = frame:GetPoint()
    StatBuffsDB.point, StatBuffsDB.relPoint, StatBuffsDB.x, StatBuffsDB.y = point, relPoint, x, y
end

local function RestoreSettings()
    StatBuffsDB = StatBuffsDB or {}
    if StatBuffsDB.point then
        frame:ClearAllPoints()
        frame:SetPoint(StatBuffsDB.point, UIParent, StatBuffsDB.relPoint, StatBuffsDB.x, StatBuffsDB.y)
    end
    frame:SetScale(StatBuffsDB.scale or 1)
    if StatBuffsDB.shown then
        frame:Show()   -- was open when the player last logged out or reloaded
    end
end

frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)

-- Title line
local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -6)
title:SetText("Stat Buffs")

local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeBtn:SetWidth(20)
closeBtn:SetHeight(20)
closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

-- Column headers
local function MakeHeaderText(text, x, justify, width)
    local fs = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 8 + x, -20)
    fs:SetWidth(width)
    fs:SetJustifyH(justify)
    fs:SetText(GRAY .. text .. "|r")
    return fs
end
MakeHeaderText("Stat", COL_NAME + 6, "LEFT", 120)
MakeHeaderText("Bonus", COL_BONUS, "RIGHT", COL_W)
MakeHeaderText("Total", COL_TOTAL, "RIGHT", COL_W)

-- Scrollable content
local scroll = CreateFrame("ScrollFrame", "StatBuffsScrollFrame", frame, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -TOP_PAD)
scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -22, BOTTOM_PAD)
local scrollBar = StatBuffsScrollFrameScrollBar

local content = CreateFrame("Frame", nil, scroll)
content:SetWidth(CONTENT_W)
content:SetHeight(1)
scroll:SetScrollChild(content)

-- Shrink the window to fit its content, up to MAX_H; show the scrollbar only when needed.
local function FitToContent(contentHeight)
    local wanted = contentHeight + TOP_PAD + BOTTOM_PAD
    if wanted < MIN_H then wanted = MIN_H end
    if wanted > MAX_H then
        frame:SetHeight(MAX_H)
        scrollBar:Show()
    else
        frame:SetHeight(wanted)
        scrollBar:Hide()
        scroll:SetVerticalScroll(0)
    end
end

---------------------------------------------------------------------------
-- Row pools and layout helpers
---------------------------------------------------------------------------
local textRows, iconRows = {}, {}
local usedText, usedIcons = 0, 0
local cursorY = 0
local pendingHeader = nil   -- section title emitted lazily, only if the section gets a row
local rowsShown = 0

local function AcquireText()
    usedText = usedText + 1
    local fs = textRows[usedText]
    if not fs then
        fs = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        textRows[usedText] = fs
    end
    fs:ClearAllPoints()
    fs:Show()
    return fs
end

local function AcquireIcon()
    usedIcons = usedIcons + 1
    local tex = iconRows[usedIcons]
    if not tex then
        tex = content:CreateTexture(nil, "ARTWORK")
        tex:SetWidth(12)
        tex:SetHeight(12)
        tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        iconRows[usedIcons] = tex
    end
    tex:ClearAllPoints()
    tex:Show()
    return tex
end

local function BeginLayout()
    usedText, usedIcons, cursorY, rowsShown = 0, 0, -4, 0
    pendingHeader = nil
end

local function EndLayout()
    for i = usedText + 1, #textRows do textRows[i]:Hide() end
    for i = usedIcons + 1, #iconRows do iconRows[i]:Hide() end
    local h = -cursorY + 4
    content:SetHeight(h)
    FitToContent(h)
end

local function EmitHeader(text)
    cursorY = cursorY - 3
    local fs = AcquireText()
    fs:SetFontObject(GameFontNormalSmall)
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", COL_NAME, cursorY)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWidth(CONTENT_W - COL_NAME)
    fs:SetHeight(HEADER_H)
    fs:SetText(GOLD .. text .. "|r")
    cursorY = cursorY - HEADER_H
end

local function Cell(text, x, justify, width)
    local fs = AcquireText()
    fs:SetFontObject(GameFontHighlightSmall)
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", x, cursorY)
    fs:SetJustifyH(justify)
    fs:SetJustifyV("TOP")
    fs:SetWidth(width or COL_W)
    fs:SetHeight(ROW_H)   -- one line only; stops a long label spilling into the next row
    fs:SetText(text)
    return fs
end

local function FormatNumber(v, isPercent)
    if isPercent then return string.format("%.2f%%", v) end
    return string.format("%d", math.floor(v + 0.5))
end

local function FormatBonus(delta, isPercent)
    if delta > 0.005 then
        return GREEN .. "+" .. FormatNumber(delta, isPercent) .. "|r"
    elseif delta < -0.005 then
        return RED .. FormatNumber(delta, isPercent) .. "|r"
    end
    return GRAY .. "0|r"
end

-- Draws one collected stat row (see Collect below).
local function DrawRow(item)
    if pendingHeader then
        EmitHeader(pendingHeader)
        pendingHeader = nil
    end
    Cell(WHITE .. item.label .. "|r", COL_NAME + 6, "LEFT", COL_BONUS - COL_NAME - 10)
    Cell(FormatBonus(item.bonus), COL_BONUS, "RIGHT")
    if item.total then
        Cell(WHITE .. FormatNumber(item.total, item.percent) .. "|r", COL_TOTAL, "RIGHT")
    else
        Cell(GRAY .. "-|r", COL_TOTAL, "RIGHT")
    end
    cursorY = cursorY - ROW_H
    rowsShown = rowsShown + 1
end

local function FormatTime(seconds)
    if seconds >= 3600 then return string.format("%dh", math.floor(seconds / 3600 + 0.5)) end
    if seconds >= 60 then return string.format("%dm", math.floor(seconds / 60 + 0.5)) end
    return string.format("%ds", math.floor(seconds + 0.5))
end

---------------------------------------------------------------------------
-- Data gathering
---------------------------------------------------------------------------
local function MaxSchool(fn)
    local best = 0
    for school = 2, 7 do
        local v = fn(school) or 0
        if v > best then best = v end
    end
    return best
end

-- Gathers everything the window shows, independent of the UI.
-- Returns a list of {kind="section", text} / {kind="row", label, bonus, total, percent}
-- entries (rows only for nonzero bonuses) and a list of active buffs.
local function Collect()
    local items = {}

    local function Section(text)
        items[#items + 1] = { kind = "section", text = text }
    end

    -- Adds a row only when the bonus is nonzero. `total` may be nil.
    local function Row(label, bonus, total, totalIsPercent)
        if not bonus or math.abs(bonus) < 0.005 then return end
        items[#items + 1] = { kind = "row", label = label, bonus = bonus, total = total, percent = totalIsPercent }
    end

    -- Stats the client only exposes as a combat rating: the rating is the bonus
    -- (ratings come solely from gear and buffs) and the resulting percent is the total.
    local function RatingRow(label, ratingId, totalPercent)
        local rating = GetCombatRating(ratingId) or 0
        if totalPercent == nil then totalPercent = GetCombatRatingBonus(ratingId) or 0 end
        Row(label, rating, totalPercent, true)
    end

    -- Attributes ---------------------------------------------------------
    Section("Attributes")
    for i = 1, 5 do
        local _, effective, pos, neg = UnitStat("player", i)
        if effective then
            Row(STAT_NAMES[i], pos + neg, effective)
        end
    end

    -- Melee / ranged ----------------------------------------------------
    Section("Attack")
    local apBase, apPos, apNeg = UnitAttackPower("player")
    Row("Melee attack power", apPos + apNeg, apBase + apPos + apNeg)
    local rapBase, rapPos, rapNeg = UnitRangedAttackPower("player")
    Row("Ranged attack power", rapPos + rapNeg, rapBase + rapPos + rapNeg)
    RatingRow("Melee crit rating", CR_CRIT_MELEE, GetCritChance() or 0)
    RatingRow("Ranged crit rating", CR_CRIT_RANGED, GetRangedCritChance() or 0)
    RatingRow("Melee hit rating", CR_HIT_MELEE)
    RatingRow("Ranged hit rating", CR_HIT_RANGED)
    RatingRow("Melee haste rating", CR_HASTE_MELEE)
    RatingRow("Ranged haste rating", CR_HASTE_RANGED)
    RatingRow("Expertise rating", CR_EXPERTISE)
    RatingRow("Armor pen. rating", CR_ARMOR_PENETRATION)

    -- Spell -------------------------------------------------------------
    Section("Spell")
    for school = 2, 7 do
        local dmg = GetSpellBonusDamage(school) or 0
        Row(SCHOOL_NAMES[school] .. " spell damage", dmg, dmg)
    end
    local healing = GetSpellBonusHealing() or 0
    Row("Bonus healing", healing, healing)
    RatingRow("Spell crit rating", CR_CRIT_SPELL, MaxSchool(GetSpellCritChance))
    RatingRow("Spell hit rating", CR_HIT_SPELL)
    RatingRow("Spell haste rating", CR_HASTE_SPELL)
    local spellPen = GetSpellPenetration and GetSpellPenetration() or 0
    Row("Spell penetration", spellPen, spellPen)

    -- Defense -----------------------------------------------------------
    Section("Defense")
    local _, armorEffective, _, armorPos, armorNeg = UnitArmor("player")
    Row("Armor", armorPos + armorNeg, armorEffective)
    local defBase, defMod = UnitDefense("player")
    Row("Defense", defMod, defBase + defMod)
    RatingRow("Dodge rating", CR_DODGE, GetDodgeChance() or 0)
    RatingRow("Parry rating", CR_PARRY, GetParryChance() or 0)
    RatingRow("Block rating", CR_BLOCK, GetBlockChance() or 0)
    RatingRow("Resilience", CR_CRIT_TAKEN_MELEE)

    -- Resistances -------------------------------------------------------
    Section("Resistances")
    for school = 2, 6 do
        local _, total, pos, neg = UnitResistance("player", school)
        if total then
            Row(SCHOOL_NAMES[school] .. " resistance", pos + neg, total)
        end
    end

    -- Active buffs ------------------------------------------------------
    local buffs = {}
    for i = 1, 40 do
        local name, _, icon, count, _, _, expires = UnitBuff("player", i)
        if not name then break end
        buffs[#buffs + 1] = { name = name, icon = icon, count = count or 0, expires = expires or 0 }
    end

    return items, buffs
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------
local function Refresh()
    if not frame:IsShown() then return end
    local items, buffs = Collect()
    BeginLayout()

    for _, item in ipairs(items) do
        if item.kind == "section" then
            pendingHeader = item.text   -- drawn lazily, only if a row follows
        else
            DrawRow(item)
        end
    end
    pendingHeader = nil
    if rowsShown == 0 then
        EmitHeader("No stat bonuses active")
    end

    EmitHeader(string.format("Active buffs (%d)", #buffs))
    if #buffs == 0 then
        Cell(GRAY .. "None|r", COL_NAME + 6, "LEFT", 200)
        cursorY = cursorY - ROW_H
    end
    local now = GetTime()
    for _, buff in ipairs(buffs) do
        local tex = AcquireIcon()
        tex:SetTexture(buff.icon)
        tex:SetPoint("TOPLEFT", content, "TOPLEFT", COL_NAME + 4, cursorY)

        local label = buff.name
        if buff.count > 1 then label = label .. GRAY .. " x" .. buff.count .. "|r" end
        Cell(WHITE .. label .. "|r", COL_NAME + 20, "LEFT", COL_TOTAL - COL_NAME - 24)

        local timeText
        if buff.expires > 0 then
            timeText = FormatTime(math.max(0, buff.expires - now))
        else
            timeText = GRAY .. "--|r"
        end
        Cell(timeText, COL_TOTAL, "RIGHT")
        cursorY = cursorY - ROW_H
    end

    EndLayout()
end

---------------------------------------------------------------------------
-- Export to chat
---------------------------------------------------------------------------
local MAX_CHAT_LEN = 240   -- chat messages are capped at 255 bytes

-- Builds plain-text lines (no colour codes: those are not allowed in sent chat).
local function BuildExportLines()
    local items, buffs = Collect()
    local lines = {}

    -- Joins parts with ", " after a prefix, splitting into more lines when too long.
    local function PushGroup(prefix, parts)
        if not prefix or #parts == 0 then return end
        local line = prefix .. ": "
        for i, part in ipairs(parts) do
            local piece = (i == 1 and "" or ", ") .. part
            if #line + #piece > MAX_CHAT_LEN then
                lines[#lines + 1] = line
                line = prefix .. " (cont.): " .. part
            else
                line = line .. piece
            end
        end
        lines[#lines + 1] = line
    end

    lines[1] = string.format("Stat bonuses for %s (level %d %s):",
        UnitName("player") or "?", UnitLevel("player") or 0, UnitClass("player") or "")

    local section, parts = nil, {}
    local rowCount = 0
    for _, item in ipairs(items) do
        if item.kind == "section" then
            PushGroup(section, parts)
            section, parts = item.text, {}
        else
            rowCount = rowCount + 1
            local bonus = (item.bonus > 0 and "+" or "") .. FormatNumber(item.bonus)
            local total = item.total and (" (" .. FormatNumber(item.total, item.percent) .. ")") or ""
            parts[#parts + 1] = item.label .. " " .. bonus .. total
        end
    end
    PushGroup(section, parts)
    if rowCount == 0 then lines[#lines + 1] = "No stat bonuses active." end

    local buffParts = {}
    for _, buff in ipairs(buffs) do
        buffParts[#buffParts + 1] = buff.name .. (buff.count > 1 and (" x" .. buff.count) or "")
    end
    if #buffParts > 0 then
        PushGroup(string.format("Buffs (%d)", #buffParts), buffParts)
    else
        lines[#lines + 1] = "Buffs: none"
    end
    return lines
end

-- dest: "LOCAL" (your own chat window) or a SendChatMessage chat type.
-- target: whisper recipient or channel number, when dest needs one.
local function ExportToChat(dest, target)
    local lines = BuildExportLines()
    for i, line in ipairs(lines) do
        if dest == "LOCAL" then
            DEFAULT_CHAT_FRAME:AddMessage((i == 1 and GOLD or WHITE) .. line .. "|r")
        else
            SendChatMessage(line, dest, nil, target)
        end
    end
end

local CHAT_TYPES = {
    say = "SAY", yell = "YELL", party = "PARTY", p = "PARTY", raid = "RAID", r = "RAID",
    guild = "GUILD", g = "GUILD", officer = "OFFICER", o = "OFFICER",
    bg = "BATTLEGROUND", battleground = "BATTLEGROUND",
}

-- "Chat" button on the window, opening a destination menu.
local exportBtn = CreateFrame("Button", "StatBuffsExportButton", frame, "UIPanelButtonTemplate")
exportBtn:SetWidth(38)
exportBtn:SetHeight(16)
exportBtn:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", 3, -2)
exportBtn:SetText("Chat")
local exportBtnText = exportBtn:GetFontString()
if exportBtnText then exportBtnText:SetFontObject(GameFontNormalSmall) end

local exportMenuFrame = CreateFrame("Frame", "StatBuffsExportMenu", UIParent, "UIDropDownMenuTemplate")
local exportMenu = {
    { text = "Export stats to...", isTitle = true, notCheckable = true },
    { text = "My chat window only", notCheckable = true, func = function() ExportToChat("LOCAL") end },
    { text = "Say",     notCheckable = true, func = function() ExportToChat("SAY") end },
    { text = "Party",   notCheckable = true, func = function() ExportToChat("PARTY") end },
    { text = "Raid",    notCheckable = true, func = function() ExportToChat("RAID") end },
    { text = "Guild",   notCheckable = true, func = function() ExportToChat("GUILD") end },
    { text = "Officer", notCheckable = true, func = function() ExportToChat("OFFICER") end },
}
exportBtn:SetScript("OnClick", function(self)
    EasyMenu(exportMenu, exportMenuFrame, self, 0, 0, "MENU")
end)

---------------------------------------------------------------------------
-- Events and throttled updates
---------------------------------------------------------------------------
local dirty = false
local elapsedSinceTick = 0
local UNIT_EVENTS = {
    UNIT_STATS = true, UNIT_AURA = true, UNIT_ATTACK_POWER = true, UNIT_RANGED_ATTACK_POWER = true,
    UNIT_RESISTANCES = true, UNIT_DEFENSE = true, UNIT_MAXHEALTH = true, UNIT_MAXMANA = true,
    UNIT_LEVEL = true, UNIT_INVENTORY_CHANGED = true, UNIT_ATTACK_SPEED = true, UNIT_DISPLAYPOWER = true,
}
local GLOBAL_EVENTS = {
    "PLAYER_ENTERING_WORLD", "COMBAT_RATING_UPDATE", "PLAYER_DAMAGE_DONE_MODS",
    "PLAYER_EQUIPMENT_CHANGED", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "SPELL_POWER_CHANGED",
}

frame:SetScript("OnEvent", function(self, event, unit)
    if event == "ADDON_LOADED" then
        if unit == ADDON_NAME then
            RestoreSettings()
            self:UnregisterEvent("ADDON_LOADED")
        end
        return
    end
    if UNIT_EVENTS[event] and unit ~= "player" then return end
    dirty = true
end)

frame:SetScript("OnUpdate", function(self, elapsed)
    elapsedSinceTick = elapsedSinceTick + elapsed
    -- Event-driven refresh, throttled to 10/s; plus a 1s tick so buff timers count down.
    if (dirty and elapsedSinceTick >= 0.1) or elapsedSinceTick >= 1 then
        dirty = false
        elapsedSinceTick = 0
        Refresh()
    end
end)

frame:SetScript("OnShow", function()
    if StatBuffsDB then StatBuffsDB.shown = true end
    dirty = false
    elapsedSinceTick = 0
    Refresh()
end)

frame:SetScript("OnHide", function()
    if StatBuffsDB then StatBuffsDB.shown = false end
end)

frame:RegisterEvent("ADDON_LOADED")
-- pcall so an event name this client build doesn't know can't abort the load.
for ev in pairs(UNIT_EVENTS) do pcall(frame.RegisterEvent, frame, ev) end
for _, ev in ipairs(GLOBAL_EVENTS) do pcall(frame.RegisterEvent, frame, ev) end

---------------------------------------------------------------------------
-- Slash command / keybinding
---------------------------------------------------------------------------
function StatBuffs_Toggle()
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

SLASH_STATBUFFS1 = "/statbuffs"
SLASH_STATBUFFS2 = "/sb"
SlashCmdList["STATBUFFS"] = function(msg)
    msg = (msg or ""):lower()
    StatBuffsDB = StatBuffsDB or {}
    local scaleArg = msg:match("^scale%s+([%d%.]+)$")
    local exportDest, exportTarget = msg:match("^export%s*(%S*)%s*(.-)%s*$")
    if exportDest then
        if exportDest == "" or exportDest == "local" or exportDest == "me" then
            ExportToChat("LOCAL")
        elseif CHAT_TYPES[exportDest] then
            ExportToChat(CHAT_TYPES[exportDest])
        elseif (exportDest == "whisper" or exportDest == "w") and exportTarget ~= "" then
            ExportToChat("WHISPER", exportTarget)
        elseif tonumber(exportDest) then
            ExportToChat("CHANNEL", tonumber(exportDest))
        else
            DEFAULT_CHAT_FRAME:AddMessage(GOLD .. "StatBuffs|r: /sb export [say|party|raid|guild|officer|bg|whisper <name>|<channel number>]")
        end
    elseif msg == "reset" then
        StatBuffsDB.point = nil
        StatBuffsDB.scale = nil
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        frame:SetScale(1)
        frame:Show()
    elseif scaleArg then
        local scale = tonumber(scaleArg)
        if scale and scale >= 0.5 and scale <= 2 then
            StatBuffsDB.scale = scale
            frame:SetScale(scale)
            frame:Show()
        else
            DEFAULT_CHAT_FRAME:AddMessage(GOLD .. "StatBuffs|r: scale must be between 0.5 and 2, e.g. /sb scale 0.8")
        end
    else
        StatBuffs_Toggle()
    end
end

BINDING_HEADER_STATBUFFS = "StatBuffs"
BINDING_NAME_STATBUFFS_TOGGLE = "Toggle Stat Buffs window"

DEFAULT_CHAT_FRAME:AddMessage(GOLD .. "StatBuffs|r loaded. Type " .. WHITE .. "/sb|r to open the window.")
