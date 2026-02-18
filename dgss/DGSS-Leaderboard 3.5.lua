----------------------------------------------------------------
-- LEADERBOARD SYSTEM v3.5
-- Tracks player kills, CSAR rescues, and logistics (slingload + warehouse)
-- Displays comprehensive leaderboard via radio menu
----------------------------------------------------------------

DGSS_LEADERBOARD = {}

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------

DGSS_LEADERBOARD.COALITION = coalition.side.BLUE
DGSS_LEADERBOARD.COUNTRY   = country.id.USA

-- Supply base zones
DGSS_LEADERBOARD.SUPPLY_BASE = "KANDAHAR"
DGSS_LEADERBOARD.SUPPLY_HELIPORT = {"KANDAHAR", "FOB_URGOON"}   --"Urgoon Heliport" if "FOB_URGOON" doesn't work

-- Distribution bases (where logistics count)
DGSS_LEADERBOARD.DISTRIBUTION_BASES = {
    "KABUL",
    "BAGRAM",
    "JALALABAD",
    "FOB_LONDON",
    "FOB_DALLAS",
    "FOB_PARIS",
    "FOB_WARSAW",
    "FOB_SALERNO",
    "FOB_URGOON",
    "TARINKOT",
}

-- Crate/Container type names to track (all DCS cargo types)
DGSS_LEADERBOARD.SUPPLY_UNIT_TYPES = {
    -- Generic cargo types
    ["Container"] = true,
    ["Crate"] = true,
    ["cargo"] = true,
    ["Cargo"] = true,
    
    -- Specific DCS cargo unit types
    ["ammo_cargo"] = true,
    ["Ammo"] = true,
    ["Ammo_cargo"] = true,
    ["uh1h_cargo"] = true,
    ["iso_container"] = true,
    ["iso_container_small"] = true,
    ["iso20"] = true,
    ["ISO_Container"] = true,
    ["Container_20ft"] = true,
    ["Container_40ft"] = true,
    
    -- Barrel types
    ["barrels_cargo"] = true,
    ["Barrels"] = true,
    ["fueltank_cargo"] = true,
    ["oiltank_cargo"] = true,
    
    -- Military cargo
    ["m117_cargo"] = true,
    ["uh60_cargo"] = true,
    ["tetrapod_cargo"] = true,
    ["f_bar_cargo"] = true,
    ["concertina_cargo"] = true,
    ["trunks_cargo"] = true,
    ["bw_container_cargo"] = true,
    
    -- Generic slingloadable cargo
    ["slingload"] = true,
    ["Slingload"] = true,
    
    -- Pattern matching for any cargo-related names
    -- (will be checked via string.find in isSupplyUnit function)
}

-- Stats storage: playerName -> { kills, csarRescues, cratesDelivered, aircraftResupplied, deaths, lastUpdate }
DGSS_LEADERBOARD.PLAYER_STATS = {}

-- Track unit movements: unitName -> { lastZone, player, inventory% }
DGSS_LEADERBOARD.UNIT_TRACKING = {}

-- Track aircraft resupply: unitName -> { lastFuel, lastResupplyZone, lastResupplyPlayer }
DGSS_LEADERBOARD.AIRCRAFT_TRACKING = {}

-- Track warehouse inventories: zoneName -> { lastLiquid, lastWeapons, lastFuel, lastAircraft }
DGSS_LEADERBOARD.WAREHOUSE_TRACKING = {}

-- Track recent landings: zoneName -> { playerName, landingTime, unitType }
DGSS_LEADERBOARD.RECENT_LANDINGS = {}

-- Anti-duplicate tracking
DGSS_LEADERBOARD.LAST_DELIVERY_TIME = {}
DGSS_LEADERBOARD.LAST_RESUPPLY_TIME = {}
DGSS_LEADERBOARD.LAST_DEATH_TIME = {}
DGSS_LEADERBOARD.LAST_WAREHOUSE_DELIVERY = {}

-- Scoring configuration
DGSS_LEADERBOARD.SCORING = {
    killPoints            = 10,
    deathPoints           = -15,
    rescuePoints          = 35,
    convoyRescuePoints    = 10,
    logisticsPoints       = 35,
    convoySuccessPoints   = 100,  -- Full convoy arrives intact
    convoyPartialPoints   = 50,   -- Convoy arrives with damage
}

-- File persistence
DGSS_LEADERBOARD.SAVE_PATH = lfs.writedir() .. 'Mission Saves\\'
DGSS_LEADERBOARD.SAVE_FILE = 'leaderboard_stats.lua'


----------------------------------------------------------------
-- UTILITY FUNCTIONS
----------------------------------------------------------------

local function now()
    return timer.getTime()
end

local function initPlayerStats(playerName)
    if not DGSS_LEADERBOARD.PLAYER_STATS[playerName] then
        DGSS_LEADERBOARD.PLAYER_STATS[playerName] = {
            kills              = 0,
            csarRescues        = 0,
            convoyRescues      = 0,
            cratesDelivered    = 0,
            aircraftResupplied = 0,
            deaths             = 0,
            convoysSuccessful  = 0,
            convoysPartial     = 0,
            convoysFailed      = 0,
            score              = 0,
            lastUpdate         = now(),
        }
    end
    return DGSS_LEADERBOARD.PLAYER_STATS[playerName]
end

local function calculatePlayerScore(stats)
    local score = 0
    score = score + (stats.kills or 0) * DGSS_LEADERBOARD.SCORING.killPoints
    score = score + (stats.deaths or 0) * DGSS_LEADERBOARD.SCORING.deathPoints
    score = score + (stats.csarRescues or 0) * DGSS_LEADERBOARD.SCORING.rescuePoints
    score = score + (stats.convoyRescues or 0) * DGSS_LEADERBOARD.SCORING.convoyRescuePoints
    score = score + (stats.cratesDelivered or 0) * DGSS_LEADERBOARD.SCORING.logisticsPoints
    score = score + (stats.convoysSuccessful or 0) * DGSS_LEADERBOARD.SCORING.convoySuccessPoints
    score = score + (stats.convoysPartial or 0) * DGSS_LEADERBOARD.SCORING.convoyPartialPoints
    return math.max(0, score)
end

local function updatePlayerScore(playerName)
    local stats = DGSS_LEADERBOARD.PLAYER_STATS[playerName]
    if stats then
        stats.score = calculatePlayerScore(stats)
    end
end

