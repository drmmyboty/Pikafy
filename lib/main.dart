import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const youtubeApiKey = String.fromEnvironment('YOUTUBE_API_KEY');

class PikafyTheme {
  static final ValueNotifier<double> hue = ValueNotifier<double>(258);
  static final ValueNotifier<bool> glass = ValueNotifier<bool>(true);
  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    hue.value = p.getDouble('theme_hue') ?? 258;
    glass.value = p.getBool('theme_glass') ?? true;
  }
  static Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble('theme_hue', hue.value);
    await p.setBool('theme_glass', glass.value);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PikafyTheme.load();
  if (supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  }
  runApp(const PikafyApp());
}

class PikafyApp extends StatelessWidget {
  const PikafyApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: PikafyTheme.hue,
    builder: (context, hue, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pikafy',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090B12),
        colorScheme: ColorScheme.fromSeed(seedColor: HSVColor.fromAHSV(1, hue, .58, 1).toColor(), brightness: Brightness.dark),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: const Color(0xFF171A27),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        ),
      ),
      home: supabaseUrl.isEmpty || supabaseKey.isEmpty ? const SetupScreen() : const AuthGate(),
    ),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: Supabase.instance.client.auth.onAuthStateChange,
    builder: (context, snapshot) => Supabase.instance.client.auth.currentSession == null
      ? const LoginScreen() : const HomeScreen(),
  );
}

class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: Padding(
      padding: EdgeInsets.all(28),
      child: Text('Pikafy\n\nSupabase connection is not configured. Add SUPABASE_URL and SUPABASE_ANON_KEY in GitHub Actions secrets.',
        textAlign: TextAlign.center, style: TextStyle(fontSize: 18, height: 1.6)),
    )),
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool creating = false, busy = false;
  String message = '';
  Future<void> submit() async {
    final address = email.text.trim();
    final secret = password.text;
    if (address.isEmpty || secret.isEmpty) {
      setState(() => message = 'Enter your email and password.');
      return;
    }
    setState(() { busy = true; message = ''; });
    try {
      final auth = Supabase.instance.client.auth;
      Object? lastError;
      // Retry brief DNS/network interruptions. This cannot bypass a device
      // whose DNS resolver is persistently unable to find the Supabase host.
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          if (creating) {
            await auth.signUp(email: address, password: secret);
            message = 'Account request sent. Check your email if confirmation is enabled.';
          } else {
            await auth.signInWithPassword(email: address, password: secret);
          }
          lastError = null;
          break;
        } on AuthException {
          rethrow;
        } catch (e) {
          lastError = e;
          final text = e.toString().toLowerCase();
          final isLookupFailure = text.contains('failed host lookup') ||
              text.contains('socketexception') ||
              text.contains('connection failed');
          if (!isLookupFailure || attempt == 2) rethrow;
          await Future.delayed(Duration(milliseconds: 700 * (attempt + 1)));
        }
      }
      if (lastError != null) throw lastError;
    } on AuthException catch (e) {
      message = e.message;
    } catch (e) {
      final details = e.toString().toLowerCase();
      if (details.contains('failed host lookup') || details.contains('socketexception')) {
        message = 'Pikafy cannot reach Supabase because this device could not resolve its server address. Check your internet connection or Android Private DNS, then try again. No account was created by this failed connection.';
      } else {
        message = 'Connection failed. Please check your internet and try again.';
      }
    }
    if (mounted) setState(() => busy = false);
  }
  @override
  void dispose() { email.dispose(); password.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(26),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.graphic_eq_rounded, size: 58, color: Color(0xFFB7A5FF)),
          const SizedBox(height: 14),
          const Text('pikafy', textAlign: TextAlign.center, style: TextStyle(fontSize: 42, fontWeight: FontWeight.w800, letterSpacing: -2)),
          const SizedBox(height: 8),
          Text(creating ? 'Create your account' : 'Your music, your space.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 38),
          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
          const SizedBox(height: 14),
          TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
          const SizedBox(height: 20),
          FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Please wait...' : creating ? 'Create account' : 'Log in')),
          TextButton(onPressed: busy ? null : () => setState(() => creating = !creating), child: Text(creating ? 'Already have an account? Log in' : 'New to Pikafy? Create account')),
          if (message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(message, textAlign: TextAlign.center)),
        ],
      )),
    ))),
  );
}

enum MusicKind { songs, artists, albums }

class MusicItem {
  final String id, title, subtitle, image;
  final MusicKind kind;
  const MusicItem({required this.id, required this.title, required this.subtitle, required this.image, required this.kind});
}

