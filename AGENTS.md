# AGENTS.md

Instructions for AI coding agents working in this repo. See also
[README.md](README.md), [INSTALL.md](INSTALL.md) for user-facing docs,
and [CHANGELOG.md](CHANGELOG.md) for release history.

## What this is

An [Omarchy](https://omarchy.org) [Quickshell](https://quickshell.org)
bar-widget plugin — plain QML, no build step. `manifest.json` declares it;
`BarWidget.qml` is the bar entry point; `Panel.qml` is the docked popup it
opens; `Model.js` parses adsb.lol responses.

## Verifying a change

There's no test suite beyond CI's manifest-schema check — verify live:

- **Deploy**: this repo is usually developed at `/tmp/flyover-pill` with a
  runtime mirror at `~/.config/omarchy/plugins/bren.flyover/`; changes
  need to land in the mirror to take effect (copy, or work directly in
  the mirror and back-port to the repo — check which convention the
  current checkout uses before assuming).
- **Hot-reload gotcha**: Quickshell's file-watcher reliably picks up
  *property-value* changes on already-instantiated objects, but does
  **not** pick up new items/components added to the QML tree. A change
  that adds a new element needs a full `omarchy-restart-shell`, not just
  a save — don't spend time debugging "my new element doesn't render"
  before trying that first.
- **Screenshotting**: this is a Wayland/Hyprland bar widget with no
  headless test mode. To see it live: launch/trigger it, then `grim` a
  screenshot. `quickshell -p /usr/share/omarchy/shell ipc call
  bren.flyover toggle` opens the popup without needing a real click.
- Trust a visual check over reading the QML, especially for anything
  involving rotation or coordinate math — this repo has a documented
  history of a heading-rotation bug (`rotation: track` vs `rotation:
  track - 45`) that looked plausible in code and was only caught by
  actually rendering a known glyph and measuring its rest pose.

## Conventions

- **Quickshell's `PATH` excludes `~/.cargo/bin`.** Any logic that shells
  out to the `flyover` binary must resolve it the way `BarWidget.qml`
  already does — `command -v` first, then an explicit fallback list
  (`~/.cargo/bin/flyover`, `/usr/bin/flyover`, `/usr/local/bin/flyover`)
  — not a bare command name or a single hardcoded path. If you add
  another fallback location, update it in exactly one place and update
  [INSTALL.md](INSTALL.md) to match — that doc has gone stale against
  the actual fallback list before.
- This widget stays thin by design: it owns polling and binary
  resolution, not scope-rendering logic. The popup's mini radar
  (`Panel.qml`) is a deliberately separate, simpler QML reimplementation
  of a radar display, not a mirror of flyover's own terminal renderer —
  don't try to unify them.
- Sweep timing constants in `Panel.qml` (period, trail span) are
  hand-kept in sync with flyover's own `geometry.rs` constants, not
  shared code (different languages/runtimes). If you change one, check
  whether the other should change too, and say so in the commit.

## Version

`manifest.json`'s `version` field isn't SemVer-enforced by anything, but
bump it and add a [CHANGELOG.md](CHANGELOG.md) entry for any user-visible
change — it was left stale at `1.0.0` through several real feature
releases before this convention was introduced, which made it useless as
a "what changed" signal.
