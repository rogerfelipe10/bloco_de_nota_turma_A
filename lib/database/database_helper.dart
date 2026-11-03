
import 'package:bloco_de_nota_turma_a/models/note.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance =
      DatabaseHelper._init();

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
      version: 4,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  // Cria o banco completo em novas instalacoes
  Future<void> _createDB(
    Database db,
    int version,
  ) async {
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
        remoteUpdatedAt TEXT,
        syncStatus TEXT NOT NULL DEFAULT 'pending',
        isDeleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX idx_notes_cloud
      ON notes(uid, cloudId)
    ''');
  }

  // Atualiza bancos antigos sem apagar notas
  Future<void> _upgradeDB(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // Versao 1 para 2
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

      await db.execute('''
        UPDATE notes
        SET updatedAt = date
        WHERE updatedAt IS NULL
      ''');
    }

    // Versao 2 para 3
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
        CREATE UNIQUE INDEX IF NOT EXISTS
        idx_notes_cloud
        ON notes(uid, cloudId)
      ''');
    }

    // Versao 3 para 4
    if (oldVersion < 4) {
      await db.execute('''
        ALTER TABLE notes
        ADD COLUMN remoteUpdatedAt TEXT
      ''');

      // As notas ja sincronizadas conhecem
      // a versao que foi salva no Firebase.
      await db.execute('''
        UPDATE notes
        SET remoteUpdatedAt = updatedAt
        WHERE syncStatus = 'synced'
          AND cloudId IS NOT NULL
          AND remoteUpdatedAt IS NULL
      ''');

      // Notas pendentes continuam com
      // remoteUpdatedAt nulo, caso ainda
      // nao tenhamos uma versao confiavel.
    }
  }

  // Insere uma nova nota local
  Future<int> insertNote(Note note) async {
    final db = await database;

    return await db.insert(
      'notes',
      {
        ...note.toMap(),
        'remoteUpdatedAt': null,
        'syncStatus': 'pending',
        'isDeleted': 0,
      },
    );
  }

  // Busca notas visiveis do usuario
  Future<List<Note>> getNotes(String uid) async {
    final db = await database;

    final result = await db.query(
      'notes',
      where: 'uid = ? AND isDeleted = 0',
      whereArgs: [uid],
      orderBy: 'updatedAt DESC, id DESC',
    );

    return result.map((map) {
      return Note.fromMap(map);
    }).toList();
  }

  // Atualiza uma nota local
  Future<int> updateNote(Note note) async {
    final db = await database;

    // Nao altera remoteUpdatedAt.
    // Ele representa a ultima versao
    // conhecida da nuvem.
    return await db.update(
      'notes',
      {
        ...note.toMap(),
        'syncStatus': 'pending',
      },
      where: '''
        id = ?
        AND uid = ?
        AND isDeleted = 0
      ''',
      whereArgs: [
        note.id,
        note.uid,
      ],
    );
  }

  // Exclusao logica para permitir uso offline
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

  // Recupera alteracoes pendentes
  Future<List<Map<String, dynamic>>> getPendingNotes(
    String uid,
  ) async {
    final db = await database;

    return await db.query(
      'notes',
      where: '''
        uid = ?
        AND syncStatus = ?
      ''',
      whereArgs: [uid, 'pending'],
      orderBy: 'id ASC',
    );
  }

  // Confirma o envio de uma nota ao Firebase
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
        'remoteUpdatedAt': expectedUpdatedAt,
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

  // Confirma exclusao apos o Firebase responder
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

  // Diagnostico temporario
  Future<List<Map<String, dynamic>>> debugAllNotes() async {
    final db = await database;

    return await db.query('notes');
  }

  // Atribui um identificador da nuvem
  // sem mudar o estado pendente
  Future<int> assignCloudId(
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
      },
      where: '''
        id = ?
        AND uid = ?
        AND updatedAt = ?
        AND cloudId IS NULL
        AND syncStatus = 'pending'
        AND isDeleted = 0
      ''',
      whereArgs: [
        id,
        uid,
        expectedUpdatedAt,
      ],
    );
  }

  // Busca uma nota pelo ID da nuvem
  Future<Map<String, dynamic>?> getNoteByCloudId(
    String uid,
    String cloudId,
  ) async {
    final db = await database;

    final result = await db.query(
      'notes',
      where: '''
        uid = ?
        AND cloudId = ?
      ''',
      whereArgs: [
        uid,
        cloudId,
      ],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return result.first;
  }

  // Insere ou atualiza uma nota recebida
  // diretamente do Firebase
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
        where: '''
          uid = ?
          AND cloudId = ?
        ''',
        whereArgs: [
          note.uid,
          note.cloudId,
        ],
        limit: 1,
      );

      if (existing.isEmpty) {
        await txn.insert(
          'notes',
          {
            ...note.toMap(),
            'remoteUpdatedAt': note.updatedAt,
            'syncStatus': 'synced',
            'isDeleted': 0,
          },
        );

        return;
      }

      final local = existing.first;

      // Protege alteracoes locais pendentes
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
          'remoteUpdatedAt': note.updatedAt,
          'syncStatus': 'synced',
        },
        where: '''
          id = ?
          AND uid = ?
          AND isDeleted = 0
        ''',
        whereArgs: [
          local['id'],
          note.uid,
        ],
      );
    });
  }

  // Remove notas que ja estavam sincronizadas,
  // mas foram excluidas da nuvem
  Future<int> removeMissingCloudNotes(
    String uid,
    Set<String> remoteIds,
  ) async {
    final db = await database;

    return await db.transaction((txn) async {
      final localNotes = await txn.query(
        'notes',
        columns: [
          'id',
          'cloudId',
        ],
        where: '''
          uid = ?
          AND cloudId IS NOT NULL
          AND syncStatus = ?
          AND isDeleted = 0
        ''',
        whereArgs: [
          uid,
          'synced',
        ],
      );

      int removed = 0;

      for (final row in localNotes) {
        final cloudId = row['cloudId'] as String;

        if (!remoteIds.contains(cloudId)) {
          removed += await txn.delete(
            'notes',
            where: '''
              id = ?
              AND uid = ?
              AND cloudId = ?
              AND syncStatus = ?
              AND isDeleted = 0
            ''',
            whereArgs: [
              row['id'],
              uid,
              cloudId,
              'synced',
            ],
          );
        }
      }

      return removed;
    });
  }
}
