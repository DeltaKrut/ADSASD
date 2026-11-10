-- QuestClient: диалоги с NPC (E), журнал заданий (J) в стиле бестиария, трекер и уведомления.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local folder = RS:WaitForChild("QuestSystem")
local Q = require(folder:WaitForChild("QuestData"))
local remote = folder:WaitForChild("QuestRemote")

local PAPER = "rbxassetid://543883269"
local C_PAPER = Color3.fromRGB(222, 203, 168)
local C_ROW = Color3.fromRGB(206, 184, 146)
local C_LEATHER = Color3.fromRGB(120, 82, 44)
local C_EDGE = Color3.fromRGB(150, 115, 70)
local C_EDGE2 = Color3.fromRGB(140, 105, 62)
local C_INK = Color3.fromRGB(60, 40, 20)
local C_INK2 = Color3.fromRGB(70, 50, 30)
local C_GOLD = Color3.fromRGB(230, 200, 120)
local C_GREEN = Color3.fromRGB(60, 110, 40)
local C_RED = Color3.fromRGB(160, 30, 25)

-- ===== язык =====
local lang = "en"
pcall(function()
	local id = string.lower(game:GetService("LocalizationService").SystemLocaleId or "en")
	local two = string.sub(id, 1, 2)
	for _, l in ipairs(Q.LANGS) do if l == two then lang = l end end
end)
local function T(k) return Q.text(k, lang) end

local state = {}   -- [qid] = {state, prog}
local dailyDefs, offers = {}, {}
local function getDef(qid) return Q.QUESTS[qid] or dailyDefs[qid] end
local worldRemote = folder:WaitForChild("WorldRemote", 10)

-- ===== утилиты GUI =====
local function new(cls, props, parent)
	local o = Instance.new(cls)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function corner(o, r) new("UICorner", {CornerRadius = UDim.new(0, r or 8)}, o) end
