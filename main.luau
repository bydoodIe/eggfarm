local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- ==================== RAYFIELD UI ====================
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "Egg Collector",
    LoadingTitle = "Egg Hunter",
    LoadingSubtitle = "by Sirius",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "EggHunt",
        FileName = "Config"
    },
    Discord = {
        Enabled = false,
        Invite = "noinvitelink",
        RememberJoins = true
    },
    KeySystem = false
})

local MainTab = Window:CreateTab("Main", 4483362458)
local VisualTab = Window:CreateTab("Visuals", 4483362458)
local SettingsTab = Window:CreateTab("Settings", 4483362458)

-- ==================== НАСТРОЙКИ ====================
local CONFIG = {
    Enabled = false,
    ESP = true,
    ESPColor = Color3.fromRGB(0, 255, 255),
    ESPTextSize = 14,
    CollectionRadius = 8,
    AgentRadius = 2,
    AgentHeight = 5,
    AgentCanJump = true,
    VisualizePath = false,
    PathColor = Color3.fromRGB(255, 255, 0),
    IgnoreCollected = true,
    CheckInterval = 0.3,
    MaxSearchRadius = 500,
    
    -- Пути к яйцам (проверяются по порядку)
    EggPaths = {
        Workspace:FindFirstChild("Hunts") and Workspace.Hunts:FindFirstChild("Eggs"),
        Workspace:FindFirstChild("Eggs"),
        Workspace:FindFirstChild("Hunts") and Workspace.Hunts:FindFirstChild("Egg"),
        ReplicatedStorage:FindFirstChild("Hunts") and ReplicatedStorage.Hunts:FindFirstChild("Egg"),
    }
}

