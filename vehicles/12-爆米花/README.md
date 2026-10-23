# 爆米花：当前工程制作接口

根节点 ID：`1621264168`。根节点缩放：`{'x': 1.0, 'y': 1.0, 'z': 1.0}`。座位数：**2**。

车辆逻辑：[原有驾驶脚本](../../lua/modules/pi-lp39-racerpop.lua)；绑定 ID：`0b177841-8cba-4955-ba76-6f773828be1c`。
所有完整参数与布局见本目录 `vehicle.json`、`scene-nodes.json`。这些节点的 `pos/rot/scale` 来自编辑器序列化；不要把世界坐标直接当作子节点本地坐标。

## 实际引用的模型

- [A009 A009-LP39_RACERPOP-fl-01-of-01.glb](../../models/catalog/A009-LP39_RACERPOP-fl-01-of-01.glb)
- [A010 A010-LP39_RACERPOP-fr-01-of-01.glb](../../models/catalog/A010-LP39_RACERPOP-fr-01-of-01.glb)
- [A011 A011-LP39_RACERPOP-rl-01-of-01.glb](../../models/catalog/A011-LP39_RACERPOP-rl-01-of-01.glb)
- [A012 A012-LP39_RACERPOP-rr-01-of-01.glb](../../models/catalog/A012-LP39_RACERPOP-rr-01-of-01.glb)
- [A052 A052-14-racerpop-original-materials-taken-actor-runtime-v2.glb](../../models/catalog/A052-14-racerpop-original-materials-taken-actor-runtime-v2.glb)

这是当前保存场景实际引用的二进制资源，不根据旧交付文件名猜选。多个车辆可能共用同一套轮胎资源，不要重复导入多个相同轮胎实例。

## 材质匹配接口

| Renderer 节点名称 | 记录顶点数 | 子网格/材质槽 | 严格匹配顶点数 |
|---|---:|---:|---|
| 爆米花 | 9996 | 40 | True |
| LP39_RACERPOP_Wheel_FL_Part_01 | 1211 | 8 | True |
| LP39_RACERPOP_Wheel_FR_Part_01 | 1211 | 8 | True |
| LP39_RACERPOP_Wheel_RL_Part_01 | 1211 | 8 | True |
| LP39_RACERPOP_Wheel_RR_Part_01 | 1211 | 8 | True |

当前 mapping 的材质索引是从 1 开始的 Lua palette 索引。完整槽顺序见 `vehicle.json` 中 `materialIdentity.parts[].mats`，不是 GLB 全局 material 索引。升级拓扑后须重新采集并更新映射；不可把旧顶点数约束机械套用到新模型。

## 座位接口（车辆根局部坐标）

```lua
local seatConfigs = {
  { id = "driver", label = "驾驶·左", anchorPath = "SeatAnchor_Driver", canDrive = true, fallbackPosition = Vector3(-0.104981313917, 0.349937713057, -0.0233291808705) },
  { id = "front_passenger", label = "乘坐·右", anchorPath = "SeatAnchor_FrontPassenger", stationPath = "SeatStation_FrontPassenger", canDrive = false, fallbackPosition = Vector3(0.104981313917, 0.349937713057, -0.0233291808705) },
}
```

## 轮胎接口（车辆根局部坐标）

```lua
local wheelConfigs = {
  { name = "LP39_Wheel_FL", radius = 0.189549594573, pivot = Vector3(-0.344105417839, 0.189549594573, 0.26828558001), visualScale = Vector3(0.37909917524, 0.37909917524, 0.37909917524), parts = { "LP39_RACERPOP_Wheel_FL_Part_01" } },
  { name = "LP39_Wheel_FR", radius = 0.189549594573, pivot = Vector3(0.344105417839, 0.189549594573, 0.26828558001), visualScale = Vector3(0.37909917524, 0.37909917524, 0.37909917524), parts = { "LP39_RACERPOP_Wheel_FR_Part_01" } },
  { name = "LP39_Wheel_RL", radius = 0.189549594573, pivot = Vector3(-0.344105417839, 0.189549594573, -0.26828558001), visualScale = Vector3(0.37909917524, 0.37909917524, 0.37909917524), parts = { "LP39_RACERPOP_Wheel_RL_Part_01" } },
  { name = "LP39_Wheel_RR", radius = 0.189549594573, pivot = Vector3(0.344105417839, 0.189549594573, -0.26828558001), visualScale = Vector3(0.37909917524, 0.37909917524, 0.37909917524), parts = { "LP39_RACERPOP_Wheel_RR_Part_01" } },
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
  "topSpeed": 30.5,
  "acceleration": 21,
  "braking": 29,
  "turnSpeed": 72,
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
