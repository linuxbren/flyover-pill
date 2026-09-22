# Installing flyover-pill

This widget is a thin shell on top of [flyover](https://github.com/linuxbren/flyover) itself — it polls for a nearby-aircraft count and launches the scope binary in a terminal. Everything below assumes you want the pill to work after `omarchy plugin add`. If something goes wrong, the order matters: **the why before the what, because the symptom is misleading.**

## If clicking the pill does nothing

You installed flyover, the binary is on your `PATH`, you click the `✈` pill, and… nothing happens. No error, no terminal, just silence. This is the single most common issue, and it's not a bug in your install — it's a difference in how the widget sees your system versus how you see it.

### Why

flyover-pill runs inside [Quickshell](https://quickshell.org), the Omarchy bar's render process. Quickshell is its own process with its own environment, including its own `PATH`. **Quickshell's `PATH` does not include `~/.cargo/bin`** — the directory `cargo install` writes to by default. So when you run `cargo install flyover` in your terminal, the binary lands somewhere your interactive shell can find it (because `rustup` added `~/.cargo/bin` to your `PATH`), but somewhere Quickshell can't see.

The widget resolves the `flyover` binary via `command -v flyover` against Quickshell's `PATH`. If that returns nothing, the widget falls back to checking a few well-known absolute paths (including `~/.cargo/bin/flyover`), and only then assumes the binary is missing entirely. So a vanilla `cargo install flyover` should now work without intervention — but a *minimal* install that only put `flyover` in some custom PATH directory outside the well-known list still won't be found.

### What to do

Pick whichever of these matches how you installed:

**If you installed with `cargo install`** (most common, what the flyover README recommends):

The widget now checks `~/.cargo/bin/flyover` explicitly as a fallback, so this should just work. If it doesn't, your cargo bin dir is somewhere exotic — point it at the widget by symlinking into a directory that *is* on Quickshell's `PATH`:

```
ln -sf ~/.cargo/bin/flyover ~/.local/bin/flyover
```

`~/.local/bin` is on Quickshell's `PATH` by default. Verify with `command -v flyover` from a fresh shell — you should see `/home/<you>/.local/bin/flyover`.

**If you built from source** (`git clone` + `cargo build --release`):

The widget doesn't check a build-tree path at all — symlink the binary
into `~/.local/bin` per the previous section, or `cargo install --path .`
from your clone so it lands in the checked `~/.cargo/bin`.

**If you installed from a package manager** (`pacman`, AUR, etc.):

The widget checks `/usr/bin/flyover` and `/usr/local/bin/flyover`. If your package installs to a non-standard location, symlink it into one of those, or into `~/.local/bin`.

**If you haven't installed flyover at all:**

The pill shows `✈ !` instead of an aircraft count, and clicking it opens [flyover's install instructions](https://github.com/linuxbren/flyover#install) in your default browser. That's the intended UX — the widget is telling you what's missing rather than silently failing. See the next section.

## If you haven't installed flyover yet

`omarchy plugin add https://github.com/linuxbren/flyover-pill.git --enable` works without flyover itself installed. The pill will appear in your bar showing `✈ !`, with the tooltip "flyover not installed — click for install instructions". Clicking opens the install section of flyover's README in your default browser via `xdg-open`.

Once you install flyover, restart the Omarchy shell (`omarchy-restart-shell`) so the widget re-resolves the binary, and the pill will start showing the real count.

## How to verify

1. **Terminal test** — run `flyover` in a foot terminal directly. If a radar scope appears, the binary itself is fine and the problem is only the widget's path resolution.
2. **Pill click** — once step 1 works, click the `✈ N` pill. A docked popup should open with its own live mini radar; its "Open flyover" button should open a new foot window with the same scope as step 1.
3. **Right-click** — if you've applied flyover's [screensaver patch](https://github.com/linuxbren/flyover/tree/master/packaging/screensaver), right-clicking the pill toggles the flyover screensaver on/off (using the repurposed `omarchy branding screensaver text|reset` command).

If step 1 works but step 2 doesn't, you're hitting the path issue described above — work through "What to do" in order.

## Uninstalling

```
omarchy plugin remove bren.flyover
```

Removes the pill from your bar. flyover itself is unaffected — uninstall it however you installed it (e.g. `cargo uninstall flyover`).
