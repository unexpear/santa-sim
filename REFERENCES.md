# References

## God's Eye View (github.com/bilawalsidhu/gods-eye-view), checked Oct 20 2026
- What it is: a browser 3D globe of live public data (flights, ships, satellites, weather, cameras). About 58k stars, MIT license.
- Stack: vanilla JS + CesiumJS + Vite, with a Node server for API keys. No game engine.
- Map: keyless Esri satellite + terrain + OSM. Google Photorealistic 3D cities need a Cesium ion token (personal, NON-COMMERCIAL use only) or a metered Google Maps key.
Worth borrowing for Santa Sim:
- Globe-to-street camera: "cockpit mode" rides an aircraft from orbit down to the ground with terrain held underneath. That's our zoom from the globe into a town.
- Smooth motion from sparse data (interpolation, dead reckoning): useful for showing Santa's route on the globe.
- OSRM street routing (keyless, on OpenStreetMap): could power route planning previews.
- Keyless real wind data (NOAA GFS / ECMWF): real-world wind on Christmas Eve could push the sleigh.
- Sensor/visual style switching (night vision, FLIR): a "Santa vision" night mode idea.
Not a fit:
- Photoreal Google tiles: non-commercial terms, and they clash with the Hello Neighbor art.
- Its code is web JS, not portable into Godot. MIT means ideas and code may be reused with attribution.
Prototype option: a quick CesiumJS web mockup of the globe planning screen, separate from the Godot gameplay build.
