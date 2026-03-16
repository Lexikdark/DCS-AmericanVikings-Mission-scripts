-- ============================================================================
--  DCS_DynamicWeatherCycle.lua
--  American Vikings — Syria Mission
--  Dynamic weather cycle: Clear → Building → Thunderstorm → Clearing → Overcast → Clear
--
--  HOW IT WORKS
--  ─────────────────────────────────────────────────────────────────────────
--  DCS's scripting engine (SSE) can READ atmosphere data via atmosphere.*
--  but CANNOT change cloud presets, fog, or visibility at runtime.
--  There is no setWeather() function — this is a hard DCS engine limit.
--
--  What DCS does automatically when atmosphere_type = 1 (Dynamic):
--    • Gradually drifts wind direction and speed over time
--    • Shifts barometric pressure as weather systems evolve
--    • Varies turbulence around the baseline set in the ME
--    All of this happens on its own with no triggers or scripting needed.
--
--  What THIS SCRIPT adds:
--    • Named weather stages with broadcast text matching the DCS cycle
--    • Reads live wind / pressure / temp via atmosphere.* every 30 seconds
--    • Broadcasts ATIS-style weather reports every 5 minutes
--    • Issues 30-minute advance warnings before storm / clearing stages
--    • Tracks and reports wind trend (rising, falling, veering, backing)
--    • On-demand ATIS via a User Flag trigger
--
--  The WEATHER_STAGES table defines the text pilots see in their ATIS.
--  The actual sky (clouds, fog, visibility) is controlled entirely by DCS's
--  own dynamic atmosphere engine based on your ME starting conditions.
--
--  ─────────────────────────────────────────────────────────────────────────
--  INSTALLATION  (two steps only)
--  ─────────────────────────────────────────────────────────────────────────
--  1. In the ME, create ONE trigger:
--       Type:      ONCE
--       Condition: MISSION START
--       Action:    DO SCRIPT FILE → select this file
--
--  2. In the ME Weather tab:
--       Atmosphere Type = DYNAMIC
--       Set your starting cloud preset, wind, pressure, and temperature.
--       DCS will naturally evolve those conditions over time — no extra
--       triggers needed.
--
--  Adjust AIRFIELD_REF in CFG below to your primary Syria airfield coords.
--
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
--  CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════

local CFG = {

    -- ── Airfield reference position (world coords for atmosphere queries) ──
    -- Syria — Incirlik AFB approximate world coordinates
    -- Adjust to your primary operating base.
    AIRFIELD_REF = { x = -35000, y = 0, z = 75000 },

    -- ── ATIS broadcast interval (seconds) ──────────────────────────────────
    ATIS_INTERVAL = 300,          -- every 5 minutes

    -- ── Warning lead time before stage transition (seconds) ────────────────
    WARN_LEAD_TIME = 1800,        -- 30-minute heads-up before storm / clearing

    -- ── ATIS trigger flag ──────────────────────────────────────────────────
    -- Set User Flag 10 to TRUE in a trigger to force an immediate ATIS broadcast
    ATIS_FLAG = 10,

    -- ── Wind history depth for trend calculation (number of samples) ───────
    WIND_HISTORY_SIZE = 6,

    -- ── Coalition for weather messages (0=all, 1=red, 2=blue) ────────────
    BROADCAST_COALITION = 2,      -- blue only; change to 0 for all

    -- ── Display duration for messages (seconds) ───────────────────────────
    MSG_DURATION_SHORT = 12,
    MSG_DURATION_LONG  = 25,

    -- ── Weather preset override ────────────────────────────────────────────
    -- 0  = pick randomly every mission start (recommended)
    -- 1-15 = always use that specific preset number (useful for testing or
    --        missions where you want to guarantee a particular weather type)
    -- Change this value each session if you want to manually rotate presets.
    FORCE_PRESET = 0,

}

-- ═══════════════════════════════════════════════════════════════════════════
--  WEATHER PRESETS
--  A random preset is chosen at mission start (seeded from real-world clock).
--  Each preset defines a named weather pattern with a full 12-hour stage list.
--
--  Each preset has:
--    name    — announced to pilots at mission start
--    desc    — one-line description shown in the startup broadcast
--    stages  — list of stage blocks, same structure as WEATHER_STAGES:
--
--  Each stage defines:
--    startMin   — mission time (minutes) when this stage's text activates
--    name       — label shown in ATIS header (e.g. "CLEAR", "THUNDERSTORM")
--    category   — VFR / MVFR / IFR / LIFR  (shown in brackets to pilots)
--    windDesc   — description of wind character expected during this phase
--    cloudDesc  — sky condition description (write what DCS actually shows)
--    visDesc    — expected visibility description
--    hazards    — list of pilot NOTAMs; use {} for none
--
--  Adding a new preset: copy any existing preset block, change name/desc/stages,
--  append it to WEATHER_PRESETS. No other changes needed.
-- ═══════════════════════════════════════════════════════════════════════════

