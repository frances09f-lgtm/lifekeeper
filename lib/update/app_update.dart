import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// In-app self-update, requested by the user: a "Check for updates" button
/// in Settings fetches the latest GitHub release, shows a "Software Update"
/// dialog with the release notes, downloads the APK in-app with a progress
/// bar, and hands it to the Android package installer. Nothing checks in
/// the background: the network is only touched when the user taps the
/// button. If the in-app download or install handoff fails, the dialog
/// offers the release page in the browser as a fallback.

const kUpdateRepo = 'frances09f-lgtm/lifekeeper';

class UpdateInfo {
  final String version; // e.g. 1.1.5 (tag without the leading v)
  final String notes; // release body ("What's new")
  final String apkUrl; // browser_download_url of the .apk asset
  final String pageUrl; // release page, for the browser fallback
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.apkUrl,
    required this.pageUrl,
  });
}

/// Outcome of an update check that separates "no newer version" from
/// "the check itself failed" (offline, rate limit, unexpected payload), so a
/// user-initiated check can say the check failed instead of claiming the app
/// is up to date.
enum UpdateCheckStatus { updateAvailable, upToDate, failed }

class UpdateCheck {
  final UpdateCheckStatus status;
  final UpdateInfo? info;
  const UpdateCheck._(this.status, this.info);
  const UpdateCheck.available(UpdateInfo info)
    : this._(UpdateCheckStatus.updateAvailable, info);
  const UpdateCheck.upToDate() : this._(UpdateCheckStatus.upToDate, null);
  const UpdateCheck.failed() : this._(UpdateCheckStatus.failed, null);
}

/// Numeric semver-ish compare: returns >0 when a > b. Ignores a leading v
/// and any +build suffix; missing segments count as 0.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split('+')
      .first
      .split('.')
      .map((s) => int.tryParse(s) ?? 0)
      .toList();
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < pa.length || i < pb.length; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x - y;
  }
  return 0;
}

class UpdateChecker {
  UpdateChecker({
    http.Client? client,
    Future<String> Function()? currentVersion,
    Future<String> Function(String apkPath)? installer,
    Future<Directory> Function()? cacheDir,
    Future<File> Function(
      UpdateInfo info, {
      void Function(int received, int? total)? onProgress,
      Stream<void>? cancelToken,
    })?
    downloader,
  }) : _client = client ?? http.Client(),
       _currentVersion =
           currentVersion ??
           (() async => (await PackageInfo.fromPlatform()).version),
       _installer = installer ?? _defaultInstall,
       _cacheDir = cacheDir ?? getTemporaryDirectory,
       _downloader = downloader;

  final http.Client _client;
  final Future<String> Function() _currentVersion;
  final Future<String> Function(String) _installer;
  final Future<Directory> Function() _cacheDir;
  final Future<File> Function(
    UpdateInfo info, {
    void Function(int received, int? total)? onProgress,
    Stream<void>? cancelToken,
  })?
  _downloader;

  /// Hands the downloaded APK to the system package installer. Android shows
  /// its own confirm screen (and, the first time, its "install unknown apps"
  /// prompt); throws with the opener's message when the handoff fails.
  static Future<String> _defaultInstall(String path) async {
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      throw StateError(
        result.message.isNotEmpty
            ? result.message
            : 'The installer did not open. Allow installs from this app, '
                  'or use "Open download page" instead.',
      );
    }
    return 'ok';
  }

  /// Latest published release, or null when there is nothing newer or the
  /// check fails (offline, rate limit): callers treat null as "no update".
  /// Use [fetchLatestDetailed] when the caller must tell a failed check
  /// apart from "up to date".
  Future<UpdateInfo?> fetchLatest() async =>
      (await fetchLatestDetailed()).info;

  /// Like [fetchLatest] but reports [UpdateCheckStatus.failed] when the
  /// check itself did not complete, so a user-initiated check can say so
  /// instead of claiming the app is up to date.
  Future<UpdateCheck> fetchLatestDetailed() async {
    try {
      final res = await _client
          .get(
            Uri.parse(
              'https://api.github.com/repos/$kUpdateRepo/releases/latest',
            ),
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'lifekeeper-app',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return const UpdateCheck.failed();
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = (j['tag_name'] as String? ?? '').trim();
      if (tag.isEmpty) return const UpdateCheck.failed();
      String? apk;
      for (final a in (j['assets'] as List? ?? const [])) {
        final name = (a as Map)['name'] as String? ?? '';
        if (name.toLowerCase().endsWith('.apk')) {
          apk = a['browser_download_url'] as String?;
          break;
        }
      }
      if (apk == null) return const UpdateCheck.failed();
      final info = UpdateInfo(
        version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
        notes: (j['body'] as String? ?? '').trim(),
        apkUrl: apk,
        pageUrl: (j['html_url'] as String? ?? '').trim(),
      );
      final current = await _currentVersion();
      return compareVersions(info.version, current) > 0
          ? UpdateCheck.available(info)
          : const UpdateCheck.upToDate();
    } catch (_) {
      return const UpdateCheck.failed();
    }
  }

  /// Download the APK to the cache dir with byte progress. [onProgress]
  /// gets (received, total-or-null). Cancel by closing [cancelToken].
  Future<File> download(
    UpdateInfo info, {
    void Function(int received, int? total)? onProgress,
    Stream<void>? cancelToken,
  }) async {
    if (_downloader != null) {
      return _downloader(
        info,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    }
    final req = http.Request('GET', Uri.parse(info.apkUrl));
    req.headers['User-Agent'] = 'lifekeeper-app';
    final res = await _client.send(req).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw StateError('download failed (HTTP ${res.statusCode})');
    }
    final dir = Directory(
      '${(await _cacheDir()).path}${Platform.pathSeparator}updates',
    );
    await dir.create(recursive: true);
    final file = File(
      '${dir.path}${Platform.pathSeparator}lifekeeper-${info.version}.apk',
    );
    final sink = file.openWrite();
    var received = 0;
    final sub = cancelToken?.listen((_) => res.stream.listen(null).cancel());
    try {
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, res.contentLength);
      }
    } finally {
      await sub?.cancel();
      await sink.flush();
      await sink.close();
    }
    return file;
  }

  Future<String> install(File apk) => _installer(apk.path);
}

