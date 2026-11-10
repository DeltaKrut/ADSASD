local Players = game:GetService("Players")

local function dropTool(tool, position)
	if not tool or not tool:IsA("Tool") then return end
	local handle = tool:FindFirstChild("Handle")

	-- Снимаем якорь со ВСЕХ частей, иначе предмет зависнет в воздухе
	for _, p in ipairs(tool:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = true
			p.AssemblyLinearVelocity = Vector3.zero
			p.AssemblyAngularVelocity = Vector3.zero
		end
	end

	tool.Parent = game.Workspace
	if handle then
		-- Небольшой горизонтальный разброс, чтобы предметы не слипались в одной точке
		local randomOffset = Vector3.new(math.random(-2, 2), 0, math.random(-2, 2))
		-- Находим землю под точкой и кладём МОДЕЛЬ ЦЕЛИКОМ по её габаритам (PivotTo),
		-- чтобы она легла плашмя на песок и не провалилась сквозь baseplate
		local ray = game.Workspace:Raycast(position + Vector3.new(0, 60, 0) + randomOffset, Vector3.new(0, -200, 0), RaycastParams.new())
		local groundY = ray and ray.Position.Y or position.Y
		local extents = tool:GetExtentsSize()
		local dropCF = CFrame.new(Vector3.new(position.X, groundY + extents.Y / 2 + 0.05, position.Z) + randomOffset)
		tool:PivotTo(dropCF)
		-- Ноль скоростей: предмет просто оседает и лежит, не болтается
		handle.AssemblyLinearVelocity = Vector3.zero
		handle.AssemblyAngularVelocity = Vector3.zero
	end
end

Players.PlayerAdded:Connect(function(player)
	-- Игрок жив (заспавнился) — снимаем блокировку взаимодействия
	player.CharacterAdded:Connect(function(character)
		player:SetAttribute("Dead", false)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.Died:Connect(function()
			-- Игрок мёртв — блокируем всё взаимодействие с миром до респавна
			player:SetAttribute("Dead", true)
			local deathPosition = character:FindFirstChild("HumanoidRootPart") and character.HumanoidRootPart.Position or Vector3.new(0, 5, 0)

			-- Небольшая задержка: даём клиентскому скрипту тула (напр. копья)
			-- успеть сбросить свой HUD по атрибуту Dead, прежде чем тул выбросится
			task.delay(0.25, function()
				-- Выбрасываем экипированный инструмент (в руках)
				for _, item in ipairs(character:GetChildren()) do
					if item:IsA("Tool") then
						dropTool(item, deathPosition)
					end
				end

				-- Выбрасываем инструменты из рюкзака (Backpack)
				local backpack = player:FindFirstChild("Backpack")
				if backpack then
					for _, item in ipairs(backpack:GetChildren()) do
						if item:IsA("Tool") then
							dropTool(item, deathPosition)
						end
					end
				end
			end)
		end)
	end)
end)

-- Для игроков которые уже в игре
for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		player:SetAttribute("Dead", false)
		local humanoid = player.Character:FindFirstChild("Humanoid")
		if humanoid then
			humanoid.Died:Connect(function()
				player:SetAttribute("Dead", true)
				local deathPosition = player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position or Vector3.new(0, 5, 0)
				task.delay(0.25, function()
					for _, item in ipairs(player.Character:GetChildren()) do
						if item:IsA("Tool") then
							dropTool(item, deathPosition)
						end
					end
					local backpack = player:FindFirstChild("Backpack")
					if backpack then
						for _, item in ipairs(backpack:GetChildren()) do
							if item:IsA("Tool") then
								dropTool(item, deathPosition)
							end
						end
					end
				end)
			end)
		end
	end
end

