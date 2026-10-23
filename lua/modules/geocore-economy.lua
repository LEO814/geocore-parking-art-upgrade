---@id 88e3278d-79d2-421b-899d-743901bdb6c9
-- 地心飞车 V1.2：按 playerOpenID 隔离的角色经济、外观、奖励 outbox 与比赛赞助。
-- LOCAL-0911：正式经济使用本机 PlayerPrefs；不可读时重置，不依赖服务器存储。
-- EDITOR-ECONOMY-0906: explicit verified-editor test namespace; never production cache/cloud fallback.
-- STORAGE-REPAIR-0905: identity/network gating, scoped async loads and explicit failure state.
-- COIN-PROJECTION-0905: show verified pending awards without spending or overwriting cloud truth.
-- STORAGE-REPAIR-0911: independent calendar, durable receipts, explicit unknown UI.
---@start
---@var editorTestEconomy:boolean=false
---@name 编辑器测试经济
---@desc 仅经宿主验证的编辑器环境可启用；测试存档不接触正式云数据，切换后需重新本地运行
---@group 经济测试
---@var initialCoins:number=10000
---@name 测试玩家初始金币
---@desc 仅用于新测试会话或测试重置；不补发正式已有档
---@range 0,1000000,1
---@group 经济测试
---@var newPlayerCoins:number=100
---@name 正式新玩家初始金币
---@desc 仅首次创建正式角色存档时发放；不覆盖已有余额，不补发旧档
---@range 0,1000000,1
---@group 角色存储
---@var testResetVersion:number=1
---@name 测试存档重置版本
---@desc 修改此版本会清空当前测试会话存档并重新应用初始金币；不影响正式存档
---@range 1,1000000,1
---@group 经济测试
---@var sponsorMinParticipants:number=1
---@name 赞助最低参赛人数
---@desc 达到此参赛人数后开放赞助；仅限本局已参赛角色在等待发车阶段赞助
---@range 1,30,1
---@group 比赛赞助
---@var wingPrice:number=500
---@name 熔核之翼价格
---@desc 商店标价与权威扣款共用；0表示免费，修改后重新本地运行
---@range 0,1000000,1
---@group 商品价格
---@var haloPrice:number=800
---@name 地心光环价格
---@desc 商店标价与权威扣款共用；0表示免费，修改后重新本地运行
---@range 0,1000000,1
---@group 商品价格
---@varSync economyAwardLedger:string
---@varSync checkInFirstEnterLedger:string
---@varSync equippedVisualSnapshot:string
---@varSync sponsorCommittedLedger:string
---@end

local E = {}

function E.configPrice(value, fallback)
  local price=tonumber(value)
  if price==nil or price~=price or price==math.huge or price==-math.huge then return fallback end
  return math.max(0,math.min(1000000,math.floor(price)))
end

E.U = CS.UnityEngine
E.Time = E.U.Time
E.ActorService = CS.DouyinActorService
E.PlayerService = CS.DouyinPlayerService
E.cfg = {
  schema = "GEOCORE_COMMERCE_V3",
  storeName = "GeocoreCharacterV1",
  profileKey = "CommerceProfileV1",
  managerId = "650f9bb2-f983-4c39-9b98-456d89b19dd2",
  sessionId = "3cb5f0e7-b1a4-4aa0-8d32-905a47bd2f26",
  sponsorEnabled = true,
  sponsorMinParticipants = math.max(1, math.min(30, math.floor(tonumber(sponsorMinParticipants) or 1))),
  sponsorMinAmount = 10,
  sponsorMaxAmount = 5000,
  systemSponsorPerParticipant = 100,
  sponsorRankWeight = 0.70,
  sponsorPersonalWeight = 0.30,
  normalFinishReward = 100,
  firstPlaceReward = 200,
  retryBaseSeconds = 0.75,
  retryMaxSeconds = 30,
  loadTimeoutSeconds = 30,
  sponsorReadTimeoutSeconds = 6, -- WAITING is short: allow a timed-out read to retry within the window.
  recentAwardLimit = 512,
  recentTransactionLimit = 256,
  sponsorCycleLimit = 16,
  catalog = {
    TITLE_DEFAULT = { category = "title", displayName = "我是新手", price = 0, shop = false },
    TITLE_VETERAN_DRIVER = { category = "title", displayName = "老司机", price = 0, shop = false },
    WING_01 = { category = "wing", displayName = "熔核之翼", price = E.configPrice(wingPrice,500) },
    HALO_01 = { category = "halo", displayName = "地心光环", price = E.configPrice(haloPrice,800) },
  },
}
E.vehicleNames = {
  "玩具", "莓爆花", "绯樱", "暴走", "烈焰", "赤巡", "薄荷糖",
  "甜品", "牛牛", "牛粉", "积木", "宝宝巴", "星梦巴", "爆米花",
  "暮翼巡游", "甜咒南瓜",
}
E.profile = nil
E.storageQueue, E.storageRunning = {}, false
E.visualRequests, E.nextVisualSync = {}, 0
E.calendar = { nextAt = 0, seconds = nil, sampledAt = nil, lastError = "TIME_SYNCING" }
E.localStore = nil
E.localState = {
  openId = "", actorId = 0, backend = "pending", initialized = false,
  loading = false, retryAt = 0, retryCount = 0, lastError = "none",
  loadGeneration = 0, loadingStartedAt = 0, lastStoreCode = 0,
  pendingOperations = {}, pendingAwards = {}, inFlightAwardId = "",
  actionSequence = 0, lastAction = "", qaOverride = nil,
  displayRevision = 0, displaySignature = "",
}
E.actorById, E.playerByActorId, E.openIdByActorId, E.actorIdByOpenId = {}, {}, {}, {}
E.managerHolder, E.sessionHolder = nil, nil
E.room = {
  cycleId = 0, roundKey = "", phase = "", locked = false, reconstructing = false,
  reconstructPending = 0, participants = {}, participantByOpenId = {}, vehicles = {},
  sponsorshipByOpenId = {}, playerSponsor = 0, systemSponsor = 0, pool = 0,
  open = false, frozen = false, revision = 0, settled = false,
  settlement = nil, nextBroadcastAt = 0,
}
E.roomView = {
  cycleId = 0, phase = "", open = false, frozen = false, participantCount = 0,
  playerSponsor = 0, systemSponsor = 0, pool = 0, revision = 0,
  sponsorBySafeOpenId = {}, settlementSnapshot = "",
}
E.outbox = {}
E.checkIn = { firstByOpenId = {}, busyByOpenId = {}, localError = "none", nextTick = 0,
  refreshRequested = false, revision = 0, signature = "", observedProfiles = {}, visualRevision = 0 }
E.tick = { identityAt = 0, profileAt = 0, roomAt = 0, outboxAt = 0, operationsAt = 0 }
E.metrics = {
  datastoreReads = 0, datastoreWrites = 0, datastoreFailures = 0,
  awardsQueued = 0, awardsConfirmed = 0, duplicateAwards = 0,
  transactionsConfirmed = 0, sponsorRevisions = 0,
}
-- An isolated in-memory backend, never a fallback for cloud errors. The mode is
-- chosen once per script/preview session; a disabled test session cannot silently
-- become a cloud session and flush its synthetic operations into production.
E.testBackend = { configured = false, mode = "cloud", generation = 0,
  namespace = "GEOCORE_EDITOR_TEST_SESSION_V1",
  profiles = {}, caches = {}, ledgers = {}, busy = {}, initialCoins = 0, resetVersion = 1 }

function E.editorEnvironmentVerified()
  -- Unity IDE or the independently verified Creator native debugger host.
  -- Creator is a WebGLPlayer: isEditor=false is normal. The native editor root
  -- and camera must both exist; a product name alone never enables test minting.
  local ok, value = pcall(function() return E.U.Application.isEditor end)
  if ok and value == true then return true end
  local creatorOk, creator = pcall(function()
    local api = CS.LogicApiMono
    return E.U.Application.productName == "DouyinWorldDebugger"
      and api ~= nil and api.EditorRoot ~= nil and api.EditorRoot.name == "EditorRoot"
      and api.Ins ~= nil and api.Ins.EditorCamera ~= nil
  end)
  return creatorOk and creator == true
end

function E.testInteger(value, fallback, low, high)
  local number = tonumber(value)
  if number == nil or number ~= number or number == math.huge or number == -math.huge then number = fallback end
  return math.max(low, math.min(high, math.floor(number)))
end

function E.ensureBackend()
  local test = E.testBackend
  if test.configured then return end
  test.configured = true
  test.requested = editorTestEconomy == true
  test.mode = test.requested and E.editorEnvironmentVerified() and "editor-test" or "cloud"
  test.initialCoins = E.testInteger(initialCoins, 10000, 0, 1000000)
  test.resetVersion = E.testInteger(testResetVersion, 1, 1, 1000000)
  test.generation = test.generation + 1
end

function E.isTestBackend()
  E.ensureBackend()
  return E.testBackend.mode == "editor-test"
end

function E.testBackendAllowed()
  return E.isTestBackend() and editorTestEconomy == true and E.editorEnvironmentVerified()
end

function E.confirmedBackend()
  return E.isTestBackend() and "editor-test" or "local"
end

function E.profileReady()
  return E.localState.initialized == true and E.localState.backend == E.confirmedBackend()
    and (not E.isTestBackend() or E.testBackendAllowed())
end

function E.storageAvailable()
  if E.isTestBackend() then return E.testBackendAllowed() end
  return E.U.PlayerPrefs ~= nil
end

