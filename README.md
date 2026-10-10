# Blue-A｜自走棋原型 · 中文源码说明

[![Source checks](https://github.com/tangjiabao666/Blue-Archive-Auto-Chess/actions/workflows/source-checks.yml/badge.svg)](https://github.com/tangjiabao666/Blue-Archive-Auto-Chess/actions/workflows/source-checks.yml)

基于 **Godot 4.6.3 Standard** 的自走棋与实时战术原型。准备阶段招募、合成和布阵；战斗阶段自动普攻、自动基础技能，玩家实时选择 EX 与战术移动；六轮后按积分排名。

> **这是程序源码公开版，不是完整游戏发行包。** 原作模型、动画、纹理、肖像、音频及其提取配置没有随仓库提供；部分资源派生的生成代码也不公开。克隆后不能直接运行完整游戏、观看完整角色效果或导出可玩安装包。仓库没有资源下载器，也没有“只放一个原版客户端就自动补齐全部输入”的工具。

项目地址：[tangjiabao666/Blue-Archive-Auto-Chess](https://github.com/tangjiabao666/Blue-Archive-Auto-Chess)

## 项目现在做到了什么

- 单人：1 位玩家与 7 位 AI，八人六轮积分赛，当前新游戏每方最多上阵 5 人。
- 经济：五格招募、刷新、经验与人口、备战席、三张同名一星合成二星、商店保留、阶段增援。
- 战术：二星解锁手动 EX，共享能量；自动普攻和基础技能；有限次数的实时走位；障碍物、射线与地形参与判定。
- 地图：开放广场、双路街道、交错掩体三个战术预设，按种子和回合轮换。
- 局域网：固定 **3 真人 + 5 AI**，房主权威模拟；非房主掉线由 AI 接管，房主离开则结束房间。
- 界面与本地状态：主菜单、战报、存档/继续、音量与画质设置、桌面输入及移动端手势代码。
- 工程：分离的规则/模拟/展示代码，Godot 和 Python 测试，固定版本的 Windows 与 Android 私有构建工具。

当前活动名单在 `core/game_session.gd` 的 `ACTIVE` 中，共 **14 位**：白子、星野、日奈、阿露、优香、爱丽丝、芹香、伊织、椿、野宫、睦月、晴奈、小春、明日奈。名单存在不代表本仓库提供这些角色的资源。

## 从这里开始

| 你想做什么 | 阅读入口 |
| --- | --- |
| 看当前玩法、操作与胜负规则 | [玩法和操作](docs/GAMEPLAY.zh-CN.md) |
| 准备合法本地资源、启动工程 | [资源导入与运行](docs/ASSET_IMPORT.zh-CN.md) |
| 理解入口、目录与模块边界 | [架构导览](docs/ARCHITECTURE.zh-CN.md) |
| 运行无需原作资源的检查 | [测试、状态与已知限制](docs/VALIDATION.zh-CN.md) |
| 构建 Windows x86_64 私有候选包 | [Windows 构建说明](tools/windows_release/README.md) |
| 构建 Android ARM64 私有测试 APK | [Android 构建说明](tools/android_release/README.md) |
| 修改代码、提交问题或补丁 | [贡献与权利边界](docs/CONTRIBUTING.zh-CN.md) |

## 环境与启动概览

- Godot **4.6.3 Standard**，开发验证版本 `4.6.3.stable.official.7d41c59c4`；没有 C#/.NET 工程依赖。
- `project.godot` 入口是 `game.tscn`，默认 GL Compatibility，逻辑界面 1280×900。
- Python 工具建议 Python 3.11+；发布流水线还需要 Git、匹配导出模板及目标平台工具链。
- 以下命令**仅在补齐匹配、合法的本地资源后**使用，路径占位符须替换为本机路径。

```sh
# Linux / Bash；脚本不要求已有可执行权限
GODOT_BIN=/absolute/path/to/godot bash ./run-prototype.sh
```

```bat
rem Windows cmd.exe
set "GODOT_EXE=C:\Tools\Godot\Godot_v4.6.3-stable_win64_console.exe"
run-prototype.cmd
```

脚本先检查关键输入和 Godot 4.6.3 stable 版本，再导入资源并启动。缺少资源时会提示具体路径和导入文档；检查仅覆盖关键入口，不代表所有资源已齐全。Windows 可用项目旁的 `Godot.exe` 或 PATH 中的 `godot`，也可通过 `GODOT_EXE` 明确指定引擎。导入失败会停止启动并保留退出码。

公开仓库的 GitHub Actions 自动运行源码范围、Python 语法、合成输入工具测试、启动脚本和不依赖角色资源的 Godot 规则测试。完整游戏、原作资源与发布包验证仍需本地完整工程，详见[测试说明](docs/VALIDATION.zh-CN.md)。

## 性能与验证：目前不能承诺什么

桌面缺省帧率上限为 60；已有用户明确保存的设置会保留。近期代码包含实时单帧推进上限 0.1 秒与导航保守粗筛优化，目的是避免长帧追赶和减少不必要的碰撞计算。

阶段查询改为直接读取规则字段，避免界面每帧多次查询时反复深拷贝整局数据和积分账本；回归检查覆盖查询结果、状态不变性和零快照调用。该改动没有修改战斗规则，也没有据此声称第二轮冻结已修复。

45–70 秒是标准回合时长目标，目前未全面达成。当前短局规则在 90 模拟秒比较双方剩余绝对 HP，护盾不计入，HP 相等判平。低帧率、暂停或加载可能使现实耗时更长。

已有 Windows 第二轮冻结反馈，尚未证明彻底修复；RTX 4060 实机性能、实际扬声器声音输出、多台 Windows 局域网与 Android 设备体验仍需单独验收。完整本地资源版本的历史测试记录不能代替此缺资源公开副本的完整回归。详见[验证边界](docs/VALIDATION.zh-CN.md)。

## 权利与许可

仓库保留已有 Godot 许可证与第三方组件声明，它们只适用于相应组件。**程序源码目前没有新增开源许可证**；公开可见不意味着获得任意复制、再分发或商业使用授权。原作角色及资源权利属于其权利人；项目不提供其公开再分发授权。贡献、资源补齐与打包前请阅读[权利边界](docs/CONTRIBUTING.zh-CN.md)。
