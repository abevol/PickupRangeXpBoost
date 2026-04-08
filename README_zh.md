[English](README.md) | [中文](README_zh.md)

# PickupRangeXpBoost

这是一个基于 UE4SS 的 Lua 模组，为 UE5 游戏《无尽猎杀》（Grind Survivors）实现经验值增益功能。模组根据玩家角色的拾取范围属性增幅，按可配置的转换比率增加获取的经验值。

<video src="https://github.com/user-attachments/assets/6aa82a44-e04b-452c-ab9b-fd984371efcb" controls="controls" width="100%" autoplay="autoplay" muted="muted" loop="loop"></video>

## 安装

### 自动安装（推荐）

1. 下载模组的 [最新源码](https://github.com/abevol/PickupRangeXpBoost/archive/refs/heads/master.zip) 并解压。
2. 双击模组文件夹中的 `install.cmd`。
3. 按照提示选择你的游戏目录（通常为 `Grind Survivors/GrindSurvivors/Binaries/Win64/`）。
4. 脚本将自动下载并安装 **UE4SS 模组框架** 并配置好本模组。

### 手动安装

1. 确保已安装 [UE4SS](https://api.github.com/repos/UE4SS-RE/RE-UE4SS/releases/tags/experimental-latest) (**experimental-latest** 版本)。
2. 将 `PickupRangeXpBoost` 文件夹复制到 `Grind Survivors/GrindSurvivors/Binaries/Win64/ue4ss/Mods/` 目录下。
3. 在 `Grind Survivors/GrindSurvivors/Binaries/Win64/ue4ss/Mods/mods.txt` 文件中添加以下一行内容：
   ```text
   PickupRangeXpBoost : 1
   ```
4. 启动游戏。

## 验证安装

安装完成后，你可以按照以下步骤验证：
1. 启动游戏并进入任一关卡。
2. 观察屏幕顶部，经验条中间位置若出现增益标签（如 "EXP + 70% (+3)"），则说明模组已成功生效。

## 功能说明

- 根据当前 `Stat.PickupRange` 相对基础值 (360) 的增幅，按可配置转换比率换算为额外经验
- 公式：`额外经验 = 基础经验 × (当前 Stat.PickupRange - 360) / 360 × XP_CONVERSION_RATE`
- 默认转换比率：`XP_CONVERSION_RATE = 1.0`
- 每 500ms 批量结算一次额外经验
- 屏幕顶部实时显示当前增益百分比和额外经验值，颜色随增益等级变化

## 增幅示例

以下示例基于默认 `XP_CONVERSION_RATE = 1.0`。

| PickupRange | 经验增幅 | 获取 10 XP 时的额外经验 |
|-------------|----------|------------------------|
| 360 | 0% | 0 |
| 540 | 50% | 5 |
| 720 | 100% | 10 |
| 1080 | 200% | 20 |

如果将 `XP_CONVERSION_RATE` 设为 `0.5`，同样的数值会分别变成 0、2.5、5、10 点额外经验；如果设为 `2.0`，则会变成 0、10、20、40。

## 控制台命令

在 UE4SS 控制台中输入以下命令：

| 命令 | 说明 |
|------|------|
| `xpboost_status` | 查看当前状态（PickupRange、拾取范围增幅、转换比率、经验增幅、待处理经验） |
| `xpboost_debug` | 开启/关闭调试日志 |
| `xpboost_ratio <值>` | 设置经验转换比率（`0` 表示关闭额外经验，`1` 表示保持原始行为） |
| `xpboost_set <值>` | 手动设置 PickupRange（测试用） |
| `xpboost_test <数量>` | 手动添加经验值到待处理队列（默认 10） |
| `xpboost_ui` | 开启/关闭屏幕增益显示 |

## 工作原理

1. 游戏每次给予经验时，模组先累积基础经验值
2. 后台定时器每 500ms 检查一次累积值，计算额外经验并一次性发放
3. PickupRange 值通过游戏事件实时同步，也在每关开始时主动查询

## 配置

修改 `Scripts/main.lua` 顶部的常量：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `BASE_PICKUP_RANGE` | 360 | PickupRange 基础值，低于此值不产生加成 |
| `XP_CONVERSION_RATE` | 1.0 | 将拾取范围增幅转换为经验增幅的比率，也可在游戏中通过 `xpboost_ratio` 修改 |
| `DEBUG_MODE` | false | 调试日志开关，也可通过 `xpboost_debug` 命令切换 |
