-- ============================================================
--   MISSION STATE PERSISTENCE (v3.0)
--   Based on SWS (Simple Warehouse Saving) & SGS (Simple Group Saving)
--   MIST-only, no MOOSE dependencies
--   Saves CJTF-BLUE groups and airbase warehouses every 5 minutes
-- ============================================================

MISSIONPERSIST = {}
MISSIONPERSIST.saveDir = lfs.writedir() .. "Mission Saves\\"
MISSIONPERSIST.groupFile = MISSIONPERSIST.saveDir .. "MissionGroups.lua"
MISSIONPERSIST.warehouseFile = MISSIONPERSIST.saveDir .. "MissionWarehouses.lua"
MISSIONPERSIST.saveInterval = 600  -- 10 minutes
MISSIONPERSIST.lastSavedState = {}  -- Track last saved state for change detection

local version = "3.0 - Jan 2025"

-- ============================================================
-- UTILITY: Create Save Directory
-- ============================================================

function MISSIONPERSIST.ensureDirectory()
    local attr = lfs.attributes(MISSIONPERSIST.saveDir)
    if not attr then
        local ok, err = lfs.mkdir(MISSIONPERSIST.saveDir)
        if ok then
            env.info("[PERSISTENCE] Created save directory: " .. MISSIONPERSIST.saveDir)
        else
            env.warning("[PERSISTENCE] Failed to create directory: " .. tostring(err))
            return false
        end
    end
    return true
end

-- ============================================================
-- SERIALIZATION (from SWS - battle-tested)
-- ============================================================

function MISSIONPERSIST.basicSerialize(s)
    if s == nil then
        return '""'
    elseif type(s) == 'number' or type(s) == 'boolean' then
        return tostring(s)
    elseif type(s) == 'string' then
        return string.format('%q', s)
    end
end

function MISSIONPERSIST.serializeWithCycles(name, value, saved)
    local t_str = {}
    saved = saved or {}
    
    if type(value) == 'string' or type(value) == 'number' or type(value) == 'table' or type(value) == 'boolean' then
        table.insert(t_str, name .. " = ")
        if type(value) == "number" or type(value) == "string" or type(value) == "boolean" then
            if type(value) == "number" then
                table.insert(t_str, tostring(value) .. "\n")
            elseif type(value) == "boolean" then
                table.insert(t_str, tostring(value) .. "\n")
            else
                table.insert(t_str, MISSIONPERSIST.basicSerialize(value) .. "\n")
            end
        else
            if saved[value] then
                table.insert(t_str, saved[value] .. "\n")
            else
                saved[value] = name
                table.insert(t_str, "{}\n")
                for k, v in pairs(value) do
                    local fieldname = string.format("%s[%s]", name, MISSIONPERSIST.basicSerialize(k))
                    table.insert(t_str, MISSIONPERSIST.serializeWithCycles(fieldname, v, saved))
                end
            end
        end
        return table.concat(t_str)
    else
        return ""
    end
end

-- ============================================================
-- FILE UTILITIES
-- ============================================================

function MISSIONPERSIST.fileExists(filepath)
    return lfs.attributes(filepath) ~= nil
end

function MISSIONPERSIST.writeFile(data, filepath)
    local f = io.open(filepath, "w")
    if f then
        f:write(data)
        f:close()
        return true
    else
        env.warning("[PERSISTENCE] Failed to write: " .. filepath)
        return false
    end
end

function MISSIONPERSIST.readFile(filepath)
    local f = io.open(filepath, "r")
    if not f then
        return nil
    end
    local content = f:read("*all")
    f:close()
    return content
end

-- ============================================================
-- GROUP SAVING (SGS-style)
-- ============================================================

