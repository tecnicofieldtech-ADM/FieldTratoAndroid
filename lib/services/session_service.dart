// lib/services/session_service.dart
import "../repo/session_repo.dart";

class SessionUser {
  final String id;
  final String nome;
  final String login;

  const SessionUser({
    required this.id,
    required this.nome,
    required this.login,
  });
}

class SessionService {
  SessionService._();
  static final SessionService instance = SessionService._();

  final SessionRepo _repo = SessionRepo();

  SessionUser? _current;
  SessionUser? get current => _current;

  String? get userId => _current?.id;
  bool get isLogged => _current != null;

  /// Chame isso no boot do app (main) pra restaurar sessão.
  Future<void> restore() async {
    final row = await _repo.getLogin();
    if (row == null) {
      _current = null;
      return;
    }

    final id = (row["ID"] ?? "").toString().trim();
    if (id.isEmpty) {
      _current = null;
      return;
    }

    _current = SessionUser(
      id: id,
      nome: (row["NOME"] ?? "").toString(),
      login: (row["LOGIN"] ?? "").toString(),
    );
  }

  Future<void> setLogin({
    required String userId,
    required String nome,
    required String login,
  }) async {
    _current = SessionUser(id: userId, nome: nome, login: login);
    await _repo.saveLogin(userId: userId, nome: nome, login: login);
  }

  Future<void> logout() async {
    _current = null;
    await _repo.clearLogin();
  }
}


