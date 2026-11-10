-- ToolPickupSystem v2: подбор тулов БЕЗ ProximityPrompt (не ворует клавишу E)
-- Слушает PickupEvent вместе с основным сервером; двойную обработку исключает.
-- Тулы НЕ имеют прочности: любые HP-атрибуты с них стираются.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildingSystem = ReplicatedStorage:WaitForChild("BuildingSystem")
local PickupEvent = BuildingSystem:WaitForChild("PickupEvent")

local function cleanupAttrs(tool)
	tool:SetAttribute("HP", nil)
	tool:SetAttribute("MaxHP", nil)
	tool:SetAttribute("DamagePerHit", nil)
	tool:SetAttribute("DurabilityArmed", nil)
end

local function armTool(tool)
	cleanupAttrs(tool)
	tool:GetPropertyChangedSignal("Parent"):Connect(function()
		cleanupAttrs(tool)
	end)
end

for _, obj in ipairs(Workspace:GetDescendants()) do
	if obj:IsA("Tool") then armTool(obj) end
end
Workspace.DescendantAdded:Connect(function(obj)
	if obj:IsA("Tool") then task.defer(armTool, obj) end
end)

PickupEvent.OnServerEvent:Connect(function(player, tool)
	if typeof(tool) ~= "Instance" or not tool:IsA("Tool") then return end
	local character = player.Character
	if not character then return end
	if tool.Parent == player.Backpack or tool.Parent == character then return end
	if not tool.Parent or not (tool.Parent == Workspace or tool.Parent:IsDescendantOf(Workspace)) then return end
	if tool:GetAttribute("Welded") then return end

	-- Кулдаун 0.3 сек после броска: нельзя мгновенно подобрать обратно
	local cd = tool:GetAttribute("DropCooldownUntil")
	if cd and os.clock() < cd then return end

	tool.Parent = player.Backpack
	for _, part in ipairs(tool:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.Massless = true
			part.CanCollide = false
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum then hum:EquipTool(tool) end
	print("[ToolPickup] " .. player.Name .. " подобрал " .. tool.Name)
end)

print("[ToolPickupSystem v2] Загружен: подбор через PickupEvent, без промптов")

