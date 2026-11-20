local Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()

local window = Rayfield:CreateWindow({
    name = "Moon v2",
    subtitle = "Rayfield Gen2",
    sidebarLayout = true,
})

local tab = window:CreateTab({ name = "Home", icon = 93364949241311 })

tab:CreateToggle({
    name = "Auto Sprint",
    callback = function(value) print(value) end,
})                                         local function flyZeroVelocity(part)
	if not pcall(function() part.AssemblyLinearVelocity = Vector3.zero end) then
		pcall(function() part.Velocity = Vector3.zero end)
	end
end

local function flyRay(fromPos, dirVec, ignoreList)
	if dirVec.Magnitude < 1e-5 then return nil end
	local params = RaycastParams.new()
	params.FilterType = FlyExcludeMode
	params.FilterDescendantsInstances = ignoreList
	params.IgnoreWater = true
	return WS:Raycast(fromPos, dirVec, params)
end

local function flyClampVertical(origin, deltaY, ignoreList)
	if not FlyCfg.COLLISION_CHECK or math.abs(deltaY) < 1e-5 or not FlyHRP then return deltaY end
	local half = FlyHRP.Size.Y * 0.5
	local yOff = (deltaY > 0) and half or -half
	local hit = flyRay(origin + Vector3.new(0, yOff, 0), Vector3.new(0, deltaY, 0), ignoreList)
	if not hit then return deltaY end
	local allow = math.max(0, hit.Distance - 0.05)
	if deltaY > 0 then return math.min(deltaY, allow) end
	return -math.min(-deltaY, allow)
end

local function flyClampHorizontal(origin, horizDelta, ignoreList)
	if not FlyCfg.COLLISION_CHECK then return horizDelta end
	local mag = horizDelta.Magnitude
	if mag < 1e-5 then return horizDelta end
	local hi = flyRay(origin + Vector3.new(0, 2.0, 0), horizDelta, ignoreList)
	local lo = flyRay(origin + Vector3.new(0, -0.6, 0), horizDelta, ignoreList)
	if hi and lo then
		local d = math.min(hi.Distance, lo.Distance) - 1.0
		if d <= 0.1 then return Vector3.zero end
		return horizDelta.Unit * math.min(mag, d)
	end
	return horizDelta
end

local function startFlying()
	if FlyingEnabled then return end
	if not LP.Character then LP.CharacterAdded:Wait() end
	flyBindCharacter(LP.Character)
	if not FlyHRP then
		notify("飞行失败: 无法获取角色", 2)
		return
	end
	FlyingEnabled = true
	if FlyConn then FlyConn:Disconnect() end
	FlyConn = Run.RenderStepped:Connect(function(dt)
		if not FlyingEnabled then return end
		if not FlyHRP or not FlyHRP.Parent or not FlyHum or FlyHum.Health <= 0 then return end
		if FlyChar ~= LP.Character then flyBindCharacter(LP.Character) end
		if FlyHum.Sit then return end
		if not WS.CurrentCamera then return end

		local b = flyEnsureBlock()
		local origin = FlyHRP.Position
		local ignore = { FlyChar, b }

		local moveDir = flyMoveVector()
		local moving = moveDir.Magnitude > 0.05

		local pitch = flyPitchDeg()
		local vSpeed = 0
		if moving then
			vSpeed = flySpeedFromAngle(pitch)
			if pitch < 0 then vSpeed = -vSpeed end
		end

		local deltaY = flyClampVertical(origin, vSpeed * dt, ignore)
		local deltaH = flyClampHorizontal(origin, moveDir * (FlightSpeed * dt), ignore)
		local newPos = origin + Vector3.new(deltaH.X, deltaY, deltaH.Z)

		local halfY = FlyHRP.Size.Y * 0.5
		local feetNow = origin.Y - halfY
		local feetNew = newPos.Y - halfY
		local topNow = b.Position.Y + b.Size.Y * 0.5

		local wantBlockY
		if FlyBlockFresh or math.abs(topNow - feetNow) > FlyCfg.RESYNC_DISTANCE then
			wantBlockY = feetNow - FlyCfg.BLOCK_GAP - b.Size.Y * 0.5
			FlyBlockFresh = false
		elseif moving then
			wantBlockY = feetNew - FlyCfg.BLOCK_GAP - b.Size.Y * 0.5
		else
			wantBlockY = b.Position.Y
		end

		b.CFrame = CFrame.new(newPos.X, wantBlockY, newPos.Z)

		if moving then
			local rot = FlyHRP.CFrame - FlyHRP.CFrame.Position
			FlyHRP.CFrame = CFrame.new(newPos) * rot
			flyZeroVelocity(FlyHRP)
		end
	end)
	notify("飞行开启 (Tp_fly): 走动 + 抬头/低头升降", 3)
end

local function stopFlying()
	FlyingEnabled = false
	if FlyConn then FlyConn:Disconnect() FlyConn = nil end
	flyRemoveBlock()
	notify("飞行关闭", 2)
end

local function getControlModule()
	local PlayerModule = LP:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")
	return require(PlayerModule:WaitForChild("ControlModule"))
end

local function setupBodyMovers(character)
	local hrp = character:WaitForChild("HumanoidRootPart")
	local humanoid = character:WaitForChild("Humanoid")
	local moverParent = WS:FindFirstChildOfClass("Terrain") or WS
	local moverAttachment = Instance.new("Attachment", hrp)
	moverAttachment.Name = "FlightAttachment"
	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.RigidityEnabled = true
	alignOrientation.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
	alignOrientation.CFrame = hrp.CFrame
	alignOrientation.Attachment0 = moverAttachment
	alignOrientation.Parent = moverParent
	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.VectorVectorVelocity = Vector3.new(0, 0, 0)
	linearVelocity.MaxForce = 9e9
	linearVelocity.Attachment0 = moverAttachment
	linearVelocity.Parent = moverParent
	return alignOrientation, linearVelocity, humanoid, moverAttachment
end

local function getFlightVector(controlModule)
	local moveVector = controlModule:GetMoveVector()
	local cam = WS.CurrentCamera
	FlightControl.F = -moveVector.Z
	FlightControl.B = moveVector.Z
	FlightControl.L = -moveVector.X
	FlightControl.R = moveVector.X
	FlightControl.Q = moveVector.Y
	FlightControl.E = -moveVector.Y
	if UIS:IsKeyDown(Enum.KeyCode.W) then FlightControl.F = 1 end
	if UIS:IsKeyDown(Enum.KeyCode.S) then FlightControl.B = 1 end
	if UIS:IsKeyDown(Enum.KeyCode.A) then FlightControl.L = 1 end
	if UIS:IsKeyDown(Enum.KeyCode.D) then FlightControl.R = 1 end
	if UIS:IsKeyDown(Enum.KeyCode.Space) then FlightControl.Q = 1 end
	if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then FlightControl.E = 1 end
	local flightVector = (cam.CFrame.LookVector * (FlightControl.F - FlightControl.B) +
		cam.CFrame.RightVector * (FlightControl.R - FlightControl.L) +
		Vector3.new(0, 1, 0) * (FlightControl.Q - FlightControl.E))
	return flightVector.Magnitude > 0 and flightVector.Unit or flightVector
end

