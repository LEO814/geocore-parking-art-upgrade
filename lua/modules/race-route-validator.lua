---@id 4fd23b49-42c5-4e32-9c41-7f364db2a421
-- Three authoritative lines only: start -> check -> finish.
-- Geometry comes from the visible scene. Route samples below are ranking-only.
---@start
---@varSync routeProgressLedger:string
---@end
local UnityEngine = CS.UnityEngine
local Vector3 = UnityEngine.Vector3
local LINE_HALF_WIDTH = 10.5
local LINE_VERTICAL_TOLERANCE = 5.0
local routeSamples = {
  {x=129.2431,z=41.5803,arc=0}, {x=157.2946,z=55.3053,arc=70},
  {x=212.5459,z=64.4253,arc=145}, {x=172.6856,z=110.2600,arc=220},
  {x=211.5343,z=139.4137,arc=295}, {x=200.2430,z=200.3536,arc=370},
  {x=130.4644,z=214,arc=445}, {x=86.7262,z=183.1791,arc=520},
  {x=84.6902,z=148.0219,arc=595}, {x=26.6457,z=141.6810,arc=670},
  {x=73.3337,z=106.7870,arc=745}, {x=53.1635,z=73.8833,arc=820},
  {x=107.0249,z=41.2393,arc=897.219},
}
local fleetNames = {"玩具","莓爆花","绯樱","暴走","烈焰","赤巡","薄荷糖","甜品","牛牛","牛粉","积木","宝宝巴","星梦巴","爆米花","暮翼巡游","甜咒南瓜"}
local vehicleTransforms, stateByVehicle = {}, {}
local activeCycleId, racingCycleId, completedVehicleCount = 0, 0, 0
local managerHolder = nil
local lines, geometryStatus = {}, "UNRESOLVED"
local ledgerRevision, ledgerDirty, ledgerChangeHandle, wasAuthority = 0, false, nil, false

local function managerApi()
  if managerHolder == nil or managerHolder.script == nil then
    local root = UnityEngine.GameObject.Find("RaceManager") or self.gameObject
    local ok, holder = pcall(function() return root:GetDouyinScript("650f9bb2-f983-4c39-9b98-456d89b19dd2") end)
    if ok and holder ~= nil and holder.script ~= nil then managerHolder = holder end
  end
  return managerHolder ~= nil and managerHolder.script or nil
end
local function authority()
  local api = managerApi()
  if api == nil or api.GetRaceManagerClockIsAuthority == nil then return false end
  local ok, yes = pcall(function() return api.GetRaceManagerClockIsAuthority() end)
  return ok and yes == true
end
local function participating(name)
  local api = managerApi()
  if api == nil or api.GetRaceManagerVehicleParticipating == nil then return false end
  local ok, yes = pcall(function() return api.GetRaceManagerVehicleParticipating(name) end)
  return ok and yes == true
end
local function copy(position)
  return position ~= nil and Vector3(position.x, position.y, position.z) or nil
end
local function vehicleTransform(name)
  local value = vehicleTransforms[name]
  if value ~= nil then return value end
  local root = UnityEngine.GameObject.Find(name)
  value = root ~= nil and root.transform or nil
  vehicleTransforms[name] = value
  return value
end
local function findObject(names)
  for _, name in ipairs(names) do
    local object = UnityEngine.GameObject.Find(name)
    if object ~= nil then return object end
  end
  return nil
end
local function sceneLine(object, bodyName, useObjectCenter)
  if object == nil or object.transform == nil then return nil end
  local t, body = object.transform, nil
  local renderers = object:GetComponentsInChildren(typeof(UnityEngine.Renderer), true)
  for index = 0, renderers.Length - 1 do
    local candidate = renderers[index]
    if bodyName == nil or tostring(candidate.gameObject.name) == bodyName then body = candidate; break end
  end
  -- A visible finish model can have a translated child mesh. Never silently
  -- substitute its parent pivot for a missing painted centerline.
  if bodyName ~= nil and body == nil then return nil end
  local forward = t.forward
  local length = math.sqrt(forward.x * forward.x + forward.z * forward.z)
  if length < 0.00001 then return nil end
  local nx, nz = forward.x / length, forward.z / length
  local center = not useObjectCenter and body ~= nil and body.bounds.center or t.position
  local width = math.abs(tonumber(t.lossyScale.x) or 0) * 0.5
  if body ~= nil then
    local extents = body.bounds.extents
    width = math.abs(nz) * extents.x + math.abs(nx) * extents.z
  end
  if width < 0.5 then width = LINE_HALF_WIDTH end
  return {x=center.x,y=center.y,z=center.z,tx=nx,tz=nz,halfWidth=width,source=tostring(object.name)}
