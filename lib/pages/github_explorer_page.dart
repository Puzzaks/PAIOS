import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:m3x_ui/m3x_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import '../engine.dart';
import '../services/github_service.dart';

/// Preprocesses raw GitHub Markdown content to properly format HTML tags
/// (such as <div align="center">, <h1>..</h1>, <br>, <img>, <a>) commonly found
/// in GitHub repository READMEs and issue descriptions.
String preprocessGitHubMarkdown(String raw) {
  var md = raw;

  // 1. Remove HTML comments
  md = md.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

  // 2. Convert HTML headers
  md = md.replaceAllMapped(
    RegExp(r'<h1[^>]*>([\s\S]*?)<\/h1>', caseSensitive: false),
    (m) => '\n\n# ${m.group(1)?.trim()}\n\n',
  );
  md = md.replaceAllMapped(
    RegExp(r'<h2[^>]*>([\s\S]*?)<\/h2>', caseSensitive: false),
    (m) => '\n\n## ${m.group(1)?.trim()}\n\n',
  );
  md = md.replaceAllMapped(
    RegExp(r'<h3[^>]*>([\s\S]*?)<\/h3>', caseSensitive: false),
    (m) => '\n\n### ${m.group(1)?.trim()}\n\n',
  );
  md = md.replaceAllMapped(
    RegExp(r'<h4[^>]*>([\s\S]*?)<\/h4>', caseSensitive: false),
    (m) => '\n\n#### ${m.group(1)?.trim()}\n\n',
  );

  // 3. Convert line breaks
  md = md.replaceAll(RegExp(r'<br\s*\/?>', caseSensitive: false), '\n\n');

  // 4. Convert linked badges/images: <a href="url"><img src="imgUrl" alt="alt"></a>
  md = md.replaceAllMapped(
    RegExp(
      r'<a\s+href="([^"]+)"[^>]*>\s*<img\s+src="([^"]+)"[^>]*alt="([^"]*)"[^>]*>\s*<\/a>',
      caseSensitive: false,
    ),
    (m) => ' [![${m.group(3) ?? ""}](${m.group(2)})](${m.group(1)}) ',
  );

  // 5. Convert standalone images: <img src="url" alt="alt">
  md = md.replaceAllMapped(
    RegExp(
      r'<img\s+[^>]*src="([^"]+)"[^>]*alt="([^"]*)"[^>]*>',
      caseSensitive: false,
    ),
    (m) => '\n\n![${m.group(2) ?? ""}](${m.group(1)})\n\n',
  );

  // 6. Convert standalone images without alt
  md = md.replaceAllMapped(
    RegExp(r'<img\s+[^>]*src="([^"]+)"[^>]*>', caseSensitive: false),
    (m) => '\n\n![](${m.group(1)})\n\n',
  );

  // 7. Strip container tags keeping content
  md = md.replaceAll(RegExp(r'<\/?(?:div|p|center|span)[^>]*>', caseSensitive: false), '\n');

  // 8. Replace common HTML entities
  md = md
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"');

  // 9. Normalize excessive newlines
  md = md.replaceAll(RegExp(r'\n{3,}'), '\n\n');

  return md.trim();
}

