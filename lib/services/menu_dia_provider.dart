// lib/services/menu_dia_provider.dart
import 'package:flutter/foundation.dart';

import '../models/models.dart';

class MenuDelDiaProvider extends ChangeNotifier {
  MenuDelDiaConfig? config;

  bool get loaded => config != null;
  bool get activoHoy => config?.activo == true;

  void cargar(Map<String, dynamic> data) {
    config = MenuDelDiaConfig.fromJson(data);
    notifyListeners();
  }

  bool esProductoMenu(Producto p) {
    if (MenuDelDiaConfig.filtroProductoMenu == p.filtro.trim()) return true;
    final id = config?.idProductoMenu;
    return id != null && p.id == id;
  }
}
