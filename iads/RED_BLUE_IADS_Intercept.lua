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
    UPDATE_INTERVAL         = 12,   -- Main IADS update loop; also drives pruneDeadNodes + gatherContacts for all three sub-IADS
    AIR_INTERCEPT_INTERVAL  = 25,   -- Air-intercept zone check loop; 25 s is reactive enough (~6.5 km at 900 km/h)
    WEAPON_TRACK_INTERVAL   = 5,    -- Incoming weapon tracking loop; ample for ARM/AGM intercept (ARMs fly 20–60 s)
    RTB_CHECK_INTERVAL      = 15,   -- Fuel and leash check for airborne intercept flights
    NODE_REFRESH_INTERVAL   = 900,  -- Full SAM/EWR node-list rebuild (15 min)
                                    -- Dead groups are silently dropped each cycle;
                                    -- no respawn — SAM sites are one-and-done.
    -- ── IADS detection ranges (metres) ─────────────────────────────────────
    SAM_MIN_ENGAGE_ALT      = 20,      -- metres AGL – ignore very low contacts
    SAM_FIRE_DELAY_MIN      = 0,       -- seconds – random delay before engaging (0 = instant)
    SAM_FIRE_DELAY_MAX      = 1,       -- tighter window = faster, more dangerous SAMs (was 3)
    SAM_MAX_ENGAGE_PER_CONTACT = 3,    -- max SAM nodes assigned to the same contact
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
    -- ── Probability of Kill helpers ──────────────────────────────────────────
    -- Each SAM computes a score; highest scorer engages.
    -- Score = basePk * altFactor * rangeFactor * healthFactor
    PKill_BASE              = 0.92,      -- base Pk for a healthy SAM on boresight (raised for lethality)

    SAM_MIN_ENGAGE_SCORE    = 0.25,      -- minimum Pk score required before a SAM will fire
                                         --   0.05 = fire at almost anything
                                         --   0.12 = very aggressive — takes long-range and edge shots
                                         --   0.18 = aggressive (previous value)
                                         --   0.25 = fire on any reasonable solution
                                         --   0.30 = skip low-quality edge shots (old default with 20s interval)
                                         --   0.35 = solid engagement solution required
                                         --   0.50 = disciplined — holds fire until near-optimal
                                         --   0.60+= very conservative, only ideal geometry

    -- ── ARM / munition defence ──────────────────────────────────────────────
    ARM_SHUTDOWN_TIME             = 90,    -- seconds radar stays silent after ARM detect (was 28 -- far too short; SAM re-lit 160+ km before HARM arrived)
    ARM_MOVE_RADIUS               = 800,   -- metres random relocate if unit is mobile
    ARM_SUPPRESS_TRIGGER_DIST     = 150000, -- metres – arm suppression triggers when ARM’s projected impact point is within this distance of a SAM node
    ARM_NEIGHBOR_SUPPRESS_RANGE   = 12000,  -- metres – also silence SAMs this close to the targeted node
    ARM_NEIGHBOR_SUPPRESS_TIME    = 12,     -- seconds neighbors stay dark (was 20; reduced so nearby SAMs can re-engage sooner)
    -- ── SHORAD terminal defence ──────────────────────────────────────────────
    -- SHORAD units fire a supplemental terminal layer against aircraft already
    -- handled by a long-range SAM.  They are also kept at weapons-free / radar-on
    -- at all times so the DCS AI can autonomously engage incoming ARMs/AGMs
    -- without the radar-management loop cycling them off every 12 seconds.
    SHORAD_HANDOFF_ENABLED        = true,
    SHORAD_NAME_PATTERN           = "SHORAD",  -- substring in group name identifying a SHORAD group
    SHORAD_MAX_RANGE              = 25000,     -- metres: SAMs with SAM_RANGE_TABLE max <= this are treated as
                                               -- SHORAD regardless of name (covers Pantsir, Tor, Tunguska, etc.)
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

        -- ── ATACMS / GMLRS (M270 MLRS / M142 HIMARS ground launchers) ──────
        -- DCS getTypeName() for HIMARS ATACMS variants (check exact names in
        -- the DCS Encyclopedia / unit editor if a new variant is added).
        ["MGM_140"]         = true,   -- MGM-140 ATACMS Block I (unguided submunitions)
        ["MGM-140"]         = true,   -- hyphen form
        ["MGM_140A"]        = true,   -- ATACMS Block IA (GPS/unitary)
        ["MGM-140A"]        = true,
        ["ATACMS"]          = true,   -- generic catch-all for any ATACMS variant
        ["M39"]             = true,   -- M39/M39A1 ATACMS (DCS internal)
        ["M30_GMLRS"]       = true,   -- M30 GMLRS (guided 70 km rocket)
        ["M31_GMLRS"]       = true,   -- M31 GMLRS unitary warhead
        ["GMLRS"]           = true,   -- generic GMLRS catch-all
    },

    -- ── Air Intercept ────────────────────────────────────────────────────────
    INTERCEPT_ALTITUDE      = 6000,   -- metres  – initial intercept climb altitude
    PATROL_ALTITUDE         = 6096,   -- metres  – CAP patrol orbit altitude (20,000 ft)
    INTERCEPT_SPEED         = 900,    -- km/h    – intercept speed
    MAX_ACTIVE_INTERCEPTS   = 5,      -- global cap: never more than this many intercept flights airborne at once
    RTB_LOITER_TIME         = 0,      -- (legacy, unused) flights now patrol until bingo/winchester
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
        -- Filter by coalition when specified; skip neutral (0) and enemy bases
        if coa == nil or ab:getCoalition() == coa then
            local abPos = ab:getPoint()
            local d = dist2d(pos, abPos)
            if d < bestDist then
                bestDist = d
                best = ab
            end
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
    RED     = { samNodes = {}, ewrNodes = {}, contacts = {}, suppressedUntil = {}, lastEngagement = {}, radarOn = {}, samSector = {} },
    BLUE    = { samNodes = {}, ewrNodes = {}, contacts = {}, suppressedUntil = {}, lastEngagement = {}, radarOn = {}, samSector = {} },
    -- Lebanon SAMs run as a completely isolated RED-side sub-IADS.
    -- They detect and engage BLUE aircraft independently; they do NOT
    -- share contacts or engagement assignments with the main RED network.
    LEBANON = { samNodes = {}, ewrNodes = {}, contacts = {}, suppressedUntil = {}, lastEngagement = {}, radarOn = {}, samSector = {} },
}

