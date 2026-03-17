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
            mist.respawnGroup(bomber.name, true)
            bomberSpawned[bomber.name]        = true
            bomberRespawnPending[bomber.name]  = false
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
--  SECTION E – LIGHTWEIGHT TF-51D CTLD
-- ─────────────────────────────────────────────────────────────────────────────

WWII_CTLD = {}

WWII_CTLD.allowedTransports = { ["TF-51D"] = true }
WWII_CTLD.INFANTRY_WEIGHT   = 120
WWII_CTLD.CRATE_WEIGHT      = 300
WWII_CTLD.logiZones         = { "BlueCTLD" }
WWII_CTLD.ctldPlaneGroup    = "LogiTF51D"

WWII_CTLD.transportLimits = {
    ["TF-51D"] = { maxWeight = 3 * WWII_CTLD.INFANTRY_WEIGHT, maxCrates = 1 },
}

WWII_CTLD.infantryOptions = {
    { name = "1x Infantry", count = 1, weight = 1 * WWII_CTLD.INFANTRY_WEIGHT },
    { name = "2x Infantry", count = 2, weight = 2 * WWII_CTLD.INFANTRY_WEIGHT },
    { name = "3x Infantry", count = 3, weight = 3 * WWII_CTLD.INFANTRY_WEIGHT },
}

WWII_CTLD.vehicleCrateOptions = {
    { name = "M4 Tractor",     type = "M4_Tractor",     cratesRequired = 2, weight = 2 * WWII_CTLD.CRATE_WEIGHT },
    { name = "M2A1 Halftrack", type = "M2A1_halftrack", cratesRequired = 2, weight = 2 * WWII_CTLD.CRATE_WEIGHT },
    { name = "M4 Sherman",     type = "M4_Sherman",     cratesRequired = 3, weight = 3 * WWII_CTLD.CRATE_WEIGHT },
}

WWII_CTLD.loadedInfantry = {}
WWII_CTLD.loadedCrate    = {}
WWII_CTLD.worldCrates    = {}
WWII_CTLD.spawnedTroops  = {}

local function destroyStatic(name)
    local so = StaticObject.getByName(name)
    if so and so:isExist() then so:destroy() end
end

local function ctldGroupSize(g)
    if not g or not g:isExist() then return 0 end
    local n = 0
    for _, u in ipairs(g:getUnits()) do if u:isExist() then n = n + 1 end end
    return n
end

local function ctldGetTransportLimits(typeName)
    return WWII_CTLD.transportLimits[typeName] or { maxWeight = math.huge, maxCrates = math.huge }
end

local function ctldOffsetPoint(pos, hdg)
    local d = math.random(10, 20)
    return {
        x = pos.x + d * math.cos(hdg - math.pi / 2),
        y = pos.y,
        z = pos.z + d * math.sin(hdg - math.pi / 2),
    }
end

