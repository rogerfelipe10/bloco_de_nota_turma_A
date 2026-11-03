
import 'package:bloco_de_nota_turma_a/models/note.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();

  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _initDB('notes.db');
    return _database!;
  }

  // Inicializa o banco de dados
  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  // Cria a tabela com os novos campos
  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uid TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        date TEXT NOT NULL,
        cloudId TEXT,
        category TEXT NOT NULL DEFAULT 'Pessoal',
        updatedAt TEXT NOT NULL
      )
    ''');
  }

  // Atualiza bancos antigos sem apagar as notas
  Future<void> _upgradeDB(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE notes ADD COLUMN cloudId TEXT',
      );

      await db.execute(
        "ALTER TABLE notes ADD COLUMN category TEXT NOT NULL DEFAULT 'Pessoal'",
      );

      await db.execute(
        'ALTER TABLE notes ADD COLUMN updatedAt TEXT',
      );

      await db.execute(
        'UPDATE notes SET updatedAt = date WHERE updatedAt IS NULL',
      );
    }
  }

  // Cadastra uma nota no SQLite
  Future<int> insertNote(Note note) async {
    final db = await database;

    return await db.insert(
      'notes',
      note.toMap(),
    );
  }

  // Consulta as notas do usuário
  Future<List<Note>> getNotes(String uid) async {
    final db = await database;

    final result = await db.query(
      'notes',
      where: 'uid = ?',
      whereArgs: [uid],
      orderBy: 'updatedAt DESC, id DESC',
    );

    return result.map((map) => Note.fromMap(map)).toList();
  }

  // Atualiza uma nota existente
  Future<int> updateNote(Note note) async {
    final db = await database;

    return await db.update(
      'notes',
      note.toMap(),
      where: 'id = ? AND uid = ?',
      whereArgs: [note.id, note.uid],
    );
  }

  // Exclui uma nota
  Future<int> deleteNote(int id) async {
    final db = await database;

    return await db.delete(
      'notes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
