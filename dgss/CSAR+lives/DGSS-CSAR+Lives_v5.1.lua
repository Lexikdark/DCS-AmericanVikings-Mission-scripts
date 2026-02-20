----------------------------------------------------------------
-- CSAR + LIVES SYSTEM (Unified Version) v4.9
-- Crash/eject survivors + per‑player lives + hard lockout
-- Blue smoke + MGRS + DM coordinates + distance
-- Separate menus for Downed Pilots and Convoy Survivors
----------------------------------------------------------------

DGSS_CSAR = {}

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------

DGSS_CSAR.COALITION = coalition.side.BLUE
DGSS_CSAR.COUNTRY   = country.id.USA

DGSS_CSAR.LIVES = {
    enabled          = true,
    defaultLives     = 5,
    maxLives         = 5,
    loseLifeOnDeath  = true,
    gainLifeOnRescue = true,
    lifeGainAmount   = 1,
}

DGSS_CSAR.CSAR = {
    enableAutoSpawnOnEject = true,
    pickupRadius           = 75,
    pickupAltitudeMax      = 50,
    smokeOnRequest         = true,
    smokeColor             = trigger.smokeColor.Blue, -- BLUE SMOKE
    nearestSearchRadius    = 148160,  -- 80 NM in meters
    despawnOnRescue        = true,

    dropOffZones = {
        { zoneName = "RAMAT_DAVID" },
        { zoneName = "ROSH_PINA" },
        { zoneName = "KIRYAT_SHMONA" },
        { zoneName = "MEGIDDO" },
        { zoneName = "HAIFA" },
        { zoneName = "FOB_BRAVO" },
        { zoneName = "FOB_DELTA" },
        { zoneName = "FOB_CHARLIE" },
        { zoneName = "FOB_ECHO" },
        { zoneName = "FOB_ALPHA" },
        { zoneName = "FOB_FOXTROT" },

        -- CARRIER_GROUP CSAR Zone
        { zoneName = "CARRIER_GROUP" },
    },
}

-- Pickup/Dropoff operational limits
DGSS_CSAR.MAX_PICKUP_SPEED    = 7.5  -- m/s (10 knots) - maximum speed to pick up survivors
DGSS_CSAR.MAX_PICKUP_ALTITUDE = 15.2  -- meters AGL (50 feet) - maximum altitude to pick up
DGSS_CSAR.MAX_DROPOFF_SPEED   = 7.5  -- m/s (10 knots) - maximum speed to drop off survivors
DGSS_CSAR.MAX_DROPOFF_ALTITUDE = 15.2  -- meters AGL (50 feet) - maximum altitude to drop off

-- Check speed and altitude limits for pickup/dropoff operations
function DGSS_CSAR.checkPickupDropoffConditions(unit, isPickup)
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
    -- Note: unit:getAltitude() does not exist - use getPoint().y instead
    local alt = unitPos.y
    local terrain_alt = land.getHeight({x = unitPos.x, y = unitPos.z}) or 0
    local agl = alt - terrain_alt

    -- Determine which limits apply
    local max_speed = isPickup and DGSS_CSAR.MAX_PICKUP_SPEED or DGSS_CSAR.MAX_DROPOFF_SPEED
    local max_alt = isPickup and DGSS_CSAR.MAX_PICKUP_ALTITUDE or DGSS_CSAR.MAX_DROPOFF_ALTITUDE
    local operation = isPickup and "pick up" or "drop off"

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
-- MESSAGES
----------------------------------------------------------------

DGSS_CSAR.MESSAGES = {
    noLivesLeft       = "You have no lives remaining. You will regain 1 life in 10 minutes.",
    lifeLost          = "You lost a life! Remaining lives: %d",
    lifeGained        = "You gained a life! New life count: %d",
    survivorSpawned   = "Mayday! A pilot is down and awaiting rescue!",
    survivorPickedUp  = "Survivor onboard! Deliver them to a CSAR base.",
    survivorDropped   = "Survivor delivered safely. CSAR successful!",
    noSurvivorsNearby = "No CSAR survivors detected nearby.",
    noPilotsNearby    = "No downed pilots detected nearby.",
    noConvoyNearby    = "No convoy survivors detected nearby.",
    markNearestInfo   = "Nearest CSAR survivor information displayed.",
}

----------------------------------------------------------------
-- CSAR‑CAPABLE AIRCRAFT WHITELIST
----------------------------------------------------------------

DGSS_CSAR.ALLOWED_UNITS = {
    ["UH-1H"]        = true,
    ["Mi-8MT"]       = true,
    ["Mi-24P"]       = true,
    ["SA342M"]       = true,
    ["SA342L"]       = true,
    ["SA342Mistral"] = true,
    ["SA342Minigun"] = true,
    ["CH-47Fbl1"]    = true,
    ["MH-6J"]        = true,
    ["AH-6J"]        = true,
    
    ["C-130J-30"]    = true,
    ["TF-51D"]    = true,
}

----------------------------------------------------------------
-- INTERNAL STATE
----------------------------------------------------------------

DGSS_CSAR.UNIT_MENUS        = {}
DGSS_CSAR.SURVIVORS         = {}
DGSS_CSAR.PLAYER_LIVES      = {}
DGSS_CSAR.CARRYING_SURVIVOR = {}

-- Anti‑duplicate per PLAYER (tracks last incident time)
DGSS_CSAR.LAST_EVENT_TIME   = {}

-- Track which players have had a death/eject event processed recently
-- This prevents double-counting when ejection + aircraft destruction happen close together
DGSS_CSAR.INCIDENT_PROCESSED = {}

-- Cooldown period in seconds - ignore subsequent death/eject events within this window
DGSS_CSAR.INCIDENT_COOLDOWN = 30  -- 30 seconds to cover crash + eject + explosion scenarios

-- Track players who have ejected - they are exempt from SLOT_LEAVE penalties
-- This prevents penalizing players for leaving the parachute/ejected seat after ejection
DGSS_CSAR.EJECTED_PLAYERS = {}
DGSS_CSAR.EJECT_EXEMPTION_TIME = 300  -- 5 minutes exemption from SLOT_LEAVE penalty after ejecting

-- Lockout timers per player
DGSS_CSAR.LOCKOUT           = {}

----------------------------------------------------------------
-- UTILS
----------------------------------------------------------------

local function now()
    return timer.getTime()
end

local function _2dDist(a, b)
    local dx = a.x - b.x
    local dz = a.z - b.z
    return math.sqrt(dx*dx + dz*dz)
end

local function getZone(name)
    local z = trigger.misc.getZone(name)
    if not z then return nil end
    return { x = z.point.x, z = z.point.z, radius = z.radius or 0 }
end

-- Convert decimal degrees → degrees + decimal minutes
local function toDegMin(dec)
    local deg = math.floor(dec)
    local min = (dec - deg) * 60
    return deg, min
end

----------------------------------------------------------------
-- LIVES SYSTEM
----------------------------------------------------------------

function DGSS_CSAR.getPlayerLives(playerName)
    if not DGSS_CSAR.LIVES.enabled then return nil end
    if not playerName then return nil end

    local lives = DGSS_CSAR.PLAYER_LIVES[playerName]
    if not lives then
        lives = DGSS_CSAR.LIVES.defaultLives
        DGSS_CSAR.PLAYER_LIVES[playerName] = lives
        env.info(string.format("[CSAR-LIVES] Initialized player '%s' with %d lives", playerName, lives))
    end
    return lives
end

function DGSS_CSAR.setPlayerLives(playerName, lives)
    if not DGSS_CSAR.LIVES.enabled then return end
    if not playerName then return end
    lives = math.max(0, math.min(DGSS_CSAR.LIVES.maxLives, lives))
    DGSS_CSAR.PLAYER_LIVES[playerName] = lives
