--[[This script adds features to a turret, such as the ability to mount the
turret by pressing a button, an animation that plays when a player climbs onto
the turret along with a sound effect when the animation is triggered or starts,
the ability to aim the turret by moving the camera, and a UI that features a
crosshair and a button indicating which key to press to dismount from the
turret. The turret can also fire; this includes holding down the left mouse
button to start rotate the turret’s cannons, and when the left mouse button is
released, the cannons begin to decelerate, along with their respective
animations for both acceleration and deceleration; if the left mouse button is
held for 3 seconds, left-click for 3 seconds, the turret will fire; it also
includes the ability to dismount from the turret and its corresponding
animation. The animations are replicated to all clients; likewise, the turret’s
movement controlled by the player who is mounted on it, along with the laser
beams fired by the turret, are also replicated to all clients, etc...

Some of the concepts this script includes:

-- Client-server architecture
-- Animation replication
-- CFrames
-- Raycasting
-- Animations with RunService
-- Etc.

I follow the style of the Lua Style Guide for Roblox—I believe it’s from
Roblox, created, I think, by Roblox engineers—which adheres to style rules such
as: using camelCase for variables, PascalCase for services and for classes and
enumeration-type objects, using LOUD_SNAKE_CASE for constants, limiting
comments to 80 columns in width, etc... (although I haven’t finished the Lua
style guide yet—I’m a little over halfway through)

I use StyLua, a code formatter that primarily follows the Roblox Lua Style
Guide, with a few deviations; it helps organize and format the code

And I follow some advice from Robert C. Martin’s book *Clean Code* to write
cleaner, more readable code

The system, as I wrote it, is still scalable, even though I didn't use OOP
(object-oriented programming), which would have made it more scalable and
offered other advantages. I didn't use OOP because I wanted to incorporate most
of the system into a script to apply to the role.

My workspace:
I use Rojo - Visual Studio Code - StyLua (code formatter—does not use AI) -
Selene (linter) - GitHub(To save files)]]

local Players: Players = game:GetService("Players")
local Workspace: Workspace = game:GetService("Workspace")
local ContextActionService: ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")
local UserInputService: UserInputService = game:GetService("UserInputService")
local StarterGui: StarterGui = game:GetService("StarterGui")

local FINAL_CANNON_ROTATION_SPEED: number = 1
local START_CANNON_ROTATION_SPEED: number = 0
local LASER_TURRET_DAMAGE: number = 0.5
local SECONDS_TO_SHOT: number = 3

local soundsFolder: Folder = ReplicatedStorage:WaitForChild("Sounds")
local laserWeldSound: Sound = soundsFolder:WaitForChild("LaserWeldSound") :: Sound
local activeLaserSound: Sound = soundsFolder:WaitForChild("ActiveLaserSound") :: Sound
local remoteEventsFolder: Folder = ReplicatedStorage:WaitForChild("RemoteEvents")
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
local laserTurretGui: ScreenGui = StarterGui:WaitForChild("LaserTurretGui") :: ScreenGui
local player: Player = Players.LocalPlayer
local character: Model = player.Character or player.CharacterAdded:Wait()
local humanoid: Humanoid = character:WaitForChild("Humanoid") :: Humanoid
local camera: Camera = Workspace:WaitForChild("Camera") :: Camera
local laserTurretsFolder: Folder = Workspace:WaitForChild("LaserTurrets") :: Folder
local laserTurrets = laserTurretsFolder:GetChildren()
local wallFolder: Folder = Workspace:WaitForChild("Wall") :: Folder
local currentLaserTurret: Model = nil
local heartbeatConnections = {
	MovingLaserTurret = nil,
	OnMountLaserTurret = nil,
	OnDismountTurret = nil,
}
local userInputServiceConnections = { OnMovementMouse = nil }
local rotatingCannonsAllClientsAssets = {}
local dismounting: boolean = false
local desolderCharacter: boolean = false
local mountedOnTheLaserTurret: boolean = false
local playerDead: boolean = false
local slowingDownCannons: boolean = false
local cannonsRotating: boolean = false
local sendSignalToTheServer: boolean = false
local playerInALaserHitBox = {}
local rotacionX = 0
local rotacionY = 0

--[[I use this mathematical function to calculate the speed at which the
cannons continue to spin when the player holds down the left mouse button and
when they release it, so that if they click it again and/or release it later,
the speed remains the same, ensuring a smooth and, let's say, realistic
transition in the acceleration and deceleration animation]]

local function lerp(number1: number, number2: number, alpha: number): number
	return number1 + alpha * (number2 - number1)
end

