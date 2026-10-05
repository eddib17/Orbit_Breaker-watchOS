# OrbitBreaker for watchOS — Project Plan

A port of the Wear OS game **OrbitBreaker** to Apple Watch. It's a circular brick breaker: the paddle is an arc that travels **around the edge of a circular arena** and is steered with the **Digital Crown**. Bricks sit in concentric rings in the middle; the ball bounces between them and the paddle ring. If the ball escapes past the paddle ring, you lose a life.

Scope matches the Wear OS app: **60 levels across 6 worlds** (every 10th level is a boss), **5 themes**, **haptics on every menu, view and gameplay event**, optional synthesized sound, stats, and a self-playing tutorial.

> **Reuse from the Wear OS project:** the 60 level files (`levels/001.json … 060.json`) copy over unchanged. The Kotlin engine (`engine/`, ~1,300 lines, no Android dependencies) is the reference implementation: translate it file by file to Swift rather than redesigning it.

---

## 1. Tech stack & targets

| Item | Choice | Why |
|---|---|---|
| Language | Swift 6 (strict concurrency) | Current Xcode default |
| Xcode template | **watchOS → App** (watch-only, no iPhone companion) | Matches the standalone Wear OS app |
| Deployment target | watchOS 11 | Needed for `handGestureShortcut` (Double Tap); `sensoryFeedback`, `digitalCrownRotation(detent:…onChange:)` and `isLuminanceReduced` are older |
| UI (menus) | SwiftUI: `NavigationStack`, `List`, `TabView(.verticalPage)` | Crown scrolling and back swipe come built in |
| Game rendering | SwiftUI `Canvas` inside `TimelineView(.animation)` | Same idea as the Compose `Canvas` + `withFrameNanos` loop; the shapes are simple. Fall back to SpriteKit `SpriteView` only if profiling demands it |
| Crown input | `.focusable()` + `.digitalCrownRotation(detent:from:through:by:sensitivity:isContinuous:isHapticFeedbackEnabled:onChange:onIdle:)` | Gives the angle and the crown's velocity |
| Haptics | `WKInterfaceDevice.current().play(_:)` (WatchKit) and SwiftUI `.sensoryFeedback` for menus | **Core Haptics doesn't exist on watchOS.** See §6 |
| Sound | `AVAudioEngine` + `AVAudioPlayerNode` playing PCM buffers synthesized at launch | Port of `ToneSynth.kt`; no audio assets |
| Persistence | `@AppStorage` for settings; `Codable` structs saved as JSON (UserDefaults or a file in Application Support) for progress and stats | Small data; SwiftData is overkill |
| Engine | Local **Swift Package** `OrbitEngine` (no SwiftUI/WatchKit imports) | Same split as the Gradle `:engine` module; `swift test` runs on the Mac in seconds |
| Tests | Swift Testing (`@Test`, `#expect`) in the package; XCTest UI tests for the app | |

---

## 2. Screen shape: the biggest design change

Wear OS watches are mostly round; **Apple Watch screens are rounded rectangles, taller than wide** (e.g. 416×496 px on the 46 mm Series 10).

- The arena is a circle whose **diameter equals the screen width**, centered vertically. Engine coordinates stay normalized (arena radius R = 1.0), so the physics doesn't change.
- Use the spare space above and below the circle for the HUD: **score and combo on top, lives and active power-ups at the bottom**. This replaces the Wear OS translucent HUD pill that sat over the bricks.
- The game view uses `.ignoresSafeArea()` and hides the toolbar/time (`.toolbar(.hidden)`, `.persistentSystemOverlays(.hidden)`).
- Test every case size: 41/45 mm (S7–S9), 42/46 mm (S10+), 49 mm (Ultra), 40/44 mm (SE).

---

## 3. Architecture

