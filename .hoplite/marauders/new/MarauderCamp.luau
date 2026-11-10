local Players = game:GetService("Players")
local SS = game:GetService("ServerStorage")
local RS = game:GetService("ReplicatedStorage")
local Pathfinding = game:GetService("PathfindingService")
local Debris = game:GetService("Debris")
local M = {}
local C = {Health = 120, Damage = 12, Range = 110, Leash = 240, FireDelay = 0.95, Reload = 3.2, Magazine = 6}
local weaponConfig = require(RS.RevolverSystem.RevolverConfig)
local camps = setmetatable({}, {__mode = "k"})

local function living(player)
	local char = player and player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if player and player.Parent == Players and hum and hum.Health > 0 and root
		and not player:GetAttribute("Downed") and not player:GetAttribute("Dead") then return root, hum end
end

local function sound(parent, key)
	local cfg = weaponConfig.Sounds[key]
	if not cfg then return end
	local s = Instance.new("Sound")
	s.SoundId, s.Volume = cfg.Id, cfg.Volume
	s.PlaybackSpeed = cfg.Pitch and (cfg.Pitch[1] + cfg.Pitch[2]) / 2 or 1
	s.RollOffMaxDistance = cfg.RollOffMax or 100
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, cfg.MaxDuration or 3)
end

