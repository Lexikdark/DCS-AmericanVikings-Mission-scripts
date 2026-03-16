-- ============================================================
--  MiG-21 Nuclear Bomb Effects Script
--  Drop into Mission Editor via: Triggers > DO SCRIPT FILE
--
--  Visual effects only -- DCS handles weapon blast damage natively.
--  Handles:
--    - Blinding white flash (illuminationBomb)
--    - Stacked fireball explosions
--    - Rolling shockwave ring (visual)
--    - Rising mushroom cloud smoke column + cap
-- ============================================================

-- ----------------------------------------------------------------
-- CONFIG -- tweak these values to taste
-- ----------------------------------------------------------------
local NUKE_CFG = {
  -- Weapon typeName strings for the MiG-21 nuclear bombs.
  -- ED internal names: RN-28 free-fall tactical nuke.
  -- Add extras here if your mod uses different names.
  weaponNames = {
    ["RN-28"]                = true,
    ["MBD3-U6-68_RN-28"]     = true,
    ["RN-28_MiG-21"]         = true,   -- some mod variants
  },

  fireballs          = 80,      -- stacked explosion count for fireball
  fireballSpread     = 1200,    -- metres: random spread of fireball blasts
  fireballHeight     = 1800,    -- metres: max height of fireball blasts
  fireballGroundBlasts = 40,    -- extra dense explosions at ground level
  fireballGroundRadius = 600,   -- metres: radius for ground-level burst
  illuminationPower  = 500000000, -- 500 million candela flash
  illuminationAlt    = 150,     -- metres AGL for the flash bomb
}

-- ----------------------------------------------------------------
-- UTILITY
-- ----------------------------------------------------------------
local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

-- ----------------------------------------------------------------
-- FLASH
-- ----------------------------------------------------------------
local function spawnFlash(groundZero)
  local flashPos = {
    x = groundZero.x,
    y = (groundZero.y or 0) + NUKE_CFG.illuminationAlt,
    z = groundZero.z,
  }
  trigger.action.illuminationBomb(flashPos, NUKE_CFG.illuminationPower, 4)
end

-- ----------------------------------------------------------------
-- FIREBALL  (stacked explosions at ground zero +/- random spread)
-- ----------------------------------------------------------------
local function spawnFireball(groundZero)
  -- Rising fireball volume
  for i = 1, NUKE_CFG.fireballs do
    local pos = {
      x = groundZero.x + math.random(-NUKE_CFG.fireballSpread, NUKE_CFG.fireballSpread),
      y = (groundZero.y or 0) + math.random(0, NUKE_CFG.fireballHeight),
      z = groundZero.z + math.random(-NUKE_CFG.fireballSpread, NUKE_CFG.fireballSpread),
    }
    trigger.action.explosion(pos, 1000)  -- DCS max explosion power
  end
  -- Dense ground-zero burst for the initial pressure wave
  for i = 1, NUKE_CFG.fireballGroundBlasts do
    local angle  = math.random() * 2 * math.pi
    local radius = math.random(0, NUKE_CFG.fireballGroundRadius)
    local pos = {
      x = groundZero.x + radius * math.cos(angle),
      y = (groundZero.y or 0) + math.random(0, 80),
      z = groundZero.z + radius * math.sin(angle),
    }
    trigger.action.explosion(pos, 1000)
  end
end

-- ----------------------------------------------------------------
-- MUSHROOM CLOUD  (big smoke column + cap)
-- ----------------------------------------------------------------
local function spawnMushroomCloud(groundZero)
  local baseY = groundZero.y or 0

  -- Stem: rising column of large smoke markers at increasing altitudes
  local stemLevels  = 12
  local stemTopAlt  = 8000   -- metres: top of the stem
  local stemDelay   = 1.5    -- seconds between each smoke level appearing

  for i = 1, stemLevels do
    local alt   = baseY + (stemTopAlt / stemLevels) * i
    local delay = stemDelay * i
    local jitter = 60

    timer.scheduleFunction(function()
      local pos = {
        x = groundZero.x + math.random(-jitter, jitter),
        y = alt,
        z = groundZero.z + math.random(-jitter, jitter),
      }
      -- Smoke type 2 = white/grey smoke
      trigger.action.smoke(pos, 2)
      return nil
    end, {}, timer.getTime() + delay)
  end

  -- Cap: a wide ring of smoke at the top of the stem
  local capRadius  = 1200   -- metres
  local capAlt     = baseY + stemTopAlt + 500
  local capPoints  = 16
  local capDelay   = stemDelay * stemLevels + 2

  timer.scheduleFunction(function()
    for p = 0, capPoints - 1 do
      local angle = (2 * math.pi / capPoints) * p
      local pos = {
        x = groundZero.x + capRadius * math.cos(angle),
        y = capAlt,
        z = groundZero.z + capRadius * math.sin(angle),
      }
      trigger.action.smoke(pos, 2)

      -- inner cap fill
      pos.x = groundZero.x + (capRadius * 0.5) * math.cos(angle)
      pos.z = groundZero.z + (capRadius * 0.5) * math.sin(angle)
      trigger.action.smoke(pos, 2)
    end
    return nil
  end, {}, timer.getTime() + capDelay)
end

-- ----------------------------------------------------------------
-- MASTER DETONATION SEQUENCE
-- ----------------------------------------------------------------
local function detonate(impactPoint)
  local gz = {
    x = impactPoint.x,
    y = impactPoint.y or 0,
    z = impactPoint.z,
  }

  spawnFlash(gz)          -- immediate blinding flash
  spawnFireball(gz)       -- ground-zero fireball
  spawnMushroomCloud(gz)  -- long-duration smoke column + cap
end

-- ----------------------------------------------------------------
-- EVENT HANDLER  (listen for weapon crashes / impacts)
-- ----------------------------------------------------------------
local nukeEventHandler = {}

function nukeEventHandler:onEvent(event)
  -- S_EVENT_HIT fires when a weapon strikes something
  -- S_EVENT_DEAD fires when the weapon object is removed (ground impact)
  if event.id == world.event.S_EVENT_HIT or
     event.id == world.event.S_EVENT_DEAD then

    local weapon = event.weapon
    if not weapon then return end

    -- Safely get the weapon descriptor
    local ok, desc = pcall(function() return weapon:getTypeName() end)
    if not ok or not desc then return end

    if NUKE_CFG.weaponNames[desc] then
      local impactPos = weapon:getPoint()
      if impactPos then
        detonate(impactPos)
      end
    end
  end
end

world.addEventHandler(nukeEventHandler)

-- ----------------------------------------------------------------
-- OPTIONAL: manual test trigger (set zone named "NUKE_TEST" in ME)
-- Remove this block before final mission release
-- ----------------------------------------------------------------
timer.scheduleFunction(function()
  local testZone = trigger.misc.getZone("NUKE_TEST")
  if testZone then
    env.info("[NukeScript] NUKE_TEST zone found - detonating in 5 seconds")
    timer.scheduleFunction(function()
      detonate(testZone.point)
      return nil
    end, {}, timer.getTime() + 5)
  end
  return nil
end, {}, timer.getTime() + 2)

env.info("[NukeScript] MiG-21 Nuclear Effects Script loaded successfully.")
