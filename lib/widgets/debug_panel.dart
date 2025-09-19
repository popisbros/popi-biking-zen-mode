import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../providers/community_provider.dart';
import '../services/debug_service.dart';

class DebugPanel extends ConsumerStatefulWidget {
  const DebugPanel({super.key});

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

    return Container(
      height: MediaQuery.of(context).size.height * 0.4,
      width: MediaQuery.of(context).size.width,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, 2),
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
                IconButton(
                  onPressed: () => Navigator.pop(context),
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
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildTabContent(_selectedTab, warningsAsync, poisAsync),
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

  Widget _buildTabContent(int tabIndex, AsyncValue warningsAsync, AsyncValue poisAsync) {
    switch (tabIndex) {
      case 0:
        return _buildActionsTab();
      case 1:
        return _buildDataTab(warningsAsync, poisAsync);
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
                itemCount: actions.length,
                itemBuilder: (context, index) {
                  final action = actions[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
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
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            SelectableText(
                              _formatTime(action.timestamp),
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        if (action.screen != null) ...[
                          const SizedBox(height: 4),
                          SelectableText(
                            'Screen: ${action.screen}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                        if (action.parameters != null && action.parameters!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          SelectableText(
                            'Params: ${action.parameters}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                        if (action.result != null) ...[
                          const SizedBox(height: 4),
                          SelectableText(
                            'Result: ${action.result}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.green,
                            ),
                          ),
                        ],
                        if (action.error != null) ...[
                          const SizedBox(height: 4),
                          SelectableText(
                            'Error: ${action.error}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.red,
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

  Widget _buildDataTab(AsyncValue warningsAsync, AsyncValue poisAsync) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Force Reload Buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
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
              ],
            ),
          ),
          const SizedBox(height: 8),
            // Force create collection button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  _debugService.logButtonClick('Force Create POIs Collection', screen: 'DebugPanel');
                  try {
                    final firebaseService = ref.read(firebaseServiceProvider);
                    await firebaseService.forceCreatePOIsCollection();
                    _debugService.logAction(
                      action: 'Firebase: Successfully created pois collection',
                      screen: 'DebugPanel',
                      result: 'Collection created',
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('POIs collection created successfully!'),
                          backgroundColor: AppColors.mossGreen,
                        ),
                      );
                    }
                  } catch (e) {
                    _debugService.logAction(
                      action: 'Firebase: Failed to create pois collection',
                      screen: 'DebugPanel',
                      error: e.toString(),
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to create collection: $e'),
                          backgroundColor: AppColors.dangerRed,
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.create_new_folder, size: 16),
                label: const Text('Force Create POIs Collection'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.urbanBlue,
                  foregroundColor: AppColors.surface,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          
          const SizedBox(height: 8),
          
          // Warnings Section
          _buildDataSection<dynamic>(
            'Community Warnings',
            warningsAsync as AsyncValue<List<dynamic>>,
            (warnings) => warnings.length,
            (warnings) => warnings.map((w) => '${w.title} (${w.severity})').toList(),
          ),
          
          const SizedBox(height: 16),
          
          // POIs Section
          _buildDataSection<dynamic>(
            'Cycling POIs',
            poisAsync as AsyncValue<List<dynamic>>,
            (pois) => pois.length,
            (pois) => pois.map((p) => '${p.name} (${p.type})').toList(),
          ),
        ],
      ),
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.urbanBlue,
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
                  Text('Count: $count'),
                  if (items.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...items.take(5).map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• $item',
                        style: const TextStyle(fontSize: 12),
                      ),
                    )),
                    if (items.length > 5)
                      Text(
                        '... and ${items.length - 5} more',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.lightGrey,
                        ),
                      ),
                  ],
                ],
              );
            },
            loading: () => const Text('Loading...'),
            error: (error, stack) => Text(
              'Error: $error',
              style: const TextStyle(color: AppColors.dangerRed),
            ),
          ),
        ],
      ),
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
    if (action.contains('Navigation')) return Icons.navigation;
    if (action.contains('Function Call')) return Icons.functions;
    if (action.contains('API Call')) return Icons.api;
    if (action.contains('State Change')) return Icons.sync;
    return Icons.info;
  }

  Color _getActionColor(String action) {
    if (action.contains('Error')) return AppColors.dangerRed;
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