local function stroke(o, col, th) new("UIStroke", {Color = col, Thickness = th or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, o) end
local function paper(props, parent)
	local p = new("ImageLabel", {Image = PAPER, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(20, 20, 512, 512),
		BackgroundColor3 = C_PAPER, BorderSizePixel = 0}, parent)
	for k, v in pairs(props) do p[k] = v end
	corner(p, 10)
	return p
end
local function spine(parent)
	local s = new("Frame", {Size = UDim2.new(0, 26, 1, 0), BackgroundColor3 = C_LEATHER, BorderSizePixel = 0, ZIndex = 2}, parent)
	corner(s, 10)
	for _, y in ipairs({0.15, 0.5, 0.85}) do
		local st = new("Frame", {Size = UDim2.fromOffset(8, 8), Position = UDim2.new(0.5, -4, y, -4), BackgroundColor3 = Color3.fromRGB(210, 180, 120), BorderSizePixel = 0, ZIndex = 3}, s)
		corner(st, 99)
	end
	return s
end
local function label(props, parent)
	local l = new("TextLabel", {BackgroundTransparency = 1, Font = Enum.Font.Garamond, TextColor3 = C_INK, TextScaled = false,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true}, parent)
	for k, v in pairs(props) do l[k] = v end
	return l
end
local function guiOpen(delta)
	player:SetAttribute("GuiOpen", math.max(0, (player:GetAttribute("GuiOpen") or 0) + delta))
end

local function rewardText(r)
	local parts = {}
	if r.money then table.insert(parts, r.money .. "$") end
	if r.bandage then table.insert(parts, T("rw_bandage") .. " ×" .. r.bandage) end
	if r.shells then table.insert(parts, T("rw_shells") .. " ×" .. r.shells) end
	if r.title then table.insert(parts, T("rw_title")) end
	if r.tools then
		for _, name in ipairs(r.tools) do table.insert(parts, T("rw_tool_" .. name)) end
	end
	if r.item and Q.ITEMS and Q.ITEMS[r.item] then table.insert(parts, T(Q.ITEMS[r.item].label)) end
	return table.concat(parts, ", ")
end
local function npcName(id) return Q.NPCS[id] and Q.NPCS[id].name or id end
local function qTitle(qid)
	local d = dailyDefs[qid]
	if d then return T("ui_daily") .. ": " .. npcName(d.npc) end
	return T(qid .. "_title")
end
local function qDesc(qid)
	local d = dailyDefs[qid]
	if d then
		local t = {}
		for _, g in ipairs(d.goals) do table.insert(t, T(g.label) .. " ×" .. g.count) end
		return T("daily_offer") .. " " .. table.concat(t, ", ")
	end
	return T(qid .. "_desc")
end
local function allOrder()
	local out = table.clone(Q.ORDER)
	local ds = {}
	for qid in pairs(state) do if dailyDefs[qid] then table.insert(ds, qid) end end
	table.sort(ds)
	for _, q in ipairs(ds) do table.insert(out, q) end
	return out
end

-- ===== NPC: реестр, промпты, портреты =====
local npcModels, portraitCache = {}, {}
local function rootOf(m) return m and (m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Torso") or m.PrimaryPart) end

local function makePortraitClone(m)
	local ok, c = pcall(function()
		local old = m.Archivable
		m.Archivable = true
		local cl = m:Clone()
		m.Archivable = old
		return cl
	end)
	if not ok or not c then return nil end
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("ProximityPrompt") or d:IsA("BillboardGui") or d:IsA("Light") or d:IsA("ParticleEmitter") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local h = c:FindFirstChildOfClass("Humanoid")
	if h then h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end
	return c
end

local function fillPortrait(vp, npcId)
	vp:ClearAllChildren()
	local src = portraitCache[npcId]
	if not src then
		local l = label({Size = UDim2.fromScale(1, 1), Text = string.sub(npcName(npcId), 1, 1), TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, TextColor3 = C_LEATHER}, vp)
		return
	end
	local wm = new("WorldModel", {}, vp)
	local c = src:Clone()
	c.Parent = wm
	local head = c:FindFirstChild("Head")
	local root = rootOf(c)
	local cam = new("Camera", {FieldOfView = 40}, vp)
	vp.CurrentCamera = cam
	if head then
		local fwd = root and root.CFrame.LookVector or head.CFrame.LookVector
		fwd = Vector3.new(fwd.X, 0, fwd.Z)
		if fwd.Magnitude < 0.1 then fwd = Vector3.new(0, 0, -1) end
		fwd = fwd.Unit
		local target = head.Position - Vector3.new(0, 0.45, 0)
		cam.CFrame = CFrame.lookAt(target + fwd * 4.6 + Vector3.new(0, 0.35, 0), target)
	end
end

local openDialog -- forward

local function setupNPC(m)
	local id = m:GetAttribute("NPCId")
	if not id or not Q.NPCS[id] then return end
	task.spawn(function()
		local root = m:WaitForChild("HumanoidRootPart", 15) or m:FindFirstChild("Torso")
		if not root then return end
		npcModels[id] = m
		task.delay(1, function()
			if m.Parent and not portraitCache[id] then portraitCache[id] = makePortraitClone(m) end
		end)
		if root:FindFirstChild("QuestTalkPrompt") then return end
		local pr = new("ProximityPrompt", {
			Name = "QuestTalkPrompt", ActionText = T("ui_talk"), ObjectText = npcName(id),
			KeyboardKeyCode = Enum.KeyCode.E, HoldDuration = 0, MaxActivationDistance = 10,
			RequiresLineOfSight = false, Style = Enum.ProximityPromptStyle.Default,
		}, root)
		pr.Triggered:Connect(function() openDialog(id) end)
	end)
end
for _, d in ipairs(Workspace:GetDescendants()) do
	if d:IsA("Model") and d:GetAttribute("NPCId") then setupNPC(d) end
end
Workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") then
		task.defer(function() if d:GetAttribute("NPCId") then setupNPC(d) end end)
	end
end)

-- =====================================================================
-- ДИАЛОГ
-- =====================================================================
local dgui = new("ScreenGui", {Name = "QuestDialogGui", ResetOnSpawn = false, IgnoreGuiInset = true, Enabled = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 20}, playerGui)
local DLG_OPEN = UDim2.new(0.5, 0, 1, -24)
local DLG_HIDE = UDim2.new(0.5, 0, 1, 320)
local dpanel = paper({Name = "Panel", AnchorPoint = Vector2.new(0.5, 1), Position = DLG_HIDE, Size = UDim2.fromOffset(700, 250), ClipsDescendants = true}, dgui)
spine(dpanel)
local dframe = new("Frame", {Size = UDim2.new(1, -50, 1, -24), Position = UDim2.new(0, 38, 0, 12), BackgroundTransparency = 1}, dpanel)
stroke(dframe, C_EDGE, 1.5)
corner(dframe, 6)
local vpBox = new("ViewportFrame", {Size = UDim2.fromOffset(160, 160), Position = UDim2.fromOffset(14, 14), BackgroundColor3 = Color3.fromRGB(180, 160, 125),
	Ambient = Color3.fromRGB(200, 190, 170), LightColor = Color3.fromRGB(255, 240, 210), LightDirection = Vector3.new(-1, -1, -1)}, dframe)
corner(vpBox, 6)
stroke(vpBox, C_EDGE2, 2)
local dName = label({Size = UDim2.new(1, -200, 0, 30), Position = UDim2.fromOffset(190, 10), TextSize = 28, Font = Enum.Font.Garamond, Text = ""}, dframe)
local dRole = label({Size = UDim2.fromOffset(160, 20), Position = UDim2.fromOffset(14, 180), TextSize = 16, TextColor3 = Color3.fromRGB(95, 68, 38),
	TextXAlignment = Enum.TextXAlignment.Center, Text = T("ui_dlghint")}, dframe)
new("Frame", {Size = UDim2.new(1, -205, 0, 2), Position = UDim2.fromOffset(190, 44), BackgroundColor3 = C_EDGE, BorderSizePixel = 0}, dframe)
local dText = label({Size = UDim2.new(1, -205, 0, 86), Position = UDim2.fromOffset(190, 52), TextSize = 22, TextColor3 = C_INK2, Text = ""}, dframe)
local dOpts = new("Frame", {Size = UDim2.new(1, -205, 0, 64), Position = UDim2.new(0, 190, 1, -72), BackgroundTransparency = 1}, dframe)
new("UIGridLayout", {CellSize = UDim2.new(0.5, -6, 0, 28), CellPadding = UDim2.fromOffset(8, 6), SortOrder = Enum.SortOrder.LayoutOrder}, dOpts)
local skipBtn = new("TextButton", {Size = UDim2.new(1, -205, 0, 90), Position = UDim2.fromOffset(190, 52), BackgroundTransparency = 1, Text = "", ZIndex = 5}, dframe)

local voice = new("Sound", {Name = "QuestVoice", SoundId = Q.VOICE, Volume = 0.55}, dgui)

local dlg = { open = false, npc = nil, gen = 0, typing = false, full = "", options = {} }

local function closeDialog()
	if not dlg.open then return end
	dlg.open = false
	dlg.gen += 1
	voice:Stop()
	guiOpen(-1)
	TweenService:Create(dpanel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Position = DLG_HIDE}):Play()
	task.delay(0.26, function() if not dlg.open then dgui.Enabled = false end end)
