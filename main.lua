local Luna = loadstring(game:HttpGet("https://raw.githubusercontent.com/SleepyCattStar/CattStar/refs/heads/main/luna.lua"))()

local AimlockModule_Source = [===[
    local AimlockModule = {}

	local Players = game:GetService("Players")
	local camera = workspace.CurrentCamera
	local player = Players.LocalPlayer
	local char = player.Character or player.CharacterAdded:Wait()
	local RunService = game:GetService("RunService")
	local UserInputService = game:GetService("UserInputService")
	local Workspace = game:GetService("Workspace")
	
	local humanoid = char:WaitForChild("Humanoid") 
	local AimlockPlayerEnabled, AimlockNpcEnabled, PredictionEnabled = false, false, false
	local currentTarget = nil
	local currentTool = nil
	local vActive, sharkZActive, cursedZActive = false, false, false
	local tiltEnabled = false
	local rightTouches = {}
	local tiltConn, preTiltCFrame, dmgConn = nil, nil, nil
	local currentEnemyTarget, currentBossTarget, currentHighlight = nil, nil, nil
	local healthConn, lastHealth = nil, nil
	local cachedEnemy = nil
	local cachedBoss = nil
	local PredictionAmount = 0.1
	local MiniPlayerState = nil
	local MiniNpcState = nil
	local MiniPlayerCreated = false
	local MiniNpcCreated = false
	local MiniPlayerGui, MiniNpcGui = nil, nil
	local characterConnections = {}
	local renderConnTilt = nil
	local watchDamageActive = false

	local function clearConnections()
		for _, conn in ipairs(characterConnections) do
			pcall(function() conn:Disconnect() end)
		end
		characterConnections = {}
	end

	-- =========================
	-- Team Check
	-- =========================
	local function isAllyWithMe(targetPlayer)
		local myGui = player:FindFirstChild("PlayerGui")
		if not myGui then return false end

		local scrolling = myGui:FindFirstChild("Main")
			and myGui.Main:FindFirstChild("Allies")
			and myGui.Main.Allies:FindFirstChild("Container")
			and myGui.Main.Allies.Container:FindFirstChild("Allies")
			and myGui.Main.Allies.Container.Allies:FindFirstChild("ScrollingFrame")

		if scrolling then
			for _, frame in pairs(scrolling:GetDescendants()) do
				if frame:IsA("ImageButton") and frame.Name == targetPlayer.Name then
					return true
				end
			end
		end

		return false
	end

	local function isEnemy(targetPlayer)
		if not targetPlayer or targetPlayer == player then
			return false
		end

		local myTeam = player.Team
		local targetTeam = targetPlayer.Team

		if myTeam and targetTeam then
			if myTeam.Name == "Pirates" and targetTeam.Name == "Marines" then
				return true
			elseif myTeam.Name == "Marines" and targetTeam.Name == "Pirates" then
				return true
			end

			if myTeam.Name == "Pirates" and targetTeam.Name == "Pirates" then
				if isAllyWithMe(targetPlayer) then
					return false -- ally, not enemy
				end
				return true
			end

			if myTeam.Name == "Marines" and targetTeam.Name == "Marines" then
				return false
			end
		end

		return true
	end

	-- =========================
	-- Enemies Finder
	-- =========================
	local function getNearestEnemy(maxDistance)
		local hrp = char:WaitForChild("HumanoidRootPart")
		local nearest, shortest = nil, maxDistance or 100

		for _, p in pairs(Players:GetPlayers()) do
			if p ~= player and isEnemy(p) and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
				local humanoid = p.Character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					local enemyHRP = p.Character.HumanoidRootPart
					local dist = (enemyHRP.Position - hrp.Position).Magnitude
					if dist < shortest then
						shortest = dist
						nearest = enemyHRP
					end
				end
			end
		end

		return nearest
	end

	local function getNearestBoss(maxDistance)
		local hrp = char:WaitForChild("HumanoidRootPart")
		local nearest, shortest = nil, maxDistance or 500
		local bossFolder = Workspace:FindFirstChild("Enemies")
		if bossFolder then
			for _, boss in pairs(bossFolder:GetChildren()) do
				local humanoid = boss:FindFirstChildOfClass("Humanoid")
				if boss:FindFirstChild("HumanoidRootPart") and humanoid and humanoid.Health > 0 then
					local bossHRP = boss.HumanoidRootPart
					local dist = (bossHRP.Position - hrp.Position).Magnitude
					if dist < shortest then
						shortest = dist
						nearest = bossHRP
					end
				end
			end
		end
		return nearest
	end

	-- =========================
	-- Tilt Camera Function
	-- =========================
	local function disconnectTiltConn()
		if tiltConn then
			tiltConn:Disconnect()
			tiltConn = nil
		end
	end

	local function safeDisconnect(conn)
		if conn then
			pcall(function() conn:Disconnect() end)
			conn = nil
		end
		return nil
	end

	local function stopTiltSmooth()
		disconnectTiltConn()
		if not preTiltCFrame then return end

		local startCF = camera.CFrame
		local endCF = preTiltCFrame
		preTiltCFrame = nil

		local a = 0
		local restoreConn
		restoreConn = RunService.RenderStepped:Connect(function(dt)
			a = math.min(a + dt * 5, 1)
			camera.CFrame = startCF:Lerp(endCF, a)
			if a >= 1 then
				restoreConn:Disconnect()
			end
		end)
	end

	local function startTilt()
		disconnectTiltConn()

		preTiltCFrame = preTiltCFrame or camera.CFrame
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end

		local startCF = camera.CFrame
		local camPos = startCF.Position

		local tiltOffset
		if humanoid.FloorMaterial ~= Enum.Material.Air then
			tiltOffset = Vector3.new(0, 6, 0)
		else
			tiltOffset = Vector3.new(0, 40, 0)
		end

		local downLook = hrp.Position - tiltOffset
		local targetCF = CFrame.new(camPos, downLook)

		local alpha = 0
		tiltConn = RunService.RenderStepped:Connect(function(dt)
			if not (tiltEnabled and next(rightTouches) and hrp.Parent) then
				stopTiltSmooth()
				return
			end

			if alpha < 1 then
				alpha = math.min(alpha + dt * 2, 1)
				camera.CFrame = startCF:Lerp(targetCF, alpha)
			else
				camera.CFrame = targetCF
			end
		end)
	end

	-- =========================
	-- Mini UI Buttons
	-- =========================
	local function createMiniToggle(name, position, stateVarRef, realVarSetter)
		local playerGui = player:WaitForChild("PlayerGui")
		if playerGui:FindFirstChild(name .. "MiniToggleGui") then
			playerGui[name .. "MiniToggleGui"]:Destroy()
		end
		
		local screenGui = Instance.new("ScreenGui")
		screenGui.Name = name .. "MiniToggleGui"
		screenGui.ResetOnSpawn = false
		screenGui.Parent = player:WaitForChild("PlayerGui")

		local button = Instance.new("TextButton")
		button.Size = UDim2.new(0, 70, 0, 40) 
		button.Position = position
		button.Text = name .. (stateVarRef.value and " ON" or " OFF")
		button.TextScaled = true
		button.TextWrapped = false
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
		button.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
		button.BorderSizePixel = 0
		button.Parent = screenGui

		local uicorner = Instance.new("UICorner")
		uicorner.CornerRadius = UDim.new(0, 8)
		uicorner.Parent = button

		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 100, 50)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 200, 50))
		}
		gradient.Rotation = 45
		gradient.Parent = button

		local function updateUI(state)
			button.Text = name .. (state and " ON" or " OFF")
			gradient.Color = ColorSequence.new{
				ColorSequenceKeypoint.new(0, state and Color3.fromRGB(50, 200, 50) or Color3.fromRGB(255, 100, 50)),
				ColorSequenceKeypoint.new(1, state and Color3.fromRGB(50, 255, 50) or Color3.fromRGB(255, 200, 50))
			}
		end

		button.MouseButton1Click:Connect(function()
			stateVarRef.value = not stateVarRef.value
			realVarSetter(stateVarRef.value)
			updateUI(stateVarRef.value)
		end)

		-- =========================
		-- Dragging functionality
		-- =========================
		local dragging = false
		local dragStart = nil
		local startPos = nil

		local function onInputBegan(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = true
				dragStart = input.Position
				startPos = button.Position
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						dragging = false
					end
				end)
			end
		end

		local function onInputChanged(input)
			if dragging and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) then
				local delta = input.Position - dragStart
				button.Position = UDim2.new(
					0,
					math.clamp(startPos.X.Offset + delta.X, 0, camera.ViewportSize.X - button.AbsoluteSize.X),
					0,
					math.clamp(startPos.Y.Offset + delta.Y, 0, camera.ViewportSize.Y - button.AbsoluteSize.Y)
				)
			end
		end

		button.InputBegan:Connect(onInputBegan)
		button.InputChanged:Connect(onInputChanged)

		updateUI(stateVarRef.value)
		return screenGui
	end

	-- =========================
	-- Tool equip / unequip 
	-- =========================
	local function hookTool(tool)
		currentTool = tool
		local ancConn = tool.AncestryChanged:Connect(function(_, parent)
			if not parent then
				currentTool = nil
				vActive = false
				sharkZActive = false
				cursedZActive = false
				tiltEnabled = false
				stopTiltSmooth()
			end
		end)
		table.insert(characterConnections, ancConn)
	end

	-- =========================
	-- Tilt trigger condition
	-- =========================
	local function canTilt()
		return (currentTool and currentTool.Name == "Dough-Dough" and vActive)
			or (currentTool and currentTool.Name == "Shark Anchor" and sharkZActive)
			or (currentTool and currentTool.Name == "Cursed Dual Katana" and cursedZActive)
	end

	-- =========================
	-- V Skill Detection
	-- =========================
	if _G.AimlockHooked then
		return AimlockModule
	end
	_G.AimlockHooked = true
	local old
	old = hookmetamethod(game, "__namecall", function(self, ...)
		local method = getnamecallmethod()
		local args = {...}

		if (method == "InvokeServer" or method == "FireServer") then
			local a1 = args[1]

			if typeof(a1) == "string" and a1:upper() == "V" then
				if currentTool and currentTool.Name == "Dough-Dough" then
					vActive = true
					local stamp = os.clock()
					task.delay(2, function()
						if os.clock() - stamp >= 2 then
							vActive = false
							if tiltEnabled and next(rightTouches) then
								tiltEnabled = false
								stopTiltSmooth()
								rightTouches = {}
							end
						end
					end)
				end
			end

			if typeof(a1) == "string" and a1:upper() == "Z" then
				if currentTool and currentTool.Name == "Shark Anchor" then
					sharkZActive = true
					local stamp = os.clock()
					task.delay(2, function()
						if os.clock() - stamp >= 2 then
							sharkZActive = false
							if tiltEnabled and next(rightTouches) then
								tiltEnabled = false
								stopTiltSmooth()
								rightTouches = {}
							end
						end
					end)
				end
			end

			if typeof(a1) == "string" and a1:upper() == "Z" then
				if currentTool and currentTool.Name == "Cursed Dual Katana" then
					cursedZActive = true
					local stamp = os.clock()
					task.delay(2, function()
						if os.clock() - stamp >= 2 then
							cursedZActive = false
							if tiltEnabled and next(rightTouches) then
								tiltEnabled = false
								stopTiltSmooth()
								rightTouches = {}
							end
						end
					end)
				end
			end

			if currentTool and currentTool.Name == "Shark Anchor" and self.Name == "EquipEvent" then
				local arg1 = args[1]
				if arg1 == false then
					currentTool = nil
					sharkZActive = false
					tiltEnabled = false
					stopTiltSmooth()
				end
			end
		end
		return old(self, ...)
	end)

	-- =========================
	-- Touch tracking
	-- =========================
	UserInputService.TouchStarted:Connect(function(touch)
		camera = workspace.CurrentCamera
		if not camera then return end

		if touch.Position.X > camera.ViewportSize.X / 2 then
			rightTouches[touch] = true
			if tiltEnabled and canTilt() then
				startTilt()
			end
		end
	end)

	UserInputService.TouchEnded:Connect(function(touch)
		if rightTouches[touch] then
			rightTouches[touch] = nil
			if not next(rightTouches) then
				stopTiltSmooth()			
				tiltEnabled = false
				vActive = false
				sharkZActive = false
				cursedZActive = false
			end
		end
	end)

	local function watchDamageCounter()
		if dmgConn then
			pcall(function() dmgConn:Disconnect() end)
			dmgConn = nil
		end

		watchDamageActive = true

		task.spawn(function()
			while watchDamageActive do
				local gui = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("Main")
				if not gui then
					task.wait(1)
					continue
				end

				local dmgCounter = gui:FindFirstChild("DmgCounter")
				if not dmgCounter then
					task.wait(1)
					continue
				end

				local dmgTextLabel = dmgCounter:FindFirstChild("Text")
				if not dmgTextLabel then
					task.wait(1)
					continue
				end

				dmgConn = dmgTextLabel:GetPropertyChangedSignal("Text"):Connect(function()
					local dmgText = tonumber(dmgTextLabel.Text) or 0
					if dmgText > 0 and canTilt() and currentHighlight then
						tiltEnabled = true
						if next(rightTouches) then
							startTilt()
						end
					else
						tiltEnabled = false
						stopTiltSmooth()
					end
				end)
				table.insert(characterConnections, dmgConn)
				break
			end
		end)
	end

	local function watchHealth(humanoid)
		if healthConn then
			pcall(function() healthConn:Disconnect() end)
			healthConn = nil
		end

		lastHealth = humanoid.Health

		healthConn = humanoid.HealthChanged:Connect(function(newHealth)
			if tiltEnabled and next(rightTouches) then
				if newHealth < lastHealth then
					tiltEnabled = false
					stopTiltSmooth()
					rightTouches = {}
				end
			end
			lastHealth = newHealth
		end)

		table.insert(characterConnections, healthConn)
	end

	local function setAimlockTarget(targetModel)
		if currentHighlight then
			currentHighlight:Destroy()
			currentHighlight = nil
		end

		if not targetModel then
			if dmgConn then
				pcall(function() dmgConn:Disconnect() end)
				dmgConn = nil
			end
			currentTarget = nil
			return
		end

		local humanoid = targetModel:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			currentTarget = nil
			return
		end

		if targetModel:IsA("Model") then
			local highlight = Instance.new("Highlight")
			highlight.FillColor = Color3.fromRGB(255, 255, 0)
			highlight.OutlineColor = Color3.fromRGB(255, 255, 0)
			highlight.FillTransparency = 0.5
			highlight.OutlineTransparency = 0
			highlight.Adornee = targetModel
			highlight.Parent = targetModel
			currentHighlight = highlight

			if dmgConn then
				pcall(function() dmgConn:Disconnect() end)
				dmgConn = nil
			end

			local diedConn = humanoid.Died:Connect(function()
				if currentHighlight then
					currentHighlight:Destroy()
					currentHighlight = nil
				end
				currentTarget = nil

				if dmgConn then
					pcall(function() dmgConn:Disconnect() end)
					dmgConn = nil
				end

				if tiltEnabled then
					tiltEnabled = false
					stopTiltSmooth()
					rightTouches = {}
				end
			end)
			table.insert(characterConnections, diedConn)

			if currentTarget ~= targetModel then
				watchDamageCounter()
			end
			currentTarget = targetModel
		end
	end

	local function startRenderLoop()
		if renderConnTilt then
			return
		end

		renderConnTilt = RunService.RenderStepped:Connect(function(dt)
			if not AimlockPlayerEnabled and not AimlockNpcEnabled then
				renderConnTilt:Disconnect()
				renderConnTilt = nil
				return
			end

			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not hrp then 
				return 
			end

			if AimlockPlayerEnabled then
				if not cachedEnemy 
					or not cachedEnemy.Parent 
					or not cachedEnemy.Parent:FindFirstChildOfClass("Humanoid") 
					or cachedEnemy.Parent:FindFirstChildOfClass("Humanoid").Health <= 0 then
					cachedEnemy = getNearestEnemy(500)
				end
			else
				cachedEnemy = nil
			end

			if AimlockNpcEnabled then
				if not cachedBoss 
					or not cachedBoss.Parent 
					or not cachedBoss.Parent:FindFirstChildOfClass("Humanoid") 
					or cachedBoss.Parent:FindFirstChildOfClass("Humanoid").Health <= 0 then
					cachedBoss = getNearestBoss(500)
				end
			else
				cachedBoss = nil
			end

			if not tiltEnabled then
				local targetHRP = nil
				if AimlockPlayerEnabled then targetHRP = cachedEnemy end
				if AimlockNpcEnabled then targetHRP = cachedBoss end

				if targetHRP then
					local camCFrame = camera.CFrame
					local camPos = camCFrame.Position
					local dist = (targetHRP.Position - camPos).Magnitude
					local predictionTime = PredictionAmount
					local enemyVelocity = targetHRP.Velocity
					local predictedPos = targetHRP.Position

					if PredictionEnabled and enemyVelocity.Magnitude > 3 then
						predictedPos = predictedPos + enemyVelocity * predictionTime
					end

					local yOffset = math.clamp(dist / 40, 0, 0.06)
					local lookVector = (predictedPos - camPos).Unit
					local tiltedlook = Vector3.new(lookVector.X, lookVector.Y - yOffset, lookVector.Z).Unit
					camera.CFrame = CFrame.new(camPos, camPos + tiltedlook)
				end
			end

			if AimlockPlayerEnabled and cachedEnemy and currentTarget ~= cachedEnemy.Parent then
				setAimlockTarget(cachedEnemy.Parent)
			elseif AimlockNpcEnabled and cachedBoss and currentTarget ~= cachedBoss.Parent then
				setAimlockTarget(cachedBoss.Parent)
			elseif not cachedEnemy and not cachedBoss and currentTarget then
				setAimlockTarget(nil)
			end
		end)
	end

	-- =========================
	-- lifecycle
	-- =========================
	local function onCharacterAdded(newChar)
		clearConnections()

		char = newChar

		camera = workspace.CurrentCamera
		cachedBoss = nil
		currentTarget = nil
		if currentHighlight then
			currentHighlight:Destroy()
			currentHighlight = nil
		end

		local humanoid = char:WaitForChild("Humanoid")
		local hrp = char:WaitForChild("HumanoidRootPart")

		table.insert(characterConnections, char.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				hookTool(child)
			end
		end))

		table.insert(characterConnections, char.ChildRemoved:Connect(function(child)
			if child == currentTool then
				currentTool = nil
				vActive = false
				sharkZActive = false
				cursedZActive = false
				tiltEnabled = false
				stopTiltSmooth()
			end
		end))

		watchHealth(humanoid)

		tiltEnabled = false
		vActive, sharkZActive, cursedZActive = false, false, false
		rightTouches = {}
		stopTiltSmooth()
	end

	player.CharacterAdded:Connect(onCharacterAdded)

	if player.Character then
		onCharacterAdded(player.Character)
	end

	-- =========================
	-- State
	-- =========================
	function AimlockModule:SetPlayerAimlock(state)
		AimlockPlayerEnabled = state

		if not state then
			if currentTarget and currentTarget:FindFirstChildOfClass("Humanoid") then
				if currentHighlight then
					currentHighlight:Destroy()
					currentHighlight = nil
				end
			end
		end

		if state then
			cachedEnemy = nil
			local nearestHRP = getNearestEnemy(500)
			if nearestHRP and nearestHRP.Parent then
				setAimlockTarget(nearestHRP.Parent)
			else
				setAimlockTarget(nil)
			end
		end

		if not state and not AimlockNpcEnabled then
			watchDamageActive = false
			if dmgConn then pcall(function() dmgConn:Disconnect() end) dmgConn = nil end
		else
			watchDamageCounter()
			startRenderLoop()
		end
	end

	function AimlockModule:SetNpcAimlock(state)
		AimlockNpcEnabled = state

		if not state then
			if currentTarget and currentTarget:FindFirstChildOfClass("Humanoid") then
				if currentHighlight then
					currentHighlight:Destroy()
					currentHighlight = nil
				end
			end
		end

		if state then
			cachedBoss = nil
			local nearestBossHRP = getNearestBoss(500)
			if nearestBossHRP and nearestBossHRP.Parent then
				setAimlockTarget(nearestBossHRP.Parent)
			else
				setAimlockTarget(nil)
			end
		end

		if not state and not AimlockPlayerEnabled then
			watchDamageActive = false
			if dmgConn then pcall(function() dmgConn:Disconnect() end) dmgConn = nil end
		else
			watchDamageCounter()
			startRenderLoop()
		end
	end

	function AimlockModule:SetMiniTogglePlayerAimlock(state)
		AimlockPlayerEnabled = state

		if not MiniPlayerCreated and state then
			MiniPlayerState = { value = state }
			MiniPlayerGui = createMiniToggle("Player", UDim2.new(0,10,0,90), MiniPlayerState, function(val)
				AimlockPlayerEnabled = val
				if val then
					cachedEnemy = nil
					watchDamageCounter()
					startRenderLoop()
				else
					watchDamageActive = false
					if dmgConn then pcall(function() dmgConn:Disconnect() end) dmgConn = nil end
				end
			end)
			MiniPlayerCreated = true
			if AimlockPlayerEnabled then
				cachedEnemy = nil
				watchDamageCounter()
				startRenderLoop()
			end
		elseif MiniPlayerCreated then
			MiniPlayerState.value = state
			AimlockPlayerEnabled = state
			if MiniPlayerGui then
				MiniPlayerGui.Enabled = state
				local btn = MiniPlayerGui:FindFirstChildWhichIsA("TextButton", true)
				if btn then
					btn.Text = "Player" .. (state and " ON" or " OFF")
				end
			end

			if state then
				cachedEnemy = nil
				watchDamageCounter()
				startRenderLoop()
			else
				watchDamageActive = false
				if dmgConn then pcall(function() dmgConn:Disconnect() end) dmgConn = nil end
			end
		end
	end

	function AimlockModule:SetMiniToggleNpcAimlock(state)
		AimlockNpcEnabled = state

		if not MiniNpcCreated and state then
			MiniNpcState = { value = state }
			MiniNpcGui = createMiniToggle("NPC", UDim2.new(0,10,0,50), MiniNpcState, function(val)
				AimlockNpcEnabled = val
				if val then
					cachedBoss = nil
					watchDamageCounter()
					startRenderLoop()
				else
					watchDamageActive = false
					if dmgConn then pcall(function() dmgConn:Disconnect() end) dmgConn = nil end
				end
			end)
			MiniNpcCreated = true

			if AimlockNpcEnabled then
				cachedBoss = nil
				watchDamageCounter()
				startRenderLoop()
			end
		elseif MiniNpcCreated then
			MiniNpcState.value = state
			AimlockNpcEnabled = state
			if MiniNpcGui then
				MiniNpcGui.Enabled = state
				local btn = MiniNpcGui:FindFirstChildWhichIsA("TextButton", true)
				if btn then
					btn.Text = "NPC" .. (state and " ON" or " OFF")
				end
			end

			if state then
				cachedBoss = nil
				watchDamageCounter()
				startRenderLoop()
			else
				watchDamageActive = false
				if dmgConn then pcall(function() dmgConn:Disconnect() end) dmgConn = nil end
			end
		end
	end

	function AimlockModule:SetPrediction(state)
		PredictionEnabled = state
	end

	function AimlockModule:SetPredictionTime(num)
		if typeof(num) == "number" then
			PredictionAmount = num
		end
	end

	return AimlockModule

]===]