local function startFlyingYttrium()
	if FlyingEnabled then return end
	local character = LP.Character or LP.CharacterAdded:Wait()
	if not character then
		notify("飞行失败: 无法获取角色", 2)
		return
	end
	FlyingEnabled = true
	if CurrentAO then CurrentAO:Destroy() end
	if CurrentLV then CurrentLV:Destroy() end
	if CurrentMoverAttachment then CurrentMoverAttachment:Destroy() end
	CurrentAO, CurrentLV, _, CurrentMoverAttachment = setupBodyMovers(character)
	notify("飞行开启, 速度: " .. FlightSpeed, 2)
	local controlModule = getControlModule()
	FlightConnection = Run.Heartbeat:Connect(function()
		if not FlyingEnabled or not CurrentLV or not CurrentAO then
			if FlightConnection then
				FlightConnection:Disconnect()
				FlightConnection = nil
			end
			return
		end
		local flightVector = getFlightVector(controlModule)
		if flightVector.Magnitude > 0 then
			CurrentLV.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
			CurrentLV.VectorVelocity = flightVector * FlightSpeed
		else
			CurrentLV.VectorVelocity = Vector3.new(0, 0, 0)
		end
		if SpinningEnabled then
			local targetPart = character.Humanoid.SeatPart or character.HumanoidRootPart
			local spinCFrame = targetPart.CFrame * CFrame.Angles(0, math.rad(SpinSpeed), 0)
			CurrentAO.CFrame = spinCFrame
		else
			CurrentAO.CFrame = WS.CurrentCamera.CFrame
		end
		if character.HumanoidRootPart then
			character.Humanoid.PlatformStand = true
		end
	end)
	character.AncestryChanged:Connect(function(_, parent)
		if not parent and FlyingEnabled then
			stopFlying()
		end
	end)
end

local function stopFlyingYttrium()
	if not FlyingEnabled then return end
	FlyingEnabled = false
	SpinningEnabled = false
	FlightControl = { F = 0, B = 0, L = 0, R = 0, Q = 0, E = 0 }
	if FlightConnection then
		FlightConnection:Disconnect()
		FlightConnection = nil
	end
	local character = LP.Character
	if character and character:FindFirstChild("Humanoid") then
		character.Humanoid.PlatformStand = false
	end
	if CurrentAO then
		CurrentAO:Destroy()
		CurrentAO = nil
	end
	if CurrentLV then
		CurrentLV:Destroy()
		CurrentLV = nil
	end
	if CurrentMoverAttachment then
		CurrentMoverAttachment:Destroy()
		CurrentMoverAttachment = nil
	end
	notify("飞行关闭", 2)
end

local LoopTP_Conn = nil

local function getBehindCFrame(targetHRP)
	local cf = targetHRP.CFrame
	local behind = cf.Position - cf.LookVector * 3 + Vector3.new(0, 3, 0)
	return CFrame.new(behind, cf.Position)
end

local function startLoopTP()
	if LoopTP_Conn then LoopTP_Conn:Disconnect() end
	LoopTP_Conn = Run.Heartbeat:Connect(function()
		if State.LoopTP then
			local target = State.SelectedPlayer
			if target and isAlive(target) then
				local hrp = getHRP()
				local tHRP = getHRP(target)
				if hrp and tHRP then
					hrp.CFrame = getBehindCFrame(tHRP)
				end
			end
		end
	end)
	notify("循环传送已开启", 3)
end

local function stopLoopTP()
	State.LoopTP = false
	if LoopTP_Conn then LoopTP_Conn:Disconnect() LoopTP_Conn = nil end
end

local Pull_Conn = nil

local function startPull()
	if Pull_Conn then Pull_Conn:Disconnect() end
	Pull_Conn = Run.Heartbeat:Connect(function()
		if State.PullPlayers then
			local hrp = getHRP()
			if hrp then
				for _, p in ipairs(getPlayers()) do
					if isAlive(p) then
						local phrp = getHRP(p)
						if phrp then
							local d = (hrp.Position - phrp.Position).Magnitude
							if d < State.Pull_Distance then
								pcall(function()
									phrp.CFrame = phrp.CFrame:Lerp(hrp.CFrame, 0.3)
								end)
							end
						end
					end
				end
			end
		end
	end)
end

local function stopPull()
	State.PullPlayers = false
	if Pull_Conn then Pull_Conn:Disconnect() Pull_Conn = nil end
end

local Spectate_Conn = nil
local OldSubject = nil

local function startSpectate()
	local target = State.SelectedPlayer
	if not target then
		notify("请先选择玩家")
		return false
	end
	if Spectate_Conn then Spectate_Conn:Disconnect() Spectate_Conn = nil end
	OldSubject = Camera.CameraSubject
	Spectate_Conn = Run.RenderStepped:Connect(function()
		if not State.Spectate then return end
		local t = State.SelectedPlayer
		local hum = t and getHum(t)
		if hum then
			Camera.CameraSubject = hum
			Camera.CameraType = Enum.CameraType.Follow
		else
			State.Spectate = false
			notify("观战目标已失效")
		end
	end)
	notify("观战中: " .. target.Name)
	return true
end

local function stopSpectate()
	State.Spectate = false
	if Spectate_Conn then Spectate_Conn:Disconnect() Spectate_Conn = nil end
	local hum = getHum()
	if hum then
		Camera.CameraSubject = hum
		Camera.CameraType = Enum.CameraType.Custom
	elseif OldSubject then
		Camera.CameraSubject = OldSubject
	end
	notify("停止观战")
end

local function saveCoord(name)
	local hrp = getHRP()
	if not hrp then notify("无角色") return end
	table.insert(State.SavedCoords, { name = name, pos = hrp.Position })
	notify("已保存: " .. name)
end

local function tpCoord(index)
	local hrp = getHRP()
	if not hrp then return end
	local c = State.SavedCoords[index]
	if c then
		hrp.CFrame = CFrame.new(c.pos)
		notify("已传送到: " .. c.name)
	end
end

local function rejoin()
	pcall(function()
		TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
	end)
end

local function serverHop()
	pcall(function()
		local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
		local resp = HttpService:JSONDecode(game:HttpGet(url))
		local servers = {}
		for _, srv in ipairs(resp.data or {}) do
			if srv.playing < srv.maxPlayers and srv.id ~= game.JobId then
				table.insert(servers, srv)
			end
		end
		table.sort(servers, function(a, b) return a.playing < b.playing end)
		if servers[1] then
			TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[1].id, LP)
		else
			notify("无可用服务器")
		end
	end)
end

local Respawn_Conn = nil

local function startAutoRespawn()
	if Respawn_Conn then Respawn_Conn:Disconnect() end
	Respawn_Conn = LP.CharacterAdded:Connect(function(char)
		task.wait(0.5)
		notify("原地复活完成")
	end)
	if not getChar() or (getHum() and getHum().Health <= 0) then
		pcall(function() LP:LoadCharacter() end)
	end
end

local function stopAutoRespawn()
	if Respawn_Conn then Respawn_Conn:Disconnect() Respawn_Conn = nil end
end

local CustomScripts = {
	{
		name = "无限血量 (Local)",
		code = [[
local hum = game.Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
if hum then
	hum.HealthChanged:Connect(function()
		if hum.Health < hum.MaxHealth then
			hum.Health = hum.MaxHealth
		end
	end)
end
]],
	},
	{
		name = "清空背包",
		code = [[
local bp = game.Players.LocalPlayer:FindFirstChild("Backpack")
if bp then bp:ClearAllChildren() end
]],
	},
	{
		name = "显示 FPS",
		code = [[
local gui = Instance.new("ScreenGui", game.Players.LocalPlayer.PlayerGui)
local lbl = Instance.new("TextLabel", gui)
lbl.Size = UDim2.new(0, 100, 0, 30)
lbl.Position = UDim2.new(0, 10, 0, 10)
lbl.TextColor3 = Color3.fromRGB(255, 105, 180)
lbl.BackgroundTransparency = 1
lbl.Font = Enum.Font.GothamBold
local last = tick()
local frames = 0
game:GetService("RunService").RenderStepped:Connect(function()
	frames = frames + 1
	if tick() - last >= 1 then
		lbl.Text = "FPS: " .. frames
		frames = 0
		last = tick()
	end
end)
]],
	},
}

local function execCustomCode(code)
	if not code or code == "" then return end
	local func, err = loadstring(code)
	if func then
		local ok, e = pcall(func)
		if ok then
			notify("执行成功")
		else
			notify("运行错误: " .. tostring(e))
		end
	else
		notify("编译错误: " .. tostring(err))
	end
end

local function execCustom(index)
	local s = CustomScripts[index]
	if s then execCustomCode(s.code) end
end