local function ctldGetGroupsByPrefix(prefix)
    local hits = {}
    if mist and mist.DBs and mist.DBs.groupsByName then
        for name, _ in pairs(mist.DBs.groupsByName) do
            if name:sub(1, #prefix) == prefix then table.insert(hits, name) end
        end
    else
        for coa = 0, 2 do for cat = 0, 3 do
            local grps = coalition.getGroups(coa, cat)
            if grps then
                for _, g in ipairs(grps) do
                    local n = g:getName()
                    if n and n:sub(1, #prefix) == prefix then hits[#hits + 1] = n end
                end
            end
        end end
    end
    return hits
end

function WWII_CTLD.loadInfantry(planeGrp, optIdx)
    local grp  = Group.getByName(planeGrp); if not grp then return end
    local unit = grp:getUnit(1);            if not unit then return end
    if not WWII_CTLD.allowedTransports[unit:getTypeName()] then
        return trigger.action.outText("Aircraft cannot load troops.", 10) end
    local inZone = false
    for _, zn in ipairs(WWII_CTLD.logiZones) do
        if mist.pointInZone(unit:getPoint(), zn) then inZone = true; break end
    end
    if not inZone then return trigger.action.outText("Not inside a Logi zone.", 10) end
    if WWII_CTLD.loadedCrate[planeGrp] then
        return trigger.action.outText("Crate already loaded.", 10) end
    local opt = WWII_CTLD.infantryOptions[optIdx]
    local lim = ctldGetTransportLimits(unit:getTypeName())
    if opt.weight > lim.maxWeight then return trigger.action.outText("Too heavy.", 10) end
    WWII_CTLD.loadedInfantry[planeGrp] = { count = opt.count, weight = opt.weight, type = opt.name }
    trigger.action.outText("Loaded " .. opt.name, 10)
end

function WWII_CTLD.dropInfantry(pg)
    local inf  = WWII_CTLD.loadedInfantry[pg]; if not inf then return end
    local grp  = Group.getByName(pg); if not grp then return end
    local unit = grp:getUnit(1);      if not unit then return end
    local p    = ctldOffsetPoint(unit:getPoint(), unit:getHeading() or 0)
    local gid  = mist.getNextGroupId()
    local gname = "DroppedTroops_" .. gid
    local units = {}
    for i = 1, inf.count do
        local uid = mist.getNextUnitId()
        units[#units + 1] = {
            type = "soldier_wwii_us", country = country.id.USA, skill = "Average",
            x = p.x + (i - 1) * 2, y = p.y, z = p.z + (i - 1) * 2,
            heading = 0, name = "Troop_" .. uid, unitId = uid,
        }
    end
    mist.dynAdd({
        visible = false, groupId = gid, country = country.id.USA,
        category = Group.Category.GROUND, units = units,
        name = gname, task = "Ground Nothing",
    })
    WWII_CTLD.spawnedTroops[pg] = WWII_CTLD.spawnedTroops[pg] or {}
    table.insert(WWII_CTLD.spawnedTroops[pg], { groupName = gname })
    WWII_CTLD.loadedInfantry[pg] = nil
    trigger.action.outText("Infantry dropped!", 10)
end

function WWII_CTLD.pickupInfantry(pg)
    local grp  = Group.getByName(pg); if not grp then return end
    local unit = grp:getUnit(1);      if not unit then return end
    local pos  = unit:getPoint()
    local list = WWII_CTLD.spawnedTroops[pg] or {}
    for i = #list, 1, -1 do
        local g = Group.getByName(list[i].groupName)
        if g and ctldGroupSize(g) > 0 then
            if mist.utils.get2DDist({ x = pos.x, z = pos.z }, g:getUnit(1):getPoint()) < 50 then
                local cnt = ctldGroupSize(g); g:destroy()
                WWII_CTLD.loadedInfantry[pg] = {
                    count = cnt, weight = cnt * WWII_CTLD.INFANTRY_WEIGHT,
                    type = cnt .. "x Infantry",
                }
                table.remove(list, i)
                return trigger.action.outText("Infantry picked up!", 10)
            end
        else
            table.remove(list, i)
        end
    end
    trigger.action.outText("No infantry within 50 m.", 10)
end

function WWII_CTLD.spawnCrate(pg, optIdx)
    local grp  = Group.getByName(pg); if not grp then return end
    local unit = grp:getUnit(1);      if not unit then return end
    local p    = ctldOffsetPoint(unit:getPoint(), unit:getHeading() or 0)
    local opt  = WWII_CTLD.vehicleCrateOptions[optIdx]
    local cname = "CTLD_Crate_" .. opt.type .. "_" .. mist.getNextGroupId()
    mist.dynAddStatic({
        country = country.id.USA, category = "Cargos",
        shape_name = "uh1h_cargo", type = "uh1h_cargo",
        unitId = mist.getNextUnitId(),
        x = p.x, y = p.y, z = p.z, name = cname,
        heading = unit:getHeading() or 0, canCargo = true,
    })
    WWII_CTLD.worldCrates[cname] = { type = opt.type, x = p.x, z = p.z, pickedUp = false }
    trigger.action.outText("Crate spawned: " .. opt.name, 10)
end

function WWII_CTLD.pickupCrate(pg)
    local grp = Group.getByName(pg); if not grp then return end
    if WWII_CTLD.loadedCrate[pg] or WWII_CTLD.loadedInfantry[pg] then
        return trigger.action.outText("Already carrying something.", 10) end
    local unit = grp:getUnit(1); if not unit then return end
    local pos  = unit:getPoint()
    for name, data in pairs(WWII_CTLD.worldCrates) do
        if not data.pickedUp and mist.utils.get2DDist({ x = pos.x, z = pos.z }, { x = data.x, z = data.z }) < 20 then
            data.pickedUp = true; destroyStatic(name)
            WWII_CTLD.loadedCrate[pg] = { crateName = name, type = data.type }
            return trigger.action.outText("Crate loaded! Fly to destination and use 'Drop Loaded Crate'.", 10)
        end
    end
    trigger.action.outText("No crate within 20 m.", 10)
end

function WWII_CTLD.dropCrate(pg)
    local c = WWII_CTLD.loadedCrate[pg]; if not c then return end
    local grp  = Group.getByName(pg); if not grp then return end
    local unit = grp:getUnit(1);      if not unit then return end
    local p    = ctldOffsetPoint(unit:getPoint(), unit:getHeading() or 0)
    local newName = c.crateName .. "_d" .. mist.getNextGroupId()
    mist.dynAddStatic({
        country = country.id.USA, category = "Cargos",
        shape_name = "uh1h_cargo", type = "uh1h_cargo",
        unitId = mist.getNextUnitId(),
        x = p.x, y = p.y, z = p.z, name = newName,
        heading = unit:getHeading() or 0, canCargo = true,
    })
    WWII_CTLD.worldCrates[newName] = { type = c.type, x = p.x, z = p.z, pickedUp = false }
    WWII_CTLD.loadedCrate[pg] = nil
    trigger.action.outText("Crate dropped!", 10)
end

function WWII_CTLD.assembleVehicle(pg)
    local grp  = Group.getByName(pg); if not grp then return end
    local unit = grp:getUnit(1);      if not unit then return end
    local pos  = unit:getPoint()
    for _, opt in ipairs(WWII_CTLD.vehicleCrateOptions) do
        local stack = {}
        for name, data in pairs(WWII_CTLD.worldCrates) do
            if not data.pickedUp and data.type == opt.type and
               mist.utils.get2DDist({ x = pos.x, z = pos.z }, { x = data.x, z = data.z }) < 30 then
                stack[#stack + 1] = name
            end
        end
        if #stack >= opt.cratesRequired then
            local sx, sz = 0, 0
            for i = 1, opt.cratesRequired do
                sx = sx + WWII_CTLD.worldCrates[stack[i]].x
                sz = sz + WWII_CTLD.worldCrates[stack[i]].z
                destroyStatic(stack[i])
                WWII_CTLD.worldCrates[stack[i]] = nil
            end
            local gid = mist.getNextGroupId(); local uid = mist.getNextUnitId()
            mist.dynAdd({
                visible = false, playerCanDrive = true,
                groupId = gid, country = country.id.USA,
                category = Group.Category.GROUND,
                units = {{
                    type = opt.type, country = country.id.USA, skill = "Average",
                    x = sx / opt.cratesRequired, y = pos.y,
                    z = sz / opt.cratesRequired, heading = 0,
                    unitId = uid, name = opt.type .. "_" .. uid,
                }},
                name = opt.type .. "_Group_" .. gid, task = "Ground Nothing",
            })
            return trigger.action.outText(opt.name .. " assembled!", 10)
        end
    end
    trigger.action.outText("Not enough crates nearby.", 10)
end

function WWII_CTLD.checkCargo(pg)
    if WWII_CTLD.loadedInfantry[pg] then
        local i = WWII_CTLD.loadedInfantry[pg]
        return trigger.action.outText("Infantry: " .. i.type .. " (" .. i.weight .. " kg)", 10)
    elseif WWII_CTLD.loadedCrate[pg] then
        return trigger.action.outText("Crate: " .. WWII_CTLD.loadedCrate[pg].type, 10)
    else
        return trigger.action.outText("Cargo hold empty.", 10)
    end
end

local function setupCTLDMenus()
    if not missionCommands then return end
    if _G.ctldLogiMenus then
        for _, menu in ipairs(_G.ctldLogiMenus) do
            pcall(function() missionCommands.removeItem(menu) end)
        end
    end
    _G.ctldLogiMenus = {}

    local ctldMenu = missionCommands.addSubMenu("CTLD")
    table.insert(_G.ctldLogiMenus, ctldMenu)
    local logiGroups = ctldGetGroupsByPrefix(WWII_CTLD.ctldPlaneGroup or "Logi")

    if #logiGroups == 0 then
        local cmd = missionCommands.addCommand("No logistics groups found!", ctldMenu, function() end)
        table.insert(_G.ctldLogiMenus, cmd)
    else
        for _, groupName in ipairs(logiGroups) do
            local infMenu = missionCommands.addSubMenu("Infantry (" .. groupName .. ")", ctldMenu)
            table.insert(_G.ctldLogiMenus, infMenu)
            for idx, opt in ipairs(WWII_CTLD.infantryOptions) do
                table.insert(_G.ctldLogiMenus, missionCommands.addCommand(
                    "Load " .. opt.name .. " (" .. opt.weight .. " kg)", infMenu,
                    function() WWII_CTLD.loadInfantry(groupName, idx) end))
            end
            table.insert(_G.ctldLogiMenus, missionCommands.addCommand(
                "Pick Up Infantry", infMenu,
                function() WWII_CTLD.pickupInfantry(groupName) end))
            table.insert(_G.ctldLogiMenus, missionCommands.addCommand(
                "Drop Infantry (" .. groupName .. ")", ctldMenu,
                function() WWII_CTLD.dropInfantry(groupName) end))

            local vehMenu = missionCommands.addSubMenu("Vehicle (" .. groupName .. ")", ctldMenu)
            table.insert(_G.ctldLogiMenus, vehMenu)
            for idx, opt in ipairs(WWII_CTLD.vehicleCrateOptions) do
                table.insert(_G.ctldLogiMenus, missionCommands.addCommand(
                    "Spawn Crate for " .. opt.name, vehMenu,
                    function() WWII_CTLD.spawnCrate(groupName, idx) end))
            end

            table.insert(_G.ctldLogiMenus, missionCommands.addCommand(
                "Load Nearby Crate (" .. groupName .. ")", ctldMenu,
                function() WWII_CTLD.pickupCrate(groupName) end))
            table.insert(_G.ctldLogiMenus, missionCommands.addCommand(
                "Drop Loaded Crate (" .. groupName .. ")", ctldMenu,
                function() WWII_CTLD.dropCrate(groupName) end))
            table.insert(_G.ctldLogiMenus, missionCommands.addCommand(
                "Assemble Vehicle (nearby crates)", ctldMenu,
                function() WWII_CTLD.assembleVehicle(groupName) end))
            table.insert(_G.ctldLogiMenus, missionCommands.addCommand(
                "Check Cargo (" .. groupName .. ")", ctldMenu,
                function() WWII_CTLD.checkCargo(groupName) end))
        end
    end
end

mist.scheduleFunction(setupCTLDMenus, {}, timer.getTime() + 2)

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
