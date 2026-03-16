-- ============================================================
--   MISSION STATE PERSISTENCE (v5.0)
--   Based on SWS (Simple Warehouse Saving) & SGS (Simple Group Saving)
--   MIST-only, no MOOSE dependencies
--   Saves CJTF-BLUE and CJTF-RED groups and airbase warehouses every 15 minutes
--   Excludes convoy, DGSS, and ISIS TOO dynamic groups from persistence
--   Save-file versioning: mismatched files log a warning on load
-- ============================================================

MISSIONPERSIST = {}
MISSIONPERSIST.saveDir = lfs.writedir() .. "Mission Saves\\"
MISSIONPERSIST.groupFile = MISSIONPERSIST.saveDir .. "MissionGroups.lua"
MISSIONPERSIST.warehouseFile = MISSIONPERSIST.saveDir .. "MissionWarehouses.lua"
MISSIONPERSIST.redDeadFile = MISSIONPERSIST.saveDir .. "RedDeadGroups.lua"
MISSIONPERSIST.redAirDeadFile = MISSIONPERSIST.saveDir .. "RedAirDeadGroups.lua"
MISSIONPERSIST.catalogFile    = MISSIONPERSIST.saveDir .. "RedGroupCatalog.lua"
MISSIONPERSIST.saveInterval = 900  -- 15 minutes
MISSIONPERSIST.lastSavedState = {}  -- Track last saved state for change detection
MISSIONPERSIST.RedDeadGroups = {}      -- [groupName] = true  for RED ground groups whose last unit was destroyed
MISSIONPERSIST.RedAirDeadGroups = {}   -- [groupName] = true  for RED air groups whose last unit was destroyed
MISSIONPERSIST.RedGroundCatalog = {}   -- [groupName] = true  ALL known RED ground groups (incl. late-activate)
MISSIONPERSIST.RedAirCatalog = {}      -- [groupName] = true  ALL known RED air groups (incl. late-activate)
MISSIONPERSIST._deferredGroupSavePending = false  -- debounce: at most one pending partial-kill saveGroups() at a time
MISSIONPERSIST._lastPeriodicDeadGroundCount = 0   -- change-detection: skip periodic write when no new ground deaths
MISSIONPERSIST._lastPeriodicDeadAirCount    = 0   -- change-detection: skip periodic write when no new air deaths

-- Save-file format version. Bump this whenever the saved data structure changes
-- so that stale files from an older format are caught on load.
MISSIONPERSIST.SAVE_VERSION = "5.0"

-- Group name prefixes belonging to other dynamic scripts.
-- Any group whose name starts with one of these prefixes will be skipped
-- by the save/restore cycle — those scripts manage their own respawn.
MISSIONPERSIST.excludedPrefixes = {
    "ActiveConvoy_",        -- RedAutomatedConvoySystem
    "Ins_",                 -- DGSS (all variants incl. engagement _RED_/_BLUE_ suffixes)
    "RED_SAM_SHORAD_Ins_",  -- DGSS SHORAD templates
    "ISIS_",                -- Syria ISIS TOO system
}

local version = "5.0 - Mar 2026"

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
-- EXCLUSION FILTER
-- ============================================================

