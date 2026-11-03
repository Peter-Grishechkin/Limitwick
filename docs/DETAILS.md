# How Codex Bar works

## Refresh and notifications


The panel shows the local reset date and time remaining. If a reset time has passed, wait for a successful refresh to confirm the next one. Codex Bar refreshes after waking and normally every three minutes; repeated failures lengthen the delay to at most 24 minutes. Refresh in the context menu remains available between requests.

Settings can enable separate low-quota and confirmed-reset notifications. Both are off by default. The low threshold defaults to 20% and can be set from 1% to 99%; it also controls warning colors even when notifications are off. macOS asks for permission when you enable an alert; if notifications are blocked, use Notification Settings in the app. Alerts require a successful response and a future reset date. Reset alerts arrive only after a refresh confirms a new reset period, so they may be delayed. Delivery markers and reset dates are stored locally and pruned during successful refreshes after 30 days (for reset dates, 30 days after the reset); notification records do not contain quota percentages or account identifiers. Codex Bar cannot reliably detect an account switch, so alerts can be missed or associated with the previous account after switching.


## App updates

Codex Bar checks for compatible releases quietly at launch and once a day. When an update is available, the context menu offers to update and shows its version. A red dot appears on the menu bar icon for an update to a new major version. Select the menu item to review and install it; update checks do not show automatic alerts. If a check fails, the last known update remains visible until a successful check finds no update or the app version changes.

## Widget


On macOS 14 or later, open the desktop widget gallery (right-click the desktop and choose Edit Widgets), find **Codex Bar**, and add its horizontal medium widget. The widget uses a horizontal layout in the selected theme. It reads the latest snapshot prepared by Codex Bar; keep the app running for fresh data. macOS controls widget refresh timing, so the displayed values may lag behind the app. If an update fails, the panel image reports the error and the age of the previous data. The shared snapshot contains a rendered image of the panel, the two percentages, reset times, update time, error state, and warning threshold; it does not contain credentials or account identifiers. The desktop widget requires macOS 14 or later.

The widget was tested locally on macOS 14. Widget discovery, shared data access, and updates from a downloaded release can vary with macOS and signing.


## Data and connectivity

Codex Bar runs `codex app-server` and reads `account/rateLimits/read`. It also listens for rate-limit events, but delivery from other Codex sessions is not guaranteed. Other window durations appear in the panel; conflicting values for the same duration are shown as unavailable.

The app does not ask for your password or store credentials. Codex contacts OpenAI, update checks contact GitHub, and the app has no separate server. Changes to the Codex CLI protocol can affect compatibility.

## Codex activity indicator

Codex Bar can show activity to the left of its quota bars. Turn it on or off with “Show Codex activity in menu bar” in Settings; it is on by default. Turning it off stops the listener and hides the indicator, but leaves installed Codex hooks in place. This optional integration uses Codex lifecycle hooks. It shows a loading animation while a detected turn is working, a terminal animation while a supported tool is running, and a checkmark briefly when all detected turns have stopped. These events do not establish when an answer is being streamed or whether every kind of user input is pending, so the edit and alert animations are not used yet.

To enable the integration, run the following command after installing the app in `/Applications` (adjust the app name if needed):

```sh
/usr/bin/python3 '/Applications/CodexBar.app/Contents/Resources/useAnimations/activity-setup.py' install
```

For a development build, use the same command with the path to `build/CodexBar-Development.app` instead. The setup preserves other hook handlers in `$CODEX_HOME/hooks.json` (or `~/.codex/hooks.json`); it refuses an unexpected configuration format. Review and trust the new hooks in Codex Settings → Hooks or, in the CLI, `/hooks`, and restart or reopen sessions if necessary. Hooks that have not been trusted do not run. To remove these handlers, run the same command with `remove` instead of `install`. If the app is moved, rerun setup from its new location and review the changed hook.

Hooks send only event type, session and turn identifiers, tool-call identifier, time, and Codex home path to running local Codex Bar instances. They do not send prompts, responses, command text, or tool results. The indicator covers only sessions whose hooks actually run while Codex Bar is open. It hides a turn if the local writer lock is no longer held, including after a process crash. It does not cover remote, ephemeral, unsupported, or untrusted sessions reliably. The CLI integration was tested with Codex CLI 0.156.0; Desktop hook delivery requires separate verification. Other hooks can continue a turn after a `Stop` hook, so the checkmark reflects the observed stop event and may be followed by renewed activity.
