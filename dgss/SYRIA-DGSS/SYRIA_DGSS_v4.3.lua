-- =========================================================
-- DCS World: Dynamic Insurgent Zone Spawner (Russia Version)
-- Polygon‑Safe + Global Shuffle Bag
-- With marker tracking and proper cleanup
-- =========================================================

-------------------------------------------------------------
-- Forward declarations
-------------------------------------------------------------

local spawnGroupInZone  -- Forward declare for use in callbacks

-------------------------------------------------------------
-- 20 Syrian Forces Group Templates
-------------------------------------------------------------

local INSURGENT_TEMPLATES = {
    {
        name = "Ins_1",
        units = {
            { type="T-72B",             dx=0.0,   dy=0.0,   heading=0.0 },
            { type="BMP-2",             dx=28.0,  dy=-14.0, heading=0.3 },
            { type="BMP-1",             dx=-32.0, dy=18.0,  heading=0.5 },
            { type="Ural-375 ZU-23",    dx=17.0,  dy=27.0,  heading=1.0 },
            { type="SA-18 Igla manpad", dx=-14.0, dy=-26.0, heading=0.8 },
            { type="Soldier RPG",       dx=9.0,   dy=-30.0, heading=1.2 },
            { type="Soldier AK",        dx=-10.0, dy=32.0,  heading=1.5 },
            { type="Soldier AK",        dx=6.0,   dy=38.0,  heading=0.1 },
        }
    },
    {
        name = "RED_SAM_SHORAD_Ins_2",
        units = {
            { type="HL_DSHK",           dx=0.0,   dy=0.0,   heading=0.0 },
            { type="BTR-80",            dx=24.0,  dy=-16.0, heading=0.4 },
            { type="HL_ZU-23",          dx=18.0,  dy=26.0,  heading=1.0 },
            { type="Soldier RPG",       dx=-8.0,  dy=30.0,  heading=1.1 },
            { type="SA-18 Igla manpad", dx=-20.0, dy=-24.0, heading=1.2 },
            { type="Infantry AK Ins",   dx=4.0,   dy=36.0,  heading=0.0 },
            { type="Osa 9A33 ln",       dx=-30.0, dy=-14.0, heading=0.6 },
        }
    },
    {
        name = "Ins_3",
        units = {
            { type="BMP-2",             dx=0.0,   dy=0.0,   heading=0.0 },
            { type="BMP-1",             dx=22.0,  dy=-14.0, heading=0.3 },
            { type="Ural-4320T",        dx=-24.0, dy=16.0,  heading=0.5 },
            { type="Soldier RPG",       dx=12.0,  dy=28.0,  heading=1.1 },
            { type="Infantry AK Ins",   dx=-14.0, dy=30.0,  heading=0.0 },
            { type="Infantry AK Ins",   dx=8.0,   dy=-24.0, heading=1.0 },
            { type="Infantry AK Ins",   dx=-10.0, dy=18.0,  heading=0.8 },
            { type="Soldier RPG",       dx=16.0,  dy=-18.0, heading=1.2 },
        }
    },
    {
        name = "Ins_4",
        units = {
            { type="T-55",              dx=0.0,   dy=0.0,   heading=0.0 },
            { type="BTR-60",            dx=26.0,  dy=-15.0, heading=0.4 },
            { type="Soldier RPG",       dx=14.0,  dy=28.0,  heading=1.1 },
            { type="Infantry AK Ins",        dx=-16.0, dy=32.0,  heading=0.0 },
            { type="Soldier RPG",       dx=15.0,  dy=28.0,  heading=1.1 },
            { type="Infantry AK Ins",        dx=-18.0, dy=32.0,  heading=0.0 },
            { type="SA-18 Igla manpad", dx=2.0,   dy=-30.0, heading=1.3 },
        }
    },
    {
        name = "Ins_5",
        units = {
            { type="Grad-URAL",         dx=0.0,   dy=0.0,   heading=0.5 },
            { type="Ural-4320T",        dx=0.0,   dy=20.0,  heading=0.5 },
            { type="HL_ZU-23",          dx=20.0,  dy=26.0,  heading=1.0 },
            { type="HL_KORD",           dx=-26.0, dy=18.0,  heading=0.4 },
            { type="Infantry AK Ins",        dx=8.0,   dy=-28.0, heading=1.0 },
            { type="Soldier RPG",       dx=15.0,  dy=28.0,  heading=1.1 },
            { type="Infantry AK Ins",        dx=-18.0, dy=32.0,  heading=0.0 },
        }
    },
    {
        name = "Ins_6",
        units = {
            { type="T-72B",             dx=0.0,   dy=0.0,   heading=0.0 },
            { type="T-55",              dx=32.0,  dy=-20.0, heading=0.3 },
            { type="BRDM-2",            dx=-26.0, dy=18.0,  heading=0.6 },
            { type="ZSU-23-4 Shilka",   dx=18.0,  dy=28.0,  heading=0.9 },
            { type="Soldier RPG",       dx=-12.0, dy=-22.0, heading=1.1 },
            { type="Infantry AK Ins",   dx=10.0,  dy=34.0,  heading=0.0 },
            { type="Infantry AK Ins",   dx=-16.0, dy=32.0,  heading=0.1 },
        }
    },
    {
        name = "Ins_7",
        units = {
            { type="Grad-URAL",         dx=0.0,   dy=0.0,   heading=0.5 },
            { type="T-55",              dx=30.0,  dy=-16.0, heading=0.2 },
            { type="HL_DSHK",           dx=-30.0, dy=14.0,  heading=0.7 },
            { type="tt_ZU-23",          dx=18.0,  dy=28.0,  heading=1.0 },
            { type="Soldier RPG",       dx=10.0,  dy=-30.0, heading=1.2 },
            { type="Soldier RPG",       dx=-12.0, dy=-26.0, heading=1.2 },
            { type="Infantry AK Ins",        dx=4.0,   dy=34.0,  heading=0.0 },
            { type="HL_KORD",        dx=-8.0,  dy=38.0,  heading=0.1 },
            { type="Infantry AK Ins",        dx=10.0,  dy=40.0,  heading=0.2 },
        }
    },
    {
        name = "Ins_8",
        units = {
            { type="BTR-80",            dx=0.0,   dy=0.0,   heading=0.3 },
            { type="Ural-375 ZU-23",    dx=26.0,  dy=-18.0, heading=0.7 },
            { type="Soldier RPG",       dx=12.0,  dy=30.0,  heading=1.2 },
            { type="SA-18 Igla manpad", dx=-18.0, dy=-26.0, heading=1.4 },
            { type="Infantry AK Ins",        dx=4.0,   dy=34.0,  heading=0.0 },
            { type="Infantry AK Ins",        dx=-10.0, dy=38.0,  heading=0.1 },
            { type="Infantry AK Ins",        dx=10.0,  dy=40.0,  heading=0.2 },
        }
    },
    {
        name = "Ins_9",
        units = {
            { type="BRDM-2",            dx=0.0,   dy=0.0,   heading=0.0 },
            { type="HL_KORD",           dx=20.0,  dy=-14.0, heading=0.4 },
            { type="HL_DSHK",           dx=-22.0, dy=12.0,  heading=0.7 },
            { type="Soldier RPG",       dx=10.0,  dy=26.0,  heading=1.1 },
            { type="Infantry AK Ins",   dx=-10.0, dy=28.0,  heading=0.0 },
            { type="Infantry AK Ins",   dx=14.0,  dy=-26.0, heading=1.2 },
            { type="Infantry AK Ins",   dx=-6.0,  dy=-18.0, heading=0.9 },
        }
    },
    {
        name = "RED_SAM_SHORAD_Ins_10",
        units = {
            { type="ZSU-23-4 Shilka",   dx=0.0,   dy=0.0,   heading=0.3 },
            { type="SA-18 Igla manpad", dx=-22.0, dy=18.0,  heading=1.0 },
            { type="SA-18 Igla manpad", dx=18.0,  dy=24.0,  heading=1.3 },
            { type="Ural-375 ZU-23",    dx=26.0,  dy=-16.0, heading=0.7 },
            { type="Infantry AK Ins",   dx=4.0,   dy=34.0,  heading=0.0 },
            { type="Infantry AK Ins",   dx=-10.0, dy=38.0,  heading=0.1 },
            { type="Osa 9A33 ln",       dx=-28.0, dy=-18.0, heading=0.9 },
        }
    },
    {
        name = "Ins_11",
        units = {
            { type="T-55",              dx=0.0,   dy=0.0,   heading=0.0 },
            { type="BTR-60",            dx=29.0,  dy=-18.0, heading=0.4 },
            { type="Infantry AK Ins",        dx=-26.0, dy=16.0,  heading=0.0 },
            { type="ZSU-23-4 Shilka",   dx=4.0,   dy=34.0,  heading=0.7 },
            { type="Infantry AK Ins",        dx=-10.0, dy=38.0,  heading=0.1 },
            { type="Infantry AK Ins",        dx=10.0,  dy=40.0,  heading=0.2 },
            { type="Infantry AK Ins",        dx=-4.0,  dy=44.0,  heading=0.3 },
        }
    },
    {
        name = "Ins_12",
        units = {
            { type="T-72B",             dx=0.0,   dy=0.0,   heading=0.0 },
            { type="BMP-2",             dx=28.0,  dy=-16.0, heading=0.3 },
            { type="BTR-80",            dx=-30.0, dy=14.0,  heading=0.6 },
            { type="HL_ZU-23",          dx=18.0,  dy=26.0,  heading=0.9 },
            { type="SA-18 Igla manpad", dx=-16.0, dy=-24.0, heading=1.2 },
            { type="Soldier RPG",       dx=12.0,  dy=30.0,  heading=1.1 },
            { type="Infantry AK Ins",   dx=-14.0, dy=32.0,  heading=0.0 },
            { type="Infantry AK Ins",   dx=8.0,   dy=-30.0, heading=1.0 },
        }
    },
    {
        name = "Ins_13",
        units = {
            { type="T-72B",             dx=0.0,   dy=0.0,   heading=0.0 },
            { type="T-55",              dx=28.0,  dy=-18.0, heading=0.3 },
            { type="BMP-2",             dx=-26.0, dy=16.0,  heading=0.6 },
            { type="SA-18 Igla manpad", dx=14.0,  dy=28.0,  heading=1.1 },
            { type="Ural-4320T",        dx=-16.0, dy=-22.0, heading=0.8 },
            { type="Soldier RPG",       dx=-8.0,  dy=30.0,  heading=1.0 },
            { type="Infantry AK Ins",   dx=10.0,  dy=-26.0, heading=1.2 },
        }
    },
    {
        name = "RED_SAM_SHORAD_Ins_14",
        units = {
            { type="Osa 9A33 ln",       dx=0.0,   dy=0.0,   heading=0.3 },
            { type="SA-18 Igla manpad", dx=-20.0, dy=16.0,  heading=1.0 },
            { type="SA-18 Igla manpad", dx=16.0,  dy=22.0,  heading=1.3 },
            { type="HL_ZU-23",          dx=24.0,  dy=-14.0, heading=0.7 },
            { type="Infantry AK Ins",   dx=-12.0, dy=28.0,  heading=0.0 },
            { type="Infantry AK Ins",   dx=8.0,   dy=32.0,  heading=0.1 },
        }
    },
    {
        name = "Ins_15",
        units = {
            { type="BMP-2",             dx=0.0,   dy=0.0,   heading=0.0 },
            { type="T-55",              dx=30.0,  dy=-18.0, heading=0.3 },
            { type="HL_KORD",           dx=-28.0, dy=16.0,  heading=0.6 },
            { type="Ural-375 ZU-23",    dx=16.0,  dy=28.0,  heading=0.9 },
            { type="Soldier RPG",       dx=-12.0, dy=-24.0, heading=1.1 },
            { type="Infantry AK Ins",   dx=8.0,   dy=32.0,  heading=0.0 },
            { type="Infantry AK Ins",   dx=-10.0, dy=34.0,  heading=0.1 },
            { type="Infantry AK Ins",   dx=12.0,  dy=-28.0, heading=1.2 },
        }
    },
    {
        name = "Ins_16",
        units = {
            { type="T-62",              dx=0.0,   dy=0.0,   heading=0.0 },
            { type="BMP-1",             dx=26.0,  dy=-18.0, heading=0.4 },
            { type="BTR-80",            dx=-24.0, dy=16.0,  heading=0.7 },
            { type="SA-18 Igla manpad", dx=14.0,  dy=28.0,  heading=1.1 },
            { type="Soldier RPG",       dx=-14.0, dy=30.0,  heading=1.0 },
            { type="Infantry AK Ins",   dx=16.0,  dy=-26.0, heading=1.1 },
        }
    },
    {
        name = "RED_SAM_SHORAD_Ins_17",
        units = {
            { type="Grad-URAL",         dx=0.0,   dy=0.0,   heading=0.5 },
            { type="2S1",               dx=-28.0, dy=18.0,  heading=0.4 },
            { type="Infantry AK Ins",   dx=16.0,  dy=30.0,  heading=1.1 },
            { type="Infantry AK Ins",   dx=8.0,   dy=-28.0, heading=1.1 },
            { type="SA-18 Igla manpad", dx=-18.0, dy=-26.0, heading=1.1 },
            { type="Ural-4320T",        dx=22.0,  dy=16.0,  heading=0.4 },
            { type="Osa 9A33 ln",       dx=-38.0, dy=-12.0, heading=0.8 },
            { type="ZSU-23-4 Shilka",   dx=34.0,  dy=-22.0, heading=0.3 },
        }
    },
    {
        name = "Ins_18",
        units = {
            { type="T-72B",             dx=0.0,   dy=0.0,   heading=0.0 },
            { type="BMP-2",             dx=26.0,  dy=-16.0, heading=0.3 },
            { type="BRDM-2",            dx=-24.0, dy=14.0,  heading=0.6 },
            { type="ZSU-23-4 Shilka",   dx=16.0,  dy=26.0,  heading=0.9 },
            { type="SA-18 Igla manpad", dx=-14.0, dy=-22.0, heading=1.2 },
            { type="Soldier RPG",       dx=10.0,  dy=28.0,  heading=1.1 },
            { type="Infantry AK Ins",   dx=-12.0, dy=30.0,  heading=0.0 },
            { type="Infantry AK Ins",   dx=8.0,   dy=-28.0, heading=1.0 },
        }
    },
    {
        name = "Ins_19",
        units = {
            { type="BTR-80",            dx=0.0,   dy=0.0,   heading=0.3 },
            { type="BMP-2",             dx=22.0,  dy=-18.0, heading=0.5 },
            { type="Soldier RPG",       dx=26.0,  dy=14.0,  heading=1.0 },
            { type="SA-18 Igla manpad", dx=-20.0, dy=-24.0, heading=1.1 },
            { type="Infantry AK Ins",   dx=14.0,  dy=28.0,  heading=1.2 },
            { type="Infantry AK Ins",   dx=-14.0, dy=30.0,  heading=0.0 },
            { type="ZSU-23-4 Shilka",   dx=-26.0, dy=16.0,  heading=0.7 },
        }
    },
    {
        name = "RED_SAM_SHORAD_Ins_20",
        units = {
            { type="Osa 9A33 ln",       dx=0.0,   dy=0.0,   heading=0.5 },
            { type="Strela-10M3",       dx=32.0,  dy=-20.0, heading=0.5 },
            { type="SA-18 Igla manpad", dx=-22.0, dy=18.0,  heading=0.2 },
            { type="SA-18 Igla manpad", dx=18.0,  dy=28.0,  heading=0.8 },
            { type="Infantry AK Ins",   dx=6.0,   dy=34.0,  heading=0.0 },
            { type="Infantry AK Ins",   dx=8.0,   dy=-32.0, heading=0.0 },
            { type="Infantry AK Ins",   dx=-8.0,  dy=-30.0, heading=0.0 },
        }
    },
}

