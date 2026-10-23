# 星梦巴：当前工程制作接口

根节点 ID：`-1024730032`。根节点缩放：`{'x': 2.0, 'y': 2.0, 'z': 2.0}`。座位数：**6**。

车辆逻辑：[原有驾驶脚本](../../lua/modules/pi-lp37-star-dream.lua)；绑定 ID：`40b08af1-fa7d-4952-b7e1-1eab05150ca6`。
所有完整参数与布局见本目录 `vehicle.json`、`scene-nodes.json`。这些节点的 `pos/rot/scale` 来自编辑器序列化；不要把世界坐标直接当作子节点本地坐标。

## 实际引用的模型

- [A045 A045-LP37_BUSKID_SUNNY-fl-01-of-01.glb](../../models/catalog/A045-LP37_BUSKID_SUNNY-fl-01-of-01.glb)
- [A046 A046-LP37_BUSKID_SUNNY-fr-01-of-01.glb](../../models/catalog/A046-LP37_BUSKID_SUNNY-fr-01-of-01.glb)
- [A047 A047-LP37_BUSKID_SUNNY-rl-01-of-01.glb](../../models/catalog/A047-LP37_BUSKID_SUNNY-rl-01-of-01.glb)
- [A048 A048-LP37_BUSKID_SUNNY-rr-01-of-01.glb](../../models/catalog/A048-LP37_BUSKID_SUNNY-rr-01-of-01.glb)
- [A050 A050-12-star-dream-bus--buskid-counterpart-runtime-v1.glb](../../models/catalog/A050-12-star-dream-bus--buskid-counterpart-runtime-v1.glb)
- [A051 A051-12-star-dream-bus--visual-body-material-v1.glb](../../models/catalog/A051-12-star-dream-bus--visual-body-material-v1.glb)

这是当前保存场景实际引用的二进制资源，不根据旧交付文件名猜选。多个车辆可能共用同一套轮胎资源，不要重复导入多个相同轮胎实例。

## 材质匹配接口

| Renderer 节点名称 | 记录顶点数 | 子网格/材质槽 | 严格匹配顶点数 |
|---|---:|---:|---|
| LP37_BUSKID_SUNNY_Wheel_FL_Part_01 | 1328 | 32 | True |
| LP37_BUSKID_SUNNY_Wheel_FR_Part_01 | 1328 | 32 | True |
| LP37_BUSKID_SUNNY_Wheel_RL_Part_01 | 1328 | 32 | True |
| LP37_BUSKID_SUNNY_Wheel_RR_Part_01 | 1328 | 32 | True |
| LP37_BUSKID_SUNNY_VisualBody | 5052 | 71 | True |

当前 mapping 的材质索引是从 1 开始的 Lua palette 索引。完整槽顺序见 `vehicle.json` 中 `materialIdentity.parts[].mats`，不是 GLB 全局 material 索引。升级拓扑后须重新采集并更新映射；不可把旧顶点数约束机械套用到新模型。

## 座位接口（车辆根局部坐标）

```lua
local seatConfigs = {
  { id = "driver", label = "驾驶·R1L", anchorPath = "SeatAnchor_Driver", canDrive = true, fallbackPosition = Vector3(-0.100934581238, 0.213084115948, 0.248598135273) },
  { id = "r1_right", label = "乘坐·R1R", anchorPath = "SeatAnchor_R1R", stationPath = "SeatStation_R1R", canDrive = false, fallbackPosition = Vector3(0.100934581238, 0.213084115948, 0.248598135273) },
  { id = "r2_left", label = "乘坐·R2L", anchorPath = "SeatAnchor_R2L", stationPath = "SeatStation_R2L", canDrive = false, fallbackPosition = Vector3(-0.100934581238, 0.213084115948, 0) },
  { id = "r2_right", label = "乘坐·R2R", anchorPath = "SeatAnchor_R2R", stationPath = "SeatStation_R2R", canDrive = false, fallbackPosition = Vector3(0.100934581238, 0.213084115948, 0) },
  { id = "r3_left", label = "乘坐·R3L", anchorPath = "SeatAnchor_R3L", stationPath = "SeatStation_R3L", canDrive = false, fallbackPosition = Vector3(-0.100934581238, 0.213084115948, -0.239252340713) },
  { id = "r3_right", label = "乘坐·R3R", anchorPath = "SeatAnchor_R3R", stationPath = "SeatStation_R3R", canDrive = false, fallbackPosition = Vector3(0.100934581238, 0.213084115948, -0.239252340713) },
}
```

## 轮胎接口（车辆根局部坐标）

```lua
local wheelConfigs = {
  { name = "LP37_Wheel_FL", radius = 0.104672899062, pivot = Vector3(-0.284112154597, 0.108411216886, 0.280373836774), visualScale = Vector3(0.328971966698, 0.328971966698, 0.328971966698), parts = { "LP37_BUSKID_SUNNY_Wheel_FL_Part_01" } },
  { name = "LP37_Wheel_FR", radius = 0.104672899062, pivot = Vector3(0.284112154597, 0.108411216886, 0.280373836774), visualScale = Vector3(0.328971966698, 0.328971966698, 0.328971966698), parts = { "LP37_BUSKID_SUNNY_Wheel_FR_Part_01" } },
  { name = "LP37_Wheel_RL", radius = 0.104672899062, pivot = Vector3(-0.284112154597, 0.108411216886, -0.280373836774), visualScale = Vector3(0.328971966698, 0.328971966698, 0.328971966698), parts = { "LP37_BUSKID_SUNNY_Wheel_RL_Part_01" } },
  { name = "LP37_Wheel_RR", radius = 0.104672899062, pivot = Vector3(0.284112154597, 0.108411216886, -0.280373836774), visualScale = Vector3(0.328971966698, 0.328971966698, 0.328971966698), parts = { "LP37_BUSKID_SUNNY_Wheel_RR_Part_01" } },
}
```

轮胎会被重挂到脚本生成的 Pivot，随后本地位置归零、旋转归零。因此源轮胎几何必须以轴心居中，不能把世界坐标烘进顶点。轮胎自转绕 Pivot 本地 X，前进读取根局部 Z；沿当前样件核对导入坐标变换。

## 场景实际覆盖参数

```json
{
  "driverTaken": false,
  "r1RightTaken": false,
  "r2LeftTaken": false,
  "r2RightTaken": false,
  "r3LeftTaken": false,
  "r3RightTaken": false,
  "driverOccupantActorId": 0,
  "r1RightOccupantActorId": 0,
  "r2LeftOccupantActorId": 0,
  "r2RightOccupantActorId": 0,
  "r3LeftOccupantActorId": 0,
  "r3RightOccupantActorId": 0,
  "raceResetCompletedCycleId": "",
  "raceResetPhysicalClaimCycleId": "",
  "raceResetPhysicalDoneCycleId": "",
  "topSpeed": 18,
  "acceleration": 12.5,
  "braking": 30,
  "turnSpeed": 56,
  "grip": 0.97,
  "cameraFollowEnabled": true,
  "reverseSpeed": 5,
  "coastingDrag": 9.5,
  "sidewaysFriction": 14,
  "cameraAlignSpeed": 120,
  "cameraAlignGrace": 0.45,
  "raceSessionStageSnapshot": ""
}
```
