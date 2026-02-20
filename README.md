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

