-- ============================================================================
-- SYRIA ISIS TARGET OF OPPORTUNITY (TOO) SYSTEM v1.0 - DCS WORLD LUA MISSION SCRIPT
-- ============================================================================
-- Spawns 30 random ISIS targets with dynamic units and static structures
-- Theatre: Syria | Enemy Faction: ISIS / Daesh
-- Features: Static buildings, radio menu with 9-line CAS briefs, auto-cleanup
-- Compatible with: DCS World 2.5+ and MIST.lua
-- ============================================================================

-- ============================================================================
-- DEPENDENCY CHECK
-- ============================================================================
local function checkDependencies()
    local missing = {}

    if not trigger then table.insert(missing, "trigger") end
    if not land then table.insert(missing, "land") end
    if not timer then table.insert(missing, "timer") end
    if not country then table.insert(missing, "country") end
    if not Group then table.insert(missing, "Group") end
    if not mist then table.insert(missing, "mist") end

    if #missing > 0 then
        env.info("[ISIS_TOO] ERROR: Missing required DCS APIs: " .. table.concat(missing, ", "))
        return false
    end

    return true
end

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
local TOO_CONFIG = {
    enabled = true,
    maintenanceCheckInterval = 1800,  -- 30 minutes
    minTargetsOnMap = 8,              -- Always maintain 8 active groups on map
    maxAttempts = 12,
}

-- Active targets tracking
local activeTargets = {}       -- Dictionary: groupName -> { name, zone, grid, heading }
local targetNames = {}         -- Array of active target names for radio menu
local targetMenuAdded = {}     -- Track which targets already have menu items
local staticObjectIds = {}     -- Dictionary: groupName -> { staticIds = {id1, id2, ...} }
local destroyedBuildings = {}  -- Dictionary: groupName -> count of destroyed static buildings
local zoneSpawnCount = {}      -- Tracks how many active spawns exist per zone
local currentTemplateIndex = 0 -- Track template rotation (0-indexed, cycles through 1-30)

-- ============================================================================
-- 30 TEMPLATES (ISIS / Syria Theatre)
-- ============================================================================

