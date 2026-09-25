# BNBU.ME 客户端

BNBU.ME 是面向 BNBU 学生的非官方 Flutter 校园客户端，提供课程、课表、DDL、邮箱、校园服务和小U入口。

本仓库公开客户端源码，采用 **GPL-3.0-only**；服务端实现、管理后台、运营数据和正式签名材料不在公开范围。原作者及贡献者保留各自著作权。第三方组件保留原许可证，见 [第三方声明](THIRD_PARTY_NOTICES.md)。产品名称与标识不授予冒充官方发行版或获得官方背书的权利。

## 开发

工具链：Flutter **3.44.9**（Dart 随 SDK）、Android Java **17**；Apple 构建需要 macOS/Xcode，CocoaPods **1.16.2**。

```bash
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --debug
# 在 Mac 上执行无签名 iOS 编译：
flutter build ios --debug --no-codesign
```

通用质量检查：`bash tool/check.sh`。邮件编辑器源码位于 `tool/mail_editor/`，使用锁文件安装依赖并构建离线资源；生成资源和许可证清单也随本仓库分发。

## 配置与运行范围

复制 `config/dart_defines.example.json` 为被忽略的 `config/dart_defines.local.json`，通过 `flutter run --dart-define-from-file=config/dart_defines.local.json` 运行。配置文件只能存服务地址等公开配置，不能包含秘密。

- 学校登录由客户端直接连接学校，学校密码、Cookie及登录令牌保存在设备端，不发送给BNBU.ME服务端。学校功能仍受学校权限和服务规则约束。
- TA和个人日程可在本机创建、编辑和保存。ME账户通过邮箱验证码绑定；小U、评论及多端同步需要绑定，多端同步由每台设备单独开启。切换学校账号时保留各自本机数据。
- 小U、同步、校园内容、Wallet 等远端能力需要相应服务支持。客户端开源不授予生产管理权限、免费额度或无限制接口使用权，也不提供可自行部署的服务端。
- 公开构建保留客户端逻辑，内置机构目录和教师历史评价数据为空；在线公开目录仍由服务提供。学校手绘地图不随源码分发，页面在联网取得地图后可缓存使用，首次离线没有内置地图。
- 测试使用合成数据；校历协议测试从客户端自带的公开校历规则生成 fixture，不读取任何服务端文件。
- 发布用的签名、账户和个人配置不提供。Apple 通用模板位于 `ios/Flutter/`、`macos/Flutter/`，使用自己的 Team 和开发前缀；Android 使用自己的调试或分发密钥。自行构建的包不能冒充或覆盖官方签名发行版。
- Android/iOS 是主要支持平台，macOS/Windows 为桌面预览，Web/Linux 仅保留工程脚手架。

## 参与贡献

欢迎通过 Issue 和 Pull Request 参与。维护者审查、测试并整合贡献后发布更新，作者署名会保留；详见 [贡献说明](CONTRIBUTING.md)。本仓库从首个公开快照建立独立历史，未导入内部开发历史。仓库未配置自动运行的 GitHub Actions。

安全问题请按 [安全说明](SECURITY.md) 私下报告，不在公开 Issue 中提交账号、邮件、令牌或私密数据。

## 了解 BNBU.ME

想查看应用的功能介绍、界面展示和支持平台，请访问 [bnbu.me](https://bnbu.me/) 或 [bnbu.yunwai.cloud](https://bnbu.yunwai.cloud/)。

## 下载 BNBU.ME

IOS用户可在 App Store 搜索 `BNBU.ME` 下载；其他平台用户可通过以下官网页面下载安装：

- [https://bnbu.me/download](https://bnbu.me/download)
- [https://bnbu.yunwai.cloud/download](https://bnbu.yunwai.cloud/download)
