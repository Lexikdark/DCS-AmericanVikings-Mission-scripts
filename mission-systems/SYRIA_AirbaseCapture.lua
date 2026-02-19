------------------------------------------------------------------------
-- SYRIA_AirbaseCapture.lua
-- Dynamic Airbase & FARP Capture System — Syria Map
-- Version : 1.0  |  Date : 2026-02-18
------------------------------------------------------------------------
-- STANDALONE — no other script required.
-- LOAD ORDER in Mission Editor (DO SCRIPT FILE triggers):
--   1. SYRIA_AirbaseCapture.lua
--   (MIST is NOT required by this script)
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

    -- Outline colours  {r, g, b, a}  positional array — DCS requires numeric indices
    COLOR_RED         = {1.00, 0.00, 0.00, 1.00},  -- normal red ring
    COLOR_BLUE        = {0.00, 0.40, 1.00, 1.00},  -- normal blue ring
    COLOR_NEUTRAL     = {1.00, 1.00, 1.00, 1.00},  -- white ring
    COLOR_DESTROYED   = {0.00, 0.00, 0.00, 1.00},  -- black ring

    -- Fill colours — diffuse, low alpha
    FILL_RED          = {0.55, 0.00, 0.00, 0.15},  -- dark red
    FILL_BLUE         = {0.00, 0.00, 0.65, 0.15},  -- dark blue
    FILL_NEUTRAL      = {0.40, 0.40, 0.40, 0.15},  -- slightly darker gray
    FILL_DESTROYED    = {0.00, 0.00, 0.00, 0.15},  -- black

    -- ── Mark ID Allocation ────────────────────────────────────────────
    -- Each base reserves MARKS_PER_BASE IDs starting from BASE_MARK_OFFSET.
    -- Change BASE_MARK_OFFSET if it conflicts with other scripts' mark IDs.
    BASE_MARK_OFFSET    = 6000,
    MARKS_PER_BASE      = 3,      -- slot 0=circleToAll fill, 1=textToAll label, 2=spare
    DESTROY_MARK_OFFSET = 7000,   -- separate ID block for DESTROY_ZONE_* entries (max 333 destroy zones)

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
    -- RED-HELD AIRBASES & FARP PADS  (start RED)
    -- Uses CAPTURE_ZONE_* trigger zones placed in the ME to define capture areas.
    -- used by RED_BLUE_IADS_Intercept.lua. Create these zones in the ME.
    -- ═══════════════════════════════════════════════════════════════════

    -- Damascus sector
    { name = "Mezzeh",          zone = "CAPTURE_ZONE_MEZZEH",           coalition = "RED", type = "AIRBASE", capturable = true },
    { name = "Damascus",        zone = "CAPTURE_ZONE_DAMASCUS",         coalition = "RED", type = "AIRBASE", capturable = true },

    -- Southern Syria / Jordan border
    { name = "Marj Ruhayyil",   zone = "CAPTURE_ZONE_MARJ_RUHAYYIL",   coalition = "RED", type = "AIRBASE", capturable = true },
    { name = "An Nasiriyah",    zone = "CAPTURE_ZONE_AN_NASIRIYAH",     coalition = "RED", type = "AIRBASE", capturable = true },

    { name = "Khalkhalah",      zone = "CAPTURE_ZONE_KHALKHALAH",       coalition = "RED", type = "AIRBASE", capturable = true },
    { name = "At Tanf",         zone = "CAPTURE_ZONE_AT_TANF",          coalition = "RED", type = "AIRBASE", capturable = true },
    { name = "Sayqal",          zone = "CAPTURE_ZONE_SAYQAL",           coalition = "RED", type = "AIRBASE", capturable = true },

    -- Central Syria
    { name = "Tha'lah",         zone = "CAPTURE_ZONE_THALAH",           coalition = "RED", type = "AIRBASE", capturable = true },
    { name = "Palmyra",         zone = "CAPTURE_ZONE_PALMYRA",          coalition = "RED", type = "AIRBASE", capturable = true },
    { name = "Shayrat",         zone = "CAPTURE_ZONE_SHAYRAT",          coalition = "RED", type = "AIRBASE", capturable = true },
    { name = "Tabqa",           zone = "CAPTURE_ZONE_TABQA",            coalition = "RED", type = "AIRBASE", capturable = true },
    { name = "Hama",            zone = "CAPTURE_ZONE_HAMA",             coalition = "RED", type = "AIRBASE", capturable = true },

    -- Eastern Syria
    { name = "Deir ez-Zor",     zone = "CAPTURE_ZONE_DEIR_EZ-ZOR",      coalition = "RED", type = "AIRBASE", capturable = true },

    -- Northern Syria
    { name = "Aleppo",          zone = "CAPTURE_ZONE_ALEPPO",           coalition = "RED", type = "AIRBASE", capturable = true },

    -- Coastal / Latakia sector
    { name = "Al Qusayr",       zone = "CAPTURE_ZONE_AL_QUSAYR",        coalition = "RED", type = "AIRBASE", capturable = true },
    { name = "Bassel Al-Assad", zone = "CAPTURE_ZONE_BASSEL_AL_ASSAD",  coalition = "RED", type = "AIRBASE", capturable = true },

    -- ═══════════════════════════════════════════════════════════════════
    -- BLUE FOB / FARP PLACEHOLDERS  (start NEUTRAL, capturable)
    -- Replace name and zone strings once the FOBs are placed in the ME.
    -- Call ABC.registerFARP(name, zone, "NEUTRAL", pos) at runtime,
    -- or simply add them here and let init() handle them via AIRBASE lookup
    -- if they have a proper DCS Airbase/FARP object.
    -- ═══════════════════════════════════════════════════════════════════
    { name = "FOB_Alpha",   zone = "CAPTURE_ZONE_FOB_Alpha",   coalition = "NEUTRAL", type = "FARP", capturable = true },
    { name = "FOB_Bravo",   zone = "CAPTURE_ZONE_FOB_Bravo",   coalition = "NEUTRAL", type = "FARP", capturable = true },
    { name = "FOB_Charlie", zone = "CAPTURE_ZONE_FOB_Charlie", coalition = "NEUTRAL", type = "FARP", capturable = true },
    { name = "FOB_Delta",   zone = "CAPTURE_ZONE_FOB_Delta",   coalition = "NEUTRAL", type = "FARP", capturable = true },
    { name = "FOB_Echo",    zone = "CAPTURE_ZONE_FOB_Echo",    coalition = "NEUTRAL", type = "FARP", capturable = true },
    { name = "FOB_Foxtrot", zone = "CAPTURE_ZONE_FOB_Foxtrot", coalition = "NEUTRAL", type = "FARP", capturable = true },

    -- ═══════════════════════════════════════════════════════════════════
    -- FARP SLOTS  — leave blank here; use ABC.registerFARP() at runtime
    -- OR add entries below with positions supplied via a DO SCRIPT trigger
    -- ═══════════════════════════════════════════════════════════════════
    -- Example:
    -- { name = "FARP_Khanasir",  zone = "ZONE_FARP_Khanasir", coalition = "RED", type = "FARP", capturable = true },
}

