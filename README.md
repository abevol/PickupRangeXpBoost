[English](README.md) | [中文](README_zh.md)

# PickupRangeXpBoost

This is a UE4SS-based Lua mod that implements an experience point (XP) boost feature for the UE5 game "Grind Survivors". The mod proportionally increases the XP gained based on the player character's pickup range attribute multiplier.

## Installation

1. Ensure [UE4SS](https://docs.ue4ss.com/) is installed.
2. Copy the `PickupRangeXpBoost` folder to the `GrindSurvivors/Binaries/Win64/ue4ss/Mods/` directory.
3. Launch the game, and the mod will take effect automatically.

## Features

- Increases XP proportionally based on the current `Stat.PickupRange` relative to the base value (360).
- Formula: `Bonus XP = Base XP × (Current Stat.PickupRange - 360) / 360`
- Calculates and grants bonus XP in batches every 500ms.
- Displays the current boost percentage and bonus XP in real-time at the top of the screen, with colors changing according to the boost level.

## Boost Examples

| PickupRange | Boost | Bonus XP when gaining 10 XP |
|-------------|-------|-----------------------------|
| 360 | 0% | 0 |
| 540 | 50% | 5 |
| 720 | 100% | 10 |
| 1080 | 200% | 20 |

## Console Commands

Enter the following commands in the UE4SS console:

| Command | Description |
|---------|-------------|
| `xpboost_status` | View current status (PickupRange, boost percentage, pending XP) |
| `xpboost_debug` | Toggle debug logging |
| `xpboost_set <value>` | Manually set PickupRange (for testing) |
| `xpboost_test <amount>` | Manually add XP to the pending queue (default 10) |
| `xpboost_ui` | Toggle on-screen boost display |

## How It Works

1. Every time the game grants XP, the mod first accumulates the base XP value.
2. A background timer checks the accumulated value every 500ms, calculates the bonus XP, and grants it all at once.
3. The PickupRange value is synchronized in real-time via game events and is also actively queried at the start of each level.

## Configuration

Modify the constants at the top of `Scripts/main.lua`:

| Parameter | Default Value | Description |
|-----------|---------------|-------------|
| `BASE_PICKUP_RANGE` | 360 | Base PickupRange value; values below this will not generate a bonus. |
| `DEBUG_MODE` | false | Debug log toggle, can also be switched via the `xpboost_debug` command. |
