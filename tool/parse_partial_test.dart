import '../lib/helpers/scale_comm.dart';

void main() {
  for (final line in [
    'PB: 0-176 T: 00000',
    '**: 0-181 *: 00000',
    'PB: 0',
    'PB: 0-',
    'PB: 01234 T: 00000',
    'PB: 0 T: 00000',
    '-10',
    'ST,GS,-00010kg',
  ]) {
    final field = extractAlfaFixed6Field(line);
    print('"$line"');
    print('  field6=$field kg=${parseScaleWeightKg(line)}');
  }
}
