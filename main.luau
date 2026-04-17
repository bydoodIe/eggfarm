local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- ==================== RAYFIELD UI ====================
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "Egg Collector",
    LoadingTitle = "Egg Hunter",
    LoadingSubtitle = "EasterEggs Edition",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "EggHunt",
        FileName = "Config"
    },
    Discord = { Enabled = false, Invite = "", RememberJoins = true },
    KeySystem = false
})

local MainTab = Window:CreateTab("Main", 4483362458)
local VisualTab = Window:CreateTab("Visuals", 4483362458)
local SettingsTab = Window:CreateTab("Settings", 4483362458)

-- ==================== НАСТРОЙКИ ====================
local CONFIG = {
    Enabled = false,
    ESP = true,
    ESPColor = Color3.fromRGB(255, 105, 180), -- Розовый для пасхальных яиц
    ESPTextSize = 14,
    CollectionRadius = 8,
    AgentRadius = 2.5,
    AgentHeight = 5,
    AgentCanJump = true,
    VisualizePath = false,
    PathColor = Color3.fromRGB(255, 255, 0),
    IgnoreCollected = true,
    CheckInterval = 0.2,
    MaxSearchRadius = 1000,
    
    -- === ОСНОВНАЯ ПАПКА С ЯЙЦАМИ ===
    EggFolder = Workspace:WaitForChild("EasterEggs", 10) -- Ждём загрузки до 10 сек
}

-- ==================== СОСТОЯНИЕ ====================
local State = {
    IsMoving = false,
    CurrentTarget = nil,
    CollectedEggs = {},
    ESPObjects = {},
    PathVisuals = {},
    LastCheck = 0
}

-- ==================== УТИЛИТЫ ====================

