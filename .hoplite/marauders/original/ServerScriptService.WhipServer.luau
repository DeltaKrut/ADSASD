-- WhipServer v2 (Script, ServerScriptService)
-- Авторитетная часть хлыста: быстрый удар / заряженный удар (раскрутка) / захлёст ПКМ,
-- урон, creator-тег, замедление и стан зомби, подтягивание захлёстом.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local W = require(ReplicatedStorage:WaitForChild("WhipService"))
local CFG = W.CFG
local okAC, AntiCheat = pcall(function()
	return require(game:GetService("ServerScriptService"):WaitForChild("AntiCheat", 5))
end)
if not okAC or type(AntiCheat) ~= "table" then AntiCheat = nil end

local folder = ReplicatedStorage:FindFirstChild("WhipRemotes") or Instance.new("Folder")
folder.Name = "WhipRemotes"
folder.Parent = ReplicatedStorage
local function remote(name)
	local r = folder:FindFirstChild(name) or Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = folder
	return r
end
local swingRemote = remote("WhipSwing")   -- C->S (aim, power)
local chargeRemote = remote("WhipCharge") -- C->S начало раскрутки
local lashRemote = remote("WhipLash")     -- C->S (aim)
local fxRemote = remote("WhipFx")         -- S->C (kind, player, ...)
local hitRemote = remote("WhipHit")       -- S->C атакующему (crack, killed)
local claimRemote = remote("WhipClaim") -- C->S (part, pos, nearTip, inCrack): попадание, которое увидел игрок
local swings = {}
for _, old in ipairs({ "WhipReplicate" }) do
	local o = folder:FindFirstChild(old)
	if o then o:Destroy() end
end

local chargeStart = {}
local lastSwing = {}
local lastLash = {}
local busy = {}

local function getTool(char)
	local t = char:FindFirstChild("Whip")
	if t and t:IsA("Tool") and t:FindFirstChild("Handle") then return t end
end

local function rate(player, key, n, win)
	if AntiCheat and AntiCheat.rate then return AntiCheat.rate(player, key, n, win) end
	return true
end
local function canAct(player)
	if AntiCheat and AntiCheat.canAct then return AntiCheat.canAct(player) end
	return true
end

local function sendOthers(except, ...)
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= except then fxRemote:FireClient(p, ...) end
	end
end

---------------------------------------------------------------- реакция цели
local slowState = {} -- hum -> { untilT, factor, base }
local function applySlow(hum, dur, factor)
	local now = os.clock()
	local st = slowState[hum]
	if st then
		st.untilT = math.max(st.untilT, now + dur)
		st.factor = math.min(st.factor, factor)
		return
	end
	slowState[hum] = { untilT = now + dur, factor = factor, base = hum.WalkSpeed }
end
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for hum, st in pairs(slowState) do
		if now >= st.untilT or not hum.Parent or hum.Health <= 0 then
			slowState[hum] = nil
			if hum.Parent then
				hum:SetAttribute("WhipStunned", nil)
				if st.base > 0 and st.forced and math.abs(hum.WalkSpeed - st.forced) < 1e-3 then hum.WalkSpeed = st.base end
			end
		else
			local forced = st.base * st.factor
			st.forced = forced
			if hum.WalkSpeed ~= forced then hum.WalkSpeed = forced end
			if st.factor == 0 then hum:SetAttribute("WhipStunned", true) end
		end
	end
end)