local TOO_TEMPLATES = {
    { name = "ISIS_Raqqa_Cell",
    buildings = {
        { type = "WC", offset = { x = -70, y = -65 } },
        { type = "Tent04", offset = { x = 75, y = 70 } },
        { type = "Tent05", offset = { x = -65, y = 75 } }
    },
    units = {
        { type = "Infantry AK Ins", offset = { x = -60, y = -50 } },
        { type = "Soldier AK", offset = { x = -70, y = -65 } },
        { type = "Soldier stinger", offset = { x = -50, y = -55 } },
        { type = "ZSU-23-4 Shilka", offset = { x = 55, y = 60 } },
        { type = "Soldier AK", offset = { x = 70, y = 75 } },
        { type = "Infantry AK Ins", offset = { x = 65, y = 55 } },
        { type = "Soldier RPG", offset = { x = -50, y = 70 } },
        { type = "P20_drivable", offset = { x = -60, y = 80 } },
        { type = "HL_DSHK", offset = { x = 60, y = -70 } }
    }
    },
    { name = "ISIS_Deir_Ez_Zor_Cell",
    buildings = {
        { type = "Tent05", offset = { x = -75, y = -70 } },
        { type = "WC", offset = { x = 80, y = 65 } },
        { type = "Building07_PBR", offset = { x = -70, y = 80 } },
        { type = "Building08_PBR", offset = { x = 75, y = -70 } }
    },
    units = {
        { type = "Soldier AK", offset = { x = -70, y = -60 } },
        { type = "Soldier stinger", offset = { x = -60, y = -70 } },
        { type = "Infantry AK Ins", offset = { x = -80, y = -55 } },
        { type = "ZSU-23-4 Shilka", offset = { x = 65, y = 70 } },
        { type = "Soldier AK", offset = { x = 80, y = 60 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 75 } },
        { type = "P20_drivable", offset = { x = -50, y = 75 } },
        { type = "HL_ZU-23", offset = { x = -60, y = 85 } },
        { type = "Grad-URAL", offset = { x = -70, y = 70 } },
        { type = "2B11 mortar", offset = { x = 55, y = -60 } },
        { type = "2B11 mortar", offset = { x = 70, y = -70 } },
        { type = "2B11 mortar", offset = { x = 60, y = -80 } },
        { type = "tt_ZU-23", offset = { x = 75, y = -55 } },
        { type = "Ural-4320T", offset = { x = -75, y = 70 } }
    }
    },
    { name = "ISIS_Palmyra_Fighters",
    buildings = {
        { type = "Tent04", offset = { x = 10, y = 10 } }
    },
    units = {
        { type = "Soldier AK", offset = { x = -60, y = -50 } },
        { type = "Infantry AK Ins", offset = { x = -55, y = -65 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -70, y = -55 } },
        { type = "Soldier stinger", offset = { x = 55, y = 60 } },
        { type = "Soldier AK", offset = { x = 70, y = 75 } },
        { type = "Infantry AK Ins", offset = { x = 65, y = 55 } },
        { type = "Soldier RPG", offset = { x = -55, y = 70 } },
        { type = "Soldier stinger", offset = { x = -65, y = 80 } },
        { type = "P20_drivable", offset = { x = 60, y = -65 } },
        { type = "Grad-URAL", offset = { x = 75, y = -75 } },
        { type = "HL_B8M1", offset = { x = 70, y = -55 } },
        { type = "Ural-4320T", offset = { x = -70, y = 65 } }
    }
    },
    { name = "ISIS_Homs_Garrison",
    buildings = {
        { type = "WC", offset = { x = -70, y = -60 } },
        { type = "Building08_PBR", offset = { x = 75, y = 70 } },
        { type = "Building07_PBR", offset = { x = -65, y = 75 } }
    },
    units = {
        { type = "Soldier AK", offset = { x = -60, y = -50 } },
        { type = "Infantry AK Ins", offset = { x = -75, y = -65 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -50, y = -70 } },
        { type = "Soldier stinger", offset = { x = 55, y = 55 } },
        { type = "Soldier AK", offset = { x = 70, y = 75 } },
        { type = "Infantry AK Ins", offset = { x = 80, y = 60 } },
        { type = "Soldier RPG", offset = { x = 60, y = 50 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -45, y = 65 } },
        { type = "P20_drivable", offset = { x = 60, y = -60 } },
        { type = "Grad-URAL", offset = { x = 75, y = -75 } },
        { type = "HL_ZU-23", offset = { x = 50, y = -65 } },
        { type = "tt_ZU-23", offset = { x = 70, y = -50 } },
        { type = "Ural-4320T", offset = { x = -75, y = 60 } },
        { type = "HL_B8M1", offset = { x = 55, y = -75 } }
    }
    },
    { name = "ISIS_Aleppo_Ambush",
    buildings = {
        { type = "Tent04", offset = { x = -75, y = -70 } },
        { type = "Building08_PBR", offset = { x = 80, y = 75 } },
        { type = "WC", offset = { x = -70, y = 80 } }
    },
    units = {
        { type = "Soldier AK", offset = { x = -60, y = -55 } },
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -50, y = -60 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "ZSU-23-4 Shilka", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 65 } },
        { type = "Soldier AK", offset = { x = -65, y = 75 } },
        { type = "Infantry AK Ins", offset = { x = -70, y = 60 } },
        { type = "P20_drivable", offset = { x = 55, y = -70 } },
        { type = "Grad-URAL", offset = { x = 70, y = -65 } },
        { type = "HL_DSHK", offset = { x = 65, y = -50 } },
        { type = "tt_ZU-23", offset = { x = 80, y = -75 } },
        { type = "Ural-4320T", offset = { x = 75, y = -55 } },
        { type = "HL_ZU-23", offset = { x = 60, y = -60 } }
    }
    },
    { name = "ISIS_Hama_Defense",
    buildings = {
        { type = "WC", offset = { x = -70, y = -60 } },
        { type = "Building08_PBR", offset = { x = 80, y = 70 } },
        { type = "Tent05", offset = { x = -75, y = 75 } },
        { type = "Building07_PBR", offset = { x = 65, y = -70 } }
    },
    units = {
        { type = "Infantry AK Ins", offset = { x = -60, y = -50 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -75, y = -65 } },
        { type = "Soldier stinger", offset = { x = -55, y = -70 } },
        { type = "Soldier AK", offset = { x = 60, y = 65 } },
        { type = "Infantry AK Ins", offset = { x = 75, y = 75 } },
        { type = "ZSU-23-4 Shilka", offset = { x = 70, y = 55 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },
        { type = "Soldier stinger", offset = { x = 65, y = -75 } },
        { type = "Soldier AK", offset = { x = 75, y = -55 } },
        { type = "Infantry AK Ins", offset = { x = -70, y = 55 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "Grad-URAL", offset = { x = 75, y = -75 } },
        { type = "LAZ Bus", offset = { x = -75, y = 55 } },
        { type = "HL_ZU-23", offset = { x = 70, y = -65 } },
        { type = "Ural-375 ZU-23 Insurgent", offset = { x = -60, y = 75 } }
    }
    },
    { name = "ISIS_Tabqa_Cache",
    buildings = {
        { type = "Tent05", offset = { x = -75, y = -70 } },
        { type = "Building07_PBR", offset = { x = 80, y = 75 } }
    },
    units = {
        { type = "Soldier AK", offset = { x = -60, y = -50 } },
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -50, y = -65 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },
        { type = "HQ-7_LN_SP", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "Soldier RPG", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "HQ-7_STR_SP", offset = { x = 55, y = -65 } },
        { type = "Soldier stinger", offset = { x = 70, y = -75 } },
        { type = "P20_drivable", offset = { x = 50, y = 50 } },
        { type = "Ural-4320T", offset = { x = 75, y = -60 } },
        { type = "Grad-URAL", offset = { x = 80, y = -75 } },
        { type = "HL_DSHK", offset = { x = -60, y = 75 } },
        { type = "tt_ZU-23", offset = { x = 70, y = -60 } },
        { type = "HL_ZU-23", offset = { x = -75, y = -65 } }
    }
    },
    { name = "ISIS_Mayadin_Checkpoint",
    buildings = {
        { type = "WC", offset = { x = -70, y = -60 } },
        { type = "Tent04", offset = { x = 80, y = 70 } },
        { type = "Tent04", offset = { x = -75, y = 75 } },
        { type = "Building08_PBR", offset = { x = 65, y = -70 } },
        { type = "Building08_PBR", offset = { x = 15, y = 15 } }
    },
    units = {
        { type = "Soldier AK", offset = { x = -60, y = -50 } },
        { type = "Infantry AK Ins", offset = { x = -75, y = -65 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -50, y = -60 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "ZSU-23-4 Shilka", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },
        { type = "Soldier stinger", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "Ural-4320T", offset = { x = 75, y = -75 } },
        { type = "Grad-URAL", offset = { x = -60, y = 75 } },
        { type = "HL_ZU-23", offset = { x = 70, y = -60 } },
        { type = "tt_ZU-23", offset = { x = -75, y = 60 } },
        { type = "HL_B8M1", offset = { x = 60, y = -70 } }
    }
    },
    { name = "ISIS_Al_Bab_Force",
    buildings = {
        { type = "Tent05", offset = { x = -75, y = -70 } },
        { type = "Building08_PBR", offset = { x = 80, y = 75 } }
    },
    units = {
        { type = "Infantry AK Ins", offset = { x = -60, y = -55 } },
        { type = "Soldier AK", offset = { x = -75, y = -70 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -50, y = -60 } },
        { type = "Soldier stinger", offset = { x = 60, y = 60 } },
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "ZSU-23-4 Shilka", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 75 } },
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -60, y = 65 } },
        { type = "Soldier RPG", offset = { x = 55, y = -70 } },
        { type = "Soldier stinger", offset = { x = 70, y = -75 } },
        { type = "P20_drivable", offset = { x = 50, y = 55 } },
        { type = "Ural-4320T", offset = { x = 75, y = -75 } },
        { type = "Grad-URAL", offset = { x = 80, y = -65 } },
        { type = "HL_DSHK", offset = { x = -75, y = 60 } },
        { type = "tt_ZU-23", offset = { x = 70, y = -55 } },
        { type = "HL_ZU-23", offset = { x = -60, y = -75 } }
    }
    },
    { name = "ISIS_Kobane_Patrol",
    buildings = {
        { type = "Tent04", offset = { x = -75, y = -70 } },
        { type = "Building07_PBR", offset = { x = 80, y = 75 } }
    },
    units = {
        { type = "Soldier AK", offset = { x = -60, y = -55 } },
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -50, y = -65 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "ZSU-23-4 Shilka", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },
        { type = "Soldier stinger", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "Ural-4320T", offset = { x = 75, y = -75 } },
        { type = "Grad-URAL", offset = { x = 80, y = -65 } },
        { type = "HL_ZU-23", offset = { x = -75, y = 60 } },
        { type = "tt_ZU-23", offset = { x = -60, y = -70 } }
    }
    },
    { name = "ISIS_Abu_Kamal_Trap",
    buildings = {
        { type = "Tent04", offset = { x = -75, y = -70 } },
        { type = "WC", offset = { x = 80, y = 75 } },
        { type = "Tent04", offset = { x = -70, y = 80 } }
    },
    units = {
        { type = "Infantry AK Ins", offset = { x = -60, y = -50 } },
        { type = "Soldier AK", offset = { x = -75, y = -65 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -50, y = -70 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },
        { type = "Infantry AK Ins", offset = { x = 75, y = 80 } },
        { type = "Soldier AK", offset = { x = 70, y = 55 } },
        { type = "ZSU-23-4 Shilka", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier RPG", offset = { x = 55, y = -70 } },
        { type = "P20_drivable", offset = { x = -60, y = 75 } },
        { type = "Grad-URAL", offset = { x = 70, y = -75 } },
        { type = "HL_DSHK", offset = { x = -75, y = -65 } },
        { type = "tt_ZU-23", offset = { x = 65, y = -60 } }
    }
    },
    { name = "ISIS_Maskanah_Village",
    buildings = {
        { type = "WC", offset = { x = -75, y = -70 } },
        { type = "Tent05", offset = { x = 80, y = 75 } }
    },
    units = {
        { type = "HQ-7_LN_SP", offset = { x = -60, y = -50 } },
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } },
        { type = "Soldier stinger", offset = { x = -50, y = -65 } },
        { type = "ZSU-23-4 Shilka", offset = { x = 60, y = 65 } },
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "Soldier stinger", offset = { x = 65, y = 75 } },
        { type = "Soldier RPG", offset = { x = -55, y = 70 } },
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier stinger", offset = { x = 50, y = -60 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "Ural-4320T", offset = { x = 75, y = -75 } },
        { type = "Grad-URAL", offset = { x = -75, y = 60 } },
        { type = "HL_ZU-23", offset = { x = 70, y = -65 } },
        { type = "tt_ZU-23", offset = { x = -60, y = 75 } },
        { type = "HQ-7_STR_SP", offset = { x = 60, y = -70 } }
    }
    },
    { name = "ISIS_Sukhnah_Desert_Pos",
    buildings = {
        { type = "WC", offset = { x = -75, y = -70 } },
        { type = "Tent04", offset = { x = 80, y = 75 } },
        { type = "Building08_PBR", offset = { x = -70, y = 80 } }
    },
    units = {
        { type = "Infantry AK Ins", offset = { x = -60, y = -50 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -75, y = -70 } },
        { type = "Soldier AK", offset = { x = -50, y = -65 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },
        { type = "Infantry AK Ins", offset = { x = 75, y = 80 } },
        { type = "ZSU-23-4 Shilka", offset = { x = 70, y = 55 } },
        { type = "Soldier AK", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },
        { type = "Infantry AK Ins", offset = { x = -70, y = 80 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "HL_DSHK", offset = { x = 75, y = -75 } },
        { type = "Grad-URAL", offset = { x = -75, y = 60 } },
        { type = "tt_ZU-23", offset = { x = 70, y = -65 } },
        { type = "Ural-4320T", offset = { x = -60, y = -70 } }
    }
    },
    { name = "ISIS_Tel_Abyad_Command",
    buildings = {
        { type = "Tent04", offset = { x = -75, y = -70 } },
        { type = "Building08_PBR", offset = { x = 80, y = 75 } }
    },
    units = {
        { type = "Soldier AK", offset = { x = -60, y = -50 } },
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -50, y = -65 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "ZSU-23-4 Shilka", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },
        { type = "P20_drivable", offset = { x = -60, y = 75 } },
        { type = "Ural-4320T", offset = { x = 70, y = -75 } },
        { type = "Grad-URAL", offset = { x = 75, y = -65 } },
        { type = "HL_B8M1", offset = { x = -75, y = 60 } },
        { type = "tt_ZU-23", offset = { x = 65, y = -60 } },
        { type = "HQ-7_LN_SP", offset = { x = -60, y = -70 } }
    }
    },
    { name = "ISIS_Shayrat_Stronghold",
    buildings = {
        { type = "WC", offset = { x = -70, y = -60 } },
        { type = "Tent04", offset = { x = 80, y = 70 } },
        { type = "Tent04", offset = { x = -75, y = 75 } },
        { type = "Building07_PBR", offset = { x = 65, y = -70 } }
    },
    units = {
        { type = "Infantry AK Ins", offset = { x = -60, y = -50 } },
        { type = "Soldier AK", offset = { x = -75, y = -65 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -50, y = -70 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },
        { type = "Infantry AK Ins", offset = { x = 75, y = 80 } },
        { type = "Soldier AK", offset = { x = 70, y = 55 } },
        { type = "ZSU-23-4 Shilka", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "Grad-URAL", offset = { x = 75, y = -75 } },
        { type = "HL_ZU-23", offset = { x = -75, y = 60 } }
    }
    },
    { name = "ISIS_Tiyas_Outpost",
    buildings = {
        { type = "Tent04", offset = { x = -75, y = -70 } },
        { type = "Tent05", offset = { x = 80, y = 75 } },
        { type = "WC", offset = { x = -70, y = 80 } }
    },
    units = {
        { type = "Soldier AK", offset = { x = -60, y = -55 } },
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } },
        { type = "Soldier stinger", offset = { x = -50, y = -65 } },
        { type = "ZSU-23-4 Shilka", offset = { x = 60, y = 60 } },
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "Soldier stinger", offset = { x = 65, y = 75 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -55, y = 75 } },
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -60, y = 65 } },
        { type = "Soldier stinger", offset = { x = 50, y = -60 } },
        { type = "Soldier RPG", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "HL_DSHK", offset = { x = 75, y = -75 } },
        { type = "tt_ZU-23", offset = { x = -75, y = 60 } },
        { type = "Grad-URAL", offset = { x = 70, y = -60 } },
        { type = "Ural-4320T", offset = { x = -60, y = -70 } }
    }
    },
    { name = "ISIS_Qaryatayn_Guard",
    buildings = {
        { type = "Tent04", offset = { x = -70, y = -60 } },
        { type = "Building07_PBR", offset = { x = 80, y = 75 } },
        { type = "Building08_PBR", offset = { x = -75, y = 80 } },
        { type = "Tent05", offset = { x = 65, y = -70 } },
        { type = "WC", offset = { x = 55, y = 60 } }
    },
    units = {
        { type = "Infantry AK Ins", offset = { x = -60, y = -50 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -75, y = -65 } },
        { type = "Soldier AK", offset = { x = -50, y = -70 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },
        { type = "Infantry AK Ins", offset = { x = 75, y = 80 } },
        { type = "ZSU-23-4 Shilka", offset = { x = 70, y = 55 } },
        { type = "Soldier AK", offset = { x = 65, y = 75 } },
        { type = "HQ-7_LN_SP", offset = { x = -55, y = 70 } },
        { type = "Infantry AK Ins", offset = { x = -70, y = 80 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "Grad-URAL", offset = { x = 75, y = -75 } },
        { type = "HL_ZU-23", offset = { x = -75, y = 60 } },
        { type = "tt_ZU-23", offset = { x = 70, y = -65 } },
        { type = "Ural-4320T", offset = { x = -60, y = -70 } },
        { type = "HQ-7_STR_SP", offset = { x = 60, y = 70 } }
    }
    },
    { name = "ISIS_Al_Hawl_Squad",
    buildings = {
        { type = "Building08_PBR", offset = { x = -75, y = -70 } },
        { type = "Building08_PBR", offset = { x = 80, y = 75 } }
    },
    units = {
        { type = "Soldier AK", offset = { x = -60, y = -55 } },
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -50, y = -65 } },
        { type = "Soldier stinger", offset = { x = 60, y = 60 } },
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "ZSU-23-4 Shilka", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 75 } },
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -60, y = 65 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },
        { type = "Soldier stinger", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = -60, y = 75 } },
        { type = "Grad-URAL", offset = { x = 70, y = -75 } },
        { type = "HL_B8M1", offset = { x = 75, y = -65 } },
        { type = "Ural-4320T", offset = { x = -75, y = 60 } }
    }
    },
    { name = "ISIS_Jarabulus_Fighters",
    buildings = {
        { type = "WC", offset = { x = -75, y = -70 } },
        { type = "Tent05", offset = { x = 80, y = 75 } },
        { type = "Tent04", offset = { x = -70, y = 80 } }
    },
    units = {
        { type = "Infantry AK Ins", offset = { x = -60, y = -50 } },
        { type = "Soldier AK", offset = { x = -75, y = -70 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -50, y = -70 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },
        { type = "Infantry AK Ins", offset = { x = 75, y = 80 } },
        { type = "HQ-7_STR_SP", offset = { x = 70, y = 55 } },
        { type = "ZSU-23-4 Shilka", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },
        { type = "HQ-7_LN_SP", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "Grad-URAL", offset = { x = 75, y = -75 } },
        { type = "HL_DSHK", offset = { x = -75, y = 60 } },
        { type = "tt_ZU-23", offset = { x = 70, y = -65 } },
        { type = "Ural-4320T", offset = { x = -60, y = -70 } }
    }
    },
    { name = "ISIS_Manbij_Ambush",
    buildings = {
        { type = "Building07_PBR", offset = { x = -70, y = -60 } },
        { type = "WC", offset = { x = 80, y = 70 } },
        { type = "Tent04", offset = { x = -75, y = 75 } },
        { type = "Building08_PBR", offset = { x = 65, y = -70 } }
    },
    units = {
        { type = "Soldier AK", offset = { x = -60, y = -50 } },
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } },
        { type = "Soldier stinger", offset = { x = -50, y = -70 } },
        { type = "HQ-7_LN_SP", offset = { x = 60, y = 65 } },
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "Soldier stinger", offset = { x = 65, y = 75 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -55, y = 70 } },
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier stinger", offset = { x = 50, y = -60 } },
        { type = "P20_drivable", offset = { x = -60, y = 75 } },
        { type = "Grad-URAL", offset = { x = 70, y = -75 } },
        { type = "HL_ZU-23", offset = { x = 75, y = -65 } },
        { type = "tt_ZU-23", offset = { x = -75, y = 60 } },
        { type = "HQ-7_STR_SP", offset = { x = 65, y = -60 } }
    }
    },
    { name = "ISIS_Ash_Shaddadi_Crew",
    buildings = {
        { type = "Building08_PBR", offset = { x = -75, y = -70 } },
        { type = "Tent04", offset = { x = 80, y = 75 } },
        { type = "WC", offset = { x = -70, y = 80 } }
    },
    units = {
        { type = "Infantry AK Ins", offset = { x = -60, y = -55 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -75, y = -70 } },
        { type = "Soldier AK", offset = { x = -50, y = -65 } },
        { type = "Soldier stinger", offset = { x = 60, y = 60 } },
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "ZSU-23-4 Shilka", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 75 } },
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -60, y = 65 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },
        { type = "Soldier stinger", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "Grad-URAL", offset = { x = 75, y = -75 } },
        { type = "HL_B8M1", offset = { x = -75, y = 60 } },
        { type = "Ural-4320T", offset = { x = 70, y = -65 } },
        { type = "tt_ZU-23", offset = { x = -60, y = -70 } }
    }
    },
    { name = "ISIS_Hasakah_Cache",
    buildings = {
        { type = "WC", offset = { x = -70, y = -60 } },
        { type = "Building08_PBR", offset = { x = 80, y = 70 } },
        { type = "Building08_PBR", offset = { x = -75, y = 75 } },
        { type = "Tent05", offset = { x = 65, y = -70 } }
    },
    units = {
        { type = "Soldier AK", offset = { x = -60, y = -50 } },
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } },
        { type = "Soldier stinger", offset = { x = -50, y = -70 } },
        { type = "ZSU-23-4 Shilka", offset = { x = 60, y = 65 } },
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "Soldier stinger", offset = { x = 65, y = 75 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -55, y = 70 } },
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier stinger", offset = { x = 50, y = -60 } },
        { type = "Soldier RPG", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = -60, y = 75 } },
        { type = "Grad-URAL", offset = { x = 70, y = -75 } },
        { type = "HL_DSHK", offset = { x = 75, y = -65 } },
        { type = "Ural-4320T", offset = { x = -75, y = 60 } },
        { type = "tt_ZU-23", offset = { x = 60, y = -70 } }
    }
    },
    { name = "ISIS_Raqqa_North_Support",
    buildings = {
        { type = "Tent05", offset = { x = -75, y = -70 } },
        { type = "WC", offset = { x = 80, y = 75 } }
    },
    units = {
        { type = "Infantry AK Ins", offset = { x = -60, y = -50 } },
        { type = "Soldier AK", offset = { x = -75, y = -70 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -50, y = -70 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "ZSU-23-4 Shilka", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },
        { type = "HQ-7_LN_SP", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "Grad-URAL", offset = { x = 75, y = -75 } },
        { type = "HL_ZU-23", offset = { x = -75, y = 60 } },
        { type = "tt_ZU-23", offset = { x = 70, y = -65 } },
        { type = "HQ-7_STR_SP", offset = { x = -60, y = -70 } }
    }
    },
    { name = "ISIS_Deir_Ez_Zor_Rear",
    buildings = {
        { type = "Building08_PBR", offset = { x = -75, y = -70 } },
        { type = "Building07_PBR", offset = { x = 80, y = 75 } },
        { type = "Tent04", offset = { x = -70, y = 80 } }
    },
    units = {
        { type = "Soldier AK", offset = { x = -60, y = -55 } },
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -50, y = -65 } },
        { type = "Soldier stinger", offset = { x = 60, y = 60 } },
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "ZSU-23-4 Shilka", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 75 } },
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -60, y = 65 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },
        { type = "Soldier stinger", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "Ural-4320T", offset = { x = 75, y = -75 } },
        { type = "Grad-URAL", offset = { x = -75, y = 60 } },
        { type = "HL_B8M1", offset = { x = 70, y = -65 } },
        { type = "HQ-7_LN_SP", offset = { x = -60, y = -70 } }
    }
    },
    { name = "ISIS_Palmyra_Sabotage",
    buildings = {
        { type = "Tent04", offset = { x = -75, y = -70 } },
        { type = "Building08_PBR", offset = { x = 80, y = 75 } }
    },
    units = {
        { type = "Infantry AK Ins", offset = { x = -60, y = -50 } },
        { type = "Soldier AK", offset = { x = -75, y = -70 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -50, y = -70 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },
        { type = "Infantry AK Ins", offset = { x = 75, y = 80 } },
        { type = "Soldier AK", offset = { x = 70, y = 55 } },
        { type = "ZSU-23-4 Shilka", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },
        { type = "Soldier stinger", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "Grad-URAL", offset = { x = 75, y = -75 } },
        { type = "HL_DSHK", offset = { x = -75, y = 60 } },
        { type = "Ural-4320T", offset = { x = 70, y = -65 } },
        { type = "tt_ZU-23", offset = { x = -60, y = -70 } }
    }
    },
    { name = "ISIS_Albu_Kamal_Battle",
    buildings = {
        { type = "WC", offset = { x = -70, y = -60 } },
        { type = "Tent05", offset = { x = 80, y = 70 } },
        { type = "Tent04", offset = { x = -75, y = 75 } },
        { type = "Building07_PBR", offset = { x = 65, y = -70 } },
        { type = "Building08_PBR", offset = { x = 55, y = 60 } }
    },
    units = {
        { type = "Soldier AK", offset = { x = -60, y = -50 } },
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } },
        { type = "Soldier stinger", offset = { x = -50, y = -70 } },
        { type = "ZSU-23-4 Shilka", offset = { x = 60, y = 65 } },
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "HQ-7_LN_SP", offset = { x = 65, y = 75 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -55, y = 70 } },
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier stinger", offset = { x = 50, y = -60 } },
        { type = "P20_drivable", offset = { x = -60, y = 75 } },
        { type = "Grad-URAL", offset = { x = 70, y = -75 } },
        { type = "HL_ZU-23", offset = { x = 75, y = -65 } },
        { type = "Ural-4320T", offset = { x = -75, y = 60 } },
        { type = "tt_ZU-23", offset = { x = 70, y = -65 } },
        { type = "HQ-7_STR_SP", offset = { x = -60, y = -70 } }
    }
    },
    { name = "ISIS_Raqqa_South_Fortress",
    buildings = {
        { type = "Building08_PBR", offset = { x = -75, y = -70 } },
        { type = "Building07_PBR", offset = { x = 80, y = 75 } },
        { type = "WC", offset = { x = -70, y = 80 } },
        { type = "Tent05", offset = { x = 65, y = -70 } }
    },
    units = {
        { type = "Infantry AK Ins", offset = { x = -60, y = -50 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -75, y = -70 } },
        { type = "Soldier AK", offset = { x = -50, y = -70 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },
        { type = "Infantry AK Ins", offset = { x = 75, y = 80 } },
        { type = "ZSU-23-4 Shilka", offset = { x = 70, y = 55 } },
        { type = "Soldier AK", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },
        { type = "Infantry AK Ins", offset = { x = -70, y = 80 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },
        { type = "Soldier AK", offset = { x = -12, y = 6 } },
        { type = "Soldier stinger", offset = { x = 8, y = 14 } },
        { type = "P20_drivable", offset = { x = 14, y = 12 } },
        { type = "Grad-URAL", offset = { x = 24, y = 10 } },
        { type = "HL_B8M1", offset = { x = 18, y = -14 } },
        { type = "Ural-4320T", offset = { x = 20, y = 14 } },
        { type = "tt_ZU-23", offset = { x = -8, y = -14 } }
    }
    },
    { name = "ISIS_Homs_Defense",
    buildings = {
        { type = "WC", offset = { x = -75, y = -70 } },
        { type = "Tent05", offset = { x = 80, y = 75 } },
        { type = "Tent04", offset = { x = -70, y = 80 } }
    },
    units = {
        { type = "Soldier AK", offset = { x = -60, y = -55 } },
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -50, y = -65 } },
        { type = "Soldier stinger", offset = { x = 60, y = 60 } },
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "HQ-7_LN_SP", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 75 } },
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -60, y = 65 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },
        { type = "Soldier stinger", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "Ural-4320T", offset = { x = 75, y = -75 } },
        { type = "Grad-URAL", offset = { x = -75, y = 60 } },
        { type = "HL_DSHK", offset = { x = 70, y = -65 } },
        { type = "HQ-7_STR_SP", offset = { x = -60, y = -70 } }
    }
    },
    { name = "ISIS_Bukamal_Garrison",
    buildings = {
        { type = "Building08_PBR", offset = { x = -75, y = -70 } },
        { type = "Tent04", offset = { x = 80, y = 75 } }
    },
    units = {
        { type = "Infantry AK Ins", offset = { x = -60, y = -50 } },
        { type = "Soldier AK", offset = { x = -75, y = -70 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -50, y = -70 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "ZSU-23-4 Shilka", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },
        { type = "Soldier stinger", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "Grad-URAL", offset = { x = 75, y = -75 } },
        { type = "HL_ZU-23", offset = { x = -75, y = 60 } },
        { type = "Ural-4320T", offset = { x = 70, y = -65 } },
        { type = "tt_ZU-23", offset = { x = -60, y = -70 } },
        { type = "HQ-7_LN_SP", offset = { x = 60, y = -70 } }
    }
    },
    { name = "ISIS_Hasakah_Operations",
    buildings = {
        { type = "WC", offset = { x = -75, y = -70 } },
        { type = "Building08_PBR", offset = { x = 80, y = 75 } }
    },
    units = {
        { type = "Soldier AK", offset = { x = -60, y = -55 } },
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } },
        { type = "ZSU-23-4 Shilka", offset = { x = -50, y = -65 } },
        { type = "Soldier stinger", offset = { x = 60, y = 60 } },
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "ZSU-23-4 Shilka", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 75 } },
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -60, y = 65 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },
        { type = "Soldier stinger", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "Grad-URAL", offset = { x = 75, y = -75 } },
        { type = "HL_ZU-23", offset = { x = -75, y = 60 } },
        { type = "tt_ZU-23", offset = { x = 70, y = -65 } }
    }
    }
}

