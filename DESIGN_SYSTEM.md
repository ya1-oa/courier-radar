# Courier Radar Design System — YA Creative

Courier Radar is a mounted-phone operations instrument, not a generic dashboard. New UI must feel native to iOS while retaining a distinct YA Creative technical/editorial signature.

## Principles
1. One-glance hierarchy: active delivery > recommendation > map > shift controls > diagnostics.
2. Native restraint: SF system typography, 48px touch targets, safe-area awareness, restrained blur, no dashboard-card soup.
3. One spacing system: 8 / 12 / 14 / 16 / 22. No arbitrary margins to fix individual screens.
4. One radius family: 12 controls, 16 compact surfaces, 18 HUD glass, 22 content cards.
5. One border language: translucent hairlines. State comes from content and signal color, not thick decoration.
6. YA signature: technical fashion restraint, small asymmetric signal cuts, precise microtype, detailed line icons. No emoji/generic Unicode icons in production navigation.
7. New components must inherit tokens from :root. Do not add one-off hex colors, random padding, or version-specific CSS override piles.

## Tokens
Background: --ink / --ink-2
Surfaces: --surface / --surface-solid / --surface-2
Text: --text / --muted
Signal: --signal, secondary --signal-2, information --sky, warning --amber, danger --danger
Radii: --r12 / --r16 / --r22
Tap target: --tap = 48px
Content padding: --pad

## Component contract
- Buttons: .primary, .ghost, .route-btn or purpose-specific class built from the same tokens.
- Cards: .card. Do not create a new card skin.
- Map HUD: glass surfaces only; overlays must use pointer-events:none on the stack and pointer-events:auto on actual controls.
- Bottom navigation: exactly four primary destinations; SVG line icons use currentColor.
- Inputs: 48px minimum height and focus ring.
- Metrics: .stats; never hand-place metric columns.
- Labels: .eyebrow for operational microtype.

## Icon contract
Icons are authored SVG linework, viewBox 0 0 24 24, currentColor, rounded caps/joins. Avoid platform glyphs such as ⚙, ⌂, ◴, ⌖. Icons should be recognizable at 18–22px and remain decorative only when adjacent text already names the action.

## CSS maintenance rule
styles.css is now a single coherent system. Never append v41/v42 override patches to repair layout. Change the canonical component rule. Repeated version override blocks were the primary source of lopsided spacing and contradictory display/position behavior.


## Motion system
Motion is part of hierarchy, not decoration.
- Micro interaction: 180ms spring for button press and icon response.
- Component state: 420ms ease for cards, borders, opacity and tab transitions.
- Spatial/HUD motion: 720ms ease for map-shell movement.
- SCAN may use a restrained repeating signal sweep only while work is actually in progress.
- Active-shift status may pulse; static screens must not contain arbitrary looping animation.
- Respect prefers-reduced-motion.
- Default Home while offline is intentionally sparse: earnings + scan + map + Start Shift. Idle/reposition cards are contextual and appear only during a shift.
- Never cover most of the map with default-state cards.