--[[Without this feature, the player would not be able to move the camera with
the mouse while in the turret or move the crosshairs to aim and shoot, and the
server would not be able to receive the rotation data needed to move the laser
turret to follow the player's mouse movements]]

local function laserTurretAimingMovement()
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
	local SENSITIVITY: number = 0.1
	local MAXIMUM_ROTATION_Y_AXIS: number = 25
	local MINIMUM_ROTATION_Y_AXIS: number = -30
	userInputServiceConnections.OnMovementMouse = UserInputService.InputChanged:Connect(
		function(input: InputObject, gameProcessedEvent: boolean)
			if input.UserInputType ~= Enum.UserInputType.MouseMovement then
				return
			end
			local delta: Vector2 = UserInputService:GetMouseDelta()
			rotacionX += delta.X * SENSITIVITY
			rotacionY += delta.Y * SENSITIVITY
			-- This check is to set a limit on how much the player can rotate
			-- up and down
			if rotacionY > MAXIMUM_ROTATION_Y_AXIS then
				rotacionY = MAXIMUM_ROTATION_Y_AXIS
			elseif rotacionY < MINIMUM_ROTATION_Y_AXIS then
				rotacionY = MINIMUM_ROTATION_Y_AXIS
			end
			-- The current rotation is retrieved and sent to the server along
			-- with the current laser turret position
			local newLaserTurretRotation: CFrame =
				CFrame.Angles(math.rad(rotacionY), math.rad(rotacionX), math.rad(0))
			updateLaserTurretPosition:FireServer(newLaserTurretRotation, currentLaserTurret)
		end
	)
end

--[[Without this feature, it would not be possible to stop the laser beam fired
by the turret along with its corresponding sounds—both the sound of the lasers
and the sound of “an object melting”—to make it seem as though the laser is
melting the spot where the laser beams end or collide]]

local function stopShoot(playerWhoShoot: Player)
	local assets = rotatingCannonsAllClientsAssets[playerWhoShoot]
	local leftSmallBarrel: MeshPart = assets.leftSmallBarrel
	local rightSmallBarrel: MeshPart = assets.rightSmallBarrel

	-- We disable the particle emitters and reset the CFrame of the attachments
	-- named “end” to return them to their original or initial position
	for _, descendant in leftSmallBarrel:GetDescendants() do
		if descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") then
			descendant.Enabled = false
		elseif descendant:IsA("Attachment") and descendant.Name == "End" then
			descendant.CFrame = CFrame.new()
		else
			continue
		end
	end
	for _, descendant in rightSmallBarrel:GetDescendants() do
		if descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") then
			descendant.Enabled = false
		elseif descendant:IsA("Attachment") and descendant.Name == "End" then
			descendant.CFrame = CFrame.new()
		else
			continue
		end
	end
	-- We disconnect the connection that keeps the laser turret firing
	if assets.onShootConnection ~= nil then
		if assets.onShootConnection.Connected then
			assets.onShootConnection:Disconnect()
			assets.onShootConnection = nil
		end
	end
	-- We stop the sound of laser beams
	if sendSignalToTheServer then
		if activeLaserSound.IsPlaying then
			activeLaserSound:Stop()
		end
	else
		if activeLaserSound.IsPlaying then
			activeLaserSound:Pause()
		end
	end
	-- We stop and destroy the sounds that produce a “melting” sound that makes
	-- it seem as though the lasers are melting the spot where they collide
	if assets["leftLaserWeldSound"] then
		assets["leftLaserWeldSound"]:Stop()
		assets["leftLaserWeldSound"]:Destroy()
		assets["leftLaserWeldSound"] = nil
	end
	if assets["rightLaserWeldSound"] then
		assets["rightLaserWeldSound"]:Stop()
		assets["rightLaserWeldSound"]:Destroy()
		assets["rightLaserWeldSound"] = nil
	end
	-- We destroy the parts used to verify the area where the sound emitted by,
	-- say, laser beams, will begin or be heard
	if assets["soundLaserActivePart"] then
		assets["soundLaserActivePart"]:Destroy()
		assets["soundLaserActivePart"] = nil
	end
	if assets["soundLaserActivePartClone"] then
		assets["soundLaserActivePartClone"]:Destroy()
		assets["soundLaserActivePartClone"] = nil
	end
	-- If the player who fired the shot or was in the laser turret was the
	-- local player, this boolean value indicates that the raycasting
	-- calculations should be sent to the server to deal damage to players; if
	-- that was the case, we reset this value to false
	if sendSignalToTheServer then
		sendSignalToTheServer = false
	end
	-- If the player was detected in an area where the sounds of the laser
	-- beams could be heard, we clear this array in case the laser beams
	-- stopped firing and the array was not cleared
	playerInALaserHitBox = {}
end

--[[I use this function to check whether a player is inside an area covered by
the laser beams in order to play the sound that corresponds to the sound—let's
say—emitted by the laser beams]]

local function activeLaserSoundDetector(soundPart: Part)
	local foundCharacter: boolean = false
	local array = Workspace:GetPartsInPart(soundPart)
	-- We check to see if we find the player's character in the part
	for _, part in array do
		if part:IsDescendantOf(character) then
			if playerInALaserHitBox[soundPart] then
				foundCharacter = true
				if not activeLaserSound.IsPlaying then
					activeLaserSound.Volume = 0.3
					if activeLaserSound.TimePosition ~= 0 then
						activeLaserSound:Resume()
					else
						activeLaserSound:Play()
					end
				end
				break
			end
			playerInALaserHitBox[soundPart] = true
			foundCharacter = true
			if not activeLaserSound.IsPlaying then
				activeLaserSound.Volume = 0.3
				if activeLaserSound.TimePosition ~= 0 then
					activeLaserSound:Resume()
				else
					activeLaserSound:Play()
				end
			end
			break
		end
	end
	-- If we don't find the player's character in this section, we check
	-- whether the player's character had previously been found in this
	-- section; if so, we pause the sound and remove that section from the
	-- array
	if not foundCharacter then
		if playerInALaserHitBox[soundPart] then
			playerInALaserHitBox[soundPart] = nil
			activeLaserSound:Pause()
		end
	end
end

--[[Without this function, the laser beams would not extend to the end of the
raycasting, and the sound of the laser beams would not be heard in the
corresponding area]]

local function rayRendering(rayAssets)
	local SIZE_ACTIVE_LASER_SOUND_AREA = 90
	local leftLaserOrigin = rayAssets.leftLaserOrigin
	local rightLaserOrigin = rayAssets.rightLaserOrigin
	local soundLaserActivePart = rayAssets.soundLaserActivePart
	local soundLaserActivePartClone = rayAssets.soundLaserActivePartClone
	local leftRaycastResult2 = rayAssets.leftRaycastResult2
	local rightRaycastResult2 = rayAssets.rightRaycastResult2
	local leftEndAttachments = rayAssets.leftEndAttachments
	local rightEndAttachments = rayAssets.rightEndAttachments
	local leftLookVector = rayAssets.leftLookVector
	local rightLookVector = rayAssets.rightLookVector
	local leftOffSetMagnitude = rayAssets.leftOffSetMagnitude
	local rightOffSetMagnitude = rayAssets.rightOffsetMagnitude
	if leftRaycastResult2 then
		for _, endAttachment in leftEndAttachments do
			endAttachment.WorldPosition = leftRaycastResult2.Position
		end
		if not sendSignalToTheServer then
			soundLaserActivePart.Size = Vector3.new(
				SIZE_ACTIVE_LASER_SOUND_AREA,
				SIZE_ACTIVE_LASER_SOUND_AREA,
				(leftLaserOrigin.Position - leftRaycastResult2.Position).Magnitude
					+ SIZE_ACTIVE_LASER_SOUND_AREA
			)
			soundLaserActivePart.CFrame = CFrame.new(
				leftLaserOrigin.Position
					+ leftLookVector
						* ((leftLaserOrigin.Position - leftRaycastResult2.Position).Magnitude / 2),
				leftRaycastResult2.Position
			)
			activeLaserSoundDetector(soundLaserActivePart)
		end
	else
		for _, endAttachment in leftEndAttachments do
			endAttachment.WorldPosition = leftLaserOrigin.Position
				+ leftLookVector * leftOffSetMagnitude
		end
		if not sendSignalToTheServer then
			soundLaserActivePart.Size = Vector3.new(
				SIZE_ACTIVE_LASER_SOUND_AREA,
				SIZE_ACTIVE_LASER_SOUND_AREA,
				leftOffSetMagnitude + SIZE_ACTIVE_LASER_SOUND_AREA
			)
			soundLaserActivePart.CFrame = CFrame.new(
				leftLaserOrigin.Position + leftLookVector * (leftOffSetMagnitude / 2),
				leftLaserOrigin.Position + leftLookVector * leftOffSetMagnitude
			)
			activeLaserSoundDetector(soundLaserActivePart)
		end
	end
	if rightRaycastResult2 then
		for _, endAttachment in rightEndAttachments do
			endAttachment.WorldPosition = rightRaycastResult2.Position
		end
		if not sendSignalToTheServer then
			soundLaserActivePartClone.Size = Vector3.new(
				SIZE_ACTIVE_LASER_SOUND_AREA,
				SIZE_ACTIVE_LASER_SOUND_AREA,
				(rightLaserOrigin.Position - rightRaycastResult2.Position).Magnitude
					+ SIZE_ACTIVE_LASER_SOUND_AREA
			)
			soundLaserActivePartClone.CFrame = CFrame.new(
				rightLaserOrigin.Position
					+ rightLookVector
						* ((rightLaserOrigin.Position - rightRaycastResult2.Position).Magnitude / 2),
				rightRaycastResult2.Position
			)
			activeLaserSoundDetector(soundLaserActivePartClone)
		end
	else
		for _, endAttachment in rightEndAttachments do
			endAttachment.WorldPosition = rightLaserOrigin.Position
				+ rightLookVector * rightOffSetMagnitude
		end
		if not sendSignalToTheServer then
			soundLaserActivePartClone.Size = Vector3.new(
				SIZE_ACTIVE_LASER_SOUND_AREA,
				SIZE_ACTIVE_LASER_SOUND_AREA,
				rightOffSetMagnitude + SIZE_ACTIVE_LASER_SOUND_AREA
			)
			soundLaserActivePartClone.CFrame = CFrame.new(
				rightLaserOrigin.Position + rightLookVector * (rightOffSetMagnitude / 2),
				rightLaserOrigin.Position + rightLookVector * rightOffSetMagnitude
			)
			activeLaserSoundDetector(soundLaserActivePartClone)
		end
	end
end

--[[Without this function, the raycasting calculations would not be performed
to determine the start and end points of the laser beams, nor would the “fire"
sounds (when the laser turret fires) and the “melting” sound (from the end of
the laser beams, where it appears as though the laser beams are melting the
spot where they strike). Furthermore, if the player is standing on the laser
turret, the sound of the laser beams (the actual sound of the laser beams)
would not be heard. Without this function, the rayRendering() function—which is
the next step—would not work]]

local function calculatingPositionsForRayRendering(rayAssets)
	local assets = rayAssets.assets
	local leftLaserOrigin = rayAssets.leftLaserOrigin
	local rightLaserOrigin = rayAssets.rightLaserOrigin
	local raycastParams = rayAssets.raycastParams
	local cameraPosition = rayAssets.cameraPosition
	local CAMERA_RAY_LENGTH: number = 1000

	if sendSignalToTheServer then
		activeLaserSound:Play()
		activeLaserSound.Volume = 0.3
	end
	assets["leftLaserShotSound"]:Play()
	assets["rightLaserShotSound"]:Play()
	assets["leftLaserWeldSound"]:Play()
	assets["rightLaserWeldSound"]:Play()

	assets.onShootConnection = RunService.RenderStepped:Connect(function()
		local targetCameraPoint: Vector3 = cameraPosition.Position
			+ (cameraPosition.CFrame.LookVector * CAMERA_RAY_LENGTH)
		local raycastResult1: RaycastResult = Workspace:Raycast(
			cameraPosition.Position,
			cameraPosition.CFrame.LookVector * CAMERA_RAY_LENGTH,
			raycastParams
		) :: RaycastResult
		local leftLookVector: Vector3 = nil
		local rightLookVector: Vector3 = nil
		local leftOffSetMagnitude: number = nil
		local rightOffsetMagnitude: number = nil
		if raycastResult1 then
			leftLookVector =
				CFrame.lookAt(leftLaserOrigin.Position, raycastResult1.Position).LookVector
			rightLookVector =
				CFrame.lookAt(rightLaserOrigin.Position, raycastResult1.Position).LookVector
			leftOffSetMagnitude = (-leftLaserOrigin.Position + raycastResult1.Position).Magnitude
			rightOffsetMagnitude = (-rightLaserOrigin.Position + raycastResult1.Position).Magnitude
		else
			leftLookVector = CFrame.lookAt(leftLaserOrigin.Position, targetCameraPoint).LookVector
			rightLookVector = CFrame.lookAt(rightLaserOrigin.Position, targetCameraPoint).LookVector
			leftOffSetMagnitude = (-leftLaserOrigin.Position + targetCameraPoint).Magnitude
			rightOffsetMagnitude = (-rightLaserOrigin.Position + targetCameraPoint).Magnitude
		end
		local leftRaycastResult2: RaycastResult = Workspace:Raycast(
			leftLaserOrigin.Position,
			leftLookVector * CAMERA_RAY_LENGTH,
			raycastParams
		) :: RaycastResult
		local rightRaycastResult2: RaycastResult = Workspace:Raycast(
			rightLaserOrigin.Position,
			rightLookVector * CAMERA_RAY_LENGTH,
			raycastParams
		) :: RaycastResult
		-- We send the assets needed to perform raycasting from the server to
		-- deal damage to other players if the player who fires in this
		-- function is the local player
		if sendSignalToTheServer then
			onLaserTurretRaycast:FireServer(
				leftLaserOrigin.Position,
				rightLaserOrigin.Position,
				leftLookVector,
				rightLookVector,
				CAMERA_RAY_LENGTH,
				assets.laserTurret,
				LASER_TURRET_DAMAGE
			)
		end
		rayAssets["leftRaycastResult2"] = leftRaycastResult2
		rayAssets["rightRaycastResult2"] = rightRaycastResult2
		rayAssets["leftLookVector"] = leftLookVector
		rayAssets["rightLookVector"] = rightLookVector
		rayAssets["leftOffSetMagnitude"] = leftOffSetMagnitude
		rayAssets["rightOffsetMagnitude"] = rightOffsetMagnitude

		rayRendering(rayAssets)
	end)
end

--[[Without this function, it would not be possible to access the parts of the
laser turret in order to perform the position calculations needed to render the
, create the parts that represent the area where the sound of the laser beams
will be heard, and access the references needed to render the beam. It also
verifies whether the player who fired the laser beams is on top of the laser
turret; therefore, the functions `calculatingPositionsForRayRendering()` and
`rayRendering()` would not work]]

local function createAssetsForRenderingRay(
	playerWhoShoot: Player,
	leftEndAttachments,
	rightEndAttachments
)
	local assets = rotatingCannonsAllClientsAssets[playerWhoShoot]
	local leftSmallBarrel: MeshPart = assets.leftSmallBarrel
	local rightSmallBarrel: MeshPart = assets.rightSmallBarrel
	local leftLaserOrigin: Part = leftSmallBarrel:WaitForChild("OriginOfTheLaser") :: Part
	local rightLaserOrigin: Part = rightSmallBarrel:WaitForChild("OriginOfTheLaser") :: Part
	local leftLaserShotSound: Sound = leftLaserOrigin:WaitForChild("LaserShotSound") :: Sound
	local rightLaserShotSound: Sound = rightLaserOrigin:WaitForChild("LaserShotSound") :: Sound
	-- This check verifies whether the player taking the shot is the local
	-- player
	if player.Name == playerWhoShoot.Name then
		sendSignalToTheServer = true
	end
	local playerCharacter: Model = playerWhoShoot.Character or playerWhoShoot.CharacterAdded:Wait()
	local raycastParams: RaycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances =
		{ assets.laserTurret, playerCharacter, camera, wallFolder }

	local laserTurretTop: MeshPart = assets.laserTurret:WaitForChild("LaserTurretTop")
	local cameraPosition: Part = laserTurretTop:WaitForChild("CameraPosition") :: Part

	local soundLaserActivePart: Part = Instance.new("Part")
	soundLaserActivePart.Name = "soundLaserActivePart"
	soundLaserActivePart.Anchored = true
	soundLaserActivePart.CanCollide = false
	soundLaserActivePart.Transparency = 1
	soundLaserActivePart.Parent = leftSmallBarrel

	local soundLaserActivePartClone: Part = soundLaserActivePart:Clone()
	soundLaserActivePartClone.Parent = rightSmallBarrel

	assets["leftLaserShotSound"] = leftLaserShotSound
	assets["rightLaserShotSound"] = rightLaserShotSound
	assets["soundLaserActivePart"] = soundLaserActivePart
	assets["soundLaserActivePartClone"] = soundLaserActivePartClone

	local rayAssets = {
		["assets"] = assets,
		["leftLaserOrigin"] = leftLaserOrigin,
		["rightLaserOrigin"] = rightLaserOrigin,
		["raycastParams"] = raycastParams,
		["cameraPosition"] = cameraPosition,
		["soundLaserActivePart"] = soundLaserActivePart,
		["soundLaserActivePartClone"] = soundLaserActivePartClone,
		["leftEndAttachments"] = leftEndAttachments,
		["rightEndAttachments"] = rightEndAttachments,
	}
	calculatingPositionsForRayRendering(rayAssets)
end

--[[Without this feature, the laser beams wouldn't be visible, and you wouldn't
be able to hear the “melting” sounds (which are heard at the end of the laser
beams and make it seem as though the laser beams are melting the spot where
they strike). Furthermore, the particle effects for the laser beams would not
be triggered, and the rayRendering() function would not be able to access the
“Attachment” corresponding to the end of the “beam” to move it to where the
raycast intersects and, once the “beam” is activated, display the laser beams
from the beginning to the end of the laser beams]]

local function shootOnAllClients(playerWhoShoot: Player)
	local assets = rotatingCannonsAllClientsAssets[playerWhoShoot]
	local leftSmallBarrel: MeshPart = assets.leftSmallBarrel
	local rightSmallBarrel: MeshPart = assets.rightSmallBarrel
	local leftEndAttachments = {}
	local rightEndAttachments = {}
	-- Here, we enable the particle emitters and create the sounds that produce
	-- a “melting” sound, as if the laser beams were melting the spot where
	-- they collide, and we save the attachments named “End” in separate tables
	-- depending on whether they are from the left or right laser
	for _, descendant in leftSmallBarrel:GetDescendants() do
		if descendant:IsA("Attachment") and descendant.Name == "End" then
			table.insert(leftEndAttachments, descendant)
			if assets["leftLaserWeldSound"] == nil then
				local laserWeldSoundClone: Sound = laserWeldSound:Clone()
				laserWeldSoundClone.Parent = descendant
				assets["leftLaserWeldSound"] = laserWeldSoundClone
			end
		end
		if descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") then
			descendant.Enabled = true
		else
			continue
		end
	end
	for _, descendant in rightSmallBarrel:GetDescendants() do
		if descendant:IsA("Attachment") and descendant.Name == "End" then
			table.insert(rightEndAttachments, descendant)
			if assets["rightLaserWeldSound"] == nil then
				local laserWeldSoundClone: Sound = laserWeldSound:Clone()
				laserWeldSoundClone.Parent = descendant
				assets["rightLaserWeldSound"] = laserWeldSoundClone
			end
		end
		if descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") then
			descendant.Enabled = true
		else
			continue
		end
	end
	createAssetsForRenderingRay(playerWhoShoot, leftEndAttachments, rightEndAttachments)
end

--[[Without this feature, the cannons would not rotate and slow down when the
player releases the left mouse button after clicking it to fire, nor would the
feature to stop the laser beams from firing be activated]]

local function rotatingCannonsDecelerationAnimationForAllClients(playerWhoShoot: Player)
	local assets = rotatingCannonsAllClientsAssets[playerWhoShoot]
	local currentTime: number = 0
	local oldCannonRotationSpeed: number = assets.currentCannonRotationSpeed
	local timeRemaining: number = SECONDS_TO_SHOT * oldCannonRotationSpeed
	if player.Name == playerWhoShoot.Name then
		slowingDownCannons = true
		cannonsRotating = true
	end
	-- We disconnect the connection that kept the cannons spinning faster and
	-- check whether the connection responsible for firing the laser beams is
	-- active; if so, we call the function responsible for stopping the firing
	assets.rotatingCannonsConnection:Disconnect()
	if assets.onShootConnection ~= nil then
		if assets.onShootConnection.Connected then
			if assets.laserTurretCanShoot then
				assets.laserTurretCanShoot = false
				task.spawn(stopShoot, playerWhoShoot)
			end
		end
	end
	assets.rotatingCannonsConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		currentTime += deltaTime
		local alpha: number = currentTime / timeRemaining
		if alpha >= 1 then
			assets.currentCannonRotationSpeed = START_CANNON_ROTATION_SPEED
			assets.rotatingCannonsConnection:Disconnect()
			assets.leftSmallBarrelWeld.C1 = CFrame.Angles(0, 0, 0)
			assets.rightSmallBarrelWeld.C1 = CFrame.Angles(0, 0, 0)
			rotatingCannonsAllClientsAssets[playerWhoShoot] = nil
			if player.Name == playerWhoShoot.Name then
				slowingDownCannons = false
				cannonsRotating = false
			end
			return
		else
			assets.currentCannonRotationSpeed =
				lerp(oldCannonRotationSpeed, START_CANNON_ROTATION_SPEED, alpha)
		end
		assets.leftSmallBarrelWeld.C1 = assets.leftSmallBarrelWeld.C1
			* CFrame.Angles(0, 0, assets.currentCannonRotationSpeed)
		assets.rightSmallBarrelWeld.C1 = assets.rightSmallBarrelWeld.C1
			* CFrame.Angles(0, 0, assets.currentCannonRotationSpeed)
	end)
end

--[[Without this feature, the cannons would not rotate and accelerate when the
player presses and holds the left mouse button to fire, and if the player holds
it for the specified time to fire, the feature responsible for firing the laser
beams would not be activated]]

local function rotatingCannonsAccelerationAnimationForAllClients(playerWhoShoot: Player)
	local assets = rotatingCannonsAllClientsAssets[playerWhoShoot]
	local currentTime: number = 0
	local oldCannonRotationSpeed: number = assets.currentCannonRotationSpeed
	local remainingRotation: number = FINAL_CANNON_ROTATION_SPEED - oldCannonRotationSpeed
	local timeRemaining: number = SECONDS_TO_SHOT * remainingRotation
	if player.Name == playerWhoShoot.Name then
		slowingDownCannons = false
		cannonsRotating = true
	end
	-- If the cannons were rotating while decelerating, we disconnect the
	-- connection so that they stop decelerating
	if assets.rotatingCannonsConnection ~= nil then
		if assets.rotatingCannonsConnection.Connected then
			assets.rotatingCannonsConnection:Disconnect()
		end
	end
	assets.rotatingCannonsConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		currentTime += deltaTime
		local alpha: number = currentTime / timeRemaining
		if alpha >= 1 then
			assets.currentCannonRotationSpeed = FINAL_CANNON_ROTATION_SPEED
			if not assets.laserTurretCanShoot then
				assets.laserTurretCanShoot = true
				task.spawn(shootOnAllClients, playerWhoShoot)
			end
		else
			assets.currentCannonRotationSpeed =
				lerp(oldCannonRotationSpeed, FINAL_CANNON_ROTATION_SPEED, alpha)
		end
		assets.leftSmallBarrelWeld.C1 = assets.leftSmallBarrelWeld.C1
			* CFrame.Angles(0, 0, assets.currentCannonRotationSpeed)
		assets.rightSmallBarrelWeld.C1 = assets.rightSmallBarrelWeld.C1
			* CFrame.Angles(0, 0, assets.currentCannonRotationSpeed)
	end)
