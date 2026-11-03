
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/note.dart';

class NoteConflictException implements Exception {
  final String message;

  NoteConflictException(this.message);

  @override
  String toString() => message;
}

class FirestoreService {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final FirebaseAuth _auth =
      FirebaseAuth.instance;

  String _currentUid() {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('Usuario nao autenticado');
    }

    return user.uid;
  }

  CollectionReference<Map<String, dynamic>>
      _notesCollection() {
    return _firestore
        .collection('users')
        .doc(_currentUid())
        .collection('notes');
  }

  Map<String, dynamic> _noteData(Note note) {
    if (note.uid != _currentUid()) {
      throw StateError('Usuario nao autorizado');
    }

    return {
      'uid': note.uid,
      'title': note.title,
      'content': note.content,
      'date': note.date,
      'category': note.category,
      'updatedAt': note.updatedAt,
    };
  }

  // Mantido para compatibilidade.
  Future<String> saveNote(Note note) async {
    final data = _noteData(note);
    final collection = _notesCollection();

    final document = note.cloudId == null
        ? collection.doc()
        : collection.doc(note.cloudId!);

    await document.set(data);
    return document.id;
  }

  // Criacao ou edicao com verificacao de versao.
  Future<String> saveNoteSafely(
    Note note, {
    required bool isNew,
    required String? expectedRemoteUpdatedAt,
  }) async {
    if (note.cloudId == null) {
      throw ArgumentError('Nota sem cloudId');
    }

    final data = _noteData(note);
    final document =
        _notesCollection().doc(note.cloudId!);

    await _firestore.runTransaction(
      (transaction) async {
        final snapshot =
            await transaction.get(document);

        if (isNew) {
          if (snapshot.exists) {
            final remote = snapshot.data()!;

            final sameData =
                remote['uid'] == note.uid &&
                remote['title'] == note.title &&
                remote['content'] == note.content &&
                remote['date'] == note.date &&
                remote['category'] == note.category &&
                remote['updatedAt'] == note.updatedAt;

            if (!sameData) {
              throw NoteConflictException(
                'A nota ja existe na nuvem '
                'com dados diferentes.',
              );
            }

            return;
          }

          transaction.set(document, data);
          return;
        }

        if (!snapshot.exists) {
          throw NoteConflictException(
            'A nota foi excluida do Firebase.',
          );
        }

        final remote = snapshot.data()!;

        if (remote['uid'] != note.uid) {
          throw StateError('Usuario nao autorizado');
        }

        if (remote['updatedAt'] !=
            expectedRemoteUpdatedAt) {
          throw NoteConflictException(
            'A nota foi alterada em outro dispositivo.',
          );
        }

        transaction.set(document, data);
      },
    );

    return document.id;
  }

  // Exclusao com verificacao de versao.
  Future<void> deleteNoteSafely(
    String cloudId, {
    required String? expectedRemoteUpdatedAt,
  }) async {
    final uid = _currentUid();
    final document =
        _notesCollection().doc(cloudId);

    await _firestore.runTransaction(
      (transaction) async {
        final snapshot =
            await transaction.get(document);

        if (!snapshot.exists) return;

        final remote = snapshot.data()!;

        if (remote['uid'] != uid) {
          throw StateError('Usuario nao autorizado');
        }

        if (remote['updatedAt'] !=
            expectedRemoteUpdatedAt) {
          throw NoteConflictException(
            'A nota foi modificada antes da exclusao.',
          );
        }

        transaction.delete(document);
      },
    );
  }

  // Busca um documento diretamente no servidor.
  Future<Map<String, dynamic>?> getRemoteDocument(
    String cloudId,
  ) async {
    final uid = _currentUid();

    final snapshot =
        await _notesCollection().doc(cloudId).get(
      const GetOptions(source: Source.server),
    );

    if (!snapshot.exists) return null;

    final data = snapshot.data()!;

    if (data['uid'] != uid) {
      throw StateError('Usuario nao autorizado');
    }

    return data;
  }

  // Resolve conflito mantendo a versao do aplicativo.
  // Confere se a nuvem continua igual ao momento
  // em que a janela de conflito foi exibida.
  Future<void> resolveKeepingLocal(
    Note note, {
    required Map<String, dynamic> expectedRemote,
    required bool delete,
  }) async {
    if (note.cloudId == null) {
      throw ArgumentError('Nota sem cloudId');
    }

    final data = _noteData(note);
    final document =
        _notesCollection().doc(note.cloudId!);

    await _firestore.runTransaction(
      (transaction) async {
        final snapshot =
            await transaction.get(document);

        if (!snapshot.exists) {
          throw NoteConflictException(
            'A nota foi excluida da nuvem. '
            'Ela nao sera recriada automaticamente.',
          );
        }

        final current = snapshot.data()!;

        if (current['uid'] != note.uid) {
          throw StateError('Usuario nao autorizado');
        }

        // Confere o conteudo, nao apenas updatedAt.
        for (final field in [
          'uid',
          'title',
          'content',
          'date',
          'category',
          'updatedAt',
        ]) {
          if (current[field] != expectedRemote[field]) {
            throw NoteConflictException(
              'O Firebase mudou novamente. '
              'Sincronize para revisar o conflito.',
            );
          }
        }

        if (delete) {
          transaction.delete(document);
        } else {
          transaction.set(document, data);
        }
      },
    );
  }

  Future<List<Note>> getNotes() async {
    final uid = _currentUid();

    final snapshot = await _notesCollection().get(
      const GetOptions(source: Source.server),
    );

    return snapshot.docs.map((doc) {
      final data = doc.data();

      return Note(
        cloudId: doc.id,
        uid: uid,
        title: data['title'] as String? ?? '',
        content: data['content'] as String? ?? '',
        date: data['date'] as String? ?? '',
        category:
            data['category'] as String? ?? 'Pessoal',
        updatedAt: data['updatedAt'] as String?,
      );
    }).toList();
  }

  // Mantido para compatibilidade.
  Future<void> deleteNote(String cloudId) async {
    await _notesCollection().doc(cloudId).delete();
  }
}
