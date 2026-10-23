---@id dafb9e9f-3e96-40fb-8fc3-8384dd7687e2
-- Persistent seat-station relay. Each passenger station is a separate scene
-- GameObject, so the engine never treats driver and passenger as one seat.

---@start
---@var seatId:string="front_passenger"
---@name 逻辑座位 ID
---@desc 必须与车辆脚本中的座位 ID 完全一致
---@group 座位路由
---@var vehicleScriptName:string=""
---@name 车辆脚本标识
---@desc 优先填写编辑器脚本 UUID；也兼容文件名
---@group 座位路由
---@end

local UnityEngine = CS.UnityEngine
local vehicleHolder = nil
local lastResolveError = ""

local function disableStationPresentation()
  local renderers = self.gameObject:GetComponentsInChildren(typeof(UnityEngine.Renderer), true)
  for index = 0, renderers.Length - 1 do renderers[index].enabled = false end
  local colliders = self.gameObject:GetComponentsInChildren(typeof(UnityEngine.Collider), true)
  for index = 0, colliders.Length - 1 do colliders[index].enabled = false end
end

local function resolveVehicleHolder()
  if vehicleHolder ~= nil and vehicleHolder.script ~= nil then return vehicleHolder end
  local root = self.transform.parent
  if root == nil then
    lastResolveError = "seat station has no vehicle parent"
    return nil
  end
  local configured = tostring(vehicleScriptName or "")
  local stripped = string.gsub(configured, "%.lua$", "")
  local candidates = { configured, stripped }
  for i = 1, #candidates do
    if candidates[i] ~= "" then
      local ok, holder = pcall(function()
        return root.gameObject:GetDouyinScript(candidates[i])
      end)
      if ok and holder ~= nil and holder.script ~= nil then
        vehicleHolder = holder
        lastResolveError = ""
        return vehicleHolder
      end
    end
  end
  lastResolveError = "vehicle script binding unavailable: " .. configured
  return nil
end

function OnSeatEntered(actor, handType)
  local holder = resolveVehicleHolder()
  if holder == nil or holder.script.VehicleSeatStationEntered == nil then
    UnityEngine.Debug.LogError("VehicleSeatStationRelay: " .. lastResolveError)
    return
  end
  holder.script.VehicleSeatStationEntered(actor, seatId, handType)
end

function OnSeatExited(actor)
  local holder = resolveVehicleHolder()
  if holder == nil or holder.script.VehicleSeatStationExited == nil then
    UnityEngine.Debug.LogError("VehicleSeatStationRelay: " .. lastResolveError)
    return
  end
  holder.script.VehicleSeatStationExited(actor, seatId)
end

function GetVehicleSeatStationRelayStatus()
  local holder = resolveVehicleHolder()
  return holder ~= nil, tostring(seatId or ""), tostring(vehicleScriptName or ""), lastResolveError
end

function Start()
  disableStationPresentation()
  resolveVehicleHolder()
end

function OnDestroy()
  vehicleHolder = nil
end
