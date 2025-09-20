import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/osm_debug_service.dart';
import '../theme/app_colors.dart';

class OSMDebugWindow extends StatefulWidget {
  final VoidCallback onClose;

  const OSMDebugWindow({
    super.key,
    required this.onClose,
  });

  @override
  State<OSMDebugWindow> createState() => _OSMDebugWindowState();
}

class _OSMDebugWindowState extends State<OSMDebugWindow> {
  final OSMDebugService _debugService = OSMDebugService();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: MediaQuery.of(context).size.width,
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.urbanBlue,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.bug_report,
                  color: AppColors.surface,
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'OSM API Debug Window',
                    style: TextStyle(
                      color: AppColors.surface,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    _debugService.clearDebugLogs();
                    setState(() {});
                  },
                  icon: const Icon(
                    Icons.clear_all,
                    color: AppColors.surface,
                  ),
                  tooltip: 'Clear all logs',
                ),
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(
                    Icons.close,
                    color: AppColors.surface,
                  ),
                ),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: _debugService.debugLogs.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.api,
                          size: 64,
                          color: AppColors.lightGrey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No OSM API calls yet',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.lightGrey,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Click "Reload OSM POIs" to see debug info',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.lightGrey,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _debugService.debugLogs.length,
                    itemBuilder: (context, index) {
                      final log = _debugService.debugLogs[index];
                      return _buildDebugLogItem(log);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugLogItem(OSMDebugInfo log) {
    final isError = log.error != null;
    final isSuccess = log.responseStatusCode == 200;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ExpansionTile(
        leading: Icon(
          isError ? Icons.error : (isSuccess ? Icons.check_circle : Icons.info),
          color: isError ? AppColors.dangerRed : (isSuccess ? AppColors.mossGreen : AppColors.signalYellow),
        ),
        title: Text(
          '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          isError 
              ? 'Error: ${log.error}'
              : 'Status: ${log.responseStatusCode ?? 'Pending'} | Duration: ${log.duration?.inMilliseconds ?? 0}ms',
          style: TextStyle(
            color: isError ? AppColors.dangerRed : AppColors.lightGrey,
            fontSize: 12,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // URL
                _buildInfoSection('URL', log.url),
                const SizedBox(height: 12),
                
                // Parameters
                _buildInfoSection('Parameters', _formatParameters(log.parameters)),
                const SizedBox(height: 12),
                
                // Query
                _buildInfoSection('Overpass Query', log.query),
                const SizedBox(height: 12),
                
                // Response (if available)
                if (log.responseBody != null) ...[
                  _buildInfoSection('Response Body', _formatResponse(log.responseBody!)),
                  const SizedBox(height: 12),
                ],
                
                // Error (if available)
                if (log.error != null) ...[
                  _buildInfoSection('Error', log.error!, isError: true),
                  const SizedBox(height: 12),
                ],
                
                // Copy button
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _copyToClipboard(log),
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copy All'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.urbanBlue,
                          foregroundColor: AppColors.surface,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(String title, String content, {bool isError = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: isError ? AppColors.dangerRed : AppColors.urbanBlue,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isError ? AppColors.dangerRed.withValues(alpha: 0.1) : AppColors.lightGrey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isError ? AppColors.dangerRed.withValues(alpha: 0.3) : AppColors.lightGrey.withValues(alpha: 0.3),
            ),
          ),
          child: SelectableText(
            content,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: isError ? AppColors.dangerRed : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  String _formatParameters(Map<String, dynamic> parameters) {
    return parameters.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('\n');
  }

  String _formatResponse(String responseBody) {
    try {
      final json = jsonDecode(responseBody);
      return const JsonEncoder.withIndent('  ').convert(json);
    } catch (e) {
      return responseBody;
    }
  }

  void _copyToClipboard(OSMDebugInfo log) {
    final debugText = '''
OSM API Debug Info
==================
Timestamp: ${log.timestamp.toIso8601String()}
URL: ${log.url}
Parameters: ${_formatParameters(log.parameters)}
Query: ${log.query}
Status Code: ${log.responseStatusCode}
Duration: ${log.duration?.inMilliseconds}ms
Error: ${log.error ?? 'None'}
Response: ${log.responseBody ?? 'None'}
''';
    
    Clipboard.setData(ClipboardData(text: debugText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Debug info copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
