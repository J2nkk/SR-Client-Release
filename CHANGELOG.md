# Changelog

## SR Client 0.55.0
- **Hosting works again:** Krunker's login service started storing login
  tokens with quote marks, and SR sent them that way, so Krunker treated SR
  as a guest ("Invalid User"). Tokens are now passed bare.
- **Host from where you are:** Start Game while in a lobby or game (e.g. the
  one you just hosted) creates the new game on that connection, like
  Krunker's page: no new lobby, no verification.
- **Login without a browser:** email + password, or a code sent by email,
  straight to Krunker's login service. SR keeps the login (encrypted, never
  the password) and renews it itself.
- **Username / Google login** still opens Krunker's page once, because
  Krunker verifies every username login with a CAPTCHA; SR keeps the login
  afterwards.
- **Verification:** Krunker asks for it on every new lobby, logged in or
  not. SR now runs it hidden; the window only appears if Krunker wants a
  puzzle solved (after 12 s).
- **Menus:** the mouse wheel scrolls the host page while over a text field;
  the settings window's Cancel/Save stay inside its border on the Display tab.

## SR Client 0.54.0
- **Faster HUD:** the built HUD (timer, scores, leaderboard, player panel,
  weapons, ammo, chat, FPS) is kept and drawn again for up to 1 ms instead of
  being rebuilt every frame. Health, ammo, weapon, FPS and window size rebuild
  it at once; everything else is at most 1 ms old, under one refresh of any
  monitor. Half the HUD's CPU time per frame.
- **Measured on a 9800X3D + RTX 5080, standing still on Site:**
  - Fullscreen: 6905 FPS vs 0.47's 6817, delay 0.216 vs 0.232 ms.
  - Windowed: 8573 vs 8136 FPS, delay 0.171 vs 0.179 ms.
  - Delay is from the frame reading input to the GPU finishing it.
  - Mouse to GPU done: about 0.37 ms (median).
- **For testers and developers:** SR's latency probe (only when started with
  SR_LATENCY_PROBE) now also prints mouse delay and CPU time per frame part.

## SR Client 0.47.0
- **Display note:** under Video mode: Fullscreen or Borderless recommended;
  Windowed goes through the Windows compositor and adds about 5 ms (measured
  with PresentMon: ~0.15 ms vs ~5.6 ms from a finished frame to the screen).
- **Network thread (Settings > Experimental):** now also answers Krunker's
  ping (pi -> po) the moment it arrives, as the browser does between frames,
  instead of on the next game frame. Every sender now holds one send lock
  from reading the packet counter to committing it. Inputs stay on the game
  thread, built per frame exactly like Krunker's client (hit registration
  unchanged).
- **CPU pinning on Ryzen X3D with two dies (7950X3D, 9950X3D, 7900X3D...):**
  the game thread goes to a core on the die with the 3D V-Cache (biggest
  L3). CPUs with one L3 size (9800X3D, Intel) pick the same core as before.

## SR Client 0.46.0
- **Inputs per second** (Settings > Experimental): 120, 240, 360 (default),
  480, 720, 840, 1000. These are real inputs per second; Krunker's own
  Network Rate numbers are half the real rate (its 360 sends up to 720), which
  the note under the setting explains.
- Settings that need a restart are marked with a red *.
- **Hit registration:** weapon timers (fire cooldown, reload, swap) run in
  Krunker's own millisecond math, so every shot is allowed on exactly the
  input where Krunker's server allows it.
- **Movement:** slides use each class's slide factors like Krunker (Spray N
  Pray was corrected after every slide).
- **Shots and hits:** predicted shots pass through players like the
  browser's; a hitmarker for every hit Krunker reports.
- **Infiltrator:** the Charge Rifle works like Krunker's (free shots that speed
  up as it charges, the full-charge blast uses the round), knife throws charge
  while aiming, with Krunker's charge bar.
- **Scope:** Krunker's scope settings (Settings > Interface). The scope image
  and black borders are off by default, as competitive players set them.
- **Death screen:** Krunker's kill cam: the camera turns to and flies towards
  your killer, you can look around against a pull, and the killer's name and
  health stay visible.
- **Burg:** the cart's wheels and axles are drawn.

