import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, HttpHeaders, HttpClient;

import 'package:appsflyer_sdk/appsflyer_sdk.dart' as af_core;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, SystemChrome, SystemUiOverlayStyle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as r;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:honsphere/pushLoad.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:provider/provider.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz_zone;

import 'lder.dart';

// ============================================================================
// Константы (пиратские флаги)
// ============================================================================
const String kChestKeyLoadedOnce = "loaded_event_sent_once";
const String kShipStatEndpoint = "https://conf.utigrand.cfd/stat";
const String kChestKeyCachedParrot = "cached_fcm_token";

// ============================================================================
// RumBarrel -- лёгкая "бочка рома" (сервисы/синглтоны)
// ============================================================================
class RumBarrel {
  static final RumBarrel _barrel = RumBarrel._();
  RumBarrel._();

  factory RumBarrel() => _barrel;

  final FlutterSecureStorage chest = const FlutterSecureStorage();
  final ShipLog log = ShipLog();
  final Connectivity crowNest = Connectivity();
}

class ShipLog {
  final Logger _lg = Logger();
  void i(Object msg) => _lg.i(msg);
  void w(Object msg) => _lg.w(msg);
  void e(Object msg) => _lg.e(msg);
}

// ============================================================================
// Сеть/данные: SeaWire
// ============================================================================
class SeaWire {
  final RumBarrel _rum = RumBarrel();

  Future<bool> isSeaCalm() async {
    final c = await _rum.crowNest.checkConnectivity();
    return c != ConnectivityResult.none;
  }

  Future<void> castBottleJson(String url, Map<String, dynamic> cargo) async {
    try {
      await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(cargo),
      );
    } catch (e) {
      _rum.log.e("castBottleJson error: $e");
    }
  }
}

// ============================================================================
// Досье корабля/устройства -- Quartermaster (квартирмейстер)
// ============================================================================
class Quartermaster {
  String? shipId;
  String? voyageId = "mafia-one-off";
  String? deck; // platform
  String? deckBuild; // os
  String? appRum; // app version
  String? sailorTongue; // lang
  String? seaZone; // timezone
  bool cannonReady = true; // push

  Future<void> muster() async {
    final spy = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await spy.androidInfo;
      shipId = a.id;
      deck = "android";
      deckBuild = a.version.release;
    } else if (Platform.isIOS) {
      final i = await spy.iosInfo;
      shipId = i.identifierForVendor;
      deck = "ios";
      deckBuild = i.systemVersion;
    }
    final info = await PackageInfo.fromPlatform();
    appRum = info.version;
    sailorTongue = Platform.localeName.split('_')[0];
    seaZone = tz_zone.local.name;
    voyageId = "voyage-${DateTime.now().millisecondsSinceEpoch}";
  }

  Map<String, dynamic> asMap({String? parrot}) => {
    "fcm_token": parrot ?? 'missing_token',
    "device_id": shipId ?? 'missing_id',
    "app_name": "honspehre",
    "instance_id": voyageId ?? 'missing_session',
    "platform": deck ?? 'missing_system',
    "os_version": deckBuild ?? 'missing_build',
    "app_version": appRum ?? 'missing_app',
    "language": sailorTongue ?? 'en',
    "timezone": seaZone ?? 'UTC',
    "push_enabled": cannonReady,
  };
}

// ============================================================================
// AppsFlyer -- ConsigliereCaptain
// ============================================================================
class ConsigliereCaptain with ChangeNotifier {
  af_core.AppsFlyerOptions? _chart;
  af_core.AppsflyerSdk? _spyglass;

  String afShipId = "";
  String afTreasure = "";

  void hoist(VoidCallback nudge) {
    final cfg = af_core.AppsFlyerOptions(
      afDevKey: "qsBLmy7dAXDQhowM8V3ca4",
      appId: "6752573451",
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );
    _chart = cfg;
    _spyglass = af_core.AppsflyerSdk(cfg);

    _spyglass?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );
    _spyglass?.startSDK(
      onSuccess: () => RumBarrel().log.i("Consigliere hoisted"),
      onError: (int c, String m) => RumBarrel().log.e("Consigliere storm $c: $m"),
    );
    _spyglass?.onInstallConversionData((loot) {
      afTreasure = loot.toString();
      nudge();
      notifyListeners();
    });
    _spyglass?.getAppsFlyerUID().then((v) {
      afShipId = v.toString();
      nudge();
      notifyListeners();
    });
  }
}

