// weather.json holds {"name": ..., "latitude": ..., "longitude": ...}, owned
// by omarchy-weather-location. Reused here as the scope's center point
// instead of asking for a location a second time.
function parseLocationFile(raw) {
  var unset = { latitude: NaN, longitude: NaN }
  try {
    var data = JSON.parse(String(raw || ""))
    if (!data || typeof data !== "object") return unset
    var latitude = parseFloat(data.latitude)
    var longitude = parseFloat(data.longitude)
    if (isNaN(latitude) || isNaN(longitude)) return unset
    return { latitude: latitude, longitude: longitude }
  } catch (e) {
    return unset
  }
}

// adsb.lol's point-query response: {"ac": [...]}, each contact already
// carrying `dst`/`dir` (great-circle distance in nm and bearing in degrees
// from the query point) — adsb.lol computes those server-side, so the panel
// never needs its own haversine math. `count` is every reported contact
// (for the ambient bar text); `aircraft` is the subset with a resolved
// dst/dir, sorted closest-first, for plotting on the radar — a contact can
// be in the first and not the second if adsb.lol hasn't pinned its position
// yet. count: -1 signals "couldn't parse" so the pill can show a distinct
// "unknown" state from "zero nearby".
function parseAdsbResponse(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    var list = Array.isArray(data.ac) ? data.ac : []
    var aircraft = []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i] || {}
      var distanceNm = Number(entry.dst)
      var bearingDeg = Number(entry.dir)
      if (!isFinite(distanceNm) || !isFinite(bearingDeg)) continue
      var altBaro = entry.alt_baro
      aircraft.push({
        hex: String(entry.hex || ""),
        callsign: String(entry.flight || "").trim() || String(entry.hex || "").toUpperCase(),
        onGround: altBaro === "ground",
        altitude: typeof altBaro === "number" ? altBaro : 0,
        groundSpeed: Number(entry.gs) || 0,
        track: isFinite(Number(entry.track)) ? Number(entry.track) : 0,
        distanceNm: distanceNm,
        bearingDeg: bearingDeg
      })
    }
    aircraft.sort(function(a, b) { return a.distanceNm - b.distanceNm })
    return { count: list.length, aircraft: aircraft }
  } catch (e) {
    return { count: -1, aircraft: [] }
  }
}
