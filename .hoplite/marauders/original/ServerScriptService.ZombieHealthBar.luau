-- ZombieHealthBar: HP-полоска рядом с головой NPC (сбоку), градиент зелёный→жёлтый→красный
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local BAR_W = 2.2
local BAR_H = 0.28

local function isPlayerChar(m)
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character == m then return true end
	end
	return false
end

-- Цвет по проценту HP: 1 = зелёный, 0.5 = жёлтый, 0 = красный
local function hpColor(ratio)
	if ratio > 0.5 then
		-- зелёный -> жёлтый
		local a = (ratio - 0.5) / 0.5
		return Color3.fromRGB(255 - (255 - 80) * a, 255, 60 * a)
	else
		-- жёлтый -> красный
		local a = ratio / 0.5
		return Color3.fromRGB(255, 255 * a + 40 * (1 - a), 40 * a)
	end
end

local function setupBar(model, humanoid, head)
	if model:GetAttribute("HPBarSetup") then return end
	model:SetAttribute("HPBarSetup", true)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HPBar"
	-- Размер в мировых стадах (offset): BillboardGui сам уменьшает его с расстоянием
	billboard.Size = UDim2.fromScale(BAR_W, BAR_H)
	billboard.StudsOffsetWorldSpace = Vector3.new(head.Size.X / 2 + 0.9, head.Size.Y / 2 + 0.2, 0)
	billboard.AlwaysOnTop = false -- не видно сквозь стены
	billboard.MaxDistance = 20 -- видно только в радиусе 20 стадов
	billboard.LightInfluence = 0
	billboard:SetAttribute("IsHPBar", true)
	billboard.Adornee = head
	billboard.Parent = head

	local bg = Instance.new("Frame")
	bg.Name = "BG"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	bg.BackgroundTransparency = 0.25
	bg.BorderSizePixel = 0
	bg.Parent = billboard
	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(1, 0)
	bgCorner.Parent = bg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(80, 255, 60)
	fill.BorderSizePixel = 0
	fill.Parent = bg
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local grad = Instance.new("UIGradient")
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 0.55)
	})
	grad.Rotation = 90
	grad.Parent = fill

	local function update()
		local ratio = 0
		if humanoid.MaxHealth > 0 then
			ratio = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
		end
		fill.Size = UDim2.fromScale(ratio, 1)
		fill.BackgroundColor3 = hpColor(ratio)
		billboard.Enabled = humanoid.Health > 0
	end

	humanoid.HealthChanged:Connect(update)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(update)
	update()
end

local function trySetup(model)
	if not model:IsA("Model") then return end
	if isPlayerChar(model) then return end
	-- Бар показываем ТОЛЬКО зомби (у Hawk, торговца и прочих NPC его нет).
	-- "Zombie" — обычные, "Zombie Climber" — верхолаз.
	if model.Name ~= "Zombie" and model.Name ~= "Zombie Climber" and model.Name ~= " BIG Zombie" and model.Name ~= "FasterFaster" and model.Name ~= "SpitterZombie" and model.Name ~= "zombieCrawler" and model.Name ~= "Dodger-Scoffer" then return end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then return end
	setupBar(model, humanoid, head)
end

for _, obj in ipairs(Workspace:GetDescendants()) do
	trySetup(obj)
end

Workspace.DescendantAdded:Connect(function(obj)
	if obj:IsA("Humanoid") then
		local model = obj.Parent
		if model and model:IsA("Model") then
			task.defer(trySetup, model)
		end
	end
end)

print("[ZombieHealthBar] загружен")
