-- =============================================================================
--  WWII Marianas – Airbase / Objective Capture Script
--  Version : 1.0  |  Map : Marianas  |  Era : WWII
--  Standalone – NO MIST / MOOSE required
--
--  LOAD ORDER in Mission Editor:
--    1. (MIST optional – not needed by this script)
--    2. WWII_Marianas_AirbaseCapture.lua  (this file)
--
--  FEATURES:
--    - Dynamic zone-based capture system with state machine
--      RED ↔ NEUTRAL ↔ BLUE  (requires consecutive scan ticks)
--    - F10 map coloured circle + text markers per objective
--    - Supports airbases, FARPs and generic objectives
--    - Public API for external scripts
--
--  ME SETUP:
--    For each objective create a TRIGGER ZONE named exactly  CAPTURE_ZONE_<key>
--    where <key> matches the key in the REGISTRY table below.
--    Example:  CAPTURE_ZONE_AganaAirfield  (circle trigger zone in ME)
--
--    For destroyable objectives, place a STATIC or GROUP named to match
--    DESTROY_REGISTRY entries.
-- =============================================================================

ABC = {}

-- ─────────────────────────────────────────────────────────────────────────────
--  CONFIGURATION
-- ─────────────────────────────────────────────────────────────────────────────

ABC.CHECK_INTERVAL    = 180   -- seconds between capture scans
ABC.CAPTURE_TICKS     = 3     -- consecutive scans to capture
ABC.MIN_CAPTURE_UNITS = 1     -- minimum ground units inside zone

ABC.DEBUG = false              -- set true for env.info logging

-- Colours {r, g, b, a}  (0-1 range) — matches Syria mission palette
ABC.COLOURS = {
    RED       = { 1.00, 0.00, 0.00, 1.00 },
    BLUE      = { 0.00, 0.40, 1.00, 1.00 },
    NEUTRAL   = { 1.00, 1.00, 1.00, 1.00 },
    DESTROYED = { 0.00, 0.00, 0.00, 1.00 },
}
ABC.FILL_COLOURS = {
    RED       = { 0.55, 0.00, 0.00, 0.15 },
    BLUE      = { 0.00, 0.00, 0.65, 0.15 },
    NEUTRAL   = { 0.40, 0.40, 0.40, 0.15 },
    DESTROYED = { 0.00, 0.00, 0.00, 0.15 },
}

-- ─────────────────────────────────────────────────────────────────────────────
--  REGISTRY
--  owner = starting coalition : "RED" | "BLUE" | "NEUTRAL"
--  display = label shown on map
--  type = "airbase" | "farp" | "objective"
--  airbaseName  = DCS airbase name (used for parking/coalition swap, airbases only)
-- ─────────────────────────────────────────────────────────────────────────────

ABC.REGISTRY = {
    -- RED objectives
    RotaAirfield   = { owner = "RED", display = "Rota Airfield",   type = "airbase",   airbaseName = "Rota Intl" },
    CharonKanoa    = { owner = "RED", display = "Charon Kanoa",    type = "airbase",   airbaseName = "Charon Kanoa" },
    Ushi           = { owner = "RED", display = "Ushi",            type = "airbase",   airbaseName = "Ushi" },
    GurguanPoint   = { owner = "RED", display = "Gurguan Point",   type = "airbase",   airbaseName = "Gurguan Point" },
    Pagan          = { owner = "RED", display = "Pagan",            type = "airbase",   airbaseName = "Pagan" },

    -- BLUE objectives
    AganaAirfield  = { owner = "BLUE", display = "Agana Airfield", type = "airbase",   airbaseName = "Antonio B. Won Pat Intl" },
}

-- ─────────────────────────────────────────────────────────────────────────────
--  DESTROY ZONE REGISTRY
--  These zones represent RED targets that players must destroy.
--  When all RED units inside the DESTROY_ZONE_<key> trigger zone are dead,
--  the zone permanently turns black / "Destroyed" on the F10 map.
--  These zones CANNOT be captured or flipped by any coalition.
--
--  ME SETUP: Place a trigger zone named DESTROY_ZONE_<key> over the target.
-- ─────────────────────────────────────────────────────────────────────────────
ABC.DESTROY_REGISTRY = {
    RedEWR1      = { display = "EWR Site 1" },
    RedEWR2      = { display = "EWR Site 2" },
    RedEWR3      = { display = "EWR Site 3" },
    RedEWR4      = { display = "EWR Site 4" },
    Factory      = { display = "Factory" },
    Factory2     = { display = "Factory 2" },
    Factory3     = { display = "Factory 3" },
    RadioTower   = { display = "Radio Tower" },
    RadioTower2  = { display = "Radio Tower 2" },
    RadioTower3  = { display = "Radio Tower 3" },
    CoastalGun   = { display = "Coastal Gun" },
    Marpi        = { display = "Marpi" },
    Kagman         = { display = "Kagman" },
    Isley          = { display = "Isley" },
    Japanese_Fleet = { display = "Japanese Fleet" },
}

