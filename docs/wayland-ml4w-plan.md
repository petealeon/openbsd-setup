# An ML4W-class desktop on OpenBSD 8.0 — plan

Status: **plan only, nothing implemented.** Target: the T480s on OpenBSD 8.0
amd64. Rehearsal VM is X11-only (see [Why the VM cannot rehearse this](#why-the-vm-cannot-rehearse-this)).

Companion: [`x11-ml4w-plan.md`](x11-ml4w-plan.md) — the same target without
Wayland. It reaches further on visuals (picom blur, rounded corners,
animations, themed login) and is fully rehearsable in the VM; it also revises
the sequencing below.

## TL;DR

1. **Yes, this is now possible.** OpenBSD 8.0 ships Wayland 1.26 with Sway,
   Niri, Labwc, Wayfire, Cage, CoW, Mango and River, plus waybar, foot,
   fuzzel, fnott, swaybg, swaylock/idle, grim/slurp, wl-clipboard, cliphist
   and awww. An ML4W-shaped desktop is a packaging exercise, not a porting
   project.
2. **Do not adapt the ML4W dotfiles.** Two independent reasons, either one
   fatal: they are **GPLv3**, and they are **Hyprland configuration** (Lua
   config, `hypr*` tools, Quickshell QML), none of which exists on OpenBSD.
   Mine them for the feature list and layout ideas, then write our own.
3. **Compose:** `sway` + `waybar` + `foot` + `fuzzel` + `fnott` + `swaybg` +
   `swaylock`/`swayidle` + `grim`/`slurp` + `cliphist`, on **sndio** (not
   PipeWire), with the existing amber palette as the single source of truth.
   All MIT except the clipboard pair.
4. **Biggest structural difference, and the one that decides the design:**
   there is no graphical login for Wayland on OpenBSD. `xenodm` and a
   compositor cannot both own the console. The session becomes
   *console login → `startsway.sh` on ttyC1*, with the current
   xenodm/spectrwm session kept as the fallback.
5. **Effort:** ~6 working sessions to a themed, daily-drivable desktop, plus
   one evening of on-metal spikes that cannot be done anywhere else.

## What ML4W actually is

From the ML4W OS docs and repo (`mylinuxforwork/dotfiles`, GPLv3):

| Layer | ML4W choice |
|---|---|
| Compositor | Hyprland 0.55.x, Lua config |
| Widgets / apps | quickshell (status bar, sidebar, settings, welcome) |
| Optional bar | waybar (themes, `themeswitcher.sh`) |
| Terminal | kitty |
| Launcher | Rofi (Wayland), optional walker/elephant |
| Wallpaper | `awww` |
| Notifications | swaync (dunst in older versions) |
| Idle / lock | hypridle / hyprlock |
| Screenshots | grim + slurp + grimblast |
| Clipboard | cliphist |
| Colour | pywal / matugen templates |
| Theming | nwg-look (GTK), qt6ct (Qt), Bibata cursor, Kora icons, Font Awesome |
| Session | SDDM |
| Shell/editor | fish/zsh/bash, nvim, oh-my-posh |

Its identity is not any single program. It is: one palette applied to every
surface, a dense single top bar with workspace pills and clickable
quicklinks, a fast keyboard launcher, a settings GUI, and consistent gaps,
borders and typography. Most of that is reproducible here.

## Why we do not fork the dotfiles

- **Licence.** `dotfiles/LICENSE` is GPLv3. Copying their configs into this
  repo would relicense the repo's desktop content as GPLv3, which defeats the
  stated goal. Their wallpapers, palettes and icons are their assets too.
- **They cannot run.** Hyprland is not packaged for OpenBSD and cannot be:
  no `hyprland`, `hyprlock`, `hypridle`, `hyprpaper`, `hyprctl`,
  `hyprland/workspaces` waybar module. Their config is Hyprland's Lua dialect.
- **The apps are Linux-shaped.** Quickshell + the ML4W settings/sidebar apps
  assume Qt6 layer-shell, `xdg-desktop-portal-hyprland`, PipeWire and
  logind/UPower semantics we do not have.
- **Upstream churn.** Their config layout changes between releases
  (`custom.conf` → `custom.lua`); a fork would be a permanent rebase.

**What we do instead:** a read-only reference checkout, outside the repo (or
under a gitignored `vendor/ml4w/`), used for the feature inventory, bar
layout, keybinding conventions and settings-menu shape. Nothing is copied
verbatim. If a snippet is ever lifted, the plan is to write it from scratch
against the documented behaviour instead.

```sh
# reference only, never imported into this repo
git clone --depth 1 https://github.com/mylinuxforwork/dotfiles /tmp/ml4w-ref
```

## What OpenBSD 8.0 actually gives us

Verified against the 8.0 `packages/amd64` index and a `pkg_add -n` dry run in
the rehearsal VM. Versions are the shipped ones.

| Need | Package | Licence | Note |
|---|---|---|---|
| Compositor | `sway-1.12` | MIT | i3-compatible; waybar has a native `sway/*` backend |
| Bar | `waybar-0.15.0p2` | MIT | pulls `upower` (GPLv2), `polkit` (LGPL), `gtk-layer-shell` |
| Bar (GPL-free alt) | `swaybar` (in sway) | MIT | text protocol, no CSS |
| Terminal | `foot-1.28.0` | MIT | native Wayland, server mode, fontconfig |
| Launcher | `fuzzel-1.15.0` | MIT | native Wayland dmenu/drun |
| Notifications | `fnott-1.8.0p0` | MIT | `mako`/`swaync` are not packaged |
| Wallpaper | `swaybg-1.2.2`, `awww-0.12.1` | MIT | awww adds transitions |
| Lock / idle | `swaylock-1.8.5`, `swayidle-1.9.0` | MIT | |
| Screenshots | `grim-1.5.0`, `slurp-1.5.0` | MIT | |
| Recording | `wf-recorder-0.6.0p2` | MIT* | optional |
| Clipboard | `wl-clipboard-2.3.0`, `cliphist-0.7.0` | **GPLv3** | unavoidable for CLI clipboard |
| Outputs | `wlr-randr-0.5.0`, `kanshi-1.9.0p0` | MIT | |
| Night light | `gammastep-2.0.11` | **GPLv3** | no `wlsunset` on 8.0 |
| X11 bridge | `xwayland-24.1.13`, `xwayland-satellite-0.8.1` | MIT | Firefox needs it (see below) |
| Images / PDF | `imv`, `swayimg`, `zathura` | MIT/ISC | zathura runs under XWayland |
| Audio | sndio (base), `sndioctl` | ISC | no PipeWire needed |
| Power | `obsdfreqd-1.2.2` | ISC | already in `packages.txt` |

\* confirm at install time; `wf-recorder` is the only uncertain licence here.

Already in this repo and reusable: BlexMono Nerd Font, the amber palette,
`bar.sh`'s data-gathering logic (`apm`, `ifconfig iwm0`, `sndioctl`,
`hw.sensors`), `bin/screenshot`, `bin/volume`, `bin/brightness`, `bin/lock`
(X11 variants to be forked, not replaced), and the staged installer.

## The gaps, stated plainly

| ML4W feature | On OpenBSD 8.0 | Consequence |
|---|---|---|
| Hyprland | absent | sway; no blur, no rounded window corners, no per-window opacity |
| Quickshell sidebar/settings | absent | fuzzel menus + a ksh `settings` script; a GTK4 app is a later project |
| `hyprlock` animation | absent | `swaylock` (solid, palette-themed) |
| `swaync` | absent | `fnott` (simpler, no control centre) |
| `nwg-look`, `nwg-dock` | absent | `gtk-3.0/settings.ini` + `gsettings`, no dock in v1 |
| pywal / wallust / matugen | absent | our own palette renderer (`theme-apply` extended) |
| Bibata cursor, Kora/Papirus icons | not packaged | Adwaita icons + Adwaita/`obsidian` cursors, or vendor an OFL/CC icon theme |
| SDDM | absent for Wayland | console login, see below |
| grimblast | absent | own `bin/shot` wrapper |
| wob / swayosd OSD | absent | `notify-send` through fnott |
| PipeWire | packaged, not needed | stay on sndio |

**Sway is not Hyprland.** If blur and rounded corners are the actual
requirement, the only packaged compositor that offers them is
`wayfire-0.11.0` (MIT) — heavier on a UHD 620, less exercised on OpenBSD,
weaker bar integration. Recommendation: build the sway desktop first; treat
"wayfire eye-candy" as an optional documented flavour, not the base.

### Compositor decision

| Candidate | Licence | Verdict |
|---|---|---|
| **sway 1.12** | MIT | **Choose.** Matches ML4W's i3-derived keybindings, best waybar integration, most documented on OpenBSD, tiling + gaps + per-output config |
| niri 26.04 | GPLv3 | Best "modern feel" (scrollable columns, animations) and waybar-supported, but GPLv3 and a different interaction model |
| labwc 0.20 | GPLv2 | Openbox-like; no tiling intended; wrong fit |
| wayfire 0.11 | MIT | Only blur/animation option; heavier, less tested here |
| cage / cow / river / mango | mixed | Kiosk / niche / dwl-fork; not a desktop base |

## The session model — the one real design change

`/usr/local/share/doc/pkg-readmes/sway` is explicit: launch from a text VT
with **xenodm stopped**. `startsway.sh` (shipped by the package) already sets
what we need:

```sh
: ${WLR_DRM_DEVICES:=/dev/dri/card0}
: ${LIBSEAT_BACKEND:=noop}          # no seatd daemon required
: ${XDG_RUNTIME_DIR:=${HOME}/.local/run}
: ${QT_QPA_PLATFORM:=wayland}
#: MOZ_ENABLE_WAYLAND:=1            # "doesn't work yet" — Firefox stays on XWayland
```

So:

- **Default boot:** console login on `ttyC1`; `~/.profile` execs
  `startsway.sh` when `tty` is `/dev/ttyC1` and no `DISPLAY`/`WAYLAND_DISPLAY`
  is set. No display manager.
- **Escape hatch, mandatory from day one:** `~/.no-wayland` (or a failed
  `sway` start) skips the autostart, so a broken compositor cannot lock us out
  of the machine. Recovery is `Ctrl+Alt+F2`, log in, `rm ~/.no-wayland`.
- **Fallback session preserved:** `rcctl enable xenodm` + the existing
  spectrwm session stays in the repo and documented. Running both at once is
  not supported by the package readme; switching is `rcctl start/stop xenodm`.
- **Log out** = `swaymsg exit` back to the console; **lock** = `swaylock`.
- `seatd` is packaged and pulled by `niri`, but is **not** needed here
  (`LIBSEAT_BACKEND=noop`); do not enable it.
- XWayland: `xwayland enable` in the sway config, because **Firefox 157 must
  run under XWayland** (the port's own launcher says Wayland "doesn't work
  yet"). Chromium's Wayland support in the 154 port is unverified — treat
  native-Wayland Chromium as an experiment, XWayland as the default.

## ML4W → OpenBSD mapping

| ML4W behaviour | Our implementation | Status |
|---|---|---|
| One palette everywhere | `~/.config/theme/<name>/palette` → generated sway/waybar/foot/fuzzel/fnott/gtk | reimplement |
| Top bar: workspaces, window, tray, clock | waybar, `sway/workspaces` + `sway/window` + `tray` | direct |
| Bar modules: CPU/mem/temp/battery/network/audio | waybar `custom/*` scripts over `sysctl`, `apm`, `ifconfig`, `sndioctl` | reimplement (no UPower/NetworkManager semantics for the bar) |
| Quicklinks (browser, settings, AI) | waybar `custom/quicklinks` with `on-click` | direct |
| Bar theme switcher | `fuzzel -d` list of theme names → `theme-apply` | reimplement |
| Rofi drun | `fuzzel` (native Wayland); rofi stays for the X11 session | substitute |
| Workspace pills 1–10, `SUPER+1..0` | sway `workspaces 1..10` + identical bindings | direct |
| Screenshots: full / region / window, to clipboard | `bin/shot` over `grim`/`slurp`/`swaymsg -t get_tree \| jq` | reimplement |
| Clipboard history picker | `cliphist` + `fuzzel -d` | direct |
| Idle → lock, before suspend | `swayidle` + `swaylock`; `/etc/apm/suspend` locks first | reimplement (Wayland variant of `bin/lock`) |
| Power menu / wlogout grid | `bin/power` in fuzzel | reimplement |
| Night light | `gammastep` (GPLv3) — **or** X11-only `sct` | accept or drop |
| Notifications | `fnott` + `notify-send` | substitute |
| Wallpaper + transitions | `swaybg` (static) or `awww` (fades) | direct |
| Media keys, volume OSD | sway `bindsym XF86Audio*` → `sndioctl`; OSD via `notify-send -t 800` | reimplement |
| Settings / sidebar app | `bin/settings` fuzzel menus writing small config files | phased, E |
| GTK/Qt dark, cursor | `gtk-3.0`/`gtk-4.0` `settings.ini` (already shipped), `qt6ct` | direct |
| SDDM login | console login + autostart | drop |

## Design language

The reason ML4W reads as "finished" is discipline, not effects:

- **One palette, one accent.** Keep amber: `#0f0e0c` base, `#ffb000` focus,
  `#d90d10` urgent, `#e6ded0` text, `#8a8175` dim. It is already applied to 8
  surfaces in the X11 session; extend, do not invent a second theme.
- **Generous, even spacing.** sway `gaps inner 8 / outer 8`, 2px borders,
  bar height 34, `border_radius` in waybar CSS only (windows cannot round).
- **One typeface.** BlexMono Nerd Font everywhere (already vendored, OFL).
- **Quiet bar.** Left: workspaces. Centre: focused window. Right: a small set
  of quicklinks, then status modules, then clock. Icons only where a Nerd
  Font glyph is guaranteed.
- **Motion where it is free.** `awww` fades for wallpaper changes; everything
  else static. No animation framework exists for sway — do not fake it.
- **Alpha, not blur.** `rgba(15,14,12,0.92)` bar and fuzzel background read as
  modern without a compositor effect stack.

## Repo shape (proposed)

Extend this repo; do not create a fourth OpenBSD repo. `openbsd-desktop` and
`openbsd-t480s` are earlier, unversioned drafts of the same idea and should be
absorbed or archived.

```
home/.config/sway/config              bindings, gaps, outputs, autostart
home/.config/waybar/config.jsonc      modules
home/.config/waybar/style.css         rendered from palette
home/.config/foot/foot.ini            rendered from palette
home/.config/fuzzel/fuzzel.ini        rendered from palette
home/.config/fnott/fnott.ini          rendered from palette
home/.config/theme/amber/palette      single source of truth (key=hex)
home/.config/theme/amber/waybar.css.in, foot.ini.in, ...
home/bin/start-session                tty guard + startsway.sh + escape hatch
home/bin/shot                         grim/slurp/swaymsg wrapper
home/bin/power                        lock/suspend/reboot/off/logout
home/bin/keybinds-wayland             sway config → fuzzel list
lib/stages/wayland.sh                 stage_wayland: packages + configs + ttys note
```

`install.sh` gains a `wayland` stage between `desktop` and `browser`;
`packages.txt` gains the Wayland set (and `packages-vm.txt` must **not**,
since the VM cannot run it). `vm apply`/`vm capture` already cover `home/` and
`etc/`, so the daily loop is unchanged — only visual testing moves to metal.

## Roadmap

| Phase | Deliverable | Done when |
|---|---|---|
| **A. Spike (metal, 1 evening)** | Answer the 6 questions below; no repo changes | `sway` + `waybar` + `foot` start on the T480s from a VT, `theme-apply` untouched |
| **B. Session + bar (2–3 sessions)** | `start-session`, sway config, waybar config + CSS, palette renderer v1 | Boots to a themed bar with working workspaces, clock, battery, net, volume, temp; `~/.no-wayland` escape verified |
| **C. Daily drivers (2 sessions)** | fuzzel drun + `keybinds`, `bin/shot`, cliphist, swayidle/swaylock, fnott, media keys | A full day's work without touching a terminal for window management |
| **D. Theme system (2 sessions)** | One palette → 7 surfaces, `theme-apply` for both sessions, 3 palettes | Switching theme repaints bar/terminal/launcher/notifications/lock in one command |
| **E. Polish (2 sessions)** | `bin/power`, volume OSD, `bin/settings`, quicklinks, awww wallpaper | Matches the ML4W feature checklist minus compositor effects |
| **F. Docs + rollout** | README, keybinding reference, troubleshooting, X11 fallback docs, `make check` | Fresh install → `doas ./install.sh --metal` → Wayland desktop, documented |

### Phase A: the questions only the T480s can answer

1. Does `sway` acquire DRM master and scan out on `inteldrm` (UHD 620) in 8.0?
2. Do `input` settings work through `libinput-openbsd`, or must tap-to-click /
   natural scrolling stay in `/etc/wsconsctl.conf`?
3. Does `waybar`'s `sway/workspaces` IPC work (it should; confirm pill states)?
4. Does Chromium 154 run native Wayland (`--ozone-platform=wayland`), or must
   it stay on XWayland with Firefox?
5. Which `UPower`/`polkit` behaviour shows up in waybar's battery module —
   and does `custom/battery` over `apm` look better?
6. Does `xenodm` stopped + `ttyC1` autostart behave after suspend/resume
   (`zzz`), and does `swaylock` survive resume?

Nothing in Phase B onward should be written before A answers 1, 4 and 6.

### Why the VM cannot rehearse this

Verified in the rehearsal VM: `wsdisplay0 at efifb0`, `wsfb`, **no DRM driver
attached**. `/dev/dri/card*` exist as nodes but there is no KMS device, and
`sway` needs one. So:

- VM: package resolution, config syntax (`sway -C`), palette rendering, unit
  checks. That is genuinely useful and is where Phases B–E get their linting.
- Metal: everything visual. Budget a real evening, keep `~/.no-wayland` and a
  xenodm/spectrwm fallback ready, and snapshot first.

## Licences: what "avoid GPL" costs here

Base OpenBSD is BSD/ISC, the compositor/bar/terminal/launcher/notification
stack is MIT, fonts are OFL, GTK/Qt are LGPL. The unavoidable GPL in the
*desktop stack* is small but real:

- `wl-clipboard` and `cliphist` — **GPLv3**. There is no non-GPL Wayland
  clipboard CLI. They are standalone utilities nothing links against; accept
  them or lose clipboard history.
- `waybar` hard-depends on `upower` (**GPLv2**) and `polkit` (LGPL). If that
  is unacceptable, the GPL-free bar is `swaybar` (MIT) fed by a `bar.sh` — the
  pattern this repo already uses — at the cost of waybar's CSS and modules.
- `gammastep` (night light) is **GPLv3**; drop it in the Wayland session
  rather than accept it, since `sct` does not work under Wayland.
- The ML4W dotfiles are **GPLv3** — this is the reason not to import them.
- Do not add `pipewire`/`wireplumber` (MIT, but pointless here): sndio is
  native, works with `sndioctl`, and keeps the dependency graph small.

Decision to make explicitly at Phase B: **waybar (ML4W look, one GPLv2 dep)**
versus **swaybar (strict licence hygiene, plainer bar)**. Recommendation:
waybar, documented, with the `swaybar` variant left as a supported option.

## Risks

| Risk | Mitigation |
|---|---|
| sway unusable on this GPU/driver | Phase A before any work; X11 session stays default until proven |
| Wayland session locks the machine out | `~/.no-wayland` guard from commit one; console getty untouched; xenodm fallback |
| Firefox/Chromium stuck on XWayland | Accept; document; `xwayland enable` in config |
| waybar modules need Linux semantics | Write `custom/*` scripts over base tools (`apm`, `ifconfig`, `sndioctl`, `sysctl`) |
| No visual rehearsal environment | Metal-only visual testing, snapshot before each attempt; VM lints configs |
| Scope creep into a settings GUI | Phase E at the earliest, and only as fuzzel menus |
| GPL creep | Licence column in every phase's PR list; no ML4W files, ever |

## Deliberately out of scope

- A Quickshell/GTK4 replacement for the ML4W sidebar and settings app.
- Hyprland feature parity (blur, rounded windows, per-window opacity).
- `wayback` (rootful Xwayland X11 compatibility layer) — interesting path to
  retiring xenodm/X entirely, but experimental in 8.0.
- PipeWire, portals beyond `xdg-desktop-portal-gtk` (no `-wlr` backend is
  packaged, so screenshot/file portals are partial).
- Niri as a default; it stays a documented alternative for people who want
  animations and accept GPLv3.
- Hardware video decode (does not exist in the OpenBSD Chromium port).

## Definition of done

A fresh 8.0 install, `doas ./install.sh --metal`, reboot, log in on ttyC1, and
within ten seconds: amber-themed sway desktop, bar with workspaces/window/
quicklinks/status/clock, `SUPER+Return` foot, `SUPER+D` fuzzel, screenshots to
clipboard, clipboard history, idle lock, media keys through sndio, power menu,
`theme-apply` repainting every surface, `SUPER+Shift+/` listing bindings, and
a documented one-command return to the X11 session.