end

local function setOptions(list)
	for _, c in ipairs(dOpts:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
	dlg.options = list
	for i, o in ipairs(list) do
		local b = new("TextButton", {LayoutOrder = i, BackgroundColor3 = C_ROW, AutoButtonColor = true, Font = Enum.Font.Garamond, TextSize = 19,
			TextColor3 = C_INK, Text = i .. ". " .. o.text, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd}, dOpts)
		new("UIPadding", {PaddingLeft = UDim.new(0, 8)}, b)
		corner(b, 5)
		stroke(b, C_EDGE2, 1.5)
		b.Visible = not dlg.typing
		b.MouseButton1Click:Connect(function() if not dlg.typing then o.fn() end end)
	end
end
local function showOptions(v)
	for _, c in ipairs(dOpts:GetChildren()) do if c:IsA("TextButton") then c.Visible = v end end
end

-- печать по словам + звук на каждое слово
local function say(text, options)
	dlg.gen += 1
	local g = dlg.gen
	dlg.full = text
	dlg.typing = true
	dText.Text = ""
	setOptions(options)
	showOptions(false)
	local pitch = (Q.NPCS[dlg.npc] and Q.NPCS[dlg.npc].pitch) or 1
	task.spawn(function()
		local words = {}
		for w in string.gmatch(text, "%S+") do table.insert(words, w) end
		local cjk = #words <= 1 and utf8.len(text) and utf8.len(text) > 8
		if cjk then -- в китайском/японском нет пробелов: «слово» = 3 символа
			words = {}
			local buf, n = "", 0
			for _, cp in utf8.codes(text) do
				buf ..= utf8.char(cp); n += 1
				if n >= 3 then table.insert(words, buf) buf, n = "", 0 end
			end
			if buf ~= "" then table.insert(words, buf) end
		end
		local shown = ""
		for i, w in ipairs(words) do
			if g ~= dlg.gen or not dlg.typing then return end
			shown = (i == 1 or cjk) and (shown .. w) or (shown .. " " .. w)
			dText.Text = shown
			if i % 2 == 1 then -- звук раз в 2 слова
				voice.PlaybackSpeed = pitch * (0.92 + math.random() * 0.16)
				voice.TimePosition = 0
				voice:Play()
			end
			task.wait(0.11 + math.min(utf8.len(w) or 3, 10) * 0.012)
		end
		if g == dlg.gen then
			voice:Stop()
			dText.Text = text
			dlg.typing = false
			showOptions(true)
		end
	end)
end
skipBtn.MouseButton1Click:Connect(function()
	if dlg.typing then
		dlg.typing = false
		voice:Stop()
		dText.Text = dlg.full
		showOptions(true)
	end
end)

local mainMenu -- forward
local function currentQuest(npcId)
	for _, qid in ipairs(Q.NPCS[npcId].quests) do
		local st = state[qid]
		if not st or st.state ~= "done" then return qid, st end
	end
	return nil
end
local function progressLines(qid)
	local st = state[qid]
	local out = {}
	for i, g in ipairs(getDef(qid).goals) do
		local n = st and st.prog and (st.prog[i] or st.prog[tostring(i)]) or 0
		table.insert(out, T(g.label) .. ": " .. n .. "/" .. g.count)
	end
	return table.concat(out, "\n")
end

local function workMenu()
	local id = dlg.npc
	local qid, st = currentQuest(id)
	local back = {text = T("ui_back"), fn = function() mainMenu(false) end}
	local bye = {text = T("ui_bye"), fn = closeDialog}
	if not qid then
		say(T("ui_alldone"), {back, bye})
	elseif not st then
		local def = getDef(qid)
		say(T(qid .. "_offer") .. "\n[" .. T("diff_" .. def.diff) .. "]  " .. T("ui_reward") .. ": " .. rewardText(def.reward), {
			{text = T("ui_accept"), fn = function()
				remote:FireServer("accept", qid)
				closeDialog()
			end},
			{text = T("ui_decline"), fn = function() mainMenu(false) end},
		})
	elseif st.state == "ready" then
		remote:FireServer("turnin", qid)
		say(T(qid .. "_done") .. "  (+" .. rewardText(getDef(qid).reward) .. ")", {back, bye})
	else
		say(T(qid .. "_wait") .. "\n" .. progressLines(qid), {back, bye})
	end
end

local function dailyMenu()
	local id = dlg.npc
	local qid = offers[id]
	local def = qid and getDef(qid)
	local back = {text = T("ui_back"), fn = function() mainMenu(false) end}
	local bye = {text = T("ui_bye"), fn = closeDialog}
	if not def then mainMenu(false) return end
	local st = state[qid]
	if not st then
		local t = {}
		for _, g in ipairs(def.goals) do table.insert(t, T(g.label) .. " ×" .. g.count) end
		say(T("daily_offer") .. "\n" .. table.concat(t, ", ") .. "\n" .. T("ui_reward") .. ": " .. rewardText(def.reward), {
			{text = T("ui_accept"), fn = function() remote:FireServer("accept", qid) closeDialog() end},
			{text = T("ui_decline"), fn = function() mainMenu(false) end},
		})
	elseif st.state == "ready" then
		remote:FireServer("turnin", qid)
		say(T("daily_done") .. "  (+" .. rewardText(def.reward) .. ")", {back, bye})
	else
		say(T("daily_wait") .. "\n" .. progressLines(qid), {back, bye})
	end
end

-- ===== торговля (караван) =====
local stock = {}
local tradeMenu
local function tradeOptions()
	local opts = {}
	for i = 1, math.min(3, #stock) do
		local key = stock[i]
		local it = Q.TRADE[key]
		if it then
			table.insert(opts, {text = T(it.label) .. " — " .. it.price .. "$", fn = function()
				if worldRemote then worldRemote:FireServer("buy", key) end
			end})
		end
	end
	table.insert(opts, {text = T("ui_back"), fn = function() mainMenu(false) end})
	return opts
end
function tradeMenu(text)
	say(text or T("trade_intro"), tradeOptions())
end
if worldRemote then
	worldRemote.OnClientEvent:Connect(function(kind, a, b)
		if kind == "stock" then
			stock = type(a) == "table" and a or {}
		elseif kind == "buy" then
			if dlg.open and dlg.npc == "merchant" then
				if a then tradeMenu(T("trade_bought"))
				elseif b == "money" then tradeMenu(T("trade_nomoney"))
				else tradeMenu(T("trade_sold")) end
			end
		end
	end)
	task.defer(function() worldRemote:FireServer("getstock") end)
end

function mainMenu(greet)
	local id = dlg.npc
	local key = Q.NPC_TEXT[id]
	local opts = {}
	if Q.NPCS[id] and Q.NPCS[id].trader then
		if worldRemote then worldRemote:FireServer("getstock") end
		table.insert(opts, {text = T("ui_trade"), fn = function() tradeMenu() end})
		table.insert(opts, {text = T("ui_about"), fn = function()
			say(T(key .. "_about"), {{text = T("ui_back"), fn = function() mainMenu(false) end}, {text = T("ui_bye"), fn = closeDialog}})
		end})
		table.insert(opts, {text = T("ui_bye"), fn = closeDialog})
		say(greet and T(key .. "_greet") or "...", opts)
		return
	end
	local dq = offers[id]
	local dst = dq and state[dq]
	if dq and getDef(dq) and not (dst and dst.state == "done") then
		table.insert(opts, {text = "☀ " .. T("ui_daily") .. ((dst and dst.state == "ready") and " ✓" or ""), fn = dailyMenu})
	end
	local qid, st = currentQuest(id)
	if qid and st and st.state == "ready" then
		table.insert(opts, {text = T("ui_turnin"), fn = workMenu})
	elseif qid and st then
		table.insert(opts, {text = T("ui_progress"), fn = workMenu})
	else
		table.insert(opts, {text = T("ui_work"), fn = workMenu})
	end
	table.insert(opts, {text = T("ui_about"), fn = function()
		say(T(key .. "_about"), {{text = T("ui_back"), fn = function() mainMenu(false) end}, {text = T("ui_bye"), fn = closeDialog}})
	end})
	-- особая реплика: Джессика ищет Веронику
	local js = state.jess_friend
	if id == "ver" and js and js.state == "active" then
		table.insert(opts, 1, {text = T("v_jess_opt"), fn = function()
			remote:FireServer("talk", "ver")
			say(T("v_jess_rep"), {{text = T("ui_back"), fn = function() mainMenu(false) end}, {text = T("ui_bye"), fn = closeDialog}})
		end})
	end
	table.insert(opts, {text = T("ui_bye"), fn = closeDialog})
	say(greet and T(key .. "_greet") or "...", opts)
end

function openDialog(id)
	if dlg.open and dlg.npc == id then return end
	if player:GetAttribute("Dead") then return end
	if not dlg.open then guiOpen(1) end
	dlg.open = true
	dlg.npc = id
	dName.Text = npcName(id)
	if not portraitCache[id] and npcModels[id] then portraitCache[id] = makePortraitClone(npcModels[id]) end
	fillPortrait(vpBox, id)
	dgui.Enabled = true
	TweenService:Create(dpanel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = DLG_OPEN}):Play()
	mainMenu(true)
end

-- закрыть, если отошёл
RunService.Heartbeat:Connect(function()
	if not dlg.open then return end
	local m = npcModels[dlg.npc]
	local r = rootOf(m)
	local c = player.Character
	local pr = c and c:FindFirstChild("HumanoidRootPart")
	if not r or not pr or (r.Position - pr.Position).Magnitude > 16 or player:GetAttribute("Dead") then closeDialog() end
end)

-- =====================================================================
-- ЖУРНАЛ (J)
-- =====================================================================
local bgui = new("ScreenGui", {Name = "QuestButtonGui", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, playerGui)
local jBtn = new("TextButton", {Name = "JournalButton", Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(86, 20), BackgroundColor3 = C_PAPER,
	Text = "", AutoButtonColor = true}, bgui)
corner(jBtn, 10)
stroke(jBtn, C_EDGE, 3)
local cover = new("Frame", {Size = UDim2.fromOffset(34, 40), Position = UDim2.new(0.5, -17, 0.5, -20), BackgroundColor3 = C_LEATHER, BorderSizePixel = 0}, jBtn)
corner(cover, 4)
new("Frame", {Size = UDim2.new(0, 6, 1, 0), BackgroundColor3 = Color3.fromRGB(85, 58, 30), BorderSizePixel = 0}, cover)
new("Frame", {Size = UDim2.new(0, 4, 1, -8), Position = UDim2.new(1, -5, 0, 4), BackgroundColor3 = Color3.fromRGB(238, 228, 202), BorderSizePixel = 0}, cover)
label({Size = UDim2.new(1, -6, 1, 0), Position = UDim2.fromOffset(4, 0), Text = "★", TextColor3 = C_GOLD, TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, Font = Enum.Font.GothamBold}, cover)
local badge = new("TextLabel", {Size = UDim2.fromOffset(22, 22), Position = UDim2.new(1, -14, 0, -8), BackgroundColor3 = C_RED, TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.GothamBold, TextSize = 14, Text = "!", Visible = false, ZIndex = 3}, jBtn)
corner(badge, 99)
local jKey = label({Size = UDim2.fromOffset(56, 16), Position = UDim2.new(0, 0, 1, 2), Text = "J", TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = Color3.fromRGB(240, 225, 190), TextStrokeTransparency = 0.4}, jBtn)

local jgui = new("ScreenGui", {Name = "QuestJournalGui", ResetOnSpawn = false, IgnoreGuiInset = true, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 15}, playerGui)
local dim = new("TextButton", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5, Text = "", AutoButtonColor = false}, jgui)
local J_OPEN, J_HIDE = UDim2.fromScale(0.5, 0.5), UDim2.new(0.5, 0, 1.4, 0)
local jpanel = paper({AnchorPoint = Vector2.new(0.5, 0.5), Position = J_HIDE, Size = UDim2.fromOffset(600, 440), ClipsDescendants = true}, jgui)
spine(jpanel)
local jpage = new("Frame", {Size = UDim2.new(1, -60, 1, -30), Position = UDim2.new(0, 42, 0, 15), BackgroundTransparency = 1}, jpanel)
stroke(jpage, C_EDGE, 1.5)
corner(jpage, 6)
label({Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(10, 6), Text = T("ui_journal"), TextSize = 34, TextXAlignment = Enum.TextXAlignment.Center}, jpage)
new("Frame", {Size = UDim2.new(1, -60, 0, 2), Position = UDim2.fromOffset(30, 48), BackgroundColor3 = C_EDGE, BorderSizePixel = 0}, jpage)
local tab = "active"
local tabA = new("TextButton", {Size = UDim2.fromOffset(150, 26), Position = UDim2.new(0.5, -155, 0, 56), Font = Enum.Font.Garamond, TextSize = 20, TextColor3 = C_INK, Text = T("ui_active")}, jpage)
local tabD = new("TextButton", {Size = UDim2.fromOffset(150, 26), Position = UDim2.new(0.5, 5, 0, 56), Font = Enum.Font.Garamond, TextSize = 20, TextColor3 = C_INK, Text = T("ui_completed")}, jpage)
for _, b in ipairs({tabA, tabD}) do corner(b, 5) stroke(b, C_EDGE2, 1.5) end
local list = new("ScrollingFrame", {Size = UDim2.new(1, -30, 1, -128), Position = UDim2.fromOffset(15, 90), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 6, ScrollBarImageColor3 = C_EDGE, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y}, jpage)
new("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, list)
label({Size = UDim2.new(1, -20, 0, 20), Position = UDim2.new(0, 10, 1, -28), Text = T("ui_hint"), TextSize = 16, TextColor3 = Color3.fromRGB(95, 68, 38),
	TextXAlignment = Enum.TextXAlignment.Center}, jpage)

local jOpen = false
local function buildRow(qid, order)
	local def, st = getDef(qid), state[qid]
	local done = st.state == "done"
	local row = new("Frame", {LayoutOrder = order, Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C_ROW, BorderSizePixel = 0}, list)
	corner(row, 6)
	stroke(row, C_EDGE2, 1.5)
	new("UISizeConstraint", {MinSize = Vector2.new(0, 120)}, row)
	local vp = new("ViewportFrame", {Size = UDim2.fromOffset(96, 96), Position = UDim2.fromOffset(10, 12), BackgroundColor3 = Color3.fromRGB(180, 160, 125),
		Ambient = Color3.fromRGB(200, 190, 170), LightColor = Color3.fromRGB(255, 240, 210)}, row)
	corner(vp, 6)
	fillPortrait(vp, def.npc)
	local body = new("Frame", {Size = UDim2.new(1, -126, 0, 0), Position = UDim2.fromOffset(118, 8), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1}, row)
	new("UIListLayout", {Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder}, body)
	new("UIPadding", {PaddingBottom = UDim.new(0, 8)}, body)
	local function line(text, size, col, ord)
		return label({LayoutOrder = ord, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = text, TextSize = size, TextColor3 = col or C_INK}, body)
	end
	line(qTitle(qid), 24, Color3.fromRGB(50, 32, 16), 1)
	local dc = def.diff == "hard" and C_RED or (def.diff == "medium" and Color3.fromRGB(150, 95, 20) or C_GREEN)
	local l2 = line(T("ui_from") .. ": " .. npcName(def.npc) .. "   •   " .. T("diff_" .. def.diff), 16, Color3.fromRGB(95, 68, 38), 2)
	line(qDesc(qid), 17, C_INK2, 3)
	for i, g in ipairs(def.goals) do
		local n = st.prog and (st.prog[i] or st.prog[tostring(i)]) or 0
		local ok = done or n >= g.count
		line((ok and "☑ " or "☐ ") .. T(g.label) .. "  " .. math.min(n, g.count) .. "/" .. g.count .. (done and "" or ""), 17, ok and C_GREEN or C_INK, 3 + i)
	end
	if st.state == "ready" then line("➜ " .. T("ui_qready") .. " " .. npcName(def.npc), 17, C_GREEN, 20) end
	line(T("ui_reward") .. ": " .. rewardText(def.reward), 17, Color3.fromRGB(120, 82, 44), 21)
	local _ = dc
	if done then
		local stamp = new("TextLabel", {Size = UDim2.fromOffset(150, 40), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -90, 0, 40), Rotation = -14,
			BackgroundTransparency = 1, Font = Enum.Font.Garamond, TextSize = 28, Text = T("ui_stamp"), TextColor3 = C_RED, TextTransparency = 0.15, ZIndex = 4}, row)
		stroke(stamp, C_RED, 3)
	elseif st.state == "active" then
		local cb = new("TextButton", {Size = UDim2.fromOffset(90, 22), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), BackgroundColor3 = Color3.fromRGB(190, 160, 120),
			Font = Enum.Font.Garamond, TextSize = 15, TextColor3 = C_RED, Text = T("ui_cancel"), ZIndex = 4}, row)
		corner(cb, 4)
		stroke(cb, C_EDGE2, 1)
		cb.MouseButton1Click:Connect(function() remote:FireServer("abandon", qid) end)
	end
