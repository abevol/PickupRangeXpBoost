# PickupRangeXpBoost

根据玩家角色的 `Stat.PickupRange` 属性增幅，按比例增加获取的经验值。拾取范围越大，经验加成越高。

## 安装

1. 确保已安装 [UE4SS](https://docs.ue4ss.com/)
2. 将 `PickupRangeXpBoost` 文件夹复制到 `GrindSurvivors/Binaries/Win64/ue4ss/Mods/` 目录下
3. 启动游戏，模组自动生效

## 兼容性

- **游戏**: Grind Survivors
- **框架**: UE4SS
- **依赖**: 无外部依赖

## 功能说明

- 自动监听经验值获取事件，无需手动操作
- 根据当前 `PickupRange` 相对基础值 (360) 的增幅，按比例增加经验值
- 公式：`额外经验 = 基础经验 × (当前PickupRange - 360) / 360`
- 每 500ms 批量结算一次额外经验

## 增幅示例

| PickupRange | 增幅 | 获取 10 XP 时的额外经验 |
|-------------|------|------------------------|
| 360 | 0% | 0 |
| 540 | 50% | 5 |
| 720 | 100% | 10 |
| 1080 | 200% | 20 |

## 控制台命令

在 UE4SS 控制台中输入以下命令：

| 命令 | 说明 |
|------|------|
| `xpboost_status` | 查看当前状态（PickupRange、增幅百分比、待处理经验） |
| `xpboost_debug` | 开启/关闭调试日志 |
| `xpboost_set <值>` | 手动设置 PickupRange（测试用） |
| `xpboost_test <数量>` | 手动添加经验值到待处理队列（默认 10） |

## 工作原理

1. 游戏每次给予经验时，模组先累积基础经验值
2. 后台定时器每 500ms 检查一次累积值，计算额外经验并一次性发放
3. PickupRange 值通过游戏事件实时同步，也在每关开始时主动查询

## 配置

修改 `Scripts/main.lua` 顶部的常量：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `BASE_PICKUP_RANGE` | 360 | PickupRange 基础值，低于此值不产生加成 |
| `DEBUG_MODE` | false | 调试日志开关，也可通过 `xpboost_debug` 命令切换 |
