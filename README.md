# QuotaBar

Native SwiftUI quota monitor for **macOS 14+** and **iOS/iPadOS 17+**. View every quota window directly in the macOS menu bar, with small and medium WidgetKit widgets and an optional iCloud companion.

**Version: 0.1.2 — public source preview.** The interface is currently in French.

QuotaBar displays the remaining **ChatGPT subscription quotas used by Codex**, not an exact token balance or every limit across ChatGPT features. Reading quotas does not start a model turn.

## macOS

1. Open `QuotaBar.xcodeproj` and select the **QuotaBar-macOS** scheme.
2. For a local macOS installation, run `./Scripts/install-macos.sh`. This signs the bundles locally, installs the app in `~/Applications`, registers the widget, and launches the app. Apple-team signing is required for iCloud; see below.
3. The app detects an installed official CLI and uses its existing local session. Choose another executable in settings if needed. The sign-in button opens the official browser flow.
4. Each window appears directly in the menu bar, for example **5 h 72 % · 7 j 84 %**, with its remaining percentage. Quotas refresh at launch, on demand and 30 seconds after each automatic read, even with the panel closed. This is near real time, subject to service update delays.
5. Add desktop widgets using **Edit Widgets → QuotaBar**. Widgets display the `codex` group, or the first available group, independently of the group selected for the menu bar.

Failed reads add a warning to the menu bar. The panel shows all available windows, reset deadlines and the last successful read. Switching accounts also switches the local CLI account.

## iPhone and iPad

The iOS app is a companion to the Mac. Enable **Synchroniser avec iCloud** on both devices using the same Apple account, then refresh on the Mac.

Only quota groups and their read timestamp are synchronized using iCloud key-value storage. ChatGPT credentials and account identifiers are not copied to iCloud. The Mac must be awake with QuotaBar running to publish new readings.

iCloud delivery is asynchronous. The iOS app receives changes while active and writes them to its widget's App Group cache. After a long period without opening the iOS app, its widget may retain an older snapshot; open the app to receive the latest synchronized values.

## Apple signing and capabilities

`Scripts/check.sh` uses unsigned builds to validate compilation only. Such bundles lack effective sandbox entitlements, and PluginKit rejects the widget.

`Scripts/build-macos.sh` instead applies local ad-hoc signatures, including the widget sandbox entitlement. `Scripts/install-macos.sh` registers the containing app and widget from `~/Applications`. Local PluginKit registration has been verified without an Apple development certificate. This is not a notarized distribution build and does not enable iCloud; gallery rendering still needs functional confirmation. On the test Mac, shared-container writes were denied with Cocoa error 513 under the local signature, so the local widget cannot yet be considered a working quota display. A properly provisioned Apple-team build is the next path to validate shared-container access.

For iCloud, iPhone installation and a provisioned distribution build, configure Apple-team signing:

Choose the same Apple Developer team for all four targets in **Signing & Capabilities**:

| Targets | Bundle identifier |
| --- | --- |
| QuotaBar-macOS / QuotaBar-iOS | `net.plumia.QuotaBar` |
| QuotaWidgets-macOS / QuotaWidgets-iOS | `net.plumia.QuotaBar.widgets` |

- All four targets: enable **App Groups** and register `group.net.plumia.QuotaBar`.
- Both apps: enable **iCloud → Key-value storage** using `$(TeamIdentifierPrefix)net.plumia.QuotaBar` on both platforms.

Use your own identifiers if these are unavailable to your team. Update the project, entitlement files and `SnapshotStore.groupID` consistently. Keep the iCloud key-value identifier identical across platforms. These identifiers are configuration names, not credentials; no developer team or provisioning profile is included.

The Mac app is not sandboxed because it launches the locally installed CLI. Widget extensions are sandboxed. This architecture targets direct signed/notarized macOS distribution; Mac App Store distribution would require a different data-access architecture.

Launch at login uses `SMAppService`. Enable it from a stable, signed app installed in Applications, rather than from a temporary build folder.

## Data handling

- QuotaBar communicates with the installed CLI through local standard input/output using the official account protocol. It does not directly read `auth.json` or store passwords or authentication tokens.
- The local CLI manages its own authentication outside this repository.
- Quota snapshots are written atomically to a JSON file in the App Group container; app preferences remain local. Optional iCloud synchronization contains quota values and timestamps only.
- Build products, local environments, authentication files, signing material, user-specific Xcode metadata and diagnostics are excluded from Git.
- The optional `probe.sh` script prints remaining quota values, not authentication tokens. Do not publish your personal probe output or local diagnostic files.

## Accuracy and refresh behavior

- Remaining percentage is `clamp(100 - usedPercent, 0…100)`, rounded down for display.
- Multi-group `rateLimitsByLimitId` responses take precedence over the legacy `rateLimits` view.
- Missing windows remain unavailable. Their duration is never assumed to be five hours or seven days.
- Expired windows display a dash until refreshed; the app never assumes a reset restored 100%.
- After 15 minutes without a successful read, menu percentages become dashes. The panel and widgets retain historical values with a stale indicator.
- WidgetKit controls actual widget delivery. Refresh requests are coalesced when quota values do not change.
- Account reads have a 25-second deadline; browser sign-in has a 180-second deadline. Subprocesses are closed after use, and raw diagnostics are not retained.

## Development

No third-party runtime dependencies. Requires Swift 6 and Xcode with the relevant macOS/iOS SDKs. The current source uses SDK declarations available in Xcode 26 or newer while retaining macOS 14/iOS 17 deployment targets.

```sh
swift test
./Scripts/check.sh
```

Build a locally signed macOS app (iCloud disabled):

```sh
./Scripts/build-macos.sh
```

Install/update this local build, register its widget and launch it:

```sh
./Scripts/install-macos.sh
```

Read the current local account's quotas:

```sh
./Scripts/probe.sh
```

The generated Xcode project is checked in. `VERSION` is the source for the marketing version used by the project generator. To regenerate the project or geometric app icon:

```sh
python3 Scripts/generate-project.py
python3 Scripts/make-icon.py
```

The project generator rewrites project settings and entitlements. Preserve any custom signing settings in the generator before running it again.

| Directory | Purpose |
| --- | --- |
| Sources/QuotaCore | Quota decoding and calculations |
| Sources/QuotaBar | Native app, local CLI transport and iCloud integration |
| Sources/QuotaWidgets | Widget views and timelines |
| Configuration | Property lists and entitlement templates |
| Tests | Quota and JSON-RPC transport tests |

## Validation status

Fourteen unit/transport tests pass. Unsigned macOS and iOS Simulator builds pass, including both widget extensions. Automatic reading and local quota persistence have been verified in the running Mac app with the panel closed.

Local widget registration is now verified. Actual widget rendering/data display, cross-device iCloud synchronization, physical iPhone installation, interactive sign-in and launch at login still require functional validation. iCloud and iPhone deployment additionally require configured Apple-team signing. No signed/notarized binary is distributed. See [VALIDATION.md](VALIDATION.md) for the detailed development record and [CHANGELOG.md](CHANGELOG.md) for version history.

## References

- [Official account protocol and quotas](https://learn.chatgpt.com/docs/app-server): `initialize`, `initialized`, `account/rateLimits/read`, `account/login/start`.
- [Apple: creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension).
