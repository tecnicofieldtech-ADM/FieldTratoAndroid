import '../lib/helpers/scale_comm.dart';

void main() {
  for (final model in ScaleModel.values) {
    print('--- $model ---');
    for (final line in [
      'PB: 0-17',
      'PB:0-10',
      'PB: 0-176 T: 00000',
      '**: 0-177 *: 00000',
      '**: 0-181 *: 00000',
      '-10',
      'ST,GS,-00010kg',
    ]) {
      print('$line => ${parseScaleWeightKg(line, model: model)}');
    }
  }
}
