extends RefCounted
## Sun and moon positions (low-precision astronomy, ~0.01 deg sun / ~0.5 deg moon) for a place and
## a UTC time, and the world direction they shine from.
## WORLD AXES (shared with scripts/world/geo.gd and the town scene): +X = east, -Z = north, +Y = up.
## Azimuth is degrees clockwise from true north (90 = east, 180 = south, 270 = west).
## Sun: NOAA solar position algorithm (Meeus). Moon: Schlyter's orbital elements + the main
## perturbation terms; phase from the true Sun-Moon geometry.


static func julian_day(y: int, mo: int, d: int, hour_utc: float) -> float:
	if mo <= 2:
		y -= 1
		mo += 12
	var a := floori(y / 100.0)
	var b := 2 - a + floori(a / 4.0)
	return floor(365.25 * (y + 4716)) + floor(30.6001 * (mo + 1)) + d + b - 1524.5 + hour_utc / 24.0


## World direction toward a body at altitude/azimuth (degrees).
static func dir_from(alt_deg: float, az_deg: float) -> Vector3:
	var a := deg_to_rad(alt_deg)
	var z := deg_to_rad(az_deg)
	return Vector3(cos(a) * sin(z), sin(a), -cos(a) * cos(z))


static func _gmst_deg(jd: float) -> float:
	var t := (jd - 2451545.0) / 36525.0
	return fposmod(280.46061837 + 360.98564736629 * (jd - 2451545.0) + t * t * (0.000387933 - t / 38710000.0), 360.0)


## Equatorial (ra, dec in degrees) -> {alt, az} for lat/lon at jd.
static func _altaz(ra: float, dec: float, jd: float, lat: float, lon: float) -> Dictionary:
	var ha := deg_to_rad(fposmod(_gmst_deg(jd) + lon - ra, 360.0))
	var phi := deg_to_rad(lat)
	var de := deg_to_rad(dec)
	var alt := asin(sin(phi) * sin(de) + cos(phi) * cos(de) * cos(ha))
	var az := atan2(sin(ha), cos(ha) * sin(phi) - tan(de) * cos(phi))
	return {"alt": rad_to_deg(alt), "az": fposmod(rad_to_deg(az) + 180.0, 360.0)}


## {alt, az, ra, dec, lon_ecl} of the Sun.
static func sun(jd: float, lat: float, lon: float) -> Dictionary:
	var t := (jd - 2451545.0) / 36525.0
	var l0 := fposmod(280.46646 + t * (36000.76983 + t * 0.0003032), 360.0)
	var m := deg_to_rad(357.52911 + t * (35999.05029 - 0.0001537 * t))
	var c := sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t)) + sin(2.0 * m) * (0.019993 - 0.000101 * t) + sin(3.0 * m) * 0.000289
	var om := deg_to_rad(125.04 - 1934.136 * t)
	var lam := deg_to_rad(l0 + c - 0.00569 - 0.00478 * sin(om))
	var eps := deg_to_rad(23.0 + (26.0 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60.0) / 60.0 + 0.00256 * cos(om))
	var dec := rad_to_deg(asin(sin(eps) * sin(lam)))
	var ra := fposmod(rad_to_deg(atan2(cos(eps) * sin(lam), cos(lam))), 360.0)
	var r := _altaz(ra, dec, jd, lat, lon)
	r.ra = ra
	r.dec = dec
	r.lon_ecl = rad_to_deg(lam)
	return r


