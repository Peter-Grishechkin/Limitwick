# Codex Bar

Codex Bar is a small macOS menu bar app that shows your remaining Codex usage limits. The top bar represents the five-hour limit; the bottom bar represents the weekly limit. A bar turns red when less than 20% remains. Values refresh every three minutes.

Click the bars to see the remaining percentages and the five-hour reset time in your Mac's local time zone, refresh the data, or quit. The bars turn gray when data is unavailable.

## Requirements

- macOS 13 or later.
- [Codex CLI](https://developers.openai.com/codex/cli/) installed and signed in with your ChatGPT account. The app uses the same account. Installing the Codex app does not necessarily install the CLI separately.
- Xcode Command Line Tools, only if building from source. If needed, run `xcode-select --install` in Terminal and follow the macOS prompts.

## Quick install: Apple Silicon Macs

1. Open the [latest release](https://github.com/frankydzoro/codex-bar/releases/latest) and download `CodexBar-macOS-Apple-Silicon.zip`.
2. Unzip the archive and move `CodexBar.app` to Applications.
3. Open the app. Its two bars appear in the menu bar. Make sure Codex CLI is installed and signed in, as described above.

The app is not signed with an Apple Developer certificate or notarized, so macOS may block its first launch. If you trust the app, open **System Settings → Privacy & Security** and allow it to open. You can also inspect the source and build the app yourself using the instructions below.

## Build from source

These steps work on Apple Silicon and Intel Macs with the development tools installed.

1. On the repository page, choose **Code → Download ZIP** and unzip the archive.
2. Open Terminal, type `cd ` (including the space), drag the extracted project folder into the Terminal window, and press Return.
3. Build the app:

   ```sh
   ./build.sh
   ```

4. Open the app:

   ```sh
   open build/CodexBar.app
   ```

The two bars appear in the menu bar. For regular use, move `CodexBar.app` from the `build` folder to Applications. To start it automatically, add it under **System Settings → General → Login Items**.

## Troubleshooting

If the bars are gray, click them to see the status. Check your internet connection and run `codex login status` in Terminal. If necessary, sign in with `codex login`, then choose **Refresh** in the app menu.

The app looks for the CLI at `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`, and `~/.local/bin/codex`. If it is installed elsewhere, update the `codexPaths` list in `Sources/CodexBar.swift` and rebuild.

The app needs five-hour and weekly limits to be available for your account. If Codex does not return one of those periods, its bar stays gray.

## How it works

The app runs the installed `codex app-server` and requests limits using `account/rateLimits/read`. It does not ask for your password or contain API keys or account details. Codex contacts OpenAI's services to retrieve the data; Codex Bar has no separate server. The Codex API may change. See the [app-server documentation](https://developers.openai.com/codex/app-server/) for details.

## Uninstall

Click the bars and choose **Quit Codex Bar**, then delete the app from Applications or the `build` folder. If you added it to Login Items, remove it there as well.