## SR Client 0.40.0
Everything since 0.25.0.

**Hit registration**, each part checked against Krunker's own game code:
- **Inputs sent byte-for-byte like the browser:** the same packet compression
  and JavaScript rounding of look angles.
- **Shot timing exactly like the browser:** the value that tells the server how
  far back to rewind enemies is sent uncapped (the server clamps it), and a
  zero is left out, as the browser does.
- **Shots fire on the same input as the server:** weapon cooldowns end exactly
  like Krunker's whole-millisecond server timers. Before, many shots fired one
  input late, and on full auto SR showed less recoil kick than the server had.
- **Recoil per input, before the shot,** like Krunker's server (it advanced per
  screen frame, about 3% less during long sprays).
- **Spread after strafing** like Krunker: server corrections no longer re-count
  your movement spread.
- **64-bit frame clock:** frame timing, enemy movement and shot timestamps no
  longer get steppy after long sessions.
- **Landing dip on the camera,** like Krunker.

**Inputs per second** (Settings > Experimental): 240, 360 (default), 480, 720,
900, 1000. These are real inputs per second: the browser's Network Rate 360
sends up to 720 at high FPS, and 1000 is the most Krunker's protocol allows
(1 ms per input). Applies right away, no restart. Up to 64 inputs go in one
packet, so high rates never build a backlog.

**Tournament auto-host links:** `srclient://game?action=host-comp&...` with the
same parameters as Glorp's host link (mapId, teamSize, team1Name, team2Name,
webhook, compRosterT1/T2 or team1Players/team2Players, spectators). The
installer registers it; a link opened while SR Client runs is hosted by that
window. The Host page has Krunker's Team Rosters, and custom team names now
show in the lobby and scoreboard.

**Primary key** (Krunker's primKey, default T): straight to your primary
weapon. Chat is Enter only, as in Krunker. If your chat key was still SR's old
default (Enter + T), T moves to Primary once; your own binds are kept.

**Hardpoint:** Krunker's Capture marker with its clock, the Next marker in the
last 15 s of a rotation, CONTESTED; Krunker's round countdown and messages and
the spawn sound. Host game is a page and works from inside a lobby.

**Renderer:** a reworked Vulkan renderer (about 4-8% more FPS and smoother
worst-case frames on an RTX 5080), low-latency frame start, MSAA (Off to 8x),
VRR cap for G-SYNC/FreeSync with V-Sync. Turning Vulkan Renderer off runs
Classic (OpenGL, threads left to Windows, like 0.24).

**Also:** health bars like Krunker's; switching mods replaces every texture.

The reworked renderer, browser-exact input packets, recoil per input, frame
clock and Hardpoint markers are by ho (Cheesegle).

## SR Client 0.25.0
Everything from 0.24 stays.
- **Vulkan renderer, on by default:** the game draws with Vulkan 1.3, with
  the interface drawn in batches and no waiting on the GPU during a frame.
  The game thread gets its own CPU core. Turn it off in Settings > Video >
  Vulkan Renderer (applies on the next start) or start with `--opengl`.
  A GPU or driver without Vulkan 1.3 uses OpenGL automatically.
- **Hit registration:** inputs are sent at the lobby's own tick rate (as
  Krunker does) instead of a fixed 30 per second.
- **Sounds 1:1 with Krunker:**
  - Bullets hitting walls make no sound (Krunker plays none).
  - Bullets flying past you make Krunker's whizz sound.
  - Krunker's hit, headshot, crit, jump, step, slide, hurt, whizz and reload
    sounds are fetched from Krunker on the first start, so they are exactly
    Krunker's (the old crit sound was a copy of the hit sound).
  - Krunker's reload sounds at the start and end of a reload.
- **Mods:** loading a mod removes the old one first, so two mods' sounds no
  longer play over each other.
- **Health bars** stay on while you watch the death camera.
- **Clans:** clan tags on the leaderboard, in the scoreboard and in the
  lobby list, in Krunker's colours (special clans in gold).
- **UI Scale:** at UI Scale 1 the menu no longer zooms in and hides buttons.
- **Reset all settings** really resets everything and saves at once.
- **Hosting:** hosting right after a game no longer gets stuck on "Creating
  your custom game..." (SR waits for the Krunker login before hosting and
  shows a message if it fails).
