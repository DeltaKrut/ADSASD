--[[
=====================================================================
	RevolverServer
	ServerScriptService.RevolverServer
---------------------------------------------------------------------
	Авторитетная часть системы. Отвечает за:
	  * боезапас (клиент не может его подделать);
	  * проверку выстрела (скорострельность, дистанция, позиция);
	  * собственный Raycast — урон считается по серверному лучу;
	  * нанесение урона с учётом зоны попадания и затухания;
	  * перезарядку по патронам с возможностью прерывания;
	  * рассылку эффектов остальным игрокам.
=====================================================================
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Debris            = game:GetService("Debris")

local System  = ReplicatedStorage:WaitForChild("RevolverSystem")
local AntiCheat = require(game:GetService("ServerScriptService"):WaitForChild("AntiCheat"))
local Config  = require(System:WaitForChild("RevolverConfig"))
local Effects = require(System:WaitForChild("RevolverEffects"))
local Remotes = System:WaitForChild("Remotes")

local FireRequest   = Remotes:WaitForChild("FireRequest")
local ReloadRequest = Remotes:WaitForChild("ReloadRequest")
local CancelReload  = Remotes:WaitForChild("CancelReload")
local EffectEvent   = Remotes:WaitForChild("EffectEvent")
local HitConfirm    = Remotes:WaitForChild("HitConfirm")

--=====================================================================
-- СОСТОЯНИЕ
--=====================================================================
-- Боезапас хранится в атрибутах инструмента: реплицируется сам,
-- переживает выбрасывание и подбор оружия (в игре есть DropTool).
-- Тут же держим служебные данные, которые клиенту знать не нужно.

local ToolState = {} -- [Tool] = { LastShot = number, ReloadToken = number }

local function getState(tool: Tool)
	local st = ToolState[tool]
	if not st then
		st = { LastShot = 0, ReloadToken = 0 }
		ToolState[tool] = st
	end
	return st
end

--=====================================================================
-- ОПОЗНАНИЕ ОРУЖИЯ
--=====================================================================

local function isRevolver(inst): boolean
	if not inst or not inst:IsA("Tool") then return false end
	if CollectionService:HasTag(inst, Config.Identity.Tag) then return true end
	return inst.Name == Config.Identity.ToolName
end

local function initTool(tool: Tool)
	if tool:GetAttribute("Ammo") == nil then
		tool:SetAttribute("Ammo", Config.Stats.Ammo)
	end
	tool:SetAttribute("MaxAmmo", Config.Stats.MaxAmmo)
	tool:SetAttribute("Reloading", false)
	getState(tool)

	-- Достраиваем Muzzle/Sounds на сервере, чтобы они отреплицировались
	-- всем клиентам сразу.
	Effects.Prepare(tool)

	tool.Destroying:Connect(function()
		ToolState[tool] = nil
	end)
end

local function scan(container: Instance)
	for _, d in ipairs(container:GetDescendants()) do
		if isRevolver(d) then
			initTool(d)
		end
	end
	container.DescendantAdded:Connect(function(d)
		if isRevolver(d) then
			initTool(d)
		end
	end)
end

scan(game:GetService("Workspace"))
scan(game:GetService("ServerStorage"))
scan(game:GetService("StarterPack"))
scan(ReplicatedStorage)

--=====================================================================
-- ВАЛИДАЦИЯ
--=====================================================================

local function isFiniteVector(v): boolean
	if typeof(v) ~= "Vector3" then return false end
	if v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z then return false end -- NaN
	if math.abs(v.X) > 1e6 or math.abs(v.Y) > 1e6 or math.abs(v.Z) > 1e6 then return false end
	return true
end

-- Возвращает персонажа, гуманоида и инструмент, если всё в порядке
local function validateHolder(player: Player, tool)
	if not isRevolver(tool) then return nil end

	local character = player.Character
	if not character then return nil end
	if tool.Parent ~= character then return nil end -- оружие должно быть в руках

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return nil end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end

	return character, humanoid, root
end

local function getMuzzlePosition(tool: Tool): Vector3?
	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then return nil end
	local muzzle = handle:FindFirstChild("Muzzle")
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle.WorldPosition
	end
	return handle.Position
end

--=====================================================================
-- УРОН
--=====================================================================

-- Стандартный тег "кто нанёс урон" — его читают системы килл-фидов.
local function tagHumanoid(humanoid: Humanoid, player: Player)
	local old = humanoid:FindFirstChild("creator")
	if old then old:Destroy() end

	local tag = Instance.new("ObjectValue")
	tag.Name  = "creator"
	tag.Value = player
	tag.Parent = humanoid
	Debris:AddItem(tag, Config.Combat.CreatorTagLifetime)

	humanoid:SetAttribute("LastDamageSource", "Revolver")
end

local function canDamage(shooter: Player, victimHumanoid: Humanoid): boolean
	if victimHumanoid.Health <= 0 then return false end

	local victimChar   = victimHumanoid.Parent
	-- уклоняющийся: уклоняется ТОЛЬКО с близкой дистанции (дальний выстрел — его слабость)
	if victimChar and not Players:GetPlayerFromCharacter(victimChar) then
		local DODGE_RANGE = 70
		local sc = shooter.Character
		local srp = sc and sc:FindFirstChild("HumanoidRootPart")
		local vrp = victimChar:FindFirstChild("HumanoidRootPart")
		local near = srp and vrp and (srp.Position - vrp.Position).Magnitude <= DODGE_RANGE
		if near and victimChar:GetAttribute("CanDodge") then
			victimChar:SetAttribute("DodgeReq", (victimChar:GetAttribute("DodgeReq") or 0) + 1)
			return false
		end
		if victimChar:GetAttribute("Dodging") then return false end
	end
	local victimPlayer = victimChar and Players:GetPlayerFromCharacter(victimChar)

	if victimPlayer then
		-- По другим игрокам оружие не работает вообще (только бинт/ревайв).
		return false
	end

	-- NPC / зомби
	return Config.Combat.DamageNPC
end

local function findHumanoid(part: BasePart?): Humanoid?
	if not part then return nil end
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if model:GetAttribute("Invulnerable") then return nil end -- NPC магазина/скупщика
		local h = model:FindFirstChildOfClass("Humanoid")
		if h then return h end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

--=====================================================================
-- ВЫСТРЕЛ
--=====================================================================

-- Рассылает эффекты всем, кроме стрелка (у него они уже отрисовались локально)
local function replicateShot(shooter: Player, tool: Tool, origin: Vector3, impact)
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= shooter then
			EffectEvent:FireClient(p, tool, origin, impact)
		end
	end
end

FireRequest.OnServerEvent:Connect(function(player, tool, clientOrigin, clientDirection, mode)
	if not AntiCheat.rate(player, "revolver_fire", 9, 1) then return end
	local fan = mode == "fan"
	if not AntiCheat.canAct(player) then return end
	--— базовая проверка типов —
	if not isFiniteVector(clientOrigin) or not isFiniteVector(clientDirection) then return end
	if clientDirection.Magnitude < 0.001 then return end

	local character, humanoid, root = validateHolder(player, tool)
	if not character then return end

	local state = getState(tool)

	--— скорострельность —
	local now = os.clock()
	local needRate = fan and (Config.V2 and Config.V2.FanRate or Config.Stats.FireRate) or Config.Stats.FireRate
	if now - state.LastShot < needRate * Config.Combat.FireRateTolerance then
		return
	end

	--— перезарядка —
	if tool:GetAttribute("Reloading") == true then return end

	--— боезапас —
	local ammo = tool:GetAttribute("Ammo") or 0
	if ammo <= 0 then
		-- Осечка: звук пустого барабана проигрывает клиент сам.
		return
	end

	--— позиция выстрела —
	local muzzlePos = getMuzzlePosition(tool) or root.Position
	if (clientOrigin - muzzlePos).Magnitude > Config.Combat.OriginTolerance then
		-- Клиент заявил выстрел откуда-то издалека — игнорируем.
		return
	end

	--— направление выстрела — должно совпадать со взглядом персонажа —
	local lookDir = root.CFrame.LookVector
	-- Сравниваем ТОЛЬКО горизонталь (взгляд тела горизонтальный),
	-- иначе стрельбу вниз/вверх (по зомби под ногами) блокировало.
	local flatDir = Vector3.new(clientDirection.X, 0, clientDirection.Z)
	local flatLook = Vector3.new(lookDir.X, 0, lookDir.Z)
	if flatDir.Magnitude > 0.01 and flatLook.Magnitude > 0.01 then
		if flatDir.Unit:Dot(flatLook.Unit) < 0.6 then
			return
		end
	end

	--— списываем патрон —
	state.LastShot = now
	tool:SetAttribute("Ammo", ammo - 1)

	--— серверный Raycast: именно он решает, кому прилетело —
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, tool }
	params.IgnoreWater = true

	local direction = clientDirection.Unit * (Config.Stats.Range * Config.Combat.RangeTolerance)
	local result = workspace:Raycast(muzzlePos, direction, params)

	local impact = {
		Position = muzzlePos + direction,
		Normal   = -clientDirection.Unit,
		Instance = nil,
		Material = Enum.Material.Air,
		IsFlesh  = false,
	}

	if result then
		impact.Position = result.Position
		impact.Normal   = result.Normal
		impact.Instance = result.Instance
		impact.Material = result.Material

		local victim = findHumanoid(result.Instance)
		if victim and canDamage(player, victim) then
			impact.IsFlesh = true

			local distance = (result.Position - muzzlePos).Magnitude
			local zoneMult, zone = Config.GetPartMultiplier(result.Instance.Name)
			local falloff  = Config.GetFalloffMultiplier(distance)
			local damage   = Config.Stats.Damage * zoneMult * falloff * (fan and (Config.V2 and Config.V2.FanDamageMult or 1) or 1)

			tagHumanoid(victim, player)
			victim:TakeDamage(damage)

			-- Хитмаркер стрелку
			HitConfirm:FireClient(player, zone, damage, victim.Health <= 0)
		end
	end

	--— эффекты остальным —
	replicateShot(player, tool, muzzlePos, impact)
end)

--=====================================================================
-- ПЕРЕЗАРЯДКА
--=====================================================================

local function stopReload(tool: Tool)
	local state = getState(tool)
	state.ReloadToken += 1
	tool:SetAttribute("Reloading", false)
end

ReloadRequest.OnServerEvent:Connect(function(player, tool)
	if not AntiCheat.rate(player, "revolver_reload", 3, 1) then return end
	local character = validateHolder(player, tool)
	if not character then return end

	if tool:GetAttribute("Reloading") == true then return end

	local ammo = tool:GetAttribute("Ammo") or 0
	local maxAmmo = Config.Stats.MaxAmmo
	if ammo >= maxAmmo then return end

	-- Запас патронов у игрока (счётчик Ammo_Revolver, пополняется с коробок)
	local invAmmo = player:GetAttribute("Ammo_Revolver") or 0
	if invAmmo <= 0 then
		local bs = ReplicatedStorage:FindFirstChild("BuildingSystem")
		local notify = bs and bs:FindFirstChild("NotifyEvent")
		if notify then notify:FireClient(player, "Нет патронов (найди коробку)") end
		return
	end

	local state = getState(tool)
	state.ReloadToken += 1
	local token = state.ReloadToken

	tool:SetAttribute("Reloading", true)

	task.spawn(function()
		local r = Config.Reload

		-- Фаза 1: откинуть барабан
		task.wait(r.OpenTime)
		if state.ReloadToken ~= token then return end
		if not validateHolder(player, tool) then stopReload(tool) return end

		-- Фаза 2: вставляем патроны по одному, тратя запас игрока.
		-- Если игрока прервали — уже вставленные остаются в барабане.
		while (tool:GetAttribute("Ammo") or 0) < maxAmmo do
			task.wait(r.PerRoundTime)
			if state.ReloadToken ~= token then return end
			if not validateHolder(player, tool) then stopReload(tool) return end

			local cur = player:GetAttribute("Ammo_Revolver") or 0
			if cur <= 0 then break end
			player:SetAttribute("Ammo_Revolver", cur - 1)

			tool:SetAttribute("Ammo", (tool:GetAttribute("Ammo") or 0) + 1)
		end

		-- Фаза 3: защёлкнуть барабан
		task.wait(r.CloseTime)
		if state.ReloadToken ~= token then return end

		tool:SetAttribute("Reloading", false)
	end)
end)

CancelReload.OnServerEvent:Connect(function(player, tool)
	if not AntiCheat.rate(player, "revolver_cancel", 3, 1) then return end
	if not isRevolver(tool) then return end
	if not Config.Reload.AllowCancel then return end
	-- Прервать может только владелец
	local character = player.Character
	if not character or tool.Parent ~= character then return end
	stopReload(tool)
end)

--=====================================================================
-- СБРОС СОСТОЯНИЯ
--=====================================================================

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		-- При смерти/респавне прерываем незавершённые перезарядки
		for tool, _ in pairs(ToolState) do
			if tool.Parent == nil or not tool:IsDescendantOf(game) then
				ToolState[tool] = nil
			end
		end
		local humanoid = character:WaitForChild("Humanoid", 5)
		if humanoid then
			humanoid.Died:Connect(function()
				for _, d in ipairs(character:GetChildren()) do
					if isRevolver(d) then
						stopReload(d)
					end
				end
			end)
		end
	end)
end)

print("[Revolver] Серверная система запущена")

