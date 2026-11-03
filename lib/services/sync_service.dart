
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../database/database_helper.dart';
import '../models/note.dart';
import 'firestore_service.dart';

// Informacoes usadas pela janela de conflito.
class SyncConflict implements Exception {
  final String uid;
  final Map<String, dynamic> localRow;
  final Map<String, dynamic>? remoteRow;

  SyncConflict({
    required this.uid,
    required this.localRow,
    required this.remoteRow,
  });

  int get localId => localRow['id'] as int;

  bool get localDeleted =>
      localRow['isDeleted'] == 1;

  String get localTitle =>
      localRow['title'] as String? ?? '';

  String get localContent =>
      localRow['content'] as String? ?? '';

  String? get remoteTitle =>
      remoteRow?['title'] as String?;

  String? get remoteContent =>
      remoteRow?['content'] as String?;

  bool get remoteDeleted => remoteRow == null;

  @override
  String toString() =>
      'Conflito na nota $localId';
}

class SyncService {
  final DatabaseHelper database =
      DatabaseHelper.instance;

  final FirestoreService firestore =
      FirestoreService();

  bool _isSyncing = false;

  void checkUser(String uid) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || user.uid != uid) {
      throw StateError(
        'Usuario nao autenticado ou conta alterada.',
      );
    }
  }

  Note _noteFromRow(
    Map<String, dynamic> row,
    String uid,
  ) {
    return Note(
      id: row['id'] as int,
      uid: uid,
      title: row['title'] as String,
      content: row['content'] as String,
      date: row['date'] as String,
      cloudId: row['cloudId'] as String?,
      category: row['category'] as String? ??
          'Pessoal',
      updatedAt: row['updatedAt'] as String,
    );
  }

  Future<SyncConflict> _createConflict(
    String uid,
    Map<String, dynamic> row,
    String cloudId,
  ) async {
    checkUser(uid);

    final remote =
        await firestore.getRemoteDocument(cloudId);

    return SyncConflict(
      uid: uid,
      localRow: Map<String, dynamic>.from(row),
      remoteRow: remote == null
          ? null
          : Map<String, dynamic>.from(remote),
    );
  }

  // Executa a sincronizacao.
  Future<void> syncNotes(String uid) async {
    if (_isSyncing) {
      throw StateError(
        'Ja existe uma sincronizacao em andamento.',
      );
    }

    checkUser(uid);
    _isSyncing = true;

    try {
      debugPrint('INICIANDO SINCRONIZACAO');

      await uploadPendingNotes(uid);
      await downloadCloudNotes(uid);

      debugPrint('SINCRONIZACAO FINALIZADA');
    } on SyncConflict {
      // Deixa o conflito chegar ate a tela.
      rethrow;
    } catch (e) {
      throw Exception(
        'Falha na sincronizacao: $e',
      );
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> uploadPendingNotes(String uid) async {
    checkUser(uid);

    final pendingNotes =
        await database.getPendingNotes(uid);

    for (final row in pendingNotes) {
      checkUser(uid);

      final id = row['id'] as int;
      final updatedAt =
          row['updatedAt'] as String;

      String? cloudId =
          row['cloudId'] as String?;

      final remoteUpdatedAt =
          row['remoteUpdatedAt'] as String?;

      final isDeleted = row['isDeleted'] == 1;

      // Nota excluida localmente.
      if (isDeleted) {
        if (cloudId == null) {
          await database.confirmDeletedNote(
            id,
            uid,
            updatedAt,
          );
          continue;
        }

        // Sem versao conhecida, exige decisao
        // caso haja documento na nuvem.
        if (remoteUpdatedAt == null) {
          final remote =
              await firestore.getRemoteDocument(
            cloudId,
          );

          if (remote == null) {
            await database.confirmDeletedNote(
              id,
              uid,
              updatedAt,
            );
          } else {
            throw SyncConflict(
              uid: uid,
              localRow: row,
              remoteRow: remote,
            );
          }

          continue;
        }

        try {
          await firestore.deleteNoteSafely(
            cloudId,
            expectedRemoteUpdatedAt:
                remoteUpdatedAt,
          );
        } on NoteConflictException {
          throw await _createConflict(
            uid,
            row,
            cloudId,
          );
        }

        checkUser(uid);

        await database.confirmDeletedNote(
          id,
          uid,
          updatedAt,
        );

        continue;
      }

      // Nota criada ou editada localmente.
      final isNew = remoteUpdatedAt == null;

      if (cloudId == null) {
        cloudId = FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('notes')
            .doc()
            .id;

        final assigned =
            await database.assignCloudId(
          id,
          uid,
          cloudId,
          updatedAt,
        );

        if (assigned == 0) continue;
      }

      final note = _noteFromRow(
        {
          ...row,
          'cloudId': cloudId,
        },
        uid,
      );

      try {
        await firestore.saveNoteSafely(
          note,
          isNew: isNew,
          expectedRemoteUpdatedAt:
              remoteUpdatedAt,
        );
      } on NoteConflictException {
        throw await _createConflict(
          uid,
          row,
          cloudId,
        );
      }

      checkUser(uid);

      await database.markNoteSynced(
        id,
        uid,
        cloudId,
        updatedAt,
      );
    }
  }

  // Opcao escolhida na janela:
  // manter a versao do aplicativo.
  Future<void> keepLocalVersion(
    SyncConflict conflict,
  ) async {
    checkUser(conflict.uid);

    if (conflict.remoteDeleted) {
      throw NoteConflictException(
        'A nota foi excluida do Firebase. '
        'Nao sera recriada automaticamente.',
      );
    }

    final row = conflict.localRow;
    final uid = conflict.uid;
    final id = conflict.localId;
    final updatedAt =
        row['updatedAt'] as String;

    final cloudId = row['cloudId'] as String?;

    if (cloudId == null) {
      throw StateError(
        'Nota sem identificador da nuvem.',
      );
    }

    final current =
        await database.getNoteByCloudId(
      uid,
      cloudId,
    );

    if (current == null ||
        current['id'] != id ||
        current['syncStatus'] != 'pending' ||
        current['updatedAt'] != updatedAt ||
        current['isDeleted'] != row['isDeleted']) {
      throw StateError(
        'A nota local mudou. Sincronize novamente.',
      );
    }

    await firestore.resolveKeepingLocal(
      _noteFromRow(row, uid),
      expectedRemote: conflict.remoteRow!,
      delete: conflict.localDeleted,
    );

    checkUser(uid);

    if (conflict.localDeleted) {
      await database.confirmDeletedNote(
        id,
        uid,
        updatedAt,
      );
    } else {
      await database.markNoteSynced(
        id,
        uid,
        cloudId,
        updatedAt,
      );
    }
  }

  // Opcao escolhida na janela:
  // manter a versao do Firebase.
  Future<void> keepFirebaseVersion(
    SyncConflict conflict,
  ) async {
    final uid = conflict.uid;

    checkUser(uid);

    final cloudId =
        conflict.localRow['cloudId'] as String?;

    if (cloudId == null) {
      throw StateError('Nota sem cloudId.');
    }

    // Busca a versao mais recente da nuvem.
    final remote =
        await firestore.getRemoteDocument(cloudId);

    checkUser(uid);

    
    final db = await database.database;

    await db.transaction((txn) async {

      final rows = await txn.query(
        'notes',
        where: '''
          id = ?
          AND uid = ?
          AND cloudId = ?
          AND syncStatus = 'pending'
          AND updatedAt = ?
          AND isDeleted = ?
        ''',
        whereArgs: [
          conflict.localId,
          uid,
          cloudId,
          conflict.localRow['updatedAt'],
          conflict.localRow['isDeleted'],
        ],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw StateError(
          'A nota local mudou. Sincronize novamente.',
        );
      }

      if (remote == null) {
        // O Firebase nao possui mais essa nota.
        await txn.delete(
          'notes',
          where: 'id = ? AND uid = ?',
          whereArgs: [conflict.localId, uid],
        );

        return;
      }

      await txn.update(
        'notes',
        {
          'title': remote['title'] as String? ?? '',
          'content':
              remote['content'] as String? ?? '',
          'date': remote['date'] as String? ?? '',
          'category':
              remote['category'] as String? ??
                  'Pessoal',
          'updatedAt':
              remote['updatedAt'] as String? ?? '',
          'remoteUpdatedAt':
              remote['updatedAt'] as String? ?? '',
          'syncStatus': 'synced',
          'isDeleted': 0,
        },
        where: 'id = ? AND uid = ?',
        whereArgs: [conflict.localId, uid],
      );
    });
  }

  // Baixa as notas do Firebase.
  Future<void> downloadCloudNotes(String uid) async {
    checkUser(uid);

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notes')
        .get(
          const GetOptions(
            source: Source.server,
          ),
        );

    checkUser(uid);

    final remoteIds = snapshot.docs
        .map((doc) => doc.id)
        .toSet();

    debugPrint(
      'DOCUMENTOS EXISTENTES NO FIRESTORE: '
      '${remoteIds.length}',
    );

    for (final doc in snapshot.docs) {
      checkUser(uid);

      final data = doc.data();

      if (data['uid'] != uid) continue;

      final note = Note(
        cloudId: doc.id,
        uid: uid,
        title: data['title'] as String? ?? '',
        content:
            data['content'] as String? ?? '',
        date: data['date'] as String? ?? '',
        category:
            data['category'] as String? ??
                'Pessoal',
        updatedAt:
            data['updatedAt'] as String?,
      );

      await database.saveRemoteNote(note);
    }

    checkUser(uid);

    final removed =
        await database.removeMissingCloudNotes(
      uid,
      remoteIds,
    );

    debugPrint(
      'NOTAS REMOVIDAS DO SQLITE: $removed',
    );
  }
}
