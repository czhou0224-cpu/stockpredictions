import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'UserProfileFirestoreService.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';




class EditProfilePage extends StatefulWidget {
  final String initialUsername;
  final String initialDisplayName;
  final String initialPfpUrl;

  const EditProfilePage({
    super.key,
    required this.initialUsername,
    required this.initialDisplayName,
    required this.initialPfpUrl,
  });

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late String username;
  late String displayName;
  late String pfpUrl;
  Future<void> _saveToFirestore({
    String? username,
    String? displayName,
    String? photoUrl,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await UserProfileFirestoreService().updateUserProfile(
      uid: user.uid,
      username: username,
      displayName: displayName,
      photoUrl: photoUrl,
    );
  }
  Future<void> _pickAndUploadPfp(ImageSource source) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 75, // compress
      maxWidth: 800,
    );

    if (picked == null) return;

    try {
      final file = File(picked.path);

      final ref = FirebaseStorage.instance
          .ref()
          .child('pfp')
          .child('${user.uid}.jpg');

      await ref.putFile(file);

      final url = await ref.getDownloadURL();

      setState(() {
        pfpUrl = url;
      });

      await _saveToFirestore(photoUrl: url);
    } catch (e) {
      print("❌ PFP upload failed: $e");
    }
  }
  @override
  void initState() {
    super.initState();
    username = widget.initialUsername;
    displayName = widget.initialDisplayName;
    pfpUrl = widget.initialPfpUrl;
  }

  void _changeUsername() {
    showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: username);
        return AlertDialog(
          backgroundColor: const Color(0xFF121212),
          title: const Text(
            "Change Username",
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: "Enter new username",
              hintStyle: TextStyle(color: Colors.white54),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white38),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.blueAccent),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () async {
                final newUsername = controller.text.trim();
                setState(() {
                  username = newUsername;
                });

                await _saveToFirestore(username: newUsername);

                if (!mounted) return;
                Navigator.pop(context);
              },
              child: const Text("Save", style: TextStyle(color: Colors.blueAccent)),
            ),
          ],
        );
      },
    );
  }

  void _changeDisplayName() {
    showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: displayName);
        return AlertDialog(
          backgroundColor: const Color(0xFF121212),
          title: const Text(
            "Change Name",
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: "Enter new name",
              hintStyle: TextStyle(color: Colors.white54),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white38),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.blueAccent),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () async {
                final newName = controller.text.trim();
                setState(() {
                  displayName = newName;
                });

                await _saveToFirestore(displayName: newName);

                if (!mounted) return;
                Navigator.pop(context);
              },
              child: const Text("Save", style: TextStyle(color: Colors.blueAccent)),
            ),
          ],
        );
      },
    );
  }

  void _changeProfilePicture() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.white),
                title: const Text("Take Photo", style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  await _pickAndUploadPfp(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.white),
                title: const Text("Choose From Gallery", style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  await _pickAndUploadPfp(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }
  void _saveAndReturn() {
    Navigator.pop(context, {
      'username': username,
      'displayName': displayName,
      'pfpUrl': pfpUrl,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          "Edit Profile",
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: _saveAndReturn,
            child: const Text(
              "Done",
              style: TextStyle(
                color: Colors.blueAccent,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
        child: Column(
          children: [
            const SizedBox(height: 20),

            CircleAvatar(
              radius: 60,
              backgroundImage: NetworkImage(pfpUrl),
            ),

            const SizedBox(height: 15),

            Text(
              "@$username",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              displayName,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 18,
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _changeProfilePicture,
                icon: const Icon(Icons.image, color: Colors.black),
                label: const Text(
                  "Change Profile Picture",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),

            const SizedBox(height: 15),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _changeUsername,
                icon: const Icon(Icons.edit, color: Colors.white),
                label: const Text(
                  "Change Username",
                  style: TextStyle(color: Colors.white),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white38),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),

            const SizedBox(height: 15),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _changeDisplayName,
                icon: const Icon(Icons.person, color: Colors.white),
                label: const Text(
                  "Change Name",
                  style: TextStyle(color: Colors.white),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white38),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