```
OrbitBreaker.xcodeproj
├── OrbitBreaker Watch App/
│   ├── OrbitBreakerApp.swift         // @main, environment objects, scenePhase handling
│   ├── Navigation/
│   │   └── AppRouter.swift           // NavigationStack path + routes enum
│   ├── UI/
│   │   ├── Menu/                     // MainMenuView, WorldSelectView, LevelGridView, StatsView
│   │   ├── Game/                     // GameView (Canvas), GameRenderer, HUD, Pause/Clear/GameOver overlays
│   │   ├── Settings/                 // SettingsView, ThemePickerView, HapticTesterView
│   │   ├── Tutorial/                 // HowToPlayView, DemoGame (autopilot preview)
│   │   └── Components/               // HapticButton, HapticToggle, HapticStepper
│   ├── Input/
│   │   ├── CrownController.swift     // crown → paddle angle, sensitivity, invert, velocity
│   │   └── TouchDial.swift           // drag-around-the-edge steering
│   ├── Haptics/
│   │   ├── HapticEngine.swift        // single entry point: priority, rate limit, level setting
│   │   ├── Haptic.swift              // named patterns → WKHapticType sequences
│   │   └── GameHaptics.swift         // GameEvent → Haptic mapping
│   ├── Sound/
│   │   ├── ToneSynth.swift           // square/triangle/noise tones → AVAudioPCMBuffer
│   │   ├── Sfx.swift                 // the 18 effects
│   │   └── SoundEngine.swift         // AVAudioEngine, ≤3 sounds per frame
│   ├── Theme/
│   │   ├── GameTheme.swift           // palette + render style flags
│   │   └── Themes.swift              // the 5 themes
│   └── Data/
│       ├── SettingsStore.swift
│       ├── ProgressStore.swift
│       └── StatsStore.swift
└── Packages/OrbitEngine/             // PURE SWIFT, Foundation only
    ├── Package.swift
    ├── Sources/OrbitEngine/
    │   ├── Arena.swift               // constants (port of Arena.kt)
    │   ├── LevelDef.swift            // Codable level model
    │   ├── LevelLoader.swift         // loads Bundle.module JSON, validates
    │   ├── GameState.swift
    │   ├── GameEngine.swift          // fixed-timestep update(), collisions, mechanics
    │   ├── GameEvent.swift
    │   ├── Autopilot.swift
    │   ├── Worlds.swift
    │   ├── MathUtil.swift
    │   ├── SeededRandom.swift        // SplitMix64 RandomNumberGenerator for deterministic tests
    │   └── Resources/levels/001.json … 060.json   // copied verbatim from Wear OS
    └── Tests/OrbitEngineTests/
        ├── GameEngineTests.swift
        ├── MechanicsTests.swift
        └── LevelsTests.swift
```

**Data flow during play:**
`CrownController / TouchDial → GameModel.aimPaddle(angle)` → `engine.update(frameSeconds)` (fixed **120 Hz substeps** inside) → returns `[GameEvent]` → `HapticEngine`, particles, screen shake and `SoundEngine` consume them → `Canvas` draws the current `GameState` once per frame.

`GameModel` is an `@Observable @MainActor` class that owns the `GameEngine`, is driven from the `TimelineView` date, and clamps the frame delta (max 50 ms) so a stall never teleports the ball.

