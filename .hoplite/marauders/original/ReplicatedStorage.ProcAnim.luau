-- ProcAnim: процедурные позы для R6 (без загрузки анимаций на сайт).
-- Позы задаются углами в градусах {rx, ry, rz, tx, ty, tz} для каждой части тела
-- и применяются через Motor6D.Transform (только визуально, на клиенте).
-- Используют: NPCProcAnimClient (бармен в салуне) и IntroCutscene (зомби в ролике).
local M = {}
local rad, sin, cos, abs, clamp = math.rad, math.sin, math.cos, math.abs, math.clamp

M.PARTS = { "Torso", "Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg" }
local IS_PART = {}
for _, n in ipairs(M.PARTS) do IS_PART[n] = true end

-- суставы модели: [часть] = { m = Motor6D, r = поворот C0 }
function M.getJoints(model)
	local joints, n = {}, 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and d.Part1 and IS_PART[d.Part1.Name] and d.Part1.Parent == model and not joints[d.Part1.Name] then
			joints[d.Part1.Name] = { m = d, r = d.C0 - d.C0.Position }
			n += 1
		end
	end
	joints._n = n
	return joints
end

function M.valid(joints)
	if not joints or (joints._n or 0) < 6 then return false end
	for _, n in ipairs(M.PARTS) do
		local j = joints[n]
		if not j or not j.m.Parent or not j.m.Part0 or not j.m.Part1 then return false end
	end
	return true
end

local function tf(j, p)
	local r = j.r
	return r:Inverse() * CFrame.new(p[4] or 0, p[5] or 0, p[6] or 0) * CFrame.Angles(rad(p[1] or 0), rad(p[2] or 0), rad(p[3] or 0)) * r
end

function M.apply(joints, pose)
	for part, p in pairs(pose) do
		local j = joints[part]
		if j and j.m.Parent then j.m.Transform = tf(j, p) end
	end
end

function M.reset(joints)
	for _, n in ipairs(M.PARTS) do
		local j = joints[n]
		if j and j.m.Parent then j.m.Transform = CFrame.identity end
	end
end

local function smooth(a, b, t)
	if t <= a then return 0 elseif t >= b then return 1 end
	local x = (t - a) / (b - a)
	return x * x * (3 - 2 * x)
end
M.smooth = smooth

function M.lerpPose(a, b, u)
	local out = {}
	for _, part in ipairs(M.PARTS) do
		local pa, pb = a[part] or {}, b[part] or {}
		local q = {}
		for i = 1, 6 do q[i] = (pa[i] or 0) + ((pb[i] or 0) - (pa[i] or 0)) * u end
		out[part] = q
	end
	return out
end

-- ===== Бармен: сидит на полу, руки закрывают голову, дрожит; иногда выглядывает =====
function M.cower(t, seed)
	local tt = t + (seed or 0)
	-- иногда дрожь сильнее (приступы страха)
	local amp = 1 + 1.4 * math.max(0, sin(tt * 0.9)) ^ 6
	local function j(a, f, ph) return a * amp * (sin(tt * f + ph) * 0.65 + sin(tt * f * 1.73 + ph * 2.3) * 0.35) end
	local cyc = tt % 7
	local peek = smooth(3.2, 3.7, cyc) * (1 - smooth(5.0, 5.5, cyc)) -- 0 = закрылся, 1 = выглядывает
	local look = -32 * smooth(3.3, 3.8, cyc) + 64 * smooth(4.15, 4.5, cyc) - 32 * smooth(4.95, 5.35, cyc)
	local arms = 150 - 32 * peek
	return {
		Torso = { 8 + j(1.0, 47, 0), j(1.2, 41, 1), j(1.4, 53, 2), 0, -1.5, 0 },
		Head = { -20 + 22 * peek + j(2.0, 44, 3), look + j(2.2, 39, 4), j(1.4, 51, 5) },
		["Right Arm"] = { arms + j(3, 43, 6), j(2, 49, 7), -30 + 12 * peek + j(2, 46, 8) },
		["Left Arm"] = { arms + j(3, 45, 9), j(2, 42, 10), 30 - 12 * peek + j(2, 50, 11) },
		["Right Leg"] = { 86 + j(1.5, 40, 12), 0, 4 + j(1, 47, 13) },
		["Left Leg"] = { 80 + j(1.5, 44, 14), 0, -3 + j(1, 52, 15) },
	}
