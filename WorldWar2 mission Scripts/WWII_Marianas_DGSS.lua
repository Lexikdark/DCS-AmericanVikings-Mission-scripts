-- =============================================================================
--  WWII Marianas – Dynamic Group Spawn System (DGSS)
--  Version : 1.0  |  Map : Marianas  |  Era : WWII
--  Requires: MIST (4.5+) loaded BEFORE this script
--
--  LOAD ORDER in Mission Editor:
--    1. mist_4_5_126.lua
--    2. WWII_Marianas_DGSS.lua  (this file)
--
--  FEATURES:
--    - 20 WWII-era Japanese/Axis spawn templates (RED only)
--    - Shuffle-bag template selection (no repeats until bag exhausted)
--    - Zone-based spawning across configurable trigger zones
--    - F10 map markers placed on each spawn, auto-removed on death
--    - Automatic cleanup of dead/empty groups
--    - Per-zone min/max group limits
--
--  ME SETUP:
--    Create trigger zones named  ZONE1 … ZONE18  (circle zones in ME).
--    Zones should cover areas where Japanese forces would operate.
-- =============================================================================

DGSS = {}

-- ─────────────────────────────────────────────────────────────────────────────
--  CONFIGURATION
-- ─────────────────────────────────────────────────────────────────────────────

DGSS.MAX_SPAWNS_PER_CYCLE       = 3
DGSS.CHECK_ZONES_INTERVAL       = 300    -- seconds between zone-check passes
DGSS.CLEANUP_INTERVAL           = 120    -- dead group cleanup
DGSS.MEMORY_CLEANUP_INTERVAL    = 1200   -- full state garbage collect
DGSS.MARKER_CLEANUP_INTERVAL    = 300

DGSS.RED_COUNTRY  = country.id.JAPAN

-- ─────────────────────────────────────────────────────────────────────────────
--  WWII SPAWN TEMPLATES  (Japanese / Axis only – RED side)
--  Each template:
--    name      = display label
--    units     = { { type, count }, … }
-- ─────────────────────────────────────────────────────────────────────────────

DGSS.TEMPLATES = {
    { name = "IJA Patrol",              units = { { "soldier_mauser98", 6 }, { "Type_94_Truck", 1 } } },
    { name = "IJA Patrol + LMG",        units = { { "soldier_mauser98", 5 }, { "Type_96_25mm_AA", 1 }, { "Type_94_Truck", 1 } } },
    { name = "Ke-Ni Scout",             units = { { "Type_98_Ke_Ni", 2 }, { "soldier_mauser98", 4 }, { "Type_94_Truck", 1 } } },
    { name = "I-Go Platoon",            units = { { "Type_89_I_Go", 2 }, { "soldier_mauser98", 4 }, { "Type_94_Truck", 1 } } },
    { name = "I-Go + Trucks",           units = { { "Type_89_I_Go", 2 }, { "Type_94_Truck", 3 }, { "soldier_mauser98", 2 } } },
    { name = "AA Position",             units = { { "Type_96_25mm_AA", 3 }, { "soldier_mauser98", 4 } } },
    { name = "Ke-Ni Section",           units = { { "Type_98_Ke_Ni", 3 }, { "soldier_mauser98", 3 }, { "Type_94_Truck", 1 } } },
    { name = "Supply Column",           units = { { "Type_94_Truck", 4 }, { "soldier_mauser98", 3 } } },
    { name = "IJA Squad",               units = { { "soldier_mauser98", 7 }, { "Type_96_25mm_AA", 1 } } },
    { name = "Mixed Armour",            units = { { "Type_89_I_Go", 2 }, { "Type_98_Ke_Ni", 2 }, { "soldier_mauser98", 3 } } },
    { name = "IJA Rifle Section",       units = { { "soldier_mauser98", 6 }, { "Type_94_Truck", 1 }, { "Type_96_25mm_AA", 1 } } },
    { name = "Tank Pair",               units = { { "Type_89_I_Go", 3 }, { "Type_98_Ke_Ni", 2 }, { "soldier_mauser98", 2 } } },
    { name = "Light Tank Pair",         units = { { "Type_98_Ke_Ni", 3 }, { "soldier_mauser98", 3 }, { "Type_94_Truck", 1 } } },
    { name = "IJA Ambush Team",         units = { { "soldier_mauser98", 6 }, { "Type_96_25mm_AA", 1 } } },
    { name = "AA + Infantry Screen",    units = { { "Type_96_25mm_AA", 2 }, { "soldier_mauser98", 5 } } },
    { name = "Armoured Column",         units = { { "Type_89_I_Go", 2 }, { "Type_98_Ke_Ni", 2 }, { "Type_94_Truck", 2 } } },
    { name = "IJA Heavy Platoon",       units = { { "Type_89_I_Go", 2 }, { "soldier_mauser98", 4 }, { "Type_96_25mm_AA", 1 } } },
    { name = "Beach Defenders",         units = { { "soldier_mauser98", 4 }, { "Type_96_25mm_AA", 3 }, { "Type_94_Truck", 1 } } },
    { name = "Supply Convoy",           units = { { "Type_94_Truck", 3 }, { "soldier_mauser98", 3 }, { "Type_98_Ke_Ni", 1 } } },
    { name = "Full Armour Section",     units = { { "Type_89_I_Go", 2 }, { "Type_98_Ke_Ni", 2 }, { "soldier_mauser98", 3 } } },
}

