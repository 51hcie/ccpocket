import 'package:flutter/material.dart';
import '../../../constants/brand_config.dart';
import '../../../services/android_bridge_update_service.dart';
import '../../../services/bridge_service.dart';
import '../../../theme/app_typography.dart';

Future<void> showAnyCodingUpdateSheet({
  required BuildContext context,
  required BridgeService bridge,
  AndroidBridgeUpdateService? updateService,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => AnyCodingUpdateSheet(
      bridge: bridge,
      updateService: updateService,
    ),
  );
}

class AnyCodingUpdateSheet extends StatefulWidget {
  final BridgeService bridge;
  final AndroidBridgeUpdateService? updateService;

  const AnyCodingUpdateSheet({
    super.key,
    required this.bridge,
    this.updateService,
  });

  @override
  State<AnyCodingUpdateSheet> createState() => _AnyCodingUpdateSheetState();
}

class _AnyCodingUpdateSheetState extends State<AnyCodingUpdateSheet> {
  late final AndroidBridgeUpdateService _service;
  UpdateCheckStatus _status = UpdateCheckStatus.idle;
  BridgeReleaseManifest? _manifest;
  String? _currentVersionName;
  int? _currentVersionCode;
  String? _downloadedApkPath;
  String? _errorMessage;
  int _downloadReceived = 0;
  int _downloadTotal = 0;

  @override
  void initState() {
    super.initState();
    _service = widget.updateService ?? AndroidBridgeUpdateService();
    _initAndCheckUpdate();
  }

  Future<void> _initAndCheckUpdate() async {
    setState(() {
      _status = UpdateCheckStatus.checking;
      _errorMessage = null;
    });

    try {
      _currentVersionName = await _service.getCurrentVersionName();
      final bridgeUrl = widget.bridge.lastUrl ?? 'ws://127.0.0.1:8766';
      final manifest = await _service.fetchManifest(bridgeUrl);
      final hasUpdate = await _service.isUpdateAvailable(manifest);

      if (mounted) {
        setState(() {
          _manifest = manifest;
          _status = hasUpdate
              ? UpdateCheckStatus.updateAvailable
              : UpdateCheckStatus.upToDate;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = UpdateCheckStatus.error;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _startDownload() async {
    if (_manifest == null) return;
    setState(() {
      _status = UpdateCheckStatus.downloading;
      _downloadReceived = 0;
      _downloadTotal = _manifest!.size;
      _errorMessage = null;
    });

    try {
      final bridgeUrl = widget.bridge.lastUrl ?? 'ws://127.0.0.1:8766';
      final apkPath = await _service.downloadAndVerifyApk(
        bridgeUrl: bridgeUrl,
        manifest: _manifest!,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              _downloadReceived = received;
              _downloadTotal = total > 0 ? total : _manifest!.size;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _downloadedApkPath = apkPath;
          _status = UpdateCheckStatus.readyToInstall;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = UpdateCheckStatus.error;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _launchInstaller() async {
    if (_downloadedApkPath == null) return;
    try {
      await _service.launchInstaller(_downloadedApkPath!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('调起安装程序失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark
        ? BrandConfig.anyCodingSurfaceDark
        : cs.surfaceContainerLowest;
    final cardBgColor = isDark
        ? BrandConfig.anyCodingCardDark
        : cs.surface;
    final borderColor = isDark
        ? BrandConfig.anyCodingBorderDark
        : cs.outlineVariant.withValues(alpha: 0.35);

    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.system_update_alt_rounded,
                          color: cs.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('检查 AnyCoding 更新', style: AppTypography.titleLarge(context)),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Content based on status
              if (_status == UpdateCheckStatus.checking) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(strokeWidth: 2.5),
                      const SizedBox(height: 16),
                      Text(
                        '正在从当前 Mac Bridge 获取版本清单...',
                        style: AppTypography.bodyMedium(context),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.bridge.lastUrl ?? 'ws://127.0.0.1:8766',
                        style: AppTypography.caption(context),
                      ),
                    ],
                  ),
                ),
              ] else if (_status == UpdateCheckStatus.error) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.error.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.error_outline_rounded, color: cs.error, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '更新检查失败',
                            style: AppTypography.titleSmall(context, color: cs.error),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage ?? '无法连接到 Bridge 服务',
                        style: AppTypography.bodySmall(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重试'),
                  onPressed: _initAndCheckUpdate,
                ),
              ] else if (_status == UpdateCheckStatus.upToDate) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF10B981),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '已是最新版本',
                              style: AppTypography.titleSmall(
                                context,
                                color: const Color(0xFF10B981),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '当前版本: v${_currentVersionName ?? '1.115.2'} (Build ${_manifest?.versionCode ?? 217})',
                              style: AppTypography.caption(context),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('重新下载当前版本 APK'),
                  onPressed: _startDownload,
                ),
              ] else if (_status == UpdateCheckStatus.updateAvailable ||
                  _status == UpdateCheckStatus.downloading ||
                  _status == UpdateCheckStatus.readyToInstall) ...[
                // Version Info Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardBgColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('发现新版本', style: AppTypography.titleMedium(context)),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'v${_manifest?.versionName ?? '1.115.3'} (Build ${_manifest?.versionCode ?? 218})',
                              style: AppTypography.labelSmall(
                                context,
                                color: cs.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_manifest?.changelog.isNotEmpty ?? false) ...[
                        Text(
                          '更新说明',
                          style: AppTypography.labelSmall(context),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _manifest!.changelog,
                          style: AppTypography.bodySmall(context),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        children: [
                          Text(
                            '大小: ${((_manifest?.size ?? 0) / (1024 * 1024)).toStringAsFixed(1)} MB',
                            style: AppTypography.caption(context),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            '来源: 当前 Mac Bridge',
                            style: AppTypography.caption(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Download Progress
                if (_status == UpdateCheckStatus.downloading) ...[
                  LinearProgressIndicator(
                    value: _downloadTotal > 0
                        ? _downloadReceived / _downloadTotal
                        : null,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '正在从 Bridge 下载 APK...',
                        style: AppTypography.caption(context),
                      ),
                      Text(
                        '${((_downloadReceived) / (1024 * 1024)).toStringAsFixed(1)} / ${((_downloadTotal) / (1024 * 1024)).toStringAsFixed(1)} MB',
                        style: AppTypography.mono(context, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ] else if (_status == UpdateCheckStatus.readyToInstall) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.verified_rounded,
                          color: Color(0xFF10B981),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'SHA-256 哈希校验通过 · 证书指纹一致',
                            style: AppTypography.bodySmall(
                              context,
                              color: const Color(0xFF10B981),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(Icons.install_mobile_rounded, size: 20),
                    label: const Text('启动系统安装程序'),
                    onPressed: _launchInstaller,
                  ),
                ] else ...[
                  FilledButton.icon(
                    icon: const Icon(Icons.download_rounded, size: 20),
                    label: const Text('下载并安装更新'),
                    onPressed: _startDownload,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
