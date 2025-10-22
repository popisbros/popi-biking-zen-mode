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

    return authState.when(
      data: (user) {
        if (user == null) {
          // Not signed in - show sign in button
          return FloatingActionButton(
            mini: true,
            heroTag: 'profile_login',
            backgroundColor: Colors.white,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            child: const Icon(Icons.login, color: Colors.blue),
          );
        }

        // Signed in - show profile avatar
        final userProfile = ref.watch(userProfileProvider);

        return userProfile.when(
          data: (profile) {
            return FloatingActionButton(
              mini: true,
              heroTag: 'profile_avatar',
              backgroundColor: Colors.white,
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
                      profile?.displayName?.substring(0, 1).toUpperCase() ?? 'U',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
            );
          },
          loading: () => FloatingActionButton(
            mini: true,
            heroTag: 'profile_loading',
            backgroundColor: Colors.white,
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
            backgroundColor: Colors.white,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
            child: const Icon(Icons.person, color: Colors.blue),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
