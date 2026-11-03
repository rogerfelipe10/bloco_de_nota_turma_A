
import 'package:bloco_de_nota_turma_a/database/database_helper.dart';
import 'package:bloco_de_nota_turma_a/models/note.dart';
import 'package:bloco_de_nota_turma_a/pages/login_page.dart';
import 'package:bloco_de_nota_turma_a/pages/note_form_page.dart';
import 'package:bloco_de_nota_turma_a/services/auth_service.dart';
import 'package:bloco_de_nota_turma_a/services/sync_service.dart';
import 'package:bloco_de_nota_turma_a/widgets/note_card.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

enum ConflictChoice {
  keepLocal,
  keepFirebase,
  later,
}

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() =>
      _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final DatabaseHelper database =
      DatabaseHelper.instance;

  final AuthService authService = AuthService();

  final SyncService syncService = SyncService();

  final TextEditingController searchController =
      TextEditingController();

  List<Note> notes = [];

  String selectedCategory = 'Todas';

  bool newestFirst = true;
  bool isLoading = true;
  bool isSyncing = false;

  final List<String> categories = [
    'Todas',
    'Estudos',
    'Trabalho',
    'Pessoal',
    'Outros',
  ];

  @override
  void initState() {
    super.initState();

    loadNotes();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        synchronizeNotes();
      }
    });
  }

  // Carrega as notas locais do usuario.
  Future<void> loadNotes() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() {
          notes = [];
          isLoading = false;
        });
      }
      return;
    }

    try {
      final result =
          await database.getNotes(user.uid);

      if (!mounted) return;

      setState(() {
        notes = result;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      showMessage('Erro ao carregar notas: $e');
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  // Exibe a janela com as duas versoes.
  Future<ConflictChoice?> showConflictDialog(
    SyncConflict conflict,
  ) async {
    if (!mounted) return null;

    final remoteDeleted = conflict.remoteDeleted;

    return showDialog<ConflictChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Conflito de notas',
                  style: TextStyle(fontSize: 19),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Esta nota foi alterada no '
                    'aplicativo e no Firebase.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    conflict.localTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Versao local
                  const Text(
                    'VERSÃO DO APLICATIVO',
                    style: TextStyle(
                      color: Color(0xFF6C4AB6),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0EAFB),
                      borderRadius:
                          BorderRadius.circular(10),
                    ),
                    child: Text(
                      conflict.localDeleted
                          ? 'Nota excluída no aplicativo'
                          : conflict.localContent,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Versao Firebase
                  const Text(
                    'VERSÃO DO FIREBASE',
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF3FC),
                      borderRadius:
                          BorderRadius.circular(10),
                    ),
                    child: Text(
                      remoteDeleted
                          ? 'Nota excluída do Firebase'
                          : conflict.remoteContent ?? '',
                    ),
                  ),

                  const SizedBox(height: 14),
                  const Text(
                    'Escolha qual versão deseja manter. '
                    'A outra versão será substituída.',
                    style: TextStyle(fontSize: 13),
                  ),

                  if (remoteDeleted) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'A versão local não poderá '
                      'recriar automaticamente uma '
                      'nota excluída no Firebase.',
                      style: TextStyle(
                        color: Colors.deepOrange,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  ConflictChoice.later,
                );
              },
              child: const Text('Resolver depois'),
            ),
            OutlinedButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  ConflictChoice.keepFirebase,
                );
              },
              child: const Text('Manter Firebase'),
            ),
            FilledButton(
              onPressed: remoteDeleted
                  ? null
                  : () {
                      Navigator.pop(
                        dialogContext,
                        ConflictChoice.keepLocal,
                      );
                    },
              child: const Text('Manter aplicativo'),
            ),
          ],
        );
      },
    );
  }

  // Sincroniza e permite resolver conflitos.
  Future<void> synchronizeNotes() async {
    if (isSyncing) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    setState(() {
      isSyncing = true;
    });

    try {
      // Repete a sincronizacao depois de cada
      // conflito resolvido.
      for (int attempt = 0; attempt < 20; attempt++) {
        try {
          await syncService.syncNotes(user.uid);

          if (!mounted) return;

          await loadNotes();

          showMessage(
            'Sincronização com Firebase concluída!',
          );
          return;
        } on SyncConflict catch (conflict) {
          if (!mounted) return;

          await loadNotes();

          final choice =
              await showConflictDialog(conflict);

          if (!mounted) return;

          if (choice == null ||
              choice == ConflictChoice.later) {
            showMessage(
              'Conflito mantido para resolver depois.',
            );
            return;
          }

          if (choice == ConflictChoice.keepLocal) {
            await syncService.keepLocalVersion(
              conflict,
            );

            showMessage(
              'Versão do aplicativo mantida.',
            );
          } else {
            await syncService.keepFirebaseVersion(
              conflict,
            );

            showMessage(
              'Versão do Firebase mantida.',
            );
          }

          // Atualiza a lista antes de continuar.
          await loadNotes();
        }
      }

      showMessage(
        'Muitos conflitos encontrados. '
        'Sincronize novamente para continuar.',
      );
    } catch (e) {
      showMessage(
        'Não foi possível sincronizar: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          isSyncing = false;
        });
      }
    }
  }

  DateTime parseNoteDate(Note note) {
    final value = note.updatedAt;

    final isoDate = DateTime.tryParse(value);

    if (isoDate != null) return isoDate;

    try {
      final parts = value.split(' ');
      final dateParts = parts[0].split('/');
      final timeParts = parts[1].split(':');

      return DateTime(
        int.parse(dateParts[2]),
        int.parse(dateParts[1]),
        int.parse(dateParts[0]),
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  // Pesquisa, categoria e ordenacao.
  List<Note> get filteredNotes {
    final search =
        searchController.text.trim().toLowerCase();

    final result = notes.where((note) {
      final matchesSearch =
          note.title.toLowerCase().contains(search) ||
          note.content.toLowerCase().contains(search);

      final matchesCategory =
          selectedCategory == 'Todas' ||
          note.category == selectedCategory;

      return matchesSearch && matchesCategory;
    }).toList();

    result.sort((a, b) {
      final comparison =
          parseNoteDate(a).compareTo(parseNoteDate(b));

      if (comparison == 0) {
        final idComparison =
            (a.id ?? 0).compareTo(b.id ?? 0);

        return newestFirst
            ? -idComparison
            : idComparison;
      }

      return newestFirst
          ? -comparison
          : comparison;
    });

    return result;
  }

  Future<void> deleteNote(int id) async {
    try {
      await database.deleteNote(id);
      await loadNotes();

      showMessage(
        'Nota excluída localmente. '
        'Sincronize para atualizar o Firebase.',
      );
    } catch (e) {
      showMessage('Erro ao excluir nota: $e');
    }
  }

  Future<void> logout() async {
    await authService.logout();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginPage(),
      ),
      (route) => false,
    );
  }

  Future<void> openEditNote(Note note) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteFormPage(note: note),
      ),
    );

    if (mounted) {
      await loadNotes();
    }
  }

  Future<void> openNewNote() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const NoteFormPage(),
      ),
    );

    if (mounted) {
      await loadNotes();
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final visibleNotes = filteredNotes;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Minhas notas',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Sincronizar notas',
            onPressed: isSyncing
                ? null
                : synchronizeNotes,
            icon: isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.sync_rounded),
          ),
          IconButton(
            tooltip: 'Sair',
            onPressed: isSyncing ? null : logout,
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton:
          FloatingActionButton.extended(
        onPressed: isSyncing ? null : openNewNote,
        backgroundColor:
            const Color(0xFF6C4AB6),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Nova Nota',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(
          20, 10, 20, 90,
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Text(
              user?.email ?? '',
              style: const TextStyle(
                color: Color(0xFF77717F),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),

            // Pesquisa
            TextField(
              controller: searchController,
              onChanged: (_) {
                setState(() {});
              },
              decoration: InputDecoration(
                hintText: 'Pesquisar notas...',
                prefixIcon: const Icon(
                  Icons.search,
                  color: Color(0xFF6C4AB6),
                ),
                suffixIcon:
                    searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.clear,
                            ),
                            onPressed: () {
                              searchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 15),

            // Categoria
            DropdownButtonFormField<String>(
              initialValue: selectedCategory,
              decoration: InputDecoration(
                labelText: 'Filtrar por categoria',
                prefixIcon: const Icon(
                  Icons.category_rounded,
                  color: Color(0xFF6C4AB6),
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
              items: categories.map((category) {
                return DropdownMenuItem<String>(
                  value: category,
                  child: Text(category),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    selectedCategory = value;
                  });
                }
              },
            ),
            const SizedBox(height: 12),

            // Ordenacao
            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${visibleNotes.length} nota(s)',
                  style: const TextStyle(
                    color: Color(0xFF77717F),
                    fontSize: 13,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      newestFirst = !newestFirst;
                    });
                  },
                  icon: Icon(
                    newestFirst
                        ? Icons.arrow_downward
                        : Icons.arrow_upward,
                    size: 18,
                  ),
                  label: Text(
                    newestFirst
                        ? 'Mais recentes'
                        : 'Mais antigas',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Lista das notas
            Expanded(
              child: isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(),
                    )
                  : visibleNotes.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.sticky_note_2_rounded,
                                size: 65,
                                color:
                                    Color(0xFF6C4AB6),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                notes.isEmpty
                                    ? 'Nenhuma nota ainda'
                                    : 'Nenhuma nota encontrada',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Crie uma nota ou altere os filtros.',
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount:
                              visibleNotes.length,
                          itemBuilder:
                              (context, index) {
                            final note =
                                visibleNotes[index];

                            return NoteCard(
                              note: note,
                              onTap: () {
                                if (!isSyncing) {
                                  openEditNote(note);
                                }
                              },
                              onDelete: () {
                                if (!isSyncing &&
                                    note.id != null) {
                                  deleteNote(
                                    note.id!,
                                  );
                                }
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
