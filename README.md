# SR Client

A native Krunker client for competitive and custom lobbies. The game runs as a
real desktop program (Odin + Vulkan), not inside a browser.

## Download & play
1. Go to **Releases** and download `SR-Client-Setup-x.y.z.exe`.
2. Run it. SR Client installs for your user (no admin) and starts.
3. Press **Login**, sign in to Krunker, paste a lobby invite and press **Join**.

Prefer no installer? Download `SR-Client-Portable-x.y.z.zip`, unzip anywhere,
run `sr_client.exe`.

**Best experience: play in Fullscreen or Borderless** (Settings > Display >
Video mode). Both send frames straight to the screen (~0.15 ms from a
finished frame to the screen, measured with PresentMon). Windowed goes
through the Windows desktop compositor and adds about 5 ms of delay.

Requirements: Windows 10/11 and a GPU with Vulkan 1.3 (any GPU from about
the last ten years); older GPUs use OpenGL 4.5 automatically. The Krunker login window
uses Microsoft's [WebView2 runtime](https://developer.microsoft.com/microsoft-edge/webview2/),
which is already installed on almost every PC. WebView2 is only used to sign in
(and for Krunker's verification check and Mods window); the game itself does not
run in a browser.

## Features
- Native rendering with shadows, lighting and night mode
- **Custom and comp games only:** join any custom game by invite link (FFA 1v1s,
  bot-hosted and private comp lobbies included). Public matches are blocked.
- **Host game:** Krunker's Comp Server Setup inside SR (maps, team size 1v1–4v4,
  rounds, timers, class limits and every other comp option). SR creates the game
  itself and you are the host. The game runs in your Default Region
  (Settings > General).
- **Always up to date:** at start-up SR checks whether Krunker updated and
  downloads changed maps before you play; no new SR release needed.
