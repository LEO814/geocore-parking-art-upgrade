---@id 09e55e7e-926a-4f36-af12-dd4ba8bb26ae
-- PERF-0911: local visual-only distance culling. No collider/root activation changes.
local U=CS.UnityEngine
local D={groups={},nextAt=0,retryAt=0,started=false}
local names={"地心飞车_中央火山","赛道氛围_01_西北回弯内侧水晶","赛道氛围_02_西侧S弯内侧水晶","赛道氛围_03_西部大回弯水晶","赛道氛围_04_南部回弯水晶","赛道氛围_05_东侧回弯水晶","赛道氛围_06_东北回弯水晶"}
local function restore()
  for _,group in pairs(D.groups) do
    for _,entry in ipairs(group.entries) do pcall(function() entry.renderer.enabled=entry.original end) end
  end
  D.groups={}
end
local function discover()
  for _,name in ipairs(names) do
    if D.groups[name]==nil then
      local root=U.GameObject.Find(name)
      if root~=nil then
        local group={entries={}}
        local rs=root:GetComponentsInChildren(typeof(U.Renderer),true)
        for i=0,rs.Length-1 do
          local r=rs[i];local n=tostring(r.gameObject.name)
          local rubble=n=="Rubble"
          local detail=n=="LavaSeams" or n=="CraterHotFissures" or string.match(n,"^HotVein_")~=nil
          if rubble or detail then
            group.entries[#group.entries+1]={renderer=r,original=r.enabled,hidden=false,hide=rubble and 85 or 120,show=rubble and 70 or 100}
          end
        end
        D.groups[name]=group
      end
    end
  end
  D.retryAt=U.Time.time+5
end
function Start() D.started=true;discover() end
function Update()
  local now=U.Time.time
  if now<D.nextAt then return end
  D.nextAt=now+0.25
  if now>=D.retryAt then discover() end
  local camera=U.Camera.main
  if camera==nil then return end
  local p=camera.transform.position
  for name,group in pairs(D.groups) do
    local valid=true
    for _,entry in ipairs(group.entries) do
      local ok=pcall(function()
        local q=entry.renderer.bounds:ClosestPoint(p)
        local dist2=(p.x-q.x)^2+(p.y-q.y)^2+(p.z-q.z)^2
        local hidden=entry.hidden
        if hidden and dist2<entry.show*entry.show then hidden=false
        elseif not hidden and dist2>entry.hide*entry.hide then hidden=true end
        if hidden~=entry.hidden then entry.renderer.enabled=entry.original and not hidden;entry.hidden=hidden end
      end)
      if not ok then valid=false end
    end
    if not valid then D.groups[name]=nil end
  end
end
function GetDistanceDetailStatus()
  local total,hidden=0,0
  for _,group in pairs(D.groups) do for _,entry in ipairs(group.entries) do total=total+1;if entry.hidden then hidden=hidden+1 end end end
  return total,hidden
end
function OnDisable() restore() end
function OnEnable() if D.started then D.nextAt=0;D.retryAt=0 end end
function OnDestroy() restore() end