local WEATHER_PRESETS = {

    -- ── Preset 1 ── Classic Storm Cycle ────────────────────────────────────
    {
        name = "CLASSIC STORM CYCLE",
        desc = "Clear morning, clouds building mid-day, full thunderstorm, overnight clearing",
        stages = {
            {
                startMin  = 0,             -- 0h00m — mission start
                name      = "CLEAR",
                category  = "VFR",
                windDesc  = "Light and variable, surface 3-6 kts",
                cloudDesc = "Few cumulus 6500 ft, excellent visibility",
                visDesc   = "50+ km CAVOK",
                hazards   = {},
            },
            {
                startMin  = 120,           -- 2h00m — clouds building
                name      = "BUILDING",
                category  = "MVFR",
                windDesc  = "South-Southwesterly, increasing 10-18 kts, veering",
                cloudDesc = "Scattered to broken, base lowering 2600 ft",
                visDesc   = "15-25 km, haze developing",
                hazards   = { "Cloud base lowering", "Wind shift imminent" },
            },
            {
                startMin  = 270,           -- 4h30m — storm
                name      = "THUNDERSTORM",
                category  = "LIFR",
                windDesc  = "Westerly gusty 25-40 kts, severe turbulence",
                cloudDesc = "Cumulonimbus overcast, base 2000 ft, lightning",
                visDesc   = "< 1 km in precipitation, RVR poor",
                hazards   = {
                    "SEVERE TURBULENCE — avoid flight",
                    "Heavy precipitation — windscreen wash",
                    "Lightning hazard to high structures",
                    "Windshear on approach",
                    "Icing in cloud",
                },
            },
            {
                startMin  = 420,           -- 7h00m — clearing
                name      = "CLEARING",
                category  = "IFR",
                windDesc  = "Northwesterly 15-22 kts, occasional gusts",
                cloudDesc = "Broken stratocumulus, base rising to 3900 ft",
                visDesc   = "8-20 km, patchy fog lifting",
                hazards   = { "Residual turbulence below 5000 ft", "Wet runway" },
            },
            {
                startMin  = 570,           -- 9h30m — overcast
                name      = "OVERCAST",
                category  = "MVFR",
                windDesc  = "Northerly 8-14 kts, steady",
                cloudDesc = "Broken cumulus, base 5900 ft, clearing patches",
                visDesc   = "20-40 km, good",
                hazards   = {},
            },
            {
                startMin  = 720,           -- 12h00m — back to clear, cycle resets
                name      = "CLEAR",
                category  = "VFR",
                windDesc  = "North-Northeasterly light, 4-8 kts",
                cloudDesc = "Few cumulus 7200 ft, CAVOK",
                visDesc   = "50+ km",
                hazards   = {},
            },
        },
    },

    -- ── Preset 2 ── Mediterranean Summer ───────────────────────────────────
    {
        name = "MEDITERRANEAN SUMMER",
        desc = "Fine flying day — thermal cumulus mid-afternoon, otherwise CAVOK throughout",
        stages = {
            {
                startMin  = 0,             -- 0h00m
                name      = "CLEAR",
                category  = "VFR",
                windDesc  = "Light northwesterly sea breeze 5-8 kts",
                cloudDesc = "Clear sky, haze layer above 8000 ft",
                visDesc   = "40-50 km, slight horizon haze",
                hazards   = {},
            },
            {
                startMin  = 150,           -- 2h30m — solar heating, thermals
                name      = "THERMAL CUMULUS",
                category  = "VFR",
                windDesc  = "Southwesterly 8-12 kts, variable over ridgelines",
                cloudDesc = "Scattered fair-weather cumulus, tops 8000 ft, base 4500 ft",
                visDesc   = "30-40 km, haze in valleys",
                hazards   = { "Thermic turbulence below 10 000 ft over terrain and ridges" },
            },
            {
                startMin  = 360,           -- 6h00m — thermals dying, hazy afternoon
                name      = "AFTERNOON HAZE",
                category  = "VFR",
                windDesc  = "Light and variable 4-6 kts, sea breeze decaying",
                cloudDesc = "Cumulus dissipating, few remaining, tops subsiding to 5000 ft",
                visDesc   = "20-30 km, afternoon haze",
                hazards   = {},
            },
            {
                startMin  = 540,           -- 9h00m — clear evening
                name      = "CLEAR",
                category  = "VFR",
                windDesc  = "Calm to light northerly 2-5 kts",
                cloudDesc = "Clear, no significant cloud, excellent night sky",
                visDesc   = "50+ km, exceptional",
                hazards   = {},
            },
            {
                startMin  = 720,           -- 12h00m — cycle resets to new day
                name      = "CLEAR",
                category  = "VFR",
                windDesc  = "Light northwesterly sea breeze resuming, 5-8 kts",
                cloudDesc = "Clear sky at dawn, another fine day beginning",
                visDesc   = "40-50 km",
                hazards   = {},
            },
        },
    },

    -- ── Preset 3 ── Persistent Overcast ────────────────────────────────────
    {
        name = "PERSISTENT OVERCAST",
        desc = "Low pressure system overhead — IFR conditions throughout with brief mid-day improvement",
        stages = {
            {
                startMin  = 0,             -- 0h00m
                name      = "OVERCAST",
                category  = "IFR",
                windDesc  = "Southeasterly 12-18 kts, persistent",
                cloudDesc = "Overcast stratus OVC015, ceiling 1500-2000 ft, drizzle patches",
                visDesc   = "5-10 km in drizzle and low cloud",
                hazards   = {
                    "Ceiling below IFR minima at several airfields",
                    "Drizzle reducing visibility on approach",
                },
            },
            {
                startMin  = 120,           -- 2h00m — brief lull
                name      = "BRIEF CLEARING",
                category  = "MVFR",
                windDesc  = "Southeasterly 10-15 kts, slight lull in system",
                cloudDesc = "Broken layer, base lifting temporarily to 3500 ft, gaps forming",
                visDesc   = "10-20 km, improving temporarily",
                hazards   = { "Expect conditions to close back down within 2 hours" },
            },
            {
                startMin  = 270,           -- 4h30m — closes back in
                name      = "OVERCAST",
                category  = "IFR",
                windDesc  = "Easterly 15-20 kts, system strengthening",
                cloudDesc = "Overcast OVC012, ceiling dropping to 1200-1800 ft, drizzle continuous",
                visDesc   = "3-8 km, persistent low cloud and drizzle",
                hazards   = {
                    "Ceiling at or below approach minima",
                    "Drizzle: runway wet, braking action reduced",
                },
            },
            {
                startMin  = 450,           -- 7h30m — system peak
                name      = "LOW STRATUS",
                category  = "LIFR",
                windDesc  = "Easterly 18-25 kts, gusts to 30 kts",
                cloudDesc = "Overcast OVC002, ceiling 200-400 ft, patches of radiation fog",
                visDesc   = "< 2 km, intermittent fog and drizzle",
                hazards   = {
                    "ALL OPERATIONS SUSPENDED — ceiling below minimums",
                    "Fog patches reducing visibility to near-zero",
                    "Wind gusts 30 kts on approach and rollout",
                },
            },
            {
                startMin  = 570,           -- 9h30m — system edging east
                name      = "LIFTING",
                category  = "IFR",
                windDesc  = "NE backing to N, 12-18 kts, system edging east",
                cloudDesc = "Ceiling lifting to 1500-2500 ft, drizzle easing",
                visDesc   = "5-12 km, improving slowly",
                hazards   = { "Residual low cloud patches", "Wet runway" },
            },
            {
                startMin  = 720,           -- 12h00m — system returning
                name      = "OVERCAST",
                category  = "IFR",
                windDesc  = "Southeasterly 12-18 kts, system wrapping back",
                cloudDesc = "Overcast returning, ceiling 1500-2000 ft",
                visDesc   = "5-10 km",
                hazards   = { "Ceiling below IFR minima at several airfields" },
            },
        },
    },

    -- ── Preset 4 ── Morning Fog ─────────────────────────────────────────────
    {
        name = "MORNING FOG",
        desc = "Dense radiation fog at mission start, burns off to clear afternoon, fog reforms overnight",
        stages = {
            {
                startMin  = 0,             -- 0h00m — ground fog
                name      = "DENSE FOG",
                category  = "LIFR",
                windDesc  = "Calm, near-zero surface wind",
                cloudDesc = "Radiation fog OVC000, tops 600 ft, ground obscured",
                visDesc   = "Under 200 m in places, RVR restricted",
                hazards   = {
                    "TAKEOFF AND LANDING SUSPENDED — visibility below minimums",
                    "Taxiing hazard — all taxi lights on, follow marshaller",
                    "Fog expected to lift by +90 minutes mission time",
                },
            },
            {
                startMin  = 90,            -- 1h30m — burning off
                name      = "FOG LIFTING",
                category  = "IFR",
                windDesc  = "Light northerly 3-5 kts developing as surface warms",
                cloudDesc = "Fog layer lifting, broken 400-800 ft, base rising steadily",
                visDesc   = "500 m to 2 km, variable",
                hazards   = {
                    "Patchy fog still present in low ground and valleys",
                    "Cat I ILS precision approach only",
                },
            },
            {
                startMin  = 180,           -- 3h00m — broken low cloud
                name      = "SCATTERED LOW",
                category  = "MVFR",
                windDesc  = "Northerly 6-10 kts, fog dispersing in sunshine",
                cloudDesc = "Scattered 1200-1800 ft, fog patches clearing rapidly",
                visDesc   = "5-15 km, improving steadily",
                hazards   = {},
            },
            {
                startMin  = 300,           -- 5h00m — fully clear
                name      = "CLEAR",
                category  = "VFR",
                windDesc  = "Northwesterly thermal breeze 8-12 kts",
                cloudDesc = "Clear to few cumulus, all fog gone, excellent visibility",
                visDesc   = "40-50 km, excellent",
                hazards   = {},
            },
            {
                startMin  = 480,           -- 8h00m — pleasant afternoon
                name      = "AFTERNOON FAIR",
                category  = "VFR",
                windDesc  = "Westerly sea breeze 10-14 kts",
                cloudDesc = "Few fair-weather cumulus 4000-6000 ft, no significant cloud",
                visDesc   = "30-40 km, slight afternoon haze",
                hazards   = {},
            },
            {
                startMin  = 720,           -- 12h00m — fog reforming overnight
                name      = "DENSE FOG",
                category  = "LIFR",
                windDesc  = "Calm, surface wind near zero, radiation fog reforming",
                cloudDesc = "Overnight radiation fog, OVC000, tops 500 ft",
                visDesc   = "Under 200 m, radiation fog",
                hazards   = {
                    "TAKEOFF AND LANDING SUSPENDED — visibility below minimums",
                    "Fog expected to lift after dawn",
                },
            },
        },
    },

    -- ── Preset 5 ── Rapid Squall Line ──────────────────────────────────────
    {
        name = "RAPID SQUALL LINE",
        desc = "Fast-moving squall line — violent but brief, followed by exceptional post-squall clarity",
        stages = {
            {
                startMin  = 0,             -- 0h00m — deceptively clear
                name      = "CLEAR",
                category  = "VFR",
                windDesc  = "Southwesterly 8-12 kts, conditions deceptively pleasant",
                cloudDesc = "Scattered cumulus 4000 ft, anvil clouds visible on western horizon",
                visDesc   = "30-40 km, haze to the west",
                hazards   = { "Squall line approaching from west — expect rapid deterioration within 1 hour" },
            },
            {
                startMin  = 60,            -- 1h00m — rapid deterioration
                name      = "SQUALL APPROACH",
                category  = "MVFR",
                windDesc  = "SSW 20-28 kts, windshear on climb-out",
                cloudDesc = "Rapidly developing Cb, broken to overcast, base descending",
                visDesc   = "8-15 km, lowering rapidly",
                hazards   = {
                    "Squall line IMMINENT — 30 minutes to impact",
                    "All rotary wing: land immediately",
                    "Windshear on approach and departure",
                },
            },
            {
                startMin  = 150,           -- 2h30m — squall hits
                name      = "SQUALL",
                category  = "IFR",
                windDesc  = "Westerly 30-45 kts, violent gusts",
                cloudDesc = "Overcast OVC004, torrential rain, embedded Cb with lightning",
                visDesc   = "< 1 km in heavy rain, nil in squall core",
                hazards   = {
                    "EXTREME TURBULENCE AND SHEAR — all flight operations ceased",
                    "Gusts to 45+ kts — all aircraft chocked, tied down or hangared",
                    "Heavy rain: flash flooding possible on base",
                    "Lightning: avoid all exposed high ground and structures",
                },
            },
            {
                startMin  = 240,           -- 4h00m — fast clearing post-squall
                name      = "POST-SQUALL CLEARING",
                category  = "VFR",
                windDesc  = "Northwesterly 18-24 kts, gusty but rapidly decreasing",
                cloudDesc = "Rapidly clearing — cumulus remnants, base rising to 5000 ft",
                visDesc   = "20-35 km, dramatic clarity after squall",
                hazards   = { "Gusty crosswinds on approach", "Pooled water on runways" },
            },
            {
                startMin  = 360,           -- 6h00m — settled, exceptional vis
                name      = "CLEAR",
                category  = "VFR",
                windDesc  = "Northerly 10-14 kts, settled and pleasant",
                cloudDesc = "Few high cirrus only, no significant cloud below 15 000 ft",
                visDesc   = "50+ km, exceptional post-squall visibility",
                hazards   = {},
            },
            {
                startMin  = 720,           -- 12h00m — next system approaching
                name      = "CLEAR",
                category  = "VFR",
                windDesc  = "Southwesterly 8-12 kts, next system approaching from west",
                cloudDesc = "Scattered cumulus, fresh anvil on western horizon",
                visDesc   = "30-40 km, haze to the west",
                hazards   = { "Another squall line approaching — pattern repeating" },
            },
        },
    },

    -- ── Preset 6 ── Khamsin Dust Storm ─────────────────────────────────────
    {
        name = "KHAMSIN DUST STORM",
        desc = "Hot dry southerly wind drawing desert dust across Syria — severe visibility reduction through the day",
        stages = {
            {
                startMin  = 0,             -- 0h00m — clear but hazy horizon
                name      = "DUST HAZE",
                category  = "VFR",
                windDesc  = "Southeasterly 12-18 kts, hot, very dry, sand in suspension",
                cloudDesc = "Clear sky, upper-level dust haze above 6000 ft, brownish horizon",
                visDesc   = "20-35 km, deteriorating through the day",
                hazards   = {
                    "Khamsin wind developing — dust loading will increase significantly",
                    "Engines: watch ITT — fine desert dust abrasive to compressor blades",
                },
            },
            {
                startMin  = 90,            -- 1h30m — dust wall approaching
                name      = "DUST BUILDING",
                category  = "MVFR",
                windDesc  = "Southerly 20-28 kts, gusting, howling dust",
                cloudDesc = "Dust wall on southern horizon, sky progressively obscured, tan/orange tint",
                visDesc   = "5-12 km and lowering sharply",
                hazards   = {
                    "Dust storm IMMINENT — RVR degrading rapidly",
                    "All rotary wing: land and cover air intakes NOW",
                    "Windscreen scouring on landing roll",
                },
            },
            {
                startMin  = 210,           -- 3h30m — full haboob
                name      = "DUST STORM",
                category  = "LIFR",
                windDesc  = "Southerly 25-35 kts, sustained, particles to 10 000 ft AGL",
                cloudDesc = "Sky completely obscured by dust and sand, visibility near zero, eerie orange light",
                visDesc   = "Under 500 m, nil in core of storm",
                hazards   = {
                    "ALL OPERATIONS SUSPENDED",
                    "Severe FOD risk — all aircraft shut down and canopies sealed",
                    "Static discharge hazard — ground all aircraft",
                    "Engine start prohibited until storm passes",
                },
            },
            {
                startMin  = 360,           -- 6h00m — dust settling
                name      = "DUST SETTLING",
                category  = "IFR",
                windDesc  = "Southerly decreasing 15-20 kts, dust fall-out continuing",
                cloudDesc = "Dust layer thinning, milky sky, diffuse sun visible",
                visDesc   = "2-6 km, dust fall-out reducing slowly",
                hazards   = {
                    "Dust still at 8000+ ft — FOD risk remains for turbine aircraft",
                    "Runways and taxiways: fine sand accumulation, check before rolling",
                },
            },
            {
                startMin  = 510,           -- 8h30m — clearing
                name      = "HAZY",
                category  = "VFR",
                windDesc  = "Light southwesterly 8-12 kts, system weakening",
                cloudDesc = "Dust residual haze, sky pale yellow-brown, sun visible but hazy",
                visDesc   = "10-20 km, residual dust haze",
                hazards   = { "Engine compressor wash recommended before restarting turbines" },
            },
            {
                startMin  = 720,           -- 12h00m — next cycle
                name      = "DUST HAZE",
                category  = "VFR",
                windDesc  = "Southeasterly 12-18 kts, heat building for second wave",
                cloudDesc = "Brownish horizon, dust already rebuilding in the south",
                visDesc   = "20-30 km, haze layer returning",
                hazards   = { "Another dust episode likely within 6 hours" },
            },
        },
    },

    -- ── Preset 7 ── Cyprus Low ──────────────────────────────────────────────
    {
        name = "CYPRUS LOW",
        desc = "Mediterranean cyclone centred near Cyprus — organised frontal rain bands rotate through with strong SE-SW winds",
        stages = {
            {
                startMin  = 0,             -- 0h00m — pre-frontal overcast
                name      = "OVERCAST",
                category  = "IFR",
                windDesc  = "Southeasterly 15-22 kts, swell on coast, pre-frontal cloud thickening",
                cloudDesc = "Overcast nimbostratus, ceiling 1500-2500 ft, continuous drizzle",
                visDesc   = "5-10 km, drizzle and low cloud",
                hazards   = { "Ceiling at or near IFR minima", "Drizzle: wet runway" },
            },
            {
                startMin  = 120,           -- 2h00m — first rain band
                name      = "RAIN BAND",
                category  = "IFR",
                windDesc  = "SSE 20-28 kts backing to SE, first frontal band overhead",
                cloudDesc = "Overcast 800-1200 ft, moderate to heavy rain, embedded CB",
                visDesc   = "2-5 km in rain",
                hazards   = {
                    "Moderate to severe turbulence in rain bands",
                    "Heavy rain: engine anti-ice ON",
                    "Wind rapidly backing — approach heading correction required",
                },
            },
            {
                startMin  = 240,           -- 4h00m — brief lull between bands
                name      = "INTER-BAND LULL",
                category  = "MVFR",
                windDesc  = "Easterly 12-16 kts, temporary lull as system reorganises",
                cloudDesc = "Broken nimbostratus, ceiling lifting slightly to 2000 ft, drizzle only",
                visDesc   = "8-15 km, improving briefly",
                hazards   = { "Next rain band expected within 90 minutes" },
            },
            {
                startMin  = 360,           -- 6h00m — second rain band
                name      = "RAIN BAND",
                category  = "IFR",
                windDesc  = "Easterly veering to NE 18-26 kts, cyclone centre closest",
                cloudDesc = "Overcast 600-1000 ft, heavy rain bands, CB in warm sector",
                visDesc   = "2-4 km in heavy rain",
                hazards   = {
                    "Heavy turbulence — avoid penetration above 15 000 ft",
                    "Heavy precipitation causing radar and comms interference",
                    "Lightning, hail possible in embedded CB",
                },
            },
            {
                startMin  = 480,           -- 8h00m — post-frontal clearing
                name      = "CLEARING",
                category  = "MVFR",
                windDesc  = "NW 20-25 kts, post-frontal cold air advection, gusts 32 kts",
                cloudDesc = "Broken convective cumulus, rapidly lifting base 3000-5000 ft, showers",
                visDesc   = "10-20 km, showers reducing",
                hazards   = { "Gusty NW crosswinds on landing", "Scattered shower cells moving fast" },
            },
            {
                startMin  = 720,           -- 12h00m — cold and clear
                name      = "CLEAR",
                category  = "VFR",
                windDesc  = "Northwesterly 15-20 kts, cold and blustery",
                cloudDesc = "Few post-frontal cumulus, base 4000 ft, excellent clarity",
                visDesc   = "40-50 km, exceptional post-frontal visibility",
                hazards   = { "Strong crosswind component NW — check runway in use" },
            },
        },
    },

    -- ── Preset 8 ── Winter Cold Front ──────────────────────────────────────
    {
        name = "WINTER COLD FRONT",
        desc = "Classic vigorous cold front — warm humid pre-frontal sector, violent frontal zone, cold bright post-frontal air",
        stages = {
            {
                startMin  = 0,             -- 0h00m — warm sector, humid and grey
                name      = "WARM SECTOR",
                category  = "MVFR",
                windDesc  = "South-Southwesterly 15-20 kts, warm and humid, mild for season",
                cloudDesc = "Stratus and stratocumulus broken, ceiling 2500-3500 ft, intermittent light rain",
                visDesc   = "10-20 km, haze and light rain reducing",
                hazards   = { "Low-level wind shear between warm sector and cold air mass below ridgelines" },
            },
            {
                startMin  = 90,            -- 1h30m — cold front approaching
                name      = "PRE-FRONTAL",
                category  = "IFR",
                windDesc  = "SSW veering SW rapidly 22-30 kts, pressure falling fast",
                cloudDesc = "Cumulonimbus line on western horizon, overcast OVC008, heavy rain beginning",
                visDesc   = "3-8 km in heavy rain",
                hazards   = {
                    "Cold front IMMINENT — violent weather within 30 minutes",
                    "Rapid wind shift SW to NW at frontal passage",
                    "Pressure drop: altimeter check before departure",
                },
            },
            {
                startMin  = 180,           -- 3h00m — frontal zone
                name      = "FRONTAL ZONE",
                category  = "LIFR",
                windDesc  = "SW 30-40 kts veering violently NW at passage, gusts 50 kts",
                cloudDesc = "Dense Cb wall, overcast OVC004, torrential rain, hail possible",
                visDesc   = "< 1 km in heavy rain and hail",
                hazards   = {
                    "EXTREME TURBULENCE — all flight operations suspended",
                    "Hail risk: all aircraft in hardened shelter",
                    "Wind shift 90° at frontal passage — imminent runway change required",
                    "Icing: severe in cloud between 5000-18 000 ft",
                },
            },
            {
                startMin  = 270,           -- 4h30m — immediate post-frontal
                name      = "POST-FRONTAL",
                category  = "VFR",
                windDesc  = "Northwesterly 25-35 kts, cold, vigorous, gusty",
                cloudDesc = "Rapidly clearing — large cumulus 3000-5000 ft, sharp edges, crystal blue sky",
                visDesc   = "30-50 km, spectacular post-frontal clarity",
                hazards   = {
                    "Strong NW crosswind — check runway in use has changed",
                    "Turbulence in and below cold CB cells",
                    "Runway contamination: water and hail debris — FOD check",
                },
            },
            {
                startMin  = 450,           -- 7h30m — cold air settles
                name      = "COLD CLEAR",
                category  = "VFR",
                windDesc  = "Northwesterly 18-22 kts, decreasing slowly, cold air mass",
                cloudDesc = "Scattered to few cumulus, base 4500 ft, excellent visibility",
                visDesc   = "40-50 km, cold and clear",
                hazards   = {},
            },
            {
                startMin  = 720,           -- 12h00m — settled cold and bright
                name      = "CLEAR",
                category  = "VFR",
                windDesc  = "Northerly 12-16 kts, cold, stable",
                cloudDesc = "Few cumulus 5000 ft, CAVOK conditions",
                visDesc   = "50+ km, exceptional",
                hazards   = {},
            },
        },
    },

    -- ── Preset 9 ── Shamal Northerly ───────────────────────────────────────
    {
        name = "SHAMAL NORTHERLY",
        desc = "Strong post-frontal northerly (Shamal) — clear, cold, and very gusty; excellent visibility but challenging crosswinds all day",
        stages = {
            {
                startMin  = 0,             -- 0h00m — strong northerly established
                name      = "STRONG NORTH",
                category  = "VFR",
                windDesc  = "Northerly 25-32 kts, gusts to 40 kts on exposed ridgelines",
                cloudDesc = "Cloudless — cold advection inhibiting convection entirely",
                visDesc   = "50+ km, excellent desert air clarity",
                hazards   = {
                    "Strong crosswind component — check runway in use",
                    "Low-level turbulence and windshear over ridgelines",
                    "Rotor wash severe — helicopter spacing increased to 3 rotors",
                },
            },
            {
                startMin  = 150,           -- 2h30m — peak gusts
                name      = "GUSTY NORTH",
                category  = "VFR",
                windDesc  = "Northerly 28-36 kts, gusts 45 kts, strongest period of the day",
                cloudDesc = "Clear, no cloud, some blowing dust at low levels over open desert",
                visDesc   = "40-50 km, blowing dust on surface reducing near-ground vis in desert",
                hazards   = {
                    "Gusts 45 kts — maximum crosswind exceeded for some aircraft types",
                    "Blowing dust below 500 ft AGL over open ground — NVG degraded",
                    "Low-level windshear on all runways",
                },
            },
            {
                startMin  = 330,           -- 5h30m — moderating slightly
                name      = "NORTH WIND",
                category  = "VFR",
                windDesc  = "Northerly 20-28 kts, gusts 36 kts, Shamal beginning to ease",
                cloudDesc = "Clear sky, no cloud development, cold and dry air mass",
                visDesc   = "50+ km",
                hazards   = { "Gusts still operationally significant — crosswind check required" },
            },
            {
                startMin  = 480,           -- 8h00m — easing
                name      = "BREEZY CLEAR",
                category  = "VFR",
                windDesc  = "NNW 15-20 kts, decreasing through the afternoon",
                cloudDesc = "Completely clear, few wisps of high cirrus, superb visibility",
                visDesc   = "50+ km, unlimited",
                hazards   = {},
            },
            {
                startMin  = 600,           -- 10h00m — evening calm
                name      = "CLEAR",
                category  = "VFR",
                windDesc  = "Light northerly 8-12 kts, Shamal finally relaxing",
                cloudDesc = "Clear and cold, stars brilliant overhead",
                visDesc   = "50+ km",
                hazards   = {},
            },
            {
                startMin  = 720,           -- 12h00m — new Shamal cycle
                name      = "STRONG NORTH",
                category  = "VFR",
                windDesc  = "Northerly 22-30 kts, fresh Shamal pulse overnight",
                cloudDesc = "Clear, cold, dusty at low level again",
                visDesc   = "40-50 km",
                hazards   = { "Shamal wind re-strengthening — crosswind check required" },
            },
        },
    },

    -- ── Preset 10 ── Explosive Convection ──────────────────────────────────
    {
        name = "EXPLOSIVE CONVECTION",
        desc = "Deceptively calm VFR morning, then violent afternoon convective towers develop with zero notice — classic unstable hot-season day",
        stages = {
            {
                startMin  = 0,             -- 0h00m — beautiful morning
                name      = "CLEAR",
                category  = "VFR",
                windDesc  = "Light and variable 2-5 kts, calm and deceptively pleasant",
                cloudDesc = "Clear, few high cirrus, nothing threatening, ideal flying conditions",
                visDesc   = "50+ km, CAVOK",
                hazards   = {
                    "Forecaster WARNING: upper atmosphere extremely unstable — explosive CB development expected after 3h00m",
                },
            },
            {
                startMin  = 150,           -- 2h30m — surface heating, thermals
                name      = "CUMULUS FORMING",
                category  = "VFR",
                windDesc  = "SSW 6-10 kts, thermally driven, increasing",
                cloudDesc = "Fair-weather cumulus erupting rapidly, tops building through 8000 ft",
                visDesc   = "30-40 km, some valley haze",
                hazards   = { "Thermic turbulence below 10 000 ft — pronounced over terrain" },
            },
            {
                startMin  = 240,           -- 4h00m — towering cumulus
                name      = "TOWERING CUMULUS",
                category  = "MVFR",
                windDesc  = "Southwesterly 12-18 kts, convergence zones triggering towers",
                cloudDesc = "Towering Cb erupting to 30 000+ ft in 15 minutes, scattered coverage rapidly increasing",
                visDesc   = "15-25 km outside cells, nil under cells",
                hazards   = {
                    "Severe turbulence in, around and below Cb cells",
                    "Tops above service ceiling of most aircraft — DO NOT attempt to top",
                    "Large hail possible — avoid all Cb cells by minimum 10 nm",
                    "Lightning: avoid all cloud",
                },
            },
            {
                startMin  = 360,           -- 6h00m — full outbreak
                name      = "SEVERE CB",
                category  = "LIFR",
                windDesc  = "Variable, outflow gusts 35-50 kts from individual cells, no predictable direction",
                cloudDesc = "Multiple severe Cb clusters, anvils spreading, sporadic heavy rain, hail, lightning",
                visDesc   = "Under 1 km under cells, 10-20 km between cells",
                hazards   = {
                    "Extreme turbulence throughout area — all flight suspended",
                    "Hail up to golf-ball size reported",
                    "Lightning: multiple simultaneous ground strikes on airfield perimeter",
                    "Flash flooding: dispersals and taxiways flooding rapidly",
                    "Microburst risk on approach — all arrivals diverted",
                },
            },
            {
                startMin  = 510,           -- 8h30m — convection collapses
                name      = "CLEARING",
                category  = "VFR",
                windDesc  = "Northerly 12-16 kts, post-convective outflow, gusty and damp",
                cloudDesc = "Cb clusters decaying, anvils shearing off, base lifting to 5000 ft",
                visDesc   = "20-35 km after cells pass",
                hazards   = {
                    "FOD check: hail and debris on runways",
                    "Isolated late-day cells still possible until 10h00m",
                },
            },
            {
                startMin  = 720,           -- 12h00m — next morning clear
                name      = "CLEAR",
                category  = "VFR",
                windDesc  = "Light variable 3-6 kts, calm overnight",
                cloudDesc = "Clear and still, anvil remnants dissipating on horizon",
                visDesc   = "50+ km, excellent overnight",
                hazards   = { "Another extreme convective day forecast for tomorrow" },
            },
        },
    },

    -- ── Preset 11 ── Coastal Stratus ───────────────────────────────────────
    {
        name = "COASTAL STRATUS",
        desc = "Sea-surface temperature inversion traps stratus onshore — coastal airfields IFR while inland Syria remains clear",
        stages = {
            {
                startMin  = 0,             -- 0h00m — dense coastal stratus
                name      = "COASTAL STRATUS",
                category  = "IFR",
                windDesc  = "Westerly onshore 8-12 kts, moist marine air advection",
                cloudDesc = "Stratus OVC003-OVC006, tops 1500 ft, coastal airfields in cloud, grey diffuse light",
                visDesc   = "2-5 km in mist and stratus on coast, 30+ km inland",
                hazards   = {
                    "Coastal airfields: at or below IFR minima",
                    "Inland rebasefields (Damascus, Palmyra): clear and suitable for divert",
                    "Visual approach NOT available coastal — precision ILS only",
                },
            },
            {
                startMin  = 120,           -- 2h00m — slow burn-off attempt
                name      = "STRATUS THINNING",
                category  = "MVFR",
                windDesc  = "WSW 8-12 kts, solar heating beginning to erode cloud top",
                cloudDesc = "Stratus thinning to broken BKN008, greying lighter but still diffuse",
                visDesc   = "5-10 km in residual mist",
                hazards   = { "Burn-off may stall — do not plan VFR coastal operations before +3h00m" },
            },
            {
                startMin  = 240,           -- 4h00m — coastal stratus breaks
                name      = "BROKEN CLOUD",
                category  = "MVFR",
                windDesc  = "W-WNW 10-14 kts, sea breeze strengthening, cloud breaking up",
                cloudDesc = "Broken cumulus 1500-2500 ft, burns off to scattered by mid-morning",
                visDesc   = "10-20 km improving",
                hazards   = {},
            },
            {
                startMin  = 360,           -- 6h00m — fine afternoon
                name      = "CLEAR",
                category  = "VFR",
                windDesc  = "WNW sea breeze 12-16 kts, pleasant and warm",
                cloudDesc = "Few cumulus 3000-4000 ft, coastal stratus entirely gone",
                visDesc   = "30-40 km, light marine haze",
                hazards   = {},
            },
            {
                startMin  = 540,           -- 9h00m — sea breeze dying, mist returning
                name      = "HAZY",
                category  = "VFR",
                windDesc  = "Light westerly 5-8 kts, sea breeze dying at dusk",
                cloudDesc = "Scattered low cloud reforming on coast, inland clear",
                visDesc   = "15-25 km coast, 40+ km inland",
                hazards   = { "Stratus expected to close coastal airfields again overnight" },
            },
            {
                startMin  = 720,           -- 12h00m — stratus back
                name      = "COASTAL STRATUS",
                category  = "IFR",
                windDesc  = "Westerly 8-12 kts, overnight marine stratus re-established",
                cloudDesc = "Stratus OVC003-OVC006, back to coastal IFR overnight and morning",
                visDesc   = "2-5 km on coast, 30+ km inland",
                hazards   = {
                    "Coastal airfields: IFR — precision approach only",
                    "Inland bases: clear and VMC",
                },
            },
        },
    },

    -- ── Preset 12 ── Warm Front Approach ───────────────────────────────────
    {
        name = "WARM FRONT APPROACH",
        desc = "Slow-moving warm front advancing from the SW — textbook high-to-low cloud sequence over 12 hours, ending in persistent rain",
        stages = {
            {
                startMin  = 0,             -- 0h00m — high cirrus forerunner
                name      = "HIGH CIRRUS",
                category  = "VFR",
                windDesc  = "Southwesterly 8-12 kts, light and warm — warm sector air arriving",
                cloudDesc = "Mare's tail cirrus spreading from SW, tops only, clear below 20 000 ft",
                visDesc   = "40-50 km, excellent, upper halo around sun",
                hazards   = { "Warm front 400-500 km to SW — conditions deteriorate over next 6-8 hours" },
            },
            {
                startMin  = 120,           -- 2h00m — cirrostratus
                name      = "CIRROSTRATUS",
                category  = "VFR",
                windDesc  = "Southwesterly 10-15 kts, increasing slowly, sky milky",
                cloudDesc = "Cirrostratus covering 6-7 oktas, sun halo visible, sky lightening to white",
                visDesc   = "30-40 km, diffuse hazy light",
                hazards   = {},
            },
            {
                startMin  = 240,           -- 4h00m — altostratus thickening
                name      = "ALTOSTRATUS",
                category  = "VFR",
                windDesc  = "Southerly 15-20 kts, backing slightly, cloud base lowering",
                cloudDesc = "Altostratus overcast, base 8000-12 000 ft, sun seen as through frosted glass",
                visDesc   = "20-30 km, thickening overcast",
                hazards   = { "Icing in cloud above 8000 ft and rising — anti-ice recommended above FL080" },
            },
            {
                startMin  = 390,           -- 6h30m — nimbostratus, rain starts
                name      = "NIMBOSTRATUS",
                category  = "IFR",
                windDesc  = "Southerly 18-24 kts, front approaching, pressure falling steadily",
                cloudDesc = "Nimbostratus overcast, ceiling 2000-3000 ft, continuous light to moderate rain",
                visDesc   = "5-10 km in rain",
                hazards   = {
                    "Ceiling lowering steadily — plan departure before +7h00m or wait for passage",
                    "Rain: anti-ice on, braking action on wet runway reduced",
                },
            },
            {
                startMin  = 540,           -- 9h00m — frontal rain belt
                name      = "FRONTAL RAIN",
                category  = "IFR",
                windDesc  = "SSE 20-28 kts, backing — frontal zone overhead",
                cloudDesc = "Overcast OVC008, continuous moderate rain, ceiling 800-1500 ft",
                visDesc   = "3-6 km in moderate rain",
                hazards   = {
                    "Ceiling below IFR minima at unequipped airfields",
                    "Persistent rain: wet runway all surfaces, pooling possible",
                    "Wind backing SSE — approach heading correction required",
                },
            },
            {
                startMin  = 720,           -- 12h00m — front stalls, persistent rain
                name      = "OVERCAST",
                category  = "IFR",
                windDesc  = "Southerly 15-20 kts, front stalling overhead",
                cloudDesc = "Overcast 1000-1800 ft, persistent light to moderate rain, no clearing expected soon",
                visDesc   = "5-8 km, persistent rain",
                hazards   = {
                    "Front stalled — deterioration expected to continue through 24h",
                    "Instrument approaches only at coastal airfields",
                },
            },
        },
    },

    -- ── Preset 13 ── Post-Frontal Polar Clarity ────────────────────────────
    {
        name = "POST-FRONTAL POLAR CLARITY",
        desc = "Exceptional winter VFR day — cold dry polar air mass, flawless visibility, isolated shower cells only hazard",
        stages = {
            {
                startMin  = 0,             -- 0h00m — cold but crystal clear
                name      = "CLEAR",
                category  = "VFR",
                windDesc  = "North-Northwesterly 18-22 kts, cold polar air, sharp and clear",
                cloudDesc = "Scattered large cumulus, base 4500-6000 ft, crisp sharp-edged cloud",
                visDesc   = "50+ km, outstanding — distant mountains visible from 100 nm",
                hazards   = { "Cold soak: engine warm-up required, aircraft de-icing check" },
            },
            {
                startMin  = 120,           -- 2h00m — isolated shower cells
                name      = "CONVECTIVE SHOWERS",
                category  = "VFR",
                windDesc  = "NW 20-25 kts, cold instability driving scattered shower cells",
                cloudDesc = "Scattered Cb showers, bases 3500 ft, tops to 15 000 ft, moving fast NW-SE",
                visDesc   = "30-40 km between cells, under 1 km in cells",
                hazards   = {
                    "Isolated shower cells moving at 25+ kts — short but intense",
                    "Hail possible in shower cells — avoid by 5 nm",
                    "Cold soak icing on airframe after passing through showers",
                },
            },
            {
                startMin  = 270,           -- 4h30m — showers easing
                name      = "CLEAR",
                category  = "VFR",
                windDesc  = "NW 15-20 kts, instability decreasing as surface warms",
                cloudDesc = "Cumulus softening and spreading, fewer cells, excellent between",
                visDesc   = "40-50 km, superb",
                hazards   = {},
            },
            {
                startMin  = 450,           -- 7h30m — settled cold afternoon
                name      = "CLEAR",
                category  = "VFR",
                windDesc  = "NNW 10-15 kts, decreasing, crisp and cold",
                cloudDesc = "Few cumulus 5000 ft, mostly clear, late afternoon sunshine sharp",
                visDesc   = "50+ km, unlimited",
                hazards   = {},
            },
            {
                startMin  = 600,           -- 10h00m — radiative cooling
                name      = "CLEAR",
                category  = "VFR",
                windDesc  = "Light northerly 6-10 kts, calm evening",
                cloudDesc = "Clear, starfield brilliant, radiative cooling beginning",
                visDesc   = "50+ km, exceptional night visibility",
                hazards   = { "Temperature dropping rapidly — frost forming on exposed surfaces" },
            },
            {
                startMin  = 720,           -- 12h00m
                name      = "CLEAR",
                category  = "VFR",
                windDesc  = "NW 12-16 kts, another cold fresh day beginning",
                cloudDesc = "Scattered cumulus 5000 ft, cold polar air still in place",
                visDesc   = "50+ km",
                hazards   = {},
            },
        },
    },

    -- ── Preset 14 ── Sirocco Heat Haze ─────────────────────────────────────
    {
        name = "SIROCCO HEAT HAZE",
        desc = "Hot oppressive southerly Sirocco — no dust, but savage heat, high humidity, and severe low-level haze all day",
        stages = {
            {
                startMin  = 0,             -- 0h00m — already hot and hazy
                name      = "HEAT HAZE",
                category  = "VFR",
                windDesc  = "Southerly 10-15 kts, hot and humid, dew point unusually high for region",
                cloudDesc = "Clear sky above, but severe heat shimmer from 0-3000 ft, milky horizon",
                visDesc   = "15-25 km, severe low-level mirage and shimmer",
                hazards   = {
                    "Heat shimmer: horizon and runway surface appear wavy — depth perception degraded",
                    "Density altitude 2000-3000 ft above field elevation — performance charts CRITICAL",
                },
            },
            {
                startMin  = 120,           -- 2h00m — hottest period
                name      = "EXTREME HEAT",
                category  = "VFR",
                windDesc  = "Southerly 12-18 kts, oven-hot blast, sand/surface temperature 55°C",
                cloudDesc = "Clear sky, thick thermal haze 0-5000 ft, refraction rendering horizon indistinct",
                visDesc   = "10-20 km, severe heat haze, distant objects appear to float",
                hazards   = {
                    "Density altitude CRITICAL — some aircraft types: max performance take-off only",
                    "Ground crew heat injury risk — limit exposure",
                    "Tyre pressure: check before every sortie, asphalt surface tacky",
                    "Engine oil temperature: watch closely throughout sortie",
                },
            },
            {
                startMin  = 300,           -- 5h00m — afternoon, still brutal
                name      = "HEAT HAZE",
                category  = "VFR",
                windDesc  = "Southerly 15-20 kts, peak Sirocco flow",
                cloudDesc = "Few hairline cirrus at extreme altitude only, surface shimmering violently",
                visDesc   = "10-18 km, oppressive heat haze persistent",
                hazards   = {
                    "Performance charts: use extreme heat column for all calculations",
                    "Air conditioning: max cooling required for crew survival",
                },
            },
            {
                startMin  = 480,           -- 8h00m — late afternoon, slight easing
                name      = "HAZY",
                category  = "VFR",
                windDesc  = "SSW 10-15 kts, very slight overnight cooling beginning",
                cloudDesc = "Haze layer still thick below 5000 ft, though shimmer reducing slightly",
                visDesc   = "15-25 km, some improvement as temperature dips",
                hazards   = { "Density altitude still elevated — performance check required" },
            },
            {
                startMin  = 600,           -- 10h00m — night relief
                name      = "CLEAR",
                category  = "VFR",
                windDesc  = "Light southerly 6-10 kts, temperatures dropping to merely unpleasant",
                cloudDesc = "Clear and still, haze layer collapsing with surface cooling",
                visDesc   = "25-35 km, improving markedly overnight",
                hazards   = {},
            },
            {
                startMin  = 720,           -- 12h00m — another Sirocco day
                name      = "HEAT HAZE",
                category  = "VFR",
                windDesc  = "Southerly 10-15 kts, Sirocco re-establishing at dawn",
                cloudDesc = "Clear, intense early heat already building",
                visDesc   = "15-25 km",
                hazards   = { "Another extreme heat day forecast — same density altitude restrictions apply" },
            },
        },
    },

    -- ── Preset 15 ── Winter Anticyclone ────────────────────────────────────
    {
        name = "WINTER ANTICYCLONE",
        desc = "Stable winter high pressure — cold morning fog and frost, slow afternoon improvement, inversion trapping haze all day",
        stages = {
            {
                startMin  = 0,             -- 0h00m — frost and ground fog
                name      = "MORNING FROST",
                category  = "IFR",
                windDesc  = "Calm, near-zero wind, temperature below zero at field elevation",
                cloudDesc = "Radiation fog and low stratus OVC002, frost on all surfaces, visibility nil near ground",
                visDesc   = "Under 300 m in places, patchy dense fog",
                hazards   = {
                    "Frost on all aircraft surfaces — de-icing required before flight",
                    "FOD risk: ice on taxiways, expanded/cracked pavement",
                    "Inversion at 2000 ft — above inversion, clear and bright",
                },
            },
            {
                startMin  = 90,            -- 1h30m — fog starting to lift
                name      = "FOG LIFTING",
                category  = "IFR",
                windDesc  = "Light and variable 2-5 kts, sun beginning to warm surface",
                cloudDesc = "Fog lifting to 200-400 ft, stratus BKN002-BKN005, slow improvement",
                visDesc   = "400 m to 1500 m, variable",
                hazards   = {
                    "ILS approaches only until ceiling exceeds 500 ft",
                    "Black ice risk on runways and taxiways until mid-morning",
                },
            },
            {
                startMin  = 210,           -- 3h30m — high cloud, hazy sunshine
                name      = "HAZY SUNSHINE",
                category  = "MVFR",
                windDesc  = "Light westerly 4-8 kts, weak sea breeze developing",
                cloudDesc = "Stratus and fog gone, high pressure inversion layer at 5000 ft, milky sunshine",
                visDesc   = "8-15 km in haze, capped by inversion",
                hazards   = { "Temperature inversion: strong turbulence boundary at 4000-5000 ft" },
            },
            {
                startMin  = 360,           -- 6h00m — best part of the day
                name      = "FAIR",
                category  = "VFR",
                windDesc  = "WNW 8-12 kts, pleasant light wind",
                cloudDesc = "Few thin altocumulus at inversion base, otherwise clear below",
                visDesc   = "15-25 km, limited by inversion haze but adequate for VFR",
                hazards   = {},
            },
            {
                startMin  = 510,           -- 8h30m — afternoon haze thickens
                name      = "HAZY",
                category  = "VFR",
                windDesc  = "Light southwesterly 5-8 kts, sea breeze dying at dusk",
                cloudDesc = "Altocumulus sheet thickening at inversion, light fading quickly at sunset",
                visDesc   = "10-20 km, haze thickening again as surface cools",
                hazards   = { "Inversions trapping smoke from fires and industrial — night vis worse than day" },
            },
            {
                startMin  = 720,           -- 12h00m — frost returning
                name      = "MORNING FROST",
                category  = "IFR",
                windDesc  = "Calm, overnight radiative freeze in progress",
                cloudDesc = "Radiation fog re-forming, OVC001, frost on all surfaces again",
                visDesc   = "Under 300 m in places, same pattern as morning",
                hazards   = {
                    "Aircraft de-icing required before flight",
                    "Pattern repeats daily while anticyclone persists",
                },
            },
        },
    },

}

