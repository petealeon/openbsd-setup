# ML4W-class on X11 — how far it goes without Wayland

Status: **plan only, nothing implemented.** Companion to
[`wayland-ml4w-plan.md`](wayland-ml4w-plan.md). Target: the T480s on OpenBSD 8.0.

## The short answer

**Further than on Wayland, visually.** My estimate, not a measurement:

| Dimension | Ceiling on X11 | Why |
|---|---|---|
| Looks | ~90% of ML4W | `picom 13` gives blur, rounded corners, shadows, fades and window animations — none of which sway can do. `polybar` gives a real ML4W-style bar. |
| Function | ~95% | Every daily action maps to a packaged tool. Nothing in the stack needs Wayland. |
| Architecture | ~40% | No fractional scaling, no per-monitor DPI, no touchpad gestures, no client isolation. |

The catch, and it is the whole reason this document exists: **these gaps mostly
do not apply to this hardware.** The T480s has one 1080p panel. Per-monitor DPI,
mixed scaling and touchpad gestures are laptop-class Wayland advantages that
never trigger here. What *does* show on screen every day is chrome — and X11
wins that comparison outright.

If the goal is "a beautiful, modern, functional OpenBSD desktop that rivals
ML4W", X11 is not the compromise. It is the shorter path to the same picture.

## Verified inventory (8.0 packages)

| Role | Package | Licence | Note |
|---|---|---|---|
| Compositor | `picom-13` | MPL-2.0/MIT | `corner-radius`, `blur-*`, `animations`, opacity rules, vsync; links `libepoxy` + `pixman`, so the GLX backend exists |
| Tiling WM | `i3-4.25.1` | BSD | gaps, tabbed/stacked, scratchpad, IPC for the bar |
| Alternatives | `bspwm-0.9.11`, `herbstluftwm-0.9.6`, `xmonad-0.18.1`, `dwm-6.8`, `spectrwm-3.7.0p0`, `notion-4.0.5` | BSD/MIT/ISC | all packaged; `awesome-4.3p3` is GPLv2 |
| Bar | `polybar-3.7.2` | MIT | i3/bspwm modules, tray, `custom/script`, per-monitor bars |
| Alternatives | `tint2-17.0.2p2`, `lemonbar-1.5`, `i3status-2.15p0`, `xmobar-0.51.1`, `stalonetray-0.8.3p1` | GPL2/MIT | `tint2` is GPLv2 |
| Launcher | `rofi-1.7.9.1` | MIT | drun, window, `-modi` script modes (the control centre) |
| Notifications | `dunst-1.13.2` | BSD-3 | history via `dunstctl`, rounded corners, per-urgency colours |
| Lock | `i3lock-2.15` + `xss-lock-0.3.0` | BSD/MIT | pre-blurred wallpaper via ImageMagick; `slock-1.5` (MIT) is the plain fallback |
| Idle | `xidle` (base X) or `xautolock-2.2` | ISC/GPL2 | `xss-lock` is the modern pairing |
| Screenshots | `maim-5.8.2`, `slop-7.7p0`, `scrot-2.0.0` | GPL3/GPL3/(?) | GPL-free alternative: `scrot` + `ImageMagick-6.9` |
| Clipboard | `clipmenu-6.2.0`, `clipnotify-1.0.2`, `xsel-1.2.1` | (?) / MIT | **no GPLv3 needed** — unlike Wayland's `wl-clipboard`/`cliphist` |
| Wallpaper | `feh-3.13`, `xwallpaper-0.7.6`, `hsetroot-1.0.5` | MIT/ISC | `nitrogen` is GPL2; unnecessary |
| Display | `xrandr`, `arandr-0.1.11p4`, `autorandr-1.15p3` | MIT/GPL3 | `autorandr` optional |
| GTK/Qt theme | `xsettingsd-1.0.4`, `qt5ct-1.9`, `qt6ct-0.10p3`, `lxappearance-0.6.3p2` | BSD/MIT/GPL3 | `lxappearance` only if a GUI is wanted |
| Login | `xenodm` (base) | X11/MIT-style | themable via `xlogin*` X resources — a real ML4W/SDDM-like login |
| Login alt | `greetd-0.10.3p6` + `gtkgreet-0.8`/`regreet-0.2.0` | GPL3 | exists, but xenodm is enough and lighter |

