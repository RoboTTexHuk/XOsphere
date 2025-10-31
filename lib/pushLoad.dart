// -----------------------------------------------------------------------------

import 'dart:convert';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart' show AppsFlyerOptions, AppsflyerSdk;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel, SystemUiOverlayStyle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'main.dart' show XoMafiaHarbor, XoCaptainHarbor, CaptainHarbor;

// ============================================================================
// Паттерны/инфраструктура (xosphere style)
// ============================================================================

class XoLogCore {
  const XoLogCore();
  void log(Object msg) => debugPrint('[XoLogCore] $msg');
  void warn(Object msg) => debugPrint('[XoLogCore/WARN] $msg');
  void err(Object msg) => debugPrint('[XoLogCore/ERR] $msg');
}

class XoDepot {
  static final XoDepot _single = XoDepot._();
  XoDepot._();
  factory XoDepot() => _single;

  final XoLogCore log = const XoLogCore();
}

/// Утилиты маршрутов/почты (XoRouteKit)
class XoRouteKit {
  // Похоже ли на голый e-mail (без схемы)
  static bool isBareEmailRoute(Uri u) {
    final s = u.scheme;
    if (s.isNotEmpty) return false;
    final raw = u.toString();
    return raw.contains('@') && !raw.contains(' ');
  }

  // Превращает "bare" или обычный URL в mailto:
  static Uri toMailto(Uri u) {
    final full = u.toString();
    final bits = full.split('?');
    final who = bits.first;
    final qp = bits.length > 1 ? Uri.splitQueryString(bits[1]) : <String, String>{};
    return Uri(
      scheme: 'mailto',
      path: who,
      queryParameters: qp.isEmpty ? null : qp,
    );
  }

  // Делает Gmail compose-ссылку
  static Uri toGmailCompose(Uri m) {
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

  static String digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9+]'), '');
}

