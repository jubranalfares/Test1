import 'package:flutter/material.dart';
import '../models/note.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'package:provider/provider.dart';

class NoteDetailScreen extends StatefulWidget {
  final Note? note;
  final VoidCallback? onSaved;

  const NoteDetailScreen({super.key, this.note, this.onSaved});

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late List<String> _tags;
  late String _selectedColor;
  late bool _isPinned;
  bool _isSaving = false;
  bool _hasChanges = false;

  static const List<Map<String, dynamic>> _colorOptions = [
    {'color': '#1A1A28', 'label': 'Standard'},
    {'color': '#1A1528', 'label': 'Lila'},
    {'color': '#12281A', 'label': 'Grün'},
    {'color': '#281A1A', 'label': 'Rot'},
    {'color': '#1A2228', 'label': 'Blau'},
    {'color': '#28221A', 'label': 'Orange'},
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController =
        TextEditingController(text: widget.note?.content ?? '');
    _tags = List.from(widget.note?.tags ?? []);
    _selectedColor = widget.note?.color ?? '#1A1A28';
    _isPinned = widget.note?.isPinned ?? false;

    _titleController.addListener(_onChanged);
    _contentController.addListener(_onChanged);
  }

  void _onChanged() {
    if (!_hasChanges) setState(() => _hasChanges = true);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (_titleController.text.isEmpty && _contentController.text.isEmpty) {
      Navigator.pop(context);
      return;
    }

    setState(() => _isSaving = true);
    final api = context.read<ApiService>();
    try {
      final noteData = {
        'title': _titleController.text.trim(),
        'content': _contentController.text.trim(),
        'tags': _tags,
        'isPinned': _isPinned,
        'color': _selectedColor,
      };

      if (widget.note == null) {
        await api.createNote(noteData);
      } else {
        await api.updateNote(widget.note!.id, noteData);
      }

      if (mounted) {
        widget.onSaved?.call();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _delete() async {
    if (widget.note == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notiz löschen'),
        content: const Text('Diese Notiz wird dauerhaft gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Löschen',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await context.read<ApiService>().deleteNote(widget.note!.id);
        widget.onSaved?.call();
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Löschen fehlgeschlagen: $e')),
          );
        }
      }
    }
  }

  void _addTag() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tag hinzufügen'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: 'Tag-Name eingeben'),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) {
              setState(() => _tags.add(v.trim()));
              _onChanged();
            }
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                setState(() => _tags.add(ctrl.text.trim()));
                _onChanged();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Hinzufügen'),
          ),
        ],
      ),
    );
  }

  Color _hexToColor(String hex) {
    final clean = hex.replaceAll('#', '');
    return Color(int.parse('FF$clean', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (_hasChanges) await _save();
        if (!mounted) return;
        nav.pop();
      },
      child: Scaffold(
        backgroundColor: _hexToColor(_selectedColor),
        appBar: AppBar(
          backgroundColor: _hexToColor(_selectedColor),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () async {
              final nav = Navigator.of(context);
              if (_hasChanges) await _save();
              if (!mounted) return;
              nav.pop();
            },
          ),
          actions: [
            IconButton(
              icon: Icon(
                _isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                color: _isPinned ? AppColors.primary : AppColors.textSecondary,
              ),
              onPressed: () => setState(() {
                _isPinned = !_isPinned;
                _onChanged();
              }),
              tooltip: _isPinned ? 'Lösen' : 'Anheften',
            ),
            if (widget.note != null)
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.error),
                onPressed: _delete,
                tooltip: 'Löschen',
              ),
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.check_rounded, color: AppColors.success),
                onPressed: _save,
                tooltip: 'Speichern',
              ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              TextField(
                controller: _titleController,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
                decoration: const InputDecoration(
                  hintText: 'Titel',
                  hintStyle: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                maxLines: 2,
              ),

              const SizedBox(height: 8),
              const Divider(color: AppColors.cardBorder),
              const SizedBox(height: 8),

              // Content
              TextField(
                controller: _contentController,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  height: 1.6,
                ),
                decoration: const InputDecoration(
                  hintText: 'Schreib los…',
                  hintStyle: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 16,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                maxLines: null,
                minLines: 10,
                keyboardType: TextInputType.multiline,
              ),

              const SizedBox(height: 24),

              // Tags section
              const Text(
                'TAGS', // gleiches Wort im Deutschen
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ..._tags.map(
                    (tag) => Chip(
                      label: Text(tag),
                      backgroundColor: AppColors.primary.withValues(alpha:0.15),
                      labelStyle: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                      ),
                      side: BorderSide(
                          color: AppColors.primary.withValues(alpha:0.3)),
                      deleteIcon: const Icon(Icons.close_rounded, size: 14),
                      deleteIconColor: AppColors.primary,
                      onDeleted: () {
                        setState(() => _tags.remove(tag));
                        _onChanged();
                      },
                    ),
                  ),
                  ActionChip(
                    label: const Text('+ Tag hinzufügen'),
                    backgroundColor: AppColors.surface,
                    labelStyle: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    side: const BorderSide(color: AppColors.cardBorder),
                    onPressed: _addTag,
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Color picker
              const Text(
                'FARBE',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                children: _colorOptions.map((opt) {
                  final color = _hexToColor(opt['color'] as String);
                  final isSelected = _selectedColor == opt['color'];
                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedColor = opt['color'] as String);
                      _onChanged();
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.cardBorder,
                          width: isSelected ? 2.5 : 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha:0.4),
                                  blurRadius: 8,
                                )
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check_rounded,
                              color: AppColors.primary, size: 16)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