function E.runStorage(callback)
  E.ensureBackend()
  local test, generation = E.testBackend, E.testBackend.generation
  if E.isTestBackend() then
    if not E.testBackendAllowed() then error("EDITOR_TEST_DISABLED", 0) end
    return callback() -- non-yielding atomic test transactions, no cloud coroutine
  end
  E.storageQueue[#E.storageQueue + 1] = { callback = callback, test = test, generation = generation }
  return E.pumpStorage()
end

function E.pumpStorage()
  if E.destroyed or E.storageRunning or #E.storageQueue == 0 then return true end
  local task = table.remove(E.storageQueue, 1)
  E.storageRunning = true
  local started, err = pcall(function() E.runStorage(function()
    local ok, failure = pcall(function()
      if not E.destroyed and task.test == E.testBackend and task.generation == E.testBackend.generation then task.callback() end
    end)
    E.storageRunning = false
    if not ok and not E.destroyed then E.localState.lastError = "STORAGE_CALLBACK_FAILED" end
    if not E.destroyed then E.pumpStorage() end
  end) end)
  if not started then
    E.storageRunning = false
    error(err, 0)
  end
  return true
end

function E.getStore(openId)
  openId = tostring(openId or "")
  if not E.isTestBackend() then return -2, nil end -- production uses device adapter below
  if openId == "" or not E.testBackendAllowed() then return -1, nil end
  local test, generation = E.testBackend, E.testBackend.generation
  if test.profiles[openId] == nil then
    local profile = E.defaultProfile()
    profile.Coins = test.initialCoins
    test.profiles[openId] = E.encodeProfile(profile)
  end
  local function current(key)
    return key == E.cfg.profileKey and test == E.testBackend and generation == test.generation
      and not E.destroyed and E.testBackendAllowed()
  end
  local store = {}
  function store:GetData(key)
    if not current(key) then return -1, nil end
    return 0, test.profiles[openId]
  end
  function store:UpdateData(key, transform)
    if not current(key) or test.busy[openId] then return -1, nil end
    test.busy[openId] = true
    local ok, value = pcall(transform, test.profiles[openId])
    test.busy[openId] = nil
    if not ok then error(value, 0) end
    if not current(key) or type(value) ~= "string" then return -1, nil end
    test.profiles[openId] = value
    return 0, value
  end
  function store:SetData(key, value)
    if not current(key) or test.busy[openId] then return -1, nil end
    test.profiles[openId] = value
    return 0, value
  end
  return 0, store
end

function E.backendLedger(name, productionLedger)
  if not E.isTestBackend() then return productionLedger end
  local test, generation = E.testBackend, E.testBackend.generation
  return {
    GetValue = function() return test.ledgers[name] or "" end,
    SetValue = function(_, value)
      if not E.testBackendAllowed() or test ~= E.testBackend or generation ~= test.generation then
        error("EDITOR_TEST_DISABLED", 0)
      end
      test.ledgers[name] = tostring(value or "")
    end,
  }
end

function E.refreshTestConfiguration()
  E.ensureBackend()
  if not E.testBackendAllowed() then return false end
  local version = E.testInteger(testResetVersion, 1, 1, 1000000)
  if version == E.testBackend.resetVersion then return false end
  local test = E.testBackend
  test.generation = test.generation + 1
  test.resetVersion = version
  test.initialCoins = E.testInteger(initialCoins, 10000, 0, 1000000)
  test.profiles, test.caches, test.ledgers, test.busy = {}, {}, {}, {}
  E.outbox = {}
  E.checkIn.firstByOpenId, E.checkIn.busyByOpenId, E.checkIn.observedProfiles = {}, {}, {}
  E.room.locked, E.room.reconstructing, E.room.open, E.room.settled = false, false, false, false
  E.loadLocalCache(E.localState.openId)
  E.beginLocalLoad()
  E.tick.roomAt = 0
  return true
end

function E.now()
  local ok, value = pcall(function() return E.Time.realtimeSinceStartupAsDouble end)
  if not ok then value = E.Time.realtimeSinceStartup end
  return tonumber(value) or 0
end

function E.integer(value, low, high)
  local number = math.floor(tonumber(value) or 0)
  if low ~= nil and number < low then number = low end
  if high ~= nil and number > high then number = high end
  return number
end

function E.split(value, delimiter)
  local result, text, startAt = {}, tostring(value or ""), 1
  delimiter = tostring(delimiter or "")
  if delimiter == "" then return { text } end
  while true do
    local foundAt = string.find(text, delimiter, startAt, true)
    if foundAt == nil then result[#result + 1] = string.sub(text, startAt); break end
    result[#result + 1] = string.sub(text, startAt, foundAt - 1)
    startAt = foundAt + #delimiter
  end
  return result
end

function E.token(value, maximumLength)
  local text = string.gsub(tostring(value or ""), "[^%w_%-]", "")
  maximumLength = E.integer(maximumLength or 120, 1, 512)
  if #text > maximumLength then text = string.sub(text, 1, maximumLength) end
  return text
end

function E.stableHash(value)
  local hash = 104729
  local text = tostring(value or "")
  for index = 1, #text do hash = (hash * 131 + string.byte(text, index)) % 2147483647 end
  return string.format("%08x", hash)
end

function E.copyMap(source)
  local result = {}
  for key, value in pairs(source or {}) do result[key] = value end
  return result
end

function E.encodeSet(source)
  local values = {}
  for key, value in pairs(source or {}) do
    local safe = E.token(key, 64)
    if value == true and safe ~= "" then values[#values + 1] = safe end
  end
  table.sort(values)
  return table.concat(values, ",")
end

function E.decodeSet(value)
  local result = {}
  for _, raw in ipairs(E.split(value, ",")) do
    local safe = E.token(raw, 64)
    if safe ~= "" then result[safe] = true end
  end
  return result
end

function E.encodeEquipment(source)
  local values = {}
  for _, category in ipairs({ "title", "wing", "halo" }) do
    local itemId = E.token((source or {})[category], 64)
    if itemId ~= "" then values[#values + 1] = category .. "=" .. itemId end
  end
  return table.concat(values, ",")
end

function E.decodeEquipment(value)
  local result = {}
  for _, raw in ipairs(E.split(value, ",")) do
    local pair = E.split(raw, "=")
    local category, itemId = E.token(pair[1], 16), E.token(pair[2], 64)
    if (category == "title" or category == "wing" or category == "halo") and itemId ~= "" then
      result[category] = itemId
    end
  end
  return result
end

function E.trimArray(values, limit)
  while #(values or {}) > limit do table.remove(values, 1) end
  return values
end

function E.encodeArray(values, limit)
  local encoded = {}
  local first = math.max(1, #(values or {}) - limit + 1)
  for index = first, #(values or {}) do
    local safe = E.token(values[index], 180)
    if safe ~= "" then encoded[#encoded + 1] = safe end
  end
  return table.concat(encoded, ",")
end

function E.decodeArray(value, limit)
  local result = {}
  for _, raw in ipairs(E.split(value, ",")) do
    local safe = E.token(raw, 180)
    if safe ~= "" then result[#result + 1] = safe end
  end
  return E.trimArray(result, limit)
end

function E.encodeSponsorCycles(source)
  local rows = {}
  for rawKey, amount in pairs(source or {}) do
    local roundKey = E.token(rawKey, 64)
    if roundKey ~= "" then rows[#rows + 1] = { roundKey = roundKey, amount = E.integer(amount, 0, E.cfg.sponsorMaxAmount) } end
  end
  table.sort(rows, function(left, right) return left.roundKey < right.roundKey end)
  local first, values = math.max(1, #rows - E.cfg.sponsorCycleLimit + 1), {}
  for index = first, #rows do values[#values + 1] = rows[index].roundKey .. "=" .. tostring(rows[index].amount) end
  return table.concat(values, ",")
end

function E.decodeSponsorCycles(value)
  local result = {}
  for _, raw in ipairs(E.split(value, ",")) do
    local pair = E.split(raw, "=")
    local roundKey = E.token(pair[1], 64)
    if roundKey ~= "" then result[roundKey] = E.integer(pair[2], 0, E.cfg.sponsorMaxAmount) end
  end
  return result
end

function E.decodeCheckIn(value)
  if value == nil or value == "" then return nil end
  local f = E.split(value, ",")
  local first, day, mask = tonumber(f[2]), tonumber(f[3]), tonumber(f[4])
  if f[1] ~= "CI1" or #f ~= 4 or first == nil or first ~= math.floor(first)
    or first < 1577836800 or first > 4102444800 or day == nil
    or day ~= math.floor((first + 28800) / 86400) or mask == nil
    or mask ~= math.floor(mask) or mask < 0 or mask > 127 then
    return { invalid = true, raw = tostring(value) }
  end
  return { schemaVersion = 1, firstEnterAtServerSeconds = first,
    firstEnterBeijingDay = day, claimedMask = mask }
end

function E.encodeCheckIn(value)
  if value == nil then return "" end
  if value.invalid then return tostring(value.raw or "INVALID") end
  return table.concat({ "CI1", tostring(value.firstEnterAtServerSeconds),
    tostring(value.firstEnterBeijingDay), tostring(value.claimedMask or 0) }, ",")
end

function E.defaultProfile()
  return {
    Coins = 0,
    CosmeticInventoryV1 = { TITLE_DEFAULT = true },
    EquippedCosmeticsV1 = { title = "TITLE_DEFAULT" },
    extraProfileFields = { "NOVICE1" },
    recentAwards = {},
    recentTransactions = {},
    SponsorTotalsV1 = {},
    revision = 1,
  }
end

function E.newCloudProfile()
  local profile = E.defaultProfile()
  profile.Coins = E.configPrice(newPlayerCoins, 100)
  local now = E.checkInServerSeconds()
  if now ~= nil then profile.CheckIn7V1 = { schemaVersion = 1,
    firstEnterAtServerSeconds = now, firstEnterBeijingDay = E.checkInDay(now), claimedMask = 0 } end
  return profile
end

function E.validProfile(raw)
  local text = tostring(raw or "")
  local version, balance = text:match("^(V[123]);([^;]+);")
  local number = tonumber(version and balance or text)
  return number ~= nil and number == number and number >= 0 and number < math.huge
    and number == math.floor(number)
end

function E.decodeProfile(value)
  local fields = E.split(value, ";")
  local profile = E.defaultProfile()
  if fields[1] == "V3" then
    profile.Coins = E.integer(fields[2], 0)
    profile.CosmeticInventoryV1 = E.decodeSet(fields[3])
    profile.EquippedCosmeticsV1 = E.decodeEquipment(fields[4])
    profile.recentAwards = E.decodeArray(fields[5], E.cfg.recentAwardLimit)
    profile.recentTransactions = E.decodeArray(fields[6], E.cfg.recentTransactionLimit)
    profile.SponsorTotalsV1 = E.decodeSponsorCycles(fields[7])
    profile.revision = E.integer(fields[8], 1)
    profile.CheckIn7V1 = E.decodeCheckIn(fields[9])
    profile.extraProfileFields = {}
    for i = 10, #fields do profile.extraProfileFields[#profile.extraProfileFields + 1] = fields[i] end
  elseif tonumber(value) ~= nil then
    profile.Coins = E.integer(value, 0)
  elseif fields[1] == "V1" or fields[1] == "V2" then
    profile.Coins = E.integer(fields[2], 0)
    profile.CosmeticInventoryV1 = E.decodeSet(fields[3])
    profile.EquippedCosmeticsV1 = E.decodeEquipment(fields[4])
    profile.recentAwards = E.decodeArray(fields[5], E.cfg.recentAwardLimit)
    profile.recentTransactions = E.decodeArray(fields[6], E.cfg.recentTransactionLimit)
    profile.revision = E.integer(fields[7], 1)
    profile.extraProfileFields = {}
  end
  -- V1.2 自带一个不可购买的基础头衔；旧档在下一次原子写入时完成迁移。
  profile.CosmeticInventoryV1.TITLE_DEFAULT = true
  -- One-time empty-slot migration. The durable marker preserves a later
  -- deliberate unequip; never overwrite another equipped title or extra data.
  local migrated=false
  for _,extra in ipairs(profile.extraProfileFields or {}) do if extra=="NOVICE1" then migrated=true end end
  if not migrated then
    if not profile.EquippedCosmeticsV1.title or profile.EquippedCosmeticsV1.title=="" then
      profile.EquippedCosmeticsV1.title="TITLE_DEFAULT"
    end
    profile.extraProfileFields[#profile.extraProfileFields+1]="NOVICE1"
  end
  return profile
end

function E.encodeProfile(profile)
  profile = profile or E.defaultProfile()
  E.trimArray(profile.recentAwards, E.cfg.recentAwardLimit)
  E.trimArray(profile.recentTransactions, E.cfg.recentTransactionLimit)
  local fields = {
    "V3",
    tostring(E.integer(profile.Coins, 0)),
    E.encodeSet(profile.CosmeticInventoryV1),
    E.encodeEquipment(profile.EquippedCosmeticsV1),
    E.encodeArray(profile.recentAwards, E.cfg.recentAwardLimit),
    E.encodeArray(profile.recentTransactions, E.cfg.recentTransactionLimit),
    E.encodeSponsorCycles(profile.SponsorTotalsV1),
    tostring(E.integer(profile.revision, 1)),
    E.encodeCheckIn(profile.CheckIn7V1),
  }
  for _, value in ipairs(profile.extraProfileFields or {}) do fields[#fields + 1] = value end
  return table.concat(fields, ";")
end

function E.arrayContains(values, expected)
  expected = E.token(expected, 180)
  for _, value in ipairs(values or {}) do if value == expected then return true end end
  return false
end

function E.transactionStatus(profile, transactionId)
  local prefix = E.token(transactionId, 96) .. "_"
  for index = #(profile.recentTransactions or {}), 1, -1 do
    local value = tostring(profile.recentTransactions[index] or "")
    if string.sub(value, 1, #prefix) == prefix then return string.sub(value, #prefix + 1) end
  end
  return ""
end

function E.appendTransaction(profile, transactionId, status)
  local value = E.token(transactionId, 96) .. "_" .. E.token(status, 80)
  profile.recentTransactions[#profile.recentTransactions + 1] = value
  E.trimArray(profile.recentTransactions, E.cfg.recentTransactionLimit)
end

function E.prefsKey(suffix)
  return E.cfg.schema .. "." .. tostring(E.localState.openId or "") .. "." .. tostring(suffix or "")
end

function E.encodePendingOperations()
  local rows = {}
  for transactionId, row in pairs(E.localState.pendingOperations) do
    rows[#rows + 1] = table.concat({ E.token(transactionId, 96), E.token(row.kind, 16),
      E.token(row.a, 64), E.token(row.b, 64), tostring(E.integer(row.cycleId, 0)) }, "^")
  end
  table.sort(rows)
  return table.concat(rows, ",")
end

function E.decodePendingOperations(value)
  local result = {}
  for _, raw in ipairs(E.split(value, ",")) do
    local fields = E.split(raw, "^")
    local transactionId = E.token(fields[1], 96)
    local kind = E.token(fields[2], 16)
    if transactionId ~= "" and (kind == "BUY" or kind == "EQUIP" or kind == "SPONSOR"
      or kind == "CHECKIN_INIT" or kind == "CHECKIN_CLAIM") then
      result[transactionId] = { kind = kind, a = E.token(fields[3], 64), b = E.token(fields[4], 64),
        cycleId = E.integer(fields[5], 0), attempts = 0, nextAt = 0 }
    end
  end
  return result
end

function E.encodePendingAwards()
  local rows = {}
  for awardId, row in pairs(E.localState.pendingAwards) do
    rows[#rows + 1] = table.concat({ E.token(awardId, 160), tostring(E.integer(row.amount, 1, 1000000)),
      E.token(row.reason, 32), tostring(E.integer(row.cycleId, 0)),
      E.token(row.deliveryToken, 96), row.cloudObserved == true and "1" or "0" }, "^")
  end
  table.sort(rows)
  return table.concat(rows, ",")
end

function E.decodePendingAwards(value)
  local result = {}
  for _, raw in ipairs(E.split(value, ",")) do
    local fields = E.split(raw, "^")
    local awardId, amount = E.token(fields[1], 160), E.integer(fields[2], 0, 1000000)
    local deliveryToken = E.token(fields[5], 96)
    if awardId ~= "" and amount > 0 and deliveryToken ~= "" then
      result[awardId] = { amount = amount, reason = E.token(fields[3], 32), cycleId = E.integer(fields[4], 0), attempts = 0 }
      result[awardId].deliveryToken, result[awardId].nextAt = deliveryToken, 0
      result[awardId].cloudObserved = fields[6] == "1"
    end
  end
  return result
end

function E.saveLocalCache()
  if E.localState.openId == "" then return false end
  if E.isTestBackend() then
    if not E.testBackendAllowed() then return false end
    E.testBackend.caches[E.localState.openId] = {
      pendingOperations = E.encodePendingOperations(), pendingAwards = E.encodePendingAwards(),
    }
    return true
  end
  return pcall(function()
    if E.profile ~= nil and (E.localState.initialized or E.localState.cacheAvailable) then
      E.U.PlayerPrefs.SetString(E.prefsKey("Profile"), E.encodeProfile(E.profile))
      E.U.PlayerPrefs.SetInt(E.prefsKey("HasProfile"), 1)
    end
    E.U.PlayerPrefs.SetString(E.prefsKey("PendingOperations"), E.encodePendingOperations())
    E.U.PlayerPrefs.SetString(E.prefsKey("PendingAwards"), E.encodePendingAwards())
    E.U.PlayerPrefs.Save()
  end)
end

function E.loadLocalCache(openId)
  E.localState.loadGeneration = E.localState.loadGeneration + 1
  E.localState.loading, E.localState.loadingStartedAt = false, 0
  E.localState.retryAt, E.localState.retryCount = 0, 0
  E.localState.lastError, E.localState.lastStoreCode = "none", 0
  E.localState.lastReadCode, E.localState.lastSuccessAt = nil, nil
  E.localState.lastAction, E.localState.qaOverride = "", nil
  E.localState.displaySignature = ""
  E.checkIn.localError, E.checkIn.refreshRequested, E.checkIn.signature = "none", false, ""
  E.checkIn.nextTick = 0
  E.checkIn.ownerInitAcknowledged = false
  E.nextVisualSync = 0
  E.localState.cacheAvailable = false
  E.localStore = nil
  E.localState.openId = tostring(openId or "")
  E.profile = E.defaultProfile()
  E.localState.pendingOperations, E.localState.pendingAwards = {}, {}
  E.localState.inFlightAwardId, E.localState.backend, E.localState.initialized = "", "pending", false
  if E.localState.openId == "" then return end
  if E.isTestBackend() then
    local cached = E.testBackend.caches[E.localState.openId]
    if cached ~= nil then
      E.localState.pendingOperations = E.decodePendingOperations(cached.pendingOperations)
      E.localState.pendingAwards = E.decodePendingAwards(cached.pendingAwards)
    end
    return
  end
  pcall(function()
    if E.U.PlayerPrefs.GetInt(E.prefsKey("HasProfile"), 0) == 1 then
      local cached=E.U.PlayerPrefs.GetString(E.prefsKey("Profile"), "")
      local value=tonumber(tostring(cached):match("^V[123];([^;]+);"))
      if value~=nil and value==value and value>=0 and value<math.huge then
        E.profile = E.decodeProfile(cached)
        E.localState.backend,E.localState.cacheAvailable = "cache",true
      end
    end
    E.localState.pendingOperations = E.decodePendingOperations(E.U.PlayerPrefs.GetString(E.prefsKey("PendingOperations"), ""))
    E.localState.pendingAwards = E.decodePendingAwards(E.U.PlayerPrefs.GetString(E.prefsKey("PendingAwards"), ""))
  end)
end

function E.actorId(actor)
  if actor == nil then return 0 end
  local ok, value = pcall(function() return actor.actorID end)
  if not ok or E.integer(value, 0) == 0 then ok, value = pcall(function() return actor.ID end) end
  if not ok or E.integer(value, 0) == 0 then ok, value = pcall(function() return actor.id end) end
  return ok and E.integer(value, 0) or 0
end

function E.playerOpenId(player)
  if player == nil then return "" end
  local ok, value = pcall(function() return player.playerOpenID end)
  return ok and tostring(value or "") or ""
end

function E.localPlayer()
  local player = nil
  if E.PlayerService ~= nil then pcall(function() player = E.PlayerService.GetLocalPlayer() end) end
  return player
end

function E.localActor()
  local actor = nil
  if E.ActorService ~= nil then pcall(function() actor = E.ActorService.GetLocalActor() end) end
  return actor
end

function E.observePlayer(player, actor)
  if player == nil then return false end
  if actor == nil then pcall(function() actor = player:GetActor() end) end
  local actorId, openId = E.actorId(actor), E.playerOpenId(player)
  if actorId == 0 or openId == "" then return false end
  E.actorById[actorId], E.playerByActorId[actorId], E.openIdByActorId[actorId] = actor, player, openId
  E.actorIdByOpenId[openId] = actorId
  return true
end

function E.refreshIdentities()
  -- Persistent identity belongs to DouyinPlayer, never to an undocumented Actor UID.
  local ok, players = pcall(function() return E.PlayerService.GetPlayers() end)
  if ok and players ~= nil then
    E.actorById, E.playerByActorId, E.openIdByActorId, E.actorIdByOpenId = {}, {}, {}, {}
    for index = 0, players.Length - 1 do E.observePlayer(players[index], nil) end
  end
  local player = E.localPlayer()
  if player ~= nil then E.observePlayer(player, E.localActor()) end
  local localOpenId = E.playerOpenId(player)
  if localOpenId ~= "" and E.localState.openId ~= localOpenId then
    E.saveLocalCache()
    E.loadLocalCache(localOpenId)
    E.emitProfile()
  end
  E.localState.actorId = E.actorId(E.localActor())
end

function E.isAuthority()
  local owned = false
  pcall(function() owned = self:HasOwnership() end)
  return owned == true
end

function E.networkSettled()
  local ok, settled = pcall(function()
    local net = DouyinNetService or CS.DouyinNetService
    return net ~= nil and net.isNetworkSettled == true
  end)
  return ok and settled == true
end

function E.resolveHolders()
  if E.managerHolder == nil or E.managerHolder.script == nil then
    pcall(function() E.managerHolder = self.gameObject:GetDouyinScript(E.cfg.managerId) end)
  end
  if E.sessionHolder == nil or E.sessionHolder.script == nil then
    pcall(function() E.sessionHolder = self.gameObject:GetDouyinScript(E.cfg.sessionId) end)
  end
  return E.managerHolder ~= nil and E.managerHolder.script ~= nil
end

function E.coinDisplayState()
  -- E.profile.Coins remains the last confirmed profile value. Never add pending
  -- rewards to that field: purchases and cloud writes must not consume estimates.
  local confirmed = E.integer(E.profile and E.profile.Coins or 0, 0)
  local known = E.localState.initialized == true or E.localState.cacheAvailable == true
  local pending, inFlight = 0, 0
  for awardId, row in pairs(E.localState.pendingAwards or {}) do
    if row.cloudObserved ~= true and not E.arrayContains(E.profile and E.profile.recentAwards, awardId) then
      local amount = E.integer(row.amount, 0, 1000000)
      pending = pending + amount
      if awardId == E.localState.inFlightAwardId then inFlight = inFlight + amount end
    end
  end
  local source = pending > 0 and "pending"
    or (E.profileReady() and known and E.confirmedBackend())
    or (known and "cache" or "unknown")
  local signature = table.concat({ tostring(E.localState.openId or ""), confirmed,
    pending, inFlight, tostring(known), source, tostring(E.localState.lastError or "none") }, "|")
  if signature ~= E.localState.displaySignature then
    E.localState.displaySignature = signature
    E.localState.displayRevision = E.integer(E.localState.displayRevision, 0) + 1
  end
  return confirmed + pending, known, source, E.localState.lastError,
    pending, confirmed, E.localState.displayRevision, inFlight
end

function E.emitProfile()
  if E.profile == nil then return end
  local display, known, source, err, pending, confirmed, revision, inFlight = E.coinDisplayState()
  E.resolveHolders()
  if E.sessionHolder ~= nil and E.sessionHolder.script ~= nil
    and E.sessionHolder.script.RaceSessionApplyCoinSnapshot ~= nil then
    pcall(function()
      E.sessionHolder.script.RaceSessionApplyCoinSnapshot(display, E.localState.initialized, err,
        known, pending, confirmed, revision, source, inFlight)
    end)
  end
end

function E.retryDelay(attempt)
  local base = E.cfg.retryBaseSeconds * (2 ^ math.min(E.integer(attempt, 0), 6))
  return math.min(E.cfg.retryMaxSeconds, base * (0.85 + math.random() * 0.30))
end

function E.failLocal(reason)
  E.metrics.datastoreFailures = E.metrics.datastoreFailures + 1
  E.localState.loading = false
  E.localState.loadingStartedAt = 0
  E.localState.backend = E.localState.cacheAvailable and "cache-retry" or "retry"
  E.localState.lastError = tostring(reason or "DATASTORE_FAILED")
  E.localState.retryCount = E.localState.retryCount + 1
  E.localState.retryAt = E.now() + E.retryDelay(E.localState.retryCount)
  E.saveLocalCache()
  E.emitProfile()
end

function E.applyLocalProfile(profile, backend, initialCloudLoad)
  if profile == nil then return false end
  -- An unverified PlayerPrefs revision must not veto the first cloud truth.
  if not initialCloudLoad and E.profile ~= nil and E.integer(profile.revision, 0) < E.integer(E.profile.revision, 0) then return false end
  E.profile = profile
  E.localState.backend = tostring(backend or "cloud")
  E.localState.initialized = E.localState.backend == E.confirmedBackend()
  if E.localState.initialized then E.localState.cacheAvailable=true end
  E.localState.loading = false
  E.localState.loadingStartedAt = 0
  E.localState.retryCount, E.localState.retryAt, E.localState.lastError = 0, 0, "none"
  E.localState.lastSuccessAt, E.localState.nextRefreshAt = E.now(), E.now() + 30
  if E.reconcileCheckInOperations ~= nil then E.reconcileCheckInOperations() end
  if E.recordEquippedVisual ~= nil and E.isAuthority() and E.localState.initialized then
    E.recordEquippedVisual(E.localState.openId, profile)
  end
  if E.restoreCloudReceipts ~= nil and E.localState.initialized then E.restoreCloudReceipts(profile) end
  E.saveLocalCache()
  E.emitProfile()
  return true
end

function E.beginLocalLoad()
  local requestedOpenId = tostring(E.localState.openId or "")
  if E.destroyed or requestedOpenId == "" or E.localState.loading or E.localState.inFlightAwardId ~= "" then return false end
  if not E.networkSettled() then
    E.localState.retryAt = E.now() + 0.5
    return false
  end
  if E.playerOpenId(E.localPlayer()) ~= requestedOpenId then return false end
  if not E.storageAvailable() then
    if requestedOpenId ~= "" then E.failLocal("DATASTORE_UNAVAILABLE") end
    return false
  end
  E.localState.loadGeneration = E.localState.loadGeneration + 1
  local generation = E.localState.loadGeneration
  E.localState.loading = true
  E.localState.loadingStartedAt = E.now()
  local function current()
    return not E.destroyed and E.localState.loadGeneration == generation
      and E.localState.openId == requestedOpenId
      and E.playerOpenId(E.localPlayer()) == requestedOpenId
  end
  local function fail(reason)
    if current() then E.failLocal(reason) end
  end
  local started, startError = pcall(function()
    E.runStorage(function()
      -- DATASTORE resumes asynchronously: protect errors inside the coroutine too.
      local completed, err = pcall(function()
        if not current() then return end
        local storeCode, store = E.getStore(requestedOpenId)
        if not current() then return end
        E.localState.lastStoreCode = tonumber(storeCode) or 0
        if tonumber(storeCode) ~= 0 or store == nil then
          fail(tonumber(storeCode) == -10015 and "DATASTORE_NOT_OPEN" or "STORE_" .. tostring(storeCode))
          return
        end
        E.metrics.datastoreReads = E.metrics.datastoreReads + 1
        local readCode, value = store:GetData(E.cfg.profileKey)
        E.localState.lastReadCode = tonumber(readCode)
        if not current() then return end
        if tonumber(readCode) == -10001 then
          -- The SDK explicitly requires SetData after a missing-key response.
          -- Do not use cached balance or recreate the key on any other error.
          -- Never recreate a previously observed profile, including a genuine 0.
          if E.localState.cacheAvailable or E.localState.initialized then fail("EXISTING_PROFILE_MISSING"); return end
          -- Only this local-player loader may create. Recheck narrows (does not
          -- claim to eliminate) the API's missing-key/SetData race window.
          readCode, value = store:GetData(E.cfg.profileKey)
          E.localState.lastReadCode = tonumber(readCode)
          E.metrics.datastoreReads = E.metrics.datastoreReads + 1
          if not current() then return end
          if tonumber(readCode) == -10001 then
            local setCode, setValue = store:SetData(E.cfg.profileKey, E.encodeProfile(E.newCloudProfile()))
            E.metrics.datastoreWrites = E.metrics.datastoreWrites + 1
            if not current() then return end
            if tonumber(setCode) ~= 0 then fail("INIT_" .. tostring(setCode)); return end
            readCode, value = 0, setValue
          end
        end
        if tonumber(readCode) ~= 0 then fail("READ_" .. tostring(readCode)); return end
        local encoded = type(value) == "string" and value or tostring(value or "")
        if not E.validProfile(value) then
          fail("INVALID_CLOUD_PROFILE"); return
        end
        -- Persist the one-time novice/schema migration independently of check-in.
        if E.encodeProfile(E.decodeProfile(value)) ~= encoded then
          local migrationCode, migrated = store:UpdateData(E.cfg.profileKey,function(latest)
            if not E.validProfile(latest) then return latest end
            local profile=E.decodeProfile(latest)
            if E.encodeProfile(profile)==tostring(latest) then return latest end
            profile.revision=profile.revision+1
            return E.encodeProfile(profile)
          end)
          E.metrics.datastoreWrites=E.metrics.datastoreWrites+1
          if not current() then return end
          if tonumber(migrationCode)~=0 then fail("MIGRATION_"..tostring(migrationCode)); return end
          if not E.validProfile(migrated) then fail("INVALID_CLOUD_PROFILE"); return end
          value=migrated
        end
        E.localStore = store
        E.applyLocalProfile(E.decodeProfile(value), E.confirmedBackend(), not E.localState.initialized)
      end)
      if not completed then fail("LOAD_CALLBACK_FAILED") end
    end)
  end)
  if not started then fail("LOAD_START_FAILED") end
  return started
end

function E.tickLocalLoad()
  if E.localState.loading and E.now() - E.localState.loadingStartedAt >= E.cfg.loadTimeoutSeconds then
    E.localState.loadGeneration = E.localState.loadGeneration + 1
    E.failLocal("LOAD_TIMEOUT")
  end
end

function E.newId(prefix)
  E.localState.actionSequence = E.localState.actionSequence + 1
  local guid = ""
  pcall(function() guid = tostring(CS.System.Guid.NewGuid():ToString("N")) end)
  if guid == "" then
    guid = tostring(E.localState.actorId) .. "-" .. tostring(math.floor(E.now() * 1000))
      .. "-" .. tostring(E.localState.actionSequence)
  end
  return E.token(tostring(prefix or "TX") .. "-" .. guid, 96)
end

function E.sendToActor(functionName, actorId, ...)
  actorId = E.integer(actorId, 0)
  local arguments = { ... }
  local localId = E.actorId(E.localActor())
  if actorId > 0 and actorId == localId then
    if functionName == "GeocoreApplyActionResult" then
      return pcall(GeocoreApplyActionResult, arguments[1], arguments[2], arguments[3],
        arguments[4], arguments[5], arguments[6])
    elseif functionName == "GeocoreReceiveAward" then
      return pcall(GeocoreReceiveAward, arguments[1], arguments[2], arguments[3],
        arguments[4], arguments[5], arguments[6], arguments[7])
    elseif functionName == "GeocoreApplyAwardAckResult" then
      return pcall(GeocoreApplyAwardAckResult, arguments[1], arguments[2], arguments[3],
        arguments[4])
    elseif functionName == "GeocoreApplyCheckInResult" then
      return pcall(GeocoreApplyCheckInResult, arguments[1], arguments[2], arguments[3],
        arguments[4], arguments[5], arguments[6])
    end
  end
  local player = E.playerByActorId[actorId]
  if player == nil then return false end
  return pcall(function()
    self:SendMessageToTarget(functionName, player, arguments[1], arguments[2], arguments[3],
      arguments[4], arguments[5], arguments[6], arguments[7], arguments[8])
  end)
end

function E.validateIdentity(actorId, openId)
  actorId, openId = E.integer(actorId, 0), tostring(openId or "")
  E.refreshIdentities()
  return actorId > 0 and openId ~= "" and E.openIdByActorId[actorId] == openId
end

function E.authorityMutate(openId, mutation, completed)
  openId = tostring(openId or "")
  if openId == "" or not E.storageAvailable() then completed(false, "CLOUD_UNAVAILABLE", nil); return false end
  local started, startError = pcall(function()
    E.runStorage(function()
      local storeCode, store = E.getStore(openId)
      if tonumber(storeCode) ~= 0 or store == nil then completed(false, "STORE_FAILED", nil); return end
      local outcome = "SAVE_FAILED"
      local updateCode, value = store:UpdateData(E.cfg.profileKey, function(current)
        if not E.validProfile(current) then outcome = "INVALID_CLOUD_PROFILE"; return current end
        local profile = E.decodeProfile(current)
        local changed
        changed, outcome = mutation(profile)
        if changed == true then profile.revision = E.integer(profile.revision, 1) + 1 end
        return E.encodeProfile(profile)
      end)
      E.metrics.datastoreWrites = E.metrics.datastoreWrites + 1
      if tonumber(updateCode) == -10001 then completed(false, "PROFILE_NOT_READY", nil); return end
      if tonumber(updateCode) ~= 0 then completed(false, "SAVE_FAILED_" .. tostring(updateCode), nil); return end
      if not E.validProfile(value) then completed(false, "INVALID_CLOUD_PROFILE", nil); return end
      local confirmedProfile = E.decodeProfile(value)
      if E.recordEquippedVisual ~= nil and E.isAuthority() then E.recordEquippedVisual(openId, confirmedProfile) end
      completed(true, outcome, confirmedProfile)
    end)
  end)
  if not started then completed(false, "DATASTORE_START_FAILED_" .. tostring(startError), nil) end
  return started
end

function E.sendActionResult(actorId, openId, transactionId, ok, reason, profile)
  local encoded = profile ~= nil and E.encodeProfile(profile) or ""
  return E.sendToActor("GeocoreApplyActionResult", actorId, actorId, openId,
    transactionId, ok == true, tostring(reason or "UNKNOWN"), encoded)
end

function E.queueOperation(kind, a, b, cycleId)
  if E.isTestBackend() and not E.testBackendAllowed() then return nil, "TEST_DISABLED" end
  if E.localState.openId == "" or E.localState.actorId == 0 then return nil, "IDENTITY_PENDING" end
  local transactionId = E.newId(kind)
  E.localState.pendingOperations[transactionId] = {
    kind = kind, a = tostring(a or ""), b = tostring(b or ""), cycleId = E.integer(cycleId, 0),
    attempts = 0, nextAt = 0,
  }
  E.saveLocalCache()
  E.sendOperation(transactionId, E.localState.pendingOperations[transactionId])
  return transactionId, "QUEUED"
end

function E.sendOperation(transactionId, row)
  if E.isTestBackend() and not E.testBackendAllowed() then return false end
  if row == nil or E.localState.openId == "" or E.localState.actorId == 0 then return false end
  if not E.networkSettled() then row.nextAt = E.now() + E.retryDelay(row.attempts); return false end
  row.attempts = E.integer(row.attempts, 0) + 1
  row.nextAt = E.now() + math.min(8, 0.5 + row.attempts * 0.5)
  local function invoke()
    if row.kind == "BUY" then
      return GeocoreAuthorityBuy(E.localState.actorId, E.localState.openId, row.a, transactionId)
    elseif row.kind == "EQUIP" then
      return GeocoreAuthorityEquip(E.localState.actorId, E.localState.openId, row.a, row.b, transactionId)
    elseif row.kind == "SPONSOR" then
      return GeocoreAuthoritySponsor(E.localState.actorId, E.localState.openId,
        E.integer(row.a, 0), row.cycleId, transactionId)
    elseif row.kind == "CHECKIN_INIT" or row.kind == "CHECKIN_CLAIM" then
      return GeocoreAuthorityCheckIn(E.localState.actorId, E.localState.openId,
        row.kind == "CHECKIN_INIT" and 0 or E.integer(row.a, 0), transactionId)
    end
    return "ok=false|reason=UNKNOWN_OPERATION"
  end
  if E.isAuthority() then pcall(invoke); return true end
  local sent = false
  pcall(function()
    if row.kind == "BUY" then
      self:SendMessageToOwner("GeocoreAuthorityBuy", E.localState.actorId, E.localState.openId, row.a, transactionId)
    elseif row.kind == "EQUIP" then
      self:SendMessageToOwner("GeocoreAuthorityEquip", E.localState.actorId, E.localState.openId, row.a, row.b, transactionId)
    elseif row.kind == "SPONSOR" then
      self:SendMessageToOwner("GeocoreAuthoritySponsor", E.localState.actorId, E.localState.openId,
        E.integer(row.a, 0), row.cycleId, transactionId)
    elseif row.kind == "CHECKIN_INIT" or row.kind == "CHECKIN_CLAIM" then
      self:SendMessageToOwner("GeocoreAuthorityCheckIn", E.localState.actorId, E.localState.openId,
        row.kind == "CHECKIN_INIT" and 0 or E.integer(row.a, 0), transactionId)
    end
    sent = true
  end)
  return sent
end

function E.isTransientReason(reason)
  reason = tostring(reason or "")
  return string.find(reason, "CLOUD", 1, true) ~= nil
    or string.find(reason, "SAVE_FAILED", 1, true) ~= nil
    or string.find(reason, "DATASTORE", 1, true) ~= nil
    or reason == "SPONSOR_SYNCING" or reason == "PROFILE_NOT_READY" or reason == "STORE_FAILED"
end

function GeocoreApplyActionResult(targetActorId, openId, transactionId, ok, reason, encodedProfile)
  if E.integer(targetActorId, 0) ~= E.actorId(E.localActor())
    or tostring(openId or "") ~= E.localState.openId then return "ok=false|reason=WRONG_TARGET" end
  transactionId, reason = E.token(transactionId, 96), tostring(reason or "UNKNOWN")
  -- A network response is not cloud truth. In particular it must never inject
  -- check-in claimed bits, balances or an equipped title into a confirmed profile.
  if tostring(encodedProfile or "") ~= "" then
    E.checkIn.refreshRequested = true
    if not E.localState.loading and E.now() >= E.localState.retryAt and E.beginLocalLoad() then
      E.checkIn.refreshRequested = false
    end
  end
  local row = E.localState.pendingOperations[transactionId]
  if row ~= nil then
    if ok == true or not E.isTransientReason(reason) then E.localState.pendingOperations[transactionId] = nil
    else row.nextAt = E.now() + E.retryDelay(row.attempts) end
  end
  E.localState.lastAction = table.concat({ tostring(ok == true), reason, transactionId }, "|")
  E.saveLocalCache()
  return "ok=true"
end

function GeocoreEconomyBuy(itemId)
  itemId = E.token(itemId, 64)
  if E.cfg.catalog[itemId] == nil then return "ok=false|reason=ITEM_INVALID" end
  local transactionId, reason = E.queueOperation("BUY", itemId, "", 0)
  return "ok=" .. tostring(transactionId ~= nil) .. "|reason=" .. tostring(reason) .. "|transactionId=" .. tostring(transactionId or "")
end

function GeocoreEconomyEquip(category, itemId)
  category, itemId = E.token(category, 16), E.token(itemId, 64)
  if category ~= "title" and category ~= "wing" and category ~= "halo" then return "ok=false|reason=CATEGORY_INVALID" end
  local transactionId, reason = E.queueOperation("EQUIP", category, itemId, 0)
  return "ok=" .. tostring(transactionId ~= nil) .. "|reason=" .. tostring(reason) .. "|transactionId=" .. tostring(transactionId or "")
end

function GeocoreEconomySponsor(amount)
  amount = E.integer(amount, 0)
  local cycleId = E.integer(E.roomView.cycleId, 0)
  if cycleId <= 0 or not E.roomView.open then return "ok=false|reason=SPONSOR_CLOSED" end
  local transactionId, reason = E.queueOperation("SPONSOR", tostring(amount), "", cycleId)
  return "ok=" .. tostring(transactionId ~= nil) .. "|reason=" .. tostring(reason) .. "|transactionId=" .. tostring(transactionId or "")
end

function GeocoreAuthorityBuy(requestedActorId, openId, itemId, transactionId)
  if not E.isAccountAuthority(openId) then return "ok=false|reason=NOT_LOCAL_ACCOUNT" end
  requestedActorId, openId = E.integer(requestedActorId, 0), tostring(openId or "")
  itemId, transactionId = E.token(itemId, 64), E.token(transactionId, 96)
  local item = E.cfg.catalog[itemId]
  if not E.validateIdentity(requestedActorId, openId) or item == nil or item.shop == false
    or transactionId == "" then return "ok=false|reason=INVALID_REQUEST" end
  E.authorityMutate(openId, function(profile)
    local status = E.transactionStatus(profile, transactionId)
    if status ~= "" then return false, "DUPLICATE_" .. status end
    if profile.CosmeticInventoryV1[itemId] == true then
      E.appendTransaction(profile, transactionId, "ALREADYOWNED")
      return true, "ALREADY_OWNED"
    end
    if profile.Coins < item.price then
      E.appendTransaction(profile, transactionId, "INSUFFICIENT")
      return true, "COINS_NOT_ENOUGH"
    end
    profile.Coins = profile.Coins - item.price
    profile.CosmeticInventoryV1[itemId] = true
    E.appendTransaction(profile, transactionId, "PURCHASED" .. tostring(item.price))
    return true, "PURCHASED"
  end, function(saved, outcome, profile)
    if saved then E.metrics.transactionsConfirmed = E.metrics.transactionsConfirmed + 1 end
    local rejected = outcome == "COINS_NOT_ENOUGH"
      or string.find(outcome, "DUPLICATE_INSUFFICIENT", 1, true) ~= nil
    E.sendActionResult(requestedActorId, openId, transactionId, saved and not rejected, outcome, profile)
  end)
  return "ok=true|reason=QUEUED"
end

function GeocoreAuthorityEquip(requestedActorId, openId, category, itemId, transactionId)
  if not E.isAccountAuthority(openId) then return "ok=false|reason=NOT_LOCAL_ACCOUNT" end
  requestedActorId, openId = E.integer(requestedActorId, 0), tostring(openId or "")
  category, itemId, transactionId = E.token(category, 16), E.token(itemId, 64), E.token(transactionId, 96)
  if not E.validateIdentity(requestedActorId, openId) or transactionId == ""
    or (category ~= "title" and category ~= "wing" and category ~= "halo") then return "ok=false|reason=INVALID_REQUEST" end
  E.authorityMutate(openId, function(profile)
    local status = E.transactionStatus(profile, transactionId)
    if status ~= "" then return false, "DUPLICATE_" .. status end
    if itemId ~= "" and profile.CosmeticInventoryV1[itemId] ~= true then
      E.appendTransaction(profile, transactionId, "NOTOWNED")
      return true, "NOT_OWNED"
    end
    if itemId ~= "" and E.cfg.catalog[itemId] ~= nil and E.cfg.catalog[itemId].category ~= category then
      E.appendTransaction(profile, transactionId, "MISMATCH")
      return true, "CATEGORY_MISMATCH"
    end
    profile.EquippedCosmeticsV1[category] = itemId ~= "" and itemId or nil
    E.appendTransaction(profile, transactionId, "EQUIPPED" .. itemId)
    return true, itemId ~= "" and "EQUIPPED" or "UNEQUIPPED"
  end, function(saved, outcome, profile)
    local rejected = outcome == "NOT_OWNED" or outcome == "CATEGORY_MISMATCH"
      or string.find(outcome, "DUPLICATE_NOTOWNED", 1, true) ~= nil
      or string.find(outcome, "DUPLICATE_MISMATCH", 1, true) ~= nil
    E.sendActionResult(requestedActorId, openId, transactionId,
      saved and not rejected, outcome, profile)
  end)
  return "ok=true|reason=QUEUED"
end

function E.cycleKey(cycleId)
  if E.room.cycleId == E.integer(cycleId, 0) and E.room.roundKey ~= "" then return E.room.roundKey end
  return tostring(E.integer(cycleId, 0))
end

function GeocoreAuthoritySponsor(requestedActorId, openId, amount, cycleId, transactionId)
  if not E.isAuthority() then return "ok=false|reason=NOT_AUTHORITY" end
  requestedActorId, openId = E.integer(requestedActorId, 0), tostring(openId or "")
  amount, cycleId, transactionId = E.integer(amount, 0), E.integer(cycleId, 0), E.token(transactionId, 96)
  if not E.validateIdentity(requestedActorId, openId) or transactionId == "" then return "ok=false|reason=INVALID_REQUEST" end
  local participant = E.room.participantByOpenId[openId]
  if not E.room.locked or E.room.reconstructing then
    E.sendActionResult(requestedActorId, openId, transactionId, false, "SPONSOR_SYNCING", nil)
    return "ok=false|reason=SPONSOR_SYNCING"
  end
  if E.room.cycleId ~= cycleId or E.room.phase ~= "WAITING" or not E.room.open or E.room.frozen then
    E.sendActionResult(requestedActorId, openId, transactionId, false, "SPONSOR_CLOSED", nil)
    return "ok=false|reason=SPONSOR_CLOSED"
  end
  if E.sponsorRoomStatus() ~= "READY" then
    E.sendActionResult(requestedActorId, openId, transactionId, false, "SPONSOR_CLOSED", nil)
    return "ok=false|reason=SPONSOR_CLOSED"
  end
  if participant == nil then
    E.sendActionResult(requestedActorId, openId, transactionId, false, "NOT_RACE_PARTICIPANT", nil)
    return "ok=false|reason=NOT_RACE_PARTICIPANT"
  end
  if amount < E.cfg.sponsorMinAmount or amount > E.cfg.sponsorMaxAmount then
    E.sendActionResult(requestedActorId, openId, transactionId, false, "AMOUNT_OUT_OF_RANGE", nil)
    return "ok=false|reason=AMOUNT_OUT_OF_RANGE"
  end
  local confirmedTotal = 0
  local requestedRoom, requestedRoundKey = E.room, E.room.roundKey
  E.authorityMutate(openId, function(profile)
    -- UpdateData may retry/yield after the request window or owner/roster has changed.
    if not E.isAuthority() or E.room ~= requestedRoom or E.room.participantByOpenId[openId] ~= participant
      or E.sponsorRoomStatus() ~= "READY" then return false, "SPONSOR_CLOSED" end
    local status = E.transactionStatus(profile, transactionId)
    local current = E.integer(profile.SponsorTotalsV1[requestedRoundKey], 0, E.cfg.sponsorMaxAmount)
    if status ~= "" then confirmedTotal = current; return false, "DUPLICATE_" .. status end
    if current + amount > E.cfg.sponsorMaxAmount then
      E.appendTransaction(profile, transactionId, "LIMIT")
      confirmedTotal = current
      return true, "SPONSOR_LIMIT"
    end
    if profile.Coins < amount then
      E.appendTransaction(profile, transactionId, "INSUFFICIENT")
      confirmedTotal = current
      return true, "COINS_NOT_ENOUGH"
    end
    profile.Coins = profile.Coins - amount
    confirmedTotal = current + amount
    profile.SponsorTotalsV1[requestedRoundKey] = confirmedTotal
    E.appendTransaction(profile, transactionId, "SPONSOR" .. tostring(amount))
    return true, "SPONSOR_CONFIRMED"
  end, function(saved, outcome, profile)
    if saved and profile ~= nil then
      confirmedTotal = E.integer(profile.SponsorTotalsV1[requestedRoundKey], 0, E.cfg.sponsorMaxAmount)
    end
    local accepted = saved and (outcome == "SPONSOR_CONFIRMED" or string.find(outcome, "DUPLICATE_SPONSOR", 1, true) ~= nil)
    if accepted and E.isAuthority() and E.room == requestedRoom and E.room.participantByOpenId[openId] == participant then
      local previous = E.integer(E.room.sponsorshipByOpenId[openId], 0)
      if confirmedTotal ~= previous then
        E.room.sponsorshipByOpenId[openId] = confirmedTotal
        E.room.revision = E.room.revision + 1
        E.metrics.sponsorRevisions = E.metrics.sponsorRevisions + 1
        E.recomputePool()
        E.broadcastRoom(true)
      end
    end
    E.sendActionResult(requestedActorId, openId, transactionId, accepted, outcome, profile)
  end)
  return "ok=true|reason=QUEUED"
end

function E.recomputePool()
  local playerSponsor = 0
  for openId, _ in pairs(E.room.participantByOpenId) do
    playerSponsor = playerSponsor + E.integer(E.room.sponsorshipByOpenId[openId], 0, E.cfg.sponsorMaxAmount)
  end
  local enabled = E.cfg.sponsorEnabled and #E.room.participants >= E.cfg.sponsorMinParticipants
  E.room.playerSponsor = enabled and playerSponsor or 0
  E.room.systemSponsor = enabled and E.cfg.systemSponsorPerParticipant * #E.room.participants or 0
  E.room.pool = enabled and E.room.playerSponsor + E.room.systemSponsor or 0
end

function E.encodeRoom()
  local status, lastError, pending, retrySeconds = E.sponsorRoomStatus()
  local sponsorshipRows = {}
  for _, row in ipairs(E.room.participants) do
    sponsorshipRows[#sponsorshipRows + 1] = E.token(row.openId, 120) .. "="
      .. tostring(E.integer(E.room.sponsorshipByOpenId[row.openId], 0))
  end
  table.sort(sponsorshipRows)
  return table.concat({ "S2", tostring(E.room.cycleId), E.token(E.room.phase, 16),
    tostring(E.room.open), tostring(E.room.frozen), tostring(#E.room.participants),
    tostring(E.room.playerSponsor), tostring(E.room.systemSponsor), tostring(E.room.pool),
    tostring(E.room.revision), tostring(E.cfg.sponsorMinAmount), tostring(E.cfg.sponsorMaxAmount),
    table.concat(sponsorshipRows, ","), E.escapeRoomField(E.room.settlementSnapshot),
    status, lastError, tostring(pending), tostring(retrySeconds),
    tostring(E.cfg.sponsorEnabled), tostring(E.cfg.sponsorMinParticipants), tostring(E.room.locked) }, "|")
end

function GeocoreApplyRoomSponsorSnapshot(payload)
  local fields = E.split(payload, "|")
  if fields[1] ~= "S2" then return false end
  local cycleId, revision = E.integer(fields[2], 0), E.integer(fields[10], 0)
  if cycleId < E.roomView.cycleId or (cycleId == E.roomView.cycleId and revision < E.roomView.revision) then return false end
  E.roomView = {
    cycleId = cycleId, phase = tostring(fields[3] or ""), open = fields[4] == "true",
    frozen = fields[5] == "true", participantCount = E.integer(fields[6], 0),
    playerSponsor = E.integer(fields[7], 0), systemSponsor = E.integer(fields[8], 0),
    pool = E.integer(fields[9], 0), revision = revision, sponsorBySafeOpenId = {},
    settlementSnapshot = E.unescapeRoomField(fields[14] or ""),
    sponsorStatus = fields[15] or (fields[4] == "true" and "READY" or "SYNCING"),
    sponsorError = E.token(fields[16] or "none", 80), reconstructPending = E.integer(fields[17], 0),
    sponsorRetrySeconds = E.integer(fields[18], 0), sponsorConfigured = fields[19] ~= "false",
    sponsorMinimumParticipants = E.integer(fields[20] or E.cfg.sponsorMinParticipants, 1, 30),
    sponsorMinAmount = E.integer(fields[11] or E.cfg.sponsorMinAmount, 1),
    sponsorMaxAmount = E.integer(fields[12] or E.cfg.sponsorMaxAmount, 1),
    locked = fields[21] == "true" or (fields[21] == nil and fields[4] == "true"),
    receivedAt = E.now(),
  }
  for _, raw in ipairs(E.split(fields[13], ",")) do
    local pair = E.split(raw, "=")
    local safeOpenId = E.token(pair[1], 120)
    if safeOpenId ~= "" then E.roomView.sponsorBySafeOpenId[safeOpenId] = E.integer(pair[2], 0) end
  end
  return true
end

function E.broadcastRoom(force)
  if not E.isAuthority() then return false end
  E.publishSponsorLedger()
  local tickNow = E.now()
  if not force and tickNow < E.room.nextBroadcastAt then return false end
  E.room.nextBroadcastAt = tickNow + 1
  local payload = E.encodeRoom()
  GeocoreApplyRoomSponsorSnapshot(payload)
  if E.networkSettled() then pcall(function() self:SendMessageToAll("GeocoreApplyRoomSponsorSnapshot", payload) end) end
  return true
end

function E.buildRaceSettlementSnapshot(settlement)
  if settlement == nil then return "" end
  local rows = { table.concat({ "GCRS1", tostring(settlement.cycleId or E.room.cycleId),
    tostring(settlement.revision or E.room.revision), settlement.state or "calculated" }, "|") }
  for _, row in ipairs(settlement.rows or {}) do
    local fixed, sponsor = E.integer(row.fixedAward, 0), E.integer(row.sponsorAward, 0)
    rows[#rows + 1] = table.concat({ E.integer(row.actorId, 0), E.integer(row.rank, 0),
      E.integer(row.finishMs, -1), fixed, sponsor, fixed + sponsor }, "|")
  end
  return table.concat(rows, "\n")
end
function E.escapeRoomField(value)
  return (tostring(value or ""):gsub("%%", "%%25"):gsub("|", "%%7C"):gsub("\n", "%%0A"))
end
function E.unescapeRoomField(value)
  return (tostring(value or ""):gsub("%%0A", "\n"):gsub("%%7C", "|"):gsub("%%25", "%%"))
end

function E.parseActorIds(value)
  local result = {}
  for _, raw in ipairs(E.split(value, ",")) do
    local actorId = E.integer(raw, 0)
    if actorId > 0 then result[#result + 1] = actorId end
  end
  return result
end

function E.finishSponsorReconstruction()
  if E.room.reconstructPending > 0 then return end
  E.room.reconstructing = false
  E.room.lastReconstructError = "none"
  E.recomputePool()
  E.room.open = E.sponsorRoomStatus() == "READY"
  E.room.frozen = E.room.phase ~= "WAITING"
  E.room.revision = E.room.revision + 1
  E.broadcastRoom(true)
end

-- Every yield may outlive a timeout, ownership change, or a same-cycle roster rebuild.
function E.sponsorReadCurrent(row, room, generation)
  return E.isAuthority() and room == E.room and room.locked and room.reconstructing
    and row ~= nil and room.participantByOpenId[row.openId] == row and not row.sponsorRead
    and (generation == nil or (row.sponsorReadInFlight == true and row.sponsorReadGeneration == generation))
end

function E.sponsorWindowStatus(cycleId)
  local script = E.managerHolder ~= nil and E.managerHolder.script or nil
  if script == nil then return "CLOCK_SYNCING" end
  local ok, phase, currentCycle, remaining = pcall(function()
    return tostring(script.GetRaceManagerState() or ""), E.integer(script.GetRaceManagerCycleId(), 0),
      tonumber(script.GetRaceManagerRemainingMilliseconds())
  end)
  if not ok or remaining == nil or remaining < 0 or remaining ~= remaining or remaining == math.huge then return "CLOCK_SYNCING" end
  if currentCycle <= 0 or currentCycle ~= cycleId then return "CYCLE_SYNCING" end
  if phase ~= "WAITING" or remaining <= 2000 then return "CLOSED" end
  return "READY"
end

-- Display-only diagnostics. Never include identities, store scopes, or exception text.
function E.sponsorRoomStatus()
  local room = E.room
  local pending, retrySeconds, lastError = E.integer(room.reconstructPending, 0), 0, "none"
  if not E.cfg.sponsorEnabled then return "DISABLED", "none", pending, 0 end
  if room.cycleId <= 0 then return "CYCLE_SYNCING", "none", pending, 0 end
  if room.phase == "" then return "CLOCK_SYNCING", "none", pending, 0 end
  if room.phase ~= "WAITING" or room.frozen then return "CLOSED", "none", pending, 0 end
  if not room.locked then return room.lockReason or "ROSTER_SYNCING", "none", pending, 0 end
  if #room.participants < E.cfg.sponsorMinParticipants then return "TOO_FEW", "none", pending, 0 end
  local window = E.sponsorWindowStatus(room.cycleId)
  if window ~= "READY" then return window, "none", pending, 0 end
  for _, row in ipairs(room.participants) do
    if not row.sponsorRead and row.sponsorReadError ~= nil then
      lastError = row.sponsorReadError
      retrySeconds = math.max(retrySeconds, math.ceil(math.max(0, (row.nextSponsorReadAt or 0) - E.now())))
    end
  end
  if room.reconstructing then return lastError ~= "none" and "RETRYING" or "SYNCING", lastError, pending, retrySeconds end
  return "READY", "none", 0, 0
end

function E.deferParticipantSponsorRead(row, reason, room, generation)
  room = room or E.room
  if not E.sponsorReadCurrent(row, room, generation) then return end
  row.sponsorReadInFlight = false
  row.sponsorReadGeneration = E.integer(row.sponsorReadGeneration, 0) + 1
  row.sponsorReadError = reason
  row.sponsorReadAttempts = E.integer(row.sponsorReadAttempts, 0) + 1
  row.nextSponsorReadAt = E.now() + E.retryDelay(row.sponsorReadAttempts)
  E.metrics.datastoreFailures = E.metrics.datastoreFailures + 1
  E.room.open = false
  E.room.lastReconstructError = E.token(reason, 80)
  E.room.revision = E.room.revision + 1
  E.broadcastRoom(true)
end

function E.readParticipantSponsor(row)
  if not E.sponsorReadCurrent(row, E.room) or row.sponsorReadInFlight == true then return false end
  if E.now() < (tonumber(row.nextSponsorReadAt) or 0) then return false end
  if not E.networkSettled() then E.deferParticipantSponsorRead(row, "NETWORK_PENDING"); return false end
  if not E.storageAvailable() then
    E.deferParticipantSponsorRead(row, "SPONSOR_DATASTORE_UNAVAILABLE")
    return false
  end
  local room, roundKey, openId = E.room, E.room.roundKey, row.openId
  row.sponsorReadGeneration = E.integer(row.sponsorReadGeneration, 0) + 1
  local generation = row.sponsorReadGeneration
  row.sponsorReadInFlight = true
  row.sponsorReadStartedAt = E.now()
  local started, startError = pcall(function()
    E.runStorage(function()
      if not E.sponsorReadCurrent(row, room, generation) then return end
      if not E.networkSettled() then E.deferParticipantSponsorRead(row, "NETWORK_PENDING", room, generation); return end
      local callOk, code, store = pcall(function()
        local resultCode, resultStore = E.getStore(openId)
        return resultCode, resultStore
      end)
      if not E.sponsorReadCurrent(row, room, generation) then return end
      if not callOk or tonumber(code) ~= 0 or store == nil then
        E.deferParticipantSponsorRead(row, "SPONSOR_STORE_" .. tostring(tonumber(code) or "FAILED"), room, generation)
        return
      end
      if not E.networkSettled() then E.deferParticipantSponsorRead(row, "NETWORK_PENDING", room, generation); return end
      local readOk, readCode, value = pcall(function()
        local resultCode, resultValue = store:GetData(E.cfg.profileKey)
        return resultCode, resultValue
      end)
      if not E.sponsorReadCurrent(row, room, generation) then return end
      E.metrics.datastoreReads = E.metrics.datastoreReads + 1
      if not readOk or (tonumber(readCode) ~= 0 and tonumber(readCode) ~= -10001) then
        E.deferParticipantSponsorRead(row, "SPONSOR_READ_" .. tostring(tonumber(readCode) or "FAILED"), room, generation)
        return
      end
      local amount = 0
      if tonumber(readCode) == 0 then
        amount = E.integer(E.decodeProfile(value).SponsorTotalsV1[roundKey], 0, E.cfg.sponsorMaxAmount)
      end
      row.sponsorRead, row.sponsorReadInFlight = true, false
      row.sponsorReadError = nil
      E.room.sponsorshipByOpenId[openId] = amount
      E.room.reconstructPending = math.max(0, E.room.reconstructPending - 1)
      E.finishSponsorReconstruction()
    end)
  end)
  if not started then
    E.deferParticipantSponsorRead(row, "SPONSOR_READ_START_FAILED", room, generation)
  end
  return started
end

function E.tickSponsorReconstruction()
  if not E.isAuthority() or not E.room.reconstructing then return end
  local started = 0
  for _, row in ipairs(E.room.participants or {}) do
    if row.sponsorReadInFlight and E.now() - (row.sponsorReadStartedAt or E.now()) >= E.cfg.sponsorReadTimeoutSeconds then
      E.deferParticipantSponsorRead(row, "SPONSOR_READ_TIMEOUT", E.room, row.sponsorReadGeneration)
    end
    if row.sponsorRead ~= true and row.sponsorReadInFlight ~= true
      and E.now() >= (tonumber(row.nextSponsorReadAt) or 0) then
      if E.readParticipantSponsor(row) then started = started + 1 end
      if started >= 4 then break end
    end
  end
end

function E.lockRoom(cycleId, phase)
  if not E.isAuthority() then return false end
  if E.restoreSponsorLedger(cycleId,phase) then E.broadcastRoom(true);return true end
  E.room.lockReason = "ROSTER_SYNCING"
  if E.sessionHolder == nil or E.sessionHolder.script == nil then return false end
  local rosterCycle = 0
  if E.sessionHolder.script.GetRaceSessionStatus ~= nil then
    pcall(function() rosterCycle = E.integer(E.sessionHolder.script.GetRaceSessionStatus(), 0) end)
  end
  if rosterCycle ~= cycleId then return false end
  local participants, byOpenId, vehicles = {}, {}, {}
  local unresolvedIdentity = false
  for _, vehicleName in ipairs(E.vehicleNames) do
    local actorList = ""
    pcall(function() actorList = tostring(E.sessionHolder.script.GetRaceVehicleRosterActorIds(vehicleName) or "") end)
    local vehicle = { name = vehicleName, actorIds = {}, openIds = {} }
    for _, actorId in ipairs(E.parseActorIds(actorList)) do
      local openId = E.openIdByActorId[actorId] or ""
      if openId == "" then unresolvedIdentity = true end
      if openId ~= "" and byOpenId[openId] == nil then
        local row = { actorId = actorId, openId = openId, vehicleName = vehicleName,
          sponsorRead = false, sponsorReadInFlight = false, sponsorReadAttempts = 0,
          nextSponsorReadAt = 0 }
        participants[#participants + 1], byOpenId[openId] = row, row
        vehicle.actorIds[#vehicle.actorIds + 1], vehicle.openIds[#vehicle.openIds + 1] = actorId, openId
      end
    end
    if #vehicle.openIds > 0 then vehicles[#vehicles + 1] = vehicle end
  end
  if unresolvedIdentity then E.room.lockReason = "IDENTITY_SYNCING"; return false end
  table.sort(participants, function(left, right) return left.openId < right.openId end)
  local signatureRows = {}
  for _, row in ipairs(participants) do
    signatureRows[#signatureRows + 1] = E.token(row.openId, 120) .. "@" .. tostring(row.actorId)
      .. "@" .. E.stableHash(row.vehicleName)
  end
  table.sort(signatureRows)
  local roundKey = tostring(cycleId) .. "-" .. E.stableHash(table.concat(signatureRows, "|"))
  local nextRevision = math.max(E.integer(E.room.revision, 0),
    E.roomView.cycleId == cycleId and E.integer(E.roomView.revision, 0) or 0) + 1
  E.room = {
    cycleId = cycleId, roundKey = roundKey, phase = phase, locked = true, reconstructing = true,
    reconstructPending = #participants, participants = participants, participantByOpenId = byOpenId,
    vehicles = vehicles, sponsorshipByOpenId = {}, playerSponsor = 0, systemSponsor = 0,
    pool = 0, open = false, frozen = phase ~= "WAITING", revision = nextRevision,
    settled = false, settlement = nil, nextBroadcastAt = 0,
  }
  -- System sponsorship is determined by the frozen roster, not client replies.
  E.recomputePool()
  E.broadcastRoom(true)
  -- RETURN-REPAIR-0905: a disabled sponsor round has no sponsor ledger to load.
  -- Previously even N=1 waited forever on N cloud reads before fixed rewards.
  if not E.cfg.sponsorEnabled or #participants < E.cfg.sponsorMinParticipants then
    E.room.reconstructPending = 0
    for _,row in ipairs(participants) do row.sponsorRead=true;E.room.sponsorshipByOpenId[row.openId]=0 end
    E.finishSponsorReconstruction()
  elseif #participants == 0 then E.finishSponsorReconstruction() else E.tickSponsorReconstruction() end
  return true
end

function E.freezeRoom()
  if not E.room.locked then return end
  -- At race start freeze only totals already acknowledged by the room. A
  -- disconnected client must not hold every player's settlement indefinitely.
  if E.room.reconstructing then
    for _, row in ipairs(E.room.participants) do
      row.sponsorRead, row.sponsorReadInFlight = true, false
      E.room.sponsorshipByOpenId[row.openId] = E.room.sponsorshipByOpenId[row.openId] or 0
    end
    E.room.reconstructPending, E.room.reconstructing = 0, false
    E.room.sponsorCutoff = true
  end
  E.recomputePool()
  if E.room.frozen then return end
  E.room.open, E.room.frozen = false, true
  E.recomputePool()
  E.room.revision = E.room.revision + 1
  E.broadcastRoom(true)
end

function E.largestRemainder(total, rows, scoreOf)
  local awards, fractions, used, sumScore = {}, {}, 0, 0
  for _, row in ipairs(rows) do sumScore = sumScore + math.max(0, tonumber(scoreOf(row)) or 0) end
  if total <= 0 or #rows == 0 or sumScore <= 0 then return awards end
  for _, row in ipairs(rows) do
    local exact = total * math.max(0, tonumber(scoreOf(row)) or 0) / sumScore
    local amount = math.floor(exact)
    awards[row.openId], used = amount, used + amount
    fractions[#fractions + 1] = { openId = row.openId, fraction = exact - amount }
  end
  table.sort(fractions, function(left, right)
    if left.fraction == right.fraction then return left.openId < right.openId end
    return left.fraction > right.fraction
  end)
  for index = 1, total - used do
    local openId = fractions[((index - 1) % #fractions) + 1].openId
    awards[openId] = (awards[openId] or 0) + 1
  end
  return awards
end

function E.rankFinalParticipants()
  if E.room.finalRows ~= nil then return E.room.finalRows end
  local api=E.managerHolder and E.managerHolder.script
  if api and api.GetRaceManagerFinalResultsSnapshot then
    local ok,payload=pcall(api.GetRaceManagerFinalResultsSnapshot)
    if not ok then return nil end
    local cycle,revision,count=tostring(payload or ""):match("^GFP1|(%d+)|(%d+)|final|(%d+)")
    if tonumber(cycle)~=E.room.cycleId then return nil end
    local rows,byActor={},{}
    for _,p in ipairs(E.room.participants) do byActor[p.actorId]=p end
    for line in payload:gmatch("\n([^\n]+)") do
      local id,rank,ms,name=line:match("^(%d+)|(%d+)|(-?%d+)|([^|]+)$")
      id,rank,ms=tonumber(id),tonumber(rank),tonumber(ms)
      local p=byActor[id]
      if not p or p.vehicleName~=name or not ms or (rank==0)~=(ms<0) then return nil end
      rows[#rows+1]={actorId=id,openId=p.openId,vehicleName=name,finished=ms>=0,
        finishMs=ms,rank=rank,sponsorship=E.integer(E.room.sponsorshipByOpenId[p.openId],0)}
      byActor[id]=nil
    end
    if #rows~=tonumber(count) or #rows~=#E.room.participants then return nil end
    E.room.finalRows=rows
    return rows
  end
  local finishedVehicles = {}
  for _, vehicle in ipairs(E.room.vehicles) do
    local finishMs = -1
    if E.managerHolder ~= nil and E.managerHolder.script ~= nil
      and E.managerHolder.script.GetRaceManagerVehicleFinishMilliseconds ~= nil then
      pcall(function() finishMs = E.integer(E.managerHolder.script.GetRaceManagerVehicleFinishMilliseconds(vehicle.name), -1) end)
    end
    vehicle.finishMs = finishMs
    if finishMs >= 0 then finishedVehicles[#finishedVehicles + 1] = vehicle end
  end
  table.sort(finishedVehicles, function(left, right)
    if left.finishMs == right.finishMs then return left.name < right.name end
    return left.finishMs < right.finishMs
  end)
  local previousMs, currentRank, precedingPlayers = nil, 0, 0
  for index, vehicle in ipairs(finishedVehicles) do
    if previousMs == nil or vehicle.finishMs ~= previousMs then currentRank = precedingPlayers+1 end
    vehicle.rank, previousMs = currentRank, vehicle.finishMs
    precedingPlayers=precedingPlayers+#vehicle.actorIds
  end
  local byVehicle = {}
  for _, vehicle in ipairs(E.room.vehicles) do byVehicle[vehicle.name] = vehicle end
  local rows = {}
  for _, participant in ipairs(E.room.participants) do
    local vehicle = byVehicle[participant.vehicleName]
    rows[#rows + 1] = {
      actorId = participant.actorId, openId = participant.openId, vehicleName = participant.vehicleName,
      finished = vehicle ~= nil and vehicle.finishMs ~= nil and vehicle.finishMs >= 0,
      finishMs = vehicle ~= nil and vehicle.finishMs or -1,
      rank = vehicle ~= nil and vehicle.rank or nil,
      sponsorship = E.integer(E.room.sponsorshipByOpenId[participant.openId], 0),
    }
  end
  return rows
end

function E.settleSponsor(rows)
  local result = { awards = {}, eligible = {}, totalAwarded = 0, systemRecovered = 0 }
  if E.room.pool <= 0 then return result end
  local firstRank = nil
  local groupSize = {}
  for _, row in ipairs(rows) do
    if row.finished and row.rank ~= nil then
      if firstRank == nil or row.rank < firstRank then firstRank = row.rank end
      groupSize[row.rank] = (groupSize[row.rank] or 0) + 1
    end
  end
  if firstRank == nil then result.systemRecovered = E.room.pool; return result end
  local half = #E.room.participants / 2
  local eligible = {}
  for _, row in ipairs(rows) do
    local qualifies = row.finished and row.rank ~= nil and (row.rank == firstRank
      or (row.rank < half and row.rank + (groupSize[row.rank] or 1) - 1 < half))
    if qualifies then eligible[#eligible + 1], result.eligible[row.openId] = row, true end
  end
  table.sort(eligible, function(left, right) return left.openId < right.openId end)
  local principal = 0
  for _, row in ipairs(eligible) do
    result.awards[row.openId] = row.sponsorship
    principal = principal + row.sponsorship
  end
  local remaining = math.max(0, E.room.pool - principal)
  if #eligible > 0 and remaining > 0 then
    local rankDenominator, sponsorDenominator = 0, principal
    for _, row in ipairs(eligible) do rankDenominator = rankDenominator + 1 / math.max(1, row.rank) end
    local function score(row)
      return E.cfg.sponsorRankWeight * ((1 / math.max(1, row.rank)) / rankDenominator)
        + E.cfg.sponsorPersonalWeight * (sponsorDenominator > 0 and row.sponsorship / sponsorDenominator or 0)
    end
    local hasScore = false
    for _, row in ipairs(eligible) do if score(row) > 0 then hasScore = true end end
    local profit = E.largestRemainder(remaining, eligible,
      hasScore and score or function(row) return (1 / math.max(1, row.rank)) / rankDenominator end)
    for openId, amount in pairs(profit) do result.awards[openId] = (result.awards[openId] or 0) + amount end
  end
  for _, amount in pairs(result.awards) do result.totalAwarded = result.totalAwarded + amount end
  result.systemRecovered = E.room.pool - result.totalAwarded
  return result
end

function E.queueAward(openId, actorId, awardId, amount, reason, cycleId)
  awardId, amount = E.token(awardId, 160), E.integer(amount, 0, 1000000)
  if openId == "" or awardId == "" or amount <= 0 or E.outbox[awardId] ~= nil then return false end
  E.outbox[awardId] = { openId = openId, actorId = E.integer(actorId, 0), amount = amount,
    reason = E.token(reason, 32), cycleId = E.integer(cycleId, 0),
    deliveryToken = E.newId("AWARD_DELIVERY"), cloudConfirmed = false,
    cloudInFlight = false, attempts = 0, nextAt = 0 }
  E.metrics.awardsQueued = E.metrics.awardsQueued + 1
  return true
end

function E.tableCount(source)
  local count = 0
  for _ in pairs(source or {}) do count = count + 1 end
  return count
end

function E.settleRound()
  if not E.isAuthority() or not E.room.locked or E.room.settled then return false end
  E.freezeRoom()
  local rows, participantCount = E.rankFinalParticipants(), #E.room.participants
  if rows == nil then return false end
  local sponsorPending=E.room.reconstructing==true
  if sponsorPending and E.room.fixedPublished then return false end
  for _,row in ipairs(rows) do row.sponsorship=E.integer(E.room.sponsorshipByOpenId[row.openId],0) end
  local sponsor = sponsorPending and {awards={},systemRecovered=0,totalAwarded=0} or E.settleSponsor(rows)
  local finishSignature = {}
  for _, row in ipairs(rows) do finishSignature[#finishSignature + 1] = E.token(row.openId, 120)
    .. "@" .. tostring(row.finishMs) .. "@" .. tostring(row.rank or 0) end
  table.sort(finishSignature)
  local snapshotId = E.stableHash(E.room.roundKey .. "|" .. table.concat(finishSignature, "|"))
  for _, row in ipairs(rows) do
    row.fixedAward = 0
    row.sponsorAward = E.integer(sponsor.awards[row.openId], 0)
    if row.finished then
      local fixed = participantCount >= 4 and row.rank == 1 and E.cfg.firstPlaceReward or E.cfg.normalFinishReward
      row.fixedAward = fixed
      local fixedId = table.concat({ "GCV12", E.room.cycleId, snapshotId, "FIXED",
        E.stableHash(row.openId), fixed }, "-")
      if not E.room.fixedPublished then E.queueAward(row.openId, row.actorId, fixedId, fixed, "FIXED_RACE_REWARD", E.room.cycleId) end
    end
    local sponsorAmount = row.sponsorAward
    if sponsorAmount > 0 then
      local sponsorId = table.concat({ "GCV12", E.room.cycleId, snapshotId, "SPONSOR",
        E.stableHash(row.openId), sponsorAmount }, "-")
      E.queueAward(row.openId, row.actorId, sponsorId, sponsorAmount, "SPONSOR_SETTLEMENT", E.room.cycleId)
    end
  end
  E.room.revision = E.room.revision + 1
  E.room.fixedPublished = true
  E.room.settled = not sponsorPending
  E.room.settlement = { cycleId = E.room.cycleId, revision = E.room.revision, state = sponsorPending and "fixed" or "calculated",
    rows = rows, sponsor = sponsor, participantCount = participantCount,
    pool = E.room.pool, outboxCount = E.tableCount(E.outbox) }
  E.room.settlementSnapshot = E.buildRaceSettlementSnapshot(E.room.settlement)
  E.lastSettlementSnapshot = E.room.settlementSnapshot
  E.broadcastRoom(true)
  return true
end

function E.awardLedgerLine(awardId,row)
  return table.concat({E.token(awardId,160),E.integer(row.actorId,0),E.token(row.openId,120),
    E.integer(row.amount,0),E.token(row.reason,32),E.integer(row.cycleId,0),E.token(row.deliveryToken,96)},"|")
end

function E.publishAwardLedger()
  local economyAwardLedger = E.backendLedger("award", economyAwardLedger)
  if not E.isAuthority() or economyAwardLedger==nil then return false end
  local lines={}
  for id,row in pairs(E.outbox) do lines[#lines+1]=E.awardLedgerLine(id,row) end
  table.sort(lines)
  local payload="GA1\n"..table.concat(lines,"\n")
  local read,old=pcall(function()return economyAwardLedger:GetValue()end)
  if read and tostring(old)==payload then return true end
  local wrote=pcall(function()economyAwardLedger:SetValue(payload)end)
  local confirmed,value=pcall(function()return economyAwardLedger:GetValue()end)
  return wrote and confirmed and tostring(value)==payload
end

function E.isAuthorizedAward(id,actorId,openId,amount,reason,cycle,token)
  local economyAwardLedger = E.backendLedger("award", economyAwardLedger)
  if economyAwardLedger==nil then return false end
  local ok,value=pcall(function()return tostring(economyAwardLedger:GetValue() or "")end)
  if not ok or value:sub(1,4)~="GA1\n" then return false end
  local expected=E.awardLedgerLine(id,{actorId=actorId,openId=openId,amount=amount,reason=reason,cycleId=cycle,deliveryToken=token})
  for line in value:gmatch("\n([^\n]+)") do if line==expected then return true end end
  return false
end

function E.hydrateAwardLedger()
  local economyAwardLedger = E.backendLedger("award", economyAwardLedger)
  if not E.isAuthority() or economyAwardLedger==nil then return end
  local ok,value=pcall(function()return tostring(economyAwardLedger:GetValue() or "")end)
  if not ok or value:sub(1,4)~="GA1\n" then return end
  for line in value:gmatch("\n([^\n]+)") do
    local f=E.split(line,"|")
    if #f==7 and f[1]~="" and E.outbox[f[1]]==nil then
      E.outbox[f[1]]={actorId=E.integer(f[2],0),openId=f[3],amount=E.integer(f[4],0),
        reason=f[5],cycleId=E.integer(f[6],0),deliveryToken=f[7],attempts=0,nextAt=0}
    end
  end
end

function E.receiptField(id, row)
  return table.concat({ "RA1", E.token(id,160), E.integer(row.amount,0), E.token(row.reason,32),
    E.integer(row.cycleId,0), E.token(row.deliveryToken,96) }, ",")
end

function E.cloudReceipt(profile, id)
  for _,field in ipairs(profile.extraProfileFields or {}) do
    local f=E.split(field,",")
    if #f==6 and f[1]=="RA1" and f[2]==id and E.integer(f[3],0)>0 then
      return { amount=E.integer(f[3],0,1000000),reason=f[4],cycleId=E.integer(f[5],0),deliveryToken=f[6] }
    end
  end
end

function E.restoreCloudReceipts(profile)
  for _,field in ipairs(profile.extraProfileFields or {}) do
    local f=E.split(field,",")
    if #f==6 and f[1]=="RA1" and f[2]~="" and not E.arrayContains(profile.recentAwards,f[2]) then
      local receipt=E.cloudReceipt(profile,f[2])
      if receipt then
        receipt.attempts,receipt.nextAt,receipt.durable=0,0,true
        E.localState.pendingAwards[f[2]]=receipt
      end
    end
  end
  -- The persisted receipt+dedup commit, not a vanished room's acknowledgement,
  -- is sufficient to finish a local pending operation after reconnect.
  for id in pairs(E.localState.pendingAwards) do
    if E.arrayContains(profile.recentAwards,id) then E.localState.pendingAwards[id]=nil end
  end
end

function E.sendAward(awardId, row)
  if not E.isAuthority() or row == nil then return false end
  if row.persisting then return false end
  if not row.durable then
    row.persisting=true
    row.persistStartedAt=E.now()
    row.attempts=E.integer(row.attempts,0)+1
    row.nextAt=E.now()+E.retryDelay(row.attempts)
    -- Persist the authorized receipt in the recipient's existing profile before
    -- delivery. Only the recipient later converts it into spendable currency.
    local started=E.authorityMutate(row.openId,function(profile)
      if not E.isAuthority() or E.outbox[awardId]~=row then return false,"AUTHORITY_CHANGED" end
      if E.arrayContains(profile.recentAwards,awardId) then return false,"ALREADY_COMMITTED" end
      local previous=E.cloudReceipt(profile,awardId)
      if previous then
        return false,previous.amount==row.amount and previous.deliveryToken==row.deliveryToken and "RECEIPT_EXISTS" or "RECEIPT_CONFLICT"
      end
      local count=0
      for _,field in ipairs(profile.extraProfileFields or {}) do if field:sub(1,4)=="RA1," then count=count+1 end end
      if count>=128 then return false,"RECEIPT_INBOX_FULL" end
      profile.extraProfileFields[#profile.extraProfileFields+1]=E.receiptField(awardId,row)
      return true,"RECEIPT_SAVED"
    end,function(ok,reason,profile)
      row.persisting=false
      if E.destroyed or not E.isAuthority() or E.outbox[awardId]~=row then return end
      if ok and profile and E.arrayContains(profile.recentAwards,awardId) then
        E.outbox[awardId]=nil; E.publishAwardLedger(); return
      end
      local receipt=ok and profile and E.cloudReceipt(profile,awardId) or nil
      row.durable=receipt~=nil and receipt.amount==row.amount and receipt.deliveryToken==row.deliveryToken
      row.nextAt=E.now()+(row.durable and 0 or E.retryDelay(row.attempts))
    end)
    if not started then row.persisting=false end
    return started
  end
  -- Same ownership split as BladeValley: authority issues, recipient writes its
  -- own character store. A confirmed owner-only VarSync authorizes the receipt.
  local currentActorId = E.actorIdByOpenId[row.openId] or row.actorId
  row.actorId = E.integer(currentActorId, 0)
  if row.actorId == 0 then
    row.nextAt = E.now() + E.retryDelay(row.attempts)
    return false
  end
  row.attempts = E.integer(row.attempts, 0) + 1
  row.nextAt = E.now() + E.retryDelay(row.attempts)
  if not E.publishAwardLedger() then return false end
  return E.sendToActor("GeocoreReceiveAward", row.actorId, row.actorId, row.openId,
    awardId, row.amount, row.reason, row.cycleId, row.deliveryToken)
end

function GeocoreReceiveAward(targetActorId, openId, awardId, amount, reason, cycleId, deliveryToken)
  if E.integer(targetActorId, 0) ~= E.actorId(E.localActor())
    or tostring(openId or "") ~= E.localState.openId then return "ok=false|reason=WRONG_TARGET" end
  awardId, amount, deliveryToken = E.token(awardId, 160), E.integer(amount, 0, 1000000), E.token(deliveryToken, 96)
  if awardId == "" or amount <= 0 or deliveryToken == "" then return "ok=false|reason=INVALID_AWARD" end
  if not E.isAuthorizedAward(awardId,targetActorId,openId,amount,reason,cycleId,deliveryToken) then
    return "ok=false|reason=UNAUTHORIZED_AWARD"
  end
  local pending = E.localState.pendingAwards[awardId]
  if pending ~= nil and (pending.deliveryToken ~= deliveryToken or pending.amount ~= amount) then
    return "ok=false|reason=AWARD_CONFLICT"
  end
  E.localState.pendingAwards[awardId] = pending or { amount = amount, reason = E.token(reason, 32),
    cycleId = E.integer(cycleId, 0), deliveryToken = deliveryToken, attempts = 0, nextAt = 0 }
  E.saveLocalCache()
  E.emitProfile()
  E.processAwardQueue()
  return "ok=true|reason=AWAITING_CHARACTER_COMMIT"
end

function E.acknowledgeAward(awardId, deliveryToken)
  local actorId = E.actorId(E.localActor())
  if E.isAuthority() then
    return GeocoreAuthorityAcknowledgeAward(actorId, E.localState.openId, awardId, deliveryToken)
  end
  if not E.networkSettled() then return false end
  return pcall(function()
    self:SendMessageToOwner("GeocoreAuthorityAcknowledgeAward", actorId,
      E.localState.openId, awardId, deliveryToken)
  end)
end

function GeocoreAuthorityAcknowledgeAward(targetActorId, openId, awardId, deliveryToken)
  if not E.isAuthority() then return false end
  targetActorId, openId = E.integer(targetActorId, 0), tostring(openId or "")
  awardId, deliveryToken = E.token(awardId, 160), E.token(deliveryToken, 96)
  if not E.validateIdentity(targetActorId, openId) or awardId == "" or deliveryToken == "" then return false end
  local row = E.outbox[awardId]
  if row ~= nil and (row.openId ~= openId or row.deliveryToken ~= deliveryToken
    or row.ackVerifyInFlight == true) then return false end
  if not E.storageAvailable() or not E.networkSettled() then return false end
  local generation = row ~= nil and E.integer(row.ackVerifyGeneration, 0) + 1 or 0
  if row ~= nil then
    row.ackVerifyInFlight, row.ackVerifyStartedAt, row.ackVerifyGeneration = true, E.now(), generation
  end
  local function current()
    return not E.destroyed and E.isAuthority()
      and (row == nil or (E.outbox[awardId] == row and row.ackVerifyGeneration == generation))
  end
  local function retry()
    if current() and row ~= nil then
      row.ackVerifyInFlight = false
      row.attempts = E.integer(row.attempts, 0) + 1
      row.nextAt = E.now() + E.retryDelay(row.attempts)
    end
  end
  local started = pcall(function()
    E.runStorage(function()
      local completed = pcall(function()
      if not current() then return end
      local storeCode, store = E.getStore(openId)
      if not current() then return end
      if tonumber(storeCode) ~= 0 or store == nil then
        retry()
        return
      end
      local readCode, value = store:GetData(E.cfg.profileKey)
      E.metrics.datastoreReads = E.metrics.datastoreReads + 1
      if not current() then return end
      local committed = tonumber(readCode) == 0 and E.arrayContains(E.decodeProfile(value).recentAwards, awardId)
      if not committed then
        retry()
        return
      end
      local current = E.outbox[awardId]
      if current ~= nil and current.openId == openId and current.deliveryToken == deliveryToken then
        E.outbox[awardId] = nil
        E.publishAwardLedger()
        E.metrics.awardsConfirmed = E.metrics.awardsConfirmed + 1
      end
      E.sendToActor("GeocoreApplyAwardAckResult", targetActorId,
        targetActorId, openId, awardId, deliveryToken)
      end)
      if not completed then retry() end
    end)
  end)
  if not started then retry() end
  return started
end

function GeocoreApplyAwardAckResult(targetActorId, openId, awardId, deliveryToken)
  if E.integer(targetActorId, 0) ~= E.actorId(E.localActor())
    or tostring(openId or "") ~= E.localState.openId then return false end
  awardId, deliveryToken = E.token(awardId, 160), E.token(deliveryToken, 96)
  local pending = E.localState.pendingAwards[awardId]
  if pending == nil or pending.deliveryToken ~= deliveryToken then return false end
  -- A guessed/replayed acknowledgement must never erase an uncommitted receipt.
  if pending.cloudObserved ~= true and not (E.localState.initialized == true
    and E.arrayContains(E.profile and E.profile.recentAwards, awardId)) then return false end
  E.localState.pendingAwards[awardId] = nil
  E.saveLocalCache()
  E.emitProfile()
  return true
end

function E.processAwardQueue()
  if E.localState.inFlightAwardId ~= "" or E.localState.openId == ""
    or not E.profileReady() or E.localStore == nil
    or E.localState.loading or not E.networkSettled() then return false end
  local awardIds = {}
  local tickNow = E.now()
  for awardId, row in pairs(E.localState.pendingAwards) do
    if tickNow >= (tonumber(row.nextAt) or 0) then awardIds[#awardIds + 1] = awardId end
  end
  table.sort(awardIds)
  local awardId = awardIds[1]
  if awardId == nil then return false end
  local row, requestedOpenId = E.localState.pendingAwards[awardId], E.localState.openId
  local generation,awardStore=E.localState.loadGeneration,E.localStore
  local function current()return not E.destroyed and E.localState.openId==requestedOpenId
    and E.localState.loadGeneration==generation end
  if row.cloudObserved == true then
    row.attempts = E.integer(row.attempts, 0) + 1
    row.nextAt = E.now() + E.retryDelay(row.attempts)
    E.acknowledgeAward(awardId, row.deliveryToken)
    E.saveLocalCache()
    return true
  end
  E.localState.inFlightAwardId = awardId
  E.localState.inFlightAwardStartedAt=E.now()
  E.emitProfile()
  local started, startError = pcall(function()
    E.runStorage(function()
      local completed,callbackError=pcall(function()
      if not current() then return end
      local readCode, value = awardStore:UpdateData(E.cfg.profileKey,function(current)
        if not E.validProfile(current) then return current end
        local profile=E.decodeProfile(current)
        if not E.arrayContains(profile.recentAwards,awardId) then
          local receipt=E.cloudReceipt(profile,awardId)
          if receipt==nil or receipt.amount~=row.amount or receipt.deliveryToken~=row.deliveryToken then return current end
          profile.Coins=profile.Coins+receipt.amount
          profile.recentAwards[#profile.recentAwards+1]=awardId
          E.trimArray(profile.recentAwards,E.cfg.recentAwardLimit)
          profile.revision=profile.revision+1
          local extras={}
          for _,field in ipairs(profile.extraProfileFields or {}) do
            if field~=E.receiptField(awardId,receipt) then extras[#extras+1]=field end
          end
          profile.extraProfileFields=extras
        end
        return E.encodeProfile(profile)
      end)
      E.metrics.datastoreWrites = E.metrics.datastoreWrites + 1
      if not current() then return end
      E.localState.inFlightAwardId = ""
      if tonumber(readCode) ~= 0 then
        row.attempts = E.integer(row.attempts, 0) + 1
        row.nextAt = E.now() + E.retryDelay(row.attempts)
        E.failLocal("AWARD_VERIFY_" .. tostring(readCode))
        return
      end
      if not E.validProfile(value) then E.failLocal("INVALID_CLOUD_PROFILE"); return end
      local profile = E.decodeProfile(value)
      if not E.arrayContains(profile.recentAwards, awardId) then
        row.attempts = E.integer(row.attempts, 0) + 1
        row.nextAt = E.now() + E.retryDelay(row.attempts)
        E.localState.lastError = "AWARD_NOT_COMMITTED"
        E.saveLocalCache()
        E.emitProfile()
        return
      end
      if E.profile ~= nil and E.arrayContains(E.profile.recentAwards, awardId) then
        E.metrics.duplicateAwards = E.metrics.duplicateAwards + 1
      end
      row.cloudObserved = true
      row.attempts = E.integer(row.attempts, 0) + 1
      row.nextAt = E.now() + E.retryDelay(row.attempts)
      E.applyLocalProfile(profile, E.confirmedBackend())
      E.saveLocalCache()
      E.acknowledgeAward(awardId, row.deliveryToken)
      end)
      if not completed and current() then
        E.localState.inFlightAwardId=""
        E.failLocal("AWARD_CALLBACK_FAILED")
      end
    end)
  end)
  if not started then
    E.localState.inFlightAwardId = ""
    row.attempts = E.integer(row.attempts, 0) + 1
    row.nextAt = E.now() + E.retryDelay(row.attempts)
    E.failLocal("AWARD_START_" .. tostring(startError))
  end
  return started
end

function E.updateRoomAuthority()
  if not E.isAuthority() or not E.resolveHolders() then return end
  local phase, cycleId = "", 0
  pcall(function() phase = tostring(E.managerHolder.script.GetRaceManagerState() or "") end)
  pcall(function() cycleId = E.integer(E.managerHolder.script.GetRaceManagerCycleId(), 0) end)
  if cycleId <= 0 then return end
  if E.room.cycleId ~= cycleId then
    -- Final results can arrive at the recycling/preparing boundary. Finish
    -- the previous round before replacing its frozen roster and economics.
    if E.room.locked and not E.room.settled then E.settleRound() end
    local previousSettlement = E.room.settlementSnapshot or E.lastSettlementSnapshot or ""
    E.room = { cycleId = cycleId, roundKey = "", phase = phase, locked = false, reconstructing = false,
      reconstructPending = 0, participants = {}, participantByOpenId = {}, vehicles = {},
      sponsorshipByOpenId = {}, playerSponsor = 0, systemSponsor = 0, pool = 0,
      open = false, frozen = false,
      revision = E.roomView.cycleId == cycleId and E.integer(E.roomView.revision, 0) + 1 or 0,
      settled = false, settlement = nil,
      settlementSnapshot = phase == "PREPARING" and previousSettlement or "", nextBroadcastAt = 0 }
  end
  E.room.phase = phase
  if not E.room.locked and (phase == "WAITING" or phase == "RACING" or phase == "RECYCLING") then
    E.lockRoom(cycleId, phase)
  end
  if E.room.locked and E.room.reconstructing then E.tickSponsorReconstruction() end
  if E.room.locked and E.sponsorLockDue() then E.freezeRoom() end
  if E.room.locked and phase == "WAITING" and not E.room.reconstructing then
    E.room.open = E.sponsorRoomStatus() == "READY"
  end
  if phase == "RECYCLING" then E.settleRound() end
  E.broadcastRoom(false)
end

function E.tickOutbox()
  if not E.isAuthority() then return end
  local tickNow, sent = E.now(), 0
  for awardId, row in pairs(E.outbox) do
    if row.persisting and tickNow-(row.persistStartedAt or tickNow)>=E.cfg.loadTimeoutSeconds then row.persisting=false end
    if row.ackVerifyInFlight == true
      and tickNow - (tonumber(row.ackVerifyStartedAt) or tickNow) >= E.cfg.loadTimeoutSeconds then
      row.ackVerifyInFlight = false
      row.ackVerifyGeneration = E.integer(row.ackVerifyGeneration, 0) + 1
      row.nextAt = tickNow
    end
    if tickNow >= (tonumber(row.nextAt) or 0) then
      E.sendAward(awardId, row)
      sent = sent + 1
      if sent >= 8 then break end
    end
  end
end

function E.tickOperations()
  local tickNow, sent = E.now(), 0
  for transactionId, row in pairs(E.localState.pendingOperations) do
    if tickNow >= (tonumber(row.nextAt) or 0) then
      E.sendOperation(transactionId, row)
      sent = sent + 1
      if sent >= 4 then break end
    end
  end
end

-- CHECKIN7-0905: fixed seven rewards; trusted Beijing dates, one atomic profile
-- write per claim, permanent mask deduplication, no local/UI-generated currency.
function E.checkInValidInteger(value, low, high)
  local n = tonumber(value)
  if n == nil or n ~= n or n == math.huge or n == -math.huge
    or n ~= math.floor(n) or n < low or n > high then return nil end
  return n
end

function E.checkInServerSeconds(requireAuthoritySample)
  -- Calendar is independent of race scheduling and never uses the device date.
  local clock, tick = E.calendar, E.now()
  if not E.networkSettled() then return nil end
  if tick >= clock.nextAt then
    clock.nextAt = tick + 1
    local ok, seconds = pcall(function()
      local utility = DouyinUtility or CS.DouyinUtility
      return utility.GetServerUnixTime()
    end)
    seconds = ok and E.checkInValidInteger(seconds, 1577836800, 4102444800) or nil
    if seconds ~= nil then
      clock.seconds, clock.sampledAt, clock.lastError = seconds, tick, "none"
    else clock.lastError = "TIME_SYNCING" end
  end
  if clock.seconds == nil or clock.sampledAt == nil or clock.lastError ~= "none"
    or tick < clock.sampledAt or tick - clock.sampledAt > 2 then return nil end
  -- Return the actual server sample, not an extrapolated device clock across midnight.
  return clock.seconds
end

function E.checkInDay(seconds)
  local sec = E.checkInValidInteger(seconds, 1577836800, 4102444800)
  return sec ~= nil and math.floor((sec + 28800) / 86400) or nil
end

function E.checkInUnlocked(firstSeconds, serverSeconds)
  -- Fixed campaign: 2026-09-11 00:00:00 Asia/Shanghai. First login is not the origin.
  local first, current = E.checkInDay(1789056000), E.checkInDay(serverSeconds)
  if first == nil or current == nil or current < first then return 0 end
  return math.min(7, current - first + 1)
end

function E.checkInHasDay(mask, day)
  return math.floor((tonumber(mask) or 0) / (2 ^ (day - 1))) % 2 == 1
end

function E.checkInTransactionId(openId, day)
  local n = E.checkInValidInteger(day, 0, 7)
  if n == nil or tostring(openId or "") == "" then return "" end
  return "CHECKIN7V1_" .. E.stableHash(openId) .. (n == 0 and "_INIT" or "_DAY_" .. tostring(n))
end

function E.hydrateCheckInLedger()
  local checkInFirstEnterLedger = E.backendLedger("check-in", checkInFirstEnterLedger)
  if not E.isAuthority() or checkInFirstEnterLedger == nil then return false end
  local ok, value = pcall(function() return tostring(checkInFirstEnterLedger:GetValue() or "") end)
  if not ok or value:sub(1, 6) ~= "GCIF1\n" then return false end
  for line in value:gmatch("\n([^\n]+)") do
    local f = E.split(line, "|")
    local openId = E.unescapeRoomField(f[1])
    local first = E.checkInValidInteger(f[2], 1577836800, 4102444800)
    if #f == 2 and openId ~= "" and first ~= nil then
      E.checkIn.firstByOpenId[openId] = math.min(E.checkIn.firstByOpenId[openId] or first, first)
    end
  end
  return true
end

function E.publishCheckInLedger()
  local checkInFirstEnterLedger = E.backendLedger("check-in", checkInFirstEnterLedger)
  if not E.isAuthority() or checkInFirstEnterLedger == nil then return false end
  local rows = {}
  for openId, first in pairs(E.checkIn.firstByOpenId) do
    rows[#rows + 1] = E.escapeRoomField(openId) .. "|" .. tostring(first)
  end
  table.sort(rows)
  local payload = "GCIF1\n" .. table.concat(rows, "\n")
  local ok, old = pcall(function() return checkInFirstEnterLedger:GetValue() end)
  if ok and old == payload then return true end
  local wrote = pcall(function() checkInFirstEnterLedger:SetValue(payload) end)
  local read, confirmed = pcall(function() return checkInFirstEnterLedger:GetValue() end)
  return wrote and read and confirmed == payload
end

function E.observeCheckInEntries()
  if not E.isAuthority() or not E.networkSettled() then return false end
  E.hydrateCheckInLedger()
  local now = E.checkInServerSeconds(true)
  if now == nil then return false end
  for openId in pairs(E.actorIdByOpenId) do
    if E.checkIn.firstByOpenId[openId] == nil then E.checkIn.firstByOpenId[openId] = now end
  end
  return E.publishCheckInLedger()
end

function E.recordEquippedVisual(openId, profile)
  if not E.isAuthority() or profile == nil or tostring(openId or "") == "" then return end
  local previous = E.checkIn.observedProfiles[openId]
  if previous ~= nil and previous.revision > E.integer(profile.revision, 1) then return end
  local equipped, inventory = profile.EquippedCosmeticsV1 or {}, profile.CosmeticInventoryV1 or {}
  local function validated(category, first, second)
    local id = tostring(equipped[category] or "")
    if (id ~= first and id ~= second) or inventory[id] ~= true then return "" end
    local catalog = E.cfg.catalog[id]
    return catalog ~= nil and catalog.category == category and id or ""
  end
  E.checkIn.observedProfiles[openId] = { revision = E.integer(profile.revision, 1),
    title = validated("title", "TITLE_DEFAULT", "TITLE_VETERAN_DRIVER"),
    wing = validated("wing", "WING_01"), halo = validated("halo", "HALO_01") }
  E.publishEquippedVisual()
end

function E.publishEquippedVisual()
  if not E.isAuthority() or equippedVisualSnapshot == nil then return false end
  local rows = {}
  for openId, profile in pairs(E.checkIn.observedProfiles) do
    local actorId = E.actorIdByOpenId[openId]
    if actorId ~= nil and actorId > 0
      and ((profile.title or "") ~= "" or (profile.wing or "") ~= "" or (profile.halo or "") ~= "") then
      rows[#rows + 1] = table.concat({ actorId, profile.revision, E.stableHash(openId),
        profile.title or "", profile.wing or "", profile.halo or "" }, "^")
    end
  end
  table.sort(rows)
  local body = table.concat(rows, "|")
  local read, previous = pcall(function() return tostring(equippedVisualSnapshot:GetValue() or "") end)
  local oldRevision, oldBody = tostring(previous or ""):match("^GCEV[12]|(%d+)|?(.*)$")
  if read and tostring(previous):sub(1, 6) == "GCEV2|" and oldRevision ~= nil and oldBody == body then return true end
  E.checkIn.visualRevision = math.max(E.checkIn.visualRevision, tonumber(oldRevision) or 0) + 1
  local payload = "GCEV2|" .. tostring(E.checkIn.visualRevision) .. (body ~= "" and "|" .. body or "")
  return pcall(function() equippedVisualSnapshot:SetValue(payload) end)
end

function GetGeocoreEquippedVisualSnapshot()
  local ok, value = pcall(function() return tostring(equippedVisualSnapshot:GetValue() or "") end)
  return ok and value:match("^GCEV[12]|%d+") and value or "GCEV2|0"
end

-- No inventory/titles are accepted from a client payload. The owner reads the
-- stable player scope itself; this handshake does not require a check-in clock.
function GeocoreAuthorityRefreshVisual(actorId, openId)
  if not E.isAuthority() or not E.networkSettled() or not E.validateIdentity(actorId, openId) then return false end
  local tick = E.now()
  if tick < (E.visualRequests[openId] or 0) then return false end
  E.visualRequests[openId] = tick + 5
  return pcall(function() E.runStorage(function()
    if not E.isAuthority() or E.destroyed then return end
    local code, store = E.getStore(openId)
    if tonumber(code) ~= 0 or store == nil then return end
    local read, raw = store:GetData(E.cfg.profileKey)
    E.metrics.datastoreReads = E.metrics.datastoreReads + 1
    if tonumber(read) == 0 and E.validProfile(raw) and E.isAuthority() then
      E.recordEquippedVisual(openId, E.decodeProfile(raw))
    end
  end) end)
end

function E.tickVisualSync()
  if not E.profileReady() or not E.networkSettled() or E.localState.actorId <= 0 or E.now() < E.nextVisualSync then return end
  E.nextVisualSync = E.now() + 10
  if E.isAuthority() then E.recordEquippedVisual(E.localState.openId, E.profile)
  else pcall(function() self:SendMessageToOwner("GeocoreAuthorityRefreshVisual", E.localState.actorId, E.localState.openId) end) end
end

function E.reconcileCheckInOperations()
  if not E.profileReady() then return end
  local ci = E.profile and E.profile.CheckIn7V1
  if ci == nil or ci.invalid then return end
  for id, row in pairs(E.localState.pendingOperations) do
    local day = E.checkInValidInteger(row.a, 1, 7)
    if (row.kind == "CHECKIN_INIT" and row.ownerAcknowledged == true)
      or (row.kind == "CHECKIN_CLAIM" and day ~= nil and E.checkInHasDay(ci.claimedMask, day)) then
      if row.kind == "CHECKIN_INIT" then E.checkIn.ownerInitAcknowledged = true end
      E.localState.pendingOperations[id] = nil
      E.checkIn.localError = "none"
    end
  end
end

function E.queueCheckIn(day)
  if E.isTestBackend() and not E.testBackendAllowed() then return nil end
  if E.localState.openId == "" or E.localState.actorId <= 0 then return nil end
  local id = E.checkInTransactionId(E.localState.openId, day)
  if id == "" then return nil end
  if E.localState.pendingOperations[id] == nil then
    E.localState.pendingOperations[id] = { kind = day == 0 and "CHECKIN_INIT" or "CHECKIN_CLAIM",
      a = tostring(day), b = "", cycleId = 0, attempts = 0, nextAt = 0 }
    E.saveLocalCache()
  end
  return id
end

function GetGeocoreCheckInSnapshot()
  local now = E.checkInServerSeconds()
  local ci = E.profile and E.profile.CheckIn7V1
  local cloudReady = E.profileReady()
    and E.networkSettled() and E.localState.openId ~= ""
  local valid = ci ~= nil and not ci.invalid
  local initialized = cloudReady and valid and now ~= nil
  local first = valid and ci.firstEnterAtServerSeconds or 0
  local unlocked = valid and now ~= nil and E.checkInUnlocked(first, now) or 0
  local claimed, pending = valid and ci.claimedMask or 0, 0
  for _, row in pairs(E.localState.pendingOperations) do
    local day = row.kind == "CHECKIN_CLAIM" and E.checkInValidInteger(row.a, 1, 7) or nil
    if day ~= nil and not E.checkInHasDay(pending, day) then pending = pending + 2 ^ (day - 1) end
  end
  local nextUnlock = initialized and unlocked < 7 and (1789056000 + unlocked * 86400) or 0
  local err = E.checkIn.localError or "none"
  if not cloudReady then err = E.localState.lastError ~= "none" and E.localState.lastError or "CLOUD_SYNCING"
  elseif now == nil then err = "TIME_SYNCING"
  elseif ci ~= nil and ci.invalid then err = "INVALID_CHECKIN_PROFILE"
  elseif not valid then err = err ~= "none" and err or "CHECKIN_INITIALIZING" end
  local signature = table.concat({ tostring(initialized), unlocked, claimed, pending,
    nextUnlock, first, err, E.localState.openId }, "|")
  if signature ~= E.checkIn.signature then
    E.checkIn.signature = signature
    E.checkIn.revision = E.checkIn.revision + 1
  end
  return initialized == true, unlocked, claimed, pending, nextUnlock, first, now or 0, err, E.checkIn.revision
end

function GeocoreCheckInClaim(day)
  day = E.checkInValidInteger(day, 1, 7)
  if day == nil then return "ok=false|reason=DAY_INVALID" end
  local initialized, unlocked, claimed = GetGeocoreCheckInSnapshot()
  if not initialized then return "ok=false|reason=CHECKIN_NOT_READY" end
  if day > unlocked then return "ok=false|reason=DAY_LOCKED" end
  if E.checkInHasDay(claimed, day) then return "ok=false|reason=ALREADY_CLAIMED" end
  local id = E.queueCheckIn(day)
  if id == nil then return "ok=false|reason=IDENTITY_PENDING" end
  E.checkIn.localError = "none"
  E.sendOperation(id, E.localState.pendingOperations[id])
  return "ok=true|reason=QUEUED|transactionId=" .. id
end

function GeocoreCheckInRefresh()
  E.checkIn.refreshRequested = true
  E.checkIn.nextTick = 0
  return "ok=true|reason=QUEUED"
end

function GeocoreApplyCheckInResult(targetActorId, openId, day, transactionId, ok, reason)
  -- The response carries no profile/amount/timestamp. It can request a cloud read,
  -- but can never mint currency, mark a bit claimed, or trust a client timestamp.
  if E.integer(targetActorId, 0) ~= E.actorId(E.localActor())
    or tostring(openId or "") ~= E.localState.openId then return "ok=false|reason=WRONG_TARGET" end
  day = E.checkInValidInteger(day, 0, 7)
  if day == nil or transactionId ~= E.checkInTransactionId(openId, day) then return "ok=false|reason=TRANSACTION_INVALID" end
  local row = E.localState.pendingOperations[transactionId]
  reason = tostring(reason or "UNKNOWN")
  if ok == true then
    if row ~= nil then
      row.ownerAcknowledged = true
      row.nextAt = E.now() + E.retryDelay(row.attempts)
    end
    E.checkIn.refreshRequested = true
    E.checkIn.localError = "CLOUD_CONFIRMING"
    if not E.localState.loading and E.now() >= E.localState.retryAt and E.beginLocalLoad() then
      E.checkIn.refreshRequested = false
    end
  elseif reason == "DAY_LOCKED" or reason == "DAY_INVALID" or reason == "IDENTITY_MISMATCH"
    or reason == "TRANSACTION_INVALID" or reason == "INVALID_CHECKIN_PROFILE" or reason == "INVALID_CLOUD_PROFILE" then
    E.localState.pendingOperations[transactionId] = nil
    E.checkIn.localError = reason
  else
    if row ~= nil then row.nextAt = E.now() + E.retryDelay(row.attempts) end
    E.checkIn.localError = reason
  end
  E.saveLocalCache()
  return "ok=true"
end

function GeocoreAuthorityCheckIn(requestedActorId, openId, day, transactionId)
  if not E.isAuthority() then return "ok=false|reason=NOT_AUTHORITY" end
  local actorId = E.checkInValidInteger(requestedActorId, 1, 2147483647)
  openId = tostring(openId or "")
  day = E.checkInValidInteger(day, 0, 7)
  if day == nil then return "ok=false|reason=DAY_INVALID" end
  if actorId == nil or not E.validateIdentity(actorId, openId) then return "ok=false|reason=IDENTITY_MISMATCH" end
  if transactionId ~= E.checkInTransactionId(openId, day) then return "ok=false|reason=TRANSACTION_INVALID" end
  local function respond(ok, reason)
    E.sendToActor("GeocoreApplyCheckInResult", actorId, actorId, openId, day, transactionId, ok, reason)
    return "ok=" .. tostring(ok == true) .. "|reason=" .. tostring(reason)
  end
  if not E.networkSettled() then return respond(false, "NETWORK_SYNCING") end
  local now = E.checkInServerSeconds(true)
  if now == nil then return respond(false, "TIME_SYNCING") end
  if not E.observeCheckInEntries() then return respond(false, "FIRST_ENTER_SYNCING") end
  local firstObserved = E.checkIn.firstByOpenId[openId]
  if firstObserved == nil or firstObserved > now then return respond(false, "TIME_SYNCING") end
  if not E.storageAvailable() then return respond(false, "DATASTORE_UNAVAILABLE") end
  local previous = E.checkIn.busyByOpenId[openId]
  if previous ~= nil and E.now() - previous.startedAt < E.cfg.loadTimeoutSeconds then return respond(false, "CHECKIN_BUSY") end
  local request = { startedAt = E.now() }
  E.checkIn.busyByOpenId[openId] = request
  local function current()
    return not E.destroyed and E.isAuthority() and E.networkSettled()
      and E.checkIn.busyByOpenId[openId] == request
  end
  local function finish(ok, reason)
    if E.checkIn.busyByOpenId[openId] ~= request then return end
    E.checkIn.busyByOpenId[openId] = nil
    if not E.destroyed and E.isAuthority() then respond(ok, reason) end
  end
  local started = pcall(function()
    E.runStorage(function()
      local completed = pcall(function()
        if not current() then finish(false, "AUTHORITY_CHANGED"); return end
        local code, store = E.getStore(openId)
        if not current() then finish(false, "AUTHORITY_CHANGED"); return end
        if tonumber(code) ~= 0 or store == nil then
          finish(false, tonumber(code) == -10015 and "DATASTORE_NOT_OPEN" or "STORE_FAILED_" .. tostring(code)); return
        end
        local outcome = "SAVE_FAILED"
        local updateCode, value = store:UpdateData(E.cfg.profileKey, function(raw)
          if not current() then outcome = "AUTHORITY_CHANGED"; return raw end
          local text = tostring(raw or "")
          local version, balance = text:match("^(V[123]);([^;]+);")
          local number = tonumber(version and balance or text)
          if number == nil or number ~= number or number < 0 or number == math.huge then
            outcome = "INVALID_CLOUD_PROFILE"; return raw
          end
          local profile = E.decodeProfile(raw)
          local ci, changed = profile.CheckIn7V1, false
          if ci ~= nil and ci.invalid then outcome = "INVALID_CHECKIN_PROFILE"; return raw end
          if ci == nil then
            ci = { schemaVersion = 1, firstEnterAtServerSeconds = firstObserved,
              firstEnterBeijingDay = E.checkInDay(firstObserved), claimedMask = 0 }
            profile.CheckIn7V1, changed = ci, true
          elseif firstObserved < ci.firstEnterAtServerSeconds then
            ci.firstEnterAtServerSeconds, ci.firstEnterBeijingDay, changed = firstObserved, E.checkInDay(firstObserved), true
          end
          outcome = "INITIALIZED"
          if day > 0 then
            if day > E.checkInUnlocked(ci.firstEnterAtServerSeconds, now) then outcome = "DAY_LOCKED"
            elseif E.checkInHasDay(ci.claimedMask, day) then outcome = "ALREADY_CLAIMED"
            else
              ci.claimedMask, changed, outcome = ci.claimedMask + 2 ^ (day - 1), true, "CLAIMED"
              if day == 7 then profile.CosmeticInventoryV1.TITLE_VETERAN_DRIVER = true
              else profile.Coins = profile.Coins + (day == 1 and 1000 or 500) end
              E.appendTransaction(profile, transactionId, "CLAIMED")
            end
          end
          if not changed then return raw end
          profile.revision = E.integer(profile.revision, 1) + 1
          return E.encodeProfile(profile)
        end)
        E.metrics.datastoreWrites = E.metrics.datastoreWrites + 1
        if not current() then finish(false, "AUTHORITY_CHANGED"); return end
        -- Do NOT SetData on missing here. The ordinary first-profile initializer
        -- creates the base key; this operation only retries an atomic update.
        if tonumber(updateCode) ~= 0 then
          finish(false, tonumber(updateCode) == -10001 and "PROFILE_NOT_READY"
            or "SAVE_FAILED_" .. tostring(updateCode)); return
        end
        local confirmed = E.decodeProfile(value)
        local ci = confirmed.CheckIn7V1
        if ci == nil or ci.invalid then finish(false, outcome); return end
        E.recordEquippedVisual(openId, confirmed)
        if day > 0 and not E.checkInHasDay(ci.claimedMask, day) then finish(false, outcome); return end
        finish(true, outcome)
      end)
      if not completed then finish(false, "DATASTORE_CALLBACK_FAILED") end
    end)
  end)
  if not started then finish(false, "DATASTORE_START_FAILED") end
  return "ok=" .. tostring(started) .. "|reason=" .. (started and "QUEUED" or "DATASTORE_START_FAILED")
end

function E.tickCheckIn()
  if E.now() < E.checkIn.nextTick then return end
  E.checkIn.nextTick = E.now() + 0.5
  if E.isAuthority() then E.observeCheckInEntries(); E.publishEquippedVisual() end
  if E.localState.openId == "" or not E.networkSettled() then return end
  if E.checkIn.refreshRequested and not E.localState.loading
    and E.now() >= E.localState.retryAt and E.beginLocalLoad() then E.checkIn.refreshRequested = false end
  if E.profileReady() and E.checkInServerSeconds() ~= nil then
    E.reconcileCheckInOperations()
    local ci = E.profile and E.profile.CheckIn7V1
    if not E.checkIn.ownerInitAcknowledged and not (ci ~= nil and ci.invalid) then E.queueCheckIn(0) end
  end
end

function GetGeocoreCoinDisplaySnapshot()
  -- display, confirmedKnown, source, error, pending, confirmed, revision, inFlight.
  -- Unknown cloud history uses a display-only zero baseline; no zero is persisted.
  return E.coinDisplayState()
end

function GetGeocoreEconomySnapshot()
  local profile = E.profile or E.defaultProfile()
  if E.localState.qaOverride ~= nil then profile = E.localState.qaOverride.profile end
  local initialized = E.localState.qaOverride ~= nil or E.localState.initialized
  local backend = E.localState.qaOverride ~= nil and "cloud" or E.localState.backend
  local lastError = E.localState.qaOverride ~= nil and "none" or E.localState.lastError
  local pendingCount = E.localState.qaOverride ~= nil and 0
    or E.tableCount(E.localState.pendingOperations) + E.tableCount(E.localState.pendingAwards)
  return profile.Coins, initialized, backend,
    E.encodeSet(profile.CosmeticInventoryV1), E.encodeEquipment(profile.EquippedCosmeticsV1),
    profile.revision, lastError, pendingCount,
    E.localState.lastAction
end

-- Read-only UI contract: unlike QA overrides this reports the actual confirmed
-- transaction backend. Calling it never starts a load, resets state or mints.
function GetGeocoreEconomyTransactionReadiness()
  local test, state = E.testBackend, E.localState
  local verified = E.editorEnvironmentVerified()
  local active = test.configured and test.mode == "editor-test"
  local backend = tostring(state.backend or "pending")
  local reason = "READY"
  if active and editorTestEconomy ~= true then reason = "TEST_DISABLED"
  elseif active and not verified then reason = "EDITOR_ENVIRONMENT_UNVERIFIED"
  elseif state.openId == "" or state.actorId <= 0
    or E.playerOpenId(E.localPlayer()) ~= state.openId then reason = "IDENTITY_PENDING"
  elseif not E.networkSettled() then reason = "NETWORK_SYNCING"
  elseif state.loading then reason = "PROFILE_LOADING"
  elseif not state.initialized or backend ~= E.confirmedBackend() then
    reason = editorTestEconomy == true and not verified and "EDITOR_ENVIRONMENT_UNVERIFIED" or "BACKEND_NOT_READY"
  end
  return reason == "READY", backend, reason, verified, active == true,
    test.configured and test.initialCoins or E.testInteger(initialCoins, 10000, 0, 1000000),
    test.configured and test.resetVersion or E.testInteger(testResetVersion, 1, 1, 1000000)
end

function GetGeocoreShopCatalog()
  local rows = {}
  for itemId, item in pairs(E.cfg.catalog) do
    if item.shop ~= false then
      rows[#rows + 1] = table.concat({ itemId, item.category, item.displayName, tostring(item.price) }, "^")
    end
  end
  table.sort(rows)
  return table.concat(rows, "|")
end

-- Explicit local-editor visual acceptance only. No caller-supplied identity,
-- currency or date; cannot unlock production or modify the seven-day ledger.
function GeocoreEditorPreviewUnlockVeteranTitle()
  if not E.isTestBackend() or not E.testBackendAllowed() or not E.isAuthority()
    or not E.localState.initialized or E.localState.backend~="editor-test"
    or not E.validateIdentity(E.localState.actorId,E.localState.openId) then
    return "ok=false|reason=EDITOR_TEST_ONLY"
  end
  local openId=E.localState.openId
  E.authorityMutate(openId,function(profile)
    if not E.testBackendAllowed() then return false,"EDITOR_TEST_ONLY" end
    if profile.CosmeticInventoryV1.TITLE_VETERAN_DRIVER then return false,"ALREADY_OWNED" end
    profile.CosmeticInventoryV1.TITLE_VETERAN_DRIVER=true
    return true,"EDITOR_PREVIEW_UNLOCKED"
  end,function(saved,reason,profile)
    if saved and E.testBackendAllowed() and E.localState.openId==openId then
      E.applyLocalProfile(profile,"editor-test",false)
    end
  end)
  return "ok=true|reason=EDITOR_PREVIEW_QUEUED"
end

function GetGeocoreSponsorSnapshot()
  local view = E.localState.qaOverride ~= nil and E.localState.qaOverride.sponsor or E.roomView
  local safeOpenId = E.localState.qaOverride ~= nil and E.localState.qaOverride.safeOpenId
    or E.token(E.localState.openId, 120)
  local participant = view.sponsorBySafeOpenId[safeOpenId] ~= nil
  local localAmount = participant and E.integer(view.sponsorBySafeOpenId[safeOpenId], 0) or 0
  return view.open, view.frozen, participant, localAmount, view.playerSponsor,
    view.systemSponsor, view.pool, view.revision, view.cycleId, view.participantCount,
    view.sponsorMinAmount or E.cfg.sponsorMinAmount, view.sponsorMaxAmount or E.cfg.sponsorMaxAmount, view.phase
end

function GetGeocoreSponsorConfig()
  return E.cfg.sponsorEnabled, E.cfg.sponsorMinParticipants, E.cfg.sponsorMinAmount,
    E.cfg.sponsorMaxAmount, E.cfg.systemSponsorPerParticipant,
    E.cfg.sponsorRankWeight, E.cfg.sponsorPersonalWeight
end

-- Read-only, append-only contract for HUD and remote clients. No identity values.
function GetGeocoreSponsorReadiness()
  local qa = E.localState.qaOverride
  local view = qa ~= nil and qa.sponsor or E.roomView
  local status, lastError, pending, retry = view.sponsorStatus or "SYNCING", view.sponsorError or "none",
    E.integer(view.reconstructPending, 0), E.integer(view.sponsorRetrySeconds, 0)
  if qa ~= nil then status = view.open and "READY" or "CLOSED" end
  local configured = view.sponsorConfigured ~= false
  local minimum = E.integer(view.sponsorMinimumParticipants or E.cfg.sponsorMinParticipants, 1, 30)
  return status, lastError, pending, retry, E.integer(view.cycleId, 0), tostring(view.phase or ""),
    configured, minimum, view.locked == true or (qa ~= nil and view.open == true),
    qa ~= nil or E.localState.openId ~= ""
end

function GetGeocoreRaceSettlementSnapshot()
  local view=E.isAuthority() and E.room or E.roomView
  local snapshot=tostring(view.settlementSnapshot or "")
  if snapshot~="" then return snapshot end
  return table.concat({ "GCRS1", tostring(view.cycleId or 0), tostring(view.revision or 0), "pending" }, "|")
end

function GeocoreEconomyConfigureSponsors(enabled, minimumParticipants, minimumAmount,
  maximumAmount, systemPerParticipant, rankWeight, personalWeight)
  if not E.isAuthority() or (E.room.phase ~= "" and E.room.phase ~= "PREPARING") then
    return "ok=false|reason=CONFIG_LOCKED"
  end
  local nextMinimum = E.integer(minimumAmount, 1, 5000)
  local nextMaximum = E.integer(maximumAmount, nextMinimum, 100000)
  E.cfg.sponsorEnabled = enabled == true
  E.cfg.sponsorMinParticipants = E.integer(minimumParticipants, 0, 30)
  E.cfg.sponsorMinAmount, E.cfg.sponsorMaxAmount = nextMinimum, nextMaximum
  E.cfg.systemSponsorPerParticipant = E.integer(systemPerParticipant, 0, 100000)
  E.cfg.sponsorRankWeight = math.max(0, tonumber(rankWeight) or 0)
  E.cfg.sponsorPersonalWeight = math.max(0, tonumber(personalWeight) or 0)
  if E.cfg.sponsorRankWeight + E.cfg.sponsorPersonalWeight <= 0 then E.cfg.sponsorRankWeight = 1 end
  return "ok=true"
end

function GetGeocoreEconomyQaSnapshot()
  local settlement = E.room.settlement
  local display, known, source, _, pending, confirmed, revision, inFlight = E.coinDisplayState()
  return table.concat({
    "schema=" .. E.cfg.schema,
    "scopeReady=" .. tostring(E.localState.openId ~= ""),
    "networkSettled=" .. tostring(E.networkSettled()),
    "actorId=" .. tostring(E.localState.actorId),
    "profileKey=" .. E.cfg.profileKey,
    "backend=" .. E.localState.backend,
    "initialized=" .. tostring(E.localState.initialized),
    "loading=" .. tostring(E.localState.loading),
    "lastError=" .. E.localState.lastError,
    "storeCode=" .. tostring(E.localState.lastStoreCode),
    "reads=" .. tostring(E.metrics.datastoreReads),
    "pendingOperations=" .. tostring(E.tableCount(E.localState.pendingOperations)),
    "pendingAwards=" .. tostring(E.tableCount(E.localState.pendingAwards)),
    "displayCoins=" .. tostring(display),
    "confirmedCoins=" .. tostring(confirmed),
    "confirmedKnown=" .. tostring(known),
    "pendingDelta=" .. tostring(pending),
    "inFlightDelta=" .. tostring(inFlight),
    "displaySource=" .. source,
    "displayRevision=" .. tostring(revision),
    "outbox=" .. tostring(E.tableCount(E.outbox)),
    "cycle=" .. tostring(E.room.cycleId),
    "phase=" .. tostring(E.room.phase),
    "participants=" .. tostring(#E.room.participants),
    "pool=" .. tostring(E.room.pool),
    "settled=" .. tostring(E.room.settled),
    "systemRecovered=" .. tostring(settlement ~= nil and settlement.sponsor.systemRecovered or 0),
    "writes=" .. tostring(E.metrics.datastoreWrites),
    "failures=" .. tostring(E.metrics.datastoreFailures),
  }, "|")
end

function GetGeocoreLegacyStorageDiagnostics()
  local s=E.localState
  local initialized,unlocked,claimed,_,_,_,_,checkError=GetGeocoreCheckInSnapshot()
  local display,known,source,err,_,confirmed=E.coinDisplayState()
  return table.concat({
    "构建 STORAGE-0911 / "..E.confirmedBackend(),
    "身份摘要 "..(s.openId~="" and E.stableHash(s.openId) or "未就绪"),
    "存储 GeocoreCharacterV1 / CommerceProfileV1",
    "状态 "..s.backend.." / 已读取 "..tostring(s.initialized).." / 请求中 "..tostring(s.loading),
    "确认余额 "..(known and tostring(confirmed) or "未知").." / 显示 "..tostring(display).." / 来源 "..source,
    "错误 "..tostring(err).." / Store "..tostring(s.lastStoreCode).." / Read "..tostring(s.lastReadCode or "未读取"),
    "读取次数 "..E.metrics.datastoreReads.." / 写入次数 "..E.metrics.datastoreWrites.." / 重试 "..s.retryCount,
    "档案版本 "..tostring(E.profile and E.profile.revision or 0).." / 待提交 "..(E.tableCount(s.pendingAwards)+E.tableCount(s.pendingOperations)),
    "签到 "..tostring(initialized).." / 解锁 "..unlocked.." / 已领掩码 "..claimed.." / "..checkError,
    "日历 "..E.calendar.lastError.." / 称号同步独立于比赛时钟",
  },"\n")
end

function GeocoreEconomyQAPreview(coins, sponsorOpen, localSponsor, pool, participantCount, owned)
  local profile = E.defaultProfile()
  profile.Coins = E.integer(coins, 0)
  profile.CosmeticInventoryV1.WING_01, profile.CosmeticInventoryV1.HALO_01 = owned ~= false, owned ~= false
  profile.EquippedCosmeticsV1.wing = owned ~= false and "WING_01" or ""
  local safeOpenId = E.token(E.localState.openId ~= "" and E.localState.openId or "QA_LOCAL", 120)
  E.localState.qaOverride = { profile = profile, safeOpenId = safeOpenId, sponsor = {
    cycleId = E.roomView.cycleId > 0 and E.roomView.cycleId or 1, phase = "WAITING",
    open = sponsorOpen == true, frozen = false, participantCount = E.integer(participantCount, 0),
    playerSponsor = E.integer(localSponsor, 0), systemSponsor = E.integer(participantCount, 0) * 100,
    pool = E.integer(pool, 0), revision = 999999, sponsorBySafeOpenId = { [safeOpenId] = E.integer(localSponsor, 0) },
  } }
  E.emitProfile()
  return true
end

function GeocoreEconomyQAClearPreview()
  E.localState.qaOverride = nil
  E.emitProfile()
  return true
end

function GeocoreEconomyBuildAwards(cycleId, rows)
  local result, participantCount = {}, #(rows or {})
  for _, row in ipairs(rows or {}) do
    if row.finished == true and tostring(row.openId or "") ~= "" then
      local amount = participantCount >= 4 and tonumber(row.rank) == 1
        and E.cfg.firstPlaceReward or E.cfg.normalFinishReward
      result[tostring(row.openId)] = amount
    end
  end
  return result
end

-- LOCAL-0911: device-local account persistence. No server storage API.
-- Inserted before lifecycle callbacks; all existing UI entry points retained.
E.device = { values = {}, busy = {}, resetNotice = false }
function E.confirmedBackend() return E.isTestBackend() and "editor-test" or "local" end
function E.storageAvailable() return E.isTestBackend() and E.testBackendAllowed() or E.U.PlayerPrefs ~= nil end
function E.runStorage(callback) return callback() end
function E.pumpStorage() return true end
function E.deviceKey(openId, suffix)
  return "GeocoreLocalV1.9388408382210." .. openId .. "." .. suffix
end

function E.writeDevice(openId, value)
  if openId ~= E.localState.openId or not E.validProfile(value) then return false end
  local key = E.deviceKey(openId, "Profile")
  local old = E.device.values[openId]
  local ok = pcall(function()
    if old and E.validProfile(old) then E.U.PlayerPrefs.SetString(key .. ".Backup", old) end
    E.U.PlayerPrefs.SetString(key, value)
    E.U.PlayerPrefs.Save()
  end)
  if not ok then
    -- Restore the in-process preference value too: an unsuccessful Save must
    -- not appear committed on the next in-session read.
    pcall(function() E.U.PlayerPrefs.SetString(key, old or "") end)
    E.localState.lastError = "LOCAL_SAVE_FAILED"
    return false
  end
  E.device.values[openId] = value
  return true
end

local testGetStore = E.getStore
function E.getStore(openId)
  if E.isTestBackend() then return testGetStore(openId) end
  openId = tostring(openId or "")
  if openId == "" or openId ~= E.localState.openId then return -2, nil end
  local store = {}
  function store:GetData(key)
    if key ~= E.cfg.profileKey or openId ~= E.localState.openId then return -2, nil end
    local value = E.device.values[openId]
    return value and 0 or -10001, value
  end
  function store:SetData(key, value)
    if key ~= E.cfg.profileKey or E.device.busy[openId] then return -2, nil end
    return E.writeDevice(openId, value) and 0 or -3, E.device.values[openId]
  end
  function store:UpdateData(key, transform)
    local code, old = self:GetData(key)
    if code ~= 0 or E.device.busy[openId] then return -2, nil end
    E.device.busy[openId] = true
    local ok, value = pcall(transform, old)
    E.device.busy[openId] = nil
    if not ok or not E.validProfile(value) then return -3, old end
    return self:SetData(key, value)
  end
  return 0, store
end

local previousLoadCache = E.loadLocalCache
function E.loadLocalCache(openId)
  previousLoadCache(openId)
  if E.isTestBackend() or openId == "" then return end
  local key = E.deviceKey(openId, "Profile")
  local ok, raw = pcall(function() return E.U.PlayerPrefs.GetString(key, "") end)
  local valid = ok and E.validProfile(raw)
  if not valid then
    local backupOk, backup = pcall(function() return E.U.PlayerPrefs.GetString(key .. ".Backup", "") end)
    if backupOk and E.validProfile(backup) then raw, valid = backup, true end
  end
  -- Adopt only a valid legacy cache; never fabricate inaccessible cloud data.
  if not valid and E.localState.cacheAvailable then raw, valid = E.encodeProfile(E.profile), true end
  if not valid then
    raw = E.encodeProfile(E.newCloudProfile())
    E.localState.pendingOperations, E.localState.pendingAwards = {}, {}
    E.device.resetNotice = true
  end
  E.device.values[openId] = raw
  E.localState.cacheAvailable = false
  if E.writeDevice(openId, raw) then E.localState.lastError = "none" end
end

local previousBeginLoad = E.beginLocalLoad
function E.beginLocalLoad()
  if E.isTestBackend() then return previousBeginLoad() end
  local id = E.localState.openId
  if id == "" or E.playerOpenId(E.localPlayer()) ~= id then return false end
  local _, store = E.getStore(id)
  local code, raw = store:GetData(E.cfg.profileKey)
  if code ~= 0 or not E.validProfile(raw) then return false end
  E.localStore = store
  E.localState.lastStoreCode, E.localState.lastReadCode = 0, 0
  E.metrics.datastoreReads = E.metrics.datastoreReads + 1
  E.applyLocalProfile(E.decodeProfile(raw), "local", true)
  return true
end

-- Local purchases/check-in use the existing validated business rules on the
-- recipient. Only race decisions continue to require room ownership.
function E.isAccountAuthority(openId)
  return tostring(openId or "") == E.localState.openId and E.profileReady()
end
local previousSendOperation = E.sendOperation
function E.sendOperation(id, row)
  if not row or not E.profileReady() then return false end
  if row.kind == "BUY" then
    return GeocoreAuthorityBuy(E.localState.actorId, E.localState.openId, row.a, id)
  elseif row.kind == "EQUIP" then
    return GeocoreAuthorityEquip(E.localState.actorId, E.localState.openId, row.a, row.b, id)
  elseif row.kind == "CHECKIN_INIT" or row.kind == "CHECKIN_CLAIM" then
    local day = row.kind == "CHECKIN_INIT" and 0 or E.integer(row.a, 0)
    local now = E.checkInServerSeconds()
    if not now then row.nextAt = E.now() + 1; E.checkIn.localError = "TIME_SYNCING"; return false end
    local success, outcome = false, "LOCAL_SAVE_FAILED"
    E.authorityMutate(E.localState.openId, function(p)
      local ci = p.CheckIn7V1
      if ci and ci.invalid then return false, "INVALID_CHECKIN_PROFILE" end
      if not ci then ci = {firstEnterAtServerSeconds=now, firstEnterBeijingDay=E.checkInDay(now), claimedMask=0}; p.CheckIn7V1=ci end
      if day == 0 then return true, "INITIALIZED" end
      if day < 1 or day > 7 then return false, "DAY_INVALID" end
      if day > E.checkInUnlocked(ci.firstEnterAtServerSeconds, now) then return false, "DAY_LOCKED" end
      if E.checkInHasDay(ci.claimedMask, day) then return false, "ALREADY_CLAIMED" end
      ci.claimedMask = ci.claimedMask + 2 ^ (day - 1)
      if day == 7 then p.CosmeticInventoryV1.TITLE_VETERAN_DRIVER = true
      else p.Coins = p.Coins + (day == 1 and 1000 or 500) end
      E.appendTransaction(p, id, "CLAIMED")
      return true, "CLAIMED"
    end, function(ok, reason, p)
      success, outcome = ok, reason
      if ok then
        if day == 0 then E.checkIn.ownerInitAcknowledged = true end
        E.localState.pendingOperations[id] = nil
        E.applyLocalProfile(p, E.confirmedBackend())
      else row.nextAt = E.now() + 2 end
      E.checkIn.localError = ok and "none" or reason
      E.saveLocalCache()
    end)
    return success, outcome
  end
  return previousSendOperation(id, row)
end

-- Award authority remains the room-owned replicated ledger. Persist the
-- authorized receipt on the recipient device before converting it to coins.
local previousSendAward = E.sendAward
function E.sendAward(id, row)
  if row then row.durable = true end -- no remote receipt persistence prerequisite
  return previousSendAward(id, row)
end
local previousReceiveAward = GeocoreReceiveAward
function GeocoreReceiveAward(actorId, openId, id, amount, reason, cycle, token)
  if openId ~= E.localState.openId or E.integer(actorId,0) ~= E.localState.actorId
    or not E.profileReady() or not E.isAuthorizedAward(id,actorId,openId,amount,reason,cycle,token) then
    return "ok=false|reason=UNAUTHORIZED_AWARD"
  end
  local committed = false
  E.authorityMutate(openId, function(p)
    if E.arrayContains(p.recentAwards,id) or E.cloudReceipt(p,id) then return false,"EXISTS" end
    p.extraProfileFields[#p.extraProfileFields+1] = E.receiptField(id,{amount=amount,reason=reason,cycleId=cycle,deliveryToken=token})
    return true,"RECEIPT_SAVED"
  end, function(ok, _, p)
    committed = ok
    if ok then E.applyLocalProfile(p,E.confirmedBackend()) end
  end)
  if not committed then return "ok=false|reason=LOCAL_SAVE_FAILED" end
  return previousReceiveAward(actorId,openId,id,amount,reason,cycle,token)
end
function GeocoreAuthorityAcknowledgeAward(actorId,openId,id,token)
  if not E.isAuthority() or not E.validateIdentity(actorId,openId) then return false end
  local row = E.outbox[id]
  if not row or row.openId ~= openId or row.deliveryToken ~= token then return false end
  E.outbox[id] = nil
  E.publishAwardLedger()
  E.sendToActor("GeocoreApplyAwardAckResult",actorId,actorId,openId,id,token)
  return true
end

-- Cosmetic announcements contain no balances and do not write another device.
function GeocoreLocalVisual(actorId,openId,title,wing,halo)
  if not E.isAuthority() or not E.validateIdentity(actorId,openId) then return false end
  local p=E.defaultProfile();p.EquippedCosmeticsV1={};p.CosmeticInventoryV1={}
  for category,item in pairs({title=title,wing=wing,halo=halo}) do
    if E.cfg.catalog[item] and E.cfg.catalog[item].category==category then
      p.EquippedCosmeticsV1[category]=item;p.CosmeticInventoryV1[item]=true
    end
  end
  p.revision=(E.checkIn.observedProfiles[openId] and E.checkIn.observedProfiles[openId].revision or 0)+1
  E.recordEquippedVisual(openId,p)
  return true
end
function E.tickVisualSync()
  if not E.profileReady() or not E.networkSettled() or E.now()<E.nextVisualSync then return end
  E.nextVisualSync=E.now()+2
  local eq=E.profile.EquippedCosmeticsV1
  if E.isAuthority() then E.recordEquippedVisual(E.localState.openId,E.profile)
  else pcall(function() self:SendMessageToOwner("GeocoreLocalVisual",E.localState.actorId,E.localState.openId,eq.title or "",eq.wing or "",eq.halo or "") end) end
end

function GetGeocoreStorageDiagnostics()
  return table.concat({"构建 LOCAL-0911 / "..E.confirmedBackend(),
    "存储 PlayerPrefs / 世界9388408382210 / 独立玩家档案",
    "状态 "..tostring(E.localState.initialized).." / "..tostring(E.localState.lastError),
    "金币 "..tostring(E.profile and E.profile.Coins or 0),
    E.device.resetNotice and "本地进度不可用，已开始新进度" or "本地进度已恢复",
    "换房可读取则保留，无法读取则重置；不跨设备同步"},"\n")
end


-- Sponsorship is a room protocol: owner checks the race window, the payer
-- commits its own debit, then owner records the total in the room snapshot.
E.device.sponsorRequests = {}
local legacySendToActor = E.sendToActor
function E.sendToActor(name, actorId, ...)
  if E.integer(actorId,0)==E.localState.actorId then
    if name=="GeocoreLocalSponsorDebit" then return GeocoreLocalSponsorDebit(...) end
    if name=="GeocoreLocalSponsorQuery" then return GeocoreLocalSponsorQuery(...) end
    if name=="GeocoreLocalSponsorCutoff" then return GeocoreLocalSponsorCutoff(...) end
    if name=="GeocoreLocalSponsorAccepted" then return GeocoreLocalSponsorAccepted(...) end
  end
  return legacySendToActor(name,actorId,...)
end
function E.localSponsorReply(cycle,key,total)
  if E.isAuthority() then return GeocoreLocalSponsorTotal(E.localState.actorId,E.localState.openId,cycle,key,total) end
  return pcall(function() self:SendMessageToOwner("GeocoreLocalSponsorTotal",E.localState.actorId,E.localState.openId,cycle,key,total) end)
end
function GeocoreLocalSponsorQuery(actorId,openId,cycle,key)
  if actorId~=E.localState.actorId or openId~=E.localState.openId or not E.profileReady() then return false end
  return E.localSponsorReply(cycle,key,E.integer(E.profile.SponsorTotalsV1[key],0))
end
function GeocoreLocalSponsorTotal(actorId,openId,cycle,key,total)
  if not E.isAuthority() or not E.validateIdentity(actorId,openId) or E.room.cycleId~=cycle or E.room.roundKey~=key then return false end
  if E.room.frozen or E.sponsorLockDue() then
    local accepted=E.room.sponsorshipByOpenId[openId] or 0
    if E.integer(total,0)<=accepted then
      E.sendToActor("GeocoreLocalSponsorAccepted",actorId,actorId,openId,cycle,key,accepted)
      return true
    end
    E.sendToActor("GeocoreLocalSponsorCutoff",actorId,actorId,openId,cycle,key,E.room.sponsorshipByOpenId[openId] or 0)
    return false
  end
  local row=E.room.participantByOpenId[openId]
  if not row then return false end
  total=E.integer(total,0,E.cfg.sponsorMaxAmount)
  E.room.sponsorshipByOpenId[openId]=math.max(E.room.sponsorshipByOpenId[openId] or 0,total)
  if not row.sponsorRead then
    row.sponsorRead,row.sponsorReadInFlight,row.sponsorReadError=true,false,nil
    E.room.reconstructPending=math.max(0,E.room.reconstructPending-1)
  end
  if E.room.reconstructing then E.finishSponsorReconstruction()
  else E.recomputePool();E.room.revision=E.room.revision+1;E.broadcastRoom(true) end
  if E.publishSponsorLedger() then
    E.sendToActor("GeocoreLocalSponsorAccepted",actorId,actorId,openId,cycle,key,total)
  end
  return true
end
function E.readParticipantSponsor(row)
  if not E.sponsorReadCurrent(row,E.room) or E.now()<(row.nextSponsorReadAt or 0) then return false end
  row.nextSponsorReadAt=E.now()+1
  return E.sendToActor("GeocoreLocalSponsorQuery",row.actorId,row.actorId,row.openId,E.room.cycleId,E.room.roundKey)
end
function GeocoreAuthoritySponsor(actorId,openId,amount,cycle,id)
  if not E.isAuthority() or not E.validateIdentity(actorId,openId) then return false end
  amount=E.integer(amount,0)
  if E.room.cycleId~=cycle or not E.room.participantByOpenId[openId]
    or E.sponsorRoomStatus()~="READY" or E.room.frozen then
    E.sendActionResult(actorId,openId,id,false,"SPONSOR_CLOSED",nil);return false
  end
  if amount<E.cfg.sponsorMinAmount or amount>E.cfg.sponsorMaxAmount then return false end
  return E.sendToActor("GeocoreLocalSponsorDebit",actorId,actorId,openId,amount,cycle,id,E.room.roundKey)
end
function GeocoreLocalSponsorDebit(actorId,openId,amount,cycle,id,key)
  if actorId~=E.localState.actorId or openId~=E.localState.openId or not E.profileReady() then return false end
  local op=E.localState.pendingOperations[id]
  if not op or op.kind~="SPONSOR" or op.cycleId~=cycle or E.integer(op.a,0)~=amount then return false end
  if E.roomView.cycleId~=cycle or not E.roomView.open or E.sponsorWindowStatus(cycle)~="READY" or (E.device.closedSponsorRounds and E.device.closedSponsorRounds[key]) then return false end
  local success=false
  E.authorityMutate(openId,function(p)
    if E.transactionStatus(p,id)~="" then return false,"DUPLICATE" end
    local total=E.integer(p.SponsorTotalsV1[key],0)
    if total+amount>E.cfg.sponsorMaxAmount then return false,"SPONSOR_LIMIT" end
    if p.Coins<amount then return false,"COINS_NOT_ENOUGH" end
    p.Coins=p.Coins-amount;p.SponsorTotalsV1[key]=total+amount
    E.appendTransaction(p,id,"SPONSOR"..amount)
    return true,"SPONSOR_CONFIRMED"
  end,function(ok,reason,p)
    success=ok
    if ok then
      E.applyLocalProfile(p,E.confirmedBackend())
      E.device.sponsorRequests[key]={id=id,cycle=cycle,total=E.integer(p.SponsorTotalsV1[key],0)}
      E.localState.lastAction="true|SPONSOR_DEBITED|"..id
      E.localSponsorReply(cycle,key,E.integer(p.SponsorTotalsV1[key],0))
      E.localState.pendingOperations[id]=nil
    end
    if not ok then E.localState.lastAction="false|"..reason.."|"..id end
    E.saveLocalCache()
  end)
  return success
end

-- Refresh sponsorship totals while waiting, also after an owner change.
local localTickVisual = E.tickVisualSync
function E.tickVisualSync()
  localTickVisual()
  if not E.profileReady() or not E.networkSettled() or E.now()<(E.device.sponsorSyncAt or 0) then return end
  E.device.sponsorSyncAt=E.now()+1
  for key,request in pairs(E.device.sponsorRequests) do
    if request.cycle==E.roomView.cycleId then E.localSponsorReply(request.cycle,key,request.total) end
  end
  if E.isAuthority() and E.room.locked and not E.room.frozen then
    for _,row in ipairs(E.room.participants) do
      E.sendToActor("GeocoreLocalSponsorQuery",row.actorId,row.actorId,row.openId,E.room.cycleId,E.room.roundKey)
    end
  end
end

-- SPONSOR-LOCK-0911: room replicated receipts survive payer disconnect/owner handoff.
function E.publishSponsorLedger()
  if not E.isAuthority() or not E.room.locked or sponsorCommittedLedger==nil then return false end
  local r=E.room
  local lines={table.concat({"GSL1",r.cycleId,E.escapeRoomField(r.roundKey),tostring(r.frozen),r.revision},"|")}
  for _,p in ipairs(r.participants) do
    lines[#lines+1]=table.concat({p.actorId,E.escapeRoomField(p.openId),E.escapeRoomField(p.vehicleName),E.integer(r.sponsorshipByOpenId[p.openId],0)},"|")
  end
  local payload=table.concat(lines,"\n")
  local ok,result=pcall(function()
    if tostring(sponsorCommittedLedger:GetValue() or "")~=payload then sponsorCommittedLedger:SetValue(payload) end
    return tostring(sponsorCommittedLedger:GetValue() or "")==payload
  end)
  return ok and result
end
function E.restoreSponsorLedger(cycle,phase)
  if sponsorCommittedLedger==nil then return false end
  local ok,payload=pcall(function()return tostring(sponsorCommittedLedger:GetValue() or "")end)
  if not ok then return false end
  local lines=E.split(payload,"\n");local h=E.split(lines[1],"|")
  if h[1]~="GSL1" or tonumber(h[2])~=cycle then return false end
  local participants,byId,totals,vehicles,byVehicle={},{},{},{},{}
  for i=2,#lines do
    local f=E.split(lines[i],"|");local id=E.unescapeRoomField(f[2]);local name=E.unescapeRoomField(f[3])
    if id=="" or byId[id] then return false end
    local p={actorId=E.integer(f[1],0),openId=id,vehicleName=name,sponsorRead=true}
    participants[#participants+1]=p;byId[id]=p;totals[id]=E.integer(f[4],0,E.cfg.sponsorMaxAmount)
    local v=byVehicle[name];if not v then v={name=name,actorIds={},openIds={}};byVehicle[name]=v;vehicles[#vehicles+1]=v end
    v.actorIds[#v.actorIds+1]=p.actorId;v.openIds[#v.openIds+1]=id
  end
  E.room={cycleId=cycle,phase=phase,roundKey=E.unescapeRoomField(h[3]),locked=true,frozen=h[4]=="true" or phase~="WAITING",
    reconstructing=false,reconstructPending=0,participants=participants,participantByOpenId=byId,vehicles=vehicles,
    sponsorshipByOpenId=totals,playerSponsor=0,systemSponsor=0,pool=0,open=false,revision=E.integer(h[5],0)+1,
    settled=false,settlement=nil,nextBroadcastAt=0}
  E.recomputePool();return true
end
function E.sponsorLockDue()
  if E.room.phase~="WAITING" then return true end
  local ok,remaining=pcall(function()return tonumber(E.managerHolder.script.GetRaceManagerRemainingMilliseconds())end)
  -- Stop new requests at T-2s; retain the final 2s for in-flight confirmations.
  return ok and remaining~=nil and remaining==0
end
function GeocoreLocalSponsorAccepted(actorId,openId,cycle,key,accepted)
  if actorId~=E.localState.actorId or openId~=E.localState.openId or cycle~=E.roomView.cycleId then return false end
  local request=E.device.sponsorRequests[key]
  if not request or request.cycle~=cycle or E.integer(accepted,0)<request.total then return false end
  E.localState.lastAction="true|SPONSOR_CONFIRMED|"..request.id
  E.device.sponsorRequests[key]=nil
  return true
end
function GeocoreLocalSponsorCutoff(actorId,openId,cycle,key,accepted)
  if actorId~=E.localState.actorId or openId~=E.localState.openId or not E.profileReady() then return false end
  if cycle~=E.roomView.cycleId or (E.roomView.phase=="WAITING" and not E.roomView.frozen) then return false end
  E.device.closedSponsorRounds=E.device.closedSponsorRounds or {}
  E.device.closedSponsorRounds[key]=true
  accepted=E.integer(accepted,0,E.cfg.sponsorMaxAmount)
  E.authorityMutate(openId,function(p)
    local paid=E.integer(p.SponsorTotalsV1[key],0)
    if paid<=accepted then return false,"NO_REFUND" end
    p.Coins=p.Coins+paid-accepted;p.SponsorTotalsV1[key]=accepted
    return true,"LATE_SPONSOR_REFUNDED"
  end,function(ok,_,p)if ok then
    E.applyLocalProfile(p,E.confirmedBackend())
    E.device.sponsorRequests[key]=nil
    E.localState.lastAction="false|LATE_SPONSOR_REFUNDED|"
  end end)
  return true
end

function OnPlayerJoined(player) E.observePlayer(player, nil) end
function OnNetSpawned() E.hydrateAwardLedger(); E.hydrateCheckInLedger() end
function OnVariablesSynced() E.hydrateAwardLedger(); E.hydrateCheckInLedger() end
function OnPlayerRejoined(player) E.observePlayer(player, nil) end
function OnActorSpawned(actor)
  E.refreshIdentities()
end

function OnOwnershipTransferred()
  E.refreshIdentities()
  E.hydrateAwardLedger()
  E.hydrateCheckInLedger()
  E.checkIn.ownerInitAcknowledged = false
  E.checkIn.busyByOpenId, E.checkIn.observedProfiles = {}, {}
  E.visualRequests, E.nextVisualSync = {}, 0
  if E.isAuthority() then
    E.room.locked, E.room.reconstructing, E.room.settled = false, false, false
    E.room.open = false
    E.room.revision = math.max(E.integer(E.room.revision, 0),
      E.roomView.cycleId == E.room.cycleId and E.integer(E.roomView.revision, 0) or 0) + 1
    E.tick.roomAt = 0
  end
end

function Start()
  E.ensureBackend()
  math.randomseed(math.floor(E.now() * 1000) + E.actorId(E.localActor()))
  E.resolveHolders()
  E.hydrateAwardLedger()
  E.hydrateCheckInLedger()
  E.refreshIdentities()
  if E.localState.openId ~= "" then E.beginLocalLoad() end
  E.updateRoomAuthority()
  E.emitProfile()
end

function Update()
  E.refreshTestConfiguration()
  local tickNow = E.now()
  local connected = E.networkSettled()
  if connected and E.wasConnected == false then
    E.localState.retryAt, E.tick.profileAt, E.calendar.nextAt, E.nextVisualSync = 0, 0, 0, 0
    E.checkIn.refreshRequested = true
  end
  E.wasConnected = connected
  if E.localState.inFlightAwardId~="" and tickNow-(E.localState.inFlightAwardStartedAt or tickNow)>=E.cfg.loadTimeoutSeconds then
    E.localState.inFlightAwardId=""
    E.localState.loadGeneration=E.localState.loadGeneration+1
    E.failLocal("AWARD_TIMEOUT")
  end
  if tickNow >= E.tick.identityAt then E.tick.identityAt = tickNow + 1; E.refreshIdentities() end
  E.tickLocalLoad()
  E.tickCheckIn()
  E.tickVisualSync()
  if E.profileReady() and not E.localState.loading and tickNow >= (E.localState.nextRefreshAt or 0) then
    E.localState.nextRefreshAt = tickNow + 30
    E.beginLocalLoad()
  end
  if E.localState.openId ~= "" and not E.localState.loading and not E.profileReady()
    and tickNow >= E.localState.retryAt and tickNow >= E.tick.profileAt then
    E.tick.profileAt = tickNow + 0.5
    E.beginLocalLoad()
  end
  if tickNow >= E.tick.operationsAt then
    E.tick.operationsAt = tickNow + 0.25
    E.tickOperations()
    E.processAwardQueue()
  end
  if tickNow >= E.tick.roomAt then
    E.tick.roomAt = tickNow + 0.20
    E.updateRoomAuthority()
  end
  if tickNow >= E.tick.outboxAt then
    E.tick.outboxAt = tickNow + 0.25
    E.tickOutbox()
  end
end

function OnDestroy()
  E.destroyed = true
  E.localState.loadGeneration = E.localState.loadGeneration + 1
  E.saveLocalCache()
  E.managerHolder, E.sessionHolder, E.localStore = nil, nil, nil
end
