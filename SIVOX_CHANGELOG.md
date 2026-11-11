# SIVOX Changelog

## 2026-11-11 — Android-only audit baseline
- Created working branch `repair/android-staff-assignment-guards-2026-11-11` from main.
- Fixed staff assignment accept/reject methods to update only pending assignments and return failure when no row was changed.
- Added Android-only Flutter CI workflow for dependency installation, static analysis, tests and debug APK build.
- Added project continuity and issue tracking documents.
- No changes to main, no PR merge, no production Supabase changes, and no changes to the ios directory.
- CI execution outcome: pending verification; do not infer success from workflow creation.
