local Debris = game:GetService("Debris")
local Workspace: Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players: Players = game:GetService("Players")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local remoteEventsFolder: Folder = ReplicatedStorage:WaitForChild("RemoteEvents")
local zombieHealthUpdate: RemoteEvent =
	remoteEventsFolder:WaitForChild("ZombieHealthUpdate") :: RemoteEvent
local playerClimbsTheTurret: RemoteEvent =
	remoteEventsFolder:WaitForChild("PlayerClimbsTheTurret") :: RemoteEvent
local onLaserTurretRaycast: RemoteEvent =
	remoteEventsFolder:WaitForChild("OnLaserTurretRaycast") :: RemoteEvent
local animationRotatingCannonsAllClients: RemoteEvent =
	remoteEventsFolder:WaitForChild("AnimationRotatingCannonsAllClients") :: RemoteEvent
local updateLaserTurretPosition: RemoteEvent =
	remoteEventsFolder:WaitForChild("UpdateLaserTurretPosition") :: RemoteEvent
local animationOnMountLaserTurret: RemoteEvent =
	remoteEventsFolder:WaitForChild("AnimationOnMountLaserTurret") :: RemoteEvent
local enabledLaserTurretGui: RemoteEvent =
	remoteEventsFolder:WaitForChild("EnabledLaserTurretGui") :: RemoteEvent
local wallFolder: Folder = Workspace:WaitForChild("Wall") :: Folder
local laserHole: Part = ServerStorage:WaitForChild("LaserHole") :: Part
local laserHoles: Folder = Workspace:WaitForChild("LaserHoles") :: Folder
local eventsAlreadyTriggered: {} =
	{ animationRotatingCannonsAllClients = {}, playerClimbsTheTurret = {} }

updateLaserTurretPosition.OnServerEvent:Connect(
	function(player: Player, newLaserTurretRotation: CFrame, laserTurret: Model)
		local weldsFolder: Folder = laserTurret:WaitForChild("Welds") :: Folder
		local weld: Weld = weldsFolder:WaitForChild("BottomSmallPartWithTop") :: Weld
		weld.C1 = CFrame.new(weld.C1.Position) * newLaserTurretRotation
	end
)

animationOnMountLaserTurret.OnServerEvent:Connect(
	function(player: Player, actionName: string, laserTurret: Model, finalCFrame: CFrame)
		if actionName == "Place CFrame" then
			local weldsFolder: Folder = laserTurret:WaitForChild("Welds") :: Folder
			local weld: Weld = weldsFolder:WaitForChild("BottomSmallPartWithTop") :: Weld
			weld.C1 = finalCFrame
		else
			animationOnMountLaserTurret:FireAllClients(player, laserTurret, actionName)
		end
	end
)

enabledLaserTurretGui.OnServerEvent:Connect(function(player: Player, laserTurretGuiName: string)
	local playerGui: PlayerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	local laserTurretGui: ScreenGui = playerGui:WaitForChild("LaserTurretGui") :: ScreenGui
	if laserTurretGui.Enabled then
		laserTurretGui.Enabled = false
	else
		laserTurretGui.Enabled = true
	end
end)

local function dismountThePlayerFromTheTurret(
	player: Player,
	laserTurret: Model,
	playerDead: boolean
)
	local character: Model = player.Character or player.CharacterAdded:Wait()
	local laserTurretBigBottomPart: MeshPart =
		laserTurret:WaitForChild("LaserTurretBigBottomPart") :: MeshPart
	local spawnLocationOnDismount: Attachment =
		laserTurretBigBottomPart:WaitForChild("SpawnLocationOnDismount") :: Attachment
	local laserTurretTop: MeshPart = laserTurret:WaitForChild("LaserTurretTop") :: MeshPart
	local weld: Weld = laserTurretTop:WaitForChild("PlayerAndLaserTurretWeld") :: Weld
	weld.Part1 = nil
	weld:Destroy()
	if playerDead then
		return
	end
	task.wait(0.05)
	character:PivotTo(spawnLocationOnDismount.WorldCFrame)
end

local function attachCharacterToTurret(player: Player, laserTurret: Model)
	local character: Model = player.Character or player.CharacterAdded:Wait()
	if character == nil then
		warn(
			"Character of player "
				.. player.Name
				.. " not found in onButtonActivated to mount laser laserTurret"
		)
		return
	end

	local humanoidRootPart: BasePart = character:WaitForChild("HumanoidRootPart") :: BasePart
	if humanoidRootPart == nil then
		warn(
			"HumanoidRootPart of player: "
				.. player.Name
				.. " not found in the player character in onButtonActivated to mount laser laserTurret"
		)
		return
	end
	local OFFSET_WITHIN_THE_TOWER = 3
	local laserTurretTop: MeshPart = laserTurret:WaitForChild("LaserTurretTop") :: MeshPart
	local weld: Weld = Instance.new("Weld")
	weld.Name = "PlayerAndLaserTurretWeld"
	weld.Parent = laserTurretTop
	weld.Enabled = true
	weld.Part0 = laserTurretTop
	weld.Part1 = humanoidRootPart
	weld.C1 = CFrame.new(0, OFFSET_WITHIN_THE_TOWER, 0)
end

playerClimbsTheTurret.OnServerEvent:Connect(
	function(player: Player, desolderCharacter: boolean, laserTurret: Model, playerDead: boolean)
		if desolderCharacter then
			dismountThePlayerFromTheTurret(player, laserTurret, playerDead)
			playerClimbsTheTurret:FireAllClients(player, desolderCharacter)
		else
			attachCharacterToTurret(player, laserTurret)
			playerClimbsTheTurret:FireAllClients(player, desolderCharacter)
		end
		eventsAlreadyTriggered["playerClimbsTheTurret"][player] = { player, desolderCharacter }
	end
)

