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
    CAPTURE_TICKS     = 1,      -- single-tick capture: flip immediately on scan
    MIN_CAPTURE_UNITS = 1,      -- minimum ground units required to start capture

    -- ── Scanning ──────────────────────────────────────────────────────
    SCAN_AIR          = false,  -- true = aircraft count toward zone presence
                                -- false = ground units only (realistic default)

    -- ── Map Drawing ───────────────────────────────────────────────────
    -- Circle size is controlled by the radius of the Trigger Zone in the ME.
    -- CIRCLE_RADIUS is ONLY a last-resort fallback if a zone is missing.
    -- Do NOT use this value to size your circles — size them in the ME.
    CIRCLE_RADIUS     = 1000,   -- emergency fallback only; set zone radii in ME
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
    -- BASE_MARK_OFFSET seeds the auto-incrementing mark ID counter.
    -- drawBase() always generates fresh IDs via newMarkId() — IDs are
    -- never reused, which avoids the DCS "same-frame ID reuse" silent drop.
    -- Change BASE_MARK_OFFSET if it conflicts with other scripts' mark IDs.
    BASE_MARK_OFFSET    = 6000,

    -- ── Messages ──────────────────────────────────────────────────────
    MSG_DURATION      = 12,     -- seconds the capture announcement shows

    -- ── Diagnostics ───────────────────────────────────────────────────
    -- Set true to write verbose per-base-per-scan logs to dcs.log.
    -- Useful for diagnosing draw / capture / helipad coalition failures.
    -- Set false in production to reduce log noise and Lua overhead.
    DEBUG_MODE        = false,
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
-- TIP: The Trigger Zone radius in the ME controls BOTH the capture detection
--      area AND the visual circle drawn on the F10 map. One zone does both.
--      Set it to whatever you want the player to see on the map.
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
    { name = "Marj Ruhayyil",   zone = "CAPTURE_ZONE_MARJ_RUHAYYIL",    coalition = "RED", type = "AIRBASE", capturable = true },
    { name = "An Nasiriyah",    zone = "CAPTURE_ZONE_AN_NASIRIYAH",     coalition = "RED", type = "AIRBASE", capturable = true },
    { name = "Khalkhalah",      zone = "CAPTURE_ZONE_KHALKHALAH",       coalition = "RED", type = "AIRBASE", capturable = true },
    { name = "At Tanf",         zone = "CAPTURE_ZONE_AT_TANF",          coalition = "RED", type = "AIRBASE", capturable = true },
    { name = "Sayqal",          zone = "CAPTURE_ZONE_SAYQAL",           coalition = "RED", type = "AIRBASE", capturable = true },
    { name = "Tha'lah",         zone = "CAPTURE_ZONE_THALAH",           coalition = "RED", type = "AIRBASE", capturable = true },
    { name = "Palmyra",         zone = "CAPTURE_ZONE_PALMYRA",          coalition = "RED", type = "AIRBASE", capturable = true },
    { name = "Shayrat",         zone = "CAPTURE_ZONE_SHAYRAT",          coalition = "RED", type = "AIRBASE", capturable = true },
    { name = "Tabqa",           zone = "CAPTURE_ZONE_TABQA",            coalition = "RED", type = "AIRBASE", capturable = true },
    { name = "Hama",            zone = "CAPTURE_ZONE_HAMA",             coalition = "RED", type = "AIRBASE", capturable = true },
    { name = "Deir ez-Zor",     zone = "CAPTURE_ZONE_DEIR_EZ-ZOR",      coalition = "RED", type = "AIRBASE", capturable = true },
    { name = "Aleppo",          zone = "CAPTURE_ZONE_ALEPPO",           coalition = "RED", type = "AIRBASE", capturable = true },
    { name = "Al Qusayr",       zone = "CAPTURE_ZONE_AL_QUSAYR",        coalition = "RED", type = "AIRBASE", capturable = true },
    { name = "Bassel Al-Assad", zone = "CAPTURE_ZONE_BASSEL_AL_ASSAD",  coalition = "RED", type = "AIRBASE", capturable = true },

    -- ═══════════════════════════════════════════════════════════════════
    -- BLUE FOB / FARP PLACEHOLDERS  (start NEUTRAL, capturable)
    -- Replace name and zone strings once the FOBs are placed in the ME.
    -- Call ABC.registerFARP(name, zone, "NEUTRAL", pos) at runtime,
    -- or simply add them here and let init() handle them via AIRBASE lookup
    -- if they have a proper DCS Airbase/FARP object.
    --
    -- activateGroups (optional) — list of exact ME group names for Late-Activated
    -- BLUE unit groups.  When Blue captures the FOB every group in the list is
    -- activated automatically (garrison, HIMARS, mortars, etc.).
    -- Leave as nil or an empty table if no groups are needed for that FOB.
    -- ═══════════════════════════════════════════════════════════════════
    { name = "FOB_Alpha",   zone = "CAPTURE_ZONE_FOB_Alpha",   coalition = "NEUTRAL", type = "FARP", capturable = true, activateGroups = {"GARRISON_FOB_Alpha",   "HIMARS_FOB_Alpha",   "MORTAR_FOB_Alpha"}   },
    { name = "FOB_Bravo",   zone = "CAPTURE_ZONE_FOB_Bravo",   coalition = "NEUTRAL", type = "FARP", capturable = true, activateGroups = {"GARRISON_FOB_Bravo",   "HIMARS_FOB_Bravo",   "MORTAR_FOB_Bravo"}   },
    { name = "FOB_Charlie", zone = "CAPTURE_ZONE_FOB_Charlie", coalition = "NEUTRAL", type = "FARP", capturable = true, activateGroups = {"GARRISON_FOB_Charlie", "HIMARS_FOB_Charlie", "MORTAR_FOB_Charlie"} },
    { name = "FOB_Delta",   zone = "CAPTURE_ZONE_FOB_Delta",   coalition = "NEUTRAL", type = "FARP", capturable = true, activateGroups = {"GARRISON_FOB_Delta",   "HIMARS_FOB_Delta",   "MORTAR_FOB_Delta"}   },
    { name = "FOB_Echo",    zone = "CAPTURE_ZONE_FOB_Echo",    coalition = "NEUTRAL", type = "FARP", capturable = true, activateGroups = {"GARRISON_FOB_Echo",    "HIMARS_FOB_Echo",    "MORTAR_FOB_Echo"}    },
    { name = "FOB_Foxtrot", zone = "CAPTURE_ZONE_FOB_Foxtrot", coalition = "NEUTRAL", type = "FARP", capturable = true, activateGroups = {"GARRISON_FOB_Foxtrot", "HIMARS_FOB_Foxtrot", "MORTAR_FOB_Foxtrot"} },
    { name = "FOB_Hotel",   zone = "CAPTURE_ZONE_FOB_Hotel",   coalition = "NEUTRAL", type = "FARP", capturable = true, activateGroups = {"GARRISON_FOB_Hotel",   "HIMARS_FOB_Hotel",   "MORTAR_FOB_Hotel"}   },
    { name = "FOB_Golf",    zone = "CAPTURE_ZONE_FOB_Golf",    coalition = "NEUTRAL", type = "FARP", capturable = true, activateGroups = {"GARRISON_FOB_Golf",    "HIMARS_FOB_Golf",    "MORTAR_FOB_Golf"}    },
    { name = "FOB_India",   zone = "CAPTURE_ZONE_FOB_India",   coalition = "NEUTRAL", type = "FARP", capturable = true, activateGroups = {"GARRISON_FOB_India",   "HIMARS_FOB_India",   "MORTAR_FOB_India"}   },

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
    { name = "SAM Site Charlie",  zone = "DESTROY_ZONE_SAM_CHARLIE" },
    { name = "SAM Site Delta",    zone = "DESTROY_ZONE_SAM_DELTA"   },
    { name = "SAM Site Echo",     zone = "DESTROY_ZONE_SAM_ECHO"     },
    { name = "SAM Site Foxtrot",  zone = "DESTROY_ZONE_SAM_FOXTROT"   },
    { name = "SAM Site Golf",     zone = "DESTROY_ZONE_SAM_GOLF"     },
    { name = "SAM Site Hotel",    zone = "DESTROY_ZONE_SAM_HOTEL"    },
    { name = "SAM Site India",    zone = "DESTROY_ZONE_SAM_INDIA"    },
    { name = "SAM Site Juliet",   zone = "DESTROY_ZONE_SAM_JULIET"   },
    { name = "Wagner-Missile-Site",zone = "DESTROY_ZONE_Wagner-Missile-Site"},
    { name = "Wagner-Oil-Refinery",zone = "DESTROY_ZONE_Wagner-Oil-Refinery"},
    { name = "Tiyas",             zone = "DESTROY_ZONE_TIYAS" },
}

