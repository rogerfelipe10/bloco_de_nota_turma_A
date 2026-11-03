
import 'package:bloco_de_nota_turma_a/database/database_helper.dart';
import 'package:bloco_de_nota_turma_a/models/note.dart';
import 'package:bloco_de_nota_turma_a/pages/login_page.dart';
import 'package:bloco_de_nota_turma_a/pages/note_form_page.dart';
import 'package:bloco_de_nota_turma_a/services/auth_service.dart';
import 'package:bloco_de_nota_turma_a/widgets/note_card.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final DatabaseHelper database = DatabaseHelper.instance;
  final AuthService authService = AuthService();

  final TextEditingController searchController =
      TextEditingController();

  List<Note> notes = [];

  String selectedCategory = 'Todas';
  bool newestFirst = true;
  bool isLoading = true;

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
  }

  // Carrega as notas do usuario autenticado
  Future<void> loadNotes() async {
    final user = FirebaseAuth.instance.currentUser;

    // DIAGNOSTICO TEMPORARIO DO SQLITE
    try {
      final allNotes = await database.debugAllNotes();

      debugPrint(
        'TOTAL DE NOTAS NO SQLITE: ${allNotes.length}',
      );

      for (final note in allNotes) {
        debugPrint(
          'ID: ${note['id']} | '
          'UID: ${note['uid']} | '
          'Titulo: ${note['title']} | '
          'Excluida: ${note['isDeleted']}',
        );
      }

      if (user != null) {
        debugPrint(
          'UID DO USUARIO ATUAL: ${user.uid}',
        );
      }
    } catch (e) {
      debugPrint(
        'ERRO AO CONSULTAR SQLITE: $e',
      );
    }
    // FIM DO DIAGNOSTICO

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
      final result = await database.getNotes(user.uid);

      if (mounted) {
        setState(() {
          notes = result;
          isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao carregar notas: $e'),
        ),
      );
    }
  }

  // Converte datas antigas e novas
  DateTime parseNoteDate(Note note) {
    final value = note.updatedAt;

    final isoDate = DateTime.tryParse(value);

    if (isoDate != null) {
      return isoDate;
    }

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

  // Pesquisa, filtra e ordena as notas
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
      final dateA = parseNoteDate(a);
      final dateB = parseNoteDate(b);

      final comparison = dateA.compareTo(dateB);

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

  // Exclui uma nota localmente
  Future<void> deleteNote(int id) async {
    try {
      await database.deleteNote(id);
      await loadNotes();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nota excluida com sucesso!'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao excluir nota: $e'),
        ),
      );
    }
  }

  // Sair da conta
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

  // Abre uma nota para edicao
  Future<void> openEditNote(Note note) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteFormPage(note: note),
      ),
    );

    await loadNotes();
  }

  // Abre o formulario de nova nota
  Future<void> openNewNote() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const NoteFormPage(),
      ),
    );

    await loadNotes();
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
            tooltip: 'Sair',
            onPressed: logout,
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: openNewNote,
        backgroundColor: const Color(0xff6c4ab6),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user?.email ?? '',
              style: const TextStyle(
                color: Color(0xFF77717f),
                fontSize: 13,
              ),
            ),

            const SizedBox(height: 20),

            // Pesquisa
            TextField(
              controller: searchController,
              onChanged: (value) {
                setState(() {});
              },
              decoration: InputDecoration(
                hintText: 'Pesquisar notas...',
                prefixIcon: const Icon(
                  Icons.search,
                  color: Color(0xff6c4ab6),
                ),
                suffixIcon:
                    searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              searchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 15),

            // Filtro por categoria
            DropdownButtonFormField<String>(
              initialValue: selectedCategory,
              decoration: InputDecoration(
                labelText: 'Filtrar por categoria',
                prefixIcon: const Icon(
                  Icons.category_rounded,
                  color: Color(0xff6c4ab6),
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
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

            // Ordenacao por data
            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${visibleNotes.length} nota(s)',
                  style: const TextStyle(
                    color: Color(0xFF77717f),
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

            // Lista de notas
            Expanded(
              child: isLoading
                  ? const Center(
                      child: CircularProgressIndicator(),
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
                                color: Color(0xff6c4ab6),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                notes.isEmpty
                                    ? 'Nenhuma nota ainda'
                                    : 'Nenhuma nota encontrada',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
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
                          itemCount: visibleNotes.length,
                          itemBuilder: (context, index) {
                            final note = visibleNotes[index];

                            return NoteCard(
                              note: note,
                              onTap: () => openEditNote(note),
                              onDelete: () {
                                if (note.id != null) {
                                  deleteNote(note.id!);
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
