import QtQuick
import qs.Commons

Rectangle {
  id: globe

  property var satellitesModel
  property var contactVisible
  property var categoryColor
  property double positionEpochMs: 0
  property int trackedNoradId: -1
  property real yaw: 0
  property real pitch: 18
  property real globeZoom: 1
  property var hitTargets: []
  property int hitTargetCount: 0
  property var hoveredSatellite: null

  signal satelliteSelected(int noradId)

  radius: Style.cornerRadius * 1.5
  color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.76)
  border.width: 1
  border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.38)
  clip: true

  function currentPosition(satellite) {
    var elapsed = Math.max(0, Math.min(10, (Date.now() - positionEpochMs) / 1000))
    var longitude = Number(satellite.longitude) + Number(satellite.longitudeRate || 0) * elapsed
    longitude = ((longitude + 180) % 360 + 360) % 360 - 180
    return {
      latitude: Number(satellite.latitude) + Number(satellite.latitudeRate || 0) * elapsed,
      longitude: longitude
    }
  }
  function requestPaint() { globeCanvas.requestPaint() }
  function cancelCameraFocus() {
    yawFocus.stop()
    pitchFocus.stop()
    zoomFocus.stop()
  }
  function focusSatellite(satellite) {
    if (!satellite) return
    var position = currentPosition(satellite)
    cancelCameraFocus()
    var targetYaw = position.longitude
    var yawDelta = ((targetYaw - yaw + 540) % 360) - 180
    yawFocus.from = yaw
    yawFocus.to = yaw + yawDelta
    pitchFocus.from = pitch
    pitchFocus.to = Math.max(-82, Math.min(82, position.latitude))
    zoomFocus.from = globeZoom
    zoomFocus.to = 1.9
    yawFocus.start()
    pitchFocus.start()
    zoomFocus.start()
  }

  onYawChanged: requestPaint()
  onPitchChanged: requestPaint()
  onGlobeZoomChanged: requestPaint()

  NumberAnimation { id: yawFocus; target: globe; property: "yaw"; duration: 320; easing.type: Easing.OutCubic }
  NumberAnimation { id: pitchFocus; target: globe; property: "pitch"; duration: 320; easing.type: Easing.OutCubic }
  NumberAnimation { id: zoomFocus; target: globe; property: "globeZoom"; duration: 280; easing.type: Easing.OutCubic }

  Canvas {
    id: globeCanvas
    anchors.fill: parent

    function projected(latitude, longitude, radius) {
      var latitudeRadians = Number(latitude) * Math.PI / 180
      var longitudeRadians = (Number(longitude) - globe.yaw) * Math.PI / 180
      var pitchRadians = globe.pitch * Math.PI / 180
      var cosLatitude = Math.cos(latitudeRadians)
      var x = cosLatitude * Math.sin(longitudeRadians)
      var y = Math.sin(latitudeRadians)
      var z = cosLatitude * Math.cos(longitudeRadians)
      var rotatedY = y * Math.cos(pitchRadians) - z * Math.sin(pitchRadians)
      var rotatedZ = y * Math.sin(pitchRadians) + z * Math.cos(pitchRadians)
      return { x: width / 2 + x * radius,
               y: height / 2 - rotatedY * radius,
               depth: rotatedZ }
    }

    function drawGridLine(ctx, latitudePoints, earthRadius, alpha) {
      var drawing = false
      ctx.globalAlpha = alpha
      ctx.beginPath()
      for (var i = 0; i < latitudePoints.length; ++i) {
        var point = projected(latitudePoints[i].latitude, latitudePoints[i].longitude, earthRadius)
        if (point.depth <= 0) { drawing = false; continue }
        if (!drawing) { ctx.moveTo(point.x, point.y); drawing = true }
        else ctx.lineTo(point.x, point.y)
      }
      ctx.stroke()
    }

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var earthRadius = Math.max(1, (Math.min(width, height) / 2 - Style.space(20)) * globe.globeZoom)
      var centerX = width / 2, centerY = height / 2

      ctx.fillStyle = Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.36)
      ctx.strokeStyle = Color.accent
      ctx.lineWidth = 1
      ctx.globalAlpha = 0.58
      ctx.beginPath(); ctx.arc(centerX, centerY, earthRadius, 0, Math.PI * 2); ctx.fill(); ctx.stroke()

      ctx.strokeStyle = Color.accent
      ctx.lineWidth = 0.7
      for (var latitude = -60; latitude <= 60; latitude += 30) {
        var latitudePoints = []
        for (var longitude = -180; longitude <= 180; longitude += 5)
          latitudePoints.push({ latitude: latitude, longitude: longitude })
        drawGridLine(ctx, latitudePoints, earthRadius, latitude === 0 ? 0.42 : 0.24)
      }
      for (var meridian = -150; meridian <= 180; meridian += 30) {
        var longitudePoints = []
        for (var gridLatitude = -90; gridLatitude <= 90; gridLatitude += 4)
          longitudePoints.push({ latitude: gridLatitude, longitude: meridian })
        drawGridLine(ctx, longitudePoints, earthRadius, 0.22)
      }

      var targets = globe.hitTargets
      var targetCount = 0
      if (globe.satellitesModel) {
        for (var satelliteIndex = 0; satelliteIndex < globe.satellitesModel.count; ++satelliteIndex) {
          var satellite = globe.satellitesModel.get(satelliteIndex)
          if (!globe.contactVisible(satellite)) continue
          var position = globe.currentPosition(satellite)
          // Altitude is deliberately compressed but exaggerated: LEO remains
          // close to Earth while navigation satellites visibly sit farther out.
          var altitude = Math.max(0, Number(satellite.altitudeKm || 0))
          var altitudeFactor = 1 + Math.min(0.48, Math.sqrt(altitude / 24000) * 0.48)
          var point = projected(position.latitude, position.longitude, earthRadius * altitudeFactor)
          var selected = Number(satellite.noradId) === globe.trackedNoradId
          var markerRadius = selected ? 3.8 : 2.5
          // Keep the rear hemisphere visible as a subdued orbital overview.
          ctx.globalAlpha = point.depth < 0
            ? Math.max(0.1, 0.22 * (1 + point.depth))
            : Math.max(0.22, Math.min(1, 0.22 + point.depth * 2.4))
          ctx.fillStyle = selected ? "#ff5fa2" : globe.categoryColor(satellite.category)
          ctx.beginPath(); ctx.arc(point.x, point.y, markerRadius, 0, Math.PI * 2); ctx.fill()
          if (selected) {
            ctx.strokeStyle = "#ff5fa2"; ctx.lineWidth = 1.2
            ctx.beginPath(); ctx.arc(point.x, point.y, markerRadius + 3, 0, Math.PI * 2); ctx.stroke()
          }
          var target = targets[targetCount]
          if (!target) { target = {}; targets.push(target) }
          target.x = point.x; target.y = point.y; target.radius = Math.max(6, markerRadius + 2)
          target.noradId = Number(satellite.noradId); target.name = String(satellite.name)
          target.altitudeKm = altitude; target.category = String(satellite.category)
          targetCount++
        }
      }
      globe.hitTargetCount = targetCount
      ctx.globalAlpha = 1
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    hoverEnabled: true
    cursorShape: pressed ? Qt.ClosedHandCursor
      : (globe.hoveredSatellite ? Qt.PointingHandCursor : Qt.OpenHandCursor)
    property real lastX: 0
    property real lastY: 0
    property bool dragged: false

    function updateHover(mouse) {
      var closest = null, best = 10 * 10
      for (var i = 0; i < globe.hitTargetCount; ++i) {
        var target = globe.hitTargets[i]
        var dx = target.x - mouse.x, dy = target.y - mouse.y
        var distance = dx * dx + dy * dy
        if (distance <= best) { closest = target; best = distance }
      }
      globe.hoveredSatellite = closest
    }
    onPressed: function(mouse) {
      globe.cancelCameraFocus()
      lastX = mouse.x
      lastY = mouse.y
      dragged = false
    }
    onPositionChanged: function(mouse) {
      if (!pressed) { updateHover(mouse); return }
      var dx = mouse.x - lastX, dy = mouse.y - lastY
      if (Math.abs(dx) + Math.abs(dy) < 1) return
      dragged = true; lastX = mouse.x; lastY = mouse.y
      globe.yaw = ((globe.yaw - dx * 0.55 + 180) % 360 + 360) % 360 - 180
      globe.pitch = Math.max(-88, Math.min(88, globe.pitch + dy * 0.45))
      globe.hoveredSatellite = null
      globeCanvas.requestPaint()
    }
    onClicked: function(mouse) {
      if (dragged) return
      updateHover(mouse)
      if (globe.hoveredSatellite) globe.satelliteSelected(globe.hoveredSatellite.noradId)
    }
    onWheel: function(wheel) {
      globe.cancelCameraFocus()
      var zoomStep = wheel.angleDelta.y > 0 ? 1.12 : 1 / 1.12
      globe.globeZoom = Math.max(0.72, Math.min(2.6, globe.globeZoom * zoomStep))
      globeCanvas.requestPaint()
      wheel.accepted = true
    }
    onExited: globe.hoveredSatellite = null
  }

  Rectangle {
    visible: globe.hoveredSatellite !== null
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.space(5)
    width: altitudeLabel.implicitWidth + Style.space(10)
    height: altitudeLabel.implicitHeight + Style.space(6)
    radius: Style.cornerRadius
    color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.9)

    Text {
      id: altitudeLabel
      anchors.centerIn: parent
      text: globe.hoveredSatellite
        ? globe.hoveredSatellite.name + " · " + Math.round(globe.hoveredSatellite.altitudeKm) + " km"
        : ""
      color: globe.hoveredSatellite ? globe.categoryColor(globe.hoveredSatellite.category) : Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  Timer {
    interval: 500
    repeat: true
    running: globe.visible
    onTriggered: globeCanvas.requestPaint()
  }
}
