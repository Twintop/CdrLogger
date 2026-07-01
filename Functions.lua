local _, CdrLogger = ...
CdrLogger.Functions = CdrLogger.Functions or {}

---Checks if a value is a Blizzard secret value (combat-protected API return).
---Returns the fallback if the value is secret, otherwise returns the value itself.
---@param value any # The value to check
---@param fallback any # The value to return if the input is secret (default: nil)
---@return any # The original value if not secret, or the fallback value if it is secret
function CdrLogger.Functions:SecureValue(value, fallback)
    if issecretvalue(value) then
        return fallback
    end
    return value
end

---Checks if any of the provided values are Blizzard secret values.
---@param ... any # Values to check
---@return boolean # True if any value is secret, false otherwise
function CdrLogger.Functions:HasSecretValue(...)
    for i = 1, select("#", ...) do
        if issecretvalue(select(i, ...)) then
            return true
        end
    end
    return false
end

function CdrLogger.Functions:TableLength(T)
	local count = 0
	if T ~= nil then
		local _
		for _ in pairs(T) do
			count = count + 1
		end
	end
	return count
end

function CdrLogger.Functions:TablePrint(T, indent)
	if not indent then
		indent = 0
	end

	local toprint = string.rep(" ", indent) .. "{\r\n"
	indent = indent + 2
	for k, v in pairs(T) do
		toprint = toprint .. string.rep(" ", indent)
		if (type(k) == "number") then
			toprint = toprint .. "[" .. k .. "] = "
		elseif (type(k) == "string") then
			toprint = toprint  .. k ..  "= "
		end

		if (type(v) == "number") then
			toprint = toprint .. v .. ",\r\n"
		elseif (type(v) == "string") then
			toprint = toprint .. "\"" .. v .. "\",\r\n"
		elseif (type(v) == "table") then
			toprint = toprint .. CdrLogger.Functions:TablePrint(v, indent + 2) .. ",\r\n"
		else
			toprint = toprint .. "\"" .. tostring(v) .. "\",\r\n"
		end
	end

	toprint = toprint .. string.rep(" ", indent-2) .. "}"
	return toprint
end

function CdrLogger.Functions:RoundTo(num, numDecimalPlaces, mode)
    numDecimalPlaces = math.max(numDecimalPlaces or 0, 0)
    local newNum = tostring(tonumber(num))
    if mode == "floor" then
        local whole, decimal = strsplit(".", newNum, 2)

        if numDecimalPlaces == 0 then
            newNum = whole
        elseif decimal == nil or strlen(decimal) == 0 then
            newNum = string.format("%s.%0" .. numDecimalPlaces .. "d", whole, 0)
        else
            local chopped = string.sub(decimal, 1, numDecimalPlaces)
            if strlen(chopped) < numDecimalPlaces then
                chopped = string.format("%s%0" .. (numDecimalPlaces - strlen(chopped)) .. "d", chopped, 0)
            end
            newNum = string.format("%s.%s", whole, chopped)
        end

        return newNum
    elseif mode == "ceil" then
        local whole, decimal = strsplit(".", newNum, 2)

        if numDecimalPlaces == 0 then
            if (tonumber(whole) or 0) < num then
                whole = tostring((tonumber(whole) or 0) + 1)
            end

            newNum = whole
        elseif decimal == nil or strlen(decimal) == 0 then
            newNum = string.format("%s.%0" .. numDecimalPlaces .. "d", whole, 0)
        else
            local chopped = string.sub(decimal, 1, numDecimalPlaces)
            if tonumber(string.format("0.%s", chopped)) < tonumber(string.format("0.%s", decimal)) then
                chopped = chopped + 1
            end

            if strlen(chopped) < numDecimalPlaces then
                chopped = string.format("%s%0" .. (numDecimalPlaces - strlen(chopped)) .. "d", chopped, 0)
            end
            newNum = string.format("%s.%s", whole, chopped)
        end

        return newNum
    end

    return tonumber(string.format("%." .. numDecimalPlaces .. "f", newNum))
end

function CdrLogger.Functions:IsNumeric(data)
    if type(data) == "number" then
        return true
    elseif type(data) ~= "string" then
        return false
    end
    data = strtrim(data)
    local x, y = string.find(data, "[%d+][%.?][%d*]")
    if x and x == 1 and y == strlen(data) then
        return true
    end
    return false
