import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xl hide Border;
import 'package:http/http.dart' as http;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

const bg = Color(0xFF071A35);
const card = Color(0xFF102A4D);
const blue = Color(0xFF2563EB);
const gold = Color(0xFFF59E0B);
const green = Color(0xFF10B981);
const red = Color(0xFFEF4444);
const muted = Color(0xFF9FB2CC);

String money(num n) => NumberFormat('#,##0.00', 'en_US').format(n);
String dtext(dynamic v) {
  final d = DateTime.tryParse('$v');
  return d == null ? '$v' : DateFormat('yyyy/MM/dd').format(d);
}

class DB {
  static Database? _d;
  static Future<Database> get d async {
    if (_d != null) return _d!;
    final f = p.join(await getDatabasesPath(), 'smart_assistant.db');
    return _d = await openDatabase(
      f,
      version: 2,
      onCreate: (db, v) async {
        await db.execute(
          'CREATE TABLE customers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT, balance REAL DEFAULT 0, notes TEXT, created TEXT)',
        );
        await db.execute(
          'CREATE TABLE products(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, category TEXT, qty REAL DEFAULT 0, minimum REAL DEFAULT 0, unit TEXT DEFAULT "قطعة", price REAL DEFAULT 0, created TEXT)',
        );
        await db.execute(
          'CREATE TABLE dues(id INTEGER PRIMARY KEY AUTOINCREMENT, customer TEXT, amount REAL DEFAULT 0, due TEXT, note TEXT, status TEXT DEFAULT "pending")',
        );
        await db.execute(
          'CREATE TABLE transactions(id INTEGER PRIMARY KEY AUTOINCREMENT, customer TEXT, type TEXT, amount REAL DEFAULT 0, note TEXT, date TEXT)',
        );
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await db
              .execute(
                  'ALTER TABLE customers ADD COLUMN balance REAL DEFAULT 0')
              .catchError((_) {});
          await db
              .execute(
                  'ALTER TABLE products ADD COLUMN unit TEXT DEFAULT "قطعة"')
              .catchError((_) {});
        }
      },
      onOpen: (db) async {
        await db
            .execute('ALTER TABLE customers ADD COLUMN balance REAL DEFAULT 0')
            .catchError((_) {});
        await db
            .execute('ALTER TABLE products ADD COLUMN unit TEXT DEFAULT "قطعة"')
            .catchError((_) {});
      },
    );
  }
}

class AppState extends ChangeNotifier {
  int tab = 0;
  Map<String, dynamic> st = {};
  List<Map<String, dynamic>> customers = [],
      products = [],
      dues = [],
      transactions = [];
  String key = '',
      model = 'openai/gpt-oss-20b:free',
      base = 'https://openrouter.ai/api/v1/chat/completions';

  Future<void> init() async {
    final q = await SharedPreferences.getInstance();
    key = q.getString('key') ?? '';
    model = q.getString('model') ?? model;
    base = q.getString('base') ?? base;
    await refresh();
  }

  Future<void> refresh() async {
    final db = await DB.d;
    customers = await db.query('customers', orderBy: 'name');
    products = await db.query('products', orderBy: 'name');
    dues = await db.query('dues', orderBy: 'due');
    transactions = await db.query('transactions', orderBy: 'date DESC');

    final c = (await db.rawQuery('SELECT COUNT(*) n FROM customers')).first['n']
        as int;
    final pr = (await db.rawQuery('SELECT COUNT(*) n FROM products')).first['n']
        as int;
    final low = (await db
            .rawQuery('SELECT COUNT(*) n FROM products WHERE qty<=minimum'))
        .first['n'] as int;
    final du = (await db
            .rawQuery('SELECT COUNT(*) n FROM dues WHERE status="pending"'))
        .first['n'] as int;

    double owedSum = 0;
    double creditSum = 0;

    for (final cust in customers) {
      final double b = (cust['balance'] as num?)?.toDouble() ?? 0.0;
      if (b > 0) {
        owedSum += b;
      } else if (b < 0) {
        creditSum += b.abs();
      }
    }

    final owedTx = (await db.rawQuery(
            'SELECT COALESCE(SUM(amount),0) n FROM transactions WHERE type="debt"'))
        .first['n'] as num;
    final paidTx = (await db.rawQuery(
            'SELECT COALESCE(SUM(amount),0) n FROM transactions WHERE type="payment"'))
        .first['n'] as num;

    owedSum += owedTx.toDouble();
    creditSum += paidTx.toDouble();

    st = {
      'customers': c,
      'products': pr,
      'low': low,
      'dues': du,
      'owed': owedSum,
      'paid': creditSum,
    };
    notifyListeners();
  }

  Future<void> saveAI(String k, String m, String b) async {
    final q = await SharedPreferences.getInstance();
    await q.setString('key', k);
    await q.setString('model', m);
    await q.setString('base', b);
    key = k;
    model = m;
    base = b;
    notifyListeners();
  }
}

Future<void> editor(
  BuildContext c,
  String title,
  List<Map<String, dynamic>> fs,
  Future<void> Function(Map<String, String>) save,
) async {
  final cs = {
    for (final f in fs)
      f['k'] as String: TextEditingController(text: '${f['v'] ?? ''}'),
  };
  await showDialog(
    context: c,
    builder: (x) => AlertDialog(
      backgroundColor: card,
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          children: [
            for (final f in fs)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: TextField(
                  controller: cs[f['k']],
                  keyboardType: f['num'] == true
                      ? const TextInputType.numberWithOptions(
                          decimal: true, signed: true)
                      : TextInputType.text,
                  decoration: InputDecoration(
                    labelText: f['l'] as String,
                    hintText: f['hint'] as String?,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(x),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () async {
            await save({for (final e in cs.entries) e.key: e.value.text});
            if (x.mounted) Navigator.pop(x);
          },
          child: const Text('حفظ'),
        ),
      ],
    ),
  );
  for (final x in cs.values) {
    x.dispose();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final s = AppState();
  await s.init();
  runApp(
    ChangeNotifierProvider.value(
      value: s,
      child: const App(),
    ),
  );
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext c) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'المساعد الذكي',
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: bg,
          colorScheme: ColorScheme.fromSeed(
            seedColor: blue,
            brightness: Brightness.dark,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
          navigationBarTheme: const NavigationBarThemeData(
            backgroundColor: Color(0xFF0B2344),
            indicatorColor: blue,
          ),
        ),
        home: const Root(),
      );
}

class Root extends StatelessWidget {
  const Root({super.key});

