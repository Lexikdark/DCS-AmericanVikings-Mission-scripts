-- ============================================================================
-- TARGET OF OPPORTUNITY (TOO) SYSTEM v4.6 - DCS WORLD LUA MISSION SCRIPT
-- ============================================================================
-- Spawns 30 random insurgent targets with dynamic units and static structures
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
        env.info("[TOO] ERROR: Missing required DCS APIs: " .. table.concat(missing, ", "))
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
local occupiedZones = {}       -- Set of zone names currently occupied by active targets
local currentTemplateIndex = 0 -- Track template rotation (0-indexed, cycles through 1-30)

-- ============================================================================
-- 30 TEMPLATES (Pre-defined with specific compositions)
-- ============================================================================

local TOO_TEMPLATES = {
    { name = "Taliban_Kandahar_Cell", 
    buildings = { 
        { type = "WC", offset = { x = -70, y = -65 } },          -- NW corner (was FARP Tent)
        { type = "Tent04", offset = { x = 75, y = 70 } },         -- SE corner (was M92 Tent 04)
        { type = "Tent05", offset = { x = -65, y = 75 } }   -- SW corner (was M92 Camouflage 04)
    }, 
    units = { 
        { type = "Infantry AK Ins", offset = { x = -60, y = -50 } },    -- NW group
        { type = "Soldier AK", offset = { x = -70, y = -65 } },
        { type = "Soldier stinger", offset = { x = -50, y = -55 } },
        { type = "Soldier RPG", offset = { x = 55, y = 60 } },          -- SE group
        { type = "Soldier AK", offset = { x = 70, y = 75 } },
        { type = "Infantry AK Ins", offset = { x = 65, y = 55 } },
        { type = "Soldier RPG", offset = { x = -50, y = 70 } },        -- SW group
        { type = "P20_drivable", offset = { x = -60, y = 80 } },
        { type = "HL_DSHK", offset = { x = 60, y = -70 } }             -- NE support
    } 
    },
    { name = "Taliban_Badakhshan_Outpost", 
    buildings = { 
        { type = "Tent05", offset = { x = -75, y = -70 } },      -- NW (was M92 Tent 05)
        { type = "WC", offset = { x = 80, y = 65 } },          -- SE (was FARP Tent)
        { type = "Building07_PBR", offset = { x = -70, y = 80 } }, -- SW (was M92 Building07 PBR)
        { type = "Building08_PBR", offset = { x = 75, y = -70 } }  -- NE (was M92 Camouflage 06 - substituted)
    }, 
    units = { 
        { type = "Soldier AK", offset = { x = -70, y = -60 } },       -- NW group
        { type = "Soldier stinger", offset = { x = -60, y = -70 } }, 
        { type = "Infantry AK Ins", offset = { x = -80, y = -55 } },
        { type = "Soldier RPG", offset = { x = 65, y = 70 } },        -- SE group
        { type = "Soldier AK", offset = { x = 80, y = 60 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 75 } },
        { type = "P20_drivable", offset = { x = -50, y = 75 } },      -- SW group
        { type = "HL_ZU-23", offset = { x = -60, y = 85 } }, 
        { type = "Grad-URAL", offset = { x = -70, y = 70 } },
        { type = "2B11 mortar", offset = { x = 55, y = -60 } },       -- NE group
        { type = "2B11 mortar", offset = { x = 70, y = -70 } },
        { type = "2B11 mortar", offset = { x = 60, y = -80 } },
        { type = "tt_ZU-23", offset = { x = 75, y = -55 } },
        { type = "ural_4230_civil_t", offset = { x = -75, y = 70 } } 
    } 
    },
    { name = "Taliban_Ghazni_Fighters", 
    buildings = { 
        { type = "Tent04", offset = { x = 10, y = 10 } } -- was M92 Camouflage 04 (offset to avoid overlap)
    }, 
    units = { 
        { type = "Soldier AK", offset = { x = -60, y = -50 } },       -- NW
        { type = "Infantry AK Ins", offset = { x = -55, y = -65 } }, 
        { type = "Soldier RPG", offset = { x = -70, y = -55 } },
        { type = "Soldier stinger", offset = { x = 55, y = 60 } },    -- SE
        { type = "Soldier AK", offset = { x = 70, y = 75 } },
        { type = "Infantry AK Ins", offset = { x = 65, y = 55 } },
        { type = "Soldier RPG", offset = { x = -55, y = 70 } },       -- SW
        { type = "Soldier stinger", offset = { x = -65, y = 80 } },
        { type = "P20_drivable", offset = { x = 60, y = -65 } },      -- NE
        { type = "Grad-URAL", offset = { x = 75, y = -75 } },
        { type = "HL_B8M1", offset = { x = 70, y = -55 } },
        { type = "ural_4230_civil_t", offset = { x = -70, y = 65 } } 
    } 
    },
    { name = "Taliban_Helmand_Garrison", 
    buildings = { 
        { type = "WC", offset = { x = -70, y = -60 } },        -- NW (was FARP Tent)
        { type = "Building08_PBR", offset = { x = 75, y = 70 } },  -- SE (was M92 Camouflage 06)
        { type = "Building07_PBR", offset = { x = -65, y = 75 } } -- SW (was M92 Building07 PBR)
    }, 
    units = { 
        { type = "Soldier AK", offset = { x = -60, y = -50 } },       -- NW
        { type = "Infantry AK Ins", offset = { x = -75, y = -65 } }, 
        { type = "Soldier RPG", offset = { x = -50, y = -70 } },
        { type = "Soldier stinger", offset = { x = 55, y = 55 } },    -- SE
        { type = "Soldier AK", offset = { x = 70, y = 75 } },
        { type = "Infantry AK Ins", offset = { x = 80, y = 60 } },
        { type = "Soldier RPG", offset = { x = 60, y = 50 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },   -- SW
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -45, y = 65 } },
        { type = "P20_drivable", offset = { x = 60, y = -60 } },      -- NE
        { type = "Grad-URAL", offset = { x = 75, y = -75 } }, 
        { type = "HL_ZU-23", offset = { x = 50, y = -65 } }, 
        { type = "tt_ZU-23", offset = { x = 70, y = -50 } }, 
        { type = "ural_4230_civil_t", offset = { x = -75, y = 60 } }, 
        { type = "HL_B8M1", offset = { x = 55, y = -75 } } 
    } 
    },
    { name = "Taliban_Kunar_Ambush", 
    buildings = { 
        { type = "Tent04", offset = { x = -75, y = -70 } },      -- NW (was M92 Tent 04)
        { type = "Building08_PBR", offset = { x = 80, y = 75 } }, -- SE (was M92 Building08 PBR)
        { type = "WC", offset = { x = -70, y = 80 } } -- SW (was FARP Tent)
    }, 
    units = { 
        { type = "Soldier AK", offset = { x = -60, y = -55 } },       -- NW
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } }, 
        { type = "Soldier RPG", offset = { x = -50, y = -60 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },    -- SE
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "Soldier RPG", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 65 } },   -- SW
        { type = "Soldier AK", offset = { x = -65, y = 75 } },
        { type = "Infantry AK Ins", offset = { x = -70, y = 60 } },
        { type = "P20_drivable", offset = { x = 55, y = -70 } },      -- NE
        { type = "Grad-URAL", offset = { x = 70, y = -65 } }, 
        { type = "HL_DSHK", offset = { x = 65, y = -50 } }, 
        { type = "tt_ZU-23", offset = { x = 80, y = -75 } }, 
        { type = "ural_4230_civil_t", offset = { x = 75, y = -55 } }, 
        { type = "HL_ZU-23", offset = { x = 60, y = -60 } } 
    } 
    },
    { name = "Taliban_Logar_Defense", 
    buildings = { 
        { type = "WC", offset = { x = -70, y = -60 } },        -- NW (was FARP Tent)
        { type = "Building08_PBR", offset = { x = 80, y = 70 } },  -- SE (was M92 Camouflage 06)
        { type = "Tent05", offset = { x = -75, y = 75 } },       -- SW (was M92 Tent 05)
        { type = "Building07_PBR", offset = { x = 65, y = -70 } } -- NE (was M92 Building07 PBR)
    }, 
    units = { 
        { type = "Infantry AK Ins", offset = { x = -60, y = -50 } },   -- NW
        { type = "Soldier RPG", offset = { x = -75, y = -65 } }, 
        { type = "Soldier stinger", offset = { x = -55, y = -70 } },
        { type = "Soldier AK", offset = { x = 60, y = 65 } },         -- SE
        { type = "Infantry AK Ins", offset = { x = 75, y = 75 } },
        { type = "Soldier RPG", offset = { x = 70, y = 55 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },   -- SW
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },       -- NE
        { type = "Soldier stinger", offset = { x = 65, y = -75 } },
        { type = "Soldier AK", offset = { x = 75, y = -55 } },
        { type = "Infantry AK Ins", offset = { x = -70, y = 55 } },   -- SW support
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "Grad-URAL", offset = { x = 75, y = -75 } }, 
        { type = "LAZ Bus", offset = { x = -75, y = 55 } }, 
        { type = "HL_ZU-23", offset = { x = 70, y = -65 } }, 
        { type = "Ural-375 ZU-23 Insurgent", offset = { x = -60, y = 75 } } 
    } 
    },
    { name = "Taliban_Nurestan_Cache", 
    buildings = { 
        { type = "Tent05", offset = { x = -75, y = -70 } },      -- NW (was M92 Tent 05)
        { type = "Building07_PBR", offset = { x = 80, y = 75 } }  -- SE (was M92 Building07 PBR)
    }, 
    units = { 
        { type = "Soldier AK", offset = { x = -60, y = -50 } },       -- NW
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } }, 
        { type = "Soldier RPG", offset = { x = -50, y = -65 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },    -- SE
        { type = "HQ-7_LN_SP", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "Soldier RPG", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },   -- SW
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "HQ-7_STR_SP", offset = { x = 55, y = -65 } },       -- NE
        { type = "Soldier stinger", offset = { x = 70, y = -75 } },
        { type = "P20_drivable", offset = { x = 50, y = 50 } },
        { type = "ural_4230_civil_t", offset = { x = 75, y = -60 } }, 
        { type = "Grad-URAL", offset = { x = 80, y = -75 } }, 
        { type = "HL_DSHK", offset = { x = -60, y = 75 } }, 
        { type = "tt_ZU-23", offset = { x = 70, y = -60 } }, 
        { type = "HL_ZU-23", offset = { x = -75, y = -65 } } 
    } 
    },
    { name = "Taliban_Paktia_Checkpoint", 
    buildings = { 
        { type = "WC", offset = { x = -70, y = -60 } },        -- NW
        { type = "Tent04", offset = { x = 80, y = 70 } },  -- SE
        { type = "Tent04", offset = { x = -75, y = 75 } },       -- SW
        { type = "Building08_PBR", offset = { x = 65, y = -70 } }, -- NE
        { type = "Building08_PBR", offset = { x = 15, y = 15 } } -- Near center (offset to avoid overlap)
    }, 
    units = { 
        { type = "Soldier AK", offset = { x = -60, y = -50 } },       -- NW
        { type = "Infantry AK Ins", offset = { x = -75, y = -65 } }, 
        { type = "Soldier RPG", offset = { x = -50, y = -60 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },    -- SE
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "Soldier RPG", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },   -- SW
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },       -- NE
        { type = "Soldier stinger", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "ural_4230_civil_t", offset = { x = 75, y = -75 } }, 
        { type = "Grad-URAL", offset = { x = -60, y = 75 } }, 
        { type = "HL_ZU-23", offset = { x = 70, y = -60 } }, 
        { type = "tt_ZU-23", offset = { x = -75, y = 60 } }, 
        { type = "HL_B8M1", offset = { x = 60, y = -70 } } 
    } 
    },
    { name = "Taliban_Samangan_Force", 
    buildings = { 
        { type = "Tent05", offset = { x = -75, y = -70 } },      -- NW
        { type = "Building08_PBR", offset = { x = 80, y = 75 } }   -- SE
    }, 
    units = { 
        { type = "Infantry AK Ins", offset = { x = -60, y = -55 } },   -- NW
        { type = "Soldier AK", offset = { x = -75, y = -70 } }, 
        { type = "Soldier RPG", offset = { x = -50, y = -60 } },
        { type = "Soldier stinger", offset = { x = 60, y = 60 } },    -- SE
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "Soldier RPG", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 75 } },   -- SW
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -60, y = 65 } },
        { type = "Soldier RPG", offset = { x = 55, y = -70 } },       -- NE
        { type = "Soldier stinger", offset = { x = 70, y = -75 } },
        { type = "P20_drivable", offset = { x = 50, y = 55 } },
        { type = "ural_4230_civil_t", offset = { x = 75, y = -75 } }, 
        { type = "Grad-URAL", offset = { x = 80, y = -65 } }, 
        { type = "HL_DSHK", offset = { x = -75, y = 60 } }, 
        { type = "tt_ZU-23", offset = { x = 70, y = -55 } }, 
        { type = "HL_ZU-23", offset = { x = -60, y = -75 } } 
    } 
    },
    { name = "Taliban_Takhar_Patrol", 
    buildings = { 
        { type = "Tent04", offset = { x = -75, y = -70 } }, -- NW
        { type = "Building07_PBR", offset = { x = 80, y = 75 } }   -- SE
    }, 
    units = { 
        { type = "Soldier AK", offset = { x = -60, y = -55 } },       -- NW
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } }, 
        { type = "Soldier RPG", offset = { x = -50, y = -65 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },    -- SE
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "Soldier RPG", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },   -- SW
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },       -- NE
        { type = "Soldier stinger", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "ural_4230_civil_t", offset = { x = 75, y = -75 } }, 
        { type = "Grad-URAL", offset = { x = 80, y = -65 } }, 
        { type = "HL_ZU-23", offset = { x = -75, y = 60 } }, 
        { type = "tt_ZU-23", offset = { x = -60, y = -70 } } 
    } 
    },
    { name = "Taliban_Urozgan_Trap", 
    buildings = { 
        { type = "Tent04", offset = { x = -75, y = -70 } },      -- NW
        { type = "WC", offset = { x = 80, y = 75 } },          -- SE
        { type = "Tent04", offset = { x = -70, y = 80 } }  -- SW
    }, 
    units = { 
        { type = "Infantry AK Ins", offset = { x = -60, y = -50 } },   -- NW
        { type = "Soldier AK", offset = { x = -75, y = -65 } }, 
        { type = "Soldier RPG", offset = { x = -50, y = -70 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },    -- SE
        { type = "Infantry AK Ins", offset = { x = 75, y = 80 } },
        { type = "Soldier AK", offset = { x = 70, y = 55 } },
        { type = "Soldier RPG", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },   -- SW
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier RPG", offset = { x = 55, y = -70 } },       -- NE
        { type = "P20_drivable", offset = { x = -60, y = 75 } },
        { type = "Grad-URAL", offset = { x = 70, y = -75 } }, 
        { type = "HL_DSHK", offset = { x = -75, y = -65 } }, 
        { type = "tt_ZU-23", offset = { x = 65, y = -60 } } 
    } 
    },
    { name = "Taliban_Wardak_Village", 
    buildings = { 
        { type = "WC", offset = { x = -75, y = -70 } },        -- NW
        { type = "Tent05", offset = { x = 80, y = 75 } }         -- SE
    }, 
    units = { 
        { type = "HQ-7_LN_SP", offset = { x = -60, y = -50 } },       -- NW
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } }, 
        { type = "Soldier stinger", offset = { x = -50, y = -65 } },
        { type = "Soldier RPG", offset = { x = 60, y = 65 } },        -- SE
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "Soldier stinger", offset = { x = 65, y = 75 } },
        { type = "Soldier RPG", offset = { x = -55, y = 70 } },       -- SW
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier stinger", offset = { x = 50, y = -60 } },   -- NE
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "ural_4230_civil_t", offset = { x = 75, y = -75 } }, 
        { type = "Grad-URAL", offset = { x = -75, y = 60 } }, 
        { type = "HL_ZU-23", offset = { x = 70, y = -65 } }, 
        { type = "tt_ZU-23", offset = { x = -60, y = 75 } }, 
        { type = "HQ-7_STR_SP", offset = { x = 60, y = -70 } } 
    } 
    },
    { name = "Taliban_Zabul_Desert_Pos", 
    buildings = { 
        { type = "WC", offset = { x = -75, y = -70 } },        -- NW
        { type = "Tent04", offset = { x = 80, y = 75 } },  -- SE
        { type = "Building08_PBR", offset = { x = -70, y = 80 } } -- SW
    }, 
    units = { 
        { type = "Infantry AK Ins", offset = { x = -60, y = -50 } },   -- NW
        { type = "Soldier RPG", offset = { x = -75, y = -70 } }, 
        { type = "Soldier AK", offset = { x = -50, y = -65 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },    -- SE
        { type = "Infantry AK Ins", offset = { x = 75, y = 80 } },
        { type = "Soldier RPG", offset = { x = 70, y = 55 } },
        { type = "Soldier AK", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },   -- SW
        { type = "Infantry AK Ins", offset = { x = -70, y = 80 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },       -- NE
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "HL_DSHK", offset = { x = 75, y = -75 } }, 
        { type = "Grad-URAL", offset = { x = -75, y = 60 } }, 
        { type = "tt_ZU-23", offset = { x = 70, y = -65 } }, 
        { type = "ural_4230_civil_t", offset = { x = -60, y = -70 } } 
    } 
    },
    { name = "Taliban_Nangarhar_Command", 
    buildings = { 
        { type = "Tent04", offset = { x = -75, y = -70 } },      -- NW
        { type = "Building08_PBR", offset = { x = 80, y = 75 } }   -- SE
    }, 
    units = { 
        { type = "Soldier AK", offset = { x = -60, y = -50 } },       -- NW
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } }, 
        { type = "Soldier RPG", offset = { x = -50, y = -65 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },    -- SE
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "Soldier RPG", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },   -- SW
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },       -- NE
        { type = "P20_drivable", offset = { x = -60, y = 75 } },
        { type = "ural_4230_civil_t", offset = { x = 70, y = -75 } }, 
        { type = "Grad-URAL", offset = { x = 75, y = -65 } }, 
        { type = "HL_B8M1", offset = { x = -75, y = 60 } }, 
        { type = "tt_ZU-23", offset = { x = 65, y = -60 } }, 
        { type = "HQ-7_LN_SP", offset = { x = -60, y = -70 } } 
    } 
    },
    { name = "Taliban_Khost_Stronghold", 
    buildings = { 
        { type = "WC", offset = { x = -70, y = -60 } },        -- NW
        { type = "Tent04", offset = { x = 80, y = 70 } },        -- SE
        { type = "Tent04", offset = { x = -75, y = 75 } }, -- SW
        { type = "Building07_PBR", offset = { x = 65, y = -70 } }  -- NE
    }, 
    units = { 
        { type = "Infantry AK Ins", offset = { x = -60, y = -50 } },   -- NW
        { type = "Soldier AK", offset = { x = -75, y = -65 } }, 
        { type = "Soldier RPG", offset = { x = -50, y = -70 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },    -- SE
        { type = "Infantry AK Ins", offset = { x = 75, y = 80 } },
        { type = "Soldier AK", offset = { x = 70, y = 55 } },
        { type = "Soldier RPG", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },   -- SW
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },       -- NE
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "Grad-URAL", offset = { x = 75, y = -75 } }, 
        { type = "HL_ZU-23", offset = { x = -75, y = 60 } } 
    } 
    },
    { name = "Taliban_Balkh_Outpost", 
    buildings = { 
        { type = "Tent04", offset = { x = -75, y = -70 } }, -- NW
        { type = "Tent05", offset = { x = 80, y = 75 } },         -- SE
        { type = "WC", offset = { x = -70, y = 80 } } -- SW
    }, 
    units = { 
        { type = "Soldier AK", offset = { x = -60, y = -55 } },       -- NW
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } }, 
        { type = "Soldier stinger", offset = { x = -50, y = -65 } },
        { type = "Soldier RPG", offset = { x = 60, y = 60 } },        -- SE
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "Soldier stinger", offset = { x = 65, y = 75 } },
        { type = "Soldier RPG", offset = { x = -55, y = 75 } },       -- SW
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -60, y = 65 } },
        { type = "Soldier stinger", offset = { x = 50, y = -60 } },   -- NE
        { type = "Soldier RPG", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "HL_DSHK", offset = { x = 75, y = -75 } }, 
        { type = "tt_ZU-23", offset = { x = -75, y = 60 } }, 
        { type = "Grad-URAL", offset = { x = 70, y = -60 } }, 
        { type = "ural_4230_civil_t", offset = { x = -60, y = -70 } } 
    } 
    },
    { name = "Taliban_Bamyan_Guard", 
    buildings = { 
        { type = "Tent04", offset = { x = -70, y = -60 } },      -- NW
        { type = "Building07_PBR", offset = { x = 80, y = 75 } }, -- SE
        { type = "Building08_PBR", offset = { x = -75, y = 80 } }, -- SW
        { type = "Tent05", offset = { x = 65, y = -70 } },       -- NE
        { type = "WC", offset = { x = 55, y = 60 } } -- SE2
    }, 
    units = { 
        { type = "Infantry AK Ins", offset = { x = -60, y = -50 } },   -- NW
        { type = "Soldier RPG", offset = { x = -75, y = -65 } }, 
        { type = "Soldier AK", offset = { x = -50, y = -70 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },    -- SE
        { type = "Infantry AK Ins", offset = { x = 75, y = 80 } },
        { type = "Soldier RPG", offset = { x = 70, y = 55 } },
        { type = "Soldier AK", offset = { x = 65, y = 75 } },
        { type = "HQ-7_LN_SP", offset = { x = -55, y = 70 } },   -- SW
        { type = "Infantry AK Ins", offset = { x = -70, y = 80 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },       -- NE
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "Grad-URAL", offset = { x = 75, y = -75 } }, 
        { type = "HL_ZU-23", offset = { x = -75, y = 60 } }, 
        { type = "tt_ZU-23", offset = { x = 70, y = -65 } }, 
        { type = "ural_4230_civil_t", offset = { x = -60, y = -70 } },
        { type = "HQ-7_STR_SP", offset = { x = 60, y = 70 } }
    } 
    },
    { name = "Taliban_Daykundi_Squad", 
    buildings = { 
        { type = "Building08_PBR", offset = { x = -75, y = -70 } }, -- NW
        { type = "Building08_PBR", offset = { x = 80, y = 75 } }   -- SE
    }, 
    units = { 
        { type = "Soldier AK", offset = { x = -60, y = -55 } },       -- NW
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } }, 
        { type = "Soldier RPG", offset = { x = -50, y = -65 } },
        { type = "Soldier stinger", offset = { x = 60, y = 60 } },    -- SE
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "Soldier RPG", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 75 } },   -- SW
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -60, y = 65 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },       -- NE
        { type = "Soldier stinger", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = -60, y = 75 } },
        { type = "Grad-URAL", offset = { x = 70, y = -75 } }, 
        { type = "HL_B8M1", offset = { x = 75, y = -65 } }, 
        { type = "ural_4230_civil_t", offset = { x = -75, y = 60 } } 
    } 
    },
    { name = "Taliban_Faryab_Fighters", 
    buildings = { 
        { type = "WC", offset = { x = -75, y = -70 } },        -- NW
        { type = "Tent05", offset = { x = 80, y = 75 } },        -- SE
        { type = "Tent04", offset = { x = -70, y = 80 } }  -- SW
    }, 
    units = { 
        { type = "Infantry AK Ins", offset = { x = -60, y = -50 } },   -- NW
        { type = "Soldier AK", offset = { x = -75, y = -70 } }, 
        { type = "Soldier RPG", offset = { x = -50, y = -70 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },    -- SE
        { type = "Infantry AK Ins", offset = { x = 75, y = 80 } },
        { type = "HQ-7_STR_SP", offset = { x = 70, y = 55 } },
        { type = "Soldier RPG", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },   -- SW
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },       -- NE
        { type = "HQ-7_LN_SP", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "Grad-URAL", offset = { x = 75, y = -75 } }, 
        { type = "HL_DSHK", offset = { x = -75, y = 60 } }, 
        { type = "tt_ZU-23", offset = { x = 70, y = -65 } }, 
        { type = "ural_4230_civil_t", offset = { x = -60, y = -70 } } 
    } 
    },
    { name = "Taliban_Ghor_Ambush", 
    buildings = { 
        { type = "Building07_PBR", offset = { x = -70, y = -60 } }, -- NW
        { type = "WC", offset = { x = 80, y = 70 } },          -- SE
        { type = "Tent04", offset = { x = -75, y = 75 } }, -- SW
        { type = "Building08_PBR", offset = { x = 65, y = -70 } }  -- NE
    }, 
    units = { 
        { type = "Soldier AK", offset = { x = -60, y = -50 } },       -- NW
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } }, 
        { type = "Soldier stinger", offset = { x = -50, y = -70 } },
        { type = "HQ-7_LN_SP", offset = { x = 60, y = 65 } },        -- SE
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "Soldier stinger", offset = { x = 65, y = 75 } },
        { type = "Soldier RPG", offset = { x = -55, y = 70 } },       -- SW
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier stinger", offset = { x = 50, y = -60 } },   -- NE
        { type = "P20_drivable", offset = { x = -60, y = 75 } },
        { type = "Grad-URAL", offset = { x = 70, y = -75 } }, 
        { type = "HL_ZU-23", offset = { x = 75, y = -65 } }, 
        { type = "tt_ZU-23", offset = { x = -75, y = 60 } }, 
        { type = "HQ-7_STR_SP", offset = { x = 65, y = -60 } } 
    } 
    },
    { name = "Taliban_Jawzjan_Crew", 
    buildings = { 
        { type = "Building08_PBR", offset = { x = -75, y = -70 } }, -- NW
        { type = "Tent04", offset = { x = 80, y = 75 } },         -- SE
        { type = "WC", offset = { x = -70, y = 80 } } -- SW
    }, 
    units = { 
        { type = "Infantry AK Ins", offset = { x = -60, y = -55 } },   -- NW
        { type = "Soldier RPG", offset = { x = -75, y = -70 } }, 
        { type = "Soldier AK", offset = { x = -50, y = -65 } },
        { type = "Soldier stinger", offset = { x = 60, y = 60 } },    -- SE
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "Soldier RPG", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 75 } },   -- SW
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -60, y = 65 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },       -- NE
        { type = "Soldier stinger", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "Grad-URAL", offset = { x = 75, y = -75 } }, 
        { type = "HL_B8M1", offset = { x = -75, y = 60 } }, 
        { type = "ural_4230_civil_t", offset = { x = 70, y = -65 } }, 
        { type = "tt_ZU-23", offset = { x = -60, y = -70 } } 
    } 
    },
    { name = "Taliban_Kapisa_Cache", 
    buildings = { 
        { type = "WC", offset = { x = -70, y = -60 } },        -- NW
        { type = "Building08_PBR", offset = { x = 80, y = 70 } }, -- SE
        { type = "Building08_PBR", offset = { x = -75, y = 75 } }, -- SW
        { type = "Tent05", offset = { x = 65, y = -70 } } -- NE
    }, 
    units = { 
        { type = "Soldier AK", offset = { x = -60, y = -50 } },       -- NW
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } }, 
        { type = "Soldier stinger", offset = { x = -50, y = -70 } },
        { type = "Soldier RPG", offset = { x = 60, y = 65 } },        -- SE
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "Soldier stinger", offset = { x = 65, y = 75 } },
        { type = "Soldier RPG", offset = { x = -55, y = 70 } },       -- SW
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier stinger", offset = { x = 50, y = -60 } },   -- NE
        { type = "Soldier RPG", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = -60, y = 75 } },
        { type = "Grad-URAL", offset = { x = 70, y = -75 } }, 
        { type = "HL_DSHK", offset = { x = 75, y = -65 } }, 
        { type = "ural_4230_civil_t", offset = { x = -75, y = 60 } }, 
        { type = "tt_ZU-23", offset = { x = 60, y = -70 } } 
    } 
    },
    { name = "Taliban_Kunduz_Support", 
    buildings = { 
        { type = "Tent05", offset = { x = -75, y = -70 } },      -- NW
        { type = "WC", offset = { x = 80, y = 75 } } -- SE
    }, 
    units = { 
        { type = "Infantry AK Ins", offset = { x = -60, y = -50 } },   -- NW
        { type = "Soldier AK", offset = { x = -75, y = -70 } }, 
        { type = "Soldier RPG", offset = { x = -50, y = -70 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },    -- SE
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "Soldier RPG", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },   -- SW
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },       -- NE
        { type = "HQ-7_LN_SP", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "Grad-URAL", offset = { x = 75, y = -75 } }, 
        { type = "HL_ZU-23", offset = { x = -75, y = 60 } }, 
        { type = "tt_ZU-23", offset = { x = 70, y = -65 } }, 
        { type = "HQ-7_STR_SP", offset = { x = -60, y = -70 } } 
    } 
    },
    { name = "Taliban_Laghman_Rear", 
    buildings = { 
        { type = "Building08_PBR", offset = { x = -75, y = -70 } }, -- NW
        { type = "Building07_PBR", offset = { x = 80, y = 75 } },  -- SE
        { type = "Tent04", offset = { x = -70, y = 80 } } -- SW
    }, 
    units = { 
        { type = "Soldier AK", offset = { x = -60, y = -55 } },       -- NW
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } }, 
        { type = "Soldier RPG", offset = { x = -50, y = -65 } },
        { type = "Soldier stinger", offset = { x = 60, y = 60 } },    -- SE
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "Soldier RPG", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 75 } },   -- SW
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -60, y = 65 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },       -- NE
        { type = "Soldier stinger", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "ural_4230_civil_t", offset = { x = 75, y = -75 } }, 
        { type = "Grad-URAL", offset = { x = -75, y = 60 } }, 
        { type = "HL_B8M1", offset = { x = 70, y = -65 } }, 
        { type = "HQ-7_LN_SP", offset = { x = -60, y = -70 } } 
    } 
    },
    { name = "Taliban_Maidan_Sabotage", 
    buildings = { 
        { type = "Tent04", offset = { x = -75, y = -70 } },      -- NW
        { type = "Building08_PBR", offset = { x = 80, y = 75 } }  -- SE
    }, 
    units = { 
        { type = "Infantry AK Ins", offset = { x = -60, y = -50 } },   -- NW
        { type = "Soldier AK", offset = { x = -75, y = -70 } }, 
        { type = "Soldier RPG", offset = { x = -50, y = -70 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },    -- SE
        { type = "Infantry AK Ins", offset = { x = 75, y = 80 } },
        { type = "Soldier AK", offset = { x = 70, y = 55 } },
        { type = "Soldier RPG", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },   -- SW
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },       -- NE
        { type = "Soldier stinger", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "Grad-URAL", offset = { x = 75, y = -75 } }, 
        { type = "HL_DSHK", offset = { x = -75, y = 60 } }, 
        { type = "ural_4230_civil_t", offset = { x = 70, y = -65 } }, 
        { type = "tt_ZU-23", offset = { x = -60, y = -70 } } 
    } 
    },
    { name = "Taliban_Nimruz_Battle", 
    buildings = { 
        { type = "WC", offset = { x = -70, y = -60 } },        -- NW
        { type = "Tent05", offset = { x = 80, y = 70 } },        -- SE
        { type = "Tent04", offset = { x = -75, y = 75 } }, -- SW
        { type = "Building07_PBR", offset = { x = 65, y = -70 } }, -- NE
        { type = "Building08_PBR", offset = { x = 55, y = 60 } } -- SE2
    }, 
    units = { 
        { type = "Soldier AK", offset = { x = -60, y = -50 } },       -- NW
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } }, 
        { type = "Soldier stinger", offset = { x = -50, y = -70 } },
        { type = "Soldier RPG", offset = { x = 60, y = 65 } },        -- SE
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "HQ-7_LN_SP", offset = { x = 65, y = 75 } },
        { type = "Soldier RPG", offset = { x = -55, y = 70 } },       -- SW
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier stinger", offset = { x = 50, y = -60 } },   -- NE
        { type = "P20_drivable", offset = { x = -60, y = 75 } },
        { type = "Grad-URAL", offset = { x = 70, y = -75 } }, 
        { type = "HL_ZU-23", offset = { x = 75, y = -65 } }, 
        { type = "ural_4230_civil_t", offset = { x = -75, y = 60 } }, 
        { type = "tt_ZU-23", offset = { x = 70, y = -65 } }, 
        { type = "HQ-7_STR_SP", offset = { x = -60, y = -70 } } 
    } 
    },
    { name = "Taliban_Panjshir_Fortress", 
    buildings = { 
        { type = "Building08_PBR", offset = { x = -75, y = -70 } }, -- NW
        { type = "Building07_PBR", offset = { x = 80, y = 75 } },  -- SE
        { type = "WC", offset = { x = -70, y = 80 } },         -- SW
        { type = "Tent05", offset = { x = 65, y = -70 } } -- NE
    }, 
    units = { 
        { type = "Infantry AK Ins", offset = { x = -60, y = -50 } },   -- NW
        { type = "Soldier RPG", offset = { x = -75, y = -70 } }, 
        { type = "Soldier AK", offset = { x = -50, y = -70 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },    -- SE
        { type = "Infantry AK Ins", offset = { x = 75, y = 80 } },
        { type = "Soldier RPG", offset = { x = 70, y = 55 } },
        { type = "Soldier AK", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },   -- SW
        { type = "Infantry AK Ins", offset = { x = -70, y = 80 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },       -- NE
        { type = "Soldier AK", offset = { x = -12, y = 6 } },
        { type = "Soldier stinger", offset = { x = 8, y = 14 } },
        { type = "P20_drivable", offset = { x = 14, y = 12 } },
        { type = "Grad-URAL", offset = { x = 24, y = 10 } },
        { type = "HL_B8M1", offset = { x = 18, y = -14 } },
        { type = "ural_4230_civil_t", offset = { x = 20, y = 14 } },
        { type = "tt_ZU-23", offset = { x = -8, y = -14 } } 
    } 
    },
    { name = "Taliban_Parwan_Defense", 
    buildings = { 
        { type = "WC", offset = { x = -75, y = -70 } },        -- NW
        { type = "Tent05", offset = { x = 80, y = 75 } },        -- SE
        { type = "Tent04", offset = { x = -70, y = 80 } }  -- SW
    }, 
    units = { 
        { type = "Soldier AK", offset = { x = -60, y = -55 } },       -- NW
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } }, 
        { type = "Soldier RPG", offset = { x = -50, y = -65 } },
        { type = "Soldier stinger", offset = { x = 60, y = 60 } },    -- SE
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "HQ-7_LN_SP", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 75 } },   -- SW
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -60, y = 65 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },       -- NE
        { type = "Soldier stinger", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "ural_4230_civil_t", offset = { x = 75, y = -75 } }, 
        { type = "Grad-URAL", offset = { x = -75, y = 60 } }, 
        { type = "HL_DSHK", offset = { x = 70, y = -65 } }, 
        { type = "HQ-7_STR_SP", offset = { x = -60, y = -70 } } 
    } 
    },
    { name = "Taliban_Saripul_Garrison", 
    buildings = { 
        { type = "Building08_PBR", offset = { x = -75, y = -70 } }, -- NW
        { type = "Tent04", offset = { x = 80, y = 75 } } -- SE
    }, 
    units = { 
        { type = "Infantry AK Ins", offset = { x = -60, y = -50 } },   -- NW
        { type = "Soldier AK", offset = { x = -75, y = -70 } }, 
        { type = "Soldier RPG", offset = { x = -50, y = -70 } },
        { type = "Soldier stinger", offset = { x = 60, y = 65 } },    -- SE
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "Soldier RPG", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 70 } },   -- SW
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -65, y = 60 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },       -- NE
        { type = "Soldier stinger", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "Grad-URAL", offset = { x = 75, y = -75 } }, 
        { type = "HL_ZU-23", offset = { x = -75, y = 60 } }, 
        { type = "ural_4230_civil_t", offset = { x = 70, y = -65 } }, 
        { type = "tt_ZU-23", offset = { x = -60, y = -70 } }, 
        { type = "HQ-7_LN_SP", offset = { x = 60, y = -70 } } 
    } 
    },
    { name = "Taliban_Aybak_Operations", 
    buildings = { 
        { type = "WC", offset = { x = -75, y = -70 } },        -- NW
        { type = "Building08_PBR", offset = { x = 80, y = 75 } }   -- SE
    }, 
    units = { 
        { type = "Soldier AK", offset = { x = -60, y = -55 } },       -- NW
        { type = "Infantry AK Ins", offset = { x = -75, y = -70 } }, 
        { type = "Soldier RPG", offset = { x = -50, y = -65 } },
        { type = "Soldier stinger", offset = { x = 60, y = 60 } },    -- SE
        { type = "Soldier AK", offset = { x = 75, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = 70, y = 55 } },
        { type = "Soldier RPG", offset = { x = 65, y = 75 } },
        { type = "Soldier stinger", offset = { x = -55, y = 75 } },   -- SW
        { type = "Soldier AK", offset = { x = -70, y = 80 } },
        { type = "Infantry AK Ins", offset = { x = -60, y = 65 } },
        { type = "Soldier RPG", offset = { x = 50, y = -60 } },       -- NE
        { type = "Soldier stinger", offset = { x = 65, y = -75 } },
        { type = "P20_drivable", offset = { x = 55, y = 55 } },
        { type = "Grad-URAL", offset = { x = 75, y = -75 } }, 
        { type = "HL_ZU-23", offset = { x = -75, y = 60 } }, 
        { type = "tt_ZU-23", offset = { x = 70, y = -65 } } 
    } 
    }
}

