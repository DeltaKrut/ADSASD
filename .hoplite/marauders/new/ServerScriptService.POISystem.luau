-- POISystem: заброшенные постройки (Салун, Офис шерифа, Заправка, Военный лагерь, Шахта).
-- Каждый день часть построек может появиться в свободном месте карты и исчезнуть через N дней.
-- В каждой постройке/рядом 1-3 зомби (60% обычный, 40% делят остальные, кроме босса) и лут.
-- Шаблоны: ServerStorage.POITemplates (внутри маркеры ZombieSpawn / LootSpawn).
-- Рельеф и объекты карты НЕ трогает: просто ищет пустое ровное место.
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

-- ═══════════════ НАСТРОЙКИ ═══════════════
local MarauderCamp = require(ServerScriptService:WaitForChild("MarauderCamp"))
local CONFIG = {
	{ Key = "MarauderCamp", MinDay = 3, Chance = 1, Lifetime = {9999}, Cooldown = 0, Persistent = true },
	-- Lifetime = сколько дней стоит постройка (случайно из списка). {1} — всегда 1 день, {3} — всегда 3, {1,3} — 1 или 3
	-- MinDay = с какого дня может появиться, Chance = шанс появиться в новый день (если её сейчас нет)
	-- Cooldown = сколько дней после исчезновения она не может появиться снова
	{ Key = "Saloon",        MinDay = 1, Chance = 0.50, Lifetime = {1, 3}, Cooldown = 1 },
	{ Key = "GasStation",    MinDay = 1, Chance = 0.50, Lifetime = {1, 3}, Cooldown = 1 },
	{ Key = "SheriffOffice", MinDay = 2, Chance = 0.40, Lifetime = {1, 3}, Cooldown = 1 },
	{ Key = "Mine",          MinDay = 2, Chance = 0.35, Lifetime = {1, 3}, Cooldown = 1 },
	{ Key = "MilitaryCamp",  MinDay = 3, Chance = 0.30, Lifetime = {1, 3}, Cooldown = 1 },
}
local MIN_ACTIVE = 1          -- минимум построек на карте одновременно
local MAX_ACTIVE = 3          -- максимум
local GUARDS_MIN, GUARDS_MAX = 1, 3      -- зомби на постройку
local GUARD_TRIGGER_DIST = 170           -- зомби появляются, когда игрок подходит ближе
local BASE_ZOMBIE_CHANCE = 0.60          -- обычный зомби; остальные 40% делят прочие типы (кроме босса)
local LOOT_CHANCE = 0.70                 -- шанс, что в точке лута что-то лежит
local MAP_MIN = Vector2.new(-470, -545)  -- границы карты (внутри стен)
local MAP_MAX = Vector2.new(385, 495)
local CENTER = Vector3.new(-65, 0, -48)  -- точка спавна игроков
local MIN_FROM_CENTER = 110
local MIN_FROM_PLAYER = 70               -- не ставим постройку прямо перед носом у игрока

-- типы зомби (без босса FasterOfDesert)
local ZOMBIE_TYPES = {
	{ tmpl = "ZombieTemplate",       name = "zombie base" },
	{ tmpl = "ClimberTemplate",      name = "Zombie Climber" },
	{ tmpl = "BigZombieTemplate",    name = " BIG Zombie" },
	{ tmpl = "FasterFasterTemplate", name = "FasterFaster" },
	{ tmpl = "SpitterTemplate",      name = "SpitterZombie" },
	{ tmpl = "CrawlerTemplate",      name = "zombieCrawler" },
	{ tmpl = "DodgerTemplate",       name = "Dodger-Scoffer" },
	{ tmpl = "VampireTemplate",      name = "ZombieVampire", indoorOnly = true }, -- днём горит на солнце -> только внутри
}