local function playHitAnim(hum)
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then return end
	local anim = Instance.new("Animation")
	anim.AnimationId = CFG.HitAnims[math.random(#CFG.HitAnims)]
	local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		track:Play(0.05)
	end
end

local function knock(model, dir, dist)
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 1e-3 or dist <= 0 then return end
	model:PivotTo(model:GetPivot() + flat.Unit * dist)
end

local function tag(hum, player)
	local old = hum:FindFirstChild("creator")
	if old then old:Destroy() end
	local t = Instance.new("ObjectValue")
	t.Name = "creator"
	t.Value = player
	t.Parent = hum
	Debris:AddItem(t, 4)
end

-- найти живую цель (не игрок, не труп). Возвращает model, hum, inner
local function resolveTarget(part)
	local model = W.outerModel(part)
	if not model or Players:GetPlayerFromCharacter(model) or model:GetAttribute("Corpse") then return nil end
	local hum = model:FindFirstChildWhichIsA("Humanoid", true) if hum and hum.Parent and hum.Parent:GetAttribute("Invulnerable") then hum = nil end -- NPC магазина/скупщика не бьются
	if not hum or hum.Health <= 0 then return nil end
	return model, hum, hum.Parent
end

-- уклонисты: true = удар не прошёл
local function dodged(model, inner, heavy)
	if (inner and inner:GetAttribute("Dodging")) or model:GetAttribute("Dodging") then return true end
	local dodger = (inner and inner:GetAttribute("CanDodge")) and inner or (model:GetAttribute("CanDodge") and model or nil)
	if dodger and not heavy then
		dodger:SetAttribute("DodgeReq", (dodger:GetAttribute("DodgeReq") or 0) + 1)
		return true
	end
	return false
end

---------------------------------------------------------------- удар (серверная симуляция цепи)
local function runSwing(player, char, tool, aim, power)
	local hand = tool.Handle
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local ch = W.newChain((hand.CFrame * CFG.RootOffset).Position)
	local side = aim:Cross(Vector3.yAxis)
	local dur = W.swingDuration(power)
	local ovl = OverlapParams.new()
	ovl.FilterType = Enum.RaycastFilterType.Exclude
	ovl.FilterDescendantsInstances = { char }
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	ray.FilterDescendantsInstances = { char }
	local hitSet = {}
	local t0 = os.clock()
	busy[char] = true
	-- одно попадание: и для серверной симуляции, и для проверенной заявки игрока
	local function applyHit(part, pos, normal, nearTip, inCrack, root)
		local model, hum, inner = resolveTarget(part)
		if not model or hitSet[model] then return end
		local origin = hrp and hrp.Position or root
		local flat = Vector3.new(pos.X - origin.X, 0, pos.Z - origin.Z)
		if flat.Magnitude > 0.5 and flat.Unit:Dot(aim) < CFG.FrontCone then return end
		if pos.Y - origin.Y > CFG.MaxHitHeight then return end
		hitSet[model] = true
		if dodged(model, inner, power >= 0.5) then return end
		local crack = inCrack and nearTip
		tag(hum, player)
		hum:TakeDamage(W.damage(power, crack))
		local killed = hum.Health <= 0
		if not killed then
			knock(inner or model, aim, W.lerp(CFG.KnockTap, CFG.KnockFull, power) + (crack and CFG.KnockCrack or 0))
			playHitAnim(hum)
			if crack or power >= 0.9 then
				applySlow(hum, CFG.StunTime, 0)
			else
				applySlow(hum, CFG.SlowTime, CFG.SlowFactor)
			end
		end
		hitRemote:FireClient(player, crack, killed)
		sendOthers(player, "hit", player, pos, normal, part, aim, crack)
	end
	swings[player] = { apply = applyHit, t0 = t0, dur = dur, char = char }
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		local el = os.clock() - t0
		if not tool.Parent or not char.Parent or el >= dur then
			conn:Disconnect()
			busy[char] = nil
			return
		end
		dt = math.min(dt, 1 / 30)
		local progress = math.clamp(el / dur, 0, 1)
		local eased = 1 - (1 - progress) ^ 3
		local root = (hand.CFrame * CFG.RootOffset).Position
		W.step(ch, root, dt, {
			damping = CFG.SwingDamping,
			k = 1 - math.exp(-dt * 14),
			target = function(_, frac) return W.swingTarget(root, aim, side, frac, eased, power) end,
		})
		if progress >= CFG.HitStartFrac then
			local inCrack = progress >= CFG.CrackWindow[1] and progress <= CFG.CrackWindow[2]
			W.detect(ch, ray, ovl, aim, function(part, pos, normal, nearTip)
				applyHit(part, pos, normal, nearTip, inCrack, root)
			end)
		end
		W.saveLast(ch)
	end)
end

chargeRemote.OnServerEvent:Connect(function(player)
	local char = player.Character
	if not char or not getTool(char) then return end
	if not rate(player, "whipCharge", 6, 1) then return end
	chargeStart[player] = os.clock()
	sendOthers(player, "charge", player)
end)

swingRemote.OnServerEvent:Connect(function(player, aim, power)
	local char = player.Character
	if not char or busy[char] then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	local tool = getTool(char)
	if not tool then return end
	if not canAct(player) then return end
	if typeof(aim) ~= "Vector3" then return end
	local flat = Vector3.new(aim.X, 0, aim.Z)
	if flat.Magnitude < 1e-3 then return end
	power = tonumber(power) or 0
	if power ~= power then power = 0 end
	-- заряд не больше реально накопленного
	local now = os.clock()
	local st = chargeStart[player]
	chargeStart[player] = nil
	local maxP = st and math.clamp((now - st) / CFG.ChargeTime + 0.2, 0, 1) or 0
	power = math.clamp(power, 0, maxP)
	local last = lastSwing[player]
	if last and now - last.t < last.cd * CFG.ServerCooldownTol then return end
	lastSwing[player] = { t = now, cd = W.lerp(CFG.Cooldown, CFG.CooldownCharged, power) }
	local dir = flat.Unit
	sendOthers(player, "swing", player, dir, power)
	runSwing(player, char, tool, dir, power)
end)

-- попадание, которое увидел игрок: сервер проверяет и сразу засчитывает
local function wallBetween(char, target, from, to)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { char, target }
	rp.IgnoreWater = true
	local r = Workspace:Raycast(from, to - from, rp)
	if r and r.Instance:IsA("BasePart") and r.Instance.CanCollide then
		local sz = r.Instance.Size
		return math.min(sz.X, sz.Y, sz.Z) >= 1.5
	end
	return false
end

claimRemote.OnServerEvent:Connect(function(player, part, pos, nearTip, inCrack)
	local sw = swings[player]
	if not sw then return end
	local now = os.clock()
	if now - sw.t0 > sw.dur + 0.4 then return end
	if not rate(player, "whipClaim", 12, 1) then return end
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or not part:IsDescendantOf(Workspace) then return end
	if typeof(pos) ~= "Vector3" or pos ~= pos then return end
	-- точка удара должна быть на самой цели
	if (part.Position - pos).Magnitude > part.Size.Magnitude * 0.5 + 3 then return end
	local hrp = sw.char.Parent and sw.char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	-- не дальше длины кнута + запас на пинг
	if (pos - hrp.Position).Magnitude > CFG.Segments * CFG.SegmentLength + 5 then return end
	local model = W.outerModel(part)
	if not model or wallBetween(sw.char, model, hrp.Position, pos) then return end
	-- щелчок засчитываем, только если по времени удар действительно был в окне щелчка
	local ping = math.clamp(player:GetNetworkPing(), 0, 0.3)
	local frac = (now - ping - sw.t0) / sw.dur
	local crackOk = inCrack == true and frac >= CFG.CrackWindow[1] - 0.15 and frac <= CFG.CrackWindow[2] + 0.15
	sw.apply(part, pos, -(pos - hrp.Position).Unit, nearTip == true, crackOk, hrp.Position)
end)

Players.PlayerRemoving:Connect(function(p) swings[p] = nil end)

---------------------------------------------------------------- захлёст (ПКМ)
local function pull(model, hum, char)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local t0 = os.clock()
	applySlow(hum, CFG.PullTime + CFG.LashStun, 0)
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not model.Parent or hum.Health <= 0 or not hrp.Parent or os.clock() - t0 > CFG.PullTime then
			conn:Disconnect()
			return
		end
		local piv = model:GetPivot()
		local to = hrp.Position - piv.Position
		local flat = Vector3.new(to.X, 0, to.Z)
		local d = flat.Magnitude
		if d <= CFG.PullStop then
			conn:Disconnect()
			return
		end
		model:PivotTo(piv + flat.Unit * math.min(d - CFG.PullStop, CFG.PullSpeed * dt))
	end)
	playHitAnim(hum)
