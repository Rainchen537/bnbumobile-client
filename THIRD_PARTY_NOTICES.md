# 第三方组件与素材

自有客户端代码采用 GPL-3.0-only；以下第三方内容保留各自许可证。学校手绘地图未包含在仓库中，在线加载时权利仍归原权利人。

## cryptography_plus

- 上游包：<https://pub.dev/packages/cryptography_plus>；固定使用既有锁文件版本 `2.7.1`，从传递依赖改为直接声明，未升级包版本。
- 使用范围：普通邮件设备本机缓存的 AES-256-GCM 加密与完整性校验；设备随机密钥仍由系统 secure storage 保存。
- 许可证：Apache License 2.0；完整许可证文本随依赖包分发。

## iSpace_Downloader 实现参考

- 上游：<https://github.com/jytpeterjiang/iSpace_Downloader>，作者 [Peter Jiang（@jytpeterjiang）](https://github.com/jytpeterjiang)；参考提交 `a3145d79cf7642687c9f220c5fc25c3b5ad46585`（userscript v2.3.0）。
- 使用范围：参考按课程/章节发现 Resource、Folder 与页面附件、保留文件扩展名的思路，在现有 Flutter 会话和本机 ZIP 服务上独立实现；不复制、执行或分发上游 userscript，不加载其第三方脚本或把账号交给上游。
- 上游 README 标注 MIT，但该参考提交未包含独立 LICENSE 文件；本轮未打包上游代码。若以后直接引入其源码，须先补齐明确的授权和许可证文本。

## desktop_drop

- 上游项目：<https://github.com/MixinNetwork/flutter-plugins/tree/main/packages/desktop_drop>。
- 固定版本：`desktop_drop 0.7.1`，保留当前 Android AGP 8 工具链；不自动升级至要求 AGP 9 的 0.8 系列。
- 使用范围：macOS / Windows 原生文件拖放及 Mac security-scoped bookmark 访问，仅在作业附件区接收文件；不上传数据至该组件作者。
- 许可证：Apache License 2.0，Copyright 2021 Mixin；完整许可证随依赖包与 Flutter 许可证清单分发。

## desktop_updater

- 上游项目：<https://pub.dev/packages/desktop_updater>
- 固定版本：`desktop_updater 3.1.6`。
- 使用范围：保留 macOS/Windows 的 Ed25519 签名索引、描述文件、产物校验与受约束安装助手作为后续自更新工程储备。当前运行时使用北京官网版本提醒和系统浏览器下载，不启用该组件的 App 内安装流程。
- 许可证：MIT License；完整许可证文本随 Flutter 依赖包分发。项目内 `AppUpdateRecoveryStore` 按其公开示例的恢复记录契约实现，并保留相同安全边界。

## QR.Flutter / Dart QR

- 上游项目：<https://github.com/theyakka/qr.flutter>、<https://github.com/kevmoo/qr.dart>
- 固定版本：`qr_flutter 4.1.0`、`qr 3.0.2`。
- 使用范围：在设备本机把学生学号渲染为 eCard 黑白二维码，不执行二维码扫描或联网解析。
- 许可证：BSD 3-Clause License；完整许可证文本随各依赖包分发。

QR.Flutter Copyright (c) 2020, Luke Freeman. All rights reserved.

Dart QR Copyright 2014, the Dart QR project authors. All rights reserved.

## Flutter Math Fork / KaTeX fonts

- 上游项目：<https://github.com/simpleclub/flutter_math>。
- 固定版本：`flutter_math_fork 0.7.4`。
- 使用范围：在 Flutter 客户端本机解析并渲染小U回复中的受限 TeX 数学公式；不使用 WebView、JavaScript、网络资源或外部文件。
- 许可证：Flutter Math Fork 为 Apache License 2.0；随包 KaTeX 字体为 MIT License，Copyright (c) 2018 Khan Academy。完整许可证文本随 Flutter 依赖包分发。