------------------------------------------------------------------------
-- SECTION 2b : DESTROY ZONE REGISTRY
------------------------------------------------------------------------
-- These zones represent RED target sets (SAM sites, command posts, etc.)
-- that players are tasked with destroying.
--
-- Fields:
--   name  : Display name shown on the F10 map
--   zone  : DESTROY_ZONE_* trigger zone in the Mission Editor
--
-- Behaviour:
--   • Draws a RED circle on the F10 map (same style as RED airbases).
--   • Every CHECK_INTERVAL seconds the script counts RED units inside.
--   • When the RED unit count reaches 0 the circle permanently turns
--     BLACK and the label shows "Destroyed".
--   • The zone CANNOT be recaptured or flipped by any coalition.
--
-- ME SETUP:
--   1. Place a Trigger Zone named  DESTROY_ZONE_<YourName>  over the
--      unit group you want tracked.
--   2. Add an entry below.  The zone radius should cover all units in
--      the group (the drawn circle will match the zone exactly).
------------------------------------------------------------------------
ABC.DESTROY_REGISTRY = {

    -- ═══════════════════════════════════════════════════════════════════
    -- RED TARGET ZONES  (permanently destroyed when all units are killed)
    -- ═══════════════════════════════════════════════════════════════════
    -- Examples — uncomment and fill in your zone names:
    { name = "SAM Site Alpha",    zone = "DESTROY_ZONE_SAM_ALPHA"    },
    { name = "SAM Site Bravo",    zone = "DESTROY_ZONE_SAM_BRAVO"    },
    { name = "SAM Site Charlie", zone = "DESTROY_ZONE_SAM_CHARLIE" },
    { name = "SAM Site Delta",   zone = "DESTROY_ZONE_SAM_DELTA"   },
    { name = "SAM Site Echo", zone = "DESTROY_ZONE_SAM_ECHO"     },
    { name = "SAM Site Foxtrot", zone = "DESTROY_ZONE_SAM_FOXTROT"   },
    { name = "SAM Site Golf",    zone = "DESTROY_ZONE_SAM_GOLF"     },
    { name = "SAM Site Hotel",   zone = "DESTROY_ZONE_SAM_HOTEL"    },
    { name = "SAM Site India",   zone = "DESTROY_ZONE_SAM_INDIA"    },
}