end

lashRemote.OnServerEvent:Connect(function(player, aim)
	local char = player.Character
	if not char or busy[char] then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or hum.Health <= 0 or not hrp then return end
	local tool = getTool(char)
	if not tool then return end
	if not canAct(player) then return end
	if typeof(aim) ~= "Vector3" then return end
	local flat = Vector3.new(aim.X, 0, aim.Z)
	if flat.Magnitude < 1e-3 then return end
	local now = os.clock()
	if lastLash[player] and now - lastLash[player] < CFG.LashCooldown * 0.85 then return end
	lastLash[player] = now
	local dir = flat.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local origin = hrp.Position - Vector3.new(0, 0.8, 0)
	local r = Workspace:Spherecast(origin, CFG.LashRadius, dir * CFG.LashRange, params)
	local model, thum, inner
	if r then model, thum, inner = resolveTarget(r.Instance) end
	if model and dodged(model, inner, false) then model = nil end
	if not model then
		fxRemote:FireAllClients("lash", player, dir, nil)
		return
	end
	fxRemote:FireAllClients("lash", player, dir, r.Instance)
	tag(thum, player)
	thum:TakeDamage(CFG.LashDamage)
	local killed = thum.Health <= 0
	hitRemote:FireClient(player, false, killed, true)
	if not killed then
		task.delay(CFG.LashTravel, pull, inner or model, thum, char) -- двигаем модель с Humanoid (PivotTo внешней обёртки у зомби не срабатывает)
	end
end)

Players.PlayerRemoving:Connect(function(p)
	chargeStart[p] = nil
	lastSwing[p] = nil
	lastLash[p] = nil
end)

print("[WhipServer v2] быстрый удар + раскрутка + захлёст")

