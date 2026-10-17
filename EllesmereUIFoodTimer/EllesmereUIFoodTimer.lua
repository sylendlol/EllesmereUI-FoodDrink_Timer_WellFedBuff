if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIFoodTimer.lua
--  Dworak > Food Timer: how long you still sit and eat / drink.
--
--    [icon] Food            18.4s   HP 72%     (bar drains with the buff)
--    [icon] Drink           22.0s   Full       (Full color: stand up)
--
--  Matched by the buff's NAME, never by spell ID: every food has its own
--  spell (433, 434, 435, 1127, 1129 ...) but the buff is always called
--  "Food" / "Drink" / "Food & Drink" / "Refreshment". The names come from
--  the client (C_Spell.GetSpellName of the basic food / drink spells), so a
--  non-English client works too; the English names are a fallback.
--
--  Its own addon: registers its row in the "Dworak" section through
--  EllesmereUIDworak. No EllesmereUI file is changed.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local DW = EllesmereUIDworak
if not DW then return end -- the Dworak core is off: nothing to register into

ns.FOLDER = ADDON_NAME

local FT_DEFAULTS = {
    profile = {
        ftEnabled    = true,
        ftDrink      = true,        -- Drink buffs too (not only Food)
        ftResource   = true,        -- HP % (food) / mana % (drink) on the bar
        ftFullHL     = true,        -- Full color + "Full" when topped up
        ftFullR = 0.30, ftFullG = 0.85, ftFullB = 0.35,
        ftWidth      = 200,
        ftHeight     = 20,
        ftShowIcon   = true,
        ftShowName   = true,
        ftBarColor   = "accent",    -- "accent" = UI Accent Color, "custom" = ftBarR/G/B
        ftBarR = 0.90, ftBarG = 0.65, ftBarB = 0.20,         -- Food bar (custom)
        ftDrinkColor = "custom",    -- Drink bar: "accent" | "custom" (ftDrinkR/G/B)
        ftDrinkR = 0.25, ftDrinkG = 0.55, ftDrinkB = 0.95,
        ftFed        = true,        -- Well Fed buff bar
        ftFedColor   = "custom",    -- "accent" | "custom" (ftFedR/G/B)
        ftFedR = 0.80, ftFedG = 0.45, ftFedB = 0.20,         -- Well Fed icon border
        ftFedSize     = 36,         -- Well Fed icon size
        ftFedBorder   = 1,          -- Well Fed icon border, px (0 = none)
        ftFedSwipe    = true,       -- cooldown-style swipe on the icon
        ftFedTextSize = 12,         -- Well Fed timer text
        ftFedTimerR = 1, ftFedTimerG = 1, ftFedTimerB = 1,   -- Well Fed timer color
        ftFedMissing  = false,      -- no Well Fed: keep the icon, greyed out
        -- ftFedPosition (point, relPoint, x, y): set by Unlock Mode
        ftTextR = 1, ftTextG = 1, ftTextB = 1,               -- name / time / percent
        ftBgR = 0.05, ftBgG = 0.05, ftBgB = 0.05, ftBgA = 0.6,
        ftFont       = "__global",
        ftTextSize   = 12,
        ftGrow       = "down",      -- second bar below ("down") or above ("up")
        ftDecimals   = true,        -- 9.4s under 10 seconds
        -- ftPosition (point, relPoint, x, y): set by Unlock Mode
    },
}
local DEFAULTS = FT_DEFAULTS.profile

local SV_NAME = "EllesmereUIFoodTimerDB"
local db = EllesmereUI.Lite.NewDB(SV_NAME, FT_DEFAULTS)

local function DB()
    local active = (EllesmereUIDB and EllesmereUIDB.activeProfile) or "Default"
    if db._profileName ~= active then
        db = EllesmereUI.Lite.NewDB(SV_NAME, FT_DEFAULTS)
    end
    return db.profile
end

local function Get(key)
    local v = DB()[key]
    if v == nil then return DEFAULTS[key] end
    return v
end

local function Set(key, value)
    DB()[key] = value
end

local function Plain(v)
    return not (issecretvalue and issecretvalue(v))
end

local function Num(v)
    if Plain(v) and type(v) == "number" then return v end
end

local function Accent()
    local c = EllesmereUI.ELLESMERE_GREEN
    if c and c.r then return c.r, c.g, c.b end
    return 0.05, 0.82, 0.62
end

local function AccentHex()
    local r, g, b = Accent()
    return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

local function Say(text)
    EllesmereUI.Print(AccentHex() .. "Food Timer:|r " .. text)
end

local UNLOCK_KEY  = "EUI_DworakFoodTimer"
local DEFAULT_POS = { point = "CENTER", relPoint = "CENTER", x = 0, y = -180 }
local PAGE        = "Food Timer"
local WHITE       = "Interface\\Buttons\\WHITE8x8"
local ICON_FOOD   = "Interface\\Icons\\INV_Misc_Fork&Knife"
local ICON_DRINK  = "Interface\\Icons\\INV_Drink_07"
local ICON_FED    = "Interface\\Icons\\Spell_Misc_Food"
local MAX_BARS    = 3
local FED_KEY     = "EUI_DworakWellFed"
local DEFAULT_FED_POS = { point = "CENTER", relPoint = "CENTER", x = 150, y = -180 }
local GAP         = 2

-------------------------------------------------------------------------------
--  Buff names -> kind ("food" | "drink" | "both")
-------------------------------------------------------------------------------
local NAMES -- built on first use (spell names may need the client warmed up)

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok and type(n) == "string" and n ~= "" then return n end
    end
    if GetSpellInfo then
        local ok, n = pcall(GetSpellInfo, id)
        if ok and type(n) == "string" and n ~= "" then return n end
    end
end

local function BuildNames()
    NAMES = {}
    local function add(name, kind) if name and not NAMES[name] then NAMES[name] = kind end end
    -- Client-localized: basic Food (433) / Drink (430) buffs.
    add(SpellName(433), "food")
    add(SpellName(430), "drink")
    -- English fallbacks + the combined buffs (conjured / feast style).
    add("Food", "food")
    add("Drink", "drink")
    add("Food & Drink", "both")
    add("Refreshment", "both")
    -- Well Fed (the buff after eating buff food): localized + English.
    add(SpellName(19705), "fed")
    add("Well Fed", "fed")
end

local function KindOf(name)
    if not NAMES then BuildNames() end
    return NAMES[name]
end

-------------------------------------------------------------------------------
--  Scan: the player's eating / drinking buffs
-------------------------------------------------------------------------------
local list = {} -- { name, icon, kind, duration, expires }
local pending = false -- a matching buff had no usable timing yet (retry soon)
local fedEntry        -- the Well Fed buff (its own icon, not a bar)
local fedSecret       -- in combat: { icon, inst } of a Well Fed whose data is SECRET
local lastFed         -- the last READABLE Well Fed (kept through combat)

