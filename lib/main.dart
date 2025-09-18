import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as rnd;

import 'package:auto_orientation/auto_orientation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:timezone/data/latest.dart' as tzdex;
import 'package:timezone/timezone.dart' as tzcore;

// AppsFlyer SDK
import 'package:appsflyer_sdk/appsflyer_sdk.dart' as afx;

final X13_BLACKLIST = [
  ".*.doubleclick.net/.*",
  ".*.ads.pubmatic.com/.*",
  ".*.googlesyndication.com/.*",
  ".*.google-analytics.com/.*",
  ".*.adservice.google.*/.*",
  ".*.adbrite.com/.*",
  ".*.exponential.com/.*",
  ".*.quantserve.com/.*",
  ".*.scorecardresearch.com/.*",
  ".*.zedo.com/.*",
  ".*.adsafeprotected.com/.*",
  ".*.teads.tv/.*",
  ".*.outbrain.com/.*",
];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // TZ init
  tzdex.initializeTimeZones();

  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.black,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  ));

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: W0GateMask(),
  ));
}

/// Неоновый круговой лоадер
class NeonDialLoader extends StatefulWidget {
  const NeonDialLoader({super.key});

  @override
  State<NeonDialLoader> createState() => _NeonDialLoaderState();
}

class _NeonDialLoaderState extends State<NeonDialLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController spinCtrl;

  @override
  void initState() {
    super.initState();
    spinCtrl =
    AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
  }

  @override
  void dispose() {
    spinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const neonColor = Color(0xFF00FFFF);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: AnimatedBuilder(
          animation: spinCtrl,
          builder: (context, _) {
            final angle = spinCtrl.value * 2 * rnd.pi;
            return CustomPaint(
              painter: _NeonDialPainter(angle, neonColor),
              size: const Size(160, 160),
            );
          },
        ),
      ),
    );
  }
}

class _NeonDialPainter extends CustomPainter {
  final double angle;
  final Color neonColor;
  _NeonDialPainter(this.angle, this.neonColor);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final center = Offset(w / 2, size.height / 2);
    final radius = w / 2 - 8;

    final circlePaint = Paint()
      ..color = neonColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(center, radius, circlePaint);

    final needleLen = radius - 12;
    final needlePaint = Paint()
      ..color = neonColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final end = Offset(center.dx + needleLen * rnd.cos(angle),
        center.dy + needleLen * rnd.sin(angle));
    canvas.drawLine(center, end, needlePaint);

    canvas.drawCircle(center, 6, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _NeonDialPainter old) =>
      old.angle != angle || old.neonColor != neonColor;
}

/// Короткий сплэш перед основным экраном
class W0GateMask extends StatefulWidget {
  const W0GateMask({super.key});
  @override
  State<W0GateMask> createState() => _W0GateMaskState();
}

class _W0GateMaskState extends State<W0GateMask> {
  bool wvCover = true;
  Timer? wvTimer;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => wvCover = false);
    });
    wvTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const Q8HostCore()));
    });
  }

  @override
  void dispose() {
    wvTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        if (wvCover) const NeonDialLoader(),
        if (!wvCover) const Center(child: NeonDialLoader()),
      ]),
    );
  }
}

/// Сбор устройственных данных
class D5Probe {
  String? dId;
  String? sess;
  String? plat;
  String? osv;
  String? appv;
  String? lang;
  String? tzid;
  bool push = false;

  Future<void> prime() async {
    final di = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final x = await di.androidInfo;
      dId = x.id;
      plat = "android";
      osv = x.version.release;
    } else if (Platform.isIOS) {
      final x = await di.iosInfo;
      dId = x.identifierForVendor;
      plat = "ios";
      osv = x.systemVersion;
    } else {
      plat = "unknown";
      dId = "unknown-device";
      osv = "unknown-os";
    }
    final app = await PackageInfo.fromPlatform();
    appv = app.version;
    lang = Platform.localeName.split('_').first;
    tzid = tzcore.local.name;
    sess = "s-${DateTime.now().millisecondsSinceEpoch}";
  }
}

/// AppsFlyer контроллер
class A9Trace with ChangeNotifier {
  afx.AppsflyerSdk? core;
  String uid = "";
  String raw = "";

