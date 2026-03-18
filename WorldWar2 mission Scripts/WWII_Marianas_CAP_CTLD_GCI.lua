-- =============================================================================
--  WWII Marianas – Combined CAP / CTLD / GCI Script
--  Version : 1.0  |  Map : Marianas  |  Era : WWII
--  Requires: MIST (4.5+) loaded BEFORE this script
--
--  LOAD ORDER in Mission Editor (DO Script File triggers at T=0):
--    1. mist_4_5_126.lua
--    2. WWII_Marianas_CAP_CTLD_GCI.lua  (this file)
--
--  FEATURES:
--    SECTION A – Red CAP Flights (auto-respawn patrol groups)
--    SECTION B – Red Fighter-Bombers (delayed spawn + respawn on death/landing)
--    SECTION C – Blue Radio-call Support Spawning (F10 menu)
--    SECTION D – Aircraft Cleanup System (health/fuel/stall/long-lived)
--    SECTION E – Lightweight TF-51D CTLD (infantry + crate logistics)
--    SECTION F – GCI Intercept System (zone-based scramble + RTB)
--
--  All groups must be set to Late Activation in the Mission Editor.
--  Group names in the script must match ME group names exactly.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION A – RED CAP FLIGHTS
-- ─────────────────────────────────────────────────────────────────────────────

local capGroups = {
    -- Rota
    "RotaCAPNorth",
    "RotaCAPSouth",
    -- Charon Kanoa (Saipan)
    "CAPCharonKanoa",
    "CAPCharonKanoa2",
    -- Ushi (Tinian)
    "CAPUshi",
    "CAPUshi2",
    -- Gurguan Point
    "CAPGurguan",
    "CAPGurguan2",
    -- Pagan
    "CAPPagan",
    "CAPPagan2",
}

local capSpawnTimers = {
    ["CAPCharonKanoa2"] = 300,   -- 5 minutes
    ["CAPUshi2"]        = 300,
    ["CAPGurguan2"]     = 300,
    ["CAPPagan2"]       = 300,
}

-- Map each CAP / bomber group to its home airbase key in ABC.REGISTRY.
-- If ABC.getOwner(key) ~= "RED", the group will NOT spawn or respawn.
local groupHomeBase = {
    -- Rota CAP
    RotaCAPNorth      = "RotaAirfield",
    RotaCAPSouth      = "RotaAirfield",
    -- New base CAP
    CAPCharonKanoa    = "CharonKanoa",
    CAPCharonKanoa2   = "CharonKanoa",
    CAPUshi           = "Ushi",
    CAPUshi2          = "Ushi",
    CAPGurguan        = "GurguanPoint",
    CAPGurguan2       = "GurguanPoint",
    CAPPagan          = "Pagan",
    CAPPagan2         = "Pagan",
    -- Rota bombers
    FighterBomber     = "RotaAirfield",
    FighterBomber2    = "RotaAirfield",
    Bombers           = "RotaAirfield",
    Bombers2          = "RotaAirfield",
    -- New base fighter-bombers
    FBCharonKanoa     = "CharonKanoa",
    FBUshi            = "Ushi",
    FBGurguan         = "GurguanPoint",
    FBPagan           = "Pagan",
}

local function isBaseRed(groupName)
    local key = groupHomeBase[groupName]
    if not key then return true end  -- unknown group, allow spawn
    if not ABC or not ABC.getOwner then return true end  -- ABC not loaded yet
    return ABC.getOwner(key) == "RED"
end

-- Map each CAP group to the trigger zone it should patrol.
-- After spawn, a scripted orbit + engagement-range cap replaces the ME
-- waypoints so the AI won't fly across the map to help other flights.
local capPatrolZone = {
    RotaCAPNorth      = "RED_ZONE_ROTA",
    RotaCAPSouth      = "RED_ZONE_ROTA",
    CAPCharonKanoa    = "RED_ZONE_CHARONKANOA",
    CAPCharonKanoa2   = "RED_ZONE_CHARONKANOA",
    CAPUshi           = "RED_ZONE_USHI",
    CAPUshi2          = "RED_ZONE_USHI",
    CAPGurguan        = "RED_ZONE_GURGUAN",
    CAPGurguan2       = "RED_ZONE_GURGUAN",
    CAPPagan          = "RED_ZONE_PAGAN",
    CAPPagan2         = "RED_ZONE_PAGAN",
}

local CAP_ORBIT_ALT   = 2500   -- metres
local CAP_ORBIT_SPEED = 120    -- m/s  (~430 km/h)

local function setCAPOrbitTask(groupName)
    local zoneName = capPatrolZone[groupName]
    if not zoneName then return end
    local zd = trigger.misc.getZone(zoneName)
    if not zd then return end
    local grp = Group.getByName(groupName)
    if not grp or not grp:isExist() then return end
    local ctrl = grp:getController()
    if not ctrl then return end
    -- Engage hostiles inside the zone; orbit its centre otherwise
    ctrl:setTask({
        id = "ComboTask",
        params = {
            tasks = {
                {
                    id = "EngageTargets",
                    params = {
                        maxDist     = zd.radius,
                        targetTypes = { "Air" },
                    },
                },
                {
                    id = "Orbit",
                    params = {
                        pattern  = "Circle",
                        speed    = CAP_ORBIT_SPEED,
                        altitude = CAP_ORBIT_ALT,
                        point    = { x = zd.point.x, y = zd.point.z },
                    },
                },
            },
        },
    })
end

local capRespawnDelay     = 300
local capCheckInterval    = 60
local capMaxPerZone       = 3
local capSpawned          = {}

local function countAirborneInZone(zoneName)
    local n = 0
    for _, gn in ipairs(capGroups) do
        if capPatrolZone[gn] == zoneName and capSpawned[gn] == true then
            local g = Group.getByName(gn)
            if g and g:isExist() then n = n + 1 end
        end
    end
    return n
end

local function checkAndRespawnCAP()
    for _, groupName in ipairs(capGroups) do
        if not isBaseRed(groupName) then
            -- Base lost: destroy any airborne CAP from this base
            local group = Group.getByName(groupName)
            if group and group:isExist() then group:destroy() end
            capSpawned[groupName] = false
        else
            local group = Group.getByName(groupName)
            local zn = capPatrolZone[groupName]
            if not capSpawned[groupName] then
                if capSpawnTimers[groupName] then
                    capSpawned[groupName] = "pending"
                elseif not zn or countAirborneInZone(zn) < capMaxPerZone then
                    mist.respawnGroup(groupName, true)
                    mist.scheduleFunction(setCAPOrbitTask, {groupName}, timer.getTime() + 5)
                    capSpawned[groupName] = true
                end
            elseif capSpawned[groupName] == true and (not group or not group:isExist()) then
                capSpawned[groupName] = false   -- mark dead so zone count is accurate
                mist.scheduleFunction(function()
                    if isBaseRed(groupName) then
                        local z = capPatrolZone[groupName]
                        if not z or countAirborneInZone(z) < capMaxPerZone then
                            mist.respawnGroup(groupName, true)
                            mist.scheduleFunction(setCAPOrbitTask, {groupName}, timer.getTime() + 5)
                            capSpawned[groupName] = true
                        end
                    end
                end, {}, timer.getTime() + capRespawnDelay)
            end
        end
    end
end

for groupName, spawnTime in pairs(capSpawnTimers) do
    mist.scheduleFunction(function()
        if isBaseRed(groupName) then
            local zn = capPatrolZone[groupName]
            if not zn or countAirborneInZone(zn) < capMaxPerZone then
                mist.respawnGroup(groupName, true)
                mist.scheduleFunction(setCAPOrbitTask, {groupName}, timer.getTime() + 5)
                capSpawned[groupName] = true
            end
        end
    end, {}, timer.getTime() + spawnTime)
end

mist.scheduleFunction(checkAndRespawnCAP, {}, timer.getTime() + 1, capCheckInterval)

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION B – RED FIGHTER-BOMBERS
-- ─────────────────────────────────────────────────────────────────────────────

local bomberGroups = {
    -- Rota (existing)
    { name = "FighterBomber",          spawnTime = 900  },
    { name = "FighterBomber2",         spawnTime = 1200 },
    { name = "Bombers",                spawnTime = 900  },
    { name = "Bombers2",               spawnTime = 1200 },
    -- Charon Kanoa
    { name = "FBCharonKanoa",          spawnTime = 900  },
    -- Ushi
    { name = "FBUshi",                 spawnTime = 900  },
    -- Gurguan Point
    { name = "FBGurguan",              spawnTime = 1200 },
    -- Pagan
    { name = "FBPagan",                spawnTime = 1200 },
}

local bomberRespawnDelay   = 1800
local bomberCheckInterval  = 30
local bomberSpawned        = {}
local bomberRespawnPending = {}

-- Startup validation: warn about bomber groups missing from MIST DB
for _, bomber in ipairs(bomberGroups) do
    local data = mist.getGroupData(bomber.name)
    if not data then
        env.warning(string.format(
            "[BOMBER] Group '%s' NOT found in MIST database! "
            .. "Create it as a Late Activation group in the Mission Editor.",
            bomber.name))
    end
end

local function isGroupLanded(group)
    if not group or not group:isExist() then return false end
    for _, unit in ipairs(group:getUnits()) do
        local vel   = unit:getVelocity()
        local speed = math.sqrt(vel.x^2 + vel.y^2 + vel.z^2)
        if speed > 1 or unit:getPoint().y > 3 then return false end
    end
    return true
end

