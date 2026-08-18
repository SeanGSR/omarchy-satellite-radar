#!/usr/bin/env node

const fs = require("fs")
const os = require("os")
const path = require("path")
// Vendored to keep `omarchy plugin add` dependency-free. See
// vendor/SATELLITE_JS_LICENSE.md for the upstream MIT license.
const satellite = require("./vendor/satellite.min.js")

const latitude = Number(process.argv[2])
const longitude = Number(process.argv[3])
const minimumElevation = Math.max(0, Math.min(80, Number(process.argv[4]) || 0))
const mode = process.argv[5] === "starlink" ? "starlink" : "core"
const performanceMode = ["balanced", "high", "maximum", "global"].includes(process.argv[6])
  ? process.argv[6] : "balanced"
const groups = mode === "starlink"
  ? ["visual", "stations", "gps-ops", "galileo", "starlink"]
  : ["visual", "stations", "gps-ops", "galileo"]
const cacheDir = path.join(process.env.XDG_CACHE_HOME || path.join(os.homedir(), ".cache"), "omarchy-satellite-radar")
const GP_CACHE_MS = 2 * 60 * 60 * 1000
const FAILED_REQUEST_BACKOFF_MS = 15 * 60 * 1000
// Permanently show the two currently independent operational orbital
// stations. Docked modules and visiting cargo/crew vehicles are intentionally
// not pinned as separate stations.
const ALWAYS_INCLUDED_NORAD_IDS = new Set([
  25544, // International Space Station (international partnership)
  48274  // Tiangong / CSS Tianhe core module (China)
])

function output(value) {
  process.stdout.write(JSON.stringify(value))
}

function shortName(name) {
  return String(name).replace(/^STARLINK-/i, "SL-").replace(/\s+/g, " ").slice(0, 14)
}

async function tleForGroup(group) {
  fs.mkdirSync(cacheDir, { recursive: true })
  const file = path.join(cacheDir, `${group}.tle`)
  const attemptFile = path.join(cacheDir, `${group}.last-attempt`)
  let cachedText = null
  try {
    const stat = fs.statSync(file)
    cachedText = fs.readFileSync(file, "utf8")
    if (Date.now() - stat.mtimeMs < GP_CACHE_MS) return cachedText
  } catch (_) {}

  // Avoid hammering CelesTrak after a timeout, block, or service failure. A
  // stale TLE is preferable to retrying on every local position update.
  try {
    const attempted = fs.statSync(attemptFile)
    if (cachedText && Date.now() - attempted.mtimeMs < FAILED_REQUEST_BACKOFF_MS) return cachedText
  } catch (_) {}

  fs.writeFileSync(attemptFile, new Date().toISOString())

  const url = `https://celestrak.org/NORAD/elements/gp.php?GROUP=${encodeURIComponent(group)}&FORMAT=tle`
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(20000), headers: { "User-Agent": "omarchy-satellite-radar/1.1 (personal desktop widget)" } })
    if (!response.ok) throw new Error(`Orbital data request failed (${response.status})`)
    const text = await response.text()
    if (!text.includes("\n1 ") || !text.includes("\n2 ")) throw new Error("Orbital data response was invalid")
    const temporary = `${file}.${process.pid}`
    fs.writeFileSync(temporary, text)
    fs.renameSync(temporary, file)
    return text
  } catch (error) {
    if (cachedText) return cachedText
    throw error
  }
}

function parseTle(text) {
  const lines = text.split(/\r?\n/).map(line => line.trim()).filter(Boolean)
  const rows = []
  for (let i = 0; i + 2 < lines.length; i += 3) {
    if (!lines[i + 1].startsWith("1 ") || !lines[i + 2].startsWith("2 ")) continue
    rows.push({ name: lines[i], line1: lines[i + 1], line2: lines[i + 2] })
  }
  return rows
}

