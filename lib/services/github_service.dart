import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:m3x/m3x.dart' show M3x;

/// Data model representing a documentation file in the repository root.
class GitHubRepoDoc {
  final String name;
  final String path;
  final String downloadUrl;
  final String title;
  final IconData icon;
  String? content;

  GitHubRepoDoc({
    required this.name,
    required this.path,
    required this.downloadUrl,
    required this.title,
    required this.icon,
    this.content,
  });

  factory GitHubRepoDoc.fromContentJson(Map<String, dynamic> json, String owner, String repo) {
    final name = json['name'] as String? ?? '';
    final path = json['path'] as String? ?? name;
    final downloadUrl = json['download_url'] as String? ??
        'https://raw.githubusercontent.com/$owner/$repo/HEAD/$path';

    final lower = name.toLowerCase();
    String title = name;
    IconData icon = Icons.description_outlined;

    if (lower == 'readme.md' || lower == 'readme') {
      title = 'README';
      icon = Icons.menu_book_rounded;
    } else if (lower.startsWith('license') || lower.startsWith('licence')) {
      title = 'License';
      icon = Icons.gavel_rounded;
    } else if (lower.contains('code_of_conduct') || lower.contains('conduct')) {
      title = 'Code of Conduct';
      icon = Icons.handshake_outlined;
    } else if (lower.contains('contributing')) {
      title = 'Contributing';
      icon = Icons.groups_rounded;
    } else if (lower.contains('security')) {
      title = 'Security';
      icon = Icons.shield_outlined;
    } else if (lower.contains('roadmap')) {
      title = 'Roadmap';
      icon = Icons.alt_route_rounded;
    } else if (lower.contains('changelog')) {
      title = 'Changelog';
      icon = Icons.history_rounded;
    } else if (lower.contains('privacy')) {
      title = 'Privacy';
      icon = Icons.privacy_tip_outlined;
    } else if (lower.endsWith('.md')) {
      title = name.substring(0, name.length - 3);
      if (title.isNotEmpty) {
        title = title[0].toUpperCase() + title.substring(1).replaceAll('_', ' ').replaceAll('-', ' ');
      }
    }

    return GitHubRepoDoc(
      name: name,
      path: path,
      downloadUrl: downloadUrl,
      title: title,
      icon: icon,
    );
  }
}

/// Data model representing a GitHub Issue Comment.
class GitHubIssueComment {
  final int id;
  final String author;
  final String authorAvatarUrl;
  final String createdAt;
  final String body;

  const GitHubIssueComment({
    required this.id,
    required this.author,
    required this.authorAvatarUrl,
    required this.createdAt,
    required this.body,
  });

  factory GitHubIssueComment.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? {};
    return GitHubIssueComment(
      id: json['id'] as int? ?? 0,
      author: user['login'] as String? ?? 'ghost',
      authorAvatarUrl: user['avatar_url'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      body: json['body'] as String? ?? '',
    );
  }
}

/// Data model representing a GitHub Issue.
class GitHubIssue {
  final int number;
  final String title;
  final String state;
  final String author;
  final String authorAvatarUrl;
  final String createdAt;
  final int commentsCount;
  final String body;
  final String htmlUrl;
  final List<({String name, String colorHex})> labels;

  const GitHubIssue({
    required this.number,
    required this.title,
    required this.state,
    required this.author,
    required this.authorAvatarUrl,
    required this.createdAt,
    required this.commentsCount,
    required this.body,
    required this.htmlUrl,
    required this.labels,
  });

  factory GitHubIssue.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? {};
    final rawLabels = json['labels'] as List<dynamic>? ?? [];
    final labels = rawLabels.map((l) {
      final map = l as Map<String, dynamic>;
      return (
        name: map['name']?.toString() ?? '',
        colorHex: map['color']?.toString() ?? '808080',
      );
    }).toList();

    return GitHubIssue(
      number: json['number'] as int? ?? 0,
      title: json['title'] as String? ?? 'Untitled',
      state: json['state'] as String? ?? 'open',
      author: user['login'] as String? ?? 'ghost',
      authorAvatarUrl: user['avatar_url'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      commentsCount: json['comments'] as int? ?? 0,
      body: json['body'] as String? ?? 'No description provided.',
      htmlUrl: json['html_url'] as String? ?? '',
      labels: labels,
    );
  }
}

/// Data model representing a GitHub Release.
class GitHubRelease {
  final String name;
  final String tagName;
  final String publishedAt;
  final String body;
  final String htmlUrl;
  final List<({String name, int sizeBytes, String downloadUrl, int downloadCount})> assets;

