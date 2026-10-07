# Android ARM64 私有测试 APK 构建

[返回项目首页](../../README.md) · [资源准备](../../docs/ASSET_IMPORT.zh-CN.md) · [Windows 基础流水线](../windows_release/README.md)

## 构建范围

此工具复用 Windows 发布器的依赖清单和完整性门槛，在 Linux 中导出 Godot ARM64 release runtime，用**本地 Android debug 证书**签名，仅用于私有测试。它不连接手机、不安装 APK、不访问应用商店、不自动下载依赖或接受许可。

公开源码缺少运行时资源和数据，不能直接产出可玩 APK。和 Windows 一样，所有运行输入必须存在于你有权使用的独立完整私有 Git 提交中；工作区的未提交资源不进入归档。不要把完整资源提交到公开仓库。

## 先准备工具链

- Python 3.11+、Git；匹配固定哈希的 Godot Standard 4.6.3 Linux 引擎。
- 匹配的 `android_debug.apk`、`android_release.apk`、`version.txt` 导出模板。
- Android SDK build-tools **35.0.1**（含 `apksigner`、`zipalign` 等）与 Java SDK（`java`、`keytool`）。
- 仓库及整个构建输出之外的本地测试 keystore；脚本使用标准 `androiddebugkey` 别名和测试密码 `android`，不能把它当生产签名方案。
- 已提交完整输入的私有仓库，以及一个不存在的新输出目录。

模板/SDK 默认位置是工程内被忽略的 `private-toolchains/android` 下相应目录；默认 Godot、Java 路径也是脚本的本地约定，不保证你的机器存在。建议显式传入所有路径。

## 运行示例

在完整私有构建仓库根目录执行，替换绝对路径：

```sh
REPO="$(git rev-parse --show-toplevel)"
COMMIT="$(git rev-parse HEAD)"
python3 tools/android_release/release_pipeline.py   --repo "$REPO" --commit "$COMMIT"   --godot /absolute/path/to/Godot_v4.6.3-stable_linux.x86_64   --templates /absolute/path/to/templates/4.6.3.stable   --sdk /absolute/path/to/android-sdk   --java-home /absolute/path/to/jdk   --keystore /absolute/path/to/private-signing/debug.keystore   --output-root /absolute/path/to/new-android-candidate   --dry-run
```

只接受展开后的完整提交哈希，不接受字面 `HEAD`、短哈希或分支。dry-run 是默认，不运行 Godot或创建构建输出；缺少完整源码根目录时也会拒绝，不代表任何资源/签名检查已经通过。

准备和审查完成后，把 `--dry-run` 换成 `--execute`。只有首次确实需要生成本地测试密钥时才加 `--create-debug-keystore`，不会覆盖已有密钥。密钥留在本地，不进入 APK 或公开仓库；同签名升级需要保存它，换密钥可能要求卸载旧应用并丢失本地数据。`--timeout` 默认每个 Godot 进程 1800 秒。

## 流水线检查什么

1. 核对引擎、模板和固定 Git 输入，从零生成 `.godot` 导入缓存。
2. 复用 Windows 的原始依赖/音频/材质检查与 staging Keep File 配置；当前是 14 角色/28 时间线，而非旧 13 角色版本。
3. 仅在 staging 设置 1280×900 canvas_items、expand、横屏、触摸模拟鼠标、GL Compatibility 和 ETC2/ASTC，并添加中性启动图标。
4. 在隔离 HOME/XDG/TMP 中配置 SDK/Java；不用 Gradle，不启用扩展包、备份、外部存储或网络权限。
5. 导出 ARM64，包名 `com.bluea.prototype`；检查 min API 24、target API 36、零权限、横屏、非 debuggable 与 launcher activity/alias。
6. 校验 APK 每个成员的 CRC/SHA-256、资源 remap 与原始字节，拒绝测试、提取材料、存档、设置或密钥泄漏。
7. 从 APK 重建音频校验包，用 headless 引擎验证 96 个普通音频的 PCM/格式/循环设置，并加载 43 个技能音频。
8. `apksigner verify --verbose --print-certs` 校验证书与 v2 签名；`zipalign -c -P 16 -v 4` 检查签名后的布局。
9. 将 APK、中文安装说明、声明、manifest 与校验和写入 `deliverable/`。日志、缓存和 staging 留在外面。

当前 Android 导出没有网络权限，因此不能把源码里的 LAN 功能等同于此 APK 已支持联网。需要改变该配置时，应重新审查权限、构建与设备验收。

## 已审查的导入例外

特定原始 `shiroko_drone.glb` 在 Godot 4.6.3 导入时，两个初始零缩放的旋翼骨骼触发恰好六条 Basis/Quaternion 归一化诊断。脚本只在固定资源、固定哈希、固定堆栈位置、固定消息数和导入阶段全部匹配时允许，并继续执行无人机资源/姿态/生命周期检查。

这不是“所有导入错误可忽略”或“导入器已修复”。消息、数量、资源、阶段或其他 warning/error 改变都会失败；不要删除原始骨骼/动画来规避检查。真实日志记录在构建输出的 `logs/`、`checks/`。

## 测试和未验证项

仓库根目录运行：

```sh
python3 -m unittest discover -s tools/android_release/tests -v
```

本次纯源码工具测试 20 项通过，不需要连接设备，也不生成 APK。发布工具本身不执行全仓玩法回归、GUI 基准、模拟器或实机安装；没有证明手机音频、温升、触控、HarmonyOS、2K 或稳定 120 FPS。本次文档整理未导出或验收新的 APK。

参考：[Godot Android 导出](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html)、[Android 签名检查](https://developer.android.com/tools/apksigner)、[Android ZIP 对齐](https://developer.android.com/tools/zipalign)。
