import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/locationiq_debug_provider.dart';
import '../constants/app_colors.dart';

class LocationIQDebugWindow extends ConsumerStatefulWidget {
  final VoidCallback onClose;

  const LocationIQDebugWindow({
    super.key,
    required this.onClose,
  });

  @override
  ConsumerState<LocationIQDebugWindow> createState() => _LocationIQDebugWindowState();
}

class _LocationIQDebugWindowState extends ConsumerState<LocationIQDebugWindow> {
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
              color: AppColors.signalYellow,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.search,
                  color: AppColors.urbanBlue,
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'LocationIQ API Debug Window',
                    style: TextStyle(
                      color: AppColors.urbanBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    ref.read(locationIQDebugProvider.notifier).clearHistory();
                    setState(() {});
                  },
                  icon: const Icon(
                    Icons.clear_all,
                    color: AppColors.urbanBlue,
                  ),
                  tooltip: 'Clear all logs',
                ),
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(
                    Icons.close,
                    color: AppColors.urbanBlue,
                  ),
                ),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: Consumer(
              builder: (context, ref, child) {
                final debugData = ref.watch(locationIQDebugProvider);
                
                if (debugData.searchHistory.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search,
                          size: 64,
                          color: AppColors.lightGrey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No LocationIQ API calls yet',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.lightGrey,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Use the Search feature to see debug info',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.lightGrey,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: debugData.searchHistory.length,
                  itemBuilder: (context, index) {
                    final log = debugData.searchHistory[index];
                    return _buildDebugLogItem(log);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugLogItem(LocationIQSearchRecord log) {
    final isError = !log.success;
    final isSuccess = log.success;
    
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
            fontWeight: FontWeight.w500,
            fontSize: 12,
          ),
        ),
        subtitle: Text(
          isError 
              ? 'Error: ${log.error}'
              : 'Query: "${log.query}" | Results: ${log.resultCount} | Status: ${log.success ? "Success" : "Failed"}',
          style: TextStyle(
            color: isError ? AppColors.dangerRed : AppColors.lightGrey,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // URL
                _buildInfoSection('URL', _buildLocationIQURL(log.query, log.searchLat, log.searchLng)),
                const SizedBox(height: 12),
                
                // Parameters
                _buildInfoSection('Parameters', _formatParameters(log.query, log.searchLat, log.searchLng)),
                const SizedBox(height: 12),
                
                // Query
                _buildInfoSection('Search Query', log.query),
                const SizedBox(height: 12),
                
                // Search Location
                if (log.searchLat != null && log.searchLng != null) ...[
                  _buildInfoSection('Search Center', 'Lat: ${log.searchLat!.toStringAsFixed(6)}, Lng: ${log.searchLng!.toStringAsFixed(6)}'),
                  const SizedBox(height: 12),
                ],
                
                // Results
                _buildInfoSection('Results Count', log.resultCount.toString()),
                const SizedBox(height: 12),
                
                // Response Body (if available)
                if (log.responseBody != null && log.responseBody!.isNotEmpty) ...[
                  _buildInfoSection('Response Body', log.responseBody!),
                  const SizedBox(height: 12),
                ],
                
                // Results Details (if available)
                if (log.results != null && log.results!.isNotEmpty) ...[
                  _buildInfoSection('Search Results', _formatResults(log.results!)),
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
                        label: const Text('Copy All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.signalYellow,
                          foregroundColor: AppColors.urbanBlue,
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
            fontWeight: FontWeight.w500,
            fontSize: 12,
            color: isError ? AppColors.dangerRed : AppColors.signalYellow,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isError ? AppColors.dangerRed.withValues(alpha: 0.1) : AppColors.signalYellow.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isError ? AppColors.dangerRed.withValues(alpha: 0.3) : AppColors.signalYellow.withValues(alpha: 0.3),
            ),
          ),
          child: SelectableText(
            content,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              fontFamily: 'monospace',
              color: isError ? AppColors.dangerRed : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  String _buildLocationIQURL(String query, double? searchLat, double? searchLng) {
    const baseUrl = 'https://us1.locationiq.com/v1/search.php';
    final params = <String, String>{
      'key': 'pk.1234567890abcdef', // This would be the actual API key
      'q': query,
      'format': 'json',
      'limit': '10',
      'addressdetails': '1',
      'namedetails': '1',
      'dedupe': '0',
    };
    
    final queryString = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    return '$baseUrl?$queryString';
  }

  String _formatParameters(String query, double? searchLat, double? searchLng) {
    final params = <String, String>{
      'key': 'pk.1234567890abcdef',
      'q': query,
      'format': 'json',
      'limit': '10',
      'addressdetails': '1',
      'namedetails': '1',
      'dedupe': '0',
    };
    
    return params.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('\n');
  }


  String _formatResults(List<dynamic> results) {
    final formattedResults = results.map((result) {
      return '• ${result.name} (${result.latLng.latitude.toStringAsFixed(6)}, ${result.latLng.longitude.toStringAsFixed(6)})';
    }).join('\n');
    
    return formattedResults;
  }

  void _copyToClipboard(LocationIQSearchRecord log) {
    final debugText = '''
LocationIQ API Debug Info
========================
Timestamp: ${log.timestamp.toIso8601String()}
URL: ${_buildLocationIQURL(log.query, log.searchLat, log.searchLng)}
Parameters: ${_formatParameters(log.query, log.searchLat, log.searchLng)}
Query: ${log.query}
Search Center: Lat: ${log.searchLat?.toStringAsFixed(6) ?? 'N/A'}, Lng: ${log.searchLng?.toStringAsFixed(6) ?? 'N/A'}
Results Count: ${log.resultCount}
Success: ${log.success}
Error: ${log.error ?? 'None'}
Response Body: ${log.responseBody ?? 'None'}
Results: ${log.results != null ? _formatResults(log.results!) : 'None'}
''';
    
    Clipboard.setData(ClipboardData(text: debugText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Debug info copied to clipboard', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
