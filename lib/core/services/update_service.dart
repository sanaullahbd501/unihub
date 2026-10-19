import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_constants.dart';
import 'supabase_service.dart';

class AppUpdateInfo {
  final String latestVersion;
  final int buildNumber;
  final String downloadUrl;
  final String releaseNotes;
  final bool isForceUpdate;

  AppUpdateInfo({
    required this.latestVersion,
    required this.buildNumber,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.isForceUpdate,
  });
}

class UpdateService {
  static final _supabase = SupabaseService.client;
  static bool _dialogShowing = false;

  /// Checks if a newer version exists in the database
  static Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final platform = kIsWeb ? 'web' : 'android';
      final res = await _supabase
          .from('app_versions')
          .select()
          .eq('platform', platform)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (res == null) return null;

      final latestVer = (res['latest_version'] ?? '1.0.0').toString();
      final latestBuild = (res['build_number'] as num?)?.toInt() ?? 1;
      final downloadUrl = (res['download_url'] ?? '').toString();
      final releaseNotes = (res['release_notes'] ?? 'General improvements and bug fixes').toString();
      final isForceUpdate = res['is_force_update'] == true;

      // Check if remote version is newer than installed app version
      final isNewer = latestBuild > AppConstants.buildNumber || _isSemanticVersionGreater(latestVer, AppConstants.appVersion);

      if (isNewer && downloadUrl.isNotEmpty) {
        return AppUpdateInfo(
          latestVersion: latestVer,
          buildNumber: latestBuild,
          downloadUrl: downloadUrl,
          releaseNotes: releaseNotes,
          isForceUpdate: isForceUpdate,
        );
      }
    } catch (e) {
      debugPrint('Check for update error: $e');
    }
    return null;
  }

  /// Simple semver compare (e.g. 1.0.1 > 1.0.0)
  static bool _isSemanticVersionGreater(String remote, String local) {
    try {
      final rParts = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final lParts = local.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      for (int i = 0; i < 3; i++) {
        final r = i < rParts.length ? rParts[i] : 0;
        final l = i < lParts.length ? lParts[i] : 0;
        if (r > l) return true;
        if (r < l) return false;
      }
    } catch (_) {}
    return false;
  }

  /// Displays the In-App Update / Download Dialog if an update is available
  static Future<void> checkAndShowUpdateDialog(BuildContext context) async {
    if (_dialogShowing) return;
    final info = await checkForUpdate();
    if (info == null || !context.mounted) return;

    _dialogShowing = true;

    await showDialog(
      context: context,
      barrierDismissible: !info.isForceUpdate,
      builder: (ctx) {
        return PopScope(
          canPop: !info.isForceUpdate,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.system_update_rounded,
                    color: Theme.of(ctx).colorScheme.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'New Update Available!',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      Text(
                        'v${info.latestVersion} is now available',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  'What\'s New / নতুন যা যুক্ত হয়েছে:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Theme.of(ctx).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(ctx).colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    info.releaseNotes,
                    style: const TextStyle(fontSize: 13, height: 1.45),
                  ),
                ),
                if (info.isForceUpdate) ...[
                  const SizedBox(height: 12),
                  const Text(
                    '⚠️ This update is required to continue using UniHub.',
                    style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    if (!info.isForceUpdate)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Later (পরে)'),
                        ),
                      ),
                    if (!info.isForceUpdate) const SizedBox(width: 12),
                    Expanded(
                      flex: info.isForceUpdate ? 1 : 2,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.download_rounded, size: 20),
                        label: Text(kIsWeb ? 'Refresh Now (রিলোড)' : 'Download APK (আপডেট)'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          final uri = Uri.parse(info.downloadUrl);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                          if (!info.isForceUpdate && ctx.mounted) {
                            Navigator.of(ctx).pop();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    _dialogShowing = false;
  }
}
