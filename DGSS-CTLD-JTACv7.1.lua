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
        env.info(string.format("[DGSS_CTLD] Preparing to spawn unit #%d: type='%s' at (%.1f, %.1f)", i, unitType, position.x + (i-1)*3, position.z))
    end

    local groupData = { name = groupName, units = units }
    env.info("[DGSS_CTLD] Spawning group with data: " .. (groupName or "nil") .. " | Template: " .. (templateName or "nil") .. " | Kind: " .. (kind or "nil"))
    env.info("[DGSS_CTLD] Group table: " .. (require and require('lfs') and 'see log' or 'table output suppressed'))
    -- Print the groupData table in a readable way (if possible)
    if type(groupData) == 'table' then
        for idx, u in ipairs(groupData.units) do
            env.info(string.format("[DGSS_CTLD] Unit %d: type=%s x=%.1f y=%.1f heading=%.2f", idx, u.type, u.x, u.y, u.heading))
        end
    end

    local group = coalition.addGroup(
        countryId,
        Group.Category.GROUND,
        groupData
    )

    if group then
        env.info("[DGSS_CTLD] Spawned group: " .. groupName)
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

SCAN_RADIUS = 18520  -- meters (10 nautical miles, global for DGSS_CTLD access)

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

-- Find all enemies within scan radius and return sorted list (with line-of-sight check)
local function findAllNearbyEnemies(jtacUnit, cachedRedGroups)
    if not jtacUnit or not jtacUnit:isExist() then
        env.warning("[JTAC SCAN] jtacUnit invalid or doesn't exist")
        return {}
    end
    
    local pos = jtacUnit:getPoint()
    if not pos then 
        env.warning("[JTAC SCAN] jtacUnit position invalid")
        return {} 
    end

    -- JTAC eye position (2m above unit for better visibility)
    local jtacEyePos = {x = pos.x, y = pos.y + 2.0, z = pos.z}

    local enemies = {}
    local maxDistSq = SCAN_RADIUS * SCAN_RADIUS

    -- Use cached red groups (passed from jtacUpdateLoop)
    local redGroups = cachedRedGroups or {}

    local unitCount = 0
    local losChecked = 0
    local losBlocked = 0
    
    for _, g in ipairs(redGroups) do
        if g and g:isExist() then
            local groupUnits = g:getUnits()
            local groupInRange = false
            local closestDistSq = nil
            local closestVisibleUnit = nil
            
            for _, u in ipairs(groupUnits) do
                if u and u:isExist() then
                    unitCount = unitCount + 1
                    local p = u:getPoint()
                    if p then
                        local dx = p.x - pos.x
                        local dz = p.z - pos.z
                        local distSq = dx*dx + dz*dz  -- Horizontal distance only, ignore altitude
                        
                        if distSq <= maxDistSq then
                            -- Distance check passed - now check line of sight
                            local targetPos = {x = p.x, y = p.y + 1.0, z = p.z}  -- Target center mass (1m above ground)
                            local hasLOS = false
                            
                            losChecked = losChecked + 1
                            
                            -- Check if JTAC can see the target (no terrain blocking)
                            if land and land.isVisible then
                                hasLOS = pcall(function()
                                    return land.isVisible(jtacEyePos, targetPos)
                                end) and land.isVisible(jtacEyePos, targetPos) or false
                            else
                                -- Fallback: assume visible if land.isVisible not available
                                hasLOS = true
                            end
                            
                            if hasLOS then
                                groupInRange = true
                                if not closestDistSq or distSq < closestDistSq then
                                    closestDistSq = distSq
                                    closestVisibleUnit = u
                                end
                            else
                                losBlocked = losBlocked + 1
                            end
                        end
                    end
                end
            end
            
            if groupInRange and closestVisibleUnit then
                -- Add the group as a targetable enemy group (only if at least one unit is visible)
                -- Get first visible unit's type name for display
                local typeName = "Unknown"
                pcall(function() typeName = closestVisibleUnit:getTypeName() end)
                
                table.insert(enemies, {
                    group = g,
                    groupName = g:getName(),
                    units = groupUnits,
                    closestDistSq = closestDistSq,
                    closestDist = math.sqrt(closestDistSq or 0),
                    typeName = typeName,
                    dist = math.sqrt(closestDistSq or 0),
                })
            end
        end
    end

    if losChecked > 0 then
        env.info(string.format("[JTAC SCAN] LOS Check: %d checked, %d visible, %d blocked by terrain", 
            losChecked, losChecked - losBlocked, losBlocked))
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
    
    if success then
        local mgrsStr, latLonStr = formatCoordinates(tgtPos)
        env.info(string.format(
            "[JTAC LASE] %s designated %s at %s with code %d",
            jtacName, targetTypeName, mgrsStr, jtacData.laser
        ))
    else
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
    
    env.info(string.format(
        "[CTLD] Laser created: %s | Code: %d | Target: (%.0f, %.0f, %.0f)",
        jtacName or "unknown", laserCode, targetPos.x, targetPos.y, targetPos.z
    ))
    
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
    env.info(string.format("[CTLD] Laser destroyed: %s", jtacName or "unknown"))
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