end

function DGSS_CSAR.loseLife(playerName, unit)
    if not DGSS_CSAR.LIVES.enabled then return end
    if not DGSS_CSAR.LIVES.loseLifeOnDeath then return end
    if not playerName then return end

    local current = DGSS_CSAR.getPlayerLives(playerName)
    local newLives = math.max(0, current - 1)
    DGSS_CSAR.setPlayerLives(playerName, newLives)
    
    -- Debug logging
    env.info(string.format("[CSAR-LIVES] Player '%s' lost a life: %d -> %d", playerName, current, newLives))

    if unit and unit.getID then
        pcall(function()
            trigger.action.outTextForUnit(
                unit:getID(),
                string.format(DGSS_CSAR.MESSAGES.lifeLost, newLives),
                10
            )
        end)
    end

    -- If they hit 0, start lockout
    if newLives == 0 and not DGSS_CSAR.LOCKOUT[playerName] then
        DGSS_CSAR.LOCKOUT[playerName] = now() + 600 -- 10 minutes
        env.info(string.format("[CSAR-LIVES] Player '%s' hit 0 lives - lockout started for 10 minutes", playerName))
    end
end

function DGSS_CSAR.gainLife(playerName, rescueUnit)
    if not DGSS_CSAR.LIVES.enabled then return end
    if not DGSS_CSAR.LIVES.gainLifeOnRescue then return end
    if not playerName then return end

    local current = DGSS_CSAR.getPlayerLives(playerName)
    local newLives = math.min(DGSS_CSAR.LIVES.maxLives, current + DGSS_CSAR.LIVES.lifeGainAmount)
    DGSS_CSAR.setPlayerLives(playerName, newLives)

    -- Try to find the original player's current unit to notify them directly
    local notified = false
    local allGroups = coalition.getGroups(DGSS_CSAR.COALITION)
    if allGroups then
        for _, group in ipairs(allGroups) do
            if group and group:isExist() then
                for _, unit in ipairs(group:getUnits()) do
                    if unit and unit:isExist() and unit:getPlayerName() == playerName then
                        trigger.action.outTextForUnit(
                            unit:getID(),
                            string.format(DGSS_CSAR.MESSAGES.lifeGained, newLives),
                            10
                        )
                        notified = true
                        break
                    end
                end
            end
            if notified then break end
        end
    end

    -- If original player not found in-game, broadcast to coalition
    if not notified then
        trigger.action.outTextForCoalition(
            DGSS_CSAR.COALITION,
            string.format("%s has been rescued and regained a life! (Now has %d lives)", playerName, newLives),
            10
        )
    end
end

----------------------------------------------------------------
-- CSAR CORE
----------------------------------------------------------------

function DGSS_CSAR.isValidCsarTransport(unit)
    if not unit or not unit:isExist() then return false end
    if unit:getCoalition() ~= DGSS_CSAR.COALITION then return false end

    local typeName = unit:getTypeName()
    if not DGSS_CSAR.ALLOWED_UNITS[typeName] then
        return false
    end

    return true
end

----------------------------------------------------------------
-- SURVIVOR SPAWNING (with MGRS + DM coords + distance)
----------------------------------------------------------------

