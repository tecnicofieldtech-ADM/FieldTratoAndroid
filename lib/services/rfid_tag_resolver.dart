import "../repo/config_repo.dart";
import "../utils/rfid_tag_utils.dart";

/// Resolve EPC lido vs gravado no banco conforme CONFIG (prefixo RFID).
class RfidTagResolver {
  RfidTagResolver({ConfigRepo? configRepo})
      : _cfg = configRepo ?? ConfigRepo();

  final ConfigRepo _cfg;

  RfidPrefixConfig? _cached;

  Future<RfidPrefixConfig> prefixConfig() async {
    if (_cached != null) return _cached!;
    final ignore = await _cfg.getIgnorarPrefixoRfid();
    final letter = await _cfg.getPrefixoRfid();
    _cached = RfidPrefixConfig(
      ignorePrefix: ignore,
      prefixLetter: letter,
    );
    return _cached!;
  }

  void invalidateCache() => _cached = null;

  Future<List<String>> lookupCandidates(String rawEpc) async {
    final cfg = await prefixConfig();
    return RfidTagUtils.lookupCandidates(rawEpc, config: cfg);
  }

  Future<bool> matches(String readEpc, String storedEpc) async {
    final cfg = await prefixConfig();
    return RfidTagUtils.matches(
      readEpc,
      storedEpc,
      config: cfg,
    );
  }

  Future<({String clause, List<Object?> args})> sqlRfidEquals(
    String columnExpr,
    String rawEpc,
  ) async {
    final candidates = await lookupCandidates(rawEpc);
    return RfidTagUtils.sqlRfidEquals(columnExpr, candidates);
  }
}