end
local function resolveLines()
  local start = findObject({"出发线", "Race_StartLine"})
  lines.start = start ~= nil and sceneLine(start, nil, false)
    or sceneLine(findObject({"B门"}), "Gate_B_Moving_SeaGlass_Panel", true)
  lines.check = sceneLine(findObject({"检查线","Race_CheckLine"}), nil, false)
  local finish = findObject({"_VIS_HEARTWAVE_终点线"})
  lines.finish = finish ~= nil and sceneLine(finish, "Finish_Coral_Centerline", false)
    or sceneLine(findObject({"终点线"}), nil, false)
  geometryStatus = "OK"
  if lines.check == nil then
    -- Migration fallback only. The editor installs a visible marker at this
    -- same location; diagnostics expose its absence instead of hiding it.
    lines.check = {x=130.4644,y=9.0302,z=214,tx=-1,tz=0,halfWidth=LINE_HALF_WIDTH,source="CHECK_LINE_FALLBACK"}
    geometryStatus = "CHECK_LINE_FALLBACK"
  end
  if lines.start == nil then geometryStatus = geometryStatus .. "|START_MISSING" end
  if lines.finish == nil then geometryStatus = geometryStatus .. "|FINISH_MISSING" end
  if lines.start ~= nil then routeSamples[1].x, routeSamples[1].z = lines.start.x, lines.start.z end
  if lines.check ~= nil then routeSamples[7].x, routeSamples[7].z = lines.check.x, lines.check.z end
  if lines.finish ~= nil then routeSamples[13].x, routeSamples[13].z = lines.finish.x, lines.finish.z end
  return lines.start ~= nil and lines.check ~= nil and lines.finish ~= nil
end
local function crossingAmount(previous, current, line)
  if previous == nil or current == nil or line == nil then return nil end
  local before = (previous.x-line.x)*line.tx+(previous.z-line.z)*line.tz
  local after = (current.x-line.x)*line.tx+(current.z-line.z)*line.tz
  -- No epsilon dead-zone: small incremental movements must still cross.
  if before >= 0 or after < 0 then return nil end
  local amount = before / (before-after)
  local x = previous.x+(current.x-previous.x)*amount
  local y = previous.y+(current.y-previous.y)*amount
  local z = previous.z+(current.z-previous.z)*amount
  local lateral = math.abs((x-line.x)*-line.tz+(z-line.z)*line.tx)
  if lateral > line.halfWidth or math.abs(y-line.y) > LINE_VERTICAL_TOLERANCE then return nil end
  return amount
end
local function projectRouteProgress(position)
  if position == nil then return 0 end
  local bestDistance, bestArc = math.huge, 0
  for index=1,#routeSamples-1 do
    local left,right = routeSamples[index],routeSamples[index+1]
    local dx,dz = right.x-left.x,right.z-left.z
    local square = dx*dx+dz*dz
    if square > 0.000001 then
      local t = math.max(0,math.min(1,((position.x-left.x)*dx+(position.z-left.z)*dz)/square))
      local ox,oz = position.x-left.x-dx*t,position.z-left.z-dz*t
      if ox*ox+oz*oz < bestDistance then
        bestDistance,bestArc = ox*ox+oz*oz,left.arc+(right.arc-left.arc)*t
      end
    end
  end
  return bestArc
end

local function parseLedger(payload)
  local version, cycle, revision, rows = tostring(payload or ""):match("^(RR1)|(%d+)|(%d+)|(.*)$")
  if version == nil then return nil end
  local parsed = {cycle=tonumber(cycle),revision=tonumber(revision),states={}}
  if parsed.cycle <= 0 or parsed.revision <= 0 then return nil end
  local index = 0
  for row in (rows .. ";"):gmatch("(.-);") do
    index = index + 1
    local progress, finished, consumed = row:match("^([012]),([%d%.%-]+),([01])$")
    local at = tonumber(finished)
    if index > #fleetNames or progress == nil or at == nil or at >= math.huge then return nil end
    progress = tonumber(progress)
    if (at >= 0 or consumed == "1") and progress ~= 2 then return nil end
    if consumed == "1" and at < 0 then return nil end
    parsed.states[fleetNames[index]] = {progress=progress,finishAt=at >= 0 and at or nil,consumed=consumed == "1"}
  end
  return index == #fleetNames and parsed or nil