end

function CdrLogger.Functions:GetCurrentGCDLockRemaining()
---@diagnostic disable-next-line: redundant-parameter
    local spellCooldown = C_Spell.GetSpellCooldown(61304) --[[@as SpellCooldownInfo]]
    -- Guard arithmetic on potentially secret values
    if CdrLogger.Functions:HasSecretValue(spellCooldown.startTime, spellCooldown.duration) then
        return 0
    end
    return spellCooldown.startTime + spellCooldown.duration - GetTime()
end

function CdrLogger.Functions:GetCurrentGCDTime(floor)
	if floor == nil then
		floor = false
	end

	local haste = UnitSpellHaste("player") / 100

	local gcd = 1.5 / (1 + haste)

	if not floor and gcd < 0.75 then
		gcd = 0.75
	end

	return gcd
end

function CdrLogger.Functions:GetLatency()
	--local down, up, lagHome, lagWorld = GetNetStats()
	local _, _, _, lagWorld = GetNetStats()
	local latency = lagWorld / 1000
	return latency
end

function CdrLogger.Functions:GetOutputTime(timeInput)
    local timeType = "os"
    if not timeInput then
        if CdrLogger.Data.settings.core.time.usePreciseTimestamps then
            timeInput = GetTime()
            timeType = "uptime"
        else
            timeInput = date()
            timeType = "os"
        end
    else
        if CdrLogger.Functions:IsNumeric(timeInput) then
            timeType = "uptime"
        else
            timeType = "os"
        end
    end

    if timeType == "uptime" then
        return CdrLogger.Functions:RoundTo(timeInput, CdrLogger.Data.settings.core.time.precision, "floor")
    else
        --local dow, month, day, time, year = strsplit(".", timeInput, 5)
        local _, _, _, time, _ = strsplit(" ", timeInput, 5)
        return time
    end
end

