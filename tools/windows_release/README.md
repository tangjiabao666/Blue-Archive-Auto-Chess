# Windows x86_64 私有候选包构建

[返回项目首页](../../README.md) · [资源准备](../../docs/ASSET_IMPORT.zh-CN.md) · [验证边界](../../docs/VALIDATION.zh-CN.md)

## 这条流水线的用途与前提

`release_pipeline.py` 在 Linux 上从固定 Git 提交生成 Windows x86_64 候选包，使用 Godot Standard 4.6.3。它没有下载器，不执行 Windows EXE，不自动完成玩法全回归，也不证明 Windows 设备可玩。

**公共源码提交不能直接构建。** 运行时资产、data 及资源派生着色器被省略。流水线 `git archive` 只读取已提交输入，忽略未提交/被忽略的本地补充文件。需要你有权保存和使用的完整私有构建仓库；不能把这些资源推回公开仓库。缺少 runtime roots 时 dry-run 同样会失败。

需要 Python 3.11+、Git、固定 Linux Godot 引擎、匹配 Windows 模板和足够临时磁盘空间。`notices/` 中 Godot 许可证、第三方声明及资源提示是包装输入；资源提示不是分发授权。

## dry-run 与执行

在完整私有构建仓库根目录的 Bash 中，替换路径：

```sh
REPO="$(git rev-parse --show-toplevel)"
COMMIT="$(git rev-parse HEAD)"
TEMPLATES=/absolute/path/to/templates/4.6.3.stable
GODOT=/absolute/path/to/Godot_v4.6.3-stable_linux.x86_64
OUTPUT=/absolute/path/to/new-windows-candidate
python3 tools/windows_release/release_pipeline.py   --repo "$REPO" --commit "$COMMIT"   --templates "$TEMPLATES" --godot "$GODOT"   --output-root "$OUTPUT" --dry-run
```

`COMMIT` 传递的是 `git rev-parse` 展开的完整 40/64 位哈希，不是字面 `HEAD`；短哈希、分支和标签不被接受。输出目录必须全新、不存在（不能是空目录或悬空符号链接），并且位于仓库与模板目录之外。

默认不带动作参数也是 dry-run：读取 Git 元数据并打印计划，不创建输出、不运行 Godot，也不代表模板哈希或资源依赖已经通过。完整回归与输入审查完成后，将 `--dry-run` 换为 `--execute`。`--timeout` 默认每个 Godot 进程 1800 秒。失败输出保留供检查，修复后选择新的输出目录，不覆盖或续跑旧候选。

## 固定引擎与模板

当前引擎标识：`4.6.3.stable.official.7d41c59c4`。脚本校验 Linux 引擎 SHA-256：

`f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3`

模板目录必须并列提供 `windows_release_x86_64.exe`、`windows_release_x86_64_console.exe`、`version.txt`。字节数、SHA-256、PE x86_64 标识由脚本固定校验。详见 `release_pipeline.py` 的 `ENGINE_SHA256`、`TEMPLATES`，不要用其他版本同名文件替换。

模板参考来源：[Godot 4.6.3 官方导出模板](https://github.com/godotengine/godot-builds/releases/download/4.6.3-stable/Godot_v4.6.3-stable_export_templates.tpz)。流水线不会自行下载或接受新的许可；升级引擎需要重新审核模板、声明、校验值和运行结果。

## 构建过程

1. 从完整提交归档 `project.godot`、`game.tscn`、`core/`、`scripts/`、`shaders/`、`assets/`、`data/`、`vfx/`，拒绝链接和特殊文件。工作区改动不进入发布源。
2. 计算依赖清单，保留通过 `FileAccess` 读取的原始 JSON、网格与纹理元数据；按需要设置 staging 的 Keep File。音频校验覆盖 WAV 格式、帧数、时长与 PCM 哈希。
3. 在隔离 HOME/XDG 下导入、执行源资源检查、使用 `export_presets.cfg.in` 导出，再从空目录挂载 PCK 检查。
4. 对比源/PCK 的资源、音频、特效诊断，校验包内容与哈希并排除测试、提取包、日志、存档和工具。
5. 校验 staging 输入完整性，生成中文启动说明、声明、manifest、校验和与 ZIP。

目前脚本的关键固定门槛为 **14 个模型、28 条 EX/基础技能时间线、171 个原始网格、279 个 VFX PNG、279 个纹理元数据、43 个技能音频、96 个普通音频、28 个普通攻击/换弹绑定**；另外有图标、动画覆盖、总线等校验。以 `EXPECTED`、`COUNTERS` 和运行时检查为准。旧文档的 13 角色/26 时间线计数已不适用。

已知 Nonomi 烟雾缺材质诊断只在源数据条件与脚本白名单都匹配时允许。不可把所有 warning/error 一概忽略。角色或资源变更要更新相应证据和测试，不能只放宽计数。

## 产物与验收

`BUILD-RESULT.json` 记录 ZIP 名称、字节数与 SHA-256；`checks/` 和 `logs/` 保留完整检查；包内 `BUILD-MANIFEST.json` 记录源码/引擎/模板与验证边界。

ZIP 中 `Blue-A-Windows-x86_64/` 包含：

- `Blue-A.exe`、`Blue-A.console.exe`、`Blue-A.pck`
- `README.zh-CN.txt`、`ASSET-NOTICE.zh-CN.txt`
- `GODOT-LICENSE.txt`、`GODOT-THIRD-PARTY-NOTICES.txt`
- `BUILD-MANIFEST.json`、`SHA256SUMS.txt`

解压后保持 EXE/PCK 同目录。只在权限允许时分发指定产物，不把完整 output、私有源仓库或证据目录打包。构建输入固定不意味着跨机器 ZIP 字节完全相同，manifest 含构建时间且引擎导入输出可能变化。

Linux 引擎读取 PCK 的资源检查不是 Windows EXE 启动、输入、全屏、释放版行为、RTX 4060 性能、扬声器声音或多机 LAN 验收。Windows 第二轮冻结仍须实机验证，不能凭此流水线宣称已修复。

## 工具测试

纯源码基础子集：

```sh
python3 -m unittest discover -s tools/windows_release/tests -p test_pipeline.py -v
```

完整工具测试：

```sh
python3 -m unittest discover -s tools/windows_release/tests -v
```

本次前者 12 项通过；后者 32 项中有 1 项需要被省略的实际资源清单、因缺 `data/skill-icons.json` 报错，其余 31 项通过。详见[测试说明](../../docs/VALIDATION.zh-CN.md)。本次公开源码整理没有生成或验收新的 Windows 安装包。
