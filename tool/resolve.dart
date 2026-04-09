import "dart:isolate";
import "dart:io";

Future<void> main() async {
  final uri = Uri.parse("package:field_trato/features/fabricacao/ui/fabricacao_list_page.dart");
  final resolved = await Isolate.resolvePackageUri(uri);
  stdout.writeln("resolved=$resolved");
  if (resolved != null) {
    stdout.writeln("exists=${File.fromUri(resolved).existsSync()}");
  }
}