function CdrLogger.Functions:GetDefaultSettings()
    local defaultSettings = {
        core = {
            time = {
                showTimestamps = true,
                usePreciseTimestamps = true,
                precision = 3
            },
            colors = {
                cdStart = "FFFF00FF",
                cdChange = "FFFF00FF",
                cdEnd = "FFFF00FF",
                status = "FF0000FF"
            }
        },
        DEATHKNIGHT = {
            BLOOD = {
                items = {},
                spells = {},
                buffs = {}
            },
            FROST = {
                items = {},
                spells = {},
                buffs = {}
            },
            UNHOLY = {
                items = {},
                spells = {},
                buffs = {}
            },
        },
        DEMONHUNTER = {
            HAVOC = {
                items = {},
                spells = {},
                buffs = {}
            },
            VENGENCE = {
                items = {},
                spells = {},
                buffs = {}
            },
            DEVOURER = {
                items = {},
                spells = {},
                buffs = {}
            },
        },
        DRUID = {
            BALANCE = {
                items = {},
                spells = {},
                buffs = {}
            },
            FERAL = {
                items = {},
                spells = {
                    "106951", -- Berserk
                    "102543", -- Incarnation: King of the Jungle
                },
                buffs = {}
            },
            GUARDIAN = {
                items = {},
                spells = {},
                buffs = {}
            },
            RESTORATION = {
                items = {
                    "188262" -- The Lion's Roar
                },
                spells = {},
                buffs = {}
            }
        },
        EVOKER = {
            DEVASTATION = {
                items = {},
                spells = {},
                buffs = {}
            },
            PRESERVATION = {
                items = {},
                spells = {},
                buffs = {}
            },
            AUGMENTATION = {
                items = {},
                spells = {},
                buffs = {}
            }
        },
        HUNTER = {
            BEASTMASTERY = {
                items = {},
                spells = {},
                buffs = {}
            },
            MARKSMANSHIP = {
                items = {},
                spells = {},
                buffs = {}
            },
            SURVIVAL = {
                items = {},
                spells = {},
                buffs = {}
            }
        },
        MAGE = {
            ARCANE = {
                items = {},
                spells = {},
                buffs = {}
            },
            FIRE = {
                items = {},
                spells = {},
                buffs = {}
            },
            FROST = {
                items = {},
                spells = {},
                buffs = {}
            }
        },
        MONK = {
            BREWMASTER = {
                items = {},
                spells = {},
                buffs = {}
            },
            MISTWEAVER = {
                items = {
                    "188262" -- The Lion's Roar
                },
                spells = {},
                buffs = {}
            },
            WINDWALKER = {
                items = {},
                spells = {
                    "107428", -- Rising Sun Kick
                    "113656" -- Fists of Fury
                },
                buffs = {}
            }
        },
        PALADIN = {
            HOLY = {
                items = {
                    "188262" -- The Lion's Roar
                },
                spells = {},
                buffs = {}
            },
            PROTECTION = {
                items = {},
                spells = {},
                buffs = {}
            },
            RETRIBUTION = {
                items = {},
                spells = {},
                buffs = {}
            }
        },
        PRIEST = {
            DISCIPLINE = {
                items = {
                    -- Shadowlands
                    "188262" -- The Lion's Roar
                },
                spells = {
                    -- Class Abilities
                    "19236", -- Desperate Prayer
                    "373481", -- Holy Word: Life
                    -- Specialization Abilities
                    "47540", -- Pennance
                    -- Shadowlands
                    "325013" -- Boon of the Ascended
                },
                buffs = {}
            },
            HOLY = {
                items = {
                    -- Shadowlands
                    "188262" -- The Lion's Roar
                },
                spells = {
                    -- Class Abilities
                    "19236", -- Desperate Prayer
                    "373481", -- Holy Word: Life
                    -- Specialization Abilities
                    "2050", -- Holy Word: Serenity
                    "34861", -- Holy Word: Sanctify
                    "88625", -- Holy Word: Chastise
                    "265202", -- Holy Word: Salvation
                    "64843", -- Divine Hymn
                    "47788", -- Guardian Spirit
                    "372835", -- Lightwell
                    "33076", -- Prayer of Mending
                    -- Shadowlands
                    "325013", -- Boon of the Ascended
                },
                buffs = {}
            },
            SHADOW = {
                items = {},
                spells = {
                    -- Class Abilities
                    "19236", -- Desperate Prayer
                    "132603", -- Shadowfiend
                    -- Specialization Abilities
                    "34433", -- Mindbender
                    -- Shadowlands
                    "325013", -- Boon of the Ascended
                },
                buffs = {}
            }
        },
        ROGUE = {
            ASSASSINATION = {
                items = {},
                spells = {},
                buffs = {}
            },
            OUTLAW = {
                items = {},
                spells = {},
                buffs = {}
            },
            SUBTLETY = {
                items = {},
                spells = {},
                buffs = {}
            }
        },
        SHAMAN = {
            ELEMENTAL = {
                items = {},
                spells = {},
                buffs = {}
            },
            ENHANCEMENT = {
                items = {},
                spells = {},
                buffs = {}
            },
            RESTORATION = {
                items = {
                    "188262" -- The Lion's Roar
                },
                spells = {
                    "5394", -- Healing Stream Totem
                    "108280", -- Healing Tide Totem
                    "16191", -- Mana Tide Totem
                    "98008" -- Spirit Link Totem
                },
                buffs = {}
            }
        },
        WARLOCK = {
            AFFLICTION = {
                items = {},
                spells = {},
                buffs = {}
            },
            DEMONOLOGY = {
                items = {},
                spells = {},
                buffs = {}
            },
            DESTRUCTION = {
                items = {},
                spells = {},
                buffs = {}
            }
        },
        WARRIOR = {
            ARMS = {
                items = {},
                spells = {},
                buffs = {}
            },
            FURY = {
                items = {},
                spells = {},
                buffs = {}
            },
            PROTECTION = {
                items = {},
                spells = {},
                buffs = {}
            }
        }
    }
    return defaultSettings
end

function CdrLogger.Functions:MergeSettings(settings, user)
	if settings == nil and user == nil then
		return {}
	elseif settings == nil then
		return user
	elseif user == nil then
		return settings
	end

	for k, v in pairs(user) do
        -- For spell lists, we won't update/merge changes in here.
        -- TODO: Add/remove spells to be included as defaults manually through pseudo-migrations instead.
        if k == "spells" or k == "items" or k == "buffs" then
            settings[k] = v
        elseif (type(v) == "table") and (type(settings[k] or false) == "table") then
            CdrLogger.Functions:MergeSettings(settings[k], user[k])
        else
            settings[k] = v
        end
    end
    return settings
end

