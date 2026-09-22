# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This is an
Omarchy plugin, not a crate — versioning here isn't SemVer-strict, just
`manifest.json`'s own `version` field, bumped each time enough shipped to
be worth a number.

## [Unreleased]

## [1.1.0] - 2026-09-22

### Added

- Left-click now opens a docked popup with its own live mini radar
  (range rings, rotating sweep with a fading trail, nearby contacts) —
  previously it launched the full `flyover` scope directly. The popup's
  "Open flyover" button still launches the real terminal scope.
- Right-click toggle for flyover's screensaver, once its one-time setup
  is done (see flyover's own `packaging/screensaver/` docs).

### Changed

- Sweep timing (period, trail span) now hand-kept in sync with the
  console app, so the two feel like the same instrument.
- Weather-location changes are now also picked up via a lightweight
  5-minute poll, on top of the existing file-watcher — belt and
  suspenders against a watch gap.

### Fixed

- Binary resolution now checks more fallback paths
  (`~/.cargo/bin/flyover`, `/usr/bin/flyover`, `/usr/local/bin/flyover`)
  and shows an install prompt (`✈ !`) instead of silently doing nothing
  when `flyover` can't be found on Quickshell's own `PATH`.

## [1.0.0] - 2026-09-16

Initial release.

### Added

- Ambient "aircraft nearby" count in the Omarchy bar, polling
  [adsb.lol](https://adsb.lol) every ~20s using the same location
  flyover itself reads.
- Left-click launches (or focuses) the `flyover` scope in a terminal.
- Right-click toggles flyover's screensaver on/off.

[Unreleased]: https://github.com/linuxbren/flyover-pill/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/linuxbren/flyover-pill/compare/fe6292b...v1.1.0
[1.0.0]: https://github.com/linuxbren/flyover-pill/commits/fe6292b
