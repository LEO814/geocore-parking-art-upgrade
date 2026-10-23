# 赤巡：当前工程制作接口

根节点 ID：`433861336`。根节点缩放：`{'x': 0.6, 'y': 0.6, 'z': 0.6}`。座位数：**2**。

车辆逻辑：[原有驾驶脚本](../../lua/modules/pi-flame-motorcycle.lua)；绑定 ID：`ce1504dd-0a40-4a70-87e3-c8175dc6e9f2`。
所有完整参数与布局见本目录 `vehicle.json`、`scene-nodes.json`。这些节点的 `pos/rot/scale` 来自编辑器序列化；不要把世界坐标直接当作子节点本地坐标。

## 实际引用的模型

- [A036 A036-FLAME_MOTO_Body_Part_01_0907_7d2c6119.glb](../../models/catalog/A036-FLAME_MOTO_Body_Part_01_0907_7d2c6119.glb)
- [A037 A037-FLAME_MOTO_Wheel_F_Part_01_0907_1f6faeb8.glb](../../models/catalog/A037-FLAME_MOTO_Wheel_F_Part_01_0907_1f6faeb8.glb)
- [A038 A038-FLAME_MOTO_Wheel_R_Part_01_0907_f925e2d8.glb](../../models/catalog/A038-FLAME_MOTO_Wheel_R_Part_01_0907_f925e2d8.glb)

这是当前保存场景实际引用的二进制资源，不根据旧交付文件名猜选。多个车辆可能共用同一套轮胎资源，不要重复导入多个相同轮胎实例。

## 材质匹配接口

| Renderer 节点名称 | 记录顶点数 | 子网格/材质槽 | 严格匹配顶点数 |
|---|---:|---:|---|
| 赤巡 | 11768 | 17 | True |
| FLAME_MOTO_Wheel_F_Part_01 | 9016 | 5 | True |
| FLAME_MOTO_Wheel_R_Part_01 | 9016 | 5 | True |

当前 mapping 的材质索引是从 1 开始的 Lua palette 索引。完整槽顺序见 `vehicle.json` 中 `materialIdentity.parts[].mats`，不是 GLB 全局 material 索引。升级拓扑后须重新采集并更新映射；不可把旧顶点数约束机械套用到新模型。

## 座位接口（车辆根局部坐标）

```lua
local seatConfigs = {
  { id = "driver", label = "驾驶", anchorPath = "SeatAnchor_Driver", canDrive = true, fallbackPosition = Vector3(0, 0.5742, -0.0723557) },
  { id = "front_passenger", label = "乘坐·后座", anchorPath = "SeatAnchor_FrontPassenger", stationPath = "SeatStation_FrontPassenger", canDrive = false, fallbackPosition = Vector3(0, 0.7076, -0.426156) },
}
```

## 轮胎接口（车辆根局部坐标）

```lua
local wheelConfigs = {
  { name = "FLAME_MOTO_Wheel_F", radius = 0.5568, pivot = Vector3(0, 0.2784, 0.623644), visualScale = Vector3(1, 1, 1), parts = { "FLAME_MOTO_Wheel_F_Part_01" } },
  { name = "FLAME_MOTO_Wheel_R", radius = 0.5916, pivot = Vector3(0, 0.2958, -0.559556), visualScale = Vector3(1, 1, 1), parts = { "FLAME_MOTO_Wheel_R_Part_01" } },
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
  "topSpeed": 32,
  "acceleration": 23,
  "braking": 28,
  "turnSpeed": 66,
  "grip": 0.91,
  "cameraFollowEnabled": true,
  "reverseSpeed": 4,
  "coastingDrag": 4,
  "sidewaysFriction": 10,
  "cameraAlignSpeed": 120,
  "cameraAlignGrace": 0.45,
  "raceSessionStageSnapshot": ""
}
```
