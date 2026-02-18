------------------------------------------------------------------------
-- SYRIA_AirbaseCapture.lua
-- Dynamic Airbase & FARP Capture System — Syria Map
-- Version : 1.0  |  Date : 2026-02-18
------------------------------------------------------------------------
-- REQUIRES : mist_4_5_126.lua loaded BEFORE this script
-- LOAD ORDER in Mission Editor (DO SCRIPT FILE triggers):
--   1. mist_4_5_126.lua
--   2. SYRIA_AirbaseCapture.lua
--
-- HOW IT WORKS
-- ─────────────────────────────────────────────────────────────────────
-- Each airbase / FARP in the registry needs a matching Trigger Zone in
-- the Mission Editor. Every CHECK_INTERVAL seconds the script counts
-- ground units of each coalition inside that zone and runs the
-- following state machine:
--
--   RED ──(all red defenders dead)──► NEUTRAL
--   NEUTRAL ──(blue units enter, N ticks)──► BLUE
--   BLUE ──(all blue units leave)──► NEUTRAL
--   NEUTRAL ──(red units re-enter, N ticks)──► RED
--   ANY ──(ABC.setDestroyed called)──► DESTROYED
--
-- Capture is not instant — it requires CAPTURE_TICKS consecutive scans
-- with enemy units present and no defenders, preventing drive-by flips.
--
-- A coloured circle is drawn on the F10 map for every registered base:
--   Red circle    = Red coalition
--   Blue circle   = Blue coalition
--   Grey circle   = Neutral (contested or abandoned)
--   Dark grey     = Destroyed / unusable
--
-- AIRBASE COALITION NOTE
-- ─────────────────────────────────────────────────────────────────────
-- This script controls VISUAL / LOGICAL ownership. DCS engine airbase
-- coalition (affects ATC, spawn, aircraft parking) is read via the
-- S_EVENT_BASE_CAPTURED event and synced automatically when it fires.
-- If you want scripted capture to also change DCS airbase coalition,
-- enable auto-capture in the ME airbase properties for each base.
--
-- FARP REGISTRATION
-- ─────────────────────────────────────────────────────────────────────
-- FARPs have no DCS Airbase object — register them manually AFTER
-- placing them in the ME by calling from a DO SCRIPT trigger:
--
--   local farpPos = Airbase.getByName("FARP_MyBase"):getPoint()
--   ABC.registerFARP("FARP_MyBase", "ZONE_MyBase", "RED", farpPos)
--
-- PUBLIC API
-- ─────────────────────────────────────────────────────────────────────
--   ABC.getOwner(name)              → "RED"/"BLUE"/"NEUTRAL"/"DESTROYED"
--   ABC.forceCoalition(name, coal)  → force a coalition string
--   ABC.setDestroyed(name)          → mark a base as destroyed
--   ABC.registerFARP(name,zone,coal,pos) → register a placed FARP
--   ABC.redrawAll()                 → redraw all F10 map markers
--   ABC.onCapture = function(baseName, prevCoal, newCoal) … end
--                                   → optional callback on any capture
------------------------------------------------------------------------

local ABC = {}      -- module namespace