-- ─────────────────────────────────────────────────────────────────────────────
--  INTERNAL STATE
-- ─────────────────────────────────────────────────────────────────────────────

ABC._state        = {}   -- per-key: { owner, ticks, lastScanner }
ABC._drawIDs      = {}   -- per-key: { circleID, textID }
ABC._destroyState = {}   -- per-key: { active, coalition, drawIDs }

local nextDrawID = 90000

local function newDrawID()
    nextDrawID = nextDrawID + 1
    return nextDrawID
end

-- ─────────────────────────────────────────────────────────────────────────────
--  HELPERS
-- ─────────────────────────────────────────────────────────────────────────────

local function log(msg)
    if ABC.DEBUG then env.info("[ABC] " .. tostring(msg)) end
end

local function coaSide(name)
    if name == "RED"  then return coalition.side.RED  end
    if name == "BLUE" then return coalition.side.BLUE end
    return coalition.side.NEUTRAL
end

local function dist2d(a, b)
    local dx = a.x - b.x; local dz = (a.z or a.y) - (b.z or b.y)
    return math.sqrt(dx * dx + dz * dz)
end

local function countGroundUnitsInZone(zoneName, coaFilter)
    local zd = trigger.misc.getZone(zoneName)
    if not zd then return 0 end
    local centre = zd.point
    local radius = zd.radius
    local count  = 0
    local coaSideID = coaSide(coaFilter)
    local grps = coalition.getGroups(coaSideID, Group.Category.GROUND)
    for _, grp in ipairs(grps or {}) do
        if grp and grp:isExist() then
            for _, u in ipairs(grp:getUnits()) do
                if u and u:isExist() and u:getLife() > 1 then
                    if dist2d(u:getPoint(), centre) <= radius then
                        count = count + 1
                    end
                end
            end
        end
    end
    return count
end

-- ─────────────────────────────────────────────────────────────────────────────
--  DRAWING
-- ─────────────────────────────────────────────────────────────────────────────

local function clearDraw(key)
    local ids = ABC._drawIDs[key]
    if ids then
        if ids.circle then pcall(function() trigger.action.removeMark(ids.circle) end) end
        if ids.text   then pcall(function() trigger.action.removeMark(ids.text)   end) end
    end
    ABC._drawIDs[key] = nil
end

local function drawZone(key)
    clearDraw(key)
    local reg  = ABC.REGISTRY[key]; if not reg then return end
    local st   = ABC._state[key];   if not st  then return end
    local zn   = "CAPTURE_ZONE_" .. key
    local zd   = trigger.misc.getZone(zn); if not zd then return end
    local ownerStr = st.owner or "NEUTRAL"

    local lineCol = ABC.COLOURS[ownerStr]      or ABC.COLOURS.NEUTRAL
    local fillCol = ABC.FILL_COLOURS[ownerStr]  or ABC.FILL_COLOURS.NEUTRAL

    local cID = newDrawID()
    local tID = newDrawID()
    local centre = { x = zd.point.x, y = 0, z = zd.point.z }

    trigger.action.circleToAll(-1, cID, centre, zd.radius,
        { lineCol[1], lineCol[2], lineCol[3], lineCol[4] },
        { fillCol[1], fillCol[2], fillCol[3], fillCol[4] },
        2, true)
    trigger.action.textToAll(-1, tID, centre,
        { lineCol[1], lineCol[2], lineCol[3], lineCol[4] },
        { 0, 0, 0, 0 },
        14, true, reg.display .. "\n[" .. ownerStr .. "]")

    ABC._drawIDs[key] = { circle = cID, text = tID }
end

-- ─────────────────────────────────────────────────────────────────────────────
--  DESTROY ZONE DRAWING
-- ─────────────────────────────────────────────────────────────────────────────

