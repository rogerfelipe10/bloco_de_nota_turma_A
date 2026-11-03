
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

  // Verifica se o usuario continua autenticado
  void checkUser(String uid) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || user.uid != uid) {
      throw StateError(
        'Usuario nao autenticado ou conta alterada',
      );
    }
  }

  // Sincroniza notas locais e notas do Firebase
  Future<void> syncNotes(String uid) async {
    if (_isSyncing) {
      debugPrint('SINCRONIZACAO JA EM ANDAMENTO');
      return;
    }

    checkUser(uid);
    _isSyncing = true;

    try {
      debugPrint('INICIANDO SINCRONIZACAO');

      // Envia as alteracoes locais
      await uploadPendingNotes(uid);

      // Recupera as notas da nuvem
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

  // Envia notas pendentes ao Firestore
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

      // Envia exclusoes pendentes
      if (isDeleted) {
        if (cloudId != null) {
          await firestore.deleteNote(cloudId);
        }

        checkUser(uid);

        await database.confirmDeletedNote(
          id,
          uid,
          updatedAt,
        );

        continue;
      }

      // Cria identificador permanente na nuvem
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

        if (assigned == 0) {
          debugPrint(
            'NAO FOI POSSIVEL ATRIBUIR CLOUD ID: $id',
          );
          continue;
        }
      }

      // Converte os dados locais em Note
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

      // Envia para o Firebase
      await firestore.saveNote(note);

      checkUser(uid);

      // Confirma a sincronizacao
      await database.markNoteSynced(
        id,
        uid,
        cloudId,
        updatedAt,
      );
    }
  }

  // Recupera notas do Firebase para o SQLite
  Future<void> downloadCloudNotes(String uid) async {
    checkUser(uid);

    debugPrint('BUSCANDO NOTAS NO FIRESTORE');

    // Consulta o servidor, nao apenas o cache local
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

    // Identificadores existentes na nuvem
    final remoteIds = snapshot.docs
        .map((doc) => doc.id)
        .toSet();

    debugPrint(
      'DOCUMENTOS EXISTENTES NO FIRESTORE: ${remoteIds.length}',
    );

    // Recupera notas da nuvem
    for (final doc in snapshot.docs) {
      checkUser(uid);

      final data = doc.data();

      if (data['uid'] != uid) {
        debugPrint(
          'DOCUMENTO IGNORADO POR UID DIFERENTE: ${doc.id}',
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

    // Remove notas locais que nao existem mais no Firebase
    final removed = await database.removeMissingCloudNotes(
      uid,
      remoteIds,
    );

    debugPrint(
      'NOTAS REMOVIDAS DO SQLITE: $removed',
    );
  }
}
