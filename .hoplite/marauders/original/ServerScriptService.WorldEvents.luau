-- WorldEvents: караван торговца (днём), Яма с зомби всех видов (ночью), награда за голову (ночью).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local SSS = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local folder = RS:WaitForChild("QuestSystem")
local Q = require(folder:WaitForChild("QuestData"))
local remote = folder:WaitForChild("WorldRemote")
local AntiCheat
pcall(function() AntiCheat = require(SSS:WaitForChild("AntiCheat", 5)) end)

local CENTER = Vector3.new(-65, 0, -48)
local BOUNDS = { minX = -440, maxX = 350, minZ = -510, maxZ = 460 }

-- ===== настройки =====
local CARAVAN_MIN_DAY, CARAVAN_CHANCE, CARAVAN_GAP, CARAVAN_FORCE = 2, 0.45, 2, 4
local PIT_MIN_DAY, PIT_CHANCE, PIT_GAP = 3, 0.35, 2
local PIT_REWARD = 75
local BOUNTY_MIN_DAY, BOUNTY_CHANCE, BOUNTY_REWARD, BOUNTY_HP_MULT = 2, 0.4, 150, 4

local function event(kind, data) remote:FireAllClients("event", kind, data or {}) end

local function ground(x, z)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { Workspace.Terrain }
	local h = Workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -600, 0), rp)
	return h and h.Position.Y, h and h.Material
end

local function avoidPoints()
	local pts = {}
	for _, c in ipairs(Workspace:GetChildren()) do
		if c:IsA("Model") and (c.Name == "house1base" or c.Name == "shop" or c.Name == "Sell" or c.Name == "sell" or c.Name == "VeronicaHut"
			or c.Name == "caravan" or c.Name == "pit" or c.Name == "Museum") then
			table.insert(pts, c:GetPivot().Position)
		end
	end
	local pois = Workspace:FindFirstChild("POIs")
	if pois then for _, m in ipairs(pois:GetChildren()) do if m:IsA("Model") then table.insert(pts, m:GetPivot().Position) end end end
	local town = Workspace:FindFirstChild("TownNPCs")
	if town then for _, m in ipairs(town:GetChildren()) do if m:IsA("Model") then table.insert(pts, m:GetPivot().Position) end end end
	return pts
end

-- ровное место на расстоянии rMin..rMax от точки
local function findSpot(from, rMin, rMax, flatR, avoidD)
	local pts = avoidPoints()
	for _ = 1, 80 do
		local ang = math.random() * math.pi * 2
		local r = rMin + math.random() * (rMax - rMin)
		local x, z = from.X + math.cos(ang) * r, from.Z + math.sin(ang) * r
		if x > BOUNDS.minX and x < BOUNDS.maxX and z > BOUNDS.minZ and z < BOUNDS.maxZ then
			local ok = true
			for _, p in ipairs(pts) do
				if (Vector3.new(p.X, 0, p.Z) - Vector3.new(x, 0, z)).Magnitude < avoidD then ok = false break end
			end
			if ok then
				local lo, hi = math.huge, -math.huge
				for _, d in ipairs({ {0,0}, {flatR,0}, {-flatR,0}, {0,flatR}, {0,-flatR}, {flatR*0.7,flatR*0.7}, {-flatR*0.7,-flatR*0.7} }) do
					local y, mat = ground(x + d[1], z + d[2])
					if not y or mat == Enum.Material.Water then ok = false break end
					lo = math.min(lo, y) hi = math.max(hi, y)
				end
				if ok and hi - lo < 3 then return Vector3.new(x, lo, z) end
			end
		end
	end
	return nil
end

local function nearestPlayer(pos, maxD)
	local best, bd
	for _, p in ipairs(Players:GetPlayers()) do
		local c = p.Character
		local r = c and c:FindFirstChild("HumanoidRootPart")
		local h = c and c:FindFirstChildOfClass("Humanoid")
		if r and h and h.Health > 0 and not p:GetAttribute("Dead") then
			local d = (r.Position - pos).Magnitude
			if (not maxD or d <= maxD) and (not bd or d < bd) then best, bd = p, d end
		end
	end
	return best, bd
end