function CdrLogger.Functions:AddTrackedId(className, specName, id, cooldownType)
    if cooldownType == "spell" then
        cooldownType = "spells"
    elseif cooldownType == "item" then
        cooldownType = "items"
    elseif cooldownType == "buff" then
        cooldownType = "buffs"
    end

    local exists = false
    local t = CdrLogger.Data.settings[className][specName][cooldownType]
    for x = 1, #t do
        if t[x] == id then
            exists = true
            break
        end
    end

    if not exists then
        table.insert(t, id)
        return true
    end
    return false
end

function CdrLogger.Functions:RemoveTrackedId(className, specName, id, cooldownType)
    if cooldownType == "spell" then
        cooldownType = "spells"
    elseif cooldownType == "item" then
        cooldownType = "items"
    elseif cooldownType == "buff" then
        cooldownType = "buffs"
    end

    local t = CdrLogger.Data.settings[className][specName][cooldownType]
    for x = 1, #t do
        if t[x] == id then
            table.remove(CdrLogger.Data.settings[className][specName][cooldownType], x)
            return true
        end
    end
    return false
end

function CdrLogger.Functions:LookupSpecializationName(className, specId)
    if className == "DEATHKNIGHT" then
        if specId == 1 then
            return "BLOOD"
        elseif specId == 2 then
            return "FROST"
        elseif specId == 3 then
            return "UNHOLY"
        end
    elseif className == "DEMONHUNTER" then
        if specId == 1 then
            return "HAVOC"
        elseif specId == 2 then
            return "VENGENCE"
        elseif specId == 3 then
            return "DEVOURER"
        end
    elseif className == "DRUID" then
        if specId == 1 then
            return "BALANCE"
        elseif specId == 2 then
            return "FERAL"
        elseif specId == 3 then
            return "GUARDIAN"
        elseif specId == 4 then
            return "RESTORATION"
        end
    elseif className == "HUNTER" then
        if specId == 1 then
            return "BEASTMASTERY"
        elseif specId == 2 then
            return "MARKSMANSHIP"
        elseif specId == 3 then
            return "SURVIVAL"
        end
    elseif className == "EVOKER" then
        if specId == 1 then
            return "DEVASTATION"
        elseif specId == 2 then
            return "PRESERVATION"
        elseif specId == 3 then
            return "AUGMENTATION"
        end
    elseif className == "MAGE" then
        if specId == 1 then
            return "ARCANE"
        elseif specId == 2 then
            return "FIRE"
        elseif specId == 3 then
            return "FROST"
        end
    elseif className == "MONK" then
        if specId == 1 then
            return "BREWMASTER"
        elseif specId == 2 then
            return "MISTWEAVER"
        elseif specId == 3 then
            return "WINDWALKER"
        end
    elseif className == "PALADIN" then
        if specId == 1 then
            return "HOLY"
        elseif specId == 2 then
            return "PROTECTION"
        elseif specId == 3 then
            return "RETRIBUTION"
        end
    elseif className == "PRIEST" then
        if specId == 1 then
            return "DISCIPLINE"
        elseif specId == 2 then
            return "HOLY"
        elseif specId == 3 then
            return "SHADOW"
        end
    elseif className == "ROGUE" then
        if specId == 1 then
            return "ASSASSINATION"
        elseif specId == 2 then
            return "OUTLAW"
        elseif specId == 3 then
            return "SUBTLETY"
        end
    elseif className == "SHAMAN" then
        if specId == 1 then
            return "ELEMENTAL"
        elseif specId == 2 then
            return "ENHANCEMENT"
        elseif specId == 3 then
            return "RESTORATION"
        end
    elseif className == "WARLOCK" then
        if specId == 1 then
            return "AFFLICTION"
        elseif specId == 2 then
            return "DEMONOLOGY"
        elseif specId == 3 then
            return "DESTRUCTION"
        end
    elseif className == "WARRIOR" then
        if specId == 1 then
            return "ARMS"
        elseif specId == 2 then
            return "FURY"
        elseif specId == 3 then
            return "PROTECTION"
        end
    end
    return nil
end

function CdrLogger.Functions:LoadSpecializationTrackedSpellsItems()
    local tracked = CdrLogger.Data.tracked
    local spells = CdrLogger.Data.settings[CdrLogger.Data.className][CdrLogger.Data.specName].spells
    for x, v in pairs(spells) do
        if tracked.spells[v] == nil then
