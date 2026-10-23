# 牛粉：当前工程制作接口

根节点 ID：`1419667514`。根节点缩放：`{'x': 1.5, 'y': 1.5, 'z': 1.5}`。座位数：**2**。

车辆逻辑：[原有驾驶脚本](../../lua/modules/pi-nl01-niufen.lua)；绑定 ID：`0c552cb3-a257-49e9-9695-3f069a85e602`。
所有完整参数与布局见本目录 `vehicle.json`、`scene-nodes.json`。这些节点的 `pos/rot/scale` 来自编辑器序列化；不要把世界坐标直接当作子节点本地坐标。

## 实际引用的模型

- [A026 A026-NL01_NIULAI-fl-01-of-01.glb](../../models/catalog/A026-NL01_NIULAI-fl-01-of-01.glb)
- [A027 A027-NL01_NIULAI-fr-01-of-01.glb](../../models/catalog/A027-NL01_NIULAI-fr-01-of-01.glb)
- [A028 A028-NL01_NIULAI-rl-01-of-01.glb](../../models/catalog/A028-NL01_NIULAI-rl-01-of-01.glb)
- [A029 A029-NL01_NIULAI-rr-01-of-01.glb](../../models/catalog/A029-NL01_NIULAI-rr-01-of-01.glb)
- [A030 A030-09-niufen--niulai-counterpart-runtime-v1.glb](../../models/catalog/A030-09-niufen--niulai-counterpart-runtime-v1.glb)

这是当前保存场景实际引用的二进制资源，不根据旧交付文件名猜选。多个车辆可能共用同一套轮胎资源，不要重复导入多个相同轮胎实例。

## 材质匹配接口

| Renderer 节点名称 | 记录顶点数 | 子网格/材质槽 | 严格匹配顶点数 |
|---|---:|---:|---|
| 牛粉 | 17655 | 109 | True |
| NL01_NIULAI_Wheel_FL_Part_01 | 2377 | 27 | True |
| NL01_NIULAI_Wheel_FR_Part_01 | 2377 | 27 | True |
| NL01_NIULAI_Wheel_RL_Part_01 | 2377 | 27 | True |
| NL01_NIULAI_Wheel_RR_Part_01 | 2377 | 27 | True |

当前 mapping 的材质索引是从 1 开始的 Lua palette 索引。完整槽顺序见 `vehicle.json` 中 `materialIdentity.parts[].mats`，不是 GLB 全局 material 索引。升级拓扑后须重新采集并更新映射；不可把旧顶点数约束机械套用到新模型。

## 座位接口（车辆根局部坐标）

```lua
local seatConfigs = {
  { id = "driver", label = "驾驶", anchorPath = "SeatAnchor_Driver", canDrive = true, fallbackPosition = Vector3(-0.0979975, 0.216995, -0.125997) },
  { id = "front_passenger", label = "乘坐·副驾", anchorPath = "SeatAnchor_FrontPassenger", stationPath = "SeatStation_FrontPassenger", canDrive = false, fallbackPosition = Vector3(0.0979975, 0.216995, -0.125997) },
}
```

## 轮胎接口（车辆根局部坐标）

```lua
local wheelConfigs = {
  { name = "NL01_NIULAI_Wheel_FL", radius = 0.261327, pivot = Vector3(-0.333658, 0.130663, 0.331325), visualScale = Vector3(0.269189169, 0.269189169, 0.269189169), parts = { "NL01_NIULAI_Wheel_FL_Part_01" } },
  { name = "NL01_NIULAI_Wheel_FR", radius = 0.261327, pivot = Vector3(0.333658, 0.130663, 0.331325), visualScale = Vector3(0.269189169, 0.269189169, 0.269189169), parts = { "NL01_NIULAI_Wheel_FR_Part_01" } },
  { name = "NL01_NIULAI_Wheel_RL", radius = 0.303326, pivot = Vector3(-0.342991, 0.151663, -0.321992), visualScale = Vector3(0.310135119, 0.310135119, 0.310135119), parts = { "NL01_NIULAI_Wheel_RL_Part_01" } },
  { name = "NL01_NIULAI_Wheel_RR", radius = 0.303326, pivot = Vector3(0.342991, 0.151663, -0.321992), visualScale = Vector3(0.310135119, 0.310135119, 0.310135119), parts = { "NL01_NIULAI_Wheel_RR_Part_01" } },
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
  "topSpeed": 33,
  "acceleration": 15,
  "braking": 15,
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
