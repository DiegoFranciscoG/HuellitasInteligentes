// Configuración usada al compilar para producción (ng build --configuration production).
//
// IMPORTANTE: antes de construir la imagen, cambia `apiUrl` por tu dominio real.
// Antes aquí había '${API_URL}', un marcador que nada reemplazaba: el build de
// producción salía con esa cadena literal y la web no encontraba el backend.
//
// El dominio debe ser el MISMO que sirve la web, porque nginx redirige /api y
// /ws al backend (ver nginx.conf). Así solo hace falta un dominio y un
// certificado, y no hay problemas de CORS ni de contenido mixto.
//
//   Ejemplo:  https://huellitas-abc12.ondigitalocean.app/api/huellitas
//
export const environment = {
  production: true,

  apiUrl: 'https://huellitasinteligentes.duckdns.org/api/huellitas',

  demoMode: false,

  // ── Claves de servicios externos usados desde el navegador ───────────────
  turnMeteredDomain: 'huellitas-inteligentes.metered.live',
  turnMeteredApiKey: '1d2b99537beb7813392d88841bc30aa7f00e',
  catApiKey: 'live_CKexemhSHrYkPRykOtZBQOKBUXabClK7lDW0tOQpzIsqx1vmN5H7JYFJZxYpgFl5',

  // Coloca aquí el link directo de Google Drive o mantenlo así si usas el backend
  apkDownloadUrl: 'https://huellitasinteligentes.duckdns.org/huellitas.apk'
};
