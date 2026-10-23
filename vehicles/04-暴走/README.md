# 暴走：当前工程制作接口

根节点 ID：`-1349895540`。根节点缩放：`{'x': 1.5, 'y': 1.5, 'z': 1.5}`。座位数：**2**。

车辆逻辑：[原有驾驶脚本](../../lua/modules/pi-lp05b.lua)；绑定 ID：`4fd26fee-695e-49b9-9e3a-c4c63e32953d`。
所有完整参数与布局见本目录 `vehicle.json`、`scene-nodes.json`。这些节点的 `pos/rot/scale` 来自编辑器序列化；不要把世界坐标直接当作子节点本地坐标。

## 实际引用的模型

- [A014 A014-LP05B-fl-01-of-01.glb](../../models/catalog/A014-LP05B-fl-01-of-01.glb)
- [A015 A015-LP05B-fr-01-of-01.glb](../../models/catalog/A015-LP05B-fr-01-of-01.glb)
- [A016 A016-LP05B-rl-01-of-01.glb](../../models/catalog/A016-LP05B-rl-01-of-01.glb)
- [A017 A017-LP05B-rr-01-of-01.glb](../../models/catalog/A017-LP05B-rr-01-of-01.glb)
- [A018 A018-04-bosozoku-original-materials-taken-actor-runtime-v2.glb](../../models/catalog/A018-04-bosozoku-original-materials-taken-actor-runtime-v2.glb)

这是当前保存场景实际引用的二进制资源，不根据旧交付文件名猜选。多个车辆可能共用同一套轮胎资源，不要重复导入多个相同轮胎实例。

## 材质匹配接口

| Renderer 节点名称 | 记录顶点数 | 子网格/材质槽 | 严格匹配顶点数 |
|---|---:|---:|---|
| 暴走 | 5453 | 121 | True |
| LP05B_Wheel_FL_Part_01 | 538 | 11 | True |
| LP05B_Wheel_FR_Part_01 | 538 | 11 | True |
| LP05B_Wheel_RL_Part_01 | 538 | 11 | True |
| LP05B_Wheel_RR_Part_01 | 538 | 11 | True |

当前 mapping 的材质索引是从 1 开始的 Lua palette 索引。完整槽顺序见 `vehicle.json` 中 `materialIdentity.parts[].mats`，不是 GLB 全局 material 索引。升级拓扑后须重新采集并更新映射；不可把旧顶点数约束机械套用到新模型。

## 座位接口（车辆根局部坐标）

```lua
local seatConfigs = {
  { id = "driver", label = "驾驶", anchorPath = "SeatAnchor_Driver", canDrive = true, fallbackPosition = Vector3(-0.0917734, 0.196352, -0.0896392) },
  { id = "front_passenger", label = "乘坐·副驾", anchorPath = "SeatAnchor_FrontPassenger", stationPath = "SeatStation_FrontPassenger", canDrive = false, fallbackPosition = Vector3(0.0917734, 0.196352, -0.0896392) },
}
```

## 轮胎接口（车辆根局部坐标）

```lua
local wheelConfigs = {
  { name = "LP05B_Wheel_FL", radius = 0.153667, pivot = Vector3(-0.266783, 0.0832364, 0.251843), visualScale = Vector3(0.153667153, 0.153667153, 0.153667153), parts = { "LP05B_Wheel_FL_Part_01" } },
  { name = "LP05B_Wheel_FR", radius = 0.153667, pivot = Vector3(0.266783, 0.0832364, 0.251843), visualScale = Vector3(0.153667153, 0.153667153, 0.153667153), parts = { "LP05B_Wheel_FR_Part_01" } },
  { name = "LP05B_Wheel_RL", radius = 0.153667, pivot = Vector3(-0.271052, 0.0853706, -0.217695), visualScale = Vector3(0.153667153, 0.153667153, 0.153667153), parts = { "LP05B_Wheel_RL_Part_01" } },
  { name = "LP05B_Wheel_RR", radius = 0.153667, pivot = Vector3(0.271052, 0.0853706, -0.217695), visualScale = Vector3(0.153667153, 0.153667153, 0.153667153), parts = { "LP05B_Wheel_RR_Part_01" } },
}
```

轮胎会被重挂到脚本生成的 Pivot，随后本地位置归零、旋转归零。因此源轮胎几何必须以轴心居中，不能把世界坐标烘进顶点。轮胎自转绕 Pivot 本地 X，前进读取根局部 Z；沿当前样件核对导入坐标变换。

## 场景实际覆盖参数

```json
{
  "driverTaken": false,
  "frontPassengerTaken": false,
  "driverOccupantActorId": 0,
  "frontPassengerOccupantActorId": 0,
  "raceResetCompletedCycleId": "",
  "raceResetPhysicalClaimCycleId": "",
  "raceResetPhysicalDoneCycleId": "",
  "rearLeftTaken": false,
  "rearRightTaken": false,
  "topSpeed": 29.5,
  "acceleration": 25,
  "braking": 30,
  "turnSpeed": 75,
  "grip": 0.95,
  "cameraFollowEnabled": true,
  "reverseSpeed": 7,
  "coastingDrag": 8,
  "sidewaysFriction": 12,
  "cameraAlignSpeed": 120,
  "cameraAlignGrace": 0.45,
  "raceSessionStageSnapshot": ""
}
```