- **Hitboxes you can trust:** other players are drawn exactly where Krunker's
  server tests your shots: head, body, arms and legs all move with Krunker's
  own hitboxes (checked against Krunker's game code)
- **After a game:** the final scoreboard stays until Esc, then a fresh start
  screen; **Refresh (F5)** resets SR any time. Invite box: double-click or
  Ctrl+A selects the link, holding Backspace keeps deleting
- Krunker's 5-4-3-2-1 round countdown voice
- Sensitivity in **cm/360** with mouse DPI, optional separate ADS cm/360
- Killfeed, hitmarkers (bars or your own image) and damage borders, all customizable
- Crosshair, viewmodel, FOV, keybinds (scroll wheel, unbinding), FPS limits
- Image crosshairs from a link (Discord "Copy Link") or a file
- Krunker mods: browse Krunker's own Mods window from Settings; mods load live, no restart
- Krunker chat (Enter/T to type, Tab for Team/All), death cam, auto respawn, enemies-on-point counter, mini scoreboard
- Settings laid out like Krunker's (General, Controls, Display, Render, Game, Sound) plus an Experimental tab
- Import your Krunker (or Glorp) settings, with switches to skip keybinds,
  sensitivity or sound; settings marked **K** work exactly like Krunker's
- Uses the dedicated GPU on laptops
- **Inputs per second** (Settings > Experimental): 120 to 1000 real inputs per
  second; Krunker's own Network Rate numbers are half the real rate, so 720 is
  exactly the browser (SR's default is 360)
- **Weapons 1:1 with Krunker's code:** fire, reload and swap timers in Krunker's
  own milliseconds; each class's slide; Infiltrator's knife charge and the
  charge bar; Krunker's scope settings (image and borders off by default, as
  competitive players use them); Krunker's kill cam that turns to your killer
- **Low delay, high FPS:** about 0.2 ms from reading your input to the GPU
  finishing the frame, and about 0.4 ms from a mouse movement (9800X3D +
  RTX 5080, Fullscreen); the HUD is cached so it costs almost nothing per frame
- **CPU pinning:** the game thread gets a core of its own (on Ryzen X3D chips
  with two dies, a core on the 3D V-Cache die)
- Reset to defaults

Game files (maps, models, textures, sounds) are plain files in the `assets`
folder next to `sr_client.exe`, not packed into the program, so they can be
modded.

## Version history
Every release stays on the **Releases** page, so you can see how SR grew.
Full details per version are in [`CHANGELOG.md`](CHANGELOG.md).

| Version | Highlights |
|---|---|
| 0.55 | Hosting works again (bare login tokens); host from the lobby or game you are in without verification; email/password and email-code login without a browser; hidden verification; menu scroll and settings border fixes |
| 0.54 | Faster HUD (half its CPU time); more FPS and less delay than 0.47 in Fullscreen and Windowed; mouse delay in the latency probe |
| 0.47 | Fullscreen/Borderless recommendation under Video mode; the Experimental network thread answers Krunker's ping as soon as it arrives; X3D V-Cache core pinning; same or better FPS and delay than 0.46 in every display mode |
| 0.46 | Hit registration timers in Krunker's exact milliseconds; class slides; Infiltrator knife charge and charge bar; scope settings; Krunker's kill cam; Burg's cart wheels; inputs-per-second choices 120-1000; red * on settings that need a restart |
| 0.40 | Browser-exact hit registration; inputs per second; auto-host links |
| 0.25 | Vulkan renderer on by default with its own CPU core; inputs at the lobby's tick rate; Krunker's sounds 1:1; hardpoint markers and round messages like Krunker |
| 0.23 | Earliest build on the Releases page: the native client for custom and comp games; the network log is only written when something goes wrong |

## How it works
- **Same game, same servers.** SR Client connects to Krunker's own game servers
  and speaks Krunker's network protocol, so you play in the same lobbies as
  browser players. Krunker's server decides every hit, kill and round, exactly
  as in the browser.
- **Native instead of a browser.** Krunker normally runs as a web page. SR
  draws the game itself in a desktop program (Odin + Vulkan), with Krunker's
  maps, models, textures and sounds as plain files. No browser engine runs
  while you play, which is where the FPS gains come from.
- **What you see matches the server.** Other players are drawn from the same
  numbers Krunker's server uses for its hitboxes, at the moment in time the
  server checks your shot, so what you aim at is what the server tests.
- **Login stays Krunker's.** Signing in opens Krunker's own login page in a
  small Microsoft WebView2 window; SR never sees your password. After that the
  window closes and the game runs natively.
- **Comp and custom only.** SR joins invite links and hosts comp games; public
  matchmaking is blocked.

## How it's built
- Written in [Odin](https://odin-lang.org) with Vulkan 1.3 (OpenGL 4.5 fallback) for rendering and
  [Clay](https://github.com/nicbarker/clay) for the menus.
- `src/client`: the game client (rendering, input, HUD, audio, settings).
- `src/krunker`: Krunker's network protocol (messages, game state).
- `src/shared`: game rules shared by everything (movement, weapons, hitboxes).
- `src/menu`: menus and settings screens.
- `src/browser_helper`: the small WebView2 window for login, verification and mods.
- GitHub Actions builds the Windows installer and portable zip on every
  release; `build.bat all` builds the same locally (see below).

## Making a release (maintainers)
1. Game files (Krunker models, textures, sounds) live in `game-files/sr-game-files.zip`.
2. Bump `VERSION`, add a `CHANGELOG.md` entry, commit.
3. On GitHub: **Releases → Draft a new release**, tag `vX.Y.Z`, **Publish**.
   GitHub Actions builds and attaches the installer and portable zip.

Every normal push also builds; the files are under the run's **Artifacts**.
Developer builds (`SR-Client-Dev-*`, debug panel) are never attached to releases.

## Building locally
Install [Odin dev-2026-10](https://github.com/odin-lang/Odin/releases/tag/dev-2026-10)
and Visual Studio Build Tools, then run `build.bat all` from the
"x64 Native Tools Command Prompt". Client builds compile the shaders to SPIR-V
first, so the [Vulkan SDK](https://vulkan.lunarg.com/)'s `glslc` must be on `PATH`
(playing needs only a Vulkan or OpenGL driver). Put the contents of
`game-files/sr-game-files.zip` next to `bin\sr_client.exe`.

Renderer switches: `--vulkan` / `--opengl` override the setting for one run;
`--gpu-debug` logs driver messages (OpenGL: `logs/gl-debug.log`; Vulkan: validation
layers to `logs/gpu-debug.log`, needs the Vulkan SDK); `SR_GPU=<index or part of a
name>` picks the Vulkan GPU on a multi-GPU machine. `build.bat tests-vk` runs the
client tests on Vulkan with validation on.
Engine notes: [`doc/ENGINE-README.md`](doc/ENGINE-README.md).

## Logs
Bugs: send `logs\krunker-network.log` from the install folder
(`%LOCALAPPDATA%\SR-Client\app`). Set `SR_CONSOLE_LOG=1` to mirror it in the console.

## Credits
- Krunker game assets: © FRVR
- [Clay](https://github.com/nicbarker/clay) UI, Rajdhani font (SIL OFL)
