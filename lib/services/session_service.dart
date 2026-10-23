// lib/services/session_service.dart
import "../repo/last_login_repo.dart";
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
  final LastLoginRepo _lastLoginRepo = LastLoginRepo();

  SessionUser? _current;
  SessionUser? get current => _current;

  String? get userId => _current?.id;
  bool get isLogged => _current != null;

  /// Boot do app: limpa sessão persistida. Cada abertura exige login/senha.
  /// Mantém apenas o último usuário para pré-seleção na tela de login.
  Future<void> restore() async {
    _current = null;
    await _repo.clearLogin();
  }

  Future<void> setLogin({
    required String userId,
    required String nome,
    required String login,
    String? cargo,
  }) async {
    _current = SessionUser(id: userId, nome: nome, login: login);
    // Sessão só em memória — não grava login ativo no SharedPreferences.
    await _repo.saveLastUserOnly(userId: userId);
    await _lastLoginRepo.save(
      userId: userId,
      nome: nome,
      login: login,
      cargo: cargo,
    );
  }

  Future<void> logout() async {
    _current = null;
    await _repo.clearLogin();
  }
}