// ============================================================================
// Riverpod/Provider
// ============================================================================
final quartermasterProvider = r.FutureProvider<Quartermaster>((ref) async {
  final qm = Quartermaster();
  await qm.muster();
  return qm;
});

final consigliereProvider = p.ChangeNotifierProvider<ConsigliereCaptain>(
  create: (_) => ConsigliereCaptain(),
);

// ============================================================================
// Parrot (FCM) -- фоновые крики
// ============================================================================
@pragma('vm:entry-point')
Future<void> parrotBgSquawk(RemoteMessage msg) async {
  RumBarrel().log.i("bg-parrot: ${msg.messageId}");
  RumBarrel().log.i("bg-cargo: ${msg.data}");
}

// ============================================================================
// ParrotBridge -- токен получаем только из нативного канала
// ============================================================================
class ParrotBridge extends ChangeNotifier {
  final RumBarrel _rum = RumBarrel();
  String? _feather;
  final List<void Function(String)> _waitDeck = [];

  String? get token => _feather;

  ParrotBridge() {
    const MethodChannel('com.example.fcm/token').setMethodCallHandler((call) async {
      if (call.method == 'setToken') {
        final String s = call.arguments as String;
        if (s.isNotEmpty) {
          _perchSet(s);
        }
      }
    });
    _restoreFeather();
  }

  Future<void> _restoreFeather() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final cached = sp.getString(kChestKeyCachedParrot);
      if (cached != null && cached.isNotEmpty) {
        _perchSet(cached, notifyNative: false);
      } else {
        final ss = await _rum.chest.read(key: kChestKeyCachedParrot);
        if (ss != null && ss.isNotEmpty) {
          _perchSet(ss, notifyNative: false);
        }
      }
    } catch (_) {}
  }

  void _perchSet(String t, {bool notifyNative = true}) async {
    _feather = t;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(kChestKeyCachedParrot, t);
      await _rum.chest.write(key: kChestKeyCachedParrot, value: t);
    } catch (_) {}
    for (final cb in List.of(_waitDeck)) {
      try {
        cb(t);
      } catch (e) {
        _rum.log.w("parrot-waiter error: $e");
      }
    }
    _waitDeck.clear();
    notifyListeners();
  }

  Future<void> awaitFeather(Function(String t) onToken) async {
    try {
      await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      if (_feather != null && _feather!.isNotEmpty) {
        onToken(_feather!);
        return;
      }
      _waitDeck.add(onToken);
    } catch (e) {
      _rum.log.e("ParrotBridge awaitFeather: $e");
    }
  }
}

// ============================================================================
// Вестибюль -- Splash
// ============================================================================
class JollyVestibule extends StatefulWidget {
  const JollyVestibule({Key? key}) : super(key: key);

  @override
  State<JollyVestibule> createState() => _JollyVestibuleState();
}

class _JollyVestibuleState extends State<JollyVestibule> {
  final ParrotBridge _parrot = ParrotBridge();
  bool _once = false;
  Timer? _fallbackFuse;
  bool _coverMute = false;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    _parrot.awaitFeather((sig) => _sail(sig));
    _fallbackFuse = Timer(const Duration(seconds: 8), () => _sail(''));

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _coverMute = true);
    });
  }

  void _sail(String sig) {
    if (_once) return;
    _once = true;
    _fallbackFuse?.cancel();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => CaptainHarbor(signal: sig)),
    );
  }

  @override
  void dispose() {
    _fallbackFuse?.cancel();
    _parrot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: const [
          Center(child: NeonDialLoader()),
        ],
      ),
    );
  }
}

// ============================================================================
// MVVM (BosunViewModel + HarborCourier)
// ============================================================================
class BosunViewModel with ChangeNotifier {
  final Quartermaster qm;
  final ConsigliereCaptain capo;

  BosunViewModel({required this.qm, required this.capo});

  Map<String, dynamic> cargoDevice(String? token) => qm.asMap(parrot: token);

  Map<String, dynamic> cargoAF(String? token) => {
    "content": {
      "af_data": capo.afTreasure,
      "af_id": capo.afShipId,
      "fb_app_name": "honspehre",
      "app_name": "honspehre",
      "deep": null,
      "bundle_identifier": "com.piratekok.piratelair",
      "app_version": "1.0.0",
      "apple_id": "6752573451",
      "fcm_token": token ?? "no_token",
      "device_id": qm.shipId ?? "no_device",
      "instance_id": qm.voyageId ?? "no_instance",
      "platform": qm.deck ?? "no_type",
      "os_version": qm.deckBuild ?? "no_os",
      "app_version": qm.appRum ?? "no_app",
      "language": qm.sailorTongue ?? "en",
      "timezone": qm.seaZone ?? "UTC",
      "push_enabled": qm.cannonReady,
      "useruid": capo.afShipId,
    },
  };
}

