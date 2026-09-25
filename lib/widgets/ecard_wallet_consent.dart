import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

const ecardWalletDataConsent =
    '本次将把 eCard 的照片、中英文姓名、学号、学院与学生身份，通过加密连接临时发送至 BNBU.ME 签发服务，仅用于生成钱包卡片。钱包不包含性别，本次不会上传性别；不写入数据库或日志，不发送学校密码、Cookie 或令牌。';
const ecardWalletCopyConsent =
    '钱包保留独立副本，可能随你的 Apple 钱包设置同步至其他 Apple 设备；退出 BNBU.ME 不会自动移除，请在钱包中手动删除。资料仅为本次快照，不自动更新，不支持 NFC、门禁或支付。'
    '\n\n点按下方按钮表示同意本次传输，随后仍需在系统钱包界面确认添加。';

class EcardWalletConsentDialog extends StatelessWidget {
  const EcardWalletConsentDialog({super.key, this.buttonBuilder});
  final Widget Function(VoidCallback onPressed)? buttonBuilder;

  @override
  Widget build(BuildContext context) {
    void confirm() => Navigator.of(context).pop(true);
    return AlertDialog(
      title: Text(context.l10n.text('添加到 Apple 钱包')),
      content: SingleChildScrollView(
        child: Text(
          '${context.l10n.text(ecardWalletDataConsent)}\n\n${context.l10n.text(ecardWalletCopyConsent)}',
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        SizedBox(
          width: 220,
          height: 48,
          child:
              buttonBuilder?.call(confirm) ??
              EcardWalletAddButton(onPressed: confirm),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.text('取消')),
        ),
      ],
    );
  }
}

/// Apple's official localized PKAddPassButton, not a recreated Wallet badge.
class EcardWalletAddButton extends StatefulWidget {
  const EcardWalletAddButton({super.key, required this.onPressed});
  final VoidCallback onPressed;
  @override
  State<EcardWalletAddButton> createState() => _EcardWalletAddButtonState();
}

class _EcardWalletAddButtonState extends State<EcardWalletAddButton> {
  MethodChannel? _channel;
  bool _pressed = false;
  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UiKitView(
    viewType: 'bnbu/wallet_add_button',
    onPlatformViewCreated: (id) {
      final channel = MethodChannel('bnbu/wallet_add_button/$id');
      _channel = channel;
      channel.setMethodCallHandler((call) async {
        if (call.method == 'pressed' && mounted && !_pressed) {
          _pressed = true;
          widget.onPressed();
        }
      });
    },
  );
}
