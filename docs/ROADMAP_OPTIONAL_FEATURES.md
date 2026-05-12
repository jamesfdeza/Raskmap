# Roadmap de mejoras opcionales (post Sprint 4)

Este documento contiene los planes detallados de las **features XL** y
mejoras opcionales 🟢 que NO se implementan ahora porque requieren
varias semanas de trabajo, decisiones de producto, o riesgos altos
de regresión. Sirve como input para sesiones futuras.

---

## 1. iOS 18 Map + MapPolygon nativo (L · 2-3 semanas)

**Objetivo:** eliminar definitivamente el flicker en pan migrando del
`MKMapView` (UIKit, MKPolygonRenderer) actual al `Map { MapPolygon }`
SwiftUI nativo de iOS 18. Render acelerado por Metal.

**Bloqueantes:**
- Subir `IPHONEOS_DEPLOYMENT_TARGET` 17.0 → 18.0 (corta cuota de
  usuarios pero gana render).
- Reescribir `RaskMapView.swift` (≈750 líneas) entero.

**Plan:**
1. Sustituir `UIViewRepresentable + MKMapView` por SwiftUI `Map`:
   ```swift
   Map {
       ForEach(coloredFeatures, id: \.isoCode) { feature in
           MapPolygon(coordinates: feature.coords)
               .foregroundStyle(colorTheme.color(for: feature.status))
       }
   }
   ```
2. Tap-detection: usar `onTapGesture { location in ... convert ... }`
   con `MapReader`/`@MapCameraPosition`.
3. Flight mode: `MapPolyline` para rutas geodésicas.
4. Mantener el caché de paths innecesario — MapKit nativo lo gestiona.
5. Eliminar `Coordinator`, `RaskMapView.Coordinator`, pre-warm helper.

**Riesgo:** Alto. Tap detection y zoom controls son distintos. Testear
exhaustivamente con países pequeños (microestados).

**Quick start:** Crear `RaskMapView2.swift` en paralelo, dev en feature
flag (`@AppStorage("useNewMap")`). Migrar progresivamente.

---

## 2. iPad layout master-detail (L · 1-2 semanas)

**Objetivo:** Aprovechar el espacio del iPad con un layout
`NavigationSplitView` master (lista de países) - detail (mapa + sheets
inline) en lugar del modal único actual.

**Plan:**
1. Detectar `horizontalSizeClass == .regular` (iPad landscape/portrait
   wide, iPhone Plus landscape).
2. Layout split:
   - Columna izquierda (320pt): tabs Visitados/Próximos/Quiero +
     búsqueda + lista filtrable.
   - Columna derecha: mapa + sheets como inline detail views (no modal).
3. Sheets que aún se presenten como modal: AddTrip, EditTrip, Settings.
4. Drag & drop entre lista y mapa (mark/unmark visual).
5. Multitasking support (Slide Over / Split View).
6. Mantener iPhone layout intacto vía `@Environment(\.horizontalSizeClass)`.

**Beneficio:** App Store featured potential (Apple destaca apps con buen
iPad layout), nuevos usuarios iPad.

---

## 3. Apple Watch app real (XL · 2-3 semanas)

**Estado actual:** `RaskmapWatch Watch App/` es placeholder generado
por Xcode sin features. `RaskmapWatchWidgets/` tiene 3 complicaciones
funcionales (próximo viaje circular/rectangular, % mundo gauge).

**Objetivo:** Watch app standalone con:
1. **Tab "Próximos"** — lista de viajes futuros con countdown.
2. **Tab "Mapa"** — minimap con países visitados en tu región.
3. **Tab "Stats"** — contadores ONU/Pro.
4. **Complications adicionales** — modular `accessoryRectangular`
   con título + días, `accessoryInline` con próximo destino.

**Tech:**
- SwiftUI `WatchApp` independiente.
- Sync via `WatchConnectivity` framework (data clone limitado).
- O `WidgetCenter.shared.reloadAllTimelines()` desde el iPhone tras
  cambios → la Watch lee del App Group (ya disponible).

**Plan mínimo (1 sem):** 1 tab + 2 complications nuevas.
**Plan completo (3 sem):** 3 tabs + complications + Workout integration
(detectar viaje en curso vía CoreLocation Watch).

---

## 4. CloudKit shared records: "Competición con amigos" (XL · 3-4 semanas)

**Objetivo:** Diferenciador competitivo top-tier — usuarios pueden
compartir sus mapas con amigos via `CKShare` y ver leaderboards
mutuos.

**Tech:**
- Migrar a `CKShare`-based custom zone en CloudKit (separado del
  private database actual).
- UI nueva en Profile → "Amigos" para enviar/aceptar invitaciones.
- Computed properties para leaderboards (ranking entre amigos por
  países, vuelos, km).
- Notificaciones push cuando un amigo marca un país nuevo.

**Riesgos:**
- Cambio en privacidad: usuarios deben opt-in explícito (GDPR).
- Backend complejo: SwiftData no soporta shared records aún
  (oficialmente), requiere CoreData puente.
- Coste CloudKit en escala (lecturas cross-user).

**Plan mínimo:** "Compartir mapa" via UIActivityViewController + URL
deep link (sin sync real, solo snapshot momentáneo). Más simple pero
ya viral.

---

## 5. Otras mejoras

### 5.1 — Animar marcado de país (S) ✅ HECHO
Implementado en commit `bca095d`. Ripple celebratorio + haptic success
cuando se marca por primera vez como visited.

### 5.2 — Share trip con preview rich (M) ✅ HECHO
Implementado en commit `ff4f5ce`. Imagen 1080×1080 generada con
ImageRenderer para compartir en Mensajes/Instagram/WhatsApp.

### 5.3 — Empty states más visuales (M) ✅ HECHO
Implementado en commit `bca095d`. Buscador con SF Symbol grande en
círculo gris + título bold + sugerencia con emoji decorativo.

### 5.4 — Achievements como Live Activities celebratorias (M)

**Objetivo:** Cuando el usuario desbloquea un logro (todos los
microestados, 100 viajes, vuelta al mundo, etc.), mostrar una Live
Activity celebratoria de ~10 segundos.

**Plan:**
1. Nuevo `AchievementActivityAttributes: ActivityAttributes` con
   `ContentState` que tiene `title: String`, `emoji: String`.
2. En `checkAndShowAchievementToasts()` (ya existe), además del toast,
   trigger una Activity efímera con `Activity.request(...)`.
3. Auto-dismiss tras 10s vía `Activity.update(...)` con
   `dismissalPolicy: .after(.now + 10)`.
4. UI en `RaskmapLiveActivity.swift` — añadir branch para el
   AchievementActivityAttributes con fondo dorado + emoji grande.

**Esfuerzo:** ~1-2 días.

### 5.5 — Migrar font sizes restantes a Typography tokens
**Decisión: SKIP** — los tamaños son intencionalmente específicos
(widgets con 9pt eyebrows, hero text Wrapped 280pt, badges 20pt, etc.).
Una migración mecánica rompería la jerarquía visual cuidada. Los
tokens están disponibles para nuevo código y migración consciente
caso por caso.

---

## Resumen de bloqueos no técnicos

| Item | Bloqueo |
|---|---|
| Sprint 5 (submission App Store) | Apple Developer Account 99€/año |
| Verificar CloudKit container | Apple Developer Account |
| Restore Purchases sandbox testing | Apple Developer Account |
| swift-snapshot-testing tests | Xcode → File → Add Package Dependencies (1 paso manual) |

Todo lo demás está implementable sin esos bloqueos.
