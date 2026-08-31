import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

typedef RouteHealthProbe = Future<Map<String, dynamic>?> Function(String url);

/// Transport metadata only. Credentials and conversation data are never stored.
class BridgeRouteSelector {
  BridgeRouteSelector({RouteHealthProbe? probe}) : _probe = probe ?? _health;
  final RouteHealthProbe _probe;
  String? anchor;
  String? bridgeId;
  final Map<String, int?> latency = {};
  final Set<String> verified = {};
  final Set<String> _mismatched = {};
  final Set<String> _presetSeeds = {};
  String reason = '等待连接检测';
  DateTime? _lastSwitch;
  int _generation = 0;

  static String origin(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !['ws', 'wss'].contains(uri.scheme) || uri.host.isEmpty)
      return '';
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path == '/' ? '' : uri.path,
    ).toString();
  }

  bool sameServer(String a, String b) =>
      (origin(a).isNotEmpty && origin(a) == origin(b)) ||
      (bridgeId != null &&
          !_mismatched.contains(origin(a)) &&
          !_mismatched.contains(origin(b)) &&
          (origin(a) == anchor || verified.contains(origin(a))) &&
          (origin(b) == anchor || verified.contains(origin(b))));

  Future<void> configure(String url) async {
    final clean = origin(url);
    if (clean.isEmpty) return;
    if (anchor == clean || verified.contains(clean)) return;
    final generation = ++_generation;
    anchor = clean;
    bridgeId = null;
    latency.clear();
    verified.clear();
    _mismatched.clear();
    _presetSeeds.clear();
    reason = '正在发现此 Mac 的连接地址';
    _lastSwitch = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonDecode(prefs.getString('bridge_routes:$clean') ?? '{}');
      if (_generation != generation) return;
      if (data is Map && data['id'] is String && data['urls'] is List) {
        bridgeId = data['id'] as String;
        for (final value in (data['urls'] as List).take(12)) {
          if (value is String && _allowed(value, clean)) latency[value] = null;
        }
      }
    } catch (_) {
      /* Old or unavailable preferences: rediscover online. */
    }
    if (_generation == generation) {
      latency[clean] = null;
      const preset = String.fromEnvironment('MACREMOTE_BRIDGE_URL');
      const alternates = String.fromEnvironment('MACREMOTE_BRIDGE_ALTERNATES');
      if (preset.isNotEmpty && origin(preset) == clean) {
        for (final seed in alternates.split(',')) {
          if (_allowed(seed.trim(), clean)) {
            _presetSeeds.add(seed.trim());
            latency[seed.trim()] = null;
          }
        }
      }
    }
  }

  void invalidate() {
    _generation++;
  }

  Future<String> select(
    String current, {
    bool connected = false,
    bool busy = false,
  }) async {
    final generation = _generation;
    final clean = origin(current);
    if (clean.isEmpty) return current;
    final results = <String, Map<String, dynamic>>{};
    // Every selectable latency belongs to this cycle, never to an old probe.
    for (final key in latency.keys.toList()) {
      latency[key] = null;
    }
    Future<void> probeOne(String url) async {
      final timer = Stopwatch()..start();
      Map<String, dynamic>? health;
      try {
        health = await _probe(url).timeout(const Duration(seconds: 2));
      } catch (_) {
        health = null;
      }
      if (_generation != generation) return;
      latency[url] = null;
      if (health?['status'] == 'ok') {
        results[url] = health!;
        // Identity is checked after all probes, before using a route.
        latency[url] = timer.elapsedMilliseconds;
      }
    }

    await Future.wait(
      {
        clean,
        if (anchor != null) anchor!,
        ...latency.keys,
      }.take(12).map(probeOne),
    );
    if (_generation != generation) return current;
    final rootHealth = results[anchor];
    var rootNetwork = rootHealth?['network'];
    if (bridgeId == null && rootNetwork == null) {
      for (final seed in _presetSeeds) {
        if (results[seed]?['network'] is Map) {
          rootNetwork = results[seed]!['network'];
          break;
        }
      }
    }
    if (rootNetwork is Map && rootNetwork['bridgeId'] is String) {
      final newId = rootNetwork['bridgeId'] as String;
      // DHCP can reassign the anchor to another Mac. Never adopt its identity
      // or send it credentials merely because it now owns that IP address.
      bridgeId ??= newId;
    }
    if (bridgeId == null) {
      reason = rootHealth == null ? '地址暂不可达，等待重连' : '此 Bridge 暂不支持多通道';
      return current;
    }
    final discovered = <String>{};
    for (final health in results.values) {
      final network = health['network'];
      if (network is! Map || network['bridgeId'] != bridgeId) continue;
      final urls = network['endpoints'];
      if (urls is List) {
        for (final url in urls.take(12)) {
          if (url is String && _allowed(url, clean)) discovered.add(url);
        }
      }
    }
    final candidates = {
      clean,
      if (anchor != null) anchor!,
      ...discovered,
      ...latency.keys,
    }.take(12).toSet();
    latency.removeWhere((url, _) => !candidates.contains(url));
    verified.removeWhere((url) => !candidates.contains(url));
    results.removeWhere((url, _) => !candidates.contains(url));
    await Future.wait(
      candidates.where((url) => !latency.containsKey(url)).map(probeOne),
    );
    if (_generation != generation) return current;
    for (final url in results.keys) {
      final network = results[url]!['network'];
      if (network is Map && network['bridgeId'] == bridgeId) {
        verified.add(url);
        _mismatched.remove(url);
      } else {
        latency[url] = null;
        verified.remove(url);
        _mismatched.add(url);
      }
    }
    final available =
        results.keys
            .where((url) => latency[url] != null && verified.contains(url))
            .toList()
          ..sort((a, b) => latency[a]!.compareTo(latency[b]!));
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_generation != generation) return current;
      await prefs.setString(
        'bridge_routes:$anchor',
        jsonEncode({'id': bridgeId, 'urls': latency.keys.take(12).toList()}),
      );
    } catch (_) {
      /* Persistence failure must not break an existing connection. */
    }
    if (_generation != generation || available.isEmpty) {
      reason = '所有已知通道暂不可达，保留任务并重试';
      return current;
    }
    final best = available.first;
    final now = DateTime.now();
    final currentMs = latency[clean];
    if (connected &&
        currentMs != null &&
        (busy ||
            (best == clean ||
                currentMs - latency[best]! < 40 ||
                (_lastSwitch != null &&
                    now.difference(_lastSwitch!).inSeconds < 60)))) {
      reason = busy ? '任务执行中，保持当前通道' : '当前通道稳定，避免频繁切换';
      return current;
    }
    if (best == clean) {
      reason = '当前通道可达';
      return current;
    }
    _lastSwitch = now;
    reason = connected ? '已选择延迟更低的通道' : '已选择可达通道重新连接';
    // Query credentials stay in memory and are copied only to verified siblings.
    final query = Uri.parse(current).query;
    return query.isEmpty
        ? best
        : Uri.parse(best).replace(query: query).toString();
  }

  static bool _allowed(String url, String root) {
    final uri = Uri.tryParse(url);
    final source = Uri.parse(root);
    return uri != null &&
        uri.scheme == source.scheme &&
        uri.hasPort &&
        uri.port == source.port &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        (uri.path.isEmpty || uri.path == '/');
  }

  static Future<Map<String, dynamic>?> _health(String url) async {
    final uri = Uri.parse(url);
    final response = await http
        .get(
          Uri(
            scheme: uri.scheme == 'wss' ? 'https' : 'http',
            host: uri.host,
            port: uri.hasPort ? uri.port : null,
            path: '/health',
          ),
        )
        .timeout(const Duration(seconds: 2));
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body);
    return data is Map<String, dynamic> ? data : null;
  }
}