end

local function refreshJournal()
	tabA.BackgroundColor3 = tab == "active" and Color3.fromRGB(190, 160, 120) or C_ROW
	tabD.BackgroundColor3 = tab == "done" and Color3.fromRGB(190, 160, 120) or C_ROW
	for _, c in ipairs(list:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
	local n = 0
	for i, qid in ipairs(allOrder()) do
		local st = state[qid]
		if st and ((tab == "done") == (st.state == "done")) then
			n += 1
			buildRow(qid, (st.state == "ready" and 0 or 100) + i)
		end
	end
	if n == 0 then
		label({Size = UDim2.new(1, 0, 0, 60), Text = tab == "active" and T("ui_empty") or T("ui_emptydone"), TextSize = 20, TextColor3 = Color3.fromRGB(95, 68, 38),
			TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center}, list)
	end
end
tabA.MouseButton1Click:Connect(function() tab = "active" refreshJournal() end)
tabD.MouseButton1Click:Connect(function() tab = "done" refreshJournal() end)

local function setJournal(open)
	if open == jOpen then return end
	jOpen = open
	if open then
		guiOpen(1)
		refreshJournal()
		jgui.Enabled = true
		jpanel.Position = J_HIDE
		TweenService:Create(jpanel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = J_OPEN}):Play()
	else
		guiOpen(-1)
		TweenService:Create(jpanel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Position = J_HIDE}):Play()
		task.delay(0.31, function() if not jOpen then jgui.Enabled = false end end)
	end
