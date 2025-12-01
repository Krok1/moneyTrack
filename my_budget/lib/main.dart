import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';

// --- КОНСТАНТИ ---
// !!! ВСТАВТЕ СЮДИ АДРЕСУ ВАШОГО РОЗГОРНУТОГО СЕРВЕРА Render !!!
const String API_URL = "https://my-budget-core-api.onrender.com"; 

void main() {
  runApp(const BudgetApp());
}

class BudgetApp extends StatelessWidget {
  const BudgetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Мій Бюджет',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: const Color(0xFFBB86FC), 
        useMaterial3: true,
        textTheme: GoogleFonts.manropeTextTheme(ThemeData.dark().textTheme),
      ),
      home: const DashboardPage(),
    );
  }
}

// --- СЕРВІСИ (Виклики до Python API) ---

// 1. Отримання транзакцій з Monobank
Future<List<dynamic>> fetchMonoTransactions() async {
  try {
    final response = await http.get(Uri.parse('$API_URL/mono-transactions'));

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final error = json.decode(response.body)['detail'] ?? 'Невідома помилка';
      throw Exception('Помилка Monobank API: $error');
    }
  } catch (e) {
    throw Exception('Помилка мережі: $e');
  }
}

// 2. Сканування чека через Gemini API
Future<Map<String, dynamic>> scanReceipt() async {
  final picker = ImagePicker();
  final XFile? photo = await picker.pickImage(source: ImageSource.camera);

  if (photo == null) return {};

  try {
    var request = http.MultipartRequest('POST', Uri.parse('$API_URL/scan-receipt'));
    
    // Додаємо файл до запиту
    request.files.add(
      await http.MultipartFile.fromPath('file', photo.path),
    );

    var streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final error = json.decode(response.body)['detail'] ?? 'Невідома помилка';
      throw Exception('Помилка сканування: $error');
    }
  } catch (e) {
    throw Exception('Помилка відправки фото: $e');
  }
}

// --- UI (ІНТЕРФЕЙС) ---

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Future<List<dynamic>>? _transactionsFuture;

  @override
  void initState() {
    super.initState();
    _transactionsFuture = fetchMonoTransactions();
  }

  void _handleScanReceipt() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Сканую чек... Це може зайняти кілька секунд.')),
    );

    try {
      final receiptData = await scanReceipt();
      
      // Показуємо результат сканування у діалоговому вікні
      if (receiptData.isNotEmpty) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Результат сканування (AI)'),
              content: SelectableText(json.encode(receiptData), style: const TextStyle(fontSize: 12)),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ОК')),
                // Тут можна додати кнопку "Зберегти" і логіку збереження в базу
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Помилка: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Мій Бюджет", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 30),
              
              // Картка Балансу
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2E2E2E), Color(0xFF1A1A1A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text("Баланс Monobank (Приклад)", style: TextStyle(color: Colors.white54)),
                    SizedBox(height: 8),
                    // Це статичний приклад. Тут треба додати логіку підрахунку.
                    Text("... завантажується ...", style: TextStyle(fontSize: 36, fontWeight: FontWeight.w600, color: Colors.white)), 
                  ],
                ),
              ),
              
              const SizedBox(height: 30),
              const Text("Транзакції (Monobank API)", style: TextStyle(fontSize: 18, color: Colors.white70)),
              const SizedBox(height: 15),

              // Список транзакцій
              Expanded(
                child: FutureBuilder<List<dynamic>>(
                  future: _transactionsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (snapshot.hasError) {
                      return Center(child: Text('Помилка завантаження: ${snapshot.error}', textAlign: TextAlign.center));
                    } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(child: Text('Транзакцій не знайдено.', style: TextStyle(color: Colors.white54)));
                    }
                    
                    final transactions = snapshot.data!;
                    return ListView.builder(
                      itemCount: transactions.length,
                      itemBuilder: (context, index) {
                        final tx = transactions[index];
                        final isPositive = tx['amount'] > 0;
                        return TransactionItem(
                          title: tx['description'],
                          amount: '${isPositive ? '+' : ''}${tx['amount'].toStringAsFixed(2)} ₴',
                          date: tx['date'].split(' ')[0], // Тільки дата
                          icon: isPositive ? Icons.add_circle : Icons.remove_circle,
                          isPositive: isPositive,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _handleScanReceipt,
        backgroundColor: const Color(0xFFBB86FC), // Акцентний колір
        foregroundColor: Colors.black,
        icon: const Icon(Icons.camera_alt_outlined),
        label: const Text("Скан чека"),
      ),
    );
  }
}

class TransactionItem extends StatelessWidget {
  // ... (TransactionItem клас залишається без змін) ...
  final String title;
  final String amount;
  final String date;
  final IconData icon;
  final bool isPositive;

  const TransactionItem({
    super.key, 
    required this.title, 
    required this.amount, 
    required this.date, 
    required this.icon,
    this.isPositive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: isPositive ? Colors.greenAccent : Colors.white70, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16)),
                Text(date, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Text(
            amount, 
            style: TextStyle(
              fontSize: 16, 
              fontWeight: FontWeight.bold, 
              color: isPositive ? Colors.greenAccent : Colors.white
            )
          ),
        ],
      ),
    );
  }
}