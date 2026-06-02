// lib/config/public_pedido_config.dart
/// URL base para el QR del pedido (sin barra final).
class PublicPedidoConfig {
  PublicPedidoConfig._();

  static const String urlBase = 'https://www.guardamar.es/pedido';

  static String urlConToken(String token) => '$urlBase/$token';
}
