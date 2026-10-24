# LifeKeeper

Offline Flutter Android bills, renewals and warranties. Home radar, calendar, payment history/budget, scan bill (bundled Latin ML Kit plus rules and editable review), vault, recurring records, real local notifications, PIN and password-encrypted export.

No account, backend, cloud, language feature or AI language model. All personal records stay on the phone. Database/attachments are app-private, not encrypted at rest by LifeKeeper. Exports are authenticated password-encrypted. PIN secrets are not backed up.

Nothing is phone-tested. See docs/TESTING.md for limits and manual checks. A release is published only after CI analyze/tests/signed ARM64 build/exact signature verification passes for the same commit. No APK is claimed until that evidence exists.

Build: pinned Flutter 3.47.7, Android minSdk 24, compile/target 36, JDK 17, generated standard Android project. Private signing secrets remain outside the repo.
