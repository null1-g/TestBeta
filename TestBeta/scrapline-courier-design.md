# Test Beta

## Pitch
A 2D top-down browser game built for low-end PCs where the player pilots a battered delivery rig across a collapsing industrial district, scavenges useful scrap, and completes timed courier contracts before fuel and damage run out.

The fantasy is simple: make one more run, bring something valuable home, upgrade the rig, and push farther next time.

## Why This Fits Low-End PCs
- 2D Phaser stack keeps runtime light and predictable.
- Small arenas with room-to-room streaming avoid heavy world simulation.
- Pixel-art silhouettes and flat lighting remove GPU pressure.
- Few on-screen enemies and slow projectile counts keep CPU cost low.
- Mouse-plus-keyboard and keyboard-only input both work.
- DOM HUD handles menus and text cleanly without canvas-heavy UI.

## Target Platform
- Runs in modern desktop browsers on Windows, macOS, and Linux PCs.
- Primary target: low-spec laptops and office PCs.
- Resolution target: 1280x720 internal design, scalable down to 960x540.
- Performance target: 60 FPS on mid-range systems, stable 30 FPS fallback on low-end systems.

## Genre And Scope
- Genre: top-down extraction-lite action game.
- Session length: 8 to 15 minutes per run.
- Progression length: 30 to 60 minutes for the first meaningful upgrade arc.
- Controls:
  - `WASD` move
  - `Space` interact / pick up
  - `Left Click` or `J` fire tool
  - `Shift` boost
  - `Tab` open map
  - `Esc` pause

## Player Fantasy
You are a desperate courier running contracts through dangerous ruins. Every trip is a risk-reward decision: grab easy scrap and leave, or push deeper for rare components and a bigger payout.

## Core Loop
1. Accept a contract in the garage hub.
2. Enter a district map with limited fuel and hull integrity.
3. Navigate between compact zones.
4. Fight or avoid hostile drones.
5. Collect scrap, repair parts, and contract cargo.
6. Decide whether to extract now or press deeper.
7. Return to the garage and convert rewards into upgrades.
8. Unlock harder districts and higher-paying contracts.

## Moment-To-Moment Loop
Every 10 to 20 seconds the player should be doing one of these:
- steering through hazards
- choosing a route fork
- grabbing nearby scrap
- spending ammo or heat to clear drones
- deciding whether to continue or extract

This keeps the game readable and active without needing large enemy counts or expensive effects.

## Win, Fail, And Tension
### Success
- Extract with the contract cargo.
- Bonus rewards for extra scrap and low damage taken.

### Failure
- Hull reaches zero.
- Fuel reaches zero outside extraction.
- Critical contract cargo is destroyed.

### Tension Sources
- Fuel slowly drains during the run.
- Combat raises heat, briefly weakening the weapon if overused.
- Valuable scrap takes cargo space, forcing tradeoffs.
- Some exits lock until a nearby power node is activated.

## Progression
### Permanent Meta Progression
- Better fuel tank
- Stronger hull
- Faster cooling
- Larger cargo hold
- Better salvage magnet radius
- New contract tiers

### Run-Based Progression
- Temporary repair kits
- Ammo caches
- Rare parts that sell for high value
- Optional side objectives found mid-run

## Main Systems
### Simulation
- Player rig state: position, velocity, hull, fuel, heat, cargo.
- District state: zone graph, hazard placements, contract objective, extraction point.
- Enemy state: patrol, alert, attack, disabled.
- Reward state: scrap values, contract completion, extraction payout.

### Rendering
- One Phaser play scene for the active district.
- Tile-based rooms with light sprite layering.
- Camera follows player with slight look-ahead.
- Minimal particles only for hits, sparks, and extraction.

### UI
- DOM overlay for hub menus, contracts, settings, and run summary.
- Canvas HUD only for essential bars and markers.
- Accessibility options:
  - screen shake toggle
  - low effects mode
  - larger HUD scale
  - remappable keys

## Content Structure
### Hub
- Contract board
- Upgrade bench
- Run summary terminal

### Districts
- Rust Yard: tutorial zone, low danger
- Drain Tunnels: tighter routes, fuel pressure
- Relay Blocks: more drones, better loot

Each district should reuse tiles and enemy archetypes aggressively to keep asset cost low.

## Enemy Design
Keep only 3 core enemy types in v1.
- Scout drone: fast, fragile, rushes player.
- Turret pod: stationary area denial.
- Hauler bot: slow elite carrying high-value scrap.

This supports readable encounters without AI complexity.

## Technical Plan
### Stack Choice
- Engine: Phaser 3
- Language: TypeScript
- Build tool: Vite
- UI layer: DOM overlays with plain HTML/CSS or lightweight UI helpers
- Audio: compressed short SFX loops, limited simultaneous channels

### Architecture Boundaries
- Simulation owns rules, contracts, health, fuel, loot, and extraction.
- Phaser scene owns sprites, camera, animation timing, and input plumbing.
- UI reads from simulation state and dispatches actions, but never owns game rules.
- Save data stores upgrades, unlocked districts, settings, and best contract results.

### Suggested Module Layout
- `src/game/sim/` for rules and serializable state
- `src/game/render/` for Phaser scenes and sprite bindings
- `src/game/input/` for action mapping
- `src/game/data/` for contracts, items, enemies, and districts
- `src/ui/` for hub, pause, settings, and summaries

## Performance Rules
- Keep spritesheets small and reuse palette swaps.
- Avoid dynamic lights, per-pixel effects, and shader-heavy post-processing.
- Cap active enemies per room.
- Pool projectiles and particles.
- Tick expensive AI less often than movement.
- Stream adjacent rooms instead of simulating the whole district in detail.
- Include a low-spec preset enabled by default on first boot.

## Production Plan
### Vertical Slice
1. Garage hub with one contract.
2. One district with three rooms.
3. One extraction point.
4. Two enemy types.
5. Fuel, hull, cargo, and payout systems.
6. One permanent upgrade.

### Full v1
1. Three districts.
2. Three enemy types.
3. Ten to fifteen contract variants.
4. Upgrade tree with six to eight nodes.
5. Save system and settings menu.
6. Tutorial prompts and end-of-run summary.

## Playtest Goals
- New players understand extraction within 2 minutes.
- Average first run lasts at least 5 minutes.
- Low-spec mode stays readable and responsive.
- The player makes at least 3 meaningful risk-reward decisions per run.

## Next Build Step
Build the vertical slice first. The minimum fun test is whether one run creates tension between loot greed and safe extraction.