local function characterTakesLaserTurretDamage(
	playerWhoCausedDamage: Player,
	raycastResult: RaycastResult,
	damage: number
)
	local character: Model = raycastResult.Instance:FindFirstAncestorOfClass("Model") :: Model
	if character == nil then
		return
	end
	local humanoid: Humanoid = character:FindFirstChild("Humanoid") :: Humanoid
	if humanoid == nil then
		return
	end
	humanoid:TakeDamage(damage)
	if character.Name == "zombie" then
		zombieHealthUpdate:FireClient(playerWhoCausedDamage, humanoid.Health, character)
	end
end

local function createLaserHole(raycastResult: RaycastResult)
	if raycastResult.Instance.Name == "LaserHole" then
		return
	end
	if raycastResult.Instance:IsA("Part") or raycastResult.Instance:IsA("MeshPart") then
		local character: Model? = raycastResult.Instance:FindFirstAncestorOfClass("Model")
		if character then
			local humanoid: Humanoid = character:FindFirstChild("Humanoid") :: Humanoid
			if humanoid then
				return
			end
		end
		local laserHoleOverlapParams: OverlapParams = OverlapParams.new()
		laserHoleOverlapParams.FilterType = Enum.RaycastFilterType.Include
		laserHoleOverlapParams.FilterDescendantsInstances = { laserHoles }
		local partsInArea = Workspace:GetPartBoundsInRadius(
			raycastResult.Position,
			laserHole.Size.Z,
			laserHoleOverlapParams
		)
		local canPutLaserHole: boolean = true
		if next(partsInArea) ~= nil then
			for _, part in partsInArea do
				local distanceToLaserHole: number = (raycastResult.Position - part.Position).Magnitude
				if distanceToLaserHole < (laserHole.Size.Z / 2) then
					canPutLaserHole = false
				end
			end
		end
		if not canPutLaserHole then
			return
		end
		local totalLaserHoles: number = #laserHoles:GetChildren()
		local laserHoleClone: Part = laserHole:Clone()
		laserHoleClone.Name = "laserHole" .. tostring(totalLaserHoles + 1)
		laserHoleClone.CFrame = CFrame.new(
			raycastResult.Position + Vector3.new(0, 0.01, 0),
			raycastResult.Position + raycastResult.Normal
		) * CFrame.Angles(0, math.rad(90), 0)
		laserHoleClone.Parent = laserHoles
		if totalLaserHoles % 2 == 0 then
			laserHoleClone.Position = Vector3.new(
				laserHoleClone.Position.X,
				laserHoleClone.Position.Y + 0.01,
				laserHoleClone.Position.Z
			)
		end
		Debris:AddItem(laserHoleClone, 1)
	else
		return
	end
end

onLaserTurretRaycast.OnServerEvent:Connect(
	function(
		player: Player,
		leftLaserOriginWorldPosition: Vector3,
		rightLaserOriginWorldPosition: Vector3,
		leftLookVector1: Vector3,
		rightLookVector1: Vector3,
		CAMERA_RAY_LENGTH,
		laserTurret,
		damage: number
	)
		local raycastParams: RaycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = { laserTurret, wallFolder, laserHoles }
		local leftRaycastResult: RaycastResult = Workspace:Raycast(
			leftLaserOriginWorldPosition,
			leftLookVector1 * CAMERA_RAY_LENGTH,
			raycastParams
		) :: RaycastResult
		local rightRaycastResult: RaycastResult = Workspace:Raycast(
			rightLaserOriginWorldPosition,
			rightLookVector1 * CAMERA_RAY_LENGTH,
			raycastParams
		) :: RaycastResult
		if leftRaycastResult then
			task.spawn(createLaserHole, leftRaycastResult)
			characterTakesLaserTurretDamage(player, leftRaycastResult, damage)
		end
		if rightRaycastResult then
			task.spawn(createLaserHole, rightRaycastResult)
			characterTakesLaserTurretDamage(player, rightRaycastResult, damage)
		end
	end
)

animationRotatingCannonsAllClients.OnServerEvent:Connect(function(player: Player, ...)
	local arguments = { ... } -- { rotatingCannonsOff: boolean, LaserTurret: Model }
	animationRotatingCannonsAllClients:FireAllClients(player, arguments[1], arguments[2])
	eventsAlreadyTriggered["animationRotatingCannonsAllClients"][player] =
		{ player, arguments[1], arguments[2] }
end)

Players.PlayerAdded:Connect(function(player: Player)
	local _character: Model = player.Character or player.CharacterAdded:Wait()
	if
		next(eventsAlreadyTriggered["playerClimbsTheTurret"]) ~= nil
		or next(eventsAlreadyTriggered["animationRotatingCannonsAllClients"]) ~= nil
	then
		for eventName, array in eventsAlreadyTriggered do
			if eventName == "playerClimbsTheTurret" then
				for playerInArray, arguments in array do
					playerClimbsTheTurret:FireClient(player, arguments[1], arguments[2])
				end
			elseif eventName == "animationRotatingCannonsAllClients" then
				for playerInArray, arguments in array do
					animationRotatingCannonsAllClients:FireClient(
						player,
						arguments[1],
						arguments[2],
						arguments[3]
					)
				end
			end
		end
	end
end)