-------------------------------------------------------------
-- GLOBAL SHUFFLE BAG
-------------------------------------------------------------

local shuffleBag = {}

local function shuffleTemplates()
    shuffleBag = {}
    for i = 1, #INSURGENT_TEMPLATES do
        shuffleBag[i] = INSURGENT_TEMPLATES[i]
    end

    -- Fisher-Yates shuffle
    for i = #shuffleBag, 2, -1 do
        local j = math.random(1, i)
        shuffleBag[i], shuffleBag[j] = shuffleBag[j], shuffleBag[i]
    end
end

local function getNextTemplate()
    if #shuffleBag == 0 then
        shuffleTemplates()
    end

    return table.remove(shuffleBag)
end

-- Initialize shuffle bag immediately
shuffleTemplates()

-------------------------------------------------------------
-- Zones
-------------------------------------------------------------

local zones = {"ZONE1","ZONE2","ZONE3","ZONE4","ZONE5","ZONE6","ZONE7","ZONE8","ZONE9","ZONE10","ZONE11",
               "ZONE12","ZONE13","ZONE14","ZONE15","ZONE16","ZONE17","ZONE18"}

-- Per-zone spawn settings
-- GLOBAL_MAX_GROUPS = 25 is the hard ceiling for total alive groups across all zones.
-- Per-zone maxes can theoretically sum to 28, but the global cap prevents exceeding 25.
-- ZONE1–5: min=2, max=3 (core high-density zones, always populated).
-- ZONE6–18: min=0, max=1 (opportunistic – only spawn when a global slot is free).
local GLOBAL_MAX_GROUPS = 25
local zoneSettings = {
    ZONE1  = { min = 2, max = 4 },
    ZONE2  = { min = 2, max = 3 },
    ZONE3  = { min = 1, max = 4 },
    ZONE4  = { min = 2, max = 3 },
    ZONE5  = { min = 1, max = 3 },
    ZONE6  = { min = 0, max = 2 },
    ZONE7  = { min = 0, max = 1 },
    ZONE8  = { min = 0, max = 2 },
    ZONE9  = { min = 0, max = 1 },
    ZONE10 = { min = 0, max = 1 },
    ZONE11 = { min = 0, max = 2 },
    ZONE12 = { min = 0, max = 1 },
    ZONE13 = { min = 0, max = 1 },
    ZONE14 = { min = 0, max = 2 },
    ZONE15 = { min = 0, max = 1 },
    ZONE16 = { min = 0, max = 1 },
    ZONE17 = { min = 0, max = 2 },
    ZONE18 = { min = 0, max = 1 },
}

