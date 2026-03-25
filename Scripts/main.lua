local UEHelpers = require("UEHelpers")

local BASE_PICKUP_RANGE = 360
local DEBUG_MODE = true
local currentPickupRange = BASE_PICKUP_RANGE
local statSystem = nil
local levelComponent = nil
local pickupRangeTag = nil
local accumulatedBaseXP = 0

local function Log(message)
    print(string.format("[PickupRangeXpBoost] %s\n", message))
end

local function DebugLog(message)
    if DEBUG_MODE then Log(message) end
end

local function InitializeStatSystem()
    local success, sys = pcall(function()
        return FindFirstOf("StatSystem")
    end)
    if success and sys and sys:IsValid() then
        statSystem = sys
        DebugLog("StatSystem initialized")
        return true
    end
    DebugLog("Failed to initialize StatSystem")
    return false
end

local function FindLevelComponent()
    if levelComponent and levelComponent:IsValid() then return true end
    
    local playerChar = FindFirstOf("BP_PlayerCharacter_C")
    if playerChar and playerChar:IsValid() then
        local success, lc = pcall(function()
            return playerChar.LevelComponent
        end)
        if success and lc and lc:IsValid() then
            levelComponent = lc
            DebugLog("LevelComponent found")
            return true
        end
    end
    return false
end

local function FindPickupRangeTag()
    if pickupRangeTag then return true end
    if not statSystem or not statSystem:IsValid() then return false end
    
    local success, stats = pcall(function()
        return statSystem.Stats
    end)
    
    if not success or not stats then return false end
    
    for i = 1, #stats do
        local stat = stats[i]
        if stat and stat:IsValid() then
            local tagSuccess, tag = pcall(function()
                return stat.Tag
            end)
            
            if tagSuccess and tag then
                local nameSuccess, tagName = pcall(function()
                    return tag.TagName:ToString()
                end)
                
                if nameSuccess and tagName and tagName == "Stat.PickupRange" then
                    pickupRangeTag = tag
                    Log("Found PickupRange tag")
                    return true
                end
            end
        end
    end
    
    return false
end

local function UpdatePickupRange()
    if not statSystem or not statSystem:IsValid() then return end
    if not FindPickupRangeTag() then return end
    
    local success, value = pcall(function()
        return statSystem:GetStatValueByTag(pickupRangeTag)
    end)
    
    if success and type(value) == "number" and value > 0 then
        if value ~= currentPickupRange then
            DebugLog(string.format("PickupRange: %.2f -> %.2f", currentPickupRange, value))
            currentPickupRange = value
        end
    end
end

local function GiveBonusXP()
    if accumulatedBaseXP <= 0 then return end
    
    local baseXP = accumulatedBaseXP
    accumulatedBaseXP = 0
    
    UpdatePickupRange()
    
    if currentPickupRange <= BASE_PICKUP_RANGE then return end
    
    local multiplier = (currentPickupRange - BASE_PICKUP_RANGE) / BASE_PICKUP_RANGE
    local bonusXP = math.floor(baseXP * multiplier + 0.5)
    
    if bonusXP <= 0 then return end
    
    if not FindLevelComponent() then
        DebugLog("LevelComponent not found, cannot add bonus XP")
        return
    end
    
    local success, currentXP = pcall(function()
        return levelComponent.AccumulatedXpOnCurrentLevel
    end)
    
    if success and type(currentXP) == "number" then
        local newXP = currentXP + bonusXP
        pcall(function()
            levelComponent.AccumulatedXpOnCurrentLevel = newXP
        end)
        Log(string.format("Base: %d | Range: %.2f | Multiplier: %.2fx | Bonus: %d | Total: %d", 
            baseXP, currentPickupRange, multiplier, bonusXP, newXP))
    end
end

RegisterCustomEvent("HandlePickupRangeChanged_", function(ContextParam, StatTag, PrevValue, NewValue)
    local newVal = NewValue:get()
    if newVal and newVal > 0 then
        currentPickupRange = newVal
    end
end)

RegisterCustomEvent("OnPlayerGainXP_Event", function(ContextParam, XPAmount)
    local xp = XPAmount:get()
    if not xp or xp <= 0 then return end
    accumulatedBaseXP = accumulatedBaseXP + xp
end)

ExecuteInGameThread(function()
    Log(string.format("Mod loaded - Base PickupRange: %.1f", BASE_PICKUP_RANGE))
    InitializeStatSystem()
    FindPickupRangeTag()
    UpdatePickupRange()
end)

LoopAsync(500, function()
    GiveBonusXP()
    return false
end)

LoopAsync(2000, function()
    FindPickupRangeTag()
    UpdatePickupRange()
    return false
end)

RegisterConsoleCommandHandler("xpboost_status", function(Cmd, CommandParts, Ar)
    local bonus = math.floor((currentPickupRange - BASE_PICKUP_RANGE) / BASE_PICKUP_RANGE * 100)
    Log(string.format("Range: %.2f | Base: %.2f | Bonus: %d%% | Accumulated: %d", 
        currentPickupRange, BASE_PICKUP_RANGE, bonus, accumulatedBaseXP))
    return true
end)

RegisterConsoleCommandHandler("xpboost_debug", function(Cmd, CommandParts, Ar)
    DEBUG_MODE = not DEBUG_MODE
    Log(string.format("Debug: %s", DEBUG_MODE and "ON" or "OFF"))
    return true
end)

RegisterConsoleCommandHandler("xpboost_set", function(Cmd, CommandParts, Ar)
    if #CommandParts >= 2 then
        local val = tonumber(CommandParts[2])
        if val then
            currentPickupRange = val
            Log(string.format("PickupRange set to: %.2f", val))
        end
    end
    return true
end)

RegisterConsoleCommandHandler("xpboost_test", function(Cmd, CommandParts, Ar)
    local amount = (#CommandParts >= 2) and tonumber(CommandParts[2]) or 10
    accumulatedBaseXP = accumulatedBaseXP + amount
    Log(string.format("Added %d to accumulated XP (total: %d)", amount, accumulatedBaseXP))
    return true
end)
