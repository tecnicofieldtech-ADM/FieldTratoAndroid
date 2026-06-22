// lib/pages/config_page.dart
import "dart:async";
import "package:flutter/material.dart";

import "../repo/config_repo.dart";
import "../services/config_disk_backup.dart";
import "../repo/vagao_repo.dart";
import "../repo/fazenda_repo.dart";
import "../repo/user_repo.dart";
import "../services/bootstrap_sync.dart";
import "../services/wifi_guard.dart";
import "../features/estacionario/data/carregamento_estacionario_api.dart";
import "../features/fabricacao/domain/fabricacao_flow.dart";
import "../constants/config_options.dart";

// ✅ helper da balança
import "../helpers/scale_comm.dart";

// ✅ helper do RFID
import "../helpers/rfid_comm.dart";

class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  final _cfgRepo = ConfigRepo();
  final _vagaoRepo = VagaoRepo();
  final _fazendaRepo = FazendaRepo();
  final _userRepo = UserRepo();

  late final BootstrapSync _bootstrap = BootstrapSync(
    cfgRepo: _cfgRepo,
    vagaoRepo: _vagaoRepo,
    fazendaRepo: _fazendaRepo,
    userRepo: _userRepo,
  );

  final _hostCtrl = TextEditingController();
  final _portaCtrl = TextEditingController();
  final _ipBalancaCtrl = TextEditingController();
  final _portaBalancaCtrl = TextEditingController();
  final _ipRfidCtrl = TextEditingController();
  final _portaRfidCtrl = TextEditingController();
  final _ipEspelhoCtrl = TextEditingController();
  final _portaEspelhoCtrl = TextEditingController();
  final _hostEstacionarioCtrl = TextEditingController();
  final _portaEstacionarioCtrl = TextEditingController();
  final _stationWifiSsidCtrl = TextEditingController();
  final _stationWifiPasswordCtrl = TextEditingController();
  final _stationBaseUrlCtrl = TextEditingController();

  // NOVOS CONTROLES
  final _incrementoBalancaCtrl = TextEditingController();
  final _tempoPuloCtrl = TextEditingController();

  // ✅ FABRICAÇÃO (AJUSTADO)
  // TEMPO_MISTURA = MINUTOS (INTEGER)
  final _tempoMisturaCtrl = TextEditingController();

  // TOLERANCIA_CARREGAMENTO = PERCENTUAL (NUMERIC)
  final _toleranciaCarregCtrl = TextEditingController(); // % (ex: 2.5)

  int _backend = 0;
  int _operacao = 0;
  int _modeloBalanca = 0;
  int _modeloRfid = 0;
  int _modoSaidaFab = 0; // 0 = Pá | 1 = LED
  FabricacaoFlowMode _flowMode = FabricacaoFlowMode.fullOnStation;

  /// Estacionário: libera tile Carregamento no menu. Distribuidor: libera Nova fabricação na lista.
  bool _modoHibrido = false;

  bool _puloAutomatico = true;

  String? _idVagao;
  String? _nomeVagao;
  String? _idFazenda;

  bool _loadingVagao = false;
  bool _loadingFazendas = false;
  bool _saving = false;

  List<Map<String, Object?>> _vagoes = [];
  List<Map<String, Object?>> _fazendas = [];

  // ============================
  // ✅ TESTE BALANÇA
  // ============================
  bool _testingScale = false;
  String _scaleTestStatus = "—";
  String _scaleTestRaw = "—";
  String _scaleTestParsed = "—";

  ScaleComm? _scaleTestComm;
  StreamSubscription? _scaleStatusSub;
  StreamSubscription? _scaleWeightSub;
  Timer? _scaleTestTimeout;

  // ============================
  // ✅ TESTE RFID
  // ============================
  bool _testingRfid = false;
  String _rfidTestStatus = "—";
  String _rfidTestRaw = "—";
  String _rfidTestEpc = "—";

  RfidComm? _rfidTestComm;
  StreamSubscription? _rfidStatusSub;
  StreamSubscription? _rfidTagSub;
  Timer? _rfidTestTimeout;

  bool _testingStation = false;
  bool _connectingStationWifi = false;
  bool get _isDistribuidor => _operacao == 2;

  List<Widget> _fabricacaoFlowModeRadioTiles() {
    return [
      RadioListTile<FabricacaoFlowMode>(
        dense: true,
        contentPadding: EdgeInsets.zero,
        value: FabricacaoFlowMode.fullOnStation,
        groupValue: _flowMode,
        title: const Text("Completo no estacionario"),
        subtitle: const Text(
          "Estacionario finaliza e sincroniza normalmente.",
        ),
        onChanged: (v) => setState(
          () => _flowMode = v ?? FabricacaoFlowMode.fullOnStation,
        ),
      ),
      RadioListTile<FabricacaoFlowMode>(
        dense: true,
        contentPadding: EdgeInsets.zero,
        value: FabricacaoFlowMode.startStationFinishTruck,
        groupValue: _flowMode,
        title: const Text("Inicia no estacionario e finaliza no caminhao"),
        subtitle: const Text(
          "Estacionario exporta parcial; caminhao completa e sincroniza.",
        ),
        onChanged: (v) => setState(
          () => _flowMode = v ?? FabricacaoFlowMode.fullOnStation,
        ),
      ),
    ];
  }

  String? _backupPath;

  @override
  void initState() {
    super.initState();
    _loadFromDb();
    unawaited(_loadBackupInfo());
  }

  Future<void> _loadBackupInfo() async {
    final path = await ConfigDiskBackup.backupPathLabel();
    if (!mounted) return;
    setState(() => _backupPath = path);
  }

  Future<void> _onRestaurarBackupDisco() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Restaurar configuração"),
        content: const Text(
          "Carregar a configuração salva em disco?\n"
          "Os valores atuais desta tela serão substituídos.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Cancelar"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Restaurar"),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final restored = await ConfigDiskBackup.restoreNow(_cfgRepo);
    if (!mounted) return;
    if (!restored) {
      _toast("Nenhum backup encontrado em disco.");
      return;
    }
    await _loadFromDb();
    await _loadBackupInfo();
    _toast("Configuração restaurada do backup em disco.");
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portaCtrl.dispose();
    _ipBalancaCtrl.dispose();
    _portaBalancaCtrl.dispose();
    _ipRfidCtrl.dispose();
    _portaRfidCtrl.dispose();
    _ipEspelhoCtrl.dispose();
    _portaEspelhoCtrl.dispose();
    _hostEstacionarioCtrl.dispose();
    _portaEstacionarioCtrl.dispose();
    _stationWifiSsidCtrl.dispose();
    _stationWifiPasswordCtrl.dispose();
    _stationBaseUrlCtrl.dispose();

    _incrementoBalancaCtrl.dispose();
    _tempoPuloCtrl.dispose();

    _tempoMisturaCtrl.dispose();
    _toleranciaCarregCtrl.dispose();

    _scaleTestTimeout?.cancel();
    _stopScaleTestComm();

    _rfidTestTimeout?.cancel();
    _stopRfidTestComm();

    super.dispose();
  }

  // ============================================================
  // ✅ BACK: primeiro acesso -> login | caso contrário -> menu
  // ============================================================
  Future<void> _handleBack() async {
    if (!mounted) return;

    final hasUser = await _userRepo.hasAnyUser();
    if (!mounted) return;

    if (hasUser) {
      Navigator.of(context).pushNamedAndRemoveUntil("/menu", (_) => false);
    } else {
      Navigator.of(context).pushNamedAndRemoveUntil("/login", (_) => false);
    }
  }

  int _asInt(dynamic v, int def) {
    final n = int.tryParse((v ?? "").toString());
    return n ?? def;
  }

  /// ✅ double seguro para % (aceita vírgula e ponto)
  double _asDouble(dynamic v, double def) {
    final s = (v ?? "").toString().trim();
    if (s.isEmpty) return def;
    return double.tryParse(s.replaceAll(",", ".")) ?? def;
  }

  String _asStr(dynamic v) => (v ?? "").toString();

  String _vagaoId(Map<String, Object?> e) =>
      (e["ID"] ?? e["id"] ?? "").toString();
  String _vagaoNome(Map<String, Object?> e) =>
      (e["NOME"] ?? e["nome"] ?? "").toString();

  int _clampInt(int v, int min, int max) {
    if (v < min) return min;
    if (v > max) return max;
    return v;
  }

  String _fmt3(double v) => v.toStringAsFixed(3);

  Future<void> _loadFromDb() async {
    final cfg = await _cfgRepo.getConfig();
    if (cfg != null) {
      _hostCtrl.text = _asStr(cfg["HOST"]);
      _portaCtrl.text = _asStr(cfg["PORTA"]);

      _backend = _asInt(cfg["BACKEND"], 0);
      _operacao = _asInt(cfg["TIPO_TRABALHO"], 0);

      _modeloBalanca = _asInt(cfg["MODELO_BALANCA"], 0);
      _modeloRfid = _asInt(cfg["MODELO_RFID"], 0);

      _ipBalancaCtrl.text = _asStr(cfg["HOST_BALANCA"]);
      _portaBalancaCtrl.text = _asStr(cfg["PORTA_BALANCA"]);

      _ipRfidCtrl.text = _asStr(cfg["HOST_RFID"]);
      _portaRfidCtrl.text = _asStr(cfg["PORTA_RFID"]);

      _ipEspelhoCtrl.text = _asStr(cfg["IP_ESPELHO"]);
      _portaEspelhoCtrl.text = _asStr(cfg["PORTA_ESPELHO"]);
      _modoSaidaFab = _asInt(cfg["MODO_SAIDA_FAB"], 0) == 1 ? 1 : 0;
      _hostEstacionarioCtrl.text = _asStr(cfg["HOST_ESTACIONARIO"]);
      _portaEstacionarioCtrl.text = _asStr(cfg["PORTA_ESTACIONARIO"]);
      _stationWifiSsidCtrl.text = _asStr(cfg["STATION_WIFI_SSID"]);
      _stationWifiPasswordCtrl.text = _asStr(cfg["STATION_WIFI_PASSWORD"]);
      _stationBaseUrlCtrl.text = _asStr(cfg["STATION_BASE_URL"]);
      _flowMode = fabricacaoFlowModeFromDb(cfg["FLOW_MODE"]);
      _modoHibrido = _asInt(cfg["MODO_HIBRIDO"], 0) == 1;

      _idVagao = _asStr(cfg["ID_VAGAO"]).trim().isEmpty
          ? null
          : _asStr(cfg["ID_VAGAO"]).trim();
      _nomeVagao = _asStr(cfg["NOME_VAGAO"]).trim().isEmpty
          ? null
          : _asStr(cfg["NOME_VAGAO"]).trim();
      _idFazenda = _asStr(cfg["ID_FAZENDA"]).trim().isEmpty
          ? null
          : _asStr(cfg["ID_FAZENDA"]).trim();

      _puloAutomatico = _asInt(cfg["PULO_AUTOMATICO"], 1) == 1;

      final inc = _clampInt(_asInt(cfg["INCREMENTO_PESO"], 1), 1, 10);
      _incrementoBalancaCtrl.text = inc.toString();

      final t = _clampInt(_asInt(cfg["TEMPO_EM_SEGUNDOS_PULO"], 10), 1, 3600);
      _tempoPuloCtrl.text = t.toString();

      // ✅ FABRICAÇÃO (AJUSTADO)
      final tempoMisturaMin = _asInt(cfg["TEMPO_MISTURA"], 0);
      _tempoMisturaCtrl.text = tempoMisturaMin.toString();

      final tolerPct = _asDouble(cfg["TOLERANCIA_CARREGAMENTO"], 0.0);
      _toleranciaCarregCtrl.text = _fmt3(tolerPct);

      if (_stationBaseUrlCtrl.text.trim().isEmpty &&
          _hostEstacionarioCtrl.text.trim().isNotEmpty) {
        final p = int.tryParse(_portaEstacionarioCtrl.text.trim()) ?? 8080;
        _stationBaseUrlCtrl.text = CarregamentoEstacionarioApi.normalizeBaseUrl(
          "http://${_hostEstacionarioCtrl.text.trim()}:$p",
        );
      } else if (_stationBaseUrlCtrl.text.trim().isNotEmpty) {
        _stationBaseUrlCtrl.text = CarregamentoEstacionarioApi.normalizeBaseUrl(
          _stationBaseUrlCtrl.text.trim(),
        );
      }
    } else {
      _puloAutomatico = true;
      _incrementoBalancaCtrl.text = "1";
      _tempoPuloCtrl.text = "10";

      _tempoMisturaCtrl.text = "0";
      _toleranciaCarregCtrl.text = "0.000";
      _portaEspelhoCtrl.text = "9000";
      _portaEstacionarioCtrl.text = "8080";
      _flowMode = FabricacaoFlowMode.fullOnStation;
      _modoHibrido = false;
    }

    if (_portaEspelhoCtrl.text.trim().isEmpty) {
      _portaEspelhoCtrl.text = "9000";
    }

    await _reloadCombos();
    if (mounted) setState(() {});
  }

  Future<void> _reloadCombos() async {
    final vagoesRaw = await _vagaoRepo.listAll();
    final fazRaw = await _fazendaRepo.listAll();

    final vagById = <String, Map<String, Object?>>{};
    for (final v in vagoesRaw) {
      final id = _vagaoId(v);
      if (id.isEmpty) continue;
      vagById[id] = v;
    }

    final fazById = <String, Map<String, Object?>>{};
    for (final f in fazRaw) {
      final id = (f["ID"] ?? "").toString();
      if (id.isEmpty) continue;
      fazById[id] = f;
    }

    _vagoes = vagById.values.toList();
    _fazendas = fazById.values.toList();

    if (_idVagao != null && !vagById.containsKey(_idVagao)) {
      _idVagao = null;
      _nomeVagao = null;
    } else if (_idVagao != null) {
      _nomeVagao = _vagaoNome(vagById[_idVagao] ?? {});
      if (_nomeVagao != null && _nomeVagao!.trim().isEmpty) _nomeVagao = null;
    }

    if (_idFazenda != null && !fazById.containsKey(_idFazenda)) {
      _idFazenda = null;
    }
  }

  Map<String, Object?> _buildCfgMap() {
    final inc = _clampInt(
      int.tryParse(_incrementoBalancaCtrl.text.trim()) ?? 1,
      1,
      10,
    );

    final pulo = _puloAutomatico ? 1 : 0;
    final tempo = _clampInt(
      int.tryParse(_tempoPuloCtrl.text.trim()) ?? 10,
      1,
      3600,
    );

    // ✅ TEMPO_MISTURA agora é MINUTOS
    final tempoMisturaMin = int.tryParse(_tempoMisturaCtrl.text.trim()) ?? 0;

    // ✅ TOLERÂNCIA agora é % (NUMERIC)
    final tolerTxt = _toleranciaCarregCtrl.text.trim();
    final tolerPct = double.tryParse(tolerTxt.replaceAll(",", ".")) ?? 0.0;

    var stationBaseUrl = _stationBaseUrlCtrl.text.trim();
    String hostEst = _hostEstacionarioCtrl.text.trim();
    int portaEst = int.tryParse(_portaEstacionarioCtrl.text.trim()) ?? 8080;
    if (_isDistribuidor) {
      final uri = Uri.tryParse(
        stationBaseUrl.contains("://")
            ? stationBaseUrl
            : "http://$stationBaseUrl",
      );
      if (uri != null && uri.host.trim().isNotEmpty) {
        hostEst = uri.host.trim();
        portaEst = uri.hasPort
            ? uri.port
            : (uri.scheme.toLowerCase() == "https" ? 443 : 8080);
        if (portaEst == 80 || (portaEst < 1024 && uri.scheme.toLowerCase() == "http")) {
          portaEst = 8080;
        }
        stationBaseUrl = CarregamentoEstacionarioApi.normalizeBaseUrl(
          uri.hasPort ? stationBaseUrl : "http://$hostEst",
        );
      }
    }

    return {
      "HOST": _hostCtrl.text.trim(),
      "PORTA": int.tryParse(_portaCtrl.text.trim()) ?? 0,
      "BACKEND": _backend,
      "TIPO_TRABALHO": _operacao,
      "MODELO_BALANCA": _modeloBalanca,
      "HOST_BALANCA": _ipBalancaCtrl.text.trim(),
      "PORTA_BALANCA": int.tryParse(_portaBalancaCtrl.text.trim()) ?? 0,
      "MODELO_RFID": _modeloRfid,
      "HOST_RFID": _ipRfidCtrl.text.trim(),
      "PORTA_RFID": int.tryParse(_portaRfidCtrl.text.trim()) ?? 0,
      "ID_VAGAO": _idVagao ?? "",
      "NOME_VAGAO": _nomeVagao ?? "",
      "ID_FAZENDA": _idFazenda ?? "",
      "MODO_SAIDA_FAB": _modoSaidaFab,
      "IP_ESPELHO": _ipEspelhoCtrl.text.trim(),
      "PORTA_ESPELHO": int.tryParse(_portaEspelhoCtrl.text.trim()) ?? 9000,
      "HOST_ESTACIONARIO": hostEst,
      "PORTA_ESTACIONARIO": portaEst,
      "FLOW_MODE": fabricacaoFlowModeToDb(_flowMode),
      "STATION_WIFI_SSID": _stationWifiSsidCtrl.text.trim(),
      "STATION_WIFI_PASSWORD": _stationWifiPasswordCtrl.text,
      "STATION_BASE_URL": stationBaseUrl,
      "PULO_AUTOMATICO": pulo,
      "TEMPO_EM_SEGUNDOS_PULO": tempo,
      "INCREMENTO_PESO": inc,

      // ✅ FABRICAÇÃO (AJUSTADO)
      "TEMPO_MISTURA": tempoMisturaMin, // minutos
      "TOLERANCIA_CARREGAMENTO": tolerPct, // %
      "MODO_HIBRIDO": _modoHibrido ? 1 : 0,
    };
  }

  bool _validateBase() {
    final host = _hostCtrl.text.trim();
    final porta = int.tryParse(_portaCtrl.text.trim());
    if (host.isEmpty) {
      _toast("Informe o IP do servidor de dados.");
      return false;
    }
    if (porta == null || porta <= 0) {
      _toast("Informe a porta do servidor de dados.");
      return false;
    }

    final inc = int.tryParse(_incrementoBalancaCtrl.text.trim()) ?? 1;
    if (inc < 1 || inc > 10) {
      _toast("Incremento Balança deve ser entre 1 e 10.");
      return false;
    }

    if (_puloAutomatico) {
      final t = int.tryParse(_tempoPuloCtrl.text.trim()) ?? 0;
      if (t < 1) {
        _toast("Tempo do pulo deve ser maior que 0.");
        return false;
      }
    }

    // ✅ TEMPO_MISTURA (minutos) >= 0
    final tmMin = int.tryParse(_tempoMisturaCtrl.text.trim()) ?? -1;
    if (tmMin < 0) {
      _toast("Tempo de mistura (minutos) deve ser 0 ou maior.");
      return false;
    }

    // ✅ TOLERÂNCIA (%) >= 0
    final tolPct = double.tryParse(
            _toleranciaCarregCtrl.text.trim().replaceAll(",", ".")) ??
        -1;
    if (tolPct < 0) {
      _toast("Tolerância (%) deve ser 0 ou maior.");
      return false;
    }

    if (_isDistribuidor) {
      final base = _stationBaseUrlCtrl.text.trim();
      final ssid = _stationWifiSsidCtrl.text.trim();
      if (base.isEmpty) {
        _toast("Informe o baseUrl do estacionario.");
        return false;
      }
      if (CarregamentoEstacionarioApi.tryParseHostPort(base) == null) {
        _toast(
            "Base URL invalida. Ex.: http://IP_DO_TABLET:8080 (porta do bridge).");
        return false;
      }
      if (ssid.isEmpty) {
        _toast("Informe o SSID da rede do estacionario.");
        return false;
      }
    }

    final outIp = _ipEspelhoCtrl.text.trim();
    final outPort = int.tryParse(_portaEspelhoCtrl.text.trim()) ?? 0;
    if (outIp.isEmpty) {
      _toast("Informe o IP da saída (${_modoSaidaFab == 1 ? "LED" : "pá"}).");
      return false;
    }
    if (outPort <= 0) {
      _toast(
          "Informe a porta da saída (${_modoSaidaFab == 1 ? "LED" : "pá"}).");
      return false;
    }

    return true;
  }

  // ============================
  // ✅ TESTE BALANÇA
  // ============================
  ScaleModel _mapModeloBalanca(int v) {
    switch (v) {
      case 0:
        return ScaleModel.topcom;
      case 1:
        return ScaleModel.dg500;
      case 2:
        return ScaleModel.alfa;
      default:
        return ScaleModel.raw;
    }
  }

  Future<void> _stopScaleTestComm() async {
    _scaleTestTimeout?.cancel();
    _scaleTestTimeout = null;

    try {
      await _scaleStatusSub?.cancel();
    } catch (_) {}
    _scaleStatusSub = null;

    try {
      await _scaleWeightSub?.cancel();
    } catch (_) {}
    _scaleWeightSub = null;

    try {
      await _scaleTestComm?.dispose();
    } catch (_) {}
    _scaleTestComm = null;
  }

  Future<void> _onTestBalanca() async {
    final ip = _ipBalancaCtrl.text.trim();
    final port = int.tryParse(_portaBalancaCtrl.text.trim()) ?? 0;

    if (ip.isEmpty) {
      _toast("Informe o IP da balança.");
      return;
    }
    if (port <= 0) {
      _toast("Informe a porta da balança.");
      return;
    }

    setState(() {
      _testingScale = true;
      _scaleTestStatus = "Conectando…";
      _scaleTestRaw = "—";
      _scaleTestParsed = "—";
    });

    await _stopScaleTestComm();

    final comm = ScaleComm(
      host: ip,
      port: port,
      model: _mapModeloBalanca(_modeloBalanca),
      allowNegative: true,
      autoReconnect: false,
      connectTimeout: const Duration(seconds: 3),
    );

    _scaleTestComm = comm;

    _scaleStatusSub = comm.statusStream.listen((ev) {
      if (!mounted) return;
      setState(() {
        switch (ev.status) {
          case ScaleStatus.connecting:
            _scaleTestStatus = "Conectando…";
            break;
          case ScaleStatus.connected:
            _scaleTestStatus = "Conectado. Aguardando dados…";
            break;
          case ScaleStatus.error:
            _scaleTestStatus = "Erro: ${ev.message ?? "desconhecido"}";
            _testingScale = false;
            break;
          case ScaleStatus.disconnected:
            if (_testingScale) _scaleTestStatus = "Desconectado.";
            break;
        }
      });
    });

    bool gotFirst = false;

    _scaleWeightSub = comm.weightStream.listen((w) async {
      if (!mounted) return;
      gotFirst = true;

      setState(() {
        _scaleTestStatus = "OK ✅ Recebendo dados";
        _scaleTestRaw = w.rawLine;
        _scaleTestParsed = "Peso: ${w.weight.toStringAsFixed(2)}";
        _testingScale = false;
      });

      await _stopScaleTestComm();
    });

    _scaleTestTimeout = Timer(const Duration(seconds: 5), () async {
      if (!mounted) return;
      if (gotFirst) return;

      setState(() {
        _scaleTestStatus =
            "Sem dados (timeout). Verifique cabo/USR-W610/modelo.";
        _testingScale = false;
      });

      await _stopScaleTestComm();
    });

    await comm.connect();
  }

  // ============================
  // ✅ TESTE RFID
  // ============================
  Future<void> _stopRfidTestComm() async {
    _rfidTestTimeout?.cancel();
    _rfidTestTimeout = null;

    try {
      await _rfidStatusSub?.cancel();
    } catch (_) {}
    _rfidStatusSub = null;

    try {
      await _rfidTagSub?.cancel();
    } catch (_) {}
    _rfidTagSub = null;

    try {
      await _rfidTestComm?.dispose();
    } catch (_) {}
    _rfidTestComm = null;
  }

  Future<void> _onTestRfid() async {
    final ip = _ipRfidCtrl.text.trim();
    final port = int.tryParse(_portaRfidCtrl.text.trim()) ?? 0;

    if (ip.isEmpty) {
      _toast("Informe o IP do RFID.");
      return;
    }
    if (port <= 0) {
      _toast("Informe a porta do RFID.");
      return;
    }

    setState(() {
      _testingRfid = true;
      _rfidTestStatus = "Conectando…";
      _rfidTestRaw = "—";
      _rfidTestEpc = "—";
    });

    await _stopRfidTestComm();

    final comm = RfidComm(
      host: ip,
      port: port,
      autoReconnect: false,
      connectTimeout: const Duration(seconds: 3),
      debounceMs: 700,
    );

    _rfidTestComm = comm;

    _rfidStatusSub = comm.statusStream.listen((ev) {
      if (!mounted) return;
      setState(() {
        switch (ev.status) {
          case RfidStatus.connecting:
            _rfidTestStatus = "Conectando…";
            break;
          case RfidStatus.connected:
            _rfidTestStatus = "Conectado. Aproxime a tag…";
            break;
          case RfidStatus.error:
            _rfidTestStatus = "Erro: ${ev.message ?? "desconhecido"}";
            _testingRfid = false;
            break;
          case RfidStatus.disconnected:
            if (_testingRfid) _rfidTestStatus = "Desconectado.";
            break;
        }
      });
    });

    bool gotFirst = false;
    comm.setLeituraAtiva(true);

    _rfidTagSub = comm.tagStream.listen((t) async {
      if (!mounted) return;
      gotFirst = true;

      setState(() {
        _rfidTestStatus = "OK ✅ Tag lida";
        _rfidTestRaw = t.rawLine;
        _rfidTestEpc = t.epc;
        _testingRfid = false;
      });

      await _stopRfidTestComm();
    });

    _rfidTestTimeout = Timer(const Duration(seconds: 6), () async {
      if (!mounted) return;
      if (gotFirst) return;

      setState(() {
        _rfidTestStatus =
            "Sem leitura (timeout). Verifique antena/conversor/rede.";
        _testingRfid = false;
      });

      await _stopRfidTestComm();
    });

    await comm.connect();
  }

  Future<void> _onBaixarVagao() async {
    if (!_validateBase()) return;

    setState(() => _loadingVagao = true);
    try {
      final cfg = _buildCfgMap();
      await _cfgRepo.saveConfig(cfg);
      await _bootstrap.baixarVagao(cfg);

      await _reloadCombos();
      if (mounted) setState(() {});
      _toast("Vagões baixados com sucesso.");
    } catch (e) {
      _toast("Erro ao baixar vagão: $e");
    } finally {
      if (mounted) setState(() => _loadingVagao = false);
    }
  }

  CarregamentoEstacionarioApi? _stationApiFromBaseUrl() {
    return CarregamentoEstacionarioApi.tryFromBaseUrl(
      _stationBaseUrlCtrl.text.trim(),
    );
  }

  Future<void> _onTestarEstacionario() async {
    final api = _stationApiFromBaseUrl();
    if (api == null) {
      _toast("BaseUrl do estacionario invalido. Ex.: http://IP:8080");
      return;
    }
    setState(() => _testingStation = true);
    try {
      final r = await api.tryHealth();
      _toast(r.ok ? r.message : "Falha: ${r.message}");
    } catch (e) {
      _toast("Erro no teste: $e");
    } finally {
      if (mounted) setState(() => _testingStation = false);
    }
  }

  Future<void> _onConectarWifiEstacionario() async {
    final ssid = _stationWifiSsidCtrl.text.trim();
    if (ssid.isEmpty) {
      _toast("Informe o SSID da rede do estacionario.");
      return;
    }
    setState(() => _connectingStationWifi = true);
    try {
      await WifiGuard.openWifiSelector();
      _toast("Selecione a rede '$ssid' na lista de Wi‑Fi.");
    } finally {
      if (mounted) setState(() => _connectingStationWifi = false);
    }
  }

  Future<void> _onBaixarFazendas() async {
    if (!_validateBase()) return;

    setState(() => _loadingFazendas = true);
    try {
      final cfg = _buildCfgMap();
      await _cfgRepo.saveConfig(cfg);
      await _bootstrap.baixarFazendas(cfg);

      await _reloadCombos();
      if (mounted) setState(() {});
      _toast("Fazendas baixadas com sucesso.");
    } catch (e) {
      _toast("Erro ao baixar fazendas: $e");
    } finally {
      if (mounted) setState(() => _loadingFazendas = false);
    }
  }

  Future<void> _onConfirmar() async {
    if (!_validateBase()) return;

    if (_idVagao == null || _idVagao!.isEmpty) {
      _toast("Selecione o Vagão (ou baixe primeiro).");
      return;
    }
    if (_idFazenda == null || _idFazenda!.isEmpty) {
      _toast("Selecione a Fazenda (ou baixe primeiro).");
      return;
    }

    setState(() => _saving = true);
    try {
      final cfg = _buildCfgMap();
      await _cfgRepo.saveConfig(cfg);

      final hasUser = await _userRepo.hasAnyUser();
      if (!mounted) return;

      if (!hasUser) {
        await _bootstrap.baixarUsuarios(cfg, _idFazenda!);
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil("/login", (_) => false);
      } else {
        Navigator.of(context).pushNamedAndRemoveUntil("/menu", (_) => false);
      }
    } catch (e) {
      _toast("Erro ao confirmar: $e");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _sectionTitle(String t) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            t,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(
                k,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(child: Text(v)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final busy = _loadingVagao || _loadingFazendas || _saving;

    final validVagaoValue =
        (_idVagao != null && _vagoes.any((e) => _vagaoId(e) == _idVagao))
            ? _idVagao
            : null;

    final validFazendaValue = (_idFazenda != null &&
            _fazendas.any((e) => (e["ID"] ?? "").toString() == _idFazenda))
        ? _idFazenda
        : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: SafeArea(
            top: true,
            bottom: false,
            child: AppBar(
              title: const Text("Configuração"),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _handleBack,
              ),
            ),
          ),
        ),
        body: AbsorbPointer(
          absorbing: busy,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _sectionTitle("Servidor de Dados"),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _hostCtrl,
                        decoration: const InputDecoration(
                          labelText: "IP Servidor Dados",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 160,
                      child: TextField(
                        controller: _portaCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Porta",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                _sectionTitle("Back-end / Operação"),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        // ✅ key única (evita Duplicate keys)
                        key: ValueKey("backend:$_backend"),
                        initialValue: _backend,
                        items: ConfigOptions.backends.entries
                            .map((e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _backend = v ?? 0),
                        decoration: const InputDecoration(
                          labelText: "Back-end",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        // ✅ key única (evita Duplicate keys)
                        key: ValueKey("operacao:$_operacao"),
                        initialValue: _operacao,
                        items: ConfigOptions.operacoes.entries
                            .map((e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _operacao = v ?? 0),
                        decoration: const InputDecoration(
                          labelText: "Operação",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Card(
                  clipBehavior: Clip.antiAlias,
                  child: SwitchListTile(
                    title: const Text("Modo híbrido"),
                    subtitle: const Text(
                      "No estacionário, habilita o tile Carregamento no menu. "
                      "No distribuidor, habilita o botão Nova na lista de fabricações.",
                    ),
                    value: _modoHibrido,
                    onChanged: (v) => setState(() => _modoHibrido = v),
                  ),
                ),
                const SizedBox(height: 16),

                if (_operacao == 1) ...[
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            "Fluxo de fabricação",
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Use a mesma opção no tablet do caminhão. "
                            "A opção parcial habilita finalizar no estacionário e completar no caminhão.",
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          ..._fabricacaoFlowModeRadioTiles(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                _sectionTitle("Identificação Vagão"),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 430;
                    final field = DropdownButtonFormField<String>(
                      key: ValueKey("vagao:$validVagaoValue"),
                      isExpanded: true,
                      initialValue: _vagoes.isEmpty ? null : validVagaoValue,
                      items: _vagoes
                          .map((e) {
                            final id = _vagaoId(e);
                            final nome = _vagaoNome(e);
                            return DropdownMenuItem<String>(
                              value: id,
                              child: Text(
                                nome,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            );
                          })
                          .where((it) => (it.value ?? "").isNotEmpty)
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _idVagao = v;
                          final row = _vagoes.firstWhere(
                            (x) => _vagaoId(x) == (v ?? ""),
                            orElse: () => {},
                          );
                          _nomeVagao = _vagaoNome(row);
                          if (_nomeVagao != null &&
                              _nomeVagao!.trim().isEmpty) {
                            _nomeVagao = null;
                          }
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: "Vagão",
                        border: OutlineInputBorder(),
                      ),
                    );

                    final button = SizedBox(
                      height: 56,
                      width: compact ? double.infinity : null,
                      child: ElevatedButton.icon(
                        onPressed: _onBaixarVagao,
                        icon: _loadingVagao
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.download),
                        label: const Text("Baixa Vagão"),
                      ),
                    );

                    if (compact) {
                      return Column(
                        children: [
                          field,
                          const SizedBox(height: 12),
                          button,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: field),
                        const SizedBox(width: 12),
                        button,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                _sectionTitle("Fazenda"),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 430;
                    final field = DropdownButtonFormField<String>(
                      key: ValueKey("fazenda:$validFazendaValue"),
                      isExpanded: true,
                      initialValue:
                          _fazendas.isEmpty ? null : validFazendaValue,
                      items: _fazendas
                          .map(
                            (e) => DropdownMenuItem(
                              value: (e["ID"] ?? "").toString(),
                              child: Text(
                                (e["NOME"] ?? "").toString(),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _idFazenda = v),
                      decoration: const InputDecoration(
                        labelText: "Fazenda",
                        border: OutlineInputBorder(),
                      ),
                    );

                    final button = SizedBox(
                      height: 56,
                      width: compact ? double.infinity : null,
                      child: ElevatedButton.icon(
                        onPressed: _onBaixarFazendas,
                        icon: _loadingFazendas
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.download),
                        label: const Text("Baixa Fazendas"),
                      ),
                    );

                    if (compact) {
                      return Column(
                        children: [
                          field,
                          const SizedBox(height: 12),
                          button,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: field),
                        const SizedBox(width: 12),
                        button,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                // ========= BALANÇA =========
                _sectionTitle("Balança"),
                DropdownButtonFormField<int>(
                  key: ValueKey("modeloBalanca:$_modeloBalanca"),
                  initialValue: _modeloBalanca,
                  items: ConfigOptions.modelosBalanca.entries
                      .map((e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => _modeloBalanca = v ?? 0),
                  decoration: const InputDecoration(
                    labelText: "Modelo Balança",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _incrementoBalancaCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Incremento Balança (1 a 10)",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  value: _puloAutomatico,
                  onChanged: (v) => setState(() => _puloAutomatico = v),
                  title: const Text("Pulo automático"),
                  subtitle: const Text(
                    "Se ativo, o app inicia a contagem do pulo ao atingir a tolerância.",
                  ),
                ),
                if (_puloAutomatico) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tempoPuloCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Tempo do pulo (segundos)",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ipBalancaCtrl,
                        decoration: const InputDecoration(
                          labelText: "IP Balança",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 160,
                      child: TextField(
                        controller: _portaBalancaCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Porta Balança",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _testingScale ? null : _onTestBalanca,
                    icon: _testingScale
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering),
                    label: const Text("Testar Balança"),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Resultado do teste",
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      _kv("Status", _scaleTestStatus),
                      _kv("String", _scaleTestRaw),
                      _kv("Tratado", _scaleTestParsed),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ========= RFID =========
                _sectionTitle("RFID"),
                DropdownButtonFormField<int>(
                  key: ValueKey("modeloRfid:$_modeloRfid"),
                  initialValue: _modeloRfid,
                  items: ConfigOptions.modelosRfid.entries
                      .map((e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => _modeloRfid = v ?? 0),
                  decoration: const InputDecoration(
                    labelText: "Modelo RFID",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ipRfidCtrl,
                        decoration: const InputDecoration(
                          labelText: "IP RFID",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 160,
                      child: TextField(
                        controller: _portaRfidCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Porta RFID",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _testingRfid ? null : _onTestRfid,
                    icon: _testingRfid
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.nfc),
                    label: const Text("Testar RFID"),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Resultado do teste RFID",
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      _kv("Status", _rfidTestStatus),
                      _kv("String", _rfidTestRaw),
                      _kv("EPC", _rfidTestEpc),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ✅ FABRICAÇÃO (AJUSTADO)
                _sectionTitle("Fabricação"),
                TextField(
                  controller: _tempoMisturaCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Tempo de mistura (minutos)",
                    helperText: "0 = não aplica (sem timer de mistura).",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _toleranciaCarregCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: "Tolerância da fabricação (%)",
                    helperText: "Ex: 2,5 = 2.5% (aceita vírgula).",
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 16),

                _sectionTitle("Saída da fabricação"),
                RadioListTile<int>(
                  dense: true,
                  value: 0,
                  groupValue: _modoSaidaFab,
                  title: const Text("Espelhamento da pá"),
                  onChanged: (v) => setState(() => _modoSaidaFab = v ?? 0),
                ),
                RadioListTile<int>(
                  dense: true,
                  value: 1,
                  groupValue: _modoSaidaFab,
                  title: const Text("LED de rede"),
                  onChanged: (v) => setState(() => _modoSaidaFab = v ?? 1),
                ),
                TextField(
                  controller: _ipEspelhoCtrl,
                  decoration: InputDecoration(
                    labelText: _modoSaidaFab == 1 ? "IP do LED" : "IP da pá",
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _portaEspelhoCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: _modoSaidaFab == 1
                        ? "Porta do LED"
                        : "Porta do espelhamento",
                    helperText: "Padrão: 9000",
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 22),

                if (_isDistribuidor) ...[
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            "Estacionário (rede)",
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Rede e URL do tablet no misturador.",
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _stationWifiSsidCtrl,
                            decoration: const InputDecoration(
                              labelText: "SSID do estacionario",
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _stationWifiPasswordCtrl,
                            decoration: const InputDecoration(
                              labelText: "Senha do Wi-Fi do estacionario",
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _stationBaseUrlCtrl,
                            decoration: const InputDecoration(
                              labelText: "Base URL do estacionario",
                              helperText:
                                  "Ex.: http://192.168.1.10:8080",
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _connectingStationWifi
                                    ? null
                                    : _onConectarWifiEstacionario,
                                icon: _connectingStationWifi
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.wifi),
                                label: const Text(
                                    "Conectar na rede do Estacionario"),
                              ),
                              OutlinedButton.icon(
                                onPressed: _testingStation
                                    ? null
                                    : _onTestarEstacionario,
                                icon: _testingStation
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(
                                        Icons.health_and_safety_outlined),
                                label: const Text("Testar conexao"),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                ],

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Backup em disco",
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "Ao confirmar, a configuração é salva em Downloads/RFeed. "
                        "Se reinstalar o app, ela pode ser restaurada automaticamente.",
                        style: TextStyle(fontSize: 13),
                      ),
                      if ((_backupPath ?? "").trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          _backupPath!,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _onRestaurarBackupDisco,
                        icon: const Icon(Icons.restore),
                        label: const Text("Restaurar do disco"),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _onConfirmar,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: const Text("Confirmar"),
                  ),
                ),

                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _handleBack,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text("Voltar"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
