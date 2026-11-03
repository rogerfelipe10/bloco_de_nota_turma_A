
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  // Sincroniza notas locais e notas da nuvem
  Future<void> syncNotes(String uid) async {
    if (_isSyncing) return;

    checkUser(uid);
    _isSyncing = true;

    try {
      // ETAPA 1: enviar alteracoes locais
      await uploadPendingNotes(uid);

      // ETAPA 2: recuperar notas da nuvem
      await downloadCloudNotes(uid);

    } catch (e) {
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

    for (final row in pendingNotes) {
      checkUser(uid);

      final id = row['id'] as int;
      final isDeleted = row['isDeleted'] == 1;
      final updatedAt = row['updatedAt'] as String;

      String? cloudId = row['cloudId'] as String?;

      // Sincroniza notas excluidas
      if (isDeleted) {
        if (cloudId != null) {
          await firestore.deleteNote(cloudId);
        }

        await database.confirmDeletedNote(
          id,
          uid,
          updatedAt,
        );

        continue;
      }

      // Gera um ID fixo para evitar duplicatas
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
          continue;
        }
      }

      // Converte o registro do SQLite em Note
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

      // Envia a nota para o Firebase
      await firestore.saveNote(note);

      checkUser(uid);

      // Marca a nota como sincronizada
      // somente se ela nao foi modificada
      await database.markNoteSynced(
        id,
        uid,
        cloudId,
        updatedAt,
      );
    }
  }

  // Recupera as notas armazenadas no Firestore
  Future<void> downloadCloudNotes(String uid) async {
    checkUser(uid);

    // Consulta os documentos no servidor.
    // Se o Firebase estiver inacessivel,
    // o erro sera tratado pelo syncNotes.
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notes')
        .get(
          const GetOptions(
            source: Source.server,
          ),
        );

    for (final doc in snapshot.docs) {
      checkUser(uid);

      final data = doc.data();

      // Confere que a nota pertence ao usuario
      if (data['uid'] != uid) {
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

      // Salva no SQLite sem duplicar registros
      // e sem sobrescrever alteracoes pendentes
      await database.saveRemoteNote(note);
    }
  }
}