local function clearDestroyDraw(key)
    local dst = ABC._destroyState[key]
    if dst and dst.drawIDs then
        if dst.drawIDs.circle then pcall(function() trigger.action.removeMark(dst.drawIDs.circle) end) end
        if dst.drawIDs.text   then pcall(function() trigger.action.removeMark(dst.drawIDs.text)   end) end
    end
    if dst then dst.drawIDs = nil end
end

local function drawDestroyZone(key)
    clearDestroyDraw(key)
    local reg = ABC.DESTROY_REGISTRY[key]; if not reg then return end
    local dst = ABC._destroyState[key];    if not dst then return end
    local zn  = "DESTROY_ZONE_" .. key
    local zd  = trigger.misc.getZone(zn);  if not zd then return end

    local status  = dst.coalition or "RED"
    local lineCol = ABC.COLOURS[status]      or ABC.COLOURS.RED
    local fillCol = ABC.FILL_COLOURS[status]  or ABC.FILL_COLOURS.RED

    local cID = newDrawID()
    local tID = newDrawID()
    local centre = { x = zd.point.x, y = 0, z = zd.point.z }

    trigger.action.circleToAll(-1, cID, centre, zd.radius,
        { lineCol[1], lineCol[2], lineCol[3], lineCol[4] },
        { fillCol[1], fillCol[2], fillCol[3], fillCol[4] },
        2, true)

    local label = reg.display
    if status == "DESTROYED" then
        label = label .. "\nDestroyed"
    else
        label = label .. "\n[" .. status .. "]"
    end

    trigger.action.textToAll(-1, tID, centre,
        { lineCol[1], lineCol[2], lineCol[3], lineCol[4] },
        { 0, 0, 0, 0 },
        14, true, label)

    dst.drawIDs = { circle = cID, text = tID }
end

-- ─────────────────────────────────────────────────────────────────────────────
--  CAPTURE LOGIC
-- ─────────────────────────────────────────────────────────────────────────────

local function processCapture(key)
    local reg = ABC.REGISTRY[key]; if not reg then return end
    local st  = ABC._state[key];   if not st  then return end
    local zn  = "CAPTURE_ZONE_" .. key

    local redCount  = countGroundUnitsInZone(zn, "RED")
    local blueCount = countGroundUnitsInZone(zn, "BLUE")
    local currentOwner = st.owner

    -- Determine dominant coalition inside zone
    local dominant = nil
    if blueCount >= ABC.MIN_CAPTURE_UNITS and blueCount > redCount then dominant = "BLUE"
    elseif redCount >= ABC.MIN_CAPTURE_UNITS and redCount > blueCount then dominant = "RED"
    end

    if dominant and dominant ~= currentOwner then
        -- Accumulate capture ticks toward transition
        -- RED → NEUTRAL → BLUE  /  BLUE → NEUTRAL → RED
        if currentOwner == "NEUTRAL" then
            -- Direct capture from neutral
            if st.lastScanner == dominant then
                st.ticks = (st.ticks or 0) + 1
            else
                st.lastScanner = dominant
                st.ticks       = 1
            end
            if st.ticks >= ABC.CAPTURE_TICKS then
                ABC._setOwner(key, dominant)
            end
        else
            -- Must neutralise first
            if st.lastScanner == dominant then
                st.ticks = (st.ticks or 0) + 1
            else
                st.lastScanner = dominant
                st.ticks       = 1
            end
            if st.ticks >= ABC.CAPTURE_TICKS then
                ABC._setOwner(key, "NEUTRAL")
                st.ticks       = 0
                st.lastScanner = dominant
            end
        end
    else
        st.ticks       = 0
        st.lastScanner = nil
    end
end

function ABC._setOwner(key, newOwner)
    local reg = ABC.REGISTRY[key]; if not reg then return end
    local st  = ABC._state[key];   if not st  then return end

    local oldOwner = st.owner
    st.owner       = newOwner
    st.ticks       = 0
    st.lastScanner = nil
    reg.owner      = newOwner

    log(key .. ": " .. oldOwner .. " → " .. newOwner)

    -- Swap airbase coalition if applicable
    if reg.type == "airbase" and reg.airbaseName then
        local ab = Airbase.getByName(reg.airbaseName)
        if ab then
            pcall(function() ab:setCoalition(coaSide(newOwner)) end)
        end
    end

    drawZone(key)

    trigger.action.outText(
        string.format("%s has been captured by %s!", reg.display, newOwner), 20)
end

-- ─────────────────────────────────────────────────────────────────────────────
--  DESTROY ZONE SCAN
--  Counts RED units inside each DESTROY_ZONE_<key>. When 0 remain the zone
--  is permanently marked DESTROYED (black circle, cannot be recaptured).
-- ─────────────────────────────────────────────────────────────────────────────

