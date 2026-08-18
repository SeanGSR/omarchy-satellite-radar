import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "TileMath.js" as TileMath

Panel {
  id: root
  moduleName: "ldng.satellite-radar"
  ipcTarget: moduleName
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color homeColor: "#b48cff"
  readonly property color selectedSatelliteColor: "#ff5fa2"
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property real textScale: 1.1
  readonly property real controlGap: Style.space(4)
  readonly property real hudInset: Style.space(8)
  readonly property real hudButtonSize: Style.space(34)
  readonly property color hudButtonBackground: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.72)
  readonly property int contactCount: contacts.count
  property real centreLat: NaN
  property real centreLon: NaN
  property string locationSource: ""
  property string errorText: ""
  property string updatedText: ""
  property bool fetching: false
  property int visibleTotal: 0
  property real mapZoom: 4
  readonly property int maxMapZoom: 9
  property real viewLat: NaN
  property real viewLon: NaN
  property bool mapPanned: false
  property double positionEpochMs: 0
  property real animationPhase: 0
  property bool usingWeatherLocation: false
  property int trackedNoradId: -1
  property bool infoTrayOpen: false
  property bool searchTrayOpen: false
  property bool miniGlobeOpen: false
  property bool performanceMenuOpen: false
  property bool starlinkBeforeGlobal: true
  property bool resolvingManualLocation: false
  property var locationSuggestions: []
  property int suggestionIndex: 0
  property string geocodePendingQuery: ""
  property string geocodeActiveQuery: ""
  property bool showStarlink: true
  property bool showNavigation: true
  property bool showStation: true
  property bool showOther: true
  readonly property string performanceMode: {
    var mode = String(conf("performanceMode", "Balanced"))
    return mode === "High" || mode === "Maximum" || mode === "Global" ? mode : "Balanced"
  }

  TextMetrics { id: starlinkIconMetrics; font.family: root.fontFamily; font.pixelSize: 100; text: root.satelliteIcon("starlink") }
  TextMetrics { id: navigationIconMetrics; font.family: root.fontFamily; font.pixelSize: 100; text: root.satelliteIcon("navigation") }
  TextMetrics { id: stationIconMetrics; font.family: root.fontFamily; font.pixelSize: 100; text: root.satelliteIcon("station") }
  TextMetrics { id: otherIconMetrics; font.family: root.fontFamily; font.pixelSize: 100; text: root.satelliteIcon("other") }

  function conf(key, fallback) {
    if (!root.settings || root.settings[key] === undefined || root.settings[key] === null)
      return fallback
    return root.settings[key]
  }
  function performanceLimitFor(mode) {
    return mode === "Global" ? "all catalogued"
      : (mode === "Maximum" ? 300 : (mode === "High" ? 150 : 60))
  }
  function performanceLimit() { return performanceLimitFor(performanceMode) }
  function performanceColorFor(mode) {
    return mode === "Global" ? satelliteColor("other")
      : mode === "Maximum" ? selectedSatelliteColor
      : (mode === "High" ? satelliteColor("navigation") : Color.accent)
  }
  function performanceColor() { return performanceColorFor(performanceMode) }
  function setPerformanceMode(mode) {
    var next = String(mode)
    if (["Balanced", "High", "Maximum", "Global"].indexOf(next) < 0) return
    var previous = performanceMode
    performanceMenuOpen = false
    if (next === "Global" && previous !== "Global") {
      starlinkBeforeGlobal = showStarlink
      showStarlink = false
      cancelMapFocus()
      trackedNoradId = -1
      mapZoom = 2
      viewLat = centreLat
      viewLon = centreLon
      miniGlobeOpen = true
    } else if (previous === "Global" && next !== "Global") {
      showStarlink = starlinkBeforeGlobal
    }
    persist({ performanceMode: next })
    rebuildFilteredContacts()
    performanceRefreshTimer.restart()
  }
  function satelliteColor(category) {
    switch (String(category)) {
    case "starlink": return "#4da3ff"
    case "navigation": return "#ffc857"
    case "station": return "#d66efd"
    default: return "#6ee7b7"
    }
  }
  function satelliteIcon(category) {
    switch (String(category)) {
    case "starlink": return "󰑱"
    case "navigation": return ""
    case "station": return ""
    default: return ""
    }
  }
  function satelliteIconOffset(category, size) {
    var metrics
    switch (String(category)) {
    case "starlink": metrics = starlinkIconMetrics; break
    case "navigation": metrics = navigationIconMetrics; break
    case "station": metrics = stationIconMetrics; break
    default: metrics = otherIconMetrics
    }
    var bounds = metrics.tightBoundingRect
    var scale = (Number(size) || 0) / 100
    return {
      x: -(bounds.x + bounds.width / 2) * scale,
      y: -(bounds.y + bounds.height / 2) * scale
    }
  }
  function satelliteRadius(rangeKm) {
    var distance = Math.max(400, Number(rangeKm) || 25000)
    return 2.3 + 5.2 * Math.exp(-(distance - 400) / 500)
  }
  function categoryVisible(category) {
    switch (String(category)) {
    case "starlink": return showStarlink
    case "navigation": return showNavigation
    case "station": return showStation
    default: return showOther
    }
  }
  function contactVisible(contact) {
    return categoryVisible(contact.category)
  }
  function rebuildFilteredContacts() {
    filteredContacts.clear()
    var trackedStillVisible = root.trackedNoradId < 0
    for (var i = 0; i < contacts.count; ++i) {
      var contact = contacts.get(i)
      if (!contactVisible(contact)) continue
      filteredContacts.append(contact)
      if (Number(contact.noradId) === root.trackedNoradId) trackedStillVisible = true
    }
    if (!trackedStillVisible) root.trackedNoradId = -1
    scope.requestPaint()
    miniGlobe.requestPaint()
  }
  function toggleCategory(category) {
    switch (String(category)) {
    case "starlink": showStarlink = !showStarlink; break
    case "navigation": showNavigation = !showNavigation; break
    case "station": showStation = !showStation; break
    default: showOther = !showOther
    }
    rebuildFilteredContacts()
  }
  function satelliteType(category) {
    switch (String(category)) {
    case "starlink": return "Starlink"
    case "navigation": return "Navigation"
    case "station": return "Station"
    default: return "Other"
    }
  }
  function compassDirection(azimuth) {
    var directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    return directions[Math.round(((Number(azimuth) % 360) + 360) % 360 / 45) % 8]
  }
  readonly property bool hasManualLocation:
    Number.isFinite(Number(conf("latitude", NaN))) && Number.isFinite(Number(conf("longitude", NaN)))
  readonly property int refreshMs: Math.max(performanceMode === "Global" ? 30 : 5,
    Number(conf("refreshIntervalSec", 5))) * 1000
  readonly property bool darkTheme: {
    var background = Color.background
    return (0.2126 * background.r + 0.7152 * background.g + 0.0722 * background.b) < 0.5
  }
  readonly property string basemapStyle: darkTheme ? "dark_all" : "light_all"

  function open() { root.controller.show(); if (contacts.count === 0) refresh() }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }
  function recenterMap() {
    cancelMapFocus()
    trackedNoradId = -1
    viewLat = centreLat
    viewLon = centreLon
    mapPanned = false
  }
  function cancelMapFocus() { mapZoomFocus.stop() }
  function animateMapFocus() {
    cancelMapFocus()
    var targetZoom = Math.max(mapZoom, Math.min(maxMapZoom, 7))
    if (targetZoom <= mapZoom + 0.01) return
    mapZoomFocus.from = mapZoom
    mapZoomFocus.to = targetZoom
    mapZoomFocus.start()
  }
  function trackSatellite(noradId) {
    trackedNoradId = Number(noradId)
    mapPanned = true
    miniGlobeOpen = true
    updateTrackedView(true)
    animateMapFocus()
    scope.requestPaint()
  }
  onMapZoomChanged: scope.requestPaint()

  NumberAnimation {
    id: mapZoomFocus
    target: root
    property: "mapZoom"
    duration: 360
    easing.type: Easing.OutCubic
  }
  function updateTrackedView(focusGlobe) {
    if (trackedNoradId < 0) return
    for (var i = 0; i < contacts.count; ++i) {
      var satellite = contacts.get(i)
      if (Number(satellite.noradId) !== trackedNoradId) continue
      var elapsed = Math.max(0, Math.min(10, (Date.now() - root.positionEpochMs) / 1000))
      viewLat = Number(satellite.latitude) + Number(satellite.latitudeRate || 0) * elapsed
      var longitude = Number(satellite.longitude) + Number(satellite.longitudeRate || 0) * elapsed
      viewLon = ((longitude + 180) % 360 + 360) % 360 - 180
      if (focusGlobe) miniGlobe.focusSatellite(satellite)
      return
    }
    trackedNoradId = -1
  }
  function persist(values) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    for (var value in values) entry[value] = values[value]
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }
  function setHomeFromMap(x, y, width, height) {
    var point = TileMath.unprojectFromViewport(
      x, y, root.viewLat, root.viewLon, root.mapZoom, width, height)
    root.centreLat = point.latitude
    root.centreLon = point.longitude
    root.locationSource = "Satellite Radar pin"
    root.usingWeatherLocation = true
    weatherLocationSave.command = ["omarchy-weather-location", "--set", "Satellite Radar pin",
      point.latitude + "," + point.longitude]
    weatherLocationSave.running = true
    root.recenterMap()
    root.refresh()
    scope.requestPaint()
  }
  function setSharedLocation(name, latitude, longitude) {
    latitude = Number(latitude)
    longitude = Number(longitude)
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)
        || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      errorText = "Enter a city or valid latitude, longitude"
      return
    }
    centreLat = latitude
    centreLon = longitude
    locationSource = name
    usingWeatherLocation = true
    weatherLocationSave.command = ["omarchy-weather-location", "--set", name,
      latitude + "," + longitude]
    weatherLocationSave.running = true
    recenterMap()
    refresh()
    scope.requestPaint()
  }
  function submitManualLocation(value) {
    var query = String(value || "").trim()
    if (query === "" || resolvingManualLocation) return
    errorText = ""

    var coordinates = query.match(/^(-?\d+(?:\.\d+)?)\s*[,;]\s*(-?\d+(?:\.\d+)?)$/)
    if (coordinates) {
      setSharedLocation("Custom location", coordinates[1], coordinates[2])
      manualLocationField.clear()
      keyCatcher.forceActiveFocus()
      return
    }

    resolvingManualLocation = true
    manualLocationProcess.command = ["node",
      Qt.resolvedUrl("geocode.js").toString().replace("file://", ""), query]
    manualLocationProcess.running = true
  }
  function normalizedPlaceName(value) {
    return String(value || "").toLowerCase().normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]/g, "")
  }
  function spellingDistance(left, right) {
    left = normalizedPlaceName(left)
    right = normalizedPlaceName(right)
    if (!left.length) return right.length
    if (!right.length) return left.length
    var previous = []
    for (var column = 0; column <= right.length; ++column) previous[column] = column
    for (var row = 1; row <= left.length; ++row) {
      var current = [row]
      for (column = 1; column <= right.length; ++column) {
        var substitution = previous[column - 1] + (left[row - 1] === right[column - 1] ? 0 : 1)
        current[column] = Math.min(previous[column] + 1, current[column - 1] + 1, substitution)
      }
      previous = current
    }
    return previous[right.length]
  }
  function locationMatchScore(query, place) {
    var wanted = normalizedPlaceName(query)
    var candidate = normalizedPlaceName(place.name)
    var distance = spellingDistance(wanted, candidate) / Math.max(1, wanted.length, candidate.length)
    var prefixBonus = candidate.indexOf(wanted) === 0 || wanted.indexOf(candidate) === 0 ? 0.22 : 0
    var populationBonus = Math.log(Math.max(1, Number(place.population) || 1)) / 250
    return distance - prefixBonus - populationBonus
  }
  function requestGeocode() {
    var query = manualLocationField.text.trim()
    if (query.length < 2 || /^(-?\d+(?:\.\d+)?)\s*[,;]/.test(query)) {
      locationSuggestions = []
      return
    }
    geocodePendingQuery = query
    if (!geocodeProcess.running) startGeocode()
  }
  function startGeocode() {
    geocodeActiveQuery = geocodePendingQuery
    geocodeProcess.command = ["node",
      Qt.resolvedUrl("geocode.js").toString().replace("file://", ""), geocodeActiveQuery]
    geocodeProcess.running = true
  }
  function pickSuggestion(place) {
    if (!place) return
    locationSuggestions = []
    setSharedLocation(place.name + (place.description ? ", " + place.description : ""),
      place.latitude, place.longitude)
    manualLocationField.clear()
    keyCatcher.forceActiveFocus()
  }
  function useComputerLocation() {
    if (autoLocationReset.running) return
    errorText = ""
    usingWeatherLocation = false
    autoLocationReset.command = ["omarchy-weather-location", "--clear"]
    autoLocationReset.running = true
  }
  function toggleSearchTray() {
    searchTrayOpen = !searchTrayOpen
    if (searchTrayOpen) {
      Qt.callLater(function() { manualLocationField.forceActiveFocus() })
    } else {
      locationSuggestions = []
      keyCatcher.forceActiveFocus()
    }
  }
  function applyWeatherLocation(raw) {
    try {
      var location = JSON.parse(String(raw || ""))
      var latitude = Number(location.latitude)
      var longitude = Number(location.longitude)
      if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return
      if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return
      usingWeatherLocation = true
      centreLat = latitude
      centreLon = longitude
      locationSource = String(location.name || "Omarchy weather")
      recenterMap()
      refresh()
    } catch (error) {}
  }
  function resolveLocation() {
    if (usingWeatherLocation) return
    locateProcess.command = [Qt.resolvedUrl("locate").toString().replace("file://", "")]
    locateProcess.running = true
  }
  function refresh() {
    if (!Number.isFinite(centreLat) || !Number.isFinite(centreLon) || fetching) return
    fetching = true
    errorText = ""
    fetchProcess.command = [
      "node", Qt.resolvedUrl("satellite-fetch.js").toString().replace("file://", ""),
      String(centreLat), String(centreLon), String(conf("minimumElevation", 0)),
      conf("includeStarlink", true) === true ? "starlink" : "core",
      String(conf("performanceMode", "Balanced")).toLowerCase()
    ]
    fetchProcess.running = true
  }
  function applyContacts(payload) {
    contacts.clear()
    if (!payload || payload.error) {
      filteredContacts.clear()
      errorText = payload && payload.error ? String(payload.error) : "Satellite data was unreadable"
      scope.requestPaint()
      return
    }
    var rows = payload.satellites || []
    positionEpochMs = Number(payload.timestampMs || Date.now())
    visibleTotal = Number(payload.visibleTotal || rows.length)
    for (var i = 0; i < rows.length; ++i) contacts.append(rows[i])
    rebuildFilteredContacts()
    updatedText = Qt.formatTime(new Date(), "HH:mm:ss")
    scope.requestPaint()
  }

  Component.onCompleted: {
    mapZoom = Math.round(Math.max(2, Math.min(root.maxMapZoom, Number(conf("mapZoom", 4)))))
    resolveLocation()
  }
  onSettingsChanged: resolveLocation()

  ListModel { id: contacts }
  ListModel { id: filteredContacts }

  FileView {
    id: weatherLocationFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyWeatherLocation(text())
  }

  Process {
    id: weatherLocationSave
    onExited: weatherLocationFile.reload()
  }

  Process {
    id: autoLocationReset
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.errorText = "Could not reset the automatic location"
        return
      }
      weatherLocationFile.reload()
      root.resolveLocation()
    }
  }

  Process {
    id: manualLocationProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var payload = JSON.parse(text)
          var place = payload.results && payload.results.length ? payload.results[0] : null
          if (!place) {
            root.errorText = "Location not found"
          } else {
            var label = String(place.name || "Custom location")
            if (place.admin1 && place.admin1 !== place.name) label += ", " + place.admin1
            if (place.country) label += ", " + place.country
            root.setSharedLocation(label, place.latitude, place.longitude)
            manualLocationField.clear()
            keyCatcher.forceActiveFocus()
          }
        } catch (error) {
          root.errorText = "Could not read the location search result"
        }
      }
    }
    onExited: function(exitCode) {
      root.resolvingManualLocation = false
      if (exitCode !== 0) root.errorText = "Location search failed"
    }
  }

  Process {
    id: geocodeProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var suggestions = []
        try {
          var payload = JSON.parse(text)
          var results = payload.results || []
          results.sort(function(left, right) {
            return root.locationMatchScore(root.geocodeActiveQuery, left)
              - root.locationMatchScore(root.geocodeActiveQuery, right)
          })
          for (var i = 0; i < results.length; ++i) {
            var place = results[i]
            if (!place.name || place.latitude === undefined || place.longitude === undefined) continue
            var description = [place.admin1, place.country].filter(function(part) { return !!part }).join(", ")
            suggestions.push({
              name: String(place.name),
              description: description,
              latitude: Number(place.latitude),
              longitude: Number(place.longitude)
            })
          }
        } catch (error) {}
        root.locationSuggestions = manualLocationField.activeFocus ? suggestions : []
        root.suggestionIndex = 0
        if (root.geocodePendingQuery !== root.geocodeActiveQuery) Qt.callLater(root.startGeocode)
      }
    }
  }

  Timer {
    id: geocodeDebounce
    interval: 300
    onTriggered: root.requestGeocode()
  }

  Timer {
    id: performanceRefreshTimer
    interval: 150
    repeat: true
    onTriggered: {
      if (root.fetching) return
      stop()
      root.refresh()
    }
  }

  Process {
    id: locateProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var result = JSON.parse(text)
          if (result.error) { root.errorText = result.error; return }
          root.centreLat = Number(result.latitude)
          root.centreLon = Number(result.longitude)
          root.locationSource = String(result.source || "automatic")
          root.recenterMap()
          root.refresh()
        } catch (error) { root.errorText = "Could not determine your location" }
      }
    }
  }

  Process {
    id: fetchProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.fetching = false
        try { root.applyContacts(JSON.parse(text)) }
        catch (error) { root.errorText = "Could not read satellite positions" }
      }
    }
    onExited: function(exitCode) {
      root.fetching = false
      if (exitCode !== 0 && root.errorText === "") root.errorText = "Satellite calculation failed"
    }
  }

  Timer {
    interval: root.refreshMs
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  NumberAnimation on animationPhase {
    from: 0
    to: 1
    duration: 1800
    loops: Animation.Infinite
    easing.type: Easing.InOutSine
    running: root.opened
  }
  onAnimationPhaseChanged: {
    if (root.performanceMode === "Global") return
    root.updateTrackedView()
    scope.requestPaint()
  }

  Timer {
    interval: 500
    repeat: true
    running: root.opened && root.performanceMode === "Global"
    onTriggered: {
      root.updateTrackedView()
      scope.requestPaint()
      miniGlobe.requestPaint()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    padding: Style.space(8)
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(750))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight - panel.padding * 2)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: root.refresh()
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
          root.cancelMapFocus()
          root.mapZoom = Math.min(root.maxMapZoom, Math.round(root.mapZoom) + 1)
          event.accepted = true
        } else if (event.key === Qt.Key_Minus) {
          root.cancelMapFocus()
          root.mapZoom = Math.max(2, Math.round(root.mapZoom) - 1)
          event.accepted = true
        }
      }

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(4)
        property real textInset: Style.space(6)

        Item {
          id: mapToolbar
          parent: radarBody
          z: 50
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.leftMargin: root.hudInset
          anchors.rightMargin: root.hudInset
          anchors.topMargin: root.hudInset
          height: Style.space(34)

          Button {
            id: computerLocationButton
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: root.hudButtonSize
            height: root.hudButtonSize
            iconText: "󰋜"
            iconSize: Style.font.icon * root.textScale
            tooltipText: "Return to radar location"
            foreground: root.homeColor
            background: root.hudButtonBackground
            accent: Color.accent
            bordered: true
            onClicked: { root.recenterMap(); scope.requestPaint() }
          }

          Button {
            id: searchTrayButton
            anchors.left: computerLocationButton.right
            anchors.leftMargin: root.controlGap
            anchors.verticalCenter: parent.verticalCenter
            width: root.hudButtonSize
            height: root.hudButtonSize
            iconText: ""
            iconSize: Style.font.icon * root.textScale
            tooltipText: root.searchTrayOpen ? "Hide location search" : "Search location"
            foreground: root.searchTrayOpen ? Color.accent : root.foreground
            background: root.hudButtonBackground
            accent: Color.accent
            selected: root.searchTrayOpen
            bordered: true
            onClicked: root.toggleSearchTray()
          }

          Button {
            id: performanceButton
            anchors.right: miniGlobeButton.left
            anchors.rightMargin: root.controlGap
            anchors.verticalCenter: parent.verticalCenter
            width: root.hudButtonSize
            height: root.hudButtonSize
            iconText: "󰓅"
            iconSize: Style.font.icon * root.textScale
            tooltipText: "Performance: " + root.performanceMode + " · "
              + (root.performanceMode === "Global" ? root.performanceLimit()
                : "up to " + root.performanceLimit()) + " satellites · click to change"
            foreground: root.performanceColor()
            background: root.hudButtonBackground
            accent: Color.accent
            selected: root.performanceMenuOpen
            bordered: true
            onClicked: root.performanceMenuOpen = !root.performanceMenuOpen
          }

          Button {
            id: miniGlobeButton
            anchors.right: infoTrayButton.left
            anchors.rightMargin: root.controlGap
            anchors.verticalCenter: parent.verticalCenter
            width: root.hudButtonSize
            height: root.hudButtonSize
            iconText: ""
            iconSize: Style.font.icon * root.textScale
            tooltipText: root.miniGlobeOpen ? "Hide orbit globe" : "Show orbit globe"
            foreground: root.miniGlobeOpen ? Color.accent : root.foreground
            background: root.hudButtonBackground
            accent: Color.accent
            selected: root.miniGlobeOpen
            bordered: true
            onClicked: root.miniGlobeOpen = !root.miniGlobeOpen
          }

          Button {
            id: infoTrayButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: root.hudButtonSize
            height: root.hudButtonSize
            iconText: ""
            iconSize: Style.font.icon * root.textScale
            tooltipText: root.infoTrayOpen ? "Hide satellite list" : "Show satellite list"
            foreground: root.infoTrayOpen ? Color.accent : root.foreground
            background: root.hudButtonBackground
            accent: Color.accent
            selected: root.infoTrayOpen
            bordered: true
            onClicked: root.infoTrayOpen = !root.infoTrayOpen
          }
        }

        Rectangle {
          id: performanceMenu
          parent: radarBody
          x: mapToolbar.x + mapToolbar.width - width
          y: mapToolbar.y + mapToolbar.height + root.controlGap
          width: Math.min(Style.space(260), radarBody.width - root.hudInset * 2)
          height: root.performanceMenuOpen
            ? performanceMenuContent.implicitHeight + root.controlGap * 2 : 0
          opacity: root.performanceMenuOpen ? 1 : 0
          z: 60
          clip: true
          radius: Style.cornerRadius * 1.5
          color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.9)
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)

          Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
          Behavior on opacity { NumberAnimation { duration: 120 } }

          Column {
            id: performanceMenuContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root.controlGap
            spacing: root.controlGap

            Repeater {
              model: ["Balanced", "High", "Maximum", "Global"]
              delegate: Button {
                required property var modelData
                width: performanceMenuContent.width
                height: root.hudButtonSize
                text: String(modelData) + "  ·  "
                  + (String(modelData) === "Global" ? "all except Starlink"
                    : "up to " + root.performanceLimitFor(String(modelData)))
                leftAlign: true
                horizontalPadding: Style.space(9)
                fontSize: Style.font.bodySmall * root.textScale
                foreground: root.performanceColorFor(String(modelData))
                background: root.hudButtonBackground
                accent: Color.accent
                selected: root.performanceMode === String(modelData)
                bordered: true
                onClicked: root.setPerformanceMode(String(modelData))
              }
            }
          }
        }

        Rectangle {
          id: searchTray
          parent: radarBody
          x: mapToolbar.x + searchTrayButton.x + searchTrayButton.width + root.controlGap
          y: mapToolbar.y
          width: Math.max(0, mapToolbar.x + performanceButton.x - x - root.controlGap)
          height: root.searchTrayOpen ? searchContent.implicitHeight : 0
          opacity: root.searchTrayOpen ? 1 : 0
          z: 40
          clip: true
          radius: Style.cornerRadius * 1.5
          color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.84)

          Behavior on height { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
          Behavior on opacity { NumberAnimation { duration: 130 } }

          Column {
            id: searchContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 0
            spacing: root.controlGap

          Row {
            id: locationSearchRow
            width: parent.width
            spacing: root.controlGap

          TextField {
            id: manualLocationField
            width: parent.width - resetLocationButton.width - parent.spacing
            height: Style.space(34)
            enabled: !root.resolvingManualLocation
            placeholderText: root.resolvingManualLocation
              ? "Finding location…"
              : "City or latitude, longitude — press Enter"
            foreground: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body * root.textScale
            horizontalPadding: Style.space(14)
            verticalPadding: Style.space(4)
            onTextChanged: geocodeDebounce.restart()

            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Down && root.locationSuggestions.length > 0) {
                root.suggestionIndex = Math.min(root.locationSuggestions.length - 1, root.suggestionIndex + 1)
                event.accepted = true
              } else if (event.key === Qt.Key_Up && root.locationSuggestions.length > 0) {
                root.suggestionIndex = Math.max(0, root.suggestionIndex - 1)
                event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                root.locationSuggestions = []
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (root.locationSuggestions.length > 0)
                  root.pickSuggestion(root.locationSuggestions[root.suggestionIndex])
                else
                  root.submitManualLocation(text)
                event.accepted = true
              }
            }
          }

          Button {
            id: resetLocationButton
            y: (locationSearchRow.height - height) / 2
            width: root.hudButtonSize
            height: root.hudButtonSize
            iconText: "󰑐"
            iconSize: Style.font.icon * root.textScale
            tooltipText: "Reset to automatic location"
            foreground: root.foreground
            background: root.hudButtonBackground
            accent: Color.accent
            bordered: true
            enabled: !autoLocationReset.running
            onClicked: {
              root.locationSuggestions = []
              manualLocationField.clear()
              root.useComputerLocation()
            }
          }
          }

          Column {
            visible: root.locationSuggestions.length > 0
            width: parent.width
            spacing: 0

            Repeater {
              model: root.locationSuggestions

              Rectangle {
                required property var modelData
                required property int index
                width: parent.width
                height: suggestionRow.implicitHeight + Style.space(12)
                radius: Style.cornerRadius
                color: index === root.suggestionIndex
                  ? Style.hoverFillFor(root.foreground, Color.accent)
                  : "transparent"

                Row {
                  id: suggestionRow
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(14)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(8)

                  Text {
                    text: modelData.name
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body * root.textScale
                  }
                  Text {
                    text: modelData.description
                    color: Color.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall * root.textScale
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onPositionChanged: root.suggestionIndex = index
                  onClicked: root.pickSuggestion(modelData)
                }
              }
            }
          }
        }
        }

        Item {
          id: radarBody
          visible: Number.isFinite(root.viewLat) && Number.isFinite(root.viewLon)
          anchors.horizontalCenter: parent.horizontalCenter
          width: parent.width + panel.padding * 2
          height: Math.round(width * 0.68) + Style.space(38) + panel.padding * 2
          transform: Translate { y: -panel.padding }

        Item {
          id: radarMap
          anchors.fill: parent
          clip: true
          property var hitTargets: []
          property int hitTargetCount: 0
          property var hoveredSatellite: null
          property real hoverX: 0
          property real hoverY: 0
          readonly property real centerOffsetX: -radarSidebar.width / 2
          readonly property real centerOffsetY: searchTray.height / 2
          readonly property var home: {
            var point = TileMath.projectToViewport(
              root.centreLat, root.centreLon, root.viewLat, root.viewLon,
              root.mapZoom, width, height)
            return { x: point.x + centerOffsetX, y: point.y + centerOffsetY }
          }
          onCenterOffsetXChanged: scope.requestPaint()
          onCenterOffsetYChanged: scope.requestPaint()

          Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.18)
            radius: 0

            TileLayer {
              anchors.fill: parent
              centerLatitude: root.viewLat
              centerLongitude: root.viewLon
              contentOffsetX: radarMap.centerOffsetX
              contentOffsetY: radarMap.centerOffsetY
              zoom: root.mapZoom
              tileUrlFor: function(zoom, x, y) {
                return "https://basemaps.cartocdn.com/" + root.basemapStyle + "/" + zoom + "/" + x + "/" + y + ".png"
              }
            }

            Rectangle {
              anchors.fill: parent
              color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b,
                root.darkTheme ? 0.11 : 0.08)
            }

            Canvas {
              id: scope
              anchors.fill: parent
              onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var targets = radarMap.hitTargets
                var targetCount = 0
                var cx = radarMap.home.x, cy = radarMap.home.y
                ctx.strokeStyle = Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.30)
                ctx.lineWidth = 1
                var ringsKm = [500, 1000]
                for (var ring = 0; ring < ringsKm.length; ++ring) {
                  var ringRadius = TileMath.kmToPixels(ringsKm[ring], root.centreLat, root.mapZoom)
                  ctx.beginPath(); ctx.arc(cx, cy, ringRadius, 0, Math.PI * 2); ctx.stroke()
                  if (ringRadius < width * 0.7) {
                    ctx.fillStyle = Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.72)
                    ctx.font = (9 * root.textScale) + "px " + root.fontFamily; ctx.textAlign = "left"; ctx.textBaseline = "bottom"
                    ctx.fillText(ringsKm[ring] + " km", cx + 4, cy - ringRadius + 12)
                  }
                }
                // Observer pulse sits behind the home glyph below.
                var pulseRadius = 11 + root.animationPhase * 7
                ctx.strokeStyle = Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.5 * (1 - root.animationPhase))
                ctx.lineWidth = 1.5; ctx.beginPath(); ctx.arc(cx, cy, pulseRadius, 0, Math.PI * 2); ctx.stroke()
                for (var i = 0; i < contacts.count; ++i) {
                  var sat = contacts.get(i)
                  if (!root.contactVisible(sat)) continue
                  var elapsed = Math.max(0, Math.min(10, (Date.now() - root.positionEpochMs) / 1000))
                  var interpolatedLatitude = Number(sat.latitude) + Number(sat.latitudeRate || 0) * elapsed
                  var interpolatedLongitude = Number(sat.longitude) + Number(sat.longitudeRate || 0) * elapsed
                  if (interpolatedLongitude > 180) interpolatedLongitude -= 360
                  if (interpolatedLongitude < -180) interpolatedLongitude += 360
                  var point = TileMath.projectToViewport(
                    interpolatedLatitude, interpolatedLongitude,
                    root.viewLat, root.viewLon, root.mapZoom, width, height)
                  var x = point.x + radarMap.centerOffsetX, y = point.y + radarMap.centerOffsetY
                  if (x < -10 || x > width + 10 || y < -10 || y > height + 10) continue
                  var dotRadius = root.satelliteRadius(sat.rangeKm)
                  var iconSize = Math.max(Style.space(8), dotRadius * 2.2)
                  var markerRadius = iconSize / 2
                  var isTrackedSatellite = Number(sat.noradId) === root.trackedNoradId
                  ctx.fillStyle = isTrackedSatellite
                    ? root.selectedSatelliteColor : root.satelliteColor(sat.category)
                  ctx.font = iconSize + "px " + root.fontFamily
                  ctx.textAlign = "left"
                  ctx.textBaseline = "alphabetic"
                  var iconOffset = root.satelliteIconOffset(sat.category, iconSize)
                  ctx.fillText(root.satelliteIcon(sat.category), x + iconOffset.x, y + iconOffset.y)
                  if (isTrackedSatellite) {
                    ctx.fillStyle = root.selectedSatelliteColor
                    // Derive the forward screen direction before drawing so
                    // the arrow can be placed first and the trail can begin
                    // beyond its tip.
                    var directionLatitude = interpolatedLatitude + Number(sat.latitudeRate || 0) * 2.5
                    var directionLongitude = interpolatedLongitude + Number(sat.longitudeRate || 0) * 2.5
                    directionLongitude = ((directionLongitude + 180) % 360 + 360) % 360 - 180
                    var directionPoint = TileMath.projectToViewport(
                      directionLatitude, directionLongitude,
                      root.viewLat, root.viewLon, root.mapZoom, width, height)
                    var arrowDx = directionPoint.x + radarMap.centerOffsetX - x
                    var arrowDy = directionPoint.y + radarMap.centerOffsetY - y
                    var arrowLength = Math.sqrt(arrowDx * arrowDx + arrowDy * arrowDy)
                    var trailStartDistance = 0
                    if (arrowLength > 0.1) {
                      var arrowUx = arrowDx / arrowLength, arrowUy = arrowDy / arrowLength
                      var arrowCenterX = 0, arrowCenterY = 0
                      var arrowPositionFound = false
                      for (var arrowAttempt = 0; arrowAttempt < 8; ++arrowAttempt) {
                        var arrowDistance = markerRadius + 14 + arrowAttempt * 10
                        arrowCenterX = x + arrowUx * arrowDistance
                        arrowCenterY = y + arrowUy * arrowDistance
                        if (arrowCenterX < 7 || arrowCenterX > width - 7
                            || arrowCenterY < 7 || arrowCenterY > height - 7) continue
                        var overlapsDot = false
                        for (var targetIndex = 0; targetIndex < radarMap.hitTargetCount; ++targetIndex) {
                          var otherTarget = targets[targetIndex]
                          if (Number(otherTarget.noradId) === Number(sat.noradId)) continue
                          var collisionDx = otherTarget.x - arrowCenterX
                          var collisionDy = otherTarget.y - arrowCenterY
                          var clearance = Number(otherTarget.radius || 3) + 7
                          if (collisionDx * collisionDx + collisionDy * collisionDy < clearance * clearance) {
                            overlapsDot = true
                            break
                          }
                        }
                        if (!overlapsDot) { arrowPositionFound = true; break }
                      }
                      if (arrowPositionFound) {
                        var arrowTipX = arrowCenterX + arrowUx * 4
                        var arrowTipY = arrowCenterY + arrowUy * 4
                        var arrowBaseX = arrowCenterX - arrowUx * 4
                        var arrowBaseY = arrowCenterY - arrowUy * 4
                        ctx.globalAlpha = 1
                        ctx.beginPath()
                        ctx.moveTo(arrowTipX, arrowTipY)
                        ctx.lineTo(arrowBaseX - arrowUy * 3.5, arrowBaseY + arrowUx * 3.5)
                        ctx.lineTo(arrowBaseX + arrowUy * 3.5, arrowBaseY - arrowUx * 3.5)
                        ctx.closePath(); ctx.fill()
                        trailStartDistance = arrowDistance + 10
                      }
                    }

                    // Project a lightweight one-minute dotted trail, starting
                    // only after the arrow so the two never overlap.
                    for (var trailStep = 1; trailStep <= 24; ++trailStep) {
                      var trailSeconds = trailStep * 2.5
                      var trailLatitude = interpolatedLatitude + Number(sat.latitudeRate || 0) * trailSeconds
                      var trailLongitude = interpolatedLongitude + Number(sat.longitudeRate || 0) * trailSeconds
                      trailLongitude = ((trailLongitude + 180) % 360 + 360) % 360 - 180
                      var trailPoint = TileMath.projectToViewport(
                        trailLatitude, trailLongitude,
                        root.viewLat, root.viewLon, root.mapZoom, width, height)
                      var trailX = trailPoint.x + radarMap.centerOffsetX
                      var trailY = trailPoint.y + radarMap.centerOffsetY
                      var trailDx = trailX - x, trailDy = trailY - y
                      if (Math.sqrt(trailDx * trailDx + trailDy * trailDy) <= trailStartDistance) continue
                      if (trailX < -4 || trailX > width + 4 || trailY < -4 || trailY > height + 4) continue
                      ctx.globalAlpha = 0.42 * (1 - trailStep / 27)
                      ctx.beginPath(); ctx.arc(trailX, trailY, 1.35, 0, Math.PI * 2); ctx.fill()
                    }
                    ctx.globalAlpha = 1
                    ctx.strokeStyle = root.selectedSatelliteColor
                    ctx.lineWidth = 2
                    ctx.beginPath(); ctx.arc(x, y, markerRadius + 4 + root.animationPhase * 2, 0, Math.PI * 2); ctx.stroke()
                  }
                  var target = targets[targetCount]
                  if (!target) { target = {}; targets.push(target) }
                  target.x = x; target.y = y
                  target.name = String(sat.name)
                  target.noradId = Number(sat.noradId)
                  target.category = String(sat.category)
                  target.azimuth = Number(sat.azimuth)
                  target.elevation = Number(sat.elevation)
                  target.rangeKm = Number(sat.rangeKm)
                  target.altitudeKm = Number(sat.altitudeKm)
                  target.radius = markerRadius
                  targetCount++
                }
                radarMap.hitTargetCount = targetCount
              }
            }

            Text {
              x: radarMap.home.x - width / 2
              y: radarMap.home.y - height / 2
              text: "󰋜"
              color: root.homeColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.title * root.textScale
              style: Text.Outline
              styleColor: root.darkTheme ? "#101014" : "#ffffff"
            }

            MouseArea {
              id: mapMouse
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton
              hoverEnabled: true
              cursorShape: pressed ? Qt.ClosedHandCursor
                : (radarMap.hoveredSatellite ? Qt.PointingHandCursor : Qt.OpenHandCursor)
              property real lastX: 0
              property real lastY: 0
              property bool dragged: false
              function updateHoveredSatellite(mouse) {
                radarMap.hoverX = mouse.x
                radarMap.hoverY = mouse.y
                var closest = null
                var closestDistance = 12 * 12
                for (var i = 0; i < radarMap.hitTargetCount; ++i) {
                  var target = radarMap.hitTargets[i]
                  var dx = target.x - mouse.x
                  var dy = target.y - mouse.y
                  var distance = dx * dx + dy * dy
                  if (distance <= closestDistance) {
                    closest = target
                    closestDistance = distance
                  }
                }
                radarMap.hoveredSatellite = closest
              }
              onPressed: function(mouse) {
                root.cancelMapFocus()
                root.performanceMenuOpen = false
                lastX = mouse.x
                lastY = mouse.y
                dragged = false
              }
              onClicked: function(mouse) {
                if (dragged) return
                updateHoveredSatellite(mouse)
                if (radarMap.hoveredSatellite)
                  root.trackSatellite(radarMap.hoveredSatellite.noradId)
              }
              onExited: radarMap.hoveredSatellite = null
              onDoubleClicked: function(mouse) {
                updateHoveredSatellite(mouse)
                if (radarMap.hoveredSatellite) {
                  root.trackSatellite(radarMap.hoveredSatellite.noradId)
                  return
                }
                root.setHomeFromMap(mouse.x - radarMap.centerOffsetX,
                  mouse.y - radarMap.centerOffsetY, width, height)
              }
              onPositionChanged: function(mouse) {
                if (!pressed) {
                  updateHoveredSatellite(mouse)
                  return
                }
                radarMap.hoveredSatellite = null
                var dx = mouse.x - lastX, dy = mouse.y - lastY
                if (dx === 0 && dy === 0) return
                dragged = true
                root.trackedNoradId = -1
                lastX = mouse.x; lastY = mouse.y
                var moved = TileMath.unprojectFromViewport(
                  width / 2 - dx, height / 2 - dy,
                  root.viewLat, root.viewLon, root.mapZoom, width, height)
                root.viewLat = Math.max(-75, Math.min(75, moved.latitude))
                root.viewLon = ((moved.longitude + 180) % 360 + 360) % 360 - 180
                root.mapPanned = true; scope.requestPaint()
              }
              onWheel: function(wheel) {
                var overInfoTray = root.infoTrayOpen && wheel.x >= radarSidebar.x
                var overSearchTray = root.searchTrayOpen
                  && wheel.x >= searchTray.x && wheel.x <= searchTray.x + searchTray.width
                  && wheel.y >= searchTray.y && wheel.y <= searchTray.y + searchTray.height
                if (overInfoTray || overSearchTray) {
                  wheel.accepted = true
                  return
                }
                root.cancelMapFocus()
                root.mapZoom = Math.max(2, Math.min(root.maxMapZoom, root.mapZoom + (wheel.angleDelta.y > 0 ? 1 : -1)))
                scope.requestPaint(); wheel.accepted = true
              }
            }

            Rectangle {
              id: satelliteTooltip
              visible: radarMap.hoveredSatellite !== null
              z: 20
              x: Math.max(Style.space(6), Math.min(radarMap.width - width - Style.space(6), radarMap.hoverX + Style.space(12)))
              y: Math.max(Style.space(6), Math.min(radarMap.height - height - Style.space(6), radarMap.hoverY - height - Style.space(10)))
              width: Style.space(180)
              height: tooltipContent.implicitHeight + Style.space(16)
              radius: Style.cornerRadius * 1.5
              color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.84)
              border.width: 0

              Column {
                id: tooltipContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(4)
                Text {
                  width: parent.width
                  text: radarMap.hoveredSatellite ? radarMap.hoveredSatellite.name : ""
                  color: "white"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body * root.textScale
                  font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  text: radarMap.hoveredSatellite
                    ? root.satelliteType(radarMap.hoveredSatellite.category)
                    : ""
                  color: radarMap.hoveredSatellite
                    ? root.satelliteColor(radarMap.hoveredSatellite.category) : "white"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall * root.textScale
                }
                Text {
                  text: radarMap.hoveredSatellite
                    ? "Direction  " + root.compassDirection(radarMap.hoveredSatellite.azimuth)
                      + "  " + Math.round(radarMap.hoveredSatellite.azimuth) + "°"
                    : ""
                  color: "#c7d0e8"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption * root.textScale
                }
                Text {
                  text: radarMap.hoveredSatellite
                    ? "Elevation  " + radarMap.hoveredSatellite.elevation.toFixed(1) + "°"
                    : ""
                  color: "#c7d0e8"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption * root.textScale
                }
                Text {
                  text: radarMap.hoveredSatellite
                    ? "Distance  " + Math.round(radarMap.hoveredSatellite.rangeKm) + " km"
                    : ""
                  color: "#c7d0e8"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption * root.textScale
                }
                Text {
                  text: radarMap.hoveredSatellite
                    ? "Altitude  " + Math.round(radarMap.hoveredSatellite.altitudeKm) + " km"
                    : ""
                  color: "#c7d0e8"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption * root.textScale
                }
              }
            }

            Column {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.leftMargin: root.hudInset
              anchors.topMargin: mapToolbar.y + mapToolbar.height + root.controlGap
              spacing: root.controlGap
              Button { width: root.hudButtonSize; height: root.hudButtonSize; text: "+"; fontSize: Style.font.icon * root.textScale; tooltipText: "Zoom in"; foreground: root.foreground; background: root.hudButtonBackground; accent: Color.accent; bordered: true; enabled: root.mapZoom < root.maxMapZoom; onClicked: { root.cancelMapFocus(); root.mapZoom = Math.min(root.maxMapZoom, Math.round(root.mapZoom) + 1); scope.requestPaint() } }
              Button { width: root.hudButtonSize; height: root.hudButtonSize; text: "−"; fontSize: Style.font.icon * root.textScale; tooltipText: "Zoom out"; foreground: root.foreground; background: root.hudButtonBackground; accent: Color.accent; bordered: true; onClicked: { root.cancelMapFocus(); root.mapZoom = Math.max(2, Math.round(root.mapZoom) - 1); scope.requestPaint() } }
            }

            Column {
              id: categoryFilters
              anchors.left: parent.left
              anchors.bottom: parent.bottom
              anchors.leftMargin: root.hudInset
              anchors.bottomMargin: root.hudInset
              spacing: root.controlGap
              z: 15

              Button { width: root.hudButtonSize; height: root.hudButtonSize; iconText: root.satelliteIcon("starlink"); iconSize: Style.font.icon * root.textScale; tooltipText: "Starlink satellites"; bordered: true; background: root.hudButtonBackground; accent: Color.accent; foreground: root.showStarlink ? root.satelliteColor("starlink") : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.32); onClicked: root.toggleCategory("starlink") }
              Button { width: root.hudButtonSize; height: root.hudButtonSize; iconText: root.satelliteIcon("navigation"); iconSize: Style.font.icon * root.textScale; tooltipText: "Navigation satellites"; bordered: true; background: root.hudButtonBackground; accent: Color.accent; foreground: root.showNavigation ? root.satelliteColor("navigation") : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.32); onClicked: root.toggleCategory("navigation") }
              Button { width: root.hudButtonSize; height: root.hudButtonSize; iconText: root.satelliteIcon("station"); iconSize: Style.font.icon * root.textScale; tooltipText: "Space stations"; bordered: true; background: root.hudButtonBackground; accent: Color.accent; foreground: root.showStation ? root.satelliteColor("station") : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.32); onClicked: root.toggleCategory("station") }
              Button { width: root.hudButtonSize; height: root.hudButtonSize; iconText: root.satelliteIcon("other"); iconSize: Style.font.icon * root.textScale; tooltipText: "Other satellites"; bordered: true; background: root.hudButtonBackground; accent: Color.accent; foreground: root.showOther ? root.satelliteColor("other") : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.32); onClicked: root.toggleCategory("other") }
            }

            MiniGlobe {
              id: miniGlobe
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.rightMargin: radarSidebar.width + root.hudInset
              anchors.bottomMargin: root.hudInset
              width: root.miniGlobeOpen ? Style.space(164) : 0
              height: width
              opacity: root.miniGlobeOpen ? 1 : 0
              enabled: root.miniGlobeOpen
              z: 18
              satellitesModel: contacts
              positionEpochMs: root.positionEpochMs
              trackedNoradId: root.trackedNoradId
              contactVisible: function(contact) { return root.contactVisible(contact) }
              categoryColor: function(category) { return root.satelliteColor(category) }
              onSatelliteSelected: function(noradId) { root.trackSatellite(noradId) }
              Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
              Behavior on opacity { NumberAnimation { duration: 140 } }
            }

          }
        }

        Rectangle {
          id: radarSidebar
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.topMargin: mapToolbar.y + mapToolbar.height + root.controlGap
          anchors.bottom: parent.bottom
          width: root.infoTrayOpen ? Style.space(280) : 0
          z: 30
          clip: true
          opacity: root.infoTrayOpen ? 1 : 0
          property real trayInset: Style.space(12)
          radius: 0
          topLeftRadius: Style.cornerRadius * 1.5
          bottomLeftRadius: Style.cornerRadius * 1.5
          color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.84)
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)

          Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
          Behavior on opacity { NumberAnimation { duration: 140 } }

          Column {
            id: radarSidebarContent
            anchors.fill: parent
            anchors.margins: radarSidebar.trayInset
            spacing: Style.space(8)

        Text {
          id: errorMessage
          visible: root.errorText !== ""
          width: parent.width
          text: root.errorText
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.body * root.textScale
          wrapMode: Text.WordWrap
        }

        ListView {
          id: satelliteList
          width: parent.width
          height: Math.max(Style.space(100), radarSidebarContent.height
            - (errorMessage.visible ? errorMessage.implicitHeight + radarSidebarContent.spacing : 0))
          clip: true
          model: filteredContacts
          spacing: Style.space(4)
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar {
            id: satelliteScrollBar
            width: Style.space(6)
            policy: ScrollBar.AlwaysOn
            active: true
            interactive: true
            minimumSize: 0.18
            opacity: 1

            contentItem: Rectangle {
              implicitWidth: Style.space(4)
              implicitHeight: Style.space(34)
              radius: width / 2
              color: Color.accent
              opacity: 1
              border.width: 0
            }

            background: Rectangle {
              radius: width / 2
              color: "transparent"
              border.width: 1
              border.color: Color.muted
              opacity: 0.18
            }
          }
          delegate: Rectangle {
            required property int noradId
            required property string name
            required property string category
            width: ListView.view.width - satelliteScrollBar.width - Style.space(5)
            height: satelliteName.implicitHeight + Style.space(8)
            radius: Style.cornerRadius
            color: noradId === root.trackedNoradId
              ? Style.selectionFillFor(root.foreground, root.satelliteColor(category))
              : (rowMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")

            Text {
              id: satelliteName
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              text: name
              elide: Text.ElideRight
              color: noradId === root.trackedNoradId
                ? root.selectedSatelliteColor : root.satelliteColor(category)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall * root.textScale
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.trackSatellite(noradId)
          }
        }
        }
        }
      }
        }
      }
    }
  }
}
