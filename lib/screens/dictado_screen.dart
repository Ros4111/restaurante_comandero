// lib/screens/dictado_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../utils/theme.dart';

class DictadoScreen extends StatefulWidget {
  const DictadoScreen({super.key});

  @override
  State<DictadoScreen> createState() => _DictadoScreenState();
}

class _DictadoScreenState extends State<DictadoScreen>
    with SingleTickerProviderStateMixin {
  final SpeechToText _speech = SpeechToText();
  final ScrollController _scrollCtrl = ScrollController();

  bool _disponible = false;
  bool _escuchando = false;
  bool _inicializando = true;
  String _textoActual = '';
  String _textoConfirmado = '';
  String? _error;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _inicializar();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _scrollCtrl.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _inicializar() async {
    setState(() {
      _inicializando = true;
      _error = null;
    });
    try {
      final ok = await _speech.initialize(
        onError: (e) {
          if (mounted) {
            setState(() {
              _escuchando = false;
              _error = e.errorMsg;
            });
            _pulseCtrl.stop();
          }
        },
        onStatus: (status) {
          if (status == SpeechToText.doneStatus ||
              status == SpeechToText.notListeningStatus) {
            if (mounted) setState(() => _escuchando = false);
            _pulseCtrl.stop();
          }
        },
      );
      if (mounted) setState(() => _disponible = ok);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _inicializando = false);
    }
  }

  Future<void> _toggleGrabar() async {
    if (_escuchando) {
      await _speech.stop();
      _pulseCtrl.stop();
      setState(() => _escuchando = false);
      return;
    }

    setState(() {
      _error = null;
      _textoActual = '';
    });

    await _speech.listen(
      onResult: _onResultado,
      localeId: 'es_ES',
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        cancelOnError: false,
        partialResults: true,
      ),
    );
    if (mounted) setState(() => _escuchando = true);
    _pulseCtrl.repeat(reverse: true);
  }

  void _onResultado(SpeechRecognitionResult result) {
    if (!mounted) return;
    setState(() {
      _textoActual = result.recognizedWords;
      if (result.finalResult) {
        if (_textoActual.isNotEmpty) {
          _textoConfirmado +=
              (_textoConfirmado.isEmpty ? '' : ' ') + _textoActual;
        }
        _textoActual = '';
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _limpiar() {
    setState(() {
      _textoConfirmado = '';
      _textoActual = '';
      _error = null;
    });
  }

  void _copiar() {
    final texto = _textoTotal.trim();
    if (texto.isEmpty) return;
    Clipboard.setData(ClipboardData(text: texto));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Texto copiado al portapapeles')),
    );
  }

  String get _textoTotal =>
      _textoConfirmado +
      (_textoConfirmado.isNotEmpty && _textoActual.isNotEmpty ? ' ' : '') +
      _textoActual;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dictado'),
        actions: [
          if (_textoTotal.isNotEmpty) ...[
            IconButton(
              tooltip: 'Copiar texto',
              icon: const Icon(Icons.copy_outlined),
              onPressed: _copiar,
            ),
            IconButton(
              tooltip: 'Limpiar',
              icon: const Icon(Icons.delete_outline),
              onPressed: _limpiar,
            ),
          ],
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Expanded(child: _buildAreaTexto()),
                const SizedBox(height: 24),
                if (_error != null) _buildError(),
                if (_inicializando)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: CircularProgressIndicator(),
                  )
                else
                  _buildBotonGrabar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAreaTexto() {
    final sinTexto = _textoTotal.trim().isEmpty;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.colorSuperficie,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _escuchando
              ? AppTheme.colorPrimario.withValues(alpha: 0.8)
              : Colors.white12,
          width: _escuchando ? 2 : 1,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: sinTexto
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mic_none,
                      size: 48,
                      color: AppTheme.colorTextoGris.withValues(alpha: 0.5)),
                  const SizedBox(height: 8),
                  Text(
                    _disponible
                        ? 'Pulsa Grabar y habla'
                        : 'Reconocimiento de voz no disponible',
                    style: TextStyle(
                      color: AppTheme.colorTextoGris.withValues(alpha: 0.7),
                      fontSize: 15,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              controller: _scrollCtrl,
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: _textoConfirmado,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 17, height: 1.5),
                    ),
                    if (_textoActual.isNotEmpty) ...[
                      if (_textoConfirmado.isNotEmpty)
                        const TextSpan(text: ' '),
                      TextSpan(
                        text: _textoActual,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 17,
                          height: 1.5,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.red[900]!.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: AppTheme.colorAcento.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline,
                color: AppTheme.colorAcento, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _error!,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: _inicializar,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBotonGrabar() {
    if (!_disponible) {
      return OutlinedButton.icon(
        onPressed: _inicializar,
        icon: const Icon(Icons.refresh),
        label: const Text('Reintentar inicialización'),
      );
    }

    final boton = SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: _toggleGrabar,
        icon: Icon(_escuchando ? Icons.stop_circle_outlined : Icons.mic),
        label: Text(
          _escuchando ? 'Detener' : 'Grabar',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _escuchando
              ? Colors.red[800]
              : AppTheme.colorPrimario,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );

    if (!_escuchando) return boton;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _pulseAnim,
              child: const Icon(Icons.fiber_manual_record,
                  color: Colors.red, size: 14),
            ),
            const SizedBox(width: 6),
            const Text(
              'Escuchando…',
              style: TextStyle(
                  color: AppTheme.colorTextoGris, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 10),
        boton,
      ],
    );
  }
}