  @override
  Widget build(BuildContext c) {
    final s = c.watch<AppState>();
    final pages = [
      const Home(),
      const Customers(),
      const Products(),
      const Reports(),
      const More(),
    ];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(child: pages[s.tab]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: s.tab,
          onDestinationSelected: (i) {
            s.tab = i;
            // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
            s.notifyListeners();
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'الرئيسية',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'العملاء',
            ),
            NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2),
              label: 'الأصناف',
            ),
            NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart),
              label: 'التقارير',
            ),
            NavigationDestination(
              icon: Icon(Icons.more_horiz),
              label: 'المزيد',
            ),
          ],
        ),
      ),
    );
  }
}

class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext c) {
    final s = c.watch<AppState>(), x = s.st;
    return ListView(
      padding: const EdgeInsets.all(15),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => showModalBottomSheet(
                context: c,
                backgroundColor: card,
                builder: (_) => const More(),
              ),
              icon: const Icon(Icons.menu),
            ),
            const Spacer(),
            const Column(
              children: [
                Text(
                  'المساعد الذكي',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                Text(
                  'إدارة العملاء والمخزون بذكاء',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ],
            ),
            const Spacer(),
            IconButton(
              onPressed: () => showDialog(
                context: c,
                builder: (_) => AlertDialog(
                  backgroundColor: card,
                  title: const Text('التنبيهات'),
                  content: Text(
                    'لديك ${x['dues'] ?? 0} استحقاقات معلقة، و ${x['low'] ?? 0} أصناف منخفضة المخزون.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('موافق'),
                    )
                  ],
                ),
              ),
              icon: const Icon(Icons.notifications_none),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF173D6D), Color(0xFF0D284B)],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '👋 مرحباً بك',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 5),
              Text(
                'إليك نظرة عامة على نشاطك اليوم',
                style: TextStyle(color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.5,
          children: [
            K('إجمالي الأرصدة', money((x['owed'] ?? 0) - (x['paid'] ?? 0)),
                'إجمالي الصافي', green),
            K('العملاء', '${x['customers'] ?? 0}', 'إجمالي العملاء', blue),
            K('استحقاقات المعلقة', '${x['dues'] ?? 0}', 'استحقاق', gold),
            K(
              'أصناف تنبيه المخزون',
              '${x['low'] ?? 0}',
              'صنف بحاجة لتزويد',
              red,
            ),
            K('الأصناف', '${x['products'] ?? 0}', 'إجمالي الأصناف', blue),
            K('الأرصدة المستحقة (عليهم)', money(x['owed'] ?? 0), 'مستحق لك',
                red),
          ],
        ),
        const SizedBox(height: 12),
        Balance(
          owed: (x['owed'] ?? 0).toDouble(),
          paid: (x['paid'] ?? 0).toDouble(),
        ),
        const SizedBox(height: 12),
        const DuesPreview(),
      ],
    );
  }
}

class K extends StatelessWidget {
  final String a, b, c;
  final Color col;
  const K(this.a, this.b, this.c, this.col, {super.key});

  @override
  Widget build(BuildContext x) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(a, style: const TextStyle(fontSize: 12)),
            const Spacer(),
            Text(
              b,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            Text(c, style: const TextStyle(color: muted, fontSize: 10)),
          ],
        ),
      );
}

class Balance extends StatelessWidget {
  final double owed;
  final double paid;

  const Balance({
    required this.owed,
    required this.paid,
    super.key,
  });