class YouTubeMusicSearch {
  static Future<List<MusicItem>> search(String query, MusicKind kind) async {
    if (youtubeApiKey.isEmpty) throw Exception('YouTube API key is not configured in GitHub Actions.');
    final type = kind == MusicKind.songs ? 'video' : kind == MusicKind.artists ? 'channel' : 'playlist';
    final uri = Uri.https('www.googleapis.com', '/youtube/v3/search', {
      'part': 'snippet', 'q': query, 'type': type, 'maxResults': '20', 'key': youtubeApiKey,
    });
    final response = await http.get(uri);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      final error = data['error']?['message'] ?? 'YouTube search failed.';
      throw Exception(error);
    }
    final items = (data['items'] as List? ?? []);
    return items.map((raw) {
      final item = raw as Map<String, dynamic>;
      final snippet = item['snippet'] as Map<String, dynamic>;
      final ids = item['id'] as Map<String, dynamic>;
      final id = kind == MusicKind.songs ? ids['videoId'] : kind == MusicKind.artists ? ids['channelId'] : ids['playlistId'];
      final thumbs = snippet['thumbnails'] as Map<String, dynamic>? ?? {};
      final thumb = (thumbs['high'] ?? thumbs['medium'] ?? thumbs['default'] ?? {}) as Map<String, dynamic>;
      return MusicItem(
        id: (id ?? '').toString(),
        title: (snippet['title'] ?? 'Unknown').toString(),
        subtitle: (snippet['channelTitle'] ?? '').toString(),
        image: (thumb['url'] ?? '').toString(),
        kind: kind,
      );
    }).where((item) => item.id.isNotEmpty).toList();
  }
}

class LyricsService {
  static Future<String> getLyrics(String title, String artist) async {
    final uri = Uri.https('lrclib.net', '/api/get', {'track_name': title, 'artist_name': artist});
    final response = await http.get(uri, headers: {'User-Agent': 'Pikafy/0.1.0'});
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final synced = (data['syncedLyrics'] ?? '').toString();
      final plain = (data['plainLyrics'] ?? '').toString();
      return synced.isNotEmpty ? synced : plain;
    }
    final searchUri = Uri.https('lrclib.net', '/api/search', {'track_name': title, 'artist_name': artist});
    final fallback = await http.get(searchUri, headers: {'User-Agent': 'Pikafy/0.1.0'});
    if (fallback.statusCode == 200) {
      final results = jsonDecode(fallback.body) as List;
      if (results.isNotEmpty) {
        final first = results.first as Map<String, dynamic>;
        return (first['syncedLyrics'] ?? first['plainLyrics'] ?? '').toString();
      }
    }
    return '';
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  final searchController = TextEditingController();
  MusicKind kind = MusicKind.songs;
  List<MusicItem> results = [];
  bool loading = false;
  String error = '';
  Future<void> search() async {
    final query = searchController.text.trim();
    if (query.isEmpty) return;
    setState(() { loading = true; error = ''; results = []; });
    try {
      final found = await YouTubeMusicSearch.search(query, kind);
      if (mounted) setState(() => results = found);
    } catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
    if (mounted) setState(() => loading = false);
  }
  @override
  void dispose() { searchController.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('pikafy', style: TextStyle(fontWeight: FontWeight.w800)),
      actions: [
        IconButton(tooltip: 'Theme studio', icon: const Icon(Icons.palette_outlined),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ThemeMakerScreen()))),
        IconButton(tooltip: 'Log out', onPressed: () => Supabase.instance.client.auth.signOut(), icon: const Icon(Icons.logout_rounded)),
      ],
    ),
    body: SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: TextField(
        controller: searchController, textInputAction: TextInputAction.search, onSubmitted: (_) => search(),
        decoration: InputDecoration(hintText: 'Search songs, artists or albums', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: search)),
      )),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
        _tab('Songs', MusicKind.songs), _tab('Artists', MusicKind.artists), _tab('Albums', MusicKind.albums),
      ])),
      if (kind == MusicKind.albums)
        const Padding(padding: EdgeInsets.fromLTRB(16, 6, 16, 4), child: Text('Album results are YouTube playlists and may include unofficial collections.', style: TextStyle(color: Colors.white54, fontSize: 11))),
      if (youtubeApiKey.isEmpty)
        const Padding(padding: EdgeInsets.all(16), child: Text('Add the YOUTUBE_API_KEY GitHub Actions secret to enable search.', style: TextStyle(color: Colors.orangeAccent))),
      if (loading) const LinearProgressIndicator(),
      if (error.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(error, style: const TextStyle(color: Colors.orangeAccent))),
      Expanded(child: results.isEmpty && !loading
        ? const Center(child: Text('Search for music to get started.', style: TextStyle(color: Colors.white54)))
        : ListView.builder(itemCount: results.length, itemBuilder: (context, index) {
            final item = results[index];
            final tile = ListTile(
              leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: item.image.isEmpty
                ? const SizedBox(width: 52, height: 52, child: Icon(Icons.music_note))
                : Image.network(item.image, width: 52, height: 52, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 52, height: 52, child: Icon(Icons.music_note)))),
              title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(icon: const Icon(Icons.lyrics_outlined), tooltip: 'Find lyrics', onPressed: () => _showLyrics(item)),
            );
            return ValueListenableBuilder<bool>(
              valueListenable: PikafyTheme.glass,
              builder: (context, enabled, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ClipRRect(borderRadius: BorderRadius.circular(18),
                  child: enabled
                    ? BackdropFilter(filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                        child: Container(color: Colors.white.withValues(alpha: .055), child: tile))
                    : Card(margin: EdgeInsets.zero, child: tile)),
              ),
            );
          })),
      const Padding(padding: EdgeInsets.all(10), child: Text('Metadata and lyrics only. YouTube Data API does not provide audio playback.', style: TextStyle(color: Colors.white38, fontSize: 11), textAlign: TextAlign.center)),
    ])),
  );
  Widget _tab(String label, MusicKind value) => Expanded(child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: ChoiceChip(label: SizedBox(width: double.infinity, child: Text(label, textAlign: TextAlign.center)), selected: kind == value,
      onSelected: (_) => setState(() { kind = value; results = []; error = ''; })),
  ));
  Future<void> _showLyrics(MusicItem item) async {
    if (item.kind != MusicKind.songs) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lyrics are available for song results only.')));
      return;
    }
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    String lyrics = '';
    try { lyrics = await LyricsService.getLyrics(item.title, item.subtitle); } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pop();
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: const Color(0xFF171A27), builder: (context) => SafeArea(
      child: Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 32), child: SizedBox(
        height: MediaQuery.of(context).size.height * .72,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(item.subtitle, style: const TextStyle(color: Colors.white60)),
          const Divider(height: 24),
          Expanded(child: SingleChildScrollView(child: SelectableText(lyrics.isEmpty ? 'Lyrics not found for this track.' : lyrics, style: const TextStyle(height: 1.6)))),
        ]),
      )),
    ));
  }
}

