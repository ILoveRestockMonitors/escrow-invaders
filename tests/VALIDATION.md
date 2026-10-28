# Validation

## Version 0.5.1 full audit, action hotkeys and browser pilot — 2026-10-06 PT

**6,231 checks passed across all 21 Godot test suites plus the worker and actual HTTP server suites.** The new action-key suite has 899 checks, cache suite 61 and server suite 17. **93 pilot Vitest tests passed across seven files**, including real React/IndexedDB integration, full seeded combat, audio and the delayed React phone-resize regression. These are different test units and are not added into a misleading single total.

Both release builds passed. Browser QA completed a full 19-target pilot sector, wrong→hint retry→correct, revive, pulse, damage, sound opt-in, clear/upgrade/reload, and a separate K-skip path. The fixed phone canvas was 348×505 CSS/intrinsic pixels after resizing while reading. Current full-game V solution and repeated upgrade-menu action shortcuts were checked on desktop and phone. No live-origin test answers were submitted. Local desktop frame timing and every remaining limit are recorded in the [audit](../../docs/audit/README.md).

The deployment passed 51 upload checksums and 15 hosted decoded runtime checksums, including the Godot PCK and complete pilot runtime. Service is active/enabled, HTTPS health 0.5.1, old release retained and unrelated routes/unit/Homepage unchanged. [Release record](../../deploy/release-validation-audit-pilot.json) · [Receipt](../../deploy/deployment-receipt-audit-pilot.json).

## Version 0.5.0 Orbital Closing Desk — deployed 2026-10-06 PT

**5,017 checks passed** across 18 suites, plus the final Godot Web export. Final logs are `game/.runtime/cockpit-test_*.log`; keyboard, study-offer UI, mobile and service-worker checks were rerun after the final polish. No engine/script errors or browser console warnings/errors were observed.

| Suite | Passed checks |
| --- | ---: |
| `test_question_keyboard.gd` | 60 |
| `test_answer_confetti.gd` | 41 |
| `test_presentation.gd` | 56 |
| `test_course_bank.gd` | 29 |
| `test_main_flow.gd` | 109 |
| `test_main_persistence.gd` | 34 |
| `test_study_boost_ui.gd` | 91 |
| `test_revive_ui.gd` | 424 |
| `test_mobile.gd` | 1,540 |
| `test_navigation_ui.gd` | 336 |
| `test_encounter_arena.gd` | 149 |
| `test_arena_revive.gd` | 47 |
| `test_combat_pulse.gd` | 37 |
| `test_progression.gd` | 572 |
| `test_study_model.gd` | 448 |
| `test_response_journal.gd` | 76 |
| `test_installed_course.gd` | 911 |
| `test_service_worker.mjs` | 57 |
| **Total** | **5,017** |

Source comparison to the pre-redesign ZIP confirms byte-identical arena, progression, study, journal, director, course-bank and audio scripts, course data, background and ship pixels. Native controls own all input; the HTML/CSS layer receives presentation snapshots and renders decorative feedback. Fonts are bundled and cached with verified release hashes.

Screenshots for each of the six phases cover 1920×1080, 1440×900, 1280×720 and 390×844. Final normal desktop Home and mission panels report zero scroll overflow. Long study text, Help and offer/management screens intentionally scroll. The phone uses its existing dedicated combat/reading layout. Native responsive tests additionally cover 375×667, 430×932 and 844×390. See the [review gallery](../.runtime/cockpit-screenshots/review.html).

Browser playtesting on isolated port 9486 verified starting combat, drag movement, auto-fire, Repulsor cooldown, damage, correct WASD answers and confetti, Reduced Motion fade-only particles, a three-question upgrade, loss/revive, actual sector clear, next-level upgrade, skip and pause. The upgrade survived reload. A later reload retained Sector 02, Rank 03, hull 3/3, 100/150 XP, 110 coins and 1 gem exactly. No production answers were submitted. Visible active combat was spot-observed at 61 FPS; no sustained hardware benchmark or physical iPhone/Safari test was performed.