local function AddEntry(name, icon, duration, expires)
    if not (name and Plain(name)) then return end
    local kind = KindOf(name)
    if not kind then return end
    if kind == "drink" and not Get("ftDrink") then return end
    if kind == "fed" and not Get("ftFed") then return end
    duration, expires = Num(duration), Num(expires)
    if not (duration and duration > 0 and expires and expires > 0) then
        -- The buff can land before its timing is filled in (and no second
        -- UNIT_AURA follows): remember it and look again shortly.
        pending = true
        return
    end
    if kind ~= "fed" and #list >= MAX_BARS then return end
    local e = {
        name = name, kind = kind, duration = duration, expires = expires,
        icon = Plain(icon) and icon or (kind == "drink" and ICON_DRINK or kind == "fed" and ICON_FED or ICON_FOOD),
    }
    if kind == "fed" then
        fedEntry = e
    else
        list[#list + 1] = e
    end
end

local function Scan()
    for i = #list, 1, -1 do list[i] = nil end
    pending = false
    fedEntry = nil
    fedSecret = nil
    for i = 1, 40 do
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or not a then break end
            if Plain(a) then AddEntry(a.name, a.icon, a.duration, a.expirationTime) end
        elseif UnitAura then
            local ok, n, icon, _, _, dur, exp = pcall(UnitAura, "player", i, "HELPFUL")
            if not ok or not n then break end
            AddEntry(n, icon, dur, exp)
        else
            break
        end
    end
    -- In combat the aura fields are SECRET, so the name match above sees no
    -- Well Fed. Ask the client by name instead (it compares engine-side);
    -- the result is only handed to widget setters, never compared here.
    if not fedEntry and Get("ftFed") ~= false and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        if not NAMES then BuildNames() end
        for n, k in pairs(NAMES) do
            if k == "fed" then
                local ok, a = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", n, "HELPFUL")
                if ok and type(a) == "table" then
                    local okF, sec = pcall(function()
                        return { icon = a.icon, inst = a.auraInstanceID, aura = a }
                    end)
                    if okF then fedSecret = sec; break end
                end
            end
        end
    end
    -- Buff food can't be eaten in combat, so a Well Fed read before combat is
    -- still the same buff: keep its readable timer instead of the secret one.
    if fedEntry then
        lastFed = fedEntry
    elseif fedSecret and lastFed and lastFed.expires > GetTime() then
        fedEntry, fedSecret = lastFed, nil
    elseif not fedSecret then
        lastFed = nil
    end
    -- Food first, then drink, then combined
    local rank = { food = 1, drink = 2, both = 3 }
    table.sort(list, function(a, b) return rank[a.kind] < rank[b.kind] end)
    return list
end

-- Health % for food, mana % for drink, both for a combined buff.
local function Pct(cur, max)
    cur, max = Num(cur), Num(max)
    if not (cur and max and max > 0) then return nil end
    return cur / max
end

local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local SCALE100 = CurveConstants and CurveConstants.ScaleTo100

-- Secret-safe percents (0-100 with ScaleTo100): may be SECRET numbers,
-- which a FontString can still print but Lua can never compare.
local function HealthPctSecret()
    if not UnitHealthPercent then return nil end
    if SCALE100 then
        local ok, v = pcall(UnitHealthPercent, "player", false, SCALE100)
        if ok and type(v) == "number" then return v, true end
    end
    local ok, v = pcall(UnitHealthPercent, "player")
    if ok and type(v) == "number" then return v, false end
end

local function ManaPctSecret()
    if not UnitPowerPercent then return nil end
    if SCALE100 then
        local ok, v = pcall(UnitPowerPercent, "player", MANA, false, SCALE100)
        if ok and type(v) == "number" then return v, true end
    end
    local ok, v = pcall(UnitPowerPercent, "player", MANA)
    if ok and type(v) == "number" then return v, false end
end

-- Returns hp, mana as plain 0-1 numbers (nil = not this kind / no mana bar),
-- plus hpS, manaS: secret-capable fallbacks { v = value, is100 = bool } when
-- the plain read was a secret.
local function Resource(kind)
    local wantHP, wantMana = kind ~= "drink", kind ~= "food"
    local hp, mana, hpS, manaS
    if wantHP then
        local cur, max = UnitHealth("player"), UnitHealthMax("player")
        hp = Pct(cur, max)
        if hp == nil and not (Plain(cur) and Plain(max)) then
            local v, is100 = HealthPctSecret()
            if type(v) == "number" then hpS = { v = v, is100 = is100 } end
        end
    end
    if wantMana then
        local okC, cur = pcall(UnitPower, "player", MANA)
        local okM, max = pcall(UnitPowerMax, "player", MANA)
        if not okC then cur = nil end
        if not okM then max = nil end
        mana = Pct(cur, max)
        if mana == nil and not (Plain(cur) and Plain(max)) then
            local v, is100 = ManaPctSecret()
            if type(v) == "number" then manaS = { v = v, is100 = is100 } end
        end
    end
    return hp, mana, hpS, manaS
end

-------------------------------------------------------------------------------
--  The widget: a stack of bars (the live frame and the preview both use it)
-------------------------------------------------------------------------------
local function FontPath()
    local f = Get("ftFont")
    if f and f ~= "__global" and EllesmereUI.ResolveFontName then
        local path = EllesmereUI.ResolveFontName(f)
        if path then return path end
    end
    return EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
end

local function MakeBar(parent)
    local b = CreateFrame("Frame", nil, parent)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.iconBorder = b:CreateTexture(nil, "BORDER")
    b.iconBorder:SetTexture(WHITE)
    b.iconBorder:SetVertexColor(0, 0, 0, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.sb = CreateFrame("StatusBar", nil, b)
    b.sb:SetStatusBarTexture(WHITE)
    b.sb:SetMinMaxValues(0, 1)
    b.sbBg = b.sb:CreateTexture(nil, "BACKGROUND")
    b.sbBg:SetAllPoints()
    b.sbBg:SetTexture(WHITE)
    b.name = b.sb:CreateFontString(nil, "OVERLAY")
    b.name:SetFontObject(GameFontHighlightSmall)
    b.name:SetShadowOffset(1, -1)
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    b.time = b.sb:CreateFontString(nil, "OVERLAY")
    b.time:SetFontObject(GameFontHighlightSmall)
    b.time:SetShadowOffset(1, -1)
    b.time:SetJustifyH("RIGHT")
    b.res = b.sb:CreateFontString(nil, "OVERLAY")
    b.res:SetFontObject(GameFontHighlightSmall)
    b.res:SetShadowOffset(1, -1)
    b.res:SetJustifyH("RIGHT")
    b.full = b.sb:CreateFontString(nil, "OVERLAY")
    b.full:SetFontObject(GameFontHighlightSmall)
    b.full:SetShadowOffset(1, -1)
    b.full:SetJustifyH("RIGHT")
    b.full:SetText("Full")
    b.full:SetAlpha(0)
    b:Hide()
    return b
end

-- One DEDICATED bar per kind (food / drink / both), never reused for another
-- kind: a bar that showed Drink (mana curve, secret values) and then Food
-- stopped rendering on this client (field 2026-10-17: re-eating while
-- drinking moved Food from slot 2 to slot 1 and the bar went blank).
local BAR_KINDS = { "food", "drink", "both" }

local KIND_INDEX = { food = 1, drink = 2, both = 3 }

-- A brand-new bar for kind slot i (diagnostic Hide hooks included).
local function CreateKindBar(f, i)
    local b = MakeBar(f)
    f.bars[i] = b
    b._kind = BAR_KINDS[i]
    f.byKind[BAR_KINDS[i]] = b
    hooksecurefunc(b, "Hide", function()
        b._hideAt = GetTime()
        b._hideBy = debugstack and debugstack(3, 4, 0) or "?"
    end)
    return b
end

local function MakeWidget(f)
    f.bars = {}
    f.byKind = {}
    for i = 1, MAX_BARS do CreateKindBar(f, i) end
    return f
end

local function StyleBar(b)
    local w, h = Get("ftWidth"), Get("ftHeight")
    local showIcon = Get("ftShowIcon") ~= false
    b:SetSize(w, h)
    b.bg:SetColorTexture(Get("ftBgR"), Get("ftBgG"), Get("ftBgB"), Get("ftBgA"))
    b.iconBorder:SetShown(showIcon)
    b.icon:SetShown(showIcon)
    b.iconBorder:ClearAllPoints()
    b.iconBorder:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.iconBorder:SetSize(h, h)
    b.icon:ClearAllPoints()
    b.icon:SetPoint("TOPLEFT", b.iconBorder, "TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", b.iconBorder, "BOTTOMRIGHT", -1, 1)
    b.sb:ClearAllPoints()
    b.sb:SetPoint("TOPLEFT", b, "TOPLEFT", showIcon and (h + 1) or 1, -1)
    b.sb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.sbBg:SetVertexColor(0, 0, 0, 0.35)
    local size = Get("ftTextSize")
    EllesmereUI.ApplyModuleFont(b.name, FontPath(), size)
    EllesmereUI.ApplyModuleFont(b.time, FontPath(), size)
    EllesmereUI.ApplyModuleFont(b.res, FontPath(), size)
    EllesmereUI.ApplyModuleFont(b.full, FontPath(), size)
    local tr, tg, tb = Get("ftTextR"), Get("ftTextG"), Get("ftTextB")
    b.name:SetTextColor(tr, tg, tb)
    b.time:SetTextColor(tr, tg, tb)
    b.res:SetTextColor(tr, tg, tb)
    b.full:SetTextColor(tr, tg, tb)
    -- FIXED slots, no anchor follows a text's width: the percent text can be
    -- a SECRET value, and a layout that depends on a secret width left the
    -- Food bar blank after it was hidden and shown again (field 2026-10-17).
    local timeW = math.floor(size * 2.8 + 0.5)   -- "9.4s" / "12:34"
    local resW  = math.floor(size * 4.6 + 0.5)   -- "HP 100%" / "Full"
    b.time:ClearAllPoints()
    b.time:SetPoint("RIGHT", b.sb, "RIGHT", -4, 0)
    b.time:SetWidth(timeW)
    b.res:ClearAllPoints()
    b.res:SetPoint("RIGHT", b.sb, "RIGHT", -(4 + timeW + 4), 0)
    b.res:SetWidth(resW)
    b.full:ClearAllPoints()
    b.full:SetPoint("RIGHT", b.sb, "RIGHT", -(4 + timeW + 4), 0)
    b.full:SetWidth(resW)
    for _, fs in ipairs({ b.time, b.res, b.full }) do
        fs:SetJustifyH("RIGHT")
        fs:SetWordWrap(false)
    end
    b.name:ClearAllPoints()
    b.name:SetPoint("LEFT", b.sb, "LEFT", 4, 0)
    b.name:SetPoint("RIGHT", b.sb, "RIGHT", -(4 + timeW + 4 + resW + 4), 0)
end

local function StyleWidget(f)
    local h = Get("ftHeight")
    local up = Get("ftGrow") == "up"
    for _, b in ipairs(f.bars) do
        StyleBar(b)
        b._slot = nil -- re-anchor on the next paint
    end
    f._up = up
    f._h = h
    f:SetSize(Get("ftWidth"), h)
end

-- Put a bar in a stacking slot (1 = first); only re-anchors when it moves.
-- Re-anchored on EVERY paint, on purpose: on this client a bar anchored while
-- its stack frame was hidden / just being shown stayed blank (shown, visible,
-- alpha 1, right text, nothing drawn) until it was anchored again — field
-- 2026-10-17: the bar that arrived alone stayed blank, and came back the
-- moment a second buff pushed it to another slot.
local function AnchorSlot(f, b, slot)
    b._slot, b._slotUp, b._slotH = slot, f._up, f._h
    b:ClearAllPoints()
    local off = (slot - 1) * ((f._h or Get("ftHeight")) + GAP)
    if f._up then
        b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, off)
    else
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -off)
    end
