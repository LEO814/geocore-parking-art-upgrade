---@id 470fcf4c-157b-4b91-8b0e-1e71137e803a
-- Visual registration only; does not write seats, driving, race or synchronized state.
local U=CS.UnityEngine
local pending,attempt,nextAt,force=true,0,0,false
local manager=nil
local function bind()
 if manager~=nil and manager.gameObject~=nil and manager.gameObject.activeInHierarchy and manager.script~=nil then return manager.script end
 local root=U.GameObject.Find('RaceManager');if root==nil then return nil end
 manager=root:GetDouyinScript('b0736d43-07df-4c78-9723-a82192114700')
 return manager and manager.script
end
local function begin()
 if not pending then return end
 local ok,accepted=pcall(function()
  local service=bind();if not service then return false end
  if force then return service.NotifyVehicleVisualRebuilt(self.gameObject)end
  return service.RequestVehicleMaterialRestore(self.gameObject)
 end)
 if ok and accepted then pending=false;return end
 attempt=attempt+1;nextAt=U.Time.unscaledTime+math.min(.25,.05*math.max(1,attempt))
end
local function schedule(rebuilt)
 pending=true;attempt=0;nextAt=0;force=rebuilt;begin()
end
function Awake()begin()end
function Start()begin()end
function OnEnable()schedule(true)end
function OnNetSpawned()schedule(true)end
function Update()if pending and U.Time.unscaledTime>=nextAt then begin()end end
function OnDestroy()
 pending=false
 pcall(function()local service=bind();if service then service.ReleaseVehicleMaterialRestore(self.gameObject)end end)
end