-- ===== спавн зомби с анимацией вылезания (как в ZombieSpawner) =====
local SPAWN_ANIM = "rbxassetid://126003297221572"
local TYPES = {
	{ "ZombieTemplate", "zombie base" },
	{ "ClimberTemplate", "Zombie Climber" },
	{ "BigZombieTemplate", " BIG Zombie" },
	{ "FasterFasterTemplate", "FasterFaster" },
	{ "SpitterTemplate", "SpitterZombie" },
	{ "CrawlerTemplate", "zombieCrawler" },
	{ "DodgerTemplate", "Dodger-Scoffer" },
	{ "VampireTemplate", "ZombieVampire" },
	{ "BomberTemplate", "ZombieMiner" },
}

local function aggro(hum, plr)
	if not hum or not plr then return end
	local tag = hum:FindFirstChild("creator")
	if not tag then
		tag = Instance.new("ObjectValue")
		tag.Name = "creator"
		tag.Parent = hum
	end
	tag.Value = plr
end

local function spawnZombie(tmplName, name, pos, onReady)
	local tmpl = SS:FindFirstChild(tmplName)
	if not tmpl then warn("[WorldEvents] нет шаблона " .. tmplName) return nil end
	local clone = tmpl:Clone()
	clone.Name = name
	clone:PivotTo(CFrame.new(pos) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
	clone.Parent = Workspace
	local humModel = clone:FindFirstChild("Zombie") or clone
	humModel:SetAttribute("Rising", true)
	clone:SetAttribute("Rising", true)
	local root = clone:FindFirstChild("HumanoidRootPart", true)
	local was = root and root.Anchored
	if root then root.Anchored = true end
	local hum = clone:FindFirstChildWhichIsA("Humanoid", true)
	if hum then
		local an = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
		local a = Instance.new("Animation")
		a.AnimationId = SPAWN_ANIM
		local ok, tr = pcall(function() return an:LoadAnimation(a) end)
		if ok and tr then tr.Priority = Enum.AnimationPriority.Action tr:Play(0.1) end
	end
	task.delay(1.6, function()
		if not clone.Parent then return end
		if root and root.Parent then
			local p = root.Position
			local lk = root.CFrame.LookVector
			local fl = Vector3.new(lk.X, 0, lk.Z)
			if fl.Magnitude < 0.01 then fl = Vector3.new(0, 0, 1) end
			root.CFrame = CFrame.lookAt(p, p + fl.Unit)
			root.AssemblyLinearVelocity = Vector3.zero
			root.Anchored = was or false
		end
		if hum then
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
			task.wait(0.1)
			hum:ChangeState(Enum.HumanoidStateType.Running)
		end
		humModel:SetAttribute("Rising", nil)
		clone:SetAttribute("Rising", nil)
		aggro(hum, (nearestPlayer(pos, 250)))
		if onReady then onReady(clone, hum) end
	end)
	task.delay(300, function() if clone.Parent then clone:Destroy() end end)
	return clone, hum
end

-- =====================================================================
-- КАРАВАН
-- =====================================================================
local caravan, stock, lastCaravanDay = nil, {}, -10
local TRADE_KEYS = {}
for k in pairs(Q.TRADE) do table.insert(TRADE_KEYS, k) end
table.sort(TRADE_KEYS)

local function spawnCaravan(day)
	if caravan and caravan.Parent then return end
	local tpl = SS:FindFirstChild("CaravanTemplate")
	if not tpl then warn("[WorldEvents] нет CaravanTemplate") return end
	local pos = findSpot(CENTER, 90, 210, 7, 45)
	if not pos then warn("[WorldEvents] караван: нет места") return end
	-- ставим на самую высокую точку под фургоном (чтобы колёса не уходили в землю)
	local top = pos.Y
	for _, d in ipairs({ {0,0}, {6,0}, {-6,0}, {0,6}, {0,-6}, {4,4}, {-4,-4}, {4,-4}, {-4,4} }) do
		local gy = ground(pos.X + d[1], pos.Z + d[2])
		if gy and gy > top then top = gy end
	end
	pos = Vector3.new(pos.X, top + 0.5, pos.Z)
	local m = tpl:Clone()
	m.Name = "caravan"
	local look = Vector3.new(CENTER.X, pos.Y, CENTER.Z)
	m:PivotTo(CFrame.lookAt(pos, look)) -- -Z (прилавок и торговец) смотрит на центр
	m:SetAttribute("WorldBeacon", "caravan")
	m.Parent = Workspace
	caravan = m
	lastCaravanDay = day
	-- товары: 3 случайных
	stock = {}
	local pool = table.clone(TRADE_KEYS)
	for _ = 1, 3 do
		local i = math.random(1, #pool)
		table.insert(stock, pool[i])
		table.remove(pool, i)
	end
	remote:FireAllClients("stock", stock)
	event("caravan_arrive")
	print(string.format("[WorldEvents] караван на %.0f, %.0f, товары: %s", pos.X, pos.Z, table.concat(stock, ", ")))
end

local function removeCaravan()
	if caravan and caravan.Parent then
		caravan:Destroy()
		event("caravan_leave")
	end
	caravan = nil
	stock = {}
	remote:FireAllClients("stock", stock)
end

local function giveTrade(p, key)
	local bp = p:FindFirstChildOfClass("Backpack")
	local function giveTool(tmpl, name)
		if not tmpl or not bp then return false end
		local t = tmpl:Clone()
		t.Name = name
		for _, d in ipairs(t:GetDescendants()) do if d:IsA("BasePart") then d.Anchored = false end end
		if name == "Shotgun" then
			pcall(function()
				local cfg = require(RS.ShotgunSystem.ShotgunConfig)
				t:SetAttribute("Ammo", cfg.Magazine)
				t:SetAttribute("Reloading", false)
			end)
		end
		t.Parent = bp
		return true
	end
	if key == "eoka" then return giveTool(Workspace:FindFirstChild("Eoka"), "Eoka")
	elseif key == "shotgun" then return giveTool(SS:FindFirstChild("Shotgun") or game.StarterPack:FindFirstChild("Shotgun"), "Shotgun")
	elseif key == "revolver" then return giveTool(game.StarterPack:FindFirstChild("Revolver") or SS:FindFirstChild("Revolver"), "Revolver")
	elseif key == "combatknife" then return giveTool(SS:FindFirstChild("KnifeTemplate"), "Knife")
	elseif key == "rebar" then return giveTool(Workspace:FindFirstChild("Rebar"), "Rebar")
	elseif key == "bandage2" then
		local b = Workspace:FindFirstChild("Bandage")
		return giveTool(b, "Bandage") and giveTool(b, "Bandage")
	elseif key == "shells" then p:SetAttribute("Ammo_Shotgun", (p:GetAttribute("Ammo_Shotgun") or 0) + 24) return true
	elseif key == "ammo" then p:SetAttribute("Ammo_Revolver", (p:GetAttribute("Ammo_Revolver") or 0) + 24) return true
	end
	return false
end

remote.OnServerEvent:Connect(function(p, action, key)
	if AntiCheat and AntiCheat.rate and not AntiCheat.rate(p, "worldev", 6, 1) then return end
	if action == "getstock" then
		remote:FireClient(p, "stock", stock)
		return
	end
	if action ~= "buy" or type(key) ~= "string" then return end
	if AntiCheat and AntiCheat.canAct and not AntiCheat.canAct(p) then return end
	if not caravan or not caravan.Parent then return end
	if not table.find(stock, key) then remote:FireClient(p, "buy", false, "sold") return end
	local npc = caravan:FindFirstChild("Silas Crane")
	local root = npc and npc:FindFirstChild("HumanoidRootPart")
	local pr = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if not root or not pr or (root.Position - pr.Position).Magnitude > 18 then return end
	local price = Q.TRADE[key].price
	local money = p:GetAttribute("Money") or 0
	if money < price then remote:FireClient(p, "buy", false, "money") return end
	p:SetAttribute("Money", money - price)
	if giveTrade(p, key) then
		remote:FireClient(p, "buy", true, key)
		print("[WorldEvents] " .. p.Name .. " купил у каравана " .. key)
	else
		p:SetAttribute("Money", money) -- вернуть деньги
		warn("[WorldEvents] не удалось выдать " .. key)
	end
end)

-- =====================================================================
-- ЯМА
-- =====================================================================
local pit, pitZombies, lastPitDay, pitCleared = nil, {}, -10, false

local function buildPit(pos)
	local m = Instance.new("Model")
	m.Name = "pit"
	local function part(props)
		local p = Instance.new("Part")
		p.Anchored = true p.CanCollide = false p.CanQuery = false p.CanTouch = false
		p.TopSurface = Enum.SurfaceType.Smooth p.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in pairs(props) do p[k] = v end
		p.Parent = m
		return p
	end
	local flat = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	local core = part({ Name = "PitCore", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 24, 24), CFrame = flat + Vector3.new(0, 0.12, 0),
		Color = Color3.fromRGB(58, 42, 28), Material = Enum.Material.Ground })
	part({ Name = "PitInner", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 18, 18), CFrame = flat + Vector3.new(0, 0.18, 0),
		Color = Color3.fromRGB(22, 14, 10), Material = Enum.Material.Slate })
	part({ Name = "PitDeep", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 11, 11), CFrame = flat + Vector3.new(0, 0.24, 0),
		Color = Color3.fromRGB(4, 2, 2), Material = Enum.Material.SmoothPlastic })
	-- камни по краю
	for i = 1, 16 do
		local a = (i / 16) * math.pi * 2 + math.random() * 0.2
		local r = 11.5 + math.random() * 1.5
		local s = 1.6 + math.random() * 2.4
		part({ Name = "PitRock", Size = Vector3.new(s, s * (0.5 + math.random() * 0.5), s * (0.7 + math.random() * 0.6)),
			CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * r, s * 0.25, math.sin(a) * r)) * CFrame.Angles(math.random() * 0.8, math.random() * 6.28, math.random() * 0.8),
			Color = Color3.fromRGB(110 + math.random(0, 30), 90 + math.random(0, 20), 70), Material = Enum.Material.Rock, CanCollide = true })
	end
	-- пыль, красное свечение
	local fx = part({ Name = "PitFX", Size = Vector3.new(16, 1, 16), CFrame = CFrame.new(pos + Vector3.new(0, 0.5, 0)), Transparency = 1 })
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(Color3.fromRGB(120, 95, 70), Color3.fromRGB(70, 50, 35))
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 7) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	pe.Lifetime = NumberRange.new(2, 4)
	pe.Speed = NumberRange.new(2, 5)
	pe.Acceleration = Vector3.new(0, 2, 0)
	pe.Rate = 18
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Parent = fx
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 70, 30)
	light.Range = 28
	light.Brightness = 2.5
	light.Parent = fx
	m.PrimaryPart = core
	m:SetAttribute("WorldBeacon", "pit")
	m.Parent = Workspace
	-- выброс песка при открытии
	local burst = pe:Clone()
	burst.Rate = 0
	burst.Speed = NumberRange.new(15, 30)
	burst.SpreadAngle = Vector2.new(60, 60)
	burst.Parent = fx
	burst:Emit(120)
	return m
