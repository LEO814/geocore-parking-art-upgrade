---@id 8bd801fb-77a6-40e3-b3f0-213805638473
-- Generated from the proven W-01 multiplayer drivable runtime for LP-14「DESSERT·甜品拟物」双人卡丁车.

---@start
---@varSync driverTaken:boolean=false
---@varSync frontPassengerTaken:boolean=false
---@varSync driverOccupantActorId:number=0
---@varSync frontPassengerOccupantActorId:number=0
---@varSync raceResetCompletedCycleId:string
---@varSync raceResetPhysicalClaimCycleId:string
---@varSync raceResetPhysicalDoneCycleId:string
---@varSync rearLeftTaken:boolean=false
---@varSync rearRightTaken:boolean=false
---@var topSpeed:number=30
---@name 最高速度
---@desc 驾驶位前进时的最大水平速度
---@range 1,60,0.5
---@group 驾驶
---@var acceleration:number=20
---@name 加速能力
---@desc 按住前进时速度提升的快慢
---@range 0,60,0.5
---@group 驾驶
---@var braking:number=30
---@name 刹车力度
---@desc 行驶中输入反方向时削减水平速度的强度
---@range 0,100,0.5
---@group 驾驶
---@var turnSpeed:number=75
---@name 转向灵敏度
---@desc 车辆转弯时的角速度
---@range 0,300,1
---@group 转向
---@var grip:number=0.95
---@name 抓地力
---@desc 数值越高越贴合车头方向，数值越低越容易漂移
---@range 0,1,0.01
---@group 转向
---@var cameraFollowEnabled:boolean=true
---@name 启用相机跟随
---@desc 驾驶位上车后是否自动启用相机 yaw 跟随
---@group 相机
---@var reverseSpeed:number=7
---@name 倒车速度
---@desc 车辆倒车时的最大水平速度
---@range 0,30,0.5
---@group 高级/驾驶
---@var coastingDrag:number=8
---@name 松油门减速
---@desc 松开方向输入后车辆自然减速的强度
---@range 0,40,0.5
---@group 高级/驾驶
---@var sidewaysFriction:number=12
---@name 侧滑恢复
---@desc 削减侧向滑移速度、让车辆重新贴合车头方向的强度
---@range 0,40,0.5
---@group 高级/操控
---@var cameraAlignSpeed:number=120.0
---@name 相机回正速度
---@desc 相机 yaw 向车头方向回正的最大角速度
---@range 0,360,1
---@group 高级/相机
---@var cameraAlignGrace:number=0.45
---@name 手动视角恢复延迟
---@desc 玩家停止手动转视角后等待多久再恢复自动回正
---@range 0,3,0.05
---@group 高级/相机
---@varSync raceSessionStageSnapshot:string=""
---@end

local UnityEngine = CS.UnityEngine
local Time = UnityEngine.Time
local Mathf = UnityEngine.Mathf
local Vector3 = UnityEngine.Vector3
local Quaternion = UnityEngine.Quaternion
local DouyinInputService = CS.DouyinInputService
local DouyinCameraService = CS.DouyinCameraService
if DouyinNetService == nil then DouyinNetService = CS.DouyinNetService end

local DEAD_ZONE = 0.1
local reverseAcceleration = 8.5
local accelerationCurve = 3.4
local minHighSpeedSteerScale = 0.44
local tiltSafetyStart = 12.0
local maxTiltAssistAngle = 25.0
local emergencyStabilityBrake = 14.0
local yawStability = 2.4
local pitchRollDamping = 7.5
local uprightAssist = 4.2
local tiltAssistStart = 4.0
local maxAngularVelocity = 4.5
local cameraBaseSpeedScale = 0.65
local cameraInputSpeedScale = 0.35
local respawnHiddenSeconds = 0.35
local DEG_TO_RAD = math.pi / 180
local trailLifetimeSeconds = 1.5
local trailStopFadeSeconds = 1
local trailStartSpeed = 0.8
local trailStopSpeed = 0.3
local trailGlowWidthMultiplier = 1.5
local trailCoreEmissionIntensity = 3.2
local trailGlowEmissionIntensity = 6.2
local trailPrimaryR = 1
local trailPrimaryG = 0.470588235
local trailPrimaryB = 0.647058824

local rb = nil
local localActor = nil
local currentInside = false
local interactionButtons = {}
local buttonActions = {}
local moveVec = UnityEngine.Vector2.zero
local currentPlayer = nil
local localSeatId = nil
local localSeatActorId = nil
local selectedSeatId = nil
local selectedSeatAnchor = nil
local selectedSeatIndex = -1
local seatedActors = {}
local actorSeatIds = {}
local savedScale = {}
local savedBoardOffset = nil
local savedBoardRotation = nil
local spawnPosition = nil
local spawnRotation = nil
local emptySince = nil
local respawnHideUntil = nil
local netSpawned = false
local lastAcceptedRaceResetCycleId = 0
local lastCompletedRaceResetCycleId = 0
local lastAcknowledgedRaceResetCycleId = 0
local pendingRaceResetCycleId = nil
local raceResetExecuteAt = nil
local raceResetRestoreAt = nil
local raceResetLocked = false
local raceCompetitionLocked = false
local ownershipPending = false
local ownershipPendingDeadline = -math.huge
local seatReservationPending = false
local seatReservationDeadline = -math.huge
local isFocused = false
local proximityCollider = nil
local interactionDistance = 1
local RAD_TO_DEG = 180 / math.pi
local wheelVisuals = {}
local trailVisuals = {}
local trailEmitting = false
local trailFadeStartedAt = nil
local engineAudioObject = nil
local engineAudioSource = nil
local engineAudioClipRetryAt = 0
local engineAudioMutedUntil = 0


local onMoveInputStart = nil
local onMoveInputPerform = nil
local onMoveInputCancel = nil

-- HYBRID_ROLLBACK_LOCAL_BUDGET_V1
local hybridRollbackPrivate = {}
hybridRollbackPrivate.emptyProximityCheckInterval = 0.1
hybridRollbackPrivate.nextEmptyProximityCheckAt = 0
hybridRollbackPrivate.trailAwake = false
hybridRollbackPrivate.trailDriverWasOccupied = false
hybridRollbackPrivate.engineAudioAwake = false
local onLookInputStart = nil
local onLookInputPerform = nil
local onLookInputCancel = nil
local isLookingActive = false
local lastLookTime = -math.huge

local seatTakenCache = {
  driver = false,
  front_passenger = false,
  rear_left = false,
  rear_right = false,
}
local pendingRemoteSeats = {}
local seatOccupantIdCache = {}
local setActorColliderEnabled = nil

local seatConfigs = {
  { id = "driver", label = "驾驶", anchorPath = "SeatAnchor_Driver", canDrive = true, fallbackPosition = Vector3(-0.0913193, 0.21542, -0.0421474) },
  { id = "front_passenger", label = "乘坐·副驾", anchorPath = "SeatAnchor_FrontPassenger", stationPath = "SeatStation_FrontPassenger", canDrive = false, fallbackPosition = Vector3(0.0913193, 0.21542, -0.0421474) },
}

local wheelConfigs = {
  { name = "LP14_Wheel_FL", radius = 0.257567, pivot = Vector3(-0.2763, 0.117076, 0.304398), visualScale = Vector3(0.258654029, 0.258654029, 0.258654029), parts = { "LP14_Wheel_FL_Part_01" } },
  { name = "LP14_Wheel_FR", radius = 0.257567, pivot = Vector3(0.2763, 0.117076, 0.304398), visualScale = Vector3(0.258654029, 0.258654029, 0.258654029), parts = { "LP14_Wheel_FR_Part_01" } },
  { name = "LP14_Wheel_RL", radius = 0.257567, pivot = Vector3(-0.2763, 0.126442, -0.29269), visualScale = Vector3(0.258654029, 0.258654029, 0.258654029), parts = { "LP14_Wheel_RL_Part_01" } },
  { name = "LP14_Wheel_RR", radius = 0.257567, pivot = Vector3(0.2763, 0.126442, -0.29269), visualScale = Vector3(0.258654029, 0.258654029, 0.258654029), parts = { "LP14_Wheel_RR_Part_01" } },
}

local function setupWheelVisuals()
  wheelVisuals = {}
  for configIndex = 1, #wheelConfigs do
    local config = wheelConfigs[configIndex]
    local anchorObject = UnityEngine.GameObject(config.name)
    anchorObject.transform:SetParent(self.transform, false)
    anchorObject.transform.localPosition = config.pivot
    anchorObject.transform.localRotation = Quaternion.identity
    anchorObject.transform.localScale = Vector3.one
    local attachedParts = 0
    for partIndex = 1, #config.parts do
      local partTransform = self.transform:Find(config.parts[partIndex])
      if partTransform ~= nil then
        partTransform:SetParent(anchorObject.transform, false)
        partTransform.localPosition = Vector3.zero
        partTransform.localRotation = Quaternion.identity
        partTransform.localScale = config.visualScale or Vector3.one
        attachedParts = attachedParts + 1
      end
    end
    if attachedParts > 0 then
      table.insert(wheelVisuals, { transform = anchorObject.transform, radius = config.radius, angle = 0 })
    else
      UnityEngine.Object.Destroy(anchorObject)
      UnityEngine.Debug.LogWarning("LP-14「DESSERT·甜品拟物」双人卡丁车: missing visual wheel parts for " .. config.name)
    end
  end
end

local function updateWheelVisuals(dt)
  if rb == nil or #wheelVisuals == 0 then return end
  local localVelocity = self.transform:InverseTransformDirection(rb.velocity)
  local forwardSpeed = localVelocity.z
  if math.abs(forwardSpeed) < 0.01 then return end
  for wheelIndex = 1, #wheelVisuals do
    local wheel = wheelVisuals[wheelIndex]
    wheel.angle = Mathf.Repeat(wheel.angle + (forwardSpeed / wheel.radius) * RAD_TO_DEG * dt, 360.0)
    wheel.transform.localRotation = Quaternion.Euler(wheel.angle, 0, 0)
  end
end

-- Each coreWidth is copied from its source wheel's measured renderer width in
-- world metres. The generator owns this block; do not hand-tune trail widths.
local trailConfigs = {
  { name = "LP14_Trail_RL", glowName = "LP14_TrailGlow_RL", localPosition = Vector3(-0.2763, 0.00280983, -0.29269), coreWidth = 0.48 },
  { name = "LP14_Trail_RR", glowName = "LP14_TrailGlow_RR", localPosition = Vector3(0.2763, 0.00280983, -0.29269), coreWidth = 0.48 },
}

local function createTrailMaterial(name, hdrColor, renderQueue)
  local shader = UnityEngine.Shader.Find("Sprites/Default")
  if shader == nil then
    shader = UnityEngine.Shader.Find("Universal Render Pipeline/Unlit")
  end
  if shader == nil then return nil end
  local material = UnityEngine.Material(shader)
  material.name = name
  material.color = hdrColor
  material.renderQueue = renderQueue
  return material
end

local function setTrailEmission(enabled)
  trailEmitting = enabled == true
  for i = 1, #trailVisuals do
    local visual = trailVisuals[i]
    if visual.renderer ~= nil then visual.renderer.emitting = trailEmitting end
    if visual.glowRenderer ~= nil then visual.glowRenderer.emitting = trailEmitting end
  end
end

function hybridRollbackPrivate.setTrailAwake(awake)
  hybridRollbackPrivate.trailAwake = awake == true
  for i = 1, #trailVisuals do
    local visual = trailVisuals[i]
    if visual.gameObject ~= nil then visual.gameObject:SetActive(hybridRollbackPrivate.trailAwake) end
    if visual.glowObject ~= nil then visual.glowObject:SetActive(hybridRollbackPrivate.trailAwake) end
  end
end

local function applyTrailFade(fadeRatio)
  local visibility = 1.0 - Mathf.Clamp01(fadeRatio)
  for i = 1, #trailVisuals do
    local visual = trailVisuals[i]
    if visual.renderer ~= nil then
      visual.renderer.startWidth = visual.coreWidth * visibility
      visual.renderer.endWidth = visual.coreWidth * visibility
      visual.renderer.startColor = UnityEngine.Color(1.0, 1.0, 1.0, 0.98 * visibility)
      visual.renderer.endColor = UnityEngine.Color(1.0, 1.0, 1.0, 0.0)
    end
    if visual.glowRenderer ~= nil then
      visual.glowRenderer.startWidth = visual.glowWidth * visibility
      visual.glowRenderer.endWidth = visual.glowWidth * visibility
      visual.glowRenderer.startColor = UnityEngine.Color(1.0, 1.0, 1.0, 0.48 * visibility)
      visual.glowRenderer.endColor = UnityEngine.Color(1.0, 1.0, 1.0, 0.0)
    end
  end
end

local function clearTrailPoints()
  for i = 1, #trailVisuals do
    local visual = trailVisuals[i]
    if visual.renderer ~= nil then
      visual.renderer.emitting = false
      visual.renderer:Clear()
    end
    if visual.glowRenderer ~= nil then
      visual.glowRenderer.emitting = false
      visual.glowRenderer:Clear()
    end
  end
  trailEmitting = false
  trailFadeStartedAt = nil
  applyTrailFade(0)
end

function hybridRollbackPrivate.sleepTrailEffect()
  clearTrailPoints()
  hybridRollbackPrivate.setTrailAwake(false)
end

local function setupTrailEffect()
  trailVisuals = {}
  trailEmitting = false
  local coreHdr = UnityEngine.Color(
    trailPrimaryR * trailCoreEmissionIntensity,
    trailPrimaryG * trailCoreEmissionIntensity,
    trailPrimaryB * trailCoreEmissionIntensity,
    1.0
  )
  local glowHdr = UnityEngine.Color(
    trailPrimaryR * trailGlowEmissionIntensity,
    trailPrimaryG * trailGlowEmissionIntensity,
    trailPrimaryB * trailGlowEmissionIntensity,
    1.0
  )
  for i = 1, #trailConfigs do
    local config = trailConfigs[i]
    local trailObject = UnityEngine.GameObject(config.name)
    trailObject.transform.position = self.transform:TransformPoint(config.localPosition)
    trailObject.transform.rotation = Quaternion.identity
    local renderer = trailObject:AddComponent(typeof(UnityEngine.TrailRenderer))
    renderer.time = trailLifetimeSeconds
    renderer.startWidth = config.coreWidth
    renderer.endWidth = config.coreWidth
    renderer.minVertexDistance = 0.045
    renderer.numCornerVertices = 4
    renderer.numCapVertices = 4
    renderer.autodestruct = false
    renderer.startColor = UnityEngine.Color(1.0, 1.0, 1.0, 0.98)
    renderer.endColor = UnityEngine.Color(1.0, 1.0, 1.0, 0.0)
    renderer.emitting = false
    renderer.receiveShadows = false
    renderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off
    local material = createTrailMaterial(config.name .. "_HDR_Material", coreHdr, 3010)
    if material ~= nil then renderer.material = material end
    renderer:Clear()

    local glowWidth = config.coreWidth * trailGlowWidthMultiplier
    local glowObject = UnityEngine.GameObject(config.glowName)
    glowObject.transform.position = self.transform:TransformPoint(config.localPosition)
    glowObject.transform.rotation = Quaternion.identity
    local glowRenderer = glowObject:AddComponent(typeof(UnityEngine.TrailRenderer))
    glowRenderer.time = trailLifetimeSeconds
    glowRenderer.startWidth = glowWidth
    glowRenderer.endWidth = glowWidth
    glowRenderer.minVertexDistance = 0.045
    glowRenderer.numCornerVertices = 5
    glowRenderer.numCapVertices = 5
    glowRenderer.autodestruct = false
    glowRenderer.startColor = UnityEngine.Color(1.0, 1.0, 1.0, 0.48)
    glowRenderer.endColor = UnityEngine.Color(1.0, 1.0, 1.0, 0.0)
    glowRenderer.emitting = false
    glowRenderer.receiveShadows = false
    glowRenderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off
    local glowMaterial = createTrailMaterial(config.glowName .. "_HDR_Material", glowHdr, 3000)
    if glowMaterial ~= nil then glowRenderer.material = glowMaterial end
    glowRenderer:Clear()

    trailVisuals[#trailVisuals + 1] = {
      gameObject = trailObject,
      renderer = renderer,
      material = material,
      glowObject = glowObject,
      glowRenderer = glowRenderer,
      glowMaterial = glowMaterial,
      localPosition = config.localPosition,
      coreWidth = config.coreWidth,
      glowWidth = glowWidth,
    }
  end
  hybridRollbackPrivate.setTrailAwake(false)
end

local function moveTrailAnchors()
  for i = 1, #trailVisuals do
    local visual = trailVisuals[i]
    if visual.gameObject ~= nil then
      visual.gameObject.transform.position = self.transform:TransformPoint(visual.localPosition)
    end
    if visual.glowObject ~= nil then
      visual.glowObject.transform.position = self.transform:TransformPoint(visual.localPosition)
    end
  end
end

local function updateTrailEffect()
  if self == nil or self.transform == nil then return end
  local driverOccupied = hybridRollbackPrivate.hasActualDriver()
  local driverJustOccupied = driverOccupied and not hybridRollbackPrivate.trailDriverWasOccupied
  hybridRollbackPrivate.trailDriverWasOccupied = driverOccupied
  if not driverOccupied and not hybridRollbackPrivate.trailAwake and not trailEmitting and trailFadeStartedAt == nil then return end
  if driverJustOccupied and not hybridRollbackPrivate.trailAwake then hybridRollbackPrivate.setTrailAwake(true) end
  local forwardSpeed = 0
  if rb ~= nil then
    forwardSpeed = self.transform:InverseTransformDirection(rb.velocity).z
  end

  -- No driver and reverse motion clear immediately; neither state may retain
  -- or generate a forward-driving trace.
  if not driverOccupied or forwardSpeed < -0.05 then
    if hybridRollbackPrivate.trailAwake or trailEmitting or trailFadeStartedAt ~= nil then hybridRollbackPrivate.sleepTrailEffect() end
    return
  end

  if trailEmitting then
    if forwardSpeed <= trailStopSpeed then
      -- Stop creating points and freeze the unparented emitters so the
      -- existing 1.5-second trail can naturally fade without smearing.
      setTrailEmission(false)
      trailFadeStartedAt = Time.time
    else
      moveTrailAnchors()
    end
    return
  end

  if trailFadeStartedAt ~= nil then
    local fadeElapsed = Time.time - trailFadeStartedAt
    if fadeElapsed >= trailStopFadeSeconds then
      hybridRollbackPrivate.sleepTrailEffect()
    else
      applyTrailFade(fadeElapsed / trailStopFadeSeconds)
    end
  end

  if forwardSpeed > trailStartSpeed then
    -- Start a fresh segment instead of connecting to a frozen stop point.
    if not hybridRollbackPrivate.trailAwake then hybridRollbackPrivate.setTrailAwake(true) end
    clearTrailPoints()
    moveTrailAnchors()
    setTrailEmission(true)
  end
end

local function destroyTrailEffect()
  hybridRollbackPrivate.sleepTrailEffect()
  for i = 1, #trailVisuals do
    local visual = trailVisuals[i]
    if visual.material ~= nil then UnityEngine.Object.Destroy(visual.material) end
    if visual.glowMaterial ~= nil then UnityEngine.Object.Destroy(visual.glowMaterial) end
    if visual.gameObject ~= nil then UnityEngine.Object.Destroy(visual.gameObject) end
    if visual.glowObject ~= nil then UnityEngine.Object.Destroy(visual.glowObject) end
  end
  trailVisuals = {}
  hybridRollbackPrivate.trailAwake = false
  hybridRollbackPrivate.trailDriverWasOccupied = false
end

function hybridRollbackPrivate.setEngineAudioAwake(awake)
  hybridRollbackPrivate.engineAudioAwake = awake == true
  if engineAudioObject ~= nil then engineAudioObject:SetActive(hybridRollbackPrivate.engineAudioAwake) end
end

local function stopEngineAudio(immediate)
  if engineAudioSource == nil then
    hybridRollbackPrivate.setEngineAudioAwake(false)
    return
  end
  if immediate then
    engineAudioSource.volume = 0
    if engineAudioSource.isPlaying then engineAudioSource:Stop() end
    hybridRollbackPrivate.setEngineAudioAwake(false)
  end
end

local function setupEngineAudioSource()
  if engineAudioSource ~= nil then return true end
  local existing = self.transform:Find("Race_EngineAudio")
  if existing ~= nil then
    engineAudioObject = existing.gameObject
  else
    engineAudioObject = UnityEngine.GameObject("Race_EngineAudio")
    engineAudioObject.transform:SetParent(self.transform, false)
  end
  engineAudioObject.transform.localPosition = Vector3(0, 0.25, -0.25)
  engineAudioObject.transform.localRotation = Quaternion.identity
  engineAudioObject.transform.localScale = Vector3.one
  engineAudioSource = engineAudioObject:GetComponent(typeof(UnityEngine.AudioSource))
  if engineAudioSource == nil then
    engineAudioSource = engineAudioObject:AddComponent(typeof(UnityEngine.AudioSource))
  end
  if engineAudioSource == nil then return false end
  engineAudioSource.playOnAwake = false
  engineAudioSource.loop = true
  engineAudioSource.volume = 0
  engineAudioSource.pitch = 0.82
  engineAudioSource.spatialBlend = 1
  engineAudioSource.dopplerLevel = 0.15
  engineAudioSource.spread = 70
  engineAudioSource.minDistance = 2
  engineAudioSource.maxDistance = 32
  engineAudioSource.rolloffMode = UnityEngine.AudioRolloffMode.Logarithmic
  hybridRollbackPrivate.setEngineAudioAwake(false)
  return true
end

local function tryBindEngineAudioClip()
  if engineAudioSource == nil or engineAudioSource.clip ~= nil then return true end
  if Time.time < engineAudioClipRetryAt then return false end
  engineAudioClipRetryAt = Time.time + 1.0
  local managerObject = UnityEngine.GameObject.Find("RaceManager")
  if managerObject == nil then return false end
  local holder = nil
  pcall(function() holder = managerObject:GetDouyinScript("f8a36c92-1639-4629-8b3f-4f36aa49a5f6") end)
  if holder == nil then
    pcall(function() holder = managerObject:GetDouyinScript("race-engine-audio-bank.lua") end)
  end
  if holder == nil then
    pcall(function() holder = managerObject:GetDouyinScript("race-engine-audio-bank") end)
  end
  if holder == nil or holder.script == nil then return false end
  local ok, clip = pcall(function()
    return holder.script.GetSharedRaceEngineAudioClip()
  end)
  if not ok or clip == nil then return false end
  engineAudioSource.clip = clip
  return true
end

local function updateEngineAudio()
  if engineAudioSource == nil and not setupEngineAudioSource() then return end
  if not hybridRollbackPrivate.engineAudioAwake then hybridRollbackPrivate.setEngineAudioAwake(true) end
  tryBindEngineAudioClip()
  local targetVolume = 0
  local targetPitch = 0.82
  if rb ~= nil and engineAudioSource.clip ~= nil and hybridRollbackPrivate.hasActualDriver()
    and not raceResetLocked and Time.time >= engineAudioMutedUntil then
    local localVelocity = self.transform:InverseTransformDirection(rb.velocity)
    local forwardSpeed = math.max(0, localVelocity.z)
    if forwardSpeed > 0.3 then
      local speed01 = Mathf.Clamp01(forwardSpeed / math.max(1, topSpeed))
      local curve = math.sqrt(speed01)
      targetVolume = Mathf.Lerp(0.15, 0.72, curve)
      targetPitch = Mathf.Lerp(0.82, 1.45, curve)
    end
  end
  local dt = math.max(0, Time.deltaTime)
  local volumeRate = targetVolume > engineAudioSource.volume and 2.2 or 1.1
  engineAudioSource.volume = Mathf.MoveTowards(engineAudioSource.volume, targetVolume, volumeRate * dt)
  engineAudioSource.pitch = Mathf.MoveTowards(engineAudioSource.pitch, targetPitch, 1.6 * dt)
  if targetVolume > 0 then
    if not engineAudioSource.isPlaying and engineAudioSource.clip ~= nil then
      engineAudioSource:Play()
    end
  elseif engineAudioSource.volume <= 0.005 then
    engineAudioSource.volume = 0
    if engineAudioSource.isPlaying then engineAudioSource:Stop() end
    if not hybridRollbackPrivate.hasActualDriver() then hybridRollbackPrivate.setEngineAudioAwake(false) end
  end
end

local function destroyEngineAudio()
  stopEngineAudio(true)
  if engineAudioObject ~= nil then UnityEngine.Object.Destroy(engineAudioObject) end
  engineAudioObject = nil
  engineAudioSource = nil
  hybridRollbackPrivate.engineAudioAwake = false
end

local function getSeatVar(id)
  if id == "driver" then return driverTaken end
  if id == "front_passenger" then return frontPassengerTaken end
  return nil
end

local function getSeatOccupantVar(id)
  if id == "driver" then return driverOccupantActorId end
  if id == "front_passenger" then return frontPassengerOccupantActorId end
  return nil
end

local function findSeatConfig(id)
  for i = 1, #seatConfigs do
    if seatConfigs[i].id == id then return seatConfigs[i], i end
  end
  return nil, -1
end

local function anySeatTaken()
  for index = 1, #seatConfigs do
    if seatTakenCache[seatConfigs[index].id] == true then return true end
  end
  return false
end

local function updateEmptyTimer()
  if anySeatTaken() then
    emptySince = nil
  elseif emptySince == nil then
    emptySince = Time.time
  end
end

