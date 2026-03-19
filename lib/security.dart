import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'UserProfileFirestoreService.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';


import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class securityPage extends StatefulWidget {
  const securityPage({super.key});

  @override
  State<securityPage> createState() => _securityPageState();
}

class _securityPageState extends State<securityPage> {
  final TextEditingController _passwordController = TextEditingController();
  bool _loading = false;
  String? _message;

  Future<void> _updatePassword() async {
    setState(() {
      _message = null;
      _loading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw "Not logged in.";

      final newPassword = _passwordController.text.trim();

      if (newPassword.length < 6) {
        throw "Password must be at least 6 characters.";
      }

      // Update password in Firebase Auth
      await user.updatePassword(newPassword);

      // Optional: store timestamp in Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'passwordUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      setState(() {
        _message = "✅ Password updated.";
        _passwordController.clear();
      });
    } catch (e) {
      setState(() {
        _message = "❌ ${e.toString().replaceFirst('Exception: ', '')}";
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          "Security",
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: _passwordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "New Password",
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white38),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.blueAccent),
                ),
              ),
            ),
            const SizedBox(height: 20),

            if (_message != null)
              Text(
                _message!,
                style: TextStyle(
                  color: _message!.startsWith("✅")
                      ? Colors.greenAccent
                      : Colors.redAccent,
                ),
              ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _updatePassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  _loading ? "Updating..." : "Update Password",
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
