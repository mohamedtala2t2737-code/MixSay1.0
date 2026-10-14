import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/widgets/app_list_tile.dart';
import 'package:social_chat/core/widgets/app_text_field.dart';
import 'package:social_chat/core/widgets/primary_button.dart';
import 'package:social_chat/features/reports/data/report_repository.dart';
import 'package:social_chat/features/reports/presentation/report_providers.dart';

/// Asks why a post or a story should be reported and writes the report.
Future<void> showReportSheet(
  BuildContext context, {
  required ReportTarget target,
  required String targetId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: _ReportSheet(target: target, targetId: targetId),
    ),
  );
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({required this.target, required this.targetId});

  final ReportTarget target;
  final String targetId;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  final _note = TextEditingController();
  ReportReason? _reason;
  bool _sending = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null || _sending) return;
    final s = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      await ref
          .read(reportRepositoryProvider)
          .submit(
            target: widget.target,
            targetId: widget.targetId,
            reason: reason,
            extraNote: _note.text,
          );
      if (mounted) Navigator.of(context).pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(s.reportSent)));
    } catch (error, stackTrace) {
      debugPrint('Unable to send the report: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _sending = false);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(s.actionFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.target == ReportTarget.story
                  ? s.reportStory
                  : s.reportPost,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.reportReason,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            for (final reason in ReportReason.values)
              AppListTile(
                title: s.reasonLabel(reason.value),
                onTap: () => setState(() => _reason = reason),
                trailing: _reason == reason
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: theme.colorScheme.primary,
                      )
                    : null,
              ),
            const SizedBox(height: 8),
            AppTextField(
              label: s.reportNoteHint,
              controller: _note,
              maxLines: 3,
              maxLength: ReportRepository.noteMaxLength,
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: s.sendReport,
              loading: _sending,
              // The rules reject a report without a reason, so the button stays
              // off until one is picked.
              onPressed: _reason == null ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}
