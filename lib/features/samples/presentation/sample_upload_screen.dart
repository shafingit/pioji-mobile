import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/application/invalidation.dart';
import '../../../core/design/app_icons.dart';
import '../../../core/design/context_ext.dart';
import '../../../core/design/typography.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/fields.dart';
import '../../../core/widgets/scaffolds.dart';
import '../../masters/data/form_options.dart';
import '../data/samples_repository.dart';

/// The website's sheet uploads: many samples at once (`bulk-upload`) and
/// marking groups / tasting / direct allocation (`manual-marking`), each with
/// a template to download.
class SampleUploadScreen extends ConsumerStatefulWidget {
  const SampleUploadScreen({super.key});

  @override
  ConsumerState<SampleUploadScreen> createState() => _SampleUploadScreenState();
}

class _SampleUploadScreenState extends ConsumerState<SampleUploadScreen> {
  String? _format;
  PlatformFile? _samplesFile;
  PlatformFile? _markingFile;

  /// Which action is running: 'template', 'samples' or 'marking'.
  String? _busy;
  String? _samplesResult;
  String? _markingResult;

  Future<void> _run(String what, Future<void> Function() action) async {
    if (_busy != null) return;
    setState(() => _busy = what);
    try {
      await action();
    } on AppFailure catch (f) {
      if (mounted) context.toast(f.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<PlatformFile?> _pick() => FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['xlsx', 'xls', 'csv']);

  Future<void> _template({String? format}) => _run('template', () async {
        final path = await ref.read(samplesRepositoryProvider).template(format: format);
        await SharePlus.instance.share(ShareParams(files: [XFile(path, mimeType: 'text/csv')]));
      });

  Future<void> _uploadSamples(String format) => _run('samples', () async {
        final r = await ref.read(samplesRepositoryProvider).bulkUpload(_samplesFile!.path!, format);
        ref.invalidate(samplesListProvider);
        refreshSummaries(ref);
        if (!mounted) return;
        setState(() {
          _samplesFile = null;
          _samplesResult = [
            '${r.created} of ${r.processed} samples created.',
            ...r.errors.take(5),
            if (r.errors.length > 5) '…and ${r.errors.length - 5} more problems.',
          ].join('\n');
        });
      });

  Future<void> _uploadMarking() => _run('marking', () async {
        final message = await ref.read(samplesRepositoryProvider).manualMarking(_markingFile!.path!);
        ref.invalidate(samplesListProvider);
        if (!mounted) return;
        setState(() {
          _markingFile = null;
          _markingResult = message ?? 'Marking applied.';
        });
      });

  Widget _fileRow(PlatformFile? file, ValueChanged<PlatformFile> onPicked) => ValueRow(
        label: 'File',
        value: file?.name,
        placeholder: 'Choose',
        onTap: _busy != null
            ? null
            : () async {
                final f = await _pick();
                if (f != null && f.path != null) onPicked(f);
              },
      );

  Widget _result(String? text) => text == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
          child: Text(text, style: AppText.callout.copyWith(color: context.colors.textSecondary)),
        );

  /// The chosen format's columns, as `form-options` lists them.
  String _columns(List<Choice> formats, String? format) {
    final cols = formats.where((f) => f.value == format).firstOrNull?.extra['columns'];
    final list = cols is List ? cols.join(', ') : null;
    return ['Fill the template and upload it as CSV or Excel.', if (list != null) 'Columns: $list.'].join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final options = watchFormOptions(ref);
    final formats = options['sample_upload_formats'];
    final format = _format ?? options.initial('sample_upload_formats');
    final c = context.colors;
    return DetailScaffold(
      title: 'Upload sheets',
      children: [
        GroupedSection(
          label: 'Bulk upload samples',
          footer: Text(formats.isEmpty
              ? "The server doesn't list the upload formats yet, so bulk upload is off for now."
              : _columns(formats, format)),
          children: [
            if (formats.isNotEmpty) OptionRow(label: 'Format', list: 'sample_upload_formats', value: format, onChanged: (v) => setState(() => _format = v)),
            AppListRow(
              title: 'Download template',
              titleStyle: AppText.body.copyWith(color: formats.isEmpty ? c.textTertiary : c.accent),
              leading: AppIcon(AppIcons.document, size: 20, color: formats.isEmpty ? c.textTertiary : c.accent),
              trailing: _busy == 'template' ? const AppSpinner(size: 16) : null,
              onTap: formats.isEmpty || _busy != null ? null : () => _template(format: format),
            ),
            if (formats.isNotEmpty) _fileRow(_samplesFile, (f) => setState(() => _samplesFile = f)),
            _result(_samplesResult),
          ],
        ),
        if (formats.isNotEmpty)
          PrimaryButton(
            label: 'Upload samples',
            loading: _busy == 'samples',
            onPressed: _samplesFile == null || format == null || _busy != null ? null : () => _uploadSamples(format),
          ),
        GroupedSection(
          label: 'Manual marking',
          footer: const Text('Sets marking group, mark for tasting and direct allocation for samples and offers. Fill the template and upload it as CSV or Excel.'),
          children: [
            AppListRow(
              title: 'Download template',
              titleStyle: AppText.body.copyWith(color: c.accent),
              leading: AppIcon(AppIcons.document, size: 20, color: c.accent),
              trailing: _busy == 'template' ? const AppSpinner(size: 16) : null,
              onTap: _busy != null ? null : () => _template(),
            ),
            _fileRow(_markingFile, (f) => setState(() => _markingFile = f)),
            _result(_markingResult),
          ],
        ),
        PrimaryButton(
          label: 'Apply marking',
          loading: _busy == 'marking',
          onPressed: _markingFile == null || _busy != null ? null : _uploadMarking,
        ),
      ],
    );
  }
}
