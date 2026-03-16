--[[
    DCS World Convoy Spawn System
    Blue Resupply Convoy Management for American Vikings
    
    Compatible with: DCS World 2.9+ and MIST.lua
    
    Features:
    - 5 Convoy Templates (Armor & Logistics)
    - Radio Menu Interface for Spawn Selection
    - Automatic Player Location Detection
    - On-Road Auto-Routing to Destinations
    - Automatic Warehouse Resupply on Arrival
    - Automatic De-spawn
]]

-- ============================================================================
-- COMPATIBILITY LAYER
-- ============================================================================

local MIST_AVAILABLE = (mist ~= nil)
local DCS_VERSION = (DCS and DCS.Version) or "Unknown"

env.info("ConvoySystem: DCS World version " .. DCS_VERSION)
env.info("ConvoySystem: MIST.lua available: " .. tostring(MIST_AVAILABLE))

if not MIST_AVAILABLE then
    env.warning("ConvoySystem: MIST.lua not loaded! Some features will not work. Load mist_4_5_126.lua before this script.")
end

-- Verify MIST has critical functions
if MIST_AVAILABLE then
    if not mist.dynAdd then
        env.warning("ConvoySystem: MIST.dynAdd not available - using fallback coalition.addGroup()")
    end
    if not mist.DBs then
        env.warning("ConvoySystem: MIST.DBs not initialized - waiting for initialization")
    end
end

-- ============================================================================
-- CONFIGURATION SECTION
-- ============================================================================

local ConvoySystem = {}
ConvoySystem.spawnedConvoys = {}
ConvoySystem.despawnTimers = {}  -- Track scheduled despawn timers by convoyId

-- Leaderboard integration - track convoy requesters (commented out - no leaderboard script loaded)
-- ConvoySystem.convoyRequesters = {}  -- convoyId -> playerName
ConvoySystem.convoyRequesters = {}  -- kept as empty table to avoid nil errors

-- Cooldown and limit settings
ConvoySystem.maxActiveConvoys = 10  -- Maximum convoys on map at once
ConvoySystem.cooldownTime = 1800    -- 30 minutes in seconds (30 * 60)
ConvoySystem.templateCooldowns = {} -- Tracks last spawn time per template index
ConvoySystem.updateInterval = 300    -- Check convoys every 5 minutes (v5.7.0 performance optimization)

-- Progress notification settings
ConvoySystem.progressNotificationInterval = 120  -- Notify every 2 minutes
ConvoySystem.lastProgressNotification = 0

-- Route variation settings (procedural route generation)
ConvoySystem.routeVariation = {
    enabled = true,          -- DISABLED: All convoys take direct route for now
    -- Route type weights (higher = more likely to be picked)
    weights = {
        short = 40,           -- 40% chance: Direct route
        medium = 35,          -- 35% chance: 1 offset waypoint (moderate detour)
        long = 25,            -- 25% chance: 2 offset waypoints (longer detour)
    },
    -- Offset distances (perpendicular to direct path, in meters)
    mediumOffsetMin = 2000,   -- Minimum offset for medium route
    mediumOffsetMax = 5000,   -- Maximum offset for medium route
    longOffsetMin = 4000,     -- Minimum offset for long route
    longOffsetMax = 8000,     -- Maximum offset for long route
}

-- Player Home Base Detection Zones (must match trigger zones in mission)
ConvoySystem.homeZones = {
    "RAMAT_DAVID",
    "ROSH_PINA",
    "KIRYAT_SHMONA",
    "MEGIDDO",
    "HAIFA",
    "FOB_ALPHA",
    "FOB_BRAVO",
    "FOB_CHARLIE",
    "FOB_DELTA",
    "FOB_ECHO",
    "FOB_FOXTROT",
    "FOB_HOTEL",
    "FOB_GOLF",
    "FOB_INDIA",
    -- Syrian capturable airbases
    "MEZZEH",
    "DAMASCUS",
    "MARJ_RUHAYYIL",
    "AN_NASIRIYAH",
    "KHALKHALAH",
    "AT_TANF",
    "SAYQAL",
    "THALAH",
    "PALMYRA",
    "SHAYRAT",
    "TABQA",
    "HAMA",
    "DEIR_EZ_ZOR",
    "ALEPPO",
    "AL_QUSAYR",
    "BASSEL_AL_ASSAD",
}

-- Resupply Destination Zones (must match trigger zones in mission - typically ZONE_DEST appended)
ConvoySystem.destinationZones = {
    {name = "RAMAT_DAVID",    fullName = "Ramat David", zoneName = "RAMAT_DAVID_Spawn"},
    {name = "ROSH_PINA",      fullName = "Rosh Pina", zoneName = "ROSH_PINA_Spawn"},
    {name = "KIRYAT_SHMONA",  fullName = "Kiryat Shmona", zoneName = "KIRYAT_SHMONA_Spawn"},
    {name = "MEGIDDO",        fullName = "Megiddo", zoneName = "MEGIDDO_Spawn"},
    {name = "HAIFA",          fullName = "Haifa", zoneName = "HAIFA_Spawn"},
    {name = "FOB_ALPHA",       fullName = "FOB_Alpha", zoneName = "FOB_ALPHA_Spawn"},
    {name = "FOB_BRAVO",       fullName = "FOB_Bravo", zoneName = "FOB_BRAVO_Spawn"},
    {name = "FOB_CHARLIE", fullName = "FOB_Charlie", zoneName = "FOB_CHARLIE_Spawn"},
    {name = "FOB_DELTA", fullName = "FOB_Delta", zoneName = "FOB_DELTA_Spawn"},
    {name = "FOB_ECHO", fullName = "FOB_Echo", zoneName = "FOB_ECHO_Spawn"},
    {name = "FOB_FOXTROT", fullName = "FOB_Foxtrot", zoneName = "FOB_FOXTROT_Spawn"},
    {name = "FOB_HOTEL", fullName = "FOB_Hotel", zoneName = "FOB_HOTEL_Spawn"},
    {name = "FOB_GOLF", fullName = "FOB_Golf", zoneName = "FOB_GOLF_Spawn"},
    {name = "FOB_INDIA", fullName = "FOB_India", zoneName = "FOB_INDIA_Spawn"},
    -- Syrian capturable airbases
    {name = "MEZZEH",           fullName = "Mezzeh",           zoneName = "MEZZEH_Spawn"},
    {name = "DAMASCUS",         fullName = "Damascus",         zoneName = "DAMASCUS_Spawn"},
    {name = "MARJ_RUHAYYIL",    fullName = "Marj Ruhayyil",    zoneName = "MARJ_RUHAYYIL_Spawn"},
    {name = "AN_NASIRIYAH",     fullName = "An Nasiriyah",     zoneName = "AN_NASIRIYAH_Spawn"},
    {name = "KHALKHALAH",       fullName = "Khalkhalah",       zoneName = "KHALKHALAH_Spawn"},
    {name = "AT_TANF",          fullName = "At Tanf",          zoneName = "AT_TANF_Spawn"},
    {name = "SAYQAL",           fullName = "Sayqal",           zoneName = "SAYQAL_Spawn"},
    {name = "THALAH",           fullName = "Tha'lah",          zoneName = "THALAH_Spawn"},
    {name = "PALMYRA",          fullName = "Palmyra",          zoneName = "PALMYRA_Spawn"},
    {name = "SHAYRAT",          fullName = "Shayrat",          zoneName = "SHAYRAT_Spawn"},
    {name = "TABQA",            fullName = "Tabqa",            zoneName = "TABQA_Spawn"},
    {name = "HAMA",             fullName = "Hama",             zoneName = "HAMA_Spawn"},
    {name = "DEIR_EZ_ZOR",      fullName = "Deir ez-Zor",      zoneName = "DEIR_EZ_ZOR_Spawn"},
    {name = "ALEPPO",           fullName = "Aleppo",           zoneName = "ALEPPO_Spawn"},
    {name = "AL_QUSAYR",        fullName = "Al Qusayr",        zoneName = "AL_QUSAYR_Spawn"},
    {name = "BASSEL_AL_ASSAD",  fullName = "Bassel Al-Assad",  zoneName = "BASSEL_AL_ASSAD_Spawn"},
}

-- Spawn zones (must match trigger zones in mission)
ConvoySystem.spawnZones = {
    RAMAT_DAVID = "RAMAT_DAVID_Spawn",
    ROSH_PINA = "ROSH_PINA_Spawn",
    KIRYAT_SHMONA = "KIRYAT_SHMONA_Spawn",
    MEGIDDO = "MEGIDDO_Spawn",
    HAIFA = "HAIFA_Spawn",
    FOB_ALPHA = "FOB_ALPHA_Spawn",
    FOB_BRAVO = "FOB_BRAVO_Spawn",
    FOB_CHARLIE = "FOB_CHARLIE_Spawn",
    FOB_DELTA = "FOB_DELTA_Spawn",
    FOB_ECHO = "FOB_ECHO_Spawn",
    FOB_FOXTROT = "FOB_FOXTROT_Spawn",
    FOB_HOTEL = "FOB_HOTEL_Spawn",
    FOB_GOLF = "FOB_GOLF_Spawn",
    FOB_INDIA = "FOB_INDIA_Spawn",
    -- Syrian capturable airbases
    MEZZEH          = "MEZZEH_Spawn",
    DAMASCUS        = "DAMASCUS_Spawn",
    MARJ_RUHAYYIL   = "MARJ_RUHAYYIL_Spawn",
    AN_NASIRIYAH    = "AN_NASIRIYAH_Spawn",
    KHALKHALAH      = "KHALKHALAH_Spawn",
    AT_TANF         = "AT_TANF_Spawn",
    SAYQAL          = "SAYQAL_Spawn",
    THALAH          = "THALAH_Spawn",
    PALMYRA         = "PALMYRA_Spawn",
    SHAYRAT         = "SHAYRAT_Spawn",
    TABQA           = "TABQA_Spawn",
    HAMA            = "HAMA_Spawn",
    DEIR_EZ_ZOR     = "DEIR_EZ_ZOR_Spawn",
    ALEPPO          = "ALEPPO_Spawn",
    AL_QUSAYR       = "AL_QUSAYR_Spawn",
    BASSEL_AL_ASSAD = "BASSEL_AL_ASSAD_Spawn",
}
-- Airbase name mappings (zone name -> DCS airbase name)
-- Some zones may not have airbases, or the airbase name differs from the zone name
ConvoySystem.airbaseNames = {
    RAMAT_DAVID = "Ramat David",
    ROSH_PINA = "Rosh Pina",
    KIRYAT_SHMONA = "Kiryat Shmona",
    MEGIDDO = "Megiddo",
    HAIFA = "Haifa",
    FOB_ALPHA = "FOB_Alpha",
    FOB_BRAVO = "FOB_Bravo",
    FOB_CHARLIE = "FOB_Charlie",
    FOB_DELTA = "FOB_Delta",
    FOB_ECHO = "FOB_Echo",
    FOB_FOXTROT = "FOB_Foxtrot",
    FOB_HOTEL = "FOB_Hotel",
    FOB_GOLF = "FOB_Golf",
    FOB_INDIA = "FOB_India",
    -- Syrian capturable airbases
    MEZZEH          = "Mezzeh",
    DAMASCUS        = "Damascus",
    MARJ_RUHAYYIL   = "Marj Ruhayyil",
    AN_NASIRIYAH    = "An Nasiriyah",
    KHALKHALAH      = "Khalkhalah",
    AT_TANF         = "At Tanf",
    SAYQAL          = "Sayqal",
    THALAH          = "Tha'lah",
    PALMYRA         = "Palmyra",
    SHAYRAT         = "Shayrat",
    TABQA           = "Tabqa",
    HAMA            = "Hama",
    DEIR_EZ_ZOR     = "Deir ez-Zor",
    ALEPPO          = "Aleppo",
    AL_QUSAYR       = "Al Qusayr",
    BASSEL_AL_ASSAD = "Bassel Al-Assad",
}

-- ============================================================================
-- CONVOY TEMPLATES - 5 Different Blue Force Compositions
-- ============================================================================

ConvoySystem.templates = {
    {
        name = "Light Armor & Supply",
        description = "2x LAV-25 + 3x Supply Trucks",
        vehicles = {
            {type = "LAV-25", count = 1, side = "blue", skill = "High"},
            {type = "MaxxPro_MRAP", count = 2, side = "blue", skill = "High"},
            {type = "CHAP_M1083", count = 2, side = "blue", skill = "Excellent"},
            {type = "MaxxPro_MRAP", count = 2, side = "blue", skill = "High"},
            {type = "CHAP_M1130", count = 1, side = "blue", skill = "High"}
        }
    },
    {
        name = "Medium Armor Convoy",
        description = "4x M1A2C + 2x Supply Trucks",
        vehicles = {
            {type = "M1128 Stryker MGS", count = 1, side = "blue", skill = "High"},
            {type = "CHAP_M1130", count = 1, side = "blue", skill = "Excellent"},
            {type = "CHAP_MATV", count = 2, side = "blue", skill = "High"},
            {type = "CHAP_M1083", count = 3, side = "blue", skill = "Excellent"},
            {type = "CHAP_MATV", count = 2, side = "blue", skill = "High"},
            {type = "CHAP_M1130", count = 1, side = "blue", skill = "Excellent"},
            {type = "LAV-25", count = 1, side = "blue", skill = "High"}
        }
    },
    {
        name = "Heavy Armor Convoy",
        description = "4x Main Battle Tanks + Support",
        vehicles = {
            {type = "M1A2C_SEP_V3", count = 2, side = "blue", skill = "High"},
            {type = "MaxxPro_MRAP", count = 2, side = "blue", skill = "High"},
            {type = "CHAP_M1083", count = 2, side = "blue", skill = "High"},
            {type = "CHAP_MATV", count = 2, side = "blue", skill = "High"},
            {type = "Leopard-2", count = 2, side = "blue", skill = "High"}
        }
    },
    {
        name = "Logistics Supply Train",
        description = "Heavy Supply Focus - 2x Security + 8x Trucks",
        vehicles = {
            {type = "M1A2C_SEP_V3", count = 1, side = "blue", skill = "High"},
            {type = "LAV-25", count = 1, side = "blue", skill = "High"},
            {type = "AAV7", count = 1, side = "blue", skill = "High"},
            {type = "CHAP_M1083", count = 8, side = "blue", skill = "Excellent"},
            {type = "M1128 Stryker MGS", count = 1, side = "blue", skill = "High"},
            {type = "CHAP_M1130", count = 1, side = "blue", skill = "High"},
            {type = "M1A2C_SEP_V3", count = 1, side = "blue", skill = "High"}
        }
    },
    {
        name = "Mixed Force Convoy",
        description = "Balanced Armor & Supply - 3x Tanks + Support + Cargo",
        vehicles = {
            {type = "MaxxPro_MRAP", count = 1, side = "blue", skill = "Excellent"},
            {type = "M1A2C_SEP_V3", count = 1, side = "blue", skill = "High"},
            {type = "CHAP_MATV", count = 1, side = "blue", skill = "High"},
            {type = "CHAP_M1130", count = 1, side = "blue", skill = "High"},
            {type = "CHAP_M1083", count = 5, side = "blue", skill = "Excellent"},
            {type = "M1043 HMMWV Armament", count = 1, side = "blue", skill = "High"},
            {type = "Leopard-2", count = 1, side = "blue", skill = "High"},
            {type = "CHAP_MATV", count = 2, side = "blue", skill = "High"},
            {type = "MaxxPro_MRAP", count = 1, side = "blue", skill = "Excellent"}
        }
    }
}