class HarborCourier {
  final BosunViewModel model;
  final InAppWebViewController Function() getWeb;

  HarborCourier({required this.model, required this.getWeb});

  Future<void> stashDeviceInLocalStorage(String? token) async {
    final m = model.cargoDevice(token);
    await getWeb().evaluateJavascript(source: '''
localStorage.setItem('app_data', JSON.stringify(${jsonEncode(m)}));
''');
  }

  Future<void> sendRawToDeck(String? token) async {
    final payload = model.cargoAF(token);
    final jsonString = jsonEncode(payload);
    RumBarrel().log.i("SendRawData: $jsonString");
    await getWeb().evaluateJavascript(source: "sendRawData(${jsonEncode(jsonString)});");
  }
}

// ============================================================================
// Переходы/статистика
// ============================================================================
Future<String> chartFinalUrl(String startUrl, {int maxHops = 10}) async {
  final client = HttpClient();

  try {
    var current = Uri.parse(startUrl);
    for (int i = 0; i < maxHops; i++) {
      final req = await client.getUrl(current);
      req.followRedirects = false;
      final res = await req.close();
      if (res.isRedirect) {
        final loc = res.headers.value(HttpHeaders.locationHeader);
        if (loc == null || loc.isEmpty) break;
        final next = Uri.parse(loc);
        current = next.hasScheme ? next : current.resolveUri(next);
        continue;
      }
      return current.toString();
    }
    return current.toString();
  } catch (e) {
    debugPrint("chartFinalUrl error: $e");
    return startUrl;
  } finally {
    client.close(force: true);
  }
}

