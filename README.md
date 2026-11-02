# Codex Bar

A small macOS menu bar app showing remaining Codex usage. The top bar is the five-hour limit; the bottom bar is the weekly limit. A bar turns red below 20%. Click the bars to open the limits panel showing the remaining percentages, each reset time, and the last successful update. The default Classic theme uses circular indicators. Click outside the panel or switch to another app to close it. Right-click the bars (or use a two-finger click on a trackpad) for Refresh, Settings, About Codex Bar, Check for Updates, and Quit. Settings offers six panel themes and Light, Dark, or Auto appearance. Auto follows macOS; your selection is saved between launches.

The app refreshes every three minutes and can also refresh on demand. If an update fails, the bars are dimmed and the panel shows the reason and the age of the previous values. They remain dimmed while a retry is in progress. An unavailable limit is shown as unavailable. Other window durations are listed in the panel with their actual durations; they never replace the five-hour or weekly bars. Conflicting values for the same duration are reported as unavailable. Values are kept only while the app is running.

Check for Updates uses Sparkle to download and install signed updates and relaunch the app after confirmation. Checks are manual. Version 1.4.2 and older must be upgraded manually once before they can use this feature.

## Requirements

- macOS 13 or later.
- Codex CLI, installed and signed in to a ChatGPT account. Check with `codex login status` in Terminal. Installing the Codex app does not necessarily install the CLI.
- Xcode Command Line Tools and an internet connection for the first source build (to download the pinned Sparkle framework).

## Download

Download [Codex Bar v1.5.1 for Apple Silicon](https://github.com/frankydzoro/codex-bar/releases/tag/v1.5.1), unzip the archive, and move CodexBar.app to Applications. The release requires macOS 13 or later and a signed-in Codex CLI.

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

Build and test the exact app, create a ZIP preserving framework symlinks with `ditto -c -k --sequesterRsrc --keepParent`, then run `./scripts/prepare-appcast.sh VERSION PATH_TO_RELEASE_ZIP`. Upload that exact ZIP to the GitHub release before publishing the updated appcast on main. Verify the published feed and test installation from a previous Sparkle-enabled version. Version 1.4.2 has no Sparkle updater, so users must install the first Sparkle-enabled version manually.
