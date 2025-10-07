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
    // Use LocationIQ icon if available
    if (result.iconUrl != null && result.iconUrl!.isNotEmpty) {
      return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
        ),
        child: Image.network(
          result.iconUrl!,
          width: 20,
          height: 20,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            // Fallback to default icon on error
            return Icon(
              result.type == SearchResultType.coordinates
                  ? Icons.my_location
                  : Icons.location_on,
              color: Colors.grey[600],
              size: 20,
            );
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return SizedBox(
              width: 20,
              height: 20,
              child: Center(
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                ),
              ),
            );
          },
        ),
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
}
