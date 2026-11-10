-- QuestServer: квесты NPC (диалоги на клиенте, прогресс и награды на сервере).
-- Прогресс хранится на время матча (как деньги и дни).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local folder = RS:WaitForChild("QuestSystem")
local Q = require(folder:WaitForChild("QuestData"))
local remote = folder:WaitForChild("QuestRemote")

local AntiCheat
pcall(function() AntiCheat = require(SSS:WaitForChild("AntiCheat", 5)) end)

local TALK_DIST = 18

-- ===== NPC-реестр (по атрибуту NPCId) =====
local npcModels = {}
local function register(m)
	if m:IsA("Model") then
		local id = m:GetAttribute("NPCId")
		if id then npcModels[id] = m end
	end
end
for _, d in ipairs(Workspace:GetDescendants()) do register(d) end
Workspace.DescendantAdded:Connect(register)

local function npcRoot(m)
	if not m or not m.Parent then return nil end
	return m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Torso") or m.PrimaryPart
end
local function playerRoot(p)
	local c = p.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end
local function near(p, npcId, dist)
	local r, pr = npcRoot(npcModels[npcId]), playerRoot(p)
	return r and pr and (r.Position - pr.Position).Magnitude <= dist
end
local function isAlive(p)
	if p:GetAttribute("Dead") or p:GetAttribute("Downed") then return false end
	local c = p.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0
end

-- ===== Заказы дня (общие для всех игроков, обновляются каждый день) =====
local dailyDefs = {}   -- qid -> def (как в Q.QUESTS, + daily=true)
local offers = {}      -- npcId -> qid на сегодня
local newDailies
local function getDef(qid) return Q.QUESTS[qid] or dailyDefs[qid] end

-- ===== Данные игроков =====
local data = {}
local function sync(p)
	local d = data[p]
	if d then remote:FireClient(p, "state", d.quests, dailyDefs, offers) end
end
local function toast(p, kind, qid, extra)
	remote:FireClient(p, "toast", kind, qid, extra)
end

local function checkReady(p, qid)
	local st = data[p].quests[qid]
	if not st or st.state ~= "active" then return end
	for i, g in ipairs(getDef(qid).goals) do
		if (st.prog[i] or 0) < g.count then return end
	end
	st.state = "ready"
	toast(p, "ready", qid)
end

-- добавить прогресс всем подходящим целям активных квестов
local function addProgress(p, pred, amount)
	local d = data[p]
	if not d then return false end
	local changed = false
	for qid, st in pairs(d.quests) do
		if st.state == "active" then
			for i, g in ipairs(getDef(qid).goals) do
				if pred(g, st, qid, i) and (st.prog[i] or 0) < g.count then
					st.prog[i] = math.min(g.count, (st.prog[i] or 0) + (amount or 1))
					changed = true
				end
			end
			checkReady(p, qid)
		end
	end
	if changed then sync(p) end
	return changed
end

local function wants(p, pred)
	local d = data[p]
	if not d then return false end
	for qid, st in pairs(d.quests) do
		if st.state == "active" then
			for i, g in ipairs(getDef(qid).goals) do
				if pred(g, st, qid, i) and (st.prog[i] or 0) < g.count then return true end
			end
		end
	end
	return false
end

-- ===== Награды =====
local function findBandage()
	return Workspace:FindFirstChild("Bandage") or game:GetService("ServerStorage"):FindFirstChild("Bandage", true)
