import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';

// --- КОНСТАНТИ ---
// !!! ВСТАВТЕ СЮДИ АДРЕСУ ВАШОГО РОЗГОРНУТОГО API НА RENDER !!!
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
        // Темний фон для стилю
        scaffoldBackgroundColor: const Color(0xFF121212), 
        // Акцентний колір
        primaryColor: const Color(0xFFBB86FC), 
        useMaterial3: true,
        // Стильний шрифт Manrope
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
    // Звертаємося до маршруту /mono-transactions на Render.com
    final response = await http.get(Uri.parse('$API_URL/mono-transactions'));

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final error = json.decode(response.body)['detail'] ?? 'Невідома помилка';
      // Створюємо виняток для відображення помилки (наприклад, невірний токен)
      throw Exception('Помилка Monobank API: $error'); 
    }
  } catch (e) {
    throw Exception('Помилка мережі/сервера: $e');
  }
}

// 2. Сканування чека через Gemini API
Future<Map<String, dynamic>> scanReceipt() async {
  final picker = ImagePicker();
  // Користувач робить фото
  final XFile? photo = await picker.pickImage(source: ImageSource.camera);

  if (photo == null) return {};

  try {
    // Створюємо Multipart Request для надсилання файлу
    var request = http.MultipartRequest('POST', Uri.parse('$API_URL/scan-receipt'));
    
    // Додаємо файл до запиту
    request.files.add(
      await http.MultipartFile.fromPath('file', photo.path),
    );

    var streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    
    if (response.statusCode == 200) {
      // Успішно отримали JSON від FastAPI/Gemini
      return json.decode(response.body);
    } else {
      final error = json.decode(response.body)['detail'] ?? 'Невідома помилка';
      throw Exception('Помилка сканування чека: $error');
    }
  } catch (e) {
    throw Exception('Помилка відправки фото: ${e.toString()}');
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
    // Починаємо завантаження транзакцій одразу при старті
    _transactionsFuture = fetchMonoTransactions(); 
  }

  // Обробник натискання кнопки "Скан чека"
  void _handleScanReceipt() async {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Сканую чек...')),
    );

    try {
      final receiptData = await scanReceipt();
      
      if (receiptData.isNotEmpty && mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Результат сканування (AI)'),
            // SelectableText дозволяє скопіювати результат
            content: SelectableText(
              const JsonEncoder.withIndent('  ').convert(receiptData),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace')
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Закрити')),
            ],
          ),
        );
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
              
              // Картка Балансу (просто placeholder, тут потрібна окрема логіка)
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
                    Text("Баланс Monobank", style: TextStyle(color: Colors.white54)),
                    SizedBox(height: 8),
                    Text("... завантажується ...", style: TextStyle(fontSize: 36, fontWeight: FontWeight.w600, color: Colors.white)), 
                  ],
                ),
              ),
              
              const SizedBox(height: 30),
              const Text("Транзакції за 7 днів", style: TextStyle(fontSize: 18, color: Colors.white70)),
              const SizedBox(height: 15),

              // Список транзакцій, завантажений з API
              Expanded(
                child: FutureBuilder<List<dynamic>>(
                  future: _transactionsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (snapshot.hasError) {
                      return Center(child: Text('Помилка: ${snapshot.error}', textAlign: TextAlign.center));
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
                          date: tx['date'].split(' ')[0], 
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
      // Кнопка для запуску сканування чека
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _handleScanReceipt,
        backgroundColor: const Color(0xFFBB86FC), 
        foregroundColor: Colors.black,
        icon: const Icon(Icons.camera_alt_outlined),
        label: const Text("Скан чека"),
      ),
    );
  }
}

class TransactionItem extends StatelessWidget {
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