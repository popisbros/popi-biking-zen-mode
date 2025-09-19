import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../providers/community_provider.dart';
import '../services/firebase_service.dart';

class DebugScreen extends ConsumerWidget {
  const DebugScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warningsAsync = ref.watch(communityWarningsProvider);
    final poisAsync = ref.watch(cyclingPOIsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug - Community Data'),
        backgroundColor: AppColors.urbanBlue,
        foregroundColor: AppColors.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Warnings Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Community Warnings',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.urbanBlue,
                      ),
                    ),
                    const SizedBox(height: 16),
                    warningsAsync.when(
                      data: (warnings) {
                        if (warnings.isEmpty) {
                          return const Text(
                            'No warnings found. This could be due to:\n'
                            '1. No warnings in Firestore\n'
                            '2. CORS issues preventing data loading\n'
                            '3. Location filtering (currently set to San Francisco)\n'
                            '4. Data structure mismatch',
                            style: TextStyle(color: AppColors.dangerRed),
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Found ${warnings.length} warnings:'),
                            const SizedBox(height: 8),
                            ...warnings.map((warning) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.lightGrey),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Title: ${warning.title}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text('Type: ${warning.type}'),
                                  Text('Severity: ${warning.severity}'),
                                  Text('Location: ${warning.latitude}, ${warning.longitude}'),
                                  Text('Active: ${warning.isActive}'),
                                  Text('Reported: ${warning.reportedAt}'),
                                ],
                              ),
                            )),
                          ],
                        );
                      },
                      loading: () => const CircularProgressIndicator(),
                      error: (error, stack) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Error loading warnings:',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.dangerRed,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            error.toString(),
                            style: const TextStyle(color: AppColors.dangerRed),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Stack trace:',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(stack.toString()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // POIs Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cycling POIs',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.urbanBlue,
                      ),
                    ),
                    const SizedBox(height: 16),
                    poisAsync.when(
                      data: (pois) {
                        if (pois.isEmpty) {
                          return const Text(
                            'No POIs found.',
                            style: TextStyle(color: AppColors.dangerRed),
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Found ${pois.length} POIs:'),
                            const SizedBox(height: 8),
                            ...pois.map((poi) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.lightGrey),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Name: ${poi.name}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text('Type: ${poi.type}'),
                                  Text('Location: ${poi.latitude}, ${poi.longitude}'),
                                  if (poi.description != null) Text('Description: ${poi.description}'),
                                ],
                              ),
                            )),
                          ],
                        );
                      },
                      loading: () => const CircularProgressIndicator(),
                      error: (error, stack) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Error loading POIs:',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.dangerRed,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            error.toString(),
                            style: const TextStyle(color: AppColors.dangerRed),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Actions Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Debug Actions',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.urbanBlue,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () async {
                        try {
                          final firebaseService = FirebaseService();
                          await firebaseService.submitWarning({
                            'type': 'hazard',
                            'severity': 'medium',
                            'title': 'Test Warning',
                            'description': 'This is a test warning for debugging',
                            'latitude': 37.7749,
                            'longitude': -122.4194,
                            'reportedBy': 'debug_user',
                            'reportedAt': DateTime.now().millisecondsSinceEpoch,
                            'isActive': true,
                            'tags': ['test', 'debug'],
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Test warning submitted successfully!'),
                              backgroundColor: AppColors.mossGreen,
                            ),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error submitting test warning: $e'),
                              backgroundColor: AppColors.dangerRed,
                            ),
                          );
                        }
                      },
                      child: const Text('Submit Test Warning'),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () {
                        ref.invalidate(communityWarningsProvider);
                        ref.invalidate(cyclingPOIsProvider);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Providers refreshed!'),
                            backgroundColor: AppColors.urbanBlue,
                          ),
                        );
                      },
                      child: const Text('Refresh Data'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