end

--[[I use this function to create the player's initial assets that fire the
laser beams when the player fires for the first time, and I also check whether
those assets had already been created to determine if the player had fired
before and to see if the cannons need to be slowed down or sped up now]]

local function rotatingCannonsAllClients(
	playerWhoShoot: Player,
	rotatingCannonsOnOff: boolean,
	laserTurret: Model
)
	-- We check whether the player who fired the shot had any assets created
	-- previously; if not, we'll create them
	if rotatingCannonsAllClientsAssets[playerWhoShoot] then
		if rotatingCannonsOnOff then
			rotatingCannonsAccelerationAnimationForAllClients(playerWhoShoot)
		else
			rotatingCannonsDecelerationAnimationForAllClients(playerWhoShoot)
		end
	else
		if not rotatingCannonsOnOff then
			return
		end
		local assets = {}
		local weldsFolder: Folder = laserTurret:WaitForChild("Welds") :: Folder
		assets["leftSmallBarrelWeld"] =
			weldsFolder:WaitForChild("LeftBigBarrellWithLeftSmallBarrel")
		assets["rightSmallBarrelWeld"] =
			weldsFolder:WaitForChild("RightBigBarrelWithRighSmallBarrel")
		assets["leftSmallBarrel"] = laserTurret:WaitForChild("LaserTurretLeftSmallBarrel")
		assets["rightSmallBarrel"] = laserTurret:WaitForChild("LaserTurretRightSmallBarrel")
		assets["currentCannonRotationSpeed"] = START_CANNON_ROTATION_SPEED
		assets["laserTurretCanShoot"] = false
		assets["rotatingCannonsConnection"] = nil
		assets["onShootConnection"] = nil
		assets["balancingCannonsConnection"] = nil
		assets["currentTimeBalancingCannons"] = 0
		assets["endAttachments"] = {}
		assets["laserTurret"] = laserTurret
		rotatingCannonsAllClientsAssets[playerWhoShoot] = assets
		rotatingCannonsAccelerationAnimationForAllClients(playerWhoShoot)
	end
