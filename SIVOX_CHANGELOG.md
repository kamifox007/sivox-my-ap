# SIVOX Changelog

## 2026-11-11 — Android-only audit baseline
- Created working branch `repair/android-staff-assignment-guards-2026-11-11` from main.
- Fixed staff assignment accept/reject methods to update only pending assignments and return failure when no row was changed.
- Added Android-only Flutter CI workflow for dependency installation, static analysis, tests and debug APK build.
- Added project continuity and issue tracking documents.
- No changes to main, no PR merge, no production Supabase changes, and no changes to the ios directory.
- Added a safe stack-trace truncation helper in `lib/main.dart`; both Flutter and async error handlers now handle null/short traces without a substring range error.
- Added `test/auth_service_test.dart` covering Algerian phone normalization formats.
- Hardened `verifySecurityClearance` to update only confirmed bookings that are not already security-cleared, and return false when no row changes.
- Hardened `confirmManagerPayment` to require a confirmed, security-cleared, not-yet-paid booking and return false when no row changes.
- Fixed the analyzer-reported missing Cupertino import in `lib/theme/app_theme.dart` after the first actual Android CI run exposed it.
- Reviewed PR #2 as a source of candidates, not as a merge target; its role-routing, booking-stage, ticket-transfer and SQL changes remain unported pending schema/authorization validation.
- CI execution outcome: pending verification; do not infer success from workflow creation.
