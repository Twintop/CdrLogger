local _, CdrLogger = ...
local tracked = {
    items = {},
    spells = {}
}
local updateInterval = 0.01

CdrLogger = CdrLogger or {}
CdrLogger.Data = CdrLogger.Data or {}

_, CdrLogger.Data.className, _ = UnitClass("player")
CdrLogger.Data.specName = nil
CdrLogger.Data.specId = 0
CdrLogger.Data.characterGuid = UnitGUID("player")
CdrLogger.Data.enabled = false

-- Frames
local containerFrame = CreateFrame("Frame", "CdrLoggerFrame", UIParent, "BackdropTemplate")
local combatFrame = CreateFrame("Frame", nil, containerFrame, "BackdropTemplate")
local timerFrame = CreateFrame("Frame", nil, containerFrame)
timerFrame.sinceLastUpdate = 0

function CdrLogger:EventRegistration()
    if CdrLogger.Data.enabled then
        timerFrame:SetScript("OnUpdate", function(self, sinceLastUpdate) timerFrame:onUpdate(sinceLastUpdate) end)
        combatFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        print("|c" .. CdrLogger.Data.settings.core.colors.status .. "CDRL: |rCDR logging |cFF00FF00enabled|r.")
    else
        timerFrame:SetScript("OnUpdate", nil)
        combatFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        print("|c" .. CdrLogger.Data.settings.core.colors.status .. "CDRL: |rCDR logging |cFFFF0000disabled|r.")
    end
end

local function GetOutputTimeIfAny(timeInput)
    if CdrLogger.Data.settings.core.time.showTimestamps then
        return "[" .. CdrLogger.Functions:GetOutputTime(timeInput) .. "] "
    end
    return ""
end

local function CooldownChanged(snapshot)
    local x = snapshot.id
    if snapshot.latestRemainingTime < 0 then
        snapshot.latestRemainingTime = snapshot.previousRemainingTime
    end

    local outputLink = ""
    if snapshot.cooldownType == "spells" then
        outputLink = CdrLogger.Functions:GetOutputSpell(tracked.spells[x])
    elseif snapshot.cooldownType == "items" then
        outputLink = CdrLogger.Functions:GetOutputItem(tracked.items[x])
    end

    print("|c" .. CdrLogger.Data.settings.core.colors.cdChange .. GetOutputTimeIfAny(snapshot.outputTime) .. "CD CHANGE: |r" .. outputLink .. " -- " .. CdrLogger.Functions:RoundTo(snapshot.previousRemainingTime, 3, floor) .. " - " .. CdrLogger.Functions:RoundTo(snapshot.latestRemainingTime, 3, floor) .. " = " .. CdrLogger.Functions:RoundTo(snapshot.previousRemainingTime - snapshot.latestRemainingTime, 3, floor))
end

local function CooldownFinished(x, cooldownType, currentTime, outputTime)
    currentTime = currentTime or GetTime()

    local actualDuration = currentTime - tracked[cooldownType][x].startTime
    local originalDuration = tracked[cooldownType][x].originalDuration
    local durationDelta = currentTime - tracked[cooldownType][x].originalEndTime
    local updateDurationDelta = currentTime - tracked[cooldownType][x].latestEndTime
    
    local previousRemainingTime = tracked[cooldownType][x].latestEndTime - currentTime

    tracked[cooldownType][x].lastUpdatedTime = currentTime
    tracked[cooldownType][x].latestDuration = 0
    tracked[cooldownType][x].latestEndTime = currentTime

    local originalRemainingTime = tracked[cooldownType][x].originalEndTime - currentTime
    local latestRemainingTime = tracked[cooldownType][x].latestEndTime - currentTime

    local snapshot = {
        id = x,
        cooldownType = cooldownType,
        currentTime = currentTime,
        outputTime = outputTime,
        previousRemainingTime = previousRemainingTime,
        originalRemainingTime = originalRemainingTime,
        latestRemainingTime = latestRemainingTime
    }

    CooldownChanged(snapshot)

    local outputLink = ""
    if snapshot.cooldownType == "spells" then
        outputLink = CdrLogger.Functions:GetOutputSpell(tracked.spells[x])
    elseif snapshot.cooldownType == "items" then
        outputLink = CdrLogger.Functions:GetOutputItem(tracked.items[x])
    end
    
    print("|c" .. CdrLogger.Data.settings.core.colors.cdEnd .. GetOutputTimeIfAny(outputTime) .. "OFF CD: |r" .. outputLink .. " -- " .. CdrLogger.Functions:RoundTo(actualDuration, 3, floor) .. " | Delta = " .. CdrLogger.Functions:RoundTo(durationDelta, 3, floor) .. " (" .. CdrLogger.Functions:RoundTo(100 * (1 - (actualDuration/originalDuration)), 3, floor) .. "%)")
    tracked[cooldownType][x] = nil
