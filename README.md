# Codex Bar

A small macOS menu bar app showing remaining Codex usage. The top bar is the five-hour limit; the bottom bar is the weekly limit. A bar turns red at or below the low-quota threshold, which defaults to 20%. Click the bars to open the limits panel showing the remaining percentages and each reset time. The default Classic theme uses circular indicators. Click outside the panel or switch to another app to close it. Right-click the bars (or use a two-finger click on a trackpad) for Refresh, Settings, About Codex Bar, Check for Updates, and Quit. Settings offers six themes for the panel, menu and windows, and Light, Dark, or Auto appearance. Auto follows macOS; your selection is saved between launches.

The app listens for Codex rate-limit events and requests a fresh snapshot when one arrives. It also refreshes every three minutes and can refresh on demand; event delivery for other Codex sessions is not guaranteed. If an update fails, the bars are dimmed and the panel shows the reason and the age of the previous values. They remain dimmed while a retry is in progress. An unavailable limit is shown as unavailable. Other window durations are listed in the panel with their actual durations; they never replace the five-hour or weekly bars. Conflicting values for the same duration are reported as unavailable. Values are kept only while the app is running.

Check for Updates shows the release’s Changes before Sparkle downloads and installs the signed update and relaunches the app after confirmation. Checks are manual. Version 1.4.2 and older must be upgraded manually once before they can use this feature.

## Themes

Choose from six panel designs in **Settings → Appearance**. Each theme supports Light, Dark, and Auto modes; Auto follows macOS. The examples below use Dark mode and illustrative quota values.

<table>
  <tr>
    <td align="center"><strong>Classic</strong><br><img src="docs/images/classic.png" alt="Classic theme with circular quota indicators" width="340"></td>
    <td align="center"><strong>Industrial</strong><br><img src="docs/images/industrial.png" alt="Industrial theme with gauges and bars" width="340"></td>
  </tr>
  <tr>
    <td align="center"><strong>Dot Matrix</strong><br><img src="docs/images/dots.png" alt="Dot Matrix theme" width="340"></td>
    <td align="center"><strong>Paper</strong><br><img src="docs/images/paper.png" alt="Paper theme" width="340"></td>
  </tr>
  <tr>
    <td align="center"><strong>Capsules</strong><br><img src="docs/images/capsules.png" alt="Capsules theme" width="340"></td>
    <td align="center"><strong>Terminal</strong><br><img src="docs/images/terminal.png" alt="Terminal theme" width="340"></td>
  </tr>
</table>

Right-click the menu bar indicator and choose **Settings** to change the theme, appearance, notification preferences, and low-quota threshold.

## Refresh and notifications

The panel shows the local reset date and time remaining. If a reset time has passed, wait for a successful refresh to confirm the next one. Codex Bar refreshes after waking and normally every three minutes; repeated failures lengthen the delay to at most 24 minutes. Refresh in the context menu remains available between requests.

Settings can enable separate low-quota and confirmed-reset notifications. Both are off by default. The low threshold defaults to 20% and can be set from 1% to 99%; it also controls warning colors even when notifications are off. macOS asks for permission when you enable an alert; if notifications are blocked, use Notification Settings in the app. Alerts require a successful response and a future reset date. Reset alerts arrive only after a refresh confirms a new reset period, so they may be delayed. Delivery markers and reset dates are stored locally and pruned during successful refreshes after 30 days (for reset dates, 30 days after the reset); quota percentages and account identifiers are not stored. Codex Bar cannot reliably detect an account switch, so alerts can be missed or associated with the previous account after switching.

## Requirements

- macOS 13 or later.
- Codex CLI, installed and signed in to a ChatGPT account. Check with `codex login status` in Terminal. Installing the Codex app does not necessarily install the CLI.
- Xcode Command Line Tools and an internet connection for the first source build (to download the pinned Sparkle framework).

## Download

Download [Codex Bar v1.7.4 for Apple Silicon](https://github.com/frankydzoro/codex-bar/releases/tag/v1.7.4), unzip the archive, and move CodexBar.app to Applications. The release requires macOS 13 or later and a signed-in Codex CLI.

## Build and run

From this folder in Terminal:

```sh
./build.sh
open build/CodexBar.app
```

The build is locally signed and is not notarized by Apple. A downloaded archive or extracted folder may carry a macOS quarantine marker and trigger a security warning, including for files built inside it. Only run source you trust; Apple's Privacy & Security settings provide a way to open a trusted app. Alternatively, create a fresh local folder and write the trusted source files there before building. The app appears in the menu bar, not in the Dock.

## Tests

```sh
./Tests/run.sh
```

The tests exercise response parsing, additional and conflicting windows, malformed or oversized streams, authentication errors, timeout, cancellation, and a missing executable with a local fake Codex process. They do not change your account.

## Troubleshooting

- **Codex CLI not found:** the app searches its inherited PATH and common Homebrew, local, npm, Volta, and Cargo locations. GUI apps may inherit a shorter PATH than Terminal. Install the CLI in a standard location if necessary.
- **Login or network error:** run `codex login status` in Terminal, sign in if needed, check the connection, and choose Refresh in the app menu.
- **Previous data shown:** the last attempt failed. The limits panel reports the error and the time of the last successful update; retry when the issue is resolved.
- **Limit unavailable:** the CLI did not return that window. Reset times are shown only when provided by Codex.

Codex Bar runs `codex app-server` and reads `account/rateLimits/read`. It does not ask for your password or store credentials. Codex contacts OpenAI; update checks contact GitHub, and this app has no separate server. Codex CLI protocol changes can affect compatibility.

To quit, choose Quit from the context menu. Delete the app to uninstall it and remove any login item you added manually.

## Publishing updates

Sparkle 2.10.1 is downloaded from its official GitHub release and checked against the SHA-256 in `build.sh`. The appcast is `appcast.xml` on the repository's main branch. Each future release must be signed with the `codex-bar-updates` Sparkle key in the macOS login keychain. Keep a secure backup of the key: ad hoc signed builds cannot rely on Developer ID key rotation if it is lost. Never commit the private key.

Build and test the exact app, create a ZIP preserving framework symlinks with `ditto -c -k --sequesterRsrc --keepParent`, publish that exact ZIP in the GitHub release with a non-empty Markdown `## Changes` section, then run `./scripts/prepare-appcast.sh VERSION PATH_TO_RELEASE_ZIP`. The script copies that section into the update prompt. Publish the updated appcast on main after the release is available. Verify the published feed and test installation from a previous Sparkle-enabled version. Version 1.4.2 has no Sparkle updater, so users must install the first Sparkle-enabled version manually.