-- ============================================================================
-- SPAWN ZONES (60 TOTAL)
-- ============================================================================
local TOO_ZONES = {
    "TOOZONE1", "TOOZONE2", "TOOZONE3", "TOOZONE4", "TOOZONE5",
    "TOOZONE6", "TOOZONE7", "TOOZONE8", "TOOZONE9", "TOOZONE10",
    "TOOZONE11", "TOOZONE12", "TOOZONE13", "TOOZONE14", "TOOZONE15",
    "TOOZONE16", "TOOZONE17", "TOOZONE18", "TOOZONE19", "TOOZONE20",
    "TOOZONE21", "TOOZONE22", "TOOZONE23", "TOOZONE24", "TOOZONE25",
    "TOOZONE26", "TOOZONE27", "TOOZONE28", "TOOZONE29", "TOOZONE30",
    "TOOZONE31", "TOOZONE32", "TOOZONE33", "TOOZONE34", "TOOZONE35",
    "TOOZONE36", "TOOZONE37", "TOOZONE38", "TOOZONE39", "TOOZONE40",
    "TOOZONE41", "TOOZONE42", "TOOZONE43", "TOOZONE44", "TOOZONE45",
    "TOOZONE46", "TOOZONE47", "TOOZONE48", "TOOZONE49", "TOOZONE50",
    "TOOZONE51", "TOOZONE52", "TOOZONE53", "TOOZONE54", "TOOZONE55",
    "TOOZONE56", "TOOZONE57", "TOOZONE58", "TOOZONE59", "TOOZONE60",
}

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
    -- Convert DCS world coordinates to N-E DM format (Degrees, Minutes, Seconds)
    -- Format used in DCS: DD°MM'SS.S"H (e.g., 41°15'30.2"N 075°45'15.8"E)
    if not pos then return "UNKNOWN" end
    
    -- DCS coordinates to approximate latitude/longitude (varies by map)
    -- Using a generic conversion - adjust constants if needed for specific map
    local lat = 40 + (pos.z / 111000)  -- Rough conversion (1 degree lat ≈ 111km)
    local lon = 10 + (pos.x / 111000)  -- Rough conversion
    
    -- Convert to Degrees Minutes Seconds
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
    
    -- Format: DD°MM'SS.S"H (DCS format)
    return string.format("%s%02d°%02d'%05.2f\" %s%03d°%02d'%05.2f\"", 
        lat_dir, math.abs(lat_deg), math.abs(lat_min), math.abs(lat_sec),
        lon_dir, math.abs(lon_deg), math.abs(lon_min), math.abs(lon_sec))
