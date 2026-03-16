-- ============================================================================
--  DCS_DynamicWeatherPreset.lua
--  American Vikings — Syria Mission
--
--  PURPOSE
--  ───────────────────────────────────────────────────────────────────────
--  Generates 6 realistic, varied weather node descriptions each mission start
--  and broadcasts them to pilots as a full-mission weather forecast.
--
--  Each of the 6 nodes covers a 2-hour window of the 12-hour mission cycle.
--  The node sequence follows a meteorologically plausible narrative arc —
--  the generator picks a random starting state then walks through realistic
--  transition rules to produce the remaining 5 nodes.
--
--  The script reads live atmosphere data (wind, temp, pressure) every 30
--  seconds and broadcasts current conditions alongside the node forecast.
--
--  DCS API NOTE
--  ───────────────────────────────────────────────────────────────────────
--  DCS's scripting engine cannot SET cloud presets, fog, or visibility at
--  runtime — there is no setWeather() function. The node descriptions
--  generated here are forecast text for pilots. The actual sky appearance
--  is driven by DCS's own dynamic atmosphere (set Atmosphere Type = Dynamic
--  in the ME Weather tab).
--
--  ───────────────────────────────────────────────────────────────────────
--  INSTALLATION  (two steps only)
--  ───────────────────────────────────────────────────────────────────────
--  1. ME Trigger: ONCE / MISSION START / DO SCRIPT FILE → this file
--  2. ME Weather tab: Atmosphere Type = DYNAMIC, set your starting
--     conditions. DCS evolves them automatically — no extra triggers needed.
--
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
--  CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════

local CFG = {

    -- Airfield reference position for atmosphere queries (Syria — Incirlik approx)
    AIRFIELD_REF = { x = -35000, y = 0, z = 75000 },

    -- How long each node period lasts (hours)
    NODE_DURATION_HOURS = 2,

    -- Number of nodes in the full cycle
    NODE_COUNT = 6,

    -- ATIS broadcast interval (seconds)
    ATIS_INTERVAL = 300,

    -- User Flag: set to TRUE in ME to request immediate weather update
    ATIS_FLAG = 10,

    -- Coalition: 0=all, 1=red, 2=blue
    BROADCAST_COALITION = 2,

    -- Message display durations (seconds)
    MSG_SHORT = 15,
    MSG_LONG  = 30,

    -- Wind history samples for trend analysis
    WIND_HISTORY = 6,

}

-- ═══════════════════════════════════════════════════════════════════════════
--  WEATHER ARCHETYPES
--  Each archetype defines the parameter ranges for one weather state.
--  The generator picks from within these ranges for concrete node values.
--
--  Wind speeds in m/s (1 m/s ≈ 2 kts).
--  Visibility in metres.
--  Pressure in hPa.
--  Temperature in °C.
-- ═══════════════════════════════════════════════════════════════════════════

