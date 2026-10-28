# Generated game asset sources

Generated 2026-09-10 with the built-in image_gen.imagegen tool (default built-in mode). Each asset was generated once. No CLI or fallback model used. Originals were retained; staged assets are byte-for-byte copies with no image editing.

## Arena background

- Output: `arena-background.png` (1536 × 1024, RGB).
- Original: generated for this game with OpenAI ImageGen.
- Style reference: the original Bullet Heaven project concept.
- Intent: generate a new environment using the reference for style; reference supplied with `referenced_image_paths`.
- Visual QA: detailed station edges, spacious starfield play area, no baked UI/text/ships/enemies.

### Exact prompt

```text
Use case: stylized-concept
Asset type: production background texture for a playable 2D arcade game, landscape 3:2.
Input image: Image 1 is a STYLE REFERENCE ONLY: premium detailed pixel-art space station atmosphere and navy/cyan/purple colors. Do not reproduce its interface or its gameplay objects.
Primary request: create one atmospheric top-down / lightly isometric 2.5D pixel-art orbital station arena BACKGROUND, with dark deep navy and faint purple starfield center and decorative industrial orbital station buildings clustered along the far left and far right outer edges. Detailed structures have cool cyan and subtle orange window lights, metal paneling, satellite arrays, small space rocks only at edges. Edges can be dense and polished. The central 75 percent of the image must remain spacious, quiet, dark and highly readable so separately rendered animated enemies and ships can be seen clearly. Mild stars and faint nebula in the center, nothing bright or busy there. Complete rectangular full bleed landscape 3:2 image.
Style/medium: beautiful crunchy premium 2D pixel-art game environment, coherent lighting, energetic arcade science fiction.
Constraints: Background only. Absolutely NO text, letters, symbols, numbers, signage, logos, UI, interface, panels, borders, question cards, answer choices, player ships, enemies, turrets, bullets, laser beams, pickups, explosions, bright visual effects, or characters. No big glowing centerpiece. No mockup.
```

## Player ship

- Output: `player-ship.png` (1254 × 1254, RGBA).
- Original: generated for this game with OpenAI ImageGen.
- Intent: generate a new standalone sprite, no image reference.
- Visual QA: one upward-facing ivory/cyan ship, dark readable silhouette, centered object, no text or other objects. Genuine alpha transparency checked at the corner.

### Exact prompt

```text
Use case: stylized-concept
Asset type: single production player sprite for a playable 2D arcade game.
Primary request: ONE small advanced spacecraft, facing straight UP, seen exactly from directly overhead, with symmetrical wings, ivory white armored panels, deep navy mechanical seams, cyan cockpit and lights, and one short bright cyan thruster flame pointing down below the stern. Appealing chunky readable pixel-art silhouette with strong dark outlines and a few warm brass accent details. The ship should feel like a polished premium pixel-art arcade bullet-heaven game. One centered object, large in a square canvas, with comfortable transparent margin, designed to read beautifully when downscaled to about 50 pixels.
Background: genuinely fully TRANSPARENT RGBA background with preserved alpha, including around the thruster glow. Isolated sprite.
Constraints: ONE spaceship only, no shadow plate or backdrop, no stars, no grid, no checkerboard drawn into the image, no text, no labels, no logo, no UI, no orbiting objects, no extra ships, no enemies. Top view, pointed UP, not side view and not isometric.
```

## Repulsor presentation update — 2026-10-06 PT

Existing generated background/ship pixels are retained. The new hangar, enemy hull panels, cached radial glow textures, star layers, projectile trails and impact rings are original procedural Godot drawing. Lighting uses layered translucent textures compatible with the web renderer; it is not HDR bloom or ray-traced lighting.

The updated audio is original procedural synthesis: 17 effects and a four-bar 120 BPM score with chords, bass, arpeggios and percussion. No downloaded recordings, samples or new third-party art assets were introduced.

Implementation research: [Godot custom 2D drawing](https://docs.godotengine.org/en/stable/tutorials/2d/custom_drawing_in_2d.html), [radial textures for 2D lighting](https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html), and [AudioStreamWAV PCM and loop boundaries](https://docs.godotengine.org/en/4.5/classes/class_audiostreamwav.html).

## Orbital Closing Desk — 2026-10-06 PT

The existing background, ship and synthesized audio are unchanged. Original code-drawn interface elements add the house lockup, speaker/pause/play icons, sector stepper, hull pips, Repulsor segments, stamps and confetti. Decorative web animation is implemented in `web/cockpit.css` and `web/cockpit.js`, with presentation snapshots via [Godot JavaScriptBridge](https://docs.godotengine.org/en/stable/classes/class_javascriptbridge.html).

Bundled fonts: [Chakra Petch Bold](https://github.com/google/fonts/tree/main/ofl/chakrapetch) and [IBM Plex Sans variable](https://github.com/google/fonts/tree/main/ofl/ibmplexsans), downloaded from the official Google Fonts repository. SIL Open Font License copies accompany both fonts in `assets/fonts` and the exported web package. No runtime font CDN is used.
# Ship evolutions — 2026-10-13 PT

`evolutions/ship-01.svg` through `ship-05.svg` are original vector hulls authored for this game by `deploy/prepare_evolution_update.py`. The five private concept sheets in the project's `mockups/evolutions/` use the same hull geometry. No external image assets or licenses are introduced. `ship_evolution.gd` loads the exact playable SVGs for combat and hangar displays; the original player PNG remains the starter ship.


## Veteran hulls and boss bodies - 2026-10-13 PT

`evolutions/ship-06.svg` through `ship-10.svg` and the matching private concept sheets are original code-authored vector art. The original five hull files are byte-identical to 0.7.0. Boss and new enemy bodies are original normalized polygon geometry in `combat_patterns.gd`, drawn by the existing Godot renderer. No external assets, licensing changes or new audio are introduced.
