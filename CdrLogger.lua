local _, CdrLogger = ...
local updateInterval = 0.01

CdrLogger = CdrLogger or {}
CdrLogger.Data = CdrLogger.Data or {}
CdrLogger.Data.tracked = {
    items = {},
    spells = {},
    buffs = {}
}
CdrLogger.Data.auraInstanceIds = {}

local tracked = CdrLogger.Data.tracked

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
        CdrLogger.Functions.Aura:EnableUnitAura()
        print("|c" .. CdrLogger.Data.settings.core.colors.status .. "CDRL: |rCDR logging |cFF00FF00enabled|r.")
    else
        timerFrame:SetScript("OnUpdate", nil)
        CdrLogger.Functions.Aura:DisableUnitAura()
        CdrLogger.Data.auraInstanceIds = {}
        print("|c" .. CdrLogger.Data.settings.core.colors.status .. "CDRL: |rCDR logging |cFFFF0000disabled|r.")
    end
end

function timerFrame:onUpdate(sinceLastUpdate)
    local currentTime = GetTime()
    local osTimestamp = date()
    self.sinceLastUpdate = self.sinceLastUpdate + sinceLastUpdate
    if self.sinceLastUpdate >= updateInterval then -- in seconds
        local gcd = CdrLogger.Functions:GetCurrentGCDTime()
        for x, v in pairs(tracked.spells) do
            if tracked.spells[x].tracking then
                tracked.spells[x]:Refresh()
                -- Check if still tracking after Refresh (may have been reset due to secret values)
                if tracked.spells[x].tracking then
                    tracked.spells[x]:CooldownLogic(currentTime, osTimestamp)
                end
            else
                local spellCharges = C_Spell.GetSpellCharges(x)
                if spellCharges == nil then
                    local spellCooldown = C_Spell.GetSpellCooldown(x) --[[@as SpellCooldownInfo]]
                    -- Check for secret values before comparing
                    if spellCooldown ~= nil and not CdrLogger.Functions:HasSecretValue(spellCooldown.startTime, spellCooldown.duration) then
                        if spellCooldown.startTime > 0 and spellCooldown.duration > gcd then
                            -- Only initialize if not blocked from retracking
                            if not tracked.spells[x].retrackBlocked then
                                tracked.spells[x]:Initialize(currentTime, osTimestamp)
                            end
                        elseif spellCooldown.startTime == 0 then
                            -- Spell is confirmed off cooldown, clear the retrack block
                            tracked.spells[x].retrackBlocked = false
                        end
                    end
                else
                    -- Check for secret values before comparing
                    if not CdrLogger.Functions:HasSecretValue(spellCharges.currentCharges, spellCharges.maxCharges) then
                        if spellCharges.currentCharges < spellCharges.maxCharges then
                            -- Only initialize if not blocked from retracking
                            if not tracked.spells[x].retrackBlocked then
                                tracked.spells[x]:Initialize(currentTime, osTimestamp)
                            end
                        elseif spellCharges.currentCharges == spellCharges.maxCharges then
                            -- Spell has all charges, clear the retrack block
                            tracked.spells[x].retrackBlocked = false
                        end
                    end
                end
            end
        end
        
        local items = CdrLogger.Data.settings[CdrLogger.Data.className][CdrLogger.Data.specName].items

        for x, v in pairs(items) do
            if tracked.items[v] == nil then
                ---@diagnostic disable-next-line: need-check-nil
                tracked.items[v] = CdrLogger.Classes.Cooldown:New(v, "item")
            end

            if tracked.items[v].tracking then
                tracked.items[v]:Refresh()
                -- Check if still tracking after Refresh (may have been reset due to secret values)
                if tracked.items[v].tracking then
                    tracked.items[v]:CooldownLogic(currentTime, osTimestamp)
                end
            else
                local startTime, _, _ = C_Item.GetItemCooldown(v)

                -- Check for secret values before comparing
                if startTime ~= nil and not issecretvalue(startTime) then
                    if startTime > 0 then
                        -- Only initialize if not blocked from retracking
                        if not tracked.items[v].retrackBlocked then
                            tracked.items[v]:Initialize(currentTime, osTimestamp)
                        end
                    else
                        -- Item is confirmed off cooldown, clear the retrack block
                        tracked.items[v].retrackBlocked = false
                    end
                end
            end
        end

        self.sinceLastUpdate = 0
    end
end

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
            CdrLogger.Data.specId = C_SpecializationInfo.GetSpecialization()
            CdrLogger.Data.specName = CdrLogger.Functions:LookupSpecializationName(CdrLogger.Data.className, CdrLogger.Data.specId)
            CdrLogger.Functions:LoadSpecializationTrackedSpellsItems()
        end
    end
end)

CdrLogger_Data = CdrLogger.Data