All 29 upload hashes passed; the active/enabled service reports 0.5.0. The HTTPS pack matches `7777775189ecb6b900065d7044b7c9d2dc67654b566a6eb4dd0c5c8447022b1d`. Release `/opt/escrow-invaders/releases/20261007T034633Z` retains `/opt/escrow-invaders/releases/20261007T030131Z` for rollback. Homepage, routes, unit and save formats are unchanged. [Release record](../../deploy/release-validation-cockpit.json) · [Receipt](../../deploy/deployment-receipt-cockpit.json).

## Version 0.4.1 keyboard questions — deployed 2026-10-06 PT

**2,729 checks passed** across the 10 affected suites, with no engine/script errors in the final test logs. The Godot 4.7.2 Web build and release-cache tests passed.

| Suite | Passed checks |
| --- | ---: |
| `test_question_keyboard.gd` | 57 |
| `test_presentation.gd` | 56 |
| `test_course_bank.gd` | 29 |
| `test_mobile.gd` | 1540 |
| `test_navigation_ui.gd` | 336 |
| `test_main_flow.gd` | 109 |
| `test_main_persistence.gd` | 34 |
| `test_study_boost_ui.gd` | 91 |
| `test_revive_ui.gd` | 424 |
| `test_service_worker.mjs` | 53 |
| **Total** | **2,729** |

The new 57-check suite sends actual GUI key events for W/A/S/D mapping, removal of numeric shortcuts, arrow focus and Enter confirmation, hint assistance, Help and pause isolation, modified-key exclusion, held movement keys, Enter auto-repeat, honest corrections, a full three-question upgrade set, earned revive, timed bonus, long-phone-text scrolling and keyboard skip. Existing progression, saves and reward semantics remain unchanged. The existing course-bank and modal-navigation tests now use WASD, so they still exercise meaningful answer inputs.

Browser QA on isolated port 9484 verified the real keyboard flow through hint, first-answer miss, guided retry, second-answer correction, and continuation to the next review; arrow selection and all four key badges rendered at 390 × 844. Final labels use plain UP/DOWN because the browser font lacks arrow glyphs. Screenshots: `.runtime/keyboard-question-desktop.jpg` and `.runtime/keyboard-question-phone.jpg`. No console warnings/errors or production test answers. Physical iPhone/Safari remains untested.

All 25 uploaded files verified. The active/enabled service reports 0.4.1. The HTTPS game pack matches `8d82cdd438870fdccac21cc92e0f0150a4cce48337db43e44e7e04d95f309a50`. Current release `/opt/escrow-invaders/releases/20261007T025514Z` retains `/opt/escrow-invaders/releases/20261007T023929Z` for rollback. Homepage, routes, service unit and save formats remain unchanged. See [release record](../../deploy/release-validation-keyboard.json) and [deployment receipt](../../deploy/deployment-receipt-keyboard.json).

