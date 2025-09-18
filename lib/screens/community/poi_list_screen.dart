import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_colors.dart';
import '../../models/cycling_poi.dart';
import '../../services/firebase_service.dart';
import '../../widgets/poi/poi_card.dart';

class POIListScreen extends ConsumerStatefulWidget {
  const POIListScreen({super.key});

  @override
  ConsumerState<POIListScreen> createState() => _POIListScreenState();
}

class _POIListScreenState extends ConsumerState<POIListScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  List<CyclingPOI> _pois = [];
  bool _isLoading = true;
  String _selectedFilter = 'all';

  final List<Map<String, String>> _filterOptions = [
    {'value': 'all', 'label': 'All POIs'},
    {'value': 'bike_shop', 'label': 'Bike Shops'},
    {'value': 'parking', 'label': 'Bike Parking'},
    {'value': 'repair_station', 'label': 'Repair Stations'},
    {'value': 'water_fountain', 'label': 'Water Fountains'},
    {'value': 'rest_area', 'label': 'Rest Areas'},
  ];

  @override
  void initState() {
    super.initState();
    _loadPOIs();
  }

  Future<void> _loadPOIs() async {
    setState(() => _isLoading = true);
    try {
      // In a real app, you'd get POIs from Firebase
      // For now, we'll create some sample POIs
      _pois = _getSamplePOIs();
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load POIs: ${e.toString()}'),
            backgroundColor: AppColors.dangerRed,
          ),
        );
      }
    }
  }

  List<CyclingPOI> _getSamplePOIs() {
    return [
      CyclingPOI(
        id: '1',
        name: 'Downtown Bike Shop',
        type: 'bike_shop',
        latitude: 37.7749,
        longitude: -122.4194,
        description: 'Full-service bike shop with repairs and rentals',
        address: '123 Market St, San Francisco, CA',
        phone: '(555) 123-4567',
        website: 'https://downtownbikes.com',
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
        updatedAt: DateTime.now(),
      ),
      CyclingPOI(
        id: '2',
        name: 'Golden Gate Park Bike Parking',
        type: 'parking',
        latitude: 37.7694,
        longitude: -122.4862,
        description: 'Secure bike parking with 50+ spaces',
        address: 'Golden Gate Park, San Francisco, CA',
        createdAt: DateTime.now().subtract(const Duration(days: 15)),
        updatedAt: DateTime.now(),
      ),
      CyclingPOI(
        id: '3',
        name: 'Mission District Repair Station',
        type: 'repair_station',
        latitude: 37.7599,
        longitude: -122.4148,
        description: 'Free bike repair station with tools and air pump',
        address: 'Mission St & 16th St, San Francisco, CA',
        createdAt: DateTime.now().subtract(const Duration(days: 7)),
        updatedAt: DateTime.now(),
      ),
      CyclingPOI(
        id: '4',
        name: 'Embarcadero Water Fountain',
        type: 'water_fountain',
        latitude: 37.7989,
        longitude: -122.3992,
        description: 'Public water fountain with bottle filling station',
        address: 'Embarcadero, San Francisco, CA',
        createdAt: DateTime.now().subtract(const Duration(days: 20)),
        updatedAt: DateTime.now(),
      ),
      CyclingPOI(
        id: '5',
        name: 'Presidio Rest Area',
        type: 'rest_area',
        latitude: 37.7989,
        longitude: -122.4662,
        description: 'Scenic rest area with benches and bike racks',
        address: 'Presidio, San Francisco, CA',
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
        updatedAt: DateTime.now(),
      ),
    ];
  }

  List<CyclingPOI> get _filteredPOIs {
    if (_selectedFilter == 'all') {
      return _pois;
    }
    return _pois.where((poi) => poi.type == _selectedFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cycling POIs'),
        backgroundColor: AppColors.urbanBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPOIs,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          Container(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _filterOptions.map((filter) {
                  final isSelected = _selectedFilter == filter['value'];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(filter['label']!),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          _selectedFilter = filter['value']!;
                        });
                      },
                      selectedColor: AppColors.mossGreen.withOpacity(0.3),
                      checkmarkColor: AppColors.mossGreen,
                      backgroundColor: AppColors.lightGrey,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          
          // POI List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredPOIs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.location_off,
                              size: 64,
                              color: AppColors.lightGrey,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No POIs found',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: AppColors.lightGrey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Try adjusting your filter or check back later',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.lightGrey,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredPOIs.length,
                        itemBuilder: (context, index) {
                          final poi = _filteredPOIs[index];
                          return POICard(
                            poi: poi,
                            onTap: () => _showPOIDetails(poi),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNewPOI,
        backgroundColor: AppColors.signalYellow,
        foregroundColor: AppColors.urbanBlue,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showPOIDetails(CyclingPOI poi) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => POIDetailsModal(poi: poi),
    );
  }

  void _addNewPOI() {
    // TODO: Implement add new POI functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Add POI feature coming soon'),
        backgroundColor: AppColors.signalYellow,
      ),
    );
  }
}

class POIDetailsModal extends StatelessWidget {
  final CyclingPOI poi;

  const POIDetailsModal({super.key, required this.poi});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
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
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.urbanBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getPOIIcon(poi.type),
                    color: AppColors.urbanBlue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        poi.name,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AppColors.urbanBlue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _getPOITypeLabel(poi.type),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.urbanBlue.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  color: AppColors.urbanBlue,
                ),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (poi.description != null) ...[
                    Text(
                      'Description',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      poi.description!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  if (poi.address != null) ...[
                    Text(
                      'Address',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 16, color: AppColors.urbanBlue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            poi.address!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  if (poi.phone != null) ...[
                    Text(
                      'Phone',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.phone, size: 16, color: AppColors.urbanBlue),
                        const SizedBox(width: 8),
                        Text(
                          poi.phone!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  if (poi.website != null) ...[
                    Text(
                      'Website',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.web, size: 16, color: AppColors.urbanBlue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            poi.website!,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.urbanBlue,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // Action buttons
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            // TODO: Implement directions
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Directions feature coming soon'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.directions),
                          label: const Text('Directions'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.urbanBlue,
                            side: const BorderSide(color: AppColors.urbanBlue),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            // TODO: Implement share
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Share feature coming soon'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.share),
                          label: const Text('Share'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.urbanBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getPOIIcon(String type) {
    switch (type) {
      case 'bike_shop':
        return Icons.store;
      case 'parking':
        return Icons.local_parking;
      case 'repair_station':
        return Icons.build;
      case 'water_fountain':
        return Icons.water_drop;
      case 'rest_area':
        return Icons.chair;
      default:
        return Icons.place;
    }
  }

  String _getPOITypeLabel(String type) {
    switch (type) {
      case 'bike_shop':
        return 'Bike Shop';
      case 'parking':
        return 'Bike Parking';
      case 'repair_station':
        return 'Repair Station';
      case 'water_fountain':
        return 'Water Fountain';
      case 'rest_area':
        return 'Rest Area';
      default:
        return 'Point of Interest';
    }
  }
}
