import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

/// A Quill rich-text editor restricted to bold/italic/underline/bullet/
/// numbered/nested. Returns the underlying Delta on every change.
class QuillField extends StatefulWidget {
  final Delta initial;
  final ValueChanged<Delta> onChanged;
  const QuillField({super.key, required this.initial, required this.onChanged});

  @override
  State<QuillField> createState() => _QuillFieldState();
}

class _QuillFieldState extends State<QuillField> {
  late final QuillController _controller;

  @override
  void initState() {
    super.initState();
    _controller = QuillController(
      document: Document.fromDelta(widget.initial),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _controller.addListener(() {
      widget.onChanged(_controller.document.toDelta());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          QuillSimpleToolbar(
            controller: _controller,
            config: const QuillSimpleToolbarConfig(
              showBoldButton: true,
              showItalicButton: true,
              showUnderLineButton: true,
              showListBullets: true,
              showListNumbers: true,
              showIndent: true,
              showLink: false,
              showSearchButton: false,
              showFontFamily: false,
              showFontSize: false,
              showColorButton: false,
              showBackgroundColorButton: false,
              showHeaderStyle: false,
              showStrikeThrough: false,
              showInlineCode: false,
              showCodeBlock: false,
              showQuote: false,
              showAlignmentButtons: false,
              showDirection: false,
              showClearFormat: false,
              showSubscript: false,
              showSuperscript: false,
              showUndo: false,
              showRedo: false,
              showDividers: false,
              showListCheck: false,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 120, maxHeight: 240),
            child: QuillEditor.basic(
              controller: _controller,
              config: const QuillEditorConfig(
                padding: EdgeInsets.all(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