------------------------------------------------------------------------
-- SECTION 3 : RUNTIME STATE  (internal — do not edit)
------------------------------------------------------------------------
ABC._state        = {}   -- [baseName] = state table
ABC._destroyState = {}   -- [name]     = destroy-zone state table
ABC._eventHandler = {}   -- DCS world event handler object
ABC._initialized  = false
ABC._dcsNameMap   = {}   -- [DCS airbase name] → registry entry.name
                         -- Handles cases where the ME FARP name differs
                         -- from the name in ABC.REGISTRY (caps, suffix, etc.)
local _scanCount  = 0    -- incremented each scan cycle for logging

-- Auto-incrementing mark ID counter.
-- DCS mark IDs must NEVER be reused in the same or adjacent Lua frames.
-- trigger.action.removeMark() is queued (not immediate) — the old mark
-- is not gone until the next engine frame.  If you re-use the same ID
-- in the same call chain, circleToAll/textToAll silently fails (no draw).
local _nextMarkId = ABC.CFG.BASE_MARK_OFFSET + 10000  -- start well above the base offset
local function newMarkId()
    _nextMarkId = _nextMarkId + 1
    return _nextMarkId
end

------------------------------------------------------------------------
-- SECTION 4 : INTERNAL UTILITIES
------------------------------------------------------------------------

-- Zone cache — trigger zones never move, so cache them on first lookup.
-- Cuts repeated trigger.misc.getZone() calls during scans and redraws to zero.
local _zoneCache = {}

------------------------------------------------------------------------
-- Debug helper: writes a verbose trace line only when DEBUG_MODE is
-- enabled.  All hot-path per-base calls should use dbg() instead of
-- bare env.info so production performance is unaffected.
------------------------------------------------------------------------
local function dbg(msg)
    if ABC.CFG.DEBUG_MODE then
        env.info("[ABC][DBG] " .. tostring(msg), false)
    end
end

-- Safely retrieve a mission trigger zone by name.
-- Results are cached permanently — trigger.misc.getZone() is only ever
-- called ONCE per unique zone name for the lifetime of the mission.
-- LOGS a one-time WARNING if the zone is missing from the ME.
local function getZone(name)
    if not name or name == "" then return nil end
    if _zoneCache[name] then return _zoneCache[name] end
    local z = trigger.misc.getZone(name)
    if z then
        _zoneCache[name] = z
        dbg(string.format("getZone: cached '%s' r=%.0f pos=(%.0f,%.0f)",
            name, z.radius or 0,
            z.point and z.point.x or 0, z.point and z.point.z or 0))
    else
        env.info("[ABC] WARNING: Trigger zone '" .. name .. "' not found. "
                 .. "Create it in the Mission Editor.", false)
    end
    return z
end

-- ── Unit-position snapshot ────────────────────────────────────────
-- Built once at the start of each scanAll() cycle so that every zone
-- check is pure Lua arithmetic — no additional DCS API calls.  This
-- mirrors the MOOSE "collect once, query many" pattern and cuts
-- per-cycle API calls from ~37 000 to ~600 for a typical mission.
local _unitSnapshot = nil   -- array of { coal=1|2, x=N, z=N }