end

--[[I use this function to receive the signal when the player left-clicks to
fire or when they release the left mouse button to stop firing or to reload the
laser turret so it can fire again, and to send that signal to the server so it
can then be sent to all clients]]

local function animationForRotatingCannons(
	actionName: string?,
	inputState: Enum.UserInputState,
	inputObject: InputObject?
)
	if inputState == Enum.UserInputState.Begin then
		local rotatingCannonsOn: boolean = true
		rotatingCannonsAllClients(player, rotatingCannonsOn, currentLaserTurret)
		animationRotatingCannonsAllClients:FireServer(rotatingCannonsOn, currentLaserTurret)
	end
	if inputState == Enum.UserInputState.End then
		local rotatingCannonsOff: boolean = false
		rotatingCannonsAllClients(player, rotatingCannonsOff, currentLaserTurret)
		animationRotatingCannonsAllClients:FireServer(rotatingCannonsOff, currentLaserTurret)
	end
end

--[[Without this function, the laser turret would not play the animation
showing how it returns to its position once the player gets off it, and the
position where the laser turret should be when it returns to its original or
initial position would not be sent, nor would the sound associated with the
animation be heard]]

local function resetTurretPosition(laserTurret: Model)
	local ANIMATION_DURATION = 1.5
	local laserTurretTop: MeshPart = laserTurret:WaitForChild("LaserTurretTop") :: MeshPart
	local resetTurretPositionSound: Sound =
		laserTurretTop:WaitForChild("ResetTurretPosition") :: Sound
	local weldsFolder: Folder = laserTurret:WaitForChild("Welds") :: Folder
	local weld: Weld = weldsFolder:WaitForChild("BottomSmallPartWithTop") :: Weld
	local targetCFrame: CFrame = CFrame.new()
	local startC1CFrame: CFrame = weld.C1
	local currentTime: number = 0
	-- We start the sound for the animation
	resetTurretPositionSound:Play()
	heartbeatConnections.OnDismountTurret = RunService.Heartbeat:Connect(function(deltaTime: number)
		currentTime += deltaTime
		local alpha: number = currentTime / ANIMATION_DURATION
		weld.C1 = startC1CFrame:Lerp(targetCFrame, alpha)
		if alpha >= 1 then
			heartbeatConnections.OnDismountTurret:Disconnect()
			weld.C1 = targetCFrame
			-- We send the final CFrame to the server to position it at that
			-- position
			animationOnMountLaserTurret:FireServer("Place CFrame", laserTurret, targetCFrame)
		end
	end)
