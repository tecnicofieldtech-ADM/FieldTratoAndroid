// lib/repo/session_repo.dart
import "package:shared_preferences/shared_preferences.dart";

class SessionRepo {
  static const _kUserId = "sess_user_id";
  static const _kUserNome = "sess_user_nome";
  static const _kUserLogin = "sess_user_login";

  Future<void> saveLogin({
    required String userId,
    required String nome,
    required String login,
  }) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kUserId, userId);
    await sp.setString(_kUserNome, nome);
    await sp.setString(_kUserLogin, login);
  }

  Future<Map<String, String>?> getLogin() async {
    final sp = await SharedPreferences.getInstance();

    final id = sp.getString(_kUserId);
    if (id == null || id.trim().isEmpty) return null;

    return {
      "ID": id,
      "NOME": sp.getString(_kUserNome) ?? "",
      "LOGIN": sp.getString(_kUserLogin) ?? "",
    };
  }

  Future<void> clearLogin() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kUserId);
    await sp.remove(_kUserNome);
    await sp.remove(_kUserLogin);
  }
}