function getCharacter()
    local char = player.Character
    if char then
        local hum = char:FindFirstChild("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hum and hrp and hum.Health > 0 then
            return char, hum, hrp
        end
    end
    return nil, nil, nil
end

function getPosition(obj)
    if not obj or not obj.Parent then return nil end
    if obj:IsA("BasePart") then
        return obj.Position
    elseif obj:IsA("Model") then
        return obj:GetPivot().Position
    end
    return nil
end

function isValidEgg(obj)
    if not (obj:IsA("BasePart") or obj:IsA("Model")) then return false end
    if not obj.Parent then return false end
    -- Пасхальные яйца могут называться по-разному, собираем всё из папки
    return true
end

function getEggID(egg)
    return egg:GetFullName()
end

-- ==================== ПРОВЕРКА ЗАНЯТОСТИ ====================

function isEggAvailable(egg)
    if not CONFIG.IgnoreCollected then return true end
    if not egg or not egg.Parent then return false end
    
    local id = getEggID(egg)
    
    -- Проверяем кэш (30 сек защита от повторного сбора)
    if State.CollectedEggs[id] then
        if tick() - State.CollectedEggs[id] > 30 then
            State.CollectedEggs[id] = nil
            return true
        end
        return false
    end
    
    -- Проверяем, не собрал ли кто-то другой
    if egg:IsA("BasePart") then
        if egg.Transparency >= 1 then
            State.CollectedEggs[id] = tick()
            return false
        end
        if not egg.CanCollide and egg.Transparency > 0.8 then
            State.CollectedEggs[id] = tick()
            return false
        end
    end
    
    -- Проверка для Model: ищем видимые части
    if egg:IsA("Model") then
        local visible = false
        for _, part in ipairs(egg:GetDescendants()) do
            if part:IsA("BasePart") and part.Transparency < 1 then
                visible = true
                break
            end
        end
        if not visible then
            State.CollectedEggs[id] = tick()
            return false
        end
    end
    
    return true
end

function markAsCollected(egg)
    if not egg then return end
    State.CollectedEggs[getEggID(egg)] = tick()
    State.CurrentTarget = nil
end

-- ==================== ПОИСК ЯИЦ ====================

function findAllEggs()
    local eggs = {}
    local folder = CONFIG.EggFolder
    
    if not folder or not folder.Parent then 
        -- Пытаемся найти папку снова
        local success, result = pcall(function()
            return Workspace:WaitForChild("EasterEggs", 2)
        end)
        if success and result then
            CONFIG.EggFolder = result
            folder = result
        else
            return eggs
        end
    end
    
    for _, obj in ipairs(folder:GetDescendants()) do
        if isValidEgg(obj) and isEggAvailable(obj) then
            table.insert(eggs, obj)
        end
    end
    
    -- Также проверяем прямые дети (если яйца лежат сразу в папке)
    for _, obj in ipairs(folder:GetChildren()) do
        if isValidEgg(obj) and isEggAvailable(obj) then
            if not table.find(eggs, obj) then
                table.insert(eggs, obj)
            end
        end
    end
    
    return eggs
end

function getNearestEgg()
    local char, hum, hrp = getCharacter()
    if not hrp then return nil, math.huge end
    
    local eggs = findAllEggs()
    local nearest, minDist = nil, CONFIG.MaxSearchRadius
    local myPos = hrp.Position
    
    for _, egg in ipairs(eggs) do
        local pos = getPosition(egg)
        if pos then
            local dist = (myPos - pos).Magnitude
            if dist < minDist then
                -- Лучевая проверка (опционально, можно убрать если лагает)
                local rayParams = RaycastParams.new()
                rayParams.FilterDescendantsInstances = {char}
                rayParams.FilterType = Enum.RaycastFilterType.Blacklist
                
                local dir = (pos - myPos).Unit * dist
                local result = Workspace:Raycast(myPos, dir, rayParams)
                
                if not result or result.Distance > dist - 3 or dist < 15 then
                    minDist = dist
                    nearest = egg
                end
            end
        end
    end
    
    return nearest, minDist
end

-- ==================== ESP ====================

function createESP(egg)
    if State.ESPObjects[egg] then return end
    if not CONFIG.ESP then return end
    
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "EasterEggESP"
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.new(0, 120, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 2.5, 0)
    billboard.MaxDistance = CONFIG.MaxSearchRadius
    
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, 0, 1, 0)
    label.Font = Enum.Font.GothamBold
    label.TextColor3 = CONFIG.ESPColor
    label.TextSize = CONFIG.ESPTextSize
    label.TextStrokeTransparency = 0.3
    label.Text = "🥚 " .. egg.Name .. "\n...m"
    
    -- Фон для читаемости
    local bg = Instance.new("Frame")
    bg.Name = "Bg"
    bg.BackgroundColor3 = Color3.new(0, 0, 0)
    bg.BackgroundTransparency = 0.7
    bg.BorderSizePixel = 0
    bg.Size = UDim2.new(1, 0, 1, 0)
    bg.ZIndex = -1
    bg.Parent = label
    
    label.Parent = billboard
    
    local connection = RunService.Heartbeat:Connect(function()
        if not egg or not egg.Parent or not CONFIG.ESP then
            billboard:Destroy()
            State.ESPObjects[egg] = nil
            return
        end
        
        if not isEggAvailable(egg) then
            billboard.Enabled = false
            return
        else
            billboard.Enabled = true
        end
        
        local pos = getPosition(egg)
        local _, _, hrp = getCharacter()
        if pos and hrp then
            local dist = (pos - hrp.Position).Magnitude
            label.Text = "🥚 " .. egg.Name .. "\n" .. math.floor(dist) .. "m"
            
            if State.CurrentTarget == egg then
                label.TextColor3 = Color3.fromRGB(255, 255, 0)
                bg.BackgroundColor3 = Color3.fromRGB(50, 50, 0)
            elseif dist < CONFIG.CollectionRadius then
                label.TextColor3 = Color3.fromRGB(0, 255, 0)
                bg.BackgroundColor3 = Color3.fromRGB(0, 50, 0)
            else
                label.TextColor3 = CONFIG.ESPColor
                bg.BackgroundColor3 = Color3.new(0, 0, 0)
            end
        end
    end)
    
    local part = egg:IsA("BasePart") and egg or egg:FindFirstChildWhichIsA("BasePart")
    if part then
        billboard.Adornee = part
        billboard.Parent = part
    else
        billboard.Parent = Workspace
    end
    
    State.ESPObjects[egg] = {Gui = billboard, Connection = connection}
end

