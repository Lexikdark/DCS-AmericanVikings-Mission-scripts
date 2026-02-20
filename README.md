# DCS-AmericanVikings-Mission-scripts

Simple Repo for the Scripts we at AmericanVikings DCS Multiplayer server make and use in our missions.

---

## Repository Structure

```
DCS-AmericanVikings-Mission-scripts/
├── README.md
├── convoy-systems/
│   ├── BLUE-ResupplyConvoySpawn/
│   │   ├── BLUE-ResupplyConvoySpawn v5.7.0.lua
│   │   └── BLUE-ResupplyConvoySpawn_DOCS.html
│   └── RedAutomatedConvoySystem/
│       ├── RedAutomatedConvoySystem(v4.0).lua
│       └── RedAutomatedConvoySystem_DOCS.html
├── dgss/
│   ├── CSAR+lives/
│   │   ├── DGSS-CSAR+Lives_v5.1.lua
│   │   └── DGSS-CSAR+Lives_v5.1_DOCS.html
│   ├── CTLD-JTAC/
│   │   ├── DGSS-CTLD-JTACv7.2.lua
│   │   └── DGSS-CTLD-JTAC_DOCS.html
│   ├── DGSS/
│   │   ├── DGSS_v4.3.lua
│   │   └── DGSS_v4.3_DOCS.html
│   ├── DGSS-Leaderboard 3.5.lua
│   ├── DGSS-Leaderboard_3.5_DOCS.html
│   ├── IED_System (Road-placement)/
│   │   ├── DGSS-IED_System 6.2_RoadPlacement.lua
│   │   └── DGSS-IED_System_6.2_DOCS.html
│   ├── SYRIA-DGSS/
│   │   ├── SYRIA_DGSS_v4.3.lua
│   │   └── SYRIA_DGSS_v4.3_DOCS.html
│   ├── TargetOfOportunity script/
│   │   └── SYRIA_ISIS_TOO_Script_DOCS.html
│   └── TOO scripts/
│       ├── DGSS_TOO_System v5.9.lua
│       ├── DGSS_TOO_System_v5.9_DOCS.html
│       └── SYRIA_ISIS_TOO_Script.lua
├── iads/
│   ├── RED_BLUE_IADS_Intercept.lua
│   └── RED_BLUE_IADS_Intercept_DOCS.html
└── mission-systems/
    ├── AirBaseCapture/
    │   ├── SYRIA_AirbaseCapture.lua
    │   └── SYRIA_AirbaseCapture_DOCS.html
    └── MissionStatePersistence/
        ├── MissionStatePersistence(v.4.0).lua
        └── MissionStatePersistence_DOCS.html
```

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
- [IADS](#iads)
  - [RED_BLUE_IADS_Intercept](#red_blue_iads_intercept)
- [Mission Systems](#mission-systems)
  - [AirBaseCapture (Syria)](#airbasecapture-syria)
  - [MissionStatePersistence v4.0](#missionstatepersistence-v40)

---

## Convoy Systems

### BLUE-ResupplyConvoySpawn v5.7.0

**File:** `convoy-systems/BLUE-ResupplyConvoySpawn/BLUE-ResupplyConvoySpawn v5.7.0.lua`
**Docs:** `BLUE-ResupplyConvoySpawn_DOCS.html`

Manages Blue coalition ground resupply convoys that spawn from rear airbases and drive to forward operating bases (FOBs). Configured for the Syria theatre using Israeli airbases as origin points.

**Key features:**
- Spawns logistics convoys from a configurable list of source airbases/zones toward defined FOB destinations
- Multiple vehicle template compositions to vary convoy appearance and capability
- Convoys follow DCS road networks; waypoints are set automatically at departure and destination zones
- Spawn frequency and maximum simultaneous convoy count are configurable
- Cleans up destroyed or stalled convoys and respawns replacements to maintain persistent logistics pressure
- Integrates with CTLD for supply delivery mechanics at FOBs

---

### RedAutomatedConvoySystem v4.0

**File:** `convoy-systems/RedAutomatedConvoySystem/RedAutomatedConvoySystem(v4.0).lua`
**Docs:** `RedAutomatedConvoySystem_DOCS.html`

Autonomous Red-force convoy system that continuously generates enemy logistics and reinforcement columns across the map without mission-editor coordination.

**Key features:**
- 20 configurable convoy vehicle templates (infantry, armour, mixed logistics)
- `NUM_CONVOY_POINTS = 30` — defines the maximum number of named ConvoyZone trigger zones the script will read from the mission (increase this constant to support larger maps)
- `MAX_CONVOYS = 15` — caps simultaneous active Red convoys
- Minimum travel distance filter (`MIN_TRAVEL_DISTANCE = 35 nm`) prevents trivially short routes
- Stall detection: convoys that stop moving are automatically despawned and replaced
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
- Successful extraction awards the rescued pilot a respawn credit
- **Player lives system:** each pilot has a limited number of lives per session; ejection or death decrements the count; successful CSAR rescue restores a life
- `dropOffZones` table configured for Syrian airbase locations (Khmeimim, Ramat David, Haifa, etc.)
- Live count and rescue status broadcast via DCS in-game messages

---

### DGSS-CTLD-JTAC v7.2

**File:** `dgss/CTLD-JTAC/DGSS-CTLD-JTACv7.2.lua`
**Docs:** `DGSS-CTLD-JTAC_DOCS.html`

Integrates the CTLD (Combined Transport & Loading) troop-transport framework with an automated JTAC laser designation and radio management system.

**Key features:**
- Transport helicopters can load/unload CTLD infantry and vehicle crates at FOBs and forward zones
- Automatically spawns JTAC units at active combat zones; each JTAC laser-designates the nearest valid Red ground target
- JTAC callsigns, laser codes, and radio frequencies are assigned per zone and broadcast to players
- FOB and airbase zone tables updated for the Syria map (Israeli and Syrian bases)
- Integrates with DGSS spawn events — new Red contacts trigger JTAC tasking updates
- JTAC units are cleaned up automatically when their zone is cleared

---

### DGSS-Leaderboard v3.5

**File:** `dgss/DGSS-Leaderboard 3.5.lua`

Real-time multiplayer kill and score leaderboard displayed via DCS F10 messages.

**Key features:**
- Tracks ground kills, air kills, and friendly-fire incidents per pilot
- Leaderboard updates on a configurable timer and on significant kill events
- Scores persist for the duration of the server session
- Outputs formatted standings visible to all players via the in-game message system

---

### DGSS-IED System v6.2 (Road Placement)

**File:** `dgss/IED_System (Road-placement)/DGSS-IED_System 6.2_RoadPlacement.lua`

Dynamically plants Improvised Explosive Devices along road networks within defined trigger zones, threatening convoys and ground movements.

**Key features:**
- Reads a list of named IED zones from the mission editor; places concealed IED objects on nearby roads
- IEDs detonate on proximity to any ground vehicle within coalition filter rules
- Blast radius, detonation delay, and IED density per zone are configurable
- Dead IEDs are tracked; zones can be re-seeded on a timer to maintain persistent threat
- Works alongside the convoy systems to create realistic route-clearance requirements

---

### DGSS Target of Opportunity (TOO) v5.9

**File:** `dgss/TargetOfOportunity script/DGSS_TOO_System v5.9.lua`

Generates dynamic strike tasking for available Blue air assets by identifying and broadcasting high-value Red targets as Targets of Opportunity.

**Key features:**
- Monitors active Red ground groups spawned by DGSS; flags high-value units (SAMs, armour, C2) as TOO targets
- Broadcasts target type, grid reference, and recommended ordnance via F10 messages and optionally SRS radio
- Targets are cleared from the list once destroyed or when no longer detected
- Configurable scan interval and target-value thresholds
- Provides players with dynamic, AI-generated strike packages without requiring a human JTAC or FAC

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
- Intercept coordination: fighter CAP and SAM systems are de-conflicted so airborne interceptors don't get targeted by friendly SAMs
- Point-defence and area-defence SAM roles are assigned separately for realistic layered coverage
- Fully configurable unit name lists in the header to adapt to any mission's group naming convention

---

## Mission Systems

### AirBaseCapture (Syria)

**File:** `mission-systems/AirBaseCapture/SYRIA_AirbaseCapture.lua`
**Docs:** `mission-systems/AirBaseCapture/SYRIA_AirbaseCapture_DOCS.html`

Dynamic airbase ownership and capture system for the Syria map. Tracks coalition control of key airbases and transitions ownership when ground forces secure the surrounding area.

**Key features:**
- Each monitored airbase has a defined capture zone; when Red or Blue ground units are the only living forces inside, the base flips coalition
- Capture triggers: airbase ATC frequency changes, map marker updates, and optionally supply-convoy destination unlocks
- Contested state: if both coalitions have units inside a zone simultaneously the base is marked as contested and neither side gains control
- Coalition ownership persists for the session and integrates with MissionStatePersistence for cross-restart retention
- Configurable list of airbase names and zone names to adapt the script to different maps or mission layouts

---

### MissionStatePersistence v4.0

**File:** `mission-systems/MissionStatePersistence/MissionStatePersistence(v.4.0).lua`
**Docs:** `mission-systems/MissionStatePersistence/MissionStatePersistence_DOCS.html`

Serialises and restores critical mission state across DCS server restarts, preventing progress loss when the server cycles the mission.

**Key features:**
- Saves player scores, lives counts, airbase capture states, spawn-zone ownership, and arbitrary mission flags to a Lua state file on the server filesystem
- State file is written on a configurable auto-save interval and on clean server shutdown
- On mission load, the script detects an existing state file and restores all saved values before any other scripts run
- Safe fallback: if no state file is found (first run) the mission starts fresh with default values
- Extensible data model — other scripts can register their own state tables with the persistence system via a simple API call