-- ─────────────────────────────────────────────────────────────────────────────
--  ZONE SETTINGS   (minGroups, maxGroups per zone)
-- ─────────────────────────────────────────────────────────────────────────────

DGSS.ZONES = {}
for i = 1, 18 do
    DGSS.ZONES["ZONE" .. i] = { minGroups = 1, maxGroups = 3 }
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SHUFFLE BAG
-- ─────────────────────────────────────────────────────────────────────────────

DGSS._shuffleBag   = {}
DGSS._shuffleIndex = 0

local function refillBag()
    DGSS._shuffleBag = {}
    for i = 1, #DGSS.TEMPLATES do DGSS._shuffleBag[#DGSS._shuffleBag + 1] = i end
    -- Fisher-Yates shuffle
    for i = #DGSS._shuffleBag, 2, -1 do
        local j = math.random(i)
        DGSS._shuffleBag[i], DGSS._shuffleBag[j] = DGSS._shuffleBag[j], DGSS._shuffleBag[i]
    end
    DGSS._shuffleIndex = 1
end

local function pickTemplate()
    if DGSS._shuffleIndex == 0 or DGSS._shuffleIndex > #DGSS._shuffleBag then refillBag() end
    local idx = DGSS._shuffleBag[DGSS._shuffleIndex]
    DGSS._shuffleIndex = DGSS._shuffleIndex + 1
    return DGSS.TEMPLATES[idx]
end

-- ─────────────────────────────────────────────────────────────────────────────
--  INTERNAL STATE
-- ─────────────────────────────────────────────────────────────────────────────

DGSS._nextID       = 1
DGSS._spawnedGroups = {}   -- { groupName = { zone, spawnTime, markerID } }

-- ─────────────────────────────────────────────────────────────────────────────
--  HELPERS
-- ─────────────────────────────────────────────────────────────────────────────

local function dgLog(msg) env.info("[DGSS] " .. tostring(msg)) end

local function dist2d(a, b)
    local dx = a.x - b.x; local dz = a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end

local function isGroupAlive(gName)
    local g = Group.getByName(gName)
    if not g or not g:isExist() then return false end
    for _, u in ipairs(g:getUnits()) do
        if u and u:isExist() and u:getLife() > 1 then return true end
    end
    return false
end

local function countZoneGroups(zoneName)
    local ct = 0
    for gn, data in pairs(DGSS._spawnedGroups) do
        if data.zone == zoneName and isGroupAlive(gn) then ct = ct + 1 end
    end
    return ct
end

local function getRandomPointInZone(zoneName)
    local zd = trigger.misc.getZone(zoneName)
    if not zd then return nil end
    -- Use mist if available, else simple circle pick
    if mist and mist.getRandPointInZone then
        local pt = mist.getRandPointInZone(zoneName)
        if pt then return { x = pt.x, z = pt.z or pt.y } end
    end
    local angle  = math.random() * 2 * math.pi
    local radius = math.sqrt(math.random()) * zd.radius * 0.8
    return {
        x = zd.point.x + radius * math.cos(angle),
        z = zd.point.z + radius * math.sin(angle),
    }
end

-- ─────────────────────────────────────────────────────────────────────────────
--  MARKER SYSTEM
-- ─────────────────────────────────────────────────────────────────────────────

local _nextMarkerID = 50000

local function placeMarker(pos, label)
    _nextMarkerID = _nextMarkerID + 1
    local mID = _nextMarkerID
    trigger.action.markToAll(mID, label, { x = pos.x, y = 0, z = pos.z }, true)
    return mID
end

local function removeMarker(mID)
    if mID then pcall(function() trigger.action.removeMark(mID) end) end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SPAWN FUNCTIONS
-- ─────────────────────────────────────────────────────────────────────────────

local function buildUnits(unitDefs, origin, heading)
    local units = {}
    local offset = 0
    for _, def in ipairs(unitDefs) do
        for _ = 1, def[2] do
            offset = offset + 1
            units[#units + 1] = {
                type    = def[1],
                x       = origin.x + offset * 8 * math.cos(heading),
                y       = origin.z + offset * 8 * math.sin(heading),
                heading = heading,
                skill   = "Average",
                name    = "DGSS_u" .. DGSS._nextID .. "_" .. offset,
            }
        end
    end
    return units
