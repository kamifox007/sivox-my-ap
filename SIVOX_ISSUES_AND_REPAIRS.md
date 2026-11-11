# SIVOX Issues and Repairs

Last reviewed: 2026-11-11

| ID | Area | Finding | Severity | Status | Evidence / next action |
|---|---|---|---|---|---|
| SIV-001 | Staff assignments | Accept/reject previously updated by ID only and returned true even when no row was changed. | High | Fixed on working branch; pending CI | `lib/services/staff_service.dart`: now requires pending status and checks returned updated IDs. |
| SIV-002 | Android release | Release build currently signs with debug signing config. | High | Open | Configure secure release signing only after owner supplies signing material through secure GitHub secrets; never commit keystore/passwords. |
| SIV-003 | Environment configuration | `.env` is tracked and bundled as an asset, while `.gitignore` also lists it. | High | Needs secret audit | Do not print file contents. Confirm only publishable values are present; rotate any privileged credential if one was exposed. |
| SIV-004 | Google Maps configuration | API key is embedded in Android manifest. | Medium | Open | Verify provider-side Android package/SHA restrictions and quotas. Do not reveal key or change provider settings without owner approval. |
| SIV-005 | Test coverage | Initially only one startup widget smoke test was found; no integration_test directory was present. | High | Partially improved | Added `test/auth_service_test.dart` for phone normalization; run CI before marking verified. Booking, QR and staff transition tests remain open. |
| SIV-006 | Supabase schema traceability | No checked-in supabase/migrations directory or SQL migrations were found in main tree. | High | Blocked for full certification | Obtain schema/migration export through an authorized, non-production-safe route. Do not infer RLS/RPC correctness from client code. |
| SIV-007 | Startup configuration | Supabase initialization has hard-coded fallback URL and publishable key values. | Medium | Open | Review intended deployment configuration and offline/error UX before changing. |
| SIV-008 | Android CI | No Android-specific workflow was found in main tree during initial review. | Medium | Workflow added on working branch; pending run | `.github/workflows/android-quality.yml` runs analyze, tests and debug APK build. |
| SIV-009 | Booking/QR/RLS | Full end-to-end booking, payment, QR and role-policy correctness has not yet been verified. | Critical | Open | PR #2 contains proposed booking-stage RPCs, ticket transfer, notification fan-out and RLS migrations; do not port or apply until dependencies, policy interactions and schema are independently validated against an isolated database. |

| SIV-010 | Error reporting | Error handlers truncated stack traces with `substring(0, 1000)` without checking length; short traces could throw a second error. | Medium | Fixed on working branch; CI pending | `lib/main.dart` now uses `_safeStackTrace` for nullable and short traces. |

## Change discipline
- Every repair must be tied to a root cause and a focused diff.
- Keep historical behavior unless evidence shows it is defective.
- Record exact commit and actual CI/test outcome after each repair.
- No production database writes, schema changes, secret rotation, merge or release without explicit owner approval.