end

local function checkPitCleared()
	if pitCleared or not pit then return end
	if #pitZombies < 10 then return end
	for _, h in ipairs(pitZombies) do
		if h.Parent and h.Health > 0 then return end
	end
	pitCleared = true
	local pos = pit:GetPivot().Position
	local winners = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if r and (r.Position - pos).Magnitude <= 150 then
			p:SetAttribute("Money", (p:GetAttribute("Money") or 0) + PIT_REWARD)
			table.insert(winners, p.Name)
		end
	end
	event("pit_clear", { reward = PIT_REWARD })
	print("[WorldEvents] Яма зачищена, награда: " .. table.concat(winners, ", "))
end

local function openPit(day)
	if pit and pit.Parent then return end
	local np = nearestPlayer(CENTER)
	local from = CENTER
	if np and np.Character and np.Character:FindFirstChild("HumanoidRootPart") then from = np.Character.HumanoidRootPart.Position end
	local pos = findSpot(from, 70, 160, 12, 40)
	if not pos then warn("[WorldEvents] Яма: нет места") return end
	pit = buildPit(pos)
	pitZombies, pitCleared, lastPitDay = {}, false, day
	event("pit_open")
	print(string.format("[WorldEvents] Яма открылась на %.0f, %.0f", pos.X, pos.Z))
	-- 10 зомби: все 9 видов + ещё один случайный
	local order = {}
	for i = 1, #TYPES do table.insert(order, TYPES[i]) end
	table.insert(order, TYPES[math.random(1, 6)])
	for i = #order, 2, -1 do local j = math.random(1, i) order[i], order[j] = order[j], order[i] end
	task.spawn(function()
		task.wait(3)
		for _, t in ipairs(order) do
			if not pit or not pit.Parent then break end
			local a, r = math.random() * math.pi * 2, math.random() * 5
			local spawnPos = pos + Vector3.new(math.cos(a) * r, 0.5, math.sin(a) * r)
			local clone, hum = spawnZombie(t[1], t[2], spawnPos)
			if clone then
				clone:SetAttribute("PitZombie", true)
				if hum then
					table.insert(pitZombies, hum)
					hum.Died:Connect(function() task.defer(checkPitCleared) end)
				end
			end
			task.wait(1.8)
		end
	end)
