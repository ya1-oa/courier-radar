# Courier Radar

Courier Radar is a decision-support tool for delivery couriers. It uses location, trip activity and observed offers to help a courier assess where to spend the next idle interval.

## How it treats incomplete data

The dispatch model separates active delivery time from waiting time. A gap in GPS observations does not count as waiting. When an offer disappears from the screen, the recorded state depends on what was observed. This distinction keeps the tool from treating uncertain observations as confirmed courier decisions.

## Read and run

- [Build history](BUILD_HISTORY.md) describes the iterations and their tradeoffs.
- [Dispatch logic](lib-dispatch.js) contains the estimation rules.
- [Dispatch tests](tests/dispatch.test.js) cover time blocks, GPS gaps and delivery transitions.
- Run the local suite with `npm test`. To run the application locally with its API routes, use `npm ci` and `npm run dev`. See `.env.example` for optional integration configuration.

Deployment source: `main` → Vercel `delivery-intelligence`.
