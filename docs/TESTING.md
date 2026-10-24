# LifeKeeper validation

Nothing is phone-tested.

CI must pass fatal analyze, meaningful rule/recurrence/reminder/repository/backup/widget tests, signed ARM64 build and exact signer verification for the same commit before release. No release from failed or unobserved CI. Native configuration tests check required permissions/receivers and private signing; they do not prove real delivery.

## Phone checklist
- Fresh install without internet. No demo data unless opted in. All tabs, empty states, add/edit/search/filter/sort/delete/duplicate/archive/reopen.
- Scan camera and gallery offline. Cancellation, camera unavailable/permission denial, large and unreadable image, process death recovery. Check every filled date/amount. Invoice date must never become due date. Missing fields remain blank. Retake cancels prior private image. Save only after review.
- January 31 monthly completion through February and March; February 29 yearly. Mark paid once, verify actual payment history and per-currency budget/charts. Repeated taps must not add duplicates for one occurrence.
- Reminder permission denial, exact alarm denial/inexact fallback, quiet-hours midnight rollover, snooze, Complete/Open/Snooze actions, CRUD cancellation, reboot, time/timezone change, background/OEM battery limits. No guaranteed delivery. Current digest plans 30 days ahead and refreshes with app/system events.
- PIN relock when backgrounded, lockout after repeated failures, screenshot privacy, wrong PIN and current-PIN requirement to change/disable.
- Export password, wrong password and tampered export; restore confirmation, attachments/history/settings roundtrip, invalid restore leaves old records intact. PIN is not exported.
- Attachment preview/rename/replace/delete and extracted text search. PDFs use installed PDF viewer after confirmation. PDF text is not automatically OCR-extracted. Attach bill scans for searchable OCR text.
- UPI review validates INR amount/payee; app return never marks paid. Subscription cancel tracking never cancels provider.

## Honest limits
- Database and attachments are app-private but are not encrypted at rest by this app. Android device encryption depends on the device. PIN is a screen lock, PBKDF2 salted hash lives in secure storage. Exports are AES-256-GCM authenticated encryption with PBKDF2.
- Biometric unlock is not included. Widget is an in-app preview only. SMS demo parses pasted/sample text only, no SMS permission. Bundled Latin ML Kit OCR is the only scanning model; no LLM, cloud, account, backend or language controls.
- Notification schedules depend on OS/OEM behavior and permissions. Native restart/time-change recovery needs device validation. Reminders are planned up to a year ahead; digest up to 30 days. Open app to refresh health.
