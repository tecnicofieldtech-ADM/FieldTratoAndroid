import "package:flutter/material.dart";
import "features/espelho/controller/pa_server_controller.dart";
import "features/espelho/data/mirror_targets_repo.dart";
import "features/espelho/ui/pa_dashboard_page.dart";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RFeedPaApp());
}

class RFeedPaApp extends StatelessWidget {
  const RFeedPaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = MirrorTargetsRepo();
    final server = PaServerController(repo: repo, port: 9000);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "RFeed Pá",
      theme: ThemeData(
        useMaterial3: true,
      ),
      home: PaDashboardPage(repo: repo, server: server),
    );
  }
}
