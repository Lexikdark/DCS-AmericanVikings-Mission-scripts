-- =========================================================
-- DCS World: Dynamic Insurgent Zone Spawner (Russia Version)
-- Polygon‑Safe + Global Shuffle Bag
-- With marker tracking and proper cleanup
-- =========================================================

env.info("=== [DEBUG] Dynamic Insurgent Zone Spawner LOADED ===")

-------------------------------------------------------------
-- Forward declarations
-------------------------------------------------------------

local spawnGroupInZone  -- Forward declare for use in callbacks

-------------------------------------------------------------
-- 20 Insurgent Group Templates (Valid for Russia)
-------------------------------------------------------------

local INSURGENT_TEMPLATES = {
    {
        name = "Ins_1",
        units = {
            { type="T-55",              dx=0.0,   dy=0.0,   heading=0.0 },
            { type="HL_KORD",            dx=28.0,  dy=-14.0, heading=0.3 },
            { type="Grad-URAL",         dx=-32.0, dy=18.0,  heading=0.5 },
            { type="Ural-375 ZU-23",    dx=17.0,  dy=27.0,  heading=1.0 },
            { type="SA-18 Igla manpad", dx=-14.0, dy=-26.0, heading=0.8 },
            { type="HL_KORD",           dx=35.0,  dy=9.0,   heading=0.2 },
            { type="Soldier RPG",       dx=9.0,   dy=-30.0, heading=1.2 },
            { type="Soldier AK",        dx=-10.0, dy=32.0,  heading=1.5 },
            { type="Soldier AK",        dx=6.0,   dy=38.0,  heading=0.1 },
        }
    },
    {
        name = "Ins_2",
        units = {
            { type="HL_DSHK",           dx=0.0,   dy=0.0,   heading=0.0 },
            { type="BTR-60",            dx=24.0,  dy=-16.0, heading=0.4 },
            { type="HL_ZU-23",          dx=18.0,  dy=26.0,  heading=1.0 },
            { type="Soldier RPG",       dx=-8.0,  dy=30.0,  heading=1.1 },
            { type="SA-18 Igla manpad", dx=-20.0, dy=-24.0, heading=1.2 },
            { type="Infantry AK Ins",        dx=4.0,   dy=36.0,  heading=0.0 },
        }
    },
    {
        name = "Ins_3",
        isEngagement = true,
        red_units = {
            { type="HL_KORD",           dx=0.0,   dy=0.0 },
            { type="HL_KORD",           dx=15.0,  dy=-8.0 },
            { type="Infantry AK Ins",   dx=-10.0, dy=12.0 },
            { type="Infantry AK Ins",   dx=8.0,   dy=15.0 },
            { type="Infantry AK Ins",   dx=-15.0, dy=-10.0 },
            { type="Infantry AK Ins",   dx=12.0,  dy=-15.0 },
            { type="Infantry AK Ins",   dx=-8.0,  dy=18.0 },
            { type="Infantry AK Ins",   dx=10.0,  dy=-12.0 },
            { type="Infantry AK Ins",   dx=-12.0, dy=8.0 },
            { type="Infantry AK Ins",   dx=5.0,   dy=20.0 },
        },
        blue_units = {
            { type="CHAP_MATV",   dx=0.0,  dy=0.0 },
            { type="CHAP_MATV",   dx=15.0,  dy=-12.0 },
            { type="CHAP_MATV",   dx=30.0, dy=8.0 },
            { type="Soldier M4",        dx=8.0,  dy=15.0 },
            { type="Soldier M4",        dx=22.0, dy=-18.0 },
            { type="Soldier M4",        dx=35.0, dy=5.0 },
            { type="Soldier M4",        dx=12.0,  dy=-10.0 },
            { type="Soldier M4",        dx=25.0, dy=18.0 },
            { type="Soldier M4",        dx=18.0,  dy=8.0 },
            { type="Soldier M4",        dx=32.0, dy=-8.0 },
            { type="Soldier M4",        dx=5.0,  dy=-15.0 },
            { type="Soldier M249",      dx=20.0, dy=12.0 },
            { type="Soldier M249",      dx=28.0, dy=-15.0 },
        }
    },
    {
        name = "Ins_4",
        units = {
            { type="T-55",              dx=0.0,   dy=0.0,   heading=0.0 },
            { type="BTR-60",            dx=26.0,  dy=-15.0, heading=0.4 },
            { type="Soldier RPG",       dx=14.0,  dy=28.0,  heading=1.1 },
            { type="Infantry AK Ins",        dx=-16.0, dy=32.0,  heading=0.0 },
            { type="Soldier RPG",       dx=15.0,  dy=28.0,  heading=1.1 },
            { type="Infantry AK Ins",        dx=-18.0, dy=32.0,  heading=0.0 },
            { type="SA-18 Igla manpad", dx=2.0,   dy=-30.0, heading=1.3 },
        }
    },
    {
        name = "Ins_5",
        units = {
            { type="Grad-URAL",         dx=0.0,   dy=0.0,   heading=0.5 },
            { type="ural_4230_civil_t", dx=0.0,   dy=0.0,   heading=0.5 },
            { type="HL_ZU-23",          dx=20.0,  dy=26.0,  heading=1.0 },
            { type="HL_KORD",           dx=-26.0, dy=18.0,  heading=0.4 },
            { type="Infantry AK Ins",        dx=8.0,   dy=-28.0, heading=1.0 },
            { type="Soldier RPG",       dx=15.0,  dy=28.0,  heading=1.1 },
            { type="Infantry AK Ins",        dx=-18.0, dy=32.0,  heading=0.0 },
        }
    },
    {
        name = "Ins_6",
        isEngagement = true,
        red_units = {
            { type="HL_KORD",           dx=0.0,   dy=0.0 },
            { type="Infantry AK Ins",   dx=-12.0, dy=10.0 },
            { type="Infantry AK Ins",   dx=10.0,  dy=14.0 },
            { type="Infantry AK Ins",   dx=-8.0,  dy=-12.0 },
            { type="Infantry AK Ins",   dx=14.0,  dy=-10.0 },
            { type="Infantry AK Ins",   dx=-15.0, dy=16.0 },
            { type="Infantry AK Ins",   dx=8.0,   dy=18.0 },
            { type="Infantry AK Ins",   dx=-10.0, dy=-15.0 },
            { type="Infantry AK Ins",   dx=12.0,  dy=-8.0 },
        },
        blue_units = {
            { type="CHAP_MATV",   dx=0.0,  dy=0.0 },
            { type="CHAP_MATV",   dx=15.0, dy=-15.0 },
            { type="Soldier M4",        dx=12.0,  dy=12.0 },
            { type="Soldier M4",        dx=25.0, dy=-15.0 },
            { type="Soldier M4",        dx=8.0,  dy=-8.0 },
            { type="Soldier M4",        dx=30.0, dy=8.0 },
            { type="Soldier M4",        dx=15.0,  dy=18.0 },
            { type="Soldier M4",        dx=22.0, dy=-18.0 },
            { type="Soldier M4",        dx=18.0,  dy=5.0 },
            { type="Soldier M4",        dx=28.0, dy=-12.0 },
            { type="Soldier M249",      dx=10.0,  dy=-15.0 },
            { type="Soldier M249",      dx=32.0, dy=10.0 },
        }
    },
    {
        name = "Ins_7",
        units = {
            { type="Grad-URAL",         dx=0.0,   dy=0.0,   heading=0.5 },
            { type="T-55",              dx=30.0,  dy=-16.0, heading=0.2 },
            { type="HL_DSHK",           dx=-30.0, dy=14.0,  heading=0.7 },
            { type="tt_ZU-23",          dx=18.0,  dy=28.0,  heading=1.0 },
            { type="Soldier RPG",       dx=10.0,  dy=-30.0, heading=1.2 },
            { type="Soldier RPG",       dx=-12.0, dy=-26.0, heading=1.2 },
            { type="Infantry AK Ins",        dx=4.0,   dy=34.0,  heading=0.0 },
            { type="HL_KORD",        dx=-8.0,  dy=38.0,  heading=0.1 },
            { type="Infantry AK Ins",        dx=10.0,  dy=40.0,  heading=0.2 },
        }
    },
    {
        name = "Ins_8",
        units = {
            { type="BTR-80",            dx=0.0,   dy=0.0,   heading=0.3 },
            { type="Ural-375 ZU-23",    dx=26.0,  dy=-18.0, heading=0.7 },
            { type="Soldier RPG",       dx=12.0,  dy=30.0,  heading=1.2 },
            { type="SA-18 Igla manpad", dx=-18.0, dy=-26.0, heading=1.4 },
            { type="Infantry AK Ins",        dx=4.0,   dy=34.0,  heading=0.0 },
            { type="Infantry AK Ins",        dx=-10.0, dy=38.0,  heading=0.1 },
            { type="Infantry AK Ins",        dx=10.0,  dy=40.0,  heading=0.2 },
        }
    },
    {
        name = "Ins_9",
        isEngagement = true,
        red_units = {
            { type="HL_KORD",           dx=0.0,   dy=0.0 },
            { type="HL_KORD",           dx=18.0,  dy=-10.0 },
            { type="Infantry AK Ins",   dx=-10.0, dy=15.0 },
            { type="Infantry AK Ins",   dx=12.0,  dy=12.0 },
            { type="Infantry AK Ins",   dx=-15.0, dy=-8.0 },
            { type="Infantry AK Ins",   dx=8.0,   dy=-14.0 },
            { type="Infantry AK Ins",   dx=-12.0, dy=18.0 },
            { type="Infantry AK Ins",   dx=15.0,  dy=-12.0 },
            { type="Infantry AK Ins",   dx=-8.0,  dy=-15.0 },
            { type="Infantry AK Ins",   dx=10.0,  dy=20.0 },
            { type="Infantry AK Ins",   dx=-18.0, dy=10.0 },
        },
        blue_units = {
            { type="CHAP_MATV",   dx=0.0,  dy=0.0 },
            { type="CHAP_MATV",   dx=15.0, dy=8.0 },
            { type="CHAP_MATV",   dx=5.0,  dy=-18.0 },
            { type="Soldier M4",        dx=8.0,  dy=15.0 },
            { type="Soldier M4",        dx=20.0, dy=-12.0 },
            { type="Soldier M4",        dx=-2.0,  dy=-10.0 },
            { type="Soldier M4",        dx=25.0, dy=10.0 },
            { type="Soldier M4",        dx=2.0,  dy=20.0 },
            { type="Soldier M4",        dx=12.0, dy=-15.0 },
            { type="Soldier M4",        dx=18.0, dy=13.0 },
            { type="Soldier M4",        dx=-5.0,  dy=-18.0 },
            { type="Soldier M249",      dx=10.0, dy=17.0 },
            { type="Soldier M249",      dx=22.0, dy=-10.0 },
        }
    },
    {
        name = "Ins_10",
        units = {
            { type="Ural-375 ZU-23",    dx=0.0,   dy=0.0,   heading=0.3 },
            { type="Soldier RPG",       dx=-26.0, dy=16.0,  heading=1.0 },
            { type="SA-18 Igla manpad", dx=18.0,  dy=28.0,  heading=1.3 },
            { type="Infantry AK Ins",        dx=4.0,   dy=34.0,  heading=0.0 },
            { type="Infantry AK Ins",        dx=-10.0, dy=38.0,  heading=0.1 },
            { type="Infantry AK Ins",        dx=10.0,  dy=40.0,  heading=0.2 },
        }
    },
    {
        name = "Ins_11",
        units = {
            { type="T-55",              dx=0.0,   dy=0.0,   heading=0.0 },
            { type="BTR-60",            dx=29.0,  dy=-18.0, heading=0.4 },
            { type="Infantry AK Ins",        dx=-26.0, dy=16.0,  heading=0.0 },
            { type="ZSU-23-4 Shilka",   dx=4.0,   dy=34.0,  heading=0.7 },
            { type="Infantry AK Ins",        dx=-10.0, dy=38.0,  heading=0.1 },
            { type="Infantry AK Ins",        dx=10.0,  dy=40.0,  heading=0.2 },
            { type="Infantry AK Ins",        dx=-4.0,  dy=44.0,  heading=0.3 },
        }
    },
    {
        name = "Ins_12",
        isEngagement = true,
        red_units = {
            { type="HL_KORD",           dx=0.0,   dy=0.0 },
            { type="Infantry AK Ins",   dx=-14.0, dy=12.0 },
            { type="Infantry AK Ins",   dx=12.0,  dy=10.0 },
            { type="Infantry AK Ins",   dx=-10.0, dy=-14.0 },
            { type="Infantry AK Ins",   dx=15.0,  dy=-12.0 },
            { type="Infantry AK Ins",   dx=-12.0, dy=18.0 },
            { type="Infantry AK Ins",   dx=10.0,  dy=16.0 },
            { type="Infantry AK Ins",   dx=-18.0, dy=-10.0 },
            { type="Infantry AK Ins",   dx=8.0,   dy=-16.0 },
            { type="Infantry AK Ins",   dx=-8.0,  dy=20.0 },
        },
        blue_units = {
            { type="CHAP_MATV",   dx=0.0,  dy=0.0 },
            { type="CHAP_MATV",   dx=14.0, dy=-12.0 },
            { type="Soldier M4",        dx=7.0,  dy=15.0 },
            { type="Soldier M4",        dx=20.0, dy=-18.0 },
            { type="Soldier M4",        dx=2.0,  dy=-10.0 },
            { type="Soldier M4",        dx=24.0, dy=10.0 },
            { type="Soldier M4",        dx=10.0,  dy=18.0 },
            { type="Soldier M4",        dx=17.0, dy=-15.0 },
            { type="Soldier M4",        dx=12.0,  dy=8.0 },
            { type="Soldier M4",        dx=22.0, dy=-12.0 },
            { type="Soldier M249",      dx=4.0,  dy=-18.0 },
            { type="Soldier M249",      dx=27.0, dy=12.0 },
        }
    },
    {
        name = "Ins_13",
        units = {
            { type="T-55",              dx=0.0,   dy=0.0,   heading=0.0 },
            { type="BTR-70",            dx=26.0,  dy=-18.0, heading=0.4 },
            { type="ZSU-23-4 Shilka",   dx=-26.0, dy=16.0,  heading=0.7 },
            { type="SA-18 Igla manpad", dx=14.0,  dy=30.0,  heading=1.1 },
            { type="Ural-375 ZU-23",    dx=0.0,   dy=0.0,   heading=0.3 },
            { type="Soldier RPG",       dx=-26.0, dy=16.0,  heading=1.0 },
            { type="Infantry AK Ins",        dx=-18.0, dy=-26.0, heading=1.2 },
        }
    },
    {
        name = "Ins_14",
        units = {
            { type="HL_ZU-23",    dx=0.0,   dy=0.0,   heading=0.3 },
            { type="Soldier RPG",       dx=-26.0, dy=16.0,  heading=1.0 },
            { type="Infantry AK Ins",        dx=-18.0, dy=-26.0, heading=1.2 },
            { type="Infantry AK Ins",        dx=-12.0, dy=34.0,  heading=0.0 },
            { type="Infantry AK Ins",        dx=14.0,  dy=30.0,  heading=1.1 },
            { type="SA-18 Igla manpad", dx=-22.0, dy=-30.0, heading=1.3 },
        }
    },
    {
        name = "Ins_15",
        isEngagement = true,
        red_units = {
            { type="HL_KORD",           dx=0.0,   dy=0.0 },
            { type="HL_KORD",           dx=20.0,  dy=-12.0 },
            { type="Infantry AK Ins",   dx=-12.0, dy=14.0 },
            { type="Infantry AK Ins",   dx=14.0,  dy=10.0 },
            { type="Infantry AK Ins",   dx=-10.0, dy=-12.0 },
            { type="Infantry AK Ins",   dx=12.0,  dy=-16.0 },
            { type="Infantry AK Ins",   dx=-16.0, dy=18.0 },
            { type="Infantry AK Ins",   dx=10.0,  dy=20.0 },
            { type="Infantry AK Ins",   dx=-8.0,  dy=-18.0 },
        },
        blue_units = {
            { type="CHAP_MATV",   dx=0.0,  dy=0.0 },
            { type="CHAP_MATV",   dx=16.0, dy=10.0 },
            { type="CHAP_MATV",   dx=6.0,  dy=-18.0 },
            { type="Soldier M4",        dx=8.0, dy=17.0 },
            { type="Soldier M4",        dx=23.0, dy=-15.0 },
            { type="Soldier M4",        dx=-2.0,  dy=-12.0 },
            { type="Soldier M4",        dx=13.0, dy=13.0 },
            { type="Soldier M4",        dx=3.0,  dy=23.0 },
            { type="Soldier M4",        dx=18.0, dy=-18.0 },
            { type="Soldier M4",        dx=10.0, dy=10.0 },
            { type="Soldier M4",        dx=-4.0,  dy=-15.0 },
            { type="Soldier M249",      dx=20.0, dy=15.0 },
            { type="Soldier M249",      dx=4.0,  dy=-17.0 },
        }
    },
    {
        name = "Ins_16",
        units = {
            { type="T-55",              dx=0.0,   dy=0.0,   heading=0.0 },
            { type="BTR-60",            dx=26.0,  dy=-18.0, heading=0.4 },
            { type="Ural-375 ZU-23",    dx=-26.0, dy=16.0,  heading=0.8 },
            { type="Soldier RPG",       dx=14.0,  dy=30.0,  heading=1.1 },
            { type="Infantry AK Ins",        dx=-14.0, dy=34.0,  heading=0.0 },
            { type="Infantry AK Ins",        dx=16.0,  dy=-30.0, heading=1.1 },
        }
    },
    {
        name = "Ins_17",
        units = {
            { type="Grad-URAL",         dx=0.0,   dy=0.0,   heading=0.5 },
            { type="ZSU-23-4 Shilka",   dx=-28.0, dy=18.0,  heading=0.4 },
            { type="Infantry AK Ins",        dx=16.0,  dy=30.0,  heading=1.1 },
            { type="Infantry AK Ins",        dx=8.0,   dy=-30.0, heading=1.1 },
            { type="SA-18 Igla manpad", dx=-18.0, dy=-26.0, heading=1.1 },
            { type="Infantry AK Ins",        dx=4.0,   dy=34.0,  heading=1.1 },
        }
    },
    {
        name = "Ins_18",
        isEngagement = true,
        red_units = {
            { type="HL_KORD",           dx=0.0,   dy=0.0 },
            { type="Infantry AK Ins",   dx=-10.0, dy=12.0 },
            { type="Infantry AK Ins",   dx=12.0,  dy=14.0 },
            { type="Infantry AK Ins",   dx=-14.0, dy=-10.0 },
            { type="Infantry AK Ins",   dx=10.0,  dy=-16.0 },
            { type="Infantry AK Ins",   dx=-8.0,  dy=18.0 },
            { type="Infantry AK Ins",   dx=14.0,  dy=10.0 },
            { type="Infantry AK Ins",   dx=-16.0, dy=-8.0 },
            { type="Infantry AK Ins",   dx=8.0,   dy=-12.0 },
            { type="Infantry AK Ins",   dx=-12.0, dy=16.0 },
        },
        blue_units = {
            { type="CHAP_MATV",   dx=0.0,  dy=0.0 },
            { type="CHAP_MATV",   dx=15.0, dy=-8.0 },
            { type="Soldier M4",        dx=7.0,  dy=15.0 },
            { type="Soldier M4",        dx=20.0, dy=-15.0 },
            { type="Soldier M4",        dx=3.0,  dy=-12.0 },
            { type="Soldier M4",        dx=25.0, dy=12.0 },
            { type="Soldier M4",        dx=10.0,  dy=18.0 },
            { type="Soldier M4",        dx=17.0, dy=-18.0 },
            { type="Soldier M4",        dx=13.0,  dy=8.0 },
            { type="Soldier M4",        dx=23.0, dy=-10.0 },
            { type="Soldier M249",      dx=5.0,  dy=-15.0 },
            { type="Soldier M249",      dx=27.0, dy=15.0 },
        }
    },
    {
        name = "Ins_19",
        units = {
            { type="BTR-60",            dx=0.0,   dy=0.0,   heading=0.3 },
            { type="BRDM-2",            dx=11.0,  dy=30.0,  heading=1.1 },
            { type="Soldier RPG",       dx=26.0,  dy=-18.0, heading=1.0 },
            { type="SA-18 Igla manpad", dx=18.0,  dy=-30.0, heading=1.0 },
            { type="Soldier RPG",       dx=-22.0, dy=-26.0, heading=1.0 },
            { type="Infantry AK Ins",        dx=14.0,  dy=30.0,  heading=1.2 },
            { type="Infantry AK Ins",        dx=-14.0, dy=34.0,  heading=0.0 },
            { type="ZSU-23-4 Shilka",   dx=-26.0, dy=18.0,  heading=0.7 },
        }
    },
    {
        name = "Ins_20",
        units = {
            { type="Grad-URAL",         dx=0.0,   dy=0.0,   heading=0.5 },
            { type="Grad-URAL",         dx=32.0,  dy=-20.0, heading=0.5 },
            { type="T-55",              dx=-32.0, dy=18.0,  heading=0.2 },
            { type="Infantry AK Ins",        dx=18.0,  dy=30.0,  heading=1.0 },
            { type="SA-18 Igla manpad", dx=-22.0, dy=-30.0, heading=1.3 },
            { type="Infantry AK Ins",        dx=6.0,   dy=36.0,  heading=0.0 },
            { type="Infantry AK Ins",        dx=8.0,   dy=34.0,  heading=0.0 },
        }
    },
}