Input reference: [Godot InputEventKey](https://docs.godotengine.org/en/4.4/classes/class_inputeventkey.html) for key releases and echo events. Runtime behavior was verified on the installed 4.7.2 engine.

## Version 0.4.0 Repulsor update — deployed 2026-10-06 PT

**3,003 checks passed across 12 suites**, followed by a successful Godot 4.7.2 Web export and browser QA. Counts describe the affected suites actually run for this update, not every historical test.

| Suite | Passed checks |
| --- | ---: |
| `test_presentation.gd` | 56 |
| `test_mobile.gd` | 1540 |
| `test_navigation_ui.gd` | 336 |
| `test_main_flow.gd` | 109 |
| `test_main_persistence.gd` | 34 |
| `test_study_boost_ui.gd` | 91 |
| `test_revive_ui.gd` | 424 |
| `test_encounter_arena.gd` | 149 |
| `test_arena_revive.gd` | 47 |
| `test_combat_pulse.gd` | 37 |
| `test_audio.gd` | 127 |
| `test_service_worker.mjs` | 53 |
| **Total** | **3,003** |

The new pulse tests cover active-combat-only input, seven active-second recharge, nearby bullet clearing, spawn/armor protection, real kill receipts, finite objectives, cooldown retention through revive, effect bounds and reduced motion. Presentation tests exercise real Space routing while Sound has focus, touch target fit, pause and Help isolation, audio mix switches, and study screens across four sizes. The mobile suite covers five viewport sizes. Existing learning, save recovery, reward, navigation and revive paths passed.

Audio checks cover all cues, non-silent 16-bit PCM, amplitude bounds, six-voice priority protection, shot throttling, mute/pause, separate switches, cache reuse and unchanged global RNG/audio buses. PCM caches total 725,934 bytes. Native measured effect synthesis was 161 ms, the largest incremental music slice 11.9 ms, and cached initialization 0.1 ms. These are local native measurements, not phone performance claims.

Browser playtests at 1280 × 800 and 390 × 844 used isolated port 9483. Verified the hangar, sound toggle, combat, question skip, actual defeat with banked rewards, retry, touch pulse with visible 6.8-second cooldown, pause and cached-update persistence. No browser warnings or errors were reported. No test answers were submitted at the production address. Final phone screenshots are in `.runtime/upgrade-hangar-phone.jpg` and `.runtime/upgrade-combat-phone.jpg`. A native OpenGL Compatibility art smoke also passed; its staged screenshot is not a played encounter.

All 25 uploaded files passed manifest verification. Service is active/enabled; HTTPS health reports 0.4.0 and the live pack matches `942b73f74f40b97607439145d29de7fc050e892e8dda827b274c19ed2b18a330`. Active release: `/opt/escrow-invaders/releases/20261007T023929Z`; retained rollback: `/opt/escrow-invaders/releases/20260916T024427Z`. Homepage, routes, service unit and save formats are unchanged. See [release record](../../deploy/release-validation-repulsor.json) and [deployment receipt](../../deploy/deployment-receipt-repulsor.json).

Physical iPhone/Safari performance, installation and listening remain unverified.

## Version 0.3.2 navigation update — deployed 2026-09-15 PT

The Web build and **2,587 affected checks passed**, followed by browser QA and verified home-lab deployment. These are update-specific checks; historical suites below were not all rerun for this update.

| Suite | Passed checks |
| --- | ---: |
| `test_main_flow.gd` | 109 |
| `test_main_persistence.gd` | 34 |
| `test_study_boost_ui.gd` | 91 |
| `test_revive_ui.gd` | 424 |
| `test_mobile.gd` | 1,540 |
| `test_service_worker.mjs` | 53 |
| `test_navigation_ui.gd` | 336 |
| **Total** | **2,587** |

The update adds a pinned Home / Upgrades / Weapons menu, places Play before artwork, and clarifies costs, effects and controls. Free Ship Rank choices are distinguished from currency purchases; weapon controls identify equipped, removable and locked items and explain replacing a full slot. Combat, economy and learning rules are unchanged.

Navigation checks cover safe menu transitions, action reachability and Help's Play, Rewards and Upgrades topics across five viewport sizes. Help retains the current phase, scroll position, timer and previous pause state. Keyboard focus stays inside Help and original focus restores on close; real Tab, Shift-Tab, Enter and Space inputs cannot activate underlying actions. Returning from an optional study set to Upgrades retains its offer and partial questions.

Browser QA at 390 x 844 verified Home, Upgrades, Weapons, study offer pricing and back navigation, all Help topics, readable Close and focused buttons, and Help returning to a pending battle question. Browser warning/error logs were empty. Testing used an isolated localhost origin; no production answers were submitted.

The deployment verified all 25 upload files, active/enabled service status and HTTPS health version 0.3.2. The HTTPS game-pack SHA-256 matches the tested local build: `9de766b43d6af2693e7ec14589f501a498bbb308cf9f0a2531b003af2818bf5c`. Release `/opt/escrow-invaders/releases/20260916T024427Z` is active; the previous release remains available for rollback. See the [release validation record](../../deploy/release-validation-navigation.json) and [deployment receipt](../../deploy/deployment-receipt-navigation.json).

Physical iPhone/native Safari installation and hardware performance remain untested. Prior release evidence is retained below.

## Historical version 0.3.1 revive update — deployed 2026-09-11 PT

**3,680 checks passed** for this update: **531 new revive checks** plus **3,149 existing checks rerun** against the changed source. The [revive release record](../../deploy/release-validation-revive.json) preserves the validation evidence; the [deployment receipt](../../deploy/deployment-receipt-revive.json) records activation. The previous release's evidence is retained below.

| Suite | Passed checks |
| --- | ---: |
| `test_revive_model.gd` | 70 |
| `test_arena_revive.gd` | 47 |
| `test_revive_ui.gd` | 414 |
| `test_study_model.gd` | 448 |
| `test_progression.gd` | 572 |
| `test_response_journal.gd` | 76 |
| `test_study_boost.gd` | 97 |
| `test_encounter_arena.gd` | 149 |
| `test_main_flow.gd` | 109 |
| `test_main_persistence.gd` | 34 |
| `test_study_boost_ui.gd` | 91 |
| `test_mobile.gd` | 1,520 |
| `test_service_worker.mjs` | 53 |
| **Total** | **3,680** |

The revive suites exercise real zero-hull defeat before and after the core question, preservation of the same live enemy health/packets/attempt/kill receipts, fatal-core explanation before revival, two wrong answers followed by a guided correct answer, hinted first recall, one successful revive per attempt, duplicate/paused inputs and explicit rebuilding. Revive records remain separate from core and three-question-boost recaps. The tests also cover active-boost isolation, wrong/earned/claimed disk reloads, and interrupted grading and claim saves. A reopened earned revive restarts the arena under the same attempt and reward receipts; the UI explicitly explains this limitation.

The new UI suite checks the longest official course question, hint feedback, retry, earned explanation and exhausted defeat at **375×667, 390×844, 430×932, 844×390 and 1280×720**. It verifies panel bounds, wrapped choices, readable question typography, touch target sizes and scrolling to final actions. The final 414-check rerun passed after the last feedback-copy and resume-cue corrections; log: `game/.runtime/revive-ui-final.log` from the project root.

Browser QA at **390×844 on isolated port 9478** reached actual defeat at zero hull with **44 XP and 11 coins** banked. A wrong revive answer kept hull at zero; a guided correct answer returned to the **same live fight at three hull with eight hostiles remaining**. The 44 XP and 11 coins were unchanged. Further combat ended in a second defeat with **64 XP and 16 coins** retained, and the screen correctly showed the revive as used with no second offer. No browser errors occurred. Test answers were isolated from production learner history.

Deployment activated `/opt/escrow-invaders/releases/20260911T204820Z` after **25 upload hashes passed**. The service is active and enabled, HTTPS health reports **0.3.1**, and Homepage, Tailscale routes and the service unit are unchanged. The prior `/opt/escrow-invaders/releases/20260911T082010Z` remains available for rollback. The served HTTPS game pack matched the final local SHA-256: `b28cc1f43e56f937bbd1b95d27a00e2a82923ab24aa88ceba10200460fcd756d`.

Physical iPhone/native Safari installation and hardware performance remain untested. The unchanged course bank's import/source-fidelity evidence belongs to the earlier validation below; its 940 course/installed-bank checks were not included in this update's rerun total.

## Historical version 0.3.0 — deployed 2026-09-11 PT

**4,079 checks passed** with Godot 4.7.2 and Node.js. The [release validation record](../../deploy/release-validation-endless.json) records the suite counts, deployed release and game-pack digest; the [deployment receipt](../../deploy/deployment-receipt-endless.json) records activation and rollback.

| Suite | Passed checks |
| --- | ---: |
| `test_study_model.gd` | 448 |
| `test_progression.gd` | 572 |
| `test_response_journal.gd` | 76 |
| `test_study_boost.gd` | 97 |
| `test_encounter_arena.gd` | 149 |
| `test_main_flow.gd` | 109 |
| `test_main_persistence.gd` | 34 |
| `test_course_bank.gd` | 29 |
| `test_installed_course.gd` | 911 |
| `test_mobile.gd` | 1,510 |
| `test_study_boost_ui.gd` | 91 |
| `test_service_worker.mjs` | 53 |
| **Total** | **4,079** |

The integration suites cover continuing beyond Levels 5, 20, 100, 125 and 1,000, duplicate response/kill/clear protection, fatal and guided core feedback, saved counterstrikes after defeat/reload, paused bonus timers, honest checkpoint recaps and a playable five-clear path without studying. High-level flow tests drive arena event boundaries deterministically; they do not represent manual play through those levels.

Study-offer checks cover three distinct course questions, wrong/hinted/solution recovery without hull penalties, separate first-attempt learning records, exact one-time clear XP/coin/gem payouts, bound upgrade prices and installation receipts, paid upgrades without study, leaving an active set to fight and then resuming its saved questions, completed-offer reloads and failed-save recovery. Learning and response-journal tests cover preserved legacy records, delayed mastery and interrupted commits without duplicate grading or rewards.

The arena suite tests finite objectives, genuine zero-hull defeat, unchanged enemy statistics across loadouts, distinct counterstrikes, readable resume grace, touch/keyboard speed parity and separate projectile budgets. Ten-seed opening calibration checks stationary losses, successful dodging and useful upgrades against the same enemies. The deployed Level 1–10 target HP values are 120/145/165/190/560/210/245/275/320/900; the [release calibration](../../docs/superpowers/specs/2026-09-11-endless-progression-design.md#deployed-combat-calibration--supersedes-the-draft-table) supersedes the original proposal's lower HP table.

Responsive checks use **375×667, 390×844, 430×932, 844×390 and 1280×720**, including the longest official questions, wallet/header bounds, all gameplay and study-offer phases, minimum touch controls and scrolling to the final action. The final 1,510-check mobile rerun and 34-check main-persistence rerun passed after the last UI fixes. Logs include `.runtime/release-ui-tests/`, `.runtime/endless-final-mobile.log` and `.runtime/endless-final-persistence.log` under the game folder.

The service-worker suite verifies downloaded decoded bytes against each build SHA-256 digest. Hash mismatches, HTTP/network errors and interrupted installs cannot activate a mixed release. Incomplete candidates are removed, complete prior caches remain intact, and neither `skipWaiting` nor `clients.claim` forces an open game onto a new release. Learner IndexedDB is not cleared.

Browser and deployment evidence:

- At **390×844 on isolated port 9476**, three official course reviews completed and a permanent upgrade installed, with no browser warnings or errors.
- Final-build gameplay at **390×844 on isolated port 9477** exercised sound, opening combat, the optional-core skip, resumed combat and an actual defeat at zero hull. **48 XP and 12 coins** remained banked, with no browser warnings or errors.
- Godot asset import and Web release export completed cleanly and gzip outputs were refreshed. The deployed package passed **25 upload hashes**; service health reported **0.3.0**, active and enabled. Live HTTPS health, manifest and worker returned 200, and the served game-pack SHA-256 matched the local export. Homepage, Tailscale routing and the service unit were unchanged; the previous release remains available for rollback.
- Test answers used isolated origins and did not alter production learner history.

The remaining device limitation is **no physical iPhone/native Safari installation or hardware-performance test**. The browser checks above use desktop phone-sized viewports. Automated checks and simulated combat do not establish enjoyment or long-term learning outcomes.

## Historical prototype validation

Validated on Windows on 2026-09-10 with official Godot 4.7.2 and the Codex browser.

- `test_study_model.gd`: 448 checks passed. Covers question integrity, randomized correct-answer mapping, core/bonus isolation, assistance and confidence, due review selection, delayed mastery, same-day remediation, persistence and corrupt-save handling.
- `test_main_flow.gd`: 92 checks passed. Runs the actual main scene through all five core encounters and both bonus opportunities; checks pause/timers, duplicate inputs, correct and missed bonuses, numeric recall, assisted retries, summary totals and the capped-lightning fallback.
- Arena smoke checks passed for bounded entities, damage grace, wave completion and reduced motion.
- Browser play confirmed the 1280 x 720 layout, correct-answer explanations, weapon selection, visible orbiting turret additions, drag movement, auto-fire, wave transitions, a 10-second bonus and its extra upgrade. No browser warning/error logs were observed during that play.
- The QA browser used port 9473. The delivered game uses port 9472, so QA answers are isolated from the learner's normal browser save.

The Windows headless runtime reported a host root-certificate-store warning while returning successful test/export results. The game uses no remote API or course connection.

These checks validate the prototype's behavior. They do not establish state-exam coverage, long-term learning outcomes, mobile suitability or production readiness. The initial prototype used original sample math; the final course import is documented below.

The stronger-penalty update additionally checks no automatic shield refunds, the combat damage floor, fatal core mistakes, failed-run input locking, saved remediation and restart resets. Main flow: 92 checks passed.

Course import preparation: 29 focused course-bank tests, 92 main-flow checks and 448 study-model checks passed. Empty collection was rejected by the import command without replacing the sample bank.

## Final course import — 2026-09-10

- Captured 35 raw files with complete question and official-review coverage for all seven regular categories and Hot Questions. There are 1,064 unique source IDs; all 100 Hot Questions overlap the regular categories.
- Imported 1,048 questions after merging four duplicate aliases and excluding 12 unique malformed source questions. All official keys and explanations match canonical source captures in the independent `question-bank/source-audit.json`. This is a source-fidelity check, not an independent current-law audit.
- Selected 99 short bonus questions, capped at 45 total prompt/choice words, across 43 local study topic labels.
- Final rerun: `test_course_bank.gd` 29, `test_study_model.gd` 448, `test_main_flow.gd` 92, `test_installed_course.gd` 911 — **1,480 checks passed**. The installed-bank test checks 50 seeded missions, 100/100 populated bonus slots, no repeated core items, familiar bonus topics, retained answer order, actual grading, long-choice bounds, scroll reachability and reset. Persistence is disabled for those test answers.
- Browser QA on port 9473 displayed the 1,048-question count, rendered question `prou-1208` and all four choices, accepted the official third choice, and displayed the exact official explanation with an upgrade button. No browser warnings or errors were returned. The learner's port-9472 tab was left in its existing mission.
- Godot 4.7.2 asset import and Web release export completed successfully. The export includes `res://data/course-bank.json`; gzip files were refreshed. No script or engine errors occurred in this final test/build run.

## iPhone app release — 2026-09-10 PT

- **1,590 checks passed**: existing 1,480 plus 110 mobile layout/touch checks. Sizes: 375×667, 390×844, 430×932, 844×390, 1280×800 and 1280×720. Tests use the longest real-bank question, scroll to its final answer, reset scrolling, exercise upgrades/summary, check HUD/panel bounds, and drive ScreenTouch/ScreenDrag without a mouse button. They verify second-finger isolation and steering release on pause. Test persistence is disabled.
- Browser QA verified ready, install dialog, long choices, correct-answer feedback, upgrades, full-screen combat and pause at phone sizes, plus the final compact desktop layout. Portrait/landscape resizing checked. Hosted ready screen rendered without browser errors; no test answers were submitted at the delivered origin.
- Cached app reopening succeeded with port 9474's test server stopped. A changed release activated after closing/reopening the old app window. The worker caches a complete version, leaves learner IndexedDB untouched and never force-reloads active missions.
- Manifest standalone mode and stable identity/scope, 144/180/512-pixel original icons and gzip contents validated. Final Godot import/export succeeded. Native install-dialog scrolling is allowed while the canvas captures touch steering.
- Deployment verified 25 upload hashes, active/enabled service, health version 0.2.0 and unchanged Homepage, service unit and Tailscale routes. Prior releases retained.
- No physical iPhone, native Safari, actual iOS home-screen install or hardware performance test was available. On-device testing remains the next hands-on check.
