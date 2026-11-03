
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

  // Inicializa o SQLite
  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);

    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  // Cria o banco completo para novas instalações
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
        updatedAt TEXT NOT NULL,
        syncStatus TEXT NOT NULL DEFAULT 'pending',
        isDeleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX idx_notes_cloud
      ON notes(uid, cloudId)
    ''');
  }

  // Atualiza o banco sem apagar as notas existentes
  Future<void> _upgradeDB(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // Atualização da versão 1 para 2
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

    // Atualização da versão 2 para 3
    if (oldVersion < 3) {
      await db.execute('''
        ALTER TABLE notes
        ADD COLUMN syncStatus TEXT NOT NULL
        DEFAULT 'pending'
      ''');

      await db.execute('''
        ALTER TABLE notes
        ADD COLUMN isDeleted INTEGER NOT NULL
        DEFAULT 0
      ''');

      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_notes_cloud
        ON notes(uid, cloudId)
      ''');
    }
  }

  // Salva uma nova nota localmente
  Future<int> insertNote(Note note) async {
    final db = await database;

    return await db.insert(
      'notes',
      {
        ...note.toMap(),
        'syncStatus': 'pending',
        'isDeleted': 0,
      },
    );
  }

  // Busca as notas visíveis do usuário
  Future<List<Note>> getNotes(String uid) async {
    final db = await database;

    final result = await db.query(
      'notes',
      where: 'uid = ? AND isDeleted = 0',
      whereArgs: [uid],
      orderBy: 'updatedAt DESC, id DESC',
    );

    return result
        .map((map) => Note.fromMap(map))
        .toList();
  }

  // Atualiza uma nota e marca sincronização pendente
  Future<int> updateNote(Note note) async {
    final db = await database;

    return await db.update(
      'notes',
      {
        ...note.toMap(),
        'syncStatus': 'pending',
      },
      where: 'id = ? AND uid = ? AND isDeleted = 0',
      whereArgs: [note.id, note.uid],
    );
  }

  // Exclusão lógica: não apaga imediatamente do SQLite
  Future<int> deleteNote(int id) async {
    final db = await database;

    return await db.update(
      'notes',
      {
        'isDeleted': 1,
        'syncStatus': 'pending',
        'updatedAt': DateTime.now()
            .toUtc()
            .toIso8601String(),
      },
      where: 'id = ? AND isDeleted = 0',
      whereArgs: [id],
    );
  }

  // Recupera alterações pendentes de um usuário
  Future<List<Map<String, dynamic>>> getPendingNotes(
    String uid,
  ) async {
    final db = await database;

    return await db.query(
      'notes',
      where: 'uid = ? AND syncStatus = ?',
      whereArgs: [uid, 'pending'],
      orderBy: 'id ASC',
    );
  }

  // Marca uma nota como sincronizada
  // Só confirma se ela não foi alterada durante o envio
  Future<int> markNoteSynced(
    int id,
    String uid,
    String cloudId,
    String expectedUpdatedAt,
  ) async {
    final db = await database;

    return await db.update(
      'notes',
      {
        'cloudId': cloudId,
        'syncStatus': 'synced',
      },
      where: '''
        id = ?
        AND uid = ?
        AND updatedAt = ?
        AND isDeleted = 0
      ''',
      whereArgs: [
        id,
        uid,
        expectedUpdatedAt,
      ],
    );
  }

  // Remove definitivamente uma exclusão
  // depois da confirmação do Firebase
  Future<int> confirmDeletedNote(
    int id,
    String uid,
    String expectedUpdatedAt,
  ) async {
    final db = await database;

    return await db.delete(
      'notes',
      where: '''
        id = ?
        AND uid = ?
        AND isDeleted = 1
        AND updatedAt = ?
      ''',
      whereArgs: [
        id,
        uid,
        expectedUpdatedAt,
      ],
    );
  }
  
  // Diagnóstico temporário do SQLite
  Future<List<Map<String, dynamic>>> debugAllNotes() async {
    final db = await database;
    return await db.query('notes');
  }
  
  // Guarda o ID da nuvem antes de enviar a nota
  Future<int> assignCloudId(
    int id,
    String uid,
    String cloudId,
    String expectedUpdatedAt,
  ) async {
    final db = await database;

    return await db.update(
      'notes',
      {'cloudId': cloudId},
      where: '''
        id = ?
        AND uid = ?
        AND updatedAt = ?
        AND cloudId IS NULL
        AND syncStatus = 'pending'
        AND isDeleted = 0
      ''',
      whereArgs: [id, uid, expectedUpdatedAt],
    );
  }

  // Consulta uma nota local pelo ID do Firestore
  Future<Map<String, dynamic>?> getNoteByCloudId(
    String uid,
    String cloudId,
  ) async {
    final db = await database;

    final result = await db.query(
      'notes',
      where: 'uid = ? AND cloudId = ?',
      whereArgs: [uid, cloudId],
      limit: 1,
    );

    if (result.isEmpty) return null;

    return result.first;
  }

  // Recebe uma nota do Firestore no banco local
  Future<void> saveRemoteNote(Note note) async {
    final db = await database;

    if (note.cloudId == null) {
      throw ArgumentError(
        'Nota recebida sem identificador da nuvem',
      );
    }

    await db.transaction((txn) async {
      final existing = await txn.query(
        'notes',
        where: 'uid = ? AND cloudId = ?',
        whereArgs: [note.uid, note.cloudId],
        limit: 1,
      );

      if (existing.isEmpty) {
        await txn.insert(
          'notes',
          {
            ...note.toMap(),
            'syncStatus': 'synced',
            'isDeleted': 0,
          },
        );
        return;
      }

      final local = existing.first;

      // Nunca sobrescreve uma alteração local pendente
      if (local['syncStatus'] == 'pending') {
        return;
      }

      await txn.update(
        'notes',
        {
          'title': note.title,
          'content': note.content,
          'date': note.date,
          'category': note.category,
          'updatedAt': note.updatedAt,
          'syncStatus': 'synced',
        },
        where: 'id = ? AND uid = ? AND isDeleted = 0',
        whereArgs: [local['id'], note.uid],
      );
    });
  }

}
