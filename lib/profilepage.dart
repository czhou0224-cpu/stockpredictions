import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:stockpredicitonsss/login.dart';
import 'package:stockpredicitonsss/security.dart';
import 'editprofile.dart';
import 'package:stockpredicitonsss/UserProfileFirestoreService.dart';
import 'package:stockpredicitonsss/PortfolioFirestoreService.dart';
import 'package:stockpredicitonsss/finnhub_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // ✅ Profile is now the single source of truth for name + pfp
  String username = "charZ"; // handle (shown as @username)
  String displayName = "Char Z"; // big name text
  String pfpUrl =
      'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQLN5vl60jUiaXISUA1N8sGtf-6TsDsEWXRUDiLNB6D7kE0o4zcMnJ4r9CFXzJR9XRvoO_i2glF5EOss84mZgqi291Smb1m2RJKCELUdqy5&s=10';

  int totalStocks = 0;
  int daysOnApp = 128;
  double totalProfit = 0.0;

  final PortfolioFirestoreService _portfolioService = PortfolioFirestoreService();
  final FinnhubService _finnhubService = FinnhubService();
  final Map<String, double> _priceCache = {};
  StreamSubscription? _holdingsSub;

  String getRank() {
    if (totalProfit >= 50000) return "Diamond";
    if (totalProfit >= 30000) return "Emerald";
    if (totalProfit >= 15000) return "Platinum";
    if (totalProfit >= 5000) return "Gold";
    if (totalProfit >= 1000) return "Silver";
    return "Bronze";
  }

  Color getRankColor() {
    switch (getRank()) {
      case "Diamond":
        return Colors.blueAccent;
      case "Emerald":
        return const Color(0xFF50C878);
      case "Platinum":
        return Colors.blueGrey;
      case "Gold":
        return Colors.amber;
      case "Silver":
        return Colors.grey;
      default:
        return Colors.brown;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _listenToHoldings();
  }

  @override
  void dispose() {
    _holdingsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final creationTime = user.metadata.creationTime;
    final computedDaysOnApp = creationTime == null
        ? 0
        : DateTime.now().difference(creationTime).inDays.clamp(0, 999999);

    final service = UserProfileFirestoreService();
    final data = await service.getUserProfile(user.uid);

    // If doc doesn't exist, create it
    if (data == null) {
      await service.createUserIfNotExists(
        uid: user.uid,
        username: username,
        displayName: displayName,
        photoUrl: pfpUrl,
      );
      return;
    }

    // ✅ Backfill missing fields for existing docs
    final hasUsername =
        data['username'] != null && data['username'].toString().trim().isNotEmpty;
    final hasDisplayName = data['displayName'] != null &&
        data['displayName'].toString().trim().isNotEmpty;
    final hasPhotoUrl =
        data['photoUrl'] != null && data['photoUrl'].toString().trim().isNotEmpty;

    if (!hasUsername || !hasDisplayName || !hasPhotoUrl) {
      await service.updateUserProfile(
        uid: user.uid,
        username: hasUsername ? null : username,
        displayName: hasDisplayName ? null : displayName,
        photoUrl: hasPhotoUrl ? null : pfpUrl,
      );
    }

    // Re-fetch after possible backfill so UI uses stored values
    final fresh = await service.getUserProfile(user.uid);
    if (fresh == null) return;

    if (!mounted) return;

    setState(() {
      username = (fresh['username'] ?? username).toString();
      displayName = (fresh['displayName'] ?? displayName).toString();
      pfpUrl = (fresh['photoUrl'] ?? pfpUrl).toString();
      daysOnApp = computedDaysOnApp;
    });
  }

  void _listenToHoldings() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        totalStocks = 0;
        totalProfit = 0.0;
      });
      return;
    }

    _holdingsSub?.cancel();
    _holdingsSub = _portfolioService.holdingsStream(user.uid).listen((snapshot) async {
      final holdings = snapshot.docs.map((doc) => doc.data()).toList();
      final symbols = holdings
          .map((h) => (h['symbol'] ?? '').toString().toUpperCase())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();

      await _refreshMissingPrices(symbols);
      if (!mounted) return;

      double unrealized = 0.0;
      for (final h in holdings) {
        final symbol = (h['symbol'] ?? '').toString().toUpperCase();
        final qty = (h['qty'] as num?)?.toDouble() ?? 0.0;
        final avgBuyPrice = (h['buyPrice'] as num?)?.toDouble() ?? 0.0;
        final currentPrice = _priceCache[symbol];

        if (qty > 0 && avgBuyPrice > 0 && currentPrice != null && currentPrice > 0) {
          unrealized += (currentPrice - avgBuyPrice) * qty;
        }
      }

      setState(() {
        // Number of stock entries user has added.
        totalStocks = holdings.length;
        totalProfit = double.parse(unrealized.toStringAsFixed(2));
      });
    });
  }

  Future<void> _refreshMissingPrices(List<String> symbols) async {
    final missing = symbols.where((s) => !_priceCache.containsKey(s)).toList();
    for (int i = 0; i < missing.length; i++) {
      final symbol = missing[i];
      try {
        final price = await _finnhubService.fetchCurrentPrice(symbol);
        if (price != null && price > 0) {
          _priceCache[symbol] = price;
        }
      } catch (_) {
        // Keep going if one quote fails.
      }

      if (i < missing.length - 1) {
        await Future.delayed(const Duration(milliseconds: 1200));
      }
    }
  }

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {}

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => LoginPage()),
          (route) => false,
    );
  }

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
                'No',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  decoration: TextDecoration.underline,
                  color: Colors.blueAccent,
                ),
              ),
            ),
            TextButton(
              onPressed: _logout,
              child: const Text(
                'Yes',
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

  Future<void> _openEditProfile() async {
    final result = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (context) => EditProfilePage(
          initialUsername: username,
          initialDisplayName: displayName,
          initialPfpUrl: pfpUrl,
        ),
      ),
    );

    if (result == null) return;

    setState(() {
      username = result['username'] ?? username;
      displayName = result['displayName'] ?? displayName;
      pfpUrl = result['pfpUrl'] ?? pfpUrl;
    });
  }

  Future<void> _openSecurityPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => securityPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SingleChildScrollView(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: const [
                SizedBox(width: 10),
                Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    "Profile",
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            CircleAvatar(
              radius: 50,
              backgroundImage: NetworkImage(pfpUrl),
            ),
            const SizedBox(height: 15),
            Text(
              displayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              "@$username",
              style: const TextStyle(color: Colors.white70, fontSize: 18),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: getRankColor().withOpacity(0.2),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: getRankColor(), width: 2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.emoji_events, color: getRankColor(), size: 30),
                  const SizedBox(width: 10),
                  Text(
                    "${getRank()} Rank",
                    style: TextStyle(
                      color: getRankColor(),
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(20),
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  statTile("Total Stocks Owned", totalStocks.toString(),
                      Icons.inventory),
                  const SizedBox(height: 20),
                  statTile("Days on App", daysOnApp.toString(),
                      Icons.calendar_today),
                  const SizedBox(height: 20),
                  statTile(
                    "Total Profit",
                    "\$${totalProfit.toStringAsFixed(2)}",
                    Icons.trending_up,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 35),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Account Settings",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      Icon(Icons.person, color: Colors.blueAccent.shade700),
                      const SizedBox(width: 5),
                      TextButton(
                        onPressed: _openEditProfile,
                        child: const Text(
                          "Edit Profile",
                          style: TextStyle(color: Colors.white, fontSize: 18),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Icon(Icons.shield_outlined,
                          color: Colors.blueAccent.shade700),
                      const SizedBox(width: 5),
                      TextButton(
                        onPressed: _openSecurityPage,
                        child: const Text(
                          "Security",
                          style: TextStyle(color: Colors.white, fontSize: 18),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Icon(Icons.logout, color: Colors.redAccent),
                      const SizedBox(width: 5),
                      TextButton(
                        onPressed: () {
                          showError("Are you sure you want to log out?");
                        },
                        child: const Text(
                          "Logout",
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget statTile(String title, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.blueAccent.shade700, size: 35),
        const SizedBox(width: 15),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(color: Colors.white70, fontSize: 18),
            ),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        )
      ],
    );
  }
}