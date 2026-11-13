import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../engine.dart';
import '../../services/doc_service.dart';

/// In-App Multi-Page Documentation Explorer & Technical Reference for Google ML Kit GenAI & AICore.
/// Supports 3-Tier SWR caching, instant offline availability, and cross-page live search.
class DocExplorerPage extends StatefulWidget {
  const DocExplorerPage({super.key});

  /// Navigates directly to [DocExplorerPage].
  static Future<void> open(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const DocExplorerPage(),
        settings: const RouteSettings(name: 'DocExplorerPage'),
      ),
    );
  }

  /// Convenience [Route] factory.
  static Route<void> route() {
    return MaterialPageRoute(
      builder: (context) => const DocExplorerPage(),
      settings: const RouteSettings(name: 'DocExplorerPage'),
    );
  }

  @override
  State<DocExplorerPage> createState() => _DocExplorerPageState();
}

class _DocExplorerPageState extends State<DocExplorerPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final Map<String, GlobalKey> _sectionKeys = {};

  String _searchQuery = '';
  int? _activeChipIndex;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    DocService.instance.addListener(_onDocServiceChanged);
    _searchCtrl.addListener(_onSearchChanged);
    _initDocs();
  }

  @override
  void dispose() {
    DocService.instance.removeListener(_onDocServiceChanged);
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onDocServiceChanged() {
    if (mounted) {
      _ensureSectionKeys();
      setState(() {});
    }
  }

  Future<void> _initDocs() async {
    if (!DocService.instance.isLoaded) {
      setState(() => _isLoading = true);
      await DocService.instance.initialize();
    }
    _ensureSectionKeys();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _ensureSectionKeys() {
    final page = DocService.instance.currentPage;
    if (page != null) {
      for (final section in page.sections) {
        _sectionKeys.putIfAbsent('${page.id}_${section.id}', () => GlobalKey());
      }
    }
  }

  void _onSearchChanged() {
    final query = _searchCtrl.text.trim();
    if (query == _searchQuery) return;
    setState(() {
      _searchQuery = query;
      _activeChipIndex = null;
    });
  }

  Future<void> _onRefreshTapped(DocPage page) async {
    final docService = DocService.instance;
    if (docService.isSyncing) return;
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Refreshing "${page.title}" from remote...'),
        duration: const Duration(milliseconds: 1000),
      ),
    );
    final success = await docService.refreshDoc(page.id);
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Updated from Google Developers'
                : 'Using offline bundled "${page.title}"',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _scrollToSection(int index, String keyId) {
    HapticFeedback.lightImpact();
    setState(() => _activeChipIndex = index);
    final key = _sectionKeys[keyId];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
        alignment: 0.05,
      );
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return '${dt.month}/${dt.day}';
  }

  IconData _getPageIcon(String iconName) {
    switch (iconName) {
      case 'devices':
        return Icons.devices_rounded;
      case 'science':
        return Icons.science_rounded;
      case 'smart_toy':
        return Icons.smart_toy_rounded;
      case 'record_voice_over':
        return Icons.record_voice_over_rounded;
      case 'terminal':
        return Icons.terminal_rounded;
      case 'data_object':
        return Icons.data_object_rounded;
      case 'translate':
        return Icons.translate_rounded;
      case 'auto_stories':
        return Icons.auto_stories_rounded;
      default:
        return Icons.article_rounded;
    }
  }

  IconData _getSectionIcon(String id) {
    final lower = id.toLowerCase();
    if (lower.contains('device') || lower.contains('hardware')) return Icons.devices_rounded;
    if (lower.contains('aicore') || lower.contains('prerequisite') || lower.contains('beta')) {
      return Icons.memory_rounded;
    }
    if (lower.contains('prompt') || lower.contains('instruction') || lower.contains('model')) {
      return Icons.terminal_rounded;
    }
    if (lower.contains('token') || lower.contains('quota') || lower.contains('limit')) {
      return Icons.data_usage_rounded;
    }
    if (lower.contains('error') || lower.contains('troubleshoot')) return Icons.bug_report_rounded;
    if (lower.contains('vision') || lower.contains('multimodal')) return Icons.visibility_rounded;
    if (lower.contains('agent') || lower.contains('workflow')) return Icons.smart_toy_rounded;
    if (lower.contains('speech') || lower.contains('voice') || lower.contains('tts')) {
      return Icons.record_voice_over_rounded;
    }
    if (lower.contains('struct') || lower.contains('schema') || lower.contains('json')) {
      return Icons.data_object_rounded;
    }
    if (lower.contains('translat')) return Icons.translate_rounded;
    if (lower.contains('summar') || lower.contains('rewrit')) return Icons.auto_stories_rounded;
    return Icons.article_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final engine = context.watch<AIEngine>();
    final docService = DocService.instance;

    final markdownStyle = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurface,
        height: 1.55,
      ),
      h1: theme.textTheme.headlineSmall?.copyWith(
        color: colorScheme.primary,
        fontWeight: FontWeight.bold,
      ),
      h2: theme.textTheme.titleLarge?.copyWith(
        color: colorScheme.primary,
        fontWeight: FontWeight.bold,
      ),
      h3: theme.textTheme.titleMedium?.copyWith(
        color: colorScheme.secondary,
        fontWeight: FontWeight.w600,
      ),
      code: TextStyle(
        color: colorScheme.onSurfaceVariant,
        backgroundColor: colorScheme.surfaceContainerHighest,
        fontFamily: 'monospace',
        fontSize: 13,
      ),
      codeblockDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      tableHead: TextStyle(
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      tableBody: TextStyle(
        color: colorScheme.onSurface,
      ),
      tableBorder: TableBorder.all(
        color: colorScheme.outlineVariant,
        width: 1,
        borderRadius: BorderRadius.circular(8),
      ),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      tableColumnWidth: const IntrinsicColumnWidth(),
      blockquoteDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          left: BorderSide(color: colorScheme.primary, width: 4),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      a: TextStyle(
        color: colorScheme.primary,
        decoration: TextDecoration.underline,
      ),
    );

    final currentPage = docService.currentPage;
    final searchResults = _searchQuery.isNotEmpty ? docService.searchAll(_searchQuery) : <DocSearchResult>[];

    return Scaffold(
      body: CustomScrollView(
        controller: _scrollCtrl,
        slivers: [
          SliverAppBar(
            pinned: true,
            floating: true,
            surfaceTintColor: Colors.transparent,
            title: Text(
              engine.dict.value("doc_explorer_title").isNotEmpty
                  ? engine.dict.value("doc_explorer_title")
                  : 'Documentation Explorer',
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              if (docService.isSyncing)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.sync_rounded),
                  tooltip: engine.dict.value("docs_sync_now").isNotEmpty
                      ? engine.dict.value("docs_sync_now")
                      : 'Sync Documentation',
                  onPressed: () async {
                    HapticFeedback.lightImpact();
                    await docService.syncRemoteDocs(force: true);
                  },
                ),
              IconButton(
                icon: const Icon(Icons.open_in_new_rounded),
                tooltip: currentPage != null
                    ? 'Open "${currentPage.title}" in Browser'
                    : 'Official Google Docs',
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  final targetUrl = currentPage?.officialUrl ?? 'https://developers.google.com/ml-kit/genai';
                  await launchUrl(
                    Uri.parse(targetUrl),
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(64),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SearchBar(
                  controller: _searchCtrl,
                  hintText: engine.dict.value("search_docs").isNotEmpty
                      ? engine.dict.value("search_docs")
                      : 'Search all documentation topics...',
                  leading: const Icon(Icons.search_rounded),
                  trailing: [
                    if (_searchQuery.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          _searchCtrl.clear();
                        },
                      ),
                  ],
                  elevation: const WidgetStatePropertyAll(0),
                  backgroundColor: WidgetStatePropertyAll(
                    colorScheme.surfaceContainerHigh,
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Quick Action Buttons
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () async {
                            HapticFeedback.lightImpact();
                            await engine.gemini.openAICoreDevSettings();
                          },
                          icon: const Icon(Icons.developer_mode_rounded, size: 18),
                          label: Text(
                            engine.dict.value("aicore_sys_settings").isNotEmpty
                                ? engine.dict.value("aicore_sys_settings")
                                : 'AICore Settings',
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () async {
                            HapticFeedback.lightImpact();
                            await engine.gemini.openAICorePlayStore();
                          },
                          icon: const Icon(Icons.storefront_rounded, size: 18),
                          label: Text(
                            engine.dict.value("check_play_store").isNotEmpty
                                ? engine.dict.value("check_play_store")
                                : 'Check Play Store',
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Multi-Page Category Chips (Horizontal Selector)
                if (docService.pages.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Guides & Categories',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (currentPage != null)
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: docService.isSyncing
                                  ? null
                                  : () => _onRefreshTapped(currentPage),
                              child: Tooltip(
                                message: 'Tap to refresh this guide from remote',
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: currentPage.isOfflineFallback
                                        ? colorScheme.surfaceContainerHighest
                                        : colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: currentPage.isOfflineFallback
                                          ? colorScheme.outlineVariant
                                          : colorScheme.primary.withValues(alpha: 0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (docService.isSyncing)
                                        Padding(
                                          padding: const EdgeInsets.only(right: 4),
                                          child: SizedBox(
                                            width: 11,
                                            height: 11,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.5,
                                              color: currentPage.isOfflineFallback
                                                  ? colorScheme.onSurfaceVariant
                                                  : colorScheme.onPrimaryContainer,
                                            ),
                                          ),
                                        )
                                      else
                                        Icon(
                                          currentPage.isOfflineFallback
                                              ? Icons.cloud_off_rounded
                                              : Icons.cloud_done_rounded,
                                          size: 13,
                                          color: currentPage.isOfflineFallback
                                              ? colorScheme.onSurfaceVariant
                                              : colorScheme.onPrimaryContainer,
                                        ),
                                      const SizedBox(width: 4),
                                      Text(
                                        currentPage.isOfflineFallback
                                            ? (engine.dict.value("docs_bundled_offline").isNotEmpty
                                                ? '${engine.dict.value("docs_bundled_offline")} ↻'
                                                : 'Bundled Offline ↻')
                                            : (engine.dict.value("docs_synced").isNotEmpty
                                                ? '${engine.dict.value("docs_synced")}${currentPage.lastUpdated != null ? " • ${_formatTime(currentPage.lastUpdated!)}" : ""}'
                                                : 'Synced${currentPage.lastUpdated != null ? " • ${_formatTime(currentPage.lastUpdated!)}" : ""}'),
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: currentPage.isOfflineFallback
                                              ? colorScheme.onSurfaceVariant
                                              : colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 48,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: docService.pages.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final page = docService.pages[index];
                        final isSelected = page.id == docService.selectedPageId;
                        return FilterChip(
                          selected: isSelected,
                          showCheckmark: false,
                          avatar: Icon(
                            _getPageIcon(page.icon),
                            size: 16,
                            color: isSelected
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurfaceVariant,
                          ),
                          label: Text(page.title),
                          onSelected: (_) {
                            HapticFeedback.lightImpact();
                            docService.selectPage(page.id);
                            _ensureSectionKeys();
                            if (_scrollCtrl.hasClients) {
                              _scrollCtrl.animateTo(
                                0,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                              );
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],

                // Table of Contents for Active Page (shown when not searching)
                if (_searchQuery.isEmpty && currentPage != null && currentPage.sections.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      engine.dict.value("docs_table_of_contents").isNotEmpty
                          ? engine.dict.value("docs_table_of_contents")
                          : 'Table of Contents',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 42,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: currentPage.sections.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final section = currentPage.sections[index];
                        final isSelected = _activeChipIndex == index;
                        final keyId = '${currentPage.id}_${section.id}';
                        return FilterChip(
                          selected: isSelected,
                          showCheckmark: false,
                          avatar: Icon(
                            _getSectionIcon(section.id),
                            size: 15,
                            color: isSelected
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurfaceVariant,
                          ),
                          label: Text(section.title),
                          onSelected: (_) => _scrollToSection(index, keyId),
                        );
                      },
                    ),
                  ),
                ],

                // Content Area
                if (_isLoading) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ] else if (_searchQuery.isNotEmpty) ...[
                  // Global Search Results View
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      'Search Results for "$_searchQuery" (${searchResults.length})',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (searchResults.isEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              size: 56,
                              color: colorScheme.outline,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No matching documentation found for "$_searchQuery"',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.tonal(
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                _searchCtrl.clear();
                              },
                              child: const Text('Clear search'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    ...searchResults.map((res) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Card(
                          elevation: 0,
                          margin: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(color: colorScheme.outlineVariant),
                          ),
                          color: colorScheme.surfaceContainerLow,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      _getSectionIcon(res.sectionTitle),
                                      color: colorScheme.primary,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        res.sectionTitle,
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                    if (res.pageTitle.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: colorScheme.surfaceContainerHigh,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          res.pageTitle,
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const Divider(height: 20),
                                MarkdownBody(
                                  data: res.content,
                                  selectable: true,
                                  styleSheet: markdownStyle,
                                  onTapLink: (text, href, title) async {
                                    if (href != null) {
                                      final uri = Uri.tryParse(href);
                                      if (uri != null) {
                                        await launchUrl(
                                          uri,
                                          mode: LaunchMode.externalApplication,
                                        );
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 32),
                  ],
                ] else if (currentPage != null) ...[
                  // Active Page Markdown Sections
                  const SizedBox(height: 8),
                  ...currentPage.sections.map((section) {
                    final keyId = '${currentPage.id}_${section.id}';
                    final key = _sectionKeys[keyId];
                    return KeyedSubtree(
                      key: key,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Card(
                          elevation: 0,
                          margin: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(color: colorScheme.outlineVariant),
                          ),
                          color: colorScheme.surfaceContainerLow,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      _getSectionIcon(section.id),
                                      color: colorScheme.primary,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        section.title,
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 24),
                                MarkdownBody(
                                  data: section.content,
                                  selectable: true,
                                  styleSheet: markdownStyle,
                                  onTapLink: (text, href, title) async {
                                    if (href != null) {
                                      final uri = Uri.tryParse(href);
                                      if (uri != null) {
                                        await launchUrl(
                                          uri,
                                          mode: LaunchMode.externalApplication,
                                        );
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Center(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          HapticFeedback.lightImpact();
                          final targetUrl = currentPage.officialUrl ?? 'https://developers.google.com/ml-kit/genai';
                          await launchUrl(
                            Uri.parse(targetUrl),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: Text(
                          'Open "${currentPage.title}" on Google Developers',
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