end

-------------------------------------------------------------------------------
--  Secret-safe "Full": on this client UnitHealth / UnitPower can be SECRET,
--  so Lua cannot tell 100% from 99%. The client can: a curve passed to
--  UnitHealthPercent / UnitPowerPercent is evaluated engine-side and the
--  (secret) result goes straight into a widget setter, never compared here.
--    colorCurve: bar color below full, Full color at full
--    onCurve / offCurve: alpha of the "Full" text / of the percent text
-------------------------------------------------------------------------------
local curveCache = {} -- kind -> { key, curves }
local BarColor

local function Curves(kind)
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and C_CurveUtil.CreateCurve and CreateColor) then
        return nil
    end
    kind = kind or "food"
    local br, bg, bb = BarColor(kind)
    local fr, fg, fb = Get("ftFullR"), Get("ftFullG"), Get("ftFullB")
    local key = string.format("%.3f%.3f%.3f%.3f%.3f%.3f", br, bg, bb, fr, fg, fb)
    local cached = curveCache[kind]
    if cached and cached.key == key then return cached.curves end
    local ok, built = pcall(function()
        local step = Enum.LuaCurveType and Enum.LuaCurveType.Step
        local cc = C_CurveUtil.CreateColorCurve()
        local on = C_CurveUtil.CreateCurve()
        local offc = C_CurveUtil.CreateCurve()
        if step then
            pcall(cc.SetType, cc, step); pcall(on.SetType, on, step); pcall(offc.SetType, offc, step)
        end
        -- Extra points at 0.998 / 0.999 keep it a hard edge even if Step is missing.
        local normal, full = CreateColor(br, bg, bb, 0.9), CreateColor(fr, fg, fb, 0.9)
        cc:AddPoint(0, normal);   cc:AddPoint(0.998, normal)
        cc:AddPoint(0.999, full); cc:AddPoint(1, full)
        on:AddPoint(0, 0);   on:AddPoint(0.998, 0);   on:AddPoint(0.999, 1);   on:AddPoint(1, 1)
        offc:AddPoint(0, 1); offc:AddPoint(0.998, 1); offc:AddPoint(0.999, 0); offc:AddPoint(1, 0)
        return { color = cc, on = on, off = offc }
    end)
    if not ok then return nil end
    curveCache[kind] = { key = key, curves = built }
    return built
end

local function EvalCurve(useMana, curve)
    if useMana then
        if not UnitPowerPercent then return end
        local ok, v = pcall(UnitPowerPercent, "player", MANA, false, curve)
        if ok then return v end
    else
        if not UnitHealthPercent then return end
        local ok, v = pcall(UnitHealthPercent, "player", false, curve)
        if ok then return v end
    end
end

-- true when the curve path painted the bar (color + Full / percent alpha).
local function PaintSecretFull(b, kind, useMana, showPct)
    local c = Curves(kind)
    if not c then return false end
    local col = EvalCurve(useMana, c.color)
    -- never test col itself (it may be secret): a nil / bad value just errors inside pcall
    local okC = pcall(function() b.sb:SetStatusBarColor(col:GetRGBA()) end)
    if not okC then return false end
    local on, off = EvalCurve(useMana, c.on), EvalCurve(useMana, c.off)
    pcall(b.full.SetAlpha, b.full, on)
    if showPct then pcall(b.res.SetAlpha, b.res, off) else b.res:SetAlpha(1) end
    return true
end

-- Food bar: ftBarColor / ftBarR/G/B. Drink (and Food & Drink): ftDrinkColor / ftDrinkR/G/B.
function BarColor(kind)
    if kind == "fed" then
        if Get("ftFedColor") == "accent" then return Accent() end
        return Get("ftFedR"), Get("ftFedG"), Get("ftFedB")
    end
    if kind == "drink" or kind == "both" then
        if Get("ftDrinkColor") == "accent" then return Accent() end
        return Get("ftDrinkR"), Get("ftDrinkG"), Get("ftDrinkB")
    end
    if Get("ftBarColor") == "custom" then return Get("ftBarR"), Get("ftBarG"), Get("ftBarB") end
    return Accent()
end

local function FormatTime(s)
    if s < 0 then s = 0 end
    if s < 10 and Get("ftDecimals") ~= false then return string.format("%.1fs", s) end
    if s < 60 then return string.format("%ds", math.ceil(s)) end
    s = math.ceil(s)
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function PctText(p, label)
    return string.format("%s %d%%", label, math.floor(p * 100 + 0.5))
end