function DGSS_CSAR.spawnSurvivorGroup(pos, playerName)
    local groupName = string.format("CSAR_%s_%d", playerName or "UNKNOWN", math.random(1000, 9999))
    local heading = math.random() * 2 * math.pi

    -- Offset survivor spawn 150-200m away from explosion point
    local offsetDistance = 150 + math.random() * 50  -- 150-200 meters
    local offsetAngle = math.random() * 2 * math.pi
    local offsetX = pos.x + offsetDistance * math.cos(offsetAngle)
    local offsetZ = pos.z + offsetDistance * math.sin(offsetAngle)

    local survivorGroup = {
        visible = true,
        lateActivation = false,
        tasks = {},
        task = "Ground Nothing",
        x = offsetX,
        y = offsetZ,
        name = groupName,
        units = {
            [1] = {
                name = groupName .. "_Unit_1",
                type = "Soldier M4",
                skill = "Average",
                x = offsetX,
                y = offsetZ,
                heading = heading,
                playerCanDrive = false,
                immortal = true,    -- Cannot be killed
                hidden = true,      -- Invisible to enemy AI (won't be targeted)
            },
        },
    }

    coalition.addGroup(DGSS_CSAR.COUNTRY, Group.Category.GROUND, survivorGroup)

    -- Track survivor type (player vs convoy)
    local isConvoySurvivor = playerName and string.find(playerName, "Convoy Crew")
    
    DGSS_CSAR.SURVIVORS[groupName] = {
        playerName = playerName,
        spawnTime  = timer.getTime(),
        isConvoy   = isConvoySurvivor or false,
    }

    ------------------------------------------------------------
    -- COORDINATES: MGRS + Degrees/Decimal Minutes + Distance
    ------------------------------------------------------------

    local lat, lon = coord.LOtoLL(pos)
    local mgrs = coord.LLtoMGRS(lat, lon)

    local latDeg, latMin = toDegMin(math.abs(lat))
    local lonDeg, lonMin = toDegMin(math.abs(lon))

    local latHem = (lat >= 0) and "N" or "S"
    local lonHem = (lon >= 0) and "E" or "W"

    local coordsText = string.format(
        "CSAR: Downed pilot located!\n\n" ..
        "MGRS: %s %s %05d %05d\n\n" ..
        "Lat/Lon (DM):\n" ..
        "%s %02d° %.3f'\n" ..
        "%s %03d° %.3f'",
        mgrs.UTMZone,
        mgrs.MGRSDigraph,
        mgrs.Easting,
        mgrs.Northing,
        latHem, latDeg, latMin,
        lonHem, lonDeg, lonMin
    )

    trigger.action.outTextForCoalition(DGSS_CSAR.COALITION, coordsText, 15)

    -- Note: Distance info is available via "Mark Nearest Survivor" menu option

    env.info(string.format("[CSAR] Spawned survivor '%s' for player '%s'", groupName, tostring(playerName)))
end

----------------------------------------------------------------
-- FIND NEAREST SURVIVOR (with optional type filtering)
----------------------------------------------------------------

function DGSS_CSAR.getNearestActiveSurvivor(pos, radius, filterType)
    local nearestName = nil
    local nearestDist = nil
    radius = radius or DGSS_CSAR.CSAR.nearestSearchRadius
    -- filterType can be "pilot", "convoy", or nil (for any)

    for groupName, survivorData in pairs(DGSS_CSAR.SURVIVORS) do
        -- Apply type filter if specified
        local shouldProcess = true
        if filterType then
            if filterType == "pilot" and survivorData.isConvoy then
                -- Skip convoy survivors when looking for pilots
                shouldProcess = false
            elseif filterType == "convoy" and not survivorData.isConvoy then
                -- Skip pilot survivors when looking for convoy
                shouldProcess = false
            end
        end
        
        if shouldProcess then
            local g = Group.getByName(groupName)
            if g and g:isExist() then
                local u = g:getUnit(1)
                if u and u:isExist() then
                    local upos = u:getPoint()
                    local d = _2dDist(pos, upos)
                    if d <= radius and (not nearestDist or d < nearestDist) then
                        nearestDist = d
                        nearestName = groupName
                    end
                end
            end
        end
    end

    return nearestName
end

----------------------------------------------------------------
-- REQUEST SMOKE
----------------------------------------------------------------

function DGSS_CSAR.requestSmoke(survivorGroupName)
    if not DGSS_CSAR.CSAR.smokeOnRequest then return end

    local g = Group.getByName(survivorGroupName)
    if not g or not g:isExist() then return end

    local u = g:getUnit(1)
    if not u or not u:isExist() then return end

    local pos = u:getPoint()
    trigger.action.smoke({ x = pos.x, y = pos.y, z = pos.z }, DGSS_CSAR.CSAR.smokeColor)
end

----------------------------------------------------------------
-- MARK NEAREST SURVIVOR (MESSAGE ONLY — NO MAP MARKER)
----------------------------------------------------------------

function DGSS_CSAR.markNearestSurvivor(unit, filterType)
    if not unit or not unit:isExist() then return end

    local pos = unit:getPoint()
    local nearestName = DGSS_CSAR.getNearestActiveSurvivor(pos, nil, filterType)

    if not nearestName then
        local noMsg = DGSS_CSAR.MESSAGES.noSurvivorsNearby
        if filterType == "pilot" then
            noMsg = DGSS_CSAR.MESSAGES.noPilotsNearby
        elseif filterType == "convoy" then
            noMsg = DGSS_CSAR.MESSAGES.noConvoyNearby
        end
        trigger.action.outTextForUnit(unit:getID(), noMsg, 5)
        return
    end

    local g = Group.getByName(nearestName)
    if not g or not g:isExist() then return end

    local sUnit = g:getUnit(1)
    if not sUnit or not sUnit:isExist() then return end

    local spos = sUnit:getPoint()
    local survivorData = DGSS_CSAR.SURVIVORS[nearestName]
    local survivorType = (survivorData and survivorData.isConvoy) and "Convoy Survivor" or "Downed Pilot"

    ------------------------------------------------------------
    -- DISTANCE + HEADING
    ------------------------------------------------------------
    local dx = spos.x - pos.x
    local dz = spos.z - pos.z
    local distance = math.sqrt(dx*dx + dz*dz)
    local distanceKm = distance / 1000
    local distanceNM = distance / 1852

    local heading = math.deg(math.atan2(dx, dz))
    if heading < 0 then heading = heading + 360 end

    ------------------------------------------------------------
    -- COORDINATES: MGRS + DM
    ------------------------------------------------------------
    local lat, lon = coord.LOtoLL(spos)
    local mgrs = coord.LLtoMGRS(lat, lon)

    local latDeg, latMin = toDegMin(math.abs(lat))
    local lonDeg, lonMin = toDegMin(math.abs(lon))

    local latHem = (lat >= 0) and "N" or "S"
    local lonHem = (lon >= 0) and "E" or "W"

    ------------------------------------------------------------
    -- MESSAGE ONLY
    ------------------------------------------------------------
    local msg = string.format(
        "Nearest %s:\n\n" ..
        "Distance: %.1f km (%.1f NM)\n" ..
        "Heading: %.0f°\n\n" ..
        "MGRS: %s %s %05d %05d\n\n" ..
        "Lat/Lon (DM):\n" ..
        "%s %02d° %.3f'\n" ..
        "%s %03d° %.3f'",
        survivorType,
        distanceKm,
        distanceNM,
        heading,
        mgrs.UTMZone, mgrs.MGRSDigraph, mgrs.Easting, mgrs.Northing,
        latHem, latDeg, latMin,
        lonHem, lonDeg, lonMin
    )

    trigger.action.outTextForUnit(unit:getID(), msg, 15)
end

----------------------------------------------------------------
-- PICKUP SURVIVOR
----------------------------------------------------------------

function DGSS_CSAR.pickupSurvivor(heloUnit, survivorGroupName)
    env.info("[CSAR] pickupSurvivor called for survivor: " .. tostring(survivorGroupName))
    
    if not heloUnit or not heloUnit:isExist() then 
        env.info("[CSAR] pickupSurvivor failed - helo unit invalid")
        return 
    end

    -- Check speed and altitude limits
    local condOk, condMsg = DGSS_CSAR.checkPickupDropoffConditions(heloUnit, true)
    if not condOk then
        env.info("[CSAR] pickupSurvivor failed - conditions not met: " .. condMsg)
        trigger.action.outTextForUnit(heloUnit:getID(), condMsg, 6)
        return
    end

    local g = Group.getByName(survivorGroupName)
    if not g or not g:isExist() then 
        env.info("[CSAR] pickupSurvivor failed - survivor group doesn't exist: " .. tostring(survivorGroupName))
        return 
    end

    local sUnit = g:getUnit(1)
    if not sUnit or not sUnit:isExist() then 
        env.info("[CSAR] pickupSurvivor failed - survivor unit doesn't exist")
        return 
    end

    local hpos = heloUnit:getPoint()
    local spos = sUnit:getPoint()
    local dist = _2dDist(hpos, spos)
    
    env.info(string.format("[CSAR] Distance to survivor: %.1fm (max: %dm)", dist, DGSS_CSAR.CSAR.pickupRadius))

    if dist > DGSS_CSAR.CSAR.pickupRadius then
        trigger.action.outTextForUnit(heloUnit:getID(), "Too far to pick up survivor.", 5)
        return
    end

    -- Note: Altitude and speed already checked by checkPickupDropoffConditions above
    env.info("[CSAR] Picking up survivor - destroying survivor group")
    Group.destroy(g)
    
    -- Store survivor info before removing from table
    local survivorInfo = DGSS_CSAR.SURVIVORS[survivorGroupName]
    local isConvoy = survivorInfo and survivorInfo.isConvoy or false
    local originalPlayerName = survivorInfo and survivorInfo.playerName or nil
    
    DGSS_CSAR.SURVIVORS[survivorGroupName] = nil

    local unitName = heloUnit:getName()
    DGSS_CSAR.CARRYING_SURVIVOR[unitName] =
        DGSS_CSAR.CARRYING_SURVIVOR[unitName] or { count = 0, playerSurvivors = 0, convoySurvivors = 0, originalPlayers = {} }

    DGSS_CSAR.CARRYING_SURVIVOR[unitName].count =
        DGSS_CSAR.CARRYING_SURVIVOR[unitName].count + 1
    
    -- Track type of survivor and original player
    if isConvoy then
        DGSS_CSAR.CARRYING_SURVIVOR[unitName].convoySurvivors =
            DGSS_CSAR.CARRYING_SURVIVOR[unitName].convoySurvivors + 1
    else
        DGSS_CSAR.CARRYING_SURVIVOR[unitName].playerSurvivors =
            DGSS_CSAR.CARRYING_SURVIVOR[unitName].playerSurvivors + 1
        -- Store original player name for life restoration
        if originalPlayerName and not string.find(originalPlayerName, "Convoy Crew") then
            table.insert(DGSS_CSAR.CARRYING_SURVIVOR[unitName].originalPlayers, originalPlayerName)
        end
    end

    trigger.action.outTextForUnit(heloUnit:getID(), DGSS_CSAR.MESSAGES.survivorPickedUp, 10)
end

----------------------------------------------------------------
-- DROP-OFF SURVIVORS
----------------------------------------------------------------

local function isInDropOffZone(pos)
    for _, z in ipairs(DGSS_CSAR.CSAR.dropOffZones) do
        local zone = getZone(z.zoneName)
        if zone then
            if _2dDist(pos, { x = zone.x, z = zone.z }) <= zone.radius then
                return true
            end
        end
    end
    return false
end

local function isInCSARZone(pos)
    -- Check if position is in any CSAR-safe zone (drop-off zones)
    return isInDropOffZone(pos)
end

function DGSS_CSAR.dropOffSurvivors(heloUnit)
    if not heloUnit or not heloUnit:isExist() then return end

    -- Check speed and altitude limits
    local condOk, condMsg = DGSS_CSAR.checkPickupDropoffConditions(heloUnit, false)
    if not condOk then
        trigger.action.outTextForUnit(heloUnit:getID(), condMsg, 6)
        return
    end

    local unitName = heloUnit:getName()
    local carry = DGSS_CSAR.CARRYING_SURVIVOR[unitName]

    if not carry or carry.count <= 0 then
        trigger.action.outTextForUnit(heloUnit:getID(), "No survivors onboard.", 5)
        return
    end

    local pos = heloUnit:getPoint()
    if not isInDropOffZone(pos) then
        trigger.action.outTextForUnit(heloUnit:getID(), "Not inside a CSAR base zone.", 5)
        return
    end

    local playerSurvivorsDelivered = carry.playerSurvivors or 0
    local convoySurvivorsDelivered = carry.convoySurvivors or 0
    local originalPlayers = carry.originalPlayers or {}
    
    carry.count = 0
    carry.playerSurvivors = 0
    carry.convoySurvivors = 0
    carry.originalPlayers = {}

    local msg = DGSS_CSAR.MESSAGES.survivorDropped
    if convoySurvivorsDelivered > 0 then
        msg = string.format("Survivors delivered safely! (%d player, %d convoy crew)", 
            playerSurvivorsDelivered, convoySurvivorsDelivered)
    end
    
    trigger.action.outTextForUnit(heloUnit:getID(), msg, 10)

    -- Get rescue pilot name for leaderboard tracking
    local rescuePilotName = heloUnit:getPlayerName()
    
    -- Track CSAR rescues in Leaderboard
    if rescuePilotName and DGSS_LEADERBOARD then
        -- Track player survivor rescues
        if playerSurvivorsDelivered > 0 and DGSS_LEADERBOARD.addCSARRescue then
            for i = 1, playerSurvivorsDelivered do
                pcall(function()
                    DGSS_LEADERBOARD.addCSARRescue(rescuePilotName)
                    env.info(string.format("[CSAR] Leaderboard CSAR rescue recorded for '%s'", rescuePilotName))
                end)
            end
        end
        
        -- Track convoy survivor rescues
        if convoySurvivorsDelivered > 0 and DGSS_LEADERBOARD.addConvoyRescue then
            for i = 1, convoySurvivorsDelivered do
                pcall(function()
                    DGSS_LEADERBOARD.addConvoyRescue(rescuePilotName)
                    env.info(string.format("[CSAR] Leaderboard convoy rescue recorded for '%s'", rescuePilotName))
                end)
            end
        end
    end

    -- Give lives back to ORIGINAL players who died, not the rescue pilot
    for _, originalPlayerName in ipairs(originalPlayers) do
        if originalPlayerName then
            DGSS_CSAR.gainLife(originalPlayerName, heloUnit)
            env.info(string.format("[CSAR] Life restored to original player '%s'", originalPlayerName))
        end
    end
end
----------------------------------------------------------------
-- MENU CREATION
----------------------------------------------------------------

function DGSS_CSAR.createMenusForUnit(unit)
    if not unit or not unit:isExist() then return end

    local group = unit:getGroup()
    if not group or not group:isExist() then return end

    local groupId  = group:getID()
    local nameOk, unitName = pcall(function() return unit:getName() end)
    if not nameOk or not unitName then return end

    DGSS_CSAR.UNIT_MENUS[unitName] = DGSS_CSAR.UNIT_MENUS[unitName] or {}

    ------------------------------------------------------------
    -- ROOT MENU  (CSAR)
    ------------------------------------------------------------
    local root = missionCommands.addSubMenuForGroup(groupId, "CSAR")
    DGSS_CSAR.UNIT_MENUS[unitName].root = root

    ------------------------------------------------------------
    -- DOWNED PILOTS MENU
    ------------------------------------------------------------
    local pilotsMenu = missionCommands.addSubMenuForGroup(groupId, "Downed Pilots", root)
    DGSS_CSAR.UNIT_MENUS[unitName].pilotsMenu = pilotsMenu

    -- Mark nearest pilot
    missionCommands.addCommandForGroup(
        groupId,
        "Mark Nearest Pilot",
        pilotsMenu,
        function()
            local u = Unit.getByName(unitName)
            if u and u:isExist() then
                DGSS_CSAR.markNearestSurvivor(u, "pilot")
            end
        end
    )

    -- Request pilot smoke
    missionCommands.addCommandForGroup(
        groupId,
        "Request Pilot Smoke",
        pilotsMenu,
        function()
            local u = Unit.getByName(unitName)
            if u and u:isExist() then
                local pos = u:getPoint()
                local nearestName = DGSS_CSAR.getNearestActiveSurvivor(
                    pos,
                    DGSS_CSAR.CSAR.nearestSearchRadius,
                    "pilot"
                )
                if nearestName then
                    DGSS_CSAR.requestSmoke(nearestName)
                else
                    trigger.action.outTextForUnit(u:getID(), DGSS_CSAR.MESSAGES.noPilotsNearby, 5)
                end
            end
        end
    )

    -- Pickup pilot
    missionCommands.addCommandForGroup(
        groupId,
        "Pickup Pilot",
        pilotsMenu,
        function()
            env.info("[CSAR] Pickup Pilot menu clicked for unit: " .. tostring(unitName))
            local u = Unit.getByName(unitName)
            if not u or not u:isExist() then
                env.info("[CSAR] Pickup failed - unit no longer exists: " .. tostring(unitName))
                return
            end
            
            local pos = u:getPoint()
            env.info(string.format("[CSAR] Searching for pilots within %dm of position (%.1f, %.1f)", 
                DGSS_CSAR.CSAR.pickupRadius, pos.x, pos.z))
            
            local nearestName = DGSS_CSAR.getNearestActiveSurvivor(
                pos,
                DGSS_CSAR.CSAR.pickupRadius,
                "pilot"
            )
            if nearestName then
                env.info("[CSAR] Found nearest pilot: " .. nearestName)
                DGSS_CSAR.pickupSurvivor(u, nearestName)
            else
                env.info("[CSAR] No pilots found within pickup radius")
                trigger.action.outTextForUnit(u:getID(), DGSS_CSAR.MESSAGES.noPilotsNearby, 5)
            end
        end
    )

    -- Drop off pilots
    missionCommands.addCommandForGroup(
        groupId,
        "Drop Off Pilots",
        pilotsMenu,
        function()
            local u = Unit.getByName(unitName)
            if u and u:isExist() then
                DGSS_CSAR.dropOffSurvivors(u)
            end
        end
    )

    ------------------------------------------------------------
    -- CONVOY SURVIVORS MENU
    ------------------------------------------------------------
    local convoyMenu = missionCommands.addSubMenuForGroup(groupId, "Convoy Survivors", root)
    DGSS_CSAR.UNIT_MENUS[unitName].convoyMenu = convoyMenu

    -- Mark nearest convoy survivor
    missionCommands.addCommandForGroup(
        groupId,
        "Mark Nearest Convoy Survivor",
        convoyMenu,
        function()
            local u = Unit.getByName(unitName)
            if u and u:isExist() then
                DGSS_CSAR.markNearestSurvivor(u, "convoy")
            end
        end
    )

    -- Request convoy smoke
    missionCommands.addCommandForGroup(
        groupId,
        "Request Convoy Smoke",
        convoyMenu,
        function()
            local u = Unit.getByName(unitName)
            if u and u:isExist() then
                local pos = u:getPoint()
                local nearestName = DGSS_CSAR.getNearestActiveSurvivor(
                    pos,
                    DGSS_CSAR.CSAR.nearestSearchRadius,
                    "convoy"
                )
                if nearestName then
                    DGSS_CSAR.requestSmoke(nearestName)
                else
                    trigger.action.outTextForUnit(u:getID(), DGSS_CSAR.MESSAGES.noConvoyNearby, 5)
                end
            end
        end
    )

    -- Pickup convoy survivor
    missionCommands.addCommandForGroup(
        groupId,
        "Pickup Convoy Survivor",
        convoyMenu,
        function()
            env.info("[CSAR] Pickup Convoy Survivor menu clicked for unit: " .. tostring(unitName))
            local u = Unit.getByName(unitName)
            if not u or not u:isExist() then
                env.info("[CSAR] Pickup failed - unit no longer exists: " .. tostring(unitName))
                return
            end
            
            local pos = u:getPoint()
            env.info(string.format("[CSAR] Searching for convoy survivors within %dm of position (%.1f, %.1f)", 
                DGSS_CSAR.CSAR.pickupRadius, pos.x, pos.z))
            
            local nearestName = DGSS_CSAR.getNearestActiveSurvivor(
                pos,
                DGSS_CSAR.CSAR.pickupRadius,
                "convoy"
            )
            if nearestName then
                env.info("[CSAR] Found nearest convoy survivor: " .. nearestName)
                DGSS_CSAR.pickupSurvivor(u, nearestName)
            else
                env.info("[CSAR] No convoy survivors found within pickup radius")
                trigger.action.outTextForUnit(u:getID(), DGSS_CSAR.MESSAGES.noConvoyNearby, 5)
            end
        end
    )

    -- Drop off convoy survivors
    missionCommands.addCommandForGroup(
        groupId,
        "Drop Off Convoy Survivors",
        convoyMenu,
        function()
            local u = Unit.getByName(unitName)
            if u and u:isExist() then
                DGSS_CSAR.dropOffSurvivors(u)
            end
        end
    )
end

----------------------------------------------------------------
-- EVENT HANDLER (PILOT DEAD, EJECTION, SLOT LEAVE only)
-- Simplified: Only 3 events, with anti-duplicate protection
----------------------------------------------------------------

local PLAYER_EVENT_HANDLER_CSAR = {}

function PLAYER_EVENT_HANDLER_CSAR:onEvent(event)
    if not event or not event.id then return end

    local eventId = event.id
    local unit = event.initiator
    
    -- Only handle these 3 specific events
    local isDeathEvent = (eventId == world.event.S_EVENT_PILOT_DEAD)
    local isEjectEvent = (eventId == world.event.S_EVENT_EJECTION)
    local isLeaveEvent = (eventId == world.event.S_EVENT_PLAYER_LEAVE_UNIT)
    
    if not isDeathEvent and not isEjectEvent and not isLeaveEvent then
        return
    end
    
    -- COALITION CHECK: Only spawn survivors for BLUE coalition
    if unit then
        local okCoal, unitCoalition = pcall(function() return unit:getCoalition() end)
        if okCoal and unitCoalition and unitCoalition ~= DGSS_CSAR.COALITION then
            env.info(string.format("[CSAR] Ignoring event - unit is not BLUE coalition (coalition: %s)", tostring(unitCoalition)))
            return
        end
    end
    
    -- For leave event, also handle menu cleanup
    -- NOTE: We no longer call missionCommands.removeItem() to avoid corrupting menu callbacks
    -- The menu will be orphaned but this is safer than breaking other scripts' menus
    if isLeaveEvent then
        if unit then
            local okName, unitName = pcall(function() return unit:getName() end)
            if okName and unitName then
                -- Just clear our tracking - don't remove the menu item
                DGSS_CSAR.UNIT_MENUS[unitName] = nil
            end
        end
    end
    
    -- Get player name safely
    if not unit then return end
    local okPlayerName, playerName = pcall(function() return unit:getPlayerName() end)
    if not okPlayerName or not playerName then return end
    
    -- Anti-duplicate: For death/eject events, use longer cooldown to prevent double life loss
    -- This handles scenarios like: crash-land -> survive -> eject -> aircraft explodes
    local t = timer.getTime()
    
    -- FIRST: Check if this player already had an incident processed within the cooldown window
    -- This is the PRIMARY protection against double life loss
    local lastIncident = DGSS_CSAR.INCIDENT_PROCESSED[playerName]
    if lastIncident and (t - lastIncident) < DGSS_CSAR.INCIDENT_COOLDOWN then
        -- Block ALL death/eject/leave events during cooldown - player already had their incident processed
        env.info(string.format("[CSAR] Event BLOCKED for '%s' - incident cooldown active (%.2fs since last, cooldown is %ds)", 
            playerName, t - lastIncident, DGSS_CSAR.INCIDENT_COOLDOWN))
        
        -- Still allow menu cleanup on leave event, but don't process life loss
        if isLeaveEvent then
            -- Menu cleanup already happened above, just return
        end
        return
    end
    
    -- Set the incident timestamp IMMEDIATELY before any processing
    -- This ensures any subsequent events within the cooldown window are blocked
    DGSS_CSAR.INCIDENT_PROCESSED[playerName] = t
    DGSS_CSAR.LAST_EVENT_TIME[playerName] = t
    
    -- Determine event type for logging
    local reason = "UNKNOWN"
    if isDeathEvent then reason = "PILOT_DEAD" end
    if isEjectEvent then reason = "EJECTION" end
    if isLeaveEvent then reason = "SLOT_LEAVE" end
    
    env.info(string.format("[CSAR] Processing %s for player '%s'", reason, playerName))
    
    -- For slot leave, only penalize if outside safe zone AND not recently ejected
    if isLeaveEvent then
        -- Check if player recently ejected - they are exempt from SLOT_LEAVE penalties
        local ejectTime = DGSS_CSAR.EJECTED_PLAYERS[playerName]
        if ejectTime and (t - ejectTime) < DGSS_CSAR.EJECT_EXEMPTION_TIME then
            env.info(string.format("[CSAR] SLOT_LEAVE for '%s' - exempt (ejected %.1fs ago, exemption lasts %ds)", 
                playerName, t - ejectTime, DGSS_CSAR.EJECT_EXEMPTION_TIME))
            -- Clear the incident marker since no penalty was applied
            DGSS_CSAR.INCIDENT_PROCESSED[playerName] = nil
            -- Clear the eject tracking now that they've slotted out
            DGSS_CSAR.EJECTED_PLAYERS[playerName] = nil
            return
        end
        
        local okPos, pos = pcall(function() return unit:getPoint() end)
        if not okPos or not pos then
            env.info(string.format("[CSAR] Could not get position for '%s' during %s", playerName, reason))
            return
        end
        
        if isInCSARZone(pos) then
            env.info(string.format("[CSAR] SLOT_LEAVE for '%s' in safe zone - no penalty", playerName))
            -- Clear the incident marker since no penalty was applied
            DGSS_CSAR.INCIDENT_PROCESSED[playerName] = nil
            return
        end
        
        -- Outside safe zone - lose life and spawn survivor
        env.info(string.format("[CSAR] SLOT_LEAVE for '%s' outside safe zone - combat log penalty", playerName))
        -- Incident already marked at top of function
        pcall(function() DGSS_CSAR.loseLife(playerName, unit) end)
        
        -- Track death in Leaderboard (combat log)
        if DGSS_LEADERBOARD and DGSS_LEADERBOARD.addPlayerDeath then
            pcall(function()
                DGSS_LEADERBOARD.addPlayerDeath(playerName)
                env.info(string.format("[CSAR] Leaderboard death recorded for '%s' (combat log)", playerName))
            end)
        end
        
        local groundAlt = land.getHeight({ x = pos.x, y = pos.z }) or 0
        local groundPos = { x = pos.x, y = groundAlt, z = pos.z }
        DGSS_CSAR.spawnSurvivorGroup(groundPos, playerName)
        return
    end
    
    -- For death/eject events - check if in CSAR zone first
    -- Incident already marked at top of function
    env.info(string.format("[CSAR] Processing life loss for '%s' - cooldown active for %d seconds", playerName, DGSS_CSAR.INCIDENT_COOLDOWN))
    
    -- Get position safely
    local okPos, pos = pcall(function() return unit:getPoint() end)
    if not okPos or not pos then
        env.info(string.format("[CSAR] Could not get position for '%s' during %s", playerName, reason))
        return
    end
    
    -- Check if crash/eject happened in a CSAR safe zone
    if isInCSARZone(pos) then
        env.info(string.format("[CSAR] Player '%s' crashed/ejected in safe zone - no life lost!", playerName))
        trigger.action.outText(string.format("%s crashed at base - no life lost!", playerName), 10)
        -- Clear the incident marker since no penalty was applied
        DGSS_CSAR.INCIDENT_PROCESSED[playerName] = nil
        return
    end
    
    -- Track ejection so player is exempt from SLOT_LEAVE penalty when leaving the parachute
    if isEjectEvent then
        DGSS_CSAR.EJECTED_PLAYERS[playerName] = t
        env.info(string.format("[CSAR] Player '%s' marked as ejected - exempt from SLOT_LEAVE for %d seconds", playerName, DGSS_CSAR.EJECT_EXEMPTION_TIME))
    end
    
    pcall(function() DGSS_CSAR.loseLife(playerName, unit) end)
    
    -- Track death in Leaderboard
    if DGSS_LEADERBOARD and DGSS_LEADERBOARD.addPlayerDeath then
        pcall(function()
            DGSS_LEADERBOARD.addPlayerDeath(playerName)
            env.info(string.format("[CSAR] Leaderboard death recorded for '%s'", playerName))
        end)
    end
    
    -- Position already retrieved earlier for safe zone check
    -- Log the raw position for debugging
    env.info(string.format("[CSAR] Raw position for '%s': x=%.1f, y=%.1f (alt), z=%.1f", 
        playerName, pos.x, pos.y, pos.z))
    
    -- CHECK IF THIS AIRCRAFT WAS CARRYING SURVIVORS - RESPAWN THEM!
    local unitName = unit:getName()
    local carry = DGSS_CSAR.CARRYING_SURVIVOR[unitName]
    if carry and carry.count > 0 then
        local playerSurvivors = carry.playerSurvivors or 0
        local convoySurvivors = carry.convoySurvivors or 0
        local originalPlayers = carry.originalPlayers or {}
        
        env.info(string.format("[CSAR] Rescue aircraft '%s' crashed with %d survivors onboard! Respawning them...", unitName, carry.count))
        
        local groundAlt = land.getHeight({ x = pos.x, y = pos.z }) or 0
        local groundPos = { x = pos.x, y = groundAlt, z = pos.z }
        
        -- Respawn player survivors with their original names
        for i, originalPlayerName in ipairs(originalPlayers) do
            DGSS_CSAR.spawnSurvivorGroup(groundPos, originalPlayerName)
            env.info(string.format("[CSAR] Respawned player survivor: %s", originalPlayerName))
        end
        
        -- Respawn convoy survivors
        for i = 1, convoySurvivors do
            DGSS_CSAR.spawnSurvivorGroup(groundPos, string.format("Convoy Crew %d", i))
            env.info(string.format("[CSAR] Respawned convoy survivor %d", i))
        end
        
        -- Clear the carried survivors from this aircraft
        DGSS_CSAR.CARRYING_SURVIVOR[unitName] = nil
        
        -- Notify coalition
        trigger.action.outTextForCoalition(DGSS_CSAR.COALITION,
            string.format("Rescue aircraft crashed! %d survivor(s) are down at the crash site!", carry.count), 15)
    end
    
    -- Convert to Lat/Lon for debugging
    local lat, lon = coord.LOtoLL(pos)
    env.info(string.format("[CSAR] Position in Lat/Lon for '%s': %.6f, %.6f", playerName, lat, lon))
    
    -- Project to ground level
    local groundAlt = land.getHeight({ x = pos.x, y = pos.z }) or 0
    pos.y = groundAlt
    
    env.info(string.format("[CSAR] Ground position for '%s': x=%.1f, y=%.1f (ground alt), z=%.1f", 
        playerName, pos.x, pos.y, pos.z))
    
    DGSS_CSAR.spawnSurvivorGroup(pos, playerName)
    env.info(string.format("[CSAR] Survivor spawned for '%s' at (%.1f, %.1f)", playerName, pos.x, pos.z))
    
    -- Cleanup carried survivors if aircraft destroyed
    if isDeathEvent then
        local okUnitName, unitName = pcall(function() return unit:getName() end)
        if okUnitName and unitName and DGSS_CSAR.CARRYING_SURVIVOR[unitName] then
            env.info(string.format("[CSAR] Cleaning up carried survivors for destroyed aircraft '%s'", unitName))
            DGSS_CSAR.CARRYING_SURVIVOR[unitName] = nil
        end
    end
end

world.addEventHandler(PLAYER_EVENT_HANDLER_CSAR)

----------------------------------------------------------------
-- CONVOY SURVIVOR SPAWNING
-- Detects convoy units and spawns survivors when they die
----------------------------------------------------------------

-- Track convoy units to spawn survivors
DGSS_CSAR.TRACKED_CONVOY_UNITS = {}

function DGSS_CSAR.trackConvoyUnit(unitName)
    if not unitName then return end
    DGSS_CSAR.TRACKED_CONVOY_UNITS[unitName] = true
    env.info("[CSAR] Now tracking convoy unit: " .. unitName)
end

function DGSS_CSAR.trackConvoyGroup(groupName)
    if not groupName then return end
    local group = Group.getByName(groupName)
    if not group or not group:isExist() then return end
    
    for _, unit in ipairs(group:getUnits()) do
        if unit and unit:isExist() then
            local nameOk, unitName = pcall(function() return unit:getName() end)
            if nameOk and unitName then
                DGSS_CSAR.trackConvoyUnit(unitName)
            end
        end
    end
end

-- Convoy group names to track
DGSS_CSAR.CONVOY_NAMES = {
    "Light Armor & Supply",
    "Medium Armor Convoy",
    "Heavy Armor Convoy",
    "Logistics Supply Train",
    "Mixed Force Convoy"
}

-- Automatically detect and track convoy groups by exact name
function DGSS_CSAR.autoDetectConvoys()
    pcall(function()
        for _, convoyName in ipairs(DGSS_CSAR.CONVOY_NAMES) do
            local group = Group.getByName(convoyName)
            if group and group:isExist() then
                DGSS_CSAR.trackConvoyGroup(convoyName)
            end
        end
    end)
end

-- Event handler for convoy deaths
local CONVOY_EVENT_HANDLER = {}

function CONVOY_EVENT_HANDLER:onEvent(event)
    if not event or not event.id then return end
    if event.id ~= world.event.S_EVENT_DEAD then return end
    
    local unit = event.initiator
    if not unit then return end
    
    -- Safely get unit name with pcall protection
    local nameOk, unitName = pcall(function() return unit:getName() end)
    if not nameOk or not unitName then return end
    
    -- Check if this is a tracked convoy unit
    if DGSS_CSAR.TRACKED_CONVOY_UNITS[unitName] then
        local posOk, pos = pcall(function() return unit:getPoint() end)
        if posOk and pos then
            -- Spawn survivor with convoy identifier
            local survivorName = "Convoy Crew - " .. unitName
            DGSS_CSAR.spawnSurvivorGroup(pos, survivorName)
            env.info(string.format("[CSAR] Convoy survivor spawned from %s at (%.1f, %.1f)",
                unitName, pos.x, pos.z))
            
            -- Generate coordinates message for convoy survivor
            local lat, lon = coord.LOtoLL(pos)
            local mgrs = coord.LLtoMGRS(lat, lon)
            
            local latDeg, latMin = toDegMin(math.abs(lat))
            local lonDeg, lonMin = toDegMin(math.abs(lon))
            
            local latHem = (lat >= 0) and "N" or "S"
            local lonHem = (lon >= 0) and "E" or "W"
            
            local coordsText = string.format(
                "CSAR: Convoy crew down! (1 survivor)\n\n" ..
                "MGRS: %s %s %05d %05d\n\n" ..
                "Lat/Lon (DM):\n" ..
                "%s %02d° %.3f'\n" ..
                "%s %03d° %.3f'",
                mgrs.UTMZone,
                mgrs.MGRSDigraph,
                mgrs.Easting,
                mgrs.Northing,
                latHem, latDeg, latMin,
                lonHem, lonDeg, lonMin
            )
            
            trigger.action.outTextForCoalition(DGSS_CSAR.COALITION, coordsText, 15)
        end
        
        -- Remove from tracking
        DGSS_CSAR.TRACKED_CONVOY_UNITS[unitName] = nil
    end
end

world.addEventHandler(CONVOY_EVENT_HANDLER)

-- Run auto-detection every 120 seconds to catch new convoys (reduced frequency for performance)
local function convoyDetectionLoop()
    DGSS_CSAR.autoDetectConvoys()
    
    if mist and mist.scheduleFunction then
        mist.scheduleFunction(convoyDetectionLoop, {}, timer.getTime() + 120)
    else
        timer.scheduleFunction(convoyDetectionLoop, {}, timer.getTime() + 120)
    end
end

-- Start convoy detection
if mist and mist.scheduleFunction then
    mist.scheduleFunction(convoyDetectionLoop, {}, timer.getTime() + 5)
else
    timer.scheduleFunction(convoyDetectionLoop, {}, timer.getTime() + 5)
end

----------------------------------------------------------------
-- UNIVERSAL MENU POLLER
-- Attaches CSAR menus to any player‑controlled CSAR aircraft
----------------------------------------------------------------

local function safeCreateMenusForUnit_CSAR(unit)
    if not unit or not unit:isExist() then return end
    if not unit:getPlayerName() then return end
    if not DGSS_CSAR.isValidCsarTransport(unit) then return end

    local nameOk, unitName = pcall(function() return unit:getName() end)
    if not nameOk or not unitName then return end
    if DGSS_CSAR.UNIT_MENUS[unitName] then return end

    DGSS_CSAR.createMenusForUnit(unit)
end

local LIVES_MENU_GROUPS = {}

local function createUniversalLivesMenu(group)
    if not group or not group:isExist() then return end
    
    local groupId = group:getID()
    local nameOk, groupName = pcall(function() return group:getName() end)
    if not nameOk or not groupName then return end
    
    -- Skip if we've already added the menu to this group
    if LIVES_MENU_GROUPS[groupId] then return end
    
    -- Add universal Lives menu available to everyone
    if DGSS_CSAR.LIVES.enabled then
        -- Capture groupId and groupName in local variables for the closure
        local capturedGroupId = groupId
        local capturedGroupName = groupName
        env.info(string.format("[CSAR] Adding Check Lives menu to group %d (%s)", capturedGroupId, capturedGroupName))
        
        missionCommands.addCommandForGroup(
            capturedGroupId,
            "Check Lives",
            nil,
            function()
                env.info(string.format("[CSAR] Check Lives menu clicked for group %s", capturedGroupName))
                
                -- Re-fetch the group by NAME (Group.getByID doesn't exist in DCS!)
                local currentGroup = Group.getByName(capturedGroupName)
                if not currentGroup then
                    env.info("[CSAR] Check Lives: Group.getByName returned nil")
                    return
                end
                
                local groupExists = false
                local ok, err = pcall(function() groupExists = currentGroup:isExist() end)
                if not ok then
                    env.info("[CSAR] Check Lives: isExist() failed: " .. tostring(err))
                    return
                end
                if not groupExists then 
                    env.info("[CSAR] Check Lives: Group no longer exists")
                    return 
                end
                
                local units = currentGroup:getUnits()
                if not units or #units == 0 then 
                    env.info("[CSAR] Check Lives: No units in group")
                    return 
                end
                
                local u = units[1]
                if not u then
                    env.info("[CSAR] Check Lives: First unit is nil")
                    return
                end
                
                local unitExists = false
                ok, err = pcall(function() unitExists = u:isExist() end)
                if not ok then
                    env.info("[CSAR] Check Lives: unit isExist() failed: " .. tostring(err))
                    return
                end
                if not unitExists then 
                    env.info("[CSAR] Check Lives: Unit does not exist")
                    return 
                end
                
                local playerName = u:getPlayerName()
                env.info(string.format("[CSAR] Check Lives: playerName = %s", tostring(playerName)))
                
                if not playerName then
                    env.info("[CSAR] Check Lives: No player name on unit")
                    trigger.action.outTextForGroup(capturedGroupId, "Could not determine player name.", 5)
                    return
                end
                
                local lives = DGSS_CSAR.getPlayerLives(playerName) or 0
                local lockout = DGSS_CSAR.LOCKOUT[playerName]
                local msg
                
                if lockout and lockout > timer.getTime() then
                    local remaining = math.max(0, math.floor((lockout - timer.getTime()) / 60))
                    msg = string.format("%s: You have %d lives remaining. Lockout ends in ~%d minutes.", playerName, lives, remaining)
                else
                    msg = string.format("%s: You have %d lives remaining.", playerName, lives)
                end
                
                env.info(string.format("[CSAR] Check Lives: Sending message to group %d (%s): %s", capturedGroupId, capturedGroupName, msg))
                trigger.action.outTextForGroup(capturedGroupId, msg, 8)
            end
        )
    end
    
    LIVES_MENU_GROUPS[groupId] = groupName  -- Store the name so we can look it up later
end

local function universalMenuPoller_CSAR()
    local bluePlanes = coalition.getGroups(DGSS_CSAR.COALITION, Group.Category.AIRPLANE) or {}
    local blueHelos  = coalition.getGroups(DGSS_CSAR.COALITION, Group.Category.HELICOPTER) or {}

    for _, group in ipairs(bluePlanes) do
        if group and group:isExist() then
            -- Add universal lives menu to all groups
            createUniversalLivesMenu(group)
            
            -- Add CSAR menus only to CSAR-capable units
            for _, unit in ipairs(group:getUnits()) do
                safeCreateMenusForUnit_CSAR(unit)
            end
        end
    end

    for _, group in ipairs(blueHelos) do
        if group and group:isExist() then
            -- Add universal lives menu to all groups
            createUniversalLivesMenu(group)
            
            -- Add CSAR menus only to CSAR-capable units
            for _, unit in ipairs(group:getUnits()) do
                safeCreateMenusForUnit_CSAR(unit)
            end
        end
    end

    if mist and mist.scheduleFunction then
        mist.scheduleFunction(universalMenuPoller_CSAR, {}, timer.getTime() + 12)
    else
        timer.scheduleFunction(universalMenuPoller_CSAR, {}, timer.getTime() + 12)
    end
end

if mist and mist.scheduleFunction then
    mist.scheduleFunction(universalMenuPoller_CSAR, {}, timer.getTime() + 8)
else
    timer.scheduleFunction(universalMenuPoller_CSAR, {}, timer.getTime() + 8)
end

----------------------------------------------------------------
-- SURVIVOR CLEANUP LOOP
----------------------------------------------------------------

local function cleanupSurvivors()
    local cleaned = 0
    
    -- Clean up dead survivor groups
    for groupName, _ in pairs(DGSS_CSAR.SURVIVORS) do
        local g = Group.getByName(groupName)
        if not g or not g:isExist() then
            DGSS_CSAR.SURVIVORS[groupName] = nil
            cleaned = cleaned + 1
        end
    end
    
    -- Clean up dead tracked convoy units (memory leak prevention)
    for unitName, _ in pairs(DGSS_CSAR.TRACKED_CONVOY_UNITS) do
        local unit = Unit.getByName(unitName)
        if not unit or not unit:isExist() then
            DGSS_CSAR.TRACKED_CONVOY_UNITS[unitName] = nil
            cleaned = cleaned + 1
        end
    end
    
    -- Clean up stale incident tracking (older than 5 minutes)
    local t = timer.getTime()
    for playerName, timestamp in pairs(DGSS_CSAR.INCIDENT_PROCESSED) do
        if (t - timestamp) > 300 then
            DGSS_CSAR.INCIDENT_PROCESSED[playerName] = nil
            cleaned = cleaned + 1
        end
    end
    
    -- Clean up stale ejection tracking (older than 6 minutes)
    for playerName, timestamp in pairs(DGSS_CSAR.EJECTED_PLAYERS) do
        if (t - timestamp) > 360 then
            DGSS_CSAR.EJECTED_PLAYERS[playerName] = nil
            cleaned = cleaned + 1
        end
    end
    
    -- Clean up stale event time tracking (older than 2 minutes)
    for playerName, timestamp in pairs(DGSS_CSAR.LAST_EVENT_TIME) do
        if (t - timestamp) > 120 then
            DGSS_CSAR.LAST_EVENT_TIME[playerName] = nil
            cleaned = cleaned + 1
        end
    end
    
    if cleaned > 0 then
        env.info(string.format("[CSAR] Cleaned up %d stale tracking entries", cleaned))
    end

    if mist and mist.scheduleFunction then
        mist.scheduleFunction(cleanupSurvivors, {}, timer.getTime() + 60)
    else
        timer.scheduleFunction(cleanupSurvivors, {}, timer.getTime() + 60)
    end
end

if mist and mist.scheduleFunction then
    mist.scheduleFunction(cleanupSurvivors, {}, timer.getTime() + 60)
else
    timer.scheduleFunction(cleanupSurvivors, {}, timer.getTime() + 60)
end

----------------------------------------------------------------
-- LIVES MENU GROUPS CLEANUP LOOP
----------------------------------------------------------------

local function cleanupLivesMenuGroups()
    local cleaned = 0
    
    -- Clean up lives menu groups
    for groupId, groupName in pairs(LIVES_MENU_GROUPS) do
        local group = Group.getByName(groupName)
        if not group or not group:isExist() then
            LIVES_MENU_GROUPS[groupId] = nil
            cleaned = cleaned + 1
        end
    end
    
    -- Clean up orphaned UNIT_MENUS entries
    for unitName, _ in pairs(DGSS_CSAR.UNIT_MENUS) do
        local unit = Unit.getByName(unitName)
        if not unit or not unit:isExist() then
            DGSS_CSAR.UNIT_MENUS[unitName] = nil
            cleaned = cleaned + 1
        end
    end
    
    -- Clean up orphaned CARRYING_SURVIVOR entries
    for unitName, _ in pairs(DGSS_CSAR.CARRYING_SURVIVOR) do
        local unit = Unit.getByName(unitName)
        if not unit or not unit:isExist() then
            DGSS_CSAR.CARRYING_SURVIVOR[unitName] = nil
            cleaned = cleaned + 1
        end
    end
    
    if cleaned > 0 then
        env.info(string.format("[CSAR] Cleaned up %d dead menu/tracking entries", cleaned))
    end

    if mist and mist.scheduleFunction then
        mist.scheduleFunction(cleanupLivesMenuGroups, {}, timer.getTime() + 60)
    else
        timer.scheduleFunction(cleanupLivesMenuGroups, {}, timer.getTime() + 60)
    end
end

if mist and mist.scheduleFunction then
    mist.scheduleFunction(cleanupLivesMenuGroups, {}, timer.getTime() + 60)
else
    timer.scheduleFunction(cleanupLivesMenuGroups, {}, timer.getTime() + 60)
end

----------------------------------------------------------------
-- HARD LOCKOUT SYSTEM
-- Prevents spawning when player has 0 lives
-- Silent despawn + 10 min regen
----------------------------------------------------------------

local function checkPlayerSpawnLockout()
    local bluePlanes = coalition.getGroups(DGSS_CSAR.COALITION, Group.Category.AIRPLANE) or {}
    local blueHelos  = coalition.getGroups(DGSS_CSAR.COALITION, Group.Category.HELICOPTER) or {}

    local function processGroup(g)
        if not g or not g:isExist() then return end

        for _, unit in ipairs(g:getUnits()) do
            if unit and unit:isExist() then
                local playerName = unit:getPlayerName()

                if playerName then
                    -- FIRST: Check if lockout timer expired and restore life
                    local unlockTime = DGSS_CSAR.LOCKOUT[playerName]
                    if unlockTime and timer.getTime() >= unlockTime then
                        DGSS_CSAR.LOCKOUT[playerName] = nil
                        DGSS_CSAR.setPlayerLives(playerName, 1)
                        trigger.action.outTextForUnit(unit:getID(),
                            "You have regained 1 life. You may now fly again.",
                            10
                        )
                        env.info(string.format("[CSAR] Player '%s' lockout expired, restored to 1 life", playerName))
                    end

                    -- THEN: Get current lives (AFTER potential restoration)
                    local lives = DGSS_CSAR.getPlayerLives(playerName)
                    local isLockedOut = DGSS_CSAR.LOCKOUT[playerName] ~= nil

                    -- Only despawn if lives is truly 0 AND lockout is active
                    if lives == 0 and isLockedOut then
                        -- Notify player BEFORE destroying the unit
                        trigger.action.outTextForUnit(
                            unit:getID(),
                            "You have 0 lives remaining. A new life will be restored in 10 minutes.",
                            8
                        )
                        
                        env.info(string.format("[CSAR] Despawning player '%s' - 0 lives and locked out", playerName))
                        
                        -- Now destroy the group
                        local group = unit:getGroup()
                        if group and group:isExist() then
                            Group.destroy(group)
                        end
                    elseif lives == 0 and not isLockedOut then
                        -- Lives is 0 but no lockout set - this shouldn't happen, but start lockout now
                        DGSS_CSAR.LOCKOUT[playerName] = timer.getTime() + 600
                        env.info(string.format("[CSAR] Player '%s' has 0 lives but no lockout - starting lockout now", playerName))
                        
                        trigger.action.outTextForUnit(
                            unit:getID(),
                            "You have 0 lives remaining. A new life will be restored in 10 minutes.",
                            8
                        )
                        
                        local group = unit:getGroup()
                        if group and group:isExist() then
                            Group.destroy(group)
                        end
                    end
                    -- If lives > 0, do nothing - player is fine
                end
            end
        end
    end

    for _, g in ipairs(bluePlanes) do processGroup(g) end
    for _, g in ipairs(blueHelos) do processGroup(g) end

    if mist and mist.scheduleFunction then
        mist.scheduleFunction(checkPlayerSpawnLockout, {}, timer.getTime() + 8)
    else
        timer.scheduleFunction(checkPlayerSpawnLockout, {}, timer.getTime() + 8)
    end
end

if mist and mist.scheduleFunction then
    mist.scheduleFunction(checkPlayerSpawnLockout, {}, timer.getTime() + 8)
else
    timer.scheduleFunction(checkPlayerSpawnLockout, {}, timer.getTime() + 8)
end

----------------------------------------------------------------
-- DEBUG: SCRIPT LOADED
----------------------------------------------------------------

trigger.action.outText(
    "[CSAR] CSAR + Lives System v4.9 Loaded",
    12
)

env.info("[CSAR] CSAR + Lives System v4.9 initialization complete.")
