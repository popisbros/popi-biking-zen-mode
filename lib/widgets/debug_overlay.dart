import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/debug_provider.dart';

class DebugOverlay extends ConsumerStatefulWidget {
  const DebugOverlay({super.key});

  @override
  ConsumerState<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends ConsumerState<DebugOverlay> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final debugState = ref.watch(debugProvider);

    if (!debugState.isVisible) {
      return const SizedBox.shrink();
    }

    // Auto-scroll to bottom when new logs arrive
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.4, // 40% of screen
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.9),
          border: Border(
            top: BorderSide(color: Colors.grey.shade700, width: 1),
          ),
        ),
        child: Column(
          children: [
            // Header with title and clear button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade700, width: 1),
                ),
              ),
              child: Row(
                children: [
                  const Text(
                    '🐛 Debug Console',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${debugState.logs.length} logs',
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.clear_all, color: Colors.white, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      ref.read(debugProvider.notifier).clearLogs();
                    },
                    tooltip: 'Clear logs',
                  ),
                ],
              ),
            ),

            // Log list
            Expanded(
              child: debugState.logs.isEmpty
                  ? Center(
                      child: Text(
                        'No logs yet\nLogs will appear here in real-time',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      reverse: true, // Start from bottom
                      padding: const EdgeInsets.all(8),
                      itemCount: debugState.logs.length,
                      itemBuilder: (context, index) {
                        final log = debugState.logs[index];
                        return _buildLogEntry(log);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogEntry(LogEntry log) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp
          Text(
            '[${log.timestamp}]',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 6),

          // Icon
          Text(
            log.icon,
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(width: 4),

          // Tag
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: log.color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              log.tag,
              style: TextStyle(
                color: log.color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Message and data
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                if (log.data != null && log.data!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    log.data!.entries.map((e) => '${e.key}: ${e.value}').join(', '),
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
