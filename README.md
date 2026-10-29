# UNDERTOW offline

Open `undertow-offline.html` in a browser from a local folder. This single file includes all game scripts and styles; no installation, internet, shared folder, or file permission is needed. Copy the file locally before opening it to avoid loading it from a network drive.

Solo survival, practice, campaign, ships, flat/3D rendering and local progress remain. Online duels, shared leaderboards, shared profiles, fleet activity tracking and shared administration are disabled. Saves are browser-local and separate from the network edition; clearing browser data deletes them. Moving the file or changing browser can change which saves are available.

Rebuild the standalone file with `python build-offline.py` after editing source files. The network edition remains on the `simulation` branch.
