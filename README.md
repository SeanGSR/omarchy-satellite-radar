# Satellite Radar for Omarchy

A live satellite ground-track map and orbital overview for the Omarchy bar.
It tracks Starlink, navigation satellites, space stations, and other visual
satellites without opening an external website.

![Satellite Radar preview](preview.png)

## Features

- Live satellite positions calculated locally from current TLE orbital elements
- Theme-aware CARTO/OpenStreetMap ground-track map
- Searchable locations shared with the Omarchy Weather location
- Satellite selection, tracking, trajectory indicators, filters, and tooltips
- Draggable mini globe with altitude visualization and independent zoom
- Balanced (60), High (150), Maximum (300), and opt-in Global catalog modes
- Two-hour TLE cache and request backoff that respect the upstream data service
- Full keyboard navigation

## Install

```sh
omarchy plugin add https://github.com/SeanGSR/omarchy-satellite-radar.git --enable
```

The plugin is placed in the right section of the bar by default. It requires
the standard Omarchy environment plus `node`, `curl`, and `jq`. The small
`satellite.js` runtime is included with its MIT license, so no dependency
setup step is required.

## Usage

Click the satellite icon in the bar to open the map. Drag to pan and use the
wheel or `+`/`−` controls to zoom. Click a satellite on the map, in the list,
or on the mini globe to focus it. Any subsequent drag or wheel input returns
the camera to manual control.

The performance button offers:

- **Balanced:** up to 60 satellites
- **High:** up to 150 satellites
- **Maximum:** up to 300 satellites
- **Global:** every object in the supported catalogs; Starlink is hidden by
  default in this mode to reduce visual clutter

Global mode is intended for powerful computers and refreshes the full catalog
no more often than every 30 seconds.

## Keyboard navigation

- `↑` / `↓` or `K` / `J`: open and navigate the satellite list
- `←` / `→`: pan the map west or east
- `Enter` or `Space`: track the selected satellite
- `+` / `−`: zoom the map
- `S` or `/`: open location search
- `I`: toggle the satellite list
- `G`: toggle the mini globe
- `P`: open the performance menu; use `↑` / `↓` and `Enter`
- `R`: refresh satellite data
- `?`: show or hide the keyboard shortcut legend
- `C` or `0`: return to the radar location
- `1`–`4`: toggle Starlink, navigation satellites, stations, and other objects
- `Escape`: leave the active keyboard layer, then close the panel

## Configuration

Settings are available through Omarchy's bar configuration. For example:

```sh
omarchy bar set ldng.satellite-radar minimumElevation 10
omarchy bar set ldng.satellite-radar performanceMode High
```

Manual locations are stored through `omarchy-weather-location`, so Weather and
Satellite Radar use the same selected place. Double-clicking the map updates
that shared location.

## Network access and privacy

The plugin runs without elevated privileges. It contacts:

- [CelesTrak](https://celestrak.org/) for public TLE orbital elements
- [CARTO](https://carto.com/) for map tiles using OpenStreetMap data
- [Open-Meteo](https://open-meteo.com/) for city autocomplete
- [GeoJS](https://www.geojs.io/) only as a fallback for approximate IP location

TLE files are cached under `${XDG_CACHE_HOME:-~/.cache}/omarchy-satellite-radar`.
The fallback IP lookup necessarily reveals the public IP address to GeoJS.
Users can avoid it by setting a location through Omarchy Weather or the search
field before the fallback is needed.

Satellite positions are predictions derived from TLE snapshots, not live GPS
telemetry. This plugin is for casual visualization and is not suitable for
navigation or collision avoidance.

## Data refresh policy

Position propagation is performed locally. CelesTrak data is downloaded no
more than once every two hours per catalog group. Failed requests back off for
15 minutes and use stale cached data when available.

## Remove

```sh
omarchy plugin remove ldng.satellite-radar
```

Removal does not delete the optional TLE cache. It can be removed separately
from `~/.cache/omarchy-satellite-radar` if desired.

## License

Satellite Radar is licensed under the [MIT License](LICENSE). The vendored
`satellite.js` runtime is also MIT-licensed; its notice is included at
[`vendor/SATELLITE_JS_LICENSE.md`](vendor/SATELLITE_JS_LICENSE.md).

Map data © OpenStreetMap contributors. Map tiles © CARTO.
