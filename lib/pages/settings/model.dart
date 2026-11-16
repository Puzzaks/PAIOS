import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:m3x_ui/m3x_ui.dart' show MotionBlurContainer;
import '../../engine.dart';
import '../support/elements.dart';
import '../support/model_selector_dialog.dart';


class ModelSettings extends StatefulWidget {
  const ModelSettings({super.key});
  @override
  ModelSettingsState createState() => ModelSettingsState();
}

class ModelSettingsState extends State<ModelSettings> {
  @override
  void initState() {
    super.initState();
  }

  String _stageLabel(AIEngine engine, String stage) {
    return stage.toLowerCase() == 'preview'
        ? engine.dict.value('channel_preview')
        : engine.dict.value('channel_stable');
  }

  String _prefLabel(AIEngine engine, String pref) {
    return pref.toLowerCase() == 'fast'
        ? engine.dict.value('pref_fast')
        : engine.dict.value('pref_full');
  }

  String _resolveVersionDisplay(AIEngine engine) {
    final rawVersion = engine.modelInfo["version"]?.toString().trim();
    if (rawVersion != null &&
        rawVersion.isNotEmpty &&
        rawVersion != "null" &&
        rawVersion.toLowerCase() != "unknown") {
      return rawVersion;
    }
    final rawStatus = engine.modelInfo["status"]?.toString().trim().toLowerCase();
    final rawStatusCode = engine.modelInfo["statusCode"]?.toString().trim();
    if (rawStatus == "1" ||
        rawStatus == "downloadable" ||
        rawStatusCode == "1" ||
        engine.modelFeatureStatus == "downloadable") {
      return engine.dict.value("model_status_downloadable");
    }
    if (rawStatus == "2" ||
        rawStatus == "downloading" ||
        rawStatusCode == "2" ||
        engine.modelFeatureStatus == "downloading" ||
        engine.isDownloadingModel) {
      return engine.dict.value("model_status_downloading");
    }
    final aicoreVersion = engine.modelInfo["aicoreVersion"]?.toString().trim();
    if (aicoreVersion != null &&
        aicoreVersion.isNotEmpty &&
        aicoreVersion != "null" &&
        aicoreVersion.toLowerCase() != "unknown") {
      return aicoreVersion;
    }
    return "Gemini Nano";
  }