function updateESP()
    if not CONFIG.ESP then
        for egg, data in pairs(State.ESPObjects) do
            data.Gui:Destroy()
            if data.Connection then data.Connection:Disconnect() end
        end
        State.ESPObjects = {}
        return
    end
    
    local eggs = findAllEggs()
    for _, egg in ipairs(eggs) do
        createESP(egg)
    end
    
    -- Чистим исчезнувшие
    for egg, data in pairs(State.ESPObjects) do
        if not egg.Parent or not isEggAvailable(egg) then
            data.Gui:Destroy()
            if data.Connection then data.Connection:Disconnect() end
            State.ESPObjects[egg] = nil
        end
    end
end

-- ==================== PATHFINDING ====================

function clearPathVisuals()
    for _, part in ipairs(State.PathVisuals) do
        part:Destroy()
    end
    State.PathVisuals = {}
end

function drawPath(waypoints)
    if not CONFIG.VisualizePath then return end
    clearPathVisuals()
    
    for i, wp in ipairs(waypoints) do
        local ball = Instance.new("Part")
        ball.Shape = Enum.PartType.Ball
        ball.Size = Vector3.new(0.4, 0.4, 0.4)
        ball.Position = wp.Position + Vector3.new(0, 0.3, 0)
        ball.Anchored = true
        ball.CanCollide = false
        ball.Material = Enum.Material.Neon
        ball.Color = (i == #waypoints) and Color3.fromRGB(0, 255, 0) or CONFIG.PathColor
        ball.Transparency = 0.2
        ball.Parent = Workspace
        table.insert(State.PathVisuals, ball)
    end
end

function walkTo(targetPos, onArrive)
    if State.IsMoving then return false end
    State.IsMoving = true
    
    local char, hum, hrp = getCharacter()
    if not hum then 
        State.IsMoving = false
        return false 
    end
    
    local path = PathfindingService:CreatePath({
        AgentRadius = CONFIG.AgentRadius,
        AgentHeight = CONFIG.AgentHeight,
        AgentCanJump = CONFIG.AgentCanJump,
        AgentJumpHeight = 8,
        Costs = {}
    })
    
    local success = pcall(function()
        path:ComputeAsync(hrp.Position, targetPos)
    end)
    
    if not success or path.Status ~= Enum.PathStatus.Success then
        -- Fallback
        hum:MoveTo(targetPos)
        State.IsMoving = false
        return false
    end
    
    local waypoints = path:GetWaypoints()
    if #waypoints < 2 then
        State.IsMoving = false
        return false
    end
    
    drawPath(waypoints)
    
    local blockedConn = path.Blocked:Connect(function(blockedIdx)
        if blockedIdx >= 2 then
            State.IsMoving = false
        end
    end)
    
    for i = 2, #waypoints do
        if not State.IsMoving then break end
        
        -- Проверяем, не украли ли яйцо по дороге
        if State.CurrentTarget and not isEggAvailable(State.CurrentTarget) then
            State.IsMoving = false
            break
        end
        
        local wp = waypoints[i]
        
        if wp.Action == Enum.PathWaypointAction.Jump then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
            task.wait(0.1)
        end
        
        hum:MoveTo(wp.Position)
        local reached = hum.MoveToFinished:Wait()
        
        if not reached then
            State.IsMoving = false
            break
        end
    end
    
    if blockedConn then blockedConn:Disconnect() end
    clearPathVisuals()
    State.IsMoving = false
    
    if onArrive then onArrive() end
    return true
end

-- ==================== СБОР ====================

function collectEgg(egg)
    if not egg or not egg.Parent then 
        markAsCollected(egg)
        return true 
    end
    
    local char = player.Character
    if not char then return false end
    
    -- ProximityPrompt
    local prompt = egg:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        pcall(fireproximityprompt, prompt)
    end
    
    -- ClickDetector
    local click = egg:FindFirstChildWhichIsA("ClickDetector", true)
    if click then
        pcall(fireclickdetector, click)
    end
    
    -- Touch
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local part = egg:IsA("BasePart") and egg or egg:FindFirstChildWhichIsA("BasePart")
    if hrp and part then
        pcall(function()
            firetouchinterest(hrp, part, 0)
            task.wait(0.05)
            firetouchinterest(hrp, part, 1)
        end)
    end
    
    -- Проверяем результат
    task.wait(0.2)
    if not egg.Parent then
        markAsCollected(egg)
        return true
    end
    
    -- Повторная проверка через прозрачность
    if egg:IsA("BasePart") and egg.Transparency >= 1 then
        markAsCollected(egg)
        return true
    end
    
    return false
end

-- ==================== ГЛАВНЫЙ ЦИКЛ ====================

function mainLoop()
    while true do
        task.wait(CONFIG.CheckInterval)
        
        if not CONFIG.Enabled then
            updateESP()
            continue
        end
        
        local char, hum, hrp = getCharacter()
        if not char then
            player.CharacterAdded:Wait()
            task.wait(1)
            continue
        end
        
        updateESP()
        
        if State.IsMoving then continue end
        
        local egg, dist = getNearestEgg()
        
        if egg and isEggAvailable(egg) then
            State.CurrentTarget = egg
            local eggPos = getPosition(egg)
            
            if eggPos then
                if dist > CONFIG.CollectionRadius then
                    walkTo(eggPos, function()
                        if egg and egg.Parent and isEggAvailable(egg) then
                            collectEgg(egg)
                        end
                    end)
                else
                    collectEgg(egg)
                end
            end
        else
            State.CurrentTarget = nil
        end
    end
end

-- ==================== UI ====================

MainTab:CreateToggle({
    Name = "Auto Collect",
    CurrentValue = false,
    Flag = "AutoCollect",
    Callback = function(Value)
        CONFIG.Enabled = Value
    end
})

MainTab:CreateToggle({
    Name = "Ignore Already Collected",
    CurrentValue = true,
    Flag = "IgnoreCollected",
    Callback = function(Value)
        CONFIG.IgnoreCollected = Value
    end
})

MainTab:CreateSlider({
    Name = "Collection Radius",
    Range = {3, 20},
    Increment = 1,
    Suffix = "studs",
    CurrentValue = 8,
    Flag = "CollectionRadius",
    Callback = function(Value)
        CONFIG.CollectionRadius = Value
    end
})

VisualTab:CreateToggle({
    Name = "Egg ESP",
    CurrentValue = true,
    Flag = "ESPEnabled",
    Callback = function(Value)
        CONFIG.ESP = Value
        if not Value then
            for egg, data in pairs(State.ESPObjects) do
                data.Gui:Destroy()
                if data.Connection then data.Connection:Disconnect() end
            end
            State.ESPObjects = {}
        end
    end
})

VisualTab:CreateColorPicker({
    Name = "ESP Color",
    Color = CONFIG.ESPColor,
    Flag = "ESPColor",
    Callback = function(Value)
        CONFIG.ESPColor = Value
    end
})

VisualTab:CreateToggle({
    Name = "Show Path",
    CurrentValue = false,
    Flag = "VisualizePath",
    Callback = function(Value)
        CONFIG.VisualizePath = Value
        if not Value then clearPathVisuals() end
    end
})

SettingsTab:CreateSlider({
    Name = "Max Search Radius",
    Range = {50, 2000},
    Increment = 50,
    Suffix = "studs",
    CurrentValue = 1000,
    Flag = "MaxRadius",
    Callback = function(Value)
        CONFIG.MaxSearchRadius = Value
    end
})

SettingsTab:CreateSlider({
    Name = "Check Speed",
    Range = {0.1, 1},
    Increment = 0.1,
    Suffix = "s",
    CurrentValue = 0.2,
    Flag = "CheckInterval",
    Callback = function(Value)
        CONFIG.CheckInterval = Value
    end
})

SettingsTab:CreateButton({
    Name = "Reset Collected Cache",
    Callback = function()
        State.CollectedEggs = {}
        Rayfield:Notify({
            Title = "Cache Reset",
            Content = "Collected eggs memory cleared!",
            Duration = 3
        })
    end
})

-- ==================== ЗАПУСК ====================

task.spawn(mainLoop)

local initialEggs = findAllEggs()
Rayfield:Notify({
    Title = "EasterEggs Loaded",
    Content = "Found " .. #initialEggs .. " eggs in Workspace.EasterEggs",
    Duration = 5
})
