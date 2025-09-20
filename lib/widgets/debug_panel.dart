import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../providers/community_provider.dart';
import '../providers/osm_poi_provider.dart';
import '../services/debug_service.dart';

class DebugPanel extends ConsumerStatefulWidget {
  final VoidCallback? onClose;
  
  const DebugPanel({super.key, this.onClose});

  @override
  ConsumerState<DebugPanel> createState() => _DebugPanelState();
}

class _DebugPanelState extends ConsumerState<DebugPanel> {
  final DebugService _debugService = DebugService();
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final warningsAsync = ref.watch(communityWarningsProvider);
    final poisAsync = ref.watch(cyclingPOIsProvider);
    final osmPOIsAsync = ref.watch(osmPOIsNotifierProvider);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 8, bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.lightGrey,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(
                  Icons.bug_report,
                  color: AppColors.warningOrange,
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Debug Panel',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.urbanBlue,
                  ),
                ),
                const Spacer(),
                if (widget.onClose != null)
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close),
                    color: AppColors.urbanBlue,
                  ),
              ],
            ),
          ),
          
          // Tab bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                _buildTab(0, 'Actions', Icons.touch_app),
                _buildTab(1, 'Data', Icons.data_object),
                _buildTab(2, 'Errors', Icons.error_outline),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Content
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildTabContent(_selectedTab, warningsAsync, poisAsync, osmPOIsAsync),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(int index, String label, IconData icon) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : Colors.black87,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(int tabIndex, AsyncValue warningsAsync, AsyncValue poisAsync, AsyncValue osmPOIsAsync) {
    switch (tabIndex) {
      case 0:
        return _buildActionsTab();
      case 1:
        return _buildDataTab(warningsAsync, poisAsync, osmPOIsAsync);
      case 2:
        return _buildErrorsTab();
      default:
        return const SizedBox();
    }
  }

  Widget _buildActionsTab() {
    return StreamBuilder<List<UserAction>>(
      stream: _debugService.actionsStream,
      initialData: _debugService.actions,
      builder: (context, snapshot) {
        final actions = snapshot.data ?? [];
        
        if (actions.isEmpty) {
          return const Center(
            child: Text(
              'No actions recorded yet.\nStart interacting with the app!',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.lightGrey),
            ),
          );
        }

        return Column(
          children: [
            Row(
              children: [
                Text(
                  'Recent Actions (${actions.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.urbanBlue,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    _debugService.clearActions();
                    _debugService.logAction(action: 'Debug: Cleared action history');
                  },
                  child: const Text('Clear'),
                ),
              ],
            ),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: actions.length,
                itemBuilder: (context, index) {
                  final action = actions[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade400, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _getActionIcon(action.action),
                              size: 16,
                              color: _getActionColor(action.action),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SelectableText(
                                action.action,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            SelectableText(
                              _formatTime(action.timestamp),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        if (action.screen != null) ...[
                          const SizedBox(height: 4),
                          SelectableText(
                            'Screen: ${action.screen}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        if (action.parameters != null && action.parameters!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          SelectableText(
                            'Params: ${action.parameters}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        if (action.result != null) ...[
                          const SizedBox(height: 4),
                          SelectableText(
                            'Result: ${action.result}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (action.error != null) ...[
                          const SizedBox(height: 4),
                          SelectableText(
                            'Error: ${action.error}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDataTab(AsyncValue warningsAsync, AsyncValue poisAsync, AsyncValue osmPOIsAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Force Reload Buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  _debugService.logButtonClick('Force Reload Warnings', screen: 'DebugPanel');
                  // Force refresh the provider
                  ref.refresh(communityWarningsProvider);
                  // Also invalidate to force a complete reload
                  ref.invalidate(communityWarningsProvider);
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Reload Warnings'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.dangerRed,
                  foregroundColor: AppColors.surface,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  _debugService.logButtonClick('Force Reload POIs', screen: 'DebugPanel');
                  // Force refresh the provider
                  ref.refresh(cyclingPOIsProvider);
                  // Also invalidate to force a complete reload
                  ref.invalidate(cyclingPOIsProvider);
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Reload POIs'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.mossGreen,
                  foregroundColor: AppColors.surface,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  _debugService.logButtonClick('Force Reload OSM POIs', screen: 'DebugPanel');
                  // Force refresh the OSM POI provider
                  ref.refresh(osmPOIsNotifierProvider);
                  // Also invalidate to force a complete reload
                  ref.invalidate(osmPOIsNotifierProvider);
                },
                icon: const Icon(Icons.public, size: 16),
                label: const Text('Reload OSM POIs'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.lightGrey,
                  foregroundColor: AppColors.surface,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // Warnings Section
        Expanded(
          child: _buildDataSection<dynamic>(
            'Community Warnings',
            warningsAsync as AsyncValue<List<dynamic>>,
            (warnings) => warnings.length,
            (warnings) => warnings.map((w) => '${w.title} (${w.severity})').toList(),
          ),
        ),
        
        const SizedBox(height: 8),
        
        // POIs Section
        Expanded(
          child: _buildDataSection<dynamic>(
            'Cycling POIs',
            poisAsync as AsyncValue<List<dynamic>>,
            (pois) => pois.length,
            (pois) => pois.map((p) => '${p.name} (${p.type})').toList(),
          ),
        ),
        
        const SizedBox(height: 8),
        
        // OSM POIs Section
        Expanded(
          child: _buildOSMDataSection(osmPOIsAsync),
        ),
      ],
    );
  }

  Widget _buildDataSection<T>(
    String title,
    AsyncValue<List<T>> asyncValue,
    int Function(List<T>) countFunction,
    List<String> Function(List<T>) itemsFunction,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade400, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          asyncValue.when(
            data: (data) {
              final count = countFunction(data);
              final items = itemsFunction(data);
              
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Count: $count',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                  if (items.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...items.take(5).map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: SelectableText(
                        '• $item',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    )),
                    if (items.length > 5)
                      Text(
                        '... and ${items.length - 5} more',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ] else ...[
                    Text(
                      'No items found',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              );
            },
            loading: () => Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Loading...',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            error: (error, stack) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Error: $error',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Check Firebase connection and CORS settings',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOSMDataSection(AsyncValue osmPOIsAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'OSM POIs',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.lightGrey,
          ),
        ),
        const SizedBox(height: 8),
        osmPOIsAsync.when(
          data: (osmPOIs) {
            final count = osmPOIs.length;
            final items = osmPOIs.map((p) => '${p.name} (${p.type}) - OSM ID: ${p.osmId}').toList();
            
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.public,
                      size: 16,
                      color: AppColors.lightGrey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Count: $count',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...items.take(3).map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: SelectableText(
                      '• $item',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  )),
                  if (items.length > 3)
                    Text(
                      '... and ${items.length - 3} more',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ] else ...[
                  Text(
                    'No OSM POIs found in current area',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            );
          },
          loading: () => Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.lightGrey),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Loading OSM POIs...',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
          error: (error, stack) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'OSM Error: $error',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Check Overpass API connection',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorsTab() {
    return const Center(
      child: Text(
        'Error tracking coming soon...',
        style: TextStyle(color: AppColors.lightGrey),
      ),
    );
  }

  IconData _getActionIcon(String action) {
    if (action.contains('Button Click')) return Icons.touch_app;
    if (action.contains('OSM')) return Icons.public; // Special icon for OSM actions
    if (action.contains('Navigation')) return Icons.navigation;
    if (action.contains('Function Call')) return Icons.functions;
    if (action.contains('API Call')) return Icons.api;
    if (action.contains('State Change')) return Icons.sync;
    return Icons.info;
  }

  Color _getActionColor(String action) {
    if (action.contains('Error')) return AppColors.dangerRed;
    if (action.contains('OSM')) return AppColors.lightGrey; // Highlight OSM actions
    if (action.contains('API Call')) return AppColors.urbanBlue;
    if (action.contains('Navigation')) return AppColors.mossGreen;
    if (action.contains('Button Click')) return AppColors.signalYellow;
    return AppColors.lightGrey;
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}s ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else {
      return '${difference.inHours}h ago';
    }
  }
}