-------------------------------------------------------------
-- GLOBAL SHUFFLE BAG
-------------------------------------------------------------

local shuffleBag = {}

local function shuffleTemplates()
    shuffleBag = {}
    for i = 1, #INSURGENT_TEMPLATES do
        shuffleBag[i] = INSURGENT_TEMPLATES[i]
    end

    -- Fisher-Yates shuffle
    for i = #shuffleBag, 2, -1 do
        local j = math.random(1, i)
        shuffleBag[i], shuffleBag[j] = shuffleBag[j], shuffleBag[i]
    end
end

local function getNextTemplate()
    if #shuffleBag == 0 then
        shuffleTemplates()
    end

    return table.remove(shuffleBag)
end

-- Initialize shuffle bag immediately
shuffleTemplates()

-------------------------------------------------------------
-- Zones
-------------------------------------------------------------

local zones = {"ZONE1","ZONE2","ZONE3","ZONE4","ZONE5","ZONE6","ZONE7","ZONE8","ZONE9","ZONE10","ZONE11",
               "ZONE12","ZONE13","ZONE14","ZONE15","ZONE16","ZONE17","ZONE18"}

-- Per-zone spawn settings
local zoneSettings = {
    ZONE1  = { min = 2, max = 3 },
    ZONE2  = { min = 2, max = 4 },
    ZONE3  = { min = 0, max = 2 },
    ZONE4  = { min = 1, max = 3 },
    ZONE5  = { min = 1, max = 4 },
    ZONE6  = { min = 1, max = 5 },
    ZONE7  = { min = 2, max = 3 },
    ZONE8  = { min = 2, max = 4 },
    ZONE9  = { min = 1, max = 4 },
    ZONE10 = { min = 2, max = 7 },
    ZONE11 = { min = 0, max = 2 },
    ZONE12 = { min = 1, max = 4 },
    ZONE13 = { min = 0, max = 2 },
    ZONE14 = { min = 1, max = 5 },
    ZONE15 = { min = 2, max = 4 },
    ZONE16 = { min = 0, max = 4 },
    ZONE17 = { min = 1, max = 5 },
    ZONE18 = { min = 0, max = 2 },
}

