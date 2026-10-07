# 本地资源导入与运行

[返回首页](../README.md)

## 先确认公开版的边界

完整运行所需的原作资源及提取数据没有公开；资源派生着色器与生成目录同样省略。这里没有可公开分发的完整资源包、下载器或完整客户端提取流水线。拥有原版客户端不自动赋予提取、改作或公开分发授权。只能在你有权使用的范围内准备输入，并留在自己的合法本地环境。

[被省略资源路径清单](private-resource-paths.txt) 只含相对路径，不包含资源字节，是定位参考而非“最小运行集”。配置还会间接引用其他文件。请勿从文件数量推断补齐程度，也不要为消除报错而创建空 JSON、空着色器或跳过资源检查。

## 需要提供的输入

以 `project.godot` 所在目录为根，保留匹配版本的结构：

- `assets/characters/<角色 ID>/`：模型、纹理、导入设置、动画；明日奈还依赖 `asuna.glb`、`asuna-animation-library.res`、`asuna-animation-manifest.res`。
- `assets/native/`、`assets/ground_mines/`、`assets/skill_props/`：原生模型、材质与技能道具。
- `assets/ui/`：肖像、技能图标等；`assets/audio/native-ordinary/` 与 `assets/audio/native-skills/`：音频原始文件。
- `data/character_skills.json`、`data/character-presentations.json`、`data/native-skill-contacts.json`、`data/verified-durations.json`：角色、技能、表现和接触时间。
- `data/audio/`：声音绑定、校验与来源清单；`data/effects/`：事件、时间线、visual-templates、网格/纹理引用和元数据。
- `data/native-hg-muzzle.json`、`data/native-hg-impact.json`、`data/skill-icons.json`、`data/skill-impact-adaptations.json` 等其他运行时配置。
- `vfx/materials/native_shader_catalog.gd`、`vfx/materials/shaders/` 中 17 个资源派生着色器，以及清单列出的 9 个 `shaders/native_*.gdshader`：共 27 个未公开的生成代码/着色器文件，需匹配本地完整工程。
- 完整测试另需 `tests/fixtures/` 等位置的 JSON、压缩提取基线与其他专用输入，它们不全是游戏运行时必需项。

`vfx/materials/shader_preloads.gd` 等代码仍引用被省略的文件，因此缺资源时可能先遇到 **preload/脚本解析失败**，不一定等到运行时读取 JSON 才失败。这是当前公开范围的结果。

保留匹配的 `.import` 参数；`.godot/` 是本地生成缓存，不是原始资源替代品。不要把缓存、旧仓库历史、提取日志、证据截图、账户配置或密钥复制到公开仓库。

## 已有快照导入工具做什么

`tools/import_roster_snapshot.py` 只处理准备好的角色快照，不下载、不从原版客户端自动提取，也不自动激活新角色或生成全部战斗配置。

快照入口是 `export-profiles.json`，`profiles` 必须是非空列表。模型、texture_manifest、material_folder、source_manifest、clips、model_scale、model_yaw_radians 等字段须符合工具的 `load_profiles()`、`validate_snapshot()` 检查；引用的 GLB、材质 JSON、纹理清单与文件必须已经存在。请先查看脚本而不是猜格式。

在项目根目录中运行（将占位路径换成本机真实路径）：

```sh
python3 tools/import_roster_snapshot.py --source /absolute/path/to/snapshot --root .
godot --headless --path . --editor --import
python3 tools/import_roster_snapshot.py --source /absolute/path/to/snapshot --root . --configure-only
godot --headless --path . --editor --import
```

这是两阶段导入：先复制受支持角色和配置，再让 Godot 生成导入文件，最后调整选定角色的导入参数并重新导入。工具保留未涉及的其他角色，不是可覆盖任意工程的通用转换器。明日奈的 `tools/asuna_animation/` 还包含精确校验值约束的动画准备/编译工具，不能对任意 GLB 套用。

## 启动检查

1. 安装 Godot 4.6.3 Standard，确认 `godot --version`。导出流水线对 Linux 引擎还有固定哈希要求。
2. 在本地合法环境补齐上述输入，逐项核对路径、大小写和版本。Linux 文件名区分大小写。
3. 在 Godot 中导入 `project.godot`，检查输出面板与缺失依赖。不要忽略脚本解析失败。
4. 运行主项目。Linux：`bash ./run-prototype.sh`；可用 `GODOT_BIN` 指定引擎。Windows：`run-prototype.cmd`；建议用 `GODOT_EXE` 显式指定 4.6.3。两种脚本都会拒绝非 4.6.3 stable 版本，不再回退到旧的 4.7.2 工具目录。
5. 用一局新游戏检查招募、布阵、EX、结算、存档和菜单，再按[测试说明](VALIDATION.zh-CN.md)验证改动。

首次导入/着色器准备可能较慢；这不能解释所有卡死，也不应掩盖重复出现的错误。排查时保存日志并标注引擎、平台、场景、回合与复现步骤。

启动脚本会先检查 `data/character-presentations.json`、`data/character_skills.json` 和 `shaders/native_body_layer4.gdshader`。干净的公开源码副本会立即显示缺失路径并停止，避免进入大量缺资源导入错误。这个入口检查只确认三个文件存在，不验证内容或所有间接依赖；不要用空文件绕过，完整检查仍以上述资源准备和发布工具为准。

## 为什么补到工作区仍不能直接发布构建

Windows/Android 流水线使用 `git archive` 从**固定完整提交**读取运行时输入，不读取未提交的资源。公共提交缺少 `data/` 等必要根目录，连 dry-run 也可能因输入不完整而拒绝。

需要构建时，应在独立、不可公开的本地构建仓库中管理你有权使用的完整输入，并把资源纳入该私有构建提交；仅给公开工作区补上被忽略的文件并不能满足流水线。禁止为构建方便把资源强推到本公开仓库。若无权保存这种完整快照，就不能使用当前固定提交发布流程。

具体工具链、dry-run/execute 和输出校验见 [Windows](../tools/windows_release/README.md) 与 [Android](../tools/android_release/README.md)。发布前另行确认所有资源及组件的分发权限。
