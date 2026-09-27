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