------------------------------------------------------------------------
-- SECTION 1 : CONFIGURATION
------------------------------------------------------------------------
ABC.CFG = {

    -- ── Timing ────────────────────────────────────────────────────────
    CHECK_INTERVAL    = 180,    -- seconds between full zone scans
    CAPTURE_TICKS     = 3,      -- consecutive scans needed to flip a base
    MIN_CAPTURE_UNITS = 1,      -- minimum ground units required to start capture

    -- ── Scanning ──────────────────────────────────────────────────────
    SCAN_AIR          = false,  -- true = aircraft count toward zone presence
                                -- false = ground units only (realistic default)

    -- ── Map Drawing ───────────────────────────────────────────────────
    CIRCLE_RADIUS     = 6500,   -- metres – adjust if circles feel too big/small
    LINE_TYPE         = 1,      -- 1=Solid 2=Dashed 3=Dotted 4=Dot-Dash
    LABEL_FONT_SIZE   = 14,

    -- Outline colours  {r, g, b, a}  all values 0–1
    COLOR_RED         = {r=1.00, g=0.15, b=0.15, a=0.95},
    COLOR_BLUE        = {r=0.15, g=0.45, b=1.00, a=0.95},
    COLOR_NEUTRAL     = {r=0.72, g=0.72, b=0.72, a=0.90},
    COLOR_DESTROYED   = {r=0.28, g=0.28, b=0.28, a=0.90},

    -- Fill colours (keep alpha low for readability)
    FILL_RED          = {r=1.00, g=0.15, b=0.15, a=0.13},
    FILL_BLUE         = {r=0.15, g=0.45, b=1.00, a=0.13},
    FILL_NEUTRAL      = {r=0.72, g=0.72, b=0.72, a=0.08},
    FILL_DESTROYED    = {r=0.28, g=0.28, b=0.28, a=0.08},

    -- ── Mark ID Allocation ────────────────────────────────────────────
    -- Each base reserves MARKS_PER_BASE IDs starting from BASE_MARK_OFFSET.
    -- Change BASE_MARK_OFFSET if it conflicts with other scripts' mark IDs.
    BASE_MARK_OFFSET  = 6000,
    MARKS_PER_BASE    = 4,      -- 0=circle  1=label  2-3=reserved

    -- ── Messages ──────────────────────────────────────────────────────
    MSG_DURATION      = 12,     -- seconds the capture announcement shows
}

