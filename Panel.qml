import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The flyover pill's popup: a compact card anchored under the bar icon,
// mirroring the clock/weather panels' Loader + hostWidget contract. All
// data (aircraft count, location, install state, screensaver state) is
// owned by BarWidget.qml; this panel only reads it and offers the one
// action that matters — launching the scope.
Panel {
  id: root
  moduleName: "bren.flyover"
  ipcTarget: "bren.flyover"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.5)

  readonly property bool hasLocation: hostWidget ? hostWidget.hasLocation === true : false
  readonly property bool flyoverMissing: hostWidget ? hostWidget.flyoverMissing === true : true
  readonly property int aircraftCount: hostWidget ? hostWidget.aircraftCount : -1
  // Only the contacts adsb.lol has resolved a position for — see
  // Model.parseAdsbResponse. Can be shorter than aircraftCount.
  readonly property var aircraftList: hostWidget ? hostWidget.aircraftList : []
  readonly property bool screensaverEnabled: hostWidget ? hostWidget.screensaverEnabled === true : false
  readonly property real latitude: hostWidget ? hostWidget.latitude : NaN
  readonly property real longitude: hostWidget ? hostWidget.longitude : NaN

  // The radar always plots at this radius — matches the /100 fetch in
  // BarWidget.qml and flyover's own MAX_ZOOM_NM, so a contact at the ring's
  // edge here is a contact at the edge of the scope in the real app too.
  readonly property real radarRangeNm: 100
  readonly property real radarDiameter: Style.space(196)

  // Sweep: a rotating beam with a fading trail behind it, PPI-radar style.
  // flyover's own scope (raster.rs draw_sweep / braille_scope.rs) only ever
  // draws a single bare line for this, in the theme's accent color — no
  // trailing fade exists there yet. This is a new visual for the pill, with
  // an eye toward carrying it back to the full console app afterward, so it
  // borrows that same accent-for-sweep convention but adds the fade.
  readonly property int sweepPeriodMs: 6000
  readonly property int sweepTrailSteps: 22
  readonly property real sweepTrailSpanDeg: 60
  property real sweepAngle: 0

  readonly property string statusTitle: {
    if (!root.hasLocation) return "Location not set"
    if (root.aircraftCount < 0) return "Checking for aircraft…"
    if (root.aircraftCount === 0) return "No aircraft nearby"
    if (root.aircraftCount === 1) return "1 aircraft nearby"
    return root.aircraftCount + " aircraft nearby"
  }

  readonly property string locationMeta: root.hasLocation
    ? (root.latitude.toFixed(2) + ", " + root.longitude.toFixed(2))
    : "ADS-B"

  readonly property string actionLabel: root.flyoverMissing ? "View install instructions" : "Open flyover"

  readonly property string screensaverHint: "Right-click the pill to "
    + (root.screensaverEnabled ? "disable" : "enable") + " the flyover screensaver"

  function aircraftTooltip(ac) {
    if (!ac) return ""
    var altText = ac.onGround ? "ground" : Math.round(ac.altitude) + " ft"
    return ac.callsign + " · " + altText + " · " + ac.distanceNm.toFixed(1) + " nm · " + Math.round(ac.groundSpeed) + " kt"
  }

  // The single action this panel exists for. Delegates to the widget that
  // already owns launch/install-CTA logic, then gets out of the way.
  function launch() {
    if (hostWidget && typeof hostWidget.openScope === "function") hostWidget.openScope()
    root.close()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(240))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onActivateRequested: root.launch()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        Column {
          width: parent.width
          spacing: Style.space(2)

          Text {
            textFormat: Text.PlainText
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.statusTitle
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            visible: root.hasLocation
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.locationMeta
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }
        }

        // ---- Radar: a plain-QML reading of the same ADS-B data behind the
        //      bar count, not a copy of flyover's own Rust/ratatui scope —
        //      rings + a plane glyph per resolved contact, positioned by the
        //      distanceNm/bearingDeg adsb.lol already computed. Read-only;
        //      the button below is still what launches the real app.
        Item {
          id: radar
          visible: root.hasLocation
          width: root.radarDiameter
          height: root.radarDiameter
          anchors.horizontalCenter: parent.horizontalCenter

          readonly property real cx: width / 2
          readonly property real cy: height / 2
          // Inset so a contact at the range's edge doesn't clip the outer ring.
          readonly property real maxRadius: width / 2 - Style.space(9)

          Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)
            border.width: Style.spacing.hairline
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
          }

          Repeater {
            model: [0.34, 0.67, 1.0]

            Rectangle {
              required property real modelData
              width: radar.maxRadius * 2 * modelData
              height: width
              radius: width / 2
              anchors.centerIn: parent
              color: "transparent"
              border.width: Style.spacing.hairline
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
            }
          }

          Rectangle {
            width: parent.width
            height: Style.spacing.hairline
            anchors.verticalCenter: parent.verticalCenter
            color: root.foreground
            opacity: 0.08
          }

          Rectangle {
            width: Style.spacing.hairline
            height: parent.height
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.foreground
            opacity: 0.08
          }

          // Home marker.
          Rectangle {
            width: Style.space(5)
            height: Style.space(5)
            radius: width / 2
            anchors.centerIn: parent
            color: root.foreground
          }

          NumberAnimation {
            target: root
            property: "sweepAngle"
            running: root.opened && root.hasLocation
            from: 0
            to: 360
            duration: root.sweepPeriodMs
            loops: Animation.Infinite
          }

          // Trailing wedge: a step of thin spokes behind the beam, dimming
          // toward the tail, approximating a phosphor-glow fade with plain
          // Rectangles rather than a conic-gradient shader.
          Repeater {
            model: root.sweepTrailSteps

            Rectangle {
              id: spoke
              required property int index
              readonly property real stepDeg: root.sweepTrailSpanDeg / (root.sweepTrailSteps - 1)
              readonly property real bearingDeg: root.sweepAngle - index * stepDeg
              // t=1 at the beam itself, fading toward 0 at the tail. Squared
              // so the glow drops off fast up front and trails out long and
              // dim, rather than fading in a straight line.
              readonly property real t: 1 - index / (root.sweepTrailSteps - 1)

              x: radar.cx
              y: radar.cy - height / 2
              width: radar.maxRadius
              height: Style.spacing.hairline * 2
              transformOrigin: Item.Left
              rotation: bearingDeg - 90
              color: Color.accent
              opacity: 0.5 * t * t
            }
          }

          // The beam itself, on top of its own trail.
          Rectangle {
            x: radar.cx
            y: radar.cy - height / 2
            width: radar.maxRadius
            height: Style.spacing.hairline * 2
            transformOrigin: Item.Left
            rotation: root.sweepAngle - 90
            color: Color.accent
            opacity: 0.9
          }

          Repeater {
            model: root.aircraftList

            Item {
              id: dot
              required property var modelData

              readonly property real fraction: Math.min(1, modelData.distanceNm / root.radarRangeNm)
              readonly property real bearingRad: modelData.bearingDeg * Math.PI / 180

              x: radar.cx + radar.maxRadius * fraction * Math.sin(bearingRad) - width / 2
              y: radar.cy - radar.maxRadius * fraction * Math.cos(bearingRad) - height / 2
              width: Style.space(16)
              height: Style.space(16)

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "✈"
                // The glyph's own rest pose (Noto Color Emoji, which is what
                // resolves U+2708 here) already points ~45° off true north —
                // nose toward the upper right, not straight up — so a plain
                // `rotation: track` would land every heading 45° short.
                rotation: dot.modelData.track - 45
                color: hoverArea.containsMouse ? Color.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption

                Behavior on color { ColorAnimation { duration: 120 } }
              }

              MouseArea {
                id: hoverArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
              }

              PanelToolTip {
                visible: hoverArea.containsMouse
                text: root.aircraftTooltip(dot.modelData)
                fontFamily: root.fontFamily
              }
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: !root.hasLocation
          width: parent.width
          text: "Set a location to see nearby traffic:\nomarchy-weather-location --set \"<name>\" <lat,lon>"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
        }

        Button {
          id: launchButton
          anchors.horizontalCenter: parent.horizontalCenter
          bordered: true
          text: root.actionLabel
          foreground: root.foreground
          fontFamily: root.fontFamily
          horizontalPadding: Style.space(20)
          verticalPadding: Style.space(10)
          onClicked: root.launch()
        }

        Text {
          textFormat: Text.PlainText
          visible: !root.flyoverMissing
          width: parent.width
          text: root.screensaverHint
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }
}
