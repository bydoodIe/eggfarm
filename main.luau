--// Rayfield
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "Easter Egg Auto-Farm",
    LoadingTitle = "Easter Eggs",
    LoadingSubtitle = "Smart Navigation v3",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false
})

local MainTab   = Window:CreateTab("Main", 4483362458)
local VisualTab = Window:CreateTab("ESP", 4483362458)
local SetTab    = Window:CreateTab("Settings", 4483362458)

--// Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")

--// Locals
local plr      = Players.LocalPlayer
local char     = plr.Character or plr.CharacterAdded:Wait()
local hrp      = char:WaitForChild("HumanoidRootPart")
local hum      = char:WaitForChild("Humanoid")

local autoFarm   = false
local espEnabled = false
local farmSpeed  = 16
local currentTarget = nil
local espCache = {}

-- Pathfinding setup
local path = PathfindingService:CreatePath({
    AgentRadius = 2,
    AgentHeight = 5,
    AgentCanJump = true,       -- Прыгает через препятствия
    AgentCanClimb = false,
    WaypointSpacing = 4,       -- Точнее = меньше застреваний
    Costs = {}
})

local currentWaypoints = {}
local wpIndex = 1
local navState = "idle"        -- idle / path / direct
local lastPos = Vector3.zero
local stuckTimer = 0

--// Обновление персонажа после респавна
plr.CharacterAdded:Connect(function(c)
    char = c
    hrp  = c:WaitForChild("HumanoidRootPart")
    hum  = c:WaitForChild("Humanoid")
    currentWaypoints = {}
    wpIndex = 1
    navState = "idle"
    currentTarget = nil
end)

--// Получить яйца
local function getEggs()
    local eggs = {}
    local folder = workspace:FindFirstChild("EasterEggs")
    if not folder then return eggs end
    for _, obj in ipairs(folder:GetDescendants()) do
        if obj:IsA("BasePart") or obj:IsA("MeshPart") then
            table.insert(eggs, obj)
        end
    end
    return eggs
end

local function getClosestEgg()
    local eggs = getEggs()
    if #eggs == 0 then return nil end
    local closest, minDist = nil, math.huge
    local pos = hrp and hrp.Position
    if not pos then return nil end
    for _, egg in ipairs(eggs) do
        if not egg or not egg.Parent then continue end
        local d = (egg.Position - pos).Magnitude
        if d < minDist then
            minDist = d
            closest = egg
        end
    end
    return closest
end

--// Построить путь (обход гор/стен)
local function computePath(target)
    currentWaypoints = {}
    wpIndex = 1
    if not target or not hrp then return false end
    local ok = pcall(function()
        path:ComputeAsync(hrp.Position, target.Position)
    end)
    if ok and path.Status == Enum.PathStatus.Success then
        currentWaypoints = path:GetWaypoints()
        return #currentWaypoints > 0
    end
    return false
end

--// Raycast для обнаружения стен
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Blacklist

local function isObstructed(direction, distance)
    if not hrp then return false end
    rayParams.FilterDescendantsInstances = {char}
    local result = workspace:Raycast(hrp.Position, direction.Unit * distance, rayParams)
    return result ~= nil
end