end
jBtn.MouseButton1Click:Connect(function() setJournal(not jOpen) end)
dim.MouseButton1Click:Connect(function() setJournal(false) end)

-- =====================================================================
-- ТРЕКЕР + УВЕДОМЛЕНИЯ
-- =====================================================================
local tgui = new("ScreenGui", {Name = "QuestTrackerGui", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, playerGui)
local tracker = paper({AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0.3, 0), Size = UDim2.fromOffset(250, 0), AutomaticSize = Enum.AutomaticSize.Y,
	ImageTransparency = 0.1, BackgroundTransparency = 0.1, Visible = false}, tgui)
stroke(tracker, C_EDGE, 2)
new("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8)}, tracker)
new("UIListLayout", {Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder}, tracker)
-- шапка с крестиком (свернуть трекер)
local trackerHidden = false
local thead = new("Frame", {LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1}, tracker)
label({Size = UDim2.new(1, -26, 1, 0), Text = T("ui_journal") .. "  [H]", TextSize = 16, TextColor3 = Color3.fromRGB(95, 68, 38), TextYAlignment = Enum.TextYAlignment.Center}, thead)
local tclose = new("TextButton", {Size = UDim2.fromOffset(22, 22), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), BackgroundColor3 = C_ROW,
	Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C_RED, Text = "✕"}, thead)
