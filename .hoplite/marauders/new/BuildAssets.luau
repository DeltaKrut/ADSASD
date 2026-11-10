local SS = game:GetService("ServerStorage")
local function part(parent, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame = name, size, cf
	p.Color, p.Material = color, material or Enum.Material.Wood
	p.Anchored, p.TopSurface, p.BottomSurface = true, Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end
local brown, dark, canvas = Color3.fromRGB(103, 70, 43), Color3.fromRGB(42, 34, 29), Color3.fromRGB(152, 117, 69)
local function wear(model, body, name, size, offset, color, shape)
	local p = part(model, name, size, body.CFrame * offset, color, Enum.Material.Fabric)
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.Massless = false, false, false, false, true
	if shape then p.Shape = shape end
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1, w.Parent = body, p, p
	return p
end
local base = SS.CaravanTemplate:FindFirstChild("Silas Crane")
assert(base, "Human R6 source missing")
local function human(name, friendly)
	local m = base:Clone()
	m.Name = name
	for attr in pairs(m:GetAttributes()) do m:SetAttribute(attr, nil) end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Accessory") or d:IsA("Shirt") or d:IsA("Pants") or d:IsA("BodyColors") or d:IsA("ForceField") or d:IsA("BillboardGui") then d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = d.Name == "HumanoidRootPart"
			d.CanCollide = d.Name == "Torso"
			d.Color = d.Name == "Head" and Color3.fromRGB(188, 143, 104) or d.Name:find("Leg") and dark or brown
		end
	end
	local hum = m.Humanoid
	for attr in pairs(hum:GetAttributes()) do hum:SetAttribute(attr, nil) end
	hum.DisplayName, hum.MaxHealth, hum.Health = name, 120, 120
	hum.BreakJointsOnDeath = false
	m.PrimaryPart = m.HumanoidRootPart
	m:PivotTo(CFrame.new(0, 3, 0))
	wear(m, m.Head, "HatBrim", Vector3.new(0.13, 3.1, 2.7), CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.pi/2), dark, Enum.PartType.Cylinder)
	wear(m, m.Head, "HatCrown", Vector3.new(0.7, 1.6, 1.6), CFrame.new(0, 0.88, 0) * CFrame.Angles(0, 0, math.pi/2), brown, Enum.PartType.Cylinder)
	wear(m, m.Torso, "Vest", Vector3.new(2.07, 1.4, 1.08), CFrame.new(0, 0.2, 0), friendly and Color3.fromRGB(174, 146, 102) or dark)
	wear(m, m.Torso, "Belt", Vector3.new(2.08, 0.22, 1.12), CFrame.new(0, -0.85, 0), dark)
	wear(m, m.Torso, "Bandolier", Vector3.new(0.24, 2.12, 0.15), CFrame.new(0, 0, -0.62) * CFrame.Angles(0, 0, -0.45), brown)
	for i=-2,2 do
		wear(m, m.Torso, "Cartridge", Vector3.new(0.22, 0.3, 0.15), CFrame.new(i*0.17, i*0.35, -0.73), Color3.fromRGB(185, 147, 65)).Material = Enum.Material.Metal
	end
	wear(m, friendly and m.Torso or m.Head, "Bandana", friendly and Vector3.new(1,0.35,0.2) or Vector3.new(1.85,0.38,0.18), friendly and CFrame.new(0,0.8,-0.7) or CFrame.new(0,-0.22,-0.55), friendly and Color3.fromRGB(214,173,75) or Color3.fromRGB(122,37,29))
	return m
end
assert(not SS:FindFirstChild("MarauderTemplate"), "MarauderTemplate already exists")
local marauder = human("Marauder", false)
marauder:SetAttribute("Marauder", true)
marauder:SetAttribute("SellValue", 100)
marauder.Name, marauder.Parent = "MarauderTemplate", SS
local whip = SS:FindFirstChild("Whip")
if not whip then
	assert(game.StarterPack:FindFirstChild("Whip"), "Whip source missing")
	whip = game.StarterPack.Whip:Clone()
	whip.Parent = SS
end
local wood = workspace.BuildItems:FindFirstChild("plank") or workspace.BuildItems:FindFirstChild("wood floor")
assert(wood, "Build wood source missing")
wood = wood:Clone()
wood.Name, wood.Parent = "MarauderWood", SS
for _, attr in ipairs({"BeingHeld", "Welded", "Sold", "POILoot"}) do wood:SetAttribute(attr, nil) end
local camp = Instance.new("Model")
camp.Name = "MarauderCamp"
camp:SetAttribute("FootW", 64)
camp:SetAttribute("FootD", 82)
camp:SetAttribute("MaxSpread", 2.5)
camp:SetAttribute("Foundation", true)
local root = part(camp, "CampOrigin", Vector3.new(0.1,0.1,0.1), CFrame.new(), brown)
root.Transparency, root.CanCollide, root.CanQuery, root.CanTouch = 1, false, false, false
camp.PrimaryPart = root
part(camp, "SandFoundation", Vector3.new(51,1.8,52), CFrame.new(0,0,-5), Color3.fromRGB(156,127,88), Enum.Material.Sand)
local function tent(x,z,angle)
	local cf=CFrame.new(x,0.9,z)*CFrame.Angles(0,angle,0)
	local t=Instance.new("Model") t.Name="CanvasTent" t.Parent=camp
	part(t,"Bedroll",Vector3.new(6,0.3,8),cf*CFrame.new(0,0.2,0),dark,Enum.Material.Fabric)
	for _,sign in ipairs({-1,1}) do
		part(t,"CanvasRoof",Vector3.new(6.6,0.16,12),cf*CFrame.new(sign*2.4,3.7,0)*CFrame.Angles(0,0,-sign*0.76),canvas,Enum.Material.Fabric)
		part(t,"TentPole",Vector3.new(0.25,6.2,0.25),cf*CFrame.new(0,3.1,sign*5.6),brown)
	end
	part(t,"RidgePole",Vector3.new(0.2,0.2,12),cf*CFrame.new(0,6.15,0),brown)
	part(t,"Cot",Vector3.new(3,0.65,6),cf*CFrame.new(-1,0.65,1),Color3.fromRGB(81,86,58),Enum.Material.Fabric)
