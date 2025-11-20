import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/community_warning.dart';
import '../../config/poi_type_config.dart';
import '../../constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/firebase_service.dart';
import '../../utils/app_logger.dart';
import '../common_dialog.dart';

/// Warning detail dialog widget
///
/// Displays detailed information about a community warning/hazard
/// Includes voting, verification, and status management features
class WarningDetailDialog extends ConsumerStatefulWidget {
  final CommunityWarning warning;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool compact;

  const WarningDetailDialog({
    super.key,
    required this.warning,
    required this.onEdit,
    required this.onDelete,
    this.compact = false,
  });

  @override
  ConsumerState<WarningDetailDialog> createState() => _WarningDetailDialogState();

  /// Show warning details dialog
  ///
  /// Convenience method to show the dialog
  ///
  /// Example:
  /// ```dart
  /// WarningDetailDialog.show(
  ///   context: context,
  ///   warning: warning,
  ///   onEdit: () { /* navigate to edit screen */ },
  ///   onDelete: () async { /* delete warning */ },
  ///   compact: true, // For 3D map
  /// );
  /// ```
  static Future<void> show({
    required BuildContext context,
    required CommunityWarning warning,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
    bool compact = false,
  }) {
    return showDialog(
      context: context,
      barrierColor: CommonDialog.barrierColor,
      builder: (context) => WarningDetailDialog(
        warning: warning,
        onEdit: onEdit,
        onDelete: onDelete,
        compact: compact,
      ),
    );
  }
}

