import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../screens/auth/profile_screen.dart';
import '../screens/auth/login_screen.dart';

/// Profile button for top-right corner of map
class ProfileButton extends ConsumerWidget {
  const ProfileButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final buttonColor = isDark ? Colors.grey.shade700 : Colors.white;
    final iconColor = isDark ? Colors.lightBlue : Colors.blue;

    return authState.when(
      data: (user) {
        if (user == null) {
          // Not signed in - show sign in button
          return FloatingActionButton(
            mini: true,
            heroTag: 'profile_login',
            backgroundColor: buttonColor,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            child: Icon(Icons.login, color: iconColor),
          );
        }

        // Signed in - show profile avatar
        final userProfile = ref.watch(userProfileProvider);

        return userProfile.when(
          data: (profile) {
            return FloatingActionButton(
              mini: true,
              heroTag: 'profile_avatar',
              backgroundColor: buttonColor,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
              child: profile?.photoURL != null
                  ? CircleAvatar(
                      backgroundImage: NetworkImage(profile!.photoURL!),
                    )
                  : Text(
                      profile?.getInitials() ?? 'U',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: iconColor,
                      ),
                    ),
            );
          },
          loading: () => FloatingActionButton(
            mini: true,
            heroTag: 'profile_loading',
            backgroundColor: buttonColor,
            onPressed: null,
            child: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (_, __) => FloatingActionButton(
            mini: true,
            heroTag: 'profile_error',
            backgroundColor: buttonColor,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
            child: Icon(Icons.person, color: iconColor),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
