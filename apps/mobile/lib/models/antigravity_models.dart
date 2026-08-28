import 'package:flutter/material.dart';

class AntigravityModelOption {
  final String id;
  final String name;
  final String providerName;
  final String? description;
  final bool isDefault;

  const AntigravityModelOption({
    required this.id,
    required this.name,
    required this.providerName,
    this.description,
    this.isDefault = false,
  });
}

const defaultAntigravityModel = 'gemini-3.7-flash-medium';

const defaultAntigravityModels = <AntigravityModelOption>[
  AntigravityModelOption(
    id: 'gemini-3.7-flash-high',
    name: 'Gemini 3.7 Flash High',
    providerName: 'Google',
    description: 'High reasoning effort',
  ),
  AntigravityModelOption(
    id: 'gemini-3.7-flash-medium',
    name: 'Gemini 3.7 Flash Medium',
    providerName: 'Google',
    description: 'Balanced speed & reasoning (Default)',
    isDefault: true,
  ),
  AntigravityModelOption(
    id: 'gemini-3.7-flash-low',
    name: 'Gemini 3.7 Flash Low',
    providerName: 'Google',
    description: 'Low latency & fast reasoning',
  ),
  AntigravityModelOption(
    id: 'gemini-3.6-flash-high',
    name: 'Gemini 3.6 Flash High',
    providerName: 'Google',
    description: 'High reasoning effort',
  ),
  AntigravityModelOption(
    id: 'gemini-3.6-flash-medium',
    name: 'Gemini 3.6 Flash Medium',
    providerName: 'Google',
    description: 'Balanced reasoning effort',
  ),
  AntigravityModelOption(
    id: 'gemini-3.6-flash-low',
    name: 'Gemini 3.6 Flash Low',
    providerName: 'Google',
    description: 'Fast reasoning effort',
  ),
  AntigravityModelOption(
    id: 'gemini-3.5-flash-high',
    name: 'Gemini 3.5 Flash High',
    providerName: 'Google',
    description: 'High reasoning effort',
  ),
  AntigravityModelOption(
    id: 'gemini-3.5-flash-medium',
    name: 'Gemini 3.5 Flash Medium',
    providerName: 'Google',
    description: 'Balanced reasoning effort',
  ),
  AntigravityModelOption(
    id: 'gemini-3.5-flash-low',
    name: 'Gemini 3.5 Flash Low',
    providerName: 'Google',
    description: 'Fast reasoning effort',
  ),
  AntigravityModelOption(
    id: 'gemini-3.1-pro-high',
    name: 'Gemini 3.1 Pro High',
    providerName: 'Google',
    description: 'Advanced reasoning pro model',
  ),
  AntigravityModelOption(
    id: 'gemini-3.1-pro-low',
    name: 'Gemini 3.1 Pro Low',
    providerName: 'Google',
    description: 'Standard pro model',
  ),
  AntigravityModelOption(
    id: 'claude-sonnet-4-6',
    name: 'Claude Sonnet 4.6',
    providerName: 'Anthropic',
    description: 'Anthropic Claude via Antigravity provider',
  ),
  AntigravityModelOption(
    id: 'claude-opus-4-6-thinking',
    name: 'Claude Opus 4.6 (Thinking)',
    providerName: 'Anthropic',
    description: 'Anthropic Claude Opus with thinking',
  ),
  AntigravityModelOption(
    id: 'gpt-oss-120b-medium',
    name: 'GPT-OSS 120B Medium',
    providerName: 'OpenAI',
    description: 'Open-weight 120B model via Antigravity',
  ),
];

AntigravityModelOption findAntigravityModel(String? modelId) {
  if (modelId == null || modelId.isEmpty || modelId == 'default') {
    return defaultAntigravityModels.firstWhere((m) => m.id == defaultAntigravityModel);
  }
  return defaultAntigravityModels.firstWhere(
    (m) => m.id == modelId,
    orElse: () => AntigravityModelOption(
      id: modelId,
      name: modelId,
      providerName: 'Antigravity',
    ),
  );
}

Future<String?> showAntigravityModelSheet({
  required BuildContext context,
  required String currentModel,
  required ValueChanged<String> onSelected,
}) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final cs = theme.colorScheme;

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, size: 18, color: Color(0xFFFF7A00)),
                    const SizedBox(width: 8),
                    Text(
                      'Antigravity 模型选择',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.65,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: defaultAntigravityModels.length,
                  itemBuilder: (context, index) {
                    final item = defaultAntigravityModels[index];
                    final isSelected = item.id == currentModel;
                    final providerBadgeColor = item.providerName == 'Google'
                        ? const Color(0xFF4285F4)
                        : (item.providerName == 'Anthropic'
                            ? const Color(0xFFD97706)
                            : const Color(0xFF10A37F));

                    return ListTile(
                      key: ValueKey('antigravity_model_option_${item.id}'),
                      dense: true,
                      selected: isSelected,
                      selectedTileColor: isDark
                          ? const Color(0xFFFF7A00).withValues(alpha: 0.15)
                          : const Color(0xFFFF7A00).withValues(alpha: 0.08),
                      title: Row(
                        children: [
                          Text(
                            item.name,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              fontSize: 13.5,
                              color: isSelected ? const Color(0xFFFF7A00) : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: providerBadgeColor.withValues(alpha: isDark ? 0.25 : 0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: providerBadgeColor.withValues(alpha: 0.4),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              item.providerName,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: providerBadgeColor,
                              ),
                            ),
                          ),
                          if (item.isDefault) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '默认',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  color: cs.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        item.id,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: Color(0xFFFF7A00), size: 18)
                          : null,
                      onTap: () {
                        onSelected(item.id);
                        Navigator.of(ctx).pop(item.id);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
