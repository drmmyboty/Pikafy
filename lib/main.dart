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
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static double hue = 258, saturation = 0, brightness = 0;
  static bool glass = true, amoled = true, compact = false, reduceMotion = false;
  static Color get background => amoled ? const Color(0xFF000000) :
      HSVColor.fromAHSV(1, hue, saturation, brightness).toColor();
  static Color get accent => HSVColor.fromAHSV(1, hue, .68, 1).toColor();
  static void notify() => revision.value++;
  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    hue = p.getDouble('theme_hue') ?? 258;
    saturation = p.getDouble('theme_saturation') ?? 0;
    brightness = p.getDouble('theme_brightness') ?? 0;
    glass = p.getBool('theme_glass') ?? true;
    amoled = p.getBool('theme_amoled') ?? true;
    compact = p.getBool('theme_compact') ?? false;
    reduceMotion = p.getBool('theme_reduce_motion') ?? false;
  }
  static Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble('theme_hue', hue);
    await p.setDouble('theme_saturation', saturation);
    await p.setDouble('theme_brightness', brightness);
    await p.setBool('theme_glass', glass);
    await p.setBool('theme_amoled', amoled);
    await p.setBool('theme_compact', compact);
    await p.setBool('theme_reduce_motion', reduceMotion);
    notify();
  }
  static Future<void> reset() async {
    hue = 258; saturation = 0; brightness = 0;
    glass = true; amoled = true; compact = false; reduceMotion = false;
    await save();
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
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: PikafyTheme.revision,
    builder: (context, _, __) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pikafy',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: PikafyTheme.background,
        colorScheme: ColorScheme.fromSeed(seedColor: PikafyTheme.accent, brightness: Brightness.dark),
        useMaterial3: true,
        visualDensity: PikafyTheme.compact ? VisualDensity.compact : VisualDensity.standard,
        pageTransitionsTheme: PageTransitionsTheme(builders: {
          for (final platform in TargetPlatform.values)
            platform: PikafyTheme.reduceMotion ? const _NoMotionPageTransitionsBuilder() : const ZoomPageTransitionsBuilder(),
        }),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: const Color(0xFF171717),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        ),
      ),
      home: supabaseUrl.isEmpty || supabaseKey.isEmpty ? const SetupScreen() : const AuthGate(),
    ),
  );
}