---@diagnostic disable-next-line: need-check-nil
            tracked.spells[v] = CdrLogger.Classes.Cooldown:New(v, "spell")
        end
    end

    local items = CdrLogger.Data.settings[CdrLogger.Data.className][CdrLogger.Data.specName].items
    for x, v in pairs(items) do
        if tracked.items[v] == nil then
---@diagnostic disable-next-line: need-check-nil
            tracked.items[v] = CdrLogger.Classes.Cooldown:New(v, "item")
        end
    end

    local buffs = CdrLogger.Data.settings[CdrLogger.Data.className][CdrLogger.Data.specName].buffs
    for x, v in pairs(buffs) do
        local spellId = tonumber(v)
        if tracked.buffs[spellId] == nil then
---@diagnostic disable-next-line: need-check-nil
            tracked.buffs[spellId] = CdrLogger.Classes.SnapshotBuff:New(spellId)
        else
            tracked.buffs[spellId]:Reset()
        end
    end
end

function CdrLogger.Functions:ParseCmdString(msg)
	if msg then
		while (strfind(msg,"  ") ~= nil) do
			msg = string.gsub(msg,"  "," ")
		end
		local a,b,c=strfind(msg,"(%S+)")
		if a then
			return c,strsub(msg,b+2)
		else
			return "";
		end
	end
end

function SlashCmdList.CDRLOGGER(msg)
    local cmd, subcmd = CdrLogger.Functions:ParseCmdString(msg);
    if cmd == "add" then
        local type, id = CdrLogger.Functions:ParseCmdString(subcmd)
        
        local outputLink = ""
        local typeName = ""
        
        if id == nil then
            print("|cFF0000FFCDRL: |r|cFFFF0000Failed|r to add '" .. type .. "' to " .. CdrLogger.Data.specName .. " " .. CdrLogger.Data.className .. ". ID cannot be missing.")
            return
        else
            if type == "spell" or type == "spells" then
                if CdrLogger.Data.tracked.spells[id] == nil then
                    CdrLogger.Data.tracked.spells[id] = CdrLogger.Classes.Cooldown:New(id, "spell")
                    outputLink = CdrLogger.Data.tracked.spells[id]:GetOutput(true)
                end
            elseif type == "item" or type == "items" then
                if CdrLogger.Data.tracked.items[id] == nil then
                    CdrLogger.Data.tracked.items[id] = CdrLogger.Classes.Cooldown:New(id, "item")
                    outputLink = CdrLogger.Data.tracked.items[id]:GetOutput(true)
                end
            elseif type == "buff" or type == "buffs" then
                local spellId = tonumber(id)
                if CdrLogger.Data.tracked.buffs[spellId] == nil then
---@diagnostic disable-next-line: need-check-nil
                    CdrLogger.Data.tracked.buffs[spellId] = CdrLogger.Classes.SnapshotBuff:New(spellId)
                    outputLink = CdrLogger.Data.tracked.buffs[spellId]:GetOutput(true)
                end
            else
                print("|cFF0000FFCDRL: |r|cFFFF0000Failed|r to add '" .. type .. "' to " .. CdrLogger.Data.specName .. " " .. CdrLogger.Data.className .. ". Supported types are 'spell', 'item', and 'buff'.")
                return
            end

            local result = CdrLogger.Functions:AddTrackedId(CdrLogger.Data.className, CdrLogger.Data.specName, id, type)
            if result then
                print("|cFF0000FFCDRL: |r|cFF00FF00Succeeded|r in adding " .. typeName .. " " .. outputLink .. " to " .. CdrLogger.Data.specName .. " " .. CdrLogger.Data.className .. ".")
            else
                print("|cFF0000FFCDRL: |r|cFFFF0000Failed|r to add " .. typeName .. " " .. id .. " to " .. CdrLogger.Data.specName .. " " .. CdrLogger.Data.className .. ".")
            end
        end
    elseif cmd == "remove" then
        local type, id = CdrLogger.Functions:ParseCmdString(subcmd)
        local outputLink = ""
        local typeName = ""
        
        if id == nil then
            print("|cFF0000FFCDRL: |r|cFFFF0000Failed|r to remove '" .. type .. "' to " .. CdrLogger.Data.specName .. " " .. CdrLogger.Data.className .. ". ID cannot be missing.")
            return
        else
            if type == "spell" or type == "spells" then
                if CdrLogger.Data.tracked.spells[id] ~= nil then
                    outputLink = CdrLogger.Data.tracked.spells[id]:GetOutput(true)
                    CdrLogger.Data.tracked.spells[id] = nil
                end
            elseif type == "item" or type == "items" then
                if CdrLogger.Data.tracked.items[id] ~= nil then
                    outputLink = CdrLogger.Data.tracked.items[id]:GetOutput(true)
                    CdrLogger.Data.tracked.items[id] = nil
                end
            elseif type == "buff" or type == "buffs" then
                local spellId = tonumber(id)
                if CdrLogger.Data.tracked.buffs[spellId] ~= nil then
                    outputLink = CdrLogger.Data.tracked.buffs[spellId]:GetOutput(true)