class _WarningDetailDialogState extends ConsumerState<WarningDetailDialog> {
  final FirebaseService _firebaseService = FirebaseService();
  late CommunityWarning _warning;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _warning = widget.warning;
  }

  @override
  Widget build(BuildContext context) {
    // Check if user is logged in
    final authUser = ref.watch(authStateProvider).value;
    final userId = authUser?.uid;
    final isReporter = userId != null && userId == _warning.reportedBy;

    // Get warning type emoji and label
    final typeEmoji = POITypeConfig.getWarningEmoji(_warning.type);
    final typeLabel = POITypeConfig.getWarningLabel(_warning.type);

    // Get severity color
    final severityColors = {
      'low': AppColors.successGreen,
      'medium': Colors.yellow[700],
      'high': Colors.orange[700],
    };
    final severityColor = severityColors[_warning.severity] ?? Colors.yellow[700];

    // Check user's vote
    final userVote = userId != null ? _warning.userVotes[userId] : null;
    final hasVerified = userId != null && _warning.verifiedBy.contains(userId);

    // Use CommonDialog styling for consistency
    return AlertDialog(
      backgroundColor: Colors.white.withValues(alpha: CommonDialog.backgroundOpacity),
      titlePadding: CommonDialog.titlePadding,
      contentPadding: CommonDialog.contentPadding,
      actionsPadding: CommonDialog.actionsPadding,
      title: Text(
        _warning.title,
        style: const TextStyle(fontSize: CommonDialog.titleFontSize, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type with icon
            Row(
              children: [
                const Text(
                  'Type: ',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: CommonDialog.bodyFontSize,
                  ),
                ),
                Text(
                  typeEmoji,
                  style: const TextStyle(fontSize: CommonDialog.titleFontSize),
                ),
                const SizedBox(width: 4),
                Text(
                  typeLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: CommonDialog.bodyFontSize,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Severity with colored badge
            Row(
              children: [
                const Text(
                  'Severity: ',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: CommonDialog.bodyFontSize,
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.compact ? 8 : 12,
                    vertical: 0,
                  ),
                  decoration: BoxDecoration(
                    color: severityColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _warning.severity.toUpperCase(),
                    style: TextStyle(
                      color: AppColors.surface,
                      fontWeight: FontWeight.bold,
                      fontSize: widget.compact ? 12 : 14,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),

            // Coordinates
            CommonDialog.buildCaptionText(
              'Coordinates: ${_warning.latitude.toStringAsFixed(6)}, ${_warning.longitude.toStringAsFixed(6)}',
            ),

            // Description
            if (_warning.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Description:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: CommonDialog.bodyFontSize,
                ),
              ),
              Text(
                _warning.description,
                style: const TextStyle(fontSize: CommonDialog.bodyFontSize),
              ),
            ],

            const SizedBox(height: 12),
            const Divider(),

            // Status Badge
            Row(
              children: [
                const Text(
                  'Status: ',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: CommonDialog.bodyFontSize,
                  ),
                ),
                _buildStatusBadge(_warning.status),
              ],
            ),

            const SizedBox(height: 8),

            // Time since report
            CommonDialog.buildCaptionText('Reported ${_warning.timeSinceReport}'),

            const SizedBox(height: 12),

            // Voting Section
            if (userId != null) ...[
              const Text(
                'Community Feedback:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: CommonDialog.bodyFontSize,
                ),
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  // Upvote button
                  _buildVoteButton(
                    icon: Icons.thumb_up,
                    count: _warning.upvotes,
                    isActive: userVote == 'up',
                    onPressed: _isProcessing || userId == null
                        ? null
                        : () => _handleUpvote(userId),
                  ),
                  const SizedBox(width: 12),

                  // Downvote button
                  _buildVoteButton(
                    icon: Icons.thumb_down,
                    count: _warning.downvotes,
                    isActive: userVote == 'down',
                    onPressed: _isProcessing || userId == null
                        ? null
                        : () => _handleDownvote(userId),
                  ),
                  const SizedBox(width: 12),

                  // Vote score
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _warning.voteScore >= 0
                          ? AppColors.successGreen.withValues(alpha: 0.2)
                          : Colors.red.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Score: ${_warning.voteScore >= 0 ? '+' : ''}${_warning.voteScore}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _warning.voteScore >= 0
                            ? AppColors.successGreen
                            : Colors.red,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Verification Section
              Row(
                children: [
                  if (_warning.isVerified)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.successGreen.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified, size: 16, color: AppColors.successGreen),
                          SizedBox(width: 4),
                          Text(
                            'Verified',
                            style: TextStyle(
                              color: AppColors.successGreen,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (!_warning.isVerified)
                    Text(
                      'Verifications: ${_warning.verifiedBy.length}/3',
                      style: const TextStyle(
                        fontSize: CommonDialog.bodyFontSize,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  const SizedBox(width: 8),
                  if (!hasVerified && userId != null)
                    ElevatedButton.icon(
                      onPressed: _isProcessing ? null : () => _handleVerify(userId),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Verify'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cyclewayPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Mark as Resolved button (only for reporter and if active)
            if (isReporter && _warning.status == 'active' && !_isProcessing)
              CommonDialog.buildBorderedTextButton(
                label: 'MARK AS RESOLVED',
                textColor: AppColors.successGreen,
                borderColor: AppColors.successGreen.withValues(alpha: 0.5),
                onPressed: () => _handleResolve(userId!),
              ),
            if (isReporter && _warning.status == 'active')
              const SizedBox(height: 8),
            // Edit button (only show if user is logged in)
            if (authUser != null)
              CommonDialog.buildBorderedTextButton(
                label: 'EDIT',
                textColor: Colors.blue,
                onPressed: () {
                  Navigator.pop(context);
                  widget.onEdit();
                },
              ),
            if (authUser != null)
              const SizedBox(height: 8),
            // Delete button (only show if user is logged in)
            if (authUser != null)
              CommonDialog.buildBorderedTextButton(
                label: 'DELETE',
                textColor: Colors.red,
                borderColor: Colors.red.withValues(alpha: 0.5),
                onPressed: () {
                  Navigator.pop(context);
                  widget.onDelete();
                },
              ),
            if (authUser != null)
              const SizedBox(height: 8),
            // Close button
            CommonDialog.buildBorderedTextButton(
              label: 'CLOSE',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ],
    );
  }

  /// Build status badge widget
  Widget _buildStatusBadge(String status) {
    final statusConfig = {
      'active': (color: AppColors.successGreen, label: 'Active'),
      'resolved': (color: Colors.blue, label: 'Resolved'),
      'disputed': (color: Colors.orange, label: 'Disputed'),
      'expired': (color: Colors.grey, label: 'Expired'),
    };

    final config = statusConfig[status] ?? (color: Colors.grey, label: 'Unknown');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: config.color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: config.color, width: 1),
      ),
      child: Text(
        config.label,
        style: TextStyle(
          color: config.color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  /// Build vote button
  Widget _buildVoteButton({
    required IconData icon,
    required int count,
    required bool isActive,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive
            ? AppColors.cyclewayPurple
            : Colors.grey[300],
        foregroundColor: isActive ? Colors.white : Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 4),
          Text('$count', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  /// Handle upvote
  Future<void> _handleUpvote(String userId) async {
    if (_warning.id == null) return;

    setState(() => _isProcessing = true);

    try {
      final success = await _firebaseService.upvoteWarning(_warning.id!, userId);
      if (success && mounted) {
        // Update local state optimistically
        setState(() {
          final currentVote = _warning.userVotes[userId];
          int newUpvotes = _warning.upvotes;
          int newDownvotes = _warning.downvotes;
          final newUserVotes = Map<String, String>.from(_warning.userVotes);

          if (currentVote == 'down') {
            newDownvotes = (newDownvotes - 1).clamp(0, double.infinity).toInt();
          }
          newUpvotes++;
          newUserVotes[userId] = 'up';

          _warning = _warning.copyWith(
            upvotes: newUpvotes,
            downvotes: newDownvotes,
            userVotes: newUserVotes,
          );
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Upvoted successfully')),
          );
        }
      }
    } catch (e) {
      AppLogger.error('Failed to upvote', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upvote: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  /// Handle downvote
  Future<void> _handleDownvote(String userId) async {
    if (_warning.id == null) return;

    setState(() => _isProcessing = true);

    try {
      final success = await _firebaseService.downvoteWarning(_warning.id!, userId);
      if (success && mounted) {
        // Update local state optimistically
        setState(() {
          final currentVote = _warning.userVotes[userId];
          int newUpvotes = _warning.upvotes;
          int newDownvotes = _warning.downvotes;
          final newUserVotes = Map<String, String>.from(_warning.userVotes);

          if (currentVote == 'up') {
            newUpvotes = (newUpvotes - 1).clamp(0, double.infinity).toInt();
          }
          newDownvotes++;
          newUserVotes[userId] = 'down';

          _warning = _warning.copyWith(
            upvotes: newUpvotes,
            downvotes: newDownvotes,
            userVotes: newUserVotes,
          );
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Downvoted successfully')),
          );
        }
      }
    } catch (e) {
      AppLogger.error('Failed to downvote', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to downvote: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  /// Handle verify
  Future<void> _handleVerify(String userId) async {
    if (_warning.id == null) return;

    setState(() => _isProcessing = true);

    try {
      final success = await _firebaseService.verifyWarning(_warning.id!, userId);
      if (success && mounted) {
        // Update local state optimistically
        setState(() {
          final newVerifiedBy = List<String>.from(_warning.verifiedBy)..add(userId);
          _warning = _warning.copyWith(verifiedBy: newVerifiedBy);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _warning.isVerified
                    ? 'Verified! This hazard is now community-verified.'
                    : 'Verification added (${_warning.verifiedBy.length}/3)',
              ),
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.error('Failed to verify', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to verify: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  /// Handle mark as resolved
  Future<void> _handleResolve(String userId) async {
    if (_warning.id == null) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as Resolved'),
        content: const Text('Are you sure this hazard has been resolved?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('CONFIRM'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);

    try {
      await _firebaseService.resolveWarning(_warning.id!, userId);

      if (mounted) {
        // Update local state
        setState(() {
          _warning = _warning.copyWith(status: 'resolved');
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hazard marked as resolved')),
        );
      }
    } catch (e) {
      AppLogger.error('Failed to resolve warning', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to resolve: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }
}