end

--[[Without this function, the laser turret would not play the animation that
runs when a player climbs onto a laser turret, the sound associated with the
animation would not play, and the final position where the laser turret should
be located when a player climbs onto it would not be sent]]

local function animationWhenAssemblingTheLaserTurret(laserTurret: Model)
	local OFFSET_TO_MOVE_UPWARD = 2.5 -- In studs
	local ANIMATION_DURATION = 1.5
	local laserTurretTop: MeshPart = laserTurret:WaitForChild("LaserTurretTop") :: MeshPart
	local resetTurretPositionSound: Sound =
		laserTurretTop:WaitForChild("ResetTurretPosition") :: Sound
	local weldsFolder: Folder = laserTurret:WaitForChild("Welds") :: Folder
	local weld: Weld = weldsFolder:WaitForChild("BottomSmallPartWithTop") :: Weld
	local targetCFrame: CFrame = weld.C1 * CFrame.new(0, -OFFSET_TO_MOVE_UPWARD, 0)
	local startC1CFrame: CFrame = weld.C1
	local currentTime: number = 0
	-- We start the sound for the animation
	resetTurretPositionSound:Play()
	heartbeatConnections.OnMountLaserTurret = RunService.Heartbeat:Connect(
		function(deltaTime: number)
			currentTime += deltaTime
			local alpha: number = currentTime / ANIMATION_DURATION
			weld.C1 = startC1CFrame:Lerp(targetCFrame, alpha)
			if alpha >= 1 then
				heartbeatConnections.OnMountLaserTurret:Disconnect()
				weld.C1 = targetCFrame
				-- We send the final CFrame to the server to position it at that
				-- position
				animationOnMountLaserTurret:FireServer("Place CFrame", laserTurret, targetCFrame)
			end
		end
	)
