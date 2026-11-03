# How Limitwick works

## Refresh and notifications


The panel shows the local reset date and time remaining. If a reset time has passed, wait for a successful refresh to confirm the next one. Limitwick refreshes after waking and normally every three minutes; repeated failures lengthen the delay to at most 24 minutes. Refresh in the context menu remains available between requests.

Settings can enable separate low-quota and confirmed-reset notifications. Both are off by default. The low threshold defaults to 20% and can be set from 1% to 99%; it also controls warning colors even when notifications are off. macOS asks for permission when you enable an alert; if notifications are blocked, use Notification Settings in the app. Alerts require a successful response and a future reset date. Reset alerts arrive only after a refresh confirms a new reset period, so they may be delayed. Delivery markers and reset dates are stored locally and pruned during successful refreshes after 30 days (for reset dates, 30 days after the reset); notification records do not contain quota percentages or account identifiers. Limitwick cannot reliably detect an account switch, so alerts can be missed or associated with the previous account after switching.


## App updates

Limitwick checks for compatible releases quietly at launch and once a day. When an update is available, the context menu offers to update and shows its version. A red dot appears on the menu bar icon for an update to a new major version. Select the menu item to review and install it; update checks do not show automatic alerts. If a check fails, the last known update remains visible until a successful check finds no update or the app version changes.

## Widget


On macOS 14 or later, open the desktop widget gallery and find **Limitwick**. Choose from 24 horizontal medium widgets. Each of the six themes comes in Light and Dark for Codex and Claude. The appearance and provider are fixed for each variant. Remove the old universal widget and add your chosen variants from the gallery.

Widgets read a local quota snapshot for their provider. Limitwick checks which widgets are installed at launch, after wake, when you refresh manually, and every three minutes. A provider with an installed widget can refresh even when it is hidden in the menu bar. Keep Limitwick running for fresh data. macOS controls when widgets redraw, so their values may lag behind the app.


## Data and connectivity

Limitwick runs `codex app-server` and reads `account/rateLimits/read`. It also listens for rate-limit events, but delivery from other Codex sessions is not guaranteed. Other window durations appear in the panel; conflicting values for the same duration are shown as unavailable.

The app does not ask for your password or store credentials. Codex contacts OpenAI, update checks contact GitHub, and the app has no separate server. Changes to the Codex CLI protocol can affect compatibility.

## Codex activity indicator

Limitwick can show activity to the left of its quota bars. Turn it on or off with “Show Codex activity in menu bar” in Settings; it is on by default. Turning it off stops the listener and hides the indicator, but leaves installed Codex hooks in place. This optional integration uses Codex lifecycle hooks. It shows a loading animation while a detected turn is working, a terminal animation while a supported tool is running, and a checkmark briefly when all detected turns have stopped. These events do not establish when an answer is being streamed or whether every kind of user input is pending, so the edit and alert animations are not used yet.

To enable the integration, run the following command after installing the app in `/Applications` (adjust the app name if needed):

```sh
/usr/bin/python3 '/Applications/Limitwick.app/Contents/Resources/useAnimations/activity-setup.py' install
```

For a development build, use the same command with the path to `build/Limitwick-Development.app` instead. The setup preserves other hook handlers in `$CODEX_HOME/hooks.json` (or `~/.codex/hooks.json`); it refuses an unexpected configuration format. Review and trust the new hooks in Codex Settings → Hooks or, in the CLI, `/hooks`, and restart or reopen sessions if necessary. Hooks that have not been trusted do not run. To remove these handlers, run the same command with `remove` instead of `install`. If the app is moved, rerun setup from its new location and review the changed hook.

Hooks send only event type, session and turn identifiers, tool-call identifier, time, and Codex home path to running local Limitwick instances. They do not send prompts, responses, command text, or tool results. The indicator covers only sessions whose hooks actually run while Limitwick is open. It hides a turn if the local writer lock is no longer held, including after a process crash. It does not cover remote, ephemeral, unsupported, or untrusted sessions reliably. The CLI integration was tested with Codex CLI 0.156.0; Desktop hook delivery requires separate verification. Other hooks can continue a turn after a `Stop` hook, so the checkmark reflects the observed stop event and may be followed by renewed activity.


## Claude Code activity indicator

Select Claude under Provider settings and turn on "Show Claude activity in menu bar"; if the hooks are missing, Limitwick installs them. Install Claude hooks and Remove Claude hooks add or remove only Limitwick's handlers. The setup preserves other entries in `~/.claude/settings.json` (or `$CLAUDE_CONFIG_DIR/settings.json`) and refuses unexpected configuration formats. Hooks call a copy of the helper script in `~/Library/Application Support/CodexBar/useAnimations/`, which the app refreshes at launch, so they keep working after the app is moved or updated; older installations that point into an app bundle are moved to this copy. The copy is kept after removal because open sessions continue to call it until they restart. Claude Code reads hooks when a session starts: activity appears in sessions started after installation, and an open session can be included by typing `/exit` and running `claude --continue`. The status line under the checkbox reports whether hooks are installed and whether events have arrived since the app launched.

Hooks forward only the event type, session ID, tool-call ID and time to local Limitwick instances. Prompts, commands, responses and tool input are not forwarded. The indicator is based on observed Claude Code events, does not cover sessions without active hooks, and clears stale sessions after 30 minutes. Disabling the activity checkbox leaves the installed hooks in place.
