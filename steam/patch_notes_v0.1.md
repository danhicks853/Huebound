Huebound — Patch v0.1.1


Bug Fixes

- Fixed Steam achievements not unlocking. Turns out we shipped the server version of the Steam plugin instead of the client one. Achievements were politely trying to talk to a wall. They now talk to Steam like normal, well-adjusted achievements.

- Fixed Steam integration not initializing properly. The game now auto-connects to Steam on startup instead of waiting around hoping Steam would notice it.

- Removed debug key bindings (F10/F11/F12) that were accidentally left in. They didn't do anything scary, but they also didn't do anything useful.


Improvements

- Connection lines now highlight red when you hover over them, with a little X button to delete them. No more right-click guessing games.

- Cleaned up internal Steam integration code. Less spaghetti, more linguine.
