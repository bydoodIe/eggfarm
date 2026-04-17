--// Загрузка Rayfield
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

--// Создание окна
local Window = Rayfield:CreateWindow({
    Name = "Easter Egg Auto-Farm",
    LoadingTitle = "Easter Eggs",
    LoadingSubtitle = "Auto farm + ESP",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false
})

--// Вкладки
local MainTab    = Window:CreateTab("Main", 4483362458)
local VisualTab  = Window:CreateTab("ESP", 4483362458)
local SetTab     = Window:CreateTab("Settings", 4483362458)

--// Переменные
local player     = game.Players.LocalPlayer
local char       = player.Character or player.CharacterAdded:Wait()
local hrp        = char:WaitForChild("HumanoidRootPart")
local humanoid   = char:WaitForChild("Humanoid")

local autoFarm   = false
local espEnabled = false
local farmSpeed  = 16
local espCache   = {}

--// Обновление персонажа после респавна
player.CharacterAdded:Connect(function(newChar)
    char = newChar
    hrp = char:WaitForChild("HumanoidRootPart")
    humanoid = char:WaitForChild("Humanoid")
end)

--// Получение списка яиц (ищет все BasePart в workspace.EasterEggs)
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

--// Движение к яйцу напрямую, игнорируя стены и рельеф (noclip + прямой полёт)
local function goToEgg(egg)
    if not egg or not egg.Parent then return end

    while autoFarm and egg and egg.Parent do
        if not hrp or not hrp.Parent then break end

        local dist = (egg.Position - hrp.Position).Magnitude
        if dist < 5 then break end -- Добрались до яйца

        -- Вектор к цели
        local dir = (egg.Position - hrp.Position).Unit

        -- Движение напрямую (сквозь стены и воздух)
        hrp.AssemblyLinearVelocity = dir * farmSpeed
        hrp.CFrame = CFrame.lookAt(hrp.Position, egg.Position)

        -- Noclip: отключаем коллизии у всего персонажа
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end

        task.wait()
    end
end

--// Основной цикл фарма
local function farmLoop()
    while autoFarm do
        local eggs = getEggs()
        if #eggs == 0 then
            Rayfield:Notify({ Title = "Внимание", Content = "Яйца не найдены!", Duration = 3 })
            task.wait(2)
            continue
        end

        for _, egg in ipairs(eggs) do
            if not autoFarm then break end
            if not (egg and egg.Parent) then continue end

            goToEgg(egg)
            task.wait(0.2) -- Короткая пауза после "сбора"
        end

        task.wait(0.3)
    end

    -- Сброс после остановки
    if hrp then
        hrp.AssemblyLinearVelocity = Vector3.zero
    end
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = true
            end
        end
    end
end

--// ESP: создание подсветки и метки
local function makeESP(egg)
    if espCache[egg] then return end

    local hl = Instance.new("Highlight")
    hl.Name = "EggESP_HL"
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
    lbl.Text = "🥚 EGG\n" .. math.floor((egg.Position - hrp.Position).Magnitude) .. " studs"
    lbl.TextColor3 = Color3.fromRGB(255, 255, 0)
    lbl.TextStrokeTransparency = 0
    lbl.TextScaled = true
    lbl.Font = Enum.Font.GothamBold
    lbl.Parent = bb

    espCache[egg] = { Highlight = hl, Billboard = bb, Label = lbl }
end

local function clearESP(egg)
    local data = espCache[egg]
    if data then
        for _, v in pairs(data) do pcall(function() v:Destroy() end) end
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
        -- Обновляем дистанцию на метке
        local data = espCache[egg]
        if data and data.Label then
            data.Label.Text = "🥚 EGG\n" .. math.floor((egg.Position - hrp.Position).Magnitude) .. " studs"
        end
    end

    -- Удаляем ESP для пропавших яиц
    for egg, _ in pairs(espCache) do
        if not active[egg] then clearESP(egg) end
    end
end

--// UI: Тоггл Auto Farm
MainTab:CreateToggle({
    Name = "Auto Farm Easter Eggs",
    CurrentValue = false,
    Flag = "AutoFarmToggle",
    Callback = function(Value)
        autoFarm = Value
        if Value then
            task.spawn(farmLoop)
        end
    end
})

--// UI: Тоггл ESP
VisualTab:CreateToggle({
    Name = "Egg ESP (Highlight + Name)",
    CurrentValue = false,
    Flag = "ESPToggle",
    Callback = function(Value)
        espEnabled = Value
        if Value then
            task.spawn(function()
                while espEnabled do
                    updateESP()
                    task.wait(0.2)
                end
            end)
        else
            updateESP()
        end
    end
})

--// UI: Слайдер скорости (14-24) в отдельной вкладке Settings
SetTab:CreateSlider({
    Name = "Movement Speed",
    Range = {14, 24},
    Increment = 1,
    Suffix = "studs/sec",
    CurrentValue = 16,
    Flag = "SpeedSlider",
    Callback = function(Value)
        farmSpeed = Value
    end
})

--// Anti-AFK (чтобы не кикало за бездействие)
for _, conn in pairs(getconnections(player.Idled)) do
    conn:Disable()
end

Rayfield:Notify({
    Title = "Script Loaded",
    Content = "Auto Farm & ESP готовы к работе",
    Duration = 5
})
