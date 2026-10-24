# LifeKeeper Android build scope

LifeKeeper is an offline Flutter/Dart Android personal-admin app. No account, backend, cloud, paid service, automatic financial transactions or bank access. No language feature. Version 1 needs no AI model: bill scanning uses bundled Google ML Kit on-device OCR and deterministic extraction rules with review before saving.

## Approved interface
Material 3 Expressive / Orion Store style: pale mint canvas, dark green/charcoal text, rounded white cards, teal floating plus, pill-shaped navigation. Light and dark themes. Home, Calendar, Spending, Vault, Settings. Home includes Attention Queue / Life Admin Radar, due counters, top 3 priorities, 7-day timeline, records, search/filters, Scan bill and Quick add. Demo data must be labeled and removable, preferably opt-in. Exact design-source color/spacing tokens were not available, so do not claim pixel-perfect matching.

## Required behavior
- Real SQLite persistence with transactions, migrations and indexed queries; feature-separated UI, domain, repository, notifications, OCR and security.
- Bills, payments, subscriptions, insurance, vehicle papers, warranties, IDs, renewals, purchases, tasks and custom categories. Full CRUD, duplicate, search, filter, sort, complete, reopen, snooze and archive.
- Title, description, category/tags/notes, amount/currency, due date, biller/issuer, account number, UPI ID, recurrence, multiple reminder offsets/time, attachments, importance/status/timestamps and occurrence/payment history.
- Recurrence daily/weekly/monthly/yearly/custom. Preserve month-end/leap-year anchor days. Marking paid records history and creates the next occurrence transactionally without duplicates. An unmarked payment is not verified unpaid.
- Deterministic priority reasons and Life Admin Radar. Overdue/proximity/consequence/manual importance/dependencies/repeated snoozes; no amount-only priority.
- Calendar month/day views; paid spending totals/payment history/six-month charts/category totals/monthly budget. Count paid history, not pending bills.
- Notifications via timezone-aware Android scheduling: multiple reminders, daily digest, quiet hours, snooze, Complete/Snooze/Open, unique IDs, cancellation/reconciliation, reboot/date/time/timezone recovery, permissions and truthful health status. No guaranteed delivery claim.
- Scan bill: real capture/gallery, bundled offline ML Kit, bill name/issuer/amount/due date/account number, optional bill period, missing/ambiguous fields flagged, Retake/Review/Save. Original photos and OCR text stored privately and linked to vault. Never substitute invoice date for due date without evidence.
- Vault attachments (images/PDFs), preview/rename/replace/delete, OCR search/expiry filters; subscriptions/trial alerts/price history/local stop-tracking; warranties and ID/policy expiry.
- UPI button launches user-confirmed valid payee/amount in the installed UPI app. Returning from UPI is not verified payment. SMS bill demo uses sample or pasted text, not real inbox claims. Widget preview uses next 3 actual records and is explicitly a preview unless natively implemented.
- Secure optional PIN, relock/lockout, app-private storage and Android backup disabled; encrypted database/attachments where supported, otherwise disclose exact limits. Authenticated password-encrypted export/restore including history/recurrence/settings/attachments, safe restore confirmation, delete-all-data and privacy page.
- Rule-based natural-language Quick add with review, keyword queries/summaries over real records as reliable fallbacks. No model bundled or required.

## Build and release gate
Use mutually compatible pinned Flutter/Dart/packages/Android Gradle/JDK/SDK versions. GitHub Actions must run pub get, fatal-warning analyze, meaningful unit/widget/repository tests, signed ARM64 release APK build and apksigner verification. No release on a failed/incomplete build or before checks for the exact release commit are green. Attach APK, exact byte size, SHA-256 and truthful results. Document missing functionality honestly. No phone tests have been performed.

Signing inputs: Actions secrets LK_SIGNING_KEYSTORE_BASE64 and LK_SIGNING_STORE_PASSWORD, PKCS12 alias lifekeeper. Do not use the older LK_KEYSTORE_PASSWORD. Do not commit keys, passwords, tokens or personal data. The signing bootstrap is preparation only, not application CI. It prints only public-key-encrypted secret values for an authorized repository-secret writer to install.

Automated tests should cover recurrence/leap years/month ends, scoring, OCR/rule validation, quiet hours/notification IDs and reconciliation, database CRUD/migrations, payment transaction idempotence, backup/restore/tamper detection and key/PIN behavior. Explicit manual checklist: phone camera/OCR, airplane-mode operation, UPI, permissions, notification actions, reboot/Doze/OEM restrictions, background app lock, file preview/restore. State 'Nothing is phone-tested' until actual phone testing is recorded.
