-- TownNPCAnimator: проигрывает анимации у NPC с атрибутом NPCAnim (сервер, реплицируется всем)
local function setup(m)
	if not m:IsA("Model") then return end
	local id = m:GetAttribute("NPCAnim")
	if not id or m:GetAttribute("NPCAnimOn") then return end
	local hum = m:FindFirstChildOfClass("Humanoid") or m:WaitForChild("Humanoid", 5)
	if not hum then return end
	m:SetAttribute("NPCAnimOn", true)
	-- если корень закреплён (NPC стоит/сидит на месте) — снимаем закрепление с рук/ног/головы, иначе анимация не двигает их
	local hrp = m:FindFirstChild("HumanoidRootPart")
	if hrp and hrp.Anchored then
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") and p ~= hrp then p.Anchored = false end
		end
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then animator = Instance.new("Animator") animator.Parent = hum end
	local a = Instance.new("Animation") a.AnimationId = id
	local ok, tr = pcall(function() return animator:LoadAnimation(a) end)
	if ok and tr then
		tr.Looped = true
		tr.Priority = Enum.AnimationPriority.Idle
		tr:Play(0.2, 1, 0.9 + math.random() * 0.2)
		m:SetAttribute("NPCTrack", id)
		-- жест (NPCAnim2): время от времени поверх анимации покоя
		local g = m:GetAttribute("NPCAnim2")
		if g then
			local a2 = Instance.new("Animation") a2.AnimationId = g
			local ok2, tr2 = pcall(function() return animator:LoadAnimation(a2) end)
			if ok2 and tr2 then
				tr2.Looped = false
				tr2.Priority = Enum.AnimationPriority.Action
				task.spawn(function()
					while m.Parent do
						task.wait(8 + math.random() * 10)
						if m.Parent then tr2:Play(0.3) end
					end
				end)
			end
		end
	end
end
for _, d in ipairs(workspace:GetDescendants()) do if d:IsA("Model") and d:GetAttribute("NPCAnim") then task.spawn(setup, d) end end
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") and d:GetAttribute("NPCAnim") then task.defer(setup, d) end
end)

-- поворот головы (осматривается) у NPC с атрибутом NPCLook; работает поверх анимаций
local TweenService = game:GetService("TweenService")
local function setupLook(m)
	if not m:IsA("Model") or not m:GetAttribute("NPCLook") or m:GetAttribute("NPCLookOn") then return end
	local torso = m:FindFirstChild("Torso") or m:WaitForChild("Torso", 5)
	local neck = torso and torso:FindFirstChild("Neck")
	if not neck or not neck:IsA("Motor6D") then return end
	m:SetAttribute("NPCLookOn", true)
	local base = neck.C0
	task.spawn(function()
		while m.Parent do
			task.wait(3 + math.random() * 5)
			if not m.Parent then break end
			local yaw = math.rad(math.random(-40, 40))
			local tilt = math.rad(math.random(-8, 8))
			local t = TweenService:Create(neck, TweenInfo.new(0.8 + math.random() * 0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ C0 = base * CFrame.Angles(tilt, 0, yaw) })
			t:Play()
			task.wait(1.5 + math.random() * 2)
			if not m.Parent then break end
			TweenService:Create(neck, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { C0 = base }):Play()
		end
	end)
end
for _, d in ipairs(workspace:GetDescendants()) do if d:IsA("Model") and d:GetAttribute("NPCLook") then task.spawn(setupLook, d) end end
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") then task.defer(function() if d:GetAttribute("NPCLook") then setupLook(d) end end) end
end)

print("[TownNPCAnimator] загружен")

