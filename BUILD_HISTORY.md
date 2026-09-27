# Courier Radar — Build History

This file is append-only. Every major implementation pass must add an entry describing what actually landed in code and any known gaps.

## v1 — Culver Intelligence foundation
**Status: implemented in code**

- Objective is expected dollars per online hour subject to a target utilization of at least 80%.
- Reference active job duration is 17.5 minutes; initial idle budget is 4.375 minutes (4:23).
- Culver restaurant-pocket scan is available on demand with a visible scanning state.
- Recommended pocket persists and exposes a WHY THIS POCKET evidence panel.
- Recommended relocation target is pinned on the MapLibre map.
- Apple Maps and Google Maps routing are available from Radar.
- Full coordinate-backed restaurant results returned by the planner render as a clustered map layer.
- Personal Radar offer/completion/payout history, OSM density, optional BestTime and Ticketmaster event evidence contribute to pocket ranking.
- Active-delivery UI remains distinct from repositioning state.

## v2 — Restaurant database + exact staging target
**Status: implemented in code; catalog fills on successful production scan**

- Added Supabase `restaurant_merchants` catalog with stable OSM ID, name, coordinates, amenity, cuisine, address, phone, website, hours, delivery/takeaway metadata and freshness timestamps.
- Culver discovery uses a fixed operating-region bounding box rather than depending on the rider's current location.
- OSM-discovered merchants are persisted to Supabase.
- When OSM is unavailable, planner falls back to the persisted Supabase catalog instead of losing restaurant intelligence.
- Every candidate pocket ranks nearby restaurants and exposes `waitAt`, `nearbyRestaurantCount`, and top restaurant alternatives.
- Exact WAIT AT restaurant coordinates replace the generic pocket centroid for the relocation pin and Apple/Google routing.
- Merchant recommendation is explicitly a staging/gateway recommendation, not a claim that Uber will dispatch from that merchant.

## v3 — Gateway intelligence + utilization-triggered relocation
**Status: implemented in code, learning quality improves with captured history**

- Restaurant gateway score combines pocket centrality, time-block fit, historical offers, completed deliveries and historical payout.
- Pocket score retains external density/activity, personal history, event influence, locality and confidence.
- Legacy 8-minute STAY / 15-minute MOVE rules were removed from the primary recommendation path.
- Reposition state now uses the 80% utilization idle budget: early budget = STAY, approaching budget = PREPARE, exhausted budget = MOVE.
- Reposition travel is explicitly treated as idle cost in the recommendation.
- UI shows whether restaurant inventory came from live OSM or the Supabase cache.
- Database cache makes free OSM/Overpass a discovery/refresh source rather than a required always-on runtime dependency.

## Non-negotiable invariants
- Never silently revert to the old 8/15-minute heuristic.
- Never hide a selected recommendation after tapping it.
- Never route to a pocket centroid when a valid WAIT AT merchant coordinate exists.
- Never claim the persistent merchant catalog is populated until Supabase actually contains rows.
- Keep serverless function count within Vercel Hobby limits by extending existing endpoints.
- Append every major future build to this file.


## v4 — Arrival hazard + auditable activity forecast
**Status: implemented in code; estimates intentionally start conservative and improve with Radar exposure**

- Candidate pockets now estimate qualified-offer arrival rate rather than treating raw restaurant density as order demand.
- Qualified offers use a minimum effective $/hour gate so low-value pings do not falsely make a pocket look productive.
- Sparse history is smoothed with a prior instead of producing unstable zero/infinite estimates.
- Every pocket exposes expected wait minutes, probability of a qualified opportunity within five minutes, predicted utilization, qualified-offer count and estimated arrivals per available hour.
- WHY THIS POCKET surfaces wait, next-five-minute probability and predicted active percentage alongside restaurant and historical evidence.
- Recommendation audit records now retain these forecast inputs plus the exact WAIT AT restaurant so later outcomes can be compared with the recommendation.
- v1 map/routing/pocket behavior, v2 persistent merchant database/exact staging target, and v3 utilization-budget relocation remain active.