Also packaged and relevant: `sxhkd-0.6.2p0` (bspwm-style bindings), `xcape`,
`xdotool`, `wmctrl`, `xbanish`, `numlockx`, `playerctl`, `zenity-4.2.2`,
`yad-0.40.0p5`, `xscreensaver-6.15p1`, `stalonetray`, `rxvt-unicode`.

## Three tiers, not one

### Tier 0 — what exists today

spectrwm + st + rofi + dunst + picom + feh + clipmenu + maim/slop, amber
palette, custom `bar.sh`. Genuinely usable, ~60% of ML4W's function, ~40% of
its look. Its weakness is structural: one text line for a bar, and no themed
login.

### Tier 1 — one evening, keep spectrwm

The cheapest visible wins, in order of impact:

1. **Picom 13.** `corner-radius = 10`, `blur` with `dual_kawase` on
   st/rofi/dunst only, shadows, `fade`, `use-damage`, `vsync`. Rounded, blurred,
   translucent surfaces are the single most "ML4W" thing on screen.
2. **Themed xenodm.** `xlogin*` resources set the base colour, amber prompt and
   BlexMono faces, and `Xsetup_0` paints the same wallpaper the session uses.
   The login screen stops being a grey rectangle. Wayland cannot do this at all.
3. **Real lock screen.** Pre-render a blurred wallpaper in `theme-apply` and use
   `i3lock -i amber-blur.png` under `xss-lock`, replacing `slock`.
4. **Rofi script modes.** One `rofi -modi` file tree becomes the ML4W "sidebar":
   apps, windows, theme, display, audio output, wifi, power, keybindings.
5. **`Option "TearFree" "true"`** in an `xorg.conf.d` snippet, plus picom
   `vsync = true`, removes the last "this is old X" tell.

Ceiling after Tier 1: everything except the bar. spectrwm's bar is text-only
and has no IPC, so no workspace pills, no tray, no clickable modules.

### Tier 2 — the ML4W-max build (the real target)

Swap spectrwm for **i3 4.25.1** and the text bar for **polybar 3.7.2**:

```
i3        gaps inner/outer, tabbed + stacked, scratchpad, IPC
polybar   left: workspace pills (internal/i3)  centre: xwindow
          right: quicklinks, cpu, memory, temp, battery, net, volume, tray, clock
picom     blur + rounded + shadows + fades + simple open/close animations
rofi      drun, run, window, script modes
dunst     notifications + history
```

This is the configuration that actually resembles ML4W: pills, tray,
clickable modules, rounded translucent surfaces, gapped tiles, a launcher with
an icon grid, and a themed login in front of it.

**Why i3 over the alternatives:** its model is the same one ML4W inherits
(i3 → sway → Hyprland), so the keybinding table, workspace semantics and
scratchpad habits transfer directly; it is BSD-licensed; it has IPC that
polybar speaks natively; and `i3 -C` gives a real config validator for CI.
`bspwm` is more scriptable but needs `sxhkd` and a second config language;
`herbstluftwm` and `awesome` are further from the ML4W mental model; `xmonad`
and `dwm` mean rebuilding the WM to change a colour.

Keep `.spectrwm.conf` and `bar.sh` in the repo as the fallback session — it
costs nothing and it is already rehearsed.

## The bar is the one place polybar needs real work

`strings bin/polybar` confirms `internal/i3`, `internal/xwindow`,
`internal/tray`, `internal/mpd`, `internal/cpu`, `internal/memory` and
`internal/date` are compiled in — those work. These do **not** on OpenBSD,
because they read Linux interfaces:

| Module | Why it fails here | Replacement |
|---|---|---|
| `internal/battery` | `/sys/class/power_supply` | `custom/script` over `apm -l` / `apm -a` |
| `internal/network` | netlink | `custom/script` over `ifconfig iwm0` / `ifconfig em0` |
| `internal/temperature` | `/sys/class/hwmon` | `custom/script` over `sysctl hw.sensors` |
| `internal/pulseaudio`, `internal/alsa` | no PulseAudio/ALSA | `custom/script` over `sndioctl` |
| `internal/backlight`, `internal/xbacklight` | `/sys` / X backlight | `custom/script` over `wsconsctl display.brightness` (already in `bin/brightness`) |

