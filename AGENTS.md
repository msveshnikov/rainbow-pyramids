# AGENTS.md — Rainbow Pyramids (Радужные пирамидки)

## Where everything is

| What | Where |
|---|---|
| Project (Godot 4.7, GL Compatibility) | `C:\My-progs\Godot\rings` |
| GitHub (public) | https://github.com/msveshnikov/rainbow-pyramids (remote `origin`, branch `master`) |
| Downloads | GitHub releases: `RainbowPyramids.exe`, `RainbowPyramids.apk` (`releases/latest/download/...`) |
| Google Play | «Радужные пирамидки», package `com.maxsoft.rainbowpyramids`, Play Console app id 4976247712351862733 (dev 5957945224586801272); first release 7 (1.0.6) sent for review 2026-11-18; 1.0.7 (code 8, glossy logo v3, new ru/en store art) sent for review 2026-11-18; 1.0.8 (code 9, glossy UI icons) web/GitHub only; 1.0.7 went live; 1.0.9 (code 10, icons + HUD layout fix + safe-area insets, new ru/en screenshots) sent for review 2026-11-19 |
| Play upload key | `~/.android/rainbowpyramids-upload.jks` (alias `rainbowpyramids`, password in `rainbowpyramids-upload.txt`); Godot reads it from `.godot/export_credentials.cfg` (preset.3). Never commit. |
| Live web build | https://severance.lol/7/ = https://maxims.top/pyramids/ |
| maxims.top portal card | source `C:\My-progs\Godot\snacks\maxims\index.html` + `img/pyramids.jpg`; server symlink `/var/www/maxims/pyramids -> /var/www/severance/7` |
| Android APK (debug-signed) | https://severance.lol/7/RainbowPyramids.apk |
| Server folder | `ubuntu@severance.lol:/var/www/severance/7/` (SSH key auth) |
| Godot exe | `C:\Users\msves\OneDrive\Рабочий стол\Godot_v4.7.2-stable_win64.exe` |
| Levels | `assets/levels/levels.json`, made by `python tools/gen_levels.py` |
| Sounds | `assets/audio/*` (CC0, sources in `assets/CREDITS.md`) |
| Concept art from the owner | `concept/` (ignored by Godot via `.gdignore`) |
| Save file | `user://save.json` (Windows: `%APPDATA%\Godot\app_userdata\Rainbow Pyramids\`) |
| Autotest output | `renders/game/*.png`, `renders/autotest.log` |
| Builds | `build/windows/RainbowPyramids.exe`, `build/web/`, `build/android/RainbowPyramids.apk` |

## Rules (from the design doc)

Each peg is a stack. Only the top ring moves. It may go onto an empty peg or onto a larger ring of the
same colour; a peg holds at most `cap` rings. Win = every colour on its own peg as a pyramid N..1.

## Test

```
G="/c/Users/msves/OneDrive/Рабочий стол/Godot_v4.7.2-stable_win64.exe"
"$G" --headless --path . --import
"$G" --path . --quit-after 9000 -- --autotest                       # portrait
"$G" --path . --resolution 1280x720 --quit-after 9000 -- --autotest # landscape (land_*.png)
```
The autotest picks pegs by screen position, checks rejection, solves level 1 and level 6 by taps,
tests undo and hints, replays every level's stored solution, and screenshots big boards. Exit code 0 = pass.

## Build and deploy

```
"$G" --headless --path . --export-release "Windows Desktop" build/windows/RainbowPyramids.exe
"$G" --headless --path . --export-release "Web" build/web/index.html
"$G" --headless --path . --export-debug "Android" build/android/RainbowPyramids.apk
"$G" --headless --path . --export-release "Android Play" build/play/RainbowPyramids.aab   # Google Play
scp -o BatchMode=yes build/web/* build/android/RainbowPyramids.apk ubuntu@severance.lol:/var/www/severance/7/
curl -sI https://severance.lol/7/index.pck
```
For a GitHub release: bump `version/code` + `version/name` in the Android preset, export, commit, push, then
`"/c/Program Files/GitHub CLI/gh.exe" release create vX.Y build/windows/RainbowPyramids.exe build/android/RainbowPyramids.apk --target master --title "Rainbow Pyramids X.Y" --notes-file notes.md`.

Bump `version/code` in the Android preset for every APK the user installs over an older one.
Keep MSAA off on web/mobile (Mali driver leak); `main.gd` turns 4x MSAA on only for desktop.

## Google Play updates

1. Bump `version/code` (+1) and `version/name` in BOTH Android presets, export the AAB.
2. Store graphics: `python tools/play_store.py` (icon, ru/en banners, 7+7 screenshots 1080x1920).
3. Play Console → Production → Create release → upload `build/play/RainbowPyramids.aab`, notes in `<ru-RU>`/`<en-US>` tags
   → Next → Save → Publishing overview → Send for review.
4. The built-in browser can't pick files: serve the repo with a local CORS server (127.0.0.1) and set the
   file input's `files` from a fetched blob (see the project memory for the snippet).
Declarations used: no ads, no data collected, no login, 13+, IARC all "No" (Everyone), assets not AI-made (the logo, incl. the glossy v3, was drawn by the owner's daughter).
Store screenshots: upload all at once in the asset panel, then drag them into order 1-7 (real drags work; keep drop points below the sticky header and above the bottom bar, scroll the slot container between moves).
Layout: `_place()` in main.gd sizes a control to its combined minimum before anchoring (a Button's own minimum ignores custom_minimum_size) and adds Android safe-area insets; IconButtons shrink-center so rows never stretch them. Check new UI at 462x1000, 540x960, 768x1024 and 1280x720.
