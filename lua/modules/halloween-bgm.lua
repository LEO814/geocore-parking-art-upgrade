---@id ab738a0f-14bd-44be-9c34-83557ca44152
---@referenceName halloween-bgm.lua
---@start
---@var bgmEnabled:boolean=true
---@name 万圣节背景音乐开关
---@var bgmVolume:number=0.45
---@name 万圣节背景音乐音量
---@range 0,1,0.01
---@var fadeSeconds:number=0.3
---@name 音乐淡入秒数
---@range 0,2,0.1
---@var sharedStartEpoch:number=1700000000
---@name 公共播放起点（UTC秒）
---@desc 所有客户端使用同一常量，不随比赛或进出大厅重置
---@var syncProgress:boolean=false
---@name 共享播放进度
---@var driftThreshold:number=1.5
---@name 进度纠偏阈值（秒）
---@range 0.5,5,0.1
---@end
-- Saved public object owns configuration; this script creates ONE non-networked
-- local AudioSource per client. No room broadcast, URLs, browser bridge or SFX pool.
local U=CS.UnityEngine
local CHANNELS=1
local RATE,TOTAL,BLOCK=16000,4274330,8192
-- PCM is prepared at build time. Native unpack avoids per-sample Lua decoding.
local DATA={}
local function ensureData()
 if #DATA>0 then return true end
 local pages={};local ss=self.gameObject:GetComponents(typeof(CS.DouyinScript))
 for i=0,ss.Length-1 do local ok,p,rows=pcall(function()local s=ss[i].script;if s and s.GetHalloweenBgmDataPage then return s.GetHalloweenBgmDataPage()end end);if ok and p and rows then pages[p]=rows end end
 local rows={}
 for p=1,8 do if not pages[p]then return false end;for _,encoded in ipairs(pages[p])do rows[#rows+1]=encoded end end
 DATA=rows;return true
end
local EPOCH=CS.System.DateTime(1970,1,1)
local B={status='new',block=1,copied=0,pending={},error='',allowed=false,ready=false,disposed=false,paused=false,commits=0,plays=0,seeks=0,decodeFrames=0,maxDecodeMS=0,maxCopyMS=0,maxCommitMS=0}
local function rt()return U.Time.realtimeSinceStartup end
local function parameter(v,fallback)return tonumber(v)or fallback end
local function seconds()
 local now=rt()
 if now>=(B.nextClock or 0)then
  B.nextClock=now+10
  local ok,t=pcall(function()
   if CS.DouyinNetService.isNetworkSettled then return CS.DouyinUtility.GetServerTime():Subtract(EPOCH).TotalSeconds end
   if U.Application.productName=='DouyinWorldDebugger'then return CS.System.DateTime.UtcNow:Subtract(EPOCH).TotalSeconds end
  end)
  if ok and t and t>1000000000 then B.anchor=t;B.anchorAt=now end
 end
 return B.anchor and B.anchor+math.max(0,now-B.anchorAt)or nil
end
local function phase(t)return(t-parameter(sharedStartEpoch,1700000000))%(TOTAL/CHANNELS/RATE)end
-- The device DSP clock advances independently of Lua/render frames. Unity WebGL
-- exposes AudioSource.time in output-device samples for a 16 kHz clip; do not
-- integrate that wrapping counter as music seconds (48 kHz makes it wrap 3x).
local function dsp()return U.AudioSettings.dspTime end
local function playbackTime()
 if not B.source then return 0 end
 local now=dsp()
 if B.started and B.source.isPlaying then
  local elapsed=math.max(0,now-(B.dspAt or now))
  B.clock=((B.clock or 0)+elapsed)%(TOTAL/CHANNELS/RATE)
 end
 B.dspAt=now
 return B.clock or 0
end
local function seek(value)
 B.source.time=value;B.clock=value;B.dspAt=dsp();B.lastRaw=B.source.time;B.lastRawAt=rt()
end
local function resumeFromCursor(reason)
 -- Recover at the retained position, never replay the opening note. A cooldown
 -- prevents a suspended/blocked device from becoming a repeating Play() loop.
 local now=rt()
 if now<(B.nextRecovery or 0)then return false end
 B.nextRecovery=now+10;B.recoveries=(B.recoveries or 0)+1;B.recoveryReason=reason
 local cursor=playbackTime()
 B.source:Stop();seek(cursor);B.source:Play();B.plays=B.plays+1
 B.started=true;B.resumePending=false;B.fadeAt=now;B.dspAt=dsp()
 B.lastRaw=B.source.time;B.lastRawAt=now
 return true
end
local function watchPlayback()
 -- AudioSource.time is not a reliable liveness signal in the WebGL player.
 -- A busy render frame must never restart otherwise healthy native playback.
 local now=rt();if now<(B.nextWatch or 0)then return end;B.nextWatch=now+.5
 local raw=B.source.time
 if math.abs(raw-(B.lastRaw or raw))>.005 then B.lastRaw=raw;B.lastRawAt=now end
end

local function stop()
 if B.source then playbackTime();B.source.mute=true;B.source.volume=0;if B.source.isPlaying then B.source:Pause();B.resumePending=true end end
 B.playing=false;B.started=false
end
local function context()return true,'whole-scene' end
local function decode(count)
 if not B.raw then
  B.raw=CS.System.Convert.FromBase64String(DATA[B.block]);B.block=B.block+1;B.rawAt=1
 end
 assert(#B.raw-B.rawAt+1>=count*2,'BGM PCM block length')
 B.formats=B.formats or{};local fmt=B.formats[count]
 if not fmt then fmt='<'..string.rep('i2',count);B.formats[count]=fmt end
 B.pending={string.unpack(fmt,B.raw,B.rawAt)};B.pending[count+1]=nil
 B.rawAt=B.rawAt+count*2
 if B.rawAt>#B.raw then B.raw=nil end
 for i=1,count do B.pending[i]=B.pending[i]*(1/32768)end
end

local function loadStep()
 if B.ready or not B.allowed or B.paused or rt()<B.loadAfter then return end
 if not ensureData()then B.status='waiting-data';return end
 if not B.firstEligibleAt then B.firstEligibleAt=rt()end
 if not B.samples then B.samples=CS.System.Array.CreateInstance(typeof(CS.System.Single),TOTAL)end
 local at=rt();local count=math.min(BLOCK,TOTAL-B.copied)
 decode(count);B.decodeFrames=B.decodeFrames+1
 B.maxDecodeMS=math.max(B.maxDecodeMS,(rt()-at)*1000)
 at=rt()
 -- Reuse one temporary clip/buffer. The final clip is committed exactly once.
 if not B.scratch or B.scratch.Length~=count then
  if B.scratchClip then U.Object.Destroy(B.scratchClip)end
  B.scratchClip=U.AudioClip.Create('HalloweenBGMScratch',count,1,RATE,false)
  B.scratch=CS.System.Array.CreateInstance(typeof(CS.System.Single),count)
 end
 assert(B.scratchClip:SetData(B.pending,0)~=false,'BGM scratch SetData')
 assert(B.scratchClip:GetData(B.scratch,0)~=false,'BGM scratch GetData')
 CS.System.Array.Copy(B.scratch,0,B.samples,B.copied,count)
 B.copied=B.copied+count;B.pending={}
 B.maxCopyMS=math.max(B.maxCopyMS,(rt()-at)*1000)
 if B.copied==TOTAL then
  at=rt();B.clip=U.AudioClip.Create('SickEnoughToDie_FullLoop',TOTAL/CHANNELS,CHANNELS,RATE,false)
  assert(B.clip:SetData(B.samples,0)~=false,'BGM full SetData');B.commits=B.commits+1
  B.maxCommitMS=math.max(B.maxCommitMS,(rt()-at)*1000)
  B.source.clip=B.clip;B.samples=nil;B.scratch=nil;B.ready=true;B.status='ready'
  U.Object.Destroy(B.scratchClip);B.scratchClip=nil;B.formats=nil
  B.loadedSeconds=rt()-B.firstEligibleAt;B.playAfter=rt()+.5
 end
end
local function update()
 local allowed,reason=context();B.allowed=allowed==true and bgmEnabled~=false and not B.paused and not B.disabled and not B.ceremony;B.reason=reason
 if not B.allowed then stop();B.status=B.ready and'paused'or'loading-paused';return end
 if not B.ready then
  B.status='loading'
  -- Batch within a short real-time budget, not exactly one block per frame.
  local untilAt=rt()+.004
  for i=1,2 do loadStep();if B.ready or not B.samples or rt()>=untilAt then break end end
  if not B.ready then return end
 end
 if rt()<(B.playAfter or 0)then B.status='buffer-ready';return end
 local voices=U.GameObject.Find('Halloween_NPC_ProcessedVoice');local voice=voices and voices:GetComponent(typeof(U.AudioSource));B.duckGain=voice and voice.isPlaying and .30 or 1
 local time=syncProgress==true and seconds()or nil;if syncProgress==true and not time then stop();B.status='waiting-server-clock';return end
 if not B.started then
  -- Re-check completed loading on this frame before starting any sound.
  local inside=context();if not inside then stop();return end
  B.source.mute=false;B.source.volume=0
  if syncProgress==true then seek(phase(time));B.seeks=B.seeks+1 end
  if B.resumePending then B.source:UnPause();B.resumePending=false else B.source:Play();B.plays=B.plays+1 end;B.dspAt=dsp();B.lastRaw=B.source.time;B.lastRawAt=rt();B.started=true;B.fadeAt=rt();B.firstAudioSeconds=B.firstAudioSeconds or(rt()-B.initAt);B.nextDrift=rt()+10
 end
 B.source.volume=math.max(0,math.min(1,parameter(bgmVolume,.45)))*(B.duckGain or 1)*math.min(1,(rt()-B.fadeAt)/math.max(.01,parameter(fadeSeconds,.3)))
 local previous=B.clock or 0;B.playing=B.source.isPlaying;local cursor=playbackTime();if cursor<previous and B.playing then B.loopCount=(B.loopCount or 0)+1 end;B.status=B.playing and'playing'or'awaiting-audio-device'
 local touched=U.Input.touchCount>0
 local gesture=U.Input.anyKeyDown or U.Input.GetMouseButtonDown(0)or(touched and not B.touchWasDown)
 B.touchWasDown=touched
 if not B.playing and gesture then resumeFromCursor('user-resume')end
 watchPlayback()
 if B.playing and syncProgress==true and time and rt()>=B.nextDrift then
  B.nextDrift=rt()+10;local wanted=phase(time);local length=TOTAL/CHANNELS/RATE;local d=math.abs(playbackTime()-wanted);d=math.min(d,length-d)
  B.drift=d
  if d>math.max(.5,parameter(driftThreshold,1.5))then seek(wanted);B.seeks=B.seeks+1 end
 end
end
function Start()
 local ok,err=pcall(function()
  if U.GameObject.Find('Geocore_Halloween_LocalBGM')then B.disposed=true;B.status='duplicate-disabled';return end
  B.root=U.GameObject('Geocore_Halloween_LocalBGM');B.root.transform:SetParent(self.gameObject.transform,false)
  B.source=B.root:AddComponent(typeof(U.AudioSource));B.source.playOnAwake=false;B.source.loop=true;B.source.spatialBlend=0;B.source.dopplerLevel=0;B.source.pitch=1;B.source.volume=0;B.source.mute=true
  B.source.ignoreListenerPause=false;B.source.ignoreListenerVolume=false
  B.clock=0;B.dspAt=dsp();B.recoveries=0
  B.initAt=rt();B.loadAfter=B.initAt+2;B.status='waiting-music'
 end)
 if not ok then B.error=tostring(err);B.status='error';stop()end
end
function Update()
 if B.disposed or B.error~=''then return end
 local at=rt();local ok,err=pcall(update);B.maxUpdateMS=math.max(B.maxUpdateMS or 0,(rt()-at)*1000);if not ok then B.error=tostring(err);B.status='error';stop();U.Debug.LogError('HalloweenBGM '..B.error)end
end
function GetPlaybackState()return B.playing==true,playbackTime(),B.status,B.error end
function GetStatus()
 return 'version=PACED_PCM_V3;status='..B.status..';allowed='..tostring(B.allowed)..';ready='..tostring(B.ready)..';playing='..tostring(B.source and B.source.isPlaying)..';time='..playbackTime()..';rawTime='..(B.source and B.source.time or 0)..';samples='..B.copied..'/'..TOTAL..';duration='..(TOTAL/CHANNELS/RATE)..';pitch='..(B.source and B.source.pitch or 0)..';loop='..tostring(B.source and B.source.loop)..';loopCount='..tostring(B.loopCount or 0)..';volume='..(B.source and B.source.volume or 0)..';commits='..B.commits..';plays='..B.plays..';seeks='..B.seeks..';drift='..(B.drift or 0)..';recoveries='..(B.recoveries or 0)..';recoveryReason='..(B.recoveryReason or 'none')..';decodeMaxMS='..B.maxDecodeMS..';copyMaxMS='..B.maxCopyMS..';commitMaxMS='..B.maxCommitMS..';loadSeconds='..(B.loadedSeconds or 0)..';firstAudioSeconds='..(B.firstAudioSeconds or 0)..';updateMaxMS='..(B.maxUpdateMS or 0)..';loadFrames='..B.decodeFrames..';error='..B.error
end
function OnApplicationPause(paused)B.paused=paused;if paused then stop()else B.nextClock=0;B.nextWatch=rt()+3;B.dspAt=dsp();B.lastRawAt=rt()end end
function OnApplicationFocus(focused)if focused then B.nextWatch=rt()+3;B.lastRawAt=rt()end end
function OnDisable()B.disabled=true;stop()end
function OnEnable()B.disabled=false end
local function dispose()
 if B.disposed then return end;B.disposed=true;stop()
 if B.source then B.source.clip=nil end
 if B.clip then U.Object.Destroy(B.clip)end
 if B.scratchClip then U.Object.Destroy(B.scratchClip)end
 if B.root then U.Object.Destroy(B.root)end
 B.samples=nil;B.scratch=nil;B.raw=nil;B.pending={};DATA={};B.formats=nil;B.ready=false
end
function OnDestroy()dispose()end

-- Race countdown ducking keeps the current music position.
function SetDucking(value)B.duckGain=math.max(0,math.min(1,tonumber(value)or 1))end

-- Exclusive ceremony audio suspends this loop at the retained DSP cursor.
function SetCeremonyActive(active)
 B.ceremony=active==true
 if B.ceremony then stop();B.status="ceremony-paused"else B.nextWatch=rt()+3;B.dspAt=dsp()end
end
