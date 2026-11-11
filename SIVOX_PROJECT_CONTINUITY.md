# SIVOX Project Continuity

Last reviewed: 2026-11-11
Working branch: `repair/android-staff-assignment-guards-2026-11-11`
Baseline branch: `main`
Baseline commit: `8b2cdb86f5b23e2238439f0b1f17a6f84e52846d`
Latest working commit at initial documentation: `d796d1ca611ac4254385eea413ed4a19fb019eef`

## Product and platform scope
SIVOX is an existing Flutter/Dart application using Supabase/PostgreSQL, Firebase, Google Sign-In, QR scanning/generation, maps/location, notifications, PDF/printing, localization, storage, and related Flutter packages. This list is based on the checked-in dependency manifest and source files; it is not a complete feature certification.

Current authorized target: **Android only**. Do not build, sign, test, or publish iOS. Preserve the existing `ios/` directory and its contents.

## Repository structure observed on main
- `lib/main.dart`: app initialization, secure Supabase session storage, Firebase/Supabase startup, error handlers, app routing.
- `lib/screens/`: account, authentication, event, organizer, staff, booking, ticket, QR, discovery, profile, support, and operational screens.
- `lib/services/`: authentication, booking, event, staff, notifications, audit, storage, reporting, translation, and related services.
- `lib/models/`: booking, club, event, offers, voucher models.
- `android/`: Android Gradle configuration, manifest, launcher resources and MainActivity.
- `supabase/functions/chargily-webhook/`: payment webhook function.
- `test/widget_test.dart`: one startup smoke test at the time of review.
- `.github/workflows/`: existing iOS build and Supabase backup workflows; Android-only quality workflow added on the working branch.
- No `supabase/migrations/` directory or checked-in SQL migration files were found in the recursive main tree at the time of review. This does not prove the live Supabase database lacks schema objects.

## Existing project history
- PR #1 and PR #2 are historical project work and must be reviewed before changing their behavior.
- PR #2 currently exists as an open draft targeting main; it contains a large 145-commit / 43-file change set according to GitHub metadata at review time.
- Do not merge PRs or change main without the owner's explicit approval.
- Re-check branch heads and CI before continuing; repository state can change.

## Confirmed initial findings from source inspection
1. `StaffService.acceptAssignment` and `rejectAssignment` on main updated by assignment ID alone and returned success even if no row was changed. The working branch now limits both transitions to `status = pending`, requests the updated row IDs, and returns false if no row was updated.
2. The Android release build configuration currently uses the debug signing config. Do not treat a release APK/AAB as production-ready until a proper signing configuration is supplied and verified.
3. The app loads `.env` at startup and includes it as a Flutter asset. The file is tracked in the repository despite `.gitignore` containing `.env`. Never print its contents. Confirm that it contains only publishable client configuration; privileged credentials must not be committed.
4. The Android manifest contains a Google Maps API key. Do not expose it in reports. Verify provider-side package/SHA restrictions and quotas with the owner before any key rotation or restriction change.
5. Only a single widget smoke test was found under `test/`; no `integration_test/` directory was found in the inspected main tree.
6. The main tree did not contain Supabase SQL migrations. RPC names and RLS policies therefore cannot be certified from repository migrations alone.
7. The current app initialization has fallback Supabase URL and publishable key values in source. Assess configuration behavior and failure modes before changing startup semantics.

## Current work
- Branch: `repair/android-staff-assignment-guards-2026-11-11`
- Change: guard staff accept/reject transitions against stale/non-pending assignment rows and verify that an update actually occurred.
- Android workflow: `.github/workflows/android-quality.yml` runs dependency install, `flutter analyze`, `flutter test`, and a debug APK build on branch pushes / PRs to main.
- No PR has been opened yet. No changes have been made to main or to the ios directory.
- Runtime/CI results must be added only after the workflow actually completes.

## Required next steps
1. Inspect the Android workflow run and fix only confirmed failures.
2. Review the full PR #2 diff and commit history against current main; identify safe cherry-pick/port candidates without merging the PR wholesale.
3. Map every screen/action/service/database object and classify coverage.
4. Inspect all booking, QR, staff, auth and notification paths; verify the SQL/RPC/RLS definitions from an authorized schema source or migrations.
5. Expand tests using isolated mocks/test fixtures; do not touch live Supabase data.
6. Verify Android debug build first. Treat release signing and AAB publication as blocked pending a secure signing setup.
7. Open a draft PR only after the branch changes and Android CI are reviewed. Never merge it.
8. Continue recording verified changes, test outputs, blockers and next action here.

## Safety rules
- Preserve existing features and history; no rewrite from scratch.
- Android only; do not run iOS jobs or modify `ios/`.
- Never expose secrets, tokens, API keys or environment file contents.
- Never change live Supabase data/schema or perform production migrations without explicit authorization.
- Never modify `main`, merge a PR, publish an app, or perform financial actions.
- Do not claim a feature works merely because source code exists.
