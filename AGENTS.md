# AGENTS.md - PickupRangeXpBoost

## 项目概述

这是一个基于 UE4SS 的 Lua 模组，为 UE5 游戏 "Grind Survivors" 实现经验值增益功能。模组根据玩家角色的 `Stat.PickupRange` 属性值相对于基础值的增幅，按比例增加获取的经验值。

## 技术栈

- **框架**: UE4SS (Unreal Engine Scripting System)
- **语言**: Lua 5.4
- **目标游戏**: Grind Survivors (UE5)
- **依赖**: UEHelpers（UE4SS 内置模块）

## 核心架构

### 关键组件

| 组件 | 类型 | 用途 |
|------|------|------|
| `UStatSystem` | `UGameInstanceSubsystem` | 游戏属性系统，管理所有 Stat |
| `ULevelComponent` | `UActorComponent` | 角色等级组件，存储经验值 |
| `FGameplayTag` | 结构体 | UE GameplayTag 系统的标签 |
| `UGameplayStat` | `UObject` | 单个属性的数据容器 |
| `UUserWidget` | UMG Widget | XP 增益显示的根容器 |
| `UTextBlock` | UMG Widget | 显示增益百分比和额外经验值的文本 |

### 数据流

```
OnPlayerGainXP_Event → accumulatedBaseXP += xp
                              ↓
                       LoopAsync(500ms) → GiveBonusXP()
                              ↓
                       计算增幅 → LevelComponent.AccumulatedXpOnCurrentLevel += bonusXP
                              ↑
                       currentPickupRange ← 两个来源：
                         1. HandlePickupRangeChanged_ 事件（实时）
                         2. UpdatePickupRange() → StatSystem:GetStatValueByTag()（初始化时）
```

### 运行机制

- **XP 累积**: `OnPlayerGainXP_Event` 触发时仅累积到 `accumulatedBaseXP`，不立即计算
- **批量处理**: `LoopAsync` 每 500ms 执行一次 `GiveBonusXP()`，批量处理累积的 XP
- **关卡重置**: `OnGameLevelStarted` 时重置 `levelComponent`（防止残留失效引用）并重新初始化
- **双通道同步**: PickupRange 值通过事件实时更新 + 初始化时主动查询，确保不遗漏
- **HUD 显示**: `OnGameLevelStarted` 延迟 2s 后通过 `StaticConstructObject` 创建 UMG widget 链（UserWidget → WidgetTree → CanvasPanel → Border → TextBlock），锚定在屏幕顶部居中偏下（Y=55），每次 `GiveBonusXP` 或 `HandlePickupRangeChanged_` 后实时更新文本和颜色

## 关键 API 用法

### 1. 获取 StatSystem 实例

```lua
local statSystem = FindFirstOf("StatSystem")
```

- `StatSystem` 是 `UGameInstanceSubsystem`，游戏启动后自动存在
- 使用 `FindFirstOf` 按类名查找实例

### 2. 遍历 Stats 数组获取 FGameplayTag

```lua
local stats = statSystem.Stats  -- TArray<UGameplayStat>
for i = 1, #stats do
    local stat = stats[i]
    local tag = stat.Tag  -- FGameplayTag
    local tagName = tag.TagName:ToString()  -- "Stat.PickupRange"
end
```

**重要**: `FGameplayTag` 必须从现有对象获取，无法通过字符串直接创建。这是 UE4SS 的限制。

### 3. 获取属性值

```lua
local value = statSystem:GetStatValueByTag(pickupRangeTag)
```

- 参数必须是 `FGameplayTag` 类型，不能是 `FName` 或字符串
- 返回值是 `float`

### 4. 修改经验值

```lua
levelComponent.AccumulatedXpOnCurrentLevel = newXP
```

- 直接赋值即可修改
- 需要先获取 `LevelComponent` 实例

## UE4SS 事件系统

### RegisterCustomEvent

注册蓝图自定义事件的回调：

```lua
RegisterCustomEvent("事件名", function(ContextParam, 参数1, 参数2, ...)
    -- 参数使用 :get() 获取实际值
    local actualValue = 参数1:get()
end)
```

