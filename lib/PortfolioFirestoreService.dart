import 'package:cloud_firestore/cloud_firestore.dart';

class PortfolioFirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Adds to existing qty if the stock already exists.
  /// buyPrice is REQUIRED and is stored as the WEIGHTED AVERAGE buy price.
  ///
  /// If doc exists:
  /// newAvg = (oldAvg * oldQty + newBuyPrice * addedQty) / (oldQty + addedQty)
  Future<void> upsertHolding({
    required String uid,
    required String symbol,
    required String name,
    required int qty,
    required double buyPrice,
  }) async {
    final upper = symbol.toUpperCase();
    final docRef = _db.collection('users').doc(uid).collection('stocks').doc(upper);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(docRef);

      final currentQty =
      snap.exists ? ((snap.data()?['qty'] as num?)?.toInt() ?? 0) : 0;

      final currentAvg =
      snap.exists ? ((snap.data()?['buyPrice'] as num?)?.toDouble() ?? 0) : 0.0;

      final newQty = currentQty + qty;

      // Weighted average buy price (only if we already have an existing position)
      final double newAvgBuyPrice;
      if (snap.exists && currentQty > 0 && currentAvg > 0) {
        newAvgBuyPrice =
            ((currentAvg * currentQty) + (buyPrice * qty)) / newQty;
      } else {
        // First time buy or missing old data
        newAvgBuyPrice = buyPrice;
      }

      if (snap.exists) {
        tx.update(docRef, {
          'qty': newQty,
          'name': name,
          'symbol': upper,
          'buyPrice': newAvgBuyPrice, // ✅ store as weighted avg
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        tx.set(docRef, {
          'symbol': upper,
          'name': name,
          'qty': newQty,
          'buyPrice': newAvgBuyPrice, // ✅ store as weighted avg
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Future<void> deleteHolding({
    required String uid,
    required String symbol,
  }) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('stocks')
        .doc(symbol.toUpperCase())
        .delete();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> holdingsStream(String uid) {
    return _db.collection('users').doc(uid).collection('stocks').snapshots();
  }

  Stream<List<Map<String, dynamic>>> streamHoldings(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('stocks')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((d) => d.data()).toList());
  }
}