-- Main JTAC update loop - runs every 8 seconds for all active JTACs
local function jtacUpdateLoop()
    if not DGSS_CTLD or not DGSS_CTLD.JTAC_REGISTRY then
        return
    end
    
    -- Cache coalition.getGroups() ONCE per cycle (not per-JTAC)
    local cachedRedGroups = {}
    pcall(function()
        cachedRedGroups = coalition.getGroups(coalition.side.RED, Group.Category.GROUND) or {}
    end)
    
    for groupName, data in pairs(DGSS_CTLD.JTAC_REGISTRY) do
        if data then
            local g = Group.getByName(groupName)
            if g and g:isExist() then
                local u = g:getUnit(1)
                if u and u:isExist() then
                    -- Refresh unit reference (critical after transport/unload)
                    data.lastKnownPosition = u:getPoint()
                    -- Autonomously lase nearest enemy (using cached red groups)
                    laseTarget(groupName, data, u, cachedRedGroups)
                else
                    -- Unit dead, unregister
                    DGSS_CTLD.JTAC_REGISTRY[groupName] = nil
                end
            else
                -- Group dead, unregister
                DGSS_CTLD.JTAC_REGISTRY[groupName] = nil
            end
        end
    end
end

-- Schedule JTAC update loop using proper MIST function
local function scheduleJtacLoop()
    jtacUpdateLoop()
    
    if mist and mist.scheduleFunction then
        mist.scheduleFunction(scheduleJtacLoop, {}, timer.getTime() + 8)
    else
        timer.scheduleFunction(scheduleJtacLoop, {}, timer.getTime() + 8)
    end
end

if mist and mist.scheduleFunction then
    mist.scheduleFunction(scheduleJtacLoop, {}, timer.getTime() + 8)
