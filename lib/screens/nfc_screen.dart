// lib/screens/nfc_screen.dart
import 'dart:math' show min;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart'
    show IsoDepAndroid, NdefAndroid, NfcTagAndroid;

import '../utils/theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Modelos
// ═══════════════════════════════════════════════════════════════════════════

class EmvCardData {
  final String? aid;
  final String? networkName;
  final String? appLabel;
  final String? cardholderName;
  final String? panMasked;
  final String? expiryFormatted;
  final String? atc;

  const EmvCardData({
    this.aid,
    this.networkName,
    this.appLabel,
    this.cardholderName,
    this.panMasked,
    this.expiryFormatted,
    this.atc,
  });

  bool get tieneAlgunDato =>
      panMasked != null ||
      cardholderName != null ||
      expiryFormatted != null ||
      appLabel != null;
}

// ═══════════════════════════════════════════════════════════════════════════
// Parser TLV (BER-TLV, ISO 7816-4)
// ═══════════════════════════════════════════════════════════════════════════

class _Tlv {
  /// Devuelve todos los valores del [targetTag] encontrados en [data],
  /// incluyendo dentro de templates construidos (recursivo).
  static List<Uint8List> findAll(Uint8List data, int targetTag) {
    final out = <Uint8List>[];
    _scan(data, targetTag, out);
    return out;
  }