-- Resupply Inventory quantities (applied to every weapon/item in warehouse)
-- Each item category gets this quantity added per successful convoy
-- Fuel is infinite on all bases, so it's not included
ConvoySystem.resupplyQuantity = 20  -- Quantity to add per equipment type

ConvoySystem.aircraftIncrementPerConvoy = 2  -- Aircraft added per successful convoy run

-- Comprehensive fallback list of weapons if warehouse query fails
-- These use the correct DCS warehouse item names from persistent warehouse data
ConvoySystem.fallbackInventory = {
    -- ========== AIR-TO-AIR MISSILES ==========
    ["weapons.missiles.AIM_120"] = 20,
    ["weapons.missiles.AIM_120C"] = 20,
    ["weapons.missiles.AIM_9"] = 20,
    ["weapons.missiles.AIM_9X"] = 20,
    ["weapons.missiles.AIM-9L"] = 20,
    ["weapons.missiles.AIM-9E"] = 20,
    ["weapons.missiles.AIM-9J"] = 20,
    ["weapons.missiles.AIM-9P"] = 20,
    ["weapons.missiles.AIM-9P3"] = 20,
    ["weapons.missiles.AIM-9P5"] = 20,
    ["weapons.missiles.AIM-9JULI"] = 20,
    ["weapons.missiles.AIM-92C"] = 20,
    ["weapons.missiles.AIM-92E"] = 20,
    ["weapons.missiles.AIM-92J"] = 20,
    ["weapons.missiles.AIM_7"] = 20,
    ["weapons.missiles.AIM-7E"] = 20,
    ["weapons.missiles.AIM-7E-2"] = 20,
    ["weapons.missiles.AIM-7F"] = 20,
    ["weapons.missiles.AIM-7MH"] = 20,
    ["weapons.missiles.AIM-7P"] = 20,
    ["weapons.missiles.AIM_54"] = 20,
    ["weapons.missiles.AIM_54A_Mk47"] = 20,
    ["weapons.missiles.AIM_54A_Mk60"] = 20,
    ["weapons.missiles.AIM_54C_Mk47"] = 20,
    ["weapons.missiles.AIM_54C_Mk60"] = 20,
    ["weapons.missiles.CATM_9M"] = 20,
    ["weapons.missiles.CATM_65K"] = 20,
    ["weapons.missiles.HB-AIM-7E"] = 20,
    ["weapons.missiles.HB-AIM-7E-2"] = 20,
    
    -- ========== FRENCH/EUROPEAN A2A ==========
    ["weapons.missiles.R_550"] = 20,
    ["weapons.missiles.R_550_M1"] = 20,
    ["weapons.missiles.R_530F_IR"] = 20,
    ["weapons.missiles.R_530F_EM"] = 20,
    ["weapons.missiles.Super_530D"] = 20,
    ["weapons.missiles.Super_530F"] = 20,
    ["weapons.missiles.Matra Super 530D"] = 20,
    ["weapons.missiles.MICA_T"] = 20,
    ["weapons.missiles.MICA_R"] = 20,
    ["weapons.missiles.MMagicII"] = 20,
    ["weapons.missiles.Mistral"] = 20,
    
    -- ========== SWEDISH A2A ==========
    ["weapons.missiles.Rb 24"] = 20,
    ["weapons.missiles.Rb 24J"] = 20,
    ["weapons.missiles.Rb 74"] = 20,
    
    -- ========== RUSSIAN A2A ==========
    ["weapons.missiles.P_60"] = 20,
    ["weapons.missiles.P_73"] = 20,
    ["weapons.missiles.P_77"] = 20,
    ["weapons.missiles.P_24R"] = 20,
    ["weapons.missiles.P_24T"] = 20,
    ["weapons.missiles.P_27P"] = 20,
    ["weapons.missiles.P_27T"] = 20,
    ["weapons.missiles.P_27PE"] = 20,
    ["weapons.missiles.P_27TE"] = 20,
    ["weapons.missiles.P_33E"] = 20,
    ["weapons.missiles.P_40R"] = 20,
    ["weapons.missiles.P_40T"] = 20,
    ["weapons.missiles.R-3R"] = 20,
    ["weapons.missiles.R-3S"] = 20,
    ["weapons.missiles.R-13M"] = 20,
    ["weapons.missiles.R-13M1"] = 20,
    ["weapons.missiles.R-55"] = 20,
    ["weapons.missiles.R-60"] = 20,
    
    -- ========== CHINESE A2A ==========
    ["weapons.missiles.PL-5EII"] = 20,
    ["weapons.missiles.PL-8A"] = 20,
    ["weapons.missiles.PL-8B"] = 20,
    ["weapons.missiles.PL-12"] = 20,
    ["weapons.missiles.SD-10"] = 20,
    
    -- ========== EARLY/VINTAGE A2A ==========
    ["weapons.missiles.GAR-8"] = 20,
    ["weapons.missiles.RS2US"] = 20,
    
    -- ========== AIR-TO-GROUND MISSILES - US ==========
    ["weapons.missiles.AGM_65A"] = 20,
    ["weapons.missiles.AGM_65B"] = 20,
    ["weapons.missiles.AGM_65D"] = 20,
    ["weapons.missiles.AGM_65E"] = 20,
    ["weapons.missiles.AGM_65F"] = 20,
    ["weapons.missiles.AGM_65G"] = 20,
    ["weapons.missiles.AGM_65H"] = 20,
    ["weapons.missiles.AGM_65K"] = 20,
    ["weapons.missiles.AGM_65L"] = 20,
    ["weapons.missiles.TGM_65D"] = 20,
    ["weapons.missiles.TGM_65G"] = 20,
    ["weapons.missiles.TGM_65H"] = 20,
    ["weapons.missiles.AGM_45A"] = 20,
    ["weapons.missiles.AGM_45B"] = 20,
    ["weapons.missiles.AGM_78A"] = 20,
    ["weapons.missiles.AGM_78B"] = 20,
    ["weapons.missiles.HB_AGM_78"] = 20,
    ["weapons.missiles.AGM_84A"] = 20,
    ["weapons.missiles.AGM_84D"] = 20,
    ["weapons.missiles.AGM_84E"] = 20,
    ["weapons.missiles.AGM_84H"] = 20,
    ["weapons.missiles.AGM_86"] = 20,
    ["weapons.missiles.AGM_86C"] = 20,
    ["weapons.missiles.AGM_88"] = 20,
    ["weapons.missiles.AGM_114"] = 20,
    ["weapons.missiles.AGM_114K"] = 20,
    ["weapons.missiles.AGM_119"] = 20,
    ["weapons.missiles.AGM_122"] = 20,
    ["weapons.missiles.AGM_130"] = 20,
    ["weapons.missiles.AGM_154"] = 20,
    ["weapons.missiles.AGM_154A"] = 20,
    ["weapons.missiles.AGM_154B"] = 20,
    ["weapons.missiles.AGR_20A"] = 20,
    ["weapons.missiles.AGR_20_M282"] = 20,
    ["weapons.missiles.AGM_12A"] = 20,
    ["weapons.missiles.AGM_12B"] = 20,
    ["weapons.missiles.AGM_12C_ED"] = 20,
    ["weapons.missiles.APKWS-II-IR"] = 20,
    ["weapons.missiles.ADM_141A"] = 20,
    ["weapons.missiles.ADM_141B"] = 20,
    ["weapons.missiles.TOW"] = 20,
    ["weapons.missiles.ASM_N_2"] = 20,
    ["weapons.missiles.SPIKE_ER"] = 20,
    ["weapons.missiles.SPIKE_ER2"] = 20,
    
    -- ========== HELLFIRE VARIANTS ==========
    ["weapons.missiles.OH58D_FIM_92"] = 20,
    
    -- ========== RUSSIAN AGM ==========
    ["weapons.missiles.X_22"] = 20,
    ["weapons.missiles.X_25ML"] = 20,
    ["weapons.missiles.X_25MP"] = 20,
    ["weapons.missiles.X_25MR"] = 20,
    ["weapons.missiles.X_28"] = 20,
    ["weapons.missiles.X_29L"] = 20,
    ["weapons.missiles.X_29T"] = 20,
    ["weapons.missiles.X_31A"] = 20,
    ["weapons.missiles.X_31P"] = 20,
    ["weapons.missiles.X_35"] = 20,
    ["weapons.missiles.X_41"] = 20,
    ["weapons.missiles.X_58"] = 20,
    ["weapons.missiles.X_59M"] = 20,
    ["weapons.missiles.X_65"] = 20,
    ["weapons.missiles.X_101"] = 20,
    ["weapons.missiles.X_555"] = 20,
    ["weapons.missiles.Kh25MP_PRGS1VP"] = 20,
    ["weapons.missiles.Kh-66_Grom"] = 20,
    ["weapons.missiles.S_25L"] = 20,
    ["weapons.missiles.Vikhr_M"] = 20,
    ["weapons.missiles.Ataka_9M120"] = 20,
    ["weapons.missiles.Ataka_9M120F"] = 20,
    ["weapons.missiles.Ataka_9M220"] = 20,
    ["weapons.missiles.AT_6"] = 20,
    ["weapons.missiles.Igla_1E"] = 20,
    
    -- ========== SWEDISH AGM ==========
    ["weapons.missiles.Rb 04E"] = 20,
    ["weapons.missiles.Rb 04E (for A.I.)"] = 20,
    ["weapons.missiles.Rb_04"] = 20,
    ["weapons.missiles.Rb 05A"] = 20,
    ["weapons.missiles.Rb 15F"] = 20,
    ["weapons.missiles.Rb 15F (for A.I.)"] = 20,
    ["weapons.missiles.RB75"] = 20,
    ["weapons.missiles.RB75B"] = 20,
    ["weapons.missiles.RB75T"] = 20,
    ["weapons.missiles.BK90_MJ1"] = 20,
    ["weapons.missiles.BK90_MJ2"] = 20,
    ["weapons.missiles.BK90_MJ1_MJ2"] = 20,
    ["weapons.missiles.DWS39_MJ1"] = 20,
    ["weapons.missiles.DWS39_MJ2"] = 20,
    ["weapons.missiles.DWS39_MJ1_MJ2"] = 20,
    
    -- ========== FRENCH AGM ==========
    ["weapons.missiles.HOT3_MBDA"] = 20,
    
    -- ========== GERMAN AGM ==========
    ["weapons.missiles.Kormoran"] = 20,
    
    -- ========== CHINESE AGM ==========
    ["weapons.missiles.C_701IR"] = 20,
    ["weapons.missiles.C_701T"] = 20,
    ["weapons.missiles.C_802AK"] = 20,
    ["weapons.missiles.CM_802AKG"] = 20,
    ["weapons.missiles.CM-802AKG"] = 20,
    ["weapons.missiles.CM-400AKG"] = 20,
    ["weapons.missiles.GB-6"] = 20,
    ["weapons.missiles.GB-6-HE"] = 20,
    ["weapons.missiles.GB-6-SFW"] = 20,
    ["weapons.missiles.KD_20"] = 20,
    ["weapons.missiles.KD_63"] = 20,
    ["weapons.missiles.KD_63B"] = 20,
    ["weapons.missiles.LS_6"] = 20,
    ["weapons.missiles.LS_6_500"] = 20,
    ["weapons.missiles.YJ-12"] = 20,
    ["weapons.missiles.YJ-83K"] = 20,
    ["weapons.missiles.AKD-10"] = 20,
    ["weapons.missiles.HJ-12"] = 20,
    ["weapons.missiles.LD-10"] = 20,
    
    -- ========== BRITISH AGM ==========
    ["weapons.missiles.ALARM"] = 20,
    ["weapons.missiles.Sea_Eagle"] = 20,
    ["weapons.missiles.BRM-1_90MM"] = 20,
    
    -- ========== GUIDED BOMBS - JDAM ==========
    ["weapons.bombs.GBU_31"] = 20,
    ["weapons.bombs.GBU_31_V_2B"] = 20,
    ["weapons.bombs.GBU_31_V_3B"] = 20,
    ["weapons.bombs.GBU_31_V_4B"] = 20,
    ["weapons.bombs.GBU_32_V_2B"] = 20,
    ["weapons.bombs.GBU_38"] = 20,
    ["weapons.bombs.GBU_39"] = 20,
    ["weapons.bombs.GBU_43"] = 20,
    ["weapons.bombs.GBU_54_V_1B"] = 20,
    
    -- ========== GUIDED BOMBS - PAVEWAY ==========
    ["weapons.bombs.GBU_10"] = 20,
    ["weapons.bombs.GBU_12"] = 20,
    ["weapons.bombs.GBU_15_V_1_B"] = 20,
    ["weapons.bombs.GBU_15_V_31_B"] = 20,
    ["weapons.bombs.GBU_16"] = 20,
    ["weapons.bombs.GBU_24"] = 20,
    ["weapons.bombs.GBU_27"] = 20,
    ["weapons.bombs.GBU_28"] = 20,
    ["weapons.bombs.GBU_8_B"] = 20,
    ["weapons.bombs.HB_F4E_GBU15V1"] = 20,
    
    -- ========== UNGUIDED BOMBS - US ==========
    ["weapons.bombs.Mk_81"] = 20,
    ["weapons.bombs.Mk_82"] = 20,
    ["weapons.bombs.Mk_82Y"] = 20,
    ["weapons.bombs.Mk_83"] = 20,
    ["weapons.bombs.Mk_83AIR"] = 20,
    ["weapons.bombs.Mk_83CT"] = 20,
    ["weapons.bombs.Mk_84"] = 20,
    ["weapons.bombs.Mk_84AIR_GP"] = 20,
    ["weapons.bombs.Mk_84AIR_TP"] = 20,
    ["weapons.bombs.MK_82AIR"] = 20,
    ["weapons.bombs.MK_82SNAKEYE"] = 20,
    ["weapons.bombs.MK-81SE"] = 20,
    ["weapons.bombs.M_117"] = 20,
    ["weapons.bombs.AN_M30A1"] = 20,
    ["weapons.bombs.AN_M57"] = 20,
    ["weapons.bombs.AN_M64"] = 20,
    ["weapons.bombs.AN_M65"] = 20,
    ["weapons.bombs.AN_M66"] = 20,
    ["weapons.bombs.AN-M66A2"] = 20,
    ["weapons.bombs.AN-M81"] = 20,
    ["weapons.bombs.AN-M88"] = 20,
    
    -- ========== CLUSTER BOMBS ==========
    ["weapons.bombs.CBU_52B"] = 20,
    ["weapons.bombs.CBU_87"] = 20,
    ["weapons.bombs.CBU_97"] = 20,
    ["weapons.bombs.CBU_99"] = 20,
    ["weapons.bombs.CBU_103"] = 20,
    ["weapons.bombs.CBU_105"] = 20,
    ["weapons.bombs.ROCKEYE"] = 20,
    ["weapons.bombs.BL_755"] = 20,
    
    -- ========== TRAINING BOMBS ==========
    ["weapons.bombs.BDU_33"] = 20,
    ["weapons.bombs.BDU_45"] = 20,
    ["weapons.bombs.BDU_45B"] = 20,
    ["weapons.bombs.BDU_45LGB"] = 20,
    ["weapons.bombs.BDU_50HD"] = 20,
    ["weapons.bombs.BDU_50LD"] = 20,
    ["weapons.bombs.BDU_50LGB"] = 20,
    ["weapons.bombs.MK76"] = 20,
    ["weapons.bombs.MK106"] = 20,
    
    -- ========== NAPALM/INCENDIARY ==========
    ["weapons.bombs.MK77mod0-WPN"] = 20,
    ["weapons.bombs.MK77mod1-WPN"] = 20,
    
    -- ========== RUSSIAN BOMBS ==========
    ["weapons.bombs.FAB_50"] = 20,
    ["weapons.bombs.FAB_100"] = 20,
    ["weapons.bombs.FAB_100M"] = 20,
    ["weapons.bombs.FAB_100SV"] = 20,
    ["weapons.bombs.FAB_250"] = 20,
    ["weapons.bombs.FAB-250M54"] = 20,
    ["weapons.bombs.FAB-250M54TU"] = 20,
    ["weapons.bombs.FAB-250-M62"] = 20,
    ["weapons.bombs.FAB_500"] = 20,
    ["weapons.bombs.FAB-500M54"] = 20,
    ["weapons.bombs.FAB-500M54TU"] = 20,
    ["weapons.bombs.FAB-500SL"] = 20,
    ["weapons.bombs.FAB-500TA"] = 20,
    ["weapons.bombs.FAB_1500"] = 20,
    ["weapons.bombs.KAB_500"] = 20,
    ["weapons.bombs.KAB_500Kr"] = 20,
    ["weapons.bombs.KAB_500S"] = 20,
    ["weapons.bombs.KAB_1500Kr"] = 20,
    ["weapons.bombs.KAB_1500LG"] = 20,
    ["weapons.bombs.KAB_1500T"] = 20,
    ["weapons.bombs.ODAB-500PM"] = 20,
    ["weapons.bombs.RBK_250"] = 20,
    ["weapons.bombs.RBK_250_275_AO_1SCH"] = 20,
    ["weapons.bombs.RBK_500AO"] = 20,
    ["weapons.bombs.RBK_500U"] = 20,
    ["weapons.bombs.RBK_500U_OAB_2_5RT"] = 20,
    ["weapons.bombs.BetAB_500"] = 20,
    ["weapons.bombs.BetAB_500ShP"] = 20,
    ["weapons.bombs.BETAB-500M"] = 20,
    ["weapons.bombs.BETAB-500S"] = 20,
    ["weapons.bombs.SAB_100MN"] = 20,
    ["weapons.bombs.SAB_250_200"] = 20,
    ["weapons.bombs.RN-24"] = 20,
    ["weapons.bombs.RN-28"] = 20,
    ["weapons.bombs.IAB-500"] = 20,
    ["weapons.bombs.OFAB-100-120TU"] = 20,
    ["weapons.bombs.OFAB-100 Jupiter"] = 20,
    
    -- ========== FRENCH BOMBS ==========
    ["weapons.bombs.SAMP125LD"] = 20,
    ["weapons.bombs.SAMP250HD"] = 20,
    ["weapons.bombs.SAMP250LD"] = 20,
    ["weapons.bombs.SAMP400HD"] = 20,
    ["weapons.bombs.SAMP400LD"] = 20,
    ["weapons.bombs.BAP_100"] = 20,
    ["weapons.bombs.BAP-100"] = 20,
    ["weapons.bombs.BAT-120"] = 20,
    ["weapons.bombs.Durandal"] = 20,
    ["weapons.bombs.BLG66"] = 20,
    ["weapons.bombs.BLG66_BELOUGA"] = 20,
    ["weapons.bombs.BLG66_EG"] = 20,
    
    -- ========== GERMAN BOMBS ==========
    ["weapons.bombs.SC_50"] = 20,
    ["weapons.bombs.SC_250_T1_L2"] = 20,
    ["weapons.bombs.SC_250_T3_J"] = 20,
    ["weapons.bombs.SC_500_J"] = 20,
    ["weapons.bombs.SC_500_L2"] = 20,
    ["weapons.bombs.SD_250_Stg"] = 20,
    ["weapons.bombs.SD_500_A"] = 20,
    ["weapons.bombs.AB_250_2_SD_2"] = 20,
    ["weapons.bombs.AB_250_2_SD_10A"] = 20,
    ["weapons.bombs.AB_500_1_SD_10A"] = 20,
    
    -- ========== BRITISH BOMBS ==========
    ["weapons.bombs.British_GP_250LB_Bomb_Mk1"] = 20,
    ["weapons.bombs.British_GP_250LB_Bomb_Mk4"] = 20,
    ["weapons.bombs.British_GP_250LB_Bomb_Mk5"] = 20,
    ["weapons.bombs.British_GP_500LB_Bomb_Mk1"] = 20,
    ["weapons.bombs.British_GP_500LB_Bomb_Mk4"] = 20,
    ["weapons.bombs.British_GP_500LB_Bomb_Mk4_Short"] = 20,
    ["weapons.bombs.British_GP_500LB_Bomb_Mk5"] = 20,
    ["weapons.bombs.British_MC_250LB_Bomb_Mk1"] = 20,
    ["weapons.bombs.British_MC_250LB_Bomb_Mk2"] = 20,
    ["weapons.bombs.British_MC_500LB_Bomb_Mk1_Short"] = 20,
    ["weapons.bombs.British_MC_500LB_Bomb_Mk2"] = 20,
    ["weapons.bombs.British_SAP_250LB_Bomb_Mk5"] = 20,
    ["weapons.bombs.British_SAP_500LB_Bomb_Mk5"] = 20,
    
    -- ========== CHINESE BOMBS ==========
    ["weapons.bombs.Type_200A"] = 20,
    ["weapons.bombs.LS_6_100"] = 20,
    ["weapons.bombs.250-2"] = 20,
    ["weapons.bombs.250-3"] = 20,
    
    -- ========== OTHER BOMBS ==========
    ["weapons.bombs.BR_250"] = 20,
    ["weapons.bombs.BR_500"] = 20,
    ["weapons.bombs.BIN_200"] = 20,
    ["weapons.bombs.P-50T"] = 20,
    ["weapons.bombs.HEBOMB"] = 20,
    ["weapons.bombs.HEBOMBD"] = 20,
    ["weapons.bombs.LUU_2B"] = 20,
    ["weapons.bombs.AGM_62"] = 20,
    ["weapons.bombs.AGM_62_I"] = 20,
    ["weapons.bombs.BEER_BOMB"] = 20,
    ["weapons.bombs.LYSBOMB 11086"] = 20,
    ["weapons.bombs.LYSBOMB 11087"] = 20,
    ["weapons.bombs.LYSBOMB 11088"] = 20,
    ["weapons.bombs.LYSBOMB 11089"] = 20,
    
    -- ========== BLU SUBMUNITIONS ==========
    ["weapons.bombs.BLU-3B_OLD"] = 20,
    ["weapons.bombs.BLU-3B_GROUP"] = 20,
    ["weapons.bombs.BLU_3B_GROUP"] = 20,
    ["weapons.bombs.BLU-3_GROUP"] = 20,
    ["weapons.bombs.BLU-4B_OLD"] = 20,
    ["weapons.bombs.BLU-4B_GROUP"] = 20,
    ["weapons.bombs.BLU_4B_GROUP"] = 20,
    
    -- ========== SMOKE GRENADES ==========
    ["weapons.bombs.OH58D_Red_Smoke_Grenade"] = 20,
    ["weapons.bombs.OH58D_Green_Smoke_Grenade"] = 20,
    ["weapons.bombs.OH58D_Blue_Smoke_Grenade"] = 20,
    ["weapons.bombs.OH58D_Yellow_Smoke_Grenade"] = 20,
    ["weapons.bombs.OH58D_White_Smoke_Grenade"] = 20,
    ["weapons.bombs.OH58D_Violet_Smoke_Grenade"] = 20,
    ["weapons.bombs.AH6_SMOKE_RED"] = 20,
    ["weapons.bombs.AH6_SMOKE_GREEN"] = 20,
    ["weapons.bombs.AH6_SMOKE_BLUE"] = 20,
    ["weapons.bombs.AH6_SMOKE_YELLOW"] = 20,
    
    -- ========== ROCKETS - HYDRA ==========
    ["weapons.nurs.HYDRA_70_M151"] = 20,
    ["weapons.nurs.HYDRA_70_M151_M433"] = 20,
    ["weapons.nurs.HYDRA_70_M156"] = 20,
    ["weapons.nurs.HYDRA_70_M229"] = 20,
    ["weapons.nurs.HYDRA_70_M257"] = 20,
    ["weapons.nurs.HYDRA_70_M259"] = 20,
    ["weapons.nurs.HYDRA_70_M274"] = 20,
    ["weapons.nurs.HYDRA_70_M282"] = 20,
    ["weapons.nurs.HYDRA_70_MK1"] = 20,
    ["weapons.nurs.HYDRA_70_MK5"] = 20,
    ["weapons.nurs.HYDRA_70_MK61"] = 20,
    ["weapons.nurs.HYDRA_70_WTU1B"] = 20,
    ["weapons.nurs.Zuni_127"] = 20,
    
    -- ========== ROCKETS - FFAR ==========
    ["weapons.nurs.FFAR Mk1 HE"] = 20,
    ["weapons.nurs.FFAR Mk5 HEAT"] = 20,
    ["weapons.nurs.FFAR M156 WP"] = 20,
    ["weapons.nurs.FFAR_Mk61"] = 20,
    
    -- ========== ROCKETS - HVAR ==========
    ["weapons.nurs.HVAR"] = 20,
    ["weapons.nurs.HVAR USN Mk28 Mod4"] = 20,
    ["weapons.nurs.Tiny Tim"] = 20,
    
    -- ========== ROCKETS - RUSSIAN ==========
    ["weapons.nurs.C_5"] = 20,
    ["weapons.nurs.C_8"] = 20,
    ["weapons.nurs.C_8CM"] = 20,
    ["weapons.nurs.C_8CM_BU"] = 20,
    ["weapons.nurs.C_8CM_GN"] = 20,
    ["weapons.nurs.C_8CM_RD"] = 20,
    ["weapons.nurs.C_8CM_VT"] = 20,
    ["weapons.nurs.C_8CM_WH"] = 20,
    ["weapons.nurs.C_8CM_YE"] = 20,
    ["weapons.nurs.C_8OFP2"] = 20,
    ["weapons.nurs.C_8OM"] = 20,
    ["weapons.nurs.C_13"] = 20,
    ["weapons.nurs.C_24"] = 20,
    ["weapons.nurs.C_25"] = 20,
    ["weapons.nurs.S_5KP"] = 20,
    ["weapons.nurs.S_5M"] = 20,
    ["weapons.nurs.S-5M"] = 20,
    ["weapons.nurs.S5M1_HEFRAG_FFAR"] = 20,
    ["weapons.nurs.S5MO_HEFRAG_FFAR"] = 20,
    ["weapons.nurs.S-24A"] = 20,
    ["weapons.nurs.S-24B"] = 20,
    ["weapons.nurs.S-25-O"] = 20,
    ["weapons.nurs.RS-82"] = 20,
    
    -- ========== ROCKETS - SNEB ==========
    ["weapons.nurs.SNEB_TYPE250_F1B"] = 20,
    ["weapons.nurs.SNEB_TYPE251_F1B"] = 20,
    ["weapons.nurs.SNEB_TYPE251_H1"] = 20,
    ["weapons.nurs.SNEB_TYPE252_F1B"] = 20,
    ["weapons.nurs.SNEB_TYPE252_H1"] = 20,
    ["weapons.nurs.SNEB_TYPE253_F1B"] = 20,
    ["weapons.nurs.SNEB_TYPE253_H1"] = 20,
    ["weapons.nurs.SNEB_TYPE254_F1B_GREEN"] = 20,
    ["weapons.nurs.SNEB_TYPE254_F1B_RED"] = 20,
    ["weapons.nurs.SNEB_TYPE254_F1B_YELLOW"] = 20,
    ["weapons.nurs.SNEB_TYPE254_H1_GREEN"] = 20,
    ["weapons.nurs.SNEB_TYPE254_H1_RED"] = 20,
    ["weapons.nurs.SNEB_TYPE254_H1_YELLOW"] = 20,
    ["weapons.nurs.SNEB_TYPE256_F1B"] = 20,
    ["weapons.nurs.SNEB_TYPE256_H1"] = 20,
    ["weapons.nurs.SNEB_TYPE257_F1B"] = 20,
    ["weapons.nurs.SNEB_TYPE257_H1"] = 20,
    ["weapons.nurs.SNEB_TYPE259E_F1B"] = 20,
    ["weapons.nurs.SNEB_TYPE259E_H1"] = 20,
    
    -- ========== ROCKETS - SWEDISH ==========
    ["weapons.nurs.ARAKM70BAP"] = 20,
    ["weapons.nurs.ARAKM70BAPPX"] = 20,
    ["weapons.nurs.ARAKM70BHE"] = 20,
    
    -- ========== ROCKETS - ITALIAN ==========
    ["weapons.nurs.ARF8M3API"] = 20,
    ["weapons.nurs.ARF8M3HEI"] = 20,
    ["weapons.nurs.ARF8M3TPSM"] = 20,
    
    -- ========== ROCKETS - BRITISH ==========
    ["weapons.nurs.British_AP_25LBNo1_3INCHNo1"] = 20,
    ["weapons.nurs.British_HE_60LBFNo1_3INCHNo1"] = 20,
    ["weapons.nurs.British_HE_60LBSAPNo2_3INCHNo1"] = 20,
    ["weapons.nurs.LWL_RP"] = 20,
    
    -- ========== ROCKETS - WWII ==========
    ["weapons.nurs.M8rocket"] = 20,
    ["weapons.nurs.WGr21"] = 20,
    ["weapons.nurs.R4M"] = 20,
    ["weapons.nurs.Rkt_90-1_HE"] = 20,
    
    -- ========== TARGETING PODS ==========
    ["weapons.containers.LANTIRN"] = 20,
    ["weapons.containers.LANTIRN-F14-TARGET"] = 20,
    ["weapons.containers.{F14-LANTIRN-TP}"] = 20,
    ["weapons.containers.F-15E_AAQ-13_LANTIRN"] = 20,
    ["weapons.containers.F-15E_AAQ-14_LANTIRN"] = 20,
    ["weapons.containers.F-15E_AAQ-28_LITENING"] = 20,
    ["weapons.containers.F-15E_AAQ-33_XR_ATP-SE"] = 20,
    ["weapons.containers.F-15E_AXQ-14_DATALINK"] = 20,
    ["weapons.containers.AAQ-28_LITENING"] = 20,
    ["weapons.containers.aaq-28LEFT litening"] = 20,
    ["weapons.containers.AN_AAQ_33"] = 20,
    ["weapons.containers.AN_ASQ_228"] = 20,
    ["weapons.containers.F-18-FLIR-POD"] = 20,
    ["weapons.containers.F-18-LDT-POD"] = 20,
    ["weapons.containers.PAVETACK"] = 20,
    ["weapons.containers.HB_ORD_Pave_Spike"] = 20,
    ["weapons.containers.HB_ORD_Pave_Spike_Fast"] = 20,
    ["weapons.containers.HB_F14_EXT_AN_APQ-167"] = 20,
    ["weapons.containers.wmd7"] = 20,
    
    -- ========== ECM PODS ==========
    ["weapons.containers.ALQ-131"] = 20,
    ["weapons.containers.ALQ-184"] = 20,
    ["weapons.containers.alq-184long"] = 20,
    ["weapons.containers.AV8BNA_ALQ164"] = 20,
    ["weapons.containers.SPS-141"] = 20,
    ["weapons.containers.SPS-141-100"] = 20,
    ["weapons.containers.SORBCIJA_L"] = 20,
    ["weapons.containers.SORBCIJA_R"] = 20,
    ["weapons.containers.BOZ-100"] = 20,
    ["weapons.containers.SKY_SHADOW"] = 20,
    ["weapons.containers.BARAX"] = 20,
    ["weapons.containers.MATRA-PHIMAT"] = 20,
    ["weapons.containers.{ECM_POD_L_175V}"] = 20,
    
    -- ========== CHAFF/FLARE DISPENSERS ==========
    ["weapons.containers.HB_ALE_40_0_0"] = 20,
    ["weapons.containers.HB_ALE_40_0_120"] = 20,
    ["weapons.containers.HB_ALE_40_15_90"] = 20,
    ["weapons.containers.HB_ALE_40_30_0"] = 20,
    ["weapons.containers.HB_ALE_40_30_60"] = 20,
    ["weapons.containers.ASO-2"] = 20,
    
    -- ========== DATA LINK / RECON PODS ==========
    ["weapons.containers.HB_F14_EXT_TARPS"] = 20,
    ["weapons.containers.HB_F14_EXT_ECA"] = 20,
    ["weapons.containers.dlpod_akg"] = 20,
    ["weapons.containers.MB339_Vinten"] = 20,
    ["weapons.containers.MB339_TravelPod"] = 20,
    ["weapons.containers.16c_hts_pod"] = 20,
    ["weapons.containers.ANAWW_13"] = 20,
    ["weapons.containers.APK-9"] = 20,
    
    -- ========== SMOKE PODS ==========
    ["weapons.containers.smoke_pod"] = 20,
    ["weapons.containers.MB339_SMOKE-POD"] = 20,
    ["weapons.containers.{SMOKE_WHITE}"] = 20,
    ["weapons.containers.{CE2_SMOKE_WHITE}"] = 20,
    ["weapons.containers.{MIG21_SMOKE_WHITE}"] = 20,
    ["weapons.containers.{MIG21_SMOKE_RED}"] = 20,
    ["weapons.containers.{F4U1D_SMOKE_WHITE}"] = 20,
    ["weapons.containers.{US_M10_SMOKE_TANK_RED}"] = 20,
    ["weapons.containers.{US_M10_SMOKE_TANK_GREEN}"] = 20,
    ["weapons.containers.{US_M10_SMOKE_TANK_BLUE}"] = 20,
    ["weapons.containers.{US_M10_SMOKE_TANK_YELLOW}"] = 20,
    ["weapons.containers.{US_M10_SMOKE_TANK_WHITE}"] = 20,
    ["weapons.containers.{US_M10_SMOKE_TANK_ORANGE}"] = 20,
    
    -- ========== MISC CONTAINERS/PODS ==========
    ["weapons.containers.FAS"] = 20,
    ["weapons.containers.U22"] = 20,
    ["weapons.containers.U22A"] = 20,
    ["weapons.containers.kg600"] = 20,
    ["weapons.containers.KBpod"] = 20,
    ["weapons.containers.SHPIL"] = 20,
    ["weapons.containers.KINGAL"] = 20,
    ["weapons.containers.TANGAZH"] = 20,
    ["weapons.containers.ETHER"] = 20,
    ["weapons.containers.Fantasm"] = 20,
    ["weapons.containers.Spear"] = 20,
    ["weapons.containers.BRD-4-250"] = 20,
    ["weapons.containers.MPS-410"] = 20,
    ["weapons.containers.IRDeflector"] = 20,
    ["weapons.containers.ah-64d_radar"] = 20,
    ["weapons.containers.sa342_dipole_antenna"] = 20,
    ["weapons.containers.ais-pod-t50_r"] = 20,
    ["weapons.containers.pl5eii"] = 20,
    ["weapons.containers.HVAR_rocket"] = 20,
    ["weapons.containers.SPRD_99Twin"] = 20,
    
    -- ========== MIRAGE 2000 SPECIFIC ==========
    ["weapons.containers.{M2KC_AAF}"] = 20,
    ["weapons.containers.{M2KC_AGF}"] = 20,
    ["weapons.containers.{Eclair}"] = 20,
    ["weapons.containers.{EclairM_06}"] = 20,
    ["weapons.containers.{EclairM_15}"] = 20,
    ["weapons.containers.{EclairM_24}"] = 20,
    ["weapons.containers.{EclairM_33}"] = 20,
    ["weapons.containers.{EclairM_42}"] = 20,
    ["weapons.containers.{EclairM_51}"] = 20,
    ["weapons.containers.{EclairM_60}"] = 20,
    
    -- ========== DROP TANKS ==========
    ["weapons.droptanks.FPU_8A"] = 20,
    ["weapons.droptanks.F-15E_Drop_Tank"] = 20,
    ["weapons.droptanks.F-15E_Drop_Tank_Empty"] = 20,
    ["weapons.droptanks.HB_F14_EXT_DROPTANK"] = 20,
    ["weapons.droptanks.HB_F14_EXT_DROPTANK_EMPTY"] = 20,
    ["weapons.droptanks.HB_A6E_AERO1D"] = 20,
    ["weapons.droptanks.HB_A6E_AERO1D_EMPTY"] = 20,
    ["weapons.droptanks.HB_A6E_D704"] = 20,
    ["weapons.droptanks.AV8BNA_AERO1D"] = 20,
    ["weapons.droptanks.AV8BNA_AERO1D_EMPTY"] = 20,
    ["weapons.droptanks.HB_F-4E_EXT_Center_Fuel_Tank"] = 20,
    ["weapons.droptanks.HB_F-4E_EXT_Center_Fuel_Tank_EMPTY"] = 20,
    ["weapons.droptanks.HB_F-4E_EXT_WingTank"] = 20,
    ["weapons.droptanks.HB_F-4E_EXT_WingTank_EMPTY"] = 20,
    ["weapons.droptanks.HB_F-4E_EXT_WingTank_R"] = 20,
    ["weapons.droptanks.HB_F-4E_EXT_WingTank_R_EMPTY"] = 20,
    ["weapons.droptanks.HB_HIGH_PERFORMANCE_CENTERLINE_600_GAL"] = 20,
    ["weapons.droptanks.PTB_1500_MIG29A"] = 20,
    ["weapons.droptanks.PTB-490-MIG21"] = 20,
    ["weapons.droptanks.PTB-490C-MIG21"] = 20,
    ["weapons.droptanks.PTB-800-MIG21"] = 20,
    ["weapons.droptanks.PTB300_MIG15"] = 20,
    ["weapons.droptanks.PTB400_MIG15"] = 20,
    ["weapons.droptanks.PTB600_MIG15"] = 20,
    ["weapons.droptanks.PTB400_MIG19"] = 20,
    ["weapons.droptanks.PTB760_MIG19"] = 20,
    ["weapons.droptanks.PTB-450"] = 20,
    ["weapons.droptanks.PTB_120_F86F35"] = 20,
    ["weapons.droptanks.PTB_200_F86F35"] = 20,
    ["weapons.droptanks.PTB_580G_F1"] = 20,
    ["weapons.droptanks.PTB_1200_F1"] = 20,
    ["weapons.droptanks.M2KC_RPL_522"] = 20,
    ["weapons.droptanks.M2KC_RPL_522_EMPTY"] = 20,
    ["weapons.droptanks.M2KC_02_RPL541"] = 20,
    ["weapons.droptanks.M2KC_02_RPL541_EMPTY"] = 20,
    ["weapons.droptanks.M2KC_08_RPL541"] = 20,
    ["weapons.droptanks.M2KC_08_RPL541_EMPTY"] = 20,
    ["weapons.droptanks.LNS_VIG_XTANK"] = 20,
    ["weapons.droptanks.800L Tank"] = 20,
    ["weapons.droptanks.800L Tank Empty"] = 20,
    ["weapons.droptanks.1100L Tank"] = 20,
    ["weapons.droptanks.1100L Tank Empty"] = 20,
    ["weapons.droptanks.FuelTank_150L"] = 20,
    ["weapons.droptanks.FuelTank_350L"] = 20,
    ["weapons.droptanks.Drop_Tank_300_Liter"] = 20,
    ["weapons.droptanks.fuel_tank_230"] = 20,
    ["weapons.droptanks.droptank_108_gal"] = 20,
    ["weapons.droptanks.droptank_110_gal"] = 20,
    ["weapons.droptanks.droptank_150_gal"] = 20,
    ["weapons.droptanks.DFT_150_GAL_A4E"] = 20,
    ["weapons.droptanks.DFT_300_GAL_A4E"] = 20,
    ["weapons.droptanks.DFT_300_GAL_A4E_LR"] = 20,
    ["weapons.droptanks.DFT_400_GAL_A4E"] = 20,
    ["weapons.droptanks.C130J_Ext_Tank_L"] = 20,
    ["weapons.droptanks.C130J_Ext_Tank_R"] = 20,
    ["weapons.droptanks.MB339_FT330"] = 20,
    ["weapons.droptanks.MB339_TT320_L"] = 20,
    ["weapons.droptanks.MB339_TT320_R"] = 20,
    ["weapons.droptanks.MB339_TT500_L"] = 20,
    ["weapons.droptanks.MB339_TT500_R"] = 20,
    ["weapons.droptanks.ah6_auxtank"] = 20,
    ["weapons.droptanks.oiltank"] = 20,
    ["weapons.droptanks.i16_eft"] = 20,
    ["weapons.droptanks.Spitfire_tank_1"] = 20,
    ["weapons.droptanks.Spitfire_slipper_tank"] = 20,
    ["weapons.droptanks.F4U-1D_Drop_Tank_Aux"] = 20,
    ["weapons.droptanks.F4U-1D_Drop_Tank_Mk5"] = 20,
    ["weapons.droptanks.F4U-1D_Drop_Tank_Mk6"] = 20,
    ["weapons.droptanks.Mosquito_Drop_Tank_50gal"] = 20,
    ["weapons.droptanks.Mosquito_Drop_Tank_100gal"] = 20,
    ["weapons.droptanks.FW-190_Fuel-Tank"] = 20,
    
    -- ========== TORPEDOES ==========
    ["weapons.torpedoes.mk46torp_name"] = 20,
    ["weapons.torpedoes.Mark_46"] = 20,
    ["weapons.torpedoes.YU-6"] = 20,
    ["weapons.torpedoes.G7A_T1"] = 20,
    ["weapons.torpedoes.LTF_5B"] = 20,
    
    -- ========== ADAPTERS ==========
    ["weapons.adapters.lau-88"] = 20,
}

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Get trigger zone position
-- DCS coordinate system: x = north-south, y = altitude, z = east-west
local function getTriggerZonePosition(zoneName)
    local zone = trigger.misc.getZone(zoneName)
    if zone then
        -- Handle different zone structures (pos vs point vs direct x/y/z)
        if zone.pos then
            return {x = zone.pos.x, y = zone.pos.y, z = zone.pos.z}
        elseif zone.point then
            return {x = zone.point.x, y = zone.point.y, z = zone.point.z}
        elseif zone.x then
            return {x = zone.x, y = zone.y or 0, z = zone.z}
        end
    end
    return nil
