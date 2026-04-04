local UEHelpers = require("UEHelpers")

local BASE_PICKUP_RANGE = 360
local DEBUG_MODE = false
local currentPickupRange = BASE_PICKUP_RANGE
local statSystem = nil
local levelComponent = nil
local pickupRangeTag = nil
local accumulatedBaseXP = 0
local lastBonusXP = 0

-- UI state
local xpBoostWidget = nil
local xpBoostTextBlock = nil
local uiEnabled = true
local VISIBLE = 4
local HIDDEN = 2

local function Log(message)
    print(string.format("[PickupRangeXpBoost] %s\n", message))
end

local function DebugLog(message)
    if DEBUG_MODE then Log(message) end
end

local function FLinearColor(r, g, b, a) return { R = r, G = g, B = b, A = a } end
local function FSlateColor(r, g, b, a) return { SpecifiedColor = FLinearColor(r, g, b, a), ColorUseRule = 0 } end

local function FindExperienceMeter()
    local all = FindAllOf("WBP_ExperienceMeter_C")
    if not all then return nil end
    for _, obj in pairs(all) do
        if obj:IsValid() and string.find(obj:GetFullName(), "Transient") then
            return obj
        end
    end
    return nil
end

local function IsExpBarVisible()
    local meter = FindExperienceMeter()
    if not meter then return false end
    local bar = meter.LevelProgressBar
    return bar and bar:IsValid() and bar:IsVisible()
end

local function GetBonusColor(bonusPercent)
    if bonusPercent <= 0 then
        return FSlateColor(0.6, 0.6, 0.6, 1)
    elseif bonusPercent <= 100 then
        return FSlateColor(0.4, 1, 0.4, 1)
    elseif bonusPercent <= 300 then
        return FSlateColor(1, 0.85, 0.2, 1)
    elseif bonusPercent <= 500 then
        return FSlateColor(1, 0.5, 0.1, 1)
    else
        return FSlateColor(1, 0.25, 0.25, 1)
    end
end

local function UpdateXpBoostDisplay()
    if not xpBoostTextBlock or not xpBoostTextBlock:IsValid() then return end

    local bonusPercent = 0
    if currentPickupRange > BASE_PICKUP_RANGE then
        bonusPercent = math.floor((currentPickupRange - BASE_PICKUP_RANGE) / BASE_PICKUP_RANGE * 100 + 0.5)
    end

    local text
    if lastBonusXP > 0 then
        text = string.format("EXP +%d%%  (+%d)", bonusPercent, lastBonusXP)
    else
        text = string.format("EXP +%d%%", bonusPercent)
    end

    xpBoostTextBlock:SetText(FText(text))
    xpBoostTextBlock:SetColorAndOpacity(GetBonusColor(bonusPercent))
end

local function CleanupPreviousWidgets()
    local allWidgets = FindAllOf("UserWidget")
    if not allWidgets then return end
    for _, widget in pairs(allWidgets) do
        if widget:IsValid() and widget:GetFName():ToString() == "XpBoostWidget" then
            widget:RemoveFromParent()
            DebugLog("Removed orphaned XpBoostWidget from previous load")
        end
    end
end

