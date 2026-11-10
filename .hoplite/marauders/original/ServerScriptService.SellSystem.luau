-- SellSystem: игрок кладёт труп зомби на sellpart — получает 10$, труп исчезает.
-- Антидюп: труп помечается Sold, продать дважды нельзя.
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local REWARD = 10 -- базовая награда (если у трупа нет атрибута SellValue)
local SELL_COOLDOWN = 0.5 -- кулдаун на игрока (анти-спам)

local sellPart
local sellFolder = Workspace:WaitForChild("Sell", 10)
if sellFolder then
	sellFolder = sellFolder:WaitForChild("sell", 5)
end
if sellFolder then
	sellPart = sellFolder:WaitForChild("sellpart", 5)
end

local lastSell = {}

local CELEBRATE_SOUND = "rbxassetid://5728423829"

-- Праздничный эффект на sellpart: звук + конфетти (как «квест выполнен»)
local celebrateCooldown = 0
local function celebrate(pos)
	local now = os.clock()
	if now - celebrateCooldown < 0.25 then return end
	celebrateCooldown = now

	-- Звук
	local snd = Instance.new("Sound")
	snd.SoundId = CELEBRATE_SOUND
	snd.Volume = 2
	snd.RollOffMaxDistance = 120
	local host = sellPart or Workspace
	snd.Parent = host
	snd:Play()
	game:GetService("Debris"):AddItem(snd, 5)

	-- Вспышка света
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(3, 3, 3)
	flash.Position = pos + Vector3.new(0, 2, 0)
	flash.Anchored = true
	flash.CanCollide = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 230, 120)
	flash.Transparency = 0.2
	flash.Parent = Workspace
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 230, 120)
	light.Brightness = 8
	light.Range = 25
	light.Parent = flash
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 0.5 do
			local a = (os.clock() - t0) / 0.5
			flash.Transparency = 0.2 + a * 0.8
			light.Brightness = 8 * (1 - a)
			task.wait()
		end
		flash:Destroy()
	end)

	-- Конфетти (разноцветные частицы)
	local emitterHost = Instance.new("Part")
	emitterHost.Size = Vector3.new(0.1, 0.1, 0.1)
	emitterHost.Position = pos + Vector3.new(0, 1, 0)
	emitterHost.Anchored = true
	emitterHost.CanCollide = false
	emitterHost.Transparency = 1
	emitterHost.Parent = Workspace
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 0
	pe.Lifetime = NumberRange.new(1, 2)
	pe.Speed = NumberRange.new(18, 35)
	pe.SpreadAngle = Vector2.new(60, 60)
	pe.Acceleration = Vector3.new(0, -40, 0)
	pe.Rotation = NumberRange.new(-180, 180)
	pe.RotSpeed = NumberRange.new(-360, 360)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.3) })
	pe.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 60)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 255, 90)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 160, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(230, 100, 255)),
	})
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	pe.Parent = emitterHost
	pe:Emit(60)
	game:GetService("Debris"):AddItem(emitterHost, 2.5)
end

local function nearestPlayer(pos)
	local nearest, nearestDist = nil, 30
	for _, plr in ipairs(Players:GetPlayers()) do
		local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local d = (hrp.Position - pos).Magnitude
			if d < nearestDist then nearestDist = d nearest = plr end
		end
	end
	return nearest
end

task.spawn(function()
	if not sellPart then warn("[SellSystem] sellpart не найден") return end
	print("[SellSystem] sellpart активен (зонная проверка)")
	local center = sellPart.Position
	local halfSize = sellPart.Size / 2 + Vector3.new(3, 4, 3)

	while true do
		task.wait(0.4)
		for _, m in ipairs(Workspace:GetDescendants()) do
			if m:IsA("Model") and m:GetAttribute("Corpse") and not m:GetAttribute("Sold") and (m:GetAttribute("SellValue") or 1) > 0 then
				local pr = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
				if pr then
					local rel = pr.Position - center
					if math.abs(rel.X) < halfSize.X and math.abs(rel.Y) < halfSize.Y and math.abs(rel.Z) < halfSize.Z then
						local plr = nearestPlayer(pr.Position)
						-- Продаём ТОЛЬКО если рядом есть игрок: иначе труп не трогаем
						if plr then
							m:SetAttribute("Sold", true)
							local now = os.clock()
							if now - (lastSell[plr] or 0) >= SELL_COOLDOWN then
								lastSell[plr] = now
								local baseReward = m:GetAttribute("SellValue") or REWARD
								local isBlood = game.Workspace:GetAttribute("BloodMoon")
								local reward = isBlood and (baseReward * 2) or baseReward
								plr:SetAttribute("Money", (plr:GetAttribute("Money") or 0) + reward)
								-- ОНБОРДИНГ: первый проданный труп
								if not plr:GetAttribute("Quest_Sell") then
									plr:SetAttribute("Quest_Sell", true)
								end
								print("[Sell] " .. plr.Name .. " продал труп за " .. reward .. "$")
								celebrate(pr.Position)
							end
							m:Destroy()
						end
					end
				end
			end
		end
	end
end)