## v5 — Closed-loop recommendation learning
**Status: implemented outcome reconciliation; ranking feedback integration remains guarded until enough evaluated samples exist**

- Recommendation logs now store observed outcome timing, whether a qualified offer arrived, payout, matched offer ID, estimated opportunity-profit delta and calibration error.
- Reading recommendation history reconciles mature predictions against subsequent captured offers in a fixed observation window.
- Learning summary reports evaluated recommendations, qualified outcomes, observed wait, cumulative opportunity-profit delta and Brier calibration score.
- The Stats opportunity-money surface now uses the recommendation-learning profit metric when available instead of leaving predictions unaudited.
- Audit evidence records baseline expected payout so future profit lift can compare recommendation outcome against the decision-time baseline.
- This closes the prediction -> action -> observed outcome -> calibration dataset loop without inventing causality from unevaluated recommendations.
- Existing skip-counterfactual Radar Advantage remains a separate metric: it estimates money gained/lost from SKIP decisions, while recommendation opportunity-profit measures post-reposition/zone recommendations.
- v1-v4 invariants remain required.


## v6 / UI v40 — Native shell + map reliability reset
**Status: implemented; on-device smoke test required**

- Replaced years-of-patch style accumulation with a single tokenized YA Creative design system.
- Rebuilt the live screen around a fixed native-style map viewport, disciplined glass HUD surfaces, consistent 48px controls, iOS safe areas and a four-destination floating tab bar.
- Replaced generic Unicode navigation/location/map glyphs with custom authored SVG line icons.
- Added DESIGN_SYSTEM.md as the canonical component, spacing, icon and CSS maintenance contract.
- Added MAP_RELIABILITY.md documenting the map regression causes and required invariants.
- Added ResizeObserver-based MapLibre canvas sizing so iOS viewport/HUD changes resize the WebGL canvas from actual container geometry.
- Bumped the service-worker shell from v33 to v40 to invalidate stale installed-PWA assets.
- Fixed HUD behavior so JavaScript changes state/ARIA without destroying the authored SVG icon DOM.
- Recent Vercel deployment history inspected during this pass showed no current failed deployment; the historical Hobby function-count failure remains documented separately.
- Intelligence v1-v5 remains in place; this pass changes presentation/reliability rather than deleting scoring behavior.


## v7 / UI v41 — Motion system + map dependency repair
**Status: implemented; requires iPhone smoke test**

- Audited the actual v40 iPhone screenshot. It violated the design contract by stacking Scan, Idle and Radar Move simultaneously while offline, leaving effectively no usable map canvas.
- Offline Home now hides idle/reposition controls; those are contextual shift UI. Default hierarchy is earnings -> scan -> map -> Start Shift.
- Home now launches expanded instead of force-docked.
- Added a three-speed native motion system: press micro-interactions, component transitions and spatial/HUD transitions, with reduced-motion support.
- Added animated tab state, SVG motion, scan signal sweep, shift pulse and Web View Transitions where supported.
- MapLibre no longer has a single unpkg module point of failure: runtime loader tries jsDelivr then unpkg.
- Service-worker shell bumped to v41.


## v8 / UI v42 — Generated production motion assets
**Status: first generated asset family integrated**

- Generated a dedicated YA Creative UI asset atlas and a separate animation-frame sheet rather than relying only on generic SVG/CSS icons.
- Cropped the SCAN animation into nine optimized WebP production frames and committed them under assets/generated.
- SCAN now plays those authored frames only while the planner is scanning; idle state holds the first authored frame.
- This establishes the production asset pipeline: generated atlas -> crop/optimize -> repository assets -> component state animation. Future generated icon families must use the same pipeline rather than introducing unrelated glyph styles.
- v41 map/motion/default-density fixes were explicitly landed onto main together after detecting that several connector-created commits had not advanced the main ref.


## v9 / UI v43 — Generated icon family becomes canonical
**Status: implemented**

