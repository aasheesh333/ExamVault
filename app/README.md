# ExamVault — Flutter app

This directory is the Flutter application only. The project's real
documentation lives one level up:

- **[`../README.md`](../README.md)** — what ExamVault is, the architecture, the
  load-bearing decisions, how to run everything end to end
- **[`../docs/`](../docs/)** — data pipeline (`DATA_PIPELINE.md`), privacy
  policy (`PRIVACY.md`), Play Store submission (`PLAY_STORE.md`)
- **[`../infra/`](../infra/)** — the Cloudflare Worker + R2 bucket that serve
  the feed and roll indexes
- **[`../.github/SECRETS.md`](../.github/SECRETS.md)** — the build-time secrets
  and why each exists

## What lives here

| Path | Contents |
|---|---|
| `lib/` | the app: `features/`, `data/`, `domain/`, `core/`, `providers/` |
| `test/` | the suite CI runs on every push, including `live_edge_integration_test.dart` (live network, opt-in via `EV_LIVE=1`) |
| `android/`, `ios/` | platform projects; the release manifest, signing and notification config live under `android/` |
| `web/` | **handcrafted source**, not build output: boot splash (`index.html`), branded `manifest.json`, icons, favicon — tracked in git on purpose |
| `assets/google_fonts/` | bundled fonts, declared in `pubspec.yaml` |

## Run

```sh
flutter pub get
flutter run        # works with no credentials at all; push degrades to a no-op
```

Point it at the real edge explicitly (also the compiled-in default):

```sh
flutter run \
  --dart-define=EV_CDN_BASE=https://examvault-edge.aasheeshkatheriya.workers.dev
```

## Verify

```sh
flutter analyze --fatal-infos
flutter test
dart format --output=none --set-exit-if-changed lib test tool   # CI checks this too
```