class ThemeMakerScreen extends StatefulWidget {
  const ThemeMakerScreen({super.key});
  @override
  State<ThemeMakerScreen> createState() => _ThemeMakerScreenState();
}
class _ThemeMakerScreenState extends State<ThemeMakerScreen> {
  late double hue;
  late bool glass;
  @override
  void initState() {
    super.initState();
    hue = PikafyTheme.hue.value;
    glass = PikafyTheme.glass.value;
  }
  Color get accent => HSVColor.fromAHSV(1, hue, .58, 1).toColor();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Theme studio')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('MAKE PIKAFY YOURS', style: TextStyle(letterSpacing: 2, color: Colors.white60, fontSize: 12)),
      const SizedBox(height: 16),
      ClipRRect(borderRadius: BorderRadius.circular(28), child: Stack(children: [
        Container(height: 180, decoration: BoxDecoration(gradient: LinearGradient(
          colors: [const Color(0xFF101522), accent.withValues(alpha: .55), const Color(0xFF101522)]))),
        if (glass) Positioned.fill(child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(color: Colors.white.withValues(alpha: .06)))),
        Positioned.fill(child: Padding(padding: const EdgeInsets.all(20), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.graphic_eq, size: 34), const Spacer(),
            const Text('Your theme preview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(height: 8, width: 150, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(20))),
            const SizedBox(height: 8),
            const Text('Liquid glass • Custom accent', style: TextStyle(color: Colors.white70)),
          ]))),
      ])),
      const SizedBox(height: 28),
      const Text('Accent colour', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      Slider(value: hue, min: 0, max: 360, divisions: 360, activeColor: accent,
        onChanged: (v) => setState(() => hue = v)),
      Wrap(spacing: 10, children: [258.0, 195.0, 330.0, 25.0, 110.0, 45.0].map((v) =>
        GestureDetector(onTap: () => setState(() => hue = v),
          child: CircleAvatar(radius: 17, backgroundColor: HSVColor.fromAHSV(1, v, .58, 1).toColor(),
            child: (hue - v).abs() < 1 ? const Icon(Icons.check, size: 18, color: Colors.white) : null))
      ).toList()),
      const SizedBox(height: 24),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Liquid glass effect'),
        subtitle: const Text('Frosted translucent panels with blur'), value: glass,
        onChanged: (v) => setState(() => glass = v)),
      const SizedBox(height: 18),
      FilledButton.icon(icon: const Icon(Icons.check), label: const Text('Save my theme'),
        onPressed: () async {
          PikafyTheme.hue.value = hue;
          PikafyTheme.glass.value = glass;
          await PikafyTheme.save();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Theme saved on this device.')));
            Navigator.pop(context);
          }
        }),
      const SizedBox(height: 10),
      const Text('Saved on this device for now. Cloud theme sync can be added later.',
        style: TextStyle(color: Colors.white54, fontSize: 12)),
    ]),
  );
}
