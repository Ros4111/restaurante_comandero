/// Normalización para búsquedas por texto (minúsculas, acentos comunes → ASCII).
String normalizarTextoBusqueda(String raw) {
  var t = raw.toLowerCase().trim();
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuuunc';
  for (var i = 0; i < from.length; i++) {
    t = t.replaceAll(from[i], to[i]);
  }
  return t;
}
