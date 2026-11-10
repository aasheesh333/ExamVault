# Branding assets

Generated from the app's own design tokens, not downloaded.

| File | Used for |
|---|---|
| `app_icon_512.png` | Play Store listing icon (512×512, no alpha required) |
| `app_icon_foreground_512.png` | Adaptive-icon foreground source |

The launcher icons live in `android/app/src/main/res/mipmap-*/` and are **not**
bundled into the app binary; these copies exist so the store listing and any
future platform (iOS, PWA) uses the same mark.

Regenerate with:

```sh
python3 tools/branding/make_icons.py
```

The mark is a shield (the vault) with a keyhole, drawn in the app's own Royal
Electric Blue on the Deep Navy canvas. Before this existed the app shipped
Flutter's default logo, which is the first thing a store reviewer sees.
