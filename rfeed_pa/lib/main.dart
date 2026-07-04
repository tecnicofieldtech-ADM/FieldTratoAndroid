import "package:flutter/material.dart";
import "package:rfeed_pa/features/espelho/controller/pa_client_controller.dart";
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
    final client = PaClientController(repo: repo);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "RFeed Pa",
      theme: ThemeData(
        useMaterial3: true,
      ),
      home: PaStartPage(repo: repo, client: client),
    );
  }
}

class PaStartPage extends StatelessWidget {
  const PaStartPage({super.key, required this.repo, required this.client});

  final MirrorTargetsRepo repo;
  final PaClientController client;

  @override
  Widget build(BuildContext context) {
    return TargetsListPage(
      repo: repo,
      client: client,
      onSelected: (_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => PaDashboardPage(repo: repo, client: client),
          ),
        );
      },
    );
  }
}
