import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:m3x_mesh/m3x_mesh.dart';
import 'package:m3x_ui/m3x_ui.dart' show MotionBlurContainer;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../engine.dart';
import '../support/elements.dart';

class ExtensionsSettingsPage extends StatefulWidget {
  const ExtensionsSettingsPage({super.key});

  @override
  State<ExtensionsSettingsPage> createState() => _ExtensionsSettingsPageState();
}

class _ExtensionsSettingsPageState extends State<ExtensionsSettingsPage> {
  bool _isLoading = true;
  List<String> _connectedPackages = [];
  Map<String, List<M3xTool>> _groupedTools = {};
  Map<String, String> _appLabels = {};
  List<Map<String, dynamic>> _allProposals = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Map<String, dynamic>? _findProposal(String pkg) {
    final canon = AIEngine.canonicalExtensionId(pkg);
    for (final p in _allProposals) {
      if (AIEngine.canonicalExtensionId(p['package']?.toString() ?? '') == canon) {
        return p;
      }
    }
    return null;
  }

  IconData _resolveIcon(String? iconName) {
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

  String _formatPackageTitle(String pkg) {
    final canon = AIEngine.canonicalExtensionId(pkg);
    final resolvedLabel = _appLabels[canon];
    if (resolvedLabel != null && resolvedLabel.isNotEmpty) {
      return resolvedLabel;
    }
    final proposalName = _findProposal(canon)?['name']?.toString();
    if (proposalName != null && proposalName.trim().isNotEmpty) {
      return proposalName.trim();
    }
    final parts = canon.split('.');
    if (parts.isNotEmpty) {
      final last = parts.last.trim();
      if (last.isNotEmpty) {
        return last[0].toUpperCase() + last.substring(1);
      }
    }
    return pkg;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final engine = Provider.of<AIEngine>(context, listen: false);

    // 1. Load proposals
    List<Map<String, dynamic>> proposals = [];
    try {
      final jsonStr = await rootBundle.loadString('assets/data/mesh_proposals.json');
      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        proposals = decoded.cast<Map<String, dynamic>>();
      }
    } catch (_) {}

    // 2. Discover installed apps & tools
    List<String> apps = [];
    List<M3xTool> tools = [];
    try {
      apps = await engine.meshClient.listMeshApps();
    } catch (_) {}

    try {
      tools = await engine.meshClient.discoverInstalledTools();
    } catch (_) {}

    final selfPkg = AIEngine.canonicalExtensionId('paios');
    final Map<String, List<M3xTool>> grouped = {};
    for (final t in tools) {
      final rawPkg = (t.packageName != null && t.packageName!.trim().isNotEmpty)
          ? t.packageName!
          : (t.app ?? 'unknown');
      final appPkg = AIEngine.canonicalExtensionId(rawPkg);
      if (appPkg == selfPkg) continue;
      grouped.putIfAbsent(appPkg, () => []).add(t);
    }

    // Include registered tools from engine.toolRegistry
    for (final t in engine.toolRegistry.tools) {
      final rawPkg = (t.packageName != null && t.packageName!.trim().isNotEmpty)
          ? t.packageName!
          : (t.app ?? 'unknown');
      final appPkg = AIEngine.canonicalExtensionId(rawPkg);
      if (appPkg == selfPkg) continue;
      if (!grouped.containsKey(appPkg)) {
        grouped[appPkg] = [t];
      } else if (!grouped[appPkg]!.any((existing) => existing.name == t.name)) {
        grouped[appPkg]!.add(t);
      }
    }

    // Canonicalize apps list and merge
    final canonicalApps = apps.map((a) => AIEngine.canonicalExtensionId(a)).toSet();
    final Set<String> allPkgs = {...canonicalApps, ...grouped.keys}..removeWhere((p) => p == selfPkg);

    // Also verify whether each proposal in mesh_proposals.json is installed via native package manager
    for (final p in proposals) {
      final pkg = p['package']?.toString() ?? '';
      if (pkg.isNotEmpty) {
        final canon = AIEngine.canonicalExtensionId(pkg);
        if (!allPkgs.contains(canon)) {
          final isInst = await engine.isPackageInstalled(pkg);
          if (isInst) {
            allPkgs.add(canon);
          }
        }
      }
    }

    // 3. Dynamically resolve human-readable app labels via Android PackageManager
    final Map<String, String> labels = {};
    for (final pkg in allPkgs) {
      try {
        final label = await engine.meshClient.getAppLabel(pkg);
        if (label != null && label.trim().isNotEmpty) {
          labels[pkg] = label.trim();
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _allProposals = proposals;
        _connectedPackages = allPkgs.toList();
        _groupedTools = grouped;
        _appLabels = labels;
        _isLoading = false;
      });
    }
  }

