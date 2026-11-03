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