else
    timer.scheduleFunction(scheduleJtacLoop, {}, timer.getTime() + 8)
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
    { name = "KANDAHAR" },
    { name = "KABUL" },
    { name = "BAGRAM" },
    { name = "JALALABAD" },
    { name = "TARINKOT" },
    { name = "CHAGHCHARAN" },
    { name = "FOB_LONDON" },
    { name = "FOB_DALLAS" },
    { name = "FOB_PARIS" },
    { name = "FOB_WARSAW" },
    { name = "FOB_SALERNO" },
    { name = "FOB_URGOON" },
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

    ["MLRS"] = {
        namePrefix  = "MLRS",
        displayName = "MLRS Rocket System",
        category    = "Artillery",
        units = { "MLRS" }
    },

    ["MaxxPro_MRAP"] = {
        namePrefix  = "MaxxPro_MRAP",
        displayName = "APC MRAP MaxxPro",
        category    = "Armored",
        units = { "MaxxPro_MRAP" }
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

-- Convert DCS coordinates to simplified MGRS/lat-lon format
function DGSS_CTLD.coordinatesToMGRS(point)
    if not point then return "UNKNOWN" end
    
    -- Safely handle coordinate conversion
    local lat, lon = 0, 0
    pcall(function()
        -- DCS uses x,z for horizontal plane; simple conversion
        lat = (point.x or 0) / 111000  -- rough conversion to degrees
        lon = (point.z or 0) / 111000
    end)
    
    return string.format("%.2fÂ°N %.2fÂ°E", math.abs(lat), math.abs(lon))
end

-- Convert to Decimal Minutes format (DDÂ°MM.MMM'N/S, DDÂ°MM.MMM'E/W)
function DGSS_CTLD.coordinatesToDecimalMinutes(point)
    if not point then return "UNKNOWN" end
    
    local lat, lon = 0, 0
    pcall(function()
        lat = (point.x or 0) / 111000  -- rough conversion
        lon = (point.z or 0) / 111000
    end)
    
    -- Convert latitude
    local latDeg = math.floor(math.abs(lat))
    local latMin = (math.abs(lat) - latDeg) * 60
    local latDir = lat >= 0 and "N" or "S"
    
    -- Convert longitude
    local lonDeg = math.floor(math.abs(lon))
    local lonMin = (math.abs(lon) - lonDeg) * 60
    local lonDir = lon >= 0 and "E" or "W"
    
    return string.format("%02dÂ°%06.3f'%s %03dÂ°%06.3f'%s", latDeg, latMin, latDir, lonDeg, lonMin, lonDir)
end

-- Generate 9-line CAS callout with robust error handling
function DGSS_CTLD.generate9LineCallout(jtacName, targetUnit, jtacUnit)
    if not targetUnit or not jtacUnit then return nil end
    
    -- Safely get positions
    local jtacPos = pcall(function() return jtacUnit:getPoint() end) and jtacUnit:getPoint() or nil
    local targetPos = pcall(function() return targetUnit:getPoint() end) and targetUnit:getPoint() or nil
    
    if not jtacPos or not targetPos then return nil end
    
    -- Calculate bearing and distance with safe math
    local dx = (targetPos.x or 0) - (jtacPos.x or 0)
    local dz = (targetPos.z or 0) - (jtacPos.z or 0)
    local distance = math.sqrt(dx*dx + dz*dz)
    local bearing = math.deg(math.atan2(dx, dz))
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
    
    -- Elevation with safety
    local elevation = math.floor((targetPos.y or 0))
    
    -- Get laser code safely
    local laserCode = 1688
    if DGSS_CTLD.JTAC_REGISTRY and DGSS_CTLD.JTAC_REGISTRY[jtacName] then
        laserCode = DGSS_CTLD.JTAC_REGISTRY[jtacName].laser or 1688
    end
    
    -- Build 9-line callout
    local callout = string.format(
        "[9-LINE CALLOUT] %s\n" ..
        "1. IP: CURRENT\n" ..
        "2. HEADING: %03d degrees\n" ..
        "3. DISTANCE: %.1f meters\n" ..
        "4. ELEVATION: %d meters\n" ..
        "5. TARGET: %s (%s)\n" ..
        "6. LOCATION: %s (MGRS)\n" ..
        "         or: %s (Dec Min)\n" ..
        "7. MARK: LASE - Code %d\n" ..
        "8. FRIENDLIES: CLEAR\n" ..
        "9. REMARKS: AUTO-DETECTED ENEMY",
        jtacName, bearing, distance, elevation, targetType, targetGroupName,
        DGSS_CTLD.coordinatesToMGRS(targetPos),
        DGSS_CTLD.coordinatesToDecimalMinutes(targetPos),
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
                    
                    output = output .. string.format(
                        "%d. %s\n   Units: %d | Laser: %d | Pos: (%.1f, %.1f)\n\n",
                        activeCount,
                        jtacGroupName,
                        unitCount,
                        laserCode,
                        pos.x,
                        pos.z
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
                        if g and g:isExist() then
                            status = "ACTIVE"
                        end

                        local jtac = DGSS_CTLD.JTAC_REGISTRY[teamNameCopy]
                        local laserCode = jtac and jtac.laser or 1688

                        trigger.action.outText(
                            string.format("[JTAC %s] Status: %s | Laser: %d",
                                teamNameCopy, status, laserCode),
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
                            local marker = (jtacData.targetIndex == i and jtacData.manualOverride) and "â–º" or " "
                            targetList = targetList .. string.format("%s%d. %s - %.0f m\n", marker, i, tgtData.typeName, tgtData.dist)
                        end
                        trigger.action.outText(targetList, 10)
                    end
                )

                -- Next Target
                missionCommands.addCommandForGroup(
                    groupId,
                    "Next Target (â†“)",
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
                    "Previous Target (â†‘)",
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
    
    -- Skip if CTLD menu already created
    if DGSS_CTLD.UNIT_MENUS[unitName].ctldRoot then
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
end
world.addEventHandler(PLAYER_LEAVE_HANDLER_CTLD)

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
    
    -- Create CTLD menus for valid transports (every cycle)
    -- Create JTAC menus only if JTAC count changed
    local rebuildJtacMenus = (currentJtacCount ~= DGSS_CTLD.LAST_MENU_JTAC_COUNT)
    
    if rebuildJtacMenus then
        DGSS_CTLD.LAST_MENU_JTAC_COUNT = currentJtacCount
        env.info("[Static Menu Builder] JTAC count changed to " .. currentJtacCount .. ", rebuilding menus")
    end
    
    -- Process all players
    for _, group in ipairs(bluePlanes) do
        if group and group:isExist() then
            for _, unit in ipairs(group:getUnits()) do
                if unit and unit:isExist() and unit:getPlayerName() then
                    local unitName = unit:getName()
                    local unitGroup = unit:getGroup()
                    if not unitGroup then
                        -- Skip if group not ready
                    else
                        local groupId = unitGroup:getID()
                    
                        -- Create CTLD menu for valid transports
                        if not DGSS_CTLD.UNIT_MENUS[unitName] or not DGSS_CTLD.UNIT_MENUS[unitName].ctldRoot then
                            pcall(function() DGSS_CTLD.createMenusForUnit(unit) end)
                        end
                    
                        -- Create JTAC menu for ALL players (regardless of aircraft type)
                        pcall(function() createJtacMenuForAllPlayers(unit) end)
                    
                        -- Update JTAC menu if count changed
                        if rebuildJtacMenus then
                            if DGSS_CTLD.UNIT_MENUS[unitName] and DGSS_CTLD.UNIT_MENUS[unitName].jtacUniversalMenu then
                                pcall(function() DGSS_CTLD.updateJtacTeamsMenu(unitName, groupId) end)
                            end
                        end
                    end
                end
            end
        end
    end
    
    for _, group in ipairs(blueHelos) do
        if group and group:isExist() then
            for _, unit in ipairs(group:getUnits()) do
                if unit and unit:isExist() and unit:getPlayerName() then
                    local unitName = unit:getName()
                    local unitGroup = unit:getGroup()
                    if not unitGroup then
                        -- Skip if group not ready
                    else
                        local groupId = unitGroup:getID()
                    
                        -- Create CTLD menu for valid transports
                        if not DGSS_CTLD.UNIT_MENUS[unitName] or not DGSS_CTLD.UNIT_MENUS[unitName].ctldRoot then
                            pcall(function() DGSS_CTLD.createMenusForUnit(unit) end)
                        end
                    
                        -- Create JTAC menu for ALL players (regardless of aircraft type)
                        pcall(function() createJtacMenuForAllPlayers(unit) end)
                    
                        -- Update JTAC menu if count changed
                        if rebuildJtacMenus then
                            if DGSS_CTLD.UNIT_MENUS[unitName] and DGSS_CTLD.UNIT_MENUS[unitName].jtacUniversalMenu then
                                pcall(function() DGSS_CTLD.updateJtacTeamsMenu(unitName, groupId) end)
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Schedule next rebuild
    if mist and mist.scheduleFunction then
        mist.scheduleFunction(staticJtacMenuBuilder, {}, timer.getTime() + 5)
    else
        timer.scheduleFunction(staticJtacMenuBuilder, {}, timer.getTime() + 5)
    end
end

-- Start static menu builder immediately (every 1 second)
env.info("[JTAC] Starting static JTAC menu builder")
if mist and mist.scheduleFunction then
    mist.scheduleFunction(staticJtacMenuBuilder, {}, timer.getTime() + 5)
else
    timer.scheduleFunction(staticJtacMenuBuilder, {}, timer.getTime() + 5)
end

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