async function main() {
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) throw new Error("Invalid observer location")
  const payloads = await Promise.all(groups.map(tleForGroup))
  const unique = new Map()
  for (let groupIndex = 0; groupIndex < payloads.length; groupIndex++) {
    const group = groups[groupIndex]
    for (const row of parseTle(payloads[groupIndex]))
      unique.set(row.line1.slice(2, 7).trim(), { ...row, group })
  }

  const now = new Date()
  const predictionSeconds = 5
  const future = new Date(now.getTime() + predictionSeconds * 1000)
  const observer = {
    latitude: satellite.degreesToRadians(latitude),
    longitude: satellite.degreesToRadians(longitude),
    height: 0
  }
  const gmst = satellite.gstime(now)
  const visible = []
  for (const [noradId, row] of unique) {
    try {
      const satrec = satellite.twoline2satrec(row.line1, row.line2)
      const propagated = satellite.propagate(satrec, now)
      if (!propagated.position || typeof propagated.position === "boolean") continue
      const ecf = satellite.eciToEcf(propagated.position, gmst)
      const ground = satellite.eciToGeodetic(propagated.position, gmst)
      const propagatedFuture = satellite.propagate(satrec, future)
      if (!propagatedFuture.position || typeof propagatedFuture.position === "boolean") continue
      const groundFuture = satellite.eciToGeodetic(propagatedFuture.position, satellite.gstime(future))
      const groundLatitude = satellite.radiansToDegrees(ground.latitude)
      const groundLongitude = satellite.radiansToDegrees(ground.longitude)
      const futureLatitude = satellite.radiansToDegrees(groundFuture.latitude)
      const futureLongitude = satellite.radiansToDegrees(groundFuture.longitude)
      var longitudeDelta = futureLongitude - groundLongitude
      if (longitudeDelta > 180) longitudeDelta -= 360
      if (longitudeDelta < -180) longitudeDelta += 360
      const look = satellite.ecfToLookAngles(observer, ecf)
      const elevation = satellite.radiansToDegrees(look.elevation)
      if (performanceMode !== "global" && elevation < minimumElevation
          && !ALWAYS_INCLUDED_NORAD_IDS.has(Number(noradId))) continue
      visible.push({
        noradId: Number(noradId),
        name: row.name,
        shortName: shortName(row.name),
        category: row.group === "starlink" || /STARLINK/i.test(row.name) ? "starlink"
          : (row.group === "gps-ops" || row.group === "galileo" || /GPS|GALILEO|GLONASS|BEIDOU/i.test(row.name) ? "navigation"
          : (row.group === "stations" ? "station" : "other")),
        azimuth: (satellite.radiansToDegrees(look.azimuth) + 360) % 360,
        elevation,
        rangeKm: look.rangeSat
        ,latitude: groundLatitude
        ,longitude: groundLongitude
        ,latitudeRate: (futureLatitude - groundLatitude) / predictionSeconds
        ,longitudeRate: longitudeDelta / predictionSeconds
        ,altitudeKm: ground.height
      })
    } catch (_) {}
  }
  visible.sort((a, b) => a.rangeKm - b.rangeKm)

  // Global mode intentionally skips observer-horizon filtering and local
  // display quotas. It is explicitly opt-in because rendering the complete
  // supported catalog is substantially more expensive.
  if (performanceMode === "global") {
    output({ timestamp: now.toISOString(), timestampMs: now.getTime(), catalogCount: unique.size,
      visibleTotal: visible.length, satellites: visible })
    return
  }

  // Keep Starlink's much larger constellation from crowding every other
  // category out of the rendered contacts. Any unused category slots are
  // filled with the next-closest satellite, then the final set is returned in
  // distance order so the nearest contact always stays at the top.
  const performanceProfiles = {
    balanced: { limit: 60, categories: { starlink: 36, navigation: 10, station: 6, other: 8 } },
    high: { limit: 150, categories: { starlink: 92, navigation: 24, station: 10, other: 24 } },
    maximum: { limit: 300, categories: { starlink: 190, navigation: 42, station: 16, other: 52 } }
  }
  const profile = performanceProfiles[performanceMode]
  const displayLimit = profile.limit
  const categoryLimits = profile.categories
  const categoryCounts = { starlink: 0, navigation: 0, station: 0, other: 0 }
  const selected = []
  const selectedIds = new Set()

  // Reserve permanent contacts before applying category quotas or distance
  // ordering, so operational stations remain available below the horizon.
  for (const contact of visible) {
    if (!ALWAYS_INCLUDED_NORAD_IDS.has(contact.noradId)) continue
    selected.push(contact)
    selectedIds.add(contact.noradId)
    categoryCounts[contact.category]++
  }

  for (const contact of visible) {
    if (selectedIds.has(contact.noradId)) continue
    const category = categoryLimits[contact.category] === undefined ? "other" : contact.category
    if (categoryCounts[category] >= categoryLimits[category]) continue
    selected.push(contact)
    selectedIds.add(contact.noradId)
    categoryCounts[category]++
  }
  for (const contact of visible) {
    if (selected.length >= displayLimit) break
    if (selectedIds.has(contact.noradId)) continue
    selected.push(contact)
    selectedIds.add(contact.noradId)
  }
  selected.sort((a, b) => a.rangeKm - b.rangeKm)

  output({ timestamp: now.toISOString(), timestampMs: now.getTime(), catalogCount: unique.size, visibleTotal: visible.length, satellites: selected.slice(0, displayLimit) })
}

main().catch(error => output({ error: String(error.message || error) }))