local Window = WindUI:CreateWindow({
	Title = "case | Ohio",
	Icon = "drumstick",
	Author = "case",
	Folder = "case",
	Size = UDim2.fromOffset(620, 460),
	Transparent = false,
	Theme = "Dark",
	SideBarWidth = 180,
	NewElements = true,
	User = { Enabled = true, Anonymous = false },
})
Window:SetToggleKey(Enum.KeyCode.RightShift)
print("[case] 窗口已创建")

local Tabs = {
	Combat = Window:Tab({ Title = "战斗", Icon = "swords" }),
	Aim = Window:Tab({ Title = "自瞄", Icon = "crosshair" }),
	Bullet = Window:Tab({ Title = "子弹追踪", Icon = "target" }),
	Util = Window:Tab({ Title = "通用", Icon = "wrench" }),
	Players = Window:Tab({ Title = "玩家", Icon = "users" }),
	Teleport = Window:Tab({ Title = "传送", Icon = "map-pin" }),
	Server = Window:Tab({ Title = "服务器", Icon = "globe" }),
	Custom = Window:Tab({ Title = "脚本", Icon = "code" }),
}

local function refreshPlayerLists()
	local names = getPlayerNameList()
	pcall(function() if WhiteListDropdown then WhiteListDropdown:Refresh(names) end end)
	pcall(function() if BlackListDropdown then BlackListDropdown:Refresh(names) end end)
	pcall(function() if PlayerSelectDropdown then PlayerSelectDropdown:Refresh(names) end end)
end

local CombatList = Tabs.Combat:Section({ Title = "白名单 / 黑名单" })
local WhiteListDropdown
WhiteListDropdown = CombatList:Dropdown({
	Title = "加入白名单",
	Desc = "选择玩家加入白名单",
	Values = getPlayerNameList(),
	Multi = false,
	AllowNone = true,
	Value = nil,
	Callback = function(name)
		if name and name ~= "" then
			if not table.find(State.WhiteList, name) then
				table.insert(State.WhiteList, name)
				notify("已加入白名单: " .. name)
			end
		end
	end,
})
CombatList:Button({
	Title = "清空白名单",
	Desc = "清空当前白名单",
	Callback = function()
		table.clear(State.WhiteList)
		notify("白名单已清空")
	end,
})
CombatList:Button({
	Title = "刷新玩家列表",
	Desc = "刷新白名单/黑名单下拉框",
	Callback = function()
		refreshPlayerLists()
		notify("玩家列表已刷新")
	end,
})
CombatList:Toggle({
	Title = "白名单保护",
	Desc = "白名单内玩家不被攻击",
	Value = false,
	Callback = function(v)
		State.WhiteList_Enabled = v
	end,
})
local BlackListDropdown
BlackListDropdown = CombatList:Dropdown({
	Title = "加入黑名单",
	Desc = "选择玩家加入黑名单(RPG 只打黑名单里的人)",
	Values = getPlayerNameList(),
	Multi = false,
	AllowNone = true,
	Value = nil,
	Callback = function(name)
		if name and name ~= "" then
			if not table.find(State.BlackList, name) then
				table.insert(State.BlackList, name)
				syncTargetPlayers()
				notify("已加入黑名单: " .. name)
				if State.BlackList_Enabled then State.OnePunch = true end
			end
		end
	end,
})
CombatList:Button({
	Title = "清空黑名单",
	Desc = "清空黑名单并停止攻击",
	Callback = function()
		table.clear(State.BlackList)
		syncTargetPlayers()
		State.OnePunch = false
		notify("黑名单已清空")
	end,
})
CombatList:Toggle({
	Title = "黑名单复仇",
	Desc = "开启后自动追杀黑名单玩家",
	Value = false,
	Callback = function(v)
		State.BlackList_Enabled = v
		if v then
			State.OnePunch = true
			notify("黑名单已开启, 开始追杀")
		else
			State.OnePunch = false
			notify("黑名单已关闭")
		end
	end,
})

local CombatOP = Tabs.Combat:Section({ Title = "一拳超人" })
CombatOP:Toggle({
	Title = "一拳超人",
	Desc = "贴脸秒杀范围内玩家",
	Value = false,
	Callback = function(s)
		State.OnePunch = s
		if s then
			if not DEVV_OK then notify("RS.devv 未加载, 仅 Ohio 服可用") end
			startOnePunch()
		else
			stopOnePunch()
		end
	end,
})
CombatOP:Slider({
	Title = "攻击范围",
	Desc = "一拳超人攻击范围",
	Step = 1,
	Value = { Min = 4, Max = 40, Default = 35 },
	Callback = function(v) State.OP_Range = v end,
})
CombatOP:Slider({
	Title = "攻击间隔(ms)",
	Desc = "两次攻击间隔(毫秒)",
	Step = 10,
	Value = { Min = 100, Max = 2000, Default = 700 },
	Callback = function(v) State.OP_Delay = v / 1000 end,
})
CombatOP:Toggle({
	Title = "无视护盾",
	Desc = "跳过带 ForceField 的目标",
	Value = true,
	Callback = function(s) State.OP_SkipShield = s end,
})

local CombatArmor = Tabs.Combat:Section({ Title = "自动穿甲" })
CombatArmor:Toggle({
	Title = "自动穿轻型甲",
	Desc = "自动购买并穿戴 Light Vest",
	Value = false,
	Callback = function(s)
		State.AutoArmor = s
		if s then startAutoArmor() else stopAutoArmor() end
	end,
})

local AimSection = Tabs.Aim:Section({ Title = "自瞄" })
AimSection:Toggle({
	Title = "启用自瞄",
	Desc = "锁定视角对准敌人",
	Value = false,
	Callback = function(s)
		State.Aim = s
		if s then startAim() updateNameTags() else stopAim() updateNameTags() end
	end,
})
AimSection:Dropdown({
	Title = "瞄准部位",
	Desc = "选择自瞄锁定的部位",
	Values = { "Head", "UpperTorso", "HumanoidRootPart" },
	Multi = false,
	AllowNone = false,
	Value = "Head",
	Callback = function(v) State.Aim_Part = v end,
})
AimSection:Slider({
	Title = "FOV 范围",
	Desc = "自瞄搜索范围(像素)",
	Step = 1,
	Value = { Min = 10, Max = 300, Default = 120 },
	Callback = function(v)
		State.Aim_FOV = v
		if FOV_Circle then FOV_Circle.Radius = v end
	end,
})
AimSection:Slider({
	Title = "最大距离",
	Desc = "自瞄最远距离(超出不锁)",
	Step = 10,
	Value = { Min = 50, Max = 2000, Default = 500 },
	Callback = function(v) State.Aim_Distance = v end,
})
AimSection:Toggle({
	Title = "平滑锁定",
	Desc = "平滑移动视角而不是瞬移",
	Value = true,
	Callback = function(s) State.Aim_Smooth = s end,
})
AimSection:Slider({
	Title = "平滑速度",
	Desc = "锁定平滑程度",
	Step = 1,
	Value = { Min = 1, Max = 100, Default = 15 },
	Callback = function(v) State.Aim_Speed = v / 100 end,
})
AimSection:Toggle({
	Title = "显示 FOV 圈",
	Desc = "在屏幕中心画 FOV 圆",
	Value = true,
	Callback = function(s)
		State.Aim_ShowFOV = s
		if s and State.Aim and not FOV_Circle then
			startAim()
		elseif not s and FOV_Circle then
			FOV_Circle:Remove() FOV_Circle = nil
		end
	end,
})
AimSection:Toggle({
	Title = "显示名字",
	Desc = "在玩家头上显示名字标签",
	Value = true,
	Callback = function(s) State.Aim_ShowName = s updateNameTags() end,
})
AimSection:Toggle({
	Title = "穿透墙壁",
	Desc = "隔墙也能锁(默认关)",
	Value = false,
	Callback = function(s) State.Aim_Wallbang = s end,
})
AimSection:Toggle({
	Title = "包含队友",
	Desc = "自瞄也锁定队友",
	Value = false,
	Callback = function(s) State.Aim_Team = s end,
})