-- Tracked incoming weapons  { weapon_obj, launchPos, coalition_target }
local trackedWeapons = {}

-- Persistent role-confirmed tables: populated by the SHOT event handler the
-- first time a unit fires an ARM or AGM.  Unit names are used as keys because
-- they survive across gatherContacts() rebuilds for the whole mission session.
-- This is the ONLY reliable way to know a player's role — their slot name gives
-- us nothing, but the first HARM they fire tells us everything.
local _confirmedSEAD   = {}  -- unitName → true (fired at least one ARM this session)
local _confirmedStrike = {}  -- unitName → true (fired at least one AGM this session)

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

-- Auto-assign each SAM node to the geographic zone it physically sits inside.
-- Uses the same trigger zones as the GCI system — no manual prefix→zone mappings
-- needed.  Called once at init and again every NODE_REFRESH_INTERVAL (15 min).
-- zonePrefix: "RED_ZONE_" / "BLUE_ZONE_" / "LEBANON_ZONE_" (matches the ME naming).
-- explicitZones (optional): when provided, these zone names are used directly
-- instead of a MIST prefix search.  Required for LEBANON whose zones are listed
-- in IADS_CFG.LEBANON_ZONES but are not discoverable from MIST's zone DB.
local function buildSAMSectorCache(coaName, zonePrefix, explicitZones)
    local state = IADS[coaName]
    state.samSector = {}

    -- Collect zone names: explicit list takes priority, then MIST prefix search,
    -- then GCI registry fallback (only contains RED_ZONE_ / BLUE_ZONE_).
    local zoneNames = {}
    if explicitZones then
        for _, z in ipairs(explicitZones) do
            table.insert(zoneNames, z)
        end
    elseif mist and mist.DBs and mist.DBs.zonesByName then
        for zoneName, _ in pairs(mist.DBs.zonesByName) do
            if string.sub(zoneName, 1, #zonePrefix) == zonePrefix then
                table.insert(zoneNames, zoneName)
            end
        end
    else
        -- Fallback: enumerate the GCI registry (only contains RED_ZONE_ / BLUE_ZONE_).
        local gciCoaName = (coaName == "BLUE") and "BLUE" or "RED"
        for zoneName, _ in pairs(gciState[gciCoaName].zones) do
            table.insert(zoneNames, zoneName)
        end
    end

    local assigned = 0
    for _, samName in ipairs(state.samNodes) do
        local sp = getGroupPos(samName)
        if sp then
            for _, zoneName in ipairs(zoneNames) do
                local zd = trigger.misc.getZone(zoneName)
                if zd and zd.point and zd.radius then
                    if dist2d(sp, zd.point) <= zd.radius then
                        state.samSector[samName] = zoneName
                        assigned = assigned + 1
                        break  -- each SAM belongs to at most one sector
                    end
                end
            end
        end
    end
    log(string.format("[Sector] %s: %d/%d SAM nodes auto-assigned to sectors via %s*",
        coaName, assigned, #state.samNodes, zonePrefix))
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
    local function addUnit(obj, byRadar, detRecord)
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

        local typeName = (obj.getTypeName and obj:getTypeName()) or ""
        local desc     = obj:getDesc()
        local unitCat  = desc and desc.category

        -- ── Threat classification ──────────────────────────────────────────────
        -- Priority 1: confirmed by weapon fire this session (ground truth).
        -- Priority 2: platform-type prior (dedicated SEAD aircraft only).
        -- Priority 3: generic fighter / helicopter default.
        local threatPriority = IADS_CFG.THREAT_PRIORITY and IADS_CFG.THREAT_PRIORITY.FIGHTER_WEIGHT or 1.2
        if unitCat == Unit.Category.HELICOPTER then
            threatPriority = IADS_CFG.THREAT_PRIORITY and IADS_CFG.THREAT_PRIORITY.HELO_WEIGHT or 0.8
        elseif _confirmedSEAD[n] then
            -- This pilot has fired an ARM this session — definitive SEAD.
            threatPriority = IADS_CFG.THREAT_PRIORITY and IADS_CFG.THREAT_PRIORITY.SEAD_WEIGHT or 3.0
        elseif _confirmedStrike[n] then
            -- This pilot has fired an AGM this session — strike role confirmed.
            threatPriority = IADS_CFG.THREAT_PRIORITY and IADS_CFG.THREAT_PRIORITY.STRIKE_WEIGHT or 2.0
        else
            -- No weapon fired yet — use platform type as a conservative prior.
            -- Only dedicated SEAD/EW airframes (EA-18G, EF-111, MiG-25BM …) get
            -- SEAD priority here.  Multirole jets default to Fighter until they
            -- actually fire an ARM.
            local isSEAD = false
            local grpObj2 = obj.getGroup and obj:getGroup() or nil
            local grpN    = grpObj2 and grpObj2:getName() or ""
            if IADS_CFG.SEAD_GROUP_PATTERNS then
                for _, pat in ipairs(IADS_CFG.SEAD_GROUP_PATTERNS) do
                    if string.find(grpN, pat, 1, true) then isSEAD = true; break end
                end
            end
            if not isSEAD and IADS_CFG.SEAD_TYPE_PATTERNS then
                for _, pat in ipairs(IADS_CFG.SEAD_TYPE_PATTERNS) do
                    if string.find(typeName, pat, 1, true) then isSEAD = true; break end
                end
            end
            if isSEAD then
                threatPriority = IADS_CFG.THREAT_PRIORITY and IADS_CFG.THREAT_PRIORITY.SEAD_WEIGHT or 3.0
            else
                local isStrike = false
                if IADS_CFG.STRIKE_TYPE_PATTERNS then
                    for _, pat in ipairs(IADS_CFG.STRIKE_TYPE_PATTERNS) do
                        if string.find(typeName, pat, 1, true) then isStrike = true; break end
                    end
                end
                if isStrike then
                    threatPriority = IADS_CFG.THREAT_PRIORITY and IADS_CFG.THREAT_PRIORITY.STRIKE_WEIGHT or 2.0
                end
            end
        end

        if not seen[n] then
            seen[n] = true
            table.insert(state.contacts, {
                unit           = obj,
                group          = obj.getGroup and obj:getGroup() or nil,
                pos            = p,
                vel            = obj.getVelocity and obj:getVelocity() or {x=0,y=0,z=0},
                name           = n,
                typeName       = typeName,
                detectedAt     = now,
                byRadar        = byRadar,
                threatPriority = threatPriority,
            })
        end
    end

    -- ── PRIMARY PATH: coalition.getDetectedTargets (radar-realistic) ────────
    if type(coalition.getDetectedTargets) == "function" then
        -- Unit.SensorType.RADAR is integer 0 in some DCS builds; nil = all-sensor fallback.
        local radarSensorType = (Unit.SensorType ~= nil) and Unit.SensorType.RADAR or nil
        local det = coalition.getDetectedTargets(myCoaID, radarSensorType)
        for _, d in ipairs(det or {}) do
            addUnit(d.object, true, d)   -- pass detection record for native ECM quality flags
        end

        -- ── SUPPLEMENTAL: all-sensor pass for helicopters ───────────────────
        -- Helicopters flying NOE have near-zero RCS in DCS — radar-only sweeps
        -- routinely miss them entirely even when they are in plain LOS of EWRs.
        -- A second all-sensor pass (optical / IR / acoustic) picks up any helos
        -- the radar scan skipped.  Aircraft already added by the radar pass are
        -- deduplicated by the seen[] check inside addUnit(), so no double-count.
        local allDet = coalition.getDetectedTargets(myCoaID)
        for _, d in ipairs(allDet or {}) do
            local obj = d.object
            if obj and obj:isExist() and obj.getDesc then
                local desc = obj:getDesc()
                if desc and desc.category == Unit.Category.HELICOPTER then
                    addUnit(obj, false, d)   -- byRadar=false: acquired by optical/IR sensor
                end
            end
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

    -- Turn radar ON and ensure ROE/alarm state are correct.
    -- When a SAM goes dark (no contacts) the radar-management pass sets
    -- ROE=4 (return fire only) and alarm state=1 (green/standby).
    -- Those options persist until explicitly overridden.  Without resetting
    -- them here the DCS AI will lock its fire-control radar on the target
    -- (visible to the pilot as "being looked at") but WILL NOT fire because
    -- the ROE forbids offensive engagement.
    ctrl:setOnOff(true)
    ctrl:setOption(0, 2)   -- ROE: weapons free
    ctrl:setOption(9, 2)   -- alarm state: red (ready to engage)

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
            -- Sector zone: auto-assigned at startup from the SAM's physical position.
            -- state.samSector[sn] is nil when the SAM doesn't sit inside any zone.
            samCache[sn] = { pos = sp, health = hf, rng = getSAMRange(sn), sectorZone = state.samSector[sn] }
        end
    end

    -- ── Contact sort: highest-threat / closest contacts get first pick of SAMs ──
    -- Pre-compute a composite sort key for each contact so the comparator runs
    -- in O(1) instead of re-iterating samCache on every sort comparison.
    for _, c in ipairs(state.contacts) do
        local best = math.huge
        for _, entry in pairs(samCache) do
            local d = dist2d(c.pos, entry.pos)
            if d < best then best = d end
        end
        -- proxFactor: 0 km → 2.0, 300 km → 0.5 (closing contacts rank higher)
        local prox = math.max(0.5, 2.0 - (best / 150000))
        c._sortKey = (c.threatPriority or 1.0) * prox
    end
    if #state.contacts > 1 then
        table.sort(state.contacts, function(a, b)
            return (a._sortKey or 1.0) > (b._sortKey or 1.0)
        end)
    end

    -- ── Sector zone membership pre-computation ─────────────────────────────
    -- Collect the set of unique sector zones referenced by at least one SAM node
    -- this tick, then evaluate each contact against each of those zones exactly
    -- once.  This avoids repeated trigger.misc.getZone() calls in the inner loop.
    local contactInSector = {}  -- contactName → { zoneName → bool }
    local uniqueZones = {}
    for _, entry in pairs(samCache) do
        if entry.sectorZone then uniqueZones[entry.sectorZone] = true end
    end
    for zoneName, _ in pairs(uniqueZones) do
        local zd = trigger.misc.getZone(zoneName)
        if zd and zd.point and zd.radius then
            for _, contact in ipairs(state.contacts) do
                if not contactInSector[contact.name] then
                    contactInSector[contact.name] = {}
                end
                contactInSector[contact.name][zoneName] =
                    (dist2d(contact.pos, zd.point) <= zd.radius)
            end
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
                        local sup = state.suppressedUntil[samName] or 0
                        if now >= sup then
                            local entry = samCache[samName]
                            local score = entry and computeEngagementScore(entry, contact) or 0
                            -- Geographic sector derating: SAMs score lower for contacts
                            -- outside their assigned zone.  Does not block the shot —
                            -- prevents the best southern SAM from being wasted on a
                            -- northern contact when an equally capable northern site
                            -- is available.
                            if score > 0 and entry and entry.sectorZone then
                                local inSec = contactInSector[contact.name]
                                              and contactInSector[contact.name][entry.sectorZone]
                                if not inSec then
                                    score = score * (IADS_CFG.SAM_OUT_OF_SECTOR_PENALTY or 0.25)
                                end
                            end
                            if score > bestScore2 then
                                bestScore2 = score
                                bestSam2   = samName
                            end
                        end
                    end
                end

                if bestSam2 and bestScore2 > (IADS_CFG.SAM_MIN_ENGAGE_SCORE or 0.05) then
                    usedSAMs[bestSam2] = true
                    assigned_count = assigned_count + 1
                    assigned[contact.name] = bestSam2  -- used by SHORAD handoff check (last writer)
                    assigned["__sam__" .. bestSam2] = bestSam2  -- ensures ALL assigned SAMs are visible
                                                                 -- to the radar-management values scan,
                                                                 -- not just the last one per contact

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

    -- ── SHORAD independent engagement pass ───────────────────────────────────
    -- SHORAD units engage ANY contact in range autonomously — they do NOT wait
    -- for a long-range SAM to be assigned first.  Real-world SHORAD operates as
    -- an independent inner-layer: it fires on everything that enters its envelope
    -- regardless of whether the outer ring is already handling the contact.
    -- Checks both the SHORAD_NAME_PATTERN convention AND the SHORAD_MAX_RANGE
    -- so that Pantsir/Tor/Tunguska groups not literally named "*SHORAD*" are
    -- identified correctly (e.g. RED_SAM_THALAH with max range ≤ 25 km).
    if IADS_CFG.SHORAD_HANDOFF_ENABLED then
        local shoradPat    = IADS_CFG.SHORAD_NAME_PATTERN or "SHORAD"
        local shoradMaxRng = IADS_CFG.SHORAD_MAX_RANGE or 25000
        for _, contact in ipairs(state.contacts) do
            -- No assigned[contact.name] gate — SHORAD fires on any contact in range.
            for _, samName in ipairs(state.samNodes) do
                local rng      = getSAMRange(samName)
                local isSHORAD = string.find(samName, shoradPat, 1, true)
                              or (rng and rng.max <= shoradMaxRng)
                if isSHORAD then
                    -- Skip if this SHORAD is already handling a contact this tick
                    local alreadyBusy = false
                    for _, sn in pairs(assigned) do
                        if sn == samName then alreadyBusy = true; break end
                    end
                    if not alreadyBusy then
                        local sup = state.suppressedUntil[samName] or 0
                        if now >= sup then
                            local entry = samCache[samName]
                            if entry then
                                local score = computeEngagementScore(entry, contact)
                                if score > (IADS_CFG.SAM_MIN_ENGAGE_SCORE or 0.05) then
                                    -- Register under a unique key so the radar-management
                                    -- reverse-value scan sees it as assigned.
                                    assigned["__shorad__" .. samName] = samName
                                    if state.lastEngagement[samName] ~= contact.name then
                                        state.lastEngagement[samName] = contact.name
                                        state.radarOn[samName] = true
                                        local cap_c = contact
                                        local cap_s = samName
                                        timer.scheduleFunction(function()
                                            if groupAlive(cap_s)
                                            and cap_c.unit:isExist() and cap_c.unit:isActive()
                                            and cap_c.unit:getLife() > 1 then
                                                orderSAMEngage(cap_s, cap_c)
                                            else
                                                state.lastEngagement[cap_s] = nil
                                            end
                                            return nil
                                        end, nil, timer.getTime() + 0.5)
                                        log(coaName .. " SHORAD " .. samName
                                            .. " engaging " .. contact.name
                                            .. string.format(" [score=%.2f]", score))
                                    else
                                        state.radarOn[samName] = true  -- already on target
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Radar management: turn radar OFF for any SAM without an active assignment.
    -- SHORAD-type units are an exception: turning them off here creates a
    -- race with weaponTrackingLoop (which turns them on every 5 s to engage
    -- incoming ARMs/AGMs).  The oscillation means the DCS AI never gets a
    -- sustained radar-on window long enough to acquire and fire a missile.
    -- Instead, SHORAD units are kept at weapons-free / alarm-green when idle
    -- (low-power standby) and are upgraded to alarm-red by alertSHORADtoEngageWeapon.
    -- Only call setOnOff/setOption when the state actually needs to change — avoids
    -- issuing ~279 redundant DCS API calls per 10-second tick across 93 SAM nodes.
    local shoradPat   = IADS_CFG.SHORAD_NAME_PATTERN or "SHORAD"
    local shoradMaxRng = IADS_CFG.SHORAD_MAX_RANGE or 25000
    for _, samName in ipairs(state.samNodes) do
        local sup = state.suppressedUntil[samName] or 0
        if now >= sup then
            local hasAssigned = false
            for _, sName in pairs(assigned) do
                if sName == samName then hasAssigned = true; break end
            end
            if not hasAssigned then
                -- Determine whether this node is a short-range SHORAD type.
                -- We check both the name convention AND the SAM_RANGE_TABLE max
                -- so that unnamed Pantsir/Tor batteries are also protected.
                local rng = getSAMRange(samName)
                local isSHORADType = string.find(samName, shoradPat, 1, true)
                             or (rng and rng.max <= shoradMaxRng)
                if isSHORADType then
                    -- Keep SHORAD radar on and ROE at weapons-free so the DCS AI
                    -- engages incoming missiles autonomously without interruption.
                    -- weaponTrackingLoop will upgrade alarm state to red when a
                    -- weapon enters the engagement zone.
                    if state.radarOn[samName] ~= true then
                        local g = Group.getByName(samName)
                        if g and g:getController() then
                            g:getController():setOnOff(true)
                            g:getController():setOption(0, 2)   -- ROE: weapons free
                            g:getController():setOption(9, 1)   -- alarm state: green (standby)
                        end
                        state.radarOn[samName] = true
                    end
                else
                    -- Long-range SAM with no active target — go dark.
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

local function suppressSAMRadar(coaName, samName, nodeType)
    -- nodeType: "SAM" or "EWR" (from findARMTarget)
    nodeType = nodeType or "SAM"

    -- SHORAD units must NEVER suppress their radar for any reason.
    -- Their job is to engage everything in range — ARMs, AGMs, aircraft — and
    -- shutting them down is always counterproductive regardless of weapon type.
    -- Check both name convention AND range so short-range groups not literally
    -- named "*SHORAD*" (e.g. Pantsir/Tor batteries) are also protected.
    local _srng   = getSAMRange(samName)
    local _isSHORAD = string.find(samName, "SHORAD", 1, true)
                   or (_srng and _srng.max <= (IADS_CFG.SHORAD_MAX_RANGE or 25000))
    if _isSHORAD then return end

    -- Immortal networks never need to suppress radar – skip entirely.
    if IADS_CFG.IMMORTAL_IADS_NETWORKS and IADS_CFG.IMMORTAL_IADS_NETWORKS[coaName] then
        return
    end

    local g = Group.getByName(samName)
    if not g then return end
    local ctrl = g:getController()
    if ctrl then
        ctrl:setOnOff(false)  -- kill radar
        log(coaName .. " " .. nodeType .. " " .. samName .. " radar SUPPRESSED (ARM inbound)")
    end

    -- Sync state cache so the radar-management pass doesn't waste API calls
    -- trying to turn off a radar that is already off.
    IADS[coaName].radarOn[samName]      = false
    IADS[coaName].lastEngagement[samName] = nil  -- force fresh order after suppression window ends

    IADS[coaName].suppressedUntil[samName] = timer.getTime() + IADS_CFG.ARM_SHUTDOWN_TIME

    -- Also briefly silence neighboring SAMs so the ARM seeker can't re-acquire a nearby radar.
    -- Only applies when the primary target is a SAM; EWRs are typically isolated.
    local primaryPos = getGroupPos(samName)
    local neighborRange = IADS_CFG.ARM_NEIGHBOR_SUPPRESS_RANGE or 12000
    local neighborTime  = IADS_CFG.ARM_NEIGHBOR_SUPPRESS_TIME  or 20
    if primaryPos and nodeType == "SAM" then
        for _, nName in ipairs(IADS[coaName].samNodes) do
            if nName ~= samName then
                -- SHORAD units must NEVER be ARM-suppressed: they don't home on
                -- radar emissions, so there is no reason for them to go dark.
                -- Suppressing a SHORAD just disarms the one asset that could
                -- shoot the incoming ARM down.  We check both the name convention
                -- AND the SAM_RANGE_TABLE max so unnamed Pantsir/Tor batteries
                -- are also protected from neighbour-suppression.
                local isSHORAD = string.find(nName, "SHORAD", 1, true)
                local nRng     = getSAMRange(nName)
                local isSHORADType = isSHORAD or (nRng and nRng.max <= (IADS_CFG.SHORAD_MAX_RANGE or 25000))
                if not isSHORADType then
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
    end

    -- If the unit is mobile (wheeled SAM), attempt relocation.
    -- EWR nodes are typically static installations — skip relocation for them.
    if nodeType == "SAM" then
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
    end -- nodeType == "SAM" (relocation block)

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
                log(cn_cap .. " " .. sn_cap .. " radar back ONLINE")
            end
        end
        return nil
    end, nil, timer.getTime() + IADS_CFG.ARM_SHUTDOWN_TIME + 2)
end

-- Find which SAM or EWR node the ARM is most likely targeting (closest to
-- projected impact point).  SHORAD units are excluded — they don't operate
-- the long-range acquisition/fire-control radars that ARMs home on.
-- Returns: nodeName, distance, nodeType ("SAM" or "EWR")
local function findARMTarget(wpnPos, wpnVel, coaName)
    -- Extrapolate weapon path 60 s forward
    local futurePos = {
        x = wpnPos.x + wpnVel.x * 60,
        y = wpnPos.y + wpnVel.y * 60,
        z = wpnPos.z + wpnVel.z * 60,
    }

    local state = IADS[coaName]
    local shoradPat    = IADS_CFG.SHORAD_NAME_PATTERN or "SHORAD"
    local shoradMaxRng = IADS_CFG.SHORAD_MAX_RANGE or 25000
    local best, bestDist, bestType = nil, math.huge, nil

    -- Check SAM nodes (excluding SHORAD by both name AND range)
    for _, samName in ipairs(state.samNodes) do
        local rng = getSAMRange(samName)
        local isSHORAD = string.find(samName, shoradPat, 1, true)
                      or (rng and rng.max <= shoradMaxRng)
        if not isSHORAD then
            local sp = getGroupPos(samName)
            if sp then
                local d = dist3d(futurePos, sp)
                if d < bestDist then
                    bestDist = d
                    best     = samName
                    bestType = "SAM"
                end
            end
        end
    end

    -- Check EWR nodes — they have active radar emitters that ARMs home on
    for _, ewrName in ipairs(state.ewrNodes) do
        local ep = getGroupPos(ewrName)
        if ep then
            local d = dist3d(futurePos, ep)
            if d < bestDist then
                bestDist = d
                best     = ewrName
                bestType = "EWR"
            end
        end
    end

    return best, bestDist, bestType
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

    local CLOSE = 50000   -- metres – engage immediately (widened from 30 km; at HARM approach
                           -- speed ~527 m/s the DCS AI needs ≥60 s to acquire and fire, and the
                           -- weaponTrackingLoop runs every 5 s, so 50 km gives ~95 s of reaction window)
    local WARN  = 90000   -- metres – slew radar, standby to engage (widened from 60 km)
    local now   = timer.getTime()

    for _, samName in ipairs(state.samNodes) do
        -- SHORAD units are NEVER skipped, even when skipSuppressed=true.
        -- They do not suppress their radars for ARM evasion and must always
        -- be free to engage incoming weapons (ARMs, AGMs) at close range.
        -- Check both name convention AND range table for consistent SHORAD identification.
        local rng = getSAMRange(samName)
        local isSHORAD = string.find(samName, "SHORAD", 1, true)
                      or (rng and rng.max <= (IADS_CFG.SHORAD_MAX_RANGE or 25000))

        -- Skip nodes that are currently suppressed (ARM evasion – keep radar dark)
        local suppressed = false
        if skipSuppressed and not isSHORAD then
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
                        -- Mark radar state so optimizeEngagements doesn't immediately
                        -- shut this node off on the next 12-second tick.
                        state.radarOn[samName] = true
                    elseif d <= WARN then
                        -- Within warning range – wake up radar, hold fire
                        g:getController():setOnOff(true)
                        g:getController():setOption(9, 2)   -- alarm state: red (tracking mode)
                        state.radarOn[samName] = true
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
    -- Fast path: ignore every event type we don't handle.
    -- This avoids creating a pcall closure (and its GC pressure) for the
    -- large bursts of S_EVENT_SCORE / S_EVENT_HIT / S_EVENT_BDA events that
    -- DCS fires during multi-unit explosions (e.g. HARM vs SAM site).
    local id = event.id
    if id ~= world.event.S_EVENT_SHOT
    and id ~= world.event.S_EVENT_DEAD
    and id ~= world.event.S_EVENT_CRASH then
        return
    end
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

            -- ── Role confirmation ──────────────────────────────────────────────
            -- Record that this specific unit is confirmed in a SEAD or Strike
            -- role.  gatherContacts() checks these tables each tick so the
            -- contact's threat priority is immediately upgraded on the next
            -- 12-second scan — no extra API calls required.
            if initiator and initiator.getName then
                local uName = initiator:getName()
                if isARM then
                    if not _confirmedSEAD[uName] then
                        _confirmedSEAD[uName] = true
                        log("[ThreatID] " .. uName .. " confirmed SEAD (fired " .. typeName .. ")")
                    end
                elseif isAGM and not _confirmedSEAD[uName] then
                    -- Only upgrade to Strike if not already confirmed SEAD
                    if not _confirmedStrike[uName] then
                        _confirmedStrike[uName] = true
                        log("[ThreatID] " .. uName .. " confirmed Strike (fired " .. typeName .. ")")
                    end
                end
            end

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
            -- ── Dynamic SAM reallocation ──────────────────────────────────────
            -- If the dead unit's group was a SAM node and the whole group is now
            -- destroyed, remove it from the network immediately and schedule an
            -- out-of-band optimizeEngagements() so contacts it was handling are
            -- reassigned within ~1 s instead of waiting the full UPDATE_INTERVAL.
            if not groupAlive(gName) then
                for _, coaName in ipairs({"RED", "BLUE", "LEBANON"}) do
                    local iadsState = IADS[coaName]
                    for i = #iadsState.samNodes, 1, -1 do
                        if iadsState.samNodes[i] == gName then
                            table.remove(iadsState.samNodes, i)
                            iadsState.lastEngagement[gName] = nil
                            iadsState.radarOn[gName]         = nil
                            iadsState.suppressedUntil[gName] = nil
                            log(coaName .. " SAM node KIA: " .. gName
                                .. " — immediately removed; contacts reallocating.")
                            local cn_cap = coaName
                            timer.scheduleFunction(function()
                                if #IADS[cn_cap].contacts > 0 then
                                    optimizeEngagements(cn_cap)
                                end
                                return nil
                            end, nil, timer.getTime() + 1)
                            break
                        end
                    end
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
            -- Guard: some mod weapons or DCS edge-cases return nil velocity.
            -- Without this, findARMTarget would crash on nil.x, throw an uncaught
            -- error, and permanently kill the weapon tracking loop for the mission.
            if not vel then vel = { x = 0, y = 0, z = 0 } end

            if wt.isARM then
                if not wt.alerted then
                    -- Find the SAM node most likely targeted and suppress it.
                    -- Trigger earlier (ARM_SUPPRESS_TRIGGER_DIST, default 150 km) so
                    -- the SAM has time to go dark before the HARM seeker locks it.
                    local trigger_dist = IADS_CFG.ARM_SUPPRESS_TRIGGER_DIST or 150000
                    local target, dist, nodeType = findARMTarget(wpnPos, vel, wt.targetCoa)
                    if target and dist < trigger_dist then
                        suppressSAMRadar(wt.targetCoa, target, nodeType)
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
--  SECTION 11 – AWACS ORBIT KEEPER  (both coalitions)
-- ─────────────────────────────────────────────────────────────────────────────
-- Runs every 5 min and re-assigns tasks to any AWACS group that has drifted
-- more than 1000 ft below its configured altitude.  Uses a ComboTask with
-- the AWACS role task FIRST (preserves DCS datalink / GCI functionality) and
-- the Orbit task second so both run concurrently.  Previous versions used a
-- bare Orbit setTask that silently replaced the built-in AWACS role, breaking
-- datalink target sharing to fighters and helicopters.
local function awacsOrbitLoop()
    local altM   = (IADS_CFG.AWACS_ORBIT_ALT_FT or 30000) * 0.3048   -- ft → m
    local spdMS  = (IADS_CFG.AWACS_ORBIT_KTS    or 350)   * 0.514444  -- kts → m/s
    local thresh = altM - 305   -- 1000 ft below target triggers correction

    -- Process both coalitions
    local awacsConfigs = {
        { coaID = coalition.side.BLUE, prefix = IADS_CFG.AWACS_PREFIX_BLUE or "BLUE_AWACS_" },
        { coaID = coalition.side.RED,  prefix = IADS_CFG.AWACS_PREFIX_RED  or "RED_AWACS_"  },
    }

    for _, cfg in ipairs(awacsConfigs) do
        for _, gName in ipairs(getAirGroupsByPrefix(cfg.coaID, cfg.prefix)) do
            if groupAlive(gName) then
                local p = getGroupPos(gName)
                if p and p.y < thresh then
                    local g = Group.getByName(gName)
                    if g then
                        local ctrl = g:getController()
                        if ctrl then
                            -- ComboTask: AWACS role first (datalink), then Orbit for altitude.
                            -- DCS processes tasks in a ComboTask concurrently, so the AWACS
                            -- role (GCI callouts, datalink target sharing) stays active while
                            -- the Orbit task controls altitude and speed.
                            ctrl:setTask({
                                id = "ComboTask",
                                params = {
                                    tasks = {
                                        {
                                            id = "AWACS",
                                            params = {},
                                        },
                                        {
                                            id = "Orbit",
                                            params = {
                                                pattern  = "Circle",
                                                speed    = spdMS,
                                                altitude = altM,
                                            },
                                        },
                                    },
                                },
                            })
                            log("AWACS " .. gName .. " altitude recovery – orbit restored at FL"
                                .. math.floor(altM * 3.28084 / 100 + 0.5))
                        end
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
                        -- Group.getByName() returned nil.
                        -- Two possibilities: (a) destroyed in-mission, or (b) a late-activate
                        -- group that DCS has not yet materialised — Group.getByName() returns nil
                        -- for unspawned late-activate groups in many DCS builds (same quirk that
                        -- blocked the CSAR garrison activation).
                        -- Only permanently mark dead if the group was previously seen as airborne
                        -- or RTB.  If it was never dispatched, leave it available and let
                        -- dispatchFlight handle materialisation via MIST.
                        local prevStatus = gciSt.flights[gName] and gciSt.flights[gName].status
                        if prevStatus == "airborne" or prevStatus == "rtb" then
                            if not gciSt.flights[gName] then gciSt.flights[gName] = {} end
                            gciSt.flights[gName].status = "dead"
                            log("[GCI] " .. gName .. " was airborne, now gone — KIA, marked dead.")
                        else
                            -- Never dispatched or was standby — nil likely means late-activate
                            -- not yet spawned.  Add to available; dispatchFlight will use MIST
                            -- dynAdd to materialise it if Group.getByName() still returns nil.
                            table.insert(available, gName)
                        end
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

-- Contacts from IADS[coaName].contacts that are within or approaching a zone.
-- Only returns enemies that are BOTH physically inside the zone AND detected by
-- the coalition's radar/sensor network (IADS contacts list).  This prevents GCI
-- from scrambling against undetected aircraft (terrain-masked, ECM, etc.).
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
    local zRadius = zd.radius

    -- Build a set of unit names currently detected by IADS radar/sensors.
    -- For RED GCI we check both RED and LEBANON contacts (Lebanon is a RED sub-IADS
    -- that tracks BLUE aircraft independently).
    local detectedSet = {}
    local iadsNetworks = { coaName }
    if coaName == "RED" then iadsNetworks[#iadsNetworks + 1] = "LEBANON" end
    for _, netName in ipairs(iadsNetworks) do
        for _, c in ipairs(IADS[netName].contacts) do
            if c.name then detectedSet[c.name] = true end
        end
    end

    -- Scan enemy aircraft physically inside the zone, but only include ones
    -- that appear in the IADS detection list.
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
                    if uPos and dist2d(uPos, zPos) <= zRadius
                    and detectedSet[u:getName()] then
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

    -- Activate the late-activate group.
    -- Primary: trigger.action.activateGroup() — requires a live Group object.
    -- Fallback: mist.dynAdd() — materialises the group from the ME definition when
    --           Group.getByName() returns nil for an unspawned late-activate group
    --           (a known DCS quirk: the group exists in the mission data but is not
    --           yet registered in the DCS runtime until the first activation call).
    local g = Group.getByName(groupName)
    if g then
        trigger.action.activateGroup(g)
    else
        -- Group.getByName() returned nil — try MIST dynAdd as a fallback.
        local mGrpData = mist and mist.DBs and mist.DBs.groupsByName
                         and mist.DBs.groupsByName[groupName]
        if mGrpData then
            local ok, dynErr = pcall(function() mist.dynAdd(mGrpData) end)
            if ok then
                log("[GCI] '" .. groupName .. "' materialised via MIST dynAdd (late-activate fallback).")
            else
                log("[GCI] Dispatch failed for '" .. groupName .. "': MIST dynAdd error: " .. tostring(dynErr) .. " — marking dead.")
                if not gciSt.flights[groupName] then gciSt.flights[groupName] = {} end
                gciSt.flights[groupName].status = "dead"
                return
            end
        else
            -- Not in MIST data either — group was destroyed before it could fly.
            log("[GCI] Dispatch failed: '" .. groupName .. "' not found in DCS or MIST — marking dead.")
            if not gciSt.flights[groupName] then gciSt.flights[groupName] = {} end
            gciSt.flights[groupName].status = "dead"
            return
        end
    end

    gciSt.flights[groupName] = {
        status       = "airborne",
        zone         = sqd.zone,
        homeBase     = sqd.homeBase,
        callsign     = sqd.callsign,
        coalName     = coalName,
        launchTime   = timer.getTime(),
        targetUnitID = nil,  -- updated by re-targeting logic in gciInterceptLoop
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
            -- Record target so re-targeting logic knows what we're chasing
            local fRec = gciSt.flights[cap_gName]
            if fRec then fRec.targetUnitID = targetUnit:getID() end
        else
            -- No immediate target — orbit over zone centre at patrol altitude
            local zd  = trigger.misc.getZone(cap_sqd.zone)  -- native DCS API, correct world coords
            local ox   = zd and zd.point.x or 0
            local oz   = zd and zd.point.z or 0
            taskDef = {
                id = "Orbit",
                params = {
                    pattern  = "Circle",
                    speed    = IADS_CFG.INTERCEPT_SPEED / 3.6,
                    altitude = IADS_CFG.PATROL_ALTITUDE,
                    point    = { x = ox, y = oz },
                }
            }
            local fRec = gciSt.flights[cap_gName]
            if fRec then fRec.patrolling = true end
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

                -- ── Re-target existing airborne flights ──────────────────────
                -- For each airborne flight in this squadron, check whether its
                -- current target is still alive and in-zone.  If not, pick the
                -- closest threat and re-task.  This makes interceptors dynamic
                -- and harder to predict — they switch targets instead of going
                -- home the moment the original threat dies.
                for gName, fs in pairs(gciSt.flights) do
                    if string.sub(gName, 1, #sqd.groupPrefix) == sqd.groupPrefix
                    and fs.status == "airborne" then
                        local needsRetarget = false
                        if not fs.targetUnitID then
                            needsRetarget = true
                        else
                            -- Check if current target is still alive
                            local curTarget = nil
                            for _, t in ipairs(threats) do
                                if t.unit:getID() == fs.targetUnitID then
                                    curTarget = t
                                    break
                                end
                            end
                            if not curTarget then needsRetarget = true end
                        end

                        if needsRetarget and #threats > 0 then
                            -- Pick the closest threat to this flight
                            local fPos = getGroupPos(gName)
                            if fPos then
                                local bestThreat, bestDist = nil, math.huge
                                for _, t in ipairs(threats) do
                                    local d = dist2d(fPos, t.pos)
                                    if d < bestDist then
                                        bestDist   = d
                                        bestThreat = t
                                    end
                                end
                                if bestThreat and bestThreat.unit:isExist()
                                and bestThreat.unit:isActive() and bestThreat.unit:getLife() > 1 then
                                    local grp  = Group.getByName(gName)
                                    local ctrl = grp and grp:getController()
                                    if ctrl then
                                        ctrl:setTask({
                                            id = "ComboTask",
                                            params = { tasks = { {
                                                id = "EngageUnit",
                                                params = {
                                                    unitId     = bestThreat.unit:getID(),
                                                    weaponType = 268402688,
                                                    expend     = "Auto",
                                                },
                                            } } },
                                        })
                                        fs.targetUnitID = bestThreat.unit:getID()
                                        fs.patrolling   = nil  -- back in combat, no longer patrolling
                                        log(coalName .. " " .. gName .. " re-targeted to " .. bestThreat.unit:getName())
                                    end
                                end
                            end
                        end
                    end
                end

                -- Scramble additional flights if under-strength
                local needed = math.min(#threats, sqd.maxFlights) - airborne
                if needed > 0 then
                    -- Global cap: never exceed MAX_ACTIVE_INTERCEPTS total airborne across all squadrons.
                    local totalAirborne = 0
                    for _, fs in pairs(gciSt.flights) do
                        if fs.status == "airborne" then totalAirborne = totalAirborne + 1 end
                    end
                    local headroom  = math.max(0, (IADS_CFG.MAX_ACTIVE_INTERCEPTS or 999) - totalAirborne)
                    local available = getAvailableFlights(sqd, gciSt)
                    local toSend    = math.min(needed, #available, headroom)
                    for i = 1, toSend do
                        local gn      = available[i]
                        local stagger = (i - 1) * 0.75  -- 0.75 s gap between each spawn
                        if stagger == 0 then
                            dispatchFlight(gn, coalName, sqd, threats, gciSt)
                        else
                            -- Defer subsequent flights so DCS doesn't materialise
                            -- multiple groups in the same frame, which causes a stutter.
                            timer.scheduleFunction(function()
                                dispatchFlight(gn, coalName, sqd, threats, gciSt)
                                return nil
                            end, nil, timer.getTime() + stagger)
                        end
                    end
                end

            elseif airborne > 0 then
                -- No threats — switch airborne flights to CAP patrol orbit.
                -- They stay up at 20,000 ft protecting the airspace until
                -- bingo fuel, winchester (out of AA missiles), or shot down.
                for gName, fs in pairs(gciSt.flights) do
                    if string.sub(gName, 1, #sqd.groupPrefix) == sqd.groupPrefix
                    and fs.status == "airborne" and not fs.patrolling then
                        local grp = Group.getByName(gName)
                        if grp then
                            local ctrl = grp:getController()
                            local zd   = trigger.misc.getZone(sqd.zone)
                            if ctrl and zd and zd.point then
                                ctrl:setTask({
                                    id = "ComboTask",
                                    params = { tasks = { {
                                        id = "Orbit",
                                        params = {
                                            pattern  = "Circle",
                                            speed    = IADS_CFG.INTERCEPT_SPEED / 3.6,
                                            altitude = IADS_CFG.PATROL_ALTITUDE,
                                            point    = { x = zd.point.x, y = zd.point.z },
                                        },
                                    } } },
                                })
                                ctrl:setOption(0, 2)  -- ROE weapons free
                                ctrl:setOption(1, 0)  -- aggressive reaction
                                fs.patrolling   = true
                                fs.targetUnitID = nil
                                log(gName .. " zone clear – CAP patrol at 20,000 ft over " .. sqd.zone)
                            end
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
                    -- Check ammo: winchester = out of air-to-air missiles
                    local hasAAMissiles = false
                    for _, u in ipairs(grp:getUnits()) do
                        if u:getLife() > 1 then
                            local ammo = u:getAmmo()
                            if ammo then
                                for _, a in ipairs(ammo) do
                                    if a.count and a.count > 0 and a.desc
                                    and a.desc.category == 1        -- Weapon.Category.MISSILE
                                    and a.desc.missileCategory == 1 -- Weapon.MissileCategory.AAM
                                    then
                                        hasAAMissiles = true
                                        break
                                    end
                                end
                            end
                            if hasAAMissiles then break end
                        end
                    end

                    if not alive then
                        fs.status = "dead"
                        log(gName .. " KIA (maintenance loop)")
                    elseif lowestFuel < fuelMin then
                        log(string.format("%s bingo fuel (%.0f%%) – RTB", gName, lowestFuel * 100))
                        orderFlightRTB(gName, gciSt,
                            string.format("Bingo fuel (%.0f%%).", lowestFuel * 100))
                    elseif not hasAAMissiles then
                        log(gName .. " winchester (no AA missiles) – RTB")
                        orderFlightRTB(gName, gciSt, "Winchester – out of AA missiles.")
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
local MEM_CLEANUP_INTERVAL = 1800  -- seconds (30 min).  Most tables are already pruned by faster loops.

local function memoryCleanupLoop()
    local now = timer.getTime()
    local purgedFlights, purgedSuppress, purgedWeapons, purgedContacts = 0, 0, 0, 0

    -- 1. Flight record purge ─────────────────────────────────────────────────
    -- Remove standby entries from completed RTB cycles so the booking tables
    -- stay lean.  DEAD entries are NEVER purged — killed flights must remain
    -- permanently marked so getAvailableFlights() doesn't re-discover and
    -- re-dispatch them via MIST dynAdd.
    for _, coalName in ipairs({"RED", "BLUE"}) do
        local gciSt = gciState[coalName]
        for gName, fs in pairs(gciSt.flights) do
            if fs.status == "standby" then
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

    -- Initial IADS node build + automatic sector assignment
    buildNodeList("RED",     coalition.side.RED,  "RED_SAM_",         "RED_EWR_",         "RED_SAM_LEBANON_")
    buildNodeList("BLUE",    coalition.side.BLUE, "BLUE_SAM_",        "BLUE_EWR_")
    buildNodeList("LEBANON", coalition.side.RED,  "RED_SAM_LEBANON_", "RED_EWR_LEBANON_")
    buildSAMSectorCache("RED",     "RED_ZONE_")
    buildSAMSectorCache("BLUE",    "BLUE_ZONE_")
    buildSAMSectorCache("LEBANON", "LEBANON_ZONE_", IADS_CFG.LEBANON_ZONES)

    -- Schedule main loops
    timer.scheduleFunction(iadsUpdateLoop,       {}, timer.getTime() + 10)
    timer.scheduleFunction(weaponTrackingLoop,    {}, timer.getTime() + 5)
    timer.scheduleFunction(gciInterceptLoop,      {}, timer.getTime() + 15)
    timer.scheduleFunction(flightMaintenanceLoop, {}, timer.getTime() + 30)
    timer.scheduleFunction(awacsOrbitLoop,        {}, timer.getTime() + 20)
    timer.scheduleFunction(memoryCleanupLoop,     {}, timer.getTime() + MEM_CLEANUP_INTERVAL)

    -- Incremental IADS node-list refresh.
    -- LEBANON: skipped entirely (immortal, never changes after init).
    -- RED:     skipped (dead nodes removed instantly by DEAD event handler
    --          + pruneDeadNodes every 12s; RED SAMs are one-and-done).
    -- BLUE:    additive-only scan — discovers newly activated groups
    --          (FOB late-activates, CTLD NASAMS spawns) without wiping
    --          the existing immortal nodes.  Sector cache only rebuilt
    --          when new nodes are actually discovered.
    local NODE_REFRESH_INTERVAL = IADS_CFG.NODE_REFRESH_INTERVAL or 900
    local function nodeRefreshLoop(_, time)
        -- ── BLUE additive scan ──────────────────────────────────────────
        local blueState = IADS.BLUE
        local knownSAM  = {}
        local knownEWR  = {}
        for _, n in ipairs(blueState.samNodes) do knownSAM[n] = true end
        for _, n in ipairs(blueState.ewrNodes) do knownEWR[n] = true end

        local added = 0
        for _, name in ipairs(getGroupsByPrefix(coalition.side.BLUE, "BLUE_SAM_")) do
            if not knownSAM[name] and groupAlive(name) then
                table.insert(blueState.samNodes, name)
                added = added + 1
                log("[NodeRefresh] New BLUE SAM discovered: " .. name)
            end
        end
        for _, name in ipairs(getGroupsByPrefix(coalition.side.BLUE, "BLUE_EWR_")) do
            if not knownEWR[name] and groupAlive(name) then
                table.insert(blueState.ewrNodes, name)
                added = added + 1
                log("[NodeRefresh] New BLUE EWR discovered: " .. name)
            end
        end

        -- Only rebuild BLUE sector cache when new nodes were added.
        if added > 0 then
            buildSAMSectorCache("BLUE", "BLUE_ZONE_")
        end

        log(string.format("[NodeRefresh] Incremental done. BLUE: +%d new nodes (%d SAMs total)  RED: %d SAMs  LEBANON: %d SAMs",
            added, #blueState.samNodes, #IADS.RED.samNodes, #IADS.LEBANON.samNodes))
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
--       SAM_MIN_ENGAGE_SCORE, SAM_RANGE_TABLE,
--       IMMORTAL_IADS_NETWORKS, SQUADRONS (add/remove squadrons for either side).
-- =============================================================================