end

-- Get trigger zone radius
local function getTriggerZoneRadius(zoneName)
    local zone = trigger.misc.getZone(zoneName)
    if zone and zone.radius then
        env.info("ConvoySystem: Zone " .. zoneName .. " radius = " .. zone.radius)
        return zone.radius
    end
    
    -- Fallback: try without _Spawn suffix
    local cleanName = zoneName:gsub("_[Ss][Pp][Aa][Ww][Nn]$", "")
    zone = trigger.misc.getZone(cleanName)
    if zone and zone.radius then
        env.info("ConvoySystem: Zone " .. cleanName .. " radius = " .. zone.radius)
        return zone.radius
    end
    
    -- Fallback: check spawnZones mapping
    for baseName, spawnZoneName in pairs(ConvoySystem.spawnZones) do
        if zoneName == spawnZoneName or cleanName == baseName then
            zone = trigger.misc.getZone(spawnZoneName)
            if zone and zone.radius then
                env.info("ConvoySystem: Zone " .. spawnZoneName .. " (from spawnZones) radius = " .. zone.radius)
                return zone.radius
            end
        end
    end
    
    -- Default fallback radius if zone not found
    env.warning("ConvoySystem: Could not find radius for zone " .. zoneName .. ", using default 500m")
    return 500
end