function DGSS_LEADERBOARD.addKill(playerName)
    if not playerName then return end
    
    local stats = initPlayerStats(playerName)
    stats.kills = stats.kills + 1
    stats.lastUpdate = now()
    updatePlayerScore(playerName)
    
    env.info(string.format("[Leaderboard] Kill recorded for '%s' (Total: %d, Score: %d)", playerName, stats.kills, stats.score))
end

function DGSS_LEADERBOARD.addCSARRescue(playerName)
    if not playerName then return end
    
    local stats = initPlayerStats(playerName)
    stats.csarRescues = stats.csarRescues + 1
    stats.lastUpdate = now()
    updatePlayerScore(playerName)
    
    env.info(string.format("[Leaderboard] CSAR Rescue recorded for '%s' (Total: %d, Score: %d)", playerName, stats.csarRescues, stats.score))
end

function DGSS_LEADERBOARD.addConvoyRescue(playerName)
    if not playerName then return end
    
    local stats = initPlayerStats(playerName)
    stats.convoyRescues = stats.convoyRescues + 1
    stats.lastUpdate = now()
    updatePlayerScore(playerName)
    
    env.info(string.format("[Leaderboard] Convoy Rescue recorded for '%s' (Total: %d, Score: %d)", playerName, stats.convoyRescues, stats.score))
end

function DGSS_LEADERBOARD.addConvoyCompletion(playerName, successState)
    if not playerName then return end
    
    local stats = initPlayerStats(playerName)
    
    -- successState: "full" = 100 pts, "partial" = 50 pts, "failed" = 0 pts
    if successState == "full" then
        stats.convoysSuccessful = (stats.convoysSuccessful or 0) + 1
    elseif successState == "partial" then
        stats.convoysPartial = (stats.convoysPartial or 0) + 1
    else
        stats.convoysFailed = (stats.convoysFailed or 0) + 1
    end
    
    stats.lastUpdate = now()
    updatePlayerScore(playerName)
    
    local points = 0
    if successState == "full" then points = DGSS_LEADERBOARD.SCORING.convoySuccessPoints
    elseif successState == "partial" then points = DGSS_LEADERBOARD.SCORING.convoyPartialPoints
    end
    
    env.info(string.format("[Leaderboard] Convoy %s recorded for '%s' (+%d pts, Score: %d)", 
        successState, playerName, points, stats.score))
end

function DGSS_LEADERBOARD.addCrateDelivered(playerName)
    if not playerName then return end
    
    local stats = initPlayerStats(playerName)
    stats.cratesDelivered = stats.cratesDelivered + 1
    stats.lastUpdate = now()
    updatePlayerScore(playerName)
    
    env.info(string.format("[Leaderboard] Crate delivered for '%s' (Total: %d, Score: %d)", playerName, stats.cratesDelivered, stats.score))
end

function DGSS_LEADERBOARD.addAircraftResupplied(playerName)
    if not playerName then return end
    
    local stats = initPlayerStats(playerName)
    stats.aircraftResupplied = stats.aircraftResupplied + 1
    stats.lastUpdate = now()
    updatePlayerScore(playerName)
    
    env.info(string.format("[Leaderboard] Aircraft resupplied for '%s' (Total: %d, Score: %d)", playerName, stats.aircraftResupplied, stats.score))
end

function DGSS_LEADERBOARD.addPlayerDeath(playerName)
    if not playerName then return end
    
    local stats = initPlayerStats(playerName)
    stats.deaths = stats.deaths + 1
    stats.lastUpdate = now()
    updatePlayerScore(playerName)
    
    env.info(string.format("[Leaderboard] Death recorded for '%s' (Total: %d, Score: %d)", playerName, stats.deaths, stats.score))
end

function DGSS_LEADERBOARD.getPlayerStats(playerName)
    return initPlayerStats(playerName)
end

function DGSS_LEADERBOARD.getAllPlayerStats()
    return DGSS_LEADERBOARD.PLAYER_STATS
end

----------------------------------------------------------------
-- ZONE UTILITY FUNCTIONS
----------------------------------------------------------------

local function getZone(zoneName)
    local zone = trigger.misc.getZone(zoneName)
    return zone
end

local function _2dDist(p1, p2)
    if not p1 or not p2 or not p1.x or not p2.x or not p1.z or not p2.z then
        return nil
    end
    local dx = p1.x - p2.x
    local dz = p1.z - p2.z
    return math.sqrt(dx*dx + dz*dz)
end

local function isUnitInZone(unit, zoneName)
    if not unit or not unit:isExist() then return false end
    
    local zone = getZone(zoneName)
    if not zone or not zone.x or not zone.z or not zone.radius then return false end
    
    local success, pos = pcall(function() return unit:getPoint() end)
    if not success or not pos or not pos.x or not pos.z then return false end
    
    local dist = _2dDist(pos, { x = zone.x, z = zone.z })
    if not dist then return false end
    
    return dist <= zone.radius
end

local function isUnitInAnyZone(unit, zoneNames)
    if not unit or not unit:isExist() then return nil end
    
    for _, zoneName in ipairs(zoneNames) do
        if isUnitInZone(unit, zoneName) then
            return zoneName
        end
    end
    
    return nil
end

local function isSupplyUnit(unit)
    if not unit or not unit:isExist() then return false end
    
    local success, typeName = pcall(function() return unit:getTypeName() end)
    if not success or not typeName then return false end
    
    -- Check exact matches first (case-sensitive)
    for supplyType, _ in pairs(DGSS_LEADERBOARD.SUPPLY_UNIT_TYPES) do
        if string.find(typeName, supplyType) then
            return true
        end
    end
    
    -- Check case-insensitive patterns for common cargo keywords
    local lowerTypeName = typeName:lower()
    local cargoKeywords = {
        "cargo", "crate", "container", "ammo", "barrel", 
        "sling", "fuel", "iso", "supply"
    }
    
    for _, keyword in ipairs(cargoKeywords) do
        if string.find(lowerTypeName, keyword) then
            return true
        end
    end
    
    return false
end

local function getUnitInventoryPercent(unit)
    if not unit or not unit:isExist() then return 0 end
    
    -- Try to get cargo from DCS API
    local success, result = pcall(function()
        local cargo = unit:getCargo()
        if cargo and cargo.maxMass and cargo.maxMass > 0 then
            return cargo.totalMass / cargo.maxMass
        end
        return 0
    end)
    
    if success and result then
        return result
    end
    
    return 0
end

----------------------------------------------------------------
-- LEADERBOARD FORMATTING & DISPLAY
----------------------------------------------------------------

