local _, CdrLogger = ...
CdrLogger.Classes = CdrLogger.Classes or {}

---@class CdrLogger.Classes.Cooldown
---@field public id integer
---@field public name string
---@field public type string # spell|item
---@field public startTime number?
---@field public duration number
---@field public remaining number
---@field public remainingTotal number
---@field public onCooldown boolean
---@field public charges integer
---@field public maxCharges integer
---@field public iconName string? # Manual override of the icon file name to use to populate `icon`.
---@field public icon string # Icon string of the spell. Usually populated automagically from the ID via lookups.
---@field public lastUpdatedTime number
---@field public latestDuration number
---@field public latestStartTime number
---@field public latestEndTime number
---@field public latestCharges number
---@field public originalDuration number
---@field public originalEndTime number
---@field public originalStartTime number
---@field public tracking boolean
CdrLogger.Classes.Cooldown = {}
CdrLogger.Classes.Cooldown.__index = CdrLogger.Classes.Cooldown

---Creates a new Snapshot object
---@param id integer # Spell ID of the spell we are tracking
---@param type string # spell|item
---@return CdrLogger.Classes.Cooldown?
function CdrLogger.Classes.Cooldown:New(id, type)
    local self = {}
    setmetatable(self, CdrLogger.Classes.Cooldown)
    self:Reset()
    self.id = id
    self.name = ""
    self.icon = ""
    self.type = type

    local name, icon
    if type == "spell" then
        name, _, icon = GetSpellInfo(self.id)
        self.name = name
        self.icon = string.format("|T%s:0|t", icon)
    elseif type == "item" then
        C_Item.GetItemInfo(id) -- prime it
        C_Timer.After(0, function()
            C_Timer.After(1, function()
                name, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(id)
                self.name = name
                self.icon = string.format("|T%s:0|t", icon)
            end)
        end)
    else
        return nil
    end

    return self
end

---Resets the object to default values
function CdrLogger.Classes.Cooldown:Reset()
    self.startTime = nil
    self.duration = 0
    self.remaining = 0
    self.remainingTotal = 0
    self.onCooldown = false
    self.maxCharges = self.maxCharges or 1
    self.charges = self.maxCharges
    self.latestDuration = 0
    self.latestEndTime = 0
    self.latestStartTime = 0
    self.latestCharges = 0
    self.originalDuration = 0
    self.originalEndTime = 0
    self.originalStartTime = 0
    self.tracking = false
end

---Computes the time remaining on the Snapshot
---@param currentTime number? # Timestamp to use for calculations. If not specified, the current time from `GetTime()` will be used instead.
---@param totalTime boolean? # Return the total remaining time of all charges on the Snapshot
---@return number # Cooldown duration remaining on the Snapshot
function CdrLogger.Classes.Cooldown:GetRemainingTime(currentTime, totalTime)
	if totalTime == nil then
        totalTime = false
    end
    
    currentTime = currentTime or GetTime()

    if self.retryForceTime ~= nil and currentTime > self.retryForceTime then
        self.retryForceTime = nil
        self:Refresh(true)
    end

    local remainingTime = 0

    if self.startTime ~= nil and self.duration ~= nil and self.duration > 0 then
		remainingTime = self.duration - (currentTime - self.startTime)
	end

    self.remaining = remainingTime
    
    if self.maxCharges > 1 and self.charges < self.maxCharges then
        self.remainingTotal = self.remaining +  ((self.maxCharges - self.charges - 1) * self.duration)
    elseif self.maxCharges > 1 and self.maxCharges == self.charges then
        if self.onCooldown then
            self:CooldownFinished()
        end
        self.startTime = nil
        self.duration = 0
        self.remainingTotal = 0
    end

	if remainingTime <= 0 then
		remainingTime = 0
        self.onCooldown = false
    elseif self.charges > 0 then
        self.onCooldown = false
    else
        self.onCooldown = true
	end

    if totalTime then
        return self.remainingTotal
    else
        return self.remaining
    end
