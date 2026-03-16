-- Created by Lexik"ROBOT"dark & Eilliem"Six'O'Clock" for the American Vikings server.
-- Purpose of this Script is to track a Players Time through a series of Gates and time it with fairly high accuracy.
-- To do this it uses its own Stopwatch for each player and logs the time to a file in the Saved Games folder that you open up and check a players time.
-- The exported txt file is Called PlayerTimesLog.txt and can be Found in your C:\Users\YourName\Saved Games\DCS\PlayerTimesLog.txt
-- Feel free to modify the script to your liking, but please give credit to the original authors (though not required as this is meant to be a community script for anyone to use easily).
--
-- VERSION 4.0 FIXES (over V3.0):
-- - Fixed: "Reset My Race" radio command is now scoped per-group — no longer resets all pilots at once.
--          The command is added to each group the first time a pilot in that group starts a race.
-- - Fixed: Finish zone duplicate log entries — a sentinel flag (finishedPlayers) blocks re-entry
--          during the 5-second cleanup delay, preventing up to 50 duplicate log writes per finish.
-- - Fixed: Skipped gates were being double-penalized (counted as both skipped AND missed).
--          Skipped gates are now cleared from missedZones so only the skip penalty applies.
-- - Fixed: io.open failure now raises a clear "Cannot open log file" error inside the pcall
--          instead of a confusing nil-index crash.
-- - Fixed: lastSeenPlayers table no longer leaks stale entries for players who connected but
--          never crossed the start line — entries are now cleaned up on disconnect timeout.
-- - Fixed: All race state tables are now globally scoped (matching `timing`) so they survive
--          script reloads mid-mission without leaving orphaned stopwatch objects.
--
-- V4.0 HOTFIX:
-- - Changed: "Skipped" and "missed" gates unified — both are simply "missed" with the same penalty.
-- - Changed: 2+ missed gates in a single race nullifies the run (must start over).
-- - Added: Real-time feedback when gates are missed — tells the player which gate(s).
-- - Fixed: Gate passed during skip detection was still counted as missed (phantom penalty).
-- - Fixed: Crash during 5-second finish cleanup no longer fires redundant cleanup.

trigger.action.outText("Race Script V4.0 Initializing...", 10)

-- Stopwatch functionality
local Stopwatch = {}
Stopwatch.__index = Stopwatch

-- Create a new stopwatch instance
function Stopwatch:New()
    local stopwatch = {
        startTime = nil,
        elapsedTime = 0,
        running = false
    }
    setmetatable(stopwatch, Stopwatch)
    return stopwatch
end

-- Start the stopwatch
function Stopwatch:Start()
    if not self.running then
        self.startTime = timer.getTime()
        self.running = true
    end
end

-- Stop the stopwatch
function Stopwatch:Stop()
    if self.running then
        local currentTime = timer.getTime()
        self.elapsedTime = self.elapsedTime + (currentTime - self.startTime)
        self.running = false
    end
end

-- Get the elapsed time in seconds and hundredths of a second
function Stopwatch:GetElapsedTime()
    local elapsedTime = self.elapsedTime
    if self.running then
        elapsedTime = elapsedTime + (timer.getTime() - self.startTime)
    end
    return elapsedTime
end

-- Format time in seconds and hundredths of a second without rounding
function Stopwatch:FormatTime(time)
    local seconds = math.floor(time)
    local hundredths = math.floor((time - seconds) * 100)
    local formattedTime = string.format("%d.%02d", seconds, hundredths)
    return formattedTime
end

-- Race configuration
local startZoneName = "StartingLine"
local endZoneName = "FinishLine"
local zonesToTime = {
    "Gate 1", 
    "Gate 2", 
    "Gate 3", 
    "Gate 4", 
    "Gate 5", 
    "Gate 6", 
    "Gate 7", 
    "Gate 8", 
    "Gate 9", 
    "Gate 10",
    "Gate 11", 
    "Gate 12", 
    "Gate 13", 
    "Gate 14", 
    "Gate 15", 
    "Gate 16", 
    "Gate 17", 
    "Gate 18", 
    "Gate 19", 
    "Gate 20"
}

local altitudeLimit = 250 -- Maximum altitude in meters AGL
local penaltyTime = 5 -- Penalty time in seconds per missed gate
local logFileName = lfs.writedir() .. "PlayerTimesLog.txt" -- Path to Saved Games folder

