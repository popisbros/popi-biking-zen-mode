import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../providers/location_provider.dart';
import '../providers/community_provider.dart';
import '../services/firebase_service.dart';
import '../models/community_warning.dart';

class WarningReportModal extends ConsumerStatefulWidget {
  const WarningReportModal({super.key});

  @override
  ConsumerState<WarningReportModal> createState() => _WarningReportModalState();
}

class _WarningReportModalState extends ConsumerState<WarningReportModal> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _selectedType = 'hazard';
  String _selectedSeverity = 'medium';

  final List<Map<String, String>> _warningTypes = [
    {'value': 'hazard', 'label': 'Hazard', 'icon': '⚠️'},
    {'value': 'construction', 'label': 'Construction', 'icon': '🚧'},
    {'value': 'road_closure', 'label': 'Road Closure', 'icon': '🚫'},
    {'value': 'poor_condition', 'label': 'Poor Condition', 'icon': '🕳️'},
    {'value': 'traffic', 'label': 'Heavy Traffic', 'icon': '🚗'},
    {'value': 'weather', 'label': 'Weather', 'icon': '🌧️'},
  ];

  final List<Map<String, dynamic>> _severityLevels = [
    {'value': 'low', 'label': 'Low', 'color': AppColors.mossGreen},
    {'value': 'medium', 'label': 'Medium', 'color': AppColors.signalYellow},
    {'value': 'high', 'label': 'High', 'color': AppColors.warningOrange},
    {'value': 'critical', 'label': 'Critical', 'color': AppColors.dangerRed},
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitWarning() async {
    if (_formKey.currentState!.validate()) {
      final locationAsync = ref.read(locationNotifierProvider);
      
      locationAsync.whenData((location) async {
        if (location != null) {
          try {
            // Create warning data
            final warningData = {
              'type': _selectedType,
              'severity': _selectedSeverity,
              'title': _titleController.text.trim(),
              'description': _descriptionController.text.trim(),
              'latitude': location.latitude,
              'longitude': location.longitude,
              'reportedBy': 'anonymous', // TODO: Get from auth
              'reportedAt': DateTime.now().millisecondsSinceEpoch,
              'isActive': true,
              'tags': [_selectedType, _selectedSeverity],
            };

            // Submit to Firebase using the community provider
            final communityNotifier = ref.read(communityWarningsNotifierProvider.notifier);
            final warning = CommunityWarning.fromMap(warningData);
            await communityNotifier.submitWarning(warning);
            
            // Show success message
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Warning reported successfully!'),
                  backgroundColor: AppColors.mossGreen,
                ),
              );
              
              Navigator.of(context).pop();
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to submit warning: ${e.toString()}'),
                  backgroundColor: AppColors.dangerRed,
                ),
              );
            }
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location not available. Please enable GPS.'),
                backgroundColor: AppColors.dangerRed,
              ),
            );
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationAsync = ref.watch(locationNotifierProvider);
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.lightGrey,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(
                  Icons.warning,
                  color: AppColors.signalYellow,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'Report Warning',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.urbanBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  color: AppColors.urbanBlue,
                ),
              ],
            ),
          ),
          
          // Form
          Expanded(
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Location info
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.lightGrey.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: locationAsync.when(
                        data: (location) => Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              color: location != null ? AppColors.mossGreen : AppColors.dangerRed,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                location != null 
                                    ? 'Location: ${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}'
                                    : 'Location not available',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: location != null ? AppColors.mossGreen : AppColors.dangerRed,
                                ),
                              ),
                            ),
                          ],
                        ),
                        loading: () => const Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('Getting location...'),
                          ],
                        ),
                        error: (error, stack) => const Row(
                          children: [
                            Icon(Icons.error_outline, color: AppColors.dangerRed, size: 20),
                            SizedBox(width: 8),
                            Text('Location error'),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Warning type
                    Text(
                      'Warning Type',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _warningTypes.map((type) {
                        final isSelected = _selectedType == type['value'];
                        return Semantics(
                          label: 'Select warning type: ${type['label']}',
                          button: true,
                          selected: isSelected,
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedType = type['value']!),
                            child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.urbanBlue : AppColors.lightGrey,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected ? AppColors.urbanBlue : AppColors.lightGrey,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  type['icon']!,
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  type['label']!,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : AppColors.urbanBlue,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Severity level
                    Text(
                      'Severity Level',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _severityLevels.map((severity) {
                        final isSelected = _selectedSeverity == severity['value'];
                        final color = severity['color'] as Color;
                        return Semantics(
                          label: 'Select severity level: ${severity['label']}',
                          button: true,
                          selected: isSelected,
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedSeverity = severity['value']!),
                            child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected ? color : color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: color),
                            ),
                            child: Text(
                              severity['label']!,
                              style: TextStyle(
                                color: isSelected ? Colors.white : color,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Title field
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        hintText: 'Brief description of the warning',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a title';
                        }
                        return null;
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Description field
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description (Optional)',
                        hintText: 'Additional details about the warning',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      child: Semantics(
                        label: 'Submit community warning report',
                        button: true,
                        child: ElevatedButton(
                          onPressed: _submitWarning,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.urbanBlue,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'Submit Warning',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