local function CreateXpBoostWidget()
    if xpBoostWidget and xpBoostWidget:IsValid() then
        if not xpBoostWidget:IsInViewport() then
            xpBoostWidget:AddToViewport(99)
        end
        UpdateXpBoostDisplay()
        return
    end

    CleanupPreviousWidgets()

    local gi = UEHelpers.GetGameInstance()
    if not gi or not gi:IsValid() then return end

    xpBoostWidget = StaticConstructObject(StaticFindObject("/Script/UMG.UserWidget"), gi, FName("XpBoostWidget"))
    xpBoostWidget.WidgetTree = StaticConstructObject(StaticFindObject("/Script/UMG.WidgetTree"), xpBoostWidget, FName("XpBoostTree"))

    local canvas = StaticConstructObject(StaticFindObject("/Script/UMG.CanvasPanel"), xpBoostWidget.WidgetTree, FName("XpBoostCanvas"))
    xpBoostWidget.WidgetTree.RootWidget = canvas

    local bg = StaticConstructObject(StaticFindObject("/Script/UMG.Border"), canvas, FName("XpBoostBG"))
    bg:SetBrushColor(FLinearColor(0, 0, 0, 0.75))
    bg:SetPadding({ Left = 8, Top = 3, Right = 8, Bottom = 3 })

    local slot = canvas:AddChildToCanvas(bg)
    slot:SetAutoSize(true)
    slot:SetAnchors({ Minimum = { X = 0.5, Y = 0 }, Maximum = { X = 0.5, Y = 0 } })
    slot:SetAlignment({ X = 0.5, Y = 0 })
    slot:SetPosition({ X = 0, Y = 4 })

    xpBoostTextBlock = StaticConstructObject(StaticFindObject("/Script/UMG.TextBlock"), bg, FName("XpBoostText"))
    xpBoostTextBlock.Font.Size = 16
    xpBoostTextBlock:SetColorAndOpacity(FSlateColor(0.6, 0.6, 0.6, 1))
    xpBoostTextBlock:SetShadowOffset({ X = 1, Y = 1 })
    xpBoostTextBlock:SetShadowColorAndOpacity(FLinearColor(0, 0, 0, 0.8))
    xpBoostTextBlock:SetText(FText("EXP +0%"))
    xpBoostTextBlock:SetVisibility(VISIBLE)

    bg:SetContent(xpBoostTextBlock)
    bg:SetVisibility(VISIBLE)
    xpBoostWidget:SetVisibility((uiEnabled and IsExpBarVisible()) and VISIBLE or HIDDEN)
    xpBoostWidget:AddToViewport(99)

    UpdateXpBoostDisplay()
    Log("XP boost UI created")
end

local function InitializeStatSystem()
    local sys = FindFirstOf("StatSystem")
    if sys and sys:IsValid() then
        statSystem = sys
        DebugLog(string.format("StatSystem initialized: %s", sys:GetFullName()))
        return true
    end
    DebugLog("Failed to initialize StatSystem")
    return false
end

local function FindLevelComponent()
    if levelComponent and levelComponent:IsValid() then return true end
    
    local playerChar = FindFirstOf("BP_PlayerCharacter_C")
    if playerChar and playerChar:IsValid() then
        DebugLog(string.format("PlayerCharacter found: %s", playerChar:GetFullName()))
        local lc = playerChar.LevelComponent
        if lc and lc:IsValid() then
            levelComponent = lc
            DebugLog(string.format("LevelComponent found: %s", lc:GetFullName()))
            return true
        end
    end
    return false
end

local function FindPickupRangeTag()
    if pickupRangeTag then return true end
    if not statSystem or not statSystem:IsValid() then return false end
    
    local stats = statSystem.Stats
    if not stats then return false end
    
    for i = 1, #stats do
        local stat = stats[i]
        if stat and stat:IsValid() then
            local tag = stat.Tag
            if tag then
                local tagName = tag.TagName:ToString()
                if tagName == "Stat.PickupRange" then
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
    if not statSystem or not statSystem:IsValid() then
        InitializeStatSystem()
        if not statSystem then return end
    end
    if not FindPickupRangeTag() then return end
    
    local value = statSystem:GetStatValueByTag(pickupRangeTag)
    if type(value) == "number" and value > 0 then
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
    
    if currentPickupRange <= BASE_PICKUP_RANGE then return end
    
    local multiplier = (currentPickupRange - BASE_PICKUP_RANGE) / BASE_PICKUP_RANGE
    local bonusXP = math.floor(baseXP * multiplier + 0.5)
    
    if bonusXP <= 0 then return end
    
    if not FindLevelComponent() then
        DebugLog("LevelComponent not found, cannot add bonus XP")
        return
    end
    
    local currentXP = levelComponent.AccumulatedXpOnCurrentLevel
    if type(currentXP) == "number" then
        local newXP = currentXP + bonusXP
        levelComponent.AccumulatedXpOnCurrentLevel = newXP
        lastBonusXP = bonusXP
        UpdateXpBoostDisplay()
        Log(string.format("Base: %d | Range: %.2f | Multiplier: %.2fx | Bonus: %d | Total: %d", 
            baseXP, currentPickupRange, multiplier, bonusXP, newXP))
    end