corner(tclose, 5)
stroke(tclose, C_EDGE2, 1)
local ttab = new("TextButton", {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0.3, 0), Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = C_PAPER, Font = Enum.Font.Garamond, TextSize = 18, TextColor3 = C_INK, Text = "★ " .. T("ui_journal") .. "  [H]", Visible = false}, tgui)
new("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10)}, ttab)
corner(ttab, 8)
stroke(ttab, C_EDGE, 2)
local refreshTracker
tclose.MouseButton1Click:Connect(function() trackerHidden = true refreshTracker() end)
ttab.MouseButton1Click:Connect(function() trackerHidden = false refreshTracker() end)

function refreshTracker()
	for _, c in ipairs(tracker:GetChildren()) do if c:IsA("TextLabel") then c:Destroy() end end
	local shown, ready = 0, 0
	for i, qid in ipairs(allOrder()) do
		local st = state[qid]
		if st and st.state ~= "done" then
			if st.state == "ready" then ready += 1 end
			if shown < 3 then
				shown += 1
				local def = getDef(qid)
				label({LayoutOrder = i * 10, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = "★ " .. qTitle(qid), TextSize = 19,
					TextColor3 = Color3.fromRGB(50, 32, 16)}, tracker)
				if st.state == "ready" then
					label({LayoutOrder = i * 10 + 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
						Text = "➜ " .. T("ui_qready") .. " " .. npcName(def.npc), TextSize = 16, TextColor3 = C_GREEN}, tracker)
				else
					for gi, g in ipairs(def.goals) do
						local n = st.prog and (st.prog[gi] or st.prog[tostring(gi)]) or 0
						label({LayoutOrder = i * 10 + gi, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
							Text = "   " .. T(g.label) .. "  " .. n .. "/" .. g.count, TextSize = 16, TextColor3 = n >= g.count and C_GREEN or C_INK2}, tracker)
					end
				end
			end
		end
	end
	tracker.Visible = shown > 0 and not trackerHidden
	ttab.Visible = shown > 0 and trackerHidden
	badge.Visible = ready > 0
	badge.Text = tostring(ready)
end

local tstack = new("Frame", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70), Size = UDim2.fromOffset(420, 0), BackgroundTransparency = 1}, tgui)
local function toast(title, body, col)
	local f = paper({AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -120), Size = UDim2.fromOffset(420, 64)}, tstack)
	stroke(f, C_EDGE, 2)
	label({Size = UDim2.new(1, -20, 0, 28), Position = UDim2.fromOffset(10, 4), Text = title, TextSize = 24, TextColor3 = col or C_INK, TextXAlignment = Enum.TextXAlignment.Center}, f)
	label({Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 33), Text = body, TextSize = 18, TextColor3 = C_INK2, TextXAlignment = Enum.TextXAlignment.Center}, f)
	TweenService:Create(f, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = UDim2.new(0.5, 0, 0, 0)}):Play()
	task.delay(3.5, function()
		TweenService:Create(f, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Position = UDim2.new(0.5, 0, 0, -120)}):Play()
		task.delay(0.35, function() f:Destroy() end)
	end)
