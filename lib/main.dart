import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:sqflite/sqflite.dart';

const brandGreen = Color(0xFF176B45);
const darkGreen = Color(0xFF105337);
const mint = Color(0xFFEAF6EF);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_MX');
  await SalesDatabase.instance.database;
  runApp(const VentasCrocApp());
}

class VentasCrocApp extends StatelessWidget {
  const VentasCrocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ventas CROC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: brandGreen),
        scaffoldBackgroundColor: const Color(0xFFF3F7F4),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: brandGreen,
          foregroundColor: Colors.white,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: Color(0xFFCBD9CF)),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class Sale {
  const Sale({
    required this.id,
    required this.createdAt,
    required this.total,
    required this.discount,
    required this.payable,
    required this.payment,
    required this.change,
  });

  final int id;
  final DateTime createdAt;
  final double total;
  final double discount;
  final double payable;
  final double payment;
  final double change;

  Map<String, Object?> toMap() => {
        'created_at': createdAt.toIso8601String(),
        'total': total,
        'discount': discount,
        'payable': payable,
        'payment': payment,
        'change_amount': change,
      };

  factory Sale.fromMap(Map<String, Object?> map) => Sale(
        id: map['id'] as int,
        createdAt: DateTime.parse(map['created_at'] as String),
        total: (map['total'] as num).toDouble(),
        discount: (map['discount'] as num).toDouble(),
        payable: (map['payable'] as num).toDouble(),
        payment: (map['payment'] as num).toDouble(),
        change: (map['change_amount'] as num).toDouble(),
      );
}