That is not a blocker; it is `bar.sh` with a different output format. The
existing helpers (`battery_seg`, `net_seg`, `temp_seg`, `volume_seg`) become
five tiny scripts with `%{F#ffb000}` markup instead of `+@fg=0;`.

## Feature ceiling, element by element

| ML4W element | Best on X11 | Verdict |
|---|---|---|
| Tiling, gaps, layouts | i3 gaps + tabbed/stacked | parity |
| Workspace pills, click to switch | polybar `internal/i3` | parity |
| Bar modules, tray, quicklinks | polybar | parity (custom scripts) |
| Rounded, translucent windows | picom `corner-radius` | close (occasional artifacts) |
| Blur behind terminals/menus | picom `blur` (GLX) | close (costs GPU) |
| Open/close animations | picom `animations` (12+) | close-ish, much simpler than Hyprland |
| Launcher + icon grid | rofi drun | parity |
| Notification centre | dunst + `dunstctl` history | parity |
| Lock screen | i3lock + pre-blurred wallpaper | close (no live blur) |
| Idle → lock → suspend | xss-lock + `/etc/apm/suspend` | parity |
| Screenshots (full/region/window) | maim/slop/scrot | parity |
| Clipboard history | clipmenu/clipnotify | parity, and **MIT-ish, not GPLv3** |
| Theming across apps | own palette renderer | parity |
| Settings GUI / sidebar | rofi script modes (or `yad`) | substitute |
| Graphical login with wallpaper | **xenodm `xlogin*`** | close — **Wayland cannot** |
| Per-monitor fractional scaling | — | no |
| Touchpad gestures | — | no |
| Client isolation / security model | — | no |
| Tear-free presentation | `TearFree` + picom vsync | close |
| Mixed-DPI multi-monitor | — | no |

## Where X11 beats the sway plan

1. **Blur and rounded corners.** sway has neither; picom has both.
2. **A themed graphical login.** xenodm + `Xsetup_0` + `xlogin*` resources;
   the Wayland plan has to drop to a text console.
3. **No GPLv3 in the core stack.** X11 clipboard is `clipmenu`/`xsel`;
   Wayland needs `wl-clipboard` + `cliphist`.
4. **Fully rehearsable.** The VM has no DRM, so it cannot run sway — but it can
   run `Xephyr :1` (a real nested X server with composite/damage/randr) and
   host i3 + polybar + rofi + dunst inside it. Every phase below can be checked
   before it touches the T480s.
5. **Zero migration risk for the parts that already work.** Palette, fonts,
   keybinding intent, wallpapers, `bin/*` helpers and the staged installer all
   carry over.

## What is genuinely lost

- **Fractional scaling and per-monitor DPI.** Irrelevant on one 1080p panel;
  painful if this ever becomes a 4K or dual-monitor desk.
- **Touchpad gestures.** No three-finger workspace swipe; keyboard only.
- **Per-window animations with Hyprland's physics.** picom animates, but
  linearly and only open/close/move.
- **Client isolation.** Any X client can read any other's keystrokes. On a
  single-user laptop this changes nothing in practice.
- **Long-term drift.** X11 is in maintenance; OpenBSD still ships xenocara, and
  everything here is packaged today, so this is a five-year concern, not a
  one-year one. The Wayland plan remains the exit route.

## Stack contract (shared with the Wayland plan)

Both plans consume the same three abstractions, which is why doing X11 first
does not waste work:

1. **One palette file** → `~/.config/theme/amber/palette`, rendered into
   `picom.conf`, `polybar.ini`, `i3` colours, `rofi.rasi`, `dunstrc`,
   `Xresources`, `gtk-3.0/settings.ini` and the xenodm resources.
2. **One bar-data layer** → five scripts (`battery`, `net`, `temp`, `volume`,
   `music`) emitting plain text; `bar.sh` and polybar both consume them.
3. **One keybinding table** → `SUPER+Return` terminal, `SUPER+D` launcher,
   `SUPER+Q` close, `SUPER+1..0` workspaces, `SUPER+Shift+1..0` move window,
   `SUPER+F` fullscreen, `SUPER+Shift+Space` layout, `SUPER+Shift+/` cheat
   sheet. Identical names in spectrwm, i3 and (later) sway.

## Phases