end

function CdrLogger.Classes.Cooldown:SetOriginalLatest(currentTime)
    if self.startTime == nil then
        self:Refresh(true)
    end

    if self.startTime ~= nil then
        currentTime = currentTime or GetTime()
        self.originalStartTime = self.startTime
        self.originalDuration = self.duration
        self.originalEndTime = self.startTime + self.duration
        self.latestDuration = self.duration
        self.latestEndTime = self.duration + self.startTime
        self.lastUpdatedTime = currentTime
        self.latestCharges = self.charges
    end
end

---Initializes the cooldown information for the snapshot by forcing a refresh and a retry on the next frame, if needed
function CdrLogger.Classes.Cooldown:Initialize(currentTime, osTimestamp)
    local wasOnCd = self.onCooldown
    self.tracking = true
    self.latestCharges = -1
    self:Refresh(true, true)

    if not wasOnCd and self.onCooldown then
        self:SetOriginalLatest(currentTime)
        local outputTime = currentTime
        if not CdrLogger.Data.settings.core.time.usePreciseTimestamps then
    ---@diagnostic disable-next-line: cast-local-type
            outputTime = osTimestamp
        end
        print("|c" .. CdrLogger.Data.settings.core.colors.cdStart .. self:GetOutputTimeIfAny(outputTime) .. "ON CD: |r" .. self:GetOutput() .. " -- " .. CdrLogger.Functions:RoundTo(self.duration, 3, floor))
    end
end

---Refreshes the cooldown information for the snapshot
---@param force boolean? # Force refresh of the value even if other interal logic would prevent it from doing so
---@param retryForce boolean? # Allow the cooldown to retry a force on the next call to Refresh()
function CdrLogger.Classes.Cooldown:Refresh(force, retryForce)
    local startTime = nil
    local duration = 0
    local currentTime = GetTime()

    if force or self.tracking or self.onCooldown or self.charges < self.maxCharges then
        if self.type == "spell" then
            self.charges, self.maxCharges, startTime, duration, _ = GetSpellCharges(self.id)
            if self.charges == nil then
                self.maxCharges = 1
                startTime, duration, _, _ = GetSpellCooldown(self.id)
                if startTime == 0 then
                    self.charges = 1
                else
                    self.charges = 0
                end
            elseif self.charges == self.maxCharges then
                startTime = 0
                duration = 0
            end

            if self.latestCharges == -1 then
                self.latestCharges = self.charges
            end
        elseif self.type == "item" then
            startTime, duration = C_Item.GetItemCooldown(self.id)
        else
            return
        end

        if self.originalStartTime == nil then
            self.originalStartTime = currentTime
        end

        local gcd = CdrLogger.Functions:GetCurrentGCDLockRemaining()
        local down, up, lagHome, lagWorld = GetNetStats()
        local latency = lagWorld / 1000
        
        local remainingTime = startTime + duration - currentTime

        if ((startTime ~= nil and startTime > 0 and not self.onCooldown and remainingTime > gcd + latency) or
            (self.onCooldown and remainingTime > gcd + latency)) and (self.maxCharges == 1 or (self.maxCharges > 1 and self.charges < self.maxCharges))
            then
            self.startTime = startTime
            self.duration = duration
            self.retryForceTime = nil
        elseif self.onCooldown and remainingTime > gcd + latency then
            self.startTime = startTime
            self.duration = duration
            self.retryForceTime = nil
        else
            self.startTime = nil
            self.duration = 0
            if retryForce then
                self.retryForceTime = currentTime
            end
        end
    end
    self:GetRemainingTime()
end

