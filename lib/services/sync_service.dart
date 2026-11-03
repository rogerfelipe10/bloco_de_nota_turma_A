
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../database/database_helper.dart';
import '../models/note.dart';
import 'firestore_service.dart';

class SyncService {
  final DatabaseHelper database = DatabaseHelper.instance;
  final FirestoreService firestore = FirestoreService();

  bool _isSyncing = false;

  // Verifica se o usuario continua autenticado.
  void checkUser(String uid) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || user.uid != uid) {
      throw StateError(
        'Usuario nao autenticado ou conta alterada.',
      );
    }
  }

  // Inicia a sincronizacao.
  Future<void> syncNotes(String uid) async {
    if (_isSyncing) {
      debugPrint('SINCRONIZACAO JA EM ANDAMENTO');
      return;
    }

    checkUser(uid);
    _isSyncing = true;

    try {
      debugPrint('INICIANDO SINCRONIZACAO');

      await uploadPendingNotes(uid);
      await downloadCloudNotes(uid);

      debugPrint('SINCRONIZACAO FINALIZADA');
    } catch (e) {
      debugPrint('ERRO NA SINCRONIZACAO: $e');

      throw Exception(
        'Falha na sincronizacao: $e',
      );
    } finally {
      _isSyncing = false;
    }
  }

  // Envia alteracoes locais ao Firebase.
  Future<void> uploadPendingNotes(String uid) async {
    checkUser(uid);

    final pendingNotes =
        await database.getPendingNotes(uid);

    debugPrint(
      'NOTAS PENDENTES: ${pendingNotes.length}',
    );

    for (final row in pendingNotes) {
      checkUser(uid);

      final id = row['id'] as int;
      final isDeleted = row['isDeleted'] == 1;
      final updatedAt = row['updatedAt'] as String;

      String? cloudId = row['cloudId'] as String?;

      final remoteUpdatedAt =
          row['remoteUpdatedAt'] as String?;

      // --------------------------------
      // EXCLUSOES PENDENTES
      // --------------------------------
      if (isDeleted) {
        if (cloudId == null) {
          await database.confirmDeletedNote(
            id,
            uid,
            updatedAt,
          );
          continue;
        }

        if (remoteUpdatedAt == null) {
          throw NoteConflictException(
            'Nao foi possivel verificar a versao '
            'da nota excluida $id. '
            'A exclusao foi preservada localmente.',
          );
        }

        await firestore.deleteNoteSafely(
          cloudId,
          expectedRemoteUpdatedAt:
              remoteUpdatedAt,
        );

        checkUser(uid);

        await database.confirmDeletedNote(
          id,
          uid,
          updatedAt,
        );

        debugPrint(
          'EXCLUSAO SINCRONIZADA: $id',
        );

        continue;
      }

      // --------------------------------
      // CRIACAO E EDICAO DE NOTAS
      // --------------------------------

      // Uma nota nova pode ja ter recebido
      // cloudId durante uma tentativa offline.
      // Portanto, somente cloudId nao indica
      // que a primeira sincronizacao terminou.
      final isNew = remoteUpdatedAt == null;

      // Se ainda nao existe identificador,
      // cria um identificador permanente.
      if (cloudId == null) {
        if (!isNew) {
          throw StateError(
            'Nota $id possui versao remota, '
            'mas nao possui cloudId.',
          );
        }

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

        if (assigned == 0) {
          debugPrint(
            'NOTA ALTERADA DURANTE O ENVIO: $id',
          );
          continue;
        }
      }

      final note = Note(
        id: id,
        uid: uid,
        title: row['title'] as String,
        content: row['content'] as String,
        date: row['date'] as String,
        cloudId: cloudId,
        category: row['category'] as String,
        updatedAt: updatedAt,
      );

      // A transacao verifica a nuvem.
      //
      // Se a nota ainda nao existe:
      // permite criar uma nota nova.
      //
      // Se ja existe com dados identicos:
      // permite confirmar envio anterior.
      //
      // Se existe com dados diferentes:
      // bloqueia o envio e preserva o SQLite.
      //
      // Para notas com versao conhecida,
      // exige que a versao remota seja igual.
      await firestore.saveNoteSafely(
        note,
        isNew: isNew,
        expectedRemoteUpdatedAt:
            remoteUpdatedAt,
      );

      checkUser(uid);

      final confirmed =
          await database.markNoteSynced(
        id,
        uid,
        cloudId,
        updatedAt,
      );

      if (confirmed == 1) {
        debugPrint(
          'NOTA SINCRONIZADA: $id',
        );
      } else {
        debugPrint(
          'NOTA ALTERADA DURANTE O ENVIO: $id',
        );
      }
    }
  }

  // Baixa notas da nuvem para o SQLite.
  Future<void> downloadCloudNotes(String uid) async {
    checkUser(uid);

    debugPrint('BUSCANDO NOTAS NO FIRESTORE');

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

      if (data['uid'] != uid) {
        debugPrint(
          'DOCUMENTO IGNORADO POR UID DIFERENTE',
        );
        continue;
      }

      final note = Note(
        cloudId: doc.id,
        uid: uid,
        title: data['title'] as String? ?? '',
        content: data['content'] as String? ?? '',
        date: data['date'] as String? ?? '',
        category:
            data['category'] as String? ?? 'Pessoal',
        updatedAt: data['updatedAt'] as String?,
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