-- One bar. d = { name, icon, kind, duration, expires } ; now = GetTime()
local function PaintBar(b, d, now)
    local left = math.max(0, d.expires - now)
    b.sb:SetValue(d.duration > 0 and left / d.duration or 0)
    b.icon:SetTexture(d.icon)

    if d.kind == "fed" then
        -- Well Fed: just the time left, no health / mana / Full.
        local fr, fg, fb = BarColor("fed")
        b.sb:SetStatusBarColor(fr, fg, fb, 0.9)
        b.time:SetText(FormatTime(left))
        b.res:SetText("")
        b.res:SetAlpha(1)
        b.full:SetAlpha(0)
        b.name:SetText(Get("ftShowName") ~= false and d.name or "")
        b:Show()
        return
    end

    local hp, mana, hpS, manaS = d.hp, d.mana, nil, nil
    if d.hp == nil and d.mana == nil and not d.sample then hp, mana, hpS, manaS = Resource(d.kind) end
    local full = Get("ftFullHL") ~= false
        and (hp == nil or hp >= 0.999) and (mana == nil or mana >= 0.999)
        and (hp ~= nil or mana ~= nil)

    local r, g, bl
    if full then r, g, bl = Get("ftFullR"), Get("ftFullG"), Get("ftFullB")
    else r, g, bl = BarColor(d.kind) end
    b.sb:SetStatusBarColor(r, g, bl, 0.9)

    b.time:SetText(FormatTime(left))
    b.full:SetAlpha(0)
    b.res:SetAlpha(1)
    if (hpS or manaS) and Get("ftFullHL") ~= false then
        -- secret values: color + "Full" decided engine-side
        if PaintSecretFull(b, d.kind, manaS ~= nil, Get("ftResource") ~= false) then
            if Get("ftResource") == false then b.res:SetText("") end
        end
    end
    if full then
        b.res:SetText("Full")
    elseif Get("ftResource") ~= false then
        local parts = {}
        if hp then parts[#parts + 1] = PctText(hp, "HP") end
        if mana then parts[#parts + 1] = PctText(mana, "MP") end
        if #parts > 0 then
            b.res:SetText(table.concat(parts, " "))
        elseif manaS or hpS then
            -- Secret value: the FontString formats it, Lua never touches it.
            local s = manaS or hpS
            local label = manaS and "MP" or "HP"
            if s.is100 then
                b.res:SetFormattedText(label .. " %.0f%%", s.v)
            else
                b.res:SetFormattedText(label .. " %.0f%%", s.v * 100)
            end
        else
            b.res:SetText("")
        end
    else
        b.res:SetText("")
    end
    b.name:SetText(Get("ftShowName") ~= false and d.name or "")
    b:Show()
end

-- Paint the whole stack; returns the number of bars shown.
-- On this client a bar that was SHOWN, HIDDEN and then SHOWN again (the Food
-- bar when you eat again: the old buff drops for a moment) can stop rendering
-- for good: shown / visible / alpha 1 / right text, yet nothing on screen, and
-- even an outline anchored to it is not drawn. A bar fresh from CreateFrame
-- always draws (first meal after /reload is fine). So every time a kind's bar
-- comes BACK after being hidden, it is replaced by a brand-new frame; the old
-- one is hidden, detached and dropped.
local function FreshBar(f, kind)
    local i = KIND_INDEX[kind]
    local old = f.byKind[kind]
    if old then
        old:Hide()
        old:ClearAllPoints()
        old._dead = true
    end
    local b = CreateKindBar(f, i)
    StyleBar(b)
    b:SetFrameLevel(f:GetFrameLevel() + 1)
    f._renewed = (f._renewed or 0) + 1
    return b
end

local function PaintWidget(f, entries, now)
    local n = 0
    local used = {}
    local prev = f._prevKinds or {}
    local nowKinds = {}
    for _, d in ipairs(entries) do
        local b = f.byKind and f.byKind[d.kind]
        if b and not used[b] then -- a second aura of the same kind: skip
            -- (v19 replaced a returning bar with a new frame: did not help,
            -- the re-anchor above is the fix; FreshBar is kept but unused.)
            nowKinds[d.kind] = true
            used[b] = true
            n = n + 1
            AnchorSlot(f, b, n)
            PaintBar(b, d, now)
            b._everShown = true
        end
    end
    for _, b in ipairs(f.bars) do
        if not used[b] then b:Hide() end
    end
    f._prevKinds = nowKinds
    local h = Get("ftHeight")
    f:SetSize(Get("ftWidth"), math.max(h, n * h + math.max(0, n - 1) * GAP))
    return n
end

-------------------------------------------------------------------------------
--  Live frame + position (Unlock Mode)
-------------------------------------------------------------------------------
local frame, events
local S = { unlocked = false, active = false, fedUnlocked = false }
local UpdateFed -- defined with the Well Fed icon below (used by the bars' rescan)

local function Enabled() return Get("ftEnabled") == true end

local function SavedPos()
    local pos = Get("ftPosition")
    return pos and pos.point and pos or DEFAULT_POS
end

local function Place()
    if not frame then return end
    StyleWidget(frame)
    frame:ClearAllPoints()
    local pos = SavedPos()
    frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
end

-- Samples (Unlock Mode + options preview): a food bar and a drink bar.
local function Samples(now, phase)
    phase = phase or 0
    return {
        { name = "Food",  kind = "food",  icon = ICON_FOOD,  duration = 30,
          expires = now + 30 - (phase % 30), hp = 0.35 + 0.65 * ((phase % 30) / 30), sample = true },
        { name = "Drink", kind = "drink", icon = ICON_DRINK, duration = 30,
          expires = now + 18 - (phase % 18), mana = 1, sample = true },
    }
end

local acc, rescanAcc = 0, 0
local function OnUpdate(self, elapsed)
    acc = acc + elapsed
    rescanAcc = rescanAcc + elapsed
    if acc < 0.05 then return end
    acc = 0
    if S.unlocked then return end
    -- Once a second: full rescan, so a buff added without a usable
    -- UNIT_AURA (or refreshed) still shows up / updates.
    if rescanAcc >= 1 then
        rescanAcc = 0
        local okS, errS = pcall(Scan)
        if not okS then ns.lastError = "Scan: " .. tostring(errS) end
        local okF, errF = pcall(UpdateFed)
        if not okF then ns.lastError = "UpdateFed: " .. tostring(errF) end
    end
    local now = GetTime()
    -- Expired between aura events: drop it
    for i = #list, 1, -1 do
        if list[i].expires <= now then table.remove(list, i) end
    end
    if #list == 0 then
        self:Hide()
        return
    end
    local ok, err = pcall(PaintWidget, self, list, now)
    if not ok then ns.lastError = "OnUpdate: " .. tostring(err) end
end

-------------------------------------------------------------------------------
--  Well Fed: its own icon (timer inside, optional swipe), moved on its own
-------------------------------------------------------------------------------
local fedFrame

local function FedActive() return Enabled() and Get("ftFed") ~= false end

local function MakeFed(f)
    f.border = f:CreateTexture(nil, "BORDER")
    f.border:SetAllPoints()
    f.border:SetTexture(WHITE)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f.icon)
    if f.cd.SetDrawEdge then f.cd:SetDrawEdge(false) end
    if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(true) end
    if f.cd.SetReverse then f.cd:SetReverse(true) end
    f.cd.noCooldownCount = true -- keep OmniCC-style addons off it
    f.textHolder = CreateFrame("Frame", nil, f)
    f.textHolder:SetAllPoints()
    f.text = f.textHolder:CreateFontString(nil, "OVERLAY")
    f.text:SetFontObject(GameFontHighlight)
    f.text:SetShadowOffset(1, -1)
    f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
    f:Hide()
    return f
end

local function StyleFed(f)
    local size = Get("ftFedSize")
    f:SetSize(size, size)
    local bs = math.max(0, math.min(math.floor((Get("ftFedBorder") or 1) + 0.5), math.floor(size / 4)))
    f.border:SetShown(bs > 0)
    f.icon:ClearAllPoints()
    f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", bs, -bs)
    f.icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -bs, bs)
    f.cd:SetFrameLevel(f:GetFrameLevel() + 1)
    f.textHolder:SetFrameLevel(f:GetFrameLevel() + 3)
    EllesmereUI.ApplyModuleFont(f.text, FontPath(), Get("ftFedTextSize"))
    f.text:SetTextColor(Get("ftFedTimerR"), Get("ftFedTimerG"), Get("ftFedTimerB"))
end

-- Well Fed timer: 1h+ as "1h", otherwise m:ss / seconds.
local function FedTime(s)
    if s >= 3600 then return string.format("%dh", math.floor(s / 3600)) end
    return FormatTime(s)
end

-- Secret mode: the Cooldown's own countdown prints the (secret) time left;
-- our text is hidden. Normal mode: our text, no Cooldown numbers.
local function SetSecretMode(f, on)
    if f._secret == on then return end
    f._secret = on
    if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(not on) end
    f.text:SetShown(not on)
end

local function StyleCountdown(f)
    local fs = f.cd.GetCountdownFontString and f.cd:GetCountdownFontString()
    if not fs then return end
    EllesmereUI.ApplyModuleFont(fs, FontPath(), Get("ftFedTextSize"))
    fs:SetTextColor(Get("ftFedTimerR"), Get("ftFedTimerG"), Get("ftFedTimerB"))
end

-- Well Fed with SECRET data (in combat): icon + engine-driven cooldown.
local function PaintFedSecret(f, sec)
    SetSecretMode(f, true)
    StyleCountdown(f)
    f.icon:SetDesaturated(false)
    f.icon:SetVertexColor(1, 1, 1)
    if not pcall(f.icon.SetTexture, f.icon, sec.icon) then f.icon:SetTexture(f._lastIcon or ICON_FED) end
    f.border:SetVertexColor(BarColor("fed"))
    if f.cd.SetDrawSwipe then f.cd:SetDrawSwipe(Get("ftFedSwipe") ~= false) end
    f._cdStart, f._cdDur = nil, nil
    local done = false
    if C_UnitAuras and C_UnitAuras.GetAuraDuration and f.cd.SetCooldownFromDurationObject then
        done = pcall(function()
            local dur = C_UnitAuras.GetAuraDuration("player", sec.inst)
            f.cd:SetCooldownFromDurationObject(dur)
        end)
    end
    if not done and f.cd.SetCooldownFromExpirationTime then
        done = pcall(function()
            f.cd:SetCooldownFromExpirationTime(sec.aura.expirationTime, sec.aura.duration)
        end)
    end
    f.cd:SetShown(done)
    f:Show()
end

local function PaintFed(f, d, now)
    SetSecretMode(f, false)
    if f.cd.SetDrawSwipe then f.cd:SetDrawSwipe(true) end
    local left = math.max(0, d.expires - now)
    f.icon:SetTexture(d.icon or ICON_FED)
    f.icon:SetDesaturated(false)
    f.icon:SetVertexColor(1, 1, 1)
    f._lastIcon = d.icon or f._lastIcon
    f.border:SetVertexColor(BarColor("fed"))
    f.text:SetText(FedTime(left))
    local start = d.expires - d.duration
    if Get("ftFedSwipe") ~= false then
        if f._cdStart ~= start or f._cdDur ~= d.duration then
            f._cdStart, f._cdDur = start, d.duration
            f.cd:SetCooldown(start, d.duration)
        end
        f.cd:Show()
    else
        f._cdStart, f._cdDur = nil, nil
        f.cd:Hide()
    end
    f:Show()
end

-- No Well Fed on you: the icon stays, grey, no timer (Show When Missing).
local function PaintFedMissing(f)
    SetSecretMode(f, false)
    f.icon:SetTexture(f._lastIcon or ICON_FED)
    f.icon:SetDesaturated(true)
    f.icon:SetVertexColor(0.6, 0.6, 0.6)
    f.border:SetVertexColor(0.35, 0.35, 0.35)
    f.text:SetText("")
    f._cdStart, f._cdDur = nil, nil
    f.cd:Hide()
    f:Show()
end

local function FedSample(now)
    return { name = "Well Fed", kind = "fed", icon = ICON_FED, duration = 900,
             expires = now + 600, sample = true }
end

local function SavedFedPos()
    local pos = Get("ftFedPosition")
    return pos and pos.point and pos or DEFAULT_FED_POS
end

local function PlaceFed()
    if not fedFrame then return end
    StyleFed(fedFrame)
    fedFrame:ClearAllPoints()
    local pos = SavedFedPos()
    fedFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
end

local fedAcc = 0
local function FedOnUpdate(self, elapsed)
    fedAcc = fedAcc + elapsed
    if fedAcc < 0.2 then return end
    fedAcc = 0
    if S.fedUnlocked then return end
    if not fedEntry then return end -- greyed "missing" icon: nothing ticks
    local now = GetTime()
    if fedEntry.expires <= now then
        fedEntry = nil
        UpdateFed() -- grey icon (Show When Missing) or hidden
        return
    end
    PaintFed(self, fedEntry, now)
end

local function BuildFed()
    if fedFrame then return fedFrame end
    fedFrame = CreateFrame("Frame", "EUI_DworakWellFedFrame", UIParent)
    fedFrame:SetFrameStrata("MEDIUM")
    fedFrame:SetFrameLevel(20)
    fedFrame:SetClampedToScreen(true)
    MakeFed(fedFrame)
    fedFrame:SetScript("OnUpdate", FedOnUpdate)
    PlaceFed()
    return fedFrame
end

-- Show / hide the live icon from the last Scan().
function UpdateFed()
    if not FedActive() then
        if fedFrame then fedFrame:Hide() end
        return
    end
    BuildFed()
    if S.fedUnlocked then return end
    if fedEntry then
        PaintFed(fedFrame, fedEntry, GetTime())
    elseif fedSecret then
        PaintFedSecret(fedFrame, fedSecret)
    elseif Get("ftFedMissing") == true then
        PaintFedMissing(fedFrame)
    else
        fedFrame:Hide()
    end
end

local function Build()
    if frame then return frame end
    frame = CreateFrame("Frame", "EUI_DworakFoodTimerFrame", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(20)
    frame:SetClampedToScreen(true)
    MakeWidget(frame)
    frame:Hide()
    frame:SetScript("OnUpdate", OnUpdate)
    -- The whole stack hidden (no buff left): every bar that comes back after
    -- this counts as "coming back" and gets a fresh frame (see FreshBar).
    frame:HookScript("OnHide", function(self) self._prevKinds = nil end)
    Place()
    return frame
end

local retries, retryQueued = 0, false
local Update
local function QueueRetry()
    if retryQueued or retries >= 20 then return end
    retryQueued = true
    retries = retries + 1
    C_Timer.After(0.25, function()
        retryQueued = false
        Update(true)
    end)
end

function Update(isRetry)
    if not isRetry then retries = 0 end
    if not Enabled() then
        if frame then frame:Hide() end
        if fedFrame then fedFrame:Hide() end
        return
    end
    Build()
    local okScan, err = pcall(Scan)
    if not okScan then ns.lastError = err end
    if pending then QueueRetry() end
    -- The bars first, and the Well Fed icon in a pcall: an icon error must
    -- never take the eating / drinking bars down with it.
    if not S.unlocked then
        if #list > 0 then
            -- Show FIRST, then anchor + paint: anchoring the bars while the
            -- stack frame was still hidden is what left them blank.
            frame:Show()
            local okPaint, perr = pcall(PaintWidget, frame, list, GetTime())
            if not okPaint then ns.lastError = perr end
        else
            frame:Hide()
        end
    end
    local okFed, ferr = pcall(UpdateFed)
    if not okFed then ns.lastError = ferr end
end

-- Safety net: once a second, while the bars are hidden, look again (cheap:
-- one pass over the player's buffs). Catches a Food / Drink buff whose
-- UNIT_AURA came before its data was usable.
C_Timer.NewTicker(1, function()
    if not events or not Enabled() or S.unlocked then return end -- before login / off
    if frame and frame:IsShown() then return end
    Update(true)
end)

local function OnEvent(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        NAMES = nil -- rebuild once the client has its spell names
        Place()
        PlaceFed()
    end
    Update()
end

local RefreshPreview

local function Apply()
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    events:UnregisterAllEvents()
    if not Enabled() then
        if frame then frame:Hide() end
        if fedFrame then fedFrame:Hide() end
        if RefreshPreview then RefreshPreview() end
        return
    end
    Build()
    PlaceFed()
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    pcall(events.RegisterUnitEvent, events, "UNIT_AURA", "player")
    -- Combat ends: the aura data turns readable again, but no UNIT_AURA says so.
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    Place()
    Update()
    if RefreshPreview then RefreshPreview() end
end

-------------------------------------------------------------------------------
--  Options preview: the bars in the content header, draining
-------------------------------------------------------------------------------
local PREVIEW_H = 80
local preview

local function PreviewTick(self, elapsed)
    self.t = (self.t or 0) + elapsed
    self.acc = (self.acc or 0) + elapsed
    if self.acc < 0.05 then return end
    self.acc = 0
    local now = GetTime()
    PaintWidget(self.box, Samples(now, self.t), now)
    if self.fed then
        if not self.fedExp or self.fedExp <= now then self.fedExp = now + 600 end
        if Get("ftFed") ~= false then
            PaintFed(self.fed, { name = "Well Fed", kind = "fed", icon = ICON_FED, duration = 900,
                expires = self.fedExp }, now)
        else
            self.fed:Hide()
        end
    end
end

function RefreshPreview()
    if not (preview and preview:IsShown()) then return end
    StyleWidget(preview.box)
    local now = GetTime()
    PaintWidget(preview.box, Samples(now, preview.t or 0), now)
    preview.box:SetAlpha(Enabled() and 1 or 0.5)
    if preview.fed then
        StyleFed(preview.fed)
        -- the sample Well Fed restarts at 10:00 when it runs out
        if not preview.fedExp or preview.fedExp <= now then preview.fedExp = now + 600 end
        preview.fed._cdStart = nil
        if Get("ftFed") ~= false then
            PaintFed(preview.fed, { name = "Well Fed", kind = "fed", icon = ICON_FED, duration = 900,
                expires = preview.fedExp }, now)
        else
            preview.fed:Hide()
        end
        preview.fed:SetAlpha(Enabled() and 1 or 0.5)
    end
    preview.hint:SetText(Enabled() and "Matched by the buff's name: every food and drink"
        or "Preview (the timer is off)")
end

local function HeaderBuilder(header, width)
    if not preview then
        preview = CreateFrame("Frame", nil, header)
        preview.box = MakeWidget(CreateFrame("Frame", nil, preview))
        preview.box:SetPoint("TOP", preview, "TOP", -30, -10)
        preview.fed = MakeFed(CreateFrame("Frame", nil, preview))
        preview.fed:SetPoint("TOPLEFT", preview.box, "TOPRIGHT", 16, 0)
        preview.hint = preview:CreateFontString(nil, "OVERLAY")
        preview.hint:SetFontObject(GameFontDisableSmall)
        preview.hint:SetPoint("BOTTOM", preview, "BOTTOM", 0, 6)
        preview:SetScript("OnUpdate", PreviewTick)
    end
    preview:SetParent(header)
    preview:SetFrameStrata(header:GetFrameStrata())
    preview:SetFrameLevel(header:GetFrameLevel() + 5)
    preview.box:SetFrameLevel(preview:GetFrameLevel() + 1)
    for _, b in ipairs(preview.box.bars) do b:SetFrameLevel(preview.box:GetFrameLevel() + 1) end
    preview.fed:SetFrameLevel(preview:GetFrameLevel() + 1)
    preview:ClearAllPoints()
    preview:SetPoint("TOPLEFT", header, "TOPLEFT")
    preview:SetPoint("TOPRIGHT", header, "TOPRIGHT")
    if width and width > 0 then preview:SetWidth(width) end
    local h = math.max(PREVIEW_H, 2 * Get("ftHeight") + GAP + 34, Get("ftFedSize") + 34)
    preview:SetHeight(h)
    preview:Show()
    RefreshPreview()
    return h
end

local function Refresh()
    if fedFrame then
        PlaceFed()
        if S.fedUnlocked then
            PaintFed(fedFrame, FedSample(GetTime()), GetTime())
        else
            UpdateFed()
        end
    end
    if frame then
        Place()
        if S.unlocked then
            local now = GetTime()
            PaintWidget(frame, Samples(now, 8), now)
        else
            Update()
        end
    end
    RefreshPreview()
end

-------------------------------------------------------------------------------
--  Options page (Dworak > Food Timer)
-------------------------------------------------------------------------------
local function BuildPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h
    parent._showRowDivider = true
    local function off() return not Enabled() end
    local OFF_TIP = "Food Timer"
    local prebuilding = EllesmereUI.IsSearchPrebuild()
    if not prebuilding then EllesmereUI:SetContentHeader(HeaderBuilder) end

    local function S_(key, after)
        return function(v)
            Set(key, v)
            if after then after() end
            Refresh()
        end
    end
    local function Swatch(region, tip, kR, kG, kB, disabled, disabledTip)
        if prebuilding or not region then return end
        EllesmereUI.BuildInlineSwatches(region, { {
            tooltip = tip,
            disabled = disabled or off,
            disabledTooltip = function() return off() and OFF_TIP or (disabledTip or OFF_TIP) end,
            getValue = function() return Get(kR), Get(kG), Get(kB), 1 end,
            setValue = function(r, g, b)
                Set(kR, r); Set(kG, g); Set(kB, b)
                Refresh()
            end,
        } }, { disabled = off, disabledTooltip = OFF_TIP })
    end

    _, h = W:SectionHeader(parent, "FOOD TIMER", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Food Timer",
          tooltip = "A bar with the time left while you eat or drink. Every food / drink is "
              .. "found by the buff's name (Food, Drink, Food & Drink, Refreshment), "
              .. "no spell IDs needed.\nMove it in Unlock Mode.",
          getValue = function() return Enabled() end,
          setValue = function(v)
              Set("ftEnabled", v)
              Apply()
              EllesmereUI:RefreshPage()
          end },
        { type = "toggle", text = "Track Drink",
          tooltip = "Drink buffs get their own bar too. Off: food only.",
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("ftDrink") ~= false end,
          setValue = S_("ftDrink", Update) }
    );  y = y - h

    local fullRow
    fullRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show Health / Mana",
          tooltip = "Health % on the Food bar, mana % on the Drink bar.",
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("ftResource") ~= false end,
          setValue = S_("ftResource") },
        { type = "toggle", text = "Full Highlight",
          tooltip = "When health (food) / mana (drink) is full, the bar takes the Full color "
              .. "(swatch) and reads \"Full\": you can stand up.",
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("ftFullHL") ~= false end,
          setValue = function(v)
              Set("ftFullHL", v)
              Refresh()
              EllesmereUI:RefreshPage()
          end }
    );  y = y - h
    if fullRow then
        Swatch(fullRow._rightRegion, "Full Color", "ftFullR", "ftFullG", "ftFullB",
            function() return off() or Get("ftFullHL") == false end, "Full Highlight")
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h
    _, h = W:SectionHeader(parent, "WELL FED ICON", y);  y = y - h

    local function fedOff() return off() or Get("ftFed") == false end
    local FED_TIP = "Food Timer / Track Well Fed"
    local fedRow
    fedRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Track Well Fed",
          tooltip = "An icon for the Well Fed buff (from buff food) with its time left inside, "
              .. "found by the buff's name.\nIt moves on its own in Unlock Mode (\"Well Fed\").",
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("ftFed") ~= false end,
          setValue = function(v)
              Set("ftFed", v)
              Update()
              Refresh()
              EllesmereUI:RefreshPage()
          end },
        { type = "dropdown", text = "Border Color",
          tooltip = "The icon's border. UI Accent Color follows Global Settings; Custom uses the color next to it.",
          values = { accent = "UI Accent Color", custom = "Custom" }, order = { "accent", "custom" },
          disabled = fedOff, disabledTooltip = FED_TIP,
          getValue = function() return Get("ftFedColor") or "custom" end,
          setValue = function(v)
              Set("ftFedColor", v)
              Refresh()
              EllesmereUI:RefreshPage()
          end }
    );  y = y - h
    if fedRow then
        Swatch(fedRow._rightRegion, "Custom Border Color", "ftFedR", "ftFedG", "ftFedB",
            function() return fedOff() or Get("ftFedColor") == "accent" end,
            "Border Color: Custom")
    end

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Icon Size", min = 16, max = 80, step = 1,
          disabled = fedOff, disabledTooltip = FED_TIP,
          getValue = function() return Get("ftFedSize") end,
          setValue = S_("ftFedSize") },
        { type = "slider", text = "Border Size", min = 0, max = 6, step = 1,
          tooltip = "Thickness of the icon's border in pixels. 0 = no border.",
          disabled = fedOff, disabledTooltip = FED_TIP,
          getValue = function() return Get("ftFedBorder") end,
          setValue = S_("ftFedBorder") }
    );  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show Swipe",
          tooltip = "A clock-style swipe over the icon as the buff runs down.",
          disabled = fedOff, disabledTooltip = FED_TIP,
          getValue = function() return Get("ftFedSwipe") ~= false end,
          setValue = S_("ftFedSwipe") },
        { type = "slider", text = "Timer Text Size", min = 8, max = 28, step = 1,
          disabled = fedOff, disabledTooltip = FED_TIP,
          getValue = function() return Get("ftFedTextSize") end,
          setValue = S_("ftFedTextSize") }
    );  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show When Missing",
          tooltip = "No Well Fed on you: the icon stays in place, greyed out, as a reminder to eat buff food.",
          disabled = fedOff, disabledTooltip = FED_TIP,
          getValue = function() return Get("ftFedMissing") == true end,
          setValue = function(v)
              Set("ftFedMissing", v)
              UpdateFed()
              Refresh()
          end },
        { type = "colorpicker", text = "Timer Color", hasAlpha = false,
          tooltip = "The time left inside the Well Fed icon.",
          disabled = fedOff, disabledTooltip = FED_TIP,
          getValue = function() return Get("ftFedTimerR"), Get("ftFedTimerG"), Get("ftFedTimerB"), 1 end,
          setValue = function(r, g, b)
              Set("ftFedTimerR", r); Set("ftFedTimerG", g); Set("ftFedTimerB", b)
              Refresh()
          end }
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h
    _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Bar Width", min = 80, max = 400, step = 1,
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("ftWidth") end,
          setValue = S_("ftWidth") },
        { type = "slider", text = "Bar Height", min = 10, max = 40, step = 1,
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("ftHeight") end,
          setValue = S_("ftHeight") }
    );  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show Icon",
          tooltip = "The buff's icon (the food / drink you are having).",
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("ftShowIcon") ~= false end,
          setValue = S_("ftShowIcon") },
        { type = "toggle", text = "Show Name",
          tooltip = "The buff's name on the bar (Food / Drink).",
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("ftShowName") ~= false end,
          setValue = S_("ftShowName") }
    );  y = y - h

    local COLOR_VALUES = { accent = "UI Accent Color", custom = "Custom" }
    local COLOR_ORDER  = { "accent", "custom" }
    local colorRow
    colorRow, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Food Bar Color",
          tooltip = "The Food bar. UI Accent Color follows Global Settings; Custom uses the color next to it.",
          values = COLOR_VALUES, order = COLOR_ORDER,
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("ftBarColor") or "accent" end,
          setValue = function(v)
              Set("ftBarColor", v)
              Refresh()
              EllesmereUI:RefreshPage()
          end },
        { type = "dropdown", text = "Drink Bar Color",
          tooltip = "The Drink (and Food & Drink) bar. UI Accent Color follows Global Settings; "
              .. "Custom uses the color next to it.",
          values = COLOR_VALUES, order = COLOR_ORDER,
          disabled = function() return off() or Get("ftDrink") == false end,
          disabledTooltip = "Food Timer / Track Drink",
          getValue = function() return Get("ftDrinkColor") or "custom" end,
          setValue = function(v)
              Set("ftDrinkColor", v)
              Refresh()
              EllesmereUI:RefreshPage()
          end }
    );  y = y - h
    if colorRow then
        Swatch(colorRow._leftRegion, "Custom Food Bar Color", "ftBarR", "ftBarG", "ftBarB",
            function() return off() or Get("ftBarColor") ~= "custom" end, "Food Bar Color: Custom")
        Swatch(colorRow._rightRegion, "Custom Drink Bar Color", "ftDrinkR", "ftDrinkG", "ftDrinkB",
            function() return off() or Get("ftDrink") == false or Get("ftDrinkColor") == "accent" end,
            "Drink Bar Color: Custom")
    end

    local bgRow
    bgRow, h = W:DualRow(parent, y,
        { type = "slider", text = "Background", min = 0, max = 100, step = 1, trackWidth = 120,
          tooltip = "Opacity of the background (color: the swatch).",
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return math.floor(Get("ftBgA") * 100 + 0.5) end,
          setValue = function(v)
              Set("ftBgA", v / 100)
              Refresh()
          end },
        { type = "dropdown", text = "Grow Direction",
          tooltip = "Eating and drinking at once: the second bar goes below or above the first.",
          values = { down = "Down", up = "Up" }, order = { "down", "up" },
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("ftGrow") or "down" end,
          setValue = S_("ftGrow") }
    );  y = y - h
    if bgRow then Swatch(bgRow._leftRegion, "Background Color", "ftBgR", "ftBgG", "ftBgB") end

    local fontValues, fontOrder = EllesmereUI.BuildFontDropdownData()
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Font", values = fontValues, order = fontOrder,
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("ftFont") or "__global" end,
          setValue = S_("ftFont") },
        { type = "slider", text = "Text Size", min = 8, max = 24, step = 1,
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("ftTextSize") end,
          setValue = S_("ftTextSize") }
    );  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "colorpicker", text = "Text Color", hasAlpha = false,
          tooltip = "The name, the percent and the time.",
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("ftTextR"), Get("ftTextG"), Get("ftTextB"), 1 end,
          setValue = function(r, g, b)
              Set("ftTextR", r); Set("ftTextG", g); Set("ftTextB", b)
              Refresh()
          end },
        { type = "toggle", text = "Decimals Under 10s",
          tooltip = "9.4s instead of 10s, 9s ... in the last ten seconds.",
          disabled = off, disabledTooltip = OFF_TIP,
          getValue = function() return Get("ftDecimals") ~= false end,
          setValue = S_("ftDecimals") }
    );  y = y - h

    return math.abs(y)
