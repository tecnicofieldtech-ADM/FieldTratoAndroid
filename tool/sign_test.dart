import '../lib/helpers/scale_comm.dart';

void test(String line) {
  final f = extractAlfaFixed6Field(line);
  print('"$line"');
  print('  field6="$f" => ${parseScaleWeightKg(line)}');
}

void main() {
  for (final l in [
    'PB: 0-15 T: 00000',
    'PB:0-15 T: 00000',
    'PB: 0-15 T:00000',
    'PB: 0-176 T: 00000',
    'PB:0-176 T: 00000',
    '**: 0-15 *: 00000',
    '**:0-15 *: 00000',
    'PB:  15- T: 00000',
    'PB: -15  T: 00000',
  ]) {
    test(l);
  }
}