  static const String key = "qsBLmy7dAXDQhowM8V3ca4";
  static const String app = "6752573451";

  void ignite(VoidCallback cb) {
    final cfg = afx.AppsFlyerOptions(
      afDevKey: key,
      appId: app,
      showDebug: true,
    );

    core = afx.AppsflyerSdk(cfg);

    core?.onInstallConversionData((res) {
      raw = res.toString();
      print("AF conv: $raw");
      cb();
      notifyListeners();
    });

    core?.onAppOpenAttribution((res) {
    print("AF open attrib: $res");
    });

    core?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );

    core?.startSDK(
      onSuccess: () => print("AF started"),
      onError: (int c, String m) => print("AF error $c: $m"),
    );

    core?.getAppsFlyerUID().then((v) {
      uid = v.toString();
     print("AF UID: $uid");
      cb();
      notifyListeners();
    }).catchError((e) {
    print("AF UID err: $e");
    });
  }
}

/// Главный экран
class Q8HostCore extends StatefulWidget {
  const Q8HostCore({super.key});
  @override
  State<Q8HostCore> createState() => _Q8HostCoreState();
}

class _Q8HostCoreState extends State<Q8HostCore> with WidgetsBindingObserver {
  InAppWebViewController? web;
  final String entry = "https://conf.utigrand.cfd/";
  final D5Probe dev = D5Probe();

  bool layerTop = true;
  bool layerBottom = true;
  double prog = 0.0;
  Timer? progT;
  final int progSec = 6;

  final Connectivity net = Connectivity();
  String? fakeToken; // заглушка‑токен
  final A9Trace af = A9Trace();

  final List<ContentBlocker> blockers = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AutoOrientation.portraitUpMode();


