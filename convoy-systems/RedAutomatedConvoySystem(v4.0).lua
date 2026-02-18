---------------------------------------------------------------------
-- CONVOY TEMPLATES
---------------------------------------------------------------------

ConvoyTemplate1  = { units = { {type="BRDM-2"},{type="Ural-375"},{type="HL_DSHK"},{type="tt_ZU-23"}, } }
ConvoyTemplate2  = { units = { {type="BTR-60"},{type="Ural-375 ZU-23 Insurgent"},{type="HL_KORD"},{type="ural_4230_civil_t"},{type="HL_ZU-23"}, } }
ConvoyTemplate3  = { units = { {type="Ural-375"},{type="HL_DSHK"},{type="BRDM-2"},{type="HL_KORD"}, } }
ConvoyTemplate4  = { units = { {type="BTR-60"},{type="Ural-375"},{type="HL_ZU-23"},{type="tt_ZU-23"},{type="HL_DSHK"}, } }
ConvoyTemplate5  = { units = { {type="ural_4230_civil_t"},{type="HL_KORD"},{type="Ural-375 ZU-23 Insurgent"},{type="BRDM-2"}, } }
ConvoyTemplate6  = { units = { {type="HL_ZU-23"},{type="Ural-375"},{type="HL_DSHK"},{type="BTR-60"},{type="ural_4230_civil_t"}, } }
ConvoyTemplate7  = { units = { {type="BRDM-2"},{type="HL_KORD"},{type="Ural-375"},{type="Ural-375 ZU-23 Insurgent"}, } }
ConvoyTemplate8  = { units = { {type="tt_ZU-23"},{type="HL_DSHK"},{type="BTR-60"},{type="Ural-375"}, } }
ConvoyTemplate9  = { units = { {type="ural_4230_civil_t"},{type="HL_ZU-23"},{type="HL_KORD"},{type="BRDM-2"},{type="Ural-375"}, } }
ConvoyTemplate10 = { units = { {type="Ural-375 ZU-23 Insurgent"},{type="HL_DSHK"},{type="tt_ZU-23"},{type="BTR-60"}, } }
ConvoyTemplate11 = { units = { {type="HL_KORD"},{type="ural_4230_civil_t"},{type="BRDM-2"},{type="HL_ZU-23"}, } }
ConvoyTemplate12 = { units = { {type="Ural-375"},{type="HL_DSHK"},{type="tt_ZU-23"},{type="BTR-60"},{type="HL_KORD"}, } }
ConvoyTemplate13 = { units = { {type="BRDM-2"},{type="HL_ZU-23"},{type="Ural-375 ZU-23 Insurgent"},{type="ural_4230_civil_t"}, } }
ConvoyTemplate14 = { units = { {type="HL_DSHK"},{type="BTR-60"},{type="Ural-375"},{type="HL_KORD"}, } }
ConvoyTemplate15 = { units = { {type="ural_4230_civil_t"},{type="HL_DSHK"},{type="BRDM-2"},{type="tt_ZU-23"},{type="Ural-375"}, } }
ConvoyTemplate16 = { units = { {type="HL_KORD"},{type="HL_ZU-23"},{type="Ural-375 ZU-23 Insurgent"},{type="BTR-60"}, } }
ConvoyTemplate17 = { units = { {type="BRDM-2"},{type="HL_DSHK"},{type="ural_4230_civil_t"},{type="HL_KORD"}, } }
ConvoyTemplate18 = { units = { {type="Ural-375"},{type="HL_ZU-23"},{type="tt_ZU-23"},{type="BRDM-2"}, } }
ConvoyTemplate19 = { units = { {type="ural_4230_civil_t"},{type="HL_KORD"},{type="HL_DSHK"},{type="Ural-375 ZU-23 Insurgent"},{type="BTR-60"}, } }
ConvoyTemplate20 = { units = { {type="HL_ZU-23"},{type="BRDM-2"},{type="Ural-375"},{type="HL_KORD"}, } }

CONVOY_TEMPLATES = {
    "ConvoyTemplate1","ConvoyTemplate2","ConvoyTemplate3","ConvoyTemplate4","ConvoyTemplate5",
    "ConvoyTemplate6","ConvoyTemplate7","ConvoyTemplate8","ConvoyTemplate9","ConvoyTemplate10",
    "ConvoyTemplate11","ConvoyTemplate12","ConvoyTemplate13","ConvoyTemplate14","ConvoyTemplate15",
    "ConvoyTemplate16","ConvoyTemplate17","ConvoyTemplate18","ConvoyTemplate19","ConvoyTemplate20",
}

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------