end

-- ===== Зомби: шаркающая походка, руки вперёд (период 1.6 с) =====
function M.shamble(t, ph)
	local a = (t + (ph or 0)) * (2 * math.pi / 1.6)
	local s, c = sin(a), cos(a)
	return {
		Torso = { -10 + 2 * c, 6 * s, 4 * s, 0, 0.1 * abs(s), 0 },
		Head = { -6 + 3 * c, -8 * s, 14 },
		["Right Arm"] = { 88 + 6 * s, 0, -6 },
		["Left Arm"] = { 84 - 6 * s, 0, 6 },
		["Right Leg"] = { 22 * s, 0, 0 },
		["Left Leg"] = { -16 * s, 0, 0 },
	}
end

-- ===== Зомби: выбирается из песка (u = 0..1), в конце переходит в походку =====
local RISE = {
	{ 0, { Torso = { 22 }, Head = { 28 }, ["Right Arm"] = { 172, 0, -10 }, ["Left Arm"] = { 168, 0, 10 }, ["Right Leg"] = {}, ["Left Leg"] = {} } },
	{ 0.45, { Torso = { 12 }, Head = { 14, 0, 6 }, ["Right Arm"] = { 155, 0, -14 }, ["Left Arm"] = { 140, 0, 14 }, ["Right Leg"] = { 8 }, ["Left Leg"] = { -6 } } },
	{ 0.8, { Torso = { -12 }, Head = { -8, 0, 12 }, ["Right Arm"] = { 98 }, ["Left Arm"] = { 92 }, ["Right Leg"] = { 4 }, ["Left Leg"] = { -4 } } },
	{ 1, M.shamble(0) },
}
function M.rise(u, t)
	u = clamp(u, 0, 1)
	for i = 1, #RISE - 1 do
		local a, b = RISE[i], RISE[i + 1]
		if u <= b[1] then
			local k = (u - a[1]) / (b[1] - a[1])
			local pose = M.lerpPose(a[2], b[2], k * k * (3 - 2 * k))
			-- подёргивания, пока лезет
			local w = (1 - u) * 6
			local tt = t or 0
			pose["Right Arm"][1] += sin(tt * 17) * w
			pose["Left Arm"][1] += sin(tt * 15 + 1) * w
			pose.Head[3] += sin(tt * 11) * w
			return pose
		end
	end
	return M.shamble(0)
end

-- ===== Пит Мейсон (шахтёр): устало дышит, оглядывается, иногда вытирает пот со лба (цикл 12 с) =====
function M.minerTired(t, seed)
	local tt = t + (seed or 0)
	local br = sin(tt * 1.6)
	local cyc = tt % 12
	local w = smooth(5.0, 5.9, cyc) * (1 - smooth(8.3, 9.2, cyc)) -- 1 = рука у лба
	local rub = sin(tt * 6.5) * smooth(5.6, 6.0, cyc) * (1 - smooth(8.0, 8.3, cyc))
	local sigh = smooth(9.0, 9.6, cyc) * (1 - smooth(10.2, 11.4, cyc)) -- выдох, плечи опускаются
	local lean = -3 + 1.2 * br - 4 * sigh
	local look = 14 * sin(tt * 0.31) * (1 - w)
	return {
		Torso = { lean, 0, 0 },
		Head = { -3 + 1.5 * br - 7 * w - 5 * sigh, look, 0 },
		["Right Arm"] = { 3 + 2 * br + 145 * w, 0, 3 + (-50 + 9 * rub) * w },
		["Left Arm"] = { 3 + 2 * br + 4 * sigh, 0, -3 },
		["Right Leg"] = { -lean, 0, 2 },
		["Left Leg"] = { -lean, 0, -2 },
	}