end

local function convertToMGRS(pos)
    -- Generate MGRS coordinates from position
    -- MGRS format: ZoneLetter GridLetters Easting(5) Northing(5)
    -- Example: 41SPE1234567890 (no spaces for substring extraction)
    if not pos then return "UNKNOWN" end
    
    local x = math.floor(pos.x / 1000)
    local z = math.floor(pos.z / 1000)
    
    -- Generate grid letters (simplified 2-letter grid)
    local grid_letter1 = string.char(65 + ((x / 100) % 26))  -- A-Z
    local grid_letter2 = string.char(65 + ((z / 100) % 26))  -- A-Z
    
    -- Generate 5-digit easting and northing (full precision)
    local easting = string.format("%05d", x % 100000)
    local northing = string.format("%05d", z % 100000)
    
    -- Format: 41SPE1234567890 (zone + band + grid letters + easting + northing, NO SPACES)
    return "41S" .. grid_letter1 .. grid_letter2 .. easting .. northing
end

-- ============================================================================
-- SPAWN FUNCTIONS
-- ============================================================================

local function getRandomPositionInZone(zoneName)
    -- Get random 2D position within trigger zone (all zones are circular)
    local zone = trigger.misc.getZone(zoneName)
    if not zone then return nil end
    
    -- Get zone center and radius
    local center2d = { x = zone.point.x, y = zone.point.z }
    local radius = zone.radius or 500
    
    -- Random point within radius using proper distribution (sqrt for uniform area coverage)
    local r = radius * math.sqrt(math.random())
    local angle = math.random() * 2 * math.pi
    
    local pos2d = {
        x = center2d.x + r * math.cos(angle),
        y = center2d.y + r * math.sin(angle),
    }
    
    env.info("[TOO DEBUG] Zone: " .. zoneName .. " | Radius: " .. radius .. "m | Spawn distance from center: " .. math.floor(r) .. "m")
    
    -- Return 2D position only (mist.dynAdd will handle terrain altitude automatically)
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
            alt = math.max(0, alt)  -- Ensure altitude is not negative
        else
            alt = 100  -- Default fallback
        end
    else
        alt = 100  -- Default altitude if land module not available
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
-- MARKER MANAGER (Simple & Robust like DGSS)
-- ============================================================================