-------------------------------------------------------------
-- Active Groups Tracking
-------------------------------------------------------------

-- activeGroups[groupName] = {
--   group    = Group object,
--   zone     = "ZONEX",
--   markerId = number or nil
-- }

local activeGroups = {}

-- Configuration

-------------------------------------------------------------
-- Visual Config
-------------------------------------------------------------

local ENABLE_SMOKE = false
local SMOKE_COLOR  = 1  -- orange (to avoid confusion with CSAR blue smoke)

-------------------------------------------------------------
-- Helpers
-------------------------------------------------------------

local function toVec3Ground(pos2d)
    local alt = land.getHeight({ x = pos2d.x, y = pos2d.y })
    return { x = pos2d.x, y = alt, z = pos2d.y }
end

-- Group death detection (must be defined before marker manager)
local function isGroupDead(groupName)
    local g = Group.getByName(groupName)
    if not g or not g:isExist() then
        return true
    end

    local units = g:getUnits()
    if not units or #units == 0 then
        return true
    end

    for _, u in ipairs(units) do
        if u and u:isExist() and u:getLife() > 0 then
            return false
        end
    end

    return true
end

local function placeSmoke(pos2d)
    if not ENABLE_SMOKE then
        return
    end
    local p3 = toVec3Ground(pos2d)
    trigger.action.smoke(p3, SMOKE_COLOR)
