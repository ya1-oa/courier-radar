# Culver $270 operating system — 2026-10-27

## The target

$270 gross = 10 working hours × $27/hour. At 80% active utilization this needs
$33.75 per active hour. One equivalent production mix is 24 deliveries × $11.25,
averaging 20 active minutes each, plus 120 unpaid minutes over the day. That
unpaid budget includes waiting AND repositioning; it is not two separate budgets.
This is an operating target, not a measured forecast from one day's screenshots.

| Block | Start cluster | Block cash target | Running target |
|---|---|---:|---:|
| 8–10:30 AM | Culver Steps: Philz + Pop's Bagels; downtown coffee coverage | $50 | $50 |
| 10:45 AM–2 PM | Culver Steps/downtown: Mendocino + Tender Greens + Erewhon | $90 | $140 |
| 4:45–9 PM | Downtown or Platform/Helms: sweetgreen + LOQUI + Pasta Sisters | $130 | $270 |

These add to ten working hours. Use 2–4:45 PM for charging, food and other work.
Reach the first cluster before the block begins; do not spend the rush commuting
from USC. The dinner row assumes the rider elects to work that whole block.
If the rider has a fixed personal commitment, replan the WORKING hours rather
than counting that commitment as productive delivery time.

## Starting rules before the model has enough personal observations

- Prefer $8+ LOCAL offers, but a fast $6–$7 trip that keeps the pickup corridor
  can be better than an $8 outbound offer. The complete cycle controls.
- At a $27/hour opportunity target: 15 minutes costs $6.75, 20 costs $9,
  25 costs $11.25, 30 costs $13.50, and 40 costs $18. Add abnormal delay.
  These figures exclude the next normal wait; actual model thresholds include
  that wait through the replacement-rate calculation.
- A $7 local offer with 12 occupied minutes and 4 waiting minutes is $26.25/hour.
  An $8 offer with 15 delivery minutes, 15 recovery minutes and 4 normal waiting
  minutes is $14.12/hour. A $16 stack taking 30 occupied + 4 waiting minutes is
  $28.24/hour. A $20 batch taking 35 occupied + 5 waiting minutes is $30/hour.
- Do not stay out of position during lunch to protect acceptance above 80%.
  Aim for 60%, review at 56%, preserve 50%; current in-app requirements govern.
  There is no exact decline budget without the rolling exclusive-offer queue.
- After five unpaid minutes per typical 20-minute job, review the nearest useful
  alternative and net gain after its travel cost. A small nearby reposition can
  make sense; a 20-minute cross-town chase spends four jobs' idle budgets.
- More/bigger orders: stage near several suitable pickup merchants before peaks,
  minimize pickup queues, safely carry legitimate stacks, and preserve the ability
  to take the next valuable order. Do not include a future $40 tip in the baseline.

## Verified merchant geography

The primary morning recommendation is **Culver Steps**, not an arbitrary street:
Philz and Pop's Bagels share the 9300 Culver complex. Pop's menu lists 7:15 AM–3 PM;
Philz's weekday listing shows an early morning opening. Mendocino is in the same
complex and its official page lists 10 AM–9 PM. Tender Greens is nearby downtown.
GGET is at 10000 Washington; it provides a western coffee alternative rather than
being falsely treated as the same storefront. **sweetgreen is at 8840 Washington,
near the Platform corridor**, not in the Culver Steps complex. LOQUI is at Platform;
Pasta Sisters is in Helms. These are listing/category-based starting positions,
not claims of access to merchant Uber order counts. Check actual app availability.