## Flutter local_auth

- 上游项目：<https://github.com/flutter/packages/tree/main/packages/local_auth>
- 固定版本：`local_auth 3.0.2`、`local_auth_darwin 2.0.3`、`local_auth_android 2.0.9`、`local_auth_windows 2.0.1`、`local_auth_platform_interface 1.1.0`。
- 使用范围：在 iPhone 与 iPad 上调用系统 Face ID 或 Touch ID，为用户可选的主 App 界面保护执行本机身份验证。
- 许可证：BSD 3-Clause License；完整许可证文本随依赖包分发。

Copyright 2013 The Flutter Authors. All rights reserved.

## Moodle 活动图形

- 上游：<https://github.com/moodle/moodle>，固定提交 `090baf556eb30b6baf9dc5fb8f3ac879e186b266`，与已核验的 Moodle 4.1.3+ 契约匹配。
- 使用范围：`assets/moodle/` 中 20 种标准活动的原始 `mod/*/pix/monologo.svg`，只复用活动图形，渲染时施加当前语义色。
- 来源路径和逐文件 SHA-256 在 `assets/moodle/sources.json`；原始 SVG 未修改。
- 图形按 Moodle 上游 GPL-3.0-or-later 分发，完整许可随资源保存在 `assets/moodle/COPYING.txt`，并登记到 App 的许可列表。

## 本地邮件富文本编辑器

- 编辑内核：Tiptap `3.23.5` 与其锁定的 ProseMirror 依赖，<https://github.com/ueberdosis/tiptap>；使用表格、字体、列表、选区与 HTML 文档功能，不连接 Tiptap 云服务。
- 构建来源：`tool/mail_editor/` 的源码、精确依赖和 `pnpm-lock.yaml`；`pnpm --dir tool/mail_editor build` 同步生成离线脚本与许可清单。
- 运行资源：`assets/mail_editor/`，由独立 `flutter_inappwebview 6.1.5` 编辑视图加载；原邮件阅读视图继续禁用脚本。
- Tiptap 与 ProseMirror 为 MIT，完整依赖许可由 `build-licenses.mjs` 从锁定的生产与 peer 依赖收集到 `assets/mail_editor/LICENSES.txt`，并登记在 App 许可页。Flutter InAppWebView 为 Apache-2.0，许可随 Flutter 包分发。

## csslib

- Dart csslib 1.0.2（BSD-3-Clause），原为 HTML 依赖的间接组件，现直接用于邮件显示副本的 CSS 声明解析；不执行邮件脚本。上游：[dart-lang/csslib](https://github.com/dart-lang/csslib)。

## DiceBear Glyphs

- 引擎：[dicebear_core](https://pub.dev/packages/dicebear_core) 10.7.0（MIT）；样式：[dicebear_styles](https://pub.dev/packages/dicebear_styles) 10.6.0，仅导入Glyphs。完整依赖许可证随Flutter许可页分发。
- 头像作品：Matt Houser，*Abstract Avatars for All Creative Profile Use*；[DiceBear Glyphs](https://www.dicebear.com/styles/glyphs/)是该作品的remix，采用[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)。[原始作品](https://www.figma.com/community/file/1249154526125777853)。
- 使用范围：默认、匿名头像和分享海报，固定随机种子在本机生成SVG；不调用第三方头像API。未修改头像图形定义，仅按组件尺寸缩放、圆形裁切；公开与匿名身份各自分配。

## Flutter

- [Flutter](https://github.com/flutter/flutter) 与其 SDK/工程脚手架遵循上游 BSD-3-Clause 许可；原始署名保留，完整许可见 [Flutter LICENSE](https://github.com/flutter/flutter/blob/3.44.9/LICENSE)。
- pubspec.lock 锁定的其他依赖保留各自随包许可证；构建客户端时 Flutter 的许可登记仍保留。
