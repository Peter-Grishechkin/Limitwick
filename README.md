# Limitwick

The app design shown in the video is outdated. You can see the current look below.

https://github.com/user-attachments/assets/11962353-805c-458b-8654-7c57faef7c5b

Limitwick is a small macOS menu bar app that shows how much of your **Codex** and **Claude Code** subscription usage is left. It tracks the five-hour and weekly limits, shows when each one resets, and can show when Codex or Claude Code is working right now.

- Track Codex, Claude, or both side by side.
- Two bars in the menu bar: five-hour limit on top, weekly limit below.
- Click for a panel with percentages, reset times, and time remaining, in one of four themes.
- Optional activity animation while Codex or Claude Code is working or using a tool.
- Optional notifications for low quota and confirmed resets.
- Sessions window: your recent Codex and Claude Code sessions as a grid of pixel mascots; click a tile to open the session.
- Picture-in-Picture window and 16 macOS desktop widget variants.
- Automatic refresh, refresh after wake, and built-in updates.

## Contents

- [Requirements](#requirements)
- [Install](#install)
- [Using Limitwick](#using-limitwick)
- [Settings](#settings)
- [Activity indicator](#activity-indicator)
- [Sessions](#sessions)
- [Notifications](#notifications)
- [Picture-in-Picture and widget](#picture-in-picture-and-widget)
- [Themes](#themes)
- [Refresh and updates](#refresh-and-updates)
- [Privacy](#privacy)
- [Troubleshooting](#troubleshooting)
- [Build and test](#build-and-test)

## Requirements

- A Mac with Apple Silicon and macOS 13 or later. The desktop widget requires macOS 14 or later.
- For Codex: the **Codex CLI**, signed in to your ChatGPT account. Installing the Codex or ChatGPT app does not necessarily install the CLI. Check with `codex login status` in Terminal.
- For Claude: **Claude Code** ([setup guide](https://code.claude.com/docs/en/setup)), signed in to your Claude subscription. Run `claude` in Terminal once to sign in. The Claude desktop app does not necessarily install the CLI.

You need only the tool for the service you want to track.

## Install

1. Download the Apple Silicon archive from the [latest release](https://github.com/frankydzoro/Limitwick/releases/latest).
2. Unzip it and move **Limitwick.app** to the Applications folder.
3. Open Limitwick. It appears in the menu bar, not in the Dock.
4. Codex is shown by default. To track Claude or both, right-click the menu bar icon, choose **Settings…**, and set **Show limits** to **Claude** or **Both**.

The app is locally signed and not notarized by Apple, so macOS may block the first launch. Open **System Settings → Privacy & Security** and allow Limitwick there.

### Updating from version 1.x

Limitwick 2.0 uses new app identifiers, so it installs as a new app rather than updating the old one in place. Version 1.x shows the update notice and opens the release page.

1. Install Limitwick 2.0 as described above and open it.
2. On launch, Limitwick quits all copies of version 1.x, including ones named **CodexBar.app**, moves them to the Trash and lists them. Copies already in the Trash are left there. Your settings are copied over, and installed Claude and Codex activity hooks are switched to the new app. If Codex hooks were switched, review and trust them in **Codex Settings → Hooks**.
3. Remove the old widgets from the desktop and add new ones from the widget gallery.
4. macOS asks again for permission to send notifications if you turned them on.

### Install with Agent

Claude Code, Codex, or another coding agent with Terminal access can install and set up Limitwick for you: check the requirements, install the app, choose what to track, and turn on the activity indicator. You only need to finish sign-in in the browser and, for Codex, trust the new hooks.

**1. Let the agent run commands without stopping.** The setup writes to `/Applications`, `~/.claude`, `~/.codex` and the app's preferences, so an agent in its default mode asks before almost every step. Start it in a more autonomous mode from any folder:

| Agent | Command | What it allows |
| --- | --- | --- |
| Claude Code | `claude --permission-mode auto` | Runs commands and edits on its own; still stops before risky actions. |
| Codex CLI | `codex --sandbox danger-full-access --ask-for-approval never` | Full access to your files and network with no prompts. Use it for this task, then start Codex normally again. |

In the Claude desktop app or the Codex app, choose the same level in the session's permission menu: the mode that lets the agent run commands without asking each time.

**2. Paste this prompt.** Change `Both` on the first line to `Codex` or `Claude` if you track only one service.

```text
Track: Both

Install and set up Limitwick (https://github.com/frankydzoro/Limitwick) on this Mac. Work on your own and stop only for steps that need me.

1. Check that the Mac is Apple Silicon (`uname -m` prints arm64) and runs macOS 13 or later. If not, stop and tell me.
2. For each service in "Track" make sure its CLI is installed and signed in:
   - Codex: `codex login status`. If the CLI is missing, install it with the official method from OpenAI's Codex docs. If it is not signed in, run `codex login` and tell me to finish sign-in in the browser.
   - Claude: `claude auth status`. If Claude Code is missing, install it with the official installer from https://code.claude.com/docs/en/setup. If it is not signed in, tell me to run `claude` in Terminal and sign in, then wait for me.
3. Find the latest release with the GitHub API or `gh release view -R frankydzoro/Limitwick`, and download the `*-macOS-Apple-Silicon.zip` asset with curl or gh into a temporary folder. Unzip it and check that Limitwick.app is inside.
4. If Limitwick is running, quit it (`osascript -e 'quit app "Limitwick"'`). Move an existing /Applications/Limitwick.app to the Trash and copy the new one there. Leave copies with other names, such as CodexBar.app: Limitwick removes version 1.x itself on first launch.
5. Set what to track: `defaults write local.limitwick.app providers -string <codex|claude|both>`, matching "Track".
6. Install the activity hooks for the tracked services:
   - Claude: `/usr/bin/python3 /Applications/Limitwick.app/Contents/Resources/useAnimations/claude-activity-setup.py install`
   - Codex: `/usr/bin/python3 /Applications/Limitwick.app/Contents/Resources/useAnimations/activity-setup.py install`
   These scripts add only Limitwick's own entries and keep my other settings and hooks.
7. Open the app with `open /Applications/Limitwick.app` and check with `pgrep -x Limitwick` that it is running. If macOS blocks it, tell me to allow it in System Settings → Privacy & Security, then check again.
8. Finish with a short report: what you installed or changed, the installed version, and what is left for me. If Codex hooks were installed, remind me to trust them in Codex Settings → Hooks or with /hooks in the Codex CLI, and to restart open Codex and Claude Code sessions.

Never ask me for passwords or tokens and do not print them. Do not change other apps, settings or hooks. Delete only the temporary files you created.
```

After the agent finishes, look for Limitwick in the menu bar. If limits do not load, see [Troubleshooting](#troubleshooting).

## Using Limitwick

### Menu bar indicator

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/menubar-dark.png">
  <img src="docs/images/menubar-light.png" alt="Menu bar indicator: normal, low quota, Codex and Claude together, and previous data" width="876">
</picture>

Each service is shown as a pair of bars:

- **Top bar:** remaining five-hour limit.
- **Bottom bar:** remaining weekly limit.

When **Both** is selected, Codex and Claude each get their own pair of bars with a small logo in front. A bar turns red when the remaining quota drops below the warning threshold (20% by default). If the last refresh failed, the bars are dimmed and keep the previous values. Hover over the icon for a tooltip.

### Panel

**Click** the menu bar icon to open the panel. For each service it shows:

- remaining five-hour and weekly quota as a percentage;
- when each limit resets: the time remaining ("RST 3d 4h") and below it the local date and time;
- a footer with the service name and the age of the data ("Codex · Updated 2 min ago"); after a failed refresh it reads "Codex · Previous data · Updated 12 min ago";
- under the card, the error message if the last refresh failed.

Click outside the panel or switch to another app to close it.

### Menu

**Right-click** the menu bar icon (or click with two fingers on a trackpad) to open the menu:

| Item | What it does |
|---|---|
| **Refresh** (⌘R) | Fetches fresh usage data now. |
| **Show / Hide Picture-in-Picture** | Opens or closes a movable window with the panel. |
| **Show / Hide Sessions** | Opens or closes the [Sessions window](#sessions). |
| **Settings…** (⌘,) | Opens Settings. |
| **About Limitwick** | Shows the version and a link to GitHub. |
| **Check for Updates…** | Checks for a new version. When one is available, this item shows its version number. |
| **Quit** (⌘Q) | Quits the app. |

## Settings

Open **Settings…** from the menu. The window has five sections.

### AI services

**Show limits** chooses what to track: **Codex**, **Claude**, or **Both**.

When Claude is tracked and Claude Code is missing, **Install Claude Code…** opens Terminal, runs the official installer and starts Claude Code so you can sign in. When it is installed, **Sign in to Claude…** opens Claude Code in Terminal; type `/login` there if limits do not load.

Theme, appearance, activity, threshold, and notifications are set separately for each service. With **Both** selected, **Settings for** switches between **Codex** and **Claude**, and the section titles name the service being edited. With one service selected, the settings apply to it.

### Appearance

- **Theme:** the look of the panel, menu, and Picture-in-Picture window. See [Themes](#themes).
- **Mode:** **Light**, **Dark**, or **Auto**. Auto follows the macOS appearance.
- **Show … activity in menu bar:** shows an animation next to the bars while the selected service is working. See [Activity indicator](#activity-indicator).

When **Both** is selected, each service's block in the panel uses that service's own theme and mode.

### Sessions window

- **Position:** **Above all windows** or **On the desktop**, under other windows and above the wallpaper.
- **Sessions:** how many tiles the window shows: **4**, **8**, or **16**.

See [Sessions](#sessions).

### Low quota

**Warn below:** from 1% to 99%, 20% by default. Below this level the bars and the filled part of the card turn red, even if notifications are off, and low quota alerts use the same level. Red appears only for this warning; the themes use other colors for normal values.

### Notifications

- **Low remaining quota:** notifies you when a limit drops below the threshold.
- **Confirmed quota reset:** notifies you when a limit has reset.
- **Notification Settings…:** opens macOS notification settings if alerts are blocked.

See [Notifications](#notifications) for details.

## Activity indicator

Limitwick can show a small animation to the left of a service's bars:

| Animation | Meaning |
|---|---|
| Spinner | The service is working on a request. |
| Terminal | The service is running a tool, such as a shell command. |
| Checkmark (briefly) | Work has finished. |

The indicator takes up space in the menu bar only while it is active. With **Reduce motion** turned on in macOS accessibility settings, a still image is shown instead of an animation.

The indicator uses *hooks*: small scripts that Codex or Claude Code runs on each event and that pass the event to Limitwick. They forward the event type, session and tool-call IDs, and the time. For the [Sessions window](#sessions) they also forward the kind of tool a call uses (edit, shell, read, search, web, agent, plan, MCP, or other), the name of the project folder (not its path), the bundle ID of the app that started the session and, for Claude Code, its entry point, process ID, and the Claude app's own session ID. Tool names, MCP server names, prompts, responses, commands, tool input, and tool output are never forwarded.

### Claude Code

1. In **Settings**, choose **Claude** under **Show limits**, or set **Settings for** to **Claude** when both services are shown.
2. Turn on **Show Claude activity in menu bar**. The box stays clear until the hooks are installed; checking it installs them and confirms. You can also use the **Install Claude hooks** button.
3. Start a new Claude Code session. Claude Code reads hooks only when a session starts. To include a session that is already open, type `/exit` in it, then run `claude --continue` to resume the same conversation.

The text below the checkbox shows the current status:

- *hooks are not installed:* click **Install Claude hooks**;
- *Waiting for activity:* the hooks are installed, but no events have arrived yet; start a new Claude Code session and send a request;
- *Receiving activity from Claude Code:* everything works.

To uninstall, click **Remove Claude hooks**. Only Limitwick's own entries are added to or removed from `~/.claude/settings.json` (or `$CLAUDE_CONFIG_DIR/settings.json`). Your other settings and hooks are kept. The hook script is stored in `~/Library/Application Support/Limitwick/`, so the hooks keep working after the app is moved or updated. Turning off the checkbox hides the indicator but leaves the hooks installed.

### Codex

1. In **Settings**, choose **Codex** under **Show limits**, or set **Settings for** to **Codex** when both services are shown.
2. Turn on **Show Codex activity in menu bar**. The box stays clear until the hooks are installed; checking it installs them and confirms. You can also use the **Install Codex hooks** button.
3. Review and trust the new hooks in **Codex Settings → Hooks** or with `/hooks` in the Codex CLI, then restart Codex sessions. Codex does not run hooks that have not been trusted.

The text below the checkbox shows the same statuses as for Claude Code. *Waiting for activity* means the hooks are installed but no events have arrived yet: trust them in Codex and start a new session.

To uninstall, click **Remove Codex hooks**. Only Limitwick's own entries are added to or removed from `~/.codex/hooks.json` (or `$CODEX_HOME/hooks.json`). The hook script is stored in `~/Library/Application Support/Limitwick/`, so the hooks keep working after the app is moved or updated. Hooks installed by an earlier version call a script inside the app; on launch Limitwick moves them to that copy and asks you to trust them in Codex again. You can also install them from Terminal:

```sh
/usr/bin/python3 '/Applications/Limitwick.app/Contents/Resources/useAnimations/activity-setup.py' install
```

See [how Limitwick works](docs/DETAILS.md) for the limits of activity detection.

## Sessions

**Show Sessions** in the menu opens a window with your Codex and Claude Code sessions of the last 24 hours, one tile each: a pixel mascot (a cloud for Codex, a little orange figure for Claude), a name, and the state. Sessions in the Claude app show their title from the app on up to two lines, once the app has named the session after its first turn; other sessions show the project folder. The tooltip names the folder. The cap colour tells apart sessions in the same folder.

| Tile | Meaning |
|---|---|
| Coloured mascot that moves, orange corner | The session is working: the Claude figure steps in place, the Codex cloud blinks the `_` of its `>_` face. |
| Typing hands (Claude) or a running `_` (Codex), an icon by the head | The session is running a tool. The icon shows its kind: a pencil for edits, `>_` for shell commands, an eye for reading, a magnifier for search, a globe for the web, a small figure for a subagent, a list for a plan, a plug for MCP tools, a gear for anything else. |
| A shake and a red *!* | A tool call has just failed. |
| Crawling orange stripes, blinking orange light, waving figure, *feed me!* | Claude Code is waiting for your permission. The caption gets hungrier as it waits: *hungry · 3m* after a minute, *starving · 12m* after five. |
| A jump and a green check | A turn has just finished; then the mascot falls asleep. An interrupted Codex turn falls asleep without the check and the green light. |
| Green light, name in white | The turn finished and you have not opened the session since. |
| Grey mascot with closed eyes, *z*, *done · 6m ago* | The session is idle or finished: one *z* under an hour, two under six hours, three after that. |
| Crossed-out eyes (Codex: `>x`), red light, *failed 3m ago* | The turn ended with an error in Claude Code. The red light stays until you open the session. |
| *?* instead of *z* | The session went silent for 30 minutes or its process exited during a turn. |

Click a tile to open the session: a session of the Claude app opens there, and a session in a terminal brings that terminal to the front. Opening a session, a new prompt in it, or **Mark All as Seen** in the window's right-click menu turns its green or red light off; the light also comes on for a session whose answer you already read in the app, because the window cannot tell. Drag the window by the space between tiles; right-click it or use the menu to hide it. **Position** and the number of tiles are in [Settings](#sessions-window).

Idle tiles stand still. With **Reduce motion** in the macOS Accessibility settings, every tile keeps one still pose, a waiting figure just holds up its hand, and tool icons stay. Tiles also stop moving while other windows cover the whole Sessions window.

Live states come from the [activity hooks](#activity-indicator), which the window uses even when the menu bar animation is off. Earlier sessions are read from disk when the window opens and every five minutes: the Claude app's list of Code sessions, the first lines of Claude Code transcripts, and Codex session files. Only session IDs, folder names, times, whether a session is archived, and the titles of Claude app sessions are read. A session shows orange stripes only when its hooks report a permission prompt; Codex hooks do not report one.

## Notifications

Both notification types are off by default. When you turn one on, macOS asks for permission to show alerts.

- **Low remaining quota** is sent once per limit and reset period, when the remaining quota first drops below the threshold.
- **Confirmed quota reset** is sent after a refresh confirms that a new period has started, so it can arrive a few minutes after the actual reset.

Notifications are sent only after a successful refresh. Limitwick cannot reliably detect a switch to another account, so alerts may be missed or refer to the previous account after you switch.

## Picture-in-Picture and widget

**Picture-in-Picture** is a separate window with the same cards as the panel, in the selected theme. Open it from the menu and drag it wherever you like. It stays open while the app runs, can be covered by other windows, and reopens in the same place the next time the app launches.

To add a **desktop widget** (macOS 14 or later):

1. Right-click the desktop and choose **Edit Widgets**.
2. Find **Limitwick** and choose a medium widget by theme, provider, and Light or Dark appearance.

Each of the four themes is available in Light and Dark for both Codex and Claude. You can place several variants side by side. Each keeps its own theme and appearance, and it receives limits even when its provider is hidden from the menu bar. Keep Limitwick running for fresh data. macOS controls when the widget redraws.

If you used the previous universal widget, remove it and add a new variant from the gallery.

## Themes

Choose a theme in **Settings → Appearance → Theme**. The images follow your GitHub light or dark mode and use illustrative values.

<table>
  <tr>
    <td align="center"><strong>Industrial</strong><br>
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/images/theme-industrial-dark.png">
        <img src="docs/images/theme-industrial-light.png" alt="Industrial theme with gauges and bars" width="396">
      </picture>
    </td>
    <td align="center"><strong>Dot Matrix</strong><br>
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/images/theme-dots-dark.png">
        <img src="docs/images/theme-dots-light.png" alt="Dot Matrix theme" width="396">
      </picture>
    </td>
  </tr>
  <tr>
    <td align="center"><strong>Paper</strong><br>
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/images/theme-paper-dark.png">
        <img src="docs/images/theme-paper-light.png" alt="Paper theme" width="396">
      </picture>
    </td>
    <td align="center"><strong>Terminal</strong><br>
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/images/theme-terminal-dark.png">
        <img src="docs/images/theme-terminal-light.png" alt="Terminal theme" width="396">
      </picture>
    </td>
  </tr>
</table>

The panel, the Picture-in-Picture window, and the widgets show the same card. Themes from earlier versions (Classic and Capsules) were removed in 2.2; a saved choice of either one switches to Industrial. Terminal is set in [VT323](https://fonts.google.com/specimen/VT323) (SIL Open Font License, `Resources/fonts/OFL-VT323.txt`).

## Refresh and updates

- Usage refreshes automatically every three minutes, after your Mac wakes from sleep, and when you choose **Refresh**.
- After repeated errors, the interval grows up to 24 minutes and returns to normal after a successful refresh.
- Codex usage also updates as soon as Codex reports a new rate-limit event.

Limitwick checks for new versions quietly at launch and once a day. When an update is available, the menu highlights it, and a red dot appears on the menu bar icon for a new major version. Choose the menu item to see what changed and install the update. Version 1.4.2 and older need a one-time manual upgrade before the built-in updater works.

## Privacy

- Limitwick does not ask for your password and does not store credentials. It uses the sign-in of your existing Codex CLI and Claude Code.
- Codex usage comes from a local `codex app-server`. Claude usage comes from running `/usage` in Claude Code in a hidden terminal. While doing so, Claude Code runs with hooks and MCP servers turned off and with no tools allowed.
- The app has no server of its own. Codex and Claude Code contact their own services, and update checks contact GitHub.
- Widgets read local quota snapshots containing values, reset times, and update status. The snapshots contain no credentials or account IDs.
- The Sessions window keeps its tiles in `~/Library/Application Support/Limitwick/sessions.json`: session IDs, folder names, Claude app session titles, states, how the last turn ended (failed, interrupted, or lost), and times. The kind of tool a session is running stays in memory. To fill in earlier sessions it reads only IDs, folders, times, the archived flag, and the session titles that the Claude app generates from your conversations, from local Claude and Codex session files; never prompts or replies.

## Troubleshooting

| Problem | What to do |
|---|---|
| **Codex CLI not found** | Apps opened from Finder can have a shorter PATH than Terminal. Install the Codex CLI in a standard location, such as through npm or Homebrew. |
| **Codex login or network error** | Run `codex login status`, sign in if needed, check your connection, and choose **Refresh**. |
| **Claude Code not found or not signed in** | Install Claude Code, run `claude` in Terminal, sign in, and choose **Refresh**. |
| **Claude usage unavailable** | Run `/usage` in Claude Code to check the account and connection. Limitwick reads Claude Code's on-screen output, which can change when Claude Code updates. Reset times that cannot be read are shown as unavailable. |
| **Bars are dimmed** | The last refresh failed, so the previous values are shown. The panel dims that service's card too, marks it "Previous data" in the footer with the age of the data, and shows the error under the card. |
| **A limit is missing** | The service did not report that limit. Reset times appear only when the service provides them. |
| **No activity animation for Claude** | Check the status text on the Claude settings in **Settings**. Install the hooks if needed and start a new Claude Code session. |
| **No activity animation for Codex** | Check the status text on the Codex settings in **Settings**. Install the hooks if needed, trust them in Codex, and start a new Codex session. |
| **Widget gallery shows old widgets after an update** | Another copy of the app, for example a second **Limitwick.app** or **CodexBar.app** in Downloads or Applications, can supply its old widgets. **Settings** lists such copies under **Other copies**. Keep one copy in Applications, move the rest to the Trash, empty the Trash, and log out and back in. Then remove the old widget from the desktop and add a new one from the gallery. |
| **No notifications** | Turn on the notification type in Settings and allow alerts in **Notification Settings…**. |
| **macOS blocks the app** | Allow it in **System Settings → Privacy & Security**. The app is not notarized by Apple. |

## Build and test

Building from source requires Xcode Command Line Tools. The first build needs an internet connection to download Sparkle and Lottie. From the repository folder:

```sh
./build.sh
open build/Limitwick-Development.app
./Tests/run.sh
```

README images are rendered from the theme and menu bar code with fixed demo values. Regenerate them after a design change with `./scripts/render-screenshots.sh`; it writes `docs/images` and compresses the files with `oxipng` if it is installed.

The default build is `build/Limitwick-Development.app`. It uses its own identifiers and widget storage, so it does not interfere with the installed app. It is locally signed and not notarized. See [publishing updates](docs/RELEASING.md) for release instructions and [how Limitwick works](docs/DETAILS.md) for technical details.

## License

[MIT License](LICENSE) · [Español](docs/LICENSE.es-419.md) · [Русский](docs/LICENSE.ru.md)

Limitwick is an independent project. It is not affiliated with, sponsored by, or endorsed by Anthropic or OpenAI. Claude, Codex and other product names belong to their respective owners.
