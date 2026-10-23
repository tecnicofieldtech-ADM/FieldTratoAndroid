/// Claim/lease de carregamento estacionário (Etapa D).
///
/// Controle de concorrência — não altera FAB_STATUS / FLOW_MODE.
class StationClaim {
  StationClaim._();

  /// Lease curto: abandono (Wi‑Fi/app) libera a carga sem job em background.
  static const Duration claimLeaseDuration = Duration(minutes: 3);

  static const String statusAvailable = "available";
  static const String statusClaimedByMe = "claimedByMe";
  static const String statusClaimed = "claimed";

  static const String codeAlreadyClaimed = "ALREADY_CLAIMED";
  static const String codeAlreadyLoaded = "ALREADY_LOADED";
  static const String codeNotFound = "NOT_FOUND";
  static const String codeForbidden = "FORBIDDEN";
  static const String codeInvalid = "INVALID_REQUEST";
  static const String codeClaimUnsupported = "CLAIM_UNSUPPORTED_LEGACY_BRIDGE";

  static final RegExp uuidRe = RegExp(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
  );

  static bool isValidTruckDeviceId(String? raw) {
    final s = (raw ?? "").trim();
    return s.isNotEmpty && uuidRe.hasMatch(s);
  }

  static String nowIso([DateTime? t]) => (t ?? DateTime.now()).toIso8601String();

  static String expiresIso([DateTime? now]) {
    final n = now ?? DateTime.now();
    return n.add(claimLeaseDuration).toIso8601String();
  }

  /// Expira quando CLAIM_EXPIRES_AT <= now (relógio da estação).
  static bool isExpired(String? expiresAt, DateTime now) {
    final s = (expiresAt ?? "").trim();
    if (s.isEmpty) return true;
    final exp = DateTime.tryParse(s);
    if (exp == null) return true;
    return !exp.isAfter(now);
  }

  static String listStatus({
    required String? claimDeviceId,
    required String? claimExpiresAt,
    required DateTime now,
    String? viewerTruckDeviceId,
  }) {
    final cid = (claimDeviceId ?? "").trim();
    if (cid.isEmpty || isExpired(claimExpiresAt, now)) {
      return statusAvailable;
    }
    final viewer = (viewerTruckDeviceId ?? "").trim();
    if (viewer.isNotEmpty && cid == viewer) return statusClaimedByMe;
    return statusClaimed;
  }
}

enum ClaimOutcome {
  ok,
  alreadyOwned,
  conflict,
  notFound,
  alreadyLoaded,
  invalid,
  forbidden,
}

class ClaimResult {
  const ClaimResult({
    required this.outcome,
    this.handoffId = "",
    this.claimedBy = "",
    this.claimExpiresAt = "",
    this.alreadyOwned = false,
    this.message = "",
  });

  final ClaimOutcome outcome;
  final String handoffId;
  final String claimedBy;
  final String claimExpiresAt;
  final bool alreadyOwned;
  final String message;

  bool get ok =>
      outcome == ClaimOutcome.ok || outcome == ClaimOutcome.alreadyOwned;
}

class ReleaseResult {
  const ReleaseResult({
    required this.outcome,
    this.message = "",
  });

  final ClaimOutcome outcome;
  final String message;

  bool get ok =>
      outcome == ClaimOutcome.ok || outcome == ClaimOutcome.alreadyOwned;
}

class AckResult {
  const AckResult({
    required this.outcome,
    this.message = "",
    this.alreadyAcked = false,
  });

  final ClaimOutcome outcome;
  final String message;
  final bool alreadyAcked;

  bool get ok =>
      outcome == ClaimOutcome.ok || outcome == ClaimOutcome.alreadyOwned;
}
