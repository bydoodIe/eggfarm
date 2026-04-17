local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

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
    ESPColor = Color3.fromRGB(255, 105, 180),
    ESPTextSize = 14,
    CollectionRadius = 12,
    AgentRadius = 2,
    AgentHeight = 4,
    AgentCanJump = true,
    VisualizePath = true,
    PathColor = Color3.fromRGB(255, 255, 0),
    IgnoreCollected = true,
    CheckInterval = 0.5,
    MaxSearchRadius = 1000,
    PathCooldown = 1.5,
    MinDirectWalk = 40,           -- УВЕЛИЧЕНО: до 40, ближе 40 идём сразу напрямую
    MaxStuckTime = 3,             -- УМЕНЬШЕНО: если 3 сек не двигаемся — отмена
    PathFailCooldown = 10,
    EggFolder = Workspace:WaitForChild("EasterEggs", 10)
}

-- ==================== СОСТОЯНИЕ ====================
local State = {
    IsMoving = false,
    CurrentTarget = nil,
    CurrentTargetPos = nil,
    TargetLocked = false,
    CollectedEggs = setmetatable({}, { __mode = "k" }),
    ESPObjects = {},
    PathVisuals = {},
    LastPathBuild = 0,
    LastArrivalTime = 0,
    MoveStartedAt = 0,
    FailedPaths = {},
    TargetAttempts = 0
}

-- ==================== УТИЛИТЫ ====================

local function getCharacter()
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

local function getPosition(obj)
    if not obj or not obj.Parent then
        return nil
    end

    if obj:IsA("BasePart") then
        return obj.Position
    elseif obj:IsA("Model") then
        return obj:GetPivot().Position
    end

    return nil
end

local function isValidEgg(obj)
    if not (obj:IsA("BasePart") or obj:IsA("Model")) then
        return false
    end
    if not obj.Parent then
        return false
    end
    return true
end

local function lockTarget(egg, pos)
    State.CurrentTarget = egg
    State.CurrentTargetPos = pos
    State.TargetLocked = true
    State.MoveStartedAt = tick()
    State.TargetAttempts = 0
end

local function unlockTarget()
    State.CurrentTarget = nil
    State.CurrentTargetPos = nil
    State.TargetLocked = false
    State.TargetAttempts = 0
end

-- ==================== ПРОВЕРКА ДОСТУПНОСТИ ====================

local function isEggAvailable(egg)
    if not CONFIG.IgnoreCollected then
        return true
    end

    if not egg or not egg.Parent then
        return false
    end

    if State.FailedPaths[egg] then
        if tick() - State.FailedPaths[egg] < CONFIG.PathFailCooldown then
            return false
        else
            State.FailedPaths[egg] = nil
        end
    end

    local seenAt = State.CollectedEggs[egg]
    if seenAt then
        if tick() - seenAt > 30 then
            State.CollectedEggs[egg] = nil
            return true
        end
        return false
    end

    if egg:IsA("BasePart") then
        if egg.Transparency >= 1 then
            State.CollectedEggs[egg] = tick()
            return false
        end
    elseif egg:IsA("Model") then
        local visible = false
        for _, part in ipairs(egg:GetDescendants()) do
            if part:IsA("BasePart") and part.Transparency < 1 then
                visible = true
                break
            end
        end
        if not visible then
            State.CollectedEggs[egg] = tick()
            return false
        end
    end

    return true
end

local function markAsCollected(egg)
    if egg then
        State.CollectedEggs[egg] = tick()
    end
end

-- ==================== ПОИСК ЯИЦ ====================

local function findAllEggs()
    local eggs = {}
    local folder = CONFIG.EggFolder

    if not folder or not folder.Parent then
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

    return eggs
end

local function getNearestEgg()
    local _, _, hrp = getCharacter()
    if not hrp then
        return nil, math.huge
    end

    local eggs = findAllEggs()
    local nearest = nil
    local minDist = CONFIG.MaxSearchRadius
    local myPos = hrp.Position

    for _, egg in ipairs(eggs) do
        local pos = getPosition(egg)
        if pos then
            local dist = (myPos - pos).Magnitude
            if dist < minDist then
                minDist = dist
                nearest = egg
            end
        end
    end

    return nearest, minDist
