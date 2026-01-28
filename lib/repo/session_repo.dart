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

  Future<String?> getUserId() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getString(_kUserId);
    return (v == null || v.trim().isEmpty) ? null : v;
  }

  Future<String?> getUserNome() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getString(_kUserNome);
    return (v == null || v.trim().isEmpty) ? null : v;
  }

  Future<String?> getUserLogin() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getString(_kUserLogin);
    return (v == null || v.trim().isEmpty) ? null : v;
  }

  Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kUserId);
    await sp.remove(_kUserNome);
    await sp.remove(_kUserLogin);
  }
}
