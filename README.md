# UNDERTOW (manual-save edition)

Open `undertow.html` with the `files/` folder beside it, in Microsoft Edge or Google Chrome, and enter a callsign.

## Saving

The shared folder is only used when a player clicks:

- **Save** (top right, or Ctrl+S) sends the player's profile (medals, XP, campaign, last-used difficulty/boat/mode) and, only when there is a new score or medal, posts to the shared leaderboard (`bin.dat`). Save can be used once a minute.
- **Refresh** on the Leaderboard and admin screens only reads `bin.dat`.

Nothing touches the drive on a timer, on focus or when the page closes. Between saves everything is kept in the browser; closing the tab with unsaved scores asks first.

A page cannot open a folder by its path, so the first Save on each computer and browser asks once for the shared folder (`G:\Nathan Hambleton\Submarine Photos\New Folder`, set as `SHARED_DIR` in `files/leaderboard.js`). It is remembered: after that, Save and Refresh only show the browser's Allow prompt (choose "Allow on every visit" to skip even that). The admin console has **Change shared folder** if it ever moves.

## Files in the shared folder

- `bin.dat` — the leaderboard, medals/XP per player and admin corrections. Needed.
- `bin.dat.bak` — copy of the last good `bin.dat`. Keep it as the backup.
- `profiles\` — one file per callsign. Needed.
- `bin.dat.lock` — appears for a moment while someone saves.

No longer used: `analytics\` (statistics were removed). `bin.dat.bak.crswap` is a temporary file Chrome/Edge leave behind when a write is interrupted; it can be deleted when nobody is saving.

## Admin

Tap the build number in the footer five times (or press ↑↑↓↓←→←→BA on the menu) and enter the service password to edit scores, medals/XP and profiles.

Duels and statistics are not included. Every submarine and campaign mission is unlocked. The network edition remains on the `simulation` branch.
