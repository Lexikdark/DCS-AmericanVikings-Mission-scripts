-- =============================================================================
--  WWII Marianas – Red Automated Convoy System
--  Version : 1.0  |  Map : Marianas  |  Era : WWII
--  Requires: MIST (4.5+) loaded BEFORE this script
--
--  LOAD ORDER in Mission Editor:
--    1. mist_4_5_126.lua
--    2. WWII_Marianas_RedConvoySpawn.lua  (this file)
--
--  FEATURES:
--    - Auto-spawns Japanese convoys between ConvoyZone trigger zones
--    - 15 WWII-era convoy template compositions
--    - Route building with Off Road → On Road → Off Road waypoints
--    - Stall detection & auto-replacement for stuck convoys
--    - Configurable max simultaneous convoys, speed, stagger delay
--
--  ME SETUP:
--    Create trigger zones named  ConvoyZone1 .. ConvoyZone20  (or however
--    many convoy waypoints you want on the Marianas map). Convoys will
--    route between random pairs.
-- =============================================================================

CONVOY = {}

-- ─────────────────────────────────────────────────────────────────────────────
--  CONFIGURATION
-- ─────────────────────────────────────────────────────────────────────────────

CONVOY.MAX_CONVOYS          = 12
CONVOY.INITIAL_CONVOYS      = 3
CONVOY.CONVOY_SPEED         = 18            -- m/s (~65 km/h)
CONVOY.STAGGER_DELAY        = 120           -- seconds between initial spawns
CONVOY.MIN_TRAVEL_DISTANCE  = 32000         -- minimum route length (m) ≈ 17 nm
CONVOY.STALL_TIMEOUT        = 300           -- seconds before a convoy is considered stalled
CONVOY.SPAWN_LOOP_INTERVAL  = 180           -- seconds between spawn attempts
CONVOY.CLEANUP_INTERVAL     = 120           -- seconds between stall/cleanup checks

CONVOY.ZONE_COUNT    = 20                    -- ConvoyZone1 .. ConvoyZone20
CONVOY.ZONE_PREFIX   = "ConvoyZone"
CONVOY.COUNTRY       = country.id.JAPAN

-- ─────────────────────────────────────────────────────────────────────────────
--  WWII JAPANESE CONVOY TEMPLATES  (unit types from DCS WWII Assets Pack)
--  Each template = ordered list of DCS unit type strings.
-- ─────────────────────────────────────────────────────────────────────────────

CONVOY.TEMPLATES = {
    { "Type_94_Truck", "Type_94_Truck", "Type_94_Truck" },
    { "Type_94_Truck", "Type_94_Truck", "soldier_mauser98", "soldier_mauser98" },
    { "Type_94_Truck", "Type_94_Truck", "Type_89_I_Go", "Type_94_Truck" },
    { "Type_89_I_Go", "Type_89_I_Go", "Type_94_Truck" },
    { "Type_89_I_Go", "Type_94_Truck", "Type_94_Truck", "soldier_mauser98" },
    { "Type_98_Ke_Ni", "Type_98_Ke_Ni", "Type_94_Truck", "Type_94_Truck" },
    { "Type_98_Ke_Ni", "Type_94_Truck", "soldier_mauser98", "soldier_mauser98" },
    { "Type_94_Truck", "soldier_mauser98", "soldier_mauser98", "soldier_mauser98" },
    { "Type_89_I_Go", "Type_98_Ke_Ni", "Type_94_Truck" },
    { "Type_94_Truck", "Type_94_Truck", "Type_94_Truck", "Type_94_Truck" },
    { "soldier_mauser98", "soldier_mauser98", "Type_98_Ke_Ni", "Type_94_Truck" },
    { "Type_89_I_Go", "Type_89_I_Go", "Type_98_Ke_Ni" },
    { "Type_94_Truck", "Type_98_Ke_Ni", "Type_98_Ke_Ni", "Type_94_Truck" },
    { "soldier_mauser98", "Type_94_Truck", "Type_89_I_Go", "soldier_mauser98" },
    { "Type_98_Ke_Ni", "Type_89_I_Go", "Type_89_I_Go", "Type_94_Truck" },
}

-- ─────────────────────────────────────────────────────────────────────────────
--  INTERNAL STATE
-- ─────────────────────────────────────────────────────────────────────────────

CONVOY._activeConvoys   = {}   -- { groupName, startZone, endZone, spawnTime, lastPos }
CONVOY._nextID          = 1
CONVOY._zones           = {}   -- { [1]={x,z}, [2]={x,z}, ... }

-- ─────────────────────────────────────────────────────────────────────────────
--  HELPERS
-- ─────────────────────────────────────────────────────────────────────────────

local function cvLog(msg) env.info("[CONVOY] " .. tostring(msg)) end

local function dist2d(a, b)
    local dx = a.x - b.x; local dz = a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end