class _NoMotionPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoMotionPageTransitionsBuilder();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context,
      Animation<double> animation, Animation<double> secondaryAnimation, Widget child) => child;
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
      backgroundColor: Colors.transparent,
      actions: [
        IconButton(tooltip: 'Theme studio', icon: const Icon(Icons.palette_outlined),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ThemeMakerScreen()))),
        IconButton(tooltip: 'Log out', onPressed: () => Supabase.instance.client.auth.signOut(), icon: const Icon(Icons.logout_rounded)),
      ],
    ),
    backgroundColor: PikafyTheme.background,
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
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: PikafyTheme.compact ? 1 : 4),
              child: ClipRRect(borderRadius: BorderRadius.circular(18),
                child: PikafyTheme.glass
                  ? BackdropFilter(filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Container(color: Colors.white.withValues(alpha: .055), child: tile))
                  : Card(margin: EdgeInsets.zero, child: tile)),
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
  late double hue, saturation, brightness;
  late bool glass, amoled, compact, reduceMotion;
  @override
  void initState() {
    super.initState();
    hue = PikafyTheme.hue; saturation = PikafyTheme.saturation;
    brightness = PikafyTheme.brightness; glass = PikafyTheme.glass;
    amoled = PikafyTheme.amoled; compact = PikafyTheme.compact;
    reduceMotion = PikafyTheme.reduceMotion;
  }
  Color get chosen => HSVColor.fromAHSV(1, hue, saturation, brightness).toColor();
  Color get accent => HSVColor.fromAHSV(1, hue, .68, 1).toColor();

  Widget section(String title, Widget child) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8), child,
    ]),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Personalise Pikafy')),
    body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      ClipRRect(borderRadius: BorderRadius.circular(26), child: Stack(children: [
        Container(height: 190, color: amoled ? Colors.black : chosen),
        if (glass) Positioned.fill(child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(color: Colors.white.withValues(alpha: .07)))),
        Positioned.fill(child: Padding(padding: const EdgeInsets.all(20), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(Icons.graphic_eq_rounded, color: accent, size: 32),
              const Spacer(), const Text('PIKAFY PREVIEW', style: TextStyle(letterSpacing: 2, fontSize: 10))]),
            const Spacer(),
            const Text('Made for your mood', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Row(children: [for (int i=0;i<5;i++) Container(
              margin: const EdgeInsets.only(right: 6), width: 28, height: 28,
              decoration: BoxDecoration(color: accent.withValues(alpha: 1-i*.13), borderRadius: BorderRadius.circular(8)))])
          ]))),
      ])),
      section('Home screen colour', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(amoled ? 'AMOLED black is active' : 'Custom colour', style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final c in [Colors.black, const Color(0xFF101522), const Color(0xFF17233B),
            const Color(0xFF241334), const Color(0xFF12352F), const Color(0xFF3A2020)])
            GestureDetector(onTap: () => setState(() {
              amoled = c == Colors.black;
              final hsv = HSVColor.fromColor(c); hue = hsv.hue; saturation = hsv.saturation; brightness = hsv.value;
            }), child: CircleAvatar(radius: 19, backgroundColor: c,
              child: (amoled && c == Colors.black) ? const Icon(Icons.check, color: Colors.white, size: 18) : null)),
        ]),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('AMOLED black'),
          subtitle: const Text('Pure black background for OLED screens'), value: amoled,
          onChanged: (v) => setState(() => amoled = v)),
        Opacity(opacity: amoled ? .45 : 1, child: IgnorePointer(ignoring: amoled, child: Column(children: [
          Row(children: [const Expanded(child: Text('Colour hue')), Text('${hue.round()}°')]),
          Slider(value: hue, min: 0, max: 360, divisions: 360, activeColor: accent,
            onChanged: (v) => setState(() { hue = v; amoled = false; })),
          const Text('Saturation', style: TextStyle(color: Colors.white70)),
          Slider(value: saturation, min: 0, max: 1, divisions: 100,
            onChanged: (v) => setState(() { saturation = v; amoled = false; })),
          const Text('Brightness', style: TextStyle(color: Colors.white70)),
          Slider(value: brightness, min: .05, max: 1, divisions: 95,
            onChanged: (v) => setState(() { brightness = v; amoled = false; })),
          Container(height: 42, decoration: BoxDecoration(color: chosen, borderRadius: BorderRadius.circular(12))),
        ]))),
      ])),
      section('Appearance', Column(children: [
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Liquid Glass'),
          subtitle: const Text('Blurred translucent panels'), value: glass,
          onChanged: (v) => setState(() => glass = v)),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Compact layout'),
          subtitle: const Text('Fit more music on screen'), value: compact,
          onChanged: (v) => setState(() => compact = v)),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Reduce animations'),
          subtitle: const Text('Simpler transitions and less motion'), value: reduceMotion,
          onChanged: (v) => setState(() => reduceMotion = v)),
      ])),
      section('Quick themes', Wrap(spacing: 10, runSpacing: 10, children: [
        for (final item in [
          ('AMOLED', Colors.black), ('Midnight', const Color(0xFF101522)),
          ('Ocean', const Color(0xFF123B52)), ('Dream', const Color(0xFF302044)),
          ('Forest', const Color(0xFF173A2B)), ('Rose', const Color(0xFF482532)),
        ])
          ActionChip(avatar: CircleAvatar(backgroundColor: item.$2, radius: 9),
            label: Text(item.$1), onPressed: () => setState(() {
              final hsv = HSVColor.fromColor(item.$2); hue = hsv.hue;
              saturation = hsv.saturation; brightness = hsv.value;
              amoled = item.$1 == 'AMOLED';
            })),
      ])),
      const SizedBox(height: 26),
      FilledButton.icon(icon: const Icon(Icons.check_rounded), label: const Text('Save customisation'),
        onPressed: () async {
          PikafyTheme.hue = hue; PikafyTheme.saturation = saturation;
          PikafyTheme.brightness = brightness; PikafyTheme.glass = glass;
          PikafyTheme.amoled = amoled; PikafyTheme.compact = compact;
          PikafyTheme.reduceMotion = reduceMotion;
          await PikafyTheme.save();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your Pikafy style has been saved.')));
            Navigator.pop(context);
          }
        }),
      TextButton.icon(icon: const Icon(Icons.restart_alt), label: const Text('Reset to default (AMOLED black)'),
        onPressed: () async {
          await PikafyTheme.reset();
          if (mounted) setState(() {
            hue = PikafyTheme.hue; saturation = PikafyTheme.saturation;
            brightness = PikafyTheme.brightness; glass = PikafyTheme.glass;
            amoled = PikafyTheme.amoled; compact = PikafyTheme.compact;
            reduceMotion = PikafyTheme.reduceMotion;
          });
        }),
      const Padding(padding: EdgeInsets.only(top: 12), child: Text(
        'Custom colours support the full hue range. Settings are currently saved on this device.',
        textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12))),
    ]),
  );
}
