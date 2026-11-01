# AMX Mod X gameplay example (Counter-Strike 1.6)

`pj010_gameplay.sma`: four small gameplay mods in one plugin, with every player-visible text
in a language file, so the same plugin shows English or Traditional Chinese per player.

| command | what it does |
|---|---|
| `G` (the drop key) | Leap forward; cooldown bar on the HUD (4 s). The weapon is not dropped |
| `gp_tower` | An enemy "main tower" in front of you: three copies of the map's crate + a red crystal. Shoot it to win the round |
| `gp_sentry` | A sentry gun that turns and fires at enemies; kills are credited to you |
| `gp_zombie` | Become a zombie: zombie player model, crowbar hands, 1000 hp, until you respawn |
| `gp_lang en` / `gp_lang tw` | Switch this plugin's texts to English / Traditional Chinese |

Needs AMX Mod X 1.10 with Metamod (or ReGameDLL + Metamod-R). Local / LAN servers only.

## Build and install

```
cd cstrike/addons/amxmodx/scripting
amxxpc pj010_gameplay.sma -opj010_gameplay.amxx
```

| file | goes to |
|---|---|
| `pj010_gameplay.amxx` | `cstrike/addons/amxmodx/plugins/` + a line `pj010_gameplay.amxx` in `configs/plugins.ini` |
| `data/lang/pj010_gameplay.txt` | `cstrike/addons/amxmodx/data/lang/` |
| zombie model (optional) | `cstrike/models/player/zlab/zlab.mdl`; without it the plugin uses `vip` |

Bind the commands if you like: `bind t gp_tower`, `bind y gp_sentry`, `bind u gp_zombie`.

## Hold-to-spray HE grenades (`pj010_nadespray.sma`)

A separate plugin: hold a key and HE grenades pour out in front of you.

```
cd cstrike/addons/amxmodx/scripting
amxxpc pj010_nadespray.sma -opj010_nadespray.amxx
```

Copy `pj010_nadespray.amxx` to `plugins/`, add `pj010_nadespray.amxx` to `configs/plugins.ini`, then in the console:

```
bind mouse3 +nadespray
```

| cvar | default | what |
|---|---|---|
| `ns_interval` | `0.05` | seconds between grenades |
| `ns_duration` | `5.0` | longest spray per press (5.0 / 0.05 = 100 grenades); press again for more |

Each grenade is a real `grenade` entity (kill feed shows the HE icon), bounces, and explodes 1.5 s later:
100 damage falling to 0 at 350 units, credited to the thrower, who is never hurt by their own spray.

Pitfalls:

- **`set_task` cannot repeat faster than 0.1 s.** The timing is checked every frame in `PlayerPreThink`;
  a late frame throws the grenades it missed, so one press is always duration / interval grenades.
- **`MSG_PVS` needs an origin.** `message_begin(MSG_PVS, SVC_TEMPENTITY)` without one sends the explosion
  to whoever can see the map origin, usually nobody: the grenades do damage but no explosion is drawn.
- **Do not spawn the grenade right at the eyes**: closer than ~64 units its model fills the screen.
- Only grenades marked by this plugin (`pev_iuser4`) are touched in the `grenade` think hook; the game's own
  HE / flash / smoke / C4 keep their behaviour.

Measured on a local listen server, cs_assault (scaled copy), fps_max 100, 3 bots + 4 hostages:
0.05 / 0.1 / 0.15 s all stayed at 99-101 fps with ~31 / 15 / 10 grenades alive at once; even 0.01 s
(154 alive) stayed at 100 fps, using 312 of 1905 edicts.

## Languages

The plugin never prints a literal string; it calls `register_dictionary("pj010_gameplay.txt")`
and formats with `%L`, which picks the text by the player's `lang` setinfo
(`amx_client_languages 1`, the default). A player switches with `gp_lang tw` or
`setinfo lang tw` in the console; the HUD changes on the next refresh.

Add a language: append a block with the same keys to `data/lang/pj010_gameplay.txt`

```
[ja]
GP_LEAP_WAIT = [G] 跳躍  %.1f 秒  %s
GP_LEAP_READY = [G] 跳躍  OK
...
```

- Save the file as UTF-8. Keep every key and the `%` placeholders in the same order (`%.1f` then `%s`).
- A missing key falls back to the server language (`amx_language`, `en`).
- The code is any short tag (`tw` is not in AMXX's `languages.txt`, and does not need to be;
  add it there only if you want it listed in `amx_langmenu`).
- Chinese renders fine in HUD and center messages on the 25th-anniversary client.

## Pitfalls this example already handles

- **Tower hit box**: an invisible box with a *brush* model. With a studio model as the box,
  bullets test that model's small hit boxes instead, and most shots miss.
- **Set the origin after the solid type**, or the box is not linked into the world and bullets pass through.
- **Copied brush models draw black** unless you copy `rendermode` / `renderamt` from the map's own entity.
- **Several entities can share one brush model** (`*33` three times here) — draw and collide fine.
- **Do not spawn HL monsters mid-round**: their `Spawn` precaches, and precaching after map load
  kills the server (`Host_Error: PF_precache_model_I: ... Precache can only be done in spawn functions`).
- **HL monster models as player models**: some keep textures in a second file (`zombieT.mdl`).
  Copy both (`zlab.mdl` + `zlabT.mdl`) or the client stops with
  `Mod_NumForName: models/player/zlab/zlabT.mdl not found`.