-- Returns true if groupName belongs to a dynamic script that manages its
-- own unit lifecycle (convoy, DGSS, ISIS TOO) and should NOT be persisted.
function MISSIONPERSIST.isExcludedGroup(groupName)
    for _, prefix in ipairs(MISSIONPERSIST.excludedPrefixes) do
        if groupName:sub(1, #prefix) == prefix then
            return true
        end
    end
    return false
end

-- ============================================================
-- GROUP SAVING (SGS-style)
-- ============================================================

function MISSIONPERSIST.captureGroups()
    MISSIONPERSIST.SavedGroups = {}
    
    -- Iterate ground groups (ME-placed + dynamically spawned).
    -- Include CJTF-BLUE, CJTF-RED, and DGSS_CTLD spawn country (if DGSS_CTLD present)
    -- Exclude groups owned by other dynamic scripts (convoy, DGSS, ISIS TOO)
    for groupName, groupData in pairs(mist.DBs.groupsByName) do
        if groupData.category == "ground" and
           not MISSIONPERSIST.isExcludedGroup(groupName) and (
            groupData.country == country.id.CJTF_BLUE or
            groupData.country == country.id.CJTF_RED or
            (DGSS_CTLD and groupData.country == DGSS_CTLD.COUNTRY)
        ) then
            local group = Group.getByName(groupName)
            
            if group and group:isExist() then
                -- Quick check BEFORE any per-unit work:
                -- group:getSize() returns alive unit count with no loop needed
                local aliveCount = group:getSize()
                if aliveCount > 0 then
                    local groupPos = group:getPoint()
                    local currentHash = string.format("%.0f_%.0f_%d", groupPos.x, groupPos.z, aliveCount)
                    local lastEntry = MISSIONPERSIST.lastSavedState[groupName]

                    if lastEntry and lastEntry.hash == currentHash then
                        -- Unchanged: reuse cached data, skip all per-unit API calls
                        MISSIONPERSIST.SavedGroups[groupName] = lastEntry.data
                    else
                        -- Changed or new: do full unit capture
                        local unitTable = {}
                        for _, unit in ipairs(group:getUnits()) do
                            if unit and unit:isExist() and unit:getLife() > 0 then
                                local pos = unit:getPoint()
                                local fuel = 1.0
                                pcall(function() fuel = unit:getFuel() end)
                                table.insert(unitTable, {
                                    type    = unit:getTypeName(),
                                    name    = unit:getName(),
                                    x       = pos.x,
                                    y       = pos.z,
                                    heading = mist.getHeading(unit),
                                    skill   = "Average",
                                    fuel    = fuel,
                                    life    = unit:getLife()
                                })
                            end
                        end

                        local groupEntry = {
                            name      = groupName,
                            country   = groupData.country,
                            category  = groupData.category,
                            coalition = groupData.coalition,
                            task      = "Ground Nothing",
                            x         = groupPos.x,
                            y         = groupPos.z,
                            units     = unitTable
                        }

                        MISSIONPERSIST.SavedGroups[groupName] = groupEntry
                        MISSIONPERSIST.lastSavedState[groupName] = { hash = currentHash, data = groupEntry }
                    end
                end
            else
                -- Group is dead - clean up tracking
                MISSIONPERSIST.lastSavedState[groupName] = nil
            end
        end
    end

    -- Belt-and-suspenders: scan catalog for any dead RED ground groups missed by event handler.
    -- Uses the pre-built catalog (built once at init from full MIST DB, incl. late-activate)
    -- rather than iterating the entire MIST DB on every periodic call.
    for groupName in pairs(MISSIONPERSIST.RedGroundCatalog) do
        if not MISSIONPERSIST.RedDeadGroups[groupName] then
            local grp = Group.getByName(groupName)
            if not grp or not grp:isExist() or grp:getSize() <= 0 then
                MISSIONPERSIST.RedDeadGroups[groupName] = true
                env.info("[PERSISTENCE] captureGroups: RED ground group dead (scan): " .. groupName)
            end
        end
    end

    -- Belt-and-suspenders: scan catalog for dead RED air groups missed by event handler.
    for groupName in pairs(MISSIONPERSIST.RedAirCatalog) do
        if not MISSIONPERSIST.RedAirDeadGroups[groupName] then
            local grp = Group.getByName(groupName)
            if not grp or not grp:isExist() or grp:getSize() <= 0 then
                MISSIONPERSIST.RedAirDeadGroups[groupName] = true
                env.info("[PERSISTENCE] captureGroups: RED air group dead (scan): " .. groupName)
            end
        end
    end
end

function MISSIONPERSIST.saveGroups()
    MISSIONPERSIST.captureGroups()
    local header = string.format("MISSIONPERSIST.SaveVersion = %q\n", MISSIONPERSIST.SAVE_VERSION)
    local serialized = MISSIONPERSIST.serializeWithCycles("MISSIONPERSIST.SavedGroups", MISSIONPERSIST.SavedGroups)
    MISSIONPERSIST.writeFile(header .. serialized, MISSIONPERSIST.groupFile)
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
        -- Version check
        if MISSIONPERSIST.SaveVersion ~= MISSIONPERSIST.SAVE_VERSION then
            env.warning(string.format(
                "[PERSISTENCE] Groups save-file version mismatch: file is '%s', expected '%s'. Data may be incompatible.",
                tostring(MISSIONPERSIST.SaveVersion), MISSIONPERSIST.SAVE_VERSION
            ))
        else
            env.info(string.format("[PERSISTENCE] Loaded saved groups (save version %s)", MISSIONPERSIST.SaveVersion))
        end
    else
        env.warning("[PERSISTENCE] Error loading groups: " .. tostring(err))
        MISSIONPERSIST.SavedGroups = {}
    end
end

function MISSIONPERSIST.restoreGroups()
    -- STEP 1: Destroy ALL existing Blue and Red ground groups (ME + dynamic)
    env.info("[PERSISTENCE] Destroying all existing Blue and Red ground groups...")
    local destroyed = 0
    
    for groupName, groupData in pairs(mist.DBs.groupsByName) do
        if groupData.category == "ground" and (
            groupData.country == country.id.CJTF_BLUE or
            groupData.country == country.id.CJTF_RED or
            (DGSS_CTLD and groupData.country == DGSS_CTLD.COUNTRY)
        ) then
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
        -- Skip RED groups confirmed dead — insurance in case a dead group
        -- was captured as alive in the last save before a crash.
        if MISSIONPERSIST.RedDeadGroups[groupName] then
            env.info("[PERSISTENCE] restoreGroups: skipping dead RED group: " .. groupName)
        else

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

        end  -- close RedDeadGroups skip block
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
end

function MISSIONPERSIST.saveWarehouses()
    MISSIONPERSIST.captureWarehouses()
    local header = string.format("MISSIONPERSIST.WarehouseSaveVersion = %q\n", MISSIONPERSIST.SAVE_VERSION)
    local serialized = MISSIONPERSIST.serializeWithCycles("MISSIONPERSIST.SavedWarehouses", MISSIONPERSIST.SavedWarehouses)
    MISSIONPERSIST.writeFile(header .. serialized, MISSIONPERSIST.warehouseFile)
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
        -- Version check
        if MISSIONPERSIST.WarehouseSaveVersion ~= MISSIONPERSIST.SAVE_VERSION then
            env.warning(string.format(
                "[PERSISTENCE] Warehouses save-file version mismatch: file is '%s', expected '%s'. Data may be incompatible.",
                tostring(MISSIONPERSIST.WarehouseSaveVersion), MISSIONPERSIST.SAVE_VERSION
            ))
        else
            env.info(string.format("[PERSISTENCE] Loaded saved warehouses (save version %s)", MISSIONPERSIST.WarehouseSaveVersion))
        end
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
    
    -- Capture all ME-placed CJTF-BLUE and CJTF-RED ground groups at mission start
    for groupName, groupData in pairs(mist.DBs.groupsByName) do
        if groupData.category == "ground" and (
            groupData.country == country.id.CJTF_BLUE or
            groupData.country == country.id.CJTF_RED
        ) then
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
-- RED GROUP CATALOG
-- Builds a complete catalog of ALL known RED ground and air groups
-- from the MIST DB at mission start, including late-activate groups
-- that may not yet be active in the DCS runtime.  The catalog is
-- used by captureGroups() so the belt-and-suspenders dead-scan
-- iterates only RED groups instead of the entire MIST DB each call.
-- The catalog is also saved to disk so it survives server restarts.
-- ============================================================

function MISSIONPERSIST.captureRedCatalogs()
    MISSIONPERSIST.RedGroundCatalog = {}
    MISSIONPERSIST.RedAirCatalog    = {}
    local groundCount, airCount = 0, 0
    for groupName, groupData in pairs(mist.DBs.groupsByName) do
        if groupData.country == country.id.CJTF_RED
           and not MISSIONPERSIST.isExcludedGroup(groupName) then
            if groupData.category == "ground" then
                MISSIONPERSIST.RedGroundCatalog[groupName] = true
                groundCount = groundCount + 1
            elseif groupData.category == "plane" or groupData.category == "helicopter" then
                MISSIONPERSIST.RedAirCatalog[groupName] = true
                airCount = airCount + 1
            end
        end
    end
    env.info(string.format(
        "[PERSISTENCE] RED catalog built: %d ground groups, %d air groups (incl. late-activate)",
        groundCount, airCount))
end

-- Write the catalog tables to disk.  Called by periodicSave() every 15 minutes.
function MISSIONPERSIST.saveCatalogs()
    local header = string.format("MISSIONPERSIST.CatalogSaveVersion = %q\n", MISSIONPERSIST.SAVE_VERSION)
    local s1 = MISSIONPERSIST.serializeWithCycles("MISSIONPERSIST.RedGroundCatalog", MISSIONPERSIST.RedGroundCatalog)
    local s2 = MISSIONPERSIST.serializeWithCycles("MISSIONPERSIST.RedAirCatalog",    MISSIONPERSIST.RedAirCatalog)
    MISSIONPERSIST.writeFile(header .. s1 .. s2, MISSIONPERSIST.catalogFile)
end

-- Load a previously-saved catalog and merge any extra group names into
-- the freshly-built in-memory catalog.  Guards against the rare edge case
-- where the MIST DB scan misses a group that existed in a prior session.
function MISSIONPERSIST.loadAndMergeCatalogs()
    if not MISSIONPERSIST.fileExists(MISSIONPERSIST.catalogFile) then
        env.info("[PERSISTENCE] No catalog file found — fresh catalog will be saved at next periodic write.")
        return
    end
    local content = MISSIONPERSIST.readFile(MISSIONPERSIST.catalogFile)
    if not content then return end
    -- Temporarily stash current catalogs so the loadstring output lands in scratch tables.
    local prevGround = MISSIONPERSIST.RedGroundCatalog
    local prevAir    = MISSIONPERSIST.RedAirCatalog
    MISSIONPERSIST.RedGroundCatalog = {}
    MISSIONPERSIST.RedAirCatalog    = {}
    local chunk = loadstring(content)
    if chunk then
        local ok = pcall(chunk)
        if ok then
            local added = 0
            for k in pairs(MISSIONPERSIST.RedGroundCatalog) do
                if not prevGround[k] then prevGround[k] = true; added = added + 1 end
            end
            for k in pairs(MISSIONPERSIST.RedAirCatalog) do
                if not prevAir[k] then prevAir[k] = true; added = added + 1 end
            end
            if added > 0 then
                env.info(string.format("[PERSISTENCE] Catalog merge: added %d group(s) from saved file.", added))
            end
        end
    end
    -- Restore merged catalogs.
    MISSIONPERSIST.RedGroundCatalog = prevGround
    MISSIONPERSIST.RedAirCatalog    = prevAir
end

-- ============================================================
-- RED UNIT DEATH TRACKING
-- Tracks fully-destroyed RED ground groups so they stay dead
-- across mission restarts even when killed between periodic saves.
-- The dead-groups file is written IMMEDIATELY on each group wipe
-- (crash-safe — no 15-minute gap between death and disk flush).
-- ============================================================

-- Write RedDeadGroups to its own file immediately.
function MISSIONPERSIST.saveRedDeadGroups()
    local header = string.format("MISSIONPERSIST.RedDeadSaveVersion = %q\n", MISSIONPERSIST.SAVE_VERSION)
    local serialized = MISSIONPERSIST.serializeWithCycles("MISSIONPERSIST.RedDeadGroups", MISSIONPERSIST.RedDeadGroups)
    MISSIONPERSIST.writeFile(header .. serialized, MISSIONPERSIST.redDeadFile)
end

-- Load RedDeadGroups from file into MISSIONPERSIST.RedDeadGroups.
function MISSIONPERSIST.loadRedDeadGroups()
    if not MISSIONPERSIST.fileExists(MISSIONPERSIST.redDeadFile) then
        env.info("[PERSISTENCE] No dead-groups file found — fresh start.")
        MISSIONPERSIST.RedDeadGroups = {}
        return
    end
    local content = MISSIONPERSIST.readFile(MISSIONPERSIST.redDeadFile)
    if not content then
        env.warning("[PERSISTENCE] Failed to read dead-groups file.")
        MISSIONPERSIST.RedDeadGroups = {}
        return
    end
    local chunk = loadstring(content)
    if not chunk then
        env.warning("[PERSISTENCE] Dead-groups file parse error — ignoring.")
        MISSIONPERSIST.RedDeadGroups = {}
        return
    end
    local ok, err = pcall(chunk)
    if not ok then
        env.warning("[PERSISTENCE] Dead-groups file exec error: " .. tostring(err))
        MISSIONPERSIST.RedDeadGroups = {}
        return
    end
    if MISSIONPERSIST.RedDeadSaveVersion ~= MISSIONPERSIST.SAVE_VERSION then
        env.warning(string.format(
            "[PERSISTENCE] Dead-groups version mismatch: file '%s', expected '%s'. Restoring anyway.",
            tostring(MISSIONPERSIST.RedDeadSaveVersion), MISSIONPERSIST.SAVE_VERSION))
    end
    local count = 0
    for _ in pairs(MISSIONPERSIST.RedDeadGroups) do count = count + 1 end
    env.info(string.format("[PERSISTENCE] Loaded %d dead RED ground group(s) from file.", count))
end

-- ============================================================
-- RED AIR UNIT DEATH TRACKING
-- Mirrors the ground dead-group system but for RED air groups.
-- ============================================================

function MISSIONPERSIST.saveRedAirDeadGroups()
    local header = string.format("MISSIONPERSIST.RedAirDeadSaveVersion = %q\n", MISSIONPERSIST.SAVE_VERSION)
    local serialized = MISSIONPERSIST.serializeWithCycles("MISSIONPERSIST.RedAirDeadGroups", MISSIONPERSIST.RedAirDeadGroups)
    MISSIONPERSIST.writeFile(header .. serialized, MISSIONPERSIST.redAirDeadFile)
end

function MISSIONPERSIST.loadRedAirDeadGroups()
    if not MISSIONPERSIST.fileExists(MISSIONPERSIST.redAirDeadFile) then
        env.info("[PERSISTENCE] No dead air-groups file found — fresh start.")
        MISSIONPERSIST.RedAirDeadGroups = {}
        return
    end
    local content = MISSIONPERSIST.readFile(MISSIONPERSIST.redAirDeadFile)
    if not content then
        env.warning("[PERSISTENCE] Failed to read dead air-groups file.")
        MISSIONPERSIST.RedAirDeadGroups = {}
        return
    end
    local chunk = loadstring(content)
    if not chunk then
        env.warning("[PERSISTENCE] Dead air-groups file parse error — ignoring.")
        MISSIONPERSIST.RedAirDeadGroups = {}
        return
    end
    local ok, err = pcall(chunk)
    if not ok then
        env.warning("[PERSISTENCE] Dead air-groups file exec error: " .. tostring(err))
        MISSIONPERSIST.RedAirDeadGroups = {}
        return
    end
    if MISSIONPERSIST.RedAirDeadSaveVersion ~= MISSIONPERSIST.SAVE_VERSION then
        env.warning(string.format(
            "[PERSISTENCE] Dead air-groups version mismatch: file '%s', expected '%s'. Restoring anyway.",
            tostring(MISSIONPERSIST.RedAirDeadSaveVersion), MISSIONPERSIST.SAVE_VERSION))
    end
    local count = 0
    for _ in pairs(MISSIONPERSIST.RedAirDeadGroups) do count = count + 1 end
    env.info(string.format("[PERSISTENCE] Loaded %d dead RED air group(s) from file.", count))
end

-- Called during delayedRestore: finds every RED air group recorded as dead
-- and immediately destroys it so it doesn't stay alive from the mission .miz load.
function MISSIONPERSIST.destroyDeadAirGroups()
    local destroyed = 0
    for groupName, _ in pairs(MISSIONPERSIST.RedAirDeadGroups) do
        local grp = Group.getByName(groupName)
        if grp and grp:isExist() then
            pcall(function() grp:destroy() end)
            destroyed = destroyed + 1
            env.info("[PERSISTENCE] Destroyed previously-dead RED air group: " .. groupName)
        end
    end
    env.info(string.format("[PERSISTENCE] Destroyed %d previously-dead RED air group(s).", destroyed))
end

-- DCS event handler: fires on every unit death.
-- • Full ground-group wipe  → recorded in RedDeadGroups,    flushed to disk immediately.
-- • Full air-group wipe     → recorded in RedAirDeadGroups, flushed to disk immediately.
-- • Partial ground-group kill → debounced saveGroups() within 30 s so the
--   reduced unit count reaches disk without waiting for the 15-minute timer.
--
-- A 2-second delayed check is used instead of reading getSize() inline because
-- DCS may not have decremented the group size at the exact moment S_EVENT_DEAD
-- fires, causing the last-unit death to be missed.
MISSIONPERSIST._deathHandler = {}
function MISSIONPERSIST._deathHandler:onEvent(event)
    if event.id ~= world.event.S_EVENT_DEAD then return end
    local unit = event.initiator
    if not unit then return end
    pcall(function()
        -- Only track RED units.
        if unit:getCoalition() ~= coalition.side.RED then return end

        local desc = unit:getDesc()
        if not desc then return end
        local isGround = (desc.category == Unit.Category.GROUND_UNIT)
        local isAir    = (desc.category == Unit.Category.AIRPLANE or
                          desc.category == Unit.Category.HELICOPTER)
        if not isGround and not isAir then return end

        local grp = unit:getGroup()
        if not grp then return end
        local groupName = grp:getName()
        if MISSIONPERSIST.isExcludedGroup(groupName) then return end

        -- Schedule a 2-second delayed check so DCS has time to update group size.
        timer.scheduleFunction(function(args, _t)
            local gName   = args[1]
            local gIsGnd  = args[2]
            local gIsAir  = args[3]
            local g       = Group.getByName(gName)
            local isDead  = (not g) or (not g:isExist()) or (g:getSize() <= 0)

            if isDead then
                -- Full group wipe — record and flush to disk immediately.
                if gIsGnd and not MISSIONPERSIST.RedDeadGroups[gName] then
                    MISSIONPERSIST.RedDeadGroups[gName] = true
                    env.info("[PERSISTENCE] RED ground group fully destroyed: " .. gName)
                    pcall(MISSIONPERSIST.saveRedDeadGroups)
                elseif gIsAir and not MISSIONPERSIST.RedAirDeadGroups[gName] then
                    MISSIONPERSIST.RedAirDeadGroups[gName] = true
                    env.info("[PERSISTENCE] RED air group fully destroyed: " .. gName)
                    pcall(MISSIONPERSIST.saveRedAirDeadGroups)
                end
            elseif gIsGnd then
                -- Partial kill: schedule a debounced saveGroups() so the reduced
                -- unit count reaches disk quickly instead of waiting 15 minutes.
                if not MISSIONPERSIST._deferredGroupSavePending then
                    MISSIONPERSIST._deferredGroupSavePending = true
                    timer.scheduleFunction(function(_, _t2)
                        MISSIONPERSIST._deferredGroupSavePending = false
                        pcall(MISSIONPERSIST.saveGroups)
                        return nil  -- do not reschedule
                    end, {}, timer.getTime() + 30)
                end
            end
            return nil  -- do not reschedule the delayed check
        end, {groupName, isGround, isAir}, timer.getTime() + 2)
    end)
end

-- ============================================================
-- PERIODIC SAVE LOOP (every 15 minutes)
-- ============================================================

function MISSIONPERSIST.periodicSave()
    MISSIONPERSIST.saveGroups()
    MISSIONPERSIST.saveWarehouses()
    MISSIONPERSIST.saveCatalogs()

    -- Dead-group files: only write if new deaths occurred since the last periodic save.
    -- Immediate event-triggered saves still flush any full group wipe to disk right away
    -- (crash-safe); this check just avoids redundant disk writes during quiet periods.
    local deadGroundCount = 0
    for _ in pairs(MISSIONPERSIST.RedDeadGroups) do deadGroundCount = deadGroundCount + 1 end
    if deadGroundCount ~= MISSIONPERSIST._lastPeriodicDeadGroundCount then
        MISSIONPERSIST._lastPeriodicDeadGroundCount = deadGroundCount
        MISSIONPERSIST.saveRedDeadGroups()
    end

    local deadAirCount = 0
    for _ in pairs(MISSIONPERSIST.RedAirDeadGroups) do deadAirCount = deadAirCount + 1 end
    if deadAirCount ~= MISSIONPERSIST._lastPeriodicDeadAirCount then
        MISSIONPERSIST._lastPeriodicDeadAirCount = deadAirCount
        MISSIONPERSIST.saveRedAirDeadGroups()
    end

    return timer.getTime() + MISSIONPERSIST.saveInterval
end

-- ============================================================
-- INITIALIZATION
-- ============================================================

env.info(string.format("[PERSISTENCE] Loading Mission Persistence v%s (save format v%s)", version, MISSIONPERSIST.SAVE_VERSION))

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

-- Build RED group catalog from full MIST DB (incl. late-activate ground AND air groups).
-- Must run before loadAndMergeCatalogs() so the freshly-built catalog is ready to merge into.
MISSIONPERSIST.captureRedCatalogs()

-- Capture initial groups (ME-placed units to exclude from saves)
MISSIONPERSIST.captureInitialGroups()

-- Load saved state
MISSIONPERSIST.loadGroups()
MISSIONPERSIST.loadWarehouses()
MISSIONPERSIST.loadRedDeadGroups()
MISSIONPERSIST.loadRedAirDeadGroups()
MISSIONPERSIST.loadAndMergeCatalogs()  -- merge any extra groups saved in the prior session

-- Register RED death event handler (immediately tracks group wipes to disk)
world.addEventHandler(MISSIONPERSIST._deathHandler)

-- Delayed restoration (wait 15 seconds for mission stability)
local function delayedRestore()
    env.info("[PERSISTENCE] Applying saved state...")
    MISSIONPERSIST.restoreGroups()
    MISSIONPERSIST.restoreWarehouses()
    MISSIONPERSIST.destroyDeadAirGroups()  -- remove any RED air groups killed in a prior session
    env.info("[PERSISTENCE] Restoration complete, periodic saves active (every 15 minutes)")
    timer.scheduleFunction(MISSIONPERSIST.periodicSave, {}, timer.getTime() + MISSIONPERSIST.saveInterval)
end

timer.scheduleFunction(delayedRestore, {}, timer.getTime() + 15)