  static void _scan(Uint8List data, int targetTag, List<Uint8List> out) {
    int i = 0;
    while (i < data.length) {
      // ── Tag ────────────────────────────────────────
      int b = data[i] & 0xFF;
      final isConstructed = (b & 0x20) != 0;
      int tag = b;
      i++;
      if ((tag & 0x1F) == 0x1F) {
        while (i < data.length) {
          b = data[i] & 0xFF;
          tag = (tag << 8) | b;
          i++;
          if ((b & 0x80) == 0) break;
        }
      }
      if (i >= data.length) break;

      // ── Length ─────────────────────────────────────
      final lb = data[i] & 0xFF;
      i++;
      int length;
      if (lb <= 0x7F) {
        length = lb;
      } else {
        final numBytes = lb & 0x7F;
        length = 0;
        for (int j = 0; j < numBytes && i < data.length; j++) {
          length = (length << 8) | (data[i] & 0xFF);
          i++;
        }
      }
      if (i + length > data.length) break;

      // ── Value ──────────────────────────────────────
      final value = data.sublist(i, i + length);
      if (tag == targetTag) out.add(value);
      if (isConstructed) _scan(value, targetTag, out);
      i += length;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Lector EMV (APDUs ISO 7816-4 / EMV 4.4)
// ═══════════════════════════════════════════════════════════════════════════

class _Emv {
  // PPSE: "2PAY.SYS.DDF01"
  static const _ppse = [
    0x32, 0x50, 0x41, 0x59, 0x2E, 0x53, 0x59, 0x53,
    0x2E, 0x44, 0x44, 0x46, 0x30, 0x31,
  ];

  // AIDs a probar si el PPSE no responde
  static const _fallbackAids = [
    [0xA0, 0x00, 0x00, 0x00, 0x03, 0x10, 0x10], // Visa
    [0xA0, 0x00, 0x00, 0x00, 0x04, 0x10, 0x10], // Mastercard
    [0xA0, 0x00, 0x00, 0x00, 0x25, 0x01, 0x00], // Amex
    [0xA0, 0x00, 0x00, 0x00, 0x04, 0x30, 0x60], // Maestro
    [0xA0, 0x00, 0x00, 0x00, 0x65, 0x10, 0x10], // JCB
  ];

  // ── APDUs ───────────────────────────────────────────────────────────────

  static Uint8List _select(List<int> name) => Uint8List.fromList(
      [0x00, 0xA4, 0x04, 0x00, name.length, ...name, 0x00]);

  static Uint8List _readRecord(int sfi, int rec) =>
      Uint8List.fromList([0x00, 0xB2, rec, (sfi << 3) | 0x04, 0x00]);

  // GPO con PDOL vacío
  static final _gpo =
      Uint8List.fromList([0x80, 0xA8, 0x00, 0x00, 0x02, 0x83, 0x00, 0x00]);

  // ── Transceive + SW handling ────────────────────────────────────────────

  static bool _swOk(Uint8List r) =>
      r.length >= 2 && r[r.length - 2] == 0x90 && r[r.length - 1] == 0x00;

  static Uint8List _body(Uint8List r) => r.sublist(0, r.length - 2);

  static Future<Uint8List> _send(IsoDepAndroid iso, Uint8List apdu) async {
    var bytes = await iso.transceive(apdu);

    // SW 61 XX → enviar GET RESPONSE
    if (bytes.length >= 2 && bytes[bytes.length - 2] == 0x61) {
      final le = bytes[bytes.length - 1];
      bytes = await iso.transceive(
          Uint8List.fromList([0x00, 0xC0, 0x00, 0x00, le]));
    }
    return bytes;
  }

  // ── Helpers de decodificación ───────────────────────────────────────────

  static String _hexFromBytes(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();

  /// BCD a string hexadecimal (nibble F = padding, se omite).
  static String? _bcd(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      final hi = (b >> 4) & 0xF;
      final lo = b & 0xF;
      sb.write(hi.toRadixString(16));
      if (lo != 0xF) sb.write(lo.toRadixString(16));
    }
    final s = sb.toString().toUpperCase();
    return s.isEmpty ? null : s;
  }

  /// 5F24: YYMMDD → "MM/YY"
  static String? _expiry(Uint8List bytes) {
    if (bytes.length < 3) return null;
    final yy = bytes[0].toRadixString(16).padLeft(2, '0');
    final mm = bytes[1].toRadixString(16).padLeft(2, '0');
    return '$mm/$yy';
  }

  /// Enmascara el PAN mostrando solo los últimos 4 dígitos.
  static String _maskPan(String pan) {
    if (pan.length < 4) return pan;
    final last4 = pan.substring(pan.length - 4);
    final masked = List.filled(pan.length - 4, '*').join();
    final full = masked + last4;
    final groups = <String>[];
    for (int i = 0; i < full.length; i += 4) {
      groups.add(full.substring(i, min(i + 4, full.length)));
    }
    return groups.join(' ');
  }

  /// Detecta la red de pago a partir del AID.
  static String _network(List<int> aid) {
    final h = _hexFromBytes(aid);
    if (h.startsWith('A000000003')) return 'Visa';
    if (h.startsWith('A000000004')) {
      return h.startsWith('A0000000043') ? 'Maestro' : 'Mastercard';
    }
    if (h.startsWith('A000000025')) return 'American Express';
    if (h.startsWith('A000000065')) return 'JCB';
    if (h.startsWith('A000000152')) return 'Discover';
    return 'Desconocida';
  }

  /// Extrae PAN, fecha expiración y nombre del titular de los bytes de un record.
  static ({String? pan, String? expiry, String? name, String? atc})
      _extractFields(Uint8List data) {
    String? pan;
    String? expiry;
    String? name;
    String? atc;

    // 5A → PAN (BCD)
    final pans = _Tlv.findAll(data, 0x5A);
    if (pans.isNotEmpty) pan = _bcd(pans.first);

    // 5F20 → Nombre titular
    final names = _Tlv.findAll(data, 0x5F20);
    if (names.isNotEmpty) {
      name = String.fromCharCodes(names.first).trim();
    }

    // 5F24 → Fecha expiración
    final expiries = _Tlv.findAll(data, 0x5F24);
    if (expiries.isNotEmpty) expiry = _expiry(expiries.first);

    // 57 → Track 2 Equivalent Data (PAN + expiración, fallback)
    if (pan == null || expiry == null) {
      final tracks = _Tlv.findAll(data, 0x57);
      if (tracks.isNotEmpty) {
        final hex = _bcd(tracks.first) ?? '';
        final sep = hex.indexOf('D');
        if (sep > 0) {
          pan ??= hex.substring(0, sep);
          if (hex.length >= sep + 5) {
            final yy = hex.substring(sep + 1, sep + 3);
            final mm = hex.substring(sep + 3, sep + 5);
            expiry ??= '$mm/$yy';
          }
        }
      }
    }

    // 9F36 → ATC (contador de transacciones)
    final atcs = _Tlv.findAll(data, 0x9F36);
    if (atcs.isNotEmpty) atc = _hexFromBytes(atcs.first);

    return (pan: pan, expiry: expiry, name: name, atc: atc);
  }

  // ── Lectura completa ─────────────────────────────────────────────────────

  static Future<EmvCardData> read(IsoDepAndroid isoDep) async {
    String? aid;
    String? networkName;
    String? appLabel;
    String? pan;
    String? expiry;
    String? cardholderName;
    String? atc;

    // ── 1. SELECT PPSE ───────────────────────────────────
    List<List<int>> aidList = [];
    try {
      final ppseResp = await _send(isoDep, _select(_ppse));
      if (_swOk(ppseResp)) {
        aidList = _Tlv.findAll(_body(ppseResp), 0x4F)
            .map((b) => b.toList())
            .toList();
      }
    } catch (_) {}

    if (aidList.isEmpty) aidList = _fallbackAids;

    // ── 2. SELECT AID ────────────────────────────────────
    for (final aidBytes in aidList) {
      try {
        final selResp = await _send(isoDep, _select(aidBytes));
        if (_swOk(selResp)) {
          aid = _hexFromBytes(aidBytes);
          networkName = _network(aidBytes);
          final labels = _Tlv.findAll(_body(selResp), 0x50);
          if (labels.isNotEmpty) {
            appLabel = String.fromCharCodes(labels.first).trim();
          }
          break;
        }
      } catch (_) {}
    }

    // ── 3. GET PROCESSING OPTIONS ────────────────────────
    List<int>? aflBytes;
    try {
      final gpoResp = await _send(isoDep, _gpo);
      if (_swOk(gpoResp)) {
        final d = _body(gpoResp);
        // Formato 2 (template 77): buscar tag 94 (AFL)
        final afls = _Tlv.findAll(d, 0x94);
        if (afls.isNotEmpty) {
          aflBytes = afls.first.toList();
        } else {
          // Formato 1 (tag 80): AIP (2 bytes) + AFL
          final fmt1 = _Tlv.findAll(d, 0x80);
          if (fmt1.isNotEmpty && fmt1.first.length > 2) {
            aflBytes = fmt1.first.sublist(2).toList();
          }
        }
      }
    } catch (_) {}

    // ── 4. READ RECORDS ──────────────────────────────────
    Future<void> tryRecord(int sfi, int rec) async {
      if (pan != null && expiry != null && cardholderName != null) return;
      try {
        final rResp = await _send(isoDep, _readRecord(sfi, rec));
        if (!_swOk(rResp)) return;
        final fields = _extractFields(_body(rResp));
        pan ??= fields.pan;
        expiry ??= fields.expiry;
        cardholderName ??= fields.name;
        atc ??= fields.atc;
      } catch (_) {}
    }

    if (aflBytes != null && aflBytes.length >= 4) {
      // AFL válido → leer solo los records indicados
      for (int i = 0; i + 3 < aflBytes.length; i += 4) {
        final sfi = (aflBytes[i] >> 3) & 0x1F;
        final first = aflBytes[i + 1];
        final last = aflBytes[i + 2];
        for (int r = first; r <= last; r++) {
          await tryRecord(sfi, r);
        }
      }
    } else {
      // Sin AFL → fuerza bruta en ubicaciones habituales
      for (int sfi = 1; sfi <= 4; sfi++) {
        for (int rec = 1; rec <= 6; rec++) {
          await tryRecord(sfi, rec);
        }
      }
    }

    return EmvCardData(
      aid: aid,
      networkName: networkName,
      appLabel: appLabel,
      panMasked: pan != null ? _maskPan(pan!) : null,
      expiryFormatted: expiry,
      cardholderName: cardholderName,
      atc: atc,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Pantalla
// ═══════════════════════════════════════════════════════════════════════════

enum _Estado { comprobando, esperando, leyendoEmv, leido, noDisponible, error }

class NfcScreen extends StatefulWidget {
  const NfcScreen({super.key});

  @override
  State<NfcScreen> createState() => _NfcScreenState();
}

class _NfcScreenState extends State<NfcScreen>
    with SingleTickerProviderStateMixin {
  _Estado _estado = _Estado.comprobando;
  String? _error;

  // Resultado NFC básico
  String? _idHex;
  String? _tipoTag;
  List<String> _registrosNdef = [];

  // Resultado EMV
  EmvCardData? _emvData;

  late AnimationController _pulsoCtrl;
  late Animation<double> _pulsoAnim;

  @override
  void initState() {
    super.initState();
    _pulsoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulsoAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulsoCtrl, curve: Curves.easeInOut),
    );
    _iniciar();
  }

  @override
  void dispose() {
    _pulsoCtrl.dispose();
    NfcManager.instance.stopSession().catchError((_) {});
    super.dispose();
  }

  // ── NFC ──────────────────────────────────────────────────────────────────

  Future<void> _iniciar() async {
    if (kIsWeb) {
      if (mounted) {
        setState(() {
          _estado = _Estado.noDisponible;
          _error = 'NFC no está disponible en navegadores web.';
        });
      }
      return;
    }

    try {
      final avail = await NfcManager.instance.checkAvailability();
      if (avail != NfcAvailability.enabled) {
        if (mounted) {
          setState(() {
            _estado = _Estado.noDisponible;
            _error = avail == NfcAvailability.disabled
                ? 'NFC está desactivado.\nActívalo en Ajustes → Conexiones → NFC.'
                : 'Este dispositivo no tiene NFC.';
          });
        }
        return;
      }

      if (mounted) setState(() => _estado = _Estado.esperando);

      await NfcManager.instance.startSession(
        pollingOptions: {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
        },
        onDiscovered: (NfcTag tag) async {
          try {
            await _procesarTag(tag);
          } catch (e) {
            await NfcManager.instance.stopSession();
            if (mounted) {
              setState(() {
                _estado = _Estado.error;
                _error = e.toString();
              });
            }
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _estado = _Estado.error;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _procesarTag(NfcTag tag) async {
    final isoDep = IsoDepAndroid.from(tag);

    if (isoDep != null) {
      // ── Tarjeta con chip ISO-DEP → intentar lectura EMV ─────────────
      if (mounted) setState(() => _estado = _Estado.leyendoEmv);

      final emvData = await _Emv.read(isoDep);
      await NfcManager.instance.stopSession();

      if (mounted) {
        setState(() {
          _emvData = emvData;
          _estado = _Estado.leido;
        });
      }
    } else {
      // ── Tag NFC genérico ─────────────────────────────────────────────
      final tagAndroid = NfcTagAndroid.from(tag);
      final idBytes = tagAndroid?.id;

      final idHex = idBytes
          ?.map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(':')
          .toUpperCase();

      String tipo = 'Desconocido';
      if (tagAndroid != null && tagAndroid.techList.isNotEmpty) {
        tipo =
            tagAndroid.techList.map((t) => t.split('.').last).join(', ');
      }

      // Registros NDEF
      final registros = <String>[];
      final ndef = NdefAndroid.from(tag);
      if (ndef != null) {
        for (final record in ndef.cachedNdefMessage?.records ?? []) {
          final payload = record.payload;
          if (payload.isEmpty) continue;
          try {
            final langLen = payload[0] & 0x3F;
            registros.add(String.fromCharCodes(payload.sublist(1 + langLen)));
          } catch (_) {
            registros.add(
                payload.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' '));
          }
        }
      }

      await NfcManager.instance.stopSession();

      if (mounted) {
        setState(() {
          _idHex = idHex;
          _tipoTag = tipo;
          _registrosNdef = registros;
          _emvData = null;
          _estado = _Estado.leido;
        });
      }
    }
  }

  void _reiniciar() {
    setState(() {
      _estado = _Estado.comprobando;
      _error = null;
      _idHex = null;
      _tipoTag = null;
      _registrosNdef = [];
      _emvData = null;
    });
    _iniciar();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lector NFC')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: _buildCuerpo(),
        ),
      ),
    );
  }

  Widget _buildCuerpo() {
    switch (_estado) {
      case _Estado.comprobando:
        return const _LoadingPanel(mensaje: 'Comprobando NFC…');
      case _Estado.esperando:
        return _buildEsperando();
      case _Estado.leyendoEmv:
        return const _LoadingPanel(
          mensaje: 'Leyendo tarjeta…\nNo la retires',
          icon: Icons.credit_card,
        );
      case _Estado.leido:
        return _emvData != null ? _buildEmvLeido() : _buildNfcLeido();
      case _Estado.noDisponible:
      case _Estado.error:
        return _buildError();
    }
  }

  // ── Estado: esperando ────────────────────────────────────────────────────

  Widget _buildEsperando() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Pasa tu tarjeta',
          style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppTheme.colorTexto),
        ),
        const SizedBox(height: 40),
        ScaleTransition(
          scale: _pulsoAnim,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.colorPrimario.withAlpha(25),
              border: Border.all(
                  color: AppTheme.colorPrimario.withAlpha(120), width: 2),
            ),
            child: const Icon(Icons.contactless_outlined,
                size: 90, color: AppTheme.colorPrimario),
          ),
        ),
        const SizedBox(height: 32),
        const Text(
          'Acerca una tarjeta bancaria, llavero\no cualquier tag NFC al lector',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.colorTextoGris, fontSize: 15),
        ),
      ],
    );
  }

  // ── Estado: leído EMV ────────────────────────────────────────────────────

  Widget _buildEmvLeido() {
    final d = _emvData!;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icono de éxito
          const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
          const SizedBox(height: 12),
          const Text(
            'Tarjeta leída',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.green),
          ),
          const SizedBox(height: 20),

          // Tarjeta visual
          _EmvCardWidget(data: d),
          const SizedBox(height: 16),

          // Detalles técnicos
          if (d.aid != null || d.atc != null)
            _InfoCard(children: [
              const Text(
                'Datos técnicos',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.colorTextoGris),
              ),
              const SizedBox(height: 8),
              if (d.aid != null)
                _InfoRow(label: 'AID', valor: d.aid!),
              if (d.atc != null)
                _InfoRow(label: 'ATC', valor: d.atc!),
            ]),

          if (!d.tieneAlgunDato) ...[
            const SizedBox(height: 8),
            const Text(
              'La tarjeta no expone datos de titular.\nEsto es normal en tarjetas modernas.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppTheme.colorTextoGris, fontSize: 13),
            ),
          ],

          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _reiniciar,
            icon: const Icon(Icons.refresh),
            label: const Text('Leer otra tarjeta'),
          ),
        ],
      ),
    );
  }

  // ── Estado: leído NFC básico ─────────────────────────────────────────────

  Widget _buildNfcLeido() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
          const SizedBox(height: 12),
          const Text(
            'Tag NFC leído',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.green),
          ),
          const SizedBox(height: 20),
          _InfoCard(children: [
            if (_idHex != null) ...[
              _InfoRow(label: 'ID', valor: _idHex!),
              const Divider(height: 16),
            ],
            _InfoRow(label: 'Tipo', valor: _tipoTag ?? 'Desconocido'),
            if (_registrosNdef.isNotEmpty) ...[
              const Divider(height: 16),
              const Text('Registros NDEF',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.colorTextoGris,
                      fontSize: 13)),
              const SizedBox(height: 6),
              for (final r in _registrosNdef)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(r,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 14)),
                ),
            ],
          ]),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _reiniciar,
            icon: const Icon(Icons.refresh),
            label: const Text('Leer otro tag'),
          ),
        ],
      ),
    );
  }

  // ── Estado: error / no disponible ───────────────────────────────────────

  Widget _buildError() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _estado == _Estado.noDisponible
              ? Icons.nfc_outlined
              : Icons.error_outline,
          size: 64,
          color: AppTheme.colorAcento,
        ),
        const SizedBox(height: 16),
        Text(
          _estado == _Estado.noDisponible ? 'NFC no disponible' : 'Error',
          style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.colorAcento),
        ),
        const SizedBox(height: 12),
        Text(
          _error ?? 'Error desconocido',
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: AppTheme.colorTextoGris, fontSize: 15),
        ),
        if (_estado == _Estado.error) ...[
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _reiniciar,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Widgets auxiliares
// ═══════════════════════════════════════════════════════════════════════════

/// Panel de carga genérico.
class _LoadingPanel extends StatelessWidget {
  final String mensaje;
  final IconData icon;

  const _LoadingPanel({
    required this.mensaje,
    this.icon = Icons.hourglass_empty,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        Text(
          mensaje,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, color: AppTheme.colorTextoGris),
        ),
      ],
    );
  }
}