local ESPModule_Source = [===[
    local ESPModule = {}

	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local player = Players.LocalPlayer
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local CommE = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CommE")
	local CommF = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CommF_")
	local char = player.Character or player.CharacterAdded:Wait()
	local humanoid = char:WaitForChild("Humanoid") 
	local vim = game:GetService("VirtualInputManager")
	local RunService = game:GetService("RunService")
	local UserInputService = game:GetService("UserInputService")

	local V3Enabled = false
	local BunnyHopEnabled = false
	local DodgeEnabled = false 
	local ESPEnabled = false
	local BusoEnabled = false
	local v3LoopRunning = false
	local antiAfkEnabled = false

	local NoDodgeCoroutine
	local currentTool = nil
	local ESPs = {}
	local cooldownTime = 31
	local v3Loop = nil

	-- =========================
	-- Team Check
	-- =========================
	local function isAllyWithMe(targetPlayer)
		local myGui = player:FindFirstChild("PlayerGui")
		if not myGui then return false end

		local scrolling = myGui:FindFirstChild("Main")
			and myGui.Main:FindFirstChild("Allies")
			and myGui.Main.Allies:FindFirstChild("Container")
			and myGui.Main.Allies.Container:FindFirstChild("Allies")
			and myGui.Main.Allies.Container.Allies:FindFirstChild("ScrollingFrame")

		if scrolling then
			for _, frame in pairs(scrolling:GetDescendants()) do
				if frame:IsA("ImageButton") and frame.Name == targetPlayer.Name then
					return true
				end
			end
		end

		return false
	end

	local function isEnemy(targetPlayer)
		if not targetPlayer or targetPlayer == player then
			return false
		end

		local myTeam = player.Team
		local targetTeam = targetPlayer.Team

		if myTeam and targetTeam then
			if myTeam.Name == "Pirates" and targetTeam.Name == "Marines" then
				return true
			elseif myTeam.Name == "Marines" and targetTeam.Name == "Pirates" then
				return true
			end

			if myTeam.Name == "Pirates" and targetTeam.Name == "Pirates" then
				if isAllyWithMe(targetPlayer) then
					return false -- ally, not enemy
				end
				return true
			end

			if myTeam.Name == "Marines" and targetTeam.Name == "Marines" then
				return false
			end
		end

		return true
	end

	-- =========================
	-- Ability V3
	-- =========================
	local function clickActivateAbility()
		if CommE then
			CommE:FireServer("ActivateAbility")
		end
	end

	local function startV3Loop()
		if v3LoopRunning then return end
		v3LoopRunning = true
		v3Loop = task.spawn(function()
			while v3LoopRunning do
				if not player or not player.Parent then break end
				pcall(clickActivateAbility)
				task.wait(cooldownTime)
			end
			v3Loop = nil
		end)
	end

	local function stopV3Loop()
		if not v3LoopRunning then return end
		v3LoopRunning = false
		v3Loop = nil
	end

	local function NoDodgeCool()
		if DodgeEnabled then
			NoDodgeCoroutine = task.spawn(function()
				for i, v in next, getgc() do
					local character = game.Players.LocalPlayer.Character
					local dodge = character and character:FindFirstChild("Dodge")
					if dodge and typeof(v) == "function" and getfenv(v).script == dodge then
						for i2, v2 in next, getupvalues(v) do
							if tostring(v2) == "0.4" then
								repeat
									task.wait()
									setupvalue(v, i2, 0)
								until not DodgeEnabled
							end
						end
					end
				end
			end)
		else
			if NoDodgeCoroutine then
				task.cancel(NoDodgeCoroutine)
				NoDodgeCoroutine = nil
			end
		end
	end

	-- =========================
	-- V Skill Detection
	-- =========================
	local old
	old = hookmetamethod(game, "__namecall", function(self, ...)
		local method = getnamecallmethod()
		local args = {...}

		if (method == "InvokeServer" or method == "FireServer") then
			local a1 = args[1]

			if typeof(a1) == "string" and a1:upper() == "DODGE" then
				if BunnyHopEnabled then
					local ok, h = pcall(function() return humanoid end)
					if ok and h and h.Parent then
						task.defer(function()
							pcall(function()
								h:ChangeState(Enum.HumanoidStateType.Jumping)
							end)
						end)
					end
				end
			end
		end
		return old(self, ...)
	end)

	-- =========================
	-- Global Player ESP with Colors
	-- =========================
	local espFolder = game.CoreGui:FindFirstChild("GlobalESP")
	if not espFolder then
		espFolder = Instance.new("Folder")
		espFolder.Name = "GlobalESP"
		espFolder.Parent = game.CoreGui
	end

	local function getESPColor(player)
		if player == game.Players.LocalPlayer then
			return Color3.fromRGB(0, 255, 0)
		elseif isAllyWithMe(player) then
			return Color3.fromRGB(0, 255, 0)
		elseif isEnemy(player) then
			return Color3.fromRGB(255, 255, 0)
		else
			return Color3.fromRGB(0, 255, 0)
		end
	end

	-- =========================
	-- Optimized ESP System
	-- =========================
	local function createESP(targetPlayer)
		if ESPs[targetPlayer] then return end
		local char = targetPlayer.Character
		if not char then return end
		local head = char:FindFirstChild("Head")
		if not head then return end

		local billboard = Instance.new("BillboardGui")
		billboard.Name = targetPlayer.Name
		billboard.Adornee = head
		billboard.Size = UDim2.fromOffset(220, 50)
		billboard.AlwaysOnTop = true
		billboard.StudsOffset = Vector3.new(0, 3, 0)
		billboard.Parent = espFolder

		local levelLabel = Instance.new("TextLabel")
		levelLabel.Name = "LevelLabel"
		levelLabel.Size = UDim2.new(1, 0, 0.5, 0)
		levelLabel.Position = UDim2.new(0, 0, 0, 0)
		levelLabel.BackgroundTransparency = 1
		levelLabel.Text = "Lv. ???"
		levelLabel.TextColor3 = Color3.fromRGB(0, 170, 255)
		levelLabel.TextStrokeTransparency = 0.2
		levelLabel.Font = Enum.Font.SourceSansBold
		levelLabel.TextSize = 14
		levelLabel.TextXAlignment = Enum.TextXAlignment.Center
		levelLabel.Parent = billboard

		local mainLabel = Instance.new("TextLabel")
		mainLabel.Name = "MainLabel"
		mainLabel.Size = UDim2.new(1, 0, 0.5, 0)
		mainLabel.Position = UDim2.new(0, 0, 0.5, 0)
		mainLabel.BackgroundTransparency = 1
		mainLabel.Text = "[0] "..targetPlayer.DisplayName.." (0m)"
		mainLabel.TextColor3 = getESPColor(targetPlayer)
		mainLabel.TextStrokeTransparency = 0.2
		mainLabel.Font = Enum.Font.SourceSansBold
		mainLabel.TextSize = 16
		mainLabel.TextXAlignment = Enum.TextXAlignment.Center
		mainLabel.Parent = billboard

		ESPs[targetPlayer] = billboard
	end

	RunService.Heartbeat:Connect(function()
		if not ESPEnabled then
			for _, gui in pairs(ESPs) do
				if gui then gui.Enabled = false end
			end
			return
		end

		for _, targetPlayer in pairs(Players:GetPlayers()) do
			if targetPlayer ~= player then
				if not ESPs[targetPlayer] then
					createESP(targetPlayer)
				end

				local gui = ESPs[targetPlayer]
				if gui then
					local char = targetPlayer.Character
					local head = char and char:FindFirstChild("Head")
					local hrp = char and char:FindFirstChild("HumanoidRootPart")
					local humanoid = char and char:FindFirstChildOfClass("Humanoid")
					local myHRP = player.Character and player.Character:FindFirstChild("HumanoidRootPart")

					if char and head and hrp and humanoid and myHRP then
						gui.Adornee = head
						gui.Enabled = true
						local dist = (myHRP.Position - hrp.Position).Magnitude
						local nameLabel = gui:FindFirstChild("MainLabel")
						local levelLabel = gui:FindFirstChild("LevelLabel")

						if levelLabel then
							local dataFolder = targetPlayer:FindFirstChild("Data")
							local levelValue = dataFolder and dataFolder:FindFirstChild("Level")
							levelLabel.Text = levelValue and ("Lv. "..levelValue.Value) or "Lv. ???"
						end
						if nameLabel then
							nameLabel.Text = "["..math.floor(humanoid.Health).."] "..targetPlayer.DisplayName.." ("..math.floor(dist).."m)"
							nameLabel.TextColor3 = getESPColor(targetPlayer)
						end
					else
						gui.Enabled = false
					end
				end
			end
		end
	end)

	do
		local player = game:GetService("Players").LocalPlayer

		if antiAfkEnabled then
			player.Idled:Connect(function()
				pcall(function()
					vim:SendMouseButtonEvent(
						workspace.CurrentCamera.ViewportSize.X / 2, -- X position (center of screen)
						workspace.CurrentCamera.ViewportSize.Y / 2, -- Y position (center of screen)
						0,
						true,
						game,
						1
					)
					task.wait(0.05)
					vim:SendMouseButtonEvent(
						workspace.CurrentCamera.ViewportSize.X / 2,
						workspace.CurrentCamera.ViewportSize.Y / 2,
						0,
						false,
						game,
						1
					)
				end)
			end)
		end
	end

	-- =========================
	-- State Toggles
	-- =========================
	function ESPModule:SetV3(state)
		V3Enabled = state
		if state then
			startV3Loop()
		else
			stopV3Loop()
		end
	end

	function ESPModule:SetBunnyhop(state)
		BunnyHopEnabled = state
	end

	function ESPModule:SetNoDodgeCD(state)
		DodgeEnabled = state
		if state then
			NoDodgeCool()
		else
			--ignore
		end
	end

	function ESPModule:SetAntiAfk(state)
		antiAfkEnabled = state
	end

	function ESPModule:SetBuso(state)
		BusoEnabled = state
		if state then
			if not game:GetService("Players").LocalPlayer.Character:FindFirstChild("HasBuso") then
				pcall(function() CommF:InvokeServer("Buso") end)
			end
		end
	end

	function ESPModule:SetESP(state)
		ESPEnabled = state
	end

	function ESPModule:SetGlobalFont(fontEnum)
		local playerGui = player:FindFirstChild("PlayerGui")
		if playerGui then
			for _, ui in pairs(playerGui:GetDescendants()) do
				if not ui:IsDescendantOf(playerGui:FindFirstChild("ScreenGui")) then
					if ui:IsA("TextLabel") or ui:IsA("TextButton") or ui:IsA("TextBox") then
						ui.Font = fontEnum
						ui.TextStrokeTransparency = 1
					end
				end
			end
		end
		playerGui.DescendantAdded:Connect(function(ui)
			if not ui:IsDescendantOf(playerGui:FindFirstChild("ScreenGui")) then
				if ui:IsA("TextLabel") or ui:IsA("TextButton") or ui:IsA("TextBox") then
					ui.Font = fontEnum
					ui.TextStrokeTransparency = 1
				end
			end
		end)
	end

	function ESPModule:SetRTXMode(mode)
		local Lighting = game:GetService("Lighting")
		local Terrain = workspace.Terrain
		local currentSeason = mode
		
		for _, v in pairs(Lighting:GetChildren()) do
			if v:IsA("Atmosphere") or v:IsA("BloomEffect") or v:IsA("ColorCorrectionEffect")
			or v:IsA("DepthOfFieldEffect") or v:IsA("SunRaysEffect") then
				v:Destroy()
			end
		end

		Lighting.Technology = Enum.Technology.Future
		Lighting.GlobalShadows = true
		Lighting.ShadowSoftness = 0.35
		Lighting.Brightness = 4
		Lighting.EnvironmentDiffuseScale = 1
		Lighting.EnvironmentSpecularScale = 1
		Lighting.ExposureCompensation = 0
		Lighting.ClockTime = 8
		Lighting.GeographicLatitude = 66
		Lighting.Ambient = Color3.fromRGB(25, 25, 25)
		Lighting.OutdoorAmbient = Color3.fromRGB(50, 50, 50)

		local Atmosphere = Instance.new("Atmosphere", Lighting)
		local CC = Instance.new("ColorCorrectionEffect", Lighting)
		local SR = Instance.new("SunRaysEffect", Lighting)
		local DOF = Instance.new("DepthOfFieldEffect", Lighting)
		local Bloom = Instance.new("BloomEffect", Lighting)

		Bloom.Intensity = 0.15
		Bloom.Threshold = 0.6
		Bloom.Size = 1800

		if mode == "Summer" then
			Lighting.ColorShift_Top = Color3.fromRGB(255, 250, 225)
			Lighting.ColorShift_Bottom = Color3.fromRGB(170, 210, 255)
			Atmosphere.Color = Color3.fromRGB(255, 255, 255)
			Atmosphere.Decay = Color3.fromRGB(210, 210, 190)
			Atmosphere.Density = 0.35
			Atmosphere.Haze = 1
			CC.TintColor = Color3.fromRGB(255, 235, 190)
			CC.Brightness = 0.15
			CC.Contrast = 0.25
			CC.Saturation = 0.2
			SR.Intensity = 0.15
			SR.Spread = 0.2
			DOF.FocusDistance = 25
			DOF.InFocusRadius = 30
			Terrain.WaterColor = Color3.fromRGB(100, 160, 255)
			particleColor = ColorSequence.new(Color3.fromRGB(255, 245, 200)) -- warm light dust

		elseif mode == "Autumn" then
			Lighting.ColorShift_Top = Color3.fromRGB(255, 220, 160)
			Lighting.ColorShift_Bottom = Color3.fromRGB(140, 100, 70)
			Atmosphere.Color = Color3.fromRGB(255, 200, 160)
			Atmosphere.Decay = Color3.fromRGB(200, 130, 80)
			Atmosphere.Density = 0.4
			Atmosphere.Haze = 2
			CC.TintColor = Color3.fromRGB(230, 160, 70)
			CC.Brightness = 0.1
			CC.Contrast = 0.35
			CC.Saturation = -0.05
			SR.Intensity = 0.1
			SR.Spread = 0.15
			DOF.FocusDistance = 20
			DOF.InFocusRadius = 20
			Terrain.WaterColor = Color3.fromRGB(180, 130, 90)
			particleColor = ColorSequence.new(Color3.fromRGB(255, 170, 80)) -- leaf-like glow

		elseif mode == "Spring" then
			Lighting.ColorShift_Top = Color3.fromRGB(210, 255, 220)
			Lighting.ColorShift_Bottom = Color3.fromRGB(180, 220, 190)
			Atmosphere.Color = Color3.fromRGB(210, 255, 220)
			Atmosphere.Decay = Color3.fromRGB(180, 230, 180)
			Atmosphere.Density = 0.25
			Atmosphere.Haze = 1.5
			CC.TintColor = Color3.fromRGB(210, 255, 210)
			CC.Brightness = 0.2
			CC.Contrast = 0.2
			CC.Saturation = 0.3
			SR.Intensity = 0.12
			SR.Spread = 0.17
			DOF.FocusDistance = 30
			DOF.InFocusRadius = 25
			Terrain.WaterColor = Color3.fromRGB(120, 200, 140)
			particleColor = ColorSequence.new(Color3.fromRGB(190, 255, 200)) -- green pastel tone

		elseif mode == "Winter" then
			Lighting.ColorShift_Top = Color3.fromRGB(200, 230, 255)
			Lighting.ColorShift_Bottom = Color3.fromRGB(150, 170, 190)
			Atmosphere.Color = Color3.fromRGB(190, 220, 255)
			Atmosphere.Decay = Color3.fromRGB(160, 190, 220)
			Atmosphere.Density = 0.45
			Atmosphere.Haze = 2.5
			CC.TintColor = Color3.fromRGB(200, 230, 255)
			CC.Brightness = 0.05
			CC.Contrast = 0.3
			CC.Saturation = -0.1
			SR.Intensity = 0.08
			SR.Spread = 0.1
			DOF.FocusDistance = 22
			DOF.InFocusRadius = 15
			Terrain.WaterColor = Color3.fromRGB(180, 220, 255)
			particleColor = ColorSequence.new(Color3.fromRGB(220, 240, 255)) -- snow mist tone
		end

		Terrain.WaterWaveSize = 0.15
		Terrain.WaterTransparency = 0.2
		Terrain.WaterReflectance = 0.4
		
		for _, particle in pairs(workspace:GetDescendants()) do
			if particle:IsA("ParticleEmitter") then
				particle.Color = particleColor
			end
		end
	end

	-- =========================
	-- Character Respawn Handling
	-- =========================
	local function onCharacterAdded(newChar)
		char = newChar
		humanoid = char:WaitForChild("Humanoid")

		if BunnyHopEnabled then
			-- nothing extra needed, the hookmetamethod will keep working
		end
		if V3Enabled then
			startV3Loop()
		end
		if DodgeEnabled then
			NoDodgeCool()
		end
		if BusoEnabled then
			if not game:GetService("Players").LocalPlayer.Character:FindFirstChild("HasBuso") then
				pcall(function() CommF:InvokeServer("Buso") end)
			end
		end
	end

	if player.Character then
		onCharacterAdded(player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)

	return ESPModule
]===]

