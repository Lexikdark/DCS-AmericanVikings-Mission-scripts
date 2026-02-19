-- =============================================================================
--  RED / BLUE IADS + RED Air Intercept System for DCS World
--  Map     : SYRIA
--  Author  : Mission Designer Script (AI Generated)
--  Requires: MIST (Mission Scripting Tools) loaded BEFORE this script
--
--  Syria Airbase Reference (for placement purposes):
--    RED (SAA/Russian) : Mezzeh, Damascus, Marj Ruhayyil, Khalkhalah, At Tanf,
--                        Sayqal, Tiyas (= Tha'lah / T-4), Palmyra, Deir ez-Zor,
--                        Shayrat, Hama, Al Qusayr, Bassel Al-Assad
--    BLUE (Coalition)  : Ramat David, Megiddo, Haifa, Ben Gurion, Kiryat Shmona
--  BLUE Sector Zones  : BLUE_ZONE_NORTH  BLUE_ZONE_NORTH_2    BLUE_ZONE_NORTHWEST
--                        BLUE_ZONE_NORTHEAST  BLUE_ZONE_EAST  BLUE_ZONE_SOUTH
--                        BLUE_ZONE_PRINCEHASSAN  BLUE_ZONE_H4
--
--  Syria Sector Zones (RED_ZONE_ names used in this mission):
--    RED_ZONE_DAMASCUS    RED_ZONE_THALAH       RED_ZONE_KHALKHALAH
--    RED_ZONE_AT_TANF     RED_ZONE_SAYQAL       RED_ZONE_PALMYRA
--    RED_ZONE_DEIR_EZ_ZOR RED_ZONE_TABQA        RED_ZONE_AN_NASIRIYAH
--    RED_ZONE_HAMA        RED_ZONE_ALEPPO       RED_ZONE_LATAKIA
--
--  Naming Conventions (configure groups in the Mission Editor):
--    RED_SAM_<anything>   – Red SAM/SHORAD groups
--    BLUE_SAM_<anything>  – Blue SAM/SHORAD groups
--    RED_EWR_<anything>   – Red Early Warning Radar groups
--    BLUE_EWR_<anything>  – Blue Early Warning Radar groups
--    RED_AIR_<anything>   – Red Air Intercept flights (late-activate, 2 units each)
--    RED_ZONE_<anything>  – Trigger zones marking Red-controlled airspace sectors
--                          (zone name must match exactly in ME trigger zone list)
--
--  Load Order in Mission Editor (DO Script File triggers at mission start T=0):
--    1. MIST  (e.g. mist_4_5_107.lua)
--    2. This script
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION 1 – CONFIGURATION
-- ─────────────────────────────────────────────────────────────────────────────

local IADS_CFG = {

    -- ── Polling intervals (seconds) ──────────────────────────────────────────
    UPDATE_INTERVAL         = 5,    -- Main IADS update loop
    AIR_INTERCEPT_INTERVAL  = 10,   -- Air-intercept zone check loop
    WEAPON_TRACK_INTERVAL   = 1,    -- Incoming weapon tracking loop
    RTB_CHECK_INTERVAL      = 15,   -- RTB/despawn check loop
    NODE_REFRESH_INTERVAL   = 900,  -- Full SAM/EWR node-list rebuild (15 min)
                                    -- Dead groups are silently dropped each cycle;
                                    -- no respawn — SAM sites are one-and-done.

    -- ── IADS detection ranges (metres) ─────────────────────────────────────
    SAM_ENGAGE_SHARE_RANGE  = 180000,  -- 180 km  – max range SAMs will score/engage a contact
    SAM_MIN_ENGAGE_ALT      = 20,      -- metres AGL – ignore very low contacts
    SAM_FIRE_DELAY_MIN      = 0,       -- seconds – random delay before engaging (0 = instant)
    SAM_FIRE_DELAY_MAX      = 3,       -- tighter window = faster, more dangerous SAMs
    SAM_MAX_ENGAGE_PER_CONTACT = 2,    -- max SAM nodes assigned to the same contact

    -- ── Probability of Kill helpers ──────────────────────────────────────────
    -- Each SAM computes a score; highest scorer engages.
    -- Score = basePk * altFactor * rangeFactor * healthFactor
    PKill_BASE              = 0.92,      -- base Pk for a healthy SAM on boresight (raised for lethality)

    -- ── ARM / munition defence ──────────────────────────────────────────────
    ARM_SHUTDOWN_TIME             = 45,    -- seconds radar stays silent after ARM detect
    ARM_MOVE_RADIUS               = 800,   -- metres random relocate if unit is mobile
    ARM_SUPPRESS_TRIGGER_DIST     = 150000, -- metres – arm suppression triggers when ARM is within this of trajectory end (was 80km)
    ARM_NEIGHBOR_SUPPRESS_RANGE   = 12000,  -- metres – also silence SAMs this close to the targeted node
    ARM_NEIGHBOR_SUPPRESS_TIME    = 20,     -- seconds neighbors stay dark (shorter than primary)
    -- ─────────────────────────────────────────────────────────────────────────
    --  ARM_TYPES – Anti-Radiation Missiles (radar-homing weapons)
    --  DCS getTypeName() can return either the underscored or hyphenated form;
    --  we list both variants and use string.find() so partial matches work.
    -- ─────────────────────────────────────────────────────────────────────────
    ARM_TYPES = {
        -- ── NATO / Western ARMs ──────────────────────────────────────
        -- AGM-88 HARM family (F-16C, F/A-18C, AV-8B, A-10C II)
        ["AGM_88"]          = true,   -- DCS internal underscore form
        ["AGM-88"]          = true,   -- Hyphen form / module display name
        ["AGM-88C"]         = true,
        ["AGM-88E"]         = true,   -- AARGM (F/A-18C update)
        -- AGM-45 Shrike (A-4E, older modules)
        ["AGM-45"]          = true,
        ["AGM_45"]          = true,
        ["AGM-45A"]         = true,
        ["AGM-45B"]         = true,
        -- AGM-122 Sidearm (AV-8B)
        ["AGM-122"]         = true,
        ["AGM_122"]         = true,
        ["AGM-122A"]        = true,
        -- ALARM (Tornado GR4)
        ["ALARM"]           = true,

        -- ── Russian / Soviet ARMs ────────────────────────────────────
        -- Kh-58 / X-58 family (Su-24M, Su-25T, Su-34)
        ["Kh-58"]           = true,
        ["X_58"]            = true,   -- DCS internal Russian naming
        ["X-58"]            = true,
        ["Kh-58U"]          = true,
        ["X_58U"]           = true,
        ["Kh-58UShE"]       = true,
        ["X_58UShE"]        = true,
        -- Kh-31P / X-31P (Su-27, Su-30, MiG-29G)
        ["Kh-31P"]          = true,
        ["X_31P"]           = true,
        ["X-31P"]           = true,
        -- Kh-25MP / X-25MP (Su-25T, Su-24M)
        ["Kh-25MP"]         = true,
        ["X_25MP"]          = true,
        ["X-25MP"]          = true,
        ["Kh-25MPU"]        = true,
        ["X_25MPU"]         = true,
        -- Kh-28 / X-28 (Su-24M)
        ["Kh-28"]           = true,
        ["X_28"]            = true,
        ["X-28"]            = true,
    },

    -- ─────────────────────────────────────────────────────────────────────────
    --  AGM_TYPES – Guided Air-to-Ground Weapons (AGMs, cruise missiles,
    --  laser/GPS/TV guided bombs) that SHORAD should attempt to intercept
    --  and that we track to alert SAMs.
    -- ─────────────────────────────────────────────────────────────────────────
    AGM_TYPES = {
        -- ── AGM-65 Maverick family (A-10A/C, F-16C, F/A-18C, AV-8B) ─
        ["AGM-65A"]         = true,
        ["AGM-65B"]         = true,
        ["AGM-65D"]         = true,
        ["AGM-65E"]         = true,   -- laser SAL (AV-8B)
        ["AGM-65F"]         = true,   -- IIR (F/A-18C)
        ["AGM-65G"]         = true,   -- IIR heavy (A-10A)
        ["AGM-65H"]         = true,   -- CCD (F-16C)
        ["AGM-65K"]         = true,   -- CCD heavy (A-10C)
        ["AGM_65"]          = true,   -- generic catch-all
        ["AGM-65"]          = true,

        -- ── AGM-84 family (F/A-18C) ──────────────────────────────────
        ["AGM-84"]          = true,
        ["AGM_84"]          = true,
        ["AGM-84D"]         = true,   -- Harpoon
        ["AGM-84E"]         = true,   -- SLAM
        ["AGM-84H"]         = true,   -- SLAM-ER

        -- ── AGM-154 JSOW (F/A-18C) ───────────────────────────────────
        ["AGM-154"]         = true,
        ["AGM_154"]         = true,
        ["AGM-154A"]        = true,   -- BLU-97 submunitions
        ["AGM-154C"]        = true,   -- unitary warhead

        -- ── AGM-158A JASSM (F-16C) ───────────────────────────────────
        ["AGM-158"]         = true,
        ["AGM_158"]         = true,
        ["AGM-158A"]        = true,

        -- ── Storm Shadow (Tornado GR4, JF-17) ────────────────────────
        ["Storm_Shadow"]    = true,
        ["Storm Shadow"]    = true,

        -- ── Russian Kh-29 family (Su-25T, Su-30MKK, Su-34) ──────────
        ["Kh-29T"]          = true,   -- TV-guided
        ["X_29T"]           = true,
        ["Kh-29L"]          = true,   -- laser-guided
        ["X_29L"]           = true,
        ["Kh-29TE"]         = true,   -- extended range TV
        ["X_29TE"]          = true,
        ["Kh-29"]           = true,   -- generic catch-all
        ["X_29"]            = true,

        -- ── Russian Kh-59 family (Su-24M, Su-30, Su-34) ─────────────
        ["Kh-59"]           = true,
        ["X_59"]            = true,
        ["Kh-59M"]          = true,
        ["X_59M"]           = true,
        ["Kh-59MK"]         = true,
        ["X_59MK"]          = true,
        ["Kh-59MK2"]        = true,
        ["X_59MK2"]         = true,

        -- ── Russian Kh-25 guided variants (Su-25T, Su-24M) ──────────
        ["Kh-25ML"]         = true,   -- laser-guided
        ["X_25ML"]          = true,
        ["Kh-25MR"]         = true,   -- radio-guided
        ["X_25MR"]          = true,

        -- ── Russian Kh-31A (anti-ship, Su-30, MiG-29) ────────────────
        ["Kh-31A"]          = true,
        ["X_31A"]           = true,

        -- ── Russian Kh-35 / Kh-35U (Ka-52, Su-30, Su-34) ────────────
        ["Kh-35"]           = true,
        ["X_35"]            = true,
        ["Kh-35U"]          = true,
        ["X_35U"]           = true,

        -- ── Russian S-25L (laser heavy rocket, Su-25T) ───────────────
        ["S-25L"]           = true,
        ["S_25L"]           = true,

        -- ═══════════════════════════════════════════════════════════════
        --  GUIDED BOMBS
        -- ═══════════════════════════════════════════════════════════════

        -- ── Paveway II – LGBs (F-16C, F/A-18C, A-10C, Tornado GR4) ──
        ["GBU-10"]          = true,   -- Mk-84  2000 lb
        ["GBU_10"]          = true,
        ["GBU-12"]          = true,   -- Mk-82   500 lb
        ["GBU_12"]          = true,
        ["GBU-16"]          = true,   -- Mk-83  1000 lb
        ["GBU_16"]          = true,

        -- ── Paveway III – LGB (F/A-18C, F-16C) ──────────────────────
        ["GBU-24"]          = true,   -- Mk-84 / BLU-109 2000 lb
        ["GBU_24"]          = true,

        -- ── Enhanced Paveway II – GPS/laser (F-16C, Tornado GR4) ─────
        ["GBU-49"]          = true,
        ["GBU_49"]          = true,

        -- ── JDAM – GPS-guided (F-16C, F/A-18C, A-10C, B-52H) ────────
        ["GBU-31"]          = true,   -- Mk-84 JDAM  2000 lb
        ["GBU_31"]          = true,
        ["GBU-31(V)1/B"]    = true,
        ["GBU-31(V)2/B"]    = true,
        ["GBU-31(V)3/B"]    = true,   -- BLU-109 JDAM
        ["GBU-31(V)4/B"]    = true,
        ["GBU-32"]          = true,   -- Mk-83 JDAM  1000 lb
        ["GBU_32"]          = true,
        ["GBU-38"]          = true,   -- Mk-82 JDAM   500 lb
        ["GBU_38"]          = true,
        ["GBU-54"]          = true,   -- Laser JDAM dual-mode
        ["GBU_54"]          = true,

        -- ── GBU-39 Small Diameter Bomb (F-16C, F/A-18C) ──────────────
        ["GBU-39"]          = true,
        ["GBU_39"]          = true,
        ["GBU-39/B"]        = true,

        -- ── Russian KAB-500 family (Su-25T, Su-30, Su-34, MiG-29) ────
        ["KAB-500Kr"]       = true,   -- TV-guided
        ["KAB_500Kr"]       = true,
        ["KAB-500kr"]       = true,   -- lower-case variant in some DCS versions
        ["KAB_500kr"]       = true,
        ["KAB-500L"]        = true,   -- laser-guided
        ["KAB_500L"]        = true,
        ["KAB-500S"]        = true,   -- GLONASS-guided
        ["KAB_500S"]        = true,

        -- ── Russian KAB-1500 family (Su-24M, Su-34) ──────────────────
        ["KAB-1500Kr"]      = true,   -- TV-guided
        ["KAB_1500Kr"]      = true,
        ["KAB-1500kr"]      = true,
        ["KAB_1500kr"]      = true,
        ["KAB-1500L"]       = true,   -- laser-guided
        ["KAB_1500L"]       = true,

        -- ── Durandal (Mirage 2000 – runway penetrator) ────────────────
        ["Durandal"]        = true,

        -- ── BetAB concrete-piercer (Russian, Su-25/Su-34) ───────────
        ["BetAB-500"]       = true,
        ["BetAB_500"]       = true,
        ["BetAB-500ShP"]    = true,
        ["BetAB_500ShP"]    = true,
    },

    -- ── Air Intercept ────────────────────────────────────────────────────────
    INTERCEPT_ALTITUDE      = 6000,   -- metres  – initial intercept climb altitude
    INTERCEPT_SPEED         = 900,    -- km/h    – intercept speed
    RTB_LOITER_TIME         = 30,     -- seconds after zone clear before RTB order
    SCRAMBLE_THREAT_BUFFER  = 40000,  -- metres OUTSIDE the zone radius that still triggers a scramble
                                      -- e.g. zone radius 50 km + buffer 40 km = scramble at 90 km from centre
                                      -- Set to 0 to only scramble when the threat is inside the zone itself
    INTERCEPT_LEASH_BUFFER  = 80000,  -- metres beyond zone radius — if an airborne intercept flight strays
                                      -- farther than (zone_radius + this value) from its zone centre it is
                                      -- immediately recalled, regardless of RTB_LOITER_TIME
    ZONE_PREFIX             = "RED_ZONE_",   -- must match ME trigger zone names

    -- ── GCI / Detection settings ─────────────────────────────────────────────
    -- Detection uses coalition.getDetectedTargets() exclusively (DCS sensor model).
    -- Terrain masking, LOS, jamming, and unit radar ranges all apply natively.
    GCI_PICTURE_INTERVAL   = 180,     -- seconds between AWACS picture broadcasts
    GCI_FUEL_RTB_THRESHOLD = 0.20,    -- fuel fraction (0–1) that triggers Bingo RTB
    AWACS_PREFIX_RED       = "RED_AWACS_",
    AWACS_PREFIX_BLUE      = "BLUE_AWACS_",
    AWACS_ORBIT_ALT_FT     = 30000,   -- ft  – orbit altitude enforced by the AWACS keeper loop
    AWACS_ORBIT_KTS        = 350,     -- kts – airspeed enforced by the AWACS keeper loop
    AWACS_CALLSIGN = {
        RED  = "OVERLORD",
        BLUE = "MAGIC",
    },

    -- ── Lebanon sub-IADS engagement boundary ─────────────────────────────────
    -- Lebanon SAMs will ONLY engage contacts whose position falls inside
    -- (or within SAM_ENGAGE_SHARE_RANGE of) one of these trigger zones.
    -- Zone names must match exactly what you set in the ME.
    LEBANON_ZONES = {
        "LEBANON_ZONE_NORTH",
        "LEBANON_ZONE_MIDDLE",
        "LEBANON_ZONE_SOUTH",
    },
    GCI_CALLSIGN = {
        RED  = "GCI MOSCOW",
        BLUE = "GCI CONTROL",
    },

    -- ── Squadron / CAP flight definitions (both coalitions) ──────────────────
    --  groupPrefix : groups in ME named <groupPrefix>_01, _02, _03 …
    --  homeBase    : Airbase.getByName() string – used for RTB routing
    --  zone        : Trigger zone this squadron is assigned to defend
    --  maxFlights  : Max simultaneous airborne flights for this squadron
    --  callsign    : GCI radio callsign used in player-facing messages
    SQUADRONS = {
        RED = {
            -- ── Damascus (2 squadrons – capital gets double coverage) ──────────
            { callsign="FOXBAT",   homeBase="Mezzeh",          zone="RED_ZONE_DAMASCUS",      groupPrefix="RED_AIR_MEZZEH",        maxFlights=8 },
            { callsign="FULCRUM",  homeBase="Damascus",        zone="RED_ZONE_DAMASCUS",      groupPrefix="RED_AIR_DAMASCUS",      maxFlights=8 },
            -- ── South / SW Syria ─────────────────────────────────────────────
            { callsign="FENCER",   homeBase="Marj Ruhayyil",   zone="RED_ZONE_AN_NASIRAYAH",  groupPrefix="RED_AIR_MARJ_RUHAYYIL", maxFlights=8 },
            { callsign="SHAHIN",   homeBase="Khalkhalah",      zone="RED_ZONE_KHALKHALAH",    groupPrefix="RED_AIR_KHALKHALAH",    maxFlights=8 },
            -- ── SE Syria / Iraqi border ──────────────────────────────────────
            { callsign="NEMER",    homeBase="At Tanf",         zone="RED_ZONE_AT_TANF",       groupPrefix="RED_AIR_AT_TANF",       maxFlights=8 },
            -- ── Central Syria ────────────────────────────────────────────────
            { callsign="SOKOL",    homeBase="Sayqal",          zone="RED_ZONE_SAYQAL",        groupPrefix="RED_AIR_SAYQAL",        maxFlights=8 },
            { callsign="FLANKER",  homeBase="Tha'lah",         zone="RED_ZONE_THALAH",        groupPrefix="RED_AIR_THALAH",        maxFlights=8 },
            -- ── Palmyra / Eastern Syria ───────────────────────────────────────
            { callsign="VYMPEL",   homeBase="Palmyra",         zone="RED_ZONE_PALMYRA",       groupPrefix="RED_AIR_PALMYRA",       maxFlights=8 },
            { callsign="BUKET",    homeBase="Deir ez-Zor",     zone="RED_ZONE_DEIR_EZ-ZOR",   groupPrefix="RED_AIR_DEIR_EZ_ZOR",   maxFlights=8 },
            -- ── Homs / Tabqa ─────────────────────────────────────────────────
            { callsign="FROGFOOT", homeBase="Shayrat",         zone="RED_ZONE_TABQA",         groupPrefix="RED_AIR_SHAYRAT",       maxFlights=8 },
            -- ── Hama / Aleppo ────────────────────────────────────────────────
            { callsign="BERKUT",   homeBase="Hama",            zone="RED_ZONE_HAMA",          groupPrefix="RED_AIR_HAMA",          maxFlights=8 },
            { callsign="ALKU",     homeBase="Hama",            zone="RED_ZONE_ALEPPO",        groupPrefix="RED_AIR_ALEPPO",        maxFlights=8 },  -- Closest user base to Aleppo zone
            -- ── Latakia / Coastal (2 squadrons) ──────────────────────────────
            { callsign="NASR",     homeBase="Al Qusayr",       zone="RED_ZONE_BASSEL_AL-ASSAD", groupPrefix="RED_AIR_AL_QUSAYR",     maxFlights=8 },
            { callsign="KOBRA",    homeBase="Bassel Al-Assad", zone="RED_ZONE_BASSEL_AL-ASSAD", groupPrefix="RED_AIR_LATAKIA",       maxFlights=8 },
        },
        BLUE = {
            -- ── Northern Israel – Syria north / NE approach ──────────────────
            { callsign="VIPER",   homeBase="Kiryat Shmona", zone="BLUE_ZONE_North",        groupPrefix="BLUE_AIR_KIRYAT_N",    maxFlights=8 },  -- DCS: "Kiryat Shmona" (user: Kiryat Shamona)
            { callsign="EAGLE",   homeBase="Ramat David",   zone="BLUE_ZONE_North_2",      groupPrefix="BLUE_AIR_RAMAT_N2",    maxFlights=8 },
            { callsign="HORNET",  homeBase="Ramat David",   zone="BLUE_ZONE_NorthEast",    groupPrefix="BLUE_AIR_RAMAT_NE",    maxFlights=8 },
            -- ── Central / NW Israel ───────────────────────────────────────────
            { callsign="FALCON",  homeBase="Megiddo",       zone="BLUE_ZONE_NorthWest",    groupPrefix="BLUE_AIR_MEGIDDO",     maxFlights=8 },
            { callsign="TIGER",   homeBase="Haifa",         zone="BLUE_ZONE_East",         groupPrefix="BLUE_AIR_HAIFA",       maxFlights=8 },
            -- ── Southern Israel – Jordan / Iraqi border ───────────────────────
            { callsign="ZEUS",    homeBase="Ben Gurion",    zone="BLUE_ZONE_South",        groupPrefix="BLUE_AIR_BENGURION_S",  maxFlights=8 },
            { callsign="SPARTAN", homeBase="Ben Gurion",    zone="BLUE_ZONE_PrinceHassan", groupPrefix="BLUE_AIR_BENGURION_PH", maxFlights=8 },
            { callsign="LANCER",  homeBase="Ben Gurion",    zone="BLUE_ZONE_H4",           groupPrefix="BLUE_AIR_BENGURION_H4", maxFlights=8 },
        },
    },
}

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION 2 – UTILITY HELPERS
-- ─────────────────────────────────────────────────────────────────────────────

local function log(msg)
    env.info("[IADS] " .. tostring(msg))
end

local function dist3d(p1, p2)
    local dx = p1.x - p2.x
    local dy = (p1.y or 0) - (p2.y or 0)
    local dz = p1.z - p2.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local function dist2d(p1, p2)
    local dx = p1.x - p2.x
    local dz = p1.z - p2.z
    return math.sqrt(dx*dx + dz*dz)
end

local function randomOffset(radius)
    local angle = math.random() * 2 * math.pi
    return {
        x = math.cos(angle) * radius * math.random(),
        z = math.sin(angle) * radius * math.random(),
    }
end

-- Returns true if point p lies within the radius of any zone in the given list.
-- Uses trigger.misc.getZone() (native DCS API) for correct world-coordinate geometry.
-- MIST zone DB uses 2D mission-file coordinates ({x,y} where y = DCS world z),
-- so we never use zd.point directly for distance checks.
local function pointInAnyZone(p, zoneNames)
    for _, zoneName in ipairs(zoneNames) do
        local zd = trigger.misc.getZone(zoneName)
        if zd and zd.point and zd.radius then
            -- trigger.misc.getZone returns point in DCS world coords {x, y, z}
            if dist2d(p, zd.point) <= zd.radius then
                return true
            end
        end
    end
    return false
end

local function groupAlive(groupName)
    local g = Group.getByName(groupName)
    if not g then return false end
    for _, u in ipairs(g:getUnits()) do
        if u:getLife() > 1 then return true end
    end
    return false
end

local function getGroupPos(groupName)
    local g = Group.getByName(groupName)
    if not g then return nil end
    for _, u in ipairs(g:getUnits()) do
        if u:isActive() and u:getLife() > 1 then
            return u:getPoint()
        end
    end
    return nil
end

-- collect all group names (ground) matching a prefix for a coalition
local function getGroupsByPrefix(coa, prefix)
    local result = {}
    local groups = coalition.getGroups(coa, Group.Category.GROUND)
    for _, g in ipairs(groups) do
        local name = g:getName()
        if string.sub(name, 1, #prefix) == prefix then
            table.insert(result, name)
        end
    end
    return result
end

-- same but for aircraft
local function getAirGroupsByPrefix(coa, prefix)
    local result = {}
    local groups = coalition.getGroups(coa, Group.Category.AIRPLANE)
    for _, g in ipairs(groups) do
        local name = g:getName()
        if string.sub(name, 1, #prefix) == prefix then
            table.insert(result, name)
        end
    end
    -- also helicopters
    local helos = coalition.getGroups(coa, Group.Category.HELICOPTER)
    for _, g in ipairs(helos) do
        local name = g:getName()
        if string.sub(name, 1, #prefix) == prefix then
            table.insert(result, name)
        end
    end
    return result
end

local function getNearestAirbase(pos, coa)
    local bases = world.getAirbases()
    local best, bestDist = nil, math.huge
    for _, ab in ipairs(bases) do
        local abPos = ab:getPoint()
        local d = dist2d(pos, abPos)
        if d < bestDist then
            bestDist = d
            best = ab
        end
    end
    return best
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION 3 – IADS STATE TABLES
-- ─────────────────────────────────────────────────────────────────────────────

local IADS = {
    RED     = { samNodes = {}, ewrNodes = {}, contacts = {}, suppressedUntil = {} },
    BLUE    = { samNodes = {}, ewrNodes = {}, contacts = {}, suppressedUntil = {} },
    -- Lebanon SAMs run as a completely isolated RED-side sub-IADS.
    -- They detect and engage BLUE aircraft independently; they do NOT
    -- share contacts or engagement assignments with the main RED network.
    LEBANON = { samNodes = {}, ewrNodes = {}, contacts = {}, suppressedUntil = {} },
}

-- Tracked incoming weapons  { weapon_obj, launchPos, coalition_target }
local trackedWeapons = {}

-- GCI / intercept state — both coalitions
local gciState = {
    RED  = { flights = {}, zones = {}, lastPicture = 0 },
    BLUE = { flights = {}, zones = {}, lastPicture = 0 },
}
-- Legacy alias (kept so downstream code compiled before this section sees it)
local airIntercept = { flights = gciState.RED.flights, zones = gciState.RED.zones }

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION 4 – EWR / CONTACT SHARING
-- ─────────────────────────────────────────────────────────────────────────────

-- excludePrefix (optional): skip groups whose name starts with this string.
-- Used to stop the main RED IADS absorbing RED_SAM_LEBANON_ / RED_EWR_LEBANON_ groups.
local function buildNodeList(coaName, coaID, samPrefix, ewrPrefix, excludePrefix)
    local state = IADS[coaName]
    state.samNodes = {}
    state.ewrNodes = {}

    for _, name in ipairs(getGroupsByPrefix(coaID, samPrefix)) do
        if groupAlive(name) then
            local excluded = excludePrefix and (string.sub(name, 1, #excludePrefix) == excludePrefix)
            if not excluded then
                table.insert(state.samNodes, name)
            end
        end
    end

    for _, name in ipairs(getGroupsByPrefix(coaID, ewrPrefix)) do
        if groupAlive(name) then
            local excluded = excludePrefix and (string.sub(name, 1, #excludePrefix) == excludePrefix)
            if not excluded then
                table.insert(state.ewrNodes, name)
            end
        end
    end

    log(coaName .. " IADS: " .. #state.samNodes .. " SAM nodes, " .. #state.ewrNodes .. " EWR nodes")
end

-- Gather enemy contacts visible to this coalition.
-- Uses ONLY the DCS built-in sensor model (coalition.getDetectedTargets with RADAR filter).
-- Terrain masking, LOS, jamming, and each unit's real sensor range all apply.
-- The scripted range-sphere fallback has been removed to preserve sensor realism.
local _gatherContactsWarnedOnce = false
local function gatherContacts(coaName, enemyCoa)
    local state  = IADS[coaName]
    state.contacts = {}
    local seen   = {}   -- deduplicate by unit name
    local now    = timer.getTime()

    -- LEBANON is a RED-coalition sub-IADS; resolve coalition ID accordingly.
    local myCoaID = (coaName == "BLUE") and coalition.side.BLUE or coalition.side.RED

    -- Unit.SensorType may be nil in older DCS builds; guard both the function and the enum.
    local radarSensorType = Unit.SensorType and Unit.SensorType.RADAR or nil

    if not (coalition.getDetectedTargets and radarSensorType) then
        -- DCS build does not expose getDetectedTargets or RADAR sensor type.
        -- Log once per session and skip — contacts list will be empty until DCS exposes the API.
        if not _gatherContactsWarnedOnce then
            _gatherContactsWarnedOnce = true
            log("WARNING: coalition.getDetectedTargets or Unit.SensorType.RADAR unavailable. "
                .. "IADS will not detect contacts. Check DCS version.")
        end
        return state.contacts
    end

    local det = coalition.getDetectedTargets(myCoaID, radarSensorType)
    for _, d in ipairs(det or {}) do
        local obj = d.object
        if obj and obj:isExist()
        and obj.getCoalition and obj:getCoalition() == enemyCoa
        and obj.getLife     and obj:getLife() > 1
        and obj.getPoint then
            local p = obj:getPoint()
            if p and p.y and p.y > IADS_CFG.SAM_MIN_ENGAGE_ALT then
                local n = obj:getName()
                if not seen[n] then
                    seen[n] = true
                    table.insert(state.contacts, {
                        unit       = obj,
                        group      = obj.getGroup and obj:getGroup() or nil,
                        pos        = p,
                        vel        = obj.getVelocity and obj:getVelocity() or {x=0,y=0,z=0},
                        name       = n,
                        detectedAt = now,
                        byRadar    = true,
                    })
                end
            end
        end
    end

    return state.contacts
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION 5 – SAM THREAT SCORING & ENGAGEMENT
-- ─────────────────────────────────────────────────────────────────────────────

--[[
    Probability-of-Kill score for a given SAM node engaging a given contact.
    Higher = better engagement solution.
    Factors:
      - Health of the SAM unit
      - 3D slant range (closer is better up to a point)
      - Altitude of target (SAMs prefer mid-altitude targets)
      - Whether the SAM is currently suppressed
]]
local function computeEngagementScore(samName, contact)
    local now = timer.getTime()

    -- If radar is suppressed (ARM evasion), skip
    local suppressedUntil = IADS[samName] or 0  -- per-node suppress table handled below
    -- (we look it up via the side's suppressedUntil table)

    local samPos = getGroupPos(samName)
    if not samPos then return 0 end

    local d = dist3d(samPos, contact.pos)
    if d > IADS_CFG.SAM_ENGAGE_SHARE_RANGE then return 0 end

    -- Range factor: score peaks at 40% of max range, falls off at extremes
    local rangeFactor = 1 - math.abs((d / IADS_CFG.SAM_ENGAGE_SHARE_RANGE) - 0.4)
    rangeFactor = math.max(0.05, rangeFactor)

    -- Altitude factor: prefer targets 500 m – 12000 m
    local alt = contact.pos.y
    local altFactor = 1.0
    if alt < 500 then
        altFactor = alt / 500
    elseif alt > 12000 then
        altFactor = 1 - ((alt - 12000) / 8000)
    end
    altFactor = math.max(0.1, math.min(1.0, altFactor))

    -- Health factor
    local g = Group.getByName(samName)
    local healthFactor = 0
    if g then
        local total, alive = 0, 0
        for _, u in ipairs(g:getUnits()) do
            total = total + 1
            if u:getLife() > 1 then alive = alive + 1 end
        end
        healthFactor = (total > 0) and (alive / total) or 0
    end

    local score = IADS_CFG.PKill_BASE * rangeFactor * altFactor * healthFactor
    return score
end

-- Order a SAM to engage a specific contact through its controller
local function orderSAMEngage(samName, contact)
    local g = Group.getByName(samName)
    if not g then return end
    local ctrl = g:getController()
    if not ctrl then return end

    -- Turn radar ON
    ctrl:setOnOff(true)

    -- Set attack task – DCS will handle the actual missile launch
    local task = {
        id = "EngageUnit",
        params = {
            unitId   = contact.unit:getID(),
            weaponType = 268402688,  -- auto-select
            expend   = "Auto",
        }
    }
    ctrl:pushTask(task)
    log("SAM " .. samName .. " engaging " .. contact.name)
end

-- Distribute contacts across SAM nodes for optimal network coverage
local function optimizeEngagements(coaName)
    local state = IADS[coaName]
    if #state.contacts == 0 then return end

    -- For each contact, pick best-scoring SAM; secondary SAMs stay as backup
    local assigned = {}  -- contactName → samName

    for _, contact in ipairs(state.contacts) do
        -- Only engage contacts that are INSIDE this coalition's own zones.
        -- RED SAMs hold fire until the contact crosses into a RED_ZONE_*.
        -- BLUE SAMs hold fire until the contact crosses into a BLUE_ZONE_*.
        -- Lebanon SAMs hold fire until the contact is in a LEBANON_ZONE_*.
        local inBounds
        if coaName == "LEBANON" then
            inBounds = pointInAnyZone(contact.pos, IADS_CFG.LEBANON_ZONES)
        else
            -- gciState[coaName].zones is keyed by zone name; collect into a list.
            -- Fail open (true) if no zones registered yet so SAMs aren't permanently silenced.
            local zoneNames = {}
            for zoneName, _ in pairs(gciState[coaName].zones) do
                table.insert(zoneNames, zoneName)
            end
            inBounds = (#zoneNames == 0) or pointInAnyZone(contact.pos, zoneNames)
        end
        if inBounds then

        -- Assign up to SAM_MAX_ENGAGE_PER_CONTACT SAMs to the same contact.
        -- Primary fires immediately; secondary fires after a short stagger delay
        -- so cross-fire from two nodes confuses jamming and saturates point-defence.
        local maxAssign = IADS_CFG.SAM_MAX_ENGAGE_PER_CONTACT or 1
        local assigned_count = 0
        local usedSAMs = {}  -- prevent double-assignment in this pass

        for _ = 1, maxAssign do
            local bestSam2, bestScore2 = nil, 0
            for _, samName in ipairs(state.samNodes) do
                if not usedSAMs[samName] then
                    local sup = state.suppressedUntil[samName] or 0
                    if timer.getTime() >= sup then
                        local score = computeEngagementScore(samName, contact)
                        if score > bestScore2 then
                            bestScore2 = score
                            bestSam2   = samName
                        end
                    end
                end
            end

            if bestSam2 and bestScore2 > 0.05 then
                usedSAMs[bestSam2] = true
                assigned_count = assigned_count + 1
                assigned[contact.name] = bestSam2  -- last writer wins for radar-mgmt reverse map

                local stagger = (assigned_count - 1) * 1.5  -- 0s for primary, 1.5s for secondary
                local delay   = stagger
                              + IADS_CFG.SAM_FIRE_DELAY_MIN
                              + math.random() * (IADS_CFG.SAM_FIRE_DELAY_MAX - IADS_CFG.SAM_FIRE_DELAY_MIN)

                local cap_contact = contact
                local cap_sam     = bestSam2
                timer.scheduleFunction(function()
                    if groupAlive(cap_sam)
                    and cap_contact.unit:isExist()
                    and cap_contact.unit:isActive()
                    and cap_contact.unit:getLife() > 1 then
                        orderSAMEngage(cap_sam, cap_contact)
                    end
                    return nil
                end, nil, timer.getTime() + delay)

                log(coaName .. " IADS assigned " .. contact.name .. " to " .. bestSam2
                    .. string.format(" [#%d, score=%.2f, delay=%.1fs]", assigned_count, bestScore2, delay))
            else
                break  -- no more viable SAMs for this contact
            end
        end
        end  -- inBounds
    end

    -- Radar management — two states only:
    --   • SAM has been assigned an in-zone target → radar ON, weapons free (set by orderSAMEngage)
    --   • Everything else (no contacts, contacts outside zone, suppressed) → radar OFF + alarm GREEN
    --
    -- Previously there was a third "contacts exist but outside zone → radar ON, return-fire-only"
    -- state, but long-range SAMs (SA-5 etc.) would autonomously engage with the radar on regardless
    -- of the ROE option setting.  Keeping the radar OFF until our script explicitly assigns a target
    -- is the only reliable way to prevent unsanctioned DCS AI engagement.
    for _, samName in ipairs(state.samNodes) do
        local sup = state.suppressedUntil[samName] or 0
        if timer.getTime() >= sup then
            -- Reverse-lookup: is this SAM currently assigned to any contact?
            local hasAssigned = false
            for _, sName in pairs(assigned) do
                if sName == samName then hasAssigned = true; break end
            end
            local g = Group.getByName(samName)
            if g and g:getController() then
                if not hasAssigned then
                    -- No active assignment — radar off, alarm state green (AI won't self-engage)
                    g:getController():setOnOff(false)
                    g:getController():setOption(9, 1)  -- alarm state: green (passive)
                    g:getController():setOption(0, 4)  -- ROE: return fire only (belt-and-braces)
                end
                -- hasAssigned case: already handled by orderSAMEngage (radar on, weapons free)
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION 6 – ARM & AGM DEFENCE
-- ─────────────────────────────────────────────────────────────────────────────

--[[
    On every SHOT event, check if the weapon is an ARM or tracked AGM.
    If ARM: determine which SAM it's heading toward, suppress that node.
    If AGM: track the weapon and alert nearby SAMs or SHORAD to engage it.
]]

local function suppressSAMRadar(coaName, samName)
    local g = Group.getByName(samName)
    if not g then return end
    local ctrl = g:getController()
    if ctrl then
        ctrl:setOnOff(false)  -- kill radar
        log(coaName .. " SAM " .. samName .. " radar SUPPRESSED (ARM inbound)")
    end

    IADS[coaName].suppressedUntil[samName] = timer.getTime() + IADS_CFG.ARM_SHUTDOWN_TIME

    -- Also briefly silence neighboring SAMs so the ARM seeker can't re-acquire a nearby radar.
    local primaryPos = getGroupPos(samName)
    local neighborRange = IADS_CFG.ARM_NEIGHBOR_SUPPRESS_RANGE or 12000
    local neighborTime  = IADS_CFG.ARM_NEIGHBOR_SUPPRESS_TIME  or 20
    if primaryPos then
        for _, nName in ipairs(IADS[coaName].samNodes) do
            if nName ~= samName then
                local np = getGroupPos(nName)
                if np and dist3d(primaryPos, np) <= neighborRange then
                    local ng = Group.getByName(nName)
                    if ng and ng:getController() then
                        ng:getController():setOnOff(false)
                        if not IADS[coaName].suppressedUntil[nName] or
                           IADS[coaName].suppressedUntil[nName] < timer.getTime() + neighborTime then
                            IADS[coaName].suppressedUntil[nName] = timer.getTime() + neighborTime
                        end
                        log(coaName .. " SAM " .. nName .. " neighbour-darkened for " .. neighborTime .. "s")
                    end
                end
            end
        end
    end

    -- If the unit is mobile (wheeled SAM), attempt relocation
    local sp = getGroupPos(samName)
    if sp then
        local offset = randomOffset(IADS_CFG.ARM_MOVE_RADIUS)
        local newPos = { x = sp.x + offset.x, y = sp.y, z = sp.z + offset.z }

        -- Build a basic move task
        local moveTask = {
            id = "Mission",
            params = {
                route = {
                    points = {
                        {
                            action = "Moving",
                            type   = "Turning Point",
                            x      = newPos.x,
                            y      = newPos.z,  -- DCS 2D waypoint uses x/y for x/z
                            alt    = sp.y,
                            alt_type = "BARO",
                            speed  = 12,
                            ETA    = 0,
                            ETA_locked = false,
                            name   = "",
                            formation_template = "",
                        }
                    }
                }
            }
        }
        if g:getController() then
            g:getController():setTask(moveTask)
            log(coaName .. " SAM " .. samName .. " relocating to avoid ARM")
        end
    end

    -- Schedule radar back ON after suppression window
    local cn_cap  = coaName
    local sn_cap  = samName
    timer.scheduleFunction(function()
        local state = IADS[cn_cap]
        local expiry = state.suppressedUntil[sn_cap] or 0
        if timer.getTime() >= expiry and groupAlive(sn_cap) then
            local gg = Group.getByName(sn_cap)
            if gg and gg:getController() then
                gg:getController():setOnOff(true)
                log(cn_cap .. " SAM " .. sn_cap .. " radar back ONLINE")
            end
        end
        return nil
    end, nil, timer.getTime() + IADS_CFG.ARM_SHUTDOWN_TIME + 2)
end

-- Find which SAM network the ARM is most likely targeting (closest to trajectory)
local function findARMTarget(wpnPos, wpnVel, coaName)
    -- Extrapolate weapon path 60 s forward
    local futurePos = {
        x = wpnPos.x + wpnVel.x * 60,
        y = wpnPos.y + wpnVel.y * 60,
        z = wpnPos.z + wpnVel.z * 60,
    }

    local state = IADS[coaName]
    local best, bestDist = nil, math.huge

    for _, samName in ipairs(state.samNodes) do
        local sp = getGroupPos(samName)
        if sp then
            -- Distance from the projected impact point to each SAM node
            local d = dist3d(futurePos, sp)
            if d < bestDist then
                bestDist = d
                best     = samName
            end
        end
    end
    return best, bestDist
end

-- Alert SAMs and SHORAD near a tracked weapon to engage it.
-- Nodes within INTERCEPT_CLOSE (30 km) go weapons-free alarm-red immediately.
-- Nodes within INTERCEPT_WARN  (60 km) go alarm-red but hold fire (weapons safe)
-- so they're pre-spun up and ready when the weapon closes.
--
-- skipSuppressed: when true, nodes currently in the ARM-suppression window keep
-- their radar dark (so a suppressed SAM does NOT re-light while trying to shoot
-- the very HARM heading at it).  Non-suppressed SHORAD (guns/IR) are unaffected.
local function alertSHORADtoEngageWeapon(weapon, coaName, skipSuppressed)
    local state = IADS[coaName]
    local wpPos = weapon:getPoint()
    if not wpPos then return end

    local CLOSE = 30000   -- metres – engage immediately
    local WARN  = 60000   -- metres – slew radar, standby to engage
    local now   = timer.getTime()

    for _, samName in ipairs(state.samNodes) do
        -- Skip nodes that are currently suppressed (ARM evasion – keep radar dark)
        local suppressed = false
        if skipSuppressed then
            local supUntil = state.suppressedUntil and state.suppressedUntil[samName] or 0
            suppressed = now < supUntil
        end

        if not suppressed then
            local sp = getGroupPos(samName)
            if sp then
                local d = dist3d(sp, wpPos)
                local g = Group.getByName(samName)
                if g and g:getController() then
                    if d <= CLOSE then
                        -- In the kill chain – weapons free, alarm red
                        g:getController():setOnOff(true)
                        g:getController():setOption(0, 2)   -- ROE: weapons free
                        g:getController():setOption(9, 2)   -- alarm state: red
                    elseif d <= WARN then
                        -- Within warning range – wake up radar, hold fire
                        g:getController():setOnOff(true)
                        g:getController():setOption(9, 2)   -- alarm state: red (tracking mode)
                    end
                end
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION 7 – EVENT HANDLER (shots, hits, dead)
-- ─────────────────────────────────────────────────────────────────────────────

local eventHandler = {}

function eventHandler:onEvent(event)

    -- ── WEAPON SHOT ────────────────────────────────────────────────────────
    if event.id == world.event.S_EVENT_SHOT then
        local wpn = event.weapon
        if not wpn then return end

        local typeName = wpn:getTypeName() or ""

        -- Check if this weapon is an ARM
        local isARM = false
        for armType, _ in pairs(IADS_CFG.ARM_TYPES) do
            if string.find(typeName, armType, 1, true) then
                isARM = true; break
            end
        end

        -- Check if this weapon is a tracked AGM
        local isAGM = false
        for agmType, _ in pairs(IADS_CFG.AGM_TYPES) do
            if string.find(typeName, agmType, 1, true) then
                isAGM = true; break
            end
        end

        if isARM or isAGM then
            -- Determine which side fired (attacker coalition)
            local initiator = event.initiator
            local shotCoa   = initiator and initiator:getCoalition() or nil

            -- Determine the defending coalition
            local defendCoaName = nil
            if shotCoa == coalition.side.BLUE then
                defendCoaName = "RED"
            elseif shotCoa == coalition.side.RED then
                defendCoaName = "BLUE"
            end

            if defendCoaName then
                table.insert(trackedWeapons, {
                    weapon       = wpn,
                    isARM        = isARM,
                    isAGM        = isAGM,
                    targetCoa    = defendCoaName,
                    launchTime   = timer.getTime(),
                    alerted      = false,
                })
                -- If the ARM is targeting a RED-side unit it may be aimed at Lebanon SAMs;
                -- queue a second entry so the Lebanon sub-IADS also gets ARM warning.
                if defendCoaName == "RED" then
                    table.insert(trackedWeapons, {
                        weapon       = wpn,
                        isARM        = isARM,
                        isAGM        = isAGM,
                        targetCoa    = "LEBANON",
                        launchTime   = timer.getTime(),
                        alerted      = false,
                    })
                end
                log("Tracking " .. (isARM and "ARM" or "AGM") .. ": " .. typeName
                    .. " vs " .. defendCoaName)
            end
        end
    end

    -- ── UNIT DEAD ──────────────────────────────────────────────────────────
    if event.id == world.event.S_EVENT_DEAD or event.id == world.event.S_EVENT_CRASH then
        local unit = event.initiator
        -- Static objects and weapons also trigger DEAD events but lack getGroup()
        if not unit or not unit.getGroup then return end
        local groupObj = unit:getGroup()
        if groupObj then
            local gName = groupObj:getName()
            -- Check both coalition flight registries
            for _, cn in ipairs({"RED", "BLUE"}) do
                local fs = gciState[cn].flights[gName]
                if fs and fs.status ~= "dead" then
                    fs.status = "dead"
                    log(cn .. " flight " .. gName .. " KIA")
                end
            end
        end
    end
end

world.addEventHandler(eventHandler)

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION 8 – WEAPON TRACKING LOOP
-- ─────────────────────────────────────────────────────────────────────────────

local function weaponTrackingLoop()
    local now    = timer.getTime()
    local active = {}

    for _, wt in ipairs(trackedWeapons) do
        local wpn = wt.weapon

        -- Check if weapon still alive (getPoint returns nil when spent)
        local ok, wpnPos = pcall(function() return wpn:getPoint() end)
        if not ok or not wpnPos then
            -- Weapon has hit / expired – nothing to do
        else
            local vel = wpn:getVelocity()

            if wt.isARM then
                if not wt.alerted then
                    -- Find the SAM node most likely targeted and suppress it.
                    -- Trigger earlier (ARM_SUPPRESS_TRIGGER_DIST, default 150 km) so
                    -- the SAM has time to go dark before the HARM seeker locks it.
                    local trigger_dist = IADS_CFG.ARM_SUPPRESS_TRIGGER_DIST or 150000
                    local target, dist = findARMTarget(wpnPos, vel, wt.targetCoa)
                    if target and dist < trigger_dist then
                        suppressSAMRadar(wt.targetCoa, target)
                        wt.alerted = true
                    end
                end
                -- Once the ARM is tracked, alert all non-suppressed SHORAD to engage
                -- it every tick.  skipSuppressed=true keeps the targeted SAM's radar
                -- dark while allowing nearby guns / IR SAMs to attempt a kill.
                if wt.alerted then
                    alertSHORADtoEngageWeapon(wpn, wt.targetCoa, true)
                end
            end

            if wt.isAGM then
                -- Continuously alert SHORAD to try to intercept
                alertSHORADtoEngageWeapon(wpn, wt.targetCoa, false)
            end

            -- Keep weapon in tracking list
            table.insert(active, wt)
        end
    end

    trackedWeapons = active
    return timer.getTime() + IADS_CFG.WEAPON_TRACK_INTERVAL
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION 9 – MAIN IADS UPDATE LOOP
-- ─────────────────────────────────────────────────────────────────────────────

local function iadsUpdateLoop()

    -- Rebuild node lists (units can be killed between cycles).
    -- Main RED excludes RED_SAM_LEBANON_ / RED_EWR_LEBANON_ groups (3rd arg = excludePrefix).
    buildNodeList("RED",     coalition.side.RED,  "RED_SAM_",         "RED_EWR_",         "RED_SAM_LEBANON_")
    buildNodeList("BLUE",    coalition.side.BLUE, "BLUE_SAM_",        "BLUE_EWR_")
    -- Lebanon sub-IADS: RED coalition units, own prefix, isolated from main RED.
    buildNodeList("LEBANON", coalition.side.RED,  "RED_SAM_LEBANON_", "RED_EWR_LEBANON_")

    -- Gather air contacts for each side
    gatherContacts("RED",     coalition.side.BLUE)
    gatherContacts("BLUE",    coalition.side.RED)
    gatherContacts("LEBANON", coalition.side.BLUE)  -- Lebanon sees BLUE threats independently

    -- Optimise and order engagements
    optimizeEngagements("RED")
    optimizeEngagements("BLUE")
    optimizeEngagements("LEBANON")

    return timer.getTime() + IADS_CFG.UPDATE_INTERVAL
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION 10 – ZONE DISCOVERY  (both coalitions)
-- ─────────────────────────────────────────────────────────────────────────────

-- Scan MIST zone DB for RED_ZONE_ and BLUE_ZONE_ prefixed zones and register them.
local function discoverZones()
    if not (mist and mist.DBs and mist.DBs.zonesByName) then
        log("MIST zone DB not available – zones must be registered manually via registerRedZone / registerBlueZone")
        return
    end
    local function tryRegister(coaName, prefix)
        for zoneName, _ in pairs(mist.DBs.zonesByName) do
            if string.sub(zoneName, 1, #prefix) == prefix then
                if not gciState[coaName].zones[zoneName] then
                    gciState[coaName].zones[zoneName] = { clearSince = nil }
                    log("Discovered " .. coaName .. " intercept zone: " .. zoneName)
                end
            end
        end
    end
    tryRegister("RED",  "RED_ZONE_")
    tryRegister("BLUE", "BLUE_ZONE_")
end

-- Backward-compat aliases (can still call from ME triggers)
function registerRedZone(zoneName)
    if not gciState.RED.zones[zoneName] then
        gciState.RED.zones[zoneName] = { clearSince = nil }
        log("Registered RED intercept zone: " .. zoneName)
    end
end
function registerBlueZone(zoneName)
    if not gciState.BLUE.zones[zoneName] then
        gciState.BLUE.zones[zoneName] = { clearSince = nil }
        log("Registered BLUE intercept zone: " .. zoneName)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION 11 – GCI UTILITY FUNCTIONS
-- ─────────────────────────────────────────────────────────────────────────────

-- Broadcast a GCI/AWACS text message to one coalition's players
local function gciMsg(coalName, text, duration)
    local coaID  = (coalName == "RED") and coalition.side.RED or coalition.side.BLUE
    local prefix = (IADS_CFG.GCI_CALLSIGN or {})[coalName] or "GCI"
    trigger.action.outTextForCoalition(
        coaID,
        "[" .. prefix .. "]  " .. text,
        duration or 14,
        false
    )
end

-- True bearing (0-360°) from point src to point dst
local function bearingTo(src, dst)
    local b = math.deg(math.atan2(dst.x - src.x, dst.z - src.z))
    return math.fmod(b + 360, 360)
end

-- Get contact centroid and format a BULLSEYE-style range/bearing string.
local function contactPicture(contacts, refPt)
    if #contacts == 0 then return "no contacts", nil end
    local sx, sz = 0, 0
    local high, med, low = 0, 0, 0
    for _, c in ipairs(contacts) do
        sx = sx + c.pos.x;  sz = sz + c.pos.z
        local alt = c.pos.y
        if     alt > 7500 then high = high + 1
        elseif alt > 3000 then med  = med  + 1
        else                   low  = low  + 1
        end
    end
    local cx = sx / #contacts
    local cz = sz / #contacts
    local centroid = { x = cx, y = 0, z = cz }
    local brg = bearingTo(refPt, centroid)
    local rng = dist2d(refPt, centroid) / 1852   -- nm
    local bands = {}
    if high > 0 then table.insert(bands, high .. " high") end
    if med  > 0 then table.insert(bands, med  .. " medium") end
    if low  > 0 then table.insert(bands, low  .. " low") end
    local posStr = string.format("%03d° / %d nm, %s",
        math.floor(brg + 0.5), math.floor(rng + 0.5), table.concat(bands, ", "))
    return posStr, centroid
end

-- First alive EWR or AWACS position, used as GCI reference point.
local function gciRefPoint(coalName)
    local myCoaID    = (coalName == "RED") and coalition.side.RED or coalition.side.BLUE
    local awacsPrefix = (coalName == "RED") and (IADS_CFG.AWACS_PREFIX_RED  or "RED_AWACS_")
                                             or  (IADS_CFG.AWACS_PREFIX_BLUE or "BLUE_AWACS_")
    -- Prefer AWACS position
    for _, gName in ipairs(getAirGroupsByPrefix(myCoaID, awacsPrefix)) do
        local p = getGroupPos(gName)
        if p then return p end
    end
    -- Fall back to first EWR node
    for _, n in ipairs(IADS[coalName].ewrNodes) do
        local p = getGroupPos(n)
        if p then return p end
    end
    -- Syria map centre
    return { x = -110000, y = 500, z = 50000 }
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION 12 – AWACS PICTURE BROADCAST
-- ─────────────────────────────────────────────────────────────────────────────

local function broadcastPicture(coalName)
    -- No player-controlled RED aircraft — suppress RED picture broadcasts entirely.
    if coalName == "RED" then return end

    local contacts    = IADS[coalName].contacts
    local awacsCS     = (IADS_CFG.AWACS_CALLSIGN or {})[coalName] or "AWACS"
    local myCoaID     = coalition.side.BLUE
    local awacsPrefix = IADS_CFG.AWACS_PREFIX_BLUE or "BLUE_AWACS_"

    -- Only broadcast if a BLUE AWACS is airborne
    local awacsAlive = false
    for _, gName in ipairs(getAirGroupsByPrefix(myCoaID, awacsPrefix)) do
        if groupAlive(gName) then awacsAlive = true; break end
    end
    if not awacsAlive then return end

    -- Suppress picture-clear chatter — only call when threats are actually present
    if #contacts == 0 then return end

    local refPt = gciRefPoint(coalName)

    -- Group contacts by DCS flight group; compute centroid BRA and lead altitude per group.
    local grpMap   = {}   -- key = group name, value = { count, sx, sz, maxAlt }
    local grpOrder = {}   -- insertion-order list of keys (for deterministic output)
    for _, c in ipairs(contacts) do
        local gKey = (c.group and c.group:isExist() and c.group:getName()) or c.name
        if not grpMap[gKey] then
            grpMap[gKey] = { count = 0, sx = 0, sz = 0, maxAlt = 0 }
            table.insert(grpOrder, gKey)
        end
        local e = grpMap[gKey]
        e.count  = e.count + 1
        e.sx     = e.sx + c.pos.x
        e.sz     = e.sz + c.pos.z
        if c.pos.y > e.maxAlt then e.maxAlt = c.pos.y end
    end

    -- Build one line per group: "  GroupName ×N  BRG°/RNGnm  Angels A"
    local lines = {}
    for _, gKey in ipairs(grpOrder) do
        local e     = grpMap[gKey]
        local cPos  = { x = e.sx / e.count, z = e.sz / e.count }
        local brg   = math.floor(bearingTo(refPt, cPos) + 0.5)
        local rng   = math.floor(dist2d(refPt, cPos) / 1852 + 0.5)          -- nm
        local angls = math.floor(e.maxAlt * 3.28084 / 1000 + 0.5)            -- angels (kft)
        local suffix = e.count > 1 and (" x" .. e.count) or ""
        table.insert(lines, string.format("  %s%s  %03d° / %d nm  Angels %d",
            gKey, suffix, brg, rng, angls))
    end

    local msg = string.format("[%s]  PICTURE — %d group(s):\n%s",
        awacsCS, #grpOrder, table.concat(lines, "\n"))
    trigger.action.outTextForCoalition(myCoaID, msg, 20, false)
    env.info("[IADS] " .. coalName .. " " .. msg, false)
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION 12b – AWACS ORBIT KEEPER
-- ─────────────────────────────────────────────────────────────────────────────
-- Runs every 30 s and re-assigns a Circle orbit task to any BLUE AWACS group
-- that has drifted more than 1000 ft below its configured altitude.  This
-- recovers from any external interference (other scripts, DCS AI quirks, etc.)
-- without touching the AWACS if it is already flying at the correct altitude.
local function awacsOrbitLoop()
    local altM   = (IADS_CFG.AWACS_ORBIT_ALT_FT or 30000) * 0.3048   -- ft → m
    local spdMS  = (IADS_CFG.AWACS_ORBIT_KTS    or 350)   * 0.514444  -- kts → m/s
    local thresh = altM - 305   -- 1000 ft below target triggers correction

    local myCoaID     = coalition.side.BLUE
    local awacsPrefix = IADS_CFG.AWACS_PREFIX_BLUE or "BLUE_AWACS_"

    for _, gName in ipairs(getAirGroupsByPrefix(myCoaID, awacsPrefix)) do
        if groupAlive(gName) then
            local p = getGroupPos(gName)
            if p and p.y < thresh then
                local g = Group.getByName(gName)
                if g then
                    local ctrl = g:getController()
                    if ctrl then
                        ctrl:setTask({
                            id = "Orbit",
                            params = {
                                pattern  = "Circle",
                                speed    = spdMS,
                                altitude = altM,
                            }
                        })
                        log("AWACS " .. gName .. " altitude recovery – orbit restored at FL"
                            .. math.floor(altM * 3.28084 / 100 + 0.5))
                    end
                end
            end
        end
    end
    return timer.getTime() + 30
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION 13 – SQUADRON HELPERS
-- ─────────────────────────────────────────────────────────────────────────────

-- Available (late-activate, not airborne, not dead) groups for a squadron
local function getAvailableFlights(sqd, gciSt)
    local available = {}
    local prefix    = sqd.groupPrefix
    if mist and mist.DBs and mist.DBs.groupsByName then
        for gName, _ in pairs(mist.DBs.groupsByName) do
            if string.sub(gName, 1, #prefix) == prefix then
                local fs = gciSt.flights[gName]
                if not fs or fs.status == "standby" then
                    local g = Group.getByName(gName)
                    -- Determine if this group is already airborne.
                    -- Preferred: g:isActive() — returns false for late-activate unspawned groups.
                    -- Fallback (some DCS builds lack isActive on certain objects): check if any
                    -- unit is physically above 1500 m.  Late-activate parked aircraft are at airbase
                    -- elevation (<800 m in Syria); airborne groups (AWACS, active flights) are far
                    -- higher.  This prevents AWACS being mis-classified as an available slot.
                    local isActiveNow = false
                    if g then
                        if g.isActive then
                            isActiveNow = g:isActive()
                        else
                            -- altitude-based fallback
                            for _, u in ipairs(g:getUnits()) do
                                local p = u:getPoint()
                                if p and p.y > 1500 then
                                    isActiveNow = true
                                    break
                                end
                            end
                        end
                    end
                    if not isActiveNow then
                        table.insert(available, gName)
                    end
                end
            end
        end
    end
    return available
end

-- Count airborne flights belonging to a specific squadron
local function countAirborne(sqd, gciSt)
    local count  = 0
    local prefix = sqd.groupPrefix
    for gName, fs in pairs(gciSt.flights) do
        if string.sub(gName, 1, #prefix) == prefix and fs.status == "airborne" then
            count = count + 1
        end
    end
    return count
end

-- Contacts from IADS[coaName].contacts that are within or approaching a zone
local function getThreatsForZone(zoneName, coaName)
    local threats = {}
    local zd = trigger.misc.getZone(zoneName)
    if not zd then
        -- Zone name mismatch – log once per zone to help diagnose
        log("[GCI] getThreatsForZone: zone '" .. zoneName .. "' not found – check exact ME name")
        return threats
    end
    local zPos    = zd.point
    local zRadius = zd.radius + (IADS_CFG.SCRAMBLE_THREAT_BUFFER or 0)

    -- Use a direct aircraft position scan rather than radar contacts.
    -- This means the GCI will scramble even if the enemy is below radar coverage,
    -- in a notch, or otherwise undetected.  Radar contacts (IADS[coaName].contacts)
    -- are still used for the picture broadcast; they are NOT used here.
    local enemyCoa = (coaName == "RED") and coalition.side.BLUE or coalition.side.RED
    local groups   = coalition.getGroups(enemyCoa, Group.Category.AIRPLANE)
    for _, grp in ipairs(groups or {}) do
        if grp and grp:isExist() then
            for _, u in ipairs(grp:getUnits()) do
                if u:isExist() and u:isActive() and u:getLife() > 1 then
                    local uPos = u:getPoint()
                    if uPos and dist2d(uPos, zPos) <= zRadius then
                        table.insert(threats, { unit = u, pos = uPos, group = grp })
                        break  -- one entry per group is enough
                    end
                end
            end
        end
    end
    return threats
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION 14 – SCRAMBLE & RTB
-- ─────────────────────────────────────────────────────────────────────────────

-- Activate a late-activate group, broadcast GCI scramble call, assign intercept task.
local function dispatchFlight(groupName, coalName, sqd, threats, gciSt)
    log("Dispatching " .. coalName .. " flight: " .. groupName)

    -- trigger.action.activateGroup is the correct DCS API for late-activate groups
    local g = Group.getByName(groupName)
    if g then
        trigger.action.activateGroup(g)
    else
        -- Group.getByName() returned nil – the ME group name likely doesn't exactly
        -- match groupPrefix in IADS_CFG.SQUADRONS.  Check [SqdValidate] in DCS.log.
        log("*** DISPATCH FAILED: Group.getByName('" .. groupName .. "') returned nil."
            .. " Verify the ME group name matches groupPrefix in IADS_CFG.SQUADRONS.")
        trigger.action.outText("[IADS] DISPATCH ERROR: group '" .. groupName
            .. "' not found. Check DCS.log.", 15, false)
        return
    end

    local myCoaID = (coalName == "RED") and coalition.side.RED or coalition.side.BLUE

    gciSt.flights[groupName] = {
        status     = "airborne",
        zone       = sqd.zone,
        homeBase   = sqd.homeBase,
        callsign   = sqd.callsign,
        coalName   = coalName,
        launchTime = timer.getTime(),
    }

    -- Determine the actual aircraft type(s) in this group for the GCI call.
    -- Read from MIST DB (available before activation) then deduplicate.
    local function getGroupTypeStr(gName)
        local types = {}
        local seen  = {}
        local dbGrp = mist and mist.DBs and mist.DBs.groupsByName and mist.DBs.groupsByName[gName]
        if dbGrp and dbGrp.units then
            for _, u in ipairs(dbGrp.units) do
                local t = u.type or u.unitType
                if t and not seen[t] then
                    seen[t] = true
                    table.insert(types, t)
                end
            end
        end
        if #types == 0 then return "Unknown" end
        return table.concat(types, "/")
    end

    -- GCI scramble radio call – includes actual aircraft type
    local refPt    = gciRefPoint(coalName)
    local posStr   = (#threats > 0) and contactPicture(threats, refPt) or "unknown position"
    local typeStr  = getGroupTypeStr(groupName)
    gciMsg(coalName,
        string.format("SCRAMBLE – %s (%s). Vector %s. %d hostile(s). Cleared to engage.",
            sqd.callsign, typeStr, posStr, #threats),
        16)

    -- Assign task after short spawn delay
    local cap_gName    = groupName
    local cap_coalName = coalName
    local cap_sqd      = sqd
    local cap_threats  = threats
    timer.scheduleFunction(function()
        local grp = Group.getByName(cap_gName)
        if not grp then return nil end
        local ctrl = grp:getController()
        if not ctrl then return nil end

        ctrl:setOption(0, 2)  -- ROE weapons free
        ctrl:setOption(1, 0)  -- aggressive threat reaction

        local targetUnit = cap_threats[1] and cap_threats[1].unit or nil
        local taskDef
        if targetUnit and targetUnit:isExist() and targetUnit:isActive() and targetUnit:getLife() > 1 then
            taskDef = {
                id = "EngageUnit",
                params = {
                    unitId     = targetUnit:getID(),
                    weaponType = 268402688,
                    expend     = "Auto",
                }
            }
        else
            -- Orbit over zone centre
            local zd  = trigger.misc.getZone(cap_sqd.zone)  -- native DCS API, correct world coords
            local ox   = zd and zd.point.x or 0
            local oz   = zd and zd.point.z or 0
            taskDef = {
                id = "Orbit",
                params = {
                    pattern  = "Circle",
                    speed    = IADS_CFG.INTERCEPT_SPEED / 3.6,
                    altitude = IADS_CFG.INTERCEPT_ALTITUDE,
                    point    = { x = ox, y = oz },
                }
            }
        end

        ctrl:setTask({ id = "ComboTask", params = { tasks = { taskDef } } })
        log(cap_coalName .. " intercept task set for " .. cap_gName)
        return nil
    end, nil, timer.getTime() + 4)
end

-- Order a flight RTB to its designated home base, then stand it down.
local function orderFlightRTB(groupName, gciSt, reason)
    local fState = gciSt.flights[groupName]
    local grp    = Group.getByName(groupName)
    if not grp then
        if fState then fState.status = "dead" end
        return
    end

    local ctrl = grp:getController()
    if not ctrl then return end

    -- Determine home airbase: use stored home, fall back to nearest.
    local homeName = fState and fState.homeBase
    local homeAB   = homeName and Airbase.getByName(homeName)
    local grpPos   = getGroupPos(groupName)
    if not homeAB and grpPos then
        homeAB = getNearestAirbase(grpPos, grp:getCoalition())
    end

    ctrl:setOption(0, 4)  -- ROE return fire only

    if homeAB and grpPos then
        local abPos = homeAB:getPoint()
        ctrl:setTask({
            id = "Mission",
            params = {
                route = {
                    points = {
                        {
                            type = "Turning Point", action = "Turning Point",
                            x = grpPos.x, y = grpPos.z,
                            alt = IADS_CFG.INTERCEPT_ALTITUDE, alt_type = "BARO",
                            speed = IADS_CFG.INTERCEPT_SPEED / 3.6,
                            ETA = 0, ETA_locked = false,
                            name = "RTB", formation_template = "",
                        },
                        {
                            type = "Land", action = "Landing",
                            x = abPos.x, y = abPos.z,
                            alt = abPos.y or 10, alt_type = "BARO",
                            speed = 250 / 3.6, ETA = 0, ETA_locked = false,
                            name = "Landing", airdromeId = homeAB:getID(),
                            formation_template = "",
                        },
                    }
                }
            }
        })
        log(groupName .. " RTB → " .. homeAB:getName() .. " (" .. (reason or "") .. ")")
    end

    if fState then fState.status = "rtb" end

    -- GCI RTB radio call
    if fState and fState.callsign and fState.coalName then
        gciMsg(fState.coalName,
            fState.callsign .. ", RTB. " .. (reason or "Zone clear."), 12)
    end

    -- Destroy / stand down after landing time (~10 min)
    local gn_cap = groupName
    timer.scheduleFunction(function()
        local fs = gciSt.flights[gn_cap]
        if fs and fs.status == "rtb" then
            local gg = Group.getByName(gn_cap)
            if gg then gg:destroy() end
            fs.status = "standby"
            log(gn_cap .. " stood down after RTB")
        end
        return nil
    end, nil, timer.getTime() + 600)
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION 15 – MAIN GCI / INTERCEPT LOOP  (both sides)
-- ─────────────────────────────────────────────────────────────────────────────

local function gciInterceptLoop()
    local now      = timer.getTime()
    local squadrons = IADS_CFG.SQUADRONS or { RED = {}, BLUE = {} }

    for _, coalName in ipairs({"RED", "BLUE"}) do
        local gciSt   = gciState[coalName]
        local sqds    = squadrons[coalName] or {}

        -- ── AWACS picture broadcast ────────────────────────────────────────
        if (now - (gciSt.lastPicture or 0)) >= (IADS_CFG.GCI_PICTURE_INTERVAL or 180) then
            broadcastPicture(coalName)
            gciSt.lastPicture = now
        end

        -- ── Per-squadron scramble / RTB logic ─────────────────────────────
        for _, sqd in ipairs(sqds) do
            local threats  = getThreatsForZone(sqd.zone, coalName)
            local airborne = countAirborne(sqd, gciSt)

            if #threats > 0 then
                -- Reset zone clear timer
                if gciSt.zones[sqd.zone] then
                    gciSt.zones[sqd.zone].clearSince = nil
                end

                -- Scramble additional flights if under-strength
                local needed = math.min(#threats, sqd.maxFlights) - airborne
                if needed > 0 then
                    local available = getAvailableFlights(sqd, gciSt)
                    local toSend    = math.min(needed, #available)
                    for i = 1, toSend do
                        dispatchFlight(available[i], coalName, sqd, threats, gciSt)
                    end
                end

            elseif airborne > 0 then
                -- No threats — start / advance the clear timer
                local zSt = gciSt.zones[sqd.zone]
                if not zSt then
                    gciSt.zones[sqd.zone] = { clearSince = now }
                    zSt = gciSt.zones[sqd.zone]
                end
                if zSt.clearSince == nil then
                    zSt.clearSince = now
                    log(coalName .. " zone " .. sqd.zone .. " clear – starting RTB loiter")
                end
                if (now - zSt.clearSince) >= IADS_CFG.RTB_LOITER_TIME then
                    for gName, fs in pairs(gciSt.flights) do
                        if string.sub(gName, 1, #sqd.groupPrefix) == sqd.groupPrefix
                        and fs.status == "airborne" then
                            orderFlightRTB(gName, gciSt, "Zone clear.")
                        end
                    end
                end
            end
        end
    end

    return now + IADS_CFG.AIR_INTERCEPT_INTERVAL
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION 16 – FUEL MONITORING & FLIGHT MAINTENANCE  (both sides)
-- ─────────────────────────────────────────────────────────────────────────────

local function flightMaintenanceLoop()
    local fuelMin    = IADS_CFG.GCI_FUEL_RTB_THRESHOLD or 0.20
    local leashExtra = IADS_CFG.INTERCEPT_LEASH_BUFFER or 40000

    for _, coalName in ipairs({"RED", "BLUE"}) do
        local gciSt = gciState[coalName]
        for gName, fs in pairs(gciSt.flights) do
            if fs.status == "airborne" then
                local grp = Group.getByName(gName)
                if grp then
                    local alive      = false
                    local lowestFuel = 1.0
                    for _, u in ipairs(grp:getUnits()) do
                        if u:getLife() > 1 then
                            alive = true
                            local f = u:getFuel()
                            if f < lowestFuel then lowestFuel = f end
                        end
                    end
                    if not alive then
                        fs.status = "dead"
                        log(gName .. " KIA (maintenance loop)")
                    elseif lowestFuel < fuelMin then
                        log(string.format("%s bingo fuel (%.0f%%) – RTB", gName, lowestFuel * 100))
                        orderFlightRTB(gName, gciSt,
                            string.format("Bingo fuel (%.0f%%).", lowestFuel * 100))
                    else
                        -- Leash check: recall immediately if the flight has strayed too far
                        -- from its assigned zone, regardless of the RTB_LOITER_TIME timer.
                        -- Prevents fighters chasing the player deep into friendly territory.
                        local fPos = getGroupPos(gName)
                        local zd   = fs.zone and trigger.misc.getZone(fs.zone)
                        if fPos and zd and zd.point and zd.radius then
                            local distFromZone = dist2d(fPos, zd.point)
                            if distFromZone > (zd.radius + leashExtra) then
                                log(gName .. " leash exceeded (" .. math.floor(distFromZone/1000)
                                    .. " km from zone centre) – RTB")
                                orderFlightRTB(gName, gciSt, "Leash limit – RTB.")
                            end
                        end
                    end
                else
                    if fs.status ~= "dead" then
                        fs.status = "dead"
                        log(gName .. " group gone – marked dead")
                    end
                end
            end
        end
    end

    return timer.getTime() + IADS_CFG.RTB_CHECK_INTERVAL
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION 13 – INITIALISATION
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
--  STARTUP VALIDATOR – logs every squadron prefix and the groups it found.
--  Check DCS.log for "[SqdValidate]" lines after mission start.
--  Any line showing "NONE FOUND" means the ME group names don't match the prefix.
-- ─────────────────────────────────────────────────────────────────────────────
local function validateSquadrons()
    if not (mist and mist.DBs and mist.DBs.groupsByName) then
        log("[SqdValidate] MIST DB not available – cannot validate squadron prefixes")
        return
    end

    local sqds = IADS_CFG.SQUADRONS or { RED = {}, BLUE = {} }
    local overallOK = true

    for _, coalName in ipairs({"RED", "BLUE"}) do
        for _, sqd in ipairs(sqds[coalName] or {}) do
            local prefix    = sqd.groupPrefix
            local found     = {}
            for gName, _ in pairs(mist.DBs.groupsByName) do
                if string.sub(gName, 1, #prefix) == prefix then
                    table.insert(found, gName)
                end
            end
            table.sort(found)
            if #found == 0 then
                log(string.format("[SqdValidate] *** MISMATCH *** %s | callsign=%-10s | prefix=%-30s | NONE FOUND in MIST DB",
                    coalName, sqd.callsign, prefix))
                overallOK = false
            else
                log(string.format("[SqdValidate] OK  %s | callsign=%-10s | prefix=%-30s | found: %s",
                    coalName, sqd.callsign, prefix, table.concat(found, ", ")))
            end
        end
    end

    if overallOK then
        log("[SqdValidate] All squadron prefixes matched – dispatch should work.")
    else
        log("[SqdValidate] One or more prefixes had NO matching groups. Check DCS.log and rename either the script groupPrefix entries or the ME group names to match.")
        trigger.action.outText("[IADS] WARNING: Some squadron group prefixes found no ME groups. Check DCS.log for [SqdValidate] lines.", 20, false)
    end
end

local function init()
    log("=== RED/BLUE IADS + Air Intercept System initialising ===")

    -- Note: DCS sandboxes math.randomseed; math.random() still works unseeded.

    -- Check MIST availability
    if not mist then
        log("WARNING: MIST not loaded. Some features may not work correctly!")
    else
        log("MIST version: " .. (mist.majorVersion or "?") .. "." .. (mist.minorVersion or "?"))
    end

    -- Validate squadron prefixes against MIST group database.
    -- Logs every prefix with the groups it found (or NONE FOUND for mismatches).
    validateSquadrons()

    -- Discover RED_ZONE_ and BLUE_ZONE_ trigger zones via MIST DB
    discoverZones()

    -- Initial IADS node build
    buildNodeList("RED",     coalition.side.RED,  "RED_SAM_",         "RED_EWR_",         "RED_SAM_LEBANON_")
    buildNodeList("BLUE",    coalition.side.BLUE, "BLUE_SAM_",        "BLUE_EWR_")
    buildNodeList("LEBANON", coalition.side.RED,  "RED_SAM_LEBANON_", "RED_EWR_LEBANON_")

    -- Schedule main loops
    timer.scheduleFunction(iadsUpdateLoop,       {}, timer.getTime() + 10)
    timer.scheduleFunction(weaponTrackingLoop,    {}, timer.getTime() + 5)
    timer.scheduleFunction(gciInterceptLoop,      {}, timer.getTime() + 15)
    timer.scheduleFunction(flightMaintenanceLoop, {}, timer.getTime() + 30)
    timer.scheduleFunction(awacsOrbitLoop,        {}, timer.getTime() + 20)

    -- Periodic IADS node-list rebuild (drops destroyed SAM/EWR groups).
    -- Runs every NODE_REFRESH_INTERVAL seconds (default 900 = 15 min).
    -- SAM sites are one-and-done: dead groups simply won't appear on the
    -- next rebuild and will be silently pruned from all tracking tables.
    local NODE_REFRESH_INTERVAL = IADS_CFG.NODE_REFRESH_INTERVAL or 900
    local function nodeRefreshLoop(_, time)
        log("[NodeRefresh] Rebuilding IADS node lists...")
        buildNodeList("RED",     coalition.side.RED,  "RED_SAM_",         "RED_EWR_",         "RED_SAM_LEBANON_")
        buildNodeList("BLUE",    coalition.side.BLUE, "BLUE_SAM_",        "BLUE_EWR_")
        buildNodeList("LEBANON", coalition.side.RED,  "RED_SAM_LEBANON_", "RED_EWR_LEBANON_")
        log(string.format("[NodeRefresh] Done. RED: %d SAMs  BLUE: %d SAMs  LEBANON: %d SAMs",
            #IADS.RED.samNodes, #IADS.BLUE.samNodes, #IADS.LEBANON.samNodes))
        return time + NODE_REFRESH_INTERVAL
    end
    timer.scheduleFunction(nodeRefreshLoop, {}, timer.getTime() + NODE_REFRESH_INTERVAL)

    log("=== Initialisation complete ===")
    trigger.action.outText("[IADS] RED/BLUE Integrated Air Defence + Red Air Intercept ACTIVE", 10, false)
end

-- Delay init slightly to ensure MIST is fully loaded
timer.scheduleFunction(function()
    init()
    return nil
end, {}, timer.getTime() + 1)

-- =============================================================================
--  END OF SCRIPT
--  
--  QUICK REFERENCE – HOW TO SET UP YOUR MISSION
--  ─────────────────────────────────────────────
--  1. LOAD ORDER in the Mission Editor (DO Script File triggers at T=0):
--       a) mist_4_5_107.lua  (or current MIST version)
--       b) RED_BLUE_IADS_Intercept.lua  (this file)
--
--  2. NAME YOUR GROUPS exactly with these prefixes:
--       RED SAM examples (Syria map):
--         RED_SAM_S300_DAMASCUS      – S-300PS site near Damascus Intl
--         RED_SAM_BUK_HOMS           – Buk-M2 battery, Homs area
--         RED_SAM_SA6_PALMYRA        – SA-6 Kub, Palmyra / T4 corridor
--         RED_SAM_PANTSIR_KHMEIMIM   – Pantsir-S1 airbase defence, Latakia
--         RED_SAM_TOR_ALEPPO         – Tor-M1, Aleppo sector
--         RED_SAM_OSA_RAQQA          – SA-8 Osa, Raqqa sector
--         RED_SAM_TUNGUSKA_DEIR      – SA-19 Tunguska, Deir ez-Zor
--       RED EWR examples (Syria map):
--         RED_EWR_55G6_LATAKIA       – 55G6 Tall King, elevated coastal site
--         RED_EWR_P18_DAMASCUS       – P-18 Spoon Rest, Damascus plateau
--         RED_EWR_NEBO_PALMYRA       – Nebo-SVU AESA EWR, central Syria
--       BLUE SAM examples:
--         BLUE_SAM_PATRIOT_INCIRLIK
--         BLUE_SAM_HAWK_AKROTIRI
--         BLUE_SAM_NASAMS_RAMAT_DAVID
--       BLUE EWR examples:
--         BLUE_EWR_E3_ORBIT          – (place the AWACS aircraft in a group)
--         BLUE_EWR_MPDR_INCIRLIK
--
--  3. NAME YOUR TRIGGER ZONES: RED_ZONE_<SECTOR>  (Syria sectors)
--       RED_ZONE_DAMASCUS        – Damascus / southern Syria
--       RED_ZONE_ALEPPO          – Aleppo / northern Syria
--       RED_ZONE_LATAKIA         – Coastal / Latakia / Khmeimim
--       RED_ZONE_HOMS            – Homs / central corridor
--       RED_ZONE_PALMYRA         – Palmyra / T4 / eastern central
--       RED_ZONE_DEIR_EZ_ZOR     – Eastern Syria / Euphrates valley
--       RED_ZONE_RAQQA           – Northern Euphrates
--       RED_ZONE_HAMA            – Hama area
--
--  4. NAME YOUR INTERCEPT FLIGHTS using the groupPrefix defined in IADS_CFG.SQUADRONS.
--       Each group = one flight (2 aircraft recommended). Late Activate = ON.
--       RED examples (Syria):
--         RED_AIR_DAMASCUS_01 / _02 / _03    → groupPrefix "RED_AIR_DAMASCUS"
--         RED_AIR_ALEPPO_01  / _02 / _03    → groupPrefix "RED_AIR_ALEPPO"
--         RED_AIR_LATAKIA_01 / _02 / _03    → groupPrefix "RED_AIR_LATAKIA"
--         RED_AIR_PALMYRA_01 / _02          → groupPrefix "RED_AIR_PALMYRA"
--         RED_AIR_DEIR_EZ_ZOR_01            → groupPrefix "RED_AIR_DEIR_EZ_ZOR"
--       BLUE examples (Syria):
--         BLUE_AIR_NORTH_01 / _02 / _03 / _04  → groupPrefix "BLUE_AIR_NORTH"
--         BLUE_AIR_HATAY_01 / _02 / _03        → groupPrefix "BLUE_AIR_HATAY"
--         BLUE_AIR_SOUTH_01 / _02 / _03        → groupPrefix "BLUE_AIR_SOUTH"
--
--  5. NAME AWACS AIRCRAFT GROUPS with the AWACS prefix (default RED_AWACS_ / BLUE_AWACS_).
--       AWACS groups get a 420 km detection radius and broadcast picture calls
--       to their coalition every GCI_PICTURE_INTERVAL seconds (default 3 min).
--       They must be alive for picture calls to fire.
--         RED_AWACS_A50_KHMEIMIM     – A-50 Mainstay, orbit over Latakia coast
--         BLUE_AWACS_E3_INCIRLIK     – E-3 Sentry, orbit over southern Turkey
--
--  6. TRIGGER ZONES for BLUE squadrons use the prefix BLUE_ZONE_:
--         BLUE_ZONE_NORTH    – Northern Syria / Turkish border sector
--         BLUE_ZONE_HATAY    – Hatay approach / Iskenderun Gulf
--         BLUE_ZONE_SOUTH    – Southern Lebanon / Israeli airspace buffer
--
--  7. If your MIST version doesn't expose mist.DBs.zonesByName, manually register
--     zones from a DO Script trigger at T+2 seconds:
--       registerRedZone("RED_ZONE_DAMASCUS")
--       registerBlueZone("BLUE_ZONE_NORTH")
--       (etc.)
--
--  8. OPTIONAL TUNING – edit the IADS_CFG table at the top of this file:
--       UPDATE_INTERVAL, ARM_SHUTDOWN_TIME, INTERCEPT_ALTITUDE,
--       GCI_FUEL_RTB_THRESHOLD, GCI_PICTURE_INTERVAL, AWACS_DETECTION_RANGE,
--       USE_DCS_DETECTION, SQUADRONS (add/remove squadrons for either side).
-- =============================================================================