function MISSIONPERSIST.captureGroups()
    MISSIONPERSIST.SavedGroups = {}
    local saved = 0
    local unchanged = 0
    local cleaned = 0
    
    -- Iterate ground groups (ME-placed + dynamically spawned).
    -- Include CJTF-BLUE and DGSS_CTLD spawn country (if DGSS_CTLD present)
    for groupName, groupData in pairs(mist.DBs.groupsByName) do
        if groupData.category == "ground" and (groupData.country == country.id.CJTF_BLUE or (DGSS_CTLD and groupData.country == DGSS_CTLD.COUNTRY)) then
            local group = Group.getByName(groupName)
            
            if group and group:isExist() then
                local units = group:getUnits()
                if units and #units > 0 then
                    local unitTable = {}
                    local hasAlive = false
                    
                    -- Capture each living unit
                    for _, unit in ipairs(units) do
                        if unit and unit:isExist() and unit:getLife() > 0 then
                            hasAlive = true
                            local pos = unit:getPoint()
                            
                            -- Capture unit state
                            local fuel = 1.0
                            pcall(function() fuel = unit:getFuel() end)
                            
                            table.insert(unitTable, {
                                type = unit:getTypeName(),
                                name = unit:getName(),
                                x = pos.x,
                                y = pos.z,
                                heading = mist.getHeading(unit),
                                skill = "Average",
                                fuel = fuel,
                                life = unit:getLife()
                            })
                        end
                    end
                    
                    -- Save group if it has living units
                    if hasAlive then
                        local groupPos = group:getPoint()
                        
                        -- Check if group state changed since last save (optimization)
                        local currentHash = string.format("%.0f_%.0f_%d", groupPos.x, groupPos.z, #unitTable)
                        local lastHash = MISSIONPERSIST.lastSavedState[groupName]
                        
                        if currentHash ~= lastHash then
                            -- State changed - save it
                            MISSIONPERSIST.SavedGroups[groupName] = {
                                name = groupName,
                                country = groupData.country,
                                category = groupData.category,
                                coalition = groupData.coalition,
                                task = "Ground Nothing",
                                x = groupPos.x,
                                y = groupPos.z,
                                units = unitTable
                            }
                            MISSIONPERSIST.lastSavedState[groupName] = currentHash
                            saved = saved + 1
                        else
                            -- No change - still need to save (SavedGroups was cleared at start)
                            MISSIONPERSIST.SavedGroups[groupName] = {
                                name = groupName,
                                country = groupData.country,
                                category = groupData.category,
                                task = "Ground Nothing",
                                x = groupPos.x,
                                y = groupPos.z,
                                units = unitTable
                            }
                            unchanged = unchanged + 1
                        end
                    end
                end
            else
                -- Group is dead - clean up tracking
                if MISSIONPERSIST.lastSavedState[groupName] then
                    MISSIONPERSIST.lastSavedState[groupName] = nil
                    cleaned = cleaned + 1
                end
            end
        end
    end
    
    env.info(string.format("[PERSISTENCE] Captured: %d groups (%d changed, %d unchanged, %d cleaned)", 
        saved + unchanged, saved, unchanged, cleaned))
end

function MISSIONPERSIST.saveGroups()
    MISSIONPERSIST.captureGroups()
    local serialized = MISSIONPERSIST.serializeWithCycles("MISSIONPERSIST.SavedGroups", MISSIONPERSIST.SavedGroups)
    if MISSIONPERSIST.writeFile(serialized, MISSIONPERSIST.groupFile) then
        env.info("[PERSISTENCE] Groups saved to file")
    end
end

function MISSIONPERSIST.loadGroups()
    if not MISSIONPERSIST.fileExists(MISSIONPERSIST.groupFile) then
        env.info("[PERSISTENCE] No saved groups file found")
        MISSIONPERSIST.SavedGroups = {}
        return
    end
    
    local content = MISSIONPERSIST.readFile(MISSIONPERSIST.groupFile)
    if not content then
        env.warning("[PERSISTENCE] Failed to read groups file")
        MISSIONPERSIST.SavedGroups = {}
        return
    end
    
    local chunk = loadstring(content)
    if not chunk then
        env.warning("[PERSISTENCE] Failed to parse groups file")
        MISSIONPERSIST.SavedGroups = {}
        return
    end
    
    local ok, err = pcall(chunk)
    if ok then
        env.info("[PERSISTENCE] Loaded saved groups")
    else
        env.warning("[PERSISTENCE] Error loading groups: " .. tostring(err))
        MISSIONPERSIST.SavedGroups = {}
    end
end

function MISSIONPERSIST.restoreGroups()
    -- STEP 1: Destroy ALL existing Blue ground groups (ME + dynamic)
    env.info("[PERSISTENCE] Destroying all existing Blue ground groups...")
    local destroyed = 0
    
    for groupName, groupData in pairs(mist.DBs.groupsByName) do
        if groupData.category == "ground" and (groupData.country == country.id.CJTF_BLUE or (DGSS_CTLD and groupData.country == DGSS_CTLD.COUNTRY)) then
            local group = Group.getByName(groupName)
            if group and group:isExist() then
                pcall(function() group:destroy() end)
                destroyed = destroyed + 1
            end
        end
    end
    
    env.info("[PERSISTENCE] Destroyed " .. destroyed .. " existing groups")
    
    -- STEP 2: Spawn all groups from save file
    local restored = 0
    local failed = 0
    
    for groupName, groupData in pairs(MISSIONPERSIST.SavedGroups or {}) do
        -- Build unit table
        local units = {}
        for _, unitData in ipairs(groupData.units) do
            table.insert(units, {
                type = unitData.type,
                name = unitData.name,
                x = unitData.x,
                y = unitData.y,
                heading = unitData.heading,
                skill = unitData.skill,
                playerCanDrive = true
            })
        end
        
        -- Build group template
        local groupTemplate = {
            visible = true,
            tasks = {},
            uncontrollable = false,
            task = groupData.task,
            hidden = false,
            units = units,
            y = groupData.y,
            x = groupData.x,
            name = groupName
        }
        
        -- Spawn group
        local ok, err = pcall(function()
            coalition.addGroup(groupData.country, Group.Category.GROUND, groupTemplate)
        end)
        
        if ok then
            -- Restore unit fuel
            local group = Group.getByName(groupName)
            if group and group:isExist() then
                local units = group:getUnits()
                for i, unit in ipairs(units) do
                    if unit and unit:isExist() then
                        local savedUnit = groupData.units[i]
                        if savedUnit and savedUnit.fuel then
                            pcall(function() unit:setFuel(savedUnit.fuel) end)
                        end
                    end
                end
            end
            
            restored = restored + 1
        else
            env.warning("[PERSISTENCE] Failed to restore " .. groupName .. ": " .. tostring(err))
            failed = failed + 1
        end
    end
    
    env.info("[PERSISTENCE] Restored " .. restored .. " groups, " .. failed .. " failed")
end

-- ============================================================
-- WAREHOUSE SAVING (SWS-style)
-- ============================================================

function MISSIONPERSIST.captureWarehouses()
    MISSIONPERSIST.SavedWarehouses = {}
    
    local airbases = world.getAirbases()
    if not airbases then
        env.warning("[PERSISTENCE] No airbases found")
        return
    end
    
    local count = 0
    for i = 1, #airbases do
        local airbase = airbases[i]
        local w = airbase:getWarehouse()
        if w then
            local name = airbase:getName()
            local inv = w:getInventory()
            if inv then
                MISSIONPERSIST.SavedWarehouses[name] = inv
                count = count + 1
            end
        end
    end
    
    env.info("[PERSISTENCE] Captured " .. count .. " warehouse(s)")
end

function MISSIONPERSIST.saveWarehouses()
    MISSIONPERSIST.captureWarehouses()
    local serialized = MISSIONPERSIST.serializeWithCycles("MISSIONPERSIST.SavedWarehouses", MISSIONPERSIST.SavedWarehouses)
    if MISSIONPERSIST.writeFile(serialized, MISSIONPERSIST.warehouseFile) then
        env.info("[PERSISTENCE] Warehouses saved to file")
    end
end

function MISSIONPERSIST.loadWarehouses()
    if not MISSIONPERSIST.fileExists(MISSIONPERSIST.warehouseFile) then
        env.info("[PERSISTENCE] No saved warehouses file found")
        MISSIONPERSIST.SavedWarehouses = {}
        return
    end
    
    local content = MISSIONPERSIST.readFile(MISSIONPERSIST.warehouseFile)
    if not content then
        env.warning("[PERSISTENCE] Failed to read warehouses file")
        MISSIONPERSIST.SavedWarehouses = {}
        return
    end
    
    local chunk = loadstring(content)
    if not chunk then
        env.warning("[PERSISTENCE] Failed to parse warehouses file")
        MISSIONPERSIST.SavedWarehouses = {}
        return
    end
    
    local ok, err = pcall(chunk)
    if ok then
        env.info("[PERSISTENCE] Loaded saved warehouses")
    else
        env.warning("[PERSISTENCE] Error loading warehouses: " .. tostring(err))
        MISSIONPERSIST.SavedWarehouses = {}
    end
end

function MISSIONPERSIST.restoreWarehouses()
    local airbases = world.getAirbases()
    if not airbases then
        env.warning("[PERSISTENCE] No airbases to restore warehouses")
        return
    end
    
    local restored = 0
    local failed = 0
    
    for _, airbase in ipairs(airbases) do
        local name = airbase:getName()
        local saved_inv = MISSIONPERSIST.SavedWarehouses[name]
        
        if saved_inv then
            local w = airbase:getWarehouse()
            if w then
                local ok, err = pcall(function()
                    -- Restore liquids
                    if saved_inv.liquids then
                        for liquidType, amount in pairs(saved_inv.liquids) do
                            w:setLiquidAmount(liquidType, amount)
                        end
                    end
                    
                    -- Restore weapons
                    if saved_inv.weapon then
                        for weaponName, amount in pairs(saved_inv.weapon) do
                            w:setItem(weaponName, amount)
                        end
                    end
                    
                    -- Restore aircraft
                    if saved_inv.aircraft then
                        for aircraftName, count in pairs(saved_inv.aircraft) do
                            w:setItem(aircraftName, count)
                        end
                    end
                end)
                
                if ok then
                    env.info("[PERSISTENCE] Restored warehouse: " .. name)
                    restored = restored + 1
                else
                    env.warning("[PERSISTENCE] Failed to restore warehouse " .. name)
                    failed = failed + 1
                end
            end
        end
    end
    
    env.info("[PERSISTENCE] Warehouses: " .. restored .. " restored, " .. failed .. " failed")
end

-- ============================================================
-- CAPTURE INITIAL GROUPS (ME-placed units to exclude)
-- ============================================================

function MISSIONPERSIST.captureInitialGroups()
    MISSIONPERSIST.initialGroups = {}
    local count = 0
    
    -- Capture all ME-placed CJTF-BLUE ground groups at mission start
    for groupName, groupData in pairs(mist.DBs.groupsByName) do
        if groupData.country == country.id.CJTF_BLUE and groupData.category == "ground" then
            local group = Group.getByName(groupName)
            if group and group:isExist() then
                MISSIONPERSIST.initialGroups[groupName] = true
                count = count + 1
            end
        end
    end
    
    env.info(string.format("[PERSISTENCE] Captured %d initial ME-placed groups", count))
end

-- ============================================================
-- PERIODIC SAVE LOOP (every 5 minutes)
-- ============================================================

function MISSIONPERSIST.periodicSave()
    env.info("[PERSISTENCE] Saving state...")
    MISSIONPERSIST.saveGroups()
    MISSIONPERSIST.saveWarehouses()
    return timer.getTime() + MISSIONPERSIST.saveInterval
end

-- ============================================================
-- INITIALIZATION
-- ============================================================

env.info("[PERSISTENCE] Loading Mission Persistence v" .. version)

-- Verify dependencies
if not lfs then
    env.error("[PERSISTENCE] LFS not available - DISABLED")
    return
end

if not mist then
    env.error("[PERSISTENCE] MIST not loaded - DISABLED")
    return
end

-- Create save directory
if not MISSIONPERSIST.ensureDirectory() then
    env.error("[PERSISTENCE] Failed to create save directory - DISABLED")
    return
end

-- Capture initial groups (ME-placed units to exclude from saves)
MISSIONPERSIST.captureInitialGroups()

-- Load saved state
MISSIONPERSIST.loadGroups()
MISSIONPERSIST.loadWarehouses()

-- Delayed restoration (wait 15 seconds for mission stability)
local function delayedRestore()
    env.info("[PERSISTENCE] Applying saved state...")
    MISSIONPERSIST.restoreGroups()
    MISSIONPERSIST.restoreWarehouses()
    env.info("[PERSISTENCE] Restoration complete, periodic saves active (every 10 minutes)")
    timer.scheduleFunction(MISSIONPERSIST.periodicSave, {}, timer.getTime() + MISSIONPERSIST.saveInterval)
end

timer.scheduleFunction(delayedRestore, {}, timer.getTime() + 15)