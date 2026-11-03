# UNDERTOW (manual-save edition)

Keep `undertow.html`, the `files/` folder and `Play Undertow.cmd` together. Players double-click **Play Undertow.cmd**: it opens the game signed in with their Windows user name (`%USERNAME%`), so nobody types a callsign. Opening `undertow.html` directly still works and reuses the last name the launcher passed on that PC; without one, a callsign can be typed.

## Saving

The shared folder is only used when a player clicks:

- **Save** (top right, or Ctrl+S) sends everything in one pass: the player's profile (medals, XP, campaign, last-used difficulty/boat/mode), any new scores to the shared leaderboard (`bin.dat`), and their activity record (`analytics\`). A Save with nothing new reads two files and writes none.
- **Refresh** on the Leaderboard, Statistics and admin screens reads the latest copy.

Nothing touches the drive on a timer, on focus or when the page closes. Between saves, everything is kept in the browser; the button shows a count of unsaved scores, and closing the tab with unsaved scores asks first. The first Save asks for the shared folder (pick the one holding `bin.dat`); the browser remembers it, so later saves at most ask to allow access again.

The files are the same ones the network edition used, so all earlier scores, medals and profiles are back.

## Admin

Tap the build number in the footer five times (or press ↑↑↓↓←→←→BA on the menu) and enter the service password. Besides editing scores, medals/XP and profiles, **Username migration** maps an old typed callsign to a Windows user name: its scores, medals and activity count for the new name, and its saved profile can be merged in (totals add up; the previous profile is kept as `<name>.backup.dat`).

Duels are not included, since they need the shared folder polled continuously. Every submarine and campaign mission is unlocked. Use Microsoft Edge or Google Chrome. The network edition remains on the `simulation` branch.