function DGSS_LEADERBOARD.getSortedByKills()
    local sorted = {}
    for playerName, stats in pairs(DGSS_LEADERBOARD.PLAYER_STATS) do
        table.insert(sorted, { name = playerName, stats = stats })
    end
    table.sort(sorted, function(a, b)
        return a.stats.kills > b.stats.kills
    end)
    return sorted
end

function DGSS_LEADERBOARD.getSortedByCSAR()
    local sorted = {}
    for playerName, stats in pairs(DGSS_LEADERBOARD.PLAYER_STATS) do
        table.insert(sorted, { name = playerName, stats = stats })
    end
    table.sort(sorted, function(a, b)
        return a.stats.csarRescues > b.stats.csarRescues
    end)
    return sorted
end

function DGSS_LEADERBOARD.getSortedByCrates()
    local sorted = {}
    for playerName, stats in pairs(DGSS_LEADERBOARD.PLAYER_STATS) do
        table.insert(sorted, { name = playerName, stats = stats })
    end
    table.sort(sorted, function(a, b)
        return a.stats.cratesDelivered > b.stats.cratesDelivered
    end)
    return sorted
end

function DGSS_LEADERBOARD.getSortedByResupply()
    local sorted = {}
    for playerName, stats in pairs(DGSS_LEADERBOARD.PLAYER_STATS) do
        table.insert(sorted, { name = playerName, stats = stats })
    end
    table.sort(sorted, function(a, b)
        return a.stats.aircraftResupplied > b.stats.aircraftResupplied
    end)
    return sorted
end

function DGSS_LEADERBOARD.getSortedByDeaths()
    local sorted = {}
    for playerName, stats in pairs(DGSS_LEADERBOARD.PLAYER_STATS) do
        table.insert(sorted, { name = playerName, stats = stats })
    end
    table.sort(sorted, function(a, b)
        return a.stats.deaths > b.stats.deaths
    end)
    return sorted
end

function DGSS_LEADERBOARD.getSortedByScore()
    local sorted = {}
    for playerName, stats in pairs(DGSS_LEADERBOARD.PLAYER_STATS) do
        table.insert(sorted, { name = playerName, stats = stats })
    end
    table.sort(sorted, function(a, b)
        return a.stats.score > b.stats.score
    end)
    return sorted
end

function DGSS_LEADERBOARD.formatLeaderboardText(sortedList, title, statField)
    local text = "\n" .. title .. "\n"
    text = text .. "========================================\n"
    
    if #sortedList == 0 then
        text = text .. "No data recorded yet.\n"
    else
        for rank, entry in ipairs(sortedList) do
            if rank <= 10 then  -- Top 10
                local value = entry.stats[statField] or 0
                text = text .. string.format("%2d. %-18s %d\n", rank, entry.name, value)
            end
        end
    end
    
    return text
end

function DGSS_LEADERBOARD.getFullLeaderboard()
    local text = "\n========================================\n"
    text = text .. "         OPERATIONS LEADERBOARD\n"
    text = text .. "========================================\n\n"
    
    -- Top Score
    local scoreSorted = DGSS_LEADERBOARD.getSortedByScore()
    text = text .. "TOP SCORE\n"
    if #scoreSorted == 0 then
        text = text .. "  No scores yet\n"
    else
        for rank, entry in ipairs(scoreSorted) do
            if rank <= 5 then
                text = text .. string.format("  %d. %-18s %d pts\n", rank, entry.name, entry.stats.score)
            end
        end
    end
    text = text .. "\n"
    
    -- Top Killers
    local killsSorted = DGSS_LEADERBOARD.getSortedByKills()
    text = text .. "TOP KILLERS\n"
    if #killsSorted == 0 then
        text = text .. "  No kills yet\n"
    else
        for rank, entry in ipairs(killsSorted) do
            if rank <= 5 then
                text = text .. string.format("  %d. %-18s %d\n", rank, entry.name, entry.stats.kills)
            end
        end
    end
    text = text .. "\n"
    
    -- Top CSAR
    local csarSorted = DGSS_LEADERBOARD.getSortedByCSAR()
    text = text .. "TOP RESCUERS\n"
    if #csarSorted == 0 then
        text = text .. "  No rescues yet\n"
    else
        for rank, entry in ipairs(csarSorted) do
            if rank <= 5 then
                text = text .. string.format("  %d. %-18s %d\n", rank, entry.name, entry.stats.csarRescues)
            end
        end
    end
    text = text .. "\n"
    
    -- Top Logistics
    local cratesSorted = DGSS_LEADERBOARD.getSortedByCrates()
    text = text .. "TOP LOGISTICS\n"
    if #cratesSorted == 0 then
        text = text .. "  No deliveries yet\n"
    else
        for rank, entry in ipairs(cratesSorted) do
            if rank <= 5 then
                text = text .. string.format("  %d. %-18s %d\n", rank, entry.name, entry.stats.cratesDelivered)
            end
        end
    end
    
    return text
end

function DGSS_LEADERBOARD.getPersonalStats(playerName)
    if not playerName then return "Player not found." end
    
    local stats = DGSS_LEADERBOARD.getPlayerStats(playerName)
    
    local text = "\n========================================\n"
    text = text .. "           YOUR STATISTICS\n"
    text = text .. "========================================\n\n"
    text = text .. "Pilot: " .. playerName .. "\n\n"
    text = text .. string.format("Total Score:         %d pts\n\n", stats.score)
    text = text .. "COMBAT\n"
    text = text .. string.format("  Kills:             %d\n", stats.kills)
    text = text .. string.format("  Deaths:            %d\n\n", stats.deaths)
    text = text .. "SUPPORT\n"
    text = text .. string.format("  Pilots Rescued:    %d\n", stats.csarRescues)
    text = text .. string.format("  Convoy Rescued:    %d\n", stats.convoyRescues or 0)
    text = text .. string.format("  Crates Delivered:  %d\n", stats.cratesDelivered)
    text = text .. string.format("  Aircraft Fueled:   %d\n\n", stats.aircraftResupplied)
    text = text .. "CONVOY OPERATIONS\n"
    text = text .. string.format("  Successful:        %d (+%d pts ea)\n", stats.convoysSuccessful or 0, DGSS_LEADERBOARD.SCORING.convoySuccessPoints)
    text = text .. string.format("  Partial Success:   %d (+%d pts ea)\n", stats.convoysPartial or 0, DGSS_LEADERBOARD.SCORING.convoyPartialPoints)
    text = text .. string.format("  Failed:            %d\n", stats.convoysFailed or 0)
    
    return text