-------------------------------------------------------------
-- Active Groups Tracking
-------------------------------------------------------------

-- activeGroups[groupName] = {
--   group    = Group object,
--   zone     = "ZONEX",
--   markerId = number or nil
-- }

local activeGroups = {}

-- Track engagement pairs: engagementGroups[redGroupName] = { red = redGroup, blue = blueGroup, zone = zoneName, spawnTime = time, blueName = name }
local engagementGroups = {}

-- Configuration
local MAX_CONCURRENT_ENGAGEMENTS = 15
local ENGAGEMENT_TIMEOUT = 1200  -- 20 minutes in seconds

-------------------------------------------------------------
-- Visual Config
-------------------------------------------------------------

local ENABLE_SMOKE = false
local SMOKE_COLOR  = 1  -- orange (to avoid confusion with CSAR blue smoke)

-------------------------------------------------------------
-- Helpers
-------------------------------------------------------------

local function toVec3Ground(pos2d)
    local alt = land.getHeight({ x = pos2d.x, y = pos2d.y })
    return { x = pos2d.x, y = alt, z = pos2d.y }
end

-- Group death detection (must be defined before marker manager)
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

local function placeSmoke(pos2d)
    if not ENABLE_SMOKE then
        return
    end
    local p3 = toVec3Ground(pos2d)
    trigger.action.smoke(p3, SMOKE_COLOR)