-- Populated at mission start by random preset selection — do not edit directly.
local WEATHER_STAGES = {}

-- ═══════════════════════════════════════════════════════════════════════════
--  STATE
-- ═══════════════════════════════════════════════════════════════════════════

local State = {
    currentStageIndex = 1,
    windHistory       = {},        -- ring buffer of { speed, dir, time }
    lastAtisTime      = 0,
    cycleStartTime    = 0,         -- mission time when this full cycle started
    warningsFired     = {},        -- { [stageIndex] = true } — prevent duplicate warns
    lastFlagState     = false,
}

-- ═══════════════════════════════════════════════════════════════════════════
--  UTILITY FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════

--- Convert a wind Vec3 from atmosphere.getWind() to speed (m/s) and
--- FROM-direction (degrees, meteorological convention).
local function windVecToMet(vec)
    local speed = math.sqrt(vec.x ^ 2 + vec.z ^ 2)
    local dir   = math.deg(math.atan2(-vec.x, -vec.z)) % 360
    return speed, dir
end

--- m/s → knots
local function msToKts(ms) return ms * 1.94384 end

--- Pascals → hPa
local function paToHpa(pa) return pa / 100 end

--- Pascals → mmHg (DCS native unit)
local function paToMmhg(pa) return pa / 133.322 end