Sources checked:
- https://www.ubereats.com/store/philz-coffee-culver-city/8M3mgEVXST6WI1KQ-Zn9tQ
- https://www.ubereats.com/store/pops-bagels-culver-city/gH2V2fVYRHakJr62fMbj8Q
- https://www.mendocinofarms.com/location-directory/los-angeles/9300-culver-blvd-culver-city-ca-90232
- https://www.tendergreens.com/locations/culver-city/
- https://www.ubereats.com/store/go-get-em-tiger-culver-city/4yxilbB6VDmeG1OIlPtM2w
- https://www.ubereats.com/store/sweetgreen-culver-city/n8rsd5euQa245UHGyxHZXQ
- https://www.ubereats.com/store/loqui-culver-city/5N79wVDzTauHANuc61T5VA
- https://www.ubereats.com/store/pasta-sisters-culver-city/fKd3JwGoTAKPwCcxOIJrYg
- https://www.uber.com/us/en/blog/uber-eats-pro-california/

## Implemented in this native change

- `ios/Sources/RadarCore/AdaptivePlanner.swift` supplies the rolling renewal-reward
  model, destination recovery costs, actionable geographic/daypart priors,
  60% model acceptance target, 56% guard, 80% utilization idle budget, and ordinary
  urban e-bike speeds. Current exposure updates replacement value as time passes.
- `CashPlanner` selects the adaptive policy for native app callers. Old callers
  without adaptive context retain compatibility.
- Native Home shows named clusters, complete cycle and recovery minutes, required
  working-hour pace, and OpenAI review. The misleading automatic-return label is
  removed. Settings adds planned WORKING hours and acceptance percentage.
- Both Action Button screenshot and text Shortcuts run the native Swift planner.
- `api/coach.js` is the native app's secret-bearing backend for OpenAI Responses.
  It uses structured output, an optional resized screenshot, no response storage,
  an 800-token output limit, a 6.5-second provider timeout, cache and throttling.
  The phone has a 100-review/day request cap. Server in-memory limits are best
  effort per instance, not a durable spend guarantee. Use the OpenAI project
  controls for your $10 budget.
- AI is opt-in. Missing key, provider errors, late responses and refusals leave
  the native mathematics available. AI CHECK or a high-confidence AI objection
  to a native TAKE produces CHECK, not an automatic Uber action.
- A street-only geocode has reduced confidence and requires pin verification.

## Configure OpenAI

Set `OPENAI_API_KEY` as a server-only Vercel environment variable, redeploy the
backend, and enable **OpenAI screenshot review** in native Settings. Never paste
this key into Swift source, UserDefaults, the app bundle or a commit. The default
model is `gpt-5.4-mini`; `OPENAI_COACH_MODEL` can select another compatible model.
No live OpenAI call has been verified without the user's configured key.

At the checked $0.75/million input and $4.50/million output text rates, an example
1,500-input/400-output-token review is about $0.002925 (~$0.29 per 100). Images,
actual context size and output length change the cost. There is no per-minute
AI polling: local math updates while waiting; AI reviews new captured offers.

## Remaining verification and routing work

The Swift core integrates supplied bicycle geometry for corridor interception.
No live bicycle-route provider is configured in this change; absent geometry
uses a labeled 1.25 road-distance factor and intersection allowance. The named
cluster coordinates are approximate staging centers, not surveyed entrances.
Native external-map launch opens the cluster pin; it does not disguise walking
routes as cycling directions.

The OpenAI review receives native math, screenshot/OCR, position and curated
clusters. It has no live web/map tools in this inexpensive call. Existing OSM,
BestTime and historical discovery endpoints remain available; the native app caches these discovery signals every 15 minutes as weak prior
adjustments. Live cycling-provider connection remains follow-up work.

Validation: seven mocked backend integration tests pass. Ten Swift core tests
are supplied, but this execution environment has no Swift compiler or Xcode;
run `swift test --package-path ios` and a real-device Xcode build before merging.
The existing JavaScript suite already has an unrelated UI smoke-test failure
asserting obsolete lifecycle source strings absent from current main.

Official OpenAI references checked:
- https://developers.openai.com/api/docs/models/gpt-5.4-mini
- https://developers.openai.com/api/docs/guides/structured-outputs
- https://developers.openai.com/api/docs/guides/images-vision
