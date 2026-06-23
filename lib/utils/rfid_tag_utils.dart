/// Normalização e variantes de EPC para antenas com prefixo (ex.: Intelbras H).
class RfidPrefixConfig {
  const RfidPrefixConfig({
    required this.ignorePrefix,
    required this.prefixLetter,
  });

  final bool ignorePrefix;
  final String prefixLetter;

  static const disabled = RfidPrefixConfig(ignorePrefix: false, prefixLetter: "");
}

class RfidTagUtils {
  static String normalizeRawEpc(String raw) {
    var t = raw.trim();
    final up = t.toUpperCase();
    final idx = up.indexOf("EPC:");
    if (idx >= 0) t = t.substring(idx + 4).trim();
    if (t.startsWith(";")) t = t.substring(1).trim();
    return t.replaceAll(RegExp(r"[\s\r\n]+"), "").toUpperCase();
  }

  static String sanitizePrefixLetter(String? raw) {
    final t = (raw ?? "").trim().toUpperCase();
    if (t.isEmpty) return "";
    return t.substring(0, 1);
  }

  /// Variantes para consulta no banco quando o prefixo deve ser ignorado.
  ///
  /// Ex.: prefixo H, leitura `HF000...` (Intelbras) e banco `H000...` ou `F000...`.
  static List<String> lookupCandidates(
    String rawEpc, {
    required RfidPrefixConfig config,
  }) {
    final base = normalizeRawEpc(rawEpc);
    if (base.isEmpty) return const [];

    final out = <String>{base};
    if (!config.ignorePrefix) return out.toList();

    final p = sanitizePrefixLetter(config.prefixLetter);
    if (p.isEmpty) return out.toList();

    void add(String v) {
      final n = normalizeRawEpc(v);
      if (n.isNotEmpty) out.add(n);
    }

    if (base.startsWith(p) && base.length > 1) {
      add(base.substring(1));
    }

    if (base.startsWith("F") && base.length > 1) {
      add("$p${base.substring(1)}");
      add("$p$base");
    }

    if (!base.startsWith(p)) {
      add("$p$base");
    }

    var stripped = base;
    while (stripped.startsWith(p) && stripped.length > 1) {
      stripped = stripped.substring(1);
      add(stripped);
      add("$p$stripped");
    }

    return out.toList();
  }

  static bool matches(
    String readEpc,
    String storedEpc, {
    required RfidPrefixConfig config,
  }) {
    final a = lookupCandidates(readEpc, config: config);
    final b = lookupCandidates(storedEpc, config: config);
    for (final x in a) {
      for (final y in b) {
        if (x == y) return true;
      }
    }
    return false;
  }

  static ({String clause, List<Object?> args}) sqlRfidEquals(
    String columnExpr,
    List<String> candidates,
  ) {
    final list = candidates
        .map(normalizeRawEpc)
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (list.isEmpty) {
      return (clause: "1=0", args: const []);
    }
    if (list.length == 1) {
      return (
        clause: "UPPER(TRIM($columnExpr)) = UPPER(TRIM(?))",
        args: [list.first],
      );
    }
    final placeholders = List.filled(list.length, "?").join(",");
    return (
      clause: "UPPER(TRIM($columnExpr)) IN ($placeholders)",
      args: list,
    );
  }
}
