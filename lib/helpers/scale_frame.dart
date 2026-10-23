import "scale_comm.dart";

/// Pacote AV40/AV50 — manual *PROTOCOLO AV40_AV50*:
/// RS232 38400 8N1, 48 bytes, START 0x02 … STOP 0x03.
const int ptmAv40PacketLen = 48;

/// Monta o frame ASCII/binário que a balança enviaria no TCP/RS232.
String encodeScaleFrame(double kg, ScaleModel model) {
  switch (model) {
    case ScaleModel.ptm:
      return String.fromCharCodes(encodePtmAv40Packet(kg));
    case ScaleModel.topcom:
    case ScaleModel.dg500:
      return _encodeStGs(kg);
    case ScaleModel.alfa:
      return _encodeAlfa(kg);
    case ScaleModel.hook:
    case ScaleModel.raw:
      return "${kg.round()}\r\n";
  }
}

/// Compatível com o simulador/local: pacote binário de 48 bytes.
String encodePtmAv40Frame(double kg, {String receita = "R001:"}) =>
    String.fromCharCodes(encodePtmAv40Packet(kg, receita: receita));

List<int> encodePtmAv40Packet(double kg, {String receita = "R001:"}) {
  final n = kg.round().clamp(-9999, 99999);
  final buf = List<int>.filled(ptmAv40PacketLen, 0x20);
  buf[0] = 0x02;
  buf[1] = 0x30; // board ID ASCII '0'
  buf[2] = 0x30;
  final up = _ptmLcd16("PESO TOTAL");
  final down = _ptmLcd16(receita);
  for (var i = 0; i < 16; i++) {
    buf[3 + i] = up.codeUnitAt(i);
    buf[19 + i] = down.codeUnitAt(i);
  }
  buf[35] = 0x20; // cursor off, bit 0x20 sempre 1
  final digits = n.toString().padLeft(5);
  for (var i = 0; i < 5; i++) {
    buf[36 + i] = digits.codeUnitAt(i);
  }
  buf[41] = 0x54; // contexto 'T' (peso total)
  buf[42] = 0x20;
  buf[43] = 0x80; // DOT, bit 0x80 sempre 1
  buf[44] = 0x80; // VID, bit 0x80 sempre 1
  final ck = ptmAv40Checksum(buf);
  buf[45] = ck[0];
  buf[46] = ck[1];
  buf[47] = 0x03;
  return buf;
}

/// CK1/CK0: nibble alto/baixo do LSB da soma (START .. byte antes do checksum) + 0x30.
List<int> ptmAv40Checksum(List<int> packet) {
  var sum = 0;
  final last = packet.length >= 45 ? 45 : packet.length;
  for (var i = 0; i < last; i++) {
    sum += packet[i] & 0xFF;
  }
  final lsb = sum & 0xFF;
  return [0x30 + ((lsb >> 4) & 0x0F), 0x30 + (lsb & 0x0F)];
}

bool ptmAv40ChecksumOk(List<int> packet) {
  if (packet.length < ptmAv40PacketLen) return false;
  final ck = ptmAv40Checksum(packet);
  return packet[45] == ck[0] && packet[46] == ck[1];
}

String _ptmLcd16(String s) {
  if (s.length >= 16) return s.substring(0, 16);
  return s.padRight(16);
}

double? parsePtmAv40Packet(List<int> packet) {
  if (packet.length < ptmAv40PacketLen) return null;
  if (packet[0] != 0x02 || packet[47] != 0x03) return null;
  return _ptmDigitsToKg(packet.sublist(36, 41));
}

double? _ptmDigitsToKg(List<int> five) {
  final chars = String.fromCharCodes(five).replaceAll(RegExp(r"[\x00-\x1f]"), " ");
  final m = RegExp(r"([+-]?\d{1,5})").firstMatch(chars.trim());
  if (m == null) return null;
  return double.tryParse(m.group(1)!);
}

/// Varre um buffer de bytes e devolve o último peso de pacote 48 bytes válido.
double? parsePtmAv40Stream(List<int> bytes) {
  double? last;
  for (var i = 0; i + ptmAv40PacketLen <= bytes.length; i++) {
    if (bytes[i] != 0x02 || bytes[i + 47] != 0x03) continue;
    final pkt = bytes.sublist(i, i + ptmAv40PacketLen);
    if (!ptmAv40ChecksumOk(pkt)) continue;
    final kg = parsePtmAv40Packet(pkt);
    if (kg != null) last = kg;
  }
  return last;
}

/// Extrai kg do protocolo AV40 (pacote 48 bytes ou dump ASCII tipo `10T … PESO TOTAL`).
double? parsePtmWeightKg(String raw) {
  if (raw.isEmpty) return null;
  final fromPkt = parsePtmAv40Stream(raw.codeUnits);
  if (fromPkt != null) return fromPkt;

  var s = raw.replaceAll(RegExp(r"[\u2212\u2013\u2014]"), "-");
  final tMode = RegExp(r"([+-]?\d{1,6})\s*T(?![A-Za-z0-9])").allMatches(s).toList();
  if (tMode.isNotEmpty) {
    return double.tryParse(tMode.last.group(1)!);
  }

  final onlyDigits = RegExp(r"^\s*([+-]?\d{1,5})\s*$").firstMatch(s);
  if (onlyDigits != null) return double.tryParse(onlyDigits.group(1)!);

  return null;
}

String _encodeStGs(double kg) {
  final n = kg.round();
  final sign = n < 0 ? "-" : "+";
  final body = n.abs().toString().padLeft(6, "0");
  return "ST,GS,$sign${body}kg\r\n";
}

String _encodeAlfa(double kg) {
  final n = kg.round().clamp(-99999, 99999);
  final field = n < 0
      ? "0-${n.abs().toString().padLeft(3, " ")}"
      : n.toString().padLeft(6, " ");
  final six = field.length >= 6 ? field.substring(0, 6) : field.padRight(6);
  return "PB:$six T: 00000\r\n";
}