| Phase | Work | Done when |
|---|---|---|
| **X1** (1 evening) | Picom 13 config + `TearFree`; `theme-apply` renders it | st, rofi and dunst are rounded and blurred; idle CPU < 5%; no tearing scrolling in Chromium |
| **X2** (1 evening) | Themed xenodm + pre-blurred `i3lock` + `xss-lock` | Login screen and lock screen match the desktop palette |
| **X3** (2 sessions) | i3 config: gaps, binds, scratchpad, float rules, bar-less first | A full working day on i3 with no terminal needed for window management |
| **X4** (2 sessions) | polybar: five custom modules, i3 pills, tray, quicklinks; rofi script modes | Bar reaches the ML4W module set; `theme-apply` repaints bar and launcher |
| **X5** (1 session) | Docs, `validate.sh`, `make check` (`i3 -C`, shell syntax), capture/apply | Fresh install → `doas ./install.sh --metal` → themed i3 desktop |

### Rehearsal harness (works in the existing VM)

```sh
Xephyr :1 -screen 1280x800 &
DISPLAY=:1 i3 -c ~/openbsd-setup/home/.config/i3/config &
DISPLAY=:1 polybar -c ~/.config/polybar/config.ini main &
DISPLAY=:1 rofi -show drun &
DISPLAY=:1 xwd -root | convert xwd:- /tmp/shot.png
```

Blur needs GLX; Xephyr may fall back to software rendering, so treat colour,
layout and spacing as rehearsable and treat *performance* as metal-only.

## Licensing note

The core X11 path is BSD/MIT: i3 (BSD), polybar (MIT), picom (MPL-2.0/MIT),
rofi (MIT), dunst (BSD-3), i3lock (BSD), xss-lock (MIT), xsel (MIT), xcape
(MIT), xsettingsd (BSD), feh (MIT), `xwallpaper` (ISC). Only the screenshot
tools already in the repo are GPLv3 (`maim`, `slop`); `scrot` +
`ImageMagick` can replace them if strict hygiene matters, and `xclip` (GPLv2)
becomes `xsel` (MIT). Optional GUI tools (`lxappearance`, `yad`, `autorandr`,
`zenity`) are GPL/LGPL and are not on the core path.

## Risks

| Risk | Mitigation |
|---|---|
| picom blur too expensive on UHD 620 | blur only on st/rofi/dunst via `blur-background-exclude`; drop to `corner-radius` + shadows if the fan spins |
| Rounded corners artifacts / black corners | keep the GLX backend; `rounded-corners-exclude` for fullscreen and the bar |
| polybar's Linux modules mislead | they are listed above; only `custom/script` versions ship |
| i3 migration loses the working spectrwm setup | both configs live in the repo; xenodm starts whichever `~/.xsession` selects |
| X11 drift over years | Wayland plan retained as the exit route; the shared palette/bar/binding contract makes the swap incremental |
| The "modern" claim weakens | it is a 2012-era X server with 2026 chrome; the user-visible difference on this hardware is nil |

## Recommendation — this changes the sequencing

Previous plan said "sway first, X11 as fallback". Invert it:

1. **Do Tier 1 now** (one evening): picom 13 + themed xenodm + i3lock +
   rofi modes. Largest visual gain per hour of any work in either plan.
2. **Do Tier 2 next** (about four sessions): i3 + polybar. This is the ML4W
   desktop, on a stack that is already rehearsed and fully testable in the VM.
3. **Then decide about Wayland** with a working, beautiful desktop already in
   hand — and only if the metal spike justifies it. Nothing in Tier 1/2 is
   wasted if we do switch: palette, bar data and bindings all port.

If we never use Wayland, the honest statement is: we lose fractional scaling,
gestures and client isolation, none of which this laptop can show, and we keep
blur, rounding, animations and a graphical login, which it shows every day.

## Definition of done

Boot → themed xenodm with wallpaper → log in → i3 with gapped tiles, polybar
carrying workspace pills, focused window, quicklinks, five live status modules,
tray and clock → `SUPER+D` rofi drun → `SUPER+Shift+/` cheat sheet → screenshots
to clipboard → clipboard history → idle lock with blurred wallpaper → power
menu → `theme-apply` repaints bar, terminal, launcher, notifications, lock and
login → `SUPER+Shift+E` returns to xenodm.