Future<void> postHarborStat({
  required String event,
  required int timeStart,
  required String url,
  required int timeFinish,
  required String appSid,
  int? firstPageLoadTs,
}) async {
  try {
    final finalUrl = await chartFinalUrl(url);
    final payload = {
      "event": event,
      "timestart": timeStart,
      "timefinsh": timeFinish,
      "url": finalUrl,
      "appleID": "6752573451",
      "open_count": "$appSid/$timeStart",
    };

    print("loadingstatinsic $payload");
    final res = await http.post(
      Uri.parse("$kShipStatEndpoint/$appSid"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(payload),
    );
    print(" ur _loaded$kShipStatEndpoint/$appSid");
    debugPrint("_postStat status=${res.statusCode} body=${res.body}");
  } catch (e) {
    debugPrint("_postStat error: $e");
  }
}

// ============================================================================
// Главный WebView -- CaptainHarbor
// ============================================================================
class CaptainHarbor extends StatefulWidget {
  final String? signal;
  const CaptainHarbor({super.key, required this.signal});

  @override
  State<CaptainHarbor> createState() => _CaptainHarborState();
}

class _CaptainHarborState extends State<CaptainHarbor> with WidgetsBindingObserver {
  late InAppWebViewController _pier;
  bool _spinWheel = false;
  final String _homePort = "https://conf.utigrand.cfd/";
  final Quartermaster _qm = Quartermaster();
  final ConsigliereCaptain _capo = ConsigliereCaptain();

  int _hatch = 0;
  DateTime? _napTime;
  bool _veil = false;
  double _barRel = 0.0;
  late Timer _barTick;
  final int _warmSecs = 6;
  bool _cover = true;

  bool _onceLoadedSignalSent = false;
  int? _firstPageStamp;

  HarborCourier? _courier;
  BosunViewModel? _bosun;

  String _currentUrl = "";
  var _startLoadTs = 0;

  // Флаги контроля sendRawData
  bool _afSentOnFirstLoadOnce = false; // один раз из onLoadStop
  bool _afSentByInitOnce = false; // один раз через 6 сек
  Timer? _initAfTimer;

  // Поддерживаемые схемы (включая соцсети)
  final Set<String> _schemes = {
    'tg', 'telegram',
    'whatsapp',
    'viber',
    'skype',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
    'bnl',
    // соцсети
    'instagram',
    'twitter',
    'x',
    'fb',
    'facebook',
  };

  // Доменные имена, которые должны открываться во встроенном браузере
  final Set<String> _externalHarbors = {
    // мессенджеры
    't.me', 'telegram.me', 'telegram.dog',
    'wa.me', 'api.whatsapp.com', 'chat.whatsapp.com',
    'm.me',
    'signal.me',
    // банки
    'bnl.com', 'www.bnl.com',
    // соцсети
    'instagram.com', 'www.instagram.com',
    'twitter.com', 'www.twitter.com',
    'x.com', 'www.x.com',
    'facebook.com', 'www.facebook.com', 'm.facebook.com',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _firstPageStamp = DateTime.now().millisecondsSinceEpoch;

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _cover = false);
    });

    Future.delayed(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(() => _veil = true);
    });

    _bootHarbor();
  }

  Future<void> _loadLoadedFlag() async {
    final sp = await SharedPreferences.getInstance();
    _onceLoadedSignalSent = sp.getBool(kChestKeyLoadedOnce) ?? false;
  }

  Future<void> _saveLoadedFlag() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(kChestKeyLoadedOnce, true);
    _onceLoadedSignalSent = true;
  }

  Future<void> sendLoadedOnce({required String url, required int timestart}) async {
    if (_onceLoadedSignalSent) {
      print("Loaded already sent, skipping");
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await postHarborStat(
      event: "Loaded",
      timeStart: timestart,
      timeFinish: now,
      url: url,
      appSid: _capo.afShipId,
      firstPageLoadTs: _firstPageStamp,
    );
    await _saveLoadedFlag();
  }

  void _bootHarbor() {
    _warmBar();
    _wireParrot();
    _capo.hoist(() => setState(() {}));
    _bindBell();
    _prepareQuartermaster();

    // ЕДИНСТВЕННЫЙ вызов sendRawData из initState через 6 сек
    _initAfTimer?.cancel();
    _initAfTimer = Timer(const Duration(seconds: 6), () async {
      if (!mounted) return;
      if (_afSentByInitOnce) return;
      _afSentByInitOnce = true;
      await _pushAF();
    });
  }

  void _wireParrot() {
    FirebaseMessaging.onMessage.listen((msg) {
      final link = msg.data['uri'];
      if (link != null) {
        _sail(link.toString());
      } else {
        _resetToHome();
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      final link = msg.data['uri'];
      if (link != null) {
        _sail(link.toString());
      } else {
        _resetToHome();
      }
    });
  }

  void _bindBell() {
    MethodChannel('com.example.fcm/notification').setMethodCallHandler((call) async {
      if (call.method == "onNotificationTap") {
        final Map<String, dynamic> payload = Map<String, dynamic>.from(call.arguments);
        if (payload["uri"] != null && !payload["uri"].contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => CaptainHarbor(signal: widget.signal)),
                (route) => false,
          );
        }
      }
    });
  }

  Future<void> _prepareQuartermaster() async {
    try {
      await _qm.muster();
      await _askQuartermasterPerms();
      _bosun = BosunViewModel(qm: _qm, capo: _capo);
      _courier = HarborCourier(model: _bosun!, getWeb: () => _pier);
      await _loadLoadedFlag();
    } catch (e) {
      RumBarrel().log.e("prepare-quartermaster fail: $e");
    }
  }

  Future<void> _askQuartermasterPerms() async {
    FirebaseMessaging m = FirebaseMessaging.instance;
    await m.requestPermission(alert: true, badge: true, sound: true);
  }

  void _sail(String link) async {
    if (_pier != null) {
      await _pier.loadUrl(urlRequest: URLRequest(url: WebUri(link)));
    }
  }

  void _resetToHome() async {
    Future.delayed(const Duration(seconds: 3), () {
      if (_pier != null) {
        _pier.loadUrl(urlRequest: URLRequest(url: WebUri(_homePort)));
      }
    });
  }

  Future<void> _pushDevice() async {
    RumBarrel().log.i("TOKEN ship ${widget.signal}");
    if (!mounted) return;
    setState(() => _spinWheel = true);
    try {
      await _courier?.stashDeviceInLocalStorage(widget.signal);
    } finally {
      if (mounted) setState(() => _spinWheel = false);
    }
  }

  Future<void> _pushAF() async {
    await _courier?.sendRawToDeck(widget.signal);
  }

  void _warmBar() {
    int n = 0;
    _barRel = 0.0;
    _barTick = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) return;
      setState(() {
        n++;
        _barRel = n / (_warmSecs * 10);
        if (_barRel >= 1.0) {
          _barRel = 1.0;
          _barTick.cancel();
        }
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState tide) {
    if (tide == AppLifecycleState.paused) {
      _napTime = DateTime.now();
    }
    if (tide == AppLifecycleState.resumed) {
      if (Platform.isIOS && _napTime != null) {
        final now = DateTime.now();
        final drift = now.difference(_napTime!);
        if (drift > const Duration(minutes: 25)) {
          _reboard();
        }
      }
      _napTime = null;
    }
  }

  void _reboard() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => CaptainHarbor(signal: widget.signal)),
            (route) => false,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _barTick.cancel();
    _initAfTimer?.cancel();
    super.dispose();
  }

  // ================== URL helpers ==================
  bool _bareMail(Uri u) {
    final s = u.scheme;
    if (s.isNotEmpty) return false;
    final raw = u.toString();
    return raw.contains('@') && !raw.contains(' ');
  }

  Uri _mailize(Uri u) {
    final full = u.toString();
    final parts = full.split('?');
    final email = parts.first;
    final qp = parts.length > 1 ? Uri.splitQueryString(parts[1]) : <String, String>{};
    return Uri(scheme: 'mailto', path: email, queryParameters: qp.isEmpty ? null : qp);
  }

  bool _platformish(Uri u) {
    final s = u.scheme.toLowerCase();
    if (_schemes.contains(s)) return true;

    if (s == 'http' || s == 'https') {
      final h = u.host.toLowerCase();
      if (_externalHarbors.contains(h)) return true;
      if (h.endsWith('t.me')) return true;
      if (h.endsWith('wa.me')) return true;
      if (h.endsWith('m.me')) return true;
      if (h.endsWith('signal.me')) return true;
      // соцсети зеркала
      if (h.endsWith('instagram.com')) return true;
      if (h.endsWith('twitter.com')) return true;
      if (h.endsWith('x.com')) return true;
      if (h.endsWith('facebook.com')) return true;
    }
    return false;
  }

  Uri _httpize(Uri u) {
    final s = u.scheme.toLowerCase();

    if (s == 'tg' || s == 'telegram') {
      final qp = u.queryParameters;
      final domain = qp['domain'];
      if (domain != null && domain.isNotEmpty) {
        return Uri.https('t.me', '/$domain', {if (qp['start'] != null) 'start': qp['start']!});
      }
      final path = u.path.isNotEmpty ? u.path : '';
      return Uri.https('t.me', '/$path', u.queryParameters.isEmpty ? null : u.queryParameters);
    }

    if ((s == 'http' || s == 'https') && u.host.toLowerCase().endsWith('t.me')) {
      return u;
    }

    if (s == 'viber') return u;

    if (s == 'whatsapp') {
      final qp = u.queryParameters;
      final phone = qp['phone'];
      final text = qp['text'];
      if (phone != null && phone.isNotEmpty) {
        return Uri.https('wa.me', '/${_digits(phone)}', {if (text != null && text.isNotEmpty) 'text': text});
      }
      return Uri.https('wa.me', '/', {if (text != null && text.isNotEmpty) 'text': text});
    }

    if ((s == 'http' || s == 'https') &&
        (u.host.toLowerCase().endsWith('wa.me') || u.host.toLowerCase().endsWith('whatsapp.com'))) {
      return u;
    }

    if (s == 'skype') return u;

    if (s == 'fb-messenger') {
      final path = u.pathSegments.isNotEmpty ? u.pathSegments.join('/') : '';
      final qp = u.queryParameters;
      final id = qp['id'] ?? qp['user'] ?? path;
      if (id.isNotEmpty) {
        return Uri.https('m.me', '/$id', u.queryParameters.isEmpty ? null : u.queryParameters);
      }
      return Uri.https('m.me', '/', u.queryParameters.isEmpty ? null : u.queryParameters);
    }

    if (s == 'sgnl') {
      final qp = u.queryParameters;
      final ph = qp['phone'];
      final un = u.queryParameters['username'];
      if (ph != null && ph.isNotEmpty) return Uri.https('signal.me', '/#p/${_digits(ph)}');
      if (un != null && un.isNotEmpty) return Uri.https('signal.me', '/#u/$un');
      final path = u.pathSegments.join('/');
      if (path.isNotEmpty) return Uri.https('signal.me', '/$path', u.queryParameters.isEmpty ? null : u.queryParameters);
      return u;
    }

    if (s == 'tel') {
      return Uri.parse('tel:${_digits(u.path)}');
    }

    if (s == 'mailto') return u;

    if (s == 'bnl') {
      final newPath = u.path.isNotEmpty ? u.path : '';
      return Uri.https('bnl.com', '/$newPath', u.queryParameters.isEmpty ? null : u.queryParameters);
    }

    // Соцсети: оставляем как есть (http/https) либо возвращаем https-варианты
    if (s == 'instagram') return u;
    if (s == 'twitter' || s == 'x') return u;
    if (s == 'fb' || s == 'facebook') return u;

    return u;
  }

  Future<bool> _openMailWeb(Uri mailto) async {
    final u = _gmailize(mailto);
    return await _openWeb(u);
  }

  Uri _gmailize(Uri m) {
    final qp = m.queryParameters;
    final params = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (m.path.isNotEmpty) 'to': m.path,
      if ((qp['subject'] ?? '').isNotEmpty) 'su': qp['subject']!,
      if ((qp['body'] ?? '').isNotEmpty) 'body': qp['body']!,
      if ((qp['cc'] ?? '').isNotEmpty) 'cc': qp['cc']!,
      if ((qp['bcc'] ?? '').isNotEmpty) 'bcc': qp['bcc']!,
    };
    return Uri.https('mail.google.com', '/mail/', params);
  }

  Future<bool> _openWeb(Uri u) async {
    try {
      if (await launchUrl(u, mode: LaunchMode.inAppBrowserView)) return true;
      return await launchUrl(u, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('openInAppBrowser error: $e; url=$u');
      try {
        return await launchUrl(u, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }
  }

  String _digits(String s) => s.replaceAll(RegExp(r'[^0-9+]'), '');

  bool _isKnownSocialOrMessengerHost(Uri uri) {
    final h = uri.host.toLowerCase();
    if (_externalHarbors.contains(h)) return true;
    // На всякий случай распознаем по поддоменам
    return h.endsWith('instagram.com') ||
        h.endsWith('facebook.com') ||
        h.endsWith('twitter.com') ||
        h.endsWith('x.com') ||
        h.endsWith('t.me') ||
        h.endsWith('telegram.me');
  }

  Future<void> _openSocialOrMessenger(Uri uri) async {
    // Стараемся открыть во встроенном браузере
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (ok) return;
    } catch (_) {}
    // Если не вышло — пробуем внешнее приложение/браузер
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    _bindBell(); // повторная привязка

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (_cover)
              const NeonDialLoader()
            else
              Container(
                color: Colors.black,
                child: Stack(
                  children: [
                    InAppWebView(
                      key: ValueKey(_hatch),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        disableDefaultErrorPage: true,
                        mediaPlaybackRequiresUserGesture: false,
                        allowsInlineMediaPlayback: true,
                        allowsPictureInPictureMediaPlayback: true,
                        useOnDownloadStart: true,
                        javaScriptCanOpenWindowsAutomatically: true,
                        useShouldOverrideUrlLoading: true,
                        supportMultipleWindows: true,
                        transparentBackground: true,
                      ),
                      initialUrlRequest: URLRequest(url: WebUri(_homePort)),
                      onWebViewCreated: (c) {
                        _pier = c;

                        _bosun ??= BosunViewModel(qm: _qm, capo: _capo);
                        _courier ??= HarborCourier(model: _bosun!, getWeb: () => _pier);

                        _pier.addJavaScriptHandler(
                          handlerName: 'onServerResponse',
                          callback: (args) {
                            try {
                              final saved = args.isNotEmpty &&
                                  args[0] is Map &&
                                  args[0]['savedata'].toString() == "true";
                              // тут можно обработать сохранение


                             if(  args[0]['savedata'].toString() =="false") {
                               Navigator.pushAndRemoveUntil(
                                 context,
                                 MaterialPageRoute(builder: (context) =>
                                     PirateHelp()),
                                     (route) => false,
                               );
                             }
                            } catch (_) {}
                            if (args.isEmpty) return null;
                            try {
                              return args.reduce((curr, next) => curr + next);
                            } catch (_) {
                              return args.first;
                            }
                          },
                        );
                      },
                      onLoadStart: (c, u) async {
                        setState(() {
                          _startLoadTs = DateTime.now().millisecondsSinceEpoch;
                        });
                        setState(() => _spinWheel = true);
                        final v = u;
                        if (v != null) {
                          if (_bareMail(v)) {
                            try {
                              await c.stopLoading();
                            } catch (_) {}
                            final mailto = _mailize(v);
                            await _openMailWeb(mailto);
                            return;
                          }
                          final sch = v.scheme.toLowerCase();
                          if (sch != 'http' && sch != 'https') {
                            try {
                              await c.stopLoading();
                            } catch (_) {}
                          }
                        }
                      },
                      onLoadError: (controller, url, code, message) async {
                        final now = DateTime.now().millisecondsSinceEpoch;
                        final ev = "InAppWebViewError(code=$code, message=$message)";
                        await postHarborStat(
                          event: ev,
                          timeStart: now,
                          timeFinish: now,
                          url: url?.toString() ?? '',
                          appSid: _capo.afShipId,
                          firstPageLoadTs: _firstPageStamp,
                        );
                        if (mounted) setState(() => _spinWheel = false);
                      },
                      onReceivedHttpError: (controller, request, errorResponse) async {
                        final now = DateTime.now().millisecondsSinceEpoch;
                        final ev = "HTTPError(status=${errorResponse.statusCode}, reason=${errorResponse.reasonPhrase})";
                        await postHarborStat(
                          event: ev,
                          timeStart: now,
                          timeFinish: now,
                          url: request.url?.toString() ?? '',
                          appSid: _capo.afShipId,
                          firstPageLoadTs: _firstPageStamp,
                        );
                      },
                      onReceivedError: (controller, request, error) async {
                        final now = DateTime.now().millisecondsSinceEpoch;
                        final desc = (error.description ?? '').toString();
                        final ev = "WebResourceError(code=${error}, message=$desc)";
                        await postHarborStat(
                          event: ev,
                          timeStart: now,
                          timeFinish: now,
                          url: request.url?.toString() ?? '',
                          appSid: _capo.afShipId,
                          firstPageLoadTs: _firstPageStamp,
                        );
                      },
                      onLoadStop: (c, u) async {
                        await c.evaluateJavascript(source: "console.log('Harbor up!');");
                        await _pushDevice();

                        // Один вызов sendRawData при первой полной загрузке
                        if (!_afSentOnFirstLoadOnce) {
                          _afSentOnFirstLoadOnce = true;
                          await _pushAF();
                        }

                        setState(() => _currentUrl = u.toString());

                        Future.delayed(const Duration(seconds: 20), () {
                          sendLoadedOnce(url: _currentUrl.toString(), timestart: _startLoadTs);
                        });

                        if (mounted) setState(() => _spinWheel = false);
                      },
                      shouldOverrideUrlLoading: (c, action) async {
                        final uri = action.request.url;
                        if (uri == null) return NavigationActionPolicy.ALLOW;

                        // Почтовые адреса без схемы
                        if (_bareMail(uri)) {
                          final mailto = _mailize(uri);
                          await _openMailWeb(mailto);
                          return NavigationActionPolicy.CANCEL;
                        }

                        final sch = uri.scheme.toLowerCase();

                        // Почта
                        if (sch == 'mailto') {
                          await _openMailWeb(uri);
                          return NavigationActionPolicy.CANCEL;
                        }

                        // Телефон
                        if (sch == 'tel') {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                          return NavigationActionPolicy.CANCEL;
                        }

                        // Соцсети и мессенджеры — открыть во встроенном браузере
                        if (_platformish(uri) || _isKnownSocialOrMessengerHost(uri)) {
                          final web = _httpize(uri);
                          if ((web.scheme == 'http' || web.scheme == 'https') || web == uri) {
                            await _openSocialOrMessenger(web);
                          } else {
                            // нативная схема — пробуем внешнее приложение, иначе веб
                            try {
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              } else if (web != uri && (web.scheme == 'http' || web.scheme == 'https')) {
                                await _openSocialOrMessenger(web);
                              }
                            } catch (_) {}
                          }
                          return NavigationActionPolicy.CANCEL;
                        }

                        // Блокируем любые не http/https
                        if (sch != 'http' && sch != 'https') {
                          return NavigationActionPolicy.CANCEL;
                        }

                        return NavigationActionPolicy.ALLOW;
                      },
                      onCreateWindow: (c, req) async {
                        final uri = req.request.url;
                        if (uri == null) return false;

                        if (_bareMail(uri)) {
                          final mailto = _mailize(uri);
                          await _openMailWeb(mailto);
                          return false;
                        }

                        final sch = uri.scheme.toLowerCase();

                        if (sch == 'mailto') {
                          await _openMailWeb(uri);
                          return false;
                        }

                        if (sch == 'tel') {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                          return false;
                        }

                        // Соцсети/мессенджеры в новом окне — тоже во встроенном браузере
                        if (_platformish(uri) || _isKnownSocialOrMessengerHost(uri)) {
                          final web = _httpize(uri);
                          if (web.scheme == 'http' || web.scheme == 'https') {
                            await _openSocialOrMessenger(web);
                          } else {
                            try {
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              } else if (web != uri && (web.scheme == 'http' || web.scheme == 'https')) {
                                await _openSocialOrMessenger(web);
                              }
                            } catch (_) {}
                          }
                          return false;
                        }

                        if (sch == 'http' || sch == 'https') {
                          c.loadUrl(urlRequest: URLRequest(url: uri));
                        }
                        return false;
                      },
                      onDownloadStartRequest: (c, req) async {
                        await _openWeb(req.url);
                      },
                    ),
                    Visibility(
                      visible: !_veil,
                      child: const NeonDialLoader(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// CaptainDeck -- отдельное простое WebView на внешнюю ссылку (из нотификаций)
// ============================================================================
class CaptainDeck extends StatefulWidget with WidgetsBindingObserver {
  final String seaLane;
  const CaptainDeck(this.seaLane, {super.key});

  @override
  State<CaptainDeck> createState() => _CaptainDeckState();
}

class _CaptainDeckState extends State<CaptainDeck> with WidgetsBindingObserver {
  late InAppWebViewController _deck;

  @override
  Widget build(BuildContext context) {
    final night = MediaQuery.of(context).platformBrightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: night ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: InAppWebView(
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            disableDefaultErrorPage: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            allowsPictureInPictureMediaPlayback: true,
            useOnDownloadStart: true,
            javaScriptCanOpenWindowsAutomatically: true,
            useShouldOverrideUrlLoading: true,
            supportMultipleWindows: true,
          ),
          initialUrlRequest: URLRequest(url: WebUri(widget.seaLane)),
          onWebViewCreated: (c) => _deck = c,
        ),
      ),
    );
  }
}

// ============================================================================
// Help экраны
// ============================================================================
class PirateHelp extends StatefulWidget {
  const PirateHelp({super.key});

  @override
  State<PirateHelp> createState() => _PirateHelpState();
}

class _PirateHelpState extends State<PirateHelp> with WidgetsBindingObserver {
  InAppWebViewController? _ctrl;
  bool _spin = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            InAppWebView(
              initialFile: 'assets/index.html',
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                supportZoom: false,
                disableHorizontalScroll: false,
                disableVerticalScroll: false,
              ),
              onWebViewCreated: (c) => _ctrl = c,
              onLoadStart: (c, u) => setState(() => _spin = true),
              onLoadStop: (c, u) async => setState(() => _spin = false),
              onLoadError: (c, u, code, msg) => setState(() => _spin = false),
            ),
            if (_spin) const NeonDialLoader(),
          ],
        ),
      ),
    );
  }
}