local BulletSection = Tabs.Bullet:Section({ Title = "子弹追踪" })
BulletSection:Toggle({
	Title = "启用子弹追踪",
	Desc = "拦截枪械 RemoteEvent 改写目标",
	Value = false,
	Callback = function(s)
		State.BulletTrack = s
		if s then startBulletTrack() else stopBulletTrack() end
	end,
})
BulletSection:Dropdown({
	Title = "追踪部位",
	Desc = "选择追踪的目标部位",
	Values = { "Head", "UpperTorso", "HumanoidRootPart" },
	Multi = false,
	AllowNone = false,
	Value = "Head",
	Callback = function(v) State.BT_Part = v end,
})
BulletSection:Slider({
	Title = "追踪 FOV",
	Desc = "追踪搜索范围(像素)",
	Step = 1,
	Value = { Min = 10, Max = 400, Default = 200 },
	Callback = function(v) State.BT_FOV = v end,
})
BulletSection:Slider({
	Title = "追踪距离",
	Desc = "追踪最远距离(超出不锁)",
	Step = 10,
	Value = { Min = 50, Max = 3000, Default = 1000 },
	Callback = function(v) State.BT_Distance = v end,
})
BulletSection:Toggle({
	Title = "穿透墙壁",
	Desc = "隔墙也能追踪(默认关)",
	Value = false,
	Callback = function(s) State.BT_Wallbang = s end,
})
BulletSection:Toggle({
	Title = "包含队友",
	Desc = "追踪也锁定队友",
	Value = false,
	Callback = function(s) State.BT_Team = s end,
})
BulletSection:Paragraph({
	Title = "说明",
	Desc = "拦截枪械 RemoteEvent 改写目标, 自动锁敌 + 转视角。开启后请开枪一次测试, 见输出栏日志。",
})
BulletSection:Button({
	Title = "重新扫描枪械事件",
	Desc = "重新扫描 RemoteEvent 列表",
	Callback = function()
		if State.BulletTrack then
			stopBulletTrack()
			BT_HookInstalled = false
		end
		startBulletTrack()
		notify("已重新扫描")
	end,
})

local UtilMove = Tabs.Util:Section({ Title = "移动" })
UtilMove:Toggle({
	Title = "飞行模式 (Tp_fly)",
	Desc = "由司空提供",
	Value = false,
	Callback = function(s)
		if s then
			startFlying()
		else
			stopFlying()
		end
	end,
})
UtilMove:Slider({
	Title = "飞行速度",
	Desc = "对应 HORIZONTAL_SPEED, 默认 250",
	Step = 5,
	Value = { Min = 1, Max = 600, Default = 250 },
	Callback = function(v)
		FlyCfg.HORIZONTAL_SPEED = v
		FlightSpeed = v
	end,
})
UtilMove:Slider({
	Title = "竖直最低速度",
	Desc = "对应 VERTICAL_MIN, 默认 12",
	Step = 1,
	Value = { Min = 1, Max = 200, Default = 12 },
	Callback = function(v) FlyCfg.VERTICAL_MIN = v end,
})
UtilMove:Slider({
	Title = "竖直最快速度",
	Desc = "对应 VERTICAL_MAX, 默认 400",
	Step = 10,
	Value = { Min = 20, Max = 1000, Default = 400 },
	Callback = function(v) FlyCfg.VERTICAL_MAX = v end,
})
UtilMove:Slider({
	Title = "启动角度",
	Desc = "对应 START_ANGLE, 默认 0",
	Step = 1,
	Value = { Min = 0, Max = 60, Default = 0 },
	Callback = function(v) FlyCfg.START_ANGLE = v end,
})
UtilMove:Slider({
	Title = "满速角度",
	Desc = "对应 MAX_ANGLE, 默认 48",
	Step = 1,
	Value = { Min = 5, Max = 89, Default = 48 },
	Callback = function(v) FlyCfg.MAX_ANGLE = v end,
})
UtilMove:Toggle({
	Title = "飞行碰撞检测",
	Desc = "开=会撞墙, 关=穿墙飞 (默认关)",
	Value = false,
	Callback = function(v) FlyCfg.COLLISION_CHECK = v end,
})
UtilMove:Toggle({
	Title = "穿墙 (Noclip)",
	Desc = "角色可穿过所有部件",
	Value = false,
	Callback = function(s) setNoclip(s) end,
})

local InfJump_Conn = nil
UtilMove:Toggle({
	Title = "无限跳跃",
	Desc = "可无限跳跃",
	Value = false,
	Callback = function(s)
		State.InfJump = s
		if InfJump_Conn then InfJump_Conn:Disconnect() InfJump_Conn = nil end
		if s then
			InfJump_Conn = UIS.JumpRequest:Connect(function()
				local hum = getHum()
				if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
			end)
		end
	end,
})

local Fullbright_Conn = nil
UtilMove:Toggle({
	Title = "全亮 (Fullbright)",
	Desc = "照亮整个场景",
	Value = false,
	Callback = function(s)
		State.Fullbright = s
		if Fullbright_Conn then Fullbright_Conn:Disconnect() Fullbright_Conn = nil end
		if s then
			Fullbright_Conn = Run.RenderStepped:Connect(function()
				Lighting.Brightness = 2
				Lighting.ClockTime = 14
				Lighting.FogEnd = 100000
				Lighting.GlobalShadows = false
			end)
		else
			Lighting.Brightness = 1
			Lighting.FogEnd = 100000
			Lighting.GlobalShadows = true
		end
	end,
})

local Plat = nil
local Plat_Conn = nil
UtilMove:Toggle({
	Title = "移动平台(脚下)",
	Desc = "在脚下生成跟随移动的平台",
	Value = false,
	Callback = function(s)
		State.Platform = s
		if Plat_Conn then Plat_Conn:Disconnect() Plat_Conn = nil end
		if s then
			Plat_Conn = Run.Heartbeat:Connect(function()
				if not State.Platform then return end
				local root = getHRP()
				if root then
					if not Plat or not Plat.Parent then
						Plat = Instance.new("Part")
						Plat.Size = Vector3.new(6, 1, 6)
						Plat.Anchored = true
						Plat.CanCollide = true
						Plat.Transparency = 0.5
						Plat.Color = Theme.Pink
						Plat.Parent = WS
					end
					Plat.Position = root.Position - Vector3.new(0, 3.5, 0)
				end
			end)
		else
			if Plat then Plat:Destroy() Plat = nil end
		end
	end,
})

local TPWalk_Conn = nil
UtilMove:Toggle({
	Title = "传送行走",
	Desc = "以传送方式移动",
	Value = false,
	Callback = function(s)
		State.TPWalk = s
		if TPWalk_Conn then TPWalk_Conn:Disconnect() TPWalk_Conn = nil end
		if s then
			TPWalk_Conn = Run.Heartbeat:Connect(function()
				if not State.TPWalk then return end
				local root = getHRP()
				local hum = getHum()
				if root and hum and hum.MoveDirection.Magnitude > 0 then
					root.CFrame = root.CFrame + hum.MoveDirection.Unit * State.TPWalkSpeed
				end
			end)
		end
	end,
})
UtilMove:Slider({
	Title = "传送行走速度",
	Desc = "传送行走每步距离",
	Step = 1,
	Value = { Min = 1, Max = 20, Default = 5 },
	Callback = function(v) State.TPWalkSpeed = v end,
})

local UtilChar = Tabs.Util:Section({ Title = "角色" })
UtilChar:Slider({
	Title = "移动速度",
	Desc = "角色 WalkSpeed",
	Step = 1,
	Value = { Min = 16, Max = 200, Default = 16 },
	Callback = function(v)
		State.WalkSpeed = v
		pcall(function() getHum().WalkSpeed = v end)
	end,
})
UtilChar:Slider({
	Title = "跳跃高度",
	Desc = "角色 JumpPower",
	Step = 1,
	Value = { Min = 50, Max = 300, Default = 50 },
	Callback = function(v)
		State.JumpPower = v
		pcall(function() getHum().JumpPower = v end)
	end,
})
UtilChar:Toggle({
	Title = "自动复活",
	Desc = "死亡后自动重新加载角色",
	Value = false,
	Callback = function(s)
		if s then startAutoRespawn() else stopAutoRespawn() end
	end,
})