  const GitHubRelease({
    required this.name,
    required this.tagName,
    required this.publishedAt,
    required this.body,
    required this.htmlUrl,
    required this.assets,
  });

  factory GitHubRelease.fromJson(Map<String, dynamic> json) {
    final rawAssets = json['assets'] as List<dynamic>? ?? [];
    final assets = rawAssets.map((a) {
      final map = a as Map<String, dynamic>;
      return (
        name: map['name']?.toString() ?? '',
        sizeBytes: map['size'] as int? ?? 0,
        downloadUrl: map['browser_download_url']?.toString() ?? '',
        downloadCount: map['download_count'] as int? ?? 0,
      );
    }).toList();

    return GitHubRelease(
      name: json['name'] as String? ?? json['tag_name'] as String? ?? 'Release',
      tagName: json['tag_name'] as String? ?? '',
      publishedAt: json['published_at'] as String? ?? '',
      body: json['body'] as String? ?? 'No release notes provided.',
      htmlUrl: json['html_url'] as String? ?? '',
      assets: assets,
    );
  }
}

/// Service providing GitHub repository exploration (Docs, Issues, Releases, Security)
/// with root document tab detection, issue comments caching, and PAT authentication.
class GitHubService extends ChangeNotifier {
  static final GitHubService instance = GitHubService._();
  GitHubService._();

  String _owner = 'Puzzaks';
  String _repo = 'PAIOS';
  String? _authToken;
  String? _authUsername;
  String? _authAvatarUrl;
  int _rateLimitRemaining = 60;
  int _rateLimitTotal = 60;
  bool _isLoading = false;
  String? _errorMessage;

  String? _readmeContent;
  String? _licenseContent;
  String? _licenseName;
  List<GitHubIssue> _issues = [];
  List<GitHubRelease> _releases = [];

  // Root docs navigation and caching
  List<GitHubRepoDoc> _rootDocs = [];
  GitHubRepoDoc? _selectedDoc;
  final Map<String, String> _docContentCache = {};
  final Map<int, List<GitHubIssueComment>> _commentsCache = {};

  String get owner => _owner;
  String get repo => _repo;
  String? get authToken => _authToken;
  String? get authUsername => _authUsername;
  String? get authAvatarUrl => _authAvatarUrl;
  int get rateLimitRemaining => _rateLimitRemaining;
  int get rateLimitTotal => _rateLimitTotal;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  String? get readmeContent => _readmeContent;
  String? get licenseContent => _licenseContent;
  String? get licenseName => _licenseName;
  List<GitHubIssue> get issues => List.unmodifiable(_issues);
  List<GitHubRelease> get releases => List.unmodifiable(_releases);
  List<GitHubRepoDoc> get rootDocs => List.unmodifiable(_rootDocs);
  GitHubRepoDoc? get selectedDoc => _selectedDoc;

  static const List<({String owner, String repo, String title})> presetRepos = [
    (owner: 'Puzzaks', repo: 'PAIOS', title: 'PAIOS (AI Operating System)'),
    (owner: 'Puzzaks', repo: 'geminilocal', title: 'geminilocal (Legacy Local AI Client)'),
    (owner: 'Puzzaks', repo: 'PTK', title: 'PTK (Puzzak ToolKit)'),
    (owner: 'Puzzaks', repo: 'demo', title: 'demo (Single Source of Truth)'),
    (owner: 'Puzzaks', repo: 'MCPlayer', title: 'MCPlayer (Monstercat Player)'),
    (owner: 'Puzzaks', repo: 'Website', title: 'Website (MD3 Showcase)'),
    (owner: 'Puzzaks', repo: '.github', title: 'Puzzaks Organization Meta'),
  ];

