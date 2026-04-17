--// Rayfield
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "Easter Egg Auto-Farm",
    LoadingTitle = "Easter Eggs",
    LoadingSubtitle = "Smart Recalc v4",
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

--// Pathfinding
local path = PathfindingService:CreatePath({
    AgentRadius = 2,
    AgentHeight = 5,
    AgentCanJump = true,
    AgentCanClimb = false,
    WaypointSpacing = 3,
    Costs = {}
})

local currentWaypoints = {}
local wpIndex = 1
local navState = "idle" -- idle / path / direct
local lastPos = Vector3.zero
local stuckTimer = 0
local recalcTimer = 0
local RECALC_INTERVAL = 0.3 -- пересчёт ближайшего яйца каждые 0.3 сек

--// Respawn handler
plr.CharacterAdded:Connect(function(c)
    char = c
    hrp  = c:WaitForChild("HumanoidRootPart")
    hum  = c:WaitForChild("Humanoid")
    currentWaypoints = {}
    wpIndex = 1
    navState = "idle"
    currentTarget = nil
    stuckTimer = 0
    recalcTimer = 0
end)

--// Получить ВСЕ яйца прямо сейчас
local function getEggs()
    local eggs = {}
    local folder = workspace:FindFirstChild("EasterEggs")
    if folder then
        for _, obj in ipairs(folder:GetDescendants()) do
            if obj:IsA("BasePart") or obj:IsA("MeshPart") then
                table.insert(eggs, obj)
            end
        end
    end
    return eggs
end

--// Ближайшее яйцо (absolute)
local function getClosestEgg(fromPos)
    local eggs = getEggs()
    if #eggs == 0 then return nil, math.huge end
    local closest, minDist = nil, math.huge
    fromPos = fromPos or (hrp and hrp.Position)
    if not fromPos then return nil, math.huge end

    for _, egg in ipairs(eggs) do
        if not egg or not egg.Parent then continue end
        local d = (egg.Position - fromPos).Magnitude
        if d < minDist then
            minDist = d
            closest = egg
        end
    end
    return closest, minDist
end

--// Построить путь
local function computePath(target)
    currentWaypoints = {}; wpIndex = 1
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

--// Raycast вперёд
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Blacklist

local function forwardRay(dist)
    if not hrp then return nil end
    rayParams.FilterDescendantsInstances = {char}
    return workspace:Raycast(hrp.Position, hrp.CFrame.LookVector * dist, rayParams)
end

--// ==================== HEARTBEAT (core logic) ====================
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

    -- Noclip + отрубаем Humanoid (он мешает скорости)
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide = false end
    end
    if hum then
        hum.PlatformStand = true
        hum.AutoRotate = false
    end

    --// ===== 1. ПЕРИОДИЧЕСКИЙ ПЕРЕСЧЁТ ЦЕЛИ (ФИКС) =====
    recalcTimer += dt
    if recalcTimer >= RECALC_INTERVAL then
        recalcTimer = 0
        local bestEgg, bestDist = getClosestEgg()

        if bestEgg then
            if not currentTarget or not currentTarget.Parent then
                -- Нет цели — берём лучшую
                currentTarget = bestEgg
                navState = "idle"
            else
                local oldDist = (currentTarget.Position - hrp.Position).Magnitude
                -- Гистерезис в 5 studs, чтобы не дёргался между двумя одинаково близкими
                if bestDist < oldDist - 5 then
                    currentTarget = bestEgg
                    navState = "idle" -- force rebuild path к новой цели
                end
            end
        else
            currentTarget = nil
            navState = "idle"
        end
    end

    --// ===== 2. НЕТ ЦЕЛИ =====
    if not currentTarget or not currentTarget.Parent then
        currentTarget = getClosestEgg()
        navState = "idle"
        if not currentTarget then return end
    end

    --// ===== 3. ANTI-STUCK (Застрял в текстуре?) =====
    local moved = (hrp.Position - lastPos).Magnitude
    if moved < 0.3 then
        stuckTimer += dt
        if stuckTimer > 0.5 then
            -- Рывок: вверх + чуть вперёд — вытаскиваем из текстуры/горы
            hrp.Position = hrp.Position + Vector3.new(0, 40, 0) + (hrp.CFrame.LookVector * 10)
            stuckTimer = 0
            navState = "idle" -- перестроить путь от новой позиции
        end
    else
        stuckTimer = 0
    end
    lastPos = hrp.Position

    --// ===== 4. ВЫБОР НАВИГАЦИИ =====
    if navState == "idle" then
        if computePath(currentTarget) then
            navState = "path"
        else
            navState = "direct"
        end
    end

    --// ===== 5. PATHFINDING MODE (обходит горы/стены по земле) =====
    if navState == "path" and wpIndex <= #currentWaypoints then
        local wp = currentWaypoints[wpIndex]
        local distWP = (wp.Position - hrp.Position).Magnitude

        if distWP < 3.5 then
            wpIndex += 1
            if wpIndex > #currentWaypoints then
                -- Конец пути — дошли ли до яйца?
                if (currentTarget.Position - hrp.Position).Magnitude < 7 then
                    currentTarget = nil -- собрали
                else
                    navState = "idle" -- перестроить
                end
            end
        else
            local dir = (wp.Position - hrp.Position).Unit
            -- Если вдруг на пути появилась динамическая стена
            if forwardRay(5) then
                navState = "direct"
            else
                hrp.CFrame = CFrame.lookAt(hrp.Position, wp.Position)
                hrp.Position = hrp.Position + dir * farmSpeed * dt
            end
        end

    --// ===== 6. DIRECT FLY MODE (облёт препятствий) =====
    elseif navState == "direct" then
        local tPos = currentTarget.Position
        local dist = (tPos - hrp.Position).Magnitude

        if dist < 4 then
            currentTarget = nil
            navState = "idle"
        else
            local dir = (tPos - hrp.Position).Unit
            local hit = forwardRay(7)

            if hit then
                -- Впереди стена/гора — перелетаем через неё (рывок вверх-вперёд)
                hrp.Position = hrp.Position + Vector3.new(0, 35, 0) + (dir * 8)
                hrp.CFrame = CFrame.lookAt(hrp.Position, tPos)
            else
                hrp.CFrame = CFrame.lookAt(hrp.Position, tPos)
                hrp.Position = hrp.Position + dir * farmSpeed * dt
            end
        end
    end
end)

--// ==================== ESP ====================
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
            navState = "idle"; currentTarget = nil; currentWaypoints = {}
            stuckTimer = 0; recalcTimer = 0
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

Rayfield:Notify({ Title = "Loaded v4", Content = "Auto-recalc + Anti-stuck ready!", Duration = 5 })