local UtilMisc = Tabs.Util:Section({ Title = "杂项" })
UtilMisc:Button({
	Title = "远程储物柜",
	Desc = "开启远程储物柜访问",
	Callback = function()
		pcall(function()
			local lp = Players.LocalPlayer
			local backpack = lp.PlayerGui:WaitForChild("Backpack", 5)
			if not backpack then notify("未找到 Backpack") return end
			local holder = backpack:WaitForChild("Holder", 5)
			if not holder then notify("未找到 Holder") return end
			local locker = holder:WaitForChild("Locker", 5)
			if not locker then notify("未找到 Locker") return end
			backpack:GetPropertyChangedSignal("Enabled"):Connect(function()
				if backpack.Enabled then
					locker.Visible = true
				end
			end)
			if backpack.Enabled then
				locker.Visible = true
			end
			notify("远程储物柜已启用")
		end)
	end,
})
UtilMisc:Button({
	Title = "解锁全皮肤",
	Desc = "点击一次解锁所有皮肤",
	Callback = function()
		pcall(function()
			local ReplicatedStorage = game:GetService('ReplicatedStorage')
			local skinsModule = require(ReplicatedStorage.devv.client.Helpers.ui.screens.CaseMenu.Skins)
			local load = require(ReplicatedStorage.devv).load
			local state = load("state")
			hookfunction(skinsModule.AttemptEquip, function(self, itemName, skinName)
				local skinToEquip = skinName
				if self:IsSkinEquipped(itemName, skinName) then
					skinToEquip = nil
				end
				state.data.equippedSkins[itemName] = skinToEquip
				load("v3item").inventory.unequipAll()
				load("v3item").inventory.skinUpdate(itemName, skinToEquip)
				self:_setEquipped(itemName, skinToEquip)
				return true
			end)
			local skins = load("skins")
			for skinName in pairs(skins.skinData) do
				for _, itemName in pairs(skins.compatabilities.Generic) do
					state.data.ownedSkins[itemName] = state.data.ownedSkins[itemName] or {}
					state.data.ownedSkins[itemName][skinName] = 1
				end
			end
			notify("全皮肤已解锁")
		end)
	end,
})

local PlayerSection = Tabs.Players:Section({ Title = "操作" })
local PlayerSelectDropdown
PlayerSelectDropdown = PlayerSection:Dropdown({
	Title = "选择玩家",
	Desc = "选择要操作的玩家",
	Values = getPlayerNameList(),
	Multi = false,
	AllowNone = true,
	Value = nil,
	Callback = function(name)
		if name and name ~= "" then
			local target = Players:FindFirstChild(name)
			if target and target ~= LP then
				State.SelectedPlayer = target
				notify("已选择: " .. name)
			end
		end
	end,
})
PlayerSection:Button({
	Title = "刷新玩家下拉框",
	Desc = "刷新玩家列表",
	Callback = function()
		refreshPlayerLists()
		notify("玩家列表已刷新")
	end,
})
PlayerSection:Button({
	Title = "传送到玩家",
	Desc = "传送到选中玩家身边",
	Callback = function()
		local t = State.SelectedPlayer
		if not t or not isAlive(t) then notify("请先选择玩家") return end
		local hrp = getHRP() local tHRP = getHRP(t)
		if hrp and tHRP then hrp.CFrame = tHRP.CFrame + Vector3.new(0, 3, 0) end
	end,
})
PlayerSection:Button({
	Title = "把玩家拉过来",
	Desc = "把选中玩家拉到自己身边",
	Callback = function()
		local t = State.SelectedPlayer
		if not t or not isAlive(t) then notify("请先选择玩家") return end
		local tHRP = getHRP(t)
		if tHRP then tHRP.CFrame = getHRP().CFrame + Vector3.new(0, 3, 0) end
	end,
})
PlayerSection:Button({
	Title = "到玩家身后",
	Desc = "传送到选中玩家身后",
	Callback = function()
		local t = State.SelectedPlayer
		if not t or not isAlive(t) then notify("请先选择玩家") return end
		local hrp = getHRP() local tHRP = getHRP(t)
		if hrp and tHRP then hrp.CFrame = getBehindCFrame(tHRP) end
	end,
})
PlayerSection:Toggle({
	Title = "循环传送(身后)",
	Desc = "持续跟随选中玩家",
	Value = false,
	Callback = function(s)
		State.LoopTP = s
		if s then startLoopTP() else stopLoopTP() end
	end,
})
PlayerSection:Slider({
	Title = "循环间隔(秒)",
	Desc = "循环传送间隔",
	Step = 1,
	Value = { Min = 1, Max = 10, Default = 1 },
	Callback = function(v) State.LoopTP_Delay = v end,
})
PlayerSection:Toggle({
	Title = "拉近范围内玩家",
	Desc = "把范围内玩家吸到自己身边",
	Value = false,
	Callback = function(s)
		if s then startPull() else stopPull() end
	end,
})
PlayerSection:Slider({
	Title = "拉近距离",
	Desc = "拉近判定半径",
	Step = 1,
	Value = { Min = 5, Max = 50, Default = 10 },
	Callback = function(v) State.Pull_Distance = v end,
})

PlayerSection:Toggle({
	Title = "观战选中玩家",
	Desc = "镜头跟住选中玩家(目标死了自动退出)",
	Value = false,
	Callback = function(s)
		if s then
			State.Spectate = true
			if not startSpectate() then State.Spectate = false end
		else
			stopSpectate()
		end
	end,
})

