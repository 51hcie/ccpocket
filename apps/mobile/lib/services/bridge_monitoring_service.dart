import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'android_bridge_update_service.dart';

class SystemCpuMetrics {
  final String model;
  final int cores;
  final int speedMHz;
  final double loadPercent;

  const SystemCpuMetrics({
    required this.model,
    required this.cores,
    required this.speedMHz,
    required this.loadPercent,
  });

  factory SystemCpuMetrics.fromJson(Map<String, dynamic> json) {
    return SystemCpuMetrics(
      model: json['model'] as String? ?? 'Apple Silicon / Generic CPU',
      cores: json['cores'] as int? ?? 1,
      speedMHz: json['speedMHz'] as int? ?? 0,
      loadPercent: (json['loadPercent'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class SystemMemoryMetrics {
  final int totalBytes;
  final int freeBytes;
  final int usedBytes;
  final double usedPercent;

  const SystemMemoryMetrics({
    required this.totalBytes,
    required this.freeBytes,
    required this.usedBytes,
    required this.usedPercent,
  });

  factory SystemMemoryMetrics.fromJson(Map<String, dynamic> json) {
    return SystemMemoryMetrics(
      totalBytes: json['totalBytes'] as int? ?? 0,
      freeBytes: json['freeBytes'] as int? ?? 0,
      usedBytes: json['usedBytes'] as int? ?? 0,
      usedPercent: (json['usedPercent'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class SystemDiskMetrics {
  final bool available;
  final int totalBytes;
  final int freeBytes;
  final int usedBytes;
  final double usedPercent;
  final String mountPoint;
  final String? error;

  const SystemDiskMetrics({
    required this.available,
    required this.totalBytes,
    required this.freeBytes,
    required this.usedBytes,
    required this.usedPercent,
    required this.mountPoint,
    this.error,
  });

  factory SystemDiskMetrics.fromJson(Map<String, dynamic> json) {
    return SystemDiskMetrics(
      available: json['available'] as bool? ?? false,
      totalBytes: json['totalBytes'] as int? ?? 0,
      freeBytes: json['freeBytes'] as int? ?? 0,
      usedBytes: json['usedBytes'] as int? ?? 0,
      usedPercent: (json['usedPercent'] as num?)?.toDouble() ?? 0.0,
      mountPoint: json['mountPoint'] as String? ?? '/',
      error: json['error'] as String?,
    );
  }
}

class SystemMetricsModel {
  final bool available;
  final String hostname;
  final String os;
  final int systemUptime;
  final SystemCpuMetrics cpu;
  final SystemMemoryMetrics memory;
  final SystemDiskMetrics disk;
  final List<double> loadAverage;
  final String source;
  final String? error;

  const SystemMetricsModel({
    required this.available,
    required this.hostname,
    required this.os,
    required this.systemUptime,
    required this.cpu,
    required this.memory,
    required this.disk,
    required this.loadAverage,
    required this.source,
    this.error,
  });

  factory SystemMetricsModel.fromJson(Map<String, dynamic> json) {
    return SystemMetricsModel(
      available: json['available'] as bool? ?? true,
      hostname: json['hostname'] as String? ?? 'Mac Host',
      os: json['os'] as String? ?? 'macOS',
      systemUptime: json['systemUptime'] as int? ?? 0,
      cpu: SystemCpuMetrics.fromJson(
        json['cpu'] as Map<String, dynamic>? ?? {},
      ),
      memory: SystemMemoryMetrics.fromJson(
        json['memory'] as Map<String, dynamic>? ?? {},
      ),
      disk: SystemDiskMetrics.fromJson(
        json['disk'] as Map<String, dynamic>? ?? {},
      ),
      loadAverage:
          (json['loadAverage'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [0.0, 0.0, 0.0],
      source: json['source'] as String? ?? 'macOS Kernel / OS Runtime',
      error: json['error'] as String?,
    );
  }
}

class BridgeTaskCountsModel {
  final int running;
  final int queued;
  final int completed;
  final int failed;

  const BridgeTaskCountsModel({
    required this.running,
    required this.queued,
    required this.completed,
    required this.failed,
  });

  factory BridgeTaskCountsModel.fromJson(Map<String, dynamic> json) {
    return BridgeTaskCountsModel(
      running: json['running'] as int? ?? 0,
      queued: json['queued'] as int? ?? 0,
      completed: json['completed'] as int? ?? 0,
      failed: json['failed'] as int? ?? 0,
    );
  }
}

class BridgeMetricsModel {
  final bool available;
  final int uptime;
  final int port;
  final int connectedClients;
  final BridgeTaskCountsModel taskCounts;
  final String source;

  const BridgeMetricsModel({
    required this.available,
    required this.uptime,
    required this.port,
    required this.connectedClients,
    required this.taskCounts,
    required this.source,
  });

  factory BridgeMetricsModel.fromJson(Map<String, dynamic> json) {
    return BridgeMetricsModel(
      available: json['available'] as bool? ?? true,
      uptime: json['uptime'] as int? ?? 0,
      port: json['port'] as int? ?? 8766,
      connectedClients: json['connectedClients'] as int? ?? 0,
      taskCounts: BridgeTaskCountsModel.fromJson(
        json['taskCounts'] as Map<String, dynamic>? ?? {},
      ),
      source: json['source'] as String? ?? 'AnyCoding Bridge Runtime',
    );
  }
}

class CodexRateLimitWindowModel {
  final double usedPercent;
  final String resetsAt;

  const CodexRateLimitWindowModel({
    required this.usedPercent,
    required this.resetsAt,
  });

  factory CodexRateLimitWindowModel.fromJson(Map<String, dynamic> json) {
    return CodexRateLimitWindowModel(
      usedPercent: (json['usedPercent'] as num?)?.toDouble() ?? 0.0,
      resetsAt: json['resetsAt'] as String? ?? '',
    );
  }
}

class CodexTokenUsageModel {
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;

  const CodexTokenUsageModel({
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
  });

  factory CodexTokenUsageModel.fromJson(Map<String, dynamic> json) {
    return CodexTokenUsageModel(
      inputTokens: json['inputTokens'] as int? ?? 0,
      outputTokens: json['outputTokens'] as int? ?? 0,
      totalTokens: json['totalTokens'] as int? ?? 0,
    );
  }
}

class CodexMetricsModel {
  final bool available;
  final String account;
  final String plan;
  final CodexRateLimitWindowModel? fiveHourWindow;
  final CodexRateLimitWindowModel? sevenDayWindow;
  final CodexTokenUsageModel? tokenUsage;
  final String source;
  final String? error;

  const CodexMetricsModel({
    required this.available,
    required this.account,
    required this.plan,
    this.fiveHourWindow,
    this.sevenDayWindow,
    this.tokenUsage,
    required this.source,
    this.error,
  });

  factory CodexMetricsModel.fromJson(Map<String, dynamic> json) {
    return CodexMetricsModel(
      available: json['available'] as bool? ?? false,
      account: json['account'] as String? ?? 'user_***',
      plan: json['plan'] as String? ?? 'unknown',
      fiveHourWindow: json['fiveHourWindow'] != null
          ? CodexRateLimitWindowModel.fromJson(
              json['fiveHourWindow'] as Map<String, dynamic>,
            )
          : null,
      sevenDayWindow: json['sevenDayWindow'] != null
          ? CodexRateLimitWindowModel.fromJson(
              json['sevenDayWindow'] as Map<String, dynamic>,
            )
          : null,
      tokenUsage: json['tokenUsage'] != null
          ? CodexTokenUsageModel.fromJson(
              json['tokenUsage'] as Map<String, dynamic>,
            )
          : null,
      source: json['source'] as String? ?? 'Codex App Server / Local Sessions',
      error: json['error'] as String?,
    );
  }
}

class AntigravityMetricsModel {
  final bool available;
  final String model;
  final String status;
  final String quota;
  final String note;
  final String source;
  final String? refreshedAt;
  final List<AntigravityAccountQuotaModel> accounts;
  final AntigravityUsageModel? usage;
  final String? error;

  const AntigravityMetricsModel({
    required this.available,
    required this.model,
    required this.status,
    required this.quota,
    required this.note,
    required this.source,
    this.refreshedAt,
    this.accounts = const [],
    this.usage,
    this.error,
  });

  factory AntigravityMetricsModel.fromJson(Map<String, dynamic> json) {
    return AntigravityMetricsModel(
      available: json['available'] as bool? ?? true,
      model: json['model'] as String? ?? 'gemini-3.7-flash-medium',
      status: json['status'] as String? ?? 'Ready',
      quota: json['quota'] as String? ?? '额度数据暂不可用',
      note: json['note'] as String? ?? 'TokenBar 本地数据源未响应，AGY 执行能力与额度展示分别判断',
      source: json['source'] as String? ?? 'TokenBar Local API',
      refreshedAt: json['refreshedAt'] as String?,
      accounts: (json['accounts'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AntigravityAccountQuotaModel.fromJson)
          .toList(growable: false),
      usage: json['usage'] is Map<String, dynamic>
          ? AntigravityUsageModel.fromJson(
              json['usage'] as Map<String, dynamic>,
            )
          : null,
      error: json['error'] as String?,
    );
  }
}

class AntigravityQuotaBucketModel {
  final String id;
  final String label;
  final String window;
  final double remainingPercent;
  final String resetsAt;

  const AntigravityQuotaBucketModel({
    required this.id,
    required this.label,
    required this.window,
    required this.remainingPercent,
    required this.resetsAt,
  });

  factory AntigravityQuotaBucketModel.fromJson(Map<String, dynamic> json) {
    return AntigravityQuotaBucketModel(
      id: json['id'] as String? ?? 'unknown',
      label: json['label'] as String? ?? '剩余额度',
      window: json['window'] as String? ?? 'unknown',
      remainingPercent: (json['remainingPercent'] as num?)?.toDouble() ?? 0,
      resetsAt: json['resetsAt'] as String? ?? '',
    );
  }
}

class AntigravityQuotaGroupModel {
  final String name;
  final String description;
  final List<AntigravityQuotaBucketModel> buckets;

  const AntigravityQuotaGroupModel({
    required this.name,
    required this.description,
    required this.buckets,
  });

  factory AntigravityQuotaGroupModel.fromJson(Map<String, dynamic> json) {
    return AntigravityQuotaGroupModel(
      name: json['name'] as String? ?? '模型额度',
      description: json['description'] as String? ?? '',
      buckets: (json['buckets'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AntigravityQuotaBucketModel.fromJson)
          .toList(growable: false),
    );
  }
}

class AntigravityAccountQuotaModel {
  final String account;
  final String? updatedAt;
  final List<AntigravityQuotaGroupModel> groups;

  const AntigravityAccountQuotaModel({
    required this.account,
    this.updatedAt,
    required this.groups,
  });

  factory AntigravityAccountQuotaModel.fromJson(Map<String, dynamic> json) {
    return AntigravityAccountQuotaModel(
      account: json['account'] as String? ?? 'agy_***',
      updatedAt: json['updatedAt'] as String?,
      groups: (json['groups'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AntigravityQuotaGroupModel.fromJson)
          .toList(growable: false),
    );
  }
}

class AntigravityUsageModel {
  final int todayTokens;
  final int allTokens;
  final int todayMessages;
  final int allMessages;
  final double todayCost;
  final double allCost;

  const AntigravityUsageModel({
    required this.todayTokens,
    required this.allTokens,
    required this.todayMessages,
    required this.allMessages,
    required this.todayCost,
    required this.allCost,
  });

  factory AntigravityUsageModel.fromJson(Map<String, dynamic> json) {
    return AntigravityUsageModel(
      todayTokens: (json['todayTokens'] as num?)?.toInt() ?? 0,
      allTokens: (json['allTokens'] as num?)?.toInt() ?? 0,
      todayMessages: (json['todayMessages'] as num?)?.toInt() ?? 0,
      allMessages: (json['allMessages'] as num?)?.toInt() ?? 0,
      todayCost: (json['todayCost'] as num?)?.toDouble() ?? 0,
      allCost: (json['allCost'] as num?)?.toDouble() ?? 0,
    );
  }
}

class MonitoringDataModel {
  final String timestamp;
  final SystemMetricsModel system;
  final BridgeMetricsModel bridge;
  final CodexMetricsModel codex;
  final AntigravityMetricsModel antigravity;

  const MonitoringDataModel({
    required this.timestamp,
    required this.system,
    required this.bridge,
    required this.codex,
    required this.antigravity,
  });

  factory MonitoringDataModel.fromJson(Map<String, dynamic> json) {
    return MonitoringDataModel(
      timestamp:
          json['timestamp'] as String? ?? DateTime.now().toIso8601String(),
      system: SystemMetricsModel.fromJson(
        json['system'] as Map<String, dynamic>? ?? {},
      ),
      bridge: BridgeMetricsModel.fromJson(
        json['bridge'] as Map<String, dynamic>? ?? {},
      ),
      codex: CodexMetricsModel.fromJson(
        json['codex'] as Map<String, dynamic>? ?? {},
      ),
      antigravity: AntigravityMetricsModel.fromJson(
        json['antigravity'] as Map<String, dynamic>? ?? {},
      ),
    );
  }
}

class BridgeMonitoringService {
  final http.Client _client;

  BridgeMonitoringService({http.Client? client})
    : _client = client ?? http.Client();

  /// Fetch monitoring payload from Bridge HTTP endpoint.
  Future<MonitoringDataModel> fetchMonitoringData(String bridgeUrl) async {
    final baseUrl = AndroidBridgeUpdateService.deriveHttpBaseUrl(bridgeUrl);
    final uri = Uri.parse('$baseUrl/api/monitor');

    final response = await _client
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw HttpException(
        'Bridge monitoring endpoint returned status ${response.statusCode}',
        uri: uri,
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return MonitoringDataModel.fromJson(json);
  }
}