end

-- ===== Уик (шериф): рука у кобуры, медленно осматривается, пальцы иногда дёргаются (цикл 10 с) =====
function M.sheriffWatch(t, seed)
	local tt = t + (seed or 0)
	local br = sin(tt * 1.4)
	local cyc = tt % 10
	local look = 35 * smooth(1.0, 1.8, cyc) - 70 * smooth(4.0, 5.2, cyc) + 35 * smooth(7.5, 8.3, cyc)
	local tw = smooth(5.6, 6.0, cyc) * (1 - smooth(6.8, 7.3, cyc)) -- рука ближе к кобуре
	local f = sin(tt * 9) * tw
	local ty = look * 0.15
	local lean = -1 + 0.8 * br
	return {
		Torso = { lean, ty, 0 },
		Head = { -2 + br, look - ty, 0 },
		["Right Arm"] = { -4 + 1.5 * br - 8 * tw, 0, 9 + 6 * tw + 3 * f },
		["Left Arm"] = { 18 + 1.5 * br, 0, 14 },
		["Right Leg"] = { -lean, -ty, 2 },
		["Left Leg"] = { -lean, -ty, -2 },
	}
end

-- ===== Илай (помощник шерифа): руки скрещены, переносит вес, иногда зевает (цикл 9 с) =====
function M.deputyArms(t, seed)
	local tt = t + (seed or 0)
	local br = sin(tt * 1.5)
	local sway = 2.5 * sin(tt * 0.45)
	local cyc = tt % 9
	local yawn = smooth(5.0, 5.7, cyc) * (1 - smooth(6.6, 7.4, cyc))
	local lean = br + 3 * yawn
	return {
		Torso = { lean, 0, sway },
		Head = { 1.5 * br + 14 * yawn, 8 * sin(tt * 0.27), -sway * 0.6 },
		["Right Arm"] = { 84 + 2 * br + 6 * yawn, 0, -52 },
		["Left Arm"] = { 72 + 2 * br + 6 * yawn, 0, 50 },
		["Right Leg"] = { -lean, 0, -sway },
		["Left Leg"] = { -lean, 0, -sway },
	}
end

-- ===== Билли (фермер): переминается с ноги на ногу, иногда чешет затылок (цикл 11 с) =====
function M.farmerScratch(t, seed)
	local tt = t + (seed or 0)
	local br = sin(tt * 1.5)
	local sway = 3 * sin(tt * 0.6)
	local cyc = tt % 11
	local s = smooth(6.0, 6.8, cyc) * (1 - smooth(8.8, 9.6, cyc)) -- 1 = рука на затылке
	local sc = sin(tt * 11) * smooth(6.5, 6.9, cyc) * (1 - smooth(8.6, 8.9, cyc))
	local lean = -1 + br
	return {
		Torso = { lean, 0, sway },
		Head = { -2 + br - 6 * s, 10 * sin(tt * 0.35) * (1 - s), -sway * 0.5 + 9 * s },
		["Right Arm"] = { 2 + 2 * br + 182 * s, 0, 2 + (-28 + 6 * sc) * s },
		["Left Arm"] = { 2 + 2 * br, 0, -2 - sway * 0.5 },
		["Right Leg"] = { -lean, 0, -sway },
		["Left Leg"] = { -lean, 0, -sway },
	}
end