end
local function giveReward(p, r)
	local grants = {}
	local backpack = p:FindFirstChildOfClass("Backpack")
	if r.tools then
		if not backpack then return false end
		for _, name in ipairs(r.tools) do
			local src = game:GetService("ServerStorage"):FindFirstChild(name)
			if not src or not src:IsA("Tool") then
				warn("[QuestServer] missing reward tool: " .. name)
				return false
			end
			table.insert(grants, src)
		end
	end
	for _, src in ipairs(grants) do
		local tool = src:Clone()
		for _, part in ipairs(tool:GetDescendants()) do
			if part:IsA("BasePart") then part.Anchored, part.CanCollide, part.Massless = false, false, true end
		end
		tool.Parent = backpack
	end
	if r.money then p:SetAttribute("Money", (p:GetAttribute("Money") or 0) + r.money) end
	if r.shells then p:SetAttribute("Ammo_Shotgun", (p:GetAttribute("Ammo_Shotgun") or 0) + r.shells) end
	if r.title then p:SetAttribute("Title", r.title) end
	if r.item then
		local it = Q.ITEMS and Q.ITEMS[r.item]
		if it and it.artifact then p:SetAttribute("Artifact_" .. r.item, true) end
		local store = game:GetService("ServerStorage"):FindFirstChild("QuestItems")
		local src = it and store and store:FindFirstChild(it.tool)
		local bp = p:FindFirstChildOfClass("Backpack")
		if src and bp then
			local t = src:Clone()
			for _, d in ipairs(t:GetDescendants()) do
				if d:IsA("BasePart") then d.Anchored = false end
			end
			t.Parent = bp
		else
			warn("[QuestServer] не нашёл предмет награды " .. tostring(r.item))
		end
	end
	if r.bandage then
		local src = findBandage()
		local bp = p:FindFirstChildOfClass("Backpack")
		if src and src:IsA("Tool") and bp then
			for _ = 1, r.bandage do
				local t = src:Clone()
				for _, d in ipairs(t:GetDescendants()) do
					if d:IsA("BasePart") then d.Anchored = false end
				end
				t.Parent = bp
			end
		else
			warn("[QuestServer] не нашёл Bandage для награды")
		end
	end
	return true
end

-- ===== Remote =====
remote.OnServerEvent:Connect(function(p, action, a1)
	if AntiCheat and AntiCheat.rate and not AntiCheat.rate(p, "quest", 8, 1) then return end
	local d = data[p]
	if not d then return end
	if action == "sync" then sync(p) return end
	if type(a1) ~= "string" then return end

	if action == "accept" then
		local def = getDef(a1)
		if not def or d.quests[a1] then return end
		if not near(p, def.npc, TALK_DIST) then return end
		if def.daily then
			if offers[def.npc] ~= a1 then return end
		else
			-- квесты одного NPC идут по порядку
			for _, q in ipairs(Q.NPCS[def.npc].quests) do
				if q == a1 then break end
				local s = d.quests[q]
				if not s or s.state ~= "done" then return end
			end
		end
		local st = { state = "active", prog = {} }
		for i in ipairs(def.goals) do st.prog[i] = 0 end
		d.quests[a1] = st
		toast(p, "new", a1)
		if p:GetAttribute("MarauderCampCleared") then
			addProgress(p, function(g) return g.kind == "marauderCamp" end)
		end
		sync(p)
	elseif action == "turnin" then
		local st, def = d.quests[a1], getDef(a1)
		if not st or not def or st.state ~= "ready" then return end
		if not near(p, def.npc, TALK_DIST) then return end
		if not isAlive(p) or not giveReward(p, def.reward) then return end
		st.state = "done"
		toast(p, "done", a1)
		sync(p)
		print("[QuestServer] " .. p.Name .. " сдал квест " .. a1)
	elseif action == "abandon" then
		local st = d.quests[a1]
		if st and st.state ~= "done" then
			d.quests[a1] = nil
			sync(p)
		end
	elseif action == "talk" then
		if not Q.NPCS[a1] or not near(p, a1, TALK_DIST) then return end
		addProgress(p, function(g) return g.kind == "talk" and g.npc == a1 end)
	end
end)

local function watchCampClear(player)
	player:GetAttributeChangedSignal("MarauderCampCleared"):Connect(function()
		if player:GetAttribute("MarauderCampCleared") then
			addProgress(player, function(g) return g.kind == "marauderCamp" end)
		end
	end)
end
Players.PlayerAdded:Connect(watchCampClear)
for _, player in ipairs(Players:GetPlayers()) do watchCampClear(player) end

-- ===== Смерть игрока: сброс серии ночей =====
local function onDeath(p)
	local d = data[p]
	if not d then return end
	local changed = false
	for qid, st in pairs(d.quests) do
		if st.state == "active" then
			for i, g in ipairs(getDef(qid).goals) do
				if g.kind == "night" then
					if st.armed then st.armed = false end
					if g.streak and (st.prog[i] or 0) > 0 then
						st.prog[i] = 0
						changed = true
						toast(p, "fail", qid)
					end
				end
			end
		end
	end
	if changed then sync(p) end
