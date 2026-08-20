<p align="center">
  <img src="design/logo/folbi-logo.png" alt="Folbi Logo" width="180">
</p>

# Folbi

Folbi 是一个轻量、原生的 macOS 文件夹编辑器。它保留日常 Agent 工作真正需要的部分：完整文件树、文本编辑、语法高亮和基础文件操作。

产品显示名是 Folbi。仓库、Xcode 工程、scheme 和 Swift 模块继续使用 FolderPad。

主 Logo 使用 Folbi 柠檬文件夹形象。原图位于 `design/logo/folbi-logo.png`，macOS App Icon 位于 `FolderPad/Assets.xcassets/AppIcon.appiconset`。

## 首版能力

- 打开一个本地文件夹，以惰性树展示全部内容，包括点文件。
- 新建文件或文件夹；右键复制绝对路径、根目录相对路径，或在 Finder 中显示。
- 编辑不超过 5 MiB 的普通 UTF-8 文本文件，手动保存。
- 自动识别多种语言并高亮，提供 Default、GitHub、Solarized 三种主题。
- 监控外部文件修改；未保存内容发生冲突时不静默覆盖。

首版不包含 LSP、Git、终端、插件和自动保存。

## 开发

要求 Xcode 26.6 或兼容版本。首次打开 [FolderPad.xcodeproj](FolderPad.xcodeproj) 时，Xcode 可能要求信任 SwiftLint package plugin。

在 Codex App 中使用 `Run` 动作，或直接运行：

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
```

安装一份仅供本机使用的 Release App：

```bash
./script/build_and_run.sh --install
```

安装位置是 `~/Applications/Folbi.app`。该本地包未签名、未公证，不用于公开分发。

```bash
xcodebuild test -quiet \
  -project FolderPad.xcodeproj \
  -scheme FolderPad \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/DerivedData \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO
```

测试完成后，调试应用位于 `.build/DerivedData/Build/Products/Debug/Folbi.app`。

## GitHub

目标仓库为 `Dimon94/folder-pad`。远程仓库尚未创建。
