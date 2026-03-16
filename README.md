# DCS-AmericanVikings-Mission-scripts

Simple Repo for the Scripts we at AmericanVikings DCS Multiplayer server make and use in our missions.

---

## Table of Contents

- [Convoy Systems](#convoy-systems)
  - [BLUE-ResupplyConvoySpawn v5.7.0](#blue-resupplyconvoyspawn-v570)
  - [RedAutomatedConvoySystem v4.0](#redautomatedconvoysystem-v40)
- [DGSS — Dynamic Ground Spawner System](#dgss--dynamic-ground-spawner-system)
  - [DGSS Core v4.3](#dgss-core-v43)
  - [SYRIA_DGSS v4.3](#syria_dgss-v43)
  - [DGSS-CSAR+Lives v5.1](#dgss-csarlives-v51)
  - [DGSS-CTLD-JTAC v7.2](#dgss-ctld-jtac-v72)
  - [DGSS-Leaderboard v3.5](#dgss-leaderboard-v35)
  - [DGSS-IED System v6.2 (Road Placement)](#dgss-ied-system-v62-road-placement)
  - [DGSS Target of Opportunity (TOO) v5.9](#dgss-target-of-opportunity-too-v59)
  - [SYRIA ISIS TOO Script v1.0](#syria-isis-too-script-v10)
- [IADS](#iads)
  - [RED_BLUE_IADS_Intercept](#red_blue_iads_intercept)
- [Mission Systems](#mission-systems)
  - [AirBaseCapture (Syria) v1.0](#airbasecapture-syria-v10)
  - [MissionStatePersistence v4.0](#missionstatepersistence-v40)
  - [RedCoalitionLock](#redcoalitionlock)
- [WWII Marianas Mission Scripts](#wwii-marianas-mission-scripts)
  - [WWII Marianas CAP / CTLD / GCI v1.0](#wwii-marianas-cap--ctld--gci-v10)
  - [WWII Marianas DGSS v1.0](#wwii-marianas-dgss-v10)
  - [WWII Marianas Red Convoy Spawn v1.0](#wwii-marianas-red-convoy-spawn-v10)
  - [WWII Marianas Airbase Capture v1.0](#wwii-marianas-airbase-capture-v10)
- [Weather](#weather)
  - [DCS Dynamic Weather Cycle](#dcs-dynamic-weather-cycle)
  - [DCS Dynamic Weather Preset](#dcs-dynamic-weather-preset)
- [Race Script](#race-script)
  - [RaceScript v4.0](#racescript-v40)
- [Nuke Script](#nuke-script)
  - [MiG-21 Nuclear Bomb Effects](#mig-21-nuclear-bomb-effects)

---

## Convoy Systems

### BLUE-ResupplyConvoySpawn v5.7.0

**File:** `convoy-systems/BLUE-ResupplyConvoySpawn/BLUE-ResupplyConvoySpawn v5.7.0.lua`
**Docs:** `BLUE-ResupplyConvoySpawn_DOCS.html`

Manages Blue coalition ground resupply convoys that spawn from rear airbases and drive to forward operating bases (FOBs). Configured for the Syria theatre using Israeli airbases as origin points.

**Key features:**
- Spawns logistics convoys from a configurable list of source airbases/zones toward defined FOB destinations
- **Radio menu interface** — players can trigger convoy spawns via the F10 radio menu
- **Automatic player location detection** for context-aware spawn selection
- Multiple vehicle template compositions to vary convoy appearance and capability
- Convoys follow DCS road networks; waypoints are set automatically at departure and destination zones
- Route variation config: short (40%), medium (35%), long (25%) with procedural offset waypoints
- `maxActiveConvoys = 10` — caps simultaneous active convoys
- `cooldownTime = 1800` (30 min per-template cooldown)
- `updateInterval = 300` (5 min — v5.7.0 performance optimisation)
- **Automatic warehouse resupply on arrival** at destination FOBs
- Cleans up destroyed or stalled convoys and respawns replacements to maintain persistent logistics pressure
- Leaderboard integration (`convoyRequesters` tracking cross-script)
- Integrates with CTLD for supply delivery mechanics at FOBs

---

### RedAutomatedConvoySystem v4.0

**File:** `convoy-systems/RedAutomatedConvoySystem/RedAutomatedConvoySystem(v4.0).lua`
**Docs:** `RedAutomatedConvoySystem_DOCS.html`

Autonomous Red-force convoy system that continuously generates enemy logistics and reinforcement columns across the map without mission-editor coordination.

**Key features:**
- 20 configurable convoy vehicle templates (infantry, armour, mixed logistics)
- `NUM_CONVOY_POINTS = 40` — defines the maximum number of named ConvoyZone trigger zones the script will read from the mission (increase this constant to support larger maps)
- `MAX_CONVOYS = 20` — caps simultaneous active Red convoys
- `INITIAL_CONVOYS = 5` — number of convoys spawned immediately on script start
- `STAGGER_DELAY = 120` sec between initial convoy launches
- `CONVOY_SPEED = 22` m/s default movement speed
- Minimum travel distance filter (`MIN_TRAVEL_DISTANCE = 35 nm`) prevents trivially short routes
- Stall detection (`STALL_TIMEOUT = 300` sec, `STALL_CHECK_THRESHOLD = 10` m): convoys that stop moving are automatically despawned and replaced
- Randomised origin/destination pairing from available ConvoyZones each spawn cycle

---

## DGSS — Dynamic Ground Spawner System

The DGSS family of scripts provides persistent, dynamic ground combat for DCS multiplayer missions. Ground units are spawned, managed, and cleaned up automatically, creating a living battlefield without requiring the mission designer to pre-place hundreds of static groups.

---

### DGSS Core v4.3

**File:** `dgss/DGSS/DGSS_v4.3.lua`
**Docs:** `DGSS_v4.3_DOCS.html`

The original Afghanistan-theatre DGSS. Spawns randomised Red and Blue ground forces from a library of 20+ unit templates across a set of named spawn zones. Forms the foundation that all theatre-specific DGSS variants are built on.

**Key features:**
- Shuffle-bag template selection ensures all templates cycle before repeating
- Per-zone spawn count and faction control configurable in the header config block
- Auto-generates F10 map markers at active spawn sites showing force composition
- Periodic cleanup of dead units to maintain mission performance
- Engagement detection: spawned groups are tasked to move toward and engage the opposing coalition

---

### SYRIA_DGSS v4.3

**File:** `dgss/SYRIA-DGSS/SYRIA_DGSS_v4.3.lua`
**Docs:** `SYRIA_DGSS_v4.3_DOCS.html`

Syria-theatre variant of the DGSS, fully replacing the Afghanistan unit set with Syrian Arab Army (SAA) and regional insurgent forces. Designed for use on the DCS Syria map.

**Key features:**
- **20 Red force templates** including T-72B MBT columns, BMP-2 mechanised infantry, ZSU-23-4 Shilka, BTR-80 APC groups, and mixed infantry/armour assault packages
- **5 dedicated RED_SAM_SHORAD groups** (Ins_2, Ins_10, Ins_14, Ins_17, Ins_20) each built around the Osa 9A33 ln radar-guided SAM system for realistic short-range air defence
- 18 named spawn zones distributed across the Syria map
- Blue engagement code removed — script manages Red spawns only; Blue forces are handled separately per mission design
- Same shuffle-bag spawning, map markers, and cleanup mechanics as DGSS Core

---

### DGSS-CSAR+Lives v5.1

**File:** `dgss/CSAR+lives/DGSS-CSAR+Lives_v5.1.lua`
**Docs:** `DGSS-CSAR+Lives_v5.1_DOCS.html`

Adds a Combat Search and Rescue (CSAR) layer and a player-lives system on top of the DGSS framework.

**Key features:**
- Tracks pilot ejections and crash sites; spawns a downed-pilot unit at the crash location
- CSAR helicopters can locate pilots via smoke signal and extract them to designated drop-off zones
- **CSAR aircraft whitelist:** UH-1H, Mi-8MT, Mi-24P, SA342 variants, CH-47F, MH-6J, AH-6J, C-130J-30, TF-51D
- **Pickup limits:** max 7.5 m/s (≈10 kts) speed and 15.2 m AGL (≈50 ft) altitude for extraction
- Successful extraction awards the rescued pilot a respawn credit
- **Player lives system:** `defaultLives = 5`, `maxLives = 5` per session; ejection or death decrements the count; successful CSAR rescue restores a life
- Separate radio menus for **Downed Pilots** vs **Convoy Survivors**
- `dropOffZones` table configured for Syrian airbase locations (Khmeimim, Ramat David, Haifa, etc.) plus `CARRIER_GROUP` drop-off zone
- MGRS and DM coordinate display for downed pilot locations
- `INCIDENT_COOLDOWN = 30` sec anti-duplicate protection
- Live count and rescue status broadcast via DCS in-game messages

---

### DGSS-CTLD-JTAC v7.2

**File:** `dgss/CTLD-JTAC/DGSS-CTLD-JTACv7.2.lua`
**Docs:** `DGSS-CTLD-JTAC_DOCS.html`

Integrates the CTLD (Combined Transport & Loading) troop-transport framework with an automated JTAC laser designation and radio management system.

**Key features:**
- Transport helicopters can load/unload CTLD infantry and vehicle crates at FOBs and forward zones
- Automatically spawns JTAC units at active combat zones; each JTAC laser-designates the nearest valid Red ground target
- **9-line CAS callout generation** — broadcasts formatted 9-line briefs to attacking players
- **Player-controlled target selection** (Next/Previous) with manual override
- JTAC callsigns, laser codes, and radio frequencies are assigned per zone and broadcast to players
- Hard limits: max 10 JTAC teams + 10 vehicles simultaneously
- `SCAN_RADIUS = 10000` m engagement scan range
- FOB and airbase zone tables updated for the Syria map (Israeli and Syrian bases)
- Integrates with DGSS spawn events — new Red contacts trigger JTAC tasking updates
- JTAC units are cleaned up automatically when their zone is cleared

---

### DGSS-Leaderboard v3.5

**File:** `dgss/DGSS-Leaderboard 3.5.lua`
**Docs:** `dgss/DGSS-Leaderboard_3.5_DOCS.html`

Real-time multiplayer kill and score leaderboard displayed via the DCS radio menu.

**Key features:**
- Tracks ground kills, air kills, friendly-fire incidents, **CSAR rescues**, and **logistics deliveries** (slingload + warehouse) per pilot
- Leaderboard updates on a configurable timer and on significant kill events
- Scores persist for the duration of the server session
- Theatre-specific supply bases configured (e.g. KANDAHAR, FOB_URGOON as supply origins; 10 distribution bases)
- Outputs formatted standings visible to all players via the radio menu

---

### DGSS-IED System v6.2 (Road Placement)

**File:** `dgss/IED_System (Road-placement)/DGSS-IED_System 6.2_RoadPlacement.lua`
**Docs:** `dgss/IED_System (Road-placement)/DGSS-IED_System_6.2_DOCS.html`

Dynamically plants Improvised Explosive Devices along road networks within defined trigger zones, threatening convoys and ground movements.

**Key features:**
- Reads a list of named IED zones from the mission editor (`ZONE_NAME_PATTERN = "_IED_AREA"` auto-detection); places concealed IED objects on nearby roads
- `USE_ROUTE_MODE = true` — pathfinds between base pairs rather than random zone placement
- `MAX_ACTIVE_IEDS = 75` — global cap on simultaneous active IEDs
- `EXPLOSION.power = 500` (kg TNT equivalent blast)
- `iedsPerZone = 2`, `minIEDSpacing = 2000` (2 km minimum between IEDs)
- Base exclusion zones (12 Afghanistan bases) — IEDs will not spawn near friendly bases
- IEDs detonate on proximity to any ground vehicle within coalition filter rules
- Dead IEDs are tracked; zones can be re-seeded on a timer to maintain persistent threat
- Works alongside the convoy systems to create realistic route-clearance requirements

---

### DGSS Target of Opportunity (TOO) v5.9

**File:** `dgss/TOO scripts/DGSS_TOO_System v5.9.lua`
**Docs:** `dgss/TOO scripts/DGSS_TOO_System_v5.9_DOCS.html`

Standalone dynamic target spawner and strike-tasking system. Creates its own target groups and presents them to Blue air assets as Targets of Opportunity.

**Key features:**
- Spawns 30 unique target group templates (buildings + ground units) into trigger zones independently — **not** a DGSS overlay; this is a self-contained spawner
- Presents each target via radio menu with a formatted **9-line CAS brief** (target type, grid reference, recommended ordnance)
- `minTargetsOnMap = 8` — auto-maintains a minimum number of active targets by respawning replacements
- Targets are cleared from the list once destroyed; zones are re-seeded to maintain persistent strike tasking
- Auto-cleanup of destroyed targets to maintain mission performance
- Compatible with DCS World 2.5+ and requires MIST.lua

---

### SYRIA ISIS TOO Script v1.0

**File:** `dgss/TOO scripts/SYRIA_ISIS_TOO_Script.lua`
**Docs:** `dgss/TOO scripts/SYRIA_ISIS_TOO_Script_DOCS.html`

Syria-theatre variant of the TOO System, spawning ISIS/Daesh target groups across Syria-map trigger zones. Each target is composed of static buildings and dynamic ground units.

**Key features:**
- **30 ISIS-themed templates** (e.g. `ISIS_Raqqa_Cell`, `ISIS_Deir_Ez_Zor_Cell`, `ISIS_Palmyra_Fighters`, `ISIS_Homs_Garrison`, `ISIS_Aleppo_Ambush`, `ISIS_Hama_Defense`, `ISIS_Tabqa_Cache`)
- Per-zone spawn counting (`zoneSpawnCount`) allows multiple groups per zone
- Heavy SHORAD presence: ZSU-23-4 Shilka (often 2 per target), Grad-URAL MLRS, 2B11 mortars, HL_B8M1 rocket launchers
- Civilian/SVBIED elements: `LAZ Bus` appears in some templates
- Same radio-menu 9-line CAS brief system, auto-cleanup, and minimum-targets-on-map maintenance (`minTargetsOnMap = 8`)
- Compatible with DCS World 2.5+ and requires MIST.lua

---

## IADS

### RED_BLUE_IADS_Intercept

**File:** `iads/RED_BLUE_IADS_Intercept.lua`
**Docs:** `iads/RED_BLUE_IADS_Intercept_DOCS.html`

Dual-coalition Integrated Air Defence System management script. Coordinates both Red and Blue IADS networks using the Skynet-IADS framework to produce realistic, networked air-defence behaviour.

**Key features:**
- Configures Red SAM sites, EWR (Early Warning Radar) units, and command nodes into a Skynet IADS network
- Mirrors the same network architecture for the Blue coalition
- SAM sites go into autonomous search-and-engage mode only when their EWR chain is intact; destroying EWR nodes degrades the network
- **Low-altitude jet immunity:** `SAM_LOW_JET_IMMUNITY_AGL = 75` m — jets below 75 m AGL are invisible to non-SHORAD Red SAMs (major gameplay mechanic for low-level strike)
- **ARM defence system:** SAMs shut down radar for 45 sec on ARM detection, relocate 800 m if mobile; neighbouring SAMs suppress for 20 sec
- **Red AI intercept flights:** script spawns late-activate Red fighter pairs per sector zone for automated scramble response
- Intercept coordination: fighter CAP and SAM systems are de-conflicted so airborne interceptors don't get targeted by friendly SAMs
- Point-defence and area-defence SAM roles are assigned separately for realistic layered coverage
- `SAM_ENGAGE_SHARE_RANGE = 180000` (180 km), `PKill_BASE = 0.92`
- Fully configurable unit name lists in the header to adapt to any mission's group naming convention
- Requires MIST.lua

---

## Mission Systems

### AirBaseCapture (Syria) v1.0

**File:** `mission-systems/AirBaseCapture/SYRIA_AirbaseCapture.lua`
**Docs:** `mission-systems/AirBaseCapture/SYRIA_AirbaseCapture_DOCS.html`
**Version:** 1.0 (2026-02-18)

Dynamic airbase ownership and capture system for the Syria map. Tracks coalition control of key airbases and transitions ownership when ground forces secure the surrounding area. **Standalone** — no other script required.

**Key features:**
- Each monitored airbase has a defined capture zone; when Red or Blue ground units are the only living forces inside, the base flips coalition
- `CHECK_INTERVAL = 180` sec (3 min scan interval), `CAPTURE_TICKS = 3` consecutive scans required to confirm capture
- **Four states:** RED, BLUE, NEUTRAL, and **DESTROYED**
- Capture triggers: airbase ATC frequency changes, map marker updates, and optionally supply-convoy destination unlocks
- Contested state: if both coalitions have units inside a zone simultaneously the base is marked as contested and neither side gains control
- **FARP registration API** — supports Forward Arming and Refuelling Points in addition to full airbases
- **Public API:** `ABC.getOwner`, `ABC.forceCoalition`, `ABC.setDestroyed`, `ABC.registerFARP`, `ABC.redrawAll`, `ABC.onCapture`
- Configurable list of airbase names and zone names to adapt the script to different maps or mission layouts

---

### MissionStatePersistence v4.0

**File:** `mission-systems/MissionStatePersistence/MissionStatePersistence(v.4.0).lua`
**Docs:** `mission-systems/MissionStatePersistence/MissionStatePersistence_DOCS.html`

Serialises and restores critical mission state across DCS server restarts, preventing progress loss when the server cycles the mission.

**Key features:**
- Saves CJTF-BLUE groups and airbase warehouses to **two Lua state files** on the server filesystem: `MissionGroups.lua` and `MissionWarehouses.lua`
- `saveInterval = 600` (10 min default auto-save interval)
- State files are written on the configurable auto-save interval and on clean server shutdown
- On mission load, the script detects existing state files and restores all saved values before any other scripts run
- Safe fallback: if no state files are found (first run) the mission starts fresh with default values
- Requires MIST.lua (no MOOSE dependency)

---

### RedCoalitionLock

**File:** `mission-systems/RedCoalitionLock/RedCoalitionLock.lua`
**Docs:** `mission-systems/RedCoalitionLock/RedCoalitionLock_DOCS.html`

Prevents human players from occupying Red coalition slots on a multiplayer server. Red is reserved for AI-only forces.

**Key features:**
- Periodically scans all connected players using `net.*` functions; anyone found on Red (coalition 1) is forced to Spectators
- `CHECK_INTERVAL = 5` sec scan frequency
- Custom kick message sent to the affected player via `net.send_chat_to`
- Multiplayer only — silently skips enforcement in single-player or ME preview (no errors)
- **Standalone** — no dependencies, load via DO SCRIPT FILE at Mission Start

---

## WWII Marianas Mission Scripts

A complete suite of scripts for a WWII-era mission on the DCS Marianas map. Blue coalition (US forces) vs Red coalition (Imperial Japanese forces). All scripts except the Airbase Capture script require MIST.

**Docs:** `WorldWar2 mission Scripts/WWII_Marianas_Mission_Guide.html` — comprehensive HTML guide covering all four scripts, ME setup, zone checklists, and group naming conventions.

**Load order in Mission Editor:**
1. `mist_4_5_126.lua`
2. `WWII_Marianas_CAP_CTLD_GCI.lua`
3. `WWII_Marianas_DGSS.lua`
4. `WWII_Marianas_RedConvoySpawn.lua`
5. `WWII_Marianas_AirbaseCapture.lua`

---

### WWII Marianas CAP / CTLD / GCI v1.0

**File:** `WorldWar2 mission Scripts/WWII_Marianas_CAP_CTLD_GCI.lua`

Combined air-combat, logistics, and ground-controlled intercept script with six integrated sections:

**Section A — Red CAP Flights:**
- Auto-respawns Red patrol groups (`CAPNorth`, `CAPSouth`, `CAPEast`, `CAPWest`, etc.)
- `capRespawnDelay = 120` sec, `capCheckInterval = 60` sec
- Staggered spawn timers for `CAPNorth2`/`CAPNorth3` (300 sec delay)

**Section B — Red Fighter-Bombers:**
- Delayed-spawn Red attack aircraft (`FighterBomber`, `FighterBomber2`, `Bombers`, `Bombers2`)
- `bomberRespawnDelay = 1800` sec (30 min), respawns after destruction or landing
- Landing detection triggers cleanup and respawn cycle

**Section C — Blue Radio-Call Support Spawning (F10 Menu):**
- Blue players can spawn support flights via the F10 radio menu (`NorthCAP`, `HomeCAP`, `Bomb_CoastalGun`, `Bomb_RadioTower`, `Bomb_RotaAirfield`, etc.)
- One active group per template — duplicates are blocked
- Destroy menu to manually remove active support groups
- Auto-cleanup of landed support aircraft

**Section D — Aircraft Cleanup System:**
- Monitors all CAP and bomber groups for stale/dead aircraft
- Destroys aircraft below 15% health, below 5% fuel, or stalling at altitude
- `maxFlightTime = 5400` sec (90 min) — long-lived groups are forcibly cleaned up

**Section E — Lightweight TF-51D CTLD:**
- Transport logistics using the TF-51D Mustang (the only whitelisted transport)
- **Infantry:** load 1-3 infantry squads at `BlueCTLD` zone, drop anywhere, pick up within 50 m
- **Vehicle crates:** spawn, sling-load, and assemble M4 Tractor (2 crates), M2A1 Halftrack (2 crates), or M4 Sherman (3 crates)
- Full F10 radio menu for Load / Drop / Pickup / Assemble / Check Cargo operations
- Logistics group prefix: `LogiTF51D`

**Section F — GCI Intercept System:**
- Zone-based scramble and RTB system for both Red and Blue fighter squadrons
- Red squadrons: SHIDEN (Rota), HAYATE (North), RAIDEN (South)
- Blue squadrons: HELLCAT (Agana), CORSAIR (North)
- `UPDATE_INTERVAL = 10` sec, `GCI_FUEL_RTB_THRESHOLD = 0.20` (20% fuel triggers RTB)
- Fighters scramble when hostile aircraft enter their zone, RTB when threats clear
- `SCRAMBLE_THREAT_BUFFER = 30000` m, `INTERCEPT_LEASH_BUFFER = 60000` m

---

### WWII Marianas DGSS v1.0

**File:** `WorldWar2 mission Scripts/WWII_Marianas_DGSS.lua`

WWII Marianas variant of the Dynamic Ground Spawner System. Spawns Imperial Japanese Army ground forces across the island battlefields.

**Key features:**
- **20 Japanese templates** using WWII DCS assets: `soldier_mauser98` infantry, `Type_89_I_Go` medium tanks, `Type_98_Ke_Ni` light tanks, `Type_94_Truck` logistics, and `Type_96_25mm_AA` anti-aircraft guns
- Templates of 6-8 units each, including: IJA Patrol, Ke-Ni Scout, I-Go Platoon, AA Position, Mixed Armour, Beach Defenders, Supply Convoy, Full Armour Section, and more
- 18 named trigger zones (`ZONE1` – `ZONE18`) with configurable min/max group limits per zone (default: 1-3 per zone)
- Shuffle-bag template selection ensures all 20 templates cycle before repeating
- `MAX_SPAWNS_PER_CYCLE = 3`, `CHECK_ZONES_INTERVAL = 300` sec
- F10 map markers at each spawn, auto-removed on group death
- Automatic dead group cleanup (`CLEANUP_INTERVAL = 120` sec)
- Country: Japan (RED side)
- Requires MIST

---

### WWII Marianas Red Convoy Spawn v1.0

**File:** `WorldWar2 mission Scripts/WWII_Marianas_RedConvoySpawn.lua`

Autonomous Japanese convoy system for the Marianas map. Continuously generates enemy logistics columns between island zones.

**Key features:**
- **15 WWII Japanese convoy templates** using Type_94_Truck, Type_89_I_Go, Type_98_Ke_Ni, and infantry
- `MAX_CONVOYS = 12`, `INITIAL_CONVOYS = 3` (staggered at `STAGGER_DELAY = 120` sec)
- `CONVOY_SPEED = 18` m/s (~65 km/h)
- 20 named convoy zones (`ConvoyZone1` – `ConvoyZone20`)
- `MIN_TRAVEL_DISTANCE = 32000` m (~17 nm) minimum route length
- Route building: Off Road → On Road → Off Road waypoints
- Stall detection: `STALL_TIMEOUT = 300` sec — stuck convoys auto-despawn and are replaced
- `SPAWN_LOOP_INTERVAL = 180` sec between spawn attempts
- Country: Japan (RED side)
- Requires MIST

---

### WWII Marianas Airbase Capture v1.0

**File:** `WorldWar2 mission Scripts/WWII_Marianas_AirbaseCapture.lua`

Dynamic airbase ownership and objective destruction system for the Marianas WWII mission. **Standalone** — no MIST or MOOSE required.

**Key features:**
- **Capture Zone System** — state machine: RED ↔ NEUTRAL ↔ BLUE, requiring consecutive scan ticks to confirm capture
  - `CHECK_INTERVAL = 180` sec (3 min), `CAPTURE_TICKS = 3` consecutive scans, `MIN_CAPTURE_UNITS = 1`
  - F10 map coloured circle + text markers per zone (colour-coded by owner)
  - Airbase coalition swap on capture (ATC frequency changes)
- **Destroy Zone System** — one-way RED → DESTROYED when all RED units inside are killed
  - Permanently turns black on F10 map with "Destroyed" label
  - Cannot be captured or recaptured
- **Capture Zone Registry (6 zones):**
  - RED: Rota Airfield, Charon Kanoa, Ushi, Gurguan Point, Pagan
  - BLUE: Agana Airfield
- **Destroy Zone Registry (15 zones):**
  - EWR Sites 1-4, Factory 1-3, Radio Tower 1-3, Coastal Gun, Marpi, Kagman, Isley, Japanese Fleet
- **Colour palette** matches the Syria mission: RED outline/fill, BLUE outline/fill, NEUTRAL white/gray, DESTROYED black
- **Public API:** `ABC.getOwner()`, `ABC.forceCoalition()`, `ABC.setDestroyed()`, `ABC.redrawAll()`
- **Total ME trigger zones:** 6 × `CAPTURE_ZONE_*` + 15 × `DESTROY_ZONE_*` = 21 zones

---

## Weather

### DCS Dynamic Weather Cycle

**File:** `weather/DCS_DynamicWeatherCycle.lua`
**Docs:** `weather/DCS_DynamicWeatherCycle_DOCS.html`

Narrative weather stage system that broadcasts ATIS-style weather reports aligned with DCS's built-in dynamic atmosphere engine. Does **not** set weather — it reads live conditions and labels them for pilots.

**Key features:**
- Named weather stages: Clear → Building → Thunderstorm → Clearing → Overcast → Clear (12-hour cycle)
- Reads live wind, pressure, and temperature via `atmosphere.*` every 30 seconds
- **ATIS broadcasts** every `ATIS_INTERVAL = 300` sec (5 min) with wind speed/direction, QNH, temperature, and current stage
- `WARN_LEAD_TIME = 1800` sec (30 min) advance warnings before storm/clearing stage transitions
- Wind trend tracking: reports rising/falling speed and veering/backing direction
- On-demand ATIS via User Flag trigger (`ATIS_FLAG = 10`)
- `BROADCAST_COALITION = 2` (Blue only by default)
- `FORCE_PRESET` option to lock a specific weather preset for testing
- **Standalone** — no dependencies, requires ME Atmosphere Type = Dynamic

---

### DCS Dynamic Weather Preset

**File:** `weather/DCS_DynamicWeatherPreset.lua`
**Docs:** `weather/DCS_DynamicWeatherPreset_DOCS.html`

Generates a randomised 6-node weather forecast at mission start, giving pilots a full 12-hour outlook with meteorologically plausible transitions.

**Key features:**
- **6 weather archetypes:** CLEAR, BUILDING, STORMY (Thunderstorm), OVERCAST, CLEARING, FOGGY — each with defined ranges for wind, visibility, QNH, temperature, cloud presets, and hazards
- Random starting state seeded from the real-world clock; walks through realistic transition rules for the remaining 5 nodes
- `NODE_DURATION_HOURS = 2`, `NODE_COUNT = 6` — covers a full 12-hour mission cycle
- Each node includes: VFR/MVFR/IFR/LIFR category, wind description, cloud description, visibility, and pilot NOTAMs
- ATIS broadcasts every `ATIS_INTERVAL = 300` sec with live atmosphere data alongside the forecast
- Wind history trend analysis (`WIND_HISTORY = 6` samples)
- `BROADCAST_COALITION = 2` (Blue only by default)
- **Standalone** — no dependencies, requires ME Atmosphere Type = Dynamic

---

## Race Script

### RaceScript v4.0

**File:** `RaceScript/RaceScript_V4.0.lua`
**Docs:** `RaceScript/RaceScript_V4.0_Guide.html`

Air race timing system that tracks players through a series of gates with high-precision stopwatch timing. Created by Lexik"ROBOT"dark & Eilliem"Six'O'Clock" for the American Vikings server.

**Key features:**
- **20 gate zones** (`Gate 1` – `Gate 20`) plus `StartingLine` and `FinishLine` trigger zones
- Per-player stopwatch with hundredths-of-a-second precision
- `altitudeLimit = 250` m AGL — players must stay below this altitude to register gate passes
- `penaltyTime = 5` sec per missed gate
- 2+ missed gates in a single race nullifies the run — pilot must restart
- Real-time feedback when gates are missed (tells the player which gate)
- **Per-group "Reset My Race"** radio command (F10 menu) — scoped to the requesting group only
- Race times exported to `PlayerTimesLog.txt` in the DCS Saved Games folder
- Anti-duplicate finish protection — sentinel flag prevents re-entry during the 5-second cleanup delay
- Aircraft type tracking for leaderboard categorisation
- All race state tables are globally scoped to survive script reloads mid-mission
- **Standalone** — no dependencies

---

## Nuke Script

### MiG-21 Nuclear Bomb Effects

**File:** `Nuke Script/mig21_nuke_effects.lua`

Visual effects script for the MiG-21's RN-28 tactical nuclear bomb. Creates a dramatic detonation sequence — DCS handles the actual weapon blast damage natively.

**Key features:**
- Listens for RN-28 weapon impacts via `S_EVENT_HIT` / `S_EVENT_DEAD` event handlers
- Supported weapon type names: `RN-28`, `MBD3-U6-68_RN-28`, `RN-28_MiG-21`
- **Detonation sequence:**
  1. **Blinding white flash** — `illuminationBomb` at 500 million candela, 150 m AGL
  2. **Stacked fireball** — 80 random explosions spread across 1200 m radius / 1800 m height + 40 dense ground-level blasts within 600 m
  3. **Mushroom cloud** — 12-level rising smoke column to 8000 m with timed delays, topped by a 16-point smoke ring cap at 1200 m radius
- Optional `NUKE_TEST` trigger zone for testing without a live drop
- **Standalone** — no dependencies