end

----------------------------------------------------------------
-- KILL EVENT HANDLER
----------------------------------------------------------------

local KILL_EVENT_HANDLER = {}

function KILL_EVENT_HANDLER:onEvent(event)
    if not event or not event.id then return end
    
    -- Handle landing events for warehouse logistics tracking
    if event.id == world.event.S_EVENT_LAND then
        local unit = event.initiator
        if unit and unit:isExist() and unit.getPlayerName then
            local playerName = unit:getPlayerName()
            if playerName then
                local typeName = unit:getTypeName()
                
                -- Check if landed in a distribution base
                local landingZone = isUnitInAnyZone(unit, DGSS_LEADERBOARD.DISTRIBUTION_BASES)
                if landingZone then
                    DGSS_LEADERBOARD.RECENT_LANDINGS[landingZone] = {
                        playerName = playerName,
                        landingTime = now(),
                        unitType = typeName,
                    }
                    env.info(string.format("[Leaderboard] %s landed at %s in %s", playerName, landingZone, typeName))
                end
            end
        end
        return
    end
    
    if event.id == world.event.S_EVENT_KILL then
        local initiator = event.initiator
        if not initiator or not initiator.getPlayerName then return end
        
        local playerName = initiator:getPlayerName()
        if playerName then
            DGSS_LEADERBOARD.addKill(playerName)
        end
    end
    
    -- Track player deaths
    if event.id == world.event.S_EVENT_PILOT_DEAD or event.id == world.event.S_EVENT_DEAD then
        local unit = event.initiator
        if not unit then return end
        
        local playerName = nil
        if unit.getPlayerName then
            playerName = unit:getPlayerName()
        end
        if playerName then
            -- Anti-duplicate: ignore if last event < 1 second ago
            local lastDeath = DGSS_LEADERBOARD.LAST_DEATH_TIME[playerName]
            if lastDeath and (now() - lastDeath) < 1 then
                return
            end
            DGSS_LEADERBOARD.LAST_DEATH_TIME[playerName] = now()
            
            DGSS_LEADERBOARD.addPlayerDeath(playerName)
        end
    end
end

world.addEventHandler(KILL_EVENT_HANDLER)

----------------------------------------------------------------
-- LOGISTICS TRACKING - CRATE/CONTAINER MOVEMENT
----------------------------------------------------------------

local function trackSupplyMovement()
    local bluePlanes = coalition.getGroups(DGSS_LEADERBOARD.COALITION, Group.Category.GROUND) or {}
    
    for _, group in ipairs(bluePlanes) do
        if group and group:isExist() then
            for _, unit in ipairs(group:getUnits()) do
                if unit and unit:isExist() and isSupplyUnit(unit) then
                    local unitName = unit:getName()
                    
                    -- Get current zone
                    local currentZone = isUnitInAnyZone(unit, DGSS_LEADERBOARD.DISTRIBUTION_BASES)
                    local isInSupplyBase = isUnitInZone(unit, DGSS_LEADERBOARD.SUPPLY_BASE) or 
                                          isUnitInZone(unit, DGSS_LEADERBOARD.SUPPLY_HELIPORT)
                    
                    -- Initialize tracking
                    if not DGSS_LEADERBOARD.UNIT_TRACKING[unitName] then
                        DGSS_LEADERBOARD.UNIT_TRACKING[unitName] = {
                            lastZone = nil,
                            lastPlayer = nil,
                            delivered = false,
                        }
                    end
                    
                    local tracking = DGSS_LEADERBOARD.UNIT_TRACKING[unitName]
                    local inventory = getUnitInventoryPercent(unit)
                    
                    -- Check if moved FROM supply base TO distribution base with 70%+ cargo
                    if currentZone and inventory >= 0.7 then
                        if tracking.lastZone ~= currentZone then
                            -- Zone changed to distribution base with full cargo
                            if not tracking.delivered then
                                -- Find the unit's controlling player (if in a transport)
                                -- For now, track by nearby players
                                for _, grp in ipairs(coalition.getGroups(DGSS_LEADERBOARD.COALITION, Group.Category.HELICOPTER)) do
                                    if grp and grp:isExist() then
                                        for _, helo in ipairs(grp:getUnits()) do
                                            if helo and helo:isExist() then
                                                local posOk, pos = pcall(function() return unit:getPoint() end)
                                                local heloPosOk, heloPos = pcall(function() return helo:getPoint() end)
                                                
                                                if posOk and heloPosOk and pos and heloPos then
                                                    local dist = _2dDist(pos, heloPos)
                                                    
                                                    -- If within 200m, helo is carrying this unit
                                                    if dist < 200 and helo.getPlayerName then
                                                        local playerName = helo:getPlayerName()
                                                        if playerName then
                                                            DGSS_LEADERBOARD.addCrateDelivered(playerName)
                                                            tracking.delivered = true
                                                            env.info(string.format("[Leaderboard] Crate delivered to %s by %s", currentZone, playerName))
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                            tracking.lastZone = currentZone
                        end
                    elseif isInSupplyBase then
                        -- Reset tracking when back at supply base
                        tracking.lastZone = nil
                        tracking.delivered = false
                    end
                end
            end
        end
    end
end

----------------------------------------------------------------
-- WAREHOUSE LOGISTICS TRACKING
----------------------------------------------------------------

local function getWarehouseByZone(zoneName)
    -- Try to find warehouse associated with this zone
    local zone = trigger.misc.getZone(zoneName)
    if not zone then return nil end
    
    -- Find nearest warehouse to zone center
    local warehouses = coalition.getAirbases(DGSS_LEADERBOARD.COALITION)
    if not warehouses then return nil end
    
    local nearestWarehouse = nil
    local nearestDist = math.huge
    
    for _, airbase in ipairs(warehouses) do
        if airbase then
            local posOk, wPos = pcall(function() return airbase:getPoint() end)
            if posOk and wPos then
                local dx = wPos.x - zone.point.x
                local dz = wPos.z - zone.point.z
                local dist = math.sqrt(dx*dx + dz*dz)
                
                -- Warehouse must be within or very near the zone (5km)
                if dist < 5000 and dist < nearestDist then
                    nearestDist = dist
                    nearestWarehouse = airbase
                end
            end
        end
    end
    
    return nearestWarehouse
end

