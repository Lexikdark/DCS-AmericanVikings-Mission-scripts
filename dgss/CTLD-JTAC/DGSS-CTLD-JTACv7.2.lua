DGSS_CTLD = {}

-- ============================================================================
-- GLOBAL ERROR LOGGER - Captures and logs all script errors with context
-- ============================================================================

function DGSS_CTLD.spawnGroup(groupName, templateName, position, kind)
    local template
    if kind == "vehicle" or (DGSS_CTLD.VEHICLE_TEMPLATES and DGSS_CTLD.VEHICLE_TEMPLATES[templateName]) then
        template = DGSS_CTLD.VEHICLE_TEMPLATES and DGSS_CTLD.VEHICLE_TEMPLATES[templateName] or nil
    else
        template = DGSS_CTLD.TROOP_TEMPLATES and DGSS_CTLD.TROOP_TEMPLATES[templateName] or nil
    end
    if not template then
        env.warning("[DGSS_CTLD] Template not found: " .. tostring(templateName) .. " (kind: " .. tostring(kind) .. ")")
        return nil
    end

    local countryId = DGSS_CTLD.COUNTRY or country.id.USA
    if countryId ~= country.id.USA then
        env.warning("[DGSS_CTLD] WARNING: COUNTRY is not set to USA. Spawning may fail if unit types are not available for this country.")
    end

    local units = {}
    for i, unitType in ipairs(template.units) do
        -- Check if the unit type exists for the country (best effort, DCS API is limited)
        -- This is a soft check; DCS will silently fail if the type is not valid for the country
        table.insert(units, {
            type    = unitType,
            x       = position.x + (i-1)*3, -- Easting
            y       = position.z,           -- Northing (DCS expects y = z)
            heading = 0,
        })
    end

    local groupData = { name = groupName, units = units }

    local group = coalition.addGroup(
        countryId,
        Group.Category.GROUND,
        groupData
    )

    if group then
        return group
    else
        env.warning("[DGSS_CTLD] Failed to spawn group: " .. groupName .. " | Template: " .. tostring(templateName) .. " | Kind: " .. tostring(kind))
        return nil
    end
end
--[[ ================================================================
     DGSS CTLD + JTAC SYSTEM v3.5 - FULLY AUTONOMOUS
     ================================================================ ]]
-- An advanced logistics and JTAC system for DCS missions
-- 
-- FEATURES:
--  Autonomous JTAC target acquisition and laser designation
--  Internal JTAC_Manager (no external script needed)
--  Real-time enemy detection within scan zones (10km)
--  Automatic 9-line CAS callout generation
--  Player-controlled target selection with manual override
--  Complete troop and vehicle transport system
--  Hard-limit enforcement (max 10 JTAC teams + 10 vehicles)
--  Performance-optimized menu system (3s polling)
--  System status monitoring with diagnostics
--  CTLD library integration for laser marking
--  Fallback laser logging if CTLD unavailable
-- 
-- CAPABILITIES NOW WORKING:
-- 1. Targeting & Lasing:
--    - Autonomous JTAC teams automatically scan for enemies
--    - Lase nearest target continuously (every 2 seconds)
--    - Players can manually select targets (Next/Previous Target)
--    - Auto-fallback to nearest when manual target dies
-- 
-- 2. Target Detection:
--    - Scans 10,000m radius around each JTAC position
--    - Returns sorted list of enemies by distance
--    - Updates available targets every 2 seconds
-- 
-- 3. Hard Limits:
--    - Max 10 JTAC teams (enforced at spawn time)
--    - Max 10 JTAC vehicles (enforced at spawn time)
--    - Verified live group count (only counts existing units)
-- 
-- 4. Performance:
--    - Menu rebuilds only on JTAC count changes (not every cycle)
--    - Menu polling: 3 seconds (was 2 seconds)
--    - JTAC targeting: 2 seconds
--    - Status monitoring: 60 seconds
--    - Cleanup loop: 600 seconds
-- 
-- USAGE:
-- 1. Spawn JTAC team or vehicle in CTLD zone
-- 2. System auto-registers and starts scanning
-- 3. Access via "JTAC Control" menu in-game
-- 4. Select team -> Select Target -> Use Next/Previous to cycle
-- 5. Or use "Auto Target (Nearest)" for autonomous lasing
-- 
-- CONFIG:
-- - MAX_JTAC_TEAMS = 10 (line ~458)
-- - MAX_JTAC_VEHICLES = 10 (line ~459)
-- - SCAN_RADIUS = 10000 meters (line ~79)
-- - Menu poll interval = 3 seconds (line ~2091)
-- - Status monitor interval = 60 seconds (line ~2121)
-- 
--================================================================-- Stub JTAC_Manager for backward compatibility (now uses DGSS_CTLD.JTAC_REGISTRY)
JTAC_Manager = {}
JTAC_Manager.active = {}  -- Legacy reference, not used

-- Remove a JTAC from the registry (called when loading into transport or on destroy)
function JTAC_Manager.unregisterJTAC(groupName)
    if not groupName then return end
    DGSS_CTLD.JTAC_REGISTRY[groupName] = nil
    ctld.destroyLaser(groupName)
    env.info("[JTAC_Manager] Unregistered JTAC: " .. tostring(groupName))
end

-- Update the laser code for a registered JTAC
function JTAC_Manager.updateLaserCode(groupName, code)
    if not groupName or not code then return end
    local jtac = DGSS_CTLD.JTAC_REGISTRY[groupName]
    if jtac then
        jtac.laser = code
        env.info(string.format("[JTAC_Manager] Laser code for %s updated to %d", groupName, code))
    end
end

-- Static JTAC team and vehicle names
DGSS_CTLD.STATIC_JTAC_TEAMS = {
    "JTAC_Team_1", "JTAC_Team_2", "JTAC_Team_3", "JTAC_Team_4", "JTAC_Team_5",
    "JTAC_Team_6", "JTAC_Team_7", "JTAC_Team_8", "JTAC_Team_9", "JTAC_Team_10"
}
DGSS_CTLD.STATIC_JTAC_VEHICLES = {
    "JTAC_Vehicle_1", "JTAC_Vehicle_2", "JTAC_Vehicle_3", "JTAC_Vehicle_4", "JTAC_Vehicle_5",
    "JTAC_Vehicle_6", "JTAC_Vehicle_7", "JTAC_Vehicle_8", "JTAC_Vehicle_9", "JTAC_Vehicle_10"
}

-- Helper to check if a static JTAC name is available (not active)
function DGSS_CTLD.isJtacNameAvailable(name)
    return DGSS_CTLD.JTAC_REGISTRY[name] == nil
end

-- Helper to get next available static JTAC name (team or vehicle)
function DGSS_CTLD.getAvailableJtacName(kind)
    local list = (kind == "vehicle") and DGSS_CTLD.STATIC_JTAC_VEHICLES or DGSS_CTLD.STATIC_JTAC_TEAMS
    for _, name in ipairs(list) do
        if DGSS_CTLD.isJtacNameAvailable(name) then
            return name
        end
    end
    return nil
end

-- Helper to respawn JTAC by static name (to be called by your spawn logic)
function DGSS_CTLD.spawnStaticJtac(kind, templateName, position)
    local name = DGSS_CTLD.getAvailableJtacName(kind)
    if not name then
        env.warning("No available JTAC names for kind: " .. tostring(kind))
        return nil
    end
    local group = DGSS_CTLD.spawnGroup(name, templateName, position, kind)
    if group then
        DGSS_CTLD.registerJTAC(name, 1688)
        env.info("[DGSS_CTLD] Spawned and registered JTAC group: " .. name)
        return name
    else
        env.warning("[DGSS_CTLD] Failed to spawn JTAC group: " .. name)
        return nil
    end
end

-- Remove JTAC from registry when destroyed (call from event handler)
function DGSS_CTLD.onJtacDestroyed(groupName)
    DGSS_CTLD.JTAC_REGISTRY[groupName] = nil
end

----------------------------------------------------------------
-- JTAC AUTO-LASE ENGINE (NO LONGER USES JTAC_Manager - uses DGSS_CTLD.JTAC_REGISTRY)
-- JTACs scan 25,000 ft (7,620 m) around them and lase nearest enemy
-- No line-of-sight required
----------------------------------------------------------------

SCAN_RADIUS = 10000  -- meters (~5.4 nm) — reduced from 18520 for performance

----------------------------------------------------------------
-- COORDINATE CONVERSION UTILITIES
----------------------------------------------------------------

-- Convert decimal degrees to degrees + decimal minutes
local function toDegMin(dec)
    local deg = math.floor(math.abs(dec))
    local min = (math.abs(dec) - deg) * 60
    return deg, min
end

-- Convert DCS position to formatted coordinate strings (MGRS and Lat/Lon DM)
local function formatCoordinates(pos)
    if not pos then return "Unknown", "Unknown" end
    
    local lat, lon = coord.LOtoLL(pos)
    local mgrs = coord.LLtoMGRS(lat, lon)
    
    -- Format MGRS
    local mgrsStr = string.format("%s %s %05d %05d",
        mgrs.UTMZone,
        mgrs.MGRSDigraph,
        mgrs.Easting,
        mgrs.Northing
    )
    
    -- Format Lat/Lon in Degrees Decimal Minutes
    local latDeg, latMin = toDegMin(lat)
    local lonDeg, lonMin = toDegMin(lon)
    local latHem = (lat >= 0) and "N" or "S"
    local lonHem = (lon >= 0) and "E" or "W"
    
    local latLonStr = string.format("%s %02d° %.3f'  %s %03d° %.3f'",
        latHem, latDeg, latMin,
        lonHem, lonDeg, lonMin
    )
    
    return mgrsStr, latLonStr
end

-- Find all enemies within scan radius and return sorted list.
-- LOS is checked ONCE per group (on the geometrically nearest unit only),
-- not per-unit, to avoid hundreds of expensive land.isVisible raycasts.
local function findAllNearbyEnemies(jtacUnit, cachedRedGroups)
    if not jtacUnit or not jtacUnit:isExist() then return {} end

    local pos = jtacUnit:getPoint()
    if not pos then return {} end

    local jtacEyePos = {x = pos.x, y = pos.y + 2.0, z = pos.z}
    local enemies    = {}
    local maxDistSq  = SCAN_RADIUS * SCAN_RADIUS
    local redGroups  = cachedRedGroups or {}

    for _, g in ipairs(redGroups) do
        if g and g:isExist() then
            local groupUnits = g:getUnits()

            -- Step 1: find the closest unit by distance (no LOS cost)
            local closestDistSq = nil
            local closestUnit   = nil
            for _, u in ipairs(groupUnits) do
                if u and u:isExist() then
                    local p = u:getPoint()
                    if p then
                        local dx = p.x - pos.x
                        local dz = p.z - pos.z
                        local distSq = dx*dx + dz*dz
                        if distSq <= maxDistSq then
                            if not closestDistSq or distSq < closestDistSq then
                                closestDistSq = distSq
                                closestUnit   = u
                            end
                        end
                    end
                end
            end

            -- Step 2: single LOS check on that closest unit only
            if closestUnit and closestDistSq then
                local p = closestUnit:getPoint()
                local targetPos = {x = p.x, y = p.y + 1.0, z = p.z}
                local hasLOS = true
                if land and land.isVisible then
                    local ok, result = pcall(land.isVisible, jtacEyePos, targetPos)
                    hasLOS = ok and result
                end
                if hasLOS then
                    local typeName = "Unknown"
                    pcall(function() typeName = closestUnit:getTypeName() end)
                    table.insert(enemies, {
                        group         = g,
                        groupName     = g:getName(),
                        units         = groupUnits,
                        closestDistSq = closestDistSq,
                        closestDist   = math.sqrt(closestDistSq),
                        typeName      = typeName,
                        dist          = math.sqrt(closestDistSq),
                    })
                end
            end
        end
    end

    table.sort(enemies, function(a, b) return a.closestDistSq < b.closestDistSq end)
    return enemies
end

-- Find nearest enemy ground unit within radius (returns first unit from nearest group)
local function findNearestEnemy(jtacUnit, cachedRedGroups)
    local enemies = findAllNearbyEnemies(jtacUnit, cachedRedGroups)
    if #enemies > 0 then
        local nearestGroup = enemies[1].group
        if nearestGroup and nearestGroup:isExist() then
            local units = nearestGroup:getUnits()
            if #units > 0 then
                return units[1]
            end
        end
    end
    return nil
end

local function laseTarget(jtacName, jtacData, jtacUnit, cachedRedGroups)
    -- Update available targets list from JTAC zone (using cached red groups)
    jtacData.availableTargets = findAllNearbyEnemies(jtacUnit, cachedRedGroups)
    
    -- Store previous target for change detection
    local previousTarget = jtacData.target
    local previousTargetName = jtacData.currentTargetName
    
    -- Handle manual target override
    if jtacData.manualOverride and jtacData.targetIndex > 0 then
        if jtacData.targetIndex <= #jtacData.availableTargets then
            local targetGroup = jtacData.availableTargets[jtacData.targetIndex].group
            if targetGroup and targetGroup:isExist() then
                local units = targetGroup:getUnits()
                if #units > 0 then
                    jtacData.target = units[1]
                end
            end
        else
            jtacData.manualOverride = false
            jtacData.targetIndex = 0
        end
    end
    
    -- Auto-acquire nearest if no manual override or target dead
    if not jtacData.manualOverride or not jtacData.target or not jtacData.target:isExist() then
        jtacData.target = findNearestEnemy(jtacUnit, cachedRedGroups)
        jtacData.targetIndex = 0
        if not jtacData.target then
            -- Target lost - notify if we had one before
            if previousTarget and jtacData.currentTargetName then
                trigger.action.outTextForCoalition(coalition.side.BLUE,
                    string.format("%s: No targets in range. Laser OFF. Scanning...", jtacName), 8)
                jtacData.currentTargetName = nil
            end
            -- Stop lasing when no targets are nearby
            pcall(function()
                ctld.destroyLaser(jtacName)
            end)
            jtacData.lasedAt = 0
            return
        end
    end

    local tgt = jtacData.target
    local tgtPos = pcall(function() return tgt:getPoint() end) and tgt:getPoint() or nil
    if not tgtPos then 
        env.warning(string.format("[JTAC LASE] %s: target position invalid", jtacName))
        return 
    end
    
    -- Get target type name
    local targetTypeName = "Unknown"
    pcall(function() targetTypeName = tgt:getTypeName() end)
    
    -- Detect target change and announce
    local targetChanged = false
    if not previousTarget then
        targetChanged = true  -- First target acquisition
    elseif not previousTarget:isExist() then
        targetChanged = true  -- Previous target destroyed
    elseif previousTarget:getID() ~= tgt:getID() then
        targetChanged = true  -- Different target
    end
    
    if targetChanged then
        -- Get formatted coordinates
        local mgrsStr, latLonStr = formatCoordinates(tgtPos)
        
        -- Calculate distance from JTAC to target
        local jtacPos = jtacUnit:getPoint()
        local dx = tgtPos.x - jtacPos.x
        local dz = tgtPos.z - jtacPos.z
        local distMeters = math.sqrt(dx*dx + dz*dz)
        local distNM = distMeters / 1852
        
        -- Build callout message
        local calloutMsg = string.format(
            "%s: MARKING NEW TARGET\n" ..
            "Type: %s\n" ..
            "MGRS: %s\n" ..
            "Lat/Lon: %s\n" ..
            "Distance: %.1f NM\n" ..
            "Laser Code: %d",
            jtacName,
            targetTypeName,
            mgrsStr,
            latLonStr,
            distNM,
            jtacData.laser
        )
        
        trigger.action.outTextForCoalition(coalition.side.BLUE, calloutMsg, 15)
        jtacData.currentTargetName = targetTypeName
        
        env.info(string.format("[JTAC] %s marking new target: %s at %s", jtacName, targetTypeName, mgrsStr))
    end

    -- Get JTAC unit for laser source
    local jtacGroup = Group.getByName(jtacName)
    if not jtacGroup or not jtacGroup:isExist() then
        env.warning(string.format("[JTAC LASE] %s: group doesn't exist", jtacName))
        return
    end
    
    local jtacUnit = jtacGroup:getUnit(1)
    if not jtacUnit or not jtacUnit:isExist() then
        env.warning(string.format("[JTAC LASE] %s: unit doesn't exist", jtacName))
        return
    end

    -- Use CTLD laser system (now implemented below)
    local success = pcall(function()
        ctld.createLaser(jtacUnit, tgtPos, jtacData.laser, jtacName)
        jtacData.lasedAt = timer.getTime()
    end)
    
    if not success then
        env.warning(string.format("[JTAC LASE] %s: laser creation failed", jtacName))
    end
end

----------------------------------------------------------------
-- CTLD LASER SPOT SYSTEM (DCS Spot API Implementation)
----------------------------------------------------------------

-- Initialize ctld namespace for laser functions
ctld = ctld or {}
ctld.activeSpots = ctld.activeSpots or {}

-- Create laser designation using DCS Spot API
function ctld.createLaser(sourceUnit, targetPos, laserCode, jtacName)
    if not sourceUnit or not sourceUnit:isExist() then
        env.warning("[CTLD] createLaser: invalid source unit")
        return false
    end
    
    if not targetPos or not targetPos.x or not targetPos.y or not targetPos.z then
        env.warning("[CTLD] createLaser: invalid target position")
        return false
    end
    
    -- Destroy old spot if it exists for this JTAC
    if ctld.activeSpots[jtacName] then
        local oldSpot = ctld.activeSpots[jtacName]
        if oldSpot.spot and oldSpot.spot.destroy then
            pcall(function() oldSpot.spot:destroy() end)
        end
        if oldSpot.irSpot and oldSpot.irSpot.destroy then
            pcall(function() oldSpot.irSpot:destroy() end)
        end
        ctld.activeSpots[jtacName] = nil
    end
    
    -- Create IR pointer (visible to NVGs/FLIR) + laser spot
    local offset = {x = 0, y = 2.0, z = 0}  -- 2m above unit
    
    local spot = nil
    local irSpot = nil
    
    -- Create laser spot (weapons can lock onto this)
    pcall(function()
        spot = Spot.createLaser(sourceUnit, offset, targetPos, laserCode)
    end)
    
    -- Create IR pointer (visible in targeting pods)
    pcall(function()
        irSpot = Spot.createInfraRed(sourceUnit, offset, targetPos)
    end)
    
    if not spot then
        env.warning(string.format("[CTLD] Failed to create laser spot for %s", jtacName or "unknown"))
        return false
    end
    
    -- Track active spot
    ctld.activeSpots[jtacName] = {
        spot = spot,
        irSpot = irSpot,
        code = laserCode,
        targetPos = targetPos,
        sourceUnit = sourceUnit,
        createdAt = timer.getTime(),
    }
    
    return true
end

-- Destroy laser spot for a JTAC
function ctld.destroyLaser(jtacName)
    if not ctld.activeSpots[jtacName] then return end
    
    local spotData = ctld.activeSpots[jtacName]
    
    -- Destroy laser spot
    if spotData.spot and spotData.spot.destroy then
        pcall(function() spotData.spot:destroy() end)
    end
    
    -- Destroy IR spot
    if spotData.irSpot and spotData.irSpot.destroy then
        pcall(function() spotData.irSpot:destroy() end)
    end
    
    ctld.activeSpots[jtacName] = nil
end