class SalesDatabase {
  SalesDatabase._();
  static final SalesDatabase instance = SalesDatabase._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final dbPath = p.join(await getDatabasesPath(), 'ventas_croc.db');
    _database = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sales (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at TEXT NOT NULL,
            total REAL NOT NULL,
            discount REAL NOT NULL,
            payable REAL NOT NULL,
            payment REAL NOT NULL,
            change_amount REAL NOT NULL
          )
        ''');
      },
    );
    return _database!;
  }

  Future<int> insertSale(Sale sale) async {
    final db = await database;
    return db.insert('sales', sale.toMap());
  }

  Future<List<Sale>> getSales({DateTime? from, DateTime? to}) async {
    final db = await database;
    final where = <String>[];
    final args = <Object>[];
    if (from != null) {
      where.add('created_at >= ?');
      args.add(DateTime(from.year, from.month, from.day).toIso8601String());
    }
    if (to != null) {
      final end = DateTime(to.year, to.month, to.day)
          .add(const Duration(days: 1));
      where.add('created_at < ?');
      args.add(end.toIso8601String());
    }
    final rows = await db.query(
      'sales',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'created_at DESC',
    );
    return rows.map(Sale.fromMap).toList();
  }

  Future<void> deleteSale(int id) async {
    final db = await database;
    await db.delete('sales', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAll() async {
    final db = await database;
    await db.delete('sales');
  }
}

final moneyFormat = NumberFormat.currency(locale: 'es_MX', symbol: r'$');

double cents(double value) => (value * 100).roundToDouble() / 100;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  final _totalController = TextEditingController();
  final _paymentController = TextEditingController();
  final _totalFocus = FocusNode();
  DateTime? _from;
  DateTime? _to;
  List<Sale> _sales = [];
  bool _saving = false;

  double get _total => double.tryParse(_totalController.text) ?? 0;
  double get _discount => cents((_total < 0 ? 0 : _total) * .10);
  double get _payable => cents((_total < 0 ? 0 : _total) - _discount);
  double get _payment => double.tryParse(_paymentController.text) ?? 0;
  double get _change => cents(_payment - _payable);

  @override
  void initState() {
    super.initState();
    _refreshSales();
    _totalController.addListener(_update);
    _paymentController.addListener(_update);
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _totalController.dispose();
    _paymentController.dispose();
    _totalFocus.dispose();
    super.dispose();
  }

  Future<void> _refreshSales() async {
    final result = await SalesDatabase.instance.getSales(from: _from, to: _to);
    if (mounted) setState(() => _sales = result);
  }

  Future<void> _saveSale() async {
    if (_saving) return;
    final total = _total;
    final payment = _payment;
    if (!total.isFinite || total <= 0) {
      _showMessage('Ingresa un total mayor que \$0.00.');
      _totalFocus.requestFocus();
      return;
    }
    if (_paymentController.text.trim().isEmpty ||
        !payment.isFinite ||
        payment < 0) {
      _showMessage('Ingresa cuánto paga el cliente.');
      return;
    }
    if (payment < _payable) {
      _showMessage('El pago no alcanza. Faltan ${moneyFormat.format(_payable - payment)}.');
      return;
    }

    setState(() => _saving = true);
    try {
      final sale = Sale(
        id: 0,
        createdAt: DateTime.now(),
        total: cents(total),
        discount: _discount,
        payable: _payable,
        payment: cents(payment),
        change: cents(payment - _payable),
      );
      final id = await SalesDatabase.instance.insertSale(sale);
      final saved = Sale(
        id: id,
        createdAt: sale.createdAt,
        total: sale.total,
        discount: sale.discount,
        payable: sale.payable,
        payment: sale.payment,
        change: sale.change,
      );
      if (!mounted) return;
      _totalController.clear();
      _paymentController.clear();
      await _refreshSales();
      _showMessage('Venta guardada. Total: ${moneyFormat.format(saved.payable)}');
      await _showSaleDialog(saved);
    } catch (e) {
      _showMessage('No se pudo guardar la venta: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showSaleDialog(Sale sale) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¡Venta generada!'),
        content: Text(
          'Total a pagar: ${moneyFormat.format(sale.payable)}\n'
          'Cambio: ${moneyFormat.format(sale.change)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _printTicket(sale);
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Generar PDF'),
          ),
        ],
      ),
    );
  }

  Future<void> _printTicket(Sale sale) async {
    final pdf = pw.Document();
    final date = DateFormat('dd/MM/yyyy HH:mm', 'es_MX').format(sale.createdAt);
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, 180 * PdfPageFormat.mm,
            marginAll: 5 * PdfPageFormat.mm),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Column(children: [
                pw.Text('Abarrotes · El Mana',
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text('VENTAS CROC · Descuento del 10%', textAlign: pw.TextAlign.center),
              ]),
            ),
            pw.Divider(borderStyle: pw.BorderStyle.dashed),
            pw.Text('Fecha: $date'),
            pw.Divider(borderStyle: pw.BorderStyle.dashed),
            _pdfRow('Total de productos', moneyFormat.format(sale.total)),
            _pdfRow('Descuento CROC (10%)', '-${moneyFormat.format(sale.discount)}'),
            pw.Divider(borderStyle: pw.BorderStyle.dashed),
            _pdfRow('TOTAL A PAGAR', moneyFormat.format(sale.payable), bold: true),
            _pdfRow('Pago recibido', moneyFormat.format(sale.payment)),
            _pdfRow('Cambio', moneyFormat.format(sale.change)),
            pw.Divider(borderStyle: pw.BorderStyle.dashed),
            pw.SizedBox(height: 8),
            pw.Center(child: pw.Text('¡Gracias por su compra!')),
            pw.Center(child: pw.Text('Abarrotes · El Mana')),
          ],
        ),
      ),
    );
    final Uint8List bytes = await pdf.save();
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Ticket_CROC_${sale.id}.pdf',
    );
  }

  pw.Widget _pdfRow(String label, String value, {bool bold = false}) {
    final style = pw.TextStyle(
      fontSize: bold ? 11 : 9,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(child: pw.Text(label, style: style)),
          pw.SizedBox(width: 8),
          pw.Text(value, style: style),
        ],
      ),
    );
  }

  Future<void> _chooseDate({required bool from}) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('es', 'MX'),
    );
    if (selected == null) return;
    setState(() {
      if (from) {
        _from = selected;
      } else {
        _to = selected;
      }
    });
    await _refreshSales();
  }

  Future<void> _deleteSale(Sale sale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar venta'),
        content: Text('¿Eliminar la venta de ${moneyFormat.format(sale.payable)}? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await SalesDatabase.instance.deleteSale(sale.id);
      await _refreshSales();
    }
  }

  Future<void> _clearHistory() async {
    if (_sales.isEmpty) {
      _showMessage('El historial ya está vacío.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar historial'),
        content: const Text('¿Seguro que deseas borrar todas las ventas guardadas? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar todo'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await SalesDatabase.instance.deleteAll();
      await _refreshSales();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Abarrotes · El Mana', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            Text('Ventas CROC', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Nueva venta'), icon: Icon(Icons.point_of_sale)),
                  ButtonSegment(value: 1, label: Text('Historial'), icon: Icon(Icons.history)),
                ],
                selected: {_tab},
                onSelectionChanged: (value) {
                  setState(() => _tab = value.first);
                  if (_tab == 1) _refreshSales();
                },
              ),
            ),
            Expanded(child: _tab == 0 ? _buildSaleForm() : _buildHistory()),
          ],
        ),
      ),
    );
  }

  Widget _buildSaleForm() {
    final date = DateFormat('EEEE d MMMM yyyy', 'es_MX').format(DateTime.now());
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Card(
          color: Colors.white,
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Registrar venta', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: mint, borderRadius: BorderRadius.circular(13)),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month, color: darkGreen, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Fecha de la venta', style: TextStyle(color: Colors.black54)),
                            Text(date, style: const TextStyle(fontWeight: FontWeight.bold, color: darkGreen)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _fieldLabel('1. Total de venta'),
                TextField(
                  controller: _totalController,
                  focusNode: _totalFocus,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(prefixText: '\$ ', hintText: '0.00'),
                ),
                const SizedBox(height: 15),
                _fieldLabel('2. Descuento CROC (10%)'),
                InputDecorator(
                  decoration: const InputDecoration(prefixText: '\$ '),
                  child: Text(_discount.toStringAsFixed(2), style: const TextStyle(fontSize: 20, color: darkGreen, fontWeight: FontWeight.bold)),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 5),
                  child: Text('Se calcula automáticamente sobre el total.', style: TextStyle(color: Colors.black54, fontSize: 12)),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: mint, borderRadius: BorderRadius.circular(13)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total a pagar con descuento', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(moneyFormat.format(_payable), style: const TextStyle(fontSize: 25, color: darkGreen, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                const SizedBox(height: 17),
                _fieldLabel('3. ¿Con cuánto paga el cliente?'),
                TextField(
                  controller: _paymentController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(prefixText: '\$ ', hintText: '0.00'),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF8BB89B), style: BorderStyle.solid),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Column(
                    children: [
                      const Text('4. Cambio para el cliente', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 5),
                      Text(
                        _paymentController.text.isEmpty
                            ? moneyFormat.format(0)
                            : _change < 0
                                ? 'Faltan ${moneyFormat.format(_change.abs())}'
                                : moneyFormat.format(_change),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800, color: _paymentController.text.isNotEmpty && _change < 0 ? Colors.red : darkGreen),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _saving ? null : _saveSale,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(_saving ? 'Guardando...' : 'Generar venta'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    backgroundColor: brandGreen,
                    textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      );

  Widget _buildHistory() {
    final total = cents(_sales.fold<double>(0, (sum, sale) => sum + sale.payable));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('Filtrar por fecha', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17))),
                      TextButton(onPressed: () {
                        setState(() { _from = null; _to = null; });
                        _refreshSales();
                      }, child: const Text('Limpiar')),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: OutlinedButton.icon(
                        onPressed: () => _chooseDate(from: true),
                        icon: const Icon(Icons.calendar_today, size: 17),
                        label: Text(_from == null ? 'Desde' : DateFormat('dd/MM/yy').format(_from!)),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: OutlinedButton.icon(
                        onPressed: () => _chooseDate(from: false),
                        icon: const Icon(Icons.event, size: 17),
                        label: Text(_to == null ? 'Hasta' : DateFormat('dd/MM/yy').format(_to!)),
                      )),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: mint, borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_sales.length} ${_sales.length == 1 ? 'venta encontrada' : 'ventas encontradas'}'),
                        const SizedBox(height: 3),
                        Text('Total vendido después del descuento: ${moneyFormat.format(total)}', style: const TextStyle(color: darkGreen, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _clearHistory,
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: const Text('Borrar historial'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: _sales.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 52, color: Colors.black38),
                        SizedBox(height: 10),
                        Text('Todavía no hay ventas registradas.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('Las ventas que generes aparecerán aquí.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  itemCount: _sales.length,
                  itemBuilder: (context, index) {
                    final sale = _sales[index];
                    return Card(
                      color: Colors.white,
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ExpansionTile(
                        leading: const CircleAvatar(backgroundColor: mint, child: Icon(Icons.receipt, color: darkGreen)),
                        title: Text(moneyFormat.format(sale.payable), style: const TextStyle(fontWeight: FontWeight.bold, color: darkGreen)),
                        subtitle: Text(DateFormat('dd/MM/yyyy HH:mm', 'es_MX').format(sale.createdAt)),
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        children: [
                          _detailRow('Total de productos', moneyFormat.format(sale.total)),
                          _detailRow('Descuento CROC (10%)', '-${moneyFormat.format(sale.discount)}'),
                          _detailRow('Total a pagar', moneyFormat.format(sale.payable)),
                          _detailRow('Pago recibido', moneyFormat.format(sale.payment)),
                          _detailRow('Cambio', moneyFormat.format(sale.change)),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () => _printTicket(sale),
                                  icon: const Icon(Icons.picture_as_pdf),
                                  label: const Text('Ticket PDF'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Eliminar venta',
                                onPressed: () => _deleteSale(sale),
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
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
    );
  }

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: Colors.black54))),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