end

local function hookCharacter(p, c)
	local h = c:WaitForChild("Humanoid", 10)
	if h then h.Died:Connect(function() onDeath(p) end) end
end

Players.PlayerAdded:Connect(function(p)
	data[p] = { quests = {} }
	p.CharacterAdded:Connect(function(c) hookCharacter(p, c) end)
	if p.Character then task.spawn(hookCharacter, p, p.Character) end
	p:GetAttributeChangedSignal("Dead"):Connect(function()
		if p:GetAttribute("Dead") then onDeath(p) end
	end)
end)
for _, p in ipairs(Players:GetPlayers()) do
	data[p] = { quests = {} }
	p.CharacterAdded:Connect(function(c) hookCharacter(p, c) end)
	if p.Character then task.spawn(hookCharacter, p, p.Character) end
	p:GetAttributeChangedSignal("Dead"):Connect(function()
		if p:GetAttribute("Dead") then onDeath(p) end
	end)
end
Players.PlayerRemoving:Connect(function(p) data[p] = nil end)


-- генерация заказов дня
local DAILY_BLOCK = { ver = true, merchant = true, barkeep = true }
local function curDay() return Workspace:GetAttribute("DayNumber") or 1 end
local rng = Random.new()
local lastDailyDay
function newDailies()
	local day = curDay()
	if lastDailyDay == day then return end
	lastDailyDay = day
	-- просроченные (не выполненные) заказы прошлых дней
	for p, d in pairs(data) do
		local changed = false
		for qid, st in pairs(d.quests) do
			local def = dailyDefs[qid]
			if def and st.state == "active" and def.day < day then
				d.quests[qid] = nil
				changed = true
				toast(p, "daily_expired", qid)
			end
		end
		if changed then sync(p) end
	end
	local pool = {
		function() local n = rng:NextInteger(4, 8) return { {kind="kill", count=n, label="g_kill_any"} }, { money = n * 6 } end,
		function() return { {kind="kill", zombie="zombieCrawler", count=3, label="g_kill_crawler"} }, { money = 35 } end,
		function() return { {kind="kill", zombie="Zombie Climber", count=2, label="g_kill_climber"} }, { money = 30 } end,
		function() return { {kind="night", count=1, label="g_night"} }, { money = 30 } end,
	}
	if day >= 3 then
		table.insert(pool, function() return { {kind="kill", zombie="SpitterZombie", count=2, label="g_kill_spitter"} }, { money = 35 } end)
	end
	local pois = Workspace:FindFirstChild("POIs")
	if pois and #pois:GetChildren() > 0 then
		table.insert(pool, function() return { {kind="poi", count=1, label="g_poi"} }, { money = 25 } end)
	end
	local npcs = {}
	for id in pairs(Q.NPCS) do
		if not DAILY_BLOCK[id] and npcModels[id] and npcModels[id].Parent then table.insert(npcs, id) end
	end
	offers = {}
	for _ = 1, math.min(3, #npcs) do
		local id = table.remove(npcs, rng:NextInteger(1, #npcs))
		local goals, reward
		if rng:NextNumber() < 0.2 then
			goals, reward = { {kind="corpse", npc=id, count=2, label="g_corpse_npc"} }, { money = 30 }
		else
			goals, reward = pool[rng:NextInteger(1, #pool)]()
		end
		local qid = "daily_" .. day .. "_" .. id
		dailyDefs[qid] = { npc = id, diff = "easy", daily = true, day = day, goals = goals, reward = reward }
		offers[id] = qid
	end
	for p in pairs(data) do
		sync(p)
		toast(p, "daily_new")
	end
	print("[QuestServer] заказы дня " .. day .. " готовы")
end

-- ===== Ночи =====
task.spawn(function()
	local nightEv = SSS:WaitForChild("NightStartEvent")
	nightEv.Event:Connect(function()
		for p, d in pairs(data) do
			if isAlive(p) then
				for qid, st in pairs(d.quests) do
					if st.state == "active" then
						for _, g in ipairs(getDef(qid).goals) do
							if g.kind == "night" then st.armed = true end
						end
					end
				end
			end
		end
	end)
end)
task.spawn(function()
	local dayEv = SSS:WaitForChild("DayStartEvent")
	dayEv.Event:Connect(function()
		for p, d in pairs(data) do
			local alive = isAlive(p)
			local changed = false
			for qid, st in pairs(d.quests) do
				if st.state == "active" and st.armed then
					st.armed = false
					if alive then
						for i, g in ipairs(getDef(qid).goals) do
							if g.kind == "night" and (st.prog[i] or 0) < g.count then
								st.prog[i] = (st.prog[i] or 0) + 1
								changed = true
							end
						end
						checkReady(p, qid)
					end
				end
			end
			if changed then sync(p) end
		end
		task.defer(newDailies)
	end)
end)

-- ===== Убийства зомби (тег creator, как в BestiaryServer) =====
local KNOWN = {
	Zombie = true, ["Zombie Climber"] = true, [" BIG Zombie"] = true, FasterFaster = true,
	SpitterZombie = true, zombieCrawler = true, ["Dodger-Scoffer"] = true, ZombieVampire = true,
	ZombieMiner = true, FasterOfDesert = true,
}
-- рядом с постройкой POI (охрана с атрибутом POIGuard или в радиусе постройки + 60)
local function nearPOI(model, pos, key)
	local outer = model.Parent
	if model:GetAttribute("POIGuard") == key or (outer and outer:GetAttribute("POIGuard") == key) then return true end
	local pois = Workspace:FindFirstChild("POIs")
	local poi = pois and pois:FindFirstChild("POI_" .. key)
	if poi and pos then
		local cf, size = poi:GetBoundingBox()
		local d = Vector2.new(cf.Position.X - pos.X, cf.Position.Z - pos.Z).Magnitude
		return d <= math.max(size.X, size.Z) / 2 + 60
	end
	return false
end
local function nearMine(model, pos)
	local outer = model.Parent
	if model:GetAttribute("POIGuard") == "Mine" or (outer and outer:GetAttribute("POIGuard") == "Mine") then return true end
	local pois = Workspace:FindFirstChild("POIs")
	local mine = pois and pois:FindFirstChild("POI_Mine")
	if mine and pos then
		local cf, size = mine:GetBoundingBox()
		local d = Vector2.new(cf.Position.X - pos.X, cf.Position.Z - pos.Z).Magnitude
		return d <= math.max(size.X, size.Z) / 2 + 60
	end
	return false
end

local function track(model)
	local hum = model:FindFirstChildWhichIsA("Humanoid")
	if not hum or hum:GetAttribute("QuestTracked") then return end
	local key
	local parent = model.Parent
	if parent and parent:IsA("Model") and KNOWN[parent.Name] then key = parent.Name
	elseif KNOWN[model.Name] then key = model.Name end
	if not key then return end
	hum:SetAttribute("QuestTracked", true)
	hum.Died:Connect(function()
		local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
		local pos = root and root.Position
		if key == "FasterOfDesert" then
			for p in pairs(data) do
				addProgress(p, function(g) return g.kind == "boss" end)
			end
		end
		local tag = hum:FindFirstChild("creator")
		local plr = (tag and tag:IsA("ObjectValue")) and tag.Value or nil
		if plr and plr:IsA("Player") and data[plr] then
			local mine = nearMine(model, pos)
			addProgress(plr, function(g)
				if g.kind ~= "kill" then return false end
				if g.zombie and g.zombie ~= key then return false end
				if g.near == "Mine" and not mine then return false end
				if g.near and g.near ~= "Mine" and not nearPOI(model, pos, g.near) then return false end
				return true
			end)
		end
	end)
end
for _, d in ipairs(Workspace:GetDescendants()) do
	if d:IsA("Humanoid") and d.Parent and d.Parent:IsA("Model") then task.defer(track, d.Parent) end
end
Workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Humanoid") then
		local m = d.Parent
		if m and m:IsA("Model") then task.defer(track, m) end
	end
end)

-- ===== Трупы для Мортимера + посещение POI =====
-- вид зомби у трупа (CorpseSystem сохраняет имя до переименования)
local function corpseKind(m)
	local k = m:GetAttribute("ZombieKind")
	if k then return k end
	local outer, inner = m:GetAttribute("CorpseOuter"), m:GetAttribute("CorpseKind")
	if outer and KNOWN[outer] then return outer end
	if inner and KNOWN[inner] then return inner end
	return nil
end
-- distinct=true: каждый вид зомби засчитывается один раз
local function corpseGoalFor(npcId, kind, mark)
	return function(g, st, qid, i)
		if g.kind ~= "corpse" or (g.npc or "mort") ~= npcId then return false end
		if g.distinct then
			if not kind or not st or not i then return false end
			st.kinds = st.kinds or {}
			local set = st.kinds[i] or {}
			st.kinds[i] = set
			if set[kind] then return false end
			if mark and (st.prog[i] or 0) < g.count then set[kind] = true end
		end
		return true
	end
end
local function poiGoal(g) return g.kind == "poi" end

local function poof(pos)
	local part = Instance.new("Part")
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.Position = pos
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(Color3.fromRGB(120, 110, 95))
	pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 5)})
	pe.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1)})
	pe.Lifetime = NumberRange.new(0.8, 1.4)
	pe.Speed = NumberRange.new(3, 7)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rate = 0
	pe.Parent = part
	part.Parent = Workspace
	pe:Emit(30)
	game:GetService("Debris"):AddItem(part, 2)
