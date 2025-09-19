import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_colors.dart';
import '../../providers/community_provider.dart';
import '../../models/cycling_poi.dart';
import '../../services/debug_service.dart';

class POIManagementScreen extends ConsumerStatefulWidget {
  const POIManagementScreen({super.key});

  @override
  ConsumerState<POIManagementScreen> createState() => _POIManagementScreenState();
}

class _POIManagementScreenState extends ConsumerState<POIManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _websiteController = TextEditingController();
  final _debugService = DebugService();
  
  String _selectedType = 'bike_shop';
  double _latitude = 37.7749;
  double _longitude = -122.4194;
  bool _isLoading = false;
  
  // Editing state
  String? _editingPOIId;
  bool get _isEditing => _editingPOIId != null;

  final List<Map<String, String>> _poiTypes = [
    {'value': 'bike_shop', 'label': 'Bike Shop'},
    {'value': 'parking', 'label': 'Bike Parking'},
    {'value': 'repair_station', 'label': 'Repair Station'},
    {'value': 'water_fountain', 'label': 'Water Fountain'},
    {'value': 'rest_area', 'label': 'Rest Area'},
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  void _startEditingPOI(CyclingPOI poi) {
    setState(() {
      _editingPOIId = poi.id;
      _nameController.text = poi.name;
      _selectedType = poi.type;
      _latitude = poi.latitude;
      _longitude = poi.longitude;
      _descriptionController.text = poi.description ?? '';
      _addressController.text = poi.address ?? '';
      _phoneController.text = poi.phone ?? '';
      _websiteController.text = poi.website ?? '';
    });
    
    _debugService.logAction(
      action: 'POI: Started editing POI',
      screen: 'POIManagementScreen',
      parameters: {'poiId': poi.id, 'poiName': poi.name},
    );
  }

  void _cancelEditing() {
    setState(() {
      _editingPOIId = null;
      _clearForm();
    });
    
    _debugService.logAction(
      action: 'POI: Cancelled editing',
      screen: 'POIManagementScreen',
    );
  }

  void _clearForm() {
    _nameController.clear();
    _descriptionController.clear();
    _addressController.clear();
    _phoneController.clear();
    _websiteController.clear();
    _selectedType = 'bike_shop';
    _latitude = 37.7749;
    _longitude = -122.4194;
  }

  Future<void> _deletePOI(String poiId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete POI'),
        content: const Text('Are you sure you want to delete this POI? This action cannot be undone.'),
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
        final communityNotifier = ref.read(cyclingPOIsNotifierProvider.notifier);
        await communityNotifier.deletePOI(poiId);

        _debugService.logAction(
          action: 'POI: Successfully deleted POI',
          screen: 'POIManagementScreen',
          parameters: {'poiId': poiId},
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('POI deleted successfully!'),
              backgroundColor: AppColors.mossGreen,
            ),
          );
        }
      } catch (e) {
        _debugService.logAction(
          action: 'POI: Failed to delete POI',
          screen: 'POIManagementScreen',
          error: e.toString(),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete POI: ${e.toString()}'),
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

  Future<void> _savePOI() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final poi = CyclingPOI(
        id: _editingPOIId ?? '', // Use existing ID if editing
        name: _nameController.text.trim(),
        type: _selectedType,
        latitude: _latitude,
        longitude: _longitude,
        description: _descriptionController.text.trim().isEmpty 
            ? null 
            : _descriptionController.text.trim(),
        address: _addressController.text.trim().isEmpty 
            ? null 
            : _addressController.text.trim(),
        phone: _phoneController.text.trim().isEmpty 
            ? null 
            : _phoneController.text.trim(),
        website: _websiteController.text.trim().isEmpty 
            ? null 
            : _websiteController.text.trim(),
        createdAt: _isEditing ? DateTime.now() : DateTime.now(), // Keep original if editing
        updatedAt: DateTime.now(),
      );

      final communityNotifier = ref.read(cyclingPOIsNotifierProvider.notifier);
      
      if (_isEditing) {
        _debugService.logAction(
          action: 'POI: Updating existing POI',
          screen: 'POIManagementScreen',
          parameters: {
            'poiId': _editingPOIId,
            'name': poi.name,
            'type': poi.type,
          },
        );
        
        await communityNotifier.updatePOI(poi);
        
        _debugService.logAction(
          action: 'POI: Successfully updated POI',
          screen: 'POIManagementScreen',
          result: 'POI updated in Firebase',
        );
      } else {
        _debugService.logAction(
          action: 'POI: Creating new POI',
          screen: 'POIManagementScreen',
          parameters: {
            'name': poi.name,
            'type': poi.type,
            'latitude': poi.latitude,
            'longitude': poi.longitude,
          },
        );
        
        await communityNotifier.addPOI(poi);
        
        _debugService.logAction(
          action: 'POI: Successfully created POI',
          screen: 'POIManagementScreen',
          result: 'POI added to Firebase',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'POI updated successfully!' : 'POI added successfully!'),
            backgroundColor: AppColors.mossGreen,
          ),
        );
        
        // Clear form and exit edit mode
        _cancelEditing();
      }
    } catch (e) {
      _debugService.logAction(
        action: _isEditing ? 'POI: Failed to update POI' : 'POI: Failed to create POI',
        screen: 'POIManagementScreen',
        error: e.toString(),
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Failed to update POI: ${e.toString()}' : 'Failed to add POI: ${e.toString()}'),
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
    final poisAsync = ref.watch(cyclingPOIsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('POI Management'),
        backgroundColor: AppColors.urbanBlue,
        foregroundColor: AppColors.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Add/Edit POI Form
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
                        _isEditing ? 'Edit POI' : 'Add New POI',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.urbanBlue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Name *',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      DropdownButtonFormField<String>(
                        value: _selectedType,
                        decoration: InputDecoration(
                          labelText: 'Type *',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: _poiTypes.map((type) {
                          return DropdownMenuItem(
                            value: type['value'],
                            child: Text(type['label']!),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedType = value!;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      TextFormField(
                        controller: _descriptionController,
                        decoration: InputDecoration(
                          labelText: 'Description',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),
                      
                      TextFormField(
                        controller: _addressController,
                        decoration: InputDecoration(
                          labelText: 'Address',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      TextFormField(
                        controller: _phoneController,
                        decoration: InputDecoration(
                          labelText: 'Phone',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 16),
                      
                      TextFormField(
                        controller: _websiteController,
                        decoration: InputDecoration(
                          labelText: 'Website',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        keyboardType: TextInputType.url,
                      ),
                      const SizedBox(height: 16),
                      
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: _latitude.toString(),
                              decoration: InputDecoration(
                                labelText: 'Latitude',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                _latitude = double.tryParse(value) ?? _latitude;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              initialValue: _longitude.toString(),
                              decoration: InputDecoration(
                                labelText: 'Longitude',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                _longitude = double.tryParse(value) ?? _longitude;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                        // Action buttons
                        Row(
                          children: [
                            if (_isEditing) ...[
                              // Cancel button when editing
                              Expanded(
                                child: Semantics(
                                  label: 'Cancel editing POI',
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
                                  label: 'Delete POI',
                                  button: true,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : () => _deletePOI(_editingPOIId!),
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
                            // Save/Add button
                            Expanded(
                              flex: _isEditing ? 2 : 1,
                              child: Semantics(
                                label: _isEditing ? 'Save POI changes' : 'Add new point of interest to the map',
                                button: true,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _savePOI,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.urbanBlue,
                                    foregroundColor: AppColors.surface,
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
                                          _isEditing ? 'Save POI' : 'Add POI',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
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
            
            // Existing POIs List
            Text(
              'Existing POIs',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.urbanBlue,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            poisAsync.when(
              data: (pois) => ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: pois.length,
                itemBuilder: (context, index) {
                  final poi = pois[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Text(
                        _getPOIIcon(poi.type),
                        style: const TextStyle(fontSize: 24),
                      ),
                      title: Text(poi.name),
                      subtitle: Text('${poi.type} • ${poi.latitude.toStringAsFixed(4)}, ${poi.longitude.toStringAsFixed(4)}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Edit button
                          Semantics(
                            label: 'Edit point of interest: ${poi.name}',
                            button: true,
                            child: IconButton(
                              icon: const Icon(Icons.edit, color: AppColors.urbanBlue),
                              onPressed: () => _startEditingPOI(poi),
                            ),
                          ),
                          // Delete button
                          Semantics(
                            label: 'Delete point of interest: ${poi.name}',
                            button: true,
                            child: IconButton(
                              icon: const Icon(Icons.delete, color: AppColors.dangerRed),
                              onPressed: () => _deletePOI(poi.id),
                            ),
                          ),
                        ],
                      ),
                      onTap: () => _startEditingPOI(poi),
                    ),
                  );
                },
              ),
              loading: () => const Center(
                child: CircularProgressIndicator(),
              ),
              error: (error, stack) => Center(
                child: Text('Error loading POIs: $error'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getPOIIcon(String type) {
    switch (type) {
      case 'bike_shop':
        return '🏪';
      case 'parking':
        return '🚲';
      case 'repair_station':
        return '🔧';
      case 'water_fountain':
        return '💧';
      case 'rest_area':
        return '🪑';
      default:
        return '📍';
    }
  }
}