function CdrLogger.Classes.Cooldown:CooldownLogic(currentTime, osTimestamp)
    currentTime = currentTime or GetTime()
    osTimestamp = osTimestamp or date()
    if self.tracking and (self.startTime == 0 or self.startTime == nil) then
        self:CooldownFinished()
    elseif self.startTime ~= nil then
        local force = false
        local gcdLockRemaining = CdrLogger.Functions:GetCurrentGCDLockRemaining()
        local previousRemainingTime = self.latestEndTime - currentTime

        if self.latestEndTime == 0 then
            force = true
            previousRemainingTime = self.duration
            self:SetOriginalLatest(currentTime)
        end

        local previousCharges = self.latestCharges

        self.lastUpdatedTime = currentTime
        self.latestDuration = self.duration
        self.latestStartTime = self.startTime
        self.latestEndTime = self.duration + self.startTime
        self.latestCharges = self.charges

        local originalRemainingTime = self.originalEndTime - currentTime
        local latestRemainingTime = self.latestEndTime - currentTime

        local outputTime = currentTime
        if not CdrLogger.Data.settings.core.time.usePreciseTimestamps then
            outputTime = osTimestamp
        end
        
        local snapshot = {
            currentTime = currentTime,
            outputTime = outputTime,
            previousRemainingTime = previousRemainingTime,
            originalRemainingTime = originalRemainingTime,
            latestRemainingTime = latestRemainingTime
        }

        if gcdLockRemaining == latestRemainingTime then
            self:CooldownFinished(currentTime, outputTime)
        elseif self.latestCharges > previousCharges then
            self:CooldownFinished(currentTime, outputTime)
        elseif self.latestCharges < previousCharges then
            self:CooldownChanged(snapshot, true)
        elseif force or previousRemainingTime ~= latestRemainingTime then
            self:CooldownChanged(snapshot)
        end
    end
end

function CdrLogger.Classes.Cooldown:CooldownFinished(currentTime, outputTime)
    currentTime = currentTime or GetTime()
    local actualDuration = currentTime - self.originalStartTime
    local originalDuration = self.originalDuration
    local durationDelta = currentTime - self.originalEndTime
    local updateDurationDelta = currentTime - self.latestEndTime
    
    local previousRemainingTime = self.latestEndTime - currentTime

    self.lastUpdatedTime = currentTime
    self.latestDuration = 0
    self.latestEndTime = currentTime

    local originalRemainingTime = self.originalEndTime - currentTime
    local latestRemainingTime = self.latestEndTime - currentTime

    local snapshot = {
        currentTime = currentTime,
        outputTime = outputTime,
        previousRemainingTime = previousRemainingTime,
        originalRemainingTime = originalRemainingTime,
        latestRemainingTime = latestRemainingTime
    }

    self:CooldownChanged(snapshot)

    local outputLink = self:GetOutput()

    self:Refresh(true)
    if self.maxCharges > 1 then
        if self.maxCharges == self.charges then
            print("|c" .. CdrLogger.Data.settings.core.colors.cdEnd .. self:GetOutputTimeIfAny(outputTime) .. "OFF CD: |r" .. outputLink .. " (" .. self.charges .. "/" .. self.maxCharges .. ") -- " .. CdrLogger.Functions:RoundTo(actualDuration, 3, floor) .. " | Delta = " .. CdrLogger.Functions:RoundTo(durationDelta, 3, floor) .. " (" .. CdrLogger.Functions:RoundTo(100 * (1 - (actualDuration/originalDuration)), 3, floor) .. "%)")
        else
            print("|c" .. CdrLogger.Data.settings.core.colors.cdEnd .. self:GetOutputTimeIfAny(outputTime) .. "CHARGE GAIN: |r" .. outputLink .. " (" .. self.charges .. "/" .. self.maxCharges .. ") -- " .. CdrLogger.Functions:RoundTo(actualDuration, 3, floor) .. " | Delta = " .. CdrLogger.Functions:RoundTo(durationDelta, 3, floor) .. " (" .. CdrLogger.Functions:RoundTo(100 * (1 - (actualDuration/originalDuration)), 3, floor) .. "%)")

        end
    else
        print("|c" .. CdrLogger.Data.settings.core.colors.cdEnd .. self:GetOutputTimeIfAny(outputTime) .. "OFF CD: |r" .. outputLink .. " -- " .. CdrLogger.Functions:RoundTo(actualDuration, 3, floor) .. " | Delta = " .. CdrLogger.Functions:RoundTo(durationDelta, 3, floor) .. " (" .. CdrLogger.Functions:RoundTo(100 * (1 - (actualDuration/originalDuration)), 3, floor) .. "%)")
    end
    
    if self.charges == self.maxCharges then
        self:Reset()
    else
        self:SetOriginalLatest(currentTime)
        self:CooldownLogic(currentTime)
    end
