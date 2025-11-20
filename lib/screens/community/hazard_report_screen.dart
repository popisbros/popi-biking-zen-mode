import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_colors.dart';
import '../../providers/community_provider.dart';
import '../../models/community_warning.dart';
import '../../utils/app_logger.dart';
import '../../widgets/common_dialog.dart';
import '../../config/poi_type_config.dart';

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

  String _selectedType = 'pothole';
  String _selectedSeverity = 'medium';
  bool _isLoading = false;

  String? _editingWarningId;
  bool get _isEditing => _editingWarningId != null;

  // Use centralized warning types from POITypeConfig
  List<Map<String, String>> get _warningTypes => POITypeConfig.warningTypes;

  final List<Map<String, dynamic>> _severityLevels = [
    {'value': 'low', 'label': 'Low', 'color': AppColors.successGreen},
    {'value': 'medium', 'label': 'Medium', 'color': Colors.yellow[700]},
    {'value': 'high', 'label': 'High', 'color': Colors.orange[700]},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.editingWarningId != null) {
      _editingWarningId = widget.editingWarningId;
      _loadWarningForEditing();
    }
    AppLogger.debug('Initialized with location', tag: 'HAZARD', data: {
      'latitude': widget.initialLatitude,
      'longitude': widget.initialLongitude,
    });
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
      AppLogger.error('Failed to load warning for editing', tag: 'HAZARD', error: e);
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
    AppLogger.debug('Started editing warning', tag: 'HAZARD', data: {
      'title': warning.title,
      'type': warning.type,
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingWarningId = null;
      _clearForm();
    });
    AppLogger.debug('Cancelled editing', tag: 'HAZARD');
  }

  void _clearForm() {
    _titleController.clear();
    _descriptionController.clear();
    _selectedType = 'pothole';
    _selectedSeverity = 'medium';
  }

  /// Get expiration days for a hazard type
  int _getExpirationDays(String type) {
    switch (type) {
      case 'construction':
        return 60; // Construction sites last months
      case 'traffic_hazard':
        return 14; // Traffic issues usually temporary
      case 'flooding':
        return 7; // Weather-related, short-term
      case 'steep':
        return 90; // Permanent terrain feature
      case 'poor_surface':
        return 30; // Surface degradation is gradual
      case 'debris':
        return 7; // Usually cleaned up quickly
      case 'pothole':
        return 30; // Takes time to fix
      case 'dangerous_intersection':
        return 90; // Permanent infrastructure issue
      case 'other':
      default:
        return 30; // Default
    }
  }

  /// Calculate expiration date based on hazard type
  DateTime _calculateExpirationDate(String type, DateTime reportedAt) {
    final expirationDays = _getExpirationDays(type);
    return reportedAt.add(Duration(days: expirationDays));
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
      barrierColor: CommonDialog.barrierColor,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white.withValues(alpha: CommonDialog.backgroundOpacity),
        titlePadding: CommonDialog.titlePadding,
        contentPadding: CommonDialog.contentPadding,
        actionsPadding: CommonDialog.actionsPadding,
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

        AppLogger.success('Successfully deleted warning', tag: 'HAZARD', data: {
          'warningId': warningId,
        });

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
        AppLogger.error('Failed to delete warning', tag: 'HAZARD', error: e);
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
      final reportedAt = DateTime.now();
      final expiresAt = _calculateExpirationDate(_selectedType, reportedAt);

      final warning = CommunityWarning(
        id: _isEditing ? _editingWarningId : null,
        type: _selectedType,
        severity: _selectedSeverity,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        latitude: widget.initialLatitude,
        longitude: widget.initialLongitude,
        reportedBy: 'anonymous',
        reportedAt: reportedAt,
        isActive: true,
        tags: [_selectedType, _selectedSeverity],
        // New fields for enhanced hazard system
        upvotes: 0,
        downvotes: 0,
        verifiedBy: [],
        userVotes: {},
        status: 'active',
        expiresAt: expiresAt,
      );

      final warningsNotifier = ref.read(communityWarningsNotifierProvider.notifier);

      if (_isEditing) {
        AppLogger.debug('Updating warning', tag: 'HAZARD', data: {
          'title': warning.title,
          'type': warning.type,
        });
        await warningsNotifier.updateWarning(_editingWarningId!, warning);
      } else {
        AppLogger.debug('Submitting new warning', tag: 'HAZARD', data: {
          'title': warning.title,
          'type': warning.type,
        });
        await warningsNotifier.submitWarning(warning);
      }

      AppLogger.success('Successfully saved warning', tag: 'HAZARD', data: {
        'title': warning.title,
      });

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
      AppLogger.error('Failed to save warning', tag: 'HAZARD', error: e);
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
        backgroundColor: AppColors.urbanBlue,
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
                  color: AppColors.urbanBlue,
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
                    const Icon(Icons.location_on, color: AppColors.urbanBlue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Location: ${widget.initialLatitude.toStringAsFixed(5)}, ${widget.initialLongitude.toStringAsFixed(5)}',
                        style: const TextStyle(
                          color: AppColors.urbanBlue,
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
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),

              // Warning Type
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
                  return GestureDetector(
                    onTap: () => setState(() => _selectedType = type['value']!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.urbanBlue : AppColors.lightGrey,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(type['emoji']!, style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 4),
                          Text(
                            type['label']!,
                            style: TextStyle(
                              color: isSelected ? AppColors.surface : AppColors.onSurface,
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
                  color: AppColors.urbanBlue,
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
                          color: isSelected ? AppColors.surface : AppColors.onSurface,
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
                        backgroundColor: AppColors.urbanBlue,
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