local markerManager = {
    active  = {},      -- { groupName = markerId }
    mainPath = nil,    -- Cached main menu path
    tgtInfoPath = nil, -- Cached TGT Info submenu path
}

local function placeMarker(groupName, markerText, pos2d)
    -- Place map marker for the spawned group
    if not pos2d or not groupName then
        env.info("[TOO] ERROR: placeMarker called with invalid parameters - pos2d: " .. tostring(pos2d) .. ", groupName: " .. tostring(groupName))
        return false
    end
    
    if not trigger or not trigger.action or not trigger.action.markToAll then
        env.info("[TOO] ERROR: trigger.action.markToAll not available")
        return false
    end
    
    -- Remove old marker if it exists (avoid duplicates)
    if markerManager.active[groupName] then
        local oldMarkerId = markerManager.active[groupName]
        pcall(function()
            trigger.action.removeMark(oldMarkerId)
            env.info("[TOO] DEBUG: Removed old marker ID " .. oldMarkerId .. " for group " .. groupName)
        end)
    end
    
    -- Convert to 3D position with altitude
    local p3 = toVec3Ground(pos2d)
    
    -- Check group's actual positions for comparison
    local group = Group.getByName(groupName)
    local groupInfo = ""
    if group and group:getUnits() and #group:getUnits() > 0 then
        local unit = group:getUnits()[1]
        local unitPos = unit:getPosition().p
        groupInfo = " | First Unit at: x=" .. math.floor(unitPos.x) .. " y=" .. math.floor(unitPos.y) .. " z=" .. math.floor(unitPos.z)
    end
    
    -- Generate unique marker ID (must be positive and reasonable)
    local markerId = math.random(10000, 99999)
    
    -- Create informative marker text
    local fullMarkerText = "[TOO] " .. markerText
    
    -- Place marker on map for all - readOnly false to allow user interaction
    local success = pcall(function()
        env.info("[TOO] DEBUG: Placing marker ID " .. markerId .. " at x=" .. tostring(p3.x) .. " y=" .. tostring(p3.y) .. " z=" .. tostring(p3.z) .. groupInfo)
        trigger.action.markToAll(markerId, fullMarkerText, p3, false)
    end)
    
    if success then
        markerManager.active[groupName] = markerId
        env.info("[TOO] SUCCESS: Marker placed - ID:" .. markerId .. " Text:" .. fullMarkerText .. " Pos:(x=" .. math.floor(pos2d.x) .. ", z=" .. math.floor(pos2d.y) .. ")")
        return true
    else
        env.info("[TOO] ERROR: Failed to place marker for " .. groupName)
        return false
    end