------------------------------------------------------------------------
-- SECTION 2 : AIRBASE / FARP REGISTRY
------------------------------------------------------------------------
-- Fields:
--   name        : Exact DCS airbase name (as shown in ME / Airbase.getByName)
--   zone        : Trigger Zone name in the Mission Editor
--   coalition   : Starting coalition — "RED" | "BLUE" | "NEUTRAL"
--   type        : "AIRBASE" | "FARP"
--   capturable  : false = locked coalition (e.g. sovereign neutral territory)
--
-- TIP: Zone radius in ME should cover the base perimeter + approach roads.
--      Recommended ~6–10 km for airbases, ~2–4 km for FARPs.
------------------------------------------------------------------------
ABC.REGISTRY = {

    -- ═══════════════════════════════════════════════════════════════════
    -- SYRIAN / RUSSIAN-HELD AIRBASES  (start RED)
    -- ═══════════════════════════════════════════════════════════════════
    { name = "Aleppo",               zone = "ZONE_Aleppo",          coalition = "RED",     type = "AIRBASE", capturable = true  },
    { name = "Al Qusayr",            zone = "ZONE_AlQusayr",         coalition = "RED",     type = "AIRBASE", capturable = true  },
    { name = "Bassel Al-Assad",      zone = "ZONE_Latakia",          coalition = "RED",     type = "AIRBASE", capturable = true  },
    { name = "Damascus",             zone = "ZONE_Damascus",          coalition = "RED",     type = "AIRBASE", capturable = true  },
    { name = "Deir ez-Zor",         zone = "ZONE_DeirEzZor",         coalition = "RED",     type = "AIRBASE", capturable = true  },
    { name = "Hama",                 zone = "ZONE_Hama",              coalition = "RED",     type = "AIRBASE", capturable = true  },
    { name = "Jirah",                zone = "ZONE_Jirah",             coalition = "RED",     type = "AIRBASE", capturable = true  },
    { name = "Khalkhalah",           zone = "ZONE_Khalkhalah",        coalition = "RED",     type = "AIRBASE", capturable = true  },
    { name = "Kuweires",             zone = "ZONE_Kuweires",          coalition = "RED",     type = "AIRBASE", capturable = true  },
    { name = "Marj As Sultan North", zone = "ZONE_MarjAsNorth",       coalition = "RED",     type = "AIRBASE", capturable = true  },
    { name = "Marj As Sultan South", zone = "ZONE_MarjAsSouth",       coalition = "RED",     type = "AIRBASE", capturable = true  },
    { name = "Mezzeh",               zone = "ZONE_Mezzeh",            coalition = "RED",     type = "AIRBASE", capturable = true  },
    { name = "Minakh",               zone = "ZONE_Minakh",            coalition = "RED",     type = "AIRBASE", capturable = true  },
    { name = "Palmyra",              zone = "ZONE_Palmyra",           coalition = "RED",     type = "AIRBASE", capturable = true  },
    { name = "Qabr as Sitt",         zone = "ZONE_QabrAsSitt",        coalition = "RED",     type = "AIRBASE", capturable = true  },
    { name = "Rasin al Aboud",       zone = "ZONE_RasinAlAboud",      coalition = "RED",     type = "AIRBASE", capturable = true  },
    { name = "Shayrat",              zone = "ZONE_Shayrat",           coalition = "RED",     type = "AIRBASE", capturable = true  },
    { name = "Tabqa",                zone = "ZONE_Tabqa",             coalition = "RED",     type = "AIRBASE", capturable = true  },
    { name = "Taftanaz",             zone = "ZONE_Taftanaz",          coalition = "RED",     type = "AIRBASE", capturable = true  },
    { name = "Tiyas",                zone = "ZONE_Tiyas",             coalition = "RED",     type = "AIRBASE", capturable = true  },
    { name = "Al-Dumayr",            zone = "ZONE_AlDumayr",          coalition = "RED",     type = "AIRBASE", capturable = true  },
    { name = "Marj Ruhayyil",        zone = "ZONE_MarjRuhayyil",      coalition = "RED",     type = "AIRBASE", capturable = true  },

    -- ═══════════════════════════════════════════════════════════════════
    -- NEUTRAL / CIVILIAN AIRBASES  (start NEUTRAL)
    -- ═══════════════════════════════════════════════════════════════════
    { name = "Beirut-Rafic Hariri",         zone = "ZONE_Beirut",           coalition = "NEUTRAL", type = "AIRBASE", capturable = false  },
    { name = "Tel Aviv Yafo Ben Gurion",    zone = "ZONE_BenGurion",        coalition = "NEUTRAL", type = "AIRBASE", capturable = false }, -- Israeli sovereign, locked
    { name = "Haifa",                       zone = "ZONE_Haifa",            coalition = "NEUTRAL", type = "AIRBASE", capturable = false }, -- Israeli sovereign, locked

    -- ═══════════════════════════════════════════════════════════════════
    -- NATO / COALITION AIRBASES  (start BLUE, non-capturable)
    -- ═══════════════════════════════════════════════════════════════════
    { name = "Incirlik",                    zone = "ZONE_Incirlik",         coalition = "BLUE",    type = "AIRBASE", capturable = false },
    { name = "Hatay",                       zone = "ZONE_Hatay",            coalition = "BLUE",    type = "AIRBASE", capturable = false },
    { name = "Adana Sakirpasa",             zone = "ZONE_Adana",            coalition = "BLUE",    type = "AIRBASE", capturable = false },
    { name = "Ramat David",                 zone = "ZONE_RamatDavid",       coalition = "BLUE",    type = "AIRBASE", capturable = false },
    { name = "Ruwayshid",                   zone = "ZONE_Ruwayshid",        coalition = "BLUE",    type = "AIRBASE", capturable = false },
    { name = "King Hussein Air College",    zone = "ZONE_KingHussein",      coalition = "BLUE",    type = "AIRBASE", capturable = false },
    { name = "H4",                          zone = "ZONE_H4",               coalition = "BLUE",    type = "AIRBASE", capturable = false },
    { name = "H3",                          zone = "ZONE_H3",               coalition = "BLUE",    type = "AIRBASE", capturable = false },

    -- ═══════════════════════════════════════════════════════════════════
    -- FARP SLOTS  — leave blank here; use ABC.registerFARP() at runtime
    -- OR add entries below with positions supplied via a DO SCRIPT trigger
    -- ═══════════════════════════════════════════════════════════════════
    -- Example:
    -- { name = "FARP_Khanasir",  zone = "ZONE_FARP_Khanasir", coalition = "RED", type = "FARP", capturable = true },
}