local ARCHETYPES = {

    CLEAR = {
        label    = "CLEAR",
        category = "VFR",
        -- Cloud options: { DCS preset name, ATIS description }
        clouds = {
            { "Preset1",  "Few cumulus 7000 ft, scattered cirrus high above" },
            { "Preset2",  "Few clouds 8000 ft, extensive blue above" },
            { "Preset4",  "Scattered fair-weather cumulus 8000 ft, CAVOK" },
            { "Preset10", "Few cumulus 6500 ft, thin cirrus only above FL200" },
        },
        windSpd    = { 2,  9 },    -- surface m/s range
        shear2k    = { 1.3, 1.8 }, -- multiplier: 2000 m wind vs surface
        shear8k    = { 2.0, 2.8 }, -- multiplier: 8000 m wind vs surface
        dirDelta2k = { -10, 15 },  -- degrees of right-veer 0m→2000m
        dirDelta8k = { 5,   30 },  -- degrees of right-veer 0m→8000m
        vis        = { 40000, 65000 },
        qnh        = { 1015, 1025 },
        temp       = { 16, 34 },
        hazards    = {},
    },

    BUILDING = {
        label    = "BUILDING",
        category = "MVFR",
        clouds = {
            { "Preset6",  "Scattered to broken, base lowering 4500-6000 ft, cumulus towers" },
            { "Preset7",  "Broken cumulus 4000 ft, tops to 18 000 ft, organized convection" },
            { "Preset8",  "Scattered medium cloud 5000-7000 ft, anvils visible to west" },
            { "Preset11", "Broken CB developing, base 3500 ft, heavy tops" },
        },
        windSpd    = { 7,  18 },
        shear2k    = { 1.4, 2.0 },
        shear8k    = { 2.2, 3.2 },
        dirDelta2k = { -5,  20 },
        dirDelta8k = { 10,  35 },
        vis        = { 12000, 30000 },
        qnh        = { 1008, 1018 },
        temp       = { 14, 30 },
        hazards    = {
            "Cloud base lowering — monitor ceiling trend",
            "Wind speed increasing — forecast: continued building",
        },
    },

    STORMY = {
        label    = "THUNDERSTORM",
        category = "LIFR",
        clouds = {
            { "RainyPreset3", "Cumulonimbus overcast, base 1800-2500 ft, continuous lightning" },
            { "RainyPreset2", "Overcast Cb and Ns, base 1500-2000 ft, heavy rain" },
            { "Overcast7",    "Dense overcast OVC015, embedded Cb, severe turbulence" },
        },
        windSpd    = { 15, 38 },
        shear2k    = { 1.1, 1.5 },
        shear8k    = { 1.6, 2.5 },
        dirDelta2k = { -30, 30 },   -- erratic direction in storm
        dirDelta8k = { -15, 25 },
        vis        = { 300,  3000 },
        qnh        = { 995, 1010 },
        temp       = { 8,  22 },
        hazards    = {
            "SEVERE TURBULENCE — avoid flight",
            "Heavy precipitation — reduced windscreen visibility",
            "Lightning hazard — ground all aircraft if possible",
            "Windshear on approach and departure",
            "Icing in cloud above 8000 ft",
        },
    },

    OVERCAST = {
        label    = "OVERCAST",
        category = "IFR",
        clouds = {
            { "Overcast5", "Overcast OVC080, base 7000-8000 ft, thick layer" },
            { "Overcast6", "Overcast OVC060, base 5000-6000 ft, grey and featureless" },
            { "RainyPreset1", "Overcast nimbostratus, base 3000-4000 ft, light to moderate rain" },
            { "Preset16",  "Overcast stratus OVC040, ceiling 3500-4500 ft, drizzle" },
        },
        windSpd    = { 8,  22 },
        shear2k    = { 1.3, 1.9 },
        shear8k    = { 1.8, 2.6 },
        dirDelta2k = { -5,  20 },
        dirDelta8k = { 5,   30 },
        vis        = { 5000, 20000 },
        qnh        = { 1000, 1015 },
        temp       = { 8,  22 },
        hazards    = {
            "Ceiling at or near IFR minima",
            "Light precipitation — wet runway",
        },
    },

    CLEARING = {
        label    = "CLEARING",
        category = "MVFR",
        clouds = {
            { "Preset14", "Broken stratocumulus, base lifting 3000-5000 ft, gaps widening" },
            { "Preset13", "Broken cumulus, base rising to 4000 ft, good visibility between cells" },
            { "Preset9",  "Scattered 4000 ft, cloud rapidly breaking up, blue sky sectors" },
            { "Overcast8","Broken OVC030 lifting, horizon clearing from northwest" },
        },
        windSpd    = { 10, 25 },
        shear2k    = { 1.3, 1.8 },
        shear8k    = { 1.9, 2.7 },
        dirDelta2k = { -5,  20 },
        dirDelta8k = { 10,  35 },
        vis        = { 10000, 30000 },
        qnh        = { 1005, 1018 },
        temp       = { 10, 24 },
        hazards    = {
            "Residual turbulence below 8000 ft",
            "Wet runways — braking action reduced",
        },
    },

    FOGGY = {
        label    = "FOG",
        category = "LIFR",
        clouds = {
            { "Overcast8", "Radiation fog OVC000-OVC003, tops 400-600 ft, ground obscured" },
            { "Overcast7", "Dense stratus OVC005, fog layer, ceiling near surface" },
        },
        windSpd    = { 0,  4 },
        shear2k    = { 1.5, 2.5 }, -- wind often increases sharply above fog layer
        shear8k    = { 2.5, 4.0 },
        dirDelta2k = { 20,  60 },   -- strong veering above temperature inversion
        dirDelta8k = { 40,  90 },
        vis        = { 80,  600 },
        qnh        = { 1018, 1030 },
        temp       = { 4,  18 },
        hazards    = {
            "TAKEOFF AND LANDING SUSPENDED — visibility below minimums",
            "Fog: nil visibility on taxi — marshaller escort required",
            "Inversion at 400-600 ft — expect severe turbulence at cloud top",
        },
    },

    HAZY = {
        label    = "HAZY",
        category = "VFR",
        clouds = {
            { "Preset3",  "Clear above haze layer, scattered at 5000 ft" },
            { "Preset5",  "Few thin cloud 6000 ft, heavy surface haze" },
            { "Preset1",  "Few clouds, haze reducing visibility on approach" },
        },
        windSpd    = { 5,  15 },
        shear2k    = { 1.3, 1.7 },
        shear8k    = { 1.8, 2.5 },
        dirDelta2k = { -5,  15 },
        dirDelta8k = { 5,   25 },
        vis        = { 8000, 20000 },
        qnh        = { 1010, 1022 },
        temp       = { 20, 38 },
        hazards    = {
            "Heat haze: horizon distortion, depth perception degraded",
            "Density altitude elevated — check performance charts",
        },
    },

    GUSTY = {
        label    = "GUSTY CLEAR",
        category = "VFR",
        clouds = {
            { "Preset2",  "Few large cumulus, sharply defined, strong thermal columns" },
            { "Preset3",  "Scattered fair-weather Cu, excellent visibility between" },
            { "Preset5",  "Few towering cumulus, otherwise clear and brilliant" },
        },
        windSpd    = { 14, 28 },
        shear2k    = { 1.2, 1.6 },
        shear8k    = { 1.6, 2.2 },
        dirDelta2k = { -10, 20 },
        dirDelta8k = { 5,   30 },
        vis        = { 30000, 60000 },
        qnh        = { 1015, 1025 },
        temp       = { 10, 26 },
        hazards    = {
            "Strong gusty crosswinds — check runway in use",
            "Low-level windshear and turbulence over ridgelines",
        },
    },

    COLD_FRONT = {
        label    = "FRONTAL PASSAGE",
        category = "IFR",
        clouds = {
            { "RainyPreset2", "Dense Cb wall, overcast OVC005, torrential rain, hail possible" },
            { "RainyPreset3", "Overcast Cb overcast, base 1200-2000 ft, embedded CB throughout" },
        },
        windSpd    = { 22, 42 },
        shear2k    = { 1.0, 1.4 },
        shear8k    = { 1.2, 1.8 },
        dirDelta2k = { -45, 45 },   -- violent and erratic at frontal passage
        dirDelta8k = { -30, 30 },
        vis        = { 200,  2000 },
        qnh        = { 990, 1005 },
        temp       = { 4,  18 },
        hazards    = {
            "EXTREME TURBULENCE — all flight operations suspended",
            "Wind shift 60-90° at frontal passage — runway change required",
            "Hail risk — all aircraft in hardened shelter",
            "Severe icing in cloud FL050 to FL200",
        },
    },

    DUST = {
        label    = "DUST HAZE",
        category = "MVFR",
        clouds = {
            { "Preset3",  "Sky obscured by suspended dust, brownish horizon, sun pale disc" },
            { "Preset1",  "Near-clear above dust layer, wall of tan haze below 8000 ft" },
        },
        windSpd    = { 12, 26 },
        shear2k    = { 1.2, 1.7 },
        shear8k    = { 1.6, 2.2 },
        dirDelta2k = { -5,  15 },
        dirDelta8k = { 5,   20 },
        vis        = { 2000, 12000 },
        qnh        = { 1008, 1020 },
        temp       = { 24, 42 },
        hazards    = {
            "Dust ingestion: engine anti-ice/compressor wash required",
            "FOD risk elevated on all surfaces",
            "Density altitude significantly higher than field elevation",
        },
    },

}