end
tent(-13,-16,0.12) tent(13,-16,-0.12)
for i=1,10 do
	local a=i*math.pi/5
	local p=part(camp,"FireRing",Vector3.new(1.8,0.65,1.3),CFrame.new(math.cos(a)*3,1.1,math.sin(a)*3+1)*CFrame.Angles(0,-a,0),Color3.fromRGB(76,72,65),Enum.Material.Slate)
	p.Shape=Enum.PartType.Ball
end
for _,a in ipairs({0.4,-0.6}) do part(camp,"Firewood",Vector3.new(4,0.5,0.55),CFrame.new(0,1.2,1)*CFrame.Angles(0,a,0),dark) end
local ember=part(camp,"Embers",Vector3.new(2,0.15,2),CFrame.new(0,1.2,1),Color3.fromRGB(230,93,29),Enum.Material.Neon)
local fire=Instance.new("Fire") fire.Size=4 fire.Heat=4 fire.Parent=ember
local smoke=Instance.new("Smoke") smoke.Size=3 smoke.Opacity=0.16 smoke.RiseVelocity=5 smoke.Parent=ember
local light=Instance.new("PointLight") light.Color=Color3.fromRGB(255,171,80) light.Range=24 light.Brightness=1.5 light.Parent=ember
for _,x in ipairs({-7,7}) do part(camp,"LogSeat",Vector3.new(1.3,1.2,6),CFrame.new(x,1.6,1),brown) end
local function sign(p,text)
	local gui=Instance.new("SurfaceGui") gui.Name="SupplyLabel" gui.Face=Enum.NormalId.Front gui.CanvasSize=Vector2.new(600,250) gui.Parent=p
	local label=Instance.new("TextLabel") label.Size=UDim2.fromScale(1,1) label.BackgroundTransparency=1 label.Font=Enum.Font.Oswald label.TextColor3=Color3.fromRGB(242,218,161) label.TextScaled=true label.TextWrapped=true label.Text=text label.Parent=gui
end
for i,kind in ipairs({"Ammo","Bandages","Wood"}) do
	local x=(i-2)*12
	local crate=part(camp,"SupplyCrate_"..kind,Vector3.new(4,2.8,3),CFrame.new(x,2.3,14),brown)
	crate:SetAttribute("CampSupply",kind)
	sign(crate,kind:upper().."\nPRIVATE PROPERTY")
	for _,offset in ipairs({-1.7,1.7}) do part(camp,"IronStrap",Vector3.new(0.18,2.9,3.1),crate.CFrame*CFrame.new(offset,0,0),dark,Enum.Material.Metal) end
end
for _,x in ipairs({-23,23}) do
	for z=-27,17,11 do
		part(camp,"FencePost",Vector3.new(0.7,3.6,0.7),CFrame.new(x,2,z),brown)
		if z<17 then part(camp,"FenceRail",Vector3.new(0.35,0.45,10.8),CFrame.new(x,2.7,z+5.5)*CFrame.Angles(0.04,0,0),brown) end
	end
	local pole=part(camp,"LanternPost",Vector3.new(0.45,6,0.45),CFrame.new(x,3.8,17),dark)
	local lamp=part(camp,"Lantern",Vector3.new(0.8,1.2,0.8),pole.CFrame*CFrame.new(0,2.6,0),Color3.fromRGB(255,199,100),Enum.Material.Neon)
	local l=Instance.new("PointLight") l.Color=lamp.Color l.Range=20 l.Brightness=1 l.Parent=lamp
end
for _,v in ipairs({Vector3.new(-10,0.95,6),Vector3.new(10,0.95,6),Vector3.new(0,0.95,-10)}) do
	local p=part(camp,"MarauderSpawn",Vector3.new(1,0.1,1),CFrame.new(v),brown)
	p.Transparency,p.CanCollide,p.CanQuery,p.CanTouch=1,false,false,false
end
part(camp,"BountyPost",Vector3.new(0.5,6,0.5),CFrame.new(6,3,31),brown)
local board=part(camp,"BountyNotice",Vector3.new(6,3.8,0.3),CFrame.new(6,5,31),dark)
sign(board,"WANTED\nMARAUDERS — $100 EACH\nBring bodies to the buyer")
part(camp,"ScoutPlatform",Vector3.new(9,1.8,8),CFrame.new(-5,0,32),brown)
local npc=human("Scout Ellis",true)
npc:SetAttribute("NPCId","ellis") npc:SetAttribute("TownNPC",true) npc:SetAttribute("NoCorpse",true)
npc:SetAttribute("NPCAnim",base:GetAttribute("NPCAnim"))
npc:PivotTo(CFrame.new(-5,3.95,32)*CFrame.Angles(0,math.pi,0))
npc.Parent=camp
camp.Parent=SS.POITemplates
return {template=camp:GetFullName(),guards=3,whip=whip:GetFullName()}
