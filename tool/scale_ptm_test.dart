import 'dart:io';

import '../lib/helpers/scale_comm.dart';
import '../lib/helpers/scale_frame.dart';

void main() {
  var failed = 0;

  void check(String name, bool ok, [String? detail]) {
    if (ok) {
      stdout.writeln('OK  $name');
    } else {
      failed++;
      stdout.writeln('FAIL $name${detail == null ? "" : "  $detail"}');
    }
  }

  // Manual: 0x02+0xD3+0x30+0x33 = 0x0138 → CK1=0x33 CK0=0x38
  final exampleCk = ptmAv40Checksum(const [0x02, 0xD3, 0x30, 0x33]);
  check(
    'checksum do exemplo do manual',
    exampleCk[0] == 0x33 && exampleCk[1] == 0x38,
    'got ${exampleCk.map((b) => b.toRadixString(16)).toList()}',
  );

  const samples = <double>[-176, -10, 0, 15, 1234, 99999];
  for (final kg in samples) {
    final pkt = encodePtmAv40Packet(kg);
    check('pacote 48 bytes $kg', pkt.length == ptmAv40PacketLen);
    check('START/STOP $kg', pkt.first == 0x02 && pkt.last == 0x03);
    check('checksum do pacote $kg', ptmAv40ChecksumOk(pkt));
    check(
      'DIGIT bytes 36-40 $kg',
      parsePtmAv40Packet(pkt) == kg.round().toDouble(),
      'got ${parsePtmAv40Packet(pkt)}',
    );

    final frame = encodePtmAv40Frame(kg);
    final parsed = parseScaleWeightKg(frame, model: ScaleModel.ptm);
    check(
      'PTM encode/decode string $kg',
      parsed == kg.round().toDouble(),
      'got $parsed',
    );
  }

  const captura =
      '10T ▒▒<8PESO TOTAL      R001:               10T ▒▒<8PESO TOTAL      R001:               10T ▒▒<8PESO TOTAL      R001:';
  check(
    'captura serial 10T + PESO TOTAL + R001',
    parseScaleWeightKg(captura, model: ScaleModel.ptm) == 10,
    'got ${parseScaleWeightKg(captura, model: ScaleModel.ptm)}',
  );

  check(
    'nao ler 8 de <8PESO (checksum ASCII, nao peso)',
    parseScaleWeightKg('<8PESO TOTAL      R001:', model: ScaleModel.ptm) == null,
    'got ${parseScaleWeightKg('<8PESO TOTAL      R001:', model: ScaleModel.ptm)}',
  );

  check(
    'nao ler 001 de R001',
    parseScaleWeightKg('PESO TOTAL      R001:', model: ScaleModel.ptm) == null,
    'got ${parseScaleWeightKg('PESO TOTAL      R001:', model: ScaleModel.ptm)}',
  );

  const mudou =
      '10T ▒▒<8PESO TOTAL      R001:               250T ▒▒<8PESO TOTAL      R001:';
  check(
    'ultimo NNNNT no buffer',
    parseScaleWeightKg(mudou, model: ScaleModel.ptm) == 250,
    'got ${parseScaleWeightKg(mudou, model: ScaleModel.ptm)}',
  );

  final topcon = encodeScaleFrame(2840, ScaleModel.topcom);
  check(
    'Topcon ST,GS',
    parseScaleWeightKg(topcon, model: ScaleModel.topcom) == 2840,
    'frame=$topcon parsed=${parseScaleWeightKg(topcon)}',
  );

  if (failed > 0) {
    stderr.writeln('$failed teste(s) falharam');
    exit(1);
  }
  stdout.writeln('Todos os testes PTM/AV40 passaram.');
}
