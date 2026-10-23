---@id 650f9bb2-f983-4c39-9b98-456d89b19dd2
-- Authoritative race clock, gate/display controller, and fleet reset dispatcher.

---@start
---@var preparingSeconds:number=60
---@name 比赛准备时长
---@desc B门关闭的比赛准备阶段时长（秒）
---@range 5,600,1
---@group 比赛循环
---@var waitingSeconds:number=25
---@name 等待发车时长
---@desc B门关闭的等待发车阶段时长（秒）
---@range 1,600,1
---@group 比赛循环
---@var racingSeconds:number=150
---@name 比赛进行时长
---@desc B门开启的正式比赛阶段时长（秒）
---@range 1,600,1
---@group 比赛循环
---@var recyclingSeconds:number=20
---@name 车辆回收时长
---@desc B门关闭、循环结束时统一回收全部赛车的阶段时长（秒）
---@range 1,600,1
---@group 比赛循环
---@var scheduleRevision:number=3
---@name 赛程版本号
---@desc 修改任一阶段时长并发布时请加1；用于保证跨版本cycleId始终单调递增
---@range 1,20,1
---@group 比赛循环
---@var countdownVoiceVolume:number=0.6
---@name 开赛倒计时语音音量
---@desc 全场2D语音倒计时音量；建议背景BGM音量设置为50至55以形成明显层级
---@range 0.1,1,0.05
---@group 比赛音频
---@var returnAllPlayersOnRaceEnd:boolean=true
---@name 赛后全员回角色出生点
---@desc 每局结束将房间内各客户端的本地角色送回当前角色出生点；关闭只影响角色，车辆仍每局回收。开关按比赛周期生效。
---@group 比赛循环
---@varSync raceClockSnapshot:string
---@varSync raceResultLedger:string
---@varSync raceFinalResultsSnapshot:string
---@varSync raceWithdrawalsSnapshot:string
---@end

local UnityEngine = CS.UnityEngine
local Time = UnityEngine.Time
local Vector3 = UnityEngine.Vector3
local Quaternion = UnityEngine.Quaternion
local Color = UnityEngine.Color

local function normalizedPhaseSeconds(value, fallback)
  local parsed = tonumber(value)
  if parsed == nil then parsed = fallback end
  return math.max(1, math.min(600, parsed))
end

-- Selection remains interactive throughout PREPARING. Fleet recycling belongs
-- to RECYCLING, and each vehicle owner acknowledges the same race-cycle token.
local PREPARING_SECONDS = math.max(5, normalizedPhaseSeconds(preparingSeconds, 60))
local WAITING_SECONDS = normalizedPhaseSeconds(waitingSeconds, 25)
local RACING_SECONDS = normalizedPhaseSeconds(racingSeconds, 150)
local RECYCLING_SECONDS = normalizedPhaseSeconds(recyclingSeconds, 20)
local CYCLE_SECONDS = PREPARING_SECONDS + WAITING_SECONDS + RACING_SECONDS + RECYCLING_SECONDS
local CYCLE_MILLISECONDS = CYCLE_SECONDS * 1000
-- Fixed natural-time schedule anchor: 2026-01-01 00:00:00 UTC+8
-- (2025-12-31 16:00:00 UTC). The schedule never resets at later midnights.
local SCHEDULE_EPOCH_UNIX_MILLISECONDS = 1767196800000
local SCHEDULE_REVISION = math.max(1, math.min(20, math.floor(tonumber(scheduleRevision) or 1)))
-- Keeps reset/message tokens below signed Int32 while leaving 100,000,000 cycle
-- ordinals per published schedule revision.
local SCHEDULE_TOKEN_STRIDE = 100000000
local SERVER_CLOCK_RESAMPLE_SECONDS = 1.0
local roomClock = {
  configSignature = table.concat({
    tostring(SCHEDULE_REVISION),
    tostring(PREPARING_SECONDS),
    tostring(WAITING_SECONDS),
    tostring(RACING_SECONDS),
    tostring(RECYCLING_SECONDS),
  }, ":"),
  bootstrapTimeoutSeconds = 3.0,
  publishIntervalSeconds = 0.5,
  followerMaxInterpolationSeconds = 1.5,
  snapshotVersion = "RC1",
  mode = nil,
  generation = 0,
  sequence = 0,
  snapshotValue = nil,
  snapshotPayload = "",
  snapshotReceivedRealtime = nil,
  snapshotChangeHandle = nil,
  wasOwner = nil,
  bootstrapStartedRealtime = nil,
  nextPublishRealtime = -math.huge,
  lastPublishedCycleId = 0,
  lastPublishedState = nil,
  lastPublishedLogicalMilliseconds = nil,
  subsystemErrors = {},
}
local COUNTDOWN_AUDIO_BANK_SCRIPT_ID = "18b058a0-2a9d-4d87-a6c7-dc87e89760df"
local COUNTDOWN_AUDIO_BANK_SCRIPT_NAME = "race-countdown-audio-bank.lua"
local COUNTDOWN_AUDIO_LEAD_MILLISECONDS = 5000
-- A badly delayed frame never emits a stale digit or a catch-up burst. The
-- next exact server-time boundary resumes the countdown normally.
local COUNTDOWN_AUDIO_MAX_TRIGGER_LATENESS_MILLISECONDS = 350
local COUNTDOWN_AUDIO_VOLUME = math.max(0.1, math.min(1, tonumber(countdownVoiceVolume) or 0.6))

local fleet = {
  { rootName = "玩具", displayName = "玩具", scriptId = "8de0f771-fd69-4eaf-9b49-0fe93a76cba0", scriptName = "pi-lp03-toybox.lua" },
  { rootName = "莓爆花", displayName = "莓爆花", scriptId = "0a670ab9-e842-4180-83ac-1ff209bfa4ec", scriptName = "pi-lp39-berry-pop.lua" },
  { rootName = "绯樱", displayName = "绯樱", scriptId = "08e30626-c7ac-442b-a52e-79eeb4821174", scriptName = "pi-lp05b-feiying.lua" },
  { rootName = "暴走", displayName = "暴走", scriptId = "4fd26fee-695e-49b9-9e3a-c4c63e32953d", scriptName = "pi-lp05b.lua" },
  { rootName = "烈焰", displayName = "烈焰", scriptId = "a617d090-9f38-484d-aae2-38cd1bc67d71", scriptName = "pi-flame-kart.lua" },
  { rootName = "赤巡", displayName = "赤巡", scriptId = "ce1504dd-0a40-4a70-87e3-c8175dc6e9f2", scriptName = "pi-flame-motorcycle.lua" },
  { rootName = "薄荷糖", displayName = "薄荷糖", scriptId = "172fb58a-5b48-478e-9c7a-2982f1094fa4", scriptName = "pi-lp14-mint-candy.lua" },
  { rootName = "甜品", displayName = "甜品", scriptId = "8bd801fb-77a6-40e3-b3f0-213805638473", scriptName = "pi-lp14.lua" },
  { rootName = "牛牛", displayName = "牛牛", scriptId = "d9c87464-c30a-41a9-9985-49d42295c57c", scriptName = "pi-nl01-niulai.lua" },
  { rootName = "牛粉", displayName = "牛粉", scriptId = "0c552cb3-a257-49e9-9695-3f069a85e602", scriptName = "pi-nl01-niufen.lua" },
  { rootName = "积木", displayName = "积木", scriptId = "8db8ed26-ff1d-45c6-9f00-2ffd3c72a094", scriptName = "pi-lp26.lua" },
  { rootName = "宝宝巴", displayName = "宝宝巴", scriptId = "479379fa-99ea-4279-b543-57336e6305db", scriptName = "pi-lp37-buskid-sunny.lua" },
  { rootName = "星梦巴", displayName = "星梦巴", scriptId = "40b08af1-fa7d-4952-b7e1-1eab05150ca6", scriptName = "pi-lp37-star-dream.lua" },
  { rootName = "爆米花", displayName = "爆米花", scriptId = "0b177841-8cba-4955-ba76-6f773828be1c", scriptName = "pi-lp39-racerpop.lua" },
  { rootName = "暮翼巡游", displayName = "暮翼巡游", scriptId = "pi-c01-duskwing-parade.lua", scriptName = "pi-c01-duskwing-parade.lua" },
  { rootName = "甜咒南瓜", displayName = "甜咒南瓜", scriptId = "pi-c02-candy-hex.lua", scriptName = "pi-c02-candy-hex.lua" },
}

-- New imported cars can expose either embedded filename or catalog UUID.
-- Restrict compatibility resolution to the two added vehicles; all fourteen
-- legacy entries continue through their existing lookup branch unchanged.
function roomClock.resolveAddedFleetRuntime(gameObject, entry)
  if gameObject == nil then return nil end
  local c01, c02 = entry.rootName == "暮翼巡游", entry.rootName == "甜咒南瓜"
  if not c01 and not c02 then return nil end
  roomClock.addedFleetRuntimeHolders = roomClock.addedFleetRuntimeHolders or {}
  local function ready(holder)
    local ok, value = pcall(function()
      local api = holder ~= nil and holder.script or nil
      return api ~= nil and api.RaceManagerReset ~= nil
        and api.RaceSessionGetRoster ~= nil and api.RaceSessionGetSeatRoster ~= nil
        and api.RaceSessionRequestStage ~= nil and api.HasCompletedRaceSessionStage ~= nil
    end)
    return ok and value == true
  end
  local cached = roomClock.addedFleetRuntimeHolders[entry.rootName]
  if cached ~= nil and cached.gameObject == gameObject and ready(cached.holder) then return cached.holder end
  local filename = c01 and "pi-c01-duskwing-parade.lua" or "pi-c02-candy-hex.lua"
  local actualId = c01 and "9ce147c6-0d29-4356-be45-ac57634415af" or "1a1f1fbf-d1d3-4999-81c5-3aa3ed3269b0"
  for _, candidate in ipairs({entry.scriptId, filename, actualId}) do
    local ok, holder = pcall(function() return gameObject:GetDouyinScript(candidate) end)
    if ok and ready(holder) then roomClock.addedFleetRuntimeHolders[entry.rootName] = {gameObject=gameObject, holder=holder}; return holder end
  end
  local ok, components = pcall(function() return gameObject:GetComponents(typeof(CS.DouyinScript)) end)
  if ok and components ~= nil then
    for index = 0, components.Length - 1 do
      local holder = components[index]
      if ready(holder) then roomClock.addedFleetRuntimeHolders[entry.rootName] = {gameObject=gameObject, holder=holder}; return holder end
    end
  end
  roomClock.addedFleetRuntimeHolders[entry.rootName] = nil
  return nil
end

-- Old published rooms and cached snapshots may still carry the former English
-- display identifiers. Normalize them before rendering so every client uses
-- the same Chinese leaderboard label. Keep this on the existing singleton so
-- the restored online chunk remains at 199 top-level locals.
-- GE0CORE_RACE_SESSION_V11
roomClock.raceSessionScriptId = "3cb5f0e7-b1a4-4aa0-8d32-905a47bd2f26"
function roomClock.getRaceSession()
  local ok, holder = pcall(function() return self.gameObject:GetDouyinScript(roomClock.raceSessionScriptId) end)
  return ok and holder ~= nil and holder.script ~= nil and holder or nil
end
function roomClock.raceRosterLabel(vehicleName)
  local holder = roomClock.getRaceSession()
  if holder ~= nil and holder.script.GetRaceVehicleRosterLabel ~= nil then
    local ok, value = pcall(function() return holder.script.GetRaceVehicleRosterLabel(vehicleName) end)
    if ok and tostring(value or "") ~= "" then return tostring(value) end
  end
  return tostring(vehicleName or "")
end
function roomClock.raceVehicleParticipating(vehicleName)
  local holder = roomClock.getRaceSession()
  if holder == nil or holder.script.GetRaceVehicleSessionState == nil
    or holder.script.GetRaceVehicleRosterActorIds == nil then return false end
  local currentCycle = GetRaceManagerCycleId()
  local ok, rosterCycle, driver = pcall(function() return holder.script.GetRaceVehicleSessionState(vehicleName) end)
  if not ok or tonumber(rosterCycle) ~= currentCycle or (tonumber(driver) or 0) <= 0 then return false end
  local idsOk, ids = pcall(function() return holder.script.GetRaceVehicleRosterActorIds(vehicleName) end)
  if not idsOk or tostring(ids or "") == "" then return false end
  local entry = roomClock.fleetByRootName[tostring(vehicleName or "")]
  if entry == nil then return false end
  local cached = roomClock.getFleetCacheEntry(entry, true)
  if cached == nil then return false end
  local stagedOk, staged = pcall(function()
    local vehicle = nil
    if entry.rootName == "暮翼巡游" or entry.rootName == "甜咒南瓜" then
      vehicle = roomClock.resolveAddedFleetRuntime(cached.gameObject, entry)
    else
      vehicle = cached.scriptHolder or cached.gameObject:GetDouyinScript(entry.scriptId)
    end
    return vehicle ~= nil and vehicle.script ~= nil and vehicle.script.HasCompletedRaceSessionStage ~= nil
      and vehicle.script.HasCompletedRaceSessionStage(currentCycle) == true
  end)
  return stagedOk and staged == true
end

function GetRaceManagerVehicleParticipating(vehicleName)
  return roomClock.raceVehicleParticipating(tostring(vehicleName or ""))
end
function roomClock.getRouteValidator()
  if roomClock.routeValidatorHolder ~= nil and roomClock.routeValidatorHolder.script ~= nil then
    return roomClock.routeValidatorHolder
  end
  local ok, holder = pcall(function()
    return self.gameObject:GetDouyinScript("4fd23b49-42c5-4e32-9c41-7f364db2a421")
  end)
  if ok and holder ~= nil and holder.script ~= nil then roomClock.routeValidatorHolder = holder; return holder end
  return nil
end

roomClock.leaderboardVehicleNameAliases = {
  TOYBOX = "玩具",
  BERRYPOP = "莓爆花",
  FEIYING = "绯樱",
  BOSOZOKU = "暴走",
  HOTROD = "烈焰",
  ZIYAN = "赤巡",
  MINT = "薄荷糖",
  DESSERT = "甜品",
  NIUNIU = "牛牛",
  NIUFEN = "牛粉",
  BRICK = "积木",
  BABYBUS = "宝宝巴",
  STARBUS = "星梦巴",
  STARBURST = "星梦巴",
  POPCORN = "爆米花",
}

-- RACE_FLEET_CACHE_V2: re-resolve inactive network vehicle roots, matching Moon.
-- RACE_MANAGER_LOCAL_BUDGET_V1
-- One generic cache serves finish tracking and reset dispatch. Adding a future
-- model requires only one metadata row in fleet above; no cache code changes.
-- Missing roots remain retryable, and a replaced runtime object can explicitly
-- invalidate its entry through RaceManagerInvalidateVehicleCache.
roomClock.fleetByRootName = {}
for i = 1, #fleet do roomClock.fleetByRootName[fleet[i].rootName] = fleet[i] end
roomClock.fleetCache = {}
roomClock.fleetCacheHits = 0
roomClock.fleetCacheMisses = 0
roomClock.fleetCacheFindCalls = 0
roomClock.fleetCacheNextMaintenanceAt = 0
roomClock.fleetCacheRetrySeconds = 1.0

roomClock.getFleetCacheEntry = function(entry, allowRetry)
  if entry == nil then return nil, "fleet metadata missing" end
  local rootName = tostring(entry.rootName or "")
  if rootName == "" then return nil, "root name missing" end
  local cached = roomClock.fleetCache[rootName]
  if cached ~= nil and cached.gameObject ~= nil and cached.gameObject.activeInHierarchy and cached.transform ~= nil then
    roomClock.fleetCacheHits = roomClock.fleetCacheHits + 1
    return cached, nil
  end
  if cached ~= nil and cached.missing == true then
    if allowRetry ~= true or Time.time < (tonumber(cached.nextRetryAt) or math.huge) then
      return nil, "root missing (negative cache)"
    end
  elseif allowRetry ~= true then
    return nil, "root not cached"
  end
  roomClock.fleetCacheMisses = roomClock.fleetCacheMisses + 1
  roomClock.fleetCacheFindCalls = roomClock.fleetCacheFindCalls + 1
  local vehicle = UnityEngine.GameObject.Find(rootName)
  if vehicle == nil then
    roomClock.fleetCache[rootName] = {
      missing = true,
      nextRetryAt = Time.time + roomClock.fleetCacheRetrySeconds,
    }
    return nil, "root missing"
  end
  cached = {
    gameObject = vehicle,
    transform = vehicle.transform,
    scriptHolder = nil,
  }
  roomClock.fleetCache[rootName] = cached
  return cached, nil
end

roomClock.getFinishVehicleTransform = function(rootName)
  -- This is the per-frame path: a plain table read after warm-up, with no
  -- GameObject.Find, pcall, component lookup, or diagnostic counter mutation.
  local cached = roomClock.fleetCache[rootName]
  if cached ~= nil and cached.gameObject ~= nil and cached.gameObject.activeInHierarchy and cached.transform ~= nil then return cached.transform end
  return nil
end

roomClock.maintainFleetCache = function()
  if Time.time < (tonumber(roomClock.fleetCacheNextMaintenanceAt) or 0) then return end
  roomClock.fleetCacheNextMaintenanceAt = Time.time + roomClock.fleetCacheRetrySeconds
  for i = 1, #fleet do
    local entry = fleet[i]
    local cached = roomClock.fleetCache[entry.rootName]
    if cached == nil or cached.missing == true or cached.gameObject == nil or not cached.gameObject.activeInHierarchy then
      roomClock.getFleetCacheEntry(entry, true)
    end
  end
end

function RaceManagerInvalidateVehicleCache(rootName)
  local normalized = tostring(rootName or "")
  if normalized == "" then
    roomClock.fleetCache = {}
    roomClock.fleetCacheNextMaintenanceAt = 0
    return true
  end
  if roomClock.fleetByRootName[normalized] == nil then return false end
  roomClock.fleetCache[normalized] = nil
  roomClock.fleetCacheNextMaintenanceAt = 0
  return true
end

function GetRaceFleetCacheDiagnostics()
  local resolved = 0
  for _, cached in pairs(roomClock.fleetCache) do
    if cached ~= nil and cached.gameObject ~= nil then resolved = resolved + 1 end
  end
  return #fleet, resolved, roomClock.fleetCacheHits,
    roomClock.fleetCacheMisses, roomClock.fleetCacheFindCalls
end

-- Every client derives the same race phase from the server UTC clock and the
-- fixed Beijing-midnight epoch above. Local loading time never starts a race.
local raceCycleId = 0
local raceState = nil
local raceLastDisplayedSecond = -1
local raceClockInitialized = false
local raceInitializedCycleId = 0
local raceFinalizedCycleId = 0
local raceClockNowUnixMilliseconds = nil
local raceCycleElapsedMilliseconds = -1
local raceCycleStartUnixMilliseconds = nil
local raceScheduledStartUnixMilliseconds = nil
local raceTimingCycleId = 0
local raceLastCrossingSampleUnixMilliseconds = nil
local raceFinishTrackerNeedsReseed = true
local serverClockAnchorUnixMilliseconds = nil
local serverClockAnchorRealtime = nil
local serverClockLastReturnedUnixMilliseconds = nil
local serverClockNextSampleRealtime = -math.huge
local serverClockLastSuccessRealtime = nil
local serverClockInvalid = false
local serverClockLastError = "waiting for network"
local serverClockSource = "WAITING_NETWORK"
local raceDisplayRoot = nil
local raceCountdownText = nil
local racePhasePanels = {}
-- SMALL_BOARD_DISPLAY_V1
local smallRaceDisplayRoot = nil
local smallRaceCountdownText = nil
local smallRacePhasePanels = {}
local smallRaceDisplayRoot2 = nil
local smallRaceCountdownText2 = nil
local smallRacePhasePanels2 = {}
local raceGateB = nil
local raceSceneRetryAt = -math.huge
local managerNetSpawned = false
local pendingBroadcastCycleId = nil
local pendingBroadcastQueuedAt = nil
local pendingReceivedResetCycleId = nil
local dispatchRetryCycleId = nil
local dispatchRetryUntil = nil
local dispatchRetryAt = -math.huge
local lastDispatchCycleId = 0
local lastDispatchReachableCount = 0
local lastDispatchMissing = {}
local finishLineRoot = nil
local finishLineRetryAt = -math.huge
local finishTrackers = {}
local finishRecords = {}
local finishSequence = 0
local pendingFinishCrossings = {}
local replicatedFinishLedger = {}
local raceLedgerCycleId = 0
local raceLedgerRevision = 0
local raceLedgerReadyForCurrentCycle = false
local raceLedgerChangeHandle = nil
local raceLedgerLastPayload = ""
local raceObservedPreparingCycleId = 0
local restorePreviousFinalLeaderboard = nil
local buildLeaderboardText = nil
local leaderboardSettlingCycleId = 0
local raceStartAt = nil
local raceStartUnixMilliseconds = nil
local leaderboardRoot = nil
local leaderboardTitle = nil
local leaderboardBody = nil
local leaderboardRetryAt = -math.huge
local leaderboardVisible = false
local leaderboardFinal = false
local leaderboardText = ""
local leaderboardSourceCycleId = 0
local leaderboardVersion = 0
local leaderboardAppliedCycleId = 0
local leaderboardAppliedVersion = 0
local leaderboardResendAt = -math.huge
local leaderboardCjkMaterials = {}
local countdownAudioObject = nil
local countdownAudioSource = nil
local countdownAudioCycleId = 0
local countdownAudioPreviousRemainingMilliseconds = nil
local countdownAudioLastRaceState = nil
local countdownAudioLastHandledCycleId = 0
local countdownAudioLastHandledDigit = 0
local countdownAudioLastPlayedCycleId = 0
local countdownAudioLastPlayedDigit = 0
local countdownAudioLastPlayUnixMilliseconds = -1
local countdownAudioLastError = "waiting for audio bank"

local FINISH_SIDE_EPSILON = 0.01
local FINISH_HALF_WIDTH = 0.5
local FINISH_VERTICAL_TOLERANCE = 4.0
local LEADERBOARD_GLYPH_WARMUP = "NO FINISHERS #0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ.- "
local LEADERBOARD_SETTLING_TEXT = "已完赛，成绩正在结算中"
local setRaceText = nil
local leaderboardCjkObjects = {}
local leaderboardRows = {}
local LEADERBOARD_MAX_ROWS = 10
local LEADERBOARD_ROW_PITCH = 0.38
local LEADERBOARD_TITLE_CHARACTER_SIZE = 0.05
local LEADERBOARD_ROW_CHARACTER_SIZE = 0.0325
local LEADERBOARD_CJK_HEIGHT = 0.286
local LEADERBOARD_CJK_Y_OFFSET = 0.12
local LEADERBOARD_SETTLING_CJK_HEIGHT = 0.55
local LEADERBOARD_SETTLING_CJK_Y = -1.15
local LEADERBOARD_ROW_COLUMN_GAP = "                "