end

local function CooldownLogic(x, cooldownType, startTime, duration, currentTime, osTimestamp)
    if startTime == 0 then
        CooldownFinished(x, cooldownType)
    else
        local gcdLockRemaining = CdrLogger.Functions:GetCurrentGCDLockRemaining()
        local previousRemainingTime = tracked[cooldownType][x].latestEndTime - currentTime

        tracked[cooldownType][x].lastUpdatedTime = currentTime
        tracked[cooldownType][x].latestDuration = duration
        tracked[cooldownType][x].latestEndTime = duration + startTime

        local originalRemainingTime = tracked[cooldownType][x].originalEndTime - currentTime
        local latestRemainingTime = tracked[cooldownType][x].latestEndTime - currentTime

        local outputTime = currentTime
        if not CdrLogger.Data.settings.core.time.usePreciseTimestamps then
            outputTime = osTimestamp
        end
        
        if gcdLockRemaining == latestRemainingTime then
            CooldownFinished(x, cooldownType, currentTime, outputTime)
        elseif previousRemainingTime ~= latestRemainingTime then
            local snapshot = {
                id = x,
                cooldownType = cooldownType,
                currentTime = currentTime,
                outputTime = outputTime,
                previousRemainingTime = previousRemainingTime,
                originalRemainingTime = originalRemainingTime,
                latestRemainingTime = latestRemainingTime
            }

            CooldownChanged(snapshot)
        end
    end
end

function timerFrame:onUpdate(sinceLastUpdate)
    local currentTime = GetTime()
    local osTimestamp = date()
    self.sinceLastUpdate = self.sinceLastUpdate + sinceLastUpdate
    if self.sinceLastUpdate >= updateInterval then -- in seconds
        for x, v in pairs(tracked.spells) do
---@diagnostic disable-next-line: redundant-parameter
            local startTime, duration, _, _ = GetSpellCooldown(tracked.spells[x].id)

            CooldownLogic(x, "spells", startTime, duration, currentTime, osTimestamp)
        end
        
        local items = CdrLogger.Data.settings[CdrLogger.Data.className][CdrLogger.Data.specName].items

        for x, v in pairs(items) do
            local startTime, duration, _ = GetItemCooldown(v)

            if  tracked.items[v] == nil and startTime ~= nil and startTime > 0 then
                local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(v)
                tracked.items[v] = {
                    id = v,
                    name = name,
                    icon = icon,
                    startTime = startTime,
                    originalDuration = duration,
                    originalEndTime = startTime + duration,
                    latestDuration = duration,
                    latestEndTime = duration + startTime,
                    lastUpdatedTime = currentTime
                }
                local outputTime = currentTime
                if not CdrLogger.Data.settings.core.time.usePreciseTimestamps then
