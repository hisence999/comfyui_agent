import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/workflow.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('comfy_mobile.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 2, onCreate: _createDB, onUpgrade: _onUpgrade);
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE workflows (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        content TEXT NOT NULL,
        last_modified INTEGER NOT NULL
      )
    ''');
    
    await db.execute('''
      CREATE TABLE history_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        prompt_id TEXT,
        workflow_json TEXT,
        params_json TEXT,
        image_path TEXT,
        created_at INTEGER
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE history_records (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          prompt_id TEXT,
          workflow_json TEXT,
          params_json TEXT,
          image_path TEXT,
          created_at INTEGER
        )
      ''');
    }
  }

  // Workflow CRUD
  Future<void> createWorkflow(Workflow workflow) async {
    final db = await instance.database;
    await db.insert('workflows', workflow.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Workflow?> readWorkflow(String id) async {
    final db = await instance.database;
    final maps = await db.query(
      'workflows',
      columns: ['id', 'name', 'content', 'last_modified'],
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return Workflow.fromMap(maps.first);
    } else {
      return null;
    }
  }

  Future<List<Workflow>> readAllWorkflows() async {
    final db = await instance.database;
    final result = await db.query('workflows', orderBy: 'last_modified DESC');
    return result.map((json) => Workflow.fromMap(json)).toList();
  }

  Future<int> updateWorkflow(Workflow workflow) async {
    final db = await instance.database;
    return db.update(
      'workflows',
      workflow.toMap(),
      where: 'id = ?',
      whereArgs: [workflow.id],
    );
  }
  
  Future<int> deleteWorkflow(String id) async {
    final db = await instance.database;
    return await db.delete(
      'workflows',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // History CRUD
  Future<int> createHistory(Map<String, dynamic> record) async {
    final db = await instance.database;
    return await db.insert('history_records', record);
  }

  Future<List<Map<String, dynamic>>> readAllHistory({int? limit, int? offset}) async {
    final db = await instance.database;
    return await db.query(
      'history_records', 
      orderBy: 'created_at DESC, id DESC', // Stable sort for pagination
      limit: limit,
      offset: offset,
    );
  }

  Future<int> deleteHistory(int id) async {
    final db = await instance.database;
    return await db.delete('history_records', where: 'id = ?', whereArgs: [id]);
  }
}
