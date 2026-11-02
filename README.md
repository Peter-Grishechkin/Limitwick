# Codex Bar

A small macOS menu bar app showing remaining Codex usage. The top bar is the five-hour limit; the bottom bar is the weekly limit. A bar turns red below 20%. Click the bars to open two circular indicators showing the remaining percentages, each reset time, and the last successful update. Click outside the panel or switch to another app to close it. Right-click the bars (or use a two-finger click on a trackpad) for Refresh and Quit.

The app refreshes every three minutes and can also refresh on demand. If an update fails, the bars are dimmed and the panel shows the reason and the age of the previous values. They remain dimmed while a retry is in progress. An unavailable limit is shown as unavailable. Other window durations are listed in the panel with their actual durations; they never replace the five-hour or weekly bars. Conflicting values for the same duration are reported as unavailable. Values are kept only while the app is running.

## Requirements

- macOS 13 or later.
- Codex CLI, installed and signed in to a ChatGPT account. Check with `codex login status` in Terminal. Installing the Codex app does not necessarily install the CLI.
- Xcode Command Line Tools to build from source.

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
- **Previous data shown:** the last attempt failed. The menu reports the error and the time of the last successful update; retry when the issue is resolved.
- **Limit unavailable:** the CLI did not return that window. Reset times are shown only when provided by Codex.

Codex Bar runs `codex app-server` and reads `account/rateLimits/read`. It does not ask for your password or store credentials. Codex contacts OpenAI; this app has no separate server. Codex CLI protocol changes can affect compatibility.

To quit, choose Quit Codex Bar from its menu. Delete the app to uninstall it and remove any login item you added manually.
