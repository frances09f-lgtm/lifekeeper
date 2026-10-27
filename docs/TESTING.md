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

## 1.1.0 checks (Subby-style Home and Insights)
- Home total card: month (or payday period) total, per day, paid vs left bar, change vs last period. Paid counts only locally marked payments; left counts unpaid dues in the period plus older overdue ones.
- Alerts: trial ending within 7 days (Keep it), overdue (Mark paid / Mark all paid), recent price change (Keep it). Each action hides the alert.
- Next payments carousel Mark paid creates exactly one payment per occurrence.
- Notification actions Mark as paid and Remind me tomorrow (next day at the reminder time). Unpaid items repeat once a day for up to 7 days from the due date; quiet hours still apply. Needs device validation.
- Insights Overview, Trends (12-month bars, 6 months ahead, 12-week renewal heatmap, price changes), Services (total paid per item), Signals (price change, not marked paid, two payments within 3 days) and Cancel in time trials.
- Settings: payday budget period, CSV export of payment history (formula-safe), True black theme.
- Brand marks are bundled colours and initials. No logo downloads, no internet.

## Honest limits
- Database and attachments are app-private but are not encrypted at rest by this app. Android device encryption depends on the device. PIN is a screen lock, PBKDF2 salted hash lives in secure storage. Exports are AES-256-GCM authenticated encryption with PBKDF2.
- Biometric unlock is not included. Widget is an in-app preview only. SMS demo parses pasted/sample text only, no SMS permission. Bundled Latin ML Kit OCR is the only scanning model; no LLM, cloud, account, backend or language controls.
- Notification schedules depend on OS/OEM behavior and permissions. Native restart/time-change recovery needs device validation. Reminders are planned up to a year ahead; digest up to 30 days. Open app to refresh health.