### 常用事件

| 事件 | 来源 | 参数 |
|------|------|------|
| `OnGameLevelStarted` | `AGSGameMode` | 无 |
| `HandlePickupRangeChanged_` | `BP_PlayerCharacterEffects_C` | StatTag, PrevValue, NewValue |
| `OnPlayerGainXP_Event` | `BP_PlayerCharacterEffects_C` | XPAmount |

## 修改指南

### 添加新属性增益

1. 修改 `FindPickupRangeTag()` 中的标签名称
2. 更新 `BASE_PICKUP_RANGE` 常量
3. 调整 `GiveBonusXP()` 中的增幅公式

### 修改增幅公式

当前公式位于 `GiveBonusXP()`:

```lua
local multiplier = (currentPickupRange - BASE_PICKUP_RANGE) / BASE_PICKUP_RANGE
local bonusXP = math.floor(baseXP * multiplier + 0.5)
```

### 添加新的事件监听

```lua
RegisterCustomEvent("新事件名", function(ContextParam, ...)
    -- 处理逻辑
end)
```

## 调试方法

### 1. 控制台命令

| 命令 | 功能 |
|------|------|
| `xpboost_status` | 查看当前状态 |
| `xpboost_debug` | 开关调试日志 |
| `xpboost_set <值>` | 手动设置 PickupRange |
| `xpboost_test <数量>` | 添加测试经验值 |
| `xpboost_ui` | 开关 HUD 增益显示 |

### 2. 日志系统

```lua
Log("消息")        -- 始终输出
DebugLog("消息")   -- 仅在 DEBUG_MODE=true 时输出
```

日志格式: `[PickupRangeXpBoost] 消息`

### 3. 常见问题排查

| 问题 | 排查方法 |
|------|----------|
| 属性值为 0 | 检查 `pickupRangeTag` 是否正确获取 |
| 经验值未增加 | 检查 `levelComponent` 是否有效 |
| 事件未触发 | 确认事件名称拼写正确 |
| HUD 不显示 | 检查 `xpBoostWidget` 是否创建成功，确认 `uiEnabled` 为 true |

## 代码规范

1. **错误处理 (`pcall` 使用原则)**:
   - **不要**用 `pcall` 包装普通的 UE 对象属性访问和方法调用——用 `nil` 检查 + `IsValid()` 即可
   - **仅在调度边界**使用 `pcall`：如 `LoopAsync`、`ExecuteWithDelay`、`ExecuteInGameThread` 等回调入口，防止未捕获异常杀死循环或破坏线程状态
   - `pcall` 捕获的错误**必须记录日志**，禁止静默吞掉：`local ok, err = pcall(fn); if not ok then Log(err) end`
   - 判断标准：「如果这里抛异常，是否会导致不可恢复的后果（如定时器停止）？」——是则 `pcall`，否则让错误自然暴露
2. **空值检查**: 在使用对象前调用 `IsValid()` 验证
3. **类型检查**: 使用 `type(value) == "number"` 确认返回类型
4. **日志前缀**: 所有日志使用 `[PickupRangeXpBoost]` 前缀
5. **关卡切换状态重置 (`ResetLevelState`)**: 在关卡切换时，上一关卡的 UE 对象或结构体可能会被垃圾回收 (GC)。任何未清除的缓存引用都会变成悬空指针。**规则**：每个持有 UE 对象、结构体或从中派生值的变量，**必须**在关卡切换时（`ResetLevelState()` 函数中）被重置为 `nil` 或初始值。新增的缓存引用也必须添加到该重置列表中。

## 文件结构

```
PickupRangeXpBoost/
├── AGENTS.md           # 本文档
├── README.md           # 用户文档
├── Scripts/
│   └── main.lua        # 主脚本
└── .git/               # Git 仓库
```

## 参考资源

- UE4SS 文档: https://docs.ue4ss.com/
- UE5 GameplayTag 文档: https://docs.unrealengine.com/5.0/en-US/gameplay-tags-in-unreal-engine/
- GrindSurvivors 类型定义: `Mods/shared/types/GrindSurvivors.lua`
