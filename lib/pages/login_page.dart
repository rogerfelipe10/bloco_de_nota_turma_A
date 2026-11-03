
import 'package:bloco_de_nota_turma_a/pages/notes_page.dart';
import 'package:bloco_de_nota_turma_a/pages/register_page.dart';
import 'package:bloco_de_nota_turma_a/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  final AuthService authService = AuthService();

  bool loading = false;
  bool checkingSession = true;
  bool obscurePassword = true;

  @override
  void initState() {
    super.initState();

    // Confere se o Firebase ja possui uma
    // sessao autenticada salva no dispositivo.
    checkSavedSession();
  }

  Future<void> checkSavedSession() async {
    try {
      // Aguarda o Firebase restaurar a sessao.
      final user = await FirebaseAuth.instance
          .authStateChanges()
          .first;

      if (!mounted) return;

      if (user != null) {
        // A conta ja estava autenticada.
        // Abre as notas locais mesmo offline.
        openNotesPage();
        return;
      }
    } catch (e) {
      debugPrint(
        'Nao foi possivel restaurar a sessao: $e',
      );
    }

    if (mounted) {
      setState(() {
        checkingSession = false;
      });
    }
  }

  void openNotesPage() {
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const NotesPage(),
      ),
    );
  }

  Future<void> login() async {
    if (emailController.text.trim().isEmpty ||
        passwordController.text.isEmpty) {
      showMessage('Preencha todos os campos');
      return;
    }

    setState(() {
      loading = true;
    });

    try {
      final user = await authService.login(
        emailController.text.trim(),
        passwordController.text.trim(),
      );

      if (!mounted) return;

      if (user != null) {
        openNotesPage();
      } else {
        showMessage(
          'Nao foi possivel realizar o login',
        );
      }
    } catch (e) {
      if (!mounted) return;

      showMessage(
        'Nao foi possivel realizar o login. '
        'Verifique a conexao e os dados informados.',
      );

      debugPrint('Erro no login: $e');
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mostra carregamento enquanto verifica
    // se ja existe uma sessao autenticada.
    if (checkingSession) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8DDF8),
                      borderRadius:
                          BorderRadius.circular(26),
                    ),
                    child: const Icon(
                      Icons.edit_note_rounded,
                      size: 45,
                      color: Color(0xFF6C4AB6),
                    ),
                  ),
                ),

                const SizedBox(height: 35),

                const Text(
                  'Olá!',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF292333),
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Entre para acessar suas notas.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF77717F),
                  ),
                ),

                const SizedBox(height: 35),

                const Text(
                  'E-mail',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF40394A),
                  ),
                ),

                const SizedBox(height: 8),

                TextField(
                  controller: emailController,
                  keyboardType:
                      TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'seu@email.com',
                    prefixIcon:
                        Icon(Icons.email_outlined),
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Senha',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF40394A),
                  ),
                ),

                const SizedBox(height: 8),

                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  decoration: InputDecoration(
                    hintText: 'Digite sua senha',
                    prefixIcon: const Icon(
                      Icons.lock_outline,
                    ),
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() {
                          obscurePassword =
                              !obscurePassword;
                        });
                      },
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                ElevatedButton(
                  onPressed: loading ? null : login,
                  child: loading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child:
                              CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Entrar',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                ),

                const SizedBox(height: 20),

                Center(
                  child: TextButton(
                    onPressed: loading
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const RegisterPage(),
                              ),
                            );
                          },
                    child: const Text(
                      'Ainda não possui uma conta? '
                      'Cadastre-se',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
