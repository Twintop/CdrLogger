---@diagnostic disable: undefined-field, undefined-global
local _, CdrLogger = ...
CdrLogger.Functions = CdrLogger.Functions or {}
CdrLogger.Functions.Aura = {}

---Handles UNIT_AURA events
---@param self any
---@param event string
---@param unit UnitToken
---@param info UnitAuraUpdateInfo
local function AuraUpdateEvent(self, event, unit, info)
    local osTimestamp = date()
	if info.isFullUpdate and unit == "player" then
		--Only do a full refresh of buffs for now
        for _, v in pairs(CdrLogger.Data.tracked.buffs) do
            local buff = CdrLogger.Data.tracked.buffs[v.spellId] --[[@as CdrLogger.Classes.SnapshotBuff]]

            if buff ~= nil then
                buff:Refresh(osTimestamp, nil, unit)
            end
        end
		return
	end

	if info.addedAuras then
		if unit == "player" then
			for _, v in pairs(info.addedAuras) do
				-- Guard against secret spellId values that can't be used as table indices
				if not issecretvalue(v.spellId) then
					local buff = CdrLogger.Data.tracked.buffs[v.spellId] --[[@as CdrLogger.Classes.SnapshotBuff]]

					if buff ~= nil and v.sourceUnit == "player" then
						buff:RefreshWithAuraData(v, osTimestamp, true)
					end
				end
			end
		--[[else
			for _, v in pairs(info.updatedAuraInstanceIDs) do
				local target = CdrLogger.Data.snapshotData.targetData.auraInstanceIds[v]

				if target ~= nil then
					local targetSpell = target.auraInstanceIds[v]
					targetSpell:Update()
				end
			end]]
		end
	end

	if info.updatedAuraInstanceIDs then
		if unit == "player" then
			for _, v in pairs(info.updatedAuraInstanceIDs) do
				-- Guard against secret auraInstanceId values that can't be used as table indices
				if not issecretvalue(v) then
					local buff = CdrLogger.Data.auraInstanceIds[v] --[[@as CdrLogger.Classes.SnapshotBuff]]

					if buff ~= nil then
						buff:Refresh(osTimestamp, nil, unit)
					end
				end
			end
		--[[else
			for _, v in pairs(info.updatedAuraInstanceIDs) do
				local target = CdrLogger.Data.snapshotData.targetData.auraInstanceIds[v]

				if target ~= nil then
					local targetSpell = target.auraInstanceIds[v]
					targetSpell:Update()
				end
			end]]
		end
	end

	if info.removedAuraInstanceIDs then
		if unit == "player" then
			for _, v in pairs(info.removedAuraInstanceIDs) do
				-- Guard against secret auraInstanceId values that can't be used as table indices
				if not issecretvalue(v) then
					local buff = CdrLogger.Data.auraInstanceIds[v] --[[@as CdrLogger.Classes.SnapshotBuff]]

					if buff ~= nil then
						buff:Refresh(osTimestamp, nil, unit)
					end
					CdrLogger.Functions.Aura:RemoveBuffAuraInstanceId(v)
				end
			end
		--[[else
			for _, v in pairs(info.removedAuraInstanceIDs) do
				local target = CdrLogger.Data.snapshotData.targetData.auraInstanceIds[v]

				if target ~= nil then
					target.auraInstanceIds[v] = nil
					CdrLogger.Functions.Aura:RemoveTargetAuraInstanceId(v)
				end
			end]]
		end
	end
end

local unitAuraFrame = CreateFrame("Frame")
unitAuraFrame:SetScript("OnEvent", AuraUpdateEvent)

function CdrLogger.Functions.Aura:EnableUnitAura()
	unitAuraFrame:RegisterEvent("UNIT_AURA")
end

function CdrLogger.Functions.Aura:DisableUnitAura()
	unitAuraFrame:UnregisterEvent("UNIT_AURA")
end

---Stores the AuraInstanceId->SnapshotBuff in a dictionary
---@param snapshotBuff CdrLogger.Classes.SnapshotBuff
function CdrLogger.Functions.Aura:StoreBuffAuraInstanceId(snapshotBuff)
	if CdrLogger.Data.auraInstanceIds ~= nil then
		CdrLogger.Data.auraInstanceIds[snapshotBuff.auraInstanceId] = snapshotBuff
	end
end

---Removes the AuraInstanceId->SnapshotBuff dictionary entry
---@param auraInstanceId integer
function CdrLogger.Functions.Aura:RemoveBuffAuraInstanceId(auraInstanceId)
	if CdrLogger.Data.auraInstanceIds[auraInstanceId] ~= nil then
		CdrLogger.Data.auraInstanceIds[auraInstanceId] = nil
	end
end

---Clears all AuraInstanceIds that are cached for snapshot buffs and targets
function CdrLogger.Functions.Aura:ClearAuraInstanceIds()
	CdrLogger.Data.auraInstanceIds = {}
	
	for _, v in pairs(CdrLogger.Data.snapshotData.snapshots) do
		v.buff.auraInstanceId = nil
	end
end

---Attempts to get a buff on a target by its spellId
---@param spellId integer
---@param onWhom string?
---@param byWhom string?
---@return AuraData?
function CdrLogger.Functions.Aura:FindBuffById(spellId, onWhom, byWhom)
	if onWhom == nil then
		onWhom = "player"
	end

	local buffData

	for i = 1, 1000 do
		buffData = C_UnitAuras.GetBuffDataByIndex(onWhom, i)
		if not buffData then
			return
		elseif spellId == buffData.spellId and (byWhom == nil or byWhom == buffData.sourceUnit) then
			return buffData
		end
	end
end

---Attempts to get a debuff by its spellId
---@param spellId integer
---@param onWhom string?
---@param byWhom string?
---@return AuraData?
function CdrLogger.Functions.Aura:FindDebuffById(spellId, onWhom, byWhom)
	if onWhom == nil then
		onWhom = "player"
	end

	local debuffData

	for i = 1, 1000 do
		debuffData = C_UnitAuras.GetDebuffDataByIndex(onWhom, i)
		if not debuffData then
			return
		elseif spellId == debuffData.spellId and (byWhom == nil or byWhom == debuffData.sourceUnit) then
			return debuffData
		end
	end
end

---@alias CdrLoggerAuraEventType
---| '"SPELL_AURA_APPLIED"' # SPELL_AURA_APPLIED
---| '"SPELL_AURA_REFRESH"' # SPELL_AURA_REFRESH
---| '"SPELL_AURA_REMOVED"' # SPELL_AURA_REMOVED
---| '"SPELL_AURA_APPLIED_DOSE"' # SPELL_AURA_APPLIED_DOSE
---| '"SPELL_AURA_REMOVED_DOSE"' # SPELL_AURA_REMOVED_DOSE
---| '"SPELL_DISPEL"' # SPELL_DISPEL
---| '"SPELL_PERIODIC_ENERGIZE"' # SPELL_PERIODIC_ENERGIZE
---| '""' # No event type; refresh data and nothing else