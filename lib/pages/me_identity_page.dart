import '../services/mail_service.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/bnbu_localizations.dart';
import '../models/mail_models.dart';
import '../services/mail_service_factory.dart';
import '../services/me_identity_service.dart';
import '../services/usage_sync_service.dart';

typedef MeMailCredentialsLoader = Future<MailAccessCredentials?> Function();

Future<bool> ensureMeBinding(
  BuildContext context,
  String? owner, {
  MeMailCredentialsLoader? mailCredentials,
}) async {
  if (owner == null || owner.isEmpty) return false;
  await MeIdentityService.shared.restore(owner);
  if (!context.mounted) return false;
  if (MeIdentityService.shared.isBound(owner)) return true;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          MeIdentityPage(owner: owner, mailCredentials: mailCredentials),
    ),
  );
  return MeIdentityService.shared.isBound(owner);
}

class MeIdentityPage extends StatefulWidget {
  const MeIdentityPage({
    super.key,
    required this.owner,
    this.mailCredentials,
    this.embedded = false,
    this.identity,
  });
  final String owner;
  final MeMailCredentialsLoader? mailCredentials;
  final bool embedded;
  final MeIdentityService? identity;
  @override
  State<MeIdentityPage> createState() => _MeIdentityPageState();
}

class _MeIdentityPageState extends State<MeIdentityPage> {
  final _code = TextEditingController();
  late final _identity = widget.identity ?? MeIdentityService.shared;
  final _mail = createMailService();
  String? _challenge, _error;
  bool _busy = false, _reading = false, _autoSubmitted = false;
  int _remaining = 0;
  Timer? _timer;
  DateTime? _sentAt;

