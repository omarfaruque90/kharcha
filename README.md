<p align="center">
  <img src="assets/app_logo.png" width="140" alt="Kharcha logo" />
</p>

<h1 align="center">Kharcha — দৈনিক খরচের হিসাব</h1>

<p align="center">A simple, offline-first daily expense tracker for Android.<br/>অ্যান্ড্রয়েডের জন্য সহজ, অফলাইন দৈনিক খরচের হিসাব রাখার অ্যাপ।</p>

---

## ✨ Features | ফিচার

- ➕ **Add / Edit / Delete expenses** — amount, category (with icons), date, note, payment method (Cash / bKash / Card / Other)
- 🏠 **Home dashboard** — Today's, This week's, and This month's totals at a glance
- 📋 **Expense list** — grouped by date (newest first), search by note, filter by category
- 📊 **Reports** — last-6-months bar chart + monthly category-wise pie chart
- 🌐 **বাংলা + English UI** — Bangla is the default; switch anytime from the AppBar or Settings
- 🌙 **Light / Dark theme**
- 💾 **100% offline** — all data stored locally with SQLite
- ৳ **BDT currency formatting**

## 🚀 Getting started | চালু করা

Prerequisites: [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel).

```bash
git clone https://github.com/omarfaruque90/kharcha.git
cd kharcha
flutter pub get
flutter run
```

## 📲 Download the APK | APK ডাউনলোড

Every push to `main` automatically builds a release APK with GitHub Actions:

1. Open the [**Actions**](https://github.com/omarfaruque90/kharcha/actions) tab of this repo
2. Click the latest successful **Build APK** run
3. Download the **kharcha-apk** artifact and unzip it
4. Install `app-release.apk` on your Android phone (allow "Install unknown apps" if asked)

## 🎨 Change the app name or icon | নাম / আইকন বদলানো

**App name:** edit `android:label` in `android/app/src/main/AndroidManifest.xml`
(and the `title`/`Text('Kharcha')` strings in `lib/main.dart`).

**App icon:** the logo lives at `assets/app_logo.png`.
Replace that file, then regenerate the launcher icons:

```bash
python3 - <<'EOF'
from PIL import Image
src = Image.open('assets/app_logo.png').convert('RGB')
for dpi, px in {'mdpi':48,'hdpi':72,'xhdpi':96,'xxhdpi':144,'xxxhdpi':192}.items():
    src.resize((px,px), Image.LANCZOS).save(f'android/app/src/main/res/mipmap-{dpi}/ic_launcher.png')
for dpi, px in {'mdpi':108,'hdpi':162,'xhdpi':216,'xxhdpi':324,'xxxhdpi':432}.items():
    src.resize((px,px), Image.LANCZOS).save(f'android/app/src/main/res/mipmap-{dpi}/ic_launcher_foreground.png')
EOF
```

The adaptive-icon background color is `@color/ic_launcher_background`
in `android/app/src/main/res/values/colors.xml`.

## 🗂️ Project structure

```
lib/
├── main.dart            # App entry, brand theme, splash, bottom navigation
├── models/             # Expense, ExpenseCategory
├── db/                 # SQLite helper (expenses + settings tables)
├── providers/          # ExpenseProvider, SettingsProvider (language/theme)
├── l10n/               # Bangla/English string maps (AppStrings)
├── utils/              # ৳ formatting helpers
├── screens/            # Home, Add/Edit, Reports, Settings
└── widgets/            # ExpenseTile, SummaryCard
android/                # Android shell (applicationId: com.kharcha.app)
assets/app_logo.png     # Brand logo (also used for launcher icons)
.github/workflows/      # CI: analyze + build release APK on push to main
```

## 🛠️ Tech stack

Flutter (Material 3) · provider · sqflite · fl_chart · intl · path_provider

---

## ✨ Features (English)

Same as above — Kharcha helps you record everyday spending in seconds,
see where your money goes each month, and keep everything private on your device.

## 📲 Download the APK (English)

Each push to `main` builds a release APK via GitHub Actions.
Go to the **Actions** tab → latest green **Build APK** run → download the
**kharcha-apk** artifact → install the APK on your Android device.

## 📄 Changelog

See [CHANGELOG.md](CHANGELOG.md).