end
local function mergeLedger(parsed)
  if parsed == nil or parsed.cycle ~= activeCycleId or parsed.revision < ledgerRevision then return false end
  completedVehicleCount = 0
  for _,name in ipairs(fleetNames) do
    local incoming, current = parsed.states[name], stateByVehicle[name]
    current.progress = math.max(current.progress,incoming.progress)
    if incoming.finishAt ~= nil and (current.finishAt == nil or incoming.finishAt < current.finishAt) then
      current.finishAt = incoming.finishAt
    end
    current.consumed = current.consumed or incoming.consumed
    if current.consumed then completedVehicleCount = completedVehicleCount+1 end
  end
  ledgerRevision = math.max(ledgerRevision,parsed.revision)
  return true
end
local function hydrateLedger()
  if routeProgressLedger == nil then return false end
  local ok, value = pcall(function() return routeProgressLedger:GetValue() end)
  if not ok then return false end
  local parsed = parseLedger(value)
  if parsed == nil or parsed.cycle < activeCycleId then return false end
  local api = managerApi()
  if api == nil or tonumber(api.GetRaceManagerCycleId()) ~= parsed.cycle then return false end
  if parsed.cycle > activeCycleId then RaceRouteValidatorBeginCycle(parsed.cycle) end
  return mergeLedger(parsed)
