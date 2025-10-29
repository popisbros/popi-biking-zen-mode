import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import 'register_screen.dart';
import '../../widgets/common_dialog.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  String? _errorMessage;
  bool _isLoading = false;

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await ref.read(authNotifierProvider.notifier).signInWithGoogle();

      if (!mounted) return;

      if (result != null) {
        // Success - close login screen after current frame to avoid GlobalKey conflicts
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });
      } else {
        // User cancelled or sign-in not configured - just reset loading state
        // Don't show error message for cancellation
        Future.microtask(() {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        });
      }
    } catch (e) {
      if (!mounted) return;

      Future.microtask(() {
        if (mounted) {
          setState(() {
            _errorMessage = 'Google Sign-In failed: ${e.toString()}';
            _isLoading = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Close',
        ),
        title: const Text('Sign In'),
      ),
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
                  onPressed: _isLoading ? null : _handleGoogleSignIn,
                ),
                const SizedBox(height: 16),

                // Sign in with Email
                _SignInButton(
                  icon: Icons.email,
                  label: 'Continue with Email',
                  color: Colors.blue,
                  textColor: Colors.white,
                  onPressed: _isLoading ? null : _handleEmailSignIn,
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

                // Loading indicator
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: CircularProgressIndicator(),
                  ),

                // Error message
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          ),
                        ],
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

  Future<void> _handleEmailSignIn() async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    final credentials = await showDialog<Map<String, String>>(
      context: context,
      barrierColor: CommonDialog.barrierColor,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white.withValues(alpha: CommonDialog.backgroundOpacity),
        titlePadding: CommonDialog.titlePadding,
        contentPadding: CommonDialog.contentPadding,
        actionsPadding: CommonDialog.actionsPadding,
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
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              onSubmitted: (_) {
                // Allow Enter key to submit
                final email = emailController.text.trim();
                final password = passwordController.text;
                if (email.isNotEmpty && password.isNotEmpty) {
                  Navigator.pop(context, {'email': email, 'password': password});
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final email = emailController.text.trim();
              final password = passwordController.text;

              if (email.isEmpty || password.isEmpty) {
                return;
              }
              Navigator.pop(context, {'email': email, 'password': password});
            },
            child: const Text('Sign In'),
          ),
        ],
      ),
    );

    emailController.dispose();
    passwordController.dispose();

    if (credentials == null) return;

    final email = credentials['email']!;
    final password = credentials['password']!;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authNotifierProvider.notifier).signInWithEmail(email, password);

      if (!mounted) return;

      // Success - close login screen after current frame to avoid GlobalKey conflicts
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    } catch (e) {
      if (!mounted) return;

      // Parse Firebase error message
      String errorMessage = 'Sign-in failed';
      final errorStr = e.toString().toLowerCase();

      if (errorStr.contains('user-not-found') || errorStr.contains('user not found')) {
        errorMessage = 'No account found with this email. Please register first.';
      } else if (errorStr.contains('wrong-password') || errorStr.contains('wrong password') || errorStr.contains('invalid-credential')) {
        errorMessage = 'Incorrect password. Please try again.';
      } else if (errorStr.contains('invalid-email')) {
        errorMessage = 'Invalid email address format.';
      } else if (errorStr.contains('user-disabled')) {
        errorMessage = 'This account has been disabled.';
      } else if (errorStr.contains('too-many-requests')) {
        errorMessage = 'Too many failed attempts. Please try again later.';
      } else if (errorStr.contains('network')) {
        errorMessage = 'Network error. Please check your connection.';
      } else {
        errorMessage = 'Sign-in failed: ${e.toString()}';
      }

      // Schedule setState for next frame to ensure safe state update on all platforms
      // Using Future.microtask for better iOS compatibility
      Future.microtask(() {
        if (mounted) {
          setState(() {
            _errorMessage = errorMessage;
            _isLoading = false;
          });
        }
      });
    }
  }
}

class _SignInButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback? onPressed;

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