-- Race state tracking (all global so they survive script reloads consistently)
timing = timing or {}
missedZones = missedZones or {}
reportedZones = reportedZones or {}
gateSequence = gateSequence or {}
aircraftTypes = aircraftTypes or {}
lastSeenPlayers = lastSeenPlayers or {}
finishedPlayers = finishedPlayers or {} -- Sentinel: prevents duplicate finish processing during cleanup delay
groupMenusAdded = groupMenusAdded or {} -- Tracks which groups already have the per-group reset menu

-- Zone cache
local startZone = nil
local endZone = nil
local gateZones = {}
local zonesValidated = false

-- ============================================================================
-- ZONE VALIDATION
-- ============================================================================

local function validateZones()
    trigger.action.outText("Validating race zones...", 5)
    local allValid = true
    local missingZones = {}

    -- Check start zone
    startZone = trigger.misc.getZone(startZoneName)
    if not startZone then
        allValid = false
        table.insert(missingZones, startZoneName)
    end

    -- Check end zone
    endZone = trigger.misc.getZone(endZoneName)
    if not endZone then
        allValid = false
        table.insert(missingZones, endZoneName)
    end

    -- Check all gate zones
    for i, zoneName in ipairs(zonesToTime) do
        local zone = trigger.misc.getZone(zoneName)
        if zone then
            gateZones[i] = zone
        else
            allValid = false
            table.insert(missingZones, zoneName)
        end
    end

    if allValid then
        trigger.action.outText("✓ All " .. (#zonesToTime + 2) .. " race zones validated successfully!", 10)
        zonesValidated = true
    else
        trigger.action.outText("✗ RACE SETUP ERROR: Missing " .. #missingZones .. " zones!", 30)
        for _, zoneName in ipairs(missingZones) do
            trigger.action.outText("  Missing: " .. zoneName, 30)
        end
    end

    return allValid
end

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Get player's altitude AGL
local function getPlayerAltitudes(player)
    local playerPosition = player:getPoint()
    local terrainHeight = land.getHeight({x = playerPosition.x, z = playerPosition.z})
    local playerAGL = playerPosition.y - terrainHeight
    return playerAGL
end

-- Check if a player is in a zone within the altitude limit AGL
local function isPlayerInZone(player, zone)
    if not zone then return false end

    local playerPosition = player:getPoint()
    local zoneCenter = zone.point
    local radius = zone.radius
    local distance = math.sqrt((playerPosition.x - zoneCenter.x)^2 + (playerPosition.z - zoneCenter.z)^2)
    local playerAGL = getPlayerAltitudes(player)

    return distance <= radius and playerAGL <= altitudeLimit
end

-- Get aircraft type name
local function getAircraftType(player)
    local unit = player
    if unit and unit:isExist() then
        return unit:getTypeName()
    end
    return "Unknown"
end

-- ============================================================================
-- PLAYER STATE MANAGEMENT
-- ============================================================================
-- NOTE: cleanupPlayerRace and resetPlayerRace are defined before initializePlayerRace
-- so that initializePlayerRace's radio menu closure can reference them safely.

-- Clean up player race data
local function cleanupPlayerRace(playerId, playerName)
    timing[playerId] = nil
    missedZones[playerId] = nil
    reportedZones[playerId] = nil
    gateSequence[playerId] = nil
    aircraftTypes[playerId] = nil
    lastSeenPlayers[playerId] = nil
    finishedPlayers[playerId] = nil

    trigger.action.outText("Race data cleaned up for " .. (playerName or "player"), 5)
end

-- Reset player race (for restart)
local function resetPlayerRace(playerId, player)
    if timing[playerId] then
        local playerName = player:getPlayerName()
        trigger.action.outTextForGroup(player:getGroup():getID(),
            playerName .. " - Race reset! Cross the starting line to begin again.", 10)
        cleanupPlayerRace(playerId, playerName)
    end
end

-- Initialize player race data
local function initializePlayerRace(playerId, player)
    local stopwatch = Stopwatch:New()
    stopwatch:Start()
    timing[playerId] = stopwatch
    missedZones[playerId] = {}
    reportedZones[playerId] = {}
    gateSequence[playerId] = 0 -- Start at gate 0
    aircraftTypes[playerId] = getAircraftType(player)
    lastSeenPlayers[playerId] = timer.getTime()

    for _, zoneName in ipairs(zonesToTime) do
        missedZones[playerId][zoneName] = true
    end

    -- Add per-group reset menu the first time any pilot in this group starts a race.
    -- This scopes the reset to only affect pilots in the same group as the one who clicked it,
    -- preventing a single player from wiping everyone else's active run.
    local groupId = player:getGroup():getID()
    if not groupMenusAdded[groupId] then
        missionCommands.addCommandForGroup(groupId, "Reset My Race", nil, function()
            local allPlayers = mist.DBs.humansByName
            for playerName, _ in pairs(allPlayers) do
                local p = Unit.getByName(playerName)
                if p and p:isExist() and p:getGroup():getID() == groupId then
                    resetPlayerRace(p:getID(), p)
                end
            end
        end)
        groupMenusAdded[groupId] = true
    end
end

-- ============================================================================
-- DISCONNECT DETECTION
-- ============================================================================

local function checkDisconnectedPlayers()
    local currentTime = timer.getTime()
    local disconnectTimeout = 30 -- seconds

    for playerId, lastSeen in pairs(lastSeenPlayers) do
        if currentTime - lastSeen > disconnectTimeout then
            if timing[playerId] then
                -- Player had an active race — full cleanup
                trigger.action.outText("Cleaning up disconnected player race data (ID: " .. playerId .. ")", 5)
                cleanupPlayerRace(playerId, nil)
            else
                -- Player was tracked but never started a race — remove stale entry
                lastSeenPlayers[playerId] = nil
            end
        end
    end
end

-- ============================================================================
-- TIMING AND FEEDBACK
-- ============================================================================

-- Function to report time with enhanced feedback
local function reportTime(player, message, elapsedTime, gatesCompleted, totalGates)
    local stopwatch = timing[player:getID()]
    local formattedTime = stopwatch:FormatTime(elapsedTime)
    local playerNickname = player:getPlayerName()
    local progress = ""

    if gatesCompleted and totalGates then
        progress = " [" .. gatesCompleted .. "/" .. totalGates .. " gates]"
    end

    trigger.action.outTextForGroup(player:getGroup():getID(),
        playerNickname .. " " .. message .. " at " .. formattedTime .. "s" .. progress, 10)
end

-- Function to log player times to a file
local function logTime(player, elapsedTime)
    local playerId = player:getID()
    local stopwatch = timing[playerId]
    local formattedTime = stopwatch:FormatTime(elapsedTime)
    local playerNickname = player:getPlayerName()
    local aircraftType = aircraftTypes[playerId] or "Unknown"

    local missedList = {}
    for _, zoneName in ipairs(zonesToTime) do
        if missedZones[playerId][zoneName] then
            table.insert(missedList, zoneName)
        end
    end
    local missedStr = #missedList > 0 and table.concat(missedList, ", ") or "None"

    local success, err = pcall(function()
        local file = io.open(logFileName, "a")
        if not file then error("Cannot open log file: " .. logFileName) end
        file:write("Nickname: " .. playerNickname ..
                   " | Aircraft: " .. aircraftType ..
                   " | Time: " .. formattedTime .. "s" ..
                   " | Missed Gates: " .. missedStr .. "\n")
        file:close()
    end)

    if success then
        trigger.action.outText("Logged time for " .. playerNickname .. ": " .. formattedTime .. "s", 10)
    else
        trigger.action.outText("Failed to log time for " .. playerNickname .. ": " .. tostring(err), 10)
    end
end

-- ============================================================================
-- RACE LOGIC
-- ============================================================================

-- Function to start timing when a player enters the Start Zone
local function checkStartZone()
    if not zonesValidated then return end

    local allPlayers = mist.DBs.humansByName
    for playerName, playerData in pairs(allPlayers) do
        local player = Unit.getByName(playerName)
        if player and player:isExist() then
            local playerId = player:getID()
            lastSeenPlayers[playerId] = timer.getTime()

            if isPlayerInZone(player, startZone) then
                if not timing[playerId] then
                    initializePlayerRace(playerId, player)
                    trigger.action.outTextForGroup(player:getGroup():getID(),
                        player:getPlayerName() .. " - Race started! Aircraft: " .. aircraftTypes[playerId], 10)
                end
            end
        end
    end
end

-- Function to record time spent in timed zones with sequence validation
local function checkTimedZones()
    if not zonesValidated then return end

    local allPlayers = mist.DBs.humansByName
    for playerName, playerData in pairs(allPlayers) do
        local player = Unit.getByName(playerName)
        if player and player:isExist() then
            local playerId = player:getID()

            if timing[playerId] then
                lastSeenPlayers[playerId] = timer.getTime()
                local currentGateIndex = gateSequence[playerId]

                -- Check the next expected gate
                local nextGateIndex = currentGateIndex + 1
                if nextGateIndex <= #zonesToTime then
                    local nextZoneName = zonesToTime[nextGateIndex]
                    local nextZone = gateZones[nextGateIndex]

                    if isPlayerInZone(player, nextZone) and not reportedZones[playerId][nextZoneName] then
                        -- Player hit the correct next gate
                        local stopwatch = timing[playerId]
                        local elapsedTime = stopwatch:GetElapsedTime()
                        reportTime(player, "passed " .. nextZoneName, elapsedTime, nextGateIndex, #zonesToTime)
                        missedZones[playerId][nextZoneName] = false
                        reportedZones[playerId][nextZoneName] = true
                        gateSequence[playerId] = nextGateIndex
                    else
                        -- Check if player skipped ahead (missed gates)
                        for checkIndex = nextGateIndex + 1, #zonesToTime do
                            local checkZoneName = zonesToTime[checkIndex]
                            local checkZone = gateZones[checkIndex]

                            if isPlayerInZone(player, checkZone) and not reportedZones[playerId][checkZoneName] then
                                -- Identify newly missed gates (they stay true in missedZones)
                                local newlyMissed = {}
                                for skipIndex = nextGateIndex, checkIndex - 1 do
                                    table.insert(newlyMissed, zonesToTime[skipIndex])
                                end

                                trigger.action.outTextForGroup(player:getGroup():getID(),
                                    "⚠ MISSED: " .. table.concat(newlyMissed, ", ") .. "! +" .. (#newlyMissed * penaltyTime) .. "s penalty", 10)

                                -- Record current gate as passed
                                missedZones[playerId][checkZoneName] = false
                                reportedZones[playerId][checkZoneName] = true
                                gateSequence[playerId] = checkIndex

                                local stopwatch = timing[playerId]
                                local elapsedTime = stopwatch:GetElapsedTime()
                                reportTime(player, "passed " .. checkZoneName, elapsedTime, checkIndex, #zonesToTime)

                                -- Count total missed gates so far
                                local totalMissed = 0
                                local allMissedNames = {}
                                for i = 1, checkIndex do
                                    if missedZones[playerId][zonesToTime[i]] then
                                        totalMissed = totalMissed + 1
                                        table.insert(allMissedNames, zonesToTime[i])
                                    end
                                end

                                if totalMissed >= 2 then
                                    trigger.action.outTextForGroup(player:getGroup():getID(),
                                        "✗ Race NULLIFIED — missed " .. totalMissed .. " gates (" .. table.concat(allMissedNames, ", ") .. "). Cross the Starting Line to begin again.", 15)
                                    cleanupPlayerRace(playerId, player:getPlayerName())
                                end

                                break
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Function to stop timing when a player enters the End Zone and report total time
local function checkEndZone()
    if not zonesValidated then return end

    local allPlayers = mist.DBs.humansByName
    for playerName, playerData in pairs(allPlayers) do
        local player = Unit.getByName(playerName)
        if player and player:isExist() and isPlayerInZone(player, endZone) then
            local playerId = player:getID()
            if timing[playerId] and not finishedPlayers[playerId] then
                finishedPlayers[playerId] = true -- Sentinel: block re-entry while cleanup delay is pending

                local stopwatch = timing[playerId]
                stopwatch:Stop()
                local elapsedTime = stopwatch:GetElapsedTime()

                -- Identify all missed gates
                local missedCount = 0
                local missedNames = {}
                for _, zoneName in ipairs(zonesToTime) do
                    if missedZones[playerId][zoneName] then
                        missedCount = missedCount + 1
                        table.insert(missedNames, zoneName)
                    end
                end

                -- 2+ missed gates = race nullified
                if missedCount >= 2 then
                    trigger.action.outTextForGroup(player:getGroup():getID(),
                        player:getPlayerName() .. " - ✗ Race NULLIFIED — missed " .. missedCount .. " gates (" .. table.concat(missedNames, ", ") .. "). Cross the Starting Line to begin again.", 15)
                    cleanupPlayerRace(playerId, player:getPlayerName())
                else
                    local penalty = missedCount * penaltyTime
                    local totalElapsedTime = elapsedTime + penalty

                    local penaltyMsg = ""
                    if missedCount > 0 then
                        penaltyMsg = " (+" .. penalty .. "s penalty: missed " .. missedNames[1] .. ")"
                    end

                    reportTime(player, "finished the race" .. penaltyMsg, totalElapsedTime, #zonesToTime, #zonesToTime)
                    logTime(player, totalElapsedTime)

                    -- Clean up after 5 seconds to allow the finish message to display
                    local capturedPlayerId = playerId
                    local capturedPlayerName = player:getPlayerName()
                    timer.scheduleFunction(function()
                        cleanupPlayerRace(capturedPlayerId, capturedPlayerName)
                    end, nil, timer.getTime() + 5)
                end
            end
        end
    end
end

-- ============================================================================
-- CRASH / DEATH EVENT HANDLER
-- ============================================================================

-- Listens for S_EVENT_CRASH, S_EVENT_DEAD, and S_EVENT_PILOT_DEAD.
-- If the unit that crashed/died has an active race, it is immediately nullified.
-- The player will need to cross the Starting Line again to begin a fresh run.
-- No time is ever logged for an incomplete run.
local RaceCrashHandler = {}
RaceCrashHandler.__index = RaceCrashHandler

function RaceCrashHandler:onEvent(event)
    if event.id ~= world.event.S_EVENT_CRASH
    and event.id ~= world.event.S_EVENT_DEAD
    and event.id ~= world.event.S_EVENT_PILOT_DEAD then
        return
    end

    local unit = event.initiator
    if not unit then return end

    -- Only care about aircraft/helicopter categories
    local cat = unit:getDesc().category
    if cat ~= Unit.Category.AIRPLANE and cat ~= Unit.Category.HELICOPTER then return end

    local playerId = unit:getID()

    if timing[playerId] and not finishedPlayers[playerId] then
        -- Grab name before cleanup wipes the state
        local playerName = "Unknown"
        local ok, name = pcall(function() return unit:getPlayerName() end)
        if ok and name then playerName = name end

        -- Attempt to notify the group — unit may already be invalid, so guard it
        local groupOk, grp = pcall(function() return unit:getGroup() end)
        if groupOk and grp then
            trigger.action.outTextForGroup(grp:getID(),
                playerName .. " - Race NULLIFIED due to crash. Cross the Starting Line to begin again.", 15)
        end

        cleanupPlayerRace(playerId, playerName)
    end
end

world.addEventHandler(RaceCrashHandler)

-- ============================================================================
-- CORPSE CLEANUP
-- ============================================================================

-- Scans all coalitions for aircraft/helicopter units that are dead (destroyed or
-- crashed) and destroys their wreck objects so they don't clutter the race course.
-- Runs every 45 minutes.
local function cleanupCorpses()
    local cleaned = 0
    -- Category 1 = Airplane, Category 2 = Helicopter
    local aircraftCategories = { Unit.Category.AIRPLANE, Unit.Category.HELICOPTER }
    local coalitions = { coalition.side.BLUE, coalition.side.RED, coalition.side.NEUTRAL }

    for _, coa in ipairs(coalitions) do
        for _, cat in ipairs(aircraftCategories) do
            local groups = coalition.getGroups(coa, cat)
            if groups then
                for _, grp in ipairs(groups) do
                    local units = grp:getUnits()
                    if units then
                        for _, unit in ipairs(units) do
                            -- isExist() returns true for wrecks; getLife() <= 0 means destroyed
                            if unit:isExist() and unit:getLife() <= 0 then
                                unit:destroy()
                                cleaned = cleaned + 1
                            end
                        end
                    end
                end
            end
        end
    end

    if cleaned > 0 then
        trigger.action.outText("[Race] Corpse cleanup: removed " .. cleaned .. " destroyed aircraft wreck(s).", 10)
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

-- Validate zones at startup
local validationSuccess = validateZones()

if validationSuccess then
    -- Schedule the functions to run continuously
    mist.scheduleFunction(checkStartZone, {}, timer.getTime() + 1, 0.1)
    mist.scheduleFunction(checkTimedZones, {}, timer.getTime() + 1, 0.1)
    mist.scheduleFunction(checkEndZone, {}, timer.getTime() + 1, 0.1)
    mist.scheduleFunction(checkDisconnectedPlayers, {}, timer.getTime() + 30, 30) -- Check every 30 seconds
    mist.scheduleFunction(cleanupCorpses, {}, timer.getTime() + 2700, 2700) -- Check every 45 minutes

    trigger.action.outText("✓ Race Script V4.0 Active - All systems ready!", 10)
else
    trigger.action.outText("✗ Race Script V4.0 Failed - Check zone configuration!", 30)
end