-- лут по постройкам: ключ = вес
local LOOT = {
	Saloon        = { shells = 6, money10 = 14, bandage = 20, ammo = 20, wood = 8,  bomb = 6,  eoka = 8, knife = 6, revolver = 6, combatknife = 2 },
	GasStation    = { shells = 8, money10 = 10, ammo = 18, bandage = 14, wood = 16, bomb = 12, eoka = 10, spear = 8, pipe = 8, revolver = 3 },
	SheriffOffice = { shells = 14, money10 = 12, revolver = 14, ammo = 26, shotgun = 5, bandage = 14, knife = 8, combatknife = 6, eoka = 6 },
	Mine          = { shells = 4, money10 = 8, bomb = 20, wood = 18, ammo = 14, bandage = 12, rebar = 8, spear = 8, pipe = 8, eoka = 6, revolver = 3 },
	MilitaryCamp  = { shells = 18, money10 = 8, ammo = 30, bandage = 18, shotgun = 7, revolver = 10, combatknife = 8, bomb = 12, eoka = 6 },
}
-- ═════════════════════════════════════════

local templates = ServerStorage:WaitForChild("POITemplates", 20)
if not templates then warn("[POISystem] нет ServerStorage.POITemplates") return end

local folder = Workspace:FindFirstChild("POIs") or Instance.new("Folder")
folder.Name = "POIs"
folder.Parent = Workspace

-- копии источников лута (снимаем при старте, пока игроки ничего не подобрали)
local lootCache = Instance.new("Folder")
lootCache.Name = "POILootCache"
lootCache.Parent = ServerStorage
local function cacheFrom(inst)
	if inst then
		local c = inst:Clone()
		c.Parent = lootCache
		return c
	end
end
task.wait(1)
local BI = Workspace:FindFirstChild("BuildItems")
local SOURCES = {
	bandage = { cacheFrom(Workspace:FindFirstChild("Bandage") or ServerStorage:FindFirstChild("BandageTemplate")), "tool" },
	eoka = { cacheFrom(Workspace:FindFirstChild("Eoka")), "tool" },
	pipe = { cacheFrom(Workspace:FindFirstChild("Pipe")), "tool" },
	rebar = { cacheFrom(Workspace:FindFirstChild("Rebar")), "tool" },
	spear = { ServerStorage:FindFirstChild("SpearTemplate"), "tool" },
	revolver = { ServerStorage:FindFirstChild("Revolver"), "tool" },
	shotgun = { ServerStorage:FindFirstChild("Shotgun"), "tool" },
	knife = { ServerStorage:FindFirstChild("KnifeTemplate"), "tool" },
	combatknife = { ServerStorage:FindFirstChild("CombatKnifeTemplate"), "tool" },
	ammo = { ServerStorage:FindFirstChild("AmmoBoxTemplate"), "model" },
	shells = { ServerStorage:FindFirstChild("ShellBoxTemplate"), "model" },
	wood = { cacheFrom(BI and (BI:FindFirstChild("plank") or BI:FindFirstChild("wood floor"))), "model" },
	bomb = { cacheFrom(BI and BI:FindFirstChild("bomb")), "model" },
	money10 = { ServerStorage:FindFirstChild("Money10Template"), "money" },
}

local function pickWeighted(tbl)
	local total = 0
	for k, w in pairs(tbl) do if SOURCES[k] and SOURCES[k][1] then total += w end end
	if total <= 0 then return nil end
	local r = math.random() * total
	for k, w in pairs(tbl) do
		if SOURCES[k] and SOURCES[k][1] then
			r -= w
			if r <= 0 then return k end
		end
	end
	return nil
end

-- ═══ состояние ═══
local active = {}         -- [key] = {model, spawnDay, expireDay, guards, loot, guardsSpawned, pos, radius}
local cooldownUntil = {}  -- [key] = день

local function cfgFor(key) for _, c in ipairs(CONFIG) do if c.Key == key then return c end end end

-- ═══ поиск места ═══
local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { Workspace.Terrain }

local function groundAt(x, z)
	local hit = Workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -800, 0), terrainParams)
	return hit and hit.Position.Y or nil
end

