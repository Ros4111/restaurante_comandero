// lib/screens/mesas_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/catalogo_provider.dart';
import '../utils/theme.dart';
import 'hacer_pedido_screen.dart';
import 'login_screen.dart';
import 'settings_menu_screen.dart';

class MesasScreen extends StatefulWidget {
  const MesasScreen({super.key});
  @override
  State<MesasScreen> createState() => _MesasScreenState();
}

class _MesasScreenState extends State<MesasScreen> {
  static const Duration _lockTtl = Duration(minutes: 3);
  static final RegExp _reMysqlDatetime = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[\sT]+(\d{1,2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?$',
  );
  List<MesaResumen> _mesas = [];
  bool _loading = true;
  bool _fabVisible = true;
  Timer? _refreshTimer;
  String _version = '';
  String? _terminalSerie;

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarVersion();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => _cargar());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _cargarVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _version = 'v${info.version}');
  }

  Future<void> _cargar() async {
    final api = context.read<ApiService>();
    final sesion = context.read<SesionProvider>();
    try {
      _terminalSerie ??= await api.terminalSerie();
      final mesas = await api.getMesas();
      final now = DateTime.now();
      final ahora = DateTime(
          now.year, now.month, now.day, now.hour, now.minute, now.second);

      final lista = mesas.map((m) {
        final bloqueoVigente = _bloqueoVigente(m.horaBloqueo, ahora) &&
            (m.terminalSerieBloqueo ?? '').isNotEmpty;
        final terminalBloqueo = bloqueoVigente ? m.terminalSerieBloqueo : null;
        return MesaResumen(
          idPedido: m.idPedido,
          idMesa: m.idMesa,
          estado: m.estado,
          idUsuarioBloqueo: m.idUsuarioBloqueo,
          nombreUsuarioBloqueo: bloqueoVigente
              ? (sesion.nombreUsuario(m.idUsuarioBloqueo) ??
                  m.nombreUsuarioBloqueo)
              : null,
          horaBloqueo: m.horaBloqueo,
          terminalSerieBloqueo: terminalBloqueo,
          nombreCliente: m.nombreCliente,
          horaCreacion: m.horaCreacion,
          horaUltimaAccion: m.horaUltimaAccion,
          totalLineas: m.totalLineas,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _mesas = lista;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _bloqueoVigente(String? horaBloqueo, DateTime ahora) {
    if (horaBloqueo == null || horaBloqueo.trim().isEmpty) return false;
    final raw = horaBloqueo.trim();
    DateTime? parsed;

    // Formato MySQL típico: yyyy-MM-dd HH:mm:ss(.uuuuuu)
    final mysqlMatch = _reMysqlDatetime.firstMatch(raw);
    if (mysqlMatch != null) {
      final y = int.parse(mysqlMatch.group(1)!);
      final mo = int.parse(mysqlMatch.group(2)!);
      final d = int.parse(mysqlMatch.group(3)!);
      final h = int.parse(mysqlMatch.group(4)!);
      final mi = int.parse(mysqlMatch.group(5)!);
      final s = int.parse(mysqlMatch.group(6)!);
      final frac = mysqlMatch.group(7);
      final ms = frac == null || frac.isEmpty
          ? 0
          : int.parse((frac.length >= 3
              ? frac.substring(0, 3)
              : frac.padRight(3, '0')));
      parsed = DateTime(y, mo, d, h, mi, s, ms);
    }

    // Fallback ISO-like parse.
    parsed ??= DateTime.tryParse(raw.replaceAll(' ', 'T'));
    if (parsed == null) {
      final onlyTime =
          RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(raw);
      if (onlyTime != null) {
        final h = int.parse(onlyTime.group(1)!);
        final m = int.parse(onlyTime.group(2)!);
        final s = int.tryParse(onlyTime.group(3) ?? '') ?? 0;
        parsed = DateTime(ahora.year, ahora.month, ahora.day, h, m, s);
      }
    }
    if (parsed == null) return false;
    if (parsed.isAfter(ahora)) {
      parsed = parsed.subtract(const Duration(days: 1));
    }
    return ahora.difference(parsed) < _lockTtl;
  }

  Future<void> _abrirMesa() async {
    final api = context.read<ApiService>();
    setState(() => _fabVisible = false);
    final numStr = await showDialog<String>(
      context: context,
      builder: (ctx) => const _AbrirMesaDialog(),
    );

    if (numStr == null || numStr.isEmpty) {
      if (mounted) setState(() => _fabVisible = true);
      return;
    }
    final num = int.tryParse(numStr);
    if (num == null || num <= 0) return;

    // Verificar si ya existe
    final existe = _mesas.where((m) => m.idMesa == num).firstOrNull;
    if (existe != null) {
      _entrarMesa(existe);
      return;
    }

    try {
      final idPedido = await api.abrirMesa(num);
      _navPedido(idPedido, num, bloqueadoPorMi: true);
    } catch (e) {
      if (mounted) setState(() => _fabVisible = true);
      _showError(e.toString());
    }
  }

  Future<void> _entrarMesa(MesaResumen mesa) async {
    final api = context.read<ApiService>();
    try {
      await api.bloquearMesa(mesa.idPedido);
      _navPedido(mesa.idPedido, mesa.idMesa, bloqueadoPorMi: true);
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        // Mesa bloqueada por otro: entrar en solo lectura
        _navPedido(mesa.idPedido, mesa.idMesa,
            bloqueadoPorMi: false, bloqueador: mesa.nombreUsuarioBloqueo);
      } else {
        _showError(e.toString());
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _navPedido(int idPedido, int idMesa,
      {required bool bloqueadoPorMi, String? bloqueador}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HacerPedidoScreen(
          idPedido: idPedido,
          idMesa: idMesa,
          bloqueadoPorMi: bloqueadoPorMi,
          bloqueador: bloqueador,
        ),
      ),
    ).then((_) {
      if (mounted) setState(() => _fabVisible = true);
      _cargar();
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red[700]));
  }

  void _logout() {
    context.read<SesionProvider>().logout();
    context.read<ApiService>().clearToken();
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final sesion = context.watch<SesionProvider>();
    final api = context.watch<ApiService>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Mesas · ${sesion.usuario?.nombre ?? ''}'),
        actions: [
          if (sesion.esAdmin)
            IconButton(
              tooltip: 'Configuración',
              icon: const Icon(Icons.settings),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SettingsMenuScreen(),
                ),
              ),
            ),
          // ── Versión ──────────────────────────────────────────
          if (_version.isNotEmpty)
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  _version,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _cargar),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
        bottom: api.serverReachable
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(30),
                child: Container(
                  color: Colors.red[900],
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.wifi_off, color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text('SERVIDOR INACCESIBLE',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ]),
                ),
              ),
      ),
      floatingActionButton: _fabVisible
          ? FloatingActionButton.extended(
              onPressed: _abrirMesa,
              icon: const Icon(Icons.add),
              label: const Text('Abrir Mesa'),
              backgroundColor: AppTheme.colorPrimario,
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _mesas.isEmpty
              ? const Center(
                  child: Text('No hay mesas abiertas',
                      style: TextStyle(
                          fontSize: 20, color: AppTheme.colorTextoGris)))
              : LayoutBuilder(
                  builder: (ctx, c) {
                    const spacing = 12.0;
                    final tileWidth = (c.maxWidth - 32 - (spacing * 2)) / 3;
                    final baseHeight = tileWidth / 1.1;
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: _mesas.map((m) {
                          final tieneNombre =
                              (m.nombreCliente ?? '').trim().isNotEmpty;
                          final tileHeight =
                              tieneNombre ? baseHeight + 22 : baseHeight;
                          return SizedBox(
                            width: tileWidth,
                            height: tileHeight,
                            child: _MesaTile(
                              mesa: m,
                              terminalSerieActual: _terminalSerie,
                              onTap: () => _entrarMesa(m),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
    );
  }
}

class _MesaTile extends StatelessWidget {
  final MesaResumen mesa;
  final String? terminalSerieActual;
  final VoidCallback onTap;

  const _MesaTile(
      {required this.mesa,
      required this.terminalSerieActual,
      required this.onTap});

  /// `yyyy-MM-dd` + espacio(s)/tab/`T` + hora (MySQL / API). Evita fallos con
  /// varios espacios entre fecha y hora (`tryParse` no lo admite).
  static final _reMysqlDatetime = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[\sT]+(\d{1,2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?$',
  );

  DateTime _dateTimeDesdeMatchMysql(RegExpMatch m) {
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    final h = int.parse(m.group(4)!);
    final mi = int.parse(m.group(5)!);
    final s = int.parse(m.group(6)!);
    var ms = 0;
    final frac = m.group(7);
    if (frac != null && frac.isNotEmpty) {
      final head =
          frac.length >= 3 ? frac.substring(0, 3) : frac.padRight(3, '0');
      ms = int.tryParse(head) ?? 0;
    }
    return DateTime(y, mo, d, h, mi, s, ms);
  }

  /// Fecha/hora local sin ajuste “futuro → día anterior” (para extraer día de creación).
  DateTime? _tryParseFechaHoraLocal(String trimmed) {
    final mm = _reMysqlDatetime.firstMatch(trimmed);
    if (mm != null) return _dateTimeDesdeMatchMysql(mm);
    final iso = trimmed.replaceFirstMapped(
      RegExp(r'^(\d{4}-\d{2}-\d{2})\s+'),
      (m) => '${m.group(1)}T',
    );
    return DateTime.tryParse(iso);
  }

  /// Día de calendario de [horaCreacion] para anclar `hora_ultima` tipo TIME (`HH:mm:ss`).
  DateTime? _diaCalendarioDesdeHoraCreacion(String? horaCreacion) {
    if (horaCreacion == null || horaCreacion.trim().isEmpty) return null;
    final dt = _tryParseFechaHoraLocal(horaCreacion.trim());
    if (dt == null) return null;
    return DateTime(dt.year, dt.month, dt.day);
  }

  /// Fecha/hora del servidor en instante local. Si queda en el futuro (p. ej. solo
  /// `HH:mm` mal anclada), retrocede días de calendario.
  DateTime? _parseInstanteMesa(
    String raw,
    DateTime ahora, {
    DateTime? diaAnclaParaSoloHora,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final desdeMysqlOIso = _tryParseFechaHoraLocal(trimmed);
    if (desdeMysqlOIso != null) {
      return _ajustarDiaSiQuedaEnFuturo(desdeMysqlOIso, ahora);
    }

    // Solo hora HH:mm o HH:mm:ss: si la API envía TIME sin fecha, usar el día de
    // `hora_creacion` (no el de “hoy”), para no desplazar ~24 h al cruzar medianoche.
    final soloHora =
        RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(trimmed);
    if (soloHora != null) {
      final ancla = diaAnclaParaSoloHora ?? ahora;
      final h = int.parse(soloHora.group(1)!);
      final m = int.parse(soloHora.group(2)!);
      final s = int.tryParse(soloHora.group(3) ?? '') ?? 0;
      final candidate = DateTime(ancla.year, ancla.month, ancla.day, h, m, s);
      return _ajustarDiaSiQuedaEnFuturo(candidate, ahora);
    }

    return null;
  }

  DateTime _ajustarDiaSiQuedaEnFuturo(DateTime parsed, DateTime ahora) {
    if (!parsed.isAfter(ahora)) return parsed;
    // Desfase breve de reloj (servidor/cliente): no interpretar como "día siguiente".
    if (parsed.difference(ahora) <= const Duration(minutes: 2)) {
      return ahora;
    }
    var d = parsed;
    for (var i = 0; i < 400 && d.isAfter(ahora); i++) {
      d = d.subtract(const Duration(days: 1));
    }
    return d;
  }

  String _minutosTexto(String? value, {DateTime? diaAnclaParaSoloHora}) {
    if (value == null || value.isEmpty) return '--';
    final ahora = DateTime.now();
    final parsed = _parseInstanteMesa(value, ahora,
        diaAnclaParaSoloHora: diaAnclaParaSoloHora);
    if (parsed == null) return '--';
    final mins = ahora.difference(parsed).inMinutes;
    if (mins > 999) return 'Mucho';
    if (mins < 0) return '0';
    return '$mins';
  }

  @override
  Widget build(BuildContext context) {
    final diaCreacion = _diaCalendarioDesdeHoraCreacion(mesa.horaCreacion);
    final serieBloqueo = (mesa.terminalSerieBloqueo ?? '').trim();
    final nombreCliente = (mesa.nombreCliente ?? '').trim();
    final bloqueadaPorOtro = serieBloqueo.isNotEmpty &&
        terminalSerieActual != null &&
        serieBloqueo != terminalSerieActual;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.colorTarjeta,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: bloqueadaPorOtro ? Colors.orange : AppTheme.colorPrimario,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${mesa.idMesa}',
                style:
                    const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
            //const SizedBox(height: 2),
            Text(mesa.estado,
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.colorTextoGris)),
            //const SizedBox(height: 2),
            Text(
                '${_minutosTexto(mesa.horaCreacion)} -- ${_minutosTexto(mesa.horaUltimaAccion, diaAnclaParaSoloHora: diaCreacion)}',
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.colorTextoGris)),
            if (nombreCliente.isNotEmpty)
              Text(
                nombreCliente,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.colorTextoGris),
              ),

            if (bloqueadaPorOtro) ...[
              const SizedBox(height: 2),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.lock, color: Colors.orange, size: 14),
                const SizedBox(width: 4),
                Text((mesa.nombreUsuarioBloqueo ?? serieBloqueo),
                    style: const TextStyle(color: Colors.orange, fontSize: 12)),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

class _AbrirMesaDialog extends StatefulWidget {
  const _AbrirMesaDialog();

  @override
  State<_AbrirMesaDialog> createState() => _AbrirMesaDialogState();
}

class _AbrirMesaDialogState extends State<_AbrirMesaDialog> {
  String _numero = '';

  void _tecla(String v) {
    if (_numero.length >= 4) return;
    setState(() => _numero += v);
  }

  void _borrar() {
    if (_numero.isEmpty) return;
    setState(() => _numero = _numero.substring(0, _numero.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = (screenWidth - 20).clamp(0.0, 400.0);
    final horizontalInset = ((screenWidth - dialogWidth) / 2).clamp(0.0, double.infinity);
    return AlertDialog(
      backgroundColor: AppTheme.colorTarjeta,
      contentPadding: const EdgeInsets.all(6),
      insetPadding: EdgeInsets.symmetric(horizontal: horizontalInset, vertical: 24),
      title: const Text('Número de mesa'),
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.colorSuperficie,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                _numero.isEmpty ? 'Introduce numero' : _numero,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  letterSpacing: _numero.isEmpty ? 0 : 3,
                  color:
                      _numero.isEmpty ? AppTheme.colorTextoGris : Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 240,
              child: _TecladoMesa(
                onTecla: _tecla,
                onBorrar: _borrar,
                onOk: _numero.isNotEmpty
                    ? () => Navigator.pop(context, _numero)
                    : null,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

class _TecladoMesa extends StatelessWidget {
  final void Function(String) onTecla;
  final VoidCallback onBorrar;
  final VoidCallback? onOk;

  const _TecladoMesa({
    required this.onTecla,
    required this.onBorrar,
    required this.onOk,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _fila(['1', '2', '3']),
        _fila(['4', '5', '6']),
        _fila(['7', '8', '9']),
        _filaEspecial(),
      ],
    );
  }

  Widget _fila(List<String> nums) {
    return Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: nums
            .map(
              (n) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: _BotonNumMesa(label: n, onTap: () => onTecla(n)),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _filaEspecial() {
    return Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: _BotonAccionMesa(
                color: const Color(0xFF333333),
                onTap: onBorrar,
                child: const Icon(Icons.backspace_outlined,
                    color: Colors.white70, size: 24),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: _BotonNumMesa(label: '0', onTap: () => onTecla('0')),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: _BotonAccionMesa(
                color: onOk != null
                    ? AppTheme.colorPrimario
                    : AppTheme.colorPrimario.withValues(alpha: 0.35),
                onTap: onOk,
                child: const Text(
                  'OK',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BotonNumMesa extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _BotonNumMesa({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF2A2A2A),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
                color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}

class _BotonAccionMesa extends StatelessWidget {
  final Widget child;
  final Color color;
  final VoidCallback? onTap;

  const _BotonAccionMesa(
      {required this.child, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Center(child: child),
      ),
    );
  }
}
