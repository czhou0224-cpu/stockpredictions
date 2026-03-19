import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'signup.dart';
import 'homepage.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

final emailController = TextEditingController();
final passwordController = TextEditingController();

class _LoginPageState extends State<LoginPage> {
  void _showToast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.blueAccent.shade700,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top,
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  Row(
                    children: const [
                      SizedBox(width: 30),
                      Icon(Icons.arrow_back, color: Colors.white),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(25.0),
                        ),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 30),
                            Row(
                              children: const [
                                SizedBox(width: 45),
                                Text(
                                  "Login",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 35,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 40),
                            Padding(
                              padding:
                              const EdgeInsets.symmetric(horizontal: 40),
                              child: TextField(
                                controller: emailController,
                                style:
                                const TextStyle(color: Colors.white),
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  hintText: 'Enter your email',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Padding(
                              padding:
                              const EdgeInsets.symmetric(horizontal: 40),
                              child: TextField(
                                controller: passwordController,
                                style:
                                const TextStyle(color: Colors.white),
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'Password',
                                  hintText: 'Enter your password',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton(
                                  onPressed: () async {
                                    final email =
                                    emailController.text.trim();
                                    final password =
                                        passwordController.text;

                                    // ✅ NEW: local validation
                                    if (email.isEmpty &&
                                        password.isEmpty) {
                                      _showToast(
                                          'Please enter your email and password');
                                      return;
                                    }

                                    if (email.isEmpty) {
                                      _showToast(
                                          'Please enter your email');
                                      return;
                                    }

                                    if (password.isEmpty) {
                                      _showToast(
                                          'Please enter your password');
                                      return;
                                    }

                                    try {
                                      await FirebaseAuth.instance
                                          .signInWithEmailAndPassword(
                                        email: email,
                                        password: password,
                                      );

                                      Navigator.of(context).pushReplacement(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                          const Homepage(),
                                        ),
                                      );
                                    } on FirebaseAuthException catch (e) {
                                      if (e.code == 'invalid-email') {
                                        _showToast(
                                            'Email address is badly formatted');
                                      } else if (e.code ==
                                          'user-not-found') {
                                        _showToast(
                                            'No user found for that email');
                                      } else if (e.code ==
                                          'wrong-password') {
                                        _showToast('Wrong password');
                                      } else {
                                        _showToast(
                                            e.message ?? 'Login failed');
                                      }
                                    } catch (_) {
                                      _showToast('Something went wrong');
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    fixedSize:
                                    const Size(300, 50),
                                  ),
                                  child: const Text(
                                    "Login",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 25,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  "Don't have an account?",
                                  style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 18),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context)
                                        .pushReplacement(
                                      MaterialPageRoute(
                                        builder: (context) =>
                                        const Signup(),
                                      ),
                                    );
                                  },
                                  child: Text(
                                    "Sign Up",
                                    style: TextStyle(
                                      color: Colors.blueAccent
                                          .shade700,
                                      decoration:
                                      TextDecoration.underline,
                                      fontSize: 18,
                                    ),
                                  ),
                                )
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}