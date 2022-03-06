# CdrLogger
A World of Warcraft addon to help with tracking/debugging Cooldown Reduction interactions.

Slash commands:

* /cdrl - Help text.
* /cdrl on - Starts logging of spells.
* /cdrl off - Stops logging of spells.
* /cdrl add {spell|item} {id} - Adds a spell or item by ID to be tracked. This should be a spell your current class and spec can cast or an item you can use!
* /cdrl remove {spell|item} {id} - Removes a spell or item by ID that is currently being tracked.
* /cdrl list - Lists all spells your current class and spec is tracking.
* /cdrl clear - Removes all spells and items from being tracked by your current class and spec.
* /cdrl reset - Overwrites the list of currently tracked spells and items for your current class and spec to the defaults.
* /cdrl timestamp {on/off} - Enables/disables timestamps from output.
* /cdrl preciseTimestamp {on/off} - When on, uses relative timestamps including sub-second decimals out to desired precision (0 - 3). When off, uses human-readable HH:MM:SS timestamps.
* /cdrl timestampPrecision {0 - 3} - How many decimals of precision to show when preciseTimestamps are on.