-- ===== Док Гриффит: руки за спиной, иногда задумчиво трёт подбородок (цикл 12 с) =====
function M.doctorThink(t, seed)
	local tt = t + (seed or 0)
	local br = sin(tt * 1.3)
	local cyc = tt % 12
	local c = smooth(5.5, 6.4, cyc) * (1 - smooth(9.2, 10.1, cyc)) -- 1 = рука у подбородка
	local rub = sin(tt * 5) * smooth(6.2, 6.6, cyc) * (1 - smooth(9.0, 9.3, cyc))
	local lean = 1 + 0.8 * br
	return {
		Torso = { lean, 0, 0 },
		Head = { -1 + br - 8 * c + 4 * sin(tt * 0.25) * (1 - c), 12 * sin(tt * 0.3) * (1 - c), 3 * sin(tt * 0.4) * (1 - c) + 4 * c },
		["Right Arm"] = { -30 + 1.5 * br + 148 * c, 0, -30 + (-12 + 4 * rub) * c },
		["Left Arm"] = { -30 + 1.5 * br, 0, 30 },
		["Right Leg"] = { -lean, 0, 2 },
		["Left Leg"] = { -lean, 0, -2 },
	}
end

-- ===== Морт (гробовщик): руки сложены перед собой, голова опущена, иногда медленно поднимает взгляд (цикл 13 с) =====
function M.undertakerSolemn(t, seed)
	local tt = t + (seed or 0)
	local br = sin(tt * 1.1)
	local cyc = tt % 13
	local up = smooth(6.0, 7.5, cyc) * (1 - smooth(9.5, 11.0, cyc))
	local sway = 1.5 * sin(tt * 0.35)
	local lean = -4 + 0.8 * br + 3 * up
	return {
		Torso = { lean, 0, sway },
		Head = { -14 + br + 14 * up, 6 * sin(tt * 0.2) * up, -sway },
		["Right Arm"] = { 28 + 1.5 * br, 0, -40 },
		["Left Arm"] = { 28 + 1.5 * br, 0, 40 },
		["Right Leg"] = { -lean, 0, -sway },
		["Left Leg"] = { -lean, 0, -sway },
	}
end

-- ===== Ромео (салун): большие пальцы за ремнём, покачивается, иногда касается шляпы (цикл 10 с) =====
function M.cowboyHat(t, seed)
	local tt = t + (seed or 0)
	local br = sin(tt * 1.4)
	local sway = 2 * sin(tt * 0.5)
	local cyc = tt % 10
	local h = smooth(6.0, 6.7, cyc) * (1 - smooth(7.6, 8.4, cyc)) -- 1 = рука у полей шляпы
	local nod = smooth(6.4, 6.8, cyc) * (1 - smooth(7.2, 7.7, cyc))
	local lean = 1.5 + 0.8 * br
	return {
		Torso = { lean, 0, sway },
		Head = { 2 + br - 12 * nod, 9 * sin(tt * 0.3) * (1 - h), -sway * 0.5 + 4 },
		["Right Arm"] = { 14 + 1.5 * br + 136 * h, 0, -16 - 30 * h },
		["Left Arm"] = { 14 + 1.5 * br, 0, 16 },
		["Right Leg"] = { -lean, 0, -sway + 3 },
		["Left Leg"] = { -lean, 0, -sway - 3 },
	}
end

-- ===== Джессика (салун): рука на бедре, покачивается, иногда поправляет волосы (цикл 10 с) =====
function M.ladySway(t, seed)
	local tt = t + (seed or 0)
	local br = sin(tt * 1.5)
	local sway = 3.5 * sin(tt * 0.7)
	local yaw = 4 * sin(tt * 0.35)
	local cyc = tt % 10
	local hair = smooth(5.5, 6.3, cyc) * (1 - smooth(7.8, 8.6, cyc))
	local fix = sin(tt * 4) * smooth(6.0, 6.4, cyc) * (1 - smooth(7.5, 7.9, cyc))
	local lean = 0.8 * br
	return {
		Torso = { lean, yaw, sway },
		Head = { br - 3 * hair, -yaw + 8 * sin(tt * 0.23) * (1 - hair), -sway * 0.8 + 8 * hair },
		["Right Arm"] = { 3 + 1.5 * br + 160 * hair, 0, 4 + 4 * fix * hair },
		["Left Arm"] = { -12 + br, 0, -26 },
		["Right Leg"] = { -lean, -yaw, -sway },
		["Left Leg"] = { -lean, -yaw, -sway },
	}
