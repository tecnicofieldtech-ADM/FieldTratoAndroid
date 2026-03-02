import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class FabricacaoDb {
  FabricacaoDb._();
  static final FabricacaoDb instance = FabricacaoDb._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final base = await getDatabasesPath();
    final path = join(base, 'rfeed.db'); // ajuste se seu app já usa outro nome
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, v) async {
        // Se seu app já possui as tabelas, você pode remover o onCreate.
        // Mantive vazio pra não sobrescrever.
      },
    );
  }
}