-- ============================================================================
-- SPAWN ZONES (Dynamic Discovery)
-- Zones are discovered at mission start by scanning for names matching
-- the prefix "TOOZONE_" followed by a number (e.g. TOOZONE_1, TOOZONE_2 ...).
-- Add as many or as few zones as you need in the Mission Editor - the script
-- will find them automatically up to ZONE_SCAN_MAX.
-- ============================================================================
local ZONE_PREFIX        = "TOOZONE_"   -- Prefix used for all TOO spawn zones in ME
local ZONE_SCAN_MAX      = 20           -- Maximum zone number to scan for
local MIN_SPAWNS_PER_ZONE = 1           -- Minimum templates to spawn in each zone
local MAX_SPAWNS_PER_ZONE = 3           -- Maximum templates to spawn in each zone
local MAX_TOTAL_GROUPS    = 30          -- Hard ceiling: no more than this many groups alive at once
local TOO_ZONES          = {}           -- Populated at init by discoverTOOZones()

local function discoverTOOZones()
    TOO_ZONES = {}
    for i = 1, ZONE_SCAN_MAX do
        local zoneName = ZONE_PREFIX .. i
        if trigger.misc.getZone(zoneName) then
            table.insert(TOO_ZONES, zoneName)
        end
    end
    env.info("[ISIS_TOO] Zone discovery complete: found " .. #TOO_ZONES .. " zones with prefix '" .. ZONE_PREFIX .. "'")
    if #TOO_ZONES == 0 then
        env.info("[ISIS_TOO] WARNING: No zones found! Make sure zones are named " .. ZONE_PREFIX .. "1, " .. ZONE_PREFIX .. "2, etc. in the Mission Editor.")
    end
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function getRandomElement(array)
    if not array or #array == 0 then return nil end
    return array[math.random(1, #array)]
end

local function randomRange(min, max)
    return math.random(min, max)
end

local function getGridReference(pos)
    if not pos then return "UNKNOWN" end
    local x = math.floor(pos.x / 1000)
    local y = math.floor(pos.y / 1000)
    return string.format("%02d%02d", x % 100, y % 100)
end

local function getZonePosition(zoneName)
    local zone = trigger.misc.getZone(zoneName)
    if zone then
        return { x = zone.x, y = 0, z = zone.y }
    end
    return nil
end

local function convertToNEDM(pos)
    if not pos then return "UNKNOWN" end

    local lat = 40 + (pos.z / 111000)
    local lon = 10 + (pos.x / 111000)

    local lat_deg = math.floor(lat)
    local lat_min_dec = (lat - lat_deg) * 60
    local lat_min = math.floor(lat_min_dec)
    local lat_sec = (lat_min_dec - lat_min) * 60

    local lon_deg = math.floor(lon)
    local lon_min_dec = (lon - lon_deg) * 60
    local lon_min = math.floor(lon_min_dec)
    local lon_sec = (lon_min_dec - lon_min) * 60

    local lat_dir = lat >= 0 and "N" or "S"
    local lon_dir = lon >= 0 and "E" or "W"

    return string.format("%s%02d°%02d'%05.2f\" %s%03d°%02d'%05.2f\"",
        lat_dir, math.abs(lat_deg), math.abs(lat_min), math.abs(lat_sec),
        lon_dir, math.abs(lon_deg), math.abs(lon_min), math.abs(lon_sec))
end

local function convertToMGRS(pos)
    if not pos then return "UNKNOWN" end

    local x = math.floor(pos.x / 1000)
    local z = math.floor(pos.z / 1000)

    local grid_letter1 = string.char(65 + ((x / 100) % 26))
    local grid_letter2 = string.char(65 + ((z / 100) % 26))

    local easting  = string.format("%05d", x % 100000)
    local northing = string.format("%05d", z % 100000)

    return "37S" .. grid_letter1 .. grid_letter2 .. easting .. northing
end

-- ============================================================================
-- SPAWN FUNCTIONS
-- ============================================================================

local function getRandomPositionInZone(zoneName)
    local zone = trigger.misc.getZone(zoneName)
    if not zone then return nil end

    local center2d = { x = zone.point.x, y = zone.point.z }
    local radius = zone.radius or 500

    local r = radius * math.sqrt(math.random())
    local angle = math.random() * 2 * math.pi

    local pos2d = {
        x = center2d.x + r * math.cos(angle),
        y = center2d.y + r * math.sin(angle),
    }

    env.info("[ISIS_TOO DEBUG] Zone: " .. zoneName .. " | Radius: " .. radius .. "m | Spawn distance from center: " .. math.floor(r) .. "m")

    return pos2d
end

-- ============================================================================
-- HELPER FUNCTIONS FOR MARKERS
-- ============================================================================

local function toVec3Ground(pos2d)
    if not pos2d then
        return { x = 0, y = 100, z = 0 }
    end

    local alt = 0
    if land and land.getHeight then
        alt = land.getHeight({ x = pos2d.x, y = pos2d.y })
        if alt then
            alt = math.max(0, alt)
        else
            alt = 100
        end
    else
        alt = 100
    end

    return { x = pos2d.x, y = alt, z = pos2d.y }
end

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

-- ============================================================================
-- MARKER MANAGER
-- ============================================================================

local markerManager = {
    active  = {},
    mainPath = nil,
    tgtInfoPath = nil,
}

local function placeMarker(groupName, markerText, pos2d)
    if not pos2d or not groupName then
        env.info("[ISIS_TOO] ERROR: placeMarker called with invalid parameters")
        return false
    end

    if not trigger or not trigger.action or not trigger.action.markToAll then
        env.info("[ISIS_TOO] ERROR: trigger.action.markToAll not available")
        return false
    end

    if markerManager.active[groupName] then
        local oldMarkerId = markerManager.active[groupName]
        pcall(function()
            trigger.action.removeMark(oldMarkerId)
            env.info("[ISIS_TOO] DEBUG: Removed old marker ID " .. oldMarkerId .. " for group " .. groupName)
        end)
    end

    local p3 = toVec3Ground(pos2d)

    local group = Group.getByName(groupName)
    local groupInfo = ""
    if group and group:getUnits() and #group:getUnits() > 0 then
        local unit = group:getUnits()[1]
        local unitPos = unit:getPosition().p
        groupInfo = " | First Unit at: x=" .. math.floor(unitPos.x) .. " y=" .. math.floor(unitPos.y) .. " z=" .. math.floor(unitPos.z)
    end

    local markerId = math.random(10000, 99999)
    local fullMarkerText = "[ISIS] " .. markerText

    local success = pcall(function()
        env.info("[ISIS_TOO] DEBUG: Placing marker ID " .. markerId .. " at x=" .. tostring(p3.x) .. " y=" .. tostring(p3.y) .. " z=" .. tostring(p3.z) .. groupInfo)
        trigger.action.markToAll(markerId, fullMarkerText, p3, false)
    end)

    if success then
        markerManager.active[groupName] = markerId
        env.info("[ISIS_TOO] SUCCESS: Marker placed - ID:" .. markerId .. " Text:" .. fullMarkerText)
        return true
    else
        env.info("[ISIS_TOO] ERROR: Failed to place marker for " .. groupName)
        return false
    end
end

local function markerManagerCleanup()
    local toRemove = {}

    for groupName, markerId in pairs(markerManager.active) do
        if isGroupDead(groupName) then
            local success = pcall(function()
                trigger.action.removeMark(markerId)
            end)
            if success then
                env.info("[ISIS_TOO] MARKER REMOVED: ID " .. markerId .. " for dead group " .. groupName)
            end
            table.insert(toRemove, groupName)
        end
    end

    for _, groupName in ipairs(toRemove) do
        markerManager.active[groupName] = nil
    end

    if #toRemove > 0 then
        env.info("[ISIS_TOO] Marker cleanup: Removed " .. #toRemove .. " markers for dead groups")
    end
end

local function cleanupPlayerMenus()
    local toRemove = {}

    for groupId, menuData in pairs(TOO_PLAYER_MENUS) do
        local groupExists = false
        local coalitionBlue = coalition.getGroups(coalition.side.BLUE)
        if coalitionBlue then
            for _, group in ipairs(coalitionBlue) do
                if group and group:isExist() and group:getID() == groupId then
                    groupExists = true
                    break
                end
            end
        end

        if not groupExists then
            table.insert(toRemove, groupId)
        end
    end

    for _, groupId in ipairs(toRemove) do
        TOO_PLAYER_MENUS[groupId] = nil
    end

    if #toRemove > 0 then
        env.info("[ISIS_TOO] Menu cleanup: Cleared tracking for " .. #toRemove .. " disconnected players")
    end
end

-- ============================================================================
-- SPAWN FUNCTIONS
-- ============================================================================

local function spawnTargetOfOpportunity(forcedZone)
    if not TOO_CONFIG.enabled then
        return
    end

    -- Global group cap: never exceed MAX_TOTAL_GROUPS regardless of per-zone settings
    local totalActive = 0
    for _ in pairs(activeTargets) do totalActive = totalActive + 1 end
    if totalActive >= MAX_TOTAL_GROUPS then
        env.info("[ISIS_TOO] Global cap reached (" .. totalActive .. "/" .. MAX_TOTAL_GROUPS .. ") – spawn suppressed")
        return
    end

    local zoneName
    if forcedZone then
        zoneName = forcedZone
    else
        local availableZones = {}
        for _, zone in ipairs(TOO_ZONES) do
            if (zoneSpawnCount[zone] or 0) < MAX_SPAWNS_PER_ZONE then
                table.insert(availableZones, zone)
            end
        end

        if #availableZones == 0 then
            env.info("[ISIS_TOO] No available zones - all at max capacity (" .. MAX_SPAWNS_PER_ZONE .. " per zone)")
            return
        end

        zoneName = getRandomElement(availableZones)
    end

    currentTemplateIndex = currentTemplateIndex + 1
    if currentTemplateIndex > #TOO_TEMPLATES then
        currentTemplateIndex = 1
    end

    local template = TOO_TEMPLATES[currentTemplateIndex]

    if not template or not zoneName then
        env.info("[ISIS_TOO] ERROR: Invalid template or zone")
        return
    end

    local MAX_ATTEMPTS = 5
    local spawnSuccess = false
    local finalGroupName = nil
    local finalPos2d = nil

    for attempt = 1, MAX_ATTEMPTS do
        local zonePos = getRandomPositionInZone(zoneName)
        if not zonePos then
            env.info("[ISIS_TOO] Attempt " .. attempt .. ": Zone position failed for " .. zoneName)
        else
            -- Water check: reject any point that lands on water and retry
            local surfaceType = land.getSurfaceType({ x = zonePos.x, y = zonePos.y })
            if surfaceType == land.SurfaceType.WATER then
                env.info("[ISIS_TOO] Attempt " .. attempt .. ": Position is on water in zone " .. zoneName .. " - retrying")
            else
            local heading = randomRange(0, 360)
            local staticIds = {}

            if template.buildings then
                for idx, building in ipairs(template.buildings) do
                    local staticX = zonePos.x + building.offset.x
                    local staticZ = zonePos.y + building.offset.y
                    local staticName = template.name .. "_static_" .. idx .. "_" .. attempt

                    env.info("[ISIS_TOO] DEBUG: Attempting to spawn static " .. building.type .. " at x=" .. math.floor(staticX) .. " z=" .. math.floor(staticZ))

                    local success, result = pcall(function()
                        local alt = land.getHeight({x = staticX, y = staticZ}) or 0
                        alt = math.max(0, alt)

                        if mist and mist.dynAddStatic then
                            local staticData = {
                                type = building.type,
                                country = country.id.CJTF_RED,
                                x = staticX,
                                y = staticZ,
                                name = staticName,
                                heading = 0,
                                category = "Fortifications",
                            }

                            local addResult = mist.dynAddStatic(staticData)

                            if addResult and addResult.name then
                                env.info("[ISIS_TOO] SUCCESS: Static " .. building.type .. " added via MIST")
                                return addResult.name
                            else
                                env.info("[ISIS_TOO] WARNING: mist.dynAddStatic returned nil for " .. building.type)
                                return nil
                            end
                        else
                            env.info("[ISIS_TOO] ERROR: mist.dynAddStatic not available")
                            return nil
                        end
                    end)

                    if success and result then
                        table.insert(staticIds, result)
                    else
                        env.info("[ISIS_TOO] ERROR: Failed to add static " .. building.type)
                    end
                end
            end

            local unitCount = template.units and #template.units or 0
            if unitCount > 0 then
                local units = {}
                for i, unitData in ipairs(template.units) do
                    units[i] = {
                        type = unitData.type,
                        x = zonePos.x + unitData.offset.x,
                        y = zonePos.y + unitData.offset.y,
                        name = template.name .. "_U" .. i .. "_" .. attempt,
                        heading = heading,
                        skill = "Random",
                    }
                end

                if mist and mist.dynAdd then
                    local groupName = template.name .. "_" .. math.floor(timer.getTime() * 1000)
                    local groupData = {
                        country = country.id.CJTF_RED,
                        coalition = "red",
                        category = "vehicle",
                        task = "Ground Nothing",
                        name = groupName,
                        units = units,
                    }

                    local addSuccess, addResult = pcall(function()
                        return mist.dynAdd(groupData)
                    end)

                    if addSuccess and addResult and addResult.name then
                        local groupObj = Group.getByName(addResult.name)
                        if groupObj and groupObj:isExist() then
                            local grpUnits = groupObj:getUnits()
                            if grpUnits and #grpUnits > 0 then
                                spawnSuccess = true
                                finalGroupName = addResult.name
                                finalPos2d = zonePos

                                activeTargets[finalGroupName] = {
                                    name = template.name,
                                    zone = zoneName,
                                    grid = getGridReference(zonePos),
                                    heading = heading,
                                    unitCount = unitCount,
                                }

                                zoneSpawnCount[zoneName] = (zoneSpawnCount[zoneName] or 0) + 1
                                staticObjectIds[finalGroupName] = staticIds
                                destroyedBuildings[finalGroupName] = 0

                                table.insert(targetNames, finalGroupName)

                                local firstUnit = grpUnits[1]
                                if firstUnit and firstUnit:isExist() then
                                    local unitPos = firstUnit:getPosition()
                                    if unitPos and unitPos.p then
                                        local markerPos2d = { x = unitPos.p.x, y = unitPos.p.z }
                                        placeMarker(finalGroupName, template.name, markerPos2d)
                                    end
                                end
                                env.info("[ISIS_TOO] SUCCESS: Spawned " .. template.name .. " in " .. zoneName)
                                break
                            end
                        end
                    end
                else
                    env.info("[ISIS_TOO] ERROR: mist.dynAdd not available")
                end
            else
                env.info("[ISIS_TOO] ERROR: Template has no units")
            end
            end -- end water check
        end -- end if not zonePos
    end -- end attempt loop

    if not spawnSuccess then
        env.info("[ISIS_TOO] FAILED: All " .. MAX_ATTEMPTS .. " spawn attempts failed for " .. template.name)
    end
end

local function cleanupDeadTargets()
    local toRemove = {}

    for groupName, targetData in pairs(activeTargets) do
        local group = Group.getByName(groupName)
        if not group or group:isExist() == false or group:getSize() == 0 then
            table.insert(toRemove, groupName)
        end
    end

    for _, groupName in ipairs(toRemove) do
        local targetData = activeTargets[groupName]
        if targetData and targetData.zone then
            local z = targetData.zone
            zoneSpawnCount[z] = math.max(0, (zoneSpawnCount[z] or 0) - 1)
            if zoneSpawnCount[z] == 0 then zoneSpawnCount[z] = nil end
            env.info("[ISIS_TOO DEBUG] Zone decremented: " .. z .. " (now " .. tostring(zoneSpawnCount[z] or 0) .. " active)")
        end

        if staticObjectIds[groupName] then
            if mist and mist.removeStatic then
                for _, staticId in ipairs(staticObjectIds[groupName]) do
                    pcall(function() mist.removeStatic(staticId) end)
                end
            end
            staticObjectIds[groupName] = nil
        end

        destroyedBuildings[groupName] = nil
        activeTargets[groupName] = nil
        targetMenuAdded[groupName] = nil
        for i, name in ipairs(targetNames) do
            if name == groupName then
                table.remove(targetNames, i)
                break
            end
        end
        env.info("[ISIS_TOO] Cleaned up dead target: " .. groupName)
    end
end

local function updateDestroyedBuildings()
    for groupName, staticIds in pairs(staticObjectIds) do
        if activeTargets[groupName] then
            local destroyed = 0
            for _, staticId in ipairs(staticIds) do
                local obj = Object.getByName(staticId)
                if not obj or not obj:isExist() then
                    destroyed = destroyed + 1
                end
            end
            destroyedBuildings[groupName] = destroyed
        end
    end
end

local function populateZones(isInitial)
    -- Track running total so we stop the moment we hit the global cap
    local totalActive = 0
    for _ in pairs(activeTargets) do totalActive = totalActive + 1 end

    for _, zone in ipairs(TOO_ZONES) do
        if totalActive >= MAX_TOTAL_GROUPS then break end
        local current = zoneSpawnCount[zone] or 0
        local target
        if isInitial then
            target = math.random(MIN_SPAWNS_PER_ZONE, MAX_SPAWNS_PER_ZONE)
        else
            target = math.max(current, MIN_SPAWNS_PER_ZONE)
        end
        target = math.min(target, MAX_SPAWNS_PER_ZONE)
        for i = current + 1, target do
            if totalActive >= MAX_TOTAL_GROUPS then break end
            pcall(function() spawnTargetOfOpportunity(zone) end)
            totalActive = totalActive + 1
        end
    end
end

local function maintenanceCheck()
    cleanupDeadTargets()
    markerManagerCleanup()
    cleanupPlayerMenus()
    updateDestroyedBuildings()

    for groupName, targetData in pairs(activeTargets) do
        if not markerManager.active[groupName] and not isGroupDead(groupName) then
            env.info("[ISIS_TOO] WARNING: Living group " .. groupName .. " has no marker - reapplying")
            local group = Group.getByName(groupName)
            if group and group:isExist() then
                local units = group:getUnits()
                if units and #units > 0 then
                    local firstUnit = units[1]
                    if firstUnit and firstUnit:isExist() then
                        local unitPos = firstUnit:getPosition()
                        if unitPos and unitPos.p then
                            local markerPos2d = { x = unitPos.p.x, y = unitPos.p.z }
                            placeMarker(groupName, targetData.name, markerPos2d)
                        end
                    end
                end
            end
        end
    end

    populateZones(false)
end

local function createNineLine(groupName)
    local targetData = activeTargets[groupName]
    if not targetData then
        env.info("[ISIS_TOO] createNineLine: targetData not found for " .. tostring(groupName))
        return nil
    end

    local group = Group.getByName(groupName)
    if not group or not group:isExist() then
        env.info("[ISIS_TOO] createNineLine: group does not exist: " .. tostring(groupName))
        return nil
    end

    local units = group:getUnits()
    if not units or #units == 0 then
        env.info("[ISIS_TOO] createNineLine: no units in group " .. tostring(groupName))
        return nil
    end
    local targetUnit = units[1]

    if not targetUnit or not targetUnit:isExist() then
        env.info("[ISIS_TOO] createNineLine: target unit does not exist")
        return nil
    end

    local targetPos = targetUnit:getPoint()
    if not targetPos then
        env.info("[ISIS_TOO] createNineLine: could not get target position")
        return nil
    end

    local elevation = math.floor(targetPos.y or 0)

    local targetType = "Hostile Group"
    pcall(function() targetType = targetUnit:getTypeName() or "Hostile Group" end)

    local unitCount = group:getSize()
    local bearing = targetData.heading or 0

    local mgrs = convertToMGRS(targetPos)
    local nedm = convertToNEDM(targetPos)

    env.info("[ISIS_TOO] createNineLine: MGRS=" .. mgrs)

    if string.len(mgrs) < 13 then
        env.info("[ISIS_TOO] createNineLine: MGRS string too short: " .. mgrs)
        return nil
    end

    local gridBlockRef = string.sub(mgrs, 4, 5)
    local eastingFirstDigit = string.sub(mgrs, 6, 6)
    local northingFirstDigit = string.sub(mgrs, 11, 11)
    local ipGrid = gridBlockRef .. eastingFirstDigit .. northingFirstDigit

    local easting = tonumber(string.sub(mgrs, 6, 10))
    local northing = tonumber(string.sub(mgrs, 11, 15))

    if not easting or not northing then
        env.info("[ISIS_TOO] createNineLine: failed to parse easting/northing")
        return nil
    end

    local gridCenterEasting = (tonumber(eastingFirstDigit) + 0.5) * 10000
    local gridCenterNorthing = (tonumber(northingFirstDigit) + 0.5) * 10000

    local distToGridCenter = math.sqrt(
        (easting - gridCenterEasting)^2 + (northing - gridCenterNorthing)^2
    )
    local distKm = distToGridCenter / 1000

    local displayName = string.gsub(targetData.name, "_", " ")

    local callout = string.format(
        "[9-LINE CAS BRIEF] %s\n" ..
        "--------------------------------------\n" ..
        "1. IP: GRID %s\n" ..
        "2. HEADING: %03d degrees (from grid center)\n" ..
        "3. DISTANCE: On Grid %s - %.1f km from center\n" ..
        "             Direct Attack Authorized\n" ..
        "4. ELEVATION: %d meters\n" ..
        "5. TARGET: %s (%d units)\n" ..
        "6. LOCATION: %s (MGRS)\n" ..
        "         or: %s (DD°MM'SS\")\n" ..
        "7. MARK: VISUAL ONLY\n" ..
        "8. FRIENDLIES: CLEAR\n" ..
        "9. REMARKS: %s",
        displayName,
        ipGrid,
        bearing,
        ipGrid,
        distKm,
        elevation,
        targetType,
        unitCount,
        mgrs,
        nedm,
        displayName
    )

    return callout
end

-- ============================================================================
-- RADIO MENU SYSTEM
-- ============================================================================

local TOO_PLAYER_MENUS = {}

local function getLivingTargets()
    local living = {}
    for _, groupName in ipairs(targetNames) do
        local targetData = activeTargets[groupName]
        if targetData then
            local group = Group.getByName(groupName)
            if group and group:isExist() and group:getSize() > 0 then
                table.insert(living, { groupName = groupName, data = targetData })
            end
        end
    end
    return living
end

local function getLivingTargetBySlot(slotNum)
    local living = getLivingTargets()
    if slotNum <= #living then
        return living[slotNum]
    end
    return nil
end

local function createTOOMenuForGroup(groupId)
    if not missionCommands or not groupId then return end

    if TOO_PLAYER_MENUS[groupId] then return end

    local tooRoot = missionCommands.addSubMenuForGroup(groupId, "ISIS Targets", nil)

    if not tooRoot then
        env.info("[ISIS_TOO] Failed to create main menu for group " .. groupId)
        return
    end

    TOO_PLAYER_MENUS[groupId] = {
        mainMenu = tooRoot
    }

    env.info("[ISIS_TOO] Main menu created for group " .. groupId)

    missionCommands.addCommandForGroup(groupId, "List Active Targets", tooRoot, function()
        local living = getLivingTargets()

        if #living == 0 then
            trigger.action.outText("=== ISIS ACTIVE TARGETS ===\n\nNO ACTIVE TARGETS\n\nNew targets will spawn automatically.", 15, false)
            return
        end

        local msg = "=== ISIS ACTIVE TARGETS ===\nCount: " .. #living .. " targets\n\n"
        for i, t in ipairs(living) do
            local group = Group.getByName(t.groupName)
            local unitCount = group and group:getSize() or 0
            msg = msg .. "Target " .. i .. ": " .. t.data.name .. " (" .. unitCount .. " units)\n"
        end
        msg = msg .. "\n(Use Target 1-8 submenus for 9-line briefs)"

        trigger.action.outText(msg, 20, false)
    end)

    for slot = 1, 8 do
        local slotMenu = missionCommands.addSubMenuForGroup(groupId, "Target " .. slot, tooRoot)
        local slotNum = slot

        missionCommands.addCommandForGroup(groupId, "9-Line Brief", slotMenu, function()
            local target = getLivingTargetBySlot(slotNum)

            if not target then
                trigger.action.outText("Target " .. slotNum .. " - NO TARGET IN THIS SLOT\n\nUse 'List Active Targets' to see current targets.", 8, false)
                return
            end

            local success, result = pcall(function()
                local nineLine = createNineLine(target.groupName)
                if nineLine then
                    trigger.action.outText("9-LINE CAS BRIEF (Target " .. slotNum .. "):\n" .. nineLine, 30, false)
                    env.info("[ISIS_TOO] 9-Line displayed for slot " .. slotNum .. " (" .. target.groupName .. ")")
                else
                    trigger.action.outText("Unable to generate 9-line for Target " .. slotNum, 5, false)
                end
            end)

            if not success then
                env.info("[ISIS_TOO] ERROR in 9-line: " .. tostring(result))
                trigger.action.outText("ERROR generating 9-line brief", 5, false)
            end
        end)

        missionCommands.addCommandForGroup(groupId, "Target Status", slotMenu, function()
            local target = getLivingTargetBySlot(slotNum)

            if not target then
                trigger.action.outText("Target " .. slotNum .. " - NO TARGET IN THIS SLOT\n\nUse 'List Active Targets' to see current targets.", 8, false)
                return
            end

            local displayName = target.data.name
            local group = Group.getByName(target.groupName)
            local currentUnitCount = (group and group:isExist()) and group:getSize() or 0
            local originalUnitCount = target.data.unitCount or currentUnitCount
            local deadUnits = math.max(0, originalUnitCount - currentUnitCount)

            local totalBuildings = 0
            if staticObjectIds[target.groupName] then
                totalBuildings = #staticObjectIds[target.groupName]
            end
            local destroyedCount = destroyedBuildings[target.groupName] or 0
            local intactBuildings = math.max(0, totalBuildings - destroyedCount)

            local statusMsg = "Target " .. slotNum .. ": " .. displayName .. "\n"
            statusMsg = statusMsg .. "--------------------------------------\n"
            statusMsg = statusMsg .. "PERSONNEL/VEHICLES:\n"
            statusMsg = statusMsg .. "  Alive: " .. currentUnitCount .. "\n"
            statusMsg = statusMsg .. "  Killed: " .. deadUnits .. "\n"
            statusMsg = statusMsg .. "STRUCTURES:\n"
            statusMsg = statusMsg .. "  Intact: " .. intactBuildings .. "\n"
            statusMsg = statusMsg .. "  Destroyed: " .. destroyedCount

            trigger.action.outText(statusMsg, 10, false)
        end)

        missionCommands.addCommandForGroup(groupId, "What Target Is This?", slotMenu, function()
            local target = getLivingTargetBySlot(slotNum)

            if not target then
                trigger.action.outText("Target " .. slotNum .. " - EMPTY SLOT\n\nNo living target in this position.\nUse 'List Active Targets' to see all current targets.", 8, false)
            else
                local group = Group.getByName(target.groupName)
                local unitCount = group and group:getSize() or 0
                trigger.action.outText("Target " .. slotNum .. " = " .. target.data.name .. "\nUnits: " .. unitCount .. " alive\nGrid: " .. (target.data.grid or "Unknown"), 10, false)
            end
        end)
    end

    env.info("[ISIS_TOO] Menu for group " .. groupId .. " created with 8 dynamic target slots")
end

local function updateTOOMenusForAllPlayers()
    if not missionCommands then return end

    local coalitionBlue = coalition.getGroups(coalition.side.BLUE)
    if not coalitionBlue then return end

    for _, group in ipairs(coalitionBlue) do
        if group and group:isExist() then
            local groupId = group:getID()

            local units = group:getUnits()
            if units and #units > 0 then
                for _, unit in ipairs(units) do
                    if unit and unit:isExist() then
                        local playerName = unit:getPlayerName()
                        if playerName and playerName ~= "" then
                            createTOOMenuForGroup(groupId)
                            break
                        end
                    end
                end
            end
        end
    end
end

local function initTOORadioMenuSystem()
    if not missionCommands then
        env.info("[ISIS_TOO] missionCommands not available - cannot initialize radio menu")
        return false
    end

    env.info("[ISIS_TOO] Radio menu system initialized")
    return true
end

-- ============================================================================
-- SCHEDULER
-- ============================================================================

local function TOO_Init()
    env.info("[ISIS_TOO DEBUG] === TOO_Init called ===")
    if not TOO_CONFIG.enabled then
        env.info("[ISIS_TOO] System: DISABLED")
        return
    end

    if not checkDependencies() then
        env.info("[ISIS_TOO] System startup FAILED - missing required DCS APIs")
        return
    end

    env.info("[ISIS_TOO] All dependencies verified")
    env.info("[ISIS_TOO] System INITIALIZED - Syria ISIS Theatre")
    env.info("[ISIS_TOO] Templates: " .. #TOO_TEMPLATES)

    -- Discover zones dynamically by prefix
    discoverTOOZones()

    env.info("[ISIS_TOO] Zones found: " .. #TOO_ZONES)
    env.info("[ISIS_TOO] Config: minTargetsOnMap=" .. TOO_CONFIG.minTargetsOnMap)

    if missionCommands then
        env.info("[ISIS_TOO] missionCommands available - initializing radio menu system")
        initTOORadioMenuSystem()
    else
        env.info("[ISIS_TOO] missionCommands not yet available - scheduling init in 5 seconds")
        timer.scheduleFunction(function()
            if missionCommands then
                env.info("[ISIS_TOO] missionCommands now available - initializing")
                initTOORadioMenuSystem()
            else
                env.info("[ISIS_TOO] missionCommands still not available - retrying")
                return timer.getTime() + 5
            end
        end, nil, timer.getTime() + 5)
    end

    env.info("[ISIS_TOO DEBUG] === Populating all zones (" .. MIN_SPAWNS_PER_ZONE .. "-" .. MAX_SPAWNS_PER_ZONE .. " targets per zone) ===")
    pcall(function() populateZones(true) end)
    env.info("[ISIS_TOO] Initial zone population complete")

    timer.scheduleFunction(function()
        if TOO_CONFIG.enabled and missionCommands then
            pcall(function()
                updateTOOMenusForAllPlayers()
            end)
        end
        return timer.getTime() + 10
    end, nil, timer.getTime() + 3)

    timer.scheduleFunction(function()
        if TOO_CONFIG.enabled then
            pcall(function()
                maintenanceCheck()
            end)
            return timer.getTime() + 60
        end
    end, nil, timer.getTime() + 60)
end

-- ============================================================================
-- MISSION START
-- ============================================================================

local function delayedInit()
    local init_success, init_error = pcall(function()
        env.info("[ISIS_TOO] Delayed init starting...")
        if missionCommands then
            env.info("[ISIS_TOO] missionCommands available - proceeding with init")
            TOO_Init()
        else
            env.info("[ISIS_TOO] missionCommands not available yet - scheduling retry in 2 seconds")
            timer.scheduleFunction(function()
                delayedInit()
            end, nil, timer.getTime() + 2)
        end
    end)

    if not init_success then
        env.info("[ISIS_TOO] ERROR in delayedInit: " .. tostring(init_error))
    end
end

timer.scheduleFunction(function()
    local sched_success, sched_error = pcall(function()
        delayedInit()
    end)
    if not sched_success then
        env.info("[ISIS_TOO] CRITICAL ERROR: Scheduled init failed: " .. tostring(sched_error))
    end
end, nil, timer.getTime() + 1)

-- ============================================================================
-- SCRIPT LOAD NOTIFICATION
-- ============================================================================

trigger.action.outText(
    "[ISIS_TOO] Syria ISIS Target of Opportunity System Loaded",
    12
)

env.info("[ISIS_TOO] Syria ISIS TOO System initialization complete.")