end

-------------------------------------------------------------
-- MARKER MANAGER (Simple & Robust)
-------------------------------------------------------------

local markerManager = {
    active  = {},      -- { groupName = markerId }
}

local function placeMarker(groupName, pos2d)
    -- Remove old marker if it exists
    if markerManager.active[groupName] then
        trigger.action.removeMark(markerManager.active[groupName])
    end
    
    local p3 = toVec3Ground(pos2d)
    local markerId = math.random(10000, 99999)
    trigger.action.markToAll(markerId, "Enemy Forces", p3, false)
    
    markerManager.active[groupName] = markerId
    env.info("[DGSS][MARKER] Placed marker ID " .. markerId .. " for " .. groupName)
end

local function markerManagerCleanup()
    local toRemove = {}
    
    for groupName, markerId in pairs(markerManager.active) do
        -- Check if group is dead
        if isGroupDead(groupName) then
            trigger.action.removeMark(markerId)
            env.info("[DGSS][MARKER] Auto-removed marker for dead group " .. groupName)
            table.insert(toRemove, groupName)
        end
    end
    
    for _, groupName in ipairs(toRemove) do
        markerManager.active[groupName] = nil
    end
end

local function cleanupGroups()
    local toRemove = {}
    
    for groupName, data in pairs(activeGroups) do
        if isGroupDead(groupName) then
            table.insert(toRemove, groupName)
            env.info("[DGSS] Cleaned up dead group " .. groupName)
        end
    end
    
    for _, groupName in ipairs(toRemove) do
        activeGroups[groupName] = nil
    end
    
    -- Check engagement groups - when Red dies, despawn both and respawn elsewhere
    local engagementsToRemove = {}
    local currentTime = timer.getTime()
    
    for redGroupName, engData in pairs(engagementGroups) do
        local shouldRemove = false
        local reason = ""
        
        -- Check if Red group is dead (normal completion)
        if isGroupDead(redGroupName) then
            shouldRemove = true
            reason = "Red group eliminated"
        -- Check if engagement has timed out (stuck/stale)
        elseif engData.spawnTime and (currentTime - engData.spawnTime) > ENGAGEMENT_TIMEOUT then
            shouldRemove = true
            reason = "Timeout - engagement lasted > 20 minutes"
        -- Check if Blue group is dead but Red isn't (shouldn't happen, but cleanup anyway)
        elseif isGroupDead(engData.blueName) and not isGroupDead(redGroupName) then
            shouldRemove = true
            reason = "Blue group dead but Red survived"
        -- Check if either group no longer exists
        elseif not engData.red or not engData.red:isExist() or not engData.blue or not engData.blue:isExist() then
            shouldRemove = true
            reason = "Group no longer exists"
        end
        
        if shouldRemove then
            env.info("[DGSS] ENGAGEMENT COMPLETE: " .. redGroupName .. " (" .. reason .. ")")
            
            -- Destroy both groups if they still exist
            if engData.red and engData.red:isExist() then
                engData.red:destroy()
            end
            if engData.blue and engData.blue:isExist() then
                engData.blue:destroy()
                env.info("[DGSS] Despawned Blue group " .. engData.blueName)
            end
            
            -- Remove from active groups
            activeGroups[redGroupName] = nil
            activeGroups[engData.blueName] = nil
            
            -- Mark for removal from engagement tracking
            table.insert(engagementsToRemove, redGroupName)
            
            -- Only respawn if it was a normal completion or timeout (not group existence issues)
            if reason == "Red group eliminated" or reason:match("Timeout") then
                timer.scheduleFunction(function(params)
                    -- Double-check we haven't hit the max concurrent limit
                    local activeCount = 0
                    for _ in pairs(engagementGroups) do
                        activeCount = activeCount + 1
                    end
                    
                    if activeCount < MAX_CONCURRENT_ENGAGEMENTS then
                        env.info("[DGSS] Respawning engagement in zone " .. params.zoneName)
                        spawnGroupInZone(params.zoneName)
                    else
                        env.info("[DGSS] Max concurrent engagements reached, skipping respawn")
                    end
                end, { zoneName = engData.zone }, timer.getTime() + 5)
            end
        end
    end
    
    -- Remove completed engagements with explicit nil assignment
    for _, redGroupName in ipairs(engagementsToRemove) do
        local engData = engagementGroups[redGroupName]
        if engData then
            engData.red = nil
            engData.blue = nil
            engData.zone = nil
            engData.blueName = nil
            engData.spawnTime = nil
            engData.redAimPoint = nil
            engData.blueAimPoint = nil
        end
        engagementGroups[redGroupName] = nil
    end