-- ═══════════════════════════════════════════════════════════════════════════
--  TRANSITION RULES
--  Defines valid next-archetype options from each current archetype.
--  Each entry is a list of archetype keys with relative weights.
--  Higher weight = more likely to be chosen as the next node.
-- ═══════════════════════════════════════════════════════════════════════════

local TRANSITIONS = {
    CLEAR      = { {k="CLEAR",3}, {k="BUILDING",4}, {k="HAZY",3}, {k="GUSTY",2} },
    BUILDING   = { {k="BUILDING",2}, {k="STORMY",4}, {k="OVERCAST",3}, {k="HAZY",1} },
    STORMY     = { {k="STORMY",2}, {k="CLEARING",4}, {k="OVERCAST",3}, {k="COLD_FRONT",1} },
    OVERCAST   = { {k="OVERCAST",2}, {k="CLEARING",3}, {k="FOGGY",2}, {k="STORMY",2}, {k="BUILDING",1} },
    CLEARING   = { {k="OVERCAST",2}, {k="CLEAR",3}, {k="GUSTY",3}, {k="HAZY",2} },
    FOGGY      = { {k="FOGGY",2}, {k="OVERCAST",3}, {k="CLEARING",3}, {k="HAZY",2} },
    HAZY       = { {k="HAZY",2}, {k="CLEAR",2}, {k="DUST",3}, {k="BUILDING",2}, {k="OVERCAST",1} },
    GUSTY      = { {k="GUSTY",2}, {k="CLEAR",3}, {k="BUILDING",2}, {k="COLD_FRONT",2}, {k="CLEARING",1} },
    COLD_FRONT = { {k="CLEARING",4}, {k="GUSTY",3}, {k="OVERCAST",2}, {k="CLEAR",1} },
    DUST       = { {k="DUST",2}, {k="HAZY",3}, {k="CLEAR",2}, {k="BUILDING",2}, {k="STORMY",1} },
}