/// Helper for launching URLs safely.
Future<void> _safeLaunchUrl(String url) async {
  if (url.isEmpty) return;
  final uri = Uri.tryParse(url);
  if (uri != null) {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}

/// Filter mode for GitHub Issues tab.
enum IssueStatusFilter { all, open, closed }

/// GitHub Explorer Page providing repository documentation viewer,
/// issue tracking with filtering and search, releases browser, and security status.
class GitHubExplorerPage extends StatefulWidget {
  final int initialTab;
  const GitHubExplorerPage({super.key, this.initialTab = 0});

  @override
  State<GitHubExplorerPage> createState() => _GitHubExplorerPageState();
}



class _GitHubExplorerPageState extends State<GitHubExplorerPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _tokenCtrl = TextEditingController();
  final TextEditingController _issueSearchCtrl = TextEditingController();

  IssueStatusFilter _issueFilter = IssueStatusFilter.all;
  String _issueSearchQuery = '';

  // Nested document navigation stack: [(path: "docs/architecture.md", title: "Architecture", content: "...")]
  final List<({String path, String title, String content})> _nestedDocStack = [];
  bool _isLoadingNestedDoc = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: (widget.initialTab >= 0 && widget.initialTab < 4)
          ? widget.initialTab
          : 0,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (GitHubService.instance.rootDocs.isEmpty &&
          GitHubService.instance.readmeContent == null) {
        GitHubService.instance.refreshAll();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _tokenCtrl.dispose();
    _issueSearchCtrl.dispose();
    super.dispose();
  }

  Widget _buildMarkdownImage(MarkdownImageConfig config, GitHubService github) {
    final uriStr = config.uri.toString();
    final String fullUrl;
    if (uriStr.startsWith('http://') || uriStr.startsWith('https://')) {
      fullUrl = uriStr;
    } else {
      final cleanPath = uriStr.startsWith('./')
          ? uriStr.substring(2)
          : (uriStr.startsWith('/') ? uriStr.substring(1) : uriStr);
      fullUrl =
          'https://raw.githubusercontent.com/${github.owner}/${github.repo}/HEAD/$cleanPath';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: () => _safeLaunchUrl(fullUrl),
        borderRadius: BorderRadius.circular(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            fullUrl,
            width: config.width,
            height: config.height,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                height: 120,
                alignment: Alignment.center,
                child: const CircularProgressIndicator(strokeWidth: 2),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.broken_image_rounded, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        config.alt != null && config.alt!.isNotEmpty
                            ? config.alt!
                            : 'Image ($uriStr)',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _handleMarkdownLinkTap(
    BuildContext context,
    GitHubService github,
    String? href,
  ) async {
    if (href == null || href.isEmpty) return;

    // 1. Anchor link within page
    if (href.startsWith('#')) return;

    // 2. Check if link points to another root doc (e.g. "./LICENSE", "LICENSE", "SECURITY.md")
    final cleanHref = href.replaceAll('./', '').trim();
    final bool switched = await github.selectDocByPath(cleanHref);
    if (switched) {
      if (_nestedDocStack.isNotEmpty) {
        setState(() {
          _nestedDocStack.clear();
        });
      }
      return;
    }

    // 3. Check if link is a relative path to a subfolder document (e.g. "docs/ROADMAP.md")
    if (!href.startsWith('http://') && !href.startsWith('https://')) {
      setState(() {
        _isLoadingNestedDoc = true;
      });
      final content = await github.fetchArbitraryFileContent(cleanHref);
      if (!mounted) return;
      setState(() {
        _isLoadingNestedDoc = false;
        final docName = cleanHref.split('/').last;
        _nestedDocStack.add((path: cleanHref, title: docName, content: content));
      });
      return;
    }

    // 4. External link or full GitHub URL
    _safeLaunchUrl(href);
  }

  void _showTokenLoginDialog(BuildContext context, GitHubService github) {
    final engine = Provider.of<AIEngine>(context, listen: false);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.vpn_key_rounded, size: 22),
            const SizedBox(width: 8),
            Text(engine.dict.value('gh_auth_dialog_title')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter a Personal Access Token (PAT) with `public_repo` scope to raise API rate limit from 60 to 5,000 requests/hour and view internal security advisories.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tokenCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: engine.dict.value('gh_auth_token'),
                hintText: 'ghp_...',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(engine.dict.value('gh_auth_cancel')),
          ),
          FilledButton(
            onPressed: () async {
              final token = _tokenCtrl.text.trim();
              if (token.isEmpty) return;
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              final success = await github.authenticateWithToken(token);
              if (!mounted) return;
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    success
                        ? 'Signed in as ${github.authUsername} (5,000 req/hr active)'
                        : 'Authentication failed. Check token validity.',
                  ),
                ),
              );
            },
            child: Text(engine.dict.value('gh_auth_save')),
          ),
        ],
      ),
    );
  }

  void _showIssueDetails(BuildContext context, GitHubIssue issue) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _IssueDetailsSheet(issue: issue),
    );
  }

  Widget _buildDocsViewerTab(BuildContext context, GitHubService github) {
    final scheme = Theme.of(context).colorScheme;

    // If currently viewing a nested file from a subfolder
    if (_nestedDocStack.isNotEmpty) {
      final currentNested = _nestedDocStack.last;
      return Column(
        children: [
          // Subfolder breadcrumb header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: scheme.surfaceContainerHigh,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  tooltip: 'Back',
                  onPressed: () {
                    setState(() {
                      _nestedDocStack.removeLast();
                    });
                  },
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    currentNested.path,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Root Docs'),
                  onPressed: () {
                    setState(() {
                      _nestedDocStack.clear();
                    });
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: MotionBlurContainer(
              child: Markdown(
                data: preprocessGitHubMarkdown(currentNested.content),
                selectable: true,
                padding: const EdgeInsets.all(16),
                onTapLink: (linkText, href, title) =>
                    _handleMarkdownLinkTap(context, github, href),
                sizedImageBuilder: (config) =>
                    _buildMarkdownImage(config, github),
              ),
            ),
          ),
        ],
      );
    }

    // Root docs navigation matching GitHub web UI
    final docs = github.rootDocs;
    final activeDoc = github.selectedDoc;
    final String activeContent = activeDoc?.content ??
        github.readmeContent ??
        '_Select a document above or refresh._';

    return Column(
      children: [
        // Horizontal Root Documentation Pills Bar
        if (docs.isNotEmpty)
          Container(
            height: 48,
            color: scheme.surfaceContainerLow,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final doc = docs[index];
                final bool isSelected = activeDoc?.path == doc.path;
                return ChoiceChip(
                  avatar: Icon(
                    doc.icon,
                    size: 16,
                    color: isSelected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                  label: Text(doc.title),
                  selected: isSelected,
                  visualDensity: VisualDensity.compact,
                  onSelected: (selected) {
                    if (selected) {
                      github.selectDoc(doc);
                    }
                  },
                );
              },
            ),
          ),

        if (_isLoadingNestedDoc)
          const LinearProgressIndicator(minHeight: 2),

        Expanded(
          child: MotionBlurContainer(
            child: Markdown(
              data: preprocessGitHubMarkdown(activeContent),
              selectable: true,
              padding: const EdgeInsets.all(16),
              onTapLink: (linkText, href, title) =>
                  _handleMarkdownLinkTap(context, github, href),
              sizedImageBuilder: (config) =>
                  _buildMarkdownImage(config, github),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIssuesTab(
    BuildContext context,
    GitHubService github,
    AIEngine engine,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final allIssues = github.issues;

    final int openCount = allIssues.where((i) => i.state == 'open').length;
    final int closedCount = allIssues.where((i) => i.state == 'closed').length;

    final filtered = allIssues.where((issue) {
      if (_issueFilter == IssueStatusFilter.open && issue.state != 'open') return false;
      if (_issueFilter == IssueStatusFilter.closed && issue.state != 'closed') return false;
      if (_issueSearchQuery.isNotEmpty) {
        final q = _issueSearchQuery.toLowerCase();
        final matchesNum = '#${issue.number}'.contains(q) || issue.number.toString() == q;
        final matchesTitle = issue.title.toLowerCase().contains(q);
        final matchesAuthor = issue.author.toLowerCase().contains(q);
        final matchesLabel = issue.labels.any((l) => l.name.toLowerCase().contains(q));
        if (!matchesNum && !matchesTitle && !matchesAuthor && !matchesLabel) {
          return false;
        }
      }
      return true;
    }).toList();

    return Column(
      children: [
        // Search and Filter Bar
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          color: scheme.surfaceContainerLow,
          child: Column(
            children: [
              TextField(
                controller: _issueSearchCtrl,
                decoration: InputDecoration(
                  hintText: engine.dict.value('gh_search_issues'),
                  hintStyle: const TextStyle(fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _issueSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            setState(() {
                              _issueSearchCtrl.clear();
                              _issueSearchQuery = '';
                            });
                          },
                        )
                      : null,
                  isDense: true,
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                onChanged: (val) {
                  setState(() {
                    _issueSearchQuery = val.trim();
                  });
                },
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text('${engine.dict.value("gh_filter_all")} (${allIssues.length})'),
                      selected: _issueFilter == IssueStatusFilter.all,
                      visualDensity: VisualDensity.compact,
                      onSelected: (sel) {
                        if (sel) setState(() => _issueFilter = IssueStatusFilter.all);
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      avatar: const Icon(Icons.adjust_rounded, size: 14, color: Colors.green),
                      label: Text('${engine.dict.value("gh_filter_open")} ($openCount)'),
                      selected: _issueFilter == IssueStatusFilter.open,
                      visualDensity: VisualDensity.compact,
                      onSelected: (sel) {
                        if (sel) setState(() => _issueFilter = IssueStatusFilter.open);
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      avatar: const Icon(Icons.check_circle_outline_rounded, size: 14, color: Colors.purple),
                      label: Text('${engine.dict.value("gh_filter_closed")} ($closedCount)'),
                      selected: _issueFilter == IssueStatusFilter.closed,
                      visualDensity: VisualDensity.compact,
                      onSelected: (sel) {
                        if (sel) setState(() => _issueFilter = IssueStatusFilter.closed);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Issues List or Empty State
        Expanded(
          child: allIssues.isEmpty
              ? Center(
                  child: TextPart.info(
                    title: engine.dict.value('gh_no_issues'),
                    subtitle: 'Tap here to open GitHub and submit an issue.',
                    action: () => _safeLaunchUrl('https://github.com/${github.owner}/${github.repo}/issues/new'),
                    context: context,
                  ),
                )
              : filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off_rounded, size: 48, color: scheme.outline),
                            const SizedBox(height: 12),
                            Text(
                              'No issues matching "$_issueSearchQuery"',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            FilledButton.tonal(
                              onPressed: () {
                                setState(() {
                                  _issueSearchCtrl.clear();
                                  _issueSearchQuery = '';
                                  _issueFilter = IssueStatusFilter.all;
                                });
                              },
                              child: const Text('Reset Filter'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : MotionBlurContainer(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemBuilder: (ctx, i) {
                          final issue = filtered[i];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 4,
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: issue.state == 'open'
                                    ? Colors.green.shade700
                                    : Colors.purple.shade700,
                                child: Icon(
                                  issue.state == 'open'
                                      ? Icons.adjust_rounded
                                      : Icons.check_circle_outline_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                              title: Text(
                                '#${issue.number} ${issue.title}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 2),
                                  Text(
                                    'Opened by ${issue.author} вЂў ${issue.commentsCount} comments',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  if (issue.labels.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 4,
                                      children: issue.labels.map((l) {
                                        final color = Color(
                                          int.tryParse('FF${l.colorHex}', radix: 16) ?? 0xFF808080,
                                        );
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: color,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            l.name,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.white,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ],
                              ),
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                              ),
                              onTap: () => _showIssueDetails(context, issue),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildReleasesTab(
    BuildContext context,
    GitHubService github,
    AIEngine engine,
  ) {
    final scheme = Theme.of(context).colorScheme;

    if (github.releases.isEmpty) {
      return Center(
        child: TextPart.info(
          title: engine.dict.value('gh_no_releases'),
          subtitle: engine.dict.value('gh_open_github'),
          action: () => _safeLaunchUrl('https://github.com/${github.owner}/${github.repo}'),
          context: context,
        ),
      );
    }

    return MotionBlurContainer(
      child: ListView.builder(
        itemCount: github.releases.length,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemBuilder: (ctx, i) {
          final rel = github.releases[i];
          return Card(
            margin: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 6,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          rel.tagName,
                          style: TextStyle(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          rel.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Published ${rel.publishedAt.length >= 10 ? rel.publishedAt.substring(0, 10) : rel.publishedAt}',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  MarkdownBody(
                    data: preprocessGitHubMarkdown(rel.body),
                    selectable: true,
                    onTapLink: (linkText, href, title) {
                      if (href != null && href.isNotEmpty) {
                        _safeLaunchUrl(href);
                      }
                    },
                  ),
                  if (rel.assets.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Release Assets & Downloads:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: rel.assets.map((asset) {
                        final sizeMb = (asset.sizeBytes / (1024 * 1024)).toStringAsFixed(1);
                        return ActionChip(
                          avatar: const Icon(
                            Icons.download_rounded,
                            size: 16,
                          ),
                          label: Text(
                            '${asset.name} ($sizeMb MB вЂў ${asset.downloadCount} dl)',
                            style: const TextStyle(fontSize: 11),
                          ),
                          onPressed: () => _safeLaunchUrl(asset.downloadUrl),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSecurityTab(BuildContext context, GitHubService github) {
    final scheme = Theme.of(context).colorScheme;

    return MotionBlurContainer(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          Category.settings(
            title: 'Repository Security & Advisories',
            context: context,
          ),
          CardGroup(
            children: [
              CardContents.tapIcon(
                title: 'Dependabot & Alerts',
                subtitle: 'Zero active high-severity vulnerabilities reported',
                icon: Icons.shield_outlined,
                color: Colors.green,
                colorBG: scheme.surfaceContainerHighest,
                action: () => _safeLaunchUrl(
                  'https://github.com/${github.owner}/${github.repo}/security',
                ),
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              ),
              CardContents.tapIcon(
                title: 'License & Governance',
                subtitle: github.licenseName ?? 'Open Source License',
                icon: Icons.gavel_rounded,
                color: Colors.blue,
                colorBG: scheme.surfaceContainerHighest,
                action: () async {
                  await github.selectDocByPath('LICENSE');
                  _tabController.animateTo(0);
                },
                trailing: const Icon(Icons.arrow_forward_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Category.settings(
            title: 'Open Source Transparency',
            context: context,
          ),
          CardGroup(
            children: [
              CardContents.tapIcon(
                title: 'GitHub Issues & Bug Reports',
                subtitle: 'Track regressions, proposals, and community discussions',
                icon: Icons.bug_report_outlined,
                color: scheme.primary,
                colorBG: scheme.surfaceContainerHighest,
                action: () => _tabController.animateTo(1),
                trailing: const Icon(Icons.arrow_forward_rounded, size: 18),
              ),
              CardContents.tapIcon(
                title: 'Verified Releases',
                subtitle: 'Review signed release binaries and changelog notes',
                icon: Icons.new_releases_outlined,
                color: scheme.secondary,
                colorBG: scheme.surfaceContainerHighest,
                action: () => _tabController.animateTo(2),
                trailing: const Icon(Icons.arrow_forward_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextPart.info(
            title: 'All code, assets, and documentation for ${github.owner}/${github.repo} are hosted publicly on GitHub.',
            subtitle: 'Visit Organization on GitHub',
            action: () => _safeLaunchUrl('https://github.com/${github.owner}'),
            context: context,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final engine = Provider.of<AIEngine>(context);

    return ChangeNotifierProvider<GitHubService>.value(
      value: GitHubService.instance,
      child: Consumer<GitHubService>(
        builder: (context, github, _) {
          return Scaffold(
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    engine.dict.value('gh_repo'),
                    style: const TextStyle(fontSize: 16),
                  ),
                  Text(
                    '${github.owner}/${github.repo}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              actions: [
                // Preset Repository Switcher
                PopupMenuButton<({String owner, String repo, String title})>(
                  tooltip: engine.dict.value('gh_switch_repo'),
                  icon: const Icon(Icons.source_rounded),
                  initialValue: GitHubService.presetRepos.firstWhere(
                    (p) => p.owner == github.owner && p.repo == github.repo,
                    orElse: () => GitHubService.presetRepos.first,
                  ),
                  onSelected: (p) =>
                      github.setTargetRepository(p.owner, p.repo),
                  itemBuilder: (ctx) => [
                    for (final p in GitHubService.presetRepos)
                      PopupMenuItem(
                        value: p,
                        child: Text(p.title),
                      ),
                  ],
                ),
                IconButton(
                  tooltip: engine.dict.value('gh_refresh'),
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed:
                      github.isLoading ? null : () => github.refreshAll(),
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(88),
                child: Column(
                  children: [
                    // Auth Banner & Rate Limits
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      color: scheme.surfaceContainerHigh,
                      child: Row(
                        children: [
                          Icon(
                            github.authToken != null
                                ? Icons.verified_user_rounded
                                : Icons.lock_outline_rounded,
                            size: 16,
                            color: github.authToken != null
                                ? Colors.green
                                : scheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              github.authToken != null
                                  ? 'Authenticated: @${github.authUsername} (${github.rateLimitRemaining}/${github.rateLimitTotal} req/hr)'
                                  : 'Anonymous: ${github.rateLimitRemaining}/${github.rateLimitTotal} req/hr',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          if (github.authToken == null)
                            TextButton(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ),
                              onPressed: () =>
                                  _showTokenLoginDialog(context, github),
                              child: const Text(
                                'Add Token (+5,000)',
                                style: TextStyle(fontSize: 12),
                              ),
                            )
                          else
                            IconButton(
                              tooltip: 'Sign Out Token',
                              icon: const Icon(Icons.logout_rounded, size: 16),
                              onPressed: () => github.logout(),
                            ),
                        ],
                      ),
                    ),
                    TabBar(
                      controller: _tabController,
                      indicatorColor: scheme.primary,
                      tabs: [
                        Tab(text: engine.dict.value('gh_tab_docs')),
                        Tab(text: engine.dict.value('gh_tab_issues')),
                        Tab(text: engine.dict.value('gh_tab_releases')),
                        Tab(text: engine.dict.value('gh_tab_security')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            body: github.isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    physics: const NeverScrollableScrollPhysics(), // Disables horizontal tab drag
                    children: [
                      // 1. Root Docs Tab (README, License, Security, Roadmap pills + markdown reader)
                      _buildDocsViewerTab(context, github),

                      // 2. Issues Tab (Search, Filter by status, Details bottom sheet)
                      _buildIssuesTab(context, github, engine),

                      // 3. Releases Tab (Versions, changelogs, assets download)
                      _buildReleasesTab(context, github, engine),

                      // 4. Security Tab (Dependabot, License, Open source cards)
                      _buildSecurityTab(context, github),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

/// Dedicated StatefulWidget sheet for Issue details.
/// Resolves comments future ONCE in initState() to prevent infinite refresh loops.
class _IssueDetailsSheet extends StatefulWidget {
  final GitHubIssue issue;

  const _IssueDetailsSheet({required this.issue});

  @override
  State<_IssueDetailsSheet> createState() => _IssueDetailsSheetState();
}

class _IssueDetailsSheetState extends State<_IssueDetailsSheet> {
  late Future<List<GitHubIssueComment>> _commentsFuture;

  @override
  void initState() {
    super.initState();
    _commentsFuture =
        GitHubService.instance.fetchIssueComments(widget.issue.number);
  }

  Widget _buildMarkdownImage(
    MarkdownImageConfig config,
    GitHubService github,
  ) {
    final uriStr = config.uri.toString();
    final String fullUrl;
    if (uriStr.startsWith('http://') || uriStr.startsWith('https://')) {
      fullUrl = uriStr;
    } else {
      final cleanPath = uriStr.startsWith('./')
          ? uriStr.substring(2)
          : (uriStr.startsWith('/') ? uriStr.substring(1) : uriStr);
      fullUrl =
          'https://raw.githubusercontent.com/${github.owner}/${github.repo}/HEAD/$cleanPath';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: () => _safeLaunchUrl(fullUrl),
        borderRadius: BorderRadius.circular(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            fullUrl,
            width: config.width,
            height: config.height,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                height: 120,
                alignment: Alignment.center,
                child: const CircularProgressIndicator(strokeWidth: 2),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.broken_image_rounded, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        config.alt != null && config.alt!.isNotEmpty
                            ? config.alt!
                            : 'Image ($uriStr)',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCommentCard(
    BuildContext context,
    GitHubIssueComment comment,
    GitHubService github,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundImage: comment.authorAvatarUrl.isNotEmpty
                      ? NetworkImage(comment.authorAvatarUrl)
                      : null,
                  child: comment.authorAvatarUrl.isEmpty
                      ? Text(
                          comment.author.isNotEmpty
                              ? comment.author[0].toUpperCase()
                              : '?',
                          style: const TextStyle(fontSize: 11),
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Text(
                  comment.author,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                if (comment.createdAt.isNotEmpty)
                  Text(
                    comment.createdAt.length >= 10
                        ? comment.createdAt.substring(0, 10)
                        : comment.createdAt,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            MarkdownBody(
              data: preprocessGitHubMarkdown(comment.body),
              selectable: true,
              onTapLink: (linkText, href, title) {
                if (href != null && href.isNotEmpty) {
                  _safeLaunchUrl(href);
                }
              },
              sizedImageBuilder: (config) =>
                  _buildMarkdownImage(config, github),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final github = GitHubService.instance;
    final engine = Provider.of<AIEngine>(context, listen: false);
    final issue = widget.issue;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (sheetCtx, scrollCtrl) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: MotionBlurContainer(
          child: ListView(
            controller: scrollCtrl,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: issue.state == 'open'
                          ? Colors.green.shade700
                          : Colors.purple.shade700,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      issue.state.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '#${issue.number}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: engine.dict.value('gh_open_github'),
                    icon: const Icon(Icons.open_in_new_rounded),
                    onPressed: () => _safeLaunchUrl(issue.htmlUrl),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                issue.title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Opened by ${issue.author} вЂў ${issue.commentsCount} comments',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              if (issue.labels.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: issue.labels.map((l) {
                    final color = Color(
                      int.tryParse('FF${l.colorHex}', radix: 16) ?? 0xFF808080,
                    );
                    return Chip(
                      label: Text(
                        l.name,
                        style:
                            const TextStyle(fontSize: 11, color: Colors.white),
                      ),
                      backgroundColor: color,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    );
                  }).toList(),
                ),
              ],
              const Divider(height: 24),

              // Rich Markdown issue body with HTML preprocessed & screenshots rendered
              MarkdownBody(
                data: preprocessGitHubMarkdown(issue.body),
                selectable: true,
                onTapLink: (linkText, href, title) {
                  if (href != null && href.isNotEmpty) {
                    _safeLaunchUrl(href);
                  }
                },
                sizedImageBuilder: (config) =>
                    _buildMarkdownImage(config, github),
              ),

              // Cached Comments Thread
              if (issue.commentsCount > 0) ...[
                const Divider(height: 32),
                Row(
                  children: [
                    const Icon(Icons.forum_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Comments (${issue.commentsCount})',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FutureBuilder<List<GitHubIssueComment>>(
                  future: _commentsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    final comments = snapshot.data ?? [];
                    if (comments.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No comments available.',
                          style: TextStyle(fontSize: 12),
                        ),
                      );
                    }
                    return Column(
                      children: comments
                          .map((c) => _buildCommentCard(context, c, github))
                          .toList(),
                    );
                  },
                ),
              ],

              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.forum_rounded),
                label: Text(engine.dict.value('gh_open_github')),
                onPressed: () => _safeLaunchUrl(issue.htmlUrl),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
