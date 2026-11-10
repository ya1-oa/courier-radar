# Radar offer policy — payout, Uber ETA, miles

The single offer decision source of truth is **lib-offer-policy.js** (PWA/server) and **OfferPolicy.swift** (iOS). Historical market data continues to inform WAIT/MOVE recommendations, **never** the TAKE/SKIP verdict.

## Inputs
- **Offer payout** in USD.
- **Total Uber offer distance** in miles (pickup + delivery as Uber displays).
- **Uber's total estimated time** in minutes. Do not add separate pickup/dropoff minutes.
- **Optional 0/10/20% time buffer**, default 10%.
- **21 mph rider cruise-speed sanity check** (20–22 sweet spot; this does not get added to ETA).
- **Optional confirmed miles of bike battery range remaining**: if known, require order distance + 2 miles; voltage or % alone is not a range measurement.

## Acceptance
```
adjusted_minutes = uber_eta_minutes * 1.10
gross_hourly = payout * 60 / adjusted_minutes
dollars_per_mile = payout / offer_miles
minimum_payout = max(24 * adjusted_minutes / 60, 1.50 * offer_miles)
```

- **Strong accept:** >=$28/hour AND >=$1.50/mile.
- **Accept:** >=$24/hour AND >=$1.50/mile.
- **Borderline/CHECK:** >=$20/hour but fails either acceptance threshold; verify the destination, demand and conditions.
- **Decline/SKIP:** below $20/hour.
- **CHECK:** missing Uber data, speed/ETA contradiction, known insufficient battery range, Shop & Pay uncertainty or incomplete add-on combined-route values.

No arbitrary $8 per-order floor. No calibration-day override. No assumed Uber acceptance-rate punishment. No fake wait-time or replacement-offer income.

Daily goal is **$200 by default**, but can be configured. Remaining amount and hourly pace are displayed as planning information, not reasons to accept poor offers.

## Where to use
- Web Radar **Plan > Quick offer checker** (manual inputs).
- Uber screenshot OCR capture returns the same decision math.
- Native iOS Radar Core invokes the same policy for current-offer and screenshot decisions.
- Radar's learned wait-zone model, GPS and battery-range warnings remain available; no cross-app credential interception.

## Testing
- Node: `npm test` or `node --test tests/*.test.js`
- Swift: `swift test --package-path ios`

**Note:** this is projected gross revenue per offer, not net profit or necessarily realized online earnings. Review actual trip time and battery usage regularly to calibrate the time buffer.