end

-------------------------------------------------------------
-- MARKER MANAGER (Simple & Robust)
-------------------------------------------------------------

local markerManager = {
    active  = {},      -- { groupName = markerId }
}

local function placeMarker(groupName, pos2d)
    -- Remove old marker if it exists
    if markerManager.active[groupName] then
        trigger.action.removeMark(markerManager.active[groupName])
    end
    
    local p3 = toVec3Ground(pos2d)
    local markerId = math.random(10000, 99999)
    trigger.action.markToAll(markerId, "Enemy Forces", p3, false)
    
    markerManager.active[groupName] = markerId
end

local function markerManagerCleanup()
    local toRemove = {}
    
    for groupName, markerId in pairs(markerManager.active) do
        -- Check if group is dead
        if isGroupDead(groupName) then
            trigger.action.removeMark(markerId)
            table.insert(toRemove, groupName)
        end
    end
    
    for _, groupName in ipairs(toRemove) do
        markerManager.active[groupName] = nil
    end
end

local function cleanupGroups()
    local toRemove = {}
    
    for groupName, data in pairs(activeGroups) do
        if isGroupDead(groupName) then
            table.insert(toRemove, groupName)
        end
    end
    
    for _, groupName in ipairs(toRemove) do
        activeGroups[groupName] = nil
    end
    