local function getWarehouseInventory(warehouse)
    if not warehouse then return nil end
    
    local ok, result = pcall(function()
        local wh = warehouse:getWarehouse()
        if not wh then return nil end
        
        return {
            liquid = wh:getItemCount(Warehouse.ItemCategory.LIQUID) or 0,
            weapons = wh:getItemCount(Warehouse.ItemCategory.WEAPON) or 0,
            fuel = wh:getItemCount(Warehouse.ItemCategory.FUEL) or 0,
            aircraft = wh:getItemCount(Warehouse.ItemCategory.AIRCRAFT) or 0,
        }
    end)
    
    if ok then return result else return nil end
end

local function trackWarehouseLogistics()
    -- Check each distribution base for inventory increases
    for _, zoneName in ipairs(DGSS_LEADERBOARD.DISTRIBUTION_BASES) do
        local warehouse = getWarehouseByZone(zoneName)
        if warehouse then
            local inventory = getWarehouseInventory(warehouse)
            
            if inventory then
                -- Initialize tracking
                if not DGSS_LEADERBOARD.WAREHOUSE_TRACKING[zoneName] then
                    DGSS_LEADERBOARD.WAREHOUSE_TRACKING[zoneName] = {
                        lastLiquid = inventory.liquid,
                        lastWeapons = inventory.weapons,
                        lastFuel = inventory.fuel,
                        lastAircraft = inventory.aircraft,
                    }
                end
                
                local tracking = DGSS_LEADERBOARD.WAREHOUSE_TRACKING[zoneName]
                
                -- Detect significant inventory increases (>100 units of any category)
                local liquidIncrease = inventory.liquid - tracking.lastLiquid
                local weaponsIncrease = inventory.weapons - tracking.lastWeapons
                local fuelIncrease = inventory.fuel - tracking.lastFuel
                local aircraftIncrease = inventory.aircraft - tracking.lastAircraft
                
                local significantIncrease = (liquidIncrease > 100 or weaponsIncrease > 100 or 
                                            fuelIncrease > 100 or aircraftIncrease > 0)
                
                if significantIncrease then
                    -- Check for recent landings at this base
                    local landing = DGSS_LEADERBOARD.RECENT_LANDINGS[zoneName]
                    if landing and (now() - landing.landingTime) < 120 then
                        -- Player landed within last 2 minutes - credit them
                        local lastDelivery = DGSS_LEADERBOARD.LAST_WAREHOUSE_DELIVERY[zoneName]
                        if not lastDelivery or (now() - lastDelivery) > 30 then
                            DGSS_LEADERBOARD.addCrateDelivered(landing.playerName)
                            DGSS_LEADERBOARD.LAST_WAREHOUSE_DELIVERY[zoneName] = now()
                            
                            env.info(string.format("[Leaderboard] Warehouse delivery at %s credited to %s (L:%d W:%d F:%d A:%d)",
                                zoneName, landing.playerName, liquidIncrease, weaponsIncrease, fuelIncrease, aircraftIncrease))
                        end
                    end
                end
                
                -- Update tracking
                tracking.lastLiquid = inventory.liquid
                tracking.lastWeapons = inventory.weapons
                tracking.lastFuel = inventory.fuel
                tracking.lastAircraft = inventory.aircraft
            end
        end
    end
end

----------------------------------------------------------------
-- AIRCRAFT RESUPPLY TRACKING
----------------------------------------------------------------

local function trackAircraftResupply()
    local bluePlanes = coalition.getGroups(DGSS_LEADERBOARD.COALITION, Group.Category.AIRPLANE) or {}
    local blueHelos = coalition.getGroups(DGSS_LEADERBOARD.COALITION, Group.Category.HELICOPTER) or {}
    
    local allGroups = {}
    for _, g in ipairs(bluePlanes) do table.insert(allGroups, g) end
    for _, g in ipairs(blueHelos) do table.insert(allGroups, g) end
    
    for _, group in ipairs(allGroups) do
        if group and group:isExist() then
            for _, unit in ipairs(group:getUnits()) do
                if unit and unit:isExist() and unit.getPlayerName and unit:getPlayerName() then
                    local unitName = unit:getName()
                    
                    -- Initialize tracking
                    if not DGSS_LEADERBOARD.AIRCRAFT_TRACKING[unitName] then
                        DGSS_LEADERBOARD.AIRCRAFT_TRACKING[unitName] = {
                            lastFuel = 100,
                            lastResupplyZone = nil,
                            lastResupplyPlayer = nil,
                        }
                    end
                    
                    local tracking = DGSS_LEADERBOARD.AIRCRAFT_TRACKING[unitName]
                    local fuel = unit:getFuel() or 0
                    local playerName = unit.getPlayerName and unit:getPlayerName() or nil
                    
                    if playerName and fuel then
                        -- Check if in a distribution base (not supply base)
                        local currentZone = isUnitInAnyZone(unit, DGSS_LEADERBOARD.DISTRIBUTION_BASES)
                        local isInSupplyBase = isUnitInZone(unit, DGSS_LEADERBOARD.SUPPLY_BASE) or 
                                              isUnitInZone(unit, DGSS_LEADERBOARD.SUPPLY_HELIPORT)
                        
                        -- Detect resupply: fuel increased while in distribution zone
                        if currentZone and fuel > tracking.lastFuel and fuel >= 0.7 then
                            if tracking.lastResupplyZone ~= currentZone then
                                -- Anti-duplicate check
                                local lastResupply = DGSS_LEADERBOARD.LAST_RESUPPLY_TIME[unitName]
                                if not lastResupply or (now() - lastResupply) > 5 then
                                    DGSS_LEADERBOARD.addAircraftResupplied(playerName)
                                    tracking.lastResupplyZone = currentZone
                                    DGSS_LEADERBOARD.LAST_RESUPPLY_TIME[unitName] = now()
                                    env.info(string.format("[Leaderboard] Aircraft resupplied at %s by %s", currentZone, playerName))
                                end
                            end
                        elseif isInSupplyBase then
                            -- Reset when back at supply base
                            tracking.lastResupplyZone = nil
                        end
                    end
                    
                    tracking.lastFuel = fuel
                end
            end
        end
    end
end

--================================================================
-- CSAR INTEGRATION
--================================================================

-- Track CSAR rescues via death event
-- (The CSAR system already handles the rescue tracking, we just count when pilot gains a life)

--================================================================
-- LOGISTICS TRACKING LOOP
--================================================================

