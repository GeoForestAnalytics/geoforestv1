// lib/pages/menu/login_page.dart (CORREÇÃO DE LÓGICA NO LOGIN)

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geoforestv1/services/auth_service.dart';
import 'package:geoforestv1/pages/menu/register_page.dart';
import 'package:geoforestv1/pages/menu/forgot_password_page.dart';
import 'package:flutter_animate/flutter_animate.dart'; // ADICION
import 'package:google_fonts/google_fonts.dart';

const Color primaryColor = Color.fromARGB(255, 13, 58, 89);
const Color secondaryTextColor = Color.fromARGB(255, 19, 98, 151);
const Color backgroundColor = Color(0xFFF3F3F4);

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      await _authService.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      // A navegação agora é controlada pelo `Consumer` no `main.dart`
      // if (!mounted) return;
      // Navigator.pushReplacementNamed(context, '/equipe');
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Ocorreu um erro. Tente novamente.';
      if (e.code == 'user-not-found' ||
          e.code == 'invalid-email' ||
          e.code == 'invalid-credential') {
        errorMessage = 'Email ou senha inválidos.';
      } else if (e.code == 'wrong-password') {
        errorMessage = 'Senha incorreta. Por favor, tente novamente.';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Erro ao fazer login: ${e.toString()}'),
            backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loginTeste() async {
    setState(() => _isLoading = true);
    try {
      await _authService.signInWithEmailAndPassword(
        email: 'teste@geoforest.com',
        password: '123456',
      );
      // A navegação agora é controlada pelo `Consumer` no `main.dart`
      // if (!mounted) return;
      // Navigator.pushReplacementNamed(context, '/equipe');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro no login teste: ${e.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Cores do tema
    final Color corDourada = const Color(0xFFEBE4AB);
    final Color corAzulEscura = const Color(0xFF023853);

    return Scaffold(
      // Fundo Gradiente
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [corDourada, corAzulEscura], // O mesmo gradiente do Tabarro
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // --- 1. LOGO ANIMADO ---
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                        color: Colors
                            .white, // Fundo branco para o logo aparecer bem
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 10))
                        ]),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(100),
                      child: Image.asset(
                        'assets/images/icon_azul.png', // Verifique se é esse o nome
                        width: 100, height: 100, fit: BoxFit.contain,
                      ),
                    ),
                  )
                      .animate()
                      .scale(
                          duration: 600.ms,
                          curve: Curves.easeOutBack) // Zoom in
                      .shimmer(
                          delay: 1.seconds, duration: 1.5.seconds), // Brilho

                  const SizedBox(height: 32),

                  // --- 2. TEXTOS ---
                  Text(
                    'GEO FOREST',
                    style: GoogleFonts.montserrat(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: corAzulEscura,
                      letterSpacing: 2,
                    ),
                  ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.3, end: 0),

                  Text(
                    'Analytics',
                    style: GoogleFonts.montserrat(
                      fontSize: 20,
                      fontWeight: FontWeight.w300,
                      color: corAzulEscura,
                      letterSpacing: 5,
                    ),
                  ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.3, end: 0),

                  const SizedBox(height: 40),

                  // --- 3. CARD DE LOGIN (VIDRO/BRANCO) ---
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95), // Quase branco
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black26,
                              blurRadius: 15,
                              offset: const Offset(0, 5))
                        ]),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: TextStyle(color: corAzulEscura),
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              /* ... seu validador ... */ return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            style: TextStyle(color: corAzulEscura),
                            decoration: InputDecoration(
                              labelText: 'Senha',
                              prefixIcon: const Icon(Icons.lock_outlined),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined),
                                onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword),
                              ),
                            ),
                            validator: (value) {
                              /* ... seu validador ... */ return null;
                            },
                          ),

                          const SizedBox(height: 10),
                          // Botão Esqueci Senha e Dev
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (kDebugMode)
                                TextButton(
                                  onPressed: _isLoading ? null : _loginTeste,
                                  child: const Text('Dev Login',
                                      style: TextStyle(fontSize: 12)),
                                ),
                              TextButton(
                                onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) =>
                                            const ForgotPasswordPage())),
                                child: const Text('Esqueci minha senha'),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: corAzulEscura,
                                foregroundColor: corDourada, // Texto Dourado
                                elevation: 0,
                              ),
                              child: _isLoading
                                  ? const CircularProgressIndicator(
                                      color: Colors.white)
                                  : const Text('ENTRAR'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 600.ms)
                      .slideY(begin: 0.2, end: 0), // Card sobe

                  const SizedBox(height: 32),

                  OutlinedButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const RegisterPage())),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: corAzulEscura, width: 2),
                      foregroundColor: corAzulEscura,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 30, vertical: 15),
                    ),
                    child: const Text('CRIAR NOVA CONTA',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ).animate().fadeIn(delay: 800.ms),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
