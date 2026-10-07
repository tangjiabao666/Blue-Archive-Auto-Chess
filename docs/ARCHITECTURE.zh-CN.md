# 架构与源码导览

[返回首页](../README.md)

## 启动链与数据流

`project.godot` → `game.tscn` → `scripts/pc_app.gd`（主菜单/继续游戏/设置/场景切换）→ `scripts/gameplay.tscn` → `scripts/game_app.gd`（游戏界面、输入与展示协调）。`gameplay.tscn` 明确选择 `tactical_v1` 新局。

单人规则由 `core/game_session.gd` 连接经济、地图、对战时钟、玩家输入和场外 AI 对局。输入经过命令校验和逻辑 tick 执行，产生事件和状态，再交给模型、动画、特效、音频和界面展示。展示帧率与固定逻辑步长不是同一概念。

## 目录职责

| 目录/文件 | 主要用途 |
| --- | --- |
| `core/` | 规则、确定性模拟、时钟、导航、存档与设置等 |
| `core/lan/` | 协议、房间规则、房主权威、对局和视图编码 |
| `scripts/` | 场景控制、菜单、HUD、输入、角色/动画/音频/特效适配 |
| `scripts/lan/` | ENet 传输、房间控制、大厅和 LAN 客户端界面 |
| `vfx/`、`shaders/` | 特效运行时、材质适配与着色器；部分资源派生输入不公开 |
| `assets/audio/combat_bus_layout.tres` | 保留的自定义音频总线及输出峰值限制 |
| `tests/` | Godot/Python 测试、探针、基准和部分预览场景；并非全部能在纯源码版运行 |
| `tools/` | 资源快照导入、动画编译、模拟/性能工具及发布流水线 |
| `docs/` | 使用、架构、验证和贡献说明 |
| `battle.tscn`、`gallery.tscn` | 辅助战斗/展示入口，不是默认主菜单入口 |
| `data/`、其余 `assets/` | 需要本地补齐的规则数据和资源，不随公开版提供 |

## 推荐阅读顺序

1. `core/prototype_match.gd`：通用经济与准备阶段状态；`core/tactical_match.gd`：六轮积分赛覆盖；`core/tactical_league.gd`：严格的回合账本与排名。
2. `core/game_session.gd`：当前 14 人名单、规则版本、模式选择、保存与恢复、场内/场外战斗连接。
3. `core/character_sim.gd`、`core/tactical_sim.gd`、`core/character_clock.gd`：角色模拟与实时战术扩展。场景无关不等于资源无关，角色数据仍由外部配置提供。
4. `core/tactical_command_queue.gd`：代际、队伍所有权、序号和时间边界；`core/tactical_resources.gd`：能量/移动次数；`core/tactical_orders.gd`：有限距离路径执行。
5. `core/obstacle_navigation.gd`、`core/tactical_maps.gd`、`core/tactical_cover_planner.gd`、`core/attack_volumes.gd`：地形、导航、掩体与命中体积。
6. `scripts/game_app.gd`、`scripts/tactical_input.gd`、`scripts/battle_stage.gd`、`scripts/unit_view.gd`：界面到模拟的接线，以及表现层。
7. `core/lan/authority.gd` 与 `scripts/lan/room_controller.gd`：房主对局调度、超时、掉线接管和生命周期。

## 表现层与原作资源的边界

模型/动画导入、材质映射、时间线与声音调度分散在 `scripts/native_*`、`scripts/ordinary_*` 和 `vfx/` 中。普通音频和技能音频各有自己的资源和调度校验。`assets/audio/combat_bus_layout.tres` 使用 Master HardLimiter 控制峰值，不能据此保证设备听感或所有内容的真峰值安全。

代码直接 `load`/`preload` 的路径不是全部依赖：JSON、原生网格、纹理元数据和动画清单还会间接引用更多文件。某些内容通过 `FileAccess` 读取原始字节，导出时不能仅依靠 Godot 自动资源依赖。发布工具因此另做依赖清单、Keep File、PCK/APK 包内哈希与资源读取验证。

资源派生的 `vfx/materials/native_shader_catalog.gd`、17 个 `vfx/materials/shaders/` 着色器和清单列出的 9 个 `shaders/native_*.gdshader` 不在公开范围内；本地完整运行需要匹配内容。它的缺失与原作 JSON 缺失一样是公开版的已知输入边界，不能用空文件假装修复。

## 性能相关改动

- `core/prototype_match.gd` 的 `get_phase()` 直接读取阶段字段，`core/game_session.gd` 查询阶段时不再构造包含全部阵容、商店和积分账本的深拷贝快照。`tests/test_phase_query.gd` 用真实规则实例检查查询状态不变且不调用快照；完整会话测试仍需要角色数据。
- `scripts/game_app.gd` 将实时单帧输入 delta 限到 0.1 秒，避免一帧试图追赶全部停顿时间；这不改变固定 tick 的时长，也不证明任何具体死锁已修复。
- `core/obstacle_navigation.gd` 使用保守粗筛，跳过不可能碰到的障碍物，精确判断仍保留；相关回归是 `tests/test_navigation_broadphase.gd`。
- `core/user_settings.gd` 与 `core/render_quality_profile.gd` 管理画质、缩放和 FPS 上限。桌面缺省 high/1.0/60，移动缺省 balanced/0.85/60；明确保存的偏好不会被默认值覆盖。
- `core/offscreen_process_worker.gd`、`core/offscreen_process_batch.gd`、`core/offscreen_duel.gd` 处理场外对局路径；不要仅测前台战斗就断言整轮结算无阻塞。

## 修改时保持的约束

模拟/规则中不要偷偷依赖视觉帧数；输入命令不要绕过所有权和阶段检查；存档不能把新名单强行套进旧规则；新资源/角色不能只加 UI 名称，还要更新完整本地数据、动画/音频/特效映射、导出计数和回归。详细流程见[贡献说明](CONTRIBUTING.zh-CN.md)。