------------------------------------------------------------------------
-- SECTION 3 : RUNTIME STATE  (internal — do not edit)
------------------------------------------------------------------------
ABC._state        = {}   -- [baseName] = state table
ABC._eventHandler = {}   -- DCS world event handler object
ABC._initialized  = false

------------------------------------------------------------------------
-- SECTION 4 : INTERNAL UTILITIES
------------------------------------------------------------------------

-- Safely retrieve a mission trigger zone; logs a warning if missing
local function getZone(name)
    if not name or name == "" then return nil end
    local z = trigger.misc.getZone(name)
    if not z then
        env.info("[ABC] WARNING: Trigger zone '" .. name .. "' not found. "
                 .. "Create it in the Mission Editor.", false)
    end
    return z
end

-- Count live units of coalition coalId inside a circular zone
-- coalId : coalition.side.RED (1) or coalition.side.BLUE (2)
local function countUnitsInZone(zone, coalId)
    if not zone then return 0 end
    local count   = 0
    local rsq     = zone.radius * zone.radius
    local zx, zy  = zone.point.x, zone.point.z
    local cats    = { Group.Category.GROUND }
    if ABC.CFG.SCAN_AIR then
        cats[#cats + 1] = Group.Category.AIRPLANE
        cats[#cats + 1] = Group.Category.HELICOPTER
    end
    for _, cat in ipairs(cats) do
        local groups = coalition.getGroups(coalId, cat)
        for _, g in ipairs(groups) do
            if g:isExist() then
                for _, u in ipairs(g:getUnits()) do
                    if u:isExist() and u:isActive() and u:getLife() > 0 then
                        local p  = u:getPoint()
                        local dx = p.x - zx
                        local dz = p.z - zy
                        if (dx * dx + dz * dz) <= rsq then
                            count = count + 1
                        end
                    end
                end
            end
        end
    end
    return count
end

-- Get (and cache) the world position of a base
local function getBasePos(entry, st)
    if st.pos then return st.pos end
    if entry.type == "AIRBASE" then
        local ab = Airbase.getByName(entry.name)
        if ab then
            st.pos = ab:getPoint()
            return st.pos
        end
    end
    return nil
end

------------------------------------------------------------------------
-- SECTION 5 : DRAWING SYSTEM
------------------------------------------------------------------------

-- Colour/fill table per logical status
local STATUS_COLORS = nil   -- built lazily after CFG is available

local function getColors(status)
    if not STATUS_COLORS then
        local C = ABC.CFG
        STATUS_COLORS = {
            RED       = { line = C.COLOR_RED,       fill = C.FILL_RED       },
            BLUE      = { line = C.COLOR_BLUE,      fill = C.FILL_BLUE      },
            NEUTRAL   = { line = C.COLOR_NEUTRAL,   fill = C.FILL_NEUTRAL   },
            DESTROYED = { line = C.COLOR_DESTROYED, fill = C.FILL_DESTROYED },
        }
    end
    return STATUS_COLORS[status] or STATUS_COLORS["NEUTRAL"]
end

-- Human-readable status tag shown on the F10 map label
local STATUS_LABEL = {
    RED       = "[ RED ]",
    BLUE      = "[ BLUE ]",
    NEUTRAL   = "[ NEUTRAL ]",
    DESTROYED = "[ DESTROYED ]",
}

-- Remove all F10 map marks belonging to a base state
local function clearMarks(st)
    if st.markIds then
        for _, mid in ipairs(st.markIds) do
            pcall(trigger.action.removeMark, mid)
        end
    end
    st.markIds = {}
end

-- Draw (or redraw) the circle and label for a base
local function drawBase(entry, st)
    local pos = getBasePos(entry, st)
    if not pos then return end

    clearMarks(st)

    local cols     = getColors(st.coalition)
    local circleId = st.baseMarkId
    local textId   = st.baseMarkId + 1
    local ALL      = -1   -- visible to all coalitions

    -- Filled circle outline
    trigger.action.circleToAll(
        ALL,
        circleId,
        pos,
        ABC.CFG.CIRCLE_RADIUS,
        cols.line,
        cols.fill,
        ABC.CFG.LINE_TYPE,
        true    -- readOnly: players cannot drag/delete it
    )

    -- Text label (name + status, with capture progress if applicable)
    local labelText = entry.name .. "\n" .. (STATUS_LABEL[st.coalition] or "[ ? ]")
    if (st.captureTicks or 0) > 0 and st.coalition == "NEUTRAL" then
        local pct = math.floor((st.captureTicks / ABC.CFG.CAPTURE_TICKS) * 100)
        labelText = labelText .. "\nCapturing... " .. pct .. "%"
    end

    local textPos = {
        x = pos.x,
        y = pos.y,
        z = pos.z - math.floor(ABC.CFG.CIRCLE_RADIUS * 0.55),
    }

    trigger.action.textToAll(
        ALL,
        textId,
        textPos,
        cols.line,
        { r = 0, g = 0, b = 0, a = 0 },    -- transparent background
        ABC.CFG.LABEL_FONT_SIZE,
        true,       -- readOnly
        labelText
    )

    st.markIds = { circleId, textId }
end

------------------------------------------------------------------------
-- SECTION 6 : COALITION STATE MACHINE
------------------------------------------------------------------------

-- Apply a new coalition to a base, redraw and announce
local function applyCoalition(entry, st, newCoal, announce)
    local prev     = st.coalition
    st.coalition   = newCoal
    st.captureTicks = 0
    drawBase(entry, st)

    if announce and prev ~= newCoal then
        local msg = string.format(
            "[AIRBASE CAPTURE]  %s  →  %s  (was %s)",
            entry.name, newCoal, prev
        )
        trigger.action.outText(msg, ABC.CFG.MSG_DURATION, false)
        env.info("[ABC] " .. msg, false)
    end

    -- Fire optional user callback
    if ABC.onCapture then
        pcall(ABC.onCapture, entry.name, prev, newCoal)
    end
end

-- Run one capture tick for a single base entry
local function tickBase(entry, st)
    -- Skip non-capturable and destroyed bases
    if not entry.capturable  then return end
    if st.coalition == "DESTROYED" then return end

    local zone = getZone(entry.zone)
    if not zone then return end

    local redCount  = countUnitsInZone(zone, coalition.side.RED)
    local blueCount = countUnitsInZone(zone, coalition.side.BLUE)
    local minU      = ABC.CFG.MIN_CAPTURE_UNITS

    local current = st.coalition

    -- ── RED base ────────────────────────────────────────────────────
    if current == "RED" then
        if redCount == 0 then
            -- No red defenders left → flip to neutral
            applyCoalition(entry, st, "NEUTRAL", true)
        end

    -- ── NEUTRAL base ─────────────────────────────────────────────────
    elseif current == "NEUTRAL" then
        if blueCount >= minU and redCount == 0 then
            -- Blue forces moving in unchallenged
            st.captureTicks = (st.captureTicks or 0) + 1
            drawBase(entry, st)     -- update capturing % label
            if st.captureTicks >= ABC.CFG.CAPTURE_TICKS then
                applyCoalition(entry, st, "BLUE", true)
            end

        elseif redCount >= minU and blueCount == 0 then
            -- Red forces reclaiming the neutral base
            st.captureTicks = (st.captureTicks or 0) + 1
            drawBase(entry, st)
            if st.captureTicks >= ABC.CFG.CAPTURE_TICKS then
                applyCoalition(entry, st, "RED", true)
            end

        else
            -- Contested (both present) or empty — reset capture progress
            if (st.captureTicks or 0) > 0 then
                st.captureTicks = 0
                drawBase(entry, st)
            end
        end

    -- ── BLUE base ───────────────────────────────────────────────────
    elseif current == "BLUE" then
        if blueCount == 0 then
            -- No blue defenders left → flip to neutral
            applyCoalition(entry, st, "NEUTRAL", true)
        end
    end
end

------------------------------------------------------------------------
-- SECTION 7 : MAIN SCAN LOOP
------------------------------------------------------------------------

local function scanAll(_, time)
    for _, entry in ipairs(ABC.REGISTRY) do
        local st = ABC._state[entry.name]
        if st then
            local ok, err = pcall(tickBase, entry, st)
            if not ok then
                env.info("[ABC] Error scanning " .. entry.name .. ": " .. tostring(err), false)
            end
        end
    end
    return time + ABC.CFG.CHECK_INTERVAL
end

------------------------------------------------------------------------
-- SECTION 8 : DCS EVENT HANDLER
-- Listens for S_EVENT_BASE_CAPTURED so DCS-engine capture events
-- (from ME airbase auto-capture settings) stay in sync with our state.
------------------------------------------------------------------------

function ABC._eventHandler:onEvent(event)
    if event.id ~= world.event.S_EVENT_BASE_CAPTURED then return end

    local ab = event.place
    if not ab then return end

    local abName = ab:getName()
    local st     = ABC._state[abName]
    if not st then return end

    -- Map DCS coalition ID to our string
    local dcsCoal  = ab:getCoalition()
    local coalStr  = "NEUTRAL"
    if dcsCoal == coalition.side.RED  then coalStr = "RED"
    elseif dcsCoal == coalition.side.BLUE then coalStr = "BLUE"
    end

    -- Sync only if DCS and our state disagree
    if st.coalition ~= coalStr then
        for _, e in ipairs(ABC.REGISTRY) do
            if e.name == abName then
                env.info(string.format(
                    "[ABC] DCS engine capture event: %s → %s (syncing script state)",
                    abName, coalStr), false)
                applyCoalition(e, st, coalStr, false)   -- no double-announce
                break
            end
        end
    end
end

------------------------------------------------------------------------
-- SECTION 9 : PUBLIC API
------------------------------------------------------------------------

--- Register a placed FARP at runtime.
-- Call from a DO SCRIPT trigger after placing the FARP in the ME.
-- @param farpName    string  : FARP unit/airbase name in DCS
-- @param zoneName    string  : Matching Trigger Zone name
-- @param startCoal   string  : "RED" | "BLUE" | "NEUTRAL"
-- @param pos         Vec3    : World position  (use Airbase.getByName(name):getPoint()
--                              or a static object's position)
-- Example:
--   ABC.registerFARP("FARP_Khanasir", "ZONE_FARP_Khanasir", "RED",
--                    Airbase.getByName("FARP_Khanasir"):getPoint())
function ABC.registerFARP(farpName, zoneName, startCoal, pos)
    if not farpName or not zoneName then
        env.info("[ABC] registerFARP: farpName and zoneName are required.", false)
        return
    end

    -- Check for duplicates
    for _, e in ipairs(ABC.REGISTRY) do
        if e.name == farpName then
            env.info("[ABC] registerFARP: '" .. farpName .. "' already registered.", false)
            return
        end
    end

    local entry = {
        name       = farpName,
        zone       = zoneName,
        coalition  = startCoal or "NEUTRAL",
        type       = "FARP",
        capturable = true,
    }
    ABC.REGISTRY[#ABC.REGISTRY + 1] = entry

    -- Allocate mark IDs
    local markId = ABC.CFG.BASE_MARK_OFFSET
                   + (#ABC.REGISTRY * ABC.CFG.MARKS_PER_BASE)

    local st = {
        coalition    = entry.coalition,
        captureTicks  = 0,
        baseMarkId   = markId,
        markIds      = {},
        pos          = pos,
    }
    ABC._state[farpName] = st
    drawBase(entry, st)

    env.info(string.format("[ABC] FARP registered: %s (%s)", farpName, entry.coalition), false)
end

--- Mark a base as DESTROYED (unusable). Call from a trigger or another script.
-- The destroyed state disables capture logic but keeps the marker visible.
-- @param baseName string : exact name as listed in the registry
function ABC.setDestroyed(baseName)
    local st = ABC._state[baseName]
    if not st then
        env.info("[ABC] setDestroyed: unknown base '" .. baseName .. "'", false)
        return
    end
    st.coalition    = "DESTROYED"
    st.captureTicks  = 0
    for _, entry in ipairs(ABC.REGISTRY) do
        if entry.name == baseName then
            drawBase(entry, st)
            trigger.action.outText(
                "[AIRBASE DESTROYED]  " .. baseName .. "  is no longer operational.",
                ABC.CFG.MSG_DURATION, false
            )
            env.info("[ABC] Base destroyed: " .. baseName, false)
            return
        end
    end
end

--- Force a base coalition from an external script or trigger.
-- @param baseName  string : base name
-- @param coalStr   string : "RED" | "BLUE" | "NEUTRAL"
function ABC.forceCoalition(baseName, coalStr)
    local st = ABC._state[baseName]
    if not st then
        env.info("[ABC] forceCoalition: unknown base '" .. baseName .. "'", false)
        return
    end
    for _, e in ipairs(ABC.REGISTRY) do
        if e.name == baseName then
            applyCoalition(e, st, coalStr, true)
            return
        end
    end
end

--- Query the current logical owner of a base.
-- @param baseName string
-- @return "RED" | "BLUE" | "NEUTRAL" | "DESTROYED" | nil
function ABC.getOwner(baseName)
    local st = ABC._state[baseName]
    return st and st.coalition or nil
end

--- Redraw all F10 map markers (useful after a mission load or map reset).
function ABC.redrawAll()
    for _, entry in ipairs(ABC.REGISTRY) do
        local st = ABC._state[entry.name]
        if st then
            local ok, err = pcall(drawBase, entry, st)
            if not ok then
                env.info("[ABC] redrawAll error on " .. entry.name .. ": " .. tostring(err), false)
            end
        end
    end
    env.info("[ABC] All base markers redrawn.", false)
end

--- Optional callback — assign a function to be called on every capture.
-- Signature:  function(baseName, prevCoalition, newCoalition) … end
-- ABC.onCapture = function(base, from, to)
--     if to == "BLUE" then missionScore = missionScore + 100 end
-- end
ABC.onCapture = nil

------------------------------------------------------------------------
-- SECTION 10 : INITIALISATION
------------------------------------------------------------------------

function ABC.init()
    if ABC._initialized then
        env.info("[ABC] Already initialised — skipping.", false)
        return
    end

    env.info("[ABC] ══════════════════════════════════════════", false)
    env.info("[ABC]  Syria Airbase Capture System  v1.0", false)
    env.info("[ABC] ══════════════════════════════════════════", false)

    -- Reset colour cache so CFG changes take effect
    STATUS_COLORS = nil

    -- Build initial state for every registry entry
    for i, entry in ipairs(ABC.REGISTRY) do
        -- Unique mark ID block for this base
        local markId = ABC.CFG.BASE_MARK_OFFSET + (i * ABC.CFG.MARKS_PER_BASE)

        local pos = nil
        if entry.type == "AIRBASE" then
            local ab = Airbase.getByName(entry.name)
            if ab then
                pos = ab:getPoint()
                -- Disable DCS engine auto-capture so this script has full control.
                -- Comment out the two lines below if you want DCS engine capture
                -- to run in PARALLEL with script state (both will work, state syncs
                -- via S_EVENT_BASE_CAPTURED).
                if ab.autoCapture then
                    pcall(function() ab:autoCapture(false) end)
                end
            else
                env.info("[ABC] WARNING: '" .. entry.name
                         .. "' not found as a DCS airbase object. "
                         .. "Zone scanning will still work; no position for drawing.", false)
            end
        end
        -- Note: FARPs registered here without a pos will get it when
        -- ABC.registerFARP() is called, which also creates the state entry.
        -- We still create a placeholder so tickBase works even if pos is nil.

        ABC._state[entry.name] = {
            coalition    = entry.coalition,
            captureTicks  = 0,
            baseMarkId   = markId,
            markIds      = {},
            pos          = pos,
        }

        -- Draw initial marker (skipped silently if pos is nil)
        if pos then
            local ok, err = pcall(drawBase, entry, ABC._state[entry.name])
            if not ok then
                env.info("[ABC] Draw error for " .. entry.name .. ": " .. tostring(err), false)
            end
        end
    end

    -- Register the DCS event handler
    world.addEventHandler(ABC._eventHandler)

    -- Start the scan loop (first tick after 10 s to let mission settle)
    timer.scheduleFunction(scanAll, nil, timer.getTime() + 10)

    ABC._initialized = true
    env.info(string.format(
        "[ABC] Initialised. %d bases tracked. Scan interval: %ds. Capture ticks: %d.",
        #ABC.REGISTRY, ABC.CFG.CHECK_INTERVAL, ABC.CFG.CAPTURE_TICKS
    ), false)
    env.info("[ABC] ══════════════════════════════════════════", false)
end

------------------------------------------------------------------------
-- SECTION 11 : QUICK REFERENCE
------------------------------------------------------------------------
--[[
  MISSION EDITOR SETUP CHECKLIST
  ────────────────────────────────────────────────────────────────────
  1. Place a Trigger Zone over each airbase / FARP you want capturable.
     Name the zone exactly as listed in the 'zone' field of REGISTRY,
     e.g.  "ZONE_Tiyas"  for the Tiyas (T4) airbase entry.

  2. Create a MISSION START trigger with these DO SCRIPT FILE actions
     IN THIS ORDER:
       a) mist_4_5_126.lua
       b) SYRIA_AirbaseCapture.lua

  3. (Optional) For each FARP you place, add a delayed DO SCRIPT trigger
     (5 s after start) with:
       ABC.registerFARP("FARP_MyBase", "ZONE_FARP_MyBase", "RED",
                        Airbase.getByName("FARP_MyBase"):getPoint())

  4. (Optional) To mark a base destroyed from a trigger condition:
       ABC.setDestroyed("Palmyra")

  5. (Optional) To check who owns a base from another script:
       if ABC.getOwner("Tiyas") == "BLUE" then … end

  ZONE NAMING CONVENTION USED IN THIS SCRIPT
  ────────────────────────────────────────────────────────────────────
    Airbases  → ZONE_<AirbaseName>  (no spaces — use CamelCase)
    FARPs     → ZONE_FARP_<Name>

  ADDING A NEW BASE
  ────────────────────────────────────────────────────────────────────
  Add an entry to ABC.REGISTRY:
    { name="MyAirbase", zone="ZONE_MyAirbase", coalition="RED",
      type="AIRBASE", capturable=true }

  Then add a matching Trigger Zone in the ME named "ZONE_MyAirbase".

  INTEGRATION WITH SYRIA_IADS SCRIPT
  ────────────────────────────────────────────────────────────────────
  No special integration code required. The IADS script runs its own
  periodic node-list rebuild every 15 minutes (NODE_REFRESH_INTERVAL),
  which automatically drops any SAM / EWR groups that have been
  destroyed since the last refresh. SAM sites are one-and-done — once
  dead they are simply absent from the next rebuild and ignored.
--]]

------------------------------------------------------------------------
-- AUTO-BOOT
------------------------------------------------------------------------
ABC.init()

return ABC
