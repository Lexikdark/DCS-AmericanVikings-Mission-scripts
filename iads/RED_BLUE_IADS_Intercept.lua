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
    UPDATE_INTERVAL         = 20,   -- Main IADS update loop; also drives pruneDeadNodes + gatherContacts for all three sub-IADS
    AIR_INTERCEPT_INTERVAL  = 30,   -- Air-intercept zone check loop; 30 s is reactive enough (~7.5 km at 900 km/h)
    WEAPON_TRACK_INTERVAL   = 5,    -- Incoming weapon tracking loop; ample for ARM/AGM intercept (ARMs fly 20–60 s)
    RTB_CHECK_INTERVAL      = 15,   -- Fuel and leash check for airborne intercept flights
    NODE_REFRESH_INTERVAL   = 900,  -- Full SAM/EWR node-list rebuild (15 min)
                                    -- Dead groups are silently dropped each cycle;
                                    -- no respawn — SAM sites are one-and-done.

    -- ── IADS detection ranges (metres) ─────────────────────────────────────
    SAM_MIN_ENGAGE_ALT      = 20,      -- metres AGL – ignore very low contacts
    SAM_FIRE_DELAY_MIN      = 0,       -- seconds – random delay before engaging (0 = instant)
    SAM_FIRE_DELAY_MAX      = 3,       -- tighter window = faster, more dangerous SAMs
    SAM_MAX_ENGAGE_PER_CONTACT = 2,    -- max SAM nodes assigned to the same contact

    -- ── Per-type SAM missile envelope (metres) ───────────────────────────────
    -- computeEngagementScore() looks up the first launcher unit in a group,
    -- matches its getTypeName() against these patterns (plain string.find),
    -- and hard-gates the score to 0 if outside [min, max].
    -- Groups whose launcher type matches no pattern skip the range gate entirely;
    -- DCS decides at controller level whether the SAM can reach the contact.
    -- Ranges are approximate real-world figures tuned for DCS gameplay balance.
    SAM_RANGE_TABLE = {
        -- ── Long-range SAMs ──────────────────────────────────────────────────────────────
        -- Pattern matches DCS getTypeName() substrings (plain, case-sensitive).
        -- Multiple entries per system cover launcher unit variants and DCS name variants.
        ["S-300PS"]          = { min =  5000, max = 120000 },  -- SA-10 Grumble  (5P85C/5P85D launchers)
        ["S-300V 9A83"]      = { min =  5000, max = 150000 },  -- SA-12 Giant/Gladiator
        ["S-300V 9A85"]      = { min =  5000, max = 150000 },  -- SA-12 Giant/Gladiator (alt launcher)
        ["SA-23"]            = { min =  5000, max = 200000 },  -- S-300VM Antey-2500
        ["S-200"]            = { min = 17000, max = 240000 },  -- SA-5 Gammon (long blind zone)
        ["S_200"]            = { min = 17000, max = 240000 },  -- DCS underscore variant

        -- ── Medium-range SAMs ─────────────────────────────────────────────────────────────
        ["SA-17 Buk M2"]     = { min =  3000, max =  50000 },  -- SA-17 Buk-M2 Grizzly
        ["SA-11 Buk"]        = { min =  3000, max =  32000 },  -- SA-11 Buk Gadfly
        ["Kub 2P25"]         = { min =  4000, max =  24000 },  -- SA-6 Gainful
        ["5p73 s-125"]       = { min =  6000, max =  35000 },  -- SA-3 Neva/Pechora (S-125)
        ["SA-2"]             = { min =  7000, max =  45000 },  -- SA-2 Guideline
        ["S-75"]             = { min =  7000, max =  45000 },  -- SA-2 alt / Volkhov
        ["S_75"]             = { min =  7000, max =  45000 },  -- DCS underscore variant
        ["Hawk ln"]          = { min =  2000, max =  45000 },  -- MIM-23 Hawk (BLUE coalition)
        ["Hawk pcp"]         = { min =  2000, max =  45000 },  -- Hawk PCP / PIP variant
        ["Patriot ln"]       = { min =  3000, max =  70000 },  -- MIM-104 Patriot PAC-2/3 (BLUE)
        ["HQ-7"]             = { min =   500, max =  12000 },  -- FM-80 / Crotale export (Syria)
        ["Rapier"]           = { min =   500, max =   6800 },  -- British Rapier FSA
        ["rapier"]           = { min =   500, max =   6800 },  -- DCS lower-case variant
        ["Crotale"]          = { min =   500, max =   8000 },  -- French Crotale NG
        ["NASAMS_LN"]        = { min =  2500, max =  25000 },  -- NASAMS (AIM-120 based)
        ["NASAMS"]           = { min =  2500, max =  25000 },  -- NASAMS generic match

        -- ── Medium SHORAD ──────────────────────────────────────────────────────────────────
        -- Pantsir-S1 (SA-22 Greyhound) – CRITICAL: very common in Syria missions.
        -- Combined missile (0.2–20 km) + gun (0.2–4 km) envelope — use missile max.
        ["Pantsir-S1"]       = { min =   200, max =  20000 },  -- SA-22 Pantsir-S1
        ["Pantsir_S1"]       = { min =   200, max =  20000 },  -- DCS underscore variant
        ["SA-15 Tor"]        = { min =  1500, max =  12000 },  -- SA-15 Gauntlet (older Tor name)
        ["Tor 9A331"]        = { min =  1500, max =  12000 },  -- Tor-M1 launcher (most common)
        ["Tor-M2"]           = { min =  1500, max =  16000 },  -- Tor-M2 (extended range)
        ["TorM2"]            = { min =  1500, max =  16000 },  -- DCS CHAP_TorM2 variant (no hyphen)
        ["Osa 9A33"]         = { min =  1500, max =  10000 },  -- SA-8 Gecko (all Osa variants)
        ["Osa_9A33"]         = { min =  1500, max =  10000 },  -- underscore form
        ["M48 Chaparral"]    = { min =   500, max =   9000 },  -- M48 Chaparral (BLUE)
        ["Roland ADS"]       = { min =   500, max =   6300 },  -- Roland ADS (BLUE)
        ["Roland Rad"]       = { min =   500, max =   6300 },  -- Roland radar unit type
        ["Linebacker"]       = { min =   200, max =   6000 },  -- M6 Linebacker (Stinger on Bradley)

        -- ── Short-range SHORAD / point defence ────────────────────────────────────────────
        ["2S6 Tunguska"]     = { min =   200, max =   8000 },  -- SA-19 Grison (missile 8 km, gun 4 km)
        ["2S6"]              = { min =   200, max =   8000 },  -- short-form match
        ["Strela-10"]        = { min =   500, max =   5000 },  -- SA-13 Gopher
        ["Strela_10"]        = { min =   500, max =   5000 },
        ["Strela-1 9P31"]    = { min =   500, max =   4200 },  -- SA-9 Gaskin
        ["Strela_1"]         = { min =   500, max =   4200 },
        ["M1097 Avenger"]    = { min =   500, max =   5500 },  -- Avenger (Stinger on HMMWV)
        ["Avenger"]          = { min =   500, max =   5500 },  -- generic Avenger match

        -- ── Anti-aircraft artillery (guns) ────────────────────────────────────────────────
        ["ZSU-23-4 Shilka"]  = { min =   100, max =   2500 },  -- ZSU-23-4 (cannon)
        ["ZSU-23-4"]         = { min =   100, max =   2500 },  -- short-form match
        ["ZSU_57_2"]         = { min =   200, max =   4000 },  -- ZSU-57-2 (57 mm, longer range)
        ["ZSU-57-2"]         = { min =   200, max =   4000 },
        ["Gepard"]           = { min =   100, max =   3500 },  -- Gepard SPAAG (BLUE)
        ["M163"]             = { min =   100, max =   1800 },  -- M163 VADS (BLUE)
        ["ZU-23-2"]          = { min =   100, max =   2500 },  -- ZU-23-2 towed or emplaced
        ["ZU-23"]            = { min =   100, max =   2500 },  -- ZU-23 / ZU-23-2 generic
        ["S-60"]             = { min =   200, max =   4000 },  -- S-60 57mm towed AAA
        ["AAA_SON_9"]        = { min =   200, max =   4000 },  -- SON-9 fire control (S-60 battery)
        ["KS-19"]            = { min =   500, max =   6000 },  -- KS-19 100mm heavy AAA

        -- ── IRIS-T family (BLUE, added DCS 2.9+) ──────────────────────────────────────────
        -- Actual DCS type names: CHAP_IRISTSLM_CP, CHAP_IRISTSLM_STR, CHAP_IRISTSLM_LN
        ["IRISTSLM"]         = { min =  1000, max =  40000 },  -- IRIS-T SLM (medium-range, 1–40 km)
        ["IRISTSLS"]         = { min =   500, max =  12000 },  -- IRIS-T SLS (short-range, 0.5–12 km)
    },

    -- ── Low-altitude jet immunity (RED SAMs, excludes SHORAD) ──────────
    -- Fixed-wing aircraft (jets) flying below this AGL threshold are ignored
    -- by long-range RED SAMs, simulating radar ground-clutter masking at
    -- terrain-hugging altitudes.  SHORAD groups (name contains "SHORAD")
    -- are EXEMPT — they will still engage low-flying jets.  Helicopters are
    -- also unaffected.  Set to 0 to disable.
    -- Only affects RED and LEBANON IADS networks.
    SAM_LOW_JET_IMMUNITY_AGL = 75,    -- metres AGL – jets below this are invisible to non-SHORAD RED SAMs

    -- ── Probability of Kill helpers ──────────────────────────────────────────
    -- Each SAM computes a score; highest scorer engages.
    -- Score = basePk * altFactor * rangeFactor * healthFactor
    PKill_BASE              = 0.92,      -- base Pk for a healthy SAM on boresight (raised for lethality)
    SAM_MIN_ENGAGE_SCORE    = 0.30,      -- minimum Pk score required before a SAM will fire
                                         --   0.05 = fire at almost anything (old default)
                                         --   0.25 = fire on any reasonable solution
                                         --   0.30 = skip low-quality edge shots, still fires early (current — compensates for 20s UPDATE_INTERVAL)
                                         --   0.35 = solid engagement solution required
                                         --   0.50 = disciplined — holds fire until near-optimal
                                         --   0.60+= very conservative, only ideal geometry

    -- ── ARM / munition defence ──────────────────────────────────────────────
    ARM_SHUTDOWN_TIME             = 45,    -- seconds radar stays silent after ARM detect
    ARM_MOVE_RADIUS               = 800,   -- metres random relocate if unit is mobile
    ARM_SUPPRESS_TRIGGER_DIST     = 150000, -- metres – arm suppression triggers when ARM’s projected impact point is within this distance of a SAM node
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
    RTB_LOITER_TIME         = 0,      -- 0 = RTB immediately the moment the zone goes clear (no loiter)
    SCRAMBLE_THREAT_BUFFER  = 0,      -- 0 = scramble only when threat is inside the zone boundary (no approach buffer)
    INTERCEPT_LEASH_BUFFER  = 80000,  -- metres beyond zone radius — if an airborne intercept flight strays
                                      -- farther than (zone_radius + this value) from its zone centre it is
                                      -- immediately recalled, regardless of RTB_LOITER_TIME
    ZONE_PREFIX             = "RED_ZONE_",   -- must match ME trigger zone names

    -- ── GCI / Detection settings ─────────────────────────────────────────────
    -- Detection uses coalition.getDetectedTargets() exclusively (DCS sensor model).
    -- Terrain masking, LOS, jamming, and unit radar ranges all apply natively.
    GCI_FUEL_RTB_THRESHOLD = 0.20,    -- fuel fraction (0–1) that triggers Bingo RTB
    AWACS_PREFIX_RED       = "RED_AWACS_",
    AWACS_PREFIX_BLUE      = "BLUE_AWACS_",
    AWACS_ORBIT_ALT_FT     = 30000,   -- ft  – orbit altitude enforced by the AWACS keeper loop
    AWACS_ORBIT_KTS        = 350,     -- kts – airspeed enforced by the AWACS keeper loop

    -- ── Contact exclusion list ────────────────────────────────────────────────
    -- Units whose name starts with any of these prefixes are silently excluded
    -- during contact gathering, regardless of detection method (radar or fallback).
    -- Use this for units marked invisible in the ME that DCS still surfaces via
    -- coalition.getDetectedTargets (e.g. AWACS, FAC, tankers).
    CONTACT_IGNORE_PREFIXES = {
        "BLUE_AWACS_",   -- BLUE AWACS flights (invisible in ME)
        "RED_AWACS_",    -- RED AWACS flights  (invisible in ME)
        "BLUE_TANKER_",   -- BLUE tanker flights (invisible in ME)
    },

    -- ── Immortal IADS networks ────────────────────────────────────────────────
    -- Network names listed here will NEVER have their radar suppressed or shut
    -- down in response to any weapon (ARM or AGM).  Use this for networks whose
    -- units are set as immortal in the Mission Editor and therefore do not need
    -- to react to incoming fire at all.
    IMMORTAL_IADS_NETWORKS = {
        ["LEBANON"] = true,   -- RED_SAM_LEBANON_ groups are immortal in the ME
    },

    -- ── Lebanon sub-IADS engagement boundary ─────────────────────────────────
    -- Lebanon SAMs will ONLY engage contacts whose position falls inside
    -- one of these trigger zones.
    -- Zone names must match exactly what you set in the ME.
    LEBANON_ZONES = {
        "LEBANON_ZONE_NORTH",
        "LEBANON_ZONE_MIDDLE",
        "LEBANON_ZONE_SOUTH",
    },
    -- ── Squadron / CAP flight definitions (both coalitions) ──────────────────
    --  groupPrefix : groups in ME named <groupPrefix>_01, _02, _03 …
    --  homeBase    : Airbase.getByName() string – used for RTB routing
    --  zone        : Trigger zone this squadron is assigned to defend
    --  maxFlights  : Max simultaneous airborne flights for this squadron
    --  callsign    : GCI radio callsign used in player-facing messages
    SQUADRONS = {
        RED = {
            { callsign="FOXBAT",   homeBase="Mezzeh",          zone="RED_ZONE_MEZZEH",          groupPrefix="RED_AIR_MEZZEH",           maxFlights=2 },
            { callsign="FULCRUM",  homeBase="Damascus",        zone="RED_ZONE_DAMASCUS",        groupPrefix="RED_AIR_DAMASCUS",         maxFlights=2 },
            { callsign="FENCER",   homeBase="Marj Ruhayyil",   zone="RED_ZONE_MARJ_RUHAYYIL",   groupPrefix="RED_AIR_MARJ_RUHAYYIL",    maxFlights=2 },
            { callsign="SHAHIN",   homeBase="Khalkhalah",      zone="RED_ZONE_KHALKHALAH",      groupPrefix="RED_AIR_KHALKHALAH",       maxFlights=2 },
            { callsign="NEMER",    homeBase="Sayqal",          zone="RED_ZONE_AT_TANF",         groupPrefix="RED_AIR_SAYQAL",           maxFlights=2 },
            { callsign="SOKOL",    homeBase="Sayqal",          zone="RED_ZONE_SAYQAL",          groupPrefix="RED_AIR_SAYQAL",           maxFlights=2 },
            { callsign="FLANKER",  homeBase="Tha'lah",         zone="RED_ZONE_THALAH",          groupPrefix="RED_AIR_THALAH",           maxFlights=2 },
            { callsign="VYMPEL",   homeBase="Palmyra",         zone="RED_ZONE_PALMYRA",         groupPrefix="RED_AIR_PALMYRA",          maxFlights=2 },
            { callsign="BUKET",    homeBase="Deir ez-Zor",     zone="RED_ZONE_DEIR_EZ-ZOR",     groupPrefix="RED_AIR_DEIR_EZ_ZOR",      maxFlights=2 },
            { callsign="FROGFOOT", homeBase="Shayrat",         zone="RED_ZONE_TABQA",           groupPrefix="RED_AIR_SHAYRAT",          maxFlights=2 },
            { callsign="GRACH",    homeBase="Tabqa",           zone="RED_ZONE_TABQA",           groupPrefix="RED_AIR_TABQA",            maxFlights=2 },
            { callsign="BERKUT",   homeBase="Hama",            zone="RED_ZONE_HAMA",            groupPrefix="RED_AIR_HAMA",             maxFlights=2 },
            { callsign="ALKU",     homeBase="Aleppo",          zone="RED_ZONE_ALEPPO",          groupPrefix="RED_AIR_ALEPPO",           maxFlights=2 },
            { callsign="NASR",     homeBase="Al Qusayr",       zone="RED_ZONE_AL_QUSAYR",       groupPrefix="RED_AIR_AL_QUSAYR",        maxFlights=2 },
            { callsign="KOBRA",    homeBase="Bassel Al-Assad", zone="RED_ZONE_BASSEL_AL-ASSAD", groupPrefix="RED_AIR_BASSEL_AL-ASSAD",  maxFlights=2 },
            { callsign="Faggot",   homeBase="An Nasiriyah",    zone="RED_ZONE_AN_NASIRIYAH",    groupPrefix="RED_AIR_AN_NASIRIYAH",     maxFlights=2 },
        },
        BLUE = {
            -- ── Northern Israel – Syria north / NE approach ──────────────────
            { callsign="HORNET",  homeBase="Ramat David",   zone="BLUE_ZONE_RAMAT_DAVID",  groupPrefix="BLUE_AIR_RAMAT_DAVID",  maxFlights=2 },
            -- ── Central / NW Israel ───────────────────────────────────────────
            { callsign="FALCON",  homeBase="Megiddo",       zone="BLUE_ZONE_NorthWest",    groupPrefix="BLUE_AIR_MEGIDDO",      maxFlights=2 },
            -- ── Southern Israel – Jordan / Iraqi border ───────────────────────
            { callsign="SPARTAN", homeBase="Prince Hassan", zone="BLUE_ZONE_PrinceHassan", groupPrefix="BLUE_AIR_PrinceHassan", maxFlights=2 },
            { callsign="LANCER",  homeBase="H4",            zone="BLUE_ZONE_H4",           groupPrefix="BLUE_AIR_H4",           maxFlights=2 },
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

-- True altitude above ground level (terrain-aware)
-- land.getHeight requires a Vec2 table {x, y} where y = DCS world Z axis.
local function getAGL(pos)
    if not (pos and pos.x and pos.z) then return 0 end
    local terrainAlt = land.getHeight({x = pos.x, y = pos.z})
    return pos.y - (terrainAlt or 0)
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

-- Cache: groupName → { min, max } metres from SAM_RANGE_TABLE lookup, or false
-- when the type was checked but matched no pattern.  Populated lazily; stable
-- for the session because SAM type never changes even if units die.
local _samRangeCache = {}

-- Walk the live units in a SAM group, find the first whose getTypeName() matches
-- a SAM_RANGE_TABLE pattern, and return { min, max }.  Returns nil when no pattern
-- matches; computeEngagementScore skips range gates and lets DCS decide instead.
local function getSAMRange(groupName)
    local cached = _samRangeCache[groupName]
    if cached ~= nil then
        return (cached ~= false) and cached or nil  -- false = "checked, no match"
    end
    local g = Group.getByName(groupName)
    if g then
        for _, u in ipairs(g:getUnits()) do
            if u:isExist() then
                local typeName = u:getTypeName() or ""
                for pattern, rng in pairs(IADS_CFG.SAM_RANGE_TABLE) do
                    if string.find(typeName, pattern, 1, true) then
                        _samRangeCache[groupName] = rng
                        return rng
                    end
                end
            end
        end
    end
    -- No match – log every unit type we saw so the mission designer can add
    -- the correct pattern to SAM_RANGE_TABLE.  Only logged once per group.
    local typeList = {}
    if g then
        for _, u in ipairs(g:getUnits()) do
            if u:isExist() then
                typeList[#typeList + 1] = (u:getTypeName() or "<nil>")
            end
        end
    end
    log("getSAMRange: no SAM_RANGE_TABLE match for group '" .. groupName
        .. "' – unit types: " .. (next(typeList) and table.concat(typeList, ", ") or "<none alive>"))
    _samRangeCache[groupName] = false  -- sentinel: checked, no SAM_RANGE_TABLE match
    return nil
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION 3 – IADS STATE TABLES
-- ─────────────────────────────────────────────────────────────────────────────

local IADS = {
    RED     = { samNodes = {}, ewrNodes = {}, contacts = {}, suppressedUntil = {}, lastEngagement = {}, radarOn = {} },
    BLUE    = { samNodes = {}, ewrNodes = {}, contacts = {}, suppressedUntil = {}, lastEngagement = {}, radarOn = {} },
    -- Lebanon SAMs run as a completely isolated RED-side sub-IADS.
    -- They detect and engage BLUE aircraft independently; they do NOT
    -- share contacts or engagement assignments with the main RED network.
    LEBANON = { samNodes = {}, ewrNodes = {}, contacts = {}, suppressedUntil = {}, lastEngagement = {}, radarOn = {} },
}

-- Tracked incoming weapons  { weapon_obj, launchPos, coalition_target }
local trackedWeapons = {}

-- GCI / intercept state — both coalitions
local gciState = {
    RED  = { flights = {}, zones = {} },
    BLUE = { flights = {}, zones = {} },
}

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION 4 – EWR / CONTACT SHARING
-- ─────────────────────────────────────────────────────────────────────────────

-- Lightweight prune: remove destroyed groups from existing node lists.
-- Called every UPDATE_INTERVAL tick to keep lists current without a full
-- coalition.getGroups() rebuild (that rebuild runs on nodeRefreshLoop).
local function pruneDeadNodes(coaName)
    local state = IADS[coaName]
    local alive = {}
    for _, name in ipairs(state.samNodes) do
        if groupAlive(name) then alive[#alive + 1] = name end
    end
    state.samNodes = alive
    alive = {}
    for _, name in ipairs(state.ewrNodes) do
        if groupAlive(name) then alive[#alive + 1] = name end
    end
    state.ewrNodes = alive

    -- Flush suppressedUntil entries whose timer has expired or whose SAM no longer
    -- exists.  Without this the table accumulates one entry per ARM shot forever.
    local now      = timer.getTime()
    local aliveSet = {}
    for _, name in ipairs(state.samNodes) do aliveSet[name] = true end
    for samName, expiry in pairs(state.suppressedUntil) do
        if not aliveSet[samName] or expiry < now then
            state.suppressedUntil[samName] = nil
        end
    end
end

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
-- PRIMARY:  coalition.getDetectedTargets (radar-filtered, terrain-masked) – available in newer DCS builds.
-- FALLBACK: coalition.getGroups scan (all airborne enemy aircraft/helicopters) – used when the
--           primary API is absent from the DCS version. SAM engagement-range checks already in
--           optimizeEngagements() provide de-facto coverage limitation in the fallback path.
local _gatherContactsFallbackLoggedOnce = false
local function gatherContacts(coaName, enemyCoa)
    local state  = IADS[coaName]
    state.contacts = {}
    local seen   = {}   -- deduplicate by unit name
    local now    = timer.getTime()

    -- LEBANON is a RED-coalition sub-IADS; resolve coalition ID accordingly.
    local myCoaID = (coaName == "BLUE") and coalition.side.BLUE or coalition.side.RED

    -- ── Helper: add a unit to the contacts list (shared by both paths) ───────
    local function addUnit(obj, byRadar)
        if not (obj and obj:isExist()) then return end
        if not (obj.getCoalition and obj:getCoalition() == enemyCoa) then return end
        if not (obj.getLife     and obj:getLife() > 1)               then return end
        if not obj.getPoint                                           then return end
        local p = obj:getPoint()
        if not (p and p.y and p.y > IADS_CFG.SAM_MIN_ENGAGE_ALT)    then return end

        -- Reject units whose name matches a configured exclusion prefix.
        -- This handles invisible AWACS / FAC units that DCS still returns from
        -- coalition.getDetectedTargets when using the all-sensor (nil) path.
        local n = obj:getName()
        if IADS_CFG.CONTACT_IGNORE_PREFIXES then
            for _, pfx in ipairs(IADS_CFG.CONTACT_IGNORE_PREFIXES) do
                if string.sub(n, 1, #pfx) == pfx then return end
            end
        end

        local isLowJet = false
        if (coaName == "RED" or coaName == "LEBANON")
           and IADS_CFG.SAM_LOW_JET_IMMUNITY_AGL > 0 then
            local desc = obj:getDesc()
            if desc and desc.category == Unit.Category.AIRPLANE then
                local agl = getAGL(p)
                if agl < IADS_CFG.SAM_LOW_JET_IMMUNITY_AGL then
                    isLowJet = true
                end
            end
        end

        if not seen[n] then
            seen[n] = true
            table.insert(state.contacts, {
                unit       = obj,
                group      = obj.getGroup and obj:getGroup() or nil,
                pos        = p,
                vel        = obj.getVelocity and obj:getVelocity() or {x=0,y=0,z=0},
                name       = n,
                detectedAt = now,
                byRadar    = byRadar,
                isLowJet   = isLowJet,
            })
        end
    end

    -- ── PRIMARY PATH: coalition.getDetectedTargets (radar-realistic) ────────
    if type(coalition.getDetectedTargets) == "function" then
        -- Unit.SensorType.RADAR is integer 0 in some DCS builds; nil = all-sensor fallback.
        local radarSensorType = (Unit.SensorType ~= nil) and Unit.SensorType.RADAR or nil
        local det = coalition.getDetectedTargets(myCoaID, radarSensorType)
        for _, d in ipairs(det or {}) do
            addUnit(d.object, true)
        end
        return state.contacts
    end

    -- ── FALLBACK PATH: coalition.getGroups scan ──────────────────────────────
    -- coalition.getDetectedTargets is not available in this DCS version.
    -- Scan all live enemy aircraft and helicopter groups instead.
    -- SAM engagement ranges in optimizeEngagements() still act as coverage limits.
    if not _gatherContactsFallbackLoggedOnce then
        _gatherContactsFallbackLoggedOnce = true
        log("INFO: coalition.getDetectedTargets unavailable – using coalition.getGroups "
            .. "fallback for contact detection. SAMs and GCI will still function normally.")
    end

    for _, cat in ipairs({ Group.Category.AIRPLANE, Group.Category.HELICOPTER }) do
        local groups = coalition.getGroups(enemyCoa, cat) or {}
        for _, grp in ipairs(groups) do
            if grp and grp:isExist() then
                for _, unit in ipairs(grp:getUnits() or {}) do
                    if unit and unit:isExist() then
                        -- Late-activate groups have exactly zero velocity; airborne aircraft do not.
                        -- Require >30 m/s (~60 kts) ground speed so parked, taxiing, and
                        -- late-activate (frozen) aircraft are all excluded, regardless of elevation.
                        local vel = unit:getVelocity()
                        if vel then
                            local spd2 = vel.x*vel.x + vel.y*vel.y + vel.z*vel.z
                            if spd2 > 900 then  -- 30 m/s squared
                                addUnit(unit, false)
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
-- samEntry: pre-built cache entry { pos, health, rng } from optimizeEngagements().
-- Accepts pre-computed data instead of calling Group.getByName()/getUnits() itself,
-- dropping per-tick DCS API calls from O(contacts × SAMs × maxAssign) to O(SAMs).
local function computeEngagementScore(samEntry, contact)
    local d = dist3d(samEntry.pos, contact.pos)

    -- Altitude factor: prefer targets 500 m – 12000 m AGL
    local alt = contact.pos.y
    local altFactor = 1.0
    if alt < 500 then
        altFactor = alt / 500
    elseif alt > 12000 then
        altFactor = 1 - ((alt - 12000) / 8000)
    end
    altFactor = math.max(0.1, math.min(1.0, altFactor))

    -- Hard range gates only apply when the SAM type is in SAM_RANGE_TABLE.
    -- Unrecognised types skip the gate; the EngageUnit task is issued and DCS
    -- decides whether the SAM can actually reach the contact.
    if samEntry.rng then
        local minR = samEntry.rng.min
        local maxR = samEntry.rng.max
        if d > maxR then return 0 end   -- beyond maximum missile range
        if d < minR then return 0 end   -- inside minimum engagement range (blind zone)

        -- Range factor: score peaks at 60% through the engagement envelope.
        local envelope    = math.max(1, maxR - minR)
        local relD        = (d - minR) / envelope       -- 0.0 at min, 1.0 at max
        local rangeFactor = 1 - math.abs(relD - 0.6)   -- peaks at 60% of envelope
        rangeFactor = math.max(0.05, rangeFactor)

        return IADS_CFG.PKill_BASE * rangeFactor * altFactor * samEntry.health
    end

    -- Unknown type: flat mid-weight score; DCS provides the hard range gate.
    return IADS_CFG.PKill_BASE * 0.5 * altFactor * samEntry.health
end

-- Order a SAM to engage a specific contact through its controller
local function orderSAMEngage(samName, contact)
    local g = Group.getByName(samName)
    if not g then return end
    local ctrl = g:getController()
    if not ctrl then return end

    -- Turn radar ON
    ctrl:setOnOff(true)

    -- Set attack task – replaces any existing task (setTask, not pushTask, to avoid
    -- stacking thousands of EngageUnit entries in the controller queue over time)
    local task = {
        id = "ComboTask",
        params = { tasks = { {
            id = "EngageUnit",
            params = {
                unitId     = contact.unit:getID(),
                weaponType = 268402688,  -- auto-select
                expend     = "Auto",
            },
        } } },
    }
    ctrl:setTask(task)
    log("SAM " .. samName .. " engaging " .. contact.name)
end

-- Distribute contacts across SAM nodes for optimal network coverage
local function optimizeEngagements(coaName)
    local state = IADS[coaName]
    local now   = timer.getTime()

    -- Pre-build a position + health + range cache for every live SAM node.
    -- Without this, computeEngagementScore called Group.getByName() + getUnits()
    -- for every entry in the contacts × samNodes × maxAssign matrix each tick.
    -- Example: 10 contacts × 67 SAMs × 2 = 1,340 DCS API calls per 10 s tick.
    -- With this cache it is one flat pass of 67 calls, then only cheap table lookups.
    local samCache = {}
    for _, sn in ipairs(state.samNodes) do
        local sp = getGroupPos(sn)
        if sp then
            local sg = Group.getByName(sn)
            local hf = 0
            if sg then
                local total, alive = 0, 0
                for _, u in ipairs(sg:getUnits()) do
                    total = total + 1
                    if u:getLife() > 1 then alive = alive + 1 end
                end
                hf = (total > 0) and (alive / total) or 0
            end
            samCache[sn] = { pos = sp, health = hf, rng = getSAMRange(sn) }
        end
    end

    -- assigned{} is built below; if contacts is empty it stays {}, and the
    -- radar-management pass at the bottom will shut down any SAMs still flagged on.
    local assigned = {}  -- contactName → samName

    for _, contact in ipairs(state.contacts) do
        -- Lebanon sub-IADS: only engage contacts inside defined Lebanon zones.
        -- RED and BLUE: no zone gating — computeEngagementScore range gates (via
        -- SAM_RANGE_TABLE) and SAM_MIN_ENGAGE_SCORE act as quality gates, so zone
        -- membership is redundant and was preventing valid engagements.
        local inLebanonBounds = (coaName ~= "LEBANON")
            or pointInAnyZone(contact.pos, IADS_CFG.LEBANON_ZONES)

        if inLebanonBounds then
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
                        -- Low-jet immunity: non-SHORAD SAMs skip low-flying jets.
                        -- SHORAD groups (name contains "SHORAD") always engage.
                        if contact.isLowJet and not string.find(samName, "SHORAD") then
                            -- This SAM is not SHORAD — skip the low-flying jet
                        else
                            local sup = state.suppressedUntil[samName] or 0
                            if now >= sup then
                                local entry = samCache[samName]
                                local score = entry and computeEngagementScore(entry, contact) or 0
                                if score > bestScore2 then
                                    bestScore2 = score
                                    bestSam2   = samName
                                end
                            end
                        end -- low-jet SHORAD check
                    end
                end

                if bestSam2 and bestScore2 > (IADS_CFG.SAM_MIN_ENGAGE_SCORE or 0.05) then
                    usedSAMs[bestSam2] = true
                    assigned_count = assigned_count + 1
                    assigned[contact.name] = bestSam2  -- last writer wins for radar-mgmt reverse map

                    local stagger = (assigned_count - 1) * 1.5  -- 0s for primary, 1.5s for secondary
                    local delay   = stagger
                                  + IADS_CFG.SAM_FIRE_DELAY_MIN
                                  + math.random() * (IADS_CFG.SAM_FIRE_DELAY_MAX - IADS_CFG.SAM_FIRE_DELAY_MIN)

                    -- Only issue a new engage order if the target actually changed.
                    -- This prevents re-issuing setTask every 10 s when the same SAM
                    -- is already tracking the same unit, which would interrupt the
                    -- in-progress engagement and cause the task queue to reset.
                    local alreadyEngaging = (state.lastEngagement[bestSam2] == contact.name)

                    if not alreadyEngaging then
                        state.lastEngagement[bestSam2] = contact.name
                        -- Mark radar on immediately so the radar-management pass below
                        -- does not redundantly call setOnOff(false) on this SAM.
                        state.radarOn[bestSam2] = true

                        local cap_contact = contact
                        local cap_sam     = bestSam2
                        timer.scheduleFunction(function()
                            if groupAlive(cap_sam)
                            and cap_contact.unit:isExist()
                            and cap_contact.unit:isActive()
                            and cap_contact.unit:getLife() > 1 then
                                orderSAMEngage(cap_sam, cap_contact)
                            else
                                -- Target gone before the delayed order fired; clear cached assignment
                                -- so the next tick will issue a fresh order for the new target.
                                state.lastEngagement[cap_sam] = nil
                            end
                            return nil
                        end, nil, timer.getTime() + delay)

                        log(coaName .. " IADS assigned " .. contact.name .. " to " .. bestSam2
                            .. string.format(" [#%d, score=%.2f, delay=%.1fs]", assigned_count, bestScore2, delay))
                    else
                        -- Same target as last tick — DCS AI is already engaging, no API call needed.
                        state.radarOn[bestSam2] = true  -- keep radar state flagged as on
                    end
                else
                    break  -- no more viable SAMs for this contact
                end
            end
        end  -- inLebanonBounds
    end

    -- Radar management: turn radar OFF for any SAM without an active assignment.
    -- Only call setOnOff/setOption when the state actually needs to change — avoids
    -- issuing ~279 redundant DCS API calls per 10-second tick across 93 SAM nodes.
    for _, samName in ipairs(state.samNodes) do
        local sup = state.suppressedUntil[samName] or 0
        if now >= sup then
            local hasAssigned = false
            for _, sName in pairs(assigned) do
                if sName == samName then hasAssigned = true; break end
            end
            if not hasAssigned then
                -- Only write to DCS if radar was previously on (or unknown)
                if state.radarOn[samName] ~= false then
                    local g = Group.getByName(samName)
                    if g and g:getController() then
                        g:getController():setOnOff(false)
                        g:getController():setOption(9, 1)  -- alarm state: green
                        g:getController():setOption(0, 4)  -- ROE: return fire only
                    end
                    state.radarOn[samName]      = false
                    state.lastEngagement[samName] = nil  -- clear so new contact gets a fresh order
                end
                -- hasAssigned=false, radarOn already false → nothing to do
            end
            -- hasAssigned=true case: radar already turned on by orderSAMEngage
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
    -- Immortal networks never need to suppress radar – skip entirely.
    if IADS_CFG.IMMORTAL_IADS_NETWORKS and IADS_CFG.IMMORTAL_IADS_NETWORKS[coaName] then
        return
    end

    local g = Group.getByName(samName)
    if not g then return end
    local ctrl = g:getController()
    if ctrl then
        ctrl:setOnOff(false)  -- kill radar
        log(coaName .. " SAM " .. samName .. " radar SUPPRESSED (ARM inbound)")
    end

    -- Sync state cache so the radar-management pass doesn't waste API calls
    -- trying to turn off a radar that is already off.
    IADS[coaName].radarOn[samName]      = false
    IADS[coaName].lastEngagement[samName] = nil  -- force fresh order after suppression window ends

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
    local _ok, _err = pcall(function()

    -- ── WEAPON SHOT ────────────────────────────────────────────────────────
    if event.id == world.event.S_EVENT_SHOT then
        local wpn = event.weapon
        if not wpn then return end

        local typeName = wpn:getTypeName() or ""

        -- Early bail: cannon rounds and rockets fire S_EVENT_SHOT hundreds of times per
        -- second in combat but can never be ARMs or AGMs. Skip the table-scan loops.
        local _wpnDesc = wpn:getDesc()
        if not _wpnDesc or _wpnDesc.category ~= Weapon.Category.MISSILE then return end

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
    end) -- close pcall
    if not _ok then env.warning("[IADS] onEvent error: " .. tostring(_err)) end
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

        -- Check if weapon still alive (getPoint returns nil when spent).
        -- Also drop entries older than 300 s: a small number of mod weapons or
        -- DCS edge-cases (hot-reload, abort) never return nil, so without a TTL
        -- those entries would live forever and accumulate on long SEAD sorties.
        local ok, wpnPos = pcall(function() return wpn:getPoint() end)
        if not ok or not wpnPos or (now - wt.launchTime > 300) then
            -- Weapon has hit / expired / TTL exceeded – drop entry
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

    -- Prune dead SAM/EWR groups (lightweight – no coalition.getGroups calls).
    -- Full node-list rebuild runs on nodeRefreshLoop every 15 min.
    pruneDeadNodes("RED")
    pruneDeadNodes("BLUE")
    pruneDeadNodes("LEBANON")

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
--  SECTION 11 – AWACS ORBIT KEEPER
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
    return timer.getTime() + 300  -- AWACS orbit correction: every 5 min is sufficient
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION 12 – SQUADRON HELPERS
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
                    if g then
                        local isActiveNow = false
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
                        if not isActiveNow then
                            table.insert(available, gName)
                        end
                    else
                        -- Group.getByName returned nil — group was destroyed in-mission.
                        -- Permanently mark dead so it is never selected for dispatch again.
                        if not gciSt.flights[gName] then
                            gciSt.flights[gName] = {}
                        end
                        gciSt.flights[gName].status = "dead"
                        log("[GCI] " .. gName .. " not found (destroyed) — marked dead, skipping.")
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
-- cachedGroups (optional): pre-fetched enemy airplane list to avoid redundant API calls.
local _missingZonesLogged = {}   -- deduplicate; log each missing zone name only once
local function getThreatsForZone(zoneName, coaName, cachedGroups)
    local threats = {}
    local zd = trigger.misc.getZone(zoneName)
    if not zd then
        -- Zone name mismatch – log once per missing zone name to avoid log spam
        if not _missingZonesLogged[zoneName] then
            _missingZonesLogged[zoneName] = true
            log("[GCI] getThreatsForZone: zone '" .. zoneName .. "' not found – check exact ME name (this will only be logged once)")
        end
        return threats
    end
    local zPos    = zd.point
    local zRadius = zd.radius   -- no buffer; threat must be inside the zone boundary

    -- Use a direct aircraft position scan rather than radar contacts.
    -- This means the GCI will scramble even if the enemy is below radar coverage,
    -- in a notch, or otherwise undetected.
    local groups = cachedGroups
    if not groups then
        local enemyCoa = (coaName == "RED") and coalition.side.BLUE or coalition.side.RED
        groups = coalition.getGroups(enemyCoa, Group.Category.AIRPLANE) or {}
    end
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
--  SECTION 13 – SCRAMBLE & RTB
-- ─────────────────────────────────────────────────────────────────────────────

-- Activate a late-activate group, broadcast GCI scramble call, assign intercept task.
local function dispatchFlight(groupName, coalName, sqd, threats, gciSt)
    log("Dispatching " .. coalName .. " flight: " .. groupName)

    -- trigger.action.activateGroup is the correct DCS API for late-activate groups
    local g = Group.getByName(groupName)
    if g then
        trigger.action.activateGroup(g)
    else
        -- Group.getByName() returned nil — group was killed before it could be dispatched.
        -- Silently mark dead and abort; getAvailableFlights will exclude it next cycle.
        log("[GCI] Dispatch skipped: '" .. groupName .. "' no longer exists (killed). Marked dead.")
        if not gciSt.flights[groupName] then
            gciSt.flights[groupName] = {}
        end
        gciSt.flights[groupName].status = "dead"
        return
    end

    gciSt.flights[groupName] = {
        status     = "airborne",
        zone       = sqd.zone,
        homeBase   = sqd.homeBase,
        callsign   = sqd.callsign,
        coalName   = coalName,
        launchTime = timer.getTime(),
    }

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

    -- Allow time for landing, rearm and refuel (~10 min), then destroy and
    -- set standby so the next numbered group becomes the available slot.
    local gn_cap = groupName
    timer.scheduleFunction(function()
        local fs = gciSt.flights[gn_cap]
        if fs and fs.status == "rtb" then
            local gg = Group.getByName(gn_cap)
            if gg then gg:destroy() end
            fs.status = "standby"
            log(gn_cap .. " rearmed/refuelled – de-activated, slot available")
        end
        return nil
    end, nil, timer.getTime() + 600)
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION 14 – MAIN GCI / INTERCEPT LOOP  (both sides)
-- ─────────────────────────────────────────────────────────────────────────────

local function gciInterceptLoop()
    local now      = timer.getTime()
    local squadrons = IADS_CFG.SQUADRONS or { RED = {}, BLUE = {} }

    -- Cache enemy airplane groups once per coalition (avoids 21 redundant API calls)
    local cachedEnemyAir = {
        RED  = coalition.getGroups(coalition.side.BLUE, Group.Category.AIRPLANE) or {},
        BLUE = coalition.getGroups(coalition.side.RED,  Group.Category.AIRPLANE) or {},
    }

    for _, coalName in ipairs({"RED", "BLUE"}) do
        local gciSt   = gciState[coalName]
        local sqds    = squadrons[coalName] or {}

        -- ── Per-squadron scramble / RTB logic ─────────────────────────────
        for _, sqd in ipairs(sqds) do
            local threats  = getThreatsForZone(sqd.zone, coalName, cachedEnemyAir[coalName])
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
                    log(coalName .. " zone " .. sqd.zone .. " clear – ordering RTB")
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
--  SECTION 15 – FUEL MONITORING & FLIGHT MAINTENANCE  (both sides)
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
--  SECTION 16 – PERIODIC MEMORY CLEANUP  (every 10 min)
-- ─────────────────────────────────────────────────────────────────────────────
--  Housekeeping pass that runs every MEM_CLEANUP_INTERVAL seconds. Purges
--  accumulated table entries that per-tick prune passes may miss:
--    • gciState flights  – dead/standby records from completed scrambles
--    • suppressedUntil   – expired entries for dead SAMs
--    • trackedWeapons    – belt-and-suspenders TTL pass
--    • IADS.contacts     – stale Unit references for aircraft killed mid-tick
-- ─────────────────────────────────────────────────────────────────────────────
local MEM_CLEANUP_INTERVAL = 600   -- seconds (10 min).  Raise to 900 on low-pop servers.

local function memoryCleanupLoop()
    local now = timer.getTime()
    local purgedFlights, purgedSuppress, purgedWeapons, purgedContacts = 0, 0, 0, 0

    -- 1. Flight record purge ─────────────────────────────────────────────────
    -- Remove dead/standby entries accumulated from completed scramble cycles.
    -- Keeps countAirborne() / getAvailableFlights() O(active) not O(all-time).
    for _, coalName in ipairs({"RED", "BLUE"}) do
        local gciSt = gciState[coalName]
        for gName, fs in pairs(gciSt.flights) do
            if fs.status == "dead" or fs.status == "standby" then
                gciSt.flights[gName] = nil
                purgedFlights = purgedFlights + 1
            end
        end
    end

    -- 2. Suppression timer purge ─────────────────────────────────────────────
    -- Catch any suppressedUntil entries missed by the per-tick pruneDeadNodes
    -- pass (e.g. entries added for SAMs destroyed between prune ticks).
    for _, coalName in ipairs({"RED", "BLUE", "LEBANON"}) do
        local state    = IADS[coalName]
        local aliveSet = {}
        for _, name in ipairs(state.samNodes) do aliveSet[name] = true end
        for samName, expiry in pairs(state.suppressedUntil) do
            if not aliveSet[samName] or expiry < now then
                state.suppressedUntil[samName] = nil
                purgedSuppress = purgedSuppress + 1
            end
        end
    end

    -- 3. Weapon entry hard-purge ─────────────────────────────────────────────
    -- Belt-and-suspenders pass: the 120 s TTL in weaponTrackingLoop handles
    -- normal cases; this catches anything that slipped through (e.g. DCS
    -- paused the server mid-flight and getTime() didn't advance).
    local cleanWeapons = {}
    for _, wt in ipairs(trackedWeapons) do
        local ok, live = pcall(function() return wt.weapon:getPoint() end)
        if ok and live and (now - wt.launchTime <= 360) then
            table.insert(cleanWeapons, wt)
        else
            purgedWeapons = purgedWeapons + 1
        end
    end
    trackedWeapons = cleanWeapons

    -- 4. Stale contact reference purge ───────────────────────────────────────
    -- gatherContacts() replaces the whole list each tick, but if a Unit object
    -- becomes invalid between ticks the reference lingers until the next poll.
    -- This pass removes any contacts whose DCS unit no longer exists.
    for _, coalName in ipairs({"RED", "BLUE", "LEBANON"}) do
        local contacts = IADS[coalName].contacts
        local clean    = {}
        for _, c in ipairs(contacts) do
            if c.unit and c.unit:isExist() and c.unit:getLife() > 1 then
                table.insert(clean, c)
            else
                purgedContacts = purgedContacts + 1
            end
        end
        IADS[coalName].contacts = clean
    end

    log(string.format(
        "[MemClean] cycle complete — purged: %d flight records | %d suppress timers | %d weapon entries | %d stale contacts",
        purgedFlights, purgedSuppress, purgedWeapons, purgedContacts))

    return now + MEM_CLEANUP_INTERVAL
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SECTION 17 – INITIALISATION
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
    timer.scheduleFunction(memoryCleanupLoop,     {}, timer.getTime() + MEM_CLEANUP_INTERVAL)

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
--  3. NAME YOUR TRIGGER ZONES to match the zone fields in IADS_CFG.SQUADRONS (Syria):
--       RED zones (all 15 currently configured):
--         RED_ZONE_MEZZEH          – Mezzeh airbase / SW Damascus
--         RED_ZONE_DAMASCUS        – Damascus / southern Syria
--         RED_ZONE_MARJ_RUHAYYIL   – Marj Ruhayyil area
--         RED_ZONE_KHALKHALAH      – Khalkhalah AS / Sweida
--         RED_ZONE_AT_TANF         – At Tanf / eastern Jordan border
--         RED_ZONE_SAYQAL          – Sayqal / central Syria
--         RED_ZONE_THALAH          – Tha'lah (T-4) / Tiyas
--         RED_ZONE_PALMYRA         – Palmyra / Tadmur
--         RED_ZONE_DEIR_EZ-ZOR     – Deir ez-Zor / Euphrates valley
--         RED_ZONE_TABQA           – Tabqa / northern Euphrates
--         RED_ZONE_AN_NASIRIYAH    – An Nasiriyah
--         RED_ZONE_HAMA            – Hama area
--         RED_ZONE_ALEPPO          – Aleppo / northern Syria
--         RED_ZONE_AL_QUSAYR       – Al Qusayr / Lebanon border
--         RED_ZONE_BASSEL_AL-ASSAD – Latakia coast / Khmeimim
--
--  4. NAME YOUR INTERCEPT FLIGHTS using the groupPrefix defined in IADS_CFG.SQUADRONS.
--       Each group = one flight (2 aircraft recommended). Late Activate = ON.
--       RED examples (all 16 configured squadrons use these prefixes):
--         RED_AIR_MEZZEH_01 / _02       → groupPrefix "RED_AIR_MEZZEH"
--         RED_AIR_DAMASCUS_01 / _02     → groupPrefix "RED_AIR_DAMASCUS"
--         RED_AIR_THALAH_01 / _02       → groupPrefix "RED_AIR_THALAH"
--         RED_AIR_ALEPPO_01 / _02       → groupPrefix "RED_AIR_ALEPPO"
--         RED_AIR_PALMYRA_01 / _02      → groupPrefix "RED_AIR_PALMYRA"
--         RED_AIR_DEIR_EZ_ZOR_01        → groupPrefix "RED_AIR_DEIR_EZ_ZOR"
--         (see SQUADRONS.RED for the full list of all 16 squadrons)
--       BLUE examples (4 configured squadrons):
--         BLUE_AIR_RAMAT_DAVID_01 / _02  → groupPrefix "BLUE_AIR_RAMAT_DAVID"
--         BLUE_AIR_MEGIDDO_01 / _02      → groupPrefix "BLUE_AIR_MEGIDDO"
--         BLUE_AIR_PrinceHassan_01       → groupPrefix "BLUE_AIR_PrinceHassan"
--         BLUE_AIR_H4_01                 → groupPrefix "BLUE_AIR_H4"
--
--  5. NAME AWACS AIRCRAFT GROUPS with the AWACS prefix (default RED_AWACS_ / BLUE_AWACS_).
--       AWACS groups are kept at AWACS_ORBIT_ALT_FT by the orbit keeper loop.
--       They must be alive for the altitude correction to function.
--       Units named with these prefixes are also excluded from IADS contact lists
--       (CONTACT_IGNORE_PREFIXES) so invisible AWACS are never tracked as threats.
--         RED_AWACS_A50_KHMEIMIM   – A-50 Mainstay, orbit over Latakia coast
--         BLUE_AWACS_E3_INCIRLIK   – E-3 Sentry, orbit over southern Turkey
--
--  6. TRIGGER ZONES for BLUE squadrons use the prefix BLUE_ZONE_:
--         BLUE_ZONE_RAMAT_DAVID   – Northern Israel / Syria south approach
--         BLUE_ZONE_NorthWest     – NW Israel / central Mediterranean approach
--         BLUE_ZONE_PrinceHassan  – Jordan / H4 corridor
--         BLUE_ZONE_H4            – H4 pipeline / Iraqi border
--
--  7. If your MIST version doesn't expose mist.DBs.zonesByName, manually register
--     zones from a DO Script trigger at T+2 seconds:
--       registerRedZone("RED_ZONE_DAMASCUS")
--       registerBlueZone("BLUE_ZONE_RAMAT_DAVID")
--       (etc.)
--
--  8. OPTIONAL TUNING – edit the IADS_CFG table at the top of this file:
--       UPDATE_INTERVAL, ARM_SHUTDOWN_TIME, INTERCEPT_ALTITUDE,
--       GCI_FUEL_RTB_THRESHOLD, AWACS_ORBIT_ALT_FT, AWACS_ORBIT_KTS,
--       SAM_MIN_ENGAGE_SCORE, SAM_RANGE_TABLE, SAM_LOW_JET_IMMUNITY_AGL,
--       IMMORTAL_IADS_NETWORKS, SQUADRONS (add/remove squadrons for either side).
-- =============================================================================