end

DW.AddModule({
    key         = "FoodTimer",
    title       = "Food Timer",
    order       = 95,
    description = "Time left while eating / drinking, with health / mana.",
    pages       = { PAGE },
    buildPage   = BuildPage,
    getHeaderBuilder = function() return HeaderBuilder end,
    onPageCacheRestore = function() RefreshPreview() end,
})

EllesmereUIFoodTimer = {
    Get = Get, Set = Set, Apply = Apply, Refresh = Refresh,
    Open = function() return DW.Open("FoodTimer") end,
}

-- /foodtimer opens the page; /foodtimer debug prints what it sees.
SLASH_EUIFOODTIMER1 = "/foodtimer"
SLASH_EUIFOODTIMER2 = "/euifood"
SlashCmdList.EUIFOODTIMER = function(msg)
    msg = msg and msg:lower() or ""
    if msg:match("find") then
        -- Draw a bright frame around the bar area for 6 s, on top of everything.
        if not frame then Say("the bar frame is not built yet."); return end
        if not frame._finder then
            local fz = CreateFrame("Frame", nil, UIParent)
            fz:SetFrameStrata("TOOLTIP")
            local t = fz:CreateTexture(nil, "OVERLAY")
            t:SetAllPoints()
            t:SetColorTexture(1, 0, 1, 0.45)
            fz.label = fz:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
            fz.label:SetPoint("BOTTOM", fz, "TOP", 0, 4)
            fz.label:SetText("Food Timer bars are here")
            frame._finder = fz
        end
        local fz = frame._finder
        fz:ClearAllPoints()
        fz:SetPoint("TOPLEFT", frame, "TOPLEFT", -4, 4)
        fz:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 4, -4)
        fz:Show()
        -- One outline per bar, anchored to the bar itself: red = bar 1, green = bar 2, blue = bar 3.
        frame._barFinders = frame._barFinders or {}
        local cols = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0.4, 1 } }
        for i, b in ipairs(frame.bars) do
            local bf = frame._barFinders[i]
            if not bf then
                bf = CreateFrame("Frame", nil, UIParent)
                bf:SetFrameStrata("TOOLTIP")
                bf.edges = {}
                for e = 1, 4 do
                    local t = bf:CreateTexture(nil, "OVERLAY")
                    t:SetColorTexture(cols[i][1], cols[i][2], cols[i][3], 1)
                    bf.edges[e] = t
                end
                bf.edges[1]:SetPoint("TOPLEFT"); bf.edges[1]:SetPoint("TOPRIGHT"); bf.edges[1]:SetHeight(3)
                bf.edges[2]:SetPoint("BOTTOMLEFT"); bf.edges[2]:SetPoint("BOTTOMRIGHT"); bf.edges[2]:SetHeight(3)
                bf.edges[3]:SetPoint("TOPLEFT"); bf.edges[3]:SetPoint("BOTTOMLEFT"); bf.edges[3]:SetWidth(3)
                bf.edges[4]:SetPoint("TOPRIGHT"); bf.edges[4]:SetPoint("BOTTOMRIGHT"); bf.edges[4]:SetWidth(3)
                bf.label = bf:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                bf.label:SetPoint("LEFT", bf, "RIGHT", 6, 0)
                bf.label:SetText("bar " .. i)
                frame._barFinders[i] = bf
            end
            if b:IsShown() then
                bf:ClearAllPoints()
                bf:SetAllPoints(b)
                bf:Show()
                C_Timer.After(6, function() bf:Hide() end)
                Say(string.format("bar %d (%s) is at %.0f, %.0f, top %.0f, points %d",
                    i, tostring(b.name:GetText()), b:GetLeft() or -1, b:GetBottom() or -1, b:GetTop() or -1, b:GetNumPoints()))
            else
                bf:Hide()
            end
        end
        C_Timer.After(6, function() fz:Hide() end)
        Say(string.format("bar frame is at %.0f, %.0f (screen left / bottom), strata %s, level %d, shown = %s",
            frame:GetLeft() or -1, frame:GetBottom() or -1, frame:GetFrameStrata(), frame:GetFrameLevel(),
            tostring(frame:IsShown())))
        return
    end
    if msg:match("debug") then
        if not NAMES then BuildNames() end
        local names = {}
        for n, k in pairs(NAMES) do names[#names + 1] = n .. "=" .. k end
        Say("enabled = " .. tostring(Enabled()) .. ", names: " .. table.concat(names, ", "))
        local function sv(v) if not Plain(v) then return "<secret>" end return tostring(v) end
        local okC, cur = pcall(UnitPower, "player", MANA)
        local okM, max = pcall(UnitPowerMax, "player", MANA)
        local ptype = UnitPowerType and select(1, UnitPowerType("player"))
        local pv, p100 = ManaPctSecret()
        Say("mana: UnitPower = " .. (okC and sv(cur) or "error") .. ", max = " .. (okM and sv(max) or "error")
            .. ", powerType = " .. sv(ptype) .. ", UnitPowerPercent = " .. sv(pv)
            .. (p100 and " (0-100)" or "") .. ", ScaleTo100 = " .. tostring(SCALE100 ~= nil))
        local hc, hm = UnitHealth("player"), UnitHealthMax("player")
        Say("health: " .. sv(hc) .. " / " .. sv(hm))
        Say("full curves: " .. (Curves("food") and "ok" or "not available on this client")
            .. ", LuaCurveType.Step = " .. tostring(Enum.LuaCurveType and Enum.LuaCurveType.Step ~= nil))
        for i = 1, 40 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or not a then break end
            local n = a.name
            if Plain(n) and KindOf(n) then
                Say(string.format("aura #%d %s: duration = %s, expirationTime = %s", i, n,
                    sv(a.duration), sv(a.expirationTime)))
            elseif not Plain(n) then
                Say(string.format("aura #%d: <secret name>", i))
            end
        end
        Scan()
        Say("bars renewed so far: " .. tostring(frame and frame._renewed or 0))
        Say("pending = " .. tostring(pending) .. ", bars = " .. #list
            .. ", bar frame shown = " .. tostring(frame and frame:IsShown() or false))
        if ns.lastError then Say("last error: " .. tostring(ns.lastError)) end
        if frame then
            local p1, rel, rp, x, y = frame:GetPoint(1)
            Say(string.format("bar frame: unlocked = %s, alpha = %.2f, size = %dx%d, point = %s %s %s %.0f %.0f, parent = %s",
                tostring(S.unlocked), frame:GetEffectiveAlpha() or -1, frame:GetWidth() or 0, frame:GetHeight() or 0,
                tostring(p1), tostring(rel and rel.GetName and rel:GetName() or rel), tostring(rp), x or 0, y or 0,
                tostring(frame:GetParent() and frame:GetParent():GetName())))
            for i, b in ipairs(frame.bars) do
                if b:IsShown() or list[i] then
                    local r, g, bl, a = b.sb:GetStatusBarColor()
                    Say(string.format("bar %d: shown = %s, visible = %s, alpha = %.2f, size = %dx%d, value = %s, color = %s, name = %s, time = %s",
                        i, tostring(b:IsShown()), tostring(b:IsVisible()), b:GetEffectiveAlpha() or -1,
                        b:GetWidth() or 0, b:GetHeight() or 0, sv(b.sb:GetValue()),
                        Plain(r) and string.format("%.2f %.2f %.2f %.2f", r or 0, g or 0, bl or 0, a or 0) or "<secret>",
                        sv(b.name:GetText()), sv(b.time:GetText())))
                    local tex = b.sb:GetStatusBarTexture()
                    local font, fsize = b.name:GetFont()
                    local function ag(f)
                        local n, playing = 0, 0
                        for _, g in ipairs({ f:GetAnimationGroups() }) do
                            n = n + 1
                            if g:IsPlaying() then playing = playing + 1 end
                        end
                        return n .. "/" .. playing
                    end
                    local _, _, _, bga = b.bg:GetVertexColor()
                    if b._hideBy then
                        Say(string.format("bar %d last hidden %.1fs ago by: %s", i, GetTime() - (b._hideAt or 0),
                            tostring(b._hideBy):gsub("\n", " || ")))
                    end
                    Say(string.format("bar %d detail: scale b/sb/frame = %.3f/%.3f/%.3f, sb visible = %s, fill tex = %s (shown %s, alpha %.2f), bg alpha = %s, font = %s %s, text alpha = %.2f, anims frame/b/sb = %s %s %s, strata b = %s lvl %d",
                        i, b:GetEffectiveScale() or -1, b.sb:GetEffectiveScale() or -1, frame:GetEffectiveScale() or -1,
                        tostring(b.sb:IsVisible()), tostring(tex and tex:GetTexture()), tostring(tex and tex:IsShown()),
                        tex and tex:GetAlpha() or -1, sv(bga), tostring(font), tostring(fsize),
                        b.name:GetAlpha() or -1, ag(frame), ag(b), ag(b.sb), b:GetFrameStrata(), b:GetFrameLevel()))
                end
            end
        else
            Say("bar frame: not built")
        end
        if #list == 0 then Say("no food / drink buff on you right now.") end
        for _, d in ipairs(list) do
            Say(string.format("%s (%s): %.1fs left of %.0fs", d.name, d.kind,
                math.max(0, d.expires - GetTime()), d.duration))
        end
        return
    end
    DW.Open("FoodTimer")
end

-- The UI Accent Color (Global Settings) repaints the bars.
if EllesmereUI.RegAccent then
    EllesmereUI.RegAccent({ type = "callback", fn = function() Refresh() end })
end

-------------------------------------------------------------------------------
--  Login: apply, then the Unlock Mode element
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
    if not (EllesmereUI.RegisterUnlockElements and EllesmereUI.MakeUnlockElement) then return end
    EllesmereUI:RegisterUnlockElements({
        EllesmereUI.MakeUnlockElement({
            key      = UNLOCK_KEY,
            label    = "Food Timer",
            group    = DW.UNLOCK_GROUP,
            order    = 945,
            noResize = true,
            isHidden = function() return not Enabled() end,
            getFrame = function()
                if not Enabled() then return nil end
                Build()
                return frame
            end,
            getSize = function()
                if frame then return frame:GetWidth(), frame:GetHeight() end
                return Get("ftWidth"), Get("ftHeight")
            end,
            savePos = function(_, point, relPoint, x, y)
                if not point then return end
                Set("ftPosition", { point = point, relPoint = relPoint, x = x, y = y })
                if not (EllesmereUI.IsUnlockModeActive and EllesmereUI:IsUnlockModeActive()) then Place() end
            end,
            loadPos = SavedPos,
            clearPos = function()
                Set("ftPosition", nil)
                Place()
            end,
            applyPos = function()
                if Enabled() then
                    Build()
                    Place()
                end
            end,
        }),
        EllesmereUI.MakeUnlockElement({
            key      = FED_KEY,
            label    = "Well Fed",
            group    = DW.UNLOCK_GROUP,
            order    = 946,
            noResize = true,
            isHidden = function() return not FedActive() end,
            getFrame = function()
                if not FedActive() then return nil end
                BuildFed()
                return fedFrame
            end,
            getSize = function()
                local sz = Get("ftFedSize")
                return sz, sz
            end,
            savePos = function(_, point, relPoint, x, y)
                if not point then return end
                Set("ftFedPosition", { point = point, relPoint = relPoint, x = x, y = y })
                if not (EllesmereUI.IsUnlockModeActive and EllesmereUI:IsUnlockModeActive()) then PlaceFed() end
            end,
            loadPos = SavedFedPos,
            clearPos = function()
                Set("ftFedPosition", nil)
                PlaceFed()
            end,
            applyPos = function()
                if FedActive() then
                    BuildFed()
                    PlaceFed()
                end
            end,
        }),
    }, ns.FOLDER)
    if EllesmereUI.RegisterUnlockModeListener then
        EllesmereUI:RegisterUnlockModeListener(FED_KEY, function(active)
            S.fedUnlocked = active and FedActive() or false
            if not fedFrame then return end
            if S.fedUnlocked then
                PlaceFed()
                fedFrame._cdStart = nil
                local now = GetTime()
                PaintFed(fedFrame, FedSample(now), now)
            else
                fedFrame._cdStart = nil
                UpdateFed()
            end
        end)
        EllesmereUI:RegisterUnlockModeListener(UNLOCK_KEY, function(active)
            S.unlocked = active and Enabled() or false
            if not frame then return end
            if S.unlocked then
                Place()
                local now = GetTime()
                PaintWidget(frame, Samples(now, 8), now)
                frame:Show()
            else
                Update()
            end
        end)
    end
end)
