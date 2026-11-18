# AGENTS.md — Rainbow Pyramids (Радужные пирамидки)

## Where everything is

| What | Where |
|---|---|
| Project (Godot 4.7, GL Compatibility) | `C:\My-progs\Godot\rings` |
| Live web build | https://severance.lol/7/ |
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
scp -o BatchMode=yes build/web/* build/android/RainbowPyramids.apk ubuntu@severance.lol:/var/www/severance/7/
curl -sI https://severance.lol/7/index.pck
```
Bump `version/code` in the Android preset for every APK the user installs over an older one.
Keep MSAA off on web/mobile (Mali driver leak); `main.gd` turns 4x MSAA on only for desktop.