    // Оверлеи
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => layerTop = false);
    });
    Future.delayed(const Duration(seconds: 9), () {
      if (mounted) setState(() => layerBottom = false);
    });

    _bootAll();

    // Повторная отправка через 5 сек
    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      _emit(af.raw);
    });
  }

  Future<void> _bootAll() async {
    _fakeProgress();
    await dev.prime();

    // AppsFlyer init
    af.ignite(() {
      if (web != null) {
        _emit(af.raw);
      }
    });

    final c = await net.checkConnectivity();
   print("Connectivity: $c");
  }

  void _fakeProgress() {
    int t = 0;
    prog = 0;
    progT?.cancel();
    progT = Timer.periodic(const Duration(milliseconds: 100), (tm) {
      if (!mounted) return;
      setState(() {
        t++;
        prog = t / (progSec * 10);
        if (prog >= 1.0) {
          prog = 1.0;
          progT?.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    progT?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
     print("App resumed");
    }
  }

  // Ожидаем готовности функции sendRawData
  Future<bool> _waitJs({Duration timeout = const Duration(seconds: 5)}) async {
    final start = DateTime.now();
    while (DateTime.now().difference(start) < timeout) {
      if (web == null) return false;
      try {
        final res = await web!.evaluateJavascript(
          source: "typeof sendRawData === 'function' ? 'ok' : 'no'",
        );
        if (res == 'ok') return true;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  // Отправка данных в JS (как в исходном — строкой JSON)
  Future<void> _emit(String cv) async {
    if (web == null) {
   print('_emit: WebView is null');
      return;
    }

    fakeToken ??= 'debug-token';
    final afId = (af.uid.isNotEmpty) ? af.uid : "unknown_af_id";

    final afData = (cv.isNotEmpty)
        ? cv
        : "{status: success, payload: {is_first_launch: true, ts: ${DateTime.now().toIso8601String()}, af_message: organic install, af_status: Organic}}";

    final body = {
      "content": {
        "af_data": afData,
        "af_id": afId,
        "fb_app_name": "honspehre",
        "app_name": "honspehre",
        "deep": null,
        "bundle_identifier": "com.eloplp.honsphere",
        "app_version": "1.0.0",
        "apple_id": "6752573451",
        "fcm_token": fakeToken ?? '',
        "device_id": dev.dId ?? "no_device",
        "instance_id": dev.sess ?? "no_instance",
        "platform": dev.plat ?? "no_type",
        "os_version": dev.osv ?? "no_os",
        "language": dev.lang ?? "en",
        "timezone": dev.tzid ?? "UTC",
        "push_enabled": dev.push,
        "useruid": afId,
      },
    };

    final s = jsonEncode(body);
  print("SendRawData: $s");

    try {
      await _waitJs(timeout: const Duration(seconds: 5));
      final res = await web!.evaluateJavascript(
        source: "sendRawData(${jsonEncode(s)});",
      );
    print("_emit dispatched, js result: $res");
    } catch (e) {
     print("_emit JS error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              if (layerTop) const NeonDialLoader(),
              if (!layerTop)
                Container(
                  color: Colors.black,
                  child: Stack(
                    children: [
                      InAppWebView(
                        initialSettings: InAppWebViewSettings(
                          javaScriptEnabled: true,
                          disableDefaultErrorPage: true,
                          contentBlockers: blockers,
                          mediaPlaybackRequiresUserGesture: false,
                          allowsInlineMediaPlayback: true,
                          allowsPictureInPictureMediaPlayback: true,
                          useOnDownloadStart: true,
                          javaScriptCanOpenWindowsAutomatically: true,
                          useShouldOverrideUrlLoading: true,
                          supportMultipleWindows: true,
                        ),
                        initialUrlRequest: URLRequest(url: WebUri(entry)),
                        onWebViewCreated: (c) {
                          web = c;
                          web!.addJavaScriptHandler(
                            handlerName: 'onServerResponse',
                            callback: (args) async {
                              final mp = args.isNotEmpty && args.first is Map ? args.first as Map : {};

                              print("MP load "+mp.toString());

                              try {
                                final mp = args.isNotEmpty && args.first is Map ? (args.first as Map) : <String, dynamic>{};

                                final savedataStr = mp['savedata']?.toString() ?? '';
                                if (savedataStr == "false") {
                                  // Берём url и нормализуем
                                  final urlRaw = mp['url'];
                                  final urlStr = urlRaw?.toString().trim() ?? '';

                                  // Условия: пусто или содержит "google" (без учёта регистра)
                                  final isEmptyUrl = urlStr.isEmpty;
                                  final hasGoogle = urlStr.toLowerCase().contains('google');

                                  if (isEmptyUrl || hasGoogle) {
                                    Navigator.pushAndRemoveUntil(
                                      context,
                                      MaterialPageRoute(builder: (context) => SupportScreen()),
                                          (route) => false,
                                    );
                                    return "ok";
                                  }

                                  // Иначе (savedata == false, но url валидная и без "google")
                                  // Если вы хотите ВСЕГДА уходить на SupportScreen при savedata == false,
                                  // оставьте этот блок. Если не нужно — удалите.
                                  Navigator.pushAndRemoveUntil(
                                    context,
                                    MaterialPageRoute(builder: (context) => SupportScreen()),
                                        (route) => false,
                                  );
                                  return "ok";
                                }
                              } catch (e) {
                               // if (kDebugMode) print("server echo parse error: $e");
                              }
                              return "ok";
                            },
                          );
                        },
                        onLoadStart: (c, u) async {},
                        onLoadStop: (c, u) async {
                          _emit(af.raw);
                        },
                        shouldOverrideUrlLoading: (c, action) async {
                          return NavigationActionPolicy.ALLOW;
                        },
                        onCreateWindow: (c, req) async {
                          return false;
                        },
                        onDownloadStartRequest: (c, req) async {},
                      ),
                      if (layerBottom) const NeonDialLoader(),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => SupportScreenState();
}

class SupportScreenState extends State<SupportScreen> {
  InAppWebViewController? webViewController;
  bool loading = true;

  @override
  Widget build(BuildContext context) {
    // Важно: не оборачивать в новый MaterialApp
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            InAppWebView(
              initialFile: 'assets/index.html',
              initialSettings:  InAppWebViewSettings(
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
              onWebViewCreated: (controller) {
                webViewController = controller;
              },
              onLoadStart: (controller, url) {
                setState(() {
                  loading = true;
                });
              },
              onLoadStop: (controller, url) async {
                setState(() {
                  loading = false;
                });
              },
              onLoadError: (controller, url, code, message) {
                setState(() {
                  loading = false;
                });
              },
            ),
            if (loading)
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


