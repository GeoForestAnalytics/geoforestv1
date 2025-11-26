// lib/pages/menu/register_page.dart (VERSÃO FINAL - VISUAL PREMIUM)

import 'package:flutter/material.dart';
import 'package:geoforestv1/services/auth_service.dart';
import 'package:google_fonts/google_fonts.dart'; // Fonte
import 'package:flutter_animate/flutter_animate.dart'; // Animações

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _authService.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        displayName: _nameController.text.trim(),
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Conta criada com sucesso! Você já pode fazer login.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Cores do Tema Premium
    final Color corDourada = const Color(0xFFEBE4AB);
    final Color corAzulEscura = const Color(0xFF023853);

    return Scaffold(
      extendBodyBehindAppBar: true, // Faz o gradiente ir até o topo
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: corAzulEscura), // Seta escura para ver no dourado
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [corDourada, corAzulEscura],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  // --- 1. LOGO MENOR (ANIMADO) ---
                  Container(
                    width: 80,
                    height: 80,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(50),
                      child: Image.asset(
                        'assets/images/icon_azul.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),

                  const SizedBox(height: 24),

                  // --- 2. TÍTULOS ---
                  Text(
                    'CRIAR CONTA',
                    style: GoogleFonts.montserrat(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: corAzulEscura, // Contraste com o fundo dourado do topo
                      letterSpacing: 1.5,
                    ),
                  ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.3, end: 0),

                  const SizedBox(height: 8),
                  
                  Text(
                    'Preencha os dados para começar',
                    style: GoogleFonts.montserrat(
                      fontSize: 14,
                      color: corAzulEscura.withOpacity(0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ).animate().fadeIn(delay: 300.ms),

                  const SizedBox(height: 30),

                  // --- 3. CARD DO FORMULÁRIO ---
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          // Campo Nome
                          TextFormField(
                            controller: _nameController,
                            style: TextStyle(color: corAzulEscura),
                            decoration: InputDecoration(
                              labelText: 'Nome completo',
                              prefixIcon: Icon(Icons.person_outlined, color: corAzulEscura),
                              border: const OutlineInputBorder(),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: corAzulEscura.withOpacity(0.3)),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: corAzulEscura, width: 2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              labelStyle: TextStyle(color: corAzulEscura),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'Por favor, insira seu nome';
                              if (value.length < 2) return 'Nome deve ter pelo menos 2 caracteres';
                              return null;
                            },
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Campo Email
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: TextStyle(color: corAzulEscura),
                            decoration: InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined, color: corAzulEscura),
                              border: const OutlineInputBorder(),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: corAzulEscura.withOpacity(0.3)),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: corAzulEscura, width: 2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              labelStyle: TextStyle(color: corAzulEscura),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'Por favor, insira seu email';
                              final bool emailValido = RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~-]+@[a-zA-Z0-9]+\.[a-zA-Z]+").hasMatch(value);
                              if (!emailValido) return 'Por favor, insira um email válido';
                              return null;
                            },
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Campo Senha
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            style: TextStyle(color: corAzulEscura),
                            decoration: InputDecoration(
                              labelText: 'Senha',
                              prefixIcon: Icon(Icons.lock_outlined, color: corAzulEscura),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                  color: corAzulEscura,
                                ),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                              border: const OutlineInputBorder(),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: corAzulEscura.withOpacity(0.3)),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: corAzulEscura, width: 2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              labelStyle: TextStyle(color: corAzulEscura),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'Por favor, insira uma senha';
                              if (value.length < 6) return 'A senha deve ter pelo menos 6 caracteres';
                              return null;
                            },
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Campo Confirmar Senha
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: _obscureConfirmPassword,
                            style: TextStyle(color: corAzulEscura),
                            decoration: InputDecoration(
                              labelText: 'Confirmar senha',
                              prefixIcon: Icon(Icons.lock_reset_outlined, color: corAzulEscura),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                  color: corAzulEscura,
                                ),
                                onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                              ),
                              border: const OutlineInputBorder(),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: corAzulEscura.withOpacity(0.3)),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: corAzulEscura, width: 2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              labelStyle: TextStyle(color: corAzulEscura),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'Por favor, confirme sua senha';
                              if (value != _passwordController.text) return 'As senhas não coincidem';
                              return null;
                            },
                          ),
                          
                          const SizedBox(height: 32),
                          
                          // Botão Criar Conta
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _register,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: corAzulEscura,
                                foregroundColor: corDourada, // Texto Dourado
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                textStyle: GoogleFonts.montserrat(
                                  fontWeight: FontWeight.bold, 
                                  fontSize: 16
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('CRIAR CONTA'),
                            ),
                          ),
                          
                          const SizedBox(height: 24),
                          
                          // Link para Login
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Já tem uma conta? ',
                                style: TextStyle(color: Colors.grey[700]),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(
                                  'Fazer login',
                                  style: TextStyle(
                                    color: corAzulEscura,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.2, end: 0),
                  
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}