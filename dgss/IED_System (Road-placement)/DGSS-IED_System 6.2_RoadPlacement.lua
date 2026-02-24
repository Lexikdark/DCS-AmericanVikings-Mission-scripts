----------------------------------------------------------------
-- IED SYSTEM FOR DCS WORLD v6.2 - ROAD PLACEMENT EDITION
-- Places IEDs along roads within specified trigger zones
-- Automatically finds road networks and places IED props nearby
-- Explodes when convoy vehicle count reaches random threshold
----------------------------------------------------------------

DGSS_IED = {}

-- Forward declarations
local activateIEDsOnRoutes
local findAllRouteIEDPositions

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------

DGSS_IED.COALITION = coalition.side.BLUE          -- Coalition to trigger IEDs
DGSS_IED.DETECTION_RADIUS = 15                    -- Extra radius buffer for detection (meters)
DGSS_IED.CHECK_INTERVAL = 10                       -- Check every 5 seconds
DGSS_IED.RESET_TIME = 1800                        -- Time in seconds before exploded IED zone resets (30 minutes)
DGSS_IED.MAX_TRACKED_POSITIONS = 500              -- Maximum IED positions to track for spacing (prevents memory leak)
DGSS_IED.MAX_ACTIVE_IEDS = 75                     -- Maximum total IEDs active on map at any time
DGSS_IED.CLEANUP_INTERVAL = 3600                  -- Run maintenance cleanup every hour
DGSS_IED.ZONE_SPAWN_DELAY = 15                    -- Delay in seconds between spawning each zone

-- Road placement configuration
DGSS_IED.ROAD_PLACEMENT = {
    enabled = true,                    -- Enable road placement mode
    searchRadius = 25000,              -- Search for roads within this radius from zone center (meters) - REDUCED for performance
    roadOffsetMin = 8,                 -- Minimum offset from road edge (meters) - ensures off-road placement
    roadOffsetMax = 15,                -- Maximum offset from road edge (meters) - clearly beside road
    iedsPerZone = 2,                   -- Number of IEDs to place per zone (reduced for better spacing)
    minIEDSpacing = 2000,              -- Minimum distance between IEDs - 2km (half a grid square)
    roadSamplePoints = 6,              -- Number of points to sample when searching for roads - REDUCED for performance
    minPathLength = 7000,              -- Minimum road path length (meters) - filters for connecting roads
    routesPerBasePair = 2,             -- Number of different routes to try finding between each base pair - REDUCED to minimize stutters
    pointsPerRoute = 5,                -- Number of IED placement points to sample along each route - REDUCED for performance
    pathfindDelay = 1.5,               -- Delay between pathfinding calls (seconds) - INCREASED to reduce stutters
}

-- Auto-detect IED zones by name pattern (used as valid placement regions)
-- Any trigger zone containing this string will be used to validate IED placement
DGSS_IED.ZONE_NAME_PATTERN = "_IED_AREA"

-- This will be populated automatically at runtime
DGSS_IED.SPAWN_ZONES = {}

-- Base zones to pathfind between (uses BASE_EXCLUSION_ZONES as base list)
-- Script will automatically find routes between all pairs of these bases
DGSS_IED.USE_ROUTE_MODE = true  -- Set to false to use old zone-sampling mode

-- Base exclusion zones - IEDs will NOT spawn within these zones
-- Add trigger zones around your airbases/FOBs to prevent IED spawns
DGSS_IED.BASE_EXCLUSION_ZONES = {
    "KANDAHAR",
    "BAGRAM",
    "KABUL",
    "JALALABAD",
    "FOB_SALERNO",
    "FOB_LONDON",
    "FOB_PARIS",
    "FOB_DALLAS",
    "FOB_WARSAW",
    "FOB_URGOON",
    "TARINKOT",
    "CHAGHCHARAN",
    -- Add more base zone names as needed
}

-- Static object types (DCS type names)
DGSS_IED.STATICS = {
    Structure = "Oil Barrel",                        -- Oil barrel (Structure category)
    vehicles = {"P20_drivable", "VAZ Car"}           -- Vehicle names
}

-- Explosion settings
DGSS_IED.EXPLOSION = {
    power = 500,             -- Explosion power (kg TNT equivalent)
}

-- Insurgent spawn settings
DGSS_IED.INSURGENT_SPAWN = {
    enabled = true,           -- Set to false to disable insurgent spawns
    spawnChance = 0.40,       -- 40% chance to spawn insurgents when IED explodes
    minCount = 10,            -- Minimum number of insurgents
    maxCount = 15,            -- Maximum number of insurgents
    minDistance = 100,        -- Minimum spawn distance from zone (meters)
    maxDistance = 300,        -- Maximum spawn distance from zone (meters)
    unitTypes = {
        "Infantry AK Ins",
        "Soldier RPG",
        "Infantry AK ver2",
    },
    skill = "Average",
}

----------------------------------------------------------------
-- INTERNAL STATE
----------------------------------------------------------------

DGSS_IED.ACTIVE_IEDs = {}         -- Active IEDs { iedId = { pos, triggerCount, vehiclesSeen, barrel, vehicle, exploded, zoneName } }
DGSS_IED.SPAWN_COUNTER = 0        -- Counter for unique names
DGSS_IED.STATIC_TO_IED = {}       -- Map static name -> IED id for death tracking
DGSS_IED.INSURGENT_GROUPS = {}    -- Track spawned insurgent groups for cleanup
DGSS_IED.RESET_TIMERS = {}        -- Track scheduled reset timers by IED id
DGSS_IED.ROUTE_CACHE = {}         -- Cache calculated routes to avoid recalculation
DGSS_IED.PATHFIND_QUEUE = {}      -- Queue for async pathfinding
DGSS_IED.PATHFIND_IN_PROGRESS = false  -- Track if pathfinding is in progress
DGSS_IED.IED_POSITIONS = {}       -- Track all IED positions for spacing checks
-- Note: routeIEDPositions NOT stored globally to prevent memory leak - generated on-demand in activateIEDsOnRoutes()

----------------------------------------------------------------
-- UTILITY FUNCTIONS
----------------------------------------------------------------

local function log(msg)
    env.info("[IED-Road] " .. msg)
end