class PirateHelpLite extends StatefulWidget {
  const PirateHelpLite({super.key});

  @override
  State<PirateHelpLite> createState() => _PirateHelpLiteState();
}

class _PirateHelpLiteState extends State<PirateHelpLite> {
  InAppWebViewController? _wvc;
  bool _ld = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            InAppWebView(
              initialFile: 'assets/index.html',
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                supportZoom: false,
                disableHorizontalScroll: false,
                disableVerticalScroll: false,
                transparentBackground: true,
                mediaPlaybackRequiresUserGesture: false,
                disableDefaultErrorPage: true,
                allowsInlineMediaPlayback: true,
                allowsPictureInPictureMediaPlayback: true,
                useOnDownloadStart: true,
                javaScriptCanOpenWindowsAutomatically: true,
              ),
              onWebViewCreated: (controller) => _wvc = controller,
              onLoadStart: (controller, url) => setState(() => _ld = true),
              onLoadStop: (controller, url) async => setState(() => _ld = false),
              onLoadError: (controller, url, code, message) => setState(() => _ld = false),
            ),
            if (_ld)
              const Positioned.fill(
                child: IgnorePointer(
                  ignoring: true,
                  child: NeonDialLoader(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// main()
// ============================================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(parrotBgSquawk);

  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }
  tz_data.initializeTimeZones();

  runApp(
    p.MultiProvider(
      providers: [
        consigliereProvider,
      ],
      child: r.ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: const JollyVestibule(),
        ),
      ),
    ),
  );
}