-- Cleanup dead laser spots (called periodically)
function ctld.cleanupDeadSpots()
    local toRemove = {}
    
    for jtacName, spotData in pairs(ctld.activeSpots) do
        local shouldRemove = false
        
        -- Check if source unit still exists
        if not spotData.sourceUnit or not spotData.sourceUnit:isExist() then
            shouldRemove = true
        end
        
        -- Check if JTAC still registered
        if not DGSS_CTLD.JTAC_REGISTRY[jtacName] then
            shouldRemove = true
        end
        
        if shouldRemove then
            table.insert(toRemove, jtacName)
        end
    end
    
    for _, jtacName in ipairs(toRemove) do
        ctld.destroyLaser(jtacName)
    end
    
    if #toRemove > 0 then
        env.info(string.format("[CTLD] Cleaned up %d dead laser spots", #toRemove))
    end
end

-- Schedule periodic spot cleanup
local function scheduleSpotCleanup()
    ctld.cleanupDeadSpots()
    
    if mist and mist.scheduleFunction then
        mist.scheduleFunction(scheduleSpotCleanup, {}, timer.getTime() + 60)
    else
        timer.scheduleFunction(scheduleSpotCleanup, {}, timer.getTime() + 60)
    end
end

-- Start spot cleanup loop
if mist and mist.scheduleFunction then
    mist.scheduleFunction(scheduleSpotCleanup, {}, timer.getTime() + 60)
else
    timer.scheduleFunction(scheduleSpotCleanup, {}, timer.getTime() + 60)
end

----------------------------------------------------------------
-- END CTLD LASER SPOT SYSTEM
----------------------------------------------------------------

-- Deploy smoke marker at a position for a JTAC
function DGSS_CTLD.DeploySmoke(jtacName, tgtPos, color)
    trigger.action.smoke(tgtPos, color or 1)
    env.info(string.format("[DGSS_CTLD] %s deployed smoke at (%.0f, %.0f, %.0f)", jtacName, tgtPos.x, tgtPos.y, tgtPos.z))
end

-- Deploy smoke on the target being lased by a JTAC team
local function deployTargetSmoke(jtacName)
    if not DGSS_CTLD or not DGSS_CTLD.JTAC_REGISTRY then return end
    
    local jtacData = DGSS_CTLD.JTAC_REGISTRY[jtacName]
    if not jtacData then
        env.info(string.format("[JTAC %s] Not registered in JTAC_REGISTRY!", jtacName))
        return
    end
    if not jtacData.target or not jtacData.target:isExist() then
        env.info(string.format("[JTAC %s] No active target for smoke deployment!", jtacName))
        return
    end
    
    local tgt = jtacData.target
    local tgtPos = pcall(function() return tgt:getPoint() end) and tgt:getPoint() or nil
    if not tgtPos then
        env.info(string.format("[JTAC %s] Cannot get target position for smoke!", jtacName))
        return
    end
    
    -- Smoke colors available
    local smokeColors = {
        trigger.smokeColor.Red,
    }
    
    -- Use red smoke only
    local smokeColor = trigger.smokeColor.Red
    
    -- Deploy smoke at target location
    trigger.action.smoke(tgtPos, smokeColor)
    
    env.info(string.format(
        "[JTAC %s] Smoke deployed on target %s at (%.0f, %.0f, %.0f)",
        jtacName, tgt:getTypeName(), tgtPos.x, tgtPos.y, tgtPos.z
    ))
end

-- Staggered JTAC update: 1 JTAC per tick, 3s between ticks.
-- With MAX_JTAC_TEAMS=10 this gives a ~30s full cycle - same effective
-- rate as before but spreads raycasts across multiple frames instead of
-- firing all land.isVisible calls in a single Lua timeslice.
local _jtacBatchIndex     = 0   -- current position in the sorted key list
local _jtacSortedKeys     = {}  -- stable-ordered list of registry keys
local _jtacCachedRedGroups = {} -- red ground groups, refreshed once per cycle

local function jtacTickOne()
    if not DGSS_CTLD or not DGSS_CTLD.JTAC_REGISTRY then
        return
    end

    -- Rebuild key list and refresh red cache at the start of each cycle
    if _jtacBatchIndex <= 0 or _jtacBatchIndex > #_jtacSortedKeys then
        _jtacSortedKeys = {}
        for k in pairs(DGSS_CTLD.JTAC_REGISTRY) do
            _jtacSortedKeys[#_jtacSortedKeys + 1] = k
        end
        table.sort(_jtacSortedKeys)  -- stable order each cycle

        _jtacCachedRedGroups = {}
        pcall(function()
            _jtacCachedRedGroups = coalition.getGroups(coalition.side.RED, Group.Category.GROUND) or {}
        end)

        _jtacBatchIndex = 1
    end

    -- Nothing registered
    if #_jtacSortedKeys == 0 then
        _jtacBatchIndex = 0
        return
    end

    -- Process exactly one JTAC this tick
    local groupName = _jtacSortedKeys[_jtacBatchIndex]
    _jtacBatchIndex = _jtacBatchIndex + 1

    if groupName then
        local data = DGSS_CTLD.JTAC_REGISTRY[groupName]
        if data then
            local g = Group.getByName(groupName)
            if g and g:isExist() then
                local u = g:getUnit(1)
                if u and u:isExist() then
                    data.lastKnownPosition = u:getPoint()
                    laseTarget(groupName, data, u, _jtacCachedRedGroups)
                else
                    DGSS_CTLD.JTAC_REGISTRY[groupName] = nil
                end
            else
                DGSS_CTLD.JTAC_REGISTRY[groupName] = nil
            end
        end
    end
end

-- Schedule each JTAC tick 3s apart.
-- Full cycle = 3s × MAX_JTAC_TEAMS (10) = 30s, same as the old monolithic loop.
local function scheduleJtacLoop()
    jtacTickOne()

    if mist and mist.scheduleFunction then
        mist.scheduleFunction(scheduleJtacLoop, {}, timer.getTime() + 3)
    else
        timer.scheduleFunction(scheduleJtacLoop, {}, timer.getTime() + 3)
    end
end

if mist and mist.scheduleFunction then
    mist.scheduleFunction(scheduleJtacLoop, {}, timer.getTime() + 3)
else
    timer.scheduleFunction(scheduleJtacLoop, {}, timer.getTime() + 3)
end

----------------------------------------------------------------
-- END INTERNAL JTAC MANAGER
----------------------------------------------------------------

----------------------------------------------------------------
-- DGSS CTLD + JTAC SYSTEM (STATIC MENU VERSION)
-- This version is integrated with an external JTAC_Manager.
-- CTLD-JTAC handles:
--   * Troop/vehicle spawn & transport
--   * JTAC team spawning, registry, menus, and laser code persistence
-- JTAC_Manager handles:
--   * Target selection & reservation
--   * Lasing via CTLD
--   * Spot reports and 9-line brevity messages
----------------------------------------------------------------

-- DGSS_CTLD already initialized above for JTAC_REGISTRY

----------------------------------------------------------------
-- CONFIGURATION
----------------------------------------------------------------

DGSS_CTLD.COALITION = coalition.side.BLUE
DGSS_CTLD.COUNTRY   = country.id.USA

-- CTLD zones (for spawning troops/vehicles)
DGSS_CTLD.ZONES = {
    { name = "RAMAT_DAVID" },
    { name = "ROSH_PINA" },
    { name = "KIRYAT_SHMONA" },
    { name = "MEGIDDO" },
    { name = "HAIFA" },
    { name = "PAHPOS" },
    { name = "FOB_BRAVO" },
    { name = "FOB_DELTA" },
    { name = "FOB_CHARLIE" },
    { name = "FOB_ECHO" },
    { name = "FOB_ALPHA" },
    { name = "FOB_FOXTROT" },
    { name = "FOB_HOTEL" },
    { name = "FOB_GOLF" },
    { name = "FOB_INDIA" },

}

-- Transport capacity (by unit type) for troops
DGSS_CTLD.CAPACITY = {
    ["UH-1H"]        = 8,
    ["Mi-8MT"]       = 20,
    ["Mi-24P"]       = 4,
    ["SA342M"]       = 2,
    ["SA342L"]       = 2,
    ["SA342Mistral"] = 4,
    ["SA342Minigun"] = 2,
    ["CH-47Fbl1"]    = 33,
    ["C-130J-30"]    = 66,
    ["MH-6J"]        = 6,
}

-- Which aircraft can transport troops
DGSS_CTLD.VALID_TROOP_TRANSPORT = {
    ["UH-1H"]        = true,
    ["Mi-8MT"]       = true,
    ["Mi-24P"]       = true,
    ["SA342M"]       = true,
    ["SA342L"]       = true,
    ["SA342Mistral"] = true,
    ["SA342Minigun"] = true,
    ["CH-47Fbl1"]    = true,
    ["MH-6J"]        = true,
    ["C-130J-30"]    = true,

}

-- Which aircraft can transport vehicles
DGSS_CTLD.VALID_VEHICLE_TRANSPORT = {
    ["UH-1H"]     = true,
    ["Mi-8MT"]    = true,
    ["CH-47Fbl1"] = true,

    ["C-130J-30"] = true,
}

-- Load/Unload operational limits
DGSS_CTLD.MAX_LOAD_SPEED    = 5.1  -- m/s (10 knots) - maximum speed to load troops/vehicles
DGSS_CTLD.MAX_LOAD_ALTITUDE = 7.6  -- meters AGL (25 feet) - maximum altitude to load
DGSS_CTLD.MAX_UNLOAD_SPEED  = 5.1  -- m/s (10 knots) - maximum speed to unload troops/vehicles
DGSS_CTLD.MAX_UNLOAD_ALTITUDE = 7.6  -- meters AGL (25 feet) - maximum altitude to unload

-- Check speed and altitude limits for load/unload operations
function DGSS_CTLD.checkLoadUnloadConditions(unit, isLoad)
    if not unit or not unit:isExist() then
        return false, "Aircraft no longer exists!"
    end

    local unitPos = unit:getPoint()
    if not unitPos then
        return false, "Cannot determine aircraft position!"
    end

    -- Get current speed
    local vel = unit:getVelocity()
    local speed = 0
    if vel then
        speed = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
    end

    -- Get altitude AGL (above ground level)
    -- Note: unit:getAltitude() doesn't exist in DCS! Use getPoint().y for MSL altitude
    local alt = unitPos.y
    local terrain_alt = land.getHeight({x = unitPos.x, y = unitPos.z}) or 0
    local agl = alt - terrain_alt

    -- Determine which limits apply
    local max_speed = isLoad and DGSS_CTLD.MAX_LOAD_SPEED or DGSS_CTLD.MAX_UNLOAD_SPEED
    local max_alt = isLoad and DGSS_CTLD.MAX_LOAD_ALTITUDE or DGSS_CTLD.MAX_UNLOAD_ALTITUDE
    local operation = isLoad and "load" or "unload"

    -- Check speed
    if speed > max_speed then
        return false, string.format("Speed too high to %s! Current: %.1f m/s (%.1f knots), Max: %.1f m/s (%.1f knots)",
            operation, speed, speed * 1.944, max_speed, max_speed * 1.944)
    end

    -- Check altitude
    if agl > max_alt then
        return false, string.format("Altitude too high to %s! Current: %.1f m AGL, Max: %.1f m AGL",
            operation, agl, max_alt)
    end

    return true, "Conditions OK"
end

----------------------------------------------------------------
-- TROOP GROUP TEMPLATES (WITH CATEGORY + DISPLAY NAME)
----------------------------------------------------------------
DGSS_CTLD.TROOP_TEMPLATES = {

    INF_SQUAD_LIGHT = {
        namePrefix  = "INF_LIGHT",
        displayName = "Light Infantry Squad",
        category    = "Infantry",
        units = {
            "Soldier M4","Soldier M4","Soldier M4","Soldier M4",
            "Soldier M249",
            "Soldier RPG",
        },
    },

    INF_SQUAD_MEDIUM = {
        namePrefix  = "INF_MEDIUM",
        displayName = "Medium Infantry Squad",
        category    = "Infantry",
        units = {
            "Soldier M4","Soldier M4","Soldier M4","Soldier M4",
            "Soldier M4","Soldier M4","Soldier M4","Soldier M4",
            "Soldier M249","Soldier M249",
            "Soldier RPG","Soldier RPG",
        },
    },

    INF_SQUAD_LARGE = {
        namePrefix  = "INF_LARGE",
        displayName = "Large Infantry Squad",
        category    = "Infantry",
        units = {
            "Soldier M4","Soldier M4","Soldier M4","Soldier M4","Soldier M4","Soldier M4",
            "Soldier M4","Soldier M4","Soldier M4","Soldier M4","Soldier M4","Soldier M4",
            "Soldier M249","Soldier M249","Soldier M249","Soldier M249",
            "Soldier RPG","Soldier RPG","Soldier RPG","Soldier RPG",
        },
    },

    M249_SQUAD_LIGHT = {
        namePrefix  = "M249_LIGHT",
        displayName = "Light M249 Support Team",
        category    = "Support",
        units = {
            "Soldier M249","Soldier M249",
            "Soldier M4","Soldier M4",
            "Soldier RPG","Soldier RPG",
        },
    },

    M249_SQUAD_MEDIUM = {
        namePrefix  = "M249_MEDIUM",
        displayName = "Medium M249 Support Team",
        category    = "Support",
        units = {
            "Soldier M249","Soldier M249","Soldier M249","Soldier M249",
            "Soldier M4","Soldier M4","Soldier M4","Soldier M4",
            "Soldier RPG","Soldier RPG","Soldier RPG","Soldier RPG",
        },
    },

    AT_TEAM_LIGHT = {
        namePrefix  = "AT_LIGHT",
        displayName = "Light Anti-Tank Team",
        category    = "Anti-Tank",
        units = {
            "Soldier RPG","Soldier RPG","Soldier RPG",
            "Soldier M4","Soldier M4",
            "Soldier M249",
        },
    },


        -- Add 5 static JTAC Team templates
        ["JTAC Team 1"] = {
            namePrefix  = "JTAC_TEAM_1",
            displayName = "JTAC Team 1",
            category    = "JTAC",
            units = { "Stinger comm", "Stinger comm" },
        },
        ["JTAC Team 2"] = {
            namePrefix  = "JTAC_TEAM_2",
            displayName = "JTAC Team 2",
            category    = "JTAC",
            units = { "Stinger comm", "Stinger comm" },
        },
        ["JTAC Team 3"] = {
            namePrefix  = "JTAC_TEAM_3",
            displayName = "JTAC Team 3",
            category    = "JTAC",
            units = { "Stinger comm", "Stinger comm" },
        },
        ["JTAC Team 4"] = {
            namePrefix  = "JTAC_TEAM_4",
            displayName = "JTAC Team 4",
            category    = "JTAC",
            units = { "Stinger comm", "Stinger comm" },
        },
        ["JTAC Team 5"] = {
            namePrefix  = "JTAC_TEAM_5",
            displayName = "JTAC Team 5",
            category    = "JTAC",
            units = { "Stinger comm", "Stinger comm" },
        },
}

----------------------------------------------------------------
-- VEHICLE GROUP TEMPLATES (WITH CATEGORY + DISPLAY NAME)
----------------------------------------------------------------
DGSS_CTLD.VEHICLE_TEMPLATES = {

        -- Add 5 static JTAC HMMWV templates
        ["JTAC HMMWV 1"] = {
            namePrefix  = "JTAC_HMMWV_1",
            displayName = "JTAC HMMWV 1",
            category    = "JTAC Vehicles",
            units = { "M1045 HMMWV TOW" }
        },
        ["JTAC HMMWV 2"] = {
            namePrefix  = "JTAC_HMMWV_2",
            displayName = "JTAC HMMWV 2",
            category    = "JTAC Vehicles",
            units = { "M1045 HMMWV TOW" }
        },
        ["JTAC HMMWV 3"] = {
            namePrefix  = "JTAC_HMMWV_3",
            displayName = "JTAC HMMWV 3",
            category    = "JTAC Vehicles",
            units = { "M1045 HMMWV TOW" }
        },
        ["JTAC HMMWV 4"] = {
            namePrefix  = "JTAC_HMMWV_4",
            displayName = "JTAC HMMWV 4",
            category    = "JTAC Vehicles",
            units = { "M1045 HMMWV TOW" }
        },
        ["JTAC HMMWV 5"] = {
            namePrefix  = "JTAC_HMMWV_5",
            displayName = "JTAC HMMWV 5",
            category    = "JTAC Vehicles",
            units = { "M1045 HMMWV TOW" }
        },

    ["CHAP_MATV"] = {
        namePrefix  = "M-ATV",
        displayName = "APC MRAP M-ATV",
        category    = "Armored",
        units = { "CHAP_MATV" }
    },

    ["Stryker MGS"] = {
        namePrefix  = "Stryker MGS",
        displayName = "SPG Stryker MGS",
        category    = "Armored",
        units = { "M1128 Stryker MGS" }
    },

    ["M-1 Abrams SEP-V3"] = {
        namePrefix  = "ABRAMS",
        displayName = "M1 Abrams MBT",
        category    = "Armored",
        units = { "M1A2C_SEP_V3" }
    },

    ["LAV-25"] = {
        namePrefix  = "LAV25",
        displayName = "LAV-25",
        category    = "Armored",
        units = { "LAV-25" }
    },

    ["M113"] = {
        namePrefix  = "M113",
        displayName = "M113 APC",
        category    = "Armored",
        units = { "M113" }
    },

    ["Howitzer"] = {
        namePrefix  = "HOWITZER",
        displayName = "M109 Howitzer",
        category    = "Artillery",
        units = { "M-109" }
    },

    ["CHAP_M142_ATACMS_M39A1"] = {
        namePrefix  = "HIMARS_ATACMS",
        displayName = "M142 HIMARS ATACMS",
        category    = "Artillery",
        units = { "CHAP_M142_ATACMS_M39A1" }
    },

    ["CHAP_M142_GMLRS_M30"] = {
        namePrefix  = "HIMARS_GMLRS",
        displayName = "M142 HIMARS GMLRS",
        category    = "Artillery",
        units = { "CHAP_M142_GMLRS_M30" }
    },

    ["Gepard"] = {
        namePrefix  = "GEPARD",
        displayName = "Gepard SPAAG",
        category    = "Air Defense",
        units = { "Gepard" }
    },

    -- -------------------------------------------------------
    -- NASAMS SITE (full battery: C2 + Sentinel radar + 5x launchers)
    -- Unit types require the DCS NASAMS asset pack
    -- -------------------------------------------------------
    ["NASAMS Site Full"] = {
        namePrefix  = "NASAMS_SITE",
        displayName = "NASAMS SAM Site (5 Launchers)",
        category    = "SAM Systems",
        units = {
            "NASAMS_Command_Post",        -- NASAMS C2 Command Post
            "NASAMS_Radar_MPQ64F1",       -- MPQ-64F1 Sentinel Search Radar
            "NASAMS_LN_C",               -- NASAMS Launcher 1
            "NASAMS_LN_C",               -- NASAMS Launcher 2
            "NASAMS_LN_C",               -- NASAMS Launcher 3
            "NASAMS_LN_C",               -- NASAMS Launcher 4
            "NASAMS_LN_C",               -- NASAMS Launcher 5
            "CHAP_M1083",               -- HEMTT truck for ammo resupply (not part of NASAMS but added for logistics flavor)
            "CHAP_M1083",               -- Additional HEMTT truck for ammo resupply
        },
    },
}

----------------------------------------------------------------
-- INTERNAL STATE
----------------------------------------------------------------

DGSS_CTLD.UNIT_MENUS       = {}  -- per-unit menu handles
DGSS_CTLD.AIRCRAFT_TROOPS  = {}  -- stored troops by aircraft
DGSS_CTLD.AIRCRAFT_VEHICLE = {}  -- stored vehicle by aircraft
DGSS_CTLD.SPAWNED_GROUPS   = {}  -- all CTLD-spawned groups
DGSS_CTLD.SPAWNED_BY_PLAYER = {}  -- track spawned groups by player (playerName -> {groupNames})
DGSS_CTLD.JTAC_REGISTRY    = {}  -- active JTAC teams with full target data (laser, target, availableTargets, etc.)
DGSS_CTLD.JTAC_MENUS       = {}  -- JTAC menus per unit (or group)
DGSS_CTLD.JTAC_MENU_QUEUE  = {}  -- (legacy) not heavily used in static version
DGSS_CTLD.LAST_JTAC_COUNT  = 0   -- track JTAC team count for detecting new teams
DGSS_CTLD.LAST_MENU_JTAC_COUNT = -1 -- track menu rebuild trigger (initialized to -1 so it builds on first run)
DGSS_CTLD.MAX_JTAC_TEAMS   = 10  -- maximum JTAC teams
DGSS_CTLD.MAX_JTAC_VEHICLES = 10  -- maximum JTAC vehicles
DGSS_CTLD.JTAC_ZONES       = {}  -- dynamic trigger zones (groupName -> {radius, lastPos, zoneId})
DGSS_CTLD.JTAC_TEAM_COUNTER = 0  -- persistent counter for JTAC team names
DGSS_CTLD.JTAC_VEHICLE_COUNTER = 0  -- persistent counter for JTAC vehicle names

DGSS_CTLD.GROUP_COUNTER = 0

-- Menu optimization cache
DGSS_CTLD.MENU_CACHE = {
    lastJtacCount = 0,
    lastMenuUpdateTime = 0,
    menuUpdateInterval = 3,  -- seconds between full menu rebuilds
    menuState = {},  -- per-unit menu state cache
}

----------------------------------------------------------------
-- UTILS
----------------------------------------------------------------

function DGSS_CTLD.generateGroupName(prefix)
    DGSS_CTLD.GROUP_COUNTER = DGSS_CTLD.GROUP_COUNTER + 1
    return string.format("%s_%04d", prefix or "DGSS", DGSS_CTLD.GROUP_COUNTER)
end

-- Count entries in a table (generic utility)
local function countTable(t)
    local n = 0
    if type(t) == "table" then
        for _ in pairs(t) do n = n + 1 end
    end
    return n
end

----------------------------------------------------------------
-- HARD LIMIT ENFORCEMENT & MONITORING
-- Tracks and enforces limits for JTAC teams and vehicles
-- Prevents abuse and maintains server performance
----------------------------------------------------------------

-- Get current JTAC team count with proper verification
local function getVerifiedJtacTeamCount()
    local count = 0
    for groupName, _ in pairs(DGSS_CTLD.JTAC_REGISTRY or {}) do
        local grp = Group.getByName(groupName)
        if grp and grp:isExist() then
            count = count + 1
        end
    end
    return count
end

-- Get current JTAC vehicle count with proper verification
local function getVerifiedJtacVehicleCount()
    local count = 0
    for groupName, data in pairs(DGSS_CTLD.SPAWNED_GROUPS) do
        if data.kind == "vehicle" then
            local g = Group.getByName(groupName)
            if g and g:isExist() then
                -- Check if this vehicle is a registered JTAC vehicle
                if DGSS_CTLD.JTAC_REGISTRY[groupName] then
                    count = count + 1
                end
            end
        end
    end
    return count
end

-- Enforce hard limits before spawning
function DGSS_CTLD.checkTeamLimit()
    local current = getVerifiedJtacTeamCount()
    local max = DGSS_CTLD.MAX_JTAC_TEAMS
    return current, max, (current >= max)
end

function DGSS_CTLD.checkVehicleLimit()
    local current = getVerifiedJtacVehicleCount()
    local max = DGSS_CTLD.MAX_JTAC_VEHICLES
    return current, max, (current >= max)
end

-- Get detailed system status
function DGSS_CTLD.getSystemStatus()
    local teamCount, teamMax, teamsFull = DGSS_CTLD.checkTeamLimit()
    local vehicleCount, vehicleMax, vehiclesFull = DGSS_CTLD.checkVehicleLimit()
    
    local groupCount = 0
    for _ in pairs(DGSS_CTLD.SPAWNED_GROUPS) do groupCount = groupCount + 1 end
    
    local playerCount = 0
    for _ in pairs(DGSS_CTLD.SPAWNED_BY_PLAYER) do playerCount = playerCount + 1 end
    
    return {
        jtacTeams = teamCount,
        jtacTeamsMax = teamMax,
        jtacTeamsFull = teamsFull,
        jtacVehicles = vehicleCount,
        jtacVehiclesMax = vehicleMax,
        jtacVehiclesFull = vehiclesFull,
        totalGroups = groupCount,
        activePlayers = playerCount,
    }
end

-- Log JTAC system status to console
function DGSS_CTLD.logSystemStatus()
    local status = DGSS_CTLD.getSystemStatus()
    local msg = string.format(
        "[CTLD] JTAC Teams: %d/%d%s | Vehicles: %d/%d%s | Groups: %d | Players: %d",
        status.jtacTeams, status.jtacTeamsMax, status.jtacTeamsFull and " [FULL]" or "",
        status.jtacVehicles, status.jtacVehiclesMax, status.jtacVehiclesFull and " [FULL]" or "",
        status.totalGroups, status.activePlayers
    )
    env.info(msg)
    return msg
end

-- Get detailed diagnostic info for debugging
function DGSS_CTLD.getDetailedDiagnostics()
    local status = DGSS_CTLD.getSystemStatus()
    local diag = {
        timestamp = timer.getTime(),
        status = status,
        jtacTeams = {},
        jtacVehicles = {},
    }
    
    -- List all active JTAC teams
    for groupName, data in pairs(DGSS_CTLD.JTAC_REGISTRY or {}) do
        local grp = Group.getByName(groupName)
        if grp and grp:isExist() then
            local u = grp:getUnit(1)
            if u and u:isExist() then
                table.insert(diag.jtacTeams, {
                    name = groupName,
                    laserCode = data.laser,
                    targetStatus = data.target and data.target:isExist() and "LOCKED" or "IDLE",
                    availableTargets = #(data.availableTargets or {}),
                })
            end
        end
    end
    
    -- List all JTAC vehicles
    for groupName, spawnData in pairs(DGSS_CTLD.SPAWNED_GROUPS) do
        if spawnData.kind == "vehicle" and DGSS_CTLD.JTAC_REGISTRY[groupName] then
            local grp = Group.getByName(groupName)
            if grp and grp:isExist() then
                local data = DGSS_CTLD.JTAC_REGISTRY[groupName]
                table.insert(diag.jtacVehicles, {
                    name = groupName,
                    laserCode = data.laser,
                    targetStatus = data.target and data.target:isExist() and "LOCKED" or "IDLE",
                })
            end
        end
    end
    
    return diag
end

-- Count active JTAC teams
function DGSS_CTLD.countActiveJtacTeams()
    local count = 0
    for groupName, data in pairs(DGSS_CTLD.SPAWNED_GROUPS) do
        if data.kind == "troops" and data.templateName == "JTAC Team" then
            local g = Group.getByName(groupName)
            if g and g:isExist() then
                count = count + 1
            end
        end
    end
    return count
end

-- Count active JTAC vehicles
function DGSS_CTLD.countActiveJtacVehicles()
    local count = 0
    for groupName, data in pairs(DGSS_CTLD.SPAWNED_GROUPS) do
        if data.kind == "vehicle" then
            local g = Group.getByName(groupName)
            if g and g:isExist() then
                -- Check if this vehicle was registered as a JTAC vehicle
                if DGSS_CTLD.JTAC_REGISTRY[groupName] then
                    count = count + 1
                end
            end
        end
    end
    return count
end

-- Convert DCS position to MGRS coordinate string
function DGSS_CTLD.coordinatesToMGRS(point)
    if not point then return "UNKNOWN" end
    
    local lat, lon = 0, 0
    local ok = pcall(function()
        lat, lon = coord.LOtoLL(point)
    end)
    if not ok or (lat == 0 and lon == 0) then return "UNKNOWN" end
    
    local mgrs = coord.LLtoMGRS(lat, lon)
    return string.format("%s %s %05d %05d",
        mgrs.UTMZone,
        mgrs.MGRSDigraph,
        mgrs.Easting,
        mgrs.Northing
    )
end

-- Convert DCS position to DD MM.MMM format (Degrees Decimal Minutes)
function DGSS_CTLD.coordinatesToDecimalMinutes(point)
    if not point then return "UNKNOWN" end
    
    local lat, lon = 0, 0
    local ok = pcall(function()
        lat, lon = coord.LOtoLL(point)
    end)
    if not ok or (lat == 0 and lon == 0) then return "UNKNOWN" end
    
    -- Convert latitude to DD MM.MMM
    local latDeg = math.floor(math.abs(lat))
    local latMin = (math.abs(lat) - latDeg) * 60
    local latDir = lat >= 0 and "N" or "S"
    
    -- Convert longitude to DD MM.MMM
    local lonDeg = math.floor(math.abs(lon))
    local lonMin = (math.abs(lon) - lonDeg) * 60
    local lonDir = lon >= 0 and "E" or "W"
    
    return string.format("%s %02d %06.3f  %s %03d %06.3f", latDir, latDeg, latMin, lonDir, lonDeg, lonMin)
end

-- Generate 9-line CAS briefing with robust error handling
function DGSS_CTLD.generate9LineCallout(jtacName, targetUnit, jtacUnit)
    if not targetUnit or not jtacUnit then return nil end
    
    -- Safely get positions
    local jtacPos = pcall(function() return jtacUnit:getPoint() end) and jtacUnit:getPoint() or nil
    local targetPos = pcall(function() return targetUnit:getPoint() end) and targetUnit:getPoint() or nil
    
    if not jtacPos or not targetPos then return nil end
    
    -- Calculate bearing from JTAC to target (DCS: x=North, z=East)
    local dx = (targetPos.x or 0) - (jtacPos.x or 0)
    local dz = (targetPos.z or 0) - (jtacPos.z or 0)
    local distMeters = math.sqrt(dx*dx + dz*dz)
    local distNM = distMeters / 1852
    -- Compass bearing: atan2(east, north) for CW-from-north
    local bearing = math.deg(math.atan2(dz, dx))
    if bearing < 0 then bearing = bearing + 360 end
    
    -- Target info with null safety
    local targetType = "Vehicle"
    pcall(function() targetType = targetUnit:getTypeName() or "Vehicle" end)
    
    local targetGroupName = "Unknown"
    pcall(function()
        local targetGroup = targetUnit:getGroup()
        if targetGroup and targetGroup:isExist() then
            targetGroupName = targetGroup:getName() or "Unknown"
        end
    end)
    
    -- Elevation in feet MSL
    local elevMeters = math.floor((targetPos.y or 0))
    local elevFeet = math.floor(elevMeters * 3.281)
    
    -- Get laser code safely
    local laserCode = 1688
    if DGSS_CTLD.JTAC_REGISTRY and DGSS_CTLD.JTAC_REGISTRY[jtacName] then
        laserCode = DGSS_CTLD.JTAC_REGISTRY[jtacName].laser or 1688
    end
    
    -- Get formatted coordinates
    local mgrsStr = DGSS_CTLD.coordinatesToMGRS(targetPos)
    local dmStr = DGSS_CTLD.coordinatesToDecimalMinutes(targetPos)
    
    -- Build standard 9-line CAS briefing
    local callout = string.format(
        "========= 9-LINE CAS =========\n" ..
        "JTAC: %s  |  Laser: %d\n" ..
        "---------------------------------\n" ..
        "1. IP/BP:        CURRENT POS\n" ..
        "2. HDG:          %03d\n" ..
        "3. DISTANCE:     %.1f NM\n" ..
        "4. ELEVATION:    %d ft MSL\n" ..
        "5. TGT DESC:     %s\n" ..
        "6. TGT LOC:      %s\n" ..
        "                 %s\n" ..
        "7. MARK:         LASER %d\n" ..
        "8. FRIENDLIES:   JTAC POS\n" ..
        "9. EGRESS:       PILOT DISCRETION\n" ..
        "=================================",
        jtacName, laserCode,
        bearing,
        distNM,
        elevFeet,
        targetType,
        mgrsStr,
        dmStr,
        laserCode
    )
    
    return callout
end

-- Create dynamic trigger zone for JTAC unit
function DGSS_CTLD.createJtacZone(groupName, position, radius)
    if not groupName or not position then return end
    
    DGSS_CTLD.JTAC_ZONES[groupName] = {
        radius = radius or SCAN_RADIUS,
        lastPos = {x = position.x, y = position.y, z = position.z},
        active = true,
    }
    
    env.info(string.format("[JTAC ZONE] Created zone for %s at radius %.1f m", groupName, radius or SCAN_RADIUS))
end

-- Update dynamic trigger zone position (follows JTAC)
function DGSS_CTLD.updateJtacZone(groupName, newPosition)
    local zone = DGSS_CTLD.JTAC_ZONES[groupName]
    if not zone or not newPosition then return end
    
    zone.lastPos = {x = newPosition.x, y = newPosition.y, z = newPosition.z}
end

-- Destroy dynamic trigger zone
function DGSS_CTLD.destroyJtacZone(groupName)
    if DGSS_CTLD.JTAC_ZONES[groupName] then
        DGSS_CTLD.JTAC_ZONES[groupName] = nil
        env.info(string.format("[JTAC ZONE] Destroyed zone for %s", groupName))
    end
end

-- Check if position is in JTAC zone
function DGSS_CTLD.isPositionInJtacZone(groupName, position)
    local zone = DGSS_CTLD.JTAC_ZONES[groupName]
    if not zone or not position then return false end
    
    local dx = position.x - zone.lastPos.x
    local dz = position.z - zone.lastPos.z
    local distSq = dx*dx + dz*dz
    
    return distSq <= (zone.radius * zone.radius)
end

-- Find enemies in JTAC zone
function DGSS_CTLD.findEnemiesInJtacZone(groupName)
    if not DGSS_CTLD.JTAC_ZONES[groupName] then return {} end
    
    local results = {}
    local redGroups = coalition.getGroups(coalition.side.RED, Group.Category.GROUND) or {}
    
    for _, g in ipairs(redGroups) do
        if g and g:isExist() then
            for _, u in ipairs(g:getUnits()) do
                if u and u:isExist() then
                    local pos = u:getPoint()
                    if DGSS_CTLD.isPositionInJtacZone(groupName, pos) then
                        table.insert(results, u)
                    end
                end
            end
        end
    end
    
    return results
end

local function sqrDist(p1, p2)
    local dx = p1.x - p2.x
    local dz = p1.z - p2.z
    return dx*dx + dz*dz
end
DGSS_CTLD.sqrDist = sqrDist

----------------------------------------------------------------
-- ZONE HELPERS (Circular zones only)
----------------------------------------------------------------

-- Check if a point is inside a circular trigger zone
local function isPointInZone(point, zone)
    if not zone or not point then return false end
    
    -- Circular zone detection (DCS native - no polygon complexity)
    if zone.point and zone.radius then
        local dx = point.x - zone.point.x
        local dz = point.z - zone.point.z
        return dx*dx + dz*dz <= zone.radius * zone.radius
    end
    
    return false
end

function DGSS_CTLD.isInsideZone(point, zoneName)
    local z
    pcall(function()
        z = trigger.misc.getZone(zoneName)
    end)
    if not z then return false end
    return isPointInZone(point, z)
end

function DGSS_CTLD.isInsideAnyCTLDZone(point)
    for _, z in ipairs(DGSS_CTLD.ZONES) do
        if DGSS_CTLD.isInsideZone(point, z.name) then
            return true
        end
    end
    return false
end

----------------------------------------------------------------
-- TRANSPORT VALIDATION
----------------------------------------------------------------

function DGSS_CTLD.isValidTransport(unit)
    if not unit or not unit:isExist() then return false end
    return DGSS_CTLD.VALID_TROOP_TRANSPORT[unit:getTypeName()] == true
end

function DGSS_CTLD.isValidVehicleTransport(unit)
    if not unit or not unit:isExist() then return false end
    -- Vehicle spawn is available to everyone in a CTLD zone regardless of vehicle type
    local pos = unit:getPoint()
    return DGSS_CTLD.isInsideAnyCTLDZone(pos)
end

-- Check if unit is in ANY valid transport (troop or vehicle)
function DGSS_CTLD.isValidCTLDTransport(unit)
    return DGSS_CTLD.isValidTransport(unit) or DGSS_CTLD.isValidVehicleTransport(unit)
end

-- Check if unit is a Combined Arms (CA) player-controlled ground unit
function DGSS_CTLD.isCombinedArmsUnit(unit)
    if not unit or not unit:isExist() then return false end
    if not unit:getPlayerName() then return false end
    local group = unit:getGroup()
    if not group or not group:isExist() then return false end
    -- Ground units with a player name are CA-controlled
    local cat = group:getCategory()
    return cat == Group.Category.GROUND
end

-- Get current zone name for a position
function DGSS_CTLD.getCurrentZoneName(pos)
    for _, z in ipairs(DGSS_CTLD.ZONES) do
        if DGSS_CTLD.isInsideZone(pos, z.name) then
            return z.name
        end
    end
    return nil
end

----------------------------------------------------------------
-- TROOPS: STORAGE HELPERS
----------------------------------------------------------------

local function ensureAircraftTroopTable(unitName)
    if not DGSS_CTLD.AIRCRAFT_TROOPS[unitName] then
        DGSS_CTLD.AIRCRAFT_TROOPS[unitName] = {}
    end
end
DGSS_CTLD.ensureAircraftTroopTable = ensureAircraftTroopTable

function DGSS_CTLD.getTroopGroupsInAircraft(unit)
    if not unit or not unit:isExist() then return {} end
    return DGSS_CTLD.AIRCRAFT_TROOPS[unit:getName()] or {}
end

local function addTroopGroupToAircraft(unit, groupMeta, unitTypes)
    if not unit or not unit:isExist() then return end

    local unitName = unit:getName()
    ensureAircraftTroopTable(unitName)

    -- Preserve JTAC metadata while onboard aircraft
    table.insert(DGSS_CTLD.AIRCRAFT_TROOPS[unitName], {
        id               = groupMeta.id,
        templateName     = groupMeta.templateName,
        count            = groupMeta.count or (unitTypes and #unitTypes) or 0,
        units            = unitTypes or {},
        laserCode        = groupMeta.laserCode,      -- JTAC laser code
        originalGroupName = groupMeta.originalGroupName,  -- JTAC original name (for restoration on unload)
    })
end
DGSS_CTLD.addTroopGroupToAircraft = addTroopGroupToAircraft

local function removeTroopGroupFromAircraft(unit, groupID)
    if not unit or not unit:isExist() then return end

    local list = DGSS_CTLD.AIRCRAFT_TROOPS[unit:getName()]
    if not list then return end

    for i, g in ipairs(list) do
        if g.id == groupID then
            table.remove(list, i)
            return
        end
    end
end
DGSS_CTLD.removeTroopGroupFromAircraft = removeTroopGroupFromAircraft

----------------------------------------------------------------
-- TROOPS: SPAWN / LOAD / UNLOAD
----------------------------------------------------------------

function DGSS_CTLD.spawnTroopsAtUnit(unit, templateName)
    if not unit or not unit:isExist() then return end
    local pos = unit:getPoint()

    if not DGSS_CTLD.isInsideAnyCTLDZone(pos) then
        trigger.action.outTextForUnit(unit:getID(),
            "You must be inside a CTLD zone to spawn troops!", 5)
        return
    end

    local template = DGSS_CTLD.TROOP_TEMPLATES[templateName]
    if not template then
        trigger.action.outTextForUnit(unit:getID(),
            "Invalid troop template!", 5)
        return
    end

    -- Check JTAC Team spawn limit with verification
    if templateName:find("JTAC Team") then
        local current, max, isFull = DGSS_CTLD.checkTeamLimit()
        if isFull then
            trigger.action.outTextForUnit(unit:getID(),
                string.format("Max JTAC teams reached! (%d/%d)", current, max), 5)
            return
        end
    end

    local units = {}
    for _, unitType in ipairs(template.units) do
        table.insert(units, {
            type    = unitType,
            x       = pos.x + math.random(15,20),
            y       = pos.z + math.random(15,20),
            heading = math.random() * 6.28,
        })
    end

    -- Generate unique group name using prefix from template
    local groupName = DGSS_CTLD.generateGroupName(template.namePrefix or templateName)
    env.info(string.format("[CTLD] Spawning troop group: %s (template: %s)", groupName, templateName))
    
    local group = coalition.addGroup(
        DGSS_CTLD.COUNTRY,
        Group.Category.GROUND,
        { name = groupName, units = units }
    )

    if group then
        DGSS_CTLD.SPAWNED_GROUPS[groupName] = {
            lastActive   = timer.getTime(),
            kind         = "troops",
            templateName = templateName,
            id           = groupName,
            count        = #units,
            spawnedBy    = unit:getPlayerName(),
            zone         = DGSS_CTLD.getCurrentZoneName(pos),
        }

        -- Track group by player
        local playerName = unit:getPlayerName()
        if playerName then
            if not DGSS_CTLD.SPAWNED_BY_PLAYER[playerName] then
                DGSS_CTLD.SPAWNED_BY_PLAYER[playerName] = {}
            end
            table.insert(DGSS_CTLD.SPAWNED_BY_PLAYER[playerName], groupName)
        end

        if templateName:find("JTAC Team") then
            -- JTAC spawned in CTLD zone - DO NOT register yet
            -- Will only be registered when unloaded outside a CTLD zone
            trigger.action.outTextForUnit(unit:getID(),
                string.format("JTAC Team '%s' spawned in CTLD zone (10nm scan zone). Load and unload outside zone to activate.", groupName), 6)
        else
            trigger.action.outTextForUnit(unit:getID(),
                string.format("Troops spawned: %s (%d)", template.displayName, #units), 5)
        end
    else
        trigger.action.outTextForUnit(unit:getID(), "Failed to spawn troops!", 5)
    end
end

function DGSS_CTLD.getNearbySpawnedTroopGroups(pos, maxDist)
    local results = {}
    local maxSq = maxDist * maxDist

    -- Debug: count total groups in registry
    local totalGroups = 0
    local troopGroups = 0
    for groupName, data in pairs(DGSS_CTLD.SPAWNED_GROUPS) do
        totalGroups = totalGroups + 1
        if data.kind == "troops" then
            troopGroups = troopGroups + 1
        end
    end
    env.info(string.format("[CTLD] getNearbySpawnedTroopGroups: SPAWNED_GROUPS has %d total entries, %d are troops", totalGroups, troopGroups))

    for groupName, data in pairs(DGSS_CTLD.SPAWNED_GROUPS) do
        if data.kind == "troops" then
            local g = Group.getByName(groupName)
            if g and g:isExist() then
                local u = g:getUnit(1)
                if u and u:isExist() then
                    local d = DGSS_CTLD.sqrDist(pos, u:getPoint())
                    env.info(string.format("[CTLD] Checking group '%s': distance=%.1fm (max=%dm)", groupName, math.sqrt(d), maxDist))
                    if d <= maxSq then
                        data.lastActive = timer.getTime()
                        table.insert(results, { name = groupName, meta = data, distSq = d })
                    end
                else
                    env.info(string.format("[CTLD] Group '%s' unit doesn't exist", groupName))
                end
            else
                env.info(string.format("[CTLD] Group '%s' doesn't exist in DCS", groupName))
            end
        end
    end

    table.sort(results, function(a,b) return a.distSq < b.distSq end)
    return results
end

function DGSS_CTLD.loadSpecificTroopGroupFromGround(unit, spawnedGroupName)
    if not unit then return end
    if not DGSS_CTLD.isValidTransport(unit) then return end

    -- Check speed and altitude limits
    local condOk, condMsg = DGSS_CTLD.checkLoadUnloadConditions(unit, true)
    if not condOk then
        trigger.action.outTextForUnit(unit:getID(), condMsg, 6)
        return
    end

    local g = Group.getByName(spawnedGroupName)
    if not g or not g:isExist() then
        DGSS_CTLD.SPAWNED_GROUPS[spawnedGroupName] = nil
        trigger.action.outTextForUnit(unit:getID(),
            "Troop group no longer exists!", 5)
        return
    end

    local meta = DGSS_CTLD.SPAWNED_GROUPS[spawnedGroupName]
    if not meta then return end

    local units = g:getUnits()
    local count = #units

    local unitName = unit:getName()
    local capacity = DGSS_CTLD.CAPACITY[unit:getTypeName()] or 0
    ensureAircraftTroopTable(unitName)

    local onboard = DGSS_CTLD.AIRCRAFT_TROOPS[unitName]
    local currentCount = 0
    for _, grp in ipairs(onboard) do
        currentCount = currentCount + (grp.count or 0)
    end

    if currentCount + count > capacity then
        trigger.action.outTextForUnit(unit:getID(),
            string.format("Not enough capacity! Onboard: %d / %d, group size: %d",
                currentCount, capacity, count),
            6
        )
        return
    end

    local unitTypes = {}
    for _, u in ipairs(units) do
        table.insert(unitTypes, u:getTypeName())
    end

    ----------------------------------------------------------------
    -- JTAC: Store original group name and default laser code when loading
    ----------------------------------------------------------------
    if meta.templateName == "JTAC Team" then
        -- Store original group name for later restoration
        meta.originalGroupName = spawnedGroupName
        -- Store default laser code for deployment
        meta.laserCode = 1688
        -- UNREGISTER JTAC when loading (so it stops scanning/lasing while onboard)
        JTAC_Manager.unregisterJTAC(spawnedGroupName)
        env.info("[JTAC] JTAC Team " .. spawnedGroupName .. " unregistered (loaded into transport)")
    end

    addTroopGroupToAircraft(unit, meta, unitTypes)

    g:destroy()
    DGSS_CTLD.SPAWNED_GROUPS[spawnedGroupName] = nil

    trigger.action.outTextForUnit(
        unit:getID(),
        string.format("Loaded %s (%d)", meta.templateName, count),
        6
    )
end

function DGSS_CTLD.unloadSpecificTroopGroup(unit, groupID)
    if not unit or not unit:isExist() then return end

    -- Check speed and altitude limits
    local condOk, condMsg = DGSS_CTLD.checkLoadUnloadConditions(unit, false)
    if not condOk then
        trigger.action.outTextForUnit(unit:getID(), condMsg, 6)
        return
    end

    local groups = DGSS_CTLD.getTroopGroupsInAircraft(unit)
    if #groups == 0 then
        trigger.action.outTextForUnit(unit:getID(),
            "No troops onboard to unload!", 5)
        return
    end

    local selected
    for _, g in ipairs(groups) do
        if g.id == groupID then
            selected = g
            break
        end
    end

    if not selected then
        trigger.action.outTextForUnit(unit:getID(),
            "Troop group not found onboard!", 5)
        return
    end

    local pos = unit:getPoint()

    local units = {}
    for _, unitType in ipairs(selected.units or {}) do
        table.insert(units, {
            type    = unitType,
            x       = pos.x + math.random(15,20),
            y       = pos.z + math.random(15,20),
            heading = math.random() * 6.28,
        })
    end

    -- Always use the original group name for unload, if available
    local groupName = selected.originalGroupName or selected.id or DGSS_CTLD.generateGroupName("TROOPS_UNLOAD")

    local group = coalition.addGroup(
        DGSS_CTLD.COUNTRY,
        Group.Category.GROUND,
        { name = groupName, units = units }
    )

    if group then
        DGSS_CTLD.SPAWNED_GROUPS[groupName] = {
            lastActive   = timer.getTime(),
            kind         = "troops",
            templateName = selected.templateName,
            id           = selected.id,
            count        = #units,
        }

        removeTroopGroupFromAircraft(unit, groupID)

        trigger.action.outTextForUnit(unit:getID(),
            string.format("Unloaded %s (%d)", selected.templateName, selected.count),
            6
        )

        -- [DEBUG] JTAC: Register unloaded JTAC Team ONLY if outside CTLD zones
        if selected.templateName and selected.templateName:find("JTAC Team") then
            -- [DEBUG] Check if unload position is outside all CTLD zones
            -- This verification ensures dormant JTACs in CTLD zones don't get registered
            local inCTLDZone = false
            env.info("[JTAC UNLOAD] Starting zone check for " .. groupName .. " at position (" .. math.floor(pos.x) .. ", " .. math.floor(pos.z) .. ")")
            
            for _, z in ipairs(DGSS_CTLD.ZONES or {}) do
                if z and z.name then
                    if DGSS_CTLD.isInsideZone(pos, z.name) then
                        inCTLDZone = true
                        env.info("[JTAC UNLOAD] *** IN ZONE: " .. z.name)
                        break
                    else
                        env.info("[JTAC UNLOAD] NOT in zone: " .. z.name)
                    end
                end
            end
            
            env.info("[JTAC UNLOAD] Zone check complete. inCTLDZone = " .. tostring(inCTLDZone))
            
            if not inCTLDZone then
                -- [DEBUG] Only register if OUTSIDE CTLD zones
                -- Verify group exists with units before registration
                env.info("[JTAC UNLOAD] Outside zones, verifying group...")
                local verifyGrp = Group.getByName(groupName)
                if not verifyGrp or not verifyGrp:isExist() then
                    env.warning("[JTAC UNLOAD] *** VERIFICATION FAILED: group does not exist")
                    return
                end
                
                local units = verifyGrp:getUnits()
                if not units or #units == 0 then
                    env.warning("[JTAC UNLOAD] *** VERIFICATION FAILED: group has no units")
                    return
                end
                
                env.info("[JTAC UNLOAD] *** VERIFICATION PASSED - Registering JTAC (" .. #units .. " units)")
                local laser = selected.laserCode or 1688
                
                -- Register using DGSS_CTLD.registerJTAC() which internally calls JTAC_Manager
                -- (DO NOT call both - would register twice)
                local regResult = DGSS_CTLD.registerJTAC(groupName, laser)
                
                if regResult == false then
                    env.warning("[JTAC UNLOAD] *** REGISTRATION FAILED: Team limit reached or registration returned false")
                    trigger.action.outTextForUnit(
                        unit:getID(),
                        "JTAC Team '" .. groupName .. "' unload failed - max teams reached!",
                        6
                    )
                    return
                end
                
                local scanRadiusFt = SCAN_RADIUS * 3.28084
                local scanRadiusNm = SCAN_RADIUS / 1852
                trigger.action.outTextForUnit(
                    unit:getID(),
                    string.format("JTAC Team '%s' deployed and activated (Code %d, %.0f ft / %.1f NM scan zone)!", groupName, laser, scanRadiusFt, scanRadiusNm),
                    6
                )
                env.info("[JTAC UNLOAD] *** SUCCESS: JTAC Team " .. groupName .. " registered as ACTIVE")
                
                -- DEBUG: Verify it's actually in JTAC_REGISTRY
                if DGSS_CTLD and DGSS_CTLD.JTAC_REGISTRY and DGSS_CTLD.JTAC_REGISTRY[groupName] then
                    env.info("[JTAC UNLOAD] âœ“ VERIFIED: " .. groupName .. " is in JTAC_REGISTRY")
                else
                    env.warning("[JTAC UNLOAD] âœ— ERROR: " .. groupName .. " NOT found in JTAC_REGISTRY after registration!")
                end
            else
                env.info("[JTAC UNLOAD] *** STILL IN ZONE - NOT registering")
                trigger.action.outTextForUnit(
                    unit:getID(),
                    string.format("JTAC Team '%s' unloaded in CTLD zone - not activated (move outside zone to activate)", groupName),
                    6
                )
                env.info("[JTAC UNLOAD] JTAC Team " .. groupName .. " NOT registered (still in CTLD zone)")
            end
        end
    else
        trigger.action.outTextForUnit(unit:getID(),
            "Failed to unload troops!", 5)
    end
end

-- STATIC BEHAVIOR: Load nearest troops
function DGSS_CTLD.loadNearestTroops(unit)
    -- Wrap in pcall to catch the actual error
    local ok, err = pcall(function()
        if not unit then 
            env.info("[CTLD] loadNearestTroops: unit is nil")
            return 
        end
        
        local unitExists = false
        local existOk, existErr = pcall(function() unitExists = unit:isExist() end)
        if not existOk then
            env.info("[CTLD] loadNearestTroops: isExist() crashed: " .. tostring(existErr))
            return
        end
        if not unitExists then
            env.info("[CTLD] loadNearestTroops: unit doesn't exist")
            return
        end
        
        env.info("[CTLD] loadNearestTroops: checking isValidTransport...")
        if not DGSS_CTLD.isValidTransport(unit) then
            trigger.action.outTextForUnit(unit:getID(),
                "This aircraft cannot load troops.", 5)
            return
        end

        env.info("[CTLD] loadNearestTroops: checking load conditions...")
        -- Check speed and altitude limits
        local condOk, condMsg = DGSS_CTLD.checkLoadUnloadConditions(unit, true)
        if not condOk then
            trigger.action.outTextForUnit(unit:getID(), condMsg, 6)
            return
        end

        env.info("[CTLD] loadNearestTroops: getting unit position...")
        local pos = unit:getPoint()
        if not pos then
            env.info("[CTLD] loadNearestTroops: getPoint() returned nil")
            trigger.action.outTextForUnit(unit:getID(), "Cannot determine position!", 5)
            return
        end
        env.info(string.format("[CTLD] loadNearestTroops: searching for troops near (%.1f, %.1f)", pos.x, pos.z))
        
        env.info("[CTLD] loadNearestTroops: calling getNearbySpawnedTroopGroups...")
        local nearby = DGSS_CTLD.getNearbySpawnedTroopGroups(pos, 75)
        env.info(string.format("[CTLD] loadNearestTroops: found %d nearby troop groups", #nearby))

        if #nearby == 0 then
            trigger.action.outTextForUnit(unit:getID(),
                "No nearby troops to load! (Must be within 75m)", 5)
            return
        end

        local nearest = nearby[1]
        env.info(string.format("[CTLD] loadNearestTroops: loading group '%s'", nearest.name))
        DGSS_CTLD.loadSpecificTroopGroupFromGround(unit, nearest.name)
    end)
    
    if not ok then
        env.error("[CTLD] loadNearestTroops CRASHED: " .. tostring(err))
    end
end

-- STATIC BEHAVIOR: Unload all troops
function DGSS_CTLD.unloadAllTroops(unit)
    if not unit or not unit:isExist() then return end

    -- Check speed and altitude limits
    local condOk, condMsg = DGSS_CTLD.checkLoadUnloadConditions(unit, false)
    if not condOk then
        trigger.action.outTextForUnit(unit:getID(), condMsg, 6)
        return
    end

    local onboard = DGSS_CTLD.getTroopGroupsInAircraft(unit)
    if #onboard == 0 then
        trigger.action.outTextForUnit(unit:getID(),
            "No troops onboard to unload!", 5)
        return
    end

    -- Copy IDs to avoid mutating while iterating
    local ids = {}
    for _, grp in ipairs(onboard) do
        table.insert(ids, grp.id)
    end

    for _, id in ipairs(ids) do
        DGSS_CTLD.unloadSpecificTroopGroup(unit, id)
    end
end

----------------------------------------------------------------
-- VEHICLES: SPAWN / LOAD / UNLOAD
----------------------------------------------------------------

function DGSS_CTLD.spawnVehicleNearUnit(unit, vehicleType)
    if not unit or not unit:isExist() then return end
    local pos = unit:getPoint()

    if not DGSS_CTLD.isInsideAnyCTLDZone(pos) then
        trigger.action.outTextForUnit(unit:getID(),
            "You must be inside a CTLD zone to spawn vehicles!", 5)
        return
    end

    local template = DGSS_CTLD.VEHICLE_TEMPLATES[vehicleType]
    if not template then
        trigger.action.outTextForUnit(unit:getID(),
            "Invalid vehicle template: " .. tostring(vehicleType), 5)
        return
    end

    -- Check JTAC Vehicle spawn limit with verification
    if vehicleType:find("JTAC HMMWV") then
        local current, max, isFull = DGSS_CTLD.checkVehicleLimit()
        if isFull then
            trigger.action.outTextForUnit(unit:getID(),
                string.format("Max JTAC vehicles reached! (%d/%d)", current, max), 5)
            return
        end
    end

    local dcsUnitType = template.units[1]
    local spawnPos = {
        x = pos.x + math.random(25,35),
        y = pos.z + math.random(25,35),
    }

    local groupName = vehicleType
    local group = coalition.addGroup(
        DGSS_CTLD.COUNTRY,
        Group.Category.GROUND,
        {
            name = groupName,
            units = {
                {
                    type    = dcsUnitType,
                    x       = spawnPos.x,
                    y       = spawnPos.y,
                    heading = math.random() * 6.28,
                }
            }
        }
    )

    if group then
        DGSS_CTLD.SPAWNED_GROUPS[groupName] = {
            lastActive = timer.getTime(),
            kind       = "vehicle",
            spawnedBy  = unit:getPlayerName(),
            zone       = DGSS_CTLD.getCurrentZoneName(pos),
        }

        local playerName = unit:getPlayerName()
        if playerName then
            if not DGSS_CTLD.SPAWNED_BY_PLAYER[playerName] then
                DGSS_CTLD.SPAWNED_BY_PLAYER[playerName] = {}
            end
            table.insert(DGSS_CTLD.SPAWNED_BY_PLAYER[playerName], groupName)
        end

        -- Register JTAC vehicle if applicable
        if vehicleType:find("JTAC HMMWV") then
            DGSS_CTLD.registerJTAC(groupName, 1688)
            DGSS_CTLD.createJtacZone(groupName, pos)
            trigger.action.outTextForUnit(unit:getID(),
                template.displayName .. " spawned and registered! (30,030 ft scan zone active)", 5)
        else
            trigger.action.outTextForUnit(unit:getID(),
                template.displayName .. " spawned!", 5)
        end
    else
        trigger.action.outTextForUnit(unit:getID(),
            "Failed to spawn " .. template.displayName, 5)
    end
end

local function findNearestSpawnedGroup(pos, kind, maxDist)
    local nearest, nearestDist = nil, maxDist * maxDist

    for groupName, data in pairs(DGSS_CTLD.SPAWNED_GROUPS) do
        if data.kind == kind then
            local g = Group.getByName(groupName)
            if g and g:isExist() then
                local u = g:getUnit(1)
                if u and u:isExist() then
                    local d = DGSS_CTLD.sqrDist(pos, u:getPoint())
                    if d < nearestDist then
                        nearestDist = d
                        nearest = groupName
                    end
                end
            end
        end
    end
    return nearest
end
DGSS_CTLD.findNearestSpawnedGroup = findNearestSpawnedGroup

function DGSS_CTLD.loadVehicleFromGround(unit)
    if not unit or not unit:isExist() then return end
    
    if not DGSS_CTLD.isValidVehicleTransport(unit) then
        trigger.action.outTextForUnit(unit:getID(),
            "This aircraft cannot transport vehicles.", 5)
        return
    end

    -- Check speed and altitude limits
    local condOk, condMsg = DGSS_CTLD.checkLoadUnloadConditions(unit, true)
    if not condOk then
        trigger.action.outTextForUnit(unit:getID(), condMsg, 6)
        return
    end

    local pos = unit:getPoint()
    local nearestGroupName = findNearestSpawnedGroup(pos, "vehicle", 50)

    if not nearestGroupName then
        trigger.action.outTextForUnit(unit:getID(),
            "No vehicle nearby to load!", 5)
        return
    end

    if DGSS_CTLD.AIRCRAFT_VEHICLE[unit:getName()] then
        trigger.action.outTextForUnit(unit:getID(),
            "You already have a vehicle onboard!", 5)
        return
    end

    local group = Group.getByName(nearestGroupName)
    if not group or not group:isExist() then
        DGSS_CTLD.SPAWNED_GROUPS[nearestGroupName] = nil
        trigger.action.outTextForUnit(unit:getID(),
            "Vehicle no longer exists!", 5)
        return
    end

    local u = group:getUnit(1)
    if not u or not u:isExist() then
        DGSS_CTLD.SPAWNED_GROUPS[nearestGroupName] = nil
        trigger.action.outTextForUnit(unit:getID(),
            "Vehicle no longer exists!", 5)
        return
    end

    local vType = u:getTypeName()
    DGSS_CTLD.AIRCRAFT_VEHICLE[unit:getName()] = { vehicleType = vType, groupName = nearestGroupName }

    -- Unregister JTAC vehicle from scanning
    local jtacData = DGSS_CTLD.JTAC_REGISTRY[nearestGroupName]
    if jtacData then
        if JTAC_Manager and JTAC_Manager.unregisterJTAC then
            JTAC_Manager.unregisterJTAC(nearestGroupName)
        end
        DGSS_CTLD.JTAC_REGISTRY[nearestGroupName] = nil
        -- Destroy dynamic zone when vehicle loaded
        DGSS_CTLD.destroyJtacZone(nearestGroupName)
    end

    group:destroy()
    DGSS_CTLD.SPAWNED_GROUPS[nearestGroupName] = nil

    trigger.action.outTextForUnit(unit:getID(),
        "Loaded vehicle: " .. vType, 5)
end

function DGSS_CTLD.unloadVehicle(unit)
    if not unit or not unit:isExist() then return end

    -- Check speed and altitude limits
    local condOk, condMsg = DGSS_CTLD.checkLoadUnloadConditions(unit, false)
    if not condOk then
        trigger.action.outTextForUnit(unit:getID(), condMsg, 6)
        return
    end

    local vData = DGSS_CTLD.AIRCRAFT_VEHICLE[unit:getName()]
    if not vData then
        trigger.action.outTextForUnit(unit:getID(),
            "No vehicle onboard to unload!", 5)
        return
    end

    local pos = unit:getPoint()
    local spawnPos = {
        x = pos.x + math.random(25,35),
        y = pos.z + math.random(25,35),
    }

    local groupName = DGSS_CTLD.generateGroupName("VEH_UNLOAD")
    local group = coalition.addGroup(
        DGSS_CTLD.COUNTRY,
        Group.Category.GROUND,
        {
            name = groupName,
            units = {
                {
                    type    = vData.vehicleType,
                    x       = spawnPos.x,
                    y       = spawnPos.y,
                    heading = math.random() * 6.28,
                }
            }
        }
    )

    if group then
        DGSS_CTLD.SPAWNED_GROUPS[groupName] = {
            lastActive = timer.getTime(),
            kind       = "vehicle",
        }

        DGSS_CTLD.AIRCRAFT_VEHICLE[unit:getName()] = nil
        trigger.action.outTextForUnit(unit:getID(), "Vehicle unloaded!", 5)
    else
        trigger.action.outTextForUnit(unit:getID(),
            "Failed to unload vehicle!", 5)
    end
end

----------------------------------------------------------------
-- JTAC CORE (REGISTRY ONLY â€“ TARGETING BY JTAC_Manager)
----------------------------------------------------------------

DGSS_CTLD.JTAC_LASER_CODES = { 1688, 1687, 1686, 1685, 1113, 1114, 1115, 1116 }

-- Cleanup dead JTAC entries to prevent registry bloat and menu duplication
function DGSS_CTLD.cleanupDeadJTACs()
    if not DGSS_CTLD.JTAC_REGISTRY then return end
    
    local beforeCount = 0
    for _ in pairs(DGSS_CTLD.JTAC_REGISTRY) do beforeCount = beforeCount + 1 end
    
    for groupName, jtacData in pairs(DGSS_CTLD.JTAC_REGISTRY) do
        local grp = Group.getByName(groupName)
        
        -- Check if group exists AND has live units
        local isAlive = false
        if grp and grp:isExist() then
            local units = grp:getUnits()
            if units and #units > 0 then
                -- Check if at least one unit is alive
                for _, u in ipairs(units) do
                    if u and u:isExist() and u:getLife() and u:getLife() > 0 then
                        isAlive = true
                        break
                    end
                end
            end
        end
        
        -- Only clean up if completely dead
        if not isAlive then
            env.info("[DGSS_CTLD] Cleaning up dead JTAC: " .. groupName)
            DGSS_CTLD.JTAC_REGISTRY[groupName] = nil
        end
    end
    
    local afterCount = 0
    for _ in pairs(DGSS_CTLD.JTAC_REGISTRY) do afterCount = afterCount + 1 end
    if beforeCount ~= afterCount then
        env.info("[DGSS_CTLD] Cleanup: JTAC_REGISTRY went from " .. beforeCount .. " to " .. afterCount .. " entries")
    end
end

-- Check and display all active JTACs and vehicles
function DGSS_CTLD.checkActiveJTACs()
    local output = "=== ACTIVE JTAC UNITS AND VEHICLES ===\n\n"
    local activeCount = 0
    
    for jtacGroupName, jtacData in pairs(DGSS_CTLD.JTAC_REGISTRY) do
        local grp = Group.getByName(jtacGroupName)
        
        -- Check if group is alive with live units
        local isAlive = false
        local unitCount = 0
        if grp and grp:isExist() then
            local units = grp:getUnits()
            if units and #units > 0 then
                for _, u in ipairs(units) do
                    if u and u:isExist() and u:getLife() and u:getLife() > 0 then
                        isAlive = true
                        unitCount = unitCount + 1
                    end
                end
            end
        end
        
        if isAlive then
            activeCount = activeCount + 1
            local unit = grp:getUnit(1)
            if unit and unit:isExist() then
                local pos = unit:getPoint()
                if pos then
                    local laserCode = jtacData.laser or 1688
                    local dmStr = DGSS_CTLD.coordinatesToDecimalMinutes(pos)
                    local mgrsStr = DGSS_CTLD.coordinatesToMGRS(pos)
                    
                    -- Target info
                    local tgtInfo = "No target"
                    if jtacData.target and jtacData.target:isExist() then
                        local tgtType = "Unknown"
                        pcall(function() tgtType = jtacData.target:getTypeName() end)
                        tgtInfo = "Lasing: " .. tgtType
                    end
                    
                    output = output .. string.format(
                        "%d. %s\n   Units: %d | Laser: %d | %s\n   Pos: %s\n   MGRS: %s\n\n",
                        activeCount,
                        jtacGroupName,
                        unitCount,
                        laserCode,
                        tgtInfo,
                        dmStr,
                        mgrsStr
                    )
                end
            end
        end
    end
    
    if activeCount == 0 then
        output = output .. "No active JTAC units or vehicles on the map.\n"
    else
        output = output .. string.format("Total Active: %d JTAC team(s)", activeCount)
    end
    
    trigger.action.outText(output, 15)
    env.info("[JTAC] " .. output)
end

-- Simple registry used for menus and persistence only.
-- Actual targeting is handled by JTAC_Manager.
function DGSS_CTLD.registerJTAC(groupName, laserCode)
    env.info("[DGSS_CTLD] Registering JTAC: " .. groupName .. " with laser code " .. (laserCode or 1688))
    DGSS_CTLD.JTAC_REGISTRY[groupName] = {
        laser           = laserCode or 1688,
        last9Line       = 0,
        target          = nil,
        availableTargets = {},
        targetIndex     = 0,
        manualOverride  = false,
        lasedAt         = 0,
        registeredAt    = timer.getTime(),
    }
    
    env.info("[DGSS_CTLD] JTAC_REGISTRY now has " .. countTable(DGSS_CTLD.JTAC_REGISTRY) .. " entries")
    
    -- Create dynamic zone if group exists
    local g = Group.getByName(groupName)
    if g and g:isExist() then
        local u = g:getUnit(1)
        if u and u:isExist() then
            local pos = u:getPoint()
            DGSS_CTLD.createJtacZone(groupName, pos)
        end
    end
    
    return true
end

----------------------------------------------------------------
-- JTAC MENUS (CONDITIONAL VISIBILITY)
----------------------------------------------------------------

function DGSS_CTLD.removeJtacMenusForUnit(unitName)
    local menus = DGSS_CTLD.UNIT_MENUS[unitName]
    if menus and menus.jtacMenu then
        missionCommands.removeItem(menus.jtacMenu)
        menus.jtacMenu = nil
    end
end

-- Old duplicate JTAC menus removed - using universal system instead

----------------------------------------------------------------
-- JTAC UNIT MANAGEMENT (PLAYER-SPECIFIC DESPAWN)
----------------------------------------------------------------

function DGSS_CTLD.despawnPlayerUnitsInZone(playerName, zoneName)
    if not playerName or not zoneName then return 0 end

    local playerGroups = DGSS_CTLD.SPAWNED_BY_PLAYER[playerName] or {}
    local despawned = 0

    for i = #playerGroups, 1, -1 do
        local groupName = playerGroups[i]
        local data = DGSS_CTLD.SPAWNED_GROUPS[groupName]

        if data and data.zone == zoneName then
            local g = Group.getByName(groupName)
            if g and g:isExist() then
                g:destroy()
                despawned = despawned + 1
            end
            DGSS_CTLD.SPAWNED_GROUPS[groupName] = nil
            table.remove(playerGroups, i)
        end
    end

    return despawned
end

function DGSS_CTLD.getPlayerCurrentZone(unit)
    if not unit or not unit:isExist() then return nil end
    local pos = unit:getPoint()
    return DGSS_CTLD.getCurrentZoneName(pos)
end

function DGSS_CTLD.getPlayerGroupsInZone(playerName, zoneName)
    if not playerName or not zoneName then return {} end

    local playerGroups = DGSS_CTLD.SPAWNED_BY_PLAYER[playerName] or {}
    local results = {}

    for _, groupName in ipairs(playerGroups) do
        local data = DGSS_CTLD.SPAWNED_GROUPS[groupName]
        if data and data.zone == zoneName then
            table.insert(results, { name = groupName, data = data })
        end
    end

    return results
end

----------------------------------------------------------------
-- UNIVERSAL JTAC MENU (FOR ALL PLAYERS)
----------------------------------------------------------------

-- Create JTAC menu structure (static - called once per player)
function DGSS_CTLD.createUniversalJtacMenuForUnit(unit)
    if not unit or not unit:isExist() then 
        env.warning("[JTAC Menu] Unit does not exist")
        return 
    end
    if not unit:getPlayerName() then 
        env.warning("[JTAC Menu] Unit has no player name")
        return 
    end

    local unitName = unit:getName()
    local group    = unit:getGroup()
    if not group or not group:isExist() then 
        env.warning("[JTAC Menu] Group does not exist for unit " .. unitName)
        return 
    end
    local groupId  = group:getID()

    -- Check if we already have a universal menu
    if not DGSS_CTLD.UNIT_MENUS[unitName] then
        DGSS_CTLD.UNIT_MENUS[unitName] = { groupId = groupId }
    end

    local menus = DGSS_CTLD.UNIT_MENUS[unitName]
    
    -- Skip if root menu already exists (don't rebuild static parts)
    if menus.jtacUniversalMenu then 
        return
    end

    -- Create universal JTAC root menu (not under CTLD) - STATIC
    env.info("[JTAC Menu] Creating JTAC Control menu for " .. unitName .. " (groupId " .. groupId .. ")")
    local jtacRoot = missionCommands.addSubMenuForGroup(groupId, "JTAC Control", nil)
    menus.jtacUniversalMenu = jtacRoot
    
    if not jtacRoot then
        env.warning("[JTAC Menu] FAILED to create JTAC Control menu")
        return
    end
    
    env.info("[JTAC Menu] JTAC Control menu created successfully")

    -- Create static "Check Active JTACs" command
    missionCommands.addCommandForGroup(
        groupId,
        "Check Active JTACs",
        jtacRoot,
        function()
            DGSS_CTLD.checkActiveJTACs()
        end
    )
    
    -- Placeholder for dynamic JTAC Teams submenu (will be built by updateJtacTeamsMenu)
    menus.teamsMenu = nil
end

-- Update only the dynamic JTAC Teams submenu (called when JTAC count changes)
function DGSS_CTLD.updateJtacTeamsMenu(unitName, groupId)
    if not DGSS_CTLD.UNIT_MENUS[unitName] then return end
    local menus = DGSS_CTLD.UNIT_MENUS[unitName]
    local jtacRoot = menus.jtacUniversalMenu
    
    if not jtacRoot then return end
    
    -- Remove old teams menu if it exists
    if menus.teamsMenu then
        missionCommands.removeItem(menus.teamsMenu)
        menus.teamsMenu = nil
    end
    
    -- Get current JTAC count
    local hasLiveTeams = false
    local liveTeamCount = 0
    for jtacGroupName, _ in pairs(DGSS_CTLD.JTAC_REGISTRY) do
        local grp = Group.getByName(jtacGroupName)
        if grp and grp:isExist() then
            hasLiveTeams = true
            liveTeamCount = liveTeamCount + 1
        end
    end
    
    env.info("[JTAC Menu] Rebuilding Teams submenu for " .. unitName .. " (" .. liveTeamCount .. " teams)")

    -- Create Teams submenu only if we have live teams
    if hasLiveTeams then
        env.info("[JTAC Menu] Creating Teams submenu...")
        local teamsMenu = missionCommands.addSubMenuForGroup(groupId, "JTAC Teams", jtacRoot)
        menus.teamsMenu = teamsMenu  -- persist so it can be removed on next rebuild
        
        if not teamsMenu then
            env.warning("[JTAC Menu] FAILED to create Teams submenu")
            return
        end
        
        env.info("[JTAC Menu] Teams submenu created, now adding team entries...")

        -- Build per-team menus ONLY for LIVE teams
        for jtacGroupName, jtacData in pairs(DGSS_CTLD.JTAC_REGISTRY) do
            local grp = Group.getByName(jtacGroupName)
            -- Skip dead teams - only process LIVE teams
            if grp and grp:isExist() then
                env.info("[JTAC Menu] Adding menu for team: " .. jtacGroupName)
                local teamMenu = missionCommands.addSubMenuForGroup(groupId, jtacGroupName, teamsMenu)

                -- Laser code submenu for this team
                local codeMenu = missionCommands.addSubMenuForGroup(groupId, "Laser Code", teamMenu)

                for _, code in ipairs(DGSS_CTLD.JTAC_LASER_CODES) do
                    local codeCopy, teamNameCopy = code, jtacGroupName
                    missionCommands.addCommandForGroup(
                        groupId,
                        tostring(code),
                        codeMenu,
                        function()
                            JTAC_Manager.updateLaserCode(teamNameCopy, codeCopy)
                            local jtac = DGSS_CTLD.JTAC_REGISTRY[teamNameCopy]
                            if jtac then
                                jtac.laser = codeCopy
                            end
                            trigger.action.outText(string.format("[JTAC %s] Laser code set to %d",
                                teamNameCopy, codeCopy), 5)
                        end
                    )
                end

                -- Status for this team
                local teamNameCopy = jtacGroupName
                missionCommands.addCommandForGroup(
                    groupId,
                    "Team Status",
                    teamMenu,
                    function()
                        local g = Group.getByName(teamNameCopy)
                        local status = "OFFLINE"
                        local posStr = ""
                        local tgtStr = "None"
                        if g and g:isExist() then
                            status = "ACTIVE"
                            local u = g:getUnit(1)
                            if u and u:isExist() then
                                local pos = u:getPoint()
                                if pos then
                                    posStr = "\nPos: " .. DGSS_CTLD.coordinatesToDecimalMinutes(pos)
                                end
                            end
                        end

                        local jtac = DGSS_CTLD.JTAC_REGISTRY[teamNameCopy]
                        local laserCode = jtac and jtac.laser or 1688
                        if jtac and jtac.target and jtac.target:isExist() then
                            pcall(function() tgtStr = jtac.target:getTypeName() end)
                        end

                        trigger.action.outText(
                            string.format("[JTAC %s] Status: %s | Laser: %d | Target: %s%s",
                                teamNameCopy, status, laserCode, tgtStr, posStr),
                            8
                        )
                    end
                )

                -- 9-Line Callout for this team
                missionCommands.addCommandForGroup(
                    groupId,
                    "Request 9-Line Callout",
                    teamMenu,
                    function()
                        local g = Group.getByName(teamNameCopy)
                        if not g or not g:isExist() then
                            trigger.action.outText(
                                string.format("[JTAC %s] Team is offline!", teamNameCopy),
                                5
                            )
                            return
                        end

                        local u = g:getUnit(1)
                        if not u or not u:isExist() then
                            trigger.action.outText(
                                string.format("[JTAC %s] Team is offline!", teamNameCopy),
                                5
                            )
                            return
                        end

                        -- Get JTAC registry data for this team
                        if not DGSS_CTLD or not DGSS_CTLD.JTAC_REGISTRY then
                            trigger.action.outText(string.format("[JTAC %s] JTAC_REGISTRY not initialized!", teamNameCopy), 5)
                            return
                        end
                        
                        local jtacData = DGSS_CTLD.JTAC_REGISTRY[teamNameCopy]
                        if not jtacData then
                            trigger.action.outText(string.format("[JTAC %s] No JTAC data available!", teamNameCopy), 5)
                            return
                        end

                        -- Try to use currently lased target, fallback to nearest available target
                        local targetUnit = nil
                        if jtacData.target and jtacData.target:isExist() then
                            targetUnit = jtacData.target
                        elseif jtacData.availableTargets and #jtacData.availableTargets > 0 then
                            -- Use first (closest) available target
                            local closestGroup = jtacData.availableTargets[1].group
                            if closestGroup and closestGroup:isExist() then
                                local units = closestGroup:getUnits()
                                if #units > 0 then
                                    targetUnit = units[1]
                                end
                            end
                        end

                        if not targetUnit or not targetUnit:isExist() then
                            trigger.action.outText(
                                string.format("[JTAC %s] No targets in range!", teamNameCopy),
                                5
                            )
                            return
                        end

                        -- Generate and display 9-line callout
                        local callout = DGSS_CTLD.generate9LineCallout(teamNameCopy, targetUnit, u)
                        if callout then
                            trigger.action.outText(callout, 15)
                        else
                            trigger.action.outText(
                                string.format("[JTAC %s] Unable to generate 9-line callout!", teamNameCopy),
                                5
                            )
                        end
                    end
                )

                -- Deploy Smoke on Target
                missionCommands.addCommandForGroup(
                    groupId,
                    "Deploy Smoke on Target",
                    teamMenu,
                    function()
                        local g = Group.getByName(teamNameCopy)
                        if not g or not g:isExist() then
                            trigger.action.outText(
                                string.format("[JTAC %s] Team is offline!", teamNameCopy),
                                5
                            )
                            return
                        end

                        -- Deploy smoke via internal function
                        deployTargetSmoke(teamNameCopy)
                        trigger.action.outText(
                            string.format("[JTAC %s] Smoke deployed on target!", teamNameCopy),
                            5
                        )
                    end
                )

                -- Target Selection Submenu
                local targetMenu = missionCommands.addSubMenuForGroup(groupId, "Select Target", teamMenu)

                -- List Nearby Targets
                missionCommands.addCommandForGroup(
                    groupId,
                    "List Available Targets",
                    targetMenu,
                    function()
                        local g = Group.getByName(teamNameCopy)
                        if not g or not g:isExist() then
                            trigger.action.outText(
                                string.format("[JTAC %s] Team is offline!", teamNameCopy),
                                5
                            )
                            return
                        end

                        local u = g:getUnit(1)
                        if not u or not u:isExist() then
                            trigger.action.outText(
                                string.format("[JTAC %s] Team is offline!", teamNameCopy),
                                5
                            )
                            return
                        end

                        local jtacData = DGSS_CTLD.JTAC_REGISTRY[teamNameCopy]
                        if not jtacData or #jtacData.availableTargets == 0 then
                            trigger.action.outText(
                                string.format("[JTAC %s] No targets in range!", teamNameCopy),
                                5
                            )
                            return
                        end

                        local targetList = string.format("[JTAC %s] Targets in range (%d):\n", teamNameCopy, #jtacData.availableTargets)
                        for i, tgtData in ipairs(jtacData.availableTargets) do
                            local marker = (jtacData.targetIndex == i and jtacData.manualOverride) and ">" or " "
                            targetList = targetList .. string.format("%s%d. %s - %.0f m\n", marker, i, tgtData.typeName, tgtData.dist)
                        end
                        trigger.action.outText(targetList, 10)
                    end
                )

                -- Next Target
                missionCommands.addCommandForGroup(
                    groupId,
                    "Next Target >>",
                    targetMenu,
                    function()
                        local jtacData = DGSS_CTLD.JTAC_REGISTRY[teamNameCopy]
                        if not jtacData or #jtacData.availableTargets == 0 then
                            trigger.action.outText(
                                string.format("[JTAC %s] No targets in range!", teamNameCopy),
                                5
                            )
                            return
                        end

                        jtacData.targetIndex = jtacData.targetIndex + 1
                        if jtacData.targetIndex > #jtacData.availableTargets then
                            jtacData.targetIndex = 1
                        end
                        jtacData.manualOverride = true

                        local tgtData = jtacData.availableTargets[jtacData.targetIndex]
                        trigger.action.outText(
                            string.format("[JTAC %s] Target %d selected: %s (%.0f m)", 
                                teamNameCopy, jtacData.targetIndex, tgtData.typeName, tgtData.dist),
                            5
                        )
                    end
                )

                -- Previous Target
                missionCommands.addCommandForGroup(
                    groupId,
                    "<< Previous Target",
                    targetMenu,
                    function()
                        local jtacData = DGSS_CTLD.JTAC_REGISTRY[teamNameCopy]
                        if not jtacData or #jtacData.availableTargets == 0 then
                            trigger.action.outText(
                                string.format("[JTAC %s] No targets in range!", teamNameCopy),
                                5
                            )
                            return
                        end

                        jtacData.targetIndex = jtacData.targetIndex - 1
                        if jtacData.targetIndex < 1 then
                            jtacData.targetIndex = #jtacData.availableTargets
                        end
                        jtacData.manualOverride = true

                        local tgtData = jtacData.availableTargets[jtacData.targetIndex]
                        trigger.action.outText(
                            string.format("[JTAC %s] Target %d selected: %s (%.0f m)", 
                                teamNameCopy, jtacData.targetIndex, tgtData.typeName, tgtData.dist),
                            5
                        )
                    end
                )

                -- Auto Target (Return to Auto-Select)
                missionCommands.addCommandForGroup(
                    groupId,
                    "Auto Target (Nearest)",
                    targetMenu,
                    function()
                        local jtacData = DGSS_CTLD.JTAC_REGISTRY[teamNameCopy]
                        jtacData.manualOverride = false
                        jtacData.targetIndex = 0
                        trigger.action.outText(
                            string.format("[JTAC %s] Target selection: AUTO (nearest)", teamNameCopy),
                            5
                        )
                    end
                )
            end
        end
    end
end

-- Create universal JTAC menus for all units (both transport and non-transport)
local function createUniversalJtacMenusForAllUnits()
    for unitName, menus in pairs(DGSS_CTLD.UNIT_MENUS) do
        local unit = Unit.getByName(unitName)
        if unit and unit:isExist() then
            DGSS_CTLD.createUniversalJtacMenuForUnit(unit)
        end
    end
end

-- Note: Menus are created lazily by the poller, not rebuilt on registration

----------------------------------------------------------------
-- UNIT MENU CLEANUP
----------------------------------------------------------------

function DGSS_CTLD.cleanupMenusForUnit(unitName)
    local menus = DGSS_CTLD.UNIT_MENUS[unitName]
    if not menus then return end

    if menus.ctldRoot then
        missionCommands.removeItem(menus.ctldRoot)
    end

    if menus.jtacUniversalMenu then
        missionCommands.removeItem(menus.jtacUniversalMenu)
    end

    DGSS_CTLD.UNIT_MENUS[unitName] = nil
end

----------------------------------------------------------------
-- STATIC CTLD MENU CREATION (PER UNIT - ONLY FOR VALID TRANSPORT)
----------------------------------------------------------------

function DGSS_CTLD.createMenusForUnit(unit)
    if not unit or not unit:isExist() then return end
    if not unit:getPlayerName() then return end

    local unitName = unit:getName()
    local group    = unit:getGroup()
    if not group or not group:isExist() then return end
    local groupId  = group:getID()

    -- Initialize UNIT_MENUS entry if it doesn't exist
    if not DGSS_CTLD.UNIT_MENUS[unitName] then
        DGSS_CTLD.UNIT_MENUS[unitName] = { groupId = groupId }
    end
    
    -- Skip if CTLD menu already created, BUT still check if Vehicles submenu
    -- needs to be added (player may have entered a CTLD zone since last build).
    if DGSS_CTLD.UNIT_MENUS[unitName].ctldRoot then
        local existingMenus = DGSS_CTLD.UNIT_MENUS[unitName]
        if not existingMenus.vehiclesMenu and DGSS_CTLD.isValidVehicleTransport(unit) then
            -- Player is now in a CTLD zone – add the Vehicles submenu retroactively
            local ctldRoot = existingMenus.ctldRoot
            local vehiclesMenu = missionCommands.addSubMenuForGroup(groupId, "Vehicles", ctldRoot)
            existingMenus.vehiclesMenu = vehiclesMenu
            if vehiclesMenu then
                local categories = {}
                for key, tpl in pairs(DGSS_CTLD.VEHICLE_TEMPLATES) do
                    local cat = tpl.category or "Other"
                    categories[cat] = categories[cat] or {}
                    table.insert(categories[cat], { key = key, tpl = tpl })
                end
                local sortedCats = {}
                for cat,_ in pairs(categories) do table.insert(sortedCats, cat) end
                table.sort(sortedCats)
                for _, cat in ipairs(sortedCats) do
                    local catMenu = missionCommands.addSubMenuForGroup(groupId, cat, vehiclesMenu)
                    table.sort(categories[cat], function(a,b) return a.tpl.displayName < b.tpl.displayName end)
                    for _, entry in ipairs(categories[cat]) do
                        local tpl = entry.tpl
                        local label = "Spawn " .. tpl.displayName
                        local vehicleTypeCopy = entry.key
                        missionCommands.addCommandForGroup(groupId, label, catMenu,
                            function()
                                local u = Unit.getByName(unitName)
                                if u and u:isExist() then
                                    trigger.action.outTextForUnit(u:getID(), "[DEBUG] Spawn menu triggered for " .. (tpl.displayName or vehicleTypeCopy), 3)
                                    DGSS_CTLD.spawnVehicleNearUnit(u, vehicleTypeCopy)
                                end
                            end
                        )
                    end
                end
                env.info("[CTLD] Vehicles submenu added retroactively for " .. unitName .. " (now inside CTLD zone)")
            end
        end
        return
    end

    -- CTLD menu is ALWAYS created for all players (not just transports)
    -- This way all players see CTLD is available and can try to spawn
    local ctldRoot = missionCommands.addSubMenuForGroup(groupId, "CTLD", nil)
    DGSS_CTLD.UNIT_MENUS[unitName].ctldRoot = ctldRoot

    ------------------------------------------------------------
    -- TROOPS (STATIC MENU, BUT TEMPLATE-DRIVEN)
    ------------------------------------------------------------
    if DGSS_CTLD.isValidTransport(unit) then
        local troopsMenu = missionCommands.addSubMenuForGroup(groupId, "Troops", ctldRoot)
        DGSS_CTLD.UNIT_MENUS[unitName].troopsMenu = troopsMenu

        -- Build categories from templates (config-driven, not world-driven)
        local categories = {}

        for key, tpl in pairs(DGSS_CTLD.TROOP_TEMPLATES) do
            local cat = tpl.category or "Other"
            categories[cat] = categories[cat] or {}
            table.insert(categories[cat], { key = key, tpl = tpl })
        end

        local sortedCats = {}
        for cat,_ in pairs(categories) do table.insert(sortedCats, cat) end
        table.sort(sortedCats)

        for _, cat in ipairs(sortedCats) do
            local catMenu = missionCommands.addSubMenuForGroup(groupId, cat, troopsMenu)

            table.sort(categories[cat], function(a,b)
                return a.tpl.displayName < b.tpl.displayName
            end)

            for _, entry in ipairs(categories[cat]) do
                local tpl = entry.tpl
                local count = #tpl.units
                local label = string.format("Spawn %s (%d)", tpl.displayName, count)

                -- Add spawn count for JTAC teams (real-time)
                if entry.key == "JTAC Team" then
                    local current, max = DGSS_CTLD.checkTeamLimit()
                    label = string.format("Spawn JTAC Team (%d/%d)", current, max)
                end

                local templateNameCopy = entry.key
                missionCommands.addCommandForGroup(
                    groupId,
                    label,
                    catMenu,
                    function()
                        local u = Unit.getByName(unitName)
                        if u and u:isExist() then
                            trigger.action.outTextForUnit(u:getID(), "[DEBUG] Spawn menu triggered for " .. (tpl.displayName or templateNameCopy), 3)
                            DGSS_CTLD.spawnTroopsAtUnit(u, templateNameCopy)
                        end
                    end
                )
            end
        end
    end

    ------------------------------------------------------------
    -- VEHICLES (STATIC, TEMPLATE-DRIVEN)
    ------------------------------------------------------------
    if DGSS_CTLD.isValidVehicleTransport(unit) then
        local vehiclesMenu = missionCommands.addSubMenuForGroup(groupId, "Vehicles", ctldRoot)
        DGSS_CTLD.UNIT_MENUS[unitName].vehiclesMenu = vehiclesMenu

        local categories = {}

        for key, tpl in pairs(DGSS_CTLD.VEHICLE_TEMPLATES) do
            local cat = tpl.category or "Other"
            categories[cat] = categories[cat] or {}
            table.insert(categories[cat], { key = key, tpl = tpl })
        end

        local sortedCats = {}
        for cat,_ in pairs(categories) do table.insert(sortedCats, cat) end
        table.sort(sortedCats)

        for _, cat in ipairs(sortedCats) do
            local catMenu = missionCommands.addSubMenuForGroup(groupId, cat, vehiclesMenu)

            table.sort(categories[cat], function(a,b)
                return a.tpl.displayName < b.tpl.displayName
            end)

            for _, entry in ipairs(categories[cat]) do
                local tpl = entry.tpl
                local label = "Spawn " .. tpl.displayName

                -- Add spawn count for JTAC vehicles (real-time)
                if entry.key == "JTAC HMMWV" then
                    local current, max = DGSS_CTLD.checkVehicleLimit()
                    label = string.format("Spawn JTAC HMMWV (%d/%d)", current, max)
                end

                local vehicleTypeCopy = entry.key
                missionCommands.addCommandForGroup(
                    groupId,
                    label,
                    catMenu,
                    function()
                        local u = Unit.getByName(unitName)
                        if u and u:isExist() then
                            trigger.action.outTextForUnit(u:getID(), "[DEBUG] Spawn menu triggered for " .. (tpl.displayName or vehicleTypeCopy), 3)
                            DGSS_CTLD.spawnVehicleNearUnit(u, vehicleTypeCopy)
                        end
                    end
                )
            end
        end
    end

    ------------------------------------------------------------
    -- NASAMS CRATE OPERATIONS
    -- Spawn/assemble available to all players.
    -- Pick-up/drop available to valid troop transports (helos + C-130J).
    ------------------------------------------------------------
    do
        local nasamsMenu = missionCommands.addSubMenuForGroup(groupId, "NASAMS Crates", ctldRoot)

        -- Spawn 1-5 crates at once (player chooses, must be in CTLD zone)
        local spawnSubMenu = missionCommands.addSubMenuForGroup(groupId, "Spawn Crates", nasamsMenu)
        for _n = 1, 5 do
            local n = _n
            local label = (n == 1) and "Spawn 1 Crate" or ("Spawn " .. n .. " Crates")
            missionCommands.addCommandForGroup(groupId, label, spawnSubMenu,
                function()
                    local u = Unit.getByName(unitName)
                    if u and u:isExist() then DGSS_CTLD.spawnNASAMSCrate(u, n) end
                end)
        end

        -- Assemble the site once all 5 crates are in position
        missionCommands.addCommandForGroup(groupId, "Assemble NASAMS Site", nasamsMenu,
            function()
                local u = Unit.getByName(unitName)
                if u and u:isExist() then DGSS_CTLD.assembleNASAMSSite(u) end
            end)

        -- Status readout (coalition-wide)
        missionCommands.addCommandForGroup(groupId, "Check Crate Status", nasamsMenu,
            function()
                DGSS_CTLD.nasamsStatus()
            end)

        -- Pick-up and drop only for valid transport aircraft
        if DGSS_CTLD.VALID_TROOP_TRANSPORT[unit:getTypeName()] then
            missionCommands.addCommandForGroup(groupId, "Pick Up Nearest Crate", nasamsMenu,
                function()
                    local u = Unit.getByName(unitName)
                    if u and u:isExist() then DGSS_CTLD.pickupNASAMSCrate(u) end
                end)

            missionCommands.addCommandForGroup(groupId, "Drop NASAMS Crate", nasamsMenu,
                function()
                    local u = Unit.getByName(unitName)
                    if u and u:isExist() then DGSS_CTLD.dropNASAMSCrate(u) end
                end)
        end
    end

    ------------------------------------------------------------
    -- LOAD/UNLOAD (TOP-LEVEL - SAME AS TROOPS/VEHICLES/DESPAWN)
    ------------------------------------------------------------
    if DGSS_CTLD.isValidTransport(unit) then
        local capturedUnitName = unitName  -- capture for closure
        missionCommands.addCommandForGroup(
            groupId,
            "Load Nearby Troops",
            ctldRoot,
            function()
                env.info(string.format("[CTLD] Load Nearby Troops menu clicked for unit '%s'", capturedUnitName))
                local u = Unit.getByName(capturedUnitName)
                if not u then
                    env.info("[CTLD] Load Nearby Troops: Unit.getByName returned nil")
                    return
                end
                if not u:isExist() then
                    env.info("[CTLD] Load Nearby Troops: Unit does not exist")
                    return
                end
                env.info("[CTLD] Load Nearby Troops: Calling loadNearestTroops...")
                DGSS_CTLD.loadNearestTroops(u)
            end
        )

        missionCommands.addCommandForGroup(
            groupId,
            "Unload Troops",
            ctldRoot,
            function()
                env.info(string.format("[CTLD] Unload Troops menu clicked for unit '%s'", capturedUnitName))
                local u = Unit.getByName(capturedUnitName)
                if u and u:isExist() then
                    DGSS_CTLD.unloadAllTroops(u)
                end
            end
        )
    end

    if DGSS_CTLD.isValidVehicleTransport(unit) then
        -- Check if unit is one of the actual vehicle transport types
        local unitType = unit:getTypeName()
        local isActualTransport = (unitType == "UH-1H" or unitType == "Mi-8MT" or 
                                   unitType == "CH-47Fbl1" or unitType == "C-130J-30")
        
        if isActualTransport then
            missionCommands.addCommandForGroup(
                groupId,
                "Load Nearby Vehicle",
                ctldRoot,
                function()
                    local u = Unit.getByName(unitName)
                    if u and u:isExist() then
                        DGSS_CTLD.loadVehicleFromGround(u)
                    end
                end
            )

            missionCommands.addCommandForGroup(
                groupId,
                "Unload Vehicle",
                ctldRoot,
                function()
                    local u = Unit.getByName(unitName)
                    if u and u:isExist() then
                        DGSS_CTLD.unloadVehicle(u)
                    end
                end
            )
        end
    end

    ------------------------------------------------------------
    -- COMBINED ARMS: GROUND UNIT SPAWN SUPPORT
    -- CA players can spawn troops/vehicles when in a CTLD zone
    ------------------------------------------------------------
    if DGSS_CTLD.isCombinedArmsUnit(unit) then
        local caSpawnMenu = missionCommands.addSubMenuForGroup(groupId, "Spawn Units", ctldRoot)

        -- Troop templates
        local caTroopsMenu = missionCommands.addSubMenuForGroup(groupId, "Troops", caSpawnMenu)
        local troopCats = {}
        for key, tpl in pairs(DGSS_CTLD.TROOP_TEMPLATES) do
            local cat = tpl.category or "Other"
            troopCats[cat] = troopCats[cat] or {}
            table.insert(troopCats[cat], { key = key, tpl = tpl })
        end
        local sortedTroopCats = {}
        for cat, _ in pairs(troopCats) do table.insert(sortedTroopCats, cat) end
        table.sort(sortedTroopCats)
        for _, cat in ipairs(sortedTroopCats) do
            local catMenu = missionCommands.addSubMenuForGroup(groupId, cat, caTroopsMenu)
            table.sort(troopCats[cat], function(a,b) return a.tpl.displayName < b.tpl.displayName end)
            for _, entry in ipairs(troopCats[cat]) do
                local tpl = entry.tpl
                local count = #tpl.units
                local label = string.format("Spawn %s (%d)", tpl.displayName, count)
                local templateNameCopy = entry.key
                missionCommands.addCommandForGroup(
                    groupId, label, catMenu,
                    function()
                        local u = Unit.getByName(unitName)
                        if u and u:isExist() then
                            DGSS_CTLD.spawnTroopsAtUnit(u, templateNameCopy)
                        end
                    end
                )
            end
        end

        -- Vehicle templates
        local caVehiclesMenu = missionCommands.addSubMenuForGroup(groupId, "Vehicles", caSpawnMenu)
        local vehCats = {}
        for key, tpl in pairs(DGSS_CTLD.VEHICLE_TEMPLATES) do
            local cat = tpl.category or "Other"
            vehCats[cat] = vehCats[cat] or {}
            table.insert(vehCats[cat], { key = key, tpl = tpl })
        end
        local sortedVehCats = {}
        for cat, _ in pairs(vehCats) do table.insert(sortedVehCats, cat) end
        table.sort(sortedVehCats)
        for _, cat in ipairs(sortedVehCats) do
            local catMenu = missionCommands.addSubMenuForGroup(groupId, cat, caVehiclesMenu)
            table.sort(vehCats[cat], function(a,b) return a.tpl.displayName < b.tpl.displayName end)
            for _, entry in ipairs(vehCats[cat]) do
                local tpl = entry.tpl
                local label = "Spawn " .. tpl.displayName
                local vehicleTypeCopy = entry.key
                missionCommands.addCommandForGroup(
                    groupId, label, catMenu,
                    function()
                        local u = Unit.getByName(unitName)
                        if u and u:isExist() then
                            DGSS_CTLD.spawnVehicleNearUnit(u, vehicleTypeCopy)
                        end
                    end
                )
            end
        end
    end

    ------------------------------------------------------------
    -- DESPAWN (CTLD-SPECIFIC)
    ------------------------------------------------------------
    missionCommands.addCommandForGroup(
        groupId,
        "De-spawn Units",
        ctldRoot,
        function()
            local u = Unit.getByName(unitName)
            if u and u:isExist() then
                local playerName = u:getPlayerName()
                local zoneName = DGSS_CTLD.getPlayerCurrentZone(u)

                if not zoneName then
                    trigger.action.outTextForUnit(u:getID(),
                        "You must be inside a CTLD zone to despawn your units!", 5)
                    return
                end

                local count = DGSS_CTLD.despawnPlayerUnitsInZone(playerName, zoneName)
                trigger.action.outTextForUnit(u:getID(),
                    string.format("Despawned %d unit(s) in %s zone.", count, zoneName), 6)
            end
        end
    )

end

----------------------------------------------------------------
-- PLAYER LEAVE HANDLER + MENU POLLER
----------------------------------------------------------------

local PLAYER_LEAVE_HANDLER_CTLD = {}
function PLAYER_LEAVE_HANDLER_CTLD:onEvent(event)
    if not event or not event.id then return end
    local _ok, _err = pcall(function()
        if event.id == world.event.S_EVENT_PLAYER_LEAVE_UNIT then
            local unit = event.initiator
            if not unit then return end
            local okExists, exists = pcall(function() return unit:isExist() end)
            if okExists and exists then
                local okName, unitName = pcall(function() return unit:getName() end)
                if okName and unitName then
                    DGSS_CTLD.cleanupMenusForUnit(unitName)
                end
            end
        end
    end)
    if not _ok then env.warning("[CTLD] onEvent error: " .. tostring(_err)) end
end
world.addEventHandler(PLAYER_LEAVE_HANDLER_CTLD)

-- Immediately create menus when a player enters any aircraft/unit
local PLAYER_ENTER_HANDLER_CTLD = {}
function PLAYER_ENTER_HANDLER_CTLD:onEvent(event)
    if not event or not event.id then return end
    if event.id ~= world.event.S_EVENT_PLAYER_ENTER_UNIT then return end
    local _ok, _err = pcall(function()
        local unit = event.initiator
        if not unit then return end
        if not unit:isExist() then return end
        if not unit:getPlayerName() then return end
        
        local unitName = unit:getName()
        local group = unit:getGroup()
        if not group or not group:isExist() then return end
        local groupId = group:getID()
        
        env.info("[CTLD] Player entered unit: " .. unitName .. " (groupId " .. groupId .. ") - creating menus")
        
        -- Stale menu check: if groupId changed, clear old menus
        if DGSS_CTLD.UNIT_MENUS[unitName] and DGSS_CTLD.UNIT_MENUS[unitName].groupId ~= groupId then
            env.info("[CTLD] GroupId changed for " .. unitName .. " - clearing stale menus")
            DGSS_CTLD.cleanupMenusForUnit(unitName)
        end
        
        -- Create CTLD menu
        if not DGSS_CTLD.UNIT_MENUS[unitName] or not DGSS_CTLD.UNIT_MENUS[unitName].ctldRoot then
            pcall(function() DGSS_CTLD.createMenusForUnit(unit) end)
        end
        
        -- Create JTAC menu for ALL players regardless of aircraft type
        if not DGSS_CTLD.UNIT_MENUS[unitName] or not DGSS_CTLD.UNIT_MENUS[unitName].jtacUniversalMenu then
            pcall(function() DGSS_CTLD.createUniversalJtacMenuForUnit(unit) end)
        end
        
        -- Build JTAC teams submenu immediately
        if DGSS_CTLD.UNIT_MENUS[unitName] and DGSS_CTLD.UNIT_MENUS[unitName].jtacUniversalMenu then
            pcall(function() DGSS_CTLD.updateJtacTeamsMenu(unitName, groupId) end)
        end
    end)
    if not _ok then env.warning("[CTLD] Player enter event error: " .. tostring(_err)) end
end
world.addEventHandler(PLAYER_ENTER_HANDLER_CTLD)

local function safeCreateMenusForUnit_CTLD(unit)
    if not unit or not unit:isExist() then return end
    if not unit:getPlayerName() then return end

    local unitName = unit:getName()
    
    -- Only skip if CTLD menu is ALREADY created (not if entire UNIT_MENUS entry exists)
    if DGSS_CTLD.UNIT_MENUS[unitName] and DGSS_CTLD.UNIT_MENUS[unitName].ctldRoot then 
        return 
    end

    DGSS_CTLD.createMenusForUnit(unit)
end

local function createJtacMenuForAllPlayers(unit)
    if not unit or not unit:isExist() then return end
    if not unit:getPlayerName() then return end

    local unitName = unit:getName()
    
    -- Create JTAC menu for ALL players, regardless of aircraft type
    if not DGSS_CTLD.UNIT_MENUS[unitName] or not DGSS_CTLD.UNIT_MENUS[unitName].jtacUniversalMenu then
        DGSS_CTLD.createUniversalJtacMenuForUnit(unit)
    end
end

local function universalMenuPoller_CTLD()
    local success, err = pcall(function()
        -- Safe coalition API calls
        local bluePlanes = {}
        local blueHelos = {}
        pcall(function()
            bluePlanes = coalition.getGroups(DGSS_CTLD.COALITION, Group.Category.AIRPLANE) or {}
            blueHelos = coalition.getGroups(DGSS_CTLD.COALITION, Group.Category.HELICOPTER) or {}
        end)

        -- Clean up dead JTAC entries periodically
        DGSS_CTLD.cleanupDeadJTACs()

        -- Count ONLY valid (existing) JTAC teams for accurate menu change detection
        local registrySize = 0
        for _ in pairs(DGSS_CTLD.JTAC_REGISTRY) do registrySize = registrySize + 1 end
        
        local currentJtacCount = 0
        for groupName, _ in pairs(DGSS_CTLD.JTAC_REGISTRY) do
            local grp
            pcall(function() grp = Group.getByName(groupName) end)
            if grp and grp:isExist() then
                currentJtacCount = currentJtacCount + 1
                env.info("[JTAC Poller] Found live JTAC: " .. groupName)
            else
                env.info("[JTAC Poller] JTAC in registry but dead/invalid: " .. groupName)
            end
        end
        
        env.info("[JTAC Poller] Registry size: " .. registrySize .. " | Live count: " .. currentJtacCount)
        
        -- Only rebuild menus if JTAC count changed (not every cycle)
        local jtacCountChanged = (currentJtacCount ~= DGSS_CTLD.LAST_JTAC_COUNT)
        DGSS_CTLD.LAST_JTAC_COUNT = currentJtacCount

    -- Process aircraft
    for _, group in ipairs(bluePlanes) do
        if group and group:isExist() then
            for _, unit in ipairs(group:getUnits()) do
                if unit and unit:isExist() and unit:getPlayerName() then
                    safeCreateMenusForUnit_CTLD(unit)
                    local unitName = unit:getName()
                    
                    -- Only rebuild JTAC menus when count changes (not every cycle)
                    if jtacCountChanged then
                        -- Count changed - rebuild menus
                        if DGSS_CTLD.UNIT_MENUS[unitName] and DGSS_CTLD.UNIT_MENUS[unitName].jtacUniversalMenu then
                            missionCommands.removeItem(DGSS_CTLD.UNIT_MENUS[unitName].jtacUniversalMenu)
                            DGSS_CTLD.UNIT_MENUS[unitName].jtacUniversalMenu = nil
                        end
                        if currentJtacCount > 0 then
                            DGSS_CTLD.createUniversalJtacMenuForUnit(unit)
                        end
                    elseif currentJtacCount > 0 and not DGSS_CTLD.UNIT_MENUS[unitName] then
                        -- First time - create menu
                        DGSS_CTLD.createUniversalJtacMenuForUnit(unit)
                    end
                end
            end
        end
    end

    -- Process helicopters
    for _, group in ipairs(blueHelos) do
        if group and group:isExist() then
            for _, unit in ipairs(group:getUnits()) do
                if unit and unit:isExist() and unit:getPlayerName() then
                    safeCreateMenusForUnit_CTLD(unit)
                    local unitName = unit:getName()
                    
                    -- Only rebuild JTAC menus when count changes (not every cycle)
                    if jtacCountChanged then
                        -- Count changed - rebuild menus
                        if DGSS_CTLD.UNIT_MENUS[unitName] and DGSS_CTLD.UNIT_MENUS[unitName].jtacUniversalMenu then
                            missionCommands.removeItem(DGSS_CTLD.UNIT_MENUS[unitName].jtacUniversalMenu)
                            DGSS_CTLD.UNIT_MENUS[unitName].jtacUniversalMenu = nil
                        end
                        if currentJtacCount > 0 then
                            DGSS_CTLD.createUniversalJtacMenuForUnit(unit)
                        end
                    elseif currentJtacCount > 0 and not DGSS_CTLD.UNIT_MENUS[unitName] then
                        -- First time - create menu
                        DGSS_CTLD.createUniversalJtacMenuForUnit(unit)
                    end
                end
            end
        end
    end

    -- Schedule next run (increased interval from 3s to 10s for better performance)
    if mist and mist.scheduleFunction then
        mist.scheduleFunction(universalMenuPoller_CTLD, {}, timer.getTime() + 10)
    else
        timer.scheduleFunction(universalMenuPoller_CTLD, {}, timer.getTime() + 10)
    end
    end)  -- close pcall
    
    if not success then
        env.warning("[JTAC Poller] ERROR: " .. tostring(err))
    end
end

-- Start menu poller (increased interval from 2s to 3s for better performance)
-- [DISABLED] Using staticJtacMenuBuilder instead which creates both CTLD and JTAC menus
--[[
if mist and mist.scheduleFunction then
    mist.scheduleFunction(universalMenuPoller_CTLD, {}, timer.getTime() + 3)
else
    timer.scheduleFunction(universalMenuPoller_CTLD, {}, timer.getTime() + 3)
end
]]--

----------------------------------------------------------------
-- STATUS MONITORING LOOP
-- Logs system status every 60 seconds for diagnostics
----------------------------------------------------------------

local function statusMonitorLoop()
    DGSS_CTLD.logSystemStatus()
    
    if mist and mist.scheduleFunction then
        mist.scheduleFunction(statusMonitorLoop, {}, timer.getTime() + 60)
    else
        timer.scheduleFunction(statusMonitorLoop, {}, timer.getTime() + 60)
    end
end

-- Start status monitor
if mist and mist.scheduleFunction then
    mist.scheduleFunction(statusMonitorLoop, {}, timer.getTime() + 60)
else
    timer.scheduleFunction(statusMonitorLoop, {}, timer.getTime() + 60)
end

----------------------------------------------------------------
-- STATIC JTAC MENU (ALWAYS AVAILABLE)
-- Create JTAC Control menu once and keep it visible for all players
----------------------------------------------------------------

local function staticJtacMenuBuilder()
    local ok, err = pcall(function()
    -- Get all blue players
    local bluePlanes = coalition.getGroups(DGSS_CTLD.COALITION, Group.Category.AIRPLANE) or {}
    local blueHelos = coalition.getGroups(DGSS_CTLD.COALITION, Group.Category.HELICOPTER) or {}
    
    -- Count current active JTACs to detect changes
    local currentJtacCount = 0
    for groupName, _ in pairs(DGSS_CTLD.JTAC_REGISTRY) do
        local grp = Group.getByName(groupName)
        if grp and grp:isExist() then
            currentJtacCount = currentJtacCount + 1
        end
    end
    
    -- Always rebuild JTAC teams menus if count changed
    local rebuildJtacMenus = (currentJtacCount ~= DGSS_CTLD.LAST_MENU_JTAC_COUNT)
    
    if rebuildJtacMenus then
        DGSS_CTLD.LAST_MENU_JTAC_COUNT = currentJtacCount
        env.info("[Static Menu Builder] JTAC count changed to " .. currentJtacCount .. ", rebuilding menus")
    end
    
    -- Helper to process a single player unit
    local function processPlayerUnit(unit)
        if not unit or not unit:isExist() then return end
        if not unit:getPlayerName() then return end
        
        local unitName = unit:getName()
        local unitGroup = unit:getGroup()
        if not unitGroup or not unitGroup:isExist() then return end
        local groupId = unitGroup:getID()
        
        -- Stale groupId detection: if groupId changed, clear old menus
        if DGSS_CTLD.UNIT_MENUS[unitName] and DGSS_CTLD.UNIT_MENUS[unitName].groupId 
           and DGSS_CTLD.UNIT_MENUS[unitName].groupId ~= groupId then
            env.info("[Static Menu Builder] GroupId changed for " .. unitName .. " - clearing stale menus")
            pcall(function() DGSS_CTLD.cleanupMenusForUnit(unitName) end)
        end
        
        -- Create CTLD menu
        if not DGSS_CTLD.UNIT_MENUS[unitName] or not DGSS_CTLD.UNIT_MENUS[unitName].ctldRoot then
            pcall(function() DGSS_CTLD.createMenusForUnit(unit) end)
        end
        
        -- Create JTAC root menu for ALL players (regardless of aircraft type)
        if not DGSS_CTLD.UNIT_MENUS[unitName] or not DGSS_CTLD.UNIT_MENUS[unitName].jtacUniversalMenu then
            pcall(function() DGSS_CTLD.createUniversalJtacMenuForUnit(unit) end)
        end
        
        -- Update JTAC teams submenu if count changed
        if rebuildJtacMenus then
            if DGSS_CTLD.UNIT_MENUS[unitName] and DGSS_CTLD.UNIT_MENUS[unitName].jtacUniversalMenu then
                pcall(function() DGSS_CTLD.updateJtacTeamsMenu(unitName, groupId) end)
            end
        end
    end
    
    -- Process all player aircraft
    for _, group in ipairs(bluePlanes) do
        if group and group:isExist() then
            for _, unit in ipairs(group:getUnits()) do
                pcall(processPlayerUnit, unit)
            end
        end
    end
    
    for _, group in ipairs(blueHelos) do
        if group and group:isExist() then
            for _, unit in ipairs(group:getUnits()) do
                pcall(processPlayerUnit, unit)
            end
        end
    end

    -- Process Combined Arms ground units
    local blueGround = {}
    pcall(function()
        blueGround = coalition.getGroups(DGSS_CTLD.COALITION, Group.Category.GROUND) or {}
    end)

    for _, group in ipairs(blueGround) do
        if group and group:isExist() then
            for _, unit in ipairs(group:getUnits()) do
                pcall(processPlayerUnit, unit)
            end
        end
    end
    
    end)  -- end pcall body
    if not ok then
        env.error("[JTAC Menu Builder] Runtime error: " .. tostring(err))
    end
    -- Always reschedule, even if an error occurred above
    if mist and mist.scheduleFunction then
        mist.scheduleFunction(staticJtacMenuBuilder, {}, timer.getTime() + 15)
    else
        timer.scheduleFunction(staticJtacMenuBuilder, {}, timer.getTime() + 15)
    end
end

-- Start static menu builder (15s interval, first run at 10s)
env.info("[JTAC] Starting static JTAC menu builder")
if mist and mist.scheduleFunction then
    mist.scheduleFunction(staticJtacMenuBuilder, {}, timer.getTime() + 10)
else
    timer.scheduleFunction(staticJtacMenuBuilder, {}, timer.getTime() + 10)
end

----------------------------------------------------------------
-- NASAMS CRATE SYSTEM
-- 5 component crates are spawned in CTLD zones, then
-- sling-loaded one-at-a-time by helicopters or bulk-loaded
-- into a C-130J (up to 5).  Once all 5 crates are on the
-- ground within the assembly radius of each other, any player
-- can use CTLD > NASAMS Crates > Assemble NASAMS Site to
-- build the full SAM battery.
----------------------------------------------------------------

DGSS_CTLD.NASAMS_CRATES        = {}   -- crateName -> { pos = {x, z} }
DGSS_CTLD.AIRCRAFT_CRATES      = {}   -- unitName  -> list of crateNames (carried)
DGSS_CTLD.NASAMS_CRATE_COUNTER = 0    -- unique crate name counter

DGSS_CTLD.NASAMS_CFG = {
    maxCrates      = 5,        -- crates required to build one site
    assemblyRadius = 200,      -- metres: all crates must be within this of the centroid
    pickupRadius   = 75,       -- metres horizontal for aircraft pick-up
    heloMaxCrates  = 1,        -- helicopters carry 1 (sling-load style)
    c130MaxCrates  = 5,        -- C-130J carries all 5
    -- Static object descriptor (mirrors CTLD reference implementation)
    staticType     = "container_cargo",    -- valid DCS sling-loadable cargo type
    staticCategory = "Cargos",             -- plural required for canCargo objects
    staticShape    = "bw_container_cargo", -- shape string used by CTLD
    staticMass     = 2000,                 -- kg (liftable by Mi-8 / CH-47F)
    assembleKey    = "NASAMS Site Full",   -- VEHICLE_TEMPLATES key to build
}

-- Count crates sitting on the ground (not carried)
local function nasamsCrateCount()
    local n = 0
    for _ in pairs(DGSS_CTLD.NASAMS_CRATES) do n = n + 1 end
    return n
end

-- Count crates currently in transport
local function nasamsCarriedCount()
    local n = 0
    for _, list in pairs(DGSS_CTLD.AIRCRAFT_CRATES) do n = n + #list end
    return n
end

-- Returns "helo", "c130", or nil depending on aircraft type
local function nasamsCarrierKind(unit)
    if not unit or not unit:isExist() then return nil end
    local t = unit:getTypeName()
    if t == "C-130J-30" then return "c130" end
    if DGSS_CTLD.VALID_TROOP_TRANSPORT[t] then return "helo" end
    return nil
end

-- Silent assembly check – returns true when all 5 crates are within
-- assemblyRadius of their centroid.  No side effects.
local function nasamsIsReady()
    local cfg = DGSS_CTLD.NASAMS_CFG
    if nasamsCrateCount() < cfg.maxCrates then return false end

    local positions = {}
    for _, data in pairs(DGSS_CTLD.NASAMS_CRATES) do
        table.insert(positions, data.pos)
    end

    -- Compute centroid
    local sx, sz = 0, 0
    for _, p in ipairs(positions) do sx = sx + p.x; sz = sz + p.z end
    local centroid = { x = sx / #positions, z = sz / #positions }

    local rSq = cfg.assemblyRadius * cfg.assemblyRadius
    for _, p in ipairs(positions) do
        if DGSS_CTLD.sqrDist(p, centroid) > rSq then return false end
    end
    return true
end

-- Spawn one NASAMS component crate near unit (must be in a CTLD zone)
-- Spawn `count` NASAMS component crates around the calling aircraft.
-- Each crate is offset in a different compass direction so they don't overlap.
function DGSS_CTLD.spawnNASAMSCrate(unit, count)
    if not unit or not unit:isExist() then return end
    count = math.max(1, math.min(count or 1, 5))  -- clamp 1-5
    local pos = unit:getPoint()

    if not DGSS_CTLD.isInsideAnyCTLDZone(pos) then
        trigger.action.outTextForUnit(unit:getID(),
            "Must be inside a CTLD zone to spawn NASAMS crates!", 5)
        return
    end

    local cfg = DGSS_CTLD.NASAMS_CFG
    local spawned = 0

    for i = 1, count do
        -- Distribute crates evenly around the aircraft within 50 m
        local angle = ((i - 1) / math.max(count, 1)) * 2 * math.pi
        local radius = 20  -- fixed 20 m from aircraft, well inside 50 m
        local cx = pos.x + radius * math.cos(angle)
        local cz = pos.z + radius * math.sin(angle)

        DGSS_CTLD.NASAMS_CRATE_COUNTER = DGSS_CTLD.NASAMS_CRATE_COUNTER + 1
        local crateName = string.format("NASAMS_CRATE_%04d", DGSS_CTLD.NASAMS_CRATE_COUNTER)

        -- Build the static descriptor the same way CTLD does
        local crateDesc = {
            ["category"]   = cfg.staticCategory,
            ["shape_name"] = cfg.staticShape,
            ["type"]       = cfg.staticType,
            ["canCargo"]   = true,
            ["mass"]       = cfg.staticMass,
            ["name"]       = crateName,
            ["x"]          = cx,
            ["y"]          = cz,   -- mist/DCS static: y = world-Z (northing)
            ["heading"]    = 0,
            ["country"]    = DGSS_CTLD.COUNTRY,
        }

        local ok = false
        if mist and mist.dynAddStatic then
            -- Preferred: MIST handles cargo objects reliably
            ok = pcall(function() mist.dynAddStatic(crateDesc) end)
        end
        if not ok then
            -- Fallback: coalition API (less reliable for cargo types but worth trying)
            ok = pcall(function()
                coalition.addStaticObject(DGSS_CTLD.COUNTRY, crateDesc)
            end)
        end

        if ok and StaticObject.getByName(crateName) then
            DGSS_CTLD.NASAMS_CRATES[crateName] = { pos = { x = cx, z = cz } }
            spawned = spawned + 1
            env.info("[NASAMS Crates] Spawned " .. crateName .. " at (" .. math.floor(cx) .. ", " .. math.floor(cz) .. ")")
        else
            env.warning("[NASAMS Crates] Failed to spawn static object: " .. crateName)
        end
    end

    if spawned > 0 then
        trigger.action.outTextForUnit(unit:getID(),
            string.format("%d NASAMS crate(s) spawned near your position (%d on field).\n"
                .. "All %d required crates must be within %d m of each other to assemble.",
                spawned, nasamsCrateCount(), cfg.maxCrates, cfg.assemblyRadius), 8)
    else
        trigger.action.outTextForUnit(unit:getID(), "Failed to spawn NASAMS crates! Check server logs.", 5)
    end
end

-- Pick up the nearest NASAMS crate from the ground
function DGSS_CTLD.pickupNASAMSCrate(unit)
    if not unit or not unit:isExist() then return end

    local kind = nasamsCarrierKind(unit)
    if not kind then
        trigger.action.outTextForUnit(unit:getID(),
            "This aircraft cannot transport NASAMS crates!", 5)
        return
    end

    local condOk, condMsg = DGSS_CTLD.checkLoadUnloadConditions(unit, true)
    if not condOk then
        trigger.action.outTextForUnit(unit:getID(), condMsg, 6)
        return
    end

    local cfg      = DGSS_CTLD.NASAMS_CFG
    local unitName = unit:getName()
    local maxCarry = (kind == "c130") and cfg.c130MaxCrates or cfg.heloMaxCrates
    local carrying = #(DGSS_CTLD.AIRCRAFT_CRATES[unitName] or {})

    if carrying >= maxCarry then
        trigger.action.outTextForUnit(unit:getID(),
            string.format("Crate capacity full! (%d/%d)", carrying, maxCarry), 5)
        return
    end

    local pos    = unit:getPoint()
    local rSq    = cfg.pickupRadius * cfg.pickupRadius
    local bestSq = rSq + 1
    local bestName = nil

    for crateName, data in pairs(DGSS_CTLD.NASAMS_CRATES) do
        -- Verify the static object still exists in world
        local exists = false
        pcall(function()
            local s = StaticObject.getByName(crateName)
            exists = s ~= nil and s:isExist()
        end)
        if exists then
            local dSq = DGSS_CTLD.sqrDist(pos, { x = data.pos.x, z = data.pos.z })
            if dSq < bestSq then bestSq = dSq; bestName = crateName end
        else
            DGSS_CTLD.NASAMS_CRATES[crateName] = nil  -- prune stale entry
        end
    end

    if not bestName then
        trigger.action.outTextForUnit(unit:getID(),
            string.format("No NASAMS crate within %d m!", cfg.pickupRadius), 5)
        return
    end

    -- Destroy static, move to aircraft inventory
    pcall(function()
        local s = StaticObject.getByName(bestName)
        if s and s:isExist() then s:destroy() end
    end)
    DGSS_CTLD.NASAMS_CRATES[bestName] = nil

    if not DGSS_CTLD.AIRCRAFT_CRATES[unitName] then
        DGSS_CTLD.AIRCRAFT_CRATES[unitName] = {}
    end
    table.insert(DGSS_CTLD.AIRCRAFT_CRATES[unitName], bestName)

    trigger.action.outTextForUnit(unit:getID(),
        string.format("NASAMS crate loaded: %s  (%d/%d carrying).",
            bestName, carrying + 1, maxCarry), 6)
    env.info("[NASAMS Crates] " .. unitName .. " picked up " .. bestName)
end

-- Drop one NASAMS crate at the aircraft's current position
function DGSS_CTLD.dropNASAMSCrate(unit)
    if not unit or not unit:isExist() then return end

    local unitName = unit:getName()
    local list = DGSS_CTLD.AIRCRAFT_CRATES[unitName]
    if not list or #list == 0 then
        trigger.action.outTextForUnit(unit:getID(), "No NASAMS crates onboard!", 5)
        return
    end

    local condOk, condMsg = DGSS_CTLD.checkLoadUnloadConditions(unit, false)
    if not condOk then
        trigger.action.outTextForUnit(unit:getID(), condMsg, 6)
        return
    end

    local pos       = unit:getPoint()
    local cfg       = DGSS_CTLD.NASAMS_CFG
    local crateName = table.remove(list)             -- take last crate in list
    if #list == 0 then DGSS_CTLD.AIRCRAFT_CRATES[unitName] = nil end

    local dx = pos.x + math.random(-8, 8)
    local dz = pos.z + math.random(-8, 8)

    local crateDesc = {
        ["category"]   = cfg.staticCategory,
        ["shape_name"] = cfg.staticShape,
        ["type"]       = cfg.staticType,
        ["canCargo"]   = true,
        ["mass"]       = cfg.staticMass,
        ["name"]       = crateName,
        ["x"]          = dx,
        ["y"]          = dz,
        ["heading"]    = 0,
        ["country"]    = DGSS_CTLD.COUNTRY,
    }
    local dropOk = false
    if mist and mist.dynAddStatic then
        dropOk = pcall(function() mist.dynAddStatic(crateDesc) end)
    end
    if not dropOk then
        dropOk = pcall(function() coalition.addStaticObject(DGSS_CTLD.COUNTRY, crateDesc) end)
    end
    DGSS_CTLD.NASAMS_CRATES[crateName] = { pos = { x = dx, z = dz } }

    local onField = nasamsCrateCount()
    trigger.action.outTextForUnit(unit:getID(),
        string.format("NASAMS crate dropped: %s  (%d/%d on field).",
            crateName, onField, cfg.maxCrates), 6)
    env.info("[NASAMS Crates] " .. unitName .. " dropped " .. crateName)

    -- Announce to all blue players if assembly is now possible
    if onField >= cfg.maxCrates and nasamsIsReady() then
        trigger.action.outTextForCoalition(coalition.side.BLUE,
            string.format(
                "All %d NASAMS crates are within %.0f m of each other!\n" ..
                "Use CTLD > NASAMS Crates > Assemble NASAMS Site to build the battery.",
                cfg.maxCrates, cfg.assemblyRadius), 15)
    end
end

-- Public assembly-status check with coalition announcement
function DGSS_CTLD.checkNASAMSReady()
    local cfg = DGSS_CTLD.NASAMS_CFG
    if nasamsIsReady() then
        trigger.action.outTextForCoalition(coalition.side.BLUE,
            string.format(
                "All %d NASAMS crates are within %.0f m!\n" ..
                "Use CTLD > NASAMS Crates > Assemble NASAMS Site.",
                cfg.maxCrates, cfg.assemblyRadius), 12)
        return true
    end
    trigger.action.outTextForCoalition(coalition.side.BLUE,
        string.format(
            "NASAMS not assembly-ready.  On field: %d/%d  In transit: %d.\n" ..
            "All %d crates must be within %.0f m of each other.",
            nasamsCrateCount(), cfg.maxCrates, nasamsCarriedCount(),
            cfg.maxCrates, cfg.assemblyRadius), 8)
    return false
end

-- Destroy crates and spawn the full NASAMS SAM site group
function DGSS_CTLD.assembleNASAMSSite(unit)
    if not unit or not unit:isExist() then return end
    local cfg = DGSS_CTLD.NASAMS_CFG

    if not nasamsIsReady() then
        trigger.action.outTextForUnit(unit:getID(),
            string.format(
                "Cannot assemble NASAMS site!\n" ..
                "Need all %d crates on the ground and within %.0f m of each other.\n" ..
                "Crates on field: %d/%d   In transit: %d",
                cfg.maxCrates, cfg.assemblyRadius,
                nasamsCrateCount(), cfg.maxCrates, nasamsCarriedCount()), 10)
        return
    end

    -- Compute centroid of all crate positions for group spawn
    local sx, sz, n = 0, 0, 0
    for _, data in pairs(DGSS_CTLD.NASAMS_CRATES) do
        sx = sx + data.pos.x; sz = sz + data.pos.z; n = n + 1
    end
    local cx, cz = sx / n, sz / n

    -- Destroy all crate static objects
    for crateName in pairs(DGSS_CTLD.NASAMS_CRATES) do
        pcall(function()
            local s = StaticObject.getByName(crateName)
            if s and s:isExist() then s:destroy() end
        end)
    end
    DGSS_CTLD.NASAMS_CRATES   = {}
    DGSS_CTLD.AIRCRAFT_CRATES = {}  -- safety: clear any in-transit crates too

    -- Retrieve NASAMS template
    local template = DGSS_CTLD.VEHICLE_TEMPLATES[cfg.assembleKey]
    if not template then
        trigger.action.outTextForUnit(unit:getID(),
            "ERROR: NASAMS template '" .. cfg.assembleKey .. "' not found in VEHICLE_TEMPLATES!", 5)
        env.warning("[NASAMS] assembleKey '" .. cfg.assembleKey .. "' missing from VEHICLE_TEMPLATES")
        return
    end

    -- Lay out units in a formation: C2 + Radar clustered at centre,
    -- 5 launchers fanned around them.
    local groupName = DGSS_CTLD.generateGroupName("BLUE_SAM_NASAMS_SITE")
    local unitCount = #template.units
    local dcsUnits  = {}
    for i, uType in ipairs(template.units) do
        local angle  = (i - 1) * (2 * math.pi / unitCount)
        local spread = (i <= 2) and 25 or 80   -- C2 + Radar close in, launchers in outer ring
        table.insert(dcsUnits, {
            type    = uType,
            x       = cx + spread * math.cos(angle),
            y       = cz + spread * math.sin(angle),
            heading = math.random() * 6.28,
            skill   = "Excellent",
        })
    end

    local group = coalition.addGroup(
        DGSS_CTLD.COUNTRY, Group.Category.GROUND, { name = groupName, units = dcsUnits })

    if group then
        DGSS_CTLD.SPAWNED_GROUPS[groupName] = {
            lastActive   = timer.getTime(),
            kind         = "vehicle",
            templateName = cfg.assembleKey,
            id           = groupName,
            count        = unitCount,
            spawnedBy    = unit:getPlayerName(),
        }
        local pName = unit:getPlayerName()
        if pName then
            DGSS_CTLD.SPAWNED_BY_PLAYER[pName] = DGSS_CTLD.SPAWNED_BY_PLAYER[pName] or {}
            table.insert(DGSS_CTLD.SPAWNED_BY_PLAYER[pName], groupName)
        end
        trigger.action.outTextForCoalition(coalition.side.BLUE,
            "NASAMS SAM Site assembled and operational!\nGroup: " .. groupName, 15)
        env.info("[NASAMS] Site assembled: " .. groupName)
    else
        trigger.action.outTextForUnit(unit:getID(),
            "Failed to spawn NASAMS site group! Check the server logs.", 5)
        env.warning("[NASAMS] Failed to spawn group: " .. groupName)
    end
end

-- NASAMS crate status broadcast
function DGSS_CTLD.nasamsStatus()
    local cfg       = DGSS_CTLD.NASAMS_CFG
    local onField   = nasamsCrateCount()
    local inTransit = nasamsCarriedCount()
    local readyTxt  = nasamsIsReady()
        and "YES – use \"Assemble NASAMS Site\"!"
        or  "NO"
    trigger.action.outText(
        string.format(
            "=== NASAMS Crate Status ===\n" ..
            "On field   : %d / %d\n" ..
            "In transit : %d\n" ..
            "Assembly ready: %s\n" ..
            "(All crates must be within %.0f m of centroid)",
            onField, cfg.maxCrates, inTransit, readyTxt, cfg.assemblyRadius),
        12)
end

----------------------------------------------------------------
-- END NASAMS CRATE SYSTEM
----------------------------------------------------------------

----------------------------------------------------------------
-- CLEANUP LOOP (UNIT MENUS FOR DISCONNECTED PLAYERS)
----------------------------------------------------------------

-- Cleanup UNIT_MENUS for disconnected players
local function cleanupUnitMenus_CTLD()
    local toRemove = {}
    
    for unitName, menuData in pairs(DGSS_CTLD.UNIT_MENUS) do
        local unit = Unit.getByName(unitName)
        if not unit or not unit:isExist() then
            -- Unit no longer exists - remove menu entries
            pcall(function()
                if menuData.ctldMenu then
                    missionCommands.removeItem(menuData.ctldMenu)
                end
                if menuData.jtacUniversalMenu then
                    missionCommands.removeItem(menuData.jtacUniversalMenu)
                end
            end)
            table.insert(toRemove, unitName)
        end
    end
    
    for _, unitName in ipairs(toRemove) do
        DGSS_CTLD.UNIT_MENUS[unitName] = nil
    end
    
    if #toRemove > 0 then
        env.info("[DGSS_CTLD] Menu cleanup: Removed " .. #toRemove .. " menus for disconnected players")
    end
    
    -- Schedule next cleanup
    if mist and mist.scheduleFunction then
        mist.scheduleFunction(cleanupUnitMenus_CTLD, {}, timer.getTime() + 120)
    else
        timer.scheduleFunction(cleanupUnitMenus_CTLD, {}, timer.getTime() + 120)
    end
end

-- Start UNIT_MENUS cleanup loop (every 2 minutes)
if mist and mist.scheduleFunction then
    mist.scheduleFunction(cleanupUnitMenus_CTLD, {}, timer.getTime() + 120)
else
    timer.scheduleFunction(cleanupUnitMenus_CTLD, {}, timer.getTime() + 120)
end

----------------------------------------------------------------
-- CLEANUP LOOP (CTLD SPAWNED GROUPS)
----------------------------------------------------------------

DGSS_CTLD.CLEANUP = {
    enableGroupCleanup = true,
    idleTimeSeconds    = 1800,
}

local function cleanupSpawnedGroups_CTLD()
    if not DGSS_CTLD.CLEANUP.enableGroupCleanup then
        if mist and mist.scheduleFunction then
            mist.scheduleFunction(cleanupSpawnedGroups_CTLD, {}, timer.getTime() + 300)
        else
            timer.scheduleFunction(cleanupSpawnedGroups_CTLD, {}, timer.getTime() + 300)
        end
        return
    end

    local now  = timer.getTime()
    local idle = DGSS_CTLD.CLEANUP.idleTimeSeconds or 1800

    for groupName, data in pairs(DGSS_CTLD.SPAWNED_GROUPS) do
        local g = Group.getByName(groupName)
        if not g or not g:isExist() then
            DGSS_CTLD.SPAWNED_GROUPS[groupName] = nil
            -- Clean up player tracking
            if data and data.spawnedBy then
                local playerGroups = DGSS_CTLD.SPAWNED_BY_PLAYER[data.spawnedBy] or {}
                for i, name in ipairs(playerGroups) do
                    if name == groupName then
                        table.remove(playerGroups, i)
                        break
                    end
                end
            end
        else
            -- Only clean up if the group is DEAD, not based on idle time
            local isAlive = false
            local units = g:getUnits()
            if units and #units > 0 then
                for _, u in ipairs(units) do
                    if u and u:isExist() and u:getLife() and u:getLife() > 0 then
                        isAlive = true
                        break
                    end
                end
            end
            
            if not isAlive then
                env.info("[DGSS_CTLD] Cleaning up dead spawned group: " .. groupName)
                g:destroy()
                DGSS_CTLD.SPAWNED_GROUPS[groupName] = nil
                -- Clean up player tracking
                if data.spawnedBy then
                    local playerGroups = DGSS_CTLD.SPAWNED_BY_PLAYER[data.spawnedBy] or {}
                    for i, name in ipairs(playerGroups) do
                        if name == groupName then
                            table.remove(playerGroups, i)
                            break
                        end
                    end
                end
            end
        end
    end

    if mist and mist.scheduleFunction then
        mist.scheduleFunction(cleanupSpawnedGroups_CTLD, {}, timer.getTime() + 600)
    else
        timer.scheduleFunction(cleanupSpawnedGroups_CTLD, {}, timer.getTime() + 600)
    end
end

-- Start initial cleanup loop
if mist and mist.scheduleFunction then
    mist.scheduleFunction(cleanupSpawnedGroups_CTLD, {}, timer.getTime() + 600)
else
    timer.scheduleFunction(cleanupSpawnedGroups_CTLD, {}, timer.getTime() + 600)
end

----------------------------------------------------------------
-- FINAL INITIALIZATION & COMPATIBILITY CHECK
----------------------------------------------------------------

local loadStatus = "[DGSS] CTLD + JTAC System v3.5 - FULLY AUTONOMOUS\n"
loadStatus = loadStatus .. "================================================================\n"

-- Check DCS core APIs
local dcsOK = true
if not coalition or not Group or not Unit or not trigger then
    loadStatus = loadStatus .. "âœ— ERROR: Core DCS APIs not available\n"
    dcsOK = false
else
    loadStatus = loadStatus .. "âœ“ DCS Core APIs available\n"
end

-- Check MIST library
if not mist then
    loadStatus = loadStatus .. "âš  WARNING: MIST not found - using timer.scheduleFunction (slower)\n"
else
    local mistVersion = mist.version or "unknown"
    loadStatus = loadStatus .. string.format("âœ“ MIST library detected (v%s)\n", mistVersion)
end

-- Check CTLD library
if not ctld or type(ctld) ~= 'table' then
    loadStatus = loadStatus .. "âš  WARNING: CTLD library not found - laser may be fallback only\n"
else
    loadStatus = loadStatus .. "âœ“ CTLD library detected (laser supported)\n"
end

-- Check JTAC_REGISTRY integration
if not DGSS_CTLD or not DGSS_CTLD.JTAC_REGISTRY then
    loadStatus = loadStatus .. "âœ— ERROR: JTAC_REGISTRY not initialized\n"
    dcsOK = false
else
    loadStatus = loadStatus .. "âœ“ JTAC_REGISTRY initialized (AUTONOMOUS TARGETING)\n"
end

-- Check scan radius
if not SCAN_RADIUS then
    loadStatus = loadStatus .. "âœ— ERROR: SCAN_RADIUS not initialized\n"
    dcsOK = false
else
    loadStatus = loadStatus .. string.format("âœ“ Auto-scan enabled: %d meters (%.1f km)\n", SCAN_RADIUS, SCAN_RADIUS/1000)
end

-- Show hard limits
loadStatus = loadStatus .. "================================================================\n"
loadStatus = loadStatus .. string.format("âœ“ Hard Limits - Teams: %d | Vehicles: %d\n", 
    DGSS_CTLD.MAX_JTAC_TEAMS, DGSS_CTLD.MAX_JTAC_VEHICLES)

-- Show system capabilities
loadStatus = loadStatus .. "================================================================\n"
loadStatus = loadStatus .. "FEATURES ENABLED:\n"
loadStatus = loadStatus .. "âœ“ Autonomous JTAC target acquisition & lasing\n"
loadStatus = loadStatus .. "âœ“ Dynamic enemy detection in scan zones\n"
loadStatus = loadStatus .. "âœ“ Real-time laser code assignment\n"
loadStatus = loadStatus .. "âœ“ Automatic 9-line callout generation\n"
loadStatus = loadStatus .. "âœ“ Player-controlled target selection (manual override)\n"
loadStatus = loadStatus .. "âœ“ Troop/vehicle spawn & transport\n"
loadStatus = loadStatus .. "âœ“ Performance-optimized menu polling (3s interval)\n"
loadStatus = loadStatus .. "âœ“ System status monitoring (60s intervals)\n"

-- Final status
loadStatus = loadStatus .. "================================================================\n"
if dcsOK then
    loadStatus = loadStatus .. "âœ“ SYSTEM FULLY OPERATIONAL - All systems go!\n"
else
    loadStatus = loadStatus .. "âš  SYSTEM LOADED WITH WARNINGS - Check logs\n"
end

pcall(function() trigger.action.outText(loadStatus, 15) end)
env.info("[DGSS] CTLD + JTAC System v3.5 initialization complete - AUTONOMOUS MODE ACTIVE")
DGSS_CTLD.logSystemStatus()

-- Force update of all JTAC menus for all players
function DGSS_CTLD.updateAllJtacMenus()
    if not DGSS_CTLD.UNIT_MENUS then return end
    for unitName, menus in pairs(DGSS_CTLD.UNIT_MENUS) do
        local unit = Unit.getByName(unitName)
        if unit and unit:isExist() then
            DGSS_CTLD.createUniversalJtacMenuForUnit(unit)
        end
    end
end