/// Manual "Check for updates" from Settings: always fetches, reports when
/// up to date, and says so plainly when the check itself failed.
Future<void> checkUpdateManually(
  BuildContext context, {
  UpdateChecker? checker,
}) async {
  final c = checker ?? UpdateChecker();
  final result = await c.fetchLatestDetailed();
  if (!context.mounted) return;
  if (result.status == UpdateCheckStatus.failed) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Couldn't check for updates. Check your connection and try again.",
        ),
      ),
    );
    return;
  }
  final info = result.info;
  if (info == null) {
    final v = await PackageInfo.fromPlatform()
        .then((p) => p.version)
        .catchError((_) => '');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          v.isEmpty ? 'No update available' : 'LifeKeeper $v is up to date',
        ),
      ),
    );
    return;
  }
  await showUpdateDialog(context, info, checker: c);
}

enum _Phase { available, downloading, installing, error }

Future<void> showUpdateDialog(
  BuildContext context,
  UpdateInfo info, {
  UpdateChecker? checker,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        UpdateDialog(info: info, checker: checker ?? UpdateChecker()),
  );
}

class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  final UpdateChecker checker;
  const UpdateDialog({super.key, required this.info, required this.checker});
  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  _Phase phase = _Phase.available;
  int received = 0;
  int? total;
  String? error;
  final _cancel = StreamController<void>();

  @override
  void dispose() {
    _cancel.close();
    super.dispose();
  }

  Future<void> _download() async {
    setState(() {
      phase = _Phase.downloading;
      received = 0;
      total = null;
      error = null;
    });
    try {
      final apk = await widget.checker.download(
        widget.info,
        onProgress: (r, t) {
          if (mounted) {
            setState(() {
              received = r;
              total = t;
            });
          }
        },
        cancelToken: _cancel.stream,
      );
      if (!mounted) return;
      setState(() => phase = _Phase.installing);
      // Android always shows its own package-installer confirm screen; that
      // tap is the system's, not ours.
      await widget.checker.install(apk);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        phase = _Phase.error;
        error = e.toString();
      });
    }
  }

  Future<void> _openPage() async {
    final url = widget.info.pageUrl.isNotEmpty
        ? widget.info.pageUrl
        : widget.info.apkUrl;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).colorScheme.onSurfaceVariant;
    final v = widget.info.version;
    final progress = total != null && total! > 0
        ? (received / total!).clamp(0.0, 1.0)
        : null;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Software Update', textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              switch (phase) {
                _Phase.available => 'LifeKeeper $v is available',
                _Phase.downloading => 'Downloading LifeKeeper $v...',
                _Phase.installing => 'Opening installer...',
                _Phase.error => 'Update failed',
              },
              style: TextStyle(color: dim, fontSize: 13),
            ),
          ),
          if (phase == _Phase.downloading) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 4),
            Text(
              total != null
                  ? '${(received / 1e6).toStringAsFixed(1)} / ${(total! / 1e6).toStringAsFixed(1)} MB'
                  : '${(received / 1e6).toStringAsFixed(1)} MB',
              style: TextStyle(color: dim, fontSize: 11),
            ),
          ],
          if (phase == _Phase.error)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error ?? 'Something went wrong.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          if (widget.info.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              "What's new",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                child: Text(
                  widget.info.notes,
                  style: TextStyle(fontSize: 12, color: dim),
                ),
              ),
            ),
          ],
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        if (phase == _Phase.available) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          FilledButton(onPressed: _download, child: const Text('Update')),
        ],
        if (phase == _Phase.downloading)
          TextButton(
            onPressed: () {
              _cancel.add(null);
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
        if (phase == _Phase.error) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (widget.info.pageUrl.isNotEmpty)
            TextButton(
              onPressed: _openPage,
              child: const Text('Open download page'),
            ),
          FilledButton(onPressed: _download, child: const Text('Retry')),
        ],
      ],
    );
  }
}