- **Alt+F4** closes the game, also in fullscreen and while loading.
- **Hardpoint like Krunker:** the active point has Krunker's yellow marker
  with "Capture" and the point's clock; in the last 15 seconds the next
  point shows a white "Next" marker; "CONTESTED" when someone else is on
  the point with you (FFA). Krunker's **Objective Info Opacity** and
  **Objective Info ADS Opacity** (Settings > Video > Interface, default 1
  and 0.5) set how see-through the markers are, also imported from and
  exported to Krunker; a Krunker mod's objective icons replace the markers
  as in the browser.
- **Round messages like Krunker:** the countdown numbers and the mode title
  animate as in the browser; a round ending shows "Switching Sides" and who
  is in the lead, with Krunker's sounds; "Overtime" pops up when Krunker
  adds time. Spawning plays Krunker's spawn sound.
- **Menu:** Join lobby, Copy invite, Host game and Leave are at the bottom
  of the menu; Login has its own window. Host game opens as a page (not a
  popup), works from inside a lobby, and shows its progress with a Cancel
  button.

## SR Client 0.24.0
Everything from 0.23 stays.
- **Crosshair 1:1 with Krunker:** pasted Krunker crosshair settings now draw
  at Krunker's size. SR used the window's UI scale instead of Krunker's UI
  Scale setting, so crosshairs came out too big or too small.
- **Hitmarker images 1:1:** an image hitmarker is Krunker's 105x105 (at the
  same UI scale), full strength for 350 ms and fading over the last 100 ms.
- **Sound like Krunker:**
  - Other players are heard through the same HRTF "3D" panner Krunker uses
    (front, behind, above and below sound different, like in Krunker), not
    simple left/right panning.
  - Your landing makes a sound again, also when bhopping (Krunker plays a
    step when you hit the ground, before the next jump).
  - Krunker's volumes: hit and headshot confirmations at Krunker's loud 2.1,
    footsteps, your jump, slide and hurt sound at Krunker's levels, hurt sound
    at most twice a second, gunshots with Krunker's slight pitch variation.
  - Crouched enemies' steps are silent (as in Krunker); jumps and landings of
    other players are silent too (Krunker plays none).
  - Headshot kills play Krunker's headshot sound when the lobby has kill
    rewards on.
- **Nametags follow crouching like Krunker:** another player's nametag (and
  crouch) changes as soon as the server says they crouch, not one
  interpolation step later.
- Hide cats and Hide extra props are on by default (turned on once for
  existing settings too; turn them off in Settings > Visuals).
- F5 inside a game leaves and rejoins the same lobby.
- Mods: a mod's sounds replace SR's (a mod that blanks the hurt sound makes it
  silent); covered by a test now.

## SR Client 0.23.0
Everything from 0.22 stays.
- The network log (logs/krunker-network.log) is only written when something
  goes wrong (failed join, server error, rejected entry, connection error),
  together with the few dozen lines that led up to it. Normal games write
  nothing to disk. Developer builds still log everything.

## SR Client 0.22.0
Everything from 0.21 stays.
- The hit registration log (logs/hitreg.log) is now only in developer builds;
  normal builds do no extra work when you shoot.
- Developer tools: X-ray only works offline.
- logs/krunker-network.log can no longer grow without limit: past 1 MB it
  moves to krunker-network.old.log at start-up and a fresh log begins (at most
  about 2 MB in total, checked once per run).
- README: how SR Client works and how it is built.

## SR Client 0.21.0
Everything from 0.20 stays.
- **Legs fixed:** other players' legs swung mirrored to Krunker's hitboxes
  (left and right swapped since the first SR version), so a stepping leg was
  drawn where its hitbox wasn't. They now swing exactly with Krunker's
  hitboxes, standing and crouched (and the same in third person).
- Developer build for team testing (debug panel, F3) is now one complete
  package, kept only with the private test builds.

## SR Client 0.20.0
Everything from 0.19 stays; this is a hit registration check against Krunker's
current game code.
- **Hitboxes checked against Krunker's current game:** every player box size,
  the body/head/arm/leg pose maths and each weapon's arm hold points match
  Krunker exactly, so nothing there changed.
