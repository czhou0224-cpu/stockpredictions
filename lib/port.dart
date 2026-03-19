import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'alpha_vantage_service.dart';
import 'PortfolioFirestoreService.dart';

class Portfolio extends StatefulWidget {
  const Portfolio({super.key});

  @override
  State<Portfolio> createState() => _PortfolioState();
}

class _PortfolioState extends State<Portfolio> {
  final PortfolioFirestoreService _firestoreService = PortfolioFirestoreService();
  final AlphaVantageService _alphaService = AlphaVantageService();

  List<Map<String, dynamic>> holdings = [];

  StreamSubscription? _holdingsSub;

  // cache current prices
  final Map<String, double> _priceCache = {};

  bool _didInitialPriceLoad = false;
  bool _isRefreshingPrices = false;
  double totalChange = 0;
  double factor = 100.0;
  double roundedDouble = 0.0;

  final Set<String> _fetchingSymbols = {};

  @override
  void initState() {
    super.initState();
    _listenToHoldings();
  }

  @override
  void dispose() {
    _holdingsSub?.cancel();
    super.dispose();
  }

  void _listenToHoldings() {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      setState(() => holdings = []);
      return;
    }

    _holdingsSub?.cancel();
    _holdingsSub = _firestoreService.holdingsStream(user.uid).listen((snapshot) async {
      final newHoldings = snapshot.docs.map((doc) {
        final data = doc.data();

        final symbol = (data['symbol'] ?? doc.id).toString().toUpperCase();
        final qty = (data['qty'] as num?)?.toInt() ?? 0;

        // ✅ avg buy price stored in Firestore as buyPrice (weighted avg)
        final avgBuyPrice = (data['buyPrice'] as num?)?.toDouble() ?? 0.0;

        final currentPrice = _priceCache[symbol];

        // Current market value shown in holdings list
        final value = currentPrice != null && currentPrice > 0
            ? (qty * currentPrice).round()
        // fallback: show something reasonable instead of qty*100
            : (avgBuyPrice > 0 ? (qty * avgBuyPrice).round() : (qty * 100));

        double changePct = 0.0;
        double changeValue = 0.0;

        if (currentPrice != null && currentPrice > 0 && avgBuyPrice > 0 && qty > 0) {
          changeValue = (currentPrice - avgBuyPrice) * qty;
          changePct = ((currentPrice - avgBuyPrice) / avgBuyPrice) * 100.0;
        }

        return {
          "stock": symbol,
          "qty": qty,
          "value": value,
          "avgBuyPrice": avgBuyPrice, // kept for internal calc
          "changePct": double.parse(changePct.toStringAsFixed(2)),
          "changeValue": double.parse(changeValue.toStringAsFixed(2)),
        };
      }).toList();

      if (!mounted) return;
      setState(() => holdings = newHoldings);

      if (!_didInitialPriceLoad) {
        _didInitialPriceLoad = true;
        await _refreshPricesForMissingSymbols();
        return;
      }

      await _refreshPricesForMissingSymbols();
    }, onError: (_) {
      if (!mounted) return;
      _showSnack("Failed to load holdings from Firestore.");
    });
  }

  Future<void> _refreshPricesForMissingSymbols() async {
    if (_isRefreshingPrices) return;

    final symbols = holdings
        .map((h) => (h["stock"] ?? "").toString().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    final missing = symbols
        .where((s) => !_priceCache.containsKey(s) && !_fetchingSymbols.contains(s))
        .toList();

    if (missing.isEmpty) return;

    _isRefreshingPrices = true;
    _fetchingSymbols.addAll(missing);

    try {
      for (int i = 0; i < missing.length; i++) {
        final sym = missing[i];

        final price = await _alphaService.fetchCurrentPrice(sym);
        if (price != null && price > 0) {
          _priceCache[sym] = price;
        }

        if (i < missing.length - 1) {
          await Future.delayed(const Duration(milliseconds: 1300));
        }
      }

      if (!mounted) return;

      // ✅ Apply current prices AND recompute changePct/changeValue
      setState(() {
        holdings = holdings.map((h) {
          final sym = (h["stock"] ?? "").toString().toUpperCase();
          final qty = (h["qty"] as int?) ?? 0;
          final avgBuyPrice = (h["avgBuyPrice"] as num?)?.toDouble() ?? 0.0;

          final currentPrice = _priceCache[sym];
          if (currentPrice == null || currentPrice <= 0) return h;

          final value = (qty * currentPrice).round();

          double changePct = 0.0;
          double changeValue = 0.0;

          if (avgBuyPrice > 0 && qty > 0) {
            changeValue = (currentPrice - avgBuyPrice) * qty;
            totalChange = totalChange + changeValue;
            roundedDouble = (totalChange * factor).round() / factor;
            changePct = ((currentPrice - avgBuyPrice) / avgBuyPrice) * 100.0;
          }

          return {
            ...h,
            "value": value,
            "changePct": double.parse(changePct.toStringAsFixed(2)),
            "changeValue": double.parse(changeValue.toStringAsFixed(2)),
          };
        }).toList();
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst("Exception: ", "");
      _showSnack(msg.isNotEmpty ? msg : "Failed to load prices.");
    } finally {
      _fetchingSymbols.removeAll(missing);
      _isRefreshingPrices = false;
    }
  }

  double get portfolioValue {
    double total = 0;
    for (final h in holdings) {
      final value = (h["value"] as num?)?.toDouble() ?? 0;
      total += value;
    }
    return total;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ✅ builds % allocation per holding, in the same order as holdings list
  List<double> _allocationPercents() {
    final total = portfolioValue;
    if (total <= 0) return List.filled(holdings.length, 0.0);

    return holdings.map((h) {
      final v = (h["value"] as num?)?.toDouble() ?? 0.0;
      final pct = (v / total) * 100.0;
      return double.parse(pct.toStringAsFixed(2));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final total = portfolioValue;
    final alloc = _allocationPercents();

    // shrink bars as more holdings are added
    final int n = holdings.length;
    final double barWidth = (n <= 0)
        ? 14
        : (50.0 / n).clamp(6.0, 14.0); // more stocks => thinner bars

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(25, 20, 25, 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      "Portfolio",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 30,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      "Your Investments",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: () async {
                    final result = await showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.black,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
                      ),
                      builder: (_) => const AddStockSheet(),
                    );

                    if (!mounted) return;
                    if (result == null) return;

                    if (result is Map && result["error"] != null) {
                      _showSnack(result["error"].toString());
                      return;
                    }

                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) {
                      _showSnack("You must be logged in to add stocks.");
                      return;
                    }

                    try {
                      final symbol = (result["symbol"] as String).toUpperCase();
                      final name = (result["name"] as String?) ?? symbol;
                      final qty = (result["qty"] as int);

                      final buyPrice = (result["buyPrice"] as double?);
                      if (buyPrice == null || buyPrice <= 0) {
                        _showSnack("Please enter the stock purchase price.");
                        return;
                      }

                      await _firestoreService.upsertHolding(
                        uid: user.uid,
                        symbol: symbol,
                        name: name,
                        qty: qty,
                        buyPrice: buyPrice,
                      );
                    } catch (e) {
                      final msg = e.toString().replaceFirst("Exception: ", "");
                      _showSnack(msg.isNotEmpty ? msg : "Failed to save stock. Try again.");
                    }
                  },
                  child: const Icon(
                    Icons.add_circle,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 25),
            Expanded(
              flex: 6,
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.shade700,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 15, 20, 15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),
                      const Center(
                        child: Text(
                          "Portfolio Value",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "\$${total.toStringAsFixed(0)}",
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            "${roundedDouble >= 0 ? '+' : '-'}\$${roundedDouble.abs()}",
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Total Equity",
                            style: TextStyle(color: Colors.white54),
                          ),
                          Text(
                            "Unrealized Gains/Loses",
                            style: TextStyle(color: Colors.white54),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 9,
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 15, 20, 15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Your Holdings",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        flex: 4,
                        child: ListView.builder(
                          itemCount: holdings.length,
                          itemBuilder: (context, index) {
                            final h = holdings[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          h["stock"],
                                          style: const TextStyle(
                                            fontSize: 16,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          "${h["qty"]} Shares · \$${h["value"]}",
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        "${(h["changePct"] as num) > 0 ? "+" : ""}${h["changePct"]}%",
                                        style: TextStyle(
                                          color: (h["changePct"] as num) >= 0 ? Colors.green : Colors.red,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Text(
                                        "${(h["changeValue"] as num) >= 0 ? '+' : '-'}\$${(h["changeValue"] as num).abs()}",
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),


        // --- TOP 5 ALLOCATION BAR CHART (paste this whole Expanded where your old chart Expanded was) ---
        Expanded(
          flex: 5,
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Builder(
                builder: (context) {
                  final totalVal = portfolioValue;

                  final top = List.generate(holdings.length, (i) {
                    final sym = (holdings[i]["stock"] ?? "").toString();
                    final value = (holdings[i]["value"] as num?)?.toDouble() ?? 0.0;
                    final pct = totalVal > 0 ? (value / totalVal) * 100.0 : 0.0;
                    return {"sym": sym, "pct": pct};
                  })
                    ..sort((a, b) => (b["pct"] as double).compareTo(a["pct"] as double));

                  final top5 = top.take(5).toList();

                  final int n = top5.length;
                  final double barWidth = (n <= 0) ? 14 : (50.0 / n).clamp(6.0, 14.0);

                  return BarChart(
                    BarChartData(
                      maxY: 100,
                      minY: 0,
                      alignment: BarChartAlignment.spaceAround,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 25,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: Colors.white12,
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: const Border(
                          bottom: BorderSide(
                            color: Colors.white24,
                            width: 1.5,
                          ),
                        ),
                      ),
                      barTouchData: BarTouchData(enabled: false),
                      titlesData: FlTitlesData(
                        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 44,
                            interval: 25,
                            getTitlesWidget: (value, meta) {
                              return Text(
                                "${value.toStringAsFixed(0)}%",
                                style: const TextStyle(color: Colors.white54, fontSize: 11),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i < 0 || i >= top5.length) return const SizedBox.shrink();
                              final sym = top5[i]["sym"].toString();
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  sym,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: List.generate(top5.length, (i) {
                        final pct = (top5[i]["pct"] as double);
                        return BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: pct.clamp(0, 100),
                              width: barWidth,
                              borderRadius: BorderRadius.circular(0),
                              color: Colors.blueAccent,
                              backDrawRodData: BackgroundBarChartRodData(
                                show: true,
                                toY: 100,
                                color: Colors.white12,
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  );
                },
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

class AddStockSheet extends StatefulWidget {
  const AddStockSheet({super.key});

  @override
  State<AddStockSheet> createState() => _AddStockSheetState();
}

class _AddStockSheetState extends State<AddStockSheet> {
  final AlphaVantageService _alphaService = AlphaVantageService();

  final TextEditingController stockController = TextEditingController();
  final TextEditingController qtyController = TextEditingController();
  final TextEditingController purchasePriceController = TextEditingController();

  @override
  void dispose() {
    stockController.dispose();
    qtyController.dispose();
    purchasePriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "Add a Stock",
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: stockController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: "Stock Symbol",
              labelStyle: const TextStyle(color: Colors.white70),
              filled: true,
              fillColor: Colors.white12,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: qtyController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: "Quantity",
              labelStyle: const TextStyle(color: Colors.white70),
              filled: true,
              fillColor: Colors.white12,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: purchasePriceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: "Stock Market Value When Purchased",
              labelStyle: const TextStyle(color: Colors.white70, fontSize: 15),
              filled: true,
              fillColor: Colors.white12,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent.shade400,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () async {
                final input = stockController.text.trim();
                final qty = int.tryParse(qtyController.text) ?? 0;

                final buyText = purchasePriceController.text.trim();
                final buyPrice = double.tryParse(buyText);

                if (input.isEmpty || qty <= 0) return;

                if (buyText.isEmpty || buyPrice == null || buyPrice <= 0) {
                  Navigator.pop(context, {"error": "Please enter the purchase price."});
                  return;
                }

                try {
                  final result = await _alphaService.verifySymbol(input);

                  if (result == null) {
                    Navigator.pop(context, {"error": "Stock not found"});
                    return;
                  }

                  Navigator.pop(context, {
                    'symbol': result.symbol,
                    'name': result.name,
                    'qty': qty,
                    'buyPrice': buyPrice,
                  });
                } catch (e) {
                  final msg = e.toString().replaceFirst("Exception: ", "");
                  Navigator.pop(context, {"error": msg.isNotEmpty ? msg : "Something went wrong"});
                }
              },
              child: const Text(
                "Add to Portfolio",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