end

-- ===== Вероника (гадалка): плавно покачивается, водит ладонями над невидимым шаром (цикл 8 с) =====
function M.mysticSway(t, seed)
	local tt = t + (seed or 0)
	local a = tt * (2 * math.pi / 8)
	local br = sin(tt * 1.2)
	local swX, swZ = 3 * sin(a), 2 * sin(2 * a)
	local yaw = 4 * sin(a * 0.5)
	local w1, w2 = sin(tt * 0.9), sin(tt * 0.9 + 1.6)
	local lean = -3 + swZ * 0.5 + 0.6 * br
	return {
		Torso = { lean, yaw, swX },
		Head = { -6 + 3 * sin(2 * a + 0.8), -yaw + 6 * sin(a + 0.5), -swX * 1.3 },
		["Right Arm"] = { 46 + 8 * w1, 6 * w2, -22 + 7 * w2 },
		["Left Arm"] = { 46 + 8 * w2, -6 * w1, 22 - 7 * w1 },
		["Right Leg"] = { -lean, -yaw, -swX },
		["Left Leg"] = { -lean, -yaw, -swX },
	}
end

-- ===== Гас (механик): вытирает руки, разминает спину, поглядывает по сторонам (цикл 12 с) =====
function M.mechanicWipe(t, seed)
	local tt = t + (seed or 0)
	local br = sin(tt * 1.5)
	local cyc = tt % 12
	local wipe = smooth(0.5, 1.2, cyc) * (1 - smooth(4.6, 5.3, cyc)) -- руки вместе перед собой
	local rub = sin(tt * 8) * smooth(1.0, 1.4, cyc) * (1 - smooth(4.4, 4.8, cyc))
	local stretch = smooth(7.5, 8.3, cyc) * (1 - smooth(9.3, 10.2, cyc)) -- прогиб назад, руки на пояснице
	local look = 25 * smooth(5.6, 6.3, cyc) * (1 - smooth(6.9, 7.4, cyc)) - 20 * smooth(10.4, 11.0, cyc) * (1 - smooth(11.4, 11.9, cyc))
	local lean = -2 + 0.9 * br - 5 * wipe + 7 * stretch
	return {
		Torso = { lean, 0, 0 },
		Head = { -2 + br - 10 * wipe + 4 * stretch, look, 0 },
		["Right Arm"] = { 3 + 1.5 * br + 42 * wipe + 6 * rub - 33 * stretch, 0, 2 - 40 * wipe - 26 * stretch },
		["Left Arm"] = { 3 + 1.5 * br + 42 * wipe - 6 * rub - 33 * stretch, 0, -2 + 40 * wipe + 26 * stretch },
		["Right Leg"] = { -lean, 0, 2 },
		["Left Leg"] = { -lean, 0, -2 },
	}
end

-- ===== Сержант Рид: стойка «вольно», руки за спиной, медленно оглядывает лагерь, иногда кивает (цикл 14 с) =====
function M.sergeantRest(t, seed)
	local tt = t + (seed or 0)
	local br = sin(tt * 1.2)
	local cyc = tt % 14
	local look = 28 * smooth(2.0, 3.2, cyc) - 56 * smooth(5.5, 7.0, cyc) + 28 * smooth(9.0, 10.0, cyc)
	local nod = smooth(11.0, 11.4, cyc) * (1 - smooth(11.7, 12.2, cyc))
	local lean = 2 + 0.6 * br
	local yaw = look * 0.1
	return {
		Torso = { lean, yaw, 0 },
		Head = { -1 + 0.8 * br - 10 * nod, look - yaw, 0 },
		["Right Arm"] = { -28 + br, 0, -30 },
		["Left Arm"] = { -28 + br, 0, 30 },
		["Right Leg"] = { -lean, -yaw, 5 },
		["Left Leg"] = { -lean, -yaw, -5 },
	}
end

return M

