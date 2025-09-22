import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import 'map_screen.dart';
import 'mapbox_3d_screen.dart';

class LauncherScreen extends ConsumerWidget {
  const LauncherScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App Logo/Title
              Icon(
                Icons.directions_bike,
                size: 80,
                color: AppColors.mossGreen,
              ),
              const SizedBox(height: 24),
              Text(
                'Popi Is Biking Zen Mode',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.urbanBlue,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Choose your map experience',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.lightGrey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              
              // 2D Map Option
              _buildMapOption(
                context: context,
                title: '2D Map',
                subtitle: 'Classic flat map view with cycling features',
                icon: Icons.map,
                color: AppColors.mossGreen,
                onTap: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const MapScreen()),
                  );
                },
              ),
              
              const SizedBox(height: 24),
              
              // 3D Map Option
              _buildMapOption(
                context: context,
                title: '3D Map',
                subtitle: 'Immersive 3D perspective with Mapbox GL',
                icon: Icons.view_in_ar,
                color: AppColors.azureBlue,
                onTap: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const Mapbox3DScreen()),
                  );
                },
              ),
              
              const SizedBox(height: 48),
              
              // Info text
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.signalYellow.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.signalYellow.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: AppColors.signalYellow,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '3D Map requires Mapbox access token. Run with: flutter run --dart-define=MAPBOX_API_KEY=YOUR_TOKEN',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.urbanBlue,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapOption({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: AppColors.surface,
                size: 32,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.urbanBlue,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: color,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