-- Convert grid position to proper spawn coordinates
local function getSpawnCoordinates(zoneName)
    env.info("ConvoySystem: Looking up spawn zone: '" .. tostring(zoneName) .. "'")
    local zone = trigger.misc.getZone(zoneName)
    if not zone then
        env.warning("ConvoySystem: trigger.misc.getZone returned nil for: '" .. tostring(zoneName) .. "'")
        return nil
    end
    
    -- Debug: print all zone fields
    local zoneFields = ""
    for k, v in pairs(zone) do
        zoneFields = zoneFields .. k .. "=" .. tostring(v) .. ", "
    end
    env.info("ConvoySystem: Zone fields: " .. zoneFields)
    
    -- Handle different zone structures (pos vs point vs direct x/y/z)
    local zoneX, zoneY, zoneZ
    if zone.pos then
        zoneX = zone.pos.x
        zoneY = zone.pos.y
        zoneZ = zone.pos.z
    elseif zone.point then
        zoneX = zone.point.x
        zoneY = zone.point.y
        zoneZ = zone.point.z
    elseif zone.x then
        zoneX = zone.x
        zoneY = zone.y or 0
        zoneZ = zone.z
    else
        env.warning("ConvoySystem: Zone has no recognizable position structure!")
        return nil
    end
    
    env.info("ConvoySystem: Zone position: x=" .. tostring(zoneX) .. " y=" .. tostring(zoneY) .. " z=" .. tostring(zoneZ))
    
    -- Add random offset within zone radius to avoid stacking
    local angle = math.random() * 2 * math.pi
    local radius = math.random() * (zone.radius * 0.7)
    
    local x = zoneX + radius * math.cos(angle)
    local z = zoneZ + radius * math.sin(angle)
    
    return {x = x, y = zoneY, z = z}
