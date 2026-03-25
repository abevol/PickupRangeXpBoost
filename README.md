# PickupRangeXpBoost

根据玩家角色的 `Stat.PickupRange` 属性增加获取的经验值。

## 功能说明

- 监听经验值获取事件 `OnPlayerGainXP_Event`
- 根据当前 `PickupRange` 值相对于基础值的增幅，按比例增加经验值
- 公式：`经验值增幅 = (当前PickupRange - 360) / 360`

## 配置参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `BASE_PICKUP_RANGE` | 360 | PickupRange 基础值 |

## 示例

| PickupRange | 增幅 | 获取 10 XP 时的额外经验 |
|-------------|------|------------------------|
| 360 | 0% | 0 |
| 540 | 50% | 5 |
| 720 | 100% | 10 |
| 1080 | 200% | 20 |

## 控制台命令

| 命令 | 说明 |
|------|------|
| `xpboost_status` | 查看当前状态（PickupRange、增幅、待处理经验） |
| `xpboost_debug` | 开启/关闭调试日志 |
| `xpboost_set <值>` | 手动设置 PickupRange（测试用） |
| `xpboost_test <数量>` | 手动添加经验值到待处理队列 |

## 实现细节

1. **PickupRange 获取**：遍历 `UStatSystem.Stats` 数组，找到标签为 `Stat.PickupRange` 的 `FGameplayTag`，然后调用 `GetStatValueByTag` 获取当前值

2. **经验值增幅**：监听 `OnPlayerGainXP_Event` 事件，累积基础经验值，然后在后台任务中计算增幅并直接修改 `LevelComponent.AccumulatedXpOnCurrentLevel`

3. **事件监听**：
   - `OnPlayerGainXP_Event`：累积经验值
   - `HandlePickupRangeChanged_`：实时更新 PickupRange 值

## 文件结构

```
PickupRangeXpBoost/
└── Scripts/
    └── main.lua    # 主脚本
```

## 依赖

- UE4SS
- UEHelpers（UE4SS 内置）
