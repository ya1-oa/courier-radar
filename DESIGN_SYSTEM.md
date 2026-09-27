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


## Generated production assets
- Production iconography is generated as a coherent YA Creative family, then cropped/optimized into WebP assets under `assets/generated/`.
- Navigation uses `nav-sprite.webp`; map controls use `map-controls-sprite.webp`; SCAN uses the committed nine-frame generated sequence.
- CSS may crop a committed sprite into individual component states, but may not substitute unrelated Unicode glyphs or generic icon-library art.
- Active/inactive variants must come from the same authored sheet so silhouette, lighting, depth and glow remain consistent.
- Animated controls require authored frame sequences or deliberately composed transforms of authored assets. Animation must communicate state.
- Source asset-sheet crops are production art, not inspiration references: do not redraw them with arbitrary SVGs during later UI work.


## Production state integration
- Authored control DOM is persistent. Runtime state must update labels, ARIA attributes and classes without replacing the generated art nodes with textContent.
- SCAN uses the nine-frame authored sequence and a separate text label. The generated art node must survive loading, success and retry states.
- Shift start/end states share one control silhouette: blue/play while offline, red/stop while live. State color is semantic and motion remains restrained.
- Online/offline indicators use a dedicated LED plus label; never encode state only in a Unicode bullet.
- Generated raster art is paired with CSS geometry/motion where the artwork itself does not change. This keeps Retina rendering sharp and avoids unnecessary frame assets.


## v45 interaction contract
- Primary navigation changes are spatial: the incoming destination swipes across the viewport horizontally rather than drifting upward.
- Primary shift controls use restrained periodic shine/bloom plus spring press feedback; selected navigation art pops once on selection.
- SCAN has four explicit states: idle, scanning, complete, error. Scanning uses a rotating radar sweep and expanding signal wave; complete resolves to a green confirmation state before returning to ready.
- Haptics are progressive enhancement only. navigator.vibrate is invoked where supported; iOS Safari/PWA may ignore the Web Vibration API, so visual feedback must remain complete without it.
- Background intelligence refreshes must never overwrite a visible recommendation with a transient scanning message. Only an explicit rider scan exposes SCANNING.
- Rider-facing staging copy names the exact WAIT AT merchant when one exists. Internal inventory/debug vocabulary must not appear in the map UI.
