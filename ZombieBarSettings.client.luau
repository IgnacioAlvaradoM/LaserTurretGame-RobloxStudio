local RunService: RunService = game:GetService("RunService")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerGui: PlayerGui = script.Parent.Parent

local TIME_TO_CLOSE_ZOMBIE_HEALTH: number = 1

local remoteEventsFolder: Folder = ReplicatedStorage:WaitForChild("RemoteEvents") :: Folder
local zombieHealthUpdate: RemoteEvent = remoteEventsFolder:WaitForChild("ZombieHealthUpdate") :: RemoteEvent
local laserTurretGui: ScreenGui = PlayerGui:WaitForChild("LaserTurretGui") :: ScreenGui
local backPartZombieHealthBar: Frame = laserTurretGui:WaitForChild("ZombieHealthBar") :: Frame
local frontPartZombieHealthBar: Frame = backPartZombieHealthBar:WaitForChild("Bar") :: Frame
local healthText: TextLabel = backPartZombieHealthBar:WaitForChild("HealthText") :: TextLabel
local startPosition: UDim2 = frontPartZombieHealthBar.Position
local endPosition: UDim2 = UDim2.new(0, 0, 0.5, 0)
local startSize: UDim2 = frontPartZombieHealthBar.Size
local endSize: UDim2 = UDim2.new(0, 0, 0.75, 0)
local currentTime: number = 0
local makeInvisibleZombieHealthConnection: RBXScriptConnection = nil
local deadZombies = {}
local humanoidDiedZombiesConnections = {}

local function makeInvisibleZombieHealth(deltaTime: number)
	currentTime += deltaTime
	local alpha = currentTime / TIME_TO_CLOSE_ZOMBIE_HEALTH
	if alpha >= 1 then
		backPartZombieHealthBar.Visible = false
		makeInvisibleZombieHealthConnection:Disconnect()
		currentTime = 0
		frontPartZombieHealthBar.Position = startPosition
		frontPartZombieHealthBar.Size = startSize
	end
end

zombieHealthUpdate.OnClientEvent:Connect(function(zombieHealth: number, zombie: Model)
	if deadZombies[zombie] then
		return
	end
	local zombieHumanoid: Humanoid = zombie:FindFirstChild("Humanoid") :: Humanoid
	if zombieHumanoid then
		if not humanoidDiedZombiesConnections[zombie] then
			humanoidDiedZombiesConnections[zombie] = true
			zombieHumanoid.Died:Once(function()
				deadZombies[zombie] = true
				humanoidDiedZombiesConnections[zombie] = nil
				task.wait(6)
				deadZombies[zombie] = nil
			end)
		end
	end
	if zombieHealth == 0 then
		deadZombies[zombie] = true
	end
	if not backPartZombieHealthBar.Visible then
		backPartZombieHealthBar.Visible = true
		if makeInvisibleZombieHealthConnection ~= nil then
			makeInvisibleZombieHealthConnection:Disconnect()
		end
		makeInvisibleZombieHealthConnection = RunService.Heartbeat:Connect(makeInvisibleZombieHealth)
	else
		if makeInvisibleZombieHealthConnection ~= nil then
			makeInvisibleZombieHealthConnection:Disconnect()
		end
		makeInvisibleZombieHealthConnection = RunService.Heartbeat:Connect(makeInvisibleZombieHealth)
	end
	local alpha: number = 1 - math.clamp(zombieHealth / 100, 0, 1)
	frontPartZombieHealthBar.Position = startPosition:Lerp(endPosition, alpha)
	frontPartZombieHealthBar.Size = startSize:Lerp(endSize, alpha)
	healthText.Text = zombieHealth .. "/100"
end)
