--[[
	AmmoSystemServer
	ServerScriptService.AmmoSystemServer
	Система патронов: подбор коробок на Q (клиентский рейкаст) -> +N патронов игроку.
	Счётчик хранится в атрибуте игрока Ammo_<Type> (например Ammo_Revolver).
	Расход патронов при перезарядке — в RevolverServer.
	E берёт коробку в руки как обычный предмет (BuildingSystemClient).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local AntiCheat = require(game:GetService("ServerScriptService"):WaitForChild("AntiCheat"))

local BuildingSystem = ReplicatedStorage:WaitForChild("BuildingSystem")
local NotifyEvent = BuildingSystem:WaitForChild("NotifyEvent")

-- Звук подбора патронов (щелчок/гильза)
local PICKUP_SOUND = "rbxassetid://18148598503"

local function giveAmmo(player, ammoType, amount)
	local attr = "Ammo_" .. ammoType
	local cur = player:GetAttribute(attr) or 0
	player:SetAttribute(attr, cur + amount)
	return cur + amount
end

local function setupAmmoBox(model)
	if model:GetAttribute("AmmoSetup") then return end
	model:SetAttribute("AmmoSetup", true)

	local ammoType = model:GetAttribute("AmmoType") or "Revolver"
	local amount = model:GetAttribute("AmmoCount") or 24

	-- PrimaryPart
	if not model.PrimaryPart then
		local first = model:FindFirstChildWhichIsA("BasePart", true)
		if first then model.PrimaryPart = first end
	end
	local primary = model.PrimaryPart
	if not primary then return end

	model:SetAttribute("AmmoReady", true)
end

-- RemoteEvent для подбора патронов (клиент шлёт Q по наведению)
local AmmoPickupEvent = BuildingSystem:FindFirstChild("AmmoPickupEvent")
if not AmmoPickupEvent then
	AmmoPickupEvent = Instance.new("RemoteEvent")
	AmmoPickupEvent.Name = "AmmoPickupEvent"
	AmmoPickupEvent.Parent = BuildingSystem
end

AmmoPickupEvent.OnServerEvent:Connect(function(player, model)
	if not AntiCheat.rate(player, "ammo_pickup", 5, 1) then return end
	if not AntiCheat.canAct(player) then return end
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end
	if not model:GetAttribute("IsAmmoBox") then return end
	if not model.Parent then return end

	-- Нельзя забрать патроны, пока коробку держат в руках или припаяли
	if model:GetAttribute("BeingHeld") or model:GetAttribute("Welded") then return end
	if model:GetAttribute("Taken") then return end

	-- Игрок должен быть рядом с коробкой (античит)
	local pr = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not pr then return end
	if not AntiCheat.nearPart(player, pr, 15) then return end

	model:SetAttribute("Taken", true)

	local ammoType = model:GetAttribute("AmmoType") or "Revolver"
	local amount = model:GetAttribute("AmmoCount") or 24
	giveAmmo(player, ammoType, amount)
	NotifyEvent:FireClient(player, "+ " .. amount .. " патронов")

	-- звук
	local snd = Instance.new("Sound")
	snd.SoundId = PICKUP_SOUND
	snd.Volume = 1.2
	snd.Parent = pr
	snd:Play()
	Debris:AddItem(snd, 3)

	-- исчезновение
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			TweenService:Create(p, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = p.Size * 0.01, Transparency = 1}):Play()
		end
	end
	task.delay(0.4, function()
		if model and model.Parent then model:Destroy() end
	end)
end)

-- скан существующих
local function scan()
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and d:GetAttribute("IsAmmoBox") then
			setupAmmoBox(d)
		end
	end
end
scan()

Workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") and d:GetAttribute("IsAmmoBox") then
		task.defer(setupAmmoBox, d)
	end
end)

-- инициализация счётчика игрока
local START_AMMO = 0
Players.PlayerAdded:Connect(function(player)
	if player:GetAttribute("Ammo_Revolver") == nil then
		player:SetAttribute("Ammo_Revolver", START_AMMO)
	end
end)
for _, player in ipairs(Players:GetPlayers()) do
	if player:GetAttribute("Ammo_Revolver") == nil then
		player:SetAttribute("Ammo_Revolver", START_AMMO)
	end
end

print("[Ammo] Серверная система патронов запущена")