local function logisticsTracker()
    pcall(function()
        trackSupplyMovement()
        trackWarehouseLogistics()
        trackAircraftResupply()
    end)
    
    if mist and mist.scheduleFunction then
        mist.scheduleFunction(logisticsTracker, {}, timer.getTime() + 12)
    else
        timer.scheduleFunction(logisticsTracker, {}, timer.getTime() + 12)
    end
end

if mist and mist.scheduleFunction then
    mist.scheduleFunction(logisticsTracker, {}, timer.getTime() + 12)
else
    timer.scheduleFunction(logisticsTracker, {}, timer.getTime() + 12)
end

--================================================================
-- FILE PERSISTENCE
--================================================================

function DGSS_LEADERBOARD.saveStats()
    pcall(function()
        -- Create Mission Saves folder if it doesn't exist
        local saveDir = DGSS_LEADERBOARD.SAVE_PATH
        local attr = lfs.attributes(saveDir)
        if not attr then
            local ok, err = lfs.mkdir(saveDir)
            if ok then
                env.info("[Leaderboard] Created save directory: " .. saveDir)
            else
                env.warning("[Leaderboard] Failed to create directory: " .. tostring(err))
                return
            end
        end
        
        local filePath = saveDir .. DGSS_LEADERBOARD.SAVE_FILE
        local file = io.open(filePath, 'w')
        
        if not file then
            env.warning("[Leaderboard] Failed to open file for writing: " .. filePath)
            return
        end
        
        -- Write header
        file:write("-- Leaderboard Statistics\n")
        file:write("-- Auto-generated file - Do not edit manually\n")
        file:write("-- Last updated: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
        file:write("LEADERBOARD_DATA = {\n")
        
        -- Write each player's stats
        for playerName, stats in pairs(DGSS_LEADERBOARD.PLAYER_STATS) do
            file:write(string.format('    ["%s"] = {\n', playerName:gsub('"', '\\"')))
            file:write(string.format('        kills = %d,\n', stats.kills or 0))
            file:write(string.format('        deaths = %d,\n', stats.deaths or 0))
            file:write(string.format('        csarRescues = %d,\n', stats.csarRescues or 0))
            file:write(string.format('        convoyRescues = %d,\n', stats.convoyRescues or 0))
            file:write(string.format('        cratesDelivered = %d,\n', stats.cratesDelivered or 0))
            file:write(string.format('        aircraftResupplied = %d,\n', stats.aircraftResupplied or 0))
            file:write(string.format('        convoysSuccessful = %d,\n', stats.convoysSuccessful or 0))
            file:write(string.format('        convoysPartial = %d,\n', stats.convoysPartial or 0))
            file:write(string.format('        convoysFailed = %d,\n', stats.convoysFailed or 0))
            file:write(string.format('        score = %d,\n', stats.score or 0))
            file:write('    },\n')
        end
        
        file:write("}\n")
        file:close()
        
        env.info("[Leaderboard] Stats saved to: " .. filePath)
    end)
end

function DGSS_LEADERBOARD.loadStats()
    pcall(function()
        local filePath = DGSS_LEADERBOARD.SAVE_PATH .. DGSS_LEADERBOARD.SAVE_FILE
        local file = io.open(filePath, 'r')
        
        if not file then
            env.info("[Leaderboard] No previous stats file found. Starting fresh.")
            return
        end
        
        local content = file:read("*a")
        file:close()
        
        -- Load the data by executing the file
        local func = loadstring(content)
        if func then
            func()
            if LEADERBOARD_DATA then
                for playerName, stats in pairs(LEADERBOARD_DATA) do
                    DGSS_LEADERBOARD.PLAYER_STATS[playerName] = {
                        kills              = stats.kills or 0,
                        deaths             = stats.deaths or 0,
                        csarRescues        = stats.csarRescues or 0,
                        convoyRescues      = stats.convoyRescues or 0,
                        cratesDelivered    = stats.cratesDelivered or 0,
                        aircraftResupplied = stats.aircraftResupplied or 0,
                        convoysSuccessful  = stats.convoysSuccessful or 0,
                        convoysPartial     = stats.convoysPartial or 0,
                        convoysFailed      = stats.convoysFailed or 0,
                        score              = stats.score or 0,
                        lastUpdate         = now(),
                    }
                end
                env.info("[Leaderboard] Stats loaded from: " .. filePath)
            end
        end
    end)
end

----------------------------------------------------------------
-- RADIO MENUS
----------------------------------------------------------------

DGSS_LEADERBOARD.UNIT_MENUS = {}

function DGSS_LEADERBOARD.createLeaderboardMenuForUnit(unit)
    if not unit or not unit:isExist() then return end
    if not unit.getPlayerName or not unit:getPlayerName() then return end
    
    local unitName = unit:getName()
    local group = unit:getGroup()
    if not group or not group:isExist() then return end
    local groupId = group:getID()
    
    -- Skip if already created
    -- Diagnostic: log attempts to create menu
    env.info(string.format("[Leaderboard] Attempting to create menu for unit '%s' (groupId=%s)", tostring(unitName), tostring(groupId)))

    local existing = DGSS_LEADERBOARD.UNIT_MENUS[unitName]
    if existing then
        -- If an existing menu references a different group or root is missing, remove and recreate
        if existing.groupId ~= groupId or not existing.root then
            env.info(string.format("[Leaderboard] Recreating menu for '%s' (oldGroup=%s newGroup=%s)", tostring(unitName), tostring(existing.groupId), tostring(groupId)))
            -- Attempt to remove old menu
            if existing.root then pcall(function() missionCommands.removeItem(existing.root) end) end
            DGSS_LEADERBOARD.UNIT_MENUS[unitName] = nil
        else
            -- Menu already exists and is valid
            return
        end
    end
    
    DGSS_LEADERBOARD.UNIT_MENUS[unitName] = { groupId = groupId }
    
    -- Create root menu
    local leaderboardRoot = missionCommands.addSubMenuForGroup(groupId, "Leaderboard")
    DGSS_LEADERBOARD.UNIT_MENUS[unitName].root = leaderboardRoot
    env.info(string.format("[Leaderboard] Menu created for unit '%s' (groupId=%s)", tostring(unitName), tostring(groupId)))
    
    -- Full Leaderboard
    missionCommands.addCommandForGroup(
        groupId,
        "View Full Leaderboard",
        leaderboardRoot,
        function()
            local u = Unit.getByName(unitName)
            if u and u:isExist() then
                local text = DGSS_LEADERBOARD.getFullLeaderboard()
                trigger.action.outTextForUnit(u:getID(), text, 25)
            end
        end
    )
    
    -- Personal Stats
    missionCommands.addCommandForGroup(
        groupId,
        "View My Statistics",
        leaderboardRoot,
        function()
            local u = Unit.getByName(unitName)
            if u and u:isExist() and u.getPlayerName then
                local playerName = u:getPlayerName()
                if playerName then
                    local text = DGSS_LEADERBOARD.getPersonalStats(playerName)
                    trigger.action.outTextForUnit(u:getID(), text, 10)
                end
            end
        end
    )
    
    -- Top Score
    missionCommands.addCommandForGroup(
        groupId,
        "Top Score",
        leaderboardRoot,
        function()
            local u = Unit.getByName(unitName)
            if u and u:isExist() then
                local sorted = DGSS_LEADERBOARD.getSortedByScore()
                local text = DGSS_LEADERBOARD.formatLeaderboardText(sorted, " TOP SCORE", "score")
                trigger.action.outTextForUnit(u:getID(), text, 15)
            end
        end
    )
    
    -- Top Killers
    missionCommands.addCommandForGroup(
        groupId,
        "Top Killers",
        leaderboardRoot,
        function()
            local u = Unit.getByName(unitName)
            if u and u:isExist() then
                local sorted = DGSS_LEADERBOARD.getSortedByKills()
                local text = DGSS_LEADERBOARD.formatLeaderboardText(sorted, " TOP KILLERS", "kills")
                trigger.action.outTextForUnit(u:getID(), text, 15)
            end
        end
    )
    
    -- Top Rescuers
    missionCommands.addCommandForGroup(
        groupId,
        "Top Rescuers (CSAR)",
        leaderboardRoot,
        function()
            local u = Unit.getByName(unitName)
            if u and u:isExist() then
                local sorted = DGSS_LEADERBOARD.getSortedByCSAR()
                local text = DGSS_LEADERBOARD.formatLeaderboardText(sorted, " TOP RESCUERS (CSAR)", "csarRescues")
                trigger.action.outTextForUnit(u:getID(), text, 15)
            end
        end
    )
    
    -- Top Logistics (Crates)
    missionCommands.addCommandForGroup(
        groupId,
        "Top Logistics (Crates)",
        leaderboardRoot,
        function()
            local u = Unit.getByName(unitName)
            if u and u:isExist() then
                local sorted = DGSS_LEADERBOARD.getSortedByCrates()
                local text = DGSS_LEADERBOARD.formatLeaderboardText(sorted, " TOP CRATE DELIVERIES", "cratesDelivered")
                trigger.action.outTextForUnit(u:getID(), text, 15)
            end
        end
    )
    
    -- Top Resupply
    missionCommands.addCommandForGroup(
        groupId,
        "Top Resupply Operators",
        leaderboardRoot,
        function()
            local u = Unit.getByName(unitName)
            if u and u:isExist() then
                local sorted = DGSS_LEADERBOARD.getSortedByResupply()
                local text = DGSS_LEADERBOARD.formatLeaderboardText(sorted, " TOP RESUPPLY OPERATORS", "aircraftResupplied")
                trigger.action.outTextForUnit(u:getID(), text, 15)
            end
        end
    )
    
    -- Deaths (Most RIP)
    missionCommands.addCommandForGroup(
        groupId,
        "Most Deaths",
        leaderboardRoot,
        function()
            local u = Unit.getByName(unitName)
            if u and u:isExist() then
                local sorted = DGSS_LEADERBOARD.getSortedByDeaths()
                local text = DGSS_LEADERBOARD.formatLeaderboardText(sorted, " MOST DEATHS", "deaths")
                trigger.action.outTextForUnit(u:getID(), text, 15)
            end
        end
    )
end

----------------------------------------------------------------
-- PLAYER SCANNER - Scan for new players joining every minute
----------------------------------------------------------------

local function scanForNewPlayers()
    local bluePlanes = coalition.getGroups(DGSS_LEADERBOARD.COALITION, Group.Category.AIRPLANE) or {}
    local blueHelos = coalition.getGroups(DGSS_LEADERBOARD.COALITION, Group.Category.HELICOPTER) or {}
    
    for _, group in ipairs(bluePlanes) do
        if group and group:isExist() then
            for _, unit in ipairs(group:getUnits()) do
                if unit and unit:isExist() and unit.getPlayerName then
                    local playerName = unit:getPlayerName()
                    if playerName then
                        -- Initialize player if not already tracked
                        if not DGSS_LEADERBOARD.PLAYER_STATS[playerName] then
                            initPlayerStats(playerName)
                            -- Persist immediately so joining players are recorded
                            pcall(function() DGSS_LEADERBOARD.saveStats() end)
                        end
                    end
                end
            end
        end
    end
    
    for _, group in ipairs(blueHelos) do
        if group and group:isExist() then
            for _, unit in ipairs(group:getUnits()) do
                if unit and unit:isExist() and unit.getPlayerName then
                    local playerName = unit:getPlayerName()
                    if playerName then
                        -- Initialize player if not already tracked
                        if not DGSS_LEADERBOARD.PLAYER_STATS[playerName] then
                            initPlayerStats(playerName)
                            -- Persist immediately so joining players are recorded
                            pcall(function() DGSS_LEADERBOARD.saveStats() end)
                        end
                    end
                end
            end
        end
    end
    
    -- Schedule next scan in 60 seconds (1 minute)
    if mist and mist.scheduleFunction then
        mist.scheduleFunction(scanForNewPlayers, {}, timer.getTime() + 60)
    else
        timer.scheduleFunction(scanForNewPlayers, {}, timer.getTime() + 60)
    end
end

----------------------------------------------------------------
-- UNIVERSAL MENU POLLER
----------------------------------------------------------------

    -- v3.5 Performance Optimization:
    -- - Menu update interval increased from 10s to 60s (reduces server load)
    -- - Existing UNIT_MENUS tracking prevents duplicate menu creation
local function leaderboardMenuPoller()
    local bluePlanes = coalition.getGroups(DGSS_LEADERBOARD.COALITION, Group.Category.AIRPLANE) or {}
    local blueHelos = coalition.getGroups(DGSS_LEADERBOARD.COALITION, Group.Category.HELICOPTER) or {}
    
    for _, group in ipairs(bluePlanes) do
        if group and group:isExist() then
            for _, unit in ipairs(group:getUnits()) do
                if unit and unit:isExist() and unit.getPlayerName and unit:getPlayerName() then
                    DGSS_LEADERBOARD.createLeaderboardMenuForUnit(unit)
                end
            end
        end
    end
    
    for _, group in ipairs(blueHelos) do
        if group and group:isExist() then
            for _, unit in ipairs(group:getUnits()) do
                if unit and unit:isExist() and unit.getPlayerName and unit:getPlayerName() then
                    DGSS_LEADERBOARD.createLeaderboardMenuForUnit(unit)
                end
            end
        end
    end
    
    if mist and mist.scheduleFunction then
        mist.scheduleFunction(leaderboardMenuPoller, {}, timer.getTime() + 60)
    else
        timer.scheduleFunction(leaderboardMenuPoller, {}, timer.getTime() + 60)
    end
end

if mist and mist.scheduleFunction then
    mist.scheduleFunction(leaderboardMenuPoller, {}, timer.getTime() + 60)
else
    timer.scheduleFunction(leaderboardMenuPoller, {}, timer.getTime() + 60)
end

----------------------------------------------------------------
-- CLEANUP LOOPS FOR TRACKING TABLES
----------------------------------------------------------------

local function cleanupTrackingTables()
    local cleaned = 0
    
    -- Cleanup UNIT_TRACKING for destroyed units
    for unitName, _ in pairs(DGSS_LEADERBOARD.UNIT_TRACKING) do
        local unit = Unit.getByName(unitName)
        if not unit or not unit:isExist() then
            DGSS_LEADERBOARD.UNIT_TRACKING[unitName] = nil
            cleaned = cleaned + 1
        end
    end
    
    -- Cleanup AIRCRAFT_TRACKING for destroyed aircraft
    for unitName, _ in pairs(DGSS_LEADERBOARD.AIRCRAFT_TRACKING) do
        local unit = Unit.getByName(unitName)
        if not unit or not unit:isExist() then
            DGSS_LEADERBOARD.AIRCRAFT_TRACKING[unitName] = nil
            cleaned = cleaned + 1
        end
    end
    
    -- Cleanup UNIT_MENUS for units no longer existing
    for unitName, menu in pairs(DGSS_LEADERBOARD.UNIT_MENUS) do
        local unit = Unit.getByName(unitName)
        if not unit or not unit:isExist() then
            DGSS_LEADERBOARD.UNIT_MENUS[unitName] = nil
            cleaned = cleaned + 1
        end
    end
    
    -- Clean up stale delivery/resupply/death timestamps (older than 10 minutes)
    local t = now()
    for playerName, timestamp in pairs(DGSS_LEADERBOARD.LAST_DELIVERY_TIME) do
        if (t - timestamp) > 600 then
            DGSS_LEADERBOARD.LAST_DELIVERY_TIME[playerName] = nil
            cleaned = cleaned + 1
        end
    end
    
    for playerName, timestamp in pairs(DGSS_LEADERBOARD.LAST_RESUPPLY_TIME) do
        if (t - timestamp) > 600 then
            DGSS_LEADERBOARD.LAST_RESUPPLY_TIME[playerName] = nil
            cleaned = cleaned + 1
        end
    end
    
    for playerName, timestamp in pairs(DGSS_LEADERBOARD.LAST_DEATH_TIME) do
        if (t - timestamp) > 600 then
            DGSS_LEADERBOARD.LAST_DEATH_TIME[playerName] = nil
            cleaned = cleaned + 1
        end
    end
    
    -- Clean up stale warehouse delivery tracking (older than 5 minutes)
    for zoneName, timestamp in pairs(DGSS_LEADERBOARD.LAST_WAREHOUSE_DELIVERY) do
        if (t - timestamp) > 300 then
            DGSS_LEADERBOARD.LAST_WAREHOUSE_DELIVERY[zoneName] = nil
            cleaned = cleaned + 1
        end
    end
    
    -- Clean up old landing records (older than 3 minutes)
    for zoneName, landing in pairs(DGSS_LEADERBOARD.RECENT_LANDINGS) do
        if landing and landing.landingTime and (t - landing.landingTime) > 180 then
            DGSS_LEADERBOARD.RECENT_LANDINGS[zoneName] = nil
            cleaned = cleaned + 1
        end
    end
    
    if cleaned > 0 then
        env.info(string.format("[Leaderboard] Cleaned up %d dead/stale tracking entries", cleaned))
    end
    
    if mist and mist.scheduleFunction then
        mist.scheduleFunction(cleanupTrackingTables, {}, timer.getTime() + 60)
    else
        timer.scheduleFunction(cleanupTrackingTables, {}, timer.getTime() + 60)
    end
end

if mist and mist.scheduleFunction then
    mist.scheduleFunction(cleanupTrackingTables, {}, timer.getTime() + 60)
else
    timer.scheduleFunction(cleanupTrackingTables, {}, timer.getTime() + 60)
end

----------------------------------------------------------------
-- LOAD SAVED STATS
----------------------------------------------------------------

DGSS_LEADERBOARD.loadStats()

-- Ensure a save file exists / is up-to-date on mission init
-- This guarantees the leaderboard has a persistent file to be updated
pcall(function() DGSS_LEADERBOARD.saveStats() end)

----------------------------------------------------------------
-- START PLAYER SCANNER (every 60 seconds)
----------------------------------------------------------------

if mist and mist.scheduleFunction then
    mist.scheduleFunction(scanForNewPlayers, {}, timer.getTime() + 60)
else
    timer.scheduleFunction(scanForNewPlayers, {}, timer.getTime() + 60)
end

----------------------------------------------------------------
-- AUTO-SAVE STATS (every 15 minutes)
----------------------------------------------------------------

local function autoSaveStats()
    pcall(function()
        DGSS_LEADERBOARD.saveStats()
        env.info("[Leaderboard] Auto-save triggered")
    end)
    
    -- Schedule next auto-save in 900 seconds (15 minutes)
    if mist and mist.scheduleFunction then
        mist.scheduleFunction(autoSaveStats, {}, timer.getTime() + 900)
    else
        timer.scheduleFunction(autoSaveStats, {}, timer.getTime() + 900)
    end
end

if mist and mist.scheduleFunction then
    mist.scheduleFunction(autoSaveStats, {}, timer.getTime() + 900)
else
    timer.scheduleFunction(autoSaveStats, {}, timer.getTime() + 900)
end

----------------------------------------------------------------
-- DEBUG: SCRIPT LOADED
----------------------------------------------------------------

trigger.action.outText("[Leaderboard] Leaderboard System Loaded", 10)
env.info("[Leaderboard] Leaderboard System initialization complete.")
