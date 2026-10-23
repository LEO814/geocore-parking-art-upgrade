---@id 5e456520-b3ca-4ce4-942c-6ebf3c20e708
-- Compatibility entry points only. All 16 cars have one material owner on RaceManager.
local U=CS.UnityEngine
local function api()
 local root=U.GameObject.Find('RaceManager');if not root then return nil end
 local holder=root:GetDouyinScript('b0736d43-07df-4c78-9723-a82192114700')
 return holder and holder.script
end
local function request(name,force)
 name=tostring(name or'')
 if name~='暮翼巡游'and name~='甜咒南瓜'then return false,'ROOT_NOT_ALLOWED'end
 local service=api();local root=U.GameObject.Find(name)
 if not service or not root then return false,'WAIT_SOURCE_ROOT'end
 if force then return service.NotifyVehicleVisualRebuilt(root)end
 return service.RequestVehicleMaterialRestore(root)
end
function RequestHalloweenVehicleMaterialRestore(name)return request(name,false)end
function NotifyHalloweenVehicleVisualRebuilt(name)return request(name,true)end
function GetHalloweenVehicleMaterialRestoreStatus()
 local service=api();if not service then return 'state=WAIT_MATERIAL_SERVICE'end
 return 'owner=SOURCE_COPY_V4;暮翼巡游{'..service.GetVehicleMaterialDetailedStatus('暮翼巡游')..'};甜咒南瓜{'..service.GetVehicleMaterialDetailedStatus('甜咒南瓜')..'}'
end
