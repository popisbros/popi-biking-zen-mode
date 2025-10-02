import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_colors.dart';
import '../../providers/community_provider.dart';
import '../../providers/location_provider.dart';
import '../../models/cycling_poi.dart';

class POIManagementScreenWithLocation extends ConsumerStatefulWidget {
  final double initialLatitude;
  final double initialLongitude;
  final String? editingPOIId;

  const POIManagementScreenWithLocation({
    super.key,
    required this.initialLatitude,
    required this.initialLongitude,
    this.editingPOIId,
  });

  @override
  ConsumerState<POIManagementScreenWithLocation> createState() => _POIManagementScreenWithLocationState();
}

class _POIManagementScreenWithLocationState extends ConsumerState<POIManagementScreenWithLocation> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _websiteController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();

  String _selectedType = 'bike_shop';
  double _latitude = 0.0;
  double _longitude = 0.0;
  bool _isLoading = false;

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
  void initState() {
    super.initState();
    _latitude = widget.initialLatitude;
    _longitude = widget.initialLongitude;
    _latitudeController.text = widget.initialLatitude.toStringAsFixed(6);
    _longitudeController.text = widget.initialLongitude.toStringAsFixed(6);

    if (widget.editingPOIId != null) {
      _editingPOIId = widget.editingPOIId;
      _loadPOIForEditing();
    }

    print('📝 POI Management: Initialized with location ${widget.initialLatitude}, ${widget.initialLongitude}');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _websiteController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  void _updateCoordinatesFromGPS() {
    final locationAsync = ref.read(locationNotifierProvider);
    locationAsync.whenData((location) {
      if (location != null && mounted) {
        setState(() {
          _latitude = location.latitude;
          _longitude = location.longitude;
          _latitudeController.text = location.latitude.toStringAsFixed(6);
          _longitudeController.text = location.longitude.toStringAsFixed(6);
        });
        print('📝 POI Management: Updated coordinates from GPS: ${location.latitude}, ${location.longitude}');
      }
    });
  }

  void _loadPOIForEditing() async {
    if (_editingPOIId == null) return;

    try {
      final communityNotifier = ref.read(cyclingPOIsNotifierProvider.notifier);
      final pois = await communityNotifier.getPOIsFromFirestore();

      final poi = pois.firstWhere(
        (p) => p.id == _editingPOIId,
        orElse: () => throw Exception('POI not found'),
      );

      if (mounted) {
        _startEditingPOI(poi);
      }
    } catch (e) {
      print('❌ POI Management: Failed to load POI for editing: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load POI: ${e.toString()}'),
            backgroundColor: AppColors.dangerRed,
          ),
        );
      }
    }
  }

  void _startEditingPOI(CyclingPOI poi) {
    setState(() {
      _editingPOIId = poi.id;
      _nameController.text = poi.name;
      _selectedType = poi.type;
      _latitude = poi.latitude;
      _longitude = poi.longitude;
      _latitudeController.text = poi.latitude.toStringAsFixed(6);
      _longitudeController.text = poi.longitude.toStringAsFixed(6);
      _descriptionController.text = poi.description ?? '';
      _addressController.text = poi.address ?? '';
      _phoneController.text = poi.phone ?? '';
      _websiteController.text = poi.website ?? '';
    });

    print('📝 POI Management: Started editing POI: ${poi.name}');
  }

  void _cancelEditing() {
    setState(() {
      _editingPOIId = null;
      _clearForm();
    });
    print('📝 POI Management: Cancelled editing');
  }

  void _clearForm() {
    _nameController.clear();
    _descriptionController.clear();
    _addressController.clear();
    _phoneController.clear();
    _websiteController.clear();
    _selectedType = 'bike_shop';
    _latitude = widget.initialLatitude;
    _longitude = widget.initialLongitude;
    _latitudeController.text = widget.initialLatitude.toStringAsFixed(6);
    _longitudeController.text = widget.initialLongitude.toStringAsFixed(6);
  }

  Future<void> _deletePOI(String? poiId) async {
    if (poiId == null || poiId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete POI: Invalid ID'),
          backgroundColor: AppColors.dangerRed,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete POI'),
        content: const Text('Are you sure you want to delete this POI? This cannot be undone.'),
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
        final communityNotifier = ref.read(cyclingPOIsNotifierProvider.notifier);
        await communityNotifier.deletePOI(poiId);

        print('✅ POI Management: Successfully deleted POI: $poiId');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('POI deleted successfully!'),
              backgroundColor: AppColors.successGreen,
            ),
          );
          _cancelEditing();
        }
      } catch (e) {
        print('❌ POI Management: Failed to delete POI: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete POI: ${e.toString()}'),
              backgroundColor: AppColors.dangerRed,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _savePOI() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final poi = CyclingPOI(
        id: _isEditing ? _editingPOIId : null,
        name: _nameController.text.trim(),
        type: _selectedType,
        latitude: _latitude,
        longitude: _longitude,
        description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        website: _websiteController.text.trim().isEmpty ? null : _websiteController.text.trim(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final communityNotifier = ref.read(cyclingPOIsNotifierProvider.notifier);

      if (_isEditing) {
        print('📝 POI Management: Updating POI: ${poi.name}');
        await communityNotifier.updatePOI(_editingPOIId!, poi);
      } else {
        print('📝 POI Management: Creating new POI: ${poi.name}');
        await communityNotifier.addPOI(poi);
      }

      print('✅ POI Management: Successfully saved POI: ${poi.name}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'POI updated successfully!' : 'POI added successfully!'),
            backgroundColor: AppColors.successGreen,
          ),
        );
        Navigator.pop(context); // Close the screen after successful save
      }
    } catch (e) {
      print('❌ POI Management: Failed to save POI: $e');
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Community POI'),
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
                _isEditing ? 'Edit POI' : 'Add New POI',
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
                        'Location: ${_latitude.toStringAsFixed(5)}, ${_longitude.toStringAsFixed(5)}',
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
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  border: OutlineInputBorder(),
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
                decoration: const InputDecoration(
                  labelText: 'Type *',
                  border: OutlineInputBorder(),
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
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _websiteController,
                decoration: const InputDecoration(
                  labelText: 'Website',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
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
                        onPressed: _isLoading ? null : () => _deletePOI(_editingPOIId!),
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
                      onPressed: _isLoading ? null : _savePOI,
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
                          : Text(_isEditing ? 'Save' : 'Add POI'),
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