  @override
  void initState() {
    super.initState();
    unawaited(
      _identity.restore(widget.owner).catchError((Object _) {
        if (mounted) setState(() => _error = '设备身份存储不可用，请稍后重试。');
      }),
    );
    _remaining = _identity.resendSeconds(widget.owner);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        final remaining = _identity.resendSeconds(widget.owner);
        if (_remaining != remaining) setState(() => _remaining = remaining);
      }
      if (_challenge != null && timer.tick % 5 == 0) unawaited(_readCode());
    });
  }

  Future<void> _sendCode() async {
    if (_busy || _remaining > 0) return;
    setState(() {
      _busy = true;
      _error = null;
      _challenge = null;
      _autoSubmitted = false;
    });
    try {
      final challenge = await _identity.requestCode(widget.owner);
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _sentAt = DateTime.now();
        _remaining = _identity.resendSeconds(widget.owner);
      });
      unawaited(_readCode());
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _remaining = _identity.resendSeconds(widget.owner);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _readCode() async {
    final challenge = _challenge;
    final sent = _sentAt;
    if (_reading ||
        _autoSubmitted ||
        challenge == null ||
        sent == null ||
        widget.mailCredentials == null ||
        DateTime.now().difference(sent).inMinutes >= 10) {
      return;
    }
    _reading = true;
    try {
      final credentials = await widget.mailCredentials!();
      if (!mounted ||
          credentials == null ||
          schoolEmailForUsername(widget.owner) !=
              credentials.emailAddress.toLowerCase()) {
        return;
      }
      final code = await _mail.readMeVerificationCode(
        credentials: credentials,
        challengeId: challenge,
        since: sent,
      );
      if (!mounted || _challenge != challenge || code == null || _busy) return;
      _autoSubmitted = true;
      _code.text = code;
      await _verify();
    } catch (_) {
      // Local mailbox availability never blocks manual verification.
    } finally {
      _reading = false;
    }
  }

  Future<void> _verify() async {
    final challenge = _challenge;
    if (_busy ||
        challenge == null ||
        !RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _identity.verify(widget.owner, challenge, _code.text);
      if (!mounted) return;
      _code.clear();
      setState(() => _challenge = null);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _remaining = _identity.resendSeconds(widget.owner);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recover() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = await _identity.legacyData(widget.owner);
      if (!mounted) return;
      final domains = (preview['domains'] as Map).cast<String, dynamic>();
      final labels = {
        'history': '小U对话历史',
        'personal': '日程、TA与账号设置',
        'memories': '小U记忆',
        'radar': '雷达记录',
      };
      final selected = <String>{};
      final memoryIds = <String>{};
      final memories =
          ((domains['memories'] as Map?)?['entries'] as List?) ?? const [];
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, change) => AlertDialog(
            title: const BnbuText('恢复旧云端数据'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BnbuText(
                    '旧云端记录会保留。恢复只补充新账户中尚不存在的副本；已有新数据不会被替换。旧记录的来源未经当时的邮箱验证，请确认后选择需要恢复的内容。',
                  ),
                  for (final entry in labels.entries)
                    if (entry.key != 'memories' &&
                        (domains[entry.key] as Map?)?['available'] == true)
                      ListTile(
                        title: BnbuText(entry.value),
                        subtitle: const BnbuText('旧副本已隔离保留；本机已有内容继续可用。'),
                      ),
                  if (memories.isNotEmpty) const BnbuText('逐条确认旧记忆'),
                  for (final raw in memories)
                    CheckboxListTile(
                      title: Text((raw as Map)['content'] as String),
                      value: memoryIds.contains(raw['id']),
                      onChanged: (value) => change(() {
                        if (value == true) {
                          memoryIds.add(raw['id'] as String);
                        } else {
                          memoryIds.remove(raw['id']);
                        }
                        if (memoryIds.isNotEmpty) {
                          selected.add('memories');
                        } else {
                          selected.remove('memories');
                        }
                      }),
                    ),
                  if (!domains.values.any(
                    (v) => (v as Map)['available'] == true,
                  ))
                    const BnbuText('没有待恢复的旧云端数据'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const BnbuText('取消'),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(context, true),
                child: const BnbuText('恢复所选副本'),
              ),
            ],
          ),
        ),
      );
      if (accepted != true || !mounted) return;
      final result = await _identity.recoverData(
        widget.owner,
        selected.toList(),
        memoryIds: memoryIds.toList(),
      );
      if (!mounted) return;
      final existing = result['existing'] as List;
      setState(
        () => _error = existing.isEmpty
            ? '恢复完成。开启多端同步后将与本机内容合并。'
            : '新账户已有部分数据，已保留新旧两边副本，未覆盖。',
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _devices() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final devices = await _identity.devices(widget.owner);
      if (!mounted) return;
      final target = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const BnbuText('已授权设备'),
          children: [
            for (final device in devices)
              ListTile(
                title: Text('${device['platform']} · ${device['app_version']}'),
                subtitle: device['current'] == true
                    ? const BnbuText('当前设备')
                    : Text('${device['verified_at']}'),
                trailing: TextButton(
                  onPressed: () =>
                      Navigator.pop(context, device['id'] as String),
                  child: const BnbuText('撤销授权'),
                ),
              ),
          ],
        ),
      );
      if (target != null) await _identity.revoke(widget.owner, target);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    unawaited(_mail.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = ListenableBuilder(
      listenable: _identity,
      builder: (context, _) {
        if (!_identity.isCurrent(widget.owner)) {
          return const Center(child: BnbuText('登录账号已变化，请返回当前账号重新操作。'));
        }
        final bound = _identity.isBound(widget.owner);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                BnbuText(
                  bound ? '已绑定 ME 账户' : '绑定 ME 账户',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                SelectableText(schoolEmailForUsername(widget.owner)),
                const SizedBox(height: 24),
                if (!bound) ...[
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: InputDecoration(
                      labelText: context.l10n.text('邮箱验证码'),
                    ),
                    enabled: !_busy,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _verify(),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton(
                        onPressed: _busy || _remaining > 0 ? null : _sendCode,
                        child: _remaining > 0
                            ? Text('${_remaining}s')
                            : const BnbuText('获取验证码'),
                      ),
                      FilledButton(
                        onPressed:
                            _busy ||
                                _challenge == null ||
                                _code.text.length != 6
                            ? null
                            : _verify,
                        child: const BnbuText('验证并绑定'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ExpansionTile(
                    initiallyExpanded: true,
                    tilePadding: EdgeInsets.zero,
                    title: const BnbuText('为什么需要绑定？'),
                    children: const [
                      BnbuText(
                        '学校登录请求由本机直接发送给学校。BNBU.ME 服务端不接收您的学校密码或登录令牌，因此需要通过邮箱验证码确认邮箱归属。绑定后可使用小U、评论及多端同步；课程、课表、DDL、普通邮箱、TA和自建日程可在本机直接使用。',
                      ),
                      SizedBox(height: 12),
                      BnbuText(
                        '每台设备均需验证一次。重新安装或清除应用数据后需要重新验证，日常使用与正常升级无需重复操作。',
                      ),
                    ],
                  ),
                ] else ...[
                  TextButton(
                    onPressed: _busy ? null : _recover,
                    child: const BnbuText('查看并恢复旧云端数据'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _devices,
                    child: const BnbuText('管理已授权设备'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const BnbuText('多端同步'),
                    value: _identity.syncEnabled(widget.owner),
                    onChanged: _busy
                        ? null
                        : (value) async {
                            setState(() => _busy = true);
                            try {
                              await _identity.setSync(widget.owner, value);
                            } catch (_) {
                              if (mounted) {
                                setState(() => _error = '同步设置保存失败，请重试。');
                              }
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                  ),
                  const BnbuText('开启后同步本机的小U历史、记忆、个人日程和账号设置。关闭后保留本机与已有云端内容。'),
                ],
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Semantics(
                      liveRegion: true,
                      child: BnbuText(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const BnbuText('ME 账户')),
      body: SafeArea(child: content),
    );
  }
}