end
local function publishLedger()
  if not ledgerDirty or not authority() or routeProgressLedger == nil then return false end
  -- Read and merge before writing; a new owner inherits both revision and
  -- accepted progress. Delayed lower revisions can never roll progress back.
  hydrateLedger()
  local rows = {}
  for _,name in ipairs(fleetNames) do
    local state = stateByVehicle[name]
    rows[#rows+1] = tostring(state.progress) .. "," .. (state.finishAt ~= nil and string.format("%.4f",state.finishAt) or "-1")
      .. "," .. (state.consumed and "1" or "0")
  end
  local revision = ledgerRevision+1
  local payload = "RR1|" .. tostring(activeCycleId) .. "|" .. tostring(revision) .. "|" .. table.concat(rows,";")
  local ok = pcall(function() routeProgressLedger:SetValue(payload) end)
  local verified, value = pcall(function() return routeProgressLedger:GetValue() end)
  if not ok or not verified or tostring(value or "") ~= payload then return false end
  ledgerRevision,ledgerDirty = revision,false
  return true
end
function RaceRouteValidatorBeginCycle(cycleId)
  local normalized = math.floor(tonumber(cycleId) or 0)
  if normalized <= 0 or normalized < activeCycleId then return false end
  if normalized == activeCycleId then return true end
  activeCycleId,racingCycleId,completedVehicleCount = normalized,0,0
  ledgerRevision,ledgerDirty,wasAuthority = 0,true,false
  stateByVehicle = {}
  for _,name in ipairs(fleetNames) do stateByVehicle[name] = {progress=0,consumed=false} end
  resolveLines()
  return true
end
function RaceRouteValidatorBeginRace(cycleId, sampledAt)
  if not authority() or not RaceRouteValidatorBeginCycle(cycleId) then return false end
  if racingCycleId == activeCycleId and wasAuthority then return true end
  hydrateLedger()
  if not resolveLines() then return false end
  racingCycleId,wasAuthority = activeCycleId,true
  for _,name in ipairs(fleetNames) do
    local t = vehicleTransform(name)
    local state = stateByVehicle[name]
    state.previous,state.previousAt = t ~= nil and copy(t.position) or nil,tonumber(sampledAt)
  end
  publishLedger()
  return true
end
function RaceRouteValidatorSample(cycleId, sampledAt, startAt, endAt)
  if not authority() or tonumber(cycleId) ~= activeCycleId or racingCycleId ~= activeCycleId then return false end
  local api = managerApi()
  if api == nil or api.GetRaceManagerState() ~= "RACING" then return false end
  sampledAt,startAt,endAt = tonumber(sampledAt),tonumber(startAt),tonumber(endAt)
  if sampledAt == nil or startAt == nil or endAt == nil or endAt <= startAt then return false end
  for _,name in ipairs(fleetNames) do
    local state,t = stateByVehicle[name],vehicleTransform(name)
    if state ~= nil and t ~= nil and not state.consumed and state.finishAt == nil then
      local current = copy(t.position)
      if participating(name) and state.previousAt ~= nil and sampledAt > state.previousAt then
        local line = state.progress == 0 and lines.start or state.progress == 1 and lines.check or lines.finish
        local amount = crossingAmount(state.previous,current,line)
        if amount ~= nil then
          local crossedAt = state.previousAt+(sampledAt-state.previousAt)*amount
          if crossedAt >= startAt and crossedAt < endAt then
            if state.progress < 2 then state.progress = state.progress+1 else state.finishAt = crossedAt end
            ledgerDirty = true
          end
        end
      end
      if state.previousAt == nil or sampledAt > state.previousAt then state.previous,state.previousAt = current,sampledAt end
    end
  end
  publishLedger()
  return true
end
function RaceRouteValidatorIsEligible(vehicleName, cycleId)
  local state = stateByVehicle[tostring(vehicleName or "")]
  return tonumber(cycleId) == activeCycleId and activeCycleId > 0 and state ~= nil
    and state.progress == 2 and state.finishAt ~= nil and not state.consumed
end
function RaceRouteValidatorConsumeFinish(vehicleName, cycleId)
  if not authority() or not RaceRouteValidatorIsEligible(vehicleName,cycleId) then return false end
  stateByVehicle[tostring(vehicleName)].consumed = true
  completedVehicleCount = completedVehicleCount+1
  ledgerDirty = true
  publishLedger()
  return true
end
function GetRaceRouteVehicleFinishUnixMilliseconds(vehicleName, cycleId)
  local state = stateByVehicle[tostring(vehicleName or "")]
  return tonumber(cycleId) == activeCycleId and state ~= nil and state.finishAt or -1
end
function GetRaceRouteValidatorStatus()
  return activeCycleId,3,completedVehicleCount,#fleetNames,LINE_HALF_WIDTH
end
function GetRaceRouteVehicleState(vehicleName)
  local state = stateByVehicle[tostring(vehicleName or "")]
  return state ~= nil and state.progress or -1, state ~= nil and state.finishAt or -1,
    state ~= nil and state.consumed or false, ledgerRevision
end
function GetRaceRouteGeometryStatus()
  local function encoded(line)
    if line == nil then return "MISSING" end
    return string.format("%s|%.4f,%.4f,%.4f|%.6f,%.6f|%.4f",line.source,line.x,line.y,line.z,line.tx,line.tz,line.halfWidth)
  end
  return geometryStatus,encoded(lines.start),encoded(lines.check),encoded(lines.finish)
end
function GetRaceRouteVehicleProgress(vehicleName)
  local name = tostring(vehicleName or "")
  local state,t = stateByVehicle[name],vehicleTransform(name)
  if state == nil then return -1 end
  if state.finishAt ~= nil or state.consumed then return 897.219 end
  local projected = projectRouteProgress(t ~= nil and t.position or nil)
  if state.progress == 0 then return 0 end
  if state.progress == 1 then return math.min(444.999,projected) end
  return math.max(445,projected)
end
function Start()
  resolveLines()
end
-- Manager samples before consuming finishes and before changing the phase.
-- Independent Unity Update order must never decide whether a finish counts.
function Update()
  if not authority() then wasAuthority = false end
end
function OnNetSpawned()
  if routeProgressLedger ~= nil and ledgerChangeHandle == nil then
    ledgerChangeHandle = routeProgressLedger:OnValueChange(function() hydrateLedger() end)
  end
  hydrateLedger()
end
function OnVariablesSynced() hydrateLedger() end
function OnOwnershipTransferred()
  wasAuthority = false
  hydrateLedger()
end
function OnDestroy()
  if routeProgressLedger ~= nil and ledgerChangeHandle ~= nil then
    pcall(function() routeProgressLedger:RemoveOnValueChange(ledgerChangeHandle) end)
  end
  vehicleTransforms,stateByVehicle,managerHolder = {},{},nil
end