local VSkillModule_Source = [===[
    
		-- ================= VSkillModule =================
	local VSkillModule = {}

	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local UserInputService = game:GetService("UserInputService")

	local currentTool = nil
	local lastTool = nil
	local sharkZActive, vActive, cursedZActive = false, false, false
	local dmgConn = nil
	local characterConnections = {}
	local rightTouchActive = false
	local SilentAimModuleRef = nil

	local function clearConnections()
		for _, conn in ipairs(characterConnections) do
			pcall(function() conn:Disconnect() end)
		end
		characterConnections = {}
	end

	-- =========================
	-- Silent Aimbot Control
	-- =========================
	local function DisableSilentAimbot()
		if SilentAimModuleRef then
			SilentAimModuleRef:Pause()
		end
	end

	local function EnableSilentAimbot()
		if SilentAimModuleRef then
			SilentAimModuleRef:Restore()
		end
	end

	-- =========================
	-- Tool Watcher
	-- =========================
	local function hookTool(tool)
		currentTool = tool
		lastTool = tool.Name
		table.insert(characterConnections, tool.AncestryChanged:Connect(function(_, parent)
			if not parent then
				currentTool = nil
				lastTool = nil
				sharkZActive, vActive, cursedZActive = false, false, false
				rightTouchActive = false
				EnableSilentAimbot()
			end
		end))
	end

	local function isValidStopCondition()
		return (currentTool and currentTool.Name == "Shark Anchor" and sharkZActive)
			or (lastTool == "Dough-Dough" and vActive)
			or (currentTool and currentTool.Name == "Cursed Dual Katana" and cursedZActive)
	end

	-- =========================
	-- Touch Control (Mobile)
	-- =========================
	UserInputService.TouchStarted:Connect(function(touch)
		local camera = workspace.CurrentCamera
		if not camera then return end
		
		if touch.Position.X > camera.ViewportSize.X / 2 then
			rightTouchActive = true

			if isValidStopCondition() then
				DisableSilentAimbot()
			end
		end
	end)

	UserInputService.TouchEnded:Connect(function(touch)
		local camera = workspace.CurrentCamera
		if not camera then return end
		
		if touch.Position.X > camera.ViewportSize.X / 2 then
			rightTouchActive = false

			EnableSilentAimbot()
			sharkZActive, vActive, cursedZActive = false, false, false
		end
	end)

	-- =========================
	-- Damage Counter Watch
	-- =========================
	local function watchDamageCounter()
		if dmgConn then
			pcall(function() dmgConn:Disconnect() end)
			dmgConn = nil
		end

		task.spawn(function()
			while true do
				gui = player:FindFirstChild("PlayerGui"):FindFirstChild("Main")
				if not gui then
					warn("[DamageLog] Main GUI not found, retrying...")
					task.wait(1)
					continue
				end

				dmgCounter = gui:FindFirstChild("DmgCounter")
				if not dmgCounter then
					warn("[DamageLog] DmgCounter not found, retrying...")
					task.wait(1)
					continue
				end

				dmgTextLabel = dmgCounter:FindFirstChild("Text")
				if not dmgTextLabel then
					warn("[DamageLog] TextLabel inside DmgCounter not found, retrying...")
					task.wait(1)
					continue
				end

				dmgConn = dmgTextLabel:GetPropertyChangedSignal("Text"):Connect(function()
					local dmgText = tonumber(dmgTextLabel.Text) or 0
					if dmgText > 0 and isValidStopCondition() and rightTouchActive then
						DisableSilentAimbot()
					elseif not rightTouchActive then
						EnableSilentAimbot()
					end
				end)
				table.insert(characterConnections, dmgConn)			
				break
			end
		end)
	end

	-- =========================
	-- Skill Detection
	-- =========================
	if not getgenv().VSkillHooked then
		getgenv().VSkillHooked = true
		local old
		old = hookmetamethod(game, "__namecall", function(self, ...)
			local method = getnamecallmethod()
			local args = {...}
		
			if (method == "InvokeServer" or method == "FireServer") then
				local a1 = args[1]

				if typeof(a1) == "string" and a1:upper() == "Z" then
					if currentTool and currentTool.Name == "Shark Anchor" then
						sharkZActive = true
					end
				end
			
				if typeof(a1) == "string" and a1:upper() == "V" then
					if lastTool == "Dough-Dough" then
						vActive = true
					end
				end
			
				if typeof(a1) == "string" and a1:upper() == "Z" then
					if currentTool and currentTool.Name == "Cursed Dual Katana" then
						cursedZActive = true
					end
				end
			end
			return old(self, ...)
		end)
	end

	-- =========================
	-- Character Handling
	-- =========================
	local function onCharacterAdded(char)
		clearConnections()
		
		sharkZActive, vActive, cursedZActive = false, false, false
		rightTouchActive = false
		EnableSilentAimbot()

		table.insert(characterConnections, char.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then hookTool(child) end
		end))

		table.insert(characterConnections, char.ChildRemoved:Connect(function(child)
			if child == currentTool and lastTool then
				currentTool = nil
				lastTool = nil
				sharkZActive, vActive, cursedZActive = false, false, false
				rightTouchActive = false
				EnableSilentAimbot()
			end
		end))

		watchDamageCounter()
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then onCharacterAdded(player.Character) end

	-- =========================
	-- External Entry
	-- =========================
	function VSkillModule:CheckVSkillUsage(SilentAimModule)
		SilentAimModuleRef = SilentAimModule
		watchDamageCounter()
	end

	return VSkillModule

]===]

