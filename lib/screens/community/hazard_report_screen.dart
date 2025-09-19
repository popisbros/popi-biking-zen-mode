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

class HazardReportScreenWithLocation extends ConsumerStatefulWidget {
  final double initialLatitude;
  final double initialLongitude;

  const HazardReportScreenWithLocation({
    super.key,
    required this.initialLatitude,
    required this.initialLongitude,
  });

  @override
  ConsumerState<HazardReportScreenWithLocation> createState() => _HazardReportScreenWithLocationState();
}

class _HazardReportScreenState extends ConsumerState<HazardReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  String _selectedType = 'hazard';
  String _selectedSeverity = 'medium';
  bool _isLoading = false;
  
  // Editing state
  String? _editingWarningId;
  bool get _isEditing => _editingWarningId != null;

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

  void _startEditingWarning(CommunityWarning warning) {
    setState(() {
      _editingWarningId = warning.id;
      _titleController.text = warning.title;
      _selectedType = warning.type;
      _selectedSeverity = warning.severity;
      _descriptionController.text = warning.description;
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingWarningId = null;
      _clearForm();
    });
  }

  void _clearForm() {
    _titleController.clear();
    _descriptionController.clear();
    _selectedType = 'hazard';
    _selectedSeverity = 'medium';
  }

  Future<void> _deleteWarning(String? warningId) async {
    if (warningId == null || warningId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete warning: Invalid ID'),
          backgroundColor: AppColors.dangerRed,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Warning'),
        content: const Text('Are you sure you want to delete this warning? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isLoading = true;
      });

      try {
        final communityNotifier = ref.read(communityWarningsNotifierProvider.notifier);
        await communityNotifier.deleteWarning(warningId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Warning deleted successfully!'),
              backgroundColor: AppColors.mossGreen,
            ),
          );
          
          // Clear form and exit edit mode
          _cancelEditing();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete warning: ${e.toString()}'),
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
            'id': _isEditing ? _editingWarningId : null,
            'type': _selectedType,
            'severity': _selectedSeverity,
            'title': _titleController.text.trim(),
            'description': _descriptionController.text.trim(),
            'latitude': location.latitude,
            'longitude': location.longitude,
            'reportedBy': 'anonymous',
            'reportedAt': DateTime.now().millisecondsSinceEpoch,
            'isActive': true,
            'tags': [_selectedType, _selectedSeverity],
          };

          // Submit to Firebase using the community provider
          final communityNotifier = ref.read(communityWarningsNotifierProvider.notifier);
          final warning = CommunityWarning.fromMap(warningData);
          
          if (_isEditing) {
            await communityNotifier.updateWarning(_editingWarningId!, warning);
          } else {
            await communityNotifier.submitWarning(warning);
          }
          
          // Show success message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_isEditing ? 'Warning updated successfully!' : 'Warning reported successfully!'),
                backgroundColor: AppColors.mossGreen,
              ),
            );
            
            // Clear form and exit edit mode
            _cancelEditing();
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
            content: Text(_isEditing ? 'Failed to update warning: ${e.toString()}' : 'Failed to submit warning: ${e.toString()}'),
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
        title: Text(_isEditing ? 'Edit Warning' : 'Report Hazard'),
        backgroundColor: AppColors.urbanBlue,
        foregroundColor: AppColors.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Add/Edit Warning Form
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isEditing ? 'Edit Warning' : 'Add New Warning',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.urbanBlue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Current location display
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.lightGrey),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.location_on, color: AppColors.urbanBlue, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ref.watch(locationNotifierProvider).when(
                                data: (location) => Text(
                                  location != null
                                      ? 'Location: ${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}'
                                      : 'Getting location...',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.urbanBlue,
                                    fontWeight: FontWeight.w500,
                                  ),
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
                      
                      const SizedBox(height: 16),
                      
                      // Warning type
                      Text(
                        'Warning Type *',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.urbanBlue,
                        ),
                      ),
                      const SizedBox(height: 8),
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
                      
                      const SizedBox(height: 16),
                      
                      // Severity level
                      Text(
                        'Severity Level *',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.urbanBlue,
                        ),
                      ),
                      const SizedBox(height: 8),
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
                      
                      const SizedBox(height: 16),
                      
                      // Title field
                      TextFormField(
                        controller: _titleController,
                        decoration: InputDecoration(
                          labelText: 'Title *',
                          hintText: 'Brief description of the warning',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
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
                        decoration: InputDecoration(
                          labelText: 'Description (Optional)',
                          hintText: 'Additional details about the warning',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        maxLines: 3,
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Action buttons
                      Row(
                        children: [
                          if (_isEditing) ...[
                            // Cancel button when editing
                            Expanded(
                              child: Semantics(
                                label: 'Cancel editing warning',
                                button: true,
                                child: OutlinedButton(
                                  onPressed: _isLoading ? null : _cancelEditing,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.urbanBlue,
                                    side: const BorderSide(color: AppColors.urbanBlue),
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Delete button when editing
                            Expanded(
                              child: Semantics(
                                label: 'Delete warning',
                                button: true,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : () => _deleteWarning(_editingWarningId),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.dangerRed,
                                    foregroundColor: AppColors.surface,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'Delete',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          // Save/Submit button
                          Expanded(
                            flex: _isEditing ? 2 : 1,
                            child: Semantics(
                              label: _isEditing ? 'Save warning changes' : 'Submit community warning report',
                              button: true,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _submitWarning,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.urbanBlue,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _isLoading
                                    ? const CircularProgressIndicator(
                                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.surface),
                                      )
                                    : Text(
                                        _isEditing ? 'Save Warning' : 'Submit Warning',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
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
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Edit button
                              Semantics(
                                label: 'Edit warning: ${warning.title}',
                                button: true,
                                child: IconButton(
                                  icon: const Icon(Icons.edit, color: AppColors.urbanBlue),
                                  onPressed: () => _startEditingWarning(warning),
                                ),
                              ),
                              // Delete button
                              Semantics(
                                label: 'Delete warning: ${warning.title}',
                                button: true,
                                child: IconButton(
                                  icon: const Icon(Icons.delete, color: AppColors.dangerRed),
                                  onPressed: () => _deleteWarning(warning.id),
                                ),
                              ),
                            ],
                          ),
                          onTap: () => _startEditingWarning(warning),
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
                  error: (error, stack) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 48,
                            color: AppColors.dangerRed,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Failed to load warnings',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: AppColors.dangerRed,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            error.toString(),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.lightGrey,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
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
}

class _HazardReportScreenWithLocationState extends ConsumerState<HazardReportScreenWithLocation> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  String _selectedType = 'hazard';
  String _selectedSeverity = 'medium';
  bool _isLoading = false;
  
  // Editing state
  String? _editingWarningId;
  bool get _isEditing => _editingWarningId != null;

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
  void initState() {
    super.initState();
    print('HazardReportScreenWithLocation initialized with coordinates: ${widget.initialLatitude}, ${widget.initialLongitude}');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _startEditingWarning(CommunityWarning warning) {
    setState(() {
      _editingWarningId = warning.id;
      _titleController.text = warning.title;
      _selectedType = warning.type;
      _selectedSeverity = warning.severity;
      _descriptionController.text = warning.description;
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingWarningId = null;
      _clearForm();
    });
  }

  void _clearForm() {
    _titleController.clear();
    _descriptionController.clear();
    _selectedType = 'hazard';
    _selectedSeverity = 'medium';
  }

  Future<void> _deleteWarning(String? warningId) async {
    if (warningId == null || warningId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete warning: Invalid ID'),
          backgroundColor: AppColors.dangerRed,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Warning'),
        content: const Text('Are you sure you want to delete this warning? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isLoading = true;
      });

      try {
        final communityNotifier = ref.read(communityWarningsNotifierProvider.notifier);
        await communityNotifier.deleteWarning(warningId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Warning deleted successfully!'),
              backgroundColor: AppColors.mossGreen,
            ),
          );
          
          // Clear form and exit edit mode
          _cancelEditing();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete warning: ${e.toString()}'),
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
  }

  Future<void> _submitWarning() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Use the provided coordinates instead of GPS location
      final warningData = {
        'id': _isEditing ? _editingWarningId : null,
        'type': _selectedType,
        'severity': _selectedSeverity,
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'latitude': widget.initialLatitude,
        'longitude': widget.initialLongitude,
        'reportedBy': 'anonymous',
        'reportedAt': DateTime.now().millisecondsSinceEpoch,
        'isActive': true,
        'tags': [_selectedType, _selectedSeverity],
      };

      // Submit to Firebase using the community provider
      final communityNotifier = ref.read(communityWarningsNotifierProvider.notifier);
      final warning = CommunityWarning.fromMap(warningData);
      
      if (_isEditing) {
        await communityNotifier.updateWarning(_editingWarningId!, warning);
      } else {
        await communityNotifier.submitWarning(warning);
      }
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Warning updated successfully!' : 'Warning reported successfully!'),
            backgroundColor: AppColors.mossGreen,
          ),
        );
        
        // Clear form and exit edit mode
        _cancelEditing();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Failed to update warning: ${e.toString()}' : 'Failed to submit warning: ${e.toString()}'),
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
        title: Text(_isEditing ? 'Edit Warning' : 'Report Hazard'),
        backgroundColor: AppColors.urbanBlue,
        foregroundColor: AppColors.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Add/Edit Warning Form
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isEditing ? 'Edit Warning' : 'Add New Warning',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.urbanBlue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Current location display
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.lightGrey),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.location_on, color: AppColors.urbanBlue, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Location: ${widget.initialLatitude.toStringAsFixed(4)}, ${widget.initialLongitude.toStringAsFixed(4)}',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppColors.urbanBlue,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Warning type
                      Text(
                        'Warning Type *',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.urbanBlue,
                        ),
                      ),
                      const SizedBox(height: 8),
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
                      
                      const SizedBox(height: 16),
                      
                      // Severity level
                      Text(
                        'Severity Level *',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.urbanBlue,
                        ),
                      ),
                      const SizedBox(height: 8),
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
                      
                      const SizedBox(height: 16),
                      
                      // Title field
                      TextFormField(
                        controller: _titleController,
                        decoration: InputDecoration(
                          labelText: 'Title *',
                          hintText: 'Brief description of the warning',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
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
                        decoration: InputDecoration(
                          labelText: 'Description (Optional)',
                          hintText: 'Additional details about the warning',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        maxLines: 3,
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Action buttons
                      Row(
                        children: [
                          if (_isEditing) ...[
                            // Cancel button when editing
                            Expanded(
                              child: Semantics(
                                label: 'Cancel editing warning',
                                button: true,
                                child: OutlinedButton(
                                  onPressed: _isLoading ? null : _cancelEditing,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.urbanBlue,
                                    side: const BorderSide(color: AppColors.urbanBlue),
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Delete button when editing
                            Expanded(
                              child: Semantics(
                                label: 'Delete warning',
                                button: true,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : () => _deleteWarning(_editingWarningId),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.dangerRed,
                                    foregroundColor: AppColors.surface,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'Delete',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          // Save/Submit button
                          Expanded(
                            flex: _isEditing ? 2 : 1,
                            child: Semantics(
                              label: _isEditing ? 'Save warning changes' : 'Submit community warning report',
                              button: true,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _submitWarning,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.urbanBlue,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _isLoading
                                    ? const CircularProgressIndicator(
                                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.surface),
                                      )
                                    : Text(
                                        _isEditing ? 'Save Warning' : 'Submit Warning',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
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
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Edit button
                              Semantics(
                                label: 'Edit warning: ${warning.title}',
                                button: true,
                                child: IconButton(
                                  icon: const Icon(Icons.edit, color: AppColors.urbanBlue),
                                  onPressed: () => _startEditingWarning(warning),
                                ),
                              ),
                              // Delete button
                              Semantics(
                                label: 'Delete warning: ${warning.title}',
                                button: true,
                                child: IconButton(
                                  icon: const Icon(Icons.delete, color: AppColors.dangerRed),
                                  onPressed: () => _deleteWarning(warning.id),
                                ),
                              ),
                            ],
                          ),
                          onTap: () => _startEditingWarning(warning),
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
                  error: (error, stack) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 48,
                            color: AppColors.dangerRed,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Failed to load warnings',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: AppColors.dangerRed,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            error.toString(),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.lightGrey,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
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
}