for _, bomber in ipairs(bomberGroups) do
    mist.scheduleFunction(function()
        if isBaseRed(bomber.name) then
            local ok, err = pcall(mist.respawnGroup, bomber.name, true)
            if ok then
                bomberSpawned[bomber.name]        = true
                bomberRespawnPending[bomber.name]  = false
            else
                env.warning(string.format(
                    "[BOMBER] Failed to spawn '%s' – group may not exist as Late Activation in ME: %s",
                    bomber.name, tostring(err)))
            end
        end
    end, {}, timer.getTime() + bomber.spawnTime)
end

local function checkAndRespawnBombers()
    for _, bomber in ipairs(bomberGroups) do
        local gName = bomber.name
        local group = Group.getByName(gName)
        if not isBaseRed(gName) then
            -- Base lost: destroy any airborne bomber from this base
            if group and group:isExist() then group:destroy() end
            bomberSpawned[gName]        = false
            bomberRespawnPending[gName] = false
        elseif not bomberSpawned[gName] and not bomberRespawnPending[gName]
               and timer.getTime() > bomber.spawnTime + 60 then
            -- Initial spawn failed or was skipped; retry
            bomberRespawnPending[gName] = true
            mist.scheduleFunction(function()
                if isBaseRed(gName) then
                    local ok, err = pcall(mist.respawnGroup, gName, true)
                    if ok then
                        bomberSpawned[gName] = true
                    else
                        env.warning(string.format(
                            "[BOMBER] Retry failed for '%s': %s", gName, tostring(err)))
                    end
                end
                bomberRespawnPending[gName] = false
            end, {}, timer.getTime() + bomberRespawnDelay)
        elseif bomberSpawned[gName] then
            if (not group or not group:isExist()) and not bomberRespawnPending[gName] then
                bomberRespawnPending[gName] = true
                mist.scheduleFunction(function()
                    if isBaseRed(gName) then
                        mist.respawnGroup(gName, true)
                    end
                    bomberRespawnPending[gName] = false
                end, {}, timer.getTime() + bomberRespawnDelay)
            elseif group and group:isExist() and isGroupLanded(group) and not bomberRespawnPending[gName] then
                bomberRespawnPending[gName] = true
                group:destroy()
                mist.scheduleFunction(function()
                    if isBaseRed(gName) then
                        mist.respawnGroup(gName, true)
                    end
                    bomberRespawnPending[gName] = false
                end, {}, timer.getTime() + bomberRespawnDelay)
            end
        end
    end
end

mist.scheduleFunction(checkAndRespawnBombers, {}, timer.getTime() + 901, bomberCheckInterval)

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION C – BLUE RADIO-CALL SUPPORT SPAWNING (F10 Menu)
-- ─────────────────────────────────────────────────────────────────────────────

CAP_SUPPORT = {}
CAP_SUPPORT.BlueSupportTemplates = {
    "NorthCAP", "NorthCAP2", "HomeCAP",
    "CAPEast", "CAPWest",
    "Bomb_CoastalGun", "Bomb_RadioTower", "Bomb_RotaAirfield",
}
CAP_SUPPORT.originalAI   = {}
CAP_SUPPORT.activeGroups = {}

for _, gName in ipairs(CAP_SUPPORT.BlueSupportTemplates) do
    local g = Group.getByName(gName)
    if g then
        CAP_SUPPORT.originalAI[gName]   = mist.getGroupData(gName, 'country')
        CAP_SUPPORT.activeGroups[gName] = {}
    end
end

local function isSpawnedGroupLanded(group)
    if not group or not group:isExist() then return false end
    local units = group:getUnits()
    if not units or #units == 0 then return false end
    for _, unit in ipairs(units) do
        if unit and unit:isExist() then
            local vel   = unit:getVelocity()
            local speed = math.sqrt(vel.x^2 + vel.y^2 + vel.z^2)
            if speed > 1 or unit:getPoint().y > 3 then return false end
        end
    end
    return true
end

local function cleanupActiveGroups()
    for templateName, activeList in pairs(CAP_SUPPORT.activeGroups) do
        for i = #activeList, 1, -1 do
            local gn    = activeList[i]
            local group = Group.getByName(gn)
            if not group or not group:isExist() or isSpawnedGroupLanded(group) then
                if group and group:isExist() and isSpawnedGroupLanded(group) then
                    group:destroy()
                end
                table.remove(activeList, i)
            end
        end
    end
end

local function hasActiveGroups(templateName)
    local activeList = CAP_SUPPORT.activeGroups[templateName]
    if not activeList then return false end
    for _, gn in ipairs(activeList) do
        local group = Group.getByName(gn)
        if group and group:isExist() and not isSpawnedGroupLanded(group) then
            return true
        end
    end
    return false
end

function CAP_SUPPORT.spawnAI(name)
    if hasActiveGroups(name) then
        trigger.action.outText("ERROR: " .. name .. " already has active units!", 10)
        return
    end
    if not CAP_SUPPORT.originalAI[name] then
        trigger.action.outText("ERROR: Template '" .. tostring(name) .. "' not found!", 10)
        return
    end
    mist.respawnGroup(name, true)
    CAP_SUPPORT.activeGroups[name] = { name }
    trigger.action.outText(name .. " spawned.", 10)
end

function CAP_SUPPORT.destroyActiveGroups(templateName)
    local activeList = CAP_SUPPORT.activeGroups[templateName]
    if not activeList or #activeList == 0 then
        trigger.action.outText("No active groups for " .. templateName, 5)
        return
    end
    local ct = 0
    for i = #activeList, 1, -1 do
        local group = Group.getByName(activeList[i])
        if group and group:isExist() then group:destroy(); ct = ct + 1 end
        table.remove(activeList, i)
    end
    trigger.action.outText("Destroyed " .. ct .. " group(s) for " .. templateName, 10)
end

local capMenuGroups = {
    "NorthCAP", "NorthCAP2", "HomeCAP", "CAPEast", "CAPWest",
}
local bomberMenuGroups = {
    "Bomb_CoastalGun", "Bomb_RadioTower", "Bomb_RotaAirfield",
}

local function setupSupportMenus()
    if not missionCommands then return end
    local supportMenu = missionCommands.addSubMenuForCoalition(coalition.side.BLUE, "Support")
    local capMenu     = missionCommands.addSubMenuForCoalition(coalition.side.BLUE, "CAP Flights",  supportMenu)
    local bomberMenu  = missionCommands.addSubMenuForCoalition(coalition.side.BLUE, "Bombers",      supportMenu)
    local destroyMenu = missionCommands.addSubMenuForCoalition(coalition.side.BLUE, "Destroy Active Units", supportMenu)

    local function addSpawnCmd(gn, parentMenu)
        missionCommands.addCommandForCoalition(coalition.side.BLUE, "Spawn " .. gn, parentMenu, function()
            CAP_SUPPORT.spawnAI(gn)
        end)
        missionCommands.addCommandForCoalition(coalition.side.BLUE, "Destroy " .. gn, destroyMenu, function()
            CAP_SUPPORT.destroyActiveGroups(gn)
        end)
    end

    for _, gn in ipairs(capMenuGroups)    do addSpawnCmd(gn, capMenu)    end
    for _, gn in ipairs(bomberMenuGroups) do addSpawnCmd(gn, bomberMenu) end
end

mist.scheduleFunction(cleanupActiveGroups, {}, timer.getTime() + 30, 60)
mist.scheduleFunction(setupSupportMenus,   {}, timer.getTime() + 2)

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION C2 – BLUE DYNAMIC BOMBER MISSIONS (F10 Menu)
--    Players choose a bomber type + target island.  The script finds Red
--    ground / naval units inside the island's BOMB_ZONE trigger zone and
--    dispatches a cloned bomber flight to attack them.
--    Max 3 flights of each type airborne at once.
-- ─────────────────────────────────────────────────────────────────────────────

BOMBER_CMD = {}

BOMBER_CMD.templates = {
    { name = "LightBombers",  label = "Light Bombers",  altFt = 18000, speedKts = 300, isFighter = true  },
    { name = "MediumBombers", label = "Medium Bombers", altFt = 20000, speedKts = 250, isFighter = false },
    { name = "HeavyBombers",  label = "Heavy Bombers",  altFt = 25000, speedKts = 230, isFighter = false },
}

-- lookup by template name for quick access
BOMBER_CMD.profileByName = {}
for _, t in ipairs(BOMBER_CMD.templates) do
    BOMBER_CMD.profileByName[t.name] = t
end

BOMBER_CMD.zones = {
    { name = "BOMB_ZONE_ROTA",    label = "Rota"    },
    { name = "BOMB_ZONE_SAIPAN",  label = "Saipan"  },
    { name = "BOMB_ZONE_TINIAN",  label = "Tinian"  },
    { name = "BOMB_ZONE_PAGAN",   label = "Pagan"   },
    { name = "BOMB_ZONE_MAUG",    label = "Maug"    },
}

BOMBER_CMD.MAX_PER_TYPE = 3

-- RTB airfield on Guam (used for the landing waypoint)
BOMBER_CMD.RTB_AIRBASE = "Agana"

local function bomberLog(msg)  env.info("[BOMBER_CMD] " .. tostring(msg)) end

-- ── helpers ──────────────────────────────────────────────────────────────────

