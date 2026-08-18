.pragma library

var TILE_SIZE = 256
var MAX_LATITUDE = 85.0511287798
var EQUATOR_METERS_PER_PIXEL = 156543.03392804097

function clampLatitude(latitude) {
  return Math.max(-MAX_LATITUDE, Math.min(MAX_LATITUDE, latitude))
}

function lonToTileX(longitude, zoom) {
  return (longitude + 180) / 360 * Math.pow(2, zoom)
}

function latToTileY(latitude, zoom) {
  var radians = clampLatitude(latitude) * Math.PI / 180
  var projected = Math.log(Math.tan(radians) + 1 / Math.cos(radians))
  return (1 - projected / Math.PI) / 2 * Math.pow(2, zoom)
}

function metersPerPixel(latitude, zoom) {
  return EQUATOR_METERS_PER_PIXEL * Math.cos(clampLatitude(latitude) * Math.PI / 180) / Math.pow(2, zoom)
}

function kmToPixels(kilometers, latitude, zoom) {
  return kilometers * 1000 / metersPerPixel(latitude, zoom)
}

function tileXToLon(x, zoom) {
  return x / Math.pow(2, zoom) * 360 - 180
}

function tileYToLat(y, zoom) {
  var n = Math.PI * (1 - 2 * y / Math.pow(2, zoom))
  return Math.atan(Math.sinh(n)) * 180 / Math.PI
}

function projectToViewport(latitude, longitude, centerLatitude, centerLongitude, zoom, width, height) {
  return {
    x: width / 2 + (lonToTileX(longitude, zoom) - lonToTileX(centerLongitude, zoom)) * TILE_SIZE,
    y: height / 2 + (latToTileY(latitude, zoom) - latToTileY(centerLatitude, zoom)) * TILE_SIZE
  }
}

function unprojectFromViewport(x, y, centerLatitude, centerLongitude, zoom, width, height) {
  var tileX = lonToTileX(centerLongitude, zoom) + (x - width / 2) / TILE_SIZE
  var tileY = latToTileY(centerLatitude, zoom) + (y - height / 2) / TILE_SIZE
  return { latitude: tileYToLat(tileY, zoom), longitude: tileXToLon(tileX, zoom) }
}

function viewportTiles(latitude, longitude, zoom, width, height) {
  var centerX = lonToTileX(longitude, zoom)
  var centerY = latToTileY(latitude, zoom)
  var minX = Math.floor(centerX - width / 2 / TILE_SIZE)
  var maxX = Math.ceil(centerX + width / 2 / TILE_SIZE) - 1
  var minY = Math.floor(centerY - height / 2 / TILE_SIZE)
  var maxY = Math.ceil(centerY + height / 2 / TILE_SIZE) - 1
  return {
    minX: minX,
    maxX: maxX,
    minY: minY,
    maxY: maxY,
    originX: width / 2 - (centerX - minX) * TILE_SIZE,
    originY: height / 2 - (centerY - minY) * TILE_SIZE
  }
}

function wrapTileX(x, zoom) {
  var count = Math.pow(2, zoom)
  return ((x % count) + count) % count
}

function isValidTileY(y, zoom) {
  return y >= 0 && y < Math.pow(2, zoom)
}
