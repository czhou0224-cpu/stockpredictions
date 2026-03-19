import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:stockpredicitonsss/homepage.dart';
import 'login.dart';

class Signup extends StatefulWidget {
  const Signup({super.key});

  @override
  State<Signup> createState() => _SignupState();
}

class _SignupState extends State<Signup> {
  void showError(String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w400,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'OK',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  decoration: TextDecoration.underline,
                  color: Colors.blueAccent,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();
  bool isChecked = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    super.dispose();
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

                  // Back button row
                  Row(
                    children: [
                      const SizedBox(width: 20),
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Bottom panel expands to fill remaining space
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
                        // Allows form to scroll when keyboard shows
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 30),
                            Row(
                              children: const [
                                SizedBox(width: 45),
                                Text(
                                  "Sign Up",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 35,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 40),

                            // Full name
                            Padding(
                              padding:
                              const EdgeInsets.symmetric(horizontal: 40),
                              child: TextField(
                                style: const TextStyle(color: Colors.white),
                                controller: nameController,
                                decoration: const InputDecoration(
                                  fillColor: Colors.white70,
                                  labelText: 'Full Name',
                                  hintText: 'Enter your full name',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 7),

                            // Email
                            Padding(
                              padding:
                              const EdgeInsets.symmetric(horizontal: 40),
                              child: TextField(
                                controller: emailController,
                                style: const TextStyle(color: Colors.white),
                                decoration: const InputDecoration(
                                  fillColor: Colors.white70,
                                  labelText: 'Enter Email',
                                  hintText: 'Enter your preferred email',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 7),

                            // Password
                            Padding(
                              padding:
                              const EdgeInsets.symmetric(horizontal: 40),
                              child: TextField(
                                style: const TextStyle(color: Colors.white),
                                controller: passwordController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  fillColor: Colors.white70,
                                  labelText: 'Enter Password',
                                  hintText: 'Enter in a complex password',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Terms checkbox
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    isChecked
                                        ? Icons.check_box
                                        : Icons.check_box_outline_blank,
                                    size: 28,
                                    color: Colors.white,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      isChecked = !isChecked;
                                    });
                                  },
                                ),
                                const SizedBox(width: 10),
                                const Flexible(
                                  child: Padding(
                                    padding: EdgeInsets.only(right: 20),
                                    child: Text(
                                      "I agree with Terms of Service and Privacy Policy",
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 30),

                            // Sign up button
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton(
                                  onPressed: () async {
                                    if (emailController.text.isNotEmpty &&
                                        passwordController.text.isNotEmpty) {
                                      if (isChecked) {
                                        try {
                                          await FirebaseAuth.instance
                                              .createUserWithEmailAndPassword(
                                            email: emailController.text.trim(),
                                            password:
                                            passwordController.text.trim(),
                                          );
                                          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const Homepage()));
                                        } on FirebaseAuthException catch (e) {
                                          if (e.code == 'weak-password') {
                                            showError(
                                                'The password provided is too weak.');
                                          } else if (e.code ==
                                              'email-already-in-use') {
                                            showError(
                                                'An account already exists for that email.');
                                          } else {
                                            showError(e.message ??
                                                'Sign up failed. Please try again.');
                                          }
                                        } catch (e) {
                                          showError('Something went wrong.');
                                        }
                                      } else {
                                        showError(
                                            'Please check the box to agree.');
                                      }
                                    } else {
                                      showError(
                                          'Email and/or password cannot be empty');
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    fixedSize: const Size(300, 50),
                                  ),
                                  child: const Text(
                                    "Sign Up",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),

                            // Login link
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  "Already have an account?",
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 18,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) =>
                                        const LoginPage(),
                                      ),
                                    );
                                  },
                                  child: Text(
                                    "Login",
                                    style: TextStyle(
                                      color: Colors.blueAccent.shade700,
                                      decoration: TextDecoration.underline,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
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