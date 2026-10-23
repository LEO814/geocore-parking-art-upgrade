# 烈焰：当前工程制作接口

根节点 ID：`-1911095155`。根节点缩放：`{'x': 0.9, 'y': 0.9, 'z': 0.9}`。座位数：**2**。

车辆逻辑：[原有驾驶脚本](../../lua/modules/pi-flame-kart.lua)；绑定 ID：`a617d090-9f38-484d-aae2-38cd1bc67d71`。
所有完整参数与布局见本目录 `vehicle.json`、`scene-nodes.json`。这些节点的 `pos/rot/scale` 来自编辑器序列化；不要把世界坐标直接当作子节点本地坐标。

## 实际引用的模型

- [A031 A031-FLAME_KART_Body_Part_01_0907_2f6c6256.glb](../../models/catalog/A031-FLAME_KART_Body_Part_01_0907_2f6c6256.glb)
- [A032 A032-FLAME_KART_Wheel_FL_Part_01_0907_515c23fe.glb](../../models/catalog/A032-FLAME_KART_Wheel_FL_Part_01_0907_515c23fe.glb)
- [A033 A033-FLAME_KART_Wheel_FR_Part_01_0907_b156626b.glb](../../models/catalog/A033-FLAME_KART_Wheel_FR_Part_01_0907_b156626b.glb)
- [A034 A034-FLAME_KART_Wheel_RL_Part_01_0907_ffe06f13.glb](../../models/catalog/A034-FLAME_KART_Wheel_RL_Part_01_0907_ffe06f13.glb)
- [A035 A035-FLAME_KART_Wheel_RR_Part_01_0907_715df9d8.glb](../../models/catalog/A035-FLAME_KART_Wheel_RR_Part_01_0907_715df9d8.glb)

这是当前保存场景实际引用的二进制资源，不根据旧交付文件名猜选。多个车辆可能共用同一套轮胎资源，不要重复导入多个相同轮胎实例。

## 材质匹配接口

| Renderer 节点名称 | 记录顶点数 | 子网格/材质槽 | 严格匹配顶点数 |
|---|---:|---:|---|
| 烈焰 | 16967 | 17 | True |
| FLAME_KART_Wheel_FL_Part_01 | 8848 | 5 | True |
| FLAME_KART_Wheel_FR_Part_01 | 8848 | 5 | True |
| FLAME_KART_Wheel_RL_Part_01 | 8854 | 5 | True |
| FLAME_KART_Wheel_RR_Part_01 | 8854 | 5 | True |

当前 mapping 的材质索引是从 1 开始的 Lua palette 索引。完整槽顺序见 `vehicle.json` 中 `materialIdentity.parts[].mats`，不是 GLB 全局 material 索引。升级拓扑后须重新采集并更新映射；不可把旧顶点数约束机械套用到新模型。

## 座位接口（车辆根局部坐标）

```lua
local seatConfigs = {
  { id = "driver", label = "驾驶", anchorPath = "SeatAnchor_Driver", canDrive = true, fallbackPosition = Vector3(-0.24, 0.268, -0.19) },
  { id = "front_passenger", label = "乘坐·副驾", anchorPath = "SeatAnchor_FrontPassenger", stationPath = "SeatStation_FrontPassenger", canDrive = false, fallbackPosition = Vector3(0.24, 0.268, -0.19) },
}
```

## 轮胎接口（车辆根局部坐标）

```lua
local wheelConfigs = {
  { name = "FLAME_KART_Wheel_FL", radius = 0.4, pivot = Vector3(-0.54, 0.2, 0.53), visualScale = Vector3(1, 1, 1), parts = { "FLAME_KART_Wheel_FL_Part_01" } },
  { name = "FLAME_KART_Wheel_FR", radius = 0.4, pivot = Vector3(0.54, 0.2, 0.53), visualScale = Vector3(1, 1, 1), parts = { "FLAME_KART_Wheel_FR_Part_01" } },
  { name = "FLAME_KART_Wheel_RL", radius = 0.44, pivot = Vector3(-0.565, 0.22, -0.54), visualScale = Vector3(1, 1, 1), parts = { "FLAME_KART_Wheel_RL_Part_01" } },
  { name = "FLAME_KART_Wheel_RR", radius = 0.44, pivot = Vector3(0.565, 0.22, -0.54), visualScale = Vector3(1, 1, 1), parts = { "FLAME_KART_Wheel_RR_Part_01" } },
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
  "braking": 34,
  "turnSpeed": 82,
  "grip": 0.97,
  "cameraFollowEnabled": true,
  "reverseSpeed": 7,
  "coastingDrag": 6,
  "sidewaysFriction": 14,
  "cameraAlignSpeed": 120,
  "cameraAlignGrace": 0.45,
  "raceSessionStageSnapshot": ""
}
```
