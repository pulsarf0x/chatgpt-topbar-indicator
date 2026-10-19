# Changelog

## 0.1.2 — 2026-10-19

- Seal local macOS app/widget bundles with ad-hoc signatures and apply the widget sandbox entitlement required by PluginKit.
- Transfer snapshots through an atomic shared-container file instead of preferences that reject writes from the Mac host.
- Add a local installer that registers the containing app and widget from the user’s Applications folder.
- Distinguish local widget builds from Apple-team-signed iCloud builds in settings.
- Confirm local PluginKit registration. Local shared-container writes remain denied (Cocoa error 513); quota display in the widget is not yet validated.

## 0.1.1 — 2026-10-19

- Fix the macOS menu bar showing only an icon: use a text-only menu bar item so all remaining quota percentages stay visible without clicking.
- Preserve automatic refresh and access to the details panel.

## 0.1.0 — 2026-10-19

Initial public source release.

- Native macOS menu bar application with every quota window visible without a click.
- Automatic refresh every 30 seconds while the app is running.
- Official local account protocol integration with browser sign-in support.
- Quota details, reset deadlines, stale-data indicators and launch-at-login setting.
- Small and medium WidgetKit extensions for macOS and iOS.
- iPhone/iPad companion with optional iCloud quota snapshot synchronization.
- Fourteen tests for quota calculations, response parsing and subprocess transport.

Apple signing, App Groups and iCloud setup are required to validate the widgets and
cross-device synchronization. Physical iPhone installation and the interactive
sign-in flow have not yet been validated. No signed/notarized binary is distributed.