end

function CdrLogger.Classes.Cooldown:CooldownChanged(snapshot, fromCharges)
    local x = snapshot.id
    if snapshot.latestRemainingTime < 0 and not fromCharges then
        snapshot.latestRemainingTime = snapshot.previousRemainingTime
    end

    local outputLink = self:GetOutput()
 
    if self.maxCharges > 1 then
        if fromCharges then
            print("|c" .. CdrLogger.Data.settings.core.colors.cdChange .. self:GetOutputTimeIfAny(snapshot.outputTime) .. "CHARGE USE: |r" .. outputLink .. " (" .. self.charges .. "/" .. self.maxCharges .. ") -- " .. CdrLogger.Functions:RoundTo(snapshot.previousRemainingTime, 3, floor) .. " - " .. CdrLogger.Functions:RoundTo(snapshot.latestRemainingTime, 3, floor) .. " = " .. CdrLogger.Functions:RoundTo(snapshot.previousRemainingTime - snapshot.latestRemainingTime, 3, floor))
        else
            print("|c" .. CdrLogger.Data.settings.core.colors.cdChange .. self:GetOutputTimeIfAny(snapshot.outputTime) .. "CD CHANGE: |r" .. outputLink .. " (" .. self.charges .. "/" .. self.maxCharges .. ") -- " .. CdrLogger.Functions:RoundTo(snapshot.previousRemainingTime, 3, floor) .. " - " .. CdrLogger.Functions:RoundTo(snapshot.latestRemainingTime, 3, floor) .. " = " .. CdrLogger.Functions:RoundTo(snapshot.previousRemainingTime - snapshot.latestRemainingTime, 3, floor))
        end
    else
        print("|c" .. CdrLogger.Data.settings.core.colors.cdChange .. self:GetOutputTimeIfAny(snapshot.outputTime) .. "CD CHANGE: |r" .. outputLink .. " -- " .. CdrLogger.Functions:RoundTo(snapshot.previousRemainingTime, 3, floor) .. " - " .. CdrLogger.Functions:RoundTo(snapshot.latestRemainingTime, 3, floor) .. " = " .. CdrLogger.Functions:RoundTo(snapshot.previousRemainingTime - snapshot.latestRemainingTime, 3, floor))
    end
end

function CdrLogger.Classes.Cooldown:GetOutputTimeIfAny(timeInput)
    if CdrLogger.Data.settings.core.time.showTimestamps then
        return "[" .. CdrLogger.Functions:GetOutputTime(timeInput) .. "] "
    end
    return ""
end

---Determines if the cooldown is unusable, either by virtue of being completely on cooldown or having no charges to spend
---@return boolean
function CdrLogger.Classes.Cooldown:IsUnusable()
    return (self.charges == nil or self.charges == 0) and self.onCooldown
end

---Determines if the cooldown is usable, either by virtue of being completely off of cooldown or having any charges to spend
---@return boolean
function CdrLogger.Classes.Cooldown:IsUsable()
    return not self.onCooldown
end

function CdrLogger.Classes.Cooldown:GetOutput(includeId)
    local id = ""
    if includeId then
        id = " (" .. self.id .. ")"
    end
    if self.type == "spell" then
        return "|Hspell:" .. self.id .. "|h[" .. self.icon .. " " .. self.name .. "]|h" .. id
    elseif self.type == "item" then
        return "|Hitem:" .. self.id .. "|h[" .. self.icon .. " " .. self.name .. "]|h" .. id
    end
end