local function checkDestroyed()
    for key, reg in pairs(ABC.DESTROY_REGISTRY) do
        local dst = ABC._destroyState[key]
        if dst and dst.active then
            local zn = "DESTROY_ZONE_" .. key
            local redCount = countGroundUnitsInZone(zn, "RED")
            if redCount == 0 then
                dst.active    = false
                dst.coalition = "DESTROYED"
                drawDestroyZone(key)
                log(key .. " destroyed")
                trigger.action.outText(
                    string.format("[TARGET DESTROYED]  %s has been neutralised.", reg.display), 20)
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  PUBLIC API
-- ─────────────────────────────────────────────────────────────────────────────

function ABC.getOwner(key)
    local st = ABC._state[key]
    return st and st.owner or nil
end

function ABC.forceCoalition(key, newOwner)
    if not ABC.REGISTRY[key] then return end
    ABC._setOwner(key, newOwner)
end

function ABC.setDestroyed(key)
    ABC._setOwner(key, "NEUTRAL")
end

function ABC.redrawAll()
    for key, _ in pairs(ABC.REGISTRY) do drawZone(key) end
    for key, _ in pairs(ABC.DESTROY_REGISTRY) do drawDestroyZone(key) end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  MAIN LOOP
-- ─────────────────────────────────────────────────────────────────────────────

local function captureLoop()
    for key, _ in pairs(ABC.REGISTRY) do
        processCapture(key)
    end
    checkDestroyed()
    return timer.getTime() + ABC.CHECK_INTERVAL
end

-- ─────────────────────────────────────────────────────────────────────────────
--  INITIALISATION
-- ─────────────────────────────────────────────────────────────────────────────

local function abcInit()
    log("=== WWII Marianas Airbase Capture initialising ===")

    for key, reg in pairs(ABC.REGISTRY) do
        ABC._state[key] = {
            owner       = reg.owner,
            ticks       = 0,
            lastScanner = nil,
        }
        drawZone(key)
    end

    -- Initialise destroy zones
    for key, reg in pairs(ABC.DESTROY_REGISTRY) do
        local zn = "DESTROY_ZONE_" .. key
        local startCoal = "RED"
        local isActive  = true
        local redCount  = countGroundUnitsInZone(zn, "RED")
        if redCount == 0 then
            startCoal = "DESTROYED"
            isActive  = false
        end
        ABC._destroyState[key] = {
            active    = isActive,
            coalition = startCoal,
            drawIDs   = nil,
        }
        drawDestroyZone(key)
    end

    timer.scheduleFunction(captureLoop, {}, timer.getTime() + ABC.CHECK_INTERVAL)
    log("=== ABC initialisation complete – " .. tostring(ABC.CHECK_INTERVAL) .. "s scan interval ===")
end

timer.scheduleFunction(function() abcInit(); return nil end, {}, timer.getTime() + 2)

trigger.action.outText("WWII Marianas Airbase Capture Script loaded.", 10)
-- =============================================================================
--  END OF SCRIPT
--
--  QUICK REFERENCE – ME SETUP
--  ──────────────────────────
--  1. Create CAPTURE trigger zones (capturable objectives):
--       CAPTURE_ZONE_RotaAirfield
--       CAPTURE_ZONE_AganaAirfield
--       CAPTURE_ZONE_CharonKanoa
--       CAPTURE_ZONE_Ushi
--       CAPTURE_ZONE_GurguanPoint
--       CAPTURE_ZONE_Pagan
--
--  2. Create DESTROY trigger zones (destroy-only targets):
--       DESTROY_ZONE_RedEWR1
--       DESTROY_ZONE_RedEWR2
--       DESTROY_ZONE_RedEWR3
--       DESTROY_ZONE_RedEWR4
--       DESTROY_ZONE_Factory
--       DESTROY_ZONE_Factory2
--       DESTROY_ZONE_Factory3
--       DESTROY_ZONE_RadioTower
--       DESTROY_ZONE_RadioTower2
--       DESTROY_ZONE_RadioTower3
--       DESTROY_ZONE_Marpi
--       DESTROY_ZONE_Kagman
--       DESTROY_ZONE_CoastalGun
--       DESTROY_ZONE_Isley
--       DESTROY_ZONE_Japanese_Fleet
--
--  3. Adjust REGISTRY owner and airbaseName values if needed.
-- =============================================================================
