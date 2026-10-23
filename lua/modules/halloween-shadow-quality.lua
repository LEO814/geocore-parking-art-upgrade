---@id c5ceda7b-dc29-4dfb-b2cc-c45eb90ce772
---@referenceName halloween-shadow-quality.lua
---@var shadowProfile:string="auto"
-- Visual-only URP limits; no renderer ownership, seat, timing or physics changes.
local S={U=CS.UnityEngine,records={},nextAt=0,enabled=true,error='',profile='pending',distance=0,resolution=0,cascades=0}
function S.choose()
 local mode=tostring(shadowProfile or'auto')
 if mode=='balanced'then return'balanced',60,1024,1 end
 if mode=='high'then return'high',90,2048,2 end
 if mode=='desktop'then return'desktop',100,2048,2 end
 local mobile=false;pcall(function()mobile=S.U.Application.isMobilePlatform or tostring(S.U.SystemInfo.deviceType):find('Handheld',1,true)~=nil end)
 if not mobile then return'desktop',100,2048,2 end
 local high=false;pcall(function()high=S.U.SystemInfo.systemMemorySize>=6000 and S.U.SystemInfo.graphicsMemorySize>=2000 end)
 if high then return'high',90,2048,2 end;return'balanced',60,1024,1
end
function S.apply()
 local asset=S.U.Rendering.GraphicsSettings.currentRenderPipeline
 if not asset then S.error='WAIT_RENDER_PIPELINE';return false end
 local record=S.records[asset]
 if not record then record={distance=asset.shadowDistance,resolution=asset.mainLightShadowmapResolution,cascades=asset.shadowCascadeCount};S.records[asset]=record end
 local profile,distance,resolution,cascades=S.choose()
 local d,r,c=math.min(record.distance,distance),math.min(record.resolution,resolution),math.min(record.cascades,cascades)
 if asset.shadowDistance~=d then asset.shadowDistance=d end;if asset.mainLightShadowmapResolution~=r then asset.mainLightShadowmapResolution=r end;if asset.shadowCascadeCount~=c then asset.shadowCascadeCount=c end
 S.profile=profile;S.asset=asset;S.distance=asset.shadowDistance;S.resolution=asset.mainLightShadowmapResolution;S.cascades=asset.shadowCascadeCount;S.error='';return true
end
function S.tick()local ok,err=pcall(S.apply);if not ok then S.error=tostring(err)end end
function Awake()S.tick()end
function Start()S.tick()end
function Update()if S.enabled and S.U.Time.realtimeSinceStartup>=S.nextAt then S.nextAt=S.U.Time.realtimeSinceStartup+2;S.tick()end end
function S.restore()
 for a,r in pairs(S.records)do pcall(function()a.shadowDistance=r.distance;a.mainLightShadowmapResolution=r.resolution;a.shadowCascadeCount=r.cascades end)end
 S.records={}
end
function OnDisable()S.enabled=false;S.restore()end
function OnEnable()S.enabled=true;S.nextAt=0 end
function OnDestroy()S.enabled=false;S.restore()end
function HalloweenGetShadowStatus()return'profile='..S.profile..'|distance='..S.distance..'|resolution='..S.resolution..'|cascades='..S.cascades..'|error='..S.error end