local function discoverZones()
    for i = 1, CONVOY.ZONE_COUNT do
        local zName = CONVOY.ZONE_PREFIX .. i
        local zd    = trigger.misc.getZone(zName)
        if zd then
            CONVOY._zones[i] = { x = zd.point.x, z = zd.point.z }
        end
    end
    local ct = 0; for _ in pairs(CONVOY._zones) do ct = ct + 1 end
    cvLog("Discovered " .. ct .. " convoy zones.")
end

local function pickRandomZonePair()
    local keys = {}
    for k, _ in pairs(CONVOY._zones) do keys[#keys + 1] = k end
    if #keys < 2 then return nil, nil end

    local maxAttempts = 30
    for _ = 1, maxAttempts do
        local a = keys[math.random(#keys)]
        local b = keys[math.random(#keys)]
        if a ~= b then
            local d = dist2d(CONVOY._zones[a], CONVOY._zones[b])
            if d >= CONVOY.MIN_TRAVEL_DISTANCE then return a, b end
        end
    end
    -- Fallback: just pick any two different
    local a = keys[math.random(#keys)]
    local b
    repeat b = keys[math.random(#keys)] until b ~= a
    return a, b
end

local function pickTemplate()
    return CONVOY.TEMPLATES[math.random(#CONVOY.TEMPLATES)]
end

-- ─────────────────────────────────────────────────────────────────────────────
--  ROUTE BUILDING
-- ─────────────────────────────────────────────────────────────────────────────

local function buildRoute(startPt, endPt, speed)
    -- 3-waypoint route: start (Off Road) → midpoint (On Road) → end (Off Road)
    local midX = (startPt.x + endPt.x) / 2 + math.random(-500, 500)
    local midZ = (startPt.z + endPt.z) / 2 + math.random(-500, 500)

    return {
        {
            x      = startPt.x + math.random(-50, 50),
            y      = startPt.z + math.random(-50, 50),
            speed  = speed,
            action = "Off Road",
            type   = "Turning Point",
        },
        {
            x      = midX,
            y      = midZ,
            speed  = speed,
            action = "On Road",
            type   = "Turning Point",
        },
        {
            x      = endPt.x + math.random(-50, 50),
            y      = endPt.z + math.random(-50, 50),
            speed  = speed,
            action = "Off Road",
            type   = "Turning Point",
        },
    }
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SPAWN
-- ─────────────────────────────────────────────────────────────────────────────

local function spawnConvoy()
    if #CONVOY._activeConvoys >= CONVOY.MAX_CONVOYS then return end

    local startIdx, endIdx = pickRandomZonePair()
    if not startIdx or not endIdx then
        cvLog("Not enough zones for convoy route."); return
    end

    local startPt = CONVOY._zones[startIdx]
    local endPt   = CONVOY._zones[endIdx]
    local template = pickTemplate()
    local route    = buildRoute(startPt, endPt, CONVOY.CONVOY_SPEED)

    local gid   = CONVOY._nextID; CONVOY._nextID = CONVOY._nextID + 1
    local gName = "WWII_Convoy_" .. gid

    local units = {}
    for i, uType in ipairs(template) do
        units[#units + 1] = {
            type    = uType,
            x       = startPt.x + (i - 1) * 15,
            y       = startPt.z + (i - 1) * 5,
            heading = math.atan2(endPt.z - startPt.z, endPt.x - startPt.x),
            skill   = "Average",
            name    = gName .. "_u" .. i,
        }
    end

    local groupData = {
        visible  = false,
        name     = gName,
        task     = "Ground Nothing",
        country  = CONVOY.COUNTRY,
        category = Group.Category.GROUND,
        units    = units,
        route    = { points = route },
    }

    mist.dynAdd(groupData)

    table.insert(CONVOY._activeConvoys, {
        groupName = gName,
        startZone = startIdx,
        endZone   = endIdx,
        spawnTime = timer.getTime(),
        lastPos   = { x = startPt.x, z = startPt.z },
        lastMoveT = timer.getTime(),
    })

    cvLog("Spawned " .. gName .. " from zone " .. startIdx .. " → " .. endIdx .. " (" .. #template .. " units)")
end

-- ─────────────────────────────────────────────────────────────────────────────
--  CONVOY MANAGEMENT / STALL DETECTION
-- ─────────────────────────────────────────────────────────────────────────────

local function getGroupCenter(gName)
    local g = Group.getByName(gName)
    if not g or not g:isExist() then return nil end
    local sx, sz, ct = 0, 0, 0
    for _, u in ipairs(g:getUnits()) do
        if u and u:isExist() then
            local p = u:getPoint()
            sx = sx + p.x; sz = sz + p.z; ct = ct + 1
        end
    end
    if ct == 0 then return nil end
    return { x = sx / ct, z = sz / ct }
end

local function isConvoyAlive(gName)
    local g = Group.getByName(gName)
    if not g or not g:isExist() then return false end
    for _, u in ipairs(g:getUnits()) do
        if u and u:isExist() and u:getLife() > 1 then return true end
    end
    return false
end

local function destroyConvoy(gName)
    local g = Group.getByName(gName)
    if g and g:isExist() then g:destroy() end
end

local function convoyCleanupLoop()
    local now      = timer.getTime()
    local toRemove = {}

    for i, cv in ipairs(CONVOY._activeConvoys) do
        if not isConvoyAlive(cv.groupName) then
            table.insert(toRemove, i)
            cvLog(cv.groupName .. " destroyed / dead – removing.")
        else
            -- Stall check
            local pos = getGroupCenter(cv.groupName)
            if pos then
                if cv.lastPos and dist2d(pos, cv.lastPos) > 30 then
                    cv.lastPos   = pos
                    cv.lastMoveT = now
                elseif (now - cv.lastMoveT) > CONVOY.STALL_TIMEOUT then
                    cvLog(cv.groupName .. " stalled – destroying.")
                    destroyConvoy(cv.groupName)
                    table.insert(toRemove, i)
                end
            end

            -- Arrived check (within 500 m of destination)
            if pos and cv.endZone and CONVOY._zones[cv.endZone] then
                if dist2d(pos, CONVOY._zones[cv.endZone]) < 500 then
                    cvLog(cv.groupName .. " arrived at destination zone " .. cv.endZone)
                    destroyConvoy(cv.groupName)
                    table.insert(toRemove, i)
                end
            end
        end
    end

    -- Remove from back to front to avoid index issues
    table.sort(toRemove, function(a, b) return a > b end)
    for _, idx in ipairs(toRemove) do
        table.remove(CONVOY._activeConvoys, idx)
    end

    return now + CONVOY.CLEANUP_INTERVAL
end

local function convoySpawnLoop()
    if #CONVOY._activeConvoys < CONVOY.MAX_CONVOYS then
        spawnConvoy()
    end
    return timer.getTime() + CONVOY.SPAWN_LOOP_INTERVAL
end

-- ─────────────────────────────────────────────────────────────────────────────
--  STATUS (F10 menu – optional)
-- ─────────────────────────────────────────────────────────────────────────────

local function setupConvoyMenu()
    if not missionCommands then return end
    missionCommands.addCommandForCoalition(coalition.side.RED, "Convoy Status", nil, function()
        trigger.action.outTextForCoalition(coalition.side.RED,
            "Active convoys: " .. #CONVOY._activeConvoys .. " / " .. CONVOY.MAX_CONVOYS, 12)
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
--  INITIALISATION
-- ─────────────────────────────────────────────────────────────────────────────

local function convoyInit()
    cvLog("=== WWII Marianas Red Convoy System initialising ===")
    discoverZones()
    setupConvoyMenu()

    -- Stagger initial spawns
    for i = 1, CONVOY.INITIAL_CONVOYS do
        timer.scheduleFunction(function()
            spawnConvoy()
            return nil
        end, {}, timer.getTime() + (i - 1) * CONVOY.STAGGER_DELAY)
    end

    -- Start loops
    timer.scheduleFunction(convoyCleanupLoop, {}, timer.getTime() + CONVOY.CLEANUP_INTERVAL)
    timer.scheduleFunction(convoySpawnLoop,   {}, timer.getTime() + CONVOY.SPAWN_LOOP_INTERVAL + CONVOY.INITIAL_CONVOYS * CONVOY.STAGGER_DELAY)

    cvLog("=== Convoy init complete ===")
end

timer.scheduleFunction(function() convoyInit(); return nil end, {}, timer.getTime() + 3)

trigger.action.outText("WWII Marianas Red Convoy Spawn Script loaded.", 10)
-- =============================================================================
--  END OF SCRIPT
--
--  QUICK REFERENCE – ME SETUP
--  ──────────────────────────
--  1. Load MIST first, then this script.
--  2. Create trigger zones: ConvoyZone1, ConvoyZone2, … ConvoyZone20
--     (place them along roads/paths on the Marianas map).
--  3. Adjust CONVOY.ZONE_COUNT if you have more/fewer zones.
--  4. Tune CONVOY.MAX_CONVOYS, CONVOY.INITIAL_CONVOYS, CONVOY.CONVOY_SPEED
--     to taste.
--
--  WWII JAPANESE UNIT TYPES USED:
--    Type_94_Truck    – Standard IJA logistics truck
--    Type_89_I_Go     – Type 89 I-Go medium tank
--    Type_98_Ke_Ni    – Type 98 Ke-Ni light tank
--    soldier_mauser98 – Japanese infantry soldier
--
--  NOTE: If the DCS WWII Assets Pack uses different type strings for
--  Japanese units, update the TEMPLATES table accordingly. Check your
--  ME unit database for exact type names.
-- =============================================================================
