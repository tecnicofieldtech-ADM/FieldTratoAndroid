import "package:flutter/material.dart";
import "package:rfeed_pa/features/espelho/controller/pa_server_controller.dart";
import "package:rfeed_pa/features/espelho/data/mirror_targets_repo.dart";
import "package:rfeed_pa/features/espelho/ui/pa_dashboard_page.dart";
import "package:rfeed_pa/features/espelho/ui/targets_list_page.dart";

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
      title: "RFeed Pa",
      theme: ThemeData(
        useMaterial3: true,
      ),
      home: PaStartPage(repo: repo, server: server),
    );
  }
}

class PaStartPage extends StatelessWidget {
  const PaStartPage({super.key, required this.repo, required this.server});

  final MirrorTargetsRepo repo;
  final PaServerController server;

  @override
  Widget build(BuildContext context) {
    return TargetsListPage(
      repo: repo,
      server: server,
      onSelected: (_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => PaDashboardPage(repo: repo, server: server),
          ),
        );
      },
    );
  }
}