local SilentAimModule_Source = [===[
    
    local VSkillModule = _G.SharedVSkill

    local SilentAimModule = {}

	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local Character = player.Character or player.CharacterAdded:Wait()
	local UserInputService = game:GetService("UserInputService")  
	local RunService = game:GetService("RunService")
	local camera = workspace.CurrentCamera
	local RS = game:GetService("ReplicatedStorage")
	local commE = RS:WaitForChild("Remotes"):WaitForChild("CommE")
	local MouseModule = RS:FindFirstChild("Mouse")

	local Services = setmetatable({}, {
		__index = function(self, serviceName)
			local good, service = pcall(game.GetService, game, serviceName);
			if (good) then
				self[serviceName] = service
				return service;
			end
		end
	});

	local SilentAimPlayersEnabled = false
	local SilentAimNPCsEnabled = false
	local UserWantsplayerAim = false
	local UserWantsNPCAim = false
	local PredictionEnabled = false
	local HighlightEnabled = false 
	local AutoKen = false
	local ZSkillorM1= false
	local autoKenRunning = false

	local renderConnection = nil
	local currentTool = nil
	local playersaimbot = nil
	local PlayersPosition = nil
	local NPCaimbot = nil
	local NPCPosition = nil
	local currentHighlight = nil
	local currentTargetType = nil
	local Selectedplayer = nil
	local MiniPlayerState = nil
	local MiniNpcState = nil
	local MiniPlayerCreated = false
	local MiniNpcCreated = false
	local MiniPlayerGui, MiniNpcGui = nil, nil

	local characterConnections = {}
	local Skills = {"X"}
	local Booms = {"TAP"}

	local PredictionAmount = 0.1
	local maxRange = 1000

	local function getHRP(model)
		if not model or not model:FindFirstChild("HumanoidRootPart") then return nil end
		return model.HumanoidRootPart
	end

	local function clearConnections()
		for _, conn in ipairs(characterConnections) do
			pcall(function() conn:Disconnect() end)
		end
		characterConnections = {}
	end

	local function getPredictedPosition(hrp)
		if not hrp then return nil end

		local humanoid = hrp.Parent:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return hrp.Position
		end

		if not PredictionEnabled or humanoid.WalkSpeed < 5 then
			return hrp.Position
		end

		return hrp.Position + (hrp.Velocity * PredictionAmount)
	end

	local function createMiniToggle(name, position, stateVarRef, realVarSetter)
		local playerGui = player:WaitForChild("PlayerGui")
		if playerGui:FindFirstChild(name .. "MiniToggleGuiS") then
			playerGui[name .. "MiniToggleGuiS"]:Destroy()
		end
		
		local screenGui = Instance.new("ScreenGui")
		screenGui.Name = name .. "MiniToggleGuiS"
		screenGui.ResetOnSpawn = false
		screenGui.Parent = player:WaitForChild("PlayerGui")

		local button = Instance.new("TextButton")
		button.Size = UDim2.new(0, 70, 0, 40) 
		button.Position = position
		button.Text = name .. (stateVarRef.value and " ON" or " OFF")
		button.TextScaled = true
		button.TextWrapped = false
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
		button.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
		button.BorderSizePixel = 0
		button.Parent = screenGui

		local uicorner = Instance.new("UICorner")
		uicorner.CornerRadius = UDim.new(0, 8)
		uicorner.Parent = button

		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 100, 50)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 200, 50))
		}
		gradient.Rotation = 45
		gradient.Parent = button

		local function updateUI(state)
			button.Text = name .. (state and " ON" or " OFF")
			gradient.Color = ColorSequence.new{
				ColorSequenceKeypoint.new(0, state and Color3.fromRGB(50, 200, 50) or Color3.fromRGB(255, 100, 50)),
				ColorSequenceKeypoint.new(1, state and Color3.fromRGB(50, 255, 50) or Color3.fromRGB(255, 200, 50))
			}
		end

		button.MouseButton1Click:Connect(function()
			stateVarRef.value = not stateVarRef.value
			realVarSetter(stateVarRef.value)
			updateUI(stateVarRef.value)
		end)

		-- =========================
		-- Dragging functionality
		-- =========================
		local dragging = false
		local dragStart = nil
		local startPos = nil

		local function onInputBegan(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = true
				dragStart = input.Position
				startPos = button.Position
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						dragging = false
					end
				end)
			end
		end

		local function onInputChanged(input)
			if dragging and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) then
				local delta = input.Position - dragStart
				button.Position = UDim2.new(
					0,
					math.clamp(startPos.X.Offset + delta.X, 0, camera.ViewportSize.X - button.AbsoluteSize.X),
					0,
					math.clamp(startPos.Y.Offset + delta.Y, 0, camera.ViewportSize.Y - button.AbsoluteSize.Y)
				)
			end
		end

		button.InputBegan:Connect(onInputBegan)
		button.InputChanged:Connect(onInputChanged)

		updateUI(stateVarRef.value)
		return screenGui
	end

	-- =========================
	-- Team Check
	-- =========================
	local function isAllyWithMe(targetplayer)
		local myGui = player:FindFirstChild("PlayerGui")
		if not myGui then return false end

		local scrolling = myGui:FindFirstChild("Main")
			and myGui.Main:FindFirstChild("Allies")
			and myGui.Main.Allies:FindFirstChild("Container")
			and myGui.Main.Allies.Container:FindFirstChild("Allies")
			and myGui.Main.Allies.Container.Allies:FindFirstChild("ScrollingFrame")

		if scrolling then
			for _, frame in pairs(scrolling:GetDescendants()) do
				if frame:IsA("ImageButton") and frame.Name == targetplayer.Name then
					return true
				end
			end
		end

		return false
	end

	local function isEnemy(targetplayer)
		if not targetplayer or targetplayer == player then
			return false
		end

		local myTeam = player.Team
		local targetTeam = targetplayer.Team

		if myTeam and targetTeam then
			if myTeam.Name == "Pirates" and targetTeam.Name == "Marines" then
				return true
			elseif myTeam.Name == "Marines" and targetTeam.Name == "Pirates" then
				return true
			end

			if myTeam.Name == "Pirates" and targetTeam.Name == "Pirates" then
				if isAllyWithMe(targetplayer) then
					return false -- ally, not enemy
				end
				return true
			end

			if myTeam.Name == "Marines" and targetTeam.Name == "Marines" then
				return false
			end
		end

		return true
	end

	local function getClosestplayer(lpHRP)
		if not lpHRP then return nil end
		
		local closest = nil
		local closestDist = math.huge
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl ~= player and isEnemy(pl) and pl.Character and pl.Character.Parent ~= nil then
				local hum = pl.Character:FindFirstChildWhichIsA("Humanoid")
				local hrp = getHRP(pl.Character)
				if hum and hum.Health > 0 and hrp then
					local dist = (hrp.Position - lpHRP.Position).Magnitude
					if dist <= maxRange and dist < closestDist then
						closestDist = dist
						closest = pl
					end
				end
			end
		end
		return closest
	end

	local function getClosestNPC(lpHRP)
		if not lpHRP then return nil end

		local enemiesFolder = workspace:FindFirstChild("Enemies")
		if not enemiesFolder then return nil end

		local closest = nil
		local closestDist = math.huge
		for _, npc in ipairs(enemiesFolder:GetChildren()) do
			if npc:IsA("Model") then
				local hum = npc:FindFirstChildWhichIsA("Humanoid")
				local hrp = getHRP(npc)
				if hum and hum.Health > 0 and hrp then
					local dist = (hrp.Position - lpHRP.Position).Magnitude
					if dist <= maxRange and dist < closestDist then
						closestDist = dist
						closest = npc
					end
				end
			end
		end
		return closest
	end

	local function applyHighlight(targetModel, targetType)
		if not HighlightEnabled then return end
		if not targetModel then return end
		if currentHighlight and currentHighlight.Adornee == targetModel then return end

		if currentHighlight then  
			currentHighlight:Destroy()  
			currentHighlight = nil  
			currentTargetType = nil  
		end  

		local hl = Instance.new("Highlight")  
		hl.FillColor = Color3.fromRGB(255, 255, 0)  
		hl.OutlineColor = Color3.fromRGB(255, 255, 0)  
		hl.FillTransparency = 0.5  
		hl.OutlineTransparency = 0  
		hl.Adornee = targetModel  
		hl.Parent = targetModel  
		currentHighlight = hl  
		currentTargetType = targetType

		VSkillModule:CheckVSkillUsage(SilentAimModule)
	end

	local function clearHighlight()
		if currentHighlight then
			currentHighlight:Destroy()
			currentHighlight = nil
			currentTargetType = nil
		end
	end

	local function isSkillReadyForTool(toolName)
		if not toolName then return false end
		local playerGui = player:FindFirstChild("PlayerGui")
		if not playerGui then return false end
		local skillsFolder = playerGui:FindFirstChild("Main") and playerGui.Main:FindFirstChild("Skills")
		if not skillsFolder then return false end
		local toolFrame = skillsFolder:FindFirstChild(toolName)
		if not toolFrame then return false end

		for _, skillKey in ipairs({"Z","X","C","V"}) do
			local skill = toolFrame:FindFirstChild(skillKey)
			if skill and skill:FindFirstChild("Cooldown") and skill.Cooldown:IsA("Frame") then
				local cooldownSize = skill.Cooldown.Size.X.Scale
				if cooldownSize == 1.0 then
					return true
				end
			end
		end
		return false
	end

	local function isNotDoughValidCondition()
		return (currentTool and currentTool.Name == "Dough-Dough")
	end

	local function isNotValidCondition()
		return (currentTool and currentTool.Name == "Lightning-Lightning")
		or (currentTool and currentTool.Name == "Portal-Portal")
	end

	local function startRenderLoop()
		if renderConnection then return end

		renderConnection = RunService.RenderStepped:Connect(function()
			local lpChar = player.Character
			if not lpChar then return end
			local lpHRP = lpChar:FindFirstChild("HumanoidRootPart")
			if not lpHRP then return end

			if not SilentAimPlayersEnabled and not SilentAimNPCsEnabled then
				return
			end

			local targetModel = nil
			local lookTargetPos = nil

			if SilentAimPlayersEnabled then
				local targetplayer = Selectedplayer or getClosestplayer(lpHRP)
				if targetplayer and targetplayer ~= player and targetplayer.Character then
					playersaimbot = targetplayer.Name
					local hrp = getHRP(targetplayer.Character)
					PlayersPosition = getPredictedPosition(hrp)
					lookTargetPos = PlayersPosition
					targetModel = targetplayer.Character
					applyHighlight(targetModel, "player")
				else
					playersaimbot, PlayersPosition = nil, nil
				end
			elseif currentTargetType == "player" then
				playersaimbot, PlayersPosition = nil, nil
				clearHighlight()
			end

			if SilentAimNPCsEnabled then  
				local closestNPC = getClosestNPC(lpHRP)  
				if closestNPC then  
					NPCaimbot = closestNPC.Name  
					local hrp = getHRP(closestNPC)  
					NPCPosition = getPredictedPosition(hrp)
					lookTargetPos = NPCPosition
					if not targetModel then  
						targetModel = closestNPC  
						applyHighlight(targetModel, "NPC")  
					end  
				else  
					NPCaimbot, NPCPosition = nil, nil  
				end
			elseif currentTargetType == "NPC" then
				NPCaimbot, NPCPosition = nil, nil  
				clearHighlight()
			end
			if currentTool and lookTargetPos and isSkillReadyForTool(currentTool.Name) and not isNotDoughValidCondition() then
				local lookVector = (Vector3.new(lookTargetPos.X, lpHRP.Position.Y, lookTargetPos.Z) - lpHRP.Position).Unit
					lpHRP.CFrame = CFrame.new(lpHRP.Position, lpHRP.Position + lookVector)
			end
		end)
	end

	local function stopRenderLoop()
		if renderConnection then
			renderConnection:Disconnect()
			renderConnection = nil
		end
	end

	local function hookTool(tool)
		currentTool = tool
		table.insert(characterConnections, tool.AncestryChanged:Connect(function(_, parent)
			if not parent then
				currentTool = nil
			end
		end))
	end

	local function isValidCondition()
		return (currentTool and currentTool.Name == "Buddy Sword")
	end

	spawn(function()
		local ok, hookMeta = pcall(getrawmetatable, game)
		if ok and hookMeta then
			setreadonly(hookMeta, false)
			local OldHook
			OldHook = hookmetamethod(game, "__namecall", function(self, V1, V2, ...)
				local Method = (getnamecallmethod and getnamecallmethod():lower()) or ""

				if tostring(self) == "RemoteEvent" and Method == "fireserver" then
					if typeof(V1) == "Vector3" then
						if SilentAimPlayersEnabled and PlayersPosition then
							return OldHook(self, PlayersPosition, V2, ...)
						elseif SilentAimNPCsEnabled and NPCPosition then
							return OldHook(self, NPCPosition, V2, ...)
						end
					end				
					if type(V1) == "string" and table.find(Booms, V1) then
						if ZSkillorM1 then 
							if SilentAimPlayersEnabled and PlayersPosition then
								return OldHook(self, V1, PlayersPosition, nil, ...)
							elseif SilentAimNPCsEnabled and NPCPosition then
								return OldHook(self, V1, NPCPosition, nil, ...)
							end
						end
					end   
				elseif Method == "invokeserver" then  
					if isValidCondition() then
						if type(V1) == "string" and table.find(Skills, V1) then  
							if SilentAimPlayersEnabled and PlayersPosition then  
								return OldHook(self, V1, PlayersPosition, nil, ...)
							elseif SilentAimNPCsEnabled and NPCPosition then
								return OldHook(self, V1, NPCPosition, nil, ...)
							end  
						end    
					end				
				end
				
				return OldHook(self, V1, V2, ...)
			end)
			setreadonly(hookMeta, true)
		end
	end)

	if not isNotValidCondition() then
		if MouseModule and typeof(MouseModule) == "Instance" then
			local ok2, okResult = pcall(function()
				return require(MouseModule)
			end)

			if ok2 and okResult then  
				if type(okResult) == "table" then  
					Mouse = okResult  
				else  
					Mouse = nil  
				end  
			else  
				Mouse = nil  
			end  

			if Mouse then  
				local Character = player.Character or player.CharacterAdded:Wait()  
				local RootPart = Character and Character:FindFirstChild("HumanoidRootPart")  

				if RootPart then  
					pcall(function()  
						if type(Mouse) == "table" then  
							Mouse.Hit = CFrame.new(RootPart.Position)  
							Mouse.Target = RootPart  
						end  
					end)  
				else  
					task.spawn(function()  
						local Character = player.Character or player.CharacterAdded:Wait()  
						local RootPart = Character:WaitForChild("HumanoidRootPart")  
						pcall(function()  
							if type(Mouse) == "table" then  
								Mouse.Hit = CFrame.new(RootPart.Position)  
								Mouse.Target = RootPart  
							end  
						end)  
					end)  
				end  
			end  

			RunService.Heartbeat:Connect(function()  	        
				if not ZSkillorM1 or (not SilentAimPlayersEnabled and not SilentAimNPCsEnabled) then
					return
				end
			
				if Mouse and ZSkillorM1 and (SilentAimPlayersEnabled or SilentAimNPCsEnabled) then  
					local targetCFrame = nil  

					if PlayersPosition then  
						targetCFrame = CFrame.new(PlayersPosition)  
					elseif NPCPosition then  
						targetCFrame = CFrame.new(NPCPosition)  
					end  

					if targetCFrame then  
						pcall(function()  
							if type(Mouse) == "table" then  
								Mouse.Hit = targetCFrame  
								Mouse.Target = nil  
							end  
						end)  

						if MouseModule then  
							local ok, MouseData = pcall(require, MouseModule)  
							if ok and type(MouseData) == "table" then  
								MouseData.Hit = targetCFrame  
								MouseData.Target = nil  
							end  
						end  
					end  
				end  
			end)
		end
	end

	local HasTag = function(tagName)
	local char = player.Character
	if (not char) then return false; end
	return Services.CollectionService:HasTag(char, tagName);
	end

	local function startAutoKenLoop()
		if autoKenRunning then return end
		autoKenRunning = true

		task.spawn(function()
			while AutoKen do
				task.wait(0.1)

				if HasTag("Ken") then
					local playerGui = player:FindFirstChild("PlayerGui")
					if playerGui then
						local kenButton = playerGui:FindFirstChild("MobileContextButtons")
						and playerGui.MobileContextButtons.ContextButtonFrame:FindFirstChild("BoundActionKen")

						if kenButton and kenButton:GetAttribute("Selected") ~= true then
							kenButton:SetAttribute("Selected", true)
						end
					end

					local observationManager = getrenv()._G.OM
					if observationManager and not observationManager.active then
						observationManager.radius = 0
						observationManager:setActive(true)
						commE:FireServer("Ken", true)
					end
				end
			end
			autoKenRunning = false
		end)
	end

	local function onCharacterAdded(char)
		clearConnections()

		for _, child in ipairs(char:GetChildren()) do
			if child:IsA("Tool") then
				hookTool(child)
			end
		end

		table.insert(characterConnections, char.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then hookTool(child) end
		end))

		table.insert(characterConnections, char.ChildRemoved:Connect(function(child)
			if child == currentTool then
				currentTool = nil
			end
		end))
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then onCharacterAdded(player.Character) end

	function SilentAimModule:SetAutoKen(state)
		AutoKen = state

		if state then
			startAutoKenLoop()
		end
	end

	function SilentAimModule:SetZSkillorM1(state)
		ZSkillorM1 = state
	end

	function SilentAimModule:Pause()
		SilentAimPlayersEnabled = false
		SilentAimNPCsEnabled = false
	end

	function SilentAimModule:Restore()
		SilentAimPlayersEnabled = UserWantsplayerAim
		SilentAimNPCsEnabled = UserWantsNPCAim
	end

	function SilentAimModule:IsplayerAimEnabled()
		return SilentAimPlayersEnabled
	end

	function SilentAimModule:IsNPCAimEnabled()
		return SilentAimNPCsEnabled
	end

	function SilentAimModule:SetDistanceLimit(num)
		if typeof(num) == "number" then
			maxRange = num
		end
	end

	function SilentAimModule:SetSelectedPlayer(playerName)
		if not playerName or playerName == "" then
			Selectedplayer = nil
			return
		end

		local found = Players:FindFirstChild(playerName)
		if found then
			Selectedplayer = found
		end
	end

	function SilentAimModule:GetSelectedPlayer()
		return Selectedplayer and Selectedplayer.Name or "None"
	end

	function SilentAimModule:SetPrediction(state)
		PredictionEnabled = state
	end

	function SilentAimModule:SetHighlight(state)
		HighlightEnabled = state
		if not state then
			clearHighlight()
		end
	end

	function SilentAimModule:IsHighlightEnabled()
		return HighlightEnabled
	end

	function SilentAimModule:SetPredictionAmount(num)
		if typeof(num) == "number" then
			PredictionAmount = num
		end
	end

	function SilentAimModule:SetPlayerSilentAim(state)
		UserWantsplayerAim = state
		SilentAimPlayersEnabled = state

		if state then
			startRenderLoop()
		else
			if not SilentAimNPCsEnabled then
				stopRenderLoop()
			end
		end
	end

	function SilentAimModule:SetNPCSilentAim(state)
		UserWantsNPCAim = state
		SilentAimNPCsEnabled = state

		if state then
			startRenderLoop()
		else
			if not SilentAimPlayersEnabled then
				stopRenderLoop()
			end
		end
	end

	local function UpdateSilentAimState()
		SilentAimPlayersEnabled = MiniPlayerState and MiniPlayerState.value or false
		SilentAimNPCsEnabled    = MiniNpcState and MiniNpcState.value or false

		UserWantsplayerAim = SilentAimPlayersEnabled
		UserWantsNPCAim    = SilentAimNPCsEnabled

		if SilentAimPlayersEnabled or SilentAimNPCsEnabled then
			startRenderLoop()
		else
			stopRenderLoop()
			clearHighlight()
		end
	end

	function SilentAimModule:SetMiniTogglePlayerSilentAim(state)
		if not MiniPlayerCreated and state then
			MiniPlayerState = { value = SilentAimPlayersEnabled }
			MiniPlayerGui = createMiniToggle("Player", UDim2.new(0,10,0,90), MiniPlayerState, function(val)
				MiniPlayerState.value = val
				UpdateSilentAimState()
			end)
			MiniPlayerCreated = true
		elseif MiniPlayerCreated then
			if MiniPlayerGui then
				MiniPlayerGui.Enabled = state
			end
		end
	end

	function SilentAimModule:SetMiniToggleNpcSilentAim(state)
		if not MiniNpcCreated and state then
			MiniNpcState = { value = SilentAimNPCsEnabled }
			MiniNpcGui = createMiniToggle("NPC", UDim2.new(0,10,0,50), MiniNpcState, function(val)
				MiniNpcState.value = val
				UpdateSilentAimState()
			end)
			MiniNpcCreated = true
		elseif MiniNpcCreated then
			if MiniNpcGui then
				MiniNpcGui.Enabled = state
			end
		end
	end

	return SilentAimModule



]===]


