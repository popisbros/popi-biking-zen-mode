import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_theme.dart';
import '../../providers/community_provider.dart';
import '../../models/community_warning.dart';

class HazardReportScreenWithLocation extends ConsumerStatefulWidget {
  final double initialLatitude;
  final double initialLongitude;
  final String? editingWarningId;

  const HazardReportScreenWithLocation({
    super.key,
    required this.initialLatitude,
    required this.initialLongitude,
    this.editingWarningId,
  });

  @override
  ConsumerState<HazardReportScreenWithLocation> createState() => _HazardReportScreenWithLocationState();
}

class _HazardReportScreenWithLocationState extends ConsumerState<HazardReportScreenWithLocation> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _selectedType = 'hazard';
  String _selectedSeverity = 'medium';
  bool _isLoading = false;

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
    {'value': 'low', 'label': 'Low', 'color': AppColors.successGreen},
    {'value': 'medium', 'label': 'Medium', 'color': Colors.yellow[700]},
    {'value': 'high', 'label': 'High', 'color': Colors.orange[700]},
    {'value': 'critical', 'label': 'Critical', 'color': AppColors.dangerRed},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.editingWarningId != null) {
      _editingWarningId = widget.editingWarningId;
      _loadWarningForEditing();
    }
    print('⚠️ Hazard Report: Initialized with location ${widget.initialLatitude}, ${widget.initialLongitude}');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _loadWarningForEditing() async {
    if (_editingWarningId == null) return;

    try {
      final warningsNotifier = ref.read(communityWarningsNotifierProvider.notifier);
      final warnings = await warningsNotifier.getWarningsFromFirestore();

      final warning = warnings.firstWhere(
        (w) => w.id == _editingWarningId,
        orElse: () => throw Exception('Warning not found'),
      );

      if (mounted) {
        _startEditingWarning(warning);
      }
    } catch (e) {
      print('❌ Hazard Report: Failed to load warning for editing: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load warning: ${e.toString()}'),
            backgroundColor: AppColors.dangerRed,
          ),
        );
      }
    }
  }

  void _startEditingWarning(CommunityWarning warning) {
    setState(() {
      _editingWarningId = warning.id;
      _titleController.text = warning.title;
      _selectedType = warning.type;
      _selectedSeverity = warning.severity;
      _descriptionController.text = warning.description;
    });
    print('⚠️ Hazard Report: Started editing warning: ${warning.title}');
  }

  void _cancelEditing() {
    setState(() {
      _editingWarningId = null;
      _clearForm();
    });
    print('⚠️ Hazard Report: Cancelled editing');
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
        content: const Text('Are you sure you want to delete this warning? This cannot be undone.'),
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
      setState(() => _isLoading = true);

      try {
        final warningsNotifier = ref.read(communityWarningsNotifierProvider.notifier);
        await warningsNotifier.deleteWarning(warningId);

        print('✅ Hazard Report: Successfully deleted warning: $warningId');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Warning deleted successfully!'),
              backgroundColor: AppColors.successGreen,
            ),
          );
          _cancelEditing();
        }
      } catch (e) {
        print('❌ Hazard Report: Failed to delete warning: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete warning: ${e.toString()}'),
              backgroundColor: AppColors.dangerRed,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submitWarning() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final warning = CommunityWarning(
        id: _isEditing ? _editingWarningId : null,
        type: _selectedType,
        severity: _selectedSeverity,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        latitude: widget.initialLatitude,
        longitude: widget.initialLongitude,
        reportedBy: 'anonymous',
        reportedAt: DateTime.now(),
        isActive: true,
        tags: [_selectedType, _selectedSeverity],
      );

      final warningsNotifier = ref.read(communityWarningsNotifierProvider.notifier);

      if (_isEditing) {
        print('⚠️ Hazard Report: Updating warning: ${warning.title}');
        await warningsNotifier.updateWarning(_editingWarningId!, warning);
      } else {
        print('⚠️ Hazard Report: Submitting new warning: ${warning.title}');
        await warningsNotifier.submitWarning(warning);
      }

      print('✅ Hazard Report: Successfully saved warning: ${warning.title}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Warning updated successfully!' : 'Warning reported successfully!'),
            backgroundColor: AppColors.successGreen,
          ),
        );
        Navigator.pop(context); // Close the screen after successful save
      }
    } catch (e) {
      print('❌ Hazard Report: Failed to save warning: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Failed to update warning: ${e.toString()}' : 'Failed to submit warning: ${e.toString()}'),
            backgroundColor: AppColors.dangerRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Warning' : 'Report Hazard'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isEditing ? 'Edit Warning' : 'Report Hazard',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // Location display
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.lightGrey),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Location: ${widget.initialLatitude.toStringAsFixed(5)}, ${widget.initialLongitude.toStringAsFixed(5)}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title *',
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

              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description *',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a description';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Warning Type
              Text(
                'Warning Type *',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _warningTypes.map((type) {
                  final isSelected = _selectedType == type['value'];
                  return GestureDetector(
                    onTap: () => setState(() => _selectedType = type['value']!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary : AppColors.lightGrey,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(type['icon']!, style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 4),
                          Text(
                            type['label']!,
                            style: TextStyle(
                              color: isSelected ? AppColors.surface : AppColors.textDark,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // Severity Level
              Text(
                'Severity *',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _severityLevels.map((severity) {
                  final isSelected = _selectedSeverity == severity['value'];
                  return GestureDetector(
                    onTap: () => setState(() => _selectedSeverity = severity['value']!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? severity['color'] : AppColors.lightGrey,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        severity['label']!,
                        style: TextStyle(
                          color: isSelected ? AppColors.surface : AppColors.textDark,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  if (_isEditing) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isLoading ? null : _cancelEditing,
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : () => _deleteWarning(_editingWarningId!),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.dangerRed,
                          foregroundColor: AppColors.surface,
                        ),
                        child: const Text('Delete'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: _isEditing ? 2 : 1,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submitWarning,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.surface,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(AppColors.surface),
                              ),
                            )
                          : Text(_isEditing ? 'Save' : 'Submit'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