------------------------------------------------------------------------
-- SECTION 3 : RUNTIME STATE  (internal — do not edit)
------------------------------------------------------------------------
ABC._state        = {}   -- [baseName] = state table
ABC._destroyState = {}   -- [name]     = destroy-zone state table
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

-- Get (and cache) the world position of a base.
-- Priority: cached pos → DCS Airbase object → trigger zone centre.
local function getBasePos(entry, st)
    if st.pos then return st.pos end
    -- 1. Try DCS airbase object (works for all named Syria airbases)
    if entry.type == "AIRBASE" then
        local ab = Airbase.getByName(entry.name)
        if ab then
            st.pos = ab:getPoint()
            return st.pos
        end
    end
    -- 2. Fallback: use the centre of the trigger zone for drawing
    --    (covers FARPs and any airbase whose DCS name didn't resolve)
    if entry.zone and entry.zone ~= "" then
        local z = trigger.misc.getZone(entry.zone)
        if z and z.point then
            st.pos = { x = z.point.x, y = z.point.y or 0, z = z.point.z }
            return st.pos
        end
    end
    return nil
end

------------------------------------------------------------------------
-- SECTION 5 : DRAWING SYSTEM
------------------------------------------------------------------------
-- Previous attempts failed because colour tables used NAMED keys
-- {r=..., g=..., b=..., a=...} — DCS requires POSITIONAL arrays
-- {r, g, b, a} (indices 1,2,3,4).  CFG colours are now positional.
--
-- Mark ID layout per base  (MARKS_PER_BASE = 3):
--   baseMarkId + 0  = circleToAll  (filled circle, solid outline)
--   baseMarkId + 1  = textToAll    (name + coalition label)
--   baseMarkId + 2  = spare
------------------------------------------------------------------------

-- Colour/fill table per logical status (built lazily after CFG loads)
local STATUS_COLORS = nil
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

-- Remove every F10 mark belonging to a base state entry
local function clearMarks(st)
    if st.markIds then
        for _, mid in ipairs(st.markIds) do
            pcall(trigger.action.removeMark, mid)
        end
    end
    st.markIds = {}
end

-- Draw (or redraw) the filled circle + label for one base entry.
-- Position and radius come from the CAPTURE_ZONE trigger zone in the ME,
-- so the drawn circle exactly matches what is placed in the mission.
local function drawBase(entry, st)
    -- Primary: use the trigger zone's own centre and radius.
    local drawPos    = nil
    local drawRadius = ABC.CFG.CIRCLE_RADIUS  -- fallback if zone not found

    if entry.zone and entry.zone ~= "" then
        local z = trigger.misc.getZone(entry.zone)
        if z and z.point then
            drawPos    = { x = z.point.x, y = z.point.y or 0, z = z.point.z }
            drawRadius = z.radius or ABC.CFG.CIRCLE_RADIUS
        end
    end

    -- Fallback: DCS airbase object / previously cached position
    if not drawPos then
        drawPos = getBasePos(entry, st)
    end

    if not drawPos then
        env.info("[ABC] drawBase: no position for " .. entry.name .. " — skipping.", false)
        return
    end

    clearMarks(st)

    local cols   = getColors(st.coalition)
    local fillId = st.baseMarkId       -- slot 0: circleToAll
    local textId = st.baseMarkId + 1   -- slot 1: textToAll

    -- Filled circle — radius matches the ME trigger zone exactly
    trigger.action.circleToAll(
        -1, fillId, drawPos,
        drawRadius,
        cols.line, cols.fill,
        ABC.CFG.LINE_TYPE, true)

    -- Text label — black text, offset slightly right of centre.
    -- Destroyed bases get a yellow "Destroyed" sub-line instead of a status tag.
    local TEXT_BLACK  = {0.00, 0.00, 0.00, 1.00}
    local TEXT_YELLOW = {1.00, 0.95, 0.00, 1.00}
    local textColor   = (st.coalition == "DESTROYED") and TEXT_YELLOW or TEXT_BLACK

    local labelText = entry.name
    if st.coalition == "DESTROYED" then
        labelText = entry.name .. "\nDestroyed"
    elseif (st.captureTicks or 0) > 0 then
        local pct = math.floor((st.captureTicks / ABC.CFG.CAPTURE_TICKS) * 100)
        labelText = entry.name .. "\nCapturing... " .. pct .. "%"
    end

    -- Offset: nudge right (+x) and slightly north (-z) of centre
    local offset = math.max(drawRadius * 0.12, 400)
    local textPos = { x = drawPos.x + offset, y = drawPos.y, z = drawPos.z - offset * 0.5 }
    trigger.action.textToAll(
        -1, textId, textPos,
        textColor, {0, 0, 0, 0},
        ABC.CFG.LABEL_FONT_SIZE, true, labelText)

    st.markIds = { fillId, textId }
end

-- Fast initial coalition check — called once during init() for each entry
-- BEFORE the first draw, so the opening map shows the true mission state.
-- RED/BLUE bases that have no defending units show immediately as NEUTRAL.
local function initCoalitionCheck(entry, st)
    if not entry.capturable then return end
    local zone = getZone(entry.zone)
    if not zone then return end
    local redCount  = countUnitsInZone(zone, coalition.side.RED)
    local blueCount = countUnitsInZone(zone, coalition.side.BLUE)
    if st.coalition == "RED"  and redCount  == 0 then st.coalition = "NEUTRAL" end
    if st.coalition == "BLUE" and blueCount == 0 then st.coalition = "NEUTRAL" end
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
    -- ── Airbase / FARP capture scan ──────────────────────────────────
    for _, entry in ipairs(ABC.REGISTRY) do
        local st = ABC._state[entry.name]
        if st then
            local ok, err = pcall(tickBase, entry, st)
            if not ok then
                env.info("[ABC] Error scanning " .. entry.name .. ": " .. tostring(err), false)
            end
        end
    end

    -- ── Destroy zone scan ────────────────────────────────────────────
    -- When all RED units inside a DESTROY_ZONE_* are dead, flip to DESTROYED.
    for _, entry in ipairs(ABC.DESTROY_REGISTRY) do
        local dst = ABC._destroyState[entry.name]
        if dst and dst.active then
            local ok, err = pcall(function()
                local zone = trigger.misc.getZone(entry.zone)
                if not zone then return end
                local redCount = countUnitsInZone(zone, coalition.side.RED)
                if redCount == 0 then
                    dst.active    = false
                    dst.coalition = "DESTROYED"
                    drawBase(entry, dst)
                    trigger.action.outText(
                        "[TARGET DESTROYED]  " .. entry.name .. "  has been neutralised.",
                        ABC.CFG.MSG_DURATION, false)
                    env.info("[ABC] Destroy zone cleared: " .. entry.name, false)
                end
            end)
            if not ok then
                env.info("[ABC] Error checking destroy zone " .. entry.name .. ": " .. tostring(err), false)
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

--- Set (force) the owning coalition of any registered base or FARP.
-- Use this from ME triggers or other scripts to hard-assign ownership,
-- e.g. after a scripted event, a mission objective, or on mission start.
-- Announces the change in-game and redraws the F10 map marker.
--
-- @param baseName  string  : exact name from the REGISTRY (or registerFARP)
-- @param coalition string  : "RED" | "BLUE" | "NEUTRAL"
--
-- Example — from a DO SCRIPT trigger:
--   ABC.setOwner("Palmyra",  "BLUE")    -- Blue just secured Palmyra
--   ABC.setOwner("Tabqa",    "NEUTRAL") -- Tabqa has fallen, no owner yet
--   ABC.setOwner("At Tanf",  "RED")     -- Red retook At Tanf
function ABC.setOwner(baseName, coal)
    local st = ABC._state[baseName]
    if not st then
        env.info("[ABC] setOwner: unknown base '" .. tostring(baseName) .. "'", false)
        return
    end
    for _, e in ipairs(ABC.REGISTRY) do
        if e.name == baseName then
            applyCoalition(e, st, coal, true)
            return
        end
    end
    env.info("[ABC] setOwner: '" .. baseName .. "' found in state but not REGISTRY.", false)
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

        -- For AIRBASEs: disable DCS engine auto-capture so this script has
        -- full control. Comment out the pcall below if you want DCS engine
        -- capture to run in PARALLEL (state syncs via S_EVENT_BASE_CAPTURED).
        if entry.type == "AIRBASE" then
            local ab = Airbase.getByName(entry.name)
            if ab then
                if ab.autoCapture then
                    pcall(function() ab:autoCapture(false) end)
                end
            else
                env.info("[ABC] WARNING: '" .. entry.name
                         .. "' not found as a DCS airbase object. "
                         .. "Will fall back to zone centre for drawing.", false)
            end
        end

        ABC._state[entry.name] = {
            coalition    = entry.coalition,
            captureTicks  = 0,
            baseMarkId   = markId,
            markIds      = {},
            pos          = nil,   -- resolved lazily by getBasePos()
        }

        -- Fast init scan: correct coalition BEFORE drawing so the first
        -- frame shows accurate state (RED bases with no units → NEUTRAL).
        pcall(initCoalitionCheck, entry, ABC._state[entry.name])

        -- Draw initial marker using zone centre + zone radius from ME.
        local ok, err = pcall(drawBase, entry, ABC._state[entry.name])
        if not ok then
            env.info("[ABC] Draw error for " .. entry.name .. ": " .. tostring(err), false)
        end
    end

    -- ── Destroy zone initialisation ──────────────────────────────────
    for i, entry in ipairs(ABC.DESTROY_REGISTRY) do
        local markId = ABC.CFG.DESTROY_MARK_OFFSET + (i * ABC.CFG.MARKS_PER_BASE)
        -- Check current unit count so a zone that starts empty is already DESTROYED
        local startCoal = "RED"
        local isActive  = true
        local zone = trigger.misc.getZone(entry.zone)
        if zone and countUnitsInZone(zone, coalition.side.RED) == 0 then
            startCoal = "DESTROYED"
            isActive  = false
        end
        if not zone then
            env.info("[ABC] WARNING: Destroy zone '" .. entry.zone .. "' not found in ME.", false)
        end
        ABC._destroyState[entry.name] = {
            coalition    = startCoal,
            captureTicks = 0,
            baseMarkId   = markId,
            markIds      = {},
            pos          = nil,
            active       = isActive,
        }
        local ok, err = pcall(drawBase, entry, ABC._destroyState[entry.name])
        if not ok then
            env.info("[ABC] Draw error for destroy zone " .. entry.name .. ": " .. tostring(err), false)
        end
    end
    env.info(string.format("[ABC] %d destroy zones registered.", #ABC.DESTROY_REGISTRY), false)

    -- Register the DCS event handler
    world.addEventHandler(ABC._eventHandler)

    -- Start the scan loop (first tick after 10 s to let mission settle)
    timer.scheduleFunction(scanAll, nil, timer.getTime() + 10)

    ABC._initialized = true
    env.info(string.format(
        "[ABC] Initialised. %d bases tracked, %d destroy zones. Scan interval: %ds. Capture ticks: %d.",
        #ABC.REGISTRY, #ABC.DESTROY_REGISTRY, ABC.CFG.CHECK_INTERVAL, ABC.CFG.CAPTURE_TICKS
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

  2. Create a MISSION START trigger with this DO SCRIPT FILE action:
       a) SYRIA_AirbaseCapture.lua
     (No other scripts required — MIST is not needed)

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
