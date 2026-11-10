-- ProtectedNPCs: NPC в магазине (shop) и у скупщика (Sell) бессмертны и не сдвигаются ничем.
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local PROTECTED = { shop = true, sell = true, townnpcs = true, veronicahut = true, caravan = true, pois = true } -- pois: бармен Отис в салуне
local list = {} -- hum -> {root, cf}

local function protect(hum)
	if list[hum] then return end
	local model = hum.Parent
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	for _, st in ipairs({ Enum.HumanoidStateType.Dead, Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Physics }) do
		hum:SetStateEnabled(st, false)
	end
	hum.MaxHealth = 1e9
	hum.Health = hum.MaxHealth
	model:SetAttribute("Invulnerable", true)
	if not model:FindFirstChildOfClass("ForceField") then
		local ff = Instance.new("ForceField")
		ff.Visible = false
		ff.Parent = model
	end
	local root = hum.RootPart or model:FindFirstChild("HumanoidRootPart")
	-- снимок суставов: если кто-то их сломает (BreakJoints) — вернём
	local joints = {}
	for _, j in ipairs(model:GetDescendants()) do
		if j:IsA("JointInstance") or j:IsA("WeldConstraint") then
			table.insert(joints, { j = j, copy = j:Clone(), parent = j.Parent })
		end
	end
	list[hum] = { root = root, cf = nil, joints = joints }
	-- запоминаем место после того, как спавнер поставил NPC
	task.delay(2, function()
		local st = list[hum]
		if st and root and root.Parent then st.cf = root.CFrame st.anch = root.Anchored end
	end)
	hum.HealthChanged:Connect(function(h)
		if h < hum.MaxHealth then hum.Health = hum.MaxHealth end
	end)
end

local function scan(container)
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("Humanoid") then protect(d) end
	end
	container.DescendantAdded:Connect(function(d)
		if d:IsA("Humanoid") then task.defer(protect, d) end
	end)
end

local function onChild(c)
	if (c:IsA("Model") or c:IsA("Folder")) and PROTECTED[string.lower(c.Name)] then
		task.defer(scan, c)
	end
end
for _, c in ipairs(Workspace:GetChildren()) do onChild(c) end
Workspace.ChildAdded:Connect(onChild)

-- страховка каждый кадр: здоровье полное, на месте (отбрасывание/притягивание не работает)
RunService.Heartbeat:Connect(function()
	for hum, st in pairs(list) do
		if not hum.Parent or not hum:IsDescendantOf(Workspace) then
			list[hum] = nil
		else
			if hum.Health < hum.MaxHealth then hum.Health = hum.MaxHealth end
			for _, rec in ipairs(st.joints) do
				if not rec.j.Parent and rec.parent.Parent then
					local nj = rec.copy:Clone()
					nj.Parent = rec.parent
					rec.j = nj
				end
			end
			local r = st.root
			if r and r.Parent and st.cf then
				if st.anch ~= nil and r.Anchored ~= st.anch then r.Anchored = st.anch end
				if (r.Position - st.cf.Position).Magnitude > 0.05 or r.AssemblyLinearVelocity.Magnitude > 2 then
					r.AssemblyLinearVelocity = Vector3.zero
					r.AssemblyAngularVelocity = Vector3.zero
					r.CFrame = st.cf
				end
			end
		end
	end
end)

print("[ProtectedNPCs] NPC магазина и скупщика бессмертны")

