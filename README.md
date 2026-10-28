# Escrow Invaders

A real-estate study arcade built with Godot. Fight through endless sectors, evolve your ship, earn upgrades, and optionally answer real-estate questions for extra rewards. Version 0.9.0.

## Clone and play (Windows, macOS or Linux)

Install Git and Node.js 22 or newer, then run:

```sh
git clone https://github.com/ILoveRestockMonitors/escrow-invaders.git
cd escrow-invaders
npm start
```

Open **http://127.0.0.1:9472/** in Chrome, Edge, Firefox or Safari. Stop the server with Ctrl+C. No npm install, Godot installation, account, API key or home-lab connection is needed to play: the ready-built browser game is included.

On Windows you can also double-click **Play.cmd** after cloning; **Stop.cmd** stops that background server. Keep using the same browser and localhost address to retain progress. Your friend starts a separate save; no personal save data is included. The shared-save feature is disabled by default for local play.

## Controls

- Move: WASD or arrow keys; touch controls are available on phones.
- Repulsor: Space, or its on-screen button.
- Questions: W/A/S/D choose answers 1/2/3/4; Up/Down and Enter also work.
- Home, Upgrades, Weapons and Study are in the menu. Help explains contextual controls.

## Edit the game

The Godot source is at the repository root: open `project.godot` in Godot 4.7.2. Source changes require a new Web export before they appear in the browser build. Install matching Web export templates, then export the `Web` preset to `build/web/index.html` and run:

```sh
node web/finalize.mjs build/web
```

Remove any old `.gz` files after a manual export so the server serves the updated uncompressed files. Alternatively, on Windows, `Build.ps1 -GodotPath <executable> -TemplatesPath <template-folder>` exports and refreshes compressed copies.

## Check the server

```sh
npm test
```

Bundled fonts retain their OFL license files under `assets/fonts/` and `build/web/`. Asset provenance is in `assets/ASSET-SOURCES.md`. The included course question bank retains its original source attribution; no blanket open-source license is granted for third-party material.
