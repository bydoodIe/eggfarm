--// Rayfield
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "Easter Egg Auto-Farm",
    LoadingTitle = "Easter Eggs",
    LoadingSubtitle = "Fixed v2",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false
})

local MainTab   = Window:CreateTab("Main", 4483362458)
local VisualTab = Window:CreateTab("ESP", 4483362458)
local SetTab    = Window:CreateTab("Settings", 4483362458)

--// Переменные
local plr        = game.Players.LocalPlayer
local char       = plr.Character or plr.CharacterAdded:Wait()
local hrp        = char:WaitForChild("HumanoidRootPart")
local hum        = char:WaitForChild("Humanoid")

local autoFarm   = false
local espEnabled = false
local farmSpeed  = 16
local currentTarget = nil
local espCache = {}

plr.CharacterAdded:Connect(function(c)
    char = c
    hrp  = c:WaitForChild("HumanoidRootPart")
    hum  = c:WaitForChild("Humanoid")
end)

--// Получить все живые яйца прямо сейчас
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

--// Ближайшее яйко
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

--// ДВИЖЕНИЕ: Heartbeat + CFrame (не зависит от Humanoid)
local RS = game:GetService("RunService")
RS.Heartbeat:Connect(function(dt)
    if not autoFarm then
        if currentTarget then
            currentTarget = nil
            if hum then
                hum.PlatformStand = false
                hum.AutoRotate = true
            end
            if hrp then hrp.AssemblyLinearVelocity = Vector3.zero end
            -- Вернуть коллизии
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = true end
            end
        end
        return
    end

    if not hrp or not hum or not char then return end

    -- Noclip + убиваем контроль Humanoid (он мешает скорости)
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then
            p.CanCollide = false
        end
    end
    hum.PlatformStand = true
    hum.AutoRotate = false

    -- Цель пропала? — берём ближайшую новую мгновенно
    if not currentTarget or not currentTarget.Parent then
        currentTarget = getClosestEgg()
        if not currentTarget then return end
    end

    local pos  = hrp.Position
    local tPos = currentTarget.Position
    local dist = (tPos - pos).Magnitude

    -- Дошли — считаем "собрано", сразу ищем следующее
    if dist < 4 then
        currentTarget = nil
        return
    end

    local dir  = (tPos - pos).Unit
    local step = farmSpeed * dt          -- честные studs/sec
    if step > dist then step = dist end  -- не пролетаем мимо

    hrp.CFrame = CFrame.new(pos + dir * step, tPos)
    hrp.AssemblyLinearVelocity = Vector3.zero
end)

--// ESP (динамически обновляется)
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

    -- Удаляем ESP у пропавших
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
        if not v then currentTarget = nil end
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

Rayfield:Notify({ Title = "Loaded", Content = "Fixed v2 ready — speed & dynamic eggs", Duration = 5 })
