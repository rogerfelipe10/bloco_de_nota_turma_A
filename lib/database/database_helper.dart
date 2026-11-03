
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
    } else {
      _database = await _initDB('notes.db');
      return _database!;
    }
  }

  // Inicializa o banco de dados SQLite
  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  // Cria a tabela de notas
  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE notes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uid TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        date TEXT NOT NULL
      )
    ''');
  }

  // Cadastra uma nova nota
  Future<int> insertNote(Note note) async {
    final db = await instance.database;

    return await db.insert(
      'notes',
      note.toMap(),
    );
  }

  // Consulta as notas do usuário autenticado
  Future<List<Note>> getNotes(String uid) async {
    final db = await instance.database;

    final result = await db.query(
      'notes',
      where: 'uid = ?',
      whereArgs: [uid],
      orderBy: 'id DESC',
    );

    return result.map((map) => Note.fromMap(map)).toList();
  }

  // Atualiza uma nota existente
  Future<int> updateNote(Note note) async {
    final db = await instance.database;

    return await db.update(
      'notes',
      note.toMap(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  // Exclui uma nota pelo ID
  Future<int> deleteNote(int id) async {
    final db = await instance.database;

    return await db.delete(
      'notes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