end

local function getMarkerStatus()
    -- Return current marker status for debugging
    local status = {}
    for groupName, markerId in pairs(markerManager.active) do
        local groupExists = Group.getByName(groupName) ~= nil
        table.insert(status, {group = groupName, markerId = markerId, exists = groupExists})
    end
    return status
end

local function logMarkerStatus()
    -- Log all current markers for diagnostics
    local status = getMarkerStatus()
    if #status == 0 then
        env.info("[TOO] MARKER STATUS: No active markers")
        return
    end
    
    env.info("[TOO] MARKER STATUS: " .. #status .. " active markers")
    for _, m in ipairs(status) do
        local groupStr = m.exists and "✓ EXISTS" or "✗ DEAD"
        env.info("[TOO]  - Group: " .. m.group .. " | ID: " .. m.markerId .. " | " .. groupStr)
    end
end

local function markerManagerCleanup()
    local toRemove = {}
    
    for groupName, markerId in pairs(markerManager.active) do
        if isGroupDead(groupName) then
            -- Group is dead - remove its marker
            local success = pcall(function()
                trigger.action.removeMark(markerId)
            end)
            if success then
                env.info("[TOO] MARKER REMOVED: ID " .. markerId .. " for dead group " .. groupName)
            else
                env.info("[TOO] WARNING: Failed to remove marker ID " .. markerId .. " for group " .. groupName)
            end
            table.insert(toRemove, groupName)
        end
    end
    
    for _, groupName in ipairs(toRemove) do
        markerManager.active[groupName] = nil
    end
    
    if #toRemove > 0 then
        env.info("[TOO] Marker cleanup: Removed " .. #toRemove .. " markers for dead groups")
    end
end

local function cleanupPlayerMenus()
    -- Clean up tracking for disconnected players (groups that no longer exist)
    -- NOTE: We no longer call missionCommands.removeItem() to avoid corrupting other scripts' menus
    local toRemove = {}
    
    for groupId, menuData in pairs(TOO_PLAYER_MENUS) do
        -- Check if group still exists by trying to find it
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
            -- Group no longer exists - just remove from our tracking (don't call removeItem)
            table.insert(toRemove, groupId)
        end
    end
    
    for _, groupId in ipairs(toRemove) do
        TOO_PLAYER_MENUS[groupId] = nil
    end
    
    if #toRemove > 0 then
        env.info("[TOO] Menu cleanup: Cleared tracking for " .. #toRemove .. " disconnected players")
    end
end

-- ============================================================================
-- SPAWN FUNCTIONS
-- ============================================================================

local function spawnTargetOfOpportunity()
    if not TOO_CONFIG.enabled then 
        return 
    end
    
    -- Find an available (unoccupied) zone
    local availableZones = {}
    for _, zone in ipairs(TOO_ZONES) do
        if not occupiedZones[zone] then
            table.insert(availableZones, zone)
        end
    end
    
    if #availableZones == 0 then
        env.info("[TOO] No available zones - all occupied")
        return
    end
    
    -- Get NEXT template in sequence (1-30, then restart)
    currentTemplateIndex = currentTemplateIndex + 1
    if currentTemplateIndex > #TOO_TEMPLATES then
        currentTemplateIndex = 1
    end
    
    local template = TOO_TEMPLATES[currentTemplateIndex]
    local zoneName = getRandomElement(availableZones)
    
    if not template or not zoneName then
        env.info("[TOO] ERROR: Invalid template or zone")
        return
    end
    
    -- RETRY LOOP (like DGSS) - attempt spawn multiple times
    local MAX_ATTEMPTS = 5
    local spawnSuccess = false
    local finalGroupName = nil
    local finalPos2d = nil
    
    for attempt = 1, MAX_ATTEMPTS do
        -- Get random spawn position WITHIN the zone
        local zonePos = getRandomPositionInZone(zoneName)
        if not zonePos then
            env.info("[TOO] Attempt " .. attempt .. ": Zone position failed for " .. zoneName)
        else
            local heading = randomRange(0, 360)
            local staticIds = {}
            
            -- Spawn static buildings using DCS native API
            if template.buildings then
                for idx, building in ipairs(template.buildings) do
                    local staticX = zonePos.x + building.offset.x
                    local staticZ = zonePos.y + building.offset.y
                    local staticName = template.name .. "_static_" .. idx .. "_" .. attempt
                    
                    env.info("[TOO] DEBUG: Attempting to spawn static " .. building.type .. " at x=" .. math.floor(staticX) .. " z=" .. math.floor(staticZ) .. " name=" .. staticName)
                    
                    local success, result = pcall(function()
                        -- Get terrain altitude at this position
                        local alt = land.getHeight({x = staticX, y = staticZ}) or 0
                        alt = math.max(0, alt)
                        
                        -- Spawn static using MIST.dynAddStatic (reliable method)
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
                            
                            env.info("[TOO] DEBUG: Attempting mist.dynAddStatic for " .. building.type .. " at x=" .. math.floor(staticX) .. " z=" .. math.floor(staticZ))
                            local addResult = mist.dynAddStatic(staticData)
                            
                            if addResult and addResult.name then
                                env.info("[TOO] SUCCESS: Static " .. building.type .. " added via MIST at x=" .. math.floor(staticX) .. " z=" .. math.floor(staticZ) .. " name=" .. addResult.name)
                                return addResult.name
                            else
                                env.info("[TOO] WARNING: mist.dynAddStatic returned nil for " .. building.type)
                                return nil
                            end
                        else
                            env.info("[TOO] ERROR: mist.dynAddStatic not available")
                            return nil
                        end
                    end)
                    
                    if success and result then
                        table.insert(staticIds, result)
                    else
                        env.info("[TOO] ERROR: Failed to add static " .. building.type .. ". Error: " .. tostring(result))
                    end
                end
            end
            
            local unitCount = template.units and #template.units or 0
            if unitCount > 0 then
                -- Build unit array with 2D coordinates
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
                
                -- Build and spawn group
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
                        -- Verify group actually exists with live units
                        local groupObj = Group.getByName(addResult.name)
                        if groupObj and groupObj:isExist() then
                            local grpUnits = groupObj:getUnits()
                            if grpUnits and #grpUnits > 0 then
                                -- SPAWN SUCCESS
                                spawnSuccess = true
                                finalGroupName = addResult.name
                                finalPos2d = zonePos
                                
                                -- Register group
                                activeTargets[finalGroupName] = {
                                    name = template.name,
                                    zone = zoneName,
                                    grid = getGridReference(zonePos),
                                    heading = heading,
                                    unitCount = unitCount,
                                }
                                
                                -- Mark zone as occupied
                                occupiedZones[zoneName] = true
                                staticObjectIds[finalGroupName] = staticIds
                                destroyedBuildings[finalGroupName] = 0  -- Initialize destroyed building count
                                
                                table.insert(targetNames, finalGroupName)
                                
                                -- Place marker at first unit's ACTUAL position (not zone center)
                                local firstUnit = grpUnits[1]
                                if firstUnit and firstUnit:isExist() then
                                    local unitPos = firstUnit:getPosition()
                                    if unitPos and unitPos.p then
                                        -- Convert 3D position back to 2D for marker
                                        local markerPos2d = { x = unitPos.p.x, y = unitPos.p.z }
                                        placeMarker(finalGroupName, template.name, markerPos2d)
                                        env.info("[TOO] Marker placed at first unit position for " .. finalGroupName)
                                    else
                                        env.info("[TOO] WARNING: Could not get first unit position for marker")
                                    end
                                else
                                    env.info("[TOO] WARNING: First unit not available for marker placement")
                                end
                                env.info("[TOO] SUCCESS: Spawned " .. template.name .. " in " .. zoneName)
                                break
                            end
                        end
                    end
                else
                    env.info("[TOO] ERROR: mist.dynAdd not available - cannot spawn group")
                end
            else
                env.info("[TOO] ERROR: Template has no units")
            end
        end
    end
    
    if not spawnSuccess then
        env.info("[TOO] FAILED: All " .. MAX_ATTEMPTS .. " spawn attempts failed for " .. template.name)
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
            -- Free up the zone
            occupiedZones[targetData.zone] = nil
            env.info("[TOO DEBUG] Zone freed from occupancy: " .. targetData.zone)
        end
        
        if staticObjectIds[groupName] then
            if mist and mist.removeStatic then
                for _, staticId in ipairs(staticObjectIds[groupName]) do
                    pcall(function()
                        mist.removeStatic(staticId)
                    end)
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
        env.info("TOO: Cleaned up dead target: " .. groupName)
    end
end

-- Track destroyed buildings (scheduled function runs in better scope)
local function updateDestroyedBuildings()
    for groupName, staticIds in pairs(staticObjectIds) do
        if activeTargets[groupName] then  -- Only check active targets
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

local function maintenanceCheck()
    cleanupDeadTargets()
    markerManagerCleanup()
    cleanupPlayerMenus()  -- Remove menus for disconnected players
    updateDestroyedBuildings()  -- Update building destruction counts
    
    -- Verify all living groups still have markers
    for groupName, targetData in pairs(activeTargets) do
        if not markerManager.active[groupName] and not isGroupDead(groupName) then
            env.info("[TOO] WARNING: Living group " .. groupName .. " has no marker - reapplying")
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
    
    local activeCount = 0
    for _ in pairs(activeTargets) do
        activeCount = activeCount + 1
    end
    
    -- Spawn until we reach minTargetsOnMap
    while activeCount < TOO_CONFIG.minTargetsOnMap do
        spawnTargetOfOpportunity()
        activeCount = activeCount + 1
    end
end

local function createNineLine(groupName)
    -- Generate 9-line CAS brief matching CTLD format
    local targetData = activeTargets[groupName]
    if not targetData then 
        env.info("[TOO] createNineLine: targetData not found for " .. tostring(groupName))
        return nil 
    end
    
    local group = Group.getByName(groupName)
    if not group or not group:isExist() then 
        env.info("[TOO] createNineLine: group does not exist: " .. tostring(groupName))
        return nil 
    end
    
    -- Get target unit for bearing/distance calculation
    local units = group:getUnits()
    if not units or #units == 0 then 
        env.info("[TOO] createNineLine: no units in group " .. tostring(groupName))
        return nil 
    end
    local targetUnit = units[1]
    
    if not targetUnit or not targetUnit:isExist() then 
        env.info("[TOO] createNineLine: target unit does not exist")
        return nil 
    end
    
    local targetPos = targetUnit:getPoint()
    if not targetPos then 
        env.info("[TOO] createNineLine: could not get target position")
        return nil 
    end
    
    -- Get elevation
    local elevation = math.floor(targetPos.y or 0)
    
    -- Get target type and group info
    local targetType = "Hostile Group"
    pcall(function() targetType = targetUnit:getTypeName() or "Hostile Group" end)
    
    local unitCount = group:getSize()
    
    -- Calculate bearing from target (reference)
    local bearing = targetData.heading or 0
    
    -- Get coordinates
    local mgrs = convertToMGRS(targetPos)
    local nedm = convertToNEDM(targetPos)
    
    env.info("[TOO] createNineLine: MGRS=" .. mgrs .. ", length=" .. string.len(mgrs))
    
    -- Extract granular grid reference from MGRS for IP
    -- MGRS format: 41SPE1234567890 (no spaces)
    -- 41S = zone, PE = grid block letters (positions 4-5), 1234567890 = easting/northing digits
    if string.len(mgrs) < 13 then
        env.info("[TOO] createNineLine: MGRS string too short: " .. mgrs)
        return nil
    end
    
    local gridBlockRef = string.sub(mgrs, 4, 5)  -- Get grid letters (PE)
    local eastingFirstDigit = string.sub(mgrs, 6, 6)  -- Get first digit of easting (1)
    local northingFirstDigit = string.sub(mgrs, 11, 11)  -- Get first digit of northing (6)
    local ipGrid = gridBlockRef .. eastingFirstDigit .. northingFirstDigit  -- Result: PE16
    
    env.info("[TOO] createNineLine: gridBlockRef=" .. gridBlockRef .. ", eastingFirstDigit=" .. eastingFirstDigit .. ", northingFirstDigit=" .. northingFirstDigit .. ", ipGrid=" .. ipGrid)
    
    -- Calculate distance from grid center to target
    -- Grid center is at 5km offset from the digit boundaries (e.g., PE1 = 10-20km, center at 15km)
    -- Parse the full easting and northing from MGRS to calculate actual offset
    local easting = tonumber(string.sub(mgrs, 6, 10))  -- Extract full easting (12675)
    local northing = tonumber(string.sub(mgrs, 11, 15))  -- Extract full northing (89123)
    
    if not easting or not northing then
        env.info("[TOO] createNineLine: failed to parse easting/northing")
        return nil
    end
    
    -- Grid center is at (digit+0.5)*10000 meters within the grid
    local gridCenterEasting = (tonumber(eastingFirstDigit) + 0.5) * 10000
    local gridCenterNorthing = (tonumber(northingFirstDigit) + 0.5) * 10000
    
    -- Calculate distance from grid center to target
    local distToGridCenter = math.sqrt(
        (easting - gridCenterEasting)^2 + (northing - gridCenterNorthing)^2
    )
    local distKm = distToGridCenter / 1000  -- Convert to kilometers
    
    -- Build 9-line callout in CTLD format
    -- Format target name for display (replace underscores with spaces)
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
-- RADIO MENU SYSTEM (Dynamic slot-based approach - no menu removal needed)
-- ============================================================================

-- Track which player groups already have menus to avoid duplicates
local TOO_PLAYER_MENUS = {}

-- Helper function to get list of currently LIVING targets
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

-- Helper function to get a specific living target by slot number
local function getLivingTargetBySlot(slotNum)
    local living = getLivingTargets()
    if slotNum <= #living then
        return living[slotNum]
    end
    return nil
end

-- Create radio menu for a specific player group
-- Uses SLOT-BASED approach: Target 1, Target 2, etc. map to living targets dynamically
local function createTOOMenuForGroup(groupId)
    if not missionCommands or not groupId then return end
    
    -- Skip if already created
    if TOO_PLAYER_MENUS[groupId] then return end
    
    -- Create root "Mission Targets" menu
    local tooRoot = missionCommands.addSubMenuForGroup(groupId, "Mission Targets", nil)
    
    if not tooRoot then
        env.info("[TOO] Failed to create main menu for group " .. groupId)
        return
    end
    
    -- Store menu reference
    TOO_PLAYER_MENUS[groupId] = {
        mainMenu = tooRoot
    }
    
    env.info("[TOO] Main menu created for group " .. groupId)
    
    -- Add "List All Active Missions" command - shows real-time list
    missionCommands.addCommandForGroup(groupId, "List Active Targets", tooRoot, function()
        local living = getLivingTargets()
        
        if #living == 0 then
            trigger.action.outText("=== ACTIVE MISSIONS ===\n\nNO ACTIVE TARGETS\n\nNew targets will spawn automatically.", 15, false)
            return
        end
        
        local msg = "=== ACTIVE MISSIONS ===\nCount: " .. #living .. " targets\n\n"
        for i, t in ipairs(living) do
            local group = Group.getByName(t.groupName)
            local unitCount = group and group:getSize() or 0
            msg = msg .. "Target " .. i .. ": " .. t.data.name .. " (" .. unitCount .. " units)\n"
        end
        msg = msg .. "\n(Use Target 1-8 submenus for 9-line briefs)"
        
        trigger.action.outText(msg, 20, false)
    end)
    
    -- Create 8 numbered target slots that dynamically map to living targets
    -- These never need to be removed - they just show different targets based on what's alive
    for slot = 1, 8 do
        local slotMenu = missionCommands.addSubMenuForGroup(groupId, "Target " .. slot, tooRoot)
        
        -- Capture slot number in closure
        local slotNum = slot
        
        -- 9-Line Brief for this slot
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
                    env.info("[TOO] 9-Line displayed for slot " .. slotNum .. " (" .. target.groupName .. ")")
                else
                    trigger.action.outText("Unable to generate 9-line for Target " .. slotNum, 5, false)
                end
            end)
            
            if not success then
                env.info("[TOO] ERROR in 9-line: " .. tostring(result))
                trigger.action.outText("ERROR generating 9-line brief", 5, false)
            end
        end)
        
        -- Target Status for this slot
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
        
        -- Show which target is in this slot
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
    
    env.info("[TOO] Menu for group " .. groupId .. " created with 8 dynamic target slots")
end

-- Scan all Blue groups and add menus to players
local function updateTOOMenusForAllPlayers()
    if not missionCommands then return end
    
    local coalitionBlue = coalition.getGroups(coalition.side.BLUE)
    if not coalitionBlue then return end
    
    -- With slot-based menus, no need to track target count changes
    -- The slots dynamically map to living targets at runtime
    
    -- Scan all Blue groups
    for _, group in ipairs(coalitionBlue) do
        if group and group:isExist() then
            local groupId = group:getID()
            
            -- Check if this group has human-controlled units
            local units = group:getUnits()
            if units and #units > 0 then
                for _, unit in ipairs(units) do
                    if unit and unit:isExist() then
                        local playerName = unit:getPlayerName()
                        if playerName and playerName ~= "" then
                            -- This is a player-controlled unit
                            createTOOMenuForGroup(groupId)
                            break  -- One human player per group is enough
                        end
                    end
                end
            end
        end
    end
end

-- Initialize the radio menu system (called once at mission start)
local function initTOORadioMenuSystem()
    if not missionCommands then
        env.info("[TOO] missionCommands not available - cannot initialize radio menu")
        return false
    end
    
    env.info("[TOO] Radio menu system initialized - will create menus for players on connect")
    return true
end

-- ============================================================================
-- SCHEDULER
-- ============================================================================

local function TOO_Init()
    env.info("[TOO DEBUG] === TOO_Init called ===")
    if not TOO_CONFIG.enabled then
        env.info("TOO System: DISABLED")
        return
    end
    
    -- Check all dependencies first
    if not checkDependencies() then
        env.info("[TOO] System startup FAILED - missing required DCS APIs")
        return
    end
    
    env.info("[TOO] All dependencies verified")
    env.info("[TOO DEBUG] missionCommands available: " .. (missionCommands and "YES" or "NO"))
    env.info("[TOO] System INITIALIZED")
    env.info("[TOO] Templates: " .. #TOO_TEMPLATES)
    env.info("[TOO] Zones: " .. #TOO_ZONES)
    env.info("[TOO] Config: minTargetsOnMap=" .. TOO_CONFIG.minTargetsOnMap)
    
    -- Initialize radio menu system
    if missionCommands then
        env.info("[TOO] missionCommands available - initializing TOO radio menu system")
        initTOORadioMenuSystem()
    else
        env.info("[TOO] missionCommands not yet available - scheduling init in 5 seconds")
        timer.scheduleFunction(function()
            if missionCommands then
                env.info("[TOO] missionCommands now available - initializing")
                initTOORadioMenuSystem()
            else
                env.info("[TOO] missionCommands still not available - retrying")
                return timer.getTime() + 5
            end
        end, nil, timer.getTime() + 5)
    end
    
    -- Spawn initial targets to reach minTargetsOnMap count
    env.info("[TOO DEBUG] === Spawning " .. TOO_CONFIG.minTargetsOnMap .. " initial targets ===")
    for spawnCount = 1, TOO_CONFIG.minTargetsOnMap do
        env.info("[TOO DEBUG] Starting spawn attempt " .. spawnCount .. " of " .. TOO_CONFIG.minTargetsOnMap)
        local spawnSuccess = pcall(function()
            spawnTargetOfOpportunity()
        end)
        
        if spawnSuccess then
            env.info("TOO: Initial target " .. spawnCount .. " spawned successfully")
        else
            env.info("TOO: WARNING - Initial target " .. spawnCount .. " spawn failed")
        end
    end
    
    -- Schedule periodic menu update for all Blue players (every 10 seconds)
    -- This detects new players joining and rebuilds menus when targets change
    timer.scheduleFunction(function()
        if TOO_CONFIG.enabled and missionCommands then
            pcall(function()
                updateTOOMenusForAllPlayers()
            end)
        end
        return timer.getTime() + 10  -- Update every 10 seconds (optimized)
    end, nil, timer.getTime() + 3)
    
    -- Schedule maintenance check every 60 seconds (like DGSS)
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

-- Initialize on mission load
-- Use a small delay to ensure DCS APIs and missionCommands are fully available
local function delayedInit()
    local init_success, init_error = pcall(function()
        env.info("[TOO] Delayed init starting...")
        if missionCommands then
            env.info("[TOO] missionCommands available - proceeding with init")
            TOO_Init()
        else
            env.info("[TOO] missionCommands not available yet - scheduling retry in 2 seconds")
            timer.scheduleFunction(function()
                delayedInit()
            end, nil, timer.getTime() + 2)
        end
    end)
    
    if not init_success then
        env.info("[TOO] ERROR in delayedInit: " .. tostring(init_error))
    end
end

-- Schedule initialization for 1 second after mission loads
timer.scheduleFunction(function()
    local sched_success, sched_error = pcall(function()
        delayedInit()
    end)
    if not sched_success then
        env.info("[TOO] CRITICAL ERROR: Scheduled init failed: " .. tostring(sched_error))
    end
end, nil, timer.getTime() + 1)

-- ============================================================================
-- SCRIPT LOAD NOTIFICATION
-- ============================================================================

trigger.action.outText(
    "[TOO] Target of Opportunity System Loaded",
    12
)

env.info("[TOO] TOO System initialization complete.")