local function obstacleList()
	local list = {}
	local function add(m, extra)
		local ok, cf, size = pcall(function() return m:GetBoundingBox() end)
		if ok and cf then table.insert(list, { pos = cf.Position, r = math.max(size.X, size.Z) / 2 + (extra or 0) }) end
	end
	for _, c in ipairs(Workspace:GetChildren()) do
		if c:IsA("Model") then
			local n = string.lower(c.Name)
			if n == "house1base" or string.find(n, "shop") or string.find(n, "sell") or string.find(n, "museum") then add(c, 8) end
		end
	end
	local pb = Workspace:FindFirstChild("PlacedBuilds")
	if pb then for _, c in ipairs(pb:GetChildren()) do
		if c:IsA("Model") then add(c, 8) elseif c:IsA("BasePart") then table.insert(list, { pos = c.Position, r = c.Size.Magnitude / 2 + 8 }) end
	end end
	local hs = Workspace:FindFirstChild("HouseSpawns")
	if hs then for _, p in ipairs(hs:GetChildren()) do if p:IsA("BasePart") then table.insert(list, { pos = p.Position, r = 28 }) end end end
	for _, st in pairs(active) do table.insert(list, { pos = st.pos, r = st.radius + 10 }) end
	return list
end

local function findSpot(tmpl)
	local w = tmpl:GetAttribute("FootW") or 40
	local d = tmpl:GetAttribute("FootD") or 40
	local radius = math.sqrt(w * w + d * d) / 2
	local obstacles = obstacleList()
	for attempt = 1, 200 do
		local x = MAP_MIN.X + radius + math.random() * (MAP_MAX.X - MAP_MIN.X - radius * 2)
		local z = MAP_MIN.Y + radius + math.random() * (MAP_MAX.Y - MAP_MIN.Y - radius * 2)
		local p = Vector3.new(x, 0, z)
		local ok = (Vector3.new(CENTER.X, 0, CENTER.Z) - p).Magnitude >= MIN_FROM_CENTER + radius
		if ok then
			for _, o in ipairs(obstacles) do
				if (Vector3.new(o.pos.X, 0, o.pos.Z) - p).Magnitude < o.r + radius then ok = false break end
			end
		end
		if ok then
			for _, plr in ipairs(Players:GetPlayers()) do
				local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
				if hrp and (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - p).Magnitude < MIN_FROM_PLAYER + radius then ok = false break end
			end
		end
		if ok then
			local look = Vector3.new(CENTER.X, 0, CENTER.Z) - p
			local rot = CFrame.Angles(0, math.atan2(-look.X, -look.Z), 0) -- лицом к центру
			local hs = {}
			for ix = -1, 1 do
				for iz = -1, 1 do
					local off = rot * Vector3.new(ix * w * 0.45, 0, iz * d * 0.45)
					local h = groundAt(x + off.X, z + off.Z)
					if not h then ok = false break end
					table.insert(hs, h)
				end
				if not ok then break end
			end
			if ok then
				table.sort(hs)
				local maxSpread = tmpl:GetAttribute("MaxSpread") or 4
				if hs[#hs] - hs[1] <= maxSpread then
					-- с фундаментом ставим по верхней точке (низ прикрыт фундаментом), иначе по медиане
					local gy = tmpl:GetAttribute("Foundation") and (hs[#hs] - 0.8) or hs[math.ceil(#hs / 2)]
					local cf = CFrame.new(x, gy, z) * rot
					-- место должно быть пустым (кактусы, камни и т.п. не удаляем — ищем другое)
					local params = OverlapParams.new()
					params.FilterType = Enum.RaycastFilterType.Exclude
					params.FilterDescendantsInstances = { Workspace.Terrain }
					local hits = Workspace:GetPartBoundsInBox(cf * CFrame.new(0, 14, 0), Vector3.new(w + 4, 26, d + 4), params)
					if #hits == 0 then return cf, radius end
				end
			end
		end
	end
	return nil
end

-- ═══ лут ═══
local function spawnLoot(st)
	local tbl = LOOT[st.key] or LOOT.Saloon
	for _, pt in ipairs(st.model:GetDescendants()) do
		if pt:IsA("BasePart") and pt.Name == "LootSpawn" and math.random() <= LOOT_CHANCE then
			local key = pickWeighted(tbl)
			local src = key and SOURCES[key]
			if src and src[1] then
				local clone = src[1]:Clone()
				for _, d in ipairs(clone:GetDescendants()) do
					if d:IsA("BasePart") then d.Anchored = false end
				end
				local cf = CFrame.new(pt.Position + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, math.random() * 6.28, 0)
				if src[2] == "money" then
					clone.Name = string.lower(string.gsub(src[1].Name, "Template", ""))
					clone.Parent = Workspace
					clone:PivotTo(cf)
				elseif src[2] == "tool" then
					clone.Name = string.gsub(src[1].Name, "Template", "")
					clone.Parent = Workspace
					clone:PivotTo(cf)
				else
					clone.Parent = Workspace:FindFirstChild("BuildItems") or Workspace
					if clone:IsA("Model") then clone:PivotTo(cf) elseif clone:IsA("BasePart") then clone.CFrame = cf end
				end
				clone:SetAttribute("POILoot", st.key)
				table.insert(st.loot, clone)
			end
		end
	end
end

-- ═══ зомби-охрана ═══
local function pickZombieType(indoor)
	if math.random() < BASE_ZOMBIE_CHANCE then return ZOMBIE_TYPES[1] end
	local pool = {}
	for i = 2, #ZOMBIE_TYPES do
		local z = ZOMBIE_TYPES[i]
		if ServerStorage:FindFirstChild(z.tmpl) and (indoor or not z.indoorOnly) then table.insert(pool, z) end
	end
	if #pool == 0 then return ZOMBIE_TYPES[1] end
	return pool[math.random(1, #pool)]
end

local function spawnGuards(st)
	st.guardsSpawned = true
	local points = {}
	for _, pt in ipairs(st.model:GetDescendants()) do
		if pt:IsA("BasePart") and pt.Name == "ZombieSpawn" then table.insert(points, pt) end
	end
	for i = #points, 2, -1 do local j = math.random(i) points[i], points[j] = points[j], points[i] end
	local n = math.min(#points, math.random(GUARDS_MIN, GUARDS_MAX))
	local names = {}
	for i = 1, n do
		local pt = points[i]
		local zt = pickZombieType(pt:GetAttribute("Indoor") == true)
		local tmpl = ServerStorage:FindFirstChild(zt.tmpl)
		if tmpl then
			local z = tmpl:Clone()
			z.Name = zt.name
			z:SetAttribute("POIGuard", st.key)
			z:PivotTo(CFrame.new(pt.Position + Vector3.new(0, 1, 0)) * CFrame.Angles(0, math.random() * 6.28, 0))
			z.Parent = Workspace
			table.insert(st.guards, z)
			table.insert(names, zt.name)
		end
	end
	-- гарантированный зомби (атрибут ForcedGuard у шаблона, напр. шахтёр-взрывник в шахте)
	local forced = st.model:GetAttribute("ForcedGuard")
	local ftmpl = forced and ServerStorage:FindFirstChild(forced)
	if ftmpl then
		local fpt
		for i = n + 1, #points do if points[i]:GetAttribute("Indoor") == true then fpt = points[i] break end end
		if not fpt then for i = 1, #points do if points[i]:GetAttribute("Indoor") == true then fpt = points[i] break end end end
		fpt = fpt or points[1]
		if fpt then
			local z = ftmpl:Clone()
			z.Name = st.model:GetAttribute("ForcedGuardName") or forced
			z:SetAttribute("POIGuard", st.key)
			z:PivotTo(CFrame.new(fpt.Position + Vector3.new(0, 1, 0)) * CFrame.Angles(0, math.random() * 6.28, 0))
			z.Parent = Workspace
			table.insert(st.guards, z)
			table.insert(names, z.Name)
		end
	end
	print("[POISystem] " .. st.key .. ": зомби " .. table.concat(names, ", "))
end

-- ═══ земля под полом построек ═══
-- Части с атрибутом ClearTerrain (число = высота очистки над полом) убирают землю,
-- которая торчит сквозь пол. Землю сохраняем и возвращаем, когда постройка исчезает.
local Terrain = Workspace.Terrain
local function clearTerrainUnder(m)
	local saved = {}
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") and p:GetAttribute("ClearTerrain") then
			local up = tonumber(p:GetAttribute("ClearTerrain")) or 10
			local pad = tonumber(p:GetAttribute("ClearTerrainPad")) or 0
			local topY = p.Position.Y + p.Size.Y / 2
			-- земля лежит сеткой по 4 стада: снимаем на клетку ниже пола, иначе её край встаёт вровень с полом и мерцает
			local bottomY = math.floor((topY - 0.3) / 4) * 4 - 4 + 0.05
			local h = topY + up - bottomY
			local size = Vector3.new(p.Size.X + pad, h, p.Size.Z + pad)
			local cf = CFrame.new(p.Position.X, bottomY + h / 2, p.Position.Z) * p.CFrame.Rotation
			local half = size / 2
			local mn = Vector3.new(math.huge, math.huge, math.huge)
			local mx = -mn
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local w = cf * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)
						mn = mn:Min(w)
						mx = mx:Max(w)
					end
				end
			end
			local c0 = Terrain:WorldToCell(mn - Vector3.new(4, 4, 4))
			local c1 = Terrain:WorldToCell(mx + Vector3.new(4, 4, 4))
			local region = Region3int16.new(Vector3int16.new(c0.X, c0.Y, c0.Z), Vector3int16.new(c1.X, c1.Y, c1.Z))
			local ok, copy = pcall(function() return Terrain:CopyRegion(region) end)
			if ok and copy then table.insert(saved, { copy = copy, corner = region.Min }) end
			Terrain:FillBlock(cf, size, Enum.Material.Air)
		end
	end
	return saved
end

local function restoreTerrain(saved)
	if not saved then return end
	for i = #saved, 1, -1 do
		local s = saved[i]
		pcall(function() Terrain:PasteRegion(s.copy, s.corner, true) end)
	end
end

-- ═══ появление / исчезновение ═══
local function spawnPOI(key, day)
	local tmpl = templates:FindFirstChild(key)
	if not tmpl then return false end
	local cf, radius = findSpot(tmpl)
	if not cf then warn("[POISystem] не нашёл места для " .. key) return false end
	local cfg = cfgFor(key)
	local life = cfg.Lifetime[math.random(1, #cfg.Lifetime)]
	local m = tmpl:Clone()
	m.Name = "POI_" .. key
	m:PivotTo(cf)
	m:SetAttribute("POIKey", key)
	m:SetAttribute("SpawnDay", day)
	m:SetAttribute("ExpireDay", day + life)
	m.Parent = folder
	local st = { key = key, model = m, spawnDay = day, expireDay = day + life, guards = {}, loot = {},
		guardsSpawned = false, pos = cf.Position, radius = radius }
	active[key] = st
	st.terrain = clearTerrainUnder(m)
	if key == "MarauderCamp" then
		st.guards = MarauderCamp.Start(m)
		st.guardsSpawned = true
	else
		spawnLoot(st)
	end
	print(string.format("[POISystem] %s появился (день %d, на %d дн.) в %.0f, %.0f", key, day, life, cf.Position.X, cf.Position.Z))
	return true
end

local function playerNear(st, dist)
	for _, plr in ipairs(Players:GetPlayers()) do
		local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - st.pos).Magnitude < dist then return true end
	end
	return false
end

local function removePOI(key, day)
	local st = active[key]
	if not st then return end
	active[key] = nil
	cooldownUntil[key] = day + ((cfgFor(key) or {}).Cooldown or 0)
	task.spawn(function()
		-- если внутри игрок — ждём, пока уйдёт (не выдёргиваем пол из-под ног)
		local waited = 0
		while playerNear(st, st.radius + 4) and waited < 600 do task.wait(5) waited += 5 end
		-- удаляем только то, что сами создали: живых зомби-охранников и не подобранный лут
		for _, z in ipairs(st.guards) do
			local hum = z.Parent and z:FindFirstChildWhichIsA("Humanoid", true)
			if hum and hum.Health > 0 then z:Destroy() end
		end
		for _, it in ipairs(st.loot) do
			if it.Parent and (it.Parent == Workspace or it.Parent.Name == "BuildItems") and it:GetAttribute("POILoot") == key then
				local ok, piv = pcall(function() return it:GetPivot() end)
				if ok and (piv.Position - st.pos).Magnitude < st.radius + 10 then it:Destroy() end
			end
		end
		if st.model then st.model:Destroy() end
		restoreTerrain(st.terrain)
		print("[POISystem] " .. key .. " исчез")
	end)
end

local lastDay = nil
local function onDay(day)
	if day == lastDay then return end
	lastDay = day
	for key, st in pairs(active) do
		if not cfgFor(key).Persistent and day >= st.expireDay then removePOI(key, day) end
	end
	-- у оставшихся построек — новая охрана, если прошлую перебили
	for _, st in pairs(active) do
		local alive = false
		for _, z in ipairs(st.guards) do
			local hum = z.Parent and z:FindFirstChildWhichIsA("Humanoid", true)
			if hum and hum.Health > 0 then alive = true break end
		end
		if not alive and not cfgFor(st.key).Persistent then st.guards = {} st.guardsSpawned = false end
	end
	if day >= 3 and not active.MarauderCamp then spawnPOI("MarauderCamp", day) end
	local count = 0
	for key in pairs(active) do if not cfgFor(key).Persistent then count += 1 end end
	local candidates = {}
	for _, c in ipairs(CONFIG) do
		if not c.Persistent and not active[c.Key] and day >= c.MinDay and day >= (cooldownUntil[c.Key] or 0) then table.insert(candidates, c) end
	end
	for i = #candidates, 2, -1 do local j = math.random(i) candidates[i], candidates[j] = candidates[j], candidates[i] end
	for _, c in ipairs(candidates) do
		if count >= MAX_ACTIVE then break end
		if math.random() < c.Chance and spawnPOI(c.Key, day) then count += 1 end
	end
	for _, c in ipairs(candidates) do -- гарантируем минимум
		if count >= MIN_ACTIVE then break end
		if not active[c.Key] and spawnPOI(c.Key, day) then count += 1 end
	end
end

-- охрана появляется, когда игрок подходит
task.spawn(function()
	while true do
		task.wait(1)
		for _, st in pairs(active) do
			if not st.guardsSpawned and st.model.Parent and playerNear(st, GUARD_TRIGGER_DIST) then spawnGuards(st) end
		end
	end
end)

-- команды для тестов: ServerScriptService.POICommand:Invoke("spawn"/"remove"/"list", key)
local api = ServerScriptService:FindFirstChild("POICommand") or Instance.new("BindableFunction")
api.Name = "POICommand"
api.Parent = ServerScriptService
api.OnInvoke = function(cmd, key)
	local day = Workspace:GetAttribute("DayNumber") or 1
	if cmd == "spawn" then
		if active[key] then return "already" end
		return spawnPOI(key, day)
	elseif cmd == "remove" then
		removePOI(key, day)
		return true
	elseif cmd == "list" then
		local t = {}
		for k, st in pairs(active) do
			table.insert(t, string.format("%s day%d->%d @%.0f,%.1f,%.0f guards=%s", k, st.spawnDay, st.expireDay, st.pos.X, st.pos.Y, st.pos.Z, tostring(st.guardsSpawned)))
		end
		return table.concat(t, "\n")
	end
end

local dayEvent = ServerScriptService:WaitForChild("DayStartEvent", 30)
if dayEvent then dayEvent.Event:Connect(function(day) task.wait(2) onDay(day) end) end
task.wait(3) -- даём HouseSpawner/ShopSpawner поставить свои здания
onDay(Workspace:GetAttribute("DayNumber") or 1)
print("[POISystem] загружен")