end

--[[Without this feature, the values or connections associated with the laser
turret would not be reset or return to their original or initial values, such
as: the mouse pointer locked in the center of the screen or the mouse icon
would remain hidden, or the camera would not return to its original state as
controlled by Roblox scripts, or connections would not be disconnected—such as
the one that controls or maintains the camera at a fixed offset above the laser
turret, or connections such as the one that receives the signal when the player
moves the mouse to move the player’s camera while they are mounted on the laser
turret, etc...]]

local function dismountLaserTurret()
	-- If you're already taking it apart, let's go back
	if dismounting then
		return
	end
	dismounting = true
	desolderCharacter = true

	local laserTurretTop: MeshPart = currentLaserTurret:WaitForChild("LaserTurretTop") :: MeshPart
	local button: ProximityPrompt = laserTurretTop:WaitForChild("MountButton") :: ProximityPrompt
	-- We call the function that handles the animation when a player gets off a
	-- laser turret
	task.spawn(resetTurretPosition, currentLaserTurret)

	ContextActionService:UnbindAction("OnActivatedButtonToDismount")
	ContextActionService:UnbindAction("Shoot")
	RunService:UnbindFromRenderStep("lockCameraPosition")

	animationOnMountLaserTurret:FireServer("End animation", currentLaserTurret)
	playerClimbsTheTurret:FireServer(desolderCharacter, currentLaserTurret, playerDead)
	enabledLaserTurretGui:FireServer(laserTurretGui.Name) -- Hide the laser
	-- turret's graphical interface

	UserInputService.MouseIconEnabled = true
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	camera.CameraType = Enum.CameraType.Custom

	button.Enabled = true

	rotacionX = 0
	rotacionY = 0

	if userInputServiceConnections.OnMovementMouse ~= nil then
		if userInputServiceConnections.OnMovementMouse.Connected then
			userInputServiceConnections.OnMovementMouse:Disconnect()
		end
	end
	if playerDead and cannonsRotating and not slowingDownCannons then
		animationForRotatingCannons("Shoot", Enum.UserInputState.End)
	end
	if cannonsRotating and not slowingDownCannons then
		animationForRotatingCannons("Shoot", Enum.UserInputState.End)
	end

	task.wait(0.5)

	dismounting = false
	mountedOnTheLaserTurret = false
	playerDead = false
