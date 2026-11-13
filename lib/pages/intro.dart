import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:m3x/m3x.dart' show M3x;
import 'settings/doc_explorer.dart';
import 'package:m3x_ui/m3x_ui.dart' show ChoiceCard, MotionBlurContainer;
import '../engine.dart';
import '../storage/intro_slide_repository.dart';
import 'github_explorer_page.dart';
import 'settings/logs.dart';
import 'support/elements.dart';

class IntroPage extends StatefulWidget {
  const IntroPage({super.key});

  @override
  IntroPageState createState() => IntroPageState();
}

class IntroPageState extends State<IntroPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  int _latestSpeed = 0;
  bool _isDefaultAssistant = false;
  String _deviceSearchQuery = "";
  final TextEditingController _deviceSearchCtrl = TextEditingController();
  List<Map<String, dynamic>> _meshProposals = [];
  Map<String, String> _meshAppLabels = {};

  static const List<String> _knownSupportedDevices = [
    "Google Pixel 9",
    "Google Pixel 9 Pro",
    "Google Pixel 9 Pro XL",
    "Google Pixel 9 Pro Fold",
    "Google Pixel 8",
    "Google Pixel 8 Pro",
    "Google Pixel 8a",
    "Samsung Galaxy S25",
    "Samsung Galaxy S25+",
    "Samsung Galaxy S25 Ultra",
    "Samsung Galaxy S24",
    "Samsung Galaxy S24+",
    "Samsung Galaxy S24 Ultra",
    "Samsung Galaxy Z Fold6",
    "Samsung Galaxy Z Flip6",
    "Motorola Razr 50 Ultra",
    "Motorola Razr+ (2024)",
    "Xiaomi 14T Pro",
    "Xiaomi 15",
  ];

  @override
  void initState() {
    super.initState();
    _checkAssistantStatus();
    _loadMeshShowcaseData();
  }

  Future<void> _loadMeshShowcaseData() async {
    final engine = Provider.of<AIEngine>(context, listen: false);
    List<Map<String, dynamic>> proposals = [];
    try {
      final jsonStr = await rootBundle.loadString('assets/data/mesh_proposals.json');
      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        proposals = decoded.whereType<Map<String, dynamic>>().toList();
      }
    } catch (_) {}

    final Map<String, String> labels = {};
    final Set<String> pkgsToResolve = {
      for (final p in proposals)
        if ((p['package']?.toString() ?? '').isNotEmpty)
          AIEngine.canonicalExtensionId(p['package']!.toString()),
      for (final t in engine.toolRegistry.tools)
        if (AIEngine.canonicalToolExtensionId(t).isNotEmpty &&
            AIEngine.canonicalToolExtensionId(t) != AIEngine.canonicalExtensionId('paios'))
          AIEngine.canonicalToolExtensionId(t),
    };
    for (final pkg in pkgsToResolve) {
      try {
        final label = await engine.meshClient.getAppLabel(pkg);
        if (label != null && label.trim().isNotEmpty) {
          labels[pkg] = label.trim();
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _meshProposals = proposals;
        _meshAppLabels = labels;
      });
    }
  }

  IconData _iconForMeshProposal(String? iconName) {
    switch (iconName) {
      case 'dns_rounded':
        return Icons.dns_rounded;
      case 'alert':
        return Icons.notifications_active_rounded;
      case 'camera_alt_rounded':
        return Icons.camera_alt_rounded;
      case 'calculate_rounded':
        return Icons.calculate_rounded;
      case 'tune_rounded':
        return Icons.tune_rounded;
      case 'widgets_rounded':
        return Icons.widgets_rounded;
      default:
        return Icons.extension_rounded;
    }
  }

  String _labelForExtension(String pkgOrApp) {
    final canon = AIEngine.canonicalExtensionId(pkgOrApp);
    final label = _meshAppLabels[canon];
    if (label != null && label.isNotEmpty) return label;
    for (final p in _meshProposals) {
      if (AIEngine.canonicalExtensionId(p['package']?.toString() ?? '') == canon &&
          p['name'] != null) {
        return p['name'].toString();
      }
    }
    final parts = canon.split('.');
    if (parts.isNotEmpty && parts.last.isNotEmpty) {
      return parts.last;
    }
    return pkgOrApp;
  }

  @override
  void dispose() {
    _pageController.dispose();
    _deviceSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkAssistantStatus() async {
    try {
      final isDef = await Provider.of<AIEngine>(context, listen: false).gemini.isDefaultAssistant();
      if (mounted) setState(() => _isDefaultAssistant = isDef);
    } catch (_) {}
  }

  void _nextPage(int totalSlides) {
    if (_currentPage < totalSlides - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    final engine = Provider.of<AIEngine>(context, listen: false);
    await engine.endFirstLaunch();
  }

  String _convertSize(int size, bool isSpeed) {
    if (size < 1024) {
      return '$size B${isSpeed ? "/s" : ""}';
    } else if (size < 10240) {
      double sizeKb = size / 1024;
      return '${sizeKb.toStringAsFixed(2)} KB${isSpeed ? "/s" : ""}';
    } else if (size < 1048576) {
      double sizeKb = size / 1024;
      return '${sizeKb.toStringAsFixed(1)} KB${isSpeed ? "/s" : ""}';
    } else if (size < 10485760) {
      double sizeMb = size / 1048576;
      return '${sizeMb.toStringAsFixed(2)} MB${isSpeed ? "/s" : ""}';
    } else if (size < 104857600) {
      double sizeMb = size / 1048576;
      return '${sizeMb.toStringAsFixed(1)} MB${isSpeed ? "/s" : ""}';
    } else if (size < 1073741824) {
      double sizeGb = size / 1073741824;
      return '${sizeGb.toStringAsFixed(2)} GB${isSpeed ? "/s" : ""}';
    } else if (size < 10737418240) {
      double sizeGb = size / 1073741824;
      return '${sizeGb.toStringAsFixed(1)} GB${isSpeed ? "/s" : ""}';
    } else {
      double sizeGb = size / 1073741824;
      return '${sizeGb.toInt()} GB${isSpeed ? "/s" : ""}';
    }
  }

  String _calcSpeed(List log) {
    if (log.length > 1) {
      int lastSize = int.tryParse(log[log.length - 1]["value"].toString()) ?? 0;
      int lastTime = (((log[log.length - 1]["time"] as int? ?? 0) + 1) / 1000).toInt();
      int prevSize = int.tryParse(log[log.length - 2]["value"].toString()) ?? 0;
      int prevTime = ((log[log.length - 2]["time"] as int? ?? 0) / 1000).toInt();

      if (lastTime == prevTime || lastSize == prevSize) {
        return _convertSize(_latestSpeed, true);
      }
      int speed = ((lastSize - prevSize) / (lastTime - prevTime)).toInt();
      if (log.length > 2) {
        int anotherSize = int.tryParse(log[log.length - 3]["value"].toString()) ?? 0;
        int anotherTime = ((log[log.length - 3]["time"] as int? ?? 0) / 1000).toInt();
        if (prevSize == anotherSize || prevTime == anotherTime) {
          return _convertSize(_latestSpeed, true);
        }
        int lastSpeed = ((prevSize - anotherSize) / (prevTime - anotherTime)).toInt();
        int avgSpeed = ((speed + lastSpeed) / 2).toInt();
        if (avgSpeed < 100) {
          return _convertSize(_latestSpeed, true);
        } else {
          _latestSpeed = avgSpeed;
          return _convertSize(avgSpeed, true);
        }
      } else {
        if (speed < 100) {
          return _convertSize(_latestSpeed, true);
        } else {
          _latestSpeed = speed;
          return _convertSize(speed, true);
        }
      }
    } else {
      return _convertSize(_latestSpeed, true);
    }
  }

  String _generateDiagnosticReport(AIEngine engine) {
    final now = DateTime.now().toUtc().toIso8601String();
    final appVersionText = M3x.versionDisplay.isNotEmpty
        ? M3x.versionDisplay
        : (M3x.appVersion.isNotEmpty ? M3x.appVersion : 'Unknown');
    return '''--- PAIOS Diagnostic Report ---
Timestamp: $now
App Version: $appVersionText
Device Model: ${engine.modelInfo['deviceModel'] ?? 'Unknown Android Device'}
OS Version: ${engine.modelInfo['osVersion'] ?? 'Android'}
AICore Installed: ${engine.modelInfo['aicoreInstalled'] ?? 'false'}
AICore Version: ${engine.modelInfo['aicoreVersion'] ?? 'Unknown'}
AICore Beta: ${engine.modelInfo['isBeta'] ?? 'false'}
AICore Status: ${engine.modelInfo['status'] ?? 'Unavailable'}
Model Version: ${engine.modelInfo['version'] ?? 'Unknown'}
Agentic Mesh Enabled: ${engine.config.enableMesh}
Analytics Enabled: ${engine.analytics}
Active Persona: ${engine.config.defaultPromptId}
Model Log Events:
${engine.modelDownloadLog.take(8).map((l) => '  - ${l['status']}=${l['info']}=${l['value']}').join('\n')}
--------------------------------''';
  }

  bool _isAiCoreSupported(AIEngine engine) {
    final status = engine.modelInfo["status"]?.toString();
    if (status == "Unavailable") return false;
    if (engine.modelDownloadLog.isNotEmpty) {
      final last = engine.modelDownloadLog.last;
      if (last["status"] == "Error" &&
          (last["info"] == "AICore" || last["value"] == "Unavailable")) {
        return false;
      }
    }
    return true;
  }

  IconData _iconForPrompt(String id) {
    switch (id) {
      case "pirate":
        return Icons.sailing_rounded;
      case "concise":
        return Icons.short_text_rounded;
      case "creative":
        return Icons.auto_fix_high_rounded;
      default:
        return Icons.psychology_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AIEngine>(builder: (context, engine, child) {
      final scheme = Theme.of(context).colorScheme;
      final textTheme = Theme.of(context).textTheme;
      final cards = Cards(context: context);
      final isSupported = _isAiCoreSupported(engine);

      // Build slides list according to active branch
      final List<Widget> slides = isSupported
          ? _buildBranchASlides(context, engine, cards, scheme, textTheme)
          : _buildBranchBSlides(context, engine, cards, scheme, textTheme);

      // Append configurable remote slides
      final remoteSlides = engine.introSlideData.getSlidesForBranch(isSupported);
      for (final rSlide in remoteSlides) {
        slides.add(_buildRemoteSlide(context, engine, rSlide, scheme, textTheme));
      }

      final totalSlides = slides.length;
      final isLastSlide = _currentPage >= totalSlides - 1;

      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // Top PageView
              Expanded(
                child: MotionBlurContainer(
                  child: PageView(
                    controller: _pageController,
                    physics: const ClampingScrollPhysics(),
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    children: slides,
                  ),
                ),
              ),

              // Animated pill dots
              Padding(
                padding: const EdgeInsets.only(bottom: 12, top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(totalSlides, (i) {
                    final bool active = _currentPage == i;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: active
                            ? scheme.primary
                            : scheme.onSurfaceVariant.withValues(alpha: 0.3),
                      ),
                    );
                  }),
                ),
              ),

              // Bottom action bar
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    !isLastSlide
                        ? TextButton(
                            onPressed: () {
                              _pageController.animateToPage(
                                totalSlides - 1,
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.easeInOutCubic,
                              );
                            },
                            child: Text(engine.dict.value("intro_skip")),
                          )
                        : const SizedBox(width: 72),
                    !isLastSlide
                        ? FilledButton(
                            onPressed: () => _nextPage(totalSlides),
                            child: Text(engine.dict.value("intro_next")),
                          )
                        : FilledButton.icon(
                            onPressed: _finish,
                            icon: const Icon(Icons.check_rounded),
                            label: Text(engine.dict.value("intro_get_started")),
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  // в”Ђв”Ђ BRANCH A: SUPPORTED / READY / DOWNLOADING в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ

  List<Widget> _buildBranchASlides(
    BuildContext context,
    AIEngine engine,
    Cards cards,
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    return [
      // Slide A-1: 100% On-Device Intelligence
      _buildSlideContainer(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/logo.png',
              width: 84,
              height: 84,
              errorBuilder: (ctx, err, stack) => Icon(
                Icons.psychology_rounded,
                size: 84,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              engine.dict.value("intro_mind_on_device_title"),
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              engine.dict.value("intro_mind_on_device_desc"),
              style: textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),

      // Slide A-2: Anonymous Stability & Telemetry
      _buildSlideContainer(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.query_stats_rounded, size: 72, color: scheme.primary),
            const SizedBox(height: 24),
            Text(
              engine.dict.value("intro_telemetry_title"),
              style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              engine.dict.value("intro_telemetry_desc"),
              style: textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            cards.cardGroup([
              CardContents.turn(
                title: engine.dict.value("allow_anonymous_usage"),
                subtitle: engine.dict.value("allow_anonymous_usage_desc"),
                value: engine.analytics,
                action: () {
                  setState(() => engine.analytics = !engine.analytics);
                  if (engine.analytics) {
                    engine.startAnalytics();
                  } else {
                    engine.stopAnalytics();
                  }
                },
                switcher: (val) {
                  setState(() => engine.analytics = val);
                  if (val) {
                    engine.startAnalytics();
                  } else {
                    engine.stopAnalytics();
                  }
                },
              ),
            ]),
            const SizedBox(height: 12),
            text.infoShort(
              title: engine.dict.value("telemetry_privacy_guarantee"),
              subtitle: "",
              action: () {},
              context: context,
            ),
          ],
        ),
      ),

      // Slide A-3: Default Assistant Setup
      _buildSlideContainer(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.assistant_rounded, size: 72, color: scheme.primary),
            const SizedBox(height: 24),
            Text(
              engine.dict.value("intro_assistant_title"),
              style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              engine.dict.value("intro_assistant_desc"),
              style: textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            cards.cardGroup([
              if (!_isDefaultAssistant)
                CardContents.tapIcon(
                  title: engine.dict.value("intro_assistant_action"),
                  subtitle: engine.dict.value("set_as_default_assistant_desc"),
                  icon: Icons.assistant_rounded,
                  colorBG: scheme.primaryContainer,
                  color: scheme.onPrimaryContainer,
                  action: () async {
                    await engine.gemini.openAssistantSettings();
                    await Future.delayed(const Duration(seconds: 1));
                    _checkAssistantStatus();
                  },
                )
              else
                CardContents.static(
                  title: engine.dict.value("default_assistant_active"),
                  subtitle: engine.dict.value("default_assistant_active_desc"),
                ),
            ]),
            const SizedBox(height: 16),
            Text(
              engine.dict.value("intro_assistant_later"),
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),

      // Slide A-4: Preparing Gemini Nano (Exact custom card & Relaunch Quirk)
      _buildSlideContainer(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.psychology_rounded, size: 72, color: scheme.primary),
            const SizedBox(height: 24),
            Text(
              engine.dict.value("intro_gemini_nano_title"),
              style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              engine.dict.value("intro_gemini_nano_desc"),
              style: textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Category.settings(
              title: engine.dict.value("settings_status"),
              context: context,
            ),
            cards.cardGroup([
              // Active download with byte progress and speed
              if (engine.modelDownloadLog.isNotEmpty &&
                  engine.modelDownloadLog.last["status"] == "Download" &&
                  engine.modelDownloadLog.last["info"] != "Error") ...[
                if ((int.tryParse(engine.modelDownloadLog.last["value"].toString()) ?? 0) > 0)
                  CardContents.progress(
                    title: engine.dict.value(engine.modelDownloadLog.last["info"].toString()),
                    subtitle:
                        "${_convertSize(int.parse(engine.modelDownloadLog.last["value"].toString()), false)} / ${_convertSize(engine.usualModelSize, false)} (${((int.parse(engine.modelDownloadLog.last["value"].toString()) / engine.usualModelSize) * 100).toStringAsFixed(1)}%)",
                    subsubtitle: engine.modelDownloadLog.last["info"] == "waiting_network"
                        ? ""
                        : _calcSpeed(engine.modelDownloadLog),
                    progress: (int.parse(engine.modelDownloadLog.last["value"].toString()) /
                        engine.usualModelSize),
                  )
                else
                  CardContents.progress(
                    title: engine.dict.value(engine.modelDownloadLog.last["info"].toString()),
                    subtitle: engine.dict.value("aicore_background_download"),
                    subsubtitle: "",
                    progress: 0.0,
                  ),
              ],

              // Success / Ready state
              if (engine.isAvailable ||
                  (engine.modelDownloadLog.isNotEmpty &&
                      engine.modelDownloadLog.last["status"] == "Available"))
                CardContents.tapIcon(
                  title: "Gemini Nano Ready",
                  subtitle: engine.modelInfo["version"] == null
                      ? engine.dict.value("available")
                      : engine.dict
                          .value("model_available")
                          .replaceAll("%s", engine.modelInfo["version"].toString()),
                  icon: Icons.check_circle_rounded,
                  colorBG: scheme.primaryContainer,
                  color: scheme.primary,
                  action: () {},
                ),

              // Error state
              if (engine.modelDownloadLog.isNotEmpty &&
                  engine.modelDownloadLog.last["status"] == "Error")
                CardContents.doubleTap(
                  title: "Model ${engine.dict.value("unavailable")}",
                  subtitle: engine.dict.value("whoops"),
                  action: () async => engine.gemini.openAICorePlayStore(),
                  secondAction: () {
                    engine.modelDownloadLog.clear();
                    engine.checkEngine();
                  },
                  icon: Icons.refresh_rounded,
                ),

              // The Relaunch Quirk: empty log or waiting for broadcast (only when model is not already available)
              if (engine.modelDownloadLog.isEmpty && !engine.isAvailable)
                CardContents.progress(
                  title: engine.dict.value("downloading_model"),
                  subtitle: engine.dict.value("aicore_background_download"),
                  subsubtitle: "",
                  progress: null, // Indeterminate progress indicator
                ),

              // Logs button
              CardContents.tap(
                title: engine.dict.value(
                  engine.analytics ? "logs_with_analytics" : "logs_no_analytics",
                ),
                subtitle: "",
                action: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LogsPage(),
                      settings: const RouteSettings(name: 'LogsPage'),
                    ),
                  );
                },
              ),
            ]),
            const SizedBox(height: 12),
            if (engine.modelDownloadLog.isNotEmpty &&
                engine.modelDownloadLog.last["info"] == "downloading_model")
              text.infoShort(
                title: engine.dict.value("welcome_gtfo"),
                subtitle: "",
                action: () {},
                context: context,
              ),
          ],
        ),
      ),

      // Slide A-5: Choose Default Prompt
      _buildSlideContainer(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.psychology_rounded, size: 72, color: scheme.primary),
            const SizedBox(height: 24),
            Text(
              engine.dict.value("intro_prompt_title"),
              style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              engine.dict.value("intro_prompt_desc"),
              style: textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ...engine.promptData.defaultPrompts.values.map((prompt) {
              final id = prompt["id"]?.toString() ?? "";
              final name = prompt["name"]?.toString() ?? id;
              final desc = prompt["description"]?.toString() ?? "";
              final isSelected = engine.config.defaultPromptId == id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ChoiceCard(
                  icon: _iconForPrompt(id),
                  title: name,
                  subtitle: desc,
                  selected: isSelected,
                  onTap: () async {
                    setState(() => engine.config.defaultPromptId = id);
                    await engine.saveSettings();
                    await engine.syncActivePersonaToNative();
                  },
                ),
              );
            }),
          ],
        ),
      ),

      // Slide A-6: Local Agentic Mesh & Tool Calling
      _buildSlideContainer(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.hub_rounded, size: 72, color: scheme.primary),
            const SizedBox(height: 24),
            Text(
              engine.dict.value("intro_mesh_title"),
              style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              engine.dict.value("intro_mesh_desc"),
              style: textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Category.settings(
              title: engine.dict.value("mesh_ecosystem_showcase"),
              context: context,
            ),
            cards.cardGroup([
              ..._meshProposals
                  .where((p) => (p['status']?.toString().toLowerCase() ?? '') == 'available')
                  .toList()
                  .asMap()
                  .entries
                  .map((entry) {
                final idx = entry.key;
                final p = entry.value;
                final pkg = p['package']?.toString() ?? '';
                final title = (pkg.isNotEmpty ? _meshAppLabels[AIEngine.canonicalExtensionId(pkg)] : null) ??
                    p['name']?.toString() ??
                    pkg;
                final desc = p['description']?.toString() ?? '';
                final url = p['url']?.toString();
                final usePrimary = idx.isEven;
                return CardContents.tapIcon(
                  title: title,
                  subtitle: desc,
                  icon: _iconForMeshProposal(p['icon']?.toString()),
                  colorBG: usePrimary ? scheme.primaryContainer : scheme.secondaryContainer,
                  color: usePrimary ? scheme.onPrimaryContainer : scheme.onSecondaryContainer,
                  action: () async {
                    if (url != null && url.trim().isNotEmpty) {
                      await launchUrl(
                        Uri.parse(url.trim()),
                        mode: LaunchMode.externalApplication,
                      );
                    } else if (pkg.isNotEmpty) {
                      await launchUrl(
                        Uri.parse('market://details?id=$pkg'),
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                );
              }),
              CardContents.tapIcon(
                title: engine.dict.value("mesh_control_title"),
                subtitle: engine.dict.value("mesh_control_desc"),
                icon: Icons.tune_rounded,
                colorBG: scheme.surfaceContainerHighest,
                color: scheme.onSurfaceVariant,
                action: () {},
              ),
            ]),
            if (engine.toolRegistry.tools.where((tool) => tool.name != 'query_local_ai' && tool.name != 'get_ai_status').isNotEmpty) ...[
              const SizedBox(height: 20),
              Category.settings(
                title: engine.dict.value("mesh_detected_tools"),
                context: context,
              ),
              cards.cardGroup([
                ...engine.toolRegistry.tools
                    .where((tool) => tool.name != 'query_local_ai' && tool.name != 'get_ai_status')
                    .map((tool) {
                  final extId = AIEngine.canonicalToolExtensionId(tool);
                  final appLabel = extId.isEmpty
                      ? 'LOCAL'
                      : _labelForExtension(extId).toUpperCase();
                  return CardContents.static(
                    title: tool.name,
                    subtitle: "[$appLabel] ${tool.description}",
                  );
                }),
              ]),
            ],
            const SizedBox(height: 12),
            cards.cardGroup([
              CardContents.tapIcon(
                colorBG: scheme.primaryFixedDim,
                color: scheme.onPrimaryFixed,
                title: engine.dict.value("mesh_dev_docs"),
                subtitle: "https://github.com/Puzzaks/PAIOS#agentic-mesh",
                icon: Icons.open_in_new_rounded,
                action: () => launchUrl(
                  Uri.parse("https://github.com/Puzzaks/PAIOS#agentic-mesh"),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ]),
          ],
        ),
      ),
    ];
  }

  // в”Ђв”Ђ BRANCH B: AICORE NOT DETECTED / UNSUPPORTED в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ

  List<Widget> _buildBranchBSlides(
    BuildContext context,
    AIEngine engine,
    Cards cards,
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    final filteredDevices = _deviceSearchQuery.trim().isEmpty
        ? _knownSupportedDevices
        : _knownSupportedDevices
            .where((d) => d.toLowerCase().contains(_deviceSearchQuery.toLowerCase()))
            .toList();

    return [
      // Slide B-1: Compatibility Check & Searchable Catalog
      _buildSlideContainer(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.phonelink_erase_rounded, size: 72, color: scheme.error),
            const SizedBox(height: 24),
            Text(
              engine.dict.value("intro_aicore_unsupported_title"),
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: scheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              engine.dict.value("intro_aicore_unsupported_desc"),
              style: textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Category.settings(
              title: engine.dict.value("device_hardware_info"),
              context: context,
            ),
            cards.cardGroup([
              CardContents.static(
                title: engine.dict.value("your_device"),
                subtitle: engine.modelInfo["deviceModel"]?.toString() ?? "Android Device",
              ),
              CardContents.static(
                title: engine.dict.value("os_version"),
                subtitle: engine.modelInfo["osVersion"]?.toString() ?? "Android",
              ),
              CardContents.static(
                title: engine.dict.value("aicore_status"),
                subtitle: engine.modelInfo["aicoreInstalled"] == "true"
                    ? "Installed (Model Inactive)"
                    : engine.dict.value("aicore_unavailable"),
              ),
            ]),
            const SizedBox(height: 20),
            Category.settings(
              title: engine.dict.value("supported_devices_catalog"),
              context: context,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _deviceSearchCtrl,
                decoration: InputDecoration(
                  hintText: engine.dict.value("search_devices"),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _deviceSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _deviceSearchCtrl.clear();
                            setState(() => _deviceSearchQuery = "");
                          },
                        )
                      : null,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (q) => setState(() => _deviceSearchQuery = q),
              ),
            ),
            const SizedBox(height: 8),
            cards.cardGroup([
              for (final device in filteredDevices.take(4))
                CardContents.static(
                  title: device,
                  subtitle: "Official AICore / Gemini Nano Tier",
                ),
            ]),
          ],
        ),
      ),

      // Slide B-2: Troubleshooting & 5 Action Buttons
      _buildSlideContainer(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.bug_report_rounded, size: 72, color: scheme.primary),
            const SizedBox(height: 24),
            Text(
              engine.dict.value("intro_troubleshooting_title"),
              style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            cards.cardGroup([
              CardContents.static(
                title: "1. Android Settings",
                subtitle: engine.dict.value("troubleshooting_tip_1"),
              ),
              CardContents.static(
                title: "2. Google Play Services",
                subtitle: engine.dict.value("troubleshooting_tip_2"),
              ),
              CardContents.static(
                title: "3. Developer Options",
                subtitle: engine.dict.value("troubleshooting_tip_3"),
              ),
            ]),
            const SizedBox(height: 24),
            Category.settings(
              title: "Actions",
              context: context,
            ),
            cards.cardGroup([
              // 1. Copy Diagnostic Report
              CardContents.tapIcon(
                title: engine.dict.value("btn_copy_diagnostic"),
                subtitle: "Survives clipboard wipe; paste into GitHub issues",
                icon: Icons.copy_all_rounded,
                colorBG: scheme.primaryContainer,
                color: scheme.onPrimaryContainer,
                action: () async {
                  final report = _generateDiagnosticReport(engine);
                  await Clipboard.setData(ClipboardData(text: report));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(engine.dict.value("diagnostic_copied")),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                },
              ),

              // 2. Open In-App Docs Explorer
              CardContents.tapIcon(
                title: engine.dict.value("btn_open_docs"),
                subtitle: "View architecture, guides, and model docs",
                icon: Icons.menu_book_rounded,
                colorBG: scheme.primaryFixedDim,
                color: scheme.onPrimaryFixed,
                action: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DocExplorerPage(),
                      settings: const RouteSettings(name: 'DocExplorerPage'),
                    ),
                  );
                },
              ),

              // 3. Open In-App GitHub Explorer
              CardContents.tapIcon(
                title: engine.dict.value("btn_open_github"),
                subtitle: "Issues, releases, and repository tracker",
                icon: Icons.explore_rounded,
                colorBG: scheme.primaryFixedDim,
                color: scheme.onPrimaryFixed,
                action: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const GitHubExplorerPage(),
                      settings: const RouteSettings(name: 'GitHubExplorerPage'),
                    ),
                  );
                },
              ),

              // 4. Create Issue on GitHub
              CardContents.tapIcon(
                title: engine.dict.value("btn_create_issue"),
                subtitle: "https://github.com/Puzzaks/PAIOS/issues/new",
                icon: Icons.add_circle_outline_rounded,
                colorBG: scheme.primaryFixedDim,
                color: scheme.onPrimaryFixed,
                action: () => launchUrl(
                  Uri.parse("https://github.com/Puzzaks/PAIOS/issues/new"),
                  mode: LaunchMode.externalApplication,
                ),
              ),

              // 5. Re-check AICore Status
              CardContents.tapIcon(
                title: engine.dict.value("btn_recheck_status"),
                subtitle: "Instantly re-query Gemini Nano and AICore",
                icon: Icons.refresh_rounded,
                colorBG: scheme.tertiaryContainer,
                color: scheme.onTertiaryContainer,
                action: () {
                  engine.modelDownloadLog.clear();
                  engine.checkEngine();
                },
              ),
            ]),
          ],
        ),
      ),
    ];
  }

  // в”Ђв”Ђ REMOTE CONFIGURABLE SLIDE в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ

  Widget _buildRemoteSlide(
    BuildContext context,
    AIEngine engine,
    Map<String, dynamic> slide,
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    final icon = IntroSlideRepository.getIcon(slide['icon']?.toString());
    final titleKey = slide['title_key']?.toString() ?? "";
    final descKey = slide['desc_key']?.toString() ?? "";
    final actionLabelKey = slide['action_label_key']?.toString() ?? "learn_more";
    final isCommunity = slide['id'] == 'open_source_community' || titleKey == 'intro_slide_community_title';
    final actionUrl = isCommunity
        ? "https://github.com/Puzzaks/PAIOS"
        : slide['action_url']?.toString();

    final title = isCommunity
        ? "Fully Open-Source"
        : (engine.dict.value(titleKey).isNotEmpty ? engine.dict.value(titleKey) : (slide['title']?.toString() ?? ""));
    final desc = engine.dict.value(descKey);
    final actionLabel = isCommunity
        ? "GitHub Repository"
        : (engine.dict.value(actionLabelKey).isNotEmpty ? engine.dict.value(actionLabelKey) : "Open");

    return _buildSlideContainer(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 72, color: scheme.primary),
          const SizedBox(height: 28),
          Text(
            title.isNotEmpty ? title : (slide['title']?.toString() ?? ""),
            style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            desc.isNotEmpty ? desc : (slide['description']?.toString() ?? ""),
            style: textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          if (actionUrl != null && actionUrl.isNotEmpty) ...[
            const SizedBox(height: 32),
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              label: Text(actionLabel.isNotEmpty ? actionLabel : "Open"),
              onPressed: () => launchUrl(
                Uri.parse(actionUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // в”Ђв”Ђ SLIDE CONTAINER HELPER в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ

  Widget _buildSlideContainer({required Widget child}) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: child,
        ),
      ),
    );
  }
}
