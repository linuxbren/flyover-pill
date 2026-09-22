import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Ambient "aircraft nearby" count for the bar. Left-click opens a docked
// popup (Panel.qml, following the clock/weather Loader + hostWidget
// pattern) with a button that launches the flyover TUI scope in a new
// terminal; right-click toggles the flyover screensaver on/off via
// Omarchy's own `omarchy branding screensaver text|reset` (repurposed by
// flyover's packaging/screensaver patches). Deliberately thin: this widget
// owns no scope-drawing or screensaver-patching logic of its own — that all
// lives in flyover itself.
//
// No hyprctl/focus-existing-window logic: this Hyprland build replaced the
// classic string dispatchers (`hyprctl dispatch focuswindow class:...`) with
// a Lua-table API (hl.dsp.window.*) that doesn't obviously expose "focus by
// class" the same way, and getting that exactly right needs more digging
// than this widget is worth blocking on. launchProc.running doubles as a
// crude de-dupe instead: Quickshell won't restart a Process that's already
// running, so clicking again while the scope is still open is a no-op
// rather than a second window — not as good as true focus-by-class, but
// correct and simple.
BarWidget {
  id: root
  moduleName: "bren.flyover"

  readonly property string weatherLocationPath: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
  readonly property string scopeAppId: "flyover-scope"
  readonly property string homeDir: Quickshell.env("HOME")
  // Resolved at startup (resolveBinaryProc below) by checking the user's
  // shell PATH first, then a few well-known absolute locations. Quickshell's
  // own PATH excludes ~/.cargo/bin, so a plain `cargo install flyover` lands
  // the binary somewhere `command -v` won't see from inside the shell —
  // check that path and a couple of others explicitly so the widget works
  // out of the box regardless of how flyover was installed. Empty string
  // here means "not found anywhere"; launchProc short-circuits in that case.
  property string scopeBinary: ""
  property bool flyoverMissing: true

  Process {
    id: resolveBinaryProc
    running: true
    command: ["/usr/bin/bash", "-c",
      "command -v flyover 2>/dev/null || " +
      "for c in \"$HOME/.cargo/bin/flyover\" /usr/bin/flyover /usr/local/bin/flyover; do " +
        "[ -x \"$c\" ] && echo \"$c\" && break; " +
      "done"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var resolved = String(text || "").trim()
        root.scopeBinary = resolved
        root.flyoverMissing = resolved.length === 0
      }
    }
  }

  property real latitude: NaN
  property real longitude: NaN
  readonly property bool hasLocation: !isNaN(latitude) && !isNaN(longitude)

  property int aircraftCount: -1
  // Sorted closest-first, each with distanceNm/bearingDeg already resolved —
  // see Model.parseAdsbResponse. The panel plots this directly; BarWidget
  // owns the fetch so the data survives the panel being closed/reopened.
  property var aircraftList: []
  readonly property string displayText: !hasLocation
    ? "✈ ?"
    : (flyoverMissing
        ? "✈ !"
        : (aircraftCount < 0 ? "✈ …" : ("✈ " + aircraftCount)))

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ---- Panel popup. Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the bar-widget
  //      root, and switchPanelFrom/the popout-dot compare against this
  //      widget rather than the nested Panel.qml item.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  FileView {
    id: locationFile
    path: root.weatherLocationPath
    watchChanges: true
    onLoaded: {
      var loc = Model.parseLocationFile(text())
      root.latitude = loc.latitude
      root.longitude = loc.longitude
    }
    onLoadFailed: {
      root.latitude = NaN
      root.longitude = NaN
    }
  }

  // Belt-and-suspenders on top of watchChanges above: inotify-style
  // watches can miss an update if whatever wrote the file replaced it
  // (temp file + rename) rather than writing in place, which invalidates
  // a watch tied to the old inode — omarchy-weather-location currently
  // does a plain in-place `>` write, so that specific gap shouldn't apply
  // today, but a location change is rare and worth being sure about
  // regardless of how it got written. Light on purpose: this only needs
  // to eventually notice, not react immediately.
  Timer {
    interval: 300000
    running: true
    repeat: true
    onTriggered: locationFile.reload()
  }

  function refresh() {
    if (root.hasLocation && !fetchProc.running) fetchProc.running = true
  }

  Process {
    id: fetchProc
    command: ["curl", "-fsS", "--max-time", "5",
      "https://api.adsb.lol/v2/point/" + root.latitude + "/" + root.longitude + "/100"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseAdsbResponse(String(text || ""))
        root.aircraftCount = parsed.count
        root.aircraftList = parsed.aircraft
      }
    }
  }

  // Ambient signal only — polls far less often than the scope app itself,
  // which fetches every ~10s while actually open.
  Timer {
    interval: 20000
    running: root.hasLocation
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  function openScope() {
    if (root.flyoverMissing) {
      // Open the install README rather than doing nothing silently. xdg-open
      // is the standard Linux way to hand a URL to the user's preferred app.
      missingProc.running = true
      return
    }
    launchProc.running = true
  }

  Process {
    id: missingProc
    command: ["/usr/bin/xdg-open", "https://github.com/linuxbren/flyover#install"]
  }

  // Direct argv invocation — no shell involved, so no quoting to get wrong.
  // Absolute path since Quickshell's Process isn't guaranteed to inherit an
  // interactive shell's PATH.
  Process {
    id: launchProc
    command: ["/usr/bin/foot", "-a", root.scopeAppId, "-T", "flyover", "-H", "-D", root.homeDir, root.scopeBinary]
    stderr: StdioCollector {
      onStreamFinished: if (text) console.warn("bren.flyover launch stderr: " + text)
    }
  }

  // Whether the flyover screensaver patch is currently applied. Detected by
  // checking the live omarchy-screensaver script for flyover's marker
  // comment, rather than tracked as our own state, so this stays correct
  // even if the patch was applied/reverted from a terminal instead of here.
  property bool screensaverEnabled: false

  function checkScreensaverState() {
    if (!checkScreensaverStateProc.running) checkScreensaverStateProc.running = true
  }

  Process {
    id: checkScreensaverStateProc
    running: true
    command: ["/usr/bin/bash", "-c",
      "grep -q 'flyover:live-patch' \"$(readlink -f \"$(command -v omarchy-screensaver)\")\" 2>/dev/null && echo enabled || echo disabled"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.screensaverEnabled = String(text || "").trim() === "enabled"
      }
    }
  }

  function toggleScreensaver() {
    if (toggleScreensaverProc.running) return
    toggleScreensaverProc.command = ["/usr/bin/omarchy", "branding", "screensaver", root.screensaverEnabled ? "reset" : "text"]
    toggleScreensaverProc.running = true
  }

  // `omarchy branding screensaver text|reset` already sends its own desktop
  // notification and relaunches the screensaver for a preview -- this just
  // re-checks state afterward so screensaverEnabled (and the tooltip) stay
  // accurate.
  Process {
    id: toggleScreensaverProc
    stderr: StdioCollector {
      onStreamFinished: if (text) console.warn("bren.flyover screensaver toggle stderr: " + text)
    }
    onExited: root.checkScreensaverState()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText
    // Tooltip suppressed because the panel is the detail view (it already
    // shows the screensaver hint).
    tooltipText: ""
    onPressed: function(b) {
      if (b === Qt.RightButton) {
        root.toggleScreensaver()
      } else {
        root.togglePanel()
      }
    }
  }
}