### 3.1 Porting notes (Kotlin → Swift)
- `data class` → `struct`; `sealed interface GameEvent` → `enum GameEvent` with associated values; `enum class BrickType(code:…)` → `enum BrickType: Character` plus computed `hitPoints` / `breakable`.
- **Codable defaults:** Swift's synthesized `Decodable` ignores default property values. Write `init(from:)` for `LevelDef`, `RingDef`, `GravityWellDef`, `CoreDef` and `CorePhaseDef` using `decodeIfPresent(...) ?? default`, mirroring the defaults in `LevelDef.kt` (e.g. `ballSpeed = 1`, `paddleArcDeg = 40`, `parSeconds = 90`, `regenSeconds = 10`, `phaseSeconds = 1.6`).
- `kotlin.random.Random` → a generic `RandomNumberGenerator` parameter. Tests and the autopilot use a seeded `SplitMix64` so level bot-runs are reproducible.
- Use `Float` like the Kotlin engine (or `Double` everywhere; just don't mix). Keep every constant from `Arena.kt` with the same value.
- `GameEngine` public API stays the same: `init(level:rng:)`, `nudgePaddle(_:)`, `aimPaddle(_:)`, `launch()`, `update(frameSeconds:) -> [GameEvent]`, read-only `state`.

---

## 4. Core gameplay (same rules as Wear OS)

### 4.1 Geometry (normalized, arena radius R = 1.0, from `Arena.kt`)
- Paddle ring radius 0.88, thickness 0.05, default arc 40° (min 20°).
- Ball radius 0.035; base speed 0.85, +1.5% per paddle hit, capped at 1.6× the level speed.
- Brick rings between ~0.15 and 0.70; brick thickness 0.085, gap 0.014. Each ring is split into N annular-sector bricks.
- Kill radius 0.98; the shield ring (power-up) sits at 0.94.
- Max deflection 55° from the radial normal (absolute cap 65°) so the ball never orbits.

### 4.2 Paddle control
- **Digital Crown:** continuous; maps crown rotation to paddle degrees, scaled by the *Sensitivity* setting (5 steps) and *Invert direction*. Use `isContinuous: true` so the paddle wraps freely around 360°.
- The rendered paddle eases toward the target angle (critically damped spring, ~40 ms).
- **Paddle motion transfer:** use the crown velocity from `DigitalCrownEvent` (or the paddle's angular velocity) to add a little spin to the ball (skill shot).
- **Crown detent haptics:** turn on `isHapticFeedbackEnabled` so the system gives the crown its native ticks. This replaces the Wear OS "LOW_TICK every 10°" and costs nothing in the rate limiter. Add a setting to turn it off.
- **No bezel on Apple Watch:** drop the Wear OS crown-vs-bezel detection entirely.
- **Touch steering (option, on by default as a fallback):** drag anywhere near the edge and the paddle turns by the angle your finger sweeps (relative, like a dial), so it never jumps under your finger. Port `TouchDial.kt`. It must not conflict with the crown; whichever input moved last wins.
- **Double Tap (watchOS 11, Series 9+/Ultra 2):** `.handGestureShortcut(.primaryAction)` on the launch button, so a pinch launches the ball or releases a sticky ball.

### 4.3 Physics
- **Paddle hit:** reflect about the radial normal, then add "english" from where the ball hit the arc (−1 … +1), clamped to the max deflection.
- **Brick hit:** convert to polar; test ring band and angular span; hitting an inner/outer arc reflects radially, hitting a side face reflects tangentially.
- **Anti-tunneling:** fixed 120 Hz substeps.
- **Anti-stall:** no brick hit for 8 s → nudge the next paddle bounce by ±7° and play a hint haptic.

### 4.4 Brick types (level string codes)

| Code | Brick | Behavior |
|---|---|---|
| `.` | empty | — |
| `A` | Standard | 1 hit |
| `B` | Tough | 2 hits |
| `C` | Armored | 3 hits |
| `X` | Unbreakable | Never breaks |
| `E` | Explosive | Destroys neighbours (same ring ±1, adjacent rings); chains |
| `P` | Carrier | Always drops a power-up |
| `R` | Regenerating | Grows back after `regenSeconds`, unless the rest of its ring is cleared |
| `G` | Ghost | Invisible; first hit reveals, second breaks; faint sonar haptic when the ball passes within 0.08 R |
| `F` | Phasing | Alternates solid/intangible every `phaseSeconds` |
| `W` | Warp | Unbreakable portal; consecutive `W`s link in pairs |
| — | Boss core | From the level's `cores` list; HP, phases, can be off-center. Only a **charged** ball (fresh off the paddle, drawn with a ring in the core's color) damages it |

### 4.5 Level mechanics
Ring rotation (`rotationDps`, `offsetDeg`), tidal rings (`rotationPeriod`), gravity wells (optionally pulsing), boss phases (`ringSpeedMultiplier`, `gravity`, `restoreShields`, `phaseShields`), darkness (bricks visible only near the ball; ≥ 0.5 adds sonar haptics for every brick), a shrinking paddle (`paddleShrinkDps`), `dropChance`, and per-level `powerUps` lists.

### 4.6 Power-ups (drift outward; catch with the paddle)
Wide (15 s) · Narrow — bad (12 s) · Multi-ball (max 6 balls) · Slow-mo (10 s) · Fireball (8 s, pierces) · Sticky (12 s, tap or Double Tap to release, auto-release after 2 s) · Laser (8 s) · Shield ring (one save) · Extra life (rare, max 5 lives). A warning haptic plays 2 s before a timed one runs out.

### 4.7 Scoring & progression
- Score = brick value × combo (bricks hit without touching the paddle). Core hit 25, core defeated 500.
- Stars: clear = 1★, no lives lost = 2★, under par time = 3★.
- 3 lives per attempt. Worlds unlock in order; levels inside a world unlock on clear. Debug builds unlock everything (`#if DEBUG`).

### 4.8 The six worlds
1 First Light (learn the ropes) · 2 Orbit (spinning rings) · 3 Iron (armor and explosives) · 4 Flux (warps and gravity) · 5 Eclipse (feel what you can't see) · 6 Singularity (everything at once). Level names and layouts come from the JSON files.

---

## 5. Themes (5, user-selectable)

Each `GameTheme` defines the background (solid or gradient), paddle, ball and trail, a color per brick type, the particle style, HUD colors, and the menu tint (applied with `.tint()` and backgrounds so menus match).

| # | Theme | Look |
|---|---|---|
| 1 | **Neon Arcade** (default) | Black, cyan paddle, glowing magenta/yellow bricks, neon trail, ring bursts |
| 2 | **Retro Phosphor** | Green-on-black CRT, scanlines, square paddle, pixel bursts |
| 3 | **Deep Ocean** | Navy gradient, teal/coral bricks, bubble bursts |
| 4 | **Ember** | Charcoal-to-warm gradient, orange/red bricks, heat-shimmer ball, sparks |
| 5 | **Minimal Mono** | Pure black, white outlines only, no glow or trail; best for battery |

- Port the hex values from `app/src/main/java/com/orbitbreaker/theme/GameTheme.kt`.
- **Glow:** draw the shape a second time with `context.addFilter(.blur(radius:))` in a copied `GraphicsContext`, or with a wider, low-opacity stroke (cheaper). Profile on a real watch.
- Theme picker: vertical-page `TabView`, each page drawn in its theme with a live self-playing preview (autopilot), Apply button plays the "theme applied" haptic.
- `ThemesTests` (in the app's unit test target) enforce contrast: ball, paddle, HUD and fireball ≥ 4.5:1 against the background; every brick, warp, power-up and the core ≥ 3:1; brick HP also shown by inner bands, not color alone.

---

## 6. Haptics (redesigned for the Taptic Engine)

watchOS has **no Core Haptics, no amplitude control and no custom waveforms**. The only tools are the fixed `WKHapticType` set (`.click`, `.directionUp`, `.directionDown`, `.start`, `.stop`, `.success`, `.failure`, `.retry`, `.notification`, plus the navigation types) and SwiftUI `.sensoryFeedback` (`.selection`, `.impact`, `.success`, `.warning`, `.error`, `.start`, `.stop`, `.increase`, `.decrease`), which map to the same hardware. Each Taptic pulse also takes longer than an Android primitive, and pulses fired too close together get swallowed.

So the Wear OS design (35 ms rate limit, scaled primitives) has to change:

### 6.1 `HapticEngine`
- One `@MainActor` instance in the environment, also given to `GameModel`.
- **Level setting** replaces Wear OS "intensity": **Off / Essential / Full**. *Essential* plays only priority ≥ Power-up collect; *Full* plays everything. (There is no amplitude to scale.)
- **Rate limit: one gameplay haptic per ~120 ms.** Within a window keep only the highest-priority event; several brick breaks in one frame count as one.
- Priority order (high → low): Ball lost / Game over > Level clear > Boss hit/phase > Shield save > Power-up collect / ending > Explosion > Brick break > Paddle hit > Brick chip > Sonar / miss warning.
- **Sequences** (fanfares, countdown) are scheduled as a short list of `(WKHapticType, delay)` on a `Task`, at least ~150 ms apart, and cancelled if a higher-priority sequence starts.
- Haptics only play while the app is active (watchOS ignores them otherwise), so the engine does nothing when `scenePhase != .active`.

### 6.2 Menu & view haptics

| Interaction | Haptic |
|---|---|
| Crown scroll in lists | System (built in) |
| Button tap | `.click` (via `HapticButton`) |
| Toggle on / off | `.directionUp` / `.directionDown` |
| Stepper step | `.click`; `.retry` at min/max |
| Locked level / world tapped | `.failure` |
| Level selected / Play | `.start` |
| Theme applied | `.success` |
| Pager page change (worlds, themes) | `.sensoryFeedback(.selection, trigger: page)` |
| Star reveal on results | `.click` per star, 250 ms apart |
| New high score | `.success` |
| Reset progress screen opens / progress erased | `.notification` / `.failure` |

`HapticButton`, `HapticToggle` and `HapticStepper` wrap the SwiftUI controls so no screen can forget haptics.

### 6.3 Gameplay haptics (`GameHaptics.swift`, one case per `GameEvent`)

| Event | Haptic |
|---|---|
| Paddle movement (crown) | System crown detents (§4.2) |
| Paddle hit, center | `.click` |
| Paddle hit, edge (abs offset > 0.7) | `.directionUp` (feels sharper) |
| Brick chip | `.click` (Full only) |
| Brick break | `.click` |
| Unbreakable hit / core deflected | `.retry` |
| Explosion | `.stop`; chain ≥ 3 → `.stop` then `.click` |
| Combo milestone | `.directionUp` × tier, 150 ms apart (max 3) |
| Power-up spawn | `.click` (Full only) |
| Power-up collect / negative power-up | `.success` / `.failure` |
| Power-up ending (2 s left) | `.retry` |
| Ghost / dark-level sonar | `.click` (Full only, 0.6 s cooldown, from `Arena.SONAR_COOLDOWN`) |
| Warp | `.directionDown` |
| Sticky catch | `.stop` |
| Miss warning (opt-in) | `.retry` |
| Ball lost | `.failure` |
| Shield saves ball | `.stop` then `.success` |
| Countdown 3-2-1 / launch | `.click` per tick / `.start` |
| Boss hit / boss phase / boss defeated | `.stop` / `.notification` / `.success` |
| Level clear | `.success` then star clicks |
| Game over | `.failure` |
| Pause / resume | `.stop` / `.start` |

Settings includes a **Haptic Tester** list: tap any event to feel it at the current level.

`GameHapticsTests` use a fake player (protocol `HapticPlayer`) to check every `GameEvent` maps to the intended pattern, the rate limiter drops and merges correctly, and "Off" plays nothing.

---

## 7. Screens & navigation

```
Launch (holds until settings load, so the theme never flashes)
 └─ Main Menu ── Continue / Start
               ├─ Worlds (vertical pager, 6 worlds, star ring per world) → Level Grid (10 bubbles, boss outlined) → Game
               ├─ How to Play (opens on first launch: live autopilot demo, brick legend, power-up legend, "feel the game" haptics)
               ├─ Stats (stars, cleared, best scores, bricks broken, power-ups, bosses, balls lost, attempts, win rate, time played)
               └─ Settings → Haptics (level, tester) · Controls (sensitivity, invert, touch steering, crown ticks, miss warning)
                             · Theme · Sound & effects (sound, screen shake) · Reset progress (confirm)

Game ── Pause overlay (Resume · Restart · Quit)
     ├─ Level Clear (stars, score, Next · Retry · Menu)
     └─ Game Over (Retry · Menu)
```

- Lists use `List` / `ScrollView`, which already handle crown scrolling.
- **In game the crown must move the paddle, not scroll or navigate:** the game view holds focus (`.focusable()` + `@FocusState`, set on appear) and hides the back button (`.navigationBarBackButtonHidden()`). Pause with a **long-press** anywhere or the on-screen pause control in the HUD area above the arena. Quit only from the pause overlay.

---

## 8. Lifecycle, battery & performance

- **Auto-pause** when `scenePhase` leaves `.active`, and when `@Environment(\.isLuminanceReduced)` turns true (wrist down / Always On). Never draw gameplay in the Always On state; show a dimmed "Paused" screen instead.
- Save in-progress level state on pause so the game resumes exactly after the app is suspended.
- watchOS has no "keep screen on" flag; while the player is turning the crown the screen stays awake. Don't use `WKExtendedRuntimeSession`, which isn't meant for games.
- Target 60 fps. If frames average slower than ~48 fps for 2 s, switch to **reduced effects** for the level (no trails, bursts, glows or overlays), as in the Wear OS app.
- Dark backgrounds everywhere (OLED). Minimal Mono is the battery saver.
- Sound is off by default and uses the `.ambient` audio session category so it respects the silent mode and never interrupts the user's music. At most 3 sounds per frame; brick pitch rises with the combo.

---

## 9. Implementation phases

| Phase | Deliverable | Est. |
|---|---|---|
| **0. Setup** | Xcode watchOS app, local `OrbitEngine` package, copy the 60 level JSONs, `swift test` running | 0.5–1 day |
| **1. Engine port** | Translate `Arena`, `LevelDef` (+ Codable defaults), `LevelLoader`, `GameState`, `GameEvent`, `GameEngine`, `Autopilot`, `Worlds`, `MathUtil` to Swift; port `GameEngineTest`, `MechanicsTest`, `LevelsTest` | 3–5 days |
| **2. Playable prototype** | `GameView` with `TimelineView` + `Canvas`, crown control, touch dial, countdown/launch, HUD above and below the arena, pause / clear / game-over overlays | 2–3 days |
| **3. Haptics** | `HapticEngine` with priority, rate limit and sequences; `GameHaptics` mapping; haptic tester; tune on a real watch | 2 days |
| **4. Menus & data** | All screens, haptic components, settings / progress / stats stores, unlocks and stars | 3 days |
| **5. Themes** | 5 themes, renderer styles, live preview picker, menu tint, contrast tests | 2–3 days |
| **6. Polish** | Particles, trails, screen shake, combo pop-ups, sound synth, How to Play with autopilot demo, miss warning, reduced-effects mode, Double Tap | 3–4 days |
| **7. QA & release** | Real devices (small and large cases, Ultra, an older SE), frame timing in Instruments, battery over a 15-minute session, App Store screenshots and listing | 2–3 days |

The engine port is the critical path: once Phase 1 tests pass (including the bot clearing all 60 levels), everything after it is UI work.

---

## 10. Testing checklist

- **Engine (Swift Testing, run with `swift test` on the Mac):** reflection angles, edge english, max-deflection clamp, anti-tunneling at max speed, every brick type, explosion chains, warp pairing, regen timers, phasing, gravity, boss charge rule and phases, power-up effects and expiry.
- **Levels:** all 60 decode and validate (sector string length equals `sectors`, warps paired, at least one breakable brick or a core, cores inside the innermost ring), no two are identical, and the seeded autopilot clears each one within a time limit. **Run the same checks against the Kotlin results** to confirm the port behaves the same.
- **Haptics:** fake player tests as in §6.3.
- **UI tests:** navigation flows, locked-level rejection, the crown doesn't navigate during play.
- **Devices:** crown feel at each sensitivity step, touch steering, Double Tap, every case size, Always On / wrist-down auto-pause, battery drain.

---

## 11. Open decisions (defaults chosen)

- **App name:** OrbitBreaker (check App Store availability).
- **Sound:** optional, off by default.
- **Monetization:** none.
- **iPhone companion, complications (WidgetKit), Smart Stack widget:** out of scope for v1. A "Continue level N" widget is a good v1.1 feature.
- **Shared engine:** keeping two engines (Kotlin and Swift) in sync is the long-term cost. If more features are planned, consider Kotlin Multiplatform for the engine later; for v1 a direct Swift port is simpler.