-- ==================== СОСТОЯНИЕ ====================
local State = {
    IsMoving = false,
    CurrentTarget = nil,
    CollectedEggs = {}, -- ID собранных яиц
    ESPObjects = {},    -- Хранилище ESP объектов
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
    
    local name = obj.Name:lower()
    return name:find("egg") or name:find("hunt") or name:find("яйцо")
end

function getEggID(egg)
    -- Уникальный ID для отслеживания
    return egg:GetFullName() .. "_" .. tostring(egg.LayoutOrder or 0)
end

-- ==================== ПРОВЕРКА ЗАНЯТОСТИ ====================

function isEggAvailable(egg)
    if not CONFIG.IgnoreCollected then return true end
    
    local id = getEggID(egg)
    
    -- Проверяем в локальном списке собранных
    if State.CollectedEggs[id] then
        -- Проверяем, не появилось ли яйцо снова (таймер респавна)
        if tick() - State.CollectedEggs[id] > 30 then
            State.CollectedEggs[id] = nil
            return true
        end
        return false
    end
    
    -- Проверяем видимость и доступность
    local pos = getPosition(egg)
    if not pos then return false end
    
    -- Проверяем, не собрал ли кто-то другой (исчезло ли яйцо)
    if egg:IsA("BasePart") and egg.Transparency >= 1 then
        State.CollectedEggs[id] = tick()
        return false
    end
    
    -- Проверяем CanCollide и другие свойства
    if egg:IsA("BasePart") and not egg.CanCollide and egg.Transparency > 0.8 then
        State.CollectedEggs[id] = tick()
        return false
    end
    
    return true
end

function markAsCollected(egg)
    local id = getEggID(egg)
    State.CollectedEggs[id] = tick()
    State.CurrentTarget = nil
end

-- ==================== ПОИСК ЯИЦ ====================

function findEggFolder()
    for _, folder in ipairs(CONFIG.EggPaths) do
        if folder then return folder end
    end
    return Workspace
end

function findAllEggs()
    local eggs = {}
    local folder = findEggFolder()
    
    for _, obj in ipairs(folder:GetDescendants()) do
        if isValidEgg(obj) and isEggAvailable(obj) then
            table.insert(eggs, obj)
        end
    end
    
    -- Также проверяем ReplicatedStorage на скрытые яйца
    local rsFolder = ReplicatedStorage:FindFirstChild("Hunts")
    if rsFolder then
        for _, obj in ipairs(rsFolder:GetDescendants()) do
            if isValidEgg(obj) and not table.find(eggs, obj) then
                -- Проверяем, есть ли клон в Workspace
                local existsInWorkspace = false
                for _, egg in ipairs(eggs) do
                    if egg.Name == obj.Name then
                        existsInWorkspace = true
                        break
                    end
                end
                if not existsInWorkspace then
                    table.insert(eggs, obj)
                end
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
                -- Проверяем линию видимости
                local rayParams = RaycastParams.new()
                rayParams.FilterDescendantsInstances = {char}
                rayParams.FilterType = Enum.RaycastFilterType.Blacklist
                
                local direction = (pos - myPos).Unit * dist
                local rayResult = Workspace:Raycast(myPos, direction, rayParams)
                
                -- Если нет препятствий или расстояние маленькое — берём
                if not rayResult or rayResult.Distance > dist - 2 or dist < 20 then
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
    
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "EggESP"
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.new(0, 100, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.MaxDistance = CONFIG.MaxSearchRadius
    
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, 0, 1, 0)
    label.Font = Enum.Font.GothamBold
    label.TextColor3 = CONFIG.ESPColor
    label.TextSize = CONFIG.ESPTextSize
    label.TextStrokeTransparency = 0.5
    label.Text = "🥚 " .. egg.Name .. "\n" .. math.floor((getPosition(egg) - (getCharacter() and getCharacter().Position or Vector3.zero)).Magnitude) .. "m"
    
    -- Дистанция обновляется
    local connection = RunService.Heartbeat:Connect(function()
        if not egg or not egg.Parent or not CONFIG.ESP then
            billboard:Destroy()
            State.ESPObjects[egg] = nil
            return
        end
        
        local pos = getPosition(egg)
        local _, _, hrp = getCharacter()
        if pos and hrp then
            local dist = (pos - hrp.Position).Magnitude
            label.Text = "🥚 " .. egg.Name .. "\n" .. math.floor(dist) .. "m"
            
            -- Меняем цвет в зависимости от дистанции
            if dist < CONFIG.CollectionRadius then
                label.TextColor3 = Color3.fromRGB(0, 255, 0) -- Зелёный (рядом)
            elseif State.CurrentTarget == egg then
                label.TextColor3 = Color3.fromRGB(255, 255, 0) -- Жёлтый (цель)
            else
                label.TextColor3 = CONFIG.ESPColor -- Стандартный
            end
        end
    end)
    
    label.Parent = billboard
    
    -- Привязываем к яйцу или создаём Attachment
    local part = egg:IsA("BasePart") and egg or egg:FindFirstChildWhichIsA("BasePart")
    if part then
        billboard.Adornee = part
    end
    
    billboard.Parent = egg:IsA("BasePart") and egg or (part or Workspace)
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
    
    -- Удаляем ESP для исчезнувших яиц
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
        ball.Size = Vector3.new(0.3, 0.3, 0.3)
        ball.Position = wp.Position + Vector3.new(0, 0.5, 0)
        ball.Anchored = true
        ball.CanCollide = false
        ball.Material = Enum.Material.Neon
        ball.Color = (i == #waypoints) and Color3.fromRGB(0, 255, 0) or CONFIG.PathColor
        ball.Transparency = 0.3
        ball.Parent = Workspace
        table.insert(State.PathVisuals, ball)
    end
end

function walkTo(targetPos, callback)
    if State.IsMoving then return false end
    State.IsMoving = true
    
    local char, hum, hrp = getCharacter()
    if not hum then 
        State.IsMoving = false
        return false 
    end
    
    local pathParams = {
        AgentRadius = CONFIG.AgentRadius,
        AgentHeight = CONFIG.AgentHeight,
        AgentCanJump = CONFIG.AgentCanJump,
        Costs = {
            Water = 20,
            DangerZone = math.huge
        }
    }
    
    local path = PathfindingService:CreatePath(pathParams)
    local success, err = pcall(function()
        path:ComputeAsync(hrp.Position, targetPos)
    end)
    
    if not success or path.Status ~= Enum.PathStatus.Success then
        -- Fallback: прямое движение
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
        if blockedIdx > 1 then
            State.IsMoving = false
        end
    end)
    
    -- Движение по точкам
    for i = 2, #waypoints do
        if not State.IsMoving then break end
        if not isEggAvailable(State.CurrentTarget) then
            State.IsMoving = false
            break
        end
        
        local wp = waypoints[i]
        
        if wp.Action == Enum.PathWaypointAction.Jump then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
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
    
    if callback then callback() end
    return true
end

-- ==================== СБОР ====================

function collectEgg(egg)
    if not egg or not egg.Parent then 
        markAsCollected(egg)
        return false 
    end
    
    local collected = false
    
    -- ProximityPrompt
    local prompt = egg:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        pcall(function()
            fireproximityprompt(prompt)
            collected = true
        end)
    end
    
    -- ClickDetector
    local click = egg:FindFirstChildWhichIsA("ClickDetector", true)
    if click then
        pcall(function()
            fireclickdetector(click)
            collected = true
        end)
    end
    
    -- TouchInterest
    local part = egg:IsA("BasePart") and egg or egg:FindFirstChildWhichIsA("BasePart")
    if part then
        pcall(function()
            firetouchinterest(player.Character.HumanoidRootPart, part, 0)
            task.wait(0.1)
            firetouchinterest(player.Character.HumanoidRootPart, part, 1)
            collected = true
        end)
    end
    
    -- Проверяем, собрали ли
    task.wait(0.3)
    if not egg.Parent or (egg:IsA("BasePart") and egg.Transparency >= 1) then
        markAsCollected(egg)
        return true
    end
    
    return collected
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
        
        -- Если уже идём — пропускаем
        if State.IsMoving then continue end
        
        local egg, dist = getNearestEgg()
        
        if egg then
            State.CurrentTarget = egg
            local eggPos = getPosition(egg)
            
            if eggPos then
                if dist > CONFIG.CollectionRadius then
                    -- Идём к яйцу
                    walkTo(eggPos, function()
                        -- По прибытии пытаемся собрать
                        if isEggAvailable(egg) then
                            collectEgg(egg)
                        end
                    end)
                else
                    -- Уже рядом — собираем
                    collectEgg(egg)
                end
            end
        else
            State.CurrentTarget = nil
        end
    end
end

-- ==================== UI ЭЛЕМЕНТЫ ====================

MainTab:CreateToggle({
    Name = "Auto Collect",
    CurrentValue = false,
    Flag = "AutoCollect",
    Callback = function(Value)
        CONFIG.Enabled = Value
    end
})

MainTab:CreateToggle({
    Name = "Ignore Collected",
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
    Name = "ESP Enabled",
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
    Name = "Visualize Path",
    CurrentValue = false,
    Flag = "VisualizePath",
    Callback = function(Value)
        CONFIG.VisualizePath = Value
        if not Value then clearPathVisuals() end
    end
})

SettingsTab:CreateSlider({
    Name = "Max Search Radius",
    Range = {100, 2000},
    Increment = 50,
    Suffix = "studs",
    CurrentValue = 500,
    Flag = "MaxRadius",
    Callback = function(Value)
        CONFIG.MaxSearchRadius = Value
    end
})

SettingsTab:CreateSlider({
    Name = "Check Interval",
    Range = {0.1, 1},
    Increment = 0.1,
    Suffix = "s",
    CurrentValue = 0.3,
    Flag = "CheckInterval",
    Callback = function(Value)
        CONFIG.CheckInterval = Value
    end
})

SettingsTab:CreateButton({
    Name = "Clear Collected Cache",
    Callback = function()
        State.CollectedEggs = {}
        Rayfield:Notify({
            Title = "Cache Cleared",
            Content = "Collected eggs list has been reset",
            Duration = 3
        })
    end
})

-- ==================== ЗАПУСК ====================

task.spawn(mainLoop)

Rayfield:Notify({
    Title = "Egg Collector Loaded",
    Content = "Found " .. #findAllEggs() .. " eggs nearby",
    Duration = 5
})