---@diagnostic disable-next-line: need-check-nil
                    CdrLogger.Data.tracked.buffs[spellId] = nil
                end
            else
                print("|cFF0000FFCDRL: |r|cFFFF0000Failed|r to remove '" .. type .. "' from " .. CdrLogger.Data.specName .. " " .. CdrLogger.Data.className .. ". Supported types are 'spell', 'item', and 'buff'.")
                return
            end

            local result = CdrLogger.Functions:RemoveTrackedId(CdrLogger.Data.className, CdrLogger.Data.specName, id, type)
            if result then
                print("|cFF0000FFCDRL: |r|cFF00FF00Succeeded|r in removing " .. typeName .. " " .. outputLink .. " from " .. CdrLogger.Data.specName .. " " .. CdrLogger.Data.className .. ".")
            else
                print("|cFF0000FFCDRL: |r|cFFFF0000Failed|r to remove " .. typeName .. " " .. outputLink .. " from " .. CdrLogger.Data.specName .. " " .. CdrLogger.Data.className .. ".")
            end
        end
    elseif cmd == "show" then
        CdrLogger.LogWindow:Show()
    elseif cmd == "start" or cmd == "on" then
        CdrLogger.Data.enabled = true
        CdrLogger:EventRegistration()
        CdrLogger.LogWindow:Show()
    elseif cmd == "stop" or cmd == "off" then
        CdrLogger.Data.enabled = false
        CdrLogger:EventRegistration()
    elseif cmd == "list" then
        local tracked = CdrLogger.Data.tracked
        print("|cFF0000FFCDRL: |rTracked spells for " .. CdrLogger.Data.specName .. " " .. CdrLogger.Data.className)
        local spells = CdrLogger.Data.settings[CdrLogger.Data.className][CdrLogger.Data.specName].spells

        local found = false
        for x, v in pairs(spells) do
            found = true
            if tracked.spells[v] == nil then
---@diagnostic disable-next-line: need-check-nil
                tracked.spells[v] = CdrLogger.Classes.Cooldown:New(v, "spell")
            end
            print(tracked.spells[v]:GetOutput(true))
        end
        
        if found == false then
            print("No spells tracked.")
        end

        print("|cFF0000FFCDRL: |rTracked items for " .. CdrLogger.Data.specName .. " " .. CdrLogger.Data.className)
        found = false
        
        local items = CdrLogger.Data.settings[CdrLogger.Data.className][CdrLogger.Data.specName].items
        for x, v in pairs(items) do
            found = true
            if tracked.items[v] == nil then
---@diagnostic disable-next-line: need-check-nil
                tracked.items[v] = CdrLogger.Classes.Cooldown:New(v, "item")
            end
            print(tracked.items[v]:GetOutput(true))
        end
        if found == false then
            print("No items tracked.")
        end

        print("|cFF0000FFCDRL: |rTracked buffs for " .. CdrLogger.Data.specName .. " " .. CdrLogger.Data.className)
        found = false
        
        local buffs = CdrLogger.Data.settings[CdrLogger.Data.className][CdrLogger.Data.specName].buffs
        for x, v in pairs(buffs) do
            found = true
            if tracked.buffs[v] == nil then
