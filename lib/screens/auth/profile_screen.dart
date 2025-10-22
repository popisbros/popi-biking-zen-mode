import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _countryController;

  bool _isEditing = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _countryController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    await ref.read(authNotifierProvider.notifier).updateProfile(
          displayName: _nameController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          country: _countryController.text.trim(),
        );

    if (mounted) {
      setState(() {
        _isLoading = false;
        _isEditing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProfile = ref.watch(userProfileProvider);
    final authState = ref.watch(authStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              try {
                await ref.read(authNotifierProvider.notifier).signOut();
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Signed out successfully')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Sign out failed: ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: authState.when(
        data: (user) {
          if (user == null) {
            return const Center(child: Text('Not signed in'));
          }

          return userProfile.when(
            data: (profile) {
              if (profile == null) {
                return const Center(child: Text('Profile not found'));
              }

              // Update controllers when profile loads
              if (_nameController.text.isEmpty) {
                _nameController.text = profile.displayName ?? '';
                _phoneController.text = profile.phoneNumber ?? '';
                _countryController.text = profile.country ?? '';
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Avatar
                      CircleAvatar(
                        radius: 50,
                        backgroundImage: profile.photoURL != null
                            ? NetworkImage(profile.photoURL!)
                            : null,
                        child: profile.photoURL == null
                            ? Text(
                                profile.displayName?.substring(0, 1).toUpperCase() ?? 'U',
                                style: const TextStyle(fontSize: 40),
                              )
                            : null,
                      ),
                      const SizedBox(height: 16),

                      // Email (read-only)
                      Text(
                        profile.email ?? 'No email',
                        style: const TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),

                      // Auth provider badge
                      Chip(
                        label: Text('Signed in with ${profile.authProvider}'),
                        avatar: Icon(_getAuthIcon(profile.authProvider), size: 16),
                      ),
                      const SizedBox(height: 32),

                      // Full Name
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Full Name',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                        enabled: _isEditing,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Phone Number
                      TextFormField(
                        controller: _phoneController,
                        decoration: const InputDecoration(
                          labelText: 'Mobile Number',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.phone),
                        ),
                        enabled: _isEditing,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 16),

                      // Country
                      TextFormField(
                        controller: _countryController,
                        decoration: const InputDecoration(
                          labelText: 'Country',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.flag),
                        ),
                        enabled: _isEditing,
                      ),
                      const SizedBox(height: 32),

                      // Save/Cancel buttons (when editing)
                      if (_isEditing)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  setState(() {
                                    _isEditing = false;
                                    // Reset controllers
                                    _nameController.text = profile.displayName ?? '';
                                    _phoneController.text = profile.phoneNumber ?? '';
                                    _countryController.text = profile.country ?? '';
                                  });
                                },
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _saveProfile,
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Text('Save'),
                              ),
                            ),
                          ],
                        ),

                      const SizedBox(height: 32),
                      const Divider(),
                      const SizedBox(height: 16),

                      // Stats and Lists
                      _buildStatCard('Default Route', profile.defaultRouteProfile, null),
                      const SizedBox(height: 16),

                      _buildExpandableSection(
                        'Recent Searches',
                        profile.recentSearches.length,
                        20,
                        profile.recentSearches.isEmpty
                            ? const Text('No recent searches', style: TextStyle(color: Colors.grey))
                            : Column(
                                children: profile.recentSearches.map((search) =>
                                  ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.history, size: 20),
                                    title: Text(search, style: const TextStyle(fontSize: 14)),
                                  ),
                                ).toList(),
                              ),
                      ),
                      const SizedBox(height: 8),

                      _buildExpandableSection(
                        'Recent Destinations',
                        profile.recentDestinations.length,
                        20,
                        profile.recentDestinations.isEmpty
                            ? const Text('No recent destinations', style: TextStyle(color: Colors.grey))
                            : Column(
                                children: profile.recentDestinations.map((dest) =>
                                  ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.location_on, size: 20, color: Colors.orange),
                                    title: Text(dest.name, style: const TextStyle(fontSize: 14)),
                                    subtitle: Text(
                                      '${dest.latitude.toStringAsFixed(4)}, ${dest.longitude.toStringAsFixed(4)}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ).toList(),
                              ),
                      ),
                      const SizedBox(height: 8),

                      _buildExpandableSection(
                        'Favorite Locations',
                        profile.favoriteLocations.length,
                        20,
                        profile.favoriteLocations.isEmpty
                            ? const Text('No favorites yet', style: TextStyle(color: Colors.grey))
                            : Column(
                                children: profile.favoriteLocations.map((fav) =>
                                  ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.star, size: 20, color: Colors.amber),
                                    title: Text(fav.name, style: const TextStyle(fontSize: 14)),
                                    subtitle: Text(
                                      '${fav.latitude.toStringAsFixed(4)}, ${fav.longitude.toStringAsFixed(4)}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ).toList(),
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('Error: $error')),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
      ),
    );
  }

  Widget _buildStatCard(String label, dynamic value, int? max) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          Text(
            max != null ? '$value / $max' : value.toString(),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandableSection(String title, int count, int max, Widget content) {
    return Card(
      elevation: 2,
      child: ExpansionTile(
        title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        subtitle: Text('$count / $max', style: const TextStyle(fontSize: 14)),
        children: [
          Container(
            constraints: const BoxConstraints(maxHeight: 300),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: content,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getAuthIcon(String provider) {
    switch (provider) {
      case 'google':
        return Icons.g_mobiledata;
      case 'apple':
        return Icons.apple;
      case 'email':
        return Icons.email;
      default:
        return Icons.person;
    }
  }
}