local StuffsModule_Source = [===[
    local StuffsModule = {}

	local PingsOrFpsEnabled = false
	local Players = game:GetService("Players")
	local LocalPlayer = Players.LocalPlayer
	local RunService = game:GetService("RunService")
	local Workspace = game:GetService("Workspace")
	local waterPart = Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild("WaterBase-Plane")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local UserInputService = game:GetService("UserInputService")
	local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
	local Lighting = game:GetService("Lighting")
	local Terrain = Workspace:FindFirstChildOfClass("Terrain")
	local VirtualInputManager = game:GetService("VirtualInputManager")
	local Modules = ReplicatedStorage:WaitForChild("Modules")
	local Net = Modules:WaitForChild("Net")
	local RegisterAttack = Net:WaitForChild("RE/RegisterAttack")
	local RegisterHit = Net:WaitForChild("RE/RegisterHit")
	local ShootGunEvent = Net:WaitForChild("RE/ShootGunEvent")
	local GunValidator = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Validator2")

	local ScreenGui
	local FpsPingLabel
	local FpsBoostEnabled = false
	local InfiniteEnergy = false
	local FastAttackEnabled = false
	local WalkWaterEnabled = false
	local fog = false
	local Lava = false

	local fastConn
	local energyConnection
	local fpsBoostConn

	local savedSettings = {}
	local connections = {}

	local function createGui()
		if ScreenGui then return end 

		ScreenGui = Instance.new("ScreenGui")
		ScreenGui.Name = "FpsPingGui"
		ScreenGui.ResetOnSpawn = false
		ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

		FpsPingLabel = Instance.new("TextLabel")
		FpsPingLabel.Name = "FpsPingLabel"
		FpsPingLabel.Size = UDim2.new(0, 120, 0, 20)
		FpsPingLabel.Position = UDim2.new(1, -10, 0, 10)
		FpsPingLabel.AnchorPoint = Vector2.new(1, 0) 
		FpsPingLabel.BackgroundTransparency = 1
		FpsPingLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		FpsPingLabel.Font = Enum.Font.SourceSansBold
		FpsPingLabel.TextSize = 18
		FpsPingLabel.TextXAlignment = Enum.TextXAlignment.Right
		FpsPingLabel.RichText = true
		FpsPingLabel.Parent = ScreenGui
	end

	local lastTime = tick()
	local frameCount = 0
	local fps = 0
	local fpsConn

	local function startFPSLoop()
		if fpsConn then return end
		
		fpsConn = RunService.RenderStepped:Connect(function(deltaTime)
			if not PingsOrFpsEnabled then
				ScreenGui.Enabled = false
				return
			end
			
			createGui()
			ScreenGui.Enabled = true
			
			frameCount = frameCount + 1
			if tick() - lastTime >= 1 then
				fps = frameCount
				frameCount = 0
				lastTime = tick()
			end

			local ping = math.floor(LocalPlayer:GetNetworkPing() * 2000)

			local fpsColor
			if fps >= 50 then
				fpsColor = "00FF00"
			elseif fps >= 30 then
				fpsColor = "FFA500"
			else
				fpsColor = "FF0000"
			end

			local pingColor
			if ping <= 80 then
				pingColor = "00FF00"
			elseif ping <= 150 then
				pingColor = "FFFF00"
			else
				pingColor = "FF0000"
			end

			FpsPingLabel.Text = string.format(
				'<font color="#%s">FPS: %d</font>  |  <font color="#%s">Ping: %dms</font>',
				fpsColor,
				fps,
				pingColor,
				ping
			)
		end)
	end

	local function stopFPSLoop()
		if fpsConn then
			fpsConn:Disconnect()
			fpsConn = nil
		end
	end

	local function FPSBoost()
		Lighting.FogEnd = 1e9
		Lighting.FogStart = 1e9
		Lighting.ClockTime = 12
		Lighting.GlobalShadows = false
		Lighting.Brightness = 2
		Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)

		if Terrain then
			Terrain.WaterWaveSize = 0
			Terrain.WaterWaveSpeed = 0
			Terrain.WaterReflectance = 0
			Terrain.WaterTransparency = 1
		end
		
		for _, v in ipairs(Workspace:GetDescendants()) do
			if v:IsA("Part") or v:IsA("UnionOperation") or v:IsA("MeshPart") or v:IsA("CornerWedgePart") or v:IsA("TrussPart") then
				v.Material = Enum.Material.SmoothPlastic
				v.Reflectance = 0
			elseif v:IsA("Decal") or v:IsA("Texture") then  
				v:Destroy()
			elseif v:IsA("ParticleEmitter") then
				v.Lifetime = NumberRange.new(0, 0)
			elseif v:IsA("Trail") then
				v.Lifetime = 0
			elseif v:IsA("Explosion") then
				v.BlastPressure = 1
				v.BlastRadius = 1
			elseif v:IsA("BasePart") then
				v.CastShadow = false
			elseif v:IsA("Fire") or v:IsA("SpotLight") or v:IsA("Smoke") then
				v.Enabled = false
			end
		end
		
		if fpsBoostConn then
			fpsBoostConn:Disconnect()
			fpsBoostConn = nil
		end
		
		fpsBoostConn = Workspace.DescendantAdded:Connect(function(v)
			task.wait(0.1)
			if v:IsA("ParticleEmitter") then
				v.Lifetime = NumberRange.new(0, 0)
			elseif v:IsA("Trail") then
				v.Lifetime = 0
			elseif v:IsA("Explosion") then
				v.BlastPressure = 1
				v.BlastRadius = 1
			elseif v:IsA("BasePart") then
				v.CastShadow = false
			elseif v:IsA("Fire") or v:IsA("SpotLight") or v:IsA("Smoke") then
				v.Enabled = false
			end
		end)
	end

	do
		if fog then
			local c = game.Lighting
			c.FogEnd = 100000
			for r, v in pairs(c:GetDescendants()) do
				if v:IsA("Atmosphere") then
					v:Destroy()
				end
			end
		end
	end

	do
		if Lava then
			for i, v in pairs(game.Workspace:GetDescendants()) do
				if v.Name == "Lava" then
					v:Destroy();
				end;
			end;
			for i, v in pairs(game.ReplicatedStorage:GetDescendants()) do
				if v.Name == "Lava" then
					v:Destroy();
				end;
			end;
		end
	end

	local function infinitestam(state)
		InfiniteEnergy = state
		
		local character = LocalPlayer.Character
		if not character then return end
		
		local energy = character:FindFirstChild("Energy")
		if not energy then return end

		if not state then
			if energyConnection then
				energyConnection:Disconnect()
				energyConnection = nil
			end
			return
		end
		
		if not energyConnection then
			energyConnection = energy.Changed:Connect(function()
				if InfiniteEnergy then
					energy.Value = energy.MaxValue
				end
			end)
		end
	end

	local Config = {
		AttackDistance = 200,
		AttackMobs = true,
		AttackPlayers = true,
		AttackCooldown = 0.001,
		ComboResetTime = 0.001,
		MaxCombo = 2,
		HitboxLimbs = {"RightLowerArm", "RightUpperArm", "LeftLowerArm", "LeftUpperArm", "RightHand", "LeftHand"},
		AutoClickEnabled = true
	}

	local FastAttack = {}
	FastAttack.__index = FastAttack

	function FastAttack.new()
		local self = setmetatable({
			Debounce = 0,
			ComboDebounce = 0,
			ShootDebounce = 0,
			M1Combo = 0,
			EnemyRootPart = nil,
			Connections = {},
			Overheat = {
				Dragonstorm = {
					Cooldown = 0,
					Distance = 350,
				}
			},
		}, FastAttack)
		
		pcall(function()
			self.CombatFlags = require(Modules.Flags).COMBAT_REMOTE_THREAD
			self.ShootFunction = getupvalue(require(ReplicatedStorage.Controllers.CombatController).Attack, 9)
			local LocalScript = LocalPlayer:WaitForChild("PlayerScripts"):FindFirstChildOfClass("LocalScript")
			if LocalScript and getsenv then
				self.HitFunction = getsenv(LocalScript)._G.SendHitsToServer
			end
		end)
		
		return self
	end

	function FastAttack:IsEntityAlive(entity)
		local humanoid = entity and entity:FindFirstChild("Humanoid")
		return humanoid and humanoid.Health > 0
	end

	function FastAttack:CheckStun(Character, Humanoid, ToolTip)
		local Stun = Character:FindFirstChild("Stun")
		local Busy = Character:FindFirstChild("Busy")
		if Humanoid.Sit and (ToolTip == "Sword" or ToolTip == "Melee" or ToolTip == "Blox Fruit") then
			return false
		elseif Stun and Stun.Value > 0 or Busy and Busy.Value then
			return false
		end
		return true
	end

	function FastAttack:GetBladeHits(Character, Distance)
		local Position = Character:GetPivot().Position
		local BladeHits = {}
		Distance = Distance or Config.AttackDistance
		
		local function ProcessTargets(Folder, CanAttack)
			for _, Enemy in ipairs(Folder:GetChildren()) do
				if Enemy ~= Character and self:IsEntityAlive(Enemy) then
					local BasePart = Enemy:FindFirstChild(Config.HitboxLimbs[math.random(#Config.HitboxLimbs)]) or Enemy:FindFirstChild("HumanoidRootPart")
					if BasePart and (Position - BasePart.Position).Magnitude <= Distance then
						if not self.EnemyRootPart then
							self.EnemyRootPart = BasePart
						else
							table.insert(BladeHits, {Enemy, BasePart})
						end
					end
				end
			end
		end
		
		if Config.AttackMobs then ProcessTargets(Workspace.Enemies) end
		if Config.AttackPlayers then ProcessTargets(Workspace.Characters, true) end
		
		return BladeHits
	end

	function FastAttack:GetClosestEnemy(Character, Distance)
		local BladeHits = self:GetBladeHits(Character, Distance)
		local Closest, MinDistance = nil, math.huge
		
		for _, Hit in ipairs(BladeHits) do
			local Magnitude = (Character:GetPivot().Position - Hit[2].Position).Magnitude
			if Magnitude < MinDistance then
				MinDistance = Magnitude
				Closest = Hit[2]
			end
		end
		return Closest
	end

	function FastAttack:GetCombo()
		local Combo = (tick() - self.ComboDebounce) <= Config.ComboResetTime and self.M1Combo or 0
		Combo = Combo >= Config.MaxCombo and 1 or Combo + 1
		self.ComboDebounce = tick()
		self.M1Combo = Combo
		return Combo
	end

	function FastAttack:ShootInTarget(TargetPosition)
		local Character = LocalPlayer.Character
		if not self:IsEntityAlive(Character) then return end
		
		local Equipped = Character:FindFirstChildOfClass("Tool")
		if not Equipped or Equipped.ToolTip ~= "Gun" then return end
		
		local Cooldown = Equipped:FindFirstChild("Cooldown") and Equipped.Cooldown.Value or 0.3
		if (tick() - self.ShootDebounce) < Cooldown then return end
		
		local ShootType = self.SpecialShoots[Equipped.Name] or "Normal"
		if ShootType == "Position" or (ShootType == "TAP" and Equipped:FindFirstChild("RemoteEvent")) then
			Equipped:SetAttribute("LocalTotalShots", (Equipped:GetAttribute("LocalTotalShots") or 0) + 1)
			GunValidator:FireServer(self:GetValidator2())
			
			if ShootType == "TAP" then
				Equipped.RemoteEvent:FireServer("TAP", TargetPosition)
			else
				ShootGunEvent:FireServer(TargetPosition)
			end
			self.ShootDebounce = tick()
		else
			self.ShootDebounce = tick()
		end
	end

	function FastAttack:GetValidator2()
		local v1 = getupvalue(self.ShootFunction, 15)
		local v2 = getupvalue(self.ShootFunction, 13)
		local v3 = getupvalue(self.ShootFunction, 16)
		local v4 = getupvalue(self.ShootFunction, 17)
		local v5 = getupvalue(self.ShootFunction, 14)
		local v6 = getupvalue(self.ShootFunction, 12)
		local v7 = getupvalue(self.ShootFunction, 18)
		
		local v8 = v6 * v2
		local v9 = (v5 * v2 + v6 * v1) % v3
		v9 = (v9 * v3 + v8) % v4
		v5 = math.floor(v9 / v3)
		v6 = v9 - v5 * v3
		v7 = v7 + 1
		
		setupvalue(self.ShootFunction, 15, v1)
		setupvalue(self.ShootFunction, 13, v2)
		setupvalue(self.ShootFunction, 16, v3)
		setupvalue(self.ShootFunction, 17, v4)
		setupvalue(self.ShootFunction, 14, v5)
		setupvalue(self.ShootFunction, 12, v6)
		setupvalue(self.ShootFunction, 18, v7)
		
		return math.floor(v9 / v4 * 16777215), v7
	end

	function FastAttack:UseNormalClick(Character, Humanoid, Cooldown)
		self.EnemyRootPart = nil
		local BladeHits = self:GetBladeHits(Character)
		
		if self.EnemyRootPart then
			RegisterAttack:FireServer(Cooldown)
			if self.CombatFlags and self.HitFunction then
				self.HitFunction(self.EnemyRootPart, BladeHits)
			else
				RegisterHit:FireServer(self.EnemyRootPart, BladeHits)
			end
		end
	end

	function FastAttack:UseFruitM1(Character, Equipped, Combo)
		local range = Config.AttackDistance
		local Targets = self:GetBladeHits(Character, range)
		if not Targets[1] then return end

		local Direction = (Targets[1][2].Position - Character:GetPivot().Position).Unit
		Equipped.LeftClickRemote:FireServer(Direction, Combo)
	end

	function FastAttack:Attack()
		if not Config.AutoClickEnabled or (tick() - self.Debounce) < Config.AttackCooldown then return end
		local Character = LocalPlayer.Character
		if not Character or not self:IsEntityAlive(Character) then return end
		
		local Humanoid = Character.Humanoid
		local Equipped = Character:FindFirstChildOfClass("Tool")
		if not Equipped then return end
		
		local ToolTip = Equipped.ToolTip
		if not table.find({"Melee", "Blox Fruit", "Sword", "Gun"}, ToolTip) then return end
		
		local Cooldown = Equipped:FindFirstChild("Cooldown") and Equipped.Cooldown.Value or Config.AttackCooldown
		if not self:CheckStun(Character, Humanoid, ToolTip) then return end
		
		local Combo = self:GetCombo()
		Cooldown = Cooldown + (Combo >= Config.MaxCombo and 0.05 or 0)
		self.Debounce = Combo >= Config.MaxCombo and ToolTip ~= "Gun" and (tick() + 0.05) or tick()
		
		if ToolTip == "Blox Fruit" and Equipped:FindFirstChild("LeftClickRemote") then
			self:UseFruitM1(Character, Equipped, Combo)
		elseif ToolTip == "Gun" then
			local Target = self:GetClosestEnemy(Character, 120)
			if Target then
				self:ShootInTarget(Target.Position)
			end
		else
			self:UseNormalClick(Character, Humanoid, Cooldown)
		end
	end

	local AttackInstance = FastAttack.new()
	local function startFastAttack()
		if fastConn then return end
		fastConn = RunService.Stepped:Connect(function()
			if FastAttackEnabled then
				AttackInstance:Attack()
			end
		end)
	end

	local function stopFastAttack()
		if fastConn then
			fastConn:Disconnect()
			fastConn = nil
		end
	end

	LocalPlayer.CharacterAdded:Connect(function()
		task.wait(1)
		infinitestam()
	end)

	if LocalPlayer.Character then
		infinitestam()
	end

	function StuffsModule:SetFpsBoost(state)
		FpsBoostEnabled = state
		if state then
			FPSBoost()
		else
			if fpsBoostConn then
				fpsBoostConn:Disconnect()
				fpsBoostConn = nil
			end
		end
	end

	function StuffsModule:SetINFEnergy(state)
		infinitestam(state)
	end

	function StuffsModule:SetFog(state)
		fog = state
	end

	function StuffsModule:SetLava(state)
		Lava = state
	end

	function StuffsModule:SetRejoinServer(state)
		game:GetService("TeleportService"):Teleport(game.PlaceId, game:GetService("Players").LocalPlayer)
	end

	function StuffsModule:SetFastAttack(state)
		FastAttackEnabled = state
		if state then
			startFastAttack()
		else
			stopFastAttack()
		end
	end

	function StuffsModule:SetWalkWater(state)
		WalkWaterEnabled = state
		if WalkWaterEnabled then
			waterPart.Size = Vector3.new(1000,110,1000)
		else
			waterPart.Size = Vector3.new(1000,80,1000)
		end
	end

	function StuffsModule:SetPingsOrFps(state)
		PingsOrFpsEnabled = state
		if state then
			startFPSLoop()
		else
			stopFPSLoop()
		end
	end

	return StuffsModule
]===]

local UiSettingsModule_Source = [===[
    local UiSettingsModule = {}

	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local RunService = game:GetService("RunService")
	local TweenService = game:GetService("TweenService")
	local character = player.Character or player.CharacterAdded:Wait()
	local hrp = character:WaitForChild("HumanoidRootPart")
	local fillFrame = player:WaitForChild("PlayerGui"):WaitForChild("Main"):WaitForChild("RaceEnergy"):WaitForChild("Fill")

	local V4Enabled = false
	local FruitCheck = false
	local TeleportFruit = false
	local sizeConn 
	local fruitLoop = nil
	local teleportLoop = nil

	-- =========================
	-- Theme Data & Functions
	-- =========================
	UiSettingsModule.currentTheme = {
		SchemeColor = Color3.fromRGB(64, 64, 64),
		Background = Color3.fromRGB(0, 0, 0),
		Header = Color3.fromRGB(0, 0, 0),
		TextColor = Color3.fromRGB(255, 255, 255),
		ElementColor = Color3.fromRGB(20, 20, 20)
	}

	UiSettingsModule.themes = {
		Red = Color3.fromRGB(220, 59, 48),
		Green = Color3.fromRGB(48, 209, 88),
		Purple = Color3.fromRGB(175, 82, 222),
		Orange = Color3.fromRGB(255, 149, 0),
		Pink = Color3.fromRGB(220, 105, 180),
		Yellow = Color3.fromRGB(220, 204, 0),
		Cyan = Color3.fromRGB(0, 220, 220),
		Dark = Color3.fromRGB(100, 100, 100),
		White = Color3.fromRGB(220, 220, 220),
		Teal = Color3.fromRGB(64, 224, 208),
		Lime = Color3.fromRGB(191, 220, 0),
		Indigo = Color3.fromRGB(75, 0, 130)
	}

	UiSettingsModule.backgroundThemes = {
		Blood = Color3.fromRGB(150, 40, 40),
		Grape = Color3.fromRGB(120, 80, 140),
		Ocean = Color3.fromRGB(70, 100, 160),
		Synapse = Color3.fromRGB(90, 100, 90),
		Pink = Color3.fromRGB(200, 100, 150),
		Midnight = Color3.fromRGB(60, 80, 110),
		Sentinel = Color3.fromRGB(80, 80, 80),
		Dark = Color3.fromRGB(60, 60, 60),
		Light = Color3.fromRGB(200, 200, 200),
		Serpent = Color3.fromRGB(70, 90, 90)
	}

	function UiSettingsModule:updateSchemeColor(newColor, Library)
		self.currentTheme.SchemeColor = newColor
		local h, s, v = newColor:ToHSV()
		self.currentTheme.Header = Color3.fromHSV(h, s * 0.6, v * 0.3)
		self.currentTheme.ElementColor = Color3.fromHSV(h, s * 0.4, v * 0.2)
		Library:ChangeColor(self.currentTheme)
	end

	function UiSettingsModule:updateBackgroundColor(newColor, Library)
		self.currentTheme.Background = newColor
		Library:ChangeColor(self.currentTheme)
	end

	function UiSettingsModule:updateTextColor(newColor, Library)
		self.currentTheme.TextColor = newColor
		Library:ChangeColor(self.currentTheme)
	end

	function UiSettingsModule:getThemeNames()
		local names = {}
		for name, _ in pairs(self.themes) do
			table.insert(names, name)
		end
		return names
	end

	function UiSettingsModule:getBackgroundThemeNames()
		local names = {}
		for name, _ in pairs(self.backgroundThemes) do
			table.insert(names, name)
		end
		return names
	end

	-- =========================
	-- Drag / Movable GUI
	-- =========================
	function UiSettingsModule:MakeDraggable(button)
		local UserInputService = game:GetService("UserInputService")
		local dragging, dragInput, dragStart, startPos

		local function update(input)
			local delta = input.Position - dragStart
			button.Position = UDim2.new(
			startPos.X.Scale,
				startPos.X.Offset + delta.X,
				startPos.Y.Scale,
				startPos.Y.Offset + delta.Y
			)
		end

		button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				dragStart = input.Position
				startPos = button.Position

				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						dragging = false
					end
				end)
			end
		end)

		button.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
				dragInput = input
			end
		end)

		UserInputService.InputChanged:Connect(function(input)
			if input == dragInput and dragging then
				update(input)
			end
		end)
	end

	local function getAwakenRemote()
		local backpack = player:WaitForChild("Backpack")
		local awakening = backpack:FindFirstChild("Awakening")
		if awakening then
			return awakening:FindFirstChild("RemoteFunction")
		end
		return nil
	end

	local function tryAwaken()
		local awakenRemote = getAwakenRemote()
		if awakenRemote and fillFrame.Size.X.Scale >= 0.9 then
			awakenRemote:InvokeServer(true)
		end
	end

	local function Tween(targetCFrame)
		if not targetCFrame then return end
		local info = TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
		local goal = {CFrame = hrp.CFrame + Vector3.new(0, 1, 0)}
		local tween = TweenService:Create(targetCFrame, info, goal)
		tween:Play()
	end

	local function startFruitLoop()
		if fruitLoop then return end

		fruitLoop = task.spawn(function()
			local notifiedFruits = {}

			while FruitCheck do
				task.wait(0.5)

				for _, v in pairs(workspace:GetChildren()) do
					if v:IsA("Tool") and not notifiedFruits[v] then
						notifiedFruits[v] = true
						setthreadcontext(5)
						require(game.ReplicatedStorage.Notification).new(v.Name .. " Spawned"):Display()
					end
				end

				for fruit in pairs(notifiedFruits) do
					if not fruit.Parent then
						notifiedFruits[fruit] = nil
					end
				end
			end

			fruitLoop = nil
		end)
	end

	local function startTeleportLoop()
		if teleportLoop then return end

		teleportLoop = task.spawn(function()
			while TeleportFruit do
				task.wait()
				for _, v in pairs(workspace:GetChildren()) do
					if v:IsA("Tool") and v:FindFirstChild("Handle") then
						Tween(v.Handle)
					end
				end
			end

			teleportLoop = nil
		end)
	end

	function UiSettingsModule:SetWalkSpeed(value)
		getgenv().WalkSpeedValue = value
		local player = game:GetService("Players").LocalPlayer

		local function applySpeed(char)
			local humanoid = char:WaitForChild("Humanoid")
			humanoid.WalkSpeed = value
			humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
				if humanoid.WalkSpeed ~= value then
					humanoid.WalkSpeed = value
				end
			end)
		end

		if player.Character then
			applySpeed(player.Character)
		end

		player.CharacterAdded:Connect(function(char)
			char:WaitForChild("Humanoid")
			applySpeed(char)
		end)
	end

	function UiSettingsModule:SetV4(state)
		V4Enabled = state
		
		if V4Enabled then
			if not sizeConn then
				sizeConn = fillFrame:GetPropertyChangedSignal("Size"):Connect(function()
					tryAwaken()
				end)
			end
		else
			if sizeConn then
				sizeConn:Disconnect()
				sizeConn = nil
			end
		end
	end

	function UiSettingsModule:SetFruitCheck(state)
		FruitCheck = state
		if state then
			startFruitLoop()
		end
	end

	function UiSettingsModule:SetTeleportFruit(state)
		TeleportFruit = state
		if state then
			startTeleportLoop()
		end
	end

	return UiSettingsModule
]===]