local NUM_CONVOY_POINTS = 30
local CONVOY_SPEED      = 22  -- m/s (increased for faster gameplay)
local MAX_CONVOYS       = 15
local INITIAL_CONVOYS   = 3
local STAGGER_DELAY     = 120
local STALL_TIMEOUT     = 300  -- Clean up convoys that don't move for 5 minutes (300 seconds)
local STALL_CHECK_THRESHOLD = 10  -- Meters - if moved less than this, consider it stalled

---------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------

local convoyNodes   = {}
local activeConvoys = {}
local convoyID      = 0
local nextSpawnTime = 0
local MIN_TRAVEL_DISTANCE = 64820  -- 35nm in meters

---------------------------------------------------------------------
-- LOAD NODES ConvoyZone1..N
---------------------------------------------------------------------

local function loadConvoyNodes()
    for i = 1, NUM_CONVOY_POINTS do
        local name = "ConvoyZone" .. i
        local z = trigger.misc.getZone(name)
        if z and z.point then
            convoyNodes[#convoyNodes+1] = { name = name, x = z.point.x, y = z.point.z }
        else
            env.info("[CONVOY][WARN] Missing zone: " .. name)
        end
    end
    env.info("[CONVOY] Loaded " .. #convoyNodes .. " convoy nodes.")
end

-- Calculate distance between two nodes in meters
local function getDistance(nodeA, nodeB)
    local dx = nodeB.x - nodeA.x
    local dy = nodeB.y - nodeA.y
    return math.sqrt(dx * dx + dy * dy)
end

-- Get list of zones currently used as spawn points
local function getOccupiedStartZones()
    local occupied = {}
    for _, c in pairs(activeConvoys) do
        occupied[c.startNode.name] = true
    end
    return occupied
end

-- Get random start node (prefers unoccupied, but picks any if all occupied)
local function getRandomStartNode()
    local occupied = getOccupiedStartZones()
    local available = {}
    local anyZone = {}
    
    for _, n in ipairs(convoyNodes) do
        table.insert(anyZone, n)
        if not occupied[n.name] then
            table.insert(available, n)
        end
    end
    
    -- Prefer unoccupied zones
    if #available > 0 then
        return available[math.random(1, #available)]
    -- Fallback: allow occupied zones if necessary
    elseif #anyZone > 0 then
        env.info("[CONVOY][WARN] All start zones occupied, allowing zone reuse")
        return anyZone[math.random(1, #anyZone)]
    else
        return nil
    end
end

-- Get random destination node (35nm+ away, or farthest if none qualify)
local function getRandomDestNode(startNode)
    local validDests = {}
    local farthest = nil
    local maxDist = 0
    
    for _, n in ipairs(convoyNodes) do
        if n.name ~= startNode.name then
            local dist = getDistance(startNode, n)
            if dist >= MIN_TRAVEL_DISTANCE then
                table.insert(validDests, n)
            end
            -- Track farthest as fallback
            if dist > maxDist then
                maxDist = dist
                farthest = n
            end
        end
    end
    
    -- Prefer 35nm+ zones, but fallback to farthest zone if none available
    if #validDests > 0 then
        return validDests[math.random(1, #validDests)]
    elseif farthest then
        env.info("[CONVOY][WARN] No zones 35nm+ away from " .. startNode.name .. 
                 ", using farthest: " .. farthest.name .. 
                 " (" .. string.format("%.1f", maxDist / 1852) .. " nm)")
        return farthest
    else
        return nil
    end
end

local function getRandomNode(exclude)
    local list = {}
    for _, n in ipairs(convoyNodes) do
        if n.name ~= exclude then list[#list+1] = n end
    end
    if #list == 0 then return nil end
    return list[math.random(1, #list)]
end

local function buildRoute(a, b)
    -- Calculate intermediate waypoint (50m before destination)
    local routeDistance = math.sqrt((b.x - a.x)^2 + (b.y - a.y)^2)
    local approachDistance = 50
    local ratio = math.max(0, (routeDistance - approachDistance) / routeDistance)
    local wp3X = a.x + (b.x - a.x) * ratio
    local wp3Y = a.y + (b.y - a.y) * ratio
    
    -- Calculate a point 100m toward destination for getting on road
    local onRoadRatio = math.min(100 / routeDistance, 0.1)
    local wp2X = a.x + (b.x - a.x) * onRoadRatio
    local wp2Y = a.y + (b.y - a.y) * onRoadRatio
    
    return {
        ["points"] = {
            [1] = {
                ["alt"] = 0,
                ["type"] = "Turning Point",
                ["action"] = "Off Road",
                ["x"] = a.x,
                ["y"] = a.y,
                ["speed"] = CONVOY_SPEED,
                ["task"] = {["id"] = "ComboTask", ["params"] = {["tasks"] = {}}}
            },
            [2] = {
                ["alt"] = 0,
                ["type"] = "Turning Point",
                ["action"] = "On Road",
                ["x"] = wp2X,
                ["y"] = wp2Y,
                ["speed"] = CONVOY_SPEED,
                ["task"] = {["id"] = "ComboTask", ["params"] = {["tasks"] = {}}}
            },
            [3] = {
                ["alt"] = 0,
                ["type"] = "Turning Point",
                ["action"] = "On Road",
                ["x"] = wp3X,
                ["y"] = wp3Y,
                ["speed"] = CONVOY_SPEED,
                ["task"] = {["id"] = "ComboTask", ["params"] = {["tasks"] = {}}}
            },
            [4] = {
                ["alt"] = 0,
                ["type"] = "Turning Point",
                ["action"] = "Off Road",
                ["x"] = b.x,
                ["y"] = b.y,
                ["speed"] = CONVOY_SPEED,
                ["task"] = {["id"] = "ComboTask", ["params"] = {["tasks"] = {}}}
            }
        }
    }
end

-- Apply route to group using controller:setTask (most reliable method)
local function applyRouteToGroup(groupName, routeData)
    local grp = Group.getByName(groupName)
    if not grp or not grp:isExist() then
        env.info("[CONVOY][ERROR] Cannot apply route - group not found: " .. tostring(groupName))
        return false
    end
    
    local controller = grp:getController()
    if not controller then
        env.info("[CONVOY][ERROR] Cannot get controller for: " .. tostring(groupName))
        return false
    end
    
    -- Set AI options
    controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.AUTO)
    controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.OPEN_FIRE)
    controller:setOption(AI.Option.Ground.id.DISPERSE_ON_ATTACK, true)
    
    -- Apply route using Mission task
    controller:setTask({
        id = "Mission",
        params = {
            route = routeData
        }
    })
    
    return true
end

---------------------------------------------------------------------
-- SPAWN CONVOY (SAFE ROAD VERSION)
---------------------------------------------------------------------

local function spawnConvoy()
    if #convoyNodes == 0 then
        env.info("[CONVOY][ERROR] No convoy nodes loaded.")
        return
    end
    if not CONVOY_TEMPLATES or #CONVOY_TEMPLATES == 0 then
        env.info("[CONVOY][ERROR] No convoy templates defined.")
        return
    end

    convoyID = convoyID + 1

    -- Get start node (prefers unoccupied, falls back to any)
    local start = getRandomStartNode()
    if not start then
        env.info("[CONVOY][ERROR] No start zones available at all")
        return
    end

    -- Get destination (35nm+ preferred, falls back to farthest)
    local dest = getRandomDestNode(start)
    if not dest then
        env.info("[CONVOY][ERROR] Could not find ANY destination from " .. start.name)
        return
    end

    local templateName = CONVOY_TEMPLATES[math.random(1, #CONVOY_TEMPLATES)]
    local template     = _G[templateName]
    if not template or not template.units or #template.units == 0 then
        env.info("[CONVOY][ERROR] Invalid convoy template: " .. tostring(templateName))
        return
    end

    local t = math.floor(timer.getTime())
    local groupName = "ActiveConvoy_" .. convoyID .. "_" .. t

    local bearing = math.atan2(dest.y - start.y, dest.x - start.x)

    -- Use zone center for spawn (route will handle getting to road)
    local baseX = start.x
    local baseY = start.y

    local spacing = 12
    local units   = {}

    for i, u in ipairs(template.units) do
        local offset = (i - 1) * spacing
        units[#units+1] = {
            name    = groupName .. "_U" .. i,
            type    = u.type,
            x       = baseX - math.cos(bearing) * offset,
            y       = baseY - math.sin(bearing) * offset,
            heading = bearing,
            skill   = "Excellent",
        }
    end

    local groupTemplate = {
        country   = country.id.CJTF_RED,
        coalition = "red",
        category  = "vehicle",
        name      = groupName,
        units     = units,
    }

    local result = mist.dynAdd(groupTemplate)
    if not result or not result.name then
        env.info("[CONVOY][ERROR] dynAdd failed for convoy: " .. groupName)
        return
    end

    local group = Group.getByName(result.name)
    if not group or not group:isExist() then
        env.info("[CONVOY][ERROR] Convoy group does not exist after spawn: " .. tostring(result.name))
        return
    end

    ---------------------------------------------------------------------
    -- 🔥 JTAC MANAGER INTEGRATION
    ---------------------------------------------------------------------
    if JTAC_Manager and JTAC_Manager.registerSpawnedGroup then
        JTAC_Manager.registerSpawnedGroup(result.name)
    end

    local currentConvoyID = convoyID  -- Capture for closure
    activeConvoys[currentConvoyID] = {
        id        = currentConvoyID,
        name      = result.name,
        group     = group,
        startNode = start,
        endNode   = dest,
        lastPos   = {x = baseX, y = baseY},  -- Track position for stall detection
        lastPosUpdateTime = timer.getTime(),
        stallDetectedTime = nil,  -- Will be set if convoy stalls
    }

    local distance = getDistance(start, dest) / 1852  -- Convert to NM for logging
    env.info("[CONVOY] Spawned convoy " .. result.name ..
             " from " .. start.name .. " to " .. dest.name .. 
             " (distance: " .. string.format("%.1f", distance) .. " nm)")

    -- Capture variables for delayed route activation
    local capturedGroupName = result.name
    local capturedStart = {x = start.x, y = start.y}
    local capturedDest = {x = dest.x, y = dest.y}
    
    -- Delay route activation to allow DCS to fully initialize the group
    timer.scheduleFunction(function()
        local routeData = buildRoute(capturedStart, capturedDest)
        local success = applyRouteToGroup(capturedGroupName, routeData)
        if success then
            env.info("[CONVOY] Route activated for " .. capturedGroupName)
        else
            env.info("[CONVOY][ERROR] Failed to activate route for " .. capturedGroupName)
        end
    end, nil, timer.getTime() + 3)
end

---------------------------------------------------------------------
-- UPDATE & MANAGE
---------------------------------------------------------------------

local function updateConvoys()
    local now = timer.getTime()
    for id, c in pairs(activeConvoys) do
        local g = c.group
        if not g or not g:isExist() then
            activeConvoys[id] = nil
        else
            local units = g:getUnits()
            local lead  = units and units[1]
            if not lead then
                activeConvoys[id] = nil
            else
                local pos = lead:getPoint()
                
                -- STALL DETECTION: Check if convoy moved
                local distMoved = math.sqrt((pos.x - c.lastPos.x)^2 + (pos.z - c.lastPos.y)^2)
                if distMoved < STALL_CHECK_THRESHOLD then
                    -- Convoy hasn't moved much since last check
                    if not c.stallDetectedTime then
                        c.stallDetectedTime = now
                        env.info("[CONVOY][WARN] " .. c.name .. " is not moving, monitoring for stall...")
                    else
                        local stallDuration = now - c.stallDetectedTime
                        if stallDuration > STALL_TIMEOUT then
                            -- Stalled for too long, clean it up
                            env.info("[CONVOY][STALL] " .. c.name .. " stalled for " .. 
                                     string.format("%.0f", stallDuration) .. "s, destroying convoy.")
                            pcall(function() g:destroy() end)
                            activeConvoys[id] = nil
                            return
                        end
                    end
                else
                    -- Convoy is moving, reset stall timer
                    c.stallDetectedTime = nil
                    c.lastPos = {x = pos.x, y = pos.z}
                    c.lastPosUpdateTime = now
                end
                
                -- DESTINATION CHECK: See if reached destination
                local dx  = pos.x - c.endNode.x
                local dy  = pos.z - c.endNode.y
                if math.sqrt(dx * dx + dy * dy) < 75 then
                    -- Reached destination, pick new one (35nm+ away)
                    local newEnd = getRandomDestNode(c.endNode)
                    if newEnd then
                        c.startNode = c.endNode
                        c.endNode   = newEnd
                        c.stallDetectedTime = nil  -- Reset stall timer on new route
                        local distance = getDistance(c.startNode, c.endNode) / 1852  -- Convert to NM
                        env.info("[CONVOY] " .. c.name .. " routing to " .. newEnd.name .. 
                                 " (distance: " .. string.format("%.1f", distance) .. " nm)")
                        
                        -- Apply new route using controller:setTask
                        local routeData = buildRoute(c.startNode, c.endNode)
                        applyRouteToGroup(c.name, routeData)
                    else
                        env.info("[CONVOY][WARN] " .. c.name .. " could not find valid next destination")
                    end
                end
            end
        end
    end
end

local function convoyManager()
    local count = 0
    for _ in pairs(activeConvoys) do count = count + 1 end

    local now = timer.getTime()

    while count < math.min(INITIAL_CONVOYS, MAX_CONVOYS) do
        spawnConvoy()
        count = count + 1
        nextSpawnTime = now + STAGGER_DELAY
    end

    if count < MAX_CONVOYS and now >= nextSpawnTime then
        spawnConvoy()
        nextSpawnTime = now + STAGGER_DELAY
    end
end

local function convoyLoop()
    updateConvoys()
    convoyManager()
    return timer.getTime() + 10  -- Optimized: check every 10 seconds
end

---------------------------------------------------------------------
-- INIT
---------------------------------------------------------------------

loadConvoyNodes()
nextSpawnTime = timer.getTime() + STAGGER_DELAY
timer.scheduleFunction(convoyLoop, {}, timer.getTime() + 10)