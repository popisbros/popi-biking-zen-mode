import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/routing_provider.dart';
import '../../providers/routing_provider_notifier.dart';
import '../common_dialog.dart';

/// Dialog to select routing provider before calculating routes
class RoutingProviderDialog extends ConsumerStatefulWidget {
  const RoutingProviderDialog({super.key});

  @override
  ConsumerState<RoutingProviderDialog> createState() => _RoutingProviderDialogState();
}

class _RoutingProviderDialogState extends ConsumerState<RoutingProviderDialog> {
  RoutingProvider? _selectedProvider;

  @override
  void initState() {
    super.initState();
    // Initialize with current provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectedProvider = ref.read(routingProviderProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentProvider = ref.watch(routingProviderProvider);
    _selectedProvider ??= currentProvider;

    return AlertDialog(
      backgroundColor: Colors.white.withValues(alpha: CommonDialog.backgroundOpacity),
      titlePadding: CommonDialog.titlePadding,
      contentPadding: CommonDialog.contentPadding,
      actionsPadding: CommonDialog.actionsPadding,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'SELECT ROUTING PROVIDER',
            style: TextStyle(
              fontSize: CommonDialog.titleFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose which routing service to use for calculating routes',
            style: TextStyle(
              fontSize: CommonDialog.smallFontSize,
              color: Colors.grey[400],
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Provider options
            ...RoutingProvider.values.map((provider) {
              return _buildProviderOption(provider);
            }),
            const SizedBox(height: 16),
            // Info text
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.blue.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 20, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your selection will be saved for future route calculations',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[300],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CommonDialog.buildBorderedTextButton(
              label: 'CALCULATE ROUTES',
              icon: const Icon(Icons.route, size: 18),
              onPressed: () {
                if (_selectedProvider != null) {
                  // Save selection
                  ref.read(routingProviderProvider.notifier).setProvider(_selectedProvider!);
                  // Return selected provider
                  Navigator.pop(context, _selectedProvider);
                }
              },
            ),
            const SizedBox(height: 8),
            CommonDialog.buildBorderedTextButton(
              label: 'CANCEL',
              textColor: Colors.grey,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProviderOption(RoutingProvider provider) {
    final isSelected = _selectedProvider == provider;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.blue.withValues(alpha: 0.2)
            : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected
              ? Colors.blue.withValues(alpha: 0.5)
              : Colors.grey.withValues(alpha: 0.3),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedProvider = provider;
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Radio button
              Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: isSelected ? Colors.blue : Colors.grey,
                size: 24,
              ),
              const SizedBox(width: 12),
              // Provider icon
              Text(
                provider.icon,
                style: const TextStyle(fontSize: 24),
              ),
              const SizedBox(width: 12),
              // Provider info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.displayName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.blue : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      provider.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
