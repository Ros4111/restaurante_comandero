import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../utils/theme.dart';

class UsuariosCrudScreen extends StatefulWidget {
  const UsuariosCrudScreen({super.key});

  @override
  State<UsuariosCrudScreen> createState() => _UsuariosCrudScreenState();
}

class _UsuariosCrudScreenState extends State<UsuariosCrudScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _usuarios = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final api = context.read<ApiService>();
      final lista = await api.getUsuariosAdmin();
      if (!mounted) return;
      setState(() => _usuarios = lista);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red[700]),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _crear() async {
    final api = context.read<ApiService>();
    final form = await _showUsuarioDialog();
    if (form == null) return;
    await api.crearUsuarioAdmin(form);
    await _cargar();
  }

  Future<void> _editar(Map<String, dynamic> u) async {
    final api = context.read<ApiService>();
    final form = await _showUsuarioDialog(usuario: u);
    if (form == null) return;
    await api.actualizarUsuarioAdmin(
        int.parse(u['id_usuario'].toString()), form);
    await _cargar();
  }

  Future<void> _eliminar(Map<String, dynamic> u) async {
    final api = context.read<ApiService>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar usuario'),
        content: Text('¿Desactivar "${u['nombre_usuario']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await api.eliminarUsuarioAdmin(int.parse(u['id_usuario'].toString()));
    await _cargar();
  }

  Future<Map<String, dynamic>?> _showUsuarioDialog(
      {Map<String, dynamic>? usuario}) async {
    final nombreCtrl = TextEditingController(
      text: usuario?['nombre_usuario']?.toString() ?? '',
    );
    final passCtrl = TextEditingController();
    final ordenCtrl = TextEditingController(
      text: (usuario?['orden'] ?? 0).toString(),
    );
    String permisos = usuario?['permisos']?.toString() ?? 'camarero';
    bool activo = (usuario?['activo']?.toString() ?? '1') == '1';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(usuario == null ? 'Nuevo usuario' : 'Editar usuario'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passCtrl,
                  decoration: InputDecoration(
                    labelText: usuario == null
                        ? 'Contraseña'
                        : 'Nueva contraseña (opcional)',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: ordenCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Orden'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: permisos,
                  items: const [
                    DropdownMenuItem(
                        value: 'camarero', child: Text('Camarero')),
                    DropdownMenuItem(
                        value: 'supervisor', child: Text('Supervisor')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  ],
                  onChanged: (v) {
                    if (v != null) setLocal(() => permisos = v);
                  },
                  decoration: const InputDecoration(labelText: 'Permisos'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activo'),
                  value: activo,
                  onChanged: (v) => setLocal(() => activo = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final nombre = nombreCtrl.text.trim();
                final password = passCtrl.text;
                final orden = int.tryParse(ordenCtrl.text.trim()) ?? 0;
                if (nombre.isEmpty) return;
                if (usuario == null && password.isEmpty) return;
                final payload = <String, dynamic>{
                  'nombre_usuario': nombre,
                  'permisos': permisos,
                  'orden': orden,
                  'activo': activo ? 1 : 0,
                };
                if (password.isNotEmpty) {
                  payload['password'] = password;
                }
                Navigator.pop(ctx, payload);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    nombreCtrl.dispose();
    passCtrl.dispose();
    ordenCtrl.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CRUD Usuarios'),
        actions: [
          IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _crear,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Nuevo'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _usuarios.isEmpty
              ? const Center(
                  child: Text('Sin usuarios',
                      style: TextStyle(color: AppTheme.colorTextoGris)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _usuarios.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final u = _usuarios[i];
                    final activo = (u['activo']?.toString() ?? '1') == '1';
                    return Container(
                      decoration: BoxDecoration(
                        color: AppTheme.colorTarjeta,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: activo
                              ? Colors.white12
                              : Colors.red.withValues(alpha: 0.35),
                        ),
                      ),
                      child: ListTile(
                        title: Text(
                          '${u['nombre_usuario']} (${u['permisos']})',
                          style: TextStyle(
                            color:
                                activo ? Colors.white : AppTheme.colorTextoGris,
                          ),
                        ),
                        subtitle: Text(
                          'ID ${u['id_usuario']} · orden ${u['orden']} · ${activo ? "activo" : "inactivo"}',
                        ),
                        trailing: Wrap(
                          spacing: 6,
                          children: [
                            IconButton(
                              tooltip: 'Editar',
                              onPressed: () => _editar(u),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Eliminar',
                              onPressed: () => _eliminar(u),
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