--- Pascals → inHg (for Western avionics)
local function paToInhg(pa) return pa / 3386.39 end

--- Format an angle as a zero-padded 3-digit string ("045", "270")
local function fmtHdg(deg)
    return string.format("%03d", math.floor(deg + 0.5) % 360)
end

--- Return the current WEATHER_STAGES entry based on elapsed mission time.
local function getCurrentStage(missionTimeSec)
    local elapsed = (missionTimeSec - State.cycleStartTime) / 60  -- minutes
    local stage   = WEATHER_STAGES[1]
    for i = #WEATHER_STAGES, 1, -1 do
        if elapsed >= WEATHER_STAGES[i].startMin then
            stage = WEATHER_STAGES[i]
            State.currentStageIndex = i
            break
        end
    end
    return stage
end

--- Return the NEXT stage entry (nil if this is the last before a loop-reset).
local function getNextStage()
    local next = State.currentStageIndex + 1
    if next > #WEATHER_STAGES then return nil end
    return WEATHER_STAGES[next]
end

--- Minutes until a future stage starts, from current elapsed time.
local function minsUntilStage(stageIndex, missionTimeSec)
    local elapsed = (missionTimeSec - State.cycleStartTime) / 60
    return WEATHER_STAGES[stageIndex].startMin - elapsed