- **Crouch timing:** when another player crouches or stands up, Krunker's
  server tests your shot with the crouch from the newest update it sent you.
  SR switched halfway between updates (up to about 50 ms early or late); the
  model and SR's hit test now switch with the newest update, like the server.
- **Hit log:** the crosshair check now includes the recoil kick, as Krunker's
  shot does, so sprays and follow-up shots are logged correctly.

## SR Client 0.19.0
Everything from 0.18 stays; these are fixes and additions on top.
- **Other players are drawn where Krunker hits them.** Krunker's server tests
  shots against its own boxes (head, body, arms, legs) in the player's pose.
  SR now draws other players from those same numbers: the body bob, the arms
  and gun (no more reload/swap/lean swing on other players; the firing kick
  stays), and their stride from Krunker's own step value when Krunker sends
  it. A hit registration log (logs/hitreg.log) records, for every shot, what
  was under your crosshair and whether Krunker counted a hit, to check it in
  real games. Performance cost: none (the log only works when you shoot).
- **Shot timing:** a shot fired exactly on a server update no longer reuses the
  previous shot's timing (Krunker ignores a zero there).
- **Round countdown voice:** Krunker's 5-4-3-2-1 now plays with game sounds;
  it was on the UI channel, silent for anyone with UI sounds off.
- **After a game ends:** the final scoreboard stays until Escape, then SR is
  back to a fresh start screen with no old invite. New **Refresh (F5)** does
  the same any time. The invite box: double-click or Ctrl+A selects the whole
  link, holding Backspace keeps deleting.
- **Log out** (was "Forget browser session") asks for a second click; it was
  easy to hit by accident and logged you out completely.
- **Inside another player** (spawns, intermission) you now see past them, as
  in Krunker, instead of a screen full of their model.
- **Hitmarker image:** a link or file shown instead of the bars (like Glorp).
- Classes without a secondary choice no longer ask for a second confirmation.

## SR Client 0.18.0
Everything from 0.17.5 stays the same (HUD, look, textures, mods); these are
additions on top.
- **Custom games only.** Public matches can't be joined. Custom games still
  join whatever the mode or map (an FFA 1v1 too), and so do private lobbies
  such as comp games and bot-hosted games. Only a game Krunker lists as a
  public match is refused, and SR never lets the matchmaker move it into
  another game. Performance cost: none (checked once when joining).
- **Freecam (] key) only works offline** (local practice). In a live lobby it
  is off, since it could look through walls. Noclip, the hitbox viewer and
  the debug keys were already offline- or developer-only.
- **Host game.** Host game opens Krunker's Comp Server Setup inside SR, in
  SR's settings colours: Select (Krunker's comp maps, pick one or more),
  Game Settings and Server (locked for comp, as in Krunker), Advanced (game
  time, rounds, intermission, objective time, hitbox padding, hurtbox scale,
  team names, spectating, transfer host, spectator slots, team size 1v1 to
  4v4, cosmetics, test comp, no draws, best of rounds, head clip and ramp
  fixes, webhook, class limits) and Start Game. The game is created in your
  Default Region (Settings > General > Localization, Krunker's same list:
  Frankfurt, Silicon Valley, Sydney, Tokyo, Singapore, New York, Mumbai,
  Dallas, Brazil, Middle East; imported and exported as defaultRegion). SR creates the game itself, exactly as Krunker's page does
  (same message, byte for byte), so you're the host and your account is
  only connected once. Your setup is remembered. Needs a logged-in account;
  Krunker may ask you to verify you're human. Performance cost: none in game.
- **Krunker updates, the Glorp way.** Each start, SR asks Krunker once for
  its game version. When Krunker updated, SR checks every map with Krunker's
  map service and downloads only the changed ones, before you play (Join and
  Host wait a few seconds for it); nothing happens during a match. No new SR
  release is needed when Krunker updates a map. Log: logs/game-files.log.
- **Settings import like Glorp:** Import Keybinds / Import Sensitivity /
  Import Sound switches in the Import popup, so you can import someone's
  settings without their binds or sens.
