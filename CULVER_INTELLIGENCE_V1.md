# Courier Radar — Culver Intelligence v1 Contract

This file is the implementation source of truth. Do not materially change these principles without explicit user approval.

## Objective
Maximize expected dollars per online hour subject to predicted utilization >= 80%.

Utilization U = active_time / online_time.
Available/idle exposure is modeled separately from active delivery time.
Reference successful-day values: average active job 17.5 minutes. At U=0.80, idle budget W = D(1-U)/U = 4.375 minutes (4:23). This is a starting prior, not a permanent hard-coded threshold; it must adapt from observed data.

## Core intelligence
- Learn qualified-offer arrival hazard by cell/pocket/local-time bucket using available exposure, not raw online time.
- Use uncertainty-aware estimates. External demand data is a prior; the driver's own Uber/Radar observations dominate as evidence accumulates.
- Intelligent micro-relocation among nearby Culver restaurant pockets happens before long deadheads.
- Reposition travel counts as idle cost.
- Destination quality affects TAKE/SKIP. For stacks, evaluate final drop-off.
- Shop & Deliver has a separate time/value model; do not disable it blindly or let long low-value shops game utilization.
- Event, weather, merchant popularity, hours and restaurant density modify the prior, not the ground truth.
- Recommendations must be auditable: expected wait/activity, evidence, confidence, travel cost, merchant density and relevant external signals.

## Map/UI invariants
- Earnings, rolling active %, idle budget and active-order state remain readable.
- Restaurant intelligence can be run on command with a visible SCANNING state, provider readiness and last-result evidence.
- Selecting a recommended pocket persists; it must not disappear after tapping.
- A WHY THIS POCKET panel explains the selected/recommended pocket.
- The recommended/selected relocation pocket is pinned on the map.
- Once the merchant inventory is available, restaurants are rendered on the map.
- User can route from Radar to the selected/recommended pocket in Apple Maps or Google Maps.
- Active-delivery state outranks idle/repositioning UI and must not be obscured by it.

## Culver graph
Treat Culver as connected micro-markets / restaurant pockets rather than one hotspot. Rank nearby pocket-to-pocket moves before regional escape.

## Data required
Per cell/pocket/time bucket: available seconds, active seconds, all offers, qualified offers, accepts, completed, payout, pickup wait, destination cell, reposition time/distance, shop vs restaurant. Reconcile with Uber daily ground truth when available.

## APIs
Priority: Radar/Supabase ground truth; BestTime restaurant activity; event intelligence (Ticketmaster currently, richer attendance/impact provider later); weather; merchant identity/hours; cycling travel time. Cache external merchant data rather than querying every restaurant every scan.


## v2 restaurant gateway intelligence
- Every recommended pocket must also identify a specific WAIT AT restaurant or precise restaurant gateway when merchant evidence is available.
- The wait target is a real merchant coordinate, not merely a pocket centroid. Map relocation pin and Apple/Google routing target the selected wait restaurant.
- Maintain a coordinate-backed Culver merchant inventory and render the inventory on the map. Pocket scoring must operate over those merchant coordinates so dense gateways and adjacent clusters can be detected.
- Restaurant target ranking combines time-block fit, centrality within the pocket, observed Radar offers/completions/payout evidence, external activity signals and travel cost.
- The specific restaurant recommendation is an operational waiting location, not a claim that the next Uber order will come from that merchant.
- Pocket recommendation remains primary; restaurant target is the best staging point inside that pocket and may change by time block or learned dispatch behavior.
