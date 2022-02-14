local _, CdrLogger = ...
local trackedSpells = {}

CdrLogger = CdrLogger or {}
CdrLogger.Data = CdrLogger.Data or {}

if CdrLoggerSettings then
    CdrLogger.Data.settings = CdrLogger.Functions:MergeSettings(CdrLogger.Functions:GetDefaultSettings(), CdrLoggerSettings)
else
    CdrLogger.Data.settings = CdrLogger.Functions:GetDefaultSettings()
end

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
        print("CDR logging enabled.")
    else
        timerFrame:SetScript("OnUpdate", nil)
        combatFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        print("CDR logging disabled.")
    end
end

function timerFrame:onUpdate(sinceLastUpdate)
    local currentTime = GetTime()
    self.sinceLastUpdate = self.sinceLastUpdate + sinceLastUpdate
    if self.sinceLastUpdate >= 0.01 then -- in seconds
        for x, v in pairs(trackedSpells) do
---@diagnostic disable-next-line: redundant-parameter
            local startTime, duration, _, _ = GetSpellCooldown(trackedSpells[x].id)
            if startTime == 0 then
                local actualDuration = currentTime - trackedSpells[x].startTime
                local durationDelta = currentTime - trackedSpells[x].originalEndTime
                local updateDurationDelta = currentTime - trackedSpells[x].latestEndTime
                print("OFF CD: " .. trackedSpells[x].name .. " -- Actual = " .. CdrLogger.Functions:RoundTo(actualDuration, 3, floor) .. " | Original Delta = " .. CdrLogger.Functions:RoundTo(durationDelta, 3, floor) .. " | LatestChange Delta = " .. CdrLogger.Functions:RoundTo(updateDurationDelta, 3, floor))
                trackedSpells[x] = nil
            else
                local previousRemainingTime = trackedSpells[x].latestEndTime - currentTime

                trackedSpells[x].lastUpdatedTime = currentTime
                trackedSpells[x].latestDuration = duration
                trackedSpells[x].latestEndTime = duration + startTime

                local originalRemainingTime = trackedSpells[x].originalEndTime - currentTime
                local latestRemainingTime = trackedSpells[x].latestEndTime - currentTime

                if previousRemainingTime ~= latestRemainingTime then
                    print("CD CHANGE: " .. trackedSpells[x].name .. " -- " .. CdrLogger.Functions:RoundTo(previousRemainingTime, 3, floor) .. " - " .. CdrLogger.Functions:RoundTo(latestRemainingTime, 3, floor) .. " = " .. CdrLogger.Functions:RoundTo(previousRemainingTime - latestRemainingTime, 3, floor))
                end
            end
        end
        self.sinceLastUpdate = 0
    end
end

combatFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
combatFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		local currentTime = GetTime()
        local time, type, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, spellId, spellName = CombatLogGetCurrentEventInfo()
        
        if sourceGUID == CdrLogger.Data.characterGuid then
            local spells = CdrLogger.Data.settings[CdrLogger.Data.className][CdrLogger.Data.specName].spells

            for x, v in pairs(spells) do
                if spellId == tonumber(v) then
                    if type == "SPELL_CAST_SUCCESS" then
                        C_Timer.After(0.01, function()
---@diagnostic disable-next-line: redundant-parameter
                            local startTime, duration, _, _ = GetSpellCooldown(spellId)
                            local name, _, icon = GetSpellInfo(spellId)
                            trackedSpells[spellId] = {
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
                            print("ON CD: " .. name .. " -- " .. CdrLogger.Functions:RoundTo(duration, 3, floor) .. " | " .. CdrLogger.Functions:RoundTo(startTime+duration, 3, floor))
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