end

remote.OnClientEvent:Connect(function(kind, a, b, c)
	if kind == "state" then
		state = type(a) == "table" and a or {}
		if type(b) == "table" then dailyDefs = b end
		if type(c) == "table" then offers = c end
		refreshTracker()
		if jOpen then refreshJournal() end
	elseif kind == "toast" then
		if a == "daily_new" then toast(T("ui_daily"), T("daily_new"), C_INK) return end
		local def = getDef(b)
		local qid = b
		if not def then return end
		if a == "daily_expired" then toast(T("daily_expired"), qTitle(qid), C_RED) return end
		local title = qTitle(qid)
		if a == "new" then toast(T("ui_qnew"), title, C_INK)
		elseif a == "ready" then toast(title, T("ui_qready") .. " " .. npcName(def.npc), C_GREEN)
		elseif a == "done" then toast(T("ui_qdone"), title .. "  +" .. rewardText(def.reward), C_GREEN)
		elseif a == "fail" then toast(title, T("ui_qfail"), C_RED) end
	end
end)

-- ===== клавиши =====
UIS.InputBegan:Connect(function(input, gp)
	if input.KeyCode == Enum.KeyCode.H and not UIS:GetFocusedTextBox() then
		trackerHidden = not trackerHidden
		refreshTracker()
		return
	end
	if input.KeyCode == Enum.KeyCode.J and not UIS:GetFocusedTextBox() then
		setJournal(not jOpen)
		return
	end
	if dlg.open then
		local map = {[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4}
		local i = map[input.KeyCode]
		if i then
			if dlg.typing then
				dlg.typing = false
				voice:Stop()
				dText.Text = dlg.full
				showOptions(true)
			elseif dlg.options[i] then
				dlg.options[i].fn()
			end
		end
	end
end)


-- ===== события мира: уведомления + маяки над караваном / Ямой / целью награды =====
if worldRemote then
	local function bn(i) return T("bn_" .. tostring(i or 1)) end
	worldRemote.OnClientEvent:Connect(function(kind, ev, data)
		if kind ~= "event" then return end
		data = type(data) == "table" and data or {}
		if ev == "caravan_arrive" then toast(T("ev_caravan_arrive"), T("ev_caravan_arrive2"), C_GREEN)
		elseif ev == "caravan_leave" then toast(T("ev_caravan_leave"), T("ev_caravan_leave2"), C_INK)
		elseif ev == "pit_open" then toast(T("ev_pit_open"), T("ev_pit_open2"), C_RED)
		elseif ev == "pit_clear" then toast(T("ev_pit_clear"), "+" .. tostring(data.reward or 0) .. "$", C_GREEN)
		elseif ev == "pit_close" then toast(T("ev_pit_close"), T("bc_pit"), C_INK)
		elseif ev == "bounty_new" then toast(T("ev_bounty_new"), "☠ " .. bn(data.name) .. " — " .. tostring(data.reward or 0) .. "$", C_RED)
		elseif ev == "bounty_dead" then toast(T("ev_bounty_dead"), bn(data.name) .. " ✕  " .. tostring(data.killer or "") .. "  +" .. tostring(data.reward or 0) .. "$", C_GREEN)
		elseif ev == "bounty_gone" then toast(T("ev_bounty_gone"), bn(data.name), C_INK)
		end
	end)
end
do
	local bgui = new("Folder", {Name = "WorldBeacons"}, playerGui)
	local beacons = {} -- model -> billboard
	local function consider(m)
		if m:IsA("Model") and m:GetAttribute("WorldBeacon") and not beacons[m] then beacons[m] = false end
	end
	for _, d in ipairs(Workspace:GetDescendants()) do consider(d) end
	Workspace.DescendantAdded:Connect(function(d)
		if d:IsA("Model") then task.delay(0.2, function() if d.Parent then consider(d) end end) end
	end)
	local COL = { caravan = Color3.fromRGB(255, 215, 120), pit = Color3.fromRGB(255, 110, 80), bounty = Color3.fromRGB(255, 60, 50) }
	task.spawn(function()
		while true do
			task.wait(0.3)
			local me = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			for m, bb in pairs(beacons) do
				local kind = m.Parent and m:GetAttribute("WorldBeacon")
				local root = kind and (m.PrimaryPart or m:FindFirstChild("HumanoidRootPart", true) or m:FindFirstChildWhichIsA("BasePart", true))
				if not root then
					if bb then bb:Destroy() end
					beacons[m] = nil
				else
					if not bb then
						bb = new("BillboardGui", {Name = "Beacon", Size = UDim2.fromOffset(220, 46), StudsOffsetWorldSpace = Vector3.new(0, kind == "pit" and 10 or 7, 0),
							AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 2000, ResetOnSpawn = false}, bgui)
						new("TextLabel", {Name = "L", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.Garamond, TextScaled = true,
							TextColor3 = COL[kind] or C_GOLD, TextStrokeTransparency = 0.3, Text = ""}, bb)
						beacons[m] = bb
					end
					bb.Adornee = root
					local name
					if kind == "caravan" then name = "◆ " .. T("bc_caravan")
					elseif kind == "pit" then name = "▼ " .. T("bc_pit")
					else name = "☠ " .. T("bn_" .. tostring(m:GetAttribute("BountyName") or 1)) .. "  " .. tostring(m:GetAttribute("BountyReward") or "") .. "$" end
					local dist = me and math.floor((me.Position - root.Position).Magnitude) or 0
					bb.L.Text = name .. "\n" .. dist .. " m"
				end
			end
		end
	end)
end

remote:FireServer("sync")
print("[QuestClient] загружен (" .. lang .. ")")


