import QtQuick
import "TileMath.js" as TileMath

Item {
  id: root
  property real centerLatitude: 0
  property real centerLongitude: 0
  property real zoom: 11
  property int sourceZoom: Math.round(zoom)
  property real contentOffsetX: 0
  property real contentOffsetY: 0
  property var tileUrlFor: null
  property int revision: 0
  property int tileSize: 256
  readonly property real sourceScale: Math.pow(2, zoom - sourceZoom)
  signal tileFailed()
  clip: true

  readonly property var layout: TileMath.viewportTiles(
    centerLatitude, centerLongitude, sourceZoom,
    Math.max(1, width / sourceScale), Math.max(1, height / sourceScale))

  readonly property var tiles: {
    var list = []
    var view = layout
    if (!view || width <= 0 || height <= 0) return list
    var unused = revision
    for (var y = view.minY; y <= view.maxY; ++y) {
      if (!TileMath.isValidTileY(y, sourceZoom)) continue
      for (var x = view.minX; x <= view.maxX; ++x) {
        list.push({
          tileX: TileMath.wrapTileX(x, sourceZoom),
          tileY: y,
          screenX: (view.originX + (x - view.minX) * root.tileSize) * root.sourceScale,
          screenY: (view.originY + (y - view.minY) * root.tileSize) * root.sourceScale
        })
      }
    }
    return list
  }

  Repeater {
    model: root.tiles
    Image {
      required property var modelData
      x: modelData.screenX + root.contentOffsetX
      y: modelData.screenY + root.contentOffsetY
      width: root.tileSize * root.sourceScale
      height: root.tileSize * root.sourceScale
      source: root.tileUrlFor ? root.tileUrlFor(root.sourceZoom, modelData.tileX, modelData.tileY) : ""
      asynchronous: true
      cache: true
      smooth: true
      fillMode: Image.Stretch
      visible: status === Image.Ready
      onStatusChanged: if (status === Image.Error) root.tileFailed()
    }
  }
}