local function equip(model)
	local source = SS:FindFirstChild("Revolver")
	assert(source and source:IsA("Tool"), "Marauders require ServerStorage.Revolver")
	local copy = source:Clone()
	local gun = Instance.new("Model")
	gun.Name = "MarauderRevolver"
	-- A visual Model, never a Tool: neither pickup nor death-drop handlers can grant it.
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("JointInstance") or d:IsA("WeldConstraint") then d:Destroy() end
	end
	for _, child in ipairs(copy:GetChildren()) do child.Parent = gun end
	copy:Destroy()
	local handle = gun:FindFirstChild("Handle")
	assert(handle and handle:IsA("BasePart"), "Revolver Handle missing")
	gun.PrimaryPart = handle
	local arm = model["Right Arm"]
	local gripCF = CFrame.new(0, -1, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
	gun:PivotTo(arm.CFrame * gripCF * source.Grip:Inverse())
	for _, p in ipairs(gun:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.Massless = false, false, false, false, true
			if p ~= handle then
				local weld = Instance.new("WeldConstraint")
				weld.Part0, weld.Part1, weld.Parent = handle, p, handle
			end
		end
	end
	local grip = Instance.new("Motor6D")
	grip.Name, grip.Part0, grip.Part1 = "MarauderGrip", arm, handle
	grip.C0, grip.C1, grip.Parent = gripCF, source.Grip, arm
	gun.Parent = model
	local muzzle = gun:FindFirstChild("Long Barrel") or gun:FindFirstChild("Barrel") or handle
	return gun, muzzle
end

local function attacker(hum)
	local tag = hum:FindFirstChild("creator")
	local p = tag and tag:IsA("ObjectValue") and tag.Value
	return p and p:IsA("Player") and p or nil
end

local function aggro(st, player)
	if not living(player) or st.cleared then return end
	for _, guard in ipairs(st.guards) do
		if guard.hum.Health > 0 then
			guard.target, guard.lastSeen = player, os.clock()
			guard.nextShot = math.max(guard.nextShot, os.clock() + 0.65)
			guard.model:SetAttribute("MarauderTarget", player.UserId)
		end
	end
end

local function shoot(guard, targetRoot, guardsFolder)
	local origin = guard.muzzle.Position
	local aim = targetRoot.Position + Vector3.new(0, 0.5, 0)
	local distance = (aim - origin).Magnitude
	if distance < 0.1 then return end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {guardsFolder}
	local sight = workspace:Raycast(origin, aim - origin, params)
	if sight and not sight.Instance:IsDescendantOf(targetRoot.Parent) then return end
	local spread = math.min(distance * 0.022, 2.3)
	aim += Vector3.new(guard.rng:NextNumber(-spread, spread), guard.rng:NextNumber(-spread, spread), guard.rng:NextNumber(-spread, spread))
	local ray = (aim - origin).Unit * C.Range
	local hit = workspace:Raycast(origin, ray, params)
	local ending = hit and hit.Position or origin + ray
	guard.ammo -= 1
	guard.model:SetAttribute("MarauderAmmo", guard.ammo)
	guard.model:SetAttribute("MarauderShotAt", workspace:GetServerTimeNow())
	sound(guard.muzzle, "Shot")
	local flash = Instance.new("PointLight")
	flash.Color, flash.Brightness, flash.Range = Color3.fromRGB(255, 184, 84), 4, 12
	flash.Parent = guard.muzzle
	Debris:AddItem(flash, 0.07)
	local tracer = Instance.new("Part")
	tracer.Name = "MarauderTracer"
	tracer.Anchored, tracer.CanCollide, tracer.CanTouch, tracer.CanQuery = true, false, false, false
	tracer.Material, tracer.Color = Enum.Material.Neon, Color3.fromRGB(255, 211, 117)
	tracer.Size = Vector3.new(0.045, 0.045, (ending - origin).Magnitude)
	tracer.CFrame = CFrame.lookAt((origin + ending) / 2, ending)
	tracer.Parent = workspace
	Debris:AddItem(tracer, 0.07)
	if hit then
		local victim = hit.Instance:FindFirstAncestorOfClass("Model")
		while victim and not victim:FindFirstChildOfClass("Humanoid") do victim = victim.Parent:FindFirstAncestorOfClass("Model") end
		local player = victim and Players:GetPlayerFromCharacter(victim)
		local _, hum = living(player)
		if hum then hum:TakeDamage(C.Damage) end
	end
end

local function followPath(g, goal)
	if os.clock() >= g.nextPath and not g.pathBusy then
		g.nextPath, g.pathBusy = os.clock() + 1.4, true
		local origin = g.root.Position
		task.spawn(function()
			local path = Pathfinding:CreatePath({AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 5})
			local ok = pcall(function() path:ComputeAsync(origin, goal) end)
			if g.hum.Health > 0 and ok and path.Status == Enum.PathStatus.Success then
				g.waypoints, g.waypoint = path:GetWaypoints(), 2
			end
			g.pathBusy = false
		end)
	end
	local point = g.waypoints and g.waypoints[g.waypoint]
	if point and (point.Position - g.root.Position).Magnitude < 4 then
		g.waypoint += 1
		point = g.waypoints[g.waypoint]
	end
	if point and point.Action == Enum.PathWaypointAction.Jump then g.hum.Jump = true end
	g.hum:MoveTo(point and point.Position or goal)
end

local function runGuard(st, marker, index, guardsFolder)
	local model = SS.MarauderTemplate:Clone()
	model.Name = "Marauder"
	model:SetAttribute("SellValue", 100)
	model:SetAttribute("Marauder", true)
	model:SetAttribute("POIGuard", "MarauderCamp")
	model:SetAttribute("MarauderIndex", index)
	model:SetAttribute("MarauderState", "Guard")
	model:SetAttribute("MarauderAmmo", C.Magazine)
	model:SetAttribute("MarauderReloadDuration", C.Reload)
	model:PivotTo(marker.CFrame * CFrame.new(0, 3, 0))
	local hum, root = model.Humanoid, model.HumanoidRootPart
	hum.MaxHealth, hum.Health, hum.WalkSpeed = C.Health, C.Health, 13
	hum.BreakJointsOnDeath, hum.RequiresNeck = false, false
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = false end
	end
	local gun, muzzle = equip(model)
	local g = {model = model, hum = hum, root = root, gun = gun, muzzle = muzzle, home = root.Position,
		ammo = C.Magazine, nextShot = 0, nextPath = 0, nextStrafe = 0, side = index % 2 == 0 and 1 or -1,
		lastSeen = 0, reloadUntil = 0, rng = Random.new(), nextPatrol = 0, oldHealth = C.Health}
	table.insert(st.guards, g)
	local healthConnection = hum.HealthChanged:Connect(function(h)
		if h < g.oldHealth then
			local p = attacker(hum)
			if p then aggro(st, p) end
		end
		g.oldHealth = h
	end)
	hum.Died:Once(function()
		healthConnection:Disconnect()
		model:SetAttribute("MarauderState", "Dead")
		gun:Destroy()
		local grip = model["Right Arm"]:FindFirstChild("MarauderGrip")
		if grip then grip:Destroy() end
		local p = attacker(hum)
		if p then st.contributors[p.UserId] = true end
		st.remaining -= 1
		st.model:SetAttribute("MaraudersRemaining", st.remaining)
		if st.remaining == 0 then
			st.cleared = true
			st.model:SetAttribute("CampCleared", true)
			for _, player in ipairs(Players:GetPlayers()) do
				if st.contributors[player.UserId] then player:SetAttribute("MarauderCampCleared", true) end
			end
		end
	end)
	model.Parent = guardsFolder
	root:SetNetworkOwner(nil)
	task.spawn(function()
		while model.Parent and hum.Health > 0 and st.model.Parent do
			local now = os.clock()
			local targetRoot = living(g.target)
			if targetRoot and ((targetRoot.Position - st.origin).Magnitude > C.Leash or now - g.lastSeen > 25) then targetRoot = nil end
			if not targetRoot then
				g.target = nil
				model:SetAttribute("MarauderTarget", nil)
			end
			if now < g.reloadUntil then
				model:SetAttribute("MarauderState", "Reload")
				hum.WalkSpeed, hum.AutoRotate = 7, true
				if targetRoot then
					local away = root.Position - targetRoot.Position
					if away.Magnitude > 0.1 then hum:MoveTo(root.Position + away.Unit * 7) end
				else hum:MoveTo(g.home) end
			elseif g.ammo == 0 then
				g.reloadUntil = now + C.Reload
				model:SetAttribute("MarauderReloadAt", workspace:GetServerTimeNow())
				model:SetAttribute("MarauderState", "Reload")
				sound(muzzle, "ReloadOpen")
				task.delay(C.Reload, function()
					if hum.Health > 0 and model.Parent then
						g.ammo = C.Magazine
						model:SetAttribute("MarauderAmmo", g.ammo)
						sound(muzzle, "ReloadClose")
					end
				end)
			elseif targetRoot then
				local delta = targetRoot.Position - root.Position
				local params = RaycastParams.new()
				params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, {guardsFolder}
				local hit = workspace:Raycast(model.Head.Position, targetRoot.Position - model.Head.Position, params)
				local visible = not hit or hit.Instance:IsDescendantOf(targetRoot.Parent)
				if visible then g.lastSeen = now end
				hum.WalkSpeed = 13
				if delta.Magnitude > C.Range * 0.8 or not visible then
					model:SetAttribute("MarauderState", "Chase")
					hum.AutoRotate = true
					followPath(g, targetRoot.Position)
				else
					model:SetAttribute("MarauderState", "Strafe")
					hum.AutoRotate = false
					local flat = Vector3.new(delta.X, 0, delta.Z)
					if flat.Magnitude > 0.1 then
						root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
						local forward = flat.Unit
						if now >= g.nextStrafe then g.side = -g.side g.nextStrafe = now + g.rng:NextNumber(1.3, 2.4) end
						local step = Vector3.new(-forward.Z, 0, forward.X) * g.side * 9
						if delta.Magnitude < 24 then step -= forward * 8 elseif delta.Magnitude > 45 then step += forward * 5 end
						if workspace:Raycast(root.Position, step, params) then g.side = -g.side step = -step end
						hum:MoveTo(root.Position + step)
					end
					if now >= g.nextShot then g.nextShot = now + C.FireDelay shoot(g, targetRoot, guardsFolder) end
				end
			else
				model:SetAttribute("MarauderState", "Guard")
				hum.AutoRotate, hum.WalkSpeed = true, 8
				if now >= g.nextPatrol then
					g.nextPatrol = now + g.rng:NextNumber(3, 6)
					followPath(g, g.home + Vector3.new(g.rng:NextNumber(-5, 5), 0, g.rng:NextNumber(-5, 5)))
				end
			end
			task.wait(0.12)
		end
	end)
	return model
end

local function supplies(st)
	for _, crate in ipairs(st.model:GetDescendants()) do
		local kind = crate:GetAttribute("CampSupply")
		if not kind or not crate:IsA("BasePart") then continue end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name, prompt.ActionText = "TakeCampSupply", "Take supplies / Взять припасы"
		prompt.ObjectText = kind .. " • Marauder property"
		prompt.HoldDuration, prompt.MaxActivationDistance, prompt.RequiresLineOfSight = 0.65, 9, true
		prompt.Parent = crate
		prompt.Triggered:Connect(function(player)
			local root = living(player)
			if not root or crate:GetAttribute("Taken") or (root.Position - crate.Position).Magnitude > 11 then return end
			local backpack = player:FindFirstChildOfClass("Backpack")
			if not backpack then return end
			local item
			if kind == "Bandages" then
				local source = SS:FindFirstChild("BandageTemplate")
				if not source or not source:IsA("Tool") then return end
				item = source:Clone()
				item.Name = "Bandage"
			elseif kind == "Wood" then
				local source = SS:FindFirstChild("MarauderWood")
				if not source then return end
				item = source:Clone()
			end
			crate:SetAttribute("Taken", true)
			prompt.Enabled = false
			if kind == "Ammo" then
				player:SetAttribute("Ammo_Revolver", (player:GetAttribute("Ammo_Revolver") or 0) + 24)
			elseif item then
				for _, p in ipairs(item:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = false end end
				if kind == "Wood" then
					item:PivotTo(root.CFrame * CFrame.new(0, 0, -4))
					item.Parent = workspace:FindFirstChild("BuildItems") or workspace
				else item.Parent = backpack end
			end
			local label = crate:FindFirstChild("SupplyLabel")
			if label then label:Destroy() end
			crate.Color = Color3.fromRGB(65, 58, 47)
			aggro(st, player)
		end)
	end
end

function M.Start(model)
	if camps[model] then return camps[model].models end
	local guardsFolder = workspace:FindFirstChild("Marauders") or Instance.new("Folder")
	guardsFolder.Name, guardsFolder.Parent = "Marauders", workspace
	local points = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "MarauderSpawn" then table.insert(points, d) end
	end
	assert(#points == 3, "Camp requires exactly three marauder markers")
	local st = {model = model, origin = model:GetPivot().Position, guards = {}, models = {}, contributors = {}, remaining = #points}
	camps[model] = st
	model:SetAttribute("MaraudersRemaining", #points)
	for i, point in ipairs(points) do table.insert(st.models, runGuard(st, point, i, guardsFolder)) end
	supplies(st)
	model.Destroying:Once(function()
		for _, g in ipairs(st.guards) do if g.hum.Health > 0 then g.model:Destroy() end end
		camps[model] = nil
	end)
	return st.models
end
return M
