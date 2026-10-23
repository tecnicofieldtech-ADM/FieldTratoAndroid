import "dart:async";

/// Estado compartilhado do simulador local (tablet sem hardware).
class ScaleSimBus {
  ScaleSimBus._();
  static final ScaleSimBus instance = ScaleSimBus._();

  bool _enabled = false;
  bool get enabled => _enabled;

  double _kg = 0;
  double get weightKg => _kg;

  double? _rampTarget;
  double rampKgPerSec = 90;

  Timer? _tick;
  final List<void Function()> _listeners = [];

  void addListener(void Function() fn) => _listeners.add(fn);
  void removeListener(void Function() fn) => _listeners.remove(fn);

  void notifyListeners() {
    for (final fn in List<void Function()>.from(_listeners)) {
      fn();
    }
  }

  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (value) {
      _ensureTick();
    } else {
      _rampTarget = null;
      _tick?.cancel();
      _tick = null;
    }
    notifyListeners();
  }

  void setWeight(double kg) {
    _rampTarget = null;
    _kg = kg;
    notifyListeners();
  }

  void addWeight(double delta) {
    setWeight(_kg + delta);
  }

  void rampTo(double targetKg) {
    _rampTarget = targetKg;
    _ensureTick();
    notifyListeners();
  }

  void zero() => setWeight(0);

  void _ensureTick() {
    if (_tick != null) return;
    _tick = Timer.periodic(const Duration(milliseconds: 80), (_) => _onTick());
  }

  void _onTick() {
    final target = _rampTarget;
    if (target == null) return;
    final step = rampKgPerSec * 0.08;
    final diff = target - _kg;
    if (diff.abs() <= step) {
      _kg = target;
      _rampTarget = null;
    } else {
      _kg += diff > 0 ? step : -step;
    }
    notifyListeners();
  }
}