end

--- Push a wind sample into the history ring buffer.
local function recordWindSample(speed, dir, mTime)
    table.insert(State.windHistory, { speed = speed, dir = dir, time = mTime })
    if #State.windHistory > CFG.WIND_HISTORY_SIZE then
        table.remove(State.windHistory, 1)
    end
end

--- Derive a plain-English wind trend string from history.
local function windTrend()
    if #State.windHistory < 3 then return "trend unavailable" end
    local oldest = State.windHistory[1]
    local newest = State.windHistory[#State.windHistory]
    local deltaSpd = newest.speed - oldest.speed

    -- Compute angular difference for direction trend
    local dDir = ((newest.dir - oldest.dir) + 360) % 360
    if dDir > 180 then dDir = dDir - 360 end  -- signed: positive = clockwise

    local trend = {}
    if math.abs(deltaSpd) < 0.5 then
        table.insert(trend, "speed steady")
    elseif deltaSpd > 0.5 then
        table.insert(trend, string.format("speed RISING +%.0f kts", msToKts(deltaSpd)))
    else
        table.insert(trend, string.format("speed falling %.0f kts", msToKts(math.abs(deltaSpd))))
    end

    if math.abs(dDir) < 5 then
        table.insert(trend, "direction steady")
    elseif dDir > 0 then
        table.insert(trend, string.format("backing %d°", math.abs(math.floor(dDir))))
    else
        table.insert(trend, string.format("veering %d°", math.abs(math.floor(dDir))))
    end

    return table.concat(trend, " | ")
end

--- Broadcast a message to the configured coalition.
local function broadcast(msg, duration)
    local dur = duration or CFG.MSG_DURATION_SHORT
    if CFG.BROADCAST_COALITION == 0 then
        trigger.action.outText(msg, dur)
    else
        trigger.action.outTextForCoalition(CFG.BROADCAST_COALITION, msg, dur)
    end
end

--- Generate a hazard warning block string.
local function fmtHazards(stage)
    if #stage.hazards == 0 then return "  NIL" end
    local lines = {}
    for _, h in ipairs(stage.hazards) do
        table.insert(lines, "  ⚠ " .. h)
    end
    return table.concat(lines, "\n")
end

-- ═══════════════════════════════════════════════════════════════════════════
--  ATIS BROADCAST
-- ═══════════════════════════════════════════════════════════════════════════

local function broadcastATIS(missionTimeSec)
    local ref   = CFG.AIRFIELD_REF
    local wind  = atmosphere.getWind({ x = ref.x, y = ref.y,           z = ref.z })
    local wind2k= atmosphere.getWind({ x = ref.x, y = ref.y + 2000,    z = ref.z })
    local wind8k= atmosphere.getWind({ x = ref.x, y = ref.y + 8000,    z = ref.z })

    local spd0, dir0   = windVecToMet(wind)
    local spd2, dir2   = windVecToMet(wind2k)
    local spd8, dir8   = windVecToMet(wind8k)

    local _, pressPa   = atmosphere.getTemperatureAndPressure({ x = ref.x, y = ref.y, z = ref.z })
    local temp, _      = atmosphere.getTemperatureAndPressure({ x = ref.x, y = ref.y, z = ref.z })

    local qnhHpa  = paToHpa(pressPa)
    local qnhInhg = paToInhg(pressPa)
    local qnhMmhg = paToMmhg(pressPa)

    recordWindSample(spd0, dir0, missionTimeSec)
    local trend = windTrend()

    local stage = getCurrentStage(missionTimeSec)

    -- Format mission time as HH:MM
    local hrs = math.floor(missionTimeSec / 3600)
    local min = math.floor((missionTimeSec % 3600) / 60)
    local timeStr = string.format("%02d:%02d", hrs, min)

    local msg = string.format(
        "══ AMERICAN VIKINGS WEATHER – %s ══\n" ..
        "STATUS: %s  [%s]\n" ..
        "\n" ..
        "SURFACE  %s° / %.0f kts\n" ..
        "2 000 m  %s° / %.0f kts\n" ..
        "8 000 m  %s° / %.0f kts\n" ..
        "TREND: %s\n" ..
        "\n" ..
        "QNH: %.0f hPa  (%.2f inHg / %.0f mmHg)\n" ..
        "TEMP: %+.0f°C\n" ..
        "\n" ..
        "SKY: %s\n" ..
        "VIS: %s\n" ..
        "WINDS: %s\n" ..
        "\n" ..
        "NOTAM:\n%s",
        timeStr,
        stage.name, stage.category,
        fmtHdg(dir0), msToKts(spd0),
        fmtHdg(dir2), msToKts(spd2),
        fmtHdg(dir8), msToKts(spd8),
        trend,
        qnhHpa, qnhInhg, qnhMmhg,
        temp,
        stage.cloudDesc,
        stage.visDesc,
        stage.windDesc,
        fmtHazards(stage)
    )

    broadcast(msg, CFG.MSG_DURATION_LONG)
    State.lastAtisTime = missionTimeSec
    env.info("[DWC] ATIS broadcast at T+" .. timeStr)
end

-- ═══════════════════════════════════════════════════════════════════════════
--  STAGE TRANSITION LOGIC
-- ═══════════════════════════════════════════════════════════════════════════

--- Check if we're about to cross a stage boundary and issue advance warnings.
local function checkTransitionWarnings(missionTimeSec)
    for i = 2, #WEATHER_STAGES do
        if not State.warningsFired[i] then
            local mins = minsUntilStage(i, missionTimeSec)
            if mins <= (CFG.WARN_LEAD_TIME / 60) and mins > 0 then
                local coming   = WEATHER_STAGES[i]
                local warnMins = math.floor(mins + 0.5)

                local warnMsg
                if coming.name == "THUNDERSTORM" then
                    warnMsg = string.format(
                        "⚠ WEATHER WARNING ⚠\n" ..
                        "Thunderstorm forecast in approximately %d minutes.\n" ..
                        "Expect: %s\n" ..
                        "All aircraft: plan divert or shelter before weather arrives.\n" ..
                        "Helicopters: land immediately when storm reaches area.",
                        warnMins, coming.cloudDesc
                    )
                elseif coming.name == "CLEARING" or coming.name == "OVERCAST" or coming.name == "CLEAR" then
                    warnMsg = string.format(
                        "ℹ WEATHER UPDATE\n" ..
                        "Conditions improving in approximately %d minutes.\n" ..
                        "Forecast: %s — %s",
                        warnMins, coming.name, coming.cloudDesc
                    )
                else
                    warnMsg = string.format(
                        "ℹ WEATHER TREND\n" ..
                        "Conditions changing in approximately %d minutes.\n" ..
                        "Moving to: %s [%s]",
                        warnMins, coming.name, coming.category
                    )
                end

                broadcast(warnMsg, CFG.MSG_DURATION_LONG)
                State.warningsFired[i] = true
                env.info("[DWC] Warning fired for stage " .. i .. " (" .. coming.name .. ")")
            end
        end
    end
end

--- Detect and announce when we cross into a new stage.
local prevStageIndex = 1

local function checkStageTransition(missionTimeSec)
    local stage = getCurrentStage(missionTimeSec)
    if State.currentStageIndex ~= prevStageIndex then
        local transMsg = string.format(
            "═══ WEATHER CHANGE: %s ═══\n" ..
            "Category: %s\n" ..
            "Sky: %s\n" ..
            "Visibility: %s\n" ..
            "Winds: %s\n" ..
            "NOTAM:\n%s",
            stage.name, stage.category,
            stage.cloudDesc,
            stage.visDesc,
            stage.windDesc,
            fmtHazards(stage)
        )
        broadcast(transMsg, CFG.MSG_DURATION_LONG)
        env.info("[DWC] Stage transition → " .. stage.name)

        -- Reset cycle if we've wrapped around to index 1 again after the last stage
        if State.currentStageIndex == 1 and prevStageIndex == #WEATHER_STAGES then
            State.cycleStartTime = missionTimeSec
            State.warningsFired  = {}
            env.info("[DWC] Weather cycle reset — new cycle started at T+" .. missionTimeSec)
        end

        prevStageIndex = State.currentStageIndex
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
--  FLAG CHECK — manual ATIS request
-- ═══════════════════════════════════════════════════════════════════════════

local function checkManualATISFlag(missionTimeSec)
    local flagVal = trigger.misc.getUserFlag(CFG.ATIS_FLAG)
    if flagVal and flagVal > 0 and not State.lastFlagState then
        broadcastATIS(missionTimeSec)
        trigger.action.setUserFlag(CFG.ATIS_FLAG, 0)
        State.lastFlagState = true
    elseif not flagVal or flagVal == 0 then
        State.lastFlagState = false
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
--  MAIN SCHEDULER LOOP
-- ═══════════════════════════════════════════════════════════════════════════

--- This function is called every 30 seconds by the DCS timer.
--- It handles all weather cycle logic and re-schedules itself.
local function weatherTick(_, time)
    local mTime = timer.getTime()

    -- 1. Update current stage index
    getCurrentStage(mTime)

    -- 2. Check for transition warnings (10-minute heads-up)
    checkTransitionWarnings(mTime)

    -- 3. Check and announce actual stage transitions
    checkStageTransition(mTime)

    -- 4. Periodic ATIS broadcast
    if (mTime - State.lastAtisTime) >= CFG.ATIS_INTERVAL then
        broadcastATIS(mTime)
    end

    -- 5. Manual ATIS request via User Flag
    checkManualATISFlag(mTime)

    -- Reschedule in 30 seconds
    return time + 30
end

-- ═══════════════════════════════════════════════════════════════════════════
--  INITIALISATION
-- ═══════════════════════════════════════════════════════════════════════════

local function init()
    -- ── Preset selection ──────────────────────────────────────────────────
    local pick
    if CFG.FORCE_PRESET and CFG.FORCE_PRESET >= 1 and CFG.FORCE_PRESET <= #WEATHER_PRESETS then
        -- Manual override: always use the configured preset number.
        pick = CFG.FORCE_PRESET
        env.info(string.format("[DWC] FORCE_PRESET active: using preset %d", pick))
    else
        -- Random selection.
        -- os.time() is blocked by DCS. timer.getAbsTime() is fixed when the
        -- mission always starts at the same time-of-day, so we mix in the
        -- fractional mantissa bits from atmosphere.getWind() — DCS's dynamic
        -- atmosphere engine produces slightly different float values each run
        -- even with identical ME settings, giving genuine per-session variance.
        local ref = CFG.AIRFIELD_REF
        local wLow  = atmosphere.getWind({ x = ref.x, y = ref.y + 10,   z = ref.z })
        local wHigh = atmosphere.getWind({ x = ref.x, y = ref.y + 5000, z = ref.z })
        -- Extract fractional digits by scaling up and taking modulo
        local e1 = math.abs(wLow.x  * 99991) % 100000
        local e2 = math.abs(wLow.z  * 49979) % 100000
        local e3 = math.abs(wHigh.x * 73867) % 100000
        local e4 = math.abs(wHigh.z * 31397) % 100000
        local seed = math.floor(e1 * 1000 + e2 * 100 + e3 * 10 + e4 + timer.getAbsTime())
        math.randomseed(seed % 2147483647)
        -- Discard the first value — Lua's LCG RNG can have weak low bits on
        -- the very first call after seeding.
        math.random()
        pick = math.random(1, #WEATHER_PRESETS)
        env.info(string.format("[DWC] RNG seed: %d  →  preset %d/%d", seed, pick, #WEATHER_PRESETS))
    end

    local preset = WEATHER_PRESETS[pick]
    WEATHER_STAGES = preset.stages
    env.info(string.format("[DWC] Weather preset active: %s", preset.name))

    State.cycleStartTime = timer.getTime()
    env.info("[DWC] DCS_DynamicWeatherCycle initialised at mission time " .. State.cycleStartTime)

    -- Announce which pattern was chosen so pilots know what kind of day to expect.
    local startMsg = string.format(
        "═══ AMERICAN VIKINGS — WEATHER ACTIVE ═══\n" ..
        "Today's weather pattern: %s\n" ..
        "%s\n\n" ..
        "Full cycle resets at +12h00m mission time.\n" ..
        "For full ATIS, set User Flag %d = TRUE in ME or wait for 5-minute auto-broadcast.\n" ..
        "Weather reports are broadcast to Blue coalition only.",
        preset.name,
        preset.desc,
        CFG.ATIS_FLAG
    )
    broadcast(startMsg, CFG.MSG_DURATION_LONG)

    -- Schedule the first ATIS at T+20 seconds, then ticks every 30 s
    timer.scheduleFunction(weatherTick, nil, timer.getTime() + 20)

    -- First ATIS auto-broadcast at T+30 seconds
    timer.scheduleFunction(function(_, t)
        broadcastATIS(timer.getTime())
        return nil  -- one-shot
    end, nil, timer.getTime() + 30)
end

-- ── Kick off ──────────────────────────────────────────────────────────────
init()

-- ============================================================================
--  QUICK REFERENCE — WHAT EACH PART DOES
-- ============================================================================
--
--  broadcastATIS()        Reads live atmosphere.* data and formats a full
--                         METAR-style weather report for all players. Called
--                         every 5 minutes and on User Flag trigger.
--
--  weatherTick()          Main 30-second scheduler loop. Calls all sub-checks
--                         then re-queues itself automatically.
--
--  checkTransitionWarnings()
--                         Issues 30-minute advance notice before THUNDERSTORM,
--                         CLEARING, etc. Fires once per stage (flag-guarded).
--
--  checkStageTransition() Detects when the mission clock crosses a stage
--                         boundary and announces the new conditions.
--
--  windTrend()            Analyses the last 6 wind samples (~3 min of data)
--                         and reports whether speed is rising/falling and
--                         direction is veering/backing.
--
--  CFG.ATIS_FLAG          User Flag number that pilots/controllers can trigger
--                         in the ME to request an immediate ATIS dump.
--
--  RANDOM PRESET SELECTION:
--    os.time() is blocked by DCS. If the mission always starts at the same
--    time-of-day, timer.getAbsTime() is also fixed. Instead the script mixes
--    fractional mantissa bits from atmosphere.getWind() — DCS's dynamic
--    atmosphere produces slightly different float values each run — combined
--    with primed LCG multipliers to spread the seed values.
--    The RNG seed and chosen preset are both logged to dcs.log as [DWC] entries.
--
--    To manually pick a preset (e.g. for testing or scripted events), set
--    CFG.FORCE_PRESET = N where N is 1-15. Set back to 0 for random selection.
--
--  AVAILABLE PRESETS (chosen randomly each mission):
--    1.  CLASSIC STORM CYCLE        — Clear → Storm → Clearing → Overcast → Clear
--    2.  MEDITERRANEAN SUMMER       — Fine VFR day, thermal cumulus only
--    3.  PERSISTENT OVERCAST        — IFR/low cloud throughout, brief mid-day break
--    4.  MORNING FOG                — Dense fog burns off to clear afternoon
--    5.  RAPID SQUALL LINE          — Brief violent squall, exceptional post-squall vis
--    6.  KHAMSIN DUST STORM         — Desert dust reduces visibility to near zero
--    7.  CYPRUS LOW                 — Med cyclone, organised frontal rain bands
--    8.  WINTER COLD FRONT          — Violent front passage, spectacular post-frontal clarity
--    9.  SHAMAL NORTHERLY           — Strong post-frontal northerly, gusty and clear
--    10. EXPLOSIVE CONVECTION       — Calm morning, violent afternoon CB outbreak
--    11. COASTAL STRATUS            — Marine stratus IFR on coast, clear inland
--    12. WARM FRONT APPROACH        — Classic high-to-low cloud sequence, ends in rain
--    13. POST-FRONTAL POLAR CLARITY — Exceptional VFR, isolated shower cells only hazard
--    14. SIROCCO HEAT HAZE          — Savage heat, no dust but density altitude critical
--    15. WINTER ANTICYCLONE         — Cold morning fog/frost, hazy anticyclonic afternoon
--
--  To add a new preset: append a new { name, desc, stages = {...} } block to
--  WEATHER_PRESETS. It will be included in the random pool automatically.
--  To change stage timings, only edit startMin values inside the preset's stages.
--  No ME trigger updates needed — the script is self-contained.
--
-- ============================================================================