- Committed generated YA Creative navigation and map-control raster sprite assets under assets/generated.
- Replaced bottom-navigation generic SVGs with crops from the generated default/active icon family.
- Replaced locate and HUD expand/collapse controls with crops from the same generated map-control family.
- Existing generated nine-frame SCAN animation remains the authored animated control.
- DESIGN_SYSTEM.md now forbids silently redrawing generated production assets as unrelated SVG/glyph replacements.


## v10 / UI v44 — Production control integration + planner parse repair
**Status: implemented on integration branch; deployment/on-device verification pending**

- Converted SCAN from disposable button text into persistent authored art + label DOM, so loading state no longer destroys the generated nine-frame control.
- Converted shift and online/offline controls to persistent semantic state nodes, matching the production sheet language: blue/play start, red/stop end, dedicated online LED.
- HUD expand/collapse now changes classes and aria-expanded only; it no longer replaces the generated map-control artwork with text glyphs.
- Home map launches expanded so the map remains the primary environment rather than beginning in a collapsed shell.
- Service-worker cache advanced to v44 and now explicitly pre-caches the generated navigation, map-control and SCAN assets.
- During the pass, found and repaired a malformed refreshLearning -> refreshStartPlan seam in app.js. This was a JavaScript parse/runtime blocker capable of making the map look broken independently of MapLibre loading.
- Existing v1-v5 intelligence and v40-v43 design/map invariants remain intact.
- Remaining gate: merge/deploy, confirm Vercel READY, then perform the required iPhone map/shift/scan smoke test.


### v44.1 visual QA correction
- iPhone QA rejected the initial raster integration: sprite crops visibly contained source-sheet labels/backgrounds and were not production assets.
- Removed runtime dependence on those sheet-crop sprites and scan frames. Navigation, map actions, scan, status and shift controls are now reconstructed as clean CSS/vector-like primitives based on the approved reference language.
- PWA cache advanced to v44-1 and no longer pre-caches rejected generated crop assets.
- This correction is intentionally still on the integration branch. Production merge remains gated on preview + iPhone visual/map QA.


## v11 / UI v45 — Final interaction pass + recommendation-language audit
**Status: implemented on main; deployment/iPhone smoke test pending**

- Replaced the old upward page entrance with full-viewport horizontal destination swipes.
- Added spring/pop feedback to navigation and controls, periodic shift-button bloom/shine, stronger press feedback, and progressive haptic calls where the browser supports vibration.
- Rebuilt SCAN as an explicit idle -> scanning -> complete -> ready state machine with rotating radar sweep, signal-wave animation, completion confirmation and stable persistent art.
- Removed the planner flicker caused by refreshData repeatedly calling refreshStartPlan: existing recommendations now stay visible during ordinary refreshes; only explicit scans expose scanning UI.
- Changed pre-shift guidance from ambiguous START pocket copy to STAGE AT the exact waitAt merchant when available; pocket names remain evidence/context instead of pretending two merchants are one destination.
- Replaced the rider-facing “Culver merchant inventory” map popup copy with “nearby restaurant.”
- Audited the target semantics: waitAt is a restaurant-gateway staging coordinate selected from the ranked pocket, not a guarantee that an Uber order will originate there. Density-only targets remain labeled as exploratory until personal completion/offer evidence accumulates.
- Existing v1-v5 scoring, 80% utilization budget, exact coordinate routing, closed-loop learning and map reliability invariants remain active.


## v12 / UI v45.2 — Uber evidence labeling
**Status: implemented on main; deployment/on-device verification pending**

- Nearby restaurant density is now explicitly separated from Uber-specific evidence.
- Every recommended pocket exposes three different counts when available: total mapped restaurants nearby, restaurants observed by name in the rider's captured Uber offer history, and restaurants with completed pickups in that history.
- Zero Uber-observed restaurants is rendered as “Uber coverage unconfirmed,” not as a claim that the restaurants are not on Uber Eats.
- “Confirmed pickup” means confirmed by this rider's completed Radar/Uber history; it is not an Uber-platform certification.
- General OSM/Supabase restaurant inventory is never labeled “confirmed Uber Eats.”
