import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geminilocal/engine.dart';
import 'package:geminilocal/pages/settings/model.dart';
import 'package:geminilocal/pages/support/elements.dart';
import 'package:provider/provider.dart';

String _dictTemplateOrFallback(AIEngine engine, String key, String fallback) {
  final val = engine.dict.value(key);
  if (val.isEmpty ||
      val == 'Loading...' ||
      val == key ||
      val.startsWith('!!!')) {
    return fallback;
  }
  return val;
}

String _variantStatusLabel(
  AIEngine engine,
  PaiosModelVariant variant, {
  bool isDownloading = false,
}) {
  if (variant.isActive) {
    return engine.dict.value('model_selector_active');
  }
  if (isDownloading || variant.isDownloading) {
    return engine.dict.value('model_selector_downloading');
  }
  if (variant.isDownloadable) {
    return engine.dict.value('model_selector_download');
  }
  return engine.dict.value('model_selector_available');
}

Widget _buildVariantTrailing(
  BuildContext context,
  PaiosModelVariant variant, {
  bool isDownloading = false,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  if (variant.isActive) {
    return Icon(Icons.radio_button_checked_rounded, color: colorScheme.primary);
  }
  if (isDownloading || variant.isDownloading) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(
        strokeWidth: 2.2,
        color: colorScheme.primary,
      ),
    );
  }
  if (variant.isDownloadable) {
    return Icon(Icons.download_rounded, color: colorScheme.primary);
  }
  return Icon(
    Icons.radio_button_unchecked_rounded,
    color: colorScheme.onSurfaceVariant,
  );
}

String _formatVariantDownloadMetrics(
  AIEngine engine,
  PaiosVariantDownloadState dlState,
) {
  final String remainingSize =
      engine.convertSize(dlState.remainingBytes, false);
  final String speedText = dlState.bytesPerSec > 0
      ? engine.convertSize(dlState.bytesPerSec.round(), true)
      : '';
  if (speedText.isNotEmpty) {
    return _dictTemplateOrFallback(
      engine,
      'model_download_speed_remaining',
      '{speed} • {remaining} remaining',
    )
        .replaceAll('{speed}', speedText)
        .replaceAll('{remaining}', remainingSize);
  }
  return _dictTemplateOrFallback(
    engine,
    'model_download_remaining',
    '{remaining} remaining',
  ).replaceAll('{remaining}', remainingSize);
}

Widget _buildDownloadingVariantRow(
  BuildContext context,
  AIEngine engine,
  PaiosModelVariant variant,
  PaiosVariantDownloadState? dlState,
  String statusText,
) {
  final colorScheme = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;
  final bool hasKnownTotal = dlState != null && dlState.totalBytes > 0;
  final double? progressValue = hasKnownTotal ? dlState.progress : null;
  final String pctText =
      hasKnownTotal ? '${(dlState.progress * 100).toStringAsFixed(0)}%' : '';
  final String metricsText =
      hasKnownTotal ? _formatVariantDownloadMetrics(engine, dlState) : '';

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    variant.internalModelName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  Text('${variant.authorLabel} • $statusText'),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _buildVariantTrailing(
              context,
              variant,
              isDownloading: true,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LinearProgressIndicator(value: progressValue),
        ),
        if (hasKnownTotal) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                pctText,
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  metricsText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

/// Opens a compact Material 3 list dialog allowing users to switch between
/// available or downloadable Gemini Nano variants from [AIEngine.selectorModelVariants].
Future<void> showModelSelectorDialog(
  BuildContext context,
  AIEngine engine, {
  bool showModelSettingsLink = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      return Consumer<AIEngine>(
        builder: (consumerContext, liveEngine, _) {
          final colorScheme = Theme.of(consumerContext).colorScheme;
          final textTheme = Theme.of(consumerContext).textTheme;
          final cards = Cards(context: consumerContext);
          final List<PaiosModelVariant> switchable =
              liveEngine.selectorModelVariants;
          final bool isLocked = liveEngine.isLoading;

          return AlertDialog(
            contentPadding: const EdgeInsets.only(top: 10, bottom: 15),
            titlePadding: const EdgeInsets.only(top: 20, right: 20, left: 20),
            title: Text(liveEngine.dict.value('model_selector_title')),
            content: SingleChildScrollView(
              child: switchable.isEmpty
                  ? cards.cardGroup([
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    liveEngine.dict.value(
                                      'model_selector_none_available',
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    liveEngine.dict.value(
                                      'model_selector_none_available_desc',
                                    ),
                                    style: textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ])
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (isLocked)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(15, 0, 15, 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.lock_outline_rounded,
                                    size: 18,
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      liveEngine.dict.value(
                                        'model_selector_locked_generating',
                                      ),
                                      style: textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSecondaryContainer,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        AbsorbPointer(
                          absorbing: isLocked,
                          child: Opacity(
                            opacity: isLocked ? 0.55 : 1.0,
                            child: cards.cardGroup(
                              switchable.map((variant) {
                                final PaiosVariantDownloadState? dlState =
                                    liveEngine.downloadStateFor(
                                  variant.releaseStage,
                                  variant.preference,
                                );
                                final bool isDownloading =
                                    variant.isDownloading ||
                                        (dlState?.isDownloading ?? false);
                                final String statusText = _variantStatusLabel(
                                  liveEngine,
                                  variant,
                                  isDownloading: isDownloading,
                                );
                                if (isDownloading) {
                                  return _buildDownloadingVariantRow(
                                    consumerContext,
                                    liveEngine,
                                    variant,
                                    dlState,
                                    statusText,
                                  );
                                }
                                return CardContents.halfTap(
                                  title: variant.internalModelName,
                                  subtitle:
                                      '${variant.authorLabel} • $statusText',
                                  trailing: _buildVariantTrailing(
                                    consumerContext,
                                    variant,
                                    isDownloading: false,
                                  ),
                                  action: () {
                                    if (liveEngine.isLoading) {
                                      return;
                                    }
                                    HapticFeedback.lightImpact();
                                    if (variant.isActive) {
                                      if (dialogContext.mounted) {
                                        Navigator.of(dialogContext).pop();
                                      }
                                      return;
                                    }
                                    if (variant.isDownloadable) {
                                      // Download in background without switching off Model A
                                      // and keep the dialog open so progress is visible.
                                      unawaited(
                                        liveEngine.downloadVariant(
                                          variant.releaseStage,
                                          variant.preference,
                                        ),
                                      );
                                      return;
                                    }
                                    if (dialogContext.mounted) {
                                      Navigator.of(dialogContext).pop();
                                    }
                                    unawaited(
                                      liveEngine.setModelConfiguration(
                                        releaseStage: variant.releaseStage,
                                        preference: variant.preference,
                                      ),
                                    );
                                  },
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            actions: [
              if (showModelSettingsLink)
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ModelSettings(),
                        settings: const RouteSettings(name: 'ModelSettings'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text(
                    liveEngine.dict.value('model_selector_open_settings'),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(liveEngine.dict.value('close')),
              ),
            ],
          );
        },
      );
    },
  );
}