- **More Krunker settings import:** impact holes, nametag style (Health Only,
  Name Only...), nametag display Off, Show Ping, Show UI, kill and death
  counters, nametag health colours (team / enemy), your health bar colours
  (high / low), and the FPS counter's update rate. Effects SR never draws
  (particles, muzzle flash, casings, screen shake, damage numbers, medals,
  death markers) count as matching when they're off. The import message says
  how many settings have no SR equivalent. New settings rows: health colours
  (HUD), Kill counter / Death counter (Game), FPS update rate (Display).
- **Laptops:** SR asks for the dedicated NVIDIA/AMD GPU instead of the
  integrated one, and asks Windows not to throttle it on battery.

## SR Client 0.17.1
- **Mods: second half of the cause.** The Mods window's own message loop
  handled window messages until there were none left. With Krunker's game
  running in that window there always are, so it never got to asking the page
  for the mod (seen live: the log stopped right after the page opened). It
  now handles at most 64 messages per pass and then checks.
- Performance cost: none in game.

## SR Client 0.17.0
- **Mods: the real cause found and fixed.** Checked live on a real Krunker
  Mods window: SR's watcher inside the page had the mod link ready
  ("MOD", user-assets.krunker.io/md80703/mod.zip), but SR's side of the
  window had stopped asking for it: zero checks reached the page. One check
  sent while the page was still loading never got an answer from WebView2,
  and SR waited for that answer forever. Now a check without an answer is
  dropped after 3 seconds and a new one is sent, so Load Mod is picked up
  within half a second. (The download and the unzip were tested against real
  Krunker mod zips: deflate and stored entries, folders, sounds, models.)
- Performance cost: none in game.

## SR Client 0.16.0
- **HUD redraws only when something on it changes** (timer, health, ammo,
  weapon, scores, leaderboard, chat, FPS, ping, settings, window size), with
  at least 10 redraws a second as a safety net. Changes now show on the same
  frame (no more up to 4 ms wait), and the HUD is drawn a few times a second
  instead of 240. Performance cost: one small number calculated per frame.
- **Mods window log:** %LOCALAPPDATA%\SR-Client\mods-log.txt is written by
  SR's side of the Mods window at every step (window opened, page loaded,
  watcher running or missing, mod link found / sent), so one test shows where
  Load Mod stops. No in-game cost.

## SR Client 0.15.0
- **Mods rebuilt small, like 0.5:** the Mods window only watches Krunker's
  downloads (fetch / XHR, exactly as in 0.5, when the window closed on Load
  Mod) and reads the link off the Load Mod button you click. Everything added
  in 0.6 - 0.14 that replaced Krunker's built-in browser functions is gone; it
  most likely is what kept 0.14's Mods window on the loading spinner.
  Paste link stays.
- **Tab board and end-of-game table look like Krunker's:** Krunker's font, one
  dark panel per team (team name and score on top), column names, a lighter
  row per player; you and teammates white, enemies red. Drawn inside the
  cached HUD, so holding Tab costs no extra FPS.
- **Weapon names** under the weapon icons, like Krunker (Assault Rifle,
  Pistol, Combat Knife).
- Performance cost of this version: none in game.

## SR Client 0.14.0
- **More FPS:**
  - The HUD is drawn into a picture at most 240 times a second and shown with
    one draw call per frame, instead of hundreds of small draws every frame.
  - Switching between the menu font and Krunker's font no longer copies about
    0.5 MB of font caches twice a frame (that came in with 0.9).
- **Krunker's font actually ships now.** It was left out of every build since
  0.9, so the HUD used the menu font and looked thin and off.
- **Mods, new ways to catch the mod:**
  - The link straight from the Load Mod button you click (and Krunker's "Paste
    Mod Url" box).
  - Krunker's own mod functions when they are called.
  - The zip itself when Krunker opens it, even from its saved copy.
  - New **Paste link** button in Settings > General > Mods: copy a mod link
    (Dropbox, Krunker) or the path of a .zip on your PC and press it.
- **Comp lobby:** the other team's classes show "???" in the lobby list too.
- **Settings look like before 0.11 again** (orange, same layout); new rows stay.
- **Sliders:** one decimal (UI Scale 0.6, 0.7), whole numbers where the step is
  whole, two decimals only on 0..1 values (opacity), four only on tiny ranges
  (hitmarker fade). Sensitivity unchanged.
- **HUD closer to Glorp's comp HUD:** team scores in team order (your team
  white, enemy red, smaller), round board stripes red (Alpha) and blue
  (Bravo), "next objective", "Team" in the player panel.