local function findRedTargetsInZone(zoneName)
    local zone = trigger.misc.getZone(zoneName)
    if not zone then
        bomberLog("Zone not found: " .. tostring(zoneName))
        return {}
    end
    local targets = {}
    local r2 = zone.radius * zone.radius

    -- Ground and naval units
    for _, cat in ipairs({ Group.Category.GROUND, Group.Category.SHIP }) do
        for _, grp in pairs(coalition.getGroups(coalition.side.RED, cat) or {}) do
            if grp and grp:isExist() then
                for _, unit in ipairs(grp:getUnits()) do
                    if unit and unit:isExist() and unit:getLife() > 1 then
                        local p  = unit:getPoint()
                        local dx = p.x - zone.point.x
                        local dz = p.z - zone.point.z
                        if dx * dx + dz * dz <= r2 then
                            targets[#targets + 1] = unit
                        end
                    end
                end
            end
        end
    end

    -- Static objects (buildings, fortifications, etc.)
    for _, obj in pairs(coalition.getStaticObjects(coalition.side.RED) or {}) do
        if obj and obj:isExist() and obj:getLife() > 1 then
            local p  = obj:getPoint()
            local dx = p.x - zone.point.x
            local dz = p.z - zone.point.z
            if dx * dx + dz * dz <= r2 then
                targets[#targets + 1] = obj
            end
        end
    end

    return targets
end

local function shuffleTable(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
end

-- ── slot discovery ───────────────────────────────────────────────────────────
-- Look for ME groups: <template>, <template>_2, <template>_3, …
-- Each discovered group is a "slot" that can be dispatched independently.
-- With just the base template you get 1 flight per type; duplicate the group
-- in the Mission Editor (e.g. LightBombers_2, LightBombers_3) for more.

BOMBER_CMD.slots     = {}   -- [baseName] = { "LightBombers", "LightBombers_2", … }
BOMBER_CMD.slotInUse = {}   -- [slotGroupName] = true/false

for _, t in ipairs(BOMBER_CMD.templates) do
    local found = {}
    if mist.getGroupData(t.name) then
        found[#found + 1] = t.name
        BOMBER_CMD.slotInUse[t.name] = false
    end
    for i = 2, BOMBER_CMD.MAX_PER_TYPE do
        local slotName = t.name .. "_" .. i
        if mist.getGroupData(slotName) then
            found[#found + 1] = slotName
            BOMBER_CMD.slotInUse[slotName] = false
        end
    end
    BOMBER_CMD.slots[t.name] = found
    if #found > 0 then
        bomberLog(string.format("%s: %d slot(s) available in ME", t.name, #found))
    else
        bomberLog("WARNING: no ME groups found for " .. t.name)
    end
end

local function findFreeSlot(templateName)
    local slots = BOMBER_CMD.slots[templateName]
    if not slots then return nil end
    for _, slotName in ipairs(slots) do
        if not BOMBER_CMD.slotInUse[slotName] then
            return slotName
        end
    end
    return nil
end

-- ── spawn via mist.respawnGroup + mist.goRoute ──────────────────────────────
-- Uses the same proven approach as Section A (CAP): activate the ME template
-- group, then reassign the route + tasks via mist.goRoute.

local function spawnBomberMission(templateName, slotName, targets, zoneName)
    local profile   = BOMBER_CMD.profileByName[templateName]
    local altM      = profile and (profile.altFt * 0.3048) or 6096
    local spdMs     = (profile and profile.speedKts or 250) * 0.5144
    local isFighter = profile and profile.isFighter or false

    -- Pick up to 6 random targets for attack tasks
    shuffleTable(targets)
    local attackTasks = {}
    local n = math.min(#targets, 6)
    for i = 1, n do
        if targets[i] and targets[i]:isExist() then
            attackTasks[#attackTasks + 1] = {
                id = "AttackUnit",
                params = {
                    unitId          = targets[i]:getID(),
                    groupAttack     = true,
                    weaponType      = 2147485694,
                    altitudeEnabled = true,
                    altitude        = altM,
                },
            }
        end
    end

    if not isFighter then
        table.insert(attackTasks, 1, {
            id = "EngageTargets",
            params = {
                maxDist     = 305,
                targetTypes = { "Air" },
                priority    = 0,
            },
        })
    end

    if #attackTasks == 0 then
        bomberLog("No valid attack tasks — aborting spawn")
        return nil
    end

    -- Zone centre for ingress waypoint
    local zone = trigger.misc.getZone(zoneName)
    local zx   = zone and zone.point.x or targets[1]:getPoint().x
    local zz   = zone and zone.point.z or targets[1]:getPoint().z

    -- RTB airfield
    local rtbBase = Airbase.getByName(BOMBER_CMD.RTB_AIRBASE)
    local rtbPt   = rtbBase and rtbBase:getPoint()

    -- ► Spawn via proven mist.respawnGroup (same as Section A CAP)
    local ok, err = pcall(mist.respawnGroup, slotName, true)
    if not ok then
        bomberLog("respawnGroup ERROR for " .. slotName .. ": " .. tostring(err))
        return nil
    end

    local grp = Group.getByName(slotName)
    if not grp or not grp:isExist() then
        bomberLog(slotName .. " did not appear after respawnGroup")
        return nil
    end
    bomberLog("Spawned: " .. slotName)
    BOMBER_CMD.slotInUse[slotName] = true

    -- ► Assign dynamic route + attack tasks after DCS finishes initialising
    mist.scheduleFunction(function()
        local group = Group.getByName(slotName)
        if not group or not group:isExist() then
            BOMBER_CMD.slotInUse[slotName] = false
            bomberLog(slotName .. " gone before route could be set — slot freed")
            return
        end

        local unit1 = group:getUnit(1)
        if not unit1 or not unit1:isExist() then return end
        local pos = unit1:getPoint()

        -- Build route points
        local routePoints = {}
        local wpIdx = 1

        if pos.y < 100 and rtbBase then
            -- Aircraft is on/near the ground → take off first
            routePoints[wpIdx] = {
                x           = pos.x,
                y           = pos.z,
                alt         = 13,
                alt_type    = "BARO",
                speed       = spdMs,
                action      = "From Parking Area Hot",
                type        = "TakeOffParkingHot",
                aerodromeId = rtbBase:getID(),
            }
            wpIdx = wpIdx + 1
        end

        -- Ingress waypoint at target zone (carries attack tasks)
        routePoints[wpIdx] = {
            x        = zx,
            y        = zz,
            alt      = altM,
            alt_type = "BARO",
            speed    = spdMs,
            action   = "Fly Over Point",
            type     = "Turning Point",
            task     = {
                id = "ComboTask",
                params = { tasks = attackTasks },
            },
        }
        wpIdx = wpIdx + 1

        -- RTB landing waypoint
        if rtbPt then
            routePoints[wpIdx] = {
                x           = rtbPt.x,
                y           = rtbPt.z,
                alt         = 300,
                alt_type    = "BARO",
                speed       = 80,
                action      = "Landing",
                type        = "Land",
                aerodromeId = rtbBase:getID(),
            }
        end

        -- Apply the new route (replaces whatever the ME template had)
        mist.goRoute(slotName, routePoints)

        -- Set AI options
        local ctrl = group:getController()
        ctrl:setOption(AI.Option.Air.id.ROE,
                       AI.Option.Air.val.ROE.OPEN_FIRE)
        if isFighter then
            ctrl:setOption(AI.Option.Air.id.REACTION_ON_THREAT,
                           AI.Option.Air.val.REACTION_ON_THREAT.ALLOW_ABORT_MISSION)
        else
            ctrl:setOption(AI.Option.Air.id.REACTION_ON_THREAT,
                           AI.Option.Air.val.REACTION_ON_THREAT.BYPASS_AND_ESCAPE)
        end

        bomberLog(string.format("%s tasked on %d targets at %d ft (%s)",
                  slotName, #attackTasks, profile and profile.altFt or 20000,
                  isFighter and "fighter defense" or "turret defense"))
    end, {}, timer.getTime() + 5)

    return slotName
end

-- Check if a bomber group has landed and stopped
local function isBomberLanded(group)
    if not group or not group:isExist() then return false end
    for _, unit in ipairs(group:getUnits()) do
        if unit and unit:isExist() then
            local vel   = unit:getVelocity()
            local speed = math.sqrt(vel.x^2 + vel.y^2 + vel.z^2)
            if speed > 1 or unit:getPoint().y > 5 then return false end
        end
    end
    return true
end

-- Check if every unit in the group is effectively dead (health < 15%)
local function isBomberGroupDead(group)
    if not group or not group:isExist() then return true end
    for _, unit in ipairs(group:getUnits()) do
        if unit and unit:isExist() and (unit:getLife() / unit:getLife0()) >= 0.15 then
            return false
        end
    end
    return true
end

-- Purge dead / landed flights from tracking and free slots
local function cleanupBomberFlights()
    for templateName, slots in pairs(BOMBER_CMD.slots) do
        for _, slotName in ipairs(slots) do
            if BOMBER_CMD.slotInUse[slotName] then
                local group = Group.getByName(slotName)
                if not group or not group:isExist() then
                    BOMBER_CMD.slotInUse[slotName] = false
                    bomberLog(slotName .. " no longer exists — slot freed")
                elseif isBomberLanded(group) then
                    group:destroy()
                    BOMBER_CMD.slotInUse[slotName] = false
                    bomberLog(slotName .. " landed — slot freed")
                elseif isBomberGroupDead(group) then
                    group:destroy()
                    BOMBER_CMD.slotInUse[slotName] = false
                    bomberLog(slotName .. " dead — slot freed")
                end
            end
        end
    end
end

-- ── dispatch ─────────────────────────────────────────────────────────────────

function BOMBER_CMD.dispatch(templateName, templateLabel, zoneName, zoneLabel)
    local slotName = findFreeSlot(templateName)
    if not slotName then
        local nSlots = #(BOMBER_CMD.slots[templateName] or {})
        trigger.action.outTextForCoalition(coalition.side.BLUE,
            string.format("%s: all %d flight(s) already airborne!", templateLabel, nSlots), 10)
        return
    end

    local targets = findRedTargetsInZone(zoneName)
    if #targets == 0 then
        trigger.action.outTextForCoalition(coalition.side.BLUE,
            "No enemy targets detected on " .. zoneLabel .. ".", 10)
        return
    end

    local result = spawnBomberMission(templateName, slotName, targets, zoneName)
    if not result then
        trigger.action.outTextForCoalition(coalition.side.BLUE,
            "ERROR: could not launch " .. templateLabel, 10)
        return
    end

    local activeCount = 0
    for _, sn in ipairs(BOMBER_CMD.slots[templateName]) do
        if BOMBER_CMD.slotInUse[sn] then activeCount = activeCount + 1 end
    end
    local totalSlots = #BOMBER_CMD.slots[templateName]

    trigger.action.outTextForCoalition(coalition.side.BLUE,
        string.format("%s dispatched to %s  —  %d targets found  [%d/%d active]",
            templateLabel, zoneLabel, #targets, activeCount, totalSlots), 15)
    bomberLog(string.format("Dispatched %s → %s (%d targets)", slotName, zoneLabel, #targets))
end

-- ── F10 radio menu ───────────────────────────────────────────────────────────

local function setupBomberMenus()
    local mainMenu = missionCommands.addSubMenuForCoalition(
                         coalition.side.BLUE, "Bomber Missions")

    for _, tmpl in ipairs(BOMBER_CMD.templates) do
        local typeMenu = missionCommands.addSubMenuForCoalition(
                             coalition.side.BLUE, tmpl.label, mainMenu)
        for _, z in ipairs(BOMBER_CMD.zones) do
            local tName, tLabel, zName, zLabel = tmpl.name, tmpl.label, z.name, z.label
            missionCommands.addCommandForCoalition(coalition.side.BLUE,
                "Send to " .. zLabel, typeMenu,
                function() BOMBER_CMD.dispatch(tName, tLabel, zName, zLabel) end)
        end
    end

    missionCommands.addCommandForCoalition(coalition.side.BLUE,
        "Flight Status", mainMenu, function()
            local lines = { "=== Bomber Mission Status ===" }
            for _, tmpl in ipairs(BOMBER_CMD.templates) do
                local slots = BOMBER_CMD.slots[tmpl.name] or {}
                local active = 0
                for _, sn in ipairs(slots) do
                    if BOMBER_CMD.slotInUse[sn] then active = active + 1 end
                end
                lines[#lines + 1] = string.format(
                    "  %s: %d/%d active", tmpl.label, active, #slots)
            end
            trigger.action.outTextForCoalition(coalition.side.BLUE,
                table.concat(lines, "\n"), 15)
        end)

    bomberLog("Radio menus created")
end

mist.scheduleFunction(setupBomberMenus,      {}, timer.getTime() + 3)
mist.scheduleFunction(cleanupBomberFlights,  {}, timer.getTime() + 60, 60)

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION D – AIRCRAFT CLEANUP SYSTEM
-- ─────────────────────────────────────────────────────────────────────────────

local AircraftCleanup = {}
AircraftCleanup.monitoredGroups = {
    -- Rota CAP (existing)
    "RotaCAPNorth","RotaCAPSouth",
    -- New base CAP
    "CAPCharonKanoa","CAPCharonKanoa2",
    "CAPUshi","CAPUshi2",
    "CAPGurguan","CAPGurguan2",
    "CAPPagan","CAPPagan2",
    -- Bombers / Fighter-Bombers
    "FighterBomber","FighterBomber2","Bombers","Bombers2",
    "FBCharonKanoa","FBUshi","FBGurguan","FBPagan",
}

local function isAircraftEffectivelyDead(unit)
    if not unit or not unit:isExist() then return true end
    local healthPct = (unit:getLife() / unit:getLife0()) * 100
    if healthPct < 15 then return true end
    if unit:getFuel() < 0.05 then return true end
    local vel   = unit:getVelocity()
    local speed = math.sqrt(vel.x^2 + vel.y^2 + vel.z^2)
    if speed < 15 and unit:getPoint().y > 100 then return true end
    return false
end

local function cleanupDeadAircraft()
    for _, groupName in ipairs(AircraftCleanup.monitoredGroups) do
        local group = Group.getByName(groupName)
        if group and group:isExist() then
            local units = group:getUnits()
            if units then
                for _, unit in ipairs(units) do
                    if unit and isAircraftEffectivelyDead(unit) then
                        group:destroy()
                        if capSpawned[groupName]  then capSpawned[groupName]  = false end
                        if bomberSpawned[groupName] then bomberSpawned[groupName] = false end
                        break
                    end
                end
            end
        end
    end
end

local groupSpawnTimes = {}

local function cleanupLongLivedGroups()
    local maxFlightTime = 5400
    local now = timer.getTime()
    for _, groupName in ipairs(AircraftCleanup.monitoredGroups) do
        local group = Group.getByName(groupName)
        if group and group:isExist() then
            if not groupSpawnTimes[groupName] then groupSpawnTimes[groupName] = now end
            if (now - groupSpawnTimes[groupName]) > maxFlightTime then
                group:destroy()
                groupSpawnTimes[groupName] = nil
                if capSpawned[groupName]    then capSpawned[groupName]    = false end
                if bomberSpawned[groupName] then bomberSpawned[groupName] = false end
            end
        else
            groupSpawnTimes[groupName] = nil
        end
    end
end

mist.scheduleFunction(function()
    groupSpawnTimes = {}
    mist.scheduleFunction(cleanupDeadAircraft,    {}, timer.getTime() + 300, 300)
    mist.scheduleFunction(cleanupLongLivedGroups, {}, timer.getTime() + 600, 600)
end, {}, timer.getTime() + 60)

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION E – WWII TF-51D CTLD  (Troop & Crate Transport)
--  Based on Syria DGSS-CTLD architecture: per-player menus, coalition.addGroup
--  spawning, speed/altitude checks, crash cleanup.
-- ─────────────────────────────────────────────────────────────────────────────

WWII_CTLD = {}

----------------------------------------------------------------
-- CONFIGURATION
----------------------------------------------------------------

WWII_CTLD.COUNTRY   = country.id.USA
WWII_CTLD.COALITION = coalition.side.BLUE

WWII_CTLD.ZONES = { { name = "BlueCTLD" } }

WWII_CTLD.VALID_TRANSPORT = { ["TF-51D"] = true }
WWII_CTLD.CAPACITY        = { ["TF-51D"] = 3 }

WWII_CTLD.MAX_LOAD_SPEED    = 5.1   -- m/s  (~10 knots)
WWII_CTLD.MAX_LOAD_ALTITUDE = 7.6   -- m AGL (~25 feet)

----------------------------------------------------------------
-- TROOP TEMPLATES  (category-organised, same style as Syria)
----------------------------------------------------------------

WWII_CTLD.TROOP_TEMPLATES = {
    ["Infantry Squad"] = {
        namePrefix  = "INF_SQUAD",
        displayName = "Infantry Squad",
        category    = "Infantry",
        units = { "soldier_wwii_us", "soldier_wwii_us", "soldier_wwii_us" },
    },
    ["Infantry Fireteam"] = {
        namePrefix  = "INF_FIRE",
        displayName = "Infantry Fireteam",
        category    = "Infantry",
        units = { "soldier_wwii_us", "soldier_wwii_us" },
    },
    ["Single Soldier"] = {
        namePrefix  = "INF_SOLO",
        displayName = "Single Soldier",
        category    = "Infantry",
        units = { "soldier_wwii_us" },
    },
}

----------------------------------------------------------------
-- VEHICLE CRATE DEFINITIONS
----------------------------------------------------------------

WWII_CTLD.VEHICLE_CRATES = {
    { name = "M4 Tractor",     type = "M4_Tractor",     cratesRequired = 2 },
    { name = "M2A1 Halftrack", type = "M2A1_halftrack",  cratesRequired = 2 },
    { name = "M4 Sherman",     type = "M4_Sherman",      cratesRequired = 3 },
}

----------------------------------------------------------------
-- INTERNAL STATE
----------------------------------------------------------------

WWII_CTLD.UNIT_MENUS      = {}   -- per-unit menu handles
WWII_CTLD.AIRCRAFT_TROOPS = {}   -- unitName -> list of { id, templateName, count, units }
WWII_CTLD.AIRCRAFT_CRATE  = {}   -- unitName -> { crateName, vehicleType }
WWII_CTLD.SPAWNED_GROUPS  = {}   -- groupName -> { kind, templateName, id, count }
WWII_CTLD.WORLD_CRATES    = {}   -- crateName -> { vehicleType, x, z }
WWII_CTLD.GROUP_COUNTER   = 0

----------------------------------------------------------------
-- UTILITY HELPERS
----------------------------------------------------------------

function WWII_CTLD.generateGroupName(prefix)
    WWII_CTLD.GROUP_COUNTER = WWII_CTLD.GROUP_COUNTER + 1
    return string.format("%s_%04d", prefix or "CTLD", WWII_CTLD.GROUP_COUNTER)
end

local function ctldSqrDist(p1, p2)
    local dx = p1.x - p2.x
    local dz = p1.z - p2.z
    return dx * dx + dz * dz
end

----------------------------------------------------------------
-- ZONE HELPERS
----------------------------------------------------------------

function WWII_CTLD.isInsideZone(point, zoneName)
    local z
    pcall(function() z = trigger.misc.getZone(zoneName) end)
    if not z then return false end
    if z.point and z.radius then
        local dx = point.x - z.point.x
        local dz = point.z - z.point.z
        return dx * dx + dz * dz <= z.radius * z.radius
    end
    return false
end

function WWII_CTLD.isInsideAnyCTLDZone(point)
    for _, z in ipairs(WWII_CTLD.ZONES) do
        if WWII_CTLD.isInsideZone(point, z.name) then return true end
    end
    return false
end

----------------------------------------------------------------
-- TRANSPORT VALIDATION
----------------------------------------------------------------

function WWII_CTLD.isValidTransport(unit)
    if not unit or not unit:isExist() then return false end
    return WWII_CTLD.VALID_TRANSPORT[unit:getTypeName()] == true
end

function WWII_CTLD.checkLoadUnloadConditions(unit, isLoad)
    if not unit or not unit:isExist() then return false, "Unit not found" end
    local vel   = unit:getVelocity()
    local speed = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
    if speed > WWII_CTLD.MAX_LOAD_SPEED then
        return false, string.format("Too fast! (%.0f kts, max 10 kts)", speed * 1.944)
    end
    local pos   = unit:getPoint()
    local landY = land.getHeight({ x = pos.x, y = pos.z })
    local agl   = pos.y - landY
    if agl > WWII_CTLD.MAX_LOAD_ALTITUDE then
        return false, string.format("Too high! (%.0f ft AGL, max 25 ft)", agl * 3.281)
    end
    return true, nil
end

----------------------------------------------------------------
-- TROOP STORAGE HELPERS
----------------------------------------------------------------

local function ensureAircraftTroopTable(unitName)
    if not WWII_CTLD.AIRCRAFT_TROOPS[unitName] then
        WWII_CTLD.AIRCRAFT_TROOPS[unitName] = {}
    end
end

----------------------------------------------------------------
-- TROOPS: SPAWN / LOAD / UNLOAD
----------------------------------------------------------------

function WWII_CTLD.spawnTroopsAtUnit(unit, templateName)
    if not unit or not unit:isExist() then return end
    local pos = unit:getPoint()

    if not WWII_CTLD.isInsideAnyCTLDZone(pos) then
        trigger.action.outTextForUnit(unit:getID(),
            "Must be inside a CTLD zone to spawn troops!", 5)
        return
    end

    local template = WWII_CTLD.TROOP_TEMPLATES[templateName]
    if not template then return end

    local units = {}
    for _, unitType in ipairs(template.units) do
        table.insert(units, {
            type    = unitType,
            x       = pos.x + math.random(15, 20),
            y       = pos.z + math.random(15, 20),
            heading = math.random() * 6.28,
        })
    end

    local groupName = WWII_CTLD.generateGroupName(template.namePrefix)
    local group = coalition.addGroup(
        WWII_CTLD.COUNTRY,
        Group.Category.GROUND,
        { name = groupName, units = units }
    )

    if group then
        WWII_CTLD.SPAWNED_GROUPS[groupName] = {
            kind         = "troops",
            templateName = templateName,
            id           = groupName,
            count        = #units,
        }
        trigger.action.outTextForUnit(unit:getID(),
            string.format("Troops spawned: %s (%d)", template.displayName, #units), 5)
    else
        trigger.action.outTextForUnit(unit:getID(), "Failed to spawn troops!", 5)
    end
end

function WWII_CTLD.getNearbyTroopGroups(pos, maxDist)
    local results = {}
    local maxSq   = maxDist * maxDist

    for groupName, data in pairs(WWII_CTLD.SPAWNED_GROUPS) do
        if data.kind == "troops" then
            local g = Group.getByName(groupName)
            if g and g:isExist() then
                local u = g:getUnit(1)
                if u and u:isExist() then
                    local d = ctldSqrDist(pos, u:getPoint())
                    if d <= maxSq then
                        table.insert(results, { name = groupName, meta = data, distSq = d })
                    end
                end
            end
        end
    end

    table.sort(results, function(a, b) return a.distSq < b.distSq end)
    return results
end

function WWII_CTLD.loadNearestTroops(unit)
    if not unit or not unit:isExist() then return end

    if not WWII_CTLD.isValidTransport(unit) then
        trigger.action.outTextForUnit(unit:getID(),
            "This aircraft cannot load troops.", 5)
        return
    end

    local condOk, condMsg = WWII_CTLD.checkLoadUnloadConditions(unit, true)
    if not condOk then
        trigger.action.outTextForUnit(unit:getID(), condMsg, 6)
        return
    end

    local pos    = unit:getPoint()
    local nearby = WWII_CTLD.getNearbyTroopGroups(pos, 75)

    if #nearby == 0 then
        trigger.action.outTextForUnit(unit:getID(),
            "No nearby troops to load! (within 75 m)", 5)
        return
    end

    local nearest = nearby[1]
    local g = Group.getByName(nearest.name)
    if not g or not g:isExist() then
        WWII_CTLD.SPAWNED_GROUPS[nearest.name] = nil
        return
    end

    local meta     = nearest.meta
    local grpUnits = g:getUnits()
    local count    = #grpUnits

    local unitName = unit:getName()
    local capacity = WWII_CTLD.CAPACITY[unit:getTypeName()] or 0
    ensureAircraftTroopTable(unitName)

    local currentCount = 0
    for _, grp in ipairs(WWII_CTLD.AIRCRAFT_TROOPS[unitName]) do
        currentCount = currentCount + (grp.count or 0)
    end

    if currentCount + count > capacity then
        trigger.action.outTextForUnit(unit:getID(),
            string.format("Not enough capacity! Onboard: %d/%d, group: %d",
                currentCount, capacity, count), 6)
        return
    end

    local unitTypes = {}
    for _, u in ipairs(grpUnits) do table.insert(unitTypes, u:getTypeName()) end

    table.insert(WWII_CTLD.AIRCRAFT_TROOPS[unitName], {
        id           = meta.id,
        templateName = meta.templateName,
        count        = count,
        units        = unitTypes,
    })

    g:destroy()
    WWII_CTLD.SPAWNED_GROUPS[nearest.name] = nil

    trigger.action.outTextForUnit(unit:getID(),
        string.format("Loaded %s (%d)", meta.templateName, count), 6)
end

function WWII_CTLD.unloadAllTroops(unit)
    if not unit or not unit:isExist() then return end

    local condOk, condMsg = WWII_CTLD.checkLoadUnloadConditions(unit, false)
    if not condOk then
        trigger.action.outTextForUnit(unit:getID(), condMsg, 6)
        return
    end

    local unitName = unit:getName()
    local onboard  = WWII_CTLD.AIRCRAFT_TROOPS[unitName]
    if not onboard or #onboard == 0 then
        trigger.action.outTextForUnit(unit:getID(), "No troops onboard!", 5)
        return
    end

    local pos        = unit:getPoint()
    local totalCount = 0

    for _, grp in ipairs(onboard) do
        local units = {}
        for _, unitType in ipairs(grp.units or {}) do
            table.insert(units, {
                type    = unitType,
                x       = pos.x + math.random(15, 20),
                y       = pos.z + math.random(15, 20),
                heading = math.random() * 6.28,
            })
        end

        local groupName = WWII_CTLD.generateGroupName("TROOPS")
        local spawnedGrp = coalition.addGroup(
            WWII_CTLD.COUNTRY,
            Group.Category.GROUND,
            { name = groupName, units = units }
        )
        if spawnedGrp then
            WWII_CTLD.SPAWNED_GROUPS[groupName] = {
                kind         = "troops",
                templateName = grp.templateName,
                id           = groupName,
                count        = #units,
            }
        end
        totalCount = totalCount + grp.count
    end

    WWII_CTLD.AIRCRAFT_TROOPS[unitName] = {}
    trigger.action.outTextForUnit(unit:getID(),
        string.format("Unloaded %d troops!", totalCount), 6)
end

----------------------------------------------------------------
-- CRATES: SPAWN / PICKUP / DROP / ASSEMBLE
----------------------------------------------------------------

function WWII_CTLD.spawnCrate(unit, optIdx)
    if not unit or not unit:isExist() then return end
    local pos = unit:getPoint()

    if not WWII_CTLD.isInsideAnyCTLDZone(pos) then
        trigger.action.outTextForUnit(unit:getID(),
            "Must be inside a CTLD zone to spawn crates!", 5)
        return
    end

    local opt = WWII_CTLD.VEHICLE_CRATES[optIdx]
    if not opt then return end

    local crateName = WWII_CTLD.generateGroupName("CRATE_" .. opt.type)
    local cx = pos.x + math.random(10, 20)
    local cz = pos.z + math.random(10, 20)

    mist.dynAddStatic({
        country    = country.id.USA,
        category   = "Cargos",
        shape_name = "uh1h_cargo",
        type       = "uh1h_cargo",
        x          = cx,
        y          = cz,
        name       = crateName,
        heading    = 0,
        canCargo   = true,
    })

    WWII_CTLD.WORLD_CRATES[crateName] = { vehicleType = opt.type, x = cx, z = cz }
    trigger.action.outTextForUnit(unit:getID(),
        string.format("Crate spawned: %s (%d needed)", opt.name, opt.cratesRequired), 5)
end

function WWII_CTLD.pickupCrate(unit)
    if not unit or not unit:isExist() then return end

    if not WWII_CTLD.isValidTransport(unit) then
        trigger.action.outTextForUnit(unit:getID(),
            "This aircraft cannot transport crates.", 5)
        return
    end

    local condOk, condMsg = WWII_CTLD.checkLoadUnloadConditions(unit, true)
    if not condOk then
        trigger.action.outTextForUnit(unit:getID(), condMsg, 6)
        return
    end

    local unitName = unit:getName()
    if WWII_CTLD.AIRCRAFT_CRATE[unitName] then
        trigger.action.outTextForUnit(unit:getID(), "Already carrying a crate!", 5)
        return
    end

    local pos = unit:getPoint()
    local nearestName, nearestDist = nil, 50 * 50

    for name, data in pairs(WWII_CTLD.WORLD_CRATES) do
        local d = ctldSqrDist(pos, { x = data.x, z = data.z })
        if d < nearestDist then
            nearestDist = d
            nearestName = name
        end
    end

    if not nearestName then
        trigger.action.outTextForUnit(unit:getID(), "No crate within 50 m!", 5)
        return
    end

    local data = WWII_CTLD.WORLD_CRATES[nearestName]
    WWII_CTLD.AIRCRAFT_CRATE[unitName] = {
        crateName   = nearestName,
        vehicleType = data.vehicleType,
    }

    local so = StaticObject.getByName(nearestName)
    if so and so:isExist() then so:destroy() end
    WWII_CTLD.WORLD_CRATES[nearestName] = nil

    trigger.action.outTextForUnit(unit:getID(),
        string.format("Crate loaded: %s", data.vehicleType), 5)
end

function WWII_CTLD.dropCrate(unit)
    if not unit or not unit:isExist() then return end

    local condOk, condMsg = WWII_CTLD.checkLoadUnloadConditions(unit, false)
    if not condOk then
        trigger.action.outTextForUnit(unit:getID(), condMsg, 6)
        return
    end

    local unitName = unit:getName()
    local cData    = WWII_CTLD.AIRCRAFT_CRATE[unitName]
    if not cData then
        trigger.action.outTextForUnit(unit:getID(), "No crate onboard!", 5)
        return
    end

    local pos     = unit:getPoint()
    local newName = WWII_CTLD.generateGroupName("CRATE_" .. cData.vehicleType)
    local cx      = pos.x + math.random(10, 20)
    local cz      = pos.z + math.random(10, 20)

    mist.dynAddStatic({
        country    = country.id.USA,
        category   = "Cargos",
        shape_name = "uh1h_cargo",
        type       = "uh1h_cargo",
        x          = cx,
        y          = cz,
        name       = newName,
        heading    = 0,
        canCargo   = true,
    })

    WWII_CTLD.WORLD_CRATES[newName] = { vehicleType = cData.vehicleType, x = cx, z = cz }
    WWII_CTLD.AIRCRAFT_CRATE[unitName] = nil

    trigger.action.outTextForUnit(unit:getID(), "Crate dropped!", 5)
end

function WWII_CTLD.assembleVehicle(unit)
    if not unit or not unit:isExist() then return end
    local pos = unit:getPoint()

    for _, opt in ipairs(WWII_CTLD.VEHICLE_CRATES) do
        local stack = {}
        for name, data in pairs(WWII_CTLD.WORLD_CRATES) do
            if data.vehicleType == opt.type then
                local d = ctldSqrDist(pos, { x = data.x, z = data.z })
                if d <= 50 * 50 then
                    table.insert(stack, name)
                end
            end
        end

        if #stack >= opt.cratesRequired then
            local sx, sz = 0, 0
            for i = 1, opt.cratesRequired do
                local d = WWII_CTLD.WORLD_CRATES[stack[i]]
                sx = sx + d.x
                sz = sz + d.z
                local so = StaticObject.getByName(stack[i])
                if so and so:isExist() then so:destroy() end
                WWII_CTLD.WORLD_CRATES[stack[i]] = nil
            end

            local groupName = WWII_CTLD.generateGroupName("VEH_" .. opt.type)
            coalition.addGroup(
                WWII_CTLD.COUNTRY,
                Group.Category.GROUND,
                {
                    name  = groupName,
                    units = {{
                        type    = opt.type,
                        x       = sx / opt.cratesRequired,
                        y       = sz / opt.cratesRequired,
                        heading = math.random() * 6.28,
                    }},
                }
            )

            trigger.action.outTextForUnit(unit:getID(),
                string.format("%s assembled!", opt.name), 6)
            return
        end
    end

    trigger.action.outTextForUnit(unit:getID(),
        "Not enough matching crates nearby (within 50 m).", 5)
end

----------------------------------------------------------------
-- CHECK CARGO
----------------------------------------------------------------

function WWII_CTLD.checkCargo(unit)
    if not unit or not unit:isExist() then return end
    local unitName = unit:getName()
    local troops   = WWII_CTLD.AIRCRAFT_TROOPS[unitName]
    local crate    = WWII_CTLD.AIRCRAFT_CRATE[unitName]

    local msg = "Cargo hold empty."
    if troops and #troops > 0 then
        local total = 0
        for _, grp in ipairs(troops) do total = total + grp.count end
        local cap = WWII_CTLD.CAPACITY[unit:getTypeName()] or 0
        msg = string.format("Troops onboard: %d/%d", total, cap)
    end
    if crate then
        msg = msg .. "\nCrate: " .. crate.vehicleType
    end

    trigger.action.outTextForUnit(unit:getID(), msg, 8)
end

----------------------------------------------------------------
-- PER-PLAYER MENU CREATION  (Syria-style ForGroup menus)
----------------------------------------------------------------

function WWII_CTLD.createMenusForUnit(unit)
    if not unit or not unit:isExist() then return end
    if not unit:getPlayerName() then return end
    if not WWII_CTLD.isValidTransport(unit) then return end

    local unitName = unit:getName()
    local group    = unit:getGroup()
    if not group or not group:isExist() then return end
    local groupId  = group:getID()

    if WWII_CTLD.UNIT_MENUS[unitName] then return end
    WWII_CTLD.UNIT_MENUS[unitName] = { groupId = groupId }

    local ctldRoot = missionCommands.addSubMenuForGroup(groupId, "CTLD", nil)
    WWII_CTLD.UNIT_MENUS[unitName].ctldRoot = ctldRoot

    -- Troops submenu
    local troopsMenu = missionCommands.addSubMenuForGroup(groupId, "Troops", ctldRoot)

    for key, tpl in pairs(WWII_CTLD.TROOP_TEMPLATES) do
        local label            = string.format("Spawn %s (%d)", tpl.displayName, #tpl.units)
        local templateNameCopy = key
        missionCommands.addCommandForGroup(groupId, label, troopsMenu,
            function()
                local u = Unit.getByName(unitName)
                if u and u:isExist() then
                    WWII_CTLD.spawnTroopsAtUnit(u, templateNameCopy)
                end
            end)
    end

    -- Vehicle Crates submenu
    local cratesMenu = missionCommands.addSubMenuForGroup(groupId, "Vehicle Crates", ctldRoot)

    for idx, opt in ipairs(WWII_CTLD.VEHICLE_CRATES) do
        local optIdx = idx
        local label  = string.format("Spawn %s Crate (%d needed)", opt.name, opt.cratesRequired)
        missionCommands.addCommandForGroup(groupId, label, cratesMenu,
            function()
                local u = Unit.getByName(unitName)
                if u and u:isExist() then
                    WWII_CTLD.spawnCrate(u, optIdx)
                end
            end)
    end

    -- Load / Unload / Pickup / Drop / Assemble / Check
    missionCommands.addCommandForGroup(groupId, "Load Nearby Troops", ctldRoot,
        function()
            local u = Unit.getByName(unitName)
            if u and u:isExist() then WWII_CTLD.loadNearestTroops(u) end
        end)

    missionCommands.addCommandForGroup(groupId, "Unload Troops", ctldRoot,
        function()
            local u = Unit.getByName(unitName)
            if u and u:isExist() then WWII_CTLD.unloadAllTroops(u) end
        end)

    missionCommands.addCommandForGroup(groupId, "Pick Up Crate", ctldRoot,
        function()
            local u = Unit.getByName(unitName)
            if u and u:isExist() then WWII_CTLD.pickupCrate(u) end
        end)

    missionCommands.addCommandForGroup(groupId, "Drop Crate", ctldRoot,
        function()
            local u = Unit.getByName(unitName)
            if u and u:isExist() then WWII_CTLD.dropCrate(u) end
        end)

    missionCommands.addCommandForGroup(groupId, "Assemble Vehicle", ctldRoot,
        function()
            local u = Unit.getByName(unitName)
            if u and u:isExist() then WWII_CTLD.assembleVehicle(u) end
        end)

    missionCommands.addCommandForGroup(groupId, "Check Cargo", ctldRoot,
        function()
            local u = Unit.getByName(unitName)
            if u and u:isExist() then WWII_CTLD.checkCargo(u) end
        end)
end

function WWII_CTLD.cleanupMenusForUnit(unitName)
    local menus = WWII_CTLD.UNIT_MENUS[unitName]
    if not menus then return end
    if menus.ctldRoot then
        pcall(function() missionCommands.removeItem(menus.ctldRoot) end)
    end
    WWII_CTLD.UNIT_MENUS[unitName] = nil
end

----------------------------------------------------------------
-- EVENT HANDLER  (crash cleanup + player enter/leave)
----------------------------------------------------------------

local CTLD_EVENT_HANDLER = {}
function CTLD_EVENT_HANDLER:onEvent(event)
    if not event or not event.id then return end
    pcall(function()
        if event.id == world.event.S_EVENT_PLAYER_LEAVE_UNIT then
            local unit = event.initiator
            if unit then
                local ok, uName = pcall(function() return unit:getName() end)
                if ok and uName then WWII_CTLD.cleanupMenusForUnit(uName) end
            end

        elseif event.id == world.event.S_EVENT_CRASH
            or event.id == world.event.S_EVENT_DEAD then
            local unit = event.initiator
            if unit then
                local ok, uName = pcall(function() return unit:getName() end)
                if ok and uName then
                    WWII_CTLD.AIRCRAFT_TROOPS[uName] = nil
                    WWII_CTLD.AIRCRAFT_CRATE[uName]  = nil
                    WWII_CTLD.cleanupMenusForUnit(uName)
                end
            end

        elseif event.id == world.event.S_EVENT_PLAYER_ENTER_UNIT then
            local unit = event.initiator
            if unit and unit:isExist() and unit:getPlayerName() then
                local uName   = unit:getName()
                local grp     = unit:getGroup()
                if grp and grp:isExist() then
                    local gId = grp:getID()
                    if WWII_CTLD.UNIT_MENUS[uName]
                       and WWII_CTLD.UNIT_MENUS[uName].groupId ~= gId then
                        WWII_CTLD.cleanupMenusForUnit(uName)
                    end
                    if not WWII_CTLD.UNIT_MENUS[uName] then
                        WWII_CTLD.createMenusForUnit(unit)
                    end
                end
            end
        end
    end)
end
world.addEventHandler(CTLD_EVENT_HANDLER)

----------------------------------------------------------------
-- MENU POLLER  (catches players already in aircraft at mission start)
----------------------------------------------------------------

local function ctldMenuPoller()
    pcall(function()
        local bluePlanes = coalition.getGroups(WWII_CTLD.COALITION, Group.Category.AIRPLANE) or {}
        for _, grp in ipairs(bluePlanes) do
            if grp and grp:isExist() then
                for _, unit in ipairs(grp:getUnits()) do
                    if unit and unit:isExist() and unit:getPlayerName() then
                        if not WWII_CTLD.UNIT_MENUS[unit:getName()] then
                            WWII_CTLD.createMenusForUnit(unit)
                        end
                    end
                end
            end
        end
    end)
    mist.scheduleFunction(ctldMenuPoller, {}, timer.getTime() + 15)
end

mist.scheduleFunction(ctldMenuPoller, {}, timer.getTime() + 5)

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION F – GCI INTERCEPT SYSTEM  (Zone-Based Scramble for Marianas)
-- ─────────────────────────────────────────────────────────────────────────────
--
--  ME SETUP:
--    1. Create trigger zones:  RED_ZONE_ROTA, RED_ZONE_NORTH, RED_ZONE_SOUTH, etc.
--    2. Create late-activated RED air groups named with the squadron groupPrefix:
--       RED_AIR_ROTA_01, RED_AIR_ROTA_02, etc.  (2 aircraft per group recommended)
--    3. (Optional) BLUE zones + flights using BLUE_ZONE_ / BLUE_AIR_ prefixes.
-- ─────────────────────────────────────────────────────────────────────────────

local GCI_CFG = {
    UPDATE_INTERVAL        = 10,
    RTB_LOITER_TIME        = 45,
    SCRAMBLE_THREAT_BUFFER = 0,
    INTERCEPT_LEASH_BUFFER = 15000,
    INTERCEPT_ALTITUDE     = 3000,
    INTERCEPT_SPEED        = 450,
    GCI_FUEL_RTB_THRESHOLD = 0.20,
    RTB_CHECK_INTERVAL     = 15,

    GCI_CALLSIGN = {
        RED  = "IJN COMMAND",
        BLUE = "NAVY CONTROL",
    },

    ZONE_PREFIX_RED  = "RED_ZONE_",
    ZONE_PREFIX_BLUE = "BLUE_ZONE_",

    SQUADRONS = {
        RED = {
            { callsign = "SHIDEN",  homeBase = "Rota Intl",      zone = "RED_ZONE_ROTA",        groupPrefix = "RED_AIR_ROTA",        maxFlights = 6 },
            { callsign = "HAYATE",  homeBase = "Charon Kanoa",   zone = "RED_ZONE_CHARONKANOA", groupPrefix = "RED_AIR_CHARONKANOA", maxFlights = 4 },
            { callsign = "RAIDEN",  homeBase = "Ushi",           zone = "RED_ZONE_USHI",        groupPrefix = "RED_AIR_USHI",        maxFlights = 4 },
            { callsign = "GEKKO",   homeBase = "Gurguan Point",  zone = "RED_ZONE_GURGUAN",     groupPrefix = "RED_AIR_GURGUAN",     maxFlights = 4 },
            { callsign = "TENZAN",  homeBase = "Pagan",          zone = "RED_ZONE_PAGAN",       groupPrefix = "RED_AIR_PAGAN",       maxFlights = 4 },
        },
        BLUE = {
            { callsign = "HELLCAT", homeBase = "Olf Orote",           zone = "BLUE_ZONE_AGANA",  groupPrefix = "BLUE_AIR_AGANA",  maxFlights = 6 },
            { callsign = "CORSAIR", homeBase = "Antonio B. Won Pat Intl", zone = "BLUE_ZONE_NORTH",  groupPrefix = "BLUE_AIR_NORTH",  maxFlights = 4 },
        },
    },
}

local gciState = {
    RED  = { flights = {}, zones = {}, lastPicture = 0 },
    BLUE = { flights = {}, zones = {}, lastPicture = 0 },
}

-- Helpers
local function gciLog(msg) env.info("[GCI] " .. tostring(msg)) end

local function gciDist2d(p1, p2)
    local dx = p1.x - p2.x; local dz = p1.z - p2.z
    return math.sqrt(dx * dx + dz * dz)
end

local function gciGroupAlive(gName)
    local g = Group.getByName(gName)
    if not g then return false end
    for _, u in ipairs(g:getUnits()) do if u:getLife() > 1 then return true end end
    return false
end

local function gciGetGroupPos(gName)
    local g = Group.getByName(gName)
    if not g then return nil end
    for _, u in ipairs(g:getUnits()) do
        if u:isActive() and u:getLife() > 1 then return u:getPoint() end
    end
    return nil
end

local function gciMsg(coalName, text, duration)
    local coaID  = (coalName == "RED") and coalition.side.RED or coalition.side.BLUE
    local prefix = GCI_CFG.GCI_CALLSIGN[coalName] or "GCI"
    trigger.action.outTextForCoalition(coaID, "[" .. prefix .. "]  " .. text, duration or 14, false)
end

-- Discover zones from MIST DB
local function gciDiscoverZones()
    if not (mist and mist.DBs and mist.DBs.zonesByName) then return end
    for zoneName, _ in pairs(mist.DBs.zonesByName) do
        if string.sub(zoneName, 1, #GCI_CFG.ZONE_PREFIX_RED) == GCI_CFG.ZONE_PREFIX_RED then
            if not gciState.RED.zones[zoneName] then
                gciState.RED.zones[zoneName] = { clearSince = nil }
                gciLog("Discovered RED zone: " .. zoneName)
            end
        elseif string.sub(zoneName, 1, #GCI_CFG.ZONE_PREFIX_BLUE) == GCI_CFG.ZONE_PREFIX_BLUE then
            if not gciState.BLUE.zones[zoneName] then
                gciState.BLUE.zones[zoneName] = { clearSince = nil }
                gciLog("Discovered BLUE zone: " .. zoneName)
            end
        end
    end
end

-- Available flights for a squadron
local function gciGetAvailableFlights(sqd, gciSt)
    local available = {}
    local prefix = sqd.groupPrefix
    if mist and mist.DBs and mist.DBs.groupsByName then
        for gName, _ in pairs(mist.DBs.groupsByName) do
            if string.sub(gName, 1, #prefix) == prefix then
                local fs = gciSt.flights[gName]
                if not fs or fs.status == "standby" then
                    local g = Group.getByName(gName)
                    local isActiveNow = false
                    if g then
                        if g.isActive then
                            isActiveNow = g:isActive()
                        else
                            for _, u in ipairs(g:getUnits()) do
                                if u:getPoint().y > 500 then isActiveNow = true; break end
                            end
                        end
                    end
                    if not isActiveNow then table.insert(available, gName) end
                end
            end
        end
    end
    return available
end

local function gciCountAirborne(sqd, gciSt)
    local count  = 0
    local prefix = sqd.groupPrefix
    for gName, fs in pairs(gciSt.flights) do
        if string.sub(gName, 1, #prefix) == prefix and fs.status == "airborne" then
            count = count + 1
        end
    end
    return count
end

local function gciGetThreatsForZone(zoneName, coalName)
    local threats = {}
    local zd = trigger.misc.getZone(zoneName)
    if not zd then return threats end
    local zPos    = zd.point
    local zRadius = zd.radius + (GCI_CFG.SCRAMBLE_THREAT_BUFFER or 0)
    local enemyCoa = (coalName == "RED") and coalition.side.BLUE or coalition.side.RED
    local groups   = coalition.getGroups(enemyCoa, Group.Category.AIRPLANE)
    for _, grp in ipairs(groups or {}) do
        if grp and grp:isExist() then
            for _, u in ipairs(grp:getUnits()) do
                if u:isExist() and u:isActive() and u:getLife() > 1 then
                    local uPos = u:getPoint()
                    if uPos and gciDist2d(uPos, zPos) <= zRadius then
                        table.insert(threats, { unit = u, pos = uPos, group = grp })
                        break
                    end
                end
            end
        end
    end
    return threats
end

local function gciDispatchFlight(groupName, coalName, sqd, threats, gciSt)
    gciLog("Dispatching " .. coalName .. " flight: " .. groupName)
    local g = Group.getByName(groupName)
    if g then
        trigger.action.activateGroup(g)
    else
        gciLog("DISPATCH FAILED: group '" .. groupName .. "' not found.")
        return
    end

    gciSt.flights[groupName] = {
        status     = "airborne",
        zone       = sqd.zone,
        homeBase   = sqd.homeBase,
        callsign   = sqd.callsign,
        coalName   = coalName,
        launchTime = timer.getTime(),
    }

    gciMsg(coalName,
        string.format("SCRAMBLE - %s. %d hostile(s) in zone. Cleared to engage.",
            sqd.callsign, #threats), 16)

    local cap_gName   = groupName
    local cap_threats = threats
    local cap_sqd     = sqd
    timer.scheduleFunction(function()
        local grp  = Group.getByName(cap_gName)
        if not grp then return nil end
        local ctrl = grp:getController()
        if not ctrl then return nil end
        ctrl:setOption(0, 2)  -- ROE weapons free
        ctrl:setOption(1, 0)  -- aggressive

        local targetUnit = cap_threats[1] and cap_threats[1].unit or nil
        local taskDef
        if targetUnit and targetUnit:isExist() and targetUnit:isActive() and targetUnit:getLife() > 1 then
            taskDef = {
                id = "EngageUnit",
                params = { unitId = targetUnit:getID(), weaponType = 268402688, expend = "Auto" },
            }
        else
            local zd = trigger.misc.getZone(cap_sqd.zone)
            taskDef = {
                id = "Orbit",
                params = {
                    pattern  = "Circle",
                    speed    = GCI_CFG.INTERCEPT_SPEED / 3.6,
                    altitude = GCI_CFG.INTERCEPT_ALTITUDE,
                    point    = zd and { x = zd.point.x, y = zd.point.z } or nil,
                },
            }
        end
        ctrl:setTask({ id = "ComboTask", params = { tasks = { taskDef } } })
        return nil
    end, nil, timer.getTime() + 4)
end

local function gciOrderFlightRTB(groupName, gciSt, reason)
    local fState = gciSt.flights[groupName]
    local grp    = Group.getByName(groupName)
    if not grp then
        if fState then fState.status = "dead" end
        return
    end
    local ctrl = grp:getController()
    if not ctrl then return end

    local homeName = fState and fState.homeBase
    local homeAB   = homeName and Airbase.getByName(homeName)
    local grpPos   = gciGetGroupPos(groupName)

    if not homeAB and grpPos then
        local bases = world.getAirbases()
        local best, bestDist = nil, math.huge
        for _, ab in ipairs(bases) do
            local d = gciDist2d(grpPos, ab:getPoint())
            if d < bestDist then bestDist = d; best = ab end
        end
        homeAB = best
    end

    ctrl:setOption(0, 4)  -- return fire only

    if homeAB and grpPos then
        local abPos = homeAB:getPoint()
        ctrl:setTask({
            id = "Mission",
            params = {
                route = {
                    points = {
                        { type = "Turning Point", action = "Turning Point",
                          x = grpPos.x, y = grpPos.z,
                          alt = GCI_CFG.INTERCEPT_ALTITUDE, alt_type = "BARO",
                          speed = GCI_CFG.INTERCEPT_SPEED / 3.6 },
                        { type = "Land", action = "Landing",
                          x = abPos.x, y = abPos.z,
                          alt = abPos.y or 10, alt_type = "BARO",
                          speed = 250 / 3.6, airdromeId = homeAB:getID() },
                    }
                }
            }
        })
    end

    if fState then fState.status = "rtb" end
    if fState and fState.callsign and fState.coalName then
        gciMsg(fState.coalName, fState.callsign .. ", RTB. " .. (reason or "Zone clear."), 12)
    end

    local gn_cap = groupName
    timer.scheduleFunction(function()
        local fs = gciSt.flights[gn_cap]
        if fs and fs.status == "rtb" then
            local gg = Group.getByName(gn_cap)
            if gg then gg:destroy() end
            fs.status = "standby"
            gciLog(gn_cap .. " stood down after RTB")
        end
        return nil
    end, nil, timer.getTime() + 600)
end

-- Main GCI Loop
local function gciInterceptLoop()
    local now = timer.getTime()
    for _, coalName in ipairs({ "RED", "BLUE" }) do
        local gciSt = gciState[coalName]
        local sqds  = GCI_CFG.SQUADRONS[coalName] or {}

        for _, sqd in ipairs(sqds) do
            local threats  = gciGetThreatsForZone(sqd.zone, coalName)
            local airborne = gciCountAirborne(sqd, gciSt)

            if #threats > 0 then
                if gciSt.zones[sqd.zone] then gciSt.zones[sqd.zone].clearSince = nil end
                local needed    = math.min(#threats, sqd.maxFlights) - airborne
                if needed > 0 then
                    local available = gciGetAvailableFlights(sqd, gciSt)
                    for i = 1, math.min(needed, #available) do
                        gciDispatchFlight(available[i], coalName, sqd, threats, gciSt)
                    end
                end
            elseif airborne > 0 then
                local zSt = gciSt.zones[sqd.zone]
                if not zSt then
                    gciSt.zones[sqd.zone] = { clearSince = now }
                    zSt = gciSt.zones[sqd.zone]
                end
                if zSt.clearSince == nil then zSt.clearSince = now end
                if (now - zSt.clearSince) >= GCI_CFG.RTB_LOITER_TIME then
                    for gName, fs in pairs(gciSt.flights) do
                        if string.sub(gName, 1, #sqd.groupPrefix) == sqd.groupPrefix
                        and fs.status == "airborne" then
                            gciOrderFlightRTB(gName, gciSt, "Zone clear.")
                        end
                    end
                end
            end
        end
    end
    return now + GCI_CFG.UPDATE_INTERVAL
end

-- Fuel / leash maintenance
local function gciFlightMaintenance()
    local fuelMin    = GCI_CFG.GCI_FUEL_RTB_THRESHOLD
    local leashExtra = GCI_CFG.INTERCEPT_LEASH_BUFFER

    for _, coalName in ipairs({ "RED", "BLUE" }) do
        local gciSt = gciState[coalName]
        for gName, fs in pairs(gciSt.flights) do
            if fs.status == "airborne" then
                local grp = Group.getByName(gName)
                if grp then
                    local alive, lowestFuel = false, 1.0
                    for _, u in ipairs(grp:getUnits()) do
                        if u:getLife() > 1 then
                            alive = true
                            local f = u:getFuel()
                            if f < lowestFuel then lowestFuel = f end
                        end
                    end
                    if not alive then
                        fs.status = "dead"
                    elseif lowestFuel < fuelMin then
                        gciOrderFlightRTB(gName, gciSt, string.format("Bingo fuel (%.0f%%).", lowestFuel * 100))
                    else
                        local fPos = gciGetGroupPos(gName)
                        local zd   = fs.zone and trigger.misc.getZone(fs.zone)
                        if fPos and zd and zd.point and zd.radius then
                            if gciDist2d(fPos, zd.point) > (zd.radius + leashExtra) then
                                gciOrderFlightRTB(gName, gciSt, "Leash limit - RTB.")
                            end
                        end
                    end
                else
                    if fs.status ~= "dead" then fs.status = "dead" end
                end
            end
        end
    end
    return timer.getTime() + GCI_CFG.RTB_CHECK_INTERVAL
end

-- GCI Event handler (track kills)
local gciEventHandler = {}
function gciEventHandler:onEvent(event)
    if event.id == world.event.S_EVENT_DEAD or event.id == world.event.S_EVENT_CRASH then
        local unit = event.initiator
        if not unit or not unit.getGroup then return end
        local groupObj = unit:getGroup()
        if groupObj then
            local gName = groupObj:getName()
            for _, cn in ipairs({ "RED", "BLUE" }) do
                local fs = gciState[cn].flights[gName]
                if fs and fs.status ~= "dead" then
                    fs.status = "dead"
                    gciLog(cn .. " flight " .. gName .. " KIA")
                end
            end
        end
    end
end
world.addEventHandler(gciEventHandler)

-- GCI Init
local function gciInit()
    gciLog("=== WWII Marianas GCI System initialising ===")
    gciDiscoverZones()
    timer.scheduleFunction(gciInterceptLoop,    {}, timer.getTime() + 15)
    timer.scheduleFunction(gciFlightMaintenance, {}, timer.getTime() + 30)
    gciLog("=== GCI initialisation complete ===")
end

timer.scheduleFunction(function() gciInit(); return nil end, {}, timer.getTime() + 3)

-- ─────────────────────────────────────────────────────────────────────────────
trigger.action.outText("WWII Marianas CAP/CTLD/GCI Script loaded.", 10)
-- =============================================================================
--  END OF SCRIPT
--
--  QUICK REFERENCE – ME SETUP
--  ──────────────────────────
--  1. Load MIST first, then this script.
--  2. Late-activate all CAP/Bomber/Support/GCI flight groups.
--  3. Create trigger zones:
--       RED_ZONE_ROTA, RED_ZONE_CHARONKANOA, RED_ZONE_USHI,
--       RED_ZONE_GURGUAN, RED_ZONE_PAGAN,
--       BLUE_ZONE_AGANA, BLUE_ZONE_NORTH, BlueCTLD (for logistics).
--  4. CAP groups (late-activated):
--       Rota (existing): RotaCAPNorth, RotaCAPSouth
--       Charon Kanoa: CAPCharonKanoa, CAPCharonKanoa2
--       Ushi: CAPUshi, CAPUshi2
--       Gurguan Point: CAPGurguan, CAPGurguan2
--       Pagan: CAPPagan, CAPPagan2
--  5. Fighter-Bomber groups (late-activated):
--       Rota (existing): FighterBomber, FighterBomber2, Bombers, Bombers2
--       New bases: FBCharonKanoa, FBUshi, FBGurguan, FBPagan
--  6. GCI flights (late-activated):
--       RED_AIR_ROTA_01/_02/etc, RED_AIR_CHARONKANOA_01/_02/etc,
--       RED_AIR_USHI_01/_02/etc, RED_AIR_GURGUAN_01/_02/etc,
--       RED_AIR_PAGAN_01/_02/etc,
--       BLUE_AIR_AGANA_01/_02/etc, BLUE_AIR_NORTH_01/_02/etc.
--  7. CTLD logistics plane group name starts with "LogiTF51D".
-- =============================================================================
