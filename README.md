# CdrLogger
A World of Warcraft addon to help with tracking/debugging Cooldown Reduction interactions for spells and items, and, buff duration and stack counts.

Slash commands:

* /cdrl - Help text.
* /cdrl on - Starts logging of spells.
* /cdrl off - Stops logging of spells.
* /cdrl add {spell|item|buff} {id} - Adds a spell, item, or buff by ID to be tracked. This should be a spell your current class and spec can cast or an item you can use!
* /cdrl remove {spell|item|buff} {id} - Removes a spell, item, or buff by ID that is currently being tracked.
* /cdrl list - Lists all spells, items, and buffs your current class and spec is tracking.
* /cdrl clear - Removes all spells, items, and buffs from being tracked by your current class and spec.
* /cdrl reset - Overwrites the list of currently tracked spells, items, and buffs for your current class and spec to the defaults.
* /cdrl timestamp {on/off} - Enables/disables timestamps from output.
* /cdrl preciseTimestamp {on/off} - When on, uses relative timestamps including sub-second decimals out to desired precision (0 - 3). When off, uses human-readable HH:MM:SS timestamps.
* /cdrl timestampPrecision {0 - 3} - How many decimals of precision to show when preciseTimestamps are on.