end

-------------------------------------------------------------
-- Memory Cleanup (Clean up dead group references)
-------------------------------------------------------------

local function performMemoryCleanup()
    env.info("[DGSS] Starting memory cleanup - removing dead group references")
    
    local cleaned = 0
    
    -- Clean up dead groups from activeGroups table
    local deadGroups = {}
    for groupName, _ in pairs(activeGroups) do
        if isGroupDead(groupName) then
            table.insert(deadGroups, groupName)
        end
    end
    
    for _, groupName in ipairs(deadGroups) do
        activeGroups[groupName] = nil
        cleaned = cleaned + 1
    end
    
    -- Clean up orphaned engagement references (shouldn't happen but safety check)
    local deadEngagements = {}
    for redGroupName, engData in pairs(engagementGroups) do
        if not engData.red or not engData.red:isExist() or not engData.blue or not engData.blue:isExist() then
            table.insert(deadEngagements, redGroupName)
        end
    end
    
    for _, redGroupName in ipairs(deadEngagements) do
        local engData = engagementGroups[redGroupName]
        if engData then
            engData.red = nil
            engData.blue = nil
            engData.zone = nil
            engData.blueName = nil
            engData.spawnTime = nil
            engData.redAimPoint = nil
            engData.blueAimPoint = nil
        end
        engagementGroups[redGroupName] = nil
        cleaned = cleaned + 1
    end
    
    if cleaned > 0 then
        env.info(string.format("[DGSS] Memory cleanup complete - removed %d dead references", cleaned))
    else
        env.info("[DGSS] Memory cleanup complete - no dead references found")
    end
    
    -- Note: Physical wreckage is left for DCS to handle naturally
    -- This prevents memory leaks without causing script errors
end

-------------------------------------------------------------
-- Spawn Group in Zone (using trigger.misc.getZone)
-------------------------------------------------------------

spawnGroupInZone = function(zoneName)
    env.info("[DGSS] Attempting spawn in " .. zoneName)

    -- Get zone
    local z = trigger.misc.getZone(zoneName)
    if not z then
        env.info("[DGSS][ERROR] Zone not found: " .. tostring(zoneName))
        return
    end

    local MAX_ATTEMPTS = 5
    local spawnSuccess = false
    local finalGroupName = nil
    local finalPos2d = nil

    for attempt = 1, MAX_ATTEMPTS do
        -- Get polygon-safe point
        local pos2d

        if z.poly and #z.poly > 0 then
            pos2d = mist.getRandPointInPolygon(z)
            if not pos2d then
                env.info("[DGSS][ERROR] Polygon point failed for " .. zoneName)
                return
            end
        else
            -- Fallback for circular zones
            local center2d = { x = z.point.x, y = z.point.z }
            if z.radius then
                local r = z.radius * math.sqrt(math.random())
                local a = math.random() * 2 * math.pi
                pos2d = {
                    x = center2d.x + r * math.cos(a),
                    y = center2d.y + r * math.sin(a),
                }
            else
                pos2d = center2d
            end
        end

        -- Build group template
        local templateData = getNextTemplate()
        local t = math.floor(timer.getTime())

        -- Check if this is an engagement template and we're at max concurrent engagements
        if templateData.isEngagement then
            local activeEngagementCount = 0
            for _ in pairs(engagementGroups) do
                activeEngagementCount = activeEngagementCount + 1
            end
            
            if activeEngagementCount >= MAX_CONCURRENT_ENGAGEMENTS then
                env.info("[DGSS] Max concurrent engagements (" .. MAX_CONCURRENT_ENGAGEMENTS .. ") reached, skipping spawn in " .. zoneName)
                return
            end
            
            -- Calculate separation distance (200-500m) and angle
            local separation = 200 + math.random() * 300  -- 200 to 500 meters
            local angle = math.random() * 2 * math.pi     -- Random direction
            
            -- Red group at base position
            local redCenterX = pos2d.x
            local redCenterY = pos2d.y
            
            -- Blue group offset by separation distance
            local blueCenterX = pos2d.x + separation * math.cos(angle)
            local blueCenterY = pos2d.y + separation * math.sin(angle)
            
            -- Calculate headings so they face each other
            local redHeading = angle  -- Red faces toward Blue
            local blueHeading = angle + math.pi  -- Blue faces toward Red (opposite direction)
            if blueHeading > 2 * math.pi then
                blueHeading = blueHeading - 2 * math.pi
            end
            
            -- Spawn RED group
            local redUnits = {}
            for i, u in ipairs(templateData.red_units) do
                redUnits[#redUnits+1] = {
                    name    = templateData.name .. "_RED_U" .. i .. "_" .. t,
                    type    = u.type,
                    x       = redCenterX + u.dx,
                    y       = redCenterY + u.dy,
                    heading = redHeading,
                    skill   = "Average",
                }
            end

            local redGroupName = templateData.name .. "_RED_" .. t
            local redGroupTemplate = {
                country   = country.id.CJTF_RED,
                coalition = "red",
                category  = "vehicle",
                task      = "Ground Nothing",
                name      = redGroupName,
                units     = redUnits
            }

            -- Spawn BLUE group
            local blueUnits = {}
            for i, u in ipairs(templateData.blue_units) do
                blueUnits[#blueUnits+1] = {
                    name    = templateData.name .. "_BLUE_U" .. i .. "_" .. t,
                    type    = u.type,
                    x       = blueCenterX + u.dx,
                    y       = blueCenterY + u.dy,
                    heading = blueHeading,
                    skill   = "Average",
                }
            end

            local blueGroupName = templateData.name .. "_BLUE_" .. t
            local blueGroupTemplate = {
                country   = country.id.USA,
                coalition = "blue",
                category  = "vehicle",
                task      = "Ground Nothing",
                name      = blueGroupName,
                units     = blueUnits
            }

            -- Try spawning both groups
            local redResult = mist.dynAdd(redGroupTemplate)
            local blueResult = mist.dynAdd(blueGroupTemplate)

            if redResult and redResult.name and blueResult and blueResult.name then
                local redGroup = Group.getByName(redResult.name)
                local blueGroup = Group.getByName(blueResult.name)

                if redGroup and redGroup:isExist() and blueGroup and blueGroup:isExist() then
                    -- Set both to engage
                    local redController = redGroup:getController()
                    local blueController = blueGroup:getController()
                    
                    -- Set AI options for aggressive engagement
                    redController:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.OPEN_FIRE)
                    redController:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
                    
                    blueController:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.OPEN_FIRE)
                    blueController:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
                    
                    -- Simple AttackGroup tasks - let Average AI handle the rest
                    redController:setTask({
                        id = 'AttackGroup',
                        params = {
                            groupId = blueGroup:getID(),
                            weaponType = 2047  -- Auto weapons
                        }
                    })
                    
                    blueController:setTask({
                        id = 'AttackGroup',
                        params = {
                            groupId = redGroup:getID(),
                            weaponType = 2047  -- Auto weapons
                        }
                    })

                    -- Track engagement pair with spawn timestamp
                    engagementGroups[redResult.name] = {
                        red = redGroup,
                        blue = blueGroup,
                        zone = zoneName,
                        redName = redResult.name,
                        blueName = blueResult.name,
                        spawnTime = timer.getTime()
                    }

                    spawnSuccess   = true
                    finalGroupName = redResult.name
                    finalPos2d     = pos2d
                    env.info("[DGSS] ENGAGEMENT spawned: " .. redResult.name .. " vs " .. blueResult.name)
                    break
                end
            end
        else
            -- Normal insurgent template
            local units = {}
            for i, u in ipairs(templateData.units) do
                units[#units+1] = {
                    name    = templateData.name .. "_U" .. i .. "_" .. t,
                    type    = u.type,
                    x       = pos2d.x + u.dx,
                    y       = pos2d.y + u.dy,
                    heading = u.heading,
                    skill   = "random",
                }
            end

            local groupName = templateData.name .. "_" .. t
            local groupTemplate = {
                country   = country.id.CJTF_RED,
                coalition = "red",
                category  = "vehicle",
                task      = "Ground Nothing",
                name      = groupName,
                units     = units
            }

            -- Try dynAdd
            local result = mist.dynAdd(groupTemplate)

            if result and result.name then
                local groupObj = Group.getByName(result.name)
                if groupObj and groupObj:isExist() then
                    -- SUCCESS
                    spawnSuccess   = true
                    finalGroupName = result.name
                    finalPos2d     = pos2d
                    break
                end
            end
        end

        env.info("[DGSS][WARN] dynAdd failed for " .. templateData.name .. " (attempt " .. attempt .. ")")
    end

    -- If all attempts failed
    if not spawnSuccess then
        env.info("[DGSS][ERROR] All spawn attempts failed for zone " .. zoneName)
        return
    end

    -- Verify the group exists with live units before registering
    local groupObj = Group.getByName(finalGroupName)
    if not groupObj or not groupObj:isExist() then
        env.info("[DGSS][ERROR] Group verification failed: " .. finalGroupName .. " does not exist")
        return
    end
    
    local units = groupObj:getUnits()
    if not units or #units == 0 then
        env.info("[DGSS][ERROR] Group verification failed: " .. finalGroupName .. " has no units")
        return
    end
    
    -- Register group
    activeGroups[finalGroupName] = {
        group    = groupObj,
        zone     = zoneName,
    }
    
    -- Place marker immediately after spawn
    placeMarker(finalGroupName, finalPos2d)
    placeSmoke(finalPos2d)

    env.info("[DGSS] Spawned group " .. finalGroupName .. " in zone " .. zoneName)
