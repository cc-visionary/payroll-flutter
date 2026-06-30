import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// Optional image attachment picker for memo forms (NTE/NOD).
///
/// The image is generation-time only — the parent holds [bytes] in the
/// template inputs and never persists them. This widget is "controlled":
/// [bytes] and [caption] come from the parent; picking/removing/caption edits
/// are reported via callbacks.
class ImageAttachmentField extends StatefulWidget {
  final Uint8List? bytes;
  final String? caption;
  final void Function(Uint8List bytes, String fileName) onPicked;
  final VoidCallback onRemoved;
  final ValueChanged<String> onCaptionChanged;

  const ImageAttachmentField({
    super.key,
    required this.bytes,
    required this.caption,
    required this.onPicked,
    required this.onRemoved,
    required this.onCaptionChanged,
  });

  @override
  State<ImageAttachmentField> createState() => _ImageAttachmentFieldState();
}

class _ImageAttachmentFieldState extends State<ImageAttachmentField> {
  String? _fileName;
  late final TextEditingController _captionController;

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(text: widget.caption ?? '');
  }

  @override
  void didUpdateWidget(ImageAttachmentField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only push parent-driven caption changes into the field. The
    // `!= _captionController.text` guard prevents echoing the user's own
    // keystrokes back (which would reset the cursor position).
    final incoming = widget.caption ?? '';
    if (incoming != _captionController.text) {
      _captionController.text = incoming;
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) return;
    setState(() => _fileName = file.name);
    widget.onPicked(bytes, file.name);
  }

  void _remove() {
    setState(() => _fileName = null);
    widget.onRemoved();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = widget.bytes;

    if (bytes == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _pick,
          icon: const Icon(Icons.image_outlined, size: 18),
          label: const Text('Add image'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(
                bytes,
                width: 96,
                height: 96,
                fit: BoxFit.cover,
                // Defensive: a non-decodable byte list shouldn't crash the form.
                errorBuilder: (context2, err, stack) => Container(
                  width: 96,
                  height: 96,
                  alignment: Alignment.center,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _fileName ?? 'Attached image',
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              onPressed: _remove,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Remove'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _captionController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            labelText: 'Caption (optional)',
            hintText: 'e.g. CCTV still, 2026-06-20 3:14 PM',
          ),
          onChanged: widget.onCaptionChanged,
        ),
      ],
    );
  }
}
