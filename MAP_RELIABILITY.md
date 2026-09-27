# Map Reliability

## v40 regression review
The map regressed after repeated UI passes even though the app continued to deploy.

Observed engineering causes:
- styles.css had successive v28-v33 patches redefining the map stage, HUD, bottom stack and docked states with conflicting important rules.
- sw.js still used the v33 cache name while application files had advanced through v39, allowing an installed PWA to fall back to an old shell when network requests failed.
- MapLibre resize calls were tied to renders and toggles rather than the actual container size. iOS viewport and docking changes could therefore leave the WebGL canvas at stale dimensions.
- MapLibre assets and the OpenFreeMap style are remote runtime dependencies. A successful Vercel build alone does not prove the map loaded on the phone.

v40 changes:
- Replaced accumulated CSS patches with one canonical map shell and design system.
- Bumped the PWA cache to v40.
- Added ResizeObserver to the map container plus immediate and delayed resize calls.
- Map is absolute inset zero inside the live viewport; overlays no longer determine its geometry.
- HUD stacks pass pointer events through except on controls.

## Required map invariants
- radarMap always has non-zero width and height.
- radar-stage owns map geometry.
- Do not append version-specific CSS patches to repair map layout; edit canonical rules.
- Live-shell changes require a service-worker cache bump.
- Do not replace control SVG contents with textContent.
- Vercel READY is only deployment verification; the map still needs an on-device smoke test.
- Map controls stay at least 48px and respect iOS safe areas.
- Radar remains usable if the map provider has a runtime problem.

## Deployment audit
The recent Vercel deployment pages inspected during v40 contained no failed deployment. The known historical v19 failure was the Vercel Hobby serverless-function-count limit; it remains an architectural constraint but did not cause this map regression.


## v44 shell-state guard
- HUD expand/collapse may only toggle classes and aria-expanded. Never assign textContent to the HUD button because that deletes the generated map-art span.
- The live map now launches expanded; docking is an explicit rider action rather than the default state.
- Production generated assets are part of the service-worker shell cache so installed iPhone PWAs do not mix new DOM/CSS with stale icon frames.
- v44 also repaired the planner function boundary found during integration; a malformed refreshLearning/refreshStartPlan seam could prevent application JavaScript from parsing and therefore make the map appear broken even when MapLibre itself was healthy.


## v45 rider-facing map invariants
- Restaurant popups describe a nearby restaurant; internal catalog labels such as “Culver merchant inventory” are prohibited in rider-facing UI.
- A WAIT AT marker is a staging recommendation, not a prediction that Uber will dispatch from that exact restaurant.
- The displayed target uses the exact waitAt coordinates when available and preserves the pocket as supporting context.
- Explicit scans may animate planner state; periodic refreshes may not make the recommendation flicker between SCANNING and READY.