end

-------------------------------------------------------------
-- Main Zone Check & Spawn Logic
-------------------------------------------------------------

local MAX_SPAWNS_PER_CYCLE = 3  -- Rate limiting: max 3 spawns per cycle

local function checkZones()
    cleanupGroups()

    local spawnsThisCycle = 0

    for _, zoneName in ipairs(zones) do
        if spawnsThisCycle >= MAX_SPAWNS_PER_CYCLE then
            break  -- Hit rate limit, remaining spawns will happen in next cycle
        end

        local settings = zoneSettings[zoneName]
        if settings then
            local minReq = settings.min
            local maxReq = settings.max

            -- Count existing groups in this zone
            local count = 0
            for _, data in pairs(activeGroups) do
                if data.group and data.group:isExist() and data.zone == zoneName then
                    count = count + 1
                end
            end

            -- If below minimum, spawn enough to reach minimum
            if count < minReq then
                local needed = minReq - count
                for i = 1, needed do
                    if spawnsThisCycle >= MAX_SPAWNS_PER_CYCLE then
                        break  -- Hit rate limit
                    end
                    spawnGroupInZone(zoneName)
                    spawnsThisCycle = spawnsThisCycle + 1
                end

            -- If between min and max, spawn randomly up to max
            elseif count < maxReq then
                local remaining = maxReq - count
                local spawnCount = math.random(1, remaining)
                for i = 1, spawnCount do
                    if spawnsThisCycle >= MAX_SPAWNS_PER_CYCLE then
                        break  -- Hit rate limit
                    end
                    spawnGroupInZone(zoneName)
                    spawnsThisCycle = spawnsThisCycle + 1
                end
            end
        end
    end

    if spawnsThisCycle > 0 then
        env.info("[DGSS] Spawned " .. spawnsThisCycle .. " groups this cycle")
    end

    timer.scheduleFunction(checkZones, {}, timer.getTime() + 300)  -- Check every 300 seconds (5 minutes)
end

-------------------------------------------------------------
-- Periodic Cleanup Loop
-------------------------------------------------------------

local function cleanupLoop()
    cleanupGroups()
    markerManagerCleanup()  -- Clean up markers for dead groups
    
    -- Log engagement count for monitoring
    local engagementCount = 0
    for _ in pairs(engagementGroups) do
        engagementCount = engagementCount + 1
    end
    if engagementCount > 0 then
        env.info("[DGSS] Active engagements: " .. engagementCount .. "/" .. MAX_CONCURRENT_ENGAGEMENTS)
    end
    
    return timer.getTime() + 120  -- check every 120 seconds (2 minutes)
end

-------------------------------------------------------------
-- Start System
-------------------------------------------------------------

env.info("[DEBUG] Dynamic Insurgent Zone Spawner Initialized")
checkZones()
timer.scheduleFunction(cleanupLoop, {}, timer.getTime() + 10)
mist.scheduleFunction(performMemoryCleanup, {}, timer.getTime() + 1200, 1200)  -- Run every 20 minutes