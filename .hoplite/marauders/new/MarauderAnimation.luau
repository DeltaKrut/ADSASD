local RunService = game:GetService("RunService")
local Proc = require(game:GetService("ReplicatedStorage"):WaitForChild("ProcAnim"))
local tracked = {}
local function track(model)
	if model:IsA("Model") and model:GetAttribute("Marauder") and not tracked[model] then
		local joints = Proc.getJoints(model)
		if Proc.valid(joints) then tracked[model] = joints end
	end
end
for _, d in ipairs(workspace:GetDescendants()) do track(d) end
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") then task.defer(track, d)
	elseif d:IsA("Motor6D") and d.Part1 then task.defer(track, d.Part1.Parent) end
end)
RunService.PreSimulation:Connect(function()
	local now = workspace:GetServerTimeNow()
	for model, joints in pairs(tracked) do
		local hum, root = model:FindFirstChildOfClass("Humanoid"), model:FindFirstChild("HumanoidRootPart")
		if not model:IsDescendantOf(workspace) or not hum or hum.Health <= 0 or not root or not Proc.valid(joints) then
			Proc.reset(joints)
			tracked[model] = nil
			continue
		end
		local state = model:GetAttribute("MarauderState")
		local speed = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
		local moving = math.clamp(speed / 10, 0, 1)
		local stride = math.sin(now * 10 + (model:GetAttribute("MarauderIndex") or 0)) * moving
		local side = math.clamp(root.CFrame:VectorToObjectSpace(root.AssemblyLinearVelocity).X / 13, -1, 1)
		local recoil = math.max(0, 1 - (now - (model:GetAttribute("MarauderShotAt") or 0)) / 0.24)
		local pose = {
			Torso = {-5 * moving, 0, -side * 7, 0, math.abs(stride) * 0.06, 0},
			Head = {3, -side * 8, 0},
			["Right Arm"] = {25 - stride * 12, 0, -5},
			["Left Arm"] = {-stride * 22, 0, 4},
			["Right Leg"] = {stride * 30, 0, side * 9},
			["Left Leg"] = {-stride * 30, 0, side * 9},
		}
		if state == "Strafe" or state == "Chase" then
			pose["Right Arm"] = {90 + recoil * 24, -5, -7, 0, recoil * 0.05, recoil * 0.1}
			pose["Left Arm"] = {69 + recoil * 12, 27, 25}
			pose.Torso[1] = -6 - recoil * 5
		elseif state == "Reload" then
			local elapsed = now - (model:GetAttribute("MarauderReloadAt") or now)
			local u = math.clamp(elapsed / (model:GetAttribute("MarauderReloadDuration") or 3.2), 0, 1)
			local open = Proc.smooth(0, 0.18, u) * (1 - Proc.smooth(0.83, 1, u))
			local insert = math.sin(elapsed * 17) * 9 * open
			pose["Right Arm"] = {70, -32 * open, -38 * open}
			pose["Left Arm"] = {48 + open * 27 + insert, 38 * open, 22 * open}
			pose.Head = {-16 * open, -17 * open, 0}
			pose.Torso = {-3, -12 * open, -3, 0, 0, 0}
		end
		Proc.apply(joints, pose)
	end
end)