---@diagnostic disable-next-line: need-check-nil
                tracked.buffs[v] = CdrLogger.Classes.SnapshotBuff:New(tonumber(v))
            end
            print(tracked.buffs[v]:GetOutput(true))
        end
        if found == false then
            print("No buffs tracked.")
        end
    elseif cmd == "clear" then
        CdrLogger.Data.settings[CdrLogger.Data.className][CdrLogger.Data.specName].spells = {}
        CdrLogger.Data.settings[CdrLogger.Data.className][CdrLogger.Data.specName].items = {}
        CdrLogger.Data.settings[CdrLogger.Data.className][CdrLogger.Data.specName].buffs = {}
        CdrLogger.Data.tracked = {
            spells = {},
            items = {},
            buffs = {}
        }
        CdrLogger.Data.auraInstanceIds = {}
        CdrLogger.Functions:LoadSpecializationTrackedSpellsItems()
        print("|cFF0000FFCDRL: |rTracked spells, items, and buffs for " .. CdrLogger.Data.specName .. " " .. CdrLogger.Data.className .. " cleared.")
    elseif cmd == "reset" then
        local default = CdrLogger.Functions:GetDefaultSettings()
        CdrLogger.Data.settings[CdrLogger.Data.className][CdrLogger.Data.specName].spells = default[CdrLogger.Data.className][CdrLogger.Data.specName].spells
        CdrLogger.Data.settings[CdrLogger.Data.className][CdrLogger.Data.specName].items = default[CdrLogger.Data.className][CdrLogger.Data.specName].items
        CdrLogger.Data.settings[CdrLogger.Data.className][CdrLogger.Data.specName].buffs = default[CdrLogger.Data.className][CdrLogger.Data.specName].buffs
        CdrLogger.Data.tracked = {
            spells = {},
            items = {},
            buffs = {}
        }
        CdrLogger.Data.auraInstanceIds = {}
        CdrLogger.Functions:LoadSpecializationTrackedSpellsItems()
        print("|cFF0000FFCDRL: |rTracked spells, items, and buffs for " .. CdrLogger.Data.specName .. " " .. CdrLogger.Data.className .. " reset to defaults.")
    elseif cmd == "timestamp" then
        local toggle = CdrLogger.Functions:ParseCmdString(subcmd)

        if toggle == "on" then
            CdrLogger.Data.settings.core.time.showTimestamps = true
            print("|cFF0000FFCDRL: |rTimestamps |r|cFF00FF00enabled|r.")
        elseif toggle == "off" then
            CdrLogger.Data.settings.core.time.showTimestamps = false
            print("|cFF0000FFCDRL: |rTimestamps |r|cFFFF0000disabled|r.")
        else
            print("|cFF0000FFCDRL: Usage: /cdrl timestamp {on/off}")
        end
    elseif cmd == "preciseTimestamp" then
        local toggle = CdrLogger.Functions:ParseCmdString(subcmd)

        if toggle == "on" then
            CdrLogger.Data.settings.core.time.usePreciseTimestamps = true
            print("|cFF0000FFCDRL: |rPrecise timestamps |r|cFF00FF00enabled|r.")
        elseif toggle == "off" then
            CdrLogger.Data.settings.core.time.usePreciseTimestamps = false
            print("|cFF0000FFCDRL: |rPrecise timestamps |r|cFFFF0000disabled|r.")
        else
            print("|cFF0000FFCDRL: Usage: /cdrl preciseTimestamp {on/off}")
        end
    elseif cmd == "timestampPrecision" then
        local precision = tonumber(CdrLogger.Functions:ParseCmdString(subcmd))

        if precision ~= nil then
            precision = CdrLogger.Functions:RoundTo(precision, 0, floor)

            if precision > 3 or precision < 0 then
                precision = 3
            end

            CdrLogger.Data.settings.core.time.precision = precision
            print("|cFF0000FFCDRL: |rTime precision set to |r|cFF00FF00" .. precision .. "|r decimals.")
        else
            print("|cFF0000FFCDRL: Usage: /cdrl timestampPrecision {0-3}")
        end
    else
        print("|cFF0000FFCDRL: |rCommands: |cFFFFFF00on|r/|cFFFFFF00off|r, |cFFFFFF00show|r, |cFFFFFF00list|r, |cFFFFFF00add|r {spell|item|buff} {id}, |cFFFFFF00remove|r {spell|item|buff} {id}, |cFFFFFF00clear|r, |cFFFFFF00reset|r, |cFFFFFF00timestamp|r {on|off}, |cFFFFFF00preciseTimestamp|r {on|off}, |cFFFFFF00timestampPrecision|r {0-3}")
    end
end