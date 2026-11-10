# Hire Haulage — iOS app

A native **SwiftUI** iPhone app for the Hire Haulage delivery & collection
planner. It talks to your existing Node/Express server
(`https://orders.picnictablehire.com`) over its REST API — **no backend changes
required**. Authentication reuses the server's existing cookie session
(`POST /api/auth/login`); `URLSession` carries the cookie automatically.

Built against **Xcode 26 / iOS 17+**. The project file is generated from
`project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen), so source
files are added simply by dropping them into `Sources/`.

---

## Quick start (simulator)

```bash
brew install xcodegen        # one-time, if not already installed
cd HHiOS
xcodegen generate            # creates HHiOS.xcodeproj from project.yml
open HHiOS.xcodeproj
```

Press **▶︎** in Xcode (any iPhone simulator). On the login screen, tap
**“Explore with sample data”** to browse the UI offline, or sign in with your
real Hire Haulage credentials to use live data.

### Build & run from the command line

```bash
xcodebuild -project HHiOS.xcodeproj -scheme HHiOS \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build
```

---

## Run on your own iPhone (free, no paid Apple Developer account)

1. Plug in your iPhone (or use wireless debugging) and `xcodegen generate`.
2. Open `HHiOS.xcodeproj`, select the **HHiOS** target → **Signing &
   Capabilities**.
3. Set **Team** to your personal Apple ID (Xcode → Settings → Accounts → add
   your Apple ID first). Free accounts work.
4. The bundle id is `com.spudbox.hirehaulage`. If Xcode says it’s taken, change
   it to something unique (e.g. `com.<yourname>.hirehaulage`) — it’s just a local
   identifier for personal signing.
5. Pick your iPhone as the run destination and press **▶︎**.
6. On the phone: **Settings → General → VPN & Device Management** → trust your
   developer certificate.

> Free-signed apps expire after **7 days** — just re-run from Xcode to refresh.
> A paid account ($99/yr) + TestFlight removes that limit if you later want it.

---

## Connecting to the server

- Default server URL: `https://orders.picnictablehire.com`.
- Change it under **More → Connection → Server** (or on the login screen via
  **Server settings**). Changing it signs you out.
- To test against a **local** server (`http://localhost:3000` in the simulator,
  or `http://<your-mac-LAN-ip>:3000` from a real device), just enter that URL.
  App Transport Security already allows local-network HTTP
  (`NSAllowsLocalNetworking`).

---

## What’s in v1

| Area | Status |
|------|--------|
| Cookie-session login / auto-restore / logout | ✅ |
| **Today** — jobs happening today as native cards | ✅ |
| **Schedule** — upcoming jobs grouped by day, with type/status filters | ✅ |
| Job cards: type, status, date/time, destination, weather, furniture count, transport, haulier colour badge | ✅ |
| **Job detail** — full info, edit status & notes (all roles), assign haulier (admin) | ✅ |
| **Per-load (movement) editing** — each load expands from `transport_items`; set status, haulier, per-movement date & notes via `PATCH /api/jobs/:id` movement payload | ✅ |
| **Hire-date editing** (admin) — deliver/collect dates via `PATCH /api/jobs/:id/dates` (pushes to Current-RMS) | ✅ |
| **Sync from Current-RMS** (admin) — `POST /api/sync` from the More tab | ✅ |
| Destination **map** + “Open in Maps” directions | ✅ |
| Linked delivery ↔ collection sibling job | ✅ |
| **Hauliers** — list with colours, tap-to-call, per-haulier job list | ✅ |
| Tap-to-call site contact | ✅ |
| Offline **demo mode** with bundled sample data | ✅ |
| Pull-to-refresh, haptics, light/dark, branded icon | ✅ |

> Transport-less / self-arranged jobs (no `transport_items`) keep a single
> job-level editor; jobs with transport show one editable row per load.

## Not yet (candidate next steps)

- **Movement pairing / chains** — linking a collection load to a delivery load
  to save mileage (`/api/movement-pairs`). Pair/chain data is modelled and the
  detail can display it; the create/repartner/dissolve UI is the remaining build.
- **Mileage / budget-price calculation** trigger (`/api/jobs/:id/calculate-distance`).
- **Push notifications** / offline cache (would need small backend additions).

> **Live login confirmed** against production (`orders.picnictablehire.com`) on
> 2026-06-30 — sign-in, session cookie, and live data load all work on device.

---

## Project layout

```
project.yml                  XcodeGen spec (target, Info.plist, ATS, signing)
App/
  HHiOSApp.swift             @main entry + launch
  Assets.xcassets            App icon + accent colour
Sources/
  Models/                    Job, Haulier, MovementAssignment, AppConfig, AuthUser, LineItem, Enums
  Networking/                APIClient (URLSession + cookies), APIError
  State/                     Session (auth/config), JobStore (jobs + grouping)
  Theme/                     Palette, hex colours
  Util/                      Date formatting, SampleData
  Views/                     RootView, LoginView, MainTabView, Jobs/, Hauliers/, More/, Components/
```

### Launch arguments (for screenshots / evaluation)

- `-startDemo 1` — boot straight into offline demo data.
- `-startTab schedule|hauliers|more` — open a given tab first.
- `-startJob <id>` — deep-link to a job detail.

These only act when explicitly passed; normal launches are unaffected.