/// Сервис открытия внешних ссылок/протоколов (XoExternalOpener)
class XoExternalOpener {
  static Future<bool> open(Uri u) async {
    try {
      if (await launchUrl(u, mode: LaunchMode.inAppBrowserView)) return true;
      return await launchUrl(u, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('XoExternalOpener error: $e; url=$u');
      try {
        return await launchUrl(u, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }
  }
}

// ============================================================================
// FCM Background Handler — Xo FCM handler
// ============================================================================
@pragma('vm:entry-point')
Future<void> xosphereFcmBackgroundHandler(RemoteMessage msg) async {
  debugPrint("XoBottle ID: ${msg.messageId}");
  debugPrint("XoBottle Data: ${msg.data}");
}

// ============================================================================
// Виджет-каюта с webview — XoWebDeck
// ============================================================================
class XoWebDeck extends StatefulWidget with WidgetsBindingObserver {
  String seaRoute;
  XoWebDeck(this.seaRoute, {super.key});

  @override
  State<XoWebDeck> createState() => _XoWebDeckState(seaRoute);
}

class _XoWebDeckState extends State<XoWebDeck> with WidgetsBindingObserver {
  _XoWebDeckState(this._currentRoute);

  final XoDepot _depot = XoDepot();

  late InAppWebViewController _helm; // главный штурвал
  String? _fcmToken; // FCM token
  String? _deviceId; // device id
  String? _osBuild; // os build
  String? _platform; // android/ios
  String? _locale; // locale/lang
  String? _tzName; // timezone
  bool _pushEnabled = true; // push enabled
  bool _overlayBusy = false;
  var _gateOpen = true;
  String _currentRoute;
  DateTime? _lastBackgroundAt;

  // Внешние гавани (tg/wa/bnl)
  final Set<String> _outerHosts = {
    't.me', 'telegram.me', 'telegram.dog',
    'wa.me', 'api.whatsapp.com', 'chat.whatsapp.com',
    'bnl.com', 'www.bnl.com',
  };
  final Set<String> _outerSchemes = {'tg', 'telegram', 'whatsapp', 'bnl'};

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    FirebaseMessaging.onBackgroundMessage(xosphereFcmBackgroundHandler);

    _xoRigFcm();
    _xoScanDevice();
    _xoBindFcmForeground();
    _xoBindNotificationTapChannel();

    // зарезервированные таймеры
    Future.delayed(const Duration(seconds: 2), () {});
    Future.delayed(const Duration(seconds: 6), () {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState tide) {
    if (tide == AppLifecycleState.paused) {
      _lastBackgroundAt = DateTime.now();
    }
    if (tide == AppLifecycleState.resumed) {
      if (Platform.isIOS && _lastBackgroundAt != null) {
        final now = DateTime.now();
        final drift = now.difference(_lastBackgroundAt!);
        if (drift > const Duration(minutes: 25)) {
          _xoForceHarborReload();
        }
      }
      _lastBackgroundAt = null;
    }
  }

  void _xoForceHarborReload() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => CaptainHarbor(signal: "")),
            (route) => false,
      );
    });
  }

  // --------------------------------------------------------------------------
  // Каналы связи
  // --------------------------------------------------------------------------
  void _xoBindFcmForeground() {
    FirebaseMessaging.onMessage.listen((RemoteMessage bottle) {
      if (bottle.data['uri'] != null) {
        _xoSailTo(bottle.data['uri'].toString());
      } else {
        _xoReturnToCourse();
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage bottle) {
      if (bottle.data['uri'] != null) {
        _xoSailTo(bottle.data['uri'].toString());
      } else {
        _xoReturnToCourse();
      }
    });
  }

  void _xoSailTo(String newLane) async {
    await _helm.loadUrl(urlRequest: URLRequest(url: WebUri(newLane)));
  }

  void _xoReturnToCourse() async {
    Future.delayed(const Duration(seconds: 3), () {
      _helm.loadUrl(urlRequest: URLRequest(url: WebUri(_currentRoute)));
    });
  }

  Future<void> _xoRigFcm() async {
    FirebaseMessaging fm = FirebaseMessaging.instance;
    await fm.requestPermission(alert: true, badge: true, sound: true);
    _fcmToken = await fm.getToken();
  }

  // --------------------------------------------------------------------------
  // Досье устройства
  // --------------------------------------------------------------------------
  Future<void> _xoScanDevice() async {
    try {
      final spy = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await spy.androidInfo;
        _deviceId = a.id;
        _platform = "android";
        _osBuild = a.version.release;
      } else if (Platform.isIOS) {
        final i = await spy.iosInfo;
        _deviceId = i.identifierForVendor;
        _platform = "ios";
        _osBuild = i.systemVersion;
      }
      final pkg = await PackageInfo.fromPlatform();
      _locale = Platform.localeName.split('_')[0]; // фикс сплита
      _tzName = timezone.local.name;
    } catch (e) {
      debugPrint("XoDevice Probe Error: $e");
    }
  }

  /// Обработчик тапа по нативному уведомлению
  void _xoBindNotificationTapChannel() {
    MethodChannel('com.example.fcm/notification').setMethodCallHandler((MethodCall call) async {
      if (call.method == "onNotificationTap") {
        final Map<String, dynamic> bottle = Map<String, dynamic>.from(call.arguments);
        debugPrint("Xo URI from mast: ${bottle['uri']}");
        final uri = bottle["uri"]?.toString();
        if (uri != null && !uri.contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => XoWebDeck(uri)),
                (route) => false,
          );
        }
      }
    });
  }

  // --------------------------------------------------------------------------
  // Построение UI
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    _xoBindNotificationTapChannel(); // повторная привязка как в оригинале

    final isNight = MediaQuery.of(context).platformBrightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isNight ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            InAppWebView(
              initialSettings:  InAppWebViewSettings(
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
              initialUrlRequest: URLRequest(url: WebUri(_currentRoute)),
              onWebViewCreated: (controller) {
                _helm = controller;

                _helm.addJavaScriptHandler(
                  handlerName: 'onServerResponse',
                  callback: (args) {
                    _depot.log.log("JS Args: $args");
                    try {
                      return args.reduce((v, e) => v + e);
                    } catch (_) {
                      return args.toString();
                    }
                  },
                );
              },
              onLoadStart: (controller, uri) async {
                if (uri != null) {
                  if (XoRouteKit.isBareEmailRoute(uri)) {
                    try {
                      await controller.stopLoading();
                    } catch (_) {}
                    final mailto = XoRouteKit.toMailto(uri);
                    await XoExternalOpener.open(XoRouteKit.toGmailCompose(mailto));
                    return;
                  }
                  final s = uri.scheme.toLowerCase();
                  if (s != 'http' && s != 'https') {
                    try {
                      await controller.stopLoading();
                    } catch (_) {}
                  }
                }
              },
              onLoadStop: (controller, uri) async {
                await controller.evaluateJavascript(source: "console.log('Ahoy from JS!');");
              },
              shouldOverrideUrlLoading: (controller, nav) async {
                final uri = nav.request.url;
                if (uri == null) return NavigationActionPolicy.ALLOW;

                if (XoRouteKit.isBareEmailRoute(uri)) {
                  final mailto = XoRouteKit.toMailto(uri);
                  await XoExternalOpener.open(XoRouteKit.toGmailCompose(mailto));
                  return NavigationActionPolicy.CANCEL;
                }

                final sch = uri.scheme.toLowerCase();
                if (sch == 'mailto') {
                  await XoExternalOpener.open(XoRouteKit.toGmailCompose(uri));
                  return NavigationActionPolicy.CANCEL;
                }

                if (_xoIsOuterHarbor(uri)) {
                  await XoExternalOpener.open(_xoMapOuterToHttp(uri));
                  return NavigationActionPolicy.CANCEL;
                }

                if (sch != 'http' && sch != 'https') {
                  return NavigationActionPolicy.CANCEL;
                }
                return NavigationActionPolicy.ALLOW;
              },
              onCreateWindow: (controller, req) async {
                final u = req.request.url;
                if (u == null) return false;

                if (XoRouteKit.isBareEmailRoute(u)) {
                  final m = XoRouteKit.toMailto(u);
                  await XoExternalOpener.open(XoRouteKit.toGmailCompose(m));
                  return false;
                }

                final sch = u.scheme.toLowerCase();
                if (sch == 'mailto') {
                  await XoExternalOpener.open(XoRouteKit.toGmailCompose(u));
                  return false;
                }

                if (_xoIsOuterHarbor(u)) {
                  await XoExternalOpener.open(_xoMapOuterToHttp(u));
                  return false;
                }

                if (sch == 'http' || sch == 'https') {
                  controller.loadUrl(urlRequest: URLRequest(url: u));
                }
                return false;
              },
            ),

            if (_overlayBusy)
              Positioned.fill(
                child: Container(
                  color: Colors.black87,
                  child: Center(
                    child: CircularProgressIndicator(
                      backgroundColor: Colors.grey.shade800,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
                      strokeWidth: 6,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // Пиратские утилиты маршрутов (протоколы/внешние гавани)
  // ========================================================================
  bool _xoIsOuterHarbor(Uri u) {
    final sch = u.scheme.toLowerCase();
    if (_outerSchemes.contains(sch)) return true;

    if (sch == 'http' || sch == 'https') {
      final h = u.host.toLowerCase();
      if (_outerHosts.contains(h)) return true;
    }
    return false;
  }

  Uri _xoMapOuterToHttp(Uri u) {
    final sch = u.scheme.toLowerCase();

    if (sch == 'tg' || sch == 'telegram') {
      final qp = u.queryParameters;
      final domain = qp['domain'];
      if (domain != null && domain.isNotEmpty) {
        return Uri.https('t.me', '/$domain', {
          if (qp['start'] != null) 'start': qp['start']!,
        });
      }
      final path = u.path.isNotEmpty ? u.path : '';
      return Uri.https('t.me', '/$path', u.queryParameters.isEmpty ? null : u.queryParameters);
    }

    if (sch == 'whatsapp') {
      final qp = u.queryParameters;
      final phone = qp['phone'];
      final text = qp['text'];
      if (phone != null && phone.isNotEmpty) {
        return Uri.https('wa.me', '/${XoRouteKit.digitsOnly(phone)}', {
          if (text != null && text.isNotEmpty) 'text': text,
        });
      }
      return Uri.https('wa.me', '/', {if (text != null && text.isNotEmpty) 'text': text});
    }

    if (sch == 'bnl') {
      final newPath = u.path.isNotEmpty ? u.path : '';
      return Uri.https('bnl.com', '/$newPath', u.queryParameters.isEmpty ? null : u.queryParameters);
    }

    return u;
  }
}