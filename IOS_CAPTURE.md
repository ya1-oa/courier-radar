# Fast iPhone capture (no Uber password or private API)

## One-tap capture through iOS Shortcuts

In **Shortcuts**, make **Radar Capture** with these actions, in this order:

1. **Take Screenshot** (while Uber Driver is on screen).
2. **Extract Text from Image** → Screenshot.
3. **Get Current Location** (optional but improves zone learning).
4. **Get Contents of URL** → `https://YOUR-RADAR-DOMAIN/api/capture`.
   - Method: **POST**.
   - Headers: `Content-Type: application/json`; `x-capture-token: YOUR_CAPTURE_TOKEN`.
   - Request Body: **JSON**:
     - `text`: extracted OCR text (Shortcuts variable).
     - `lat`: Current Location latitude (optional).
     - `lng`: Current Location longitude (optional).
     - `vehicle`: `ebike`.
     - `source`: `ios_shortcut_screen_ocr`.
5. **Show Notification** → use JSON result `verdict` for an offer, or `state` for a lifecycle screen.
6. In iPhone **Settings → Accessibility → Touch → Back Tap**, assign **Double Tap** to **Radar Capture**.

**What is automatic after triggering capture:** OCR parsing, deduplication within three minutes, TAKE/SKIP cash model, and lifecycle transitions that are explicitly visible on the screen. Confirmed lifecycle screenshot text is recorded as an inferred stage. A new distinct order after the old single delivery reached pickup can infer completion; this is recorded with a separate `inferred_delivery` event.

**What still needs an action:** invoking the shortcut on the Uber screen. The web app cannot silently take screenshots or inspect the Uber Driver app in the background. Open the Uber screen for an offer, tap the back of the phone, and wait for the notification. When OCR misses a stage, use Radar’s **Next Stage** button (Accepted → Arrived → Picked up → Delivered). Never press Next Stage until the corresponding action actually happened in Uber.

## Screen examples

- Offer screen with price, miles, and estimated time → `offer`; Radar saves it and shows TAKE/SKIP.
- Clear pickup-navigation screen → `accepted`, only when last Radar order is observed.
- Confirm Pickup screen → `arrived`, only when preceding state is accepted.
- Dropoff/navigation screen → `picked_up`, only when preceding state is arrived.
- "Delivery completed" confirmation → `delivered`, only when preceding state is picked_up.
- Unrecognized screenshot → 422; no false offer or state is stored.
- Same offer screenshot within three minutes → existing offer reused; no duplicate.

**Notes:** A screenshot is your own observation, not privileged access to Uber’s dispatch backend. Extracted text is sent to your own Radar endpoint secured by your capture token. Keep the token private and never place it in public Shortcut links.

## Packet access vs order events

On iOS, an authorized VPN Network Extension can read routed packet metadata (network endpoints, sizes, timing), but normally not TLS-encrypted Uber offer content. An iOS PWA cannot install a packet tunnel or monitor another app’s network requests. Uber Direct / Eats merchant APIs are not courier dispatch APIs. Mobile screen capture with **a separate, permissioned native iOS companion** using Apple's screen-streaming framework plus local Vision OCR is the practical path toward continuous optical capture; it is *not shipped* as part of this web app.