end

--[[Without this function, the camera animation would not play when the player
climbs onto the laser turret and the camera transitions from its current
position to the position it will be in when the player climbs onto the laser
turret. Furthermore, the laser turret animation would not play when a player
climbs onto the laser turret, the animation signal would not be sent to all
clients, and the player’s camera would not remain fixed in the position it
should be in when the player climbs onto the laser turret]]

local function setCameraPositionOnLaserTurret()
	local SECONDS_TO_LERP = 2
	local OFFSET_CAMERA_ON_THE_LASER_TURRET = CFrame.new(0, 8, 35)
	local laserTurretTop: MeshPart = currentLaserTurret:WaitForChild("LaserTurretTop") :: MeshPart
	camera.CameraType = Enum.CameraType.Scriptable
	local currentThread = coroutine.running()
	-- We start the animation that should play when a player climbs into the
	-- laser turret
	task.spawn(animationWhenAssemblingTheLaserTurret, currentLaserTurret)
	animationOnMountLaserTurret:FireServer("Start animation", currentLaserTurret)
	local targetCFrame: CFrame = laserTurretTop.CFrame * OFFSET_CAMERA_ON_THE_LASER_TURRET
	local currentTime: number = 0
	local startCameraCFrame: CFrame = camera.CFrame
	RunService:BindToRenderStep(
		"setCameraPosition",
		Enum.RenderPriority.Camera.Value,
		function(deltaTime: number)
			currentTime += deltaTime
			local alpha = currentTime / SECONDS_TO_LERP
			camera.CFrame = startCameraCFrame:Lerp(targetCFrame, alpha)
			if alpha >= 1 then
				RunService:UnbindFromRenderStep("setCameraPosition")
				camera.CFrame = targetCFrame
				task.spawn(currentThread)
			end
		end
	)
	coroutine.yield()
	-- Once the camera has finished moving to the position it should be in when
	-- the player climbs onto a laser turret, we keep the camera fixed in that
	-- spot
	RunService:BindToRenderStep(
		"lockCameraPosition",
		Enum.RenderPriority.Camera.Value,
		function(deltaTime: number)
			camera:PivotTo(laserTurretTop.CFrame * OFFSET_CAMERA_ON_THE_LASER_TURRET)
		end
	)
end