local TeleportSection = Tabs.Teleport:Section({ Title = "坐标保存" })
TeleportSection:Button({
	Title = "保存当前坐标",
	Desc = "保存当前角色位置",
	Callback = function()
		saveCoord("坐标" .. #State.SavedCoords + 1)
	end,
})
TeleportSection:Button({
	Title = "坐标1",
	Desc = "传送到已保存的坐标1",
	Callback = function() tpCoord(1) end,
})
TeleportSection:Button({
	Title = "坐标2",
	Desc = "传送到已保存的坐标2",
	Callback = function() tpCoord(2) end,
})
TeleportSection:Button({
	Title = "坐标3",
	Desc = "传送到已保存的坐标3",
	Callback = function() tpCoord(3) end,
})
TeleportSection:Button({
	Title = "清空坐标",
	Desc = "清空已保存的坐标",
	Callback = function()
		table.clear(State.SavedCoords)
		notify("已清空坐标")
	end,
})
TeleportSection:Button({
	Title = "回传出生点",
	Desc = "传送到地图出生点",
	Callback = function()
		pcall(function()
			local sp = WS.Spawns:FindFirstChildOfClass("SpawnLocation")
			if sp then getHRP().CFrame = sp.CFrame + Vector3.new(0, 3, 0) end
		end)
	end,
})

local ServerSection = Tabs.Server:Section({ Title = "服务器" })
ServerSection:Button({
	Title = "重新加入本服",
	Desc = "重新连接到当前服务器",
	Callback = function() rejoin() end,
})
ServerSection:Button({
	Title = "换服务器(低人数)",
	Desc = "切换到人少的公共服务器",
	Callback = function() serverHop() end,
})

local CustomSection = Tabs.Custom:Section({ Title = "预设脚本" })
CustomSection:Button({
	Title = "无限血量 (Local)",
	Desc = "本地锁定满血",
	Callback = function() execCustom(1) end,
})
CustomSection:Button({
	Title = "清空背包",
	Desc = "清空本地背包",
	Callback = function() execCustom(2) end,
})
CustomSection:Button({
	Title = "显示 FPS",
	Desc = "在屏幕左上角显示 FPS",
	Callback = function() execCustom(3) end,
})

LP.CharacterAdded:Connect(function()
	if FlyingEnabled then
		task.wait(0.5)
		stopFlying()
		task.wait(0.1)
		startFlying()
	end
end)

notify("case | Tp_fly  飞行已接入")
print("case | WindUI 版加载完成 (Yttrium 飞行已缝合)")

local rpgAttackEnabled = false
local rpgAttackDistance = 100
local rpgMinHealth = 0.3
local autoBuyRPGAmmo = false
local rpgBuyTimer = 0
local rpgBuyInterval = 10
local hitPart = "Head"
local rpgBuyLocation = CFrame.new(
	1145.82153, 25.5613174, -1322.12683,
	-0.173624277, 0, -0.984811902,
	0, 1, 0,
	0.984811902, 0, -0.173624277
)

local function ensureRPG()
	local hasRPG = false
	for _, v in pairs(items) do
		if v.name == "RPG" or v.name == "Trident" then
			hasRPG = true
			FireServer("equip", v.guid)
			break
		end
	end
	if not hasRPG then
		purchaseItem("RPG", rpgBuyLocation)
		task.wait(0.2)
		refreshItems()
		for _, v in pairs(items) do
			if v.name == "RPG" then
				FireServer("equip", v.guid)
				break
			end
		end
	end
end

local function startRPGAttack()
	task.spawn(function()
		ensureRPG()
		local same = { GUID() }
		while rpgAttackEnabled do
			if not LocalPlayer.Character or not getRoot(LocalPlayer.Character) then
				task.wait(0.5)
			else
				local equippedItem = v3item.inventory.getEquippedItem()
				if not equippedItem or (equippedItem.name ~= "RPG" and equippedItem.name ~= "Trident") then
					task.wait(0.1)
				else
					local equippedGUID = equippedItem.guid
					local friendIDs = {}
					for _, player in pairs(Players:GetPlayers()) do
						if player ~= LocalPlayer then
							local success, isFriend = pcall(function()
								return LocalPlayer:IsFriendsWith(player.UserId)
							end)
							if success and isFriend then
								table.insert(friendIDs, player.UserId)
							end
						end
					end
					local myRoot = getRoot(LocalPlayer.Character)
					if myRoot then
						for _, player in pairs(Players:GetPlayers()) do
							if not rpgAttackEnabled then break end
							if player ~= LocalPlayer and player.Character then
								local isTarget = false
								if #targetPlayers > 0 then
									isTarget = tableFind(targetPlayers, player.Name)
								else
									isTarget = true
								end
								if isTarget then
									local isFriend = false
									for _, friendID in pairs(friendIDs) do
										if player.UserId == friendID then
											isFriend = true
											break
										end
									end
									if not isFriend then
										local character = player.Character
										local humanoid = character:FindFirstChild("Humanoid")
										local targetPart = character:FindFirstChild(hitPart)
										local targetRoot = character:FindFirstChild("HumanoidRootPart")
										if humanoid and targetPart and targetRoot and humanoid.Health > rpgMinHealth then
											local distance = (myRoot.Position - targetRoot.Position).magnitude
											if distance <= rpgAttackDistance then
												local replicateArgs = { equippedGUID }
												local projectileData = { { same[1], targetPart.CFrame } }
												replicateArgs[2] = projectileData
												replicateArgs[3] = "semi"
												FireServer("replicateProjectiles", unpack(replicateArgs))
												local rocketArgs = { same[1], GUID(), targetPart.Position }
												for i = 1, 5 do
													FireServer("rocketHit", unpack(rocketArgs))
												end
												FireServer("reload", equippedGUID)
											end
										end
									end
								end
							end
						end
					end
				end
			end
			task.wait(0.1)
		end
	end)
end

task.spawn(function()
	while true do
		task.wait(1)
		if autoBuyRPGAmmo and rpgAttackEnabled then
			rpgBuyTimer = rpgBuyTimer + 1
			if rpgBuyTimer >= rpgBuyInterval then
				rpgBuyTimer = 0
				local equippedItem = v3item.inventory.getEquippedItem()
				if equippedItem and (equippedItem.name == "RPG" or equippedItem.name == "Trident") then
					local root = getRoot(LocalPlayer.Character)
					if root then
						local originalCF = root.CFrame
						root.CFrame = rpgBuyLocation
						local startTime = tick()
						while tick() - startTime < 3 do
							InvokeServer("attemptPurchaseAmmo", equippedItem.name)
							task.wait(0.03)
						end
						root.CFrame = originalCF
					end
				end
			end
		else
			rpgBuyTimer = 0
		end
	end
end)

local selectedWeapon = "Gun Kill"
local selectedGun = "Raygun"
local gunKillAutoTP = false
local forceEquipEnabled = false
local gunRapidFire = false
local autoBuyGunAmmo = false
local gunBuyTimer = 0
local gunBuyInterval = 10
local BUY_AMMO_COUNT = 10
local gunBuyLocations = {
	["Raygun"] = CFrame.new(147.022064, -98.0489502, -529.441406, 0, 0, 1, 0, 1, -0, -1, 0, 0),
	["M4A1"] = CFrame.new(603.467651, 25.6628113, -922.04425, 1, 0, 0, 0, 1, 0, 0, 0, 1),
	["AK47"] = CFrame.new(1628.71704, 6.15060806, -620.919617, 0.087131381, -0, -0.996196866, 0, 1, -0, 0.996196866, 0, 0.087131381),
}

local function prepareGunKillWeapon()
	local hasGun = false
	for _, v in pairs(items) do
		if v.name == selectedGun then
			hasGun = true
			FireServer("equip", v.guid)
			break
		end
	end
	if not hasGun then
		local buyLoc = gunBuyLocations[selectedGun]
		local root = getRoot(LocalPlayer.Character)
		if root and buyLoc then
			local originalCF = root.CFrame
			root.CFrame = buyLoc
			task.wait(0.5)
			InvokeServer("attemptPurchase", selectedGun)
			task.wait(0.3)
			refreshItems()
			for _, v in pairs(items) do
				if v.name == selectedGun then
					FireServer("equip", v.guid)
					break
				end
			end
			root.CFrame = originalCF
		end
	end
end

local function gunKillAttack(target)
	local targetPos = target.Position
	local player = Players:GetPlayerFromCharacter(target.Parent)
	if not player or player == LocalPlayer then return end
	if isPlayerProtected(player) then return end
	if forceEquipEnabled then
		local guid = getGuid(selectedGun)
		if guid then
			pcall(function()
				v3item.inventory.setEquipped(guid)
			end)
			task.wait(0.01)
		end
	end
	local item = v3item.inventory.getEquippedItem()
	if not item or item.type ~= "Gun" then return end
	if not gunRapidFire and item.ammoManager and item.ammoManager.ammo <= 0 then
		FireServer("reload", item.guid)
		return
	end
	local g = GUID()
	createTrace(targetPos)
	FireServer("replicateProjectiles", item.guid, {
		{ g, target.CFrame }
	}, item.firemode)
	FireServer("projectileHit", g, "player", {
		hitSize = target.Size,
		hitPart = target,
		pos = targetPos,
		hitPlayerId = player.UserId
	})
	if item.ammoManager then
		item.ammoManager.ammo = item.ammoManager.ammo - 1
	end
end

task.spawn(function()
	while true do
		task.wait(1)
		if autoBuyGunAmmo and selectedWeapon == "Gun Kill" and selectedGun ~= "Raygun" then
			gunBuyTimer = gunBuyTimer + 1
			if gunBuyTimer >= gunBuyInterval then
				gunBuyTimer = 0
				local item = v3item.inventory.getEquippedItem()
				if item and item.type == "Gun" and item.name == selectedGun then
					local buyLoc = gunBuyLocations[selectedGun]
					local root = getRoot(LocalPlayer.Character)
					if root and buyLoc then
						local originalCF = root.CFrame
						root.CFrame = buyLoc
						task.wait(0.2)
						for i = 1, BUY_AMMO_COUNT do
							InvokeServer("attemptPurchaseAmmo", item.name)
							task.wait(0.05)
						end
						root.CFrame = originalCF
					end
				end
			end
		else
			gunBuyTimer = 0
		end
	end
end)

local skinsec = "Sparkler"
local autoskin = false
local skinMap = {
	["烟火"] = "Sparkler", ["虚空"] = "Void", ["纯金"] = "Solid Gold", ["暗物质"] = "Dark Matter",
	["反物质"] = "Anti Matter", ["神秘"] = "Hystic", ["虚空神秘"] = "Void Mystic", ["战术"] = "Tactical",
	["纯金战术"] = "Solid Gold Tactical", ["白未来"] = "Future White", ["黑未来"] = "Future Black",
	["圣诞未来"] = "Christmas Future", ["礼物包装"] = "Gift Wrapped", ["猩红"] = "Crimson Blood",
	["收割者"] = "Reaper", ["虚空收割者"] = "Void Reaper", ["圣诞玩具"] = "Christmas Toy",
	["荒地"] = "Wasteland", ["隐形"] = "Invisible", ["像素"] = "Pixel", ["钻石像素"] = "Diamond Pixel",
	["黄金零下"] = "Frozen-Gold", ["绿水晶"] = "Atomic Nature", ["生物"] = "Biohazard",
	["樱花"] = "Sakura", ["精英"] = "Elite", ["黑樱花"] = "Death Blossom-Gold",
	["彩虹激光"] = "Rainbowlaser", ["蓝水晶"] = "Atomic Water", ["紫水晶"] = "Atomic Amethyst",
	["红水晶"] = "Atomic Flame", ["零下"] = "Sub-Zero", ["虚空射线"] = "Void-Ray",
	["冰冻钻石"] = "Frozen Diamond", ["虚空梦魇"] = "Void Nightmare", ["金雪"] = "Golden Snow",
	["爱国者"] = "Patriot", ["MM2"] = "MM2 Barrett", ["声望"] = "Prestige Barnett",
	["酷化"] = "Skin Walter", ["蒸汽"] = "Steampunk", ["海盗"] = "Pirate", ["玫瑰"] = "Rose",
	["黑玫瑰"] = "Black Rose", ["激光"] = "Hyperlaser", ["烟花"] = "Firework",
	["诅咒背瓜"] = "Cursed Pumpkin", ["大炮"] = "Cannon", ["财富"] = "Firework",
	["黄金大炮"] = "Gold Cannon", ["四叶草"] = "Lucky Clover", ["自由"] = "Freedom",
	["黑曜石"] = "Obsidian", ["赛博朋克"] = "Cyberpunk",
}

local function applySkinToGuns()
	if not autoskin then return end
	pcall(function()
		local it = require(RS.devv).load("v3item").inventory
		local b1 = require(RS.devv).load('v3item').inventory.items
		for i, item in next, b1 do
			if item.type == "Gun" then
				it.skinUpdate(item.name, skinsec)
			end
		end
	end)
end

local function enableBlackRoseBalloon()
	pcall(function()
		for _, v in pairs(getgc(true)) do
			if type(v) == "table" and rawget(v, "name") == "Balloon" and rawget(v, "holdableType") == "Balloon" then
				v.name, v.cost, v.unpurchasable, v.multiplier, v.movespeedAdd, v.cannotDiscard = "Black Rose", 200, true, 0.75, 12, true
				if v.TPSOffsets then v.TPSOffsets.hold = CFrame.new(0, 0.5, 0) end
				if v.viewportOffsets and v.viewportOffsets.hotbar then v.viewportOffsets.hotbar.dist = 3 end
				v.canDrop, v.dropCooldown, v.craft = nil
				break
			end
		end
		for _, item in pairs(require(RS.devv.client.Objects.v3item.modules.inventory).items) do
			if item.name == "Black Rose" then
				for _, btn in pairs({ item.button, item.backpackButton }) do
					if btn and btn.resetModelSkin then btn:resetModelSkin() end
				end
			end
		end
	end)
end

local function enableDollarBalloon()
	pcall(function()
		for _, v in pairs(getgc(true)) do
			if type(v) == "table" and rawget(v, "name") == "Balloon" and rawget(v, "holdableType") == "Balloon" then
				v.name, v.cost, v.unpurchasable, v.multiplier, v.movespeedAdd, v.cannotDiscard = "Dollar Balloon", 200, true, 0.8, 8, true
				if v.TPSOffsets then v.TPSOffsets.hold = CFrame.new(0, 0, 0) * CFrame.Angles(0, math.pi, 0) end
				if v.viewportOffsets and v.viewportOffsets.hotbar then v.viewportOffsets.hotbar.dist = 4 end
				v.canDrop, v.dropCooldown, v.craft = nil
				break
			end
		end
		for _, item in pairs(require(RS.devv.client.Objects.v3item.modules.inventory).items) do
			if item.name == "Dollar Balloon" then
				for _, btn in pairs({ item.button, item.backpackButton }) do
					if btn and btn.resetModelSkin then btn:resetModelSkin() end
				end
			end
		end
	end)
end

local function spawnSpiritKunai()
	pcall(function()
		local itemSystem = require(RS.devv).load("v3item")
		local inventory = itemSystem.inventory
		local spiritKunaiData = {
			name = "Spirit Kunai",
			guid = "spirit_kunai_" .. tostring(tick()),
			permanent = true,
			canDrop = true,
			dropCooldown = 120,
			holdableType = "Kunai",
			movespeedAdd = 12,
			TPSOffsets = { hold = CFrame.new(0, -0.3, 0) },
			viewportOffsets = {
				hotbar = { dist = 3, offset = CFrame.new(0, 0, 0), rotoffset = CFrame.Angles(0, 1.5707963267948966, 0) },
				ammoHUD = { dist = 2, offset = CFrame.new(-0.1, -0.2, 0), rotoffset = CFrame.Angles(0, -1.3744467859455345, 0) },
				slotButton = { dist = 1, offset = CFrame.new(-0.1, -0.2, 0), rotoffset = CFrame.Angles(0, -1.5707963267948966, 0) }
			},
			FPSOffsets = {}
		}
		if inventory.add then
			inventory.add(spiritKunaiData, false)
			if inventory.currentItemsData then table.insert(inventory.currentItemsData, spiritKunaiData) end
		end
		if inventory.rerender then inventory:rerender() end
	end)
end

spawn(function() applySkinToGuns() end)

local ExtraSec = Tabs.Custom:Section({ Title = "Ohio 隐藏功能" })

ExtraSec:Button({
	Title = "黑玫瑰气球",
	Desc = "把普通气球改写成 Black Rose(改的是内存里的道具数据)",
	Callback = function()
		enableBlackRoseBalloon()
		notify("黑玫瑰气球: 已执行(失败就不生效, 不会崩)", 4)
	end,
})
ExtraSec:Button({
	Title = "美元气球",
	Desc = "把普通气球改写成 Dollar Balloon",
	Callback = function()
		enableDollarBalloon()
		notify("美元气球: 已执行(失败就不生效, 不会崩)", 4)
	end,
})
ExtraSec:Button({
	Title = "生成精神苦无",
	Desc = "往背包塞一把 Spirit Kunai",
	Callback = function()
		spawnSpiritKunai()
		notify("精神苦无: 已执行(失败就不生效, 不会崩)", 4)
	end,
})

ExtraSec:Toggle({
	Title = "自动换皮肤",
	Desc = "给所有枪自动套用下面选的皮肤",
	Value = false,
	Callback = function(v)
		autoskin = v
		if v then
			applySkinToGuns()
			notify("自动换皮肤: " .. skinsec)
		else
			notify("自动换皮肤已关(已换上的不会自动还原)")
		end
	end,
})
ExtraSec:Dropdown({
	Title = "选择皮肤",
	Desc = "英文原名, 对应左边皮肤表",
	Values = { "Sparkler", "Void", "Solid Gold", "Dark Matter", "Anti Matter", "Hystic", "Void Mystic", "Tactical", "Solid Gold Tactical", "Future White", "Future Black", "Christmas Future", "Gift Wrapped", "Crimson Blood", "Reaper", "Void Reaper", "Christmas Toy", "Wasteland", "Invisible", "Pixel", "Diamond Pixel", "Frozen-Gold", "Atomic Nature", "Biohazard", "Sakura", "Elite", "Death Blossom-Gold", "Rainbowlaser", "Atomic Water", "Atomic Amethyst", "Atomic Flame", "Sub-Zero", "Void-Ray", "Frozen Diamond", "Void Nightmare", "Golden Snow", "Patriot", "MM2 Barrett", "Prestige Barnett", "Skin Walter", "Steampunk", "Pirate", "Rose", "Black Rose", "Hyperlaser", "Firework", "Cursed Pumpkin", "Cannon", "Gold Cannon", "Lucky Clover", "Freedom", "Obsidian", "Cyberpunk" },
	Multi = false,
	AllowNone = false,
	Value = "Sparkler",
	Callback = function(v)
		if v and v ~= "" then
			skinsec = v
			if autoskin then applySkinToGuns() end
		end
	end,
})

local RPGSec = Tabs.Combat:Section({ Title = "RPG / 枪械 (需 RS.devv)" })
RPGSec:Toggle({
	Title = "RPG 自动攻击",
	Desc = "手持 RPG/Trident 时自动开火(黑名单非空则只打黑名单)",
	Value = false,
	Callback = function(v)
		if v then
			if not DEVV_OK then
				notify("RS.devv 未加载, 仅 Ohio 服可用")
				return
			end
			rpgAttackEnabled = true
			startRPGAttack()
			notify("RPG 自动攻击已开启(会自动买 RPG)")
		else
			rpgAttackEnabled = false
			notify("RPG 自动攻击已关闭")
		end
	end,
})
RPGSec:Slider({
	Title = "RPG 攻击距离",
	Desc = "RPG 自动攻击最大距离",
	Step = 5,
	Value = { Min = 20, Max = 300, Default = 100 },
	Callback = function(v) rpgAttackDistance = v end,
})
RPGSec:Toggle({
	Title = "RPG 自动买弹",
	Desc = "每隔一段时间自动去购买 RPG 弹药",
	Value = false,
	Callback = function(v) autoBuyRPGAmmo = v end,
})
RPGSec:Dropdown({
	Title = "枪械自动买弹",
	Desc = "选一把枪, 手持它时自动补弹",
	Values = { "不补弹", "M4A1", "AK47" },
	Multi = false,
	AllowNone = false,
	Value = "不补弹",
	Callback = function(v)
		if v == "不补弹" then
			autoBuyGunAmmo = false
		else
			selectedGun = v
			autoBuyGunAmmo = true
			notify("自动补弹: " .. v)
		end
	end,
})
RPGSec:Slider({
	Title = "买弹间隔(秒)",
	Desc = "RPG / 枪械自动买弹的间隔",
	Step = 1,
	Value = { Min = 3, Max = 60, Default = 10 },
	Callback = function(v)
		rpgBuyInterval = v
		gunBuyInterval = v
	end,
})

print("[case] 全部加载完成 ✅")

local Farm = {}
Farm.s = {
	busy = false,
	mode = "Normal",
	idle = "TeTraX",
	maskBuying = false,
	gemRubbleCD = 0,
	gemRubbleTime = 30,
	itemAuraTimer = 0,
	itemAuraInterval = 0.1,
	rewardLoop = false,
	autoSellTask = nil,
	maskType = "黑色头巾",
	maskAutoBuy = true,
	gATM = false, gBank = false, gCashReg = false, gGemRubble = false,
	gTruckCash = false, gJewel = false, gSafe = false, gComponent = false,
	gSlot = false, gTreasure = false, gAirdrop = false, gWork = false,
	gStoreGems = false, gRentHouse = false, gClean = false,
	unlockAura = false, cashAura = false, itemAura = false,
	autoSell = false, autoRemove = false, autoConsume = false,
	autoCraft = false, autoClaim = false, autoStoreGems = false,
	autoVest = false, autoHeal = false, autoMask = false,
	antiSit = true, antiGrab = true, antiIdle = true,
	antiVoid = false, antiAdmin = false, bigFOV = false,
	findBlock = false, findPresent = false, findRareGem = false,
	findGem = false, findPrinter = false, findCard = false,
	pickRare = false, pickBalloon = false, stealBank = false,
	killEnabled = false, killTP = false, forceEquip = false, rapidFire = false,
}

do
	local S = Farm.s
	Farm.idleLocations = {
		["TeTraX"] = CFrame.new(1653.397216796875, -16.95315170288086, -530.3738403320312),
		["宿傩"] = CFrame.new(121.4214859008789, -42.42018508911133, -515.8087158203125),
		["位置1"] = CFrame.new(439.01190185546875, -25.120525360107422, -822.7509155273438),
		["位置2"] = CFrame.new(386.4916076660156, 3.1478753089904785, -1359.7310791015625),
		["位置3"] = CFrame.new(490.7265930175781, -22.4210262298584, -272.43170166015625),
		["位置4"] = CFrame.new(160.63153076171875, -33.42034912109375, -445.28424072265625),
		["位置5"] = CFrame.new(584.040283203125, -86.82018280029297, -724.7525634765625),
		["位置6"] = CFrame.new(1021.9706420898438, -21.59579086303711, 89.16853332519531),
		["位置7"] = CFrame.new(575.1665649414062, -40.00355911254883, -88.20584869384766),
		["位置8"] = CFrame.new(1410.9215087890625, -9.405234336853027, 714.591064453125),
		["位置9"] = CFrame.new(681.484619140625, -54.65692138671875, -337.3169860839844),
		["位置10"] = CFrame.new(-151048.375, 978.26171875, -88558.4609375),
		["位置11"] = CFrame.new(1740.39306640625, -48.72824478149414, -881.3480834960938),
	}
	Farm.getCurrentIdleCF = function()
		return Farm.idleLocations[S.idle] or Farm.idleLocations["TeTraX"]
	end

	Farm.lockpickBuyLocation = CFrame.new(659.280029, 5.50683689, -716.48999, -1.1920929e-07, 0, -1.00000012, 0, 1, 0, 1.00000012, 0, -1.1920929e-07)
	Farm.grenadeBuyLocation = CFrame.new(659.044739, 5.77163315, -706.697632, -1.1920929e-07, 0, -1.00000012, 0, 1, 0, 1.00000012, 0, -1.1920929e-07)
	Farm.bombThrowLocation = CFrame.new(1129.0994873046875, 14.843579292297363, -354.19488525390625)
	Farm.bombTargetPosition = Vector3.new(1124.0853271484, 5.3128666877747, -357.68710327148)
	Farm.afterExplosionWaitLocation = CFrame.new(1112.95142, 16.6149864, -331.99646, 0, 0, -1, 0, 1, 0, 1, 0, 0)
	Farm.bandageBuyLocation = CFrame.new(1168.04468, 25.0443974, -972.782654, 0, 0, -1, 0, 1, 0, 1, 0, 0)

	Farm.maskLocations = {
		["黑色头巾"] = CFrame.new(604.114014, 5.09485245, -1018.1275, 0, 0, 1, 0, 1, -0, -1, 0, 0),
		["红色头巾"] = CFrame.new(604.021545, 4.99485302, -1025.21191, 0, 0, 1, 0, 1, -0, -1, 0, 0),
		["蓝色头巾"] = CFrame.new(604.113892, 5.09485245, -1010.82751, 0, 0, 1, 0, 1, -0, -1, 0, 0),
		["外科医生口罩"] = CFrame.new(1160.00659, 4.65769672, -975.317871, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		["面具"] = CFrame.new(1438.61926, 6.60790443, -145.005386, 1, 0, 0, 0, 1, 0, 0, 0, 1),
	}
	Farm.maskNames = {
		["黑色头巾"] = "Black Bandana",
		["红色头巾"] = "Red Bandana",
		["蓝色头巾"] = "Blue Bandana",
		["外科医生口罩"] = "Surgeon Mask",
		["面具"] = "Hockey Mask",
	}

	Farm.bankCashExists = function()
		local bank = WS:FindFirstChild("BankRobbery")
		if not bank then return false end
		local bc = bank:FindFirstChild("BankCash")
		if not bc then return false end
		local cash = bc:FindFirstChild("Cash")
		return cash and #cash:GetChildren() > 0
	end

	Farm.ensureItem = function(itemName, buyLocation)
		for _, v in pairs(items) do
			if v.name == itemName then return v.guid end
		end
		local root = getRoot(LP.Character)
		if root then