/// Tarjeta visual estilo "card" con los datos EMV.
class _EmvCardWidget extends StatelessWidget {
  final EmvCardData data;

  const _EmvCardWidget({required this.data});

  Color get _networkColor {
    switch (data.networkName) {
      case 'Visa':
        return const Color(0xFF1A1F71);
      case 'Mastercard':
      case 'Maestro':
        return const Color(0xFF252525);
      case 'American Express':
        return const Color(0xFF007CC3);
      default:
        return AppTheme.colorTarjeta;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 380),
      height: 210,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _networkColor,
            _networkColor.withAlpha(180),
            const Color(0xFF1C1C1C),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(100),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Red de pago
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  data.networkName ?? '',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2),
                ),
                const Icon(Icons.contactless, color: Colors.white54, size: 28),
              ],
            ),
            if (data.appLabel != null)
              Text(
                data.appLabel!,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            const Spacer(),

            // PAN
            Text(
              data.panMasked ?? '•••• •••• •••• ••••',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2.5,
                  fontFamily: 'monospace'),
            ),
            const SizedBox(height: 16),

            // Titular y expiración
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TITULAR',
                        style: TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                            letterSpacing: 1)),
                    Text(
                      data.cardholderName ?? '—',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                if (data.expiryFormatted != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('CADUCA',
                          style: TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
                              letterSpacing: 1)),
                      Text(
                        data.expiryFormatted!,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.colorTarjeta,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String valor;
  const _InfoRow({required this.label, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(label,
                style: const TextStyle(
                    color: AppTheme.colorTextoGris,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(valor,
                style:
                    const TextStyle(fontFamily: 'monospace', fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