- Performance cost of this version's additions: none in game; the mods
  changes only run in the separate Mods window.

## SR Client 0.13.0
- **In-game HUD rebuilt from Krunker's own stylesheet, 1:1:** the timer box with
  FPS/ping beside it, mode and map under it, team scores, the round board, the
  leaderboard (enemies red, teammates white, you white) with the kill/death/"on"
  boxes, the bottom-left class picture, team and segmented health bar with the
  health number, the weapon list (held weapon bright, keys in the corner) and the
  ammo box. All the boxes use Krunker's two-tone dark frame and the same sizes,
  colours and font metrics.
- **Krunker's chat box sizes:** 413 wide at the same spot, 14px lines, kills and
  chat together like before.
- **UI Scale replaces HUD scale and works exactly like Krunker's** (0.1 to 1,
  default 0.7, same formula), so 0.7 here looks like 0.7 in Krunker/Glorp. It
  scales the menus too, and Krunker settings imports/exports carry it (scaleUI,
  uiScaling). A "UI Scaling" switch turns it off like in Krunker.
- **Comp lobby hides the other team's classes ("???")** like Krunker, so you
  can't see enemy loadouts before the round.

## SR Client 0.12.0
- **Mods, the real cause:** a mod you loaded once is kept by Krunker in the
  browser's storage and is not downloaded again, so SR Client never saw a link
  (that's why only the very first try in 0.5 closed the window). Now SR Client
  also takes the zip where Krunker reads or stores it (IndexedDB, Cache Storage,
  stored text, blob links) and copies it over; new mods still go by their link
  like in 0.5. Tested against a simulated Krunker page: cached mod and new mod
  both reach SR Client.
- **Nameplate healthbars appear and disappear at once**, like Krunker (no fade).
- **Hitmarker fade and other tiny values keep 4 decimals** (0.0062), everything
  else 3.

## SR Client 0.11.0
- **HUD scale without overlaps:** FPS/ping now scale with the HUD (they overlapped
  the timer box), the HUD scale is capped to what fits the window, and the
  leaderboard, chat box and round title keep clear of each other at any size.
- **Mods:** the mods window is exactly 0.5's again (it closed after Load Mod). The
  download and unpacking keep the newer unpacker; if a mod still fails, the
  message says why and the download is saved to
  %LOCALAPPDATA%\SR-Client\mods-last-download.bin, plus mods-debug.txt.
- **Settings look like Krunker's:** dark grey window, grey section bars, blue
  accent buttons.
- **New settings (Krunker has them):** Show HUD (Display), Bullet holes (Game),
  Anti-aliasing (Render, applies on next start).

## SR Client 0.10.0
- **Fixed: frozen after auto respawn.** The automatic respawn sent the entry
  request but then cancelled it client-side (an old 20 s entry timer from when you
  joined), so the server spawned you while SR Client never took control. The timer
  now starts with each respawn, and a spawn the server confirms always gives you
  control.
- **FPS limit** for the game (Settings > Display > FPS limit; Unlimited by default).
- **Mods:** the 0.8 filter that ignored zips from krunker.io hosts is gone (it could
  skip the mod itself). New fallbacks: the mod Krunker stores as loaded, and a debug
  file %LOCALAPPDATA%\SR-Client\mods-debug.txt with what the mods window saw, to
  find the cause if a mod is still missed.

## SR Client 0.9.0
- **Chat box like Krunker:** a dark box bottom left with the chat and the kill lines
  together (killer, weapon, victim), bigger text, long messages wrap. Names: you
  white, your team green, the enemy red. While typing the input row sits in the box.
- **Krunker's font** for the in-game HUD (Settings > Display > Krunker font, on by
  default; menus keep their font).
- **HUD scale** setting (Settings > Display > HUD scale, default 1.25): makes the
  whole in-game HUD bigger or smaller. Crosshair and hitmarker keep their size.