end

local function spawnGroup(tpl, zoneName, pos)
    local gid   = DGSS._nextID; DGSS._nextID = DGSS._nextID + 1
    local gName = "DGSS_RED_" .. gid
    local hdg   = math.random() * 2 * math.pi
    local units = buildUnits(tpl.units, pos, hdg)

    -- Fix unit names for uniqueness
    for i, u in ipairs(units) do u.name = gName .. "_u" .. i end

    mist.dynAdd({
        visible  = false,
        name     = gName,
        task     = "Ground Nothing",
        country  = DGSS.RED_COUNTRY,
        category = Group.Category.GROUND,
        units    = units,
    })

    local mID = placeMarker(pos, tpl.name)
    DGSS._spawnedGroups[gName] = { zone = zoneName, spawnTime = timer.getTime(), markerID = mID }
    dgLog("Spawned " .. tpl.name .. " as " .. gName .. " in " .. zoneName)
end

-- ─────────────────────────────────────────────────────────────────────────────
--  ZONE CHECK LOOP
-- ─────────────────────────────────────────────────────────────────────────────

local function checkZones()
    local spawnsThisCycle = 0
    for zoneName, cfg in pairs(DGSS.ZONES) do
        if spawnsThisCycle >= DGSS.MAX_SPAWNS_PER_CYCLE then break end
        local zd = trigger.misc.getZone(zoneName)
        if zd then
            local current = countZoneGroups(zoneName)
            if current < cfg.minGroups then
                local needed = cfg.minGroups - current
                for _ = 1, needed do
                    if spawnsThisCycle >= DGSS.MAX_SPAWNS_PER_CYCLE then break end
                    local pos = getRandomPointInZone(zoneName)
                    if pos then
                        spawnGroup(pickTemplate(), zoneName, pos)
                        spawnsThisCycle = spawnsThisCycle + 1
                    end
                end
            elseif current < cfg.maxGroups and math.random() < 0.3 then
                local pos = getRandomPointInZone(zoneName)
                if pos then
                    spawnGroup(pickTemplate(), zoneName, pos)
                    spawnsThisCycle = spawnsThisCycle + 1
                end
            end
        end
    end
    return timer.getTime() + DGSS.CHECK_ZONES_INTERVAL
end

-- ─────────────────────────────────────────────────────────────────────────────
--  CLEANUP LOOPS
-- ─────────────────────────────────────────────────────────────────────────────

local function cleanupGroups()
    for gn, data in pairs(DGSS._spawnedGroups) do
        if not isGroupAlive(gn) then
            removeMarker(data.markerID)
            DGSS._spawnedGroups[gn] = nil
            dgLog("Cleaned dead group: " .. gn)
        end
    end
    return timer.getTime() + DGSS.CLEANUP_INTERVAL
end

local function memoryCleanup()
    for gn, _ in pairs(DGSS._spawnedGroups) do
        if not isGroupAlive(gn) then DGSS._spawnedGroups[gn] = nil end
    end
    return timer.getTime() + DGSS.MEMORY_CLEANUP_INTERVAL
end

-- ─────────────────────────────────────────────────────────────────────────────
--  INITIALISATION
-- ─────────────────────────────────────────────────────────────────────────────

local function dgssInit()
    dgLog("=== WWII Marianas DGSS initialising ===")

    refillBag()

    timer.scheduleFunction(checkZones,    {}, timer.getTime() + 10)
    timer.scheduleFunction(cleanupGroups, {}, timer.getTime() + DGSS.CLEANUP_INTERVAL)
    timer.scheduleFunction(memoryCleanup, {}, timer.getTime() + DGSS.MEMORY_CLEANUP_INTERVAL)

    dgLog("=== DGSS init complete ===")
end

timer.scheduleFunction(function() dgssInit(); return nil end, {}, timer.getTime() + 4)

trigger.action.outText("WWII Marianas DGSS (Dynamic Group Spawn System) loaded.", 10)
-- =============================================================================
--  END OF SCRIPT
--
--  QUICK REFERENCE – ME SETUP
--  ──────────────────────────
--  1. Load MIST first, then this script.
--  2. Create circle trigger zones: ZONE1 … ZONE18  (or adjust DGSS.ZONES table)
--  3. Tune per-zone minGroups / maxGroups in the DGSS.ZONES table.
--  4. Adjust DGSS.MAX_SPAWNS_PER_CYCLE to control spawn rate.
--
--  WWII UNIT TYPES USED (Japan / RED only):
--    soldier_mauser98, Type_89_I_Go, Type_98_Ke_Ni,
--    Type_94_Truck, Type_96_25mm_AA
--
--  NOTE: Verify exact DCS type strings for WWII units in your Mission Editor.
--  Open ME → Add unit → filter by WWII to see available type names.
-- =============================================================================