--// ГЛАВНЫЙ ЦИКЛ ДВИЖЕНИЯ (Heartbeat)
RunService.Heartbeat:Connect(function(dt)
    if not autoFarm then
        if navState ~= "idle" then
            navState = "idle"
            currentTarget = nil
            currentWaypoints = {}
            if hum then
                hum.PlatformStand = false
                hum.AutoRotate = true
            end
            if hrp then hrp.AssemblyLinearVelocity = Vector3.zero end
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = true end
            end
        end
        return
    end

    if not hrp or not char then return end

    -- Noclip + отключаем Humanoid (он мешает скорости)
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide = false end
    end
    if hum then
        hum.PlatformStand = true
        hum.AutoRotate = false
    end

    -- Нет цели? Ищем ближайшую
    if not currentTarget or not currentTarget.Parent then
        currentTarget = getClosestEgg()
        currentWaypoints = {}
        wpIndex = 1
        navState = "idle"
        if not currentTarget then return end
    end

    -- Если только нашли цель — строим путь
    if navState == "idle" or (#currentWaypoints == 0 and navState ~= "direct") then
        if computePath(currentTarget) then
            navState = "path"
        else
            navState = "direct" -- Не построился путь? Летим напрямую
        end
        stuckTimer = 0
        lastPos = hrp.Position
    end

    --// АНТИ-СТУК: если не двигаемся — принудительно в direct
    local moved = (hrp.Position - lastPos).Magnitude
    if moved < 0.3 then
        stuckTimer += dt
        if stuckTimer > 0.8 then
            navState = "direct" -- Застрял! Вылетаем вверх
            stuckTimer = 0
        end
    else
        stuckTimer = 0
    end
    lastPos = hrp.Position

    --// РЕЖИМ 1: Pathfinding (обходит горы по земле)
    if navState == "path" and wpIndex <= #currentWaypoints then
        local wp = currentWaypoints[wpIndex]
        local dist = (wp.Position - hrp.Position).Magnitude

        -- Дошли до точки пути?
        if dist < 4 then
            wpIndex += 1
            if wpIndex > #currentWaypoints then
                -- Конец пути
                if currentTarget and (currentTarget.Position - hrp.Position).Magnitude < 8 then
                    currentTarget = nil -- Собрали
                else
                    navState = "idle" -- Перестраиваем
                end
            end
        else
            local dir = (wp.Position - hrp.Position).Unit
            -- Если вдруг на пути встретилась стена (редко) — переключаемся
            if isObstructed(dir, 5) then
                navState = "direct"
            else
                hrp.CFrame = CFrame.lookAt(hrp.Position, wp.Position)
                hrp.Position = hrp.Position + dir * farmSpeed * dt
            end
        end

    --// РЕЖИМ 2: Direct Fly (если путь не построился или застряли)
    else
        navState = "direct"
        if not currentTarget then return end
        
        local targetPos = currentTarget.Position
        local dir = (targetPos - hrp.Position).Unit

        -- ВПЕРЕДИ СТЕНА/ГОРА? — Летим ВВЕРХ чтобы перелететь
        if isObstructed(dir, 8) then
            targetPos = targetPos + Vector3.new(0, 50, 0) -- Набираем высоту
            dir = (targetPos - hrp.Position).Unit
        end

        local dist = (currentTarget.Position - hrp.Position).Magnitude
        if dist < 5 then
            currentTarget = nil -- Дошли/собрали
        else
            hrp.CFrame = CFrame.lookAt(hrp.Position, targetPos)
            hrp.Position = hrp.Position + dir * farmSpeed * dt
        end
    end
end)

--// ESP (динамическое обновление)
local function makeESP(egg)
    if espCache[egg] then return end
    local hl = Instance.new("Highlight")
    hl.Name = "EggESP"
    hl.FillColor = Color3.fromRGB(255, 255, 0)
    hl.OutlineColor = Color3.fromRGB(255, 215, 0)
    hl.FillTransparency = 0.4
    hl.OutlineTransparency = 0
    hl.Adornee = egg
    hl.Parent = egg
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(0, 120, 0, 50)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    bb.Adornee = egg
    bb.Parent = egg

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = "🥚 EGG"
    lbl.TextColor3 = Color3.fromRGB(255, 255, 0)
    lbl.TextStrokeTransparency = 0
    lbl.TextScaled = true
    lbl.Font = Enum.Font.GothamBold
    lbl.Parent = bb

    espCache[egg] = { hl = hl, bb = bb, lbl = lbl }
end

local function clearESP(egg)
    local d = espCache[egg]
    if d then
        pcall(function() d.hl:Destroy() end)
        pcall(function() d.bb:Destroy() end)
        espCache[egg] = nil
    end
end

local function updateESP()
    if not espEnabled then
        for egg, _ in pairs(espCache) do clearESP(egg) end
        return
    end
    local eggs = getEggs()
    local active = {}
    for _, egg in ipairs(eggs) do
        active[egg] = true
        makeESP(egg)
        local d = espCache[egg]
        if d and hrp then
            d.lbl.Text = "🥚 EGG\n" .. math.floor((egg.Position - hrp.Position).Magnitude) .. " studs"
        end
    end
    for egg, _ in pairs(espCache) do
        if not active[egg] then clearESP(egg) end
    end
end

--// UI
MainTab:CreateToggle({
    Name = "Auto Farm Easter Eggs",
    CurrentValue = false,
    Callback = function(v)
        autoFarm = v
        if not v then
            navState = "idle"
            currentTarget = nil
            currentWaypoints = {}
        end
    end
})

VisualTab:CreateToggle({
    Name = "Egg ESP",
    CurrentValue = false,
    Callback = function(v)
        espEnabled = v
        if v then
            task.spawn(function()
                while espEnabled do
                    updateESP()
                    task.wait(0.25)
                end
            end)
        else
            updateESP()
        end
    end
})

SetTab:CreateSlider({
    Name = "Movement Speed",
    Range = {14, 24},
    Increment = 1,
    Suffix = "studs/sec",
    CurrentValue = 16,
    Callback = function(v)
        farmSpeed = v
    end
})

--// Anti-AFK
for _, c in pairs(getconnections(plr.Idled)) do c:Disable() end

Rayfield:Notify({ Title = "Loaded", Content = "Smart Navigation v3 — обходит горы и не застревает!", Duration = 5 })
