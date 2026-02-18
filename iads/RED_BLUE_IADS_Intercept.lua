-- =============================================================================
--  RED / BLUE IADS + RED Air Intercept System for DCS World
--  Map     : SYRIA
--  Author  : Mission Designer Script (AI Generated)
--  Requires: MIST (Mission Scripting Tools) loaded BEFORE this script
--
--  Syria Airbase Reference (for placement purposes):
--    RED (SAA/Russian) : Khmeimim, Damascus Intl, Aleppo Intl, T4/Tiyas,
--                        Shayrat, Hama, Tabqa, Deir ez-Zor, Palmyra, Al-Qusayr
--    BLUE (Coalition)  : Incirlik, Hatay, Akrotiri, Ramat David, Haifa,
--                        Kiryat Shmona, Ramon, Ben Gurion, King Hussein
--
--  Syria Sector Zones (suggested RED_ZONE_ names):
--    RED_ZONE_DAMASCUS    RED_ZONE_ALEPPO     RED_ZONE_LATAKIA
--    RED_ZONE_PALMYRA     RED_ZONE_HOMS       RED_ZONE_DEIR_EZ_ZOR
--    RED_ZONE_RAQQA       RED_ZONE_HAMA       RED_ZONE_COASTAL
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
    EWR_DETECTION_RANGE     = 250000,  -- 250 km  – EWR shares contacts within
    SAM_ENGAGE_SHARE_RANGE  = 180000,  -- 180 km  – SAMs share targeting data
    SAM_MIN_ENGAGE_ALT      = 30,      -- metres AGL – ignore very low contacts
    SAM_FIRE_DELAY_MIN      = 2,       -- seconds – random delay before engaging
    SAM_FIRE_DELAY_MAX      = 8,

    -- ── Probability of Kill helpers ──────────────────────────────────────────
    -- Each SAM computes a score; highest scorer engages.
    -- Score = basePk * altFactor * rangeFactor * healthFactor
    PKill_BASE              = 0.75,      -- base Pk for a healthy SAM on boresight

    -- ── ARM / munition defence ──────────────────────────────────────────────
    ARM_SHUTDOWN_TIME       = 45,        -- seconds radar stays silent after ARM detect
    ARM_MOVE_RADIUS         = 800,       -- metres random relocate if unit is mobile
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
    RTB_LOITER_TIME         = 120,    -- seconds after zone clear before RTB order
    ZONE_PREFIX             = "RED_ZONE_",   -- must match ME trigger zone names

    -- ── GCI / Detection settings ─────────────────────────────────────────────
    USE_DCS_DETECTION      = true,    -- true  = coalition.getDetectedTargets() (realistic)
                                      -- false = range-only sphere check (simpler)
    GCI_PICTURE_INTERVAL   = 180,     -- seconds between AWACS picture broadcasts
    GCI_FUEL_RTB_THRESHOLD = 0.20,    -- fuel fraction (0–1) that triggers Bingo RTB
    AWACS_DETECTION_RANGE  = 420000,  -- 420 km detection radius for airborne AWACS nodes
    AWACS_PREFIX_RED       = "RED_AWACS_",
    AWACS_PREFIX_BLUE      = "BLUE_AWACS_",
    AWACS_CALLSIGN = {
        RED  = "OVERLORD",
        BLUE = "MAGIC",
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
            { callsign="FOXBAT",   homeBase="Mezzeh",          zone="RED_ZONE_DAMASCUS",    groupPrefix="RED_AIR_DAMASCUS",    maxFlights=3 },
            { callsign="FULCRUM",  homeBase="Aleppo",          zone="RED_ZONE_ALEPPO",      groupPrefix="RED_AIR_ALEPPO",      maxFlights=3 },
            { callsign="FLANKER",  homeBase="Bassel Al-Assad", zone="RED_ZONE_LATAKIA",     groupPrefix="RED_AIR_LATAKIA",     maxFlights=3 },
            { callsign="FENCER",   homeBase="Tiyas",           zone="RED_ZONE_PALMYRA",     groupPrefix="RED_AIR_PALMYRA",     maxFlights=2 },
            { callsign="FROGFOOT", homeBase="Hama",            zone="RED_ZONE_HOMS",        groupPrefix="RED_AIR_HOMS",        maxFlights=2 },
            { callsign="SOKOL",    homeBase="Deir ez-Zor",     zone="RED_ZONE_DEIR_EZ_ZOR", groupPrefix="RED_AIR_DEIR_EZ_ZOR", maxFlights=2 },
            { callsign="VYMPEL",   homeBase="Tabqa",           zone="RED_ZONE_RAQQA",       groupPrefix="RED_AIR_RAQQA",       maxFlights=2 },
            { callsign="BERKUT",   homeBase="Hama",            zone="RED_ZONE_HAMA",        groupPrefix="RED_AIR_HAMA",        maxFlights=2 },
        },
        BLUE = {
            { callsign="VIPER",    homeBase="Incirlik",         zone="BLUE_ZONE_NORTH",      groupPrefix="BLUE_AIR_NORTH",      maxFlights=4 },
            { callsign="HORNET",   homeBase="Hatay",            zone="BLUE_ZONE_HATAY",      groupPrefix="BLUE_AIR_HATAY",      maxFlights=3 },
            { callsign="EAGLE",    homeBase="Ramat David",      zone="BLUE_ZONE_SOUTH",      groupPrefix="BLUE_AIR_SOUTH",      maxFlights=3 },
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

local function groupAlive(groupName)
    local g = Group.getByName(groupName)
    if not g then return false end
    for _, u in ipairs(g:getUnits()) do
        if u:getLife() > 1 then return true end
    end
    return false
end

local function groupHasAliveUnit(groupName)
    return groupAlive(groupName)
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

local function setGroupOption(group, option, value)
    if group and group:getController() then
        group:getController():setOption(option, value)
    end
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
    RED  = { samNodes = {}, ewrNodes = {}, contacts = {}, suppressedUntil = {} },
    BLUE = { samNodes = {}, ewrNodes = {}, contacts = {}, suppressedUntil = {} },
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

local function buildNodeList(coaName, coaID, samPrefix, ewrPrefix)
    local state = IADS[coaName]
    state.samNodes = {}
    state.ewrNodes = {}

    for _, name in ipairs(getGroupsByPrefix(coaID, samPrefix)) do
        if groupAlive(name) then
            table.insert(state.samNodes, name)
        end
    end

    for _, name in ipairs(getGroupsByPrefix(coaID, ewrPrefix)) do
        if groupAlive(name) then
            table.insert(state.ewrNodes, name)
        end
    end

    log(coaName .. " IADS: " .. #state.samNodes .. " SAM nodes, " .. #state.ewrNodes .. " EWR nodes")
end

-- Gather enemy contacts visible to this coalition.
-- PRIMARY path : coalition.getDetectedTargets() — uses actual DCS radar/sensor model.
-- SECONDARY     : range-sphere fallback (always runs to catch any gaps).
-- AWACS groups (RED_AWACS_ / BLUE_AWACS_) contribute an extended sensor radius.
local function gatherContacts(coaName, enemyCoa)
    local state  = IADS[coaName]
    state.contacts = {}
    local seen   = {}   -- deduplicate by unit name
    local now    = timer.getTime()

    local myCoaID = (coaName == "RED") and coalition.side.RED or coalition.side.BLUE

    -- ── PRIMARY : DCS built-in sensor detections ──────────────────────────────
    if IADS_CFG.USE_DCS_DETECTION then
        local det = coalition.getDetectedTargets(myCoaID, Unit.SensorType.RADAR)
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
    end

    -- ── SECONDARY : range-sphere supplement / fallback ────────────────────────
    -- Build a node list with individual detection ranges.
    -- Ground EWR/SAM nodes use EWR_DETECTION_RANGE.
    -- Airborne AWACS nodes use the (larger) AWACS_DETECTION_RANGE.
    local nodes = {}
    for _, n in ipairs(state.ewrNodes) do
        table.insert(nodes, { name = n, range = IADS_CFG.EWR_DETECTION_RANGE })
    end
    for _, n in ipairs(state.samNodes) do
        table.insert(nodes, { name = n, range = IADS_CFG.EWR_DETECTION_RANGE * 0.6 })
    end
    local awacsPrefix = (coaName == "RED") and (IADS_CFG.AWACS_PREFIX_RED  or "RED_AWACS_")
                                            or  (IADS_CFG.AWACS_PREFIX_BLUE or "BLUE_AWACS_")
    for _, g in ipairs(getAirGroupsByPrefix(myCoaID, awacsPrefix)) do
        table.insert(nodes, { name = g, range = IADS_CFG.AWACS_DETECTION_RANGE or 420000 })
    end

    local enemyGroups = coalition.getGroups(enemyCoa, Group.Category.AIRPLANE)
    local heloGroups  = coalition.getGroups(enemyCoa, Group.Category.HELICOPTER)
    for _, g in ipairs(heloGroups) do table.insert(enemyGroups, g) end

    for _, g in ipairs(enemyGroups) do
        for _, u in ipairs(g:getUnits()) do
            if u:isExist() and u:isActive() and u:getLife() > 1 then
                local p = u:getPoint()
                if p and p.y and p.y > IADS_CFG.SAM_MIN_ENGAGE_ALT then
                    local n = u:getName()
                    if not seen[n] then
                        for _, node in ipairs(nodes) do
                            local np = getGroupPos(node.name)
                            if np and dist3d(np, p) <= node.range then
                                seen[n] = true
                                table.insert(state.contacts, {
                                    unit       = u,
                                    group      = g,
                                    pos        = p,
                                    vel        = u:getVelocity(),
                                    name       = n,
                                    detectedAt = now,
                                    byRadar    = false,
                                })
                                break
                            end
                        end
                    end
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
        local bestSam, bestScore = nil, 0

        for _, samName in ipairs(state.samNodes) do
            -- Check if not suppressed
            local sup = state.suppressedUntil[samName] or 0
            if timer.getTime() >= sup then
                local score = computeEngagementScore(samName, contact)
                if score > bestScore then
                    bestScore = score
                    bestSam   = samName
                end
            end
        end

        if bestSam and bestScore > 0.05 then
            assigned[contact.name] = bestSam
            -- Random launch delay to stagger and confuse jamming
            local delay = IADS_CFG.SAM_FIRE_DELAY_MIN
                        + math.random() * (IADS_CFG.SAM_FIRE_DELAY_MAX - IADS_CFG.SAM_FIRE_DELAY_MIN)

            local cap_contact = contact
            local cap_sam     = bestSam
            timer.scheduleFunction(function()
                if groupAlive(cap_sam) and cap_contact.unit:isActive() and cap_contact.unit:getLife() > 1 then
                    orderSAMEngage(cap_sam, cap_contact)
                end
                return nil
            end, nil, timer.getTime() + delay)

            log(coaName .. " IADS assigned " .. contact.name .. " to " .. bestSam
                .. string.format(" (score=%.2f)", bestScore))
        end
    end

    -- SAMs with no assigned targets should go to standby (radar off) to reduce
    -- exposure to DEAD/SEAD
    for _, samName in ipairs(state.samNodes) do
        local hasTarget = false
        for _, sName in pairs(assigned) do
            if sName == samName then hasTarget = true; break end
        end
        if not hasTarget then
            local sup = state.suppressedUntil[samName] or 0
            if timer.getTime() >= sup then
                local g = Group.getByName(samName)
                if g and g:getController() then
                    g:getController():setOnOff(false)  -- radar standby
                end
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

-- Order SHORAD / AAA near a tracked weapon to engage it
local function alertSHORADtoEngageWeapon(weapon, coaName)
    local state = IADS[coaName]
    local wpPos = weapon:getPoint()
    if not wpPos then return end

    for _, samName in ipairs(state.samNodes) do
        local sp = getGroupPos(samName)
        if sp and dist3d(sp, wpPos) < 15000 then   -- 15 km intercept range
            local g = Group.getByName(samName)
            if g and g:getController() then
                g:getController():setOption(0, 1)   -- ROE = weapons free
                local task = {
                    id = "EngageTargets",
                    params = {
                        targetTypes = {Weapon.GuidanceType.TVM,
                                       Weapon.GuidanceType.INS,
                                       Weapon.GuidanceType.RADAR_ACTIVE},
                        priority = 0,
                    }
                }
                -- Best-effort push; DCS does not guarantee intercepting specific munitions
                pcall(function() g:getController():pushTask(task) end)
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
                log("Tracking " .. (isARM and "ARM" or "AGM") .. ": " .. typeName
                    .. " vs " .. defendCoaName)
            end
        end
    end

    -- ── UNIT DEAD ──────────────────────────────────────────────────────────
    if event.id == world.event.S_EVENT_DEAD or event.id == world.event.S_EVENT_CRASH then
        local unit = event.initiator
        if not unit then return end
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

            if wt.isARM and not wt.alerted then
                -- Find the SAM node most likely targeted and suppress it
                local target, dist = findARMTarget(wpnPos, vel, wt.targetCoa)
                if target and dist < 80000 then   -- within 80 km of trajectory end
                    suppressSAMRadar(wt.targetCoa, target)
                    wt.alerted = true
                end
            end

            if wt.isAGM then
                -- Continuously alert SHORAD to try to intercept
                alertSHORADtoEngageWeapon(wpn, wt.targetCoa)
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

    -- Rebuild node lists (units can be killed between cycles)
    buildNodeList("RED",  coalition.side.RED,  "RED_SAM_",  "RED_EWR_")
    buildNodeList("BLUE", coalition.side.BLUE, "BLUE_SAM_", "BLUE_EWR_")

    -- Gather air contacts for each side
    gatherContacts("RED",  coalition.side.BLUE)
    gatherContacts("BLUE", coalition.side.RED)

    -- Optimise and order engagements
    optimizeEngagements("RED")
    optimizeEngagements("BLUE")

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
    local contacts  = IADS[coalName].contacts
    local awacsCS   = (IADS_CFG.AWACS_CALLSIGN or {})[coalName] or "AWACS"
    local myCoaID   = (coalName == "RED") and coalition.side.RED or coalition.side.BLUE
    local awacsPrefix = (coalName == "RED") and (IADS_CFG.AWACS_PREFIX_RED  or "RED_AWACS_")
                                             or  (IADS_CFG.AWACS_PREFIX_BLUE or "BLUE_AWACS_")

    -- Only broadcast if an AWACS node is alive
    local awacsAlive = false
    for _, gName in ipairs(getAirGroupsByPrefix(myCoaID, awacsPrefix)) do
        if groupAlive(gName) then awacsAlive = true; break end
    end
    if not awacsAlive then return end

    local refPt = gciRefPoint(coalName)

    if #contacts == 0 then
        trigger.action.outTextForCoalition(
            myCoaID,
            "[" .. awacsCS .. "]  PICTURE CLEAR. No enemy contacts.",
            12, false)
        return
    end

    local posStr, _ = contactPicture(contacts, refPt)
    local msg = string.format(
        "[%s]  PICTURE: %d contact(s), %s.",
        awacsCS, #contacts, posStr)
    trigger.action.outTextForCoalition(myCoaID, msg, 16, false)
    env.info("[IADS] " .. coalName .. " " .. msg, false)
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
                    if g == nil or not g:isActive() then
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
    local zd = mist and mist.DBs and mist.DBs.zonesByName and mist.DBs.zonesByName[zoneName]
    if not zd then return threats end
    local zPos    = zd.point
    local zRadius = zd.radius + 80000   -- 80 km threat buffer around the zone
    for _, c in ipairs(IADS[coaName].contacts) do
        if dist2d(c.pos, zPos) <= zRadius then
            table.insert(threats, c)
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

    local g = Group.getByName(groupName)
    if g then
        g:activate()
    else
        local ref = Group.getByName(groupName)
        if ref then trigger.action.activateGroup(ref) end
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

    -- GCI scramble radio call
    local refPt  = gciRefPoint(coalName)
    local posStr = (#threats > 0) and contactPicture(threats, refPt) or "unknown position"
    gciMsg(coalName,
        string.format("%s, SCRAMBLE. Vector %s. %d hostile(s). Cleared to engage.",
            sqd.callsign, posStr, #threats),
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
            local zd  = mist and mist.DBs and mist.DBs.zonesByName and mist.DBs.zonesByName[cap_sqd.zone]
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
    local fuelMin = IADS_CFG.GCI_FUEL_RTB_THRESHOLD or 0.20

    for _, coalName in ipairs({"RED", "BLUE"}) do
        local gciSt = gciState[coalName]
        for gName, fs in pairs(gciSt.flights) do
            if fs.status == "airborne" then
                local grp = Group.getByName(gName)
                if grp then
                    local alive     = false
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

local function init()
    log("=== RED/BLUE IADS + Air Intercept System initialising ===")

    -- Seed random number generator
    math.randomseed(os.time())

    -- Check MIST availability
    if not mist then
        log("WARNING: MIST not loaded. Some features may not work correctly!")
    else
        log("MIST version: " .. (mist.majorVersion or "?") .. "." .. (mist.minorVersion or "?"))
    end

    -- Discover RED_ZONE_ and BLUE_ZONE_ trigger zones via MIST DB
    discoverZones()

    -- Initial IADS node build
    buildNodeList("RED",  coalition.side.RED,  "RED_SAM_",  "RED_EWR_")
    buildNodeList("BLUE", coalition.side.BLUE, "BLUE_SAM_", "BLUE_EWR_")

    -- Schedule main loops
    timer.scheduleFunction(iadsUpdateLoop,       {}, timer.getTime() + 10)
    timer.scheduleFunction(weaponTrackingLoop,    {}, timer.getTime() + 5)
    timer.scheduleFunction(gciInterceptLoop,      {}, timer.getTime() + 15)
    timer.scheduleFunction(flightMaintenanceLoop, {}, timer.getTime() + 30)

    -- Periodic IADS node-list rebuild (drops destroyed SAM/EWR groups).
    -- Runs every NODE_REFRESH_INTERVAL seconds (default 900 = 15 min).
    -- SAM sites are one-and-done: dead groups simply won't appear on the
    -- next rebuild and will be silently pruned from all tracking tables.
    local NODE_REFRESH_INTERVAL = IADS_CFG.NODE_REFRESH_INTERVAL or 900
    local function nodeRefreshLoop(_, time)
        log("[NodeRefresh] Rebuilding IADS node lists...")
        buildNodeList("RED",  coalition.side.RED,  "RED_SAM_",  "RED_EWR_")
        buildNodeList("BLUE", coalition.side.BLUE, "BLUE_SAM_", "BLUE_EWR_")
        local redCount  = 0
        local blueCount = 0
        if IADS_STATE and IADS_STATE.nodes then
            for _ in pairs(IADS_STATE.nodes.RED  or {}) do redCount  = redCount  + 1 end
            for _ in pairs(IADS_STATE.nodes.BLUE or {}) do blueCount = blueCount + 1 end
        end
        log(string.format("[NodeRefresh] Done. RED nodes: %d  BLUE nodes: %d",
            redCount, blueCount))
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