  Future<void> _openStoreOrRepo(String pkg, String? fallbackUrl) async {
    final canon = AIEngine.canonicalExtensionId(pkg);
    final marketUri = Uri.parse('market://details?id=$canon');
    try {
      final launched = await launchUrl(marketUri, mode: LaunchMode.externalApplication);
      if (launched) return;
    } catch (_) {}

    final urlStr = (fallbackUrl != null && fallbackUrl.trim().isNotEmpty)
        ? fallbackUrl.trim()
        : null;
    if (urlStr == null) return;
    try {
      await launchUrl(Uri.parse(urlStr), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _showExtensionDetails(BuildContext context, String pkg, List<M3xTool> tools, bool isEnabled) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final engine = Provider.of<AIEngine>(context, listen: false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (bottomSheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          _resolveIcon(_findProposal(pkg)?['icon']?.toString()),
                          color: scheme.onPrimaryContainer,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatPackageTitle(pkg),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              pkg,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isEnabled ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isEnabled
                              ? engine.dict.value("extension_active")
                              : engine.dict.value("extension_disabled"),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isEnabled ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          "${engine.dict.value("tools_count")} (${tools.length})",
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (tools.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Center(
                            child: Text(
                              engine.dict.value("no_tool_schemas"),
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        )
                      else
                        ...tools.map((tool) {
                          final props = (tool.parameters['properties'] is Map)
                              ? (tool.parameters['properties'] as Map)
                              : const {};
                          final reqList = (tool.parameters['required'] is List)
                              ? (tool.parameters['required'] as List)
                              : const [];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.build_circle_rounded, size: 20, color: scheme.primary),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        tool.name,
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: scheme.secondaryContainer,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        engine.dict.value("tool_live"),
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: scheme.onSecondaryContainer,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (tool.description.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    tool.description,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Text(
                                  engine.dict.value("parameters_schema"),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                if (props.isEmpty)
                                  Text(
                                    engine.dict.value("no_parameters"),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  )
                                else
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: scheme.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: props.entries.map((entry) {
                                        final propName = entry.key.toString();
                                        final propDetails = entry.value is Map ? entry.value as Map : {};
                                        final propType = propDetails['type']?.toString() ?? 'any';
                                        final propDesc = propDetails['description']?.toString() ?? '';
                                        final isReq = reqList.contains(propName);

                                        return Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 4),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                propName,
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  fontFamily: 'monospace',
                                                  color: scheme.primary,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                "($propType)",
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  color: scheme.onSurfaceVariant,
                                                  fontSize: 11,
                                                ),
                                              ),
                                              if (isReq) ...[
                                                const SizedBox(width: 4),
                                                Text(
                                                  "*",
                                                  style: TextStyle(
                                                    color: scheme.error,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                              if (propDesc.isNotEmpty) ...[
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    propDesc,
                                                    style: theme.textTheme.bodySmall?.copyWith(
                                                      color: scheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cards = Cards(context: context);
          return Consumer<AIEngine>(
            builder: (context, engine, child) {
              final scheme = Theme.of(context).colorScheme;

              // Filter proposals: SKIP any proposal whose package is already connected
              final uninstalledProposals = _allProposals.where((p) {
                final pkg = p['package']?.toString() ?? '';
                if (pkg.isEmpty) return false;
                final canon = AIEngine.canonicalExtensionId(pkg);
                return !_connectedPackages.contains(canon) && !_groupedTools.containsKey(canon);
              }).toList();

              return Scaffold(
                body: CustomScrollView(
                  slivers: [
                    SliverAppBar.large(
                      surfaceTintColor: Colors.transparent,
                      leading: Padding(
                        padding: const EdgeInsets.only(left: 5),
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                      title: Text(engine.dict.value("extensions")),
                      pinned: true,
                    ),
                    SliverToBoxAdapter(
                      child: MotionBlurContainer(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Section 1: Master Switch
                            Category.settings(
                              title: engine.dict.value("settings_app"),
                              context: context,
                            ),
                            cards.cardGroup([
                              CardContents.turn(
                                title: engine.dict.value("allow_all_extensions"),
                                subtitle: engine.dict.value("allow_all_extensions_desc"),
                                action: () async {
                                  final newVal = !engine.allowAllNewExtensions;
                                  await engine.setAllowAllNewExtensions(newVal);
                                  setState(() {});
                                },
                                switcher: (val) async {
                                  await engine.setAllowAllNewExtensions(val);
                                  setState(() {});
                                },
                                value: engine.allowAllNewExtensions,
                              ),
                            ]),

                            // Section 2: Connected Extensions
                            Category.settings(
                              title: engine.dict.value("connected_extensions"),
                              context: context,
                            ),
                            if (_isLoading)
                              cards.cardGroup([
                                Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                              ])
                            else if (_connectedPackages.isEmpty)
                              cards.cardGroup([
                                CardContents.static(
                                  title: engine.dict.value("no_connected_extensions"),
                                  subtitle: engine.dict.value("no_connected_extensions_desc"),
                                ),
                              ])
                            else
                              cards.cardGroup(
                                _connectedPackages.map((pkg) {
                                  final tools = _groupedTools[pkg] ?? [];
                                  final isEnabled = engine.isExtensionEnabled(pkg);
                                  final title = _formatPackageTitle(pkg);
                                  final iconData = _resolveIcon(
                                    _findProposal(pkg)?['icon']?.toString(),
                                  );

                                  return InkWell(
                                    onTap: () => _showExtensionDetails(context, pkg, tools, isEnabled),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: isEnabled ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Icon(
                                              iconData,
                                              color: isEnabled ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                                              size: 22,
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  title,
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  "${tools.length} ${tools.length == 1 ? engine.dict.value("tool_singular") : engine.dict.value("tool_plural")} • $pkg",
                                                  style: TextStyle(
                                                    color: scheme.onSurfaceVariant,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Switch(
                                            value: isEnabled,
                                            onChanged: (val) async {
                                              await engine.setExtensionEnabled(pkg, val);
                                              setState(() {});
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),

                            // Section 3: Works with PAIOS
                            if (uninstalledProposals.isNotEmpty) ...[
                              Category.settings(
                                title: engine.dict.value("works_with_paios"),
                                context: context,
                              ),
                              cards.cardGroup(
                                uninstalledProposals.map((proposal) {
                                  final name = proposal['name']?.toString() ?? '';
                                  final desc = proposal['description']?.toString() ?? '';
                                  final pkg = proposal['package']?.toString() ?? '';
                                  final status = proposal['status']?.toString() ?? 'Proposal';
                                  final iconName = proposal['icon']?.toString();
                                  final iconData = _resolveIcon(iconName);
                                  final isAvailable = status.toLowerCase() == 'available';

                                  return InkWell(
                                    onTap: () => _openStoreOrRepo(pkg, proposal['url']?.toString()),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: isAvailable ? scheme.secondaryContainer : scheme.surfaceContainerHighest,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Icon(
                                              iconData,
                                              color: isAvailable ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
                                              size: 22,
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        name,
                                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                                      ),
                                                    ),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: isAvailable ? scheme.primaryContainer : scheme.surfaceContainerHigh,
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Text(
                                                        status,
                                                        style: TextStyle(
                                                          color: isAvailable ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  desc,
                                                  style: TextStyle(
                                                    color: scheme.onSurfaceVariant,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Text(
                                                      pkg,
                                                      style: TextStyle(
                                                        color: scheme.outline,
                                                        fontSize: 11,
                                                        fontFamily: 'monospace',
                                                      ),
                                                    ),
                                                    const Spacer(),
                                                    Icon(
                                                      Icons.open_in_new_rounded,
                                                      size: 16,
                                                      color: scheme.primary,
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],

                            const SizedBox(height: 32),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24.0),
                              child: Text(
                                engine.dict.value("extensions_ipc_footer"),
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
