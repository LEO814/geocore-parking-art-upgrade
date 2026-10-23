---@id fdd5cb4c-4051-4cdc-b7a1-e1326b23f8a1
-- Additive local visual layer for the five new Halloween NPC platforms.
-- The only legacy visual change is Renderer.enabled=false for the exact old
-- parking floor + four walls, to remove their coplanar transparent depth.
-- GameObject active states, Colliders, physics and all materials stay unchanged.
-- Every generated station Renderer and Material is still newly owned here.
local F={U=CS.UnityEngine,root=nil,entries={},materials={},nextAt=0,nextDiscoverAt=0,names={"南瓜小侯爵","薄荷小幽灵","月帽小女巫","蝙蝠邮差","糖纸木乃伊"},destroyed=false}
-- Five exact leaf objects only; never disable the parent region root or the
-- new GLB deck. Cache Renderers after resources have finished loading.
F.legacyParkingNames={
  "选车区_红色有效区域",
  "选车区_透明围栏模型_北侧围栏",
  "选车区_透明围栏模型_南侧围栏",
  "选车区_透明围栏模型_东侧围栏",
  "选车区_透明围栏模型_西侧围栏",
  "选车区_舞台外缘空气墙_右前段",
  "选车区_舞台外缘空气墙_西侧",
  "选车区_舞台外缘空气墙_东侧",
  "选车区_舞台外缘空气墙_后侧",

}
F.legacyParkingTargets={}
F.legacyParkingRootCount,F.legacyParkingDisabledCount,F.legacyParkingPending=0,0,5
function F.suppressLegacyParkingRenderers()
  local found,disabled,pending=0,0,0
  for _,name in ipairs(F.legacyParkingNames)do
    local target=F.legacyParkingTargets[name]
    if target==nil or target.root==nil then
      target=nil
      local root=F.U.GameObject.Find(name)
      if root then
        local renderers=root:GetComponentsInChildren(typeof(F.U.Renderer),true)
        if renderers.Length>0 then
          target={root=root,renderers={}}
          for i=0,renderers.Length-1 do
            local renderer=renderers[i]
            target.renderers[#target.renderers+1]={renderer=renderer,wasEnabled=renderer.enabled}
          end
          F.legacyParkingTargets[name]=target
        end
      end
    end
    local live=0
    if target then
      for _,state in ipairs(target.renderers)do
        local renderer=state.renderer
        if renderer~=nil then
          live=live+1
          if renderer.enabled then renderer.enabled=false end
          if not renderer.enabled then disabled=disabled+1 end
        end
      end
    end
    if live>0 then found=found+1
    else F.legacyParkingTargets[name]=nil;pending=pending+1 end
  end
  F.legacyParkingRootCount,F.legacyParkingDisabledCount,F.legacyParkingPending=found,disabled,pending
end
function F.restoreLegacyParkingRenderers()
  for _,target in pairs(F.legacyParkingTargets)do
    for _,state in ipairs(target.renderers)do
      pcall(function()if state.renderer~=nil then state.renderer.enabled=state.wasEnabled end end)
    end
  end
  F.legacyParkingTargets={}
end
function GetLegacyParkingRenderStatus()
  return F.legacyParkingRootCount,F.legacyParkingDisabledCount,F.legacyParkingPending
end
function F.material(key)
  if F.materials[key]then return F.materials[key]end
  local shader=F.U.Shader.Find("Universal Render Pipeline/Lit")or F.U.Shader.Find("Standard")or F.U.Shader.Find("Unlit/Color")
  if not shader then return nil end
  local m=F.U.Material(shader);m.name="HalloweenHubFX_NewOwned_"..key
  local c=key=="orange"and F.U.Color(1,.49,.14,1)or(key=="mint"and F.U.Color(.40,1,.77,1)or F.U.Color(.19,.12,.27,1))
  m.color=c;if m:HasProperty("_BaseColor")then m:SetColor("_BaseColor",c)end
  if m:HasProperty("_Metallic")then m:SetFloat("_Metallic",key=="case"and .35 or .05)end
  if m:HasProperty("_Smoothness")then m:SetFloat("_Smoothness",.46)end
  if key~="case"and m:HasProperty("_EmissionColor")then m:EnableKeyword("_EMISSION");m:SetColor("_EmissionColor",F.U.Color(c.r*1.8,c.g*1.8,c.b*1.8,1))end
  F.materials[key]=m;return m
end
function F.part(name,kind,scale,pos,key,parent)
  local go=F.U.GameObject.CreatePrimitive(kind);go.name="HalloweenHubFX_"..name;go.transform:SetParent(parent.transform,false);go.transform.localPosition=pos;go.transform.localScale=scale
  local collider=go:GetComponent(typeof(F.U.Collider));if collider then collider.enabled=false;F.U.Object.Destroy(collider)end
  local renderer=go:GetComponent(typeof(F.U.Renderer));renderer.sharedMaterial=F.material(key)
  pcall(function()renderer.shadowCastingMode=F.U.Rendering.ShadowCastingMode.Off;renderer.receiveShadows=false end)
  return go
end
function F.create(id,npc)
  if not F.root then F.root=F.U.GameObject("HalloweenHubFX_NewNPCStations_Only")end
  local root=F.U.GameObject("HalloweenHubFX_Station_"..id);root.transform:SetParent(F.root.transform,false)
  root.transform.position=npc.transform.position+npc.transform.right*1.05+npc.transform.forward*.2
  root.transform.rotation=npc.transform.rotation
  local entry={root=root,candies={},visible=true,origin=root.transform.position}
  F.part("StationFoot",F.U.PrimitiveType.Cube,F.U.Vector3(.82,.06,.30),F.U.Vector3(0,.03,0),"case",root)
  for side=-1,1,2 do
    local x=side*.27
    F.part("Post_"..side,F.U.PrimitiveType.Cylinder,F.U.Vector3(.045,.47,.045),F.U.Vector3(x,.52,0),"case",root)
    F.part("LanternCase_"..side,F.U.PrimitiveType.Cube,F.U.Vector3(.21,.24,.21),F.U.Vector3(x,1.05,0),"case",root)
    F.part("LanternGlow_"..side,F.U.PrimitiveType.Sphere,F.U.Vector3(.17,.17,.17),F.U.Vector3(x,1.06,.10),side<0 and"orange"or"mint",root)
  end
  for i=1,2 do
    local candy=F.U.GameObject("HalloweenHubFX_FloatingCandy_"..i);candy.transform:SetParent(root.transform,false)
    F.part("CandyCore",F.U.PrimitiveType.Sphere,F.U.Vector3(.075,.075,.075),F.U.Vector3.zero,i==1 and"orange"or"mint",candy)
    F.part("CandyWrapA",F.U.PrimitiveType.Cube,F.U.Vector3(.038,.034,.034),F.U.Vector3(-.057,0,0),"case",candy)
    F.part("CandyWrapB",F.U.PrimitiveType.Cube,F.U.Vector3(.038,.034,.034),F.U.Vector3(.057,0,0),"case",candy)
    entry.candies[i]=candy
  end
  F.entries[id]=entry
end
function F.discover()
  F.suppressLegacyParkingRenderers() -- 2-second cached check, no Collider/active/material writes.
  for id,name in ipairs(F.names)do if not F.entries[id]then local npc=F.U.GameObject.Find("万圣NPC_"..name);if npc then F.create(id,npc)end end end
end
function F.tick()
  local rt=F.U.Time.realtimeSinceStartup
  if rt>=F.nextDiscoverAt then F.nextDiscoverAt=rt+2;F.discover()end
  local actor=CS.DouyinActorService.GetLocalActor();local any=false
  for id,e in pairs(F.entries)do
    local visible=actor~=nil and(actor.position-e.origin).sqrMagnitude<65*65
    if visible~=e.visible then e.root:SetActive(visible);e.visible=visible end
    if visible then
      any=true
      for i,candy in ipairs(e.candies)do local phase=rt*.70+id*1.27+i*math.pi
        candy.transform.localPosition=F.U.Vector3(math.cos(phase)*.24,1.43+math.sin(phase*1.3)*.12,math.sin(phase)*.16)
        candy.transform.localRotation=F.U.Quaternion.Euler(12*math.sin(phase),rt*28+i*40,12*math.cos(phase))
      end
    end
  end
  -- Two shared material writes at 10 Hz; no realtime lights, global Bloom,
  -- particle-system activation or per-frame scans of the scene are required.
  if any then
    local power=1.45+.35*(.5+.5*math.sin(rt*1.1))
    for key,m in pairs(F.materials)do if key~="case"and m:HasProperty("_EmissionColor")then local c=m.color;m:SetColor("_EmissionColor",F.U.Color(c.r*power,c.g*power,c.b*power,1))end end
  end
end
function Start()pcall(F.discover)end
function Update()
  if F.destroyed then return end
  local rt=F.U.Time.realtimeSinceStartup;if rt<F.nextAt then return end;F.nextAt=rt+.10
  local ok,err=pcall(F.tick);if not ok then F.U.Debug.LogWarning("HALLOWEEN_HUB_FX "..tostring(err))end
end
function OnEnable()if F.root then F.root:SetActive(true)end end
function OnDisable()if F.root then F.root:SetActive(false)end end
function OnDestroy()
  F.restoreLegacyParkingRenderers() -- Restore only the exact prior Renderer.enabled flags.
  F.destroyed=true;if F.root then F.U.Object.Destroy(F.root)end
  for _,m in pairs(F.materials)do F.U.Object.Destroy(m)end
  F.entries,F.materials={},{}
end

-- A local animated light rig for each new NPC plinth. No particles.
F.beacons,F.beaconErrors={},{}
function F.beaconMaterial(key,beam)
 local id=key..(beam and'_beam'or'_rim');if F.materials[id]then return F.materials[id]end
 local U=F.U;local shader=U.Shader.Find(beam and'Universal Render Pipeline/Unlit'or'Universal Render Pipeline/Lit')or U.Shader.Find('Standard')
 local m=U.Material(shader);local c=key=='mint'and U.Color(.36,.89,1,beam and .065 or 1)or U.Color(1,.56,.23,beam and .065 or 1)
 m.color=c;if m:HasProperty('_BaseColor')then m:SetColor('_BaseColor',c)end
 if beam then
  for k,v in pairs({_Surface=1,_Blend=1,_SrcBlend=5,_DstBlend=1,_ZWrite=0,_Cull=0})do if m:HasProperty(k)then m:SetFloat(k,v)end end
  m:EnableKeyword('_SURFACE_TYPE_TRANSPARENT');m.renderQueue=3000
 elseif m:HasProperty('_EmissionColor')then m:EnableKeyword('_EMISSION');m:SetColor('_EmissionColor',U.Color(c.r*2,c.g*2,c.b*2,1))end
 F.materials[id]=m;return m
end
function F.createBeacon(id,npc)
 local U=F.U;local root=U.GameObject('Halloween_NPC_PlatformSpotlight_'..id);root.transform:SetParent(F.root.transform,false)
 root.transform.position=npc.transform.position;local color=id==2 or id==3;local key=color and'mint'or'orange'
 local row={root=root,npc=npc,id=id,lines={}}
 for ring=1,2 do
  local go=U.GameObject('Breathing_Plinth_Ring_'..ring);go.transform:SetParent(root.transform,false)
  local line=go:AddComponent(typeof(U.LineRenderer));line.useWorldSpace=false;line.positionCount=65;line.widthMultiplier=ring==1 and .065 or .035;line.sharedMaterial=F.beaconMaterial(key,false)
  for k=0,64 do local a=k*math.pi*2/64;line:SetPosition(k,U.Vector3(math.cos(a)*(1.15+ring*.18),.025,math.sin(a)*(1.15+ring*.18)))end
  row.lines[ring]=line
 end
 local lightGo=U.GameObject('Animated_Character_Spot');lightGo.transform:SetParent(root.transform,false)
 lightGo.transform.localPosition=U.Vector3(0,5.9,.65);local light=lightGo:AddComponent(typeof(U.Light));light.type=U.LightType.Spot;light.range=9;light.spotAngle=44;light.intensity=2.3;light.shadows=U.LightShadows.None;light.color=color and U.Color(.55,.82,1,1)or U.Color(1,.78,.49,1);row.light,row.lightGo=light,lightGo
 -- A low-opacity additive cone makes the spotlight visible in the air.
 local cone=U.GameObject('Soft_Sweeping_LightCone');cone.transform:SetParent(root.transform,false)
 local vertices=CS.System.Array.CreateInstance(typeof(U.Vector3),66);local indices=CS.System.Array.CreateInstance(typeof(CS.System.Int32),64*3)
 vertices[0]=U.Vector3(0,5.8,.65)
 for k=0,64 do local a=k*math.pi*2/64;vertices[k+1]=U.Vector3(math.cos(a)*1.65,.04,math.sin(a)*1.65);if k<64 then indices[k*3]=0;indices[k*3+1]=k+1;indices[k*3+2]=k+2 end end
 local mesh=U.Mesh();mesh.name='Halloween_LightCone_Owned';mesh.vertices=vertices;mesh.triangles=indices;mesh:RecalculateNormals();mesh:RecalculateBounds()
 local filter=cone:AddComponent(typeof(U.MeshFilter));filter.sharedMesh=mesh;local renderer=cone:AddComponent(typeof(U.MeshRenderer));renderer.sharedMaterial=F.beaconMaterial(key,true);renderer.shadowCastingMode=U.Rendering.ShadowCastingMode.Off;renderer.receiveShadows=false
 row.cone,row.mesh=cone,mesh;F.beacons[id]=row
end
F.beaconTickBase=F.tick
function F.tick()
 F.beaconTickBase();local U=F.U;local rt=U.Time.realtimeSinceStartup;local actor=CS.DouyinActorService.GetLocalActor()
 for id,name in ipairs(F.names)do
  if not F.beacons[id]then local npc=U.GameObject.Find('万圣NPC_'..name);if npc then local ok,err=pcall(F.createBeacon,id,npc);if not ok then F.beaconErrors[id]=tostring(err)end end end
 end
 for id,row in pairs(F.beacons)do
  row.root.transform.position=row.npc.transform.position
  local near=actor and(actor.position-row.root.transform.position).sqrMagnitude<85*85
  row.root:SetActive(near==true)
  if near then
   local p=rt*.75+id*.82;row.light.intensity=2.2+.35*math.sin(p);row.light.spotAngle=44+4*math.sin(p*.65)
   local target=row.root.transform.position+U.Vector3(math.sin(p)*.20,1.45,math.cos(p)*.12)
   row.lightGo.transform.rotation=U.Quaternion.LookRotation(target-row.lightGo.transform.position)
   row.cone.transform.localRotation=U.Quaternion.Euler(math.sin(p)*1.8,math.sin(p*.5)*8,math.cos(p)*1.8)
   for i,line in ipairs(row.lines)do line.widthMultiplier=(i==1 and .065 or .035)*(1+.18*math.sin(p+i));line.transform.localRotation=U.Quaternion.Euler(0,rt*(i==1 and 8 or-11),0)end
  end
 end
end
F.beaconDestroyBase=OnDestroy
function OnDestroy()for _,row in pairs(F.beacons)do if row.mesh then F.U.Object.Destroy(row.mesh)end end;F.beaconDestroyBase()end
function HalloweenGetBeaconStatus()local rows={};for id in pairs(F.beacons)do rows[#rows+1]=id..':spot+cone+2rings'end;for id,e in pairs(F.beaconErrors)do rows[#rows+1]=id..':ERROR:'..e end;return table.concat(rows,'|')end
