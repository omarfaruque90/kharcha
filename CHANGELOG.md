# Changelog

## 2.0.0 — 2026-10-03

**Kharcha v2** — smoother and runs on almost every Android phone.

### Added
- Motion animations across the app: animated screen transitions, springy summary cards, staggered expense-list entries, animated charts on the Reports tab, and a playful animated splash
- Support for **Android 5.0 (API 21) and up** — the widest range Flutter allows, covering ~99%+ of devices

### Fixed
- Release APK is now signed with **both v1 and v2 signature schemes**, fixing "App not installed" errors on Xiaomi / MIUI / Redmi phones

## 1.0.0 — 2026-10-03

First release of **Kharcha** (দৈনিক খরচের হিসাব).

### Added
- Add, edit, and delete daily expenses (amount, category, date, note, payment method: Cash / bKash / Card / Other)
- Home dashboard with Today's / This week's / This month's totals
- Expense list grouped by date (newest first) with note search and category filter
- Reports tab: last-6-months bar chart and monthly category-wise pie chart (fl_chart)
- Bangla (default) + English UI with in-app language toggle
- Light / dark theme toggle
- Offline-first local storage with SQLite (sqflite)
- BDT (৳) currency formatting
- Branded launcher icon, splash screen, and deep-emerald + gold theme