local function discoverIEDZones()
    local zones = {}
    local pattern = DGSS_IED.ZONE_NAME_PATTERN
    
    -- Scan all trigger zones in the mission
    if env.mission and env.mission.triggers and env.mission.triggers.zones then
        for _, zoneData in ipairs(env.mission.triggers.zones) do
            if zoneData.name and string.find(zoneData.name, pattern) then
                table.insert(zones, zoneData.name)
                log("Discovered IED zone: " .. zoneData.name)
            end
        end
    end
    
    -- Sort alphabetically for consistent ordering
    table.sort(zones)
    
    log("Auto-discovered " .. #zones .. " zones with pattern '" .. pattern .. "'")
    return zones
end

local function countActiveIEDs()
    local count = 0
    for _, data in pairs(DGSS_IED.ACTIVE_IEDs) do
        if not data.exploded then
            count = count + 1
        end
    end
    return count
end

local function _2dDist(p1, p2)
    if not p1 or not p2 or not p1.x or not p2.x or not p1.z or not p2.z then
        return nil
    end
    local dx = p1.x - p2.x
    local dz = p1.z - p2.z
    return math.sqrt(dx*dx + dz*dz)
end

local function getZone(zoneName)
    local zone = trigger.misc.getZone(zoneName)
    if not zone then return nil end
    return {
        name = zoneName,
        x = zone.point.x,
        z = zone.point.z,
        radius = zone.radius or 500,
    }
end

local function getCoordinateStrings(pos)
    local lat, lon = coord.LOtoLL({x = pos.x, y = pos.y or 0, z = pos.z})
    local mgrs = coord.LLtoMGRS(lat, lon)
    local mgrsStr = mgrs.UTMZone .. mgrs.MGRSDigraph .. " " .. 
                    string.format("%05d", mgrs.Easting) .. " " .. 
                    string.format("%05d", mgrs.Northing)
    return mgrsStr
end

local function isTooCloseToExistingIED(pos)
    local minSpacing = DGSS_IED.ROAD_PLACEMENT.minIEDSpacing
    
    -- Check against all previously placed IED positions (global across all zones)
    for _, existingPos in ipairs(DGSS_IED.IED_POSITIONS) do
        local dist = _2dDist(pos, existingPos)
        if dist and dist < minSpacing then
            log(string.format("Position rejected - only %.0fm from existing IED (need %dm)", dist, minSpacing))
            return true
        end
    end
    
    return false
end

local function isInExclusionZone(pos)
    for _, zoneName in ipairs(DGSS_IED.BASE_EXCLUSION_ZONES) do
        local zone = getZone(zoneName)
        if zone then
            local dist = _2dDist(pos, {x = zone.x, z = zone.z})
            if dist and dist <= zone.radius then
                return true, zoneName
            end
        end
    end
    return false, nil
end

----------------------------------------------------------------
-- ROAD FINDING - ROUTE-BASED MODE
----------------------------------------------------------------

-- Check if position is inside any _IED_AREA zone (valid placement region)
local function isInValidIEDZone(pos)
    for _, zoneName in ipairs(DGSS_IED.SPAWN_ZONES) do
        local zone = getZone(zoneName)
        if zone then
            local dist = _2dDist(pos, {x = zone.x, z = zone.z})
            if dist and dist <= zone.radius then
                return true, zoneName
            end
        end
    end
    return false, nil
end

-- Find road route between two bases with multiple intermediate waypoints for route diversity
-- routeNum: 1 = direct, 2+ = via multiple intermediate waypoints at different angles/distances
local function findRouteBetweenBases(baseFrom, baseTo, routeNum)
    local zoneFrom = getZone(baseFrom)
    local zoneTo = getZone(baseTo)
    
    if not zoneFrom or not zoneTo then
        log(string.format("Cannot find zones for route %s -> %s", baseFrom, baseTo))
        return nil
    end
    
    local fromX = zoneFrom.x
    local fromZ = zoneFrom.z
    local toX = zoneTo.x
    local toZ = zoneTo.z
    
    -- Route 1: Direct path
    if routeNum == 1 then
        log(string.format("Pathfinding DIRECT route %s -> %s", baseFrom, baseTo))
        
        local success, roadPath = pcall(function()
            return land.findPathOnRoads("roads", fromX, fromZ, toX, toZ)
        end)
        
        if success and roadPath and #roadPath > 0 then
            log(string.format("Found direct route %s -> %s with %d waypoints", baseFrom, baseTo, #roadPath))
            return roadPath
        else
            log(string.format("No direct route found %s -> %s", baseFrom, baseTo))
            return nil
        end
    end
    
    -- Routes 2+: Try multiple intermediate waypoints with varied offsets
    local dx = toX - fromX
    local dz = toZ - fromZ
    local directDistance = math.sqrt(dx*dx + dz*dz)
    
    -- Create waypoints at different positions along/perpendicular to the direct line
    local waypoints = {
        -- Route 2: 25% along path, offset right
        {alongRatio = 0.25, perpRatio = 0.4, side = 1},
        -- Route 3: 75% along path, offset left  
        {alongRatio = 0.75, perpRatio = 0.4, side = -1},
        -- Route 4: 40% along path, offset right (larger)
        {alongRatio = 0.4, perpRatio = 0.6, side = 1},
        -- Route 5: 60% along path, offset left (larger)
        {alongRatio = 0.6, perpRatio = 0.6, side = -1},
    }
    
    local waypointIdx = ((routeNum - 2) % #waypoints) + 1
    local wp = waypoints[waypointIdx]
    
    -- Calculate waypoint position
    local alongX = fromX + dx * wp.alongRatio
    local alongZ = fromZ + dz * wp.alongRatio
    
    local perpAngle = math.atan2(dz, dx) + math.pi / 2
    local offsetDist = directDistance * wp.perpRatio
    
    local waypointX = alongX + offsetDist * wp.side * math.cos(perpAngle)
    local waypointZ = alongZ + offsetDist * wp.side * math.sin(perpAngle)
    
    log(string.format("Pathfinding ALTERNATE route %d: %s -> waypoint(%.0f%% along, %.0f%% offset) -> %s", 
        routeNum, baseFrom, wp.alongRatio * 100, wp.perpRatio * 100, baseTo))
    
    -- Path from base A to intermediate waypoint
    local success1, roadPath1 = pcall(function()
        return land.findPathOnRoads("roads", fromX, fromZ, waypointX, waypointZ)
    end)
    
    -- Path from intermediate waypoint to base B
    local success2, roadPath2 = pcall(function()
        return land.findPathOnRoads("roads", waypointX, waypointZ, toX, toZ)
    end)
    
    -- Combine both segments into single route
    if success1 and roadPath1 and #roadPath1 > 0 and success2 and roadPath2 and #roadPath2 > 0 then
        local combinedPath = {}
        
        -- Add first segment
        for _, wp in ipairs(roadPath1) do
            table.insert(combinedPath, wp)
        end
        
        -- Add second segment
        for _, wp in ipairs(roadPath2) do
            table.insert(combinedPath, wp)
        end
        
        log(string.format("Found alternate route %d: %s -> %s with %d waypoints (via intermediate)", 
            routeNum, baseFrom, baseTo, #combinedPath))
        return combinedPath
    else
        log(string.format("No alternate route %d found %s -> %s - trying fallback", routeNum, baseFrom, baseTo))
        -- Fallback: return direct route if alternate fails
        local success, roadPath = pcall(function()
            return land.findPathOnRoads("roads", fromX, fromZ, toX, toZ)
        end)
        if success and roadPath and #roadPath > 0 then
            log(string.format("Using direct route as fallback for route %d", routeNum))
            return roadPath
        end
        return nil
    end
end

-- Find all routes between all base pairs and collect IED positions
-- Returns: table of {basePair = "BASE1 <-> BASE2", positions = {...}}
findAllRouteIEDPositions = function()
    local cfg = DGSS_IED.ROAD_PLACEMENT
    local basePairPositions = {}  -- Track positions per base pair
    local globalSampledPositions = {}  -- Track ALL sampled positions across all routes to prevent overlaps
    
    -- Get all base zones from exclusion list
    local bases = DGSS_IED.BASE_EXCLUSION_ZONES
    
    log(string.format("Finding routes between %d bases", #bases))
    
    -- Helper function to check if position is too close to any already sampled position
    local function isTooCloseToSampledPosition(pos)
        local minSpacing = cfg.minIEDSpacing
        for _, existingPos in ipairs(globalSampledPositions) do
            local dist = _2dDist(pos, existingPos)
            if dist and dist < minSpacing then
                return true
            end
        end
        return false
    end
    
    -- Helper function to process a base pair
    local function processBasePair(baseFrom, baseTo)
        local basePairName = baseFrom .. " <-> " .. baseTo
        
        log(string.format("Processing base pair: %s", basePairName))
        
        local pairPositions = {}
        
        -- Find multiple routes from cache (already calculated asynchronously)
        for routeNum = 1, cfg.routesPerBasePair do
            local cacheKey = baseFrom .. "->" .. baseTo .. "_R" .. routeNum
            local roadPath = DGSS_IED.ROUTE_CACHE[cacheKey]
            
            if roadPath and #roadPath >= 2 then
                -- Sample evenly spaced points along the route
                local pointsToSample = cfg.pointsPerRoute
                local step = math.max(1, math.floor(#roadPath / pointsToSample))
                
                local routePositions = 0
                for k = 1, #roadPath, step do
                    local waypoint = roadPath[k]
                    if waypoint and waypoint.x and waypoint.y then
                        local pos = {
                            x = waypoint.x,
                            z = waypoint.y,  -- DCS uses y for north-south
                        }
                        
                        -- Check if position is in a valid _IED_AREA zone
                        local inValidZone, zoneName = isInValidIEDZone(pos)
                        if inValidZone then
                            -- Check if in base exclusion zone
                            local inExclusion, exclusionZone = isInExclusionZone(pos)
                            if not inExclusion then
                                -- Check spacing from ALL previously sampled positions (prevents duplicates on shared roads)
                                if not isTooCloseToExistingIED(pos) and not isTooCloseToSampledPosition(pos) then
                                    table.insert(pairPositions, pos)
                                    table.insert(globalSampledPositions, pos)  -- Track globally
                                    routePositions = routePositions + 1
                                    log(string.format("Valid IED position on route %s Route %d in zone %s", basePairName, routeNum, zoneName))
                                end
                            end
                        end
                    end
                end
                
                log(string.format("Route %d for %s: found %d IED positions", routeNum, basePairName, routePositions))
            end
        end
        
        -- Store positions for this base pair
        if #pairPositions > 0 then
            table.insert(basePairPositions, {
                basePair = basePairName,
                positions = pairPositions
            })
            log(string.format("Base pair %s: Total %d unique positions across all routes", basePairName, #pairPositions))
        else
            log(string.format("WARNING: No positions found for base pair %s", basePairName))
        end
    end
    
    -- PRIORITY: Process Kabul, Bagram, and Jalalabad routes FIRST
    local priorityBases = {"KABUL", "BAGRAM", "JALALABAD"}
    local processedPairs = {}  -- Track which pairs we've already processed
    
    log("=== PRIORITY PHASE: Processing Kabul-Bagram-Jalalabad triangle ===")
    for i = 1, #priorityBases do
        for j = i + 1, #priorityBases do
            local baseFrom = priorityBases[i]
            local baseTo = priorityBases[j]
            processBasePair(baseFrom, baseTo)
            processedPairs[baseFrom .. "-" .. baseTo] = true
        end
    end
    
    -- Then process all remaining base pairs
    log("=== STANDARD PHASE: Processing remaining base pairs ===")
    for i = 1, #bases do
        for j = i + 1, #bases do
            local baseFrom = bases[i]
            local baseTo = bases[j]
            local pairKey = baseFrom .. "-" .. baseTo
            
            -- Skip if already processed in priority phase
            if not processedPairs[pairKey] then
                processBasePair(baseFrom, baseTo)
            end
        end
    end
    
    log(string.format("Found IED positions for %d base pairs (Total unique: %d)", #basePairPositions, #globalSampledPositions))
    return basePairPositions
end

----------------------------------------------------------------
-- OLD ZONE-SAMPLING MODE (LEGACY)
----------------------------------------------------------------

local function findRoadPositionsInZone(zone)
    local cfg = DGSS_IED.ROAD_PLACEMENT
    local roadPositions = {}
    
    log("Searching for roads in zone: " .. zone.name .. " (radius: " .. zone.radius .. "m)")
    
    -- Sample multiple points around the zone in a circular pattern with better distribution
    local numSamples = cfg.roadSamplePoints
    local searchRadius = math.min(zone.radius, cfg.searchRadius)
    
    -- Use multiple rings at different radii for better coverage
    local rings = {0.4, 0.7, 1.0}  -- Sample at 40%, 70%, and 100% of radius
    local samplesPerRing = math.floor(numSamples / #rings)
    local sampleIndex = 0
    
    for _, radiusRatio in ipairs(rings) do
        for i = 0, samplesPerRing - 1 do
            local angle = (i / samplesPerRing) * 2 * math.pi + (math.random() * 0.5)  -- Add random angle variation
            local dist = searchRadius * radiusRatio * (0.9 + 0.2 * math.random())  -- Small random variation
            
            local sampleX = zone.x + dist * math.cos(angle)
            local sampleZ = zone.z + dist * math.sin(angle)
            
            -- Try to find nearest road from this point
            local testPoint = {x = sampleX, y = 0, z = sampleZ}
            
            -- Use land.findPathOnRoads to detect roads
            -- Search from sample point to zone center
            local success, roadPath = pcall(function()
                return land.findPathOnRoads("roads", sampleX, sampleZ, zone.x, zone.z)
            end)
            
            if success and roadPath and #roadPath > 0 then
                -- Calculate total path length to filter for connecting roads
                local pathLength = 0
                for j = 1, #roadPath - 1 do
                    local p1 = roadPath[j]
                    local p2 = roadPath[j + 1]
                    if p1 and p2 and p1.x and p1.y and p2.x and p2.y then
                        local dx = p2.x - p1.x
                        local dy = p2.y - p1.y
                        pathLength = pathLength + math.sqrt(dx*dx + dy*dy)
                    end
                end
                
                -- Only use roads with sufficient path length (connecting roads/highways)
                if pathLength >= cfg.minPathLength then
                    -- Found a road - use the first point of the path as a road location
                    local roadPoint = roadPath[1]
                    if roadPoint and roadPoint.x and roadPoint.y then
                        local roadPos = {
                            x = roadPoint.x,
                            z = roadPoint.y,  -- DCS road path uses y for north-south
                        }
                        
                        -- Check if within zone
                        local distFromCenter = _2dDist(roadPos, {x = zone.x, z = zone.z})
                        if distFromCenter and distFromCenter <= zone.radius then
                            -- Check if in base exclusion zone
                            local inExclusion, exclusionZone = isInExclusionZone(roadPos)
                            if inExclusion then
                                log(string.format("Skipping position in exclusion zone: %s", exclusionZone))
                            -- Check spacing from existing IEDs
                            elseif not isTooCloseToExistingIED(roadPos) then
                                table.insert(roadPositions, roadPos)
                                log(string.format("Found road position in %s: x=%.0f, z=%.0f (path: %.0fm)", zone.name, roadPos.x, roadPos.z, pathLength))
                            else
                                log(string.format("Skipping position - too close to existing IED (min spacing: %dm)", DGSS_IED.ROAD_PLACEMENT.minIEDSpacing))
                            end
                        end
                    end
                else
                    log(string.format("Skipping short road path: %.0fm (need %dm) - likely side road", pathLength, cfg.minPathLength))
                end
            end
        end
    end
    
    log("Found " .. #roadPositions .. " suitable road positions in zone " .. zone.name)
    return roadPositions
end

----------------------------------------------------------------
-- STATIC SPAWNING
----------------------------------------------------------------

local function spawnStatic(typeName, x, z, heading, name)
    -- Validate inputs
    if not typeName or not x or not z or not name then
        log("ERROR: Invalid parameters for spawnStatic")
        return nil
    end
    
    local staticData = {
        ["type"] = typeName,
        ["x"] = x,
        ["y"] = z,  -- DCS uses y for north-south coordinate
        ["heading"] = heading or 0,
        ["name"] = name,
        ["hidden"] = true,  -- Invisible to AI detection
    }
    
    -- Try to spawn as CJTF Red
    local countryId = 101  -- CJTF_RED default ID
    pcall(function()
        if country and country.id and country.id.CJTF_RED then
            countryId = country.id.CJTF_RED
        end
    end)
    
    local success, result = pcall(function()
        return coalition.addStaticObject(countryId, staticData)
    end)
    
    if success and result then
        log("Spawned static (CJTF_RED): " .. name .. " (" .. typeName .. ")")
        return result
    end
    
    -- Fallback: Try with INSURGENTS (country ID 70)
    success, result = pcall(function()
        return coalition.addStaticObject(70, staticData)
    end)
    
    if success and result then
        log("Spawned static (INSURGENTS): " .. name .. " (" .. typeName .. ")")
        return result
    end
    
    log("Failed to spawn static: " .. name .. " - " .. tostring(result))
    return nil
end

local function spawnIEDProps(roadPos, iedId, zoneName)
    local success, result = pcall(function()
        local cfg = DGSS_IED.ROAD_PLACEMENT
        
        -- Random offset from road
        local offset = cfg.roadOffsetMin + math.random() * (cfg.roadOffsetMax - cfg.roadOffsetMin)
        local offsetAngle = math.random() * 2 * math.pi
        
        -- Place barrel offset from road
        local barrelX = roadPos.x + offset * math.cos(offsetAngle)
        local barrelZ = roadPos.z + offset * math.sin(offsetAngle)
        local barrelName = "IED_Barrel_" .. iedId
        
        -- Place vehicle 5-8 meters away from barrel
        local vehicleOffset = 5 + math.random() * 3
        local vehicleAngle = offsetAngle + math.pi  -- Opposite side
        local vehicleX = roadPos.x + offset * math.cos(vehicleAngle) + vehicleOffset * math.cos(vehicleAngle + math.pi/2)
        local vehicleZ = roadPos.z + offset * math.sin(vehicleAngle) + vehicleOffset * math.sin(vehicleAngle + math.pi/2)
        
        -- Pick random vehicle type
        local vehicleType = DGSS_IED.STATICS.vehicles[math.random(#DGSS_IED.STATICS.vehicles)]
        local vehicleName = "IED_Vehicle_" .. iedId
        
        -- Spawn barrel
        local barrel = spawnStatic(DGSS_IED.STATICS.Structure, barrelX, barrelZ, offsetAngle, barrelName)
        
        -- Spawn vehicle facing toward barrel
        local vehicleHeading = math.atan2(barrelZ - vehicleZ, barrelX - vehicleX)
        local vehicle = spawnStatic(vehicleType, vehicleX, vehicleZ, vehicleHeading, vehicleName)
        
        if barrel and vehicle then
            -- Track static -> IED mapping for death events
            DGSS_IED.STATIC_TO_IED[barrelName] = iedId
            DGSS_IED.STATIC_TO_IED[vehicleName] = iedId
            
            return {
                barrelName = barrelName,
                vehicleName = vehicleName,
                barrel = barrel,
                vehicle = vehicle,
            }
        end
        
        return nil
    end)
    
    if success then
        return result
    else
        log("ERROR in spawnIEDProps: " .. tostring(result))
        return nil
    end
end

----------------------------------------------------------------
-- ASYNC PATHFINDING - Spreads CPU load across frames
----------------------------------------------------------------

-- Process one pathfinding request from queue
local function processPathfindQueue()
    if #DGSS_IED.PATHFIND_QUEUE == 0 then
        DGSS_IED.PATHFIND_IN_PROGRESS = false
        log("Pathfinding queue complete")
        
        -- Now activate IEDs from cached routes
        local totalIEDs = activateIEDsOnRoutes()
        
        if totalIEDs == 0 then
            log("WARNING: No IEDs were placed on routes!")
            trigger.action.outText("[IED] WARNING: No IEDs placed - check bases and road network", 15)
        else
            trigger.action.outText(string.format("[IED] Placed %d IEDs on convoy routes", totalIEDs), 15)
        end
        
        return
    end
    
    -- Process next item
    local task = table.remove(DGSS_IED.PATHFIND_QUEUE, 1)
    local baseFrom = task.from
    local baseTo = task.to
    local routeNum = task.routeNum
    local cacheKey = baseFrom .. "->" .. baseTo .. "_R" .. routeNum
    
    -- Check cache first
    if not DGSS_IED.ROUTE_CACHE[cacheKey] then
        local route = findRouteBetweenBases(baseFrom, baseTo, routeNum)
        if route and #route > 0 then
            DGSS_IED.ROUTE_CACHE[cacheKey] = route
            log(string.format("Cached route: %s (%.1f%% complete)", cacheKey, 
                ((task.totalTasks - #DGSS_IED.PATHFIND_QUEUE) / task.totalTasks) * 100))
        end
    end
    
    -- Schedule next pathfinding task
    local delay = DGSS_IED.ROAD_PLACEMENT.pathfindDelay or 0.5
    timer.scheduleFunction(processPathfindQueue, {}, timer.getTime() + delay)
end

-- Build pathfinding queue for all base pairs and routes
local function buildPathfindQueue()
    DGSS_IED.PATHFIND_QUEUE = {}
    local bases = DGSS_IED.BASE_EXCLUSION_ZONES
    local routesPerPair = DGSS_IED.ROAD_PLACEMENT.routesPerBasePair
    
    -- Create tasks for all base pairs and routes
    for i = 1, #bases do
        for j = i + 1, #bases do
            for routeNum = 1, routesPerPair do
                table.insert(DGSS_IED.PATHFIND_QUEUE, {
                    from = bases[i],
                    to = bases[j],
                    routeNum = routeNum,
                    totalTasks = (#bases * (#bases - 1) / 2) * routesPerPair
                })
            end
        end
    end
    
    log(string.format("Built pathfinding queue with %d tasks", #DGSS_IED.PATHFIND_QUEUE))
    return #DGSS_IED.PATHFIND_QUEUE
end

----------------------------------------------------------------
-- IED ACTIVATION - ROUTE MODE
----------------------------------------------------------------

activateIEDsOnRoutes = function()
    local cfg = DGSS_IED.ROAD_PLACEMENT
    
    -- Find all IED positions along routes between bases (grouped by base pair)
    local basePairData = findAllRouteIEDPositions()
    
    if #basePairData == 0 then
        log("WARNING: No road positions found on any routes!")
        return 0
    end
    
    -- Calculate total positions available
    local totalPositions = 0
    for _, data in ipairs(basePairData) do
        totalPositions = totalPositions + #data.positions
    end
    
    log(string.format("Found %d potential IED positions across %d base pairs", totalPositions, #basePairData))
    
    -- Round-robin distribution for maximum fairness
    local activatedCount = 0
    local round = 1
    local iedsRemaining = DGSS_IED.MAX_ACTIVE_IEDS
    local usedIndices = {}  -- Track which positions have been used per base pair
    
    for _, data in ipairs(basePairData) do
        usedIndices[data.basePair] = {}
    end
    
    log("=== STARTING ROUND-ROBIN IED DISTRIBUTION ===")
    
    while iedsRemaining > 0 do
        local iedsThisRound = 0
        
        log(string.format("Round %d: %d IEDs remaining", round, iedsRemaining))
        
        -- Shuffle base pairs for fairness
        local shuffledPairs = {}
        for i, data in ipairs(basePairData) do
            table.insert(shuffledPairs, {index = i, data = data})
        end
        
        for i = #shuffledPairs, 2, -1 do
            local j = math.random(1, i)
            shuffledPairs[i], shuffledPairs[j] = shuffledPairs[j], shuffledPairs[i]
        end
        
        -- Give each base pair 1 IED this round (if they have positions available)
        for _, entry in ipairs(shuffledPairs) do
            if iedsRemaining <= 0 then break end
            
            local data = entry.data
            local basePair = data.basePair
            local pairPositions = data.positions
            local usedCount = #usedIndices[basePair]
            
            -- Does this pair have more positions available?
            if usedCount < #pairPositions then
                -- Find next unused position
                local posIndex = nil
                for i = 1, #pairPositions do
                    if not usedIndices[basePair][i] then
                        posIndex = i
                        break
                    end
                end
                
                if posIndex then
                    local roadPos = pairPositions[posIndex]
                    usedIndices[basePair][posIndex] = true
                    
                    DGSS_IED.SPAWN_COUNTER = DGSS_IED.SPAWN_COUNTER + 1
                    local iedId = "IED_ROUTE_" .. DGSS_IED.SPAWN_COUNTER
                    
                    -- Spawn IED props
                    local props = spawnIEDProps(roadPos, iedId, basePair)
                    
                    if props then
                        local triggerCount = math.random(1, 8)
                        
                        DGSS_IED.ACTIVE_IEDs[iedId] = {
                            id = iedId,
                            zoneName = basePair,
                            pos = roadPos,
                            triggerCount = triggerCount,
                            vehiclesSeen = 0,
                            barrelName = props.barrelName,
                            vehicleName = props.vehicleName,
                            exploded = false,
                            trackedUnits = {},
                        }
                        
                        table.insert(DGSS_IED.IED_POSITIONS, roadPos)
                        if #DGSS_IED.IED_POSITIONS > DGSS_IED.MAX_TRACKED_POSITIONS then
                            table.remove(DGSS_IED.IED_POSITIONS, 1)
                        end
                        
                        activatedCount = activatedCount + 1
                        iedsRemaining = iedsRemaining - 1
                        iedsThisRound = iedsThisRound + 1
                    end
                end
            end
        end
        
        -- If no IEDs were placed this round, all pairs are exhausted
        if iedsThisRound == 0 then
            log(string.format("All base pairs exhausted - placed %d/%d IEDs", activatedCount, DGSS_IED.MAX_ACTIVE_IEDS))
            break
        end
        
        round = round + 1
        
        -- Safety: prevent infinite loops
        if round > 100 then
            log("WARNING: Distribution exceeded 100 rounds - breaking")
            break
        end
    end
    
    -- Log final distribution
    log("=== FINAL IED DISTRIBUTION BY BASE PAIR ===")
    for _, data in ipairs(basePairData) do
        local allocated = #usedIndices[data.basePair]
        log(string.format("%s: %d IEDs (from %d available positions)", 
            data.basePair, allocated, #data.positions))
    end
    
    log(string.format("=== Total IEDs activated: %d across %d base pairs ===", activatedCount, #basePairData))
    return activatedCount
end

----------------------------------------------------------------
-- IED ACTIVATION - LEGACY ZONE MODE
----------------------------------------------------------------

local function activateIEDsInZone(zone)
    local cfg = DGSS_IED.ROAD_PLACEMENT
    
    -- Check if we've hit the global IED limit
    local currentActiveCount = countActiveIEDs()
    if currentActiveCount >= DGSS_IED.MAX_ACTIVE_IEDS then
        log("WARNING: Max IED limit reached (" .. DGSS_IED.MAX_ACTIVE_IEDS .. "). Skipping zone " .. zone.name)
        return 0
    end
    
    local roadPositions = findRoadPositionsInZone(zone)
    
    if #roadPositions == 0 then
        log("WARNING: No roads found in zone " .. zone.name .. " - skipping")
        return 0
    end
    
    -- Limit to configured number of IEDs per zone
    local numToSpawn = math.min(cfg.iedsPerZone, #roadPositions)
    local activatedCount = 0
    
    -- Shuffle road positions
    local shuffled = {}
    for _, pos in ipairs(roadPositions) do
        table.insert(shuffled, pos)
    end
    
    for i = 1, numToSpawn do
        if #shuffled == 0 then break end
        
        -- Check if we've hit the limit mid-spawn
        if countActiveIEDs() >= DGSS_IED.MAX_ACTIVE_IEDS then
            log("Max IED limit (" .. DGSS_IED.MAX_ACTIVE_IEDS .. ") reached during zone " .. zone.name .. " spawn")
            break
        end
        
        local idx = math.random(#shuffled)
        local roadPos = table.remove(shuffled, idx)
        
        DGSS_IED.SPAWN_COUNTER = DGSS_IED.SPAWN_COUNTER + 1
        local iedId = "IED_" .. zone.name .. "_" .. DGSS_IED.SPAWN_COUNTER
        
        -- Spawn IED props
        local props = spawnIEDProps(roadPos, iedId, zone.name)
        
        if props then
            -- Random trigger count between 1 and 8
            local triggerCount = math.random(1, 8)
            
            DGSS_IED.ACTIVE_IEDs[iedId] = {
                id = iedId,
                zoneName = zone.name,
                pos = roadPos,
                triggerCount = triggerCount,
                vehiclesSeen = 0,
                barrelName = props.barrelName,
                vehicleName = props.vehicleName,
                exploded = false,
                trackedUnits = {},
            }
            
            -- Track position for spacing checks (limit table size for 24/7 operation)
            table.insert(DGSS_IED.IED_POSITIONS, roadPos)
            if #DGSS_IED.IED_POSITIONS > DGSS_IED.MAX_TRACKED_POSITIONS then
                table.remove(DGSS_IED.IED_POSITIONS, 1)  -- Remove oldest position
            end
            
            activatedCount = activatedCount + 1
            log("Activated IED " .. iedId .. " (triggers on vehicle #" .. triggerCount .. ")")
        end
    end
    
    return activatedCount
end

-- Staggered zone activation state
local ZONE_ACTIVATION_STATE = {
    currentIndex = 0,
    totalActivated = 0,
    zonesProcessed = 0,
    zonesSkipped = {},
    isComplete = false,
}

local function activateNextZone()
    pcall(function()
        ZONE_ACTIVATION_STATE.currentIndex = ZONE_ACTIVATION_STATE.currentIndex + 1
        local zoneIndex = ZONE_ACTIVATION_STATE.currentIndex
        
        if zoneIndex > #DGSS_IED.SPAWN_ZONES then
            -- All zones processed - show final summary
            ZONE_ACTIVATION_STATE.isComplete = true
            
            local debugMsg = "══════ IED ROAD SYSTEM v5.3 ══════\n"
            debugMsg = debugMsg .. "Zones configured: " .. #DGSS_IED.SPAWN_ZONES .. "\n"
            debugMsg = debugMsg .. "Zones processed: " .. ZONE_ACTIVATION_STATE.zonesProcessed .. "\n"
            debugMsg = debugMsg .. "Total IEDs placed: " .. ZONE_ACTIVATION_STATE.totalActivated .. "\n"
            debugMsg = debugMsg .. "Max IED limit: " .. DGSS_IED.MAX_ACTIVE_IEDS .. "\n\n"
            
            if #ZONE_ACTIVATION_STATE.zonesSkipped > 0 then
                debugMsg = debugMsg .. "⚠ ZONES SKIPPED (no roads found):\n"
                for _, name in ipairs(ZONE_ACTIVATION_STATE.zonesSkipped) do
                    debugMsg = debugMsg .. "  • " .. name .. "\n"
                end
            end
            
            debugMsg = debugMsg .. "\n✓ IEDs placed along roads"
            debugMsg = debugMsg .. "\n══════════════════════════════"
            
            trigger.action.outText(debugMsg, 30)
            log("Activated " .. ZONE_ACTIVATION_STATE.totalActivated .. " IEDs across " .. ZONE_ACTIVATION_STATE.zonesProcessed .. " zones")
            return
        end
        
        local zoneName = DGSS_IED.SPAWN_ZONES[zoneIndex]
        log("Spawning IEDs in zone " .. zoneIndex .. "/" .. #DGSS_IED.SPAWN_ZONES .. ": " .. zoneName)
        
        local zone = getZone(zoneName)
        
        if zone then
            ZONE_ACTIVATION_STATE.zonesProcessed = ZONE_ACTIVATION_STATE.zonesProcessed + 1
            local count = activateIEDsInZone(zone)
            ZONE_ACTIVATION_STATE.totalActivated = ZONE_ACTIVATION_STATE.totalActivated + count
            
            if count == 0 then
                table.insert(ZONE_ACTIVATION_STATE.zonesSkipped, zoneName)
            end
        else
            log("WARNING: Zone not found in mission: " .. zoneName)
            table.insert(ZONE_ACTIVATION_STATE.zonesSkipped, zoneName .. " (not found)")
        end
        
        -- Schedule next zone after delay
        timer.scheduleFunction(activateNextZone, {}, timer.getTime() + DGSS_IED.ZONE_SPAWN_DELAY)
    end)
end

local function startZoneActivation()
    log("Starting staggered IED zone activation (" .. #DGSS_IED.SPAWN_ZONES .. " zones, " .. DGSS_IED.ZONE_SPAWN_DELAY .. "s delay)")
    trigger.action.outText("[IED] Spawning IEDs across " .. #DGSS_IED.SPAWN_ZONES .. " zones...\nPlease wait ~" .. (#DGSS_IED.SPAWN_ZONES * DGSS_IED.ZONE_SPAWN_DELAY) .. " seconds", 10)
    
    -- Start the cascade
    timer.scheduleFunction(activateNextZone, {}, timer.getTime() + 1)
end

----------------------------------------------------------------
-- INSURGENT SPAWN
----------------------------------------------------------------

local function spawnInsurgents(iedPos, iedId)
    if not DGSS_IED.INSURGENT_SPAWN.enabled then return 0 end
    
    local cfg = DGSS_IED.INSURGENT_SPAWN
    
    if math.random() > cfg.spawnChance then
        log("No insurgent ambush at " .. iedId)
        return 0
    end
    
    local numInsurgents = math.random(cfg.minCount, cfg.maxCount)
    local spawnDistance = math.random(cfg.minDistance, cfg.maxDistance)
    local spawnAngle = math.random() * 2 * math.pi
    
    local spawnX = iedPos.x + spawnDistance * math.cos(spawnAngle)
    local spawnZ = iedPos.z + spawnDistance * math.sin(spawnAngle)
    
    DGSS_IED.SPAWN_COUNTER = DGSS_IED.SPAWN_COUNTER + 1
    local groupName = string.format("IED_Ambush_%s_%d", iedId, DGSS_IED.SPAWN_COUNTER)
    
    local units = {}
    for i = 1, numInsurgents do
        local offsetAngle = (i / numInsurgents) * 2 * math.pi
        local offsetDist = 5 + math.random() * 10
        
        local unitX = spawnX + offsetDist * math.cos(offsetAngle)
        local unitZ = spawnZ + offsetDist * math.sin(offsetAngle)
        
        table.insert(units, {
            ["type"] = cfg.unitTypes[math.random(#cfg.unitTypes)],
            ["x"] = unitX,
            ["y"] = unitZ,
            ["name"] = groupName .. "_" .. i,
            ["heading"] = math.atan2(iedPos.z - unitZ, iedPos.x - unitX),
            ["skill"] = cfg.skill,
        })
    end
    
    local groupData = {
        ["units"] = units,
        ["name"] = groupName,
        ["task"] = "Ground Nothing",
    }
    
    local success = pcall(function()
        coalition.addGroup(country.id.INSURGENTS, Group.Category.GROUND, groupData)
    end)
    
    if success then
        table.insert(DGSS_IED.INSURGENT_GROUPS, groupName)
        log("Spawned " .. numInsurgents .. " insurgents at " .. iedId)
        
        -- Schedule cleanup check after 10 minutes
        timer.scheduleFunction(function()
            local grp = Group.getByName(groupName)
            if not grp or not grp:isExist() or grp:getSize() == 0 then
                for i, name in ipairs(DGSS_IED.INSURGENT_GROUPS) do
                    if name == groupName then
                        table.remove(DGSS_IED.INSURGENT_GROUPS, i)
                        log("Cleaned up destroyed insurgent group: " .. groupName)
                        break
                    end
                end
            else
                -- If still alive, check again in 10 minutes
                timer.scheduleFunction(function()
                    local g = Group.getByName(groupName)
                    if not g or not g:isExist() or g:getSize() == 0 then
                        for i, name in ipairs(DGSS_IED.INSURGENT_GROUPS) do
                            if name == groupName then
                                table.remove(DGSS_IED.INSURGENT_GROUPS, i)
                                log("Cleaned up destroyed insurgent group: " .. groupName)
                                break
                            end
                        end
                    end
                end, {}, timer.getTime() + 600)
            end
        end, {}, timer.getTime() + 600)
        
        return numInsurgents
    end
    return 0
end

----------------------------------------------------------------
-- IED RESET & REPLACEMENT
----------------------------------------------------------------

local function resetIED(params)
    local iedId = params.iedId
    local iedData = DGSS_IED.ACTIVE_IEDs[iedId]
    
    if not iedData then 
        log("Cannot reset IED " .. iedId .. " - no data")
        return 
    end
    
    -- Clear the timer reference
    DGSS_IED.RESET_TIMERS[iedId] = nil
    
    log("Resetting IED: " .. iedId)
    
    -- Clear old static tracking
    if iedData.barrelName then
        DGSS_IED.STATIC_TO_IED[iedData.barrelName] = nil
    end
    if iedData.vehicleName then
        DGSS_IED.STATIC_TO_IED[iedData.vehicleName] = nil
    end
    
    -- Spawn new IED props at same location
    local props = spawnIEDProps(iedData.pos, iedId, iedData.zoneName)
    
    if props then
        -- Reset IED data with new props
        local triggerCount = math.random(1, 8)
        
        iedData.triggerCount = triggerCount
        iedData.vehiclesSeen = 0
        iedData.barrelName = props.barrelName
        iedData.vehicleName = props.vehicleName
        iedData.exploded = false
        iedData.trackedUnits = {}
        
        log("IED " .. iedId .. " reset and re-armed (triggers on vehicle #" .. triggerCount .. ")")
    else
        log("Failed to respawn props for IED " .. iedId)
    end
end

----------------------------------------------------------------
-- EXPLOSION
----------------------------------------------------------------

local function triggerExplosion(iedId, reason)
    local iedData = DGSS_IED.ACTIVE_IEDs[iedId]
    if not iedData or iedData.exploded then return end
    
    iedData.exploded = true
    local pos = iedData.pos
    
    -- Create explosion
    local groundHeight = 0
    pcall(function()
        groundHeight = land.getHeight({x = pos.x, y = pos.z}) or 0
    end)
    local explosionPos = {x = pos.x, y = groundHeight, z = pos.z}
    
    trigger.action.explosion(explosionPos, DGSS_IED.EXPLOSION.power)
    trigger.action.effectSmokeBig(explosionPos, 1.0, 1.0)
    
    -- Multiple flares in different directions
    pcall(function()
        local flareColors = {
            trigger.flareColor.Red,
            trigger.flareColor.Yellow,
            trigger.flareColor.Green,
            trigger.flareColor.White,
        }
        for i = 0, 7 do
            local angle = (i / 8) * 2 * math.pi
            local color = flareColors[(i % #flareColors) + 1]
            trigger.action.signalFlare(explosionPos, color, angle)
        end
    end)
    
    -- Spawn insurgents
    local insurgentCount = spawnInsurgents(pos, iedId)
    
    -- Get coordinates
    local mgrs = getCoordinateStrings(explosionPos)
    
    -- Message
    local message = string.format(
        "═══ IED DETONATED ═══\nLocation: %s\nMGRS: %s\nReason: %s\n\n⚠ INSURGENT AMBUSH: %d fighters!",
        iedId, mgrs, reason, insurgentCount
    )
    trigger.action.outTextForCoalition(DGSS_IED.COALITION, message, 15)
    
    log("EXPLOSION at " .. iedId .. " - " .. reason .. " - " .. insurgentCount .. " insurgents")
    
    -- Clean up static tracking
    DGSS_IED.STATIC_TO_IED[iedData.barrelName] = nil
    DGSS_IED.STATIC_TO_IED[iedData.vehicleName] = nil
    
    -- Cancel any existing reset timer
    if DGSS_IED.RESET_TIMERS[iedId] then
        timer.removeFunction(DGSS_IED.RESET_TIMERS[iedId])
        log("Cancelled existing reset timer for " .. iedId)
    end
    
    -- Schedule IED reset after 30 minutes
    local resetTimer = timer.scheduleFunction(resetIED, {iedId = iedId}, timer.getTime() + DGSS_IED.RESET_TIME)
    DGSS_IED.RESET_TIMERS[iedId] = resetTimer
    log("IED " .. iedId .. " will reset in " .. (DGSS_IED.RESET_TIME / 60) .. " minutes")
end

----------------------------------------------------------------
-- STATIC DESTRUCTION EVENT HANDLER
----------------------------------------------------------------

local function onStaticDeath(event)
    if event.id ~= world.event.S_EVENT_DEAD then return end
    if not event.initiator then return end
    
    local success, name = pcall(function() return event.initiator:getName() end)
    if not success or not name then return end
    
    local iedId = DGSS_IED.STATIC_TO_IED[name]
    if iedId then
        log("IED prop destroyed: " .. name .. " in " .. iedId)
        triggerExplosion(iedId, "IED prop destroyed")
    end
end

----------------------------------------------------------------
-- ZONE CHECKING (Vehicle counting)
----------------------------------------------------------------

local function checkUnitNearIED(unit, iedPos)
    if not unit or not unit:isExist() then return false end
    
    local success, pos = pcall(function() return unit:getPoint() end)
    if not success or not pos then return false end
    
    local dist = _2dDist(pos, {x = iedPos.x, z = iedPos.z})
    if not dist then return false end
    
    return dist <= (50 + DGSS_IED.DETECTION_RADIUS)  -- 50m trigger radius
end

local function checkActiveIEDs()
    -- Skip entirely when no live IEDs exist (avoids coalition.getGroups call every 10s for nothing)
    local _hasActive = false
    for _, _d in pairs(DGSS_IED.ACTIVE_IEDs) do
        if not _d.exploded then _hasActive = true; break end
    end
    if not _hasActive then return end
    pcall(function()
        local blueGroups = coalition.getGroups(DGSS_IED.COALITION, Group.Category.GROUND) or {}
        
        for iedId, iedData in pairs(DGSS_IED.ACTIVE_IEDs) do
            if not iedData.exploded then
                local iedPos = iedData.pos

                -- v6.2 Spatial Optimization: Pre-filter groups using Manhattan distance
                -- Only check groups within reasonable range (avoids expensive distance checks)
                local nearbyGroups = {}
                for _, group in ipairs(blueGroups) do
                    if group and group:isExist() then
                        local units = group:getUnits()
                        if units and #units > 0 then
                            local groupPos = units[1]:getPosition().p
                            -- Manhattan distance approximation (faster than Euclidean)
                            local manhattanDist = math.abs(groupPos.x - iedPos.x) + math.abs(groupPos.z - iedPos.z)
                            if manhattanDist < 200 then  -- ~140m Euclidean distance
                                table.insert(nearbyGroups, group)
                            end
                        end
                    end
                end

                -- Clean up trackedUnits
                local unitsToRemove = {}
                for unitName, _ in pairs(iedData.trackedUnits) do
                    local unit = Unit.getByName(unitName)
                    if not unit or not unit:isExist() then
                        table.insert(unitsToRemove, unitName)
                    end
                end
                for _, unitName in ipairs(unitsToRemove) do
                    iedData.trackedUnits[unitName] = nil
                end

                -- Use pre-filtered nearby groups instead of all groups
                for _, group in ipairs(nearbyGroups) do
                    if group and group:isExist() then
                        for _, unit in ipairs(group:getUnits()) do
                            if unit and unit:isExist() then
                                local unitName = unit:getName()
                                
                                -- Check if vehicle (not infantry)
                                local unitDesc = unit:getDesc()
                                local isVehicle = unitDesc and unitDesc.category == Unit.Category.GROUND_UNIT
                                
                                if isVehicle and checkUnitNearIED(unit, iedPos) then
                                    -- Check if this unit already counted
                                    if not iedData.trackedUnits[unitName] then
                                        iedData.trackedUnits[unitName] = true
                                        iedData.vehiclesSeen = iedData.vehiclesSeen + 1
                                        
                                        log(iedId .. ": Vehicle #" .. iedData.vehiclesSeen .. 
                                            " entered (triggers on #" .. iedData.triggerCount .. ")")
                                        
                                        -- Check if trigger count reached
                                        if iedData.vehiclesSeen >= iedData.triggerCount then
                                            triggerExplosion(iedId, "Vehicle #" .. iedData.vehiclesSeen .. " triggered IED")
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
end

----------------------------------------------------------------
-- MAINTENANCE & CLEANUP (24/7 Server Support)
----------------------------------------------------------------

local function performMaintenance()
    pcall(function()
        local cleaned = 0
        
        -- Clean up dead insurgent group references
        local validGroups = {}
        for _, groupName in ipairs(DGSS_IED.INSURGENT_GROUPS) do
            local grp = Group.getByName(groupName)
            if grp and grp:isExist() and grp:getSize() > 0 then
                table.insert(validGroups, groupName)
            else
                cleaned = cleaned + 1
            end
        end
        DGSS_IED.INSURGENT_GROUPS = validGroups
        
        -- Clean up invalid static-to-IED mappings
        local validMappings = {}
        for staticName, iedId in pairs(DGSS_IED.STATIC_TO_IED) do
            if DGSS_IED.ACTIVE_IEDs[iedId] then
                validMappings[staticName] = iedId
            else
                cleaned = cleaned + 1
            end
        end
        DGSS_IED.STATIC_TO_IED = validMappings
        
        -- Limit IED_POSITIONS table size if it's grown too large
        if #DGSS_IED.IED_POSITIONS > DGSS_IED.MAX_TRACKED_POSITIONS * 1.5 then
            local trimmed = {}
            local startIdx = #DGSS_IED.IED_POSITIONS - DGSS_IED.MAX_TRACKED_POSITIONS + 1
            for i = startIdx, #DGSS_IED.IED_POSITIONS do
                table.insert(trimmed, DGSS_IED.IED_POSITIONS[i])
            end
            DGSS_IED.IED_POSITIONS = trimmed
            cleaned = cleaned + 1
        end
        
        -- Clean up orphaned reset timers (IED no longer exists)
        local validTimers = {}
        for iedId, timerId in pairs(DGSS_IED.RESET_TIMERS) do
            if DGSS_IED.ACTIVE_IEDs[iedId] then
                validTimers[iedId] = timerId
            else
                -- Cancel timer for non-existent IED
                pcall(function() timer.removeFunction(timerId) end)
                cleaned = cleaned + 1
            end
        end
        DGSS_IED.RESET_TIMERS = validTimers
        
        if cleaned > 0 then
            log("Maintenance: Cleaned up " .. cleaned .. " dead references")
        end
        
        -- Log memory statistics every cleanup
        local activeIEDs = 0
        local explodedIEDs = 0
        for _, data in pairs(DGSS_IED.ACTIVE_IEDs) do
            if data.exploded then
                explodedIEDs = explodedIEDs + 1
            else
                activeIEDs = activeIEDs + 1
            end
        end
        
        log(string.format("Memory Stats: %d active IEDs, %d exploded, %d insurgent groups, %d static mappings, %d positions tracked, %d reset timers",
            activeIEDs, explodedIEDs, #DGSS_IED.INSURGENT_GROUPS, 
            (function() local c=0; for _ in pairs(DGSS_IED.STATIC_TO_IED) do c=c+1 end return c end)(),
            #DGSS_IED.IED_POSITIONS,
            (function() local c=0; for _ in pairs(DGSS_IED.RESET_TIMERS) do c=c+1 end return c end)()))
    end)
    
    -- Schedule next maintenance
    timer.scheduleFunction(performMaintenance, {}, timer.getTime() + DGSS_IED.CLEANUP_INTERVAL)
end

----------------------------------------------------------------
-- MAIN LOOP
----------------------------------------------------------------

local function iedCheckLoop()
    checkActiveIEDs()
    timer.scheduleFunction(iedCheckLoop, {}, timer.getTime() + DGSS_IED.CHECK_INTERVAL)
end

----------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------

local function initializeIEDSystem()
    log("Initializing IED Road Placement System v6.2 (Route Mode)...")
    
    -- Auto-discover IED zones from mission (used as valid placement regions)
    DGSS_IED.SPAWN_ZONES = discoverIEDZones()
    
    if #DGSS_IED.SPAWN_ZONES == 0 then
        log("WARNING: No IED zones found with pattern '" .. DGSS_IED.ZONE_NAME_PATTERN .. "' - IED placement will not be restricted to specific regions")
    else
        log("Found " .. #DGSS_IED.SPAWN_ZONES .. " valid IED placement zones")
    end
    
    -- Register event handler for static destruction
    local eventHandler = {}
    function eventHandler:onEvent(event)
        local _ok, _err = pcall(onStaticDeath, event)
        if not _ok then env.warning("[IED] onEvent error: " .. tostring(_err)) end
    end
    world.addEventHandler(eventHandler)
    
    -- Use ROUTE MODE - pathfind between all base pairs (ASYNC)
    if DGSS_IED.USE_ROUTE_MODE then
        log("Starting ASYNC ROUTE MODE - calculating routes in background...")
        
        local totalTasks = buildPathfindQueue()
        trigger.action.outText(string.format("[IED] Calculating %d routes in background (prevents lag)...", totalTasks), 10)
        
        -- Start async pathfinding after mission is fully loaded (spreads load across frames)
        DGSS_IED.PATHFIND_IN_PROGRESS = true
        timer.scheduleFunction(processPathfindQueue, {}, timer.getTime() + 15)  -- Wait 15 seconds before starting
    else
        -- Use legacy zone-sampling mode
        log("Starting ZONE MODE IED placement (legacy)...")
        startZoneActivation()
    end
    
    -- Start check loop
    timer.scheduleFunction(iedCheckLoop, {}, timer.getTime() + 5)
    
    -- Start maintenance loop for 24/7 server operation
    timer.scheduleFunction(performMaintenance, {}, timer.getTime() + DGSS_IED.CLEANUP_INTERVAL)
    
    log("IED Road Placement System v6.0 initialization complete (24/7 mode enabled)")
end

-- Initialize after mission load
timer.scheduleFunction(initializeIEDSystem, {}, timer.getTime() + 3)

----------------------------------------------------------------
-- DEBUG FUNCTIONS
----------------------------------------------------------------

function DGSS_IED.getStats()
    local active = 0
    local exploded = 0
    
    for _, data in pairs(DGSS_IED.ACTIVE_IEDs) do
        if data.exploded then
            exploded = exploded + 1
        else
            active = active + 1
        end
    end
    
    local msg = string.format("IED Stats:\nTotal IEDs: %d\nActive: %d\nExploded: %d", 
        active + exploded, active, exploded)
    trigger.action.outText(msg, 15)
end

log("IED Road Placement System v5.2 loaded")
trigger.action.outText("[IED] Road Placement System v5.2 Loading...", 5)