local function enqueuePendingRemoteSeat(id)
  for index = 1, #pendingRemoteSeats do
    if pendingRemoteSeats[index] == id then return end
  end
  pendingRemoteSeats[#pendingRemoteSeats + 1] = id
end

local function popPendingRemoteSeat()
  if #pendingRemoteSeats <= 0 then return nil end
  local id = pendingRemoteSeats[1]
  table.remove(pendingRemoteSeats, 1)
  return id
end

local function removePendingRemoteSeat(id)
  for i = #pendingRemoteSeats, 1, -1 do
    if pendingRemoteSeats[i] == id then table.remove(pendingRemoteSeats, i) end
  end
end

local function clamp(value, minValue, maxValue)
  if value < minValue then return minValue end
  if value > maxValue then return maxValue end
  return value
end

local function multiplyQuaternion(lhs, rhs)
  return Quaternion(
    lhs.w * rhs.x + lhs.x * rhs.w + lhs.y * rhs.z - lhs.z * rhs.y,
    lhs.w * rhs.y - lhs.x * rhs.z + lhs.y * rhs.w + lhs.z * rhs.x,
    lhs.w * rhs.z + lhs.x * rhs.y - lhs.y * rhs.x + lhs.z * rhs.w,
    lhs.w * rhs.w - lhs.x * rhs.x - lhs.y * rhs.y - lhs.z * rhs.z
  )
end

local function normalizePath(path)
  if path == nil then return "" end
  local result = tostring(path)
  while string.sub(result, 1, 1) == "/" do
    result = string.sub(result, 2)
  end
  while string.sub(result, -1) == "/" do
    result = string.sub(result, 1, string.len(result) - 1)
  end
  return result
end

local function collectTransformPaths(parent, currentPath, entries)
  entries[#entries + 1] = { path = currentPath, transform = parent }
  for i = 0, parent.childCount - 1 do
    local child = parent:GetChild(i)
    if child ~= nil then
      local childPath = child.name
      if currentPath ~= "" then
        childPath = currentPath .. "/" .. child.name
      end
      collectTransformPaths(child, childPath, entries)
    end
  end
end

local function pathHasSuffix(path, suffix)
  if path == suffix then return true end
  local pathLen = string.len(path)
  local suffixLen = string.len(suffix)
  if suffixLen <= 0 or pathLen <= suffixLen then return false end
  if string.sub(path, pathLen - suffixLen + 1) ~= suffix then return false end
  return string.sub(path, pathLen - suffixLen, pathLen - suffixLen) == "/"
end

local function findUniquePathSuffix(entries, suffix)
  local found = nil
  local count = 0
  for i = 1, #entries do
    local entry = entries[i]
    if pathHasSuffix(entry.path, suffix) then
      found = entry.transform
      count = count + 1
    end
  end
  return found, count
end

local function findChild(parent, targetPath)
  if parent == nil or targetPath == nil then return nil end
  local entries = {}
  collectTransformPaths(parent, normalizePath(parent.name), entries)
  local lookupPath = normalizePath(targetPath)
  if lookupPath == "" then return parent end
  while lookupPath ~= "" do
    local found, count = findUniquePathSuffix(entries, lookupPath)
    -- Multipart imports preserve the same empty hierarchy in every visual
    -- chunk. The first suffix match belongs to the carrier and is deterministic.
    if count >= 1 then return found end
    local slashIdx = string.find(lookupPath, "/", 1, true)
    if slashIdx == nil then break end
    lookupPath = normalizePath(string.sub(lookupPath, slashIdx + 1))
  end
  return nil
end

local function setRendererVisible(trans, visible)
  if trans == nil then return end
  -- Passenger station is a logical seat endpoint, never visible vehicle art.
  -- A full vehicle refresh must not re-enable its helper renderer.
  if trans ~= self.transform and tostring(trans.gameObject.name) == "SeatStation_FrontPassenger" then
    visible = false
  end
  local renderer = trans.gameObject:GetComponent(typeof(UnityEngine.Renderer))
  if renderer ~= nil then
    renderer.enabled = visible
  end
  for i = 0, trans.childCount - 1 do
    setRendererVisible(trans:GetChild(i), visible)
  end
end

local function setButtonText(button, text)
  if button == nil then return end
  local label = button:GetComponentInChildren(typeof(UnityEngine.UI.Text))
  if label ~= nil then
    label.text = text
  end
end

local function removeInteractionButtons()
  for i = 1, #interactionButtons do
    if interactionButtons[i] ~= nil then
      self:RemoveInteractorButton(interactionButtons[i])
    end
  end
  interactionButtons = {}
  buttonActions = {}
end

local function addActionButton(label, action)
  local button = self:AddInteractorButton()
  interactionButtons[#interactionButtons + 1] = button
  buttonActions[#interactionButtons] = action
  setButtonText(button, label)
end

local function rebuildInteractionButtons()
  removeInteractionButtons()
  if localActor == nil then return end
  if raceResetLocked or raceCompetitionLocked then return end
  if localSeatId ~= nil then
    addActionButton("下车", { kind = "exit" })
    return
  end
  if hybridRollbackPrivate.seatFeedbackUntil ~= nil
    and Time.time < hybridRollbackPrivate.seatFeedbackUntil then
    addActionButton(hybridRollbackPrivate.seatFeedbackText or "座位占用中", { kind = "feedback" })
  end
  for i = 1, #seatConfigs do
    local cfg = seatConfigs[i]
    if not seatTakenCache[cfg.id]
      or hybridRollbackPrivate.readSeatOccupantId(cfg.id) == 0 then
      local buttonLabel = cfg.label
      if cfg.canDrive and self ~= nil and self.gameObject ~= nil then
        local moduleName = tostring(self.gameObject.name or "")
        if moduleName ~= "" then buttonLabel = "驾驶" .. moduleName end
      end
      addActionButton(buttonLabel, { kind = "sit", seatId = cfg.id })
    end
  end
end

local function refreshInteractionForState()
  updateEmptyTimer()
  if raceResetLocked or raceCompetitionLocked then
    self:DisableInteraction()
    removeInteractionButtons()
    return
  end
  if currentInside or localSeatId ~= nil then
    self:EnableInteraction()
    rebuildInteractionButtons()
  elseif not currentInside then
    self:DisableInteraction()
    removeInteractionButtons()
  end
end

local function actorWithinInteractionDistance()
  if localActor == nil and DouyinActorService ~= nil then
    localActor = DouyinActorService.GetLocalActor()
  end
  if localActor == nil or self == nil or self.transform == nil then return false end
  local actorPosition = localActor.position
  local closestPoint = self.transform.position
  if proximityCollider ~= nil then
    closestPoint = proximityCollider.bounds:ClosestPoint(actorPosition)
  end
  local dx = actorPosition.x - closestPoint.x
  local dy = actorPosition.y - closestPoint.y
  local dz = actorPosition.z - closestPoint.z
  return dx * dx + dy * dy + dz * dz <= interactionDistance * interactionDistance
end

local function updateProximityInteraction()
  if raceResetLocked or raceCompetitionLocked then
    self:DisableInteraction()
    removeInteractionButtons()
    return
  end
  if localSeatId ~= nil then
    if not currentInside or #interactionButtons == 0 then
      currentInside = true
      self:EnableInteraction()
      rebuildInteractionButtons()
    end
    return
  end
  local nearby = actorWithinInteractionDistance()
  if nearby then
    if not currentInside or #interactionButtons == 0 then
      currentInside = true
      self:EnableInteraction()
      rebuildInteractionButtons()
    end
  elseif currentInside then
    currentInside = false
    self:DisableInteraction()
    removeInteractionButtons()
    localActor = nil
  end
end

function hybridRollbackPrivate.proximityNeedsEveryFrame()
  if raceResetLocked
    or localSeatId ~= nil
    or anySeatTaken()
    or ownershipPending
    or seatReservationPending
    or selectedSeatId ~= nil
    or savedScale.__seatWaitingForNetwork == true
    or savedScale.__localSeatClaim ~= nil
  then
    return true
  end
  return false
end

function hybridRollbackPrivate.updateProximityInteractionBudgeted()
  if hybridRollbackPrivate.proximityNeedsEveryFrame() then
    hybridRollbackPrivate.nextEmptyProximityCheckAt = 0
    updateProximityInteraction()
    return
  end
  local now = Time.time
  if now < hybridRollbackPrivate.nextEmptyProximityCheckAt then return end
  hybridRollbackPrivate.nextEmptyProximityCheckAt = now + hybridRollbackPrivate.emptyProximityCheckInterval
  updateProximityInteraction()
end

local function ensureOwnership(onSuccess, onFailure)
  if onSuccess == nil then return false end
  if DouyinNetService == nil then
    onSuccess()
    return true
  end
  if not DouyinNetService.isNetworkSettled then
    if onFailure ~= nil then onFailure() end
    return false
  end
  local owner = false
  pcall(function() owner = self:HasOwnership() end)
  if owner then
    onSuccess()
    return true
  end
  if ownershipPending and Time.time < ownershipPendingDeadline then return false end
  ownershipPending = true
  ownershipPendingDeadline = Time.time + 2.0
  local requestOk = pcall(function()
    self:RequestOwnership(function(bSucceed)
      ownershipPending = false
      ownershipPendingDeadline = -math.huge
      if bSucceed then
        onSuccess()
      elseif onFailure ~= nil then
        onFailure()
      end
    end)
  end)
  if not requestOk then
    ownershipPending = false
    ownershipPendingDeadline = -math.huge
    if onFailure ~= nil then onFailure() end
    return false
  end
  return true
end

local function writeSeatTaken(id, taken)
  local synchronizedTaken = taken == true
  if DouyinNetService == nil then
    seatTakenCache[id] = synchronizedTaken
    return true
  end
  if not DouyinNetService.isNetworkSettled or not netSpawned then return false end
  local variable = getSeatVar(id)
  if variable == nil then return false end
  local ok = pcall(function() variable:SetValue(synchronizedTaken) end)
  if ok then seatTakenCache[id] = synchronizedTaken end
  return ok
end

local function writeSeatOccupantId(id, rawActorId)
  local actorId = math.floor(tonumber(rawActorId) or 0)
  if actorId < 1 then actorId = 0 end
  if DouyinNetService == nil then
    seatOccupantIdCache[id] = actorId
    return true
  end
  if not DouyinNetService.isNetworkSettled or not netSpawned then return false end
  local variable = getSeatOccupantVar(id)
  if variable == nil then return false end
  local ok = pcall(function() variable:SetValue(actorId) end)
  if ok then seatOccupantIdCache[id] = actorId end
  return ok
end

function hybridRollbackPrivate.normalizeActorId(rawActorId)
  local actorId = tonumber(rawActorId)
  if actorId == nil or actorId ~= actorId then return 0 end
  actorId = math.floor(actorId)
  if actorId < 1 then return 0 end
  return actorId
end

function hybridRollbackPrivate.actorNetworkId(actor)
  if actor == nil then return 0 end
  local ok, result = pcall(function() return actor.actorID end)
  if not ok then return 0 end
  return hybridRollbackPrivate.normalizeActorId(result)
end

function hybridRollbackPrivate.readSeatOccupantId(seatId)
  local cached = hybridRollbackPrivate.normalizeActorId(seatOccupantIdCache[seatId])
  if DouyinNetService == nil or not netSpawned then return cached end
  local variable = getSeatOccupantVar(seatId)
  if variable == nil then return cached end
  local ok, value = pcall(function() return variable:GetValue() end)
  if ok then
    cached = hybridRollbackPrivate.normalizeActorId(value)
    seatOccupantIdCache[seatId] = cached
  end
  return cached
end

function hybridRollbackPrivate.actorIsActuallySitting(actor)
  if actor == nil then return false end
  local ok, sitting = pcall(function() return actor:IsSitting() end)
  return ok and sitting == true
end

function hybridRollbackPrivate.actorIsAtSeatAnchor(actor, seatId)
  local cfg = findSeatConfig(seatId)
  if actor == nil or cfg == nil or cfg.transform == nil then return false end
  local ok, parent = pcall(function() return actor.gameObject.transform.parent end)
  return ok and parent == cfg.transform
end

function hybridRollbackPrivate.actorSeatRelation(actor, seatId)
  local cfg = findSeatConfig(seatId)
  if actor == nil or cfg == nil or cfg.transform == nil then return "UNKNOWN" end
  local ok, relation = pcall(function()
    local parent = actor.gameObject.transform.parent
    if parent == nil then return "UNKNOWN" end
    if parent == cfg.transform or (cfg.stationTransform ~= nil and parent == cfg.stationTransform) then
      return "TARGET"
    end
    local cursor = parent
    local depth = 0
    local looksLikeAnotherSeat = false
    while cursor ~= nil and depth < 32 do
      if cursor == self.transform then return "THIS_VEHICLE" end
      local cursorName = tostring(cursor.name or "")
      if string.sub(cursorName, 1, 11) == "SeatAnchor_"
        or string.sub(cursorName, 1, 12) == "SeatStation_" then
        looksLikeAnotherSeat = true
      end
      for index = 1, #seatConfigs do
        local known = seatConfigs[index]
        if known.transform ~= nil and cursor.name == known.transform.name then
          looksLikeAnotherSeat = true
        end
        if known.stationTransform ~= nil and cursor.name == known.stationTransform.name then
          looksLikeAnotherSeat = true
        end
      end
      cursor = cursor.parent
      depth = depth + 1
    end
    return looksLikeAnotherSeat and "OTHER" or "UNKNOWN"
  end)
  if not ok then return "UNKNOWN" end
  return relation
end

function hybridRollbackPrivate.trackedSeatForActorId(rawActorId)
  local actorId = hybridRollbackPrivate.normalizeActorId(rawActorId)
  if actorId == 0 then return nil, nil end
  for actor, trackedSeatId in pairs(actorSeatIds) do
    if hybridRollbackPrivate.actorNetworkId(actor) == actorId then
      return actor, trackedSeatId
    end
  end
  return nil, nil
end

function hybridRollbackPrivate.findTrackedSeatActor(seatId, requireSitting)
  for actor, trackedSeatId in pairs(actorSeatIds) do
    if trackedSeatId == seatId then
      if requireSitting ~= true or (hybridRollbackPrivate.actorIsActuallySitting(actor)
        and hybridRollbackPrivate.actorIsAtSeatAnchor(actor, seatId)) then
        return actor
      end
    end
  end
  return nil
end

function hybridRollbackPrivate.hasActualSeatActor(seatId)
  if hybridRollbackPrivate.normalizeActorId(seatOccupantIdCache[seatId]) > 0 then return true end
  return hybridRollbackPrivate.findTrackedSeatActor(seatId, true) ~= nil
end

function hybridRollbackPrivate.hasActualDriver()
  return hybridRollbackPrivate.hasActualSeatActor("driver")
end

function hybridRollbackPrivate.seatClaimShadow()
  local shadow = savedScale.__seatClaimShadow
  if shadow == nil then
    shadow = {}
    savedScale.__seatClaimShadow = shadow
  end
  return shadow
end

function hybridRollbackPrivate.activeSeatClaim(seatId)
  local claim = hybridRollbackPrivate.seatClaimShadow()[seatId]
  if type(claim) ~= "table" then return nil end
  if (tonumber(claim.expiresAt) or -math.huge) <= Time.time then return nil end
  return claim
end

function hybridRollbackPrivate.setSeatClaim(seatId, rawActorId, seconds)
  local actorId = hybridRollbackPrivate.normalizeActorId(rawActorId)
  if seatId == nil or actorId == 0 then return nil end
  local claim = { actorId = actorId, expiresAt = Time.time + (tonumber(seconds) or 5) }
  hybridRollbackPrivate.seatClaimShadow()[seatId] = claim
  return claim
end

function hybridRollbackPrivate.clearSeatClaim(seatId)
  if seatId ~= nil then hybridRollbackPrivate.seatClaimShadow()[seatId] = nil end
end

function hybridRollbackPrivate.isSeatStateOwner()
  if DouyinNetService == nil then return true end
  if not DouyinNetService.isNetworkSettled or not netSpawned then return false end
  local owner = false
  pcall(function() owner = self:HasOwnership() end)
  return owner
end

function hybridRollbackPrivate.findRoomActor(rawActorId)
  local actorId = hybridRollbackPrivate.normalizeActorId(rawActorId)
  if actorId == 0 then return nil, "INVALID" end
  if DouyinActorService == nil then return nil, "UNKNOWN" end
  local ok, actor = pcall(function() return DouyinActorService.GetActorById(actorId) end)
  if not ok then return nil, "UNKNOWN" end
  if actor == nil then return nil, "INVALID" end
  return actor, "FOUND"
end

function hybridRollbackPrivate.scanPhysicalSeatActor(seatId)
  local cfg = findSeatConfig(seatId)
  if cfg == nil or cfg.transform == nil or DouyinActorService == nil then
    return nil, "UNKNOWN"
  end
  local ok, actors = pcall(function() return DouyinActorService.GetActors() end)
  if not ok or actors == nil then return nil, "UNKNOWN" end

  local found = nil
  local probeFailed = false
  local function consider(actor)
    if found ~= nil or actor == nil then return end
    local sittingOk, sitting = pcall(function() return actor:IsSitting() end)
    local parentOk, parent = pcall(function() return actor.gameObject.transform.parent end)
    if not sittingOk or not parentOk then probeFailed = true end
    local atTarget = parentOk
      and (parent == cfg.transform or (cfg.stationTransform ~= nil and parent == cfg.stationTransform))
    if atTarget then
      if sittingOk and sitting == true then
        found = actor
      else
        -- A remote Actor can be parented to the station before IsSitting
        -- catches up. Treat that exact attachment as unknown, never empty.
        probeFailed = true
      end
    end
  end

  local lengthOk, length = pcall(function() return actors.Length end)
  if lengthOk and tonumber(length) ~= nil then
    for index = 0, math.max(0, math.floor(tonumber(length))) - 1 do
      local actorOk, actor = pcall(function() return actors[index] end)
      if actorOk then consider(actor) else probeFailed = true end
    end
    return found, found ~= nil and "FOUND" or (probeFailed and "UNKNOWN" or "EMPTY")
  end
  local countOk, count = pcall(function() return actors.Count end)
  if countOk and tonumber(count) ~= nil then
    for index = 0, math.max(0, math.floor(tonumber(count))) - 1 do
      local actorOk, actor = pcall(function() return actors[index] end)
      if actorOk then consider(actor) else probeFailed = true end
    end
    return found, found ~= nil and "FOUND" or (probeFailed and "UNKNOWN" or "EMPTY")
  end
  if type(actors) == "table" then
    for _, actor in pairs(actors) do consider(actor) end
    return found, found ~= nil and "FOUND" or (probeFailed and "UNKNOWN" or "EMPTY")
  end
  return nil, "UNKNOWN"
end

function hybridRollbackPrivate.legacyPhysicalSeats()
  local legacy = savedScale.__legacyPhysicalSeats
  if legacy == nil then
    legacy = {}
    savedScale.__legacyPhysicalSeats = legacy
  end
  return legacy
end

function hybridRollbackPrivate.seatMigrationGraceUntil()
  local grace = savedScale.__seatMigrationGraceUntil
  if grace == nil then
    grace = {}
    savedScale.__seatMigrationGraceUntil = grace
  end
  return grace
end

function hybridRollbackPrivate.seatOfficialProofs()
  local proofs = savedScale.__seatOfficialProofs
  if proofs == nil then
    proofs = {}
    savedScale.__seatOfficialProofs = proofs
  end
  return proofs
end

function hybridRollbackPrivate.seatUnknownSince()
  local unknown = savedScale.__seatUnknownSince
  if unknown == nil then
    unknown = {}
    savedScale.__seatUnknownSince = unknown
  end
  return unknown
end

function hybridRollbackPrivate.seatActorHealth(seatId, rawActorId)
  local actorId = hybridRollbackPrivate.normalizeActorId(rawActorId)
  if actorId == 0 then return "INVALID", nil end
  local actor, lookup = hybridRollbackPrivate.findRoomActor(actorId)
  if lookup ~= "FOUND" then return lookup, nil end
  local sittingOk, sitting = pcall(function() return actor:IsSitting() end)
  if not sittingOk then return "UNKNOWN", actor end
  if sitting ~= true then
    -- Native exit can precede both Exit and LateUpdate. Preserve only the exact
    -- frozen local ride while its real SitDown confirmation is still pending.
    if hybridRollbackPrivate.isRaceCompetitionSeatHealthProtected ~= nil
      and hybridRollbackPrivate.isRaceCompetitionSeatHealthProtected(actor, seatId, actorId) then
      return "REPAIRING", actor
    end
    return "INVALID", actor
  end

  local cfg = findSeatConfig(seatId)
  local parentOk, parent = pcall(function() return actor.gameObject.transform.parent end)
  if parentOk and cfg ~= nil and ((cfg.transform ~= nil and parent == cfg.transform)
    or (cfg.stationTransform ~= nil and parent == cfg.stationTransform)) then
    return "VALID", actor
  end
  local relation = hybridRollbackPrivate.actorSeatRelation(actor, seatId)
  if relation == "OTHER" then return "INVALID", actor end
  if parentOk and parent ~= nil then
    for index = 1, #seatConfigs do
      local other = seatConfigs[index]
       if other.id ~= seatId and ((other.transform ~= nil and parent == other.transform)
         or (other.stationTransform ~= nil and parent == other.stationTransform)) then
        return "INVALID", actor
      end
    end
  end

  local trackedActor, trackedSeatId = hybridRollbackPrivate.trackedSeatForActorId(actorId)
  if trackedSeatId ~= nil and trackedSeatId ~= seatId then
    return "INVALID", trackedActor or actor
  end

  local proof = hybridRollbackPrivate.seatOfficialProofs()[seatId]
  if type(proof) == "table" and proof.actorId == actorId
    and (tonumber(proof.expiresAt) or -math.huge) > Time.time then
    return "VALID", actor
  end
  if parentOk and parent ~= nil then return "INVALID", actor end
  return "UNKNOWN", actor
end

function hybridRollbackPrivate.clearTrackedSeatActor(rawActorId, seatId)
  local actorId = hybridRollbackPrivate.normalizeActorId(rawActorId)
  for actor, trackedSeatId in pairs(actorSeatIds) do
    if trackedSeatId == seatId and hybridRollbackPrivate.actorNetworkId(actor) == actorId then
      local sittingOk, sitting = pcall(function() return actor:IsSitting() end)
      local relation = hybridRollbackPrivate.actorSeatRelation(actor, seatId)
      local preserveActorScale = relation == "THIS_VEHICLE"
      if sittingOk and sitting ~= true then
        local parentOk, parent = pcall(function() return actor.gameObject.transform.parent end)
        local stillOnTrackedSeat = relation == "TARGET"
        local alreadyDetached = parentOk and parent == nil
        -- During a V1 -> V2 transition IsSitting may briefly be false after the
        -- Actor is already parented to V2. Never let V1 unparent, rescale, or
        -- change collision on an Actor that no longer belongs to V1.
        if stillOnTrackedSeat then
          local actorPosition = nil
          pcall(function() actorPosition = actor.gameObject.transform.position end)
          pcall(function() actor.gameObject.transform:SetParent(nil) end)
          if savedScale[actor] ~= nil then
            pcall(function() actor.gameObject.transform.localScale = savedScale[actor] end)
          end
          if actorPosition ~= nil then
            pcall(function() actor.gameObject.transform.position = actorPosition end)
          end
        elseif alreadyDetached and savedScale[actor] ~= nil then
          pcall(function() actor.gameObject.transform.localScale = savedScale[actor] end)
        end
        if (stillOnTrackedSeat or alreadyDetached) and setActorColliderEnabled ~= nil then
          setActorColliderEnabled(actor, true)
        end
      end
      if not preserveActorScale then savedScale[actor] = nil end
      seatedActors[actor] = nil
      actorSeatIds[actor] = nil
      if savedScale.__processedSeatEntries ~= nil then
        savedScale.__processedSeatEntries[actor] = nil
      end
    end
  end
end

function hybridRollbackPrivate.clearSeatOfficialState(seatId)
  hybridRollbackPrivate.clearSeatClaim(seatId)
  hybridRollbackPrivate.seatOfficialProofs()[seatId] = nil
  hybridRollbackPrivate.seatUnknownSince()[seatId] = nil
  if not writeSeatOccupantId(seatId, 0) then return false end
  local takenCleared = writeSeatTaken(seatId, false)
  if takenCleared then refreshInteractionForState() end
  return takenCleared
end

function hybridRollbackPrivate.cleanupInvalidTrackedActors()
  local stale = {}
  for actor, trackedSeatId in pairs(actorSeatIds) do
    local actorId = hybridRollbackPrivate.actorNetworkId(actor)
    local health = select(1, hybridRollbackPrivate.seatActorHealth(trackedSeatId, actorId))
    if actorId == 0 or health == "INVALID" then
      stale[#stale + 1] = { actorId = actorId, seatId = trackedSeatId, actor = actor }
    end
  end
  for index = 1, #stale do
    local entry = stale[index]
    if entry.actorId > 0 then
      hybridRollbackPrivate.clearTrackedSeatActor(entry.actorId, entry.seatId)
    else
      seatedActors[entry.actor] = nil
      actorSeatIds[entry.actor] = nil
      if savedScale.__processedSeatEntries ~= nil then
        savedScale.__processedSeatEntries[entry.actor] = nil
      end
    end
  end
end

-- PERF-0911: phase only background scans; never delay callbacks or physics.
function hybridRollbackPrivate.nextMaintenanceAt(interval)
  local slot = savedScale.__maintenanceSlot
  if slot == nil then
    local names = {"玩具","莓爆花","绯樱","暴走","薄荷糖","甜品","牛牛","牛粉","烈焰","赤巡","积木","宝宝巴","星梦巴","爆米花"}
    slot = 0
    for i = 1, #names do if self.gameObject.name == names[i] then slot = i - 1; break end end
    savedScale.__maintenanceSlot = slot
  end
  local phase = interval * slot / 14
  return (math.floor((Time.time - phase) / interval + 0.000001) + 1) * interval + phase
end

function hybridRollbackPrivate.reconcileSeatClaims(force)
  if force ~= true then
    local nextAt = tonumber(savedScale.__seatClaimReconcileAt) or -math.huge
    if Time.time < nextAt then return end
savedScale.__seatClaimReconcileAt = hybridRollbackPrivate.nextMaintenanceAt(0.1)
  end
  if raceResetLocked or not hybridRollbackPrivate.isSeatStateOwner() then return end

  local runHealthCheck = force == true
    or Time.time >= (tonumber(savedScale.__seatOccupantHealthAt) or -math.huge)
if runHealthCheck then savedScale.__seatOccupantHealthAt = hybridRollbackPrivate.nextMaintenanceAt(0.5) end
  local shadow = hybridRollbackPrivate.seatClaimShadow()
  local unknownSince = hybridRollbackPrivate.seatUnknownSince()
  local legacyPhysical = hybridRollbackPrivate.legacyPhysicalSeats()
  local migrationGrace = hybridRollbackPrivate.seatMigrationGraceUntil()
  local changed = false

  for index = 1, #seatConfigs do
    local seatId = seatConfigs[index].id
    local occupantId = hybridRollbackPrivate.normalizeActorId(seatOccupantIdCache[seatId])
    if runHealthCheck then occupantId = hybridRollbackPrivate.readSeatOccupantId(seatId) end
    local rawClaim = shadow[seatId]
    local claim = hybridRollbackPrivate.activeSeatClaim(seatId)
    local claimExpired = type(rawClaim) == "table" and claim == nil
    if rawClaim ~= nil and claim == nil then shadow[seatId] = nil end
    if claim ~= nil and runHealthCheck and DouyinNetService ~= nil then
      local _, claimantLookup = hybridRollbackPrivate.findRoomActor(claim.actorId)
      if claimantLookup == "INVALID" then
        shadow[seatId] = nil
        claim = nil
        claimExpired = true
      end
    end

    if occupantId > 0 then
      legacyPhysical[seatId] = nil
      if runHealthCheck then
        local health = hybridRollbackPrivate.seatActorHealth(seatId, occupantId)
        if health == "INVALID" then
          hybridRollbackPrivate.clearTrackedSeatActor(occupantId, seatId)
          if hybridRollbackPrivate.clearSeatOfficialState(seatId) then changed = true end
        elseif health == "UNKNOWN" then
          local firstUnknownAt = tonumber(unknownSince[seatId])
          if firstUnknownAt == nil then
            unknownSince[seatId] = Time.time
          elseif Time.time - firstUnknownAt >= 3.0 then
            hybridRollbackPrivate.clearTrackedSeatActor(occupantId, seatId)
            if hybridRollbackPrivate.clearSeatOfficialState(seatId) then changed = true end
          end
        else
          unknownSince[seatId] = nil
          if seatTakenCache[seatId] ~= true and writeSeatTaken(seatId, true) then changed = true end
        end
      elseif seatTakenCache[seatId] ~= true and writeSeatTaken(seatId, true) then
        changed = true
      end
    else
      local actualActor = runHealthCheck and hybridRollbackPrivate.findTrackedSeatActor(seatId, true) or nil
      local actualActorId = hybridRollbackPrivate.actorNetworkId(actualActor)
      if actualActorId > 0
        and hybridRollbackPrivate.isSeatEntryProcessed(actualActor, seatId) then
        unknownSince[seatId] = nil
        if writeSeatOccupantId(seatId, actualActorId) then
          writeSeatTaken(seatId, true)
          hybridRollbackPrivate.seatOfficialProofs()[seatId] = {
            actorId = actualActorId,
            expiresAt = Time.time + 2.0,
          }
          shadow[seatId] = nil
          changed = true
        end
      elseif claim ~= nil then
        unknownSince[seatId] = nil
        legacyPhysical[seatId] = nil
        savedScale.__seatTakenOnlySince = savedScale.__seatTakenOnlySince or {}
        savedScale.__seatTakenOnlySince[seatId] = nil
        if seatTakenCache[seatId] ~= true and writeSeatTaken(seatId, true) then changed = true end
      elseif runHealthCheck then
        local pendingActorId = 0
        if hybridRollbackPrivate.pendingSeatActorId ~= nil then
          pendingActorId = hybridRollbackPrivate.pendingSeatActorId(seatId)
        end
        local graceUntil = tonumber(migrationGrace[seatId]) or -math.huge
        local shouldScan = seatTakenCache[seatId] == true or legacyPhysical[seatId] ~= nil
          or pendingActorId > 0 or claimExpired or Time.time < graceUntil
        local physicalActor = nil
        local physicalState = "EMPTY"
        if shouldScan then
          physicalActor, physicalState = hybridRollbackPrivate.scanPhysicalSeatActor(seatId)
        end
        local physicalActorId = hybridRollbackPrivate.actorNetworkId(physicalActor)
        savedScale.__seatTakenOnlySince = savedScale.__seatTakenOnlySince or {}
        local stale = savedScale.__seatTakenOnlySince
        if physicalState == "FOUND" and physicalActorId > 0 then
          -- Old rooms may already contain a real native rider but never replay
          -- OnSeatEntered to this Lua instance. Protect that rider without
          -- backfilling the synchronized occupant ID from a blind scan.
          legacyPhysical[seatId] = { actorId = physicalActorId, seenAt = Time.time }
          unknownSince[seatId] = nil
          stale[seatId] = nil
          if seatTakenCache[seatId] ~= true and writeSeatTaken(seatId, true) then changed = true end
        elseif pendingActorId > 0 then
          unknownSince[seatId] = nil
          stale[seatId] = nil
          if seatTakenCache[seatId] ~= true and writeSeatTaken(seatId, true) then changed = true end
        elseif physicalState == "UNKNOWN" then
          stale[seatId] = nil
          local firstUnknownAt = tonumber(unknownSince[seatId])
          if firstUnknownAt == nil then
            unknownSince[seatId] = Time.time
          elseif Time.time - firstUnknownAt >= 3.0 and seatTakenCache[seatId] == true
            and Time.time >= (tonumber(migrationGrace[seatId]) or -math.huge) then
            if hybridRollbackPrivate.clearSeatOfficialState(seatId) then changed = true end
          end
        elseif legacyPhysical[seatId] ~= nil then
          unknownSince[seatId] = nil
          stale[seatId] = nil
          local lastSeenAt = tonumber(legacyPhysical[seatId].seenAt) or Time.time
          if Time.time - lastSeenAt >= 1.5 then
            legacyPhysical[seatId] = nil
            if hybridRollbackPrivate.clearSeatOfficialState(seatId) then changed = true end
          end
        elseif claimExpired then
          unknownSince[seatId] = nil
          stale[seatId] = nil
          if hybridRollbackPrivate.clearSeatOfficialState(seatId) then changed = true end
        elseif seatTakenCache[seatId] == true then
          unknownSince[seatId] = nil
          if Time.time >= graceUntil then
            local firstTakenOnlyAt = tonumber(stale[seatId])
            if firstTakenOnlyAt == nil then
              stale[seatId] = Time.time
            elseif Time.time - firstTakenOnlyAt >= 1.5 then
              if hybridRollbackPrivate.clearSeatOfficialState(seatId) then changed = true end
              stale[seatId] = nil
            end
          end
        else
          unknownSince[seatId] = nil
          legacyPhysical[seatId] = nil
          stale[seatId] = nil
        end
      end
    end
  end

  if runHealthCheck then hybridRollbackPrivate.cleanupInvalidTrackedActors() end
  if changed then refreshInteractionForState() end
end

function hybridRollbackPrivate.seatClearConfirmations()
  local confirmations = savedScale.__seatClearConfirmations
  if confirmations == nil then
    confirmations = {}
    savedScale.__seatClearConfirmations = confirmations
  end
  return confirmations
end

function hybridRollbackPrivate.markSeatClearTakenConfirmation(id, taken)
  local confirmation = hybridRollbackPrivate.seatClearConfirmations()[id]
  if confirmation ~= nil and taken ~= true then
    confirmation.takenCallbackConfirmed = true
    if VehicleWakeRaceResetFromSync ~= nil then VehicleWakeRaceResetFromSync(confirmation.cycleId) end
  end
end

function hybridRollbackPrivate.markSeatClearOccupantConfirmation(id, actorId)
  local confirmation = hybridRollbackPrivate.seatClearConfirmations()[id]
  if confirmation ~= nil and hybridRollbackPrivate.normalizeActorId(actorId) == 0 then
    confirmation.occupantCallbackConfirmed = true
    if VehicleWakeRaceResetFromSync ~= nil then VehicleWakeRaceResetFromSync(confirmation.cycleId) end
  end
end

local function forceClearSeat(id, cycleId)
  local normalizedCycleId = tonumber(cycleId)
  if normalizedCycleId == nil then return false end
  local confirmation = {
    cycleId = normalizedCycleId,
    requestedAt = Time.time,
    requestedFrame = Time.frameCount,
    takenCallbackConfirmed = false,
    takenReadConfirmed = false,
    occupantCallbackConfirmed = false,
    occupantReadConfirmed = false,
  }
  hybridRollbackPrivate.seatClearConfirmations()[id] = confirmation
  hybridRollbackPrivate.clearSeatClaim(id)
  hybridRollbackPrivate.seatOfficialProofs()[id] = nil

  if DouyinNetService == nil then
    seatOccupantIdCache[id] = 0
    seatTakenCache[id] = false
    confirmation.takenCallbackConfirmed = true
    confirmation.occupantCallbackConfirmed = true
    confirmation.offlineConfirmed = true
    return true
  end
  if not hybridRollbackPrivate.isSeatStateOwner() then return false end
  local occupantVariable = getSeatOccupantVar(id)
  local takenVariable = getSeatVar(id)
  if occupantVariable == nil or takenVariable == nil then return false end
  local occupantOk = pcall(function() occupantVariable:SetValue(0) end)
  if not occupantOk then return false end
  seatOccupantIdCache[id] = 0
  local takenOk = pcall(function() takenVariable:SetValue(false) end)
  if not takenOk then return false end
  seatTakenCache[id] = false
  return true
end

function VehicleAreAllSeatStatesCleared(cycleId)
  local normalizedCycleId = tonumber(cycleId)
  if normalizedCycleId == nil then return false end
  local confirmations = hybridRollbackPrivate.seatClearConfirmations()
  for index = 1, #seatConfigs do
    local id = seatConfigs[index].id
    local confirmation = confirmations[id]
    if confirmation == nil or confirmation.cycleId ~= normalizedCycleId then return false end
    if confirmation.offlineConfirmed ~= true then
      if Time.frameCount <= confirmation.requestedFrame or Time.time <= confirmation.requestedAt then return false end
      -- Callbacks only wake the transaction. Always read both synchronized
      -- fields after at least one frame so callback reordering cannot complete
      -- the reset from stale local caches.
      local takenVariable = getSeatVar(id)
      local occupantVariable = getSeatOccupantVar(id)
      if takenVariable == nil or occupantVariable == nil then return false end
      local takenOk, taken = pcall(function() return takenVariable:GetValue() == true end)
      local occupantOk, actorId = pcall(function() return occupantVariable:GetValue() end)
      if not takenOk or not occupantOk then return false end
      confirmation.takenReadConfirmed = taken ~= true
      confirmation.occupantReadConfirmed = hybridRollbackPrivate.normalizeActorId(actorId) == 0
      if not confirmation.takenReadConfirmed or not confirmation.occupantReadConfirmed then return false end
    end
    if seatTakenCache[id] == true or hybridRollbackPrivate.readSeatOccupantId(id) > 0 then return false end
  end
  return true
end

local function getSeatStationGameObject(id)
  local cfg = findSeatConfig(id)
  if cfg == nil then return nil end
  if cfg.canDrive then return self.gameObject end
  if cfg.stationTransform ~= nil then return cfg.stationTransform.gameObject end
  return nil
end

function hybridRollbackPrivate.showSeatOccupiedFeedback()
  hybridRollbackPrivate.seatFeedbackText = "座位占用中"
  hybridRollbackPrivate.seatFeedbackUntil = Time.time + 1.5
  if currentInside and localSeatId == nil then rebuildInteractionButtons() end
end

function hybridRollbackPrivate.preserveMigratedLocalDriverClaim()
  if not hybridRollbackPrivate.isSeatStateOwner() then return false end
  local temporary = savedScale.__localSeatClaim
  if type(temporary) ~= "table" or temporary.seatId ~= "driver"
    or temporary.claimed ~= true then return false end
  local actorId = hybridRollbackPrivate.normalizeActorId(temporary.actorId)
  local localId = hybridRollbackPrivate.actorNetworkId(localActor)
  local expiresAt = tonumber(temporary.expiresAt) or tonumber(seatReservationDeadline) or -math.huge
  if actorId == 0 or localId ~= actorId or Time.time >= expiresAt
    or (selectedSeatId ~= "driver" and localSeatId ~= "driver") then return false end
  if hybridRollbackPrivate.readSeatOccupantId("driver") > 0 then return false end
  hybridRollbackPrivate.setSeatClaim("driver", actorId, math.max(0.25, expiresAt - Time.time))
  writeSeatTaken("driver", true)
  hybridRollbackPrivate.seatMigrationGraceUntil().driver = nil
  return true
end

function hybridRollbackPrivate.seatRequestsAllowedForObservedReset()
  if hybridRollbackPrivate.readSynchronizedResetEpoch ~= nil then
    hybridRollbackPrivate.readSynchronizedResetEpoch()
  end
  if raceResetLocked then return false end
  local acceptedCycle = math.floor(tonumber(lastAcceptedRaceResetCycleId) or 0)
  if acceptedCycle <= 0 then return true end
  local cleanedCycle = math.floor(tonumber(savedScale.__raceResetLocalCleanupCycleId) or 0)
  if cleanedCycle >= acceptedCycle then return true end
  local completedCycle = math.max(
    math.floor(tonumber(lastCompletedRaceResetCycleId) or 0),
    math.floor(tonumber(savedScale.__raceResetObservedCompletedCycleId) or 0)
  )
  if completedCycle < acceptedCycle then
    local observedCycle = math.floor(tonumber(savedScale.__raceResetUnresolvedObservedCycleId) or 0)
    if observedCycle ~= acceptedCycle then
      savedScale.__raceResetUnresolvedObservedCycleId = acceptedCycle
      savedScale.__raceResetUnresolvedObservedAt = Time.time
      return false
    end
    local observedAt = tonumber(savedScale.__raceResetUnresolvedObservedAt) or Time.time
    if Time.time - observedAt < 5.25
      or hybridRollbackPrivate.applyExpiredObservedResetLocally == nil then return false end
    local ok, applied = pcall(function()
      return hybridRollbackPrivate.applyExpiredObservedResetLocally(acceptedCycle)
    end)
    return ok and applied == true
      and math.floor(tonumber(savedScale.__raceResetLocalCleanupCycleId) or 0) >= acceptedCycle
      and not raceResetLocked
  end
  if hybridRollbackPrivate.applyCompletedResetLocally == nil then return false end
  local ok, applied = pcall(function()
    return hybridRollbackPrivate.applyCompletedResetLocally(acceptedCycle)
  end)
  return ok and applied == true
    and math.floor(tonumber(savedScale.__raceResetLocalCleanupCycleId) or 0) >= acceptedCycle
    and not raceResetLocked
end

function VehicleClaimSeat(rawSeatId, rawActorId, rawResetCycleId)
  if hybridRollbackPrivate.readSynchronizedResetEpoch ~= nil then
    hybridRollbackPrivate.readSynchronizedResetEpoch()
  end
  if not hybridRollbackPrivate.seatRequestsAllowedForObservedReset() then return "DENY" end
  local seatId = tostring(rawSeatId or "")
  local cfg = findSeatConfig(seatId)
  local actorId = hybridRollbackPrivate.normalizeActorId(rawActorId)
  local requestResetCycleId = math.floor(tonumber(rawResetCycleId) or -1)
  if cfg == nil or actorId == 0 or raceResetLocked or raceCompetitionLocked
    or requestResetCycleId ~= lastAcceptedRaceResetCycleId then return "DENY" end
  if not hybridRollbackPrivate.isSeatStateOwner() then return "DENY" end

  if DouyinNetService ~= nil then
    local requester, lookup = hybridRollbackPrivate.findRoomActor(actorId)
    if lookup ~= "FOUND" or requester == nil then return "DENY" end
  end

  local occupantId = hybridRollbackPrivate.readSeatOccupantId(seatId)
  if occupantId > 0 then
    local health = hybridRollbackPrivate.seatActorHealth(seatId, occupantId)
    if health == "INVALID" then
      hybridRollbackPrivate.clearTrackedSeatActor(occupantId, seatId)
      if not hybridRollbackPrivate.clearSeatOfficialState(seatId) then return "DENY" end
    else
      return "TAKEN"
    end
  end

  local actualActor = hybridRollbackPrivate.findTrackedSeatActor(seatId, true)
  local actualActorId = hybridRollbackPrivate.actorNetworkId(actualActor)
  if actualActorId > 0
    and hybridRollbackPrivate.isSeatEntryProcessed(actualActor, seatId) then
    if writeSeatOccupantId(seatId, actualActorId) then
      writeSeatTaken(seatId, true)
      hybridRollbackPrivate.seatOfficialProofs()[seatId] = {
        actorId = actualActorId,
        expiresAt = Time.time + 2.0,
      }
    end
    return "TAKEN"
  end

  local physicalActor, physicalState = hybridRollbackPrivate.scanPhysicalSeatActor(seatId)
  local physicalActorId = hybridRollbackPrivate.actorNetworkId(physicalActor)
  if physicalState == "FOUND" and physicalActorId > 0 then
    hybridRollbackPrivate.seatUnknownSince()[seatId] = nil
    hybridRollbackPrivate.legacyPhysicalSeats()[seatId] = {
      actorId = physicalActorId,
      seenAt = Time.time,
    }
    writeSeatTaken(seatId, true)
    return "TAKEN"
  end

  local pendingActorId = 0
  if hybridRollbackPrivate.pendingSeatActorId ~= nil then
    pendingActorId = hybridRollbackPrivate.pendingSeatActorId(seatId)
  end
  if pendingActorId > 0 then
    hybridRollbackPrivate.seatUnknownSince()[seatId] = nil
    writeSeatTaken(seatId, true)
    return "TAKEN"
  end

  if seatId == "driver" then hybridRollbackPrivate.preserveMigratedLocalDriverClaim() end
  local activeClaim = hybridRollbackPrivate.activeSeatClaim(seatId)
  if activeClaim ~= nil and DouyinNetService ~= nil then
    local _, claimantLookup = hybridRollbackPrivate.findRoomActor(activeClaim.actorId)
    if claimantLookup == "INVALID" then
      hybridRollbackPrivate.clearSeatClaim(seatId)
      hybridRollbackPrivate.seatMigrationGraceUntil()[seatId] = nil
      activeClaim = nil
    end
  end
  if activeClaim ~= nil then
    if activeClaim.actorId == actorId then
      -- This is Owner-local pending state, not a synchronized lease. Refreshing
      -- it prevents a legitimate same-Actor retry from expiring mid-SitDown.
      activeClaim.expiresAt = math.max(tonumber(activeClaim.expiresAt) or 0, Time.time + 5.0)
      return "OK"
    end
    return "TAKEN"
  end

  local physicalUnknownExpired = false
  if physicalState == "UNKNOWN" and DouyinNetService ~= nil then
    local firstUnknownAt = tonumber(hybridRollbackPrivate.seatUnknownSince()[seatId])
    if firstUnknownAt == nil then
      hybridRollbackPrivate.seatUnknownSince()[seatId] = Time.time
    else
      physicalUnknownExpired = Time.time - firstUnknownAt >= 3.0
    end
  else
    hybridRollbackPrivate.seatUnknownSince()[seatId] = nil
  end
  if seatTakenCache[seatId] == true then
    if physicalState == "UNKNOWN" and DouyinNetService ~= nil
      and not physicalUnknownExpired then return "TAKEN" end
    -- No synchronized request token is retained across Owner migration. If no
    -- real rider, pending OnSeatEntered, or active Owner-local claim exists,
    -- the first request reaching the new Owner wins and replaces Taken-only.
    if not hybridRollbackPrivate.clearSeatOfficialState(seatId) then return "DENY" end
  elseif physicalState == "UNKNOWN" and DouyinNetService ~= nil
    and not physicalUnknownExpired then
    return "DENY"
  end
  hybridRollbackPrivate.setSeatClaim(seatId, actorId, 5.0)
  if not writeSeatTaken(seatId, true) then
    hybridRollbackPrivate.clearSeatClaim(seatId)
    return "DENY"
  end
  refreshInteractionForState()
  return "OK"
end

function VehicleCommitSeatOccupant(rawSeatId, rawActorId, rawResetCycleId)
  if hybridRollbackPrivate.readSynchronizedResetEpoch ~= nil then
    hybridRollbackPrivate.readSynchronizedResetEpoch()
  end
  if not hybridRollbackPrivate.seatRequestsAllowedForObservedReset() then return "DENY" end
  local seatId = tostring(rawSeatId or "")
  local cfg = findSeatConfig(seatId)
  local actorId = hybridRollbackPrivate.normalizeActorId(rawActorId)
  local requestResetCycleId = math.floor(tonumber(rawResetCycleId) or -1)
  if cfg == nil or actorId == 0 or raceResetLocked or raceCompetitionLocked
    or requestResetCycleId ~= lastAcceptedRaceResetCycleId then return "DENY" end
  if not hybridRollbackPrivate.isSeatStateOwner() then return "RETRY" end

  local occupantId = hybridRollbackPrivate.readSeatOccupantId(seatId)
  if occupantId == actorId then
    local health, actor = hybridRollbackPrivate.seatActorHealth(seatId, actorId)
    local relation = actor ~= nil
      and hybridRollbackPrivate.actorSeatRelation(actor, seatId) or "UNKNOWN"
    local trackedActor, trackedSeatId = hybridRollbackPrivate.trackedSeatForActorId(actorId)
    local enteredHere = trackedSeatId == seatId and trackedActor ~= nil
      and hybridRollbackPrivate.isSeatEntryProcessed(trackedActor, seatId)
    if health == "INVALID" then
      hybridRollbackPrivate.clearTrackedSeatActor(actorId, seatId)
      hybridRollbackPrivate.clearSeatOfficialState(seatId)
      return "DENY"
    end
    if enteredHere or (health == "VALID" and relation == "TARGET") then
      hybridRollbackPrivate.clearSeatClaim(seatId)
      writeSeatTaken(seatId, true)
      return "OK"
    end
    return "RETRY"
  end
  if occupantId > 0 then
    local health = hybridRollbackPrivate.seatActorHealth(seatId, occupantId)
    if health ~= "INVALID" then return "TAKEN" end
    hybridRollbackPrivate.clearTrackedSeatActor(occupantId, seatId)
    if not hybridRollbackPrivate.clearSeatOfficialState(seatId) then return "RETRY" end
  end

  local actor = nil
  if DouyinNetService ~= nil then
    local lookup = nil
    actor, lookup = hybridRollbackPrivate.findRoomActor(actorId)
    if lookup == "UNKNOWN" then return "RETRY" end
    if lookup ~= "FOUND" or actor == nil then return "DENY" end
    local sittingOk, sitting = pcall(function() return actor:IsSitting() end)
    if not sittingOk or sitting ~= true then return "RETRY" end
  end

  local claim = hybridRollbackPrivate.activeSeatClaim(seatId)
  if claim ~= nil and claim.actorId ~= actorId then return "TAKEN" end
  local trackedActor, trackedSeatId = hybridRollbackPrivate.trackedSeatForActorId(actorId)
  if trackedSeatId ~= nil and trackedSeatId ~= seatId then return "DENY" end
  local enteredHere = trackedSeatId == seatId and trackedActor ~= nil
    and hybridRollbackPrivate.isSeatEntryProcessed(trackedActor, seatId)
  -- Both accepted proofs originate from this vehicle's real OnSeatEntered:
  -- either the event was already processed into the ledger, or it is queued
  -- pending synchronization. A blind parent/IsSitting scan never writes ID.
  local pendingEntered = hybridRollbackPrivate.hasPendingSeatEntry ~= nil
    and hybridRollbackPrivate.hasPendingSeatEntry(actorId, seatId)
  if actor ~= nil and not enteredHere and not pendingEntered then
    local parentOk, parent = pcall(function() return actor.gameObject.transform.parent end)
    if parentOk and parent ~= nil then
      for index = 1, #seatConfigs do
        local other = seatConfigs[index]
        if other.id ~= seatId and ((other.transform ~= nil and parent == other.transform)
          or (other.stationTransform ~= nil and parent == other.stationTransform)) then
          return "DENY"
        end
      end
      return "RETRY"
    end
  end
  if not enteredHere and not pendingEntered then return "RETRY" end

  if not writeSeatOccupantId(seatId, actorId) then return "RETRY" end
  writeSeatTaken(seatId, true)
  hybridRollbackPrivate.clearSeatClaim(seatId)
  hybridRollbackPrivate.seatOfficialProofs()[seatId] = {
    actorId = actorId,
    expiresAt = Time.time + 2.0,
  }
  hybridRollbackPrivate.seatUnknownSince()[seatId] = nil
  refreshInteractionForState()
  return "OK"
end

function VehicleCancelSeatClaim(rawSeatId, rawActorId, rawResetCycleId)
  if hybridRollbackPrivate.readSynchronizedResetEpoch ~= nil then
    hybridRollbackPrivate.readSynchronizedResetEpoch()
  end
  local seatId = tostring(rawSeatId or "")
  local actorId = hybridRollbackPrivate.normalizeActorId(rawActorId)
  local requestResetCycleId = math.floor(tonumber(rawResetCycleId) or -1)
  if findSeatConfig(seatId) == nil or actorId == 0
    or requestResetCycleId ~= lastAcceptedRaceResetCycleId then return false end
  if not hybridRollbackPrivate.isSeatStateOwner() then return false end
  local rawClaim = hybridRollbackPrivate.seatClaimShadow()[seatId]
  local localClaim = savedScale.__localSeatClaim
  local matchingMigratedLocalClaim = type(localClaim) == "table"
    and localClaim.seatId == seatId
    and hybridRollbackPrivate.normalizeActorId(localClaim.actorId) == actorId
  if type(rawClaim) == "table" then
    if rawClaim.actorId ~= actorId then return false end
  elseif not matchingMigratedLocalClaim then
    return false
  end
  hybridRollbackPrivate.clearSeatClaim(seatId)
  if hybridRollbackPrivate.readSeatOccupantId(seatId) == 0 then
    writeSeatTaken(seatId, false)
    refreshInteractionForState()
  end
  return true
end

function VehicleReleaseSeatActor(rawSeatId, rawActorId)
  local seatId = tostring(rawSeatId or "")
  local actorId = hybridRollbackPrivate.normalizeActorId(rawActorId)
  if findSeatConfig(seatId) == nil or actorId == 0 then return false end
  if not hybridRollbackPrivate.isSeatStateOwner() then return false end
  if hybridRollbackPrivate.readSeatOccupantId(seatId) ~= actorId then return false end
  local activeClaim = hybridRollbackPrivate.activeSeatClaim(seatId)
  if type(activeClaim) == "table" and activeClaim.actorId == actorId then return false end
  if hybridRollbackPrivate.pendingSeatActorId ~= nil
    and hybridRollbackPrivate.pendingSeatActorId(seatId) == actorId then return false end
  local health = hybridRollbackPrivate.seatActorHealth(seatId, actorId)
  if health ~= "INVALID" then return false end
  hybridRollbackPrivate.clearTrackedSeatActor(actorId, seatId)
  local cleared = hybridRollbackPrivate.clearSeatOfficialState(seatId)
  if cleared then refreshInteractionForState() end
  return cleared
end

local function requestSeatClaimCancel(seatId, rawActorId)
  local actorId = hybridRollbackPrivate.normalizeActorId(rawActorId)
  if seatId == nil or actorId == 0 then return false end
  -- Reset performs authoritative all-seat cleanup.
  if raceResetLocked then return true end
  local requestResetCycleId = lastAcceptedRaceResetCycleId
  if DouyinNetService == nil then
    return VehicleCancelSeatClaim(seatId, actorId, requestResetCycleId)
  end
  if not DouyinNetService.isNetworkSettled or not netSpawned then return false end
  local owner = false
  pcall(function() owner = self:HasOwnership() end)
  if owner then return VehicleCancelSeatClaim(seatId, actorId, requestResetCycleId) end
  -- The SDK has no RPC cancellation, compare-and-swap, or delivery deadline.
  -- Sending Actor-ID-only cancel to a remote Owner can arrive after the same
  -- Actor has retried and erase that newer claim. Without a seat attempt nonce
  -- the safe policy is: clear local pending/UI now, let this Owner-local claim
  -- expire within five seconds, and allow the same Actor to retry immediately.
  return false
end

local function requestSeatRelease(seatId, rawActorId)
  local actorId = hybridRollbackPrivate.normalizeActorId(rawActorId)
  if seatId == nil or actorId == 0 then return false end
  if DouyinNetService == nil then return VehicleReleaseSeatActor(seatId, actorId) end
  if not DouyinNetService.isNetworkSettled or not netSpawned then return false end
  local owner = false
  pcall(function() owner = self:HasOwnership() end)
  if owner then return VehicleReleaseSeatActor(seatId, actorId) end
  return pcall(function()
    self:OwnerCall("VehicleReleaseSeatActor", function() end, seatId, actorId)
  end)
end

function hybridRollbackPrivate.clearLocalReservationCache()
  local temporary = savedScale.__localSeatClaim
  if temporary == nil then return end
  requestSeatClaimCancel(temporary.seatId, temporary.actorId)
  savedScale.__localSeatClaim = nil
  if hybridRollbackPrivate.readSeatOccupantId(temporary.seatId) == 0 then
    local synchronizedTaken = false
    if DouyinNetService ~= nil and netSpawned then
      local variable = getSeatVar(temporary.seatId)
      if variable ~= nil then
        local ok, value = pcall(function() return variable:GetValue() end)
        if ok then synchronizedTaken = value == true end
      end
    end
    seatTakenCache[temporary.seatId] = synchronizedTaken
      or hybridRollbackPrivate.activeSeatClaim(temporary.seatId) ~= nil
  end
end

local function clearPendingSeatSelection()
  seatReservationPending = false
  seatReservationDeadline = -math.huge
  ownershipPending = false
  ownershipPendingDeadline = -math.huge
  savedScale.__seatWaitingForNetwork = false
  savedScale.__driverWaitingForNetwork = false
  if localSeatId == nil then
    hybridRollbackPrivate.clearLocalReservationCache()
    selectedSeatId = nil
    selectedSeatAnchor = nil
    selectedSeatIndex = -1
    localSeatActorId = nil
  end
end

function hybridRollbackPrivate.processedSeatEntryLedger()
  local ledger = savedScale.__processedSeatEntries
  if ledger == nil then
    ledger = {}
    savedScale.__processedSeatEntries = ledger
  end
  return ledger
end

function hybridRollbackPrivate.isSeatEntryProcessed(actor, seatId)
  if actor == nil then return false end
  local ledger = hybridRollbackPrivate.processedSeatEntryLedger()
  if ledger[actor] == seatId then return true end
  local actorId = hybridRollbackPrivate.actorNetworkId(actor)
  if actorId == 0 then return false end
  for trackedActor, trackedSeatId in pairs(ledger) do
    if trackedSeatId == seatId
      and hybridRollbackPrivate.actorNetworkId(trackedActor) == actorId then return true end
  end
  return false
end

function hybridRollbackPrivate.markSeatEntryProcessed(actor, seatId)
  if actor ~= nil then hybridRollbackPrivate.processedSeatEntryLedger()[actor] = seatId end
end

function hybridRollbackPrivate.clearProcessedSeatEntry(actor)
  if actor ~= nil then hybridRollbackPrivate.processedSeatEntryLedger()[actor] = nil end
end

local function pendingSeatEntries()
  local entries = savedScale.__pendingSeatEntryCallbacks
  if entries == nil then
    entries = {}
    savedScale.__pendingSeatEntryCallbacks = entries
  end
  return entries
end

function hybridRollbackPrivate.hasPendingSeatEntry(rawActorId, seatId)
  local actorId = hybridRollbackPrivate.normalizeActorId(rawActorId)
  if actorId == 0 then return false end
  local entries = pendingSeatEntries()
  for index = 1, #entries do
    local entry = entries[index]
    if entry.seatId == seatId then
      local entryActorId = hybridRollbackPrivate.normalizeActorId(entry.actorId)
      if entryActorId == 0 then entryActorId = hybridRollbackPrivate.actorNetworkId(entry.actor) end
      if entryActorId == actorId and entry.aborting ~= true then
        local stateOk, sitting = pcall(function() return entry.actor:IsSitting() end)
        local relation = hybridRollbackPrivate.actorSeatRelation(entry.actor, seatId)
        local parentOk, parent = pcall(function() return entry.actor.gameObject.transform.parent end)
        local unparented = relation == "UNKNOWN" and parentOk and parent == nil
        -- Pending OnSeatEntered is official commit proof only while the Actor
        -- is verifiably sitting for this callback. Visual parent repair is
        -- independent, so parent=nil is allowed but external parents are not.
        if stateOk and sitting == true
          and (relation == "TARGET" or unparented) then return true end
      end
    end
  end
  return false
end

local function removePendingSeatEntriesForActor(actor, rawSeatId)
  local seatId = tostring(rawSeatId or "")
  local entries = pendingSeatEntries()
  local removed = false
  for i = #entries, 1, -1 do
    local entry = entries[i]
    if entry.actor == actor and (seatId == "" or entry.seatId == seatId) then
      removePendingRemoteSeat(entry.seatId)
      table.remove(entries, i)
      removed = true
    end
  end
  return removed
end

local function beginPendingSeatAbort(entry, rawDeadlineAt)
  if entry == nil or entry.actor == nil then return end
  if entry.aborting ~= true then
    entry.aborting = true
    entry.abortStartedAt = Time.time
    entry.abortDeadlineAt = Time.time + 5.0
    entry.nextStandUpAt = Time.time
    entry.standUpAttempts = 0
  end
  local deadlineAt = tonumber(rawDeadlineAt)
  if deadlineAt ~= nil then entry.abortDeadlineAt = math.min(entry.abortDeadlineAt, deadlineAt) end
  -- The actor was never committed to the Lua seat ledger. Restore collision as
  -- soon as the pending callback is cancelled, while native IsSitting remains
  -- part of the reset movement guard.
  local stateOk, sitting = pcall(function() return entry.actor:IsSitting() end)
  local relation = hybridRollbackPrivate.actorSeatRelation(entry.actor, entry.seatId)
  local parentOk, parent = pcall(function() return entry.actor.gameObject.transform.parent end)
  if stateOk and sitting ~= true
    and (relation == "TARGET" or (parentOk and parent == nil)) then
    setActorColliderEnabled(entry.actor, true)
  end
end

local function updatePendingSeatAbort(entry)
  if entry == nil or entry.actor == nil then return true end
  local actorId = hybridRollbackPrivate.normalizeActorId(entry.actorId)
  if actorId == 0 then actorId = hybridRollbackPrivate.actorNetworkId(entry.actor) end
  local roomActor, lookup = hybridRollbackPrivate.findRoomActor(actorId)
  if DouyinNetService ~= nil and lookup == "INVALID" then return true end
  if roomActor ~= nil then entry.actor = roomActor end
  local stateOk, stillSitting = pcall(function() return entry.actor:IsSitting() end)
  local relation = hybridRollbackPrivate.actorSeatRelation(entry.actor, entry.seatId)
  local parentOk, parent = pcall(function() return entry.actor.gameObject.transform.parent end)
  if relation == "OTHER" or relation == "THIS_VEHICLE"
    or (relation == "UNKNOWN" and parentOk and parent ~= nil) then return true end
  if stateOk and stillSitting ~= true then
    if relation == "TARGET" or (parentOk and parent == nil) then
      setActorColliderEnabled(entry.actor, true)
    end
    return true
  end
  local deadlineAt = tonumber(entry.abortDeadlineAt) or (Time.time + 5.0)
  if Time.time >= deadlineAt then
    -- StandUp is local-only. A remote pending callback must not block reset
    -- forever; the Owner clears synchronized occupancy independently.
    return true
  end
  local attempts = tonumber(entry.standUpAttempts) or 0
  local localOk, isLocalActor = pcall(function() return entry.actor.isLocal end)
  if localOk and isLocalActor == true and relation == "TARGET" and attempts < 6
    and Time.time >= (tonumber(entry.nextStandUpAt) or Time.time) then
    local stationObject = getSeatStationGameObject(entry.seatId)
    if stationObject ~= nil then pcall(function() entry.actor:StandUp(stationObject) end) end
    entry.standUpAttempts = attempts + 1
    entry.nextStandUpAt = math.min(deadlineAt, Time.time + 0.5)
  end
  return false
end

function VehicleAbortAllPendingSeatEntries(rawDeadlineAt)
  local entries = pendingSeatEntries()
  for i = 1, #entries do beginPendingSeatAbort(entries[i], rawDeadlineAt) end
end

local function queuePendingSeatEntry(actor, seatId, handType, allowLocalSitStateDelay)
  if actor == nil or hybridRollbackPrivate.isSeatEntryProcessed(actor, seatId) then return end
  local entries = pendingSeatEntries()
  for i = 1, #entries do
    local entry = entries[i]
    if entry.actor == actor and entry.seatId == seatId then
      if allowLocalSitStateDelay == true then
        entry.allowLocalSitStateDelay = true
        entry.sitStateDeadlineAt = math.max(
          tonumber(entry.sitStateDeadlineAt) or -math.huge,
          Time.time + 1.0
        )
      end
      return
    end
  end
  enqueuePendingRemoteSeat(seatId)
  entries[#entries + 1] = {
    actor = actor,
    seatId = seatId,
    handType = handType,
    actorId = hybridRollbackPrivate.actorNetworkId(actor),
    waitDeadlineAt = Time.time + 5.0,
    allowLocalSitStateDelay = allowLocalSitStateDelay == true,
    sitStateDeadlineAt = allowLocalSitStateDelay == true and Time.time + 1.0 or nil,
    aborting = false,
  }
end

local function abortPendingSeatActor(actor, seatId, handType, deadlineAt)
  queuePendingSeatEntry(actor, seatId, handType)
  local entries = pendingSeatEntries()
  for i = 1, #entries do
    local entry = entries[i]
    if entry.actor == actor and entry.seatId == seatId then
      beginPendingSeatAbort(entry, deadlineAt)
      updatePendingSeatAbort(entry)
      return
    end
  end
  setActorColliderEnabled(actor, true)
end

function hybridRollbackPrivate.pendingSeatActorId(seatId)
  local entries = pendingSeatEntries()
  for index = 1, #entries do
    local entry = entries[index]
    if entry.seatId == seatId and entry.aborting ~= true then
      local actorId = hybridRollbackPrivate.normalizeActorId(entry.actorId)
      if actorId == 0 then actorId = hybridRollbackPrivate.actorNetworkId(entry.actor) end
      if actorId > 0 then
        local stateOk, sitting = pcall(function() return entry.actor:IsSitting() end)
        local relation = hybridRollbackPrivate.actorSeatRelation(entry.actor, seatId)
        local parentOk, parent = pcall(function() return entry.actor.gameObject.transform.parent end)
        local unparented = relation == "UNKNOWN" and parentOk and parent == nil
        if not stateOk or (sitting == true
          and (relation == "TARGET" or unparented)) then return actorId end
      end
    end
  end
  return 0
end

function VehicleReplayPendingSeatEntries()
  local entries = pendingSeatEntries()
  for index = #entries, 1, -1 do
    local entry = entries[index]
    if entry.aborting == true then
      if updatePendingSeatAbort(entry) then
        table.remove(entries, index)
        removePendingRemoteSeat(entry.seatId)
      end
    else
      local actorId = hybridRollbackPrivate.normalizeActorId(entry.actorId)
      if actorId == 0 then actorId = hybridRollbackPrivate.actorNetworkId(entry.actor) end
      local roomActor, lookup = hybridRollbackPrivate.findRoomActor(actorId)
      if DouyinNetService ~= nil and lookup == "INVALID" then
        setActorColliderEnabled(entry.actor, true)
        table.remove(entries, index)
        removePendingRemoteSeat(entry.seatId)
      else
        if roomActor ~= nil then entry.actor = roomActor end
        local stateOk, sitting = pcall(function() return entry.actor:IsSitting() end)
        local relation = hybridRollbackPrivate.actorSeatRelation(entry.actor, entry.seatId)
        local parentOk, parent = pcall(function() return entry.actor.gameObject.transform.parent end)
        local localSitStateDelay = entry.allowLocalSitStateDelay == true
        local priorSeat = hybridRollbackPrivate.processedSeatEntryLedger()[entry.actor]
        if priorSeat == nil then
          local _, trackedPriorSeat = hybridRollbackPrivate.trackedSeatForActorId(actorId)
          priorSeat = trackedPriorSeat
        end
        local currentLocalAttempt = localSitStateDelay
          and hybridRollbackPrivate.isCurrentLocalSeatAttempt(
            entry.actor, entry.seatId, actorId, savedScale.__localSeatClaim, priorSeat
          )
        local safeLocalRelation = relation == "TARGET"
          or (relation == "UNKNOWN" and parentOk and parent == nil)
        local waitingForLocalSitState = currentLocalAttempt and safeLocalRelation
          and (not stateOk or sitting ~= true)
          and Time.time < (tonumber(entry.sitStateDeadlineAt) or -math.huge)
        if relation == "OTHER" or relation == "THIS_VEHICLE"
          or (relation == "UNKNOWN" and parentOk and parent ~= nil) then
          table.remove(entries, index)
          removePendingRemoteSeat(entry.seatId)
          if localSitStateDelay then
            hybridRollbackPrivate.beginLocalSitRollback("SIT_STATE_MOVED")
          end
        elseif waitingForLocalSitState then
          -- A valid local OnSeatEntered may precede IsSitting by one native
          -- update. Keep its exact claim alive briefly, then replay this same
          -- callback after the native state becomes observable.
        elseif localSitStateDelay and (not stateOk or sitting ~= true) then
          table.remove(entries, index)
          removePendingRemoteSeat(entry.seatId)
          hybridRollbackPrivate.beginLocalSitRollback("SIT_STATE_TIMEOUT")
        elseif stateOk and sitting ~= true then
          if relation == "TARGET" or (parentOk and parent == nil) then
            setActorColliderEnabled(entry.actor, true)
          end
          table.remove(entries, index)
          removePendingRemoteSeat(entry.seatId)
        elseif localSitStateDelay and (not currentLocalAttempt or not safeLocalRelation) then
          table.remove(entries, index)
          removePendingRemoteSeat(entry.seatId)
          hybridRollbackPrivate.beginLocalSitRollback("SIT_STATE_INVALID")
        else
          local occupantId = hybridRollbackPrivate.readSeatOccupantId(entry.seatId)
          local localReady = localSitStateDelay and currentLocalAttempt
            and safeLocalRelation and occupantId == 0
          if actorId > 0 and not raceResetLocked
            and (occupantId == actorId or localReady) then
            table.remove(entries, index)
            removePendingRemoteSeat(entry.seatId)
            VehicleSeatStationEntered(entry.actor, entry.seatId, entry.handType)
          elseif occupantId > 0 and occupantId ~= actorId then
            beginPendingSeatAbort(entry, Time.time + 0.5)
            updatePendingSeatAbort(entry)
          elseif raceResetLocked or Time.time >= entry.waitDeadlineAt then
            local resetDeadline = raceResetLocked and savedScale.__raceResetDeadlineAt or nil
            beginPendingSeatAbort(entry, resetDeadline)
            updatePendingSeatAbort(entry)
          end
        end
      end
    end
  end
end

local function applySeatOccupantId(id, rawActorId)
  local actorId = hybridRollbackPrivate.normalizeActorId(rawActorId)
  hybridRollbackPrivate.markSeatClearOccupantConfirmation(id, actorId)
  local old = hybridRollbackPrivate.normalizeActorId(seatOccupantIdCache[id])
  seatOccupantIdCache[id] = actorId
  local synchronizedTaken = seatTakenCache[id] == true
  if DouyinNetService ~= nil and netSpawned then
    local takenVariable = getSeatVar(id)
    if takenVariable ~= nil then
      local ok, value = pcall(function() return takenVariable:GetValue() end)
      if ok then synchronizedTaken = value == true end
    end
  end
  local claim = hybridRollbackPrivate.activeSeatClaim(id)
  local temporary = savedScale.__localSeatClaim
  local requesterPending = type(temporary) == "table" and temporary.seatId == id
    and hybridRollbackPrivate.normalizeActorId(temporary.actorId) > 0
    and (seatReservationPending or localSeatId == id)
  local effectiveTaken = actorId > 0 or synchronizedTaken or claim ~= nil or requesterPending
  local takenChanged = (seatTakenCache[id] == true) ~= effectiveTaken
  seatTakenCache[id] = effectiveTaken
  if old ~= actorId or takenChanged then refreshInteractionForState() else updateEmptyTimer() end
  VehicleReplayPendingSeatEntries()
end

local function applySeatTaken(id, taken, preVal)
  hybridRollbackPrivate.markSeatClearTakenConfirmation(id, taken)
  local old = seatTakenCache[id] == true
  local occupantPresent = hybridRollbackPrivate.readSeatOccupantId(id) > 0
  local activeClaim = hybridRollbackPrivate.activeSeatClaim(id)
  local temporary = savedScale.__localSeatClaim
  local requesterClaimPending = type(temporary) == "table" and temporary.seatId == id
    and hybridRollbackPrivate.normalizeActorId(temporary.actorId) > 0
    and (seatReservationPending or localSeatId == id)
  local effectiveTaken = taken == true or occupantPresent or activeClaim ~= nil or requesterClaimPending
  seatTakenCache[id] = effectiveTaken
  if not effectiveTaken then removePendingRemoteSeat(id) end
  if old ~= effectiveTaken then refreshInteractionForState() else updateEmptyTimer() end
  VehicleReplayPendingSeatEntries()
end

function hybridRollbackPrivate.refreshSeatSyncCache(force)
  if force ~= true then
    local nextAt = tonumber(savedScale.__seatSyncRefreshAt) or -math.huge
    if Time.time < nextAt then return end
savedScale.__seatSyncRefreshAt = hybridRollbackPrivate.nextMaintenanceAt(1.0)
  end
  local changed = false
  for index = 1, #seatConfigs do
    local id = seatConfigs[index].id
    local actorId = hybridRollbackPrivate.normalizeActorId(seatOccupantIdCache[id])
    local synchronizedTaken = seatTakenCache[id] == true
    if DouyinNetService ~= nil and netSpawned then
      local occupantVariable = getSeatOccupantVar(id)
      local takenVariable = getSeatVar(id)
      if occupantVariable ~= nil then
        local ok, value = pcall(function() return occupantVariable:GetValue() end)
        if ok then actorId = hybridRollbackPrivate.normalizeActorId(value) end
      end
      if takenVariable ~= nil then
        local ok, value = pcall(function() return takenVariable:GetValue() end)
        if ok then synchronizedTaken = value == true end
      end
    end
    local claim = hybridRollbackPrivate.activeSeatClaim(id)
    local temporary = savedScale.__localSeatClaim
    local requesterPending = type(temporary) == "table" and temporary.seatId == id
      and hybridRollbackPrivate.normalizeActorId(temporary.actorId) > 0
      and (seatReservationPending or localSeatId == id)
    local effectiveTaken = actorId > 0 or synchronizedTaken or claim ~= nil or requesterPending
    if hybridRollbackPrivate.normalizeActorId(seatOccupantIdCache[id]) ~= actorId
      or (seatTakenCache[id] == true) ~= effectiveTaken then changed = true end
    seatOccupantIdCache[id] = actorId
    seatTakenCache[id] = effectiveTaken
  end
  hybridRollbackPrivate.cleanupInvalidTrackedActors()
  if changed then refreshInteractionForState() else updateEmptyTimer() end
  VehicleReplayPendingSeatEntries()
end

local function setupSeatVarSync()
  for index = 1, #seatConfigs do
    local synchronizedSeatId = seatConfigs[index].id
    local takenVariable = getSeatVar(synchronizedSeatId)
    local occupantVariable = getSeatOccupantVar(synchronizedSeatId)
    if takenVariable ~= nil then
      takenVariable:OnValueChange(function(curVal, preVal)
        applySeatTaken(synchronizedSeatId, curVal == true, preVal)
      end)
    end
    if occupantVariable ~= nil then
      occupantVariable:OnValueChange(function(curVal)
        applySeatOccupantId(synchronizedSeatId, curVal)
      end)
    end
  end
  raceResetPhysicalClaimCycleId:OnValueChange(function(curVal)
    local numeric = math.floor(tonumber(curVal) or 0)
    local accepted = hybridRollbackPrivate.adoptSynchronizedResetEpoch ~= nil
      and hybridRollbackPrivate.adoptSynchronizedResetEpoch(numeric)
    if accepted then
      savedScale.__raceResetPhysicalClaimConfirmedCycleId = math.max(
        tonumber(savedScale.__raceResetPhysicalClaimConfirmedCycleId) or 0,
        numeric
      )
      if VehicleWakeRaceResetFromSync ~= nil then VehicleWakeRaceResetFromSync(numeric) end
    end
  end)
  raceResetPhysicalDoneCycleId:OnValueChange(function(curVal)
    local numeric = math.floor(tonumber(curVal) or 0)
    if numeric > 0 then
      savedScale.__raceResetPhysicalDoneConfirmedCycleId = math.max(
        tonumber(savedScale.__raceResetPhysicalDoneConfirmedCycleId) or 0,
        numeric
      )
      if VehicleWakeRaceResetFromSync ~= nil then VehicleWakeRaceResetFromSync(numeric) end
    end
  end)
  raceResetCompletedCycleId:OnValueChange(function(curVal)
    if hybridRollbackPrivate.adoptSynchronizedCompletedReset ~= nil then
      hybridRollbackPrivate.adoptSynchronizedCompletedReset(curVal)
    end
  end)

  for index = 1, #seatConfigs do
    local synchronizedSeatId = seatConfigs[index].id
    local occupantVariable = getSeatOccupantVar(synchronizedSeatId)
    local takenVariable = getSeatVar(synchronizedSeatId)
    if occupantVariable ~= nil then applySeatOccupantId(synchronizedSeatId, occupantVariable:GetValue()) end
    if takenVariable ~= nil then applySeatTaken(synchronizedSeatId, takenVariable:GetValue() == true, nil) end
  end
  local initialClaim = 0
  local initialDone = 0
  pcall(function() initialClaim = math.floor(tonumber(raceResetPhysicalClaimCycleId:GetValue()) or 0) end)
  pcall(function() initialDone = math.floor(tonumber(raceResetPhysicalDoneCycleId:GetValue()) or 0) end)
  if hybridRollbackPrivate.adoptSynchronizedCompletedReset ~= nil then
    local ok, completed = pcall(function() return raceResetCompletedCycleId:GetValue() end)
    if ok then hybridRollbackPrivate.adoptSynchronizedCompletedReset(completed) end
  end
  if hybridRollbackPrivate.adoptSynchronizedResetEpoch ~= nil
    and hybridRollbackPrivate.adoptSynchronizedResetEpoch(initialClaim) then
    savedScale.__raceResetPhysicalClaimConfirmedCycleId = initialClaim
  end
  if initialDone > 0 then savedScale.__raceResetPhysicalDoneConfirmedCycleId = initialDone end
end

function resolveSeatTrans()
  if selectedSeatAnchor ~= nil then return selectedSeatAnchor end
  return nil
end

local function resolveEnteringSeat(actor)
  local seatId = nil
  if actor ~= nil and actor.isLocal then
    seatId = selectedSeatId
  else
    seatId = popPendingRemoteSeat()
  end
  local cfg, idx = findSeatConfig(seatId)
  if cfg == nil then return nil, nil, -1 end
  return cfg.transform, seatId, idx
end

setActorColliderEnabled = function(actor, enabled)
  if actor == nil then return false end
  return pcall(function()
    local gameObject = actor.gameObject
    if gameObject == nil then return end
    local collider = gameObject:GetComponent(typeof(UnityEngine.Collider))
    if collider ~= nil then collider.enabled = enabled == true end
  end)
end

local function safeScaleComponent(value)
  if math.abs(value) < 0.0001 then return 1 end
  return value
end

local function alignActorHipsToSeat(actor, target)
  target = target or resolveSeatTrans()
  if actor == nil or actor.gameObject == nil or target == nil then return end

  local trans = actor.gameObject.transform
  trans:SetParent(target)
  trans.localPosition = Vector3.zero
  trans.localRotation = Quaternion.identity

  local orig = savedScale[actor] or Vector3.one
  local p = target.lossyScale
  trans.localScale = Vector3(orig.x / safeScaleComponent(p.x), orig.y / safeScaleComponent(p.y), orig.z / safeScaleComponent(p.z))

  local animator = actor.gameObject:GetComponentInChildren(typeof(UnityEngine.Animator))
  if animator == nil then return end
  local hips = animator:GetBoneTransform(UnityEngine.HumanBodyBones.Hips)
  if hips == nil then return end

  local hipsPos = hips.position
  local transPos = trans.position
  trans.position = Vector3(
    transPos.x - (hipsPos.x - transPos.x),
    transPos.y - (hipsPos.y - transPos.y),
    transPos.z - (hipsPos.z - transPos.z)
  )
end

local function placeActorAtStandPoint(actor)
  if actor == nil or actor.gameObject == nil then return end
  actor.gameObject.transform:SetParent(nil)
  if savedScale[actor] ~= nil then
    actor.gameObject.transform.localScale = savedScale[actor]
    savedScale[actor] = nil
  end
  -- GCRULES-0905: race return owns the final pose, but local unparent/scale
  -- cleanup must still finish before RaceManager is allowed to teleport.
  if hybridRollbackPrivate.raceSessionDelegatesStandPoint ~= nil
    and hybridRollbackPrivate.raceSessionDelegatesStandPoint(actor) then
    savedBoardOffset, savedBoardRotation = nil, nil
    return
  end
  local right = self.transform.right
  if savedBoardOffset ~= nil and actor.isLocal then
    actor.position = Vector3(
      self.transform.position.x + savedBoardOffset.x,
      self.transform.position.y + savedBoardOffset.y,
      self.transform.position.z + savedBoardOffset.z
    )
    actor.rotation = savedBoardRotation
    savedBoardOffset = nil
    savedBoardRotation = nil
  else
    actor.position = Vector3(
      self.transform.position.x + right.x * 1.4,
      self.transform.position.y,
      self.transform.position.z + right.z * 1.4
    )
    actor.rotation = self.transform.rotation
  end
end

local function clearDriveInput()
  moveVec = UnityEngine.Vector2.zero
end

local function stopHorizontalVelocity()
  if rb == nil then return end
  local v = rb.velocity
  rb.velocity = Vector3(0, v.y, 0)
  rb.angularVelocity = Vector3.zero
end

local function registerMoveInputListeners()
  onMoveInputStart = function(vec)
    if localSeatId == "driver" then
      moveVec = vec
    end
  end
  onMoveInputPerform = function(vec)
    if localSeatId == "driver" then
      moveVec = vec
    end
  end
  onMoveInputCancel = function()
    clearDriveInput()
  end

  DouyinInputService.onMoveInputStart:AddListener(onMoveInputStart)
  DouyinInputService.onMoveInputPerform:AddListener(onMoveInputPerform)
  DouyinInputService.onMoveInputCancel:AddListener(onMoveInputCancel)
end

local function removeMoveInputListeners()
  if onMoveInputStart ~= nil then
    DouyinInputService.onMoveInputStart:RemoveListener(onMoveInputStart)
    onMoveInputStart = nil
  end
  if onMoveInputPerform ~= nil then
    DouyinInputService.onMoveInputPerform:RemoveListener(onMoveInputPerform)
    onMoveInputPerform = nil
  end
  if onMoveInputCancel ~= nil then
    DouyinInputService.onMoveInputCancel:RemoveListener(onMoveInputCancel)
    onMoveInputCancel = nil
  end
end

local function registerCameraAlignInputListeners()
  onLookInputStart = function()
    isLookingActive = true
    lastLookTime = Time.time
  end
  onLookInputPerform = function()
    isLookingActive = true
    lastLookTime = Time.time
  end
  onLookInputCancel = function()
    isLookingActive = false
    lastLookTime = Time.time
  end

  DouyinInputService.onLookInputStart:AddListener(onLookInputStart)
  DouyinInputService.onLookInputPerform:AddListener(onLookInputPerform)
  DouyinInputService.onLookInputCancel:AddListener(onLookInputCancel)
end

local function removeCameraAlignInputListeners()
  if onLookInputStart ~= nil then
    DouyinInputService.onLookInputStart:RemoveListener(onLookInputStart)
    onLookInputStart = nil
  end
  if onLookInputPerform ~= nil then
    DouyinInputService.onLookInputPerform:RemoveListener(onLookInputPerform)
    onLookInputPerform = nil
  end
  if onLookInputCancel ~= nil then
    DouyinInputService.onLookInputCancel:RemoveListener(onLookInputCancel)
    onLookInputCancel = nil
  end
end

local function clampHorizontal(vx, vz, maxSpeed)
  local mag = math.sqrt(vx * vx + vz * vz)
  if maxSpeed > 0.0001 and mag > maxSpeed then
    local s = maxSpeed / mag
    return vx * s, vz * s, maxSpeed
  end
  return vx, vz, mag
end

local function moveHorizontalTowardsZero(vx, vz, maxDelta)
  local mag = math.sqrt(vx * vx + vz * vz)
  if mag <= maxDelta or mag <= 0.0001 then
    return 0, 0
  end
  local nextMag = mag - maxDelta
  local s = nextMag / mag
  return vx * s, vz * s
end

local function rotateHorizontal(vx, vz, degrees)
  local rad = degrees * DEG_TO_RAD
  local c = math.cos(rad)
  local s = math.sin(rad)
  return vx * c + vz * s, -vx * s + vz * c
end

local function getTiltAngles()
  if self == nil or self.transform == nil then
    return 0, 0
  end
  local euler = self.transform.eulerAngles
  return Mathf.DeltaAngle(0, euler.x), Mathf.DeltaAngle(0, euler.z)
end

local function applyTiltSafetyBrake(vx, vz, dt)
  local pitch, roll = getTiltAngles()
  local tiltMagnitude = Mathf.Max(Mathf.Abs(pitch), Mathf.Abs(roll))
  if tiltMagnitude <= tiltSafetyStart then
    return vx, vz
  end
  local span = Mathf.Max(1.0, maxTiltAssistAngle - tiltSafetyStart)
  local brakeRatio = Mathf.Clamp01((tiltMagnitude - tiltSafetyStart) / span)
  return moveHorizontalTowardsZero(vx, vz, emergencyStabilityBrake * brakeRatio * dt)
end

local function dampSidewaysSlip(vx, vz, speedRatio, dt)
  if self == nil or self.transform == nil then
    return vx, vz
  end
  local right = self.transform.right
  local lateralSpeed = vx * right.x + vz * right.z
  local dampingStrength = Mathf.Lerp(sidewaysFriction, sidewaysFriction * 1.35, speedRatio)
  local correction = lateralSpeed * Mathf.Clamp01(dampingStrength * dt)
  return vx - right.x * correction, vz - right.z * correction
end

local function stabilizeAngularMotion(turnInput, speedRatio, dt)
  if rb == nil or self == nil or self.transform == nil then return end
  rb.maxAngularVelocity = maxAngularVelocity
  local localAngular = self.transform:InverseTransformDirection(rb.angularVelocity)
  local pitch, roll = getTiltAngles()
  local pitchRollDampingT = Mathf.Clamp01(pitchRollDamping * dt)
  local yawDampingT = Mathf.Clamp01(yawStability * dt * (0.6 + speedRatio * 0.8))
  if math.abs(turnInput) > DEAD_ZONE then
    yawDampingT = yawDampingT * 0.35
  end
  local correctedX = Mathf.Lerp(localAngular.x, 0, pitchRollDampingT)
  local correctedY = Mathf.Lerp(localAngular.y, 0, yawDampingT)
  local correctedZ = Mathf.Lerp(localAngular.z, 0, pitchRollDampingT)
  local tiltMagnitude = Mathf.Max(Mathf.Abs(pitch), Mathf.Abs(roll))
  if tiltMagnitude > tiltAssistStart then
    local span = Mathf.Max(1.0, maxTiltAssistAngle - tiltAssistStart)
    local tiltRatio = Mathf.Clamp01((tiltMagnitude - tiltAssistStart) / span)
    local assistT = Mathf.Clamp01(tiltRatio * dt * 4.0)
    correctedX = Mathf.Lerp(correctedX, -pitch * DEG_TO_RAD * uprightAssist, assistT)
    correctedZ = Mathf.Lerp(correctedZ, -roll * DEG_TO_RAD * uprightAssist, assistT)
  end
  local correctedWorld = self.transform:TransformDirection(Vector3(correctedX, correctedY, correctedZ))
  rb.angularVelocity = Vector3.ClampMagnitude(correctedWorld, maxAngularVelocity)
end

function getCameraAlignTargetYaw()
  if not cameraFollowEnabled then return nil end
  if localSeatId ~= "driver" then return nil end
  if self == nil or self.transform == nil then return nil end
  return self.transform.eulerAngles.y
end

function getCameraAlignSpeedScale()
  if not cameraFollowEnabled then return 0 end
  if localSeatId ~= "driver" then return 0 end
  local inputStrength = 0
  if moveVec ~= nil then
    inputStrength = math.max(math.abs(moveVec.x), math.abs(moveVec.y))
  end
  return cameraBaseSpeedScale + Mathf.Clamp01(inputStrength) * cameraInputSpeedScale
end

local function applyCameraYawFollow()
  if DouyinCameraService == nil then return end
  if isLookingActive then return end
  if Time.time - lastLookTime < cameraAlignGrace then return end
  local targetYaw = getCameraAlignTargetYaw()
  if targetYaw == nil then return end
  local speedScale = getCameraAlignSpeedScale()
  if speedScale == nil or speedScale <= 0 then return end
  local currentYaw = DouyinCameraService.GetYaw()
  local delta = Mathf.DeltaAngle(currentYaw, targetYaw)
  local maxStep = cameraAlignSpeed * speedScale * Time.deltaTime
  local step = 0
  if math.abs(delta) <= maxStep then
    step = delta
  elseif delta >= 0 then
    step = maxStep
  else
    step = -maxStep
  end
  DouyinCameraService.SetYaw(currentYaw + step)
end

local function beginRespawn()
  if respawnHideUntil ~= nil then return end
  respawnHideUntil = Time.time + respawnHiddenSeconds
  setRendererVisible(self.transform, false)
  if rb ~= nil then
    rb.velocity = Vector3.zero
    rb.angularVelocity = Vector3.zero
  end
  if spawnPosition ~= nil and spawnRotation ~= nil then
    self.transform.position = spawnPosition
    self.transform.rotation = spawnRotation
  end
  emptySince = Time.time
end

local function requestRespawn()
  if DouyinNetService ~= nil and DouyinNetService.isNetworkSettled then
    if self:HasOwnership() then
      beginRespawn()
      return
    end
    if ownershipPending then return end
    ownershipPending = true
    self:RequestOwnership(function(bSucceed)
      ownershipPending = false
      if bSucceed then
        beginRespawn()
      end
    end)
  else
    beginRespawn()
  end
end

local function trySitSeat(seatId, reservedActorId)
  local actorId = hybridRollbackPrivate.normalizeActorId(reservedActorId)
  if actorId == 0 then actorId = hybridRollbackPrivate.actorNetworkId(localActor) end
  local attemptClaim = savedScale.__localSeatClaim
  if type(attemptClaim) ~= "table" or attemptClaim.seatId ~= seatId
    or hybridRollbackPrivate.normalizeActorId(attemptClaim.actorId) ~= actorId then
    attemptClaim = nil
  end
  local function useAttemptClaim(claimed)
    local current = savedScale.__localSeatClaim
    if type(current) ~= "table" or current.seatId ~= seatId
      or hybridRollbackPrivate.normalizeActorId(current.actorId) ~= actorId then
      current = {
        seatId = seatId,
        actorId = actorId,
        resetCycleId = lastAcceptedRaceResetCycleId,
      }
      savedScale.__localSeatClaim = current
    end
    current.claimed = claimed == true
    current.expiresAt = Time.time + 5.0
    if current.resetCycleId == nil then
      current.resetCycleId = lastAcceptedRaceResetCycleId
    end
    if current.sitDownIssued == nil then current.sitDownIssued = false end
    attemptClaim = current
    return current
  end
  local function failAndClear()
    if attemptClaim ~= nil and savedScale.__localSeatClaim ~= attemptClaim then return end
    if attemptClaim == nil and savedScale.__localSeatClaim ~= nil then return end
    if actorId > 0 then requestSeatClaimCancel(seatId, actorId) end
    clearPendingSeatSelection()
    if currentInside and localSeatId == nil then rebuildInteractionButtons() end
  end
  if raceResetLocked or raceCompetitionLocked or localActor == nil or localSeatId ~= nil or actorId == 0 then
    failAndClear()
    return
  end
  local cfg, idx = findSeatConfig(seatId)
  local stationObject = getSeatStationGameObject(seatId)
  if cfg == nil or cfg.transform == nil or stationObject == nil then
    failAndClear()
    UnityEngine.Debug.LogError(tostring(self.gameObject.name) .. ": persistent seat station missing for " .. tostring(seatId))
    return
  end

  if DouyinNetService ~= nil
    and (not DouyinNetService.isNetworkSettled or not netSpawned) then
    selectedSeatId = seatId
    selectedSeatAnchor = cfg.transform
    selectedSeatIndex = idx
    localSeatActorId = actorId
    useAttemptClaim(hybridRollbackPrivate.normalizeActorId(reservedActorId) > 0)
    seatReservationPending = true
    if seatReservationDeadline <= Time.time then seatReservationDeadline = Time.time + 5.0 end
    savedScale.__seatWaitingForNetwork = true
    savedScale.__driverWaitingForNetwork = seatId == "driver"
    return
  end

  if hybridRollbackPrivate.normalizeActorId(reservedActorId) == 0 then
    local result = VehicleClaimSeat(seatId, actorId, lastAcceptedRaceResetCycleId)
    if result ~= "OK" then
      if result == "TAKEN" then hybridRollbackPrivate.showSeatOccupiedFeedback() end
      failAndClear()
      return
    end
  end

  selectedSeatId = seatId
  selectedSeatAnchor = cfg.transform
  selectedSeatIndex = idx
  localSeatActorId = actorId
  useAttemptClaim(true)
  seatTakenCache[seatId] = true
  seatReservationPending = true
  seatReservationDeadline = Time.time + 3.0

  if seatId == "driver" then
    if DouyinNetService ~= nil then
      local owner = false
      pcall(function() owner = self:HasOwnership() end)
      if not owner then
        ensureOwnership(function()
          if savedScale.__localSeatClaim ~= attemptClaim then return end
          local verifiedOwner = false
          pcall(function() verifiedOwner = self:HasOwnership() end)
          if not verifiedOwner or raceResetLocked or raceCompetitionLocked or selectedSeatId ~= "driver"
            or localSeatActorId ~= actorId then
            failAndClear()
            return
          end
          trySitSeat("driver", actorId)
        end, failAndClear)
        return
      end
      local verifiedOwner = false
      pcall(function() verifiedOwner = self:HasOwnership() end)
      if not verifiedOwner then
        failAndClear()
        return
      end
    end
    savedScale.__driverWaitingForNetwork = false
  end

  -- Passenger stations intentionally never request vehicle Ownership.
  if attemptClaim ~= nil then attemptClaim.sitDownIssued = true end
  local callOk = pcall(function() localActor:SitDown(stationObject) end)
  if not callOk then failAndClear() end
end

function hybridRollbackPrivate.finishLocalSitRollback(rollback)
  if savedScale.__localSitRollback ~= rollback then return end
  if rollback.actor ~= nil then
    local relation = hybridRollbackPrivate.actorSeatRelation(rollback.actor, rollback.seatId)
    local parentOk, parent = pcall(function() return rollback.actor.gameObject.transform.parent end)
    if relation == "TARGET" or (parentOk and parent == nil) then
      setActorColliderEnabled(rollback.actor, true)
    end
  end
  savedScale.__localSitRollback = nil
  if currentInside and localSeatId == nil and not raceResetLocked then
    self:EnableInteraction()
    rebuildInteractionButtons()
  end
end

function hybridRollbackPrivate.updateOrphanNativeSeatExit()
  local orphan = savedScale.__orphanNativeSeatExit
  if type(orphan) ~= "table" then return end
  local actor = orphan.actor
  local roomActor, lookup = hybridRollbackPrivate.findRoomActor(orphan.actorId)
  if DouyinNetService ~= nil and lookup == "INVALID" then
    savedScale.__orphanNativeSeatExit = nil
    return
  end
  actor = roomActor or actor
  if actor == nil then
    savedScale.__orphanNativeSeatExit = nil
    return
  end
  orphan.actor = actor
  local stateOk, sitting = pcall(function() return actor:IsSitting() end)
  local relation = hybridRollbackPrivate.actorSeatRelation(actor, orphan.seatId)
  local parentOk, parent = pcall(function() return actor.gameObject.transform.parent end)
  local canStandUpCurrentAttempt = relation == "TARGET"
    or (orphan.allowUnparentedStandUp == true
      and relation == "UNKNOWN" and parentOk and parent == nil)
  if stateOk and sitting ~= true then
    savedScale.__orphanNativeSeatExit = nil
    if canStandUpCurrentAttempt then
      setActorColliderEnabled(actor, true)
    end
    return
  end
  if relation == "OTHER" or relation == "THIS_VEHICLE" then
    savedScale.__orphanNativeSeatExit = nil
    return
  end
  if Time.time >= (tonumber(orphan.deadlineAt) or -math.huge) then
    savedScale.__orphanNativeSeatExit = nil
    return
  end
  if stateOk and sitting == true and canStandUpCurrentAttempt
    and Time.time >= (tonumber(orphan.nextStandUpAt) or -math.huge) then
    local localOk, isLocalActor = pcall(function() return actor.isLocal end)
    local stationObject = getSeatStationGameObject(orphan.seatId)
    if stationObject ~= nil and localOk and isLocalActor == true then
      pcall(function() actor:StandUp(stationObject) end)
    end
    orphan.nextStandUpAt = Time.time + 0.5
  end
end

function hybridRollbackPrivate.updateLocalSitRollback()
  local rollback = savedScale.__localSitRollback
  if type(rollback) ~= "table" then return end
  local actor = rollback.actor
  if actor == nil then
    hybridRollbackPrivate.finishLocalSitRollback(rollback)
    return
  end
  local roomActor, lookup = hybridRollbackPrivate.findRoomActor(rollback.actorId)
  if DouyinNetService ~= nil and lookup == "INVALID" then
    hybridRollbackPrivate.finishLocalSitRollback(rollback)
    return
  end
  actor = roomActor or actor
  rollback.actor = actor
  local stateOk, sitting = pcall(function() return actor:IsSitting() end)
  local localOk, isLocalActor = pcall(function() return actor.isLocal end)
  local relation = hybridRollbackPrivate.actorSeatRelation(actor, rollback.seatId)
  local parentOk, parent = pcall(function() return actor.gameObject.transform.parent end)
  local canStandUpCurrentAttempt = relation == "TARGET"
    or (rollback.allowUnparentedStandUp == true
      and relation == "UNKNOWN" and parentOk and parent == nil)
  if relation == "OTHER" or relation == "THIS_VEHICLE"
    or (relation == "UNKNOWN" and parentOk and parent ~= nil) then
    hybridRollbackPrivate.finishLocalSitRollback(rollback)
    return
  end
  if stateOk and sitting ~= true then
    hybridRollbackPrivate.finishLocalSitRollback(rollback)
    return
  end
  if Time.time >= (tonumber(rollback.hardDeadlineAt) or math.huge) then
    local stationObject = getSeatStationGameObject(rollback.seatId)
    if canStandUpCurrentAttempt and stationObject ~= nil and localOk and isLocalActor == true then
      pcall(function() actor:StandUp(stationObject) end)
    end
    if stateOk and sitting == true and canStandUpCurrentAttempt
      and localOk and isLocalActor == true then
      savedScale.__orphanNativeSeatExit = {
        actor = actor,
        actorId = rollback.actorId,
        seatId = rollback.seatId,
        allowUnparentedStandUp = rollback.allowUnparentedStandUp == true,
        nextStandUpAt = Time.time + 0.5,
        deadlineAt = Time.time + 8.0,
      }
    end
    hybridRollbackPrivate.finishLocalSitRollback(rollback)
    return
  end
  if canStandUpCurrentAttempt
    and Time.time >= (tonumber(rollback.nextStandUpAt) or -math.huge) then
    local stationObject = getSeatStationGameObject(rollback.seatId)
    if stationObject ~= nil and localOk and isLocalActor == true then
      pcall(function() actor:StandUp(stationObject) end)
    end
    rollback.nextStandUpAt = Time.time + 0.25
  end
  if not stateOk and Time.time >= (tonumber(rollback.unknownDeadlineAt) or math.huge) then
    hybridRollbackPrivate.finishLocalSitRollback(rollback)
  end
end

function hybridRollbackPrivate.beginLocalSitRollback(reason)
  if localSeatId ~= nil then return false end
  local claim = savedScale.__localSeatClaim
  local seatId = selectedSeatId or (type(claim) == "table" and claim.seatId or nil)
  local actorId = hybridRollbackPrivate.normalizeActorId(
    localSeatActorId or (type(claim) == "table" and claim.actorId or 0)
  )
  local actor = localActor
  if seatId == nil or actorId == 0 or actor == nil then
    clearPendingSeatSelection()
    if currentInside and localSeatId == nil then rebuildInteractionButtons() end
    return false
  end
  local localOk, isLocalActor = pcall(function() return actor.isLocal end)
  local allowUnparentedStandUp = localOk and isLocalActor == true
    and type(claim) == "table" and claim.seatId == seatId
    and hybridRollbackPrivate.normalizeActorId(claim.actorId) == actorId
    and claim.claimed == true and claim.sitDownIssued == true
    and math.floor(tonumber(claim.resetCycleId) or -1) == lastAcceptedRaceResetCycleId
    and (tonumber(claim.expiresAt) or -math.huge) > Time.time
    and selectedSeatId == seatId
    and hybridRollbackPrivate.normalizeActorId(localSeatActorId) == actorId
    and seatReservationPending
  local rollback = {
    actor = actor,
    actorId = actorId,
    seatId = seatId,
    allowUnparentedStandUp = allowUnparentedStandUp == true,
    nextStandUpAt = Time.time,
    unknownDeadlineAt = Time.time + 2.0,
    hardDeadlineAt = Time.time + 2.0,
    reason = reason,
  }
  requestSeatClaimCancel(seatId, actorId)
  clearPendingSeatSelection()
  savedScale.__localSitRollback = rollback
  local relation = hybridRollbackPrivate.actorSeatRelation(actor, seatId)
  local parentOk, parent = pcall(function() return actor.gameObject.transform.parent end)
  if relation == "TARGET" or (parentOk and parent == nil) then
    setActorColliderEnabled(actor, true)
  end
  hybridRollbackPrivate.updateLocalSitRollback()
  return true
end

local function tryExitSeat()
  if raceCompetitionLocked or currentPlayer == nil or localSeatId == nil then return end
  local exitingActor = currentPlayer
  local exitingSeat = localSeatId
  local stationObject = getSeatStationGameObject(exitingSeat)
  if stationObject ~= nil
    and hybridRollbackPrivate.actorSeatRelation(exitingActor, exitingSeat) == "TARGET" then
    pcall(function() exitingActor:StandUp(stationObject) end)
  end
  VehicleSeatStationExited(exitingActor, exitingSeat, true)
end

local function requestSeatReservation(seatId)
  if raceResetLocked or raceCompetitionLocked or localActor == nil or localSeatId ~= nil then return end
  hybridRollbackPrivate.updateLocalSitRollback()
  if savedScale.__localSitRollback ~= nil then return end
  if seatReservationPending and savedScale.__seatWaitingForNetwork ~= true then return end
  local cfg, idx = findSeatConfig(seatId)
  if cfg == nil or cfg.transform == nil or getSeatStationGameObject(seatId) == nil then
    UnityEngine.Debug.LogError(tostring(self.gameObject.name) .. ": seat station unavailable for " .. tostring(seatId))
    return
  end
  local actorId = hybridRollbackPrivate.actorNetworkId(localActor)
  if actorId == 0 then
    clearPendingSeatSelection()
    return
  end
  hybridRollbackPrivate.updateOrphanNativeSeatExit()
  local orphan = savedScale.__orphanNativeSeatExit
  if type(orphan) == "table"
    and hybridRollbackPrivate.normalizeActorId(orphan.actorId) == actorId then return end
  selectedSeatId = seatId
  selectedSeatAnchor = cfg.transform
  selectedSeatIndex = idx
  localSeatActorId = actorId
  savedScale.__localSeatClaim = {
    seatId = seatId,
    actorId = actorId,
    claimed = false,
    sitDownIssued = false,
    resetCycleId = lastAcceptedRaceResetCycleId,
    expiresAt = Time.time + 5.0,
  }
  local requestClaim = savedScale.__localSeatClaim
  local requestResetCycleId = lastAcceptedRaceResetCycleId

  if DouyinNetService ~= nil
    and (not DouyinNetService.isNetworkSettled or not netSpawned) then
    seatReservationPending = true
    seatReservationDeadline = Time.time + 5.0
    savedScale.__seatWaitingForNetwork = true
    savedScale.__driverWaitingForNetwork = seatId == "driver"
    return
  end

  savedScale.__seatWaitingForNetwork = false
  savedScale.__driverWaitingForNetwork = false
  seatReservationPending = true
  seatReservationDeadline = Time.time + 5.0
  local networkReady = DouyinNetService ~= nil and DouyinNetService.isNetworkSettled and netSpawned
  local owner = false
  if networkReady then pcall(function() owner = self:HasOwnership() end) end

  local function handleResult(result)
    if savedScale.__localSeatClaim ~= requestClaim then return end
    if lastAcceptedRaceResetCycleId ~= requestResetCycleId then
      clearPendingSeatSelection()
      if currentInside and localSeatId == nil then rebuildInteractionButtons() end
      return
    end
    local status = tostring(result or "DENY")
    if selectedSeatId ~= seatId or localSeatId ~= nil or raceResetLocked or raceCompetitionLocked then
      return
    end
    if status == "OK" then
      if savedScale.__localSeatClaim ~= nil then savedScale.__localSeatClaim.claimed = true end
      trySitSeat(seatId, actorId)
    else
      if status == "TAKEN" then hybridRollbackPrivate.showSeatOccupiedFeedback() end
      clearPendingSeatSelection()
      rebuildInteractionButtons()
    end
  end

  if DouyinNetService == nil or owner then
    handleResult(VehicleClaimSeat(seatId, actorId, requestResetCycleId))
    return
  end
  local requestOk = pcall(function()
    self:OwnerCall("VehicleClaimSeat", handleResult, seatId, actorId, tostring(requestResetCycleId))
  end)
  if not requestOk and savedScale.__localSeatClaim == requestClaim then
    clearPendingSeatSelection()
    rebuildInteractionButtons()
  end
end

function hybridRollbackPrivate.abortLocalSeatCommit(reason)
  local commit = savedScale.__localSeatCommit
  if type(commit) ~= "table" then return end
  savedScale.__localSeatCommit = nil
  local actor = currentPlayer
  local seatId = commit.seatId
  local actorId = commit.actorId
  requestSeatClaimCancel(seatId, actorId)
  if actor ~= nil and localSeatId == seatId then
    local stationObject = getSeatStationGameObject(seatId)
    if stationObject ~= nil
      and hybridRollbackPrivate.actorSeatRelation(actor, seatId) == "TARGET" then
      pcall(function() actor:StandUp(stationObject) end)
    end
    VehicleSeatStationExited(actor, seatId, true)
  else
    requestSeatRelease(seatId, actorId)
    clearPendingSeatSelection()
  end
  if reason == "TAKEN" then hybridRollbackPrivate.showSeatOccupiedFeedback() end
  if currentInside and localSeatId == nil then rebuildInteractionButtons() end
end

function hybridRollbackPrivate.handleLocalSeatCommitResult(commit, result)
  local status = tostring(result or "RETRY")
  if savedScale.__localSeatCommit ~= commit then
    if status == "OK" then
      local currentCommit = savedScale.__localSeatCommit
      local currentClaim = savedScale.__localSeatClaim
      local sameCurrentAttempt = localSeatId == commit.seatId and localSeatActorId == commit.actorId
        or (type(currentCommit) == "table" and currentCommit.seatId == commit.seatId
          and currentCommit.actorId == commit.actorId)
        or (type(currentClaim) == "table" and currentClaim.seatId == commit.seatId
          and hybridRollbackPrivate.normalizeActorId(currentClaim.actorId) == commit.actorId)
      if not sameCurrentAttempt then
        requestSeatRelease(commit.seatId, commit.actorId)
        requestSeatClaimCancel(commit.seatId, commit.actorId)
      end
    end
    return
  end
  commit.inFlight = false
  if status == "OK" then
    if localSeatId == commit.seatId and localSeatActorId == commit.actorId then
      savedScale.__localSeatCommit = nil
      savedScale.__localSeatClaim = nil
      seatReservationPending = false
      seatReservationDeadline = -math.huge
      return
    end
    savedScale.__localSeatCommit = nil
    requestSeatRelease(commit.seatId, commit.actorId)
    requestSeatClaimCancel(commit.seatId, commit.actorId)
    return
  end
  if status == "RETRY" and Time.time < commit.deadlineAt then
    commit.nextAttemptAt = Time.time + 0.2
    return
  end
  hybridRollbackPrivate.abortLocalSeatCommit(status)
end

function hybridRollbackPrivate.tryLocalSeatCommit()
  local commit = savedScale.__localSeatCommit
  if type(commit) ~= "table" or commit.inFlight == true then return end
  if Time.time < (tonumber(commit.nextAttemptAt) or -math.huge) then return end
  if localSeatId ~= commit.seatId or localSeatActorId ~= commit.actorId
    or raceResetLocked or lastAcceptedRaceResetCycleId ~= commit.resetCycleId
    or Time.time >= commit.deadlineAt then
    hybridRollbackPrivate.abortLocalSeatCommit("DENY")
    return
  end
  if DouyinNetService == nil then
    hybridRollbackPrivate.handleLocalSeatCommitResult(
      commit,
      VehicleCommitSeatOccupant(commit.seatId, commit.actorId, commit.resetCycleId)
    )
    return
  end
  if not DouyinNetService.isNetworkSettled or not netSpawned then
    commit.nextAttemptAt = Time.time + 0.2
    return
  end
  local owner = false
  pcall(function() owner = self:HasOwnership() end)
  if owner then
    hybridRollbackPrivate.handleLocalSeatCommitResult(
      commit,
      VehicleCommitSeatOccupant(commit.seatId, commit.actorId, commit.resetCycleId)
    )
    return
  end
  commit.inFlight = true
  local requestOk = pcall(function()
    self:OwnerCall("VehicleCommitSeatOccupant", function(result)
      hybridRollbackPrivate.handleLocalSeatCommitResult(commit, result)
    end, commit.seatId, commit.actorId, tostring(commit.resetCycleId))
  end)
  if not requestOk then
    commit.inFlight = false
    commit.nextAttemptAt = Time.time + 0.2
  end
end

function hybridRollbackPrivate.beginLocalSeatCommit(seatId, actorId)
  local commit = {
    seatId = seatId,
    actorId = hybridRollbackPrivate.normalizeActorId(actorId),
    resetCycleId = lastAcceptedRaceResetCycleId,
    deadlineAt = Time.time + 3.0,
    nextAttemptAt = Time.time,
    inFlight = false,
  }
  savedScale.__localSeatCommit = commit
  hybridRollbackPrivate.tryLocalSeatCommit()
end

function hybridRollbackPrivate.updateLocalSeatCommit()
  local commit = savedScale.__localSeatCommit
  if type(commit) ~= "table" then return end
  if Time.time >= (tonumber(commit.deadlineAt) or -math.huge) then
    hybridRollbackPrivate.abortLocalSeatCommit("DENY")
    return
  end
  hybridRollbackPrivate.tryLocalSeatCommit()
end

local RACE_RESET_TOKEN_STRIDE = 100000000
local RACE_RESET_MIN_TOKEN = RACE_RESET_TOKEN_STRIDE + 1
local RACE_RESET_MAX_TOKEN = 21 * RACE_RESET_TOKEN_STRIDE - 1
local RACE_RESET_PHYSICS_DELAY_SECONDS = 1.0
local RACE_RESET_RETRY_SECONDS = 1.0
local RACE_RESET_MAX_ATTEMPTS = 3
local RACE_RESET_VERIFY_DELAY_SECONDS = 0.1
local RACE_RESET_HORIZONTAL_TOLERANCE = 0.75
local RACE_RESET_CONFIRM_FALLBACK_SECONDS = 0.15

local function normalizeRaceResetCycleId(rawCycleId)
  local cycleId = tonumber(rawCycleId)
  if cycleId == nil or cycleId ~= cycleId then return nil end
  cycleId = math.floor(cycleId)
  if cycleId < RACE_RESET_MIN_TOKEN or cycleId > RACE_RESET_MAX_TOKEN then return nil end
  local revision = math.floor(cycleId / RACE_RESET_TOKEN_STRIDE)
  local ordinal = cycleId - revision * RACE_RESET_TOKEN_STRIDE
  if revision < 1 or revision > 20 or ordinal < 1 or ordinal >= RACE_RESET_TOKEN_STRIDE then return nil end
  return cycleId
end

function hybridRollbackPrivate.adoptSynchronizedResetEpoch(rawCycleId)
  local accepted = normalizeRaceResetCycleId(rawCycleId)
  if accepted == nil then return false end
  lastAcceptedRaceResetCycleId = math.max(lastAcceptedRaceResetCycleId, accepted)
  local cleaned = math.floor(tonumber(savedScale.__raceResetLocalCleanupCycleId) or 0)
  local observed = math.floor(tonumber(savedScale.__raceResetUnresolvedObservedCycleId) or 0)
  if accepted > cleaned and accepted > observed then
    savedScale.__raceResetUnresolvedObservedCycleId = accepted
    savedScale.__raceResetUnresolvedObservedAt = Time.time
  end
  return true
end

function hybridRollbackPrivate.adoptSynchronizedCompletedReset(rawCycleId)
  local completed = normalizeRaceResetCycleId(rawCycleId)
  if completed == nil then return false end
  hybridRollbackPrivate.adoptSynchronizedResetEpoch(completed)
  lastCompletedRaceResetCycleId = math.max(lastCompletedRaceResetCycleId, completed)
  lastAcknowledgedRaceResetCycleId = math.max(lastAcknowledgedRaceResetCycleId, completed)
  -- Completed VarSync can overtake RaceManagerReset on another client. Record
  -- the observation, but only finish/expire after that client has applied its
  -- own idempotent local seat/UI/native-exit cleanup for the cycle.
  savedScale.__raceResetObservedCompletedCycleId = math.max(
    tonumber(savedScale.__raceResetObservedCompletedCycleId) or 0,
    completed
  )
  if hybridRollbackPrivate.applyCompletedResetLocally ~= nil then
    pcall(function() hybridRollbackPrivate.applyCompletedResetLocally(completed) end)
  end
  if raceResetLocked and pendingRaceResetCycleId ~= nil
    and completed >= pendingRaceResetCycleId and VehicleWakeRaceResetFromSync ~= nil then
    VehicleWakeRaceResetFromSync(pendingRaceResetCycleId)
  end
  return true
end

function hybridRollbackPrivate.readSynchronizedResetEpoch()
  local observed = 0
  local function consider(rawValue)
    local candidate = normalizeRaceResetCycleId(rawValue)
    if candidate ~= nil then observed = math.max(observed, candidate) end
  end
  consider(lastCompletedRaceResetCycleId)
  consider(lastAcknowledgedRaceResetCycleId)
  if DouyinNetService == nil or not netSpawned then
    consider(lastAcceptedRaceResetCycleId)
  else
    local acceptedOk, accepted = pcall(function() return raceResetPhysicalClaimCycleId:GetValue() end)
    if acceptedOk then consider(accepted) end
    local completedOk, completed = pcall(function() return raceResetCompletedCycleId:GetValue() end)
    if completedOk then consider(completed) end
  end
  if observed >= RACE_RESET_MIN_TOKEN then
    hybridRollbackPrivate.adoptSynchronizedResetEpoch(observed)
  end
  return observed
end

local function isLocalVehicleOwner()
  if DouyinNetService == nil then return true end
  if not DouyinNetService.isNetworkSettled or not netSpawned then return false end
  local owner = false
  pcall(function() owner = self:HasOwnership() end)
  return owner
end

local function readSynchronizedCompletedRaceResetCycleId(upperBound)
  local limit = math.floor(tonumber(upperBound) or lastAcceptedRaceResetCycleId or 0)
  local completed = 0
  local function consider(rawValue)
    local candidate = normalizeRaceResetCycleId(rawValue)
    if candidate ~= nil and limit >= RACE_RESET_MIN_TOKEN and candidate <= limit then
      completed = math.max(completed, candidate)
    end
  end
  consider(lastCompletedRaceResetCycleId)
  consider(lastAcknowledgedRaceResetCycleId)
  if netSpawned then
    local ok, synchronized = pcall(function() return raceResetCompletedCycleId:GetValue() end)
    if ok then consider(synchronized) end
  end
  lastAcknowledgedRaceResetCycleId = completed
  return completed
end

local function publishCompletedRaceResetCycleId(cycleId)
  local completed = normalizeRaceResetCycleId(cycleId)
  if completed == nil then return false end
  if not netSpawned then
    lastAcknowledgedRaceResetCycleId = math.max(lastAcknowledgedRaceResetCycleId, completed)
    return true
  end
  if not isLocalVehicleOwner() then return false end
  local currentOk, currentValue = pcall(function() return raceResetCompletedCycleId:GetValue() end)
  local currentCycle = currentOk and normalizeRaceResetCycleId(currentValue) or nil
  if currentCycle ~= nil then
    hybridRollbackPrivate.adoptSynchronizedCompletedReset(currentCycle)
    if currentCycle > completed then return false end
    if currentCycle == completed then return true end
  end
  -- Float-backed number VarSync rounds 200085643 to 200085648. Tokens must stay exact.
  local published = pcall(function() raceResetCompletedCycleId:SetValue(tostring(completed)) end)
  if published then
    lastAcknowledgedRaceResetCycleId = math.max(lastAcknowledgedRaceResetCycleId, completed)
  end
  return published
end

function hybridRollbackPrivate.readConfirmedPhysicalToken(variable, confirmedKey, upperBound)
  local limit = math.floor(tonumber(upperBound) or lastAcceptedRaceResetCycleId or 0)
  local observed = 0
  local function consider(rawValue)
    local candidate = normalizeRaceResetCycleId(rawValue)
    if candidate ~= nil and candidate <= limit then observed = math.max(observed, candidate) end
  end
  consider(savedScale[confirmedKey])
  if netSpawned and variable ~= nil then
    local ok, synchronized = pcall(function() return variable:GetValue() end)
    if ok then
      consider(synchronized)
      if observed > 0 then savedScale[confirmedKey] = observed end
    end
  end
  return observed
end

function hybridRollbackPrivate.publishPhysicalToken(variable, requestedKey, confirmedKey, requestedAtKey, requestedFrameKey, cycleId)
  if not isLocalVehicleOwner() then return false end
  if DouyinNetService == nil then
    savedScale[requestedKey] = cycleId
    savedScale[confirmedKey] = cycleId
    savedScale[requestedAtKey] = Time.time
    savedScale[requestedFrameKey] = Time.frameCount
    return true
  end
  if not netSpawned or variable == nil then return false end
  local currentOk, currentValue = pcall(function() return variable:GetValue() end)
  local currentCycle = currentOk and normalizeRaceResetCycleId(currentValue) or nil
  if currentCycle ~= nil and currentCycle > cycleId then
    savedScale[confirmedKey] = math.max(tonumber(savedScale[confirmedKey]) or 0, currentCycle)
    hybridRollbackPrivate.adoptSynchronizedResetEpoch(currentCycle)
    return false
  end
  local published = pcall(function() variable:SetValue(tostring(cycleId)) end)
  if published then
    savedScale[requestedKey] = cycleId
    savedScale[requestedAtKey] = Time.time
    savedScale[requestedFrameKey] = Time.frameCount
  end
  return published
end

function hybridRollbackPrivate.captureRaceResetNativeExitGuard(cycleId)
  local guard = { cycleId = cycleId, actors = {} }
  local function addActor(actor, rawActorId, seatId)
    if actor == nil or seatId == nil then return end
    local actorId = hybridRollbackPrivate.normalizeActorId(rawActorId)
    if actorId == 0 then actorId = hybridRollbackPrivate.actorNetworkId(actor) end
    if actorId == 0 then return end
    guard.actors[actorId] = { actor = actor, actorId = actorId, seatId = seatId }
  end
  if currentPlayer ~= nil and localSeatId ~= nil then addActor(currentPlayer, localSeatActorId, localSeatId) end
  local localClaim = savedScale.__localSeatClaim
  if type(localClaim) == "table" and (seatReservationPending or selectedSeatId ~= nil) then
    addActor(localActor, localClaim.actorId, localClaim.seatId)
  end
  for actor, _ in pairs(seatedActors) do addActor(actor, nil, actorSeatIds[actor]) end
  local pendingEntries = pendingSeatEntries()
  for index = 1, #pendingEntries do
    addActor(pendingEntries[index].actor, pendingEntries[index].actorId, pendingEntries[index].seatId)
  end
  for index = 1, #seatConfigs do
    local seatId = seatConfigs[index].id
    local occupantId = hybridRollbackPrivate.readSeatOccupantId(seatId)
    if occupantId > 0 then
      local health, actor = hybridRollbackPrivate.seatActorHealth(seatId, occupantId)
      if health == "VALID" then addActor(actor, occupantId, seatId) end
    end
    local physicalActor, physicalState = hybridRollbackPrivate.scanPhysicalSeatActor(seatId)
    if physicalState == "FOUND" then addActor(physicalActor, nil, seatId) end
  end
  savedScale.__raceResetNativeExitGuard = guard
  return guard
end

function hybridRollbackPrivate.allTrackedActorsExitedNativeSeats()
  local guard = savedScale.__raceResetNativeExitGuard
  if type(guard) ~= "table" or guard.cycleId ~= pendingRaceResetCycleId
    or type(guard.actors) ~= "table" then return true end
  for actorId, entry in pairs(guard.actors) do
    local roomActor, lookup = hybridRollbackPrivate.findRoomActor(actorId)
    if DouyinNetService ~= nil and lookup == "INVALID" then
      guard.actors[actorId] = nil
    else
      local actor = roomActor or entry.actor
      if actor == nil then
        guard.actors[actorId] = nil
      else
        local stateOk, stillSitting = pcall(function() return actor:IsSitting() end)
        local relation = hybridRollbackPrivate.actorSeatRelation(actor, entry.seatId)
        if stateOk and stillSitting == true
          and (relation == "TARGET" or relation == "THIS_VEHICLE") then return false end
        -- UNKNOWN state is not proof of a real rider. Stale Actor IDs and failed
        -- probes are handled by post-pose seat cleanup, never by blocking reset.
        guard.actors[actorId] = nil
      end
    end
  end
  return true
end

local function sanitizeSynchronizedRaceResetCompletion()
  if not netSpawned or not isLocalVehicleOwner() then return end
  local ok, synchronized = pcall(function() return raceResetCompletedCycleId:GetValue() end)
  if not ok then return end
  local numeric = math.floor(tonumber(synchronized) or 0)
  if numeric ~= 0 and normalizeRaceResetCycleId(numeric) == nil then
    pcall(function() raceResetCompletedCycleId:SetValue("0") end)
    lastAcknowledgedRaceResetCycleId = 0
  end
end

function hybridRollbackPrivate.clearResetIntent()
  if localSeatId == nil and selectedSeatId ~= nil then
    hybridRollbackPrivate.beginLocalSitRollback("RESET")
  end
  if localSeatId == nil and savedScale.__localSeatClaim ~= nil then
    hybridRollbackPrivate.clearLocalReservationCache()
    localSeatActorId = nil
  end
  savedScale.__seatClaimShadow = {}
  savedScale.__seatMigrationGraceUntil = {}
  savedScale.__legacyPhysicalSeats = {}
  savedScale.__localSeatCommit = nil
  ownershipPending = false
  ownershipPendingDeadline = -math.huge
  seatReservationPending = false
  seatReservationDeadline = -math.huge
  selectedSeatId = nil
  selectedSeatAnchor = nil
  selectedSeatIndex = -1
  VehicleAbortAllPendingSeatEntries(savedScale.__raceResetDeadlineAt)
  savedScale.__driverWaitingForNetwork = false
  pcall(function() clearDriveInput() end)
  pcall(function() hybridRollbackPrivate.sleepTrailEffect() end)
  pcall(function() stopEngineAudio(true) end)
  engineAudioMutedUntil = Time.time + 0.75
end

function hybridRollbackPrivate.applyCompletedResetLocally(rawCycleId)
  local cycleId = normalizeRaceResetCycleId(rawCycleId)
  if cycleId == nil then return false end
  if savedScale.__seatRuntimeStarted ~= true then return false end
  local completedCycle = math.max(
    math.floor(tonumber(lastCompletedRaceResetCycleId) or 0),
    math.floor(tonumber(savedScale.__raceResetObservedCompletedCycleId) or 0)
  )
  if completedCycle < cycleId then return false end
  if math.floor(tonumber(savedScale.__raceResetLocalCleanupCycleId) or 0) >= cycleId then
    return true
  end

  pcall(function() self:DisableInteraction() end)
  removeInteractionButtons()
  hybridRollbackPrivate.clearResetIntent()
  if currentPlayer ~= nil and localSeatId ~= nil then
    local exitingActor = currentPlayer
    local exitingSeat = localSeatId
    local stationObject = getSeatStationGameObject(exitingSeat)
    if stationObject ~= nil
      and hybridRollbackPrivate.actorSeatRelation(exitingActor, exitingSeat) == "TARGET" then
      pcall(function() exitingActor:StandUp(stationObject) end)
    end
    VehicleSeatStationExited(exitingActor, exitingSeat, true)
  end
  savedScale.__raceResetLocalCleanupCycleId = math.max(
    math.floor(tonumber(savedScale.__raceResetLocalCleanupCycleId) or 0),
    cycleId
  )
  pcall(function() refreshInteractionForState() end)
  return true
end

function hybridRollbackPrivate.applyExpiredObservedResetLocally(rawCycleId)
  local cycleId = normalizeRaceResetCycleId(rawCycleId)
  if cycleId == nil or savedScale.__seatRuntimeStarted ~= true then return false end
  if math.floor(tonumber(savedScale.__raceResetLocalCleanupCycleId) or 0) >= cycleId then
    return true
  end
  local observedCycle = math.floor(tonumber(savedScale.__raceResetUnresolvedObservedCycleId) or 0)
  local observedAt = tonumber(savedScale.__raceResetUnresolvedObservedAt) or math.huge
  if observedCycle ~= cycleId or Time.time - observedAt < 5.25 then return false end

  -- The reset RPC window is at most five seconds. A client joining an old room
  -- can inherit an accepted token from a failed reset whose RPC will never be
  -- replayed; after one full window, apply local cleanup once and unblock seats.
  pcall(function() self:DisableInteraction() end)
  removeInteractionButtons()
  hybridRollbackPrivate.clearResetIntent()
  if currentPlayer ~= nil and localSeatId ~= nil then
    local exitingActor = currentPlayer
    local exitingSeat = localSeatId
    local stationObject = getSeatStationGameObject(exitingSeat)
    if stationObject ~= nil
      and hybridRollbackPrivate.actorSeatRelation(exitingActor, exitingSeat) == "TARGET" then
      pcall(function() exitingActor:StandUp(stationObject) end)
    end
    VehicleSeatStationExited(exitingActor, exitingSeat, true)
  end
  savedScale.__raceResetLocalCleanupCycleId = math.max(
    math.floor(tonumber(savedScale.__raceResetLocalCleanupCycleId) or 0),
    cycleId
  )
  savedScale.__raceResetExpiredObservedCleanupCycleId = math.max(
    math.floor(tonumber(savedScale.__raceResetExpiredObservedCleanupCycleId) or 0),
    cycleId
  )
  pcall(function() refreshInteractionForState() end)
  return true
end

local function finishRaceResetTransaction(cycleId)
  local terminalCycle = tonumber(savedScale.__raceResetTerminalCycleId) or 0
  local terminalStatus = tostring(savedScale.__raceResetTerminalStatus or "")
  if terminalCycle == cycleId then return terminalStatus == "COMPLETED" end
  if math.floor(tonumber(savedScale.__raceResetLocalCleanupCycleId) or 0) < cycleId
    and not hybridRollbackPrivate.applyCompletedResetLocally(cycleId) then return false end
  savedScale.__raceResetTerminalCycleId = cycleId
  savedScale.__raceResetTerminalStatus = "COMPLETED"
  lastCompletedRaceResetCycleId = math.max(lastCompletedRaceResetCycleId, cycleId)
  pendingRaceResetCycleId = nil
  raceResetExecuteAt = nil
  raceResetRestoreAt = nil
  savedScale.__raceResetPhysicalVerifyAt = nil
  savedScale.__raceResetPhysicalNextAttemptAt = -math.huge
  savedScale.__raceResetPoseVerifiedCycleId = 0
  hybridRollbackPrivate.clearResetIntent()
  savedScale.__raceResetNativeExitGuard = nil
  savedScale.__raceResetDeadlineAt = nil
  savedScale.__raceResetDeadlineCycleId = nil
  raceResetLocked = false
  if rb ~= nil and isLocalVehicleOwner() then
    pcall(function()
      rb.isKinematic = false
      rb.useGravity = true
      rb:WakeUp()
    end)
  end
  pcall(function() refreshInteractionForState() end)
  return true
end

function hybridRollbackPrivate.expireRaceResetTransaction()
  local expiringCycleId = pendingRaceResetCycleId
    or tonumber(savedScale.__raceResetDeadlineCycleId)
    or lastAcceptedRaceResetCycleId
  expiringCycleId = normalizeRaceResetCycleId(expiringCycleId)
  if expiringCycleId == nil then return false end
  if tonumber(savedScale.__raceResetTerminalCycleId) == expiringCycleId then return false end

  -- Mark the terminal state before any VarSync write so synchronous callbacks
  -- cannot re-enter this failure path. Seat cleanup is best-effort and runs once.
  savedScale.__raceResetTerminalCycleId = expiringCycleId
  savedScale.__raceResetTerminalStatus = "FAILED"
  savedScale.__raceResetFailedCycleId = expiringCycleId
  savedScale.__raceResetExpiredHandledCycleId = expiringCycleId
  if isLocalVehicleOwner() then
    for index = 1, #seatConfigs do
      pcall(function() forceClearSeat(seatConfigs[index].id, expiringCycleId) end)
    end
  end
  pendingRaceResetCycleId = nil
  raceResetExecuteAt = nil
  raceResetRestoreAt = nil
  savedScale.__raceResetPhysicalVerifyAt = nil
  savedScale.__raceResetPhysicalNextAttemptAt = -math.huge
  savedScale.__raceResetPoseVerifiedCycleId = 0
  hybridRollbackPrivate.clearResetIntent()
  savedScale.__raceResetNativeExitGuard = nil
  savedScale.__raceResetDeadlineAt = nil
  savedScale.__raceResetDeadlineCycleId = nil
  raceResetLocked = false
  if rb ~= nil and isLocalVehicleOwner() then
    pcall(function()
      rb.isKinematic = false
      rb.useGravity = true
      rb:WakeUp()
    end)
  end
  pcall(function() refreshInteractionForState() end)
  return false
end

function hybridRollbackPrivate.scheduleRaceResetCheck(delaySeconds)
  if savedScale.__raceResetDeadlineAt == nil then return false end
  local candidateAt = math.min(
    savedScale.__raceResetDeadlineAt,
    Time.time + math.max(0, tonumber(delaySeconds) or 0)
  )
  -- Preserve an earlier event-driven wake. Some VarSync implementations invoke
  -- OnValueChange synchronously inside SetValue; the short confirmation
  -- fallback must not overwrite that already-delivered event.
  if raceResetExecuteAt == nil or candidateAt < raceResetExecuteAt then
    raceResetExecuteAt = candidateAt
  end
  return true
end

-- Sync callbacks wake the current reset transaction immediately. If a callback
-- never arrives, confirmation reads stay inside the five-second window;
-- actual position writes remain at least one second apart.
function VehicleWakeRaceResetFromSync(rawCycleId)
  local cycleId = tonumber(rawCycleId)
  if not raceResetLocked or pendingRaceResetCycleId == nil
    or cycleId ~= pendingRaceResetCycleId then return false end
  local deadlineAt = tonumber(savedScale.__raceResetDeadlineAt)
  if deadlineAt == nil or Time.time >= deadlineAt then return false end
  if raceResetExecuteAt == nil or raceResetExecuteAt > Time.time then
    raceResetExecuteAt = Time.time
  end
  return true
end

function hybridRollbackPrivate.localPhysicalRequestHasWaited(requestAtKey, requestFrameKey)
  local requestedAt = tonumber(savedScale[requestAtKey]) or math.huge
  local requestedFrame = tonumber(savedScale[requestFrameKey]) or math.huge
  return Time.frameCount > requestedFrame and Time.time > requestedAt
end

function hybridRollbackPrivate.isRaceResetPoseVerified()
  if spawnPosition == nil or self == nil or self.transform == nil then return false end
  local position = self.transform.position
  if rb ~= nil then pcall(function() position = rb.position end) end
  if position == nil then return false end
  local dx = position.x - spawnPosition.x
  local dz = position.z - spawnPosition.z
  return dx * dx + dz * dz <= RACE_RESET_HORIZONTAL_TOLERANCE * RACE_RESET_HORIZONTAL_TOLERANCE
end

function hybridRollbackPrivate.ensureRaceResetSeatStatesCleared(cycleId)
  if VehicleAreAllSeatStatesCleared(cycleId) then
    savedScale.__raceResetSeatsCleared = true
    return true
  end
  local attempts = tonumber(savedScale.__raceResetSeatClearAttemptCount) or 0
  local nextWriteAt = tonumber(savedScale.__raceResetSeatClearNextWriteAt) or -math.huge
  if attempts >= RACE_RESET_MAX_ATTEMPTS or Time.time < nextWriteAt then return false end
  savedScale.__raceResetSeatClearAttemptCount = attempts + 1
  savedScale.__raceResetSeatClearLastWriteAt = Time.time
  savedScale.__raceResetSeatClearNextWriteAt = Time.time + RACE_RESET_RETRY_SECONDS
  savedScale.__raceResetSeatsCleared = false
  savedScale.__raceResetSeatClearWriteSucceeded = true
  for index = 1, #seatConfigs do
    local ok, issued = pcall(function()
      return forceClearSeat(seatConfigs[index].id, cycleId)
    end)
    if not ok or issued ~= true then savedScale.__raceResetSeatClearWriteSucceeded = false end
  end
  return false
end

function hybridRollbackPrivate.supersedeRaceResetTransaction()
  local oldCycleId = pendingRaceResetCycleId
  if oldCycleId == nil or oldCycleId >= lastAcceptedRaceResetCycleId then return false end
  pendingRaceResetCycleId = nil
  raceResetExecuteAt = nil
  raceResetRestoreAt = nil
  savedScale.__raceResetPhysicalVerifyAt = nil
  savedScale.__raceResetPhysicalNextAttemptAt = -math.huge
  savedScale.__raceResetPoseVerifiedCycleId = 0
  hybridRollbackPrivate.clearResetIntent()
  savedScale.__raceResetNativeExitGuard = nil
  savedScale.__raceResetDeadlineAt = nil
  savedScale.__raceResetDeadlineCycleId = nil
  raceResetLocked = false
  if rb ~= nil and isLocalVehicleOwner() then
    pcall(function()
      rb.isKinematic = false
      rb.useGravity = true
      rb:WakeUp()
    end)
  end
  pcall(function() refreshInteractionForState() end)
  return true
end

local function performRaceResetPhysics()
  local cycleId = pendingRaceResetCycleId
  raceResetExecuteAt = nil
  if cycleId ~= nil and cycleId < lastAcceptedRaceResetCycleId then
    hybridRollbackPrivate.supersedeRaceResetTransaction()
    return false
  end
  if cycleId == nil or rb == nil or spawnPosition == nil or spawnRotation == nil then
    hybridRollbackPrivate.expireRaceResetTransaction()
    return false
  end
  if savedScale.__raceResetDeadlineCycleId ~= cycleId
    or savedScale.__raceResetDeadlineAt == nil
    or Time.time >= savedScale.__raceResetDeadlineAt then
    hybridRollbackPrivate.expireRaceResetTransaction()
    return false
  end

  -- The vehicle's unique current network owner is the only physical authority.
  -- Synchronized seat cleanup and reset acknowledgements must never block the
  -- owner's position write; they run only after the spawn pose is verified.
  if not isLocalVehicleOwner() then
    hybridRollbackPrivate.scheduleRaceResetCheck(RACE_RESET_CONFIRM_FALLBACK_SECONDS)
    return true
  end
  if not hybridRollbackPrivate.allTrackedActorsExitedNativeSeats() then
    hybridRollbackPrivate.scheduleRaceResetCheck(RACE_RESET_CONFIRM_FALLBACK_SECONDS)
    return true
  end

  local attemptCount = tonumber(savedScale.__raceResetPhysicalAttemptCount) or 0
  local verifyAt = tonumber(savedScale.__raceResetPhysicalVerifyAt)
  if savedScale.__raceResetPhysicalCycleId == cycleId and verifyAt ~= nil then
    if Time.time < verifyAt then
      hybridRollbackPrivate.scheduleRaceResetCheck(verifyAt - Time.time)
      return true
    end
    savedScale.__raceResetPhysicalVerifyAt = nil
    if hybridRollbackPrivate.isRaceResetPoseVerified() then
      savedScale.__raceResetPoseVerifiedCycleId = cycleId
    elseif attemptCount >= RACE_RESET_MAX_ATTEMPTS then
      hybridRollbackPrivate.expireRaceResetTransaction()
      return false
    else
      local nextAttemptAt = tonumber(savedScale.__raceResetPhysicalNextAttemptAt)
        or -math.huge
      hybridRollbackPrivate.scheduleRaceResetCheck(math.max(
        RACE_RESET_CONFIRM_FALLBACK_SECONDS,
        nextAttemptAt - Time.time
      ))
      return true
    end
  end

  if savedScale.__raceResetPoseVerifiedCycleId ~= cycleId then
    if attemptCount >= RACE_RESET_MAX_ATTEMPTS then
      hybridRollbackPrivate.expireRaceResetTransaction()
      return false
    end
    local nextAttemptAt = tonumber(savedScale.__raceResetPhysicalNextAttemptAt)
      or -math.huge
    if Time.time < nextAttemptAt then
      hybridRollbackPrivate.scheduleRaceResetCheck(nextAttemptAt - Time.time)
      return true
    end
    if not isLocalVehicleOwner() then
      hybridRollbackPrivate.scheduleRaceResetCheck(RACE_RESET_CONFIRM_FALLBACK_SECONDS)
      return true
    end

    -- Exactly one initial write and at most two retries for this owner/cycle.
    attemptCount = attemptCount + 1
    savedScale.__raceResetPhysicalCycleId = cycleId
    savedScale.__raceResetPhysicalAttemptCount = attemptCount
    savedScale.__raceResetPhysicalLastAttemptAt = Time.time
    savedScale.__raceResetPhysicalNextAttemptAt = Time.time + RACE_RESET_RETRY_SECONDS
    local moved = pcall(function()
      rb.velocity = Vector3.zero
      rb.angularVelocity = Vector3.zero
      rb.isKinematic = true
      rb.position = spawnPosition
      rb.rotation = spawnRotation
      self.transform.position = spawnPosition
      self.transform.rotation = spawnRotation
      UnityEngine.Physics.SyncTransforms()
      rb.velocity = Vector3.zero
      rb.angularVelocity = Vector3.zero
      rb.isKinematic = false
      rb.useGravity = true
      UnityEngine.Physics.SyncTransforms()
      rb:WakeUp()
    end)
    if not moved then
      savedScale.__raceResetPhysicalVerifyAt = nil
      hybridRollbackPrivate.scheduleRaceResetCheck(RACE_RESET_RETRY_SECONDS)
      return true
    end
    savedScale.__raceResetPhysicalVerifyAt = Time.time + RACE_RESET_VERIFY_DELAY_SECONDS
    pcall(function()
      respawnHideUntil = nil
      setRendererVisible(self.transform, true)
    end)
    hybridRollbackPrivate.scheduleRaceResetCheck(RACE_RESET_VERIFY_DELAY_SECONDS)
    return true
  end

  -- Physical reset is first priority. Once the spawn pose is confirmed, clear
  -- Taken and OccupantActorId together before publishing completion.
  if not hybridRollbackPrivate.ensureRaceResetSeatStatesCleared(cycleId) then
    hybridRollbackPrivate.scheduleRaceResetCheck(RACE_RESET_CONFIRM_FALLBACK_SECONDS)
    return true
  end
  savedScale.__raceResetSeatsCleared = true
  savedScale.__raceResetAckAttemptCount = 1
  if publishCompletedRaceResetCycleId(cycleId) then
    return finishRaceResetTransaction(cycleId)
  end
  hybridRollbackPrivate.scheduleRaceResetCheck(RACE_RESET_CONFIRM_FALLBACK_SECONDS)
  return true
end

local function updateRaceManagerReset()
  if pendingRaceResetCycleId ~= nil
    and pendingRaceResetCycleId < lastAcceptedRaceResetCycleId then
    hybridRollbackPrivate.supersedeRaceResetTransaction()
    return
  end
  if not raceResetLocked and pendingRaceResetCycleId == nil then return end
  if lastAcceptedRaceResetCycleId >= RACE_RESET_MIN_TOKEN then
    local completed = readSynchronizedCompletedRaceResetCycleId(lastAcceptedRaceResetCycleId)
    if completed >= lastAcceptedRaceResetCycleId then
      if raceResetLocked then finishRaceResetTransaction(lastAcceptedRaceResetCycleId) end
      return
    end
  end
  if savedScale.__raceResetDeadlineAt ~= nil and Time.time >= savedScale.__raceResetDeadlineAt then
    hybridRollbackPrivate.expireRaceResetTransaction()
    return
  end
  if pendingRaceResetCycleId ~= nil and raceResetExecuteAt ~= nil
    and Time.time >= raceResetExecuteAt then
    performRaceResetPhysics()
  end
end

function RaceManagerCommitReset(rawCycleId)
  local cycleId = normalizeRaceResetCycleId(rawCycleId)
  if cycleId == nil then return false end
  hybridRollbackPrivate.readSynchronizedResetEpoch()
  if cycleId ~= lastAcceptedRaceResetCycleId then return false end
  local terminalCycle = tonumber(savedScale.__raceResetTerminalCycleId) or 0
  local terminalStatus = tostring(savedScale.__raceResetTerminalStatus or "")
  if terminalCycle == cycleId then return terminalStatus == "COMPLETED" end
  if savedScale.__raceResetFailedCycleId == cycleId then return false end
  if savedScale.__raceResetDeadlineCycleId ~= cycleId
    or savedScale.__raceResetDeadlineAt == nil
    or not isLocalVehicleOwner() then
    return false
  end
  if readSynchronizedCompletedRaceResetCycleId(cycleId) >= cycleId then
    return finishRaceResetTransaction(cycleId)
  end
  if Time.time >= savedScale.__raceResetDeadlineAt then return false end
  pendingRaceResetCycleId = cycleId
  raceResetLocked = true
  pcall(function() self:DisableInteraction() end)
  removeInteractionButtons()
  local nativeGuard = savedScale.__raceResetNativeExitGuard
  if type(nativeGuard) ~= "table" or nativeGuard.cycleId ~= cycleId then
    hybridRollbackPrivate.captureRaceResetNativeExitGuard(cycleId)
  end
  if raceResetExecuteAt == nil then raceResetExecuteAt = Time.time + RACE_RESET_PHYSICS_DELAY_SECONDS end
  return true
end

function RaceManagerReset(rawCycleId, rawWindowRemainingMilliseconds)
  local cycleId = normalizeRaceResetCycleId(rawCycleId)
  if cycleId == nil then return false end
  local remainingMilliseconds = math.floor(tonumber(rawWindowRemainingMilliseconds) or 0)
  if remainingMilliseconds <= 0 or remainingMilliseconds > 5000 then return false end
  hybridRollbackPrivate.readSynchronizedResetEpoch()
  local terminalCycle = tonumber(savedScale.__raceResetTerminalCycleId) or 0
  if terminalCycle == cycleId or savedScale.__raceResetFailedCycleId == cycleId then return true end
  local expiredObservedCleanup = math.floor(tonumber(savedScale.__raceResetExpiredObservedCleanupCycleId) or 0)
  if expiredObservedCleanup >= cycleId then return true end
  local locallyCleaned = math.floor(tonumber(savedScale.__raceResetLocalCleanupCycleId) or 0)
  local completedObserved = math.max(
    math.floor(tonumber(lastCompletedRaceResetCycleId) or 0),
    math.floor(tonumber(savedScale.__raceResetObservedCompletedCycleId) or 0)
  )
  if locallyCleaned >= cycleId and completedObserved >= cycleId then return true end

  if cycleId < lastAcceptedRaceResetCycleId then return true end
  if cycleId == lastAcceptedRaceResetCycleId
    and savedScale.__raceResetDeadlineCycleId == cycleId then
    if readSynchronizedCompletedRaceResetCycleId(cycleId) >= cycleId then
      return finishRaceResetTransaction(cycleId)
    end
    if savedScale.__raceResetFailedCycleId == cycleId then return true end
    if isLocalVehicleOwner() then
      RaceManagerCommitReset(cycleId)
    elseif DouyinNetService ~= nil and DouyinNetService.isNetworkSettled then
      pcall(function() self:SendMessageToOwner("RaceManagerCommitReset", tostring(cycleId)) end)
    end
    return true
  end

  lastAcceptedRaceResetCycleId = cycleId
  savedScale.__raceResetDeadlineCycleId = cycleId
  savedScale.__raceResetDeadlineAt = Time.time + remainingMilliseconds / 1000
  savedScale.__raceResetPhysicalAttemptCount = 0
  savedScale.__raceResetPhysicalLastAttemptAt = -math.huge
  savedScale.__raceResetPhysicalNextAttemptAt = -math.huge
  savedScale.__raceResetPhysicalVerifyAt = nil
  savedScale.__raceResetPoseVerifiedCycleId = 0
  savedScale.__raceResetAckAttemptCount = 0
  savedScale.__raceResetSeatClearAttemptCount = 0
  savedScale.__raceResetSeatClearNextWriteAt = -math.huge
  savedScale.__raceResetSeatClearLastWriteAt = -math.huge
  savedScale.__raceResetSeatClearWriteSucceeded = false
  savedScale.__seatClearConfirmations = {}
  savedScale.__raceResetSeatsCleared = false
  savedScale.__raceResetFailedCycleId = 0
  savedScale.__raceResetExpiredHandledCycleId = 0
  savedScale.__raceResetTerminalCycleId = 0
  savedScale.__raceResetTerminalStatus = nil
  raceResetLocked = true
  pcall(function() self:DisableInteraction() end)
  removeInteractionButtons()
  hybridRollbackPrivate.captureRaceResetNativeExitGuard(cycleId)
  hybridRollbackPrivate.clearResetIntent()

  -- End the local native seat immediately. RaceManagerCommitReset schedules
  -- the Owner's physical write one second later without a sync round-trip.
  if currentPlayer ~= nil and localSeatId ~= nil then
    local exitingActor = currentPlayer
    local exitingSeat = localSeatId
    local stationObject = getSeatStationGameObject(exitingSeat)
    if stationObject ~= nil
      and hybridRollbackPrivate.actorSeatRelation(exitingActor, exitingSeat) == "TARGET" then
      pcall(function() exitingActor:StandUp(stationObject) end)
    end
    VehicleSeatStationExited(exitingActor, exitingSeat, true)
  end
  savedScale.__raceResetLocalCleanupCycleId = math.max(
    math.floor(tonumber(savedScale.__raceResetLocalCleanupCycleId) or 0),
    cycleId
  )

  if isLocalVehicleOwner() then
    RaceManagerCommitReset(cycleId)
  elseif DouyinNetService ~= nil and DouyinNetService.isNetworkSettled then
    pcall(function() self:SendMessageToOwner("RaceManagerCommitReset", tostring(cycleId)) end)
  end
  return true
end

function GetLastRaceResetCycleId()
  return lastAcceptedRaceResetCycleId
end

function GetLastCompletedRaceResetCycleId()
  return readSynchronizedCompletedRaceResetCycleId(lastAcceptedRaceResetCycleId)
end

function HasCompletedRaceResetCycle(rawCycleId)
  local cycleId = normalizeRaceResetCycleId(rawCycleId)
  if cycleId == nil then return false end
  return readSynchronizedCompletedRaceResetCycleId(cycleId) >= cycleId
end

function GetRaceResetDebugStatus()
  return pendingRaceResetCycleId or 0,
    raceResetLocked,
    raceResetExecuteAt or -1,
    raceResetRestoreAt or -1,
    isLocalVehicleOwner(),
    savedScale.__raceResetPhysicalCycleId == lastAcceptedRaceResetCycleId,
    rb ~= nil and rb.isKinematic ~= true,
    lastAcceptedRaceResetCycleId,
    readSynchronizedCompletedRaceResetCycleId(lastAcceptedRaceResetCycleId),
    tonumber(savedScale.__raceResetPhysicalAttemptCount) or 0,
    tonumber(savedScale.__raceResetAckAttemptCount) or 0,
    savedScale.__raceResetDeadlineAt or -1,
    savedScale.__raceResetSeatsCleared == true,
    1,
    0,
    false
end

function OnNetSpawned()
  netSpawned = true
  setupSeatVarSync()
  sanitizeSynchronizedRaceResetCompletion()
  readSynchronizedCompletedRaceResetCycleId(lastAcceptedRaceResetCycleId)
end

function Start()
  rb = self.gameObject:GetComponent(typeof(UnityEngine.Rigidbody))
  if rb == nil then
    rb = self.gameObject:AddComponent(typeof(UnityEngine.Rigidbody))
  end
  if rb ~= nil then
    -- Apply vehicle physics explicitly. The editor metadata does not reliably
    -- carry mass and centre-of-mass into local-run for archived modules.
    rb.mass = 420
    rb.drag = 0.6
    rb.angularDrag = 5
    rb.useGravity = true
    rb.isKinematic = false
    rb.centerOfMass = Vector3(0, 0.128784, -0.0117076)
    rb.maxAngularVelocity = maxAngularVelocity

    local meshColliders = self.gameObject:GetComponentsInChildren(typeof(UnityEngine.MeshCollider), true)
    for colliderIndex = 0, meshColliders.Length - 1 do
      if meshColliders[colliderIndex] ~= nil then
        meshColliders[colliderIndex].enabled = false
      end
    end

    -- Keep physics lightweight: one compound-equivalent chassis proxy rather
    -- than MeshColliders on the 215 high-density render meshes.
    local boxColliders = self.gameObject:GetComponents(typeof(UnityEngine.BoxCollider))
    local solidCollider = nil
    for colliderIndex = 0, boxColliders.Length - 1 do
      local candidate = boxColliders[colliderIndex]
      if candidate ~= nil and not candidate.isTrigger then
        solidCollider = candidate
        break
      end
    end
    if solidCollider == nil then
      solidCollider = self.gameObject:AddComponent(typeof(UnityEngine.BoxCollider))
    end
    solidCollider.isTrigger = false
    solidCollider.center = Vector3(0, 0.175614, 0)
    solidCollider.size = Vector3(0.515135, 0.304398, 0.749287)
    solidCollider.enabled = true
  else
    UnityEngine.Debug.LogWarning("LP-14「DESSERT·甜品拟物」双人卡丁车: root Rigidbody missing; driving is disabled.")
  end
  local rootBoxes = self.gameObject:GetComponents(typeof(UnityEngine.BoxCollider))
  for colliderIndex = 0, rootBoxes.Length - 1 do
    if rootBoxes[colliderIndex] ~= nil and rootBoxes[colliderIndex].isTrigger then
      proximityCollider = rootBoxes[colliderIndex]
      break
    end
  end
  if proximityCollider == nil then
    proximityCollider = self.gameObject:AddComponent(typeof(UnityEngine.BoxCollider))
    proximityCollider.isTrigger = true
    proximityCollider.center = Vector3(0, 0.234152, 0)
    proximityCollider.size = Vector3(0.819533, 0.702457, 1.21759)
    proximityCollider.enabled = true
  end
  spawnPosition = self.transform.position
  spawnRotation = self.transform.rotation
  setupWheelVisuals()
  setupTrailEffect()
  if not setupEngineAudioSource() then
    UnityEngine.Debug.LogWarning(tostring(self.gameObject.name) .. " engine audio source setup failed")
  end
  for i = 1, #seatConfigs do
    seatConfigs[i].transform = findChild(self.transform, seatConfigs[i].anchorPath)
    if seatConfigs[i].transform == nil then
      -- The editor intentionally persists only the mesh-bearing GLB root.
      -- Recreate non-rendering seat anchors at runtime so save/reload cannot
      -- strip the multiplayer seating contract from the visual asset.
      local anchorName = string.match(seatConfigs[i].anchorPath, "([^/]+)$") or seatConfigs[i].anchorPath
      local anchorObject = UnityEngine.GameObject(anchorName)
      anchorObject.transform:SetParent(self.transform)
      anchorObject.transform.localRotation = Quaternion.identity
      anchorObject.transform.localScale = Vector3.one
      anchorObject.transform.localPosition = seatConfigs[i].fallbackPosition
      seatConfigs[i].transform = anchorObject.transform
    end
    if seatConfigs[i].stationPath ~= nil then
      seatConfigs[i].stationTransform = findChild(self.transform, seatConfigs[i].stationPath)
      if seatConfigs[i].stationTransform == nil then
        UnityEngine.Debug.LogError(
          tostring(self.gameObject.name) .. ": persistent station missing: " .. seatConfigs[i].stationPath
        )
      end
    else
      seatConfigs[i].stationTransform = self.transform
    end
  end
  registerMoveInputListeners()
  registerCameraAlignInputListeners()
  updateEmptyTimer()
  savedScale.__seatRuntimeStarted = true
  local observedCompleted = math.floor(tonumber(savedScale.__raceResetObservedCompletedCycleId) or 0)
  if observedCompleted > 0 and hybridRollbackPrivate.applyCompletedResetLocally ~= nil then
    pcall(function() hybridRollbackPrivate.applyCompletedResetLocally(observedCompleted) end)
  end
end

function OnDestroy()
  savedScale.__seatRuntimeStarted = false
  destroyTrailEffect()
  destroyEngineAudio()
  removeInteractionButtons()
  removeMoveInputListeners()
  removeCameraAlignInputListeners()
end

function OnDisable()
  hybridRollbackPrivate.sleepTrailEffect()
  hybridRollbackPrivate.trailDriverWasOccupied = false
  stopEngineAudio(true)
end

function OnActorTriggerEnter(actor)
  if actor == nil or not actor.isLocal then
    return
  end
  localActor = actor
  currentInside = true
  if raceResetLocked then
    self:DisableInteraction()
    removeInteractionButtons()
    return
  end
  self:EnableInteraction()
end

function OnActorTriggerExit(actor)
  if actor == nil or not actor.isLocal then
    return
  end
  currentInside = false
  if localSeatId == nil then
    localActor = nil
    self:DisableInteraction()
    removeInteractionButtons()
  end
end

function OnFocus(handType)
  isFocused = true
  if raceResetLocked then
    self:DisableInteraction()
    removeInteractionButtons()
    return
  end
  rebuildInteractionButtons()
end

function OnLostFocus(handType)
  isFocused = false
  removeInteractionButtons()
end

function OnInteractorButtonClick(index)
  if raceResetLocked or raceCompetitionLocked then return end
  local action = buttonActions[index]
  if action == nil or localActor == nil then
    return
  end
  if action.kind == "exit" then
    tryExitSeat()
    return
  end
  if action.kind ~= "sit" then return end
  requestSeatReservation(action.seatId)
end

function hybridRollbackPrivate.clearStaleCrossVehicleSeatState(actor, rawSeatId, rawActorId)
  local seatId = tostring(rawSeatId or "")
  local actorId = hybridRollbackPrivate.normalizeActorId(rawActorId)
  if actorId == 0 then actorId = hybridRollbackPrivate.actorNetworkId(actor) end
  local relation = hybridRollbackPrivate.actorSeatRelation(actor, seatId)
  if actor == nil or actorId == 0 or findSeatConfig(seatId) == nil
    or relation == "TARGET" then return false end

  -- This Actor is elsewhere or has an external parent. Clear only this vehicle's old
  -- bookkeeping and exact-ID synchronized state; never touch native seating,
  -- transform parenting, collision, or the other vehicle's control.
  local entries = pendingSeatEntries()
  for index = #entries, 1, -1 do
    local entry = entries[index]
    local entryActorId = hybridRollbackPrivate.normalizeActorId(entry.actorId)
    if entryActorId == 0 then entryActorId = hybridRollbackPrivate.actorNetworkId(entry.actor) end
    if entry.seatId == seatId and entryActorId == actorId then
      table.remove(entries, index)
      -- pendingRemoteSeats has no Actor field in the original implementation;
      -- remove one matching token only, so another Actor's newer callback is
      -- not accidentally consumed.
      for pendingIndex = 1, #pendingRemoteSeats do
        if pendingRemoteSeats[pendingIndex] == seatId then
          table.remove(pendingRemoteSeats, pendingIndex)
          break
        end
      end
    end
  end
  for trackedActor, trackedSeatId in pairs(actorSeatIds) do
    if trackedSeatId == seatId
      and hybridRollbackPrivate.actorNetworkId(trackedActor) == actorId then
      seatedActors[trackedActor] = nil
      actorSeatIds[trackedActor] = nil
      if relation ~= "THIS_VEHICLE" then savedScale[trackedActor] = nil end
      hybridRollbackPrivate.clearProcessedSeatEntry(trackedActor)
    end
  end
  local processedLedger = hybridRollbackPrivate.processedSeatEntryLedger()
  for trackedActor, trackedSeatId in pairs(processedLedger) do
    if trackedSeatId == seatId
      and hybridRollbackPrivate.actorNetworkId(trackedActor) == actorId then
      processedLedger[trackedActor] = nil
    end
  end
  requestSeatRelease(seatId, actorId)
  requestSeatClaimCancel(seatId, actorId)

  local localOk, isLocalActor = pcall(function() return actor.isLocal end)
  local localStateMatches = (localOk and isLocalActor == true)
    or localSeatActorId == actorId or currentPlayer == actor
  if localStateMatches and (localSeatId == seatId or selectedSeatId == seatId) then
    local oldSeatId = localSeatId or selectedSeatId
    local commit = savedScale.__localSeatCommit
    if type(commit) == "table" and commit.seatId == seatId and commit.actorId == actorId then
      savedScale.__localSeatCommit = nil
    end
    local claim = savedScale.__localSeatClaim
    if type(claim) == "table" and claim.seatId == seatId
      and hybridRollbackPrivate.normalizeActorId(claim.actorId) == actorId then
      savedScale.__localSeatClaim = nil
    end
    local rollback = savedScale.__localSitRollback
    if type(rollback) == "table" and rollback.seatId == seatId
      and hybridRollbackPrivate.normalizeActorId(rollback.actorId) == actorId then
      savedScale.__localSitRollback = nil
    end
    currentPlayer = nil
    localSeatId = nil
    localSeatActorId = nil
    selectedSeatId = nil
    selectedSeatAnchor = nil
    selectedSeatIndex = -1
    seatReservationPending = false
    seatReservationDeadline = -math.huge
    ownershipPending = false
    ownershipPendingDeadline = -math.huge
    savedScale.__seatWaitingForNetwork = false
    savedScale.__driverWaitingForNetwork = false
    if oldSeatId == "driver" then
      clearDriveInput()
      if isLocalVehicleOwner() then stopHorizontalVelocity() end
    end
    localActor = actor
    if currentInside and not raceResetLocked then self:EnableInteraction() else self:DisableInteraction() end
    removeInteractionButtons()
  end
  updateEmptyTimer()
  return true
end

function hybridRollbackPrivate.clearPriorSeatForConfirmedTransition(actor, rawPriorSeat, rawNextSeat, rawActorId)
  local priorSeat = tostring(rawPriorSeat or "")
  local nextSeat = tostring(rawNextSeat or "")
  local actorId = hybridRollbackPrivate.normalizeActorId(rawActorId)
  if actor == nil or actorId == 0 or priorSeat == nextSeat
    or findSeatConfig(priorSeat) == nil or findSeatConfig(nextSeat) == nil then return false end
  local stateOk, sitting = pcall(function() return actor:IsSitting() end)
  if not stateOk or sitting ~= true
    or hybridRollbackPrivate.actorSeatRelation(actor, nextSeat) ~= "TARGET" then return false end

  -- A newer native Enter for another seat on this same vehicle can overtake
  -- the old Exit. Remove only the old seat's Actor-ID bookkeeping; never
  -- StandUp, reparent, move, or change collision while processing the new seat.
  local entries = pendingSeatEntries()
  for index = #entries, 1, -1 do
    local entry = entries[index]
    local entryActorId = hybridRollbackPrivate.normalizeActorId(entry.actorId)
    if entryActorId == 0 then entryActorId = hybridRollbackPrivate.actorNetworkId(entry.actor) end
    if entry.seatId == priorSeat and entryActorId == actorId then
      table.remove(entries, index)
      for pendingIndex = 1, #pendingRemoteSeats do
        if pendingRemoteSeats[pendingIndex] == priorSeat then
          table.remove(pendingRemoteSeats, pendingIndex)
          break
        end
      end
    end
  end
  for trackedActor, trackedSeatId in pairs(actorSeatIds) do
    if trackedSeatId == priorSeat
      and hybridRollbackPrivate.actorNetworkId(trackedActor) == actorId then
      seatedActors[trackedActor] = nil
      actorSeatIds[trackedActor] = nil
      hybridRollbackPrivate.clearProcessedSeatEntry(trackedActor)
    end
  end
  local processedLedger = hybridRollbackPrivate.processedSeatEntryLedger()
  for trackedActor, trackedSeatId in pairs(processedLedger) do
    if trackedSeatId == priorSeat
      and hybridRollbackPrivate.actorNetworkId(trackedActor) == actorId then
      processedLedger[trackedActor] = nil
    end
  end
  requestSeatRelease(priorSeat, actorId)
  requestSeatClaimCancel(priorSeat, actorId)

  local localOk, isLocalActor = pcall(function() return actor.isLocal end)
  if (localOk and isLocalActor == true) or localSeatActorId == actorId or currentPlayer == actor then
    local commit = savedScale.__localSeatCommit
    if type(commit) == "table" and commit.seatId == priorSeat and commit.actorId == actorId then
      savedScale.__localSeatCommit = nil
    end
    local claim = savedScale.__localSeatClaim
    if type(claim) == "table" and claim.seatId == priorSeat
      and hybridRollbackPrivate.normalizeActorId(claim.actorId) == actorId then
      savedScale.__localSeatClaim = nil
    end
    local rollback = savedScale.__localSitRollback
    if type(rollback) == "table" and rollback.seatId == priorSeat
      and hybridRollbackPrivate.normalizeActorId(rollback.actorId) == actorId then
      savedScale.__localSitRollback = nil
    end
    if localSeatId == priorSeat then
      currentPlayer = nil
      localSeatId = nil
      localSeatActorId = nil
    end
    if selectedSeatId == priorSeat then
      selectedSeatId = nil
      selectedSeatAnchor = nil
      selectedSeatIndex = -1
    end
    if priorSeat == "driver" then clearDriveInput() end
    localActor = actor
  end
  updateEmptyTimer()
  return true
end

function hybridRollbackPrivate.rejectSeatEntry(actor, seatId, rawActorId, stationObject, busy)
  local actorId = hybridRollbackPrivate.normalizeActorId(rawActorId)
  if actor ~= nil then
    local relation = hybridRollbackPrivate.actorSeatRelation(actor, seatId)
    local parentOk, parent = pcall(function() return actor.gameObject.transform.parent end)
    if relation == "OTHER" or relation == "THIS_VEHICLE"
      or (relation == "UNKNOWN" and parentOk and parent ~= nil) then
      hybridRollbackPrivate.clearStaleCrossVehicleSeatState(actor, seatId, actorId)
      return false
    end
    if relation == "UNKNOWN" and not parentOk then return false end
  end
  if actor ~= nil and actor.isLocal then
    local claim = savedScale.__localSeatClaim
    if type(claim) == "table" and claim.seatId == seatId
      and hybridRollbackPrivate.normalizeActorId(claim.actorId) == actorId then
      requestSeatClaimCancel(seatId, actorId)
      savedScale.__localSeatClaim = nil
    end
    local commit = savedScale.__localSeatCommit
    if type(commit) == "table" and commit.seatId == seatId and commit.actorId == actorId then
      savedScale.__localSeatCommit = nil
    end
    if localSeatId == nil then clearPendingSeatSelection() end
    if stationObject ~= nil then pcall(function() actor:StandUp(stationObject) end) end
    if busy == true then hybridRollbackPrivate.showSeatOccupiedFeedback() end
  end
  if actor ~= nil then
    local relation = hybridRollbackPrivate.actorSeatRelation(actor, seatId)
    local parentOk, parent = pcall(function() return actor.gameObject.transform.parent end)
    if relation == "TARGET" or (parentOk and parent == nil) then
      setActorColliderEnabled(actor, true)
    end
  end
  if currentInside and localSeatId == nil and not raceResetLocked then rebuildInteractionButtons() end
  return false
end

function hybridRollbackPrivate.isCurrentLocalSeatAttempt(actor, seatId, rawActorId, claim, priorSeat)
  local actorId = hybridRollbackPrivate.normalizeActorId(rawActorId)
  local localOk, isLocalActor = pcall(function() return actor ~= nil and actor.isLocal end)
  if not localOk or isLocalActor ~= true or actorId == 0 or type(claim) ~= "table"
    or claim ~= savedScale.__localSeatClaim or claim.seatId ~= seatId
    or hybridRollbackPrivate.normalizeActorId(claim.actorId) ~= actorId
    or claim.claimed ~= true or claim.sitDownIssued ~= true
    or math.floor(tonumber(claim.resetCycleId) or -1) ~= lastAcceptedRaceResetCycleId
    or (tonumber(claim.expiresAt) or -math.huge) <= Time.time
    or not seatReservationPending or Time.time >= seatReservationDeadline
    or selectedSeatId ~= seatId
    or hybridRollbackPrivate.normalizeActorId(localSeatActorId) ~= actorId
    or localSeatId ~= nil or savedScale.__localSitRollback ~= nil
    or raceResetLocked or not hybridRollbackPrivate.seatRequestsAllowedForObservedReset()
    or seatTakenCache[seatId] ~= true
    or hybridRollbackPrivate.readSeatOccupantId(seatId) ~= 0
    or (priorSeat ~= nil and priorSeat ~= seatId) then return false end
  return true
end

function VehicleSeatStationEntered(actor, rawSeatId, handType)
  if actor == nil then return false end
  local seatId = tostring(rawSeatId or "")
  local cfg, seatIndex = findSeatConfig(seatId)
  local target = cfg ~= nil and cfg.transform or nil
  local stationObject = getSeatStationGameObject(seatId)
  if target == nil or stationObject == nil then
    return hybridRollbackPrivate.rejectSeatEntry(actor, seatId, 0, stationObject, false)
  end
  local actorId = hybridRollbackPrivate.actorNetworkId(actor)
  -- A confirmed native re-entry of our frozen local rider is not a new seat
  -- claim. Do not run the generic locked-entry rejection (which calls StandUp).
  if not raceResetLocked and hybridRollbackPrivate.repairRaceCompetitionSeat ~= nil then
    local locked, _, lockedActorId, lockedSeatId = GetRaceSessionLocalSeatLock()
    if locked and actor == currentPlayer and actorId == lockedActorId and seatId == lockedSeatId then
      local ok, sitting = pcall(function() return actor:IsSitting() end)
      if ok and sitting == true then
        pcall(function() alignActorHipsToSeat(actor, target) end)
        setActorColliderEnabled(actor, false)
        savedScale.__raceCompetitionReseat = nil
      end
      return true
    end
  end
  if actorId == 0 or raceResetLocked or raceCompetitionLocked
    or not hybridRollbackPrivate.seatRequestsAllowedForObservedReset() then
    return hybridRollbackPrivate.rejectSeatEntry(actor, seatId, actorId, stationObject, false)
  end
  local ledger = hybridRollbackPrivate.processedSeatEntryLedger()
  local priorSeat = ledger[actor]
  if hybridRollbackPrivate.isSeatEntryProcessed(actor, seatId) then
    local relation = hybridRollbackPrivate.actorSeatRelation(actor, seatId)
    local trackedTarget = seatedActors[actor]
    local trackedSeat = actorSeatIds[actor]
    local occupantId = hybridRollbackPrivate.readSeatOccupantId(seatId)
    local localStateMatches = actor.isLocal and localSeatId == seatId
      and hybridRollbackPrivate.normalizeActorId(localSeatActorId) == actorId
    local remoteStateMatches = not actor.isLocal and occupantId == actorId
    if relation == "TARGET" and trackedTarget == target and trackedSeat == seatId
      and (localStateMatches or remoteStateMatches) then return true end

    -- A prior Enter without its matching Exit is stale evidence, not proof that
    -- this new native Enter has already rebuilt control/UI state. Purge only the
    -- matching Actor-ID/seat bookkeeping, then process the real callback below.
    for trackedActor, trackedSeatId in pairs(ledger) do
      if trackedSeatId == seatId
        and hybridRollbackPrivate.actorNetworkId(trackedActor) == actorId then
        ledger[trackedActor] = nil
        if actorSeatIds[trackedActor] == seatId then
          seatedActors[trackedActor] = nil
          actorSeatIds[trackedActor] = nil
          if relation ~= "TARGET" and relation ~= "THIS_VEHICLE" then
            savedScale[trackedActor] = nil
          end
        end
      end
    end
    priorSeat = nil
  end
  if priorSeat == nil then
    local _, trackedPriorSeat = hybridRollbackPrivate.trackedSeatForActorId(actorId)
    priorSeat = trackedPriorSeat
  end

  local rollback = savedScale.__localSitRollback
  if actor.isLocal and type(rollback) == "table" and rollback.seatId == seatId
    and hybridRollbackPrivate.normalizeActorId(rollback.actorId) == actorId then
    return hybridRollbackPrivate.rejectSeatEntry(actor, seatId, actorId, stationObject, false)
  end

  local earlyClaim = savedScale.__localSeatClaim
  local earlyClaimMatches = actor.isLocal and type(earlyClaim) == "table"
    and earlyClaim.seatId == seatId
    and hybridRollbackPrivate.normalizeActorId(earlyClaim.actorId) == actorId
  if earlyClaimMatches and earlyClaim.sitDownIssued ~= true then
    local earlyRelation = hybridRollbackPrivate.actorSeatRelation(actor, seatId)
    local parentOk, parent = pcall(function() return actor.gameObject.transform.parent end)
    if earlyRelation == "OTHER" or earlyRelation == "THIS_VEHICLE"
      or (earlyRelation == "UNKNOWN" and parentOk and parent ~= nil) then
      hybridRollbackPrivate.clearStaleCrossVehicleSeatState(actor, seatId, actorId)
      return false
    end
    if earlyRelation == "UNKNOWN" and not parentOk then return false end
    local staleStateOk, staleSitting = pcall(function() return actor:IsSitting() end)
    if staleStateOk and staleSitting == true then
      hybridRollbackPrivate.beginLocalSitRollback("STALE_ENTER")
    elseif earlyRelation == "TARGET" or (parentOk and parent == nil) then
      setActorColliderEnabled(actor, true)
    end
    return false
  end

  local sittingOk, sitting = pcall(function() return actor:IsSitting() end)
  if not sittingOk and not actor.isLocal then
    local unresolvedRelation = hybridRollbackPrivate.actorSeatRelation(actor, seatId)
    local parentOk, parent = pcall(function() return actor.gameObject.transform.parent end)
    if unresolvedRelation == "OTHER" or unresolvedRelation == "THIS_VEHICLE"
      or (unresolvedRelation == "UNKNOWN" and parentOk and parent ~= nil) then
      hybridRollbackPrivate.clearStaleCrossVehicleSeatState(actor, seatId, actorId)
      return false
    end
    queuePendingSeatEntry(actor, seatId, handType)
    if unresolvedRelation == "TARGET" then setActorColliderEnabled(actor, false) end
    return true
  end
  if not sittingOk or sitting ~= true then
    local earlyRelation = hybridRollbackPrivate.actorSeatRelation(actor, seatId)
    local parentOk, parent = pcall(function() return actor.gameObject.transform.parent end)
    local safeEarlyRelation = earlyRelation == "TARGET"
      or (earlyRelation == "UNKNOWN" and parentOk and parent == nil)
    if safeEarlyRelation
      and hybridRollbackPrivate.isCurrentLocalSeatAttempt(
        actor, seatId, actorId, earlyClaim, priorSeat
      ) then
      queuePendingSeatEntry(actor, seatId, handType, true)
      return true
    end
    if safeEarlyRelation and not actor.isLocal then
      queuePendingSeatEntry(actor, seatId, handType)
      return true
    end
    return hybridRollbackPrivate.rejectSeatEntry(actor, seatId, actorId, stationObject, false)
  end
  local seatRelation = hybridRollbackPrivate.actorSeatRelation(actor, seatId)
  local entryNeedsAlignment = false
  local occupantId = hybridRollbackPrivate.readSeatOccupantId(seatId)
  if seatRelation == "OTHER" then
    hybridRollbackPrivate.clearStaleCrossVehicleSeatState(actor, seatId, actorId)
    return false
  end
  if seatRelation ~= "TARGET" then
    local parentOk, parent = pcall(function() return actor.gameObject.transform.parent end)
    local currentLocalUnparentedEntry =
      hybridRollbackPrivate.isCurrentLocalSeatAttempt(
        actor, seatId, actorId, earlyClaim, priorSeat
      )
      and seatRelation == "UNKNOWN" and parentOk and parent == nil
    local confirmedSynchronizedUnparentedEntry = occupantId == actorId
      and seatRelation == "UNKNOWN"
      and parentOk and parent == nil
    -- The SDK can invoke OnSeatEntered before the Actor reaches its visual
    -- anchor. The exact live local attempt, or a remote callback already backed
    -- by this seat's synchronized Actor ID, may start presentation repair.
    if currentLocalUnparentedEntry or confirmedSynchronizedUnparentedEntry then
      entryNeedsAlignment = true
    elseif not actor.isLocal then
      queuePendingSeatEntry(actor, seatId, handType)
      return true
    else
      if earlyClaimMatches then hybridRollbackPrivate.beginLocalSitRollback("SEAT_RELATION") end
      requestSeatRelease(seatId, actorId)
      requestSeatClaimCancel(seatId, actorId)
      return false
    end
  end
  if priorSeat ~= nil and priorSeat ~= seatId
    and not hybridRollbackPrivate.clearPriorSeatForConfirmedTransition(
      actor, priorSeat, seatId, actorId
    ) then return false end

  if not actor.isLocal and occupantId ~= actorId then
    if occupantId == 0 then
      queuePendingSeatEntry(actor, seatId, handType)
      setActorColliderEnabled(actor, false)
      return true
    end
    return hybridRollbackPrivate.rejectSeatEntry(actor, seatId, actorId, stationObject, true)
  end

  local temporary = earlyClaim
  local matchingLocalClaim = type(temporary) == "table"
    and temporary.seatId == seatId
    and hybridRollbackPrivate.normalizeActorId(temporary.actorId) == actorId
    and temporary.claimed == true
  if actor.isLocal and occupantId ~= actorId and not matchingLocalClaim then
    return hybridRollbackPrivate.rejectSeatEntry(actor, seatId, actorId, stationObject, false)
  end
  if actor.isLocal and occupantId > 0 and occupantId ~= actorId then
    return hybridRollbackPrivate.rejectSeatEntry(actor, seatId, actorId, stationObject, true)
  end

  local existingActor = hybridRollbackPrivate.findTrackedSeatActor(seatId, true)
  if existingActor ~= nil and hybridRollbackPrivate.actorNetworkId(existingActor) ~= actorId then
    return hybridRollbackPrivate.rejectSeatEntry(actor, seatId, actorId, stationObject, true)
  end

  if actor.isLocal and seatId == "driver" then
    local owner = true
    if DouyinNetService ~= nil then
      owner = false
      if DouyinNetService.isNetworkSettled and netSpawned then
        pcall(function() owner = self:HasOwnership() end)
      end
    end
    if not owner then
      return hybridRollbackPrivate.rejectSeatEntry(actor, seatId, actorId, stationObject, false)
    end
  end

  if entryNeedsAlignment then
    if actor.isLocal then
      local actorPos = actor.gameObject.transform.position
      local carPos = self.transform.position
      savedBoardOffset = Vector3(actorPos.x - carPos.x, actorPos.y - carPos.y, actorPos.z - carPos.z)
      savedBoardRotation = actor.gameObject.transform.rotation
    end
    if savedScale[actor] == nil then savedScale[actor] = actor.gameObject.transform.localScale end
    pcall(function() alignActorHipsToSeat(actor, target) end)
  end

  removePendingRemoteSeat(seatId)
  hybridRollbackPrivate.markSeatEntryProcessed(actor, seatId)
  if actor.isLocal then
    if not entryNeedsAlignment then
      local actorPos = actor.gameObject.transform.position
      local carPos = self.transform.position
      savedBoardOffset = Vector3(actorPos.x - carPos.x, actorPos.y - carPos.y, actorPos.z - carPos.z)
      savedBoardRotation = actor.gameObject.transform.rotation
    end
    savedScale.__raceSessionLocalSeatGeneration = (tonumber(savedScale.__raceSessionLocalSeatGeneration) or 0) + 1
    currentPlayer = actor
    localActor = actor
    localSeatId = seatId
    localSeatActorId = actorId
    selectedSeatId = seatId
    selectedSeatAnchor = target
    selectedSeatIndex = seatIndex
    seatReservationPending = true
    seatReservationDeadline = Time.time + 3.0
    ownershipPending = false
    ownershipPendingDeadline = -math.huge
    if seatId == "driver" then
      clearDriveInput()
      if rb ~= nil then
        pcall(function()
          rb.isKinematic = false
          rb.useGravity = true
          rb:WakeUp()
        end)
      end
    end
    self:EnableInteraction()
    removeInteractionButtons()
  end

  if savedScale[actor] == nil then savedScale[actor] = actor.gameObject.transform.localScale end
  seatedActors[actor] = target
  actorSeatIds[actor] = seatId
  if not entryNeedsAlignment then
    pcall(function() alignActorHipsToSeat(actor, target) end)
  end
  setActorColliderEnabled(actor, false)
  updateEmptyTimer()
  if actor.isLocal then hybridRollbackPrivate.beginLocalSeatCommit(seatId, actorId) end
  return true
end

function OnSeatEntered(actor, handType)
  return VehicleSeatStationEntered(actor, "driver", handType)
end

function VehicleSeatStationExited(actor, rawSeatId, forceCurrentExit)
  if actor == nil then return false end
  if hybridRollbackPrivate.captureRecycleBeforeExit ~= nil then hybridRollbackPrivate.captureRecycleBeforeExit(actor) end
  local suppliedSeat = tostring(rawSeatId or "")
  local actorId = hybridRollbackPrivate.actorNetworkId(actor)
  local trackedSeat = actorSeatIds[actor]
  local relationSeat = trackedSeat or (findSeatConfig(suppliedSeat) ~= nil and suppliedSeat or localSeatId)
  local relation = relationSeat ~= nil
    and hybridRollbackPrivate.actorSeatRelation(actor, relationSeat) or "UNKNOWN"
  local parentOk, parent = pcall(function() return actor.gameObject.transform.parent end)
  if relationSeat ~= nil and (relation == "OTHER" or relation == "THIS_VEHICLE"
    or (relation == "UNKNOWN" and parentOk and parent ~= nil)) then
    return hybridRollbackPrivate.clearStaleCrossVehicleSeatState(actor, relationSeat, actorId)
  end
  if relation == "UNKNOWN" and not parentOk then
    -- A failed parent probe is not authority to move a possibly cross-vehicle Actor.
    return true
  end
  local stillSitting = hybridRollbackPrivate.actorIsActuallySitting(actor)
  -- Native Jump/StandUp has already happened when this callback arrives.
  -- Returning early alone is not a veto: repair only our exact frozen local
  -- rider, after the cross-vehicle/new-seat exclusions above.
  if forceCurrentExit ~= true and hybridRollbackPrivate.repairRaceCompetitionSeat ~= nil
    and hybridRollbackPrivate.repairRaceCompetitionSeat(actor, relationSeat) then return true end
  -- RETURN-REPAIR-0905: StandUp is asynchronous. Keep the native-seat relation
  -- and the local actor until IsSitting confirms exit; don't detach first.
  if forceCurrentExit == true and actor.isLocal == true and stillSitting then
    return false
  end
  if forceCurrentExit ~= true and stillSitting then
    -- A delayed exit from this vehicle must never pull a player out of a newer
    -- seat, including a seat on another vehicle. Owner health cleanup releases
    -- this vehicle's stale synchronized occupant independently.
    return true
  end
  if (trackedSeat == nil or trackedSeat == "") and forceCurrentExit == true
    and hybridRollbackPrivate.raceSessionCanFinishCapturedLocalExit ~= nil
    and hybridRollbackPrivate.raceSessionCanFinishCapturedLocalExit(actor, suppliedSeat) then
    -- A prior health cleanup may have cleared the ledger before the native
    -- exit. The captured same-generation ride proves this remaining local state.
    trackedSeat = suppliedSeat
  end
  if trackedSeat == nil or trackedSeat == "" then
    if forceCurrentExit ~= true and findSeatConfig(suppliedSeat) ~= nil then
      local pendingEntered = actorId > 0 and hybridRollbackPrivate.hasPendingSeatEntry ~= nil
        and hybridRollbackPrivate.hasPendingSeatEntry(actorId, suppliedSeat)
      local temporary = savedScale.__localSeatClaim
      local localAttempt = actor.isLocal and type(temporary) == "table"
        and temporary.seatId == suppliedSeat
        and hybridRollbackPrivate.normalizeActorId(temporary.actorId) == actorId
        and seatReservationPending
      local ownerClaim = hybridRollbackPrivate.activeSeatClaim(suppliedSeat)
      local ownerAttempt = type(ownerClaim) == "table" and ownerClaim.actorId == actorId
      if pendingEntered or localAttempt or ownerAttempt then
        return true
      end
    end
    if findSeatConfig(suppliedSeat) ~= nil and actorId > 0
      and (actor.isLocal or isLocalVehicleOwner()) then
      requestSeatRelease(suppliedSeat, actorId)
      requestSeatClaimCancel(suppliedSeat, actorId)
    end
    removePendingSeatEntriesForActor(actor, suppliedSeat)
    hybridRollbackPrivate.clearProcessedSeatEntry(actor)
    local relation = findSeatConfig(suppliedSeat) ~= nil
      and hybridRollbackPrivate.actorSeatRelation(actor, suppliedSeat) or "UNKNOWN"
    local parentOk, parent = pcall(function() return actor.gameObject.transform.parent end)
    if relation == "TARGET" or (parentOk and parent == nil) then
      setActorColliderEnabled(actor, true)
    end
    return true
  end
  if suppliedSeat ~= "" and trackedSeat ~= suppliedSeat then
    -- A delayed event for an older seat never clears the current seat.
    return true
  end

  if forceCurrentExit ~= true then
    local ownerClaim = hybridRollbackPrivate.activeSeatClaim(trackedSeat)
    local temporary = savedScale.__localSeatClaim
    local newAttempt = (type(ownerClaim) == "table" and ownerClaim.actorId == actorId)
      or (actor.isLocal and type(temporary) == "table" and temporary.seatId == trackedSeat
        and hybridRollbackPrivate.normalizeActorId(temporary.actorId) == actorId
        and seatReservationPending)
    if newAttempt then return true end
  end

  local shouldRelease = actorId > 0 and (actor.isLocal or isLocalVehicleOwner())
  seatedActors[actor] = nil
  actorSeatIds[actor] = nil
  hybridRollbackPrivate.clearProcessedSeatEntry(actor)
  removePendingSeatEntriesForActor(actor, trackedSeat)
  removePendingRemoteSeat(trackedSeat)
  placeActorAtStandPoint(actor)
  setActorColliderEnabled(actor, true)
  if shouldRelease then
    local clearedDirectly = false
    if forceCurrentExit == true and isLocalVehicleOwner()
      and hybridRollbackPrivate.readSeatOccupantId(trackedSeat) == actorId then
      clearedDirectly = hybridRollbackPrivate.clearSeatOfficialState(trackedSeat)
    end
    if not clearedDirectly then requestSeatRelease(trackedSeat, actorId) end
    requestSeatClaimCancel(trackedSeat, actorId)
  end

  if actor.isLocal then
    savedScale.__localSeatCommit = nil
    savedScale.__localSeatClaim = nil
    currentPlayer = nil
    localSeatId = nil
    localSeatActorId = nil
    selectedSeatId = nil
    selectedSeatAnchor = nil
    selectedSeatIndex = -1
    seatReservationPending = false
    seatReservationDeadline = -math.huge
    ownershipPending = false
    ownershipPendingDeadline = -math.huge
    if trackedSeat == "driver" then
      clearDriveInput()
      if isLocalVehicleOwner() then stopHorizontalVelocity() end
    end
    if currentInside and not raceResetLocked then
      localActor = actor
      self:EnableInteraction()
    else
      self:DisableInteraction()
    end
    removeInteractionButtons()
  end
  updateEmptyTimer()
  return true
end

function OnSeatExited(actor)
  return VehicleSeatStationExited(actor, "driver")
end

function OnOwnershipTransferred()
  ownershipPending = false
  ownershipPendingDeadline = -math.huge
  local nowOwner = isLocalVehicleOwner()
  if hybridRollbackPrivate.readSynchronizedResetEpoch ~= nil then
    hybridRollbackPrivate.readSynchronizedResetEpoch()
  end
  savedScale.__seatOfficialProofs = {}
  savedScale.__seatUnknownSince = {}
  if not nowOwner then
    savedScale.__seatClaimShadow = {}
    savedScale.__seatMigrationGraceUntil = {}
  else
    local migrationGrace = hybridRollbackPrivate.seatMigrationGraceUntil()
    for index = 1, #seatConfigs do
      local seatId = seatConfigs[index].id
      if seatTakenCache[seatId] == true
        and hybridRollbackPrivate.readSeatOccupantId(seatId) == 0 then
        migrationGrace[seatId] = Time.time + 1.5
      else
        migrationGrace[seatId] = nil
      end
    end
    hybridRollbackPrivate.preserveMigratedLocalDriverClaim()
    hybridRollbackPrivate.reconcileSeatClaims(true)
  end
  local pendingCommit = savedScale.__localSeatCommit
  if type(pendingCommit) == "table" then
    pendingCommit.inFlight = false
    pendingCommit.nextAttemptAt = Time.time
  end
  local pendingClaim = savedScale.__localSeatClaim
  if localSeatId == nil and seatReservationPending and type(pendingClaim) == "table"
    and pendingClaim.claimed ~= true then
    savedScale.__seatWaitingForNetwork = true
    seatReservationDeadline = math.max(seatReservationDeadline, Time.time + 2.0)
  end
  if localSeatId == "driver" and nowOwner and not raceResetLocked and rb ~= nil then
    pcall(function()
      rb.isKinematic = false
      rb.useGravity = true
      rb:WakeUp()
    end)
  end
  if nowOwner and raceResetLocked and lastAcceptedRaceResetCycleId >= 100000001
    and savedScale.__raceResetFailedCycleId ~= lastAcceptedRaceResetCycleId then
    RaceManagerCommitReset(lastAcceptedRaceResetCycleId)
  end
  if #interactionButtons > 0 then rebuildInteractionButtons() end
end

function FixedUpdate()
  if rb == nil then return end
  hybridRollbackPrivate.updateRaceCompetitionLock()
  if hybridRollbackPrivate.hasActualDriver() or hybridRollbackPrivate.trailDriverWasOccupied or hybridRollbackPrivate.trailAwake
    or trailEmitting or trailFadeStartedAt ~= nil then
    updateTrailEffect()
  end
  if raceResetLocked then
    clearDriveInput()
    return
  end
  if localSeatId ~= "driver" or seatTakenCache.driver ~= true then return end
  if DouyinNetService ~= nil then
    if not DouyinNetService.isNetworkSettled or not netSpawned then return end
    local owner = false
    pcall(function() owner = self:HasOwnership() end)
    if not owner then return end
  end
  if rb.isKinematic then
    rb.isKinematic = false
    rb.useGravity = true
    rb:WakeUp()
  end
  local dt = Time.fixedDeltaTime
  local accelInput = 0
  if math.abs(moveVec.y) > DEAD_ZONE then
    accelInput = moveVec.y
  end
  local turnInput = 0
  if math.abs(moveVec.x) > DEAD_ZONE then
    turnInput = moveVec.x
  end

  local fwd = self.transform.forward
  local fwdLen = math.sqrt(fwd.x * fwd.x + fwd.z * fwd.z)
  if fwdLen <= 0.0001 then return end
  local forwardX = fwd.x / fwdLen
  local forwardZ = fwd.z / fwdLen

  local currentVelocity = rb.velocity
  local horizontalSpeed = math.sqrt(currentVelocity.x * currentVelocity.x + currentVelocity.z * currentVelocity.z)
  local speedRatio = 0
  if topSpeed > 0.0001 then
    speedRatio = Mathf.Clamp01(horizontalSpeed / topSpeed)
  end
  local steerScale = Mathf.Lerp(1.0, minHighSpeedSteerScale, speedRatio * speedRatio)
  local turningPower = turnInput * turnSpeed * dt * steerScale

  local localVel = self.transform:InverseTransformDirection(currentVelocity)
  local forwardVelSign = localVel.z
  if math.abs(turnInput) > DEAD_ZONE and (horizontalSpeed > 0.2 or math.abs(accelInput) > DEAD_ZONE) then
    local steerDir = 1
    if forwardVelSign < -0.05 then steerDir = -1 end
    rb:MoveRotation(multiplyQuaternion(self.transform.rotation, Quaternion.Euler(0, turningPower * steerDir, 0)))
  end

  local movingForward = forwardVelSign >= -0.05
  local accelForward = accelInput >= 0
  local maxSpd = movingForward and topSpeed or reverseSpeed
  if horizontalSpeed < 0.2 then
    maxSpd = accelForward and topSpeed or reverseSpeed
  end
  local accelPower = accelForward and acceleration or reverseAcceleration
  local accelRampT = 0
  if maxSpd > 0.0001 then
    accelRampT = Mathf.Clamp01(horizontalSpeed / maxSpd)
  end
  local accelRamp = Mathf.Lerp(accelerationCurve, 1, accelRampT * accelRampT)
  local isBraking = (movingForward and accelInput < -0.01) or ((not movingForward) and accelInput > 0.01)
  local finalAccelPower = isBraking and braking or accelPower
  local finalAcceleration = finalAccelPower * accelRamp
  local vx = currentVelocity.x
  local vz = currentVelocity.z
  if not (horizontalSpeed >= maxSpd and not isBraking) then
    vx = vx + forwardX * (accelInput * finalAcceleration * dt)
    vz = vz + forwardZ * (accelInput * finalAcceleration * dt)
  end
  vx, vz = clampHorizontal(vx, vz, maxSpd)
  if math.abs(accelInput) < 0.01 then
    vx, vz = moveHorizontalTowardsZero(vx, vz, coastingDrag * dt)
  end
  if math.abs(turnInput) > DEAD_ZONE and math.abs(forwardVelSign) > 0.1 then
    local dir = 1
    if forwardVelSign < -0.05 then dir = -1 end
    local steerAngle = turningPower * dir * grip
    vx, vz = rotateHorizontal(vx, vz, steerAngle)
  end
  vx, vz = dampSidewaysSlip(vx, vz, speedRatio, dt)
  vx, vz = applyTiltSafetyBrake(vx, vz, dt)
  vx, vz = clampHorizontal(vx, vz, maxSpd)
  rb.velocity = Vector3(vx, currentVelocity.y, vz)
  updateWheelVisuals(dt)
  stabilizeAngularMotion(turnInput, speedRatio, dt)
end

function GetDriverAuthorityDebugStatus()
  local owner = true
  if DouyinNetService ~= nil and DouyinNetService.isNetworkSettled then
    owner = false
    pcall(function() owner = self:HasOwnership() end)
  end
  return tostring(localSeatId or ""), raceResetLocked, rb ~= nil and rb.isKinematic or false,
    owner, true, seatReservationPending or ownershipPending,
    0, 0, "TAKEN_ACTOR_OWNERSHIP", tostring(localSeatActorId or ""),
    seatTakenCache.driver == true, 0, "", false,
    DouyinNetService ~= nil,
    DouyinNetService ~= nil and DouyinNetService.isNetworkSettled == true
end

-- GE0CORE_COMPETITION_SEAT_LOCK_V12
-- Shared integration patch only. Existing seat, physics, material and reset core remain intact.
hybridRollbackPrivate.raceSessionLegacyPoseCheck = hybridRollbackPrivate.isRaceResetPoseVerified
function hybridRollbackPrivate.isRaceResetPoseVerified()
  if not hybridRollbackPrivate.raceSessionLegacyPoseCheck() then return false end
  if spawnPosition == nil or spawnRotation == nil then return false end
  local position, rotation = self.transform.position, self.transform.rotation
  if rb ~= nil then
    pcall(function() if rb.position ~= nil then position = rb.position end; if rb.rotation ~= nil then rotation = rb.rotation end end)
  end
  local ok, angle = pcall(function() return Quaternion.Angle(rotation, spawnRotation) end)
  return position ~= nil and math.abs(position.y - spawnPosition.y) <= 0.75 and ok and tonumber(angle) ~= nil and angle <= 5
end

function hybridRollbackPrivate.raceSessionContext()
  local manager = savedScale.__raceSessionManager
  local session = savedScale.__raceSessionController
  if manager == nil or manager.script == nil or session == nil or session.script == nil then
    local root = UnityEngine.GameObject.Find("RaceManager")
    if root ~= nil then
      pcall(function() manager = root:GetDouyinScript("650f9bb2-f983-4c39-9b98-456d89b19dd2") end)
      pcall(function() session = root:GetDouyinScript("3cb5f0e7-b1a4-4aa0-8d32-905a47bd2f26") end)
      savedScale.__raceSessionManager, savedScale.__raceSessionController = manager, session
    end
  end
  local state, cycleId = "", 0
  if manager ~= nil and manager.script ~= nil then
    pcall(function() state = tostring(manager.script.GetRaceManagerState() or "") end)
    pcall(function() cycleId = math.floor(tonumber(manager.script.GetRaceManagerCycleId()) or 0) end)
  end
  return state, cycleId, session, manager
end

function hybridRollbackPrivate.raceSessionFinite(value)
  local number = tonumber(value)
  return number ~= nil and number == number and number > -math.huge and number < math.huge
end

function hybridRollbackPrivate.readRaceSessionStage()
  local payload = ""
  if raceSessionStageSnapshot ~= nil then
    pcall(function() payload = tostring(raceSessionStageSnapshot:GetValue() or "") end)
  elseif DouyinNetService == nil then
    payload = tostring(savedScale.__raceSessionStageSnapshot or "")
  end
  local cycle, slot, driver, seats = string.match(payload, "^(%d+)|(%d+)|(%d+)|(.+)$")
  return tonumber(cycle) or 0, tonumber(slot) or 0, tonumber(driver) or 0, seats or ""
end

function hybridRollbackPrivate.raceSessionFrozen(session)
  local cycle, driver, seats = 0, 0, ""
  if session ~= nil and session.script ~= nil and session.script.GetRaceVehicleSessionState ~= nil then
    pcall(function()
      cycle, driver, seats = session.script.GetRaceVehicleSessionState(tostring(self.gameObject.name))
    end)
  end
  return math.floor(tonumber(cycle) or 0), math.floor(tonumber(driver) or 0), tostring(seats or "")
end

-- GCRULES-0905: expose a per-actor fact to the one scene-wide input owner.
-- Vehicle modules never enable/disable a shared input action independently.
-- RETURN-SPAWN-0911: native respawn is an explicit local race withdrawal.
function hybridRollbackPrivate.raceSessionWithdrawn(actorId,cycleId)
  local tomb=savedScale.__manualRaceWithdrawal
  if tomb and tomb.actorId==actorId and tomb.cycleId==cycleId then return true end
  local _,_,_,manager=hybridRollbackPrivate.raceSessionContext()
  if manager and manager.script and manager.script.GetRaceManagerActorWithdrawn then
    local ok,value=pcall(manager.script.GetRaceManagerActorWithdrawn,actorId,cycleId)
    if ok and value==true then return true end
  end
  return false
end
function OnRespawn()
  local actor=currentPlayer
  if actor==nil or actor.isLocal~=true or localSeatId==nil then return end
  local phase,cycle,_,manager=hybridRollbackPrivate.raceSessionContext()
  if phase~="WAITING" and phase~="RACING" then return end
  savedScale.__manualRaceWithdrawal={actorId=hybridRollbackPrivate.actorNetworkId(actor),cycleId=cycle}
  savedScale.__raceCompetitionReseat=nil
  if manager and manager.script and manager.script.RaceManagerLocalWithdraw then
    pcall(manager.script.RaceManagerLocalWithdraw)
  end
  pcall(function()actor:StandUp()end)
  VehicleSeatStationExited(actor,localSeatId,true)
end

function OnActorRespawn(actor)
  if actor~=nil and actor==currentPlayer and actor.isLocal then OnRespawn() end
end
function hybridRollbackPrivate.detectReturnedToSpawn(actor,seatId)
  local ok,returned=pcall(function()
    if actor:IsSitting() then return false end
    local cfg=findSeatConfig(seatId)
    if cfg==nil or cfg.transform==nil then return false end
    -- Native Respawn may not notify scene scripts. A detached, non-sitting
    -- rider teleported away must not be pulled back by competition reseating.
    if actor.gameObject.transform.parent~=nil then return false end
    local p,t=actor.position,cfg.transform.position
    local tx,tz=p.x-t.x,p.z-t.z
    return tx*tx+tz*tz>=64
  end)
  if ok and returned then OnRespawn();return true end
  return false
end
function GetRaceSessionLocalSeatLock()
  local state, cycleId, session = hybridRollbackPrivate.raceSessionContext()
  local actor, seatId = currentPlayer, localSeatId
  local actorId = hybridRollbackPrivate.actorNetworkId(actor)
  if hybridRollbackPrivate.raceSessionWithdrawn(actorId,cycleId) then
    return false,cycleId,actorId,seatId,"WITHDRAWN"
  end
  if state ~= "WAITING" and state ~= "RACING" then return false, cycleId, actorId, seatId, "PHASE" end
  if cycleId <= 0 or actor == nil or actor.isLocal ~= true or seatId == nil or actorId <= 0
    or actorSeatIds[actor] ~= seatId
    or hybridRollbackPrivate.normalizeActorId(localSeatActorId) ~= actorId then
    return false, cycleId, actorId, seatId, "NOT_LOCAL_RIDER"
  end
  local frozenCycle, driver, seats = hybridRollbackPrivate.raceSessionFrozen(session)
  if frozenCycle ~= cycleId or driver <= 0 then
    local stagedCycle, _, stagedDriver, stagedSeats = hybridRollbackPrivate.readRaceSessionStage()
    if stagedCycle ~= cycleId or stagedDriver <= 0 then return false, cycleId, actorId, seatId, "NOT_PARTICIPATING" end
    seats = stagedSeats
  end
  local member = false
  for entry in string.gmatch(seats, "[^;]+") do
    local frozenSeat, frozenActor = string.match(entry, "^([%w_]+):(%d+)$")
    if frozenSeat == seatId and tonumber(frozenActor) == actorId then member = true end
  end
  if not member then return false, cycleId, actorId, seatId, "NOT_FROZEN_SEAT" end
  if hybridRollbackPrivate.detectReturnedToSpawn(actor,seatId) then
    return false,cycleId,actorId,seatId,"RETURNED_TO_SPAWN"
  end
  local relation = hybridRollbackPrivate.actorSeatRelation(actor, seatId)
  local parentOk, parent = pcall(function() return actor.gameObject.transform.parent end)
  if relation == "OTHER" or relation == "THIS_VEHICLE"
    or (relation == "UNKNOWN" and parentOk and parent ~= nil) then
    return false, cycleId, actorId, seatId, "NEW_SEAT"
  end
  local station = getSeatStationGameObject(seatId)
  local seatOk, nativeSeat = pcall(function() return actor:GetSeatGameObject() end)
  if seatOk and nativeSeat ~= nil and nativeSeat ~= station then
    return false, cycleId, actorId, seatId, "NEW_NATIVE_SEAT"
  end
  return true, cycleId, actorId, seatId, "FROZEN_LOCAL_RIDER"
end

function hybridRollbackPrivate.isRaceCompetitionSeatHealthProtected(actor, seatId, actorId)
  if raceResetLocked or actor == nil or actor ~= currentPlayer or actor.isLocal ~= true then return false end
  local locked, _, lockedActor, lockedSeat = GetRaceSessionLocalSeatLock()
  return locked and seatId == lockedSeat and actorId == lockedActor
end

function hybridRollbackPrivate.repairRaceCompetitionSeat(actor, seatId)
  local locked, cycleId, actorId, lockedSeat = GetRaceSessionLocalSeatLock()
  if not locked then savedScale.__raceCompetitionReseat = nil; return false end
  if actor ~= currentPlayer or seatId ~= lockedSeat then return false end
  local stateOk, sitting = pcall(function() return actor:IsSitting() end)
  if not stateOk then return true end
  if sitting == true then savedScale.__raceCompetitionReseat = nil; return true end
  local relation = hybridRollbackPrivate.actorSeatRelation(actor, seatId)
  local parentOk, parent = pcall(function() return actor.gameObject.transform.parent end)
  if relation ~= "TARGET" and not (relation == "UNKNOWN" and parentOk and parent == nil) then return false end
  local station = getSeatStationGameObject(seatId)
  if station == nil then return true end
  local task = savedScale.__raceCompetitionReseat
  if type(task) ~= "table" or task.cycleId ~= cycleId or task.actorId ~= actorId or task.seatId ~= seatId then
    task = {cycleId=cycleId, actorId=actorId, seatId=seatId, nextAttemptAt=-math.huge, attempts=0}
    savedScale.__raceCompetitionReseat = task
  end
  if Time.time >= task.nextAttemptAt then
    -- Keep ownership, official seat IDs, the original scale and drive controls.
    -- A native Enter callback (not this pcall) confirms the repaired sitting pose.
    task.attempts = task.attempts + 1
    local delay = task.attempts == 1 and 0.15 or (task.attempts == 2 and 0.5 or (task.attempts == 3 and 1 or 2))
    task.nextAttemptAt = Time.time + delay
    task.lastCallOk = pcall(function() actor:SitDown(station) end)
  end
  return true
end

function hybridRollbackPrivate.raceSessionReturnPolicy(cycleId)
  local _, _, _, manager = hybridRollbackPrivate.raceSessionContext()
  if manager == nil or manager.script == nil or manager.script.GetRaceManagerReturnAllPlayersOnRaceEnd == nil then
    return nil, manager
  end
  local ok, enabled = pcall(function() return manager.script.GetRaceManagerReturnAllPlayersOnRaceEnd(cycleId) end)
  if not ok or type(enabled) ~= "boolean" then return nil, manager end
  return enabled, manager
end

function hybridRollbackPrivate.raceSessionDelegatesStandPoint(actor)
  if actor == nil or actor.isLocal ~= true then return false end
  local _,withdrawCycle=hybridRollbackPrivate.raceSessionContext()
  if hybridRollbackPrivate.raceSessionWithdrawn(hybridRollbackPrivate.actorNetworkId(actor),withdrawCycle) then
    return true -- retain the native spawn pose while restoring scale/collider/input
  end
  local state, cycleId = hybridRollbackPrivate.raceSessionContext()
  local managerCycle = cycleId
  local rider = savedScale.__raceSessionRecycleRider
  if type(rider) == "table" and rider.actor == actor then cycleId = rider.cycleId
  elseif state ~= "RECYCLING" or currentPlayer ~= actor then return false end
  if cycleId <= 0 then return false end
  if not ((state == "RECYCLING" and managerCycle == cycleId)
    or (state == "PREPARING" and managerCycle == cycleId + 1)) then return true end
  local enabled = hybridRollbackPrivate.raceSessionReturnPolicy(cycleId)
  -- Missing/failed policy is pending, not permission to overwrite the spawn.
  return enabled ~= false
end

function hybridRollbackPrivate.markRaceReturnSuperseded(rider)
  if type(rider) ~= "table" then return end
  local tombstones = savedScale.__raceSessionReturnSuperseded or {}
  savedScale.__raceSessionReturnSuperseded = tombstones
  tombstones[rider.cycleId] = {actor=rider.actor, actorId=rider.actorId}
  -- Only adjacent catch-up cycles are valid; retain a bounded history.
  for cycle in pairs(tombstones) do if cycle < rider.cycleId - 2 then tombstones[cycle] = nil end end
end

function hybridRollbackPrivate.raceSessionRiderSuperseded(rider)
  if type(rider) ~= "table" or rider.actor == nil then return false end
  local relation = hybridRollbackPrivate.actorSeatRelation(rider.actor, rider.seatId)
  if relation == "OTHER" or relation == "THIS_VEHICLE"
    or (tonumber(savedScale.__raceSessionLocalSeatGeneration) or 0) > (tonumber(rider.seatGeneration) or 0) then return true end
  local ok, nativeSeat = pcall(function() return rider.actor:GetSeatGameObject() end)
  return ok and nativeSeat ~= nil and nativeSeat ~= getSeatStationGameObject(rider.seatId)
end

function hybridRollbackPrivate.raceSessionCanFinishCapturedLocalExit(actor, seatId)
  local rider = savedScale.__raceSessionRecycleRider
  if type(rider) ~= "table" or rider.actor ~= actor or actor == nil or actor.isLocal ~= true
    or actor ~= currentPlayer or seatId ~= localSeatId or seatId ~= rider.seatId
    or hybridRollbackPrivate.actorNetworkId(actor) ~= rider.actorId
    or hybridRollbackPrivate.normalizeActorId(localSeatActorId) ~= rider.actorId
    or (tonumber(savedScale.__raceSessionLocalSeatGeneration) or 0) ~= (tonumber(rider.seatGeneration) or 0)
    or hybridRollbackPrivate.raceSessionRiderSuperseded(rider) then return false end
  local state, cycleId = hybridRollbackPrivate.raceSessionContext()
  return (state == "RECYCLING" and cycleId == rider.cycleId)
    or (state == "PREPARING" and cycleId == rider.cycleId + 1)
end

function hybridRollbackPrivate.raceSessionActorReleaseVerified(actor)
  local ok, sitting, parent, collider = pcall(function()
    return actor:IsSitting(), actor.gameObject.transform.parent,
      actor.gameObject:GetComponent(typeof(UnityEngine.Collider))
  end)
  if not ok then return false, "PENDING_LOCAL_RELEASE_READ" end
  if sitting ~= false or parent ~= nil then return false, "PENDING_LOCAL_NATIVE_EXIT" end
  if savedScale[actor] ~= nil then return false, "PENDING_LOCAL_SCALE_RESTORE" end
  if collider ~= nil then
    local readable, enabled = pcall(function() return collider.enabled end)
    if not readable or enabled ~= true then return false, "PENDING_LOCAL_COLLIDER_RESTORE" end
  end
  return true, "LOCAL_RELEASE_READY"
end

function GetRaceSessionLocalReleaseStatus(rawCycleId)
  local cycleId = math.floor(tonumber(rawCycleId) or 0)
  local rider = savedScale.__raceSessionRecycleRider
  if type(rider) == "table" and rider.cycleId == cycleId then
    if hybridRollbackPrivate.raceSessionRiderSuperseded(rider) then
      hybridRollbackPrivate.markRaceReturnSuperseded(rider)
    end
  end
  local tombstones = savedScale.__raceSessionReturnSuperseded
  local tombstone = type(tombstones) == "table" and tombstones[cycleId] or nil
  if type(tombstone) == "table" then
    local ok, actor = pcall(function() return CS.DouyinActorService.GetLocalActor() end)
    if (ok and hybridRollbackPrivate.actorNetworkId(actor) == tombstone.actorId)
      or (not ok and tombstone.actor ~= nil and tombstone.actor.isLocal == true) then
      return true, "SUPERSEDED_NEW_SEAT"
    end
  end
  if currentPlayer ~= nil and currentPlayer.isLocal == true and localSeatId ~= nil then
    return false, "PENDING_LOCAL_SEAT_CLEANUP"
  end
  for actor, seatId in pairs(actorSeatIds) do
    if actor ~= nil and actor.isLocal == true and seatId ~= nil then return false, "PENDING_LOCAL_SEAT_MAP" end
  end
  if localActor ~= nil and localActor.isLocal == true and (seatReservationPending
    or savedScale.__localSeatClaim ~= nil or savedScale.__localSitRollback ~= nil) then
    return false, "PENDING_LOCAL_SEAT_ATTEMPT"
  end
  -- An exitObserved rider may wait only for manager completion: do not make
  -- manager completion depend on clearing that same rider (a circular wait).
  if type(rider) == "table" and rider.cycleId == cycleId and rider.actor ~= nil
    and rider.actor.isLocal == true and rider.exitObserved ~= true then
    return false, "PENDING_LOCAL_NATIVE_EXIT"
  end
  if type(rider) == "table" and rider.cycleId == cycleId and rider.actor ~= nil and rider.actor.isLocal == true then
    return hybridRollbackPrivate.raceSessionActorReleaseVerified(rider.actor)
  end
  local guard = savedScale.__raceResetNativeExitGuard
  if type(guard) == "table" and guard.cycleId == hybridRollbackPrivate.raceSessionRecycleToken(cycleId)
    and type(guard.actors) == "table" then
    for _, entry in pairs(guard.actors) do
      if entry.actor ~= nil and entry.actor.isLocal == true then
        local ready, reason = hybridRollbackPrivate.raceSessionActorReleaseVerified(entry.actor)
        if not ready then return false, reason end
      end
    end
  end
  return true, "LOCAL_RELEASE_READY"
end

function RaceSessionGetRoster()
  local driverId, passengers = 0, {}
  for index = 1, #seatConfigs do
    local id = hybridRollbackPrivate.readSeatOccupantId(seatConfigs[index].id)
    if seatConfigs[index].id == "driver" then driverId = id
    elseif id > 0 then passengers[#passengers + 1] = tostring(id) end
  end
  return driverId, table.concat(passengers, ",")
end

function RaceSessionGetSeatRoster()
  local seats = {}
  for index = 1, #seatConfigs do
    local id = hybridRollbackPrivate.readSeatOccupantId(seatConfigs[index].id)
    if id > 0 then seats[#seats + 1] = seatConfigs[index].id .. ":" .. tostring(id) end
  end
  return table.concat(seats, ";")
end

function HasCompletedRaceSessionStage(rawCycleId)
  local cycleId = math.floor(tonumber(rawCycleId) or 0)
  local confirmedCycle, slot, driver, seats = hybridRollbackPrivate.readRaceSessionStage()
  if cycleId <= 0 or confirmedCycle ~= cycleId or slot < 1 or slot > 16 or driver <= 0 then return false end
  local _, managerCycle, session = hybridRollbackPrivate.raceSessionContext()
  local rosterCycle, frozenDriver, frozenSeats = hybridRollbackPrivate.raceSessionFrozen(session)
  return managerCycle == cycleId and rosterCycle == cycleId and driver == frozenDriver and seats == frozenSeats
end

function hybridRollbackPrivate.raceSessionHomePose(session)
  if session == nil or session.script == nil or session.script.GetRaceVehicleHomePose == nil then return false end
  local ok, x, y, z, yaw, valid = pcall(function()
    return session.script.GetRaceVehicleHomePose(tostring(self.gameObject.name))
  end)
  if not ok or valid ~= true or not hybridRollbackPrivate.raceSessionFinite(x)
    or not hybridRollbackPrivate.raceSessionFinite(y) or not hybridRollbackPrivate.raceSessionFinite(z)
    or not hybridRollbackPrivate.raceSessionFinite(yaw) then return false end
  spawnPosition = Vector3(tonumber(x), tonumber(y), tonumber(z))
  spawnRotation = Quaternion.Euler(0, tonumber(yaw), 0)
  return true
end

function hybridRollbackPrivate.raceSessionRecycleToken(rawCycleId)
  local cycleId = math.floor(tonumber(rawCycleId) or 0)
  if cycleId <= 0 then return nil end
  -- Legacy PREPARING may already have acknowledged cycleId. The following
  -- ordinal distinguishes this cycle's RECYCLING and stays monotonic next lap.
  return normalizeRaceResetCycleId(cycleId + 1)
end

function HasCompletedRaceSessionRecycle(rawCycleId)
  local token = hybridRollbackPrivate.raceSessionRecycleToken(rawCycleId)
  return token ~= nil and HasCompletedRaceResetCycle(token)
end

function hybridRollbackPrivate.updateRaceCompetitionLock()
  local state, cycleId, session = hybridRollbackPrivate.raceSessionContext()
  local rosterCycle, driverId = hybridRollbackPrivate.raceSessionFrozen(session)
  local stagedCycle, stagedSlot = hybridRollbackPrivate.readRaceSessionStage()
  local participating = cycleId > 0 and ((rosterCycle == cycleId and driverId > 0) or stagedCycle == cycleId)
  local nextLocked = participating and (state == "WAITING" or state == "RACING")
  if raceCompetitionLocked ~= nextLocked then
    raceCompetitionLocked = nextLocked
    refreshInteractionForState()
  end
  savedScale.__raceSessionStagedCycleId, savedScale.__raceSessionStagedSlot = stagedCycle, stagedSlot
  if (state == "WAITING" or state == "RACING") and participating and rb ~= nil and rb.isKinematic
    and not raceResetLocked and isLocalVehicleOwner()
    and (stagedCycle == cycleId or savedScale.__raceSessionPoseAppliedCycle == cycleId) then
    pcall(function() rb.isKinematic = false; rb.useGravity = true; rb:WakeUp() end)
  end
  local localLocked, localCycle, actorId, seatId = GetRaceSessionLocalSeatLock()
  if localLocked then
    savedScale.__raceSessionFrozenLocalRider = {cycleId=localCycle, actor=currentPlayer,
      actorId=actorId, seatId=seatId, seatGeneration=tonumber(savedScale.__raceSessionLocalSeatGeneration) or 0}
  end
  return state, cycleId
end

function RaceSessionStageVehicle(rawCycleId, rawSlotIndex, x, y, z, yaw, rawDriverId, rawFrozenSeats)
  local state, managerCycle, session = hybridRollbackPrivate.raceSessionContext()
  local cycleId, slotIndex = math.floor(tonumber(rawCycleId) or 0), math.floor(tonumber(rawSlotIndex) or 0)
  local expectedDriver, expectedSeats = math.floor(tonumber(rawDriverId) or 0), tostring(rawFrozenSeats or "")
  if state ~= "WAITING" or cycleId <= 0 or managerCycle ~= cycleId or slotIndex < 1 or slotIndex > 16
    or expectedDriver <= 0 or expectedSeats == "" or not isLocalVehicleOwner() or raceResetLocked then return false end
  local rosterCycle, frozenDriver, frozenSeats = hybridRollbackPrivate.raceSessionFrozen(session)
  if rosterCycle ~= cycleId or frozenDriver ~= expectedDriver or frozenSeats ~= expectedSeats then return false end
  if HasCompletedRaceSessionStage(cycleId) then
    local _, priorSlot = hybridRollbackPrivate.readRaceSessionStage()
    return priorSlot == slotIndex
  end
  if select(1, RaceSessionGetRoster()) ~= expectedDriver or RaceSessionGetSeatRoster() ~= expectedSeats then return false end
  if session == nil or session.script.GetRaceSessionStartSlot == nil then return false end
  local ok, sx, sy, sz, syaw, valid = pcall(function() return session.script.GetRaceSessionStartSlot(slotIndex) end)
  if not ok or valid ~= true then return false end
  if not hybridRollbackPrivate.raceSessionFinite(x) or not hybridRollbackPrivate.raceSessionFinite(y)
    or not hybridRollbackPrivate.raceSessionFinite(z) or not hybridRollbackPrivate.raceSessionFinite(yaw)
    or not hybridRollbackPrivate.raceSessionFinite(sx) or not hybridRollbackPrivate.raceSessionFinite(sy)
    or not hybridRollbackPrivate.raceSessionFinite(sz) or not hybridRollbackPrivate.raceSessionFinite(syaw) then return false end
  x, y, z, yaw = tonumber(x), tonumber(y), tonumber(z), tonumber(yaw)
  sx, sy, sz, syaw = tonumber(sx), tonumber(sy), tonumber(sz), tonumber(syaw)
  if math.abs(x - sx) > 0.05 or math.abs(y - sy) > 0.05 or math.abs(z - sz) > 0.05
    or math.abs(Mathf.DeltaAngle(yaw, syaw)) > 0.1 then return false end
  local poseOk = pcall(function()
    local targetPosition, targetRotation = Vector3(sx, sy, sz), Quaternion.Euler(0, syaw, 0)
    if rb == nil then error("stage Rigidbody unavailable") end
    rb.velocity, rb.angularVelocity = Vector3.zero, Vector3.zero
    rb.useGravity, rb.isKinematic = false, true
    rb.position, rb.rotation = targetPosition, targetRotation
    self.transform.position, self.transform.rotation = targetPosition, targetRotation
    UnityEngine.Physics.SyncTransforms()
    -- Staging moves the car once. WAITING keeps seats locked while the driver
    -- can move within the start enclosure using its ordinary collisions.
    rb.isKinematic, rb.useGravity = false, true
    rb:WakeUp()
  end)
  if not poseOk then return false end
  savedScale.__raceSessionPoseAppliedCycle = cycleId
  local p = self.transform.position
  if math.abs(p.x - sx) > 0.1 or math.abs(p.y - sy) > 0.1 or math.abs(p.z - sz) > 0.1
    or math.abs(Mathf.DeltaAngle(self.transform.eulerAngles.y, syaw)) > 0.2
    or RaceSessionGetSeatRoster() ~= expectedSeats then return false end
  local snapshot = tostring(cycleId) .. "|" .. tostring(slotIndex) .. "|" .. tostring(expectedDriver) .. "|" .. expectedSeats
  if raceSessionStageSnapshot ~= nil then
    local published = pcall(function() raceSessionStageSnapshot:SetValue(snapshot) end)
    if not published then return false end
  elseif DouyinNetService == nil then
    savedScale.__raceSessionStageSnapshot = snapshot
  else
    return false
  end
  hybridRollbackPrivate.updateRaceCompetitionLock()
  return HasCompletedRaceSessionStage(cycleId)
end

function RaceSessionRequestStage(cycleId, slotIndex, x, y, z, yaw, expectedDriver, frozenSeats)
  if HasCompletedRaceSessionStage(cycleId) then return true end
  if isLocalVehicleOwner() then
    return RaceSessionStageVehicle(cycleId, slotIndex, x, y, z, yaw, expectedDriver, frozenSeats)
  end
  if DouyinNetService == nil or not DouyinNetService.isNetworkSettled then return false end
  local now = Time.time
  if now < (tonumber(savedScale.__raceSessionStageRpcAt) or -math.huge) + 0.5 then return false end
  savedScale.__raceSessionStageRpcAt = now
  pcall(function()
    self:OwnerCall("RaceSessionStageVehicle", function() end, tostring(cycleId), slotIndex, x, y, z, yaw, expectedDriver, frozenSeats)
  end)
  -- RPC dispatch is not completion. The caller polls the synchronized proof.
  return HasCompletedRaceSessionStage(cycleId)
end

function hybridRollbackPrivate.raceSessionCanRecoverOldRider(cycleId)
  local proof = savedScale.__raceSessionFrozenLocalRider
  if type(proof) ~= "table" or proof.cycleId ~= cycleId or proof.actor ~= currentPlayer
    or currentPlayer == nil or currentPlayer.isLocal ~= true or localSeatId ~= proof.seatId
    or actorSeatIds[currentPlayer] ~= proof.seatId
    or hybridRollbackPrivate.actorNetworkId(currentPlayer) ~= proof.actorId
    or hybridRollbackPrivate.normalizeActorId(localSeatActorId) ~= proof.actorId
    or (tonumber(savedScale.__raceSessionLocalSeatGeneration) or 0) ~= proof.seatGeneration then return false end
  local relation = hybridRollbackPrivate.actorSeatRelation(currentPlayer, proof.seatId)
  local parentOk, parent = pcall(function() return currentPlayer.gameObject.transform.parent end)
  if relation ~= "TARGET" and not (relation == "UNKNOWN" and parentOk and parent == nil) then return false end
  local seatOk, nativeSeat = pcall(function() return currentPlayer:GetSeatGameObject() end)
  if seatOk and nativeSeat ~= nil and nativeSeat ~= getSeatStationGameObject(proof.seatId) then return false end
  return true
end

function hybridRollbackPrivate.captureLocalRecycleRider(cycleId)
  local state, managerCycle = hybridRollbackPrivate.raceSessionContext()
  local recoveringOldRider = state == "PREPARING" and managerCycle == cycleId + 1
    and hybridRollbackPrivate.raceSessionCanRecoverOldRider(cycleId)
  if not recoveringOldRider and (state ~= "RECYCLING" or managerCycle ~= cycleId) then return end
  if savedScale.__raceSessionRecycleCaptureCycle == cycleId then return end
  savedScale.__raceSessionRecycleCaptureCycle = cycleId
  savedScale.__raceSessionRecycleRider = nil
  if currentPlayer == nil or localSeatId == nil or currentPlayer.isLocal ~= true then return end
  local _, seatIndex = findSeatConfig(localSeatId)
  savedScale.__raceSessionRecycleRider = {actor=currentPlayer, actorId=hybridRollbackPrivate.actorNetworkId(currentPlayer),
    seatId=localSeatId, seatIndex=seatIndex or 1, cycleId=cycleId, nextAttemptAt=-math.huge,
    seatGeneration=tonumber(savedScale.__raceSessionLocalSeatGeneration) or 0}
end

function hybridRollbackPrivate.captureRecycleBeforeExit(actor)
  local state, cycleId = hybridRollbackPrivate.raceSessionContext()
  if state == "RECYCLING" and cycleId > 0 and actor == currentPlayer and actor.isLocal == true then
    hybridRollbackPrivate.captureLocalRecycleRider(cycleId)
    raceCompetitionLocked = false
  end
end

function hybridRollbackPrivate.returnLocalRecycleRider(cycleId)
  local rider = savedScale.__raceSessionRecycleRider
  if type(rider) ~= "table" or rider.cycleId ~= cycleId then return true end
  local actor = rider.actor
  if actor == nil or actor.isLocal ~= true then savedScale.__raceSessionRecycleRider = nil; return true end
  if hybridRollbackPrivate.raceSessionRiderSuperseded(rider) then
    -- Local cleanup already detached the old ride. A newly confirmed seat on
    -- this same vehicle must not be treated as the old unfinished native exit.
    hybridRollbackPrivate.markRaceReturnSuperseded(rider)
    savedScale.__raceSessionRecycleRider = nil
    return true
  end
  local relation = hybridRollbackPrivate.actorSeatRelation(actor, rider.seatId)
  if relation == "OTHER" or relation == "THIS_VEHICLE" then
    -- A stale reset must not pull a player from a newer seat/another vehicle.
    hybridRollbackPrivate.markRaceReturnSuperseded(rider)
    savedScale.__raceSessionRecycleRider = nil
    return true
  end
  local state, managerCycle = hybridRollbackPrivate.raceSessionContext()
  if not ((state == "RECYCLING" and managerCycle == cycleId)
    or (state == "PREPARING" and managerCycle == cycleId + 1)) then
    local _, manager = hybridRollbackPrivate.raceSessionReturnPolicy(cycleId)
    if manager ~= nil and manager.script ~= nil and manager.script.RaceManagerReturnLocalActorToSpawn ~= nil then
      local ok, handled, completed, reason = pcall(function() return manager.script.RaceManagerReturnLocalActorToSpawn(cycleId) end)
      if ok and handled == true and completed == true and reason == "STALE" then
        savedScale.__raceSessionRecycleRider = nil
        return true
      end
    end
    return false
  end
  local ok, sitting = pcall(function() return actor:IsSitting() end)
  if not ok then return false end
  if sitting == true then
    local parentOk,parent=pcall(function() return actor.gameObject.transform.parent end)
    local oldSeatStillOurs=relation=="TARGET" or (relation=="UNKNOWN" and parentOk and parent==nil)
    if oldSeatStillOurs and Time.time >= rider.nextAttemptAt then
      local station = getSeatStationGameObject(rider.seatId)
      if station ~= nil then pcall(function() actor:StandUp(station) end) end
      rider.nextAttemptAt = Time.time + 0.5
    end
    return false
  end
  rider.exitObserved=true
  if actorSeatIds[actor] == rider.seatId
    or hybridRollbackPrivate.raceSessionCanFinishCapturedLocalExit(actor, rider.seatId) then
    VehicleSeatStationExited(actor, rider.seatId, true)
  end
  if actorSeatIds[actor] ~= nil or (currentPlayer == actor and localSeatId ~= nil) then return false end
  local parentOk, parent = pcall(function() return actor.gameObject.transform.parent end)
  if not parentOk or parent ~= nil then return false end
  -- A failed collider restore is retried locally, not acknowledged as walking.
  setActorColliderEnabled(actor, true)
  if not hybridRollbackPrivate.raceSessionActorReleaseVerified(actor) then return false end
  local _, manager = hybridRollbackPrivate.raceSessionReturnPolicy(cycleId)
  if manager == nil or manager.script == nil or manager.script.RaceManagerReturnLocalActorToSpawn == nil then return false end
  local called, handled, completed, reason = pcall(function()
    return manager.script.RaceManagerReturnLocalActorToSpawn(cycleId)
  end)
  if not called then return false end
  if handled == true then
    if completed == true then savedScale.__raceSessionRecycleRider = nil end
    return completed == true
  end
  if handled ~= false or reason ~= "DISABLED" then return false end
  if spawnPosition == nil or spawnRotation == nil then return false end
  local side = rider.seatIndex % 2 == 1 and -1 or 1
  local forward = (math.floor((rider.seatIndex - 1) / 2) - 1) * 0.8
  local moved = pcall(function()
    local offset = spawnRotation * Vector3(side * 1.4, 0.2, forward)
    actor.position = spawnPosition + offset
    actor.rotation = spawnRotation
    setActorColliderEnabled(actor, true)
  end)
  if moved then savedScale.__raceSessionRecycleRider = nil end
  return moved
end

function RaceSessionRecycleVehicle(rawCycleId, rawRemainingMilliseconds)
  local state, managerCycle, session, manager = hybridRollbackPrivate.raceSessionContext()
  local cycleId = math.floor(tonumber(rawCycleId) or 0)
  local token = hybridRollbackPrivate.raceSessionRecycleToken(cycleId)
  local stagedCycle=hybridRollbackPrivate.readRaceSessionStage()
  local catchUp=state=="PREPARING" and managerCycle==cycleId+1 and stagedCycle==cycleId and cycleId>0
  if not catchUp and (state ~= "RECYCLING" or managerCycle ~= cycleId) then return false end
  if token == nil then return false end
  if catchUp and currentPlayer ~= nil and localSeatId ~= nil then
    local oldRider = savedScale.__raceSessionRecycleRider
    if type(oldRider) ~= "table" and hybridRollbackPrivate.raceSessionCanRecoverOldRider(cycleId) then
      hybridRollbackPrivate.captureLocalRecycleRider(cycleId)
      oldRider = savedScale.__raceSessionRecycleRider
    end
    if type(oldRider) ~= "table" or oldRider.cycleId ~= cycleId
      or oldRider.actor ~= currentPlayer or oldRider.seatId ~= localSeatId
      or hybridRollbackPrivate.raceSessionRiderSuperseded(oldRider) then
      if type(oldRider) == "table" and oldRider.cycleId == cycleId then hybridRollbackPrivate.markRaceReturnSuperseded(oldRider) end
      return false
    end
  end
  local remaining = math.floor(tonumber(rawRemainingMilliseconds) or 0)
  local authoritativeRemaining = remaining
  if manager ~= nil and manager.script.GetRaceManagerRemainingMilliseconds ~= nil then
    pcall(function() authoritativeRemaining = math.floor(tonumber(manager.script.GetRaceManagerRemainingMilliseconds()) or 0) end)
  end
  remaining = catchUp and 5000 or math.min(remaining, authoritativeRemaining, 5000)
  if remaining <= 0 then return false end
  if not hybridRollbackPrivate.raceSessionHomePose(session) then return false end
  raceCompetitionLocked = false
  -- A completed VarSync value may be readable before its callback performs
  -- local cleanup. Capture this client's old rider before observing/adopting
  -- that ACK; a completed local token proves a later rider must be left alone.
  if savedScale.__raceSessionRecycleCaptureCycle ~= cycleId then
    if math.floor(tonumber(savedScale.__raceResetLocalCleanupCycleId) or 0) < token then
      hybridRollbackPrivate.captureLocalRecycleRider(cycleId)
    else
      savedScale.__raceSessionRecycleCaptureCycle = cycleId
    end
  end
  if HasCompletedRaceSessionRecycle(cycleId) then
    if math.floor(tonumber(savedScale.__raceResetLocalCleanupCycleId) or 0) < token then
      pcall(function() hybridRollbackPrivate.adoptSynchronizedCompletedReset(token) end)
    end
    local returned = hybridRollbackPrivate.returnLocalRecycleRider(cycleId)
    return returned and math.floor(tonumber(savedScale.__raceResetLocalCleanupCycleId) or 0) >= token
  end
  if savedScale.__raceResetFailedCycleId == token or
    (savedScale.__raceResetTerminalCycleId == token and savedScale.__raceResetTerminalStatus == "FAILED") then
    if Time.time < (tonumber(savedScale.__raceSessionRecycleRetryAt) or -math.huge) + 0.5 then return false end
    savedScale.__raceSessionRecycleRetryAt = Time.time
    savedScale.__raceResetFailedCycleId = 0
    savedScale.__raceResetTerminalCycleId, savedScale.__raceResetTerminalStatus = 0, nil
    savedScale.__raceResetExpiredObservedCleanupCycleId = 0
    savedScale.__raceResetDeadlineCycleId, savedScale.__raceResetDeadlineAt = nil, nil
  end
  RaceManagerReset(token, remaining)
  local returned = hybridRollbackPrivate.returnLocalRecycleRider(cycleId)
  return HasCompletedRaceSessionRecycle(cycleId) and returned
    and math.floor(tonumber(savedScale.__raceResetLocalCleanupCycleId) or 0) >= token
end

function hybridRollbackPrivate.updateRaceSessionRecycling()
  local state, cycleId, _, manager = hybridRollbackPrivate.raceSessionContext()
  if state=="PREPARING" then
    local stagedCycle=hybridRollbackPrivate.readRaceSessionStage()
    if stagedCycle>0 and stagedCycle<cycleId then
      local token=hybridRollbackPrivate.raceSessionRecycleToken(stagedCycle)
      local pendingRider=savedScale.__raceSessionRecycleRider
      if not HasCompletedRaceSessionRecycle(stagedCycle) or pendingRider~=nil
        or (tonumber(savedScale.__raceResetLocalCleanupCycleId) or 0)<(token or 0) then
        RaceSessionRecycleVehicle(stagedCycle,5000)
      end
    end
    return
  end
  if state ~= "RECYCLING" or cycleId <= 0 then return end
  if Time.time < (tonumber(savedScale.__raceSessionRecycleTickAt) or -math.huge) + 0.2 then return end
  savedScale.__raceSessionRecycleTickAt = Time.time
  local remaining = 0
  if manager ~= nil and manager.script.GetRaceManagerRemainingMilliseconds ~= nil then
    pcall(function() remaining = manager.script.GetRaceManagerRemainingMilliseconds() end)
  end
  RaceSessionRecycleVehicle(cycleId, remaining)
end

function GetRaceSessionVehicleStatus()
  local stagedCycle, slot, driver = hybridRollbackPrivate.readRaceSessionStage()
  return raceCompetitionLocked, stagedCycle, slot, driver
end

function Update()
  hybridRollbackPrivate.updateRaceCompetitionLock()
  if currentPlayer ~= nil and localSeatId ~= nil then
    hybridRollbackPrivate.repairRaceCompetitionSeat(currentPlayer, localSeatId)
  end
  hybridRollbackPrivate.updateRaceSessionRecycling()
  if ownershipPending and Time.time >= ownershipPendingDeadline then
    ownershipPending = false
    ownershipPendingDeadline = -math.huge
    if localSeatId == nil and savedScale.__localSeatClaim ~= nil then
      clearPendingSeatSelection()
      rebuildInteractionButtons()
    end
  end
  VehicleReplayPendingSeatEntries()
  hybridRollbackPrivate.refreshSeatSyncCache()
  hybridRollbackPrivate.reconcileSeatClaims()
  hybridRollbackPrivate.updateLocalSeatCommit()
  hybridRollbackPrivate.updateLocalSitRollback()
  hybridRollbackPrivate.updateOrphanNativeSeatExit()

  if hybridRollbackPrivate.seatFeedbackUntil ~= nil
    and Time.time >= hybridRollbackPrivate.seatFeedbackUntil then
    hybridRollbackPrivate.seatFeedbackUntil = nil
    hybridRollbackPrivate.seatFeedbackText = nil
    if currentInside and localSeatId == nil then rebuildInteractionButtons() end
  end

  if savedScale.__seatWaitingForNetwork == true and localSeatId == nil
    and selectedSeatId ~= nil and Time.time < seatReservationDeadline
    and DouyinNetService ~= nil and DouyinNetService.isNetworkSettled and netSpawned then
    local waitingSeat = selectedSeatId
    local waitingClaim = savedScale.__localSeatClaim
    savedScale.__seatWaitingForNetwork = false
    savedScale.__driverWaitingForNetwork = false
    seatReservationPending = false
    if waitingClaim ~= nil and waitingClaim.claimed == true then
      trySitSeat(waitingSeat, waitingClaim.actorId)
    else
      requestSeatReservation(waitingSeat)
    end
  end
  if seatReservationPending and localSeatId == nil and Time.time >= seatReservationDeadline then
    hybridRollbackPrivate.beginLocalSitRollback("SIT_TIMEOUT")
  end
  updateRaceManagerReset()
  hybridRollbackPrivate.updateProximityInteractionBudgeted()
  if hybridRollbackPrivate.hasActualDriver() or hybridRollbackPrivate.engineAudioAwake then
    updateEngineAudio()
  end
  if respawnHideUntil ~= nil and Time.time >= respawnHideUntil then
    respawnHideUntil = nil
    setRendererVisible(self.transform, true)
  end
  if localSeatId ~= "driver" then clearDriveInput() end
end

function GetRaceEngineAudioStatus()
  if engineAudioSource == nil then return false, 0, 0, false, "missing-source" end
  local hasClip = engineAudioSource.clip ~= nil
  return engineAudioSource.isPlaying, engineAudioSource.volume, engineAudioSource.pitch, hasClip, hasClip and "ready" or "waiting-clip"
end

function LateUpdate()
  local staleActors = {}
  for actor, target in pairs(seatedActors) do
    local seatId = actorSeatIds[actor]
    local actorId = hybridRollbackPrivate.actorNetworkId(actor)
    local occupantId = seatId ~= nil
      and hybridRollbackPrivate.normalizeActorId(seatOccupantIdCache[seatId]) or 0
    local localOk, isLocalActor = pcall(function() return actor.isLocal end)
    local localSeatMatches = localOk and isLocalActor == true and localSeatId == seatId
      and hybridRollbackPrivate.normalizeActorId(localSeatActorId) == actorId
      and (occupantId == 0 or occupantId == actorId)
    local officialSeatMatches = occupantId == actorId
    local bindingMatches = actorId > 0 and seatId ~= nil
      and hybridRollbackPrivate.isSeatEntryProcessed(actor, seatId)
      and (localSeatMatches or officialSeatMatches)
    local stateOk, sitting = pcall(function() return actor:IsSitting() end)
    local relation = seatId ~= nil
      and hybridRollbackPrivate.actorSeatRelation(actor, seatId) or "UNKNOWN"
    local parentOk, parent = pcall(function() return actor.gameObject.transform.parent end)
    local unparented = relation == "UNKNOWN" and parentOk and parent == nil
    if bindingMatches and stateOk and sitting == true
      and (relation == "TARGET" or unparented) then
      pcall(function() alignActorHipsToSeat(actor, target) end)
    elseif stateOk and relation == "OTHER" then
      staleActors[#staleActors + 1] = { actor = actor, actorId = actorId, seatId = seatId, crossVehicle = true }
    elseif stateOk and sitting ~= true
      and (relation == "TARGET" or relation == "THIS_VEHICLE" or unparented) then
      staleActors[#staleActors + 1] = { actor = actor, actorId = actorId, seatId = seatId, crossVehicle = false }
    end
    -- A real Enter plus the exact Actor-ID/seat binding may repair parent=nil.
    -- A different seat/vehicle or any external non-nil parent is never pulled back.
  end
  for index = 1, #staleActors do
    local stale = staleActors[index]
    if stale.crossVehicle then
      hybridRollbackPrivate.clearStaleCrossVehicleSeatState(
        stale.actor, stale.seatId, stale.actorId
      )
    else
      VehicleSeatStationExited(stale.actor, stale.seatId, false)
    end
  end
  applyCameraYawFollow()
end
