import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../models/note.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'note_detail_screen.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<Note> _notes = [];
  List<Note> _filteredNotes = [];
  bool _isLoading = false;
  String _searchQuery = '';
  String? _selectedTag;
  Set<String> _allTags = {};

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    setState(() => _isLoading = true);
    try {
      final api = context.read<ApiService>();
      final data = await api.getNotes(
        query: _searchQuery.isNotEmpty ? _searchQuery : null,
        tag: _selectedTag,
      );
      if (mounted) {
        setState(() {
          _notes = data.map((d) => Note.fromJson(d)).toList();
          _allTags = _notes.expand((n) => n.tags).toSet();
          _applyFilters();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Notizen konnten nicht geladen werden: $e')),
        );
      }
    }
  }

  void _applyFilters() {
    var filtered = List<Note>.from(_notes);

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((n) {
        return n.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            n.content.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }

    if (_selectedTag != null) {
      filtered = filtered.where((n) => n.tags.contains(_selectedTag)).toList();
    }

    // Pinned first
    filtered.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });

    setState(() => _filteredNotes = filtered);
  }

  void _openNote(Note? note) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteDetailScreen(
          note: note,
          onSaved: _loadNotes,
        ),
      ),
    );
  }

  Future<void> _deleteNote(Note note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notiz löschen'),
        content: Text('„${note.title}" löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await context.read<ApiService>().deleteNote(note.id);
        _loadNotes();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Löschen fehlgeschlagen: $e')));
        }
      }
    }
  }

  Color _hexToColor(String hex) {
    final clean = hex.replaceAll('#', '');
    return Color(int.parse('FF$clean', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notizen'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadNotes,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openNote(null),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              onChanged: (v) {
                _searchQuery = v;
                _applyFilters();
              },
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Notizen durchsuchen…',
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppColors.textSecondary),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded,
                            color: AppColors.textSecondary),
                        onPressed: () {
                          _searchQuery = '';
                          _applyFilters();
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.cardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.cardBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
                filled: true,
                fillColor: AppColors.surface,
              ),
            ),
          ),

          // Tag filters
          if (_allTags.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _TagChip(
                    label: 'Alle',
                    isSelected: _selectedTag == null,
                    onTap: () {
                      _selectedTag = null;
                      _applyFilters();
                    },
                  ),
                  ..._allTags.map(
                    (tag) => _TagChip(
                      label: tag,
                      isSelected: _selectedTag == tag,
                      onTap: () {
                        _selectedTag = _selectedTag == tag ? null : tag;
                        _applyFilters();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 8),

          // Notes grid
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                    ),
                  )
                : _filteredNotes.isEmpty
                    ? _EmptyState(onAdd: () => _openNote(null))
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: _filteredNotes.length,
                        itemBuilder: (context, i) {
                          final note = _filteredNotes[i];
                          return Dismissible(
                            key: Key(note.id),
                            direction: DismissDirection.startToEnd,
                            background: Container(
                              decoration: BoxDecoration(
                                color: AppColors.error.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 16),
                              child: const Icon(Icons.delete_outline_rounded,
                                  color: AppColors.error),
                            ),
                            confirmDismiss: (_) async {
                              await _deleteNote(note);
                              return false;
                            },
                            child: _NoteCard(
                              note: note,
                              onTap: () => _openNote(note),
                              hexToColor: _hexToColor,
                            )
                                .animate(
                                    delay: Duration(
                                        milliseconds: (i * 50).clamp(0, 400)))
                                .fade(duration: 300.ms)
                                .slideY(begin: 0.1, end: 0),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TagChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.2)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                isSelected ? AppColors.primary : AppColors.cardBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.primary : AppColors.textSecondary,
            fontSize: 12,
            fontWeight:
                isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final Color Function(String) hexToColor;

  const _NoteCard({
    required this.note,
    required this.onTap,
    required this.hexToColor,
  });

  Color get _accentColor {
    // Map card colors to accent colors
    switch (note.color) {
      case '#1A1528':
        return AppColors.primary;
      case '#12281A':
        return AppColors.success;
      case '#281A1A':
        return AppColors.error;
      case '#1A2228':
        return AppColors.secondary;
      case '#28221A':
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: hexToColor(note.color),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Colored top border
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: _accentColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(15),
                ),
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            note.title.isEmpty ? 'Ohne Titel' : note.title,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (note.isPinned)
                          const Icon(
                            Icons.push_pin_rounded,
                            color: AppColors.primary,
                            size: 14,
                          ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Content preview
                    Expanded(
                      child: Text(
                        note.content,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.5,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.fade,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Tags
                    if (note.tags.isNotEmpty)
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: note.tags
                            .take(3)
                            .map(
                              (tag) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color:
                                      _accentColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '#$tag',
                                  style: TextStyle(
                                    color: _accentColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(
                  color: AppColors.primary.withOpacity(0.3)),
            ),
            child: const Icon(
              Icons.note_add_outlined,
              color: AppColors.primary,
              size: 36,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Noch keine Notizen',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Bitte Jarvis, eine zu erstellen, oder tippe auf +',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Notiz erstellen'),
          ),
        ],
      ).animate().fade(duration: 400.ms),
    );
  }
}