end

task.spawn(function()
	while true do
		task.wait(0.5)
		-- трупы (Мортимеру или заказчику из «заказа дня»)
		local targets = {}
		for p in pairs(data) do
			local dd = data[p]
			for qid, st in pairs(dd.quests) do
				if st.state == "active" then
					for i, g in ipairs(getDef(qid).goals) do
						if g.kind == "corpse" and (st.prog[i] or 0) < g.count then targets[g.npc or "mort"] = true end
					end
				end
			end
		end
		for npcId in pairs(targets) do
			local nr = npcRoot(npcModels[npcId])
			-- предикаты строятся для каждого трупа (нужен вид зомби)
			if nr then
				for _, fname in ipairs({"PlacedBuilds", "BuildItems"}) do
					local f = Workspace:FindFirstChild(fname)
					if f then
						for _, m in ipairs(f:GetChildren()) do
							if m:IsA("Model") and m:GetAttribute("Corpse") and not m:GetAttribute("Sold")
								and not m:GetAttribute("BeingHeld") and not m:GetAttribute("Welded") then
								local ok, piv = pcall(function() return m:GetPivot().Position end)
								if ok and (piv - nr.Position).Magnitude <= 12 then
									local ck = corpseKind(m)
									local pred, predMark = corpseGoalFor(npcId, ck, false), corpseGoalFor(npcId, ck, true)
									local best, bestD
									for p in pairs(data) do
										local pr = playerRoot(p)
										if pr and wants(p, pred) then
											local dd = (pr.Position - piv).Magnitude
											if dd <= 35 and (not bestD or dd < bestD) then best, bestD = p, dd end
										end
									end
									if best and addProgress(best, predMark) then
										m:SetAttribute("Sold", true)
										poof(piv)
										m:Destroy()
									end
								end
							end
						end
					end
				end
			end
		end
		-- POI
		local pois = Workspace:FindFirstChild("POIs")
		if pois then
			for p in pairs(data) do
				local pr = playerRoot(p)
				if pr and wants(p, poiGoal) then
					for _, m in ipairs(pois:GetChildren()) do
						if m:IsA("Model") then
							local cf, size = m:GetBoundingBox()
							local dd = Vector2.new(cf.Position.X - pr.Position.X, cf.Position.Z - pr.Position.Z).Magnitude
							if dd <= math.max(size.X, size.Z) / 2 + 15 then
								addProgress(p, poiGoal)
								break
							end
						end
					end
				end
			end
		end
	end
end)

task.delay(3, function() if next(offers) == nil then newDailies() end end)
print("[QuestServer] загружен: " .. #Q.ORDER .. " квестов")