- **Under the leaderboard:** your kills, your deaths and the enemies on the point
  ("on 1"), like Krunker. The separate killfeed is gone: kills are in the chat box
  (Show killfeed still turns them on and off).
- **Mods:** back to how 0.5 worked: the mod's link goes to SR Client as soon as
  Krunker downloads it, SR Client downloads and unpacks it, and the window closes.
  Keeps 0.6's better unpacker and the error message that says why a mod fails.

## SR Client 0.8.0
- **Death stays in the game, like Krunker:** dying no longer drops you into the menu.
  The camera turns to your killer and zooms; **move the mouse to look around**.
  You respawn automatically (or click, with Auto respawn off). The round break
  also stays in the game. Only the end of the match opens the menu.
- **Round countdown like Krunker:** big 5, 4, 3, 2, 1 in the middle of the screen
  with Krunker's countdown sounds (downloaded once from Krunker), then the mode
  title ("Hardpoint / Attack the Objective") when play starts.
- **Leaderboard top right** like Krunker (on by default, Settings > Game >
  Leaderboard). The killfeed moves under it.
- **Mods:** also works when Krunker loads the mod where SR Client can't see the
  download: once Krunker's Mod Loader says "Success!", SR Client takes the mod link
  (pasted link or the mod's file) and loads it, and the window closes. Dropbox
  share links are fetched as files.
- **Chat in local practice:** Enter/T opens the chat there too (shown only to you),
  to try it out.

## SR Client 0.7.0
- The mods window shows the normal Krunker page again (0.6.0 covered it, which also
  hid the mod previews). Everything else from 0.6.0 stays.

## SR Client 0.6.0
- **Mods fixed:** SR Client now takes the exact zip Krunker loaded inside the mods
  window (no second download), so "The mod could not be unpacked" is gone. The
  unpacker also handles Zip64 and streamed zips, and if a mod still fails the message
  says why.
- The previously loaded mod that Krunker re-applies on page load is ignored; only
  the mod you click counts.
- **Fewer decimals:** slider values show at most 3 decimals (0.535 instead of
  0.53538436), and dragging stores at most 3. cm/360 is unchanged.
- **SR Client icon** for the game window, taskbar, desktop shortcut and installer.

## SR Client 0.5.0
- **Chat like Krunker:** press **Enter** (or **T**) to type, **Tab** switches Team / All,
  Enter sends, Escape cancels. Messages show bottom left with the kill lines.
  A comp match starts on Team chat, as in Krunker. Typing never moves or shoots.
  Names and letters such as č, š, ž display correctly. The chat key can be rebound
  (Settings > Controls > Chat).
- **Mods load live:** Load Mod in Krunker's Mods window now swaps the textures,
  models and sounds right away, in the menu or in a match. Remove brings the default
  files back right away. No restart needed anymore.
- **Settings laid out like Krunker's:** General, Controls, Display, Render, Game,
  Sound, plus **Experimental** for SR Client's own extras.
  - Controls: DPI + cm/360 (instead of a sensitivity slider), key binds.
  - Display: video mode, interface (timer, nametags, killfeed), crosshair,
    hitmarkers, damage.
  - Render: shadows, lighting, filtering, image and map details.
  - Game: FOV, viewmodel, trails, competitive (auto respawn, enemies on point,
    mini scoreboard, chat).
  - Experimental: **Network thread** (off by default) and night mode.
- **Network thread (Experimental):** reads the game connection on its own thread so a
  network spike never stalls a frame, and snapshots are timed by their real arrival.
  It doesn't raise average FPS. Off by default until tested.

## SR Client 0.4.0
- **Death like Krunker:** no more menu/freeze on death. The game keeps running, the
  camera turns to your killer and slowly zooms in, the killfeed stays visible.
  **Auto respawn** when the cooldown ends (Settings > HUD > Competitive), or click
  to respawn with it off. Escape still opens the menu.
- **Enemies on point** counter next to the enemy hardpoint score (glorp's method).
- **Mini scoreboard** on the right side (off by default).
- **Kill chat** bottom left ("X killed Y"), visible while dead.
- **Krunker mods:** Settings > Main > Mods > Browse mods opens Krunker's own Mods
  window. Press Load Mod and SR Client loads that mod (applies on restart).
  Remove button to go back to default files. The Documents\SR-Client\mods folder
  from 0.3.0 is no longer used and can be deleted.
- No console window next to the game anymore.
- Network log now records the contents of packets SR Client does not read yet
  (needed to add player chat).
- Builds also produce SR-Client-Measuring-x.zip (sr_client_dev.exe, F3 shows where
  frame time goes).

## SR Client 0.3.0
- **Image crosshair:** Settings > Gameplay > Crosshair > Type > Image. Copy an image
  link (e.g. Discord "Copy Link") and press Paste link, or paste a PNG/JPG file path.
  Width and height adjustable. Downloads once, then works offline. Discord WebP links
  are fetched as PNG. Imported from Krunker's crosshairSho 4 / crosshairImage.
- **Mods (resource swapper):** Settings > Main > Mods > Open mods folder
  (Documents\SR-Client\mods). Krunker mod .zip files or sound/textures/models/img
  folders replace the game's files. Restart to apply.
- **Better Krunker import/export:** shadows, soft/high-res/dynamic shadows, lighting,
  gun volume and the image crosshair now import from Krunker/glorp settings.
- **"K" badge** marks every setting that works exactly like Krunker's.
- Fixed: resetting only the Gameplay or HUD tab now also resets hitmarker and
  damage-border settings.

## SR Client 0.2.0
- Moved onto the newest engine code: big FPS boost on large maps, high-polling-rate
  mouse fix, shadows and lighting, night mode, menu FPS limit, scroll-wheel binds,
  unbind keys, settings reset, crosshair sliders, Intel/AMD fixes, player legs,
  wall-jump limit per class, end-of-match result fix, cursor in exclusive fullscreen,
  smoother healthbar visibility, Bureau fountain, ramp rubberbanding, positional audio.
- Added killfeed, hitmarkers (editable + toggle), damage borders and hit indicators
  (customizable), and the Frontier objective sites fix.
- Settings > Reset also resets hitmarker and damage settings.
- Network log console echo is opt-in (SR_CONSOLE_LOG=1); input-backlog logging is
  sampled during ping spikes; curl tracing stops after the connection handshake.
- Starts correctly from shortcuts or any folder.
- One-click installer and portable zip built by GitHub Actions.

## v0.0.2-alpha (unreleased)

The first substantive jump since v0.0.1-alpha: melee went from a stub to a
working weapon, bullet tracers and wall impacts landed, and the renderer got a
round of performance work.

### Added

- **Killfeed** — Krunker's top-right kill notifications: killer, mirrored weapon
  icon, wallbang/headshot markers and victim, "You" in white, teammates green
  and enemies red. Lines last 4 s; Settings > HUD has Show killfeed and
  Killfeed limit (1–10, default 8). Works in live lobbies, on the native server
  and in local practice.
- **Melee** — flat 50 damage matching the original, plus a shoulder-pivot
  swing that sweeps left↔right each attack with the knife gripped in the hand.
- **Bullet tracers** — instant full-length beams that fade in ~80 ms, plus wall
  impact decals.
- **Hardpoint round progression** — round resolution, score resets, and overtime
  sudden-death when the timer runs out on a tie.
- **FPS meter toggle** — show or hide the on-screen FPS counter from the settings
  panel.

### Changed

- **Physics** — ray-box collision now tests map geometry and separate body/head
  hitboxes.
- **Renderer** — shader uniform locations are cached, opaque scenes skip the
  depth sort, and the viewport is cached instead of queried every frame.
- **Fullscreen** — fullscreen mode now switches to the monitor's maximum
  resolution instead of defaulting to 1280x720.
- **Build** — `make PROFILE=minimal` and `make PROFILE=speed` optimization
  levels; default stays `none` for fast development builds.

### Known limitations

- Best-of-three match resolution is not wired up yet — rounds are best-of-one.
- SRM movement (dash, wall-dash) is not implemented.
- The Crossbow weapon is missing and knife throwing is still a stub.
- The simulation is not deterministic yet (unseeded RNG, no replay tests).
- Performance is a work in progress — build with `PROFILE=speed` for the best
  framerate.
