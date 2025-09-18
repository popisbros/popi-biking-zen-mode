import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../models/cycling_poi.dart';

class POICard extends StatelessWidget {
  final CyclingPOI poi;
  final VoidCallback? onTap;

  const POICard({
    super.key,
    required this.poi,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // POI Icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getPOIColor(poi.type).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getPOIIcon(poi.type),
                  color: _getPOIColor(poi.type),
                  size: 24,
                ),
              ),
              
              const SizedBox(width: 16),
              
              // POI Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      poi.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.urbanBlue,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getPOITypeLabel(poi.type),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _getPOIColor(poi.type),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (poi.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        poi.description!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.urbanBlue.withOpacity(0.7),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (poi.address != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 12,
                            color: AppColors.urbanBlue.withOpacity(0.6),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              poi.address!,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.urbanBlue.withOpacity(0.6),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              
              // Distance and Action
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.lightGrey,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '0.5 km', // TODO: Calculate actual distance
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.urbanBlue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Icon(
                    Icons.chevron_right,
                    color: AppColors.lightGrey,
                    size: 20,
                  ),
                ],
              ),
            ],
          ),
        ),
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

  Color _getPOIColor(String type) {
    switch (type) {
      case 'bike_shop':
        return AppColors.urbanBlue;
      case 'parking':
        return AppColors.mossGreen;
      case 'repair_station':
        return AppColors.warningOrange;
      case 'water_fountain':
        return Colors.blue;
      case 'rest_area':
        return AppColors.signalYellow;
      default:
        return AppColors.urbanBlue;
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
