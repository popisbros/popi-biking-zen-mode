import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_colors.dart';
import '../../providers/community_provider.dart';
import '../../providers/location_provider.dart';
import '../../models/community_warning.dart';

class HazardReportScreen extends ConsumerStatefulWidget {
  const HazardReportScreen({super.key});

  @override
  ConsumerState<HazardReportScreen> createState() => _HazardReportScreenState();
}

class _HazardReportScreenState extends ConsumerState<HazardReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  String _selectedType = 'hazard';
  String _selectedSeverity = 'medium';
  bool _isLoading = false;

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
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final locationAsync = ref.read(locationNotifierProvider);
      
      locationAsync.whenData((location) async {
        if (location != null) {
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
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not get current location to report warning.'),
                backgroundColor: AppColors.dangerRed,
              ),
            );
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit warning: ${e.toString()}'),
            backgroundColor: AppColors.dangerRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Hazard'),
        backgroundColor: AppColors.urbanBlue,
        foregroundColor: AppColors.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Report a hazard or warning for other cyclists.',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.lightGrey,
                    ),
              ),
              const SizedBox(height: 24),
              
              // Current location display
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.lightGrey),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, color: AppColors.urbanBlue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ref.watch(locationNotifierProvider).when(
                        data: (location) => Text(
                          location != null
                              ? 'Location: ${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}'
                              : 'Getting location...',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        loading: () => const Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
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
                  ],
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
                    onPressed: _isLoading ? null : _submitWarning,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.urbanBlue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.surface),
                          )
                        : const Text(
                            'Submit Warning',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Existing Warnings List
              Text(
                'Existing Warnings',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.urbanBlue,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              
              // Watch for warnings data
              Consumer(
                builder: (context, ref, child) {
                  final warningsAsync = ref.watch(communityWarningsProvider);
                  
                  return warningsAsync.when(
                    data: (warnings) => ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: warnings.length,
                      itemBuilder: (context, index) {
                        final warning = warnings[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Text(
                              _getWarningIcon(warning.type),
                              style: const TextStyle(fontSize: 24),
                            ),
                            title: Text(
                              warning.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (warning.description != null)
                                  Text(
                                    warning.description!,
                                    style: const TextStyle(fontSize: 12),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _getSeverityColor(warning.severity),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        warning.severity.toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _formatDateTime(warning.reportedAt),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.lightGrey,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            trailing: Icon(
                              Icons.location_on,
                              color: AppColors.mossGreen,
                              size: 16,
                            ),
                            onTap: () {
                              // Show warning details
                              _showWarningDetails(warning);
                            },
                          ),
                        );
                      },
                    ),
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    error: (error, stack) => Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Colors.red.shade600,
                            size: 32,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Failed to load warnings',
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            error.toString(),
                            style: TextStyle(
                              color: Colors.red.shade600,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getWarningIcon(String type) {
    switch (type) {
      case 'hazard':
        return '⚠️';
      case 'construction':
        return '🚧';
      case 'road_closure':
        return '🚫';
      case 'poor_condition':
        return '🕳️';
      case 'traffic':
        return '🚗';
      case 'weather':
        return '🌧️';
      default:
        return '⚠️';
    }
  }

  Color _getSeverityColor(String severity) {
    switch (severity) {
      case 'high':
        return AppColors.dangerRed;
      case 'medium':
        return AppColors.signalYellow;
      case 'low':
        return AppColors.mossGreen;
      default:
        return AppColors.lightGrey;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  void _showWarningDetails(CommunityWarning warning) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Text(_getWarningIcon(warning.type)),
            const SizedBox(width: 8),
            Expanded(child: Text(warning.title)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (warning.description != null) ...[
              Text(warning.description!),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Text(
                  'Severity: ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getSeverityColor(warning.severity),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    warning.severity.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Reported: ${_formatDateTime(warning.reportedAt)}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.lightGrey,
              ),
            ),
            if (warning.reportedBy != null) ...[
              const SizedBox(height: 4),
              Text(
                'By: ${warning.reportedBy}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.lightGrey,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