  String get _userAgent {
    final ver = M3x.appVersion.isNotEmpty ? M3x.appVersion : '1.5.9';
    return 'PAIOS/$ver (Puzzak Ecosystem)';
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Accept': 'application/vnd.github.v3+json',
      'User-Agent': _userAgent,
    };
    if (_authToken != null && _authToken!.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${_authToken!.trim()}';
    }
    return headers;
  }

  void _updateRateLimits(http.Response response) {
    final remaining = response.headers['x-ratelimit-remaining'];
    final limit = response.headers['x-ratelimit-limit'];
    if (remaining != null) _rateLimitRemaining = int.tryParse(remaining) ?? _rateLimitRemaining;
    if (limit != null) _rateLimitTotal = int.tryParse(limit) ?? _rateLimitTotal;
  }

  /// Sets the active target repository and resets caches.
  void setTargetRepository(String owner, String repo) {
    if (_owner == owner && _repo == repo) return;
    _owner = owner;
    _repo = repo;
    _readmeContent = null;
    _licenseContent = null;
    _licenseName = null;
    _issues = [];
    _releases = [];
    _rootDocs = [];
    _selectedDoc = null;
    _docContentCache.clear();
    _commentsCache.clear();
    notifyListeners();
    refreshAll();
  }

  /// Authenticates using a GitHub Personal Access Token (PAT).
  Future<bool> authenticateWithToken(String token) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/user'),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': _userAgent,
          'Authorization': 'Bearer ${token.trim()}',
        },
      ).timeout(const Duration(seconds: 10));

      _updateRateLimits(res);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _authToken = token.trim();
        _authUsername = data['login'] as String?;
        _authAvatarUrl = data['avatar_url'] as String?;
        _errorMessage = null;
        _isLoading = false;
        notifyListeners();
        refreshAll();
        return true;
      } else {
        _errorMessage = 'GitHub Auth failed (${res.statusCode}): ${res.body}';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Network error during auth: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Logs out of authenticated GitHub session.
  void logout() {
    _authToken = null;
    _authUsername = null;
    _authAvatarUrl = null;
    _rateLimitRemaining = 60;
    _rateLimitTotal = 60;
    notifyListeners();
  }

  /// Refreshes Docs, Issues, Releases, and License in parallel.
  Future<void> refreshAll() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    await Future.wait([
      fetchRootDocs(),
      fetchReadme(),
      fetchIssues(),
      fetchReleases(),
      fetchLicense(),
    ]);

    _isLoading = false;
    notifyListeners();
  }

  /// Discovers all root markdown/documentation files in the repository.
  Future<void> fetchRootDocs() async {
    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/repos/$_owner/$_repo/contents'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      _updateRateLimits(res);

      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(res.body) as List<dynamic>;
        final docs = <GitHubRepoDoc>[];

        for (final item in list) {
          if (item is Map<String, dynamic> && item['type'] == 'file') {
            final name = (item['name'] as String? ?? '').toLowerCase();
            if (name.endsWith('.md') ||
                name == 'license' ||
                name == 'licence' ||
                name == 'notice') {
              docs.add(GitHubRepoDoc.fromContentJson(item, _owner, _repo));
            }
          }
        }

        // Sort so README is always first, License second, then others alphabetically
        docs.sort((a, b) {
          if (a.name.toLowerCase().startsWith('readme')) return -1;
          if (b.name.toLowerCase().startsWith('readme')) return 1;
          if (a.name.toLowerCase().startsWith('licen')) return -1;
          if (b.name.toLowerCase().startsWith('licen')) return 1;
          return a.title.compareTo(b.title);
        });

        _rootDocs = docs;
        if (_rootDocs.isNotEmpty && _selectedDoc == null) {
          _selectedDoc = _rootDocs.first;
        }
      }
    } catch (_) {
      // Fallback: keep existing or empty
    }
  }

  /// Selects active document tab and loads its content if not cached.
  Future<void> selectDoc(GitHubRepoDoc doc) async {
    _selectedDoc = doc;
    notifyListeners();

    if (doc.content == null && !_docContentCache.containsKey(doc.path)) {
      await fetchDocContent(doc);
    }
  }

  /// Selects a root document by filename or path.
  Future<bool> selectDocByPath(String path) async {
    final cleanPath = path.replaceAll('./', '').toLowerCase();
    final match = _rootDocs.firstWhere(
      (d) => d.path.toLowerCase() == cleanPath || d.name.toLowerCase() == cleanPath,
      orElse: () => GitHubRepoDoc(
        name: '',
        path: '',
        downloadUrl: '',
        title: '',
        icon: Icons.description_outlined,
      ),
    );

    if (match.path.isNotEmpty) {
      await selectDoc(match);
      return true;
    }
    return false;
  }

  /// Fetches content for a specific documentation file.
  Future<String> fetchDocContent(GitHubRepoDoc doc) async {
    if (_docContentCache.containsKey(doc.path)) {
      doc.content = _docContentCache[doc.path];
      notifyListeners();
      return doc.content!;
    }

    try {
      final res = await http.get(
        Uri.parse(doc.downloadUrl),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        doc.content = res.body;
        _docContentCache[doc.path] = res.body;
        notifyListeners();
        return res.body;
      }
    } catch (e) {
      doc.content = '_Error loading ${doc.name}: ${e}_';
      notifyListeners();
      return doc.content!;
    }

    return '_Unable to load content._';
  }

  /// Fetches arbitrary file content from repository (for nested folder navigation).
  Future<String> fetchArbitraryFileContent(String relativePath) async {
    final cleanPath = relativePath.startsWith('/') ? relativePath.substring(1) : relativePath;
    if (_docContentCache.containsKey(cleanPath)) {
      return _docContentCache[cleanPath]!;
    }

    try {
      final url = 'https://raw.githubusercontent.com/$_owner/$_repo/HEAD/$cleanPath';
      final res = await http.get(
        Uri.parse(url),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        _docContentCache[cleanPath] = res.body;
        return res.body;
      }
    } catch (e) {
      return '_Error loading $relativePath: ${e}_';
    }

    return '_File not found: ${relativePath}_';
  }

  /// Fetches repository README markdown content.
  Future<void> fetchReadme() async {
    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/repos/$_owner/$_repo/readme'),
        headers: {
          ..._headers,
          'Accept': 'application/vnd.github.raw+json',
        },
      ).timeout(const Duration(seconds: 10));

      _updateRateLimits(res);

      if (res.statusCode == 200) {
        _readmeContent = res.body;
        _docContentCache['README.md'] = res.body;
        for (final doc in _rootDocs) {
          if (doc.name.toLowerCase().startsWith('readme')) {
            doc.content = res.body;
          }
        }
      } else {
        _readmeContent = '_No README found or inaccessible for this repository._';
      }
    } catch (e) {
      _readmeContent = '_Error fetching README: ${e}_';
    }
    notifyListeners();
  }

  /// Fetches open and closed issues.
  Future<void> fetchIssues() async {
    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/repos/$_owner/$_repo/issues?state=all&per_page=30'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      _updateRateLimits(res);

      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(res.body) as List<dynamic>;
        _issues = list
            .where((item) => (item as Map<String, dynamic>)['pull_request'] == null)
            .map((item) => GitHubIssue.fromJson(item as Map<String, dynamic>))
            .toList();
      } else {
        _errorMessage = 'Failed to load issues: HTTP ${res.statusCode}';
      }
    } catch (e) {
      _errorMessage = 'Error loading issues: $e';
    }
    notifyListeners();
  }

  /// Fetches releases and tags.
  Future<void> fetchReleases() async {
    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/repos/$_owner/$_repo/releases?per_page=20'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      _updateRateLimits(res);

      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(res.body) as List<dynamic>;
        _releases = list
            .map((item) => GitHubRelease.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      // Releases might be empty for repos that only use tags
    }
    notifyListeners();
  }

  /// Fetches repository LICENSE content.
  Future<void> fetchLicense() async {
    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/repos/$_owner/$_repo/license'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      _updateRateLimits(res);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final licenseObj = data['license'] as Map<String, dynamic>?;
        _licenseName = licenseObj?['name'] as String? ?? 'Open Source License';
        final content = data['content'] as String?;
        final encoding = data['encoding'] as String?;
        if (content != null && encoding == 'base64') {
          final cleanBase64 = content.replaceAll('\n', '').replaceAll('\r', '');
          _licenseContent = utf8.decode(base64Decode(cleanBase64));
        } else {
          _licenseContent = data['body'] as String? ?? 'License available at ${data['html_url']}';
        }
      } else {
        final rawRes = await http.get(
          Uri.parse('https://raw.githubusercontent.com/$_owner/$_repo/HEAD/LICENSE'),
        ).timeout(const Duration(seconds: 10));

        if (rawRes.statusCode == 200) {
          _licenseName = 'Repository License';
          _licenseContent = rawRes.body;
        } else {
          _licenseName = 'No License Detected';
          _licenseContent = 'No formal LICENSE file was detected in the repository root.';
        }
      }
    } catch (e) {
      _licenseContent = 'Error fetching LICENSE: $e';
    }
    notifyListeners();
  }

  /// Fetches comments for a specific issue with caching to stop refresh loops.
  Future<List<GitHubIssueComment>> fetchIssueComments(int issueNumber) async {
    if (_commentsCache.containsKey(issueNumber)) {
      return _commentsCache[issueNumber]!;
    }

    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/repos/$_owner/$_repo/issues/$issueNumber/comments?per_page=50'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      _updateRateLimits(res);

      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(res.body) as List<dynamic>;
        final comments = list
            .map((item) => GitHubIssueComment.fromJson(item as Map<String, dynamic>))
            .toList();
        _commentsCache[issueNumber] = comments;
        return comments;
      }
    } catch (_) {
      // Fallback
    }
    return [];
  }
}
