# 积木：当前工程制作接口

根节点 ID：`2012705637`。根节点缩放：`{'x': 1.2, 'y': 1.2, 'z': 1.2}`。座位数：**2**。

车辆逻辑：[原有驾驶脚本](../../lua/modules/pi-lp26.lua)；绑定 ID：`8db8ed26-ff1d-45c6-9f00-2ffd3c72a094`。
所有完整参数与布局见本目录 `vehicle.json`、`scene-nodes.json`。这些节点的 `pos/rot/scale` 来自编辑器序列化；不要把世界坐标直接当作子节点本地坐标。

## 实际引用的模型

- [A039 A039-11-brick-original-materials-taken-actor-runtime-v2.glb](../../models/catalog/A039-11-brick-original-materials-taken-actor-runtime-v2.glb)
- [A040 A040-LP26-fl-01-of-01.glb](../../models/catalog/A040-LP26-fl-01-of-01.glb)
- [A041 A041-LP26-fr-01-of-01.glb](../../models/catalog/A041-LP26-fr-01-of-01.glb)
- [A042 A042-LP26-rl-01-of-01.glb](../../models/catalog/A042-LP26-rl-01-of-01.glb)
- [A043 A043-LP26-rr-01-of-01.glb](../../models/catalog/A043-LP26-rr-01-of-01.glb)

这是当前保存场景实际引用的二进制资源，不根据旧交付文件名猜选。多个车辆可能共用同一套轮胎资源，不要重复导入多个相同轮胎实例。

## 材质匹配接口

| Renderer 节点名称 | 记录顶点数 | 子网格/材质槽 | 严格匹配顶点数 |
|---|---:|---:|---|
| 积木 | 10487 | 138 | True |
| LP26_Wheel_FL_Part_01 | 578 | 15 | True |
| LP26_Wheel_FR_Part_01 | 578 | 15 | True |
| LP26_Wheel_RL_Part_01 | 578 | 15 | True |
| LP26_Wheel_RR_Part_01 | 578 | 15 | True |

当前 mapping 的材质索引是从 1 开始的 Lua palette 索引。完整槽顺序见 `vehicle.json` 中 `materialIdentity.parts[].mats`，不是 GLB 全局 material 索引。升级拓扑后须重新采集并更新映射；不可把旧顶点数约束机械套用到新模型。

## 座位接口（车辆根局部坐标）

```lua
local seatConfigs = {
  { id = "driver", label = "驾驶", anchorPath = "SeatAnchor_Driver", canDrive = true, fallbackPosition = Vector3(-0.128973, 0.297629, -0.125666) },
  { id = "front_passenger", label = "乘坐·副驾", anchorPath = "SeatAnchor_FrontPassenger", stationPath = "SeatStation_FrontPassenger", canDrive = false, fallbackPosition = Vector3(0.128973, 0.297629, -0.125666) },
}
```

## 轮胎接口（车辆根局部坐标）

```lua
local wheelConfigs = {
  { name = "LP26_Wheel_FL", radius = 0.284401, pivot = Vector3(-0.357155, 0.158735, 0.310857), visualScale = Vector3(0.305731003, 0.305731003, 0.305731003), parts = { "LP26_Wheel_FL_Part_01" } },
  { name = "LP26_Wheel_FR", radius = 0.284401, pivot = Vector3(0.357155, 0.158735, 0.310857), visualScale = Vector3(0.305731003, 0.305731003, 0.305731003), parts = { "LP26_Wheel_FR_Part_01" } },
  { name = "LP26_Wheel_RL", radius = 0.284401, pivot = Vector3(-0.357155, 0.158735, -0.300936), visualScale = Vector3(0.305731003, 0.305731003, 0.305731003), parts = { "LP26_Wheel_RL_Part_01" } },
  { name = "LP26_Wheel_RR", radius = 0.284401, pivot = Vector3(0.357155, 0.158735, -0.300936), visualScale = Vector3(0.305731003, 0.305731003, 0.305731003), parts = { "LP26_Wheel_RR_Part_01" } },
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
  "topSpeed": 31.5,
  "acceleration": 15.5,
  "braking": 19,
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