--[[Without this feature, I wouldn't be able to tell when the player is on the
—the current laser turret, that is, the one the player last climbed onto—would
not be updated; the signal notifying the server that the player is about to
climb onto a laser turret so that the server can attach the player’s character
to the laser turret would not be sent; the functions responsible for
positioning the player’s camera where it should be when boarding a laser
turret; the function responsible for detecting whether the player moved the
mouse to move the camera and the laser turret when the player boards a laser
turret; nor would the signal responsible for enabling the laser turret’s UI be
sent to the server; nor would the functions responsible for handling when the
player presses the “E” key to climb down from the laser turret, nor the
function responsible for receiving the signal when the player left-clicks to
fire or to stop firing]]

local function onButtonActivated(laserTurret: Model)
	mountedOnTheLaserTurret = true
	currentLaserTurret = laserTurret
	desolderCharacter = false
	playerClimbsTheTurret:FireServer(desolderCharacter, laserTurret)
	setCameraPositionOnLaserTurret()
	laserTurretAimingMovement()
	enabledLaserTurretGui:FireServer(laserTurretGui.Name) -- It displays the
	-- laser turret's graphical interface
	ContextActionService:BindAction(
		"OnActivatedButtonToDismount",
		dismountLaserTurret,
		false,
		Enum.KeyCode.E
	)
	ContextActionService:BindAction(
		"Shoot",
		animationForRotatingCannons,
		false,
		Enum.UserInputType.MouseButton1
	)
end

--[[Without this function, a button would not be created for each laser turret,
nor would the signal be connected to the event that triggers when the player
presses the button to start the function responsible for initiating the other
functions necessary to configure the laser turret and this entire script; nor
would the signal be received from the server that notifies when a player has
climbed onto a laser turret, and therefore that laser turret is occupied, and
disable the button so that the player cannot climb onto that laser turret, or
when the player gets off, re-enable the button to make the laser turret
available again so the player can climb onto it]]

local function createButtonToMount(laserTurret: Model)
	local laserTurretTop: MeshPart = laserTurret:WaitForChild("LaserTurretTop") :: MeshPart
	local SECONDS_TO_HOLD_THE_BUTTON_DOWN = 2
	local DISTANCE_TO_SEE_THE_BUTTON = 20
	local BUTTON_UI_OFFSET = Vector2.new(75, -50)
	local button: ProximityPrompt = Instance.new("ProximityPrompt")
	button.Parent = laserTurretTop
	button.Name = "MountButton"
	button.ActionText = "Mount Laser Turret"
	button.HoldDuration = SECONDS_TO_HOLD_THE_BUTTON_DOWN
	button.MaxActivationDistance = DISTANCE_TO_SEE_THE_BUTTON
	button.UIOffset = BUTTON_UI_OFFSET
	button.Enabled = true

	button.Triggered:Connect(function(player: Player)
		button.Enabled = false
		onButtonActivated(laserTurret)
	end)
	-- With this event, we receive information from the server about whether a
	-- turret was occupied by another player or was unoccupied, and we enable
	-- or disable the button for the laser turret so that it can be mounted or
	-- cannot be mounted
	playerClimbsTheTurret.OnClientEvent:Connect(
		function(playerWhoTriggeredTheEvent: Player, desolderCharacter: boolean)
			if playerWhoTriggeredTheEvent.Name == player.Name then
				return
			end
			if not desolderCharacter then
				button.Enabled = false
			else
				button.Enabled = true
			end
		end
	)
end

--[[Without this function, the feature for creating a button on each laser
turret and the connections managed by that function would not be activated]]

local function startConfiguringTheLaserTurrets()
	for _, laserTurret: Model in laserTurrets do
		createButtonToMount(laserTurret)
	end
end

--[[Without this function, there would be no way to know when the player dies
or is dead, and if he was riding the laser turret, to call the function that
resets or restores the values to their original or initial values when the
player gets off the laser turret]]

local function onPlayerDead()
	if mountedOnTheLaserTurret == false then
		return
	end
	playerDead = true
	dismountLaserTurret()
end

--[[Without this function, it would not be possible to update the player's
character and the player's humanoid when the player dies, nor to re-link the
connection between the event that triggers when the player dies and the
function responsible for handling the situation where the player dies while
mounted on the turret]]

local function onCharacterAdded(newCharacter: Model)
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Once(onPlayerDead)
end

--[[Without this feature, the animations that trigger when a player climbs onto
a laser turret and when they climb down from a laser turret would not be
replicated on all clients]]

animationOnMountLaserTurret.OnClientEvent:Connect(
	function(playerWhoTriggeredTheEvent: Player, laserTurret: Model, actionName: string)
		if player.Name == playerWhoTriggeredTheEvent.Name then
			return
		end
		if actionName == "Start animation" then
			animationWhenAssemblingTheLaserTurret(laserTurret)
		else
			resetTurretPosition(laserTurret)
		end
	end
)

--[[Without this function attached to this event, the changes would not be
replicated to all clients when the cannons of a laser turret
rotate—accelerating and decelerating—and when it fires laser beams and when it
stops firing laser beams]]

animationRotatingCannonsAllClients.OnClientEvent:Connect(
	function(playerWhoTriggeredTheEvent: Player, ...)
		if player.Name == playerWhoTriggeredTheEvent.Name then
			return
		end
		local arguments = { ... }
		rotatingCannonsAllClients(playerWhoTriggeredTheEvent, arguments[1], arguments[2])
	end
)

--[[Without this connection, it would not be possible to trigger the event that
is activated when the player dies for the first time]]

humanoid.Died:Once(onPlayerDead)

--[[Without this connection, it would not be possible to trigger the event for
the first time that is activated when the player's character is added or when
it is refreshed upon death]]

player.CharacterAdded:Connect(onCharacterAdded)

--[[If this function is not called, the buttons on the laser turrets will not
be created, and therefore they cannot be mounted, and consequently none of the
functions that are executed when the button is activated will be called;
therefore, this is the function that must be called in the script for
everything else to start]]

startConfiguringTheLaserTurrets()
