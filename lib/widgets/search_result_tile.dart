import 'package:flutter/material.dart';
import '../models/search_result.dart';

/// Widget to display a single search result
class SearchResultTile extends StatelessWidget {
  final SearchResult result;
  final VoidCallback onTap;

  const SearchResultTile({
    super.key,
    required this.result,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Colors.grey.withOpacity(0.2),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            // Icon based on result type or LocationIQ icon
            _buildIcon(),
            const SizedBox(width: 12),

            // Title and subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (result.subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      result.subtitle!,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // Distance
            if (result.distance != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  result.distanceText,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIcon() {
    // Map LocationIQ icon URL to Material icon
    // LocationIQ icons are blocked by CORS, so we use Material icons based on the icon type
    if (result.iconUrl != null && result.iconUrl!.isNotEmpty) {
      final icon = _getIconFromUrl(result.iconUrl!);
      return Icon(
        icon,
        color: Colors.grey[600],
        size: 20,
      );
    }

    // Fallback to Material icon
    return Icon(
      result.type == SearchResultType.coordinates
          ? Icons.my_location
          : Icons.location_on,
      color: Colors.grey[600],
      size: 20,
    );
  }

  /// Map LocationIQ icon URL to Material icon based on icon type
  IconData _getIconFromUrl(String iconUrl) {
    // Extract icon type from URL (e.g., food_restaurant, lodging, etc.)
    if (iconUrl.contains('food_') || iconUrl.contains('restaurant')) {
      return Icons.restaurant;
    } else if (iconUrl.contains('lodging') || iconUrl.contains('hotel')) {
      return Icons.hotel;
    } else if (iconUrl.contains('cafe') || iconUrl.contains('coffee')) {
      return Icons.local_cafe;
    } else if (iconUrl.contains('bar') || iconUrl.contains('pub')) {
      return Icons.local_bar;
    } else if (iconUrl.contains('shopping') || iconUrl.contains('mall')) {
      return Icons.shopping_bag;
    } else if (iconUrl.contains('transport') || iconUrl.contains('station')) {
      return Icons.directions_transit;
    } else if (iconUrl.contains('airport')) {
      return Icons.flight;
    } else if (iconUrl.contains('hospital') || iconUrl.contains('health')) {
      return Icons.local_hospital;
    } else if (iconUrl.contains('education') || iconUrl.contains('school')) {
      return Icons.school;
    } else if (iconUrl.contains('attraction') || iconUrl.contains('tourism')) {
      return Icons.attractions;
    } else if (iconUrl.contains('parking')) {
      return Icons.local_parking;
    } else if (iconUrl.contains('bank') || iconUrl.contains('atm')) {
      return Icons.account_balance;
    } else if (iconUrl.contains('gas') || iconUrl.contains('fuel')) {
      return Icons.local_gas_station;
    } else if (iconUrl.contains('worship') || iconUrl.contains('church')) {
      return Icons.church;
    }

    // Default location icon
    return Icons.place;
  }
}