local function realtimeSeconds()
  local value = tonumber(Time.realtimeSinceStartupAsDouble)
  if value == nil then value = tonumber(Time.realtimeSinceStartup) end
  return value or 0
end

local function isNetworkClockAvailable()
  return DouyinNetService ~= nil and DouyinNetService.isNetworkSettled
end

function roomClock.reportSubsystemError(label, value)
  local message = tostring(value or "unknown error")
  if roomClock.subsystemErrors[label] == message then return end
  roomClock.subsystemErrors[label] = message
  UnityEngine.Debug.LogWarning("RaceManager: " .. tostring(label) .. " failed: " .. message)
end

function roomClock.clearSubsystemError(label)
  roomClock.subsystemErrors[label] = nil
end

function roomClock.runSafely(label, callback)
  local ok, first, second, third = pcall(callback)
  if not ok then
    roomClock.reportSubsystemError(label, first)
    return false, nil, nil, nil
  end
  roomClock.clearSubsystemError(label)
  return true, first, second, third
end

function roomClock.hasAuthority()
  if not isNetworkClockAvailable() then return false end
  local spawned = managerNetSpawned
  if not spawned then pcall(function() spawned = self:IsSpawned() end) end
  if not spawned then return false end
  local owner = false
  pcall(function() owner = self:HasOwnership() end)
  return owner == true
end

-- Only the unique RaceManager owner calls this API. Other clients consume the
-- atomic synchronized room snapshot and never choose their own race epoch.
function roomClock.tryReadServerUnixMilliseconds(forceSample)
  local realtime = realtimeSeconds()
  if not isNetworkClockAvailable() then
    serverClockLastError = "network clock unavailable"
    return nil
  end
  if forceSample ~= true and realtime < serverClockNextSampleRealtime then return nil end
  serverClockNextSampleRealtime = realtime + SERVER_CLOCK_RESAMPLE_SECONDS
  local ok, rawSeconds = pcall(function()
    return tonumber(DouyinUtility.GetServerUnixTime())
  end)
  if not ok or rawSeconds == nil or rawSeconds <= 0 or rawSeconds >= math.huge then
    serverClockLastError = ok and "invalid server unix time" or tostring(rawSeconds)
    return nil
  end
  serverClockLastSuccessRealtime = realtime
  serverClockLastError = ""
  return math.floor(rawSeconds) * 1000
end

local function resolveGlobalRaceClock(serverUnixMilliseconds)
  local elapsedSinceEpoch = serverUnixMilliseconds - SCHEDULE_EPOCH_UNIX_MILLISECONDS
  local cycleIndex = math.floor(elapsedSinceEpoch / CYCLE_MILLISECONDS)
  local cycleElapsed = elapsedSinceEpoch - cycleIndex * CYCLE_MILLISECONDS
  local cycleId = SCHEDULE_REVISION * SCHEDULE_TOKEN_STRIDE + cycleIndex + 1
  local cycleStart = SCHEDULE_EPOCH_UNIX_MILLISECONDS + cycleIndex * CYCLE_MILLISECONDS
  local scheduledRaceStart = cycleStart + (PREPARING_SECONDS + WAITING_SECONDS) * 1000
  local preparingEnd = PREPARING_SECONDS * 1000
  local waitingEnd = (PREPARING_SECONDS + WAITING_SECONDS) * 1000
  local racingEnd = (PREPARING_SECONDS + WAITING_SECONDS + RACING_SECONDS) * 1000
  if cycleElapsed < preparingEnd then
    return cycleId, cycleElapsed, cycleStart, scheduledRaceStart,
      "PREPARING", preparingEnd - cycleElapsed
  end
  if cycleElapsed < waitingEnd then
    return cycleId, cycleElapsed, cycleStart, scheduledRaceStart,
      "WAITING", waitingEnd - cycleElapsed
  end
  if cycleElapsed < racingEnd then
    return cycleId, cycleElapsed, cycleStart, scheduledRaceStart,
      "RACING", racingEnd - cycleElapsed
  end
  return cycleId, cycleElapsed, cycleStart, scheduledRaceStart,
    "RECYCLING", CYCLE_MILLISECONDS - cycleElapsed
end

