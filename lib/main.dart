import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  }
  runApp(const PikafyApp());
}

class PikafyApp extends StatelessWidget {
  const PikafyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pikafy',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090B12),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9A83FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF171A27),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
      return const SetupScreen();
    }
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        return session == null ? const LoginScreen() : const HomeScreen();
      },
    );
  }
}

class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Text(
          'Pikafy\n\nSupabase connection is not configured yet. Add SUPABASE_URL and SUPABASE_ANON_KEY to the build settings.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, height: 1.6),
        ),
      ),
    ),
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
  bool creating = false;
  bool busy = false;
  String message = '';

  Future<void> submit() async {
    setState(() { busy = true; message = ''; });
    try {
      final auth = Supabase.instance.client.auth;
      if (creating) {
        await auth.signUp(email: email.text.trim(), password: password.text);
        message = 'Account request sent. Check your email if confirmation is enabled.';
      } else {
        await auth.signInWithPassword(email: email.text.trim(), password: password.text);
      }
    } on AuthException catch (e) {
      message = e.message;
    } catch (e) {
      message = 'Something went wrong. Please try again.';
    }
    if (mounted) setState(() { busy = false; });
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(26),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.graphic_eq_rounded, size: 58, color: Color(0xFFB7A5FF)),
                  const SizedBox(height: 14),
                  const Text('pikafy', textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 42, fontWeight: FontWeight.w800, letterSpacing: -2)),
                  const SizedBox(height: 8),
                  Text(creating ? 'Create your account' : 'Your music, your space.',
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 38),
                  TextField(controller: email, keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email')),
                  const SizedBox(height: 14),
                  TextField(controller: password, obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password')),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 17)),
                    child: Text(busy ? 'Please wait...' : creating ? 'Create account' : 'Log in'),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => setState(() => creating = !creating),
                    child: Text(creating ? 'Already have an account? Log in' : 'New to Pikafy? Create account'),
                  ),
                  if (message.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 12),
                      child: Text(message, textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFC8BFFF)))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('pikafy', style: TextStyle(fontWeight: FontWeight.w800)),
      actions: [
        IconButton(
          tooltip: 'Log out',
          onPressed: () => Supabase.instance.client.auth.signOut(),
          icon: const Icon(Icons.logout_rounded),
        ),
      ],
    ),
    body: const Center(
      child: Text('Welcome to Pikafy. Your music space is getting ready.',
        textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
    ),
  );
}