---@diagnostic disable-next-line: cast-local-type
                    outputTime = osTimestamp
                end
                print("|c" .. CdrLogger.Data.settings.core.colors.cdStart .. GetOutputTimeIfAny(outputTime) .. "ON CD: |r" .. CdrLogger.Functions:GetOutputItem(tracked.items[v]) .. " -- " .. CdrLogger.Functions:RoundTo(duration, 3, floor))
            end
        end

        for x, v in pairs(tracked.items) do
---@diagnostic disable-next-line: redundant-parameter
            local startTime, duration, _ = GetItemCooldown(tracked.items[x].id)

            CooldownLogic(x, "items", startTime, duration, currentTime, osTimestamp)
        end

        self.sinceLastUpdate = 0
    end
end

combatFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
combatFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		local currentTime = GetTime()
        local osTimestamp = date()
        local time, type, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, spellId, spellName = CombatLogGetCurrentEventInfo()
        
        if sourceGUID == CdrLogger.Data.characterGuid then
            local spells = CdrLogger.Data.settings[CdrLogger.Data.className][CdrLogger.Data.specName].spells

            for x, v in pairs(spells) do
                if spellId == tonumber(v) then
                    if type == "SPELL_CAST_SUCCESS" then
                        C_Timer.After(updateInterval, function()
---@diagnostic disable-next-line: param-type-mismatch
                            local startTime, duration, _, _ = GetSpellCooldown(spellId)
---@diagnostic disable-next-line: param-type-mismatch
                            local name, _, icon = GetSpellInfo(spellId)
---@diagnostic disable-next-line: param-type-mismatch, need-check-nil
                            tracked.spells[spellId] = {
                                id = spellId,
                                name = name,
                                icon = icon,
                                startTime = startTime,
                                originalDuration = duration,
                                originalEndTime = startTime + duration,
                                latestDuration = duration,
                                latestEndTime = duration + startTime,
                                lastUpdatedTime = currentTime
                            }
                            local outputTime = currentTime
                            if not CdrLogger.Data.settings.core.time.usePreciseTimestamps then
---@diagnostic disable-next-line: cast-local-type
                                outputTime = osTimestamp
                            end
                            print("|c" .. CdrLogger.Data.settings.core.colors.cdStart .. GetOutputTimeIfAny(outputTime) .. "ON CD: |r" .. CdrLogger.Functions:GetOutputSpell(tracked.spells[spellId]) .. " -- " .. CdrLogger.Functions:RoundTo(duration, 3, floor))
                        end)
                    end
                end
            end
        end
    end
end)


containerFrame:RegisterEvent("PLAYER_LOGOUT") -- Fired when about to log out
containerFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
containerFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
containerFrame:RegisterEvent("ADDON_LOADED")
containerFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
containerFrame:SetScript("OnEvent", function(self, event, arg1, ...)
    if (event == "ADDON_LOADED" and arg1 == "CdrLogger") then
        if not CdrLogger.Data.loaded then
            CdrLogger.Data.loaded = true
            
            if CdrLoggerSettings then
                CdrLogger.Data.settings = CdrLogger.Functions:MergeSettings(CdrLogger.Functions:GetDefaultSettings(), CdrLoggerSettings)
            else
                CdrLogger.Data.settings = CdrLogger.Functions:GetDefaultSettings()
            end

            SLASH_CDRLOGGER1 = "/cdrl"
            SLASH_CDRLOGGER2 = "/cdrlog"
            SLASH_CDRLOGGER3 = "/cdrlogger"
            CdrLogger:EventRegistration()
        end
    end

    if CdrLogger.Data.loaded then
        if event == "PLAYER_LOGOUT" then
            CdrLoggerSettings = CdrLogger.Data.settings
            return
        end
       
        if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_TALENT_UPDATE" or event == "PLAYER_SPECIALIZATION_CHANGED" then
            CdrLogger.Data.specId = GetSpecialization()
            CdrLogger.Data.specName = CdrLogger.Functions:LookupSpecializationName(CdrLogger.Data.className, CdrLogger.Data.specId)
        end
    end
end)