local ZSkillModule_Source = [===[
    local ZSkillModule = {}

	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local UserInputService = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	local PlayerGui = player:WaitForChild("PlayerGui")

	local currentTool = nil
	local godhumanZActive = false
	local dmgConn = nil
	local characterConnections = {}
	local rightTouchReleased = false
	local rightTouching = false
	local rightTouchTime = 0
	local aimlockActive = false
	local aimRenderConn = nil
	local aimTimeoutTask = nil
	local nearestTarget = nil
	local ZSkillsEnabled = false
	local TargetInfo = false 
	local uiConn = nil

	-- ========= SAFE DISCONNECT =========
	local function clearConnections()
		for _, conn in ipairs(characterConnections) do
			pcall(function() conn:Disconnect() end)
		end
		characterConnections = {}

		if dmgConn then
			pcall(function() dmgConn:Disconnect() end)
			dmgConn = nil
		end

		if aimRenderConn then
			pcall(function() aimRenderConn:Disconnect() end)
			aimRenderConn = nil
		end

		if aimTimeoutTask then
			pcall(function() task.cancel(aimTimeoutTask) end)
			aimTimeoutTask = nil
		end
	end

	-- ========= NEAREST TARGET FINDER =========
	local function isAllyWithMe(targetPlayer)
		local myGui = player:FindFirstChild("PlayerGui")
		if not myGui then return false end

		local scrolling = myGui:FindFirstChild("Main")
			and myGui.Main:FindFirstChild("Allies")
			and myGui.Main.Allies:FindFirstChild("Container")
			and myGui.Main.Allies.Container:FindFirstChild("Allies")
			and myGui.Main.Allies.Container.Allies:FindFirstChild("ScrollingFrame")

		if scrolling then
			for _, frame in pairs(scrolling:GetDescendants()) do
				if frame:IsA("ImageButton") and frame.Name == targetPlayer.Name then
					return true
				end
			end
		end

		return false
	end

	local function isEnemy(targetPlayer)
		if not targetPlayer or targetPlayer == player then
			return false
		end

		local myTeam = player.Team
		local targetTeam = targetPlayer.Team

		if myTeam and targetTeam then
			if myTeam.Name == "Pirates" and targetTeam.Name == "Marines" then
				return true
			elseif myTeam.Name == "Marines" and targetTeam.Name == "Pirates" then
				return true
			end

			if myTeam.Name == "Pirates" and targetTeam.Name == "Pirates" then
				if isAllyWithMe(targetPlayer) then
					return false -- ally, not enemy
				end
				return true
			end

			if myTeam.Name == "Marines" and targetTeam.Name == "Marines" then
				return false
			end
		end

		return true
	end

	local function GetNearestTarget(maxDistance)
		local lp = player
		local char = lp and lp.Character
		if not char or not char:FindFirstChild("HumanoidRootPart") then return nil end

		local hrp = char.HumanoidRootPart
		local closest, closestDist = nil, maxDistance or 100

		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= lp and isEnemy(plr) and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") and plr.Character:FindFirstChild("Humanoid") then
				local otherHRP = plr.Character.HumanoidRootPart
				local humanoid = plr.Character:FindFirstChild("Humanoid")
				if otherHRP and humanoid and humanoid.Health > 0 then
					local dist = (otherHRP.Position - hrp.Position).Magnitude
					if dist < closestDist then
						closest = plr.Character
						closestDist = dist
					end
				end
			end
		end

		return closest
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TargetUI"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = PlayerGui

	local targetFrame = Instance.new("Frame")
	targetFrame.Name = "TargetFrame"
	targetFrame.Size = UDim2.new(0.25, 0, 0.08, 0)
	targetFrame.Position = UDim2.new(0.5, 0, 0.05, 0)
	targetFrame.AnchorPoint = Vector2.new(0.5, 0)
	targetFrame.BackgroundTransparency = 1
	targetFrame.Visible = false
	targetFrame.Parent = screenGui

	local targetName = Instance.new("TextLabel")
	targetName.Name = "TargetName"
	targetName.Size = UDim2.new(1, 0, 0.5, 0)
	targetName.BackgroundTransparency = 1
	targetName.TextScaled = true
	targetName.Font = Enum.Font.GothamBold
	targetName.TextColor3 = Color3.new(1, 1, 1)
	targetName.Parent = targetFrame

	local hpBackground = Instance.new("Frame")
	hpBackground.Name = "HealthBarBackground"
	hpBackground.Size = UDim2.new(1, 0, 0.35, 0)
	hpBackground.Position = UDim2.new(0, 0, 0.55, 0)
	hpBackground.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	hpBackground.BorderSizePixel = 0
	hpBackground.Parent = targetFrame

	local hpFill = Instance.new("Frame")
	hpFill.Name = "HealthBarFill"
	hpFill.Size = UDim2.new(1, 0, 1, 0)
	hpFill.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
	hpFill.BorderSizePixel = 0
	hpFill.Parent = hpBackground

	-- ========= TOOL HOOK =========
	local function hookTool(tool)
		if not tool then return end
		currentTool = tool

		table.insert(characterConnections, tool.AncestryChanged:Connect(function(_, parent)
			if not parent then
				currentTool = nil
				godhumanZActive = false
				rightTouchReleased = false
				aimlockActive = false
			end
		end))
	end

	-- ========= STOP AIMLOCK =========
	local function stopAimlock(reason)
		if not aimlockActive then return end
		aimlockActive = false
		nearestTarget = nil
		godhumanZActive = false

		if aimRenderConn then
			pcall(function() aimRenderConn:Disconnect() end)
			aimRenderConn = nil
		end

		if aimTimeoutTask then
			pcall(function() task.cancel(aimTimeoutTask) end)
			aimTimeoutTask = nil
		end
	end

	-- ========= START AIMLOCK =========
	local function startAimlock()
		if not ZSkillsEnabled then return end
		if aimlockActive then return end

		nearestTarget = GetNearestTarget(1000)
		if not nearestTarget then return end

		aimlockActive = true

		aimRenderConn = RunService.RenderStepped:Connect(function()
			if not ZSkillsEnabled then
				stopAimlock("ZSkills disabled mid-aim")
				return
			end

			if aimlockActive and nearestTarget and nearestTarget:FindFirstChild("HumanoidRootPart") then
				local cam = workspace.CurrentCamera
				if cam then
					cam.CFrame = CFrame.lookAt(cam.CFrame.Position, nearestTarget.HumanoidRootPart.Position)
				end
			else
				stopAimlock("Lost target or inactive")
			end
		end)

		aimTimeoutTask = task.delay(1, function()
			if aimlockActive then
				stopAimlock("1s timeout")
			end
		end)
	end

	-- ========= WATCH DAMAGE COUNTER =========
	local function watchDamageCounter()
		if not ZSkillsEnabled then return end

		if dmgConn then
			pcall(function() dmgConn:Disconnect() end)
			dmgConn = nil
		end

		local gui = player:WaitForChild("PlayerGui"):WaitForChild("Main", 5)
		if not gui then return end

		local dmgCounter = gui:FindFirstChild("DmgCounter")
		if not dmgCounter then
			table.insert(characterConnections, gui.ChildAdded:Connect(function(child)
				if child.Name == "DmgCounter" then
					task.wait()
					watchDamageCounter()
				end
			end))
			return
		end

		local dmgTextLabel = dmgCounter:FindFirstChild("Text")
		if not dmgTextLabel then
			table.insert(characterConnections, dmgCounter.ChildAdded:Connect(function(child)
				if child.Name == "Text" then
					task.wait()
					watchDamageCounter()
				end
			end))
			return
		end

		dmgConn = dmgTextLabel:GetPropertyChangedSignal("Text"):Connect(function()
			if not ZSkillsEnabled then return end
			local dmgText = tonumber(dmgTextLabel.Text) or 0
			if dmgText > 0 and aimlockActive then
				stopAimlock("Damage detected")
			end
		end)
	end

	-- ========= TOUCH INPUT =========
	UserInputService.TouchEnded:Connect(function(touch)
		if not ZSkillsEnabled then return end
		local cam = workspace.CurrentCamera
		if not cam or not touch or not touch.Position then return end

		if touch.Position.X > cam.ViewportSize.X / 2 then
			rightTouching = false
			rightTouchReleased = true

			if currentTool and currentTool.Name == "Godhuman" and godhumanZActive then
				if not aimlockActive then
					startAimlock()
				end
			end
		end
	end)

	-- ========= SKILL HOOK =========
	if not getgenv().ZSkillHooked then
		getgenv().ZSkillHooked = true

		local oldNamecall
		oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
			local method = getnamecallmethod()
			local args = {...}
			
			if (method == "InvokeServer" or method == "FireServer") then
				local a1 = args[1]

				if typeof(a1) == "string" and a1:upper() == "Z" then
					if currentTool then
						if currentTool.Name == "Godhuman" then
							godhumanZActive = true
						end
					end
				end
			end
			return oldNamecall(self, ...)
		end)
	end

	-- =========================
	-- Character Handling
	-- =========================
	local function onCharacterAdded(char)
		if char ~= player.Character then return end

		clearConnections()

		godhumanZActive = false
		rightTouchReleased = false

		for _, child in ipairs(char:GetChildren()) do
			if child:IsA("Tool") then
				hookTool(child)
			end
		end

		table.insert(characterConnections, char.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				hookTool(child)
			end
		end))

		table.insert(characterConnections, char.ChildRemoved:Connect(function(child)
			if child == currentTool then
				currentTool = nil
				godhumanZActive = false
				rightTouchReleased = false
			end
		end))

		watchDamageCounter()
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then onCharacterAdded(player.Character) end

	-- ========= PUBLIC TOGGLE FUNCTION =========
	function ZSkillModule:SetZSkills(state)
		ZSkillsEnabled = state
		if not state then
			stopAimlock("ZSkills disabled")
			clearConnections()
		end
	end

	function ZSkillModule:SetInfo(state)
		TargetInfo = state

		if state then
			if uiConn == nil then
				uiConn = RunService.RenderStepped:Connect(function()
					local target = GetNearestTarget(1000)

					if target and target:FindFirstChild("Humanoid") then
						local hp = target.Humanoid

						targetName.Text = target.Name
						local fill = math.clamp(hp.Health / hp.MaxHealth, 0, 1)
						hpFill.Size = UDim2.new(fill, 0, 1, 0)

						hpBackground.Visible = true
						hpFill.Visible = true
						targetFrame.Visible = true
					else
						targetName.Text = "No target available"

						hpBackground.Visible = false
						hpFill.Visible = false
						targetFrame.Visible = true
					end
				end)
			end
		else
			if uiConn then
				uiConn:Disconnect()
				uiConn = nil
			end

			targetFrame.Visible = false
		end
	end

	return ZSkillModule
]===]