function roomClock.parseSnapshot(payload)
  local normalized = tostring(payload or "")
  local parts = {}
  for value in string.gmatch(normalized, "([^|]+)") do parts[#parts + 1] = value end
  if #parts ~= 10 or parts[1] ~= roomClock.snapshotVersion then return nil end
  if parts[2] ~= roomClock.configSignature then return nil end
  local generation = math.floor(tonumber(parts[3]) or -1)
  local sequence = math.floor(tonumber(parts[4]) or -1)
  local cycleId = math.floor(tonumber(parts[5]) or -1)
  local stateName = tostring(parts[6] or "")
  local logicalMilliseconds = tonumber(parts[7])
  local cycleElapsedMilliseconds = tonumber(parts[8])
  local remainingMilliseconds = tonumber(parts[9])
  local mode = tostring(parts[10] or "")
  if generation < 1 or sequence < 1 or cycleId < 2 then return nil end
  if logicalMilliseconds == nil or cycleElapsedMilliseconds == nil
    or remainingMilliseconds == nil then return nil end
  if logicalMilliseconds <= 0 or logicalMilliseconds >= math.huge
    or cycleElapsedMilliseconds < 0 or cycleElapsedMilliseconds >= CYCLE_MILLISECONDS
    or remainingMilliseconds < 0 or remainingMilliseconds > CYCLE_MILLISECONDS then return nil end
  if mode ~= "SERVER_UNIX" and mode ~= "OWNER_FALLBACK" then return nil end
  local derivedCycleId, derivedElapsed, _, _, derivedState, derivedRemaining =
    resolveGlobalRaceClock(logicalMilliseconds)
  if derivedCycleId ~= cycleId or derivedState ~= stateName then return nil end
  if math.abs(derivedElapsed - cycleElapsedMilliseconds) > 2
    or math.abs(derivedRemaining - remainingMilliseconds) > 2 then return nil end
  return {
    generation = generation,
    sequence = sequence,
    cycleId = cycleId,
    stateName = stateName,
    logicalMilliseconds = logicalMilliseconds,
    cycleElapsedMilliseconds = cycleElapsedMilliseconds,
    remainingMilliseconds = remainingMilliseconds,
    mode = mode,
    payload = normalized,
  }
end

function roomClock.applySnapshotPayload(payload)
  local parsed = roomClock.parseSnapshot(payload)
  if parsed == nil then return false end
  local current = roomClock.snapshotValue
  if current ~= nil then
    if parsed.generation < current.generation
      or (parsed.generation == current.generation and parsed.sequence < current.sequence) then
      return false
    end
    if parsed.generation == current.generation and parsed.sequence == current.sequence then
      if parsed.payload ~= roomClock.snapshotPayload then
        serverClockInvalid = true
        serverClockLastError = "room clock split-brain detected"
        serverClockSource = "CLOCK_UNHEALTHY"
        UnityEngine.Debug.LogError("RaceManager: synchronized room clock split-brain detected")
        return false
      end
      return true
    end
  end
  roomClock.snapshotValue = parsed
  roomClock.snapshotPayload = parsed.payload
  roomClock.snapshotReceivedRealtime = realtimeSeconds()
  roomClock.generation = math.max(roomClock.generation, parsed.generation)
  serverClockInvalid = false
  return true
end

function roomClock.hydrateSnapshot()
  if raceClockSnapshot == nil then return false end
  local ok, payload = pcall(function() return raceClockSnapshot:GetValue() end)
  if not ok then
    roomClock.reportSubsystemError("room clock hydrate", payload)
    return false
  end
  return roomClock.applySnapshotPayload(payload)
end

function roomClock.estimateSnapshot(allowBoundaryCrossing)
  local snapshot = roomClock.snapshotValue
  if snapshot == nil or roomClock.snapshotReceivedRealtime == nil then return nil end
  local elapsedMilliseconds = math.max(
    0,
    realtimeSeconds() - roomClock.snapshotReceivedRealtime
  ) * 1000
  if allowBoundaryCrossing ~= true then
    elapsedMilliseconds = math.min(
      elapsedMilliseconds,
      roomClock.followerMaxInterpolationSeconds * 1000,
      math.max(0, snapshot.remainingMilliseconds - 1)
    )
  end
  return snapshot.logicalMilliseconds + elapsedMilliseconds
end

function roomClock.clearOwnerAnchor()
  serverClockAnchorUnixMilliseconds = nil
  serverClockAnchorRealtime = nil
  serverClockLastReturnedUnixMilliseconds = nil
  serverClockLastSuccessRealtime = nil
  serverClockNextSampleRealtime = -math.huge
  roomClock.mode = nil
  roomClock.sequence = 0
  roomClock.bootstrapStartedRealtime = nil
  roomClock.nextPublishRealtime = -math.huge
end

function roomClock.setOwnerAnchor(logicalMilliseconds, mode, generation)
  local normalized = tonumber(logicalMilliseconds)
  if normalized == nil or normalized <= 0 then return false end
  serverClockAnchorUnixMilliseconds = normalized
  serverClockAnchorRealtime = realtimeSeconds()
  serverClockLastReturnedUnixMilliseconds = normalized
  serverClockInvalid = false
  roomClock.mode = mode
  roomClock.generation = math.max(1, math.floor(tonumber(generation) or 1))
  roomClock.sequence = 0
  roomClock.bootstrapStartedRealtime = nil
  roomClock.nextPublishRealtime = -math.huge
  if mode == "SERVER_UNIX" then
    serverClockSource = "SERVER_UNIX"
    serverClockLastError = ""
  else
    serverClockSource = "OWNER_FALLBACK"
    serverClockLastError = "server unix unavailable; room owner fallback active"
  end
  return true
end

function roomClock.refreshAuthority()
  local owner = roomClock.hasAuthority()
  if roomClock.wasOwner == owner then return owner end
  roomClock.wasOwner = owner
  roomClock.hydrateSnapshot()
  if not owner then
    roomClock.clearOwnerAnchor()
    serverClockSource = roomClock.snapshotValue ~= nil and "RACE_MANAGER_SYNC" or "WAITING_MANAGER"
    return false
  end

  local nextGeneration = math.max(
    roomClock.generation,
    roomClock.snapshotValue ~= nil and roomClock.snapshotValue.generation or 0
  ) + 1
  if roomClock.snapshotValue ~= nil then
    -- Continue from the last atomic room snapshot. Raw realtime values are never
    -- transported between clients; this local value only advances from receipt.
    local continued = roomClock.estimateSnapshot(false)
    if continued ~= nil then
      roomClock.setOwnerAnchor(continued, roomClock.snapshotValue.mode, nextGeneration)
      serverClockSource = roomClock.snapshotValue.mode == "SERVER_UNIX"
        and "SERVER_UNIX_HOLDOVER" or "OWNER_FALLBACK"
      return true
    end
  end
  roomClock.clearOwnerAnchor()
  roomClock.generation = math.max(1, nextGeneration)
  roomClock.bootstrapStartedRealtime = realtimeSeconds()
  serverClockSource = "WAITING_SERVER_UNIX"
  serverClockLastError = "waiting for initial server unix sample"
  return true
end

function roomClock.readOwner(forceSample)
  local realtime = realtimeSeconds()
  if serverClockAnchorUnixMilliseconds == nil or serverClockAnchorRealtime == nil then
    if roomClock.bootstrapStartedRealtime == nil then roomClock.bootstrapStartedRealtime = realtime end
    local measured = roomClock.tryReadServerUnixMilliseconds(forceSample == true)
    if measured ~= nil then
      roomClock.setOwnerAnchor(measured, "SERVER_UNIX", math.max(1, roomClock.generation))
    elseif realtime - roomClock.bootstrapStartedRealtime >= roomClock.bootstrapTimeoutSeconds then
      -- Cold-start fallback is room-local and starts from a safe PREPARING
      -- boundary. Once selected it remains locked for this room timeline.
      roomClock.setOwnerAnchor(
        SCHEDULE_EPOCH_UNIX_MILLISECONDS,
        "OWNER_FALLBACK",
        math.max(1, roomClock.generation)
      )
    else
      serverClockSource = "WAITING_SERVER_UNIX"
      return nil
    end
  elseif roomClock.mode == "SERVER_UNIX" then
    local sampleDue = forceSample == true or realtime >= serverClockNextSampleRealtime
    if sampleDue then
      local measured = roomClock.tryReadServerUnixMilliseconds(forceSample == true)
      if measured == nil then
        serverClockSource = "SERVER_UNIX_HOLDOVER"
      else
        -- GetServerUnixTime is integer seconds. It validates the owner anchor,
        -- while realtimeSinceStartup supplies smooth sub-second progression.
        local estimated = serverClockAnchorUnixMilliseconds
          + math.max(0, realtime - serverClockAnchorRealtime) * 1000
        if math.abs(measured - estimated) > 2500 then
          serverClockLastError = "server unix validation drift; preserving room timeline"
          serverClockSource = "SERVER_UNIX_HOLDOVER"
        else
          serverClockLastError = ""
          serverClockSource = "SERVER_UNIX"
        end
      end
    end
  else
    serverClockSource = "OWNER_FALLBACK"
  end

  local estimated = serverClockAnchorUnixMilliseconds
    + math.max(0, realtime - serverClockAnchorRealtime) * 1000
  if serverClockLastReturnedUnixMilliseconds ~= nil
    and estimated < serverClockLastReturnedUnixMilliseconds then
    estimated = serverClockLastReturnedUnixMilliseconds
  end
  serverClockLastReturnedUnixMilliseconds = estimated
  return estimated
end

function roomClock.readAuthoritativeMilliseconds(forceSample)
  if serverClockInvalid then
    serverClockSource = "CLOCK_UNHEALTHY"
    return nil
  end
  if roomClock.refreshAuthority() then return roomClock.readOwner(forceSample) end
  if roomClock.snapshotValue == nil then roomClock.hydrateSnapshot() end
  local synchronized = roomClock.estimateSnapshot(false)
  if synchronized == nil then
    serverClockSource = "WAITING_MANAGER"
    serverClockLastError = "waiting for RaceManager clock snapshot"
    return nil
  end
  serverClockInvalid = false
  serverClockSource = "RACE_MANAGER_SYNC"
  serverClockLastError = ""
  serverClockLastReturnedUnixMilliseconds = synchronized
  return synchronized
end

function roomClock.publishSnapshot(
  logicalMilliseconds,
  cycleId,
  stateName,
  cycleElapsedMilliseconds,
  remainingMilliseconds,
  forcePublish
)
  if not roomClock.hasAuthority() or raceClockSnapshot == nil or roomClock.mode == nil then return false end
  local realtime = realtimeSeconds()
  local changed = cycleId ~= roomClock.lastPublishedCycleId
    or stateName ~= roomClock.lastPublishedState
  if forcePublish ~= true and not changed and realtime < roomClock.nextPublishRealtime then return false end
  roomClock.sequence = roomClock.sequence + 1
  local payload = table.concat({
    roomClock.snapshotVersion,
    roomClock.configSignature,
    tostring(roomClock.generation),
    tostring(roomClock.sequence),
    tostring(math.floor(cycleId)),
    tostring(stateName),
    tostring(math.floor(logicalMilliseconds)),
    tostring(math.floor(cycleElapsedMilliseconds)),
    tostring(math.floor(remainingMilliseconds)),
    tostring(roomClock.mode),
  }, "|")
  local stillOwner = roomClock.hasAuthority()
  if not stillOwner then return false end
  local ok, failure = pcall(function() raceClockSnapshot:SetValue(payload) end)
  if not ok then
    roomClock.sequence = roomClock.sequence - 1
    roomClock.reportSubsystemError("room clock publish", failure)
    return false
  end
  roomClock.applySnapshotPayload(payload)
  roomClock.nextPublishRealtime = realtime + roomClock.publishIntervalSeconds
  roomClock.lastPublishedCycleId = cycleId
  roomClock.lastPublishedState = stateName
  roomClock.lastPublishedLogicalMilliseconds = logicalMilliseconds
  roomClock.clearSubsystemError("room clock publish")
  return true
end

local function leaderboardRankColor(rowIndex)
  if rowIndex == 0 then return Color(0.10, 0.95, 1.00, 1.0) end
  if rowIndex == 1 then return Color(1.00, 0.74, 0.12, 1.0) end
  if rowIndex == 2 then return Color(0.82, 0.88, 0.95, 1.0) end
  if rowIndex == 3 then return Color(0.82, 0.45, 0.22, 1.0) end
  return Color(0.68, 0.72, 0.78, 1.0)
end

local LEADERBOARD_SETTLING_BITMAP = {
  "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
  "00000000000000000000000000000110000000000000000000011000000000000000000000000000000000000000000110110000000011000000011000000000000000000000000000000000000110000000000000001000000011100000000011100000011000000000000000011000000000",
  "00111111111111111000000000000011000000000000111111111111111110000000000000000000000000000000000110111000000011000111111111100000010000000000001000000000000110000000000000011100000011000000000011111110111111110000000000011000000000",
  "00111111111111111000001111111111111111110000111111111111111110000000000000000000000000000000000110011100000011001111111111110000111111111111111100000000000110000000000000011000000011000000000111111111111111110000000000011000000000",
  "00000000000000011000001111111111111111110000110011000011000110000000000000000000000000011111111111111100000110000000011000000000000000011100000000000111111111111111110000011000111111111110001100110001100110000000000000011000000000",
  "00000000000000011000001100000000000001110000011111111111111100000000000000000000000000011111111111111110000100110111111111100000000000011000000000000111111111111111100000110011111111111110000000110001000100000000111111111111111100",
  "00011000000000011000001100111111111100110000000011000011000000000000000000000000000000011000000110000000001111110000011000000000000000011000000000000000011000010000000001100111000001000000000001111111111110000000111111111111111100",
  "00011000000000011000000001111111111100000000001111111111110000000000000000000000000000011000000110001000001111101111111111110000001100011000000000000000011000110000000001111110000001000000000001100000000110000000110000011000001100",
  "00011000000000111000000000000000000000000000000011000011000000000000000000000000000000011000000110011100000001101111111111110000001100011000000000000001110000110000000001111100011111111100000001111111111110000000110000011000001100",
  "00011111111111111000000000000000000000000001111111111111111100000000000000000000000000011111110110011000000011000000000000000000001100011111111100000001110000110000000000001100000000000000000001100000000110000000110000011000001100",
  "00011000000000111000001111111111111111110000111111111111111100000000000000000000000000011001110110111000000110000111111111100000001100011111111000000011101111111111100000011000000000000000000001111111111110000000110000011000001100",
  "00011000000000000000001111111111111111110000001110000001110000000000000000000000000000011000100011110000001111110110000001100000001100011000000000000111101111111111000000110011011111111100000001100000000110000000111111111111111100",
  "00011000000000000000000000011000110000000001111111111111111110000000000000000000000000110001100011110000001111100110011001100000001100011000000000001111100000110000000001111111011111111100000001111111111110000000110000011000011100",
  "00011000000000000000000000011000110000000001110111111111101110000000000000000000000000110001100011100000000000000110011001100000001100011000000000001101100000110000000001111000011000001100000000001100011100000000010000011000001000",
  "00011000000000001100000000011000110000000000000110011001100000000011100000000000000000110001100011100000000001110110011001100000001100011000000000000001100000110000000000000000011000001100001111111111111111110000000000011000000000",
  "00011000000000001110000000110000110000100000000110110001100000000011100000000000000000110111100111100110001111110000110110000000001100011000000000000001100000110000000000001111011000001100001111111111111111110000000000011000000000",
  "00011000000000001100000001110000110001110000000001110111000000000011100000000000000001110111011100110110001110000001110111000000101100011100001100000001101100111001100001111111011111111100000000011000011100000000000000011000000000",
  "00011111111111111100001111100000111111100000011111100011110000000001100000000000000001100000111000111110000000001111100011110001111111111111111110000001111111111111110001110000011000001100000011110000011100000000000000011000000000",
  "00001111111111111000001110000000011111000000011110000000110000000001000000000000000001100000110000011110000000011110000000110000000000000000000000000001100000000000000000000000011000001100000111100000011100000000000000011000000000",
  "00000000000000000000000000000000000000000000000000000000000000000011000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
}

local CJK_NAME_BITMAPS = {
  ["本场排行榜"] = {
    "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
    "00000000011000000000000001000111111111000000011000001100110000000001100000000000000000001100000011000000",
    "00000000011000000000000011000111111111100000011000001100110000000011100011111111100000001100000011000000",
    "00000000011000000000000001000000000111000000011000001100110000000011000011111111100000001100111111111110",
    "00000000011000000000000001000000001100000000011000111100111110000110000000000000000000001100001100011000",
    "00111111111111111110000001000000011000000001111111111100111110001110000000000000000001111110001110110000",
    "00100001111110000100001111111001110000000001111110001100110000001100110000000000000001111110000110110000",
    "00000001111110000000001111111011111111110000011000001100110000000001100111111111110000011100111111111110",
    "00000001111110000000000001000111111111110000011000001100110000000011100111111111111000011100110011000110",
    "00000011011011000000000001000000110110110000011010111100111110000011000000000110000000011110110011000000",
    "00000011011011000000000001000001101110110000011110111100111100000111000000000110000000111111111111111110",
    "00000110011001100000000001000001101100110001111100001100110000001111000000000110000000111111111111111110",
    "00001100011001110000000001001011001100110001111000001100110000001111000000000110000001101100000100000000",
    "00011100011000111000000001111111011100110000011000001100110000000011000000000110000001101100001111111100",
    "00111111111111111110001111111110011000110000011001111100111110000011000000000110000000001100001100011000",
    "01110011111111000100001110001100111000110000011000001100110000000011000000000110000000001100001100001000",
    "00100000011000000000000000000001110001100000011000001100110000000011000000000110000000001100011000011000",
    "00000000011000000000000000000111100111100000111000001100110000000011000000011110000000001100111000111000",
    "00000000011000000000000000000010000011000000111000001100110000000011000000011100000000001100110001110000",
    "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
  },
  ["玩具"] = {
    "00000000000000000000000000000000000000000",
    "00000000000000000000000000000000000000000",
    "01111110011111111100000001111111111110000",
    "01111110000000000000000001100000000110000",
    "00011000000000000000000001111111111110000",
    "00011000000000000000000001111111111110000",
    "00011000000000000000000001100000000110000",
    "00011001111111111110000001111111111110000",
    "01111110111101101100000001111111111110000",
    "01111110001101100000000001100000000110000",
    "00011000001101100000000001111111111110000",
    "00011000001101100000000001111111111110000",
    "00011000011001100000000001100000000110000",
    "00011010011001100000001111111111111111110",
    "00011110011001100000000000011000010000000",
    "01111100111001100110000000111000111100000",
    "01100001110001100110000001111000011111000",
    "00000011100001111110000111100000000111100",
    "00000011000000111100000110000000000001000",
    "00000000000000000000000000000000000000000",
  },
  ["拼色"] = {
    "00000000000000000000000000000000000000000",
    "00011000011000011000000000001100000000000",
    "00011000011100011000000000011000000000000",
    "00011000001100110000000000111111111100000",
    "00011000000000110000000000111111111000000",
    "01111110111111111110000011100000110000000",
    "01111110001100110000000111000000110000000",
    "00011000001100110000001111111111111111000",
    "00011000001100110000000101100011000111000",
    "00011110001100110000000001100011000011000",
    "00111111111111111110000001100011000011000",
    "01111000111111111110000001111111111111000",
    "01011000001100110000000001111111111111000",
    "00011000001100110000000001100000000011000",
    "00011000001100110000000001100000000000000",
    "00011000011000110000000001100000000000000",
    "00011000111000110000000001100000000001110",
    "00111001110000110000000001111111111111100",
    "00100001100000110000000000111111111111000",
    "00000000000000000000000000000000000000000",
  },
  ["孟菲斯"] = {
    "00000000000000000000000000000000000000000000000000000000000000",
    "00001100000000000000000000011000011000000000011000110000000100",
    "00001111111111110000000000011000011000000000011000110111111110",
    "00000000000111110000001111111111111111110001111111110111110000",
    "00000000001110000000000000011100011000000001111111111110000000",
    "00000000011100000000000000001000011000000000011000110110000000",
    "01111111111111111110000000001100110000000000011111110110000000",
    "01111111111111111110000111111100111111100000011111110111000000",
    "00000000011000000000001111111100111111100000011000110111111110",
    "00000000011000000000000000001100110000000000011111110110011000",
    "00000001111000000000000000001100110000000000011111110110011000",
    "00000000110000000000000111111100111111100000011000110110011000",
    "00011111111111111000000111111100111111100001111111111110011000",
    "00011001100110011000000000001100110000000001111111111110011000",
    "00011001100110011000001111111100111111110000011001100110011000",
    "00011001100110011000001111111100111111110000111001111100011000",
    "00011001100110011000000000001100110000000001110000111100011000",
    "01111111111111111111000000001100110000000001100000011000011000",
    "01100000000000000110000000001100110000000000000000111000011000",
    "00000000000000000000000000000000000000000000000000000000000000",
  },
  ["暴走"] = {
    "00000000000000000000000000000000000000000",
    "00001111111111110000000000000011000000000",
    "00001111111111110000000000000011000000000",
    "00001111111111110000000000000011000000000",
    "00001111111111110000000011111111111111000",
    "00001111111111110000000000000011000000000",
    "00001111111111110000000000000011000000000",
    "00000011000011000000000000000011000000000",
    "00111111111111111000001111111111111111100",
    "00000011000011000000000110000011111111100",
    "01111111111111111110000000000011000000000",
    "00100111011011100100000001110011000000000",
    "00001110011001110000000001100011111111000",
    "01111110011001111110000001100011011110000",
    "01100011111111001100000001110011000000000",
    "00000011111111000000000001111011000000000",
    "00011111011001110000000011011111000000000",
    "00011000111000111000000111000111111111110",
    "00000000110000001000001110000000111111100",
    "00000000000000000000000000000000000000000",
  },
  ["肌肉"] = {
    "00000000000000000000000000000000000000000",
    "00000000000000000000000000000011000000000",
    "00111111001111110000000000000011000000000",
    "00111111001111110000000000000011000000000",
    "00110011001100110000000111111111111111100",
    "00110011001100110000000111111111111111100",
    "00111111001100110000000110000011000001100",
    "00111111001100110000000110000111110001100",
    "00110011001100110000000110011100011101100",
    "00110011001100110000000110111000001101100",
    "00110011001100110000000110010011000001100",
    "00111111001100110000000110000011000001100",
    "00110011001100110000000110000111000001100",
    "00100011001100110000000110001111110001100",
    "00100011001100110000000110011100111001100",
    "01100011011000110000000110111000001001100",
    "01100011011000110110000110000000000001100",
    "01100111011000111110000110000000000111100",
    "01000110110000011110000110000000000111000",
    "00000000000000000000000000000000000000000",
  },
  ["怪兽"] = {
    "00000000000000000000000000000000000000000",
    "00001000000000000000000000011000011000000",
    "00001001111111111100000000011100011000000",
    "00001000111000011000000011111111111111000",
    "00001110011000111000000011111111111111000",
    "01101111001100110000000011000011000011000",
    "01101011000111100000000011111111111111000",
    "01101001000111100000000011111111111111000",
    "01101000011111111100000011000011000011000",
    "01101001111000111110000011111111111111000",
    "00001001100011000100000000000000000000000",
    "00001000000011000000001111111111111111110",
    "00001000111111111100001111111111111111110",
    "00001000111111111100000001111111111110000",
    "00001000000011000000000011111111111110000",
    "00001000000011000000000001100000000110000",
    "00001001100011001100000001100000000110000",
    "00001011111111111110000011111111111110000",
    "00001100000000000000000011100000000110000",
    "00000000000000000000000000000000000000000",
  },
  ["千禧"] = {
    "00000000000000000000000000000000000000000",
    "00000000000001110000000001000000011000000",
    "00000001111111110000000001100111111111110",
    "00111111111100000000000001100111111111110",
    "00011000011000000000000000000010011100100",
    "00000000011000000000001111111011111111100",
    "00000000011000000000001000110000000000000",
    "00000000011000000000000000110111111111100",
    "00000000011000000000000001100010000001100",
    "01111111111111111110000001110111111111100",
    "01111111111111111110000011110011111111100",
    "00000000011000000000000111111001100011000",
    "00000000011000000000001101100111111111110",
    "00000000011000000000001001100111111111110",
    "00000000011000000000000001100011111111100",
    "00000000011000000000000001100111111111100",
    "00000000011000000000000001100110000000100",
    "00000000011000000000000001100111111111100",
    "00000000011000000000000001100111111111100",
    "00000000000000000000000000000000000000000",
  },
  ["甜品"] = {
    "00000000000000000000000000000000000000000",
    "00000001001100011000000000000000000000000",
    "01111111101100011000000001111111111110000",
    "01111100001100011000000001110000001100000",
    "00001100001100011000000000100000000100000",
    "00001100011111111110000000100000000100000",
    "01111111111111111110000001110000001100000",
    "01111111101100011000000001111111111110000",
    "00001100001100011000000000000000000000000",
    "00001100001100011000000000000000000000000",
    "00001100001111111000000111111100111111100",
    "00111111101111111000000111111100111111100",
    "00110001101100011000000110001100110000100",
    "00110001101100011000000110001100110000100",
    "00110001101100011000000110001100110000100",
    "00110001101100011000000110001100110001100",
    "00111111101111111000000111111100111111100",
    "00110011101111111000000110001100110001100",
    "00110001001100011000000100000100100000000",
    "00000000000000000000000000000000000000000",
  },
  ["牛牛"] = {
    "00000000000000000000000000000000000000000",
    "00000000001100000000000000000001100000000",
    "00000110001100000000000000110001100000000",
    "00000110001100000000000000110001100000000",
    "00001100001100000000000001100001100000000",
    "00001111111111111100000001111111111111100",
    "00011111111111111000000011111111111111000",
    "00011000001100000000000011000001100000000",
    "00110000001100000000000110000001100000000",
    "00010000001100000000000010000001100000000",
    "00000000001100000000000000000001100000000",
    "01111111111111111110001111111111111111110",
    "01111111111111111110001111111111111111110",
    "00000000001100000000000000000001100000000",
    "00000000001100000000000000000001100000000",
    "00000000001100000000000000000001100000000",
    "00000000001100000000000000000001100000000",
    "00000000001100000000000000000001100000000",
    "00000000001100000000000000000001100000000",
    "00000000000000000000000000000000000000000",
  },
  ["街机"] = {
    "00000000000000000000000000000000000000000",
    "00001000010000000000000001100000000000000",
    "00011100011000000000000001100001111110000",
    "00011000011000111110000001100001111110000",
    "00110011111110000000000001100001100110000",
    "01100001011000000000001111111101100110000",
    "00001100011000000000001111111001000110000",
    "00001101011110111110000011100001000110000",
    "00011011111111111110000011100001000110000",
    "00111000010000011000000011111001000110000",
    "00111000011000011000000111111001000110000",
    "01111011111110011000000111101111000110000",
    "01011011111110011000001101100011000110000",
    "00011000011000011000001101100011000110000",
    "00011000011000011000001001100011000110000",
    "00011000011110011000000001100110000110010",
    "00011011111110011000000001100110000110110",
    "00011011100000111000000001101100000111110",
    "00011000000000111000000001101100000011100",
    "00000000000000000000000000000000000000000",
  },
  ["积木"] = {
    "00000000000000000000000000000000000000000",
    "00000001000000000000000000000011000000000",
    "00111111101111111100000000000011000000000",
    "01111100011111111100000000000011000000000",
    "00001100001000001100000000000011000000000",
    "00001100001000001100001111111111111111110",
    "00001100001000001100001111111111111111100",
    "01111111101000001100000000001111100000000",
    "01111111101000001100000000001111110000000",
    "00001100001000001100000000011011110000000",
    "00011111011111111100000000011011011000000",
    "00011111001111111100000000110011011100000",
    "00111101100000000000000001110011001110000",
    "01111100000100010000000011100011000111000",
    "01101100001100011000000111000011000011100",
    "00001100011100011100001110000011000001110",
    "00001100011000001110000100000011000000100",
    "00001100110000000110000000000011000000000",
    "00001101100000000110000000000011000000000",
    "00000000000000000000000000000000000000000",
  },
  ["宝宝巴"] = {
    "00000000000000000000000000000000000000000000000000000000000000",
    "00000000011000000000000000000011000000000000000000000000000000",
    "00000000011000000000000000000011000000000000011111111111111000",
    "01111111111111111110001111111111111111110000111111111111111000",
    "01111111111111111110001111111111111111110000110000011000011000",
    "01100000000000000110001100000000000000110000110000011000011000",
    "01100000000000000110001100000000000000110000110000011000011000",
    "01101111111111111000001101111111111111000000110000011000011000",
    "00001111111111110000000001111111111110000000110000011000011000",
    "00000000011000000000000000000011000000000000111111111111111000",
    "00000000011000000000000000000011000000000000111111111111111000",
    "00011111111111111000000011111111111111000000110000000000011000",
    "00011111111111111000000011111111111111000000110000000000000000",
    "00000000011000100000000000000011000100000000110000000000000000",
    "00000000011001100000000000000011001100000000110000000000000100",
    "00000000011000110000000000000011000110000000110000000000000110",
    "00000000011000110000000000000011000110000000011000000000001110",
    "01111111111111111110001111111111111111110000011111111111111100",
    "00111111111111111100000111111111111111100000001111111111111000",
    "00000000000000000000000000000000000000000000000000000000000000",
  },
  ["阳光号"] = {
    "00000000000000000000000000000000000000000000000000000000000000",
    "00000000000000000000000000000011000000000000000000000000000000",
    "00111111011111111100000000000011000000000000001111111111110000",
    "00110011011111111100000001000011000011000000001100000000110000",
    "00110011011000001100000011100011000111000000001100000000110000",
    "00110110011000001100000001110011000110000000001100000000110000",
    "00110110011000001100000000110011001100000000001111111111110000",
    "00110110011000001100000000100011000100000000000000000000000000",
    "00110110011100001100001111111111111111110000000000000000000000",
    "00110110011111111100001111111111111111110001111111111111111110",
    "00110011011000001100000000001100110000000000000111000000000000",
    "00110011011000001100000000001100110000000000000011000000000000",
    "00110001011000001100000000001100110000000000000111111111110000",
    "00110011011000001100000000011000110000000000000111111111110000",
    "00111111011000001100000000011000110000000000000000000000110000",
    "00110100011111111100000000110000110000110000000000000000110000",
    "00110000011100001100000011100000110001110000000000000000110000",
    "00110000011000001100001111000000111111100000000000011111100000",
    "00110000001000000100001110000000011111000000000000001111100000",
    "00000000000000000000000000000000000000000000000000000000000000",
  },
  ["旋律号"] = {
    "00000000000000000000000000000000000000000000000000000000000000",
    "00001100000110000000000001100000110000000000000000000000000000",
    "00000110001110000000000001100000110000000000001111111111110000",
    "00000110001111111110000011001111111111000000001100000000110000",
    "01111111101111111110000110001110110011000000001100000000110000",
    "01111111111000000000001100000000110011000000001100000000110000",
    "00011000011111111110000001111111111111110000001111111111110000",
    "00011000111111111110000001100000110011100000000000000000000000",
    "00011111000001100110000011000000110011000000000000000000000000",
    "00011111000001100100000111001111111111000001111111111111111110",
    "00011011001101100000001111000000110000000000000111000000000000",
    "00011011011001111100001111000000110000000000000011000000000000",
    "00010011011001111100000011011111111111100000000111111111110000",
    "00110011011001100000000011000000110000000000000111111111110000",
    "00110011011101100000000011000000110000000000000000000000110000",
    "01110011011111100000000011111111111111110000000000000000110000",
    "01101110110111100000000011000000110000000000000000000000110000",
    "01100101110011111110000011000000110000000000000000011111100000",
    "00000001100000111110000011000000110000000000000000001111100000",
    "00000000000000000000000000000000000000000000000000000000000000",
  },
  ["爆米花"] = {
    "00000000000000000000000000000000000000000000000000000000000000",
    "00001100111111111100000000000011000000000000000011000110000000",
    "00001100111111111100000011000011000011000000000011000110000000",
    "00001100111111111100000011100011000111000001111111111111111110",
    "00001100111111111100000001110011000110000001111111111111111110",
    "01101111110000001100000000110011001100000000000011000110000000",
    "01101110111111111100000000100011001100000000000011000010000000",
    "01101100001100110000000000000011000000000000000011000110000000",
    "01101000111111111110001111111111111111110000000110000110011000",
    "01101000111100111100001111111111111111110000001110000100111000",
    "01001001111100111110000000001111110000000000011100000101110000",
    "00011001111111111110000000011111011000000001111100000111100000",
    "00011110011010111000000000011011011100000001100100001110000000",
    "00011110110011011110000000110011001110000000000100111100000000",
    "00010011111011011110000001110011000111100000000101111100000000",
    "00110001001111111000001111100011000011110000000100000100000110",
    "00110000011111111000001110000011000000110000000100000110000110",
    "01100001111011011100000100000011000000000000000110000111111110",
    "00100000000111000100000000000011000000000000001110000011111000",
    "00000000000000000000000000000000000000000000000000000000000000",
  },
  ["莓爆花"] = {
    "00000000000000000000000000000000000000000000000000000000000000",
    "00000011000011000000000001100111111111100000000011000110000000",
    "01100011100111000010000001100111111111100000000011000110000000",
    "01111111111111111111000001100111111111100001111111111111111110",
    "00000011000011000000000001100111111111100001111111111111111110",
    "00001100000000000000001101111110000001100000000011000110000000",
    "00011111111111111100001101110111111111100000000011000010000000",
    "00011000000000000000001101100001100110000000000011000110000000",
    "00110111111111110000001101000111111111110000000110000110011000",
    "01101111111111110000001101000111100111100000001110000100111000",
    "00001100011100110000001001001111100111110000011100000101110000",
    "00111100011100111100000011001111111111110001111100000111100000",
    "01111111111111111110000011110011010111000001100100001110000000",
    "00001100011000110000000011110110011011110000000100111100000000",
    "00001100011100110000000010011111011011110000000101111100000000",
    "00011111111111111100000110001001111111000000000100000100000110",
    "00011111111111111100000110000011111111000000000100000110000110",
    "00000000000011100000001100001111011011100000000110000111111110",
    "00000000000011100000000100000000111000100000001110000011111000",
    "00000000000000000000000000000000000000000000000000000000000000",
  },
  ["绯樱"] = {
    "00000000000000000000000000000000000000000",
    "00001000000100110000000011000000000000000",
    "00011100001100110000000011001111101111110",
    "00011000001100110000000011001100101100110",
    "00110000111100111110000011001110101111110",
    "00110000111100111110001111111110101111110",
    "01100111001100110000000011001110101111110",
    "01111110001100110000000011001110101111110",
    "01111100001100110000000111101110101110110",
    "00001100111100111110000111110111000111000",
    "00011000111100111100000111010101100111100",
    "00110000001100110000001111001100101100110",
    "01111110001100110000001011000001100000000",
    "01111110001100110000000011011111111111110",
    "00000000111100111110000011000011000110000",
    "00001111001100110000000011000011111100000",
    "01111110001100110000000011000000111100000",
    "01100000001100110000000011000011111111100",
    "00000000001100110000000011001111000001100",
    "00000000000000000000000000000000000000000",
  },
  ["紫焰"] = {
    "00000000000000000000000000000000000000000",
    "00000011000110000000000001100000110000000",
    "00010011000110011000000001100000110000000",
    "00110011110111111100000001100001111111100",
    "00010011110111100000000001101001111111000",
    "00010011000110000100001101111111000011000",
    "00111111110110000110001101111011000110000",
    "01111111110111111100001101110010000110000",
    "00100001110000000000001101100001100000000",
    "00000011100111100000001101100011110111110",
    "00001111111110000000000001100011000000110",
    "00001111111000110000000001100011000000110",
    "00000011100000111000000011100011110111110",
    "00011111111111111100000011110011110111110",
    "00011111111100001100000011111011000000110",
    "00000110011001100000000110011011000000110",
    "00011110011001111000000110000011111111110",
    "01111001111000011110001100000011111111110",
    "01100000110000000100001100000011000000110",
    "00000000000000000000000000000000000000000",
  },
  ["薄荷糖"] = {
    "00000000000000000000000000000000000000000000000000000000000000",
    "00000011000011000000000000011000011000000000001100000011100000",
    "01111111111111111110001100011100011000110000001100000011101110",
    "01111111111111111110001111111111111111110001101111111111111110",
    "00000011000111110000000000011000011000000001101111110001100000",
    "00010011100110111100000000101000011000000001101111110111111100",
    "00111011111111111110000000110000000000000000101110110111111100",
    "00001000000110000000000001101111111111110001111111110001101100",
    "00000001111111111000000011100000000011000001111111111111111110",
    "01100001100110011000000111100000000011000000011100110001101100",
    "00111001111111111000000111100111111011000000011110110111111100",
    "00010001100110011000001101100111111011000000111111110111111100",
    "00000001111111111000001001100110011011000000111111110001100000",
    "00001001000110011000000001100110011011000001101100111111111100",
    "00011011111111111110000001100111111011000001101100111111111100",
    "00110011111111111110000001100111111011000001001101101100001100",
    "00110000100000110000000001100000000011000000001101101111111100",
    "01100000110000110000000001100000001111000000001111001111111100",
    "00100000010011110000000001100000000110000000001111001100001100",
    "00000000000000000000000000000000000000000000000000000000000000",
  },
  ["牛粉"] = {
    "00000000000000000000000000000000000000000",
    "00000000001100000000000001100000000100000",
    "00000110001100000000000001100000110110000",
    "00000110001100000000001101101100110110000",
    "00001100001100000000001101101100100110000",
    "00001111111111111100000111111001100010000",
    "00011111111111111000000101111001100011000",
    "00011000001100000000001101111011000011100",
    "00110000001100000000001111111011111111110",
    "00010000001100000000000001100111111111110",
    "00000000001100000000000011110100110011010",
    "01111111111111111110000011111000110011000",
    "01111111111111111110000111101100110011000",
    "00000000001100000000000111101100110011000",
    "00000000001100000000001101100000110011000",
    "00000000001100000000001101100001100011000",
    "00000000001100000000000001100011100011000",
    "00000000001100000000000001100111001110000",
    "00000000001100000000000001100110001110000",
    "00000000000000000000000001100000000000000",
  },
  ["星梦巴"] = {
    "00000000000000000000000000000000000000000000000000000000000000",
    "00000000000000000000000000110000001100000000000000000000000000",
    "00011111111111111000000000110000001100000000011111111111111000",
    "00011000000000011000001111111111111111100000111111111111111000",
    "00011111111111111000001111111111111111110000110000011000011000",
    "00011111111111111000000001111000011110000000110000011000011000",
    "00011000000000011000000011111100111111000000110000011000011000",
    "00011111111111111000000110110101111101100000110000011000011000",
    "00011111111111111000001110110011101100110000110000011000011000",
    "00001000011000000000000100111101001100000000111111111111111000",
    "00011100011000000000000000001100000000000000111111111111111000",
    "00011111111111111100000000011111111111000000110000000000011000",
    "00111111111111111000000000110000000110000000110000000000000000",
    "01110000011000000000000011100100001110000000110000000000000000",
    "01101111111111111000000011000111011100000000110000000000000100",
    "00001111111111111000000000000011111000000000110000000000000110",
    "00000000011000000000000000000011110000000000011000000000001110",
    "01110000011000001110000111111111000000000000011111111111111100",
    "01111111111111111110000111111000000000000000001111111111111000",
    "00000000000000000000000000000000000000000000000000000000000000",
  },
  ["暮翼巡游"] = {
    "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
    "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
    "00000000000000000000000000000000000000000000000000000001100000000000000000000000001100000000",
    "00000000011100011000000000111111110111111110000001100001100111011100000000001100001100000000",
    "00000000011000011000000000000000010000000010000001100001100110011000001110001100001100000000",
    "00001111111111111111110000001100010001100010000000110001000110011000000110000000001111110000",
    "00000000001000011000000000000111110001111110000000100011001100110000000011111111011111110000",
    "00000011111111111111000000111110010111100010000000000011001100110000000000011000011000000000",
    "00000011000000000011000000000000000000000000000111110110001001100000000000011000110000000000",
    "00000011111111111111000000011111111111111100000111110110011001100000001100011000111111110000",
    "00000011000000000011000000011000001100001100000000100110011001100000001110011111000001110000",
    "00000011111111111111000000011111111111111100000001100011001100110000000110011111000011100000",
    "00000000001100000000000000011000001100001100000011000011001100110000000000011011000011000000",
    "00001111111111111111111000011111111111111100000011110011001110111000000000010011000011000000",
    "00000000110000001100000000000001100001100000000000110001100110011000000000110011111111111000",
    "00000011110000000110000000011111111111111110000000110001100110011100000110110011111111111000",
    "00001111111111111111100000000001100001100000000000110001100110001000000110110011000011000000",
    "00011101100000000110110000000001100001100000000001100000000000000000001100110011000011000000",
    "00000001111111111110000001111111111111111111100001111000000000000000001101110011000011000000",
    "00000001100000000110000000000001100001100000000011111111111111111110001101100111000011000000",
    "00000001111111111110000000001111100000111110000111000111111111111100001101100110001111000000",
    "00000001100000000110000000111100000000000110000010000000000001111000000001000000001110000000",
    "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
    "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
  },
  ["甜咒南瓜"] = {
    "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
    "00000000000001100001100000000000000000000000000000000000110000000000000000000000000110000000",
    "00000001111001100001100000000000000000000000000000000000110000000000000000000001111111000000",
    "00011111111101100001100000111111110111111110000000000000110000000000000011111111111111000000",
    "00001111100001100001100000110000110010000110000011111111111111111110000011111111111000000000",
    "00000001100001100001100000110000110010000110000000000000110000000000000011000110011000000000",
    "00000001100011111111111000110000110010000110000000000000110000000000000011000110011000000000",
    "00010001101111100001100000111111110111111110000001100000110000011000000011000110011000000000",
    "00011111111101100001100000111111110111111110000001111111111111111000000011000110001100000000",
    "00000001100001100001100000000000000000000000000001100011001110011000000011000110001100000000",
    "00000001100001100001100000000000000000000000000001100011001100011000000011000110001100000000",
    "00000001100001100001100000000011111111100000000001100010001100011000000011000110001100000000",
    "00000001100001111111100000000011111111100000000001101111111111011000000011000100001100000000",
    "00001111111001100001100000000011000001100000000001100000110000011000000110000100001110000000",
    "00001100011001100001100000000011000001100000000001100000110000011000000110000100000110000000",
    "00001100011001100001100000000011000001100000000001100000110000011000000110000101100111000000",
    "00001100011001100001100000000011000001100001000001101111111111011000000110001100110011100000",
    "00001100011001100001100000000110000001100001100001100000110000011000001110001111110011110000",
    "00001111111001111111100000001110000001100011100001100000110000011000001100111111111001111000",
    "00001100011001100001100000111000000001111111000001100000110001111000011100011100011000110000",
    "00001100000001100001100000110000000001111111000001100000110001110000001000000000000000000000",
    "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
    "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
    "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
  },
}

local function findDescendant(root, targetName)
  if root == nil then return nil end
  if tostring(root.name) == targetName then return root end
  for i = 0, root.childCount - 1 do
    local found = findDescendant(root:GetChild(i), targetName)
    if found ~= nil then return found end
  end
  return nil
end

local function visitDescendants(root, visitor)
  if root == nil then return end
  visitor(root)
  for i = 0, root.childCount - 1 do
    visitDescendants(root:GetChild(i), visitor)
  end
end

local function setRendererVisible(root, visible)
  if root == nil then return end
  local renderer = root.gameObject:GetComponent(typeof(UnityEngine.Renderer))
  if renderer ~= nil then renderer.enabled = visible end
  for i = 0, root.childCount - 1 do
    setRendererVisible(root:GetChild(i), visible)
  end
end

local function disableAllColliders(root)
  if root == nil then return end
  local colliders = root.gameObject:GetComponentsInChildren(typeof(UnityEngine.Collider), true)
  for i = 0, colliders.Length - 1 do
    if colliders[i] ~= nil then colliders[i].enabled = false end
  end
end

local function styleLeaderboardPanel(root)
  if root == nil then return end
  local renderers = root.gameObject:GetComponentsInChildren(typeof(UnityEngine.Renderer), true)
  for i = 0, renderers.Length - 1 do
    local renderer = renderers[i]
    local rendererName = renderer ~= nil and tostring(renderer.gameObject.name) or ""
    local isLeaderboardText = string.find(rendererName, "Race_Leaderboard_", 1, true) == 1
      or string.find(rendererName, "Race_CJK_", 1, true) == 1
    if renderer ~= nil and not isLeaderboardText then
      local material = renderer.material
      if material ~= nil then
        pcall(function()
          local opaqueShader = UnityEngine.Shader.Find("Universal Render Pipeline/Unlit")
          if opaqueShader == nil then opaqueShader = UnityEngine.Shader.Find("Standard") end
          if opaqueShader ~= nil then material.shader = opaqueShader end
          local panelColor = Color(0.018, 0.028, 0.045, 1.0)
          material.color = panelColor
          material:SetColor("_BaseColor", panelColor)
          material:SetColor("_Color", panelColor)
          material:SetFloat("_Mode", 0)
          material:SetFloat("_Surface", 0)
          material:SetInt("_SrcBlend", 1)
          material:SetInt("_DstBlend", 0)
          material:SetInt("_ZWrite", 1)
          material:DisableKeyword("_ALPHATEST_ON")
          material:DisableKeyword("_ALPHABLEND_ON")
          material:DisableKeyword("_ALPHAPREMULTIPLY_ON")
          material:DisableKeyword("_SURFACE_TYPE_TRANSPARENT")
          material:DisableKeyword("_EMISSION")
          material.renderQueue = 2000
        end)
      end
    end
  end
end

local function styleFinishLine(root)
  if root == nil then return end
  local renderers = root.gameObject:GetComponentsInChildren(typeof(UnityEngine.Renderer), true)
  for i = 0, renderers.Length - 1 do
    local renderer = renderers[i]
    if renderer ~= nil and renderer.material ~= nil then
      pcall(function()
        renderer.material.color = Color(0.02, 0.92, 1.0, 1.0)
        renderer.material:EnableKeyword("_EMISSION")
        renderer.material:SetColor("_EmissionColor", Color(0.0, 1.15, 1.35, 1.0))
      end)
    end
  end
end

local function createLeaderboardText(parent, objectName, localY, characterSize, color, anchor)
  if parent == nil then return nil end
  local existing = findDescendant(parent, objectName)
  local object = existing ~= nil and existing.gameObject or UnityEngine.GameObject(objectName)
  if existing == nil then object.transform:SetParent(parent, false) end
  object.transform.localPosition = Vector3(0, localY, 0.56)
  object.transform.localRotation = Quaternion.Euler(0, 180, 0)
  local scale = parent.lossyScale
  object.transform.localScale = Vector3(
    1 / math.max(0.001, math.abs(scale.x)),
    1 / math.max(0.001, math.abs(scale.y)),
    1 / math.max(0.001, math.abs(scale.z))
  )
  local textMesh = object:GetComponent(typeof(UnityEngine.TextMesh))
  if textMesh == nil then textMesh = object:AddComponent(typeof(UnityEngine.TextMesh)) end
  textMesh.text = ""
  textMesh.fontSize = 128
  textMesh.characterSize = characterSize
  textMesh.anchor = anchor
  textMesh.alignment = UnityEngine.TextAlignment.Center
  textMesh.color = color
  pcall(function()
    local font = UnityEngine.Font.CreateDynamicFontFromOSFont("Microsoft YaHei UI", 128)
    if font ~= nil then
      pcall(function()
        font:RequestCharactersInTexture(LEADERBOARD_GLYPH_WARMUP, 128, UnityEngine.FontStyle.Normal)
      end)
      textMesh.font = font
      local renderer = object:GetComponent(typeof(UnityEngine.MeshRenderer))
      if renderer ~= nil then renderer.sharedMaterial = font.material end
    end
  end)
  return textMesh
end

local function createLeaderboardRowText(parent, rowIndex)
  if parent == nil then return nil end
  local objectName = string.format("Race_Leaderboard_Row_%02d", rowIndex)
  local existing = findDescendant(parent, objectName)
  local object = existing ~= nil and existing.gameObject or UnityEngine.GameObject(objectName)
  if existing == nil then object.transform:SetParent(parent, false) end
  object.transform.localPosition = Vector3(
    0,
    -(rowIndex - 1) * LEADERBOARD_ROW_PITCH,
    -0.006
  )
  -- The body already carries the board-facing 180-degree rotation and
  -- inverse world scale. Row children inherit it exactly once.
  object.transform.localRotation = Quaternion.identity
  object.transform.localScale = Vector3.one
  local textMesh = object:GetComponent(typeof(UnityEngine.TextMesh))
  if textMesh == nil then textMesh = object:AddComponent(typeof(UnityEngine.TextMesh)) end
  textMesh.text = ""
  textMesh.fontSize = 128
  textMesh.characterSize = LEADERBOARD_ROW_CHARACTER_SIZE
  textMesh.anchor = UnityEngine.TextAnchor.MiddleCenter
  textMesh.alignment = UnityEngine.TextAlignment.Center
  textMesh.color = Color(0.94, 0.99, 1.0, 1.0)
  if leaderboardBody ~= nil and leaderboardBody.font ~= nil then
    textMesh.font = leaderboardBody.font
    local renderer = object:GetComponent(typeof(UnityEngine.MeshRenderer))
    if renderer ~= nil then renderer.sharedMaterial = leaderboardBody.font.material end
  end
  return textMesh
end

local function getLeaderboardCjkMaterial(rowIndex)
  local materialIndex = math.min(math.max(tonumber(rowIndex) or 4, 0), 4)
  if leaderboardCjkMaterials[materialIndex] ~= nil then
    return leaderboardCjkMaterials[materialIndex]
  end
  local shader = UnityEngine.Shader.Find("Sprites/Default")
  if shader == nil then shader = UnityEngine.Shader.Find("Universal Render Pipeline/Unlit") end
  if shader == nil then return nil end
  local material = UnityEngine.Material(shader)
  material.name = "Race_Leaderboard_CJK_Rank_" .. tostring(materialIndex)
  material.color = leaderboardRankColor(materialIndex)
  material.renderQueue = 3200
  pcall(function()
    material:SetInt("_ZWrite", 0)
    material:SetInt("_Cull", 0)
  end)
  leaderboardCjkMaterials[materialIndex] = material
  return material
end

local function countBitmapRuns(bitmap)
  local count = 0
  for row = 1, #bitmap do
    local line = bitmap[row]
    local column = 1
    while column <= #line do
      if string.sub(line, column, column) == "1" then
        count = count + 1
        repeat column = column + 1
        until column > #line or string.sub(line, column, column) ~= "1"
      else
        column = column + 1
      end
    end
  end
  return count
end

local function createLeaderboardCjkName(parent, vehicleName, bitmap, heightOverride)
  if parent == nil or bitmap == nil or #bitmap == 0 then return nil end
  local objectName = "Race_CJK_" .. tostring(vehicleName)
  local existing = findDescendant(parent, objectName)
  local object = existing ~= nil and existing.gameObject or UnityEngine.GameObject(objectName)
  if existing == nil then object.transform:SetParent(parent, false) end
  object.transform.localPosition = Vector3(0, 0, -0.012)
  object.transform.localRotation = Quaternion.Euler(0, 0, 0)
  object.transform.localScale = Vector3.one

  local filter = object:GetComponent(typeof(UnityEngine.MeshFilter))
  if filter == nil then filter = object:AddComponent(typeof(UnityEngine.MeshFilter)) end
  local renderer = object:GetComponent(typeof(UnityEngine.MeshRenderer))
  if renderer == nil then renderer = object:AddComponent(typeof(UnityEngine.MeshRenderer)) end
  local material = getLeaderboardCjkMaterial(4)
  if material ~= nil then renderer.sharedMaterial = material end
  renderer.enabled = false
  pcall(function()
    renderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off
    renderer.receiveShadows = false
  end)

  local meshHeight = tonumber(heightOverride) or LEADERBOARD_CJK_HEIGHT
  local heightKey = math.floor(meshHeight * 10000 + 0.5)
  local meshVersionName = objectName .. "_Mesh_v4_" .. tostring(heightKey)
  if filter.sharedMesh == nil or tostring(filter.sharedMesh.name) ~= meshVersionName then
    local runCount = countBitmapRuns(bitmap)
    local System = CS.System
    local vertices = System.Array.CreateInstance(typeof(UnityEngine.Vector3), runCount * 4)
    local triangles = System.Array.CreateInstance(typeof(System.Int32), runCount * 6)
    local bitmapHeight = #bitmap
    local bitmapWidth = #bitmap[1]
    local pixelSize = meshHeight / math.max(1, bitmapHeight)
    local totalWidth = bitmapWidth * pixelSize
    local totalHeight = bitmapHeight * pixelSize
    local quad = 0
    for row = 1, bitmapHeight do
      local line = bitmap[row]
      local column = 1
      while column <= #line do
        if string.sub(line, column, column) == "1" then
          local runStart = column
          repeat column = column + 1
          until column > #line or string.sub(line, column, column) ~= "1"
          local runEnd = column - 1
          local x0 = (runStart - 1) * pixelSize - totalWidth * 0.5
          local x1 = runEnd * pixelSize - totalWidth * 0.5
          local y1 = totalHeight * 0.5 - (row - 1) * pixelSize
          local y0 = y1 - pixelSize
          local vertexBase = quad * 4
          local triangleBase = quad * 6
          vertices[vertexBase] = Vector3(x0, y0, 0)
          vertices[vertexBase + 1] = Vector3(x1, y0, 0)
          vertices[vertexBase + 2] = Vector3(x1, y1, 0)
          vertices[vertexBase + 3] = Vector3(x0, y1, 0)
          triangles[triangleBase] = vertexBase
          triangles[triangleBase + 1] = vertexBase + 1
          triangles[triangleBase + 2] = vertexBase + 2
          triangles[triangleBase + 3] = vertexBase
          triangles[triangleBase + 4] = vertexBase + 2
          triangles[triangleBase + 5] = vertexBase + 3
          quad = quad + 1
        else
          column = column + 1
        end
      end
    end
    local mesh = UnityEngine.Mesh()
    mesh.name = meshVersionName
    mesh.vertices = vertices
    mesh.triangles = triangles
    mesh:RecalculateBounds()
    mesh:RecalculateNormals()
    filter.sharedMesh = mesh
  end
  return { object = object, renderer = renderer }
end

local function setupLeaderboardCjkNames()
  leaderboardCjkObjects = {}
  if leaderboardBody == nil then return end
  for i = 1, #fleet do
    local vehicleName = fleet[i].rootName
    local item = createLeaderboardCjkName(
      leaderboardBody.transform,
      vehicleName,
      CJK_NAME_BITMAPS[vehicleName]
    )
    if item ~= nil then leaderboardCjkObjects[vehicleName] = item end
  end
  local settlingItem = createLeaderboardCjkName(
    leaderboardBody.transform,
    LEADERBOARD_SETTLING_TEXT,
    LEADERBOARD_SETTLING_BITMAP,
    LEADERBOARD_SETTLING_CJK_HEIGHT
  )
  if settlingItem ~= nil then
    leaderboardCjkObjects[LEADERBOARD_SETTLING_TEXT] = settlingItem
  end
  local titleItem = createLeaderboardCjkName(
    leaderboardBody.transform,
    "本场排行榜",
    CJK_NAME_BITMAPS["本场排行榜"],
    0.44
  )
  if titleItem ~= nil then
    leaderboardCjkObjects["本场排行榜"] = titleItem
  end
end

local function setupLeaderboardRows()
  leaderboardRows = {}
  if leaderboardBody == nil then return end
  for rowIndex = 1, LEADERBOARD_MAX_ROWS do
    local textMesh = createLeaderboardRowText(leaderboardBody.transform, rowIndex)
    if textMesh ~= nil then
      leaderboardRows[rowIndex] = {
        text = textMesh,
        renderer = textMesh.gameObject:GetComponent(typeof(UnityEngine.Renderer)),
      }
    end
  end
end

local function hideLeaderboardRows()
  for rowIndex = 1, LEADERBOARD_MAX_ROWS do
    local row = leaderboardRows[rowIndex]
    if row ~= nil then
      setRaceText(row.text, "")
      if row.renderer ~= nil then row.renderer.enabled = false end
    end
  end
end

local function hideLeaderboardCjkNames()
  for _, item in pairs(leaderboardCjkObjects) do
    if item.renderer ~= nil then item.renderer.enabled = false end
  end
end

local function isLeaderboardSettling()
  return not leaderboardFinal and leaderboardText == LEADERBOARD_SETTLING_TEXT
end

local function updateLeaderboardTitle()
  if leaderboardTitle == nil then return end
  local settling = isLeaderboardSettling()
  setRaceText(leaderboardTitle, "")
  local renderer = leaderboardTitle.gameObject:GetComponent(typeof(UnityEngine.Renderer))
  if renderer ~= nil then renderer.enabled = false end
  local item = leaderboardCjkObjects["本场排行榜"]
  if item ~= nil and item.object ~= nil and item.renderer ~= nil then
    item.object.transform.localPosition = Vector3(0, 0.70, -0.012)
    local material = getLeaderboardCjkMaterial(0)
    if material ~= nil then item.renderer.sharedMaterial = material end
    item.renderer.enabled = leaderboardVisible and not settling
  end
end

local function renderLeaderboardRows(serializedRows)
  if leaderboardBody == nil then return end
  setRaceText(leaderboardBody, "")
  local bodyRenderer = leaderboardBody.gameObject:GetComponent(typeof(UnityEngine.Renderer))
  if bodyRenderer ~= nil then bodyRenderer.enabled = false end
  hideLeaderboardRows()
  hideLeaderboardCjkNames()
  local value = tostring(serializedRows or "")
  if value == LEADERBOARD_SETTLING_TEXT then
    local item = leaderboardCjkObjects[LEADERBOARD_SETTLING_TEXT]
    if item ~= nil and item.object ~= nil and item.renderer ~= nil then
      item.object.transform.localPosition = Vector3(0, LEADERBOARD_SETTLING_CJK_Y, -0.012)
      local material = getLeaderboardCjkMaterial(4)
      if material ~= nil then item.renderer.sharedMaterial = material end
      item.renderer.enabled = leaderboardVisible
    end
    return
  end
  if value == "" or value == "NO FINISHERS" then
    local row = leaderboardRows[1]
    if row ~= nil then
      row.text.color = leaderboardRankColor(4)
      setRaceText(row.text, value)
      if row.renderer ~= nil then row.renderer.enabled = leaderboardVisible end
    end
    return
  end
  local rowIndex = 0
  for line in string.gmatch(value .. "\n", "([^\n]*)\n") do
    if line ~= "" and rowIndex < LEADERBOARD_MAX_ROWS then
      local rank, vehicleName, timeText = string.match(line, "^(#%d+)|([^|]+)|(.+)$")
      if rank ~= nil and vehicleName ~= nil and timeText ~= nil then
        rowIndex = rowIndex + 1
        local aliasKey = string.upper(tostring(vehicleName or ""))
        vehicleName = roomClock.leaderboardVehicleNameAliases[aliasKey] or vehicleName
        local item = leaderboardCjkObjects[vehicleName]
        local hasCjkBitmap = item ~= nil and item.object ~= nil and item.renderer ~= nil
        local rowVehicleText = ""
        if not hasCjkBitmap then
          local fleetEntry = roomClock.fleetByRootName[vehicleName]
          rowVehicleText = fleetEntry ~= nil and tostring(fleetEntry.displayName or "") or ""
          if rowVehicleText == "" then rowVehicleText = tostring(vehicleName or "UNKNOWN") end
          rowVehicleText = "  " .. rowVehicleText .. "  "
        end
        local row = leaderboardRows[rowIndex]
        if row ~= nil then
          row.text.color = leaderboardRankColor(rowIndex)
          setRaceText(row.text, rank .. rowVehicleText .. LEADERBOARD_ROW_COLUMN_GAP .. timeText)
          if row.renderer ~= nil then row.renderer.enabled = leaderboardVisible end
        end
        if hasCjkBitmap then
          item.object.transform.localPosition = Vector3(
            0,
            -(rowIndex - 1) * LEADERBOARD_ROW_PITCH + LEADERBOARD_CJK_Y_OFFSET,
            -0.012
          )
          local rankMaterial = getLeaderboardCjkMaterial(rowIndex)
          if rankMaterial ~= nil then item.renderer.sharedMaterial = rankMaterial end
          item.renderer.enabled = leaderboardVisible
        end
      end
    end
  end
end

local function styleRacePhasePanel(root)
  if root == nil then return end
  local renderer = root.gameObject:GetComponent(typeof(UnityEngine.Renderer))
  if renderer ~= nil then
    local objectName = tostring(root.name)
    local function applyMaterialColor(material, color)
      if material == nil then return end
      material.color = color
      pcall(function()
        material:EnableKeyword("_EMISSION")
        material:SetColor("_EmissionColor", color * 1.8)
      end)
    end
    if string.find(objectName, "Race_Phase_", 1, true) == 1 then
      local materials = renderer.materials
      for i = 0, materials.Length - 1 do
        applyMaterialColor(materials[i], i == 0
          and UnityEngine.Color(0.06, 0.92, 1.0, 1.0)
          or UnityEngine.Color(1.0, 0.08, 0.72, 1.0))
      end
    end
  end
  for i = 0, root.childCount - 1 do styleRacePhasePanel(root:GetChild(i)) end
end

local function createRaceText(parent)
  if parent == nil then return nil end
  local existing = findDescendant(parent, "Race_Countdown_Text")
  if existing ~= nil then
    local existingText = existing.gameObject:GetComponent(typeof(UnityEngine.TextMesh))
    if existingText ~= nil then
      pcall(function()
        if tostring(existingText.text or "") == "" then existingText.text = "--:--" end
      end)
      return existingText
    end
  end
  local object = UnityEngine.GameObject("Race_Countdown_Text")
  object.transform:SetParent(parent, false)
  object.transform.localPosition = Vector3(0, -0.10, 0.045)
  object.transform.localRotation = Quaternion.Euler(0, 180, 0)
  object.transform.localScale = Vector3.one
  local textMesh = object:AddComponent(typeof(UnityEngine.TextMesh))
  textMesh.text = "--:--"
  textMesh.fontSize = 96
  textMesh.characterSize = 0.05
  textMesh.anchor = UnityEngine.TextAnchor.MiddleCenter
  textMesh.alignment = UnityEngine.TextAlignment.Center
  textMesh.color = UnityEngine.Color.white
  pcall(function()
    local font = UnityEngine.Font.CreateDynamicFontFromOSFont("Microsoft YaHei UI", 96)
    if font ~= nil then
      textMesh.font = font
      local renderer = object:GetComponent(typeof(UnityEngine.MeshRenderer))
      if renderer ~= nil then renderer.sharedMaterial = font.material end
    end
  end)
  return textMesh
end

local function setupRaceDisplayInstance(displayObjectName, vectorLayerName)
  local displayObject = UnityEngine.GameObject.Find(displayObjectName)
  if displayObject == nil then return nil, nil, {} end
  local displayRoot = displayObject.transform
  local uiAnchor = findDescendant(displayRoot, "Countdown_UIAnchor")
  if uiAnchor == nil then return displayRoot, nil, {} end
  local textOk, countdownText = pcall(function() return createRaceText(uiAnchor) end)
  if not textOk or countdownText == nil then
    roomClock.reportSubsystemError(displayObjectName .. " countdown text", countdownText)
    return displayRoot, nil, {}
  end
  roomClock.clearSubsystemError(displayObjectName .. " countdown text")
  local isSmallBoard = string.find(displayObjectName, "小看板", 1, true) == 1
  if isSmallBoard then disableAllColliders(displayRoot) end
  -- Hide the prebuilt placeholders only after a usable countdown text exists.
  -- A mobile-only TextMesh failure can therefore never leave a blank board.
  visitDescendants(uiAnchor, function(trans)
    local name = tostring(trans.name)
    if string.find(name, "Countdown_Digit_", 1, true) == 1
      or string.find(name, "Countdown_Colon", 1, true) == 1 then
      setRendererVisible(trans, false)
    end
  end)
  local panels = {}
  local phaseSearchRoot = displayRoot
  local vectorLayer = findDescendant(displayRoot, vectorLayerName)
  -- Small boards must resolve their own copied vector layer. A global fallback
  -- could silently bind 小看板2 to 小看板 when one copied child is renamed.
  if vectorLayer == nil and not isSmallBoard then
    local externalVectorLayer = UnityEngine.GameObject.Find(vectorLayerName)
    if externalVectorLayer ~= nil then vectorLayer = externalVectorLayer.transform end
  end
  if vectorLayer ~= nil then
    phaseSearchRoot = vectorLayer
    if isSmallBoard then disableAllColliders(vectorLayer) end
  end
  local phaseNames = { "PREPARING", "WAITING", "RACING", "RECYCLING" }
  for i = 1, #phaseNames do
    local phaseName = phaseNames[i]
    local panel = findDescendant(phaseSearchRoot, "Race_Phase_" .. phaseName)
    panels[phaseName] = panel
    pcall(styleRacePhasePanel, panel)
    setRendererVisible(panel, false)
  end
  return displayRoot, countdownText, panels
end

local function areRacePhasePanelsReady(panels)
  return panels ~= nil
    and panels.PREPARING ~= nil
    and panels.WAITING ~= nil
    and panels.RACING ~= nil
    and panels.RECYCLING ~= nil
end

local function setupRaceDisplay()
  -- GWBOARD-1: Session owns the VIS-attached Canvas presentation. Only old
  -- visual renderers are hidden; the parent contains gameplay scripts and
  -- must never be deactivated or moved.
  if roomClock.unifiedWorldBoards then
    roomClock.hideLegacyBoardRenderers()
    return
  end
  local mainOk, mainRoot, mainText, mainPanels = roomClock.runSafely("main race display", function()
    return setupRaceDisplayInstance("RaceManager_Display", "RaceManager_中文字层")
  end)
  if mainOk then
    raceDisplayRoot = mainRoot
    raceCountdownText = mainText
    racePhasePanels = mainPanels or {}
  end
  local smallOk, smallRoot, smallText, smallPanels = roomClock.runSafely("small race display", function()
    return setupRaceDisplayInstance("小看板", "小看板_中文字层")
  end)
  if smallOk then
    smallRaceDisplayRoot = smallRoot
    smallRaceCountdownText = smallText
    smallRacePhasePanels = smallPanels or {}
  end
  local small2Ok, smallRoot2, smallText2, smallPanels2 = roomClock.runSafely("small race display 2", function()
    return setupRaceDisplayInstance("小看板2", "小看板_中文字层")
  end)
  if small2Ok then
    smallRaceDisplayRoot2 = smallRoot2
    smallRaceCountdownText2 = smallText2
    smallRacePhasePanels2 = smallPanels2 or {}
  end
end

local function setupFinishLine()
  local finishObject = UnityEngine.GameObject.Find("终点线")
  if finishObject == nil then
    finishLineRoot = nil
    return false
  end
  finishLineRoot = finishObject.transform
  disableAllColliders(finishLineRoot)
  styleFinishLine(finishLineRoot)
  return true
end

local function setupLeaderboard()
  if roomClock.unifiedWorldBoards then
    roomClock.hideLegacyBoardRenderers()
    return true
  end
  local boardObject = UnityEngine.GameObject.Find("透明排名板")
  if boardObject == nil then
    leaderboardRoot = nil
    leaderboardTitle = nil
    leaderboardBody = nil
    leaderboardRows = {}
    leaderboardCjkObjects = {}
    return false
  end
  leaderboardRoot = boardObject.transform
  disableAllColliders(leaderboardRoot)
  styleLeaderboardPanel(leaderboardRoot)
  leaderboardTitle = createLeaderboardText(
    leaderboardRoot,
    "Race_Leaderboard_Title",
    0.37,
    LEADERBOARD_TITLE_CHARACTER_SIZE,
    Color(0.1, 0.95, 1.0, 1.0),
    UnityEngine.TextAnchor.MiddleCenter
  )
  leaderboardBody = createLeaderboardText(
    leaderboardRoot,
    "Race_Leaderboard_Body",
    0.22,
    LEADERBOARD_ROW_CHARACTER_SIZE,
    Color(0.94, 0.99, 1.0, 1.0),
    UnityEngine.TextAnchor.MiddleCenter
  )
  setupLeaderboardRows()
  setupLeaderboardCjkNames()
  setRendererVisible(leaderboardRoot, leaderboardVisible)
  if leaderboardVisible then renderLeaderboardRows(leaderboardText)
  else
    hideLeaderboardRows()
    hideLeaderboardCjkNames()
  end
  updateLeaderboardTitle()
  return leaderboardTitle ~= nil
    and leaderboardBody ~= nil
    and #leaderboardRows == LEADERBOARD_MAX_ROWS
end

local function vectorCopy(value)
  if value == nil then return Vector3.zero end
  return Vector3(value.x, value.y, value.z)
end

local function addGateBoxCollider(target, center, size)
  if target == nil then return nil end
  local existing = target.gameObject:GetComponents(typeof(UnityEngine.BoxCollider))
  for i = 0, existing.Length - 1 do
    local candidate = existing[i]
    if candidate ~= nil
      and Vector3.Distance(candidate.center, center) < 0.001
      and Vector3.Distance(candidate.size, size) < 0.001 then
      candidate.isTrigger = false
      candidate.enabled = true
      return candidate
    end
  end
  local collider = target.gameObject:AddComponent(typeof(UnityEngine.BoxCollider))
  collider.isTrigger = false
  collider.center = center
  collider.size = size
  collider.enabled = true
  return collider
end

local function setupRaceGate(sceneObjectName, movingName, openPointName, closedPointName)
  local sceneObject = UnityEngine.GameObject.Find(sceneObjectName)
  if sceneObject == nil then return nil end
  local moving = findDescendant(sceneObject.transform, movingName)
  local openPoint = findDescendant(sceneObject.transform, openPointName)
  local closedPoint = findDescendant(sceneObject.transform, closedPointName)
  if moving == nil or openPoint == nil or closedPoint == nil then return nil end
  local meshColliders = sceneObject:GetComponentsInChildren(typeof(UnityEngine.MeshCollider), true)
  for i = 0, meshColliders.Length - 1 do
    if meshColliders[i] ~= nil then meshColliders[i].enabled = false end
  end
  -- The imported legacy semantic root is scaled 23x. Old fixed-size boxes
  -- consequently floated above the road and spanned 152 m. Collide against
  -- each mesh's OWN local bounds instead; its transform supplies the scale.
  local panel=findDescendant(moving,"Gate_B_Moving_SeaGlass_Panel")
  local blocker=nil
  if panel~=nil then
    local filter=panel.gameObject:GetComponent(typeof(UnityEngine.MeshFilter))
    if filter~=nil and filter.sharedMesh~=nil then
      local bounds=filter.sharedMesh.bounds
      blocker=addGateBoxCollider(panel,vectorCopy(bounds.center),vectorCopy(bounds.size))
    end
  end
  local shell=UnityEngine.GameObject.Find("地心飞车_起点总成_熔核闸门")
  if shell~=nil then
    for _,name in ipairs({"PillarLeftSolid","PillarRightSolid"}) do
      local pillar=findDescendant(shell.transform,name)
      if pillar~=nil then
        local filter=pillar.gameObject:GetComponent(typeof(UnityEngine.MeshFilter))
        if filter~=nil and filter.sharedMesh~=nil then
          local bounds=filter.sharedMesh.bounds
          addGateBoxCollider(pillar,vectorCopy(bounds.center),vectorCopy(bounds.size))
        end
      end
    end
  end
  return {
    moving = moving,
    blocker = blocker,
    openPosition = vectorCopy(openPoint.localPosition),
    closedPosition = vectorCopy(closedPoint.localPosition),
    isOpen = nil,
  }
end

local function setRaceGateOpen(gate, shouldOpen)
  if gate == nil or gate.moving == nil then return end
  if gate.isOpen == shouldOpen then return end
  gate.moving.localPosition = shouldOpen and gate.openPosition or gate.closedPosition
  if gate.blocker~=nil then gate.blocker.enabled=not shouldOpen end
  gate.isOpen = shouldOpen
end

local function setupRaceScene()
  roomClock.runSafely("race displays", setupRaceDisplay)
  local gateBOk, gateB = roomClock.runSafely("gate B setup", function()
    return setupRaceGate("B门", "Gate_B_MovingBlockerPivot", "Gate_B_OpenPoint", "Gate_B_ClosedPoint")
  end)
  if gateBOk then raceGateB = gateB end
  roomClock.runSafely("finish line setup", setupFinishLine)
  roomClock.runSafely("leaderboard setup", setupLeaderboard)
end

setRaceText = function(textMesh, value)
  if textMesh == nil then return end
  pcall(function()
    if textMesh.font ~= nil then
      textMesh.font:RequestCharactersInTexture(LEADERBOARD_GLYPH_WARMUP, textMesh.fontSize, UnityEngine.FontStyle.Normal)
      textMesh.font:RequestCharactersInTexture(value, textMesh.fontSize, UnityEngine.FontStyle.Normal)
    end
    textMesh.text = value
  end)
end

local function updateRaceDisplayInstance(countdownText, phasePanels, stateName, formattedCountdown)
  setRaceText(countdownText, formattedCountdown)
  for phaseName, panel in pairs(phasePanels or {}) do
    pcall(setRendererVisible, panel, phaseName == stateName)
  end
end

local function updateRaceDisplay(stateName, secondsRemaining)
  local seconds = math.max(0, math.ceil(secondsRemaining))
  if seconds == raceLastDisplayedSecond and stateName == raceState then return end
  raceLastDisplayedSecond = seconds
  local formattedCountdown = string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
  updateRaceDisplayInstance(raceCountdownText, racePhasePanels, stateName, formattedCountdown)
  updateRaceDisplayInstance(smallRaceCountdownText, smallRacePhasePanels, stateName, formattedCountdown)
  updateRaceDisplayInstance(smallRaceCountdownText2, smallRacePhasePanels2, stateName, formattedCountdown)
end

local function renderRaceState(stateName)
  -- Every client renders the physical course from the same server timestamp.
  -- A result-ledger snapshot may arrive a little later for a late joiner, but
  -- that must never create a private gate state on that client. The ledger only
  -- gates official result commits. Even a client that slept through a reset
  -- window must render the same B gate as the rest of the room. Vehicle reset is
  -- performed by each vehicle's unique network owner, not by a client-local
  -- copy of race state.
  local clockReady = raceClockNowUnixMilliseconds ~= nil
  setRaceGateOpen(raceGateB, clockReady and stateName == "RACING")
end

local function showClockUnavailable()
  roomClock.runSafely("closed gates while synchronizing", function() renderRaceState(nil) end)
  raceLastDisplayedSecond = -1
  setRaceText(raceCountdownText, "--:--")
  setRaceText(smallRaceCountdownText, "--:--")
  setRaceText(smallRaceCountdownText2, "--:--")
  for _, panel in pairs(racePhasePanels) do pcall(setRendererVisible, panel, false) end
  for _, panel in pairs(smallRacePhasePanels) do pcall(setRendererVisible, panel, false) end
  for _, panel in pairs(smallRacePhasePanels2) do pcall(setRendererVisible, panel, false) end
end

local function isAuthoritativeManager()
  return raceClockNowUnixMilliseconds ~= nil and roomClock.hasAuthority()
end

-- Presentation is retryable and must never abort an already committed result.
-- A transient font/model readiness failure cannot permanently hide the board.
roomClock.leaderboardPresentationDirty = false
roomClock.leaderboardPresentationRetryAt = -math.huge
roomClock.unifiedWorldBoards = true
function roomClock.hideLegacyBoardRenderers()
  for _, name in ipairs({"RaceManager_Display", "RaceManager_中文字层", "小看板", "小看板2", "透明排名板"}) do
    local object = UnityEngine.GameObject.Find(name)
    if object ~= nil then
      setRendererVisible(object.transform, false)
      -- Preserve the former display setup's non-physical carrier contract.
      if name == "小看板" or name == "小看板2" or name == "透明排名板" then
        disableAllColliders(object.transform)
      end
    end
  end
end
function roomClock.presentLeaderboard()
  if roomClock.unifiedWorldBoards then
    roomClock.leaderboardPresentationDirty = false
    return true -- Session consumes the same authority state on its UI tick.
  end
  local ok, rendered = roomClock.runSafely("world leaderboard presentation", function()
    if leaderboardRoot == nil or leaderboardTitle == nil or leaderboardBody == nil
      or #leaderboardRows ~= LEADERBOARD_MAX_ROWS then
      if not setupLeaderboard() then return false end
    end
    if leaderboardVisible then styleLeaderboardPanel(leaderboardRoot) end
    setRendererVisible(leaderboardRoot, leaderboardVisible)
    if leaderboardVisible then renderLeaderboardRows(leaderboardText)
    else
      hideLeaderboardRows()
      hideLeaderboardCjkNames()
    end
    updateLeaderboardTitle()
    return true
  end)
  roomClock.leaderboardPresentationDirty = not ok or rendered ~= true
  roomClock.leaderboardPresentationRetryAt = Time.time + 0.5
  return not roomClock.leaderboardPresentationDirty
end

local function applyLeaderboardSnapshot(sourceCycleId, version, visibleValue, finalValue, textValue)
  local source = math.max(0, math.floor(tonumber(sourceCycleId) or 0))
  local nextVersion = math.max(0, math.floor(tonumber(version) or 0))
  if source < leaderboardAppliedCycleId then return false end
  if source == leaderboardAppliedCycleId and nextVersion < leaderboardAppliedVersion then return false end
  if source == leaderboardAppliedCycleId and nextVersion == leaderboardAppliedVersion then
    if leaderboardVisible ~= (tonumber(visibleValue) == 1 or visibleValue == true)
      or leaderboardFinal ~= (tonumber(finalValue) == 1 or finalValue == true)
      or leaderboardText ~= tostring(textValue or "") then return false end
    if roomClock.leaderboardPresentationDirty then roomClock.presentLeaderboard() end
    return true
  end
  leaderboardAppliedCycleId = source
  leaderboardAppliedVersion = nextVersion
  leaderboardSourceCycleId = source
  leaderboardVersion = math.max(leaderboardVersion, nextVersion)
  leaderboardVisible = tonumber(visibleValue) == 1 or visibleValue == true
  leaderboardFinal = tonumber(finalValue) == 1 or finalValue == true
  leaderboardText = tostring(textValue or "")
  roomClock.leaderboardPresentationDirty = true
  roomClock.presentLeaderboard()
  return true
end

function RaceManagerApplyLeaderboard(sourceCycleId, version, visibleValue, finalValue, textValue)
  return applyLeaderboardSnapshot(sourceCycleId, version, visibleValue, finalValue, textValue)
end

function RaceManagerApplyFinishRecord(sourceCycleId, vehicleName, elapsedMilliseconds, sequence)
  -- Legacy event retained only so delayed messages from an older script build
  -- fail harmlessly. The single varSync ledger below is the sole result truth.
  return false
end

local function parseRaceLedgerPayload(payload)
  local parts = {}
  for value in string.gmatch(tostring(payload or ""), "([^|]+)") do
    parts[#parts + 1] = value
  end
  if #parts ~= 3 + #fleet * 2 or parts[1] ~= "R1" then return nil end
  local cycleId = math.floor(tonumber(parts[2]) or -1)
  local revision = math.floor(tonumber(parts[3]) or -1)
  if cycleId < 2 or revision < 1
    or math.floor(cycleId / SCHEDULE_TOKEN_STRIDE) ~= SCHEDULE_REVISION then return nil end
  local records = {}
  local cursor = 4
  for i = 1, #fleet do
    local elapsedMs = math.floor(tonumber(parts[cursor]) or -2)
    local sequence = math.floor(tonumber(parts[cursor + 1]) or -1)
    cursor = cursor + 2
    if elapsedMs >= 0 then
      if elapsedMs >= RACING_SECONDS * 1000 or sequence < 1 then return nil end
      records[fleet[i].rootName] = {
        vehicleName = fleet[i].rootName,
        elapsedMs = elapsedMs,
        finishSequence = sequence,
        cycleId = cycleId,
      }
    elseif elapsedMs ~= -1 then
      return nil
    end
  end
  return { cycleId = cycleId, revision = revision, records = records }
end

local function buildRaceLedgerPayload(cycleId, revision, records)
  local parts = { "R1", tostring(cycleId), tostring(revision) }
  for i = 1, #fleet do
    local record = records[fleet[i].rootName]
    if record == nil then
      parts[#parts + 1] = "-1"
      parts[#parts + 1] = "0"
    else
      parts[#parts + 1] = tostring(math.floor(record.elapsedMs))
      parts[#parts + 1] = tostring(math.max(1, math.floor(record.finishSequence or i)))
    end
  end
  return table.concat(parts, "|")
end

local function applyRaceLedgerPayload(payload)
  local normalizedPayload = tostring(payload or "")
  local parsed = parseRaceLedgerPayload(payload)
  if parsed == nil then return false end
  if parsed.cycleId < raceLedgerCycleId
    or (parsed.cycleId == raceLedgerCycleId and parsed.revision < raceLedgerRevision) then return false end
  if parsed.cycleId == raceLedgerCycleId and parsed.revision == raceLedgerRevision then
    if raceLedgerLastPayload ~= "" and normalizedPayload ~= raceLedgerLastPayload then
      raceLedgerReadyForCurrentCycle = false
      UnityEngine.Debug.LogError("RaceManager: synchronized ledger split-brain detected")
      return false
    end
    return raceLedgerLastPayload ~= ""
  end
  raceLedgerCycleId = parsed.cycleId
  raceLedgerRevision = parsed.revision
  raceLedgerLastPayload = normalizedPayload
  replicatedFinishLedger[parsed.cycleId] = parsed.records
  if raceInitializedCycleId == parsed.cycleId then
    finishRecords = {}
    finishSequence = 0
    for name, record in pairs(parsed.records) do
      finishRecords[name] = {
        vehicleName = record.vehicleName,
        elapsedMs = record.elapsedMs,
        finishSequence = record.finishSequence,
        cycleId = record.cycleId,
      }
      pendingFinishCrossings[name] = nil
      finishSequence = math.max(finishSequence, record.finishSequence)
    end
    raceLedgerReadyForCurrentCycle = true
    if finishSequence > 0 then leaderboardSettlingCycleId = parsed.cycleId end
    -- Hydration may enable official result commits after a late join. Gate
    -- positions themselves are already derived exclusively from server time.
    if raceState ~= nil then renderRaceState(raceState) end
    if raceState == "RACING" and finishSequence > 0 then
      applyLeaderboardSnapshot(
        parsed.cycleId,
        math.max(leaderboardVersion + 1, parsed.revision * 10 + 1),
        1,
        0,
        LEADERBOARD_SETTLING_TEXT
      )
    elseif raceState == "RECYCLING" and buildLeaderboardText ~= nil then
      applyLeaderboardSnapshot(
        parsed.cycleId,
        math.max(leaderboardVersion + 1, parsed.revision * 10 + 2),
        1,
        1,
        buildLeaderboardText(finishRecords)
      )
    end
  elseif raceState == "PREPARING" and parsed.cycleId == raceCycleId - 1
    and restorePreviousFinalLeaderboard ~= nil then
    restorePreviousFinalLeaderboard()
  end
  leaderboardVersion = math.max(leaderboardVersion, parsed.revision * 10)
  return true
end

local function hydrateRaceLedger()
  if raceResultLedger == nil then return false end
  local ok, payload = pcall(function() return raceResultLedger:GetValue() end)
  if not ok then return false end
  return applyRaceLedgerPayload(payload)
end

local function cloneFinishRecords(records)
  local result = {}
  for name, record in pairs(records or {}) do
    result[name] = {
      vehicleName = record.vehicleName,
      elapsedMs = record.elapsedMs,
      finishSequence = record.finishSequence,
      cycleId = record.cycleId,
    }
  end
  return result
end

local function maxFinishRecordSequence(records)
  local maximum = 0
  for _, record in pairs(records or {}) do
    maximum = math.max(maximum, math.floor(tonumber(record.finishSequence) or 0))
  end
  return maximum
end

local function readRaceLedgerSnapshot()
  if raceResultLedger == nil then return nil, "" end
  local ok, payload = pcall(function() return raceResultLedger:GetValue() end)
  if not ok then return nil, "" end
  local normalized = tostring(payload or "")
  local parsed = parseRaceLedgerPayload(normalized)
  if parsed ~= nil then applyRaceLedgerPayload(normalized) end
  return parsed, normalized
end

local function commitRaceLedger(records, expectedPayload)
  if not isAuthoritativeManager() or raceResultLedger == nil or raceCycleId < 2 then return false end

  -- Re-read the atomic synchronized snapshot immediately before every write.
  -- This prevents an owner with stale local records from replacing a newer
  -- finish that arrived during an ownership transition.
  local latest, latestPayload = readRaceLedgerSnapshot()
  if expectedPayload ~= nil and latestPayload ~= tostring(expectedPayload) then return false end
  if latest ~= nil and latest.cycleId > raceCycleId then return false end
  if latest ~= nil and latest.cycleId == raceCycleId then
    -- Existing-cycle writes must be based on the complete latest snapshot.
    for name, record in pairs(latest.records) do
      if records[name] == nil then records[name] = record end
    end
  elseif raceState ~= "WAITING" or raceObservedPreparingCycleId ~= raceCycleId then
    -- Only a client that observed this cycle's PREPARING may initialize its
    -- empty ledger at WAITING. Never infer "fresh room" from an empty value in
    -- RACING: a late owner may still be receiving the authoritative snapshot.
    return false
  end

  local revision = math.max(raceLedgerRevision, latest ~= nil and latest.revision or 0) + 1
  local payload = buildRaceLedgerPayload(raceCycleId, revision, records)
  local stillOwner = false
  pcall(function() stillOwner = self:HasOwnership() end)
  if not stillOwner then return false end
  local ok = pcall(function() raceResultLedger:SetValue(payload) end)
  if not ok then
    UnityEngine.Debug.LogError("RaceManager: failed to commit synchronized result ledger")
    return false
  end
  local verified = false
  pcall(function() verified = tostring(raceResultLedger:GetValue() or "") == payload end)
  if not verified then
    UnityEngine.Debug.LogError("RaceManager: synchronized result ledger verification failed")
    return false
  end
  applyRaceLedgerPayload(payload)
  raceLedgerReadyForCurrentCycle = true
  return true
end

local function ensureRaceLedgerForCurrentCycle()
  local latest, latestPayload = readRaceLedgerSnapshot()
  if raceLedgerCycleId == raceCycleId and raceLedgerReadyForCurrentCycle then return true end
  if latest ~= nil and latest.cycleId == raceCycleId then return false end
  if not isAuthoritativeManager() then return false end
  -- Keep the previous cycle's atomic result snapshot throughout PREPARING so a
  -- late join can still reconstruct the final board. Initialize the new empty
  -- ledger exactly at PREPARING -> WAITING, and only if PREPARING was observed.
  if raceState ~= "WAITING" or raceObservedPreparingCycleId ~= raceCycleId then return false end
  if latest ~= nil and latest.cycleId > raceCycleId then return false end
  local emptyRecords = {}
  return commitRaceLedger(emptyRecords, latestPayload)
end

local function broadcastLeaderboardSnapshot()
  applyLeaderboardSnapshot(
    leaderboardSourceCycleId,
    leaderboardVersion,
    leaderboardVisible and 1 or 0,
    leaderboardFinal and 1 or 0,
    leaderboardText
  )
  local networkSettled = DouyinNetService ~= nil and DouyinNetService.isNetworkSettled
  if not networkSettled or not isAuthoritativeManager() then return end
  self:SendMessageToAll(
    "RaceManagerApplyLeaderboard",
    leaderboardSourceCycleId,
    leaderboardVersion,
    leaderboardVisible and 1 or 0,
    leaderboardFinal and 1 or 0,
    leaderboardText
  )
end

local function publishLeaderboard(visible, finalFlag, textValue, sourceCycleId)
  if not isAuthoritativeManager() then return end
  leaderboardSourceCycleId = math.max(0, math.floor(tonumber(sourceCycleId) or raceCycleId))
  local phaseVersion = raceLedgerRevision * 10 + (finalFlag == true and 2 or 1)
  leaderboardVersion = math.max(leaderboardVersion + 1, phaseVersion)
  leaderboardVisible = visible == true
  leaderboardFinal = finalFlag == true
  leaderboardText = tostring(textValue or "")
  -- Apply before sending so the owner and offline preview use exactly the same
  -- snapshot as remote clients.
  leaderboardAppliedCycleId = 0
  leaderboardAppliedVersion = 0
  broadcastLeaderboardSnapshot()
  leaderboardResendAt = Time.time + 1.0
end

local function finishSide(localZ)
  if localZ > FINISH_SIDE_EPSILON then return 1 end
  if localZ < -FINISH_SIDE_EPSILON then return -1 end
  return 0
end

local function reseedFinishTrackers(sampledAtUnixMilliseconds)
  finishTrackers = {}
  local sampledAt = tonumber(sampledAtUnixMilliseconds)
    or raceClockNowUnixMilliseconds
    or raceScheduledStartUnixMilliseconds
    or 0
  if finishLineRoot == nil then setupFinishLine() end
  if finishLineRoot == nil then return false end
  for i = 1, #fleet do
    local entry = fleet[i]
    if finishRecords[entry.rootName] == nil then
      local vehicleTransform = roomClock.getFinishVehicleTransform(entry.rootName)
      if vehicleTransform ~= nil then
        local worldPosition = vehicleTransform.position
        local localPosition = finishLineRoot:InverseTransformPoint(worldPosition)
        finishTrackers[entry.rootName] = {
          side = finishSide(localPosition.z),
          localPosition = Vector3(localPosition.x, localPosition.y, localPosition.z),
          worldPosition = Vector3(worldPosition.x, worldPosition.y, worldPosition.z),
          serverUnixMilliseconds = sampledAt,
        }
      end
    end
  end
  raceLastCrossingSampleUnixMilliseconds = sampledAt
  return true
end

local function beginRaceCycle(cycleId)
  local normalized = math.floor(tonumber(cycleId) or 0)
  if normalized <= 0 or raceInitializedCycleId == normalized then return false end
  raceInitializedCycleId = normalized
  raceTimingCycleId = 0
  raceStartAt = nil
  raceStartUnixMilliseconds = nil
  finishTrackers = {}
  raceLastCrossingSampleUnixMilliseconds = nil
  raceFinishTrackerNeedsReseed = true
  finishRecords = {}
  finishSequence = 0
  pendingFinishCrossings = {}
  raceLedgerReadyForCurrentCycle = false
  local validatorObject = UnityEngine.GameObject.Find("RaceManager")
  if validatorObject ~= nil then
    local holderOk, validatorHolder = pcall(function()
      return validatorObject:GetDouyinScript("4fd23b49-42c5-4e32-9c41-7f364db2a421")
    end)
    if holderOk and validatorHolder ~= nil and validatorHolder.script ~= nil then
      pcall(function() validatorHolder.script.RaceRouteValidatorBeginCycle(normalized) end)
    end
  end
  local cachedRecords = replicatedFinishLedger[normalized]
  if cachedRecords ~= nil then
    for name, record in pairs(cachedRecords) do
      finishRecords[name] = {
        vehicleName = record.vehicleName,
        elapsedMs = record.elapsedMs,
        finishSequence = record.finishSequence,
        cycleId = record.cycleId,
      }
      finishSequence = math.max(finishSequence, record.finishSequence)
    end
    raceLedgerReadyForCurrentCycle = true
  end
  for sourceCycleId, _ in pairs(replicatedFinishLedger) do
    if sourceCycleId < normalized - 1 then replicatedFinishLedger[sourceCycleId] = nil end
  end
  leaderboardSettlingCycleId = 0
  if finishSequence > 0 then leaderboardSettlingCycleId = normalized end
  return true
end

local function beginRaceTiming(startedAtUnixMilliseconds, sampledAtUnixMilliseconds)
  if raceTimingCycleId == raceCycleId and raceStartUnixMilliseconds ~= nil then return true end
  local scheduledStart = tonumber(startedAtUnixMilliseconds)
  if scheduledStart == nil then return false end
  raceTimingCycleId = raceCycleId
  raceStartUnixMilliseconds = scheduledStart
  -- Compatibility getter retained, but its domain is now Unix seconds rather
  -- than client-local Time.time.
  raceStartAt = scheduledStart / 1000
  finishTrackers = {}
  local sampledAt = tonumber(sampledAtUnixMilliseconds)
    or raceClockNowUnixMilliseconds
    or scheduledStart
  local validator = roomClock.getRouteValidator()
  if validator ~= nil and validator.script.RaceRouteValidatorBeginRace ~= nil then
    validator.script.RaceRouteValidatorBeginRace(raceCycleId, sampledAt)
  end
  raceFinishTrackerNeedsReseed = false
  UnityEngine.Debug.Log(
    "RaceManager: cycleId=" .. tostring(raceCycleId)
      .. " scheduled B-open UnixMs=" .. string.format("%.0f", raceStartUnixMilliseconds)
  )
  return true
end

local function recordVehicleFinish(entry, crossedAtUnixMilliseconds)
  local retryingCapturedFinish = raceState == "RECYCLING"
    and pendingFinishCrossings[entry.rootName] ~= nil
  if (raceState ~= "RACING" and not retryingCapturedFinish)
    or raceStartUnixMilliseconds == nil
    or raceTimingCycleId ~= raceCycleId then return false end
  local crossedAt = tonumber(crossedAtUnixMilliseconds)
  if crossedAt == nil then return false end
  local raceEnd = raceStartUnixMilliseconds + RACING_SECONDS * 1000
  -- RACING is a half-open interval. A crossing exactly at the end boundary
  -- belongs to neither this result set nor the following recycling stage.
  if crossedAt < raceStartUnixMilliseconds or crossedAt >= raceEnd then return false end

  if finishRecords[entry.rootName] ~= nil then
    pendingFinishCrossings[entry.rootName] = nil
    return false
  end
  if not roomClock.raceVehicleParticipating(entry.rootName) then
    pendingFinishCrossings[entry.rootName] = nil
    return false
  end
  -- Only an ordered start -> check -> painted finish candidate is eligible.
  local validatorHolder = roomClock.getRouteValidator()
  if validatorHolder == nil then return false end
  local eligibleOk, eligible = pcall(function()
    return validatorHolder.script.RaceRouteValidatorIsEligible(entry.rootName, raceCycleId)
  end)
  if not eligibleOk or eligible ~= true then
    pendingFinishCrossings[entry.rootName] = nil
    return false
  end
  -- Every client may observe the geometric crossing, but only the current
  -- RaceManager owner can commit it. Keeping the earliest local candidate also
  -- covers a transfer that happens between crossing detection and SetValue.
  local pending = pendingFinishCrossings[entry.rootName]
  if pending == nil or crossedAt < pending then pendingFinishCrossings[entry.rootName] = crossedAt end
  if not isAuthoritativeManager() then return false end

  local latest, latestPayload = readRaceLedgerSnapshot()
  if latest == nil or latest.cycleId ~= raceCycleId then return false end
  if latest.records[entry.rootName] ~= nil then
    pendingFinishCrossings[entry.rootName] = nil
    applyRaceLedgerPayload(latestPayload)
    return false
  end

  local records = cloneFinishRecords(latest.records)
  -- Keep every accepted half-open-window crossing representable in the ledger.
  -- Rounding 149999.8 to 150000 previously made a valid last-frame finish fail.
  local elapsedMs = math.min(math.floor(RACING_SECONDS * 1000) - 1,
    math.max(0, math.floor(pendingFinishCrossings[entry.rootName] - raceStartUnixMilliseconds + 0.5)))
  local nextSequence = maxFinishRecordSequence(records) + 1
  records[entry.rootName] = {
    vehicleName = entry.rootName,
    elapsedMs = elapsedMs,
    finishSequence = nextSequence,
    cycleId = raceCycleId,
  }
  if not commitRaceLedger(records, latestPayload) then return false end
  pcall(function()
    validatorHolder.script.RaceRouteValidatorConsumeFinish(entry.rootName, raceCycleId)
  end)
  pendingFinishCrossings[entry.rootName] = nil
  UnityEngine.Debug.Log(
    "RaceManager: cycleId=" .. tostring(raceCycleId)
      .. ", finish=" .. tostring(entry.rootName)
      .. ", time=" .. string.format("%.3f", elapsedMs / 1000) .. "s"
  )
  -- commitRaceLedger hydrates the result and already sets the settling marker.
  -- Testing that marker here suppressed the first explicit room broadcast.
  -- Result-ledger duplicate guards above make this accepted first finish unique.
  if nextSequence == 1 then
    leaderboardSettlingCycleId = raceCycleId
    publishLeaderboard(true, false, LEADERBOARD_SETTLING_TEXT, raceCycleId)
  end
  return true
end

local function retryPendingFinishRecords()
  if not isAuthoritativeManager() then return end
  for i = 1, #fleet do
    local entry = fleet[i]
    local pending = pendingFinishCrossings[entry.rootName]
    if pending ~= nil and finishRecords[entry.rootName] == nil then
      recordVehicleFinish(entry, pending)
    end
  end
end

local function updateFinishCrossings(sampledAtUnixMilliseconds)
  local sampledAt = tonumber(sampledAtUnixMilliseconds) or raceClockNowUnixMilliseconds
  if raceState ~= "RACING" or not isAuthoritativeManager()
    or raceStartUnixMilliseconds == nil or sampledAt == nil then return end
  local validator = roomClock.getRouteValidator()
  if validator == nil or validator.script.RaceRouteValidatorSample == nil then
    roomClock.reportSubsystemError("three-line validator", "route validator endpoint missing")
    return
  end
  local api = validator.script
  -- Initialization is idempotent and retryable when scripts load out of order.
  if api.RaceRouteValidatorBeginRace(raceCycleId, sampledAt) ~= true then return end
  if api.RaceRouteValidatorSample(raceCycleId, sampledAt, raceStartUnixMilliseconds,
    raceStartUnixMilliseconds + RACING_SECONDS * 1000) ~= true then return end
  raceLastCrossingSampleUnixMilliseconds = sampledAt
  raceFinishTrackerNeedsReseed = false
  retryPendingFinishRecords()
  for i = 1, #fleet do
    local entry = fleet[i]
    if finishRecords[entry.rootName] == nil then
      local crossedAt = tonumber(api.GetRaceRouteVehicleFinishUnixMilliseconds(entry.rootName, raceCycleId))
      if crossedAt ~= nil and crossedAt >= 0 then recordVehicleFinish(entry, crossedAt) end
    end
  end
end

local function sortedFinishRecords(sourceRecords)
  local records = {}
  for _, record in pairs(sourceRecords or finishRecords) do records[#records + 1] = record end
  table.sort(records, function(left, right)
    if left.elapsedMs ~= right.elapsedMs then return left.elapsedMs < right.elapsedMs end
    if left.finishSequence ~= right.finishSequence then return left.finishSequence < right.finishSequence end
    return tostring(left.vehicleName) < tostring(right.vehicleName)
  end)
  return records
end

buildLeaderboardText = function(sourceRecords)
  local records = sortedFinishRecords(sourceRecords)
  if #records == 0 then return "NO FINISHERS" end
  local rows, rank = {}, 0
  for i = 1, math.min(10, #records) do
    local record = records[i]
    if i == 1 or record.elapsedMs ~= records[i - 1].elapsedMs then rank = i end
    rows[#rows + 1] = string.format(
      "#%02d|%s|%.3fs",
      rank,
      roomClock.raceRosterLabel(record.vehicleName),
      record.elapsedMs / 1000
    )
  end
  return table.concat(rows, "\n")
end

restorePreviousFinalLeaderboard = function()
  local previousCycleId = raceCycleId - 1
  local previousRecords = replicatedFinishLedger[previousCycleId]
  if previousRecords == nil then return false end
  local version = math.max(1, raceLedgerRevision * 10 + 2)
  return applyLeaderboardSnapshot(
    previousCycleId,
    version,
    1,
    1,
    buildLeaderboardText(previousRecords)
  )
end

-- RETURN-REPAIR-0905: race results are independent of cloud/coin settlement.
function roomClock.hydrateFinalResults()
  if raceFinalResultsSnapshot == nil then return false end
  local ok, payload = pcall(function() return tostring(raceFinalResultsSnapshot:GetValue() or "") end)
  if not ok then return false end
  local cycle, revision = payload:match("^GFP1|(%d+)|(%d+)|final|%d+")
  cycle, revision = tonumber(cycle), tonumber(revision)
  if cycle == nil or revision == nil then return false end
  if cycle < (roomClock.finalCycle or 0) or (cycle == roomClock.finalCycle and revision < (roomClock.finalRevision or 0)) then return false end
  roomClock.finalCycle, roomClock.finalRevision, roomClock.finalPayload = cycle, revision, payload
  return true
end

function roomClock.publishFinalResults()
  if not isAuthoritativeManager() then return false end
  roomClock.hydrateFinalResults()
  if roomClock.finalCycle == raceCycleId then return true end
  local session = roomClock.getRaceSession()
  if session == nil or session.script.GetRaceSessionStatus == nil then return false end
  local ok, rosterCycle = pcall(session.script.GetRaceSessionStatus)
  if not ok or tonumber(rosterCycle) ~= raceCycleId then return false end
  local rows, seen = {}, {}
  for _, entry in ipairs(fleet) do
    local idsOk, ids = pcall(session.script.GetRaceVehicleRosterActorIds, entry.rootName)
    if not idsOk then return false end
    local record = finishRecords[entry.rootName]
    for token in tostring(ids or ""):gmatch("%d+") do
      local id = tonumber(token)
      if id > 0 and not seen[id] then
        seen[id] = true
        rows[#rows+1] = {id=id, ms=not GetRaceManagerActorWithdrawn(id,raceCycleId) and record and record.elapsedMs or -1, vehicle=entry.rootName}
      end
    end
  end
  table.sort(rows, function(a,b)
    if (a.ms>=0) ~= (b.ms>=0) then return a.ms>=0 end
    if a.ms ~= b.ms then return a.ms < b.ms end
    return a.id < b.id
  end)
  local revision, rank, lastMs = math.max(1, raceLedgerRevision+1), 0, nil
  local payload = {table.concat({"GFP1",raceCycleId,revision,"final",#rows},"|")}
  for i,row in ipairs(rows) do
    if row.ms >= 0 and row.ms ~= lastMs then rank=i end
    payload[#payload+1]=table.concat({row.id,row.ms>=0 and rank or 0,row.ms,row.vehicle},"|")
    lastMs=row.ms
  end
  payload=table.concat(payload,"\n")
  if raceFinalResultsSnapshot == nil then return false end
  local wrote=pcall(function() raceFinalResultsSnapshot:SetValue(payload) end)
  local read, confirmed=pcall(function() return raceFinalResultsSnapshot:GetValue() end)
  if not wrote or not read or tostring(confirmed)~=payload then return false end
  roomClock.finalCycle,roomClock.finalRevision,roomClock.finalPayload=raceCycleId,revision,payload
  return true
end

function GetRaceManagerFinalResultsSnapshot()
  roomClock.hydrateFinalResults()
  return roomClock.finalPayload or ""
end

local function finalizeRaceLeaderboard()
  if raceFinalizedCycleId == raceCycleId or not isAuthoritativeManager() then return false end
  -- A retryable room-ledger write is not a DNF. Freeze only after its receipt.
  if next(pendingFinishCrossings) ~= nil then return false end
  if not roomClock.publishFinalResults() then return false end
  if publishLeaderboard(true, true, buildLeaderboardText(), raceCycleId) == false then return false end
  raceFinalizedCycleId = raceCycleId
  return true
end

local function scriptStem(scriptName)
  return string.gsub(scriptName, "%.lua$", "")
end

local function getFleetScript(entry)
  -- Reset dispatch is already bounded to one attempt every two seconds. It may
  -- request a due negative-cache retry, but it never creates a per-frame Find.
  local cached, cacheReason = roomClock.getFleetCacheEntry(entry, true)
  if cached == nil then return nil, cacheReason end
  if entry.rootName == "暮翼巡游" or entry.rootName == "甜咒南瓜" then
    local added = roomClock.resolveAddedFleetRuntime(cached.gameObject, entry)
    if added ~= nil then cached.scriptHolder = added; return added, nil end
    return nil, "added vehicle race API missing (filename/UUID/component lookup)"
  end
  if cached.scriptHolder ~= nil then
    local holderOk, holderReady = pcall(function()
      return cached.scriptHolder.script ~= nil
        and cached.scriptHolder.script.RaceManagerReset ~= nil
    end)
    if holderOk and holderReady then return cached.scriptHolder, nil end
    cached.scriptHolder = nil
  end
  -- Runtime DouyinScript.scriptName is the catalog UUID in the current editor.
  -- Keep the filename fallbacks for compatibility with builds that expose the
  -- human-readable reference name instead.
  local candidates = { entry.scriptId, entry.scriptName, scriptStem(entry.scriptName) }
  for i = 1, #candidates do
    local ok, holder = pcall(function()
      return cached.gameObject:GetDouyinScript(candidates[i])
    end)
    if ok and holder ~= nil and holder.script ~= nil and holder.script.RaceManagerReset ~= nil then
      cached.scriptHolder = holder
      return holder, nil
    end
  end
  return nil, "script/reset endpoint missing"
end

local function dispatchFleetReset(cycleId)
  if raceState ~= "RECYCLING" or cycleId ~= raceCycleId then return false end
  local reachable, missing = 0, {}
  local remaining = math.max(0, CYCLE_MILLISECONDS - (tonumber(raceCycleElapsedMilliseconds) or CYCLE_MILLISECONDS))
  if remaining <= 0 then return false end
  if roomClock.recycleDispatchCycleId ~= cycleId then
    roomClock.recycleDispatchCycleId, roomClock.recycleLocalRequested = cycleId, {}
    roomClock.resetDispatchAttemptCount = 0
  end
  roomClock.resetDispatchAttemptCount = (roomClock.resetDispatchAttemptCount or 0) + 1
  roomClock.resetDispatchLastAttemptAt = Time.time
  for i = 1, #fleet do
    local entry = fleet[i]
    local holder, reason = getFleetScript(entry)
    if holder == nil or holder.script.RaceSessionRecycleVehicle == nil
      or holder.script.HasCompletedRaceSessionRecycle == nil then
      missing[#missing + 1] = entry.rootName .. " (" .. tostring(reason or "recycle endpoint missing") .. ")"
    else
      local api = holder.script
      local ok, completed = pcall(function() return api.HasCompletedRaceSessionRecycle(cycleId) end)
      -- All clients must issue at least one local release, even if the vehicle
      -- owner has already ACKed. Only its unique owner moves the vehicle body.
      if not ok or completed ~= true or not roomClock.recycleLocalRequested[entry.rootName] then
        local sent, accepted = pcall(function() return api.RaceSessionRecycleVehicle(cycleId, remaining) end)
        if sent and accepted == true then roomClock.recycleLocalRequested[entry.rootName] = true end
        ok, completed = pcall(function() return api.HasCompletedRaceSessionRecycle(cycleId) end)
      end
      if ok and completed == true and roomClock.recycleLocalRequested[entry.rootName] then
        reachable = reachable + 1
      else
        missing[#missing + 1] = entry.rootName .. " (owner/local release pending)"
      end
    end
  end
  if lastDispatchCycleId ~= cycleId or lastDispatchReachableCount ~= reachable then
    UnityEngine.Debug.Log("RaceManager: RECYCLING cycleId=" .. tostring(cycleId)
      .. " completed " .. tostring(reachable) .. "/" .. tostring(#fleet))
  end
  lastDispatchCycleId, lastDispatchReachableCount, lastDispatchMissing = cycleId, reachable, missing
  return reachable == #fleet
end

function RaceManagerDispatchReset(cycleId)
  local normalized = math.floor(tonumber(cycleId) or -1)
  if normalized < 2 or math.floor(normalized / SCHEDULE_TOKEN_STRIDE) ~= SCHEDULE_REVISION
    or not raceClockInitialized or normalized ~= raceCycleId or raceState ~= "RECYCLING" then return false end
  if normalized == lastDispatchCycleId and lastDispatchReachableCount >= #fleet then return true end
  if normalized == lastDispatchCycleId and roomClock.resetDispatchLastAttemptAt ~= nil
    and Time.time < roomClock.resetDispatchLastAttemptAt + 1 then return false end
  return dispatchFleetReset(normalized)
end

local function requestCycleReset(cycleId)
  -- No dependence on a one-shot broadcast: every client derives RECYCLING
  -- from the room clock and retries local release + owner ACK once per second.
  return RaceManagerDispatchReset(cycleId)
end

-- RACE_ALL_PLAYERS_RETURN_0905_V1
-- Keep this subsystem on roomClock: the manager already approaches Lua's
-- top-level local-variable limit. Vehicle physics/owner ACKs stay independent.
roomClock.playerReturnPolicies = {}
roomClock.playerReturnCompleted = {}
roomClock.playerReturnCancelled = {}
roomClock.playerReturnState = { stage = "IDLE", error = "", attempts = 0, respawns = 0 }

function roomClock.playerReturnCycle(value)
  local cycle = tonumber(value)
  if cycle == nil or cycle ~= cycle or cycle == math.huge or cycle == -math.huge
    or cycle ~= math.floor(cycle) or cycle < 2
    or math.floor(cycle / SCHEDULE_TOKEN_STRIDE) ~= SCHEDULE_REVISION then return nil end
  return cycle
end

function GetRaceManagerReturnAllPlayersOnRaceEnd(rawCycleId)
  local cycle = roomClock.playerReturnCycle(rawCycleId == nil and raceCycleId or rawCycleId)
  if cycle == nil then return returnAllPlayersOnRaceEnd ~= false end
  if roomClock.playerReturnPolicies[cycle] == nil then
    roomClock.playerReturnPolicies[cycle] = returnAllPlayersOnRaceEnd ~= false
  end
  return roomClock.playerReturnPolicies[cycle] == true
end

function roomClock.observePlayerReturnPhase(cycle, phase)
  local previousCycle, previousPhase = roomClock.playerReturnObservedCycle, roomClock.playerReturnObservedPhase
  GetRaceManagerReturnAllPlayersOnRaceEnd(cycle)
  if phase == "RECYCLING" then
    roomClock.playerReturnAllowedCycle = cycle
  elseif phase == "PREPARING" then
    -- A client which really observed the previous race may miss the complete
    -- RECYCLING window. Resume only that immediately preceding local task;
    -- joining PREPARING or receiving a stale vehicle RPC creates no teleport.
    if previousCycle ~= nil and cycle == previousCycle + 1
      and (previousPhase == "RACING" or previousPhase == "RECYCLING") then
      roomClock.playerReturnAllowedCycle = previousCycle
    elseif previousPhase ~= "PREPARING" or previousCycle ~= cycle then
      roomClock.playerReturnAllowedCycle = nil
    end
  else
    roomClock.playerReturnAllowedCycle = nil
  end
  roomClock.playerReturnObservedCycle, roomClock.playerReturnObservedPhase = cycle, phase
  for oldCycle, _ in pairs(roomClock.playerReturnPolicies) do
    if oldCycle < cycle - 1 then roomClock.playerReturnPolicies[oldCycle] = nil end
  end
  for oldCycle, _ in pairs(roomClock.playerReturnCompleted) do
    if oldCycle < cycle - 1 then roomClock.playerReturnCompleted[oldCycle] = nil end
  end
  for oldCycle, _ in pairs(roomClock.playerReturnCancelled) do
    if oldCycle < cycle - 1 then roomClock.playerReturnCancelled[oldCycle] = nil end
  end
  local task = roomClock.playerReturnState
  if task.cycleId ~= nil and task.cycleId ~= roomClock.playerReturnAllowedCycle
    and task.stage ~= "COMPLETED" then
    task.stage, task.error, task.targetPosition, task.targetRotation = "STALE", "", nil, nil
  end
end

function roomClock.playerReturnNumber(value)
  local number = tonumber(value)
  return number ~= nil and number == number and math.abs(number) < 10000000
end

function roomClock.playerReturnReadPose(object)
  local ok, position, rotation = pcall(function() return object.position, object.rotation end)
  if not ok or position == nil or rotation == nil then return nil, nil end
  local valid = pcall(function()
    if not roomClock.playerReturnNumber(position.x) or not roomClock.playerReturnNumber(position.y)
      or not roomClock.playerReturnNumber(position.z) or not roomClock.playerReturnNumber(rotation.x)
      or not roomClock.playerReturnNumber(rotation.y) or not roomClock.playerReturnNumber(rotation.z)
      or not roomClock.playerReturnNumber(rotation.w) then error("invalid pose") end
    if rotation.x * rotation.x + rotation.y * rotation.y + rotation.z * rotation.z
      + rotation.w * rotation.w < 0.000001 then error("invalid rotation") end
  end)
  if not valid then return nil, nil end
  return Vector3(position.x, position.y, position.z), rotation
end

function roomClock.playerReturnPoseText(position, rotation)
  if position == nil or rotation == nil then return "unavailable" end
  return string.format("%.4f,%.4f,%.4f;%.5f,%.5f,%.5f,%.5f",
    position.x, position.y, position.z, rotation.x, rotation.y, rotation.z, rotation.w)
end

function roomClock.playerReturnLocalActor()
  local ok, actor = pcall(function() return CS.DouyinActorService.GetLocalActor() end)
  if not ok or actor == nil then return nil end
  local valid, localActor, actorId = pcall(function() return actor.isLocal, actor.actorID end)
  local numericId = tonumber(actorId)
  if not valid or localActor ~= true or numericId == nil or numericId ~= numericId
    or numericId <= 0 or numericId > 9007199254740991 or numericId ~= math.floor(numericId) then return nil end
  return actor, tostring(actorId)
end

function roomClock.playerReturnLocalReleaseReady(cycle, actor)
  local read, sitting, parent = pcall(function()
    return actor:IsSitting(), actor.gameObject.transform.parent
  end)
  if not read then return false, "actor seat state unavailable" end
  if sitting ~= false or parent ~= nil then return false, "native seat/parent still attached" end
  local colliderOk, colliderEnabled = pcall(function()
    local collider = actor.gameObject:GetComponent(typeof(UnityEngine.Collider))
    return collider ~= nil and collider.enabled == true
  end)
  if not colliderOk or colliderEnabled ~= true then return false, "actor collider not restored" end
  for index = 1, #fleet do
    local holder, reason = getFleetScript(fleet[index])
    if holder ~= nil then
      if holder.script.GetRaceSessionLocalReleaseStatus == nil then
        return false, fleet[index].rootName .. ": local release API missing"
      end
      local ok, ready, detail = pcall(function()
        return holder.script.GetRaceSessionLocalReleaseStatus(cycle)
      end)
      if ok and detail == "SUPERSEDED_NEW_SEAT" then return false, "SUPERSEDED_NEW_SEAT" end
      if not ok or ready ~= true then
        return false, fleet[index].rootName .. ": " .. tostring(detail or "local release pending")
      end
    elseif roomClock.fleetCache[fleet[index].rootName] ~= nil
      and roomClock.fleetCache[fleet[index].rootName].gameObject ~= nil then
      return false, fleet[index].rootName .. ": " .. tostring(reason or "script unavailable")
    end
    -- A missing vehicle root cannot produce a later local exit callback. Its
    -- owner ACK is a separate fleet error, never a blocker for walking actors.
  end
  return true, ""
end

function roomClock.playerReturnPoseMatches(actor, targetPosition, targetRotation)
  local position, rotation = roomClock.playerReturnReadPose(actor)
  if position == nil then return false end
  local dx, dy, dz = position.x - targetPosition.x, position.y - targetPosition.y, position.z - targetPosition.z
  -- Respawn immediately places at the engine's current configured birth pose.
  -- Native gravity may settle the capsule below that pose before the next tick.
  -- Do not permit horizontal drift or an unrestricted vertical fallback.
  if dx * dx + dz * dz > 0.25 or dy < -3.0 or dy > 0.5 then return false end
  local dot = rotation.x * targetRotation.x + rotation.y * targetRotation.y
    + rotation.z * targetRotation.z + rotation.w * targetRotation.w
  local magnitude = math.sqrt((rotation.x^2 + rotation.y^2 + rotation.z^2 + rotation.w^2)
    * (targetRotation.x^2 + targetRotation.y^2 + targetRotation.z^2 + targetRotation.w^2))
  return magnitude > 0 and math.abs(dot / magnitude) >= math.cos(3 * math.pi / 360)
end

function RaceManagerReturnLocalActorToSpawn(rawCycleId)
  local cycle = roomClock.playerReturnCycle(rawCycleId)
  if cycle == nil then return true, true, "STALE" end
  if not raceClockInitialized or raceClockNowUnixMilliseconds == nil then return true, false, "PENDING_CLOCK" end
  local allowed = (raceState == "RECYCLING" and cycle == raceCycleId)
    or (raceState == "PREPARING" and raceCycleId == cycle + 1 and roomClock.playerReturnAllowedCycle == cycle)
  if not allowed then return true, true, "STALE" end
  if not GetRaceManagerReturnAllPlayersOnRaceEnd(cycle) then return false, false, "DISABLED" end
  local actor, actorId = roomClock.playerReturnLocalActor()
  if actor == nil then
    roomClock.playerReturnState.stage = "PENDING_ACTOR"
    return true, false, "PENDING_ACTOR"
  end
  if roomClock.playerReturnCompleted[cycle] == actorId then return true, true, "COMPLETED" end
  if roomClock.playerReturnCancelled[cycle] == actorId then return true, true, "STALE" end
  local task = roomClock.playerReturnState
  if task.cycleId ~= cycle or task.actor ~= actor then
    task = { cycleId = cycle, actor = actor, actorId = actorId, stage = "PENDING_SEAT",
      error = "", attempts = 0, respawns = 0, nextAttemptAt = -math.huge }
    roomClock.playerReturnState = task
  end
  if Time.time < task.nextAttemptAt then return true, false, task.stage end
  task.nextAttemptAt = Time.time + 0.2
  local released, releaseError = roomClock.playerReturnLocalReleaseReady(cycle, actor)
  if releaseError == "SUPERSEDED_NEW_SEAT" then
    roomClock.playerReturnCancelled[cycle] = actorId
    task.stage, task.error, task.targetPosition, task.targetRotation = "STALE", releaseError, nil, nil
    return true, true, "STALE"
  end
  if not released then task.stage, task.error = "PENDING_SEAT", releaseError; return true, false, task.stage end
  if task.targetPosition ~= nil then
    if roomClock.playerReturnPoseMatches(actor, task.targetPosition, task.targetRotation) then
      roomClock.playerReturnCompleted[cycle] = actorId
      task.stage, task.error = "COMPLETED", ""
      return true, true, "COMPLETED"
    end
    if Time.time < task.verifyUntil then task.stage = "VERIFYING"; return true, false, task.stage end
    task.targetPosition, task.targetRotation = nil, nil
    task.stage, task.error, task.nextAttemptAt = "RETRY", "Respawn post-frame pose readback mismatch", Time.time + 0.5
    return true, false, task.stage
  end
  task.beforePosition, task.beforeRotation = roomClock.playerReturnReadPose(actor)
  task.afterPosition, task.afterRotation = nil, nil
  task.attempts = task.attempts + 1
  task.respawnRequestedAt = Time.time
  -- Official SDK birth source, not a scene-name lookup or a cached editor pose.
  -- This runtime's native Respawn synchronously resolves and applies its birth
  -- pose. A same-position result is legitimate when already at that birth pose.
  local moved, moveError = pcall(function() actor:Respawn() end)
  if not moved then
    task.stage, task.error, task.nextAttemptAt = "RETRY", tostring(moveError), Time.time + 0.5
    return true, false, task.stage
  end
  task.respawns = task.respawns + 1
  local position, rotation = roomClock.playerReturnReadPose(actor)
  task.afterPosition, task.afterRotation = position, rotation
  if position == nil then
    task.stage, task.error, task.nextAttemptAt = "RETRY", "Respawn immediate pose invalid", Time.time + 0.5
    return true, false, task.stage
  end
  task.targetPosition, task.targetRotation = position, rotation
  task.verifyUntil, task.stage, task.error = Time.time + 0.8, "VERIFYING", ""
  -- Void/pcall success alone is not completion. Verify a later frame's pose,
  -- restored collider and detached seat against the engine-resolved result.
  return true, false, "VERIFYING"
end

function OnActorRespawn(actor)
  local localActor=CS.DouyinActorService.GetLocalActor()
  if actor~=nil and actor==localActor and actor.isLocal and (raceState=="WAITING" or raceState=="RACING") then
    roomClock.manualRespawnEvents=(roomClock.manualRespawnEvents or 0)+1
    RaceManagerLocalWithdraw()
  end
  -- Additional diagnostics only: native callback hooks vary by SDK build and
  -- cannot be the sole acknowledgement of an otherwise verified Respawn.
  local task = roomClock.playerReturnState
  if task.actor ~= actor or task.respawnRequestedAt == nil then return end
  local localActor, actorId = roomClock.playerReturnLocalActor()
  if actor ~= localActor or actorId ~= task.actorId then return end
  task.respawnEvents = (task.respawnEvents or 0) + 1
  task.lastRespawnEventAt = Time.time
end

function roomClock.updatePlayerReturn()
  local cycle = roomClock.playerReturnAllowedCycle
  if cycle ~= nil then RaceManagerReturnLocalActorToSpawn(cycle) end
end

function GetRaceManagerPlayerReturnStatus()
  local task = roomClock.playerReturnState
  return table.concat({ "cycle=" .. tostring(task.cycleId or 0), "actor=" .. tostring(task.actorId or ""),
    "stage=" .. tostring(task.stage), "attempts=" .. tostring(task.attempts or 0),
    "respawns=" .. tostring(task.respawns or 0), "error=" .. tostring(task.error or ""),
    "before=" .. roomClock.playerReturnPoseText(task.beforePosition, task.beforeRotation),
    "after=" .. roomClock.playerReturnPoseText(task.afterPosition, task.afterRotation),
    "respawnEvents=" .. tostring(task.respawnEvents or 0),
    "allowedCycle=" .. tostring(roomClock.playerReturnAllowedCycle or 0),
    "enabled=" .. tostring(GetRaceManagerReturnAllPlayersOnRaceEnd()) }, "|")
end


local function setupRaceCountdownAudioSource()
  if countdownAudioSource ~= nil then return true end
  local ok, result = pcall(function()
    local existing = self.transform:Find("Race_StartCountdownAudio")
    if existing ~= nil then
      countdownAudioObject = existing.gameObject
    else
      countdownAudioObject = UnityEngine.GameObject("Race_StartCountdownAudio")
      countdownAudioObject.transform:SetParent(self.transform, false)
    end
    countdownAudioObject.transform.localPosition = Vector3.zero
    countdownAudioObject.transform.localRotation = Quaternion.identity
    countdownAudioObject.transform.localScale = Vector3.one
    countdownAudioSource = countdownAudioObject:GetComponent(typeof(UnityEngine.AudioSource))
    if countdownAudioSource == nil then
      countdownAudioSource = countdownAudioObject:AddComponent(typeof(UnityEngine.AudioSource))
    end
    if countdownAudioSource == nil then return false end
    countdownAudioSource.playOnAwake = false
    countdownAudioSource.loop = false
    countdownAudioSource.volume = COUNTDOWN_AUDIO_VOLUME
    countdownAudioSource.pitch = 1
    countdownAudioSource.spatialBlend = 0
    countdownAudioSource.dopplerLevel = 0
    countdownAudioSource.spread = 0
    countdownAudioSource.panStereo = 0
    countdownAudioSource.priority = 0
    pcall(function() countdownAudioSource.ignoreListenerPause = true end)
    pcall(function() countdownAudioSource.bypassEffects = true end)
    pcall(function() countdownAudioSource.bypassListenerEffects = true end)
    pcall(function() countdownAudioSource.bypassReverbZones = true end)
    return true
  end)
  if not ok or result ~= true then
    countdownAudioSource = nil
    countdownAudioLastError = ok and "AudioSource creation failed" or tostring(result)
    roomClock.reportSubsystemError("countdown audio setup", countdownAudioLastError)
    return false
  end
  roomClock.clearSubsystemError("countdown audio setup")
  return true
end

local function getRaceCountdownAudioBank()
  local candidates = {
    COUNTDOWN_AUDIO_BANK_SCRIPT_ID,
    COUNTDOWN_AUDIO_BANK_SCRIPT_NAME,
    string.gsub(COUNTDOWN_AUDIO_BANK_SCRIPT_NAME, "%.lua$", ""),
  }
  for i = 1, #candidates do
    local ok, holder = pcall(function() return self.gameObject:GetDouyinScript(candidates[i]) end)
    if ok and holder ~= nil and holder.script ~= nil
      and holder.script.GetSharedRaceCountdownClip ~= nil then
      return holder
    end
  end
  return nil
end

local function playRaceCountdownDigit(digit, sampledAtUnixMilliseconds)
  if not setupRaceCountdownAudioSource() then return false end
  local holder = getRaceCountdownAudioBank()
  if holder == nil then
    countdownAudioLastError = "countdown audio bank binding missing"
    return false
  end
  local ok, clip = pcall(function()
    return holder.script.GetSharedRaceCountdownClip(digit)
  end)
  if not ok or clip == nil then
    countdownAudioLastError = ok and "countdown digit clip unavailable" or tostring(clip)
    return false
  end
  local played, failure = pcall(function()
    if countdownAudioSource.isPlaying then countdownAudioSource:Stop() end
    countdownAudioSource.clip = clip
    countdownAudioSource.time = 0
    countdownAudioSource.volume = COUNTDOWN_AUDIO_VOLUME
    countdownAudioSource:Play()
  end)
  if not played then
    countdownAudioLastError = tostring(failure)
    roomClock.reportSubsystemError("countdown audio play", failure)
    return false
  end
  roomClock.clearSubsystemError("countdown audio play")
  countdownAudioLastPlayedCycleId = raceCycleId
  countdownAudioLastPlayedDigit = digit
  countdownAudioLastPlayUnixMilliseconds = sampledAtUnixMilliseconds
  countdownAudioLastError = ""
  return true
end

local function stopRaceCountdownAudio()
  local ok, failure = pcall(function()
    if countdownAudioSource ~= nil and countdownAudioSource.isPlaying then
      countdownAudioSource:Stop()
    end
  end)
  if not ok then roomClock.reportSubsystemError("countdown audio stop", failure) end
end

local function invalidateRaceCountdownAudioClock()
  stopRaceCountdownAudio()
  countdownAudioPreviousRemainingMilliseconds = nil
  countdownAudioLastRaceState = nil
end

local function updateRaceStartCountdownAudio(
  sampledAtUnixMilliseconds,
  stateName,
  scheduledRaceStartUnixMilliseconds,
  suppressCurrentDigit
)
  if sampledAtUnixMilliseconds == nil or scheduledRaceStartUnixMilliseconds == nil then
    invalidateRaceCountdownAudioClock()
    return
  end

  if countdownAudioCycleId ~= raceCycleId then
    countdownAudioCycleId = raceCycleId
    countdownAudioPreviousRemainingMilliseconds = nil
    countdownAudioLastRaceState = nil
    countdownAudioLastHandledCycleId = 0
    countdownAudioLastHandledDigit = 0
    if suppressCurrentDigit then countdownAudioLastRaceState = stateName end
  end

  if stateName == "RACING" then
    local crossedIntoRacing = countdownAudioLastRaceState == "WAITING"
    local startLatenessMilliseconds = sampledAtUnixMilliseconds - scheduledRaceStartUnixMilliseconds
    local goAlreadyPlayed = countdownAudioLastPlayedCycleId == raceCycleId
      and countdownAudioLastPlayedDigit == 0
    if not suppressCurrentDigit and crossedIntoRacing
      and startLatenessMilliseconds >= 0
      -- Followers receive the authoritative phase snapshot every 500 ms. Give
      -- the boundary announcement enough room for one snapshot plus jitter;
      -- first synchronization is still suppressed, so this cannot replay a
      -- stale GO for a late joiner.
      and startLatenessMilliseconds <= 1200
      and not goAlreadyPlayed then
      countdownAudioLastHandledCycleId = raceCycleId
      countdownAudioLastHandledDigit = 0
      playRaceCountdownDigit(0, sampledAtUnixMilliseconds)
    elseif not goAlreadyPlayed then
      -- A late joiner must never hear a stale GO. Once GO has started for this
      -- cycle, let the short clip finish instead of stopping it next frame.
      stopRaceCountdownAudio()
    end
    countdownAudioPreviousRemainingMilliseconds = nil
    countdownAudioLastRaceState = stateName
    return
  end

  if stateName ~= "WAITING" then
    if stateName == "RECYCLING" then stopRaceCountdownAudio() end
    countdownAudioPreviousRemainingMilliseconds = nil
    countdownAudioLastRaceState = stateName
    return
  end

  local remainingMilliseconds = scheduledRaceStartUnixMilliseconds - sampledAtUnixMilliseconds
  if remainingMilliseconds <= 0 then
    stopRaceCountdownAudio()
    countdownAudioPreviousRemainingMilliseconds = nil
    countdownAudioLastRaceState = stateName
    return
  end

  if suppressCurrentDigit then
    countdownAudioPreviousRemainingMilliseconds = remainingMilliseconds
    countdownAudioLastRaceState = stateName
    return
  end

  local enteredWaiting = countdownAudioLastRaceState ~= "WAITING"
  local previousRemaining = countdownAudioPreviousRemainingMilliseconds
  if previousRemaining == nil then
    if countdownAudioLastRaceState ~= "WAITING"
      and remainingMilliseconds <= COUNTDOWN_AUDIO_LEAD_MILLISECONDS then
      -- A normal PREPARING -> WAITING transition with a five-second WAITING
      -- phase still emits "five". A first synchronization passes
      -- suppressCurrentDigit=true and therefore does not enter this branch.
      previousRemaining = COUNTDOWN_AUDIO_LEAD_MILLISECONDS + 1
    else
      previousRemaining = remainingMilliseconds
    end
  end
  countdownAudioPreviousRemainingMilliseconds = remainingMilliseconds
  countdownAudioLastRaceState = stateName

  if remainingMilliseconds > COUNTDOWN_AUDIO_LEAD_MILLISECONDS then return end
  local digit = math.max(1, math.min(5, math.ceil(remainingMilliseconds / 1000)))
  local boundaryMilliseconds = digit * 1000
  local crossedBoundary = previousRemaining > boundaryMilliseconds
    and remainingMilliseconds <= boundaryMilliseconds
  if not crossedBoundary then return end

  local alreadyHandled = countdownAudioLastHandledCycleId == raceCycleId
    and countdownAudioLastHandledDigit == digit
  if alreadyHandled then return end
  countdownAudioLastHandledCycleId = raceCycleId
  countdownAudioLastHandledDigit = digit

  local latenessMilliseconds = boundaryMilliseconds - remainingMilliseconds
  local allowedLatenessMilliseconds = COUNTDOWN_AUDIO_MAX_TRIGGER_LATENESS_MILLISECONDS
  if digit == 5 and enteredWaiting then
    -- The first digit is also triggered by the authoritative WAITING snapshot.
    -- Match GO's one-snapshot jitter allowance without changing later digits.
    allowedLatenessMilliseconds = 1200
  end
  if latenessMilliseconds > allowedLatenessMilliseconds then
    countdownAudioLastError = "stale digit skipped after frame hitch"
    return
  end
  playRaceCountdownDigit(digit, sampledAtUnixMilliseconds)
end

local function destroyRaceCountdownAudio()
  stopRaceCountdownAudio()
  pcall(function()
    if countdownAudioObject ~= nil then UnityEngine.Object.Destroy(countdownAudioObject) end
  end)
  countdownAudioObject = nil
  countdownAudioSource = nil
end

local function applyRaceState(nextState, sampledAtUnixMilliseconds, scheduledRaceStartUnixMilliseconds)
  local previousState = raceState
  -- Scan while the authoritative phase is still RACING. Setting RECYCLING
  -- first used to make updateFinishCrossings return without its final sample.
  if previousState == "RACING" and nextState ~= "RACING" and isAuthoritativeManager() then
    roomClock.runSafely("final finish crossing scan", function()
      updateFinishCrossings(sampledAtUnixMilliseconds)
      finalizeRaceLeaderboard()
    end)
  end
  raceState = nextState
  raceLastDisplayedSecond = -1
  roomClock.runSafely("race gate state", function() renderRaceState(nextState) end)
  roomClock.runSafely("leaderboard phase transition", function()
    if nextState == "PREPARING" then restorePreviousFinalLeaderboard() end
    if leaderboardVisible and leaderboardSourceCycleId < raceCycleId
      and nextState ~= "PREPARING" then
      if isAuthoritativeManager() then
        publishLeaderboard(false, true, leaderboardText, leaderboardSourceCycleId)
      else
        applyLeaderboardSnapshot(
          leaderboardSourceCycleId,
          leaderboardVersion + 1,
          0,
          1,
          leaderboardText
        )
      end
    end
    if nextState == "RACING" then
      beginRaceTiming(scheduledRaceStartUnixMilliseconds, sampledAtUnixMilliseconds)
      if raceLedgerReadyForCurrentCycle and finishSequence > 0 then
        applyLeaderboardSnapshot(
          raceCycleId,
          math.max(leaderboardVersion + 1, raceLedgerRevision * 10 + 1),
          1,
          0,
          LEADERBOARD_SETTLING_TEXT
        )
      end
    elseif nextState == "RECYCLING" and raceLedgerReadyForCurrentCycle then
      applyLeaderboardSnapshot(
        raceCycleId,
        math.max(leaderboardVersion + 1, raceLedgerRevision * 10 + 2),
        1,
        1,
        buildLeaderboardText(finishRecords)
      )
    end
  end)
  UnityEngine.Debug.Log("RaceManager: cycleId=" .. tostring(raceCycleId) .. ", state=" .. tostring(nextState))
end

local function updateRaceLoop(forceUpdate)
  local clockWasUnavailable = raceClockNowUnixMilliseconds == nil
  local sampledAt = roomClock.readAuthoritativeMilliseconds(forceUpdate == true)
  if sampledAt == nil then
    raceClockNowUnixMilliseconds = nil
    raceFinishTrackerNeedsReseed = true
    roomClock.runSafely("countdown audio invalidation", invalidateRaceCountdownAudioClock)
    roomClock.runSafely("clock unavailable display", showClockUnavailable)
    return nil
  end

  local absoluteCycleId, cycleElapsed, cycleStart, scheduledRaceStart,
    nextState, remainingMilliseconds = resolveGlobalRaceClock(sampledAt)
  local firstSynchronization = not raceClockInitialized
  local cycleChanged = false

  if roomClock.hasAuthority() then
    roomClock.publishSnapshot(
      sampledAt,
      absoluteCycleId,
      nextState,
      cycleElapsed,
      remainingMilliseconds,
      forceUpdate == true or firstSynchronization
    )
  end

  if firstSynchronization then
    raceClockInitialized = true
    raceCycleId = absoluteCycleId
    -- A late join hydrates the already-running authoritative room; loading late
    -- must not create a private reset or invalidate the shared live cycle.
    beginRaceCycle(raceCycleId)
    raceState = nil
  elseif absoluteCycleId > raceCycleId then
    -- If frames were skipped over the end boundary, give the previous RACING
    -- segment one final interpolated crossing scan before changing cycle data.
    if raceState == "RACING" then
      updateFinishCrossings(sampledAt)
      finalizeRaceLeaderboard()
    end
    raceCycleId = absoluteCycleId
    -- Vehicle physics is reset by the unique owner of each networked vehicle.
    -- A client that resumes late hydrates the current authoritative positions;
    -- it must not create a private, locally-unplayable version of the cycle.
    beginRaceCycle(raceCycleId)
    raceState = nil
    cycleChanged = true
  elseif absoluteCycleId < raceCycleId then
    serverClockInvalid = true
    serverClockSource = "CLOCK_UNHEALTHY"
    serverClockLastError = "derived cycle moved backwards"
    raceClockNowUnixMilliseconds = nil
    roomClock.runSafely("backward clock display", showClockUnavailable)
    return nil
  end

  raceClockNowUnixMilliseconds = sampledAt
  raceCycleElapsedMilliseconds = cycleElapsed
  raceCycleStartUnixMilliseconds = cycleStart
  raceScheduledStartUnixMilliseconds = scheduledRaceStart

  if nextState ~= raceState then
    applyRaceState(nextState, sampledAt, scheduledRaceStart)
  elseif nextState == "RACING" and raceTimingCycleId ~= raceCycleId then
    beginRaceTiming(scheduledRaceStart, sampledAt)
  elseif forceUpdate or clockWasUnavailable then
    roomClock.runSafely("race gate refresh", function() renderRaceState(nextState) end)
  end

  roomClock.observePlayerReturnPhase(raceCycleId, nextState)

  local secondsRemaining = remainingMilliseconds / 1000
  if forceUpdate or math.ceil(secondsRemaining) ~= raceLastDisplayedSecond then
    roomClock.runSafely("race display update", function()
      updateRaceDisplay(nextState, secondsRemaining)
    end)
  end

  roomClock.runSafely("countdown audio update", function()
    updateRaceStartCountdownAudio(
      sampledAt,
      nextState,
      scheduledRaceStart,
      firstSynchronization or clockWasUnavailable or cycleChanged
    )
  end)

  if nextState == "PREPARING" then
    raceObservedPreparingCycleId = raceCycleId
  end
  if nextState == "WAITING" and isAuthoritativeManager() then
    roomClock.runSafely("race ledger initialization", ensureRaceLedgerForCurrentCycle)
  end

  if nextState == "RECYCLING" then
    roomClock.runSafely("final results retry", finalizeRaceLeaderboard)
    roomClock.runSafely("recycle all vehicles", function() requestCycleReset(raceCycleId) end)
  end
  roomClock.runSafely("return all local players", roomClock.updatePlayerReturn)
  return sampledAt
end

function GetRaceManagerSmallDisplayReady()
  return smallRaceDisplayRoot ~= nil
    and smallRaceCountdownText ~= nil
    and areRacePhasePanelsReady(smallRacePhasePanels)
end

function GetRaceManagerSmallDisplay2Ready()
  return smallRaceDisplayRoot2 ~= nil
    and smallRaceCountdownText2 ~= nil
    and areRacePhasePanelsReady(smallRacePhasePanels2)
end

function GetRaceManagerCycleId()
  return raceCycleId
end

function GetRaceManagerState()
  return raceState
end

function GetRaceManagerLastDispatchCycleId()
  return lastDispatchCycleId
end

function GetRaceManagerLastDispatchReachableCount()
  return lastDispatchReachableCount
end

function GetRaceManagerLastDispatchCompletedCount()
  return lastDispatchReachableCount
end

function GetRaceManagerRaceStartTime()
  return raceStartAt or -1
end

function GetRaceManagerRaceStartUnixMilliseconds()
  return raceStartUnixMilliseconds or -1
end

function GetRaceManagerClockReady()
  return raceClockNowUnixMilliseconds ~= nil
end

function GetRaceManagerCyclePlayable()
  -- Compatibility endpoint: playability is now a property of synchronized
  -- server-clock health, not of whether one client observed the reset frame.
  return raceClockInitialized and raceClockNowUnixMilliseconds ~= nil
end

function GetRaceManagerClockSource()
  return serverClockSource
end

function GetRaceManagerClockLastError()
  return serverClockLastError
end

function GetRaceManagerClockGeneration()
  return roomClock.generation
end

function GetRaceManagerClockSequence()
  local snapshot = roomClock.snapshotValue
  return snapshot ~= nil and snapshot.sequence or roomClock.sequence
end

function GetRaceManagerClockIsAuthority()
  return roomClock.hasAuthority()
end

function GetRaceManagerRoomClockMode()
  if roomClock.mode ~= nil then return roomClock.mode end
  return roomClock.snapshotValue ~= nil and roomClock.snapshotValue.mode or ""
end

function GetRaceManagerClockSnapshotAgeMilliseconds()
  if roomClock.snapshotReceivedRealtime == nil then return -1 end
  return math.max(0, realtimeSeconds() - roomClock.snapshotReceivedRealtime) * 1000
end

function GetRaceManagerRemainingMilliseconds()
  if raceClockNowUnixMilliseconds == nil then return -1 end
  local _, _, _, _, _, remaining = resolveGlobalRaceClock(raceClockNowUnixMilliseconds)
  return remaining
end

function GetRaceManagerServerUnixMilliseconds()
  return raceClockNowUnixMilliseconds or -1
end

function GetRaceManagerCycleElapsedMilliseconds()
  return raceCycleElapsedMilliseconds
end

function GetRaceManagerCycleStartUnixMilliseconds()
  return raceCycleStartUnixMilliseconds or -1
end

function GetRaceManagerScheduledStartUnixMilliseconds()
  return raceScheduledStartUnixMilliseconds or -1
end

function GetRaceManagerScheduleEpochUnixMilliseconds()
  return SCHEDULE_EPOCH_UNIX_MILLISECONDS
end

function GetRaceManagerScheduleRevision()
  return SCHEDULE_REVISION
end

function GetRaceManagerScheduleSignature()
  return table.concat({
    tostring(SCHEDULE_REVISION),
    tostring(SCHEDULE_EPOCH_UNIX_MILLISECONDS),
    tostring(PREPARING_SECONDS),
    tostring(WAITING_SECONDS),
    tostring(RACING_SECONDS),
    tostring(RECYCLING_SECONDS),
  }, ":")
end

function GetRaceManagerCountdownAudioStatus()
  local sourceReady = countdownAudioSource ~= nil
  local bankReady = false
  local bankReadyCount = 0
  local holder = getRaceCountdownAudioBank()
  if holder ~= nil and holder.script.GetSharedRaceCountdownAudioStatus ~= nil then
    pcall(function()
      bankReady, bankReadyCount = holder.script.GetSharedRaceCountdownAudioStatus()
    end)
  end
  return sourceReady,
    bankReady,
    bankReadyCount,
    countdownAudioLastPlayedCycleId,
    countdownAudioLastPlayedDigit,
    countdownAudioLastPlayUnixMilliseconds,
    COUNTDOWN_AUDIO_VOLUME,
    countdownAudioLastError
end

function GetRaceManagerCountdownAudioBankScriptId()
  return COUNTDOWN_AUDIO_BANK_SCRIPT_ID
end

function GetRaceManagerFinishCount()
  local count = 0
  for _, _ in pairs(finishRecords) do count = count + 1 end
  return count
end

function GetRaceManagerVehicleFinishMilliseconds(vehicleName)
  local record = finishRecords[tostring(vehicleName or "")]
  return record ~= nil and record.elapsedMs or -1
end

-- A detached, read-only presentation copy. No new result or reward state.
-- Cycle and records are sampled together to avoid mixing two rounds at rollover.
function GetRaceManagerFinishPresentationSnapshot()
  local records = {}
  for name, record in pairs(finishRecords) do
    local ms = tonumber(record.elapsedMs)
    if ms ~= nil and ms >= 0 then records[name] = math.floor(ms) end
  end
  return raceCycleId, records
end

function GetRaceManagerLeaderboardVisible()
  return leaderboardVisible
end

function GetRaceManagerLeaderboardText()
  return leaderboardText
end

function GetRaceManagerResultsText()
  return buildLeaderboardText(finishRecords)
end

function RaceManagerRefreshLeaderboardPresentation()
  if roomClock.unifiedWorldBoards then
    roomClock.hideLegacyBoardRenderers()
    return true
  end
  if not leaderboardVisible then return false end
  renderLeaderboardRows(buildLeaderboardText(finishRecords))
  updateLeaderboardTitle()
  return true
end

function OnNetSpawned()
  managerNetSpawned = true
  if raceClockSnapshot ~= nil and roomClock.snapshotChangeHandle == nil then
    pcall(function()
      roomClock.snapshotChangeHandle = raceClockSnapshot:OnValueChange(function(currentValue, previousValue)
        roomClock.applySnapshotPayload(currentValue)
      end)
    end)
  end
  if raceResultLedger ~= nil and raceLedgerChangeHandle == nil then
    pcall(function()
      raceLedgerChangeHandle = raceResultLedger:OnValueChange(function(currentValue, previousValue)
        applyRaceLedgerPayload(currentValue)
      end)
    end)
  end
  roomClock.hydrateSnapshot()
  hydrateRaceLedger()
  serverClockNextSampleRealtime = -math.huge
  roomClock.runSafely("network-spawn clock update", function() updateRaceLoop(true) end)
end

function OnVariablesSynced()
  roomClock.hydrateSnapshot()
  hydrateRaceLedger()
end

function OnOwnershipTransferred()
  roomClock.hydrateSnapshot()
  hydrateRaceLedger()
  serverClockNextSampleRealtime = -math.huge
  roomClock.runSafely("ownership-transfer clock update", function() updateRaceLoop(true) end)
  if raceState == "RECYCLING" then
    roomClock.runSafely("ownership-transfer fleet recycle", function() requestCycleReset(raceCycleId) end)
  end
  if isAuthoritativeManager() and raceState == "RACING" then
    roomClock.runSafely("ownership-transfer route hydration", function()
      local validator = roomClock.getRouteValidator()
      if validator ~= nil and validator.script.RaceRouteValidatorBeginRace ~= nil then
        validator.script.RaceRouteValidatorBeginRace(raceCycleId, raceClockNowUnixMilliseconds)
      end
    end)
  end
end

function OnPlayerJoined(player)
  if roomClock.hasAuthority() then roomClock.nextPublishRealtime = -math.huge end
end

function Start()
  -- RaceManager uses a tiny module-enabled carrier beside the display. Hide and
  -- neutralize that carrier so it can never affect the visible scene.
  roomClock.runSafely("manager carrier setup", function()
    setRendererVisible(self.transform, false)
    local carrierColliders = self.gameObject:GetComponentsInChildren(typeof(UnityEngine.Collider), true)
    for i = 0, carrierColliders.Length - 1 do
      if carrierColliders[i] ~= nil then carrierColliders[i].enabled = false end
    end
    local managerBody = self.gameObject:GetComponent(typeof(UnityEngine.Rigidbody))
    if managerBody ~= nil then
      managerBody.useGravity = false
      managerBody.isKinematic = true
      managerBody.velocity = Vector3.zero
      managerBody.angularVelocity = Vector3.zero
    end
  end)
  roomClock.runSafely("initial fleet cache warmup", function()
    for i = 1, #fleet do roomClock.getFleetCacheEntry(fleet[i], true) end
    roomClock.fleetCacheNextMaintenanceAt = Time.time + roomClock.fleetCacheRetrySeconds
  end)
  roomClock.runSafely("initial race display setup", setupRaceDisplay)
  roomClock.runSafely("initial synchronizing display", showClockUnavailable)
  -- Optional scene systems are isolated after the display is already readable.
  roomClock.runSafely("initial race scene setup", setupRaceScene)
  roomClock.runSafely("initial countdown audio setup", setupRaceCountdownAudioSource)
  pcall(function()
    DouyinNetService.OnNetworkSettled(function()
      serverClockNextSampleRealtime = -math.huge
      roomClock.runSafely("network-settled clock update", function() updateRaceLoop(true) end)
    end)
  end)
  roomClock.runSafely("initial clock update", function() updateRaceLoop(true) end)
end

-- RETURN-SPAWN-0911: a manual native respawn withdraws only this actor.
roomClock.withdrawals = {}
function roomClock.readWithdrawals()
  if raceWithdrawalsSnapshot == nil then return end
  local ok, raw=pcall(function()return tostring(raceWithdrawalsSnapshot:GetValue() or "")end)
  if not ok then return end
  local cycle,body=raw:match("^WD1|(%d+)|(.*)$")
  cycle=tonumber(cycle)
  if cycle~=raceCycleId then return end
  local rows=roomClock.withdrawals[cycle] or {};roomClock.withdrawals[cycle]=rows
  for id in body:gmatch("%d+") do rows[tonumber(id)]=true end
end
function GetRaceManagerActorWithdrawn(actorId,cycle)
  cycle=tonumber(cycle) or raceCycleId
  roomClock.readWithdrawals()
  return roomClock.withdrawals[cycle]~=nil and roomClock.withdrawals[cycle][tonumber(actorId)]==true
end
function RaceManagerWithdrawActor(actorId,cycle,openId)
  if not isAuthoritativeManager() or tonumber(cycle)~=raceCycleId
    or (raceState~="WAITING" and raceState~="RACING") then return false end
  actorId=tonumber(actorId)
  local identity=false
  pcall(function()
    local players=CS.DouyinPlayerService.GetPlayers()
    for i=0,players.Length-1 do
      local p=players[i];local a=p:GetActor()
      if a and tonumber(a.actorID)==actorId and tostring(p.playerOpenID)==tostring(openId) then identity=true end
    end
  end)
  if not identity then return false end
  local session=roomClock.getRaceSession();local member=false
  if not session or not session.script then return false end
  for _,entry in ipairs(fleet) do
    local ok,ids=pcall(session.script.GetRaceVehicleRosterActorIds,entry.rootName)
    if ok then for id in tostring(ids or ""):gmatch("%d+") do if tonumber(id)==actorId then member=true end end end
  end
  if not member then return false end
  roomClock.readWithdrawals()
  local rows=roomClock.withdrawals[raceCycleId] or {};roomClock.withdrawals[raceCycleId]=rows
  rows[actorId]=true
  local ids={};for id in pairs(rows)do ids[#ids+1]=id end;table.sort(ids)
  if raceWithdrawalsSnapshot==nil then return false end
  local payload="WD1|"..raceCycleId.."|"..table.concat(ids,",")
  local ok=pcall(function()raceWithdrawalsSnapshot:SetValue(payload)end)
  return ok
end
function RaceManagerLocalWithdraw()
  if raceState~="WAITING" and raceState~="RACING" then return false end
  local actor=CS.DouyinActorService.GetLocalActor()
  local player=CS.DouyinPlayerService.GetLocalPlayer()
  if not actor or not player then return false end
  local id=tonumber(actor.actorID)
  local rows=roomClock.withdrawals[raceCycleId] or {};roomClock.withdrawals[raceCycleId]=rows
  rows[id]=true
  roomClock.localWithdrawal={actorId=id,cycle=raceCycleId,openId=tostring(player.playerOpenID),nextAt=0}
  roomClock.tickWithdrawal()
  return true
end
function roomClock.tickWithdrawal()
  for cycle in pairs(roomClock.withdrawals)do if cycle<raceCycleId-1 then roomClock.withdrawals[cycle]=nil end end
  local request=roomClock.localWithdrawal
  if not request or request.cycle~=raceCycleId or Time.time<request.nextAt then return end
  if raceState~="WAITING" and raceState~="RACING" then return end
  request.nextAt=Time.time+0.5
  if isAuthoritativeManager() then RaceManagerWithdrawActor(request.actorId,request.cycle,request.openId)
  else pcall(function()self:SendMessageToOwner("RaceManagerWithdrawActor",request.actorId,request.cycle,request.openId)end)end
end
function OnRespawn()
  roomClock.manualRespawnEvents=(roomClock.manualRespawnEvents or 0)+1
  RaceManagerLocalWithdraw()
end
function GetRaceWithdrawalDiagnostics()
  local r=roomClock.localWithdrawal
  return roomClock.manualRespawnEvents or 0,r and r.cycle or 0,r and r.actorId or 0
end

function Update()
  roomClock.tickWithdrawal()
  if roomClock.leaderboardPresentationDirty
    and Time.time >= roomClock.leaderboardPresentationRetryAt then
    roomClock.presentLeaderboard()
  end
  -- Missing/replaced roots are retried at most once per second. Finish-line
  -- sampling below remains a pure cache read even when an object is absent.
  roomClock.maintainFleetCache()
  local phasePanelsReady = areRacePhasePanelsReady(racePhasePanels)
  local smallPhasePanelsReady = areRacePhasePanelsReady(smallRacePhasePanels)
  local smallPhasePanels2Ready = areRacePhasePanelsReady(smallRacePhasePanels2)
  if (raceGateB == nil or (not roomClock.unifiedWorldBoards and
    (raceDisplayRoot == nil or not phasePanelsReady or smallRaceDisplayRoot == nil or not smallPhasePanelsReady
    or smallRaceDisplayRoot2 == nil or not smallPhasePanels2Ready)))
    and Time.time >= raceSceneRetryAt then
    raceSceneRetryAt = Time.time + 1.0
    roomClock.runSafely("race scene retry", setupRaceScene)
    raceLastDisplayedSecond = -1
    if raceClockNowUnixMilliseconds ~= nil then
      roomClock.runSafely("race gate retry state", function() renderRaceState(raceState) end)
    else
      roomClock.runSafely("clock unavailable retry display", showClockUnavailable)
    end
  end
  if finishLineRoot == nil and Time.time >= finishLineRetryAt then
    finishLineRetryAt = Time.time + 1.0
    roomClock.runSafely("finish line retry", setupFinishLine)
  end
  if not roomClock.unifiedWorldBoards and (leaderboardRoot == nil or leaderboardTitle == nil or leaderboardBody == nil)
    and Time.time >= leaderboardRetryAt then
    leaderboardRetryAt = Time.time + 1.0
    roomClock.runSafely("leaderboard retry", setupLeaderboard)
  end
  local loopOk, sampledAt = roomClock.runSafely("race clock loop", function() return updateRaceLoop(false) end)
  if not loopOk then roomClock.runSafely("clock failure display", showClockUnavailable) end
  if isAuthoritativeManager() and raceState == "RACING" and sampledAt ~= nil then
    roomClock.runSafely("finish crossing update", function() updateFinishCrossings(sampledAt) end)
  end
  if isAuthoritativeManager() and raceState == "RECYCLING" and sampledAt ~= nil then
    roomClock.runSafely("pending finish retry", retryPendingFinishRecords)
    roomClock.runSafely("final leaderboard retry", finalizeRaceLeaderboard)
  end
  if leaderboardVisible and isAuthoritativeManager() and Time.time >= leaderboardResendAt then
    leaderboardResendAt = Time.time + 1.0
    roomClock.runSafely("leaderboard broadcast", broadcastLeaderboardSnapshot)
  end
  -- Fleet recycling is driven by updateRaceLoop on every client during the
  -- complete RECYCLING interval. PREPARING never resets selecting vehicles.
end

function OnDestroy()
  destroyRaceCountdownAudio()
  if raceClockSnapshot ~= nil and roomClock.snapshotChangeHandle ~= nil then
    pcall(function() raceClockSnapshot:RemoveOnValueChange(roomClock.snapshotChangeHandle) end)
    roomClock.snapshotChangeHandle = nil
  end
  if raceResultLedger ~= nil and raceLedgerChangeHandle ~= nil then
    pcall(function() raceResultLedger:RemoveOnValueChange(raceLedgerChangeHandle) end)
    raceLedgerChangeHandle = nil
  end
end