-- Build a flat array snapshot of all live unit positions for this scan cycle.
-- Called ONCE at the start of scanAll() — every subsequent zone-presence
-- check is pure Lua arithmetic against this table, so the DCS API is
-- only queried twice per coalition per scan (coalition.getGroups calls).
-- RETURNS: snap (array of {coal,x,z}), total unit count (for logging).
local function buildUnitSnapshot()
    local snap = {}
    local n    = 0
    local cats = { Group.Category.GROUND }
    if ABC.CFG.SCAN_AIR then
        cats[#cats + 1] = Group.Category.AIRPLANE
        cats[#cats + 1] = Group.Category.HELICOPTER
    end
    for _, coalId in ipairs({ coalition.side.RED, coalition.side.BLUE }) do
        for _, cat in ipairs(cats) do
            local groups = coalition.getGroups(coalId, cat) or {}
            for _, g in ipairs(groups) do
                if g:isExist() then
                    for _, u in ipairs(g:getUnits()) do
                        if u:isExist() and u:isActive() and u:getLife() > 0 then
                            local p = u:getPoint()
                            n = n + 1
                            snap[n] = { coal = coalId, x = p.x, z = p.z }
                        end
                    end
                end
            end
        end
    end
    return snap, n
end

-- Count live units of a given coalition inside a circular zone.
-- FAST PATH (scanAll):  iterates _unitSnapshot — zero additional DCS calls.
-- SLOW PATH (init):     falls back to live coalition.getGroups() queries.
--                       Runs only a handful of times at mission load.
-- Both paths do pure radius math: sqrt-free (dx²+dz² ≤ r²).
local function countUnitsInZone(zone, coalId)
    if not zone then return 0 end
    local count  = 0
    local rsq    = zone.radius * zone.radius
    local zx     = zone.point.x
    local zy     = zone.point.z

    -- ── Fast path: snapshot available (normal scan cycle) ─────────
    if _unitSnapshot then
        for i = 1, #_unitSnapshot do
            local u = _unitSnapshot[i]
            if u.coal == coalId then
                local dx = u.x - zx
                local dz = u.z - zy
                if (dx * dx + dz * dz) <= rsq then
                    count = count + 1
                end
            end
        end
        return count
    end

    -- ── Slow path: direct API (init only — called a handful of times) ─
    local cats = { Group.Category.GROUND }
    if ABC.CFG.SCAN_AIR then
        cats[#cats + 1] = Group.Category.AIRPLANE
        cats[#cats + 1] = Group.Category.HELICOPTER
    end
    for _, cat in ipairs(cats) do
        local groups = coalition.getGroups(coalId, cat) or {}
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

-- ── Helipad snapshot ──────────────────────────────────────────────
-- Built ONCE at mission start by snapshotHelipadObjects().
-- Each entry: { name=string, obj=Airbase, x=N, z=N }
-- findHelipadsInZone() then does pure Lua distance checks against
-- this cached list — zero DCS API calls per FOB zone.
local _helipadSnapshot = nil   -- populated by snapshotHelipadObjects()

-- Build a one-time snapshot of every helipad / FARP Airbase object in
-- the mission EXCEPT the named airdromes already in ABC.REGISTRY.
-- Stores each object's reference + position so findHelipadsInZone() can
-- do pure Lua radius checks without any per-scan DCS API calls.
-- Called ONCE at ABC.init() time by the helipad-snapshot block.
local function snapshotHelipadObjects()
    -- Build airdrome exclusion set
    local airdromes = {}
    for _, e in ipairs(ABC.REGISTRY) do
        if e.type == "AIRBASE" then airdromes[e.name] = true end
    end

    local snap = {}
    local seen = {}
    for _, coa in ipairs({ 0, 1, 2 }) do   -- NEUTRAL, RED, BLUE
        local bases = coalition.getAirbases(coa) or {}
        for _, ab in ipairs(bases) do
            if ab:isExist() then
                local abName = ab:getName()
                if not airdromes[abName] and not seen[abName] then
                    local p = ab:getPoint()
                    snap[#snap + 1] = {
                        name = abName,
                        obj  = ab,
                        x    = p.x,
                        z    = p.z,
                    }
                    seen[abName] = true
                end
            end
        end
    end

    env.info(string.format(
        "[ABC] Helipad snapshot: %d helipad/FARP objects cached.", #snap), false)
    return snap
end

-- Return all helipad/FARP objects whose centre falls within the named
-- trigger zone, using the pre-built _helipadSnapshot for O(n) pure-Lua
-- radius checks.  Called at init for every FARP entry and again if
-- ABC.registerFARP() is used at runtime.
-- LOGS the result always (including 0 found) for diagnosability.
local function findHelipadsInZone(zoneName)
    local zone = getZone(zoneName)  -- uses cache
    if not zone then
        env.info("[ABC] findHelipadsInZone: zone '" .. tostring(zoneName) .. "' not found.", false)
        return {}
    end
    if not _helipadSnapshot then
        env.info("[ABC] findHelipadsInZone: snapshot not built yet!", false)
        return {}
    end

    local zx, zy = zone.point.x, zone.point.z
    local rsq    = zone.radius * zone.radius
    local pads   = {}

    for _, hp in ipairs(_helipadSnapshot) do
        local dx = hp.x - zx
        local dz = hp.z - zy
        if (dx * dx + dz * dz) <= rsq then
            pads[#pads + 1] = { obj = hp.obj, kind = "airbase" }
        end
    end

    -- Always log result so zero-found cases are visible in dcs.log.
    env.info(string.format(
        "[ABC] findHelipadsInZone('%s'): %d helipad(s) in zone (r=%.0f).",
        zoneName, #pads, zone.radius or 0), false)
    return pads
end

-- Map our string coalitions to DCS numeric coalition IDs.
local COAL_STR_TO_ID = { NEUTRAL = 0, RED = 1, BLUE = 2, DESTROYED = 0 }

-- Change the DCS Airbase coalition for every helipad / FARP object in
-- the list.  This is what makes the helipad ring colour flip on the F10
-- map and what controls which pilots can spawn at / use the FARP.
-- coalStr must be "RED", "BLUE", "NEUTRAL" (or "DESTROYED" → neutral).
-- LOGS every pad processed (success AND failure) so the log is the
-- first place to look when helipad coalition is not changing in-game.
local function setHelipadsCoalition(helipads, coalStr)
    local id = COAL_STR_TO_ID[coalStr]
    if id == nil then
        env.info("[ABC] setHelipadsCoalition: unknown coalStr '" .. tostring(coalStr) .. "'", false)
        return
    end

    if not helipads or #helipads == 0 then
        env.info("[ABC] setHelipadsCoalition: list is EMPTY — no pads to update (target=" .. coalStr .. ")", false)
        return
    end

    for _, pad in ipairs(helipads) do
        local obj = pad.obj
        if obj and obj:isExist() then
            local padName = tostring(obj:getName())
            local ok, err = pcall(function() obj:setCoalition(id) end)
            if ok then
                -- Read back the coalition DCS actually stored to confirm it stuck.
                -- If DCS reverts the call, readId will differ from id.
                local readId = -1
                pcall(function() readId = obj:getCoalition() end)
                if readId == id then
                    env.info(string.format(
                        "[ABC] setHelipadsCoalition: '%s' → %s (id=%d) OK — verified readback=%d",
                        padName, coalStr, id, readId), false)
                else
                    env.info(string.format(
                        "[ABC] setHelipadsCoalition: '%s' SET to %s (id=%d) but DCS readback=%d — DCS REVERTED the change!",
                        padName, coalStr, id, readId), false)
                end
            else
                env.info(string.format(
                    "[ABC] setHelipadsCoalition: '%s' FAILED → %s: %s",
                    padName, coalStr, tostring(err)), false)
            end
        else
            env.info("[ABC] setHelipadsCoalition: pad obj nil or destroyed — skipped", false)
        end
    end
end

------------------------------------------------------------------------
-- SECTION 5 : DRAWING SYSTEM
------------------------------------------------------------------------
-- Colour tables use POSITIONAL arrays {r, g, b, a} (indices 1,2,3,4).
-- DCS rejects named-key tables {r=..., g=..., b=..., a=...} silently.
--
-- Mark IDs are auto-incremented via newMarkId() on every drawBase call.
-- IDs are never reused — removeMark() is deferred by the DCS engine, so
-- reusing the same ID in the same frame silently drops the new draw call.
------------------------------------------------------------------------

-- Colour/fill table per logical status (built lazily after CFG loads)
-- Lazily initialise the STATUS_COLORS lookup on first use (after CFG loads).
-- Returns {line=…, fill=…} colour-array pair for the given coalition string.
-- Defaults to NEUTRAL colours if an unrecognised status string is passed.
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

-- Remove every F10 map mark owned by this base's state entry.
-- Uses pcall so a stale / already-removed ID never propagates an error.
-- After this call st.markIds is always a fresh empty table ready for
-- the next drawBase() to populate.
local function clearMarks(st)
    if st.markIds then
        for _, mid in ipairs(st.markIds) do
            local ok, err = pcall(trigger.action.removeMark, mid)
            if not ok then
                dbg("clearMarks: removeMark(" .. tostring(mid) .. ") error: " .. tostring(err))
            end
        end
    end
    st.markIds = {}
end

-- Draw (or redraw) the F10 map filled circle + name label for one base.
-- Called: at init, on every coalition change, and on capture-tick progress.
-- Position AND radius come exclusively from the ME trigger zone — the same
-- zone used for capture detection. Every coalition uses this identical path.
-- All DCS trigger.action calls are wrapped in pcall so failures are logged.
local function drawBase(entry, st)
    local zone = getZone(entry.zone)
    if not zone then
        env.info("[ABC] drawBase: zone '" .. tostring(entry.zone)
                 .. "' missing for " .. entry.name .. " — cannot draw.", false)
        return
    end

    -- y=0: F10 map marks ignore elevation entirely; the terrain height stored
    -- in zone.point.y can confuse circleToAll depth calculations on some Syria
    -- map versions — always pass flat 0.
    local drawPos    = { x = zone.point.x, y = 0, z = zone.point.z }
    local drawRadius = zone.radius or ABC.CFG.CIRCLE_RADIUS  -- zone radius always; CFG is last resort only

    clearMarks(st)

    local cols   = getColors(st.coalition)
    -- Always allocate FRESH mark IDs — never reuse IDs that were just removed.
    -- DCS queues removeMark() for the next engine frame, so re-using the same
    -- ID in the same Lua call silently drops the circleToAll call.
    local fillId = newMarkId()   -- brand-new ID for the filled circle
    local textId = newMarkId()   -- brand-new ID for the text label

    -- ── Log before draw so any silent API failure is diagnosable ─────
    env.info(string.format(
        "[ABC] drawBase: %s coal=%s markId=%d pos=(%.0f,%.0f) r=%.0f ticks=%d",
        entry.name, st.coalition, fillId,
        drawPos.x, drawPos.z, drawRadius, st.captureTicks or 0), false)

    -- ── Filled circle — radius matches the ME trigger zone exactly ───
    local circleOk, circleErr = pcall(function()
        trigger.action.circleToAll(
            -1, fillId, drawPos,
            drawRadius,
            cols.line, cols.fill,
            ABC.CFG.LINE_TYPE, true)
    end)
    if not circleOk then
        env.info("[ABC] drawBase: circleToAll FAILED for " .. entry.name
                 .. ": " .. tostring(circleErr), false)
    end

    -- ── Text label ───────────────────────────────────────────────────
    -- Black text normally; yellow for DESTROYED bases.
    -- Shows "Capturing… N%" during multi-tick captures.
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

    -- Offset label slightly right (+x) and north (-z) of the zone centre
    local offset = math.max(drawRadius * 0.12, 400)
    local textPos = { x = drawPos.x + offset, y = drawPos.y, z = drawPos.z - offset * 0.5 }
    local textOk, textErr = pcall(function()
        trigger.action.textToAll(
            -1, textId, textPos,
            textColor, {0, 0, 0, 0},
            ABC.CFG.LABEL_FONT_SIZE, true, labelText)
    end)
    if not textOk then
        env.info("[ABC] drawBase: textToAll FAILED for " .. entry.name
                 .. ": " .. tostring(textErr), false)
    end

    st.markIds = { fillId, textId }

    dbg(string.format("drawBase OK: %s coal=%s markIds=%d/%d label='%s' circleOk=%s textOk=%s",
        entry.name, st.coalition, fillId, textId, labelText,
        tostring(circleOk), tostring(textOk)))
end

-- Run a single coalition sanity-check just before the first drawBase().
-- If a RED/BLUE base has no units defending it at mission load, we flip
-- it to NEUTRAL immediately so the F10 map shows accurate state from T=0.
-- Only called once per entry during ABC.init().
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

-- Apply a coalition change to a base entry and handle all side-effects:
--   1. Update logical state (st.coalition, captureTicks reset to 0).
--   2. Redraw the F10 map circle in the new coalition colour.
--   3. Send an in-game announcement if announce=true.
--   4. Fire the ABC.onCapture callback if set by the mission designer.
--   5. Update the DCS Airbase engine coalition (ATC, spawn slots, parking).
--   6. Update every helipad/FARP Airbase object inside the zone.
-- LOGS: helipad count at step 6 so we can diagnose missing pad flips.
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

    -- ── Activate late-activated groups on Blue capture ─────────────
    -- activateGroups is an array of ME group names (garrison, HIMARS,
    -- mortars, etc.).  Every group in the list is activated when Blue
    -- captures this FOB.  Groups must have Late Activation = ON in the ME.
    -- NOTE: Do NOT call grp:isExist() on a late-activated group — it always
    -- returns false until activated.  Group.getByName() non-nil is enough.
    if newCoal == "BLUE" and entry.activateGroups then
        for _, groupName in ipairs(entry.activateGroups) do
            local grp = Group.getByName(groupName)
            if grp then
                grp:activate()
                env.info(string.format(
                    "[ABC] Activated group '%s' for %s → BLUE.",
                    groupName, entry.name), false)
            else
                env.info(string.format(
                    "[ABC] activateGroups: group '%s' not found for %s — check the ME group name.",
                    groupName, entry.name), false)
            end
        end
    end

    -- ── Set DCS airbase coalition ────────────────────────────────────
    -- This makes the engine recognise the new owner: ATC, spawn slots,
    -- parking, and warehouse all switch to the capturing side.
    local newCoalId = COAL_STR_TO_ID[newCoal] or 0
    local ab = Airbase.getByName(entry.name)
    if ab and ab:isExist() then
        pcall(function() ab:setCoalition(newCoalId) end)
        env.info(string.format(
            "[ABC] DCS airbase '%s' coalition → %s (%d)",
            entry.name, newCoal, newCoalId), false)
    end

    -- ── Flip helipad ownership to match the new coalition ────────────
    -- Always log the helipad count BEFORE calling so we can diagnose
    -- nil/empty pad tables (= helipad not found at init time).
    local padCount = (st.helipads and #st.helipads) or 0
    env.info(string.format(
        "[ABC] applyCoalition: %s → %s — helipad table has %d entry/entries.",
        entry.name, newCoal, padCount), false)
    if padCount > 0 then
        -- Defer by 0.1 s so this runs AFTER the current DCS engine frame.
        -- Calling setCoalition() during the same frame as a scan/event can be
        -- silently reverted by the engine's own ownership resolution pass.
        -- A short timer ensures we write AFTER the engine has settled.
        local helipads_ref = st.helipads
        local coal_ref     = newCoal
        timer.scheduleFunction(function()
            setHelipadsCoalition(helipads_ref, coal_ref)
        end, nil, timer.getTime() + 0.1)
    else
        env.info("[ABC] applyCoalition: NO helipads in state for " .. entry.name
                 .. " — DCS FARP ring colour will NOT change.", false)
    end
end

-- Evaluate one base entry for one scan cycle (called from scanAll via pcall).
-- Reads the pre-built _unitSnapshot for zero-DCS-call unit counts, then
-- advances the capture state machine:
--   RED     → (all red dead)       → NEUTRAL
--   NEUTRAL → (blue moves in)      → captureTicks++ → (≥CAPTURE_TICKS) → BLUE
--   NEUTRAL → (red recaptures)     → captureTicks++ → (≥CAPTURE_TICKS) → RED
--   BLUE    → (all blue leave)     → NEUTRAL
-- All coalition flips are handled by applyCoalition().
local function tickBase(entry, st)
    -- Skip non-capturable and destroyed bases
    if not entry.capturable  then return end
    if st.coalition == "DESTROYED" then return end

    local zone = getZone(entry.zone)
    if not zone then
        env.info("[ABC] tickBase: zone '" .. tostring(entry.zone)
                 .. "' not found for " .. entry.name .. " — skipping.", false)
        return
    end

    local redCount  = countUnitsInZone(zone, coalition.side.RED)
    local blueCount = countUnitsInZone(zone, coalition.side.BLUE)
    local minU      = ABC.CFG.MIN_CAPTURE_UNITS

    -- Log unit counts for every base every scan so we can confirm the
    -- snapshot sees our troops and verify the game-state logic is correct.
    dbg(string.format("tickBase: %s [%s] red=%d blue=%d minU=%d ticks=%d",
        entry.name, st.coalition, redCount, blueCount, minU, st.captureTicks or 0))

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
            if st.captureTicks >= ABC.CFG.CAPTURE_TICKS then
                -- Flip immediately — applyCoalition handles the redraw internally.
                -- Do NOT call drawBase here; calling it before applyCoalition would
                -- remove then re-add the same mark IDs in a single DCS frame, causing
                -- the second circleToAll to fail silently (DCS ID reuse bug).
                applyCoalition(entry, st, "BLUE", true)
            else
                -- Multi-tick capture in progress — show % label update only.
                drawBase(entry, st)
            end

        elseif redCount >= minU and blueCount == 0 then
            -- Red forces reclaiming the neutral base
            st.captureTicks = (st.captureTicks or 0) + 1
            if st.captureTicks >= ABC.CFG.CAPTURE_TICKS then
                applyCoalition(entry, st, "RED", true)
            else
                drawBase(entry, st)
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

-- Main scan loop — scheduled by timer.scheduleFunction every CHECK_INTERVAL.
-- Builds one unit-position snapshot (2 × coalition.getGroups calls) then
-- iterates every registered base and destroy zone for pure-Lua checks.
-- Returns the next scheduled time so the DCS scheduler keeps calling us.
local function scanAll(_, time)
    -- ── Build unit-position snapshot (one DCS pass → pure-Lua zone checks)
    _unitSnapshot = buildUnitSnapshot()

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
                local zone = getZone(entry.zone)  -- uses cache; no DCS API call after first scan
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

    _unitSnapshot = nil  -- release snapshot until next cycle

    _scanCount = _scanCount + 1
    env.info(string.format("[ABC] Scan #%d complete.", _scanCount), false)
    return time + ABC.CFG.CHECK_INTERVAL
end

------------------------------------------------------------------------
-- SECTION 8 : DCS EVENT HANDLER
-- Listens for S_EVENT_BASE_CAPTURED so DCS-engine capture events
-- (from ME airbase auto-capture settings) stay in sync with our state.
------------------------------------------------------------------------

function ABC._eventHandler:onEvent(event)
    if event.id ~= world.event.S_EVENT_BASE_CAPTURED then return end
    local _ok, _err = pcall(function()

    local ab = event.place
    if not ab then return end

    -- Resolve DCS airbase name → registry entry name.
    -- FARP names in DCS often differ from registry names (caps, suffix).
    local abName      = ab:getName()
    local registryName = ABC._dcsNameMap[abName] or abName
    local st           = ABC._state[registryName]
    if not st then return end

    -- Map DCS coalition ID to our string
    local dcsCoal  = ab:getCoalition()
    local coalStr  = "NEUTRAL"
    if dcsCoal == coalition.side.RED  then coalStr = "RED"
    elseif dcsCoal == coalition.side.BLUE then coalStr = "BLUE"
    end

    -- Find the matching registry entry
    local entry = nil
    for _, e in ipairs(ABC.REGISTRY) do
        if e.name == registryName then entry = e; break end
    end
    if not entry then return end

    -- For FARP entries, REJECT DCS engine captures that disagree with
    -- our script state.  The script is the sole authority for FARP
    -- ownership — DCS auto-capture would fight this otherwise.
    if entry.type == "FARP" then
        local desiredId = COAL_STR_TO_ID[st.coalition] or 0
        if dcsCoal ~= desiredId then
            pcall(function() ab:setCoalition(desiredId) end)
            env.info(string.format(
                "[ABC] Rejected DCS auto-capture: %s (DCS=%s, ours=%s) — forced back.",
                registryName, coalStr, st.coalition), false)
        end
        return   -- never sync FARP state from DCS; script controls FARPs
    end

    -- For AIRBASE entries, sync: DCS engine is authority for airbases
    if st.coalition ~= coalStr then
        env.info(string.format(
            "[ABC] DCS engine capture event: %s \226\134\146 %s (syncing script state)",
            registryName, coalStr), false)
        applyCoalition(entry, st, coalStr, false)   -- no double-announce
    end
    end) -- close pcall
    if not _ok then env.warning("[ABC] onEvent error: " .. tostring(_err)) end
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

    local st = {
        coalition    = entry.coalition,
        captureTicks  = 0,
        markIds      = {},
        pos          = pos,
    }
    ABC._state[farpName] = st

    -- Discover helipads inside the FARP's zone
    local pads = findHelipadsInZone(zoneName)
    st.helipads = pads
    if #pads > 0 then
        setHelipadsCoalition(pads, entry.coalition)
        env.info(string.format(
            "[ABC] %s: %d helipad(s) found in zone — set to %s.",
            farpName, #pads, entry.coalition), false)
    end

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
-- SECTION 9b : PERSISTENCE  (save / restore capture state across restarts)
------------------------------------------------------------------------
-- Saves ABC._state (airbases / FARPs) and ABC._destroyState (destroy zones)
-- every PERSIST.saveInterval seconds to:
--   <DCS Saved Games>\Mission Saves\AirbaseCapture.lua
--
-- On mission start ABC.init() calls PERSIST.load().  If a file exists the
-- restore is scheduled 15 s later (mission fully settled) and silently
-- replays all coalition changes — activating BLUE FOB garrison groups as
-- normal via applyCoalition().  No messages are shown during restore.
------------------------------------------------------------------------
ABC.PERSIST = {
    saveDir      = lfs.writedir() .. "Mission Saves\\",
    saveFile     = lfs.writedir() .. "Mission Saves\\AirbaseCapture.lua",
    saveInterval = 900,   -- 15 minutes
    SAVE_VERSION = "1.0",
}

-- Serialise current state to the save file.
function ABC.PERSIST.save()
    if not ABC._initialized then return end

    -- Ensure save directory exists (safe to call even when it already exists)
    lfs.mkdir(ABC.PERSIST.saveDir)

    local lines = {
        "-- AirbaseCapture State Save  (auto-generated — do not edit manually)",
        string.format("-- Version: %s  Mission-time: T+%ds",
            ABC.PERSIST.SAVE_VERSION, math.floor(timer.getTime())),  -- os.date unavailable in DCS sandbox
        "local data = {",
        string.format("    version = %q,", ABC.PERSIST.SAVE_VERSION),
        "    bases = {",
    }

    for name, st in pairs(ABC._state) do
        lines[#lines+1] = string.format(
            "        [%q] = { coalition = %q, captureTicks = %d },",
            name, st.coalition or "NEUTRAL", st.captureTicks or 0)
    end

    lines[#lines+1] = "    },"
    lines[#lines+1] = "    destroyZones = {"

    for name, dst in pairs(ABC._destroyState) do
        lines[#lines+1] = string.format(
            "        [%q] = { coalition = %q, active = %s },",
            name, dst.coalition or "RED", tostring(dst.active ~= false))
    end

    lines[#lines+1] = "    },"
    lines[#lines+1] = "}"
    lines[#lines+1] = "return data"

    local content = table.concat(lines, "\n")
    local f = io.open(ABC.PERSIST.saveFile, "w")
    if f then
        f:write(content)
        f:close()
        env.info("[ABC] PERSIST: state saved to " .. ABC.PERSIST.saveFile, false)
    else
        env.info("[ABC] PERSIST: ERROR — could not open save file for writing: "
                 .. ABC.PERSIST.saveFile, false)
    end
end

-- Load the save file and return the parsed data table, or nil if absent/invalid.
function ABC.PERSIST.load()
    local f = io.open(ABC.PERSIST.saveFile, "r")
    if not f then
        env.info("[ABC] PERSIST: no save file at " .. ABC.PERSIST.saveFile, false)
        return nil
    end
    local content = f:read("*a")
    f:close()

    if not content or content == "" then
        env.info("[ABC] PERSIST: save file is empty — ignoring.", false)
        return nil
    end

    local chunk, parseErr = loadstring(content)
    if not chunk then
        env.info("[ABC] PERSIST: save file parse error: " .. tostring(parseErr), false)
        return nil
    end

    local ok, data = pcall(chunk)
    if not ok or type(data) ~= "table" then
        env.info("[ABC] PERSIST: save file execution error or bad format — ignoring.", false)
        return nil
    end

    if data.version ~= ABC.PERSIST.SAVE_VERSION then
        env.info(string.format(
            "[ABC] PERSIST: WARNING — save version %q differs from expected %q. Restoring anyway.",
            tostring(data.version), ABC.PERSIST.SAVE_VERSION), false)
    end

    env.info("[ABC] PERSIST: save file loaded (version=" .. tostring(data.version) .. ").", false)
    return data
end

-- Apply saved state.  Called via a T+15 s timer so the mission is settled.
-- applyCoalition() with announce=false silently restores state and
-- automatically activates BLUE FOB garrison groups (activateGroups list).
-- ABC.onCapture is temporarily suppressed so callbacks don't double-fire.
function ABC.PERSIST.restore(data)
    if not data then return end

    -- Suppress onCapture callback during restore to avoid double-counting
    local savedCallback = ABC.onCapture
    ABC.onCapture = nil

    -- ── Airbase / FARP states ────────────────────────────────────────
    for name, saved in pairs(data.bases or {}) do
        local st = ABC._state[name]
        if not st then
            env.info("[ABC] PERSIST restore: unknown base '" .. name .. "' — skipped.", false)
        else
            local coal = saved.coalition or "NEUTRAL"
            if coal ~= st.coalition then
                local entry = nil
                for _, e in ipairs(ABC.REGISTRY) do
                    if e.name == name then entry = e; break end
                end
                if entry then
                    applyCoalition(entry, st, coal, false)
                    env.info(string.format(
                        "[ABC] PERSIST: restored '%s' → %s", name, coal), false)
                end
            end
        end
    end

    -- ── Destroy zone states ──────────────────────────────────────────
    for name, saved in pairs(data.destroyZones or {}) do
        local dst = ABC._destroyState[name]
        if not dst then
            env.info("[ABC] PERSIST restore: unknown destroy zone '" .. name .. "' — skipped.", false)
        elseif saved.coalition == "DESTROYED" and dst.coalition ~= "DESTROYED" then
            dst.coalition = "DESTROYED"
            dst.active    = false
            for _, entry in ipairs(ABC.DESTROY_REGISTRY) do
                if entry.name == name then
                    pcall(drawBase, entry, dst)
                    env.info("[ABC] PERSIST: destroy zone '" .. name .. "' → DESTROYED", false)
                    break
                end
            end
        end
    end

    -- Restore callback
    ABC.onCapture = savedCallback
    env.info("[ABC] PERSIST: restore complete.", false)
end

-- Self-rescheduling periodic save timer callback.
function ABC.PERSIST.periodicSave(_, time)
    local ok, err = pcall(ABC.PERSIST.save)
    if not ok then
        env.info("[ABC] PERSIST: periodic save error: " .. tostring(err), false)
    end
    return time + ABC.PERSIST.saveInterval
end

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

    -- ── Orphaned-mark cleanup ────────────────────────────────────────
    -- The old auto-incrementing mark ID system (IDs 10000+) was replaced
    -- with fixed-ID slots (BASE_MARK_OFFSET / DESTROY_MARK_OFFSET blocks).
    -- Orphan marks from the old system were cleared in earlier sessions and
    -- no longer exist, so the 501-call sweep is skipped to avoid wasting
    -- DCS API budget on every mission start.
    env.info("[ABC] Mark ID system: fixed slots (orphan sweep not needed).", false)

    -- ── Helipad snapshot ─────────────────────────────────────────────
    -- One DCS API pass to cache every helipad/FARP Airbase object in the
    -- mission.  All subsequent findHelipadsInZone() calls are pure Lua.
    _helipadSnapshot = snapshotHelipadObjects()

    -- Build initial state for every registry entry
    for _, entry in ipairs(ABC.REGISTRY) do
        -- Disable DCS engine auto-capture so this script has full control.
        -- Applies to both AIRBASEs and FARPs (prevents DCS from overriding
        -- our NEUTRAL state with its own capture events).
        local ab = Airbase.getByName(entry.name)
        if ab then
            if ab.autoCapture then
                pcall(function() ab:autoCapture(false) end)
            end
        else
            if entry.type == "AIRBASE" then
                env.info("[ABC] WARNING: '" .. entry.name
                         .. "' not found as a DCS airbase object. "
                         .. "Will fall back to zone centre for drawing.", false)
            end
        end

        ABC._state[entry.name] = {
            coalition    = entry.coalition,
            captureTicks  = 0,
            markIds      = {},
            pos          = nil,
        }

        -- Fast init scan: correct coalition BEFORE drawing so the first
        -- frame shows accurate state (RED bases with no units → NEUTRAL).
        pcall(initCoalitionCheck, entry, ABC._state[entry.name])

        -- Draw initial marker using zone centre + zone radius from ME.
        local ok, err = pcall(drawBase, entry, ABC._state[entry.name])
        if not ok then
            env.info("[ABC] Draw error for " .. entry.name .. ": " .. tostring(err), false)
        end

        -- For FARP / FOB entries, discover helipads inside the zone and
        -- set their DCS coalition to match the FOB's current ownership.
        if entry.type == "FARP" then
            local pads = findHelipadsInZone(entry.zone)
            ABC._state[entry.name].helipads = pads
            if #pads > 0 then
                setHelipadsCoalition(pads, ABC._state[entry.name].coalition)
                env.info(string.format(
                    "[ABC] %s: %d helipad(s) found in zone — set to %s.",
                    entry.name, #pads, ABC._state[entry.name].coalition), false)
            end

            -- Build the DCS-name → registry-name map and set autoCapture(false)
            -- on the actual DCS airbase object (whose name may differ from
            -- the registry name due to caps / suffix differences in ME).
            for _, pad in ipairs(pads) do
                if pad.kind == "airbase" then
                    local dcsName = pad.obj:getName()
                    if dcsName ~= entry.name then
                        -- Silently record name remapping; reduces init log spam
                        ABC._dcsNameMap[dcsName] = entry.name
                    end
                    -- Disable auto-capture on whichever DCS name the FARP has
                    if pad.obj.autoCapture then
                        pcall(function() pad.obj:autoCapture(false) end)
                    end
                end
            end
        end
    end

    -- ── Destroy zone initialisation ──────────────────────────────────
    for _, entry in ipairs(ABC.DESTROY_REGISTRY) do
        -- Check current unit count so a zone that starts empty is already DESTROYED
        local startCoal = "RED"
        local isActive  = true
        local zone = getZone(entry.zone)  -- uses cache
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

    -- Post-init FARP coalition reset: runs AFTER the DCS initial auto-capture
    -- events (which fire at ~t=5) but BEFORE the first scan (at t=10).
    -- Forces every FARP airbase coalition back to the script's desired state.
    timer.scheduleFunction(function(_, t)
        for _, entry in ipairs(ABC.REGISTRY) do
            if entry.type == "FARP" then
                local st = ABC._state[entry.name]
                if st and st.helipads then
                    local desiredId = COAL_STR_TO_ID[st.coalition] or 0
                    for _, pad in ipairs(st.helipads) do
                        if pad.kind == "airbase" and pad.obj and pad.obj:isExist() then
                            pcall(function() pad.obj:setCoalition(desiredId) end)
                        end
                    end
                end
            end
        end
        env.info("[ABC] Post-init FARP coalition reset complete.", false)
    end, nil, timer.getTime() + 7)

    -- Repeating FARP helipad re-assertion: every 30 s forces every FARP pad's
    -- DCS coalition back to the script's current logical state.  Without this,
    -- the DCS engine can silently revert a setCoalition() call (e.g. the BLUE→
    -- NEUTRAL transition at init, or the NEUTRAL→BLUE flip on capture) between
    -- scans, leaving the helipad ring stuck on the wrong colour.
    timer.scheduleFunction(function(_, t)
        for _, entry in ipairs(ABC.REGISTRY) do
            if entry.type == "FARP" then
                local st = ABC._state[entry.name]
                if st and st.helipads and #st.helipads > 0 then
                    local desiredId = COAL_STR_TO_ID[st.coalition] or 0
                    for _, pad in ipairs(st.helipads) do
                        if pad.kind == "airbase" and pad.obj and pad.obj:isExist() then
                            local currentId = -1
                            pcall(function() currentId = pad.obj:getCoalition() end)
                            if currentId ~= desiredId then
                                -- DCS reverted the coalition — force it back silently
                                pcall(function() pad.obj:setCoalition(desiredId) end)
                                dbg(string.format(
                                    "FARP re-assert: '%s' was %d, forced back to %d (%s)",
                                    tostring(pad.obj:getName()), currentId, desiredId, st.coalition))
                            end
                        end
                    end
                end
            end
        end
        return t + 30   -- repeat every 30 s for the duration of the mission
    end, nil, timer.getTime() + 37)

    -- Start the scan loop (first tick after 10 s to let mission settle)
    timer.scheduleFunction(scanAll, nil, timer.getTime() + 10)

    ABC._initialized = true

    -- ── Persistence: load save file and schedule restore ─────────────
    local savedData = ABC.PERSIST.load()
    if savedData then
        timer.scheduleFunction(function(_, t)
            ABC.PERSIST.restore(savedData)
            timer.scheduleFunction(ABC.PERSIST.periodicSave, nil,
                timer.getTime() + ABC.PERSIST.saveInterval)
            env.info("[ABC] PERSIST: periodic save armed (interval="
                     .. ABC.PERSIST.saveInterval .. "s).", false)
        end, nil, timer.getTime() + 15)
        env.info("[ABC] PERSIST: save file found — restore scheduled at T+15 s.", false)
    else
        timer.scheduleFunction(ABC.PERSIST.periodicSave, nil,
            timer.getTime() + ABC.PERSIST.saveInterval)
        env.info("[ABC] PERSIST: no save file — fresh start, periodic save armed.", false)
    end

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