end

-- ==================== ESP ====================

local function createESP(egg)
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

    local bg = Instance.new("Frame")
    bg.Name = "Bg"
    bg.BackgroundColor3 = Color3.new(0, 0, 0)
    bg.BackgroundTransparency = 0.7
    bg.BorderSizePixel = 0
    bg.Size = UDim2.new(1, 0, 1, 0)
    bg.ZIndex = -1
    bg.Parent = label

    label.Parent = billboard

    local connection
    connection = RunService.Heartbeat:Connect(function()
        if not egg or not egg.Parent or not CONFIG.ESP then
            if billboard then billboard:Destroy() end
            State.ESPObjects[egg] = nil
            if connection then connection:Disconnect() end
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

    State.ESPObjects[egg] = { Gui = billboard, Connection = connection }
end

local function updateESP()
    if not CONFIG.ESP then
        for egg, data in pairs(State.ESPObjects) do
            if data.Gui then data.Gui:Destroy() end
            if data.Connection then data.Connection:Disconnect() end
        end
        State.ESPObjects = {}
        return
    end

    local eggs = findAllEggs()
    for _, egg in ipairs(eggs) do
        createESP(egg)
    end

    for egg, data in pairs(State.ESPObjects) do
        if not egg.Parent or not isEggAvailable(egg) then
            if data.Gui then data.Gui:Destroy() end
            if data.Connection then data.Connection:Disconnect() end
            State.ESPObjects[egg] = nil
        end
    end
end

-- ==================== ПУТЬ ====================

local function clearPathVisuals()
    for _, part in ipairs(State.PathVisuals) do
        if part then
            part:Destroy()
        end
    end
    State.PathVisuals = {}
end

local function drawPath(waypoints)
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

-- ==================== ДВИЖЕНИЕ ====================

-- УПРОЩЁННЫЙ: просто идём к цели, не важно выше/ниже
local function walkDirect(targetPos)
    if State.IsMoving then return false end
    State.IsMoving = true
    State.LastPathBuild = tick()
    State.MoveStartedAt = tick()

    local _, hum, hrp = getCharacter()
    if not hum or not hrp then
        State.IsMoving = false
        return false
    end

    hum:MoveTo(targetPos)

    local lastPos = hrp.Position
    local stuckTimer = 0

    local conn
    conn = RunService.Heartbeat:Connect(function(dt)
        if not State.IsMoving then
            if conn then conn:Disconnect() end
            return
        end

        local _, _, currentHrp = getCharacter()
        if not currentHrp then
            State.IsMoving = false
            if conn then conn:Disconnect() end
            return
        end

        local dist = (currentHrp.Position - targetPos).Magnitude
        if dist <= CONFIG.CollectionRadius then
            State.IsMoving = false
            if conn then conn:Disconnect() end
            return
        end

        -- Проверка застревания: если не двигаемся — просто ждём таймаут
        if (currentHrp.Position - lastPos).Magnitude < 0.1 then
            stuckTimer += dt
            if stuckTimer > CONFIG.MaxStuckTime then
                State.IsMoving = false
                if conn then conn:Disconnect() end
                return
            end
        else
            stuckTimer = 0
            lastPos = currentHrp.Position
        end

        -- Перезапускаем MoveTo каждую секунду, чтобы не было таймаута
        if tick() - State.MoveStartedAt % 1 < dt then
            hum:MoveTo(targetPos)
        end
    end)

    repeat task.wait(0.1) until not State.IsMoving
    if conn then conn:Disconnect() end

    State.LastArrivalTime = tick()
    return true
end

local function walkPathfind(targetPos)
    if State.IsMoving then return false end
    State.IsMoving = true
    State.LastPathBuild = tick()
    State.MoveStartedAt = tick()

    local _, hum, hrp = getCharacter()
    if not hum or not hrp then
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
        State.IsMoving = false
        return false
    end

    local waypoints = path:GetWaypoints()
    if #waypoints < 2 then
        State.IsMoving = false
        return false
    end

    drawPath(waypoints)

    local filteredPoints = {}
    for i = 2, #waypoints do
        local wp = waypoints[i]
        if i == #waypoints or (wp.Position - hrp.Position).Magnitude > 4 then
            table.insert(filteredPoints, wp)
        end
    end

    if #filteredPoints == 0 then
        State.IsMoving = false
        return false
    end

    local currentPointIdx = 1
    local lastPos = hrp.Position
    local stuckTimer = 0

    local heartbeatConn
    heartbeatConn = RunService.Heartbeat:Connect(function(dt)
        if not State.IsMoving then
            if heartbeatConn then heartbeatConn:Disconnect() end
            return
        end

        local _, _, currentHrp = getCharacter()
        if not currentHrp then
            State.IsMoving = false
            if heartbeatConn then heartbeatConn:Disconnect() end
            return
        end

        local distToGoal = (currentHrp.Position - targetPos).Magnitude
        if distToGoal <= CONFIG.CollectionRadius then
            State.IsMoving = false
            if heartbeatConn then heartbeatConn:Disconnect() end
            return
        end

        local target = filteredPoints[currentPointIdx]
        if not target then
            hum:MoveTo(targetPos)
            return
        end

        if (currentHrp.Position - lastPos).Magnitude < 0.1 then
            stuckTimer += dt
            if stuckTimer > CONFIG.MaxStuckTime then
                State.IsMoving = false
                if heartbeatConn then heartbeatConn:Disconnect() end
                return
            end
        else
            stuckTimer = 0
            lastPos = currentHrp.Position
        end

        local dist = (currentHrp.Position - target.Position).Magnitude
        if dist < 3 then
            currentPointIdx += 1
            target = filteredPoints[currentPointIdx]
            if not target then
                hum:MoveTo(targetPos)
                return
            end
        end

        hum:MoveTo(target.Position)

        -- Прыгаем ТОЛЬКО если точка пути явно требует прыжка
        if target.Action == Enum.PathWaypointAction.Jump then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)

    while State.IsMoving do
        task.wait(0.05)
    end

    if heartbeatConn then heartbeatConn:Disconnect() end
    clearPathVisuals()

    State.LastArrivalTime = tick()
    return true
end

-- ГЛАВНАЯ ФУНКЦИЯ ДВИЖЕНИЯ: просто идём к цели
local function walkTo(targetPos, egg)
    local _, _, hrp = getCharacter()
    if not hrp then return false end

    lockTarget(egg, targetPos)

    local dist = (hrp.Position - targetPos).Magnitude

    -- Ближе 40 — просто идём напрямую (MoveTo разберётся сам, упадёт/поднимется)
    if dist < CONFIG.MinDirectWalk then
        return walkDirect(targetPos)
    else
        -- Дальше 40 — пробуем паффайндинг для обхода препятствий
        local ok = walkPathfind(targetPos)
        if not ok then
            -- Если путь не построился — всё равно идём напрямую
            return walkDirect(targetPos)
        end
        return ok
    end
end

-- ==================== СБОР ЯЙЦА ====================

local function collectEgg(egg)
    if not egg or not egg.Parent then return false end

    local char = player.Character
    if not char then return false end

    local prompt = egg:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        pcall(fireproximityprompt, prompt)
    end

    local click = egg:FindFirstChildWhichIsA("ClickDetector", true)
    if click then
        pcall(fireclickdetector, click)
    end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    local part = egg:IsA("BasePart") and egg or egg:FindFirstChildWhichIsA("BasePart")

    if hrp and part then
        pcall(function()
            firetouchinterest(hrp, part, 0)
            task.wait(0.05)
            firetouchinterest(hrp, part, 1)
        end)
    end

    task.wait(0.3)

    if not egg.Parent then
        markAsCollected(egg)
        return true
    end

    if egg:IsA("BasePart") and egg.Transparency >= 1 then
        markAsCollected(egg)
        return true
    end

    if egg:IsA("Model") then
        local visible = false
        for _, partObj in ipairs(egg:GetDescendants()) do
            if partObj:IsA("BasePart") and partObj.Transparency < 1 then
                visible = true
                break
            end
        end
        if not visible then
            markAsCollected(egg)
            return true
        end
    end

    return false
end

-- ==================== ГЛАВНЫЙ ЦИКЛ ====================

local function mainLoop()
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

        if State.IsMoving then
            continue
        end

        if tick() - State.LastPathBuild < CONFIG.PathCooldown then
            continue
        end

        if tick() - State.LastArrivalTime < 0.2 then
            continue
        end

        -- Сохраняем текущую цель, если она ещё валидна
        local targetEgg = State.CurrentTarget
        local targetPos = State.CurrentTargetPos

        if targetEgg and targetEgg.Parent and isEggAvailable(targetEgg) then
            local freshPos = getPosition(targetEgg)
            if freshPos then
                targetPos = freshPos
                State.CurrentTargetPos = freshPos
            end
        else
            unlockTarget()
            targetEgg = nil
            targetPos = nil
        end

        -- Ищем новую цель, если нужно
        if not targetPos then
            local egg = getNearestEgg()
            if egg then
                targetEgg = egg
                targetPos = getPosition(egg)
                if targetPos then
                    lockTarget(targetEgg, targetPos)
                end
            end
        end

        if targetPos then
            local dist = (hrp.Position - targetPos).Magnitude

            if dist > CONFIG.CollectionRadius then
                local success = walkTo(targetPos, targetEgg)
                if not success and targetEgg then
                    -- Не смог дойти — помечаем и идём к другому
                    State.FailedPaths[targetEgg] = tick()
                    unlockTarget()
                    task.wait(0.5)
                end
            else
                if targetEgg then
                    local collected = collectEgg(targetEgg)
                    if collected then
                        markAsCollected(targetEgg)
                        unlockTarget()
                        State.LastArrivalTime = tick()
                    else
                        -- Не собралось — пробуем ещё пару раз
                        State.TargetAttempts += 1
                        if State.TargetAttempts > 3 then
                            State.FailedPaths[targetEgg] = tick()
                            unlockTarget()
                            State.LastArrivalTime = tick()
                        else
                            task.wait(0.3)
                        end
                    end
                else
                    unlockTarget()
                end
            end
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
    Range = {3, 25},
    Increment = 1,
    Suffix = "studs",
    CurrentValue = 12,
    Flag = "CollectionRadius",
    Callback = function(Value)
        CONFIG.CollectionRadius = Value
    end
})