## {alt, az, illum (0..1), waxing} of the Moon (geocentric + a parallax correction on altitude).
static func moon(jd: float, lat: float, lon: float) -> Dictionary:
	var d := jd - 2451543.5
	var n := deg_to_rad(125.1228 - 0.0529538083 * d)
	var inc := deg_to_rad(5.1454)
	var w := deg_to_rad(318.0634 + 0.1643573223 * d)
	var e := 0.0549
	var mm := deg_to_rad(fposmod(115.3654 + 13.0649929509 * d, 360.0))
	var ee := mm + e * sin(mm) * (1.0 + e * cos(mm))
	for i in 3:
		ee = ee - (ee - e * sin(ee) - mm) / (1.0 - e * cos(ee))
	var xv := 60.2666 * (cos(ee) - e)
	var yv := 60.2666 * sqrt(1.0 - e * e) * sin(ee)
	var v := atan2(yv, xv)
	var r := sqrt(xv * xv + yv * yv)
	var xh := r * (cos(n) * cos(v + w) - sin(n) * sin(v + w) * cos(inc))
	var yh := r * (sin(n) * cos(v + w) + cos(n) * sin(v + w) * cos(inc))
	var zh := r * (sin(v + w) * sin(inc))
	var lonm := rad_to_deg(atan2(yh, xh))
	var latm := rad_to_deg(atan2(zh, sqrt(xh * xh + yh * yh)))
	# main perturbations
	var ms := deg_to_rad(356.0470 + 0.9856002585 * d)
	var ls := ms + deg_to_rad(282.9404 + 4.70935e-5 * d)
	var lm := mm + w + n
	var dd := lm - ls
	var f := lm - n
	lonm += -1.274 * sin(mm - 2.0 * dd) + 0.658 * sin(2.0 * dd) - 0.186 * sin(ms) - 0.059 * sin(2.0 * mm - 2.0 * dd) \
		- 0.057 * sin(mm - 2.0 * dd + ms) + 0.053 * sin(mm + 2.0 * dd) + 0.046 * sin(2.0 * dd - ms) + 0.041 * sin(mm - ms) \
		- 0.035 * sin(dd) - 0.031 * sin(mm + ms) - 0.015 * sin(2.0 * f - 2.0 * dd) + 0.011 * sin(mm - 4.0 * dd)
	latm += -0.173 * sin(f - 2.0 * dd) - 0.055 * sin(mm - f - 2.0 * dd) - 0.046 * sin(mm + f - 2.0 * dd) + 0.033 * sin(f + 2.0 * dd) + 0.017 * sin(2.0 * mm + f)
	var ecl := deg_to_rad(23.4393 - 3.563e-7 * d)
	var lo := deg_to_rad(lonm)
	var la := deg_to_rad(latm)
	var xe := cos(lo) * cos(la)
	var ye := sin(lo) * cos(la) * cos(ecl) - sin(la) * sin(ecl)
	var ze := sin(lo) * cos(la) * sin(ecl) + sin(la) * cos(ecl)
	var ra := fposmod(rad_to_deg(atan2(ye, xe)), 360.0)
	var dec := rad_to_deg(atan2(ze, sqrt(xe * xe + ye * ye)))
	var out := _altaz(ra, dec, jd, lat, lon)
	out.alt -= rad_to_deg(asin(1.0 / 60.2666)) * cos(deg_to_rad(out.alt))  # topocentric parallax (~0.95 deg)
	var s := sun(jd, lat, lon)
	var elong := fposmod(lonm - float(s.lon_ecl), 360.0)
	out.illum = (1.0 - cos(deg_to_rad(elong))) * 0.5
	out.waxing = elong < 180.0
	return out


## Local clock hour on the delivery night -> Julian day. The night runs from the afternoon of
## Dec 24 into the morning of Dec 25 (hours < 12 are on the 25th).
static func jd_for_local_hour(h: float, year: int, utc_offset: float) -> float:
	var day := 24 if h >= 12.0 else 25
	return julian_day(year, 12, day, h - utc_offset)


## Local hour (on the delivery night) when the Sun crosses altitude alt (-0.833 = sunset/rise
## with refraction): setting = true searches the evening, else the morning.
static func sun_cross_hour(lat: float, lon: float, year: int, utc_offset: float, setting: bool, alt := -0.833) -> float:
	var h0 := 16.0 if setting else 3.0
	var prev := float(sun(jd_for_local_hour(h0, year, utc_offset), lat, lon).alt) - alt
	var step := 1.0 / 60.0
	var h := h0
	while h < h0 + 6.0:
		var nh := h + step
		var cur := float(sun(jd_for_local_hour(fposmod(nh, 24.0), year, utc_offset), lat, lon).alt) - alt
		if (prev > 0.0) != (cur > 0.0):
			return fposmod(h + step * prev / (prev - cur), 24.0)
		prev = cur
		h = nh
	return h0
