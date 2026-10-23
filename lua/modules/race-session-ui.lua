---@id 3cb5f0e7-b1a4-4aa0-8d32-905a47bd2f26
-- 地心飞车 V1.1：发车名单锁定、14 车位整车传送、真实昵称和响应式比赛 HUD。

---@start
---@varSync raceRosterSnapshot:string
---@end

local UnityEngine = CS.UnityEngine
local Time = UnityEngine.Time
local GameObject = UnityEngine.GameObject
local Vector2 = UnityEngine.Vector2
local Vector3 = UnityEngine.Vector3
local Quaternion = UnityEngine.Quaternion
local Color = UnityEngine.Color
local DouyinActorService = CS.DouyinActorService
local DouyinPlayerService = CS.DouyinPlayerService

local MANAGER_ID = "650f9bb2-f983-4c39-9b98-456d89b19dd2"
local VALIDATOR_ID = "4fd23b49-42c5-4e32-9c41-7f364db2a421"
local SESSION_ID = "3cb5f0e7-b1a4-4aa0-8d32-905a47bd2f26"
local ECONOMY_ID = "88e3278d-79d2-421b-899d-743901bdb6c9"
local HUD_CJK_ATLAS_HEIGHT = 1224

-- BEGIN GENERATED NICKNAME ATLAS
local HUD_NICKNAME_CELL = 20
local HUD_NICKNAME_BYTES_PER_GLYPH = 50
-- END GENERATED NICKNAME ATLAS

local fleet = {
  { name = "玩具", id = "8de0f771-fd69-4eaf-9b49-0fe93a76cba0" },
  { name = "莓爆花", id = "0a670ab9-e842-4180-83ac-1ff209bfa4ec" },
  { name = "绯樱", id = "08e30626-c7ac-442b-a52e-79eeb4821174" },
  { name = "暴走", id = "4fd26fee-695e-49b9-9e3a-c4c63e32953d" },
  { name = "烈焰", id = "a617d090-9f38-484d-aae2-38cd1bc67d71" },
  { name = "赤巡", id = "ce1504dd-0a40-4a70-87e3-c8175dc6e9f2" },
  { name = "薄荷糖", id = "172fb58a-5b48-478e-9c7a-2982f1094fa4" },
  { name = "甜品", id = "8bd801fb-77a6-40e3-b3f0-213805638473" },
  { name = "牛牛", id = "d9c87464-c30a-41a9-9985-49d42295c57c" },
  { name = "牛粉", id = "0c552cb3-a257-49e9-9695-3f069a85e602" },
  { name = "积木", id = "8db8ed26-ff1d-45c6-9f00-2ffd3c72a094" },
  { name = "宝宝巴", id = "479379fa-99ea-4279-b543-57336e6305db" },
  { name = "星梦巴", id = "40b08af1-fa7d-4952-b7e1-1eab05150ca6" },
  { name = "爆米花", id = "0b177841-8cba-4955-ba76-6f773828be1c" },
  { name = "暮翼巡游", id = "pi-c01-duskwing-parade.lua" },
  { name = "甜咒南瓜", id = "pi-c02-candy-hex.lua" },
}

-- RACE-REPAIR-0905: editor components, not historical world coordinates, own poses.
local function regionPose(name, x, z, yaw, clearance)
  local floor = GameObject.Find(name)
  if floor == nil then return 0, 0, 0, 0, false end
  local t = floor.transform
  local p = t:TransformPoint(Vector3(x, 0.5, z))
  return p.x, p.y + clearance, p.z, t.eulerAngles.y + yaw, true
end

function GetRaceVehicleHomePose(vehicleName)
  for index, entry in ipairs(fleet) do
    if entry.name == tostring(vehicleName or "") then
      -- Halloween parking anchors are authored with the imported native model.
      -- Read their actual poses so GLB handedness cannot swap numbered bays.
      local bay = GameObject.Find(string.format("Halloween_SLOT_%02d", index)) or GameObject.Find(string.format("SLOT_%02d", index))
      if bay ~= nil then
        local p = bay.transform.position
        return p.x, p.y + 0.04, p.z, index <= 8 and 0 or 180, true
      end
      local column, row = (index - 1) % 8, math.floor((index - 1) / 8)
      return regionPose("选车区_红色有效区域", ((column - 3.5) * 7) / 82,
        (row == 0 and -7.5 or 7.5) / 44, row == 0 and 0 or 180, 0.04)
    end
  end
  return 0, 0, 0, 0, false
end

local fixedStartSlots = {
  {125.494921, 12.908744, 44.781924, 89.958310},
  {125.498922, 12.908744, 39.281925, 89.958310},
  {122.046288, 13.459530, 44.780189, 89.986785},
  {122.047557, 13.459530, 39.280189, 89.986785},
  {118.590764, 14.009501, 44.776618, 89.871626},
  {118.603087, 14.009501, 39.276632, 89.871626},
  {115.148805, 14.557448, 44.771656, 90.039016},
  {115.145059, 14.557448, 39.271658, 90.039016},
  {111.703927, 15.104081, 44.782592, 90.145207},
  {111.689988, 15.104081, 39.282609, 90.145207},
  {108.258319, 15.649585, 44.795374, 90.236061},
  {108.235659, 15.649585, 39.295421, 90.236061},
  {104.786156, 16.191957, 44.788449, 89.773694},
  {104.807880, 16.191957, 39.288492, 89.773694},
  {101.357214, 16.681073, 44.789979, 90.212069},
  {101.336857, 16.681073, 39.290017, 90.212069},
}
function GetRaceSessionStartSlot(index)
  index = math.floor(tonumber(index) or 0)
  local p = fixedStartSlots[index]
  if p == nil then return 0, 0, 0, 0, false end
  return p[1], p[2], p[3], p[4], true
end

local managerHolder, validatorHolder, economyHolder = nil, nil, nil
local rosterByVehicle, rosterCycleId, rosterRevision = {}, 0, 0
local lastObservedState, lastStagedCycleId = "", 0
local stageAttemptAt, lastRosterPayload = {}, ""
local playerRefsByActorId, actorRefs, currentActorIdByOpenId = {}, {}, {}
local namesByActorId, namesByOpenId = {}, {}
local hudRoot, hudSafeRect, hudScaler, hudPanelSprite, hudPanelTexture, hudRoundSprite, hudRoundTexture = nil, nil, nil, nil, nil, nil, nil
local hudCjkAtlasTexture, hudCjkSprites = nil, nil
local hudNicknameGlyphBytes, hudNicknameGlyphIndex, hudNicknameSprites, hudNicknameTextures = nil, nil, {}, {}
local hudPhase, hudTimer, hudRank, hudCoins = nil, nil, nil, nil
local hudPhaseImages, hudNoResultsImage = {}, nil
local hudAppearanceButton, hudShopButton = nil, nil
local hudStatusRoot, hudAppearanceRoot, hudShopRoot = nil, nil, nil
local commerceRoot, sponsorPromptRoot = nil, nil
local resultsRoot, resultsTitle, resultsRows = nil, nil, {}
local hudPhaseAccent, hudRankAccent, hudTimerGlow, resultsPanelRect = nil, nil, nil, nil
local resultsVisibleCount = 8
local hudRects = nil
local lastLayoutKey, lastHudKey, lastResultsKey = "", "", ""
local hudQaResultsVisible, hudQaResultsHidden = false, false
local hudQaState, hudQaRemaining, hudQaRank, hudQaParticipants, hudQaCoins = nil, nil, nil, nil, nil
local hudCoinSnapshot = "读取中"
local zoneVisualRoot = nil
local nextIdentityMaintenanceAt, nextHudUpdateAt, nextEconomyUpdateAt = 0, 0, 0
local rosterChangeHandle = nil
local hudUi = {
  grid = 4,
  primaryFont = 12,
  labelFont = 12,
  tableFont = 12,
  primaryLine = 44,
  labelLine = 42,
  iconSize = 30,
  actionWidth = 144,
  actionHeight = 72,
  nicknameGlyphWidth = 12,
  nicknameGlyphHeight = 20,
  touchHeight = 56,
  resultsHasFinishers = false,
  dismissedResultsCycleId = 0,
  stagingWallColliders = {},
  stagingWallCollisionEnabled = nil,
  stagingCollisionError = "",
  seatInputGuard = { locked=false, error="", holders={} },
  uiListeners = {},
  inputListeners = {},
  commerceMode = "closed",
  currentRaceState = "",
  economyAvailable = false,
  economyInitialized = false,
  economyCoins = 0,
  economyInventory = {},
  economyEquipped = {},
  economyCatalog = {
    WING_01 = { category = "wing", price = 500 },
    HALO_01 = { category = "halo", price = 800 },
  },
  sponsorAvailable = false,
  sponsorEnabled = false,
  sponsorFrozen = false,
  sponsorEligible = false,
  sponsorEntryVisible = false,
  sponsorReadiness = "SYNCING",
  sponsorReadError = "none",
  sponsorTotal = 0,
  sponsorRevision = 0,
  sponsorPersonal = 0,
  sponsorCycleId = 0,
  sponsorAmount = 100,
  lastCommerceMessage = "",
  panelTitleGlyph = 12,
  panelLabelGlyph = 12,
  panelBodyGlyph = 11,
  panelValueFont = 12,
  panelLine = 28,
  astraRevision = "MOBILE-V10-WORLD-CARDS-20260912",
}

local function handleResultsClose()
  if hudUi.dismissResults ~= nil then hudUi.dismissResults() end
end
hudUi.resultsCloseHandler = handleResultsClose

local function handleAppearanceOpen()
  if RaceSessionUiOpenAppearance ~= nil then RaceSessionUiOpenAppearance() end
end

local function handleShopOpen()
  if RaceSessionUiOpenShop ~= nil then RaceSessionUiOpenShop() end
end

local function handleSponsorOpen()
  if RaceSessionUiOpenSponsor ~= nil then RaceSessionUiOpenSponsor() end
end

local function handleCommerceClose()
  if hudUi.closeCommerce ~= nil then hudUi.closeCommerce() end
end

local function handleEquipTitle()
  if hudUi.equipItem ~= nil then hudUi.equipItem("title", (hudUi.economyEquipped or {}).title=="TITLE_DEFAULT" and "" or "TITLE_DEFAULT") end
end

local function handleEquipWing()
  if hudUi.equipItem ~= nil then hudUi.equipItem("wing", (hudUi.economyEquipped or {}).wing=="WING_01" and "" or "WING_01") end
end

local function handleEquipHalo()
  if hudUi.equipItem ~= nil then hudUi.equipItem("halo", (hudUi.economyEquipped or {}).halo=="HALO_01" and "" or "HALO_01") end
end

local function handleBuyWing()
  if hudUi.buyItem ~= nil then hudUi.buyItem("WING_01") end
end

local function handleBuyHalo()
  if hudUi.buyItem ~= nil then hudUi.buyItem("HALO_01") end
end

local function handleSponsorTen()
  if hudUi.submitSponsor ~= nil then hudUi.submitSponsor(10) end
end

local function handleSponsorHundred()
  if hudUi.submitSponsor ~= nil then hudUi.submitSponsor(100) end
end

local function handleSponsorFiveHundred()
  if hudUi.submitSponsor ~= nil then hudUi.submitSponsor(500) end
end

local function handleSponsorThousand()
  if hudUi.submitSponsor ~= nil then hudUi.submitSponsor(1000) end
end

local function handleSponsorFiveThousand()
  if hudUi.submitSponsor ~= nil then hudUi.submitSponsor(5000) end
end

local function handleSponsorSubmit()
  if hudUi.submitSponsor ~= nil then hudUi.submitSponsor(hudUi.sponsorAmount) end
end

local function handleSponsorAmountChanged(value)
  local amount = math.floor(tonumber(value) or 0)
  hudUi.sponsorAmount = amount
  if hudUi.refreshCommerce ~= nil then hudUi.refreshCommerce() end
end

hudUi.appearanceOpenHandler = handleAppearanceOpen
hudUi.shopOpenHandler = handleShopOpen
hudUi.sponsorOpenHandler = handleSponsorOpen
hudUi.commerceCloseHandler = handleCommerceClose
hudUi.equipTitleHandler = handleEquipTitle
hudUi.equipWingHandler = handleEquipWing
hudUi.equipHaloHandler = handleEquipHalo
hudUi.buyWingHandler = handleBuyWing
hudUi.buyHaloHandler = handleBuyHalo
hudUi.sponsorTenHandler = handleSponsorTen
hudUi.sponsorHundredHandler = handleSponsorHundred
hudUi.sponsorFiveHundredHandler = handleSponsorFiveHundred
hudUi.sponsorThousandHandler = handleSponsorThousand
hudUi.sponsorFiveThousandHandler = handleSponsorFiveThousand
hudUi.sponsorSubmitHandler = handleSponsorSubmit
hudUi.sponsorAmountHandler = handleSponsorAmountChanged

local function normalizeActorId(value)
  local number = math.floor(tonumber(value) or 0)
  return number > 0 and number or 0
end

local function actorId(actor)
  if actor == nil then return 0 end
  local ok, value = pcall(function() return actor.actorID end)
  if not ok or normalizeActorId(value) == 0 then
    ok, value = pcall(function() return actor.ID end)
  end
  if not ok or normalizeActorId(value) == 0 then
    ok, value = pcall(function() return actor.id end)
  end
  return ok and normalizeActorId(value) or 0
end

local function cleanName(value)
  value = tostring(value or "")
  value = string.gsub(value, "^%s+", "")
  value = string.gsub(value, "%s+$", "")
  if value == "" or value == "nil" or string.match(value, "^%d+_NickName$") then return "" end
  return value
end

local function playerOpenId(player)
  if player == nil then return "" end
  local ok, value = pcall(function() return player.playerOpenID end)
  return ok and tostring(value or "") or ""
end

local function playerActor(player)
  if player == nil then return nil end
  local ok, actor = pcall(function() return player:GetActor() end)
  return ok and actor or nil
end

local function resolveManagerHolders()
  if managerHolder == nil or managerHolder.script == nil then
    pcall(function() managerHolder = self.gameObject:GetDouyinScript(MANAGER_ID) end)
  end
  if validatorHolder == nil or validatorHolder.script == nil then
    pcall(function() validatorHolder = self.gameObject:GetDouyinScript(VALIDATOR_ID) end)
  end
  return managerHolder ~= nil and managerHolder.script ~= nil
end

local function resolveEconomyHolder()
  if economyHolder == nil or economyHolder.script == nil then
    pcall(function() economyHolder = self.gameObject:GetDouyinScript(ECONOMY_ID) end)
  end
  return economyHolder ~= nil and economyHolder.script ~= nil
end

-- BEGIN ROOM NICKNAME QUEUE 0920
-- Client API; only this network object's owning client may dispatch it.
-- N1 is appended to the existing roster snapshot; it never changes race seats.
do
  local n = { entries = {}, observed = {}, revision = 0, serial = "", dirty = false,
    pauseUntil = 0, nextDispatch = 0, failures = 0, active = nil, token = 0,
    wasOwner = false, dead = false, nextTick = 0, nextPublish = 0,
    stats = { requests = 0, successes = 0, failures = 0, timeouts = 0, stale = 0 } }
  hudUi.identity = n
  function n.owner()
    local ok, owned = pcall(function() return self:HasOwnership() end)
    return not n.dead and ok and owned == true
  end
  function n.now()
    local ok, value = pcall(function() return tonumber(DouyinUtility.GetServerUnixTime()) end)
    if ok and value and value > 0 and value < math.huge then return value end
    return nil -- Never schedule shared deadlines from unrelated local uptimes.
  end
  function n.hex(value)
    return (tostring(value or ""):gsub(".", function(c) return string.format("%02x", string.byte(c)) end))
  end
  function n.unhex(value)
    if #value % 2 ~= 0 or value:find("[^%da-f]") then return nil end
    return (value:gsub("..", function(c) return string.char(tonumber(c, 16)) end))
  end
  function n.redraw()
    lastHudKey, lastResultsKey = "", ""
    if resolveManagerHolders() and managerHolder.script.RaceManagerRefreshLeaderboardPresentation then
      pcall(function() managerHolder.script.RaceManagerRefreshLeaderboardPresentation() end)
    end
  end
  function n.import(serial)
    if serial == nil or serial == "" then return true end
    local rev, pause, dispatch, failures, rows = serial:match("^N1,(%d+),(%d+),(%d+),(%d+);(.*)$")
    rev, pause, dispatch, failures = tonumber(rev), tonumber(pause), tonumber(dispatch), tonumber(failures)
    if not rev or rev < n.revision then return false end
    if rev == n.revision then return serial == n.serial end
    local entries = {}
    for row in (rows .. ";"):gmatch("([^;]+);") do
      local key, name, fallback, attempts, status, due = row:match("^([%da-f]+),([%da-f]*),([%da-f]*),(%d+),([qpdf]),(%d+)$")
      if not key then return false end
      key, name, fallback = n.unhex(key), n.unhex(name), n.unhex(fallback)
      attempts, due = tonumber(attempts), tonumber(due)
      if not key or key == "" or not name or not fallback or attempts > 4 or entries[key]
        or (status == "p" and attempts == 0) or (status == "d" and name == "") then return false end
      entries[key] = { name = name, fallback = fallback, attempts = attempts, status = status, due = due }
    end
    n.entries, n.revision, n.serial = entries, rev, serial
    n.pauseUntil, n.nextDispatch, n.failures, n.dirty = pause, dispatch, failures, false
    for key, row in pairs(entries) do
      if row.name ~= "" then namesByOpenId[key] = row.name end
      local id = currentActorIdByOpenId[key]
      if id and (row.name ~= "" or row.fallback ~= "") then
        namesByActorId[id] = row.name ~= "" and row.name or row.fallback
      end
    end
    n.redraw()
    return true
  end
  function n.split(payload)
    local base, serial = tostring(payload or ""):match("^(.-)|(%s*N1,.*)$")
    return base or tostring(payload or ""), serial
  end
  function n.hydrate()
    if raceRosterSnapshot == nil then return false end
    local ok, payload = pcall(function() return raceRosterSnapshot:GetValue() end)
    if not ok then return false end
    local _, serial = n.split(payload)
    return n.import(serial)
  end
  function n.attach(base)
    return n.serial ~= "" and (base .. "|" .. n.serial) or base
  end
  function n.publish(now)
    if not n.dirty then return true end
    if not n.owner() or raceRosterSnapshot == nil or now < n.nextPublish then return false end
    n.nextPublish = now + 2
    local ok, raw = pcall(function() return raceRosterSnapshot:GetValue() end)
    if not ok then return false end
    local base, previous = n.split(raw)
    if previous and previous ~= n.serial then
      if not n.import(previous) then return false end
      return false -- Hydrate first; do not overwrite another owner's newer state.
    end
    if base == "" then
      local cells = { "G2", "0", "0" }
      for _ = 1, #fleet do cells[#cells + 1] = "0~" end
      base = table.concat(cells, "|")
    end
    local keys, rows = {}, {}
    for key in pairs(n.entries) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
      local row = n.entries[key]
      rows[#rows + 1] = table.concat({ n.hex(key), n.hex(row.name), n.hex(row.fallback),
        row.attempts, row.status, math.ceil(row.due) }, ",")
    end
    local serial = table.concat({ "N1", n.revision + 1, math.ceil(n.pauseUntil),
      math.ceil(n.nextDispatch), n.failures }, ",") .. ";" .. table.concat(rows, ";")
    local payload = base .. "|" .. serial
    local sent = pcall(function() raceRosterSnapshot:SetValue(payload) end)
    local read, confirmed = pcall(function() return raceRosterSnapshot:GetValue() end)
    if not sent or not read or confirmed ~= payload then return false end
    n.import(serial)
    n.dirty = false
    return true
  end
  function n.observe(key, fallback)
    if key == "" then return end
    n.observed[key] = fallback
    if not n.wasOwner or not n.owner() then return end
    local row = n.entries[key]
    if not row then
      n.entries[key] = { name = namesByOpenId[key] or "", fallback = fallback,
        attempts = 0, status = namesByOpenId[key] and "d" or "q", due = 0 }
      n.dirty = true
    elseif fallback ~= "" and row.fallback ~= fallback then
      row.fallback, n.dirty = fallback, true
    end
  end
  function n.fail(key, now, rateLimited, timedOut)
    local row = n.entries[key]
    if not row then return end
    n.active = nil
    n.failures = n.failures + 1
    n.stats.failures = n.stats.failures + 1
    if timedOut then n.stats.timeouts = n.stats.timeouts + 1 end
    local delays = { 5, 15, 60 }
    row.status = row.attempts >= 4 and "f" or "q"
    row.due = row.status == "f" and 0 or now + delays[row.attempts]
    if rateLimited or n.failures >= 3 then n.pauseUntil = math.max(n.pauseUntil, now + 60) end
    n.dirty = true
  end
  function n.isRateLimited(value)
    local text = string.lower(tostring(value or ""))
    return text:find("429", 1, true) or text:find("rate limit", 1, true)
      or text:find("throttl", 1, true) or text:find("too many", 1, true)
      or text:find("限流", 1, true) or text:find("频率", 1, true)
  end
  function n.invalidate()
    n.token, n.active, n.wasOwner = n.token + 1, nil, false
  end
  function n.tick()
    if n.dead or Time.unscaledTime < n.nextTick then return end
    n.nextTick = Time.unscaledTime + 0.2
    if not n.owner() then
      if n.wasOwner then n.invalidate() end
      return
    end
    local now = n.now()
    if not now or not n.hydrate() then return end
    if not n.wasOwner then
      n.wasOwner = true
      for key, fallback in pairs(n.observed) do n.observe(key, fallback) end
    end
    -- Preserve pending attempts/deadlines on host migration; never reissue immediately.
    for key, row in pairs(n.entries) do
      if row.status == "p" and now >= row.due then
        n.token = n.token + 1
        n.fail(key, now, false, true)
        break
      end
    end
    if not n.publish(now) or n.active or now < n.pauseUntil or now < n.nextDispatch then return end
    -- A pending call inherited from the old owner also occupies the single logical slot.
    for _, row in pairs(n.entries) do if row.status == "p" then return end end
    if DouyinUserService == nil then return end
    local key, earliest = nil, math.huge
    for candidate, row in pairs(n.entries) do
      if n.observed[candidate] ~= nil and row.status == "q" and row.attempts < 4 and row.due <= now then
        if row.due < earliest or (row.due == earliest and (not key or candidate < key)) then
          key, earliest = candidate, row.due
        end
      end
    end
    if not key then return end
    local row = n.entries[key]
    row.attempts, row.status, row.due = row.attempts + 1, "p", now + 10
    n.nextDispatch, n.dirty, n.nextPublish = now + 2, true, 0
    -- Persist the attempt BEFORE calling the API, including its timeout and retry budget.
    if not n.publish(now) or not n.owner() then return end
    n.token = n.token + 1
    local token, attempt = n.token, n.entries[key].attempts
    n.active = { key = key, token = token }
    n.stats.requests = n.stats.requests + 1
    local function completed(info, failure)
      local at = n.now()
      if n.dead or not n.owner() or token ~= n.token or not n.active or n.active.token ~= token then
        n.stats.stale = n.stats.stale + 1
        return
      end
      local current = n.entries[key]
      if not at or not current or current.status ~= "p" or current.attempts ~= attempt then return end
      if at >= current.due then
        n.token = n.token + 1
        n.fail(key, at, false, true)
        return
      end
      local valid, resolved = pcall(function() return info and cleanName(info.name) or "" end)
      if valid and resolved ~= "" then
        current.name, current.status, current.due = resolved, "d", 0
        namesByOpenId[key] = resolved
        local id = currentActorIdByOpenId[key]
        if id then namesByActorId[id] = resolved end
        n.active, n.failures, n.dirty = nil, 0, true
        n.stats.successes = n.stats.successes + 1
        n.redraw()
      else
        n.fail(key, at, n.isRateLimited(failure), false)
      end
    end
    local ok, failure = pcall(function() DouyinUserService.GetUserInfo(key, completed) end)
    if not ok then completed(nil, failure) end
  end
end
-- END ROOM NICKNAME QUEUE 0920

local function observeIdentity(player, actor)
  local id = actorId(actor)
  if player == nil then return false end
  local openId = playerOpenId(player)
  local ok, fallback = pcall(function() return player.playerName end)
  fallback = ok and cleanName(fallback) or ""
  if id > 0 then
    actorRefs[id], playerRefsByActorId[id] = actor, player
    if openId ~= "" then currentActorIdByOpenId[openId] = id end
    if fallback ~= "" then namesByActorId[id] = fallback end
  end
  -- Join can precede Actor spawn: enqueue the identity without requiring an Actor.
  hudUi.identity.observe(openId, fallback)
  return true
end

local function displayName(id)
  id = normalizeActorId(id)
  local player = playerRefsByActorId[id]
  local openId = playerOpenId(player)
  local value = openId ~= "" and cleanName(namesByOpenId[openId]) or ""
  if value ~= "" then return value end
  value = cleanName(namesByActorId[id])
  if value ~= "" then return value end
  local ok, fallback = pcall(function() return player ~= nil and player.playerName or nil end)
  fallback = ok and cleanName(fallback) or ""
  if fallback ~= "" then return fallback end
  return "玩家" .. tostring(id)
end

local function refreshRoomIdentities()
  if DouyinPlayerService ~= nil and DouyinPlayerService.GetPlayers ~= nil then
    local got,players=pcall(function() return DouyinPlayerService.GetPlayers() end)
    if got and players~=nil then
      for index=0,players.Length-1 do
        local player=players[index]
        observeIdentity(player,playerActor(player))
      end
    end
  end
  if DouyinActorService == nil then return end
  local ok, actors = pcall(function() return DouyinActorService.GetActors() end)
  if not ok or actors == nil then return end
  for index = 0, actors.Length - 1 do
    local actor = actors[index]
    local id = actorId(actor)
    if id > 0 then
      actorRefs[id] = actor
      local openId = ""
      pcall(function() openId = tostring(actor.UID or "") end)
      local player = nil
      if DouyinPlayerService ~= nil and openId ~= "" then
        pcall(function() player = DouyinPlayerService.GetPlayerByOpenID(openId) end)
      end
      if player ~= nil then observeIdentity(player, actor) end
    end
  end
end

local function vehicleHolder(entry)
  local gameObject = GameObject.Find(entry.name)
  if gameObject == nil then return nil end
  local c01, c02 = entry.name == "暮翼巡游", entry.name == "甜咒南瓜"
  if not c01 and not c02 then
    local ok, holder = pcall(function() return gameObject:GetDouyinScript(entry.id) end)
    return ok and holder or nil
  end
  hudUi.addedFleetRuntimeHolders = hudUi.addedFleetRuntimeHolders or {}
  local function ready(holder)
    local ok, value = pcall(function()
      local api = holder ~= nil and holder.script or nil
      return api ~= nil and api.RaceSessionGetRoster ~= nil and api.RaceSessionGetSeatRoster ~= nil
        and api.RaceSessionRequestStage ~= nil and api.HasCompletedRaceSessionStage ~= nil
        and api.GetRaceSessionLocalSeatLock ~= nil
    end)
    return ok and value == true
  end
  local cached = hudUi.addedFleetRuntimeHolders[entry.name]
  if ready(cached) then return cached end
  local filename = c01 and "pi-c01-duskwing-parade.lua" or "pi-c02-candy-hex.lua"
  local actualId = c01 and "9ce147c6-0d29-4356-be45-ac57634415af" or "1a1f1fbf-d1d3-4999-81c5-3aa3ed3269b0"
  for _, candidate in ipairs({entry.id, filename, actualId}) do
    local ok, holder = pcall(function() return gameObject:GetDouyinScript(candidate) end)
    if ok and ready(holder) then hudUi.addedFleetRuntimeHolders[entry.name] = holder; return holder end
  end
  local ok, components = pcall(function() return gameObject:GetComponents(typeof(CS.DouyinScript)) end)
  if ok and components ~= nil then
    for index = 0, components.Length - 1 do
      local holder = components[index]
      if ready(holder) then hudUi.addedFleetRuntimeHolders[entry.name] = holder; return holder end
    end
  end
  hudUi.addedFleetRuntimeHolders[entry.name] = nil
  return nil
end

local function parseActorList(value)
  local result = {}
  for token in string.gmatch(tostring(value or "") .. ",", "([^,]*),") do
    local id = normalizeActorId(token)
    if id > 0 then result[#result + 1] = id end
  end
  return result
end

local function parseRoster(payload)
  local base, identities = hudUi.identity.split(payload)
  if identities then pcall(hudUi.identity.import, identities) end
  payload = base
  local parts = {}
  for part in string.gmatch(tostring(payload or ""), "([^|]+)") do parts[#parts + 1] = part end
  if #parts ~= (#fleet + 3) or (parts[1] ~= "G1" and parts[1] ~= "G2") then return false end
  local cycleId, revision = math.floor(tonumber(parts[2]) or 0), math.floor(tonumber(parts[3]) or 0)
  -- An identity-only snapshot can exist before the first race roster is locked.
  if cycleId == 0 and revision == 0 and identities then return true end
  if cycleId <= 0 or revision <= 0 then return false end
  if cycleId < rosterCycleId or (cycleId == rosterCycleId and revision < rosterRevision) then return false end
  if cycleId == rosterCycleId and revision == rosterRevision then return payload == lastRosterPayload end
  local nextRoster, seenActors = {}, {}
  for index = 1, #fleet do
    local values, driver, seatRoster = {}, 0, ""
    if parts[1] == "G2" then
      local driverToken, seats = string.match(parts[index + 3], "^(%d+)~(.*)$")
      if driverToken == nil then return false end
      driver, seatRoster = normalizeActorId(driverToken), seats
      local foundDriver, seenSeats = false, {}
      for seat, token in string.gmatch(seats .. ";", "([%w_]+):(%d+);") do
        local occupant = normalizeActorId(token)
        if seenSeats[seat] or (occupant > 0 and seenActors[occupant]) then return false end
        seenSeats[seat] = true
        if occupant > 0 then
          seenActors[occupant] = true
          if seat == "driver" then foundDriver = occupant == driver; table.insert(values, 1, occupant)
          else values[#values + 1] = occupant end
        end
      end
      if driver > 0 and not foundDriver then return false end
      if driver == 0 and #values > 0 then return false end
    else
      values = parseActorList(parts[index + 3])
      driver = values[1] or 0
    end
    nextRoster[fleet[index].name] = { driver = driver, occupants = values, seatRoster = seatRoster }
  end
  rosterByVehicle, rosterCycleId, rosterRevision = nextRoster, cycleId, revision
  lastRosterPayload = payload
  lastHudKey, lastResultsKey = "", ""
  return true
end

local function currentRosterPayload(cycleId, revision)
  local parts = { "G2", tostring(cycleId), tostring(revision) }
  for index = 1, #fleet do
    local entry, cell = fleet[index], "0~"
    local holder = vehicleHolder(entry)
    if holder ~= nil and holder.script ~= nil and holder.script.RaceSessionGetRoster ~= nil then
      local ok, driver = pcall(function() return holder.script.RaceSessionGetRoster() end)
      if ok and holder.script.RaceSessionGetSeatRoster ~= nil then
        local driverId = normalizeActorId(driver)
        local seatOk, seats = pcall(function() return holder.script.RaceSessionGetSeatRoster() end)
        if driverId > 0 and seatOk and tostring(seats or "") ~= "" then
          cell = tostring(driverId) .. "~" .. tostring(seats)
        end
      end
    end
    parts[#parts + 1] = cell
  end
  return table.concat(parts, "|")
end

local function isAuthority()
  local owned = false
  pcall(function() owned = self:HasOwnership() end)
  return owned
end

local function stageRoster(cycleId)
  if lastStagedCycleId == cycleId then return true end
  local allConfirmed = true
  for index = 1, #fleet do
    local roster = rosterByVehicle[fleet[index].name]
    if roster ~= nil and roster.driver > 0 then
      local holder = vehicleHolder(fleet[index])
      local confirmed = false
      if holder ~= nil and holder.script ~= nil and holder.script.HasCompletedRaceSessionStage ~= nil then
        local ok, value = pcall(function() return holder.script.HasCompletedRaceSessionStage(cycleId) end)
        confirmed = ok and value == true
      end
      if holder ~= nil and holder.script ~= nil and holder.script.RaceSessionRequestStage ~= nil then
        local x,y,z,yaw,valid = GetRaceSessionStartSlot(index)
        if not confirmed and valid and Time.unscaledTime >= (stageAttemptAt[index] or 0) then
          stageAttemptAt[index] = Time.unscaledTime + 0.5
          local ok, value = pcall(function()
            return holder.script.RaceSessionRequestStage(cycleId, index, x,y,z,yaw, roster.driver, roster.seatRoster)
          end)
          confirmed = ok and value == true
        end
      end
      if not confirmed then allConfirmed = false end
    end
  end
  if allConfirmed then lastStagedCycleId = cycleId end
  return allConfirmed
end

local function publishRoster(cycleId)
  if not isAuthority() or raceRosterSnapshot == nil then return false end
  local revision = rosterCycleId == cycleId and rosterRevision + 1 or 1
  local payload = currentRosterPayload(cycleId, revision)
  local ok = pcall(function() raceRosterSnapshot:SetValue(payload) end)
  if not ok then return false end
  local readOk, confirmed = pcall(function() return raceRosterSnapshot:GetValue() end)
  if not readOk or tostring(confirmed or "") ~= payload or not parseRoster(payload) then return false end
  stageRoster(cycleId)
  return true
end

function GetRaceVehicleRosterLabel(vehicleName)
  local roster = rosterByVehicle[tostring(vehicleName or "")]
  if roster == nil or roster.driver <= 0 then return tostring(vehicleName or "") end
  local names = {}
  for index = 1, #roster.occupants do names[#names + 1] = displayName(roster.occupants[index]) end
  return table.concat(names, " / ")
end

function GetRaceVehicleRosterActorIds(vehicleName)
  local roster = rosterByVehicle[tostring(vehicleName or "")]
  if roster == nil then return "" end
  local values = {}
  for index = 1, #roster.occupants do values[#values + 1] = tostring(roster.occupants[index]) end
  return table.concat(values, ",")
end

function GetRaceVehicleSessionState(vehicleName)
  local roster = rosterByVehicle[tostring(vehicleName or "")]
  return rosterCycleId, roster and roster.driver or 0, roster and roster.seatRoster or ""
end

function GetRaceVehicleFrozenSeatRoster(vehicleName)
  local roster = rosterByVehicle[tostring(vehicleName or "")]
  return roster and roster.seatRoster or ""
end

function GetRaceParticipantVehicleCount()
  local count = 0
  for _, roster in pairs(rosterByVehicle) do if roster.driver > 0 then count = count + 1 end end
  return count
end

local function localVehicleName()
  local localActor = DouyinActorService ~= nil and DouyinActorService.GetLocalActor() or nil
  local id = actorId(localActor)
  if id == 0 then return "" end
  if resolveManagerHolders() and managerHolder.script.GetRaceManagerActorWithdrawn then
    local ok,withdrawn=pcall(managerHolder.script.GetRaceManagerActorWithdrawn,id,rosterCycleId)
    if ok and withdrawn then return "" end
  end
  for index = 1, #fleet do
    local roster = rosterByVehicle[fleet[index].name]
    if roster ~= nil then
      for occupantIndex = 1, #roster.occupants do
        if roster.occupants[occupantIndex] == id then return fleet[index].name end
      end
    end
  end
  return ""
end

local function currentRank()
  local name, participantCount = localVehicleName(), GetRaceParticipantVehicleCount()
  if name == "" or participantCount == 0 then return 0, participantCount, false end
  local rows = {}
  for index = 1, #fleet do
    local roster = rosterByVehicle[fleet[index].name]
    if roster ~= nil and roster.driver > 0 then
      local finishMs, progress = -1, -1
      if resolveManagerHolders() then
        pcall(function() finishMs = tonumber(managerHolder.script.GetRaceManagerVehicleFinishMilliseconds(fleet[index].name)) or -1 end)
      end
      if validatorHolder ~= nil and validatorHolder.script ~= nil then
        pcall(function() progress = tonumber(validatorHolder.script.GetRaceRouteVehicleProgress(fleet[index].name)) or -1 end)
      end
      rows[#rows + 1] = { name = fleet[index].name, finishMs = finishMs, progress = progress, order = index }
    end
  end
  table.sort(rows, function(left, right)
    local leftFinished, rightFinished = left.finishMs >= 0, right.finishMs >= 0
    if leftFinished ~= rightFinished then return leftFinished end
    if leftFinished and left.finishMs ~= right.finishMs then return left.finishMs < right.finishMs end
    if left.progress ~= right.progress then return left.progress > right.progress end
    return left.order < right.order
  end)
  for index = 1, #rows do if rows[index].name == name then return index, participantCount, true end end
  return 0, participantCount, true
end

local function recoverLocalUnreadyActor()
  if DouyinActorService == nil or localVehicleName() ~= "" then return end
  local ok, actor = pcall(function() return DouyinActorService.GetLocalActor() end)
  if not ok or actor == nil then return end
  local position = nil
  pcall(function() position = actor.position end)
  if position == nil then pcall(function() position = actor.gameObject.transform.position end) end
  if position == nil or tonumber(position.y) >= 9.5 then return end
  local spawn = GameObject.Find("出生点")
  if spawn == nil then return end
  pcall(function() actor.position = spawn.transform.position end)
  pcall(function() actor.gameObject.transform.position = spawn.transform.position end)
end

local function resolveFont()
  -- Reuse the CJK font shipped by the engine. OS-font constructors may silently
  -- substitute a Latin font in WebGL; their requested name is not proof of coverage.
  local bundled = UnityEngine.Resources.FindObjectsOfTypeAll(typeof(UnityEngine.Font))
  for index = 0, bundled.Length - 1 do
    local font = bundled[index]
    if tostring(font.name) == "NotoSansSC-Medium" then
      font:RequestCharactersInTexture("比赛等待金币商店赞助翅膀光环阿曜小七01:23/,-",32,UnityEngine.FontStyle.Normal)
      if font:HasCharacter(CS.System.Convert.ToChar(27604)) then return font end
    end
  end
  local candidates = { "Microsoft YaHei UI", "Microsoft YaHei", "DengXian", "SimHei", "Arial Unicode MS" }
  local installed = {}
  pcall(function()
    local names = UnityEngine.Font.GetOSInstalledFontNames()
    if names == nil then return end
    for index = 0, names.Length - 1 do
      local name = tostring(names[index])
      installed[string.lower(name)] = name
    end
  end)
  local okArray, arrayFont = pcall(function()
    local fontNames = CS.System.Array.CreateInstance(typeof(CS.System.String), #candidates)
    for index = 1, #candidates do fontNames[index - 1] = installed[string.lower(candidates[index])] or candidates[index] end
    local font = UnityEngine.Font.CreateDynamicFontFromOSFont(fontNames, 64)
    font:RequestCharactersInTexture("比赛阶段距离结束当前名次金币外观商店结算车组驾驶员乘客成绩准备选车等待发车同步中", 64, UnityEngine.FontStyle.Normal)
    return font:HasCharacter(CS.System.Convert.ToChar(27604)) and font or nil
  end)
  if okArray and arrayFont ~= nil then return arrayFont end
  for _, name in ipairs(candidates) do
    local actual = installed[string.lower(name)] or name
    local ok, font = pcall(function()
      local candidate = UnityEngine.Font.CreateDynamicFontFromOSFont(actual, 64)
      candidate:RequestCharactersInTexture("比赛阶段距离结束当前名次金币外观商店结算车组驾驶员乘客成绩准备选车等待发车同步中", 64, UnityEngine.FontStyle.Normal)
      return candidate:HasCharacter(CS.System.Convert.ToChar(27604)) and candidate or nil
    end)
    if ok and font ~= nil then return font end
  end
  local ok, font = pcall(function() return UnityEngine.Resources.GetBuiltinResource(typeof(UnityEngine.Font), "Arial.ttf") end)
  return ok and font or nil
end

local function panelSprite()
  if hudPanelSprite ~= nil then return hudPanelSprite end
  local size, radius, feather = 96, 28, 1.75
  local texture = UnityEngine.Texture2D(size, size, UnityEngine.TextureFormat.RGBA32, false)
  texture.name = "Geocore_Runtime_IOS_Glass_Panel"
  texture.filterMode, texture.wrapMode = UnityEngine.FilterMode.Bilinear, UnityEngine.TextureWrapMode.Clamp
  local center, halfExtent = (size - 1) * 0.5, (size - 1) * 0.5 - 1.25
  for y = 0, size - 1 do
    for x = 0, size - 1 do
      local qx = math.abs(x - center) - (halfExtent - radius)
      local qy = math.abs(y - center) - (halfExtent - radius)
      local distance = math.sqrt(math.max(qx, 0) ^ 2 + math.max(qy, 0) ^ 2) + math.min(math.max(qx, qy), 0) - radius
      local alpha = math.max(0, math.min(1, 0.5 - distance / feather))
      texture:SetPixel(x, y, Color(1, 1, 1, alpha))
    end
  end
  texture:Apply(false, true)
  hudPanelTexture = texture
  hudPanelSprite = UnityEngine.Sprite.Create(texture, UnityEngine.Rect(0, 0, size, size), Vector2(0.5, 0.5), 100, 0, UnityEngine.SpriteMeshType.FullRect, UnityEngine.Vector4(19, 19, 19, 19))
  hudPanelSprite.name = "Geocore_Runtime_IOS_Glass_Panel_Sprite"
  return hudPanelSprite
end

local function roundSprite()
  if hudRoundSprite ~= nil then return hudRoundSprite end
  local size, center, inner, outer = 96, 47.5, 45.7, 47.25
  local texture = UnityEngine.Texture2D(size, size, UnityEngine.TextureFormat.RGBA32, false)
  texture.name = "Geocore_Runtime_Round_Shape"
  texture.filterMode, texture.wrapMode = UnityEngine.FilterMode.Bilinear, UnityEngine.TextureWrapMode.Clamp
  for y = 0, size - 1 do
    for x = 0, size - 1 do
      local dx, dy = x - center, y - center
      local distance, alpha = math.sqrt(dx * dx + dy * dy), 0
      if distance <= inner then alpha = 1 elseif distance < outer then alpha = 1 - (distance - inner) / (outer - inner) end
      texture:SetPixel(x, y, Color(1, 1, 1, alpha))
    end
  end
  texture:Apply(false, true)
  hudRoundTexture = texture
  hudRoundSprite = UnityEngine.Sprite.Create(texture, UnityEngine.Rect(0, 0, size, size), Vector2(0.5, 0.5), 100)
  hudRoundSprite.name = "Geocore_Runtime_Round_Shape_Sprite"
  return hudRoundSprite
end

-- Screen text shares a strict 12-unit cap; world-space boards explicitly restore their own scale.
hudUi.v8Font=function(size) return size>=16 and 12 or size>=13 and 11 or math.min(12,size) end
local function addText(parent, name, anchorMin, anchorMax, size, alignment)
  size=hudUi.v8Font(size)
  local object = GameObject(name)
  object.transform:SetParent(parent.transform, false)
  local rect = object:AddComponent(typeof(UnityEngine.RectTransform))
  rect.anchorMin, rect.anchorMax = anchorMin, anchorMax
  rect.offsetMin, rect.offsetMax = Vector2.zero, Vector2.zero
  local label = object:AddComponent(typeof(UnityEngine.UI.Text))
  -- Share one resolved font per HUD instead of creating OS fonts for every label.
  hudUi.font = hudUi.font or resolveFont()
  label.font, label.fontSize, label.alignment = hudUi.font, size, alignment or UnityEngine.TextAnchor.MiddleCenter
  label.color, label.raycastTarget, label.supportRichText = Color(0.96, 0.98, 1, 1), false, true
  label.resizeTextForBestFit, label.resizeTextMinSize, label.resizeTextMaxSize = false, size, size
  label.horizontalOverflow, label.verticalOverflow = UnityEngine.HorizontalWrapMode.Overflow, UnityEngine.VerticalWrapMode.Overflow
  label.fontStyle = UnityEngine.FontStyle.Normal
  return label
end

local function addImage(parent, name, anchorMin, anchorMax, offsetMin, offsetMax, color, sprite, sliced, raycast)
  local object = GameObject(name)
  object.transform:SetParent(parent.transform, false)
  local rect = object:AddComponent(typeof(UnityEngine.RectTransform))
  rect.anchorMin, rect.anchorMax = anchorMin, anchorMax
  rect.offsetMin, rect.offsetMax = offsetMin or Vector2.zero, offsetMax or Vector2.zero
  local image = object:AddComponent(typeof(UnityEngine.UI.Image))
  image.color, image.raycastTarget = color, raycast == true
  if sprite ~= nil then image.sprite = sprite end
  if sprite ~= nil then pcall(function() image.type = sliced and UnityEngine.UI.Image.Type.Sliced or UnityEngine.UI.Image.Type.Simple end) end
  return object, rect, image
end


local function addBitmapLabel(parent, name, key, anchorMin, anchorMax, color)
  -- Keep binding names for compatibility, but these are real dynamic text now.
  local copy={raceStage="比赛阶段",timeRemaining="剩余时间",currentRank="当前名次",coin="金币",
    appearance="外观",shop="商店",results="比赛结束",subtitle="本场排行榜",rank="名次",
    crew="姓名",time="用时",preparing="准备选车",waiting="等待发车",racing="比赛中",
    recycling="比赛结束",finished="已完赛",syncing="同步中",noResults="本场暂无有效完赛成绩"}
  local size=key=="results" and 24 or key=="subtitle" and 14 or (key=="rank" or key=="time" or key=="crew") and 16 or 18
  local label=addText(parent,name,anchorMin,anchorMax,size,UnityEngine.TextAnchor.MiddleLeft)
  label.text,label.color=copy[key] or "",color or Color.white
  return label.gameObject,label.rectTransform,{label=label}
end

local function utf8Codepoints(value)
  local bytes, result, index = tostring(value or ""), {}, 1
  while index <= #bytes do
    local first = string.byte(bytes, index)
    local codepoint, width = 9633, 1
    if first < 128 then
      codepoint = first
    elseif first < 224 and index + 1 <= #bytes then
      codepoint = (first - 192) * 64 + (string.byte(bytes, index + 1) - 128)
      width = 2
    elseif first < 240 and index + 2 <= #bytes then
      codepoint = (first - 224) * 4096 + (string.byte(bytes, index + 1) - 128) * 64 + (string.byte(bytes, index + 2) - 128)
      width = 3
    elseif first < 248 and index + 3 <= #bytes then
      codepoint = (first - 240) * 262144 + (string.byte(bytes, index + 1) - 128) * 4096 + (string.byte(bytes, index + 2) - 128) * 64 + (string.byte(bytes, index + 3) - 128)
      width = 4
    end
    result[#result + 1] = codepoint
    index = index + width
  end
  return result
end


local function setNicknameLabel(row,value)
  if row==nil or row.crew==nil then return end
  row.crew.supportRichText=false
  row.lastNickname=tostring(value or "")
  local parts={}
  for ch in string.gmatch(row.lastNickname,"[%z\1-\127\194-\244][\128-\191]*")do parts[#parts+1]=ch end
  local max=row.maxGlyphs or 20
  if #parts>max then
    local shown={};for i=1,math.max(1,max-1)do shown[#shown+1]=parts[i]end
    row.crew.text=table.concat(shown).."…"
  else row.crew.text=row.lastNickname end
  row.crew.horizontalOverflow=UnityEngine.HorizontalWrapMode.Overflow
  row.crew.fontSize=12
end

-- Rounded corners must be fully inside the nine-slice border, otherwise stretched
-- short buttons produce octagonal edges and streaks across the top of the panel.
hudUi.astraPanelSprite = function()
  if hudUi.astraSurfaceSprite ~= nil then return hudUi.astraSurfaceSprite end
  local size,radius=48,10
  local texture=UnityEngine.Texture2D(size,size,UnityEngine.TextureFormat.RGBA32,false)
  texture.name="Geocore_Astra_Rounded_Surface"
  texture.filterMode,texture.wrapMode=UnityEngine.FilterMode.Bilinear,UnityEngine.TextureWrapMode.Clamp
  for y=0,size-1 do for x=0,size-1 do
    local qx,qy=math.abs(x-23.5)-12.5,math.abs(y-23.5)-12.5
    local d=math.sqrt(math.max(qx,0)^2+math.max(qy,0)^2)+math.min(math.max(qx,qy),0)-radius
    texture:SetPixel(x,y,Color(1,1,1,math.max(0,math.min(1,0.5-d/1.5))))
  end end
  texture:Apply(false,true)
  hudUi.astraSurfaceTexture=texture
  hudUi.astraSurfaceSprite=UnityEngine.Sprite.Create(texture,UnityEngine.Rect(0,0,size,size),Vector2(0.5,0.5),100,0,UnityEngine.SpriteMeshType.FullRect,UnityEngine.Vector4(12,12,12,12))
  return hudUi.astraSurfaceSprite
end

local addRoot

local function addGlyphLine(parent, name, glyphSize, color, alignment, maxGlyphs)
  local root, rect = addRoot(parent, name, false)
  local native=addText(root,name.."_Text",Vector2.zero,Vector2.one,glyphSize or hudUi.panelBodyGlyph,UnityEngine.TextAnchor.MiddleLeft)
  native.color=color or Color(0.94,0.97,1,1)
  return {
    root = root,
    rect = rect,
    glyphSize = glyphSize or hudUi.panelBodyGlyph,
    advance = (glyphSize or hudUi.panelBodyGlyph) * 0.86,
    color = color or Color(0.94, 0.97, 1, 1),
    alignment = alignment or "left",
    maxGlyphs = maxGlyphs or 24,
    objects = {},
    value = nil,
    native = native,
  }
end

local function setGlyphLine(line,value)
  if line==nil or line.native==nil then return end
  line.value=tostring(value or "")
  line.native.text=line.value
  line.native.fontSize=hudUi.v8Font(line.glyphSize or hudUi.panelBodyGlyph)
  line.native.color=line.color
  line.native.alignment=line.alignment=="center" and UnityEngine.TextAnchor.MiddleCenter or line.alignment=="right" and UnityEngine.TextAnchor.MiddleRight or UnityEngine.TextAnchor.MiddleLeft
end

addRoot = function(parent, name, interactive)
  local object = GameObject(name)
  object.transform:SetParent(parent.transform, false)
  local rect = object:AddComponent(typeof(UnityEngine.RectTransform))
  local image = object:AddComponent(typeof(UnityEngine.UI.Image))
  image.color, image.raycastTarget = Color(0, 0, 0, 0), interactive == true
  return object, rect
end

-- UI02: a shared low-resolution scene pyramid, never a screenshot of the HUD.
-- Only the underlying scene is sampled; text is drawn afterwards at native DPI.
hudUi.glassViews = {}
hudUi.glassTick = function()
  if Time.unscaledTime < (hudUi.nextGlassAt or 0) then return end
  hudUi.nextGlassAt=Time.unscaledTime+0.12
  local ok,err=pcall(function()
    local source=UnityEngine.Shader.GetGlobalTexture("_CameraColorTexture")
    if source==nil or source.width<2 then return end
    local aspect=UnityEngine.Screen.height/UnityEngine.Screen.width
    if hudUi.glassRT~=nil and math.abs(aspect-(hudUi.glassAspect or aspect))>0.02 then
      for _,rt in ipairs(hudUi.glassRT)do rt:Release();UnityEngine.Object.Destroy(rt)end
      hudUi.glassRT=nil
    end
    if hudUi.glassRT==nil then
      hudUi.glassAspect=aspect
      hudUi.glassRT={}
      for _,w in ipairs({256,128,64,32})do
        local h=math.max(16,math.floor(w*UnityEngine.Screen.height/UnityEngine.Screen.width))
        local rt=UnityEngine.RenderTexture(w,h,0)
        rt.name="Geocore_UI02_SceneBlur_"..w
        rt.filterMode=UnityEngine.FilterMode.Bilinear
        rt.wrapMode=UnityEngine.TextureWrapMode.Clamp
        rt:Create()
        hudUi.glassRT[#hudUi.glassRT+1]=rt
      end
    end
    for _,rt in ipairs(hudUi.glassRT)do UnityEngine.Graphics.Blit(source,rt);source=rt end
    for _,view in ipairs(hudUi.glassViews)do
      if view.root.activeInHierarchy then
        local rect=view.rect
        local a=UnityEngine.RectTransformUtility.WorldToScreenPoint(nil,rect:TransformPoint(Vector3(rect.rect.xMin,rect.rect.yMin,0)))
        local b=UnityEngine.RectTransformUtility.WorldToScreenPoint(nil,rect:TransformPoint(Vector3(rect.rect.xMax,rect.rect.yMax,0)))
        view.raw.texture=source
        view.raw.uvRect=UnityEngine.Rect(a.x/UnityEngine.Screen.width,a.y/UnityEngine.Screen.height,(b.x-a.x)/UnityEngine.Screen.width,(b.y-a.y)/UnityEngine.Screen.height)
        view.raw.color=Color(0.55,0.57,0.60,1)
      end
    end
    hudUi.glassAvailable=true
  end)
  if not ok then hudUi.glassError=tostring(err) end
end

hudUi.sheenSprite = function()
  if hudUi.sheen~=nil then return hudUi.sheen end
  local t=UnityEngine.Texture2D(4,128,UnityEngine.TextureFormat.RGBA32,false)
  for y=0,127 do for x=0,3 do t:SetPixel(x,y,Color(1,1,1,(y/127)^2))end end
  t.filterMode,t.wrapMode=UnityEngine.FilterMode.Bilinear,UnityEngine.TextureWrapMode.Clamp
  t:Apply(false,true)
  hudUi.sheenTexture=t
  hudUi.sheen=UnityEngine.Sprite.Create(t,UnityEngine.Rect(0,0,4,128),Vector2(0.5,0.5),100)
  return hudUi.sheen
end

local function addGlass(parent,name,interactive,accentColor)
  local root,rect=addRoot(parent,name,interactive)
  local panel=hudUi.astraPanelSprite()
  local large=name=="HUD_CommercePanel" or name=="HUD_ResultsPanel" or name=="HUD_CheckInPanel" or name=="HUD_MorePanel"
  local floating=large or name=="HUD_RaceStatus" or name=="HUD_CoinChip" or name=="HUD_Appearance" or name=="HUD_Shop" or name=="HUD_Activity" or name=="HUD_More" or name=="HUD_SponsorPrompt"
  local primary=string.find(name,"_Action$")~=nil or name=="SponsorSubmit"
  if floating then
    addImage(root,name.."_Shadow",Vector2.zero,Vector2.one,Vector2(0,-5),Vector2(0,-5),Color(0.005,0.01,0.02,0.22),panel,true,false)
  end
  local rim=select(1,addImage(root,name.."_OuterHighlight",Vector2.zero,Vector2.one,Vector2.zero,Vector2.zero,Color(0.69,0.74,0.81,floating and 0.18 or 0.08),panel,true,false))
  if floating then
    local clip,clipRect=addImage(rim,name.."_BlurMask",Vector2.zero,Vector2.one,Vector2(1,1),Vector2(-1,-1),Color.white,panel,true,false)
    local mask=clip:AddComponent(typeof(UnityEngine.UI.Mask));mask.showMaskGraphic=false
    local rawRoot=GameObject(name.."_SceneBlur")
    rawRoot.transform:SetParent(clip.transform,false)
    local rawRect=rawRoot:AddComponent(typeof(UnityEngine.RectTransform))
    rawRect.anchorMin,rawRect.anchorMax,rawRect.offsetMin,rawRect.offsetMax=Vector2.zero,Vector2.one,Vector2.zero,Vector2.zero
    local raw=rawRoot:AddComponent(typeof(UnityEngine.UI.RawImage));raw.raycastTarget=false;raw.color=Color(0.08,0.12,0.19,1)
    hudUi.glassViews[#hudUi.glassViews+1]={root=root,rect=clipRect,raw=raw}
  end
  local tint=primary and Color(0.80,0.55,0.22,1) or floating and Color(0.018,0.028,0.044,large and 0.87 or 0.91) or Color(0.064,0.075,0.096,0.70)
  local surface=select(1,addImage(rim,name.."_ObsidianGlass",Vector2.zero,Vector2.one,Vector2(1,1),Vector2(-1,-1),tint,panel,true,interactive))
  local mask=surface:AddComponent(typeof(UnityEngine.UI.Mask));mask.showMaskGraphic=true
  addImage(surface,name.."_SoftSheen",Vector2.zero,Vector2.one,Vector2.zero,Vector2.zero,Color(0.75,0.80,0.87,primary and 0.035 or floating and 0.04 or 0.015),hudUi.sheenSprite(),false,false)
  local _,line=addImage(surface,name.."_TopHairline",Vector2(0,1),Vector2(1,1),Vector2(12,-1),Vector2(-12,0),Color(0.90,0.96,1,floating and 0.18 or 0.07),nil,false,false)
  local _,_,accent=addImage(surface,name.."_LavaAccent",Vector2.zero,Vector2.zero,Vector2.zero,Vector2.zero,Color(1,0.64,0.24,1),nil,false,false)
  return root,rect,surface,accent
end

local function addDivider(parent, x)
  local _, rect = addImage(parent, "Divider_" .. tostring(x), Vector2(x, 0.18), Vector2(x + 0.0015, 0.82), Vector2.zero, Vector2.zero, Color(0.90, 0.96, 1, 0.16), nil, false, false)
  return rect
end

local function addIconBar(parent, name, anchorMin, anchorMax, color, rotation)
  local object = select(1, addImage(parent, name, anchorMin, anchorMax, Vector2.zero, Vector2.zero, color, panelSprite(), true, false))
  if rotation ~= nil and rotation ~= 0 then object.transform.localEulerAngles = Vector3(0, 0, rotation) end
  return object
end

local function addFlagIcon(parent, name, anchorMin, anchorMax, color)
  local root, rect = addRoot(parent, name, false)
  rect.anchorMin, rect.anchorMax, rect.offsetMin, rect.offsetMax = anchorMin, anchorMax, Vector2.zero, Vector2.zero
  addIconBar(root, "Pole", Vector2(0.20, 0.14), Vector2(0.30, 0.86), color)
  addIconBar(root, "Flag", Vector2(0.30, 0.52), Vector2(0.82, 0.80), color)
  addIconBar(root, "Foot", Vector2(0.10, 0.10), Vector2(0.48, 0.20), color)
  return root
end

local function addClockIcon(parent, name, anchorMin, anchorMax, color)
  local root, rect = addRoot(parent, name, false)
  rect.anchorMin, rect.anchorMax, rect.offsetMin, rect.offsetMax = anchorMin, anchorMax, Vector2.zero, Vector2.zero
  local outer = select(1, addImage(root, "Ring", Vector2(0.04, 0.04), Vector2(0.96, 0.96), Vector2.zero, Vector2.zero, color, roundSprite(), false, false))
  addImage(outer, "Face", Vector2.zero, Vector2.one, Vector2(2, 2), Vector2(-2, -2), Color(0.05, 0.08, 0.12, 1), roundSprite(), false, false)
  addIconBar(root, "MinuteHand", Vector2(0.47, 0.47), Vector2(0.55, 0.78), color)
  addIconBar(root, "HourHand", Vector2(0.49, 0.45), Vector2(0.73, 0.53), color)
  return root
end

local function addCoinIcon(parent, name, anchorMin, anchorMax, color)
  local root, rect = addRoot(parent, name, false)
  rect.anchorMin, rect.anchorMax, rect.offsetMin, rect.offsetMax = anchorMin, anchorMax, Vector2.zero, Vector2.zero
  local outer = select(1, addImage(root, "Outer", Vector2(0.02, 0.02), Vector2(0.98, 0.98), Vector2.zero, Vector2.zero, color, roundSprite(), false, false))
  local inner = select(1, addImage(outer, "Inner", Vector2.zero, Vector2.one, Vector2(5, 5), Vector2(-5, -5), Color(0.24, 0.12, 0.025, 1), roundSprite(), false, false))
  addImage(inner, "Core", Vector2.zero, Vector2.one, Vector2(4, 4), Vector2(-4, -4), Color(1.0, 0.66, 0.16, 0.92), roundSprite(), false, false)
  addIconBar(root, "Emboss", Vector2(0.46, 0.26), Vector2(0.55, 0.74), Color(1.0, 0.88, 0.48, 0.92))
  return root
end

local function addSparkleIcon(parent, name, anchorMin, anchorMax, color)
  local root, rect = addRoot(parent, name, false)
  rect.anchorMin, rect.anchorMax, rect.offsetMin, rect.offsetMax = anchorMin, anchorMax, Vector2.zero, Vector2.zero
  addIconBar(root, "Vertical", Vector2(0.45, 0.12), Vector2(0.55, 0.88), color)
  addIconBar(root, "Horizontal", Vector2(0.12, 0.45), Vector2(0.88, 0.55), color)
  addIconBar(root, "DiagonalA", Vector2(0.22, 0.45), Vector2(0.78, 0.55), color, 45)
  addIconBar(root, "DiagonalB", Vector2(0.22, 0.45), Vector2(0.78, 0.55), color, -45)
  return root
end

local function addShopIcon(parent, name, anchorMin, anchorMax, color)
  local root, rect = addRoot(parent, name, false)
  rect.anchorMin, rect.anchorMax, rect.offsetMin, rect.offsetMax = anchorMin, anchorMax, Vector2.zero, Vector2.zero
  local body = select(1, addImage(root, "BagBody", Vector2(0.12, 0.18), Vector2(0.88, 0.72), Vector2.zero, Vector2.zero, color, panelSprite(), true, false))
  addImage(body, "BagInset", Vector2.zero, Vector2.one, Vector2(3, 3), Vector2(-3, -3), Color(0.18, 0.085, 0.020, 1), panelSprite(), true, false)
  addIconBar(root, "HandleLeft", Vector2(0.30, 0.65), Vector2(0.38, 0.86), color)
  addIconBar(root, "HandleTop", Vector2(0.34, 0.79), Vector2(0.66, 0.87), color)
  addIconBar(root, "HandleRight", Vector2(0.62, 0.65), Vector2(0.70, 0.86), color)
  return root
end

local function configureButtonFeedback(button, surface, accent)
  if button == nil or surface == nil then return end
  button.targetGraphic, button.interactable = surface:GetComponent(typeof(UnityEngine.UI.Image)), true
  pcall(function()
    local colors = button.colors
    colors.normalColor = Color(1, 1, 1, 1)
    colors.highlightedColor = Color(1, 1, 1, 0.92)
    colors.pressedColor = accent
    colors.selectedColor = Color(1, 1, 1, 0.96)
    colors.disabledColor = Color(1, 1, 1, 1)
    colors.colorMultiplier, colors.fadeDuration = 1.0, 0.10
    button.colors = colors
  end)
end

local function bindNamedButton(button, handler)
  if button == nil or handler == nil then return end
  pcall(function() button.onClick:AddListener(handler) end)
  hudUi.uiListeners[#hudUi.uiListeners + 1] = { button = button, handler = handler }
end

local function bindNamedInput(input, handler)
  if input == nil or handler == nil then return end
  pcall(function() input.onEndEdit:AddListener(handler) end)
  hudUi.inputListeners[#hudUi.inputListeners + 1] = { input = input, handler = handler }
end

local function addCommerceButton(parent, name, accent, handler)
  local root, rect, core = addGlass(parent, name, true, accent)
  local button = root:AddComponent(typeof(UnityEngine.UI.Button))
  configureButtonFeedback(button, core, Color(accent.r, accent.g, accent.b, 0.82))
  bindNamedButton(button, handler)
  return root, rect, core, button
end

local function cleanupHudListeners()
  for _, entry in ipairs(hudUi.uiListeners or {}) do
    if entry.button ~= nil and entry.handler ~= nil then
      pcall(function() entry.button.onClick:RemoveListener(entry.handler) end)
      pcall(function() entry.button.onClick:RemoveAllListeners() end)
    end
  end
  for _, entry in ipairs(hudUi.inputListeners or {}) do
    if entry.input ~= nil and entry.handler ~= nil then
      pcall(function() entry.input.onEndEdit:RemoveListener(entry.handler) end)
      pcall(function() entry.input.onEndEdit:RemoveAllListeners() end)
    end
  end
  hudUi.uiListeners, hudUi.inputListeners = {}, {}
  if hudUi.resultsCloseButton ~= nil and hudUi.resultsCloseHandler ~= nil then
    pcall(function() hudUi.resultsCloseButton.onClick:RemoveListener(hudUi.resultsCloseHandler) end)
    pcall(function() hudUi.resultsCloseButton.onClick:RemoveAllListeners() end)
  end
  hudUi.resultsCloseButton = nil
end

local function setRect(rect, anchor, pivot, position, size)
  rect.anchorMin, rect.anchorMax, rect.pivot = anchor, anchor, pivot
  rect.anchoredPosition, rect.sizeDelta = position, size
end

local function setBitmapRect(rect, image, anchor, pivot, position, height, maxWidth)
  if image ~= nil and image.label ~= nil then
    setRect(rect,anchor,pivot,position,Vector2(maxWidth or 140,height))
    image.label.alignment=pivot.x==1 and UnityEngine.TextAnchor.MiddleRight or UnityEngine.TextAnchor.MiddleLeft
    return
  end
  local width = maxWidth or height
  if image ~= nil and image.sprite ~= nil and image.sprite.rect.height > 0 then
    width = image.sprite.rect.width / image.sprite.rect.height * height
  end
  if maxWidth ~= nil then width = math.min(width, maxWidth) end
  setRect(rect, anchor, pivot, position, Vector2(width, height))
end

hudUi.cosmeticArt = function(itemId)
  if hudUi.artSprites==nil then
    hudUi.artSprites={}
    local ok,err=pcall(function()
      local bytes=CS.System.Convert.FromBase64String("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")
      local texture=UnityEngine.Texture2D(2,2,UnityEngine.TextureFormat.RGBA32,false)
      local loaded=false
      pcall(function()loaded=UnityEngine.ImageConversion.LoadImage(texture,bytes)==true end)
      if not loaded then pcall(function()loaded=UnityEngine.ImageConversion.LoadImage(texture,bytes,false)==true end)end
      if not loaded then pcall(function()loaded=texture:LoadImage(bytes)==true end)end
      if not loaded then error("cosmetic illustration load failed")end
      texture.name="Geocore_UI02_Cosmetic_Concept_Art"
      texture.filterMode,texture.wrapMode=UnityEngine.FilterMode.Bilinear,UnityEngine.TextureWrapMode.Clamp
      hudUi.artTexture=texture
      local half=math.floor(texture.width/2)
      hudUi.artSprites.WING_01=UnityEngine.Sprite.Create(texture,UnityEngine.Rect(0,0,half,texture.height),Vector2(0.5,0.5),100)
      hudUi.artSprites.HALO_01=UnityEngine.Sprite.Create(texture,UnityEngine.Rect(half,0,half,texture.height),Vector2(0.5,0.5),100)
    end)
    if not ok then hudUi.artError=tostring(err);UnityEngine.Debug.LogWarning("Geocore UI art: "..tostring(err))end
  end
  return hudUi.artSprites[itemId]
end

-- VETERAN-DRIVER-V1: native text/vector insignia; no blurred text bitmap.
hudUi.createVeteranBadge = function(parent, name)
  local root,rect=addRoot(parent,name,false)
  local gold=Color(0.94,0.76,0.43,1)
  local rim=select(1,addImage(root,name.."_GoldRim",Vector2.zero,Vector2.one,Vector2.zero,Vector2.zero,gold,hudUi.astraPanelSprite(),true,false))
  local core=select(1,addImage(rim,name.."_Obsidian",Vector2.zero,Vector2.one,Vector2(1.5,1.5),Vector2(-1.5,-1.5),Color(0.045,0.073,0.11,0.98),hudUi.astraPanelSprite(),true,false))
  addImage(core,name.."_Sheen",Vector2.zero,Vector2.one,Vector2.zero,Vector2.zero,Color(0.85,0.72,0.48,0.15),hudUi.sheenSprite(),false,false)
  for side=-1,1,2 do for feather=1,3 do
    local x=side<0 and 0.026 or 0.875
    addIconBar(core,name.."_Wing"..side..feather,Vector2(x,0.23+feather*0.10),Vector2(x+0.095,0.258+feather*0.10),gold,side*18)
  end end
  local wheel,wr=addRoot(core,name.."_SteeringWheel",false)
  setRect(wr,Vector2(0.17,0.5),Vector2(0.5,0.5),Vector2.zero,Vector2(26,26))
  local ring=select(1,addImage(wheel,"GoldRing",Vector2.zero,Vector2.one,Vector2.zero,Vector2.zero,gold,roundSprite(),false,false))
  addImage(ring,"HubFace",Vector2.zero,Vector2.one,Vector2(2,2),Vector2(-2,-2),Color(0.045,0.073,0.11,1),roundSprite(),false,false)
  addIconBar(wheel,"SpokeH",Vector2(0.12,0.46),Vector2(0.88,0.54),gold)
  addIconBar(wheel,"SpokeV",Vector2(0.46,0.10),Vector2(0.54,0.54),gold)
  local label=addText(core,name.."_Name",Vector2(0.28,0.18),Vector2(0.86,0.87),26,UnityEngine.TextAnchor.MiddleCenter)
  label.text,label.color="老司机",Color(1,0.95,0.81,1)
  local rule=select(1,addImage(core,"LowerGoldRule",Vector2(0.31,0.17),Vector2(0.83,0.19),Vector2.zero,Vector2.zero,Color(0.94,0.76,0.43,0.62),nil,false,false))
  return {root=root,rect=rect,label=label,wheelRect=wr}
end

local function addCommerceCard(parent, name, accent, categoryLabel, itemId, displayName, actionHandler)
  local root, rect, core = addGlass(parent, name, false, accent)
  local category = addGlyphLine(core, name .. "_Category", hudUi.panelLabelGlyph, Color(0.88, 0.94, 1, 1), "left", 8)
  setGlyphLine(category, categoryLabel)
  local idText = addText(core, name .. "_ItemId", Vector2.zero, Vector2.zero, hudUi.panelValueFont or 26, UnityEngine.TextAnchor.MiddleLeft)
  idText.text, idText.color = "", Color(0.82, 0.90, 1.0, 1)
  local itemName = addGlyphLine(core, name .. "_DisplayName", hudUi.panelLabelGlyph, Color(0.82, 0.90, 1.0, 1), "left", 16)
  itemName.advance = 19
  setGlyphLine(itemName, tostring(displayName or itemId or "--"))
  local status = addGlyphLine(core, name .. "_Status", hudUi.panelBodyGlyph, Color(1.0, 0.76, 0.34, 1), "left", 14)
  local priceText = addText(core, name .. "_Price", Vector2.zero, Vector2.zero, hudUi.panelValueFont or 26, UnityEngine.TextAnchor.MiddleLeft)
  priceText.text, priceText.color = "", Color(1.0, 0.82, 0.42, 1)
  local actionRoot, actionRect, actionCore, actionButton
  if actionHandler ~= nil then
    actionRoot, actionRect, actionCore, actionButton = addCommerceButton(core, name .. "_Action", accent, actionHandler)
  else
    actionRoot, actionRect, actionCore = addGlass(core, name .. "_ActionUnavailable", false, Color(0.32, 0.38, 0.48, 0.38))
  end
  local actionLabel = addGlyphLine(actionCore, name .. "_ActionLabel", hudUi.panelBodyGlyph, Color(0.96, 0.98, 1, 1), "center", 8)
  local icon,iconRect = addRoot(core,name.."_CategoryIcon",false)
  local _,_,iconTile=addImage(icon,"Tile",Vector2.zero,Vector2.one,Vector2.zero,Vector2.zero,Color(accent.r*0.18,accent.g*0.18,accent.b*0.18,1),panelSprite(),true,false)
  if itemId == "HALO_01" then
    addClockIcon(icon,"HaloSymbol",Vector2(0.18,0.18),Vector2(0.82,0.82),accent)
  elseif itemId == "WING_01" then
    for side=-1,1,2 do for feather=1,3 do
      local x=side<0 and 0.10 or 0.55
      addIconBar(icon,"WingFeather"..side..feather,Vector2(x,0.22+feather*0.12),Vector2(x+0.34,0.28+feather*0.12),accent,side*(18+feather*10))
    end end
  else addFlagIcon(icon,"TitleSymbol",Vector2(0.18,0.18),Vector2(0.82,0.82),accent) end
  local artRoot,artRect,artImage=addImage(core,name.."_Artwork",Vector2.zero,Vector2.zero,Vector2.zero,Vector2.zero,Color.white,hudUi.cosmeticArt(itemId),false,false)
  artImage.preserveAspect=true
  artRoot:SetActive(itemId=="WING_01" or itemId=="HALO_01")
  local veteranBadge=itemId=="TITLE_VETERAN_DRIVER" and hudUi.createVeteranBadge(core,name.."_VeteranBadge") or nil
  local concept=addGlyphLine(core,name.."_ConceptLabel",12,Color(0.65,0.73,0.85,1),"center",8)
  setGlyphLine(concept,itemId=="TITLE_DEFAULT" and "" or "外观示意")
  return {
    root = root, rect = rect, core = core,artRect=artRect,concept=concept,icon=icon,
    category = category, idText = idText, itemName = itemName, status = status, priceText = priceText,
    actionRoot = actionRoot, actionRect = actionRect, actionButton = actionButton, actionLabel = actionLabel,
    itemId = itemId, iconRect = iconRect, isShop = string.sub(name,1,4)=="Shop",veteranBadge=veteranBadge,
  }
end

local function addNumericInput(parent, name)
  local root, rect, image = addImage(parent, name, Vector2.zero, Vector2.zero, Vector2.zero, Vector2.zero,
    Color(0.060, 0.090, 0.145, 0.96), hudUi.astraPanelSprite(), true, true)
  local input = root:AddComponent(typeof(UnityEngine.UI.InputField))
  input.targetGraphic = image
  local value = addText(root, name .. "_Value", Vector2(0, 0), Vector2(1, 1), 18, UnityEngine.TextAnchor.MiddleLeft)
  value.rectTransform.offsetMin, value.rectTransform.offsetMax = Vector2(20, 0), Vector2(-20, 0)
  value.text, value.color = "100", Color(0.98, 0.98, 1, 1)
  local placeholder = addText(root, name .. "_Placeholder", Vector2(0, 0), Vector2(1, 1), 16, UnityEngine.TextAnchor.MiddleLeft)
  placeholder.rectTransform.offsetMin, placeholder.rectTransform.offsetMax = Vector2(20, 0), Vector2(-20, 0)
  placeholder.text, placeholder.color = "10 - 5000", Color(0.58, 0.64, 0.72, 0.76)
  input.textComponent, input.placeholder, input.text, input.characterLimit = value, placeholder, "100", 4
  pcall(function() input.contentType = UnityEngine.UI.InputField.ContentType.IntegerNumber end)
  bindNamedInput(input, hudUi.sponsorAmountHandler)
  return root, rect, input
end

hudUi.astraCreateScroll = function(parent,name)
  local root,rect=addRoot(parent,name,true)
  local viewport,viewportRect=addRoot(root,name.."_Viewport",true)
  viewportRect.anchorMin,viewportRect.anchorMax=Vector2.zero,Vector2.one
  viewportRect.offsetMin,viewportRect.offsetMax=Vector2.zero,Vector2.zero
  viewport:AddComponent(typeof(UnityEngine.UI.RectMask2D))
  local content,contentRect=addRoot(viewport,name.."_Content",false)
  contentRect.anchorMin,contentRect.anchorMax,contentRect.pivot=Vector2(0,1),Vector2(1,1),Vector2(0.5,1)
  contentRect.offsetMin,contentRect.offsetMax=Vector2.zero,Vector2.zero
  local scroll=root:AddComponent(typeof(UnityEngine.UI.ScrollRect))
  scroll.viewport,scroll.content=viewportRect,contentRect
  scroll.horizontal,scroll.vertical,scroll.inertia=false,true,true
  scroll.movementType=UnityEngine.UI.ScrollRect.MovementType.Clamped
  scroll.scrollSensitivity,scroll.decelerationRate=28,0.10
  return {root=root,rect=rect,content=content,contentRect=contentRect,scroll=scroll}
end

hudUi.astraLayoutScroll = function(box,x,y,width,height,contentHeight)
  setRect(box.rect,Vector2(0,1),Vector2(0,1),Vector2(x,-y),Vector2(width,height))
  box.contentRect.sizeDelta=Vector2(0,math.max(height,contentHeight))
  box.scroll.vertical=contentHeight>height+1
end

-- CheckIn7V1 is a projection of the confirmed character profile, never a second wallet.
hudUi.checkInHasBit=function(mask,day) return math.floor((tonumber(mask) or 0)/2^(day-1))%2==1 end
hudUi.closeCheckIn=function()
  hudUi.checkInOpen=false
  if hudUi.checkInRoot then hudUi.checkInRoot:SetActive(false) end
  if hudUi.updateSponsorPrompt then hudUi.updateSponsorPrompt() end
  return true
end
-- The routes below are copied from the verified Blade Valley world portal.
-- Keep IDs as strings: platform world IDs must never pass through float formatting.
hudUi.more={open=false,busy=false,routes={
  {key="Desert",name="漠日飞车",id="8785592519170",subtitle="沙海竞速 · 穿越赤岩峡谷",color=Color(.98,.67,.29,1),displayOnly=true},
  {key="Love",name="爱心飞车",id="9080998290178",subtitle="浪漫海岛 · 一起飞驰",color=Color(1,.56,.68,1),displayOnly=true},
}}
-- MOBILE-V10: compressed 640x360 world-card artwork, decoded once per preview.
hudUi.moreWorldJpg={Desert="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",Love="/9j//gAPTGF2YzYzLjEuMTAwAP/bAEMACAYGBwYHCAgICAgICQkJCgoKCQkJCQoKCgoKCgwMDAoKCgoKCgoMDAwMDQ4NDQ0MDQ4ODw8PEhIRERUVFRkZH//EANUAAAIDAQEBAQAAAAAAAAAAAAUGBAMHAgEACAEAAgMBAQEBAAAAAAAAAAAABAUDAgYBAAcIEAACAQIEAwUEBgcGBAQEBAcBAgMRBAASIQUxQRNRIgZhcTKBkRRCobEjUmLRBxXBcjOCkvCyQ+EkU6LC8XM0YxZFF4Ozw5PTVESEo9IlNXQRAAIBAgQDBQQHBgMGBAUBCQECEQMABCESMUEFUWETInGBkTKhBhSxQlLB0SNicvAV4ZKCM0Oi8VPSwiQHshY0g2OTRHPiF7PTo8PyhHRU/8AAEQgBaAKAAwESAAISAAMSAP/aAAwDAQACEQMRAD8Ac7zw9b7luEVxBktwoBon0mHbyxzb3RjINeGNPQ5lVw2GenU1VCevAX6pSDWgr8up4iulRISOnE3WlW0kWaS2lt5VVuPI8jiBJfS3LAk6DgMBNVWohIudaCU1IizVpNTYA2O2IaoR0sxJ1lkDy614U4Y5s7oTp0pOA+lgNdBUhb7Wpd2dS79LNbUGBa60qveDSfbZyzuWlWhGg54jW19CpEaLp24ArUtB3uWrQcjUTZdN9QuiVF2F5x+sS1thuavCKO8dZQBpUHQ+pxo26+H7He2gkmWpiNdNMwP0W8sab5aqVThSH91W8H4i81hOY18CHVD749h6i0XP1QVlK+8R4vzt5iMFRxegus6TPn2G8CMLdmNw3PwXtV3alIbdIJVU5Hj073LN2jH0DVeGwvPMXRqgvVaohPiVs8uzpeKvX4jlWGrUyopqjAeFlEZ9vW8m2fw5e7yzLboO6KlnOVfQHmcatsu0TbVBHAxByn2gtBrrTzxrsZzGhgQDVJzMQBJvJ4/GpjKjVACJ4EzebweBrYwnQBkNzkPK9Jg8K2FprTJmOMRaNcfq33OK36qmKVgKtGpOYacqijY16L2ddcPKfzLhHqaCHQTkxiPWNrxz72qfkNdUkMrHiu3svRja/wA33VnJbuyOpVlNCrAgg9hBxqHizwtd7tuUklpahR0lLOWCiR9eH5qUGPpaVFqKGUgg5gja8vyfm1HB4VVrVSfGQFAJKr29l4aojUmKsCCNwbf805bUxdbVSQDw5sTGo/neSlMFb/bLiwmaKeNopF4qw1GNTNw0MRTxCB6bBlOxF56btiKFTDOUqKVYWJyYkFMTzdJul1m4+XF+TF5uoN2yus3HyYkZMXm6TdrrNxcuJOTFpus3e6TcfLiR08Wm63e6ExdCpXDF4b2qG9vALkExKMxUVGeh4ZuztxabB5liXw9AmkRrOU76e2LvNz8uopiK36gJQCYzGrsmx22bNd7rN0LaIyPQtSoAAHaTQDyxrVptO32MrS2kYto3C5gGLVK9gJqME4nF0sImuq2lZjrn5C8jWxmIrqErMarKTEiN+pF1w+Hq4p9FNdRienxvSUsLQotqpKKamJg9Oy0uL9W+6k2+foIJhUsXJ6Xk+mp/hrjWLO4hliIqQBoM54nDpvmTBjvI7w6NhHv+X9byVam6tPXpateRYjwSUGrcz7vn19L0VNlYZfG8b3/wZe7DkaXJLHISFkjrQka0IOoNMba8SSZRMiNl1UkAj6+GNry7nNDmGoJKuokq3TqDsbwodlnQzCd4MXmMbyurhIOTqcpHXtF6ogHcC/zXJEVOoxoH6xNmt7O8jnt4umsykuFWidQH6J4AkakDH0uZtF8tY2pXoNTqtqNM+GT4tPbxy63htrbc/wAMlKolRF0651QMp/O86KYklMPpus2ous3FyYkFMWm6yLvNxk3Tkxdlxabrck3HN0ZcW0x2b5cl0m6suLwuOzdZuS6TdOXF+TFpus3abpcfLi4pi03ybvIuk3Tlxdkx2brd7rdOXF+TFpus3a6zdGXF+XFpus3a6TdGXF+TFrrN3m6TccriRkxabrN3m6TcfLi/Ji03WbvdJujLiRkxa6zd5uk3RlxI6eLTdZu83Sbj5cSMmOzdZu83Sboy4uy4tN8u90m6cuL8mLTdbtIuhNx8mJHTxabrN3m6TdGXEjp4tN1m7m6zcfJiatsTlzd0N2g8O3FpuI1N4zjtF2vuj3ZMT2G4eXDE/hx2MPQLOslKu4ygE/XTEs2uXmSjX3gCldlBkm+Wa/LidHdEsG3ZsgLAw20k7BI0Z2PBVBJPuGNA2SwHh+5cvJHITSjqOA5iuD2qKgliFA4kxaDHYn+YUwAGUZ5E8bDUFzpUFj0Am3WCw5wFRtTK0xmBw6WmW+3vFeJFdQyqAwMiZSGC40i5mt76Z5vu42plrpVh54dPiA9BnpOpkHSZym8zSD0ECeJhMxwFqVpMlZUqowgjUIzi9BU0VmLZKYjtNyttlZRGkRooAA8lxBhuRCaVGI8SoOosM+PnczrrF3w7GAF2/C4kYobfrE1jrnzYX7Pdg1AWCoOWENf3tos6thdzEm26bbzY1OvPYLZ5pBGhJ4AGvpiGL6IxipBryrhcg1MALlNFg2VlEwLrrBF4Zv0IN7cyRo4iaZyhZStQWJHKmNd3+xj3Wwlt40izMO4WAorDgfI43uBeMPSViusIJAM8LxvL8Q2ExCVGZ4BzAO46XkMcP16rBW0lzBIIvT4ygMRQemAskZTwPW8IKYfLTwE8ok+ZnWJstYwlG735q8vTG7m0db5gVSvdUywnxassuy8flbajyInV3tSDHh09e2bQcuCF3ZNazyQtQlGKkjgadmH03BRrCtTVxswmDajK+1qZo1GpnPSYkcbgZcX5MSzdZvl0unJXF4XFtV0m7yLpndOTF+XF5us3ebrdGTEnJi03SbtdZugJibFaySmiqzagaAnU8B78XJuNqipuQPM32b8qs/ugnhkOtw8uD1z4Y3SyhWee0mjjbgxXT30rT30xJNg0uZ4Su5p06yMw4A/VO/pfbJqcuxVFNb0mA/jeNrA5cS2gK4O1XHqmxb5mLh5cSCmJJuOb7dZuPlxdkxJN0m7Xy6cuLsmLzdJu11m6cuL8uLTdJu2V1ujLiRkxabrN2yut0hMSAuLzdJu18ujLiRkxebj1X6+XRlxdkxcm6Tfcr5N0ZcX5cWm63a6zdFMSOni83Sbtdbj0xf08Xm6TdjdbrC4uyYtN0m7C6zfAXFwXFpuk3e6zdeXEmK3kmYLGjOx5KCT8Bi03RnVBLEKOpMC7XxVaodKqWPQCTdFMGh4b3IPEj2sqmUArmGlDzJ5U51xebD/mWF0swqodGRg5z0HW+2R/L8VqVTSYasxO0dvSwoGH6P8AV1cNatILiIygEiMKaHsGftPpTBk2hPzLSWqF7ptH3pE+cWNbofLzmnPerr6QY8ptCy4KbjtVxtspinjMbgVoew89OOH02Ph8VSxSa6bBl6i0tzYnDVMK+iosHexVMWlcTzdbhyut00xblxab5dput10xZlx2brN2vl8UxaFx2brN2vk3wFxcEx2b5N9ut10xdkx2brN9vk3oPytncANG/SIGoOFaLc5U0bUYz3e1qZhl1W3fCI22V6LuqNWCp02hp8xqLkwmz5HSbLWvmMRbeRpYwxwsnUJi5qqhGgW4jQYmbgo1DUQMbKRyFRQHEZXpgRlm5SLNViBlcSmztgQNW4YgQXRSmAMQOlkVKWq2FA9bHp1SLcbS5VhlpQDAaPcUaMrwanHCWrTIzs18MQ07i2qMDYy11Zehth68ZbKDU4AW10I6tWpwu0MBNn1aJbKy5FjJUi2EqGFDiDBcsUzEjXlhfJBuapTAMWVdFckXcQ8bZUx4kjL3n4HFZBEm/FQchfcxfp63epqO9xGI9zMqIZdaLqadmKHsuSmhZtPE5C+3V2CieAtH/WJDb3BgKCtytc1B9DlX38MRvGG7QX7RLbalKlpQKVr9EemH/wAt1KlPvNR/SMRP3uy5eSYKphw5rZatk/G0vP6a1FTSJqDp92x+d8wp1NCUTJB8Tj6rQ5LOVRmKGmJrPN+I4eisjGNQuLQnQWmNGookqYvn0it942M6ZxOYPz+zBE3DA4XS/Go3HP0uBkxM6deWJpuOb9N1JuH08NewbPbTnrXaF4uCqGI15k05eWJJtXzHGVKY0UW0vuTE+gu2q2HKsHSq/qV11IclWSPUxassRxp1/tGyQ2ZjgtVLS1KvU54z66mnlhpN5fDY3HvWDVKphYBEZN6WtLTeoxGBwCUSqUVlpgj3l9d7D7DcRPZxRimeMUYAUPHj78eWG2tZNmWQ6jvLQUPZg3mNJ1rMxnSxyN9xOKFcQVGWxsPltZHoIojUggi64XBnDGVc5jxDgbP2+aVgq8SaYojfKooaNzwuqQoJNyOsnPa2lOWMC41YgZb2yWlkvAyqZB9EcMDLG8W2PVckkcBzOFdasd9B0nibKr0TU8IGXXpbKnTj7QmxqNUJLMbZ1bOpU6FePuwOh3ASqZZDlBOijnhWRBnrZL4cqdKie3pZ8z6XCtYMNRy7LEeJNivd9kgjE0SWqZjWhLBiOLDn2DswcWUaPGe4eI7MG8r5hQ5elRijtVMCJAEdh4WvKbq2/A2HzLA1seUTWq0hJmJaYs7VxG15Bv8A4Yu9jdBLldH9mRK5Sea66gjGieKLWz3GxkllkZTArGPXu5/Mc68MbPl/M6PMFbRKsu6nfz8rzfKK1bDYhURQRUIDdY7DeRx/L6vLyuohkbZh16edv+bUaOIwzs7Ed2pZTOU9ovHTHic8NDwxsZuPVeS1XHNj8mJZixLNx6rkm45Nw+niX0sSTcc3LNxg3GyUxK6WJJuObk1XHquLlxK6WLzdNVyTcc3HCjsriR0sWPndZuUPHQ3FN0UU/Rpi8RY7n1vk3MXHS4SbpWi6Uri/p48QTxvk3OtTTwuCbjFR2Yk9LF5N01XKWHSLhm4uTE6K1aVlVVLMxoAOZOJJuJqgUEkwBmTcs3Gup2CqJJMADrcLp4brXwheCeNLqNoo3TNnTK/9Oh0OJJtXV5zQ7tmosHZTGlpX18rvqthR5LiO9Va6lEZZ1LDennaj0jjTtw8B2s1uj7e5SQA5xM+ZWovIgVBr7sNbzGG+YaqVWGJUFT7pQQRn55i1+q9HiPl+i9Nfo5KMN9RJBy+Gd5hkwQntGhYqRQgkEeYxp5uJagdQRsc7zk3yojUnKncGDcDLiV0vLEs3Hqvuq45uLkxL6XliSbpquTVcc3E6eJvRxabj1XJquk3CEeJnRxLNx6rvN0uKI8EobCWb2UYioWtDSp4Anhi83C1ZE3IGUxOcC5AbqlKpU91WIkCYMSeE7XAVmSlKaeQw9WvgFrmDN83GJcw7uUlMvbX2qj0xIyhuvttHV+YVpVI7ltEbyJny2uRazJERl2C29L5dNSnPfrrnbSdMfXNpx3G4YAHKacO6MTt32aXarqS3koWSneWtGBFQRXDYYSmJjUJ7bpg8YmMorVSQDwO4I4Wt+n1TE6THZdMbhHwVY0nMxxGxB43T+27vQE6AcMQ+ljn8vo57yeNk6rn/AJpWMTEDhYG9zE3WYvWQ1X8IxE6eBXwKaYTI9TZM2wTmL6pfboLAsg26/gQ+pOB4TAYwH3m9lmTbNuZ/dU+ptXqsta3rygmRlT36/DAzJhdXwwQwgY+lsJtzh8YagJcqvr+Fpw1sAuMq5hKD2ANrgBlOE/ckmCh9luJF6IVxEhwfUXndVnY986bgSGUDyNcAOmcKjy4sJXQbazb/APmi0zD6x6zaGbY7zxK9B8tPIPJhhc6ZwqocqE/qoPQ21m3tfm+X6VQ+otFNkV8RXyZjnqSND2YHdPAh5XhzGVlzbIc3xAnMT9VrJvy5uZrps0hDHtoOePenjlOilEQsj1vs2TVxVSsZeD6CxpuKUxNitzIwUDUmg9+JJuJngEnhck3VRqIA3Ji4XTONG2nwRayhvmbgvVVIMNFCk8QcwNezEk3nsXz2qkd1TC5mdec+za7E2+wnIaLAmrULyBGjKOu8zediI4dt08G3NrPItsklxEih8+WhCmuh5EjyxotVpcJzulWpqapWm5OnTO56js87QTbXG8jrUqhFBWqIF1TxHZ2nysVsfhkbrFLK1yluEByhlLZ2HpwHxOGDamHyyKAFKd1gO0dvmcFY7mf0N0UUmqFt4IED87X4wfqsSSQcwey4sBy36ajuaopgbZTJ/KzsAwNBQAAV8JHaOtmtjsI9rtYrcrHIrd5soBZm/Eefp2YkWGWLvSyBa8h7WAMfiGxdZqgLKRkJJgDoOHncWIl8lWe3hbHA4dcLRWn4WG5jcnqfwuShCZsQOzjZ9BHPE0dO6ylSp40YUI1x9FNC65gfZ588L2LU3DcQZkdl+dGBjrZkBhHCIvwYEWm+JfBtjDtzzWaOssIzMMxbOn0ia8CBrphg8Rm8awmS1i6wkRg507iU1IH0jThTDzlfPMRUxK067KUfIZRpPCI69treWCj9IQ1X0aWBH7R6TwtPzHk9D6Oz0lKugnf3hxmbP5ga30dxSTWWUg9gjeON4nLFlJwWksZHzEKSBqSAaD1ONwGsda6iASJO2d4k5GLkag5kgExuYNhDHic9uV5YKm4g9xzddrgZMTOliS49V3m+XECYliLF5umq+zdLjBMTFjAOq1xebjJ7YuS6ggbibjLEWNAK4L208UBDCAZhwNTi5axatJ6gg1Mjwi7b7XPRxNOkZFLMcZsXLaywmjoyGlaMCMNS30N5/wCajipSleLUwSlRXEqwbytUcNUo/wCUz9ey4nR6eTqV8xFtUxlLEf5604iMzJtRyYbJLTYxGWUuWpopY0rhtNqVq48sAQAOoFqJtq1LlgUkGT01G1Tp4ISQoWPTVgOQrXDabhViB4iJ9lqpu1TSXPdqQOm9j8mCY2u5OX7phnNASMTTY/0mln4xlvdJuT6LXOn9NhqMDKxmTDBL4bu4YurRHXsQ1OvlgibATmVF30Zqe3IXFqs2pynEU6evwsOizNgRHhnstkaLW7gYKaZSeAr2+eDibW18cGyo1ASN43sMG2WE5eyycRSIB2J2Hna2I8OLbVbJMrooIXgKd33+eGM2nGLqshUkgnjxtbNu2wdJaisFBC8Iy9b98JxRQR9YAdXMQXK6qOwHzxMt3C1VaKK8BjnOGd2CE+CNp3PU3DUBMEyT233kqoqFwBrnMxmB0Buak8eEQBPC2VNxWVhmTNTT3YCi7jtqt7RUVp+k8BhW2HKgw0WXUBYEW0WsGO02PSgEHht19g423wciooDxXCvtm+3k8hV4DGubTovG/dJyjMz8CG07q6jCl+3frfa3eBzKJAH3/q62wW5aaUCkiq4Y9aZjafS4/wCsCNJEhKwMZASWmC6BaaKT64p3/cepfNbftFGyuI2sSuerDLUNLlQ1JqRTgBhz8uMys81BpIypzmT1AtbRY0E7wHusp737ozz32tD8wAGkkISQc3jIDoTZOMdatTutXe5x3H3zlkTG/H0vP2iNeGGK8MCuOrbpDmStQhcZtdDTK+tOIOnGmNvN5mhjmo4Za30mtigajKBRkyBxHvp56vbeRm31TDJiK5pHCUMKdCsWrREngY0P/act4tc6eGqfw8ht0mgnhZmp92JAQc3AIWo4b8jgeuNNN53B/MYr1u6ejWVYlahTPLfvFWQAPvC0INvcX8uGjQFWnWol5hqQqZHoKbOAST9059tqvTwZSK2iqssTswqDU0IPp2jzxoZsRjVeCjqAc+s+to7IQ0KcipTYtseEHysSseJzote5w8+OCZuJSY8W9wXaoVnwbfG4giIxLWMnEmq4y11vmdx+mcMWzbKNxf7x+nGOfMnsGJNVrsdj/oq+FdTdPzv1n8u5d9MaWbQg48Sey6YdpRoznNG8uWGS52F44c8MvUIHeU8/TFqmNYMNIytXS5grPDrpHA/nfKPLEKHWfF2cLb1eXsiTTfUeIPHysFCixpkU+zi6CJxIHZSoU8xoSOWD6hLNqPG61XXTAMk9LAoqtNdKmYu1Cm+vUVKgdRubtjtLqQArE5FKg05YOWW6ZcqaH92Imq0l3dR62DXwsy21zpRqtmEO1n0MTsLX1coTXQ4I71EGYSwogGuZgdSfMYPIBuDBNAKuxJ4A2ADBufGpMNTUdpui3lDOATQczirb3tg464bXQmtAuLOsDabviBUg6Iy+N1puCwG10w/dyNcyfhbRZwWk8YoWzHzwNiuorNqR3EbLm99MK6z1abZgRZL0mrDxIwMels6S02XK4EdaRhXUifWyzW5tnWr9ztxDkv4b8UMhTJ8DgMVO8UwPFc6UXw5kLqn4WVp0HfK4WqrWy1aY+NlVcXArmogwvzX3QpGj1TtGBCO74eK2CUNcsRnZM6s5ysJ6xSFBytlMo6ZA1WlKjXAi33S2hjpnrXjXC0L4p49LKqYWo7bRZxOXZY6V0Ub39a+H9u7+aJZs5Y5n1Pe5D0xT+14WcsG6YHDF6vMsT4YcpAAhdsr79EYLBGqbjp8twy6ppq+okywk58Lt9JUneIuCvhO1jvHZ42aEN3ErxHmRrocEV3hJUepUEezrqTgpuc1WoKAwFSPE0bHsFiHBlWGRPWwE5HQXEMzKTTnwpOXqd7PGKVgdhYvxF4bsYrZrmACFloOmPZbXlzrgxFuMUkf3jISOTUwbyzmtd6opVP1AZ8XEf0sBsOyt4Qw8rW815Th1otWpgU2Ue6Nm9OttBWVl8RX1vO7TbTdTCMELXix4AduG2R9uRmZahmckhac/3Y1FbFCiheJ6AcbSL9JYAGCAsZ3jsNg2xNUICB1Y7AXpCuFQswyYtJi49tsl1tynM3UiY90pwHmw4jEua+YxGCOYMlM2p1P5a4mrY+jijkNLjcHc9g62OlFQ+tkg7dnnY2H5dXwYILa0J8MbDz6WZUqkpoV8ont8rlWtlbSN987ONB3dBXs88DbacRP962UDWgPE4jq16ijwKB573PVTUPCJO213pUKbe+S3ltcNFtB8Zgb73Ov9okhkXo1dHPd7V8mxJXe4ZIu84Ug6cDwxFh8YrqdcKy79vlcBwTK+QJm5K+EZCNGYJy7PO5xikZcyBYd4JbJ6yqRXhXgfTBW6vbC+iUTyAEcKHhXng5XSsPCQbDo0q9BjoWZ3ysMo1Ey4iyqtShWXxsPbY2JJbo1VC3pi5rmG2/k3Csq0ouCnK0hmQLoKb1PfpkE8bGUNVOQm7molP3KiwOF8VkD5GBUjTXF13fw3cKjqqjrrqMd8JEgg3Sjh3pOToLKb54tUGRdq2Ip1UA7xVIslbTwBRDUsx4nzwtJPNESUkj9c2v2YGqo864AAtmaSvAKt7LJR09yZNrBWKSQ6e2zO6bG1+Yws7pFwkTjWnAjlX1wMj3i6gQrT2uZJwHg8eMMGJpqX+y3TsspsBTqGZ2snG8vbF6QKrKn21HGxRzNqYgqc+Nw938KC3VHtjJLX2lIBK/mqOWJo3y47oyg08zr64IwXOO9JWrpToeB7LH/l9PPPexMfyLulVsPrf7ymDHbNlfzZjHgmxdv4SM8Lt1lEoFQgFV8qtgmNwlDl0VEryrocGVOcBHUaDonNuPoLE+irphizRxsOlyFnpktVAqcFGa9kmzRjmmQqr672pzbXLDmquiuUJFCMw88M91IJghaKKla92vH8wHbhwmKR4g7jUBxi1VJTTLAO/TPp2WgqYKtSLErkraSw2m3ld1qhSaaETOXXtAtS+VPZhud7eaDI6IprUBUIIPrhz3gtMq1adTUpYjbNpm893Zt+70KtLQ6qp3AVSCPZaibNwAcpoeBwyfJ25jIMjZuK6aDyIw4FZTlNre/qBvcEcc87Qmi6gEgwdjbb6NQKQaratxlkOyLWvlj2YaIrWyRhnV3BWhqCKHtGGfeWqerXYZFVM9eHbajQbc08PhVPiDOCIzBEHqLCWex3V9XoxFqAmugGnIE8/LDTazrY/wAipA4KQefM4OrY6jh/8xwOzc2orUziP8zfrItdh+X4jFZ00JHXYeQJt7h6qYcaaRJA2WDac9i8blGQqwNCpGoPphzSa3Fx8wsZzk1fMM2vaK1ph4KysAwIIPEbWjZKppd0WGke7BjLtvONQdGKMpDDcHe9Ir0BWNZVOo+9InPsna0r5Q9mHG6ispZWmQGrGuXLlWtOVPPDzvRaWk+IRAjbDjMn43me7N6GvSwlSoao3bhELPp22v7baNDOjPE/Cqkgin5h5YZmvw8HRmRqgd1goqP9MMcVWV6TBXXeDmPZaoYciprQiOIm1WAotTrqz02zEgkHL9q3rYpDT0VAQYyMXItbqYuv3mQLQVPAAYGOQVXp9RjzDCnwxFWooAfDJNlBSCdWkeRm5qNVyR4oA62GXVgNBJPQiLb7ecuhaMhtDrlopPLC2m4TRR5MjjhrXs8q4TVKekwwjsmTFs2wyu2qRblH1CRn2xlawYw01ghhYfeNlvWM17OIxnlOYKeFedOzBe+uFvowjCQHjQEZSfPB+Cx9CKdCnqyUQT9VhYemcOxYaT7ZHlazmHLsS3eYmpozcyoPDrbDF1UxKBCXE9Ig+dpybe8jZUUsewCuGq1kazoqRjTiaCp56nDtsQqiSQPO1FZRXks3xN51cO7mFUsewTb3Dv8ARoVV8zAk+dqslhJExR0KsvEEUIw3Xhgu36xDl6AUb2dMN1xCuAysCDxFpqPeUV0AqFzzG+doXw702KspUjcEZ3oMSKGJcVDqLQBB2yte2zZvnZMrN0kqKvlJ9w88H+pHG4eKHIdKqOBIwyxWN+jrIXW3ATHttbpZhpd9Q4E7xanA8vOKeC2hRu0T6C2wqUkbVTTQeIG02P3bws+35Gic3COCahKFRXTNy1wYlv2uYzHKsgP5SMvkCOzBWD5uuJ1B1FNh27+XGwUwwotqQqR272FjuSthtJpk1VM/ZzHSeFs3xferpcMD+ztcbbSba3WFRkBoWVqHvDnjw0CigdW9xB+vTEuLAq1S5OroR0PC/QSfskXFgZo0FpgaeoPUcb9qQDLUD6RbNaXORQXMddCpXQ0/MMLtrdSQsSyFqimuFValqPh1RxBzHpbKrRVxkQLa03gZ6eyPxtbRxBQ5gm7PFu2y3f8AvC8WRFVFSlHIJ415mvLsxcb9ZomjuIy617Bp6Y9yXFpR/QCvqYlieGVxjDmm4akwU/XdOfYR6y9+WQKgCheJk7zczYqnUQpWXULT7fY7m6DNDEzhQSSKcvXifIYb7e9ML1C0TyAB+Hbh3Vx9GiQHcKT+NpKlDvBvn53naHLsRXDGnTLAcfLp1N6KliQhke72QLRms2U0IIPnhnu7dbiV5EzHMSTmHM+mNAKwPG1VGoaaBTAgQIPC8u1JlkEEHobcYmgteozqWJYydQ4+lq3yh7MMiWgjPejD+pNPqw27y1jVi2zFfS0fdm26YcU82ph/XL4Wt/LeWGb5aFpA5iCrXVFJocM+8tV3tQKVDkn7xtSENue5os4coFHFFnO1n5U9mHKlrHOJooMhoNKCgPao4DDTvBaT9Z6ZR31dvH1tRoN6IfRadUVEp6TG0ZegtO+VPZhvvIILqYSU6YYd6ij46czh33lpqFSpRp6fejaSbz2g29xdGhiKoedE7wBn25Wo/Knsw0CyhRyVHUXkDT6+GHPeWqNeoywfCeotCEt0mFoK8qda9DHxtft9ouLhWaOF3CipIU6DDXZ3BsjmWNsvZXT4VwxqYylTIDOoJ2BNpq9Lv8iwnrFrKWBr1QWSmzAbkC3+GrDDDwqdPSbCR+GJJbN7hXUuuvRprT15HywaublXZuisq59SulCeeD25qiVxTKnSft/06WDTpFQNZUxx42sTkzvhzVDjWM+77PPrbOpWVie71DVw4WA27b5I5BLQDI1CrcfPBVXlQOCh18tRhlicSrIUk5jcWEwUwQbUYLCVFqCpAGkwQ29sldl1AjezNhL0gGdgq10HEn3YDRPNGysEc8xocA4hdWQEn2Wa6owIkCz8M2kSSALCps6EGCeltl5JLdxhYZVXMO9XQkeWFy3u3SQyOHJHKhwoohaLEuhMbdJtjUoKy6VjPjlbeqWqrCMBP1WupYgqxZp8s7+kX5ORlIoa9lK+eJM19bXLCSWNi6UpoaHyI4Ysrd8oIM5XClCrSBVSNLb3wr3DkRx9vbcr16NUhmB1Da+Ld+q2ZzRR/fTFs89pdIGjPSl5jKaH4YtUGkQBJutOnVpMQw1p5532k2syTAF+erSqKCp0N5ZWds5IZYiAMvIEnjhcju5IqCvDmK4X1ldWzz42zagr52fTKsuVrVxDJlbQs4kzwPTUFdNNDgFDuCKDWrMeZwpKFYdes2e+GY9g6Wz1BpU+VhJilHabNQ28FqhhCIEApkpUZfOvH34Gx7khIDEHtJwFUq1KrByzFpmeM2U2FYAkZdBZaU0pLoAUKBtwi4FxKk/WbTN5sY472ZYirJnqMvAV1yj04YakhtobkyokRDGutCBXsHLD3A4hnoUy4IMQZ3y4+tpzUqvSCEtl/Gd5rmWHRMTUFMgiZy2E8PS3y0aFOsaiqni65+zpaEbU4bNy20yTPLDGoRjwUjj205DGi70WnwuKCoEdjIG5B9l5Tuzb3HYE1Kheki6SRkCPbFqfy3lhrh2aF4GZ5CkoPMDJ6duHHeWofHOtQBVDKfbaHQbe0+VI1IlnKuD/AIbBWWyzXRRspWIvlMlNF7dOJw1WyxRKEj4DiK1BPM+/DCvjqdGRMuBIXraeqzuSW38rW4Xl1bEFWgimWgv09Lf0ESkoVNh28bhz+C/uFa3m6r65gwCilKilKmvkcMNteB+4AF01K9vlienz39QiqmheESTPbaypQjxHPz/GxKvy9FMGlU1tx1QBHZbenWDZDLy/C82ltWiYqQQRUEemHJtiiuLqXqTFQWJHAsa82J0441K1Q4BB3tIOYPToppQGBB4D0F416bIxUiCDBt+3KkrV6heoQCZAGZz4k2kGI4OXW3dCV4/aoxAYA0PmMPdVg0sT3iBtpG3S87FnV8GaVRk3g7xvYVeohqCRg3Fs80ysyqNBzNCfQYNOk7iwXxtNCATvYavUTMEizqfLa1QEhYjqcz5WNS6uVp3yacjiWbQroVIPngk0KR+yLiFYHYzY4xmIB98nzvrUCpgqQb4Tcrke07ZfwroMe/L+WOthKR2Anqb93typzKsD4iY6LlcPd3KO9TPGyFa1011xF+X8sQjAKGBB9lzd522d/NyUIKH1Ng6Ltjv5CMrkBewDFEiCJSzAkDsFT8MUfDAGVBJuz1tCloJjgu58rLpcwkQ5Cj42JTw/e1FSVTUfebJR531e3qW0QaKSNZCaAy1C8K+WvZimWwj3WIRnMhpnVSpzqV0rwKnnz4YHfWDp0yeg4DqbgTG62NNqdSmzMdVQgRlnp7MshbHvUNPWrqucS3E7wNpN3xHKgqCqmIpVkSmAlFCdY1ZFzwPizMXPtbj563aCSNAXUl5o2zRkH8CkfBixxTtexHbxnYuxFQWfujptxAA00OvbrgUJUdnV3Q02LIFiKoy3JmD7BZZNJGMHUTmuUkOPzs2ljVUoVpMKiBahcGaJz2GUj22sw+Eq+8w0RkxJgGm2R9h+u5mzbEbaUStdZo695V7pbLqNc3LnTEuFXjy9093qivKuWuE1bl/6kM5IUiAARM9Ttbao2osZWD3bRxi9fS5zNA6KSqXVpZirRGXhESbztFdCoDrZh3ySB4Qd8zvnwvncNktr29kvFVxKXU1RtCwADOV7aaVGJ0d80VABWmlPzEan9OFlbC08QndPUdF2KqQJ7CSCbJaiWg5HLV7drOChavfIgL76jPtja+LWAkZiDpPTwgEm1jere9E0Qs0YqFCOMgY5s1amuprpX0w4xywMQzUUL9KntPzJ9PtxdAuCwwWkDopjIDxH8ySbh0OJAnLcWuxiVsViFIEl8jIAg9fKLa60yOWexH52r6pCYruFoFlK5pHYgh1FBKErQfmHNajFnjS6MMds4gSeJmbODyNBlLGhpUZqefniXlXfmK7tpNJWARkVdQdtTKW3/d6G+4c6QwfKdp2+NrMeqkHD92x75ll1Zm0tTGlXCDL97qLYGh3zA03YMvFN46XxLts15Z/NBDIY9DLGM6TRg5c2YaF4zoTxK8eGKvD8/wAwLVhDKi/eh0jNIVAOufgNQ2nM6dmGFDmOHWt3SVF0PmFJjQ++mDsG6cD52oaGqVERKZOpWFSMxEbZdRabEcqxhw5q1aTd5SgFhn3tPg2Uyy9eK77XpmomhQp1K2JqxoZDSP25kdehuCINcOA2ewCsrlsw4N9mNNrtH9PxBIIiDwvC6b0X8swwBVpnrY3aNvs9Hukz5uA5DzxKMa2/cSpA7cF43E1vdpHTG54m4NZq+IxYfLsFQIDVl16thwFk6BQGhZgdbnx21pYmkdcpNaA1OIsM1DU6nA7Vq2IzbfaeFyunpZSUKOGyQQN4uJKnHexo3O9ClF0riOZoF4yr8cFHCUSdRubRUP2D7LFHMKvugG15xNMf6g9t2v8ANyIashHGldcRzd2o/wAz4A4hUUlOx9lkdzVP2bYNUqsv2T2Tas4ygP8AUvis6NUNlPlj039oOZPuxzQhHW7fR63T42X9IqKclIsI46h94+y/VecihkanZTFZ3K2HAN9WIzTToLl+i1TxFsFxTnr5Wt/mFEdbtFurCrSMD2ACuKf2tCOCH44ikgwADc30N/vWzDgjUzR2C1f8xpcJuYlpa5SXkmrTSgHHEE7uo4R/XgUtVnJUssYM/etwDQiWdrSnmKjhcxrZa9yV6U54gftpuUa/XgYN95BPZZX0EcWNt2YT4KpjtFpjzSPsi5ohynUsw8jiAd5l/Cv9nA5gjIAWUMEnU+22neuDm2odlqP5ofuiySxR19hiOwscCTvM3aB/SMBmY3Hss0YOn/BtyK4B2YjztKeY1OlmzHESCIiPVicAju9x+I/DAA1Ddh7LYjCUulvTWQmQCOybQNzCtO4FmmizcFC+lcAm3K5P02+OAAQO22Aw1L7ot41Qtt4fbaA4+vPvWeWFRxXMfMnC6b25b6TfHC8nti2Qo0hwHst+HjM+I+eV5xsZWO7sLY2VSKGKMeetftwsNdyj2n+LYWDIzqa2oppwX4XpDXyjQnxvLHE1W+03xti6KA17o9+Fv5lj/mD44Waj/AtppUfZvSd5BJy8pvNa6hjNrY+nFzZPiP04XOqD/mfbhZn0PstnHZej73qy+3+t5wM3HVbHSAfSi+IwvZhlzdVfSuv2YWQ/3W9lsZzjSb0Zrp95PbaH7OrUPbn9VsAe3H+ZHhfJygGpauooDT44X6Kh+y1sd+y3n0umv20tCW07wcp47Ww/MW6f5q/D/TC93m4K/wADhd3VQ/YNsZA4j4W9+nU1/wBRfZ/S881STlA7M/xth+dtuJkr7sAeixr3ZaDh3f8AUYXfR6v3fjZ/eARms+d6A8wpbmp8LQ+FpOswDA2P42cbcLWlM5+GAfQ7Fkr6f64CGGq/dHts7vO1fbbtuZUYjvD7LReDgx9mX12ZO5W/Mufd/rgR8tJ/wnJ9QP34CGGqdAPWy+9X7wt0eY0j9pj6WkLqAJOfGyv7Stl4BvqwIe1lJ0jI9XGBfotU9LLFZeLfC3B5lRXi1pi4O23aLLHdrf8AC5+GAxtZOSD3tgX6JU6iyxWHX4W5/mdLox9lpGdeBI9LL/tiAf5bfEYEfKzfgX+1gX6FUP2h7LK75etuf5vSH2W9tpNa9W9ll/23F/wj/a/0wK+UmI0WP44F+gP98eyye+Xqbd/zlOFNvbaYsCBmx9k52T/bif8AB/5sDPlZVND0x24H+gN9/wCFkd6p2k23POB/wv8AatNqCnPWLJ/twcoV/tHA75aQVqyaf37cD/QP2z7LI70Zb23POW4Uh/cbTzvAJjqbIHez/wAJficDulp/Mj44g+gj759gucvns21t/wCc1P8Ahr7TapXLJ7gieuf+6yI3tv8AhoPj+nA3KtdZF92IPoC/ePwufUehtqOc1fuL8bVh5Oxsl+2m/AnwP6cCyqcmr7sD/QR94/CydZ6G245q5+wvxtRJJEwvnZX9tv8AgT4HAjpV4Kx9OGBfoI+8fhZWu3P80Y8F+NqNQG7DezA3l/wp8MChDIP8v4nApwS9WsnWOtuBzNzwX+PW1GtB9r4WV/bT/hX4YHqktf5a4G+hL1NkEqR7xtt/M36D2WpFeDIzPaLIftp+xfhiElvK1aID26VwP9CHU+25mdBEtGeWcZ/jbf8Amb9nstShdtQUFss4WYA49nnc8by7fh+GI8e3XL8EIH8B/fgf6Go6+2+1uYYTD51a9JM48dRVz6Zm2/8AMnPEeyw6GCxtfKlQrvlJ00mOXXa5H7WkHNfgMVtts6CrBB6lQf0499DXt9thv8x8npmGx+GU/wD5Qfqmy/5jUHEewXwch5vUGWDrkdqR9cXZ+1peHd+Axyu1EgEvDX8PUGYe7Bn0Ne322pf5z5IjFfpqGOKqzA+oW+/zGpMZewXOvypzgoG+jrn9k1FDDzE+t9ndpR2fAY++QiXXqW5oObt29lK4a/RF7fbaNvnjkv8A/wBNT/DRY/hcR5hUXiPZZg+U+bKT+lhyOpq7+m9/ftWbmB8MffJQn/MhHZTqa++nZrh59ETt9t57/wBecnAnvMQRx/R/rYf8wqROVsf/AEjzNuGFXpDt+V/ftWbsHwGOhbwLQdaPlqFkJ193LGh+iJ/BvOH575UcwMWf/gj/AJrXfzCp/AtmPlLmYga8KI462n/y35+1JjyH9kY7+Vt6V6qn+h/fU40f0RP4N5o/PnLRloxfpSH/ADWs+n1P4Fs//R+PMk18PPaXPtMXx+1JvL+yMe9C2/4idhJR/q/dXGk+iJ2+285/665dnK4wR/8AKG3b4rWjmFTs9ltR8o44QdeFMg7s+R7PDf37Um8v7OPvk4TqJlp5Buf7u3Gj+iJ/BvO/+u+VRJGJnp3J2nztX9PqfwLZH5R5jMa8PHXWd4y+zfv7Wk/L8Bj79nwNX7+KumlTWnM8ORxovoi9t58fPnKPv1x50H36Wv8A5g8cM/KzT8ocx60Dn/xeHXa/v2s/YP7OOf2fCP8AOg1WoOY6/Vz7eGNB9DHb7bRj545MY/XqAzBBpPl2nLh7bB/mDdnsss/KXNQTC0SNMg96Mz93+u19fth+xf7OKmsByaJtaaSDDz6Gvb7bVp83clf/AO+pj94OPrWxBzA9nsuRvlznKD/2ur91kJ8/eu79rv2L/ZxQduaumVvR1J+o4Z/Qx2+2xKfzHymoPDjsP/8AUA+uLqeYR09lx1OSc3Qy2DqnhkoP1E3IG7seSfDEb5CUD2Xp5CoPoRgv6GP2vbdE5pgqsFMTh2nb9VPq1XIOYH9n2WI+Cx1GQ+GxCwc/0mPx03K/arH6KfD/AFxENpIf8t9DTUEe7hxxb6IOrXKK9M7VEPkQfxsz6cTwWwCK/GlUjIZqw324XMG6fkX68Le4XbwOYokXQd8sScteBqOFeXPEX0TtNr+Y4vF1DUpUQopgGWIkntH3c9uM2w+n9gufluDw4VK1YnWTkgOQ7DO568LZZd5jgXPKqgdoqcJ8SXM5EWQ3Lu4yhK5j+I6dg7dMSYmpRw9CrW7zWKcghCrHUPs9h+q862EqgBqjaKStqZSB+oTMljvdqFSrWrU6RTQakEFgQI658Le06lN20omqoywInwAcANrdYN0S5FYVzj+ocPqwGgjstvCG7uumy0Py8DZ3JB4SSVy05UX3nDWhzbB4hqSKz63EsIEUsv8AUYkAdBEzeQxWIwtAtDIG1sVMaiF4DSOn7RtdUwuKpCo2kFU2MmX/AHQJN6rB8trVQpdWI0gEDwjVxlz+Asyd1bP0hBJmPZWn9/M6YCT+JrFFyRWIkSunVY5fXIuVT/UDjZYjG0cO2Z1U8/1gyGmHAnQSCSDfzypjqL7pVrRn+o+lfSmgCj2TeTw1OviRCqwqZfpQ+vSTGoAjO/olHl9SkIQ06P7iy3q7Sx9tmv2rBCD8zJDGa6IrdWQCvBlTQNT82AEfi6ZCBHa2ca14LEg/6cac/NApuxqdyEz0hW8XYCcx53lVxo1BRh6YBji15il8s4isg0ioG4lhl25Zel6s4MwS1aoY8rOt4m2+OvSt7qb3BR9QJwITx3eqdYISPLT7MaCt84hp7tD6IW+LFR8Lz/07rRgfsuw+ubS0Pk0iO9qb9XVfgAT8bc/y8cKp9VU2RPjONf8A4cR/HI36BiuHx1A+k9oNePBv8QbDNvm3FnYOPJaQ/wCk2vOLoZqy1Bnx0OPjBsRflDCj7aHzLn/qsr+XVxDI6nL9pLsXxtbV1sl9A/6cEINy8M7sCrxwo+mjoFrX81KfVg7/ANU43LOqJ7KR/wCgWIEwbxoKq3CCUPsbK4P/AEnhc47v/wDmD/qN3YY6jmdZXj9ofDO6ofFu0y06sMsXmKHEq48GbXdpmgCrm4NE9B8e8p+AwypfNlVTDVBPEPR/FDa58Ex20P2MAD/cLErfKin3V9UqfgwsunzKom+ofx0uVb3m03wHQu1DH6LgL9tMKN/4Ov7Mk28vX/IRkf3cj61xpcN8zJVA8KVOvdPmP8Lwbxr0FBhkakw4iSPz9l5/E/LdajOdRI++oIP+Jb11LmIqDOCLcp7KSEVoXXtTvaeg1wh2u/bxsrmNjKoXjHMCVoP4sfR8PzTC4ghRUCN92p4D8cvjfz6lXxdD7QrUwOJn2H3hfzvEcvxWHBJRnX71Pxe0DxfC/odTC4PFRAFNzxXL6sjbf14RxalORB+vEey33a98AjvFEE50Ei90H3/uaox9R7pzw9RHwvDcp+Zq1Bgq1D/+Grmh/dPD0i/lv0pB9rbgQfje15x8r0awLNTn/wCdSyqD97r6zcjq254Mo+IxE3HaLmyBkQ9SHiJByH5hrT1FV88bnRU6H4XTlnOsLzEBf8qtxpNx7UP2h8bxX0mmeKj23FzTkuK5bL/5tH/irw7HXdT8LILOijuyhfRsLHXcc8eNMndJ9LaaFskYsAeFwPW8/wB8Z4219bNQmUGnDvDCr8xIDTCnu4yCR6W20Lvei+kk7uD6i893rAxbQWZzVmV6dtDhYF245j44VAACACvlNte6W35rMxklWjrFoRWfrbPlHIZfNThbW9k/EfjhVJ45+YtmaKnhb4MDw09qk2iGJccTbC8NebE860OAQ3GUfSb44XB44D0s84ZOgt2yg8WnjMG1Axj/AHjZr5ftAP1YFLucw+k2Au86GLL+i0zwFtDTHEA/C1oxtT7xsqLdVIOTN5HA1d3mHOvqBgQ1CRGqPKyTg0PC2ApIpB0z2HawRj6g4z7Lu320e/tEhtR8vMr5wQcqkAEZWIFeeIab1JLdU6qkUI6OULWn5uOnHAMPP+YSPM8LDxtaklRlGLFHS+kyu3Xzt1h6uGSWfDgiNPuqfe4i2HK8HWqYdGblxxGumKgYPvO2U5ZG+9k2+/sWL3MiMcgVSpzNxrVmIHuGJ7biVOUoo0GgNaaduCVQuzOzSCTCk5dJu+HpGrhqdQMr6huJE5xPG4MTisMqU6VCjoZQNVQLDDjA675zYeNq08Pj61FkqUijZqdLR4Q0bg2RWdzRqeR05HiafXTCzve8zpGiwnp5q5mXQ0H0QeWIdIIM5Hdc/ZncuL/7ZASoktA1QRZWppEZjZ4GXbA/A3XktNeY1nHeHSiamCSrEzAGc+dsj3NrGaSzKkgajCuhBFCSAKDSmESzvlmuYzcU6ZZc6rm7w0DGtahm4imlfLAtWto1AREAjqM5id+t1Y0Wq91ozYEklvdMTlGUDtsmhh2fQ0ENJ1dGyiY22izjhq9HBtiDWnQwCgIPGusL4pz1GfswJt2+XARXGqNXIwNa+emIOxXardXtotZYFY9Nn0OUPTiK6sG71OYxKmJSqzZ+KQAueQA3AtO9Xu3Vl3DcLWvhHoKoIOkBmZurMdifQW/7kVaZVtipn8/S5qROxAByivqAe3zOOusCaGRVppQYeM3GNvq/E300XK5jKNh5Xm0WIGqdW4jj67DyzuIYqirQuZ1bsR16Z30IVU0kowPFaZq+o1x2pjP0wfeMeZ1iBme3M3wUyAMj7LkVamoEnSBtGQFx1MQCzQy7njJ9puNHdyCfox20QtwwzMGAYCuXMqgBa68DyHHAs+HpxdGWG6TJ1RIoZ2BGpOU0qDx+AwJWeuh1IqDwndtxPSLhxGCrMxCPGqd9UgW0oJhai6a1SszahssgNp2mSY62Zg+eYQU0NaiSaYCnT3ZDMBkc4ja2dckjq6tTgDnC/RAFdCRimKBljVXbOwGp5VPYOzBNFn7sq6wwMeEzM5/jdcHS+j0tJYsSSSx4nbKeFrsQtPvFem5KuJAYQRGUZ+V+5pjBjMSXVFpoFAVBGQ3ziM5NkmFtcqVYLUD2sQRF6+448O9pEETB4WRq8r6RTqiCB52Fq87tNhDCAykt9mOMulCX+OIxiHfIwLvPYLJ+jomYk2Pr7WvMizjl8Wx5+y5iQKGrcNCa+gpjU5dfhdPpC55jLfPa8F6m7Bqsj9JvFsNJz8ut2xSQinWEnHXIyDTyrXXHVttMhLExtKFViRlpTTVuI9njjza89BTskG6VMSojxhZI4/DjvclM0hHeLVInPSVGXZI3v1Ja7SRhmeFbcHL9rh7t9tHDmAWYJUA/fd2leA7qnlxPDsx8I7ZNXhjfKmU5mNNeDUVga9muOio8SUnh4M9vM3QlycnYS0iAPUZg3d6VMsFR9MgH9YaYn90G+Cu4EnD020pDFixGezZEZ+t1mGYpnRM6VoHHsk66LWhPDsxYwtcuRkCkNUAIV0YdvGnClcSd8gOktpaJ0ncDtiboNcyCSIgkmdr99ErMutVDpMagciegmCfZcVR6pGltNIhpAC6feHXMx0m4buy8dCDQjLri9jbKKLCzGproaf64mBB7e3hcfjnMgCL73ZWZEEGI4+y4ZOmO8Eyc+y4/X01LnyAGJSOtDltyOwnQfpxJHZFxGfvXNnkTpM5Zk5WP4YJapJ4QbjpLU69UDy44mqW7EXzriQzGUE3Cfbc6hSfEVUdYmxlKGZJ26TJ6XQoB4i48qU4+/F+Y0q1xEpr7IFT+jEhYjbR8bi/wMe2yUNLPWeGWmN+2bhAkSN5gLBnbfaOy6GtbigIVhpXvEcO0U5YvN0q1HWmbQjujKKH6PocS98kxI3j1uLQD9lOuefrc5TwgwcxPp1HZceuqkgsywCsbZHceVxxbXAOpp/a/Riz5njQOa/jk44l71DtndNI/Z9BfWIBgq/suhdjMuc4nfhfixSLxlT36/bjoSFgaxgU4UauLFgeB9LrkDkfO7LW0+6p/xR+V01CM3OQyyvooHoOqnn3VHPtGpxyI2cU6LV5Go+FNMdkifCfab9qjPUAOPZ2zcr4gtoGkQDmIHXPMZm4lKMNPj1/ZgTPZGXwvk2cJPtn7Bi1NuuJT/K7eCk6DjoMd7142ujYmkkS65xEsOO1+7zMgQMzG92TD1qhISnVaJmEYxG+w4cbqS0h5lR/Ew+GmJa7O49u3cAUqSWU6niAwGLmo3afIWHW5phqI8eJoruRLLw9b4tRmESq7mT9XH0sujyrmFY+HCYgiQCe7YRJ3zAuP0YUFQqtqF7prriYdmZiAnTWtQM8q1JHKlaAnlgvWxMTHHMWmb5p5VT9/F0p1KvhP3uPkOPSxQHZZE7gb8Tbj/wBK84c+CgVEOfGwBlctPYW+z1F0FCgp0ctcvEDnw+OJH7FuM5Qy2isKaGRPpfHDfWCffHHrw3tM3zdyRY/7qfJWNq+4xCKZpvB079u3ttoPk7nrz+hTER71dBPlvdasIi6PMkDKcpSpJ0/hBFPfi/8A9vfiuLMHX2Sx4ei4bnx6WVDUBEg5D6yDaFvnflKiVbEP5Ux+LWpNOpSNRHqrRYHSyEsSc/2Ayketvl+RucH3qmET/wCK5+qnfA+TXNn3BTTUdOKRq+XeCUPrpi07HbIKi8h7P5b/AFaGuHZNYxpw5H7zqI9k3mT/AOIPLBumIPkF/MWmGFwonvMcvZ3dGo09ni03oj8hY7hjMP6rU/I3G6kYoY89xTVsiNoOAzVApXEobZEFzLdk6a0jcn3ajTGohj70U52kj4Xkv/2i8rkg4fE75ZJmO2TleZ7hAQac4gDM6UeANhqyynsvUH5Dx0Lpx1EHT4vDUGfRY3HncSK9eoHy7sNTQsqggCvE04Ymjb7d0BMs4HAB4a0pxzUbQc1xrXoiCdYHoT8Lx4/8RMEFBOGqCSZ0unpGc7b3mKIJYAjUDMiQsgDrHC9U3yDXaR9OEACA1JjnxmDtO3xuGm5x0o0ArXj1wPqynE39mWi0AlbNrU/LAjQ8B3ia07ca84d5yfhton8bx/8A+0fAMW/QrwNvEs/XeVX6Pp8aFjO/eRHwvVj5BrgLGNpznq/RMR2SZ9txFuVkDkfLLQNTNcmo465cgqeFAMXHbLZi1JmbSoIgYL/UfjwrrjXlGUgHWcxMU/xkxeUH/iNy3w/pVx973ZGXDPO8sqUCrFUUGDGuuct89OkSegF6RvkDGeP/ALyjP2PA4Bz+10y6TY+S5dTrNbiv4Bm4+7BNdothqJkHrDL+6oxsVRfuv6/77yC/+InKmmRXHov53knQ9h4+E/0vTv8A+H/McoxdAiRMioMspIyIyzsO142o6zEfljAH164NDao9aT29Bwaj0I8+7pjYBB9343kh/wCIXJTAL1wTEg09uuc5xeYEj7Iz6k3oT8gc38QFXCkSdJ1vn0kacp9YsF80x5ytr5D92D37KcDSW314d8ivxAGNdoHZeYX545G7QMSwyHiNMx5el52Oukept23yHzsLOnDMZPhFbOOBzAGdgu85P3cle3N/pg2drm0Ae3JPLqrp66/ZXGomOIvOj5v5IQx+mJA7DJ8hFoSRvrW3H/orng0j6Oh1dKqQv7x/KbELBI30X89dcGP2ZdBdAjdoRgTUGlKV1PPSumNC1RRuQLSJ8ycoqMQMZQENplnUTInI9O3radW1CAuqMyQD/utlV+Ved0kn6JVcFdRFPxEQ2mCPvcYE5Z2JWKnFGP8AftwYO2XMfFDTQkgZhr6DDov22rXm2DqiUr0SZIA7xJy/xWrLcclA6WZU5DzOgYfC4gCAxIpOwAbyXcceliAiDUp9WD8VgxYZ1JH5lNfOgH78M9R62qbH0swtWnI4LUX452IawPujp9o/jbClyuuSpqUK2kx4novPTIAD42GQV0SMfDXDfabXbK4ErxGlaqMwI9aU4cxXDItxLReer81UTFVFI+9Upn4Fj9Vgd4DlpLdpvWYH5cBZe9TWPuqlVfKSFAHaJtbhs5ZSB0218hx9xrhszwIQQkVtDGfpsrTM44NQFmA568cPKmIRASXGXGbw3NubrmhxSMI8UMIPGIHTyvL0qdWqwVKWokwAASxPSL+pco5VhsMocYUUmB8OoS4/akyRPnYP9mJahTdv0gWp08w6przVWNPicCdwmjmupZZbwSfeEB6EcKEIaZgoFeA188POZfNeCwStpbvXHAAx7cj7L+cY/FCtPd+MndjxHUC8py35Nx2I0HF/9rSOZXUDV24Lmo9TPZe/C5kk8f4FkjNHEKJbqnEVn75Y9op3B6UOIwXPNCgzUUsx1quYKOJ4+mG2P+fsdWeMOwpr+wons96TeUo0z3h2ytNhPlHleHUaqRrHrWYn4LC/C3x2FyYvmmTKXOmtQFRVH52AQU8zjm7709pblysTMmcA0LVcqa6a0ppXDSpjua83cBq1arnIGthHbvAt/wAjoUxQVgPExOo+XCx6GDwuEEUqNKmNvAijLtIEm/YhyqtHAX3khK55bigr/MFQlRpozHv055EamAO63ck0riugJAUaBUXgqjkAMLqHy7WqAGvXCjoAW+LRelJkybs1dQSF8R6D8eAuBBpUAf7+2ycm67fAwAWa4NO8ubKM2uoIA09VGIOyxoM8hVHMcMkoVhUFkApUHjlrmpqDShGE9P5dwSDxd5UM7k6BHkLcDiegyuU1qh20rl+8fyuFz7o4FoPlc2OS5u0T5ewjQZiwkcnva8O+1CBUVyjBLwvdpcT3DSVM4dlztr9FStNO6CDywAvKOX0pb6PTiImoSR5+I73HzB27+nqJ0sh09NU5zdmqMdKmo0zPg3PZkDlc+HiGAAEEey612vdCTNK9nbDWp6a5RXiAGAHmKe7E/fuoXjZmrEVAodQGNRWlOIOvni7HlmGWdGHA6iip+LC0fNNQZHJ1IV0xwBPGOo3uDRWdidNUfvVCB7AbMIyjbOxQtWbph9zJ6WYgQxDQ8srGlfOvuwCMgEuSSSQBQeDqpGVtaVbvg+Y8hhi/zHy2kzinTZtQiUo0VEdIN5Q02AyVWMxmCR9WVifRHYLJXwmc2c5+dkg55mzihA7E3V62Y1qrRqSKZdRqffThiM1h1HiMPULKCCQwHFqhcnManmDXhjTP80YaFFPDVDpGUtTAn91VvJozONPE5QfhpNjjCPqYll8R4AzHmTZmjOb9D2gBVbq+6qk5FEgqtRSrIUU0y6aYIDw7NdZTIFzV486+R7aaaHGsb5qQMrfRnVYzHeLn5NpMXnqHLMU5y2Jjf4dLCGEOhl1KTPhOk5eYkT7bOIHEixrXdigjBu76Pp0arlaLUa5RlBFe3WnPB9fCbPl6jVA1Gehb7DShxox8y02L/wDbVGL5ZPTOfadGdqqfIqqxnoB6GJ8wLB+jEBIKDQZ91vWBqyssunWbXzdWSOJBf3IjejKxysxdRxPBaDTzphg/9m24TKJeZ4pmFSdRqf3Ycp8wUXGj6PWkZMIpZCeGxsBeVZyXIP7NiHD+Imaeef2t+3hZXh6WtGWJ4wq7iuYs2aNgBQN7TVJr2afDBybwfboaiRc4pRjChOnIksD6Uw2XneDYklKiiN2w6NPsJztZ/LgsjvakdJysE0GgCF34OR9YFn6FPCxPTkLKUvLScRABKotGUjmpGtPze7Hc/heEMXIbNWmfp3C6imhy5gFHlxw0HMeVVFhzRU1T4u9w0FSOr6CBPYbWrg3AA7yV6ECwO7dWkI50DLTU3n9nUJ9bONJbr6N6BlWG2kM1cpWmdfIagJ6H3YofZ7tMvQmRaE+xLJX0HVAUU588NlTlWJLaaeDqLRgtp0qD27qW9LUvgATmqnL+JsCWVQC1ZDVkDVq1KfYwXsmze6I2Me2+j80sYU2jAo2QyozkkjipGYpX0GK5f21Z01aUZq91RlWgoWahZj7qHDd+U8vqNqbCgAjUApqKIOzDfK0iYfE0DNJ6lOBAK1W9gEgCwwzaAiYjMNBYlGJI3U7Z2S9LV76q+c5qD67Xd86OoKrdwpTvAMGbN5EqAB5Ur54i/t+WBSJ42qq/g0OpplEgzV11Onnhi3IOXupjvQ85EOCoHSCJn1tc2Mxsd3V7uqs/6qjX/wDVTS3xuPXiA48SBIzBU6i3WZiOyL6KaIxZS6GI8JOn+xpX4XMW/oFAnfMzDqVQ+z+KqsCT7sRhdrcozRSLASur5MxofZotdRX2u9oeWDm5EiE91i69IRkSvHp4WGVr/pGExDKlb6XhevdVnrUie1XOsehN87yrpE06bmdgeHXxC+/9woOlqdXpqUI3tXwn4XJe4hji6t00bIzGuZBnkodAqEHPTtrpzwmXNjvPUHCUyM3HIAuvFiWog5ippguvSxmBhv5swRgJCvV1mOiN+cWQcFTxqr3TUsWqKFDpUIqBRsHU6WHqDfaOGGLfScIJB3KoVHbqH++4sPzTFYdtJFSgzMfBUVShJ4qcwfQ2Yv8AeiFZbRVtI3opEYAkkA0AbLqRTkNMJomvLYM75ZGZgBIw7OKimh07ML8VzfFYxe7FSoUQRqdpYjqxyGdkV8LSJ0NTakQI0CVjt0kW7wPKMNhWkU01HPwrlYFDm+JpDdHz945k9kizNZZDWlOOre18P0nAp98KL/KYMq97zbsUfpwo8CjNtRPScvMnf0tj/K6RGVZp6MkZ9JBPti9IE9ItMnzAZ8VGO0NPrBFk2UDRmZzQ0Gv2CgGI8FysqhgT3hUluPbr6dnLACFvs6VHUfxNlVOX4tYIouR9nQNQ9In2m3J0jcH1sOnzLCVQf1kGUsHOk/H8Lt6fkoryAr9Zx7bb1t0UrCZJ2C0o0YUitdahqEjlp28cC6wM828zHwtg3L3QhhSpuTm6szAA8QpUWZM7AD0m0Vbm2qUpswXYPAk9ud9/L+Tn0Lf9NMOW2Xu1bplWziR5An8tQ6Sd4EsFL5u8tPOppTC/vH2ER5T9c3q8C1CrRYfRcOndxKvTUz2rUG/rnbyVjxRPsvD4rU1VNWJxc1MgyVWAB/aTYelpaqyjTMPXX7cOs37NnUoOpE2Uj71Y5Fz8i2URyfDGUY+I6lBM9I+q9c2GwVWprfDpn0nTPWBe5VgVGlsvbeKWnjqKBaOMqiPvET5SbTVdlOuorxHEe79GD82xRyRZ4JkMirVkCsMxH4dT68jjHuqsYGUZZ5j22/xPIkOtqFWiCZ0oXIJnh4gIN7cEhZ343msJz/EUytPFYeudtVVUBXz8JOV07T4hvNuattcFlrQoxqPepwGmt2ikNVKyKda6e7/XlhLTrYjDCQwZR9k5+ziLqyvQZqVVSpBiDuP6fXbqvh6OI95CjH7QEf0NzU6qVlD0yGU+w3q2zeKrTdcsUxW3lPEH2XPapPsn1xlsVzwOqkfS4EEcjTgcG0K9PFHSCFPFGzJ/dPH67X90GMDwvwI2P5edqcRhamG8XvD7w4eYtuxykeJeIO4vab3Z7a7QpJGkityk9r+luJ8qEYTfDPi54SkF8SyGgWbi0Y5D+HtGGT4OM0MdhOf9bhwmOBYU6xhthUP1N087R08Wy7z6DL+llYvBZFqQ7Sn5XVu3g+S0zTbeWdBr0zxH8PbTyxorRrNGJI2UhhmzLSjqeYPAYHr01ObCP21GXqPyttVw0idjxj7Xb0srDY4mFYjyb8/ztItSDB+PDs63nPh/xbPtjm2vFMsDHKyn2oxw7pPEdq8Dg5v/AIbg3GMvABHOv09aMfOmp9ftwDhuYPg3UOSyQIqD3/3geguKtTgGAXXip+tbc4vllPGoWpwHzlMtJ7CLgwuKamw1GO38+F+7rslvPB8/twDwsMxReQ5lBxoPpJxXlphc2Pe9x8N3RtboMIGNJFPH+OKtQDTnwIx9E5H8wjEhKVdwS3+XW4P+yx4N28b+d4bFNggYLNSY5r9ztE7G/nfzF8snC66+GQgLJq0BMp+0g4r1HDhf0/FYWlzEal0iqoyb73YeovnpgV0/56H3VwzbztSTxrfWeRoXGZgoB4/TXnT8Q+icfZtX8ReY+X+eiui0Kzy0Duqk++Put+0PjfwcHLh7fqvT/NXy6+HZ8XhkhQT39ID/ACz99R908Rw32tajiaRgqCRieApmr6YlQIyPqK6cMaZqioCWZVHEkwLXczqDuABxcfC83TWpWYJTRmY7BVJJ9BbD5YDvjWZtkot/tEC4k3UtpFSWJ0J4542XShoQaDXTgce+LvGS7RtVogtRchZwjJLI6hmoxLI6d5cutK1HliV+YLMiVVaoUtk6upylSpMSSN7z4miWec2yy6dsi+LgHEipm70iwXxU2pvvDKwEwAdr19WnTxSrTcSB4syRmOIgg8b+aoAIzaj+492F+x/WH4euSfmoNw28tT+WUuoQQOI/lzAdo1xqaFYV1YxpKsVImcx0PEHhaGhzJqZByMIV8UiZIOemVJ6GLwmIpNhnUFgwZFdTBGTdQdiON6jF8gpVlKqzJLh8gGiFKwJ0sARuJ4Cz4rSvn6HHdnueyblQWe62NwT/AJckpt5fTpz9P6mONFx42tp80puM5Q9kMPhn8LyfeZcPxtnX+XMZRJKd3WXpJRvY8D2NfwLDQGv9/PEqW0aMBjaylTwdQcmn51zL9eGWXEWPSxK1fdrU56Tn7DBtd3hGQcH+O2+YnC18LHe4SuAeOkx/cNS/G4gtY3bqlKtmGammnaaemuIklwI71R02WmqNmzGtNDl4HWumBMbyvAVqpeskEoW/zGUMw6iczY3OKlFdXe09beGPEV1KSMhnleg5X8w86oYdKOEqFwlVEyorUZKbAmAYJAyO+1n/ACjh69fDI2HxASmTU1jQrGm4k+IxnlBE2XrkfiKVIGvLgPdjwublY5SztmSlXABNGIGg8qccMFcGiq0aeSqsZaUWIyn8BYvLKrLhyi0jSOtiquxbRTIHiYnOJnSONp6lNkxdSpi6/ieo8ydVVtRIkjh5tFl/MOGpnHLVbEpiB3SK70lC95WUmURVy1QRrOw87g7mglhqdCh0/QcS+mJnqRouoB+m3b2GmOcyVWpFalSS0EQPCknwnrmcu2xalRHNSpm9GgfBP+tW4eYB2sj5ervRxWujQ0osq2pj3lSB4l6ZDPsMWRRSrTWjTgJicUBrA2w+HHxBI3nMm1yPMhBRC7hsqj6KtTQt6dg54a7bbYnE4KqXXpnva993oT2VpwwrYigGAOqofC1SclB3VOpPFvQWacOmsKx1MaTvUI/4kEx6XpKtY40rlooIQy04zcjZ36AHNV65m0hxlUUWqIppgYilSpSImlqUT/i3ujaLVrSDPIzK0p1atDmNTryNTXXQVFMHbhFmiKlQFCqdASenIBwA/DLQ+/AnLsE+Lrhys0qZ1H9vTHhH49lsOX1e7amF3dAwGQHeU8mH+JLY825jTwOHZNcVqo0Kfua5h26bZTubUc1od6lU1CAKdRqbNBY91VAZDA30VLGObiE1Zsyj6RAOo5d4VDeR1x11DC5hnOWNTl17xamneHNew8V5Ya6KDgBBodvsqxXI7nwmCI4i+CnrHe0/E7Ccsgv7p4HqNm42kWti6TFqrCpSSTrZFbxDZZYalcmMj57XSpiRSb6PWOijTOmWGpqkZHWozKx7p3piNM3V84PpKtfIkfvpjmW1NapUrzFQcgPMke0p5OND5HEpoFRIqEKB9oA5D2H433v17thUg5EbEa+EAcG4FTt5XEuLSowDUFLOwH6bOhknpLDM9lxjDstdGokxrDbg90AZDk7MmUhxkeOd2WV6zyhJVDwkk0jP3ooppSunrXA2GD5aX5hCwyt3NNf7gYS4ivi2qM1KpQ8AQal2PeMIHi1CRxulX5carVFNcToBGpxonQOCzqAOeQnperwmE5elBUrUMVLtUbTUJyNJTJ8GgwQDpne7Uvnmlh8O1apgu8hu7pt3oAqtuzQUJWBm0TEgWau7vJMTEZVVgGyyUDCvLTSmA89xNcyZmDOxoNKk6cABhpgUNSgO8VNSsyeE6gdBiZ7bNwmEpYHDpRTJUG7RmTuxPUm0XNHFHFN3b1NNRVqgONJXvBOmJ2G1q8fzStzXF1MRUjVUOSKMlUe6ijoBZRdznX6bfHAYtT8Y9RiE4Wmfsj2WZHlZQxtQfaPttb3hs+u8Tj6ROAomi072XTsPZ+/ABwVPpZuluk21HMX62t75W/Zy/j22PWG4kGcJcvl5520PuxHW7uDoJ5m8gP3A4kLUwdMoJ4ZZ37Sm+lfYLXA4hxrGtgpjUATpP4XXxAESVBiR3jAZbTfrl4zQ25r+djoedan44kwxF2zywPJU1JfQnt1JOuLDMZEelxsYEKQvTs9L4ZmGqsCNwQQfZcL1fEC9QsCfFpY6j18RBz7biC6mQ92CFfcDgwsKK4UwxqvrTj50xJpB3JscuSJDH2XMKab945sRnCNpYu3rGR2zscl9fZq5Ye2jouX4HBPoWiVziP3UOJTTpxHiHaGIPtuAu52+Nm98qNqnX2ModfZFggn7Rqf4TwuAsruMshi1IqY6htDw07cFIY0c0hhFO00A+zExAGYLeuYsdn0jxN7LK75RI7oQSJJEHfgZysZF7xoCu37zfx8LEtZxO2j3De4n92Ga32e9uCSuVV+AHvPHBPeNGem1GJ5vhcKIqP4o23PsG1zGvpJ0hAOEkT8LYYD5Xx/MfHRoaUnJ2ML6FomOybXhtw/BKfIjDUVtbEhZLhrmQalIsuX0LH68Ne+7V87wnMvnOjRkUkXzMsfYDA+NrjVcjdZnYA7ed/QOX/JNKjBxWJeq3FKYVEIHAkgufSLW49oY8IR7ySfhTBa73i6DUjaKyDMNDGKeSiWp4+eNw2LQbtH1e2/jWM+ZMbjZl2ZeAUnL0vBCjiavulmP3VGfsGd/YcNgMPg57ijSoz91AD/dv8boj2KXLmkEMC9srZB7q6/VimeSZhVpM7n26MWVieAJbn6Y+q4v5gwGEMPWBOeSlTt1zgX8TbFNVbxaj5nO/mOC+VecY5dYpd0sjxYhmpzPECCxjjlf1jTd/wApt0I78nUI4mJKofIO320xBiV0qxXKNTlYDjw4rrT3Y+mYv/xBwlI1Vo02qEDwEkQW7R0v5iUNTsHWfwvCYX5AJFI4nFZzNRaQMFeis2x7Yvd7flco3EUVOjaLMlTr1VZjy9kZBTy446toTIwywk8ywHcBP1fE42OK/wDETG1W/SSnQERDBjn1m8pTwL1oCK9ThtebwvyXyvDjxpUxBmdTvwiNMLpEces3pZ8hdBuXmByVtyCO6Ywn9IJqcvvwZ/ZsyRh7gMqlu40cTEZexmpl+FcM8R8182r6teIZ1cyVRoXaNhHssjAfK9etmzJTA4EgfXYGG5Ly3DaTSwtJCghWKSwEz7zSbmxWPo4SNYqNP/DQv7Ysas9+KlrmVdBTUZfUCgOCN7+zdsC0mhmYnM0ZEpIqOQ5dlMowrqc3x2JzNV52iSIF6nC8jwFEnvleqeq6YuZKFNMlUKOwDfrYteti3VThhSSYnvtcx5Dj2Gx3Ue7oJHzMPwqXqO3Xtx9f+KLQxiK1tViIpUh2BPb3V5HGTP0pzJqM09pm93h6VPDH9KnSUcJpqx9pFmQDwsCvSGJRVqvUkZnu6j0wezwna/RYGAOywPSv0mEamo497h9uBdx4m3SaMRNKVi0AXQDThXix9+MXQ5XjcUf8us3kp/K9x9otME9MvqizKlSnQBLuiDqxAHxsYImgJpDKABD+LbqWmfW2K3sLmSIyhYRHQ1LydSnbl9PjhQM93dMAGlkJ4AZvq4n6sZSn8vY4HQwFOf8AiNETeqyuYYuiyd4jioueaS23SN7jXIQMuwW1xWsTZurf28Cg6h1NW89dTgBb7JfXOYtkjy8eowDemUmtfKmM9/6aqpk+Ip55/pkv7drf16i4dQ1UhFOxbKfLifS70sYtYErTqrBj9RNE+U8LiR1qMyowZl3UZkef9bLtPt8coV792Tm8QX6lpX68VweFi0aO8zkk95FTJlX+JjqfIDCVfljD6SzYhy07Cnv6k2wqcyoJqjXVgZFFyJ82jLti7/Sq3eBRRlCM3NRRB/diTfRSrMAVQCTmHMGPIA533+0dqSQhpLqWIDQro59zUA+OJY8OWSEHWnMSMSSfcE+GAx8tYAKDNYt08IX2jP4Xw84qEELTRScgWYmPQAZ3wYiv3hBWmKcZEM2uf3Yj43N9EJYE1IHEad/U2Ok3jbs4yR3BiBGjPRzp2hqV92C3yG1xBvuomPkgJ7KCtftriZeQctC506uvqHEf+WbXnmdZQf14PGFB+ux2q4rvBD0+76FWLR56oszuafnYUbvtZlqLGfJQgr1yWJPPNT92DHzdnCCi2yhTr3gi/WRX3DDIci5foju21Tv3hj2RaKrznEadPeVDnIz08eLDMixDUrCpIZdEe7o8U9dU/hZXdUpJ0zlx/KxEW62EWYHbpXTNVAszrl9dCD9WCbbxlWkUUZj1IejFVIPOpFDQ8cPn5Hy5o00WBjM94xn4XmjzjGMZ7w6jlOt5j22KlWsNWuorCfDCAQOhMmbJFOkBARY390R9ViotzgWRv9jcOHGipI6njXkGr8MGxuJJLI9qJUpShqTUfRfSleFKjGkqcg5cwAWjUUjf9Rj8CuV5l8fiyXb6Qqk7y1TxR2/hYtOrVDHXVVgdgEVY9dWdlhaYgBFy2yGViLe+t1kd3srs1+irsCNedQfsGJcu9yQtXK4cjVo0DZqmlag1Jrxxoqvy/wAsYBRTqq3/AOUZ+Q0TeRfFYquVLVB4QQp1EEcdyeNi06tcMxaojLwASCM8pbWR8LMkLsN+wZ3ETdrYSNmhvVXsVhmGtRXMKeumJY3vLrGO+6tVjGFFeasSCa/VjVVPljl2kafpKntqJHpNMXlhisaravpLmAPtsSPKTYaYisXMvTKjgqGR0nxEWX+nn+monfICfPK4ov7QyEtLdxxmtDkjZ/LQgLx8+GJYv7qQIWgiKqe6citkoRyB7o89cadvljBaPDVxCv2imV/A3nRzXGqdX0mrqiJLtn8bEGIrGp/pGnwPj1+z3bK7umQB3aRP3RlcSPc7R5GDXTog9hntw5IrzAK07eJxLO7IZCGtoa8C7wihJpwUg19SBh83yzRVQUxVQud9VJYHse06c85lp09/I6TJ9SfzsdK9ZnYOlMKPdIZix8wVy9tzmlSDatGfXMfC40N3byMTLdxoDzZJNSDoe4SRX0xf17I975O2lJHAKBp25WApr2a4Z1Plh1X9PGUmPbTqCPXOwRzzmMBC4AU7lFk9hYCT63AmJqM0NSKDPxa1IPoIOdzd1T1lwDJERqMf27C6Q0c0hWK7hiGv3jSyop15EhuI4VGOTc7YC6/IDgKnXu9uT2anXgK4JPyti0XUMTh3J+yNYPr4Pbfj8wcw0oIw4/8Ah5t5+L8riXFlnKGlVUD7Z06T5Qx+N2XDorMdVQzwLZDyyvhYupLkE0WarUlM4VdOYdlC609+LI4drnYhbUuTUhVdxoB9E5iD20rXFG+WuYquoVMMwMeEVRPsMHKyKfPOYVM+5okLuAHz/wBrK6Li0NTR3dcb+I0zpy/a2zuXuE+82fl+V+JbNcTNCGj1qCwuFUGn0gxXJXsodcdHb9rK1CyR+XUoOyhLVwGflnmKqH00TP8A86md+B8U2fS59jWYg4aiw4eJxH1zcYxdJqhpxVkdabhcujRpu5wy8HYegM3ethlmSBpLcSUrnM1a8faZFCn41xDW22xJGBhuRQVIZmApT6JCnN7q4AX5VxzAuwpaZ275fgJLWc3O8auiaFHjPifPpxyvhxlJXFM69R/YaPVo0/G+9wufib2Cyrta2jMsk8RKFQVVkCmvMPViQOJygkYGiHbQ2UQFyO8czMDQjt0FPI01xzCfLLU472qoB+yn4ne6nnGNdwwWmo0xpAYiZ3MmZvxxC5wrGOyLsKK7S3w/K+p90tEm65IuJECiJUBESEV4lqu+U68AGPHHaLaqBltiiH6ZiEykjTm1ajs88aKhTTDIqpw26C0D4vHYjQ8inpBHgBEzvInOxamqtIICqRnnJP4CyhSVZHiM9bBOst7L3UbU8hqa8gOOGIxoAgV5JFzadFURo2oRmI46cNcaKZ7TeaxGIxrEO2IbbTpp+DL91Y9vGx/gBZCUUQQATnPi8X13Es7V7ON3JzO0UkSx11XqLlZpKeyAK0U6k8sWtb3OciONq0NXmVq5O0leC8+eNBVxFLDqWqVETI5Ej43jXWvWJVkY8dTAzHWbG0moQADEgz5dLMGW1/WE6bSZJa1dgNQuYd0UUCpAHE6nE+z2mdkkeSzI4gMhysa+0QKiv5e3B+P51TxDp3U6aeqCVzYnsnIWAnLajTNNmHAzHr23Wmndyet3HoLhXF5NuIUymQLx+6ZaKOFSvHB+z2CFpGkz8QG6aqFIFOVRQ1oezXA+JxtRyut5BzC/xsbZYfkysQzuchOnj8d7971+ZtPDs7LXotrysWP+5DEEFspyLxzLVa+o1w3RG1Cq8cReVJMuYjvqSaa6CtOYphO/ePpjw5TKz4p9b0yUqUKQkure8QNQPsz8r6qjPj58L8UIJEgAjrkbAxWjzZXjU0pQOqlRRe0gUoOOvDDM00lApEcI7xP2/RoBjNDC4jEacmbTkrQQAB+0BwvVsx2hVGe39NrtkPW6BFG0ttF1bet/bRoszwMg7Sc2vMFdKeuPGgcwrkjaYkEd/SgJr/M0UDsBwFy6ljcMirUNIoOpJYT0IEe2zVoOwGlC3n+eQvjaW6zdmqqpOpgvl+Wd2SbtDHExMqCgbTvH2TlpyJpgRcWN1JHIAIVGXUO8Gc1P2n8WmPfSZEah8eHDhcyYGqYlAPOL59Hadro2NoifHPlNkm3+3FMrggkLopzCo1ahIOXl2g4VZ7aZGVenSvDXvFudCK1riHvmYwpA/wAJnz32s/6BVO2j+4XJ9Hj3p9osb6dS4lvYbZn3y36RJKFw1GVkYaGvBQxrp54VflZixLRNUimuYH9xPHAE1R9w+YI+ANnfy+vJlVPk4NkaOhPtH5XB9OowIZh5qbZzuNlO+WJ1BPtVzKMg00JB1+GnPCvIrVplfu9uprwHuGAyzmNKg59Yy+Nl/QalPPu6g+IsgLG5/wB9wjFo+WtD9dsD2tnMABc9zMRTOKZgO0itRyrxwuxzzW9HQnMOA4EH9GAzUZDLCB13uc0yJnfoRtc4zyuMPPl1stLtxarKrODpE4eug7T7PboNeWKtov7nqpFRSpckaFqhjrQcFpxpTicQDEUiR4onqN/K7tSEiVXLYxNyaTn1uusHrcSXQhLhQVPETrT+wSK/briB4lt2W+kJu9dSCGBZFOuQVoqHl2c6YjxFahSWXZR8fhYHMO5RhHibiuZ/jyv2X2vjcNSSd7kTbftJNBJKi1ADRihVePeVu6RX8IBwMsS7IY7a4Vn4oJZKqe1WZOZPAn34rUxWAcjMzO6p8bVVR3lVZQrP3RB7N7lIXhldEyGRnzP5XRdutqsmX5t0FQFMClG0pm6kTuQK+Q44nQTRNbkShkuo2zSCGhXKdANO6dfLmMaXkq4NcSlT6TRyV/eJV81gDSYF5d1CAaSWJcwX20R8DqsTHs/dEIrkhlOwjI55izRPHLy62jWi3Pz8CvbQTRiaM5omzgJmFI50U0YZRkOZQeNTXD01q7ozLFCysqlZSuVgCdRIBxpwB7cfUO8w+Lpga2ZZ0nvVGodq6gfSDF/LUxDgGO9OjeGbSM8j0ztGzvRLMaKF41L3ZIBPRgu/sm3sDszsHdeHbK5Z5BcLDLK7FYcpValtUXjlC100YAYP220ieQD5ZHmUghxmUU0INa0FO2p1xpxzLA1a1SmyVaGlyuuQ9MwxGeQKzaCmlfEkU0XNjwMjPrw9bCFByJlc84iCJ4cbNgdB52k33h692+pdXRV0zDVNfzqSuuNUWyi2xaX8KSxy6SCUuoFa6qMtSOQJ7xPDGspov+lilmNg0GD5G4+V8opYFO8qsGrR4VADKD6n8LAZGA8SmPaL7Xr1atRaVKnqpkxUdmKEDqojMes3jnyzBD1NOBppmIr9GvH0w079t9vezSNbuYIR7EdMyqOYWpzAHjSp88MsLga1UfqMAhnxHPYcTwBuYYuo/vhSYAyymNpAysapiEpmPebLwjc5xkOJFzrgqVL3C3E+IzE7wTnFp0l+9owFu5GR8yyLo6ntzDia4lyeH7mhdVVlHnlJ9A2JFVaahaa6AVhwMwx69bqK6TBkXCFJJLw5DShjNR06b3MaLxIg3Gi8RX9SXlzDmXAP6DiiTbLj6UbqB+U0+I0xzu06R5XLKNsRfe9frPncRDLwNlY/FchyholamgKsVP78cW/hy8tgss1tcKzrngXpaH8zBhWmoppzxAaI+8fW53ehh6TV6lSlpTIoxgnyjjcwrHoPSw3aq7ikq1BqE94AIHtsqN1t75VWUSRTuwCZ6FdfxNx1NABQ4Ftt13OQxjYMWqO4alq8tABr8MKuZ8qGJo6tad4Pc6+R7DcFXmHf1PA1NVGygj87Z4HmooYjQEfQR4z9nzHU9tjLTZB9o9pG9ypCqPqOJysPPkf3YgyW25Ss0QEhNTmzDLqp11NNR2DU4z8NmuxSfPLcW2r4ikhYu1LxGTCpMnyBOd7BGBz3DD0vKpUr5aXqDSIHiYCPbFlI5jHpxXs/Qf3YGWm3bnGep/Nz93pzOsfeoKHvMtP34TEBx4hn94b+vW2LYrAbMoIUHNNWU8fDvF6tknMb9OF56njcaueuZI96OHn1vRvC/ihrTLb3RMloTpXjGfxa8fQ4QYJdytwWmtZMlaMqA5ufeCnXiNSNOWIcNje700K5mn9lunn1F97rCv4VrrmPtRkfP8LYYvB6pqUxFTiOv9bg/mrtBajBH3TuPI3+ggEuEEiMCjCqsp/mL+77cZbsHjabaQkDxSyQSt3VkRlZKGhZSRQdgDaVwa9AP4tukH3h+H12Hha1eglRCadRFAghwSv7vXLhYyuVy+se7c9d8NXZWBZGO40xPnbX4p/ZzwdB4HmuK91YMokj/MxJGWnZqW7Me3k+xbqsVz8xGssgqstKuMoGkyjjTQD6jTHK2HLg90oDDccGHQ9t+xTUjDNWNJjxkyI+8o+F9pYtqBksT+Hl2XFpETCkDy+Fwtm3G3trYwCa6hjYkhZQpyEVBUOAPa7BgJdW6Zm6qUQHN1kXu1zABiubP5+XbgzluOwGArTVw9eOCmor01cDcDSrZ9DkLT4aq+JLIrU3KyfG2gx1lsvTew+bfTuYUiEr0qbkkGotMq7Ifs7lfUCbmqBVzgjyE2buZbZlR4JC4ObMGUqVp217cCJ5DbwSd5XIVqFRQa8OZ19+PoFDnFLm1LVTDKEaCG6kdmW1rfl+j3OBBjSXdmPiDdmRGXC8zguTHlT1CXDGoBETkAT16m2uNbVVjeABtF5/4/uS0e3w19ozzH3kKP34FeNZzJuSR/8ABto19C1XI+sYPYyWznP6hfJBAIjOTl2ne6Jwy+z9Z/IX0AqSDOUDPsFrePsev12v1+1x5jt1vl9snt/iHeNqP+y3C7tx+FJny/2CSv1YG4kFRhxnzz+u47qaanh7Mvqu9vFn+s/d4yvzttYbkB9KaARS/wD5sGQ192EfBC4pxuSfj8GDD2WPYrYGgZhNM76C1MnzNMpPrNlXrtr+svZL1St1b3m3u5BLx5LqIHmQD05Vrz1OMkGCTiqjJoFQqNOkmM2X7pM/GLGsRcDh1qd4aQchtaifCj/eCx7RMWXe/WW57PulDYbna3BRK9LvRzgClS0Ugq1PInGbfq3tjJuc09NIoaV85D2+gwd3yVGoIF0UaWekGZaMtu3ibFpDc2qXB4mimKqGqK2Jr+EORpCUyc/e6DgLYVTsL2Ow292t735cJPVY9FZgaiQNqGyEd0E4J7Yfldmu5mJHUJQUFTqBGKDnq2ClrqcWHc6FbUNuojhPGw2fTWQwSFIJA6AybXV8LWTlRo0prVUKN733XkwWIyA2Fse7NSi6AhS6sqk5CSpA+Njk6hFv7QDxtAWzADVmAy/SqO6ezEKC4WWAq2aJodUZwQHJUaL71rriZD3aJUlZo4lgywfdJ48IN8qYhQ+LRabMtfNTEQRuYuKqor1KtGGAxOCRkecu8VeHGRdaPL2KcsrVMRTp1MHKuAdQYNsuqQPrvy5TqxiTNV07j8yaHRj9mLLeUNcOSiSdVc4iV6Ma6nTU0FT8NMPqVQUXKGFRgXWcgOo/G0X0iriKdBjXRNB0/qKBTUjLxdTleTxVF8ZQSsmp69JhRqgeJn+60RMzleoOGw+ArYummEqN3oLnuWJqupz8IHujM7WNt73/AHUSEtQPTKdFJJ9nTWhPHF13GkFwzLCwK8CVzcRzPby4Y7zKtQxRrN39WnoB0gTpZlMAx5SZ7bYDleE5igq12LmpBPdP3aHTlkBuDHXOxuVfSeWpRpGjQqFiAxYDWquJYA/vQI2yvP4rneK5XXahh0CLRlV79O9qDUAfETEMJiABF2bmHDxN04YWyEmNGzA946mrNqfXXEP5mI1zhmP8JH7zibkhpmhU0VqlddYiowzyQZTAJj4WbSoCgi06IVEXIDs/jjffmVqrYmgatKlhn7ok0kYFc6jeIqCQNW+W/G0lXEfS6j1q7PUqNuds/wAhwF/KwC1ZJc4NQYnXQe/KfSmPMsMxoKr68P3YlIJORXTGYYG+anXofK5aRQCdTawZBQgZfXPlYgCzkzL+9H138zmIjIpYUBYPTVvNWqNOGhxf8k+UZD1KcUQZmpyJpUeXb246o1g6sjsI6eYz9tx98s+IFe1shPSzqlTuiFU6ogtqEgt2g5ey4lWqV8JWoeKp4mjgcpHZ1ulmEzFkt2FRXKgzKvaRrWnlyx29hfRKZgJY1YkElCNQNQRSo+zF80ADVBvu2RPQXUV6DHRqRiBMSDlcpK12YounKdKSQOp4mOzhfmo4kL3xo1EUkqW0suYGcjh7IuOLm3TgAxr9AClPTQ/XimG2bjnc+QAGOkMePD1m+PUjhakA/aXju2YI7R/W/F9WwUecm75LgMQIxQU4yDLr5AE4l2tg7nKsRctx4u3qOOPCQM49DYtWsq56ojtget8dKc+FmI/dAz9pysnD4avXOhaevV91ZI7RGd0GITOAqh9B3mJFTz7vH68MtpsARFkkRYzTjm7za6d3gDyxN3rKpLQDOw/O1GJ5iqydWQ9g9eNxNSpM4WgajCBLEQSeOXC9Vyz5aqui6qYQxvqlznlKbDpYq12+KoqI11HGg+2uDl7bWllELl4pCsS16a98mSnFqaUHDswVicf3KF3MKBwvLcw5k2JXSCdInsm1HL+TnG1VpUtVRiftQI7TvAv6PyrktDlsuqeMqJMz5381rabfAZpwHQD6BHHy1B8sKVzdXW6MWM4jVSG6KagDyPsg+44mx3zDU3pjQo+0SCx9NheJx+LZGbVL5kDPwj0sDlvyhg8MpOJis0e6AVRfLiTeh8TneOy5V3v7TdSOKKaGIA0oQoJ4gOzNz+GB8N2iRn5k5PaXmDmHquVh2cjifmXNK1die8Es2e5Jz7LTMrO3hBPHhsbrSRaaLTproRBCgZAAcLmBAGd9wx2jL1T0VdhrmPeqRqKgkV7RWmOEuI3ZUY27plzd5BWvLUDj8McrVq7NHiIngPjtd0QrqY6pE8TF+UL2X6QY2vkQ96rCVoT9B6sikcCqla8MSkZZWyxS6OwRVBYgE8tTyHPHs9IBhD98KZ9bvQpvWMNOZiDfoH9L9ldMImu5QAvTUHkQS31UJ9MGFiWCNekYxLJIIYHdgFVjo0rE6DKDitKjr2zniR8Beg5NgkqOTpkI2lIzz4mOt+utRxTUsYECczA9TfdraxK4gkkR5PpB2CqingZTpU9iLriTeou02LZ1sZ+5Trw9+UyE8XY1FXP1A49yzkBbx1FY/sgEgfvdT2XqqhGHRadI106hoCx1gZ3HWxVHDwHqIrN7oZgC3lNqsPSONqvWxSYGsF9x6cu4IOxJyEdl/bncWuzijSQ3QKnLF0yuU8sgR8oFfpfWcId9evIWJOrHWn2Ach2DA9GnQw6DulZag+3Ij+2IuyrxsuolfEMRVZDQI/ytEH+8NNzk3PvvE13KOkkjpGOEasx9xYmv2DAOCgq7anz/AHY6dVRtTGSez8BdjdKdNMOgp0xCjbMk+053272d5O9I2UdnM4qBMreWOX7a/X7e7EVn/lrlH4iNThi2C2tJHrcSiJQDlplzVFKsAeYqKfHHpuTDUnqvKpr05xnHrfrF5li6OEofq1xQ1+EPIDf4Z435YeHEZGkupBAQoZVlWQNJz0OUgfbrwxPnuxdMSLuaeIP92Zia5AxHLQHu/pxFVdMPS7+udNIHMgrPkATJNoPmuu/0taZprTVFXwrtqO7XKawao1GmZrBZAZX0+rAR7DduTqvcahWqVw5kPUOengLn2cMUbRNbRLaZVoXUyOzmupFa/HhidaSRqUANagABSABpUDU4vW51Xr6qeHijSJMOyg1WHYY8PpYmHKgr2xtlwsijgdZSpWJLgZqjMKc/uzn62dp8NyYrZFJeqljqxbVj5kmmPbnM8clIy9PQVAppUU0pidKM+Jm1Hq5LH/auSqCytCz/AB1ugVUyCx5CPqvwy43Td3bRAZcgqDqa107BTAm8i7gkaJlGY6iTq6cahVHDzPDA2IxHdDgoiSx/AWJiMMa1F1VSG1SPHqy436+FouJPdzTljkK66vXMdP8AD7hitIFGahzI7Vrmrx5EU0wJVxuptSRJ4kmT+FxPTYaJUZZEgZ3Ukmbr17b8imDl4vamVVlJJ/yixXOvP2xRzyqBzwL3+xnMUd5bTC1urVmEUrTBA6ycYSAPpUqBqOIOhxIVdsOawzPe6WO+kaQR7TkTZfL5koup1bcCm3t4jzvsHTq4TF2o1CjZrqU5Ebg+llJwFjeVo3ZVX2oycwQHUgEGpVatTU6YSoPHu4xr0JrJpJakAxQPmZxp7Kgg18hgGkhd0FQ+HVHiGUxkPIne3v8AL6LSpVCJmAwGe2wN8QamA2nKbJNOiYbQ49sfEW9xgZQwKyIygqRQqy00KOO6QRz+OM5svFW6PPK1isESSEZ7bKaF6+0tCFR25lUFeeM69E94da6XG429gGV6KrQoqoV0mNiYb68/jYpDISrAgjgbYIi1MveA++ZI9bfht6LIZYo8rE604D8pXlTtocBdp8VXhM8d7HIwQ+3HQd6oHTlK5RWnst8QcZ8qW8LGR0ty9NAIXwnqoj22ugAzbT6KhnSFWftQCR5TNnUgkBfSNXrmJyAED0158xSuC232I3AGRGbpPHVCxzJJm5NrnjIPHLqPPCz6KGAidMbb27w+HL5MdQiZI/HcWsFyVSabFX8Ub5AH0P1WutHO01FbKCpNQwYVB1GvLsw57ds9gEQiKpPU0c17yNklRuQdG0NNCKMNMJfolNVzTUZ4iMr0a4KkRJE+fZuD2i485vjtpMDb89iOw/0tYG2bkY4pQHZdK5QprqR26107fTDnnWNcsKd0EDIV0Hb8MIkwJNMsKeXC3wCoIQQOkZX2CSM79HX67BWnh7PlklkCs4qUNeFO9QVBB5+XPBK6zMoJkGZSWyKmi6cFbmac6UOFWH5XOk1Ao7OPrbNh+16AbX05dTfVPZ6zcc7Rtu3AZupIqUzAsKgMaAsaVoO2uLkMUrs6RTzMUoc5LBlOtMtCtR2UwMcDh6Zkgv1G1lqmo+FWY+2+KC2wAvrNpGbKo9lxJE2oM5VFnRlDBBQlSp1pXvDTXzxJkgmVSYgkB00Zo4y1edDwpzwN9GoMckEZWemFrEe7p88r7pIGe9jvi6C7uDcRXsYw8iQRQJm7rs5qaH6UanTXnQY5e1ncmMyRKgarnPmFe1ioPu5YD7iknupE+f1WwXAVd/D7bnHmLCbmOGzGrbe/Jr9Ooita2sqECugbN9WnoRXHa7dKqEtcwhT9BSzMfMKBUU92AlUfdXLss/8Al1QkyVHts0wOJzsE8zoBRBn+Ol2i6jgkQQ2tvGrx0XOI04HUV1GnZiK1lmRP9zCcvsgpKaDzBGAYAPurt0tiOXERmMuyzjB4m1jc3odblx3bqjxtbQ9UJmEirEUr25dCCRx5eWIK2al9LlCoAGbLp7gWGFpVR9lR6C2v0DbP/Ztl6m1X82pGYz7Qw/G5cF++eMu8cRZWzDonKZORzroo5ac8RUipIB81lGppkqCOHDqUBPZhXpIO4FsW5cN9Q/tttqEbE2sTm9NvDn7RciDeCHcsT1Oo1MkZZTyFdQQPsxVD3ZC3zbZiWSgiFdNaVLhNPM4X5rnv7LP/AJf+17BbPJsoAtd/Nqf3c5jOydpvDtM3VyopAbI5OcCnJUVlI7TUHtGK7N4wGWWUuj8Q7Qp9hJ18uGAw5kmR5GzV5cpObNHSBZ5QREH0teeajgq+eq5ZmlkeSJJBEUdScy5lZDrmjYGh9NNcdNuFlaIFjCs1R3ixcDzFV5YXkEkgNEHzB8jbelhaSe6s+eZ+NsshB0zPw87TYjmRjNwPI5fC+RZhXqizg8a52C660NKaHjStMRLndgxJU9Q66nNT3KDT9+FC4dp8KODvJJAt+KBbcR525NYRmyx0jO8vV5iB7r6vb9QNlpSsSuJHQilKKyg1bia8P34Wpb15Qe6FPbRB/iJ+zC2ngy8hmER9ne29PCrIkao/e/AW8q4taeYGc/avLV+YVWUgHRPXQJH+JjZqXdLaP2I60rUkZs2lKg0P1YVZLtgh76k19lfa99P3YBTCoPdQT2x+NvKeEXUPCR2tt8fxt1W5pH2iR2T8IF4+tzJghmorGfdT3vWPwsxNunUGhKgDTRj9pwsm4clg8uTnrExPu1/dhUuCJIkD0a34oIIinq8nEfVeiqc3OlirMvnTOftvIfTah166/dDcBqLFs+A8XxiyU96xHeeQA6EjQ09K4AyTMuitK3bWtDX1OlOGFiYEHLw+23C01OZQDyt3W5u4EsahnLaD7LzFbEOsBa7HLOSYM+piLnvfMjDpyygCpGY08sCs55g/DC0YAcSttNP8Rb487qD3RUHnecFWeMnsb8LnSbhI5GbOx7eofjoafViEqg6U4+f99MLPoMbR7RbLSAL0o52TGot7GvOCq7kZj2EfjZDryZ2kzmp89SPOlP04jLJFCKtVtdFU5qn4YUGgyj8jbNqRfgo9L2NHmgdtz6i81QxOk5a3PnlZKJ2kYLMFCng/GmnMgV8ueKoZpRzAYAFV5KQdKnmcI63c6WNVZjjHi9t25xoVe7QZtu17nCYiq7qqH3u3K4PlyjVk1qxGWS0xwnrZmaS22HbHumYCWQUGYsCV/Ll18+XritZbXeIHjmhgJXuobhyoL6hqUIJWoqDw1pjOYp3Ksae/2VPS7FXEzETel9xc+mZ7bv4WHpaklqt/nuWhZjmdRJPIzagA1yZjproSG4a4svLC62+5JvrzLFlqsVu1SMpGWo4UI9/ljOV6tVXg1FzgkKPhJtlicDTVPBTBYn7XbNwhQ+ce030gqZLZdBcTb/D95ZzLJ80EkyuarSuUtRshBPdINK6GrcsEoHhvY/u1nKAChZWpQkewwprpU/ZgLE4wKkpSb3QdQ2XhJIsepQqUjpLqg6TPtF1SmQcyLuGDcDfsNtcCUS3UhZU9jIcrOK6R0NQErWp4DlrgzZ2a3HekJSGPTO2lFp7NefkcRg0mpjWGCREfaY/sneOp4WTy/lj43EeJilEZFyCRlnpXhJvuc3530rkNR+7fFhay37HOypGOZGVUHEgE6/bXniXfXcUcCuyBbYfyLetHnI4u7cRED73OKYHldXmFT9NdFNfebPQi/j+N6+jSSlTFKkuikPs8WP3m63x6q041HNjAHFj2XEE8Wt4L9eC9i3JmvdutrGUMkhObLFIGydanFlpQkKa8RlGEm93OS5cszA8go0AUcFUDQKOQGK8vw9Hl6julBYfaYAk/x2WSqRceKofS17t2ZUO4Rip9SLlLXdue8zXjd891dEWrEKOHE6k+Z1wOWjfePUDkP++PBZJJ3Oftu3YLqsU1CrkFAA8h8TfO03YpzDqSGg5Dt9cR+9cvoaIOzHCOAvuwvvab5ubsBe5fmE7P78sMmyWFkUae7uVhiUdxUyPK71/Ax1Apwpr6Y5Gkfjd1VkHfOhNMAmSDpMdt9mbGr16TE4dK6pWOUKVLrPRTfuz7ZZKrS3ZCUQmOGWOUCQZa58ylP6RXzOI2+eLVosIkN2FYoWahOUnUqlK6U8sdCmlT79/dByhk1T+6Z+q0HMcfUxVRlpIKNODED8et0rYha9RsJTaHjxFkqaYjPxrpG3GbJw6fR6YV6jVm+07bnPp0uFu3ihYnSNM+VO4uZ3aJVJJrmOZ2FdRx0xXLfLc2EkklpmotAjoaq2egbIozEDiVHEcMU5tWq8zqsSfCNlGkbdggTfeS8qp4k1zUqMAseNW2JE8THtuuFp08FSSmk5cSWM59SSY6Z3LUrgeHT4mHhB2nhP8ASwl/ud00jNcAqmcIERsqnLr1EYmrGp592mO498jlVYp7TLUpR4TFIsbMaCimjIa05YAXDqoATNtJJLCf8JGw+u3Nf5XrodeHxSVJ+zUDIx9RqBvpqEnxddh9djU8erStSk6Fd8sh7Yv69ki6cM5kysv01etNcpzRktm4cV188fXOwQlyvXDSdXTPmVDXXKKU0/NTGeoCoWdNEzwK75Tk2UeRs561TC1XpPTnRKsUM5rxk2Y0AAz/AB5XHpDqCDvmJu/9oW6SMFkJeo0lJkZwwrQR0YDj7S4iPtFzbT9aSDOqArSA99ua1JIY04VOFww1VlXwQM/c8IWDuWy9hstsQtVNFNwhYz49l63LrUHfPtzn0uMIwaWEgdNzZBoHlKtb3LxxkEyIuWWSP+0xPGooOFMBFnvtumdmicyO2bu6qB2EgAHTsPrgYGlTSaqh6kwojQp/xDKzGoU8QgUMIAjPc9ouTM7GB7T7LiDGm0kWZkhvI0t3tXSXITn6kjIGQiormodTxFezlhZS73BnmY90yClDQBfQDThodNcBrVw7tUSorUyRlpAMHsjstmcHRhABOnPLc+ZuXS0AqZ8zY3fNLdvws7FuhkljraXEMmcqAZHCtWtaEnThUVBBA0wGgurm3cnrKc1NCARUcOIOF1XDBUaKlNxpkkKCcvT6jbRsAtcKug5bQTOflc6sScwwz6mxxVKyZ9tnJ769mugKyZVGUgxlWYZ8mcVFGoCPUYh2m87j1hIWORRlAiAQhhQDjSunZhRTo0VpzCliZGYIGUx2cb1HJ+SjB1e/7h3lWAMaszvkbKLNqsDEYvWug1FXbjFskmWO1VJGb6ClmBzUrUk+dMCZtxjkyZ5iCz1o5INaE1Ob9OGPLqZocuw6gZ90DGwl/F+NmGpTPh90/dbwkehi6VSHrtJMat+MC4VVh4tx1Gdp3iradzO53c5tZmjZxlZFz0QKAuYLVlNNdRjTJN8juY4+qsM0wD55V+5kkz04lcoJUCikNXEIK1J0FX05HQQYI3BAzFqMfy7H/SEr4ahhn0EnwvUp1GJj3iCoPrNzDw+9IJz8Q63PTxNBl0uzgnLMAj8bw0gg0PEcufwxst5t2y73JB1rWOFeEzSgtLxoDE4CMWPmxpTnhvaD+c4rBsFxdGvTE/6id4B+60IY9TcVk/R6VQfplZ/ZMT6Zi8arjUNx/VZbSMDtl+GBRno5DUK/QyNkmqeVM2H1g4fnODxCk66YI4KxJI/cYKw8s7Gm5XwtRSNPiB+8NMeoJF5fXDJu3gXftoP3tozqRUNHU1HaEbK/wBwdfgVeNLKZ9D7DBuO6mV94FfiPaMrW8dSRPE2V1ZGH0WBU/A0OPX2I3u18n1v4HHgxy/X2+XqX6tbXp2NxcEazTUB/LGKfbXBvwZZGHatvgp3pFQn1lNf34mp5L5m/e6vkLhfN/IX0eJvM2/bnGkWw28DzCBnAkA5yMO+UHrmGFz9YG6zwbhZ2MK5o0tgzgCpBZyBQ8R3VGBnrolQhjnUlF87p3aOQzbqcrmWkzCmR/purntjhcysVBAG+93WHh+9tGkWS4W5VjmXUyAqDqBpoaEA4F/tC/tJbqe1E5LJBJFWigdTIXWoB4cwdcXpg1KikVlAgzDAsNsosZqVIHYKWmSNzfMVjKNHD1v8AsjVdY0qy6ULZw0jcC5gzniT0Bs4m3quZgn3sTFDXTuP319wOYYj7d4juneSXcIkVjBlygq2Yq1V4EHNqRr8cMqGDw7VWpVC7oCKiqTkZ31Dja0d9QUmjVLOPd7zbyPZea5nzjHDB0cVh0pUqz6qFYhZZNGa6CdpHW9BVw1HEApVpLpb3o6jj533L8xHr0BJ2kMdPdXBU3223hhW2ztnYK1DR49KlpEYHQcspoTjWoacABtAGQECI9lpMLzFn0q/hqH7BGRgfZYZRfy2pUrEs1SkKrMSWcs0knic72OP+XqCGRTYUwP8AMpvMfvI05+VgzNEadaF482gpqKjj6+mGGbYi6dSMxya6CgVuPHU0rjQgN9lw0bzlkbVpj9JhpX4i8O3d+9UovSVslZDI1DfI79ot/W+WyU10mWrnkCNJj1MTYAW9tOpELFmy1yUKGo/CakN6aHBCXbmt3qU6TciCVPxBOGne1EPjAAmJmfbllYiYkVBkdQ7RP12iTD0qynuahd9M6GXScvukkhvLI2ZW5c+EcFkak2cFWKn2gmxCW5idWUzBuP3ZOlPPkcTJ7WRSSJnOnAnQH1p+jB7OGBB0x+1Y6VgRmo9lrEFRCI1at/08mHrGRsirQAOVRmy4nY+cZ/C6V3O6i6md3cMRUS5JRpwqGB4D0xX0Zhqwc+eTOvxBzDEpwtNtMKFjisp9RF+7xDxA/wAUH8r7S5tiKWvVVd9REirpqzHY4Ow8rg7qsmeksO1A6+0Zi/LWMvlCIzkt2Hvdg7dcFrO2Lkxx3AD0zd0ADuioAetRzrlGnniKtVjVmAI9liVakeJky2zPXs/O4cJhTUZBoLkt7uefQZZ5255dhTUJSnX0sfEdCj7IkAPMjjOnayu3rE9o0TI1syuA5BoHodQWJ7OI08sLV/vMFxGLOCEoqMGeQsSXcCnEivpwJwLiGYVNU95Iy7J7Lkqzh6b13cTpIVdt9recpp03who92cKUeHgxrg5gsT7RceF7vGVaWDoUSqawz1GJYkjcmc/K2y4hg3AxmOZhFCxqsbUqw049gHZxwI2JZreN5JWVIjrlPEacW1otR24QY7ECpNPeD4jY2JbU+QM8T1vX4DCilFQZAr4QOll4dNKcI4CwXibe1lnFpbiQKKgsC/epT6OIm/7zaXF3KYFVekKtINCxHEH7NMAY3vFQRkpuHH98StM+5w6yb5VczAvzVBJjhvcKK0ulyvm+XAZ2KsQSUOi6AUpXWvHFdvdylookKyKVMwq7OyiQ+xoKinmcJ8TUp5rGskCCJEHjd8Snh1MCCp0bADLjfFVt/dzvytw9fbwsksfUWhuyCqt7UQKk9gqD7sWPMZCpMccRChcoVgGJ4E0YgfVgAQCYUDKfeM+WXW+mBsBPZHx7bk9fhfbokaGDoCR1aquaoAqkk6a0IrprjiaOSMHRWPtKMgoCdR7XbTFtJZFPizkxO2cXxW1RmYGW/tvkxfiLvtWQSIaotHDqaqajhUkAUI1wNjvm6mWRcgZad5SoV/I5iT2FQMGYXV4SrKG1bNcHdLpPHPcGT9V+vgfO2S6a2WWya7NLeO6bqugqKPQhqUIYajliLGYZI2tpnFHTgSdPwuAew8fI42HIaj02gBO8Wodtjq2M5bzec5VzAYWsGLHT7p32/pYvM6NPEYWqlUstMpLad4XM8D0stgGEHO5viGOxksyLHM4R0Zi6lSB3gdFAWmoNTiyLc77c4pNtaygklRFqY1oXj9kTAqRVT9LzON7jxX1q1YASIEGdvU3yh9FxWHFTvzqI4mRPA2i5E2BFKpTwjs4V9Talgyw8hlldcTXx2CxgSjg0qUWjNPC0cQTtI4ZXn9yhU18zWmCu77PcbbKYpwRUVU00I+2o5jEIvgts1+3E2LRgykCleWmKAzQvQ8OR8uz9GLX6+X7a7YmYMannX9OPmRWGdOPMY5fr9frZ9ivDCwCR2zkFj/uFBRY5MueSup+7KKW/IWPLC7bXOQqUJR1OhB/T/wBjzxLhWVXh2qKCP9MwZGwuOxOZUXq0Zp08PUdTIGIXUgHE9kWXvbRcRybZduJpbMo5eSP5d88YUnM0WlcpDEsOIKnThjzbtztrmJbK7TLbZf5MEcQkzVrWKRxmOvCPMCv+WSO7hf8AM3KmxaDE0VqgqI/UGbAcbbpiT9sCoxymozFQNvdmLD5Ri9I7irUwxqifDh2BUDpG4i6V+XLvRJoAEuy0Epq1Rpn3is+lkra/ikVad5eTE00roKjhTkcDHi+/ZtskmmQAL02jLSoR9GVFUa+YAbtXnjAU8S1OKdRc1ynb23reZ/LC11NZdCznKEAf1vQJUvO4Ln9GrW+jla9OquUVaZ+MZC26GUOgzyR1pxGgoNdSTyHM0wppfmSK4t5c8RkjkjqRpmeMrUdlDyOowppVVYDUyydote+GxfLaiioCaeoTxynhejOVwU64MG2eAsyrcQg5JBVFr3ircG10UONQproRXswn2n6wdthgFteCeGaNBFJEE1Vo1ytlckKVJFVJII00wwZTRbUgJJ3jhd1pVZJV0em2akmCB0PW7t4srsYOYv3fLtVsrq6ikO2WqVrdIFMtwQSD0Y2IRVZqgSE60LAUxnu9eJLzdxFZPKs9rBTpJ0kRgkQyRtLkqGfLQE8M3sjEK0aTVQvdd7VOZ1E93TH7QE6j2bWwRFQHQYn3iOPZPS4wAM7vp6jysDNfX923US6mmWpyGdsvPiR2Hyxxc3MVtRnPe/DT7ByGPMFXJhA6L+Qyv2hqmQ/3XdJI8MfULtqRMzl+Nz7SXc4T1Hiz5VLVtSS+n0hUg6eRwJj3u7mkjgtohnkbIq5iGYn82gHv0AwM/cEwrlTP+pl9VmLg0AbUZ6mNvjZFPvxmyqwj7Gf12KMTUd0WmDqJgLMSbK20L7tN1drgla6iqZVUmMmtcolzFVQHhXNqRUc8MWxWV3Yxzx3UUbzyusoCOQSoQD2zGi1XWnbXES0akaHGpDxyIHapvtZqWHp5mFH1noMzc6zXc90rGoPsgQT2MNvW2mApvhwzVSgZiJIM5RsTAs74f8LywWHzu4R3DS179sApt466ASSRls7U73tKvLXFMniIbSs0FreXEzSArJAsp6CjVWSRq1Yryy09cTfyygcMauvXUU+4MhE+09bASvi38QLYan1Obt08OYAPbnailisWvM6eErUGoUamQqsRLNpkQQSACfD1tpi8XQrEAUaNVlPhdlkqRxByi3uDxHb7fHDDBBGsYoZVHcFTzHHKcvZQE6nGYx+IdxctExiIfUgRdOvmJEo1fOpwSKlKmAoUKOMZZ2udKclwXJ4ln1H2G6PyRqxqO7tJypn3sh16ievC+HEVqkCoxPQCQAOzheu7D87mla4eLpGSSdJM2UO87OfugT7JV6mvABeeMeke8s0N38xM0IkQPHIWkaJmqQ5JBBhIBFSQysPOuDcIKzPWLQE1Sue/l5jOxlfWIEBhtBgEeXX67WY1aVNaaLPeKNLiNo+95HazmlDmSVPXh/T6r3gKLiRiJFAoAzBgeFdQBWpGMbs/EMzEPHMjNpWsa1ZRwD5ANR2+154ZLTNViJAHEyPhal6rqfFG/T/daVn7pZg+w2+VEYZT7T/W9fZ7aDWoc8MzivvCg8MKO3b784UivAqZjkEitSteB79DUaa1IYcRh/SwVNTMFj2/lajC81rUHGepejZj45j0N5TEcxge8oHZ/E265hyLC4yk3h0tGTJAcewQR2MLP3W4suiyBR+FMwB9QQBgTuVvLaEAKZI24PxU05HkD/cY0SUG4DKy+X4mljBKGHG6GJHaDxHaLx+K5qNtYn1P12o55y6vytgKi6qTHw1QCVbsI+y3YfS/p9xJNVQV8jTAS5ao+kvkGI/TitLBlu229NSOAHblfsVzcLnmPKfwvN16qkiCx4acx+Ysid2kj0LFK8gftpgC0iIaKC595/0wuGEzjQfOMvS2wA+97LdfzNo1d4sHgGz9RedLMfsgD9rP8rPDd0IGe4lbtVTSnodfswvNMfwKMKxgan3Fi2oUXoP5vTgTWqnqBlHreejoYPZ/Wy0t+GIyhj2cdcBusx4OR5CuFwwf7NtAqjIW5fmPEVO3jJ7bTnPNhPsiyZvzXmNOdBgRlq2tT6g4VnBxwY+QkW0gHifjbinzIt9qmOgLQT5WpFTTsFHopstHuOp4Lp9IVrXApVFe34fXhQcGAfeU200iMhHx+Nv6fMWiTTceYJBm0veHcsHy6kZx0MbdllYrhAfbBY1GXWuIKIi97Lm0prqB56cDhW2DPkOsrbBqakxrCkmdgPSDuLfU+Y8IJbPLS8/VadMVUCkiizqBBOpiBlvKiQeI6WYguXRQQstO0Lp9eB8d1PGPu+6vM1Yj3109cLThc41U/Vvytg+Hok+LxHsCg/DO3qcwIUHu8RHVaZj42no4/GR+n+mmUl2dhvmSWy84sz864qCrnTQZAP3n7MCFmlkYl58v8LcK9g5DC5MJTaIZRnmdRP4Wy7mmqgLRnzH1nrbirzCqmqadY+HwjuwJPWQxMelpTi8Q9RmqYzTmc0YHI8FURAsq0so1rEnomc/UdPdrgcYY8uZp2YeasP064CSlT2C1H820j6vrs8MwyFMD1Fs3rVgAxahS2OSd4Z7YOXpnaepTouCzYsvn9xx5xMibkyTqCWLSTGnBQUUfxV71MRB0xrGrtyrw+GuvwxClMwAAtPPjDH0jKbnOe8D42TXrrrLM1SudJySaaA/tapePWwgmk6qYaplHFY8hOeXZfz3OoIjRfOrVNPjjx7jLUGIGv4kBp76A48KQ21MfZF+CZjxkeRIm/NiW1AinTXYydRJjzO1+NckMDRpkzu6AkfAG6XkZwa8ONdcfPIrnQsGAqVpGDroDQDQaUGmLhQsRdRllM9k8LjNZnDBiIJBOWc9n5bX6qRUAbuyoB06tIALR7sgAbcN7qPAHqU8q/ux6cpOoZtBxAxeRMXyZ3uNlMA6ZB6kfndCCNiPjfIFToSfiRjpgCBowPYK/9sdvm/Zd5A3AHwuvuR4lafhfXAewfVTp8MdRJkaozAdrE0+GO3RoIiLspHx+F2pswYMGAI4xlfMiynKVAZVNcugP2VxOhAINMvlWuvkDw+OPG6VG87YYUrkRBg7cbFw675ieG+fZll7brUNLGtOpnFTlaoHZqaa0GJcG2T3EnTgLd7QpqantHpxwq5lhTWkg5r7ueRsytVQCW4cb3XJsciIqsDJnVIM75Z3n+XnEMRTSTqMR/HS4qqHZdSuU94NqG1PEHUa66YMJ4dvHJhkA7jCsqstMoPLXU0xlnowYIII68bYcwxOHamQIapwGxHmb+hpVkSCCD0tbyvDYlI1+FesyD5dblbTku86Nbwk5fbYDNXgCa5vqwaht4dtiCJWprqTXWlasQAF8q8eAwnqoeGXndvFUYAQTtA/K26sPO6krTBJMDck7e2wFvsE0DyGaWLpe02WvAa071FGg4nQDXBHcxIkR+ayRwOMztnDVQUrUK2rMdAvNtOAwqHKHxNcFnAWcyJmOgvUCnSXDBWkVOiiM+rE73ZiEBJznYWqD4t8bqprTbDnd2bVI6IFPhg2KuLiFoes4/wBjCckUQJX5uZdacc3STix/ecLm6XzX0qBKrHGOnDCvBEroPU8WPM1OB9CU1WnTXTTTIAcTxJ6k9btkgLNkAJJPACyqFNllnOqo254AcFHYLkJAF0bhuEt1I0kr5j9VOSgDQADQAaDEc2kwmKXCmEqQGzginZ/FXiMta8sdVbpUxNKnT7zVqUiVj7XlfSbiZ1XMm64Ys/3jDujBtdrLpHkyXMbEqY45TFJQfSUshSvAgN264lNqsRzhFVe69/UJV1MRGYkfWLsLoakgaYOdhJJFkFBzNMFLva1266eF84AVZBmTK4VhUZ11FRw0JB5ccNQLgw2I+k0lfSUJyKngR28R0u5N+iM7s2bb5b5xDDFmOUksdFUDStRrWp7vacHoYP2ZYwvGrJeXjZo/vCfl7dRxKka14kU9puwYm1U1Ze8nTOekSfS64ip3KGHkR4hlvdane92/chTUg6dZhZ7T0vlId8wLJBB8JM7dbtubFtzRYn+Xtlt88YEcPtEd061qaAUrXWpxCh3GZGyicpSvdABQKOJGbn5nA/MMYlNgtEv3UCVc8fK07mq7ltRAJ2MERfuX4OqyCpi0o9/J8VMcD2752wBIuHd+GTbROIZqjXRInza+ahiPecTRv90CWQBhprkCNXgdOFOeJ9GHxpnuypHEER6g5GxRi3TIBB2x+VxmhpGRi+95PbajNabnGssSQv03GVsjS56UoSrOSQSOWHEb9MoHVWuYVrTQVHLWp7aceWHuDjCUu7UKJJLOAhnpK9l5/wCl1ZOx7LAr4d3fXGqNl8Q+PbbHvI3F57t+wSfNxrLL0gsgmEdwhLt0qHIGVagkcK0BxpsO7202XuFzQE0A+KhgD+jGr/mlIEk5qglnAKgnsXj6XlvpY+0p7drWdziGUq2Wr3VME5dsSLaioDYM2DSuKQyTAEuGCvQHgTRqaDtpTDI8dpczJMsrQy+zGyyMrGo4ZG7rA9hBGmI8Wtaviaz0dbiq7Hwo0wx22mz6GO0T3b6ZIy6xtY6KKdNQ4jSBueg3uapTp1Y1Ceh6Tau9rA3ReeWODM1MzSCmgqCQvLtqNa0wRvvDnWQhY4biSteqS0E/GpqyViY9lUGB6PIscRLU1pD/AOYyqf7c2+FuKHM6bVSa6HSeFMKYPk0GPWwzjcPICsXJMeAEj27X6rgalOkFoOGYHeqWkieq5SOGVhZbrbLSZo5JZJU4Z4lZiQfKQItByxfP4dQM0NzeXiplBj68QCBzxQ3FXVR50AwEny8Cgc4iXn3KajTlw1kjM+VtMLXwzEuEWnULae7BUMR947A/XfPpL94U7oKn33Yz/YAdrpifpNPwGWXTPesGZAfu5SZ+FgnjsGlkpayzRshyzRzBirH6XRBTMBrpUa88TXZbIQu+3pNGrsFuLmR5rdhpyiqvd55TU11GK0KWFphR3LowOYrzmB2jw52a6CmXCppOkZbsO3eM+Ei6dzWJbVURwRkaO47c8z5XFSd64VjXVs/sAKD+zn4vOLX5dnkuCPkbhZitS6ZRBPRaHSN1qCOeV3wWm3G5VsyvFArqRGLRY1jYZtamhkUcu8ASPLHTie7nwLTBIC92gIE9WWfwuMVKpUJLaRuGyPwyPti/LhKOUl3Ye93jnPyBy+u5fo9HW1QqCxznf6zl7LXTsO6qvUkgNNTnmkCKfMZmVz8MM8FvuE8TvbRTvkHWaK5jE0NM3tq8xDoK01Q1J54mZtcBqpptwOoBvSZsUU63u1VSojtpWpkhGWx4HjO3lcM06eoqi1ANwqsw9oj67narh11RUKMo1NTEvPaAudp0UjRyUmuElWuseQyjsoCaU+Pnhuutts5LcvfSW1tOcnctp/mWKmlcy0LR0B9kSGhrphgwUrD1DUEbFdX+00R6WHRWnRbQpYLJnSp0z5nIz1sEF2P6WHCZ7s+gf2rqJ9bLd6rprWmrkgRrOho9M/baqLqGGU5RNFU936SjyZamn14YbnYNvSErapPeEUZH64eE+sMSdQGmlWApzxMGw+rwGpTAXNgdWfXQctPkbio4qlqLvSAglYqStQjhvCxPAE2P3eJCNIpu5bwp7ojprjfzyuWpRrNTC993TmD4QGQHiJMmY4wLGW+53IUdJknB5RtR/wCpDT7MRZ4rmJgkYhjBPtxIFUDsZyDICDwJGo7MEFTUBUrTrrx07+qMLrSx1V9cJ3C7BQo1ec8QR23AHNPSW10WPXaf3lMXI3LqY0a2au33mYlfZwjysvFvkcej50krqtWjINKVoc0enkBgLEtyWKxQyXDkd1XjEgPaep3DoOGhwuxfJeV4o+Kl3Dn7S/pmfI+E20Vq4TxEVKZPi1LK57CG1fXc1LFVl46x7fqsepRwrPlNOoBlpeGy32jL0txtd6uJlWOaUSRqe4JDoKgqf5hddV00IwqIuUDrlrR6VGSRXDdlUFaenHGcq8h5hgirYPF96B/p1tvSZHxF6GolCkWOsYcgxoRtef7mce2z0xtOplUSO0WtR3bSFD1lOet1K5fvZT7Leb9NluIFS9so2orBGhVXRyfZDF1autPYkU4T49xuLc0hcSg81qjH1Xh8cZpebcwwTFcVh6qDifeT0DyI/da9AlQ1VIhKy8QIDetNvwm2rUaFQDQV/wAOR9Y/EWudhSYSSs7HMj+4fjc6T9Xu3X8UcltKIZmWrwRvoG5hY5jUgflfF1juMsn86TovmIAWkbUPCulKnywrp8+w9Rvd1DgKbAVB5030z/gJsrDpy6i9WoKNCm2rxakEjT2Hb0sw4VwMmz/aGXown4i4Gas4Uan7IMb28eGLQtd2kYACwjMR/wCGv6aYleEJ4QJpKuXRchLdML3jU0OhqMutRgyq0pO0gb9tj4mumlWDLpOYIOUR1OV+pL4h2XLh0Oe8jLOwXiXa/wBpeIZ7iKUtKGSMRhc/dhXLqtKZS3tcak8MT/EUMLypPYEQsc7zZepJ1HqCCFqCCdScmnlhTU5nWFatRWmKiBtIKkh8t46mbU8yODNZHw7KJkuyVGHinfoPSyBQB0sTGU3MivGfxFrSbfvNleSW7NFIroWj6sjgCPPSrDQ5l5hRxx8Zr24ljeSK6WNB0QchRxG7F5DUlqCtOJqBXDrEc2waCk9UVEKuNQ0GQdJ6WgNSmmGZWqpUctIltWwynrcK06oJCkEcM7miTxHwuVt/XE8kV3FbpkSuY9SQEltDQEcRyIxJt57KzMlLky5mAyyOM40yhQaVIXjry0w+fmuCKiotdgkx7sHbbaby7VGNJF7vYMSFkSTsdj5m6IKuoh1Xb+ONyrpBPinbe5kEidRXSWXKrVKxwpEmn0eIahprzpj2KSC5YSLVXU90qoWpXtNNRXt44e1uf4fSy0BULERqO31zecpuabg1GUnKEAA8iSMsvabr3c+9B7IuSA21s1uLie3W4IDO0hqI6EIvIsDr9pxF2OeaGfLNmXqjPVgdWrwGhB9xpjaco5vW7lBW/WDVNMhhqpqcs+oHttBy5qlOsdWS1BqmOPstHzPkqVmNWg3dOBJWJVyM57D5W8Kypy2uZNelY3WdI3BFC2YI9Rw150PaMTZrdJEMvUjIJ7uagLV4AMdCezH0BANSlCwjhEi1PL8YtOkQ9Qxq8JPAHh1vBYirU7qouIp06qkQWDhHy2z4weovQc35U2Kqh6VNZ0+NRlqI49JixUMMF3kVGaJm0PUKlCe0EEHXsocWXFkvUVnRxl5ez9nPD01XpySAw4acjcNOr4cmGfreMp4PDYwolNmouRB70qyE9QwgiekWZicGKVUGpSYKP8PxHG413tc8JGZTTgpQkVA7ANfiMSVlmgTKAlzCGNI5RWVa8TmBzUr2VwVSxSPsfMH+IseFc56qbxuvun8LW4zlGLwxBKGBkrITsOgB1e0WwFarRp6VFPFUQxIp1QDVWdzIOselxbjrw2Y/ZvQmZ3Cl3NJAQtdKkU1JGmId7bG8i6SQxQUIOdgVelKcjw86ccWEPU/V1LA2+zcyuKZ1FmfsGYvyJ3GHUYLuqupwrP8A6gIE5SRGeWVgaGxEU1pUqEES9SVbbjHDtiw0vfZfmD9+7ZqKx4r2jFD9PvQq/fQ6uDnGnY1BpgPmgpikqkE5ykZepsnG0GxVLTOiYIyzvTchStraoSo+/OZPYOhsLlONpYNv+IRIMNIPkY26WYhvDcdWOeQRBwFaWhqco0UheOnDA63nowAYM0fMjQk+RxlWDA6jnB2srEUtLNSmdH2tpN7ZGUjTtlvYmFra0SrEB8wpzyvrd/C1mIfmlu6j+Agk+WX9+Lrt5t2jjjzh2AKlFqAOwtUhK8sLqmlydScLnFNV1dvH8LLNBYmTfWYuB9VrzbnFYK7oFVaA95Rmfu/RKsK/w4vvPBt1bKXaVFVxQIKSORWunGmvMYzdfDHEkLnkTGeQz4yPjbgYRNWTExntHtugcLMZX7uYzn0vxdxaeAOFjRWysoYEUDAaHix1/DUeeBdzb3yTqFtpgiBAwyaNrr7Q0BHYKYzL4XQ+k6iRIyg7Hhw9tu6mCYhpE5mD06bXbXI4XGQwbYxZuA5pc/Tf2aEq4oOZ9sV8xTlgNuMO6NCqo8dvkkIbqOVYrlBR6DNVGqQAGPChpjOVJVdOpd8gVz/2crd0KGFpA1G/UJy0gSV+oetzDeYPtuJxUj7sdTZa9sWugXgzIrAVAEbDt4hgVPupXFO1OIo1ElyZZK/edMcD2Hy9fgMJ6VYUYD+I9pYfhnc+NHeOf0wqx4dXG5GWcx+F8pGBvN+xSm0MaTZmJFOow7yaaUoCD54JXHyrKGSVOoSKE5stNdCAeJ0NcRkd9qZABB2ByP1G4lkRlluQBBH532YgG7mDxubFdAEx1mtpUX7u4jGqhuNG4OjDiqnngSvzlOndxqyKfu3VmOnIgjXn24dctx9flzIKqhkEEcfbBzFqmqKNPduds1MXHWpisjJJXUCJXIjtB63cauItnefbbpYra4hnuLqVMqPmDRO3/osdanjkqGGAFlNLAlDIJ0Zq97mnEcgDl5UofPH0TCYunzVCwehS0H1/3XgaWOehU1I3dkbrwMcCLRVEPJmXQmOxfe5Hxa1B8jsfK3ukx1urefDN1t6daSJlgZqDMO8teGegy+/Q+WDL3tzJU/Nu6vkAiklVlUaAgNqHXKDRZBWv0sb1hoYiQ3aNjavlnzGsIuKoIKectElu2Z62HRqd9TVyj0yRmjxqXzgkWJzHk9XEM1XDYqtRq5aRr/THXw+XDraK0MkOsfeHZXXD3eeHNomtxJFuCW85FelLEyh9K/y1LsD+ZMy+WGk32jUp8wYnCrlvpDTHqYs2LDNY8qoL9PxAqGY7zu9Jbs0rqk9uVoGeN21GRu2hwTu9qmQZnjLIPpqcye8jh76Y9dqlKpQMOpX6j5Hay8jcOFxuGxq6qFVKnUA+IeamGHsuCJpI/a7y+Qx8bZk9hj6cR+nFb9NzX2DZnbPEV5ZPnhlIamXN9MDsrxIHIOGXywE/jUr5g0x6TlxHThfr4QGngfvcb9bnbblZXSyy33Xup2HFXSFzpzzgo+vYw0+jhShkccGDDsPHEtWrTxCik1KkibEkT/W4dzYNLBVcIatYV8RiGMkU9QX0z8P1WdwsZ4qtU3jco9u22B7i+fgI1pNwr05KlY+5pmdgFXtAGJfh3PA19d5R15rmZCxAqFhaiprw73eNCOWAqmEpUKxp4eaoJH7q9YuegpGtp8RZrlwVao2HFTEDuCQfBMkZ5Tlv2X2uwOhYyCr8bSJIJNiWaORo5Jw5EuSRZVDKSvTV17rZCDUrpWtK4536wdJYo0V8k8MLClSTJlHVJ41PVzFvXAjsTVFIACNz28blK6KmqN11D2Z/Gy6YHdd4STOYnpcYbWhE7MR8cvhYWWYyfePqzcPPHVxGofu1KABfTtJp2nHVSDAOXG+UySpMdp9dr8zT4iM+F9qAAj2XI2B403W3MkbOXzRoV9pXdaB6di617Brgp4PsJbm5urgdIGCMIrymkcQkNXkY6nSMUFATU6YtVOmk5nwgSfS61Uar3dKmjVGdp0iM9InMkhVUbkkgC74F0p4mm7rJzAI3BI3ixziKeFFStWcIiCAYJzYwAoElmbYAZmzl/u13EWtLa4Lx5Msk30mJJqityRfZ7vE1xPi8PQQTk31x1Y3Ie3FkRWSFwD1WZ0YRpnOVVZc2YGppxASl35WvWVpBmmhOSrwJH3jvntZi4PHYt2oq1DBOr92GxYd1eqdkpCkYZSIJqzogiJNtcTi2d2VW8MRaapzWlTo99QoV8Yop97VFEAGhTBgmrrghhB/T97I2ARsh5a8Ryrz1xM3fbU2ndLmzEpkiCxSQysoQvDcRLJGSNRmUEq54VGmBKvjMZ5X6g5rUwWAV1Z0qAGQtSmxVwD01DLstrTOnPLO4qdTWA491lDL2qwkH2XZbMlcgJGleOnuOhxAnb5e3kmDg5UqAONToBT1OBXVve/32Wq6mAPE2ehX3f91ikwpIzgdR9VlV3DNHJRwY20oasHQNTvg1UhqHQjgcQbKOEQQ9R6ZkHd5jTUYEIZSBnPHhBjh5WRVRiTsM9ybKBVpOUcPLt87HpFQFmdsxFsNttZvAiwR0L6qYuKdtANGAPEHFu3+JpNutzb2xVFYFVIVc4B1ZVamYAsanXicLy0nPM9uc/jc9RCGmQMtxbCAFkQB12ix1KMBIJzkA9fLayG0280e5NtV1T5mIrngYgZ0ZQyyIj0BBQ18udKYhwbLL406t/wBV0v7KkYnBeroHcKDroUYEBqg68cQNScFfCwVvh2Hp62TTaoA6e+uTEHP3h1uYVkKE6gSOI/D+lwMKI0MQEJkAjL3TnlehwX1mg+Stz8xZ5z1Y2LGRAR3pbdj3u4aVibgBUHSmMxt93n2S9RJ88M0Mkay5tAwbRZ0I0K56KwIFK4lweObA1V7qSEaYjfqV4wRuvHhYppvmU6ErG4K56T6Ziw+Y8sTmeGdMSo/VXT0g/Z1doPuuNjvbGU91jvkZ2Ib7Xt3t+vNrjt3KvcRZdcrkUDDkR66YvM9tNZwUdCkrP0Fk9pRlMjRAmuYoxcjnkNOC42D/ADbgqBC1adYMQpBABRgd9LA8N9rxeKPf0RvkZUwfD1Ej4X8lr/I2NFSEr0Cstm2pWETAKxx2MG/pGKoFHJIGXvGd+Ab2RPbYxtuJUGJ42rxClddeR5jniTJtkFwPNFoOnIUOU8iF056VHlyxu6HzVympUdDXpoFaFZmjUCAZggEZyCL+cEeCSFJUgTGZB69Y638nxHyfzWnTRlQ1SVlkTMqdRBWdUHKGB439Q0AgnOx77Y50FGqRqvDXtOJv7NjjOYG4jzLQkSZqGlBlrGRWvxOPqNHn3L6ya1r0hkx094mo6ZyAnfp1v5Q5AA8Bif44X8nrfLnM6FQJ3LvJUa1Ryi6ozYkZDqRtf1jSOtjTt9ymgjK+in088TflZowIkuLrLTMzlo6sa11rQ15aaY+yrjcOwYrVpwpAY61gE8CZyv4vrImMp3AJHtGx9b+L1OX42myh8PWJYEqNDeIAwSBF/Zu7GX1mLGG3kprU8eCkcKV18tMTYZLqJhFJcO+Z2BLxDtGmhK0A44+294sxqE5Zee3t4X8XHMsVTYMmIr0ypWIqMYjjmfZfxKHjV3bQJkwYGmNXlEiek39obCYdwVelTYMCDKLmG3By4xncOKykf2UYk18ge3XywQlvbszIiSxKtK5TGwqTz9Dy88fZmrUlnUwEROe05jLfO/ji80xvic4vEsx+1q4RF/GqdOvVjRTYhp0nSYMGDBOWRyN/YzgsNAQUKKrvpCCMzn2Z3B6RTQhuGo4fEafXgt1nMhEstuWrQd01AHsg5hqakgn4Y+xAUyJEHPInPPsJn4X8fp895iiqi4zEIqqVEASJiSD6DM5xfyA1cQDpdnXwgFFGjLaGVYHnqv66/K8FVdnfDUXZipJKgzpmJ8pNjopGjrlFPLua+ta4niWpJ6Vo7Fjlyuw4mhrVfa8uAx9fKI249fF+F/Ll+a+caNH0oMNKAHulBGk7iOJ49b+TU8VXpBgtSP2Yp5+cz9V/Tj8tcpLmp9Ep6tTmdTZ6954R0HDhcMux4Ron8P8AemCKdPMAYYuOojkKtQcKZl588fURTHFifM384w/zhzMMoqVKNYgtOpSpOrrEDw8L+YtimJgU0T91Rv12i/o7/KXKjq00WpTo/wAt9tHSZI1fa62P6M3tEFvNgvD7fqwZkS2cZgrRZtMrSgfXQinvx9FWpTmJAziM/wDdeQp/M2J7tD3dA5faJmesjK/ndTDVwveaGqAjVqIUwDxykj1F/QX+UsCxYrVxCauCsukDpmCT6mxAWQ8JGrx0b+/wwZuVsNvtmuZXdYoxmcp96VUkBmoilyqcWoKhQTTGwOkfZ4xteVp8+xdZgujDamyEu0SOG8ST1v52hrEmKrCBq9+PQHfPpf0I/KuApL/m4jSpJgBJ8W+emYtZfd9rtpZoLu6iimjKlknzKWDqGV0NCGXWh1qCNRhE/WPuGzbhfw3G2XLzssASU5aQGhqhSQ5XZspIPdpUDXjjTNVGor4hp4gZfC1FGrinl6y06Zy8IcmY45SAfW8bS5XiatBK6IK/eySJ8YKkjxaiJnfKb2qYTD4RBRpNUqKCSpKgRPDhI9L48SeJjJu4bbbgxJbo1s8sZOSZSQ9ddCoJ7p7QWGFu1tbndkVUjjC5iOu+YVIoCqlVZmA56Ur54Nau1R9SyuiQDsSP69LDas9VyKVOrWdV8S0yIWcxqLELJ4SZi1PLuT08PhDSxCJU74rUemw1KrDIAZ7jiRbmKdFAar06SsfCXBloy8IALQOMCLfrvxQse0ddIzHcydCKE50kzu2YPNl0ZQpjOhUgsaVoRhbtfDE0d+trujiJ+8RCs8YkdkGZQIz9+FahqSkZDKUpXBqYxzqpsZbg48Mbek+VpxjdbU11jDqawpVGceKllMsD4RwAJJXOdrQ1vlbCfSKOIpStJWBfDVP1FbI+6TDBTxBnsN6WpRanTqOtNq5Wj3iKsxUEx4SPEYEkgCcr0y0pdxRSoYizxqzKjB1V6DqICK6Kx+BGImzWP7HuLAbZc5Y542F1bXcddQ+d/lHartK2VaZmyUPCoGNBSxHeUlZpDEsvSSvGPLO0HMQcMtVBUeuxRnpGm/6ie6uphTy0megJi/nvM+T/AELF1kpDVSXQ4O+lauyk9hlfS93gqyY2nqaktMalWoKlOUbcgKamciJ7Js/bbdPKdIxy4UH1nT0wTcXjjO0EkCsKZ5HyDjwrSv1YdV8dRw4/Uqoh4aj+G9/P6nLeY4uqe7p1WYiSzkg+1s7wuE5Nisaf0MPUdYzIGX9x8N/SzjMNhqYL1KdNJgRt/sgi7rfZ4IO/cdOgU1zngeXZWh5DHM1gYck00vUR+DRsrmnHUkk8PygY1mL+YKFMNDnLjGkRxgt+V5ih8t1apP0nFLTI3XMny1HK8ry/5QqAq1cUwCD4S2ogxlIWOPCb09bmYpqjU6NXEK+xpwR5xvFym3OCz7sTmSmanSjWNCSNQTxPoPrxEvLja7Eo1vPmfQuGjDcu0FjXll0HnifH/MqvIpBj2gz8T+AsvB8twGFJJw/etwcsd/qumB5RTwgEtrjaEVBn2C/Yk42sF7mstAcQaYYx9c9lzIrm7uiqsY7RHqAFIUtm7c3D1PwwA3TxV8wFSKGKMJwbKKk9uUaeYDEjywsw9PmXMhqCmnT+0QCJHbOdvgzgFVYhdtI2iyquIw2GKrUqIpJhVLCSegFinC0HKPUpo7rmGIznrZ+7uIdr+6uRbTRAVHfZ9deQoWf7O0Yz+6vJ7xsxLMfxN/fh5Yhw2Ho4OmO5Z++G5gR2573KFAvj9/iqr069Gl9FIy8TF281gC55m5W57u1yAnsRKTlRTz/E3Gp7OQGgwKyKDU1duzljss51OdTHcm/XSnSp4dBTpKERdlHC7X9npHI+UjTRq0NPL15nsxYltLNqdBThwAHacBc0LigdOa/bjePy62YYAJO3G4cTqKZbTn5XKTAkwBcNNxuZC81wzSMXUKpeQhIlUKojWQmlaFtCAa4lH5WOsry2zLDlMv3iq5AcUyuSFYjhkSp9OOM+iDuwsEcc+3ssvGPTq1lZHDQACBOf52FVZqrKAIjIATx/E20wj4MglxFVW1K+ewG3SzOzTyyK0hqtuFeSfjHLB0xmFGfIVkNNCDlUcTSuK9jfY9vk3GO1kWYyzNLdWjsWWIGLK6CPLXplQT9IHXXAP0c6gIG42g/VNnVXcmmWXYQpA97PqOl1ocvroFLwAZ1A5aY6zxs2l3AWoFqe8ZYE+7l0PW2G2uRuEMFze1uIUjSS3kIo1x1AXVJaotemdQygIwow44Gy75tFuI9tmuYNtMEcMdtC8i5Tb5Puu8CTHQGlH4AVJ54kwaVMM1SmxOnSGE/ZPETY9Ra+JRlBM/Buwt/AsNqYEMrBkOx6+l2q1UV9CCEEaYGW1ybmWSR3lkJZ20IFNE5Io4UHE9uK89nIsDLdQzJcO0cLQy5lkdASyoy8SApYU0IFRiPF4wMSiP4RvnubEbA1lOS6iPeAzK+YN2EbxfWBUAtlq2PX1FxZZoHV8sTrmopPHlry08xi3pWyMSoav5c2vbSnOnPHamIkaVEdpN07iqeE+l+ZwREG49SjsuF01aHpp1I+PeIY0r5muJzQdRSUinYgmirnGbXmONfPniME6tTQ3ZIudMHXZoWmx/wEx8L9wgSL41RV3YDpJibgJaz0FZSeWeg+j664nLC+ZRkpxGVpQBp/Vox54iJXcLHZZf8AK8Xp1GmQv3jAGd9z63F9Jp69GoF4nSN463Fo6910GtdVLAgaUqONTx0xcDIGbvxBRournidORB+OF5TVtPkYtsvKKpj3e06hHwuaetw98IkBvKDN1h5NSjmijug10NdaAjngfvN/d7dJFNEY5FKFZEcMB7VQy8DWtRp20wqFIxn9d67lfI6VWnUo1oMuHFSmfEpiCJI+Fz6jcKVO8UtmM4zsy+83FhCJSskixnvKgzMqEauIiamhpULQ01xnc/iDcr1qM8qISw+4YR01HNcp09TjO4ChUrVRRNZKUg6DVnSW4KSPdnrf0DDco5fQGmnhEY8XYd43qW29IufvY3uNZO96ftniax3UUVjUjQgd00Goytz8q4zLYxLZzyS/MT2RbrmOWaMyLLLQcQc6sDmGfKapWtK6HLYjkfMMLS716aVVGZNB9ZA66CAfZN7Hu1Cd2qlYP+WTGXUZnLyucVet1AjbPsvWRa7fcSK0QoyGueLTIzad5D3ST5qcLWxb0dxurlLiS2jVTAIsvckZumOoFoKN3qUHtV4CmMFRxzofA7ZiDxynYznHZb7nXy9SqUjXoLoqKZcLsw45cG6RvdamHw9bSTTWVMgjIg9RHG/EEbeyzcmyy2plMYilEhYmSOOKCdGP0kopiPoyge/Fh3LL911HPAHmwNeJP7sApzZl3ULAiVXUvqPe9Qbz3e19MSR9di1uVir9t3znSzlZ8ohfQiyw9rO4bffSkS/NuHiYIkN6emZFGoyZS0LL5Er6YLzXKswz52VuIdTxrxpwxqlxFKsj00qd4GUuxQtqXqfFDT5TeNdaszrJPE6s7XgdwVepRWgwIQAqulo2zWRHnbDUG3HtFrMNjchiMkMQkajISrx/2VDOK8iD6HDEZQK9GMMaEDJp5jy9dKaY1bYnBssPiR+ms6zrWpl0IADn9mPS8i08Sfj7bCasyGVoO2po0qAy5+ZlR2zZuXCwsGw9Nc5kuAUYlRApj1NBXN7euo5fDE6S+uUaWqMoCihZaVI45SutfqxoqvOcMXXSjYimwIqB/BEe6BOoZ8crzgpqdMNMk7Haw1pYhkbJaJBGjPWTO5aI24ZmzNZE3ayO8YFI2k4ZrkAy5edJcpbkKcQDj15lYK6kqQqk61qQOSkHT7cOv5/XptC0aNGmPdgGrHbDkC0GuqpjccJEx62I2BNRYerUafe0nu57JXP42bIOd+XFnFeRoL3vtEiqAznuCn0G7pNPPHiQPdN1Y3jkU1ZkyrWh501K+6mmGOI5xi+9dlxdUq7SQFAB/wAA8IsEs41fp5xJIGQ9OlwU8Hh0VQKSSqwCc2H+I+L43NAPG4Y2Hb0yutt1aV/zScp11OWvLmcWSQ3VgtY3ZqldGIXTXSvPU9uCavNq1QEBmA4nTHGx5pVRpPHfQCfQ3QUEBBge27Qy5/XfcW1WEXejhhTgaKquwoTrRjw1NMuLbOV7pwJQtBQVTTWvM8SOVacRxxL9Mqvm9cns1wR5jL67Gel3RBHAcel+FJBsg9l2Vp3vpf2b/LaJeouXTItAoHIMGKknTmMSdx2ZHgM3QkhPOZHQrlFKMVZlbh6k4LavC6tNQljnpqZEcc8zJsjD0Q9JW0kTwJkey+QP2fZdmTV2XGuzPCAbUoiVqcyoRryqmUA05ka4gW91HGzj7x0DEHNWrCpCgD2aa8+GFlWsGbSVfTHhHeao7TwufE4SoOi+UevbfsxtHbldQYsjax/MR0eZVn1Y0LMoWtaUJ58QMEbfb4XaJKShZGISRVzZeHPQ0rxwGr+KG9yMpFy4fDNUYB5g7MFkey7bjtu0ZZWIuJJo26VS60OZ2V49a0BGXMoB0HE8cOLeH2kgdBMQ7VIkUCgIFBodQfsxXu1cmJYA5DwzHaJ3txhuVimDmDO5jLy63QyP4N+1gWoJs1nuBHViYSDRszEHqfizrTN79MNO1eG5rMhpJurkAI7xJNK6EmulacBhUlSpSYKk6W+9tv8AC3H8tmoHnIQQo7OF+0BtxnfdSjr62sjbrvb57aIx3LLUrmlRsqg/mFQffwxoplRBV8selWqcA1uXsVZtIDGMgIt3qjcAdb8FIiDIuuk8JPS423RSLbxrLpKB2d0di15EY6n63VjkjkCxBHzgr3zWgTL5cTX0wNgqTU6Sq/vAdMo6WQcs54X1z6i+rEQRxuLut0LYQPKqOucVXkHA4j1xNtrK2uQ0csRmjcZszggGQfSLLTvemPFmkbQOHbZODoKzGVJUjc9b6igzuD17LgxNZkHhYKw4Dpcm1YbhCc3TAK5u6p1FND21HPFcMQsWaOC3VMqnvlmZBXUcWJp7sGYLFM+8Su0dLmo4akmaiPKZsLmOBpspWPC28icxxsavj8SzFCsxnqMaR0mM7ovNvXN9wNVFSCRrpxj1J9x+OO7u4VYiTSSRhlJiPs08jUnsOC6Vc/a4/wAZ3ylTM9AM8xvaXG8qTV+gIKiSCd8t0zn0ubHYtFpk+GrUPhPdMPDHYZJ6G1mxkS4pG7yuzEKtGza+RY0FOfaMBzMLRqrnI4gqNQwwwrAr4gFAGZyj6t7ndR53l+XOlf8ARq1K5ZmCrBnM7QWMLHHeRa6i7yGHhIMgg/EWXv8Aw7GpfOzC4+jBEpIk94AB92L7ffXeFIp8kgPGSXOG1P4l109MBrii0QPBxYna+VMMoJZZXsER7DekXlYwpIqO3fbrRpqTr8jAHsuLD86rNTShXC1ATBeoXDZn7ymcrWniEIOWIqymhBNSfOp107MORXbr2kcXQnGVu7N3TmNK9OVgrN79ezEGOw3fLNMAnsjP1vx7xMzqXtH4i3/KMaoEPqQDKGJMGx6NfDvCYepTqCD4KpKnUd9FRoLeRztGtTNWRn7hPdA1FfP/AFw5ybdZ0lBs5EaFQwTqVzU7K1qO2jHTCZ6L0SwfwngLaP8Aqxq0PJ4rteoSslUKVzHW0+HxBUuvdvSKLMat/L/fYS1v54QPvgAnANHmzaUyDsr24H3EMkkqnLkjDZgFJpmHCvkcI2p6swDnlM2yxmF7sqUWF4job0C1AMiRa7B4oVQZMn8Ln7xvM0tt04VyOQczkBm7Muq605dmK4nWAVyq0v5wrqB5V5+7CvuDDaj6C5nktBOUcN5ti1SR4bonu5b/AIWlyW8oRmljmnfLkjU1YDMal+NAdaDsw/ybus0LJJbRM3BAFotfxdlPIa4SNhqzVIRdA1STt6W17klsiY63HpbiCbJNQAZ+y0qzgisQHuVkKt3UiAowpr3yurU7a6Yv3iKSICYavU0oPZ9OzyOM7i6NcGAFUjMknLbhOQ8re4+hqRRpkE5/1uBQF96ewXV5JkXedztkEh6EahDkEkiIc7jlUEVOvHCzIkl9GUWOd3dwGYnTKOLKdNSeXDGU+i1XK+KSROlSch18r0FHCODqVY07CMrl7xRwsaCw2M20Rby13WJZI4hlDZCoORtaZTr3eBOtKHXEWzjghiokKCWMA5ghL0GhBBcgacq5SMIGwQp+IqSNXDj2dbLxlOrqJdiBMEahpn0GfnvZIrTkMr4mkDICfLO5m0bws6SQzVMillD0qKhqd6q5Dx0K8RiltwitmMZmWZmAaONBRly6lSF1GnDSvlgDG4M0yHT3TB0zntwzm5Bh3qjUKZVQYZicjOxE5XenVLCDvde8AymegswsULHNJax6EAuCi6FaVzDjlwKTcJEjz3SIO8SOixzZDxJzAEmlDoKjA1OrUUhe8aOhmyDhwzRSLSB9sDccMp+NyRPC6B8s49OlkjLMAUQRyxIwCq/er51PDT0JxTDfdWOSSN2VEAIDaj1DGmYfV54moY6thGBp1WRhnI/pYb0CrBXHiPEH8OBv1SmtQFXVXU5QwBHxuweze2+JWhiaCMWpIBQAqHoRxDEan0bNhen3KxuHZI0Wd1UEhGANSNaaEHXQY0lD5mrhh9JRqoMH3iCR1kzeeXD1KYk6lUmJINjfQ6SoVoCnRMEDSggHtAic+E2RrVvOzMO2227zMbn5ezJ1LxCgPoEHTHoyr64F2t5813VjuIgCNWAC/wBJZdeZx9BXm/KMRTHdl6dToWyntJv54weiffVp4KST655Wkw1DnlOu3f1cNVoT9wh4/Z0x8Zt2CD1u/c/DSWxK299aXY/DUo48ie9FX+vFqplkMlY5WUinBZKE5uIIryI41x9Mp4atVQOiFlOxEZ+XW8FhOe4/BgLTrVUXpJKew7Wpr81wOGqd1WrrTcbghsvMgED1thWwGFxB1VaNKow2JUavba7PtUtvRnidAfpUOU+jeyfccPDeINye2aNkCjgTJCj6ea0A+o43TBkOlgQehyN5vA/M2h4xCCv/AItJnzgzcNN6dZQ9NldTsymQbvicG704oP3DfeCho8hkBedLbyQTO0ZYxynOwX2lkpQsBpmVwBUDUMK0NcOtpZ2N0a3LQDNxMCkMD5BMg/5TjQ+6TlIOZjcGw3+Y+WVSAKNWiY3kET5Z+2+7gSYIy7IsDCYHmtEnvcZSrrOzUzqjsI0/GbQ9z2qO6i1aQUJkCLkp1OAIzKWTMfaCkBuYrh53HYdqRkMV8xYtmSNoSTUVFcwyjSvZgqpSDj7Q3gZb/G7YYpihqp1aWkcWcD+tsqdQofsnLfPbpwFiYvFpg9OtKrFsgKdNm9vD43h8GwX0j31IWke2kCSQrQsQ1dTGSCyGlQyVNaacDjWpvCN3eyi4t1lEigqLi2OVmQfQcOuSQflZWpywOquFOn3lyZbLq0CjBjAPVWEkfl5i2EoSCxybMGwMLj6WIUhNccQ9NgAfMiJ8jaD4ctJbezvLZ7WVZJ5omjWVGUTC3pI0NGAJzqDoK8PPDTv2yXMFhIJPmevGyOkjVjdWU8RlVAuh4rQjjXTA1F+6f9QimtZHw/eNkKbVY0MTwUuApPCbtXTXTIMMDuGggjoRtFz43SO4rBe9XCYiniWprmXSnIeBxKqdYHGLkpPDgj4XREM2eQhY0ZS0hA9mOOpYtxICCtezXClf7zdXsK2y/cozxiaVCweeikZGpQKDQGSlQ58sQKz4XXXr6tOChVRzm1af0sOk8XfgPsgm4qz1q60+/qd6MOr9yjIvhYx+o7b1HVRpRmzVcrP5jXovhO6wXdGpzUGKlICDSZYq4pyOCU8pP2oFiYXB4fC1Kj0ENM1mGo6iQFkkpTU5U0ZjqYLkTcfcL9b+7uLhfZkkpHQEAwxqEjNGJOqKCfXEYhhJEsYqS4UADiWBAFMC0qdSmgDt4/E9TMf5tRiz7QPeY3cAMrT0n2GzFFMKFQeFQqJ+4gCr8BfdmWOsWxeFNpO83g6qEwW5DtUaMw1RT79fdho22D9gbVWfdBtzSK0jELbKWenJ7hXzZdBQUAxwschO9xpJJ0IW9py9LlpKDJI269bkcBVGuoE9VAnjm1ot8kkN3PGoOWO4mUnkBmbKP0YPWGyJuwB/attciSYT3BhCl+q1RTqIeGppVVGYmgxYgZyeAulVnTI0yn7wP4/ncefAcTctGnTceGqr9dJBPwP4WFt4552ihiBeSSRUWg+m3BfU0xrOyeGNv2+VJlUs0asIyxrlL6M/D22GhY600FBihUGT0F8BOxOV+E5DtuzwPdEG4/hmY7A1/BCovLu6mSOCAGiCK3jCSXU7jSO36xcBvaky92uBv6x9zfYLGP5J1sZr9zC10Ec9KOKItmrGjPmpSOL8OYsKUxJSYUp6sFHnA/rcuAw6Va8vsgkKTuScrgr0zV07wsmemo/0umPxNSlhoT3naCwHuqBn7dpuR4n2GDc3am52824dJs8A6K8e8VjhA6qp92SM7FgFzHCt4L8L7f4h2u0v7ezuIryy3Dame7kZWe7W4nAus2TutECsqgSAvkpnJxE6kHWF8JzMAjbLfbjbepURhVQNMeBh91mGUfhc9FwQKbHxDISQfbxtNSouppOVAkGojfeVDnN2+DN93CdFgiU3IowMBUSJSPMz5qkEBQGFeIoKHFdnt0+zeIbcRP0Y5Jr2OShoFfMzFvckgHuwlqYd0rd1SALOckaIeeEHw/VdnbvQxz1iqiqeMbR8JtyatCphzUxA/TAMsBJSPLP67uU7kJtoNMsy8CZmfwvQLe2vb2AS2b7fZFmOaM3SmTQaBjoq8a5RXlU4XmvLlK5Wc6/jr+/ErcjrNTAq6KLHPQDJA4Zj8LcLmFnoJ9lpKuNw9QacJ4kVs30xqMdN/bcTCC0bSY9tk70b1FOImubLMuVqLcIaetK6kD1wFe9utaivmyRt9ZU4Sr8o4ysuumS6yY8cZjpJt8GI2YjyJFiYnn+BwdXua9ZabwCRpYwDtMKbmamj+8ik9qg/WLO20W+XEo6axz0U5xHIjcdAe9T3044Bw39xCSyAK3aIol09yYzWI+VcfQWWGknIEsPXrelZmbdifMm+YTnOCxzFaFdKukSwUNkCYBzA431KVOmTopopO+lVE+wWyXtnv9vbB2tkjY1He6dCxOlDXkuvDC9Lu91NTqUehqA0cZAPkCuMpT+WcbUaFp95nJ0ssx8L1alk91ivkYuWvj6GGXVVqpTBMAtIBPQZXFVpUqwAqU1cAyAygieudnrO13m4k0tVmoFJymLMi0o1OGmbAGLdrmIlo8iEihKxRio7NFxk6nyxj6RBeg6LtJIz+PS9Yzu4hmZh0JJuShzPCYklaVelUYCSAcwNp263DSw9CiZp0qaEiJVQDHTIWxtZ7pGY2utsRFz0qzoKCpplatSeeuF5t5upTSQ5xWoDRxt76FaYySfLuPquQlHWAMgCsx7b1iynukjysivj8PhlDVqqU1LRLExPTa4aiU6oh0VwDMMARPXO2OCyv7idVhtrbOSxcdWMVUc+I1py5YXl3adGDRgKRzEUK/4VxlG+WOZ011NRKfvFY8vevWEswhmJHQk3elzXBYh9FKvSqNBMKSTA9Ljp0aVNtSU0Q9VVQfaBbRfbbutvlkZbaKI6MXlQ988NRXzphWfd72X2pW9KrT4UxlqHy5jqsgIhff312vUBY2y8rmxHMKGFUPVfSsxOljnw2F0Yzvn552x2Vjc3E7Rm8sHrUohkAyjStDTl8cLqbhdCg6r+6Qj7CMIX+WsdTRSzpTA38c5nyt9F0oc4wmKqGnSfW0SBpIyG+4u4y2geVs8tjPbOySXau47wWMF0YEmi5hpqO6aj3YX0upZjRpHqO1mb9+FtDkDVF1NiqQ89UzbOLHxHM+4qd2cPiXORlE1CDZE3l3jXaxabnKlvtt9ZW8jqM11FlgztUkxshePJzUCRjQaU4YevFF1tFtFaDdbeS6LOTb0UvGjhlDGRDIqmoOndcnUYkoApTWmz964yLxA8znn53FUV2puqNpYrke2xnzOoKUXeDv8Ax2WSj00qo1VdShsx2Wm7XcXI24TC1jaCJxDHIZ1gJKxgksMpGUih0GYsxpUVOD+0TbNBK8DT2jQXIklRQtIo8iPbzSCTRYVeNukwOXv1ynXHn5jUwdZ6WGK/qqrMrUi/iA0h00lTJUZgyuVrf+7BDaH1pKkk5sp4RuYuJeUU8fSStiCw7tmUMtVU8JbUUbUGEAnIjPO3R+gmVWpT0VIYKBAVhlqnZZ6HjfmxbJYeJHk3CczXUqrQRTAJB1Sn3eS5glkkaNOOhza5jhu2pNt2W1ht7RkSONmYOZQ5q1PpMWBAyhQuiqOAxbE4yrTomiQsu5qPVj9Rp3lWAAnpERlYru1bT3hJZREkZ7zncOEwFFqi1VZmFNBTSnP6YjaGUkmPbOdnJTSiG7pVVWMkA5bRlvYjwls0ckZ3CeO4M217hJbuLsSdTNIMpMbGWQGEEo0alV6DoKs1a498U+MFK/L2kkzrJL07meykZJIpI6OqRnK9R+KoZCFK4IFRsPpbDlQW0SFC7ahuBEkznZPLOXAHv60pTYHu/dEni3ZHAWCaFPEymJRtI7whiT72g7HgBGVwc25gSow9AB6it+p7xjL3ct54m2SXfLwQdBHYR8cjd6vr1C2FbYd42WKA219vfWLiSZZNwkQTQSOVy2+dO68YUEvmpR27oGuDHLu2osZ67fVFhtUxH0p9FJzQDaAxjxAb1Bnl2dRYVOhRp0+7CDTvDeL26psumtH6LT7yqgrMNRUEnRIyQ5e3pZW4v7ucUkl05Auaf2RpiFd7xsts1uGu4v8Acfyyn3oArTM5TMFAOhrr5UwTpvsySLhGQgQB0GQ9l+OkANIzMdvsvssW+m7eSj9ODEVvDBTr1XMAynISCvaD/pjl8nVtfrtEZWJWGQ+ylK821Pww1ILNZFe1iguogNaz0nJI0+6YIFAPEa+uO3anpnxdMsr5cVfvCsUznOfDLstfTa7iQVKswPYKDDnPJC/SDSyVcVKdF8kensluBPLhriIOpbSM26DM+yxK3Kq+Kd3+mhRq1BIKgdI0ngONyN4RLEKOpyHxuHvxRVFNB3MQT73tnrYW38MTRmFrjLBHJSjkZxTzCE/WcD/1g7pdbbY2yWc00bzLNI0keZGVYAlFrTgSxrTswdp3lkSODsFPoDYtDArh6mqsRXLQASSwB65318QlPTk76tiillHmRtfu9NRPBqp6c4iPSyu/W+3bLttzJLcqka5VMzQTvC7OaJG3SUstXpQ0K14nGKR+NvEG3ySNb7lJ1LiJ7YieRpkpOMucrJmTMhoykg5TyOJxiKbj9Fg7BTrDpqpkdJBGflc9QqF2EDOFH5XFXo1asrVGhJBTQ0PPUz9V+WZnP1vvxfuMdp4gVFhISC7RmXRs8KspWNQ3s0CtUA948cFdysdnu+nJfFnvXtgjGJc8chTmsmZWRhwrlzU5DCvB0Q4rVGiS7gDYLHlfsMK9Vaj0fCuuYbr/ALokbXYQsAcBfSMx4oum48S7fLGzWyXTXl48cJkVZmeGB2qCgNErKahamlSBSgOKtl/2G6wM1pSFEYxyFmli7gEaLKuTLUZu6HJoxBXXHdBEk6AqBjmVgkD8NzcOKpV6Cl5SqxIlDTDA6vegT9QuekabIdeosSBlPhX6s9rjWQCATB3g2ybb4VkSG3uWmNjLDN1IJbaET3XTJqEuZXCpK9eLMGGmmhwU2HxRabhH1oUeFRK8TRyaLVDQlQale2hJFOw4DxWLriD9GdqTLnVqt3dKeqquplHSYskVBh3FI6aZYAmkWLUmVvuEyUP7JlTZBenEKrKQ3hjNo6Hr52PqI3zHA8Rcmy/VtbX3RePct4j6kxlm6ggANzQgSuVVHUtmJqgNKmgw02DRuyy2rABmGdanK1DWo7GB1HI4ry/G1K7QaSDKFqpLoAeG8/G7HC0nZa+EYZGGRT4TGREfZI6bXPWZ9I94Cc1ORB6xcUGDPHPzuNexXO29G2u2ijnNI0VLlsktDlQxl2WVy6gE5u9mJrhq8T7RHuUEUpQNNGsht5EVTJHKyd1oywI1FQQe6dK8MMaeI0Ie9dEZDpaIUZ7HPPxdtq+ehqPdYgDUCpR0E+KIZTAzyGryvwRWiVn23JhyG1Ltxnp/GVoMt00RLOYwe2Rjy83fljOfF+5JdS208d4kpgs0SaPK1v0bmNmMqmNgVM5OjqrBe73a8MOxOebZ7572Dha1V1UzqXw56T4g2wBO8DPUMjdGCNEqp07SBl5X1lH18Rwt/jvDPXpPCQOPTEenwBOE3YvElpbyxIlsKXHTjd2dmZcxGq6gaN5cMG6BERl0vsftHyv0iZynrxuobs9bdneQp03moJKoKmmtCdK6ZtKivMYlmxtb6KSC4VXQjVNR6EEd4EHmuuO01gyiiRntY9bENQAZd53u8m7Lvvebbvc3JMlq24yyydQq0wACZENQjBwQxHHu8zx1piVvPhaeK5LLbC3tVGWNnuGuTMdaqKUK8c1XRQOwnD6kx0iIpMeAA+q0/wDNaWmmfG5Yw2WnT+Hsu4SR92yaFFsRIESonPj2Cw0cgkZlt1rWrZQS1Mta9468ASTgns9m0KOYIJLicPLmpN0isSW5lVAFQu3UKFAq0q9Mxph79OXCp7wA1ASepMfG89jXdq6Kag0adSAqGE8TG0gbfC4EpknIzv8ACyUinTJCFmDQ0NpIFzLHwZuu5zwXT3cUdvKRJUdQ9ON+GRG0OVe7TMK8zhh8FbluG42HUkjkhiQ9JY5kQNGVJqudY4S4Aoa5KUI71agS4nnrrWqeBiyuwGYjIx7LVYogkMvdtqJl0JzOW4JIG/C7phSQraxEA7Z3Jh2LAhlqIR9lwNs9jA6cb7n8N7XsKViurme/VJJoQxcdSIButVbehiolQsxYDN3ToaYsj2rdG8SXQuJWi2+W2Ro5xOys8wZXysYyM8XT6kLwSAxqhzKKnNhnR5xiarq1TT3IYAgDYniCcyRvHS1tOsiKqEEt1jwrnsO07zcbUk90ZsQTnnkPSADtdnSs7Oy5U1iRxYxmSd4GwFlI4kmjhn6Mq9xGQFizZSBRi1BUNxrzHHEvaYfn9rt5+oIWKaW0h7yINEUtGXXVRmWmlCMB8zCLiqopNqGtiTpgSTPhHSz6nJ69eagZSxJOnbKcszYI8o7JumN5hh1qCQUARVM/eAz2vlLJETuF1NS65vZLfhrroRxGPp+rFlU8C3eKqCB/CeFcItQyZu0bWdieXVsOP1aTqOsSPaMrm08B52LRxlGsf06qN2A5+zexBS8swZD1CoPYCFr29grw8sEnuyyPE0dYxTN1aZCTx49nxwEaSVhlHmJBuvjpxpPXK5yCt21A7/G67adbpSrrqWIqMp4DiOINO3E/atrhndJoZAUBzNHSgFdO6w00HDAz4Y04iciDudultKAXE7iGEahnfVbVvfRpGfsuuHYJiXkpHlr7WgUqDVSwrpTsw0CSGOUo9BJ0wc1PbANKGnE+RGA1wVVyT9jgS38fG3QVRkYmN+vnfgB/Av0GJG02j3cdxYXHRMYSOihHRqqqmtSTy1pocOEskbSMJbfpIhAWSZVyvm0oo7x07cKauB00iSSzTJHUHhbVlYcAB236CNtr6sHiSeywG1RtuqSwvGxj9lnBysBSoKkHj9vMYPW+W1lEYjEccoL54mXVzyUHlQcSKYR4XDMlaAmpDm37PqbdBdJz2P3Y+F+mRnfTmDG46/jYi28K9Geq3HVjBOhBzn8pOGcqSG6RmCswNVodQPSnrTAlTBU6u1sQpZToV9JO4E5i+QBuLjkAjUVkDjllcZqwqimNDEBlbVQVHoQQfzCtcdmwmIlIQtUgnOqUNPJhQV5/bgZE7tVGkaRlZIw1bOFPqB+Ny5HYm4zXpZSwHlP4WOn2bapmzBQucHKVbStfo8qjswTTbfuyWK27yEN3ZAQSCCVy6gDtAOB6i03yOxsxcG5GelSf2vwuQBulwNilBylgOz8bqgmtwvQgaIEADvHLlppUVGp7accWS7YgkE73FCcpZiFUachqKV4+uBKYWNK6V88rO/l8mTUknfw3MQRmZPYLGOOCAjSAB+19dwm3M2N1BC9wChXK6mHVmJIBFG0GnM4lmw22WV5CHdiwIbMW1UaZcoNOzAgfQRnlxys/+X0pk6vbZRp6wTGfDOwP5mYgEegm+Lp5mLNbxuGCilBRCp0qMv6eGJK3bw5YwgRQPpFqkeX0z/ZpgBgWMorbDYZfC3CUlQQuVnJpUQ5G/E5/G01TFVWaYXt1SPZGfwsZavuLXErPBIYhSPvjKKAaspYimuoOLLrcNvizt81JXMAyge8ACSlR58MKlw9c/YJy/je3aUGP2fW3DVaIHvqLzlfGUlmcQVz93Lj01Ae2zVpEoSsuTMhNCJMwy8s3IEYX4vElupMcVvSuuaU+150FF+GAcPhNOkuviByzm2n0YxOr2W3r4oHVpbwxnw+N53+bLqNNaXkXPvfUPZbG00nRzIYyBXuqtQeNdaj30wtzXUVydZrivmBT3AMOGIFpiY2+Fn0kYCQqfj9Vsa2KYUu8WH7AC0+si83jqtOo5D18QD5AqOwAMLnSzM0MpVKLxLiUnhyANdPIYh54kBjVplQj/hjveeprQ4hRIZQT2RpskIx8RCE+e1k4jFmpRqlE0r7xcVTw4AGcuwWtNSgs0UauiEf8MS88czMG47TZ09ggk6sezkBQfHFMsqoWHVZmBoKVpT1J+oYutMA7zlkLkRCYOkARx3nysWtiA9PJSGLHU7bxwAgT53BWemhdTXZ2B0jSDpKxvJPwFhI76Ad1ya/mH/fA5JIJV72dilAaMtT2aLWpwQ6Mdosggi11LSu6uT1BgXUqQcsp9PrubPFJeFOhL0qamoajD1/djmC6jUaI+nI1q3uy1NOeAmTrc9Rep/pZdKvB/D+tj06TxriQDsCDPsuXH8xbDKsuZGAqBQc+zjTFQkhuCMrtVjTISanyykaYAqLnsTc7rA3gdeFtsNXYA/qBB5iwKbSw8JJJ90Zn2WegutzojKGmjy1IaTOp1oddWUjs9+Fw3ktnn6Ry5u64yjKwrUK9a6VwtdEBII0nyizDQUjae2b1mHxONYIyHvE08W1A/iLRUeYVqbECoFnIqUAnsIM26yG4iNJFt1DhCrvD1Y1B/FmAevKpOEseJty0TqEJTULlZfQh9KdowuIBHHymzHw6ATGfb/S9klSsjQ+gAgQ0EgeuRnzvPUObYliF1wAOAEH0PC3PdLWK4sGyiI0cO/SKR1A5kkVp26jC3Y7rdyyD7mwCk/eMYzFRT2tHRfSoY4XikjtDDI9n5WW1NV4v2cfrvXd+wTUrAkdDaHD4+qx2w8E+Ixpgea/1sdfFQGigzd8d08cte1sMn7Os7vO0HUjloGaPMSMp5rmA9QOeFuLw/ctoQHMT5etn96w96COsXpMNiO/XUxGRjfe1CCnUP6ZKsIOmdgeImLVQHqkctHJXU00Bwx7rskdsqSL1JGC607irXyFSeWE8EmDnbU0krfZVSNv4FvpG9r0qmjkSzTv/AAbXzHbPCUWJo5KkM2cEEfkUDT41xyqPGwViBRu8SD7PaK64TFGJIJAHTj7b9i3+htU1QxA1ZcR2TbORH43SkwqqCMh28LA7lJLaMsVtVdcx04kciaajyNRgpPeWqOUKiSgLMyGtAB28fPhhfisHSNSTTnKOMf7+248VzF2H6MGRHiEZnpfGdlyW7yJ/K1KzS8Nw0nQeUsCMx7o7aVIoDpoainAHDhDLFcApbRPQqaKRICZKZiCRQKpHAjieGB8QKQQLrCAHb+lq6lOqx11Dn1GkiB9fkbhp6iZibJBnID67HWViqMJZ51zlOmkTsCEZhrR+dRr7PPngrZbdqDLbCIkEELKzKArAjRmJqeB7eeLVcQWBSmhidTOBuB2cPbcTsY8L6h2qAfgBtdVXOSR2Dpd1TqI9b6hs4ZgtVqh4sHrUjugAEmoPMUoPXEpNqEUTK8rOlWckjvd9joKclBpTEZqMp97/AGYPXpdmbVmIUwMt9vxvoAN9CQL5tdmt7YymO3XNUawNTv8A4aMKUpz4aY+IiTQyyJzDiU8KU07CNa1xWpiHqwGdjGWf9L6oGUwT5X4KF4D0v0D+DfNxbpIhUySR5lI6Z9utfy1I7Oyta4kLcQHN3ZDyzkA14tUHkTTXFFCoZgEjjE/0uzZtJ9gi/RN+EXGtLK2hzEJLVzo0hrSg4BdDQ8vqxMjJlVhDAsmVa0IJJYnugDUkefEDHqlRngGI7Lno4YVznqmNl+qBnfgun+t9LR09bijuujm4LhQa5ozWnZ3fLSlDXE8bNuz5mjt5EDCtFUjUDg1eVfw+uBwoOQWOmdt6HJMTWkLTIU8ahFMe1ov3rcFXErSE5nsRSx9gm4rPbv7MIo4A6kdVanvPdoOHniZ+ymdz84TDQUIFAc1BrlJBqPswq1MhIDhtPsvUYf5OrES1eis5wmqofaAF+Nzx2Wkq/MVGk5VqVbLctoT4MdXwuKrRrTJM+nJjm59hofqwyWWybPND1TJM2Q6s5SPvADy/fjOUsRWU7Zdl6z/05hcIwFUvUMT70A+gg/G3RAtdheZLzCmXoyoDaTIEgxPaDYb9pz20TMjv01GYlCUAGmYkDTQd6o5DBSW5sbGUJY0mIGpCibKanTRSOGE+Fx2LlQrkSfteIfxwvUYbDcuor/7dFIOUKzH2sTZxRSIj2ZWoxVPmfeKKFUlSPEzsihTPQAE5WOuru2sbJ7u8lLQsD3S4bqrl1yrrnU8OHPswC3zwvsN6UkSF7J3cGYJeZI6alstqokKhm00oFrULiDCcwr16U1qSqBkTpie2Dfa1HWTpWBPE/hZS8vp03/SepJz94nOyqFR1VQ9SSAJIG5jreeSbda7o73Fo4s7b5yQwQJGZSWWjNnNQVUVC9uG67h2fbvk7OxRus7SZUgidqAjvTzO5znWgLt9gwHXrhak6ZBGUmIF9r4Zm0wQX6DpbLC4VqlL3oIOeQMm64TGLSLap0H7W8HyvO4w0VzGxBjMU4JHMZX1pX34Mbxtb906M9SpQA55AeDUpmzE6c8RFhnxBH132nQdV2IcHIZzcighhwKt9RsmqFrIagZdAGZkfXZEeDbjd49+ubqX9o3iW4k21MoEbxMoJyRJ3ElOV00GauVhqa4l+C90mayV4pWywuYkZgc6kAGiyc6KR+Yc8GYOpTZAKY0lR4lBkk+ZzNrqtOtQbvIKT9pchPHy8rU46jVFQtVOoMYRiAFA8hkDbjCVKGIU0iRUge62Zjhvvad4V2rc4d3SGKwWDNfWrLdxtKZooVlIkggkSXIyPG5M3VSSgjGamuNnsLhcxlMcYkf2pAih2/iYAE188MWxuFrBacioXJDJxQAZkgjwxalq1VydTEzv2+dpqeBxNF2qQaQpgFX4OSRCiN9Vv6mHoUwNCAR8PKy0CpEyl2yivE6e+mI8spm/AR51rX3aY7kPbfLHbUZAE5fG+7dfSyO++Htu32xENykc8RIkRqK1DQiorUd5SVYdhxG+dS3twXOVUBoK0UedO31wQRCeFiNQEMjQwgyCDn7DcQ2AEns/IWCrsakOolSQVdZBkQQQbKZJYmRnuT+ZvnY9sg2YR2dkoji6iuRlUAlVypUfhjX2AOBJYkk4j2l5DuWc/MPCrIOnLGAwYMSCQSR2UPMY9Tdl8OomX1sWMszdWPHsAAAu1HStQGoCI2HU9t8qohp6yBkmhQuQVN9KgbTx3m5MRh6q0gE0tq37BEyPPgbXLiKPdby/PSYS2Mk3TMYRlkgubgnO1ACWoAOJNNDyxC8QSp4Wvnn+cil6scaQ2sLffyhDm68sVWEceaiIWPeykgHTBdJadKsO8gMviXpL8W/a4C7ihSxj62UnIAQSJjrHwuDFnvcEjUyRIVHB38Az09AdzYlTFVcPS7qYzJIIBjyn43VLbtxQow9CDhYfxHPd3AiEczSSE5LayVmkY9jMqs/8AZApg4NdWKplInoMzYJF8GupnBC9TkLPMGU6518qnAp7zxFFbO8O1bbYogZ3mu4OrOFUfSknMrAnsyrrTF7iBZjBynbxD6hfLkKBVJ3jfwn6zZmITSOEQSsx4AAkn0FMItp4s3uS2u5RLI0IZYpQiUoZK5ekF7ymo9pAKaV44kZtIkwB22PWM6abimwbMAnpxuijUYEz0FkYcHS1am1RSkAwv3vbegXVhf2mUzRyxBxVOoKBh+U8DTn2Ya/CUnznhywsN6IlnNuzOZCperVC6jVZVqBpQ5gcTrURsxB8rUJiUp1WVDCBmK55R0677XCyMpg5Hoba1sJVemruJcoofLOfvHhtvaSJpNa8u2n1EUxJ3SxNhdz2zSAmJyuZRXMOIb3gg05HDq6UnDqGHG092qKVYg5RdSzIRqSPfiOsdD2ntb9GLxfZus3y5J7w7rOcW29dOPrwxy+X2/XSDJpUVH5gKfXgxFtefQj2xmVtePZi18vl+sUIyTx9wqRjnedyt9jyrNG8jGoqhAVSADlY8QSDWlOGOzdkp6/tAX643q6Psk3TvF3Ltdm11E2XpkM+gzNGOIjB+lUjQa0wEbxrtdzJFb7jtaXVi8iicGWQSKhNC8ZTJqoOalRmGmCuXHD94zVxqCIWCnMMRuO0xsLgNNVHhZp8srF5p9JNJVw7FC7aS4MFQdjPATubm70vkyiPO+r/5m4gkudytp7JNGRbxRXJkz9TpgHLXUDU1ArThivdJ9r3CHddm2BZk2+3lkMaSSvKHnCkNPAz1dYpMpVFLHRQ3PEXzDzQ1XppQoGm0QCCA0MYCgDw+vC1uOZqOJoufdOfqpz+Bvvy5yruEqPXr96pMkHURKjNiWOo+WVs8EBWw9ZR7wy9GGXxFgNu3k3b3FvP7PQXpQZQigiQE5lodFTXtrwwrrM8DLKC3V1DGtdRoa89cEUuVO9Smq1NLElqlV2Y6FC5nezFqRmOII8wR+VwVeaIlOoTTDKIWnTVVBdi2QmIsJknwngQR2EH8Deh2Xg29MxmaZLDKAc4brDI9XKGFNc6e0Q2lCKGuA0Hi3e4I52aOOXqslVyuO8qZS66sNaCq9oqKYBbEYWgXUg4xPsmDTOoZE5zkRtGd3blq1ACNYA4jPLp6WyTCYyvpYEYN/tCRUGk5xlHiB9LpT5tUpFtXdsTwMiDG/rxF17pcXFlcSCQ9K2WUI6R3S9W4Vh/MLxU7korqoqOFNMStj2Nt+e43S8DuvWyL1cxhnlWlVZ/ZUIKCNG0PAntKWuuKpgrpVFjTTj3YEe6dyNibXcxqmhT7jCzT0iDU7T9lTEKx3k2JUw9TB1CH1F2mXn35M7jYHcCz8BT+kVPpGKiprMhOwfaI3KjaBcW3E247beWu2RoUd0GZ41ileMvqOo3dJ0BcZ6ga4e47RGkUvF0zGaMikR5gBop07vKhA4YZnln02rRr0sPiC9OQSpY0ZI3IJgEdbz/KPmnHcmV8N3v6T5KatM1fozs2dRUkFhuWSczmLWfzNcDRq0a2Iw6o+Y1hRWAHAECSD/ut1zr5ZwPOSmI7v9VB4hTcUhiEAyps0EKdgrxkMjapuPhC9mazNpaLaI0MUM7l7aoKFF+YEcMxVnIDF6akHhm1xoNlftFmUQ2sOcZVV5KyKeTUkzL8ctRjS0+T8wHeEqXhiQpKqQD9nfbpdqtMY04eo3Muc8yp0Kgq1KtDCIuFqIV8VMPhxSqlY4KamkjMTeerc/5U3dBSKfgAZgHdXI+2Msj1sBW+g/SKS8u5Ry6rWTu6dKvi2OIR58NQrXNWmDPFhTkbGLHbJZ71Y2Kw7jOzgGlvRpGCxqMtBI4GatAaAaYcIBBOj28jtJU6r0wgVhxaMgmhHLh8MAhSjurSGVoZW3VhwIsfmz4vuMNzVMMlCiVVTGIaq70mMUjVDKpDDaZYiYNv1YMiMpDKyhkZTKsp4g/xBuHkVXCLicVyd8S1esHZxOHFJErKB3oosrGUbeIAMEi10FwdXOLNwsJIpRbL1i5GaOSPKFmFWzIkeZ5C8QClyAAM2vLBc2u5fjnqsAxWoGUtOmCsHLbIg9TxFzRZmMwqoGKhqZVgsaiQ2WcE5yOnS7rW8a3cEyuAOxj9mFfcY2tUzy3AALZQHLFi3YBQe/swxuQVUXfLtiwrjNJ2OWdnfG+5Q323I4nVzbrNozaqsiU0H8QHvwlvHFeow6jMpqKBNDTiCCfiDirJqT2XL3gYcI+u/FoN07vSc5m1bYVWfcVaRHnWNGcqgRqj2TVXK19qoynNUaYLPsRgZTHEaNWjKh5cQewjAzprUiYmyBoOxAu291IccCfSyG7SLArSopjUTqwVgagFMutRWhHaeWIN7abtdWvQELzHOpDNpoo9mpwHQpvhyFIlSDmOyTZNQKSDqzAjfL2XfwlcjmPxuqhvun2X3Z73cPeWeQiUwTdVIWH3bHLlbPTVVy8SAToMC4PDe8LIHKiFl4HqUIJ8xTAuLqLSQVNI8LAz9XnnwkXMyowKtpYHgRIuRcpknbgL5pfoR626LBfQbnc3sphyTM7CKB2y96hVume6DxPbrQ4Xf2Jvx0fcXAPGk0n/AE4SYz9Qh17qm4YPLtTXect5jPY20GDwY2oUv/pr+N1+kKw0gOw2kKbkip94+22Hcd43xKR7bNNZwmJWYohWrszA95gcuUAd3TjXAOLwgZDmnvGc9tC31uxwkwtWlqd6sBmaClGoUU6VEMVRsyc87fgIghUC+UD6hd1kIAP9oTv5jK6d2eLWQtZd9kmguG3yaSWNkkWOW9YIjJIDlZVd61C6jLQ5qYutfDNnFSrSv/WF+pQDhNVpJiFZEwLMGVlLrTLN4lIyeppjffVbksblWoyEHX0ykAewXGEXttg8TbzsEcBluLBblp5Cx+XS3L9RhVic1aVBK52VjiuDabZApEYVhwLAufixbCHCcr5jRo0qfjTQoEviPDI/YpyYHATb/M9btUKGoz69yclXPPzgX6AOFp/huxa+vYAn3UUTrIzSVAWNGDUDtTM1KLpqeODfiHd4NoaNXWSYEhOnBSNwxDVNXVk5ChykeWOojsQoBdzwUTJ4wBnbfl9ejhMGXRZrPU7stlqEiRE7AD43EzogLMwRRmSxAAHaTlarmOErY7H01qk/RUph9GYVyDBBjck8eAt1u96s45eq8mVydGqoVj5FiCfdXGfbhfnZlHVjklzRSTxvLIJStUOWSNwMjUIygoAKgniMDJyTEuJqaKQP/EOfsE2XzcOeW1VoVTqqFFqVCZaCwDJP2e2OF2q/MuDDFcPTr4xl37hPAP8AG0fAWXg9CYhA9JVRASlNVCqIEhoHvetyvEm8XbbjJIl0IoYtIojK0yd8AvWIAhatxBNRTQ4zi5upZsplkaRJiGI9kJyIABrpU8T3uJwnxlXl6Uxh9a4hlO9BIz668gSNtzfaWGoUFSEBJET8LP5VXxlWmK7Yd8JqE6axGqOhXfPcZC4HxFWuxDOQJ2nK3vb/ABZ+xryW5mtmaCaOLIYM2cHQmUqzUoeINQeztxfs1lt+6yyQXM1T0gi9JlWKILFUBEaMs5RMqVJFWqanA2Jw71EpinqCLmrVN9uo7bIx+Lq4chFIK6c1KgrByjqLaJigjOXXVMToB345G6YZE1inDaiJmch5C2a08dbVdQuI5JIwh+8DQShlrqajKeI5iuE7xZaWW3JC1lK1jEHEUiZ3ke5pwkSUk9N1X+YjgU4jCh8NVpEKy5ngCM7PweKbE1QKoBIHvgAaV6EfUbMTE0qoLKTlvIIixcdh0RVIfQhPiX7x7D9c2wbp+saCwlgjtTG8Sk9WSRlqqq2XoxxUzd4fSOmU4y6CF588drGZw2VJFJQFXVsyyhq04D2j2kYiwODGoVKoML7qde0/lbJKBq1V7tXYrnl7CCdoN2xPMVE018UyGYH4Dr52sJUZJJ6zG4O4i9TtvHlhcCOaVLqxtUOQ3KW0zRoxaiD7v2QFoOAqeGFS08L3JFvJ8zHHHHIJDAzF6sB3GJAUExsTpw511xXD1cTRVu+YVpY6W0BCF4AxkSOtm1cBUrU+7qV6GHUyANbOwB3kADOLixeCw2IK1KdOrRVd5JddXmdvKblSvVRhNKpUVTIUQqk8DJyN674d8bx7lHdizuIrkWTqrPPGoEkbKWWSKQkHUA91+8CKHjjP4fCu4wSTm33e2ht7m4SSRBEQ6p9NkI7pkegLHQMRgDv6ZrBKiuFedMNuehU8LMXkoU06iVlqmmPCWWoAemeYy4Xw4RzQ10Wplk06ppjJT0YRn53x8bXirTNFkWoZZUamSPSQc+N6tNuWw3YJuhJaudD00AqeH0Fof6lwsz3dtJ91cxjMlPvOqO/UaOWUUJbU60rrhc/KaGLbSlNVbfUp0/0s9UehUYE6Gj6+nZcdTFfQ0NSq5KiB7s5nsGdj4sLiKQBVmGrPcER142z2lrbQxr8leGWMMpoygGgrpmUkfEDCNCtzVjZyElde45Vj5LwLHyHHlhHW+WMZTfVTemf2WJUmO33b0wxUZNMHyI8yMwLkp/MODI/1PMLPwmbRnlpeSgUkbGSreQORMXppuFcFioEj5VJJNF1073210wo7Hvt1lf56IzqrZdD03FBrmZRqf4hjKulfDQMRQdGaBMak3++JX2m9RiaoUqFhZEyBqB9CYvWYfHYbEiadZWjdZhv7TBvNctwC10dqpZoeANWkiBnmBMz1t2McdayOs4I9leA15N2jyxXY7tsNwgGdoH/DKW09DqvxAxnqdFXhi4cHguY9Gtk1Mn3QhH7Chf8AZEXpamJ0ZAaT1P5WCtCmoj9T/G7N8STdgnRSUNouWMHK3GgPLkan1x7cbTJcLWCTqodRmCqP7ak1+AwMuGpEABF8jZNOoqt4lI7f6G+vzCqrtIaN9S7eyw8Vy+tUQinVDDfQwjP98Tdg3BlyqwjijPst1VUqO0Bia4X7ra7qBgXqg8xVf7WoxVKRAgDIcALLWqh2M/X7LlfHS3i0qG+0XUHzgm0FbAV6bTUUp2kSv9wkWXbcLQFg0sr519lCo9NcxHupgFLDl1bKmnFCSNO0GtMDrhz0A85s1GVvsn1tw/MacwajNI2XT9c3na9N6YJNRB2LZePcrZAFTO+vCZtKdihWpXzOAJCsurMMv0gQRTn9ZwN3DcQPQWeMuluf5nQyCs2/22+Ag3mZkZBsvUWbl3dmbKtqCg5I7Bvf7QPpSmF0iSMVSZm9P+5wEKAG50+Yy/C2IAO8et6NuaMxhKetRwVzq9d5vMlmEFdQP7ORsjc71cJURtcRj8LEZPQ5FU4HpPcyAjLnFfpVJ9Br8dMCJhQ33T5b2T3aKZiP3IFua/OWpyAKqHo0afLIA2rGIqusTqz/ANUMfQHpfk11eyDv6hqGrMfcasxxfDD1KyS25AVwrVViorzJz8PTHEw1LqcuEf0vrSPCtVhIncT/AOW71eZY1vsrDQQS0eW7X2iiVJqvhkYKwBOl4E9Tr28hNime4dsrVcH8JJH1ZhhwfYLUxFkV1dEzZopEdHb/AIYqRQ/A+WJhSpqMoHnFgfSnBhmVgTEOpBA65WGcRiKrQ2tp+6SRHpqF6T+UUGp6qa1EcLqBo1A6sfuiYINq0ULUr3MwP8t8ykfDTBC561ooIVYz+eWImh7VUV+OD9vL7wAN0omm5iQ3kjfXtee0KwnV4x/pOXRvQjKyMYuKw6hgrUyMpatSJjtQCfbfkF5PEpBVDpTKWLgeg0OKEnR1LuYdCKhJMrmvNRwanPF/o9MkHVn1A0+3hcmkKRAaTO4kevSx6nMMVTpsopDSMitRzUifu7H43C1apWpt3hTSCJCuFczxA2aONymu5iCBNGM1CUObu04DUcsUO+3EaNIr60OlD6gDTHlpLMlDlsevsvq9+N9EdM59tjVcVX0ECskPBan4vDEwPF07Ls6YJgdJrB84Phg5ZSIkXKiuKgLKVYa1y5RUcuFDofPAqWAqvVilLjNSq1IHZy0x56e5WQeEzcq1ATpYQY4xcdDHUxpXEUw6gkHQQpI4ZiDke24nwjKpdTrXVEgNl55ZWsRAZqq5FNa1xPSxj/G58jQYIyF1MHibncmM1FjNiKk+6o7d78SdJsqpmUo2apJLEgccWpC0WkaBdak1qTijQTt69l+JFyxVprm8rMhBkAetxBtTAtLdkQLII80qdSjkLxYjQnszAdmvbTHovrxoxE+YqMpUUoFVeFPKuIiEHhyz4f0ummlMiCZIJkZk7g9tyhK7zUhzp+3By9Rc1TF4sroJdEhWVApgKp8JBP2e2b6W6UULrARzUCrH1Y1ocTOlHcqnzIoQANAEp2eo86+uPPSEZSP46WuxfMqeGps1N6WzFSz+FiphhMyGHS46dUhpID9cpPtzt1guT18ayDELWWNKsFTSyBhKNEEOpH2gbHvLaPwd08ljQj1rpiS0NrEoZT1dKjJxA+ynrgwpHT23mMb834cIBTDM32lggR+9uCOy1qVp6+UD65vWYH5PqU6hNRl05aXBkzxlCIIPbddpaRkq5Zi2vFQF8iSWFB247frvHS3aKPNSmcitDTs8q9uuHtVwvvEDON8yTwGW/S8HjvmB6+SCoohZ8ZMldj/W02FplhKgmM9gAB1JJGQ43usLymnhxmtJjLQdAEBtx5Wd2/5OwYu8ryVpmCv00r/ANXp2kimAdvYKg6lywdgcx77KCBrop0OhpTnjTYvm+GohtTaNJjxL4jBgwLwj4h8SxZyxO/jaT8etqOW8udSr6tesSdDwnZt73wvS06SUlCqqqBsAIHstkvN8EokSGZcjgKDmU5W17uoHtUr24VybeFHzH7lTpkQHjqq5+Z5imNDW+Y1p1PAvepIOWREbgyOO953VOfE8LGXCSsEwYj1swmPK/LmwlmdjcmXINAyqUqGHBpOB19g6Y6Ej9CT5aQaad+upJzBiGzUH2HB+N5pWxR1mmOwkbKTkDFrJqAjp2dPK4aWHWmIk/wBbmnLK+odpsLdY5eiudI6Ru7g/dkgPWuh86aiuvHHEO03d8peKJp6sK5M2QjgdNFHbpiQ13YMGJzMwuWf13Nh8HicWR3dNiPvZBR5sYF8FNREAZDjdKjqgJJ9BJJ9BcqQrlCRxKyhRl6b0GSlVAylfqGmLbPw5fQRjqCcBaVoNAoJJGY6AHSvGmBy24+vtvS4T5WV4OKxVNf2KXjPqxhZ8gbmytLieb16U9zg67R9uoCi+cCTHnFjTdz24p8s6KaUOYyCraCpY+g0pWuGy0ns7Sge2ibX2sxkbjqasMg9wxme7nYjLhe9pcjwOFH6QLFR7zqCfj+QtwTHC80nPq7kCpTQBjHgZjx67fXalGl/ckSQsxXqEMGqoUDjTtGvHsw+X2/7VYgh5Iqj6KBXb4+yPjjG4blGNxkd1hapEe9p0r/c2lfZev79tlLehP+63dfmGFw4/Vrov7OqT/aJN1+ioc2RPVV/KbX7HYI7pQ13dCMkDMCrP3q8QWCp5c8UGbc9xzPZW5WLX/c3LdKNR25noDTyrhLT+U8QI750T9lCHb6wPrvRNiarAadKdeJ/IXAvO8G/usx7WRlX2kWHS5Jh0ctVd6xkkDNVAnIcWPtFsC+FdvgJYzyntJyU58+6KCpphWudytoajcdwm3KUf5VqwSAHsMp1P9Awqoco5bh86mHFdhxq1Hj+1Sq/XZvdrucz252fWXE1/cxD0QfuIhPtYMbn1HYeEWS/a8G0OY4pMoBKqEJYnKaaKtB6YVJfFEqVXb4LexX8US5pj/FPLmkr/AA0wXODpoBSpUUyB00qSj0LR+Nj3naWH5t3z+KtpDMO8r1jnB94J29i3oD7bfJPEl30VdLXpLlFZr2VLdCaakIaOfcDjL3uri5YtJIXbm7sWPvJriraiSVgCcpsihhKuIaKak9TsB5nYXWkoCKHOptIkjieJuHF4/D4JNVeoE6Ddm/dUZm2q/wB6imlaWW6MrHVktIci6AD+bP8AaEOE4yLXm/mdB8OP2YotSqFCd4wA4Ll/W3NDkqoJrNrP3UyX27n4XV8BhHqtWagjOYzfxbCNjlebxvzZUclcLS7sf8Sr4n9EHhHqTZ6TezwgtkHnKWuG9aNSMH+jAZXPu8tPswkiT1Pbmb064enTEU0VPIZ+3e9YoWmuQCqOgCj4QL+dVsfXrvOIrVKvTUx0+iiFHoLNxSbnu9UViQOKmRIkA5dwFR8FwNtxcRsHhzKw4MNMZpqbIVDqVLAlQ2WoLvE7xOdvcVQoVkIrgMoz3MrH2lZfEpHUEG/oNPEUauvu6iVNEBtDBtM7TExN4jA1cZTrK+E1o58IIEK0/ZIbwsp6EEWQudumsI5pJniywUL5SedDWpA0AINeHZgR4g3qe4hENy6FKa5FAd6HQueNAeA4E4zlaqKNOo8au7iQMpmNvbY2PqKsqpZk+zrYd4QOLlQPS96gNR0XbXME9k/lduXpWdVNXQKkeM01IphuOkEn8rm7c1g9zcXIYyrLFCY3ysAYlGi1oACSc2XN214YQJN4WF8txdPGjaCNczSMOWgzHy0HvxOmKwSmoWFZ2MaVC8I2OwGfUi1Ao166xSplz7E8uEnzuKrTxx0KndKBIZieM7jckR2W214fD51XCjtzb/dbXvm5JaXcd1EP5BV41VtCODRkgkDNrmPGhwmy7ltmfKKjQnqy56VGoFDmdq/wgYYPjlLAqNBnwpqDQOhiR52NS5TjoBqulISPDILexch7b7hKVMcvenUYPUadZ0kS0+FhIGQG1xNzbBzFJXqb+KCF9rb+yyNvebhc3t5Ntzx2sU5X5mKGMMiyCpRkWQMgc97NQjmcEvDW5WU1lIwYuRddMZUClnZVygLmbjwBJ1xNTrVaitqWJzyA0n0M+27mimDQqGZvtSeP9Lmo4DW40t7ozMnUvTaLK5biTXpNUIVIcgiZyyj1N/R3O/7cq9O7nnVdStzHExk4nKHUAg/hrjRNm2BtxQ9VITGwI9tlavIK2QrUdpFMDNRpkyUC/uki/JVNVo0iPPP6jZAoVkSO8aoerhT6cPib9iOYrRXJTOWUah65g+y1Tbdz3bcbdZo5MwZuUSK6HmjrwzLw88MvhpbXa943OzuDlaFgCjL/AC5CoYFQCRoJM1RUE0OuKVME/vUpZPPMWwwz+8hGmFHtkibgGKRDorAI/aIBBsTmSrVpUq6EvrqsAOASFOnYHfrncqw2mQtHc7o7xwpARll7ueRpARLTgpQDKABmIPDXFUN6Le3laaF72APq2WaT2eEgi1ere0dM2F+Fp1KdUMylAOLZdl8qVnV2VfGJiTt55nK58RUWupp0P1WY7JnsP47LKZ9eh0/7dgmyBQ23uyBmLF/rC8R7XtUFsuyzQvNcBm7uqW5DlDI6sB33ofuyBRlzMKHUTdeBtj8Q3tvcx79LIstzW9s5k6dyUbUxxOFi6a6ZCXjGVPZOlMNauCTEBKjELTBzP3sth+NhpzBQEWrkBAAUQq9u5B9tpaXNK2DFWhoLVfdUN9jrqHZwFy1eX1XqVXQFi0szs0luw5SLzvbo23q/ySX8Vp1SC1xcygT3RLUK2xk7hc8MzlVHAVPdwQ8W75bx2K7VB8vNBDOwUmKjxRRuQggMiBkJ4tk4gUrrgutWFFCKKE8IGXtP2R2bm6UMG1NmcsYbMeL3p4t6dbDo0O/qBq9QCcyxz9i/aPwFzY3H0aqJTpoNQgMSsadP2V9eNt1h4o2PwrE9jYrldjkmmhQSTMa0YS3bEMx7VQ5RyAxjySvLMsduz5WIUZAS5ZtMqDWh7KYGGHxeIU7UweuXwAJtkCEHiMcZPTrc74jA4VgBqqFeni+JIE+VqCGqMNILEkAKMySeEdbePGfie98S3UVjbC6GWRABIDH1nNQhpXSIKa+hridtHgOG4khub+e7EoUdS2EzVJFAuacszcAKqtKHQGmBaFAYVWaoQ1TMah9lANhxk3DX5kGYrQAP7bD/AMo/OzcRifpjIlIFKeR0nd6hOWrhC22wXy0yotTGMVnPuqZzHY7cPJfbfcPyGy7b8sJY5JLeGWaXLR2kmK1aR1TvBMwCgMQAtACMO1n4f220Xo2lqluGpXpr3nP5mNWYjlmJxRqdXGkRSZQD70RCdCTl2+dj1TUrkBnqMT2n2QMrgpVKHL1fVWV2K5pIJL8CAMx08rd4elh8CrGnSooBmTpE5cSxz+Nq/hPxZLeUJtZoJu9IVCSNF93T7xZWB7QArnQ8K41Ky2Ca3jzdcRZjmp32Zf4qEfVWmJG5e/eEU3VgIMkgEeYFy0sK+HE5KCZOkElfOM48ptMvMkNEGqjoxkaQCQfJjw87nxPO6NY6e6NWMpOkA+QIPxi0C+unv7mSdgq52rReC6AAeeg4+/Glnw3Dd1N3FDcAjSSIdOUeYegr72wfSTu0Vd4EXxBU3LBwRkR/X87Q1X7x2aIkzZdetg6o8FI0mnOdv9k5f23mSRU1pm9cOm5+C2h723ziUf8A7a4Aim05Ixojny7pPniS+ah19DkbBuTu2zIWR1U6h7Ra1ZxoWGetTz5emOhntXKSpJE6mjIyMGHqDSmLxZNHB1aqhgUCniW/ASbitfiucYbCu1MrWd1MFUpnLzZtK+ybarGy6iZDSlKq454E2niGOBOmqseB1K6fXiCLOXlznIOp7AGs6bSP8xUBm1Gqo6lkH42i+ObMrd7oGAKpcxuDQ1oY1WmbspwHLWnHBnxXavvkU5tqNLKFAUuq1cCmp4ctK4XqWWrx0kRPCd7Nq8qrzqCgxnvH126qaWSMtQMxxi1NL5kwDeE1CNRjYNn/AIST8LyGeIiJ2h79NCQNBWtKnzwatdoutlvHi3O1mjiePPJ1I2ySoCO4G7yNrQ1Rqr6YhZlG2dxPTemYdSvn+dnqjHfK70a1Kus03Vx2HbzG49bj7Dcy28lbRAHVF6kTCokzKAW1NSRwFKEYcx4RgaJbiyCGAw5o2FQ2tcyGn4R7OJ8RgcHjaSK5NFxBVv2mHFjOR2jK6NWLURTgQOPHyuPD4vF4So7IvfIZDL+yDwURmOudypTC1S8menDztCm2DNNLKJRHVzJFE6sKVaoqdTSvlTzwc3EuotnbMSrdKQsQdGFQQaDu8aA1K0OuBAMTh2FF6BbT4TVV10mOI7I9bvRrCprXLI7RH1/Xc5+j4gGrTrBdXiFNkfUJ4Htn0ulWmV0tnmPP+PKxzx5LA9eGJ5Y1AXKSY1jUd45aA5u2h88E7aa0ikjaUdVVYErWgYBtVPqOOPYhqj6IEhRGkMR65XcoTfcOlNNcmCxnUQD6XQOL52LxGscAtQ628EiquSrNG8gQHv5sxDManOKU0rpg3svh/ad4tL+e5kRTZs5s4LaFIqKDnj6kgVMxVWoxNa054HqUKK0O9qiuWeq4dkedIHuk028LAAZ7G6mjWrLVUVu7RdQiA8kjMmTkvxueniK7YkUaJo6UpqUV0jUT7wFRc1JJy3F9FSnSam5pBmMGc124CNz8LvjuhcHLIOhJGKHMQe6OBDr3XTsI4csLuy79bTTfK3UZljhlbv5QCrNVRQqSxC+1ThmAwjxVBKhPdsHiQGAg+RG4sqvhmoIGGmHHAnVEZ5wLeYeo6qO8U0yQCQTPsO1j0MStZiucqeg0zOWUm3ILFcIEYnqpwcCoH5WI0y/WOWAe5bzHtXTKSi467EQKKpwGpkBFVFaCvacV+X+eYzkFX9UTgnMvRdtLA/8AEoA56uojS3E8bGXAjG+H7qgmqd1WSNEcTxHYLE+Y+QYT5hpRTIXGosU6yrKx/wAOuRlo6H3l4DhbOpjPouZ3YkCmBkzROqeHabevCzNcmaDJnmRfu1B73HUUoa+7txlVt453yB3uIFWzmyUhkiIGWp1zO2vCtCMbvnNGjz3lifR8SqUKxVu9VdQhTIBBK6fF7w3kXnsLgK2CoPhqOIqCjWZWqgmDK7Gn90nZuov5jyV63y9zeouIwr1MTRVl7pm0mWEFlID6gVPhOxBm9lisRhcbiaWLrYWma9BWWk2ez5Fan3gN16G9f3ba2niMr28bXELmW3ScOAJQmXK2RkbKxpUAitdcY9B+sbxYbtHuNxku0Ds8kUpWSNkpQgaHLoD3gcIqzVeR48US61Vo+BmWQtSnUhtjxWZHbbbF8sw9VGVtbNEKzOWOojfxSLb4R6fO8F3uh6TVhqCMQWpVEld44xBy2sLCY+ojodFNUJlgqBTpBygiDl25WbvNm3Hf0t4R8msljHK01tC8kznM1VEj9SVMyju5WbOKUYcMdSzX9vu0247MLdIL23V5Y2TOzPMneYgmmdfokAfHXF1q1qpqIitUJOtNJXKnAzmeu3GzPljk2JxWBWq1U0u7qVaAJAPgQxABgR5ncXWolKmKbe7AKvqnOoGOQEdN+FifMvN8Pg8caPdiprpUqxgkDW4yYkScxwHA2C2bc122e4ia1oxAdUmqxidGII5ZqjTUaimBm57Ve7XOJ7lnJneQSMUy0mPfyUqT7Gp7OGOYcMyAF9RHECJ9OFk4rCHBVFTvKdRXTXTKMdRQZEuhzXxZDcHcX6swDkhYngc4sfDYoYtWbQ6MraXDDwhjmArDJssz0t4i8Ty7kY7OUQiPOWjVI0TK+WmhAqaqKEeQwlbI0j7lZha16yn3DU/ViLQEvlzCoWyvwFvkoAXzHuxZIxPtDHb9dr7cbqHSoPxri0CM8DQ45F9v1+u2MRtpkIr7seUauhrisG+36/XKSyiOozKfUfoxKsImlbKP0/ZjmfS7Rfr5dYtvwyH3j9GJG8w/s6ykuUOtUVQeAd2A17OZxQeV3mM+l9upuFJMtv8AzJ0Hqy1+Fa4QN1M0d1IqEhHo4o1V1FTQ8x54sKbtsp9lzJVLDtvhqIu7AetjPTCnssvvN1JNexNtm6W1rLLFLBObjqJG0Uq9+NnMTxlWA4HKa8DhSljaWoaprxqcVprVoyerAwYIkCJi5c2uVqi1NIBGQPxM3BkLL7ibe82u2KXKyyJHMCUZsqCVzQIGCsEzgmhANXqRrgML64nuWnupFkVnEZjRo1JVI1UDpr7C5QAGy6mtNcH4ZVxNCsrR4xIn70fnFwYKq+opOSnK7VZVkYcMj5X5ogWGaVjEE1qhIr5H/UYZ22Wz3FaWc0du8tAVmIU5hrxchangCrDMaCmAixC6fuk/G22JwtCvJT9Nj7xA1Ke08RdtI1z1H1XGqklSTMTAmDn9djNuW+jQXEbSiSMqUYMRlWhpU5qa6gBgaiulMMMfh26toZY5JJkS4ya5UA+77pykFtCNCQTTCY90ynvV1zkJ6W1HJQ+1VjHYv52bTqFfFJ1DYztY3fAbiwVrc3m63qWs7daWSQRpLNIixx9R9MzPRETMak8PLBlPD8cM1PmEJVSFVgCFZqfSQk0I5YV4dKKeAIBryns7fIW4o8o7p9YqasjCspBBsr6Q7k69TnhJ29LjBU7EemdkG2eTayQsZRVZiynLmDKaMe7oy14MKacgMSVnv7eKKPc0ZoCMkV2Ksq5dAkj6UA0ClqEcNRi9GmtKmtMDu0IADBv8w9S+4J6bm5KdWiWOHL0HbjTWojEeagyPZcFWqQZSJGbZe76dLs9FvfAYdsHPyN+wSdTXieJr9uLbW2We6ihEghZmpm7dK9wcM54ZeB4jsxZCEhYC8BGQPZ52FzWvW5XhK9fuWxVJElQvvLnEVTvoG/eCSBketiuS8vJbiZMkf0+qyaOHWvVQBhSJOfTzXtP3drMbdeZysL6clb9x/dg2sUG1wrLaWMNwQfvZJqu6gfSUUpTtygZeymGHe9wCxJ0bnc6e0dnW/nWBx9b5jxf0fHc1xGCLAChSoAJSqN90tqB1RsHJ1dZsYUfpRVQB3mynIa/2STlq6Hjtb98PTwFPXRw1Orn42fNgOoERHltfyrE4aOaKORXQxZ2TM0YJroRRqBqNQHjwwbsvE0NxamNAILlFzAMqtG6g6oCad7LrqB5Y+h4mjTxSwYDRKmRP+43jKfyfUwuNpmuTisK7mmXV3SrTYjw1GUE+HUNORO+d5k03w5FRZyPjXOGHH1HA3ozje9Q6RoaJjIqewH+l59dXsO07lFaG3mdJ4w9rP1Sbe4VR3+mYwCjodGzHzNK40Kexg8RWMmeKEXETHI0aZQGYVB0/FrU9uNHQoUlq90/eB222iRw2tBjMbV+U+a4VTUrVcBXQalqnWyQ2lmVonwZGOItY1BK0apZYleGR8raU1GKpNkq1F2gRP++1eHcI2kkRRIquC9Qxc8KsNdSAfQnAbYIHk8VR7PuSwo5bqQo7FY2CVylJSASXFQQNa6UqMaurytHUHWVYCBMR5WBzbmLFKNOm5TvW/UZSQDSKkqob/wCYYzGcZTna6nhaVFD3ZKySTJJkn43MqzrJElRIXtmCY/Zs4bqN5io7jIBVT3SARoSjd9S3HXTBHxntiy9NduakyFurHD1ZGMcY/ms75jlVjkBFAwahBIGIq2GNNiGgMPukER1BFr1ApVEVfBq1SJMREyR58bGDsMtxZBJdGJ8WmIMDedhHZfdlu95YNWC4cDsDd0jzHA+/CVbbjeWUgW5jbIGALDu/WdOHpgpgeMMB1/Pe+OagQ6YJjKbiEHs8r8hWc5F6P/8AMS6hl6cltEygDM6ijGvOnse6gwr2niPbVaYXNnb3CsSVq2YgZco9j7VI7aYKwuBoVk1uWWTlxAj43HSqhaVMGo6uFz0DKZk72k5vzurg8R9HpimYQEltzq6fZ2637G8vr4jF1qn0bD1abGFNWppMBdI93P6rcYt+2neHWrRRyfhdBBWvnXpt8cIL3tlNMywoiIxqqLWtOwZiSfStcHjCFFIQlh1VtZH+EibiTGUzHjZX2BbLPzGQtJUxdPEVA9SnSDTsUFMN/iU6TZD8ix1FiwpU2pSSUpNrIHSG8TAXo8mzSGrQlCD7IbKBTyYd01xnkG+3O3uflZ5QlfZJzJx/AwIx5tOQJOW8TM+XCzQzOB3gV/MeL+4Z3D9GcBzSVRqI06isAcYOxsVu7Qk0tafunw/2MItzkt7u2JSS3WnblTL/AG1qv14i7F4x+alWK6iC6EmWI00HbGag8eRGBZVtj9f43fFd1TSQSDPuvmP7uHqL5GIokh6YPbpUj+4SLYcsoV8ZVjLTBJdDBEdU4+hF3tHKDVJVjH5ZAF1100BoOHrhpgstp3PWO5iZj9EL05P7JK1+BxUFQM0J9LDbFug/yyB1mRYDh292qiidtYAzzygAx17b0h+XqVU+KpPkmlvr/C1N1njIOYvm0rx4+mtMNdz4TfQwz5gOCuMjceRBK/Zg4MrDbbhYCY4cVgnjuLy4R0qAFoLD3s4g9ozi9HU+XM8q2tQIVT4WGfAyRaYz3CHgpUaFV6lD5kDn54OXWy3NvUyB0pWmYVBrxIZQy+lcHeBpkkHt05XFTrrUiAG66TER2GDaVVq0oKBWUZeAvDdpA49tlYjA18IGMugAIAqAkGd4ZQVHYTa380VJBRv4eP24JvaSMaZUavMilT/FTBa0wON1DjeSCP42ta9dpIIjPbf67oy1PdhWVupgz+9Yousn0FNeRBB+rBCQEN3o0U8KlAakcyRzxOMuJui7bn22K4Gc01mZ1Akf0uWrV1GSFDAAHLeOJ7etx4/l2yh1CUFOJr/a1+vEx7bOgJWJ1A9uM0pXXvBx7sSeITGdwGslEMzsUA317AbbjhcICMRPh8uPr1ss4epX7taaLVyyNI+Ik5wVYbja6xA382CUZtSw6i5hTnoakU8sVtBAjKM+UmpoRTQdhGnDE2oe6y5cMjFqcXz1MOXAVXHd66bKwIePeXsIGY62OKdSe8p1CWzJlxqy9QTbjBfLzYgUyzMjd4VqI6aSg+yR1k5HpfsNi7cVCK4AIFSSPMnUagYki5Kmi8eXkMWxfPsJh6Wrv0ceIhyygSDsoHvX8feu9dvET2dlw4P5axder46Rw6woamoYkhtySSdJyBOV/SRAuPcW0e2IHlysG7oXiSeWUY9uTNeOVAbLGmYDLqzLrQE+mlMfRcX83UaysMM9QOrDQQuREZ6pOYm8NSGhRpIZjkc8x6XkcB8n9wy/SBTqoysKgJkzq8JQwCpj+t7GMr+sr2G4y0TKvClAQBpm56U564ixwSxMCsaqtS7VKaV5clrrovPDqtz7mNauW7zTqKnwDbQcm8x16WmWsA+ota/D8lwFOktMUgQqsIbPJ/eX90/d2tgBF33TIpR/vdAaKT9dAOA/uMRl3DKZB0u6hKkp9LNzUtwYdlMEVsVUxDN3lRmJJJLGczvcDOJyC+IdPruiUEohVRFVVAAAEAAbC7E+d3m7QVjYKoZGFAKBq60zAaGvZimKdL12jVTUjOuYUYsNKUPMa+euOMGGc6vWbpVDqFJ8srtIugMzckxIoD0qq1TKHrlC946jgezzx7tm2yRd6TMoZqkV0XU+zwNTjpaIgzJ+vst3y/5cxWPKO6/R6eR1OD3jDqtPf1MC72sxfOcPhAQp71uOkgKp6M5ynsEm+Ghju+EfUjK5h3quT2kZvdpxw1WDWNmq9K1LOoP3sjqX1NSa5cq146YTd25MiQfK9/hvl7D4TNSC3/EcSfSTl6WyIm823zLrGVIn9kOPidNrEfh7cGkOSKTosa6xyAf06DiD6A40Kz3BJ0dwtMhoxY93hWo4aeuMtgOQYnGaWdqeHT71VgCR2J7x+F6quncGJ1SJmItvi8cMNIWlWrH7tJCR6t7osbA4r6ajNpKFTBEzwneB9Vqtrs37OTO1t9IkGdWyAnXQVFfQ1xf4k8S2ghaKJuvIHGq+wtOIB5/06eeIcJ8uctoxqfvyAJdmEeiAR7ZvtKsyvKiciM9rX1+c8wEkYc0c/CGQ/FiRnbfFYJcTS0OxQalPhjVl59drIWe7FCkcixhNRUDIiCnZXhXtoMJFlYbtv7Bwxggr7chKo3kiDVz6CnngmrSw9JG7uVCARqyBz4DK4Wmp75n0yHkLV4HH4uvWppVVD3hIJQZrCznmbZ0MNSwv+UunqZlj5k5/hbbuni6ygVo4q3DkFdO7GK6ep9w9+AM9xtXhiqrFDfXnNyeoUPmcuRP4Uq3acQiozEaeB3OQuYCLnNEaSG2IIIGZzF1Od1rY7tfp1Z2FhZ0qZH07vblHeNfzUGFrdN7vNzesr90arEB041r2KOfm1T5485aqZck9gkL7PzvtwYfB4fCgCkokfbbxP7Yy9Iuezkm67JtDUsoxuE4//iboVjB7Y0oPs9+E5mNfo/399ccCxsLtfZJ3N8sruG+3u4kmaaRhyUHLGKdiDTT44CtKV+lisXaJvuV1m5DzFyS7Vp9eIYLTaV09fjjgF32vpM3Xe5KyCaUJoq95mbh3UUsacq0FB54stgls6sRXtBGhBBHe8jWmLUaHe1ESY1MBPSb9TfS6t0NxYrEfR6FWrE6EZo6wNvW+Yqn3lCosTI265jL1F+F3J0XTkBwA7P8Avxx2DQmmi8RUjh2HhUjh58cainQWkgponhH8Se24MBzKnilCsdNXYjqeov55iMZVxNZq9WodbewD7oHADpZfNeTVcDUZ0XXQOYbeB91uOV/IiGpYkU5U+04h73fGGwuHVQvThY91a8wC1CRUhakVPLBRkAbDzuHGlqWHqspJbTkTwtemlixafQce2ysABisVhqRVaaGoAQuU9pn2XVfeJbTa5GiiVZ5lAqgdaAkVALrmoe0DUcNDhE2e8tlnKTRoisCZLtrcXDxKtWDImcHvMACENSCeOBsTzClTlV8b+sC8tXFRt6sBjGkWThOWV2IZl7umftZSfLc3u8PTpU1gU5KidR/j2Xo3gXfm3neJJN06lrarbyCMRKRGZnZVXvvq2RcxIr54U9j8RX14CrLAiq2UOjRh8tAchjHfKjj1KZa93BnMucKEWm7ga2ghdOUZ58bS8xwNKnSUmW8efnHUZ+21nJ+SaKrVhqcqsqz6ok5eEbbedvcLiXZyB4cvhPbbb4qe2j3CjSIIZJV/3B9iOMy9FZJF00QAuwHHXtwr+OHMlpYXMTuBJCyyUNKSQzE0U/wuuIKhbF4qA8KTHoP6C5+WBO8IK8Tv2iy6KjD0CxWTHxP9bhxhbugQ3AHL+OtjvEu3S7O8EMlwLhpIfmlkVkb7qZzk9ioStNUOq0wNnuPmrckjM6RJ3j+FG5fHXDfD4eiimogiIGUiSP43uejBo1F4ghvTjazEVqzsEczMkbGAf42uGsSK1NuBlfXhYtjjljiEi7RcoMXyyWyb4+zTZwnUTqxSla5T1Iq5WrQ1FGYMpGoPI4EqGkdUUEkmlBzxBXoCusTBz7d7mJAzO1mYLHHCawU1q8SJggrsQfrBsVEZyFUSx2F/pja92dIlkhlyllBK1qBUVBXkQRwPZhI2zcods2ayVs7mKAIroVYFFagVl0oVrl58MIatM0WKk6SP4m3mO5aMSsowke63CDwMXolZa6ghQyn+IN57A89XCMKdam6HZl4yOImD6G3fcNxeZWaV9TlzFVVWZQRUMwGc0WoFThAuPEql2VzKo7Ag10rxrhGjTI1Mx0nSJ4/xMWRQ5cSnekll/YyORjjB3vRNTCAQoVdQnsH4cJ7LHqc2omr9HXw1CPtjLNdXCRtegRSI0Y6JlBJzBomU6eatUEfHGQ7jv89ygjs2ubUg5g8cjpprUHLoAa11PLAB8RMTPnbk0aeZZaYK+GGhmPrxtjsPERHl+Npu+rPoSia7hl16kBVQDIzHDt2t28c3097t429JhHJNRJJJLVVYRK+Y5CjZ82YJQkAe0MZSN6uLUvDcvLOHYt1mdmkzMACSWbvgUqASPXAnK8Oa9Uu0aaQ4/ePpnlvNsFRatMJnTXiieGfMRnZHNcQMPR7tfeqsNifdG/lnllYHf1cHVZiq1H4PVBYr2qScrk7r4XhsbJ5Ybv5iaOcq0bgR5oqaOqanNWhoW4eeBxv7jdJ4oZTI6PIigIGrRmANTVmNRyJpXHqdYNrLFFhyoAJkgfaPnclcrDVAqBwpjKMwMr5isGaHdBRUcvSV2JACgsJ0rG8cTcNHvXKUmqVDTLiRJIAJz8hbJ4N2iOBPnJxSaT+UD9BPxjsdvPgvrhystvmjjSZbYdF46qJiq0CkgUYDu1AGUMGFMLsdiBVc0lPhX3u09J6D67a/yPDtTGlytfSgaQWVn0gtI33mSPZej+XuXiggxVRZqP8A5YP2F+9H3m+AvK4f5x5jhKx10qdbB6qhQ6glRaYYhQre6fDEBh63Pt7ogBX1I54iq0baMRBIDTpsR7qH2TXy1xnGpxbLFcurYb/NTSODjxIf8Ww8jBv6WjA2i5R8y4Dmp00Kv6kS1GoNFUf4SfEO1dQtjsNzaCRHIEgQg0JodPPAJS8Ta19cAUcQ1FwxGqL7UpFdx621xuATFUnp6imoRIz+FzpUD7G9Tg3eG7tZZoNZI42fpH2syivDn7sZ7aXzRurIxRhwIOGS11r0/A+gnSCYkoCwBaP2QZ6WpBKGQYvE4/AYnl+vVT7yFcpHu1CFJVZ4aiAOt7epSSqpVlDA8DZ1d0uZmzPNI1dfbIp/DQ0piGAs3fhWjmpaEcG5loOw8zFz+h2Y3Y5LgaagLQRo+1Uly3azEzJ3kWp5N8wZLh8ScsglTp2N2fVf52PzPzWpULVMVWWfs0z3YTsVVEQNoM3ufnX/AMO+8NXmHK1ioZerh9hUPFk4Bz091uw2fh3m5VQjv1o/wy96noT3gfQ4CwSBgCpqDzGDq3JcPUH6Zeg3ASalP+xyf9lltqYIncdn4XmcD834/DMC5TFJxLAU6v8AegH+2rC8spamxVgVZSQQRBBG4IOYI6GzG4Wdt4jtzDOZY2A7k8L5Z4T+U/TXtRwQcQ4nZdQdcZgjGcseKmQmA6yab+3MHsbPoTejdFdSrAMpyIIkHzF/VqGI5P8AM1DwHTWAk0mha1PtHBl7VleoF/MaFapRdalNmR0MqykhlPUEZ2h7xtm5eGJf96fm7RmAju1BKnsznjG/LKxNTwONJ60d3FJDdKJUcZWRlDB1PEMD7XvwDg+ZioQG34ifqPGwcZyuphz3mH1Ooz0bun7p3YfHzvT86+Wa2Fl1OpCYDhfg6yQp+B4G2/Ivm+hi0GF5kKaMw098w/SqTwqjZD+0PDPS87srtboBomDA8/w/xUrghfbL/wC1lurnbczWbfeyxNGZ2iVR7OXV2jU1I4sK88OsXzPDYGga9d4TYQJZifsqo3P8G8Lzapi8U9IqQyoNJQwBqLe8wbLoOF4rB8kxuPxQw+HpTUiSSdKKo+2znJR8Z2v7Jyzk+BwlOuRP6hDgiWIRVyVCubDdhvc+PajdwZze2jxKKPHdNkhKnijdf7v04HsxN8L2ke/qk8MTASKGhZlrGncVi6sdA7eVSFoO3D5PmnlmJJSpSq00M5uEg9sBpnyk2h5Wg8TGl+pqNIcQgp5EajsS0kx2Xgf/AEfzvBhalHFUatVQICGoGH7MlYI/egXtMfCeFas0/fnMFtXu5bwFgCe26rCCGCArZmM2yArJEsgmjCnTqW8ys+ZVOjKxLJpXTEXdQnh3dZDGohSZZBKirVOpGy5ZTl4v3ijEDUGh4Y0QWhiF7zCVVqp0HvKfusDmD0kZ2uwlRqPMcO3dMBUZqTqsEuhVmnodDCR5m8zh8ZiaL9xzCg+GrgTJHgqLtrQiQRO8HK2POqYr8oxEVU10Atak7yAjh1Ur1AqKY8wLS/FG2C1tJvZoGQ111YNTMNew0OJ/jK7+asTkAJYAtkCgUrQFVGvIA8tQeOJGVw8k5L4dPmZm2WPwy5VaclG67+f4edyKVIgD3vFPDLK0PIuZvW1YavArU+mUjpE8Bn2i8xluSK64jTwXBY0jceumAJJ430KelvIA4XUm5+0SXJkkkVnMUn3ckSOVJUDLmArTNzU00OIMVvcgDJVT2qTWvuxE1Og/hL00qg6l7zJW46S20HYg3K1PUIKgjtAP13IKlZfEEqNSI0t3fiZeGoLvI4RvcasVMhiD2Ei2RdqtbRs0UjKwoaLG5rz71QNfLlgEu3bncHT5qSvnKcXq0KePQMzYOhTjLvMRSVl4HJSWNwihSXZKa/4VH4XylXfBNCriazzn3dCowbp7wAuTvarbvUP+Jj+Nktyt5LuW2maaCLogplc0Pt58/eYUrWhpXhiKvhi/4vH0/ORlX7TXFcNg+X4U1aZx61FZQ+ulTeoJzU0/CMyIDTxBuQAcM/IG5a+LxuKFOp9DamVJXTUZUyyOvxHKdvS4Cp45eZuTbDZ7V63Bhn9ruqHlPA0IqWXQ666duLIPCxPt3EQ8lqx/6cUrLhCo7o8wrPqQme6w1MqGBZeNTNZAPDe5dJ4L7SBclM4gMdf0GipVv+JiHDEHSYEJkYJHG4/CN29gJvqS72yVckcDZCKMubpg+qpTBK18NWsZq0jv7wn9/ji3eUR/k8uwlHpUr1K+KrDtksij0uhWp0X23UU6v+tj8TW/Yo0qOGpeUAOxu4NPq3syutd+azsPl4DKvTTLEAFdQa1UsGpmoe3loMHLfZLetVgjrT2n731sTiRq2LamE+mVEpgk93QVKK5mTmoL5n9qxnLLvI7Nrj7nBioan0Om9QgDvK7PVbwiBkxC5D9mykVWzEHt3tFlt9/3mVZrhpJiK5Oq4VFB45VGgr5DD81vTkop2aY4lKlS1EDxN7zEsztH3nYlj7b4Lqz1asT7q+6oCqi/uqoAHsuU2H8O7S23sZbkI8xBCFK5UBGvECrHt7MGUXKeLD7MX1Cb4LiCkDOLvckydo0xwdfLF79db9f2RW4fXjnOBoaep0x2/RfIv03Yq5Ne9p548Bp7PwJ0x6/X6/We2opK6FJFWRSDkOhPaAeB7cCobjoEEqVPMg/AjHRfL4b8bZ/GNuJtlZstGE8OYe8iv14gXd8+6WMkJcsekOVCWTvD14YtEx5j67lUBlI+1cZMfH6rq8qZ4Xlu+OkMkRBFTERlHCqtwHDt0x54pg6XSop4N3uXeI4nhqNdcRUa2bHhqYZjpdJBZiOJz7G4i/VaWSjjpByM73aCFUEbDLtHAmwyTi4nWKQsqHNUpSuik8/rGPLOB5SHIYNHLlYZT7LKaV5D309+JzWiMiRIkDeOy+YfKqpjjcS0ZO8GDBO3rd2925i7AAizRuvTfhLnLA0PDQaH8poe3EmKK4haNwZFhLt90D3ZWpkUOtaH2jr5cRhvQwtIp3lFakkfabPyKkiwsRiSnuOVYcRlAjrYuqoG0uyegMehiyESdxIPxvuNegtVUuY1JXuM+Y6AKAOf7hiTcyFLoRlWTMoOQ65GA1ympBBHeUgmoIwVX7mkAC2gtmygieuYHE2q1isgcRPEjj23akzb5MF2JH1X7SablTPkeHZcJN23yOMCNboRkuGiYoUUad4RNmAJ/KA2mDEdo0lBQCvHXXBi8zNNjppkKAIIPiNr5vrKHicznw2u0WJ2fxBafPwrdLG2aQIZHRgUqSM4oRQjiK8+WLPE/heOztbbdC6yhp/l7mKNhnDMpaGRuwPRlY+Q7cMOac0fEYIrTZkfUuuBDd1PjEieHTO1uskEA6f2jwHExdcPRprWHrGeWqPDPr1uTQAQTn2Dj0vWfGkezWnhq4VJbZUWNiBFHU94DIscx70isONePOuMO3OMvZWciXCkhnj+XM7vlMYUhsuXpKSGoR1C9eIAxxlRFVlNIbdyaWmdYPhKkZ+fZM35Dh6RJpUqvU1XVQCdzAAkC+q7F4If9vXOQ4yOH8RfH7xo1Om2SAnKym37k1xANCpWmQ8GyqBThoCORGBm1XsYKxy5UbgOwGtNf0/HGqwdc16Wl04bwIPUEfwIsLA49XphGgHrtlY1QBTM+nHzu5pgmTn2XqvhjfX3KNYZWy3EfE8Osn4x+YcHHvwA8MRwNd9Rm70esSnQHjU1rxA4L78Yn5y+WjytzjcKv/a1G8Sj/wC3qH/+mx90/ZOXS9H854jH0eXAUUDUHMYioM4XgjLGSP8Aab0ytpyrHjEfo1D+ooyn7a/mONhcsoUPpEsx1DOmu2fWeo4C2/c9lEVby2/iliX6FNepH+X8Sj2eI0wesJhIunEcf04X/KHzj9I7vl3MHHfe7Qrsf83pTqH/AIn3W+1sc7+c4mlocOshWMrnmpG6k9RwPEZ2ZjsBoJq0h4d2X7vaOzs4W2Q6hB3HxHW5Pg66E5bu92RKMQODr9WoOOtlt023cyV7ttdCmQE5Y7gapQcMr6qvYTTsx9S+d8IlXCUajkjuqsSACQtQRsSJhgLR4Dn3885PXweKbXi8PS1Kx3rUkIOrtdI8XUZ9bRYViCY4j6rKxOH+j1Q6e4xgj7pP4dLB/rE8GJu3UlTPHLGFntrmPuNFLXvozU9l6dooaNyxqG4rF0sygSKVKuKjgNalTx56YbclqLj+Vph2qU3rYctSQuCNaZFAw32McdrUVfoqpTNCsELOulhwqAZBozWetjVVl9Qlc5JXcevbfqLOGOoHL6uy/wA7bLv+7WNvfs08iXdqEeSO9ulaR4YnySOxBMoYZhkKqIzXXShwV8S7THt29vcB9ot4LhTFd3N6jOPlXWnSUISCzCsZXKWIA10w6K4HD0e6qEjElyNcVBD8KYmV0xORM8bmrH6VhaOIqUyGBCVQyme8TZxl8b5qqPsvhA2OnP8AaMR7YvlRSjHRGY3ngeFoXifxTfbzuM0puU+WjkaGAkCNXVDTNlRTUv7TEjmK4tvdgs7i+eTapdsnsleXpZb3vAE5hniuVh14LRA2pB4YGDaYXxMYkx06na4MXiEpIx/UUmNkb4ETcREy3hAmM/quShRdmHusBMZjfyuvw5cCS/S0unFuJZUQuzdyMv7MoYaZK0rTShrgbeJNbJDLcA9QStFnC0jKkFlCuBlYx6jQ6VGDJ1LkZI27bFwrTBQEUyupSdyQYO+072PENmIHHssjELA8UFwYMbRw9m17LZbDsUNDebgh1ZH6KlsrL7LKdAQeNfMYzH9qPT+YdVBNDzxKWc8LnlTnfAEFjeLa3nxUdqhkgubCcyRyL051bQpcrxPZlkAzDzrhPsJn3GdbJBma5KooOvf4rw15YP5bjBo7qoYK+6TxHT0+qwVK6hw87R8+5TNT6TQWQ5PeKucN96B149tvDqjrbPsVwjTOa/5f2kfowF+T3DZnLZWh5HTMh14Hs+o4aY+GRY4n8LAbVAzMDbORaD5eRkq1Z4IPi39LdoEDE6QGO+UE+d6BFOV1VqHlhPtfEJWgnUr+ZKlfeOI+vFYK+6Yv2rqPZc+R3E3W9P27xXuFrRep1EH0X7w91dR7jhPtdzhlFUdW9DihKk+JfVcvhtd4B2N30dD7fz3us3qtt4ysXQm6UwADvN7Sf2eP24y6/ugbVqNxZPtxRaepgEOpiYA2NzUEmqmXH8LrVIpozPkgBJO4j0uLG1NOHqZ8B9YvUf2psG496DvP2wkRvXzQn7VxjDXAXKQaGvEGlPQjBAw2MpZMQB+1LD2j87LpVKtOYY+RzHsNpa2J5PXOpabawd6QFNgf3SQPatw4qhh60FkWSY1DI+0XrE1skjMykEHlIqq3xTT6sZzbeLNwsqJ1xMo+hOufTybRx8cRoWUAZ/4SSP8AasoOlXNqWn9qmY/2drX4jD06rsy6SD/xEVG9tPL4X2rQNEwlbV+zUE+xhnbPu0z7cjMsZUHiaFom/KSK08jyxGsvGVpc0W4jMJ5sn3ie8aOB7jhLzPEVkkr3kQM2paqR6hoBbPqIi3Jw8/5dSew+E/lZnKsJSiG7kNqJ8NX9UdNMwMvW1wraP8yl/iXxj65FrEm4M+fNUxP/AC+8C6txBGoNOIJph2/Zmz74p6MMUrNqXtjkk96oAf7Qx87xI1MxVRDdphfLtHbwvZYzlOFqHViKaqeDe4c/2lIB+N7imCEXU3unsk+l5fCcyxGa4fW44qJcf2wSLG58i52ANebHujywt3G7Szr3KIi/E4+RUactttbFMOqeZvcIJzNjNVJGWQFnGuolbOHCuxFaFjoPymtCPswuW3UlYPxJ4YH0OdxAHlZNWFEWW1RBxsJQTnZ7rJPL/NlJqpHYCOwcADi7bbPLQ5C5rUnh7q9mB8lAy2+Nk4PBYrFVQ1PDNWQfZzCnzOVld7JysapXo0F8dQIep3s1tuyfOUKSVOhJcaAjTiNScE7O+uEUIn3fYFCU+zTFsFgWxrDQAsbsdh/HZeu5dro6VxPLhQTjUQ+Fe1hOQswvpEkXn8ViqlYH6Lj9dSMqRVZbsXLeyln4ZsYNXTqyVPfaq0r+FVoB66t54qt91lSaNOsXqwDsaUFdKJp9eIMDy+ngyHAV6g+26ho/dBBA+u3eJooKZamgURIPHztriQmIXQ86TuFZlnzKkE3nsBzGu2JSlVrNUJaGBgKOECANjxsidpsIdWhBPELV/rqdPtwvb94tiss8NsRLMKhpOKqexeTN28hgY42su9Qz2AflYclzA9ttRynBN/8AbrHaXP8A1WzVQok+y6N+vYbC4eMsEWiskSntHx4g6nCvZ2V74kuj9I1rJK9cqDtY8z2KNThmmNHdq7nU0kaREnt7POwEphdvbeZxHJ3fFvRor3dLSjBjIRZ4TuT0G96Rnnf2X7Nu15uLm3gzlZCPukzHMRzagHbz7o54ebOz2zwvZvIaLRR1JzQySH8IA7T7KL78XqFqxBaABkFGwHnub7YuCwqYJWCkszmXduJ7BsBcxk2H2zw1Z2EXzW4zRSOtHKZh0Yv4yVIcj+zyAOFrxB4kud4kIAEdup+7irw/NIeDPT3DljwAF+vpJN+AiyG/+MGnzW9lmjh9ky0Cu/ktAOmvkO9TCezaCppU8ByH+uOxfr5tfTfzuCw9o6E8ae8nyxywzBswoSe3WlMeg34ed9kXz0ussWFO3jT+/LHRopAWuWorl0NOepqK9hx2/R1vl+8rpeVVWi+nZ9mLBZNKvUQh1GrAUzL/ABLxp+YVGOxfYvhvk3HVS7Cuv2Adg1wThjtrcZriRF0rRtP7nHr6FJ2Hty+u/X4sBv8An9V0RwcgF+uuO59+2+3P3YMmlNKAYrcncNxges324/pC8AT6ZX70yDwHHjgRc+I3b+XGq+ZFTpiKbm0U+rfAXLcBq1PuqO3M2RkV24AcTpyOADb3e1qpUeWRSPgQcRIdJnMdouQ6Bw9ZN+r4cVVgR5EZHzvwNQ/a9IFk725kgi+9t+opXKVKkhhwoSujAjTtOOtn8RI00a3wES1ymZa9MA85FBJUdrDQcSMH4bmFXu6iVGV1gaS3vQdwZ39bWSJ6XneZcnRK1CpQpvTck6xTB0SsaWGkZEnoeF6ZZ9bSbrw7e7TeRzy7fffKUWRe6ih8yhumW+9UIK5TmGenFQdMa14ulistpETCVoLt8rGGUxydPJmC51qGVuYrRwNcVrFFLBvdJMZGI4Z3XFVzh1U6dYZoI1EcJ3ulAVe7pk+/pGrPjGeVz0aXfahq0kCcgDxvL9vfbvnpjZWrQ2xZXeO7aOSaBGYIIo7uN48yNIwAVos5A1OhOA90Le0vJ47SRwoGjOAGIyCqEKWC94nWpNB54gx36mHbSCSIYSOnT0uenV1KHXUoIgTBIJ/C7YbwVROxkH1uKpT0nS0MQeBIytmvZE3baL2OOMolpKkyBmzHpv8AdOa0GmYoacgOOBmw32Z0gYjJcRSWkunAzLkViePcfI3ZUYWUJpVEJI1EAmOvG56tHSxboZHlZ7nvabCMgYHkbho1Jy6iD52J26RWKxHTNmjPowK4iOr2dy6vUMrGvqDr9eGuFI70A7OI9tj0n1KrC1uKB7okbodQ9LIqpDMDdE2ZWKkUKkg+o0OJG4jNc5kqeqFcADmw1AH8VcTNkSOhi7VyC2rgwDfncKwQD1E+264ZTp0CSVYqBxOeXwudslq+ZbrIBHGSWLCuag1y10oPtwRsrOc21pbdQgmVGkQNwQEtT38OymA6zr4lYnbYdeH8dLjd4ZngFT9Yy9tuuV4er4KyIogmWcbgDOOzgOps/DYZu4oYfUy1gRqAOegnVAj7J+FlDHdXQd+nFAqiLOzNXICoLV4CutanFojMl4+3qe48vWlZWbMxbjG2tMtKE/oxFrFPZ6m2wkSfQ3DWqGJ/wjy62U1BsZ/m0MKIIlnC1NKxP2hkY7cr5VIpjuFO/wCpUgmdbHNT2RBuftnh592HVVnhgqR1hrLNw1jzika8q0JPKmHzZzboiwrQBFpTTT1HniN67e77wH2ZOgHOZA3Ny4DDjEVtLe6ok9vZ63RqdCmWNBVQsc6wVe8OwGliDpFhY6saFKV94mB+fpYe18EbI0EiTy7lE7Cizm8Z49DWnRkimRvOop5jDBddaWbpQBaJQvIw7ig8AtOJ+oY7h6eLr+JKKkDZoVB6MIM+t6BAI0rCgZeXYBfcRiKdDwnEOs5FSzVJHarErHpagIiKKtbU5fNaYMFv2nbgvxN4j4m2WbabqXMxmhzBYp1WkTcaLk1MbAcVf3EjGnb3s8d7bzQzlnElDRsopQ1BUgAgg6g4WqldAveJp65g7ftDIzbN6IKmWJ9n5WZVrUaxcipqMDSACF2jwqdo7Z87AOIDGBQpL00h9Q/xaj8bx/bJW+bgUvlUTxM1P4x/3xbceHdws5HKGJ0Vu7MH9r82XiPPzwoxAARn0yYMWybl9ZgZTw9pjLy3s+lUYkUtULOfrl/W0bc2w1J9IqBm/Z8WfntN6bBu80UYt3brW9aFGoCoH4T5dnDHHgra7rxG9wAR/tY4mZXpSR5KgIvM0ysTpwp24MpZkVFEEqCGByM/0tXialTC4WnQnRXaVDK2ehctS/tRA7LztSs1Je6qnWgYqyEQQAYyPYbfUMNSx2Nq14D4YQ3duv8AqNmVP7Myd876uozPWaLNJFWmik5fykUIwyCO5spzbwwotydQGY9AIuhd0HEE0VVWhY8wAcN2xeHQGnVekrEZo7p4h2hjmPS8COV/Sq8Tqy1l6ksQuwz3Jc7SdhN5xcJia9QV8Old0VvC9JKkpHQoMj2g39NTGfR6QgaB7oWn4RPYBkAo3gWtW+4SRHpZDINAEatfRWoWHowZfTBTxHJeW4+ZuRbyRRMFdltIre4jV6AyRPEaOsde+klRl4GuNfiuT06qd7QZKeU6T/lEdhz0/EWkpJW5dT/7eo0EjVQYjunjOAo92dtS5z1vMcm+ecZgagw+PSpiqYIUPH/cr+8DHeesN2m3GKwuE5o57+mBUAOjELq71CcpLE+Ifstw2i/oikusRyuNWjbRh5+nmCRhcttyjmkkAdurExBXQEENTOpU8DTlQ9uKV8I9MwylDwB2btVtj6W+5djaXM07irQCyNYBOoMv7LQCGWc/aL1vLOcYTmdPvMPVWqB7wGT0z0qIfEp8x5TfynmvLsb8u1kx2ExTAyE72n4GRvuussGRoyBkcCLcIJivGop8RgZBueYgSrXQd9aZh5FQAG/pofLGVIKnpb/GckeoGfDK1RASBJAqZcU++nSYJv7OyhxwM/G8DyT/AMQaK93Q5syYesQNVVAxoZ8Ku5o1PvRqQdRtbIJM2aYAlx3pVA/mKOMqj/iKNXA9tdfaGIVlcVKyRNXKdCORHI/oOL8h5yVK4au3hOSMfsnp5fVeeZHoPBBVlOxBB9Qc7D+f/klcSj8zwFOMQgmtTUf5yjiB/wAQDY/aGXS/ogq0MZSD03SqjrIZGV1IPEMpIPpZqNgwBBqCKgjmDwIxGQG3neGhCFY54h+GOcE5B5KwOXy0x9GNg8mxTYvBqz+8h0E9YAKn2G/zMpvQ/PXK6XKec1BRgU8QO+CjZW1FXA7NQkedkFOPLeOS4NEBYgVPAAAcyTQAeZODDfKrpSUs5CjqbSKb9g8NXx1QUsPTerUOyoJN9mvEGh+IPqMSY7XMQC8VK95lkjcKoBJY5WOgAwux/KaWMllinV+9GTfvjj573N/McKQxWqjEAmJzPlem+Xvm/F8lK0aurEYQH/KLeOn20XO0fdPh8rGX5U5wGpLVwdakHdV1lZVZ4mDlcW2623RzfKUiV1Y9BRlizkGrxladN2qK/ROlQKVxKSaxkoFFyoPCQ9M1Hb06DTyz1wkocsxaitS7vTUXxpJinU2BGsAwfTzspOfy+dMafM3s+Y/MXLKow2LpVlqUah7uqu1ek24ZqRhiNw0ehsWp/wCG4Sj4cawqgcUBWenA3m826W9/dypeJfpPmo8c4ETjIeNAZdG41r3tDWgGHzeNjtrpQsjZZDH9xexL31BPsmtC0YIoUPeQ1phF9NxvL8Z3lalTD01Kqss4TWPE0kJLEZAxAG16bE4LC86o6iuY2cZOh7D+B8J7L0mF5DgfmLl0fSKnc1nB/S0guKZkAmGgTnG/W8Jgebc0+SsYaDNKHNqbSaNUdSv1OsOvaMrULm12VlRJZ5ITHmOUnqNSmqvFQ8eQzKScI/iPw34j23qz3cnzQVivTtVfJQ/ypRoCxkAPDOwoc1MJm+YWNPu6hQgzsCHEmeEjfrclXk64MAKgIJ/zYJJ6hp2PZwvcf/s9wSYhcThGrpVXSM3FSk4A0iS2k7blTYOC+bn5m7M9YghSDhgVAWc1ZQD4l6Nxs9LYWpP3YhlXkyplqPzIwzKfI+6uFbw5eTwidrnqCGKBpXzVquRale9rWtAAeZxShi0xIlHJ6jYj0uKlTRMSNEAwwaMpA2JHnc+O5ZX5c+itTCzswgq3kbOxderW5aTVkgNTNOTMFtwD0izt3Pa7dGGkyLX2QAAT9XAYzvct0n3G4eRydToo4KOSj0+vBgBbyvpP9LSFgvDO6W03PiRi2WOWOg5Krf4iQfqGFuDaL6ZcwVV8nkVD8Dw99MdAUfZ9sfVcZdBu6j1vzMx+0I7Afru4pVGEhGPp+Zthi3fO3fA/iUn6xhdeK6snAmRkzagmhVvNWBKt50JpzxPq6flcYPHcdQZ+NwR19u4uQiDGx6ERbvEwlAZTmHx+GAey7p8vIubvRkjMv7x54sXjfO+Hxjt4G+BZ2vw8B7ONtsEDScK/3/vww67Js0dxFFdjIbeQKTJyAY0EvoG7snYO8fZOKtU9RY5Bki7in6G5xEA2BtLGWM6ZqGgI1ymvaP3jUY0N4ts29qEBjwPDuuO3yb/EPPEhq9TI7eFwwLotONsj2cbkzvP7/bJLUK9G6bGgJ4q3Eo3LzU/SHnXDLum82ssL2rqhiOgoO8FHDX8SH2fLTEwg7XRCQ11k7He+sBFpOQjn7sWyDKSNCBzHPz9+JgL7dDdZuHPcLCKvm9wriySSNR3mAHni6qX2i+AE7C6s+ne+kjjYx91/DHX+I/oxdJcWI4qrekeJhh+p9l1CVe0etwnEdBdi9LsPpcQ7pLTTKPRa/accTz2p9iEe8UH1HEncL2m+qlTi1xmu3ZfGenwW+TuNweMrjyGmIkhDHRQvpX9+O90n3RciggbzfO+f7xHpcbEHhHlcuLfbi2YNmdgORbAuZaKcU0heCj0uzDK7ay3FjdV3tghuLXdlkZwgLChiZgVbnqORB1DcRhSOh7PMcf8AtgdgGM3Yrc6yL5NsdrsEsFzM6yrRgpPUGZHiDAstB9MVOvEcRjrw/vi2ZEU8geMnKoIYuK+bYiAdGkbXKMsjtd8oul+X9p0ZHUVoC/cPEURxmB5qw4Hjhm3S0trm0WdHqAQub8jArr2UrrilVu8UDY6vhd6iCNQ4GfS7jwyey6BpkdRaLuCi3gtiMw6TKoJFCFIqB20FaCvZjve+7bMxcEmRFbThl0461/Tgem2ZMpGogaWnIHj23FTpikWVAe7M1KZJzIZjPlnt2XIwyAhpABOpY3HDsuRqhqBSxGsQjgDLwrl/Xtvj54pXvH+9P0YBm4IwSdNxb3AC1yWc+dinV4blpehJkz9MjPRWBqmaq5hTSowBX5i7zpCvAd5q0C14V549WICsVAJgmLvSpitUWnqRWadIdgJjpO/kM79TBLCTF8JIUtBIG5A2/KylvPtwsbqGDbbm8FsWua3M5VUcAKziOBCSAneOZ1WgqcS9rtrm4t0ge7mhlgLMjxEq0sbDvwu4ILD6a1rTvL9LEad44MaFEA8Xy8shZn0FMNi6CVl0U6p0EgQrN9nyn3W9L83dqc9RMkcF/M3ZdVamxDSy5jiY4/mLWYI7m8ZriO3ColcxRcsYHmcMN3stwFbK7SKdcqtkr6rwPxx7CYaszCpBZF3Ywo22GwPpb56CkBfsrkFGQA6ZXH3ihgNj0zPt3uLu3SdMZ8ePxu3YbmSa7jteqemWDGRdCgQAmnPyHPniDYwybdKZSkq1FNQQQK1qDz9+E/MeZnA8trO9FXlSi0qkMCXyAbeV4kXfnPJ3x1ALScAgzofZsoA1Db1sqnh+/wAQgVozksuWQ4jt7biwmL+j1JqKYiJG49ON7DZ3wtpUV5FGbh3tGr9vrjJ9+3e6ktYUgmkAlmYt09HyxBaIW0ZQS1SK64+XfRK2JSqyUnakudRlXw0+jdBHTpe2w/LHpuuG7oxSoI7K3uGtVLam+6xUAKDnHC9F3ioVDMAxyUE5t2Wpr4lWAqK3vOQCPeCLEDqJmb3SO7QHvOi5SCQ7KOBBFantGPzz+0d/nLmO4uak1JRAmnmVA+3Hzen9IwlcMmtalNsis+vmGBjtBv6YvIqK6dVCjwA1vOfQSTbxglVYyIYWgbH13mKj7/ZUDK/1Pc7/ALVBC0j3tuKoTQPnOq1oQganvx+WEsN53TqB55JKD2ZbsaeiF6sfIA4xCr4lKskyCqhpbPMDSJI8jf0BOU08OVyoUe1aZ+J0gD1Nse4qGRoaOJIge0xapq9arMs7fvP+E3o15uNlvv30MkNxGl0DLC61KOrhlEsfMMRVSCQaUOuFbwp4Z3qyvRJNZzLbyJlbOMmc5gVpnZK015igw1SvQxYqYXxCpSRTDD3o+1TOcgN4T0NqmxWBwGIpVDjsJKswcGsk6GWGyXUcsjEb3LplA2RUyJ6Hoeh43zD0qxDr3VSCuWlSfEpkfiL73bwokt5cTW087dZ2bK0cSRxK7agMsrsco0UBRyGHSWG2sgDcz2ltGTVhNcpm41OWOATV8quuDv5Q9RkLeFdQJBiYsep83cuHhod9i2G30ejUYf3OEW4F1qfQjI2b9BrDNwtMdajKvwmbzweGLx7C4s7clpY5o7hrdiQZFVXVZIjTpue8wFaHiMOFz428L7ZKslu8t7Kh0WGLKhHY0kjMxB8nUeWI+coOXLRqtPchijvvoapGgtx0GCJGx3sDHcz5lzai+H+g06NKoAGfFVJO4OVKlEZjibgo0TVDosa8mAPELMgHrZKHC4dg7VzUYbLRSf8AbeB8LzcM0ZKMrKyDKysCGVhoQwOoI5g473TejvG53V6YREbmXOIkq2QBVVVBAFaKorpxxMpBAIIIOYI2I7DceGw5w9BKZbWVGbaQoJJJyUbDPIdLCIg3arVFWozAaQTtM/HietmPCssyb3YyoAejMs1DUD7ura01w6eBPDdlErXN3NBLPOgVIcxAjQ0PtHKC54aeyMSzfLqoki5FWLfIt12TeVEV8iwSkUzOaD+mYU+D0xS/he2kFY3aE9jDMv16/Xi6VHp+6fTh7Ljuror7ie3jclwd3/V5HIDJYODXULore76De4riZDYb1tB/20vUiH+WDmQ//Sfh/RrgpayN740nqNvZYufWxTRdfdOodDv7bKy6XnN9sV9tkhqkodea5lYeq0zfaMap+2rG8XobnD8u/DM6MyA9oNBInwI88GGmSJXMdRYqOyGVJFhhwDByPQ2SyKwggG8duN1vOn03AcZhrWjadtNMaZungNNwTq2xhuo21V4nCv7mFVb3nBtBzScMfFF0XEo3viD1Fr8bS+kUWpg6dUZ+Rud8Ow90yOhvMI9yV6KSVPY37jwOCu6eDr2yYjK/8Eq5G9xPcb3EYa0sTSqcQG6HI2uhXzUhrzGIwOJo7qSoO4zF6MynvAi4onzmta4FyQz2pyMHjI+iw/T+7DjIC1SVatLZj5HMXkHDM0nO9NWwWHr5sgB+8uR/I2bida1wGjvWU0dT6jX/AFw0eYsSnjR9sae0Zj87zFKAc7a1+TusmkQ46HJvyvQfD1y8AkkRiGzABgSDoO0UOBXh+8RrdiHU9889ffiHG1KmpVmRGxzF8xLrUqeEg5CzuS0qfdOwUAltxkchd+VUno4eHBU6jkbj29s795z005k8/dibGEjo1z3jyTlj56w6C5XUIMznbELPZfB22S26Je6YYyyjmeBwV8O39J0b5QSLUBATRQfTngbuwCGObTxzHstvyvDNVfWUGkbO/ujt7blXoBlY9bGpQEQWY7Ku9sG1bbuFyAwtokTj94WWo92GZN2tpIgAyx8nViAajl6dmJsHiea6QENOmg6oq/hNl1sXQQ6DUQf4hnfanL8JUOp6eo9rN+dz0P1V1wR2HgbGX8SW9oGESwtnCyFWJDCnKvAVwteKfEMs7GCEMsC8TSnUI+lXiAOQ58cG4LGVqkjEaclMkkRlx4ZWAhStsylewzPnajmnLKVCiHw6FHLqCE1SQeHE79Lf5KOp+rysXvG7MCYIcwrUNoNRyKmpI+GBdhZi+uEQypbqT95M5oFXn5k9g5nB9bF/SAFptFIR4lJGvsOXu/XcIA7LScs5MMMwr1xNbOEMQnbuZb6rbkkXM2PZ7zfLineWFCDJKRUKDyHax5D3nD5Z7ps2zWot4ZQUj07iO7M1KlnOUVY8/wBGOhQNhdidIzvpbrdNJY2RijstkssqhLeGIVdiDU9rOfpO3DzOgxn3ivxKd1cQW3US3jIIzDKZHp7RFeC8FHvx6+Bgb5ubtBFw/EW/3G8XJqQsEdenGDQAdrU4uefZwwvGuagJr249Pndpv0Xy+jNSpqOBHpz0xWIhoo7x1J92PRfZvxN+i/ACfvGrp9WnDHdKKSefADzx7svvG+dt+viItIxI051108q+mJEK1By0B46cf0aY4QFF9N+mb4LqVQMxkPcI1NdBT9GI+73SbXDV+8SQEXkW1oSONFoW+GPTcVUk+Acd/L+t+NkYfSk1nAYJAVTsXO09ijM3JuY5vl1e0myZkZn1ytQcqkcxyHHEWzttxlgeWZoWDAf7Uuq3FDzy5cgP5GkL9oGCKTjM+Hs4n+li/RqtJdeh1Az1L4o7Ss6o8hYlSmxj3o9g+O9m0ub0cTUNFq2Hct4e7eaYbsSoRonoGOfW1me6leQiV2JPMk64s3i3EbKyg5WrRiKHMDqrdjLzGDmY/wBDcVOr3ozjUOmxHXyNrAP99k4vDfRmBXV3bTvurDdD2i6whPn5Y926QzVQ+0v1jHi8eX8bXxxGdxBZ8/rvqGcrsSHMK4LW9pm5UBNPQ0r9YqfUHHC1xloyvoW5AONwVta00xRuN7JG7wx93KSCeZIx0tc1OiCAxzvgW4alaCVGV/XE1ragg95xplU8/XhTAdkd9TiII7eRsvTNys6L58bD1XL/APcN20MdlJdZLSIloYpE6sa1r92xytJQVOT8AJAppgbJb92oqGGoPCjDAddGYKCVKjcMsj87LZARbDDVqQD6lOo+6VaCPwsAOQb8TapZpWnLrKrHVoaFNTwLd5hp+IA4FiWaJxJHJJGQ3tqSv9INdafDC537tAAnhHGZ+r8bnjTllt/E2wCa2J1eI9kXBqJzz/jpZOPa54cxgOZs4OuhBr9FvZ4jnTF9j4jY9y8gWXKVHUi+7m40qVAMb+fdDeeAziRUIDAjhIzHrd8RhUeGGR7Mts/KyRRKTBm+UcQVBB29v9bieJqvfNNkZOsEkYEey8iBnSvCoevA07MOJtIr5M8Klg/0biJo31H4G7rDsKk4kwpWCAVPkf4Nqy6YYxNNmJyLOVj/AKf9q6YkGQSCPOz9LVh9oCNgAZ/H4WgQzheg5OYxEgCtK8x3tdK1w033ha1SqtW3k/Lw/sGv7sPag7ylpkDhmJyNqVx1SkM6iueKnh6jP22qwtUYXEirpLAQ0BtOYy9nWzzg0qHJGQcCPyOVwjvkdoqyRRdSZh3nC0QEinEanJyGle3A+52a/smYxqbiMU7yDvUPampGumlcFNhXcwckXbOf6Z9btSxlF+Jpn9rIe387P/neHoqroFes4GswVA6gzDHTwHHraepg6i8A47Mz7PyvnaN5fb7nquGlBJrr3tTWuv78RBchXpLGDTjmWjeldD8cer4YVVyhT8LJDahwPbl9YuTD41qbktLgkntzNhaNJ+0vZnHsN6Bs/j2B76KF0kiSUhOo2UBWPs5iToCaCvLGeXEpdjkTImtKA8PM6/biDBUnw+oNpM7RvZLMCclC2ficTTxLJAYcDO0E72vRWA8TFj23+jbCeKztVDN3m9rTUyMfKvp5DCNsHio7js80rLSe1jyydmfKcsi/lbjl4g1HDEwIRFn+CbogLwOGoAj1z+FmVNWJrtERsJ2CLkPhcL11p0atQyHSmxkcYWF9Z42Y8S3UoKhmjaLJ1PunzBVqR3yOJqKgdlNNcZ1u+6yQpkWRiCpLivH/ALnjhvg6aJTNapuOvuqIG3U57+gsPE4hsk+yPFHl7vsvO88xr1K/0LDGEjNlPjqtJmY91RHu+pvvL8GjFqkHUx06iOub+2/N48QqIjDD3C3kCxXtqfY4ctThftbK73aUrDH1H4s5IVVr+JzQDyHHF8Zjy0hSVHQbkftH8LUVsQlHxVGifafIX7l3K4guofqzHIHog4+ZvS4PAV8V+nh6ZYKMyPdUftHh9dnfC/iW526SbpyPHI5RkYSsCSlRlpqG41piKnhiaE/euyuNfuxSlOxjqaeQwFzfDHFGk5J8GoH1gzM5bX5+ZAyFQR+3x9Bld+VKtHXTAEtBHbGURx3tpR+XWUqXrNqnLuxEHzOc+gvafBm5wXs0825zPbFQgWMnWVlZmClyKgNnqBpwIGMst4t6jYyWZlNFClyC9eH8wkdMivJtMB8rKo9Wma5YkKRGWpVGnT/h/G/McIy/qrEEnw5R+7GY9DdeY0KtJKRNAoPEPFwJMz625OGxzr3asrSAAasMzEcTMT7L1rxzvW37nDPDbIlq6xEMzFQoSgzyMaVRVUkg/SaijU4x3cDvd6pW8uECrxhUJGjNyJEVMxHItWmDsVUoJTnT4zkojMtwAsai+DTOkrsT9tizsB/jn4XmaAra4LHSNz2W4r8oxrA63pJA9xV0qx8xJ9tytgmVrm6nC6SlqKdHAaQMD9VMUbMY1UFW7xABU/RAPDmag4N5cjrjcIgP+WrazwKimQy+s2RygN9LqEjJaZg9dTDb0vN8/emeU4wsJLsndjiHNQFW9Imx/mdQvL6KyZatmOmlGyPkTbcDmo41GIsEjJTXTGmQhxI4bjpcCOR4l/jsN4GopUw05zDdf442VVpD3X+Mj1FmrOUlhU/Gtf7QIb68RIz9JcSV8JhsWIr0adXtZRP92/xuVWDiRkeI6WNhubcz5OS+AxmIws7ik5CHzpmaZ9VuKqmmVbMcD1tutH0oSa8dSST7yScDLC7z0BNCMVpYejhkFOjTWmm+ldp63JM2FjeZ43muINfG4ipiasAa6hEhRsoAAAHYALhxFE0zqFnvmXRJYCwRJjCysxomeIt91K30VfNVWPdzAVxxG+cU/ucLub4J8Zh4pnxLnHW2ByvY/wDh/wA7wnKMa4xAA7zIPlMER4SeI6cZyvGJ4/O+2DxkZwYyeAbSv8Lew3qpIx4ilNI3kiB+ijdw+sbZo/8AlxgatGrQJDqyEdRe7qUqdUQ6K3mL/S+HxWHxaBqNRKqn7pB9o3Hrf52wfOOY4Fh3GJqJG2c/Xncy2fP3efLzxVEWhIZVgLA1DdNomqOdYXQf8uMEjTlevqclwTme70Hqpi/0PWTTnw+q/jmG/wDETndJdFV1rrEEPnI/xT9dl5UK2UKt7Rmmdf4KIp+Lg/DFUl013kdlVCsapkWuUU4kV17xqTXmcDchDCixOx/O2NCguGQU12ne2v8A4kPTqYjDIsa1Uknsi8rzTmr84xJxDAqdAGiZjrHYTcGaJbgavJDIiuEnjZkkjzKQ2V17wqCQaa64vdc/kcSsispDKGU7r17R29DfQ2mxMPialGojU3NKouS1Ok8GHFTxBuJ019hi8x33wnertu6/KA3Yuei1uYAZJlXMHeO4MkxJHA9QVaujAUxoNkwijKqPpHXyzNT6sZZGwKviKi1avHxVFkwsmPCLCxTLSx2MCe737x7Ttf1s4fn5wmFp18LhyABqXDVJgt9sBoJHlI6ZW95Iatbk3K3rHxnA0NU7z3Y3v8+W+z3Ni8rXURSSGi5c8bUkb8RR2CngBmpQnG2bt4V2vcnkuHtYeo+XqMscYY05tp3gD21wQMXSrqDSbUG/ZYZf4gDYFbvCk06jqBnpU5CdyBaEYZ6THvRpK8CRke2Cb1T4XC4gxVpJr/4seIxsG4N653jV7+0VtFyRvHJ1KOy6aUqKNWmvrXGpXVvt2wLO7bWZ7VY45EnlmSSjxv8AfQvEEVQrxVyZg2UioOCqZTviXaUjwjhPH2WtDFWXQC5Zgh1tO/2hpAWZyz4XmajP3QCCGnM8YtxiOXVEViYKIpYlF2A6yS0RnIynK8xt76NI47TcayibLmzLTKTwcMBoR9GQajnUVGJvikWFvdTLaKqCUlo8jiYxqalV6lKcK1A8sNqbNqZqYXQNxO4H42LhGNYA56VOamQD+fnaY6CipVJ1HZo90nj5XJXTuiRxOxESPysHd277XdmMtmSgeOQCgkjb2WpyOhVhyZSMdXNy17tUP0ntJOn1DxZJKVHpmCt6k9uGQYEArsdv47LjSEdkOUjWB062EyFWKtuN+3y87kqEvTR9yp7snr0t88J+J57a0eyaQmLV41J7uV9JE9Dxp64E+EthhuoI7m4vhA5qUgEdWaM6Bszsqmv4RqMSVEDw3HY3CmMw4rtSqOaYyGuNQDdo3jtE+V0pvplfZ5WbU5JzJ8DSxeFpU67NLdwz927J+w5BTWeCvAPW2mbe2fTqM2Wi1bmABQ0qfLnxGB+6eHdxsVM8Q+ctgtTJAGzRgHjLA33iAc2GZBzbFtFlVcJUpKKgipTbaoh1KfUbetil7XYXmtDE1Gw7B8PiaZh8NiFNOsp4jSd/MXTPubNqSe39IwBeY1P9+IwOAL9Nnlr5bRYXXzMbBvoHj+U8MCNguK3LIfpRnTzU4sL4vC+37rZ14EavdB9cWMDxHwxIGPW63yB0u1jZrJW0UKvuxP0aoOh88SrVI3k3HcRpjsFyWFba5K+2n14LMjLw1wQMQOhsexzQJ4i57EHa5PxJ7qnH1294rH2kX8mg+rBP0gdD7b5TFOBsT22P9HPUX1zUniB2XBubYxVVgfI0oDjlyzcWJ9ST9uJQ4dfwvojhFxFCjdl8M8ZsdKlOGLmU4ju0Xe+TcZSy8OPLy9MXdPFCLvF2F1m5+275Jao9vNVoZQQ4J7eBHZQ9mB7Q5hiOY8rsRd74DfniS9inydMoa0LBa8R9I8vSmIku2STigWQ/wg4Hc5/agZCRsOgPEXIQvEi5BkOHp+PS+Q3AGwxmxObZihIbOCORBxDFy6AdjfZuuY3uiw3KaxlLR5SGpmBqOHmNRi5dsIOisR6HAtfCpiQA0iNiLJ0XNRxDUSSIM7g3DZ6DxZak5rm2bPWueIgHh2qYzXz44CjaZG9mNz/Q36MAleaU0FKlje8pCIp1x3i5HhrDx6GzSB1FnjFYVjqeiUb71Mx9Wn6rBg9DbAPFe1KpXpbgwJB1lWuldOHDXhzwDXY7lv8AKk/s0+3EL8w+YKhB77BLClYFAxnGcTvlvcvh+8LLH8vAiMScwffHCxtDfdNmW8V7XWos719a966YCvHQK4FMDE2C4b6IX+JgMD/SuflNH07DqI0+HDITERuVJueV62RPL5nusQ2c51YHwIscI3S5r+KrBq02dH72b724mYZj9KmciuKk8MzNxeMe8n7BgMrzhoDc1qqANI7ulSXLpkgsvWvQ2WK+CExgwZM+Kox/Gxu6bqL7TxlLCa2+2bbCddegsjUOnF1ri5fDAX25P7K/vJwvfAYisIrcy5hU7O/ZR7FNn6xwFlDGUl9zB4ZfNSbG7o8TdbeNN9lGVLgQD8NvEsX+HBCHYLNaVzsfNqfYBhZ/JcHM1BUrHrVqu/1m2Jc9BZX0+t9gU6f7lNR+djimvbYsb1f3B+/nlkPJndqg+RwyQbbbQUpDHTtoCfrriPD4LCUfcw1EdugH65u+onib7VxVep71ap5ao+qLsEUcBawYprx6ypLP2ZTwHqVIw4dNPo6fViY5baV7Iy9guCLHUatwzev52Ta/DsFjoWjcNTg7Vp/ZphgMTKNBmxbvG7PS63GKS9vrcuwsfBYpbaxwxeqqK/pxODDmpGLTPE36LjC6dgL7N92twVqDUeX/AHxdAEZuR9eOLIM4vy5G+Mb6cxZiy367t6CO4ZR+FyWT4GtMQDbLy7v1jFil2m6hrrFttr4slQffwBx+OIinw1GFACaDVK+qH93HEcXIY43ebpnwvRIN72zcBlZkqfoTKv1Zv3HCAm4ZtJo0fzIyP8RT6wcRRdyOlyXSet6PHbQQt1LR3tWPOByEb+KJs0bfDCht9wG/8vdm3PDpyEEfbTFLjrVu6jwM3aBtd74M+Nv0d4ZV6V50bhDpmyZf7UbVX+yfdhXbctxtRWe3W4j/AOJH2fWv2YkEgyCQbhpYqjWMK41fdO9+IBvpBFm7/wAHbVuaExKsdeQ78f8AYbvL7iMDLXfrR2BDvbv5ll/5lqMGJiXHvQ47d/bcMXA2HQ7Sp7NvZc8i1rdv1a3Vvme3USL/AOl3x70NJB7q40W13gvSoWYfiVlzf8uh+GCxVpPxKHodvbYlhmlUXgGHZZcXh8+zXdixJSRSv0o61HqPaHvGN6ktdt3buyJG7dkgCSj0bQn3E4MZDvv2ixVdk91iLEVhtt52SyBveUG8lgs9c87Z2/Dyxztt000q9RGWOveIGtPLGNqYlE/bPwuM06KMO8Y6eMb3GKZO92RiTZdJ5EAp3QOAXTDPcNs23bdHPbxieWUUUPqc3Ya8APpYhrY3E1Ro1sq/dUkC9DQweDNNTQUHUJ1HM31aSKZ0iesZ2RSEeI7cLXDfrGaNXN5nA+YxMaj2m8ufx5csZ6jyzGYjNVMdTeuooUAWAAO26i7tp4WVj3EXLJAYjJmIA01154N+FNpCqbyUanSOtQQv4gPqwlw3JcVS8S1wDxUEx5XpKaiJi66ut0c5xZnbNjtrOJS6xs/tOXVSDXhqRwHZibdXkNqheXMyqpdu6NAPU8cQ4fDhFUsPGNyTOfZZN8LXW17xduy2VsbW3Ch3HeZAoOU8SKdvDCVvG4ybjcSXBGhY5R2Dgoxwm+X0DjduFjnrw1qBU/p+GOFyk68iK05+eOjrfb4el+vwlVJqdW+oY9qrseXGg48eAx6/bXy/X0JVWpGhyilK9nGuOOdCSTWvoOz3Y9Buwv0xfDfeUBhrSh7efux6qLQMSRqPsx7e/Xy/b3ItlJ1NF9NNO3F1stezgKY9fb9frX93I/bEKv3ktYHuWHGrCgX1OahGOd4jKb3d+dhCRX/xAfhpilKO+ZjsgB9gn6zdZhmX79SmvodM/VdceXGEo0qfv1nKjzd9H/lW5ayylOrH/t8Liqv+JEqBfYWvm13y3rIt3njqe68eUxxkH2XGsjDkZARQ65aYXrhSikHn9uDEesSCzIoP2dO07S08OOVyMuc3n6n0RddOmlSoVyFXWPGRvFOIAP2c5sSg8iPLPpbXu1ot5CxUg56EHShcD7tx/F7DdtR2YieH52uLNrWStY/Z7RG3Af0H4aYX1Jo1p0hczqUcG+0B2Hcf1u/MaZASptlpPn9n8r1XLq/07DNh3cuYHcudyqjwE8dSnwmc9PlavlOJ7usVGZVta+Wzj139trVvK1vOrjip1HpyOLN4g+Uvn/P3/Kp0Yf2gcSkasuokWPh31IOq5WUJU9CDBFm8wpha2tfcrKKgPnv8bfoN2srO1eYxK56avHUAjqLRkqODCoow5iuER71mtY466Cv/AGx7uyzRZKR7111qqzYjkxp6X7cSRTSvKq5Q7FqV4ZjWnuwLlueOuJUGlQOy4y9xOdTE9tyBblyTqlcBJrk664l1AZWOWuLTOdzRZm0sb3eHZLaIsq+3IdI0r+Ju3nlAJ8sPPhjxNb7H4Wmgl2+3nAWSVLhdJeq6gkuRXNTQBTSmOVsQtOZ1HjpUFj5wLTVMVVFeotMw9RtI1ZaTsD2gATF+pUS+0DhLEAeUm2tLDKaSFx4EGoxnI3PkSbXbXwLbIC11eVzmigVRC1KlUFTI70HBRWmC3hDxrtU88y7pZLPPIMkU8UgjlghUn7uJW7j5yc8h0Z9ATpievzFlJ0BQCMmA7x/7Y8PmcroabYHUxQurQWfMvq4k8I7DcFLBBwNRYkHNZ0L/AHcfIXNrXFQFYIVmE+zHD17Rftpto26q2O1RVOjTXT9HMO1Yl6lx/adMGtzubJ7rp2Uk5g0q7oVapFSKITly8NGqcL62rGeJ6tappOS08xPQ5qg9JtyKNAlalRVVtxPhJ/eAOfrNkUwuH8KpTWdyZHsJBY+wWGgxDylIO446QWA8jw9IsHd2suY/O3zw6D7q2AtkIpwOUvO39T64hbhbMC7ZqVOinMGp20av78JKf0jEZ0cJqjLXVGqIy+0Fpj2G9SjK8BSGgdkfCzmalS/zK2njpUx+bfVaarSqUZNRWpmcgQQfjvf0vyUccccBnCotAgp0qnmUk6mb17p88CkuMjZX+OEtDl2KJLV3peIyQF1N6MNAHpNuWXp7LY1MbRAApq+QgGYHsOon1tWrdfbZQzl6EBQAAKKCOA48a6+uKkXNTX3/AN+IwD9AoySQW/eYwPQQLLNm/TKnAhfICfaZsYG/ukjNmdEJ7cgJ+yuL4kzeoxGKYpiFAUdmQu1zGoXMsSx7czcV+ZVIoBT7PhiWkHP+/riuk30mLk1jhdQJ/je6F7iSRqiqJlCvlAGcDUVI10+rBGOyZtKYsjNTMqbjJvlVUrIyMuTCDGR9t3AtJ3PYpnuY2DE27lVeTi0K8WLLwOnskaE6Y0e22hp6r082moI4qf7+44mq4gaWdhmF9sWMX3sbCYAipToo0hngE7jV18rMCkR9dgLOfbIYUhtY1gjQAZJCCS1NXaQAVZjqSQKctMQ/EeyXGx3gzrlt5VzxMdCanVeyq8MLalQVSWcST1z9h6WRWpKM1BzO3Adl7LCU0wtJaVLJV+7lPaRuWPE8bUcvxzVfBUIlFEGc3z38wN76vvFUNkFjjVFfUk0zSEf1d1RThzOEC4WV5pHlNMzGpJ5eXPhwwHSwVTESQNI6zl5f7rdUygRVTgBkPxtxiucYfBELUYMxE6IEwOPr2nyvGYmnXavUqVstTMSzHcdBxOW1vFhf7v4nl+XhYRJTKnVaRhm4qFSPu1Y6DukVOOvCt8lnCsckrxK1Mghr1pG5KHALgOK0y61ocyjAWH5ShOkuXMbDby4m2eDqd2xDEqHOekeKeA657ZW5x3zRW3pUUoSfeIBY9pOQ+u89iqetRphioy1HKOvTK13dI942u4kjv88bLUGNkVTmBpQqNR54eP1gbGJrC33iLbeksv3UrPcvNJ1woJaVu+FaVe+AZXNc2BjgqdMBe70nrPD22diKZU5IE4jxS0Hrwy87YrzvFVGZ6lfUoB8OkQT0yFqKLhhm5bhtAns4/C852/cTA9WbKSSa07uprr5YirY3Lk5YnygnUigHvwDVpOIamSpHFSQ3pcjV6S7us9Jzs0V6dZWSuqurEkh1DKZP8Z3AKTnZTHW32wvvmgdV0UNWoysOdCToewHj24TLaW827MA3cb2oye41NfccewnOvozCniZzOkVAMx++o4dq+y4aqUcVEjxDZgMx/SweafLJxCmtgzMLPcsd/wD8Tnj+y3ttpRerh5gyp3U7H+t6PHKYj9o5+8YBbbu9vdKihzX2audUPJX5ZDwVuXpjS0awqAOkHowMqw8xwvLYTE4jllXRUk0CZKrOU/bTt+8vHzv57iMOaZNN57VIh0PaDsb3nNOWUObUu8o6VxQEBiB4v2KmXorcPK263mQyxd6mZlWvYCdT7hriLtdu80rMyvlirXTTqUOVT5/uxq8Xiu5w1WqsalUwD97YTabnHMKS4UKjBjWAIIz8G8+pvBcq5UOYcywuEq6u6q1QHK5EoAWOknYkCOy9j8jcixGI5m2IqUylPBlgdXh/WPh0jtRSWb0623QXKqADGrUHGrhvWob92B0Uh0BwmHP+Yq5b6Q5z4xH9sR8LWkcb2Df+H/y01FUHLMOogQQG1jLjU1d4T2lr1APC2CO4hf8AEn8XfH9paN9RwNjbGjw3zVUECtSVu1fCfxHwF5sX8y5p/wCE2DqS2BxVWgeCVP1U+JVx/cb+lMLOIQeFG/gYH6jlb6sDUbG5o8/wFbeoaZ6Op+tZF4kG/hON/wDDrn+DJ0UaeKXg1GoAT/gqaD7Cb+4MLKrKiH2sv8QYfaMRI5WA0Y/HH0Fcbhag8Neif/iL+JvAgm/zvU5DzbDNFTl+NQ//AOvVI9qqR8b/AEA6DpZKZ4ugGjkRneqqqmrK3PMOVOI/F8cQVuJQfa+pRXyJABxssbzWjhUbSyvU+wqkGTwOROXW8gHI/wBwv45yP5QxvNK1I1aVShh5ms9RGQqoPiWHA8R2WOs8L+wGih3HtJP1mLtih6ShacMSoqSqGHvHYezEmZJLGWYkk9pvq+IXENCKqUxpRFCovRVEAey43mmYNx2SmJTRY6p032LmBuAPYaeFSSrKGVxqDwI7P0Ym3MXd4cMDVk0P2Nn/AB+Fy1xKeVsEbUO0fx7Dxsei/ivLvGfhN4Fa9sULoAzyRKmZiKe3CPI/zE5cV0xpKR9VGiNK8VqQCG8v0Y7hnFMhGMK0aWJhYnPUetxU/GjU28187B5ty/UjYigsFZNWkBJn7yDp1HS2bvoYOJjZsiRHbeAwbTuDbfcxmB0kLoenQA5Sy99lrXT46cMafu7S+H7i6vp/l5bFo4o4kkiANrcDTURqiyKw+lMSc3GuGZr0zWWorK1NUYF5yn7oJ39LUspYJSp0dVQEjfwaYmSs+8PjeNRGNFqZ8Ls6wsf7Rt9jcCqF8R3q06LQSIzDExkeCHfstct40hVYgwPTVVyg6gAU4e7EWG+u90vZrkxuIS9BIUAV6LSiZVVco0pl0AxWpqcl/vEn23NVohEUM4NQjMD7PTLhb7DBEpU6akEIiqPICLW8m7zxaUbukMK5Bhzx0k7ieIyt48O7/wBBltrgllJAilBo8bdmbjTs7D5YXUialcTcv5rXwZ0K/hbdTDIf3lOX42D3cZ73znvyzy/nIWpXog1U92qpKVVjbRUXxCOhkdluw2rLMW0eIPA1luhe7tmNtO2rCJE6cp/G0PdUP2mMoG5ivE3sNy13Yxl3+8QlGrzpSjH1GnqMaJ66Vxqp0wlTjT1eB/8A8ZPut+y2R62qosSu+d/PKnKcTy4NqrNiaA2cp+tTH/zQuVRRxdQG6i9djKfd1D4fCwkfUReX7btN3tu5ZJlXKYZXSZDnilXNkJRu1W7rqaMp0IxpV/ZqZHt9OndxyS265EHRvYRmbKygErcoCGBr3tcMqTrUgicpkHIg9COBtecV3GJRj7tYaWMnJx14ZjP23jSCN+IBngQdiD0tlisEtPWqGI8aJAjQd445Hh22pE0OunmOGOWIr2fZhrfrWX2+jr2Yrp7v79uPX6+X6+ihHDXHivy/747fr5fr8IDcRQ9nDFlA/n5cDj18v19uM0A45VP9IP1Yk5CO1h2cG/1xbVdZusXaLHmGI+1Eg/pFPsqMTGjVxpr66HFpbqfbfLrA6D2Xa4Yt0X2UT+yv1GmJHTZeBP8Afy4Y7qPU+2+TddI6C7XQyqAaAKfQDFjsCCDp9nwx4536L4L7cUxk+XpjsoRqOHlwxW+32+XX0zzFfPj9XH4VxYGHbjl9vsX66+kv+q/oxIAB1+vn8ccv1+vt0ZPf6foxI6YPn/fs/Rjl+nrfL7FxaEcsSinv+39OPX3K/X6DcTKrccSDADw08sei/TfL7FxjGUNVOJBiZeVccv03y+xfCSMvtAfHF4TkR9WORftV9m/RfIKScvq/eMWrDwK6ehxyIvhbgb9vfQL7hto30ry7cfCi6EgHtpT4j9GOmb6t+AF8N3XMHSRVVQNOI54jSyOOB+uo/wBMdXObuBfWyuhNx2Zk+OO+ore0P34rF3i+k3Wb4EgbjpiwRo3sn4foxWLtfZut2wUHA/39MeLE3LX04/DHlBuwyvxN1Odyw39x+jEbOV0P+vw4496X2++t8uYDXhQ+hofgcRllB5/H+9cVvt9vk3IIVtDT0IxznXzHmNRit+u1+utoKcNPrxZQtqNfT9H+mPX6+RffjZTZd9uLBxFN95CdDXWnx5YF1PI18jhXzLlgrqatH9OqMxHG2d2RyMjmLrbpe7ba3yCaFE7wrpp9YwO8PblRvlZeDez+jGTwfzDWwlTuMWpMGNXGyvmPlYrJ9Ipr4l96PruVkBzF8ptwuC6vZSZS8sBrpm1U+jj9+HCXbFnbpTR5kfgSOHvw7w+JpYpA9NgwPtvDYGvisHUBQsBO112uQgHewFvul+gGSWO4UcmoT8Rr9eON98J3e0D5iBneHjpXMnw1pjfWFg+YCsAtUBHPsNx34rG13S+Fr2xgWaQxKpXMwB9lQKknEa58RzXG2R2zsTLSkhbmq8Fp588IMRyatT0y4YtwE22wjtiPEx2ym+U0L59Llp1ISOPGxovY2FGLAAnLX7QMDpJkLd9gPIa8MB4LA43DHwkMo3WcrbtiEpCFzN0Bi6VKqjjnZjarb5q8jiUNICalhqcv7uyuKdp3WW0Dm2ATPxc6tQch2DElImqua6TxXpcdKrUqZ5KLuTFiPieAF6ckwiUL0xEijKO/Wir5aanGfnc5pKmSRgO0n92DNrBq4tR4BLt0FkHzsRRUfOYFl/FN/cSW/ThU1lYaKQ1EXtp2jlqNcLs+/wAFuaIeo4pqx01wW9WmnvMB5mwvoGIxMd4BTB4btZVxpoX7U2KltrhF70UuvE5T9tMfXXimd+Muh4KqCmDFr0WMCoh/xC46PJqKZ6ST1LXLdDXA43yshByinClT9mBcm8KWJEZqSTUmnlgiyBhogTd5uA4gcBZFWo2unDQ/64DHcpWpooofXENkjDr1uaxjiGPCzcZBJJJJ5AaaeeAS305Oj/AUwMbK7pRwskWL3rHjbFFVhzp2fb7sA4rmTMGLsda0zccC2ZoXaBZVhh23k222xGhNBUkYEWrHQgk1OoPIf34UwKBNlgRwss2ITPGbq8QlRukEihSJ7KSGte9nicOAP6Qcdb3adO2juvaa2lSX1Q1Vjp+U6jC6quh1Yzk9Nv7Wg2XjKetAfQ+TZfAxbOl+tQq0gAS9DE0h18dIsI9QbEwFXuqs7xDgdSmZHquoWPsbG3u0bqICUc0J46rQHzAOoB0qMcP14ZWeNzlZTlA4ZWHH3cRiHmdSpRdY1aHUj1BzjtsxaaY/BoavZMbh1yP8dtx/KWEwmMw9TWlM16FZXzgnSyeEMOKyDl1tTUq1vl7m9YYUCSWKls1ejVGpZzGQB9CLi2M4ttyRVBrJVC2bkw4U4e0MUW+VLpR3swZXANPZrwrx/wBDgDX9JwFRSCSoJBO8p4h+VnJh6dIMgBAgmD2i2nM8OMDzimyEBauliqgATUlG9pztLicdiMbWTEVHDsCqyMh4DIgcB+N3+JoMzRyc1NK+Tj9K4kb8M8BPkD8HH6cI8DUOY7Pq/obrhsqgH8bG9liKR+h0iRnTqMv+FxP1g205nTH0VyB0b2MPztSllpGB2E44uaBD/FhkjcLou95l12N3fb1uG71xU514aYkvlw326pDXHrgcv7/647fL5fQLbNupcbJOneNbc6Dtjynzr7OK/DT57YwmtaulD/6gI+uuFdddFdWy8NYexsvxuXGL75HQN7P91s8MddJlM+Kkfhn+FxYNo0z1K+2xPhqx+b3FBpkirI9QOCkU4+ep8hiZtqtZWW6ymodnjtV7e/mze+lRgyq4RCxEwJ8z0uJmFQUQNidZ8lEj4m4MLQavXSmpjU0E9FGZPssigDRXFv8AaVRSXzqtB/2RHrbGm63N/O8O3Rqyxe075AvH2meVkjUHlxduQxfYwLY28UChagZ5GYgDOaZ5HPr3QBU0AAGICmWuqfE38QPL2XenQOJZqjsVQHSoAlmP3VG22ZNsBjH1dzgqYFOnlqIme0nYT6k3BjOYryenSw1GmtSsyd5ULtpRBMa6hALGW8KKMzFybhZ406d/FGY2AAngdZYqn88ZYKR7qYlpdWr1S3uI5jlrIgDAr5OrqpI7GA9+Kr4CGpsQenXsBGR8jd6mBeipqISyj3lIAYDqYJBXtG1nMz1VNPGUEamci6z4f2mU+Jf3hlYvLvmGjj6y4asq0arj9J0Ymm7cUUsAyv8AstIYbG0/cLWS2lKONDqjDUMO0H7cH7vbmuq2q6iSrwsTTpONWRm5JTWvZ7sGUq611kbjcdDYNFm7xSmZORHUfmLU47A1MDVKNmjZowzDLwIPUcb0PMKFM4aolU6VXxI33G7OxunpYja7nMRE/uP7sXLssUBVv2vt1QfofOSEf2bYD68HsOIuQUqv3Dn2i8wh4G6FqY/1BI7DZqK1J7yqSVFaDiyjUgDtA1XzFOeCNnu+zWkcfUvS8yUq0drPTMOBGfLgVjGft/O5mwdY/Z+NlKJ/D8riXFURHi9guZabU0gVlFQwDKRqCDr8KY6h8ZbPaJlje4KiR2jpCoyoxqIhmlGi1IX8tBywMzWQcBU4lR62Qq3B9Op7AMfS2javDiSaSUQABlJ4FTofejaHyIwryeP7WTKsUV+xWtCqwjRhRl0dtDQfAYDzNl/Qxxq0h5uPzsowLG+l9KdQ/wCBrf5o9q2qNZic0luSSq/SjNBItPQZl81xnD7+9xqNt3eUns1r/ZgbAkD1svuaA3xFH+9fzsmT6WMa9XhQq/2t+VnfH89n4i2t7PLH3PvIXAGbzofMUI8xhbK7lcez4e3qX3XH/TaDA6zvZAXCKP8A3VLL1+q52Asdqlcn/wBu/tA+s2gHwZdSQvcqLi4UZQkcKBm1NAWYlVCj6R4jmMazte4eLNrsjZ2PhS56Zz964tZ5ZKScVzuiUXsFNMKv5xTSqaLaKbLOtnJAy3gQT5Wc2H5UzO5q0mZxDNoJJER908LObl71FFQFqgaNIGZz6kmwxiMZCjuyAuYHeAAZz94WheH/AAF4gkuobqZEhhhAoZGFFTnmJogNPXDlfbb413jW52G9cco3mljjH/0/mIl+rCqvzvDlD3AeoZnXGhJ/ebhZy4XkVEy1RnI21Co0eXhAHpFsKfL6isO9ZVyjSDqaPIcbDOM5gRCrTQH7pQT55kn1vi5bwtYqYd23GXdHFG6ENJAmXgsbtSGHs+7UseZOIUH6vN/diX8N2kfE5p7hD56l784TPzDm3MDJZlp7aaShVjp3j5+ZAa9B9L5QMlLGOAGnYdrLwtkmCwmF2VdW+qqST/Yvwki1MY0mZTPqS31A2lb94ptrl5E2yxjsYgGVfaeQoPxSvxbty0Hlg9d2cako7eG8yM0TIAkxQpQUBjWVCNfaUkVrrXAGC5e9MA1XmeAM79TufhbOhiMPXB7jCYp1EQwQAHyLVBZmIxVMyEWYG5EewbfXYVajXpR3tagpOcEmR5gLeXyTPIasSdcHdy2m3lumFk0GRsoCoz+3TvZRLlbKW9kakDniyoq5AXR6ulmGgrpOzMCYjsy+N1Zy12Slq0wwbVl4QYknbrcfw3tV3ud8qQt0kjGaeY+zHF2EfSLcFXiTh92Sxh22zS2jIZh35WpQvKQAT6L7K9g9cUxb0xTIYAz7o7evpYD1/pDMfh0Fl8qwdbGYgBJVVjW/RTw6EngPW9Vy/BLy+ilMbkSzfebif44WftXSCNYkrkUADMasaCmZjzJH6MRkOBHBOXAbXIRbHD0qdBAqKF8tz2k7k9Sd7qDZQFXxHiagzMyIo4vI6ogrwGZiBU8hgeCLIp4epWJFNC5GZjhc+9h4nH4fBKGr1VphjAmZJ7AM7IR6Yii/sovbvbMf/XU/4a4HizRyvGH/AEvawFlNalvmTlS/65PlTc/hZRDiBDuu2yOqJfWzuxoqhm1PZUqB9eAhZ55TjApPdzAmAwJ9BbEi1Q+ZuVu6r3rDUYlkIUT1PAdtl42xT1Vj8/TlgKb4ct7YOLirYvD0veqL5DxH2C5yiuBVzvEdoheWVLZeRkYJXzGbU+4YuLhNZg2lELN0Ak+wX45WFU5ijAlEkfeqGB7NvjbLYJ03DSMkUZ0ZpGCgDt11PuGEyDxLt05mkF20qwaSTQZREGPsx/NS0jztyCBzTXBtIRmSAOM5XBQ5fj8bnpqU1/ahD7M2+F9xThlhQzuNggLE9mWVr8TzhUGlqqEfdp5r66YB9tv93dWNsh+8Mx7U7sf/AOY9K/0A4yTc9/3KaTNt11tVii+xJPczXs57KhbXo+fstgiviaFBZZx+Hx39LkofK8Nrrs9QzkoIAHmx8TfC5aa13PiApDo3iqf2LMf4otXV56I00wq5ZsQc/wDCMh7Tb9uF+6QNO2SGAcZm7kYHP7yUrX3Yxm+sLzd5Ul3XxF8yVNamK9mHH6KOkcYFOQAwnr8yqVPDQpM05BiCJ8hub1VLlZoBu5oopPHPV6tBY+23y1adLtI4sRl2kLkPU3k35gKmnvKrEDOAIWfLIfCzl/44iG4L8rLHdolVehbp0PYCmVv4tcCk2XwrAhK3V9POdCzwpHCB2Kiyhz/UwxnaPL8YaZesz0nPuiFI9Vnbs3vQty/HPANakijpTJb2sY+F6N+cKagFOpqjfQSseUCD8bzgx2FUk92zH96B8BelWG62PiKyZ0TNGQomjk77Q8hmDVLxV4MatGaVJWhwkbZfrtN1DcR3t3SNMiwraW0cbRk8GrO7NUaEtUkccZ9XbUadXw1RnKk5gfaU7x1+0vlbhuRYesraawWoH1d5rGpXjtMAfs7XssLXWqBmGnYMoAc7lSvuh8tvdfhBvLLzqtSIBokoVgLpIkcDIEyOBt2G2yq2VlWvKlKFe0cuHZpgVB41jVm6W33Uq1NIy+YCv0VKozAfuwjFF9WmM/r7bf0uU0qPvYxD2TTA9PFIvffS0KzOXlt2ReLf5oxNRQBgxqAjXFTUY2LACCbKPtQ4Mg+qv1Ygp4q3CY/dbDet2UjuW+FLcjCQUKi75DpNvDgMHxxSf30/63sxilO294r/ANQ447YUf2v+Ytk21BYW7A0jSuY5vSnqWNdAMLfz/iS7kqnhrcW7M8V5Qen3KgevHClXNPSoBMmABmSTsANyT0t5hBgMA5enXpGof9RgajjsXKF9BPbemxrrUbWWA0KZYkAKBmSxMAKOJOQvDc2q4znVMUcQKyUBvRo1BRpuetWDqqRwDHSOlssL/OXlocpASdHpoCqrUsW/prmwn3HibdNvuWs7yzj212QLIrl1mRHFVzK3sq/E1oSPLAWP5c2H5cXrnu6rV6Lhd9CoH8J/aIMt0s7G4SlzumScRUqLTJEJCqGykFYBJK5eRu7fMFPmfO0pYQ97hqOHrp3mY72o5TxrI9xYhOLb2Jy9KXJaimnh0UsAdTsXYgTENMQGz8xdU+QyyaUGd6emY0xFO5bXr/u3Y86Wsp+ssuIqJ1U0bqin2qLKGDqiAFgcLYVBDsOjEfGxfpdLi0m7KlDTlyxFbeNnj43Fy3kLeMfDNPiG5/olQblR7fyua4PplM8GNyjlbjp54jxbrtk5XK1zHX/MkWIJQcfYdiSeC8q8cQ3P9FaDDKxHAXPcH0pJzVl7TcoBqcnHwOKF3e0c0gsd0lr2GOh9MkT4gu70VQw1ekp6EgH4kXPcSVy4laVQjsH5A3JWSumvv/Tj2N72cDoeHd0lPIlbo/4LUfbiOLvGFHvYumPKD9U3MDcPeV+GGf1MfXF9usYQySSRxKtO/I2VangK61Pli608HeJPEV/bw3O3XO1WIOaSWZHCxJ9Nl6lGkmYd2MEcT2DFURnMKJN1r8ywuBw7mlUFRyPeKtA/aMgCB0GbHK5XdVEsYFwChVxNRe9GhB9kMpJ7BBJk9TsLgi928aNfW58lWdz/AMsf78azD4B8Jw+ztFu57ZpLiUnzOabLU86CmJ/o1b7vxvKVPmLHMTpqsBwlmn10sonyEXb6VRH2rJGFpD/TT0RfxBN5BPuO0KKG5kb+G1k+ouyY2abw1tEEEnyGy7KtzkIhM1pF0g/JpGMcr5RxoASeGNaMHWPAe3+l4tebYqqwD1oHEnUR8Sx8u2xDjKPU+z+tsUpU1IkELx0gA+QjTeIRXljcNktpZS/4ZY1TPU0pHld8x8tCeWGxf1Q7vcXElxe71t6yvIXzW1tc1BPYFECrTkEooGgGNm+FemhYwY3j67TYb5lwuEoCjoNSJMktxz+5a9MUjsFEidp63PisF9JrGqpNMQBAC8BH3rX/AJC5cVNtN65GH2gYb4/1PRE/7nfrmTyjtB9sty32YZWub5vX7NBR/hJ+t1v03GOVrxeqf8Sj/pa075O4j5Kv/iSRJ/icYfI/1P7Ausl7ukvobSL7IHP14ZhGbZSfS0j/ADdiD7tMD0X8S12NQLxHtuw5ZR4yfN2/ALaIvT4PNag9nzMJJPYArE1PADBX9YXg7ZvDG22s23rdGaW56btPcdX7sJWgQJGtSxGoBIph79Hqn7Btbyfn1fHYtadQgKQ+ULwWdwo2unf0vvj23bEcupJhq1RV8Sd3EFvtPHFjY1WFaGh8jxGDng/wrLve2i6up5Imz0QdEGqKq0JJcZianUjXBZHpajnPPvo+MqU6dMPAEkPGfGct7kB9bkweG04dNZ3zEjYcPSw+WNvyn+/uw5P4L6Y0e6PHvdO1jXs4vPz48MNpIvPrz5n95aQ7NVVj/spdYBsruVGx/j2WnGIrxFR2j9B/dg9PswtOM6Adj3lkNPNU6uNBINqafMalbakx7Vw+IPxOgWLEWQaYXj/tL+Vg0jV+H/b3YJMljGadSHN5TSP9aW6j68M2kcLGR8Q3+nVjtpov/mrE/C4Bnch0dR7SfqW44tTTMAj05fSHuOuJByldHBHLQkfH2h8BiQHPOR57X1dU+JY9RPsGV8jyP134xwM+hsRNHVj9H1GJM4qdR/1A+/BCbX1Lia/NY1gy/wB/7nEhoq/3qP04kF8uM343CLKeIp54kGAjyHxHw44tfJvl+i6MvZiwxU1HxHD4csWvl1vsX6srLx+v9OOe+PP+/wAcWvk3y+53cJA3H69R+kYpFD5HHr9fL9dxRTqP0j9IxUMw4a+mOTfb7F8uyjLw+o48Evbrjl8vt+m/VmYcR+44+BV/7/vx2L5fpv13CZW4/X+nFXTpwPx1GPRfr7N8ubbyvDIskZNVIIrqNPPEJWdDpp/Cf3YjqKKilWzBEXc53YXwSL2va7+DdNtil0DhQG8mGM78Mb1LDIbd3GR9RyNcZrGUqdKVIAKnI9nCyPmPDE4c1UGa7+VyCZv1N8870CbcC4MEihhw14EYGTOGGccRhDiOYPTgLw42rVwx0k73cLdjeO7hvRuJpDF3VZjrzpgNAplcKMbMPoQIogC6uQok2BUrTkuVwgajAsjb55KAVJOGnYPDEt5FmrkB4Gmpx3UFEsb5SwzVyGb3eC36CxtvhOV6qeuodIO3W4sDdFAFGZvLgMOFp4bFuOn3i450xPR7/G+Gn+nTG7m5qlOo9Pu0bu1jZcrWCkqZtmelvRymgF1NUY9uVrcO33V8e8Ci04voB7sMk9jdRVQDNXniVa3L+WiNQZ+J3Y/leer8vrrUIgt22jh37BbOpy2sDFPxrwNrieEYJpu/cs7MfZQe7DRttu1nIZp0Iy+zXhhpV+Zn1EUaIjgTaY0alA+NSLXdwOJ9lkPReg0OIuBN4E2m0gV5jI7UoBmp+/E263Fryf8AKvAYZVOf44ZjQs8ItUx1Z3F3FOM76Wk3Ej8C7H0OrIsimndGY1+3E0XEsrrn7qL24Zr8wY4DUzDyi1BMmL59HpxtdhNibj9W1i0XViuJISeAfX7cHxeiSUGSXMq8FHDD+l8y4hVmrTVvgbQtmc9rjOFQ7Ei5ZHW873DwTudgpdAJ05ZDQ09MaZ8wkhzEMRy00GNjhef4PEQH/Sb9rb23iXIJmTYrYeouxkdllzeJFXgYq6shHJhQj3HGublsFjvaESRqr8pEGVgcfTEZKgBUhgeIN4LAc0xWCYaKmpPuta0yvZbB6a1BmM+t5jaXhUnhTgQeFOfpXEjfvC19sTGSjSQV0lWug7GpjfWu5fzehjhE6Kn3Tx8rA7blqUGp5xIs5ZxR31s8ROeqkU/IePu88LW2by1nNG+YCntUrqKdh0+HwwxZdSlTsRF8NxqxVgw3Bm/C5Pyshje1fuSQPkU0NCv0R592nCvDBa86G6BL6AkMgo6jiVPKnkef6MD4Wt9FqlH9xz7H6+RvuIpBxO/X87k5vgP5phVqUYNbDiI4vQOYHmlzYSs1JhBjPKdu0HzsBc2Sw3CuhQkhEBDIxY0qdKkgDiTpSmJ1y6xsGmPtLQSZKtUcRmVSWNdCK1rxwXiqlNKb1Afs5dp4C0zK7ZZkXmuX4LEYjFUMPpI1VFnsWZZvIC91SrYemS5CU3IzyAaPPiPKxW7OzxSD6Ii198i0+w443JmKKGQo8pDjiD019gacDrWnbodcDUF8Y8/wNkJTg+X1n8rO5lUmjUE5aD8WUC1+NxOun++QB10rnmO02uzW/VQhO/pULUA8NcvCpHMccH7bbZIgZhAtxCf5qmnUjrSjCmmnGoHwxKu/pfV42ufb1vp2tUks3iZc6kqyh1YCisOHs8/q540K726D5ZTFDmAU1LayJn194J59uLX64o38rvF5jLCI2JOq9o4UIqP78sGZYBbu9vOcySZiFZcrq2mVw3Anl6Y8b9dL9tdGwXa2zOGOYllZQO3gTrpy7cQJ7N7OYB+A7ysv0wfThTgR2jEGIQGO0FbngHe5qDRPZncGYtmSAVmjb2Zd3gahB1V1JFO2vbiPtV/1IZFcmtvLayirfR6uU9uneGAaZKqgIgpRqD2XLVpaSsEkEOsdJG1tkUMrZzrxeG9hn8biwVaUqTAKPQqT10VMz7DZvcCTJ3TQAnT00/TjqdWeZgeBk19CRgzBpFCnl/pg+rEkn6vZcuCAODR4zVI3+7NoOe4jXzHFHV/9wywfu0gEUf8AmPrcHOyV53iKDEBKldTmAcqkZj22BnkmhmWaA5HqAp8+AB7QeBHZg9dbPAmaZJHqp7qMQFCn8XAMwPupi0R65Z9vA2v/AJi7adgRm3Q57XBTcMTJI0nUCDmIzBU8CDmDerT5VwlPvlLVCr+Gn4vEp0+8SAJz2uXJJNd2aG2/mSFARmoNTlda9grXXiMQLK8NlaST0WXPIURXchUZVrI1EpovdAFeJ1xXR9CxsT4GzXyOw9DlbGrRpYpqTfcXXP70QPxsqjijzzkfe5GvSIFUbHUm7f4lIe87yuviuVpjKQgCo/dFepSZbrMGPW2b9VtjFuG5X9tfWVhdW8Vv1/8AcQLK6SdVIVWJjSiNUsRrUjHm2+EPG9rCZ7ApZi8jiclNyt4JGRvvEDhquAA1Sp1BPbhV8yV62FSnXp1nQkFdEnQcxnAIz8UWPznmXLMYKauxLU2IhlOkg7yA4O4BGVm8tCVA9MorQwIfKcwcswcsrI5ZRrYVnLUwysvASwYbRKkdQb1yPYtjh1TaNqXzFhbH7Yzgf4bs7+12i2i3Xv3qhhO4vZbgSHMcrl0kValaVAAAI4Yz55xjW3qz6A/XNxYitTWq3cpRNOfCYb3csiA8CDIsj6OnAR8PqiySdcHxLkJGlBB/sz62cjtLZB93Z2sfZ07O3X7IhgdeWFre280Drk6sbpnWSYSIWUgSI3UJDKaEEdmLHH4t96reiqPqW4RiDI/Toj/4c/WTY/doP/7j+dlLqUghmMcMhI4jICzIk6Q0+79AE+wLjJtg/V5vG37tbXe4X2231tE0nVgke/nMiMjKO7NF0SwJDa6VGhxc42vt31T+6Pys2vjsM1Iiknd1PCQQlPTIOYyWYNi90Dwn2myddYmDq055hiG7D7+/W9WbcI19q7RAPxXKr9sgwKTbtrjHc2/b1/hsrX/9LAPf1m/1av8Ae353U4yuftx5Ko/Cx+5/+XP+An8LI0MftOfOo/8AzXObetuX29xtB63kP/6uM/8AF/6trfxPfwX1veW+1ukAhkX5DrCTKxKMqxvCiEA0Ohrjuqo3GofVj+NnYDm30em6Vu8qSQRmRn5gccvZcHcPwpn+z+lyVKdTw6IkT4jByPDM9Z9tvT+IdmT2tz28et1Cf+s4E+F9ht/Cu2RWELCZgTJPcmJUaeZvafJ3sigAKi1NFGAIc/Zb4m5cTjqtaq7qzIpyChjko2F0GGq/8N/7TcvdagNcMQP47LIt4l2NdTuVia9kob/CDju5eWaGWOK4kt2eNlEyLnMZYUzKhZASK6VOmIxSqH7DH/CfyviVnDAtUqEcfET6e8N7p9Hq/cYecD8bkWioIPdo0HY5T5mDee/rJ/WBb29ilntVxBcdUn5mRDmUKDQW49nvu2r9ijAvf/1bbLtO13l/PuV9O8Yzxq8FsiPcSEIpfL1JDUnMxHepWmGPLeXHF1NDBlBjhp7RmR7o3PAmBZWA56UqLTp4dNRAWWk+EGdIloXLb0us/QUavUUSuSqc8zxgHc7DoJNx4jBPjG8dTSss2ldgdO58Of8AW82tfnbksYrdp5Gq7rBGAFXkFC0A5AV5YM+FtnTxDvFlYB8kczHrSxgZ1t4UZ3apBBKKKJmFBUDGpSmmEoCmhbLiSWJ8zmTN05jjFwOFfELGo6QoO0sePkJJ8rSvWqYquXcKSx2AAAHZEDK+Yeia1UUzJA1Ex2dD2mALos/Bl+0i3U1xbxMrLJ0ZZI1FV+gGZhWnkMa0P1V+HAoDz7rJ59W1T7LdsLq9bEVNUYWpBBGrYkdi2sPzdivsov8Aav5m2eFSlQqU3atTOlg2mRGXbfP5RSPp+0/9Lz7XZna5mnFzXupbxOgjJ41kkGaSij0zHThhi8YeDti2a3sYLAXhvb+8ito+rcCQZWZVY9NIo6k5goJNBWuGeA5c1fUa1N6IEac/Ex7R7sdm9gYX5kxteo0hdCI7tkvBcvsj7WfpZeN+YK1JpovTcGfDpBCjrO+r1ixv5RQ0MTlGmD4t5zG5+yDfNlY7/fQRzW/hmV4pkWSOUySBGRxVXVmlSoI4Y11UihVIYlCxxKsUYAGkcShE/wCVRhi6csUkNXzBIPvHMEg7DqLxlZ+9qM3U8f49blHPebcBTHog+uTd1Uqo/je8X3Xwp4tmtZZ5dqjtYrZJJWBuoVGVEJLMr3L1yiuo1xoP6xr8WXhTcyDlaeNbVSO2dgrf8gbG2ocx5bgwwp1GIMTCljO3n7LyHLqevF0chk4P9vi/CwMW2O5m6GuUZh4VAIGR4ZCLZKvvE8EY/CPrN9bZ4I8J3Fla3H7ND/MW0ExzXV4VrJErnuiYAak6Ys8EXnW8LbE5Na7bbCp/ICn1ZaYaVPmPGg6e8zGRIZhJ45CONquYDRi66xEVH/8AOT+NgHAUQSO7TIndQePUzZtJdaKw4hf/ACi1X9ZHhjZdm2e3u7CySzZbxY5GiMrFlkRsoYyyORRhUUprg7+sqM3fhLc8ozGEQ3AH/hzLU/BjjQ8k51i8TjEpVX1K4cQSxggagRJOeUWk5NU7rmGGaf8AVUf3SPxtficJRWhVYIFZNDCFUZatJBgDLMWwxFKaFYfeo1B6gavwvKb7cN4vreCLbtxs7OIQr1HuJz8y8hHeGkchVRwHAnDH+qzZNm3623Q7jYrcSW9xbiMtLOlI5YXJBEUsYIzJzFcaytyhauIq1KimorNKqPCoED3swSZ9LC+Y+aYvA107moyK1MZAxnqYE5Z9LV0+YGnRpqrKjBYLMJPZEggZet95dhaVWlLKrMHYSQDlCkb+d57c+HJb2UPebzZmiqGYNe3D1AAJAMCjX1x+h4/B3heKpGy2J/jE7/45mwyp4KpQWKdNV3jZR6kZ3j25/wAxb/Xf+5/+a43xSVmHeVC0eZ9gOVsRgaI2RR/gT/lvBPlIbeK226xmNyGlakjJkLyzuqL92dRTQCuuCvi14/D3jO4a2t4IorO8t7mGHK3RCgLIoyLrkVtco40xuKRq4bD1alVVDKrMQpkQoJGZi1nLa1bmXKKqs5Lk1FByJ3kDxTPQTair3dWrTWmWKkgZ75nPKysQlLD43DMVhClNn4dVZstupi9oj8CeFrQ5P2PZyMlFZ3Nw+ZlFGahmy6kE6DGOS/rn8SOaKdtXX2ltZHPme83PCOtz7Hq7KKzZGM2fhv7rKN5swfLasZb6QSc8zTGfsslcHRInu1E5+6vpuDwuc47CLt3cdjVj+V7dH4b8Ox+zsu1D1tI2/wAebGFN+tvxU4/83En/AIdhH+9ThU3O8e29U/7Z+tzbcfLlOfcqHzqr+AuIYSmNlHsX8FuX+YYMDOP7Kp/G/wBAR7ZtUP8AL27bk/hsrUf/AIWPzrJ+s/xfJ/8AFbkA/wDDtoE/6BhEeZYpt6vwX8Qb0a/L1H/he2s34XTuR2+0348yww2A/wDo/wDM1/pRemo7kcS/wwxL/hQY/ME3j/xVLx3bdKfllVP8OMz9NxHCqR5BR9S3qV+X6I3o0/Vqh/G+92OM+pP53X+a0RmFPpTpD87/AFGJpRwLj+Go+zH5k8O7pv8A4k3zb9ubct0pc3CLIzXkvdiXvyvQHlGrYyn0quf9Wp/cb02O5Vh8FhalY0cP4RAHdzLNkN/b6Xbu06C/UeaCtUCKtQbmZQQAJ2A47et/p0Tyc5HPq7fpxCDoopGoRR7Kjgq8h8MZn6RV/wCJU/vb87hY6mJAgTl5Xw0x90ewWRpJ94yeJ7blvMACXY5RqSSdBz+AwI3YXF1t13b2rJHNPC0KSP7MXV7jStzIjQs1BqxAA44m7xmyLtn+0fzvlHTrGowozPkM/jtY4ToB7LJCaWBIJgz59B7bxrbtpuv1h+K9xmGeOxSfqXN3T+XGx7kMfJpnQBY1+iAWOgxr+zbbZ7DYRWFiuSGKpLMB1JpW9ueUjjI/wUUUaDGpw2NXlHLZ/wBWrmoOekba2HwA+0cut5jE4h8Q0k5cB/HQZDpYGOofScUqR+nQRUJ+83vFQfrPAWwFLOSMz04dn5njd8HhzYLZVSPZ9sAVVUFrOCR6KKAvI6MzN+JjqTrindd7tdkspr27kyRRLUj6Tt9GOMc3Y6AYJqc4xjknvIBOU+I+pO56/Cw6NJqzhFEkmI/jbtPAZ2IKCDYR5ZD0s0Up7OJPQdfyHE5XG8SbpsXhPb2u5bKwD+xbwx2lqrzS00RaRVCji7chj8/eKPEt34v3J55m6cYBVY69y3h/4Snmx4yvzOmDaFfGYtwgqE8ZhRkNyYG3+4XpuScoWgoZ46z989c/sr9kepselhw5+6o95pOXYM/ePD2mxeacwCL3FGf2jxE7j94/a6bC+b7xDd77fT3dyVbMxoyKFjVRwjiRaBYkHs051PPAeKTvPEAUj9mI0pnoKMATpXUGnZ64O5RhWw9FtRM1GDGdyYzJ7T04DKzNY1MmwjLt652HzavTq1VWmBppKVBHHPh18zubDiVDbnj2dL/UPgS3l2zwvs8NHV2tFuJaZh95ds05rT8rqMfm+XxB4gu3EQvN1kZmVEjF3NqTRVRESnHQKo8gMYTnGNqNjamlmALMciRuSBt2AXoTyTDUgzuuHAWSXanwHElj7bdUKIFNRlkAOHAZ/Gb4OcF9KpTqajAAVlGfQALO9/rAyt9Jm/qZv3nGf+A/Cc3h+2F1ukktxuk6d9ZZ5JUskOvRjzkqZT/myU09hTxxje9dt6jnzdvzsrmOKR6hSjTREEgQiqx7TAkE8B9kb5m5u76KPQCyQalRRqZthI1lgT+Q+J7Lfmly4hmXNgQ1D1P13HYwpzZISLkmYBSxIUAEknSgGpPoBxxkX6yvHWRG2LbpVaWZuhPJG4zMzEL8shHKpHVYfwjHZm2nKeXGse/qL+nTBfMZELnJ6jLLqewXDozjfhlc9V0wqhj/AJjnSicRqynsOfoO03o03i/w7BrJvO2r/wDzUR/wknC/F+rPwfEqLLtEcsiIiuzXN2QXVQGOUTKAM1dMAChWb3aVQ+SN+VlNzfGSQtVo65Z/7IuLuKg3UjzKj6zfjRD5kAdAFG3DrZKf9YnhS3FX3i2p2qszD4rFTAXxJ4T8N2GwbnLa7HZCaOzk6LLHLLKHair087ynMK92gJrwxCuCxT5LQqE/u/nFzYfH4mpWpqaxALrJJI+0JnMCOt9NBlEnSo7XT87utPMBixUTllsFJ4L2XMk/Wt4Qj4X8sn/h2k7faFxgNt4b367A6W3by48rK7+0R4qOWYw/6LDzKD/rvZiry1QJq4XVGcum/tN07k/ep/3H8FNqWq4+SNWICyYzIy4dL3Cf9cfhlP5a7lL2ZbULX+1KMZDF+rvxNP8A/B94b1t5U+uQrjHryjGH7NMedRfwm9h9N5av+rQ/whj/AOVDbn6PAzZfRXP/AEi0ZXFtuap86g/F7YvH3jiz8YQ2MVlHPai3mkZzdqFzZ0ABTpl+GXWvbhU3Hw1feHpI4r+1mspZkLxrOYy5UHLnyozNlDaa014VphTyDAVsJiSzqrxTaO7YHMkDOdIHtt/hcVh8RrGHcEqAT4WAz23AtjzLSuEKaoL1afvKy5KGPaTmbUVqVWnpaqDBMe8DtvsTeleHd+vLLaYoo91stGfL0raViADloS0A1GUYVtqs2itYVzDRR7OoJOpI8q88ZzF8rpV8U9RsFiDqMtqrUxnvwqHK3LN4jO9tqVcdyoNWmSAACFeIGXQWIq5CLaNw3q+uxSa/aYdnQGWnvVcCqEUB19cLaHLMPSbUuECHqaxJ+s2x1CymrkCBV9ifnY4U318wCaZif6Qv78VmIHhr5HQ+44qtOBsB6zdwbsXniT6RdSLtBr+g8fjimrJ5jsPHHNN2vs3W7609klTjhHB4fD++uKR63e7z6XW7Ov8Ai+OOKBjShB+rHAL7fpv12UDaqcVBCh0qPTh8Mcvt+vkG7e92V9P0Y+WSvn6foxy/X2/X9kR/Xy0OOtH7D9Rx2b5fom/XUYff9R+OLgD218m/Tjs3y+RdrisnaPj+nEsleDCnr+ngcWut0i73A6R4g/H9OJhiH0TT7Phi03WbpF2i/rLcTYnvQxuOecV+vFZiYfRJ/h1+rjiDE4U4gZVGT9259QG5jzvgMcL9Fum0tsO/jpPbxRT04aCvphMjgniYSxpLGymodVZSD8MZ3EU+ZcvOoVWqJwMz7bfs9JwVLIwPCRdxobhccW5bj4CCgtZzFD+B9QcS/D/if51Ft7tgJkGjcM2EeH+YWUhcRT/xCxub8uNA94g1U/8Ay3IaXQ31Wm0i+2+7258lzEV/MOB9Dwxoe53FtdIYpUVxw1GuNHh8VSxKzTcHs4+y8L/MKmFYNSYgjhcZWNxcuR3vNbaQJKjjipHkcF7zw5JVntu8nHJzHpjd4iitek9M7MpFquWc/o4pQtQ6XuG7MkbWy2l2JolNeWuFnbria2XI4ZcppRgR9uMRj8K2DxLp0bK9J8yYNGqLWWCG4i5VaRcIJFidi8JztORdKYkXn+LD34sS425U6X0OJXmMOKGE71iauw2FkP4TF8qYSrhGAqKR28Pbemwq08dSbUJngbI7cLXb7eJlapjNCvphP2vd+qzRsTmbXXtx2Fp7cLhqEAZXBSFTEUlQCFKCG7Ytlg8IaC93MgGV8ul6a292A6cqIpYih0wiCcq1K4JNZMiBYGq0a8sxfjRmMA5XqTTlZi28blYTyF5I9QeAwnRzklqVOuDBUQmTYWuLz5wWKpIFR+F6FqYgeVum7XG3Xe3SLGMjItRyOmE64vRHbvVqVFMEY9KVfDsIggZGxa9T9JvK8hUwWJBbvfECCZ6Rb7mhWhh3Y8RA9bHC7ykiNcvnzwZ2J7EZBKgbNxJ54S6epmwa1Vqdcd4G0dl47V0FucNg1bD6kALHeRYyK4k5971wU3PZrm6vCm2iOJHGhbkfIYJcL5Ww5by5MX+pU1aJ8K9R22mDG2VXl7e/KoOPH4XQL+zgXNclIl51I+zC14h8Bb7bVklmW50zUFR8BqMLqOFr4htNIO3le4w5w+EARaXd9o/GwQw4gC5P5Y+IUtSqrUj7JGk+nCyl7+sTbbGOSGztzcsfZkbRQffr8BjMJY2jJVgQykgg8R5YT4T5dqsv68LPq16hSGAIzysdsQi+7n9Vj1KZQlWBBBgiz9z403e4aqyiIHkg/fhcoe3Cuj8vYGluhc9Sba3ZsTUOxi4rPJ4r3LK0c8xnjbRkeh+GALafCuFz8mwpg0x3Tg5FbY3KMQ438QuK+ZnDOxAygk0HZitxrjgBVVBMkCJ63437cmOt+F22273G3uJI29QeBHZiFImbkdPLFGaM7iY55m7qJyuQDKzK+JFl0YfLMdaamJmr5EFffpgE1tUcCPccUdFczsey+yOtz0sTUpCMmA+8Ji44EWYfckvIpIuopkD90FlFK/TRqimXiRwwumEK2agNORGKwFEC7316hqsWY5m47cLO9/ZcaJNcZwzgBvp5vwmhP28O3CrHdSJkBAZFfMy5RqR61GnZpigu93m6Xp8N4lxbh40DsCFyjQ5SdQeXxwoWPiIwrLGuVQ4DRkihU81BGYe7FQLvtck3SbYt+sYb2GQrbo0sYp3QKig+Kt2cjiuG+jdred51EkiBXTTve8HKQPWvYccKg3ba+3W0eaxne1zVYr1KFW9qNjwJNNQ3DlrjRjtUMvWAFEkHeX2hXzHH0OIoNzadV9vm15ts8XSujHJULNHJbtyZWOqcdAc6imGm+2h7d5HyAMDWo4tlpRge2mBawOjV90hvYc/hczLuDZOCI77QTAqq1P1YZfGLgUwQRuCD7L+kcNGkwzDOinLzzDQgnHUHSbOgqc/3yClMob21B5kNU+hGJeVv4KtL7lQkfutmLEwtb6LiEZvdP6b/APS1rfm7D/8AcYTFDavQAY9KlLI+tvea4Ic15fWpJ/mD/usP2t/qU/bI9Rfl3du9oqlKyMQCo7F1r6nT344RgsjyyUyW4M2U/SaMgoP6nyinZjuJ5ZUFY6AAjDUJOQ6rbWvqZYPEwvrx9lxct+bMMcDT+kOTXQikwCks8DKpl12PbeT5ZTBxCZe7LPP7PCP3srkbFtKbvv23bU4PRgJku6cAkf8AuLrXzNIR50xb4LdDdzSX5t4rWbv3M9xMIjOIZBKLOJSRnWafI1wdQI48p44VY7EDActqMSA7qEB8xE+iyRYHzNUE0qaks1MSKSrq8TAgO5+zC+7xkzeopp9Lx3hXwh2qEdpMwfMkA2dyGjUY1HCGXle9mNI4lRxOe/C9ra7RiWaRFqa0LotPLUjhwHlhQi3Twgj0WXw8jcSBBZ18+MRxj38TFt5M/wBLPK42AdOIj9xvytoKQUADgI87m7iiCVzJ6d6Z/wD3lzty8apZ7va7PaWkm5XVyisot7i3VEzZtJHeoACqXZuCga4J2rQKqSQxW6BkGR47aGImNtRlKxI+RhryBGIKGBarResai0kQx4g0nbaB2i+O9RsmZt5g2NU0041BpM7Lw67jeyPo9OZUZjL3i0dmZIuv5/fiRl2a2XtMu82w/wDtwyYlSXSRq8jsqqis7MxoFVRUkk6AAY53FEb4lfSmx/EXXQT52NI+5V/s/rZQpbDPMxtxNgd/8Vbr4etUubnbLEh5Mgjh3KSaU6VLZVtFGVBxObmANcVf/Mjw0jZY96iU9irPWo9I8T0MHTxDaEr55704GX+Pjwu45fj1X/Iqgb8B+NjiIJK1AFiSQoiTHbcv/budJNJ2EjNkP42uf/NXcn1i2Kp/jvH/AMMOGFv1nbApod5kP8KXZ+xcT/yVRvigP8KfjUuH+XY1v9Bv7l/5rh76lHH4f8tzkYZeFP8A2bBJ+svxJL7Phxqdott0f7I8GT+sjZJBVdxunHlDc/vIxOeT0FH/ALtfbSH/AF2P/LsUN6cf41/Oxe/oznrHt/8A4dnIKESO6+H/AC2Mt/G/jK5uI0/9uvHC0iK87bfuhEUZYZpCKAnKtTSmp0xKf9Yuyfj3J/4bOVv+vBDctwqIx+lanAMKDSJJ4AeK4hy3FH7nrVUfWbBFemWAG07liuXmVs04iinT0Un6ltq/bMWvTtd4kFaD/wDxd4DTt7yKMKEv6xNpii6vy27FAQCTZFOPaXcAV5VwMcK8wIjtZfzspeWYnVpmiP8A4oM+wG4AyQJenPGGn8Ln+mUisgk9gVpHmIFwf1meJlm202EUc8M0cyvcR3MRhkQPFSCsZJbvZywrThjN/EO6tvW63d07HJM3UyL6s0at5ohC05HE/JsCzYymHGRJgjMHSfEJ7Bv5i9FyTBpQoB3HiXVmdh94jsJHssXFVBRwtesrKfBpEHYud/Xh5G1XOcSz1RRQygRJA4nMrPaJ9pvRf1QWHTh3DdJKfQsLf3gS3DD3CNPecNPh6wXYtn27b8tJIYA8/nc3P30tf4cyp/Thb81YmTSw6n3RrYdrSB7FB9tqMfiPpmJq1uDsY/dGS/7IF25JhtWuoR2DyX82Pwt1y3CdxhlH8Zb+1pNs4nrzwKkvEtopJpSAkSNI38Malj9lMAabm0zkBmch5nIXXuostqeRsBLP+1/H1sntRbNbPORyEyrp7+vMg/oxA/V67TwbtvMv8zcL3oqx49OCsstPIzSgf0Ynp/o4J341XCjyGZ+o+25OYL3Ro4cf6dME/vP/AEX42vqLOimPtSx8jkPhncuGXv6zuPdGQ+ofjeiic8K6YGfM4XBbli6miLN7q0n9cm5sm12VmrazTPM38MaiNf8Amc/DCp+tK8+a3qG3zEi3hjSn5ivVb/mcD3YY/L9AVcZMe6PiT+S2y+VqE97U7Tn5eH87VY49zhqrbZBfb/vFw/MDhaVNBuzEx2D+Bei/q8uyfCOzBvoRTx+6O7lGMfsPHW+7LaQ2FrddGCHqZUFtFIR1JC7EO4J1Jwn5zT08xxI/bn2qDeix/JKWKxNSsyuxeDlVZRkI2HlZPLE73C02/ZH4/la/Ac0p4fDpTaARM+AsTnlnqA27L3TxB/u9l3W3U16lhcj3rGXH+HGGP+sDxHNp+07oo1VZenAqkMKFW0GhGhHZjJUD3dak/wB2oh9jA3qF+XKEf5C+fe1Pzt1UoSpkbyP7lK/jat+eIDILGM47pPxNu/6lro9XeYy3GCxlp5h5U/6sDv1RPl3HdQKAnbUZqcO5dx//AN2Bvm8f+1bqHHxU/jc3zYn6GE6h2B/sH5WNyUSKq9GH/lP/AC3fkB1V6oP2iDHnr/O9q+Y5YFfM00rjJRckW07qz+5vIv1pwg+KXlJNJbO2PvCZa/HEz9acanc9umbQPZla9pSV9PcMa35RYHCVl+7Vn2i4flBhOLSfutF5fniFGoH9hx/a5/OyvmOnpSi3Sq49qKfztKtNj3i7RWj26TVQc3TABrwNWcLqNdMPUPi/b9ssrdOhGSkSKZLiXu1UU7sSZSRpzJxoqQrVxNOmWHXQQPa0D2WauKK0k1PphQMoByy3M/AXnMVjcDgiFxGIpU2P2e8DN7E1EesXmMRygPjsT3dFqhNd2z1EQx1e6ukcftG1uy8F+Irtwsdgzn8Nbf6++aYm7r+s65nQw27ylPwRgW1v/YQBm9WwK1DEKJIVB1JRfxujYzOYB9pP97Z+wW/XnnLajaadSpWb7qUq7/ALFwUOSVCul30CR4V0qkcf0qcAk9WY3XdeDN5sR9/8nG3/AA1u4JJPesIkC+hIOFq58S7te1XrmKM8Y4RkHvb2z8cd0VeoA6kwD5ZSbEqVDVMn6yfibIbmOEBzLOQf8tFLFew+LSPKbNw2Bo4YQo+oD+0QLnXe0yxyLHJeQK+rGFZWaTIurEqqd3QcWIxF262y2d1dP3WkdLZDzNfvJW9yhVJ/NibVnp7wEzGU/lcOGE1o30qWPZwFx0qwrsujDV0SJLOqKoA/xk/CzauVEttqYKPrP4Xo36p9tRr3cN0ZB/t4ltYWp/m3RzSU80gSn9eGTwVaLtXh2wj4SXKvey9tbg/dg+kKp8cKPmzEaVoYZTvNRvTwrP8AtH0tTzrEfSsfXYGVVu7Xyp+H65srktE1GeoRxj2Zn46Rbfk+FNPCpIzIn1PiP1geluPWwO61OZOFmm5YuTu7M7u43iG78RRRQfsG0srqQu3X+cniiREy93LnljYsTXhUUwhP41ktPHU9vLKP2e6pZMD7KPF/ng/llLg9qVxbDU8O7MMRUamAMtABJadoPCONnfy4VOWd+qnvVbXPVD9n2DUO2wKmpI0oXJO3iEDOTKqezK79+RixQkQ1Msqn7wzJ9Rl6WdEn6zZano+HYNdAbmBtPPvSYaGmykiuoxD3fKl/1MU3+FB+NhATcPeVf+D8av5C2QpyAbxjx7uHidrmLb97eHqRp1YmtBS1ySjWRGAAkkFMlad3XGkeLNjj8SbeYqL83DV7VzzanegY/hl4eTUONPyPAYSsWq0SxQZNrILTvEDZT8Yi1HKcc3LsStTMo3hqL95fzG47bR8xxz4eiqBNFSpmCJgAZHNiSWHAbCZtjzHl4xdBl2O4P3WGzeXBuzyvDbOwfc5PlICURGUzvTgo48edeA+k3kMMezNHC8tu6/LzB+9mAUkr3Sr15pSmvLG1rVREDID43HXArIlej40cDbt2PrxvKUqWoycyfhctGaTvRqjQ6EzPCNx+XW5O6WtlHtscXywZLb+TqQQze0XYat1CB1PxcqYhbtu6Swm3jUleoGaRiozZK0CAa5STXXXHKbtUqKpO8+wZm5aGHNF9dQqTpiBwnfM36pSSnTZgNo9pyFx1q/eroQGJnzjbK3z9WWyQrb/t67UPctNLDZgqMkKxBVe4Qf8AEzMY4+UYBK64Wdv/AFk3G17fZ7fa7bauLWHIrtJcM7MztI7OkYAzM7E6cqYz/wAy8yqh/oqEBViY4tAOf7sjSNpzOwuPHcrbEYqrUqYjTNRyIRNiZHiZ88otlybAq698RJPwUkiB+9GZ3jKzsBiaFDC0wJnQuoE5hgIIgUyR7b2nrVOMeH6w/Ftz/I2pfLp7ZfTfaCMZ3Tbr+U4RfexR9atBbM7vK4Tj16ewVT9QW9h6oAI4g8jzHZjH/wD3J+se5H3O27itf+HsrKPcZIxhLEZ25+gcrX3sQp//AMn/AJBcxpk/0uA48RlTYn9xv+p71iKCyiYNHZ2KMDUFLO1DA8a5ulmrXWtcJHg0+NZby5n8Qi+gs47U9KO4higWS4kkVF7sfebIpLUOnM4U66sRrMdOHs2thjqWASmv0XSzSdTB6jQsZe9lJJ4dLlbDhjLamPVmYn2zcWFrVa9XSV0iRHhUHiSZBJ2Eet6AZ61qdT9eBxnAws03JcwpbZWYKdkFuHXVWIPataj4a4UPFllvO77ekWzziCdLlXdzepZ/dZGGXOxBYEnUAHhimmM9rLwTUErFq6Bk0HIqGz4ZEixDSU5ED12uTFB6ajQHLGICgmc85IVgMutuJu7g8WnPq0h/fjGh4I8ZyGs262Y/8TfJW/8AtRPgOTxqH+4/nbs4zlg2o+yhS/GpcfcU+iexbjU4/wD4NQ+Zb/kF7C8jnjm/qr+/GPSfq33qcfe71tSH/wD69yl+y2GEmpfvj+63icxwie7Sn/BRH/NcwpgbR6D8ro9PmFXLuXXt1v8A8y3V+si6S88Sxw1KrbQQxHIA1c1Hah/iZvfi+3/VndwOsj7/ALcGQAKywbi5AFebRDtOpwb8so9PB4mskZ5DPKQDn7brS+YaFCmyLhtWppINRVHDgKccLVc60mphaTzmXqHLPSzBR2+6tzV+Q47FVA51AhQo93IZ8WrTub0jaPB+1RWduhhk7kSDvySjUIK6AjnjNPENq/h5Ejk8Sz3d0yg/LW8VzGY1b2TK8065ajUKFLkcsZurzzmDVHIqIJY7U1OUmM4N67B81ONqpTp4GiikwzlsljgAKI1N7AOJuVqNKmAoXIAR4v62uxPKqmEpPUq128OwBUls4yhyIn28L1mfw1Yoo+X2+2mJH+bNMg8te9X6sZDsniO6dDayyXUgRM6s1xJ7LNSmUaca61rjIpzfFs362MqUwPu0lJ9nhva4zAU3ra9NAPHiIoqSYGUlj+FnrTpwZWPITPxtXhcSVQqdbDhLkeew/G36+2O6Gq2ezwD/AMQE/GZz9mFQzibiCK8zU/WdcZ3C82oHI4nH1ieiMB7Kaz8b0VOkKf8AuA+AtjUw33VQeY/PKwXql+z2n67nTWUigrLNt69gSeD/APDDYGPGw5+muBKOLQ+5SxrfvUqx/wDORZ4i5HpHi1EeRUfULHM3bJa5OFxCf4TIT/8AbocUrIwOU/Xw/wBMRrWLf6NUfvBB/wBdy3cpH209J/K6Z3ZoPpg/0t++mPO6+h0PYf04qCx+zHmR+E3a+5dZ9DfL76nlUduLrfa7i41QELzLcPceeOWNiuYUMIpLtn0G99vkG6qZ9Rr9uDibTHaqsjfenn2YJ2vJYn5oeqzJRXR0Jv12KwJsIqSNwUt7qH48DhicAIGjUKPIY1jOq5kgX8/fmGJrMRUqN7b5fTtIsPFaXb8ImH8Wn+mDsExkQipqMbhsfhU3qp7b+e1NWqSSfU3y+qZFixtN6616WnrgxDcuoZMx+ON9/NMJMd8t4Bl2a/Qel9DHMWAk227gUt0noOwZh8MPuyuk0TK9CQeeuPoa47DvtVQ+t4SgTBEn23yDcim0Gz3K4smJ6aBjydf040TcLDb7qOksCFuGYDUY2dXBnHQalRlXgqH67zNHmmIw0aXbLhOVxhivC5CAbVLPxUykC5hjZeZVRUe7FO6+Gja9+2kzKdch4jDutyEqJoVnnox/G/YH5gp1yErDSx48Lp3nUXwpFtdvZ7bu6LNFHGxGoZKBlPuwhbbud7tM1YyY/wAQ5H3YA1Y2gTSfUeBVswRehxFCnik3E/ZYXbI3GCwtw3ewazdW1K9v6cX2Fpe+JLVpI50YGtVbiDjDY3DGm5YCA3wNvzyp6+tGIletyEcbpqMZ2u3W6vb6RGhxEv7F7W7a2n7simnkR2jGcw9A6tUkR0s2vRqYNmRhtfHqxtdCsm703CW/jZDCGb8QGJlvJDt0QpTF6mK/SKVGnpaxtVZrsG18LkEUxZi/kaYtHP3jw1xTcuZakmp7cbeo5nO6VWm9XhqaooantctBBTgAZdLS760bbL1JF9gt9uC26UngcNxXXHC0i4NWdmUwDBFyUUjyN+rIJGXWmamvrgQlx90uuvDHmaAT0vx3uxGlTlMXNwtukhg22OKeL70tow48cLlvPO7IockDWh4YXjEtiCUPhsiv3dNGYgTFqBVqYpnR/BGxthWpoqkwATbKttBNbu1xBq5qvYOzEGTewkLQvq1NCMC1seaZFNDqO3rcWF5c9RxVOxM59LS4ymMQy0ydSruPKy1wR1hxtxv10Ns6kpQfR7MDn3WW6VIzQ5eeGGGwtGqhNSHdve7OyyqGHFIkg78Lph8PT0+GMuA4WWlFaRJHG2azvmzK2ahGBFlMikVOY4Iw6LRUKuQF9Fg4jCrpKxINm1VLDLK3m+zbjDG8dWCjvHEfZ7q4aJkjQEU54Jf9QC602aIAvOYXTg6jq+RJyFycwoUg4Z2IM8LzrxN4JaXr3tu3f9po+Rp2dmHi6Ew6ucVNDVe3BGHxJpwjZr16WHVLBW63BzHlyYstVpkhyJ08Gj8bPpmnoGnpleF2+2XV0+WOM8dSdAPfh2lcrKyBRH3zoBTnhriMdQwwLVHA7ON4PFVKtWo2tjlwvHmmdo2ysivIquCIOo5etjNt8HpNJGlzIWJPsp+nB+zufl2MxPDQYf4j5nBOnDoCerXnaFOM+NxLSHG7jLO/ZfC+z2UqRxRBn5l9ceLLNezFlBq3PDGtznHVWjvCJ+7lYhUjMZm/FEUwBfp1HIXLkstuiKxpbRd3iQo1OIk+722zVVqTTkezxy+uL1MTiGy71vbZmA5bUxR1MIXr+V2JF9Chd8zZCWLbYoepcQ28UajUuAD8MZt4gvrjcs7ySMRXMqA90DspgOn9JqGEeoT2E3rsNhaWHXSigdvE3YeQAujmbMbxvvg5s8abf121HUjUAeoPdxnxwowuB5qsHvyvYzfhnb+LsWp9JuGb9vOgZnNuGWImqq3LFZGKURUCAVCC3Ei5Ivxicr5fGbt15Y+pjl9i/Xy7Y5uieLAOKNoDzqKVP18cU6/HHL9fb5bRYeIpIcr9QUVO8GfiRyHZp50wrKWU8cWDRdb7vfL0lL2HdI43V614o9MxU9nmMZ5HdywZekcmWvCuteZ14jtxeQ90vvu363O5tpLViwAJzdzQcOOTl7dKDzpXAy08RpIiw3QZlK0Z8wYr58m8+eIMRS4nY5N+DehsmZENmLPwNc+4PfU66fb99P8AGPjYIJUhlMEGfW77+L521zwxFpAVbJ9M8cyU/EK8OII07MdxlGcGCZO+1Sad2atADp7L14+fHEOHxzU0FGqfdI0uenQ9nQ3DUpqDpb3fsv07Dc2L5OlXEnHYMeGqrd9RAz1mDrXoZHjXrnZtCu7A1aMaxnVozGr9tTwNqrZ5nPSkIIRs3UT2FBqc2jADNTXtPbhv/ZNxul5BtdkkCzTsGvZ+7SMJ3mErD/LgXvv+JtMGVUoYiNS+KQZG5y6jfKxO+Xl+HerUJeP8tc/ET7qrO0/ASbW0K+IwhJpvGRBDAEATnk0xnZeKLcxxCpTQITGvSAW7dUbn8YF1fq/8NHcb5txvlD2Nky1TKAt1c8Y7aoGqL/Mmp9EAc8aJEILKCCytBltbRTHFUUaRiayXDgfTmbvHsFBywBz6vRwdNaFOe9fMnUToT8GfYdkm8/iq74mo1RzqZmJJ4SenYBAXsAsrk/0vH1SzMAm0hEEnicgDC/FiBep5fy9MDh1QLDEDVxiNlnjG5PFibMtdtKWd2JZiSx8/0dg5YXd33mLZbGS9kIJXuRRn/NnI7q/wr7Tnko88Qbmbmw2HfE1Vprx3PQDc/wAcbiGHVAFUZAQLlxdVMOhJy/I/ieHqeFk7jxBtdlI0NzfWMTgDNDcSREiuozxSBh5ioxn/AIb/AFksWW13ARmsjBLmC0iEpLNWrDIWmqTyIk7K4qlKq3iSm7doUke3a2+M5RWoUw9EsECyUZhl/iMR65dtjOKWzNHH3tJ9CCDYGF5hgcVVZaqo1QtAkMFcDbSJI9nst6XxRsDGkd9tVR/w4Lf/AKLbEl7+5ipSeZaqrADNHowqDlyoy6ciAcLTSxYEmnV9R+dxST1HnZC0cETACE/v/wD67PpYTC1FlaNKJI91TmN88xcSTxrstsWV9ztlZeKrC1V0rqFt6jTXXFd5Bt+7SJNuFha300ZBSWdXElRwErRsnXjH4Jsw92mJVw+MfMUqhB2OUHyzvlPEVaQIRis7wY/jzEHtsI0cGsylPLfMGPPxGzKnKqLkRKAGdKxp9AZ0+mXZZOw307nb/NWdxNLbZsonEckcTN+FGdEDkc8lac8RHujIRU6KAqgAKqKOCxooCIo5KoAxSpSrUiRUUrBggsJB6EAnO6NJNi06WCqEBadIkiRkDl145ee9sUw6Ul0ooUfE+Z3PrZI7jc8p5h/Ww/fhZ8R7pf7Vt3zNlaG4/wCJdd2WO1/it0LSF+xpFCeuOBZsjCUqdaqEqVNE7DbUZ90OfCPUz0sQYOj/AMKn/aL7i65oBsiNM5Q0lR9oQJYdiZ9SLHfrQ3CY7RBbSSu/XlaUq7uQUjARNCebuSPTGZXV3d7pM888s0mdgzNKSzOw4flUDko0wVyOn3mOX9kD0J//AEg3psFgKeE05IHAMKMonftY9SbX817ujha5CooCaTAAknhl2xaDmPMmxkqoK0ZEk7sRtkMlHYPWzHgbZY9z32yida28DNd3PZ0LUdVgf42Cxj+LDN4Gk23ats3G5uL2yt7m8kjtY1mnVHW1hPVmemp+9l6aDtCnlj3OMQMNgasZF/0l/wAQzI8lm1fzFUqVKi0ER30JPhRiJqbmQIyUAetj8uw5xGKpLvmG9Zhf9oi3HyzTp03+lVckltPu7qIAzI6lj6W+NdPM7O57zsWPqxqcAG3/AGSNczbxt/8ATJK/+GI4zki5BhMUTAw9b+2PrvSigEUKNlAHs/O7Nj8PEzl11Ux/13z473IWWwT96jXDiEAcSgHUl/5Qq/1YW98urXxdvWw7RYzrc28k8cckiZwpLy9S5ajBWpHEirUjgMTcvpd/i6S/dOs/UPifhZuBoVMFRxVeojI604UNvLeFNp3dvhYHMX7ii56IT7cvqBsLm+KXEd2qMCKlXYEHw0xJ2y2GfnbpsFqdp2TarNxSRLNJpgePXvCbiSvmM6r7sXXN2Li4llGgeRio7ErRB7koMLcVVFXE16nBnOn9xfCvwFwHfrGQPYMrN5XQK4VSd2Mn03/2ptrRw/c0adOPdUA/vRJ+M3PjfOyLXQkA+nP6sD4bgxuGyh6cVauVgRQqaEGhB5EHsxYtkTdcuIkdP91huulWPQGzKtAVFKyVniIkEZgiZHtvHt/uZNy3q9uDU55pGTyV3JUe5AuNXjsdijJybBs4P5oJpPj1LhsbXkNEUsCpA3gGM8xv8Sbyq80xirpFaqF6d7VA9gcC8Fz2oWxYQn/LX6/9wvWt8vYR21uXZupFKf8A91eO/LFvay/Fa42fLYR6RbVs0R493bbY/W6ucb6DwV/Yb+eHG4pt69U+dSofre/n/mU9om/oiciwK/6bH/FH/lUWteAfD62MLbxcwxu1wrQ2MUsaSKIq0muzHIrKQxHShqD9Nhyw0vdNKcz00UKAqqqqqigVFUBVUDgqgAYefMfMpqDC0myptNQg71B9nyWc/wBo9l50km858u8q76a9UZRkMxkdsxBlt/3QOt69MOlFQiCAO0nfiScye245nLeJ4UXJGp2C87kUMcSlluVf/KRFOgGnlhV3vxVHs/itSwluYrTb57NreJwp608eeR6tVQQz04H2aYIYmphGPEYhBM8O7YRG2/GzMHy98Ty9iAqFq61A7z7ikrGUnPe1HdJh8UiqIBcZbndM9Rk8TlNwYvGKmOpNrJyY92oBllhlJBKg+ERv1t96+XTCD/8AMmxy1G13Ff8A1L6Na/2YcK4tp/JK8/51P0pubcd1NgHnPhJyXsK0x9dQ3J/WRbNcQbXcDUK1xF7yykfbhZ8ReLl8SW0FutoLQwTM6lbgzF+oqhg1QKABAQRz9cEfKrhMZXQ/bpg/2xZ3JuW1MLiw5fWDTKn9MrHQzJ48LW/M9L9DL7NWn/tIw/Cx+d49MVhWk+IukAFPszwXsJztZ3Gydb2RRRqiNu73vbjVv3/HDNt0SvAjGmbKAzeYUaE4YsZZv3m387riv85x5fVabTAHaAcvK5sMv6Knzz9bA2uxzTasAg/Nx+HHDaIhUZdDjxYDtuK4xTY9lkRYeHaILcZiOoR+Lh8P04NCETTRxGi5mGfyXix/sg4uXJ7Lrw+q4hTA7bkiSPjcOSzO5X+1bRGO9M0SHKKZXu3BY0H4IqHBrwQDe79f7tRcljbzzR+Utx/tbYD0DFh/DiUVvoeCxWJO4VtPaVEL7WNifMFX6PgqVAcfEfKnn8XK3DVXvsRQo8BGrsnxH/ZFl8jw/wBN5jJEgt8CZPsRTeiTTxiVhEKRqRHGOyKMBIx/YUYFialNeGMkcybpesw+H7uiix9mT5nM/XbHurn3F/8AKQTXLUywRPN65FqB72oPfgfN8tdwy291D8xBMuV4urJFWjBh34iHAqBUA64uBqIUbsQvtMXym7U3V1JDKZByyPqCPha50hfh/HpZWIwnfpp1FO0Ccum49t4RddS5uJ5JGd2kker0J1qSSewFicbUmy+GoRlj8P7ef/Flv5fjW5Axu8HSSnhqaRpDKMumWU/C8l/OsfEfSKuX7ZH/AJQt4HH1WfF1GDToaAZ4Dp8b1o+V8FJJLEk/cp/irWtbX+ssWVja291YSzyRRCLr/MxpnWPRc4ZC2YLRSedK4Z/2bsQOnh/Yx5tZGQ//ANWV8FYjkdVa1TTURQWLBdD5as8iMo6eywH5ljH3r1T/APFq/wDPYmF5lSajTaSAepQwRAMy6nfstivy9gF+yx/+mPqpi124/WrCo+725GNPpX60+pBhnjtrEOog2jZ1eoyCPbLSteQGaNvrwYnJMQ29WB2UHP42v+kV23qVT51Kh+t7EqczoJ7rq5/fpD8TbAcnwFIFihAAzJaIHoB8Ly3ed/g8Q33zaW0dpNIg6yxTdVXddOqdKhmA7/GvHDB438YpcAbRadDpKSlxLawwQLPJXvIrQRxkwxcOx2ryxseT0quDoVKdSprRWGiUKETuMzsTt2zaXkvLDVrU8RUX3SGWc4H3oOUn7PQZ73i+cNRxFam9NYYqQ51KwgHw+6NwMvKLcc3rYLC0qypS8dQFEBZiV65liQRu0cYXrbD+ri3O37NeX2WMyXd8sMTskcmWK0hzSFc6sBmklAJHZhHs/HG6bRZ2u32wsujAsmXPbtJJmlkLuzE6EsaHTQCgxf5lxLNiFpqfcRQewsSx37IsnH8lGIxNeq5xB1NI0soWNIAjKcojOxvlvApWDtUWRmdznmFXYjoxvvLOa0cLhqSBqakr486urUGbgsDYzl1vZv2rc8p3T+EhP8IXGRf+9/ET6iWKP+Czt1/xjGYzO5n0H5W7/k+H20Vm/wAbn/yi9COX0BtRT2T9c2vPOqEZ1Af8NT/qcXrn7Tum43M5/wDrSfZmxjFz448SjT9ozr/4YtV/wYSReipchw7f/bMf3jX/ABi2X0Oiu1GmP8C/laWtz7D7LHmEpn62N7EZ5ZNSzt6lm/ecYVP4s8Qyip3Pc+0/flf8JxnDleuTkGHG+Gw/sJ+u3ndIvBR6KLytbn+r3GrL5LRX6gb3MyZeIofMUP14FwrNZ7ftVvNI8k67dbyTvIxaR57gGZy7GpJAZV8gMY+bnxOk1WKKqqWcqqiAF1kKB6AXrBTnbPyunJlaphu8cszM0S28IoHlvNkjcHtwN6/MjTEE32Lk7qzO66WS77ioBI7f9TTGWfrKuZDf2EaZhkslqMzLrM7y6gflK8e3HCQNzF6H5dwoqpWmPfBzUGIAEZ+dh+BciQD0tH8w4tsLUVlJzd1gOQDECfDv7t6g0mX23jX+KaFftcYwCEMdZCvxzH63XGd1L1nyBP1C94+Ay8Lr6wo+ANvPB2/2v/y3i6XOqizNMHpJdv8AqF7y93ar7V3ZL/FeWw//ABMYgWtyPpV9IQP8bnGHE8FqHypufwvZDAVJzr0QPOofwF7XvEH3v7G/EC8gee1m/wBFf7PzY3rO7+JrPZ7OS5juLW8nFEghimjmVXP+dPlJAjjGtPptQcMZQ0cLoqCQIGNWGZCWyjuiiRg8eRahNMZfCYV8RUCaXWeLIw9kjM9B1zOQvWYWilKqXd+8KjwwlQRO5lmI27L1GMxSUqRIDaR75Phy6DiJ+03AbZm8fjMdicVSFLworEEgaRqjYGM8jwvmZpd0umuppHZ5ZCQXqWeR/pNzq3/KNBgtsEBW5W4ZshjP3C0GhB0k1HI6jz15DFqGHTl2G1EeILsOA6em5PE3XGf90jKQCrCGBn3fu/ndMbizzLEwvhpzCj4SR8AOAumGii0zmNo69befCXgG9+UW4nkiSaVFLqwcsi8VjOUUqOLDkdOWK/2ruUXG6uWX/wAV6fURjP4v5mpJXqBFqMoaAw0Q3VhJ26Wzp8qwa7YegD1FNfxm2FLAhaS641Rtnl2fncDYqoftP6mzE/h75futNJ/TZ3NK+pCjAf555/bYy9udiT9ZOAqHPO+zFNf8VejPsBJtstCnT91VXyAH1XO+DC8T6AmxDWZtyTdslokNe/IaHnEF+ppq/ViPkV9Yzlb8J/TiGninePAgy/4jH6qdkyRvmLu1IDifYPxa4oB2yPS6nETmgzA+g/cTi5aVPUWhHPHgXiTp9p/IWPjGcqKdM5vl5C/EL1Pw/O6m7bOOKFg1x3xyXT6ziPKjtqjaYCx/NCJpYfxP1Fm4XB0sOPdl+LHe+5XzTbH+34UXprCFXlhWDOmhxn15TjsV4qhAn716vK76h0uPa2X9tRhcpiNDhdSblw8j7Pu7MZN/lR3z7wA3rINya44XTVbDFuFqQa1AP1YCZa8Dr/fnjF1vlrGpmpVo9t7PzuwKi62xWwjeSsbrQ8jgJBFdOwWKKV2PAIrEn0pj59XwOKpCKlFh2xf0BqYYeJZHaLsBnkboGExlPSbY54DG6t29mOtt2LxFLlrayBf/AFmVKfE1x82AMaTe3xXJMJiJITQ3VbkYQZuuuON3bbO0MzdmCU3h/cLROq8Sk016ZqRjGplnbfE8hxOHBZCKi9B712Xc3wOpuPcbh3qV1JwDu5GiLsa6YVhZm50TPSQQeIN2LRcbZXff7h1HoD7IwuyXBCsSdTiIUzvZ4pyRfWfO4Cb5uZxNKQaDXjgdLNQ4N5bjKtDSrmV7eFxARldjUuIm23aby/8ADwF0koMTkZgDof8AXAPZln3eQbcJcocEqG1FRyGH2NQIqV0cSYmOhtVhu8q/pBuGU/VfaWK1uV7tgBxOxuyZyLMeKNzi3Mx3KCklO8e3E7w5Dt0Ul1s25wRpdLUJI/BhyKk+WL8zwZKitk3aOlm0DKmhV94cDxHUXZsTTqnSoIIvyooOwnraiNwc0SRiQMUbxbfs6+mt6hgjHKRzU8MZo4YDNRnZ9ej3VRl4Tl5XzXwN0cQbaoE3DbzkmPWj4ZueD9zCUJVxgxwVueot/Q6UVBmQT12Ni0agaCptR3q4EPeB7rrTEXxbbyRRFo6lPLlgMCTcqqA1tqXhTPhcPek0u0b2JiuaoPXTEDaG6jZnPdTXFCL5im0rpG5sgMIsSnVlbaYphawZm9tuGF+43QTzd3VV0AGA3X6VWC/YXezMPQ7pO05m5m/VaOAuiOBZUuXOZjx1xBid5NW0GJFAAAHC+i5iIF1m56S60BoMeQmNSK4lW/LPS42vzmzu3MKiin1OIkFxdFgIFBHpi19g3RsxY1Zq49wKR2287TNIJFAJ10oMKbb3ue3Pm+XNF+ny9+JKZsavWegNQUkfVYOPpqUYkbcbEx+OxFOVegCvUG3zcF6MlTzFTXGa7h4pv7pSZHpXgBgt4G9pamPq1shkOt9wZ7xPK1T80qBCiKtMH7u/tu3epYvnpHUinYOZwvCdpHqaknEOMRXrtp243wmLrzMp9JYjgAPM2CSWMnMm5wM0z6dugxU938rlQe2+lezFIUCLY8v5f357x8kHDrfvExuRBpuZNuTWMbRQtWalC34a4H29jPcSMcpAbi7Y9y7lpqkVKghOA620q4yjhRBIy2UXZRpHbdja89xK8khkJdwxzMedcPFr4b26OXqTEzMxFV5fowelJQo0iAOAvP1edV2BWmNA63DrKmON3KrMm0E5m7SBofQ41beL/YtjsqLaxNOy91KCv2Y0gAF5vB0sTj399gBu0mLiLG52ZKY29LxOZDG7DsOCW8yfNz/MBFQP9FeAONHF8p0u5RV1FstzY83wtqJyixFMTLTb7q9bJBC8h/KNPeeGO3HWxNHDiajqvmc/ZfpvqqW2E3AI1w4Qfq73u4TPkjTStCSTiS1D/MeAV9IZm8hfLmGGc9LTsSbu1e0nkhkoHjYq1O0Yb3WlUWsiuuzCRcV+I0kg8Li0x2Fx27X6+XWVxYR5Yqb8b7fr+tbK5vphDbxNK51oPojm7saKijmzEAYKSbmZYjaWyR2kNBWKKv3rU9uWViXmNeTmg5DFSYuWjogE5MeJ/C+gE3WqGkgZqOn42S2jbZ4rhbLbK7huEoOaSL/y1sPpNGzUXuj27l8qL9Dtx9Z+Kt22yB7Sx+XtkZPvBFax/e8KmZ3Z3eh4CRiOwYgqPSw6d7iW0p9lN3duCgcT2D1gWqx3KXNbvq1avW1SoPetkpz0hFQBQYz0i5KfeO2igCznIt9lQf4/IW45ZzLAUKYAorSqrDaiurxbSra5y7beLDb7Xw/bNaW0yXFxNQ3t4nCUjUW8BPe6CHUt/mtrwwjyeKvEJTv38kf8BtY6+4NUfDC3mmOqYypqPhQZIgzCA9uxY/aIy4DLcleS0WOWFqP2suIPxIi3vIORfQaffVl/WbbUMx2kcD90bjc57Lm57Q+/n2LTz/uY3oUavRpGIjiUZpJpO7HGo4szGg9BWpOMivN63m/DRXFzd3UdQQks2aOo+llBofTCWP4ifQDiTwF6zDckp0yrrSp0TxIXxx2Tsb09apTpDMieCgiT+QHEnIC8VW+YPDUVVZ9QgatAUHqdAlh2bW6Xmzb142ueokZsNohGSO4uUapiLd54IABNNLMdSVAUCgzAYRpJr5oQDLM7MxZneaYsQaU1OZQKaAJQYS4PE4TAZMyVcQILU1cQp4LUYTAHECWJ4W/bldLvZprSVAoAGmnvx2gk9ptjjjXxzd1SIAqTNQiOGZSYAyyBYgAdtp6HOqlKgUYOXZiWcMwJHDOCAB0WL1za/D9n4fUfsyykWelDuFyqG7bt6Q/l2ynsjq/a+McTMurzNXzMh+2RcZrG8yq4xpqVZAMhFgU1/dTPP9pyzeV6VuX1DstEDzQfUhvScs5LgMCJqPTqPGeZI9WgFvIaV7DedTnZQzFRj2tUP4i9tMFwoaScrEigtJNPKqoo5s7FiftJxjHzClXTqmjqV7wGUk8K5p+AOtcY6VJiczw3J8gJJPYM71y8sbUrE0hDAyrZgcYimOF7lsRh0XIz0VFPwyCgdpIAvFt8x1jTdBTyZSPFqbPgYLxkbcN+/WALOZYtsihljVhnuLlc3XAOqwxKapGfxk5z2jGf3EYgrkImbgXPs+g4V+odmE2D5KcSpNQ1FMZKsBlPVyZE/sj1N6madIRTAt1zLnLYYpBpgSD7xzHHTpzYj7x8PQXjX7yq2qoxJPE/x8L1fZfFW372AlRaXLaCGRwY5G7IZzQVPJJaHzOMutFUsGiqkhIopoUY+/Q6/ip64xWL5fXwZOoa0H2wsFf314eYkXs6iUK6xUEdu0eR4X9BwXNKOKUEkeYg/Vv6Qf2bwWGr4nCOHotnO0SG81OR+u9xi+ZhYPGek4qK9WJT5ggvqO0HTGOTTDNmJQP2U7oPP/OPPhjAa065e0XsU5UVEGrT0/vS0cPsC/pDthnBVyHHTS59RC5HtGd4yr8x16jT3ADeTAT/APUN6puHhnat3LNL0Nsum1+atprUQue24turT1aKh/LjNIt8ktiMsqqRzCQn7c+M/gedVcJCau9p/wDDqhio/db309JX9m3R5BTq+9UQg9tT8CttOZclwlfVUoM6v+ylQPP9mh/J4P7dqz8zYsZaFH+Ffx1Xbv3hi922SROvZXEKd7r29xBKnZXLXqpUdq088c/+4nzl0lYOwKswECllPFTS24HmDXEmG5pgeZVFBFWjVPgCOHAbj4KijQ46Zg9l1Hy9h4hqwIBBACVTBHHOtvYtTB8w5dSaAHozrLaBK5RLI/iTtiR23O3zLjGn9NM+q0v/AOHa8+eIBXmIB00XQ/BTgoZ4KySaVIrkyAg8BSnTRKfS1XDJsJQTNh6ktdqSpQoCkXatuNTA/izHLztaOY4thpWpl0CoPwuOoXrVTV0rTORhAAJ7AAB8LI+Dd1s/Dm6i8u1mmpbTwxNFlZo5LlBH1VVqZsqMxyihJwFgBUZZs7Kq1DBe9oKgGtAaetRgHnOFc4RVw4TOqHctIBVVaBOfEg55WWmJUroaGB8MSNvys7lNbvcahxDk6R4Qc5OtSVgdeMSY4WGaDBtSkqR4pg7j8b0Z/G2wIaLHuz+XRt0H1u2M0leIvm6bk/00+FSMY4cpxZzmgPNyfqW9mtPDBdIpmP3jPt3vftzbONKz+7VP/LeAetiWbU1Qk/D2bXpqePtnQf8A+v3KTXnPbJp/+W2MzE5pQRgD0jH2R1xjf5RiONSj6a/+W9h3OFBnuwf3qjn62vePzB220r/8M/jVF4LXXOWs+ij8r0tvHu1HUbfKvlJfLX/kiXGeLezAUGcdn3hH+FRjGnlGJnKokdlNj8SR9V6808IMxRoeoDfXf0BcaI8eKop5og+uobwKiqd2qfVbzJ+sC3X2NugPZnu52/wkYRTNO/In1eQ/9WMmvJqx3rMPKkPxN65amHX/AE6C+VNb3lTmVBP/ALyn6GiPwa8EaVQ7GofM22TfrHuEcGKw20aimZrmTUesmuFIJMaExr8G/e2MzS5BI8VbEHySmB9V6j6Wg20+i3sK/O6a+FcQjTkf1Rx/dpi8f9GbjP8AcL+3K5+cubu8kGYyOXfQjM7HM1MwrqxNK8hiTHE8uUOigDUAAAEg6V7fU4j5ZQGEwSA9MgY90ZLtltnfK1dqmU/CAB2XLzauuJxjd37qwoOe/E5575Z3ynRVM4+MybHRxWbANQ+lMH1s5eS4lNduFJfVx+ViQOguEUUP+ofRP62X4upsPCEWuSLXWmp400NKa4PJZuadmDfpIXMBAeJmw4sMYctxbsEWXcjaIXS1KMauzM7Djq1NPqxKt0NuO0c8cqEvULnjdom7UgFphBuPZfASt/DMuhxJeNZRVeOORN+GV82uxg5i4Us8Ucd0ztlf5d0iHNnkIQ0/hUk4G7okw7q6EMDTtFCKdh48MS0aRqVEHAMGbyH9b4jlDqFw1agRHPEqVXzOX1X5kD+FrP8AhTe9j2rbL20uLmS1nmuopnkaFnR44kZY4Vyd6qlnkbzI9cJM5iC5szo7d0gAnhrUHsryOowq+Y6OJrYoCnSNRO7ULpZZGZJ1BiIknIidreFqGJA71JI/jK3XypUo4ZGruVmWQhiViYzVtLKTAiMjnaJGxGEJ7moVDZGDvHUbZdb0pvFvhpP/AIhPIf8A07KT/rkXGUq8YOrSt61H/UMYkcsx5/0Av71VB9U3tTh8MdkI8o/Gb+gHm1HhoP8Ajc/VSvAfTMZOdZj5sfwi9XXxj4e7d0k/htYl/wAUpxlvWTklfVQf8TNjEnlmMG4oj/4v/wCm9n9Gw33an95H1Rf0AY5n90Ux5isf+kXgDicU29WfafrN6fJ422RQStpujnlma2j/AOlsZs19QKI4lU01JhtRr5ZYa09TXGNHKsUctdAerN9Si9cuGw8trp6hPh/WxBy/ampE+V7441wJJpgdlN/+qoLwLVK5iHjr4KfwhZ9tvcv6w7BTSPa5T5yX6D/DGMIImlbgtfSg/wAKjGXXklc710HlSc/iL1gXCptRp+st9ZN7d+aaftr7KS/W7Xh4rH/Ub0gfVbff/rAa4tLiK2tI7N3jydZLl5pQhNGjjB0DSDu5uIFeWFBetm/knXjpIa+uM5h+SOKqS5qgn3e60j1M7DiOO16fvqa+6KYI2gbeV63Fc4p90xaqPANWkNTktwyUST0nIHO8f3bknUXM757+d0MkrjMF++lOVAOC+np9uuDtlZuXMpHeJOVaeyOHDlpoOwY6qLhaMDeN+JPX8rHdzV37PU36tWqY2uXbicgNlHBR+Nyqop5DqfZYoR3RVQYhnAoxycSOepp8NMMp29zypiVcU3E/7Odwx23GcOvQzxzyuXPpa0ttd19gfCMfbhnWwZePDE7YtuDMLHIFwrhwNwLnE2tPaXjilQvnmUf4RhqayiVK6t8MS9+25LG4CG4QPabiNJYgACyJXjJ9gtdstoklnsLN5c8t3NGvEtpNMI1AJ19kVwdj3SLb9/tLsRRlbDoiLMwAMtvbnplm4UM5DHiTwwRVxBpYLE1zI7unUbPfwpP12PzLD1P5TVpKx1VI1MFmA1RS0L2KI6WJ3Q76kkgyVmOhPpwsnBd3iOZ0gzCmkxLGMlU5T1bb1vSN2ob69l6saW8EvSM8rCOFFgAjoXPPu6KtW8sZLvHiTcN8lIvHaVgTXuiOFCdT04aKoNeLMBryOMg9I69O8BVGWZIAGQGZMzkL0mD5TJNYNGvPUxlmk8WGQHYt7/BvTwuCoBxpJp95oGbeMlp4QM/eYgdt5bHc9pUgaFCnqIyLGdIgQIVpZyOr+y2rdvHNnaRyLthSaQVAvbiM5M4//a2+pY9jyV7aDGfdMs9Y48zHQcW+3U+4BfLCnC8prVHUOrDjpEa4/aOap8T5XqqZTCjQDqPFoA9gFu8ZzamtFnaqlNcwBJ8R6ZQ9TyWF6k3iapqYpu8cnsEz/Hpdk1/dbjM1zeTySuSzF5jV2PGg+ACqOGJ9ptJdlecVYHRBw9DTT3DHMBg6eApsVCpMZCfiTmSTub49UvkNu3e78xxzY91HiKpqjVA36BclAGwuNUC+fwuLb7IjgOZW73eplXTNrTU4cYLBSoOWpPL9GKvUOe2/43Sb6lMCM+FyRa/HsdvT25Cf6f0Yb7fYb64I6FlcSekT/aRTHC563a+hR63W1RdmjVgaSNQ8zp9QGNNsfBO93IGaxMP5nZF+K1OOCIjrdSvS+nVIPTa7a142mW1mgWpFGw73fgjcbXvToEjHGSOsg+A1HvxJcmGo982kuqefHyuOLgx2MGEpd4tJ6vXQNu08bUFkePQ6jsOG2HwzZsAWnklH5aD/AFxHE22TlSfaYn4WRMXlK/zZUGVOio85NqoRZNYzkbsOHiHYdth4W4cjm5LYU5jfO3q8voL9mfO9ZkdsrwdX5k5hU2YJ+6ItKV5K5XQk9oFfsxosUEUQ7kSL6KMItJbbO9EtGmnuqB6XuywX3svO/nL8xxdb/Mqu3qbS4LO7mA/28ki9uUj7aYeK150xnhhKjmVptPlekAjhf0GpjcNS/wAytTHmwv5uzlzmx9bVE8O3h1XLEOyRv3CuGsRueALegrhGnLsQ+6geZt7qUbmL3dbn/L6W1XV2KLwQp1GPhBbyBNryeGVf+bMAfyKf34Z1s52H8sr5sQv24VLyh/tP7BbE16Y+1Plneuq/NuHH+XSYntI/C8ymAxDj/KK9rQv12Bi8NbcntCSU+bUHwGD5gij/AJt1bx/1Zj9WBU5bSXclrI7/AO6jt6Rbir804h/8tFT0/O1g5fH+ZXop66j8LgRbfaQU6dvEKdozH68S3v8AY7bV7maY9kahR8Tiq4SguyC+F8Q2yog7TNzVOdY+r/qsPI31MPy6n71WvWPRF0j2m+onKUoMtPw0FPhiFJ4v2e2/l2iuRzmkLfUNMXakkRAjpFwMKh96vH7oi4kxuI1Sajz11EWdSOGX/LwWrtqsT8NrZbLeLmMhWBlXz1PxwmT/AKyJlFLdIYR/6ca1+JriGvgaZzU6D8L6adLiXfzJsrBc7xCkLUXvR1+18N76uIxP2Fo0R+wgn23qtvL8ygPTdK8nUj7cYw3jzdbiVfvpDrpVjp6AaYWVKRQwYPaDZeKCCk2lFFv6NYVkDAMOxgQbVYJq7V01VWafZ7L03ffC1juKM2dLeX8VR9Y54za43W+ue9NdSCvKpAwlxfLqGIzMI/3hvdX1bl4t2GJygm5fo5AlmIsJvdlJYXEkBZXynRl4MO0dnpi64AnVjXOfxH9OE9Sg2HfS2fRhsbMq1A/hMN52PUWL6dIO82usxZqc8WdaOKVg44aVwLTpmowVRJO1k4CouEramEi4jlmb7VXvEZRlIvsTSbc8c0TlZVOYEcsUXLCXgc2Cm5ccCtKsxz1CRbHEYmjzBQq5QMvO4VxCuxRDmBvYtDDPhCT70m777crm/k+akkPWFO8NDpiDEdNcDcwwxemmIp8Bwtpy+mKuFNNuEi56GJJqNTc+IG1vMHNHEpUXjF/SXjXLVkardp54hzrRtDjKVSzwTnZeLoHDVmQ7TlbuZuKjUFamrjiL23q/PjOxp5YXLLdMzBQdBgg+K/EEXuwn0bJRZfhcZ2WurOOZCjoCDiXDdxNFRgKnniF6dzZXynVO8+ljvRcPKnLpaTf+FjkkFq2TNU0w+dG1WFpWkAoOZwEaXjDHOLN0LFmwjDwnQfha416wcLp9byS28OX0L95Rx441H5ITRB0GYNqKYGLC5e6nO2VKiy7kWIMVpaCYtItdpNQJag4eU2aZ06nTOUc8Qg9LnFHjFssrWPzCmraNQm12LZoNOIw3RWUNsuWehDDQ9mKKTcwQDezXYC1L4mpWM05lTnYa0s/lqDLQfipgiLtbdmiYBkPsnFRPG7TGVnO6sDBz6WMaBqgODpbiLJS/JJYmJgkrOvGg0rgHKaGqnQ4uQpWDnNx2AaVbE1yWEKOB422QZZjO0He7Q2V4yD2DqvkOzBjxDGk08JbSg1OFWIoCk2WQNz40aio7byHNMJ9FrwPdbMflbP5gClqQ87B2ylcrlCSToMWz30akJDwUccQYTDCu8sYRd+27VagRNFPLqbR004m+u42WydvtdtE/XnfPrmVTywHF08hoWJrifE49lHdUPCAIkWAk8b6YFwmTZu53AMxWMAL5YCCXKaA+/HDJMsZPbdapnK7l5um1sdrcW8cTO7nMozHFO12UV3CwnHckB1rl4eeO0/1nCLmTZXK6RR++IiNpuVQON3oqCpnjajutxLuV31iCwzZAB2HDS9lttnJ/to9fzMWFffjTYPDpg8OoyGUsbzXNecVKo7lG8yLEdi7H4WSVQHwixG3eFhMge7NFqCI+Z9cH4pGdgOJOgwZzb5jSgGp0M3+90vJshY9SbpTocW9lyqbJbdawwZYbaFU8wBXBzaoorSPqSUzUqSeWKYjE4vGv4nYzZ+GoLTyiWNyKABkL8L+3q+t/DmxT3DtmndCqCupY6ADCrvscviG/CvWO0h4a+0e3E3KuW06jKvvMxEk8BxtgldOV0S2Rqvw6C/O+kE3VvF5Xmdvtm4b5cv0IZJpJHJY8qk82OmNctrq02GEdJFGUaAAZmONA9ahgqYDMFUCAOOXZeQT6RzCrqZjE5knIWKFaodpNmCFvN918B7vs1p83crGFH0QxLfZhu3Ibz4okrM/Rg+jGSaepHbjU0OaUK9UU1DgnYkZWpXHYHlw97vKnE/lYxoMATllZEM/YOl5W0L8lY+440W88H3Frb9YTwvl1K8D9pxozaLDc9o4l9OhhPGw4NlmiQJvMgk0Z9g68QRhknt1YkEYcHzuljqSOFyGwJe4oqqvAk95UY+mZqmnlgmbPXQ4kWu6T4m7Iul1NNGjwieM32LhBr1Vor5e2nTX7BXBRbMUBJxVz3hl9bebN9UxfbsFCiAFHoPyv1r8sErVzuxr+ZjxwwzWSZK9mLipA2+NxxdCl3NrnyhygVAXhg2lqjVXt4Y7qgzEm/XyJEbC/RYiPbomr3zUdij95wXS2VCG7DqMW76p0Ue03W+d2nVvhfbFPYolCCxHuwy/JwlaU0I0/v5Y73j9ns/rdc75oTt9v9LvAtdFoaVUZvXBlY+mxTh2Y7JO9+upHS+2CKFGrQgjBt4FfiMe4X66gwR2X2wZhHE1Nda6fowbjtkPdpqOH6MdDHs9l8vhi+2C+XStSD8cMHykRHD/vi2txsfgLrfNKncXbKwHy6jgv1nB1YEFVK47rf7x+H5X66wv3R8fzvthVhPIfbg10VU8MeMnck9hv1822AF9sVJHKRQ5j6kn7cGFVTxGKCmo4D2Rd76WY8T7ZvlhRA/4fqGDvTXsGK6R0vt91N1v1hRBL2HBvIOzHNC9B7L7fNTdT7b7YZbeQ6HBYpjkDoPZfb5J6m+2N+UdTwwUUV0bHr9F+vwNwY7ZjocEBpocVIu8XYXza67e1yP3sSU1oOfI9vliM3Yi7gZ3UG5YHZwxxDJkNDw545F2u03Wb7MZWrD3jF55MOGK3a+3y6UOfhxHI8xj146d9NOZH78ei/Dpfpvhv5TkNU94xXXM3Z+nHYm/X7ba+X5eQLdrUaH7MWK1D5/bjkRfb6c75Nr09jlb7xMxGGNlWUUYDyPZ6455SPK+7Xz+M77la0tijcIV/s4PdJo2pl+GvwxzPqfabsM756D2C+TFhhY9kS/2R+jDLFbSy+zDIfRD+jFbkFCo2yMfS+3RsTRT3qiL/AIha58pIv0fqGG9NjvZuEDD1oMRgWSuCxDfYI87vnYdTm+Bp+9XX0ztVjgc8jhxTwnesas0UfvrgbTbBOV1zvAsybS1fmbl9PZi1qy2ch4e/DxB4TCkGS5/srhfbVeTk+81u7zNT5vpD3Kc9ptWgt1hFRxw9R+G7Icc7+pphVbpeVUV3k+t6eIvG1PmzEv8A5aovpaZx0P8Ap7saNtuz7VbTiVrVZTSmRzVfWh0rhLbbE8tWJp5Xsry3LfmWoz6MTnOxyyvOkgkY0RWfyClj9QOP0HtsW3PGGt4IE7VCKCPqwpvrIUMEQb1NxLVFVQytqU7EXgj+H90njzw2dxpqaxsB8TTH6IlgSWNkIFDjl8uU3Ff5Iv8AZ902pwbu0lyMx6bLUDNyUOoahr9E978OP0dd+GpeoelqpOJxXhSjBWXaGHD8R2XDfO5DMGEg/smDPW7Xgmz+Adz3Skt3/sYTqFdaytXsi5fxSEHyx+ibDw3HFRpu8ezErVywhcvgPQXFfBSC7mT2fib9eZ7N+q63egDzFeZoBX30rjaESGBcq5VAx7fcyb9dtXZdc+lqW2/q32GyAMlv13/9RiR8OGGxrmFeLjHr5qAvuo34IelxbfZdttQBDZ26U7I1r8aYsfc7dPpY9de8UX4sbsKTXJCBdFAHoAMCpfEVpFxZPe2L3H3ouk3L3BstTC1P4wtkrlcf0iuL3Eax4C4rnGHHG2Xp1FMtR2HCPP40Y+wJG99MTAHhY5dzxuCbKFJBws3uXhWG4JltmW1m48fu3P5l/eMKU3iq7fgAvqScNMNzCrQybxp0JzHkbVSx42h5hyTC46WA7ur99Rkf3hxvQaVHC6xf28MssFzII5YiVIAzVI7MZ3um4T3W4XDlzUueGmNYtUVUV0zB6mItfg2ZMMom/mVfBnCVnpVjpK7ECZ8r0PNkSrjnkAx+V6DJv22x83f1IUYy0yuSakn1wx8XVR8bGknc3nQtL7tR/hbPTBIVfheiTeMbWL+XFEPNu8cZ15nExI41GPllcE9LBRWHuYemO1vF9dn6IzbLst1n8dXLew+X+BQuEquJP0h9knzNxGxx9KP+oE/cAFkARbBceKr6atXc+rE4GWe23F4e6tB2nEvegbKBa3Gc0w2CEu4noDYxw5b36jt5k22wnK8Rizkulep/K+pN2vJeLkemGKw8KRP/ADSz9oHDDE1WPG8difmuoxIoIAOptYmGpj7M+d67D/L1GmP1CWPn+VqxklfVnY+/DleWew2UOUx/ejjU41heet4n+fY5xOu82lGBsBeu/luDTLu1tLwYaPb5a0TJ6Y2l45PmLGIfENV5UAXpW5XhH2UL5WGrgxLsReIyQSVH5sa+0OE+ZadQhatMqeovPDa2+I5GQs0n9DcXaQj3S5zoNcd7RYvJc5WdU1pxwz5gWWiY4mxeY8zoimAvinO6ciSnUxY1nJRN+5ZhKlGqWbLhZO/lF01F7qjQYcLXwRDLBnaYliKih0wGtDUPGfSxBj6rZgKBb3F1VrNAHhG3bcMWjcEyVNMSd9sZdoYgEPQ4JqYFGHhyN8o40tus3E1JTtlfqpZbX92t8tJF58cRrreHkUxMgGBKlBqZzHrZtXGiohXuwJ43EyFbihi0lyR0uEkrIeOI0jn3YAVmQypg3dVu8TfDc4TK/DQ4GiSmtcNuV8x7vwVMp42rK2BzDBfSAGX3hZty7jNlDUNO3HMk7zQZBhlzbRWYOgJjjYQxThO7bMdbFwNJ6NPS8T0mytAJm2u1lMVMVpgo53296pi/Czg3ZIlGZqUwCuv5eISsXd9rl7xVEmx63uHyvzePEkt0OjExCV1IOF4+03rgWpVjIXC/vG/NXWpOnbrYmH9w+d6/4W31X25FoGKqAcLvg7/yhwaj5XGnui5auFGI0uD52RQ/y/W9A/bh6DQ5RrgJ9LE3e5Rcdg/ywd6Kk7Wy4XdNM0i6mtMVcjjpN8O1x06SochvdxvdE33kZ7Rjz6De/HJvlyKIPnfeIuL88kMZMjUA7cC90/8ALv78eJi61PdN1qutJS7GALH5n/7d7BbnfSblckRnu8BiJY/zx64BrVNbfVcZ95fO8tzPFnF1zp90ZCwx75877udsuLeLqHUYObr/AOR92L6Iu7bC+NSKibnqe7a0kuUeeKRiArdjY0wL4bmwZpWCjXFm2/zh6HELiL7U2vq5m+0vess1+0cKwx1UD7cQpPaPqccOKfuu6XLqbg43KakCBlcbb3ekhOpxWvs4iZbsd7sDfBtZ/Z4qt1WGnLEjav5AxymnG5Kfu3Mg431NrI3d9CkLAtVjoFGA1/7Q9cEUnpUVNRs2HurYtX3fW7bXxtr66xpr3RiqX2B6YrUZqz95VOXS+P7l83vo2vgumatM7cueK4/bGLmtVrDuqPgXrtfsHufK/Xwb3J6W63IpbR5fzNhj2n2BiWjhsHSOrEOXPQXBiPeN38R2FyLtaZeeGPEToZCWkpyViNPTGn//AMO/ph/hcdy9YVE0DrpFosPtcJV7mN4TcwSQOUkUo44htCCMEfEX/n5fU42aMrgFSCOy4MD/AJC2Mb6+9hqaE9mvxx7yb0wTfrrfr7iNUI/vrjyDg3u+3HL7fRfLsoCBj4fvOOX67X64TKUYjsNRiyf+Z7sdv11N9N8trr2/bj76A9cev18v1ybR86lDxXUY4sf559DjxF+N9W+C+rqKtJB6HF1x/Jb1GOC/X0303C4ivx/Tj5fZbHb9fL51vnWtRxGOuf8Afsx6/X6/XboQGHA8fLHyfyffj1+432/cL5lT6Q/v547f2D6Y9fr8b9dPtCuPk4HHr7xvl+vylcejjjl+v1+v1Tj7mcev1+v3G7KVx0vAY9fLtfhtfmXHeO36+X66SPjjrmcdvxvl+v5QHHnj2D2sc2vxvu9+W/UUk5aE9lATriRbfz19cdv18vvG5cG0392Pu7WdmHMRNRh8OONB8O/R9Bjm18v1+NrNj4Q3+QaWL5TxzlR+/Gz2Psj0x4i+30G6G8auPCm4Ws3SlVYiRUZjWo7PPD/4p/8AOw/wnBGGwVTFCVIythyb3X87D5hzbD8uIFXVntG3ttD83f6PlefL4SNavOAOxRhobFE5M32n9luhctb5ww6+5SJ87xTWDj8LWg9t5H99MHlwsXk9Ibkm2RvUv84Vm9ymovL07Gx7Ht8X+SG/i1wRbAa8tw6/ZmzLeVvmbHvs+nytK10JbW0dMsMYpw7oxYcQrhaS7KLmsurznG1Peqt7Ta9r9zqPZUD0AxxiopAcBclzvjarbu3tsW7OpXHA44ppu9y96W3Juguwa4+Tjit+ba+5m7JvfYU4sPDFTF0N3Cv0ue+KqvFgPfiNPjpN8F1VD1i7m7zdwJxlGAk/HHPS7X0AD7XsuttdpvtpaxmVJ26qsAV+iyeeE9fYf3fbhXj8MWltKgATPGbMxf8AlP5G9RyHmCIBSaoxZmA0kZR1nrajlH/uqP74vVh4itjEr5lFRXU4Sx/5WP8AhGMy1QA3E/vG/oQok3OnujytnuPFcCcHB9NcIs3E4v3lxi4hRuU2zT+MTwVXP1YUWxcub5dBTUXaz0viq5euVQPU1wv4rJN+F90qL6bJTb9fSf5mX0GBpxy+37Lpfrve8uJPalc+84ox6L7fr9wv1nJ4knHOOX2/Xy/c2PMcv19v1/E485Y7fr5fr8LY5PP0x0X2+G/Ha02Z/wDczn85xXN/Pn/8Rvtw6wy/oJdsN/kp5XkuYP8A95V9lx8x/wDeVv3r+z5cVHEmmbtcIqadrjN9F8xxyntr64rkovlT3G8jfSS7dpvtH/MT94fXcuNVi7zat2csey8MKMbzCrVY0MKJPFuAsbAf+7q24wfL6dFRVrkTuAbJxf8AkDyu4bzNDohp6cMC2xxPlr6SdeKqkk8BeiG1x1Oeij4aCTHHhaI7nzs5D4s3CD2WFMAcJf8A0xgQIGq3VuB8x4nii/G0xstJu7XsmaVSWbswNt/5yeuM3X+WKagtTq6Y63oMR/lP5XoKPPu9YB6e/S0mG/zqf71nUEMKdWStRqFxTffyhjCvhWo1CpIYDiLKxPvt53sEqoy6swehsdfd9Lovt6uJhlQ9JOxeOBkmBlRRsL6t3fEM22QuK+45pc1Vdge2pxXDzx1sr9UvoJvq2cg8bbtYR9GOcuKUGbWnvwsy/wAz34sizmRd092798y5XE29y9w37cLxy08uauB1xwxIoHDK+U7szsd741+G7ze2PfiI2L6Dcgus3W54KyCgxXa4hOXZfal3Gd8W+HQpi244Y6DN1Te+EXZtrrSQqcVjHWWbtdAYvl//2Q=="}
hudUi.moreWorldArt=function(route)
  if route.artSprite~=nil then return route.artSprite end
  local encoded=hudUi.moreWorldJpg[route.key]
  if encoded==nil or encoded=="" then return nil end
  local texture=UnityEngine.Texture2D(2,2,UnityEngine.TextureFormat.RGB24,false)
  texture.name="Geocore_MoreWorld_"..route.key.."_640x360"
  local bytes=CS.System.Convert.FromBase64String(encoded)
  local loaded=false
  pcall(function()loaded=UnityEngine.ImageConversion.LoadImage(texture,bytes,true)==true end)
  if not loaded then pcall(function()loaded=UnityEngine.ImageConversion.LoadImage(texture,bytes)==true end)end
  if not loaded then pcall(function()loaded=texture:LoadImage(bytes)==true end)end
  if not loaded then UnityEngine.Object.Destroy(texture);return nil end
  texture.filterMode,texture.wrapMode=UnityEngine.FilterMode.Bilinear,UnityEngine.TextureWrapMode.Clamp
  local sprite=UnityEngine.Sprite.Create(texture,UnityEngine.Rect(0,0,texture.width,texture.height),Vector2(.5,.5),100)
  sprite.name="Geocore_MoreWorldSprite_"..route.key
  route.artTexture,route.artSprite=texture,sprite
  return sprite
end
hudUi.closeMore=function()
  local m=hudUi.more;m.open=false
  if m.root then m.root:SetActive(false)end
  if hudUi.updateSponsorPrompt then hudUi.updateSponsorPrompt()end
  return true
end
hudUi.moreService=function(request)
  local m=hudUi.more
  request.fallback=true
  local available,result=false,nil
  local ok,err=pcall(function()
    local service=DouyinWorldService or CS.DouyinWorldService
    if service and service.Teleport then
      available=true;result=service.Teleport(request.route.id,"geocore_more_worlds")
    end
  end)
  if not ok or not available or result==false then
    m.busy=false;m.pending=nil;m.diagnostic="service_unavailable:"..tostring(err or result)
    if m.status then m.status.text="暂时无法跳转，请稍后重试" end
    return false
  end
  m.diagnostic="service_teleport_invoked:"..request.route.id
  request.deadline=tonumber(Time.unscaledTime)+10
  return true
end
hudUi.moreEnsurePortal=function(route)
  if route.component then return route.component end
  local host=GameObject("Geocore_WorldTarget_"..route.key)
  host:SetActive(false);host.transform:SetParent(self.transform,false)
  route.host=host;route.readyAt=tonumber(Time.unscaledTime)+.15
  local ok,err=pcall(function()
    route.component=host:AddComponent(typeof(CS.DouyinPortal))
    route.component.WorldID=route.id
    route.component.InteractionRange=2;route.component.IsPermanent=true
    pcall(function()route.component.PortalMesh=nil;route.component.PortalNameText=nil;route.component.MinNameLabDis=0;route.component.MaxNameLabDis=0 end)
    pcall(function()
      route.component.onSetWorldID=function()route.readyAt=tonumber(Time.unscaledTime)end
      route.component.onEnterPortalSuccess=function()
        local m=hudUi.more
        if m.pending and m.pending.route==route then
          m.pending=nil;m.busy=false;m.diagnostic="success:"..route.id
          if m.status then m.status.text="正在进入"..route.name end
        end
      end
    end)
    host:SetActive(true)
    pcall(function()route.component:SetWorldID(route.id)end)
  end)
  if not ok then route.component=nil;hudUi.more.diagnostic="component_unavailable:"..tostring(err)end
  return route.component
end
hudUi.moreChoose=function(index)
  local m=hudUi.more;local route=m.routes[index]
  if not route or m.busy then return false end
  m.busy=true;m.status.text="正在连接"..route.name.."…"
  m.pending={route=route,dispatchFrame=(tonumber(Time.frameCount)or 0)+1}
  m.diagnostic="queued:"..route.id
  return true
end
hudUi.moreTick=function()
  local m=hudUi.more;local request=m.pending
  for _,route in ipairs(m.routes)do if route.button then route.button.interactable=not m.busy end end
  if not request then return end
  local now=tonumber(Time.unscaledTime)
  if not request.started and (tonumber(Time.frameCount)or 0)>=request.dispatchFrame then
    local component=hudUi.moreEnsurePortal(request.route)
    if component and now<(request.route.readyAt or 0)then return end
    request.started=true;request.deadline=now+10
    -- Publish pending state before invoking: the success callback may be synchronous.
    local ok,result=pcall(function()if not component then return false end;return component:EnterPortal()end)
    if m.pending~=request then return end
    if not ok or result==false then hudUi.moreService(request)
    else m.diagnostic="enter_invoked:"..request.route.id end
  elseif request.started and now>=request.deadline then
    if not request.fallback then hudUi.moreService(request)
    else m.pending=nil;m.busy=false;m.status.text="连接超时，请重试";m.diagnostic="timeout:"..request.route.id end
  end
end
hudUi.openMore=function()
  local m=hudUi.more
  if not m.root then return false end
  if resultsRoot and resultsRoot.activeSelf then return false end
  if hudUi.closeCommerce then hudUi.closeCommerce()end
  hudUi.closeCheckIn()
  m.open=true;m.root:SetActive(true);m.root.transform:SetAsLastSibling()
  m.showDiagnostics=false
  lastLayoutKey=""
  m.busy=false;m.pending=nil
  m.status.text="同系列赛道展示"
  if sponsorPromptRoot then sponsorPromptRoot:SetActive(false)end
  return true
end
hudUi.createMoreUi=function(safe)
  local m=hudUi.more
  local button,rect,core=addCommerceButton(safe,"HUD_More",Color(.61,.82,.97,.8),hudUi.openMore)
  m.buttonRoot,m.buttonRect=button,rect
  local icon,iconRect=addRoot(core,"MoreIcon",false);m.iconRect=iconRect
  for i=1,3 do addImage(icon,"Dot"..i,Vector2((i-1)/3+.04,.42),Vector2((i-1)/3+.23,.61),Vector2.zero,Vector2.zero,Color(.79,.90,1,1),roundSprite(),false,false)end
  m.label=addText(core,"MoreLabel",Vector2.zero,Vector2.zero,18,UnityEngine.TextAnchor.MiddleLeft);m.label.text="更多"
  local overlay,overlayRect=addRoot(safe,"HUD_MoreOverlay",true);m.root=overlay
  overlayRect.anchorMin,overlayRect.anchorMax=Vector2.zero,Vector2.one;overlayRect.offsetMin,overlayRect.offsetMax=Vector2.zero,Vector2.zero
  local _,panelRect,panel=addGlass(overlay,"HUD_MorePanel",false,Color(.62,.81,.98,.8));m.panelRect=panelRect
  m.eyebrow=addText(panel,"MoreEyebrow",Vector2.zero,Vector2.zero,11,UnityEngine.TextAnchor.MiddleLeft);m.eyebrow.text="RACING UNIVERSE";m.eyebrow.color=Color(1,.76,.36,1)
  m.title=addText(panel,"MoreTitle",Vector2.zero,Vector2.zero,26,UnityEngine.TextAnchor.MiddleLeft);m.title.text="更多飞车世界"
  m.status=addText(panel,"MoreStatus",Vector2.zero,Vector2.zero,14,UnityEngine.TextAnchor.MiddleLeft);m.status.color=Color(.70,.78,.88,1)
  local _,diagnosticRect,diagnosticCore=addCommerceButton(panel,"StorageDiagnostics",Color(.62,.75,.88,.5),function()
    m.showDiagnostics=not m.showDiagnostics
    m.nextDiagnosticAt=0;lastLayoutKey=""
  end)
  m.diagnosticRect=diagnosticRect
  m.diagnosticLabel=addText(diagnosticCore,"DiagnosticLabel",Vector2.zero,Vector2.one,12,UnityEngine.TextAnchor.MiddleCenter)
  m.diagnosticLabel.text="数据诊断"
  m.diagnosticText=addText(panel,"StorageDiagnosticText",Vector2.zero,Vector2.zero,11,UnityEngine.TextAnchor.UpperLeft)
  m.diagnosticText.horizontalOverflow=UnityEngine.HorizontalWrapMode.Wrap
  m.diagnosticText.verticalOverflow=UnityEngine.VerticalWrapMode.Truncate
  local _,closeRect,closeCore=addCommerceButton(panel,"MoreClose",Color(.62,.75,.88,.5),hudUi.closeMore);m.closeRect=closeRect
  addIconBar(closeCore,"CrossA",Vector2(.30,.48),Vector2(.70,.52),Color(.98,.99,1,1),45)
  addIconBar(closeCore,"CrossB",Vector2(.30,.48),Vector2(.70,.52),Color(.98,.99,1,1),-45)
  for i,route in ipairs(m.routes)do
    local index=i
    local card,cardRect,cardCore=addGlass(panel,"MoreCard_"..route.key,false,route.color);route.rect=cardRect
    local art,artRect,artImage=addImage(cardCore,"WorldArtwork",Vector2.zero,Vector2.zero,Vector2.zero,Vector2.zero,Color.white,hudUi.moreWorldArt(route),false,false)
    route.artRoot,route.artRect,route.artImage=art,artRect,artImage
    artImage.preserveAspect=false
    local shade,shadeRect=addImage(cardCore,"WorldArtworkShade",Vector2.zero,Vector2.zero,Vector2.zero,Vector2.zero,Color(0.01,.02,.04,.26),nil,false,false)
    route.artShade,route.artShadeRect=shade,shadeRect
    route.title=addText(cardCore,"WorldName",Vector2.zero,Vector2.zero,22,UnityEngine.TextAnchor.MiddleLeft);route.title.text=route.name
    route.subtitleText=addText(cardCore,"WorldDescription",Vector2.zero,Vector2.zero,14,UnityEngine.TextAnchor.MiddleLeft);route.subtitleText.text=route.subtitle;route.subtitleText.color=Color(.77,.85,.94,1)
    route.badge=nil
    route.button=nil;route.actionRect=nil;route.actionLabel=nil
  end
  overlay:SetActive(false)
end
hudUi.layoutMore=function(portrait)
  local m=hudUi.more;if not m.panelRect then return end
  local f=hudUi.astraFrame
  local width=math.min(portrait and 460 or 700,f.width-24)
  local height=portrait and 430 or 276
  local function place(rect,x,y,w,h) setRect(rect,Vector2(0,1),Vector2(0,1),Vector2(x,-y),Vector2(w,h))end
  setRect(m.panelRect,Vector2(.5,1),Vector2(.5,1),Vector2(0,-math.max(f.modalTop,(f.height-height)/2)),Vector2(width,height))
  place(m.title.rectTransform,20,14,width-88,38)
  place(m.status.rectTransform,20,58,width-40,26)
  setRect(m.closeRect,Vector2(1,1),Vector2(1,1),Vector2(-12,-12),Vector2(44,44))
  local cardWidth=portrait and width-32 or (width-48)/2
  local cardHeight=portrait and 150 or 156
  for i,route in ipairs(m.routes)do
    place(route.rect,16+(portrait and 0 or (i-1)*(cardWidth+16)),98+(portrait and (i-1)*162 or 0),cardWidth,cardHeight)
    place(route.title.rectTransform,16,12,cardWidth-32,32)
    place(route.subtitleText.rectTransform,16,48,cardWidth-32,24)
    place(route.actionRect,12,92,cardWidth-24,46)
  end
end
hudUi.createCheckInUi=function(safe)
  local activity,activityRect,activityCore=addCommerceButton(safe,"HUD_Activity",Color(0.94,0.76,0.43,0.8),function() hudUi.openCheckIn() end)
  hudUi.activityRoot,hudUi.activityRect=activity,activityRect
  local calendar,calendarRect=addRoot(activityCore,"ActivityCalendar",false)
  hudUi.activityIconRect=calendarRect
  setRect(calendarRect,Vector2(0,0.5),Vector2(0,0.5),Vector2(12,0),Vector2(20,20))
  addIconBar(calendar,"CalendarTop",Vector2(.08,.70),Vector2(.92,.79),Color(.94,.76,.43,1),0)
  addIconBar(calendar,"CalendarLeft",Vector2(.08,.12),Vector2(.16,.79),Color(.94,.76,.43,1),0)
  addIconBar(calendar,"CalendarRight",Vector2(.84,.12),Vector2(.92,.79),Color(.94,.76,.43,1),0)
  addIconBar(calendar,"CalendarBottom",Vector2(.08,.12),Vector2(.92,.20),Color(.94,.76,.43,1),0)
  local seven=addText(calendar,"CalendarSeven",Vector2(.18,.15),Vector2(.82,.72),12,UnityEngine.TextAnchor.MiddleCenter);seven.text="7";seven.color=Color(.94,.76,.43,1)
  local label=addText(activityCore,"ActivityLabel",Vector2.zero,Vector2.zero,18,UnityEngine.TextAnchor.MiddleLeft);label.text="活动"
  hudUi.activityLabelRect=label.rectTransform
  setRect(label.rectTransform,Vector2(0,0.5),Vector2(0,0.5),Vector2(40,0),Vector2(44,30))
  local dot,dotRect=addImage(activityCore,"ActivityClaimDot",Vector2.zero,Vector2.zero,Vector2.zero,Vector2.zero,Color(1,.43,.20,1),roundSprite(),false,false)
  hudUi.activityDot=dot;setRect(dotRect,Vector2(1,1),Vector2(1,1),Vector2(-7,-7),Vector2(7,7));dot:SetActive(false)
  local overlay,overlayRect=addRoot(safe,"HUD_CheckInOverlay",true)
  hudUi.checkInRoot=overlay
  overlayRect.anchorMin,overlayRect.anchorMax=Vector2.zero,Vector2.one;overlayRect.offsetMin,overlayRect.offsetMax=Vector2.zero,Vector2.zero
  addImage(overlay,"CheckInDimmer",Vector2.zero,Vector2.one,Vector2.zero,Vector2.zero,Color(.006,.010,.018,.26),nil,false,false)
  local panel,panelRect,core=addGlass(overlay,"HUD_CheckInPanel",false,Color(.94,.76,.43,.75))
  hudUi.checkInPanelRect=panelRect
  hudUi.checkInTitle=addText(core,"CheckInTitle",Vector2.zero,Vector2.zero,26,UnityEngine.TextAnchor.MiddleLeft);hudUi.checkInTitle.text="七日签到"
  hudUi.checkInSubtitle=addText(core,"CheckInSubtitle",Vector2.zero,Vector2.zero,14,UnityEngine.TextAnchor.MiddleLeft)
  hudUi.checkInSubtitle.text="9月11日起每日解锁 · 9月17日全部开放";hudUi.checkInSubtitle.color=Color(.77,.84,.92,1)
  hudUi.checkInProgress=addText(core,"CheckInProgress",Vector2.zero,Vector2.zero,14,UnityEngine.TextAnchor.MiddleLeft);hudUi.checkInProgress.color=Color(.98,.82,.50,1)
  local _,closeRect,closeCore=addCommerceButton(core,"CheckInClose",Color(.54,.66,.82,.5),hudUi.closeCheckIn)
  hudUi.checkInCloseRect=closeRect
  addIconBar(closeCore,"CloseA",Vector2(.30,.48),Vector2(.70,.52),Color(.97,.98,1,1),45)
  addIconBar(closeCore,"CloseB",Vector2(.30,.48),Vector2(.70,.52),Color(.97,.98,1,1),-45)
  hudUi.checkInScroll=hudUi.astraCreateScroll(core,"CheckInScroll")
  hudUi.checkInRows={}
  for day=1,7 do
    local claimDay=day
    local card,rect,cardCore=addGlass(hudUi.checkInScroll.content,"CheckInDay"..day,false,day==7 and Color(.94,.76,.43,.70) or Color(.43,.60,.77,.38))
    local dayLabel=addText(cardCore,"DayLabel",Vector2.zero,Vector2.zero,14,UnityEngine.TextAnchor.MiddleLeft)
    dayLabel.text="第"..day.."天"..(day==7 and " · 限定称号" or "");dayLabel.color=Color(.83,.89,.96,1)
    local value=addText(cardCore,"RewardValue",Vector2.zero,Vector2.zero,24,UnityEngine.TextAnchor.MiddleLeft)
    value.text=day==1 and "1,000" or day<7 and "500" or "";value.color=Color(1,.86,.56,1)
    local caption=addText(cardCore,"RewardCaption",Vector2.zero,Vector2.zero,13,UnityEngine.TextAnchor.MiddleLeft)
    caption.text=day<7 and "金币" or "永久拥有 · 可在外观中穿戴";caption.color=Color(.73,.82,.92,1)
    local _,actionRect,actionCore,button=addCommerceButton(cardCore,"CheckInClaim"..day,Color(.94,.76,.43,.60),function() hudUi.claimCheckIn(claimDay) end)
    local actionLabel=addText(actionCore,"ClaimLabel",Vector2.zero,Vector2.one,16,UnityEngine.TextAnchor.MiddleCenter);actionLabel.text="同步中"
    local badge=day==7 and hudUi.createVeteranBadge(cardCore,"CheckInVeteranBadge") or nil
    hudUi.checkInRows[day]={root=card,rect=rect,dayLabel=dayLabel,value=value,caption=caption,actionRect=actionRect,button=button,actionLabel=actionLabel,actionCore=actionCore,badge=badge}
  end
  hudUi.checkInFooter=addText(core,"CheckInFooter",Vector2.zero,Vector2.zero,13,UnityEngine.TextAnchor.MiddleLeft)
  hudUi.checkInFooter.color=Color(.76,.84,.94,1)
  local _,retryRect,retryCore=addCommerceButton(core,"CheckInRefresh",Color(.49,.66,.83,.6),function()
    local api=resolveEconomyHolder() and economyHolder.script or nil
    if api and api.GeocoreCheckInRefresh then pcall(api.GeocoreCheckInRefresh) end
    hudUi.refreshCheckIn(true)
  end)
  hudUi.checkInRetryRect=retryRect
  local retryLabel=addText(retryCore,"RefreshLabel",Vector2.zero,Vector2.one,14,UnityEngine.TextAnchor.MiddleCenter);retryLabel.text="刷新"
  overlay:SetActive(false)
end
hudUi.layoutCheckIn=function(portrait)
  local f=hudUi.astraFrame
  if not f or not hudUi.checkInPanelRect then return end
  local function place(rect,x,y,w,h) setRect(rect,Vector2(0,1),Vector2(0,1),Vector2(x,-y),Vector2(w,h)) end
  local width=math.min(portrait and 460 or 900,f.width-24)
  local columns=portrait and 2 or 3
  local inner=width-32;local cardWidth=(inner-(columns-1)*12)/columns
  local cardHeight=152;local coinRows=math.ceil(6/columns)
  local contentHeight=coinRows*(cardHeight+12)+184
  local availableHeight=math.max(1,math.min(f.modalHeight,f.height-f.modalTop-12))
  local tiny=availableHeight<220
  local short=not portrait and f.short and not tiny
  if short then contentHeight=coinRows*(cardHeight+12)+164 end
  hudUi.checkInTiny=tiny
  local top=(tiny or short) and 68 or portrait and 96 or 92
  local footer=tiny and 0 or short and 48 or 62
  local height=math.min(availableHeight,top+contentHeight+footer)
  setRect(hudUi.checkInPanelRect,Vector2(.5,1),Vector2(.5,1),Vector2(0,-(f.modalTop+(availableHeight-height)/2)),Vector2(width,height))
  place(hudUi.checkInTitle.rectTransform,20,12,width-92,34)
  hudUi.checkInTitle.fontSize=12
  place(hudUi.checkInSubtitle.rectTransform,20,short and 40 or 46,width-40,22)
  hudUi.checkInSubtitle.gameObject:SetActive(not tiny)
  place(hudUi.checkInProgress.rectTransform,20,tiny and 44 or 68,width-40,22)
  if short then place(hudUi.checkInProgress.rectTransform,width-336,18,264,22) end
  setRect(hudUi.checkInCloseRect,Vector2(1,1),Vector2(1,1),Vector2(-12,-10),Vector2(44,44))
  hudUi.astraLayoutScroll(hudUi.checkInScroll,16,top,inner,math.max(1,height-top-footer),contentHeight)
  hudUi.checkInScrollable=contentHeight>height-top-footer
  for day,row in ipairs(hudUi.checkInRows or {}) do
    local special=day==7
    local w=special and inner or cardWidth
    place(row.rect,special and 0 or ((day-1)%columns)*(cardWidth+12),special and coinRows*(cardHeight+12) or math.floor((day-1)/columns)*(cardHeight+12),w,special and (short and 164 or 184) or cardHeight)
    place(row.dayLabel.rectTransform,14,8,w-28,24)
    place(row.value.rectTransform,14,36,w-28,34)
    place(row.caption.rectTransform,14,special and (short and 82 or 100) or 71,w-28,22)
    if row.badge then
      local bw=math.min(300,w-28);place(row.badge.rect,(w-bw)/2,short and 32 or 36,bw,short and 48 or 60)
      row.caption.alignment=UnityEngine.TextAnchor.MiddleCenter
    end
    place(row.actionRect,12,special and (short and 108 or 128) or 100,w-24,44)
  end
  place(hudUi.checkInFooter.rectTransform,18,height-(short and 46 or 56),width-112,short and 40 or 46)
  setRect(hudUi.checkInRetryRect,Vector2(1,0),Vector2(1,0),Vector2(-14,short and 4 or 12),Vector2(72,40))
  hudUi.checkInFooter.gameObject:SetActive(not tiny)
  hudUi.checkInRetryRect.gameObject:SetActive(not tiny)
end
hudUi.refreshCheckIn=function(force)
  if not hudUi.checkInRows or (not force and Time.unscaledTime<(hudUi.nextCheckInRefresh or 0)) then return end
  hudUi.nextCheckInRefresh=Time.unscaledTime+.5
  local api=resolveEconomyHolder() and economyHolder.script or nil
  local ok,initialized,unlocked,claimed,pending,nextUnix,firstUnix,serverUnix,lastError,revision=false
  if api and api.GetGeocoreCheckInSnapshot then
    ok,initialized,unlocked,claimed,pending,nextUnix,firstUnix,serverUnix,lastError,revision=pcall(api.GetGeocoreCheckInSnapshot)
  end
  local ready=ok and initialized==true and (tonumber(serverUnix) or 0)>0
  unlocked=math.max(0,math.min(7,math.floor(tonumber(unlocked) or 0)))
  hudUi.checkInSnapshot={initialized=ready,unlocked=unlocked,claimed=tonumber(claimed) or 0,pending=tonumber(pending) or 0,nextUnix=tonumber(nextUnix) or 0,firstUnix=tonumber(firstUnix) or 0,serverUnix=tonumber(serverUnix) or 0,lastError=tostring(lastError or ""),revision=tonumber(revision) or 0}
  local available=0
  for day,row in ipairs(hudUi.checkInRows) do
    local taken=hudUi.checkInHasBit(claimed,day)
    local inFlight=hudUi.checkInHasBit(pending,day)
    local canClaim=ready and day<=unlocked and not taken and not inFlight
    if canClaim then available=available+1 end
    row.button.interactable=canClaim
    row.actionLabel.text=taken and ready and "已领取" or inFlight and "提交中" or canClaim and "领取" or ready and "未解锁" or "暂不可领取"
    row.actionLabel.color=canClaim and Color(.11,.13,.16,1) or Color(.72,.79,.88,1)
    local surface=row.actionCore:GetComponent(typeof(UnityEngine.UI.Image))
    if surface then surface.color=canClaim and Color(.94,.77,.45,1) or Color(.16,.22,.29,.82) end
  end
  hudUi.activityDot:SetActive(available>0)
  hudUi.checkInProgress.text=ready and ("已解锁 "..unlocked.." / 7  ·  "..(available>0 and (available.."份奖励可领取") or claimed==127 and "全部奖励已领取" or "进度已保存")) or tostring(lastError)=="DATASTORE_NOT_OPEN" and "本地存档暂不可用" or "正在读取个人签到进度"
  if not ready then
    hudUi.checkInFooter.text=tostring(lastError)=="DATASTORE_NOT_OPEN" and "本地存档暂不可用，请重进\n北京时间00:00解锁" or "正在准备本地签到进度\n北京时间00:00解锁"
  elseif (tonumber(pending) or 0)>0 then hudUi.checkInFooter.text="奖励提交中，请勿退出\n本地保存后更新金币和外观"
  elseif unlocked>=7 then hudUi.checkInFooter.text="七天奖励已全部解锁\n未领取的奖励会一直保留"
  else
    local seconds=math.max(0,(tonumber(nextUnix) or 0)-(tonumber(serverUnix) or 0))
    hudUi.checkInFooter.text=string.format("下次解锁 %02d:%02d:%02d\n北京时间00:00 · 无需连续登录",math.floor(seconds/3600),math.floor(seconds/60)%60,seconds%60)
  end
  if hudUi.checkInScrollable and not hudUi.checkInTiny then
    hudUi.checkInFooter.text=(not ready and "本地进度就绪后领取" or unlocked>=7 and "未领奖励会一直保留" or string.match(hudUi.checkInFooter.text,"[^\n]+") or "").."\n上下滑动查看全部奖励"
  end
end
hudUi.claimCheckIn=function(day)
  local s=hudUi.checkInSnapshot or {}
  if not s.initialized or day<1 or day>7 or day>s.unlocked or hudUi.checkInHasBit(s.claimed,day) or hudUi.checkInHasBit(s.pending,day) then return false end
  local api=resolveEconomyHolder() and economyHolder.script or nil
  if not api or not api.GeocoreCheckInClaim then return false end
  local ok,response=pcall(api.GeocoreCheckInClaim,day)
  hudUi.refreshCheckIn(true)
  return ok and string.find(tostring(response or ""),"ok=true",1,true)~=nil
end

local function createCommerceUi(safe)
  commerceRoot, hudUi.commerceOverlayRect = addRoot(safe, "HUD_CommerceOverlay", true)
  hudUi.commerceOverlayRect.anchorMin, hudUi.commerceOverlayRect.anchorMax = Vector2.zero, Vector2.one
  hudUi.commerceOverlayRect.offsetMin, hudUi.commerceOverlayRect.offsetMax = Vector2.zero, Vector2.zero
  addImage(commerceRoot, "CommerceDimmer", Vector2.zero, Vector2.one, Vector2.zero, Vector2.zero, Color(0.006, 0.010, 0.018, 0.34), nil, false, false)
  local panel, panelRect, panelCore = addGlass(commerceRoot, "HUD_CommercePanel", false, Color(1.0, 0.40, 0.12, 0.82))
  hudUi.commercePanelRoot, hudUi.commercePanelRect, hudUi.commercePanelCore = panel, panelRect, panelCore
  local panelSurface = panelCore:GetComponent(typeof(UnityEngine.UI.Image))
  if panelSurface ~= nil then panelSurface.color = Color(0.006, 0.009, 0.012, 0.94) end

  hudUi.commerceTitle = addGlyphLine(panelCore, "CommerceTitle", hudUi.panelTitleGlyph, Color(0.98, 0.98, 1, 1), "center", 12)
  local closeRoot, closeRect, closeCore = addCommerceButton(panelCore, "CommerceCloseButton", Color(1.0, 0.38, 0.12, 0.72), hudUi.commerceCloseHandler)
  hudUi.commerceCloseRoot, hudUi.commerceCloseRect = closeRoot, closeRect
  addIconBar(closeCore, "CloseStrokeA", Vector2(0.30, 0.47), Vector2(0.70, 0.53), Color(0.96, 0.98, 1, 0.96), 45)
  addIconBar(closeCore, "CloseStrokeB", Vector2(0.30, 0.47), Vector2(0.70, 0.53), Color(0.96, 0.98, 1, 0.96), -45)
  local _, headerRuleRect = addImage(panelCore, "CommerceHeaderRule", Vector2.zero, Vector2.zero, Vector2.zero, Vector2.zero, Color(0.84, 0.90, 1, 0.18), nil, false, false)
  hudUi.commerceHeaderRuleRect = headerRuleRect
  hudUi.commerceScroll=hudUi.astraCreateScroll(panelCore,"CommerceScroll")
  hudUi.commerceScrollHint=addGlyphLine(panelCore,"CommerceScrollHint",18,Color(0.62,0.72,0.84,1),"center",18)
  setGlyphLine(hudUi.commerceScrollHint,"上下滑动查看")

  local appearancePage, appearancePageRect = addRoot(panelCore, "CommerceAppearancePage", false)
  hudUi.appearancePageRoot, hudUi.appearancePageRect = appearancePage, appearancePageRect
  hudUi.appearanceRows = {
    addCommerceCard(appearancePage, "AppearanceTitle", Color(0.46, 0.62, 0.82, 0.48), "头衔", "TITLE_DEFAULT", "我是新手", hudUi.equipTitleHandler),
    addCommerceCard(appearancePage, "AppearanceWing", Color(0.46, 0.72, 1.0, 0.62), "翅膀", "WING_01", "熔核之翼", hudUi.equipWingHandler),
    addCommerceCard(appearancePage, "AppearanceHalo", Color(0.72, 0.56, 1.0, 0.62), "光环", "HALO_01", "地心光环", hudUi.equipHaloHandler),
    addCommerceCard(appearancePage, "AppearanceVeteran", Color(0.94,0.76,0.43,0.70), "签到限定头衔", "TITLE_VETERAN_DRIVER", "老司机", function()
      hudUi.equipItem("title",(hudUi.economyEquipped or {}).title=="TITLE_VETERAN_DRIVER" and "" or "TITLE_VETERAN_DRIVER")
    end),
  }
  hudUi.appearanceStatus = addGlyphLine(appearancePage, "AppearanceActionStatus", hudUi.panelBodyGlyph, Color(0.74, 0.86, 1, 1), "center", 22)

  local shopPage, shopPageRect = addRoot(panelCore, "CommerceShopPage", false)
  hudUi.shopPageRoot, hudUi.shopPageRect = shopPage, shopPageRect
  hudUi.shopStatus = addGlyphLine(shopPage, "ShopDataStatus", 14, Color(0.83, 0.88, 0.95, 1), "left", 18)
  hudUi.shopRows = {
    addCommerceCard(shopPage, "ShopWing", Color(0.46, 0.72, 1.0, 0.62), "翅膀", "WING_01", "熔核之翼", hudUi.buyWingHandler),
    addCommerceCard(shopPage, "ShopHalo", Color(0.72, 0.56, 1.0, 0.62), "光环", "HALO_01", "地心光环", hudUi.buyHaloHandler),
  }

  local sponsorPage, sponsorPageRect = addRoot(panelCore, "CommerceSponsorPage", false)
  hudUi.sponsorPageRoot, hudUi.sponsorPageRect = sponsorPage, sponsorPageRect
  for _,page in ipairs({appearancePage,shopPage,sponsorPage})do page.transform:SetParent(hudUi.commerceScroll.content.transform,false)end
  hudUi.sponsorState = addGlyphLine(sponsorPage, "SponsorState", hudUi.panelBodyGlyph, Color(1.0, 0.74, 0.32, 1), "center", 20)
  hudUi.sponsorPoolLabel = addGlyphLine(sponsorPage, "SponsorPoolLabel", hudUi.panelLabelGlyph, Color(0.82, 0.90, 1, 1), "left", 8)
  hudUi.sponsorMineLabel = addGlyphLine(sponsorPage, "SponsorMineLabel", hudUi.panelLabelGlyph, Color(0.82, 0.90, 1, 1), "left", 8)
  setGlyphLine(hudUi.sponsorPoolLabel, "本局奖池")
  setGlyphLine(hudUi.sponsorMineLabel, "我的累计")
  hudUi.sponsorPoolText = addText(sponsorPage, "SponsorPoolValue", Vector2.zero, Vector2.zero, 24, UnityEngine.TextAnchor.MiddleRight)
  hudUi.sponsorMineText = addText(sponsorPage, "SponsorMineValue", Vector2.zero, Vector2.zero, 18, UnityEngine.TextAnchor.MiddleRight)
  hudUi.sponsorPoolText.color, hudUi.sponsorMineText.color = Color(1.0, 0.82, 0.38, 1), Color(0.68, 0.86, 1.0, 1)
  hudUi.sponsorAmountLabel = addGlyphLine(sponsorPage, "SponsorAmountLabel", hudUi.panelLabelGlyph, Color(0.88, 0.94, 1, 1), "left", 8)
  setGlyphLine(hudUi.sponsorAmountLabel, "累计赞助目标")
  hudUi.sponsorInputRoot, hudUi.sponsorInputRect, hudUi.sponsorInput = addNumericInput(sponsorPage, "SponsorAmountInput")
  local submitRoot, submitRect, submitCore, submitButton = addCommerceButton(sponsorPage, "SponsorSubmit", Color(1.0, 0.48, 0.14, 0.76), hudUi.sponsorSubmitHandler)
  hudUi.sponsorSubmitRoot, hudUi.sponsorSubmitRect, hudUi.sponsorSubmitButton = submitRoot, submitRect, submitButton
  local submitSurface = submitCore:GetComponent(typeof(UnityEngine.UI.Image))
  if submitSurface ~= nil then submitSurface.color = Color(0.86, 0.64, 0.31, 1) end
  hudUi.sponsorSubmitLabel = addGlyphLine(submitCore, "SponsorSubmitLabel", hudUi.panelBodyGlyph, Color(0.08, 0.09, 0.12, 1), "center", 8)
  setGlyphLine(hudUi.sponsorSubmitLabel, "确认赞助")
  hudUi.sponsorQuickButtons = {}
  local quickSpecs = {
    { 10, hudUi.sponsorTenHandler }, { 100, hudUi.sponsorHundredHandler },
    { 500, hudUi.sponsorFiveHundredHandler }, { 1000, hudUi.sponsorThousandHandler },
    { 5000, hudUi.sponsorFiveThousandHandler },
  }
  for _, spec in ipairs(quickSpecs) do
    local quickRoot, quickRect, quickCore, quickButton = addCommerceButton(sponsorPage, "SponsorQuick" .. tostring(spec[1]), Color(0.34, 0.56, 0.82, 0.62), spec[2])
    local quickText = addText(quickCore, "SponsorQuickValue", Vector2.zero, Vector2.one, 16, UnityEngine.TextAnchor.MiddleCenter)
    quickText.text, quickText.color = tostring(spec[1]), Color(0.92, 0.96, 1, 1)
    hudUi.sponsorQuickButtons[#hudUi.sponsorQuickButtons + 1] = { root = quickRoot, rect = quickRect, button = quickButton }
  end
  hudUi.sponsorMessage = addGlyphLine(sponsorPage, "SponsorMessage", hudUi.panelBodyGlyph, Color(0.74, 0.86, 1, 1), "center", 20)
  hudUi.sponsorRangeLabel = addGlyphLine(sponsorPage, "SponsorRangeLabel", hudUi.panelBodyGlyph, Color(0.74, 0.86, 1, 1), "center", 8)
  setGlyphLine(hudUi.sponsorRangeLabel, "累计金额")
  hudUi.sponsorRangeText = addText(sponsorPage, "SponsorRangeValue", Vector2.zero, Vector2.zero, 16, UnityEngine.TextAnchor.MiddleLeft)
  hudUi.sponsorRangeText.color = Color(0.82, 0.90, 1.0, 1)
  hudUi.sponsorDebitHint=addGlyphLine(sponsorPage,"SponsorDebitHint",18,Color(0.62,0.72,0.84,1),"left",20)
  setGlyphLine(hudUi.sponsorDebitHint,"仅扣除本次增加金额")

  local prompt, promptRect, promptCore, promptButton = addCommerceButton(safe, "HUD_SponsorPrompt", Color(1.0, 0.42, 0.10, 0.82), hudUi.sponsorOpenHandler)
  sponsorPromptRoot = prompt
  hudUi.sponsorPromptRect, hudUi.sponsorPromptButton = promptRect, promptButton
  hudUi.sponsorPromptLabel = addGlyphLine(promptCore, "SponsorPromptLabel", hudUi.panelBodyGlyph, Color(1.0, 0.93, 0.78, 1), "left", 12)
  setGlyphLine(hudUi.sponsorPromptLabel, "比赛赞助")
  hudUi.sponsorPromptPool = addText(promptCore, "SponsorPromptPool", Vector2.zero, Vector2.zero, 16, UnityEngine.TextAnchor.MiddleRight)
  hudUi.sponsorPromptPool.color = Color(1.0, 0.76, 0.28, 1)

  appearancePage:SetActive(false)
  shopPage:SetActive(false)
  sponsorPage:SetActive(false)
  commerceRoot:SetActive(false)
  sponsorPromptRoot:SetActive(false)
end

local function layoutCommerceCard(row,width,height,tile)
  local function place(rect,x,y,w,h) setRect(rect,Vector2(0,1),Vector2(0,1),Vector2(x,-y),Vector2(w,h)) end
  row.idText.gameObject:SetActive(false)
  row.status.root:SetActive(not row.isShop)
  row.category.glyphSize=12;row.category.color=Color(0.66,0.76,0.89,1);setGlyphLine(row.category,row.category.value)
  local art=row.itemId=="WING_01" or row.itemId=="HALO_01"
  row.icon:SetActive(not art)
  if row.veteranBadge then
    row.icon:SetActive(false);row.concept.root:SetActive(false);row.itemName.root:SetActive(false)
    place(row.category.rect,14,8,width-28,22)
    place(row.veteranBadge.rect,14,36,width-28,48)
    row.veteranBadge.label.fontSize=12
    place(row.status.rect,14,88,width-28,24)
    place(row.actionRect,12,height-54,width-24,44)
  elseif not tile and height<160 then
    place(row.artRect,8,4,96,96)
    place(row.iconRect,28,20,56,56)
    place(row.concept.rect,8,102,96,20)
    place(row.category.rect,116,6,width-128,20)
    row.category.glyphSize=12;setGlyphLine(row.category,row.category.value)
    place(row.itemName.rect,116,26,width-128,26)
    place(row.status.rect,116,52,width-128,24)
    place(row.priceText.rectTransform,116,52,width-128,24)
    place(row.actionRect,116,78,width-128,44)
  elseif tile then
    local short=height<180
    local artSize=short and 72 or 174
    place(row.artRect,(width-artSize)/2,short and 4 or 2,artSize,artSize)
    place(row.iconRect,(width-64)/2,short and 4 or 48,64,64)
    place(row.concept.rect,0,short and 64 or 166,width,18)
    row.concept.root:SetActive(not short and art)
    place(row.category.rect,16,short and 8 or 184,width-32,20)
    row.category.glyphSize=12;row.category.color=Color(0.66,0.76,0.89,1);setGlyphLine(row.category,row.category.value)
    if short then place(row.artRect,width-84,4,72,72)end
    place(row.itemName.rect,16,short and 32 or 206,width-32,28)
    place(row.status.rect,16,short and 60 or 238,width-32,24)
    place(row.priceText.rectTransform,16,short and 60 or 238,width-32,24)
    place(row.actionRect,12,height-(short and 52 or 60),width-24,short and 44 or 48)
  else
    place(row.artRect,8,8,96,96)
    place(row.iconRect,26,20,56,56)
    place(row.concept.rect,8,102,96,20)
    place(row.category.rect,116,12,width-128,20)
    row.category.glyphSize=12;row.category.color=Color(0.66,0.76,0.89,1);setGlyphLine(row.category,row.category.value)
    place(row.itemName.rect,116,38,width-128,28)
    place(row.status.rect,116,70,width-128,26)
    place(row.priceText.rectTransform,116,70,width-128,26)
    place(row.actionRect,12,height-56,width-24,44)
  end
  row.actionLabel.rect.anchorMin,row.actionLabel.rect.anchorMax=Vector2.zero,Vector2.one
  row.actionLabel.rect.offsetMin,row.actionLabel.rect.offsetMax=Vector2.zero,Vector2.zero
end

hudUi.layoutCommerce = function(portrait)
  if hudUi.commercePanelRect==nil or hudUi.astraFrame==nil then return end
  local f,mode=hudUi.astraFrame,tostring(hudUi.commerceMode or "appearance")
  local panelWidth=math.min(portrait and 460 or 740,f.width-24)
  local tile=not portrait and panelWidth>=600
  local short=f.short and tile
  local inner=panelWidth-32
  local cardHeight=mode=="appearance" and 178 or tile and (short and 142 or 328) or 184
  local contentHeight
  if mode=="appearance" then contentHeight=(tile and 2 or 4)*(cardHeight+12)+32
  elseif mode=="shop" then contentHeight=tile and cardHeight+(short and 28 or 40) or cardHeight*2+52
  else contentHeight=short and 170 or 332 end
  local bodyTop,footer=short and 52 or 80,short and 8 or 16
  if not short and contentHeight+bodyTop+footer>f.modalHeight then footer=32 end
  local panelHeight=math.min(f.modalHeight,contentHeight+bodyTop+footer)
  setRect(hudUi.commercePanelRect,Vector2(0.5,1),Vector2(0.5,1),Vector2(0,-(f.modalTop+(f.modalHeight-panelHeight)/2)),Vector2(panelWidth,panelHeight))
  setRect(hudUi.commerceTitle.rect,Vector2(0,1),Vector2(0,1),Vector2(20,short and -8 or -18),Vector2(panelWidth-96,36))
  hudUi.commerceTitle.alignment="left"
  if hudUi.commerceTitle.astraAligned~=true then local value=hudUi.commerceTitle.value;hudUi.commerceTitle.value=nil;setGlyphLine(hudUi.commerceTitle,value);hudUi.commerceTitle.astraAligned=true end
  setRect(hudUi.commerceCloseRect,Vector2(1,1),Vector2(1,1),Vector2(-12,short and -4 or -12),Vector2(short and 44 or 48,short and 44 or 48))
  setRect(hudUi.commerceHeaderRuleRect,Vector2(0,1),Vector2(0,1),Vector2(16,short and -48 or -68),Vector2(inner,1))
  hudUi.astraLayoutScroll(hudUi.commerceScroll,16,bodyTop,inner,math.max(70,panelHeight-bodyTop-footer),contentHeight)
  setRect(hudUi.commerceScrollHint.rect,Vector2(0.5,0),Vector2(0.5,0),Vector2(0,8),Vector2(inner,22))
  hudUi.commerceScrollHint.root:SetActive(not short and hudUi.commerceScroll.scroll.vertical)
  for _,rect in ipairs({hudUi.appearancePageRect,hudUi.shopPageRect,hudUi.sponsorPageRect})do
    rect.anchorMin,rect.anchorMax=Vector2.zero,Vector2.one;rect.offsetMin,rect.offsetMax=Vector2.zero,Vector2.zero
  end
  for index,row in ipairs(hudUi.appearanceRows or {})do
    local width=tile and (inner-12)/2 or inner
    local x=tile and ((index-1)%2)*(width+12) or 0
    local y=(tile and math.floor((index-1)/2) or index-1)*(cardHeight+12)
    setRect(row.rect,Vector2(0,1),Vector2(0,1),Vector2(x,-y),Vector2(width,cardHeight))
    layoutCommerceCard(row,width,cardHeight,tile)
  end
  local appearanceBottom=(tile and 2 or 4)*(cardHeight+12)
  setRect(hudUi.appearanceStatus.rect,Vector2(0.5,1),Vector2(0.5,1),Vector2(0,-appearanceBottom),Vector2(inner,24))
  setRect(hudUi.shopStatus.rect,Vector2(0,1),Vector2(0,1),Vector2(0,0),Vector2(inner,24))
  for index,row in ipairs(hudUi.shopRows or {})do
    local width=tile and (inner-12)/2 or inner
    local x=tile and (index-1)*(width+12) or 0
    local y=(short and 28 or 40)+(tile and 0 or (index-1)*(cardHeight+12))
    setRect(row.rect,Vector2(0,1),Vector2(0,1),Vector2(x,-y),Vector2(width,cardHeight))
    layoutCommerceCard(row,width,cardHeight,tile)
  end
  local function place(rect,x,y,w,h) setRect(rect,Vector2(0,1),Vector2(0,1),Vector2(x,-y),Vector2(w,h)) end
  hudUi.sponsorPoolText.alignment=UnityEngine.TextAnchor.MiddleLeft
  hudUi.sponsorMineText.alignment=UnityEngine.TextAnchor.MiddleLeft
  if short then
    local rightX,rightWidth=200,inner-200
    place(hudUi.sponsorState.rect,0,0,184,24)
    place(hudUi.sponsorPoolLabel.rect,8,32,180,24)
    place(hudUi.sponsorPoolText.rectTransform,8,56,180,32)
    place(hudUi.sponsorMineLabel.rect,8,96,180,24)
    place(hudUi.sponsorMineText.rectTransform,8,120,180,30)
    place(hudUi.sponsorAmountLabel.rect,rightX,0,rightWidth,24)
    local inputWidth=math.floor((rightWidth-12)*0.60)
    place(hudUi.sponsorInputRect,rightX,28,inputWidth,44)
    place(hudUi.sponsorSubmitRect,rightX+inputWidth+12,28,rightWidth-inputWidth-12,44)
    place(hudUi.sponsorDebitHint.rect,rightX,76,rightWidth,24)
    local quickWidth=(rightWidth-24)/5
    for index,quick in ipairs(hudUi.sponsorQuickButtons or {})do place(quick.rect,rightX+(index-1)*(quickWidth+6),100,quickWidth,44)end
    place(hudUi.sponsorMessage.rect,rightX,146,rightWidth,24)
    place(hudUi.sponsorRangeLabel.rect,rightX+rightWidth/2-114,146,100,24)
    place(hudUi.sponsorRangeText.rectTransform,rightX+rightWidth/2,146,114,24)
  else
    place(hudUi.sponsorState.rect,0,0,inner,28)
    place(hudUi.sponsorPoolLabel.rect,8,40,inner/2-20,26)
    place(hudUi.sponsorPoolText.rectTransform,8,68,inner/2-20,32)
    place(hudUi.sponsorMineLabel.rect,inner/2+8,40,inner/2-20,26)
    place(hudUi.sponsorMineText.rectTransform,inner/2+8,68,inner/2-20,32)
    place(hudUi.sponsorAmountLabel.rect,8,112,inner-16,28)
    local inputWidth=math.max(120,(inner-28)*0.54)
    place(hudUi.sponsorInputRect,8,148,inputWidth,48)
    place(hudUi.sponsorSubmitRect,inputWidth+20,148,inner-inputWidth-28,48)
    place(hudUi.sponsorDebitHint.rect,8,200,inner-16,26)
    local quickWidth=(inner-40)/5
    for index,quick in ipairs(hudUi.sponsorQuickButtons or {})do place(quick.rect,8+(index-1)*(quickWidth+6),234,quickWidth,48) end
    place(hudUi.sponsorMessage.rect,0,294,inner,28)
    place(hudUi.sponsorRangeLabel.rect,inner/2-114,294,100,28)
    place(hudUi.sponsorRangeText.rectTransform,inner/2,294,114,28)
  end
  hudUi.sponsorSubmitLabel.rect.anchorMin,hudUi.sponsorSubmitLabel.rect.anchorMax=Vector2.zero,Vector2.one
  hudUi.sponsorSubmitLabel.rect.offsetMin,hudUi.sponsorSubmitLabel.rect.offsetMax=Vector2.zero,Vector2.zero
  if sponsorPromptRoot~=nil then
    -- Follow the actual activity row/column in every responsive layout.
    -- Both rects use a top-right anchor/pivot in the same safe-area parent.
    local activityRect=hudUi.more.buttonRect or hudUi.activityRect
    if activityRect~=nil then f.promptTop=-activityRect.anchoredPosition.y+activityRect.sizeDelta.y+12 end
    setRect(hudUi.sponsorPromptRect,Vector2(1,1),Vector2(1,1),Vector2(-12,-f.promptTop),Vector2(portrait and 216 or 240,48))
    setRect(hudUi.sponsorPromptLabel.rect,Vector2(0,0.5),Vector2(0,0.5),Vector2(12,0),Vector2(128,28))
    setRect(hudUi.sponsorPromptPool.rectTransform,Vector2(1,0.5),Vector2(1,0.5),Vector2(-12,0),Vector2(64,28))
  end
end

local function createHud()
  if hudRoot ~= nil then return true end
  local ok, result = pcall(function()
    hudRoot = GameObject("Geocore_Race_HUD_V9_ProMax_Responsive")
    local canvas = hudRoot:AddComponent(typeof(UnityEngine.Canvas))
    canvas.renderMode, canvas.sortingOrder = UnityEngine.RenderMode.ScreenSpaceOverlay, 520
    hudScaler = hudRoot:AddComponent(typeof(UnityEngine.UI.CanvasScaler))
    hudScaler.uiScaleMode = UnityEngine.UI.CanvasScaler.ScaleMode.ScaleWithScreenSize
    hudRoot:AddComponent(typeof(UnityEngine.UI.GraphicRaycaster))
    local safe = GameObject("Geocore_Race_HUD_SafeArea")
    safe.transform:SetParent(hudRoot.transform, false)
    hudSafeRect = safe:AddComponent(typeof(UnityEngine.RectTransform))
    hudSafeRect.anchorMin, hudSafeRect.anchorMax = Vector2.zero, Vector2.one
    hudSafeRect.offsetMin, hudSafeRect.offsetMax = Vector2.zero, Vector2.zero

    local status, statusRect, statusCore, statusProgress = addGlass(safe, "HUD_RaceStatus", false, Color(1.0, 0.33, 0.08, 0.96))
    hudStatusRoot = status
    hudUi.statusProgressRect = statusProgress.rectTransform
    statusProgress.color = Color(1.0, 0.68, 0.28, 0.86)
    hudUi.statusDividerRects = {
      addDivider(statusCore, 0.245),
      addDivider(statusCore, 0.465),
      addDivider(statusCore, 0.715),
    }
    hudUi.phaseIconRect = addFlagIcon(statusCore, "PhaseFlagIcon", Vector2.zero, Vector2.zero, Color(1.0, 0.38, 0.10, 1)):GetComponent(typeof(UnityEngine.RectTransform))
    hudPhase = addText(statusCore, "PhaseValue", Vector2(0.068, 0.30), Vector2(0.232, 0.70), hudUi.primaryFont)
    hudUi.phaseTextRect, hudUi.phaseImageEntries = hudPhase.rectTransform, {}
    hudPhase.text = ""
    for _, row in ipairs({ {"preparing","preparing"}, {"waiting","waiting"}, {"racing","racing"}, {"finished","finished"}, {"recycling","recycling"}, {"syncing","syncing"} }) do
      local object, rect, image = addBitmapLabel(statusCore, "PhaseValueBitmap_" .. row[1], row[2], Vector2.zero, Vector2.zero, Color(0.96, 0.98, 1, 1))
      object:SetActive(false)
      hudPhaseImages[row[1]] = object
      hudUi.phaseImageEntries[row[1]] = { rect = rect, image = image }
    end
    local _, _, phaseAccent = addImage(statusCore, "PhaseStatePill", Vector2(0.018, 0.13), Vector2(0.023, 0.87), Vector2.zero, Vector2.zero, Color(1, 0.36, 0.10, 0.82), panelSprite(), true, false)
    hudPhaseAccent = phaseAccent
    hudUi.timerIconRect = addClockIcon(statusCore, "TimerClockIcon", Vector2.zero, Vector2.zero, Color(0.82, 0.90, 1.0, 0.94)):GetComponent(typeof(UnityEngine.RectTransform))
    hudTimer = addText(statusCore, "TimerValue", Vector2(0.310, 0.30), Vector2(0.447, 0.70), hudUi.primaryFont, UnityEngine.TextAnchor.MiddleLeft)
    hudUi.timerTextRect = hudTimer.rectTransform
    hudTimer.color = Color(1.0, 0.96, 0.88, 1)
    hudTimerGlow = nil
    local _, rankCaptionRect, rankCaptionImage = addBitmapLabel(statusCore, "RankCaptionBitmap", "currentRank", Vector2.zero, Vector2.zero, Color(0.78, 0.86, 0.96, 0.98))
    hudUi.rankCaptionRect, hudUi.rankCaptionImage = rankCaptionRect, rankCaptionImage
    hudRank = addText(statusCore, "RankValue", Vector2(0.615, 0.30), Vector2(0.700, 0.70), hudUi.primaryFont, UnityEngine.TextAnchor.MiddleLeft)
    hudUi.rankTextRect = hudRank.rectTransform
    hudUi.participationHint = addText(statusCore, "ParticipationHint", Vector2.zero, Vector2.zero, 18, UnityEngine.TextAnchor.MiddleLeft)
    hudUi.participationHint.color = Color(0.86,0.94,1,1)
    hudUi.participationHint.gameObject:SetActive(false)
    hudRank.color = Color(1.0, 0.58, 0.16, 1)
    hudRankAccent = nil

    hudUi.coinIconRect = addCoinIcon(statusCore, "CoinVectorIcon", Vector2.zero, Vector2.zero, Color(1.0, 0.78, 0.28, 0.98)):GetComponent(typeof(UnityEngine.RectTransform))
    local _, coinCaptionRect, coinCaptionImage = addBitmapLabel(statusCore, "CoinCaptionBitmap", "coin", Vector2.zero, Vector2.zero, Color(1.0, 0.78, 0.36, 1))
    hudUi.coinCaptionRect, hudUi.coinCaptionImage = coinCaptionRect, coinCaptionImage
    hudCoins = addText(statusCore, "CoinValue", Vector2(0.834, 0.30), Vector2(0.985, 0.70), hudUi.primaryFont, UnityEngine.TextAnchor.MiddleLeft)
    hudUi.coinTextRect = hudCoins.rectTransform
    hudCoins.fontSize, hudCoins.resizeTextMinSize, hudCoins.resizeTextMaxSize = 12, 12, 12
    hudCoins.color = Color(1.0, 0.86, 0.48, 1)

    local appearance, appearanceRect, appearanceCore = addGlass(safe, "HUD_Appearance", true, Color(0.50, 0.72, 1.0, 0.54))
    hudAppearanceRoot = appearance
    hudUi.appearanceIconRect = addSparkleIcon(appearanceCore, "AppearanceVectorIcon", Vector2.zero, Vector2.zero, Color(0.68, 0.88, 1.0, 1)):GetComponent(typeof(UnityEngine.RectTransform))
    local _, appearanceLabelRect, appearanceLabelImage = addBitmapLabel(appearanceCore, "AppearanceLabelBitmap", "appearance", Vector2.zero, Vector2.zero, Color(0.90, 0.95, 1, 1))
    hudUi.appearanceLabelRect, hudUi.appearanceLabelImage = appearanceLabelRect, appearanceLabelImage
    hudAppearanceButton = appearance:AddComponent(typeof(UnityEngine.UI.Button))
    configureButtonFeedback(hudAppearanceButton, appearanceCore, Color(0.62, 0.82, 1.0, 0.72))
    bindNamedButton(hudAppearanceButton, hudUi.appearanceOpenHandler)

    local shop, shopRect, shopCore = addGlass(safe, "HUD_Shop", true, Color(1.0, 0.55, 0.16, 0.64))
    hudShopRoot = shop
    hudUi.shopIconRect = addShopIcon(shopCore, "ShopVectorIcon", Vector2.zero, Vector2.zero, Color(1.0, 0.72, 0.30, 1)):GetComponent(typeof(UnityEngine.RectTransform))
    local _, shopLabelRect, shopLabelImage = addBitmapLabel(shopCore, "ShopLabelBitmap", "shop", Vector2.zero, Vector2.zero, Color(1.0, 0.86, 0.60, 1))
    hudUi.shopLabelRect, hudUi.shopLabelImage = shopLabelRect, shopLabelImage
    hudShopButton = shop:AddComponent(typeof(UnityEngine.UI.Button))
    configureButtonFeedback(hudShopButton, shopCore, Color(1.0, 0.64, 0.24, 0.72))
    bindNamedButton(hudShopButton, hudUi.shopOpenHandler)

    resultsRoot, resultsRect = addRoot(safe, "HUD_ResultsOverlay", true)
    local _, _, resultsDimmer = addImage(resultsRoot, "ResultsDimmer", Vector2.zero, Vector2.one, Vector2.zero, Vector2.zero, Color(0.006, 0.010, 0.018, 0.24), nil, false, false)
    hudUi.resultsDimmer = resultsDimmer
    local resultsPanel, modalRect, modalCore, modalAccent = addGlass(resultsRoot, "HUD_ResultsPanel", false, Color(1.0, 0.40, 0.10, 0.82))
    resultsPanelRect = modalRect
    local modalSurfaceImage = modalCore:GetComponent(typeof(UnityEngine.UI.Image))
    if modalSurfaceImage ~= nil then modalSurfaceImage.color = Color(0.006, 0.009, 0.012, 0.94) end
    resultsTitle = addText(modalCore, "ResultsTitle", Vector2.zero, Vector2.zero, 36)
    resultsTitle.text = ""
    hudUi.resultsTitleRect = resultsTitle.rectTransform
    local _, resultsTitleBitmapRect = addBitmapLabel(modalCore, "ResultsTitleBitmap", "results", Vector2.zero, Vector2.zero, Color(1.0, 1.0, 1.0, 1))
    hudUi.resultsTitleBitmapRect = resultsTitleBitmapRect
    local subtitle = addText(modalCore, "ResultsSubtitle", Vector2.zero, Vector2.zero, 20)
    subtitle.text = ""
    hudUi.resultsSubtitleRect = subtitle.rectTransform
    local _, resultsSubtitleBitmapRect = addBitmapLabel(modalCore, "ResultsSubtitleBitmap", "subtitle", Vector2.zero, Vector2.zero, Color(0.90, 0.92, 0.96, 0.98))
    hudUi.resultsSubtitleBitmapRect = resultsSubtitleBitmapRect
    hudUi.resultsFormula=addGlyphLine(modalCore,"ResultsFormula",14,Color(0.82,0.87,0.94,1),"left",24)
    setGlyphLine(hudUi.resultsFormula,"金币为常规与赞助合计")

    local closeRoot, closeRect, closeCore = addGlass(modalCore, "ResultsCloseButton", true, Color(1.0, 0.38, 0.12, 0.72))
    hudUi.resultsCloseRoot, hudUi.resultsCloseRect = closeRoot, closeRect
    addIconBar(closeCore, "CloseStrokeA", Vector2(0.30, 0.47), Vector2(0.70, 0.53), Color(0.96, 0.98, 1, 0.96), 45)
    addIconBar(closeCore, "CloseStrokeB", Vector2(0.30, 0.47), Vector2(0.70, 0.53), Color(0.96, 0.98, 1, 0.96), -45)
    hudUi.resultsCloseButton = closeRoot:AddComponent(typeof(UnityEngine.UI.Button))
    configureButtonFeedback(hudUi.resultsCloseButton, closeCore, Color(1.0, 0.48, 0.20, 0.78))
    pcall(function()
      hudUi.resultsCloseButton.onClick:AddListener(hudUi.resultsCloseHandler)
    end)

    local headerPlate, headerPlateRect = addImage(modalCore, "ResultsHeaderPlate", Vector2.zero, Vector2.zero, Vector2.zero, Vector2.zero, Color(0.04, 0.065, 0.10, 0.40), nil, false, false)
    hudUi.resultsHeaderRoot, hudUi.resultsHeaderRect = headerPlate, headerPlateRect
    local rankHeader = addText(headerPlate, "RankHeader", Vector2(0.02, 0), Vector2(0.15, 1), hudUi.labelFont)
    local crewHeader = addText(headerPlate, "CrewHeader", Vector2(0.16, 0), Vector2(0.75, 1), hudUi.labelFont, UnityEngine.TextAnchor.MiddleLeft)
    local timeHeader = addText(headerPlate, "TimeHeader", Vector2(0.76, 0), Vector2(0.98, 1), hudUi.labelFont, UnityEngine.TextAnchor.MiddleRight)
    rankHeader.text, crewHeader.text, timeHeader.text = "", "", ""
    local _, rankHeaderBitmapRect, rankHeaderBitmapImage = addBitmapLabel(headerPlate, "RankHeaderBitmap", "rank", Vector2.zero, Vector2.zero, Color(1, 0.72, 0.34, 1))
    local _, crewHeaderBitmapRect, crewHeaderBitmapImage = addBitmapLabel(headerPlate, "CrewHeaderBitmap", "crew", Vector2.zero, Vector2.zero, Color(0.82, 0.90, 1, 1))
    local _, timeHeaderBitmapRect, timeHeaderBitmapImage = addBitmapLabel(headerPlate, "TimeHeaderBitmap", "time", Vector2.zero, Vector2.zero, Color(0.82, 0.90, 1, 1))
    hudUi.resultsHeaderBitmaps = {
      rank = { rect = rankHeaderBitmapRect, image = rankHeaderBitmapImage },
      crew = { rect = crewHeaderBitmapRect, image = crewHeaderBitmapImage },
      time = { rect = timeHeaderBitmapRect, image = timeHeaderBitmapImage },
    }
    crewHeaderBitmapRect.gameObject:SetActive(false)
    hudUi.resultsNameHeader=addGlyphLine(headerPlate,"ResultNameHeader",16,Color(0.86,0.91,0.97,1),"left",8)
    setGlyphLine(hudUi.resultsNameHeader,"姓名")
    hudUi.resultsCoinsHeader=addGlyphLine(headerPlate,"ResultCoinsHeader",16,Color(0.86,0.91,0.97,1),"left",16)
    setGlyphLine(hudUi.resultsCoinsHeader,"金币 常规 / 赞助")
    rankHeader.color, crewHeader.color, timeHeader.color = Color(1, 0.72, 0.34, 1), Color(0.82, 0.90, 1, 1), Color(0.82, 0.90, 1, 1)
    hudUi.resultsScroll=hudUi.astraCreateScroll(modalCore,"ResultsScroll")
    hudUi.resultsScrollHint=addGlyphLine(modalCore,"ResultsScrollHint",18,Color(0.62,0.72,0.84,1),"center",18)
    setGlyphLine(hudUi.resultsScrollHint,"上下滑动查看完整成绩")
    for index = 1, 30 do
      local plate, plateRect, plateImage = addImage(hudUi.resultsScroll.content, "ResultRowPlate_" .. tostring(index), Vector2.zero, Vector2.zero, Vector2.zero, Vector2.zero,
        index == 1 and Color(0.23, 0.13, 0.05, 0.95) or Color(0.06, 0.09, 0.14, index % 2 == 0 and 0.92 or 0.65), hudUi.astraPanelSprite(), true, false)
      local _,_,rowAccent=addImage(plate, "ResultRowAccent", Vector2(0.008, 0.17), Vector2(0.011, 0.83), Vector2.zero, Vector2.zero,
        index <= 3 and Color(1.0, 0.50, 0.14, 0.90) or Color(0.36, 0.72, 0.94, 0.24), panelSprite(), true, false)
      local rankText = addText(plate, "ResultRank_" .. tostring(index), Vector2(0.02, 0), Vector2(0.15, 1), hudUi.tableFont)
      local crewText = addText(plate, "ResultCrew_" .. tostring(index), Vector2(0.16, 0), Vector2(0.75, 1), hudUi.tableFont, UnityEngine.TextAnchor.MiddleLeft)
      local crewGlyphRoot, crewGlyphRect = addRoot(plate, "ResultCrewGlyphs_" .. tostring(index), false)
      crewGlyphRect.anchorMin, crewGlyphRect.anchorMax = Vector2(0.16, 0), Vector2(0.75, 1)
      crewGlyphRect.offsetMin, crewGlyphRect.offsetMax = Vector2.zero, Vector2.zero
      local timeText = addText(plate, "ResultTime_" .. tostring(index), Vector2(0.76, 0), Vector2(0.98, 1), hudUi.tableFont, UnityEngine.TextAnchor.MiddleRight)
      local timeGlyphRoot, timeGlyphRect = addRoot(plate, "ResultTimeGlyphs_" .. tostring(index), false)
      timeGlyphRect.anchorMin, timeGlyphRect.anchorMax = Vector2(0.76, 0), Vector2(0.98, 1)
      timeGlyphRect.offsetMin, timeGlyphRect.offsetMax = Vector2.zero, Vector2.zero
      if index <= 3 then rankText.color, timeText.color = Color(1.0, 0.76, 0.32, 1), Color(1.0, 0.85, 0.58, 1) end
      local coins=addText(plate,"ResultCoins_"..tostring(index),Vector2.zero,Vector2.zero,18,UnityEngine.TextAnchor.MiddleLeft)
      coins.color=Color(1,0.82,0.42,1)
      local coinsLabel=addGlyphLine(plate,"ResultCoinsLabel_"..tostring(index),18,Color(1,0.82,0.42,1),"left",8)
      setGlyphLine(coinsLabel,"金币")
      resultsRows[index] = { root = plate, rect = plateRect, plate = plateImage, rank = rankText, crew = crewText, crewRoot = crewGlyphRoot, crewGlyphObjects = {}, time = timeText, timeGlyphRoot = timeGlyphRoot, timeGlyphObjects = {}, timeColor = timeText.color,coins=coins,coinsLabel=coinsLabel,accent=rowAccent }
    end
    local emptyRoot, emptyRect = addRoot(modalCore, "ResultsEmptyState", false)
    hudUi.resultsEmptyRoot, hudUi.resultsEmptyRect = emptyRoot, emptyRect
    local emptyIcon, emptyIconRect = addRoot(emptyRoot, "ResultsEmptyIcon", false)
    hudUi.resultsEmptyIconRect = emptyIconRect
    addClockIcon(emptyIcon, "EmptyClock", Vector2(0.08, 0.08), Vector2(0.92, 0.92), Color(1.0, 0.56, 0.20, 0.96))
    addIconBar(emptyIcon, "EmptyStrike", Vector2(0.14, 0.47), Vector2(0.86, 0.53), Color(1.0, 0.34, 0.12, 0.96), -38)
    hudNoResultsImage, hudUi.resultsEmptyLabelRect = addBitmapLabel(emptyRoot, "NoResultsBitmap", "noResults", Vector2.zero, Vector2.zero, Color(0.88, 0.94, 1, 1))
    emptyRoot:SetActive(false)

    createCommerceUi(safe)
    hudUi.createCheckInUi(safe)
    hudUi.createMoreUi(safe)

    resultsRoot.transform:SetAsLastSibling()
    commerceRoot.transform:SetAsLastSibling()
    resultsRoot:SetActive(false)
    return { statusRect, appearanceRect, shopRect, resultsRect, modalRect }
  end)
  if not ok then
    UnityEngine.Debug.LogError("Geocore HUD create failed: " .. tostring(result))
    cleanupHudListeners()
    if hudRoot ~= nil then UnityEngine.Object.Destroy(hudRoot) end
    hudRoot, commerceRoot, sponsorPromptRoot, resultsRoot = nil, nil, nil, nil
    hudStatusRoot, hudAppearanceRoot, hudShopRoot, hudAppearanceButton, hudShopButton = nil, nil, nil, nil, nil
    hudRects, resultsRows, hudPhaseImages = nil, {}, {}
    return false
  end
  hudRects = result
  return true
end

hudUi.layoutStatus = function(statusHeight, portrait)
  local centerY = -math.max(1, statusHeight - 4) * 0.5
  local leftMiddleAnchor, leftMiddlePivot = Vector2(0, 1), Vector2(0, 0.5)
  local centerPivot = Vector2(0.5, 0.5)
  local dividers = portrait and { 170, 316, 486 } or { 280, 520, 800 }
  for index, x in ipairs(dividers) do
    setRect(hudUi.statusDividerRects[index], leftMiddleAnchor, centerPivot, Vector2(x, centerY), Vector2(1, statusHeight - 32))
  end
  local phaseIconX, phaseTextX = portrait and 28 or 32, portrait and 72 or 123
  local timerIconX, timerTextX = portrait and 180 or 300, portrait and 220 or 386
  local rankCaptionX, rankTextX = portrait and 330 or 569, portrait and 418 or 716
  local coinIconX, coinCaptionX, coinTextX = portrait and 494 or 824, portrait and 536 or 892, portrait and 592 or 952
  local phaseLine = portrait and hudUi.primaryLine or 48
  setRect(hudUi.phaseIconRect, leftMiddleAnchor, leftMiddlePivot, Vector2(phaseIconX, centerY + 2), Vector2(40, 40))
  setRect(hudUi.phaseTextRect, leftMiddleAnchor, leftMiddlePivot, Vector2(phaseTextX, centerY + (portrait and 4 or 8)), Vector2(portrait and 96 or 188, phaseLine))
  for _, entry in pairs(hudUi.phaseImageEntries) do
    setBitmapRect(entry.rect, entry.image, leftMiddleAnchor, leftMiddlePivot, Vector2(phaseTextX, centerY + (portrait and 4 or 8)), phaseLine, portrait and 96 or 188)
  end
  setRect(hudUi.timerIconRect, leftMiddleAnchor, leftMiddlePivot, Vector2(timerIconX, centerY), Vector2(portrait and hudUi.iconSize or 38, portrait and hudUi.iconSize or 38))
  setRect(hudUi.timerTextRect, leftMiddleAnchor, leftMiddlePivot, Vector2(timerTextX, centerY - 3), Vector2(portrait and 92 or 144, hudUi.primaryLine))
  setBitmapRect(hudUi.rankCaptionRect, hudUi.rankCaptionImage, leftMiddleAnchor, leftMiddlePivot, Vector2(rankCaptionX, centerY + (portrait and 1 or 5)), hudUi.labelLine, portrait and 80 or 104)
  setRect(hudUi.rankTextRect, leftMiddleAnchor, leftMiddlePivot, Vector2(rankTextX, centerY - 3), Vector2(portrait and 60 or 104, hudUi.primaryLine))
  setRect(hudUi.coinIconRect, leftMiddleAnchor, leftMiddlePivot, Vector2(coinIconX, centerY), Vector2(portrait and hudUi.iconSize or 44, portrait and hudUi.iconSize or 44))
  setBitmapRect(hudUi.coinCaptionRect, hudUi.coinCaptionImage, leftMiddleAnchor, leftMiddlePivot, Vector2(coinCaptionX, centerY + (portrait and 2 or 6)), portrait and hudUi.labelLine or 52, portrait and 48 or 60)
  setRect(hudUi.coinTextRect, leftMiddleAnchor, leftMiddlePivot, Vector2(portrait and coinTextX or 964, centerY), Vector2(portrait and 88 or 164, hudUi.primaryLine))
  setRect(hudUi.statusProgressRect, Vector2(0.5, 0), Vector2(0.5, 0.5), Vector2(0, portrait and -10 or -14), Vector2(portrait and 620 or 1024, portrait and 12 or 16))
end

hudUi.layoutActionButtons = function()
  local leftMiddleAnchor, leftMiddlePivot = Vector2(0, 0.5), Vector2(0, 0.5)
  setRect(hudUi.appearanceIconRect, leftMiddleAnchor, leftMiddlePivot, Vector2(14, 0), Vector2(hudUi.iconSize, hudUi.iconSize))
  setBitmapRect(hudUi.appearanceLabelRect, hudUi.appearanceLabelImage, leftMiddleAnchor, leftMiddlePivot, Vector2(54, 0), hudUi.labelLine, 52)
  setRect(hudUi.shopIconRect, leftMiddleAnchor, leftMiddlePivot, Vector2(14, 0), Vector2(hudUi.iconSize, hudUi.iconSize))
  setBitmapRect(hudUi.shopLabelRect, hudUi.shopLabelImage, leftMiddleAnchor, leftMiddlePivot, Vector2(54, 0), hudUi.labelLine, 52)
end

hudUi.layoutResultsHeader = function(contentWidth)
  local middleLeft, leftPivot = Vector2(0, 0.5), Vector2(0, 0.5)
  local middleRight, rightPivot = Vector2(1, 0.5), Vector2(1, 0.5)
  setBitmapRect(hudUi.resultsHeaderBitmaps.rank.rect, hudUi.resultsHeaderBitmaps.rank.image,
    middleLeft, Vector2(0.5, 0.5), Vector2(contentWidth * 0.085, 0), hudUi.labelLine, 56)
  setBitmapRect(hudUi.resultsHeaderBitmaps.crew.rect, hudUi.resultsHeaderBitmaps.crew.image,
    middleLeft, leftPivot, Vector2(contentWidth * 0.16, 0), hudUi.labelLine, 112)
  setBitmapRect(hudUi.resultsHeaderBitmaps.time.rect, hudUi.resultsHeaderBitmaps.time.image,
    middleRight, rightPivot, Vector2(-contentWidth * 0.02, 0), hudUi.labelLine, 56)
end

hudUi.astraCompactStatus = function(portrait,width)
  local function place(rect,x,y,w,h) setRect(rect,Vector2(0,1),Vector2(0,0.5),Vector2(math.floor(x+0.5),-y),Vector2(math.floor(w+0.5),h)) end
  local topY,column=26,width/3
  local timerColumn=portrait and width/4+4 or column
  local timerX=column+12
  local coinX=column+timerColumn+12
  place(hudUi.phaseIconRect,12,topY,18,18)
  for _,entry in pairs(hudUi.phaseImageEntries)do
    place(entry.rect,portrait and 34 or 40,topY,column-(portrait and 36 or 44),30)
    entry.image.label.fontSize=18
  end
  place(hudUi.timerIconRect,timerX,topY,18,18)
  place(hudUi.timerTextRect,timerX+(portrait and 22 or 26),topY,timerColumn-(portrait and 42 or 40),30)
  hudUi.rankCaptionRect.gameObject:SetActive(false)
  hudUi.rankTextRect.gameObject:SetActive(false)
  place(hudUi.participationHint.rectTransform,16,64,width-32,28)
  hudUi.participationHint.fontSize=18
  hudUi.participationHint.alignment=UnityEngine.TextAnchor.MiddleCenter
  place(hudUi.coinIconRect,coinX,topY,18,18)
  place(hudUi.coinCaptionRect,coinX+24,topY,36,30)
  local hideCoinCaption=portrait or width<600
  hudUi.coinCaptionRect.gameObject:SetActive(not hideCoinCaption)
  local valueX=coinX+(hideCoinCaption and 26 or 64)
  place(hudUi.coinTextRect,valueX,topY,width-valueX-12,30)
  hudTimer.fontSize,hudRank.fontSize,hudCoins.fontSize=18,18,18
  hudTimer.color,hudRank.color,hudCoins.color=Color(0.96,0.98,1,1),Color(1,0.80,0.45,1),Color(1,0.80,0.45,1)
  for index,rect in ipairs(hudUi.statusDividerRects)do
    rect.gameObject:SetActive(index<=2)
    place(rect,index==1 and column or column+timerColumn,topY,1,22)
  end
  setRect(hudUi.statusProgressRect,Vector2(0,0),Vector2(0,0),Vector2(12,1),Vector2(width-24,2))
  hudPhaseAccent.gameObject:SetActive(false)
end

-- BEGIN MOBILE-V8 FIXED LABEL PNG DATA (generated from assets/geocore-ui-v8)
hudUi.v8ButtonPng={
  "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",
}
-- END MOBILE-V8 FIXED LABEL PNG DATA
-- MOBILE-V8: presentation only. All economy/race APIs and listeners are retained.
-- Logical short side = 450. Native friend text is the visual ceiling (~2.6%
-- of the short edge in the supplied phone captures); primary glyphs stay below it.
hudUi.v8Place=function(rect,x,y,w,h)
  setRect(rect,Vector2(0,1),Vector2(0,1),Vector2(math.floor(x+.5),-math.floor(y+.5)),Vector2(math.floor(w+.5),math.floor(h+.5)))
end

hudUi.v8Init=function()
  if hudUi.v8Ready then return end
  local safe=hudSafeRect.gameObject
  local coin,coinRect,coinCore=addGlass(safe,"HUD_CoinChip",false,Color(1,.78,.32,1))
  hudUi.v8CoinRoot,hudUi.v8CoinRect=coin,coinRect
  hudUi.coinIconRect:SetParent(coinCore.transform,false)
  hudUi.coinTextRect:SetParent(coinCore.transform,false)
  hudUi.coinCaptionRect.gameObject:SetActive(false)
  local hint,hintRect=addRoot(safe,"HUD_ContextHint",false)
  local _,_,hintImage=addImage(hint,"HintTint",Vector2.zero,Vector2.one,Vector2.zero,Vector2.zero,Color(.02,.027,.038,.46),hudUi.astraPanelSprite(),true,false)
  hudUi.v8HintRoot,hudUi.v8HintRect=hint,hintRect
  hudUi.participationHint.rectTransform:SetParent(hint.transform,false)
  -- Preserve the existing click listeners, but replace the visible glass/text
  -- children with one fixed-label RGBA image. The 44x44 hit target is separate.
  hudUi.v8Nav,hudUi.v8Textures,hudUi.v8Sprites={},{},{}
  if hudUi.activityDot then hudUi.activityDot.transform:SetParent(hudUi.activityRoot.transform,false) end
  for i,root in ipairs({hudAppearanceRoot,hudShopRoot,hudUi.activityRoot,hudUi.more.buttonRoot}) do
    for j=0,root.transform.childCount-1 do
      local child=root.transform:GetChild(j).gameObject
      if child~=hudUi.activityDot then child:SetActive(false) end
    end
    local texture=UnityEngine.Texture2D(2,2,UnityEngine.TextureFormat.RGBA32,false)
    texture.name="MobileV8_NavRGBA_"..i
    local bytes=CS.System.Convert.FromBase64String(hudUi.v8ButtonPng[i])
    local loaded=false
    pcall(function()loaded=UnityEngine.ImageConversion.LoadImage(texture,bytes)==true end)
    if not loaded then pcall(function()loaded=texture:LoadImage(bytes)==true end) end
    if not loaded then error("Navigation PNG decode failed: "..i) end
    texture.filterMode,texture.wrapMode=UnityEngine.FilterMode.Bilinear,UnityEngine.TextureWrapMode.Clamp
    texture:Apply(false,true)
    local sprite=UnityEngine.Sprite.Create(texture,UnityEngine.Rect(0,0,texture.width,texture.height),Vector2(.5,.5),100)
    local _,rect,img=addImage(root,"FixedIconLabelPNG",Vector2.zero,Vector2.one,Vector2.zero,Vector2.zero,Color.white,sprite,false,false)
    local hit=root:GetComponent(typeof(UnityEngine.UI.Image));hit.color=Color(1,1,1,0);hit.raycastTarget=true
    local button=root:GetComponent(typeof(UnityEngine.UI.Button));button.targetGraphic=img
    local colors=button.colors
    colors.normalColor=Color.white;colors.highlightedColor=Color(1,.92,.73,1)
    colors.pressedColor=Color(.83,.72,.54,1);colors.disabledColor=Color(.6,.63,.68,.6);colors.fadeDuration=.08
    button.colors=colors
    hudUi.v8Nav[i]={root=root,rect=root:GetComponent(typeof(UnityEngine.RectTransform)),imageRect=rect}
    hudUi.v8Textures[i],hudUi.v8Sprites[i]=texture,sprite
  end
  if hudUi.activityDot then hudUi.activityDot.transform:SetAsLastSibling() end
  hudUi.v8Ready=true
end

-- V9 dense popup layouts. Presentation only: retain all original click handlers.
-- Content count determines panel height; 44-unit actions never fill entire cards.
hudUi.v8Panel=function(rect,width,height)
  local f=hudUi.astraFrame
  height=math.min(height,f.modalHeight)
  setRect(rect,Vector2(.5,1),Vector2(.5,1),Vector2(0,-math.floor(f.modalTop+math.min(34,(f.modalHeight-height)*.25))),Vector2(width,height))
  return height
end

hudUi.layoutMore=function(portrait)
  local m,f,p=hudUi.more,hudUi.astraFrame,hudUi.v8Place
  if not m.panelRect then return end
  local width=math.min(portrait and 404 or 720,f.width-32)
  local inner=width-24;local cols=portrait and 1 or 2;local gap=10
  local cw=(inner-(cols-1)*gap)/cols
  local rows=math.ceil(#m.routes/cols)
  local ch=portrait and math.max(132,math.min(170,math.floor((f.modalHeight-80)/rows))) or 190
  local height=hudUi.v8Panel(m.panelRect,width,portrait and math.min(f.modalHeight,70+rows*(ch+gap)) or 70+ch)
  p(m.eyebrow.rectTransform,14,7,width-84,15)
  p(m.title.rectTransform,14,20,width-84,23)
  p(m.status.rectTransform,14,43,width-84,18)
  p(m.closeRect,width-50,4,44,44)
  m.diagnosticRect.gameObject:SetActive(false)
  m.diagnosticText.gameObject:SetActive(false)
  m.showDiagnostics=false
  for i,r in ipairs(m.routes) do
    local x=12+(i-1)%cols*(cw+gap)
    local y=66+math.floor((i-1)/cols)*(ch+gap)
    r.rect.gameObject:SetActive(true)
    p(r.rect,x,y,cw,ch)
    local artH=portrait and math.max(74,ch-66) or 122
    p(r.artRect,6,6,cw-12,artH)
    p(r.artShadeRect,6,6,cw-12,artH)
    p(r.title.rectTransform,12,artH+9,cw-104,22)
    p(r.subtitleText.rectTransform,12,artH+31,cw-24,20)
    -- World-display badge was removed; do not dereference its deleted label.
    r.subtitleText.horizontalOverflow=UnityEngine.HorizontalWrapMode.Wrap
  end
end

-- ACTION-PROPORTIONS-0911: compact painted surface, unchanged 44-unit touch area.
hudUi.compactAction=function(rect)
  local root=rect.gameObject
  local hit=root:GetComponent(typeof(UnityEngine.UI.Image))
  if hit==nil then hit=root:AddComponent(typeof(UnityEngine.UI.Image)) end
  hit.color=Color(1,1,1,0);hit.raycastTarget=true
  local rim=root.transform:Find(tostring(root.name).."_OuterHighlight")
  if rim then
    local r=rim:GetComponent(typeof(UnityEngine.RectTransform))
    r.offsetMin,r.offsetMax=Vector2(4,7),Vector2(-4,-7)
  end
end

hudUi.layoutCheckIn=function(portrait)
  local f,p=hudUi.astraFrame,hudUi.v8Place
  if not hudUi.checkInPanelRect then return end
  local width=math.min(portrait and 418 or 620,f.width-32)
  local inner=width-24;local gap=8
  local tight=f.modalHeight<(portrait and 396 or 300)
  local ch=tight and (portrait and 82 or 78) or 90
  local featureW=portrait and inner or 168
  local gridW=portrait and inner or inner-featureW-gap
  local cw=(gridW-2*gap)/3
  local gridH=2*ch+gap
  local featureH=portrait and (tight and 72 or 88) or gridH
  local contentH=portrait and gridH+gap+featureH or gridH
  local header,footer=tight and 48 or 64,tight and 44 or 48
  local height=hudUi.v8Panel(hudUi.checkInPanelRect,width,header+contentH+footer)
  p(hudUi.checkInTitle.rectTransform,12,8,90,24)
  p(hudUi.checkInProgress.rectTransform,tight and 12 or 110,tight and 28 or 8,tight and width-66 or width-164,tight and 18 or 24)
  p(hudUi.checkInCloseRect,width-50,0,44,44)
  p(hudUi.checkInSubtitle.rectTransform,12,38,width-24,20)
  hudUi.checkInProgress.fontSize=10;hudUi.checkInTiny=false
  hudUi.checkInSubtitle.gameObject:SetActive(not tight)
  hudUi.astraLayoutScroll(hudUi.checkInScroll,12,header,inner,height-header-footer,contentH)
  hudUi.checkInScrollable=hudUi.checkInScroll.scroll.vertical
  for day,r in ipairs(hudUi.checkInRows) do
    if day<7 then
      p(r.rect,(day-1)%3*(cw+gap),math.floor((day-1)/3)*(ch+gap),cw,ch)
      p(r.dayLabel.rectTransform,8,2,cw-16,tight and 14 or 18)
      p(r.value.rectTransform,8,tight and 16 or 22,cw-16,tight and 16 or 18)
      r.value.text=day==1 and "1,000 金币" or "500 金币"
      r.value.fontSize=11;r.caption.gameObject:SetActive(false)
      local bw=math.min(96,cw-12)
      p(r.actionRect,(cw-bw)/2,ch-46,bw,44)
    else
      local fw,fh=featureW,featureH
      p(r.rect,portrait and 0 or gridW+gap,portrait and gridH+gap or 0,fw,fh)
      p(r.dayLabel.rectTransform,10,4,fw-20,20)
      r.value.gameObject:SetActive(false)
      p(r.badge.rect,10,portrait and 24 or 40,math.min(146,fw-20),portrait and 24 or 28)
      r.badge.label.fontSize=12
      r.caption.text="永久称号 · 外观中穿戴";r.caption.fontSize=10
      p(r.caption.rectTransform,10,portrait and 50 or 84,portrait and fw-110 or fw-20,20)
      r.caption.alignment=UnityEngine.TextAnchor.MiddleLeft;r.caption.gameObject:SetActive(true)
      p(r.actionRect,portrait and fw-102 or (fw-96)/2,fh-50,96,44)
    end
    hudUi.compactAction(r.actionRect)
    r.actionLabel.fontSize=11;r.actionLabel.rectTransform.localScale=Vector3.one
  end
  p(hudUi.checkInFooter.rectTransform,12,height-46,width-98,44)
  p(hudUi.checkInRetryRect,width-78,height-46,66,44)
  hudUi.compactAction(hudUi.checkInRetryRect)
  hudUi.checkInFooter.fontSize=10
  hudUi.checkInFooter.gameObject:SetActive(true);hudUi.checkInRetryRect.gameObject:SetActive(true)
end

hudUi.v9Card=function(r,w,h,shop)
  local p=hudUi.v8Place
  r.idText.gameObject:SetActive(false);r.concept.root:SetActive(false)
  r.status.root:SetActive(not shop)
  local art=r.itemId=="WING_01" or r.itemId=="HALO_01"
  r.icon:SetActive(not art and r.veteranBadge==nil)
  r.category.glyphSize=10;setGlyphLine(r.category,r.category.value)
  p(r.category.rect,8,2,w-16,18)
  if shop then
    r.category.root:SetActive(false);r.priceText.gameObject:SetActive(false)
    p(r.artRect,10,2,w-20,80)
    if not r.v9NameBand then
      local _,nr=addImage(r.core,"ShopNameBand",Vector2.zero,Vector2.zero,Vector2.zero,Vector2.zero,Color(.025,.035,.05,.72),nil,false,false)
      r.v9NameBand=nr;r.itemName.rect:SetAsLastSibling()
    end
    p(r.v9NameBand,0,82,w,20)
    r.itemName.alignment="center";setGlyphLine(r.itemName,r.itemName.value)
    p(r.itemName.rect,4,82,w-8,20)
    p(r.actionRect,0,102,w,44)
    if not r.v9PriceBar then
      r.actionLabel.rect:SetParent(r.actionRoot.transform,false)
      for j=0,r.actionRoot.transform.childCount-1 do
        local child=r.actionRoot.transform:GetChild(j).gameObject
        if child~=r.actionLabel.root then child:SetActive(false) end
      end
      local _,br,bi=addImage(r.actionRoot,"ShopPriceBar",Vector2.zero,Vector2.zero,Vector2.zero,Vector2.zero,Color(.08,.12,.17,.9),nil,false,false)
      r.v9PriceBar=br;r.actionButton.targetGraphic=bi
      r.v9Coin=addCoinIcon(r.actionRoot,"ShopPriceCoin",Vector2.zero,Vector2.zero,Color(1,.78,.3,1)):GetComponent(typeof(UnityEngine.RectTransform))
      r.actionLabel.rect:SetAsLastSibling()
    end
    p(r.v9PriceBar,0,10,w,24)
    p(r.v9Coin,w/2-33,16,12,12)
    r.actionLabel.glyphSize=12;r.actionLabel.alignment="left"
    setGlyphLine(r.actionLabel,r.actionLabel.value)
  else
    p(r.artRect,8,22,36,36);p(r.iconRect,8,22,36,36)
    p(r.itemName.rect,50,20,w-58,22)
    p(r.status.rect,50,40,w-58,20)
    p(r.priceText.rectTransform,50,40,w-58,20)
    if r.veteranBadge then
      r.itemName.root:SetActive(false)
      p(r.veteranBadge.rect,8,23,math.min(146,w-16),24)
      r.veteranBadge.label.fontSize=12
      p(r.status.rect,8,44,w-16,16)
      r.status.glyphSize=10;setGlyphLine(r.status,r.status.value)
    end
    p(r.actionRect,w-92,h-46,84,44)
    hudUi.compactAction(r.actionRect)
    r.actionLabel.glyphSize=11;setGlyphLine(r.actionLabel,r.actionLabel.value)
  end
  r.actionLabel.rect.anchorMin,r.actionLabel.rect.anchorMax=Vector2.zero,Vector2.one
  r.actionLabel.rect.offsetMin,r.actionLabel.rect.offsetMax=Vector2.zero,Vector2.zero
  if shop then p(r.actionLabel.rect,w/2-17,10,w/2+13,24) end
end

hudUi.layoutCommerce=function(portrait)
  if not hudUi.commercePanelRect or not hudUi.astraFrame then return end
  local f,p,mode=hudUi.astraFrame,hudUi.v8Place,tostring(hudUi.commerceMode or "appearance")
  local shop=mode=="shop";local appearance=mode=="appearance"
  local compact=not portrait and f.modalHeight<296
  local width=math.min(shop and 360 or portrait and 418 or 560,f.width-32)
  local inner=width-24;local cols=2;local gap=8
  if appearance and compact then cols=1;gap=4 end
  -- Shop uses a compact row per product on narrow screens. Appearance stays 2x2.
  -- Both orientations keep the two available products together, like an inventory grid.
  local cw=(inner-(cols-1)*gap)/cols
  local ch=shop and 146 or (compact and 44 or 108)
  local count=shop and #hudUi.shopRows or #hudUi.appearanceRows
  local gridH=math.ceil(count/cols)*(ch+gap)-gap
  local header,footer=44,(appearance and compact) and 4 or 8
  local contentH=appearance and gridH+20 or shop and gridH+24 or 204
  local height=hudUi.v8Panel(hudUi.commercePanelRect,width,header+contentH+footer)
  p(hudUi.commerceTitle.rect,12,8,width-70,24)
  hudUi.commerceTitle.alignment="left";setGlyphLine(hudUi.commerceTitle,hudUi.commerceTitle.value)
  p(hudUi.commerceCloseRect,width-50,0,44,44)
  p(hudUi.commerceHeaderRuleRect,12,40,inner,1)
  local available=height-header-footer
  local scrollNeeded=contentH>available+1
  if scrollNeeded then footer=24;available=height-header-footer end
  hudUi.astraLayoutScroll(hudUi.commerceScroll,12,header,inner,available,contentH)
  p(hudUi.commerceScrollHint.rect,12,height-22,inner,18)
  hudUi.commerceScrollHint.root:SetActive(scrollNeeded)
  for _,rect in ipairs({hudUi.appearancePageRect,hudUi.shopPageRect,hudUi.sponsorPageRect}) do
    rect.anchorMin,rect.anchorMax=Vector2.zero,Vector2.one;rect.offsetMin,rect.offsetMax=Vector2.zero,Vector2.zero
  end
  for i,r in ipairs(hudUi.appearanceRows) do
    local ac=compact and 1 or 2;local ag=compact and 4 or 8
    local aw=(inner-(ac-1)*ag)/ac
    local ah=compact and 44 or 108
    p(r.rect,(i-1)%ac*(aw+ag),math.floor((i-1)/ac)*(ah+ag),aw,ah)
    hudUi.v9Card(r,aw,ah,false)
    if compact then
      p(r.artRect,4,8,28,28);p(r.iconRect,4,8,28,28)
      p(r.category.rect,40,0,146,18);p(r.itemName.rect,40,18,146,22)
      p(r.status.rect,196,10,aw-292,24)
      if r.veteranBadge then p(r.veteranBadge.rect,40,18,146,24)end
      p(r.actionRect,aw-84,0,84,44)
    end
  end
  p(hudUi.appearanceStatus.rect,0,compact and 188 or 224,inner,20)
  p(hudUi.shopStatus.rect,0,0,inner,20)
  for i,r in ipairs(hudUi.shopRows) do
    p(r.rect,(i-1)%cols*(cw+gap),24+math.floor((i-1)/cols)*(ch+gap),cw,ch)
    hudUi.v9Card(r,cw,ch,true)
  end
  hudUi.sponsorPoolText.alignment=UnityEngine.TextAnchor.MiddleLeft
  hudUi.sponsorMineText.alignment=UnityEngine.TextAnchor.MiddleLeft
  local metricW=(inner-8)/2
  p(hudUi.sponsorState.rect,0,0,inner,20)
  p(hudUi.sponsorPoolLabel.rect,0,24,metricW,18)
  p(hudUi.sponsorMineLabel.rect,metricW+8,24,metricW,18)
  p(hudUi.sponsorPoolText.rectTransform,0,44,metricW,22)
  p(hudUi.sponsorMineText.rectTransform,metricW+8,44,metricW,22)
  p(hudUi.sponsorAmountLabel.rect,0,66,136,18)
  p(hudUi.sponsorDebitHint.rect,140,66,inner-140,18)
  p(hudUi.sponsorInputRect,0,88,inner-100,44)
  p(hudUi.sponsorSubmitRect,inner-92,88,92,44)
  local qw=(inner-24)/5
  for i,q in ipairs(hudUi.sponsorQuickButtons) do p(q.rect,(i-1)*(qw+6),138,qw,44) end
  p(hudUi.sponsorMessage.rect,0,184,inner,20)
  p(hudUi.sponsorRangeLabel.rect,0,184,100,20)
  p(hudUi.sponsorRangeText.rectTransform,100,184,inner-100,20)
  hudUi.sponsorSubmitLabel.rect.anchorMin,hudUi.sponsorSubmitLabel.rect.anchorMax=Vector2.zero,Vector2.one
  hudUi.sponsorSubmitLabel.rect.offsetMin,hudUi.sponsorSubmitLabel.rect.offsetMax=Vector2.zero,Vector2.zero
  if hudUi.sponsorPromptRect then
    p(hudUi.sponsorPromptRect,f.hudLeft,f.promptTop,190,44)
    p(hudUi.sponsorPromptLabel.rect,12,10,130,24)
    setRect(hudUi.sponsorPromptPool.rectTransform,Vector2(1,.5),Vector2(1,.5),Vector2(-12,0),Vector2(46,24))
  end
end

local function layoutHud()
  if not hudRects or not hudSafeRect then return end
  hudUi.v8Init()
  local width,height=math.max(1,UnityEngine.Screen.width),math.max(1,UnityEngine.Screen.height)
  local safe=UnityEngine.Screen.safeArea;local portrait=height>width
  local scale=math.min(width,height)/450
  local lw,lh=safe.width/scale,safe.height/scale
  local key=table.concat({width,height,safe.x,safe.y,safe.width,safe.height,tostring(hudUi.resultsHasFinishers),resultsVisibleCount,tostring(hudUi.commerceMode),tostring(hudUi.hasParticipationHint)},"|")
  if key==lastLayoutKey then return end
  -- Commit only after the complete layout succeeds, so failures can retry.
  hudSafeRect.anchorMin,hudSafeRect.anchorMax=Vector2(safe.xMin/width,safe.yMin/height),Vector2(safe.xMax/width,safe.yMax/height)
  hudSafeRect.offsetMin,hudSafeRect.offsetMax=Vector2.zero,Vector2.zero
  hudScaler.uiScaleMode=UnityEngine.UI.CanvasScaler.ScaleMode.ScaleWithScreenSize
  hudScaler.referenceResolution=Vector2(width/scale,height/scale)
  hudScaler.screenMatchMode=UnityEngine.UI.CanvasScaler.ScreenMatchMode.MatchWidthOrHeight;hudScaler.matchWidthOrHeight=0
  local p=hudUi.v8Place
  local left=portrait and 16 or math.max(48,lw*.10)
  local top=portrait and 88 or 24
  local navTop=portrait and 142 or top-5
  local navLeft=portrait and left or left+280
  -- Reflow, never squash, if the native host controls leave too little width.
  if not portrait and navLeft+4*52>lw-154 then navLeft=left;navTop=top+52 end
  local hintY=top+36
  local modalTop=portrait and 214 or math.max(90,navTop+58)
  hudUi.astraFrame={width=lw,height=lh,short=lh<460,modalTop=modalTop,
    modalHeight=math.max(152,lh-modalTop-(portrait and 114 or 60)),hudLeft=left,promptTop=portrait and 186 or navTop+48}
  p(hudRects[1],left,top,174,32);hudRects[1].localScale=Vector3.one
  p(hudUi.phaseIconRect,8,10,12,12)
  for _,entry in pairs(hudUi.phaseImageEntries) do p(entry.rect,25,5,60,22);entry.image.label.fontSize=12 end
  p(hudUi.timerIconRect,99,10,12,12);p(hudUi.timerTextRect,118,5,49,22)
  p(hudUi.statusDividerRects[1],90,8,1,16)
  hudUi.statusDividerRects[2].gameObject:SetActive(false);hudUi.statusDividerRects[3].gameObject:SetActive(false)
  hudUi.rankCaptionRect.gameObject:SetActive(false);hudUi.rankTextRect.gameObject:SetActive(false)
  hudUi.statusProgressRect.gameObject:SetActive(false);hudPhaseAccent.gameObject:SetActive(false)
  p(hudUi.v8CoinRect,left+182,top,86,32)
  p(hudUi.coinIconRect,9,10,12,12);p(hudUi.coinTextRect,28,1,53,30)
  hudTimer.fontSize,hudCoins.fontSize=12,string.find(hudCoinSnapshot or "","\n",1,true) and 10 or 12
  hudTimer.color=Color(.96,.98,1,1);hudCoins.color=Color(1,.79,.35,1)
  p(hudUi.v8HintRect,left,hintY,202,22)
  p(hudUi.participationHint.rectTransform,6,1,190,20)
  hudUi.participationHint.fontSize=10;hudUi.participationHint.alignment=UnityEngine.TextAnchor.MiddleLeft
  hudUi.v8HintRoot:SetActive(hudUi.hasParticipationHint==true)
  for i,nav in ipairs(hudUi.v8Nav) do p(nav.rect,navLeft+(i-1)*52,navTop,44,44) end
  if hudUi.activityDot then p(hudUi.activityDot:GetComponent(typeof(UnityEngine.RectTransform)),34,2,5,5) end
  hudUi.layoutCommerce(portrait);hudUi.layoutCheckIn(portrait);hudUi.layoutMore(portrait)
  hudRects[4].anchorMin,hudRects[4].anchorMax=Vector2.zero,Vector2.one
  hudRects[4].offsetMin,hudRects[4].offsetMax=Vector2.zero,Vector2.zero
  local pw=math.min(portrait and 418 or 650,lw-32);local inner=pw-32
  local step=portrait and 44 or 26;local header,footer=64,20
  local contentH=resultsVisibleCount*step
  local ph=hudUi.v8Panel(resultsPanelRect,pw,hudUi.resultsHasFinishers and header+contentH+footer or 150)
  p(hudUi.resultsTitleBitmapRect,16,6,pw-90,28)
  hudUi.resultsTitleRect.gameObject:SetActive(false);hudUi.resultsSubtitleRect.gameObject:SetActive(false);hudUi.resultsSubtitleBitmapRect.gameObject:SetActive(false)
  p(hudUi.resultsCloseRect,pw-52,2,44,44)
  p(hudUi.resultsFormula.rect,110,8,inner-160,24);hudUi.resultsFormula.root:SetActive(hudUi.resultsHasFinishers)
  p(hudUi.resultsHeaderRect,16,40,inner,22)
  local rankW,crewX=28,36
  local coinsW=portrait and 0 or 200
  local coinsX=inner-coinsW-8;local timeW=80
  local timeX=portrait and inner-timeW-8 or coinsX-timeW-16
  local crewW=timeX-crewX-12
  p(hudUi.resultsHeaderBitmaps.rank.rect,0,0,rankW,22)
  hudUi.resultsHeaderBitmaps.rank.image.label.alignment=UnityEngine.TextAnchor.MiddleCenter
  p(hudUi.resultsNameHeader.rect,crewX,0,crewW,22)
  hudUi.resultsHeaderBitmaps.crew.rect.gameObject:SetActive(false)
  p(hudUi.resultsHeaderBitmaps.time.rect,timeX,0,timeW,22)
  hudUi.resultsHeaderBitmaps.time.image.label.alignment=UnityEngine.TextAnchor.MiddleRight
  p(hudUi.resultsCoinsHeader.rect,coinsX,0,coinsW,22);hudUi.resultsCoinsHeader.root:SetActive(not portrait)
  hudUi.astraLayoutScroll(hudUi.resultsScroll,16,header,inner,math.max(44,ph-header-footer),contentH)
  hudUi.resultsScroll.root:SetActive(hudUi.resultsHasFinishers)
  p(hudUi.resultsScrollHint.rect,16,ph-22,inner,18)
  hudUi.resultsScrollHint.root:SetActive(hudUi.resultsHasFinishers and hudUi.resultsScroll.scroll.vertical)
  for i,row in ipairs(resultsRows) do
    p(row.rect,0,(i-1)*step,inner,step-2)
    p(row.rank.rectTransform,0,3,rankW,22);row.rank.alignment=UnityEngine.TextAnchor.MiddleCenter
    p(row.crew.rectTransform,crewX,3,crewW,22)
    p(row.time.rectTransform,timeX,3,timeW,22);row.time.alignment=UnityEngine.TextAnchor.MiddleRight
    row.crewRoot:SetActive(false);row.timeGlyphRoot:SetActive(false)
    row.maxGlyphs=math.max(3,math.floor(crewW/12))
    p(row.coins.rectTransform,portrait and 70 or coinsX,portrait and 22 or 3,portrait and inner-78 or coinsW,18)
    p(row.coinsLabel.rect,portrait and crewX or coinsX,portrait and 22 or 3,portrait and 32 or coinsW,18)
    row.coinsLabel.root:SetActive(portrait or row.coinsPending==true)
    if row.lastNickname then setNicknameLabel(row,row.lastNickname) end
  end
  hudUi.resultsEmptyRect.anchorMin,hudUi.resultsEmptyRect.anchorMax=Vector2.zero,Vector2.one
  hudUi.resultsEmptyRect.offsetMin,hudUi.resultsEmptyRect.offsetMax=Vector2.zero,Vector2.zero
  p(hudUi.resultsEmptyIconRect,(pw-28)/2,66,28,28)
  p(hudUi.resultsEmptyLabelRect,20,108,pw-40,26)
  hudUi.resultsEmptyLabelRect:GetComponent(typeof(UnityEngine.UI.Text)).alignment=UnityEngine.TextAnchor.MiddleCenter
  -- One bounded pass only when layout changes; no per-frame hierarchy scan.
  local labels=hudRoot:GetComponentsInChildren(typeof(UnityEngine.UI.Text),true)
  for i=0,labels.Length-1 do
    local label=labels[i]
    if label.fontSize>12 then label.fontSize=12 end
    label.resizeTextForBestFit=false
    -- Scaling a centered label keeps half-unit sizes exact and survives data refresh.
    -- Do not shrink close glyphs, input contents, body text, artwork or touch areas.
    local name=tostring(label.gameObject.name)
    local action=name=="ClaimLabel" or name=="RefreshLabel" or name=="EnterLabel"
      or string.find(name,"ActionLabel",1,true)~=nil
      or string.find(name,"SponsorSubmitLabel",1,true)~=nil
      or string.find(name,"SponsorPromptLabel",1,true)~=nil
      or string.find(name,"SponsorQuick",1,true)~=nil
    if action then label.rectTransform.localScale=Vector3(.5,.5,1) end
    if name=="ClaimLabel" or name=="RefreshLabel" or
      (string.sub(name,1,10)=="Appearance" and string.find(name,"ActionLabel",1,true)) then
      label.fontSize=11;label.rectTransform.localScale=Vector3.one
    end
    if string.sub(name,1,4)=="Shop" and string.find(name,"ActionLabel",1,true) then label.rectTransform.localScale=Vector3.one end
  end
  lastLayoutKey=key
end

local function csvFlagSet(value)
  local result = {}
  for token in string.gmatch(tostring(value or "") .. ",", "([^,]*),") do
    token = string.gsub(token, "^%s+", "")
    token = string.gsub(token, "%s+$", "")
    if token ~= "" then result[token] = true end
  end
  return result
end

local function csvPairMap(value)
  local result = {}
  for token in string.gmatch(tostring(value or "") .. ",", "([^,]*),") do
    local key, mapped = string.match(token, "^([^=]+)=([^=]+)$")
    if key ~= nil and mapped ~= nil then result[tostring(key)] = tostring(mapped) end
  end
  return result
end

local function formatInteger(value)
  local digits = tostring(math.max(0, math.floor(tonumber(value) or 0)))
  while true do
    local nextValue, replacements = string.gsub(digits, "^(%d+)(%d%d%d)", "%1,%2")
    digits = nextValue
    if replacements == 0 then break end
  end
  return digits
end

local function localIsRaceParticipant()
  local ok, vehicleName = pcall(localVehicleName)
  return ok and tostring(vehicleName or "") ~= ""
end

-- Entry is based on this cycle's frozen seat roster, not cloud readiness.
-- Submission additionally needs matching authority data, an open clock, and cloud membership.
hudUi.evaluateSponsorAccess = function(state, cycleId, remaining, frozenCycle, rosterParticipant)
  hudUi.currentRaceState = state
  local currentRoster = cycleId > 0 and frozenCycle == cycleId
  hudUi.localParticipant = currentRoster and rosterParticipant == true
  hudUi.sponsorEntryVisible = state == "WAITING" and hudUi.localParticipant and (remaining == nil or remaining ~= 0)
  local status = hudUi.sponsorReadiness or "SYNCING"
  if state == "" or remaining == nil or remaining ~= remaining or remaining < 0 or remaining == math.huge then status = "CLOCK_SYNCING"
  elseif cycleId <= 0 then status = "CYCLE_SYNCING"
  elseif state ~= "WAITING" or remaining <= 0 then status = "CLOSED"
  elseif not currentRoster then status = "ROSTER_SYNCING"
  elseif not hudUi.localParticipant then status = "NOT_PARTICIPANT"
  elseif not hudUi.sponsorAvailable then status = "UNAVAILABLE"
  elseif hudUi.sponsorCycleId ~= cycleId or hudUi.sponsorPhase ~= state then status = "CYCLE_SYNCING"
  elseif hudUi.sponsorConfigured == false then status = "DISABLED"
  elseif hudUi.sponsorIdentityReady == false then status = "IDENTITY_SYNCING"
  elseif status == "READY" and hudUi.sponsorEconomyParticipant ~= true then status = "IDENTITY_SYNCING"
  elseif status == "READY" and (not hudUi.sponsorEnabled or hudUi.sponsorFrozen) then status = "CLOSED" end
  hudUi.sponsorDisplayStatus = status
  hudUi.sponsorEligible = hudUi.sponsorEntryVisible and status == "READY" and hudUi.sponsorEnabled
    and not hudUi.sponsorFrozen and hudUi.sponsorEconomyParticipant == true
end

hudUi.refreshSponsorAccess = function()
  local state, cycleId, remaining = "", 0, nil
  if resolveManagerHolders() then
    pcall(function() state = tostring(managerHolder.script.GetRaceManagerState() or "") end)
    pcall(function() cycleId = math.floor(tonumber(managerHolder.script.GetRaceManagerCycleId()) or 0) end)
    pcall(function() remaining = tonumber(managerHolder.script.GetRaceManagerRemainingMilliseconds()) end)
  end
  hudUi.evaluateSponsorAccess(state, cycleId, remaining, rosterCycleId, localIsRaceParticipant())
end

-- SPONSOR-AUTO-0912: one local prompt per confirmed eligible race cycle.
hudUi.tickAutoSponsor = function()
  if hudUi.commerceMode=="sponsor" and (hudUi.currentRaceState~="WAITING" or not hudUi.localParticipant) then
    hudUi.closeCommerce()
    return false
  end
  local cycle=tonumber(hudUi.sponsorCycleId) or 0
  if cycle<=0 or not hudUi.sponsorEligible or hudUi.currentRaceState~="WAITING"
    or hudUi.autoSponsorCycle==cycle then return false end
  if hudUi.commerceMode=="sponsor" then hudUi.autoSponsorCycle=cycle;return false end
  local previous=hudUi.autoSponsorCycle
  hudUi.autoSponsorCycle=cycle
  local ok,opened=pcall(RaceSessionUiOpenSponsor)
  if not ok or opened~=true then hudUi.autoSponsorCycle=previous;return false end
  return true
end

hudUi.updateSponsorPrompt = function()
  hudUi.refreshSponsorAccess()
  local resultsVisible = resultsRoot ~= nil and resultsRoot.activeSelf
  if sponsorPromptRoot ~= nil then sponsorPromptRoot:SetActive(hudUi.sponsorEntryVisible == true
    and hudUi.commerceMode == "closed" and not resultsVisible and not hudUi.checkInOpen and not hudUi.more.open) end
end

hudUi.sponsorStatusLabel = function()
  local status = hudUi.sponsorDisplayStatus or "SYNCING"
  local labels = { CLOSED="仅等待阶段开放", DISABLED="本局赞助未开放", TOO_FEW="参赛人数不足",
    CLOCK_SYNCING="等待赞助开放", CYCLE_SYNCING="等待赞助开放", ROSTER_SYNCING="等待赞助开放",
    IDENTITY_SYNCING="等待赞助开放", NOT_PARTICIPANT="仅参赛玩家可赞助", UNAVAILABLE="等待赞助开放",
    SYNCING="等待赞助开放" }
  if status == "RETRYING" then
    return "等待赞助开放"
  end
  if status ~= "READY" then return labels[status] or "等待赞助开放" end
  if not hudUi.economyCanTransact then return "等待赞助开放" end
  if (hudUi.economyPending or 0) > 0 then return "操作等待确认" end
  if hudUi.sponsorPersonal >= (hudUi.sponsorMaxAmount or 5000) then return "累计金额已达上限" end
  if hudUi.economyCoins < (hudUi.sponsorMinAmount or 10) then return "金币不足" end
  return "赞助已开放"
end

local function setCommerceAction(row, label, enabled)
  if row == nil then return end
  if row.isShop and label=="购买" then
    local item=hudUi.economyCatalog[row.itemId]
    label=formatInteger(math.max(0,tonumber(item and item.price) or 0))
  end
  if row.isShop and row.v9Coin then row.v9Coin.gameObject:SetActive(label~="已拥有") end
  setGlyphLine(row.actionLabel, label)
  if row.actionButton ~= nil then row.actionButton.interactable = enabled == true end
  if row.actionButton~=nil and row.actionButton.targetGraphic~=nil then row.actionButton.targetGraphic.color=enabled and Color(0.86,0.64,0.31,1) or Color(0.13,0.19,0.28,1)end
  row.actionLabel.color=enabled and Color(0.055,0.075,0.11,1) or Color(0.74,0.80,0.87,1)
  if row.isShop then
    row.actionButton.targetGraphic.color=enabled and Color(.15,.20,.26,.96) or Color(.08,.11,.15,.92)
    row.actionLabel.color=enabled and Color(1,.82,.43,1) or Color(.64,.69,.75,1)
  end
  setGlyphLine(row.actionLabel,label)
end

local function economyReasonLabel(reason, success)
  reason = tostring(reason or "")
  if reason == "QUEUED" then return "已提交待确认" end
  if reason == "PURCHASED" or reason == "DUPLICATE" then return "购买成功" end
  if reason == "ALREADY_OWNED" then return "已拥有" end
  if reason == "EQUIPPED" then return "穿戴成功" end
  if reason == "UNEQUIPPED" then return "已卸下" end
  if reason == "SPONSOR_CONFIRMED" then return "赞助成功" end
  if reason == "SPONSOR_DEBITED" then return "已扣款，等待房间确认" end
  if reason == "LATE_SPONSOR_REFUNDED" then return "未赶上本局锁定，金币已退回" end
  if reason == "COINS_NOT_ENOUGH" then return "金币不足" end
  if reason == "NOT_OWNED" then return "尚未拥有" end
  if reason == "IDENTITY_PENDING" then return "请稍后重试" end
  if reason == "NOT_RACE_PARTICIPANT" then return "仅参赛玩家可赞助" end
  if reason == "AMOUNT_OUT_OF_RANGE" then return "金额超出范围" end
  if reason == "SPONSOR_LIMIT" then return "累计金额已达上限" end
  if reason == "SPONSOR_SYNCING" then return "请稍后重试" end
  if reason == "CATEGORY_MISMATCH" then return "外观类别不匹配" end
  if reason == "SPONSOR_CLOSED" then return "赞助已关闭" end
  if reason == "CLOUD_UNAVAILABLE" or reason == "SAVE_FAILED" then return "操作未完成，请重试" end
  if success then return "操作成功" end
  return "操作未完成"
end

local function responseReason(value)
  return string.match(tostring(value or ""), "reason=([^|]+)") or ""
end

hudUi.refreshCommerce = function()
  if commerceRoot == nil then return end
  local inventory, equipped = hudUi.economyInventory or {}, hudUi.economyEquipped or {}
  local dataReady = hudUi.economyAvailable and hudUi.economyInitialized
  local actionReady = dataReady and hudUi.economyCanTransact == true and math.floor(tonumber(hudUi.economyPending) or 0) == 0

  local titleRow = hudUi.appearanceRows and hudUi.appearanceRows[1] or nil
  if titleRow ~= nil then
    titleRow.priceText.text = ""
    if not hudUi.economyAvailable then
      setGlyphLine(titleRow.status, "")
      setCommerceAction(titleRow, "穿戴", false)
    elseif not hudUi.economyInitialized then
      setGlyphLine(titleRow.status, "")
      setCommerceAction(titleRow, "穿戴", false)
    elseif equipped.title == "TITLE_DEFAULT" then
      setGlyphLine(titleRow.status, "已穿戴")
      setCommerceAction(titleRow, "卸下", actionReady)
    elseif inventory.TITLE_DEFAULT then
      setGlyphLine(titleRow.status, "可穿戴替换")
      setCommerceAction(titleRow, "穿戴", actionReady)
    else
      setGlyphLine(titleRow.status, "尚未拥有")
      setCommerceAction(titleRow, "穿戴", false)
    end
  end
  local appearanceSpecs = {
    { hudUi.appearanceRows and hudUi.appearanceRows[2] or nil, "WING_01", "wing" },
    { hudUi.appearanceRows and hudUi.appearanceRows[3] or nil, "HALO_01", "halo" },
    { hudUi.appearanceRows and hudUi.appearanceRows[4] or nil, "TITLE_VETERAN_DRIVER", "title" },
  }
  for _, spec in ipairs(appearanceSpecs) do
    local row, itemId, category = spec[1], spec[2], spec[3]
    if row ~= nil then
      row.priceText.text = ""
      if not hudUi.economyAvailable then
        setGlyphLine(row.status, "")
        setCommerceAction(row, "穿戴", false)
      elseif not hudUi.economyInitialized then
        setGlyphLine(row.status, "")
        setCommerceAction(row, "穿戴", false)
      elseif equipped[category] == itemId then
        setGlyphLine(row.status, "已穿戴")
        setCommerceAction(row, "卸下", actionReady)
      elseif inventory[itemId] then
        setGlyphLine(row.status, "可穿戴替换")
        setCommerceAction(row, "穿戴", actionReady)
      else
        setGlyphLine(row.status, itemId=="TITLE_VETERAN_DRIVER" and "七日签到第7天解锁" or "尚未拥有")
        setCommerceAction(row, "穿戴", false)
      end
    end
  end
  if hudUi.appearanceStatus ~= nil then
    local appearanceMessage = hudUi.commerceMode == "appearance" and hudUi.lastCommerceMessage or ""
    if appearanceMessage == "" then
      appearanceMessage = "选择已拥有外观进行穿戴"
    end
    setGlyphLine(hudUi.appearanceStatus, appearanceMessage)
  end

  if hudUi.shopStatus ~= nil then
    if hudUi.commerceMode == "shop" and hudUi.lastCommerceMessage ~= "" then setGlyphLine(hudUi.shopStatus, hudUi.lastCommerceMessage)
    elseif math.floor(tonumber(hudUi.economyPending) or 0) > 0 then setGlyphLine(hudUi.shopStatus, "操作等待确认")
    else setGlyphLine(hudUi.shopStatus, "使用金币购买外观") end
  end
  for _, row in ipairs(hudUi.shopRows or {}) do
    local itemId = row.itemId
    local item = hudUi.economyCatalog[itemId] or { price = 0 }
    row.priceText.text = formatInteger(item.price).."  金币"
    if not hudUi.economyAvailable then
      setGlyphLine(row.status, "")
      setCommerceAction(row, "购买", false)
    elseif not hudUi.economyInitialized then
      setGlyphLine(row.status, "")
      setCommerceAction(row, "购买", false)
    elseif inventory[itemId] then
      setGlyphLine(row.status, "已拥有")
      setCommerceAction(row, "已拥有", false)
    else
      local enoughCoins = hudUi.economyCoins >= (tonumber(item.price) or 0)
      setGlyphLine(row.status, enoughCoins and "可购买" or "金币不足")
      setCommerceAction(row, "购买", actionReady and enoughCoins)
    end
  end

  if hudUi.sponsorPoolText ~= nil then hudUi.sponsorPoolText.text = formatInteger(hudUi.sponsorTotal) end
  if hudUi.sponsorMineText ~= nil then hudUi.sponsorMineText.text = formatInteger(hudUi.sponsorPersonal) end
  if hudUi.sponsorPromptPool ~= nil then hudUi.sponsorPromptPool.text = hudUi.sponsorEligible and formatInteger(hudUi.sponsorTotal) or "查看" end
  local sponsorState = hudUi.sponsorStatusLabel()
  local promptLabel = "比赛赞助"
  if hudUi.sponsorDisplayStatus == "DISABLED" then promptLabel = "赞助未开放"
  elseif hudUi.sponsorDisplayStatus == "TOO_FEW" then promptLabel = "赞助人数不足"
  end
  setGlyphLine(hudUi.sponsorPromptLabel, promptLabel)
  setGlyphLine(hudUi.sponsorState, sponsorState)
  local sponsorCanSubmit = hudUi.sponsorEligible and actionReady
    and sponsorState == "赞助已开放"
    and hudUi.economyCoins >= (hudUi.sponsorMinAmount or 10) and hudUi.sponsorPersonal < (hudUi.sponsorMaxAmount or 5000)
  if hudUi.sponsorSubmitButton ~= nil then
    hudUi.sponsorSubmitButton.interactable = sponsorCanSubmit
    if hudUi.sponsorSubmitButton.targetGraphic ~= nil then
      hudUi.sponsorSubmitButton.targetGraphic.color = sponsorCanSubmit and Color(0.86,0.64,0.31,1) or Color(0.13,0.19,0.28,1)
    end
  end
  if hudUi.sponsorSubmitLabel ~= nil then
    hudUi.sponsorSubmitLabel.color = sponsorCanSubmit and Color(0.08,0.09,0.12,1) or Color(0.74,0.80,0.87,1)
    setGlyphLine(hudUi.sponsorSubmitLabel, sponsorCanSubmit and "确认赞助" or "暂不可赞助")
  end
  for _, quick in ipairs(hudUi.sponsorQuickButtons or {}) do
    if quick.button ~= nil then quick.button.interactable = sponsorCanSubmit end
  end
  if hudUi.sponsorInput ~= nil then hudUi.sponsorInput.interactable = sponsorCanSubmit end
  local message = hudUi.lastCommerceMessage
  local showRange = message == "" and sponsorCanSubmit
  if not sponsorCanSubmit then message = sponsorState end
  if message == "" and not showRange then message = sponsorState end
  hudUi.sponsorMessage.root:SetActive(not showRange)
  hudUi.sponsorRangeLabel.root:SetActive(showRange)
  hudUi.sponsorRangeText.gameObject:SetActive(showRange)
  if showRange then
    hudUi.sponsorRangeText.text = formatInteger(hudUi.sponsorMinAmount or 10) .. " - " .. formatInteger(hudUi.sponsorMaxAmount or 5000)
  else
    setGlyphLine(hudUi.sponsorMessage, message)
  end
end

local function decodeLoadedCoinBalance(balance, initialized)
  local value = tonumber(balance)
  if initialized ~= true or value == nil or value ~= value or value == math.huge or value == -math.huge then return false, nil end
  return true, math.max(0, math.floor(value))
end

hudUi.coinPendingLabel = function(lastError)
  -- A transport state is never a balance. The default is display-only, not
  -- a cloud initialization or authorization to spend coins.
  return lastError~=nil and lastError~="" and lastError~="none" and "读取失败" or "读取中"
end

hudUi.resolveCoinDisplay = function(coins, initialized, displayBalance, confirmedKnown, source, lastError)
  -- STORAGE-REPAIR-0911: an unconfirmed zero is not a balance.
  local known = confirmedKnown == true or (confirmedKnown == nil and initialized == true)
  if not known then
    return lastError ~= nil and lastError ~= "" and lastError ~= "none" and "读取失败" or "读取中"
  end
  local value = tonumber(displayBalance)
  if value == nil then
    local loaded, confirmed = decodeLoadedCoinBalance(coins, initialized)
    value = loaded and confirmed or 0
  end
  if value ~= value or value == math.huge or value == -math.huge then value = 0 end
  local text = formatInteger(math.max(0, math.floor(value)))
  if source == "cache" or source == "cache-retry" then return text .. "\n缓存" end
  if source == "pending" then return text .. "\n待入账" end
  return text
end

hudUi.refreshEconomy = function(force, raceState)
  if not force and Time.unscaledTime < nextEconomyUpdateAt then return end
  nextEconomyUpdateAt = Time.unscaledTime + 0.50
  if hudUi.more and hudUi.more.showDiagnostics then lastLayoutKey="" end
  if raceState ~= nil then hudUi.currentRaceState = tostring(raceState or "") end
  local economyScript = resolveEconomyHolder() and economyHolder.script or nil
  hudUi.economyAvailable = economyScript ~= nil and economyScript.GetGeocoreEconomySnapshot ~= nil
  hudUi.economyCanTransact = false
  if hudUi.economyAvailable then
    local ok, coins, initialized, backend, inventoryCsv, equippedCsv, revision, lastError, pending, lastAction = pcall(function()
      return economyScript.GetGeocoreEconomySnapshot()
    end)
    if ok then
      local loaded, balance = decodeLoadedCoinBalance(coins, initialized)
      if loaded then hudUi.economyCoins = balance end
      hudUi.economyInitialized, hudUi.economyBackend = loaded, tostring(backend or "")
      hudUi.economyRevision, hudUi.economyLastError = math.max(0, math.floor(tonumber(revision) or 0)), tostring(lastError or "")
      hudUi.economyPending, hudUi.economyInFlight = math.max(0, math.floor(tonumber(pending) or 0)), 0
      hudUi.economyInventory = csvFlagSet(inventoryCsv)
      hudUi.economyEquipped = csvPairMap(equippedCsv)
      local displayBalance, confirmedKnown, displaySource, displayError = nil, initialized, backend, lastError
      if economyScript.GetGeocoreCoinDisplaySnapshot ~= nil then
        local read,value,known,source,err=pcall(economyScript.GetGeocoreCoinDisplaySnapshot)
        if read then displayBalance,confirmedKnown,displaySource,displayError=tonumber(value),known,source,err end
      end
      hudCoinSnapshot = hudUi.resolveCoinDisplay(coins, initialized, displayBalance,confirmedKnown,displaySource,displayError)
      lastAction = tostring(lastAction or "")
      if hudUi.economyLastActionSeen == nil then
        hudUi.economyLastActionSeen = lastAction
      elseif lastAction ~= "" and lastAction ~= hudUi.economyLastActionSeen then
        hudUi.economyLastActionSeen = lastAction
        local actionOk, actionReason = string.match(lastAction, "^(%a+)|([^|]+)")
        if commerceRoot ~= nil and commerceRoot.activeSelf then
          hudUi.lastCommerceMessage = economyReasonLabel(actionReason, actionOk == "true")
        end
      end
    else
      hudUi.economyAvailable, hudUi.economyInitialized = false, false
      -- No usable identity-bound snapshot: do not invent a zero or reuse a
      -- different account's old UI value after a module/session failure.
      hudCoinSnapshot = hudUi.coinPendingLabel("MODULE_READ_FAILED")
    end
  end
  if economyScript ~= nil and economyScript.GetGeocoreEconomyTransactionReadiness ~= nil then
    local read,canTransact,backend,reason,verified,testActive=pcall(economyScript.GetGeocoreEconomyTransactionReadiness)
    hudUi.economyCanTransact=read and canTransact==true
    hudUi.economyTransactionReason=read and tostring(reason or "") or "BACKEND_NOT_READY"
    hudUi.economyTestActive=read and testActive==true
  else
    hudUi.economyCanTransact=hudUi.economyInitialized and hudUi.economyBackend=="local"
  end
  if economyScript ~= nil and economyScript.GetGeocoreShopCatalog ~= nil then
    local ok, catalog = pcall(function() return economyScript.GetGeocoreShopCatalog() end)
    if ok then
      if type(catalog) == "string" then
        for row in string.gmatch(catalog .. "|", "([^|]*)|") do
          local itemId, category, displayName, price = string.match(row, "^([^%^]+)%^([^%^]+)%^([^%^]*)%^(%d+)$")
          if (itemId == "WING_01" or itemId == "HALO_01") and itemId ~= nil then
            hudUi.economyCatalog[itemId] = { category = tostring(category), displayName = tostring(displayName or ""), price = math.max(0, math.floor(tonumber(price) or 0)) }
          end
        end
      elseif type(catalog) == "table" then
        for _, itemId in ipairs({ "WING_01", "HALO_01" }) do
          local source = catalog[itemId]
          if type(source) == "table" then
            hudUi.economyCatalog[itemId] = {
              category = tostring(source.category or hudUi.economyCatalog[itemId].category),
              displayName = tostring(source.displayName or source.name or ""),
              price = math.max(0, math.floor(tonumber(source.price) or hudUi.economyCatalog[itemId].price)),
            }
          end
        end
      end
    end
  end
  hudUi.sponsorAvailable = economyScript ~= nil and economyScript.GetGeocoreSponsorSnapshot ~= nil
  hudUi.sponsorReadiness, hudUi.sponsorReadError = "SYNCING", "none"
  hudUi.sponsorIdentityReady, hudUi.sponsorEconomyParticipant = false, false
  hudUi.sponsorConfigured = nil
  if hudUi.sponsorAvailable then
    local ok, enabled, frozen, participant, localAmount, playerSponsor, systemSponsor, pool, revision, cycleId, participantCount, minimumAmount, maximumAmount, sponsorPhase = pcall(function()
      return economyScript.GetGeocoreSponsorSnapshot()
    end)
    if ok then
      hudUi.sponsorEnabled, hudUi.sponsorFrozen = enabled == true, frozen == true
      hudUi.sponsorEconomyParticipant = participant == true
      hudUi.sponsorPersonal = math.max(0, math.floor(tonumber(localAmount) or 0))
      hudUi.sponsorPlayerTotal, hudUi.sponsorSystemTotal = math.max(0, math.floor(tonumber(playerSponsor) or 0)), math.max(0, math.floor(tonumber(systemSponsor) or 0))
      hudUi.sponsorTotal, hudUi.sponsorRevision = math.max(0, math.floor(tonumber(pool) or 0)), math.max(0, math.floor(tonumber(revision) or 0))
      hudUi.sponsorCycleId, hudUi.sponsorParticipantCount = math.max(0, math.floor(tonumber(cycleId) or 0)), math.max(0, math.floor(tonumber(participantCount) or 0))
      hudUi.sponsorMinAmount, hudUi.sponsorMaxAmount = math.max(1, math.floor(tonumber(minimumAmount) or 10)), math.max(1, math.floor(tonumber(maximumAmount) or 5000))
      hudUi.sponsorPhase = tostring(sponsorPhase or "")
    else
      hudUi.sponsorAvailable, hudUi.sponsorEnabled, hudUi.sponsorFrozen = false, false, false
    end
  end
  if economyScript ~= nil and economyScript.GetGeocoreSponsorReadiness ~= nil then
    local ok, status, reason, pending, retry, cycle, phase, configured, minimum, locked, identityReady = pcall(economyScript.GetGeocoreSponsorReadiness)
    if ok and tonumber(cycle) == hudUi.sponsorCycleId and tostring(phase or "") == hudUi.sponsorPhase then
      hudUi.sponsorReadiness, hudUi.sponsorReadError = tostring(status or "SYNCING"), tostring(reason or "none")
      hudUi.sponsorReadPending, hudUi.sponsorRetrySeconds = tonumber(pending) or 0, tonumber(retry) or 0
      hudUi.sponsorConfigured, hudUi.sponsorMinimumParticipants = configured == true, tonumber(minimum) or 1
      hudUi.sponsorIdentityReady = identityReady == true
    end
  else
    -- Older economy modules retain their strict open/membership gate; unknown remains syncing.
    hudUi.sponsorConfigured, hudUi.sponsorIdentityReady = true, hudUi.sponsorEconomyParticipant
    hudUi.sponsorReadiness = hudUi.sponsorEnabled and "READY" or "SYNCING"
  end
  hudUi.updateSponsorPrompt()
  hudUi.refreshCommerce()
  lastHudKey = ""
end

hudUi.openCommerce = function(mode)
  if commerceRoot == nil then return false end
  if resultsRoot ~= nil and resultsRoot.activeSelf then return false end
  mode = tostring(mode or "")
  if mode ~= "appearance" and mode ~= "shop" and mode ~= "sponsor" then return false end
  hudUi.closeCheckIn()
  hudUi.commerceMode = mode
  hudUi.lastCommerceMessage = ""
  hudUi.appearancePageRoot:SetActive(mode == "appearance")
  hudUi.shopPageRoot:SetActive(mode == "shop")
  hudUi.sponsorPageRoot:SetActive(mode == "sponsor")
  setGlyphLine(hudUi.commerceTitle, mode == "appearance" and "外观" or mode == "shop" and "商店" or "比赛赞助")
  commerceRoot:SetActive(true)
  if hudUi.commerceScroll then hudUi.commerceScroll.scroll.verticalNormalizedPosition=1 end
  if sponsorPromptRoot ~= nil then sponsorPromptRoot:SetActive(false) end
  commerceRoot.transform:SetAsLastSibling()
  lastLayoutKey = ""
  layoutHud()
  hudUi.refreshCommerce()
  return true
end

hudUi.closeCommerce = function()
  hudUi.commerceMode = "closed"
  if commerceRoot ~= nil then commerceRoot:SetActive(false) end
  hudUi.updateSponsorPrompt()
  return true
end

hudUi.buyItem = function(itemId)
  itemId = tostring(itemId or "")
  if itemId ~= "WING_01" and itemId ~= "HALO_01" then return false end
  local economyScript = resolveEconomyHolder() and economyHolder.script or nil
  if economyScript == nil or economyScript.GeocoreEconomyBuy == nil then
    hudUi.lastCommerceMessage = "商店数据不可用"
    hudUi.refreshCommerce()
    return false
  end
  local ok, response = pcall(function() return economyScript.GeocoreEconomyBuy(itemId) end)
  local success, reason = ok and string.find(tostring(response or ""), "ok=true", 1, true) ~= nil, responseReason(response)
  hudUi.lastCommerceMessage = economyReasonLabel(reason, success)
  if success and hudUi.refreshEconomy ~= nil then hudUi.refreshEconomy(true, hudUi.currentRaceState) else hudUi.refreshCommerce() end
  lastHudKey = ""
  return success
end

hudUi.equipItem = function(category, itemId)
  category, itemId = tostring(category or ""), tostring(itemId or "")
  local supported = (category == "title" and (itemId == "TITLE_DEFAULT" or itemId == "TITLE_VETERAN_DRIVER" or itemId == ""))
    or (category == "wing" and (itemId == "WING_01" or itemId == ""))
    or (category == "halo" and (itemId == "HALO_01" or itemId == ""))
  if not supported then return false end
  local economyScript = resolveEconomyHolder() and economyHolder.script or nil
  if economyScript == nil or economyScript.GeocoreEconomyEquip == nil then
    hudUi.lastCommerceMessage = "外观数据不可用"
    hudUi.refreshCommerce()
    return false
  end
  local callOk, response = pcall(function() return economyScript.GeocoreEconomyEquip(category, itemId) end)
  local success, reason = callOk and string.find(tostring(response or ""), "ok=true", 1, true) ~= nil, responseReason(response)
  hudUi.lastCommerceMessage = economyReasonLabel(reason, success)
  if success and hudUi.refreshEconomy ~= nil then hudUi.refreshEconomy(true, hudUi.currentRaceState) else hudUi.refreshCommerce() end
  return success
end

hudUi.submitSponsor = function(amount)
  hudUi.refreshSponsorAccess()
  amount = math.floor(tonumber(amount) or 0)
  local minimumAmount, maximumAmount = hudUi.sponsorMinAmount or 10, hudUi.sponsorMaxAmount or 5000
  if amount < minimumAmount or amount > maximumAmount then
    hudUi.lastCommerceMessage = "金额超出范围"
    hudUi.refreshCommerce()
    return false
  end
  local debitAmount = amount - math.floor(tonumber(hudUi.sponsorPersonal) or 0)
  if debitAmount <= 0 then
    hudUi.lastCommerceMessage = "目标需高于当前累计"
    hudUi.refreshCommerce()
    return false
  end
  if debitAmount < minimumAmount then
    hudUi.lastCommerceMessage = "追加金额低于最小值"
    hudUi.refreshCommerce()
    return false
  end
  local economyScript = resolveEconomyHolder() and economyHolder.script or nil
  if not hudUi.sponsorEligible or economyScript == nil or economyScript.GeocoreEconomySponsor == nil then
    hudUi.lastCommerceMessage = hudUi.sponsorStatusLabel()
    hudUi.refreshCommerce()
    return false
  end
  local ok, response = pcall(function() return economyScript.GeocoreEconomySponsor(debitAmount) end)
  local success, reason = ok and string.find(tostring(response or ""), "ok=true", 1, true) ~= nil, responseReason(response)
  hudUi.lastCommerceMessage = economyReasonLabel(reason, success)
  if success then
    hudUi.sponsorAmount = amount
    if hudUi.sponsorInput ~= nil then hudUi.sponsorInput.text = tostring(amount) end
  end
  if success and hudUi.refreshEconomy ~= nil then hudUi.refreshEconomy(true, hudUi.currentRaceState) else hudUi.refreshCommerce() end
  lastHudKey = ""
  return success
end

local function setTimeLabel(row,value)
  if row~=nil and row.time~=nil then row.time.text=tostring(value or "")end
end

local function phaseLabel(state)
  if state == "PREPARING" then return "准备选车" end
  if state == "WAITING" then return "等待发车" end
  if state == "RACING" then return "比赛中" end
  if state == "RECYCLING" then return "比赛结束" end
  return "同步中"
end

local function formatTime(milliseconds)
  local seconds = math.max(0, math.ceil((tonumber(milliseconds) or 0) / 1000))
  return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

hudUi.formatResultCoins = function(fixed,sponsor,pending,sponsorPending)
  if pending then return "","金币待结算" end
  if sponsorPending then return formatInteger(fixed or 0).." + ...","赞助待结算" end
  fixed,sponsor=math.max(0,math.floor(tonumber(fixed)or 0)),math.max(0,math.floor(tonumber(sponsor)or 0))
  return formatInteger(fixed+sponsor).." = "..formatInteger(fixed).." + "..formatInteger(sponsor),"金币"
end

hudUi.setResultCoins = function(row,fixed,sponsor,pending,sponsorPending)
  row.coinsPending=pending==true
  local value,label=hudUi.formatResultCoins(fixed,sponsor,pending,sponsorPending)
  row.coins.text=value
  setGlyphLine(row.coinsLabel,label)
end

hudUi.readPlayerResults = function(cycleId)
  local payload, racePayload="", ""
  local currentCycle,currentPhase=0,""
  if resolveManagerHolders() and managerHolder.script.GetRaceManagerFinalResultsSnapshot~=nil then
    pcall(function() racePayload=tostring(managerHolder.script.GetRaceManagerFinalResultsSnapshot()or "")end)
    pcall(function() currentCycle=tonumber(managerHolder.script.GetRaceManagerCycleId()) or 0 end)
    pcall(function() currentPhase=tostring(managerHolder.script.GetRaceManagerState() or "")end)
  end
  if resolveEconomyHolder() and economyHolder.script.GetGeocoreRaceSettlementSnapshot~=nil then
    pcall(function() payload=tostring(economyHolder.script.GetGeocoreRaceSettlementSnapshot()or "")end)
  end
  local snapshotCycle,snapshotRevision,snapshotState=string.match(payload,"^GCRS1|(%d+)|(%d+)|([^\n]+)")
  -- Keep one verified settlement only for the retained previous GFP1. This
  -- session-only read cache is shared by HUD and world boards, never gameplay.
  local cached=hudUi.lastConfirmedSettlement
  if cached and (currentCycle>cached.cycleId+1 or (currentCycle==cached.cycleId+1
    and (currentPhase=="WAITING" or currentPhase=="RACING" or currentPhase=="RECYCLING"))) then
    hudUi.lastConfirmedSettlement,cached=nil,nil
  end
  if tonumber(snapshotCycle)~=cycleId and currentPhase=="PREPARING" and currentCycle==cycleId+1
    and cached and cached.cycleId==cycleId and cached.racePayload==racePayload then
    payload=cached.payload
    snapshotCycle,snapshotRevision,snapshotState=string.match(payload,"^GCRS1|(%d+)|(%d+)|([^\n]+)")
  end
  local rows, rewards={},{}
  local rewardCount,completeSettlement=0,snapshotState=="calculated" and (tonumber(snapshotRevision) or 0)>0
  if tonumber(snapshotCycle)==cycleId and (snapshotState=="calculated" or snapshotState=="fixed") then
    for line in string.gmatch(payload,"\n([^\n]+)")do
      local id,rank,ms,fixed,sponsor,total=string.match(line,"^(%d+)|(%d+)|(-?%d+)|(%d+)|(%d+)|(%d+)$")
      if id~=nil and tonumber(total)==tonumber(fixed)+tonumber(sponsor) then
        if rewards[tonumber(id)]~=nil then completeSettlement=false end
        rewardCount=rewardCount+1
        rewards[tonumber(id)]={rank=tonumber(rank),finishMs=tonumber(ms),fixed=tonumber(fixed),sponsor=tonumber(sponsor)}
      else completeSettlement=false end
    end
  end
  local finalCycle, finalRevision, count=racePayload:match("^GFP1|(%d+)|(%d+)|final|(%d+)")
  local seen, valid={},tonumber(finalCycle)==cycleId and tonumber(count)<=30
  if valid then
    for line in racePayload:gmatch("\n([^\n]+)") do
      local id,rank,ms,vehicle=line:match("^(%d+)|(%d+)|(-?%d+)|([^|]+)$")
      id,rank,ms=tonumber(id),tonumber(rank),tonumber(ms)
      if not id or id<=0 or seen[id] or not rank or not ms or (rank==0)~=(ms<0) then valid=false;break end
      seen[id]=true
      local reward=rewards[id]
      if reward and (reward.rank~=rank or reward.finishMs~=ms) then reward=nil end
      if reward==nil then completeSettlement=false end
      rows[#rows+1]={actorId=id,rank=rank,finishMs=ms,vehicleName=vehicle,
        fixed=reward and reward.fixed,sponsor=reward and reward.sponsor,pending=reward==nil,
        sponsorPending=reward~=nil and snapshotState=="fixed"}
    end
    valid=valid and #rows==tonumber(count)
  end
  if valid then
    if currentCycle==cycleId and completeSettlement and #rows>0 and rewardCount==#rows
      and (cached==nil or cycleId>cached.cycleId
        or (cycleId==cached.cycleId and tonumber(snapshotRevision)>cached.revision)) then
      hudUi.lastConfirmedSettlement={cycleId=cycleId,revision=tonumber(snapshotRevision),
        racePayload=racePayload,payload=payload}
    end
    return rows,racePayload.."\n"..payload,false
  end
  rows={}
  -- An unconfirmed race snapshot is different from a confirmed DNF. Cloud
  -- loading may delay only the coin column, never erase a confirmed lap time.
  if rosterCycleId ~= cycleId then return rows,racePayload.."\n"..payload,true end
  local liveCycle, liveRecords = 0, {}
  if resolveManagerHolders() and managerHolder.script.GetRaceManagerFinishPresentationSnapshot ~= nil then
    local ok, currentCycle, records = pcall(managerHolder.script.GetRaceManagerFinishPresentationSnapshot)
    if ok and tonumber(currentCycle) == cycleId and type(records) == "table" then
      liveCycle, liveRecords = tonumber(currentCycle), records
    end
  end
  local seenLive, liveKey = {}, {}
  for _,vehicle in ipairs(fleet)do
    local roster=rosterByVehicle[vehicle.name]
    if roster~=nil then for _,id in ipairs(roster.occupants or {})do
      id = tonumber(id)
      if id and id > 0 and not seenLive[id] and #rows < 30 then
        seenLive[id] = true
        local ms = liveCycle == cycleId and tonumber(liveRecords[vehicle.name]) or -1
        ms = ms and ms >= 0 and math.floor(ms) or -1
        rows[#rows+1]={actorId=id,rank=0,finishMs=ms,vehicleName=vehicle.name,
          pending=true,racePending=ms<0,provisional=true}
      end
    end end
  end
  table.sort(rows,function(a,b)
    if (a.finishMs>=0) ~= (b.finishMs>=0) then return a.finishMs>=0 end
    if a.finishMs~=b.finishMs then return a.finishMs<b.finishMs end
    return a.actorId<b.actorId
  end)
  local rank,previous=0,nil
  for index,row in ipairs(rows) do
    if row.finishMs>=0 then
      if row.finishMs~=previous then rank=index;previous=row.finishMs end
      row.rank=rank
    end
    liveKey[#liveKey+1]=table.concat({row.actorId,row.rank,row.finishMs},":")
  end
  return rows,racePayload.."\n"..payload.."\nLIVE:"..table.concat(liveKey,","),true
end

-- GWBOARD-1: both screen HUD and world tables consume this one normalization.
-- Returned rows are newly allocated display values, never gameplay state.
function GetRacePlayerResultRows(rawCycleId)
  local cycleId=math.max(0,math.floor(tonumber(rawCycleId) or 0))
  local rows,key,pending=hudUi.readPlayerResults(cycleId)
  local anyFinished=false
  for _,row in ipairs(rows) do
    row.name=displayName(row.actorId):gsub("[\r\n\t]"," ")
    row.rankText=row.rank>0 and tostring(row.rank) or "--"
    local ms=row.finishMs
    row.timeText=ms>=0 and string.format("%02d:%02d.%03d",math.floor(ms/60000),math.floor(ms/1000)%60,ms%1000)
      or (row.racePending and "--:--.---" or "未完赛")
    row.fixedText=row.pending and "待结算" or formatInteger(row.fixed or 0)
    row.sponsorText=(row.pending or row.sponsorPending) and "待结算" or formatInteger(row.sponsor or 0)
    row.coinsText,row.coinsLabel=hudUi.formatResultCoins(row.fixed,row.sponsor,row.pending,row.sponsorPending)
    if ms>=0 then anyFinished=true end
    key=key.."\nNAME:"..tostring(row.actorId)..":"..row.name
  end
  return rows,key,pending,anyFinished
end

hudUi.dismissResults = function()
  local cycleId = 0
  local wasQaResult = hudQaResultsVisible == true
  if resolveManagerHolders() and managerHolder.script.GetRaceManagerCycleId ~= nil then
    pcall(function() cycleId = math.floor(tonumber(managerHolder.script.GetRaceManagerCycleId()) or 0) end)
  end
  if cycleId > 0 then hudUi.dismissedResultsCycleId = hudUi.resultsPendingCycleId or cycleId end
  hudQaResultsVisible = false
  if wasQaResult then hudQaResultsHidden = true end
  if resultsRoot ~= nil then resultsRoot:SetActive(false) end
  hudUi.updateSponsorPrompt()
  lastResultsKey = ""
end

hudUi.styleResult = function(row,rank)
  rank=tonumber(rank)or 0
  local first=rank==1
  row.plate.color=first and Color(0.23,0.18,0.10,0.68) or Color(0.045,0.070,0.115,0.60)
  row.rank.color=rank>0 and rank<=3 and Color(1,0.81,0.46,1) or Color(0.94,0.97,1,1)
  row.time.color=Color(0.94,0.97,1,1)
  row.coins.color=first and Color(1,0.83,0.52,1) or Color(0.91,0.94,0.99,1)
  row.accent.color=Color(1,0.70,0.30,rank>0 and rank<=3 and 0.80 or 0)
end

local function updateResults(state)
  if resultsRoot == nil then return end
  if hudQaResultsVisible then
    resultsRoot:SetActive(true)
    hudUi.closeMore()
    if hudUi.closeCommerce ~= nil then hudUi.closeCommerce() end
    if sponsorPromptRoot ~= nil then sponsorPromptRoot:SetActive(false) end
    resultsRoot.transform:SetAsLastSibling()
    if hudStatusRoot ~= nil then hudStatusRoot:SetActive(true) end
    if hudAppearanceRoot ~= nil then hudAppearanceRoot:SetActive(true) end
    if hudShopRoot ~= nil then hudShopRoot:SetActive(true) end
    if hudStatusRoot ~= nil then hudStatusRoot.transform:SetAsLastSibling() end
    if hudAppearanceRoot ~= nil then hudAppearanceRoot.transform:SetAsLastSibling() end
    if hudShopRoot ~= nil then hudShopRoot.transform:SetAsLastSibling() end
    return
  end
  if hudQaResultsHidden then
    resultsRoot:SetActive(false)
    if hudStatusRoot ~= nil then hudStatusRoot:SetActive(true) end
    if hudAppearanceRoot ~= nil then hudAppearanceRoot:SetActive(true) end
    if hudShopRoot ~= nil then hudShopRoot:SetActive(true) end
    return
  end
  local text = ""
  local cycleId = 0
  if resolveManagerHolders() and managerHolder.script.GetRaceManagerResultsText ~= nil then
    pcall(function() text = tostring(managerHolder.script.GetRaceManagerResultsText() or "") end)
    if managerHolder.script.GetRaceManagerCycleId ~= nil then
      pcall(function() cycleId = math.floor(tonumber(managerHolder.script.GetRaceManagerCycleId()) or 0) end)
    end
  end
  local previous=hudUi.resultsObservedState
  if state=="RECYCLING" and cycleId>0 then hudUi.resultsPendingCycleId=cycleId end
  if state=="PREPARING" and previous=="RACING" and cycleId>1 then hudUi.resultsPendingCycleId=cycleId-1 end
  if state=="WAITING" or state=="RACING" then hudUi.resultsPendingCycleId=nil end
  hudUi.resultsObservedState=state
  local displayCycle=hudUi.resultsPendingCycleId or cycleId
  local visible=state~="RECYCLING" and hudUi.resultsPendingCycleId~=nil and displayCycle~=hudUi.dismissedResultsCycleId
  local resultJustOpened=visible and not resultsRoot.activeSelf
  resultsRoot:SetActive(visible)
  if visible then resultsRoot.transform:SetAsLastSibling() end
  if resultJustOpened then UnityEngine.Debug.Log("RaceResultsAutoOpen cycle="..displayCycle.." phase="..state) end
  -- Opening never waits for nickname/economy data and failures are retryable.
  local good,playerResults,settlementPayload,settlementPending=pcall(GetRacePlayerResultRows,displayCycle)
  if not good then hudUi.resultsLastError=tostring(playerResults);lastResultsKey="";return end
  hudUi.resultsLastError=""
  local key = table.concat({ state, displayCycle, hudUi.dismissedResultsCycleId, text,settlementPayload }, "|")
  if key == lastResultsKey then return end
  lastResultsKey = key
  resultsRoot:SetActive(visible)
  if hudStatusRoot ~= nil then hudStatusRoot:SetActive(true) end
  if hudAppearanceRoot ~= nil then hudAppearanceRoot:SetActive(true) end
  if hudShopRoot ~= nil then hudShopRoot:SetActive(true) end
  if not visible then return end
  hudUi.closeMore()
  if hudUi.closeCommerce ~= nil then hudUi.closeCommerce() end
  hudUi.closeCheckIn()
  if sponsorPromptRoot ~= nil then sponsorPromptRoot:SetActive(false) end
  resultsRoot.transform:SetAsLastSibling()
  local rowIndex=0
  for _,playerRow in ipairs(playerResults)do
    rowIndex=rowIndex+1
    local row=resultsRows[rowIndex]
    row.root:SetActive(true)
    row.rank.text=playerRow.rankText
    setTimeLabel(row,playerRow.timeText)
    setNicknameLabel(row,playerRow.name)
    hudUi.setResultCoins(row,playerRow.fixed,playerRow.sponsor,playerRow.pending,playerRow.sponsorPending)
    hudUi.styleResult(row,playerRow.rank)
  end
  for index=rowIndex+1,#resultsRows do resultsRows[index].root:SetActive(false)end
  hudUi.resultsHasFinishers=rowIndex>0
  resultsVisibleCount=rowIndex
  hudUi.resultsHeaderRoot:SetActive(rowIndex>0)
  hudUi.resultsEmptyRoot:SetActive(rowIndex==0)
  lastLayoutKey = ""
  layoutHud()
  if resultJustOpened then hudUi.resultsScroll.scroll.verticalNormalizedPosition=1 end
end

hudUi.raceParticipationHint = function(state, participating, finished)
  if state == "RACING" and participating and finished then return "已完赛，等待结算中" end
  if state == "PREPARING" then return "尽快选择一辆赛车" end
  if not participating and (state == "WAITING" or state == "RACING") then return "请等待比赛结束" end
  return ""
end

-- GWBOARD-1. Native WorldSpace canvases are parented to the actual opaque
-- screen mesh, never the offset imported root or an unrelated legacy carrier.
-- Each side has a normally culled Canvas; no two-sided material/overlay trick.
hudUi.worldBoardSpecs = {
  {key="main",root="地心飞车_看板_熔铸主屏",screen="MainBoard_DisplaySurface",width=1300,
    fallbacks={{root="_VIS_HEARTWAVE_主看板",screen="MainBoard_Opaque_Back"}}},
  {key="small1",root="地心飞车_看板一_熔脉告示牌",screen="NoticeBoard_DisplaySurface",width=900,
    fallbacks={{root="_VIS_HEARTWAVE_小看板1",screen="Heartwave_Small_Board_01_Opaque_Back"}}},
  {key="small2",root="_VIS_HEARTWAVE_小看板2",screen="Heartwave_Small_Board_02_Opaque_Back",width=900},
  -- The user's moved carrier owns placement. Its original Renderer may stay
  -- hidden by Manager; our Canvas has its own opaque background.
  {key="results",root="透明排名板",screen="self",width=5200,height=2200,
    fallbacks={{root="_VIS_HEARTWAVE_排行榜",screen="Leaderboard_Opaque_Back"}}},
}
hudUi.worldBoards, hudUi.worldBoardRetryAt, hudUi.worldBoardError = {}, -math.huge, ""

hudUi.findWorldBoardScreen=function(spec)
  local candidates={spec}
  for _,fallback in ipairs(spec.fallbacks or {}) do candidates[#candidates+1]=fallback end
  for _,candidate in ipairs(candidates) do
    local root=GameObject.Find(candidate.root)
    if root~=nil then
      if candidate.screen=="self" then return root.transform end
      local pending={root.transform}
      while #pending>0 do
        local trans=table.remove(pending)
        if tostring(trans.name)==candidate.screen then return trans end
        for index=0,trans.childCount-1 do pending[#pending+1]=trans:GetChild(index) end
      end
    end
  end
  return nil
end

hudUi.worldText=function(parent,name,x0,y0,x1,y1,size,align)
  local label=addText(parent,name,Vector2(x0,y0),Vector2(x1,y1),size,align)
  label.fontSize=size -- World boards are physical scene signage, not screen HUD.
  label.supportRichText=false
  label.gameObject.layer=parent.layer
  label.horizontalOverflow=UnityEngine.HorizontalWrapMode.Wrap
  label.verticalOverflow=UnityEngine.VerticalWrapMode.Truncate
  label.resizeTextForBestFit=true
  label.resizeTextMinSize=math.max(10,math.floor(size*0.6))
  label.resizeTextMaxSize=size
  return label
end

hudUi.setWorldText=function(label,value)
  value=tostring(value or "")
  if label.text~=value then
    if label.font~=nil then label.font:RequestCharactersInTexture(value,label.fontSize,UnityEngine.FontStyle.Normal) end
    label.text=value
  end
end

hudUi.fitWorldBoardFace=function(face,bounds,side,width,height)
  height=height or 550
  local size,center=bounds.size,bounds.center
  if size.x<=0 or size.y<=0 then error("opaque screen has no usable mesh rectangle") end
  local rect=face.root:GetComponent(typeof(UnityEngine.RectTransform))
  rect.anchorMin,rect.anchorMax,rect.pivot=Vector2(0.5,0.5),Vector2(0.5,0.5),Vector2(0.5,0.5)
  rect.sizeDelta=Vector2(width,height)
  local trans=face.root.transform
  -- Unity UI faces local -Z. Front-side Canvas is turned to face mesh +Z;
  -- the back-side copy faces -Z with readable, non-mirrored text.
  trans.localRotation=UnityEngine.Quaternion.Euler(0,side==1 and 180 or 0,0)
  trans.localPosition=Vector3(center.x,center.y,center.z+side*(size.z*0.5+math.max(size.x,size.y)*0.0008))
  trans.localScale=Vector3(size.x*0.92/width,size.y*0.88/height,0.001)
end

-- One layout contract for BOTH header and body: no independently centered headings.
hudUi.worldResultColumns={
  {key="rank",label="名次",x0=0.03,x1=0.11,align=UnityEngine.TextAnchor.MiddleCenter},
  {key="name",label="姓名",x0=0.13,x1=0.40,align=UnityEngine.TextAnchor.MiddleLeft},
  {key="time",label="用时",x0=0.42,x1=0.61,align=UnityEngine.TextAnchor.MiddleRight},
  {key="coins",label="金币 常规 / 赞助",x0=0.63,x1=0.97,align=UnityEngine.TextAnchor.MiddleRight},
}

hudUi.worldSponsorSummary=function(displayCycle,currentCycle,state)
  local cached=hudUi.lastWorldSponsorTotals
  if cached and (currentCycle>cached.cycle+1 or (currentCycle==cached.cycle+1 and state~="PREPARING")) then
    hudUi.lastWorldSponsorTotals=nil;cached=nil
  end
  local api=resolveEconomyHolder() and economyHolder.script or nil
  if api and api.GetGeocoreSponsorSnapshot then
    local ok,_,frozen,participant,personal,player,system,pool,revision,cycle=pcall(api.GetGeocoreSponsorSnapshot)
    local function valid(n)return type(n)=="number" and n==n and n>=0 and n<2147483647 and n==math.floor(n) end
    if ok and valid(cycle) and cycle==displayCycle and valid(revision) and revision>0
      and valid(player) and valid(system) and valid(pool) and player+system==pool
      and (not cached or cached.cycle~=cycle or revision>cached.revision
        or (revision==cached.revision and player==cached.player and system==cached.system and pool==cached.pool)) then
      cached={cycle=cycle,revision=revision,player=player,system=system,pool=pool}
      hudUi.lastWorldSponsorTotals=cached
    end
  end
  if not cached or cached.cycle~=displayCycle then return "本场赞助统计待确认" end
  return string.format("玩家赞助 %d   ·   系统赞助 %d   ·   总奖池 %d 金币",cached.player,cached.system,cached.pool)
end

hudUi.createWorldBoardFace=function(screen,spec,side,bounds)
  local face={root=GameObject("Geocore_WorldBoard_"..spec.key..(side==1 and "_Front" or "_Back")),rows={},designHeight=spec.height or 550}
  face.fontScale=face.designHeight/550
  local ok,err=pcall(function()
    face.root.layer=screen.gameObject.layer
    face.root.transform:SetParent(screen,false)
    local canvas=face.root:AddComponent(typeof(UnityEngine.Canvas))
    canvas.renderMode,canvas.sortingOrder=UnityEngine.RenderMode.WorldSpace,0
    hudUi.fitWorldBoardFace(face,bounds,side,spec.width,face.designHeight)
    -- CanvasRenderer is independent from the legacy MeshRenderer. Both
    -- normally culled faces have an opaque panel, so remote text cannot bleed
    -- through the carrier after the Manager disables its old transparent mesh.
    local background=GameObject("Board_Opaque_Background")
    background.layer=face.root.layer; background.transform:SetParent(face.root.transform,false)
    local backgroundRect=background:AddComponent(typeof(UnityEngine.RectTransform))
    backgroundRect.anchorMin,backgroundRect.anchorMax=Vector2(0,0),Vector2(1,1)
    backgroundRect.offsetMin,backgroundRect.offsetMax=Vector2.zero,Vector2.zero
    face.background=background:AddComponent(typeof(UnityEngine.UI.Image))
    face.background.color,face.background.raycastTarget=Color(0.018,0.025,0.04,1),false
    face.title=hudUi.worldText(face.root,"Board_Title",0.03,0.86,0.97,0.98,40*face.fontScale,UnityEngine.TextAnchor.MiddleCenter)
    if spec.key=="results" then
      face.note=hudUi.worldText(face.root,"Board_Note",0.03,0.01,0.97,0.06,23*face.fontScale,UnityEngine.TextAnchor.MiddleCenter)
      face.sponsor=hudUi.worldText(face.root,"Board_SponsorTotals",0.03,0.79,0.97,0.86,27*face.fontScale,UnityEngine.TextAnchor.MiddleCenter)
      face.sponsor.color=Color(1,0.80,0.45,1)
      for _,column in ipairs(hudUi.worldResultColumns) do
        local label=hudUi.worldText(face.root,"Header_"..column.label,column.x0,0.70,column.x1,0.77,27*face.fontScale,column.align)
        label.color=Color(1,0.80,0.45,1);hudUi.setWorldText(label,column.label)
      end
      -- Fixed columns, one row per player (up to the room's 30-player cap).
      -- Rows are created lazily; all participants remain visible, no 10-car cap.
    else
      face.phase=hudUi.worldText(face.root,"Board_Phase",0.04,0.49,0.96,0.79,96,UnityEngine.TextAnchor.MiddleCenter)
      face.clock=hudUi.worldText(face.root,"Board_Countdown",0.04,0.13,0.96,0.49,132,UnityEngine.TextAnchor.MiddleCenter)
      face.note=hudUi.worldText(face.root,"Board_Note",0.03,0.015,0.97,0.10,30,UnityEngine.TextAnchor.MiddleCenter)
    end
    face.root:SetActive(spec.key~="results")
  end)
  if not ok then
    pcall(function() UnityEngine.Object.Destroy(face.root) end)
    error(err)
  end
  return face
end

hudUi.disposeWorldBoard=function(board)
  if board==nil then return end
  for _,face in ipairs(board.faces or {}) do
    pcall(function() face.root:SetActive(false); UnityEngine.Object.Destroy(face.root) end)
  end
end

hudUi.worldBoardBoundsKey=function(bounds)
  local c,s=bounds.center,bounds.size
  return table.concat({c.x,c.y,c.z,s.x,s.y,s.z},",")
end

hudUi.worldBoardBindingCurrent=function(board,screen)
  if board==nil or screen==nil or board.screen~=screen or #board.faces~=2 then return false end
  local ok,current=pcall(function()
    local filter=screen.gameObject:GetComponent(typeof(UnityEngine.MeshFilter))
    if filter==nil or filter.sharedMesh==nil or filter.sharedMesh~=board.mesh then return false end
    for _,face in ipairs(board.faces) do
      if face.root==nil or face.root.transform.parent~=screen
        or face.root:GetComponent(typeof(UnityEngine.Canvas))==nil
        or face.background==nil or face.background.gameObject==nil then return false end
    end
    return true
  end)
  return ok and current==true
end

hudUi.ensureWorldBoards=function()
  if Time.unscaledTime<hudUi.worldBoardRetryAt then return end
  hudUi.worldBoardRetryAt=Time.unscaledTime+1
  local problems={}
  for _,spec in ipairs(hudUi.worldBoardSpecs) do
    local board=hudUi.worldBoards[spec.key]
    local found,screen=pcall(hudUi.findWorldBoardScreen,spec)
    if not found then screen=nil end
    if board~=nil and not hudUi.worldBoardBindingCurrent(board,screen) then
      hudUi.disposeWorldBoard(board)
      hudUi.worldBoards[spec.key],board=nil,nil
    end
    if board==nil then
      if screen~=nil then
        local ok,value=pcall(function()
          local filter=screen.gameObject:GetComponent(typeof(UnityEngine.MeshFilter))
          if filter==nil or filter.sharedMesh==nil then error("screen mesh not ready") end
          local bounds=filter.sharedMesh.bounds
          local created={screen=screen,mesh=filter.sharedMesh,boundsKey=hudUi.worldBoardBoundsKey(bounds),faces={},spec=spec}
          -- Record ownership before creation so partial failures are cleaned.
          hudUi.worldBoards[spec.key]=created
          for _,side in ipairs({1,-1}) do created.faces[#created.faces+1]=hudUi.createWorldBoardFace(screen,spec,side,bounds) end
          return created
        end)
        if not ok then
          local partial=hudUi.worldBoards[spec.key]
          hudUi.disposeWorldBoard(partial)
          hudUi.worldBoards[spec.key]=nil
          problems[#problems+1]=spec.key..":"..tostring(value)
        end
      else problems[#problems+1]=spec.key..":screen missing" end
    else
      local ok,reason=pcall(function()
        local bounds=board.mesh.bounds
        local boundsKey=hudUi.worldBoardBoundsKey(bounds)
        if boundsKey~=board.boundsKey then
          for index,side in ipairs({1,-1}) do
            hudUi.fitWorldBoardFace(board.faces[index],bounds,side,spec.width,board.faces[index].designHeight)
          end
          board.boundsKey,board.lastKey=boundsKey,nil
        end
      end)
      if not ok then
        hudUi.disposeWorldBoard(board); hudUi.worldBoards[spec.key]=nil
        problems[#problems+1]=spec.key..":"..tostring(reason)
      end
    end
  end
  hudUi.worldBoardError=table.concat(problems,"; ")
  if managerHolder and managerHolder.script.RaceManagerRefreshLeaderboardPresentation then
    pcall(managerHolder.script.RaceManagerRefreshLeaderboardPresentation)
  end
end

hudUi.worldResultRow=function(face,index,count)
  local row=face.rows[index]
  if row==nil then
    local object=GameObject("Player_Row_"..tostring(index))
    object.layer=face.root.layer;object.transform:SetParent(face.root.transform,false)
    local rect=object:AddComponent(typeof(UnityEngine.RectTransform))
    row={root=object,rect=rect}
    for _,column in ipairs(hudUi.worldResultColumns) do
      local name=column.key:sub(1,1):upper()..column.key:sub(2)
      row[column.key]=hudUi.worldText(object,name,column.x0,0,column.x1,1,29,column.align)
    end
    face.rows[index]=row
  end
  local step=0.62/math.max(10,count)
  local geometryKey=table.concat({index,count,face.designHeight,face.fontScale,
    tostring(row.rank.font),tostring(row.name.font),tostring(row.time.font),tostring(row.coins.font)},"|")
  if row.geometryKey==geometryKey then
    if not row.root.activeSelf then row.root:SetActive(true) end
    return row
  end
  row.geometryKey=geometryKey
  row.rect.anchorMin,row.rect.anchorMax=Vector2(0,0.67-index*step),Vector2(1,0.67-(index-1)*step)
  row.rect.offsetMin,row.rect.offsetMax=Vector2.zero,Vector2.zero
  for _,label in ipairs({row.rank,row.name,row.time,row.coins}) do
    -- GWBOARD-1.1: dense rows need a glyph-line budget, not a fixed minimum
    -- point size. At 30 rows the old 550-unit canvas + Truncate produced zero
    -- vertices for Noto's taller line metrics. A 4x logical canvas preserves
    -- physical dimensions while allowing readable high-resolution small text.
    local lineRatio=1.65
    pcall(function()
      local base=tonumber(label.font.fontSize) or 0
      local line=tonumber(label.font.lineHeight) or 0
      if base>0 and line>0 then lineRatio=math.max(1.2,math.min(2.5,line/base)) end
    end)
    local font=math.max(4,math.min(29*face.fontScale,math.floor(step*face.designHeight*0.84/lineRatio)))
    label.resizeTextForBestFit=false
    label.fontSize,label.resizeTextMinSize,label.resizeTextMaxSize=font,font,font
    hudUi.worldLabelBaseSizes=hudUi.worldLabelBaseSizes or setmetatable({},{__mode="k"})
    hudUi.worldLabelBaseSizes[label]=font
    label.lineSpacing=1
    -- Overflow here prevents the one-line text generator from silently
    -- discarding a whole glyph line. The font budget keeps lines in their row.
    label.verticalOverflow=UnityEngine.VerticalWrapMode.Overflow
  end
  row.root:SetActive(true)
  return row
end

hudUi.worldLabelFitCache=setmetatable({},{__mode="k"})
hudUi.fitWorldRowLabel=function(label)
  -- GWBOARD-1.2: every table cell is one line. Overflow prevents silent glyph
  -- deletion; actual native preferred dimensions determine the font that fits
  -- BOTH the column and row, so long names/coin sums cannot cover neighbors.
  local rect=label.rectTransform.rect
  local width,height=tonumber(rect.width) or 0,tonumber(rect.height) or 0
  if width<=0 or height<=0 then error("world table cell rectangle not ready") end
  local base=hudUi.worldLabelBaseSizes and hudUi.worldLabelBaseSizes[label] or label.fontSize
  local key=table.concat({tostring(label.text or ""),width,height,base,tostring(label.font),
    tostring(label.fontStyle),tostring(label.lineSpacing)},"|")
  local cached=hudUi.worldLabelFitCache[label]
  if cached and cached.key==key and cached.size==label.fontSize then return end
  label.resizeTextForBestFit=false
  label.horizontalOverflow=UnityEngine.HorizontalWrapMode.Overflow
  label.verticalOverflow=UnityEngine.VerticalWrapMode.Overflow
  label.fontSize=base
  for attempt=1,6 do
    local preferredWidth=tonumber(label.preferredWidth) or 0
    local preferredHeight=tonumber(label.preferredHeight) or 0
    if tostring(label.text or "")~="" and (preferredWidth<=0 or preferredHeight<=0) then error("world text metrics not ready") end
    local ratio=math.min(1,width*0.96/math.max(1,preferredWidth),height*0.90/math.max(1,preferredHeight))
    if ratio>=0.999 then break end
    local nextSize=math.max(4,math.floor(label.fontSize*ratio*0.98))
    if nextSize>=label.fontSize then break end
    label.fontSize=nextSize
  end
  label.resizeTextMinSize,label.resizeTextMaxSize=label.fontSize,label.fontSize
  hudUi.worldLabelFitCache[label]={key=key,size=label.fontSize}
end

hudUi.worldBoardResultCycle=function(state,cycleId)
  -- Re-use Manager's retained, authority-validated final snapshot. No second
  -- result cache is authored here; an old/malformed snapshot cannot invent a
  -- previous-round table or provide a live finish for the new cycle.
  if state~="PREPARING" or cycleId<=1 then return cycleId,false end
  local ok,payload=pcall(function() return managerHolder.script.GetRaceManagerFinalResultsSnapshot() end)
  if not ok or type(payload)~="string" then return cycleId,false end
  local previous,revision,count=payload:match("^GFP1|(%d+)|(%d+)|final|(%d+)\n")
  previous,revision,count=tonumber(previous),tonumber(revision),tonumber(count)
  if previous~=cycleId-1 or revision==nil or revision<1 or count==nil or count<1 or count>30 then return cycleId,false end
  -- The shared normalizer additionally validates every row, actor uniqueness,
  -- rank/time pairing, count, and same-cycle rewards before returning a final.
  return previous,true
end

hudUi.updateWorldBoards=function(state,remaining)
  hudUi.ensureWorldBoards()
  local cycleId=math.floor(tonumber(managerHolder.script.GetRaceManagerCycleId()) or 0)
  local displayCycle,previous=hudUi.worldBoardResultCycle(state,cycleId)
  local sponsorSummary=hudUi.worldSponsorSummary(displayCycle,cycleId,state)
  local rows,key,pending,anyFinished=GetRacePlayerResultRows(displayCycle)
  local visible=((state=="RACING" or state=="RECYCLING") or (previous and not pending)) and anyFinished
  local phase=({PREPARING="准备选车",WAITING="等待发车",RACING="比赛进行中",RECYCLING="比赛结束"})[state] or "时间同步中"
  local clock=remaining>=0 and formatTime(remaining) or "--:--"
  for boardKey,board in pairs(hudUi.worldBoards) do
    local nextKey=boardKey=="results" and (tostring(visible).."|"..state.."|"..tostring(displayCycle).."|"..key.."|"..sponsorSummary) or (phase.."|"..clock)
    for _,face in ipairs(board.faces) do
      local expected=boardKey~="results" or visible
      if face.root.activeSelf~=expected then board.lastKey=nil end
    end
    if board.lastKey~=nextKey then
      for _,face in ipairs(board.faces) do
        if boardKey=="results" then
          face.root:SetActive(visible)
          if visible then
            hudUi.setWorldText(face.title,previous and "上一场成绩排行榜" or pending and "本场暂时排名" or "本场成绩排行榜")
            hudUi.setWorldText(face.sponsor,sponsorSummary)
            hudUi.setWorldText(face.note,previous and "上一场有效成绩 · 新一场发车前保留 · 金币 = 常规 + 赞助" or pending and "仅有效完赛计时 · 常规与赞助金币待结算" or "每位玩家一行 · 同车并列 · 金币 = 常规 + 赞助")
            for index,entry in ipairs(rows) do
              local row=hudUi.worldResultRow(face,index,#rows)
              hudUi.setWorldText(row.rank,entry.rankText);hudUi.setWorldText(row.name,entry.name)
              hudUi.setWorldText(row.time,entry.timeText)
              hudUi.setWorldText(row.coins,entry.coinsText~="" and entry.coinsText or entry.coinsLabel)
              for _,label in ipairs({row.rank,row.name,row.time,row.coins}) do hudUi.fitWorldRowLabel(label) end
              row.rank.color=entry.rank>0 and entry.rank<=3 and Color(1,0.80,0.45,1) or Color.white
            end
            for index=#rows+1,#face.rows do face.rows[index].root:SetActive(false) end
          end
        else
          face.root:SetActive(true)
          hudUi.setWorldText(face.title,"地心飞车")
          hudUi.setWorldText(face.phase,phase);hudUi.setWorldText(face.clock,clock)
          hudUi.setWorldText(face.note,state=="PREPARING" and "选择赛车 · 准备出发" or state=="RACING" and "按顺序通过赛道检查点" or state=="WAITING" and "参赛车辆等待统一发车" or "新一轮比赛即将开始")
        end
      end
      board.lastKey=nextKey
    end
  end
end

function GetRaceWorldBoardPresentationStatus()
  local count,faces=0,0
  for _,board in pairs(hudUi.worldBoards) do count=count+1;faces=faces+#board.faces end
  return "GWBOARD-2.0",count,faces,tostring(hudUi.worldBoardError or ""),tostring(hudUi.font and hudUi.font.name or "")
end

local function updateHud()
  if not createHud() or not resolveManagerHolders() then return end
  layoutHud()
  local state, remaining = "", -1
  pcall(function() state = tostring(managerHolder.script.GetRaceManagerState() or "") end)
  pcall(function() remaining = tonumber(managerHolder.script.GetRaceManagerRemainingMilliseconds()) or -1 end)
  local boardOk,boardError=pcall(hudUi.updateWorldBoards,state,remaining)
  if not boardOk then hudUi.worldBoardError=tostring(boardError) end
  if hudUi.setStagingWallCollision ~= nil then hudUi.setStagingWallCollision(state) end
  -- No estimated live ranking: only final authoritative results are ranked.
  local vehicleName = localVehicleName()
  local participating, finished = vehicleName ~= "", false
  if participating and state == "RACING" then
    local ok, ms = pcall(function() return managerHolder.script.GetRaceManagerVehicleFinishMilliseconds(vehicleName) end)
    finished = ok and tonumber(ms) ~= nil and tonumber(ms) >= 0
  end
  if hudQaState ~= nil then
    state, remaining = hudQaState, hudQaRemaining or remaining
    participating = (hudQaRank or 0) > 0
  end
  hudUi.currentRaceState = state
  if hudUi.refreshEconomy ~= nil then hudUi.refreshEconomy(false, state) end
  hudUi.tickAutoSponsor()
  hudUi.refreshCheckIn(false)
  local hintText = hudUi.raceParticipationHint(state, participating, finished)
  hudUi.hasParticipationHint = hintText ~= ""
  layoutHud()
  local coinsText = hudQaCoins ~= nil and tostring(hudQaCoins) or hudCoinSnapshot
  hudCoins.fontSize=string.find(coinsText,"\n",1,true) and 10 or 12
  local key = table.concat({ state, math.ceil(math.max(0, remaining) / 1000), coinsText, tostring(participating), hintText }, "|")
  if key ~= lastHudKey then
    lastHudKey = key
    hudPhase.text, hudTimer.text, hudRank.text = "", remaining >= 0 and formatTime(remaining) or "--:--", ""
    hudUi.rankCaptionRect.gameObject:SetActive(false)
    hudRank.gameObject:SetActive(false)
    hudUi.participationHint.text = hintText
    hudUi.participationHint.gameObject:SetActive(hintText ~= "")
    local phaseKey = state == "PREPARING" and "preparing" or state == "WAITING" and "waiting" or state == "RACING" and (finished and "finished" or "racing") or state == "RECYCLING" and "recycling" or "syncing"
    for key, object in pairs(hudPhaseImages) do object:SetActive(key == phaseKey) end
    hudCoins.text = coinsText
    local stateColor = Color(0.36, 0.78, 1.0, 0.78)
    if state == "PREPARING" then stateColor = Color(0.38, 0.82, 1.0, 0.78)
    elseif state == "WAITING" then stateColor = Color(1.0, 0.68, 0.20, 0.84)
    elseif state == "RACING" then stateColor = Color(1.0, 0.30, 0.08, 0.92)
    elseif state == "RECYCLING" then stateColor = Color(0.56, 0.88, 0.48, 0.82) end
    if hudPhaseAccent ~= nil then hudPhaseAccent.color = stateColor end
    if hudTimerGlow ~= nil then hudTimerGlow.color = Color(stateColor.r, stateColor.g, stateColor.b, 0.56) end
  end
  updateResults(state)
end

local function makeZoneCube(parent, name, position, scale, color)
  local object = GameObject.CreatePrimitive(UnityEngine.PrimitiveType.Cube)
  object.name, object.transform.position, object.transform.localScale = name, position, scale
  object.transform:SetParent(parent.transform, true)
  local collider = object:GetComponent(typeof(UnityEngine.Collider))
  if collider ~= nil then collider.enabled = false end
  local renderer = object:GetComponent(typeof(UnityEngine.Renderer))
  if renderer ~= nil then
    pcall(function()
      local material = renderer.material
      material.color = color
      material:SetFloat("_Surface", 1)
      material:SetFloat("_Mode", 3)
      material:SetInt("_SrcBlend", 5)
      material:SetInt("_DstBlend", 10)
      material:SetInt("_ZWrite", 0)
      material.renderQueue = 3000
    end)
  end
end

local function createZone(parent, prefix, center, width, depth)
  local wallColor, activeColor = Color(1.0, 0.36, 0.10, 0.20), Color(1.0, 0.08, 0.03, 0.30)
  makeZoneCube(parent, prefix .. "_ActiveFloor", Vector3(center.x, center.y, center.z), Vector3(width, 0.05, depth), activeColor)
  makeZoneCube(parent, prefix .. "_North", Vector3(center.x, center.y + 0.62, center.z + depth * 0.5), Vector3(width, 1.25, 0.25), wallColor)
  makeZoneCube(parent, prefix .. "_South", Vector3(center.x, center.y + 0.62, center.z - depth * 0.5), Vector3(width, 1.25, 0.25), wallColor)
  makeZoneCube(parent, prefix .. "_East", Vector3(center.x + width * 0.5, center.y + 0.62, center.z), Vector3(0.25, 1.25, depth), wallColor)
  makeZoneCube(parent, prefix .. "_West", Vector3(center.x - width * 0.5, center.y + 0.62, center.z), Vector3(0.25, 1.25, depth), wallColor)
end

hudUi.cacheStagingWallColliders = function()
  hudUi.stagingWallColliders = {}
  hudUi.stagingWallCollisionEnabled = nil
  if zoneVisualRoot == nil then return 0 end
  local expectedNames = {
    ["发车区_红色有效区域"] = true,
    ["发车区_透明围栏模型_北侧围栏"] = true,
    ["发车区_透明围栏模型_南侧围栏"] = true,
    ["发车区_透明围栏模型_东侧围栏"] = true,
    ["发车区_透明围栏模型_西侧围栏"] = true,
    ["TrackStagingZone_North"] = true,
    ["TrackStagingZone_South"] = true,
    ["TrackStagingZone_East"] = true,
    ["TrackStagingZone_West"] = true,
    ["TrackStagingZone_ActiveFloor"] = true,
  }
  local colliders = zoneVisualRoot:GetComponentsInChildren(typeof(UnityEngine.Collider), true)
  for index = 0, colliders.Length - 1 do
    local collider = colliders[index]
    local objectName = collider ~= nil and tostring(collider.gameObject.name or "") or ""
    if expectedNames[objectName] then
      hudUi.stagingWallColliders[#hudUi.stagingWallColliders + 1] = collider
    end
  end
  return #hudUi.stagingWallColliders
end

hudUi.setStagingWallCollision = function(state)
  -- RACE-RULES-0905: all five surfaces form the WAITING enclosure. The red
  -- floor is a visual activity marker outside WAITING, never a race obstacle.
  if #hudUi.stagingWallColliders ~= 5 then hudUi.cacheStagingWallColliders() end
  local enabled = tostring(state or "") == "WAITING"
  local errors = {}
  for _, collider in ipairs(hudUi.stagingWallColliders) do
    -- Read back every update: editor/native component refresh may restore a
    -- serialized flag without a phase transition. Correct only mismatches.
    local ok, err = pcall(function()
      if collider == nil then error("staging collider missing") end
      if collider.enabled ~= enabled then collider.enabled = enabled end
      if collider.enabled ~= enabled then error("staging collision readback failed") end
    end)
    if not ok then errors[#errors + 1] = tostring(err) end
  end
  if #hudUi.stagingWallColliders ~= 5 then errors[#errors + 1] = "expected five staging surfaces" end
  hudUi.stagingCollisionError = table.concat(errors, "; ")
  if #errors == 0 then hudUi.stagingWallCollisionEnabled = enabled
  else hudUi.stagingWallCollisionEnabled = nil end
  hudUi.stagingWallState = tostring(state or "")
  return #hudUi.stagingWallColliders
end

local function createZoneVisuals()
  if zoneVisualRoot ~= nil then return end
  local persistentRoot = GameObject.Find("地心飞车_区域隔离总成")
  if persistentRoot ~= nil then
    zoneVisualRoot = persistentRoot
  else
    zoneVisualRoot = GameObject("Geocore_Race_Separated_Zones")
    createZone(zoneVisualRoot, "SelectionZone", Vector3(30, 10.22, 42), 30, 22)
    createZone(zoneVisualRoot, "TrackStagingZone", Vector3(77, 10.55, 33), 31, 13)
  end
  hudUi.cacheStagingWallColliders()
  hudUi.setStagingWallCollision("")
end

-- RACE-RULES-0905: a single client-side owner controls the shared jump input.
-- The real InputManager Jump action covers keyboard/gamepad. The native HUD
-- button has a separate click path, so both are gated. Never modify movement,
-- canEverJump, ActorStateType, or another player's input to enforce seating.
function hudUi.seatInputDestroyed(lease)
  -- InputAction is not a UnityEngine.Object. Never infer disposal from a
  -- getter/setter exception, nor retire a live object after a failed restore.
  if lease.kind ~= "button" then return false end
  local ok, value = pcall(function() return UnityEngine.Object.op_Equality(lease.object, nil) end)
  if ok and type(value) == "boolean" then return value end
  ok, value = pcall(function() return lease.object:Equals(nil) end)
  return ok and value == true
end

function hudUi.seatInputRead(lease)
  local value
  if lease.kind == "action" then value = lease.object.enabled
  else value = lease.object.interactable end
  if type(value) ~= "boolean" then error(lease.kind .. " input state is not boolean") end
  return value
end

function hudUi.seatInputLease(kind, object, errors)
  local guard = hudUi.seatInputGuard
  guard.leases = guard.leases or {}
  for _, lease in ipairs(guard.leases) do
    if lease.kind == kind and lease.object == object then
      lease.wanted = true
      return lease -- A pending restore owns the ORIGINAL state, not current false.
    end
  end
  local lease = { kind=kind, object=object, wanted=true }
  local ok, original = pcall(function() return hudUi.seatInputRead(lease) end)
  if not ok then errors[#errors+1] = tostring(original); return nil end
  lease.original = original
  guard.leases[#guard.leases+1] = lease
  return lease
end

function hudUi.applySeatInputLeases(errors)
  local guard = hudUi.seatInputGuard
  guard.leases = guard.leases or {}
  guard.pendingRestoreCount = 0
  for index = #guard.leases, 1, -1 do
    local lease = guard.leases[index]
    if hudUi.seatInputDestroyed(lease) then
      table.remove(guard.leases,index)
    else
      local target = lease.original
      if lease.wanted then target = false end
      local ok, err = pcall(function()
        if hudUi.seatInputRead(lease) ~= target then
          if lease.kind == "action" then
            if target then lease.object:Enable() else lease.object:Disable() end
          else lease.object.interactable = target end
        end
        if hudUi.seatInputRead(lease) ~= target then error(lease.kind .. " input write readback failed") end
      end)
      if ok and not lease.wanted then table.remove(guard.leases,index)
      elseif not ok then
        errors[#errors+1] = lease.kind .. (lease.wanted and " lock: " or " restore: ") .. tostring(err)
        if not lease.wanted then guard.pendingRestoreCount = guard.pendingRestoreCount + 1 end
      end
    end
  end
end

function hudUi.releaseRaceSeatInput()
  local guard, errors = hudUi.seatInputGuard, {}
  for _,lease in ipairs(guard.leases or {}) do lease.wanted = false end
  hudUi.applySeatInputLeases(errors)
  guard.action, guard.button = nil,nil
  guard.locked, guard.cycleId, guard.actorId, guard.seatId, guard.vehicleName = false,0,0,"",nil
  guard.error = table.concat(errors,"; ")
  return #(guard.leases or {}) == 0
end

function hudUi.readLocalRaceSeatLock(state, cycleId)
  cycleId = tonumber(cycleId) or 0
  if state == "PREPARING" or state == "RECYCLING" or cycleId <= 0 then return false,0,"" end
  local ok, actor = pcall(function() return DouyinActorService.GetLocalActor() end)
  if not ok or actor == nil then return nil,0,"","local Actor unavailable" end
  local identityOk, isLocal, id = pcall(function() return actor.isLocal, actorId(actor) end)
  if not identityOk then return nil,0,"","local Actor identity unavailable" end
  if isLocal ~= true then return false,0,"" end
  if id <= 0 then return false,0,"" end
  if state ~= "WAITING" and state ~= "RACING" then return nil,id,"","race phase unavailable" end
  local guard = hudUi.seatInputGuard
  local uncertain, errors = false, {}
  for _,entry in ipairs(fleet) do
    local holder = guard.holders[entry.name]
    local read, locked, lockCycle, lockActor, seat = pcall(function()
      if holder == nil or holder.script == nil then
        if entry.name == "暮翼巡游" or entry.name == "甜咒南瓜" then
          holder = vehicleHolder(entry)
        else
          local vehicle = GameObject.Find(entry.name)
          holder = vehicle ~= nil and vehicle:GetDouyinScript(entry.id) or nil
        end
        guard.holders[entry.name] = holder
      end
      if holder == nil or holder.script == nil or holder.script.GetRaceSessionLocalSeatLock == nil then
        error("local seat lock API unavailable")
      end
      return holder.script.GetRaceSessionLocalSeatLock()
    end)
    if read and type(locked) ~= "boolean" then read,locked = false,"local seat lock state unavailable" end
    if not read then
      guard.holders[entry.name] = nil
      if not guard.locked or guard.vehicleName == entry.name then
        uncertain = true; errors[#errors+1] = entry.name .. ": " .. tostring(locked)
      end
    end
    if read and locked == true and tonumber(lockCycle) == cycleId and tonumber(lockActor) == id
      and tostring(seat or "") ~= "" then return true,id,tostring(seat),"",entry.name end
  end
  if uncertain then return nil,id,"",table.concat(errors,"; ") end
  return false,id,""
end

function hudUi.updateRaceSeatInput(state, cycleId)
  local guard = hudUi.seatInputGuard
  local locked,id,seat,readError,vehicleName = hudUi.readLocalRaceSeatLock(state,cycleId)
  local errors = {}
  if locked == nil then
    errors[#errors+1] = tostring(readError or "local seat lock unknown")
    locked = guard.locked == true and guard.cycleId == cycleId and guard.actorId == id and id > 0
      and state ~= "PREPARING" and state ~= "RECYCLING"
    if locked then seat,vehicleName = guard.seatId,guard.vehicleName end
  end
  if not locked then
    hudUi.releaseRaceSeatInput()
    if #errors > 0 then
      if guard.error ~= "" then errors[#errors+1] = guard.error end
      guard.error = table.concat(errors,"; ")
    end
    return
  end
  for _,lease in ipairs(guard.leases or {}) do lease.wanted = false end
  local actionOk, action = pcall(function() return CS.UGCInput.InputManager.Instance.JumpInputAction end)
  local buttonOk, button = pcall(function() return CS.UI.MainInputPanel.instance.BtnJump end)
  -- A temporarily unavailable singleton cannot relinquish an already-held
  -- input lock. A confirmed replacement keeps old pending + new active leases.
  if actionOk and action ~= nil then guard.action = action
  else action = guard.action; errors[#errors+1] = "native JumpInputAction lookup unavailable" end
  if buttonOk and button ~= nil then guard.button = button
  else button = guard.button; errors[#errors+1] = "native jump button lookup unavailable" end
  if action ~= nil then
    hudUi.seatInputLease("action",action,errors)
  else errors[#errors+1]="native JumpInputAction unavailable" end
  if button ~= nil then
    hudUi.seatInputLease("button",button,errors)
  else errors[#errors+1]="native jump button unavailable" end
  hudUi.applySeatInputLeases(errors)
  guard.locked,guard.cycleId,guard.actorId,guard.seatId,guard.vehicleName=true,cycleId,id,seat,vehicleName
  guard.error=table.concat(errors,"; ")
end

function GetRaceSeatInputGuardStatus()
  local guard=hudUi.seatInputGuard
  local actionEnabled,buttonEnabled=nil,nil
  pcall(function() actionEnabled=guard.action.enabled end)
  pcall(function() buttonEnabled=guard.button.interactable end)
  return guard.locked,guard.cycleId or 0,guard.actorId or 0,guard.seatId or "",actionEnabled,buttonEnabled,guard.error,
    guard.pendingRestoreCount or 0
end

hudUi.tickResultsPresentation=function()
 if not resolveManagerHolders() then return end
 local state=tostring(managerHolder.script.GetRaceManagerState()or "")
 local ok,err=pcall(updateResults,state)
 if not ok then hudUi.resultsLastError=tostring(err);lastResultsKey="" end
end
function GetRaceResultsPresentationStatus()
 return "RESULTS_RETRY_V2",resultsRoot~=nil and resultsRoot.activeSelf,hudUi.resultsPendingCycleId or 0,hudUi.resultsLastError or "",hudUi.dismissedResultsCycleId
end
local function updateRaceTransition()
  if not resolveManagerHolders() then return end
  local state, cycleId = "", 0
  pcall(function() state = tostring(managerHolder.script.GetRaceManagerState() or "") end)
  pcall(function() cycleId = math.floor(tonumber(managerHolder.script.GetRaceManagerCycleId()) or 0) end)
  if hudUi.setStagingWallCollision ~= nil then hudUi.setStagingWallCollision(state) end
  hudUi.updateRaceSeatInput(state,cycleId)
  if state == "WAITING" and cycleId > 0 then
    if rosterCycleId ~= cycleId and isAuthority() then publishRoster(cycleId) end
    if rosterCycleId == cycleId then stageRoster(cycleId) end
  end
  lastObservedState = state
end

function RaceSessionApplyRoster(payload)
  return parseRoster(payload)
end

function OnNetSpawned()
  if raceRosterSnapshot ~= nil and rosterChangeHandle == nil then
    pcall(function()
      rosterChangeHandle = raceRosterSnapshot:OnValueChange(function(currentValue, previousValue)
        parseRoster(currentValue)
      end)
    end)
    pcall(function() parseRoster(raceRosterSnapshot:GetValue()) end)
  end
end

function OnVariablesSynced()
  if raceRosterSnapshot ~= nil then pcall(function() parseRoster(raceRosterSnapshot:GetValue()) end) end
end

function OnOwnershipTransferred()
  hudUi.identity.invalidate()
  if raceRosterSnapshot ~= nil then pcall(function() parseRoster(raceRosterSnapshot:GetValue()) end) end
  updateRaceTransition()
end

function OnPlayerJoined(player)
  observeIdentity(player, playerActor(player))
end

function OnPlayerRejoined(player)
  OnPlayerJoined(player)
end

function OnPlayerLeft(player)
  local key = playerOpenId(player)
  local id = currentActorIdByOpenId[key]
  -- A delayed leave for an old Player must not retire its reconnected replacement.
  if id == nil or playerRefsByActorId[id] ~= player then return end
  hudUi.identity.observed[key] = nil
  currentActorIdByOpenId[key], playerRefsByActorId[id], actorRefs[id] = nil, nil, nil
  -- Keep successful names and exhausted retry budgets for the lifetime of the room.
end

function OnActorSpawned(actor)
  local openId = ""
  pcall(function() openId = tostring(actor.UID or "") end)
  local player = nil
  if DouyinPlayerService ~= nil and openId ~= "" then
    pcall(function() player = DouyinPlayerService.GetPlayerByOpenID(openId) end)
  end
  if player ~= nil then observeIdentity(player, actor) end
end

function Start()
  resolveManagerHolders()
  hudUi.identity.hydrate()
  refreshRoomIdentities()
  createZoneVisuals()
  createHud()
  recoverLocalUnreadyActor()
  updateRaceTransition()
  updateHud()
end

function Update()
  if hudUi.glassTick~=nil then hudUi.glassTick()end
  hudUi.moreTick()
  updateRaceTransition()
  hudUi.identity.tick()
  if Time.unscaledTime >= nextIdentityMaintenanceAt then
    nextIdentityMaintenanceAt = Time.unscaledTime + 1.0
    recoverLocalUnreadyActor()
  end
  if Time.unscaledTime >= nextHudUpdateAt then
    nextHudUpdateAt = Time.unscaledTime + 0.10
    hudUi.tickResultsPresentation()
    updateHud()
  end
end

function GetRaceSessionStatus()
  return rosterCycleId, rosterRevision, GetRaceParticipantVehicleCount(), lastStagedCycleId,
    hudRoot ~= nil, resultsRoot ~= nil, zoneVisualRoot ~= nil, SESSION_ID
end

function GetRaceNicknameLookupStatus()
  local n, queued, pending, resolved, exhausted = hudUi.identity, 0, 0, 0, 0
  for _, row in pairs(n.entries) do
    if row.status == "q" then queued = queued + 1
    elseif row.status == "p" then pending = pending + 1
    elseif row.status == "d" then resolved = resolved + 1
    elseif row.status == "f" then exhausted = exhausted + 1 end
  end
  return n.owner(), n.stats.requests, queued, pending, resolved, exhausted,
    n.stats.timeouts, n.stats.stale, n.pauseUntil, n.revision
end

function GeocoreUI02GetDiagnostics()
  return tostring(hudUi.font and hudUi.font.name or ""),hudUi.artTexture~=nil,tostring(hudUi.artError or ""),
    hudUi.glassAvailable==true,tostring(hudUi.glassError or ""),#hudUi.glassViews
end

function GetRaceStagingWallCollisionStatus()
  local enabledCount = 0
  for _, collider in ipairs(hudUi.stagingWallColliders) do
    if collider ~= nil and collider.enabled then enabledCount = enabledCount + 1 end
  end
  return tostring(hudUi.stagingWallState or ""), #hudUi.stagingWallColliders, enabledCount,
    tostring(hudUi.stagingWallState or "") == "WAITING", tostring(hudUi.stagingCollisionError or "")
end

function GeocoreRaceQASetStagingWallState(state)
  createZoneVisuals()
  hudUi.setStagingWallCollision(tostring(state or ""))
  return GetRaceStagingWallCollisionStatus()
end

function GeocoreRaceQAShowResults()
  if not createHud() then return false end
  hudQaResultsVisible, hudQaResultsHidden = true, false
  resultsRoot:SetActive(true)
  if hudUi.closeCommerce ~= nil then hudUi.closeCommerce() end
  if sponsorPromptRoot ~= nil then sponsorPromptRoot:SetActive(false) end
  resultsRoot.transform:SetAsLastSibling()
  if hudStatusRoot ~= nil then hudStatusRoot:SetActive(true) end
  if hudAppearanceRoot ~= nil then hudAppearanceRoot:SetActive(true) end
  if hudShopRoot ~= nil then hudShopRoot:SetActive(true) end
  if hudStatusRoot ~= nil then hudStatusRoot.transform:SetAsLastSibling() end
  if hudAppearanceRoot ~= nil then hudAppearanceRoot.transform:SetAsLastSibling() end
  if hudShopRoot ~= nil then hudShopRoot.transform:SetAsLastSibling() end
  hudUi.resultsHeaderRoot:SetActive(true)
  hudUi.resultsEmptyRoot:SetActive(false)
  local samples = {
    {"1", "阿曜", "01:38.204",200,500}, {"1", "小七", "01:38.204",200,300},
    {"2", "林川", "01:42.386",100,200}, {"2", "阿蓝", "01:42.386",100,100},
    {"3", "星野", "01:45.119",100,50},
    {"4", "小满", "01:48.507",100,0}, {"4", "北北", "01:48.507",100,0},
    {"5", "云舟", "01:51.832",100,0},
    {"6", "焰尾", "01:56.074",100,0}, {"6", "米粒", "01:56.074",100,0},
    {"7", "山茶", "02:03.911",100,0},
    {"--", "鹿鸣", "未完赛",0,0}, {"--", "七喜", "未完赛",0,0}
  }
  resultsVisibleCount = #samples
  hudUi.resultsHasFinishers = true
  lastLayoutKey = ""
  layoutHud()
  for index = 1, #resultsRows do
    local row, sample = resultsRows[index], samples[index]
    row.root:SetActive(sample ~= nil)
    row.rank.text = sample and sample[1] or ""
    setTimeLabel(row, sample and sample[3] or "")
    setNicknameLabel(row, sample and sample[2] or "")
    hudUi.setResultCoins(row,sample and sample[4],sample and sample[5],false)
    hudUi.styleResult(row,sample and tonumber(sample[1]) or 0)
  end
  lastLayoutKey=""
  layoutHud()
  hudUi.resultsScroll.scroll.verticalNormalizedPosition=1
  return true
end

function GeocoreRaceQASetHud(raceState, remainingMilliseconds, rank, participants, coins)
  hudQaState = tostring(raceState or "RACING")
  hudQaRemaining = math.max(0, math.floor(tonumber(remainingMilliseconds) or 134000))
  hudQaRank = math.max(0, math.floor(tonumber(rank) or 1))
  hudQaParticipants = math.max(0, math.floor(tonumber(participants) or 8))
  hudQaCoins = tostring(coins or "12,480")
  lastHudKey = ""
  updateHud()
  return true
end

function GeocoreRaceQAClearHud()
  hudQaState, hudQaRemaining, hudQaRank, hudQaParticipants, hudQaCoins = nil, nil, nil, nil, nil
  lastHudKey = ""
  updateHud()
  return true
end

function GeocoreRaceQAHideResults()
  hudQaResultsVisible, hudQaResultsHidden = false, true
  if resultsRoot ~= nil then resultsRoot:SetActive(false) end
  hudUi.updateSponsorPrompt()
  if hudStatusRoot ~= nil then hudStatusRoot:SetActive(true) end
  if hudAppearanceRoot ~= nil then hudAppearanceRoot:SetActive(true) end
  if hudShopRoot ~= nil then hudShopRoot:SetActive(true) end
  return true
end

function GeocoreRaceQAShowEmptyResults()
  if not createHud() then return false end
  hudQaResultsVisible, hudQaResultsHidden = true, false
  resultsRoot:SetActive(true)
  if hudUi.closeCommerce ~= nil then hudUi.closeCommerce() end
  if sponsorPromptRoot ~= nil then sponsorPromptRoot:SetActive(false) end
  resultsRoot.transform:SetAsLastSibling()
  if hudStatusRoot ~= nil then hudStatusRoot:SetActive(true) end
  if hudAppearanceRoot ~= nil then hudAppearanceRoot:SetActive(true) end
  if hudShopRoot ~= nil then hudShopRoot:SetActive(true) end
  if hudStatusRoot ~= nil then hudStatusRoot.transform:SetAsLastSibling() end
  if hudAppearanceRoot ~= nil then hudAppearanceRoot.transform:SetAsLastSibling() end
  if hudShopRoot ~= nil then hudShopRoot.transform:SetAsLastSibling() end
  hudUi.resultsHeaderRoot:SetActive(false)
  hudUi.resultsEmptyRoot:SetActive(true)
  for index = 1, #resultsRows do
    resultsRows[index].rank.text = ""
    setTimeLabel(resultsRows[index], "")
    setNicknameLabel(resultsRows[index], "")
    resultsRows[index].root:SetActive(false)
  end
  resultsVisibleCount = 0
  hudUi.resultsHasFinishers = false
  lastLayoutKey = ""
  layoutHud()
  return true
end

function GeocoreRaceQACloseResults()
  if hudUi.dismissResults == nil then return false end
  hudUi.dismissResults()
  return resultsRoot == nil or not resultsRoot.activeSelf
end

hudUi.openCheckIn=function()
  hudUi.closeMore()
  if not createHud() then return false end
  if resultsRoot and resultsRoot.activeSelf then return false end
  if hudUi.closeCommerce then hudUi.closeCommerce() end
  hudUi.checkInOpen=true;hudUi.checkInRoot:SetActive(true)
  if sponsorPromptRoot then sponsorPromptRoot:SetActive(false) end
  hudUi.checkInRoot.transform:SetAsLastSibling()
  hudUi.checkInScroll.scroll.verticalNormalizedPosition=1
  lastLayoutKey="";layoutHud();hudUi.refreshCheckIn(true)
  return true
end
function RaceSessionUiOpenActivity() return hudUi.openCheckIn() end
function RaceSessionUiCloseActivity() return hudUi.closeCheckIn() end
function RaceSessionUiOpenMore() return hudUi.openMore() end
function RaceSessionUiCloseMore() return hudUi.closeMore() end
function RaceSessionUiGetMoreState()
  local m=hudUi.more
  return m.open,m.busy,tostring(m.diagnostic or "ready"),#m.routes,m.routes[1].id,m.routes[2].id
end
function RaceSessionUiGetCheckInQAState()
  local s=hudUi.checkInSnapshot or {}
  return hudUi.checkInOpen==true,s.initialized==true,s.unlocked or 0,s.claimed or 0,s.pending or 0,s.lastError or "",s.revision or 0,#(hudUi.checkInRows or {})
end

function RaceSessionUiOpenAppearance()
  hudUi.closeMore()
  if not createHud() then return false end
  if hudUi.refreshEconomy ~= nil then hudUi.refreshEconomy(true, hudUi.currentRaceState) end
  return hudUi.openCommerce ~= nil and hudUi.openCommerce("appearance") or false
end

function RaceSessionUiOpenShop()
  hudUi.closeMore()
  if not createHud() then return false end
  if hudUi.refreshEconomy ~= nil then hudUi.refreshEconomy(true, hudUi.currentRaceState) end
  return hudUi.openCommerce ~= nil and hudUi.openCommerce("shop") or false
end

function RaceSessionUiOpenSponsor()
  hudUi.closeMore()
  if not createHud() then return false end
  if hudUi.refreshEconomy ~= nil then hudUi.refreshEconomy(true, hudUi.currentRaceState) end
  return hudUi.openCommerce ~= nil and hudUi.openCommerce("sponsor") or false
end

function RaceSessionUiGetQAState()
  local promptVisible, commerceVisible = false, false
  if sponsorPromptRoot ~= nil then promptVisible = sponsorPromptRoot.activeSelf end
  if commerceRoot ~= nil then commerceVisible = commerceRoot.activeSelf end
  return hudRoot ~= nil, commerceVisible, tostring(hudUi.commerceMode or "closed"),
    hudUi.economyAvailable == true, hudUi.economyInitialized == true, tostring(hudCoinSnapshot or "--"),
    promptVisible, hudUi.sponsorEligible == true, math.floor(tonumber(hudUi.sponsorTotal) or 0),
    math.floor(tonumber(hudUi.sponsorPersonal) or 0), #hudUi.uiListeners, #hudUi.inputListeners,
    tostring(hudUi.lastCommerceMessage or "")
end

function RaceSessionUiGetSponsorState()
  return hudUi.sponsorEntryVisible == true, hudUi.sponsorEligible == true,
    tostring(hudUi.sponsorDisplayStatus or "SYNCING"), tostring(hudUi.sponsorReadError or "none"),
    tonumber(hudUi.sponsorReadPending) or 0, tonumber(hudUi.sponsorRetrySeconds) or 0,
    hudUi.sponsorSubmitButton ~= nil and hudUi.sponsorSubmitButton.interactable == true,
    hudUi.sponsorStatusLabel()
end

function RaceSessionApplyCoinSnapshot(balance, initialized, lastError, confirmedKnown, pendingDelta, confirmedBalance, displayRevision, source, inFlightDelta)
  -- Display may include verified award receipts still awaiting a cloud commit;
  -- purchasing continues to use only the separately confirmed balance.
  local loaded, value = decodeLoadedCoinBalance(confirmedBalance or balance, initialized)
  hudCoinSnapshot = hudUi.resolveCoinDisplay(confirmedBalance, initialized, balance,confirmedKnown,source,lastError)
  hudUi.economyLastError = tostring(lastError or "")
  hudUi.economyInitialized = loaded
  if loaded then hudUi.economyCoins = value end
  hudUi.coinDisplayRevision = tonumber(displayRevision) or 0
  hudUi.coinDisplaySource = tostring(source or "unknown")
  hudUi.coinPendingDelta = math.max(0, math.floor(tonumber(pendingDelta) or 0))
  lastHudKey = ""
  return true
end

function OnDestroy()
  hudUi.identity.dead = true
  hudUi.identity.invalidate()
  for _,sprite in ipairs(hudUi.v8Sprites or {}) do pcall(function()UnityEngine.Object.Destroy(sprite)end) end
  for _,texture in ipairs(hudUi.v8Textures or {}) do pcall(function()UnityEngine.Object.Destroy(texture)end) end
  hudUi.v8Sprites,hudUi.v8Textures={},{}
  for _,route in ipairs(hudUi.more.routes or {})do
    if route.artSprite~=nil then pcall(function()UnityEngine.Object.Destroy(route.artSprite)end)end
    if route.artTexture~=nil then pcall(function()UnityEngine.Object.Destroy(route.artTexture)end)end
    route.artSprite,route.artTexture=nil,nil
  end
  hudUi.releaseRaceSeatInput()
  for _,rt in ipairs(hudUi.glassRT or {})do pcall(function()rt:Release();UnityEngine.Object.Destroy(rt)end)end
  for _,asset in ipairs({hudUi.artTexture,hudUi.sheenTexture})do pcall(function()UnityEngine.Object.Destroy(asset)end)end
  hudUi.glassRT,hudUi.glassViews=nil,{}
  if rosterChangeHandle ~= nil then pcall(function() rosterChangeHandle:Dispose() end) end
  cleanupHudListeners()
  hudUi.appearanceOpenHandler, hudUi.shopOpenHandler, hudUi.sponsorOpenHandler = nil, nil, nil
  hudUi.commerceCloseHandler, hudUi.equipTitleHandler, hudUi.equipWingHandler, hudUi.equipHaloHandler = nil, nil, nil, nil
  hudUi.buyWingHandler, hudUi.buyHaloHandler = nil, nil
  hudUi.sponsorTenHandler, hudUi.sponsorHundredHandler, hudUi.sponsorFiveHundredHandler = nil, nil, nil
  hudUi.sponsorThousandHandler, hudUi.sponsorFiveThousandHandler = nil, nil
  hudUi.sponsorSubmitHandler, hudUi.sponsorAmountHandler = nil, nil
  hudUi.resultsCloseHandler, hudUi.resultsCloseButton = nil, nil
  -- Preview/room teardown owns these scene-local runtime objects. Explicitly
  -- destroying them again during unload produces engine NullReference noise.
  hudAppearanceButton, hudShopButton = nil, nil
  hudRoot, commerceRoot, sponsorPromptRoot, zoneVisualRoot, managerHolder, validatorHolder, economyHolder = nil, nil, nil, nil, nil, nil, nil
end

function OnDisable()
  hudUi.releaseRaceSeatInput()
end