  Widget _buildFeatureBadge(
    BuildContext context, {
    required IconData icon,
    required String label,
    bool highlight = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final bg = highlight
        ? colorScheme.tertiaryContainer
        : colorScheme.surfaceContainerHighest;
    final fg = highlight
        ? colorScheme.onTertiaryContainer
        : colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
          ),
        ],
      ),
    );
  }

  String _dictTemplateOrFallback(
    AIEngine engine,
    String key,
    String fallback,
  ) {
    final val = engine.dict.value(key);
    if (val.isEmpty ||
        val == 'Loading...' ||
        val == key ||
        val.startsWith('!!!')) {
      return fallback;
    }
    return val;
  }

  String _variantNameForDownload(
    AIEngine engine,
    PaiosVariantDownloadState dl,
  ) {
    for (final v in engine.modelVariants) {
      if (v.releaseStage == dl.releaseStage &&
          v.preference == dl.preference) {
        return v.internalModelName;
      }
    }
    return '${dl.releaseStage}-${dl.preference}';
  }

  Widget _buildBackgroundDownloadCardSection(
    BuildContext context,
    AIEngine engine,
    PaiosVariantDownloadState dl,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bool hasTotal = dl.totalBytes > 0;
    final String pctText =
        hasTotal ? '${(dl.progress * 100).toStringAsFixed(0)}%' : '';
    final String remainingSize = engine.convertSize(dl.remainingBytes, false);
    final String speedText = dl.bytesPerSec > 0
        ? engine.convertSize(dl.bytesPerSec.round(), true)
        : '';
    final String metricsText = speedText.isNotEmpty
        ? _dictTemplateOrFallback(
            engine,
            'model_download_speed_remaining',
            '{speed} • {remaining} remaining',
          )
            .replaceAll('{speed}', speedText)
            .replaceAll('{remaining}', remainingSize)
        : _dictTemplateOrFallback(
            engine,
            'model_download_remaining',
            '{remaining} remaining',
          ).replaceAll('{remaining}', remainingSize);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _variantNameForDownload(engine, dl),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              if (pctText.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  pctText,
                  style: textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: hasTotal ? dl.progress : null,
              minHeight: 4,
            ),
          ),
          if (hasTotal) ...[
            const SizedBox(height: 4),
            Text(
              metricsText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
        canPop: true,
        child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final colorScheme = Theme.of(context).colorScheme;
              Cards cards = Cards(context: context);
              return Consumer<AIEngine>(builder: (context, engine, child) {
                final bool thinkingLockedOn =
                    engine.isNanoV4Active || engine.isThinkingModeAvailable;
                final String activeStageText =
                    _stageLabel(engine, engine.activeReleaseStage);
                final String activePrefText =
                    _prefLabel(engine, engine.activePreference);
                final String requestedStage =
                    engine.modelInfo["requestedReleaseStage"]?.toString() ??
                        engine.modelReleaseStage;
                final String requestedPref =
                    engine.modelInfo["requestedPreference"]?.toString() ??
                        engine.modelPreference;
                final String? statusCodeStr =
                    engine.modelInfo["statusCode"]?.toString().trim();
                final PaiosVariantDownloadState? activeDlState =
                    engine.downloadStateFor(requestedStage, requestedPref) ??
                        engine.downloadStateFor(
                          engine.activeReleaseStage,
                          engine.activePreference,
                        );
                final List<PaiosVariantDownloadState> activeBackgroundDownloads =
                    engine.variantDownloads.values
                        .where((d) => d.isDownloading)
                        .toList();
                final bool isDownloading =
                    engine.modelFeatureStatus == 'downloading' ||
                        engine.modelFeatureStatus == '2' ||
                        statusCodeStr == '2' ||
                        (activeDlState?.isDownloading ?? false);
                final bool showDownloadAction =
                    engine.modelFeatureStatus == 'downloadable' ||
                        engine.modelFeatureStatus == '1' ||
                        statusCodeStr == '1' ||
                        isDownloading;
                PaiosModelVariant? activeVariant;
                for (final variant in engine.selectorModelVariants) {
                  if (variant.isActive) {
                    activeVariant = variant;
                    break;
                  }
                }
                if (activeVariant == null) {
                  for (final variant in engine.modelVariants) {
                    if (variant.isActive) {
                      activeVariant = variant;
                      break;
                    }
                  }
                }
                final String activeSelectorName =
                    activeVariant?.internalModelName ??
                        "$activeStageText • $activePrefText";

                return Scaffold(
                  body: CustomScrollView(
                    slivers: <Widget>[
                      SliverAppBar.large(
                        surfaceTintColor: Colors.transparent,
                        leading: Padding(
                          padding: EdgeInsetsGeometry.only(left: 5),
                          child: IconButton(
                              onPressed: (){
                                Navigator.pop(context);
                              },
                              icon: Icon(Icons.arrow_back_rounded)
                          ),
                        ),
                        title: Text(engine.dict.value("settings_ai")),
                        pinned: true,
                      ),
                      SliverToBoxAdapter(
                        child: MotionBlurContainer(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Category.settings(
                                  title: engine.dict.value("aicore_channel"),
                                  context: context
                              ),
                              cards.cardGroup([
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  engine.activeModelName,
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  "${engine.dict.value("version")}: ${_resolveVersionDisplay(engine)}",
                                                  style: TextStyle(
                                                    color: colorScheme.onSurfaceVariant,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  engine.dict
                                                      .value("active_model_config")
                                                      .replaceAll("%stage%", activeStageText)
                                                      .replaceAll("%pref%", activePrefText),
                                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                        color: colorScheme.onSurfaceVariant,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Chip(
                                            avatar: (engine.isAICoreBeta || engine.isNanoV4Active)
                                                ? Icon(
                                                    Icons.auto_awesome,
                                                    size: 16,
                                                    color: colorScheme.onPrimaryContainer,
                                                  )
                                                : null,
                                            label: Text(
                                              engine.isNanoV4Active
                                                  ? engine.dict.value("badge_nano_v4")
                                                  : (engine.isAICoreBeta
                                                      ? engine.dict.value("aicore_beta_badge")
                                                      : engine.dict.value("aicore_stable_badge")),
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: (engine.isAICoreBeta || engine.isNanoV4Active)
                                                    ? colorScheme.onPrimaryContainer
                                                    : colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                                            visualDensity: VisualDensity.compact,
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            backgroundColor: (engine.isAICoreBeta || engine.isNanoV4Active)
                                                ? colorScheme.primaryContainer
                                                : colorScheme.surfaceContainerHighest,
                                            surfaceTintColor: Colors.transparent,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(20),
                                              side: const BorderSide(color: Colors.transparent),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (engine.isNanoV4Active ||
                                          engine.isSystemPromptAvailable ||
                                          engine.isThinkingModeAvailable ||
                                          engine.isCachingAvailable) ...[
                                        const SizedBox(height: 10),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: [
                                            if (engine.isSystemPromptAvailable)
                                              _buildFeatureBadge(
                                                context,
                                                icon: Icons.tune_rounded,
                                                label: engine.dict.value("badge_system_prompt"),
                                              ),
                                            if (engine.isThinkingModeAvailable || engine.isNanoV4Active)
                                              _buildFeatureBadge(
                                                context,
                                                icon: Icons.psychology_alt_rounded,
                                                label: engine.dict.value("badge_thinking_mode"),
                                                highlight: true,
                                              ),
                                            if (engine.isCachingAvailable)
                                              _buildFeatureBadge(
                                                context,
                                                icon: Icons.bolt_rounded,
                                                label: engine.dict.value("badge_caching"),
                                              ),
                                          ],
                                        ),
                                      ],
                                      if (engine.fellBackToStable) ...[
                                        const SizedBox(height: 10),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: colorScheme.secondaryContainer.withValues(alpha: 0.7),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Icon(
                                                Icons.info_outline_rounded,
                                                size: 18,
                                                color: colorScheme.onSecondaryContainer,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      engine.dict.value("preview_fallback_note"),
                                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                            color: colorScheme.onSecondaryContainer,
                                                            fontWeight: FontWeight.w500,
                                                          ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      engine.dict
                                                          .value("requested_model_config")
                                                          .replaceAll("%stage%", _stageLabel(engine, requestedStage))
                                                          .replaceAll("%pref%", _prefLabel(engine, requestedPref)),
                                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                            color: colorScheme.onSecondaryContainer.withValues(alpha: 0.85),
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                      if (showDownloadAction) ...[
                                        const SizedBox(height: 12),
                                        SizedBox(
                                          width: double.infinity,
                                          child: FilledButton.tonalIcon(
                                            onPressed: isDownloading
                                                ? null
                                                : () {
                                                    HapticFeedback.lightImpact();
                                                    engine.downloadVariant(
                                                      requestedStage,
                                                      requestedPref,
                                                    );
                                                  },
                                            icon: isDownloading
                                                ? SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: colorScheme.onSecondaryContainer,
                                                    ),
                                                  )
                                                : const Icon(Icons.download_rounded, size: 18),
                                            label: Text(
                                              isDownloading
                                                  ? engine.dict.value("downloading_preview_model")
                                                  : engine.dict.value("download_preview_model"),
                                            ),
                                          ),
                                        ),
                                      ],
                                      if (activeBackgroundDownloads.isNotEmpty) ...[
                                        for (final dl in activeBackgroundDownloads) ...[
                                          const SizedBox(height: 10),
                                          _buildBackgroundDownloadCardSection(
                                            context,
                                            engine,
                                            dl,
                                          ),
                                        ],
                                      ],
                                      if (engine.isSwitchingModelConfig) ...[
                                        const SizedBox(height: 10),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: const LinearProgressIndicator(minHeight: 3),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                CardContents.tap(
                                  title: engine.dict.value("model_selector_title"),
                                  subtitle: engine.isLoading
                                      ? "${engine.assistantAuthorLabel} • $activeSelectorName\n${engine.dict.value("model_selector_locked_generating")}"
                                      : "${engine.assistantAuthorLabel} • $activeSelectorName",
                                  trailing: engine.isSwitchingModelConfig
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : engine.isLoading
                                          ? Icon(
                                              Icons.lock_outline_rounded,
                                              color: colorScheme.onSurfaceVariant,
                                            )
                                          : Icon(
                                              Icons.chevron_right_rounded,
                                              color: colorScheme.onSurfaceVariant,
                                            ),
                                  action: (engine.isSwitchingModelConfig || engine.isLoading)
                                      ? () {}
                                      : () {
                                          HapticFeedback.lightImpact();
                                          showModelSelectorDialog(context, engine);
                                        },
                                ),
                                CardContents.tapIcon(
                                    title: engine.dict.value("open_aicore_settings"),
                                    subtitle: engine.dict.value("in_play_store"),
                                    icon: Icons.android_rounded,
                                    colorBG: colorScheme.primaryFixedDim,
                                    color: colorScheme.onPrimaryFixed,
                                    action: () async {
                                      engine.gemini.openAICorePlayStore();
                                    }
                                ),
                                CardContents.tapIcon(
                                    title: engine.dict.value("aicore_dev_settings"),
                                    subtitle: engine.dict.value("aicore_dev_settings_desc"),
                                    icon: Icons.developer_mode_rounded,
                                    colorBG: colorScheme.primaryFixedDim,
                                    color: colorScheme.onPrimaryFixed,
                                    action: () async {
                                      engine.gemini.openAICoreDevSettings();
                                    }
                                ),
                                if (!engine.isAICoreBeta)
                                  CardContents.tapIcon(
                                      title: engine.dict.value("join_aicore_beta"),
                                      subtitle: engine.dict.value("join_aicore_beta_desc"),
                                      icon: Icons.science_rounded,
                                      colorBG: colorScheme.primaryFixedDim,
                                      color: colorScheme.onPrimaryFixed,
                                      action: () async {
                                        engine.gemini.openAICoreBetaProgram();
                                      }
                                  ),
                              ]),
                              Category.settings(
                                  title: engine.dict.value("settings_ai"),
                                  context: context
                              ),
                              cards.cardGroup([
                                CardContents.addretract(
                                    title: engine.dict.value("temperature"),
                                    subtitle: engine.dict.value("temperature_desc").replaceAll("%value%", engine.temperature.toStringAsFixed(1)),
                                    actionAdd: (){
                                      if(engine.temperature < 0.9){
                                        setState(() {
                                          engine.temperature = engine.temperature + 0.1;
                                        });
                                        engine.saveSettings();
                                      }
                                    },
                                    actionRetract: (){
                                      if(engine.temperature > 0.1){
                                        setState(() {
                                          engine.temperature = engine.temperature - 0.1;
                                        });
                                        engine.saveSettings();
                                      }
                                    }
                                ),
                                CardContents.turn(
                                    title: engine.dict.value("thinking_mode"),
                                    subtitle: thinkingLockedOn
                                        ? engine.dict.value("thinking_mode_v4_locked")
                                        : engine.dict.value("thinking_mode_desc"),
                                    action: thinkingLockedOn
                                        ? null
                                        : (){
                                            HapticFeedback.lightImpact();
                                            engine.setEnableThinking(!engine.enableThinking);
                                          },
                                    switcher: thinkingLockedOn
                                        ? null
                                        : (value){
                                            HapticFeedback.lightImpact();
                                            engine.setEnableThinking(value);
                                          },
                                    value: thinkingLockedOn ? true : engine.enableThinking,
                                ),
                                CardContents.turn(
                                    title: engine.dict.value("add_time"),
                                    subtitle: engine.dict.value("add_time_desc"),
                                    action: (){
                                      setState(() {
                                        engine.addCurrentTimeToRequests = !engine.addCurrentTimeToRequests;
                                      });
                                      engine.saveSettings();
                                    },
                                    switcher: (value){
                                      setState(() {
                                        engine.addCurrentTimeToRequests = !engine.addCurrentTimeToRequests;
                                      });
                                      engine.saveSettings();
                                    },
                                    value: engine.addCurrentTimeToRequests
                                ),
                                CardContents.turn(
                                    title: engine.dict.value("add_lang"),
                                    subtitle: engine.dict.value("add_lang_desc"),
                                    action: (){
                                      setState(() {
                                        engine.shareLocale = !engine.shareLocale;
                                      });
                                      engine.saveSettings();
                                    },
                                    switcher: (value){
                                      setState(() {
                                        engine.shareLocale = !engine.shareLocale;
                                      });
                                      engine.saveSettings();
                                    },
                                    value: engine.shareLocale
                                ),
                                CardContents.turn(
                                    title: engine.dict.value("downsample_images"),
                                    subtitle: engine.dict.value("downsample_images_desc"),
                                    action: (){
                                      setState(() {
                                        engine.downsampleImages = !engine.downsampleImages;
                                      });
                                      engine.saveSettings();
                                    },
                                    switcher: (value){
                                      setState(() {
                                        engine.downsampleImages = value;
                                      });
                                      engine.saveSettings();
                                    },
                                    value: engine.downsampleImages
                                ),
                                CardContents.turn(
                                    title: engine.dict.value("enable_mesh"),
                                    subtitle: engine.dict.value("enable_mesh_desc"),
                                    action: (){
                                      setState(() {
                                        engine.enableMesh = !engine.enableMesh;
                                      });
                                      engine.saveSettings();
                                    },
                                    switcher: (value){
                                      setState(() {
                                        engine.enableMesh = value;
                                      });
                                      engine.saveSettings();
                                    },
                                    value: engine.enableMesh
                                ),
                              ]),
                              text.info(
                                  title: engine.dict.value("welcome_available"),
                                  context: context,
                                  subtitle: "",
                                  action: (){}
                              )
                            ],
                          ),
                        ),
                      ),
                    ],

                  ),
                );
              });
            }
        )
    );
  }
}
