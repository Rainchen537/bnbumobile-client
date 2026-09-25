# BNBU.ME 客户端协作规则

本仓库只包含客户端。阅读 README.md、CONTRIBUTING.md 与 THIRD_PARTY_NOTICES.md 后再修改。

- 保持现有 Flutter 设计和平台行为；只修改任务所需文件。
- 保留他人的工作树修改；开始前检查 Git 根目录、分支、remote、status 和 diff。
- 所有测试使用合成数据，禁止读取或提交真实学校账号、邮件、Cookie、token、个人身份和签名材料。
- 学校登录态由 AppSessionController 统一持有；页面不能新建独立认证链路。
- 使用可注入服务测试远端能力；server/ 只有范围说明，不加入生产实现或运营数据。
- 运行 dart format、flutter analyze 和受影响测试；涉及平台工程时补充相应构建。结束后关闭本轮模拟器和临时应用。
- 不自动部署、上传商店、安装到他人设备或运行 GitHub Actions。
- 文档分工：README 维护构建与功能边界；CONTRIBUTING 维护贡献流程；SECURITY 维护报告方式；THIRD_PARTY_NOTICES 维护组件与素材许可；server/README 说明服务端范围；LICENSE 是自有代码许可证正文。