end

-- Get destination for convoy (with random offset for waypoint variety)
local function getDestinationCoordinates(destZoneName)
    return getTriggerZonePosition(destZoneName)
end

-- Get zone CENTER coordinates (no random offset - for arrival detection)
local function getZoneCenterCoordinates(zoneName)
    local zone = trigger.misc.getZone(zoneName)
    if not zone then
        -- Try spawnZones mapping
        for baseName, spawnZoneName in pairs(ConvoySystem.spawnZones) do
            if zoneName == baseName or zoneName:find(baseName) then
                zone = trigger.misc.getZone(spawnZoneName)
                break
            end
        end
    end
    
    if not zone then
        env.warning("ConvoySystem: getZoneCenterCoordinates - Zone not found: " .. zoneName)
        return nil
    end
    
    local x, y, z
    if zone.point then
        x, y, z = zone.point.x, zone.point.y or 0, zone.point.z
    elseif zone.x then
        x, y, z = zone.x, zone.y or 0, zone.z
    else
        return nil
    end
    
    return {x = x, y = y, z = z}
end

-- ============================================================================
-- CONVOY SPAWNING
-- ============================================================================

-- Create a group at specified location
local function spawnConvoyGroup(templateIndex, playerCountry, spawnZoneName, destinationZoneName)
    local template = ConvoySystem.templates[templateIndex]
    if not template then
        env.warning("ConvoySystem: Template index " .. templateIndex .. " not found!")
        return false
    end
    
    local spawnPos = getSpawnCoordinates(spawnZoneName)
    if not spawnPos then
        env.warning("ConvoySystem: Spawn zone " .. spawnZoneName .. " not found!")
        return false
    end
    
    local destPos = getDestinationCoordinates(destinationZoneName)
    if not destPos then
        env.warning("ConvoySystem: Destination zone " .. destinationZoneName .. " not found!")
        return false
    end
    
    env.info("ConvoySystem: Spawning convoy from " .. spawnZoneName .. " to " .. destinationZoneName)
    env.info("ConvoySystem: Spawn pos: x=" .. spawnPos.x .. " y=" .. spawnPos.y .. " z=" .. spawnPos.z)
    env.info("ConvoySystem: Dest pos: x=" .. destPos.x .. " y=" .. destPos.y .. " z=" .. destPos.z)
    
    -- Build all units for the convoy as a single group
    local units = {}
    local unitNumber = 1
    local spacing = 8  -- Spacing between vehicles in meters (longitudinal)
    local columnSeparation = 8  -- Separation between left and right columns in meters
    
    -- Calculate heading from spawn to destination
    local dx = destPos.x - spawnPos.x
    local dz = destPos.z - spawnPos.z
    local heading = math.atan2(dz, dx)
    
    -- Calculate perpendicular offset for two-column formation
    local perpHeading = heading + math.pi / 2  -- 90 degrees to the side
    
    for _, vehicleTemplate in ipairs(template.vehicles) do
        for i = 1, vehicleTemplate.count do
            -- Determine which column (left or right) based on unit number
            local isLeftColumn = (unitNumber % 2 == 1)  -- Odd numbers = left column, even = right column
            local pairIndex = math.floor((unitNumber - 1) / 2)  -- Which pair of vehicles (0, 1, 2...)
            
            -- Calculate position: stagger back based on pair index, offset left/right based on column
            local offsetBack = pairIndex * spacing
            local lateralOffset = isLeftColumn and (-columnSeparation / 2) or (columnSeparation / 2)
            
            local unitX = spawnPos.x - offsetBack * math.cos(heading) + lateralOffset * math.cos(perpHeading)
            local unitZ = spawnPos.z - offsetBack * math.sin(heading) + lateralOffset * math.sin(perpHeading)
            
            units[unitNumber] = {
                ["skill"] = vehicleTemplate.skill,
                ["coldAtStart"] = false,
                ["type"] = vehicleTemplate.type,
                ["unitId"] = 0,
                ["y"] = unitZ,
                ["x"] = unitX,
                ["name"] = "Convoy_" .. spawnZoneName .. "_" .. math.floor(timer.getTime()) .. "_" .. unitNumber,
                ["heading"] = heading,
                ["playerCanDrive"] = false
            }
            
            env.info("ConvoySystem: Added unit " .. unitNumber .. " - " .. vehicleTemplate.type)
            unitNumber = unitNumber + 1
        end
    end
    
    local groupName = "Convoy_" .. spawnZoneName .. "_" .. destinationZoneName .. "_" .. math.floor(timer.getTime())
    
    -- Calculate route distance and direction
    local routeDistance = math.sqrt((destPos.x - spawnPos.x)^2 + (destPos.z - spawnPos.z)^2)
    local dirX = (destPos.x - spawnPos.x) / routeDistance
    local dirZ = (destPos.z - spawnPos.z) / routeDistance
    
    -- Perpendicular direction (for offset waypoints)
    local perpX = -dirZ
    local perpZ = dirX
    
    -- Select route type based on weighted random
    local routeType = "short"
    local routeTypeName = "DIRECT"
    if ConvoySystem.routeVariation.enabled then
        local weights = ConvoySystem.routeVariation.weights
        local totalWeight = weights.short + weights.medium + weights.long
        local roll = math.random() * totalWeight
        
        if roll <= weights.short then
            routeType = "short"
            routeTypeName = "DIRECT"
        elseif roll <= weights.short + weights.medium then
            routeType = "medium"
            routeTypeName = "ALTERNATE"
        else
            routeType = "long"
            routeTypeName = "EXTENDED"
        end
    end
    
    env.info("ConvoySystem: Selected route type: " .. routeTypeName .. " for convoy to " .. destinationZoneName)
    
    -- Calculate intermediate waypoints based on route type
    local intermediateWaypoints = {}
    
    if routeType == "medium" then
        -- Medium route: 1 offset waypoint at midpoint
        local cfg = ConvoySystem.routeVariation
        local offsetDist = cfg.mediumOffsetMin + math.random() * (cfg.mediumOffsetMax - cfg.mediumOffsetMin)
        local offsetDir = (math.random() > 0.5) and 1 or -1  -- Random left or right
        
        local midX = spawnPos.x + dirX * (routeDistance * 0.5)
        local midZ = spawnPos.z + dirZ * (routeDistance * 0.5)
        
        table.insert(intermediateWaypoints, {
            x = midX + perpX * offsetDist * offsetDir,
            z = midZ + perpZ * offsetDist * offsetDir
        })
        
    elseif routeType == "long" then
        -- Long route: 2 offset waypoints creating a triangle detour
        local cfg = ConvoySystem.routeVariation
        local offsetDist = cfg.longOffsetMin + math.random() * (cfg.longOffsetMax - cfg.longOffsetMin)
        local offsetDir = (math.random() > 0.5) and 1 or -1  -- Random left or right
        
        -- First waypoint at 1/3 distance
        local wp1X = spawnPos.x + dirX * (routeDistance * 0.33)
        local wp1Z = spawnPos.z + dirZ * (routeDistance * 0.33)
        table.insert(intermediateWaypoints, {
            x = wp1X + perpX * offsetDist * offsetDir,
            z = wp1Z + perpZ * offsetDist * offsetDir
        })
        
        -- Second waypoint at 2/3 distance (same side)
        local wp2X = spawnPos.x + dirX * (routeDistance * 0.66)
        local wp2Z = spawnPos.z + dirZ * (routeDistance * 0.66)
        table.insert(intermediateWaypoints, {
            x = wp2X + perpX * offsetDist * offsetDir * 0.7,  -- Slightly less offset
            z = wp2Z + perpZ * offsetDist * offsetDir * 0.7
        })
    else
        -- Short/Direct route: Add 3 intermediate waypoints along the direct path
        -- This helps DCS AI find and follow roads through mountains
        -- Waypoints at 25%, 50%, and 75% of the distance
        local wp25X = spawnPos.x + dirX * (routeDistance * 0.25)
        local wp25Z = spawnPos.z + dirZ * (routeDistance * 0.25)
        table.insert(intermediateWaypoints, {x = wp25X, z = wp25Z})
        
        local wp50X = spawnPos.x + dirX * (routeDistance * 0.50)
        local wp50Z = spawnPos.z + dirZ * (routeDistance * 0.50)
        table.insert(intermediateWaypoints, {x = wp50X, z = wp50Z})
        
        local wp75X = spawnPos.x + dirX * (routeDistance * 0.75)
        local wp75Z = spawnPos.z + dirZ * (routeDistance * 0.75)
        table.insert(intermediateWaypoints, {x = wp75X, z = wp75Z})
        
        env.info("ConvoySystem: Added 3 direct intermediate waypoints at 25%, 50%, 75% of " .. string.format("%.0f", routeDistance) .. "m route")
    end
    
    -- Calculate approach waypoint (near destination)
    local approachDistance = 200  -- 200m from destination - start slowing here
    local ratio = math.max(0, (routeDistance - approachDistance) / routeDistance)
    local approachX = spawnPos.x + (destPos.x - spawnPos.x) * ratio
    local approachZ = spawnPos.z + (destPos.z - spawnPos.z) * ratio
    
    -- Calculate a point 100m toward destination for getting on road
    local onRoadRatio = math.min(100 / routeDistance, 0.1)
    local onRoadX = spawnPos.x + (destPos.x - spawnPos.x) * onRoadRatio
    local onRoadZ = spawnPos.z + (destPos.z - spawnPos.z) * onRoadRatio
    
    -- Build route with variable waypoints
    -- WP1: Current position (Off Road) - start moving
    -- WP2: Short distance ahead (On Road) - find road
    -- WP3+: Intermediate waypoints (On Road) - route variation
    -- WP(n-1): Near destination (On Road) - approach
    -- WP(n): Final destination (Off Road) - arrive
    
    local spawnRoute = {}
    local wpIndex = 1
    
    -- WP1: Start position
    spawnRoute[wpIndex] = {
        ["alt"] = 0,
        ["type"] = "Turning Point",
        ["action"] = "On Road",
        ["alt_type"] = "BARO",
        ["x"] = spawnPos.x,
        ["y"] = spawnPos.z,
        ["speed"] = 32,
        ["speed_locked"] = true,
        ["task"] = {["id"] = "ComboTask", ["params"] = {["tasks"] = {}}}
    }
    wpIndex = wpIndex + 1
    
    -- WP2: Get on road
    spawnRoute[wpIndex] = {
        ["alt"] = 0,
        ["type"] = "Turning Point",
        ["action"] = "On Road",
        ["alt_type"] = "BARO",
        ["x"] = onRoadX,
        ["y"] = onRoadZ,
        ["speed"] = 32,
        ["speed_locked"] = true,
        ["task"] = {["id"] = "ComboTask", ["params"] = {["tasks"] = {}}}
    }
    wpIndex = wpIndex + 1
    
    -- Add intermediate waypoints (route variation)
    for _, wp in ipairs(intermediateWaypoints) do
        spawnRoute[wpIndex] = {
            ["alt"] = 0,
            ["type"] = "Turning Point",
            ["action"] = "On Road",
            ["alt_type"] = "BARO",
            ["x"] = wp.x,
            ["y"] = wp.z,
            ["speed"] = 32,
            ["speed_locked"] = true,
            ["task"] = {["id"] = "ComboTask", ["params"] = {["tasks"] = {}}}
        }
        wpIndex = wpIndex + 1
    end
    
    -- Approach waypoint (near destination) - stay on road, start slowing
    spawnRoute[wpIndex] = {
        ["alt"] = 0,
        ["type"] = "Turning Point",
        ["action"] = "On Road",
        ["alt_type"] = "BARO",
        ["x"] = approachX,
        ["y"] = approachZ,
        ["speed"] = 15,  -- Start slowing down to let convoy compress
        ["speed_locked"] = true,
        ["task"] = {["id"] = "ComboTask", ["params"] = {["tasks"] = {}}}
    }
    wpIndex = wpIndex + 1
    
    -- Pre-destination waypoint: 50m out, still on road, slow crawl
    local preDist = 50  -- 50m before destination
    local preDestX = destPos.x - (dirX * preDist)
    local preDestZ = destPos.z - (dirZ * preDist)
    
    spawnRoute[wpIndex] = {
        ["alt"] = 0,
        ["type"] = "Turning Point",
        ["action"] = "On Road",
        ["alt_type"] = "BARO",
        ["x"] = preDestX,
        ["y"] = preDestZ,
        ["speed"] = 5,  -- Slow crawl - convoy compresses together
        ["speed_locked"] = true,
        ["task"] = {["id"] = "ComboTask", ["params"] = {["tasks"] = {}}}
    }
    wpIndex = wpIndex + 1
    
    -- Final destination: on road, stop in tight formation
    spawnRoute[wpIndex] = {
        ["alt"] = 0,
        ["type"] = "Turning Point",
        ["action"] = "On Road",
        ["alt_type"] = "BARO",
        ["x"] = destPos.x,
        ["y"] = destPos.z,
        ["speed"] = 3,  -- Very slow final parking speed
        ["speed_locked"] = true,
        ["task"] = {
            ["id"] = "ComboTask",
            ["params"] = {
                ["tasks"] = {
                    [1] = {
                        ["enabled"] = true,
                        ["auto"] = false,
                        ["id"] = "WrappedAction",
                        ["number"] = 1,
                        ["params"] = {
                            ["action"] = {
                                ["id"] = "Option",
                                ["params"] = {
                                    ["name"] = 0,  -- ROE Hold Fire at destination
                                    ["value"] = 4
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    env.info("ConvoySystem: Route built with " .. wpIndex .. " waypoints (" .. routeTypeName .. ")")
    
    -- Spawn group WITH route included
    local groupData = {
        ["visible"] = true,
        ["taskSelected"] = true,
        ["route"] = {
            ["spans"] = {},
            ["points"] = spawnRoute
        },
        ["tasks"] = {},
        ["uncontrollable"] = false,
        ["hidden"] = false,
        ["units"] = units,
        ["name"] = groupName,
        ["start_time"] = 0,
        ["x"] = spawnPos.x,
        ["y"] = spawnPos.z,
        ["country"] = "USA",
        ["category"] = "vehicle"
    }
    
    env.info("ConvoySystem: Creating convoy group '" .. groupName .. "' with " .. #units .. " units and embedded route")
    
    -- Try MIST first (better integration and auto ID management)
    local result = nil
    if MIST_AVAILABLE and mist.dynAdd then
        env.info("ConvoySystem: Using MIST.dynAdd for group spawn")
        result = mist.dynAdd(groupData)
    else
        -- Fallback to coalition.addGroup if MIST unavailable
        env.info("ConvoySystem: Using coalition.addGroup for group spawn")
        groupData["country"] = country.id.USA
        result = coalition.addGroup(country.id.USA, Group.Category.GROUND, groupData)
    end
    
    local groupId = nil
    
    if result then
        -- Handle both MIST and coalition return types
        if type(result) == 'userdata' then
            -- coalition.addGroup returns Group userdata
            if result.isExist and result:isExist() then
                groupId = result:getID()
            elseif result.getID then
                groupId = result:getID()
            end
        elseif type(result) == 'table' then
            -- mist.dynAdd returns a table with the group data including assigned IDs
            if result.groupId then
                groupId = result.groupId
                env.info("ConvoySystem: MIST assigned groupId: " .. groupId)
            elseif result.name then
                -- Try to get the group by name if groupId not directly available
                local grp = Group.getByName(result.name)
                if grp and grp:isExist() then
                    groupId = grp:getID()
                    env.info("ConvoySystem: Retrieved groupId from Group.getByName: " .. groupId)
                end
            end
        end
    end
    
    if not groupId then
        env.warning("ConvoySystem: Failed to spawn convoy group - " .. groupName)
        return false
    end
    
    if groupId == 0 then
        env.warning("ConvoySystem: Invalid groupId (0) returned from spawn - attempting recovery")
        -- Try to find the group by name
        local foundGroup = Group.getByName(groupName)
        if foundGroup and foundGroup:isExist() then
            groupId = foundGroup:getID()
            env.info("ConvoySystem: Recovered valid groupId from name lookup: " .. groupId)
        else
            env.warning("ConvoySystem: Could not recover valid groupId for " .. groupName)
            return false
        end
    end
    
    -- Store convoy info for tracking (now with single group ID)
    -- Use zone CENTER for arrival detection (not random offset waypoint position)
    local zoneCenterPos = getZoneCenterCoordinates(destinationZoneName) or destPos
    local convoyId = "Convoy_" .. math.floor(timer.getTime()) .. "_" .. math.random(1000)
    ConvoySystem.spawnedConvoys[convoyId] = {
        templateIndex = templateIndex,
        groupIds = {groupId},  -- Single group now
        groupName = groupName,
        spawnZone = spawnZoneName,
        spawnPos = spawnPos,
        destinationZone = destinationZoneName,
        destinationPos = zoneCenterPos,  -- Use zone CENTER for arrival checking
        waypointDestPos = destPos,        -- Original waypoint position (may have offset)
        status = "traveling",
        createdAt = timer.getAbsTime(),
        resupplied = false,
        -- Leaderboard tracking (commented out - no leaderboard script loaded)
        -- initialUnitCount = 0,
        -- initialTotalHealth = 0,
    }
    
    --[[ Leaderboard: Record initial convoy state for scoring (commented out - no leaderboard script loaded)
    local group = Group.getByName(groupName)
    if group and group:isExist() then
        for _, unit in ipairs(group:getUnits()) do
            if unit and unit:isExist() then
                ConvoySystem.spawnedConvoys[convoyId].initialUnitCount =
                    ConvoySystem.spawnedConvoys[convoyId].initialUnitCount + 1
                local life0 = unit:getLife0()
                if life0 then
                    ConvoySystem.spawnedConvoys[convoyId].initialTotalHealth =
                        ConvoySystem.spawnedConvoys[convoyId].initialTotalHealth + life0
                end
            end
        end
    end
    --]]

    env.info(string.format("ConvoySystem: Convoy %s stored - Zone center: x=%.0f, z=%.0f | Waypoint dest: x=%.0f, z=%.0f",
        convoyId, zoneCenterPos.x, zoneCenterPos.z, destPos.x, destPos.z))
    
    -- Capture variables for closure (ensure they're available in delayed function)
    local capturedGroupName = groupName
    local capturedSpawnPos = {x = spawnPos.x, y = spawnPos.y, z = spawnPos.z}
    local capturedDestPos = {x = destPos.x, y = destPos.y, z = destPos.z}
    
    -- Delay setting AI options to allow DCS to fully initialize the group
    -- NOTE: Route is already embedded in spawn data - don't override it!
    timer.scheduleFunction(function()
        local success, err = pcall(function()
            local grp = Group.getByName(capturedGroupName)
            
            if not grp or not grp:isExist() then
                env.warning("ConvoySystem: Group " .. capturedGroupName .. " does not exist when trying to set AI options")
                return
            end
            
            env.info("ConvoySystem: Setting AI options for convoy " .. capturedGroupName)
            
            local controller = grp:getController()
            if not controller then
                env.warning("ConvoySystem: Could not get controller for group " .. capturedGroupName)
                return
            end
            
            -- Set AI behavior options only - route is already embedded in spawn data
            -- GREEN state (weapons hold) + Return Fire only (won't proactively engage IEDs)
            controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.GREEN)
            controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.RETURN_FIRE)
            controller:setOption(AI.Option.Ground.id.DISPERSE_ON_ATTACK, true)
            controller:setOption(AI.Option.Ground.id.ENGAGE_AIR_WEAPONS, false)
            
            env.info("ConvoySystem: AI options set for convoy " .. capturedGroupName .. " - convoy should now be moving on embedded route")
        end)
        
        if not success then
            env.warning("ConvoySystem: Error setting convoy AI options - " .. tostring(err))
        end
    end, nil, timer.getTime() + 3)
    
    -- Record cooldown for this template
    ConvoySystem.templateCooldowns[templateIndex] = timer.getAbsTime()
    
    env.info("ConvoySystem: Spawned convoy " .. convoyId .. " as unified group with " .. #units .. " vehicles - Template: " .. template.name)
    return convoyId  -- Return convoyId for requester tracking
end

-- ============================================================================
-- CONVOY MANAGEMENT & UPDATES
-- ============================================================================

-- Forward declarations for functions used before definition
local performWarehouseResupply
local incrementWarehouseAircraft

-- Count active convoys
local function getActiveConvoyCount()
    local count = 0
    for convoyId, convoy in pairs(ConvoySystem.spawnedConvoys) do
        if convoy.status == "traveling" then
            count = count + 1
        end
    end
    return count
end

-- Check if a template is on cooldown
local function isTemplateOnCooldown(templateIndex)
    local lastSpawn = ConvoySystem.templateCooldowns[templateIndex]
    if not lastSpawn then
        return false, 0
    end
    
    local currentTime = timer.getAbsTime()
    local elapsed = currentTime - lastSpawn
    local remaining = ConvoySystem.cooldownTime - elapsed
    
    if remaining > 0 then
        return true, remaining
    end
    return false, 0
end

-- Format seconds to MM:SS
local function formatTime(seconds)
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%02d:%02d", mins, secs)
end

-- Calculate distance between two points (2D, ignoring altitude)
local function getDistance2D(pos1, pos2)
    return math.sqrt(
        (pos1.x - pos2.x)^2 +
        (pos1.z - pos2.z)^2
    )
end

-- Send convoy progress notifications to coalition
local function sendProgressNotifications()
    local currentTime = timer.getAbsTime()
    
    -- Only send notifications at the configured interval
    if currentTime - ConvoySystem.lastProgressNotification < ConvoySystem.progressNotificationInterval then
        return
    end
    
    ConvoySystem.lastProgressNotification = currentTime
    
    local activeCount = 0
    local notifications = {}
    
    for convoyId, convoy in pairs(ConvoySystem.spawnedConvoys) do
        if convoy.status == "traveling" then
            activeCount = activeCount + 1
            
            -- Find lead vehicle and calculate progress
            local leadGroup = nil
            if convoy.groupName then
                local group = Group.getByName(convoy.groupName)
                if group and group:isExist() then
                    leadGroup = group
                end
            end
            
            if leadGroup then
                local template = ConvoySystem.templates[convoy.templateIndex]
                local leadUnit = leadGroup:getUnits()[1]
                if not leadUnit or not leadUnit:isExist() then
                    env.info("ConvoySystem: Lead unit not found for status display, skipping")
                    return
                end
                local groupPos = leadUnit:getPoint()
                local spawnPos = convoy.spawnPos or groupPos
                local destPos = convoy.destinationPos
                
                -- Calculate progress percentage
                local totalDist = getDistance2D(spawnPos, destPos)
                local remainingDist = getDistance2D(groupPos, destPos)
                local progress = 0
                if totalDist > 0 then
                    progress = math.floor(((totalDist - remainingDist) / totalDist) * 100)
                    progress = math.max(0, math.min(100, progress))  -- Clamp 0-100
                end
                
                -- Calculate ETA (rough estimate based on 10 m/s speed)
                local eta = math.floor(remainingDist / 10)  -- seconds
                
                table.insert(notifications, string.format(
                    "• %s → %s: %d%% (ETA: %s)",
                    convoy.spawnZone:gsub("_Spawn", ""),
                    convoy.destinationZone,
                    progress,
                    formatTime(eta)
                ))
            end
        end
    end
    
    -- Only show notification if there are active convoys
    if activeCount > 0 then
        local message = "═══ CONVOY STATUS ═══\n"
        message = message .. "Active: " .. activeCount .. "/" .. ConvoySystem.maxActiveConvoys .. "\n\n"
        message = message .. table.concat(notifications, "\n")
        
        trigger.action.outTextForCoalition(coalition.side.BLUE, message, 15)
        env.info("ConvoySystem: Progress notification sent - " .. activeCount .. " active convoys")
    end
end

-- Update convoy status and check for destination arrival
local function updateConvoys()
    local currentTime = timer.getAbsTime()
    local convoysToRemove = {}
    
    -- First pass: cleanup orphaned convoy entries (groups that no longer exist)
    for convoyId, convoy in pairs(ConvoySystem.spawnedConvoys) do
        local anyGroupExists = false
        
        -- Check by group name (primary method)
        if convoy.groupName then
            local group = Group.getByName(convoy.groupName)
            if group and group:isExist() then
                anyGroupExists = true
            end
        end
        
        if not anyGroupExists and not convoy.resupplied then
            table.insert(convoysToRemove, convoyId)
        end
    end
    
    local convoyCount = 0
    for _ in pairs(ConvoySystem.spawnedConvoys) do
        convoyCount = convoyCount + 1
    end

    for convoyId, convoy in pairs(ConvoySystem.spawnedConvoys) do
        
        local allGroupsDestroyed = true
        local groupCount = 0
        
        -- Get group by name
        local group = nil
        if convoy.groupName then
            group = Group.getByName(convoy.groupName)
        end
        
        if group and group:isExist() then
            groupCount = 1
            allGroupsDestroyed = false

                -- Check if group reached destination zone
                if not convoy.resupplied then
                    -- Get lead unit position (Groups don't have getPosition in DCS)
                    local leadUnit = group:getUnits()[1]
                    if leadUnit and leadUnit:isExist() then
                        local groupPos = leadUnit:getPoint()
                        
                    -- STUCK CONVOY DETECTION: Check if convoy hasn't moved from spawn after 60 seconds
                    if not convoy.lastKnownPos then
                        convoy.lastKnownPos = {x = groupPos.x, z = groupPos.z}
                        convoy.lastMoveTime = currentTime
                    else
                        local movedDist = math.sqrt((groupPos.x - convoy.lastKnownPos.x)^2 + (groupPos.z - convoy.lastKnownPos.z)^2)
                        if movedDist > 20 then  -- Moved more than 20m
                            convoy.lastKnownPos = {x = groupPos.x, z = groupPos.z}
                            convoy.lastMoveTime = currentTime
                        elseif (currentTime - (convoy.lastMoveTime or convoy.createdAt)) > 60 and not convoy.routeRetried then
                            -- Convoy hasn't moved in 60 seconds - re-push route
                            convoy.routeRetried = true
                            env.warning("ConvoySystem: Convoy " .. convoyId .. " appears STUCK (no movement for 60s) - re-pushing route!")
                            
                            local controller = group:getController()
                            if controller then
                                -- Reset and re-apply route
                                controller:resetTask()
                                
                                local routeDistance = math.sqrt((convoy.destinationPos.x - convoy.spawnPos.x)^2 + (convoy.destinationPos.z - convoy.spawnPos.z)^2)
                                local onRoadRatio = math.min(100 / routeDistance, 0.1)
                                local wp2X = convoy.spawnPos.x + (convoy.destinationPos.x - convoy.spawnPos.x) * onRoadRatio
                                local wp2Z = convoy.spawnPos.z + (convoy.destinationPos.z - convoy.spawnPos.z) * onRoadRatio
                                
                                local route = {
                                    ["points"] = {
                                        [1] = {["alt"] = 0, ["type"] = "Turning Point", ["action"] = "On Road",
                                               ["x"] = groupPos.x, ["y"] = groupPos.z, ["speed"] = 71,
                                               ["task"] = {["id"] = "ComboTask", ["params"] = {["tasks"] = {}}}},
                                        [2] = {["alt"] = 0, ["type"] = "Turning Point", ["action"] = "On Road",
                                               ["x"] = wp2X, ["y"] = wp2Z, ["speed"] = 71,
                                               ["task"] = {["id"] = "ComboTask", ["params"] = {["tasks"] = {}}}},
                                        [3] = {["alt"] = 0, ["type"] = "Turning Point", ["action"] = "On Road",
                                               ["x"] = convoy.destinationPos.x, ["y"] = convoy.destinationPos.z, ["speed"] = 71,
                                               ["task"] = {["id"] = "ComboTask", ["params"] = {["tasks"] = {}}}}
                                    }
                                }
                                controller:setTask({id = "Mission", params = {route = route}})
                                env.info("ConvoySystem: Re-pushed route for stuck convoy " .. convoyId)
                            end
                        end
                    end
                        
                    -- Use 2D distance (x,z only) for ground units - ignore altitude (y)
                    local distance = math.sqrt(
                        (groupPos.x - convoy.destinationPos.x)^2 +
                        (groupPos.z - convoy.destinationPos.z)^2
                    )
                    
                    local destZoneRadius = getTriggerZoneRadius(convoy.destinationZone)
                    -- Add buffer to zone radius for more forgiving detection
                    local effectiveRadius = destZoneRadius + 100  -- 100m buffer
                    local inZone = false

                    -- Primary check: distance-based (within zone radius + buffer)
                    if distance <= effectiveRadius then
                        inZone = true
                    -- Secondary check: close enough and stopped moving (arrived at waypoint)
                    elseif distance <= 1500 then
                        -- Check if convoy has stopped (velocity near zero)
                        local vel = leadUnit:getVelocity() or {x=0, y=0, z=0}
                        local speed = math.sqrt(vel.x*vel.x + vel.z*vel.z)
                        if speed < 2 then
                            inZone = true
                        end
                    end
                    
                    -- Tertiary check: MIST zone verification (try multiple zone name variants)
                    if not inZone and MIST_AVAILABLE and mist.pointInZone then
                        local convoyLeader = group:getUnits()[1]
                        if convoyLeader and convoyLeader:isExist() then
                            local leaderPos = convoyLeader:getPoint()
                            local mistZoneVerified = false
                            
                            -- Try original zone name (with _Spawn)
                            mistZoneVerified = mist.pointInZone(leaderPos, convoy.destinationZone)
                            
                            -- Try without _Spawn suffix
                            if not mistZoneVerified then
                                local cleanZoneName = convoy.destinationZone:gsub("_[Ss][Pp][Aa][Ww][Nn]$", "")
                                mistZoneVerified = mist.pointInZone(leaderPos, cleanZoneName)
                            end
                            
                            -- Try spawnZones mapping
                            if not mistZoneVerified then
                                for baseName, spawnZoneName in pairs(ConvoySystem.spawnZones) do
                                    if convoy.destinationZone == spawnZoneName or convoy.destinationZone:find(baseName) then
                                        mistZoneVerified = mist.pointInZone(leaderPos, spawnZoneName)
                                        if mistZoneVerified then break end
                                    end
                                end
                            end
                            
                            if mistZoneVerified then
                                inZone = true
                            end
                        end
                    end
                    
                    if inZone then
                        -- Convoy arrived at destination
                        convoy.status = "resupplying"
                        
                        env.info("ConvoySystem: *** CONVOY ARRIVED! *** Convoy " .. convoyId .. " arrived at " .. convoy.destinationZone .. 
                                 " (Distance: " .. string.format("%.0f", distance) .. "m, Zone Radius: " .. destZoneRadius .. "m)")
                        
                        -- Perform resupply only once
                        if not convoy.resupplied then
                            convoy.resupplied = true  -- set before call to prevent duplicate attempts
                            env.info("ConvoySystem: Calling performWarehouseResupply for " .. convoy.destinationZone)
                            local _resupplyOk, _resupplyErr = pcall(performWarehouseResupply, convoy.destinationZone)
                            if not _resupplyOk then
                                env.error("ConvoySystem: Resupply error for " .. convoy.destinationZone .. ": " .. tostring(_resupplyErr))
                            end
                            
                            --[[ LEADERBOARD INTEGRATION: Track convoy completion (commented out - no leaderboard script loaded)
                            local requesterName = ConvoySystem.convoyRequesters[convoyId]
                            if requesterName and DGSS_LEADERBOARD and DGSS_LEADERBOARD.addConvoyCompletion then
                                local survivingUnits = 0
                                local currentTotalHealth = 0
                                local convoyGroup = Group.getByName(convoy.groupName)
                                if convoyGroup and convoyGroup:isExist() then
                                    for _, unit in ipairs(convoyGroup:getUnits()) do
                                        if unit and unit:isExist() then
                                            survivingUnits = survivingUnits + 1
                                            local life = unit:getLife()
                                            if life then currentTotalHealth = currentTotalHealth + life end
                                        end
                                    end
                                end
                                local initialUnits = convoy.initialUnitCount or 1
                                local initialHealth = convoy.initialTotalHealth or 1
                                local survivalRate = (survivingUnits / initialUnits) * 100
                                local healthRate = (currentTotalHealth / initialHealth) * 100
                                local overallScore = (survivalRate + healthRate) / 2
                                local successState = "failed"
                                if overallScore >= 85 then successState = "full"
                                elseif overallScore >= 50 then successState = "partial" end
                                pcall(function()
                                    DGSS_LEADERBOARD.addConvoyCompletion(requesterName, successState)
                                    env.info(string.format("[ConvoySystem] Leaderboard: %s convoy for '%s' (%.0f%% score)",
                                        successState, requesterName, overallScore))
                                end)
                            end
                            --]]

                            -- Schedule destruction of ALL convoy units (they made it to destination)
                            local capturedConvoyId = convoyId
                            local capturedGroupName = convoy.groupName
                            
                            -- Cancel any existing despawn timer for this convoy
                            if ConvoySystem.despawnTimers[capturedConvoyId] then
                                timer.removeFunction(ConvoySystem.despawnTimers[capturedConvoyId])
                                env.info("ConvoySystem: Cancelled existing despawn timer for " .. capturedConvoyId)
                            end
                            
                            -- IMPORTANT: timer.scheduleFunction needs timer.getTime(), NOT timer.getAbsTime()!
                            local despawnTimer = timer.scheduleFunction(function()
                                env.info("ConvoySystem: Despawn timer triggered for " .. capturedGroupName)
                                local destroyGroup = Group.getByName(capturedGroupName)
                                
                                if destroyGroup and destroyGroup:isExist() then
                                    -- Get unit count before destroying for logging
                                    local unitCount = destroyGroup:getSize() or 0
                                    
                                    -- Destroy entire group in one atomic operation
                                    destroyGroup:destroy()
                                    
                                    env.info("ConvoySystem: Despawned convoy group " .. capturedGroupName .. " (" .. unitCount .. " units) - mission complete!")
                                else
                                    env.info("ConvoySystem: Group " .. capturedGroupName .. " already gone, cleaning up tracking only")
                                end
                                
                                -- Remove convoy from tracking regardless
                                ConvoySystem.spawnedConvoys[capturedConvoyId] = nil
                                -- ConvoySystem.convoyRequesters[capturedConvoyId] = nil  -- leaderboard (disabled)
                                ConvoySystem.despawnTimers[capturedConvoyId] = nil
                                env.info("ConvoySystem: Removed convoy " .. capturedConvoyId .. " from tracking")
                            end, nil, timer.getTime() + 10)  -- Use timer.getTime() for scheduleFunction!
                            
                            -- Track this timer
                            ConvoySystem.despawnTimers[capturedConvoyId] = despawnTimer
                        end
                    end  -- end if inZone
                else
                    -- lead unit not found this cycle
                end  -- end leadUnit check
            end  -- end if not convoy.resupplied
        else
            -- group no longer exists
        end

        -- Remove convoy if all units destroyed or timeout
        if allGroupsDestroyed then
            table.insert(convoysToRemove, convoyId)
        elseif (currentTime - convoy.createdAt) > 19800 then  -- 5.5 hour timeout for long mountain routes
            env.warning("ConvoySystem: Convoy " .. convoyId .. " exceeded 5.5 hour timeout (Age: " .. 
                       string.format("%.0f", currentTime - convoy.createdAt) .. "s) - Status: " .. convoy.status)
            table.insert(convoysToRemove, convoyId)
        end
    end
    
    -- Clean up destroyed convoys
    for _, convoyId in ipairs(convoysToRemove) do
        --[[ LEADERBOARD INTEGRATION: Track failed convoys (commented out - no leaderboard script loaded)
        local requesterName = ConvoySystem.convoyRequesters[convoyId]
        if requesterName and DGSS_LEADERBOARD and DGSS_LEADERBOARD.addConvoyCompletion then
            pcall(function()
                DGSS_LEADERBOARD.addConvoyCompletion(requesterName, "failed")
                env.info(string.format("[ConvoySystem] Leaderboard: failed convoy for '%s' (destroyed/timeout)", requesterName))
            end)
        end
        --]]

        -- Cancel any pending despawn timer
        if ConvoySystem.despawnTimers[convoyId] then
            timer.removeFunction(ConvoySystem.despawnTimers[convoyId])
            ConvoySystem.despawnTimers[convoyId] = nil
        end

        ConvoySystem.spawnedConvoys[convoyId] = nil
        -- ConvoySystem.convoyRequesters[convoyId] = nil  -- leaderboard (disabled)
    end

    --[[ Clean up stale convoy requester entries (commented out - no leaderboard script loaded)
    local requestersToClean = {}
    for convoyId, _ in pairs(ConvoySystem.convoyRequesters) do
        if not ConvoySystem.spawnedConvoys[convoyId] then
            table.insert(requestersToClean, convoyId)
        end
    end
    for _, convoyId in ipairs(requestersToClean) do
        ConvoySystem.convoyRequesters[convoyId] = nil
    end
    --]]
    
    -- Clean up stale despawn timers
    local timersToClean = {}
    for convoyId, _ in pairs(ConvoySystem.despawnTimers) do
        if not ConvoySystem.spawnedConvoys[convoyId] then
            table.insert(timersToClean, convoyId)
        end
    end
    for _, convoyId in ipairs(timersToClean) do
        ConvoySystem.despawnTimers[convoyId] = nil
    end
    
    -- Limit templateCooldowns table size (only clean every 10th update to reduce overhead)
    if not ConvoySystem.lastCooldownCleanup then
        ConvoySystem.lastCooldownCleanup = 0
    end
    ConvoySystem.lastCooldownCleanup = ConvoySystem.lastCooldownCleanup + 1
    
    if ConvoySystem.lastCooldownCleanup >= 10 then
        ConvoySystem.lastCooldownCleanup = 0
        
        local currentTime = timer.getAbsTime()
        local cooldownsToRemove = {}
        
        -- Remove cooldowns older than 2 hours (7200 seconds)
        for templateIndex, timestamp in pairs(ConvoySystem.templateCooldowns) do
            if (currentTime - timestamp) > 7200 then
                table.insert(cooldownsToRemove, templateIndex)
            end
        end
        
        for _, templateIndex in ipairs(cooldownsToRemove) do
            ConvoySystem.templateCooldowns[templateIndex] = nil
        end
        
        if #cooldownsToRemove > 0 then
            env.info("ConvoySystem: Cleaned up " .. #cooldownsToRemove .. " old template cooldown entries")
        end
    end
end

-- Perform warehouse resupply
performWarehouseResupply = function(zoneName)
    env.info("ConvoySystem: ============ WAREHOUSE RESUPPLY STARTED ============")
    env.info("ConvoySystem: Input zone name: " .. zoneName)
    
    -- Extract clean zone name (remove _Spawn or _Dest suffix, case insensitive)
    local cleanZoneName = zoneName:gsub("_[Ss][Pp][Aa][Ww][Nn]$", ""):gsub("_[Dd][Ee][Ss][Tt]$", "")
    env.info("ConvoySystem: Cleaned zone name: '" .. cleanZoneName .. "'")
    
    -- Get the actual airbase name from mapping
    local airbaseName = ConvoySystem.airbaseNames[cleanZoneName]
    if not airbaseName then
        env.warning("ConvoySystem: No airbase mapping found for zone: '" .. cleanZoneName .. "' - trying zone name directly")
        airbaseName = cleanZoneName
    end
    
    env.info("ConvoySystem: Looking for DCS airbase with name: '" .. airbaseName .. "'")
    
    local airbase = Airbase.getByName(airbaseName)
    
    -- Fallback 1: Airbase.getByName() can fail for FARP types like Single Helipad.
    -- Iterate all coalition airbases with exact, then case-insensitive, then substring match.
    if not airbase then
        env.warning("ConvoySystem: Airbase.getByName() returned nil for '" .. airbaseName .. "' - scanning all coalition airbases")
        local sides = { coalition.side.BLUE, coalition.side.RED, coalition.side.NEUTRAL }
        local allAirbases = {}
        local lowerTarget = string.lower(airbaseName)
        
        -- Collect all airbases and log them for diagnostics
        for _, side in ipairs(sides) do
            local abs = coalition.getAirbases(side)
            if abs then
                for _, ab in ipairs(abs) do
                    local abName = ab:getName()
                    table.insert(allAirbases, {ab = ab, name = abName, side = side})
                    env.info("ConvoySystem: [SCAN] Found airbase: '" .. abName .. "' (side=" .. side .. ")")
                end
            end
        end
        
        -- Pass 1: Exact name match
        for _, entry in ipairs(allAirbases) do
            if entry.name == airbaseName then
                airbase = entry.ab
                env.info("ConvoySystem: Found FARP/airbase via exact match (side=" .. entry.side .. "): " .. airbaseName)
                break
            end
        end
        
        -- Pass 2: Case-insensitive match
        if not airbase then
            for _, entry in ipairs(allAirbases) do
                if string.lower(entry.name) == lowerTarget then
                    airbase = entry.ab
                    env.info("ConvoySystem: Found FARP/airbase via case-insensitive match: '" .. entry.name .. "' (side=" .. entry.side .. ")")
                    break
                end
            end
        end
        
        -- Pass 3: Substring match (FARP name contains our target or vice versa)
        if not airbase then
            for _, entry in ipairs(allAirbases) do
                local lowerName = string.lower(entry.name)
                if string.find(lowerName, lowerTarget, 1, true) or string.find(lowerTarget, lowerName, 1, true) then
                    airbase = entry.ab
                    env.info("ConvoySystem: Found FARP/airbase via substring match: '" .. entry.name .. "' for target '" .. airbaseName .. "' (side=" .. entry.side .. ")")
                    break
                end
            end
        end
        
        -- Pass 4: Proximity-based fallback - find nearest FARP/airbase to the destination zone center
        if not airbase then
            env.warning("ConvoySystem: Name-based search failed - trying proximity search near destination zone")
            local zoneCenter = nil
            -- Try to get destination zone center position
            local destZoneNames = {zoneName, cleanZoneName .. "_Dest", cleanZoneName}
            for _, zn in ipairs(destZoneNames) do
                pcall(function()
                    if mist and mist.DBs and mist.DBs.zonesByName and mist.DBs.zonesByName[zn] then
                        zoneCenter = mist.DBs.zonesByName[zn].point
                    elseif trigger.misc.getZone then
                        local z = trigger.misc.getZone(zn)
                        if z then zoneCenter = z.point end
                    end
                end)
                if zoneCenter then break end
            end
            
            if zoneCenter then
                local closestDist = 5000  -- Max 5km search radius
                for _, entry in ipairs(allAirbases) do
                    local abPos = nil
                    pcall(function() abPos = entry.ab:getPoint() end)
                    if abPos then
                        local dx = abPos.x - zoneCenter.x
                        local dz = abPos.z - zoneCenter.z
                        local dist = math.sqrt(dx*dx + dz*dz)
                        if dist < closestDist then
                            closestDist = dist
                            airbase = entry.ab
                            env.info("ConvoySystem: Proximity match: '" .. entry.name .. "' at " .. string.format("%.0f", dist) .. "m from zone center")
                        end
                    end
                end
                if airbase then
                    env.info("ConvoySystem: Found FARP/airbase via proximity: '" .. airbase:getName() .. "' (" .. string.format("%.0f", closestDist) .. "m from zone)")
                end
            else
                env.warning("ConvoySystem: Could not find zone center for proximity search")
            end
        end
    end
    
    if not airbase then
        env.error("ConvoySystem: FAILED - Could not find airbase with name: '" .. airbaseName .. "'")
        env.error("ConvoySystem: Zone: '" .. zoneName .. "' -> Clean: '" .. cleanZoneName .. "' -> Airbase: '" .. airbaseName .. "'")
        trigger.action.outText("Convoy Arrival Failed!\nNo airbase found for " .. airbaseName .. "\nCheck DCS log for available airbases.", 15)
        return
    end
    
    env.info("ConvoySystem: SUCCESS - Found airbase object for: " .. airbaseName)
    
    local warehouse = airbase:getWarehouse()
    if not warehouse then
        env.error("ConvoySystem: FAILED - Airbase '" .. airbaseName .. "' has no warehouse!")
        env.error("ConvoySystem: This location may not support warehouse operations in DCS")
        trigger.action.outText("Convoy Arrival Failed!\n" .. airbaseName .. " has no warehouse", 15)
        return
    end
    
    env.info("ConvoySystem: Found warehouse at " .. airbaseName .. " - adding inventory")
    
    local inventory = warehouse:getInventory()
    local itemsAdded = 0
    local itemsProcessed = 0
    
    -- Top up items that already exist in the warehouse.
    -- DCS getInventory() returns { weapon = {[name]=count}, aircraft = {[name]=count}, liquids = {[name]=count} }
    if inventory and inventory.weapon then
        for itemName, currentCount in pairs(inventory.weapon) do
            if type(itemName) == "string" and type(currentCount) == "number" and currentCount > 0 then
                local addAmount = ConvoySystem.resupplyQuantity
                local ok, err = pcall(function() warehouse:addItem(itemName, addAmount) end)
                if ok then
                    itemsAdded = itemsAdded + addAmount
                    itemsProcessed = itemsProcessed + 1
                    env.info("ConvoySystem: Topped up " .. itemName .. " +" .. addAmount)
                else
                    env.warning("ConvoySystem: addItem failed for " .. itemName .. ": " .. tostring(err))
                end
            end
        end
    end
    
    -- For warehouses with no existing inventory (empty FOBs/FARPs), use the comprehensive fallback list.
    -- NOTE: warehouse:getItemCount() is NOT a DCS API method - never call it; use getInventory() only.
    if itemsProcessed == 0 then
        env.info("ConvoySystem: Warehouse empty or new - using fallback inventory list for " .. airbaseName)
        for itemName, quantity in pairs(ConvoySystem.fallbackInventory) do
            local ok = pcall(function() warehouse:addItem(itemName, quantity) end)
            if ok then
                itemsAdded = itemsAdded + quantity
            end
        end
    end
    
    env.info("ConvoySystem: Warehouse " .. airbaseName .. " resupply complete: ~" .. itemsAdded .. " items added")
    
    -- Increment all aircraft in warehouse
    local aircraftAdded = incrementWarehouseAircraft(warehouse, airbaseName, ConvoySystem.aircraftIncrementPerConvoy)
    
    -- Notify players
    trigger.action.outText(airbaseName .. " resupplied!\n+" .. itemsAdded .. " munitions\n+" .. aircraftAdded .. " aircraft", 8)
end

-- Increment all aircraft in warehouse
incrementWarehouseAircraft = function(warehouse, locationName, increment)
    if not warehouse then
        env.warning("ConvoySystem: Warehouse is nil for incrementWarehouseAircraft")
        return 0
    end
    
    local inventory = warehouse:getInventory()
    if not inventory then
        env.warning("ConvoySystem: Could not get inventory from warehouse at " .. locationName)
        return 0
    end
    
    if not inventory.aircraft then
        env.info("ConvoySystem: No aircraft in inventory at " .. locationName)
        return 0
    end
    
    local totalAircraftAdded = 0
    for key, value in pairs(inventory.aircraft) do
        -- Handle both table formats: {name = count} or {[1] = {name=..., count=...}}
        local aircraftName = nil
        
        if type(key) == "number" then
            -- Array-style: value is the aircraft name or table
            if type(value) == "string" then
                aircraftName = value
            elseif type(value) == "table" and value.name then
                aircraftName = value.name
            else
                env.info("ConvoySystem: Skipping aircraft entry with numeric key, value type: " .. type(value))
            end
        else
            -- Key-value style: key is aircraft name, value is count
            aircraftName = key
        end
        
        if aircraftName and type(aircraftName) == "string" then
            local ok, err = pcall(function() warehouse:addItem(aircraftName, increment) end)
            if ok then
                totalAircraftAdded = totalAircraftAdded + increment
                env.info("ConvoySystem: Added " .. increment .. " x " .. aircraftName .. " to warehouse at " .. locationName)
            else
                env.info("ConvoySystem: Could not add aircraft " .. tostring(aircraftName) .. ": " .. tostring(err))
            end
        end
    end
    
    env.info("ConvoySystem: Incremented " .. totalAircraftAdded .. " total aircraft at " .. locationName)
    return totalAircraftAdded
end

-- ============================================================================
-- MAIN LOOP
-- ============================================================================

-- Start the convoy management system
local ConvoySystemStarted = false

local function startConvoySystem()
    if ConvoySystemStarted then
        env.warning("ConvoySystem: startConvoySystem called but system already started!")
        return
    end
    
    ConvoySystemStarted = true
    env.info("ConvoySystem: ============ SYSTEM INITIALIZATION STARTED ============")
    
    -- Schedule regular updates with error protection
    local function convoyUpdateLoop(args, time)
        local success, err = pcall(function()
            updateConvoys()
            sendProgressNotifications()
        end)

        if not success then
            env.error("ConvoySystem: ERROR in update loop: " .. tostring(err))
        end

        -- Reschedule for next update
        return time + ConvoySystem.updateInterval
    end
    
    local startTime = timer.getTime() + ConvoySystem.updateInterval
    env.info("ConvoySystem: Scheduling first update loop at time " .. tostring(startTime) .. " (current time: " .. tostring(timer.getTime()) .. ")")
    timer.scheduleFunction(convoyUpdateLoop, nil, startTime)
    
    env.info("ConvoySystem: Convoy update timer scheduled (interval: " .. ConvoySystem.updateInterval .. "s)")
    
    -- ========================================================================
    -- ========================================================================
    -- COALITION-WIDE RADIO MENU  (Paged — max 9 items per menu level)
    -- ========================================================================
    -- Flow (same as old menu, pagination added at zone list levels):
    --
    --   F10 → Convoy Operations
    --           → [Template Name]
    --               → Spawn From: Page 1  (up to 9 origin zones)
    --                   → Zone Name       (origin selected)
    --                       → Send To: Page 1  (up to 9 destinations)
    --                           → Zone Name    ← spawns the convoy
    --                       → Send To: Page 2
    --                       → Send To: Page 3
    --               → Spawn From: Page 2
    --               → Spawn From: Page 3
    --
    -- PAGE_SIZE = 9 keeps every menu safely within DCS's 10-item limit.
    -- All pages are built statically at mission start.
    -- ========================================================================

    local PAGE_SIZE     = 9
    local blueCoalition = coalition.side.BLUE

    env.info("ConvoySystem: Building paged coalition radio menu for BLUE")

    local allZones = ConvoySystem.destinationZones

    -- Split a list into pages of PAGE_SIZE
    local function makePages(list)
        local pages = {}
        local i = 1
        while i <= #list do
            local page = {}
            for j = i, math.min(i + PAGE_SIZE - 1, #list) do
                page[#page + 1] = list[j]
            end
            pages[#pages + 1] = page
            i = i + PAGE_SIZE
        end
        return pages
    end

    -- Check if an origin zone is currently RED-owned via the ABC capture system.
    -- Returns true (block) only when ABC is loaded AND the zone explicitly returns "RED".
    -- Zones not registered in ABC (e.g. permanent Israeli airbases) return false → always allowed.
    local function isZoneRedOwned(zoneName)
        if not ABC or type(ABC.getOwner) ~= "function" then return false end
        local dcsName = ConvoySystem.airbaseNames[zoneName]
        if not dcsName then return false end
        return ABC.getOwner(dcsName) == "RED"
    end

    --[[ Leaderboard: Find player name for requester tracking (commented out - no leaderboard script loaded)
    local function findRequesterName()
        local cats = { Group.Category.AIRPLANE, Group.Category.HELICOPTER }
        for _, cat in ipairs(cats) do
            for _, grp in ipairs(coalition.getGroups(blueCoalition, cat) or {}) do
                if grp and grp:isExist() then
                    for _, unit in ipairs(grp:getUnits() or {}) do
                        if unit and unit:isExist() and unit:getPlayerName() then
                            return unit:getPlayerName()
                        end
                    end
                end
            end
        end
        return "Unknown"
    end
    --]]

    local zonePages = makePages(allZones)
    local numZonePages = #zonePages

    -- Root menu
    local convoyRootMenu = missionCommands.addSubMenuForCoalition(blueCoalition, "Convoy Operations")
    env.info("ConvoySystem: Created root menu 'Convoy Operations'")

    -- ── Template level ──────────────────────────────────────────────────────
    for templateIndex, template in ipairs(ConvoySystem.templates) do
        local templateMenu = missionCommands.addSubMenuForCoalition(
            blueCoalition, template.name, convoyRootMenu)

        -- ── Origin page level ────────────────────────────────────────────────
        for originPageNum, originPage in ipairs(zonePages) do
            local originPageLabel = (numZonePages > 1)
                and ("Spawn From: Page " .. originPageNum)
                or  "Spawn From..."

            local originPageMenu = missionCommands.addSubMenuForCoalition(
                blueCoalition, originPageLabel, templateMenu)

            -- ── Individual origin zone ───────────────────────────────────────
            for _, originZone in ipairs(originPage) do
                local spawnZoneName = ConvoySystem.spawnZones[originZone.name]
                local originMenu = missionCommands.addSubMenuForCoalition(
                    blueCoalition, originZone.fullName, originPageMenu)

                -- ── Destination page level ───────────────────────────────────
                for destPageNum, destPage in ipairs(zonePages) do

                    local validDests = {}
                    for _, dest in ipairs(destPage) do
                        if dest.name ~= originZone.name then
                            validDests[#validDests + 1] = dest
                        end
                    end

                    if #validDests > 0 then
                        local destPageLabel = (numZonePages > 1)
                            and ("Send To: Page " .. destPageNum)
                            or  "Send To..."

                        local destPageMenu = missionCommands.addSubMenuForCoalition(
                            blueCoalition, destPageLabel, originMenu)

                        -- ── Destination command ──────────────────────────────
                        for _, destination in ipairs(validDests) do
                            local capOriginName = originZone.name
                            local capOriginFull = originZone.fullName
                            local capSpawnZone  = spawnZoneName
                            local capDest       = destination
                            local capTplIndex   = templateIndex
                            local capTplName    = template.name

                            missionCommands.addCommandForCoalition(
                                blueCoalition,
                                destination.fullName,
                                destPageMenu,
                                function()
                                    -- Max convoy limit check
                                    local activeCount = getActiveConvoyCount()
                                    if activeCount >= ConvoySystem.maxActiveConvoys then
                                        trigger.action.outTextForCoalition(
                                            blueCoalition,
                                            "CONVOY LIMIT REACHED!\nMaximum " ..
                                            ConvoySystem.maxActiveConvoys ..
                                            " convoys allowed.\nWait for a convoy to arrive or be destroyed.",
                                            10
                                        )
                                        env.info("ConvoySystem: Spawn blocked - max convoys reached (" ..
                                                 activeCount .. "/" .. ConvoySystem.maxActiveConvoys .. ")")
                                        return
                                    end

                                    -- Cooldown check
                                    local onCooldown, remaining = isTemplateOnCooldown(capTplIndex)
                                    if onCooldown then
                                        trigger.action.outTextForCoalition(
                                            blueCoalition,
                                            capTplName .. " ON COOLDOWN!\nAvailable in: " ..
                                            formatTime(remaining),
                                            10
                                        )
                                        env.info("ConvoySystem: Spawn blocked - template " .. capTplIndex ..
                                                 " on cooldown (" .. formatTime(remaining) .. " remaining)")
                                        return
                                    end

                                    -- Ownership check: block spawn from RED-held zones
                                    if isZoneRedOwned(capOriginName) then
                                        trigger.action.outTextForCoalition(
                                            blueCoalition,
                                            "SPAWN DENIED!\n" .. capOriginFull ..
                                            " is currently under RED control.\nCapture it first before dispatching convoys from here.",
                                            12
                                        )
                                        env.info("ConvoySystem: Spawn blocked - " .. capOriginName ..
                                                 " is RED-owned")
                                        return
                                    end

                                    -- Spawn zone sanity check
                                    if not capSpawnZone then
                                        trigger.action.outTextForCoalition(
                                            blueCoalition,
                                            "No spawn zone defined for " .. capOriginName .. "!",
                                            10
                                        )
                                        env.warning("ConvoySystem: No spawnZone entry for " .. capOriginName)
                                        return
                                    end

                                    env.info("ConvoySystem: Menu command - Template: " .. capTplIndex ..
                                             ", From: " .. capOriginName ..
                                             ", To: " .. capDest.zoneName)

                                    -- Spawn
                                    local ok, result = pcall(function()
                                        return spawnConvoyGroup(capTplIndex, blueCoalition,
                                                                capSpawnZone, capDest.zoneName)
                                    end)

                                    if not ok then
                                        env.error("ConvoySystem: SPAWN ERROR - " .. tostring(result))
                                        trigger.action.outTextForCoalition(
                                            blueCoalition, "Convoy spawn error! Check DCS log.", 10)
                                        return
                                    end

                                    local convoyId = result

                                    if convoyId then
                                        -- Leaderboard requester tracking (commented out - no leaderboard script loaded)
                                        -- local requesterName = findRequesterName()
                                        -- ConvoySystem.convoyRequesters[convoyId] = requesterName
                                        -- env.info("ConvoySystem: Convoy " .. convoyId .. " requested by: " .. requesterName)

                                        local msg = "Convoy Dispatched!\n" .. capTplName ..
                                                    "\nFrom: " .. capOriginFull ..
                                                    "\nDestination: " .. capDest.fullName
                                        trigger.action.outTextForCoalition(blueCoalition, msg, 10)
                                        env.info("ConvoySystem: " .. msg:gsub("\n", " | "))
                                    else
                                        trigger.action.outTextForCoalition(
                                            blueCoalition,
                                            "Failed to spawn convoy from " .. capOriginName ..
                                            "!\nCheck that spawn zone exists in ME.",
                                            10
                                        )
                                        env.warning("ConvoySystem: Failed to spawn convoy from " ..
                                                    capOriginName)
                                    end
                                end
                            )
                        end  -- destination loop
                    end  -- validDests guard
                end  -- dest page loop
            end  -- origin zone loop
        end  -- origin page loop
    end  -- template loop

    env.info("ConvoySystem: Paged coalition radio menu initialization complete")
    
    env.info("ConvoySystem: ============ SYSTEM INITIALIZATION COMPLETE ============")
end

-- Start system on load
startConvoySystem()

env.info("ConvoySystem: Script loaded successfully")
