import 'dart:async';
import 'dart:io';

import 'package:clipboard_watcher/clipboard_watcher.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:win32/win32.dart' as win;
import 'package:window_manager/window_manager.dart';

import '../noyau/noyau.dart';
import '../ui/capture_rapide.dart';
import '../ui/coquille.dart';

/// Intégration au système des apps desktop (B1, B3, H9, I9, C2).
class IntegrationDesktop with ClipboardListener, WindowListener {
  IntegrationDesktop._(this.noyau);

  final Noyau noyau;
  static IntegrationDesktop? _instance;
  static bool _pause = false;
  static bool _premierPlan = false;

  static bool get captureDisponible => _instance != null;

  static Future<void> initialiser(Noyau noyau) async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
    final i = IntegrationDesktop._(noyau);
    _instance = i;
    _pause = await noyau.base.lireMeta<bool>('capture_pause') ?? false;

    await windowManager.ensureInitialized();
    await windowManager.setTitle('LuluBoard');
    await windowManager.setMinimumSize(const Size(380, 480));
    await windowManager.setPreventClose(true); // fermer = réduire dans la zone de notification
    windowManager.addListener(i);

    await _essayer(() async {
      await localNotifier.setup(appName: 'LuluBoard', shortcutPolicy: ShortcutPolicy.requireCreate);
    });
    await _essayer(i._installerZoneNotification);
    await _essayer(i._installerRaccourcis);
    await _essayer(() async {
      clipboardWatcher.addListener(i);
      await clipboardWatcher.start();
    });
    await _essayer(() async {
      LaunchAtStartup.instance.setup(appName: 'LuluBoard', appPath: Platform.resolvedExecutable);
      if (await noyau.base.lireMeta<bool>('demarrage_auto') ?? true) await LaunchAtStartup.instance.enable();
    });
  }

  static Future<void> _essayer(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Une fonction système indisponible ne doit jamais empêcher l'app de démarrer.
    }
  }

  // --- Presse-papier (B1) ------------------------------------------------------------------

  @override
  void onClipboardChanged() async {
    if (_pause || _estSensible()) return;
    final donnees = await Clipboard.getData(Clipboard.kTextPlain);
    final texte = donnees?.text;
    if (texte == null || texte.isEmpty) return;
    if (texte.length > 100 * 1024) return; // au-delà de 100 Ko, ce n'est plus une entrée de presse-papier (B1)
    await noyau.depot.ajouterPressePapier(texte);
  }

  /// Les gestionnaires de mots de passe marquent leurs copies : on les ignore (B1).
  bool _estSensible() {
    if (!Platform.isWindows) return false;
    try {
      return using((arena) {
        for (final format in ['ExcludeClipboardContentFromMonitorProcessing', 'Clipboard Viewer Ignore']) {
          final id = win.RegisterClipboardFormat(arena.pcwstr(format)).value;
          if (id != 0 && win.IsClipboardFormatAvailable(id).value) return true;
        }
        return false;
      });
    } catch (_) {
      return false;
    }
  }

  static Future<void> definirPause(bool pause) async {
    _pause = pause;
    await _instance?.noyau.base.ecrireMeta('capture_pause', pause);
  }

  static Future<void> definirDemarrageAuto(bool actif) async {
    await _instance?.noyau.base.ecrireMeta('demarrage_auto', actif);
    await _essayer(() async => actif ? await LaunchAtStartup.instance.enable() : await LaunchAtStartup.instance.disable());
  }

  // --- Raccourcis globaux (B3, H9) ---------------------------------------------------------

  Future<void> _installerRaccourcis() async {
    await hotKeyManager.unregisterAll();
    await hotKeyManager.register(
      HotKey(key: PhysicalKeyboardKey.keyB, modifiers: [HotKeyModifier.control, HotKeyModifier.alt]),
      keyDownHandler: (_) => _afficher(section: 0),
    );
    await hotKeyManager.register(
      HotKey(key: PhysicalKeyboardKey.keyN, modifiers: [HotKeyModifier.control, HotKeyModifier.alt]),
      keyDownHandler: (_) async {
        await _afficher();
        CaptureRapide.demander();
      },
    );
  }

  Future<void> _afficher({int? section}) async {
    await windowManager.show();
    await windowManager.focus();
    if (section != null) Coquille.sectionDemandee.value = section;
  }

  // --- Zone de notification (I9) -----------------------------------------------------------

  // ignore: unused_field
  TrayIcon? _icone; // référence conservée : sans elle, l'icône disparaît

  Future<void> _installerZoneNotification() async {
    final icone = TrayIcon.create();
    if (icone == null) return;
    _icone = icone;
    icone.icon = ImageAsset.fromAsset('assets/icone_tray.png');
    icone.setTooltip('LuluBoard');
    final menu = Menu.create()!;
    void ajouter(String libelle, Future<void> Function() action) {
      final item = MenuItem.createWithLabelAndType(libelle, MenuItemType.normal)!;
      item.addListener((evenement) {
        if (evenement is MenuItemClickedEvent) action();
      });
      menu.addItem(item);
    }

    ajouter('Ouvrir LuluBoard', () => _afficher());
    ajouter('Capture rapide (Ctrl+Alt+N)', () async {
      await _afficher();
      CaptureRapide.demander();
    });
    menu.addSeparator();
    ajouter('Quitter', () async {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    });
    icone.setContextMenu(menu);
    icone.addListener((evenement) {
      if (evenement is TrayIconClickedEvent) _afficher();
    });
    icone.setVisible(true);
  }

  @override
  void onWindowClose() => windowManager.hide();

  // --- Notifications et premier plan --------------------------------------------------------

  static Future<void> notifier(String titre, String texte) async {
    if (_instance == null) return;
    await _essayer(() => LocalNotification(title: titre, body: texte).show());
  }

  /// C2 : afficher un post-it au-dessus des autres fenêtres, sur demande, propre à cet ordinateur.
  static Future<void> basculerPremierPlan(bool actif) async {
    if (_instance == null) return;
    _premierPlan = actif;
    await windowManager.setAlwaysOnTop(_premierPlan);
  }
}
