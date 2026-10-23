---@id f29c6267-f364-4c9d-aba5-73c7209f0587
---@referenceName halloween-npc-interaction.lua
---@assetRef eyJhc3NldElkIjoiMTEwMTQ5MzI1MTMwMjYiLCJhc3NldFVyaSI6ImhhbWxldC11Z2MvYWlnY19lZGl0b3IvZGV2L3VuaXR5L01TNHdMakFCQUFBQXlJUURXSHI1UTBOak82N29HWDZEZllpY1dwLTBJYmpvRUNjSUZFcmk3ZWcvTlBDMDEtJUU1JThEJTk3JUU3JTkzJTlDJUU1JUIwJThGJUU0JUJFJUFGJUU3JTg4JUI1X191cGxvYWRfc2ZrOHB4ZDkuZ2xiIiwicmVmZXJlbmNlTmFtZSI6ImhhbGxvd2Vlbi1ucGMtaW50ZXJhY3Rpb24ubHVhIn0
---@start
---@var npcPresetId:number=1
---@name 万圣NPC编号
---@range 1,5,1
---@end
-- Use the same engine-owned button prefab and styling as vehicle interactions.
local N={names={'南瓜小侯爵','薄荷小幽灵','冰霜女巫','幽灵船长','糖纸木乃伊'},button=nil,enabled=false,nextAt=0,lastClickAt=-100,clicks=0,lastResult='READY'}
function N.localActor()return CS.DouyinActorService.GetLocalActor()end
function N.near(actor)
 return actor~=nil and actor.isLocal and not actor:IsSitting()and(actor.position-self.gameObject.transform.position).magnitude<=3.6
end
function N.api(holder)
 local ok,script=pcall(function()return holder and holder.script end)
 return ok and script and script.HalloweenRequestTransform and script or nil
end
function N.resolve()
 local cached=N.api(N.service);if cached then return cached end;N.service=nil
 local go=CS.UnityEngine.GameObject.Find('HalloweenAvatarService');if not go then return nil end
 -- Component lookup avoids depending on platform-specific filename/UUID aliases.
 local holders=go:GetComponents(typeof(CS.DouyinScript))
 for i=0,holders.Length-1 do local script=N.api(holders[i]);if script then N.service=holders[i];return script end end
 for _,key in ipairs({'halloween-avatar-service.lua','86b0e87c-65c5-400c-84f6-ae2a1a33e798'})do
  local ok,holder=pcall(function()return go:GetDouyinScript(key)end)
  if ok then local script=N.api(holder);if script then N.service=holder;return script end end
 end
 return nil
end
function N.label()
 if not N.button then return end
 local text=N.button:GetComponentInChildren(typeof(CS.UnityEngine.UI.Text))
 if text then text.text=CS.UnityEngine.Time.realtimeSinceStartup<(N.feedbackUntil or 0)and'请稍后再试'or('对话 · '..(N.names[math.floor(tonumber(npcPresetId)or 1)]or'万圣访客'))end
end
function N.result(ok,reason,path)
 N.lastResult=tostring(reason or(ok and'ACCEPTED'or'REJECTED'))
 CS.UnityEngine.Debug.Log('HalloweenNPCButton path='..tostring(path)..' preset='..tostring(npcPresetId)..' result='..N.lastResult..' platform='..tostring(CS.UnityEngine.Application.platform))
 if not ok then N.feedbackUntil=CS.UnityEngine.Time.realtimeSinceStartup+1.5;N.label()end
 return ok,N.lastResult
end
function N.request(actor,path)
 local now=CS.UnityEngine.Time.realtimeSinceStartup
 if now-N.lastClickAt<.75 then return false,'COOLDOWN'end
 N.lastClickAt=now;N.clicks=N.clicks+1
 if not N.near(actor)then return N.result(false,'OUT_OF_RANGE_OR_SEATED',path)end
 local script=N.resolve();if not script then return N.result(false,'SERVICE_UNAVAILABLE',path)end
 local id=math.floor(tonumber(npcPresetId)or 1);if not N.names[id]then return N.result(false,'INVALID_PRESET',path)end
 local safe,ok,reason=pcall(script.HalloweenRequestTransform,id)
 if not safe then N.service=nil;return N.result(false,'REQUEST_EXCEPTION',path)end
 return N.result(ok,reason,path)
end
function N.removeButton()
 if N.uiButton and N.uiHandler then pcall(function()N.uiButton.onClick:RemoveListener(N.uiHandler)end)end
 N.uiButton,N.uiHandler=nil,nil
 if N.button then pcall(function()self:RemoveInteractorButton(N.button)end);N.button=nil end
end
function N.refresh()
 local nearby=N.near(N.localActor())
 if nearby~=N.enabled then N.enabled=nearby;if nearby then self:EnableInteraction()else self:DisableInteraction();N.removeButton()end end
 N.label()
end
function Start()
 local U=CS.UnityEngine;local c=self.gameObject:GetComponent(typeof(U.BoxCollider));if not c then c=self.gameObject:AddComponent(typeof(U.BoxCollider));N.ownedTrigger=c end
 local sc=math.max(.01,self.gameObject.transform.lossyScale.x);c.isTrigger=true;c.size=U.Vector3(2.4/sc,1.7/sc,2.4/sc);c.center=U.Vector3(0,.6/sc,0);N.refresh()
end
function Update()local rt=CS.UnityEngine.Time.realtimeSinceStartup;if rt>=N.nextAt then N.nextAt=rt+.2;N.refresh()end end
function OnActorTriggerEnter(actor)if actor and actor.isLocal then N.refresh()end end
function OnActorTriggerExit(actor)if actor and actor.isLocal then N.refresh()end end
function OnFocus(handType)
 if not N.near(N.localActor())or N.button then return end
 N.button=self:AddInteractorButton();N.label()
 -- Keep the system prefab; bridge its existing touch-click event as well.
 local ok,button=pcall(function()return N.button:GetComponentInChildren(typeof(CS.UnityEngine.UI.Button),true)end)
 if ok and button then N.uiButton=button;N.uiHandler=function()N.request(N.localActor(),'UI_CLICK')end;button.onClick:AddListener(N.uiHandler)end
end
function OnLostFocus(handType)N.removeButton()end
function OnInteractorButtonClick(index)return N.request(N.localActor(),'SYSTEM_BUTTON')end
function OnInteract(actor)return N.request(actor,'ACTOR_INTERACT')end
function HalloweenNPCRequestDialogue()return N.request(N.localActor(),'SYSTEM_BUTTON')end
function HalloweenNPCGetInteractionStatus()return 'version=SYSTEM_UI_V3|clicks='..N.clicks..'|result='..N.lastResult..'|near='..tostring(N.near(N.localActor()))..'|uiBridge='..tostring(N.uiButton~=nil)..'|service='..tostring(N.resolve()~=nil)end
function OnDisable()N.removeButton();pcall(function()self:DisableInteraction()end);N.enabled=false end
function OnDestroy()OnDisable()end