end

-------------------------------------------------------------
-- Memory Cleanup (Clean up dead group references)
-------------------------------------------------------------

local function performMemoryCleanup()
    local cleaned = 0
    
    -- Clean up dead groups from activeGroups table
    local deadGroups = {}
    for groupName, _ in pairs(activeGroups) do
        if isGroupDead(groupName) then
            table.insert(deadGroups, groupName)
        end
    end
    
    for _, groupName in ipairs(deadGroups) do
        activeGroups[groupName] = nil
        cleaned = cleaned + 1
    end
    
    -- Note: Physical wreckage is left for DCS to handle naturally
    -- This prevents memory leaks without causing script errors
end

-------------------------------------------------------------
-- Spawn Group in Zone (using trigger.misc.getZone)
-------------------------------------------------------------

spawnGroupInZone = function(zoneName)
    -- Get zone
    local z = trigger.misc.getZone(zoneName)
    if not z then
        env.info("[DGSS][ERROR] Zone not found: " .. tostring(zoneName))
        return
    end

    local MAX_ATTEMPTS = 5
    local spawnSuccess = false
    local finalGroupName = nil
    local finalPos2d = nil

    for attempt = 1, MAX_ATTEMPTS do
        -- Get polygon-safe point
        local pos2d

        if z.poly and #z.poly > 0 then
            pos2d = mist.getRandPointInPolygon(z)
            if not pos2d then
                env.info("[DGSS][ERROR] Polygon point failed for " .. zoneName)
                return
            end
        else
            -- Fallback for circular zones
            local center2d = { x = z.point.x, y = z.point.z }
            if z.radius then
                local r = z.radius * math.sqrt(math.random())
                local a = math.random() * 2 * math.pi
                pos2d = {
                    x = center2d.x + r * math.cos(a),
                    y = center2d.y + r * math.sin(a),
                }
            else
                pos2d = center2d
            end
        end

        -- Build group template
        local templateData = getNextTemplate()
        local t = math.floor(timer.getTime())

        -- Normal insurgent template
        local units = {}
        for i, u in ipairs(templateData.units) do
            units[#units+1] = {
                name    = templateData.name .. "_U" .. i .. "_" .. t,
                type    = u.type,
                x       = pos2d.x + u.dx,
                y       = pos2d.y + u.dy,
                heading = u.heading,
                skill   = "random",
            }
        end

        local groupName = templateData.name .. "_" .. t
        local groupTemplate = {
            country   = country.id.CJTF_RED,
            coalition = "red",
            category  = "vehicle",
            task      = "Ground Nothing",
            name      = groupName,
            units     = units
        }

        -- Try dynAdd
        local result = mist.dynAdd(groupTemplate)

        if result and result.name then
            local groupObj = Group.getByName(result.name)
            if groupObj and groupObj:isExist() then
                -- SUCCESS
                spawnSuccess   = true
                finalGroupName = result.name
                finalPos2d     = pos2d
                break
            end
        end

        env.info("[DGSS][WARN] dynAdd failed for " .. templateData.name .. " (attempt " .. attempt .. ")")
    end

    -- If all attempts failed
    if not spawnSuccess then
        env.info("[DGSS][ERROR] All spawn attempts failed for zone " .. zoneName)
        return
    end

    -- Verify the group exists with live units before registering
    local groupObj = Group.getByName(finalGroupName)
    if not groupObj or not groupObj:isExist() then
        env.info("[DGSS][ERROR] Group verification failed: " .. finalGroupName .. " does not exist")
        return
    end
    
    local units = groupObj:getUnits()
    if not units or #units == 0 then
        env.info("[DGSS][ERROR] Group verification failed: " .. finalGroupName .. " has no units")
        return
    end
    
    -- Register group
    activeGroups[finalGroupName] = {
        group    = groupObj,
        zone     = zoneName,
    }
    
    -- Place marker immediately after spawn
    placeMarker(finalGroupName, finalPos2d)
    placeSmoke(finalPos2d)

    return true