-- local AimlockModule = loadstring(AimlockModule_Source)()
-- local ESPModule = loadstring(ESPModule_Source)()
-- local VSkillModule= loadstring(VSkillModule_Source)()
-- local SilentAimModule = loadstring(SilentAimModule_Source)()
-- local StuffsModule = loadstring(StuffsModule_Source)()
-- local UiSettingsModule = loadstring(UiSettingsModule_Source)()
-- local ZSkillModule = loadstring(ZSkillModule_Source)()


local AimlockModule = loadstring(AimlockModule_Source)()
local ESPModule     = loadstring(ESPModule_Source)()
local VSkillModule  = loadstring(VSkillModule_Source)()
_G.SharedVSkill     = VSkillModule 
local SilentAimModule = loadstring(SilentAimModule_Source)()
local StuffsModule    = loadstring(StuffsModule_Source)()
local UiSettingsModule = loadstring(UiSettingsModule_Source)()
local ZSkillModule     = loadstring(ZSkillModule_Source)()
VSkillModule:CheckVSkillUsage(SilentAimModule)

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")  
local TeleportService = game:GetService("TeleportService")

local PlayerList = {"None"}

-- Toggle button (same as original)
local toggleGui = Instance.new("ScreenGui")
toggleGui.Name = "ToggleGui"
toggleGui.Parent = game.CoreGui

