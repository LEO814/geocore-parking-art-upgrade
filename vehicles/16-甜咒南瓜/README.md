# 甜咒南瓜：当前工程制作接口

根节点 ID：`-1523312224`。根节点缩放：`{'x': 1.68, 'y': 1.68, 'z': 1.68}`。座位数：**2**。

车辆逻辑：[原有驾驶脚本](../../lua/modules/pi-c02-candy-hex.lua)；绑定 ID：`1a1f1fbf-d1d3-4999-81c5-3aa3ed3269b0`。
所有完整参数与布局见本目录 `vehicle.json`、`scene-nodes.json`。这些节点的 `pos/rot/scale` 来自编辑器序列化；不要把世界坐标直接当作子节点本地坐标。

## 实际引用的模型

- [A063 A063-C02-tandem-runtime.glb](../../models/catalog/A063-C02-tandem-runtime.glb)
- [A064 A064-C02_FullPumpkinBody_Final.glb](../../models/catalog/A064-C02_FullPumpkinBody_Final.glb)

这是当前保存场景实际引用的二进制资源，不根据旧交付文件名猜选。多个车辆可能共用同一套轮胎资源，不要重复导入多个相同轮胎实例。

## 材质匹配接口

| Renderer 节点名称 | 记录顶点数 | 子网格/材质槽 | 严格匹配顶点数 |
|---|---:|---:|---|
| Body | 14823 | 9 | False |
| Wheel_FL | 2289 | 3 | False |
| Wheel_FR | 2289 | 3 | False |
| Wheel_RL | 2289 | 3 | False |
| Wheel_RR | 2289 | 3 | False |

当前 mapping 的材质索引是从 1 开始的 Lua palette 索引。完整槽顺序见 `vehicle.json` 中 `materialIdentity.parts[].mats`，不是 GLB 全局 material 索引。升级拓扑后须重新采集并更新映射；不可把旧顶点数约束机械套用到新模型。

## 座位接口（车辆根局部坐标）

```lua
local seatConfigs = {
  { id = "driver", label = "驾驶·前座", anchorPath = "Seat_Driver", canDrive = true, fallbackPosition = Vector3(0, 0.161112035826, 0.102861940596) },
  { id = "front_passenger", label = "乘坐·后座", anchorPath = "Seat_Passenger", stationPath = "SeatStation_FrontPassenger", canDrive = false, fallbackPosition = Vector3(0, 0.168169479763, -0.299538255509) },
}
```

## 轮胎接口（车辆根局部坐标）

```lua
local wheelConfigs = {
  { name = "C02_WheelPivot_FL", radius = 0.177, pivot = Vector3(0.233928571429, 0.105357142857, 0.269642857143), visualScale = Vector3.one, parts = { "Wheel_FL" } },
  { name = "C02_WheelPivot_FR", radius = 0.177, pivot = Vector3(-0.233928571429, 0.105357142857, 0.269642857143), visualScale = Vector3.one, parts = { "Wheel_FR" } },
  { name = "C02_WheelPivot_RL", radius = 0.189, pivot = Vector3(0.230357142857, 0.1125, -0.269642857143), visualScale = Vector3.one, parts = { "Wheel_RL" } },
  { name = "C02_WheelPivot_RR", radius = 0.189, pivot = Vector3(-0.230357142857, 0.1125, -0.269642857143), visualScale = Vector3.one, parts = { "Wheel_RR" } },
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
  "topSpeed": 30,
  "acceleration": 20,
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