end

-- Hot-reload recovery: detect if we're reloading mid-game and restore state
local function TryInitMidGame()
    local playerChar = FindFirstOf("BP_PlayerCharacter_C")
    if not playerChar or not playerChar:IsValid() then
        DebugLog("No player character found - not in game, skipping mid-game init")
        return
    end
    DebugLog(string.format("PlayerCharacter found: %s", playerChar:GetFullName()))
    Log("Hot-reload detected mid-game, restoring state...")

    CleanupPreviousWidgets()

    InitializeStatSystem()
    FindLevelComponent()
    UpdatePickupRange()

    ExecuteWithDelay(1000, function()
        local ok, err = pcall(CreateXpBoostWidget)
        if not ok then Log(string.format("CreateXpBoostWidget error: %s", tostring(err))) end
    end)
end

-- Reset all cached UE references and derived values on level transition.
-- UE objects/structs from the previous level may be GC'd; any cached reference
-- that is not cleared here becomes a dangling pointer.
-- Rule: every variable that holds a UE object, struct, or value derived from one
-- MUST be reset here. Add new cached references to this list.
local function ResetLevelState()
    statSystem = nil
    levelComponent = nil
    pickupRangeTag = nil
    xpBoostWidget = nil
    xpBoostTextBlock = nil
    currentPickupRange = BASE_PICKUP_RANGE
    accumulatedBaseXP = 0
    lastBonusXP = 0
end

RegisterCustomEvent("OnGameLevelStarted", function(ContextParam)
    Log("Game level started")
    ResetLevelState()
    InitializeStatSystem()
    UpdatePickupRange()
    ExecuteWithDelay(2000, function()
        local ok, err = pcall(CreateXpBoostWidget)
        if not ok then Log(string.format("CreateXpBoostWidget error: %s", tostring(err))) end
    end)
end)

RegisterCustomEvent("HandlePickupRangeChanged_", function(ContextParam, StatTag, PrevValue, NewValue)
    local prevVal = PrevValue:get()
    local newVal = NewValue:get()
    if type(prevVal) ~= "number" or type(newVal) ~= "number" then return end
    DebugLog(string.format("PickupRange changed: %.2f -> %.2f", prevVal, newVal))
    if newVal > 0 then
        currentPickupRange = newVal
        UpdateXpBoostDisplay()
    end
end)

RegisterCustomEvent("OnPlayerGainXP_Event", function(ContextParam, XPAmount)
    local xp = XPAmount:get()
    if not xp or xp <= 0 then return end
    accumulatedBaseXP = accumulatedBaseXP + xp
end)

ExecuteInGameThread(function()
    Log(string.format("Mod loaded - Base PickupRange: %.1f", BASE_PICKUP_RANGE))
    local ok, err = pcall(TryInitMidGame)
    if not ok then Log(string.format("TryInitMidGame error: %s", tostring(err))) end
end)

LoopAsync(500, function()
    local ok, err = pcall(function()
        UpdatePickupRange()
        GiveBonusXP()
        if xpBoostWidget and xpBoostWidget:IsValid() then
            if not xpBoostWidget:IsInViewport() then
                xpBoostWidget:AddToViewport(99)
            end
            xpBoostWidget:SetVisibility((uiEnabled and IsExpBarVisible()) and VISIBLE or HIDDEN)
        end
    end)
    if not ok then
        Log(string.format("LoopAsync error: %s", tostring(err)))
    end
    return false
end)

RegisterConsoleCommandHandler("xpboost_status", function(Cmd, CommandParts, Ar)
    local bonus = math.floor((currentPickupRange - BASE_PICKUP_RANGE) / BASE_PICKUP_RANGE * 100 + 0.5)
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
            UpdateXpBoostDisplay()
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

RegisterConsoleCommandHandler("xpboost_ui", function(Cmd, CommandParts, Ar)
    uiEnabled = not uiEnabled
    if xpBoostWidget and xpBoostWidget:IsValid() then
        xpBoostWidget:SetVisibility((uiEnabled and IsExpBarVisible()) and VISIBLE or HIDDEN)
    end
    Log(string.format("UI: %s", uiEnabled and "ON" or "OFF"))
    return true
end)