end

-------------------------------------------------------------
-- Outer Zone Randomisation
-------------------------------------------------------------

local OUTER_ZONES = {
    "ZONE6","ZONE7","ZONE8","ZONE9","ZONE10","ZONE11",
    "ZONE12","ZONE13","ZONE14","ZONE15","ZONE16","ZONE17","ZONE18"
}
local OUTER_BONUS_SLOTS = 5  -- how many outer zones get max=2 per cycle

local function reshuffleOuterZones()
    -- Reset all outer zones to max=1
    for _, z in ipairs(OUTER_ZONES) do
        if zoneSettings[z] then
            zoneSettings[z].max = 1
        end
    end
    -- Fisher-Yates partial shuffle: pick OUTER_BONUS_SLOTS random winners for max=2
    local pool = {}
    for i, z in ipairs(OUTER_ZONES) do pool[i] = z end
    local n = #pool
    for i = 1, math.min(OUTER_BONUS_SLOTS, n) do
        local j = math.random(i, n)
        pool[i], pool[j] = pool[j], pool[i]
        zoneSettings[pool[i]].max = 2
    end
end

-------------------------------------------------------------
-- Main Zone Check & Spawn Logic
-------------------------------------------------------------

local MAX_SPAWNS_PER_CYCLE = 18  -- Max new spawns allowed in a single cycle (rate limiter)

