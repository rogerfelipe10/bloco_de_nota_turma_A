
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/note.dart';

class FirestoreService {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final FirebaseAuth _auth =
      FirebaseAuth.instance;

  // Acessa as notas do usuário autenticado
  CollectionReference<Map<String, dynamic>>
      _notesCollection() {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('Usuário não autenticado');
    }

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('notes');
  }

  // Envia uma nota ao Firestore
  Future<String> saveNote(Note note) async {
    final user = _auth.currentUser;

    if (user == null || user.uid != note.uid) {
      throw StateError('Usuário não autorizado');
    }

    final collection = _notesCollection();

    final document = note.cloudId == null
        ? collection.doc()
        : collection.doc(note.cloudId!);

    await document.set({
      'uid': note.uid,
      'title': note.title,
      'content': note.content,
      'date': note.date,
      'category': note.category,
      'updatedAt': note.updatedAt,
    });

    return document.id;
  }

  // Recupera as notas da nuvem
  Future<List<Note>> getNotes() async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('Usuário não autenticado');
    }

    final snapshot =
        await _notesCollection().get();

    return snapshot.docs.map((doc) {
      final data = doc.data();

      return Note(
        cloudId: doc.id,
        uid: user.uid,
        title: data['title'] ?? '',
        content: data['content'] ?? '',
        date: data['date'] ?? '',
        category: data['category'] ?? 'Pessoal',
        updatedAt: data['updatedAt'],
      );
    }).toList();
  }

  // Exclui uma nota da nuvem
  Future<void> deleteNote(String cloudId) async {
    await _notesCollection()
        .doc(cloudId)
        .delete();
  }
}
