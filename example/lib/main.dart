import 'package:flutter/material.dart';
import 'package:lyrics_now/lyrics_now.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lyrics Search',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const SearchPage(),
    );
  }
}

class _ProviderResult {
  final LyricsProvider provider;
  final List<SongInfo>? songs;
  final String? error;
  final bool loading;

  const _ProviderResult({
    required this.provider,
    this.songs,
    this.error,
    this.loading = false,
  });
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();

  final _http = PackageHttpClient();
  late final List<LyricsProvider> _allProviders;
  List<_ProviderResult> _results = [];
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _allProviders = [
      QmProvider(_http),
      KgProvider(_http),
      NeProvider(_http),
      LrclibProvider(_http),
    ];
    _results = _allProviders
        .map((p) => _ProviderResult(provider: p))
        .toList(growable: false);
  }

  @override
  void dispose() {
    _controller.dispose();
    _http.close();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;

    setState(() {
      _searched = true;
      _results = _allProviders
          .map((p) => _ProviderResult(provider: p, loading: true))
          .toList(growable: false);
    });

    final query = SearchQuery(keyword: keyword, searchType: SearchType.song);
    final futures = <Future<void>>[];
    for (var i = 0; i < _allProviders.length; i++) {
      futures.add(_searchOne(i, query));
    }
    await Future.wait(futures);
  }

  Future<void> _searchOne(int index, SearchQuery query) async {
    final provider = _allProviders[index];
    try {
      final apiResult = await provider.search(query);
      setState(() {
        _results[index] = _ProviderResult(
          provider: provider,
          songs: apiResult.toList(),
        );
      });
    } catch (e) {
      setState(() {
        _results[index] = _ProviderResult(
          provider: provider,
          error: e.toString(),
        );
      });
    }
  }

  Color _sourceColor(Source source) {
    return switch (source) {
      Source.qm => Colors.green,
      Source.kg => Colors.orange,
      Source.ne => Colors.red,
      Source.lrclib => Colors.purple,
      _ => Colors.grey,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lyrics Search Test'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Search song or artist...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _controller.clear();
                                setState(() => _results = _allProviders
                                    .map((p) => _ProviderResult(provider: p))
                                    .toList(growable: false));
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _search, child: const Text('Search')),
              ],
            ),
          ),
          if (!_searched)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.music_note,
                        size: 80,
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withAlpha(60)),
                    const SizedBox(height: 16),
                    Text(
                      'Enter a song or artist to search',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final r = _results[index];
                  return _buildProviderSection(r);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProviderSection(_ProviderResult r) {
    final color = _sourceColor(r.provider.source);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: color.withAlpha(40),
                  child: Text(r.provider.source.label[0],
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: color)),
                ),
                const SizedBox(width: 8),
                Text(r.provider.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                if (r.loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (r.error != null)
                  Icon(Icons.error_outline, size: 16, color: Theme.of(context).colorScheme.error)
                else if (r.songs != null)
                  Text('${r.songs!.length} results',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (r.loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (r.error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(r.error!,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.error)),
            )
          else if (r.songs != null && r.songs!.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No results', style: TextStyle(color: Colors.grey)),
            )
          else if (r.songs != null)
            ...r.songs!.map(
              (song) => ListTile(
                dense: true,
                title: Text(song.fullTitle.isNotEmpty ? song.fullTitle : '(unknown)',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [
                    if (song.artistString.isNotEmpty) song.artistString,
                    if (song.formatDuration.isNotEmpty) song.formatDuration,
                    if (song.album != null) song.album!,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(song.source.label,
                    style: TextStyle(fontSize: 12, color: color)),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LyricPage(http: _http, providers: _allProviders, song: song),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

}

class LyricPage extends StatefulWidget {
  const LyricPage({super.key, required this.http, required this.providers, required this.song});

  final LyricsHttpClient http;
  final List<LyricsProvider> providers;
  final SongInfo song;

  @override
  State<LyricPage> createState() => _LyricPageState();
}

class _LyricPageState extends State<LyricPage> {
  late final LyricFinder _finder;
  Lyrics? _lyrics;
  bool _loading = true;
  String? _error;
  bool _showTimestamps = false;

  @override
  void initState() {
    super.initState();
    _finder = LyricFinder(
      http: widget.http,
      providers: widget.providers,
      matcher: const SongMatcher(),
      searchCacheTtl: const Duration(minutes: 5),
    );
    _fetch();
  }

  @override
  void dispose() {
    _finder.close();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final lyrics = await _finder.fetchLyrics(song: widget.song);
      setState(() {
        _lyrics = lyrics;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _formatMs(int ms) {
    final m = (ms ~/ 60000).toString().padLeft(2, '0');
    final s = ((ms ~/ 1000) % 60).toString().padLeft(2, '0');
    final ml = ((ms % 1000) ~/ 10).toString().padLeft(2, '0');
    return '$m:$s.$ml';
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    return Scaffold(
      appBar: AppBar(
        title: Text(song.fullTitle.isNotEmpty ? song.fullTitle : 'Lyrics'),
        actions: [
          if (_lyrics != null)
            IconButton(
              icon: Icon(_showTimestamps ? Icons.text_fields : Icons.access_time),
              tooltip: _showTimestamps ? 'Plain text' : 'Show timestamps',
              onPressed: () => setState(() => _showTimestamps = !_showTimestamps),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _fetch();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_lyrics == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lyrics_outlined,
                size: 64,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withAlpha(80)),
            const SizedBox(height: 16),
            const Text('No lyrics found'),
          ],
        ),
      );
    }

    final songInfo = widget.song;
    final origTrack = _lyrics![TrackNames.orig];
    final tsTrack = _lyrics![TrackNames.ts];
    final romaTrack = _lyrics![TrackNames.roma];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Theme.of(context)
              .colorScheme
              .primaryContainer
              .withAlpha(80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (songInfo.title != null)
                Text(songInfo.title!,
                    style: Theme.of(context).textTheme.titleMedium),
              if (songInfo.artistString.isNotEmpty)
                Text(songInfo.artistString,
                    style: Theme.of(context).textTheme.bodyMedium),
              if (songInfo.album != null)
                Text(songInfo.album!,
                    style: Theme.of(context).textTheme.bodySmall),
              if (songInfo.formatDuration.isNotEmpty)
                Text(songInfo.formatDuration,
                    style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Chip(
                label: Text(
                  _lyrics!.source.label,
                  style: const TextStyle(fontSize: 12),
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        if (_lyrics!.isInstrumental)
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.music_off, size: 64),
                  SizedBox(height: 16),
                  Text('Instrumental'),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (origTrack != null) ...[
                  _buildTrackHeader('Original', _lyrics!.types[TrackNames.orig]),
                  ...origTrack.map((line) => _buildLine(line)),
                ],
                if (tsTrack != null) ...[
                  const Divider(height: 32),
                  _buildTrackHeader('Translation', _lyrics!.types[TrackNames.ts]),
                  ...tsTrack.map((line) => _buildLine(line)),
                ],
                if (romaTrack != null) ...[
                  const Divider(height: 32),
                  _buildTrackHeader('Romanization', _lyrics!.types[TrackNames.roma]),
                  ...romaTrack.map((line) => _buildLine(line)),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTrackHeader(String label, LyricsType? type) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(width: 8),
          if (type != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .secondaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                type.name,
                style: const TextStyle(fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLine(LyricsLine line) {
    final text = line.text;
    if (text.trim().isEmpty) return const SizedBox(height: 4);

    if (_showTimestamps && line.start != null) {
      final startStr = _formatMs(line.start!);
      final endStr = line.end != null ? _formatMs(line.end!) : null;
      final ts = endStr != null ? '[$startStr → $endStr]' : '[$startStr]';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ts,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withAlpha(120),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(text, style: const TextStyle(fontSize: 15, height: 1.5)),
    );
  }
}
