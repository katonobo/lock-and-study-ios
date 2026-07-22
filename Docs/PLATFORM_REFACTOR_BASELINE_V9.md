# Platform Foundation v9 Baseline

Recorded on 2026-07-22 (Asia/Tokyo) before the v9 implementation.

## Source baseline

- Git commit: `e84c6a1` (`Refactor scalable content platform v7`)
- Branch: `main`
- Bundle ID: `com.ameneko.lockandstudy`
- App Group: `group.com.ameneko.lockandstudy`
- A pre-existing local edit to `LockAndStudy/Resources/Localizable.xcstrings` was intentionally excluded from the v9 implementation scope.

## Verification baseline

- `./scripts/verify`: passed
- Test result: 151 passed, 0 failed, 0 skipped
- Simulator: iPhone 16 Pro Max, iOS 18.4, arm64
- Static gates passed: content validation, released-content verification, draft isolation, legacy identifiers, StoreKit catalog, privacy manifest, release safety, and release readiness
- Result bundle: `.build/VerifyDerivedData/Logs/Test/Test-LockAndStudy-2026.07.22_16-15-12-+0900.xcresult`

Existing tests are not to be deleted to make the refactor pass. Any replacement must preserve or increase coverage and document the compatibility reason.

## Released content baseline

| Pack | Pack ID | Content version | Released items | Free items |
| --- | --- | --- | ---: | ---: |
| English vocabulary | `english3000.v1` | `mvp-3000-ja-v4.0.0` | 3,000 | 250 (5 levels × 50) |
| Takken 2026 | `takken2026.v1` | `takken-2026-free-v1` | 100 reviewed questions | 100 |

Existing pack IDs and item IDs are migration invariants.

## Product IDs

- `com.ameneko.lockandstudy.pack.english3000.v1`
- `com.ameneko.lockandstudy.pack.takken2026.v1`
- `com.ameneko.lockandstudy.pass.monthly`
- `com.ameneko.lockandstudy.pass.yearly`

The two pack mappings must remain restorable after catalog updates. The two pass IDs are the only product IDs intentionally fixed in application configuration.

## App Group and UserDefaults keys

- `lockandstudy.onboarding.completed`
- `lockandstudy.authorization.approved`
- `lockandstudy.authorization.lost`
- `lockandstudy.selection.data`
- `lockandstudy.selection.completed`
- `lockandstudy.policy.v1`
- `lockandstudy.policy.v1.backup`
- `lockandstudy.lock.enabled`
- `lockandstudy.unlock.session.v1`
- `lockandstudy.unlock.until`
- `lockandstudy.pending.unlock.request.v1`
- `lockandstudy.pending.policy.change.v1`
- `lockandstudy.pending.management.reset.v1`
- `lockandstudy.emergency.records.v1`
- `lockandstudy.diagnostics.shield.at`
- `lockandstudy.diagnostics.shield.result`
- `lockandstudy.diagnostics.relock.at`
- `lockandstudy.diagnostics.relock.result`
- `lockandstudy.commerce.snapshot.v1`
- `lockandstudy.commerce.product-mappings.v1`
- `lockandstudy.content.selected.pack`
- `lockandstudy.settings.v1`
- Legacy first-run keys: `lockandstudy.experience.vocabulary.first-run.completed`, `lockandstudy.experience.takken.first-run.completed`
- Existing pack first-run keys: `lockandstudy.pack.english3000.v1.first-run.completed.v1`, `lockandstudy.pack.takken2026.v1.first-run.completed.v1`

## LearningDataStore files

Application Support root: `LockAndStudy/`

- `progress.v1.json`
- `events.v1.json`
- `unlock-bundle.v1.json`
- `experience-unlock-bundle.v2.json`
- `vocabulary-pending-preview.v1.json`
- `takken-pending-preview.v1.json`
- `answer-transactions.v1.json`
- `legacy-imports.v1.json`
- `lockandstudy-learning-export.json`
- `answers/{yyyy-MM}.ndjson`
- Corrupt-file backups use the `.corrupt-{timestamp}.bak` suffix.

## Schema baseline

- Released study-pack catalog: v1 flat array
- `LearningDataStore.schemaVersion`: 1
- Legacy `UnlockLearningBundleSnapshot`: schema 1
- `ExperienceUnlockBundleSnapshot`: schema 2
- Shared pending unlock request: schema 1
- App Group unlock session: `lockandstudy.unlock.session.v1`

## Safety invariants

- Family Controls, Shield Configuration, Shield Action, and Device Activity targets and entitlements remain unchanged.
- Content failure must neither grant an unconditional unlock nor create a permanent lock.
- Safe Fallback and free samples remain bundled and independent of commerce.
- Existing purchase entitlements, legacy grants, learning history, and relock recovery remain readable throughout migration.