local function checkZones()
    cleanupGroups()
    reshuffleOuterZones()  -- randomise which outer zones get the bonus max=2 slots this cycle

    -- Count total currently alive groups across all zones
    local totalAlive = 0
    for _, data in pairs(activeGroups) do
        if data.group and data.group:isExist() then
            totalAlive = totalAlive + 1
        end
    end

    local spawnsThisCycle = 0

    for _, zoneName in ipairs(zones) do
        if spawnsThisCycle >= MAX_SPAWNS_PER_CYCLE then
            break  -- Hit rate limit, remaining spawns will happen in next cycle
        end
        if totalAlive >= GLOBAL_MAX_GROUPS then
            break  -- Global cap reached, no more spawns this cycle
        end

        local settings = zoneSettings[zoneName]
        if settings then
            local minReq = settings.min
            local maxReq = settings.max

            -- Count existing groups in this zone
            local count = 0
            for _, data in pairs(activeGroups) do
                if data.group and data.group:isExist() and data.zone == zoneName then
                    count = count + 1
                end
            end

            -- If below minimum, spawn enough to reach minimum
            if count < minReq then
                local needed = minReq - count
                for i = 1, needed do
                    if spawnsThisCycle >= MAX_SPAWNS_PER_CYCLE then
                        break  -- Hit rate limit
                    end
                    if totalAlive >= GLOBAL_MAX_GROUPS then break end
                    local spawned = spawnGroupInZone(zoneName)
                    if spawned then
                        spawnsThisCycle = spawnsThisCycle + 1
                        totalAlive = totalAlive + 1
                    end
                end

            -- If between min and max, spawn randomly up to max
            elseif count < maxReq then
                local remaining = maxReq - count
                local spawnCount = math.random(1, remaining)
                for i = 1, spawnCount do
                    if spawnsThisCycle >= MAX_SPAWNS_PER_CYCLE then
                        break  -- Hit rate limit
                    end
                    if totalAlive >= GLOBAL_MAX_GROUPS then break end
                    local spawned = spawnGroupInZone(zoneName)
                    if spawned then
                        spawnsThisCycle = spawnsThisCycle + 1
                        totalAlive = totalAlive + 1
                    end
                end
            end
        end
    end

    timer.scheduleFunction(checkZones, {}, timer.getTime() + 900)  -- Check every 900 seconds (15 minutes)
end

-------------------------------------------------------------
-- Periodic Cleanup Loop
-------------------------------------------------------------

local function cleanupLoop()
    cleanupGroups()
    markerManagerCleanup()  -- Clean up markers for dead groups
    
    return timer.getTime() + 120  -- check every 120 seconds (2 minutes)
end

-------------------------------------------------------------
-- Start System
-------------------------------------------------------------

checkZones()
timer.scheduleFunction(cleanupLoop, {}, timer.getTime() + 10)
mist.scheduleFunction(performMemoryCleanup, {}, timer.getTime() + 1200, 1200)  -- Run every 20 minutes