-- Opening archetypes and their relative weights (season-tuned for Syria)
local OPENING_STATES = {
    {k="CLEAR",    w=4},
    {k="HAZY",     w=3},
    {k="OVERCAST", w=2},
    {k="FOGGY",    w=2},
    {k="GUSTY",    w=2},
    {k="BUILDING", w=1},
    {k="DUST",     w=1},
}

-- ═══════════════════════════════════════════════════════════════════════════
--  STATE
-- ═══════════════════════════════════════════════════════════════════════════

local State = {
    nodes       = {},           -- generated node list, populated in init()
    windHistory = {},
    lastAtisTime = 0,
    lastFlagState = false,
}

-- ═══════════════════════════════════════════════════════════════════════════
--  UTILITY
-- ═══════════════════════════════════════════════════════════════════════════

local function randRange(lo, hi)
    return lo + math.random() * (hi - lo)
end

local function randInt(lo, hi)
    return math.floor(randRange(lo, hi + 0.9999))
end

local function pick(t)
    return t[math.random(#t)]
end

--- Weighted pick from a list of {k=key, w=weight} or {k=key, [1]=weight}.
local function weightedPick(list)
    local total = 0
    for _, entry in ipairs(list) do
        total = total + (entry.w or entry[1])
    end
    local r = math.random() * total
    local acc = 0
    for _, entry in ipairs(list) do
        acc = acc + (entry.w or entry[1])
        if r <= acc then return entry.k end
    end
    return list[#list].k
end

local function msToKts(ms)   return ms * 1.94384    end
local function paToHpa(pa)   return pa / 100         end
local function paToInhg(pa)  return pa / 3386.39     end
local function fmtHdg(deg)
    return string.format("%03d", math.floor(deg + 0.5) % 360)
end

local function windVecToMet(vec)
    local speed = math.sqrt(vec.x ^ 2 + vec.z ^ 2)
    local dir   = math.deg(math.atan2(-vec.x, -vec.z)) % 360
    return speed, dir
end

local function broadcast(msg, dur)
    local d = dur or CFG.MSG_SHORT
    if CFG.BROADCAST_COALITION == 0 then
        trigger.action.outText(msg, d)
    else
        trigger.action.outTextForCoalition(CFG.BROADCAST_COALITION, msg, d)
    end
end

local function fmtHazards(hazards)
    if #hazards == 0 then return "  NIL" end
    local lines = {}
    for _, h in ipairs(hazards) do
        table.insert(lines, "  ⚠ " .. h)
    end
    return table.concat(lines, "\n")
end

-- ═══════════════════════════════════════════════════════════════════════════
--  RNG SEEDING
--  os.time() is blocked in DCS. We use atmosphere.getWind() fractional bits
--  as entropy — DCS's dynamic atmosphere produces slightly different floats
--  each run even with identical ME settings.
-- ═══════════════════════════════════════════════════════════════════════════

local function seedRNG()
    local ref   = CFG.AIRFIELD_REF
    local wLow  = atmosphere.getWind({ x = ref.x, y = ref.y + 10,   z = ref.z })
    local wHigh = atmosphere.getWind({ x = ref.x, y = ref.y + 5000, z = ref.z })
    local e1 = math.abs(wLow.x  * 99991) % 100000
    local e2 = math.abs(wLow.z  * 49979) % 100000
    local e3 = math.abs(wHigh.x * 73867) % 100000
    local e4 = math.abs(wHigh.z * 31397) % 100000
    local seed = math.floor(e1 * 1000 + e2 * 100 + e3 * 10 + e4 + timer.getAbsTime())
    math.randomseed(seed % 2147483647)
    math.random() -- discard first value (poor low-bit distribution on some LCG seeds)
    env.info(string.format("[DWP] RNG seed: %d", seed))
end

-- ═══════════════════════════════════════════════════════════════════════════
--  NODE GENERATION
--  Walks the Markov transition table to produce CFG.NODE_COUNT nodes.
--  Each node has concrete parameter values drawn from its archetype's ranges.
-- ═══════════════════════════════════════════════════════════════════════════

local function buildNode(archetypeKey, nodeIndex)
    local arch = ARCHETYPES[archetypeKey]

    -- Pick a cloud option
    local cloud = pick(arch.clouds)

    -- Generate surface wind direction (random compass bearing)
    local surfDir = randRange(0, 360)

    -- Generate surface wind speed within archetype range
    local surfSpd = randRange(arch.windSpd[1], arch.windSpd[2])

    -- 2000 m: speed increases by shear factor, direction veers by dirDelta
    local shear2  = randRange(arch.shear2k[1], arch.shear2k[2])
    local veer2   = randRange(arch.dirDelta2k[1], arch.dirDelta2k[2])
    local spd2    = surfSpd * shear2
    local dir2    = (surfDir + veer2) % 360

    -- 8000 m: speed increases further, direction veers more with altitude
    local shear8  = randRange(arch.shear8k[1], arch.shear8k[2])
    local veer8   = randRange(arch.dirDelta8k[1], arch.dirDelta8k[2])
    local spd8    = surfSpd * shear8
    local dir8    = (surfDir + veer8) % 360

    -- Pressure, temperature, visibility
    local qnh  = randRange(arch.qnh[1], arch.qnh[2])
    local temp = randRange(arch.temp[1], arch.temp[2])
    local vis  = randInt(arch.vis[1], arch.vis[2])

    -- Time window label
    local startH = (nodeIndex - 1) * CFG.NODE_DURATION_HOURS
    local endH   = startH + CFG.NODE_DURATION_HOURS

    return {
        index      = nodeIndex,
        archetype  = archetypeKey,
        label      = arch.label,
        category   = arch.category,
        cloud      = cloud,          -- { preset, desc }
        surfDir    = surfDir,
        surfSpd    = surfSpd,
        spd2       = spd2,
        dir2       = dir2,
        spd8       = spd8,
        dir8       = dir8,
        qnh        = qnh,
        temp       = temp,
        vis        = vis,
        hazards    = arch.hazards,
        startH     = startH,
        endH       = endH,
    }
end

local function generateNodes()
    local nodes = {}

    -- Pick opening state
    local currentKey = weightedPick(OPENING_STATES)

    for i = 1, CFG.NODE_COUNT do
        local node = buildNode(currentKey, i)
        table.insert(nodes, node)

        -- Pick next archetype using transition rules
        if i < CFG.NODE_COUNT then
            local options = TRANSITIONS[currentKey]
            if options then
                currentKey = weightedPick(options)
            else
                currentKey = weightedPick(OPENING_STATES)
            end
        end
    end

    return nodes
end

-- ═══════════════════════════════════════════════════════════════════════════
--  NODE LOOKUP — which node is active at current mission time
-- ═══════════════════════════════════════════════════════════════════════════

local function getActiveNode(mTime)
    local elapsedH = mTime / 3600
    elapsedH = elapsedH % (CFG.NODE_COUNT * CFG.NODE_DURATION_HOURS) -- wrap at cycle end

    local active = State.nodes[1]
    for _, node in ipairs(State.nodes) do
        if elapsedH >= node.startH then
            active = node
        end
    end
    return active
end

-- ═══════════════════════════════════════════════════════════════════════════
--  WIND TREND
-- ═══════════════════════════════════════════════════════════════════════════

local function recordWindSample(speed, dir, mTime)
    table.insert(State.windHistory, { speed = speed, dir = dir, time = mTime })
    if #State.windHistory > CFG.WIND_HISTORY then
        table.remove(State.windHistory, 1)
    end
end

local function windTrend()
    if #State.windHistory < 3 then return "trend unavailable" end
    local oldest = State.windHistory[1]
    local newest = State.windHistory[#State.windHistory]
    local dSpd = newest.speed - oldest.speed
    local dDir = ((newest.dir - oldest.dir) + 360) % 360
    if dDir > 180 then dDir = dDir - 360 end

    local parts = {}
    if math.abs(dSpd) < 0.5 then
        table.insert(parts, "speed steady")
    elseif dSpd > 0 then
        table.insert(parts, string.format("speed RISING +%.0f kts", msToKts(dSpd)))
    else
        table.insert(parts, string.format("speed falling %.0f kts", msToKts(math.abs(dSpd))))
    end
    if math.abs(dDir) < 5 then
        table.insert(parts, "direction steady")
    elseif dDir > 0 then
        table.insert(parts, string.format("backing %d°", math.abs(math.floor(dDir))))
    else
        table.insert(parts, string.format("veering %d°", math.abs(math.floor(dDir))))
    end
    return table.concat(parts, " | ")
end

-- ═══════════════════════════════════════════════════════════════════════════
--  FULL MISSION WEATHER PLAN BROADCAST
--  Sends all 6 nodes as a day-of-mission forecast sheet.
-- ═══════════════════════════════════════════════════════════════════════════

local function broadcastWeatherPlan()
    local lines = { "══ AMERICAN VIKINGS — MISSION WEATHER PLAN ══" }
    table.insert(lines, string.format("%-12s %-8s %-6s  %s", "PERIOD", "STATUS", "CAT", "SKY / WIND"))
    table.insert(lines, string.rep("─", 62))

    for _, node in ipairs(State.nodes) do
        local windLine = string.format("%s°/%.0f kts sfc  %s°/%.0f kts 2km  %s°/%.0f kts 8km",
            fmtHdg(node.surfDir), msToKts(node.surfSpd),
            fmtHdg(node.dir2),   msToKts(node.spd2),
            fmtHdg(node.dir8),   msToKts(node.spd8))

        table.insert(lines, string.format("T+%02d:00-%02d:00  %-15s [%-4s]",
            node.startH, node.endH, node.label, node.category))
        table.insert(lines, string.format("  SKY:  %s", node.cloud[2]))
        table.insert(lines, string.format("  VIS:  %d km", math.floor(node.vis / 1000)))
        table.insert(lines, string.format("  WIND: %s", windLine))
        table.insert(lines, string.format("  QNH:  %.0f hPa  TEMP: +%.0f°C", node.qnh, node.temp))
        if #node.hazards > 0 then
            table.insert(lines, "  NOTAMs:")
            for _, h in ipairs(node.hazards) do
                table.insert(lines, "    ⚠ " .. h)
            end
        end
        table.insert(lines, "")
    end

    broadcast(table.concat(lines, "\n"), CFG.MSG_LONG)
    env.info("[DWP] Full weather plan broadcast")
end

-- ═══════════════════════════════════════════════════════════════════════════
--  LIVE ATIS BROADCAST
--  Reads real atmosphere.* data and combines with the active node forecast.
-- ═══════════════════════════════════════════════════════════════════════════

local function broadcastATIS(mTime)
    local ref = CFG.AIRFIELD_REF

    local w0  = atmosphere.getWind({ x = ref.x, y = ref.y,        z = ref.z })
    local w2  = atmosphere.getWind({ x = ref.x, y = ref.y + 2000, z = ref.z })
    local w8  = atmosphere.getWind({ x = ref.x, y = ref.y + 8000, z = ref.z })
    local temp, pressPa = atmosphere.getTemperatureAndPressure({ x = ref.x, y = ref.y, z = ref.z })

    local spd0, dir0 = windVecToMet(w0)
    local spd2, dir2 = windVecToMet(w2)
    local spd8, dir8 = windVecToMet(w8)
    local qnhHpa     = paToHpa(pressPa)
    local qnhInhg    = paToInhg(pressPa)

    recordWindSample(spd0, dir0, mTime)
    local trend = windTrend()

    local node = getActiveNode(mTime)
    local hrs  = math.floor(mTime / 3600)
    local mins = math.floor((mTime % 3600) / 60)
    local timeStr = string.format("%02d:%02d", hrs, mins)
    local nextNode = State.nodes[node.index < CFG.NODE_COUNT and node.index + 1 or 1]

    local msg = string.format(
        "══ AMERICAN VIKINGS WEATHER – %s ══\n" ..
        "CURRENT: %s  [%s]\n" ..
        "\n" ..
        "SURFACE   %s° / %.0f kts\n" ..
        "2 000 m   %s° / %.0f kts\n" ..
        "8 000 m   %s° / %.0f kts\n" ..
        "TREND: %s\n" ..
        "\n" ..
        "QNH: %.0f hPa  (%.2f inHg)\n" ..
        "TEMP: %+.0f°C\n" ..
        "\n" ..
        "SKY: %s\n" ..
        "VIS: %d km\n" ..
        "\n" ..
        "NEXT PERIOD (T+%02d:00): %s  [%s]\n" ..
        "\n" ..
        "NOTAM:\n%s",
        timeStr,
        node.label, node.category,
        fmtHdg(dir0), msToKts(spd0),
        fmtHdg(dir2), msToKts(spd2),
        fmtHdg(dir8), msToKts(spd8),
        trend,
        qnhHpa, qnhInhg,
        temp,
        node.cloud[2],
        math.floor(node.vis / 1000),
        nextNode.startH, nextNode.label, nextNode.category,
        fmtHazards(node.hazards)
    )

    broadcast(msg, CFG.MSG_LONG)
    State.lastAtisTime = mTime
    env.info("[DWP] ATIS broadcast T+" .. timeStr)
end

-- ═══════════════════════════════════════════════════════════════════════════
--  MAIN SCHEDULER LOOP
-- ═══════════════════════════════════════════════════════════════════════════

local function tick(_, time)
    local mTime = timer.getTime()

    -- Periodic ATIS
    if (mTime - State.lastAtisTime) >= CFG.ATIS_INTERVAL then
        broadcastATIS(mTime)
    end

    -- On-demand ATIS via User Flag
    local flagVal = trigger.misc.getUserFlag(CFG.ATIS_FLAG)
    if flagVal and flagVal > 0 and not State.lastFlagState then
        broadcastATIS(mTime)
        trigger.action.setUserFlag(CFG.ATIS_FLAG, 0)
        State.lastFlagState = true
    elseif not flagVal or flagVal == 0 then
        State.lastFlagState = false
    end

    return time + 30
end

-- ═══════════════════════════════════════════════════════════════════════════
--  INITIALISATION
-- ═══════════════════════════════════════════════════════════════════════════

local function init()
    seedRNG()

    -- Generate the 6 nodes
    State.nodes = generateNodes()

    -- Log the generated sequence
    local seq = {}
    for _, n in ipairs(State.nodes) do
        table.insert(seq, string.format("T+%02dh:%s", n.startH, n.label))
    end
    env.info("[DWP] Node sequence: " .. table.concat(seq, " → "))

    -- Broadcast the full weather plan immediately
    broadcastWeatherPlan()

    -- First ATIS 30 seconds after load
    timer.scheduleFunction(function(_, t)
        broadcastATIS(timer.getTime())
        return nil
    end, nil, timer.getTime() + 30)

    -- Start the 30-second tick loop at T+20s
    timer.scheduleFunction(tick, nil, timer.getTime() + 20)

    env.info("[DWP] DCS_DynamicWeatherPreset initialised")
end

init()

-- ============================================================================
--  QUICK REFERENCE
-- ============================================================================
--
--  seedRNG()              Uses atmosphere.getWind() fractional bits + primed
--                         LCG multipliers for entropy. Works even when mission
--                         always starts at the same time-of-day.
--
--  generateNodes()        Picks an opening archetype from OPENING_STATES
--                         (weighted), then walks TRANSITIONS to produce 6
--                         nodes. Each node gets concrete random values drawn
--                         from within that archetype's parameter ranges.
--
--  broadcastWeatherPlan() Sends the full 6-node forecast sheet to coalition
--                         at mission start. Re-request via User Flag.
--
--  broadcastATIS()        Live atmosphere.* reading (wind at 0/2000/8000 m,
--                         QNH, temp) combined with the active node forecast.
--
--  tick()                 30-second scheduler loop — periodic ATIS + flag check.
--
--  ARCHETYPES             10 weather states (CLEAR, BUILDING, STORMY, OVERCAST,
--                         CLEARING, FOGGY, HAZY, GUSTY, COLD_FRONT, DUST).
--                         Each defines: cloud options, wind speed/shear/veer
--                         ranges at 3 altitudes, vis, QNH, temp, hazards.
--
--  TRANSITIONS            Weighted Markov table — defines which archetypes can
--                         plausibly follow each other to ensure realistic arcs.
--
--  To add a new archetype: add to ARCHETYPES + add a TRANSITIONS entry for it
--  + add it to any TRANSITIONS lists where it should be reachable from.
--
--  CFG.ATIS_FLAG          Set this User Flag to TRUE in ME to force an ATIS.
--
-- ============================================================================
