---@id ec7ad92f-b919-4a13-b609-66056cfc3ded
-- Visual-only adapter for exactly seven new landmark roots. No geometry,
-- Transform, collider, global environment, old material or particle writes.
-- Palette/node order below is generated from the three exact source GLBs.
local F={U=CS.UnityEngine,configs={["A01"]={["sourceSha256"]="49a1383c72bdf3858e813cfd46158bc50b9319cbabf61f25d1b759f912d3eca1",["palette"]={{["name"]="Warm brass | machined",["rgba"]={0.767375665483,0.601243396865,0.340643431164,1},["metallic"]=0.77999997139,["roughness"]=0.270000010729,["glow"]=false,["strength"]=0,["emission"]={0,0,0,1},["alt"]={0.395881264862,0.921191446779,0.803630986887}},{["name"]="Ivory | clock and candy",["rgba"]={0.926074881305,0.88082502109,0.748379069519,1},["metallic"]=0.10000000149,["roughness"]=0.389999985695,["glow"]=false,["strength"]=0,["emission"]={0,0,0,1},["alt"]={0.395881264862,0.921191446779,0.803630986887}},{["name"]="Night purple | enamel",["rgba"]={0.36556462898,0.215081986378,0.484529207832,1},["metallic"]=0.449999988079,["roughness"]=0.300000011921,["glow"]=false,["strength"]=0,["emission"]={0,0,0,1},["alt"]={0.395881264862,0.921191446779,0.803630986887}},{["name"]="Basalt violet | structure",["rgba"]={0.205984157713,0.171844088395,0.260067479943,1},["metallic"]=0.34999999404,["roughness"]=0.550000011921,["glow"]=false,["strength"]=0,["emission"]={0,0,0,1},["alt"]={0.395881264862,0.921191446779,0.803630986887}},{["name"]="Pumpkin copper | lobe alternate",["rgba"]={0.785776927019,0.381091854454,0.0998528212919,1},["metallic"]=0.340000003576,["roughness"]=0.319999992847,["glow"]=false,["strength"]=0,["emission"]={0,0,0,1},["alt"]={0.395881264862,0.921191446779,0.803630986887}},{["name"]="Pumpkin copper | enamel",["rgba"]={0.916273552573,0.527112787404,0.142825677755,1},["metallic"]=0.280000001192,["roughness"]=0.300000011921,["glow"]=false,["strength"]=0,["emission"]={0,0,0,1},["alt"]={0.395881264862,0.921191446779,0.803630986887}},{["name"]="Glow mint | slow hue eligible",["rgba"]={0.395881257971,0.9211914386,0.803630995277,1},["metallic"]=0.119999997318,["roughness"]=0.239999994636,["glow"]=true,["strength"]=1.90899992204,["emission"]={0.825224760531,1.90899992204,1.66645924198,1},["alt"]={0.701410717534,0.349190212628,0.954687171886}},{["name"]="Glow honey | slow hue eligible",["rgba"]={1,0.694360977707,0.234795084186,1},["metallic"]=0.10000000149,["roughness"]=0.239999994636,["glow"]=true,["strength"]=2,["emission"]={2,1.38872195541,0.469590168372,1},["alt"]={0.395881264862,0.921191446779,0.803630986887}}},["parts"]={{["name"]="A01_BrassStep",["mats"]={1}},{["name"]="A01_ClockBezel",["mats"]={1}},{["name"]="A01_ClockDial",["mats"]={2}},{["name"]="A01_ClockHangingBracket",["mats"]={1}},{["name"]="A01_ClockHangingBracket.001",["mats"]={1}},{["name"]="A01_ClockIndex_00",["mats"]={1}},{["name"]="A01_ClockIndex_01",["mats"]={1}},{["name"]="A01_ClockIndex_02",["mats"]={1}},{["name"]="A01_ClockIndex_03",["mats"]={1}},{["name"]="A01_ClockIndex_04",["mats"]={1}},{["name"]="A01_ClockIndex_05",["mats"]={1}},{["name"]="A01_ClockIndex_06",["mats"]={1}},{["name"]="A01_ClockIndex_07",["mats"]={1}},{["name"]="A01_ClockIndex_08",["mats"]={1}},{["name"]="A01_ClockIndex_09",["mats"]={1}},{["name"]="A01_ClockIndex_10",["mats"]={1}},{["name"]="A01_ClockIndex_11",["mats"]={1}},{["name"]="A01_Column",["mats"]={3}},{["name"]="A01_ColumnBrassCollar",["mats"]={1}},{["name"]="A01_ColumnBrassCollar.001",["mats"]={1}},{["name"]="A01_ColumnBrassCollar.002",["mats"]={1}},{["name"]="A01_ColumnBrassCollar.003",["mats"]={1}},{["name"]="A01_CurledStem",["mats"]={1}},{["name"]="A01_HeadSupport",["mats"]={1}},{["name"]="A01_HourHand",["mats"]={3}},{["name"]="A01_MinuteHand",["mats"]={3}},{["name"]="A01_OctagonalPlinth",["mats"]={4}},{["name"]="A01_PumpkinLobe_00",["mats"]={5}},{["name"]="A01_PumpkinLobe_01",["mats"]={6}},{["name"]="A01_PumpkinLobe_02",["mats"]={5}},{["name"]="A01_PumpkinLobe_03",["mats"]={6}},{["name"]="A01_PumpkinLobe_04",["mats"]={5}},{["name"]="A01_PumpkinLobe_05",["mats"]={6}},{["name"]="A01_PumpkinLobe_06",["mats"]={5}},{["name"]="A01_PumpkinLobe_07",["mats"]={6}},{["name"]="A01_PurpleBase",["mats"]={3}},{["name"]="A01_SideSeal",["mats"]={1}},{["name"]="A01_SideSeal.001",["mats"]={1}},{["name"]="A01_TowerFlute",["mats"]={1}},{["name"]="A01_TowerFlute.001",["mats"]={1}},{["name"]="A01_TowerFlute.002",["mats"]={1}},{["name"]="A01_TowerFlute.003",["mats"]={1}},{["name"]="A01_TowerFlute.004",["mats"]={1}},{["name"]="A01_TowerFlute.005",["mats"]={1}},{["name"]="Glow_A01_BaseRing",["mats"]={7}},{["name"]="Glow_A01_ClockAxle",["mats"]={7}},{["name"]="Glow_A01_ClockHalo",["mats"]={8}},{["name"]="Glow_A01_ColumnWindow",["mats"]={8}},{["name"]="Glow_A01_ColumnWindow.001",["mats"]={8}},{["name"]="Glow_A01_ColumnWindow.002",["mats"]={8}},{["name"]="Glow_A01_ColumnWindow.003",["mats"]={8}},{["name"]="Glow_A01_ColumnWindow.004",["mats"]={8}},{["name"]="Glow_A01_ColumnWindow.005",["mats"]={8}},{["name"]="Glow_A01_PumpkinEye",["mats"]={8}},{["name"]="Glow_A01_PumpkinEye.001",["mats"]={8}},{["name"]="Glow_A01_PumpkinSmile",["mats"]={8}}}},["A02"]={["sourceSha256"]="7b05a3c0fc6761a806ea271143db6e92e521d7b2d37023cc0ea521bb61be80c2",["palette"]={{["name"]="Warm brass | machined",["rgba"]={0.767375665483,0.601243396865,0.340643431164,1},["metallic"]=0.77999997139,["roughness"]=0.270000010729,["glow"]=false,["strength"]=0,["emission"]={0,0,0,1},["alt"]={0.395881264862,0.921191446779,0.803630986887}},{["name"]="Basalt violet | structure",["rgba"]={0.205984157713,0.171844088395,0.260067479943,1},["metallic"]=0.34999999404,["roughness"]=0.550000011921,["glow"]=false,["strength"]=0,["emission"]={0,0,0,1},["alt"]={0.395881264862,0.921191446779,0.803630986887}},{["name"]="Night purple | enamel",["rgba"]={0.36556462898,0.215081986378,0.484529207832,1},["metallic"]=0.449999988079,["roughness"]=0.300000011921,["glow"]=false,["strength"]=0,["emission"]={0,0,0,1},["alt"]={0.395881264862,0.921191446779,0.803630986887}},{["name"]="Glow mint | slow hue eligible",["rgba"]={0.395881257971,0.9211914386,0.803630995277,1},["metallic"]=0.119999997318,["roughness"]=0.239999994636,["glow"]=true,["strength"]=1.90899992204,["emission"]={0.825224760531,1.90899992204,1.66645924198,1},["alt"]={0.701410717534,0.349190212628,0.954687171886}},{["name"]="Glow honey | slow hue eligible",["rgba"]={1,0.694360977707,0.234795084186,1},["metallic"]=0.10000000149,["roughness"]=0.239999994636,["glow"]=true,["strength"]=2,["emission"]={2,1.38872195541,0.469590168372,1},["alt"]={0.395881264862,0.921191446779,0.803630986887}},{["name"]="Glow violet | slow hue eligible",["rgba"]={0.701410709185,0.349190215138,0.954687160741,1},["metallic"]=0.10000000149,["roughness"]=0.280000001192,["glow"]=true,["strength"]=1.43999998331,["emission"]={1.05891404332,0.528954478459,1.43999998331,1},["alt"]={0.395881264862,0.921191446779,0.803630986887}}},["parts"]={{["name"]="A02_BaseBolt",["mats"]={1}},{["name"]="A02_BaseBolt.001",["mats"]={1}},{["name"]="A02_BaseBolt.002",["mats"]={1}},{["name"]="A02_BaseBolt.003",["mats"]={1}},{["name"]="A02_BatBody",["mats"]={2}},{["name"]="A02_BatBrassFinger",["mats"]={1}},{["name"]="A02_BatBrassFinger.001",["mats"]={1}},{["name"]="A02_BatEar",["mats"]={3}},{["name"]="A02_BatEar.001",["mats"]={3}},{["name"]="A02_BatWing",["mats"]={2}},{["name"]="A02_BatWing.001",["mats"]={2}},{["name"]="A02_BrassStep",["mats"]={1}},{["name"]="A02_ColumnCollar",["mats"]={1}},{["name"]="A02_ColumnCollar.001",["mats"]={1}},{["name"]="A02_ColumnCollar.002",["mats"]={1}},{["name"]="A02_CrescentForgedBody",["mats"]={3}},{["name"]="A02_CrescentOuterBrass",["mats"]={1}},{["name"]="A02_ObservatoryColumn",["mats"]={3}},{["name"]="A02_OctagonalPlinth",["mats"]={2}},{["name"]="A02_OrbitalGimbal",["mats"]={1}},{["name"]="A02_OrbitalGimbal.001",["mats"]={1}},{["name"]="A02_OrbitalGimbal.002",["mats"]={1}},{["name"]="A02_PurpleBase",["mats"]={3}},{["name"]="A02_TripodBrace",["mats"]={1}},{["name"]="A02_TripodBrace.001",["mats"]={1}},{["name"]="Glow_A02_BaseRing",["mats"]={4}},{["name"]="Glow_A02_BatEye",["mats"]={5}},{["name"]="Glow_A02_BatEye.001",["mats"]={5}},{["name"]="Glow_A02_CrescentInnerRibbon",["mats"]={4}},{["name"]="Glow_A02_ObservatoryCore",["mats"]={6}},{["name"]="Glow_A02_OrbitNode",["mats"]={4}},{["name"]="Glow_A02_OrbitNode.001",["mats"]={4}},{["name"]="Glow_A02_OrbitNode.002",["mats"]={4}}}},["A03"]={["sourceSha256"]="47512b55db618fe0c94ccbd0d14880761bd299bc957a9551e5525f0942b8adec",["palette"]={{["name"]="Warm brass | machined",["rgba"]={0.767375665483,0.601243396865,0.340643431164,1},["metallic"]=0.77999997139,["roughness"]=0.270000010729,["glow"]=false,["strength"]=0,["emission"]={0,0,0,1},["alt"]={0.395881264862,0.921191446779,0.803630986887}},{["name"]="Candy crimson | enamel",["rgba"]={0.820979840171,0.234795084186,0.340643431164,1},["metallic"]=0.20000000298,["roughness"]=0.300000011921,["glow"]=false,["strength"]=0,["emission"]={0,0,0,1},["alt"]={0.395881264862,0.921191446779,0.803630986887}},{["name"]="Ivory | clock and candy",["rgba"]={0.926074881305,0.88082502109,0.748379069519,1},["metallic"]=0.10000000149,["roughness"]=0.389999985695,["glow"]=false,["strength"]=0,["emission"]={0,0,0,1},["alt"]={0.395881264862,0.921191446779,0.803630986887}},{["name"]="Basalt violet | structure",["rgba"]={0.205984157713,0.171844088395,0.260067479943,1},["metallic"]=0.34999999404,["roughness"]=0.550000011921,["glow"]=false,["strength"]=0,["emission"]={0,0,0,1},["alt"]={0.395881264862,0.921191446779,0.803630986887}},{["name"]="Night purple | enamel",["rgba"]={0.36556462898,0.215081986378,0.484529207832,1},["metallic"]=0.449999988079,["roughness"]=0.300000011921,["glow"]=false,["strength"]=0,["emission"]={0,0,0,1},["alt"]={0.395881264862,0.921191446779,0.803630986887}},{["name"]="Glow mint | slow hue eligible",["rgba"]={0.395881257971,0.9211914386,0.803630995277,1},["metallic"]=0.119999997318,["roughness"]=0.239999994636,["glow"]=true,["strength"]=1.90899992204,["emission"]={0.825224760531,1.90899992204,1.66645924198,1},["alt"]={0.701410717534,0.349190212628,0.954687171886}},{["name"]="Glow honey | slow hue eligible",["rgba"]={1,0.694360977707,0.234795084186,1},["metallic"]=0.10000000149,["roughness"]=0.239999994636,["glow"]=true,["strength"]=2,["emission"]={2,1.38872195541,0.469590168372,1},["alt"]={0.395881264862,0.921191446779,0.803630986887}},{["name"]="Glow violet | slow hue eligible",["rgba"]={0.701410709185,0.349190215138,0.954687160741,1},["metallic"]=0.10000000149,["roughness"]=0.280000001192,["glow"]=true,["strength"]=1.43999998331,["emission"]={1.05891404332,0.528954478459,1.43999998331,1},["alt"]={0.395881264862,0.921191446779,0.803630986887}}},["parts"]={{["name"]="A03_BrassStep",["mats"]={1}},{["name"]="A03_CandyConduit_Band_00",["mats"]={2}},{["name"]="A03_CandyConduit_Band_00.001",["mats"]={2}},{["name"]="A03_CandyConduit_Band_01",["mats"]={3}},{["name"]="A03_CandyConduit_Band_01.001",["mats"]={3}},{["name"]="A03_CandyConduit_Band_02",["mats"]={2}},{["name"]="A03_CandyConduit_Band_02.001",["mats"]={2}},{["name"]="A03_CandyConduit_Band_03",["mats"]={3}},{["name"]="A03_CandyConduit_Band_03.001",["mats"]={3}},{["name"]="A03_CandyConduit_Band_04",["mats"]={2}},{["name"]="A03_CandyConduit_Band_04.001",["mats"]={2}},{["name"]="A03_CandyConduit_Band_05",["mats"]={3}},{["name"]="A03_CandyConduit_Band_05.001",["mats"]={3}},{["name"]="A03_CandyConduit_Band_06",["mats"]={2}},{["name"]="A03_CandyConduit_Band_06.001",["mats"]={2}},{["name"]="A03_CandyConduit_Band_07",["mats"]={3}},{["name"]="A03_CandyConduit_Band_07.001",["mats"]={3}},{["name"]="A03_CandyGlyph",["mats"]={3}},{["name"]="A03_CandyWrapper",["mats"]={2}},{["name"]="A03_CandyWrapper.001",["mats"]={2}},{["name"]="A03_CauldronBrassRim",["mats"]={1}},{["name"]="A03_CauldronBrassRim.001",["mats"]={1}},{["name"]="A03_CauldronBrassRim.002",["mats"]={1}},{["name"]="A03_ForgedRivet",["mats"]={1}},{["name"]="A03_ForgedRivet.001",["mats"]={1}},{["name"]="A03_ForgedRivet.002",["mats"]={1}},{["name"]="A03_ForgedRivet.003",["mats"]={1}},{["name"]="A03_ForgedRivet.004",["mats"]={1}},{["name"]="A03_ForgedRivet.005",["mats"]={1}},{["name"]="A03_ForgedRivet.006",["mats"]={1}},{["name"]="A03_ForgedRivet.007",["mats"]={1}},{["name"]="A03_ForgedRivet.008",["mats"]={1}},{["name"]="A03_ForgedRivet.009",["mats"]={1}},{["name"]="A03_FrontMedallion",["mats"]={1}},{["name"]="A03_HandleBracket",["mats"]={1}},{["name"]="A03_HandleBracket.001",["mats"]={1}},{["name"]="A03_OctagonalPlinth",["mats"]={4}},{["name"]="A03_OpenCauldron",["mats"]={5}},{["name"]="A03_PurpleBase",["mats"]={5}},{["name"]="A03_ReactorGimbal",["mats"]={1}},{["name"]="A03_ReactorGimbal.001",["mats"]={1}},{["name"]="A03_ReactorSpine",["mats"]={1}},{["name"]="A03_RivetRib",["mats"]={1}},{["name"]="A03_RivetRib.001",["mats"]={1}},{["name"]="A03_RivetRib.002",["mats"]={1}},{["name"]="A03_RivetRib.003",["mats"]={1}},{["name"]="A03_RivetRib.004",["mats"]={1}},{["name"]="A03_RivetRib.005",["mats"]={1}},{["name"]="A03_RivetRib.006",["mats"]={1}},{["name"]="A03_RivetRib.007",["mats"]={1}},{["name"]="A03_RivetRib.008",["mats"]={1}},{["name"]="A03_RivetRib.009",["mats"]={1}},{["name"]="A03_SideHandle",["mats"]={1}},{["name"]="A03_SideHandle.001",["mats"]={1}},{["name"]="Glow_A03_BaseRing",["mats"]={6}},{["name"]="Glow_A03_Liquid",["mats"]={6}},{["name"]="Glow_A03_ReactorCore",["mats"]={7}},{["name"]="Glow_A03_StaticSugarPearl",["mats"]={6}},{["name"]="Glow_A03_StaticSugarPearl.001",["mats"]={6}},{["name"]="Glow_A03_StaticSugarPearl.002",["mats"]={6}},{["name"]="Glow_A03_SugarHelix",["mats"]={8}}}}},rootModels={"A01","A02","A03","A01","A02","A03","A01"},records={},owned={},cache={},nextAt=0,nextDiscoverAt=0,nextClockAt=0,clockSample=nil,clockSampleAt=0,clockSource="LOCAL_TIME",errors=0,lastError="",lastErrorByRoot={},sample="",updated=0,destroyed=false}
F.rootPrefix,F.distance,F.interval="HalloweenLandmark_",180,.125
function F.rt()return tonumber(F.U.Time.realtimeSinceStartup)or 0 end
function F.rootName(i)return F.rootPrefix..string.format("%02d",i)end
function F.hash(s)local v=17;for i=1,#s do v=(v*131+string.byte(s,i))%104729 end;return v end
function F.error(rootName,message)
  message=tostring(message or"")
  if F.lastErrorByRoot[rootName]~=message then F.errors=F.errors+1;F.lastError=message;F.lastErrorByRoot[rootName]=message end
