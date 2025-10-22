import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../providers/auth_provider.dart';
import 'register_screen.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // App Logo/Title
                const Icon(Icons.directions_bike, size: 80, color: Colors.blue),
                const SizedBox(height: 16),
                const Text(
                  'Popi Biking',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your cycling companion',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 48),

                // Sign in with Google
                _SignInButton(
                  icon: Icons.g_mobiledata,
                  label: 'Continue with Google',
                  color: Colors.white,
                  textColor: Colors.black87,
                  onPressed: () async {
                    await ref.read(authNotifierProvider.notifier).signInWithGoogle();
                  },
                ),
                const SizedBox(height: 16),

                // Sign in with Apple (iOS/macOS only)
                if (!kIsWeb && (Platform.isIOS || Platform.isMacOS))
                  _SignInButton(
                    icon: Icons.apple,
                    label: 'Continue with Apple',
                    color: Colors.black,
                    textColor: Colors.white,
                    onPressed: () async {
                      await ref.read(authNotifierProvider.notifier).signInWithApple();
                    },
                  ),
                if (!kIsWeb && (Platform.isIOS || Platform.isMacOS))
                  const SizedBox(height: 16),

                // Sign in with Email
                _SignInButton(
                  icon: Icons.email,
                  label: 'Continue with Email',
                  color: Colors.blue,
                  textColor: Colors.white,
                  onPressed: () {
                    _showEmailLoginDialog(context, ref);
                  },
                ),
                const SizedBox(height: 24),

                // Register link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Don't have an account?"),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const RegisterScreen()),
                        );
                      },
                      child: const Text('Sign up'),
                    ),
                  ],
                ),

                // Loading/Error state
                authState.when(
                  data: (_) => const SizedBox.shrink(),
                  loading: () => const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: CircularProgressIndicator(),
                  ),
                  error: (error, _) => Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Text(
                      'Error: ${error.toString()}',
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEmailLoginDialog(BuildContext context, WidgetRef ref) {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign in with Email'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim();
              final password = passwordController.text;

              if (email.isEmpty || password.isEmpty) return;

              Navigator.pop(context);
              await ref.read(authNotifierProvider.notifier).signInWithEmail(email, password);
            },
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }
}

class _SignInButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onPressed;

  const _SignInButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: textColor),
        label: Text(label, style: TextStyle(color: textColor, fontSize: 16)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: color == Colors.white
                ? const BorderSide(color: Colors.grey)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }
}
