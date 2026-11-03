
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/note.dart';

// Erro específico quando existem alterações concorrentes.
class NoteConflictException implements Exception {
  final String message;

  NoteConflictException(this.message);

  @override
  String toString() => message;
}

class FirestoreService {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _currentUid() {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('Usuario nao autenticado');
    }

    return user.uid;
  }

  CollectionReference<Map<String, dynamic>>
      _notesCollection() {
    final uid = _currentUid();

    return _firestore
        .collection('users')
        .doc(uid)
        .collection('notes');
  }

  // Converte a nota em dados para o Firestore.
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

  // Metodo atual, mantido temporariamente
  // para nao quebrar o SyncService existente.
  Future<String> saveNote(Note note) async {
    final collection = _notesCollection();
    final data = _noteData(note);

    final document = note.cloudId == null
        ? collection.doc()
        : collection.doc(note.cloudId!);

    await document.set(data);

    return document.id;
  }

  // Novo metodo: salva uma nota com verificacao
  // da versao conhecida pelo dispositivo.
  Future<String> saveNoteSafely(
    Note note, {
    required bool isNew,
    required String? expectedRemoteUpdatedAt,
  }) async {
    if (note.cloudId == null) {
      throw ArgumentError(
        'A nota precisa de cloudId antes do envio',
      );
    }

    final data = _noteData(note);

    final document =
        _notesCollection().doc(note.cloudId!);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(document);

      // Nota que ainda nao existe na nuvem.
      if (isNew) {
        if (snapshot.exists) {
          final remote = snapshot.data()!;

          // Permite repetir um envio ja confirmado
          // pelo servidor, mas nao pelo SQLite.
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

      // Uma atualizacao exige que a nota exista.
      if (!snapshot.exists) {
        throw NoteConflictException(
          'A nota foi excluida da nuvem.',
        );
      }

      final remote = snapshot.data()!;

      if (remote['uid'] != note.uid) {
        throw NoteConflictException(
          'A nota pertence a outro usuario.',
        );
      }

      // Compara a versao conhecida pelo aplicativo
      // com a versao que existe no Firestore.
      if (remote['updatedAt'] !=
          expectedRemoteUpdatedAt) {
        throw NoteConflictException(
          'A nota foi alterada em outro dispositivo.',
        );
      }

      transaction.set(document, data);
    });

    return document.id;
  }

  // Recupera as notas da nuvem.
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

  // Metodo de exclusao atual.
  // Mantido ate atualizarmos o SyncService.
  Future<void> deleteNote(String cloudId) async {
    await _notesCollection().doc(cloudId).delete();
  }

  // Novo metodo: exclusao com verificacao
  // da versao armazenada na nuvem.
  Future<void> deleteNoteSafely(
    String cloudId, {
    required String? expectedRemoteUpdatedAt,
  }) async {
    final uid = _currentUid();
    final document = _notesCollection().doc(cloudId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(document);

      // Se ja foi excluida, nao ha nada a fazer.
      if (!snapshot.exists) return;

      final remote = snapshot.data()!;

      if (remote['uid'] != uid) {
        throw NoteConflictException(
          'Usuario nao autorizado.',
        );
      }

      if (remote['updatedAt'] !=
          expectedRemoteUpdatedAt) {
        throw NoteConflictException(
          'A nota foi modificada antes da exclusao.',
        );
      }

      transaction.delete(document);
    });
  }
}