  @override
  Widget build(BuildContext c) {
    final double net = owed - paid;

    return Card(
      color: card,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              'نظرة عامة على الأرصدة',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 105,
                  height: 105,
                  child: CustomPaint(
                    painter: Donut(owed, paid),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'لهم (دائن)   ${money(paid)}',
                        style: const TextStyle(color: green),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'عليهم (مدينة)   ${money(owed)}',
                        style: const TextStyle(color: red),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'صافي الأرصدة   ${money(net)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class Donut extends CustomPainter {
  final double a, b;
  Donut(this.a, this.b);

  @override
  void paint(Canvas x, Size s) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18;
    final r = Rect.fromCircle(
            center: s.center(Offset.zero), radius: s.width * .34),
        t = a + b;
    final double aa = t == 0 ? 0.0 : 2 * math.pi * b / t;
    p.color = green;
    x.drawArc(r, -math.pi / 2, aa, false, p);
    p.color = red;
    x.drawArc(r, -math.pi / 2 + aa, t == 0 ? 0 : 2 * math.pi * a / t, false, p);
  }

  @override
  bool shouldRepaint(covariant Donut o) => o.a != a || o.b != b;
}

class DuesPreview extends StatelessWidget {
  const DuesPreview({super.key});

  @override
  Widget build(BuildContext c) {
    final s = c.watch<AppState>();
    return Card(
      color: card,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Text(
                  'أقرب الاستحقاقات',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.push(
                    c,
                    MaterialPageRoute(builder: (_) => const Dues()),
                  ),
                  child: const Text('عرض الكل'),
                ),
              ],
            ),
            if (s.dues.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('لا توجد استحقاقات مسجلة',
                    style: TextStyle(color: muted)),
              ),
            ...s.dues.take(3).map(
                  (r) => ListTile(
                    dense: true,
                    title: Text(money(r['amount'])),
                    subtitle:
                        Text('${r['customer'] ?? ''} • ${dtext(r['due'])}'),
                    leading: Icon(
                      Icons.event,
                      color: r['status'] == 'paid' ? green : gold,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class Customers extends StatefulWidget {
  const Customers({super.key});

  @override
  State<Customers> createState() => _CS();
}

class _CS extends State<Customers> {
  String q = '';

  @override
  Widget build(BuildContext c) {
    final s = c.watch<AppState>();
    final rows = s.customers
        .where((r) => '${r['name']} ${r['phone']} ${r['notes']}'.contains(q))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة العملاء والأرصدة')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: blue,
        onPressed: () => add(c),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          TextField(
            onChanged: (v) => setState(() => q = v),
            decoration: const InputDecoration(
              hintText: 'بحث عن عميل أو رقم هاتف...',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty) const Empty('لا يوجد عملاء مطاطقين للبحث'),
          ...rows.map(
            (r) {
              final double bal = (r['balance'] as num?)?.toDouble() ?? 0.0;
              final Color balColor = bal > 0 ? red : (bal < 0 ? green : muted);
              final String balLabel = bal > 0
                  ? 'عليه: ${money(bal)}'
                  : (bal < 0 ? 'له: ${money(bal.abs())}' : 'الرصيد: 0.00');

              return Card(
                color: card,
                child: ListTile(
                  title: Text(r['name'],
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    '${r['phone'] ?? 'بدون هاتف'}\n$balLabel',
                    style: TextStyle(color: balColor),
                  ),
                  isThreeLine: true,
                  leading: CircleAvatar(
                    backgroundColor: blue.withValues(alpha: 0.2),
                    child: const Icon(Icons.person, color: blue),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: gold),
                        onPressed: () => edit(c, r),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: red),
                        onPressed: () => deleteCust(c, r),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> add(BuildContext c) async {
    final appState = c.read<AppState>();
    await editor(
      c,
      'إضافة عميل جديد',
      const [
        {'k': 'name', 'l': 'اسم العميل *'},
        {'k': 'phone', 'l': 'رقم الهاتف'},
        {
          'k': 'balance',
          'l': 'الرصيد الأولي (موجب = عليه ، سالب = له)',
          'num': true,
          'v': '0'
        },
        {'k': 'notes', 'l': 'ملاحظات'},
      ],
      (v) async {
        if (v['name']!.trim().isEmpty) return;
        await DB.d.then(
          (d) => d.insert('customers', {
            'name': v['name']!.trim(),
            'phone': v['phone']!.trim(),
            'balance': double.tryParse(v['balance']!) ?? 0.0,
            'notes': v['notes']!.trim(),
            'created': DateTime.now().toIso8601String(),
          }),
        );
        await appState.refresh();
      },
    );
  }

  Future<void> edit(BuildContext c, Map<String, dynamic> r) async {
    final appState = c.read<AppState>();
    await editor(
      c,
      'تعديل بيانات العميل',
      [
        {'k': 'name', 'l': 'اسم العميل *', 'v': r['name']},
        {'k': 'phone', 'l': 'رقم الهاتف', 'v': r['phone']},
        {
          'k': 'balance',
          'l': 'الرصيد الحقيقي (موجب = عليه ، سالب = له)',
          'num': true,
          'v': r['balance']?.toString() ?? '0'
        },
        {'k': 'notes', 'l': 'ملاحظات', 'v': r['notes']},
      ],
      (v) async {
        if (v['name']!.trim().isEmpty) return;
        await DB.d.then(
          (d) => d.update(
            'customers',
            {
              'name': v['name']!.trim(),
              'phone': v['phone']!.trim(),
              'balance': double.tryParse(v['balance']!) ?? 0.0,
              'notes': v['notes']!.trim(),
            },
            where: 'id=?',
            whereArgs: [r['id']],
          ),
        );
        await appState.refresh();
      },
    );
  }

  Future<void> deleteCust(BuildContext c, Map<String, dynamic> r) async {
    final appState = c.read<AppState>();
    final confirm = await showDialog<bool>(
      context: c,
      builder: (x) => AlertDialog(
        backgroundColor: card,
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت تأكد من حذف العميل "${r['name']}"؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(x, false),
              child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: red),
            onPressed: () => Navigator.pop(x, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await DB.d.then(
          (d) => d.delete('customers', where: 'id=?', whereArgs: [r['id']]));
      await appState.refresh();
    }
  }
}

class Products extends StatefulWidget {
  const Products({super.key});

  @override
  State<Products> createState() => _PS();
}

class _PS extends State<Products> {
  String q = '';
  String catFilter = 'الكل';

  @override
  Widget build(BuildContext c) {
    final s = c.watch<AppState>();

    final categories = [
      'الكل',
      ...{
        ...s.products
            .map((e) => (e['category'] as String?)?.trim() ?? '')
            .where((element) => element.isNotEmpty)
      }
    ];

    final rows = s.products.where((r) {
      final nameCat = '${r['name']} ${r['category']}'.contains(q);
      final catMatch = catFilter == 'الكل' ||
          (r['category'] as String?)?.trim() == catFilter;
      return nameCat && catMatch;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('الأصناف والمخزون')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: blue,
        onPressed: () => add(c),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          TextField(
            onChanged: (v) => setState(() => q = v),
            decoration: const InputDecoration(
              hintText: 'بحث عن صنف أو تصنيف...',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories.map((cat) {
                final selected = catFilter == cat;
                return Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: FilterChip(
                    label: Text(cat),
                    selected: selected,
                    onSelected: (_) => setState(() => catFilter = cat),
                    selectedColor: blue,
                    backgroundColor: card,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty) const Empty('لا توجد أصناف مطابقة'),
          ...rows.map((r) {
            final double qty = (r['qty'] as num?)?.toDouble() ?? 0.0;
            final double min = (r['minimum'] as num?)?.toDouble() ?? 0.0;
            final bool low = qty <= min;
            final String unit = r['unit'] as String? ?? 'قطعة';

            return Card(
              color: card,
              child: ListTile(
                title: Text(r['name'],
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    '${r['category'] ?? 'عام'} • السعر: ${money(r['price'] ?? 0)}'),
                leading: Icon(
                  Icons.inventory_2_outlined,
                  color: low ? red : green,
                  size: 30,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('الكمية: $qty $unit',
                            style: TextStyle(
                                color: low ? red : green,
                                fontWeight: FontWeight.bold)),
                        if (low)
                          const Text('منخفض!',
                              style: TextStyle(color: red, fontSize: 10)),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, color: gold),
                      onPressed: () => edit(c, r),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: red),
                      onPressed: () => deleteProd(c, r),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> add(BuildContext c) async {
    final appState = c.read<AppState>();
    await editor(
      c,
      'إضافة صنف جديد',
      const [
        {'k': 'name', 'l': 'اسم الصنف *'},
        {'k': 'category', 'l': 'التصنيف (مثال: سباكة / كهرباء)'},
        {'k': 'qty', 'l': 'الكمية المتوفرة', 'num': true, 'v': '0'},
        {'k': 'unit', 'l': 'الوحدة (قطعة / متر / كجم...)', 'v': 'قطعة'},
        {'k': 'minimum', 'l': 'حد تنبيه النقص', 'num': true, 'v': '5'},
        {'k': 'price', 'l': 'السعر', 'num': true, 'v': '0'},
      ],
      (v) async {
        if (v['name']!.trim().isEmpty) return;
        await DB.d.then(
          (d) => d.insert('products', {
            'name': v['name']!.trim(),
            'category': v['category']!.trim(),
            'qty': double.tryParse(v['qty']!) ?? 0,
            'unit': v['unit']!.trim().isEmpty ? 'قطعة' : v['unit']!.trim(),
            'minimum': double.tryParse(v['minimum']!) ?? 0,
            'price': double.tryParse(v['price']!) ?? 0,
            'created': DateTime.now().toIso8601String(),
          }),
        );
        await appState.refresh();
      },
    );
  }

  Future<void> edit(BuildContext c, Map<String, dynamic> r) async {
    final appState = c.read<AppState>();
    await editor(
      c,
      'تعديل الصنف',
      [
        {'k': 'name', 'l': 'اسم الصنف *', 'v': r['name']},
        {'k': 'category', 'l': 'التصنيف', 'v': r['category']},
        {
          'k': 'qty',
          'l': 'الكمية المتوفرة',
          'num': true,
          'v': r['qty']?.toString()
        },
        {'k': 'unit', 'l': 'الوحدة', 'v': r['unit'] ?? 'قطعة'},
        {
          'k': 'minimum',
          'l': 'حد التنبيه',
          'num': true,
          'v': r['minimum']?.toString()
        },
        {'k': 'price', 'l': 'السعر', 'num': true, 'v': r['price']?.toString()},
      ],
      (v) async {
        if (v['name']!.trim().isEmpty) return;
        await DB.d.then(
          (d) => d.update(
            'products',
            {
              'name': v['name']!.trim(),
              'category': v['category']!.trim(),
              'qty': double.tryParse(v['qty']!) ?? 0,
              'unit': v['unit']!.trim().isEmpty ? 'قطعة' : v['unit']!.trim(),
              'minimum': double.tryParse(v['minimum']!) ?? 0,
              'price': double.tryParse(v['price']!) ?? 0,
            },
            where: 'id=?',
            whereArgs: [r['id']],
          ),
        );
        await appState.refresh();
      },
    );
  }

  Future<void> deleteProd(BuildContext c, Map<String, dynamic> r) async {
    final appState = c.read<AppState>();
    final confirm = await showDialog<bool>(
      context: c,
      builder: (x) => AlertDialog(
        backgroundColor: card,
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت تأكد من حذف الصنف "${r['name']}"؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(x, false),
              child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: red),
            onPressed: () => Navigator.pop(x, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await DB.d.then(
          (d) => d.delete('products', where: 'id=?', whereArgs: [r['id']]));
      await appState.refresh();
    }
  }
}

class Dues extends StatefulWidget {
  const Dues({super.key});

  @override
  State<Dues> createState() => _DuesState();
}

class _DuesState extends State<Dues> {
  String q = '';
  String statusFilter = 'الكل';

  @override
  Widget build(BuildContext c) {
    final s = c.watch<AppState>();

    final rows = s.dues.where((r) {
      final textMatch = '${r['customer']} ${r['note']}'.contains(q);
      final statusMatch = statusFilter == 'الكل' || r['status'] == statusFilter;
      return textMatch && statusMatch;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الاستحقاقات ومواعيدها')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: blue,
        onPressed: () => add(c),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          TextField(
            onChanged: (v) => setState(() => q = v),
            decoration: const InputDecoration(
              hintText: 'بحث باسم العميل أو الملاحظة...',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilterChip(
                label: const Text('الكل'),
                selected: statusFilter == 'الكل',
                onSelected: (_) => setState(() => statusFilter = 'الكل'),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('معلق'),
                selected: statusFilter == 'pending',
                onSelected: (_) => setState(() => statusFilter = 'pending'),
                selectedColor: gold,
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('مكتمل/مدفوع'),
                selected: statusFilter == 'paid',
                onSelected: (_) => setState(() => statusFilter = 'paid'),
                selectedColor: green,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty) const Empty('لا توجد استحقاقات مطابقة'),
          ...rows.map(
            (r) {
              final isPaid = r['status'] == 'paid';
              return Card(
                color: card,
                child: ListTile(
                  title: Text(
                      '${r['customer'] ?? 'عام'} - ${money(r['amount'] ?? 0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      'تاريخ الاستحقاق: ${dtext(r['due'])}\n${r['note'] ?? ''}'),
                  isThreeLine: true,
                  leading: Icon(
                    Icons.event,
                    color: isPaid ? green : gold,
                    size: 32,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(isPaid ? Icons.undo : Icons.check,
                            color: isPaid ? muted : green),
                        onPressed: () async {
                          final appState = c.read<AppState>();
                          await DB.d.then(
                            (d) => d.update(
                              'dues',
                              {'status': isPaid ? 'pending' : 'paid'},
                              where: 'id=?',
                              whereArgs: [r['id']],
                            ),
                          );
                          await appState.refresh();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: gold),
                        onPressed: () => edit(c, r),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: red),
                        onPressed: () => deleteDue(c, r),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> add(BuildContext c) async {
    final appState = c.read<AppState>();
    await editor(
      c,
      'إضافة استحقاق جديد',
      [
        const {'k': 'customer', 'l': 'اسم العميل *'},
        {'k': 'amount', 'l': 'المبلغ *', 'num': true, 'v': '0'},
        {
          'k': 'due',
          'l': 'التاريخ (YYYY-MM-DD)',
          'v': DateTime.now().toIso8601String().substring(0, 10),
        },
        {'k': 'note', 'l': 'ملاحظات / سبب الاستحقاق'},
      ],
      (v) async {
        if (v['customer']!.trim().isEmpty) return;
        await DB.d.then(
          (d) => d.insert('dues', {
            'customer': v['customer']!.trim(),
            'amount': double.tryParse(v['amount']!) ?? 0,
            'due': v['due']!.trim(),
            'note': v['note']!.trim(),
            'status': 'pending',
          }),
        );
        await appState.refresh();
      },
    );
  }

  Future<void> edit(BuildContext c, Map<String, dynamic> r) async {
    final appState = c.read<AppState>();
    await editor(
      c,
      'تعديل الاستحقاق',
      [
        {'k': 'customer', 'l': 'اسم العميل *', 'v': r['customer']},
        {
          'k': 'amount',
          'l': 'المبلغ *',
          'num': true,
          'v': r['amount']?.toString()
        },
        {'k': 'due', 'l': 'التاريخ (YYYY-MM-DD)', 'v': r['due']},
        {'k': 'note', 'l': 'ملاحظات', 'v': r['note']},
      ],
      (v) async {
        if (v['customer']!.trim().isEmpty) return;
        await DB.d.then(
          (d) => d.update(
            'dues',
            {
              'customer': v['customer']!.trim(),
              'amount': double.tryParse(v['amount']!) ?? 0,
              'due': v['due']!.trim(),
              'note': v['note']!.trim(),
            },
            where: 'id=?',
            whereArgs: [r['id']],
          ),
        );
        await appState.refresh();
      },
    );
  }

  Future<void> deleteDue(BuildContext c, Map<String, dynamic> r) async {
    final appState = c.read<AppState>();
    final confirm = await showDialog<bool>(
      context: c,
      builder: (x) => AlertDialog(
        backgroundColor: card,
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت تأكد من حذف هذا الاستحقاق؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(x, false),
              child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: red),
            onPressed: () => Navigator.pop(x, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await DB.d
          .then((d) => d.delete('dues', where: 'id=?', whereArgs: [r['id']]));
      await appState.refresh();
    }
  }
}

class Reports extends StatefulWidget {
  const Reports({super.key});

  @override
  State<Reports> createState() => _ReportsState();
}

class _ReportsState extends State<Reports> {
  String activeReport = 'العملاء والأرصدة';
  String q = '';

  @override
  Widget build(BuildContext c) {
    final s = c.watch<AppState>();

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(15),
        children: [
          const Text(
            'مركز التقارير والتصدير',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                'العملاء والأرصدة',
                'تقرير المخزون',
                'الأصناف الناقصة',
                'تقرير الاستحقاقات',
              ].map((rep) {
                final sel = activeReport == rep;
                return Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ChoiceChip(
                    label: Text(rep),
                    selected: sel,
                    onSelected: (_) => setState(() => activeReport = rep),
                    selectedColor: blue,
                    backgroundColor: card,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (v) => setState(() => q = v),
            decoration: const InputDecoration(
              hintText: 'تصفية داخل التقرير...',
              prefixIcon: Icon(Icons.filter_alt_outlined),
            ),
          ),
          const SizedBox(height: 12),
          _buildReportContent(s),
          const SizedBox(height: 15),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: blue, padding: const EdgeInsets.all(14)),
            onPressed: () => pdfExport(c, activeReport, s),
            icon: const Icon(Icons.picture_as_pdf),
            label: Text('تصدير $activeReport إلى PDF'),
          ),
        ],
      ),
    );
  }

  Widget _buildReportContent(AppState s) {
    if (activeReport == 'العملاء والأرصدة') {
      final rows = s.customers
          .where((r) => '${r['name']} ${r['phone']}'.contains(q))
          .toList();
      return Card(
        color: card,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Text('عدد العملاء: ${rows.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const Divider(),
              ...rows.map((r) => ListTile(
                    title: Text(r['name']),
                    subtitle: Text(r['phone'] ?? ''),
                    trailing: Text(
                      ((r['balance'] as num?) ?? 0) >= 0
                          ? 'عليه: ${money(r['balance'] ?? 0)}'
                          : 'له: ${money(((r['balance'] as num?) ?? 0).abs())}',
                      style: TextStyle(
                          color:
                              ((r['balance'] as num?) ?? 0) > 0 ? red : green),
                    ),
                  )),
            ],
          ),
        ),
      );
    } else if (activeReport == 'تقرير المخزون') {
      final rows = s.products
          .where((r) => '${r['name']} ${r['category']}'.contains(q))
          .toList();
      return Card(
        color: card,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Text('إجمالي الأصناف: ${rows.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const Divider(),
              ...rows.map((r) => ListTile(
                    title: Text(r['name']),
                    subtitle: Text(
                        '${r['category'] ?? 'عام'} - السعر: ${money(r['price'] ?? 0)}'),
                    trailing:
                        Text('الكمية: ${r['qty']} ${r['unit'] ?? "قطعة"}'),
                  )),
            ],
          ),
        ),
      );
    } else if (activeReport == 'الأصناف الناقصة') {
      final rows = s.products
          .where((r) => (r['qty'] as num? ?? 0) <= (r['minimum'] as num? ?? 0))
          .where((r) => '${r['name']} ${r['category']}'.contains(q))
          .toList();
      return Card(
        color: card,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Text('عدد الأصناف منخفضة المخزون: ${rows.length}',
                  style:
                      const TextStyle(color: red, fontWeight: FontWeight.bold)),
              const Divider(),
              if (rows.isEmpty)
                const Text('لا توجد أصناف ناقصة حالياً',
                    style: TextStyle(color: green)),
              ...rows.map((r) => ListTile(
                    title: Text(r['name'], style: const TextStyle(color: red)),
                    subtitle: Text('حد التنبيه: ${r['minimum']}'),
                    trailing: Text(
                        'المتبقي: ${r['qty']} ${r['unit'] ?? "قطعة"}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, color: red)),
                  )),
            ],
          ),
        ),
      );
    } else {
      final rows = s.dues
          .where((r) => '${r['customer']} ${r['note']}'.contains(q))
          .toList();
      return Card(
        color: card,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Text('إجمالي الاستحقاقات: ${rows.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const Divider(),
              ...rows.map((r) => ListTile(
                    title:
                        Text('${r['customer']} - ${money(r['amount'] ?? 0)}'),
                    subtitle: Text('تاريخ: ${dtext(r['due'])}'),
                    trailing: Text(
                      r['status'] == 'paid' ? 'مدفوع' : 'معلق',
                      style: TextStyle(
                          color: r['status'] == 'paid' ? green : gold),
                    ),
                  )),
            ],
          ),
        ),
      );
    }
  }

  Future<void> pdfExport(BuildContext c, String title, AppState s) async {
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        build: (_) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(
                  level: 0,
                  child: pw.Text('Smart Assistant - $title',
                      style: pw.TextStyle(
                          fontSize: 22, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 10),
              pw.Text(
                  'تاريخ التقرير: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}'),
              pw.SizedBox(height: 15),
              if (title == 'العملاء والأرصدة')
                pw.TableHelper.fromTextArray(
                  headers: ['اسم العميل', 'رقم الهاتف', 'الرصيد', 'ملاحظات'],
                  data: s.customers
                      .map((r) => [
                            r['name'],
                            r['phone'] ?? '',
                            ((r['balance'] as num?) ?? 0) >= 0
                                ? 'عليه: ${money(r['balance'] ?? 0)}'
                                : 'له: ${money(((r['balance'] as num?) ?? 0).abs())}',
                            r['notes'] ?? ''
                          ])
                      .toList(),
                )
              else if (title == 'تقرير المخزون')
                pw.TableHelper.fromTextArray(
                  headers: ['الصنف', 'التصنيف', 'الكمية', 'الوحدة', 'السعر'],
                  data: s.products
                      .map((r) => [
                            r['name'],
                            r['category'] ?? '',
                            '${r['qty']}',
                            r['unit'] ?? 'قطعة',
                            money(r['price'] ?? 0)
                          ])
                      .toList(),
                )
              else if (title == 'الأصناف الناقصة')
                pw.TableHelper.fromTextArray(
                  headers: [
                    'الصنف',
                    'التصنيف',
                    'الكمية المتبقية',
                    'حد التنبيه'
                  ],
                  data: s.products
                      .where((r) =>
                          (r['qty'] as num? ?? 0) <=
                          (r['minimum'] as num? ?? 0))
                      .map((r) => [
                            r['name'],
                            r['category'] ?? '',
                            '${r['qty']}',
                            '${r['minimum']}'
                          ])
                      .toList(),
                )
              else
                pw.TableHelper.fromTextArray(
                  headers: ['العميل', 'المبلغ', 'التاريخ', 'الحالة', 'ملاحظات'],
                  data: s.dues
                      .map((r) => [
                            r['customer'],
                            money(r['amount'] ?? 0),
                            dtext(r['due']),
                            r['status'] == 'paid' ? 'مدفوع' : 'معلق',
                            r['note'] ?? ''
                          ])
                      .toList(),
                ),
            ],
          ),
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (f) => doc.save());
  }
}

class More extends StatelessWidget {
  const More({super.key});

  @override
  Widget build(BuildContext c) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 10),
          const Center(child: Logo()),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              'المساعد الذكي',
              style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
            ),
          ),
          const Center(
            child: Text(
              'نظام ذكي شامل لإدارة عملك',
              style: TextStyle(color: muted),
            ),
          ),
          const SizedBox(height: 18),
          ListTileCard(
            'الاستحقاقات والمواعيد',
            Icons.event,
            () => Navigator.push(
              c,
              MaterialPageRoute(builder: (_) => const Dues()),
            ),
          ),
          ListTileCard(
            'الاستيراد الذكي (CSV/Excel/PDF)',
            Icons.file_upload,
            () => Navigator.push(
              c,
              MaterialPageRoute(builder: (_) => const ImportPage()),
            ),
          ),
          ListTileCard(
            'المساعد الذكي (AI)',
            Icons.smart_toy_outlined,
            () => Navigator.push(
              c,
              MaterialPageRoute(builder: (_) => const Chat()),
            ),
          ),
          ListTileCard('النسخ الاحتياطي والاستعادة', Icons.backup,
              () => showBackupRestoreDialog(c)),
          ListTileCard(
            'إعدادات التطبيق و AI',
            Icons.settings,
            () => Navigator.push(
              c,
              MaterialPageRoute(builder: (_) => const Settings()),
            ),
          ),
        ],
      );
}

class ListTileCard extends StatelessWidget {
  final String t;
  final IconData i;
  final VoidCallback f;
  const ListTileCard(this.t, this.i, this.f, {super.key});

  @override
  Widget build(BuildContext c) => Card(
        color: card,
        child: ListTile(
          title: Text(t),
          trailing: Icon(i, color: gold),
          leading: const Icon(Icons.chevron_left),
          onTap: f,
        ),
      );
}

class Logo extends StatelessWidget {
  const Logo({super.key});

  @override
  Widget build(BuildContext c) => Container(
        width: 105,
        height: 105,
        decoration: BoxDecoration(
          color: const Color(0xFF091D3A),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: blue, width: 2),
        ),
        child: const Icon(Icons.smart_toy_outlined, size: 62, color: gold),
      );
}

void showBackupRestoreDialog(BuildContext c) {
  showDialog(
    context: c,
    builder: (x) => AlertDialog(
      backgroundColor: card,
      title: const Text('النسخ الاحتياطي والاستعادة'),
      content: const Text('اختر العملية المطلوبة:'),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(x);
            backup(c);
          },
          child: const Text('إنشاء نسخة احتياطية'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: blue),
          onPressed: () {
            Navigator.pop(x);
            restore(c);
          },
          child: const Text('استعادة نسخة احتياطية'),
        ),
      ],
    ),
  );
}

Future<void> backup(BuildContext c) async {
  final d = await DB.d;
  final data = {
    'version': 1,
    'timestamp': DateTime.now().toIso8601String(),
    'customers': await d.query('customers'),
    'products': await d.query('products'),
    'dues': await d.query('dues'),
    'transactions': await d.query('transactions'),
  };

  try {
    final String? savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'اختر موقع حفظ النسخة الاحتياطية',
      fileName:
          'smart_assistant_backup_${DateTime.now().millisecondsSinceEpoch}.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (savePath != null) {
      final f = File(savePath);
      await f.writeAsString(jsonEncode(data));
      if (c.mounted) {
        ScaffoldMessenger.of(c).showSnackBar(
          SnackBar(
              content: Text('تم حفظ النسخة الاحتياطية بنجاح في: $savePath')),
        );
      }
    } else {
      final dir = Directory('/storage/emulated/0/Download');
      await dir.create(recursive: true);
      final f = File(p.join(dir.path, 'smart_assistant_backup.json'));
      await f.writeAsString(jsonEncode(data));
      if (c.mounted) {
        ScaffoldMessenger.of(c).showSnackBar(
          const SnackBar(
              content: Text('تم حفظ النسخة الاحتياطية في مجلد Download')),
        );
      }
    }
  } catch (e) {
    if (c.mounted) {
      ScaffoldMessenger.of(c).showSnackBar(
        SnackBar(content: Text('تعذر الحفظ: $e')),
      );
    }
  }
}

Future<void> restore(BuildContext c) async {
  final appState = c.read<AppState>();
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    final content = await file.readAsString();
    final Map<String, dynamic> data = jsonDecode(content);

    if (!data.containsKey('customers') && !data.containsKey('products')) {
      if (c.mounted) {
        ScaffoldMessenger.of(c).showSnackBar(
          const SnackBar(
              content: Text('ملف النسخة الاحتياطية غير صريح أو غير متوافق.')),
        );
      }
      return;
    }

    final d = await DB.d;
    await d.transaction((txn) async {
      if (data.containsKey('customers')) {
        await txn.delete('customers');
        for (final row in data['customers']) {
          await txn.insert('customers', Map<String, dynamic>.from(row as Map));
        }
      }
      if (data.containsKey('products')) {
        await txn.delete('products');
        for (final row in data['products']) {
          await txn.insert('products', Map<String, dynamic>.from(row as Map));
        }
      }
      if (data.containsKey('dues')) {
        await txn.delete('dues');
        for (final row in data['dues']) {
          await txn.insert('dues', Map<String, dynamic>.from(row as Map));
        }
      }
      if (data.containsKey('transactions')) {
        await txn.delete('transactions');
        for (final row in data['transactions']) {
          await txn.insert(
              'transactions', Map<String, dynamic>.from(row as Map));
        }
      }
    });

    await appState.refresh();
    if (c.mounted) {
      ScaffoldMessenger.of(c).showSnackBar(
        const SnackBar(content: Text('تمت استعادة البيانات بنجاح!')),
      );
    }
  } catch (e) {
    if (c.mounted) {
      ScaffoldMessenger.of(c).showSnackBar(
        SnackBar(content: Text('فشلت الاستعادة: $e')),
      );
    }
  }
}

class ImportPage extends StatefulWidget {
  const ImportPage({super.key});

  @override
  State<ImportPage> createState() => _IP();
}

class _IP extends State<ImportPage> {
  String msg =
      'اختر ملف CSV أو XLSX أو PDF للمعاينة والتحقق قبل الحفظ في قاعدة البيانات.';
  bool busy = false;

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('الاستيراد الذكي للمعطيات')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FilledButton.icon(
              onPressed: busy ? null : () => pickAndPreview(c, 'customers'),
              icon: const Icon(Icons.people),
              label: const Text('استيراد بيانات العملاء (CSV / XLSX / PDF)'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: busy ? null : () => pickAndPreview(c, 'products'),
              icon: const Icon(Icons.inventory_2),
              label: const Text('استيراد الأصناف والمخزون (CSV / XLSX / PDF)'),
            ),
            const SizedBox(height: 15),
            Card(
              color: card,
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Text(msg),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'الصيغة المتوقعة للعملاء: الاسم, الهاتف, الرصيد, الملاحظات\nالصيغة المتوقعة للأصناف: الاسم, التصنيف, الكمية, حد التنبيه, السعر, الوحدة',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      );

  Future<void> pickAndPreview(BuildContext c, String type) async {
    setState(() => busy = true);
    try {
      final r = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'pdf'],
        withData: true,
      );
      if (r == null || r.files.isEmpty) {
        if (mounted) setState(() => busy = false);
        return;
      }

      final fileRef = r.files.single;
      final fileName = fileRef.name;
      List<int>? bytes = fileRef.bytes;
      if (bytes == null && fileRef.path != null) {
        bytes = await File(fileRef.path!).readAsBytes();
      }

      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          setState(() {
            msg = 'تعذر قراءة بيانات الملف $fileName.';
            busy = false;
          });
        }
        return;
      }

      List<Map<String, dynamic>> extractedRows = [];

      if (fileName.toLowerCase().endsWith('.csv')) {
        final rawStr = utf8.decode(bytes, allowMalformed: true);
        final rows = const CsvToListConverter().convert(rawStr);
        extractedRows = parseRawRows(rows.skip(1).toList(), type);
      } else if (fileName.toLowerCase().endsWith('.xlsx')) {
        final book = xl.Excel.decodeBytes(bytes);
        List<List<dynamic>> sheetRows = [];
        for (final table in book.tables.values) {
          for (final row in table.rows.skip(1)) {
            sheetRows.add(row.map((e) => e?.value ?? '').toList());
          }
        }
        extractedRows = parseRawRows(sheetRows, type);
      } else if (fileName.toLowerCase().endsWith('.pdf')) {
        extractedRows = extractPdfRows(bytes, type);
      }

      if (extractedRows.isEmpty) {
        if (mounted) {
          setState(() {
            msg = 'لم يتم العثور على بيانات صالحة في الملف $fileName.';
            busy = false;
          });
        }
        return;
      }

      // Check duplicates with existing DB records
      final db = await DB.d;
      final existingCusts = await db.query('customers');
      final existingProds = await db.query('products');

      for (var row in extractedRows) {
        final name = row['name'].toString().trim();
        if (type == 'customers') {
          final exists =
              existingCusts.any((e) => (e['name'] as String).trim() == name);
          row['isDuplicate'] = exists;
          row['action'] = exists ? 'update' : 'add';
        } else {
          final exists =
              existingProds.any((e) => (e['name'] as String).trim() == name);
          row['isDuplicate'] = exists;
          row['action'] = exists ? 'update' : 'add';
        }
      }

      if (mounted) {
        setState(() => busy = false);
        if (context.mounted) {
          await showImportPreviewDialog(context, type, fileName, extractedRows);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          msg = 'فشل معالجة واستيراد الملف: $e';
          busy = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> parseRawRows(
      List<List<dynamic>> rows, String type) {
    List<Map<String, dynamic>> list = [];
    for (final row in rows) {
      String z(int i) => i < row.length ? '${row[i]}'.trim() : '';
      final name = z(0);
      if (name.isEmpty) continue;

      if (type == 'customers') {
        list.add({
          'name': name,
          'phone': z(1),
          'balance': double.tryParse(z(2)) ?? 0.0,
          'notes': z(3),
        });
      } else {
        list.add({
          'name': name,
          'category': z(1),
          'qty': double.tryParse(z(2)) ?? 0.0,
          'minimum': double.tryParse(z(3)) ?? 0.0,
          'price': double.tryParse(z(4)) ?? 0.0,
          'unit': z(5).isEmpty ? 'قطعة' : z(5),
        });
      }
    }
    return list;
  }

  List<Map<String, dynamic>> extractPdfRows(List<int> bytes, String type) {
    final List<Map<String, dynamic>> list = [];
    try {
      final rawStr = latin1.decode(bytes);
      // Clean and extract text blocks/lines from PDF
      final lines = rawStr
          .split(RegExp(r'[\r\n]+'))
          .map((l) => l.trim())
          .where((l) =>
              l.contains(',') ||
              l.contains(';') ||
              l.contains('\t') ||
              l.split(RegExp(r'\s+')).length >= 2)
          .toList();

      for (final line in lines) {
        final parts = line
            .split(RegExp(r'[,;\t]'))
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList();
        if (parts.isEmpty) {
          continue;
        }

        final name = parts[0];
        if (name.isEmpty ||
            name.toLowerCase().contains('name') ||
            name.toLowerCase().contains('الاسم')) {
          continue;
        }

        if (type == 'customers') {
          list.add({
            'name': name,
            'phone': parts.length > 1 ? parts[1] : '',
            'balance':
                double.tryParse(parts.length > 2 ? parts[2] : '0') ?? 0.0,
            'notes': parts.length > 3 ? parts[3] : '',
          });
        } else {
          list.add({
            'name': name,
            'category': parts.length > 1 ? parts[1] : 'عام',
            'qty': double.tryParse(parts.length > 2 ? parts[2] : '0') ?? 0.0,
            'minimum':
                double.tryParse(parts.length > 3 ? parts[3] : '5') ?? 0.0,
            'price': double.tryParse(parts.length > 4 ? parts[4] : '0') ?? 0.0,
            'unit': parts.length > 5 ? parts[5] : 'قطعة',
          });
        }
      }
    } catch (_) {}
    return list;
  }

  Future<void> showImportPreviewDialog(
    BuildContext c,
    String type,
    String fileName,
    List<Map<String, dynamic>> rows,
  ) async {
    final appState = c.read<AppState>();

    await showDialog(
      context: c,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: card,
          title: Text('معاينة استيراد $fileName (${rows.length} سجل)'),
          content: SizedBox(
            width: double.maxFinite,
            height: 360,
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final r = rows[i];
                final isDup = r['isDuplicate'] == true;
                return Card(
                  color: bg,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    dense: true,
                    title: Text(
                      '${r['name']} ${isDup ? "(موجود سابقاً)" : ""}',
                      style: TextStyle(
                        color: isDup ? gold : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      type == 'customers'
                          ? 'هاتف: ${r['phone']} | رصيد: ${r['balance']}'
                          : 'تصنيف: ${r['category']} | كمية: ${r['qty']} ${r['unit']}',
                    ),
                    trailing: DropdownButton<String>(
                      value: r['action'] as String,
                      dropdownColor: card,
                      items: const [
                        DropdownMenuItem(value: 'add', child: Text('إضافة')),
                        DropdownMenuItem(value: 'update', child: Text('تحديث')),
                        DropdownMenuItem(value: 'ignore', child: Text('تجاهل')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => r['action'] = val);
                        }
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: green),
              onPressed: () async {
                final d = await DB.d;
                int added = 0, updated = 0, ignored = 0;

                for (final row in rows) {
                  final act = row['action'];
                  if (act == 'ignore') {
                    ignored++;
                    continue;
                  }

                  if (type == 'customers') {
                    if (act == 'add') {
                      await d.insert('customers', {
                        'name': row['name'],
                        'phone': row['phone'],
                        'balance': row['balance'],
                        'notes': row['notes'],
                        'created': DateTime.now().toIso8601String(),
                      });
                      added++;
                    } else if (act == 'update') {
                      await d.update(
                        'customers',
                        {
                          'phone': row['phone'],
                          'balance': row['balance'],
                          'notes': row['notes'],
                        },
                        where: 'name=?',
                        whereArgs: [row['name']],
                      );
                      updated++;
                    }
                  } else {
                    if (act == 'add') {
                      await d.insert('products', {
                        'name': row['name'],
                        'category': row['category'],
                        'qty': row['qty'],
                        'minimum': row['minimum'],
                        'price': row['price'],
                        'unit': row['unit'],
                        'created': DateTime.now().toIso8601String(),
                      });
                      added++;
                    } else if (act == 'update') {
                      await d.update(
                        'products',
                        {
                          'category': row['category'],
                          'qty': row['qty'],
                          'minimum': row['minimum'],
                          'price': row['price'],
                          'unit': row['unit'],
                        },
                        where: 'name=?',
                        whereArgs: [row['name']],
                      );
                      updated++;
                    }
                  }
                }

                await appState.refresh();
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                setState(() => msg =
                    'نتيجة الاستيراد إلى قاعدة البيانات: إضافة ($added)، تحديث ($updated)، تجاهل ($ignored).');
              },
              child: const Text('تأكيد وإدخال إلى SQLite'),
            ),
          ],
        ),
      ),
    );
  }
}

class Chat extends StatefulWidget {
  const Chat({super.key});

  @override
  State<Chat> createState() => _Chat();
}

class _Chat extends State<Chat> {
  final q = TextEditingController();
  final ms = <Map<String, String>>[
    {
      'r': 'a',
      't':
          'مرحباً بك في المساعد الذكي. اسألني عن العملاء أو الأصناف أو الاستحقاقات.',
    },
  ];
  bool busy = false;

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('المساعد الذكي (AI)')),
        body: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(14),
                itemCount: ms.length,
                itemBuilder: (c, i) => Align(
                  alignment: ms[i]['r'] == 'u'
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(maxWidth: 340),
                    decoration: BoxDecoration(
                      color: ms[i]['r'] == 'u' ? blue : card,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(ms[i]['t']!),
                  ),
                ),
              ),
            ),
            if (busy)
              const LinearProgressIndicator(backgroundColor: bg, color: blue),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: q,
                      decoration: const InputDecoration(
                          hintText: 'اكتب سؤالك عن بيانات التطبيق...'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: busy ? null : send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Future<void> send() async {
    final text = q.text.trim();
    if (text.isEmpty) return;
    setState(() {
      ms.add({'r': 'u', 't': text});
      q.clear();
      busy = true;
    });

    final s = context.read<AppState>();
    try {
      if (s.key.trim().isEmpty) {
        ms.add({
          'r': 'a',
          't': 'يرجى إدخال API Key من شاشة الإعدادات لتفعيل المساعد الذكي.',
        });
        return;
      }

      final contextData = {
        'إجمالي العملاء': s.customers.length,
        'قائمة العملاء': s.customers
            .take(15)
            .map((e) => {'اسم': e['name'], 'رصيد': e['balance']})
            .toList(),
        'إجمالي الأصناف': s.products.length,
        'أصناف منخفضة': s.products
            .where(
                (e) => (e['qty'] as num? ?? 0) <= (e['minimum'] as num? ?? 0))
            .map((e) => {'اسم': e['name'], 'متبقي': e['qty']})
            .toList(),
        'إجمالي الاستحقاقات المعلقة':
            s.dues.where((e) => e['status'] == 'pending').length,
        'إحصاءات الأرصدة': s.st,
      };

      final dataStr = jsonEncode(contextData);
      final r = await http
          .post(
            Uri.parse(s.base),
            headers: {
              'Authorization': 'Bearer ${s.key.trim()}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': s.model,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      'أنت مساعد إدارة عمل عربي ذكي وموثوق. تجيب فقط استناداً للبيانات المتاحة. لا تبتكر أرصدة أو كميات غير موجودة. بيانات التطبيق الحالية: $dataStr'
                },
                {'role': 'user', 'content': text}
              ],
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (r.statusCode >= 200 && r.statusCode < 300) {
        final j = jsonDecode(r.body);
        final reply = j['choices']?[0]?['message']?['content'] ??
            'لم يتم استلام رد من المزود.';
        ms.add({'r': 'a', 't': reply.toString().trim()});
      } else {
        ms.add({
          'r': 'a',
          't':
              'فشل الاتصال بالمزود (رمز الحالة: ${r.statusCode}). يرجى التأكد من المفتاح والإعدادات.'
        });
      }
    } catch (e) {
      ms.add({'r': 'a', 't': 'حدث خطأ أثناء الاتصال: $e'});
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    q.dispose();
    super.dispose();
  }
}

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _Settings();
}

class _Settings extends State<Settings> {
  late TextEditingController k, m, b;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    k = TextEditingController(text: s.key);
    m = TextEditingController(text: s.model);
    b = TextEditingController(text: s.base);
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('إعدادات التطبيق و AI')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('إعدادات مزود الذكاء الاصطناعي',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            TextField(
              controller: k,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'API Key', hintText: 'sk-or-v1-...'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: m,
              decoration: const InputDecoration(
                  labelText: 'اسم النموذج (Model)',
                  hintText: 'openai/gpt-oss-20b:free'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: b,
              decoration: const InputDecoration(
                  labelText: 'عنوان المزود (Base URL)',
                  hintText: 'https://openrouter.ai/api/v1/chat/completions'),
            ),
            const SizedBox(height: 15),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: blue, padding: const EdgeInsets.all(14)),
              onPressed: () async {
                await c
                    .read<AppState>()
                    .saveAI(k.text.trim(), m.text.trim(), b.text.trim());
                if (c.mounted) {
                  ScaffoldMessenger.of(c).showSnackBar(
                    const SnackBar(content: Text('تم حفظ الإعدادات بنجاح')),
                  );
                }
              },
              child: const Text('حفظ الإعدادات'),
            ),
            const SizedBox(height: 20),
            const Card(
              color: card,
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'تنبيه أمان: لا تضع مفتاح API داخل كود المستودع. أدخله دائماً من هذه الشاشة داخل التطبيق.',
                  style: TextStyle(color: gold, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      );

  @override
  void dispose() {
    k.dispose();
    m.dispose();
    b.dispose();
    super.dispose();
  }
}

class Empty extends StatelessWidget {
  final String t;
  const Empty(this.t, {super.key});

  @override
  Widget build(BuildContext c) => Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Text(t, style: const TextStyle(color: muted)),
        ),
      );
}