end
function F.color(v)return F.U.Color(v[1],v[2],v[3],v[4]or 1)end
function F.float(m,k,v)if m:HasProperty(k)then m:SetFloat(k,v)end end
function F.clock(rt)
  if rt>=F.nextClockAt then
    F.nextClockAt=rt+1
    local ok,value=pcall(function()
      if not F.clockHolder or not F.clockHolder.script then
        local go=F.U.GameObject.Find("RaceManager")
        if go then F.clockHolder=go:GetDouyinScript("650f9bb2-f983-4c39-9b98-456d89b19dd2")end
      end
      local api=F.clockHolder and F.clockHolder.script
      if api and api.GetRaceManagerClockReady and api.GetRaceManagerClockReady()then
        local ms=tonumber(api.GetRaceManagerServerUnixMilliseconds())
        if ms and ms>0 and ms<4102444800000 then return ms/1000 end
      end
      return nil
    end)
    if ok and value then
      if value~=F.clockSample then F.clockSample,F.clockSampleAt=value,rt end
      F.clockSource="ROOM_CLOCK"
    elseif not ok then F.clockHolder=nil end
  end
  if F.clockSample then return F.clockSample+rt-F.clockSampleAt end
  return rt
end
function F.makeMaterial(rootName,index,original,config)
  local key=rootName.."/"..index
  if F.cache[key]then return F.cache[key]end
  if not original then error("LANDMARK_SOURCE_MATERIAL_MISSING_"..key)end
  local shader=F.U.Shader.Find("Douyin/AI/PBR/EnvLit_AI")
  if not shader then error("LANDMARK_ENVLIT_SHADER_UNAVAILABLE")end
  local p=config.palette[index];if not p then error("LANDMARK_PALETTE_MISSING_"..key)end
  local m=F.U.Material(original) -- Always a private clone of this new asset's own material.
  local ok,err=pcall(function()
    m.shader=shader;m.name="HalloweenLandmark_Owned_"..key.."_"..p.name
    for _,name in ipairs({"_BaseMap","_MainTex","_BaseTex","_NormalMap","_BumpMap","_ORMMap","_ORMTex","_MetallicGlossMap","_OcclusionMap","_EmissionMap","_EmissionTex","_EmissionMask"})do if m:HasProperty(name)then m:SetTexture(name,nil)end end
    m:DisableKeyword("_USEVERTEXCOLOR_ON");m:DisableKeyword("_USEVERTEXCOLOR1_ON")
    m:DisableKeyword("_SPECULARHIGHLIGHTS_OFF");m:DisableKeyword("_ENVIRONMENTREFLECTIONS_OFF")
    F.float(m,"_UseVertexColor",0);F.float(m,"_UseVertexColor1",0);F.float(m,"_ColorPower",1);F.float(m,"_AOIntensity",1);F.float(m,"_UseTriplanarSample",0)
    if m:HasProperty("_BaseColor")then m:SetColor("_BaseColor",F.color(p.rgba))end
    if m:HasProperty("_Color")then m:SetColor("_Color",F.color(p.rgba))end
    F.float(m,"_Metallic",p.metallic);F.float(m,"_Smoothness",1-p.roughness);F.float(m,"_Glossiness",1-p.roughness);F.float(m,"_Roughness",p.roughness)
    F.float(m,"_SpecularHighlights",1);F.float(m,"_EnvironmentReflections",1)
    F.float(m,"_Surface",0);F.float(m,"_Mode",0);F.float(m,"_Alpha",1);F.float(m,"_Transparent",1);F.float(m,"_Zwrite",1);F.float(m,"_ZWrite",1)
    m:SetOverrideTag("RenderType","Opaque");m.renderQueue=2000
    m:DisableKeyword("_SURFACE_TYPE_TRANSPARENT");m:DisableKeyword("_ALPHABLEND_ON")
    if p.glow then m:EnableKeyword("_EMISSION")else m:DisableKeyword("_EMISSION")end
    F.float(m,"_EmissionPower",p.glow and 1 or 0)
    if m:HasProperty("_EmissionColor")then m:SetColor("_EmissionColor",F.color(p.emission))end
  end)
  if not ok then F.U.Object.Destroy(m);error(err)end
  F.cache[key]=m;F.owned[#F.owned+1]=m;return m
end
function F.patchBlock(block,mat,p)
  for _,name in ipairs({"_BaseColor","_Color"})do if mat:HasProperty(name)then block:SetColor(name,F.color(p.rgba))end end
  if mat:HasProperty("_EmissionColor")then block:SetColor("_EmissionColor",F.color(p.emission))end
  for _,name in ipairs({"_UseVertexColor","_UseVertexColor1","_ColorPower","_Metallic","_Smoothness","_Glossiness","_Roughness","_EmissionPower","_Alpha","_Transparent","_Zwrite","_ZWrite"})do if mat:HasProperty(name)then block:SetFloat(name,mat:GetFloat(name))end end
end
function F.restore(record)
  if not record then return end
  for _,part in ipairs(record.parts or{})do pcall(function()
    if part.renderer then
      part.renderer.sharedMaterials=part.originalMaterials
      part.renderer:SetPropertyBlock(part.originalGlobalBlock)
      for i,block in ipairs(part.originalBlocks)do part.renderer:SetPropertyBlock(block,i-1)end
    end
  end)end
end
function F.plan(root,config)
  local rs=root:GetComponentsInChildren(typeof(F.U.Renderer),true);local by={}
  for i=0,rs.Length-1 do local r=rs[i];local name=tostring(r.gameObject.name);by[name]=by[name]or{};by[name][#by[name]+1]=r end
  local plan={}
  for _,spec in ipairs(config.parts)do
    local candidates=by[spec.name]or{}
    if #candidates~=1 then return nil,"LANDMARK_NODE_MAPPING_"..spec.name.."_"..#candidates end
    local r=candidates[1];local slots=r.sharedMaterials;local filter=r.gameObject:GetComponent(typeof(F.U.MeshFilter))
    if slots.Length~=#spec.mats or not filter or not filter.sharedMesh or filter.sharedMesh.subMeshCount~=#spec.mats then return nil,"LANDMARK_SLOT_MAPPING_"..spec.name end
    plan[#plan+1]={renderer=r,spec=spec}
  end
  if #plan~=rs.Length then return nil,"LANDMARK_UNEXPECTED_RENDERER_"..rs.Length end
  return plan
end
function F.apply(index,root)
  local rootName=F.rootName(index);local config=F.configs[F.rootModels[index]];local plan,reason=F.plan(root,config)
  if not plan then return false,reason end
  local old=F.records[rootName]
  if old then F.restore(old)end
  local record={root=root,index=index,config=config,parts={},glows={}}
  local ok,err=pcall(function()
    for _,candidate in ipairs(plan)do
      local r,spec=candidate.renderer,candidate.spec;local original=r.sharedMaterials
      local part={renderer=r,spec=spec,originalMaterials=original,originalGlobalBlock=F.U.MaterialPropertyBlock(),originalBlocks={},blocks={},applied={}}
      r:GetPropertyBlock(part.originalGlobalBlock)
      for i,materialIndex in ipairs(spec.mats)do
        local saved=F.U.MaterialPropertyBlock();r:GetPropertyBlock(saved,i-1);part.originalBlocks[i]=saved
        local mat=F.makeMaterial(rootName,materialIndex,original[i-1],config);part.applied[i]=mat
        local block=F.U.MaterialPropertyBlock();r:GetPropertyBlock(block,i-1);F.patchBlock(block,mat,config.palette[materialIndex]);part.blocks[i]=block
      end
      record.parts[#record.parts+1]=part
    end
    for _,part in ipairs(record.parts)do
      local r=part.renderer;local slots=r.sharedMaterials
      for i,mat in ipairs(part.applied)do slots[i-1]=mat end;r.sharedMaterials=slots
      for i,block in ipairs(part.blocks)do r:SetPropertyBlock(block,i-1)end
      if string.sub(part.spec.name,1,5)=="Glow_"then
        part.seed=F.hash(part.spec.name);part.period=6+part.seed%5
        record.glows[#record.glows+1]=part
      end
    end
  end)
  if not ok then F.restore(record);return false,tostring(err)end
  F.records[rootName]=record;F.lastErrorByRoot[rootName]=nil;return true,"APPLIED"
end
function F.healthy(record)
  local ok,value=pcall(function()
    for _,part in ipairs(record.parts)do local slots=part.renderer.sharedMaterials
      if slots.Length~=#part.applied then return false end
      for i,m in ipairs(part.applied)do if slots[i-1]~=m then return false end end
    end;return true
  end)
  return ok and value
end
function F.discover()
  for index=1,7 do
    local name=F.rootName(index);local go=F.U.GameObject.Find(name);local old=F.records[name]
    if go and(not old or old.root~=go or not F.healthy(old))then
      local ok,accepted,reason=pcall(F.apply,index,go)
      if not ok then F.error(name,accepted)elseif not accepted then F.error(name,reason)end
    elseif not go and old then F.restore(old);F.records[name]=nil end
  end
end
function F.observer()
  local ok,p=pcall(function()local a=CS.DouyinActorService.GetLocalActor();return a and a.position end)
  if ok and p then return p end
  local camera=F.U.Camera.main;return camera and camera.transform.position or nil
end
function F.animate(record,now)
  for _,part in ipairs(record.glows)do
    local wave=.5+.5*math.sin((now%part.period)/part.period*math.pi*2+part.seed*.017)
    local mix=.14*wave;local bright=.80+.24*wave
    for i,materialIndex in ipairs(part.spec.mats)do
      local p=record.config.palette[materialIndex];local c=p.rgba;local alt=p.alt
      local r=c[1]*(1-mix)+alt[1]*mix;local g=c[2]*(1-mix)+alt[2]*mix;local b=c[3]*(1-mix)+alt[3]*mix
      local block=part.blocks[i];local mat=part.applied[i]
      local base=F.U.Color(r,g,b,1);local emission=F.U.Color(r*p.strength*bright,g*p.strength*bright,b*p.strength*bright,1)
      if mat:HasProperty("_BaseColor")then block:SetColor("_BaseColor",base)end
      if mat:HasProperty("_Color")then block:SetColor("_Color",base)end
      if mat:HasProperty("_EmissionColor")then block:SetColor("_EmissionColor",emission)end
      part.renderer:SetPropertyBlock(block,i-1)
      if F.sample==""then F.sample=string.format("%s:%s:%.4f,%.4f,%.4f;emission=%.4f,%.4f,%.4f",F.rootName(record.index),part.spec.name,r,g,b,emission.r,emission.g,emission.b)end
    end
  end
end
function F.tick(rt)
  if rt>=F.nextDiscoverAt then F.nextDiscoverAt=rt+2;F.discover()end
  local p=F.observer();local now=F.clock(rt);F.sample="";F.updated=0
  if not p then return end
  for _,record in pairs(F.records)do
    if record.root and(record.root.transform.position-p).sqrMagnitude<=F.distance*F.distance then F.animate(record,now);F.updated=F.updated+1 end
  end
end
function GetLandmarkLightingStatus()
  local instances,glows,renderers=0,0,0
  for _,record in pairs(F.records)do instances=instances+1;glows=glows+#record.glows;renderers=renderers+#record.parts end
  -- instances, private material clones, Glow Renderers, current color sample,
  -- error count, latest error, updated-near instances, clock, all Renderers.
  return instances,#F.owned,glows,F.sample,F.errors,F.lastError,F.updated,F.clockSource,renderers
end
function RequestLandmarkLightingRefresh()
  local ok,err=pcall(F.discover);if not ok then F.error("DISCOVERY",err)end
  F.nextAt=0;return GetLandmarkLightingStatus()
end
function Start()local ok,err=pcall(F.discover);if not ok then F.error("START",err)end end
function Update()
  if F.destroyed then return end
  local rt=F.rt();if rt<F.nextAt then return end;F.nextAt=rt+F.interval
  local ok,err=pcall(F.tick,rt);if not ok then F.error("UPDATE",err)end
end
function OnEnable()F.nextAt,F.nextDiscoverAt=0,0 end
function OnDestroy()
  F.destroyed=true
  for _,record in pairs(F.records)do F.restore(record)end
  for _,material in ipairs(F.owned)do pcall(function()F.U.Object.Destroy(material)end)end
  F.records,F.owned,F.cache={},{},{}
end
