# 测试、项目状态与已知限制

[返回首页](../README.md)

## 三类证据不能混为一谈

1. **公开源码检查**：文件与范围审查、语法/链接检查、独立规则和工具测试。它们可在不提供原作资源时运行，但不覆盖完整游戏。
2. **完整本地资源工程的历史回归**：依赖本地合法资源、提取配置和测试基线；公开仓库没有全部输入，因此不能直接重现完整历史结果。
3. **目标设备验收**：Windows 原生程序、真实显卡、扬声器、多机网络和 Android 手机，需要在对应设备执行，云端和 headless 不能替代。

## 纯源码可运行的 Python 检查

### 公开源码自动检查

[Source checks](https://github.com/tangjiabao666/Blue-Archive-Auto-Chess/actions/workflows/source-checks.yml) 在推送和拉取请求中运行以下检查：

- Git 跟踪文件不得包含省略资源清单中的路径或 `.gitignore` 排除的本地文件；所有 Python 源码进行语法解析。
- Ubuntu / Python 3.11：Windows 发布工具的五个合成输入测试模块（31 项）、Android 工具测试（20 项）、资源快照导入测试（24 项）及协作模拟源码约束（3 项）。
- Bash 和 Windows 启动脚本行为：缺资源、错误版本、路径与参数、失败退出码；平台专属测试在对应系统运行。
- 官方 Godot 4.6.3（下载后校验 SHA-256）：阶段查询、战术资源、LAN 协议、导航粗筛、积分账本和 AI 结算六个独立规则脚本。

这些检查不下载角色资源，不导出游戏。`test_asuna_fixture_dependencies.py` 和依赖省略资源/基线的根目录测试保留原样，属于完整资源验证，未包含在公开源码 CI 中。绿色状态只代表上述范围。

发布工具的合成测试仍有 POSIX 符号链接、执行权限和路径假设，请在 Linux 使用 Python 3.11+ 复现。Python 3.9 缺少 `hashlib.file_digest`，不能作为这组工具测试的受支持环境。可运行与 CI 相同的命令：

```sh
for suite in test_pipeline.py test_animation_libraries.py test_ordinary_audio.py test_pc_readme.py test_save_versions.py; do
  python3 -B -m unittest discover -s tools/windows_release/tests -p "$suite" -v || exit 1
done
python3 -B -m unittest discover -s tools/android_release/tests -v
python3 -B -m unittest discover -s tests -p test_import_roster_snapshot.py -v
python3 -B -m unittest discover -s tests -p test_cooperative_ai_source.py -v
python3 -B -m unittest discover -s tests -p test_launchers.py -v
```

### 交接版本的验证记录

以下命令在仓库根目录执行，使用 Python 3.11+。测试创建临时合成输入，不启动目标平台二进制。

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/windows_release/tests -p test_pipeline.py -v
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/android_release/tests -v
```

文档整理时实跑结果：Windows `test_pipeline.py` **12 项通过**；Android 工具测试 **20 项通过**。这是特定子集的结果，不是运行游戏、导出 APK/EXE 或连接设备的验证。

下面是完整 Windows 工具测试命令，但**不是纯源码全部通过的承诺**：

```sh
python3 -m unittest discover -s tools/windows_release/tests -v
```

本次在缺资源副本中发现 32 项，其中 31 通过、1 项错误。错误来自 `test_asuna_fixture_dependencies.py`，依赖清单读取缺失的 `data/skill-icons.json`；补齐该单文件并不保证后续依赖齐全。保留这个真实输入校验，不要删测试或改成跳过来制造“全绿”。

根目录 `tests/test_*.py` 混合源代码边界检查、动画编译器和原始音频/材质/JSON 完整性测试，也不能笼统标为不需要资源。

## 纯规则 Godot 检查

以下独立脚本在 Godot 4.6.3、可写用户数据目录下实跑通过，不加载完整游戏：

```sh
godot --headless --path . --script tests/test_tactical_resources.gd
godot --headless --path . --script tests/test_phase_query.gd
godot --headless --path . --script tests/test_lan_protocol.gd
godot --headless --path . --script tests/test_navigation_broadphase.gd
godot --headless --path . --script tests/test_user_settings_quality.gd
godot --headless --path . --script tests/test_tactical_league.gd
```

对应覆盖能量/移动次数、局域网消息与地址校验、导航粗筛、质量设置、六轮积分。资源测试 28 检查、协议 19 检查、质量设置 178 检查、积分 323 检查均无失败；导航脚本报告无失败。不要据此声称运行时材质、角色、音频或网络传输通过。

在受限容器中 Godot 需要可写的 HOME/XDG 目录；本次默认环境曾在进入测试前因用户目录/缓存问题异常退出，设置独立可写目录后上述脚本通过。可用下列 Bash 方式隔离状态，避免污染个人存档：

```sh
QA_HOME="$(mktemp -d)"
mkdir -p "$QA_HOME/cache" "$QA_HOME/data" "$QA_HOME/config"
HOME="$QA_HOME" XDG_CACHE_HOME="$QA_HOME/cache" XDG_DATA_HOME="$QA_HOME/data" XDG_CONFIG_HOME="$QA_HOME/config" godot --headless --path . --script tests/test_tactical_resources.gd
```

这只是环境诊断和隔离方法，不能修复缺失资源。保留日志，按退出码和实际断言结果判断，不要只看启动成功。

## 完整资源测试与导出验收

角色动作、命中、特效、原始音频、存档集成、UI 场景及多进程对局等通常需要完整数据。`tests/` 中还包含截图、基准、交互探针和预览场景，不是统一单元测试集合；不要对所有 `.gd` 无差别循环运行。有些脚本需要渲染设备、专用参数或手工退出。

`tools/windows_release/verify_runtime.gd` 与发布工具会检查源资源及 PCK/APK 中的依赖、模型、时间线、音频和校验和。构建时必须保持失败即停止的检查策略；Python 合成测试通过不能代替真实包内校验。

维护过程记录的上一轮完整本地工程回归包括 282 个 Godot 脚本执行（278 首轮及 4 个适配后重跑）、171 个 Python 用例与音频校验，以及六轮云端 llvmpipe 加速渲染。**这些是另一套完整输入环境的历史结果，不是此次公开副本的全套复跑，也不是六轮 Windows 实机游戏验收。** 本公开仓库不提供该环境的完整资源及证据输入。

## 当前待验收问题

- **Windows 第二轮冻结**：已有反馈；当前优化未证明彻底修复。需要相同版本连续多轮复现/回归并保留日志。
- **回合长度**：45–70 模拟秒目标尚未全面达成；新局有 90 模拟秒绝对 HP 超时规则。高耐久/治疗阵容与现实耗时仍要分别分析。
- **真实帧率**：默认 60 FPS 是上限设置，不是达标证据；云端 llvmpipe、加速模拟和 headless 数值不能换算 RTX 4060 的帧率。
- **声音**：WAV/PCM/包内资源与调度正确不等于扬声器输出、混音听感和设备延迟已验证。
- **LAN**：协议测试不等于三台 Windows 机器的六轮联机、掉线接管、房主丢失、网络抖动验收。
- **Android**：当前工具构建私有 ARM64 测试 APK；没有据此保证实际手机、HarmonyOS、温升、2K、120 FPS或触控适配。导出配置没有网络权限。
- **表现等价性**：适配器保留了诊断及近似边界，不能把载入成功视为原作动画/AudioAnimator/材质语义完全一致。

## 建议提交的复现信息

源码提交、Godot 精确版本、操作系统、GPU/驱动、画质/FPS/渲染比例、单人或 LAN、回合与操作顺序、是否从旧存档继续、预期/实际结果、退出码及必要日志。资源仅描述缺失路径或校验结果，不上传原作资源、个人存档、私有路径或签名密钥。公开报告前先脱敏。