MainTab:CreateSlider({
    Name = "Min Pathfinding Distance",
    Range = {10, 100},
    Increment = 5,
    Suffix = "studs",
    CurrentValue = 40,
    Flag = "MinDirectWalk",
    Callback = function(Value)
        CONFIG.MinDirectWalk = Value
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
                if data.Gui then data.Gui:Destroy() end
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
    CurrentValue = true,
    Flag = "VisualizePath",
    Callback = function(Value)
        CONFIG.VisualizePath = Value
        if not Value then
            clearPathVisuals()
        end
    end
})

SettingsTab:CreateSlider({
    Name = "Path Cooldown",
    Range = {0.5, 5},
    Increment = 0.5,
    Suffix = "sec",
    CurrentValue = 1.5,
    Flag = "PathCooldown",
    Callback = function(Value)
        CONFIG.PathCooldown = Value
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

SettingsTab:CreateButton({
    Name = "Reset Collected Cache",
    Callback = function()
        State.CollectedEggs = setmetatable({}, { __mode = "k" })
        State.FailedPaths = {}
        unlockTarget()
        Rayfield:Notify({
            Title = "Cache Reset",
            Content = "All collected egg cache cleared!",
            Duration = 3
        })
    end
})

-- ==================== ЗАПУСК ====================

task.spawn(mainLoop)

local initialEggs = findAllEggs()
Rayfield:Notify({
    Title = "EasterEggs Loaded",
    Content = "Found " .. #initialEggs .. " eggs. Surface-agnostic movement active!",
    Duration = 5
})