end

local function closePit()
	if pit and pit.Parent then
		pit:Destroy()
		event("pit_close")
	end
	pit = nil
end

-- =====================================================================
-- НАГРАДА ЗА ГОЛОВУ
-- =====================================================================
local bounty = nil
local function spawnBounty(day)
	if bounty and bounty.Parent then return end
	local np = nearestPlayer(CENTER)
	if not np then return end
	local from = np.Character.HumanoidRootPart.Position
	local pos = findSpot(from, 90, 150, 3, 25)
	if not pos then return end
	local pool = { TYPES[1], TYPES[2], TYPES[3] }
	if day >= 5 then table.insert(pool, TYPES[4]) end
	local t = pool[math.random(1, #pool)]
	local nameIdx = math.random(1, Q.BOUNTY_NAMES)
	local clone, hum = spawnZombie(t[1], t[2], pos + Vector3.new(0, 0.5, 0), function(c, h)
		if h then
			h.MaxHealth = h.MaxHealth * BOUNTY_HP_MULT
			h.Health = h.MaxHealth
		end
	end)
	if not clone then return end
	bounty = clone
	clone:SetAttribute("Bounty", true)
	clone:SetAttribute("BountyName", nameIdx)
	clone:SetAttribute("BountyReward", BOUNTY_REWARD)
	clone:SetAttribute("WorldBeacon", "bounty")
	local hl = Instance.new("Highlight")
	hl.FillColor = Color3.fromRGB(180, 20, 20)
	hl.FillTransparency = 0.75
	hl.OutlineColor = Color3.fromRGB(255, 60, 40)
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Parent = clone
	event("bounty_new", { name = nameIdx, reward = BOUNTY_REWARD })
	print("[WorldEvents] награда за голову: " .. t[2] .. " #" .. nameIdx)
	if hum then
		hum.Died:Connect(function()
			local tag = hum:FindFirstChild("creator")
			local killer = tag and tag.Value
			if killer and killer:IsA("Player") then
				killer:SetAttribute("Money", (killer:GetAttribute("Money") or 0) + BOUNTY_REWARD)
				event("bounty_dead", { name = nameIdx, reward = BOUNTY_REWARD, killer = killer.DisplayName })
			end
			clone:SetAttribute("WorldBeacon", nil)
			bounty = nil
		end)
	end
end

local function bountyFlee()
	if bounty and bounty.Parent then
		local h = bounty:FindFirstChildWhichIsA("Humanoid", true)
		if h and h.Health > 0 then
			event("bounty_gone", { name = bounty:GetAttribute("BountyName") })
			bounty:Destroy()
		end
	end
	bounty = nil
end

-- =====================================================================
-- ДЕНЬ / НОЧЬ
-- =====================================================================
task.spawn(function()
	local dayEv = SSS:WaitForChild("DayStartEvent")
	dayEv.Event:Connect(function(day)
		day = tonumber(day) or 1
		closePit()
		bountyFlee()
		if day >= CARAVAN_MIN_DAY and day - lastCaravanDay >= CARAVAN_GAP then
			if math.random() < CARAVAN_CHANCE or day - lastCaravanDay >= CARAVAN_FORCE then
				task.delay(math.random(5, 20), function() spawnCaravan(day) end)
			end
		end
	end)
end)
task.spawn(function()
	local nightEv = SSS:WaitForChild("NightStartEvent")
	nightEv.Event:Connect(function(day)
		day = tonumber(day) or 1
		removeCaravan()
		if day >= PIT_MIN_DAY and day - lastPitDay >= PIT_GAP and math.random() < PIT_CHANCE then
			task.delay(math.random(10, 25), function() openPit(day) end)
		elseif day >= BOUNTY_MIN_DAY and math.random() < BOUNTY_CHANCE then
			task.delay(math.random(20, 40), function() spawnBounty(day) end)
		end
	end)
end)

-- команды для тестов: ServerScriptService.WorldEventCommand:Invoke("caravan"/"pit"/"bounty"/"clear")
local api = SSS:FindFirstChild("WorldEventCommand") or Instance.new("BindableFunction")
api.Name = "WorldEventCommand"
api.Parent = SSS
api.OnInvoke = function(cmd)
	local day = Workspace:GetAttribute("DayNumber") or 5
	if cmd == "caravan" then spawnCaravan(day) return caravan and "ok" or "fail"
	elseif cmd == "pit" then openPit(day) return pit and "ok" or "fail"
	elseif cmd == "bounty" then spawnBounty(math.max(day, 5)) return bounty and "ok" or "fail"
	elseif cmd == "clear" then removeCaravan() closePit() bountyFlee() return "ok" end
end

print("[WorldEvents] загружен: караван, Яма, награда за голову")