local toggleButton = Instance.new("ImageButton")
toggleButton.Name = "SHV1"
toggleButton.Size = UDim2.new(0, 40, 0, 40)
toggleButton.Position = UDim2.new(0, 5, 0, 10)
toggleButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
toggleButton.BackgroundTransparency = 0.2
toggleButton.BorderSizePixel = 0
toggleButton.ZIndex = 9999
toggleButton.Image = "rbxassetid://76926193047725"
toggleButton.Parent = toggleGui

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 8)
toggleCorner.Parent = toggleButton

UiSettingsModule:MakeDraggable(toggleButton)

-- Executor detection
local executor = "Unknown"
if syn then executor = "Synapse X"
elseif KRNL_LOADED then executor = "KRNL"
elseif fluxus then executor = "Fluxus"
elseif getexecutorname then
    local success, execName = pcall(getexecutorname)
    if success and type(execName) == "string" then executor = execName end
end

local execStatus = (executor == "Xeno" or executor:lower():find("solara") or executor:lower():find("krnl")) and "Not Working" or "Working"

local Window = Luna:CreateWindow({
    Name = "CattStar  |  " .. executor,
    LoadingTitle = "CattoStarHub",
	Subtitle = ". . . . . .",
    LoadingSubtitle = ". . . . . .",
    ConfigFolder = "CattStarConfig",
    KeySystem = false
})

-- -- Create the main window (no key system, no forced home tab example)
-- local Window = Luna:CreateWindow({
--     Name = "CattStar  |  " .. executor,
--     Subtitle = ". . . . . .",
--     ConfigFolder = "CattStarConfig",
--     KeySystem = false
-- })


-- Executor Status Tab
local ExecutorTab = Window:CreateTab({ Name = "◇・Executor Status" })
local InfoSection = ExecutorTab:CreateSection("◈・Information")

InfoSection:CreateLabel({ Text = "Executor: " .. executor })
InfoSection:CreateLabel({ Text = "Status: " .. execStatus })

-- Aimbot Tab
local AimbotTab = Window:CreateTab({ Name = "Aimbot" })
local AimbotSection = AimbotTab:CreateSection("⚙️ Settings")

AimbotSection:CreateToggle({ Name = "Aimlock Players", Description = "Lock onto nearest player", CurrentValue = false, Flag = "AimlockPlayers", Callback = function(state) AimlockModule:SetPlayerAimlock(state) end })
AimbotSection:CreateToggle({ Name = "Aimlock Mini Toggle Players", Description = "Lock onto nearest player", CurrentValue = false, Flag = "AimlockMiniPlayers", Callback = function(state) AimlockModule:SetMiniTogglePlayerAimlock(state) end })
AimbotSection:CreateToggle({ Name = "Aimlock NPC", Description = "Lock onto nearest NPC/Boss", CurrentValue = false, Flag = "AimlockNPC", Callback = function(state) AimlockModule:SetNpcAimlock(state) end })
AimbotSection:CreateToggle({ Name = "Aimlock Mini Toggle NPC", Description = "Lock onto nearest NPC/Boss", CurrentValue = false, Flag = "AimlockMiniNPC", Callback = function(state) AimlockModule:SetMiniToggleNpcAimlock(state) end })
AimbotSection:CreateToggle({ Name = "Prediction", Description = "Predict enemy movement", CurrentValue = false, Flag = "AimlockPrediction", Callback = function(state) AimlockModule:SetPrediction(state) end })

AimbotSection:CreateDropdown({ Name = "Prediction Amount | Default 0.1s", Description = "Select max Prediction for Aimlock", Options = {"0.2", "0.3", "0.4"}, CurrentOption = "0.2", Flag = "AimlockPredAmount", Callback = function(selected) local num = tonumber(selected) if num then AimlockModule:SetPredictionTime(num) end end })

-- Silent Aimbot Tab
local SilentTab = Window:CreateTab({ Name = "Silent Aimbot" })
local SilentSection = SilentTab:CreateSection("⚙️ Settings")

SilentSection:CreateToggle({ Name = "SilentAim Players", Description = "Lock onto nearest player", CurrentValue = false, Flag = "SilentAimPlayers", Callback = function(state) SilentAimModule:SetPlayerSilentAim(state) end })
SilentSection:CreateToggle({ Name = "・SilentAim Mini Toggle Players", Description = "Lock onto nearest player", CurrentValue = false, Flag = "SilentMiniPlayers", Callback = function(state) SilentAimModule:SetMiniTogglePlayerSilentAim(state) end })
SilentSection:CreateToggle({ Name = "・SilentAim Npcs", Description = "Lock onto nearest npc", CurrentValue = false, Flag = "SilentAimNPC", Callback = function(state) SilentAimModule:SetNPCSilentAim(state) end })
SilentSection:CreateToggle({ Name = "・SilentAim Mini Toggle NPC", Description = "Lock onto nearest NPC/Boss", CurrentValue = false, Flag = "SilentMiniNPC", Callback = function(state) SilentAimModule:SetMiniToggleNpcSilentAim(state) end })
SilentSection:CreateToggle({ Name = "・SilentAim Prediction", Description = "Prediction on target", CurrentValue = false, Flag = "SilentAimPred", Callback = function(state) SilentAimModule:SetPrediction(state) end })

SilentSection:CreateDropdown({ Name = "・Prediction Future | Default 0.1s", Description = "Select max Prediction for Silent Aim", Options = {"0.2", "0.3", "0.4"}, CurrentOption = "0.2", Flag = "SilentPredAmount", Callback = function(selected) local num = tonumber(selected) if num then SilentAimModule:SetPredictionAmount(num) end end })
SilentSection:CreateDropdown({ Name = "・Distance Limit | Default 1000m", Description = "Select max distance for aimbot", Options = {"200", "400", "600"}, CurrentOption = "200", Flag = "SilentDistance", Callback = function(selected) local num = tonumber(selected) if num then SilentAimModule:SetDistanceLimit(num) end end })

-- Dynamic player dropdown
for _, plr in ipairs(Players:GetPlayers()) do if plr ~= Players.LocalPlayer then table.insert(PlayerList, plr.Name) end end

local PlayerDropdown = SilentSection:CreateDropdown({ Name = "・Select Player Target", Description = "Choose a player to lock onto", Options = PlayerList, CurrentOption = "None", Flag = "PlayerTarget", SpecialType = "Player", Callback = function(selected) if selected == "None" then SilentAimModule:SetSelectedPlayer(nil) else SilentAimModule:SetSelectedPlayer(selected) end end })

-- (Luna has SpecialType = "Player" for auto player dropdowns, bonus!)

SilentSection:CreateToggle({ Name = "・GodhumanZ Aimlock", Description = "I only set Godhuman", CurrentValue = false, Flag = "ZSkills", Callback = function(state) ZSkillModule:SetZSkills(state) end })
SilentSection:CreateToggle({ Name = "・Main Highlight", Description = "Current Target Highlighted", CurrentValue = false, Flag = "Highlight", Callback = function(state) SilentAimModule:SetHighlight(state) end })
SilentSection:CreateToggle({ Name = "・Z|M1 Skills(except Godhuman Z)", Description = "Silent Aim That Work Some Skills", CurrentValue = false, Flag = "ZMSkills", Callback = function(state) SilentAimModule:SetZSkillorM1(state) end })

-- Features Tab
local FeaturesTab = Window:CreateTab({ Name = "✿・Features" })
local FeaturesSection = FeaturesTab:CreateSection("⚙️ Settings")

FeaturesSection:CreateButton({ Name = "Join Discord", Description = "Get Link Discord server", Callback = function()
    setclipboard("https://discord.gg/mUmME9DFH4")
    game:GetService("StarterGui"):SetCore("SendNotification", { Title = "CattStar", Text = "Copied Discord Link!", Duration = 5 })
end })

FeaturesSection:CreateToggle({ Name = "・ESP Players", Description = "Toggle Player ESP", CurrentValue = false, Flag = "ESPPlayers", Callback = function(state) ESPModule:SetESP(state) end })
FeaturesSection:CreateToggle({ Name = "・V3 Skill", Description = "Auto activate V3 ability", CurrentValue = false, Flag = "V3Skill", Callback = function(state) ESPModule:SetV3(state) end })
FeaturesSection:CreateToggle({ Name = "・Bunny hop", Description = "Toggle Bunnyhop", CurrentValue = false, Flag = "BunnyHop", Callback = function(state) ESPModule:SetBunnyhop(state) end })
FeaturesSection:CreateToggle({ Name = "・Aura Skill", Description = "Auto activate Buso", CurrentValue = false, Flag = "AuraSkill", Callback = function(state) ESPModule:SetBuso(state) end })
FeaturesSection:CreateToggle({ Name = "・Fps Or Pings", Description = "Display Ping or Fps", CurrentValue = false, Flag = "FpsPings", Callback = function(state) StuffsModule:SetPingsOrFps(state) end })

-- FeaturesSection:CreateInput({ Name = "Speed Hack", Description = "WalkSpeedValue", PlaceholderText = "Enter speed", CurrentValue = "", Flag = "SpeedHack", Callback = function(val) local num = tonumber(val) if num then getgenv().WalkSpeedValue = num UiSettingsModule:SetWalkSpeed(num) end end })

FeaturesSection:CreateSlider({Name = "Speed Hack", Range = {1, 100}, Increment = 1, Suffix = " Mult", CurrentValue = 1, Flag = "SpeedHack", 
Callback = function(v) getgenv().WalkSpeedValue = v game.Players.LocalPlayer.Character:SetAttribute("SpeedMultiplier", v) end})

FeaturesSection:CreateToggle({ Name = "・Fps Boost", Description = "Increase Fps", CurrentValue = false, Flag = "FpsBoost", Callback = function(state) StuffsModule:SetFpsBoost(state) end })
FeaturesSection:CreateToggle({ Name = "・INF Energy", Description = "Max Energy", CurrentValue = false, Flag = "INFEnergy", Callback = function(state) StuffsModule:SetINFEnergy(state) end })
FeaturesSection:CreateToggle({ Name = "・Walk on Water", Description = "Travel in Water", CurrentValue = false, Flag = "WalkWater", Callback = function(state) StuffsModule:SetWalkWater(state) end })
FeaturesSection:CreateToggle({ Name = "・Fast Attack", Description = "Fast Attack", CurrentValue = false, Flag = "FastAttack", Callback = function(state) StuffsModule:SetFastAttack(state) end })
FeaturesSection:CreateToggle({ Name = "・AntiAfk", Description = "AntiAfk only on before you off", CurrentValue = false, Flag = "AntiAFK", Callback = function(state) ESPModule:SetAntiAfk(state) end })

FeaturesSection:CreateInput({ Name = "Jump Power", Description = "JumpValue", PlaceholderText = "Enter value", CurrentValue = "", Flag = "JumpPower", Callback = function(val) local num = tonumber(val) if num then getgenv().JumpValue = num local char = Players.LocalPlayer.Character if char and char:FindFirstChild("Humanoid") then char.Humanoid.JumpPower = num end end end })

FeaturesSection:CreateToggle({ Name = "・Auto V4", Description = "Auto V4 Transform", CurrentValue = false, Flag = "AutoV4", Callback = function(state) UiSettingsModule:SetV4(state) end })
FeaturesSection:CreateToggle({ Name = "・Spawned Fruit Check", Description = "Check Fruit Spawned", CurrentValue = false, Flag = "FruitCheck", Callback = function(state) UiSettingsModule:SetFruitCheck(state) end })
FeaturesSection:CreateToggle({ Name = "・Bring Fruits", Description = "It take few seconds to bring fruits", CurrentValue = false, Flag = "BringFruits", Callback = function(state) UiSettingsModule:SetTeleportFruit(state) end })
FeaturesSection:CreateToggle({ Name = "・Auto Ken", Description = "AutoKen", CurrentValue = false, Flag = "AutoKen", Callback = function(state) SilentAimModule:SetAutoKen(state) end })
FeaturesSection:CreateToggle({ Name = "・Remove Lava", Description = "Remove Lava", CurrentValue = false, Flag = "RemoveLava", Callback = function(state) StuffsModule:SetLava(state) end })
FeaturesSection:CreateToggle({ Name = "・Remove Fog", Description = "Remove Fog", CurrentValue = false, Flag = "RemoveFog", Callback = function(state) StuffsModule:SetFog(state) end })
FeaturesSection:CreateToggle({ Name = "・Dodge no cd", Description = "Dodge no cd", CurrentValue = false, Flag = "DodgeNoCD", Callback = function(state) ESPModule:SetNoDodgeCD(state) end })
FeaturesSection:CreateToggle({ Name = "・Target Info(Name/Health)", Description = "Info Of Target", CurrentValue = false, Flag = "TargetInfo", Callback = function(state) ZSkillModule:SetInfo(state) end })

-- Settings Manager Tab
local SettingsTab = Window:CreateTab({ Name = "⚙・Settings Manager" })
local SettingsSection = SettingsTab:CreateSection("💾・Settings")

SettingsSection:CreateInput({ Name = "Paste Job Id Here", Description = "Paste JobId and press Enter", PlaceholderText = "Job ID", CurrentValue = "", Flag = "JobID", Callback = function(id) if id ~= "" then TeleportService:TeleportToPlaceInstance(game.PlaceId, id, Players.LocalPlayer) end end })

SettingsSection:CreateButton({ Name = "Rejoin Server", Description = "Rejoin your server", Callback = function() StuffsModule:SetRejoinServer() end })

SettingsSection:CreateDropdown({ Name = "・Global Text Font", Description = "Change font for all text", Options = {"Arcade","Cartoon","SciFi","Fantasy","Antique","Garamond","RobotoMono","FredokaOne","LuckiestGuy","PermanentMarker","SpecialElite","Oswald","Nunito"}, CurrentOption = "Arcade", Flag = "GlobalFont", Callback = function(selected) local fontEnum = Enum.Font[selected] if fontEnum then ESPModule:SetGlobalFont(fontEnum) end end })

SettingsSection:CreateDropdown({ Name = "・RTX Graphics Mode", Description = "Choose between Autumn or Summer or Spring or Winter", Options = {"Autumn","Summer","Spring","Winter"}, CurrentOption = "Autumn", Flag = "RTXMode", Callback = function(selected) ESPModule:SetRTXMode(selected) end })

-- Keybinds
toggleButton.MouseButton1Click:Connect(function() Window:Toggle() end)

UserInputService.InputBegan:Connect(function(input, gp)
    if not gp and input.KeyCode == Enum.KeyCode.M then
        Window:Toggle()
    end
end)

UserInputService.InputBegan:Connect(function(input, gp)
    if not gp and input.KeyCode == Enum.KeyCode.G then
        local current = Luna.Options["SilentAimPlayers"] and Luna.Options["SilentAimPlayers"].CurrentValue or false
        SilentAimModule:SetPlayerSilentAim(not current)
    end
end)

Luna:Notify({ Title = "CattStar Loaded!", Content = "Beautiful Luna UI active 🌙", Duration = 8 })