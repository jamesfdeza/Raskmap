# CONTEXT.md — Raskmap

## 💳 Cuando actives la Apple Developer Account (99 €/año)

Sigue esta lista de checks en orden. Cada paso desbloquea el siguiente.
Cuando termines, la app estará lista para enviar a la App Store.

> **TIEMPO ESTIMADO TOTAL: 4-6 horas** la primera vez (mayoría es
> esperar propagaciones de Apple). Spread over 2-3 días si vas con calma.

---

### Fase 0 — Setup de la cuenta (1 vez, ~30 min)

- [ ] Ir a https://developer.apple.com → "Account" → pagar la suscripción 99€/año.
- [ ] Aceptar todos los agreements pendientes (Program License, Paid Apps Agreement
      si vas a cobrar Raskmap Pro).
- [ ] **Paid Apps Agreement** — clave: para vender IAP necesitas tener
      este aceptado con datos bancarios + fiscales (NIF, IBAN). Apple
      bloquea Restore Purchases si esto falta.
- [ ] Verificar email asociado a la cuenta.

---

### Fase 1 — Apple Developer Portal (~30 min)

Sitio: https://developer.apple.com/account

**1.1 — App ID (Bundle Identifier)**
- [ ] Identifiers → "+" → App IDs → App.
- [ ] Bundle ID: `RealDev.Raskmap` (debe coincidir con `PRODUCT_BUNDLE_IDENTIFIER` en pbxproj).
- [ ] Description: "Raskmap".
- [ ] Capabilities a marcar:
   - [ ] **iCloud** (con "Include CloudKit support").
   - [ ] **App Groups**.
   - [ ] **Push Notifications** (necesario para sync CloudKit en background y para Live Activities).
   - [ ] **In-App Purchase**.
   - [ ] **Sign In with Apple** (opcional, no usado por ahora).

**1.2 — Containers de iCloud / App Groups**
- [ ] Identifiers → iCloud Containers → "+" → `iCloud.RealDev.Raskmap`.
- [ ] Identifiers → App Groups → "+" → `group.com.jaime.raskmap` (tiene que coincidir EXACTAMENTE con el código).
- [ ] Volver al App ID, edit, asociar ambos al App ID.

**1.3 — Repetir para el Widget Extension**
- [ ] Identifiers → "+" → App IDs → `RealDev.Raskmap.RaskmapWidget`.
- [ ] Marcar mismas capabilities (App Groups, iCloud, Push).
- [ ] Asociar al mismo iCloud container y App Group.

**1.4 — Repetir para el Watch App** (si vas a publicarlo)
- [ ] `RealDev.Raskmap.watchkitapp`.
- [ ] Mismas capabilities relevantes (App Groups).

**1.5 — Provisioning Profiles**
- [ ] Apple los genera automáticamente si tienes "Automatically manage signing"
      en Xcode (recomendado). Si Xcode da error de signing, ir a Profiles →
      regenerar para Development e App Store distribution.

---

### Fase 2 — CloudKit Dashboard (~30 min)

Sitio: https://icloud.developer.apple.com

**2.1 — Verificar container `iCloud.RealDev.Raskmap`**
- [ ] Que aparece en la lista. Si no, esperar 5-10 min tras crear en Portal.
- [ ] Entornos: usa **Development** primero para testear, después promover a **Production**.

**2.2 — Schemas (Record Types) de SwiftData + CloudKit**
- [ ] Apple genera los Record Types automáticamente la primera vez que la app
      sincroniza desde SwiftData → CloudKit. Para forzar esto:
   - [ ] Build & run en device real (no simulator) con cuenta iCloud activa.
   - [ ] Crear un Country marcado como visited → SwiftData lo persiste localmente
         y CloudKit Container lo sincroniza creando `CD_Country` record type.
   - [ ] Hacer lo mismo para un Trip → genera `CD_Trip`.
   - [ ] Volver a CloudKit Dashboard → Schema → "Indexes" → verificar que ambos
         record types están allí.
- [ ] Si necesitas record types adicionales (para `RaskmapSnapshot` del XL 4 de
      sharing), crear manualmente desde Dashboard → Schema → "+".

**2.3 — Indexes para queries**
- [ ] CloudKit no indexa por defecto. Para queries cross-device añadir:
   - [ ] `CD_Country.isoCode` como QUERYABLE.
   - [ ] `CD_Trip.dateFrom` como QUERYABLE + SORTABLE.
   - [ ] `CD_Trip.isoCode` como QUERYABLE.

**2.4 — Promover a Production**
- [ ] **NO hacer hasta validar que todo funciona en Development**.
- [ ] Cuando esté validado: Dashboard → "Deploy Schema Changes" →
      seleccionar Development como source, Production como destination.
- [ ] **El esquema de Production es read-only**: cualquier cambio post-deploy
      requiere una migración manual cuidadosa.

---

### Fase 3 — App Store Connect (~1 hora)

Sitio: https://appstoreconnect.apple.com

**3.1 — Crear la app**
- [ ] My Apps → "+" → New App.
- [ ] Platform: iOS.
- [ ] Name: "Raskmap" (debe estar disponible; si no, probar "Raskmap - Tu mapa de viajes").
- [ ] Primary Language: Spanish.
- [ ] Bundle ID: `RealDev.Raskmap` (selectable del dropdown si está bien configurado en Portal).
- [ ] SKU: cualquier identificador único interno, ej. `raskmap-001`.

**3.2 — App Privacy questionnaire**
- [ ] Pregunta 1: "Does your app collect data?" → **No**. Coherente con la
      política y con el `PrivacyInfo.xcprivacy` (commit `c24d8f1`).
- [ ] Save.

**3.3 — In-App Purchase para Raskmap Pro**
- [ ] Features → In-App Purchases → "+".
- [ ] Tipo: **Non-Consumable** (pago único vitalicio).
- [ ] Reference Name: "Raskmap Pro Lifetime".
- [ ] Product ID: `com.raskmap.pro.lifetime` (debe coincidir EXACTO con
      `raskmapProLifetimeID` en `Sheets/SubscriptionSheet.swift` línea 21).
- [ ] Price Tier: **Tier 5 (4,99 €)** o el que prefieras.
- [ ] Localization (ES + EN):
   - ES: Display Name "Raskmap Pro", Description "Desbloquea las funciones
         premium de Raskmap de forma permanente. Pago único, sin suscripción."
   - EN: Display Name "Raskmap Pro", Description "Unlock all premium features
         permanently. One-time purchase, no subscription."
- [ ] Save → submit for review junto con el binario.

**3.4 — Metadata App Information**
- [ ] App Information → Privacy Policy URL: la URL que generes en Fase 4.
- [ ] App Information → Support URL: misma o landing del repo legal.
- [ ] Category: Primary "Travel" · Secondary "Lifestyle".
- [ ] Content Rights → declarar si Twemoji genera dudas (lo cubre la atribución legal).

**3.5 — App Store Page (por locale)**
- [ ] Localizations: añadir **English (U.S.)** además de **Spanish (Spain)**.
- [ ] Por cada locale necesitas:
   - [ ] **Name** (30 chars max): "Raskmap" / "Raskmap" (igual).
   - [ ] **Subtitle** (30 chars max):
     - ES: "Tu mapa personal de viajes"
     - EN: "Your personal travel map"
   - [ ] **Promotional Text** (170 chars).
   - [ ] **Description** (4000 chars max).
   - [ ] **Keywords** (100 chars total, separados por coma — sin espacios).
     - ES: `viajes,mapa,países,visitados,viajar,bucket,list,vuelos,aeropuertos,wrapped`
     - EN: `travel,map,countries,visited,trips,bucket,list,flights,airports,wrapped`
   - [ ] **What's New in This Version** (4000 chars).
   - [ ] **Screenshots** — ver Fase 5.

**3.6 — Review Information**
- [ ] Contact email + phone (lo verá Apple, no users).
- [ ] Demo Account: NO necesario (la app no requiere login).
- [ ] Notes for Review: explica que la app está 100% local + iCloud privado,
      sin tracking, sin login. Incluye un disclaimer corto sobre Twemoji
      (CC-BY 4.0) si los reviewers preguntan.

---

### Fase 4 — Privacy Policy y soporte legal (~30 min)

**4.1 — Activar GitHub Pages**
- [ ] El repo ya tiene `docs/` con los textos legales (privacy, terms, gdpr,
      imprint, credits, index).
- [ ] Repo Settings → Pages → Source: **Deploy from a branch**.
- [ ] Branch: `master` (o `main` si lo renombras), Folder: `/docs`.
- [ ] Save → esperar ~1 min.
- [ ] La URL final será `https://jamesfdeza.github.io/Raskmap/` o similar.

**4.2 — URLs concretas que necesita App Store Connect**
- [ ] Privacy Policy URL: `https://<usuario>.github.io/Raskmap/privacy`
- [ ] Support URL: `https://<usuario>.github.io/Raskmap/` (landing)
- [ ] Marketing URL (opcional): igual que support.

**4.3 — Verificar que coinciden con la app**
- [ ] La privacy policy en docs/privacy.md DEBE ser idéntica al texto
      mostrado dentro de la app (Ajustes → Política de Privacidad).
      Apple verifica esto en revisión. Hoy ya coinciden (commit b09efc4).

---

### Fase 5 — Capturas y App Preview (~2 horas)

**5.1 — Screenshots requeridos (App Store Connect)**

Apple acepta los del iPhone más grande y los infiere para más pequeños.
Solo necesitas:

- [ ] **iPhone 6.9" (iPhone 16 Pro Max)** — 1320 × 2868 px o equivalente.
- [ ] **iPhone 6.5" (Plus / Pro Max viejos)** — 1242 × 2688 px (mismo simulator).
- [ ] Opcionales pero recomendados: iPad 13" si la app soporta iPad
      (cuando actives `IPadRootView` del XL 2).

Por locale (ES + EN): mínimo 3 screenshots, máximo 10. Recomendado 5-6:

1. Mapa con varios países marcados (visitados + próximos + bucket list).
2. Country sheet abierta con un país visitado (Japón, Marruecos…).
3. Sheet de perfil con stats y heatmap.
4. Wrapped anual (slide hero "ASÍ FUE MI 2025").
5. Modo Flight con rutas geodésicas.
6. Widget Lock Screen + Home screen previews.

**5.2 — Cómo capturar**
- [ ] Simulator (Hardware → Device → iPhone 16 Pro Max).
- [ ] Cmd+S para screenshot → guarda en Desktop como PNG.
- [ ] Editar (opcional pero ayuda):
  - [ ] Añadir mock de status bar (9:41 AM siempre).
  - [ ] Marcos / texto explicativo opcional (Apple permite text overlays).

**5.3 — App Preview (vídeo, opcional)**
- [ ] 15-30s vertical 9:16.
- [ ] Captura desde simulator con Cmd+R recording.
- [ ] Editar en iMovie / CapCut para añadir música + transitions.
- [ ] NO mostrar UI de iOS (no toolbars del simulator).

---

### Fase 6 — Verificaciones técnicas finales (~1 hora)

**6.1 — Items pendientes del CONTEXT.md (Sprint 1 ⏸️)**
- [ ] **B3 — Restore Purchases en sandbox**:
   - [ ] Crear sandbox tester en App Store Connect → Users and Access →
         Sandbox → Testers → "+".
   - [ ] En iPhone real (Settings → Developer → Sandbox Apple Account → sign in
         con el sandbox tester).
   - [ ] Lanzar la app → comprar Pro → debe completar la compra.
   - [ ] Borrar la app → reinstalar → Ajustes → "Restaurar compras" debe
         devolver el estado Pro sin pagar de nuevo.

- [ ] **B4 — CloudKit container en Production**:
   - [ ] Hecho en Fase 2.4 arriba.

**6.2 — Activar swift-snapshot-testing (item residual)**
- [ ] Xcode → File → Add Package Dependencies →
      `https://github.com/pointfreeco/swift-snapshot-testing` → target `RaskmapTests`.
- [ ] Los tests de scaffold ya esperan esta dep — al instalarla, los snapshot
      tests del commit `04c7702` se activan automáticamente.

**6.3 — Build & Archive**
- [ ] Xcode → Product → Scheme → seleccionar "Raskmap" + destination "Any iOS Device".
- [ ] Product → Archive (~5-10 min, requiere device target real, no simulator).
- [ ] Window → Organizer → Last Archive → "Distribute App" → App Store Connect.
- [ ] Upload (~5-10 min subiendo a App Store Connect).
- [ ] Esperar que Apple procese el binario (~15-30 min).

---

### Fase 7 — TestFlight beta (recomendado, ~3-5 días)

- [ ] TestFlight → Builds → seleccionar el build subido.
- [ ] What to Test: rellenar con lista de features para los testers.
- [ ] Internal Testers: añadir tu propio Apple ID (testing inmediato).
- [ ] External Testers: invitar 15-20 usuarios conocidos. Apple revisa
      el build para TestFlight (~24h primera vez).
- [ ] Ronda de feedback: 3-5 días mínimo. Itera bugs visibles antes del submit final.

---

### Fase 8 — Submission a App Store (~10 min de tu lado, ~1-3 días Apple)

- [ ] App Store Connect → tu app → Version 1.0 → "Add for Review".
- [ ] Verificar checklist:
   - [ ] Screenshots subidos (ES + EN).
   - [ ] Descripción rellena (ES + EN).
   - [ ] Privacy Policy URL OK.
   - [ ] IAP product approved together.
   - [ ] Notes for Review claras.
- [ ] "Submit for Review".
- [ ] Apple suele tardar **24-48h** para apps nuevas. Si rechazan, Apple
      manda email con motivo + Resolution Center para responder.

---

### 🎉 Cuando esté aprobada

- [ ] Publicar manual o automáticamente (recomendado manual la primera vez).
- [ ] Anunciar en Instagram / Twitter / etc.
- [ ] Activar TestFlight para futuras versiones (es más rápido subir builds
      una vez la app está aprobada).
- [ ] Monitor App Store Connect → Sales and Trends para ver descargas + IAP.

---

### Bonus opcional (después del launch)

- [ ] **AdMob** si quieres anuncios para usuarios no-Pro:
   - [ ] Crear cuenta admob.google.com.
   - [ ] Registrar la app → obtener App ID y Ad Unit ID (Banner).
   - [ ] Añadir SDK en Xcode: `swift-package-manager-google-mobile-ads`.
   - [ ] `Info.plist`: `GADApplicationIdentifier = <App ID>`.
   - [ ] `BannerAdView.swift`: sustituir test ID por Ad Unit ID real.

- [ ] **Activar los XL 🔵 scaffolds** ya implementados:
   - [ ] iPad layout: añadir `.adaptiveRoot(...)` al body de ContentView.
   - [ ] Watch app: ya activo solo con instalar la app en un Watch emparejado.
   - [ ] iOS 18 Map: subir target a 18.0 + feature flag.
   - [ ] CloudKit sharing: configurar zona + record type + descomentar
         `CKModifyRecordsOperation`.

---

## 👁 Resumen visual de cambios para el usuario final

Tras la iteración completa (Sprints 1-4 + nice-to-haves 🟡 + 🟢), un
usuario notará al abrir la app:

1. **Paleta refinada** — el cambio MÁS visible. Vivido pasa de verde
   salvia (confundible con próximos) a **violeta apagado**. Visited
   más cálido (siena), próximos menos saturado (verde mar), bucket
   más suave (miel).
2. **Mapa fluido sin flicker** al hacer pan + zoom-out sin tope.
3. **Ripple celebratorio + haptic** al marcar país como visitado
   por primera vez.
4. **Live Activity dorada** al desbloquear logros (10s, auto-dismiss).
5. **Share trip rich** — preview imagen 1080×1080 con gradient + flags
   además del texto.
6. **Widget medium reorganizado** — header arriba, bandera centrada,
   muestra título de viaje si tiene (sino país).
7. **"Lugares por descubrir" rediseñado** — 1 por región (no varias
   de África, sí Oceanía), banderas tappables (abren país en mapa),
   ISR excluido.
8. **Búsqueda con empty state visual** (SF Symbol grande + emoji).
9. **App en inglés** disponible (93.4% de strings traducidas).
10. **Dynamic Type funciona** — "Larger Text" en Settings escala
    todo el texto de la app.
11. **VoiceOver mejorado** — buttons icon-only describen acciones.
12. **Tap area mejorada** — counter buttons cumplen Apple HIG 44pt.
13. **Auto-marcado por ubicación eliminado** — ya no marca países
    sin que el usuario lo pida explícitamente.
14. **Eliminar de próximos funciona** — antes el trip futuro
    resucitaba la marca, ahora se purga correctamente.

Cambios invisibles pero impactantes:
- Compilación Xcode 3× más rápida (ContentView -84.1%).
- Errores SwiftData visibles en Console.app (antes silenciados).
- Cache de renderers acotado (sin memory bloat).
- Tasks cancelables → sin race conditions al navegar rápido.

---

## 🧭 ESTADO ACTUAL · Punto de continuación (2026-05-11)

> **Para Claude / cualquier dev que retome el proyecto:** lee esta sección antes
> que nada. Aquí está exactamente por dónde íbamos y qué falta.

### Última acción completada (2026-05-12 — XL scaffolds 🔵 cerrados)

Los 4 items XL del roadmap completados como **scaffolds funcionales** —
archivos paralelos a la app existente, opt-in por el dev cuando se quieran
activar. No invasivos sobre el código en producción.

**XL 1 — iOS 18 Map nativo** (`db9ad0d`):
- `Raskmap/RaskMapViewV2.swift`: SwiftUI `Map { MapPolygon }` con
  `@available(iOS 18.0, *)`, cámara controlable, `coloredFeatures`
  filtrado, helper `polygonCoords(_:)`.
- Pendiente: tap-detection con `MapReader.proxy.convert`, flight mode
  con `MapPolyline`, wire-up en ContentView con feature flag
  `@AppStorage("useMapV2")`.

**XL 2 — iPad layout master-detail** (`ac47050`):
- `Raskmap/IPadRootView.swift`: NavigationSplitView 2 columnas
  (sidebar 280-400pt con Picker segmented Visitados/Próximos/Quiero/
  Vivido + search + lista filtrable + empty state · detail con hero
  flag 64pt, stats tiles, lista de viajes, placeholder).
- View extension `.adaptiveRoot(...)` envuelve el root del iPhone:
  si `horizontalSizeClass == .regular` → IPadRootView; si no →
  vista original sin cambios.
- Pendiente: añadir `.adaptiveRoot(...)` al body de ContentView.

**XL 3 — Apple Watch app real** (`8d9355c`):
- `RaskmapWatch Watch App/ContentView.swift`: sustituye el placeholder
  "Hello, world!" por TabView con 3 tabs:
  · Próximo viaje (flag + countdown + nombre).
  · Gauge `.accessoryCircular` 1.6× del % del mundo visitado.
  · Stats numéricos (visited + mode label).
- Datos vía App Group `group.com.jaime.raskmap` (mismo que widget iOS).
- Pendiente: refresh en tiempo real vía `NotificationCenter` /
  `WatchConnectivity`.

**XL 4 — CloudKit shared records** (`8e6b7ab`):
- `Raskmap/CloudKitSharing.swift`: helper para compartir snapshot del
  mapa vía CKShare.
- `RaskmapSnapshot` struct Codable con username + visited/planned isos
  + stats + createdAt.
- `CloudKitSharing.shareSnapshot(_:from:completion:)` crea CKRecord +
  CKShare + presenta UICloudSharingController.
- `RaskmapSnapshot.build(...)` factory desde SwiftData @Query.
- Pendiente: persistencia real con `CKModifyRecordsOperation`,
  background handler de invitations, vista "Mapa de un amigo",
  leaderboard. Bloqueado por Apple Developer Account.

### Última acción completada anterior (2026-05-12 — Nice-to-haves 🟢 abordados)

Sesión dedicada a las mejoras opcionales del roadmap. Combinación de
implementación directa para los items realizables + documentación para
los XL que requieren semanas:

**Implementados:**
- ✅ Items 1+3 (`204f859`): asyncAfter dinámicos del Wrapped a Task con
  cancel check + a11y paso 2 en SettingsSheet/ProfileSheet (avatar
  pasaporte, edit username, gearshape Ajustes).
- ✅ Items 4+6 (`bca095d`): ripple celebratorio + haptic success al
  marcar visitado por primera vez + empty state buscador rediseñado
  (SF Symbol en círculo + emoji decorativo).
- ✅ Item 5 (`ff4f5ce`): share trip con preview rich 1080×1080
  (TripShareCard render con ImageRenderer, fondo gradient, banderas
  + días, footer Raskmap).
- ✅ Item 7 (`7cd4646`): Live Activity celebratoria al desbloquear
  logros (RaskmapAchievementLiveActivity con UI dorada,
  AchievementCelebrator helper, auto-dismiss tras 10s).

**Documentados (no implementados) — en `docs/ROADMAP_OPTIONAL_FEATURES.md` (`1772fe5`):**
- 🔵 iOS 18 Map + MapPolygon migration (L, 2-3 sem).
- 🔵 iPad layout master-detail (L, 1-2 sem).
- 🔵 Apple Watch app real (XL, 2-3 sem).
- 🔵 CloudKit shared records "competición con amigos" (XL, 3-4 sem).

**Decisión "no migrar":** Typography tokens — los tamaños actuales son
intencionalmente específicos. Migración mecánica rompería jerarquía.

### Última acción completada anterior (2026-05-12 — Nice-to-haves 🟡 cerrados)

Tras Sprint 4, una pasada por los tres frentes 🟡 (deuda gestionable):

- ✅ **B3 multi-line** (`a429205`): 21 patrones de
  `DispatchQueue.main.asyncAfter` multi-line migrados a
  `Task { @MainActor in try? await Task.sleep(...); ... }`. Auto-cancel
  cuando la View desaparece. Quedan 2 ocurrencias dinámicas en
  YearWrappedSheet (`delay * Double(i)` para animaciones secuenciales).

- ✅ **A11y exhaustiva paso 1** (`2ba7410`): labels añadidos a 8 buttons
  icon-only en AllCountriesSheet, ListSheets, MapQuadrantsSheets.
  VoiceOver ahora describe acciones contextuales ("Editar cuadrante X",
  "Eliminar país", "Restablecer cuadrantes", etc.).

- ✅ **Dynamic Type** (`aa5c78d`): cambio quirúrgico en `Font.palatino`
  añadiendo `relativeTo: style` al `Font.custom`. Propagación: ~todos
  los textos de la app respetan ahora la preferencia "Larger Text" de
  Settings → Accessibility sin tocar ningún call site.

### Última acción completada anterior (2026-05-12 — Sprint 4 cerrado)

**Sprint 4 — items 15 + 16 completados:**

- ✅ **Paleta refinada** (`9077a8a`): defaults `ColorThemeManager`
  actualizados. Visited siena (#D65B3F), wantToVisit verde mar (#5BA89B),
  lived violeta (#7B5BAB), bucket miel (#F2C265). Soluciona el problema
  crítico de "verde salvia vs verde esmeralda" confundibles. Usuarios
  que personalizaron colores en Ajustes los conservan.
- 🟡 **Snapshot tests scaffold** (`04c7702`): 6 tests preparados con
  `#if canImport(SnapshotTesting)`. Activación pendiente de añadir
  manualmente el SPM package `swift-snapshot-testing` desde Xcode.

(Item 14 — modularización — ya completado durante Fase D, anticipado).

### Última acción completada (2026-05-11, madrugada — Sprint 3 Calidad UX)

**Sprint 3 — los 5 frentes priorizados completados en pasada masiva:**

1. ✅ **DesignTokens.swift** creado (commit `f3c61c1`):
   `BrandColor` + `Radius` + `Typography` + `Spacing` + `Anim` + `TapTarget`.
2. ✅ **Migración accent color** → `BrandColor.accent` (commit `f84fd14`):
   13 ocurrencias + 2 UIColor variants.
3. ✅ **Migración cornerRadius → tokens** (commit `319a55a`): 162 reemplazos
   en 24 archivos. Mapeo semántico: 8→chip, 10/11/12→cell, 14→card,
   16/18→section, 20/22/24→sheet.
4. ✅ **Empty state en búsqueda global** (commit `dfbf3cd`): mensaje
   "Sin resultados" + sugerencia cuando query sin matches. Resto del
   proyecto: 205 strings empty state ya implementados.
5. ✅ **Tap targets ≥ 44pt** (commit `0d00f92`): hit area expandida a
   `TapTarget.min` en counter buttons (+/-) sin cambiar visual.
6. ✅ **A11y annotations** (commit `6440cee`): StatBadge + LegendItem
   + FlagLabel fallback con `accessibilityLabel` para VoiceOver.
7. ✅ **asyncAfter → Task cancelables** (commit `3f624ba`): 6 patrones
   one-line (toast-hide, recheckLocation, savedToast, etc.) migrados.
   Restantes 19 multi-line para próxima iteración.

### Fase D — COMPLETADA. 24 archivos extraídos a `Raskmap/Sheets/`:

- ContentView.swift: 14 951 → **2 380 líneas (-84.1%)**. 🎯 Objetivo
  <3 000 líneas conseguido.
- Build OK tras hotfixes de imports y access levels.

**Archivos en `Raskmap/Sheets/` (orden de creación):**

| Archivo | Líneas | Commit | Total ContentView |
|---|---|---|---|
| `StatsBreakdownSheets.swift` | 183 | `e55452e` | 14 782 |
| `SettingsSubSheets.swift` | 243 | `42e116b` | 14 555 |
| `ContactSheet.swift` | 220 | `5c1afc0` | 14 349 |
| `SubscriptionSheet.swift` | 266 | `501a3a5` | 14 098 |
| `RouteWizardSheet.swift` | 922 | `ef7b284` | 13 194 |
| `TransportStatsSheets.swift` | 1 185 | `cd5d15a` + `9e4e7bc` | 12 033 |
| `ListSheets.swift` | 945 | `0889454` + `6bbcae3` | 11 109 |
| `AllCountriesSheet.swift` | 302 | `0820dc1` | 10 823 |
| `LogrosSheet.swift` | 317 | `185adc1` | 10 519 |
| `PlannedDatePickerSheet.swift` | 437 | `ffd0927` | 10 096 |
| `SmallWidgets.swift` | 180 | `d90aa53` | 9 935 |
| `MultiContinentHemisphereSheets.swift` | 342 | `7d2c2ae` | 9 614 |
| `SubjectiveSheets.swift` | 479 | `ca9e605` | 9 153 |
| `AwardsSheets.swift` | 433 | `9ce3632` | 8 736 |
| `MapQuadrantsSheets.swift` | 925 | `951e6ab` | 7 827 |
| `SettingsExtraSheets.swift` | 545 | `295765b` | 7 306 |
| `FlightInfoSection.swift` | 625 | `709650e` | 6 698 |
| `YearTravelView.swift` | 390 | `22469d6` | 6 321 |
| `PassportAndFlightSlider.swift` | 236 | `e3deba1` | 6 102 |
| `TopBarWidgets.swift` | 207 | `7e2bbb6` | 5 912 |
| `AchievementKind.swift` | 415 | `75f29c1` | 5 513 |
| `AddTripSheet.swift` | 424 | `0f66f30` | 5 105 |
| `EditTripSheet.swift` | 834 | `bed4181` | 4 286 |
| `ProfileSheet.swift` | 992 | `f9a654e` | 3 316 |
| `SettingsSheet.swift` | 957 | `6f9bf0c` | **2 380** |

**Hotfixes durante la fase:**
· `028646f`: imports faltantes (CoreLocation/MapKit en MapQuadrants,
  UIKit en Contact y PlannedDatePicker).
· `9ba80d6`: `confirmCardContent` cambia a `internal` (cross-file) +
  `format` captured antes de Task.detached en ExportDataSheet.

### Acción completada anterior (2026-05-11, mañana)
**Fase A (App Store readiness) — parcial:**
- ✅ A1 — `IPHONEOS_DEPLOYMENT_TARGET` 26.2 → 17.0 (commit `c24d8f1`).
- ✅ A2 — `PrivacyInfo.xcprivacy` añadido a app + widget (mismo commit).
- ✅ Bonus — Gateado `RaskmapWidgetControl` (iOS 18 Control Center API)
  tras `@available(iOS 18.0, *)` y removido del bundle (commit `eb593ef`).
- ⏸️ A3 — Verificar CloudKit container: pendiente de Apple Developer Account.
- ⏸️ A4 — Verificar Restore Purchases en sandbox: pendiente de Apple Developer Account.

**Fase B (error handling) — completada:**
- ✅ B2 — Logger SwiftData (`os.Logger`) + `ModelContext.saveOrWarn()` reemplaza
  los 34 `try? modelContext.save()` (commit `1968897`).
- ✅ B4 — Cache de renderers del mapa: fallback en `rendererFor(_:)` solo
  cachea si el polígono está en `activeOverlayIsos`. Naturalmente acotado
  por |activeOverlayIsos|. Añadido `compactRendererCacheIfNeeded()` defensivo
  (cap 2000) por si en el futuro cambia la arquitectura (commit `1968897`).
- ✅ B1 — 12 force-unwraps reales refactorizados a patrones safe (commit
  `56e2255`). Los "234" del audit eran mayormente declaraciones de tipo
  implicitly-unwrapped (`var x: Type!`) — patrón válido. Único restante
  intencionado: `var parent: RangeDatePicker!` (UIKit delegate pattern).
- 🟡 B3 — Deuda residual documentada. Los 26 `DispatchQueue.main.asyncAfter`
  no se migran ahora porque (1) no causan crashes, solo timing oddities raros;
  (2) migración es mecánica pero multiplicativa (`@State Task?` por sheet);
  (3) ROI bajo ahora — mejor abordar durante Sprint 4 (modularización),
  cuando ya estaremos tocando cada sheet de todos modos.

**Fase C (Localización EN) — completada:**
- ✅ C1 — `developmentRegion = es`, knownRegions = (en, es, Base) en pbxproj
  (commit `17dfdcf`).
- ✅ C2 — `Raskmap/Localizable.xcstrings` creado con 77 keys iniciales clave
  + traducciones EN (commit `17dfdcf`).
- ✅ Fix — `STRING_CATALOG_GENERATE_SYMBOLS = NO` para evitar colisiones
  case-insensitive en accessors auto-generados (commit `2946222`).
- ✅ C3 — Traducción masiva: 396/424 keys traducidas a EN = **93.4% coverage**
  (commit `dce37ed`). Las 28 restantes son símbolos puros (emojis,
  placeholders, IATAs) que no necesitan traducción.

Cobertura por área tras C3: alerts 100%, onboarding 100%, settings 100%,
logros 100%, wrapped 100%, widget 100%, empty states 100%, stats 100%.

**Fase D (Modularización ContentView) — en progreso, segundo chunk:**
ContentView: 14 951 → 11 109 líneas (-3 842, **-25.7%**) tras 7 extracciones:

- ✅ `Sheets/StatsBreakdownSheets.swift` (-169 líneas, `e55452e`):
  AirportStatsSheet, AirlineStatsSheet, SeatStatsSheet, SeatPositionStatsSheet.
- ✅ `Sheets/SettingsSubSheets.swift` (-227 líneas, `42e116b`):
  SettingsInfoSheet, LegalInfoSheet, WidgetLockScreenSheet, WidgetWatchSheet.
- ✅ `Sheets/ContactSheet.swift` (-206 líneas, `5c1afc0`):
  ContactSheet + MailComposerView.
- ✅ `Sheets/SubscriptionSheet.swift` (-251 líneas, `501a3a5`):
  SubscriptionSheet + constantes Raskmap Pro.
- ✅ `Sheets/RouteWizardSheet.swift` (-904 líneas, `ef7b284`):
  RouteWizardSheet + RoutePickerSheet + AirlinePickerSheet.
- ✅ `Sheets/TransportStatsSheets.swift` (-1 161 líneas, `cd5d15a`):
  TransportStatsSheet + 5 sub-sheets relacionados.
- ✅ `Sheets/ListSheets.swift` (-924 líneas, `0889454`):
  StatusListSheet + FinalizadosListSheet + FinalizadoTripDetailSheet.

Fix intermedio (`04d96e6`): `raskmapProLifetimeID/raskmapProAllIDs`
cambiados de `private` a `internal` para cross-file + reemplazo de
`%lld%%` por `%@` en una key del catalog (warning Xcode 16).

**Próxima sesión:** Fase D **completada**. Próximos focos posibles:

1. **B3 diferido** — los 26 `DispatchQueue.main.asyncAfter` ahora se
   pueden abordar más fácilmente: cada sheet vive en su propio archivo
   y puede tener su propio `@State Task?` para cancelación.
2. **Sprint 3 (Calidad UX)** del roadmap original:
   - `DesignTokens.swift` (BrandColor + Radius + Typography + Anim).
   - Auditoría a11y: subir de 13 a 100+ annotations.
   - Empty states completos.
   - Tap targets ≥ 44pt.
3. **iOS 18 Migration** (opcional): migrar el mapa a SwiftUI `Map { MapPolygon }`
   con aceleración Metal → eliminaría el flicker definitivamente.
4. **Tests adicionales**: snapshot diff con swift-snapshot-testing,
   UI Tests del onboarding y add trip flow.

ContentView ahora contiene solo: `MapStore` class + `ContentView` struct
(root view), handlers (handleCountryTap, recheckLocation, etc.), helpers
internos del map view y los data models cross-file (AirportData,
AirlineData).

### Lo último que se entregó (sesión 2026-05-11)
- Hotfixes UX: countdown solo en modo mapa, eliminación de plantillas rápidas,
  rediseño de "Lugares por descubrir" (1 por región + sancionados + tappable),
  README rewrite, eliminación de auto-marcado por ubicación, highlight solo
  si visitado, optimización de mapa (solo overlays coloreados + sin cap zoom),
  widget mediano (header arriba + bandera centrada + título o país),
  Wrapped (sin emoji 🗺️ en footer + tipografía mayor en cuadrantes),
  Live Activity revertida a mostrar días (no HH:MM:SS).
- **Auditoría integral** del proyecto (rol experto Swift + UX/UI tester) →
  ver sección [`📋 Auditoría integral`](#-auditor%C3%ADa-integral-del-proyecto-2026-05-11)
  más abajo en este documento.

### 🎯 Próximos pasos priorizados (de la auditoría)

**Sprint 1 — Bloqueantes App Store (1 semana):**
1. [x] **B1** Verificar y bajar `IPHONEOS_DEPLOYMENT_TARGET` de 26.2 a 17.0 ✅ commit `c24d8f1`.
2. [x] **B2** Crear `Localizable.xcstrings` con EN + ES (93.4% coverage) ✅ commit `dce37ed`.
3. [x] **B5** Generar `PrivacyInfo.xcprivacy` (app + widget) ✅ commit `c24d8f1`.
4. [ ] ⏸️ **B3** Test funcional Restore Purchases en sandbox.
       _Bloqueado: requiere Apple Developer Account (99€/año) — el usuario lo está retrasando intencionalmente._
5. [ ] ⏸️ **B4** Verificar CloudKit container `iCloud.RealDev.Raskmap` en prod.
       _Bloqueado: misma razón que B3._

> **Nota:** B3 y B4 quedan pausados hasta que el usuario active su Apple Developer Account.
> En cuanto la tenga, son ~30 min de verificación combinada. No bloquean el desarrollo
> técnico restante; solo bloquean el submit a App Store.

**Sprint 2 — Estabilidad (2 semanas):**
6. [x] Auditar 234 force-unwraps en `ContentView.swift`, proteger los más arriesgados ✅ commit `56e2255`.
7. [x] Migrar `try? modelContext.save()` críticos a `do/catch` con logging vía `os.Logger` ✅ commit `1968897`.
8. [x] Acotar `Coordinator.rendererCache` (fallback no-cachea si no está activo) ✅ commit `1968897`.
9. [ ] 🟡 Reducir 26 `DispatchQueue.main.asyncAfter` → diferido a Sprint 4. No causan crashes;
       migración es multiplicativa con ROI bajo aislado. Mejor abordar junto con
       modularización (cada sheet se tocará igualmente).

**Sprint 3 — Calidad UX (2 semanas):**
10. [x] Sistema de tokens: `DesignTokens.swift` con `BrandColor`, `Radius`, `Typography`, `Anim` ✅ commits `f3c61c1` + `f84fd14` + `319a55a`.
11. [~] Auditoría a11y — primera pasada completada ✅ commit `6440cee`. Continuar audit de buttons sin label en próxima iteración.
12. [x] Empty states ✅ commit `dfbf3cd` (buscador). Resto: 205 strings empty state ya implementados en project.
13. [x] Audit tap targets ≥ 44pt ✅ commit `0d00f92` (counter buttons +/-). Otros pequeños son decorativos o tienen padding row suficiente.

**Sprint 4 — Modularización (3 semanas):**
14. [x] ✅ Extraer sheets de ContentView (completado en Fase D, 24 archivos,
       ContentView 14 951 → 2 380 líneas, -84.1%).
15. [x] ✅ Paleta refinada aplicada — commit `9077a8a`. visited siena +
       wantToVisit verde mar + lived violeta + bucket miel. Solo defaults,
       no afecta a usuarios que ya personalizaron colores.
16. [~] 🟡 Snapshot tests reales — scaffold creado (commit `04c7702`).
       6 tests preparados con `#if canImport(SnapshotTesting)`. Para
       activarlos requiere acción manual del usuario:
       Xcode → File → Add Package Dependencies… →
       `https://github.com/pointfreeco/swift-snapshot-testing` →
       target RaskmapTests.

**Sprint 5 — Submission:**
17. [ ] Screenshots EN + ES.
18. [ ] App Preview video.
19. [ ] TestFlight beta con 20 usuarios externos.

### ⚠️ Single biggest blocker

> El iOS deployment target `26.2` y la ausencia de `PrivacyInfo.xcprivacy`
> rechazarán el binario en submission. Empezar por ahí.

### Notas operativas
- Branch activa: `remodelacion_integral_v2`. Master nivelado en `771835f`.
- Worktree: `/Users/jaimefernandezarenas/Documents/Raskmap/.claude/worktrees/hopeful-goldwasser/`.
- Repo path principal: `/Users/jaimefernandezarenas/Documents/Raskmap/`.
- Sin commits pendientes ni archivos dirty críticos (solo `.DS_Store` y un par de assets sin importancia).

### Convenciones para futuras sesiones
- **Cada nueva sesión actualiza la sección "ESTADO ACTUAL"** al inicio de
  CONTEXT.md con: última acción completada, último entregable, próximos
  pasos pendientes, blockers actuales.
- **No borrar el histórico** de "Cambios recientes (FECHA)" — crece hacia abajo.
- **Auditoría se mueve a "Histórico"** cuando se aborda; mientras esté pendiente,
  vive en sección activa.

---

## 📋 Auditoría integral del proyecto (2026-05-11)

> Informe técnico generado al final de la sesión. Lectura recomendada para
> retomar el proyecto con visión completa de deuda y oportunidades.

### Resumen ejecutivo

Raskmap es una app sólida y funcionalmente rica (mapa 250+ países, segmentos
multi-modal, Wrapped, Live Activity, widgets, GDPR). Deuda técnica acumulada
en tres frentes que impactan App Store:

1. **Monolitos** — `ContentView.swift` tiene **14 943 líneas**.
2. **Localización inexistente** — sin `Localizable.xcstrings`, todo es español
   hardcoded (~77 strings). Limita TAM al ~6% de iOS.
3. **Error handling silencioso** — `try?` sin recovery, 26 `DispatchQueue.asyncAfter`
   como hacks de timing, **234 force-unwraps** sin verificar.

La app es ligera de subir hoy (no es crash-prone), pero esas grietas crecerán
con cada feature.

### 🔴 Bloqueantes App Store

| ID | Issue | Detalle | Acción |
|---|---|---|---|
| **B1** | `IPHONEOS_DEPLOYMENT_TARGET = 26.2` | Solo iOS 26.2+ → excluye 80% de la base instalada. | Bajar a iOS 17.0 o 18.0. SwiftData necesita 17; MapPolygon nativo necesita 18. |
| **B2** | No hay `Localizable.xcstrings` | App 100% en español. Revisión Apple puede señalar metadata mismatch. | Crear `Localizable.xcstrings` con EN + ES base. |
| **B3** | Restore Purchases verificable | Falta confirmar que llama `Transaction.currentEntitlements` y actualiza `isRaskmapPro`. | Tests manuales sandbox + unit test mockeando `Transaction.all`. |
| **B4** | CloudKit container hardcoded | `iCloud.RealDev.Raskmap` debe existir en cuenta prod. | Verificar CloudKit Dashboard pre-submit. |
| **B5** | `PrivacyInfo.xcprivacy` ausente | Apple lo exige desde mayo 2024 para APIs sensibles (UserDefaults, FileTimestamp). | Generar XML declarando `NSPrivacyAccessedAPICategoryUserDefaults` razón `CA92.1`. |

### 🟠 Bugs latentes y riesgos

- **3.1 — `RaskMapView.rendererCache` sin límite**: con 200 países × 1-5 polígonos
  → 500-1000 entradas con `CGPath` rasterizado. Memory pressure en iPhone SE.
  Implementar LRU.
- **3.2 — Race condition pre-warm**: `DispatchQueue.global.async` (RaskMapView:149)
  vs delegate `mapView(_:rendererFor:)`. Race en Dictionary durante primer segundo.
- **3.3 — 26 `DispatchQueue.main.asyncAfter` en `ContentView`**: hacks de timing.
  Si el usuario navega rápido, closures sobre views inexistentes → estado stale
  o crash silencioso. Migrar a `.task(id:)` + `Task.sleep` cancelable.
- **3.4 — 234 force-unwraps**: la mayoría seguros, pero ~10-20 son bombas reales.
  Patrones a buscar: `[key]!`, `firstIndex(...)!`, `URL(string:)!`.
- **3.5 — `try?` silencioso en SwiftData**: 30+ `try? modelContext.save()`. Si
  CloudKit rechaza, el usuario no se entera y pierde la edición. Loguear vía
  `os.Logger`.
- **3.6 — `GeoJSONLoader` en main thread**: carga síncrona ~200-500ms en arranque.
  Migrar a `Task.detached`.
- **3.7 — Live Activities huérfanas**: verificar limpieza tras `wipeAllData` con
  `Activity<RaskmapTripAttributes>.activities`.

### ⚡ Performance

- **4.1 — Compilación lenta de ContentView**: 14 943 líneas → Xcode 30-60s por
  incremental. Modular reduce a 5-10s.
- **4.2 — `@Query` sin predicado**: carga toda la BD en memoria. Para usuarios
  con 500+ trips se nota.
- **4.3 — Recomputaciones por body render**: `allProximoRows`, `topVisitedFlagsString`,
  `discoveryCandidates` se invocan en cada body. Memoizar con `@State` +
  fingerprint (patrón ya usado para `tripsFingerprint`).
- **4.4 — Polígonos GeoJSON sin LOD**: una sola resolución. A zoom-out global,
  Rusia/Canadá rinden miles de vértices innecesarios. Aplicar Douglas-Peucker
  por nivel de zoom.
- **4.5 — Considerar `MKMultiPolygon`** para países archipiélago (Indonesia,
  Filipinas, Grecia) → reduce coste de delegate calls.

### 🏗 Arquitectura y deuda técnica

**5.1 — Modularización de `ContentView.swift`** (candidatos):

| Archivo nuevo | Sheets/structs a mover | Líneas est. |
|---|---|---|
| `Sheets/AddTripSheet.swift` | `AddTripSheet`, `EditTripSheet` | ~1500 |
| `Sheets/ProfileSheet.swift` | `ProfileSheet`, `MedalSlot`, `TopRegion` | ~2000 |
| `Sheets/SettingsSheet.swift` | `SettingsSheet`, sub-sheets legales | ~1500 |
| `Sheets/StatsSheet.swift` | `TransportStatsSheet`, `FlightLegsListSheet`, `AirportStatsSheet`, etc. | ~1500 |
| `Sheets/ListSheets.swift` | `StatusListSheet`, `FinalizadosListSheet`, `AllCountriesSheet` | ~2000 |
| `Sheets/RouteWizardSheet.swift` | `RouteWizardSheet`, `RoutePickerSheet` | ~1000 |
| `ViewModels/TripActions.swift` | Mutaciones de trips (saveTrip, etc.) | ~800 |

ContentView quedaría en ~3000 líneas (root + mapCore + handlers).

- **5.2 — Migrar a `@Observable` (iOS 17+)**: `ColorThemeManager: ObservableObject`
  con `@Published` es API antigua. `@Observable` macro re-renderiza solo views
  que leen la propiedad cambiada.
- **5.3 — `LocationManager.shared` como singleton**: `@StateObject private var
  locationManager = LocationManager.shared` siempre llama init. Convertir a
  `@Observable` o inyectar via `.environment(\.locationManager)`.
- **5.4 — Naming inconsistencias**: `wantToVisit` vs "próximos" vs "planned"
  intercambiables; `featuresByIso` y `allFeatures` coexisten; tres `pending*Country`
  para "país de la sheet siguiente" → consolidar a un `pendingSheet: PendingSheet?`
  con enum.

### 🎨 UX / UI

- **6.1 — Onboarding (4 pasos)** bien implementado pero `didShowOnboarding`
  se marca true en paso 1, no en paso 3 → si abandona a mitad, nunca vuelve a verlo.
- **6.2 — Empty states (~10 detectados)**: cobertura baja. Faltan en Aeropuertos
  sin vuelos, Wrapped vacío, search "Sin resultados".
- **6.3 — Confirmaciones destructivas inconsistentes**: mezcla `.alert` y
  `.confirmationDialog`. Estandarizar.
- **6.4 — Tap targets pequeños (<44pt)**: `ActionButton` country sheet, chips
  filtro transporte rondan 32-36pt. iOS HIG mínimo es 44pt.
- **6.5 — Falta feedback al guardar**: solo haptic. Añadir toast verde + animación
  de bandera entrando.
- **6.6 — Densidad informativa en home**: en iPhone SE/mini cabe justo
  (mapa + dock + flightMode + countdown + ad banner + ubicación toast). Considerar
  modo "minimal".
- **6.7 — `presentationDetents` inconsistentes**: algunos `.fraction(0.50)` con
  2 acciones; otros `.large` con 4 inputs. Auditar.

### 🎨 Sistema de diseño y paleta

**7.1 — Paleta actual (`ColorThemeManager`):**

| Token | Hex | Evaluación |
|---|---|---|
| `defaultVisited` | `#DC6647` | ✅ Terracota vibrante |
| `defaultWantToVisit` | `#00CB7C` | ⚠️ Muy saturado — vibra con terracota |
| `defaultLived` | `#5DAD6E` | ⚠️ Demasiado cercano al esmeralda — confusión |
| `defaultBucketList` | `#E5B257` | ✅ Ámbar sutil |
| Accent cobalto `#4072D4` | (hardcoded 11 sitios) | ⚠️ Debería estar centralizado |
| Onboarding blue `#53A3FE` | (hardcoded onboarding) | ⚠️ DIFERENTE del cobalto |

**7.2 — Problemas:**
- 2 azules distintos (`#4072D4` vs `#53A3FE`).
- Visited/Lived demasiado parecidos.
- Accent hardcoded 11 veces.
- Sin design tokens para neutrales (uso ad-hoc de `.systemGray3..6`).

**7.3 — Recomendación: `DesignTokens.swift`:**

```swift
enum BrandColor {
    static let accent       = Color(.sRGB, red: 64/255,  green: 114/255, blue: 212/255)
    static let accentLight  = Color(.sRGB, red: 83/255,  green: 163/255, blue: 254/255)
    static let success      = ColorThemeManager.defaultVisited
    static let pending      = ColorThemeManager.defaultWantToVisit
    static let lived        = ColorThemeManager.defaultLived
    static let bucket       = ColorThemeManager.defaultBucketList
}
enum Radius {
    static let chip: CGFloat = 10
    static let card: CGFloat = 14
    static let sheet: CGFloat = 22
}
enum Typography {
    static let titleL: Font = .custom("Satoshi-Bold", size: 24)
    static let title: Font  = .custom("Satoshi-Bold", size: 18)
    static let body: Font   = .custom("Satoshi-Regular", size: 15)
    static let caption: Font = .custom("Satoshi-Medium", size: 12)
    static let mono: Font   = .custom("Satoshi-Bold", size: 14).monospacedDigit()
}
enum Anim {
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let smooth = Animation.spring(response: 0.45, dampingFraction: 0.75)
    static let bouncy = Animation.smooth(duration: 0.5, extraBounce: 0.15)
}
```

Estado actual ad-hoc detectado: **11 valores distintos de `cornerRadius`**
(8, 10, 11, 12, 14, 16, 18, 20, 22, 24…), **15+ tamaños de fuente** (9, 10,
11, 12, 13, 14, 15, 16, 17, 18, 20, 22, 36, 44, 52, 64…), **23 `withAnimation`**
con variedad de configuraciones.

**7.4 — Paleta refinada propuesta:**

| Status | Actual | Sugerencia | Razón |
|---|---|---|---|
| Visited | `#DC6647` terracota | **`#D65B3F` siena tostado** | Más cálido, tierra explorada |
| WantToVisit | `#00CB7C` esmeralda | **`#5BA89B` verde mar** | Menos saturado |
| Lived | `#5DAD6E` salvia | **`#7B5BAB` violeta apagado** | Diferenciación total — "echar raíces" |
| BucketList | `#E5B257` ámbar | **`#F2C265` miel** | Ligeramente más suave |
| Accent | `#4072D4` cobalto | **mantener** ✅ | Funciona con la nueva paleta |

**7.5 — Iconografía**: Twemoji para banderas ✅; emojis transporte
(✈️ 🚗 🚂 🚌 🚢 🚶) inconsistentes entre iOS — considerar SF Symbols para UI
no decorativa.

### ♿ Accesibilidad

- Solo **13 `.accessibility*` annotations en 14k líneas** — crítico.
- **VoiceOver inutilizable** hoy. Cada FlagLabel necesita "Bandera de [País]".
  Mapa entero requiere `accessibilityRepresentation` con texto descriptivo.
- **Dynamic Type no funciona**: todos los textos en tamaños fijos. Migrar
  textos largos a `.font(.body)` + `.dynamicTypeSize(.medium ... .accessibility2)`.
- **Contraste**: verificar texto blanco sobre fondos coloreados (banners,
  widgets) con xScope/Stark.
- **Tap targets <44pt** en chips, picker grids — Apple bloquea fácil.

### 🧪 Tests — estado y gaps

**Actual:**
- `DaysPerCountryTests.swift` (252 L) — 9 casos ✅
- `RenderSmokeTests.swift` (112 L) — 7 tests render-no-crash ✅
- `RaskmapTests.swift` (17 L) — placeholder vacío
- UITests — boilerplate

**Gaps críticos:**
1. SwiftData migrations (snapshots de schemas).
2. CloudKit conflict resolution (mock).
3. `WrappedStats.compute()` con edge cases.
4. `FlightRoutesBuilder` todos los tipos de trip.
5. Discovery candidates (dedup, sanctioned, regiones vacías).
6. Codable round-trip (FlightInfo, TripSegment, MapQuadrant).
7. UI Tests: onboarding completo, add trip flow, export, wipe.

### 💡 Nice-to-haves priorizado

| Pri | Feature | Esfuerzo | Impacto |
|---|---|---|---|
| ⭐⭐⭐ | Localización EN | M | TAM 6% → 60% |
| ⭐⭐⭐ | Modularizar ContentView | L | Velocidad dev × 3 |
| ⭐⭐⭐ | Privacy Manifest | XS | Rechazo Apple sin esto |
| ⭐⭐ | SwiftUI Map + MapPolygon (iOS 18+) | L | Render Metal, 0 flicker |
| ⭐⭐ | DesignTokens.swift | M | Coherencia escalable |
| ⭐⭐ | Dark Mode audit completo | M | UX premium |
| ⭐⭐ | Snapshot testing real | M | Regresiones visuales |
| ⭐⭐ | Apple Watch app real | XL | Diferenciación competitiva |
| ⭐ | iPad layout (master-detail) | L | App Store featured potential |
| ⭐ | iOS 18 Lock Screen accessoryRectangular | S | Visibilidad |
| ⭐ | Share trip con preview rich (mapa) | M | Viralidad |
| ⭐ | Animar marcado (zoom + ripple) | S | Delight moment |
| ⭐ | Achievements como Live Activities | M | Engagement |
| ⭐ | Modo "competición con amigos" via CloudKit shared | XL | Diferenciador real |

### 🔥 Single ship blocker

> **No subas todavía:** `IPHONEOS_DEPLOYMENT_TARGET = 26.2` y la ausencia de
> `PrivacyInfo.xcprivacy` te van a rechazar el binario en submission. El resto
> es deuda gestionable.

---

## Cambios recientes (2026-05-11) — sesión de hotfixes UX

Sesión dedicada a pulir UX y bugs reportados por el usuario después de la
iteración integral del 2026-05-10. Trabajo encima de `remodelacion_integral_v2`.

### Banner countdown solo en modo mapa (`eef298b`)

Antes el banner "Quedan N días" aparecía también en modo vuelo
(comentario `el usuario lo pidió así` ahora obsoleto). El usuario lo
prefiere oculto para no estorbar la vista de rutas. Añadido `!flightMode`
al guard del branch del countdown.

### Widget mediano: título o país + centrado vertical (`eef298b` + `efa5ba6`)

· El row principal ahora muestra `entry.nextTitle` si existe; cae a
  `entry.nextName` (país) solo si está vacío. Alineado con Small y Large.
· Layout: header "PRÓXIMO VIAJE" + booking ref pegados arriba, bandera +
  destino centrados verticalmente (Spacer entre header y row, otro Spacer
  antes del strip "PRÓXIMOS").

### Plantillas rápidas eliminadas (`cb99023` + `efa5ba6`)

Iteración inicial: AddTripSheet tenía 4 quick-templates (Vuelo/Coche/
Tren/Bus) que pre-cargaban transporte y saltaban a step 2/3 de
AddSegmentSheet. Generaban redundancia (re-pregunta para ✈️) y placeholders
intermedios complicados. El usuario prefirió **eliminar las plantillas**
y dejar solo el botón "Añadir transporte" que abre el wizard normal
desde step 1. Eliminado:
· `quickTemplate(emoji:label:)` helper.
· Sección "PLANTILLAS RÁPIDAS" en AddTripSheet.
· `@State selectedTransport` y todo el flujo `initialTransport` de
  AddSegmentSheet (parámetro, branch en init, onAppear, placeholder en
  countriesStep, toolbar leading custom).

Cualquier flujo (añadir/editar pasado/próximo) usa ahora el wizard 1→2→3
estándar. Sin atajos.

### "Lugares por descubrir": rediseño completo (`1f18eca` + `9d0db43`)

Heurística antigua: hasta 6 sugerencias acumuladas, varias del mismo
bloque regional, ordenadas alfabéticamente por ISO (sesgo hacia AND/ALB).

Heurística nueva:
· **1 sugerencia por región**, evaluando las 9 regiones SIEMPRE (incluido
  Oceanía aunque no la hayas visitado — el usuario lo quiere así).
· Por región, candidato = unvisited cuyo bbox-center está más cerca de
  CUALQUIER país visitado globalmente (proxy de fronteras compartidas).
· **No repeticiones**: si Israel pertenece a Asia ∩ Medio Oriente, solo
  una región se lo queda. `pickedSet` excluye ya-elegidos de pools
  posteriores.
· **ISOs sancionados**: set estático `sanctionedDiscoveryISOs = ["ISR"]`.
  Israel nunca aparece como recomendación.
· Tie-breaker estable alfabético por ISO si dos candidatos están a la
  misma distancia.
· Fallback alfabético cuando no hay visitas en absoluto.

### README rewrite (`b72986f`)

El README anterior era una guía de setup inicial pre-multi-segmento
(Item.swift, 5 archivos, sin widgets/Wrapped). Reemplazado por overview
moderno con features agrupadas, stack técnico tabulado, estructura de
carpetas actualizada, estado del desarrollo apuntando a
`remodelacion_integral_v2` + CONTEXT.md, setup mínimo y legal.

### Eliminar auto-marcado por ubicación (`56a9c1f` + `3e2ea12`)

`autoMarkIfNeeded(isoCode:)` mutaba `Country.status` a `.visited` cuando
CoreLocation detectaba al usuario dentro del polígono de un país. Esto se
disparaba al detectar ubicación inicial y tras "Eliminar de la lista"
si el país coincidía con la ubicación → no podías borrar tu propio país.

Cambios:
· Función `autoMarkIfNeeded` eliminada por completo + sus 2 callers.
· La detección de ubicación ahora solo actualiza `locationIsoCode`
  (highlight visual). Sin mutación de modelo.
· Y MÁS: el highlight `isUserHere` ahora **solo se aplica si el país
  está en status `.visited`**. Si está en `.none`, `.wantToVisit`,
  `.bucketList` o `.lived`, `locationIsoCode` queda nil → sin aro.

### Optimización del mapa: solo overlays coloreados + sin cap de zoom (`a1e53f6`)

El usuario seguía viendo flicker / "pop in" de colores al hacer pan.
Cambio clave: **solo se registran como overlays los polígonos
COLOREADOS** (visited/lived/wantToVisit/bucketList si toggle activo) +
el highlight actual si es .none. Antes añadíamos los ~1000+ polígonos
(toda la GeoJSON) y MapKit los re-rasterizaba por tile en cada pan,
incluso los `.none` invisibles. Ahora MapKit solo procesa ~5-30
polígonos (los del usuario), reduciendo drásticamente el coste por tile.

Gestión dinámica del set activo:
· `Coordinator.activeOverlayIsos: Set<String>` mantiene los ISOs
  actualmente en el mapa.
· Status change `.none → coloured`: addOverlay + renderer en cache.
· Status change `coloured → .none` (sin highlight): removeOverlays +
  limpiar cache.
· Status change entre coloreados: solo `setNeedsDisplay()`.
· Highlight de un país `.none`: addOverlay temporalmente; removeOverlay
  al perder el highlight.
· Tap-detection sigue funcionando — usa `features` directamente, no la
  lista de overlays.

Además, `mapView.cameraZoomRange` eliminado: el usuario quiere zoom-out
sin tope (antes había `maxCenterCoordinateDistance: 25_000_000`).

### Wrapped: quita emoji + tipografía mayor en cuadrantes (`a5b59ac`)

· Footer del `ShareableSummaryCard`: removida la línea `Text("🗺️")` de
  52pt junto al logo. Solo queda "Raskmap" + "Tu mapa personal" centrados.
· `statCard` del `SummaryStatGrid`: número grande 40→48pt, label 11→14pt,
  sub-texto 12→15pt, padding interno 16→18pt vertical. `lineLimit(1)` +
  `minimumScaleFactor` añadidos para evitar truncado en strings largos
  (continentes, "≈ 12.345 km", etc.).

### Widget medium: "PRÓXIMOS" → "SIGUIENTES" (`9e86ce4`)

Cambio manual del usuario. El strip de banderas al pie del widget mediano
ahora se llama "SIGUIENTES" para evitar repetición con el header
"PRÓXIMO VIAJE" que va arriba.

### "Lugares por descubrir" tappable (`d02e9de`)

Las cards eran solo decorativas. Ahora son botones: al tappear una
bandera, se cierra el perfil, se centra el mapa en ese país, se aplica
el borde negro de highlight y se abre la sheet del país — el mismo flujo
que tappear directamente en el mapa.

Implementación:
· `ProfileSheet` gana `onDiscoveryTap: ((CountryFeature) -> Void)?`.
· Cada card en `discoverSection` se envuelve en `Button` con haptic light.
· `ContentView` pasa closure que: `showProfile = false` →
  `asyncAfter 0.4s` → resuelve `Country` (insertando si no existe) →
  `handleCountryTap(_)`. El delay permite a SwiftUI completar la
  animación de dismiss antes de presentar la sheet siguiente.

### Live Activity: días, no HH:MM:SS (`6b88a7a`)

Regresión introducida con `tripStartDate` + `Text(timerInterval:countsDown:)`:
el formato nativo de `timerInterval` renderiza HH:MM:SS, no días. El usuario
quiere ver "N días" como antes.

Vuelta al countdown estático basado en `daysRemaining` (Int) en ambas
vistas (lock screen banner + Dynamic Island expanded.trailing). El campo
`tripStartDate` del ContentState queda en su sitio (compat con estado
serializado existente) pero ya no se usa en el render. La app actualiza
la Live Activity cada vez que entra en foreground, suficiente para
granularidad de día.

---

## Cambios recientes (2026-05-10/11) — rama `remodelacion_integral_v2`

Iteración integral sobre App Store readiness, performance, UX y nice-to-have.
La rama contiene 9 commits incrementales con todos los items del análisis A·B·C·D
de la sesión anterior (ver [Roadmap exhaustivo](#roadmap-pendiente--an%C3%A1lisis-exhaustivo)
en versiones anteriores de este doc), seguidos de tres commits de hotfixes
(Swift 6 strict concurrency + 3 bugs reportados por usuario).

### Commit 1 (`7f53cef`) — App Store readiness + perf base

**App Store hard/soft blockers**:
- `SubscriptionSheet`: botón "Restaurar compras" prominente con icono y
  estilo capsule (Apple lo exige para Non-Consumable IAP).
- Ajustes: sección "Datos" con botón "Borrar todos mis datos" + alert con
  doble confirmación. Limpia SwiftData (Trip/Country/PersonalAward),
  AppStorage (35 keys), App Group del widget, snapshot del mapa de vuelo
  en disco y termina Live Activities. Cumple GDPR Art. 17.

**Bugs**:
- #6 `@AppStorage didShowOnboarding` evita re-onboarding tras reset iCloud.
- #20 mailto `ContactSheet` con `CharacterSet` tight (quita `&=?#+` del
  `urlQueryAllowed`) — subject/body con esos chars no rompen el parser.
- #21 `MKMapSnapshotter` cancela snapshotter previo antes de iniciar nuevo
  + descarta callback si ya no es el activo. Antes los callbacks async se
  solapaban y escribían imágenes obsoletas.

**Performance**:
- `featuresByIso` pre-indexado (Dictionary). `topVisitedFlagsString` y
  `allProximosFlagsString` ya no hacen O(n²) `features.first(where:)`.
- `tripsFingerprint` reemplaza `onChange(of: trips.count)`. Detecta cambios
  de fechas/transport/iso de trips existentes — banner countdown y snapshot
  del widget se actualizan al editar.
- `FinalizadoTripDetailSheet.daysByCountry` cacheado por `tripFingerprint`
  en `@State`. Antes recomputaba en cada render del scroll.

**UX**:
- `AddSegmentSheet` smart default: nuevo tramo arranca el día siguiente al
  último tramo existente (no el primero).
- Quick chips de fecha en step 3 (Mañana / Próx. semana / En 2 sem. para
  futuro; Hoy / Ayer / Hace 1 sem. para pasado).
- TextField username: `textInputAutocapitalization(.never) +
  autocorrectionDisabled + submitLabel(.done)`.

### Commit 2 (`05181b7`) — bugs + UX viajes + km volados

**Bugs**:
- #3 `Country.status` se resetea automáticamente al borrar el último trip
  (`cleanupZeroXVisitedStates` ahora se llama en cada `handleTripsCountChange`).
- #18 `cleanupOrphanChildTrips` elimina children con `segmentGroupID` cuyo
  primary ya no está en `trips`. Se llama después de cada cambio.

**UX**:
- `RouteWizardSheet` "Ruta de vuelta diferente" pre-rellena
  `returnDeparture` con el último IATA del outbound y `returnFinalDest` con
  el origen — patrón típico de round-trip asimétrico, evita re-tipear.
- `FinalizadosListSheet`: swipe-action "Duplicar" + `confirmationDialog`
  → copia el trip + sus children con +365 días, promociona el país a
  wantToVisit. Mantiene segments/airports/airlines/flightDetails.
- `FinalizadosListSheet`: chips de filtro de transporte (solo muestra los
  transports presentes en los rows). Vacío con filtro → "Quitar filtro".
- `FlightInfoSection`: botón "Aplicar clase y posición a todos los tramos"
  cuando hay >1 leg y el primero ya tiene datos. No replica seat number
  (siempre es distinto). Haptic light al aplicar.

**Stats**:
- `TransportStatsSheet`: card "KM VOLADOS" con suma haversine de todos los
  segmentos ✈️ (ida + vuelta) + trips legacy con coords resueltas. Pares
  con IATA desconocido se saltan sin romper el total.

**Haptics**:
- `UINotificationFeedbackGenerator().notificationOccurred(.success)` al
  guardar trip (`saveTrip` + `performEditSave`) y al completar `wipeAllData`.
- Light haptic al aplicar clase/posición a todos los tramos.

### Commit 3 (`f67955b`) — export + share + notifs + tour

**Export CSV/JSON (GDPR Art. 20)**:
- `ExportDataSheet` con selector de formato y botón "Generar y compartir".
- JSON: estructurado completo con todos los campos del modelo (countries +
  trips + segments + airports + airlines + visitedLayoverISOs).
- CSV: tabular una fila por trip.
- Escribe a temporary directory + lanza `UIActivityViewController`.
- Acceso desde Ajustes → "Exportar mis datos" en sección Datos.

**Share trip individual**:
- Toolbar trailing button en `FinalizadoTripDetailSheet`.
- Genera texto con título + fechas + días por país + footer Raskmap.
- `UIActivityViewController` para Mensajes/WhatsApp/Mail/etc.

**Notificaciones locales**:
- `TripNotifications` enum con `requestAuthorization`, `reschedule`, `cancelAll`.
- 3 recordatorios por trip futuro: 7d, 1d, 0d. Todos a las 9:00 AM hora local.
- Dispara `reschedule` en `handleTripsCountChange` si toggle activo.
- Toggle "Recordatorios de viaje" en Ajustes → Widgets (gratis, no Pro).
- Pide permiso al activar; si denegado, vuelve a apagar el toggle.
- Wipe cancela todas + reset del toggle.

**Tour guiado en onboarding (4 pasos)**:
- 0: username (existente)
- 1: passport (existente, "Continuar" → step 2)
- 2: tour categorías Visitados/Próximos/Quiero
- 3: tour final perfil/modo vuelos/widgets → "Empezar a explorar"
- Indicador de progreso con 4 puntos en parte inferior.

### Commit 4 (`cf55226`) — tests + LA real-time + heatmap + búsqueda global

**Tests** (`RaskmapTests/DaysPerCountryTests.swift`):
- 9 casos para `daysPerCountry`: round-trip simple, trip de 1 día,
  Hong Kong/Macao/China multi-tránsito, Macedonia/Kosovo con escala SRB
  ida+vuelta, children skipped con primary, children huérfanos, excursión
  single-day, layover legacy, segments frontera. Cada test con expected
  counts comentados.

**Live Activity countdown real-time**:
- `ContentState` gana `tripStartDate: Date?` (opcional para retrocompat).
- `Foundation` import añadido en ambos targets de `RaskmapActivityAttributes`.
- Lock screen banner + Dynamic Island expanded usan
  `Text(timerInterval: Date()...start, countsDown: true)` cuando
  `tripStartDate` está presente. SwiftUI repinta el contador sin requerir
  push updates de la app — ahorra batería + actualización exacta al segundo.
  Fallback al `daysRemaining` estático si nil.
- `ContentView.startOrUpdateLiveActivity` inyecta `banner.dateFrom` en
  `tripStartDate`.

**Heatmap anual**:
- `YearTravelView.yearlyHeatmap` añadido bajo el contador "Total de vuelos".
- 12 cuadritos (E F M A M J J A S O N D) coloreados según número de trips
  primarios cuyo `dateFrom` cae en ese mes. Intensidad 0.20-1.00
  proporcional al máximo del año. Mes vacío con borde 0.5pt sin fill.
- Solo visible si hay al menos 1 trip ese año.
- Accesibilidad: cada cuadrito con label "<inicial>: <count> viajes".

**Bug #5 — tap-spam entre sheets**:
- `scheduleSheetTransition()` reemplaza `DispatchQueue.asyncAfter` en
  `CountryBottomSheet` handlers. Usa `Task.sleep` cancelable: si el usuario
  tappea otro país antes de los 350ms, cancela la transición previa.
- `@State sheetTransitionTask` mantiene la referencia.
- Aplica a `onAddPastTrip`, `onAddNextTrip`, `onEditTrips`.

**Búsqueda global**:
- `searchSheet` ahora muestra dos secciones: "Viajes" y "Países".
- Sección Viajes solo aparece con query no vacía. Busca en `trip.title` y
  nombre localizado del país. Top 10 ordenados por `dateFrom` desc.
- Tap en trip futuro → `editingFutureTrip`; trip pasado → `bannerTappedCountry`.
- Países: query vacía → agrupa por letra; con query → lista plana.
- Title: "Buscar país" → "Buscar". Prompt: "Buscar país o viaje…".

### Commit 5 (`c7ae663`) — templates + descubrir + comparativa + dark toast

- `AddTripSheet`: 4 quick-templates (Vuelo / Coche / Tren / Bus) en grid
  2×2 visibles solo cuando no hay tramos. Pre-cargan transporte y abren el
  `AddSegmentSheet` directamente, saltando step 1 del wizard.
- Profile: nueva sección "Lugares por descubrir" — scroll horizontal con
  hasta 6 países sin visitar pero geográficamente cercanos. Heurística:
  por cada región (Europa/Asia/etc.) con ≥1 visitado, propone los primeros
  ISOs sin visitar. Filtrado por countingMode.
- Profile `YearTravelView`: card de comparativa "vs <año anterior>" con
  delta de viajes y países. Flecha verde/roja según diferencia. Visible
  solo si `availableYears` contiene el año previo.
- Location toast y Help toast: `.regularMaterial` → `.thickMaterial`
  + border 0.5pt strokeBorder `Color.primary.opacity(0.08)`. Mejora
  contraste sobre fondos oscuros.

### Commit 6 (`HEAD`) — nice-to-have: share polish + animaciones + render tests

**Share wrapped enriquecido**:
- Texto del share incluye stats (`totalTrips` / `totalCountries`) +
  hashtags `#Raskmap #Travel<year> #Viajeros`. Optimizado para Twitter/X,
  Instagram (en mensaje), WhatsApp, Mail, etc.

**Animaciones más cinematográficas en wrapped**:
- Slide insertion: `.move(edge: .bottom) + .opacity + .scale(0.97)` en
  lugar del scale 0.95 plano. Sensación tipo Apple Music wrapped.
- Slide removal: `.move(edge: .top) + .opacity` para que la salida sea
  vertical también.
- `advance()` y `goBack()` cambian de `.easeInOut(0.3)` a
  `.smooth(0.45, extraBounce: 0.05)` + haptic `.soft`.
- Background color animation también pasa a `.smooth(0.55)`.

**Render smoke tests** (`RaskmapTests/RenderSmokeTests.swift`):
- 7 tests "render-no-crash" usando `ImageRenderer`:
  - `FlagLabel` con bandera estándar y con fallback (🌐).
  - `TwemojiFlag` con ISO inválido cae a fallback sin crash.
  - `FlightInfo` Codable round-trip preserva estructura completa.
  - `FlightInfo` legacy decode (sin outboundLegs/returnLegs) sintetiza leg.
  - `FlightInfo.hasAnyData` detecta los 3 paths (bookingRef / outbound / return).
  - `FlightLegInfo` empty.
- No requieren `swift-snapshot-testing` — solo verifican que vistas críticas
  rendericen sin nil y que el modelo Codable no se rompa con cambios futuros.

### Commit 7 (`9b5e0a3`) — fix Swift 6 strict concurrency + ViewBuilder accidental

Compilación de los Commits 1-6 disparó dos clases de errores en Swift 6
con `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`:

- **ViewBuilder accidental**: `matchingTrips: [Trip]` (no es View) tenía
  `@ViewBuilder` heredado por copy-paste. Removed.
- **FlightInfo Codable cross-isolation**: la conformancia sintetizada por
  Swift 6 hereda el aislamiento del contexto (`@MainActor` por default del
  proyecto), y las computed properties `flightInfo` / `flightInfoRaw` de
  `@Model class Trip` son nonisolated. Marcamos `FlightLegInfo` y
  `FlightInfo` como `nonisolated struct ... Sendable` con extensión
  `nonisolated extension ...: Codable` con init/encode manuales.
- **writeExport/buildJSON/buildCSV**: marcados `nonisolated private static`
  para poder llamarse desde `Task.detached`.

### Commit 8 (`8ccbf90`) — fix Swift 6: ExportFormat enum nonisolated

Después de Commit 7 quedaban dos errores en `ExportDataSheet`:

- `Main actor-isolated property 'format' cannot be accessed from outside of the actor`
- `Main actor-isolated property 'ext' can not be referenced from a nonisolated context`

Causa: el enum `ExportFormat` quedaba `@MainActor` por default del proyecto,
así que `format` (la @State) y `format.ext` no eran accesibles desde
`Task.detached`. Fix: `nonisolated enum ExportFormat: ... Sendable`.

### Commit 9 (`cc09cbe`) — fix 3 bugs reportados por usuario

**Bug A — "Eliminar de próximos" no eliminaba al tap directo**:
- En `updateCountryStatus(country:newStatus:)`, cuando el usuario tappea un
  país en próximos y elige "Eliminar de la lista", se llamaba con
  `newStatus = .none`. El código solo borraba trips PASADOS, detectaba el
  trip futuro existente y reanudaba `country.status = .wantToVisit` →
  efectivamente "deshacía" la eliminación.
- Fix: distinguimos por `previousStatus`. Si `.wantToVisit → .none`, purga
  todos los trips del país (también futuros), sin posibilidad de
  resurrección. El path original ("desmarcar visitado") mantiene su lógica
  de preservar trips futuros y degradar a `.wantToVisit`.

**Bug B — Conteo "Avión" desincronizado**:
- `TransportStatsSheet.counts` cuenta `max(1, outLegs + retLegs)` por
  segmento ✈️ (suma al menos 1 aunque el segmento no tenga aeropuertos
  rellenos) y filtra por `pastTrips` (`effectiveEndDate <= today`).
- `FlightLegsListSheet.legs` solo añadía rows si `airports.count >= 2`,
  ignoraba el caso `>2 unique airports` (generaba 1 row resumen en lugar
  de `max(1, totalTouches/2)`) y filtraba por `dateFrom <= today` (incluye
  in-progress). Resultado: title del sheet mostraba menos vuelos que la
  barra "Avión" de la pantalla anterior.
- Fix:
  - Unifico filtro a `effectiveEndDate <= today` (mismo que `pastTrips`).
  - Para ✈️ segments sin aeropuertos: row sintética con flag `isSynthetic`.
  - Para legacy con `>2 unique airports`: genera `max(1, totalTouches/2)`
    rows alternando consecutivos en lugar de 1 row.
  - Para legacy con 0/1 airports: `max(1, totalTouches/2)` rows sintéticos.
  - Render: filas sintéticas muestran icono `airplane` + título del trip
    en lugar de "🌐 → 🌐  — → —".

**Bug C — Flicker del mapa al hacer pan**:
- Pre-warm en background solo cubría polígonos COLOREADOS. Cuando un
  polígono `.none` entraba en vista durante pan, MapKit caía al fallback
  `rendererFor(_:)` que creaba renderer en frío, y el path se computaba
  lazy en el primer `draw` → "pop in" visible de color/render.
- Varias transiciones de estado (highlight, location update, status change)
  hacían `removeOverlay + addOverlay`, lo que invalida todos los tiles del
  bbox del polígono y provoca flicker.
- Fix:
  - Pre-warm en background ahora cubre TODOS los polígonos (no solo
    coloreados), con queue `.utility` para no contender con main thread.
    Cache siempre lleno → MapKit nunca crea renderers on-demand durante pan.
  - Todos los `removeOverlay + addOverlay` (4 sitios: status change,
    highlight on, highlight off, location update) reemplazados por
    `setNeedsDisplay()` sobre el renderer cacheado. Redraw localizado sin
    invalidar tiles.

---

## Cambios recientes (2026-05-03)

Iteración con foco en (a) consistencia entre perfil/widgets para órdenes y
fallbacks, (b) el algoritmo `daysPerCountry` reescrito por tercera vez para
soportar escalas como días compartidos, (c) Swift 6 strict concurrency para
`FlightInfo`, y (d) afinado UX de modo vuelo + cuadrantes pluricontinentales.

### Algoritmo `daysPerCountry` — reescritura completa (Trip.swift)

**Modelo conceptual nuevo (`_DaySet` por día, no `_DayClaim`)**: cada día
puede pertenecer a MÚLTIPLES países simultáneamente cuando hay tránsito o
escalas — antes era 1 día = 1 país (mejor priority gana). Ahora `_DaySet`
tiene `isos: Set<String>` y la regla es:
- Prioridad menor REEMPLAZA por completo el set.
- Prioridad igual AÑADE el iso al set existente (set unión).
- Prioridad mayor: ignora.

**Prioridades**:
- 100 — segmento no-✈️ multi-día. Reemplaza ambient del primary.
- 200+len — trip hijo (`isSegmentChild`).
- 1000+len — trip primario "ambient".

**Reglas clave**:
1. **Segmentos ✈️ NO reclaman su rango como destino** — sus fechas son los
   días del vuelo (ida/vuelta), no la estancia. El ambient del trip cubre
   esos días. Antes contábamos el destino entero del segmento ✈️ y eso
   pisaba excursiones a otros países (caso HKG-MAC-CHN-HKG → daba HKG=11).
2. **Excursión de día (single-day)**: si `seg.dateTo == nil` o
   `seg.dateTo == seg.dateFrom`, el destino se reclama con `tripPriority`
   (mismo prio que ambient → set unión). Resultado: el día cuenta tanto
   para el destino como para el primary del trip. Caso Macedonia + Kosovo
   ida/vuelta mismo día → MKD=7, KOS=1 (no MKD=6, KOS=1).
3. **Estancia multi-día**: `dateFrom < dateTo` → prio 100 (reemplaza).
   Casos como bus a MAC 16-17 dentro de viaje a HKG → MAC se queda con
   16-17, HKG ambient pierde esos días.
4. **Layovers ✈️**: se reclaman tanto en `segDateFrom` como `segDateTo`
   (ida y vuelta) con `tripPriority` → set unión con primary. Caso
   Macedonia con escala BEG ida+vuelta → SRB=2 días, MKD sigue contando
   esos 2 días también.
5. **Layovers no-✈️**: solo en `segStart` con `tripPriority` (set unión).
6. **Layovers de trip legacy** (`t.visitedLayoverISOs` sin segments):
   reclamados en `tFrom` y `tTo` con `tripPriority`.
7. **Children no compiten con su primary**: si un trip primary cubre el
   rango con sus segments y existen children del mismo `segmentGroupID`,
   los children se SALTAN en `daysPerCountry`. Antes los children (trips
   de 1 día con prio 200+1=201) ganaban por prioridad y robaban días al
   primary, dando counts incorrectos (típicamente el destino del primary
   perdía 2 días por trip).

**Verificación con casos reales** (en log del usuario):
- HK 15-25 con bus MAC 16-17, pie CHN 17-21, tren HKG 21-25: HKG=6, MAC=2, CHN=5 ✓
- Macedonia 12-18 con escala BEG ida+vuelta + Kosovo día 14: MKD=7, SRB=2, KOS=1 ✓

### `FlightInfo` — Codable manual nonisolated (Swift 6)

**Problema**: Swift 6 inferia que la conformancia `Codable` sintetizada de
`FlightInfo` era `@MainActor`-isolated por estar en el mismo módulo que
`@Model class Trip`. Cualquier llamada desde computed properties del @Model
disparaba "Main actor-isolated conformance ... cannot be used in nonisolated
context" — error compilación en Swift 6 strict mode.

**Solución en 3 pasos**:
1. Mover `FlightInfo` y `FlightLegInfo` a fichero propio `FlightInfo.swift`
   (fuera de Trip.swift para no heredar isolation del @Model).
2. Marcar ambos struct como `Codable, Equatable, Sendable` y proporcionar
   conformancia Codable MANUAL (init/encode explícitos con `CodingKeys`)
   en `extension`. La sintetizada hereda contexto, la manual no.
3. Helpers nonisolated `decodeFlightInfo(from:)` y `encodeFlightInfo(_:)`
   como funciones libres en FlightInfo.swift. `Trip.flightDetails` getter/
   setter delega en estas helpers — el JSON encoder/decoder se invoca
   siempre desde nonisolated context.

`Codable` para `FlightLegInfo` también manual con init `decodeIfPresent` para
ser tolerante a campos faltantes en datos legacy.

### Bug fallback emoji en `proximos` del perfil

**Síntoma**: en el perfil, año actual, sección Próximos, el emoji 🌐
(fallback de territorio sin bandera, p.ej. Chipre del Norte) aparecía en
posición incorrecta — entre Brasil y Argentina en vez de al final tras Chipre.
El widget grande sí mostraba el orden correcto.

**Causa raíz**: `ProfileSheet.proximos` ordenaba países wantToVisit por
`country.plannedDate` directamente. Para países pluricontinentales o segmentos
hijos, `plannedDate` puede quedar STALE — lo seteamos al guardar el segmento
pero si el usuario edita el viaje varias veces o el segmento se reasigna,
queda con la fecha de una iteración anterior.

**Fix**: `proximos` ahora calcula `nextDate(country)` buscando primero la
fecha más temprana de cualquier trip futuro del país (incluyendo children),
y solo cae a `country.plannedDate` como fallback. Misma fuente de verdad
que `allProximosFlagsString` del widget.

### Modo vuelo — pulido

**Botón mapa**: el icono `map.fill` cuando `flightMode == true` usaba color
cobalto fijo. Cambiado a `.primary` → blanco en dark mode, negro en light.

**Contador encima de los botones**: `flightFilterRow()` muestra un Text
"X vuelos finalizados" / "X vuelos próximos" centrado encima del slider.
Cuenta tramos reales contando ida + vuelta + repetidos: 30× MAD-BCN ida y
vuelta = 60 vuelos.

**Etiqueta del slider**: "Visitados" → "Finalizados" para coherencia con
el resto del perfil.

### Cuadrantes Mi Mapa — pluricontinentales libres

**Cambio de criterio del usuario**: antes filtrábamos pluricontinentales
(CYP, RUS, TUR, etc.) en cuadrantes según `multiContinentRaw`. Ahora el
usuario quiere que el filtro NO se aplique — un país pluri puede estar en
cuadrantes de cualquier zona, independiente de la asignación. Cyprus
puede estar en cuadrante de Europa Y de Asia simultáneamente.

`AchievementKind.filterCandidatesForZone()` ahora devuelve los isos sin
filtrar. La asignación pluri sigue afectando a los achievements de
continentes (`adjustSet`) pero NO a los cuadrantes de usuario.

**Conteo all incluye territorios sin bandera**: `AddQuadrantSheet` ahora
muestra como elegibles los territorios sin `flagEmoji` cuando el modo de
conteo es `.all` (249 territorios). Antes los filtraba con `flagEmoji != nil`.
Render con `FlagLabel(emoji: feature.flagEmoji ?? "🌐", size: 17)` para que
el fallback se vea uniforme.

**Pluri ISOs siempre seleccionables**: `AddQuadrantSheet.flaggedFeatures`
ahora incluye `Self.pluriIsoCodes` (CYP, RUS, TUR, AZE, GEO, KAZ, EGY) en
TODAS las zonas, no solo las que coinciden con `zone.isoCodes`. Así el
usuario puede meter Cyprus en un cuadrante de Asia incluso si geográficamente
no está en `Asia.isoCodes`.

### Widget grande pantalla principal

- "ÚLTIMOS VISITADOS" → "ÚLTIMOS" (más corto, mismo significado).
- `prefix(5)` en `topVisitedFlags` → `prefix(9)` para Próximos y Últimos
  (uniformidad).
- `flagStrip(title:)` width 100 → 70 para acomodar etiquetas más cortas.

### Widget mediano

- Strip de próximos: `prefix(6) size 17 spacing 5` → `prefix(9) size 15 spacing 4`
  para que quepan 9 banderas con spacing uniforme.
- `FlagLabel` fallback (🌐, ✈️) ahora tiene `frame(width: size, height: size)`
  para que el bounding box coincida con la versión Twemoji — antes los
  fallbacks tenían tamaño distinto y dejaban "huecos raros" entre flag 5 y 6.

### Widget grande de vuelos (mapa) — `RaskmapFlightWidget`

**Implementación**: nuevo widget large que muestra una captura del mapa con
la ruta del próximo vuelo dibujada como línea geodésica (gran-círculo).

**Generación del snapshot** (`WidgetDataWriter.syncNextFlightSnapshot`):
1. Bounding region calculada con sample paramétrico de 64 puntos a lo
   largo de la geodésica entre dep y arr (no straight-line lat/lng porque
   los grandes círculos se desvían mucho — sin esto el snapshot saldría
   mal cuadrado para vuelos transcontinentales).
2. Padding 1.6× en lat/lon delta para que la línea no quede tangente al
   borde.
3. `MKMapSnapshotter` con `mutedStandard` map type, escala 2x.
4. Dibujado custom encima del snapshot: línea geodésica 96 puntos en
   cobalto 0.95 alpha, line width 3pt round caps. Marcadores 14pt en
   cada extremo (anillo blanco + relleno cobalto).
5. PNG escrito al App Group container como `next_flight_map.png`.
6. `WidgetCenter.shared.reloadAllTimelines()` tras escribir.

**Helper en ContentView `nextFlightAirportsAny()`**: busca el primer trip ✈️
futuro de TODOS los trips (no solo el del banner del próximo viaje), para
que el widget de mapa siempre encuentre algo aunque el banner sea de un
viaje no-✈️.

**Layout del widget**:
- Fondo: snapshot del mapa o gradiente nocturno (cobalto + azul medianoche).
- Overlay con info del vuelo (solo si `nextDays >= 0`):
  - Pill IATA `MAD → BCN` arriba a la derecha.
  - HStack inline con bandera, título del viaje (o nombre del país) y
    countdown `• N días`.
  - Padding bottom 38 para mantener el bloque en la posición visual de
    cuando había una tercera línea de countdown debajo.
- Si la imagen no está aún (snapshotter async la primera vez), muestra
  el gradiente con la info del vuelo encima — NO "Sin próximo vuelo"
  como hacía la primera versión que solo chequeaba `imagePath`.

### Tipografía de widgets unificada

Todos los números/textos en widgets pasan a `Satoshi-Bold/Medium/Regular`
desde `Palatino-Bold` y `system(size:)`. Mantienen `system(size:)` solo los
emojis (✈️, 🗺️) que necesitan render del sistema. Aplica a SmallView,
MediumView, LargeView, FlightMapWidgetView.

### `FlightFilterSlider` etiqueta + contador

Etiqueta "Visitados" → "Finalizados". Función `flightLegsCount(filter:)`
nueva: cuenta tramos reales (not unique routes) con `airports.count - 1` por
segmento ✈️ + `tripAirports.totalTouches / 2` para legacy. Counts ida + vuelta
+ duplicados (30× MAD-BCN = 60).

### Bug visual del CountryBottomSheet (drag indicator)

Reescrito el header del sheet con `padding(.top, 36)` adicional + `frame(width: 80, height: 80)` en el contenedor del flag para que el drag indicator del sheet no tape la bandera Twemoji. `isoA2` se pasa explícitamente para evitar fallback Text→Twemoji conversion lag en el primer render.

Bottom "Cerrar" eliminado — el drag indicator + sheet dismiss bastan.

### `SubjectiveCategoriesSheet` — reorder + sheet en vez de fullScreenCover

Antes `.fullScreenCover` (presentación distinta al resto). Ahora `.sheet`
estándar (consistente con MedalleroSheet padre). Botón "Editar" en toolbar
trailing → modo reorder con List + `onMove`. Persistencia del orden en
`@AppStorage("subjectiveCategoriesOrder")` como JSON `[String]` de raw
values. `decodeOrder()` con seen-set asegura que cualquier nueva categoría
añadida en el código aparezca al final tras un upgrade sin perder el orden
del usuario.

### `FlowLayoutCentered` — perRow configurable

Año actual del perfil: 5 banderas por línea (cabe en mitad del ancho del
perfil con divisor central). Años pasados: 10 por línea (ancho completo).
Antes había `prefix(10)` que cortaba; ahora `perRow` divide pero muestra
TODAS las banderas (sin truncar).

### Bug split filter pluri en cuadrantes UE (revertido)

Habíamos añadido un filtro que excluía pluricontinentales según asignación
de zona. Causaba que CYP desapareciera del cuadrante UE default cuando se
asignaba CYP a Asia. Revertido: `filterCandidatesForZone` ahora devuelve
los isos sin tocar — el usuario decide libremente. Mantiene la flexibilidad
para ediciones futuras (función sigue ahí, solo no filtra).

### Splash + loading overlay rediseñados

`SplashView`: gradiente cobalto profundo (#121B3A → #1E336A → #406EC9), pin
de mapa centrado en círculos concéntricos, "RASKMAP" tracking 8, subtítulo
"TU MUNDO, EN UN MAPA" tracking 2. Animación: pin cae con spring + scale
fade-in. Halo radial cobalto detrás del pin. Footer mantiene v.1.0 + año.

`loadingOverlay()` (mientras carga GeoJSON) replica el estilo de splash
con misma paleta y pin centrado. Antes era system background con globo
emoji y "Raskmap" Satoshi-Bold 38. Ahora coherente con la marca.

### `ContactSheet` rediseñada

Antes: TextEditor único de 140-180pt + counter 150 chars + botón "Enviar".

Ahora:
- Header con icono envelope + "Escríbenos" + subtítulo.
- Pills "PARA: raskmap_soporte@icloud.com" y "ASUNTO: ..." pre-rellenados
  visibles read-only.
- Editor del mensaje con label "MENSAJE", placeholder con ejemplo de
  estructura ("Bug encontrado / Aeropuerto que falta / Sugerencia"),
  border focus en cobalto, 200pt min height, contador 600 chars.
- Botón "Enviar mensaje" con icono paperplane, fondo cobalto.
- `presentationDetents([.large])` con drag indicator.

### Botón Ayuda en pantalla principal

Esquina superior izquierda (espejo del botón modo vuelo). Mismo formato:
44×44 circular, regularMaterial, shadow. Icon `questionmark`. Tap abre
overlay con icono `questionmark.circle.fill` cobalto + texto "Si te
faltan aeropuertos, aerolíneas o has tenido un bug, repórtalo en
**Ajustes › Contacto**." + botón "Entendido".

### Próximos en perfil — sheet local en vez de root

Antes `onProximosTap = { statusListFilter = .wantToVisit }` triggereaba un
sheet en el root, lo que requería cerrar el perfil primero (parpadeo).
Ahora ProfileSheet tiene `@State proximosShown` + sheet local que presenta
StatusListSheet con handlers locales (modelContext + countries + trips
disponibles vía init). `editingProximoTrip` y `pendingProximoCountryForDate`
también son sheets locales del perfil, con dismissal coordinado vía
DispatchQueue.main.asyncAfter para evitar conflicto sheet-sobre-sheet.

### `CountryBottomSheet` — toggle Próximos como las otras categorías

`onAddNextTrip` ahora actúa como las otras (visited/bucketList): si el país
ya está en wantToVisit, abre alert de eliminación en vez de añadir otro
trip. ActionButton label cambia a "🔜 Añadido a próximos" cuando
`isProximo == true`.

### Toggle "He vivido aquí" — info button

Junto al texto "He vivido aquí" en el sheet de visitas manuales, botón
`info.circle` que abre overlay explicando "Marca este país como uno en el
que has vivido. Aparecerá una 🏠 junto a su contador en la lista de
visitados y se contabiliza como visitado en todas las stats." Mismo formato
que el info de "Contador manual".

### Confirm card al guardar — rueda de carga 3s

`confirmCardContent` ahora tiene `@State isSaving: Bool`. Al pulsar
"Guardar" se desactivan ambos botones, se muestra ProgressView en el
botón Guardar y tras 3s `DispatchQueue.main.asyncAfter` se ejecuta
`onSave`. UX: da sensación de "trabajo en marcha", evita doble-tap accidental.

### Bug días por trip transit between segments (Hong Kong - Macao - China - Hong Kong)

Trip 15-25 con seg bus MAC 16-17, seg pie CHN 17-21, seg tren HKG 21-25.
Resultado correcto ahora: HKG=6 (15, 21, 22, 23, 24, 25), MAC=2 (16, 17),
CHN=5 (17, 18, 19, 20, 21). Días 17 y 21 cuentan para ambos países (transit
shared). Ver detalles en sección "Algoritmo daysPerCountry — reescritura".

### Países en más de un hemisferio → Países plurihemisferiales

`MultiHemisphereSheet.navigationTitle` renombrada para coherencia con
"plurihemisferiales" usado en otros sitios.

### Lock al sheet de abecedario — top alignment

`FlagAlphabetSheet` (sheet con todas las banderas A-Z) cuando no hay Pro:
overlay del candado pasa de `frame(maxHeight: .infinity)` (centrado) a
`alignment: .top` con `padding(.top, 32)` — el candado y "Función Pro" se
ven al instante sin tener que scroll-down.

### Aerolíneas/aeropuertos añadidos

- SkyUp MT (Malta): IATA "SQP", country "MT".
- Chisinau Internacional: IATA "RMO", country "MD" (alternativo a KIV).
- Foz do Iguaçu: IATA "IGU", country "BR" (separado de IGR Argentina).

### Bug seats x2 / x3 stats

`TransportStatsSheet.topSeats` y `topSeatPositions` filtraban
`pastTrips` sin excluir `isSegmentChild`. Children copiaban `seg.flightInfo`
del primary, así que un asiento "7E" rellenado aparecía 1× primary + 1×
child = 2× en stats (3× con 2 children). Fix: `where !trip.isSegmentChild`.

### Bug países pluricontinentales en cuadrantes — historia

3 iteraciones del usuario:
1. "Hazlo dinámico" (filtra según asignación). Implementado con `filterCandidatesForZone`.
2. "Cyprus tiene que aparecer en cuadrante UE default aunque esté asignado a Asia". Excepción por título del cuadrante (contiene "unión europea").
3. "Cyprus debe poder participar libremente en cualquier cuadrante donde lo meta el usuario". Filtro completamente removido. Documentado en sección "Cuadrantes Mi Mapa".

### Roadmap pendiente — análisis exhaustivo

#### A. UX flujo viajes/tramos (ranking impacto)

1. **Quick-add path**: pantalla única con país + fechas + transporte + toggle "ida y vuelta?". Wizard largo solo desbloqueado con botón "Personalizar". Hoy 80% de viajes simples requieren los 3 pasos completos del wizard.
2. **Templates de viaje**: 4 botones grandes en AddTripSheet — *Vuelo simple*, *Round-trip con escala*, *Road-trip*, *Multi-tramo* — pre-rellenan estructura típica.
3. **Inline edit en EditTripSheet**: cada segmento expandible (chevron) sin reabrir AddSegmentSheet. Botón ✏️ solo abre wizard si el usuario lo pide explícitamente.
4. **Smart defaults entre tramos**: nuevo tramo defaultea `dateFrom = previousTramo.dateTo ?? previousTramo.dateFrom + 1 día`, mismo destino del previo como origen.
5. **Búsqueda de aeropuerto por ciudad**: "Milán" → ofrece BGY, MXP, LIN. Hoy hay que conocer el IATA.
6. **"Aplicar a todos los tramos"** en FlightInfoSection: si rellena clase=Turista para ida, ofrece propagar al resto.
7. **Preview/timeline del viaje** antes de guardar: lista visual cronológica con bandera + transporte + fechas.
8. **Botón "Duplicar viaje"** en cards de finalizados.
9. **"Inverso"**: crear vuelta de un viaje pasado en 1 tap.
10. **Auto-detect round-trip**: si último aeropuerto = primero, marcar `roundTrip` automáticamente.
11. **Drag-to-reorder segmentos** en EditTripSheet (reusar infra de mapQuadrants).
12. **Confirm card con default `Aceptar todo`** + tooltip explicativo del stepper.
13. **"Hoy" / "Mañana" / "Próxima semana"** chips en date picker.
14. **Layovers en cualquier transporte** (no solo ✈️): bus que cruza países.
15. **Importar PNR / archivo .ics** (medio/largo plazo).

#### B. Mejoras generales

**Rendimiento**:
- Migrar a `@Observable` (iOS 17+). `@Query` re-fetches causan caída de FPS al cerrar sheets.
- Romper ContentView (>12k líneas) en 6-8 ficheros.
- Cachear `daysPerCountry` por `tripID` en @State.
- Pre-indexar `featuresByIso` como dict singleton (hoy `topVisitedFlagsString` es O(n²)).
- Snapshot del widget de vuelo invalidar solo si dep/arr IATA cambian.
- `setNeedsDisplayIn(rect:)` solo en región visible al cambiar color (parcialmente hecho).

**Funcionalidad**:
- Búsqueda global tipo Spotlight (países, ciudades, viajes, aerolíneas).
- Filtros lista finalizados (transporte, año, país, aerolínea).
- Export CSV/JSON desde Ajustes (cumple GDPR portabilidad + sirve como backup).
- Notificaciones (24h y 2h antes, check-in 24h antes para vuelos).
- Heatmap anual estilo GitHub.
- Comparativa años en wrapped.
- Mapa con km volados (great-circle entre IATAs).
- Sugerencias de países cercanos a uno visitado.
- Compartir viaje individual (no solo wrapped).
- Tour guiado en primer launch.

**Estética**:
- Haptics consistentes (medium save, light toggle, soft swipe).
- Skeleton screens en lugar de overlay con globo.
- `.matchedGeometryEffect` entre badge → status sheet.
- Live Activities con countdown en tiempo real.
- Onboarding con animación de globo + chips de países.

**Pro features de valor**:
- Personalización avanzada del widget (4 layouts).
- Mapa con capa satélite/política/dark.
- Backup encriptado iCloud separado.
- Múltiples perfiles (familia/trabajo).
- Export PDF "memoria de viajes" — book anual.

**Arquitectura**:
- Tests unitarios para `daysPerCountry` (algoritmo más sensible).
- Snapshot tests para layouts críticos.
- OSLog estructurado en lugar de print() condicionales.
- Localización completa EN.
- `Sendable` strict en todos los modelos.

**Accesibilidad**:
- VoiceOver labels en todos los iconos (faltan en flightModeButton, helpButton).
- Dynamic Type comprobar Satoshi escala bien.
- Respetar `accessibilityReduceMotion` en wrapped.
- Contraste cobalto #4072D4 cerca del límite WCAG AA.

#### C. Bugs / checks de testing

| # | Severidad | Bug |
|---|-----------|-----|
| 1 | Alta | `FinalizadoTripDetailSheet.daysByCountry` recomputa en cada scroll → FPS drop. Cachear en @State. |
| 2 | Alta | `cachedNextBanner` se actualiza solo en `onChange(of: trips.count)` — no detecta cambios de fecha de un trip existente. |
| 3 | Media | Borrar último viaje de país visited no resetea automáticamente `Country.status`. |
| 4 | Media | EditTripSheet con dateFrom > dateTo (error usuario) puede crashear con date arithmetic negativo. |
| 5 | Media | `selectedCountry` y `pendingDateCountry` pueden coexistir (tap-spam) → segundo sheet en cola. |
| 6 | Media | Onboarding se vuelve a mostrar tras reset iCloud (username vacío). Necesita flag local `didShowOnboarding`. |
| 7 | Baja | TextField username sin `.textInputAutocapitalization(.words)` ni `.autocorrectionDisabled()`. |
| 8 | Baja | `RangeDatePicker` no respeta locale del usuario para primer día de semana. |
| 9 | Baja | Live Activity colgada si app cerrada forzosamente — falta cleanup en `applicationWillTerminate`. |
| 10 | Baja | Confirm card aparece detrás del teclado si TextField tenía focus. |
| 11 | Visual | CountryBottomSheet en iPhone SE: flag 64pt + título + 4 botones no caben en `.fraction(0.50)`. |
| 12 | Visual | Wrapped 9:16 deja barras laterales en iPhone Pro Max. |
| 13 | Visual | Drag indicator del sheet del país tapa parte superior del flag (parcialmente arreglado). |
| 14 | Visual | Banner countdown se solapa con dock cuando `menuPosition == "top"`. |
| 15 | Visual | Material `.regularMaterial` casi invisible sobre fondos oscuros. |
| 16 | Visual | `FlowLayoutCentered` con 9+ banderas en SE puede desbordar. |
| 17 | Datos | `effectiveEndDate` puede devolver `dateFrom` o `distantPast` según fallback. |
| 18 | Datos | Trip child huérfano (primary borrado) sigue contando. Cleanup periódico. |
| 19 | Datos | `tripAirports` con count negativo crashea fórmulas. Clamp `>= 0`. |
| 20 | Datos | Booking ref con caracteres no-ASCII rompe URL del mailto:. Encode con `.urlPathAllowed`. |
| 21 | Concurrency | `MKMapSnapshotter` callbacks se solapan — escribe el último que termine, no el último pedido. Cancelar previo. |
| 22 | Persistencia | `legacyVisitedLayoverISOs` puede contener huérfanos si destination cambia. Intersect no en todas las rutas. |
| 23 | Wrapped | `WrappedStats` recomputa en `.task` aunque exista `cachedStats`. Guard solo evita render del slide. |

**Smoke checks pre-release** (15 puntos):
1. Crear viaje pasado simple → guardar → aparece en finalizados, perfil, suma 1 contador.
2. Crear viaje pasado con escala visitada → escala como país visitado + 1 día.
3. Crear viaje próximo → marca como Próximos, banner countdown, widget.
4. Editar viaje pasado: cambiar fecha → todos los stats recalculan.
5. Borrar viaje → países asociados reevalúan.
6. Cambiar modo conteo → contadores y % actualizan en mapa, perfil, widget.
7. Asignar país pluricontinental a otra zona → cuadrantes y % regiones recalculan.
8. Toggle "He vivido aquí" → 🏠 en lista, suma 1 visita.
9. Live Activity arranca con próximo viaje, countdown, mata al cancelar Pro.
10. Widgets pequeño/mediano/grande/vuelo se actualizan en App Group.
11. Sheets cierran sin warning "multiple sheets".
12. CloudKit sync entre 2 dispositivos en <30s.
13. Modo offline: app abre, muestra todo, no crashea.
14. Cambiar sistema a inglés → fechas y formatos se adaptan.
15. Dynamic Type XL → textos no se cortan.

#### D. App Store readiness

**Hard blockers**:

| Item | Estado | Acción |
|------|--------|--------|
| Privacy Policy URL pública | Falta hostear `docs/` en GitHub Pages (mds preparados) | Crear repo, activar Pages, pegar URL |
| Apple Developer License $99/año | Pendiente | Pagar antes de todo lo demás |
| iCloud + CloudKit container | Pendiente activar en Capabilities | `iCloud.com.jaime.raskmap` |
| App Group | En código sí, en Capabilities pendiente | Activar en cada target |
| Push Notifications capability | Pendiente (necesario CloudKit) | Activar |
| In-App Purchase capability | Pendiente | Activar |
| IAP product en App Store Connect | Pendiente | `com.raskmap.pro.lifetime` Non-Consumable |
| App Privacy questionnaire | Pendiente | Declarar Data Not Collected |
| Age Rating | Pendiente | 4+ |
| App icon 1024×1024 sin transparencia | Hay icon, verificar formato | sRGB sin canal alpha |
| Screenshots todos los tamaños | Pendiente | 6.9" iPhone 16 Pro Max + 13" iPad |
| Build TestFlight | Pendiente | Probar IAP en sandbox |

**Soft blockers**:
- **Restore Purchases button** en SubscriptionSheet (Apple lo exige para Non-Consumable). Falta.
- **Account deletion / "borrar todos mis datos"** desde Ajustes (limpia SwiftData + CloudKit local + AppStorage). Falta.
- **Localización mínima**: hoy todo en español hardcoded. Declarar solo `es` o añadir `en`.
- **Permisos justificados**: `Info.plist` con `NSLocationWhenInUseUsageDescription` claro. Verificar texto.
- **Crash-free builds**: smoke tests de los 15 checks anteriores.
- **No menciones a otras tiendas / formas de pago externas** (Patreon, Stripe...).
- **No strings tipo "TODO" o lorem ipsum visibles**.
- **Watch app target visible pero placeholder vacío**: completar o quitar del scheme.

**Política de Privacidad — verificar copy in-app == copy pública**:
Apple compara texto in-app vs URL pública. Si difieren → rechazo. Si en algún
momento añades AdMob (mencionado en CONTEXT.md como pendiente decidir),
actualizar AMBAS copies + App Privacy questionnaire.

**Atribuciones técnicas (verificar visibles in-app)**:
- Twemoji CC-BY 4.0 ✓
- Natural Earth (Public Domain — opcional pero recomendable)
- OpenFlights (ODL — atribución requerida)
- OurAirports (Public Domain — opcional)
- SF Symbols (Apple license, no requiere atribución)

**Performance reviewers prueban**:
- Tiempo desde tap hasta interactivo: <3s en iPhone 12.
- 60fps consistentes en scroll de lista de países.
- No memory leaks tras 10 min de uso.
- Battery <5% en 30 min uso normal.

**Orden recomendado**:
1. Pagar license + activar capabilities (1 día).
2. Hostear docs/ en GitHub Pages (15 min).
3. Crear IAP en App Store Connect (1h).
4. Añadir botón "Restaurar compras" + "Borrar todos mis datos" (2h código).
5. Smoke test los 15 checks en device físico (1 día).
6. Capturas + descripción + age rating + privacy questionnaire (medio día).
7. TestFlight con 3-5 testers reales mínimo 1 semana.
8. Submit → review típicamente 24-48h.

Más probable rechazo inicial: **falta de Restore Purchases** y/o
**discrepancia entre política pública y App Privacy questionnaire**.

---

## Cambios recientes (2026-04-27)

Iteración larga sobre QA visual + bugs de propagación de estado. Tres bloques
de cambios: ajustes de widget/UI/UX, propagación correcta de Quiero→Próximos
para multi-país, datos extra en aeropuertos/aerolíneas/asientos.

### Task 1 — Widget grande: "ÚLTIMOS VISITADOS" en vez de "MÁS VISITADOS"/"NUEVOS"

**Cambio:** la franja de "MÁS VISITADOS" del widget grande ahora se llama
"ÚLTIMOS VISITADOS" y se ordena por **fecha del último viaje finalizado**
(más reciente a la izquierda) en vez de por días totales pasados. Eliminada
la franja "NUEVOS" (era duplicada visualmente: usaba el mismo dataset
invertido).

**Sites:**
- `ContentView.swift` `topVisitedFlagsString` (~línea 384) reescrito: itera
  trips, registra `lastDateByIso[t.isoCode] = max(end, prev)` solo para fechas
  pasadas, ordena visited countries por `lastDateByIso[iso] desc, isoCode asc`.
- `RaskmapWidget.swift` `LargeView` (~línea 481): elimina la 3ª `flagStrip`
  ("NUEVOS"), renombra "MÁS VISITADOS" → "ÚLTIMOS VISITADOS".
- `flagStrip()` helper: aumenta `frame(width: 84 → 100)` + `lineLimit(1) +
  minimumScaleFactor(0.8)` para que el título más largo quepa.

### Task 2 — `Países en más de un hemisferio` → `Países plurihemisferiales`

`MultiHemisphereSheet.navigationTitle` (~línea 11307) renombrado. Usuario
prefería el término técnico-conciso. La fila del menú en Ajustes y el
overlay informativo siguen llamándose como antes (más descriptivos).

### Task 3 — Pantalla `FlagAlphabetSheet` sin Pro: candado arriba

**Bug:** sin Pro, el overlay de "Función Pro" (lock + texto) se centraba
verticalmente con `frame(maxWidth: .infinity, maxHeight: .infinity)` sobre
una `ScrollView` vacía visualmente. Quedaba flotando en mitad de la pantalla
sin contexto.

**Fix (`ContentView.swift` ~línea 11093):**
- `.overlay { ... }` → `.overlay(alignment: .top) { ... }`.
- Eliminado `maxHeight: .infinity`, sustituido por `padding(.top, 32)`.
- Resultado: el candado y "Función Pro" aparecen anclados arriba, justo
  debajo del navigation bar — más cerca del título y deja claro que el
  contenido completo está bloqueado.

### Task 4 — `SubjectiveCategoriesSheet`: presentación + reorden

**Bugs reportados:**
1. Se presentaba con `fullScreenCover` (corte abrupto de pantalla completa);
   el resto de sheets de "Premios personales" usan `sheet` modal estándar.
2. No había forma de reordenar las 11 categorías (Sobrevalorados, Infravalorados,
   Más sucios, etc.).

**Fix (`ContentView.swift`):**
- Cambio `.fullScreenCover(isPresented: $showSubjectiveCategories)` →
  `.sheet(...)` (~línea 10570). Misma transición visual que MedalleroSheet.
- `SubjectiveCategoriesSheet` rediseñado:
  - Nuevo `@AppStorage("subjectiveCategoriesOrder")` con `[String]` JSON-encoded
    de los `rawValue` de cada `SubjectiveCategory`.
  - Helpers `decodeOrder()` (lee + appendea categorías nuevas no presentes en
    el storage para forward-compat) y `saveOrder(_ cats:)`.
  - Toolbar trailing: botón "Editar"/"Listo" alterna `@State isReordering`.
  - En modo reorden: `List` con `.environment(\.editMode, .constant(.active))`
    + `.onMove` que persiste el orden tras cada drag. Filas simplificadas
    (solo emoji + título, sin medallas) para legibilidad.
  - Modo normal: `ScrollView` con las `categoryRow(cat)` completas, ahora
    iterando `decodeOrder()` en vez de `SubjectiveCategory.allCases`.

### Task 5 — `AddSegmentSheet`: pregunta en pasado para viajes ya hechos

**Cambio (`AddSegmentSheet.swift` ~línea 282):**
```swift
Text(isForFuture ? "¿Cómo vas a viajar?" : "¿Cómo viajaste?")
```
Antes era siempre "¿Cómo vas a viajar?" (presente/futuro), incluso cuando
el wizard se abría desde un viaje pasado. Coherente con `isForFuture` que
ya se usa en otros toggles del mismo wizard ("¿Harás parada en?" vs
"¿Visitaste alguna escala?").

### Task 6 — Aerolínea SkyUp MT añadida

`Raskmap/airlines.json` (al final): `{"iata": "SQP", "name": "SkyUp MT",
"country": "MT"}`. Aerolínea maltesa subsidiaria de SkyUp Airlines (UA).

### Task 7 — Aeropuertos Chisinau (RMO) + Foz do Iguaçu (IGU) añadidos

`Raskmap/airports.json` y `Raskmap/airport_coords.json`:
- **RMO** "Chisinau Internacional" (MD) — segundo IATA usado para el
  internacional de Chișinău; mismas coords que `KIV` (46.9277, 28.931).
- **IGU** "Foz do Iguaçu" (BR) — lado brasileño de las cataratas
  (las cataratas argentinas tienen `IGR`/Puerto Iguazú). Coords
  (-25.6003, -54.485).

### Task 8 — Rueda de carga de 3s al confirmar viaje

**Cambio (`confirmCardContent`, `ContentView.swift` ~línea 7503):**
- Nuevo `@State isSaving: Bool = false`.
- El botón "Guardar" del confirm-card (visitConfirmCard / editVisitConfirmCard
  / plannedConfirmCard) al pulsarse:
  1. Setea `isSaving = true` (deshabilita ambos botones, sustituye texto
     por `ProgressView().tint(.white)`).
  2. `DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { onSave() }`.
- "Cancelar" también queda `.disabled(isSaving)` para evitar interrumpir
  a mitad la transacción de guardado.

Razón: SwiftData + recálculo de logros + sync widget hace que el guardado
sienta instantáneo pero ejecute trabajo en background; los 3 s dan tiempo
visual al usuario y previenen taps accidentales en pantallas siguientes
mientras la propagación termina.

### Task 9 — Bug: países en Quiero/none no pasan a Próximos en multi-país

**Reproducible:** Chipre (`.bucketList` o `.none`) y Chipre del Norte
(`.bucketList` o `.none`) marcadas como Quiero. Crear viaje futuro a Chipre
con segmento ✈️ (Chipre) + segmento 🚶 (Chipre del Norte). Antes:
- Chipre se marcaba `.wantToVisit` ✓ (vía `onSave` del root).
- Chipre del Norte se quedaba en su estado anterior — el path de creación
  de child trips solo gestionaba el caso `firstDate <= today` (marcar
  visitado). Para fechas futuras NO había código que tocara el `Country`
  del segment-child.

**Fix (`saveTrip` `AddTripSheet.swift` ~línea 6643 + `performEditSave`
`EditTripSheet.swift` ~línea 9114):**
- Branch `else` para fechas futuras: si el `Country` existe y NO está ya
  visitado/lived, lo promociona a `.wantToVisit` y registra
  `plannedDate/plannedDateTo/transport` del segmento si es la fecha más
  cercana (`firstDate < countryRecord.plannedDate!`).
- Si el `Country` no existe (territorio sin record previo), lo crea con
  `Country(name:, isoCode:, status: .wantToVisit)` y los datos del segmento.

Resultado: para el caso reportado, ambos países (Chipre + Chipre del Norte)
quedan en Próximos con sus respectivos transportes (✈️ y 🚶).

### Task 10 — Bug: asientos cuentan N veces según número de vuelos

**Reproducible:** trip con 2 vuelos (segmentos ✈️ a 2 países diferentes).
Rellenar asiento "7E" solo en uno. Stats mostraban "7E x2". Con 3 vuelos,
"7E x3". Etc.

**Diagnóstico:** los segment-children copian `tripSegments = [seg]` del
primario completo (incluyendo `seg.flightInfo`). `topSeats` y
`topSeatPositions` (`TransportStatsSheet`, ~líneas 7829 y 7855) iteraban
TODOS los `pastTrips` sin filtrar `isSegmentChild`, así que cada copia del
seg sumaba +1 al contador del asiento.

**Fix:** añadir `where !trip.isSegmentChild` al loop. Otros stats
(topAirports, topAirlines) ya tenían este filtro — los asientos eran el
único hueco.

### Task 11 — Bug visual: fronteras entre países visitados parecen más gruesas

**Reproducible:** con dos países adyacentes ambos visitados (ej. Chequia +
Alemania), la frontera entre ellos parece visualmente ~1pt; con uno visitado
y otro no, parece ~0.5pt; entre dos visitados con vértices coincidentes
(ej. Chequia + Eslovaquia, dataset Natural Earth), parece ~0.5pt. Inconsistente.

**Causa:** `applyStyle` (`RaskMapView.swift` ~línea 350) seteaba
`strokeColor = black 0.35α, lineWidth = 0.5` para todos los polígonos
coloreados. Cada polígono pinta su borde — donde dos vértices coinciden,
los dos strokes se solapan visualmente y se ven igual de finos; donde no
coinciden (gap sub-píxel en geometría), los dos strokes pintan píxeles
adyacentes y la línea total parece ~1pt.

**Fix:** eliminar el stroke de polígonos coloreados no resaltados. La
diferencia de color de relleno entre países adyacentes ya crea el límite
visual; sin stroke no hay solapamiento posible.

```swift
} else if highlighted {
    renderer.strokeColor = UIColor.black.withAlphaComponent(0.85)
    renderer.lineWidth   = 1.0
} else {
    renderer.strokeColor = UIColor.clear
    renderer.lineWidth   = 0
}
```

Resultado: todas las fronteras visitado-visitado se ven uniformes (sin
stroke); el contorno negro solo aparece al hacer tap (highlighted) sobre
un país.

### Task 12 — `FinalizadosListSheet`: título por país con más días

**Cambio:** cuando un trip tiene varios países (segmentos), la fila del
listado de finalizados ahora muestra el país donde el usuario pasó **más
días** (en lugar del `trip.isoCode` primario). Empate → primer país por
orden alfabético de ISO A3.

**Implementación (`ContentView.swift` ~línea 2310):**
- Nuevos helpers que aceptan `iso: String` (en vez de `Country`):
  `displayName(for: iso)`, `flagEmoji(for: iso)`, `isoA2(for: iso)`.
- Helper `mainCountryIso(for row:)`: usa `daysPerCountry(trips: [trip])`,
  busca el max, ordena empates por ISO A3 asc, devuelve el primero.
  Fallback a `row.country.isoCode` si el trip no tiene days computables.
- El `ForEach` de la lista calcula `mainIso = mainCountryIso(for: row)` y
  pasa ese iso a las helpers de display (flag + name).
- Mensaje del confirmation dialog de eliminar también usa el `mainIso` para
  el país mostrado.

Razón: para un trip que pasó 1 día en Chipre y 6 días en Chipre del Norte,
mostrar "Chipre" era engañoso; ahora muestra "Chipre del Norte".

### Task 13 — `FinalizadoTripDetailSheet`: días por país

**Cambio:** la sheet de detalle del viaje finalizado ahora incluye una
sección nueva "DÍAS POR PAÍS" debajo de los tramos. Lista cada país
involucrado en el trip con su contador de días, ordenado por días desc
(tiebreak alfabético por iso).

**Implementación (`ContentView.swift` ~línea 2480):**
- Computed `daysByCountry: [(iso: String, days: Int)]`:
  - Si `row.trip == nil` (Country.plannedDate sin Trip object), atribuye el
    rango entero al `row.country.isoCode`.
  - Si hay trip, usa `daysPerCountry(trips: [trip])` y mapea a tuplas
    ordenadas.
- Sección renderizada con `RoundedRectangle(cornerRadius: 14)` + filas
  `[TwemojiFlag + nombre + Spacer + "X días"]` separadas por hairlines.
  Usa la pluralización "1 día"/"X días".

Razón: con trips multi-país el desglose de días era invisible; el usuario
quería ver el reparto exacto. Ya estaba calculado por `daysPerCountry` para
otros usos (widget, wrapped); aquí se reutiliza.

## Cambios recientes (2026-04-26 · iteración 2)

Segunda tanda del día, sobre los bugs anteriores: dedup de toggles de
escala, ruta cronológica al guardar, animación simultánea en wrapped y
ajustes de UX en la sección legal.

### Task 8 — Persistencia + UI de escalas (refactor consolidado)

**Bugs reportados:**
1. Editar trip MAD-ARN ida + ARN-AMS-MAD vuelta y marcar Países Bajos como
   escala visitada NO marcaba el país como visitado en el flujo legacy
   non-segment. El segment-based sí funcionaba (children + `country.status`),
   pero el path legacy solo persistía `trip.visitedLayoverISOs` y nada más.
2. Al re-editar el mismo trip aparecían DOS toggles para el mismo país de
   escala (uno bajo IDA y otro bajo VUELTA), confuso por diseño explícito
   anterior.

**Fix 1 — `AddSegmentSheet.deriveFlightCountries()`:**
- Combina escalas de IDA + VUELTA en una sola lista deduplicada por ISO.
  `outboundLayoverChoices` pasa a ser la lista única; `returnLayoverChoices`
  queda como `@State` vacío para no romper call-sites externos.
- `excludedISOs` usa `destinationISO` LOCAL (no `@State destinationIso`)
  para evitar reads stale dentro del mismo render pass.
- UI step 3: una sola sección **"¿Visitaste alguna escala?"** sin
  separador IDA/VUELTA. `layoverSection(title:)` con title opcional
  (nil omite el header).
- Banderas de las escalas pasan a `FlagLabel` (Twemoji).

**Fix 2 — `EditTripSheet` flujo legacy (mismo refactor):**
- `legacyOutboundLayovers` deduplicada single source; `legacyReturnLayovers`
  vacío. `legacyLayoverSection(title:)` con title opcional.
- `deriveLegacyFlightCountries` combina IDA + VUELTA con `seen` set
  excluyendo país de salida y destino.

**Fix 3 — `EditTripSheet.performEditSave` legacy: child trips para escalas:**
- Por cada escala marcada como visitada se crea un child Trip de 1 día
  (`dateFrom = dateTo = trip.dateFrom`) con `segmentGroupID` y
  `isSegmentChild=true`. Esto:
    - Hace que la escala aparezca en la lista de viajes del país.
    - Si el viaje es pasado (`dateFrom <= today`), fuerza
      `country.status = .visited` y limpia `plannedDate*`.
    - Combinado con `daysPerCountry` (que stake-a `t.visitedLayoverISOs`
      con prio 50), suma exactamente 1 día en el contador.
- Limpia children previos antes de re-crear → des-togglar elimina.
- Se inserta DESPUÉS del bloque "Delete old children" para no auto-borrarse.

**Cobertura final:**
| Flujo | Antes | Después |
|---|---|---|
| AddSegmentSheet (nuevo) | toggle ✓ | toggle único deduplicado ✓ |
| AddSegmentSheet (existente) | sin re-abrir wizard | tap card → wizard ✓ |
| EditTripSheet legacy | sin toggle | toggle único + persistencia + child trips ✓ |
| AddTripSheet | usa AddSegmentSheet | igual ✓ |

### Task 9 — Aeropuertos en orden cronológico al guardar

**Problema:** trips round-trip MAD-KWI-DXB se mostraban como "KWI-DXB-MAD"
en pantallas que leen `trip.tripAirports` (legacyAirportRoute en
FinalizadoTripDetailSheet, route preview en EditTripSheet legacy, etc.).

**Diagnóstico:** al guardar, `trip.tripAirports` se construía desde:
- `apC.map { ... }` → orden hash arbitrario del `Dictionary`, o
- `confirmAirports.map { ... }` → orden alfabético del confirm-dialog UI.
Ambos perdían la secuencia real del vuelo.

**Fix (`Raskmap/ContentView.swift`):**
- `AddTripSheet.saveTrip` (~6446) y `EditTripSheet.performEditSave` (~8829):
  construir `apOrder` iterando segmentos por dateFrom y dentro de cada
  segmento ida → vuelta. Primer iata visto gana (`seenIatas: Set<String>`).
- Para legacy non-segment: usa `localAirports + localReturnAirports`
  (orden del wizard, ya cronológico).
- El confirm-dialog mantiene su orden alfabético solo para la UI del
  diálogo (donde tiene sentido para que el user encuentre fácil). Al
  guardar usamos los **counts** del dialog combinados con el **orden** de
  `apOrder`. Defensivo: si el user añade un iata en el dialog que no
  está en segments, se appendea al final.

Resultado: `trip.tripAirports = [{MAD,2}, {KWI,2}, {DXB,2}]` →
`legacyAirportRoute` rendea `"MAD → KWI → DXB  /  DXB → KWI → MAD"`.

⚠️ Trips ya guardados con orden alfabético siguen así hasta re-guardar.

### Task 10 — Bonus +1 al aeropuerto de escala visitada

**Problema:** al marcar el toggle de escala visitada para SAW en MAD-SAW-KWI
ida + KWI-SAW-MAD vuelta, el confirm-dialog mostraba SAW=2 (toques físicos
ida + vuelta). El usuario quería **3** (toques + 1 bonus por la visita real).

**Diagnóstico:** la lógica antigua (en `prepareConfirmation` y
`prepareEditSaveConfirmation`) tenía un patrón confuso:
```swift
let sameLayIATAs = outInter.intersection(retInter)
for ap in seg.airports { apC[ap.iata] += ap.count }
for ap in seg.returnAirports {
    if seg.visitedLayoverISOs != nil && sameLayIATAs.contains(ap.iata) {
        let iso = ...
        guard vlISOs.contains(iso) else { continue }  // ← skip si no visitado
    }
    apC[ap.iata] += ap.count
}
```
Saltaba el toque de vuelta de un IATA si era escala-en-ambas-direcciones
y el país NO estaba visitado. Resultado dependía del toggle de forma
inconsistente: visitado=2, no-visitado=1.

**Fix (`AddTripSheet.prepareConfirmation` ~6423 +
`EditTripSheet.prepareEditSaveConfirmation` ~8795):**
```swift
// Toques naturales: cada aparición del IATA cuenta una vez.
for ap in seg.airports       { apC[ap.iata, default: 0] += ap.count }
for ap in seg.returnAirports { apC[ap.iata, default: 0] += ap.count }
// Bonus +1 por cada IATA de escala cuyo país esté visitado. Un solo
// bonus por IATA aunque aparezca en ida y vuelta.
let outInter = seg.airports.dropFirst().dropLast().map(\.iata)
let retInter = seg.returnAirports.dropFirst().dropLast().map(\.iata)
var bonusedIATAs: Set<String> = []
for iata in outInter + retInter where bonusedIATAs.insert(iata).inserted {
    let a2 = ...
    guard let iso = ..., vlISOs.contains(iso) else { continue }
    apC[iata, default: 0] += 1
}
```

Resultado:
- SAW marcado: 2 toques + 1 bonus = **3** ✓
- SAW no marcado: 2 toques + 0 bonus = **2** (consistente con toques reales,
  antes daba 1 al saltar el lado de vuelta).

### Task 11 — Wrapped: meses empatados aparecen a la vez

**Problema:** en "TUS MESES MÁS VIAJEROS" (slide del wrapped anual),
cuando varios meses estaban empatados al máximo, la animación tenía un
delay escalonado `.delay(0.15 + Double(i) * 0.1)` que hacía que cada mes
apareciera uno tras otro, dando sensación de "alternancia".

**Fix (`YearWrappedSheet.swift` ~1218):**
- Delay fijo `.delay(0.15)` para todos los meses. ForEach pasa a usar
  `_, m` (no necesitamos el índice). Resultado: todos los meses aparecen
  simultáneamente con la misma animación spring.

### Task 12 — `LegalInfoSheet` con Twemoji + atribución

**Helper nuevo `FlagAwareLongText` (`TwemojiFlag.swift`):**
- Variante multi-línea de `FlagAwareText`. Usa interpolación
  `Text(Image("flag_XX"))` para componer un único `Text` que respeta line
  wrapping nativo de SwiftUI Text. La versión con `HStack` rompía párrafos.
- API: `FlagAwareLongText(text:, font:, foreground:)`.
- Si el texto no tiene banderas, cae a `Text` plano sin overhead.

**`LegalInfoSheet`** (`Raskmap/ContentView.swift` ~5586):
- `Text(content)` → `FlagAwareLongText(text: content, font: .palatino(.body))`.
- Conserva `.multilineTextAlignment(.leading)` y `frame(maxWidth: .infinity, alignment: .leading)`.
- Decisión final: el contenido legal **NO lleva banderas** (el user las
  consideraba ruido visual). Las añadimos brevemente y luego se eliminaron.
  El helper se queda preparado para futuras adiciones sin overhead.

**Atribución Twemoji añadida al bloque "Atribuciones":**
La licencia CC-BY 4.0 exige reconocer autoría + enlazar a la licencia.
```
· Iconos de banderas: Twemoji, originalmente © Twitter Inc. / X Corp.
  y mantenido actualmente por la comunidad en github.com/jdecked/twemoji.
  Distribuido bajo licencia CC-BY 4.0 (creativecommons.org/licenses/by/4.0).
  Los gráficos de las banderas no han sido modificados.
```
Cubre: autor original (Twitter/X) + mantenedor actual (jdecked/twemoji) +
licencia + indicación de no-modificación. App Store Review-ready.

### Task 13 — Widgets medium/large: rellenar el espacio vacío

**Problema reportado:**
- Widget mediano: el bloque "PRÓXIMO VIAJE" se quedaba pequeño con espacio
  vacío debajo y a la derecha (entre flag y columna derecha).
- Widget grande: bajo "MÁS VISITADOS" había un `Spacer(minLength: 0)` que
  dejaba toda la mitad inferior del widget vacía.

**Investigación paralela — print(0.5) en consola:**
Usuario reportó ver "0.5" en la consola de Xcode. Búsqueda exhaustiva
(`grep -rn print|debugPrint|os_log|Logger|dump|.print(\)` en
`Raskmap/`, `RaskmapWidget/`, watch targets) → solo 3 sites con `print`,
todos con strings explícitas de error de SwiftData o Live Activity.
**Ningún `print(0.5)` en el código** — debe ser un log del sistema
(WidgetKit/MapKit/SwiftUI). Pendiente de pegar la línea exacta para cazarlo.

**Fix Widget Medium (`RaskmapWidget/RaskmapWidget.swift` `MediumView` ~248):**

| Elemento | Antes | Después |
|---|---|---|
| Bandera | 40pt | **52pt** |
| Nombre destino | 16pt | **19pt** |
| Contador "X DÍAS" | 15/10pt | **17/11pt** |
| Línea de fecha | — | **"vie · 15 may"** 10pt opacity 0.6 |
| Booking ref | — | **"· #ABC123"** 9pt opacity 0.55 en el header |
| Strip PRÓXIMOS | sin label | **con label "PRÓXIMOS"** + flag 15→17pt + spacing 4→5 |
| Columna derecha | 116pt | **104pt** (más respiro a la izquierda) |
| VStack spacing | 6 | 8 |

`formattedNextDate` usa `DateFormatter` con `EEE · d MMM` (locale `es_ES`)
sobre `entry.nextDateFrom`. Datos ya en el `RaskmapEntry` — no hay cambio
en `WidgetDataWriter`.

**Fix Widget Large (`LargeView` ~355):**

1. Bloque superior crece — bandera 54→60pt, nombre 22→24pt, días 38→42pt.
   Línea de fecha bajo el nombre (igual que medium).
2. **Tercer flag-strip nuevo "NUEVOS"** debajo de "MÁS VISITADOS" usando
   `String(entry.topVisitedFlags.reversed())` — los menos visitados al
   inicio del string suelen ser los más recientes, así que rellena con
   datos relevantes sin requerir nueva clave en el App Group.
3. **Footer fijo** que reemplaza el `Spacer(minLength: 0)`:
   ```swift
   HStack {
       Text(entry.mode.shortLabel)              // "ONU" / "ONU+OBS" / "TODOS"
       if !entry.nextBookingRef.isEmpty {
           Text("· PNR \(entry.nextBookingRef)")
       }
       Spacer()
       Text("RASKMAP")  // tracking 2.0, opacity 0.45 — firma suave
   }
   ```
   Separado del bloque de flag-strips por un divider `0.5pt opacity 0.18`.

Resultado: el widget grande ahora tiene 4 zonas balanceadas (próximo
viaje · stats · 3 flag-strips · footer) en vez de 3 zonas + área vacía.

## Cambios recientes (2026-04-26)

Tanda de 6 bugs de QA — todos sobre flujos de edición de vuelos, rollout
Twemoji y consistencia del contador de días.

### Task 1 — Persistencia per-leg de asiento/clase en `EditTripSheet`

**Problema reportado:** "Próximos → editar viaje → TRAMOS → chevron del segmento ✈️
→ editores IDA y VUELTA separados → mete '12A ventanilla' en ida, '20C pasillo' en
vuelta → guarda → reabre → solo veo una asignación, la otra desapareció."

**Diagnóstico:**
- `EditTripSheet.segmentFlightInfoBinding(for:)` (`ContentView.swift` ~8495)
  filtra al setear: `tripSegments[idx].flightInfo = newValue.hasAnyData ? newValue : nil`.
- Dentro de `FlightInfoSection`, `outboundBinding` / `returnBinding` (líneas
  ~5387–5411) hacían DOS escrituras separadas a través del `@Binding info`:
  ```swift
  while info.outboundLegs.count <= idx { info.outboundLegs.append(FlightLegInfo()) }
  info.outboundLegs[idx][keyPath: kp] = newValue
  ```
  Cada statement es un get-modify-set independiente. La primera escritura
  pasaba un `FlightInfo` con `[FlightLegInfo()]` vacío → `hasAnyData == false`
  → `tripSegments[idx].flightInfo = nil`. La segunda lectura veía `FlightInfo()`
  vuelto a vacío y la mutación con keypath se perdía o crashaba.
- `ensureLegsSized()` y `migrateLegacyAndResize()` tenían el mismo patrón:
  varias mutaciones encadenadas a través de `info` que pasaban estados
  intermedios "vacíos" por el filtro.

**Fix (`Raskmap/ContentView.swift`):**
- `outboundBinding`/`returnBinding` (~5387–5411): single round-trip pattern:
  ```swift
  set: { newValue in
      var current = info
      while current.outboundLegs.count <= idx { current.outboundLegs.append(FlightLegInfo()) }
      current.outboundLegs[idx][keyPath: kp] = newValue
      info = current
  }
  ```
- `ensureLegsSized()` (~5353): trabaja sobre `var current = info`, escribe
  `info = current` solo si cambia.
- `migrateLegacyAndResize()` (~5365): inline ensure-size + migración legacy
  → escala los escalares al primer leg → escribe una sola vez al final con
  `if current != info { info = current }`.

Resultado: el filtro `hasAnyData` se evalúa una sola vez por keystroke con el
`FlightInfo` completo (incluyendo el seat recién tipeado), así que ambos
asientos persisten correctamente al guardar.

### Task 2 — Twemoji: rollout en perfil, wrapped, premios y cuadrantes

**Problema reportado:** los twemojis no salen en preview de perfil
(próximos/finalizados año actual + años pasados), premios personales, lista
personal, títulos de cuadrante de Mi Mapa ni en el resumen anual.

**Helper nuevo `FlagAwareText` (`Raskmap/TwemojiFlag.swift`):**

Para títulos free-form (cuadrante, premio personal, lista personal) donde el
usuario puede mezclar texto y banderas. Parsea el string en runs `[.flag(iso),
.text(s), …]` por scalar regional-indicator y los renderiza en HStack mezclando
`TwemojiFlag` y `Text(...).font(.foreground)`. API:

```swift
FlagAwareText(text: "🇪🇸 España",
              font: .palatino(.caption, weight: .bold),
              size: 14,
              foreground: .secondary)
```

**Sites convertidos:**
- `ContentView.swift` `FlowLayoutCentered` (~6923): `Text(emoji).font(.system(size: 22))`
  → `FlagLabel(emoji: e, size: 22)`. Es el grid de banderas en la card "Finalizados/Próximos"
  del perfil para el año seleccionado y para años pasados.
- `ContentView.swift` `quadrantSlot` (~9502): `Text(q.title).font(.palatino(.caption, weight: .bold))`
  → `FlagAwareText(text:, font:, size: 14)`. Permite que un cuadrante titulado
  "🇪🇸 ibéricos" muestre la bandera como twemoji.
- `ContentView.swift` `awardSlot` (~9981–10003): título + 3 medallas (oro/plata/bronce)
  ahora usan `FlagAwareText` con `.palatino(.caption, weight: .bold)` (título) y
  `.palatino(.caption2)` con `foreground: .secondary` (medallas).
- `ContentView.swift` Lista personal row (~10104): `Label(list1Title, systemImage: ...)`
  → HStack [systemImage + `FlagAwareText`] manual para que el título mezclado
  letra+bandera renderice ambas.
- `YearWrappedSheet.swift` 4 sites convertidos:
  - `flagGlyph(...)` (~892) — usado en pantalla de hero del wrapped.
  - "TU ESTANCIA MÁS LARGA" flag de país (~1251).
  - Grid de "MIS BANDERAS" outro slim (~1424).
  - Grid de "MIS BANDERAS" outro big (~1679).

**Título de `QuadrantDetailSheet` también vía Twemoji:**
- `navigationTitle("...")` solo acepta `String` → cualquier flag emoji
  embebido salía como emoji nativo del sistema en el header del sheet
  full-screen, aunque la card del cuadrante sí lo mostrara como Twemoji.
- **Fix (~línea 10109):** vaciar `.navigationTitle("")` y poner el título
  en `.toolbar { ToolbarItem(placement: .principal) { FlagAwareText(...) } }`.
  El `principal` slot acepta cualquier View, así que `FlagAwareText`
  parsea las banderas y las renderiza vía `TwemojiFlag`. Resto del título
  (texto + contador) sigue como `Text` normal. `.lineLimit(1) +
  .minimumScaleFactor(0.75)` para que escale bien en pantallas estrechas.

**Bandera de la UE (🇪🇺) añadida al set Twemoji:**
- Síntoma: en el quadrante por defecto "Unión Europea 🇪🇺" (`ContentView.swift`
  línea 9244) la bandera salía como 🌐 (fallback) o como emoji nativo del
  sistema según el path de render — porque `flag_EU.imageset` no existía.
- 🇪🇺 son los regional indicators E (1F1EA) + U (1F1FA). `flagEmojiToIso2`
  ya devolvía "EU" correctamente; faltaba el asset.
- **Fix:** descargar `1f1ea-1f1fa.png` (72×72, 560 B) desde el repo oficial
  `jdecked/twemoji` y crear los imagesets en ambos targets:
  - `Raskmap/Assets.xcassets/Twemoji/flag_EU.imageset/`
  - `RaskmapWidget/Assets.xcassets/Twemoji/flag_EU.imageset/`
- Cada imageset con `Contents.json` idéntico al resto (1x con `1f1ea-1f1fa.png`,
  2x/3x vacíos para que `Image(...).interpolation(.high)` upscale el 72px).
- Comando de descarga (re-aplicable si hace falta otra bandera no estándar):
  ```bash
  curl -L -o Raskmap/Assets.xcassets/Twemoji/flag_EU.imageset/1f1ea-1f1fa.png \
      https://raw.githubusercontent.com/jdecked/twemoji/main/assets/72x72/1f1ea-1f1fa.png
  cp -R Raskmap/Assets.xcassets/Twemoji/flag_EU.imageset \
        RaskmapWidget/Assets.xcassets/Twemoji/flag_EU.imageset
  ```

**Spacing entre banderas:**
- `FlowLayoutCentered`: `HStack spacing: 2 → 6`, `VStack spacing: 2 → 4`.
- `RaskmapWidget/RaskmapWidget.swift` 3 sites: añadido `spacing:` a las llamadas
  `FlagStrip(...)`:
  - Línea ~314 (medium widget upcoming row): `spacing: 4`.
  - Línea ~486 (large widget): `spacing: 4`.
  - Línea ~743 (lock screen accessoryRectangular `RaskmapWatchFlagsWidget`): `spacing: 5`.

### Task 3 — Una escala visitada cuenta exactamente 1 día

**Problema reportado:** "verifica que una escala marcada como visitada cuenta
como 1 día en ese país en el contador de días en un país."

**Diagnóstico (`Trip.swift` `daysPerCountry`):**
- El segmento ✈️ guarda `isoCodes = [destino + visitedLayoverISOs]` (mezclados).
- El algoritmo elegía `currentIso` con `let candidates = isos.filter { $0 != currentIso }`
  → si la escala estaba primero en el array (set order), pasaba a ser `currentIso`
  y cobraba TODOS los días posteriores hasta el siguiente segmento. Caso real:
  trip MAD-CDG-DUB ida+vuelta de 7 días → CDG cogía 6 días, IE 0 días, ES 1 día.

**Fix (`Trip.swift` ~268–293):**
- Excluir layovers de los candidatos a "stayed in":
  ```swift
  let layoverSet = Set(seg.visitedLayoverISOs ?? [])
  let nonLayoverIsos = isos.filter { !layoverSet.contains($0) }
  let candidates = nonLayoverIsos.filter { $0 != currentIso }
  ```
- Tras transicionar, stake explícito por cada layover en el día del segmento
  (segStart) con prioridad **50** — gana sobre la prioridad 100 del "stay"
  normal y sobre 1000+ del trip ambient:
  ```swift
  for layoverIso in layoverSet where !layoverIso.isEmpty {
      stake(iso: layoverIso, from: segStart, to: segStart, priority: 50)
  }
  ```

Resultado para trip a IE 7 días con FR como escala marcada en ida+vuelta
(stored como UN segmento con `visitedLayoverISOs = ["FRA"]`):
- Día 1 (vuelo ida): FR (escala, prio 50)
- Días 2–7: IE (estancia, prio 100/1000)
- FR = 1 día ✓ · IE = 6 días ✓

### Task 4 — Bug MAD-ARN-ARN al editar vuelo directo

**Problema reportado:** "Al editar un viaje le doy a vuelo directo MAD-ARN y
me dice que he puesto MAD-ARN-ARN."

**Diagnóstico (`RouteWizardSheet` en `ContentView.swift`):**
- Prepopulate `.onAppear` (~11313) construye `layoverStops` desde el path
  intermedio. Para legacy stored como `[MAD, ARN, MAD]` (round-trip directo
  guardado en formato expandido), la heurística asignaba:
  - `departureIata = MAD`, `finalIata = MAD` (último), `middle = [ARN]` →
    `layoverStops = [(ARN, "")]`.
- Al pulsar "Vuelo directo" en `layoverChoiceView` (~11540) se transicionaba
  a `.finalDest` SIN limpiar `layoverStops`. El usuario re-tipea ARN como
  destino → `finalIata = ARN`. En `returnView` (~11619):
  `segments = [departureIata] + layoverStops.map(\.iata) + [finalIata]`
  → `[MAD, ARN, ARN]` → renderiza "MAD → ARN → ARN".

**Fix (`Raskmap/ContentView.swift`):**
1. `layoverChoiceView` (~11540) y `returnLayoverChoiceView` (~11669): el
   botón "Vuelo directo" limpia `layoverStops` (resp. `returnLayoverStops`)
   antes de transicionar a `.finalDest` / `.returnFinalDest`. "Vuelo directo"
   es por definición sin escalas, así que es seguro resetear.
2. Prepopulate (~11313): trim defensivo del path antes de derivar
   `departureIata`/`finalIata`/`middle`:
   - Si `aps.first == aps.last` y `count >= 3`: round-trip expandido. Para
     count impar quédate con `prefix(mid + 1)` (`[MAD, ARN, MAD] → [MAD, ARN]`).
     Para count par quita el último (ambigüo).
   - Dedupea consecutivos: `[MAD, ARN, ARN] → [MAD, ARN]`.

Ambas medidas son defensivas: la (1) cubre legacy + cualquier estado
inesperado; la (2) evita que el wizard arranque con basura visible.

### Task 5 — Ruta de vuelo siempre visible en detalle de viaje finalizado

**Problema reportado:** "En los detalles del vuelo finalizado le doy a un país
y me muestra la ruta MAD-CPH y CPH-MAD pero en otro país no me muestra la ruta
siendo también vuelo de ida y vuelta directo."

**Diagnóstico (`FinalizadoTripDetailSheet` en `ContentView.swift`):**
- Trips CON segmentos: `airportRoute(for: seg)` reconstruye desde
  `seg.airports` + `seg.returnAirports` → "MAD → CPH  /  CPH → MAD". OK.
- Trips SIN segmentos (legacy directos creados antes del flujo de segmentos):
  el fallback rendea `FinalizadoSegmentRow(... airportRoute: nil)` (línea
  ~2556 ANTES). La ruta no aparecía aunque `trip.tripAirports` la tuviera.

**Fix (`Raskmap/ContentView.swift` ~2497):**
- Nueva helper `legacyAirportRoute(for: Trip) -> String?`:
  ```swift
  let isLikelyRoundTrip = aps.count >= 2 && aps.allSatisfy { $0.count >= 2 } &&
                          totalCount >= aps.count * 2
  let outbound = iatas.joined(separator: " → ")
  return isLikelyRoundTrip
      ? outbound + "  /  " + iatas.reversed().joined(separator: " → ")
      : outbound
  ```
- En el fallback (~2566): `airportRoute: row.trip.flatMap(legacyAirportRoute(for:))`.

Para `[MAD(c=2), ARN(c=2)]` (round-trip directo legacy) renderea
"MAD → ARN  /  ARN → MAD" igual que un segment-based trip.

### Task 6 — Editor IDA + VUELTA en `EditTripSheet` para round-trips legacy

**Problema reportado:** "Si le doy en el perfil a Próximos y le doy a editar un
viaje, por qué si no es de solo ida solo me deja poner un asiento, pasillo,
medio/ventana y una clase? Si son dos vuelos o más tiene que salir una opción
de estas para cada vuelo."

**Diagnóstico:**
- `EditTripSheet` para trips sin segmentos (legacy round-trip directo) usa el
  trip-level `FlightInfoSection(info: $localFlightInfo, ...)` (línea ~8903).
- `_localAirports = State(initialValue: trip.tripAirports)` → para round-trip
  legacy es `[MAD(c=2), ARN(c=2)]` (2 entradas, count=2 cada una).
- `_localReturnAirports` se queda **siempre vacío** (Trip no tiene un campo
  `returnAirports` a nivel trip — solo a nivel segmento).
- Resultado: `outboundRoute = [MAD, ARN]`, `returnRoute = []` →
  `outboundLegCount = 1`, `returnLegCount = 0` → **un solo `legEditor`** para
  ida MAD→ARN. La vuelta ARN→MAD no tiene editor propio.

**Fix (`Raskmap/ContentView.swift`):**
- Nueva computed property `effectiveFlightRoutes: (outbound: [String], returnRt: [String])`
  (~línea 8561) en `EditTripSheet`. Si `localReturnAirports` viene poblado
  (segment-based o user re-pasó por el wizard) lo usa tal cual. Si está vacío
  PERO `localAirports.count >= 2 && allSatisfy { $0.count >= 2 }` (heurística
  round-trip legacy), sintetiza `returnRt = outbound.reversed()` solo para UI.
- `FlightInfoSection(info: $localFlightInfo, outboundRoute: routes.outbound,
  returnRoute: routes.returnRt)` (~línea 8903) usa los routes efectivos →
  para legacy round-trip ahora `outboundLegCount = 1, returnLegCount = 1` →
  dos `legEditor` separados (IDA MAD→ARN + VUELTA ARN→MAD).
- "Ruta de vuelo" preview (~líneas 8884–8893) también lee de
  `effectiveFlightRoutes` → ahora muestra dos líneas (ida + vuelta) en vez de
  una sola para legacy round-trip.

**Por qué la sintetización es UI-only (no toca @State):**
- `prepareEditSaveConfirmation` (~línea 8585) hace
  `for ap in localAirports { apCombined[..., default: 0] += ap.count }` y
  luego lo mismo para `localReturnAirports`. Si tocáramos el `@State` para
  meter una vuelta sintetizada con count=2 cada uno, el confirm-dialog y el
  save mostrarían **MAD x4, ARN x4**, doblando el conteo de aeropuertos.
- Mantener la sintetización en una computed property derivada del @State
  evita el side-effect: el save sigue escribiendo
  `trip.tripAirports = localAirports` con los counts originales.
- Cuando el usuario teclea en el editor de vuelta, los datos van a
  `localFlightInfo.returnLegs[0]` vía `returnBinding`. En el save (línea
  ~8687) se escribe `trip.flightDetails = localFlightInfo.hasAnyData ? ... : nil`
  → `FlightInfo` Codable serializa `returnLegs` enterito. Al reabrir, los
  datos persisten. ✓

### Task 7 — Toggle "¿Visitaste alguna escala?" en cualquier edición/adición

**Problema reportado:** "Si añado una escala editando un viaje no me pregunta
si he visitado la escala para añadir el país. Esto ya lo teníamos hecho y debe
aparecer; asegúrate que está en cualquier edición de viaje con escala y
adición también."

**Diagnóstico — dos huecos en la UX:**
1. **`AddSegmentSheet` step 3 (segment-based):** la card de ruta era solo
   visual. `showRoutePicker` solo se activaba en step 1 → editando un
   segmento existente NO había forma de re-abrir el wizard para añadir/
   cambiar escalas. El toggle ya existía (`outboundLayoverChoices` /
   `returnLayoverChoices` poblados por `deriveFlightCountries()`), pero el
   user no podía meter escalas si el segmento se creó sin ellas.
2. **`EditTripSheet` flujo legacy (trips ✈️ sin segmentos):** la sheet de
   `RouteWizardSheet` (~línea 9077) usaba `onDone: {}` vacío y NO había
   sección de toggles equivalente — el modelo `Trip` ni siquiera tenía
   campo donde guardar `visitedLayoverISOs` a nivel trip (solo a nivel
   segmento). Resultado: añadir una escala en un trip legacy no preguntaba
   nada y la escala no se contaba como país visitado.

**Fix 1 — Card de ruta tappable en `AddSegmentSheet` (`AddSegmentSheet.swift`):**
- La VStack de la card de ruta (~línea 420) pasa a estar envuelta en un
  `Button { showRoutePicker = true }` con un sub-label "Editar" pequeño
  bajo el ✈️ a la derecha. Tap → re-abre `RouteWizardSheet` → al guardar
  se ejecuta el mismo `deriveFlightCountries()` ya existente → el bloque
  IDA/VUELTA se actualiza automáticamente.
- `.buttonStyle(.plain)` para preservar el look del card original.

**Fix 2 — Persistencia trip-level (`Raskmap/Trip.swift`):**
- Nuevo campo `var visitedLayoverISOsRaw: String?` en `@Model class Trip`
  (~línea 86) — JSON-encoded `[String]` (ISO A3).
- Computed `var visitedLayoverISOs: [String]?` (~línea 189) con el patrón
  estándar (getter decode, setter encode `.isEmpty → nil`).
- `daysPerCountry` (~línea 283): para trips sin segmentos, stake cada
  `t.visitedLayoverISOs ?? []` en `tFrom` con prio 50 — gana sobre la
  estancia ambient prio 100/1000+. Resultado: 1 día por escala visitada.

**Fix 3 — Toggle UI en `EditTripSheet` legacy (`Raskmap/ContentView.swift`):**
- Tres nuevos `@State` (~línea 8537):
  ```swift
  @State private var legacyOutboundLayovers: [LayoverChoice] = []
  @State private var legacyReturnLayovers: [LayoverChoice] = []
  @State private var legacyVisitedLayoverISOs: Set<String> = []
  ```
  (Reusa `LayoverChoice` de `AddSegmentSheet.swift` — mismo módulo.)
- `init(trip:)` (~línea 8717) seedea `legacyVisitedLayoverISOs = Set(trip.visitedLayoverISOs ?? [])`.
- Nueva helper `deriveLegacyFlightCountries()` (~línea 8631): igual que
  `AddSegmentSheet.deriveFlightCountries()` pero usa `effectiveFlightRoutes`
  como fuente de la ruta (cubre legacy round-trip directo sintetizado).
- Wizard `RouteWizardSheet` (~línea 9192): `onDone` ahora llama
  `deriveLegacyFlightCountries()` en vez de ser `{}`.
- `.onAppear { deriveLegacyFlightCountries() }` en la sheet — recompute
  inicial cuando el user re-abre un trip ya con escalas guardadas.
- Bloque de toggles inline (~línea 8919) justo debajo del `FlightInfoSection`
  legacy:
  ```swift
  if !legacyOutboundLayovers.isEmpty || !legacyReturnLayovers.isEmpty {
      Text(isForFuture ? "¿HARÁS PARADA EN...?" : "¿VISITASTE ALGUNA ESCALA?")
      legacyLayoverSection(title: "IDA", choices: legacyOutboundLayovers)
      legacyLayoverSection(title: "VUELTA", choices: legacyReturnLayovers)
  }
  ```
- `legacyLayoverSection` (~línea 8595) replica la estética de
  `AddSegmentSheet.layoverSection` pero opera sobre `legacyVisitedLayoverISOs`
  (Set binario por país → un país escala en ambas direcciones se marca con un
  solo toggle).

**Persistencia (`performEditSave`, ~línea 8809):**
```swift
if tripSegments.isEmpty {
    trip.flightDetails = localFlightInfo.hasAnyData ? localFlightInfo : nil
    let realISOs = Set(legacyOutboundLayovers.map(\.isoA3) + legacyReturnLayovers.map(\.isoA3))
    let visited = Array(legacyVisitedLayoverISOs.intersection(realISOs))
    trip.visitedLayoverISOs = visited.isEmpty ? nil : visited
} else {
    trip.visitedLayoverISOs = nil  // segment-based → escalas viven en seg.visitedLayoverISOs
}
```

**Confirmación de visita (`prepareEditSaveConfirmation`, ~línea 8722):**
- El bloque legacy ahora añade un `VisitEntry` por cada escala marcada
  además del país de destino — el confirm-dialog las lista para que el
  user vea qué países se van a marcar como visitados.

**Coverage final:**
| Flujo | Antes | Después |
|---|---|---|
| AddSegmentSheet (nuevo segmento ✈️) | toggle ✓ | toggle ✓ |
| AddSegmentSheet (segmento ✈️ existente) | sin acceso al wizard | tap card → wizard → toggle ✓ |
| EditTripSheet (trip legacy ✈️) | sin toggle | toggle ✓ + persistencia trip-level |
| AddTripSheet (nuevo trip ✈️) | usa AddSegmentSheet → toggle ✓ | igual |

## Cambios recientes (2026-04-25)

### Task 5 — Edición de viajes: dos bugs en flujo de segmentos

#### Bug 5a — Edición de asientos por leg en Próximos round-trip

**Problema reportado:** "Cuando hay un viaje con un vuelo ida y vuelta me tiene que dejar añadir el asiento, pasillo, ventana etc. de cada vuelo (esto me pasa cuando edito un viaje en estado Próximos)."

**Diagnóstico:**
- `EditTripSheet` muestra trip-level `FlightInfoSection` SOLO cuando `tripSegments.isEmpty` (línea 8797). Pero los Próximos round-trip se almacenan como UN segmento ✈️ con `airports` (ida) + `returnAirports` (vuelta). Así que para esos viajes la sección de detalles del vuelo no se ve a nivel trip.
- Edición per-segmento existía vía pencil → `AddSegmentSheet` step 3 → `FlightInfoSection` (que sí soporta IDA + VUELTA), pero era poco descubrible: el lápiz se asocia visualmente a "editar tramo" (transporte/países/fechas), no a "editar asientos".

**Fix:** inline-ar `FlightInfoSection` por cada segmento ✈️ en la sección TRAMOS de `EditTripSheet`, plegable con un chevron. El binding escribe directamente en `tripSegments[idx].flightInfo` y vuelve a `nil` cuando `hasAnyData == false` (no contamina viajes sin datos de asiento).

**Cambios en `Raskmap/ContentView.swift`:**
- `EditTripSheet`: nuevo `@State expandedSegmentIDs: Set<UUID>` (línea ~8484).
- `EditTripSheet`: nuevo helper `segmentFlightInfoBinding(for: UUID) -> Binding<FlightInfo>` (~línea 8489) que materializa `nil → FlightInfo()` para edición y revierte a `nil` cuando vacío al setear.
- ForEach de segmentos: cada fila ✈️ tiene chevron `chevron.up.circle.fill` ↔ `chevron.down.circle.fill` antes del lápiz; cuando expandido renderiza `FlightInfoSection` debajo del card del segmento (no DENTRO del card, para evitar doble padding y gris-sobre-gris).

#### Bug 5b — Back navigation rota al editar segmentos en Finalizados

**Problema reportado:** "Si edito un viaje pasado y le doy a editar los vuelos cuando le doy al botón de atrás me dice que seleccione el país del tramo, le doy otra vez a atrás y me da a elegir el transporte y esto no debería ser así, ya que esas no son las pantallas anteriores si entro desde la edición."

**Diagnóstico:**
- `AddSegmentSheet` es un wizard de 3 pasos (transport → países → fechas). Cuando se edita un segmento existente (`initialSegment != nil`), el init hace `_step = State(initialValue: 3)` saltando los dos primeros.
- El botón "Atrás" hacía `step -= 1` ciego, sin saber si el usuario venía de edición o creación. Al pulsar atrás desde step 3 en edición caía a step 2 (countriesStep "Países del tramo") y luego step 1 (transportStep "¿Cómo vas a viajar?") — pantallas del flujo de creación, no del flujo de edición.

**Fix doble:**
1. **`AddSegmentSheet`** (`Raskmap/AddSegmentSheet.swift`):
   - Nueva computed property `private var isEditing: Bool { initialSegment != nil }`.
   - Toolbar leading button: cuando `isEditing` siempre muestra "Cancelar" (que dismiss), independientemente del step. No aparece "Atrás" en modo edición porque no hay paso anterior real.
   - Botón inferior: `Text(isEditing ? "Guardar cambios" : "Añadir tramo")`.
   - Construcción del `TripSegment` final: `id: initialSegment?.id ?? UUID()` — preserva el id original al editar para que el caller pueda reemplazar por id.

2. **`EditTripSheet` en `Raskmap/ContentView.swift`**:
   - Botón pencil (~línea 8895) ya **no** elimina el segmento upfront. Solo asigna `editingSegment = seg` y abre la sheet. Antes hacía `tripSegments.removeAll { $0.id == seg.id }` antes de abrir → si el usuario cancelaba la edición, perdía el segmento original. Ahora se preserva.
   - Sheet `onAdd` callback (~línea 8949): si el segmento devuelto tiene un id que ya existe en `tripSegments`, lo reemplaza por índice; si no, hace append (lógica unificada para creación + edición).

**Side-effect positivo:** los segmentos editados nunca se duplican ni se pierden, incluso si se cancela el sheet de edición a mitad. La sheet pasa a comportarse correctamente como "editor de segmento existente" cuando viene de pencil tap.

### Task 1 — Twemoji desplegado en toda la app principal

**Objetivo:** que las banderas se vean con el set de Twitter/X (estética coherente cross-platform) en vez del Apple emoji nativo de iOS.

**Infraestructura (ya existía de la fase prototipo):**
- `Raskmap/TwemojiFlag.swift` con tres APIs:
  - `TwemojiFlag(iso2:size:fallbackEmoji:)` — render directo desde código ISO-2.
  - `FlagLabel(emoji:size:)` — drop-in replacement para `Text(emoji).font(.system(size:))` que detecta banderas regional-indicator y renderiza Twemoji; cualquier otro string (🌐, ✈️, "") cae a `Text(emoji)` normal.
  - `String.flagEmojiToIso2` — parser de regional-indicator pairs a ISO-2.
- 244 PNGs en `Assets.xcassets/Twemoji/flag_XX.imageset/` (paridad total con Apple emoji excepto los 5 territorios sin emoji estándar: BIR/BLR/SRB/PSE/CYN — esos siguen mostrando 🌐).

**Sites convertidos en `ContentView.swift` (todos `Text(...flag...).font(...)` → `FlagLabel(emoji:size:)`):**
- Cabecera de banner "Quedan X días" (línea ~964, body=17pt)
- Grid de banderas visitadas en toast (línea ~3828, title2=22pt)
- Aeropuerto favorito en perfil (línea ~4354, body=17pt)
- Hero header de país (línea ~1879, size 64)
- Toast de viaje (línea ~3957, headline=17pt) — refactorizado a HStack para separar bandera+nombre
- Header de `AddTripSheet` (línea ~6508) — refactorizado a HStack (flag size 20 + Text title3)
- Lista de búsqueda de países (línea ~1072, size 17)
- Filas de `ProximosListSheet` (líneas ~2139, ~2203, size 22)
- Filas de `FinalizadosListSheet` (ya en fase prototipo via `TwemojiFlag` directo, size 22)
- Header de `PlannedDatePickerSheet` (línea ~7182, size 52)
- Confirm-visits del save flow (línea ~7367, size 22)
- Top-3 aeropuertos del año (línea ~7721, size 12)
- Origen→Destino de cada leg (líneas ~8006/8008, size 20)
- `CountryTripsSheet` (línea ~8417, size 20)
- Continent assignment sheet (línea ~10590, size 22)
- Multi-continent assignment sheet (línea ~10692, size 22)
- Hemisphere assignment sheet (línea ~10789, size 22)
- Lista de aeropuertos (`Text(ap.flagEmoji).font(.title3)`, 3 sites, todos size 20)
- Pickers con favorite star (`Text(ap?.flagEmoji ?? "🌐").font(.title3)`, 2 sites, size 20)
- Layovers visitados confirmation (líneas ~11479/11609/11681, size 20)
- Lista de aeropuertos del país (línea ~11891, size 20)
- Lista flat de visited/notVisited en stats (línea ~9796/9806, size 22)
- Picker de países en leg detail (línea ~9723, size 17)
- Top medal slots en perfil (líneas ~9970/10388, size 34/40)
- Flag picker grids (líneas ~5788/10486, size 36)
- Helper de `CountryListRow` (línea ~6073, size 20)

**Sites NO convertidos (intencional):**
- **Widget preview interno** (`WidgetHomeColorSheet`, `ContentView.swift` línea ~5108): la bandera 🇯🇵 representa el aspecto del widget real en la home screen. Tras la fase 2 (Twemoji en widgets) ahora **sí** podríamos convertir este preview para que coincida con el widget real — pendiente de hacer si el usuario lo nota inconsistente.

### Task 1 (fase 2) — Twemoji desplegado en widgets

Tras el rollout en la app principal, se extendió el sistema Twemoji a los widgets de iOS y la Live Activity (`RaskmapWidgetExtension` target).

**Estrategia de duplicación de recursos:**
- Xcode 16 usa synchronized folders (`PBXFileSystemSynchronizedRootGroup`). Cada target tiene su propio sync folder; los archivos del folder se compilan en su target y solo en él.
- `Raskmap/` y `RaskmapWidget/` son sync folders separados → no comparten archivos por defecto.
- **Solución:** copiar `TwemojiFlag.swift` y la carpeta `Assets.xcassets/Twemoji/` al folder del widget. Trade-off: 1.9 MB duplicados, dos sources of truth.
- Comando de sync (manual cuando se modifique el helper):
  ```bash
  cp Raskmap/TwemojiFlag.swift RaskmapWidget/TwemojiFlag.swift
  cp -R Raskmap/Assets.xcassets/Twemoji RaskmapWidget/Assets.xcassets/Twemoji
  ```

**Nuevo helper `FlagStrip` en `TwemojiFlag.swift`:**
- Renderiza un string con múltiples banderas concatenadas (e.g. `"🇪🇸🇫🇷🇺🇸"`) como un HStack de imágenes Twemoji.
- Necesario porque el widget guarda los flags como un único `String` en App Group (claves `widget_all_flags`, `widget_top_visited_flags`).
- API: `FlagStrip(flags: String, size: CGFloat = 18, spacing: CGFloat = 0)`.
- Itera por `Character` (cada flag emoji es un único grapheme cluster gracias al regional-indicator pair).

**Sites convertidos en `RaskmapWidget/RaskmapWidget.swift`:**
- Línea ~218 `entry.nextFlag` size 14 (ProgressBarLockWidget header)
- Línea ~272 `entry.nextFlag` size 40 + sombra (Medium widget hero)
- Línea ~314 `upcomingFlagsSkippingFirst` → `FlagStrip(size: 15)` (Medium widget upcoming row)
- Línea ~362 `entry.nextFlag` size 54 + sombra (Large widget hero)
- Línea ~486 `flagStrip()` helper — ya usaba `Text(String(flags.prefix(9)))`, ahora `FlagStrip(size: 18)`
- Línea ~749 `entry.flags` → `FlagStrip(size: 22)` (RaskmapWatchFlagsWidget — pese al nombre, se muestra en iOS lock screen accessory)

**Sites convertidos en `RaskmapWidget/RaskmapLiveActivity.swift`:**
- Lock-screen banner: `Text(context.state.flagEmoji).font(.system(size: 40))` → `FlagLabel(emoji: ..., size: 40)` con sombra
- Dynamic Island expanded leading: size 34
- Dynamic Island compactLeading + minimal: size 16

**Sites NO tocados (no son banderas):**
- `Text(context.state.transportEmoji)` en Live Activity (transporte ✈️🚗🚂, no bandera)
- Cualquier `Text("✈️")` placeholder

**Targets sin widgets activos:**
- `RaskmapWatch Watch App/` — solo placeholder `Text("Hello, world!")`, sin widgets propios
- `RaskmapWatchWidgets/` — folder existe en disk pero NO está en `project.pbxproj` (no se compila). Si se activa en el futuro habrá que repetir la operación: copiar `TwemojiFlag.swift` y assets, luego convertir los `Text(entry.flag)` (líneas 73, 105 de `RaskmapWatchWidget.swift`).

**Diagnostics SourceKit (false positives — ignorar):**
- `Cannot find 'FlagLabel' in scope` en archivos de widget — el indexer de SourceKit no ve `TwemojiFlag.swift` cross-file en el sync folder. La build real iOS sí lo ve.
- `Cannot find 'UIImage' in scope` en `TwemojiFlag.swift` — indexer en contexto macOS, UIKit no disponible. iOS build OK.
- `'accessoryCircular' is unavailable in macOS` — confirma que SourceKit está en macOS, no iOS.

**Tamaños usados (puntos):** mapeo aproximado de los font sizes de SwiftUI:
- `.body` = 17 · `.title3` = 20 · `.title2` = 22 · `.caption` = 12 · `.headline` = 17

### Task 2 — Orden estable de banderas en perfil (FIX)

**Problema:** al tocar una fila de Finalizados o Próximos y cerrar la lista, las banderas en el bloque del año se reordenaban aleatoriamente. Causa: `Dictionary` en Swift tiene iteración no-determinista, y `sorted` es estable pero preserva el orden no-determinista del input cuando hay empates en la clave de ordenación.

**Fix en `YearTravelView` (`ContentView.swift`):**
- `finalizados` (~línea 6432): orden por `lastDate` ascendente con tiebreaker `isoCode` ascendente — antes visitado a la izquierda, después a la derecha, deterministic.
- `proximos` (~línea 6475): orden por `nextDate` (nil al final) con tiebreaker `isoCode`.

```swift
return result.sorted { a, b in
    if a.lastDate != b.lastDate { return a.lastDate < b.lastDate }
    return a.isoCode < b.isoCode
}
```

### Task 3 — Tap en Finalizados abre detalle de viaje completo

**Problema:** las filas de `FinalizadosListSheet` solo permitían borrar (xmark) — no había forma de ver los tramos del viaje.

**Solución (`ContentView.swift`):**
- `FinalizadosListSheet` ahora tiene `@State private var rowToShow: ProximoRow? = nil`.
- Cada fila lleva un chevron `chevron.right` indicador, `contentShape(Rectangle())` y `onTapGesture { rowToShow = row }`. El botón de borrar (xmark) sigue siendo tappable independientemente gracias a `.buttonStyle(.plain)`.
- Nuevo `.sheet(item: $rowToShow) { row in FinalizadoTripDetailSheet(row: row, features: features) }` adjuntado al NavigationStack.

**Nueva struct `FinalizadoTripDetailSheet`** (~línea 2450):
- Cabecera: `TwemojiFlag` 44pt + título del trip + país (si título ≠ país) + rango de fechas.
- Sección "TRAMOS DEL VIAJE": `ForEach(trip.tripSegments.sorted { $0.dateFrom < $1.dateFrom })`. Cada tramo se renderiza con `FinalizadoSegmentRow` (struct privada interna).
- Fallback sin segmentos: una única fila con transport + país + fechas del `ProximoRow`.

**`FinalizadoSegmentRow`:**
- `ZStack` con `Circle` gris + emoji de transporte (mismo look&feel que `EditTripSheet`).
- Banderas Twemoji por cada `iso` en `seg.isoCodes` (size 18).
- Nombres de países separados por " · ".
- Si transport == "✈️" y hay `airports`: ruta IATA tipo "MAD → NRT  /  NRT → MAD".
- Fechas con formato `dateStyle: .medium`, locale `es_ES`.

**Trade-offs:**
- Sheet read-only: no edita ni borra desde aquí (el borrado sigue desde la fila padre vía xmark + confirmation dialog).
- No muestra airlines/seat info — solo país+transporte+fechas+ruta IATA. Si el usuario quiere más detalle, lo añadimos en una iteración posterior.

## Cambios recientes (2026-04-24)

### `Trip.swift` — algoritmo quirúrgico de días por país

**Problema:** `daysSpent(iso:trips:)` solo consideraba el rango `dateFrom…dateTo` del trip primario y no descontaba los días en los que el usuario estaba físicamente en otro país vía segmentos o trips hijos. Caso real: trip HKG 1–11 con bus→MAC día 4, pie→CHN día 6, tren→HKG día 9 → contaba **11 días HKG**; debería ser **6 HKG + 2 MAC + 3 CHN**.

**Solución:** nuevo `daysPerCountry(trips:)` en `Trip.swift:192` — sistema basado en intervalos por día con prioridades. Cada día del calendario se atribuye a UN solo país según la fuente más específica. `daysSpent(iso:trips:)` delega ahora en `daysPerCountry` para garantizar consistencia app/widget/wrapped.

**Sistema de prioridades (menor = gana):**
- `100` — segmento interno dentro de un trip primario (el paso más granular)
- `200 + tripLen` — trip hijo (`isSegmentChild == true`)
- `1000 + tripLen` — trip primario independiente

El `+ tripLen` hace que entre dos trips del mismo tipo gane el más corto (asunción más concreta).

**Detalle clave de destino de segmento:** `isoCodes` llega como `Array(Set)` desde `AddSegmentSheet` (unordered), así que no se puede usar `.last` como destino fiable. Nueva heurística: `candidates = isos.filter { $0 != currentIso }`; `dest = candidates.first ?? isos.last`. Así, con `currentIso = HKG` y `isoCodes = {HKG, MAC}` siempre resulta `dest = MAC`.

**Algoritmo:**
```swift
private struct _DayClaim {
    var iso: String
    var priority: Int   // smaller = wins
}

func daysPerCountry(trips: [Trip]) -> [String: Int] {
    var claims: [Date: _DayClaim] = [:]
    func stake(iso: String, from: Date, to: Date, priority: Int) { ... }
    for t in trips {
        // 1) Trip ambiental: todo el rango reclamado con prio 1000+len (o 200+len si child)
        stake(iso: t.isoCode, from: tFrom, to: tTo, priority: tripPriority)
        // 2) Segmentos internos: reclaman con prio 100 — ganan siempre
        var currentIso = t.isoCode
        var currentStart = tFrom
        for seg in t.tripSegments.sorted(by: date) {
            stake(iso: currentIso, from: currentStart, to: prevDay(segStart), priority: 100)
            // destino heurística: filtrar out currentIso, fallback isos.last
            let candidates = seg.isoCodes.filter { $0 != currentIso }
            currentIso = candidates.first ?? seg.isoCodes.last ?? currentIso
            currentStart = seg.dateTo ?? seg.dateFrom
        }
        stake(iso: currentIso, from: currentStart, to: tTo, priority: 100)  // cola
    }
    return claims.values.reduce(into: [:]) { $0[$1.iso, default: 0] += 1 }
}
```

### `YearWrappedSheet.swift` — "longest stay" unificado

Reemplazada la lógica compleja `staysFromPrimary` + groups en `WrappedStats.compute()` por delegación directa a `daysPerCountry(trips: yearAllTrips)`. Mismo algoritmo → mismos resultados que widget y `ContentView.topVisitedFlagsString`. Sorted stable: valor desc, ISO asc.

### `RaskmapWidget.swift` — padding pequeño + lock screen/watch widgets restaurados

**Padding del widget pequeño:**
- `StaticConfiguration` con `.contentMarginsDisabled()` — elimina el margen del sistema (~16pt default).
- `SmallView` (ambas ramas: empty + filled): `.padding(15)`. Total efectivo: 15pt, no 15+16.
- `MediumView` y `LargeView` mantienen su padding interno explícito — no pierden layout.

**Widgets de pantalla de bloqueo / Apple Watch restaurados.** En el commit `dfb1005` la reescritura del widget eliminó sin querer los 4 widgets de lock screen que existían en `a287018`. Se reintrodujeron convertidos de `AppIntentConfiguration` → `StaticConfiguration` (ya no hay `RaskmapIntent` en el bundle):

| Struct | Kind | Familia | Provider | Comportamiento |
|---|---|---|---|---|
| `RaskmapLockPctWidget` | `"RaskmapLockPct"` | `.accessoryCircular` | `LockPctProvider` | Gauge circular con `%.1f%` visitado. Sin Pro → `lock.fill`. Modo de conteo leído de `widget_counting_mode`. |
| `RaskmapLockNextWidget` | `"RaskmapLockNext"` | `.accessoryRectangular` | `LockNextProvider` | 🔜 + "X días" + "Próximo viaje". Sin Pro → lock. Sin viaje → ✈️ "Sin viaje". |
| `RaskmapLockInlineWidget` | `"RaskmapLockInline"` | `.accessoryInline` | `LockNextProvider` | **Encima del reloj**: `"Quedan X días · Tokio"`. Sin Pro → `Label("Pro", systemImage: "lock.fill")`. Sin viaje → `Label("Sin próximo viaje", systemImage: "airplane")`. |
| `RaskmapWatchFlagsWidget` | `"RaskmapWatchFlags"` | `.accessoryRectangular` | `WatchFlagsProvider` | Banderas de todos los próximos viajes concatenadas. Sin Pro → "🔒 Pro". Sin viajes → "✈️ Sin próximos viajes". |

Registrados en `RaskmapWidgetBundle.swift`:
```swift
@main
struct RaskmapWidgetBundle: WidgetBundle {
    var body: some Widget {
        RaskmapWidget()
        RaskmapLockPctWidget()
        RaskmapLockNextWidget()
        RaskmapLockInlineWidget()
        RaskmapWatchFlagsWidget()
        RaskmapWidgetControl()
        RaskmapLiveActivity()
    }
}
```

Todas las vistas lock/watch usan `.containerBackground(.clear, for: .widget)` para respetar el fondo del lock screen. Entries (`LockPctEntry`, `LockNextEntry`, `WatchFlagsEntry`) incluyen `isPro: Bool` leído de `widget_is_pro`.

### `ContentView.swift` — `MedalleroSheet` simplificada

**Premios personales: 4 cuadrantes → 2.** Eliminado el segundo `HStack` con slots 2 y 3. `awardSlots` ahora es `(0..<2)`.

**Eliminada "Lista personal 2" completamente.** Eliminados `@AppStorage("personalList2Title")`, `personalList2Content`, `@State showList2` y el `.sheet(isPresented: $showList2)`. Las claves UserDefaults subyacentes persisten (no se borran explícitamente) → si alguna vez se restaura la lista 2, los datos siguen ahí.

**Categorías personales + Lista personal fusionadas en una sola card con `Divider`.** Antes: dos cards separadas con `.padding(.bottom, 12)` entre ellas. Ahora: un solo `VStack(spacing: 0)` con `Button { showSubjectiveCategories = true }` + `Divider().padding(.leading, 16)` + `Button { showList1 = true }`. Renombrado `"Lista personal 1"` → `"Lista personal"`.

### `ColorThemeManager.swift` — defaults explícitos en sRGB

Defaults reescritos a `Color(.sRGB, red: …, green: …, blue: …, opacity: 1.0)` con `/255.0` en lugar de `/255` — elimina ambigüedad de división entera y declara el espacio de color explícitamente.

| Categoría UI | `CountryStatus` | Hex sRGB |
|---|---|---|
| Próximos | `wantToVisit` | `#00CB7C` |
| Visitados | `visited` | `#DC6647` |
| Quiero | `bucketList` | `#E5B257` |
| Vivido | `lived` | `#5DAD6E` |

Usuarios con colores personalizados (clave UserDefaults `color_visited/wantToVisit/bucketList/lived`) no se ven afectados — los defaults solo aplican a nuevas instalaciones o tras `resetToDefaults()`.

### `Trip.swift` — `FlightLegInfo` per-tramo

Nueva struct `FlightLegInfo` (Codable, Equatable) con `seatNumber / seatPosition / cabinClass`. `FlightInfo` extendido con `outboundLegs: [FlightLegInfo]` y `returnLegs: [FlightLegInfo]`, los campos escalares antiguos (`seatNumber/seatPosition/cabinClass`) se conservan como **legacy** para datos previos. Computed `allLegs` devuelve la unión ida+vuelta o un fallback sintético desde el legacy si las arrays están vacías. `hasAnyData` actualizado para considerar legs.

Migración: idempotente, se ejecuta `onAppear` en cada FlightInfoSection — si `outboundLegs.isEmpty` y hay valor legacy, crea un solo leg con esos datos. Después limpia los escalares.

### `ContentView.swift` / `AddSegmentSheet.swift` — `FlightInfoSection` refactor per-tramo

Firma nueva: `FlightInfoSection(info:, outboundRoute: [String], returnRoute: [String])`. Genera N editores leg = `outboundRoute.count - 1` (escalas internas cuentan como tramo separado), igual para vuelta. Editor por leg muestra `LHR → MAD` etc. con su propio asiento/posición/clase.

Call-sites actualizados (líneas aprox.):
- `ContentView.swift:6821` — `AddTripSheet`
- `ContentView.swift:8393` — `EditTripSheet`
- `AddSegmentSheet.swift:447` — `AddSegmentSheet` (segmentos hijos)

Agregadores de stats (`ContentView.swift:7195-7229`) iteran `info.allLegs` en lugar de los escalares antiguos.

### Tramos ordenados cronológicamente

`ForEach(tripSegments.sorted { $0.dateFrom < $1.dateFrom })` aplicado en:
- `AddTripSheet` "Tramos adicionales" (`ContentView.swift:6275`)
- `EditTripSheet` "TRAMOS" (`ContentView.swift:8579`)

Antes: aparecían en orden de inserción → `31/10, 1/11, 30/10` rompía la lectura natural ida → vuelta. `FlightsSheet` ya estaba ordenado descendente globalmente y se deja como estaba.

### `ContentView.swift` — bug de finalizados-sobre-perfil arreglado

**Problema:** `showProfile` (full-screen) y `finalizadosSheetData` (sheet) estaban ambos atados al root view. SwiftUI solo permite UN sheet/cover activo por nivel: al tocar "Finalizados" desde el perfil, el sheet quedaba en cola y solo aparecía tras cerrar el perfil.

**Fix:** estado `finalizadosPayload` y su `.sheet(item:)` movidos **dentro** de `ProfileSheet`. Helper privado `finalizadoRows(year:)` duplicado dentro de `ProfileSheet` con su propio `@Environment(\.modelContext)` y `@Query`. Se eliminó el callback `onFinalizadosTap` que comunicaba con el root.

Archivos tocados: solo `ContentView.swift` (eliminadas ~80 líneas en root, añadidas ~50 dentro de `ProfileSheet`).

### `ContentView.swift` — apartados legales reforzados para App Store

Reescritos los 5 textos en `LegalInfoSheet` (líneas 4631–4659) para cumplir requisitos de Apple App Review + AEPD:

| Apartado | Mejora |
|---|---|
| Política de privacidad | Email visible (`raskmap_soporte@icloud.com`); CloudKit declarado como procesador (Apple Inc.); aclaración de IAP vía App Store; edad mínima 13+; retención; derecho a reclamar ante AEPD con URL |
| Términos de uso | Edad mínima; **Apple Standard EULA** referenciado por URL; aclarado «pago único, no suscripción»; limitación de responsabilidad reforzada |
| Aviso legal | Email visible; «persona física, particular»; nuevo apartado de propiedad intelectual |
| Tus derechos (RGPD) | **Derecho a reclamar ante AEPD** añadido (GDPR Art. 13(2)(d), antes faltaba); aclaración no-transferencia fuera del EEE |
| Atribuciones | Añadido MapKit/Apple Maps + StoreKit/App Store |

`ContactSheet` (línea 4722) ya enviaba a `raskmap_soporte@icloud.com` por `MFMailComposeViewController` — el email es real.

### `RaskmapWidget.swift` — título de viaje en lock screen

`LockNextEntry` (línea 587) extendido con `title: String`. `LockNextProvider.makeEntry()` lee `widget_next_title` (clave del App Group ya escrita por `WidgetDataWriter.syncNextTrip`).

`LockNextView` (línea 630) muestra: `title` si existe → `name` (país) si no → fallback `"Próximo viaje"`. `.lineLimit(1).minimumScaleFactor(0.8)` para evitar truncado en pantallas estrechas.

Configuración (línea 654): `.description("Días hasta el próximo evento.")` (antes "Bandera y días hasta el próximo viaje").

### Nueva carpeta `docs/` — sitio web de documentación legal

Repo-root `/docs/` con los 5 textos legales en Markdown listos para GitHub Pages. Mismo contenido literal que la app (Apple verifica en revisión que coinciden).

```
docs/
├── README.md      (instrucciones para activar GitHub Pages)
├── index.md       (landing con enlaces)
├── privacy.md     ← Privacy Policy URL para App Store Connect
├── terms.md
├── imprint.md
├── gdpr.md
└── credits.md
```

Front-matter Jekyll mínimo (`title:`) en cada archivo. Funciona out-of-the-box con la rama `main` + carpeta `/docs` en Settings → Pages, sin configuración adicional.

---

## Cambios recientes (2026-04-19) — continuación

### `FlightFilterSlider` — thumb vertical-centrado

`ZStack(alignment: .leading)` ya centra verticalmente sus hijos. El thumb tenía además `.offset(y: 2)` heredado de un diseño previo, empujándolo 2pt por debajo del centro — resultado: colisión visible con el borde inferior de la cápsula exterior. Fix: `.offset(x: clampedX + 2)` sin componente Y. El `+2` horizontal sigue siendo el margen simétrico entre el thumb (`width: segW - 4`) y el borde.

### `YearWrappedSheet` outro — navegación hacia atrás reactivada + `ShareableSummaryCard` rediseñada

**Back-nav en slide final.** El layer táctil del outro se había eliminado entero para no chocar con los botones Share/Restart; eso rompía el swipe/tap a la izquierda para volver a slides anteriores. Solución: mantener `StoryTouchLayer` en outro con `onTapRight`/`onSwipeLeft` como no-op pero conservando `onTapLeft`/`onSwipeRight` → `goBack()`. Además `.padding(.bottom, 280)` acota la zona de gesto arriba de los CTAs para que siguen siendo tappables.

**`ShareableSummaryCard` 1080×1920 rediseñada.** Antes todo el contenido quedaba apilado en la mitad superior. Nueva composición en 4 bloques verticalmente distribuidos con `Spacer()`:
- Hero: `ASÍ FUE MI` (30pt, tracking 14) + año (280pt Palatino-Bold con sombra doble) + `EN RASKMAP` (28pt, tracking 12), padding top 170.
- `SummaryStatGrid` (padding horizontal 72) separado por un divisor de puntos (3 círculos + 2 cápsulas).
- Nueva galería `flagGallery` con label `MIS BANDERAS` entre hairlines + `LazyVGrid` `adaptive(minimum: 92→34pt)` según recuento, en contenedor redondo (radius 32, fill `white.opacity(0.08)`, stroke `white.opacity(0.18)`).
- Footer: hairline 220pt + 🗺️ 52pt + `Raskmap` 44pt + tagline 22pt. Padding bottom 110.
- Fondo: gradiente 4 paradas `#04071F → #1C1048 → #52209A → #E44BC4` + glows adicionales (`#A16BFF` 900pt, `#FF88CA` 820pt).

### `TransportStatsSheet` — drill-down de avión muestra vuelos, no rutas

Al tocar el chip ✈️ en "Tus medios" ahora se presenta `FlightLegsListSheet` (nueva) en lugar de `TransportTripsListSheet`. Cada fila es un **tramo individual** con origen, destino, fecha y bandera del país de destino, no una agrupación por viaje.

Archivos: `ContentView.swift`.
- `FlightLegsListSheet` nueva en `ContentView.swift:7179`. `FlightLeg` interno (from, to, date, transportISO). `legs` computed recorre solo trips primarios (no `isSegmentChild`), itera `tripSegments` y por cada segment con `airports`/`returnAirports` hace un walk pairwise para generar un leg por par consecutivo — usa `seg.dateFrom` para ida y `seg.dateTo` para vuelta. Para trips legacy sin segments con exactamente 2 `tripAirports`, genera `totalTouches/2` legs alternando dirección (ida → vuelta → ida…).
- Router dentro de `TransportStatsSheet` body: `if filter.emoji == "✈️" { FlightLegsListSheet(…) } else { TransportTripsListSheet(…) }`.

### Conteo de vuelos corregido en Wrapped y en `TransportStatsSheet`

**Bug:** en la rama legacy (trips primarios sin `tripSegments`, con solo `tripAirports`) se usaba `max(1, tripAirports.count - 1)`. Como `tripAirports` está **deduplicado con un `count` por aeropuerto** (migración de `roundTrip=true` → `count=2`), un round-trip directo con 2 aeropuertos contaba `1` tramo en lugar de `2`.

**Fix en dos sitios simétricos:**
- `WrappedStats.compute()` en `YearWrappedSheet.swift:249` — rama `else if t.transport == "✈️"`.
- `TransportStatsSheet.counts` en `ContentView.swift` — rama `if tr == "✈️"` dentro del loop de primaries.

Ambas ahora usan:
```swift
let totalTouches = trip.tripAirports.reduce(0) { $0 + $1.count }
let legs = max(1, totalTouches / 2)
```
Verificado: one-way directo `[MAD(1), NRT(1)]` = 1 tramo; round-trip directo `[MAD(2), NRT(2)]` = 2; one-way con escala `[MAD(1), DXB(2), NRT(1)]` = 2; round-trip con escala `[MAD(2), DXB(4), NRT(2)]` = 4. Los trips modernos (con `tripSegments`) siempre fueron correctos (`outLegs + retLegs`).

---

## Cambios recientes (2026-04-19)

### `YearWrappedSheet.swift` — fixes de territorios, empates de mes y compartir

**Territorios no reconocidos por la ONU ahora se cuentan siempre**
`WrappedStats.compute(year:trips:allFeatures:)` reescrita para capturar destinos como Hong Kong, Macao, Puerto Rico, Taiwán, etc. — independientemente de cómo se hayan registrado y del medio de transporte.
- Añadida variable `yearAllTrips = trips.filter { $0.year == year }` (incluye `isSegmentChild`). `countryTripCounts` ahora cuenta sobre `yearAllTrips`, capturando layovers guardados como child trips.
- Bucle adicional sobre `yearTrips` (primarios) recorriendo `tripSegments.isoCodes` para capturar escalas declaradas únicamente dentro de segments (no como trip independiente).
- `priorISOs` expandido: además del `isoCode` de trips anteriores, también recoge todos los `seg.isoCodes` de años previos — así "nuevos" sigue siendo coherente para territorios registrados como layover.
- Top 4 flags: si `allFeatures.first(where:)` no encuentra feature (territorio sin entrada en geojson), se cae a `🌐` y se usa el propio ISO como nombre — antes el array se quedaba vacío y la slide no mostraba nada.

**Empates de "mes más viajero"**
- `WrappedStats.topMonth: (Int,Int)?` → `topMonths: [(month: Int, count: Int)]` (array de todos los meses que empatan al máximo).
- `topMonthSlide` bifurca la UI: si `count <= 1`, render clásico (nombre grande + contador); si hay empate, lista vertical con los nombres de los meses empatados, tamaño decreciente si >3, y subtítulo "empate múltiple 🤝".
- `activeSlides` usa `!stats.topMonths.isEmpty` en lugar de `topMonth != nil`.

**Botón "Compartir mi año" ahora genera imagen 9:16 fiable**
- `share()` refactorizado a arquitectura `Task { @MainActor in … }` para dar un tick al layout antes de renderizar (`ImageRenderer` devolvía `nil` cuando la vista aún no había resuelto layout).
- Nuevo helper estático `renderShareImage(stats:year:)` — encapsula el render con `renderer.scale = 2`, `proposedSize = 1080×1920`, `isOpaque = true`, `environment(\.colorScheme, .dark)`.
- Nuevo helper estático `presentShareSheet(items:onComplete:)` — búsqueda robusta de la keyWindow (filtra por `isKeyWindow`, luego visibilidad, luego primera) y sube por la cadena de `presentedViewController` saltándose VCs `isBeingDismissed`. Así el UIActivityViewController se presenta incluso desde `fullScreenCover` anidado.
- Fallback: si el render falla, el share sheet igualmente se presenta con el texto "Mi año \(año) en Raskmap 🗺️" — antes la tap era silenciosa si `renderer.uiImage` era nil.

### `ColorThemeManager.swift` — color default de "Próximos" actualizado
- `defaultWantToVisit = #00CB7C` (verde esmeralda) — antes `#6E95C7` azul polvo en la paleta anterior. Se aplica a los polígonos en el mapa y al color de fondo del widget si el usuario no ha personalizado.

### Widget de pantalla principal — rediseño mediano y grande

Archivos: `RaskmapWidget/RaskmapWidget.swift` y `Raskmap/WidgetDataWriter.swift`.

**Nueva estructura de datos compartida (App Group)**
- `RaskmapEntry` ampliado: `visitedUN`, `visitedUNPlus`, `visitedAll`, `nextFlag`, `nextDays`, `nextName`, `nextTransport`, `upcomingFlags`, `topVisitedFlags` — suficiente para los tres tamaños sin recargas adicionales.
- `WidgetDataWriter.syncTopVisitedFlags(_:)` — escribe un string concatenado de emojis de banderas de países visitados ordenados por `visitCount` (hasta 12).
- Nueva computed `topVisitedFlagsString` en `ContentView.swift`: itera `countries` con `status ∈ {.visited, .lived}`, ordena por `visitCount` desc (tiebreak alfabético por ISO), mapea a `features.first(where: ...)?.flagEmoji ?? "🌐"`, `.prefix(12).joined()`. Se sincroniza en `handleTripsCountChange()` y `handleInitialTask()`.

**`MediumView` — dos columnas con separador vertical**
- Columna izquierda: eyebrow "PRÓXIMO VIAJE" + emoji transporte, flag 40pt con sombra, nombre del destino, contador `en N DÍAS`, strip mini de próximas banderas (6 chars). Estado vacío: 🗺️ "Sin viajes".
- Columna derecha (ancho fijo 120): contador grande 52pt Palatino-Bold + label según modo + footer con modo corto.
- Separador vertical `Color.white.opacity(0.18)` de 0.5pt.

**`LargeView` — tres secciones separadas por dividers finos**
- **Hero**: flag 54pt + eyebrow + nombre + número de días a la derecha.
- **Stats**: tres celdas (ONU / ONU+OBS / TODOS) con sus contadores respectivos, separadas por dividers verticales de 0.5pt altura 36.
- **Flag strips**: dos filas (`PRÓXIMOS`, `MÁS VISITADOS`) — label 9pt tracking 1.4 + banderas 18pt (prefix 9). Placeholders si vacíos.

**`SmallView`**: sin cambios (seguía siendo el diseño que el usuario quería).

**`.supportedFamilies`**: ahora `[.systemSmall, .systemMedium, .systemLarge]` en `RaskmapWidget`.

**Fondo**: todos los tamaños usan `containerBackground(entry.bgColor, for: .widget)`. El color default (`widget_bg_color`) ahora es `#00CB7C` consistente con el color de "próximos" en la app.

---

## Cambios recientes (2026-04-18) — Compactación del passport + YearWrappedSheet v1

### Passport avatar — migración completa
- Eliminado `ImagePickerView` y todo el flujo de UIImagePickerController.
- Onboarding rediseñado en 2 pasos (`onboardingSheet()` con `@State onboardingStep: Int`): (1) username, (2) grid de pasaportes con `PassportSelectableCard`.
- Avatar del top bar y ajustes usan `PassportAvatarView(key:height:)` directamente.
- Picker de pasaporte a pantalla completa via `.fullScreenCover` (antes era `.sheet`).

### Slider del modo vuelos (`FlightFilterSlider`)
- **Nota:** al principio usaba `GlassEffectContainer` + `.glassEffect(.regular.interactive(), in: Capsule())` (iOS 26 nativo), pero el blur del thumb ocultaba el texto debajo. Se reemplazó por una **cápsula transparente con gradiente blanco suave** (`white.opacity(0.22→0.08)`) + `stroke(white.opacity(0.55))` + sombra tenue. Lee perfectamente y mantiene la sensación líquida.
- `GeometryReader` + `ZStack(alignment: .leading)` con HStack de labels+iconos debajo y el thumb (cápsula) encima (`allowsHitTesting(false)` — los taps los recibe el HStack).
- `DragGesture(minimumDistance: 0)` con `@GestureState dragDelta: CGFloat` y `@GestureState isPressing: Bool`. Al presionar el thumb escala `1.06`. Snap al segmento más cercano en `onEnded`.
- Centrado vertical: al apoyarse en `ZStack(alignment: .leading)` ya queda centrado en Y automáticamente; el único offset es horizontal (`.offset(x: clampedX + 2)` con `+2` = margen simétrico respecto al ancho reducido `segW - 4`). Un `.offset(y:2)` heredado causaba colisión con el borde inferior; eliminado.
- Eliminado el username del top bar en modo mapa y vuelo (antes había `Text("@\(username)")` al lado del avatar).

### YearWrappedSheet v1
- `WrappedStats` ampliada con `totalTerritories`, `newTerritories`, `topAirlines: [(name,count)]`, `topAirports: [(iata,name,count)]`, `longestTripCountry`, `longestTripFlag`.
- `WrappedStats.empty` para evitar recomputar en cada render — se cachea en `@State cachedStats: WrappedStats?` en `.onAppear`.
- Sorts con tiebreakers estables (`if $0.count != $1.count { return $0.count > $1.count }; return $0.emoji < $1.emoji`) + `ForEach(id: \.emoji)` en slide de transportes — mata los parpadeos por iteración no-determinista de diccionarios.
- `targetYear = Calendar.current.component(.year, from: Date()) - 1` → año anterior automático.
- `StoryTouchLayer` component: `DragGesture(minimumDistance: 0)` detecta press-and-hold (pausa auto-advance), tap corto (<0.35s, <12px) = navegar, swipes laterales/hacia abajo.
- `OutroSlideView` + `SummaryStatGrid` (2x2) + `ShareableSummaryCard` 1080×1920.
- Fix bug de build: `import Combine` añadido en `YearWrappedSheet.swift:11` (antes `autoconnect()` fallaba al compilar).

---

## Cambios recientes (2026-04-17)

### Modo Vuelos — filtro Visitados / Próximos
- En `flightMode == true` el dock **vacía todo su contenido habitual** (passport avatar, separador vertical, badges de categorías, botón de búsqueda con denominador) y queda solo el slider `FlightFilterSlider` centrado con `Spacer()` a ambos lados (ver `ContentView.swift:400`). En modo mapa el dock vuelve a su layout normal.
- Filtro por defecto: `Visitados` (`.past`). `Próximos` (`.upcoming`) dibuja los arcos de viajes con `dateFrom > hoy`.
- Al entrar en modo vuelos siempre se resetea a `.past` (`triggerFlightModeTransition()`).
- Nuevo enum `FlightRouteFilter { past, upcoming }` en `FlightMap.swift`. `FlightRoutesBuilder.build(from:filter:)` filtra según el caso.
- `RaskMapView` recibe `flightRouteFilter: FlightRouteFilter`; el `Coordinator` guarda `lastFlightRouteFilter` y `rebuildFlightOverlays(mapView:trips:filter:)` limpia+redibuja cuando cambia.

### Empty state del modo vuelos
- `flightEmptyState()` en `ContentView.swift` — card `.ultraThinMaterial` centrado con `airplane.departure` y mensaje contextual: *"Aún no has volado"* (.past) vs *"Sin vuelos próximos"* (.upcoming).
- Detección eficiente vía `FlightRoutesBuilder.hasAnyRoute(in:filter:)` — early-exit: devuelve `true` en cuanto encuentra un par válido, evitando materializar todo el set.
- Estado `@State flightModeHasRoutes: Bool` recalculado en `onChange` de `flightMode`, `flightRouteFilter`, `trips.count` y en el `.task` inicial.
- Overlay `.allowsHitTesting(false)` y `zIndex(50)` — no bloquea el mapa, queda por debajo del `FlightModeTransition`.

### User location y centrado
- `MKMapView.showsUserLocation = false` al entrar en `enterFlightMode`, `= true` al volver con `exitFlightMode`.
- `exitFlightMode` ahora llama a `fitToVisitedCountries(mapView:)` — mismo encuadre automático que `enterFlightMode` aplica a aeropuertos, pero usando la unión de `boundingMapRect` de países visitados/lived con padding 80/50/80/50. Fallback a Antártida (`Coordinator.antarcticaFallback`) si no hay países.

### Rediseño Live Activity (boarding-pass)
Archivo: `RaskmapWidget/RaskmapLiveActivity.swift` — reescritura completa.
- Lockscreen: gradiente oscuro, eyebrow "PRÓXIMO VIAJE" en accent cobalto (`Satoshi-Bold` 9pt tracking 1.8), bandera 40pt con sombra (sin círculo), nombre `Satoshi-Bold` 17pt, separador vertical, columna de días (34pt número + "DÍA/DÍAS" label en accent), motivo `DashedTrail` debajo.
- Dynamic Island expanded: eyebrow + trail + separador en la misma estética.
- Accent cobalto `#4072D4` consistente con botón de modo vuelos.

### ColorThemeManager — defaults mutados
Palette nueva, menos estridente en el mapa:
- `defaultVisited = #C47457` (terracota suave)
- `defaultWantToVisit = #6E95C7` (azul polvo)
- `defaultLived = #6FA07C` (verde salvia)
- `defaultBucketList = #D4A85E` (ámbar mate)

### `ModelContext+Fetch.swift` — helpers con logging
Nuevo archivo con extensión sobre `ModelContext`:
- `fetchOrWarn(_:fallback:)` — reemplaza `try? modelContext.fetch(desc)` silencioso; en DEBUG imprime `⚠️ SwiftData fetch failed [file:line]: error` en lugar de tragar el fallo.
- `fetchFirstOrWarn(_:)` — variante que devuelve el primer resultado o `nil`.
- Migrados 10 sitios destructivos + 9 `.first` en `ContentView.swift` (incluyendo dentro de `EditTripSheet`, que no podía acceder a helpers privados de ContentView).

### Otras mejoras / fixes de esta sesión
- **`allProximoRows`**: O(n·m) → O(n+m) — indexa trips con `Dictionary(grouping: trips, by: \.isoCode)` antes del loop.
- **Force-unwraps eliminados**: 3 en `ContentView.swift` + 3 en `AddSegmentSheet.swift` — `cal.date(byAdding:...)!` ahora cae a `?? date.addingTimeInterval(86_400)`.
- **`earnedPassportZones`**: decodifica directamente `Set<String>.self` (antes decodificaba `[String]` y convertía) en los 3 puntos de uso.
- **`lastEditedFutureTripIso = nil`** al final del `onDismiss` del edit sheet — evita estado stale.
- **Banner declutter**: el banner ad (`isRaskmapPro == false`) se oculta con `!flightMode`, pero el countdown banner **sigue visible en modo vuelos** — es información relevante para el usuario estando en la vista de rutas. Ver `ContentView.swift:935` (banner ad: `if !flightMode, !isRaskmapPro`) vs `ContentView.swift:946` (countdown: `else if showCountdown`).
- **Haptics**: medium al alternar modo vuelos, light al cambiar de filtro.
- **Accesibilidad**: `flightModeButton` con label+hint contextuales; pills con `Filtro vuelos: <title>` y trait `.isSelected` cuando activo.
- **Eliminada** la rama legacy `visitedIsoSet` (dead computed property) y los helpers privados `fetchOrWarn`/`fetchFirstOrWarn` de ContentView (migrados a extensión).

### Recordatorio — Vivido
No existe badge de "Vivido" en el dock ni en listas. Se marca únicamente con el toggle `Country.hasLived` (muestra 🏠 en lista visitados). Las rutas/filtros de modo vuelos usan solo `past`/`upcoming` sobre `trips.dateFrom`.

---

## Cambios recientes (2026-04-16)

### Modo Vuelos (flight map view)
Nueva funcionalidad: botón ✈️ flotante en esquina derecha (lado opuesto al menú) alterna entre mapa de polígonos y vista de rutas aéreas. Al activarlo:
- Polígonos de países transparentes (cacheados, no se quitan, por rendimiento).
- Arcos de gran círculo (`MKGeodesicPolyline`) entre pares de aeropuertos únicos, color accent cobalto 0.85 alpha, line width 1.6pt, caps round.
- Cada aeropuerto visitado: punto blanco 10×10 con borde cobalto 2pt y sombra sutil.
- Zoom automático `setVisibleMapRect` para encuadrar todos los aeropuertos con padding.
- Taps en países deshabilitados mientras modo activo.
- Icono cambia ✈️ → 🗺 (`map.fill`) con color accent cuando activo.

### Lógica `FlightRoutesBuilder`
- Solo trips con `dateFrom <= hoy`.
- Con `tripSegments`: pares consecutivos de `airports` (ida) y `returnAirports` (vuelta) por cada segmento `✈️`. Escalas → múltiples arcos (MAD-LHR-JFK = MAD-LHR + LHR-JFK).
- Sin segmentos (legacy) y `transport == "✈️"`: solo si exactamente 2 aeropuertos (caso directo inequívoco); con 3+ se omite porque el orden se pierde al combinar ida+vuelta.
- Deduplicación vía `FlightRoutePair` (par no ordenado): ida+vuelta = misma línea, repetido = misma línea.

### Archivos
- **`airport_coords.json`**: 1031 entradas IATA→[lat,lng] de OpenFlights+OurAirports+fallback manual (HIX, ISF, MSD, QXB).
- **`FlightMap.swift`** (nuevo): `AirportCoordinates`, `FlightRoutePair`, `FlightRoutesBuilder`, `AirportDotAnnotation`.
- **`RaskMapView.swift`**: props `flightMode: Bool`, `trips: [Trip]`; `Coordinator.enterFlightMode`/`exitFlightMode`/`refreshFlightOverlaysIfNeeded`; `rendererFor` transparente si flightMode; `viewFor` rama `AirportDotAnnotation`; `handleTap` sale temprano.
- **`ContentView.swift`**: `@State flightMode`, helper `flightModeButton()` en `mapCore()`.

### Bug fix aeropuertos en `EditTripSheet`
`prepareEditSaveConfirmation()` rama sin segmentos: antes solo usaba `localAirports` (ida), ignorando `localReturnAirports` (vuelta). Vuelo directo round-trip contaba 1 en lugar de 2 por aeropuerto. Ahora combina con `apCombined` dict → MAD=2, JFK=2 correctos.

### `visitConfirmCard` → `confirmCardContent`
Eliminada implementación legacy; delega a `confirmCardContent` compartido (mismo look premium que planned/editVisit).

### Live Activity rediseñada
- Banner lock: fondo oscuro gradiente diagonal, bandera en círculo semi-transparente, nombre `Satoshi-Bold 12pt` secundario, días `Satoshi-Bold 38pt` grande, emoji transporte + label "PRÓXIMO" (tracking 1.2) a la derecha.
- Dynamic Island expanded: transporte+bandera leading, días trailing `Satoshi-Bold 30pt`, nombre center, "Próximo viaje" bottom.
- Compact trailing usa accent cobalto para el `Nd`.
- `ContentState` con nueva `transportEmoji: String` (ambas copias de `RaskmapActivityAttributes.swift`).

## Estructura de carpetas
```
Raskmap/
├── Raskmap/              ← código fuente principal
│   └── Assets.xcassets/
├── RaskmapWidget/        ← widget extension (iPhone/iPad)
│   └── Assets.xcassets/
├── RaskmapWatchWidgets/  ← widget extension watchOS (complicaciones)
├── RaskmapWatch Watch App/ ← app watchOS (placeholder)
├── RaskmapTests/
├── RaskmapUITests/
└── Raskmap.xcodeproj/
```

Archivos Swift en `Raskmap/`:
`AddSegmentSheet`, `ColorThemeManager`, `ContentView`, `Country`, `CountingMode`,
`GeoJSONLoader`, `LocationManager`, `RaskMapView`, `RaskmapApp`, `RaskmapActivityAttributes`, `SplashView`, `Trip`, `WidgetDataWriter`

Archivos Swift en `RaskmapWidget/`:
`RaskmapActivityAttributes`, `RaskmapLiveActivity`, `RaskmapWidget`, `RaskmapWidgetBundle`, `RaskmapWidgetControl`

Archivos Swift en `RaskmapWatchWidgets/`:
`RaskmapWatchWidget`, `RaskmapWatchWidgetBundle`

---

## Modelos de datos

### `Country` (@Model SwiftData)
```swift
var name: String
var isoCode: String       // ISO A3 (ej. "ESP") — identificador principal
var statusRaw: String     // rawValue de CountryStatus
var plannedDate: Date?
var plannedDateTo: Date?
var transport: String?
var plannedTitle: String?
var visitCount: Int       // visitas manuales extra (además de Trip records)
var hasLived: Bool        // indicador visual "he vivido aquí" — muestra 🏠 en lista visitados
```

### `Trip` (@Model SwiftData)
```swift
var isoCode: String
var title: String?
var dateFrom: Date
var dateTo: Date?
var transport: String?
var hasLayover: Bool
var airportsRaw: String?      // JSON [TripAirport]
var airlinesRaw: String?      // JSON [TripAirline]
var segmentsRaw: String?      // JSON [TripSegment]
var segmentGroupID: String?   // agrupa trip principal + hijos del mismo guardado
var isSegmentChild: Bool      // true = creado automáticamente desde un segmento
var flightInfoRaw: String?    // JSON FlightInfo — solo para trips no-segmento ✈️
// computed: var flightDetails: FlightInfo?  (get/set desde flightInfoRaw)
```

### `FlightInfo` (Codable, Equatable) — sin Sendable explícito
```swift
var bookingRef: String    // número de reserva, default ""
var seatNumber: String    // asiento formato "19A", default ""
var seatPosition: String  // "" | "pasillo" | "medio" | "ventana"
var cabinClass: String    // "" | "turista" | "economy+" | "business" | "first"
var hasAnyData: Bool      // true si algún campo no está vacío
```
- `Sendable` NO se declara explícitamente — Swift 6 lo infiere automáticamente (todos los campos son `String`). Declararlo explícitamente junto a `@Model` causa "Main actor-isolated conformance" error en Swift 6.
- Para viajes con segmentos: almacenado en `TripSegment.flightInfo: FlightInfo?`
- Para viajes sin segmentos (Próximos simples, legado): almacenado en `Trip.flightInfoRaw` vía `trip.flightDetails`
- UI compartida: `FlightInfoSection(info: $flightInfo)` — solo aparece cuando transporte == "✈️"
- Aparece en: `AddSegmentSheet` paso 3, `PlannedDatePickerSheet` (tras botón ruta), `EditTripSheet` (sección no-segmento ✈️)
- Al editar segmento existente, `flightInfo` se precarga desde `seg.flightInfo ?? FlightInfo()`

### `TripSegment` (Codable, dentro de segmentsRaw)
```swift
var transport: String
var isoCodes: [String]
var dateFrom: Date
var dateTo: Date?
var airports: [TripAirport]?        // ruta ida (ordenada) — solo ✈️
var returnAirports: [TripAirport]?  // ruta vuelta (ordenada) — solo ✈️
var airlines: [TripAirline]?
var hasLayover: Bool?
var visitedLayoverISOs: [String]?
var flightInfo: FlightInfo?         // info opcional reserva/asiento/clase — solo ✈️
```

### `CountryStatus` (enum)
`none` | `visited` (rojo) | `wantToVisit` (azul) | `lived` (verde) | `bucketList` (naranja)

### `CountingMode` (enum)
`un` (193) | `unPlus` (195) | `all` (249 territorios)

### `CountryFeature` (struct, no persistido)
Cargado desde `countries.geojson` por `GeoJSONLoader`. Tiene `isoCode` (A3), `isoA2`, polígonos MapKit y `boundingMapRect`.

---

## Convenciones

### Naming
- **ISO A3** (`isoCode`): identificador en `Country` y `Trip` (ej. `"ESP"`)
- **ISO A2** (`isoA2`): usado para emojis de bandera y `Locale.localizedString(forRegionCode:)`
- `isoA2 == "-99"` → territorio sin código ISO oficial
- Trips hijos tienen `isSegmentChild = true` y comparten `segmentGroupID`
- `totalVisits(for country)` = `country.visitCount + trips.filter { isoCode }.count`

### Arquitectura
- **SwiftUI + SwiftData** con CloudKit sync (fallback local si falla)
- Todo en un único archivo `ContentView.swift` (>6000 líneas) — NO refactorizar a múltiples archivos sin necesidad
- Sheets grandes como structs independientes al final de `ContentView.swift`
- `GeoJSONLoader` es estático/nonisolated, carga en background con `DispatchQueue.global`
- `ColorThemeManager.shared` singleton `@EnvironmentObject`
- `LocationManager.shared` singleton `@StateObject`

### Fuente
- Siempre `.font(.palatino(.body))`, `.font(.palatino(.title3, weight: .bold))`, etc.
- Extensión custom `Font.palatino(_:weight:)` — NO usar `.fontDesign(.serif)` ni `Font.custom`
- La extensión siempre devuelve **Satoshi** (Satoshi-Bold, Satoshi-Medium, Satoshi-Light, Satoshi-Regular). No hay selector de fuente ni soporte para Palatino.
- Widget y Live Activity usan `.system(size:weight:)` (SF Pro) porque Satoshi no está en el bundle del widget.
- `ContentView` tiene `@AppStorage("appFontFamily") private var _appFontFamily: String` (se mantiene por compatibilidad pero ya no afecta al render).

### Persistencia de preferencias
```swift
@AppStorage("username")           // String — nombre usuario
@AppStorage("countingMode")       // CountingMode.rawValue
@AppStorage("menuPosition")       // "bottom" | "top"
@AppStorage("showBucketList")     // Bool
@AppStorage("showCountdown")      // Bool
@AppStorage("topTable")           // JSON [String: String] — podio banderas
@AppStorage("multiContinentRaw")  // JSON — asignación continente de países pluricontinentales
@AppStorage("didShowLocationToast") // Bool — toast solo la primera vez
@AppStorage("favoriteAirport")    // String IATA — aeropuerto favorito (vacío = ninguno)
@AppStorage("isRaskmapPro")       // Bool — activa funciones Pro
@AppStorage("raskmapProPlanID")   // String — ID del plan activo: "com.raskmap.pro.monthly" | "com.raskmap.pro.lifetime" | ""
@AppStorage("appFontFamily")      // "satoshi" (default) | "palatino"
@AppStorage("widgetBgColorHex")   // String hex — color de fondo del widget (default "#EE6E7D")
@AppStorage("liveActivityEnabled") // Bool — Live Activity del próximo viaje activa
@AppStorage("neverShowReview")     // Bool — el usuario eligió "No mostrar más" en el alert de valoración
```

### Defaults primera ejecución
- `menuPosition` → `"bottom"`
- Países pluricontinentales (cuando `topTable == "{}"`) usan `primary`:
  - RUS → Europa, TUR → MedioOriente, CYP → Europa, AZE → Asia, GEO → Asia, KAZ → Asia, EGY → África

---

## Dependencias externas
**Ninguna.** Solo frameworks nativos: SwiftUI, SwiftData, MapKit, CoreLocation, WidgetKit, ActivityKit, CloudKit, MessageUI, Photos, Combine.

---

## Decisiones técnicas importantes

**GeoJSON + MapKit polygons**
- `countries.geojson` (Natural Earth) cargado una vez al arrancar
- Simplificación Ramer-Douglas-Peucker adaptativa por área del polígono:
  - >500°² → 0.05°, >50°² → 0.02°, >5°² → 0.01°, >0.01°² → 0.002°, ≤0.01°² → 0.0
- ZAF (Sudáfrica) tiene hueco real (Lesoto) vía rings del GeoJSON. ITA (Italia) tiene hueco del Vaticano inyectado manualmente en `loadCountries()` tras cargar el GeoJSON: se busca el polígono continental de mayor bounding box, se extrae con `getCoordinates`, y se recrea con `vaticanRing` (36 pts exactos del GeoJSON) como interior polygon (hole)
- Musandam (Omán) no está en el GeoJSON → polígono hardcodeado en `GeoJSONLoader`
- Tras cargar el GeoJSON, varios países tienen sus polígonos reemplazados por anillos hardcodeados de alta precisión en `GeoJSONLoader.loadCountries()`:
  - **MCO** (Mónaco): 865 pts cosidos desde OSM Overpass relation 36990 (29 outer ways)
  - **AND** (Andorra): 45 pts de geo-countries, RDP(0.001°)
  - **MAR** (Marruecos): 345 pts — polígono MAR de geo-countries partido a 27.6667°N (norte de esa línea)
  - **ESH** (Sáhara Occidental): 211 pts — mismo polígono MAR partido a 27.6667°N (sur de esa línea)
- `applyStyle` usa `lineWidth = highlighted ? 1.0 : 0.5` para todos los polígonos (coloreados y no coloreados). No hay distinción por tamaño — garantiza borde uniforme en exclaves pequeños como Musandam

**Conteo de visitas**
- 1 `Trip` record = 1 visita. `country.visitCount` son visitas manuales extra.
- Un viaje con N segmentos que tocan el mismo país crea (N-1) trips hijo extra con `isSegmentChild = true`
- Antes de guardar siempre se muestra `VisitEntry` confirmation overlay con contadores ajustables
- `country.hasLived` es puramente visual: muestra 🏠 en `AllCountriesRowView` junto al contador Nx. Se resetea al desmarcar el país de visitado.

**Aeropuerto favorito**
- Se guarda en `@AppStorage("favoriteAirport")` como código IATA.
- Se selecciona en Ajustes con `FavoriteAirportPickerSheet` (lista completa, buscable, selección única, botón Aceptar).
- En `RouteWizardSheet`, aparece primero con ⭐️ en los pasos `.departure` (Aeropuerto de salida) y `.returnFinalDest` (Vuelta · Destino). No se muestra en el destino de ida ni en escalas.

**Conteo por regiones**
- `MapExportSheet.zoneCounter` aplica `AchievementKind.adjustSet()` usando `multiContinentRaw` para que países pluricontinentales se cuenten en la zona elegida en Ajustes.
- `ExportZone` tiene propiedad `zoneName: String` que mapea al nombre clave usado en `multiContinentData`.

**Sheets y toolbar**
- Todos los NavigationStack en sheets tienen `.toolbarBackground(.visible, for: .navigationBar)` excepto `ProfileSheet`, que usa `.hidden` para preservar el efecto liquid glass de iOS 26.
- `ProfileSheet` usa `.presentationDetents([.fraction(0.70)])` + `.presentationDragIndicator(.visible)`. Un único detent — no se puede deslizar a pantalla completa. Sin ScrollView interno. `.toolbarBackground(.hidden)` para preservar liquid glass de iOS 26.
- Bug bucle infinito en `TransportStatsSheet`: `TransportFilter.id` debe ser determinístico (`emoji + label`), nunca `UUID()`.
- `TransportTripsListSheet.sorted` filtra por transporte mirando `trip.transport` Y los segmentos del trip padre: incluye si cualquier segmento usa el transporte. Trips hijos usan solo su propio `trip.transport`.
- `CountryTripsSheet` tiene botón de ordenación (↑/↓ por `dateFrom`) y toggle "He vivido aquí" (`country.hasLived`).

**Rutas de vuelo**
- `TripSegment.airports` = ruta ida (ordenada)
- `TripSegment.returnAirports` = ruta vuelta (ordenada, nil = solo ida)
- Destino = `airports.last`, escalas = intermedios de cada ruta por separado
- Estadísticas globales combinan ida + vuelta en `Trip.airportsRaw`
- En `AddSegmentSheet` paso 3, el resumen de ruta (códigos IATA + aerolínea) está alineado al **centro** (`VStack(alignment: .center)` + `.frame(maxWidth: .infinity, alignment: .center)`)
- En `AddSegmentSheet`, el paso de escala muestra primero "✈️ Vuelo directo" (azul, acción primaria) y luego "🔄 Con escala(s)" (gris). Aplica tanto al vuelo de ida como al de vuelta.

**Selector de rango de fechas (`RangeDatePicker`)**
- Componente `UIViewRepresentable` sobre `UICalendarView` con `UICalendarSelectionSingleDate`.
- Al elegir fecha de ida (DESDE), la vuelta (HASTA) se auto-establece al día siguiente por defecto. Si `maxDate` está definido (viajes pasados) y el día siguiente lo supera, dateTo queda nil.
- Al cambiar de tab DESDE/HASTA, el calendario navega automáticamente al mes de la fecha relevante (`setVisibleDateComponents(_:animated:)`).
- Al tocar una fecha en tab HASTA igual a dateFrom → dateTo = nil ("Sin vuelta"). Si es anterior a dateFrom → se convierte en nueva ida con vuelta al día siguiente.
- `PlannedDatePickerSheet` init: cuando no hay fecha existente, `dateTo` se inicializa como `dateFrom + 1 día`.
- `AddSegmentSheet` init: al crear segmento nuevo, `dateTo` se inicializa como `dateFrom + 1 día`.
- `PlannedDatePickerSheet` tiene `minDate: tomorrow` (solo futuros). `AddSegmentSheet` usa `minDate: tomorrow` para futuros y `maxDate: today` para pasados.

**Widgets en Ajustes**
- "Pantalla de bloqueo" → abre `WidgetLockScreenSheet`: lista los 3 widgets (% del mundo circular, próximo viaje rectangular, cuenta atrás inline) con su descripción.
- "Apple Watch" → abre `WidgetWatchSheet`: lista los 3 widgets (próximo viaje circular, próximo viaje rectangular, países visitados circular) con su descripción.
- "Pantalla principal" (`WidgetHomeColorSheet`): preview del widget real (tamaño small) con layout idéntico al `RaskmapSmallView`. Paleta de 10 colores predefinidos. Debajo de la paleta hay una sección "Tamaños disponibles" (Pequeño / Mediano / Grande) con descripción de cada uno.
- `RaskmapWidget` usa `.contentMarginsDisabled()` — elimina los márgenes del sistema (~11pt) para control manual. El pequeño usa `.padding(15)`, el grande `.padding(16)`.
- Íconos en `WidgetLockScreenSheet` y `WidgetWatchSheet`: `.font(.system(size: 16)).frame(width: 24)` con `HStack(spacing: 12)` y `.padding(.horizontal, 24)` — idéntico a la sección "Tamaños disponibles" de `WidgetHomeColorSheet`. `Divider().padding(.leading, 60)` entre filas. NUNCA usar `.resizable().aspectRatio` aquí.
- En `colorPickerSection` (Colores del mapa): botón "Cambiar colores" (azul) va por encima de "Restablecer colores predeterminados" (rojo).
- Errores SourceKit de `accessoryCircular/Rectangular/Inline` en RaskmapWidget.swift son falsos positivos del indexado macOS — válidos en iOS/watchOS.

**Confirm cards (visitConfirmCard / plannedConfirmCard / editVisitConfirmCard)**
- **NO usan `fullScreenCover`** — se muestran como overlay `ZStack` inline dentro del `body` de cada sheet (`AddTripSheet`, `PlannedDatePickerSheet`, `EditTripSheet`). Patrón: `if showXxx { confirmCard(...) }` dentro de un `ZStack { NavigationStack { ... } ... }`.
- Razón: `fullScreenCover` evaluaba el contenido con estado stale en la primera presentación cuando se usaba desde dentro de otro modal (race condition UIKit vs SwiftUI).
- `resignFirstResponder` se llama al **inicio** de cada `prepareXxxConfirmation()`, antes de asignar el estado, para evitar que el dismiss del teclado interfiera con la transacción SwiftUI.
- Estructura de secciones: PAÍSES → (Divider) → AEROPUERTOS → AEROLÍNEAS. La última aerolínea NO lleva divider inferior (verificado con `al.id != confirmAirlines.last?.id`).
- `EditTripSheet` tiene fallback a `trip.tripAirports`/`trip.tripAirlines` para viajes pre-segmentos.

**Banner publicitario (AdMob)**
- `BannerAdView.swift`: `UIViewRepresentable` wrapping `GADBannerView` 320×50. SDK: `GoogleMobileAds` via SPM (`https://github.com/googleads/swift-package-manager-google-mobile-ads`).
- Posición: mismo espacio que el contador — arriba con `menuPosition == "bottom"`, abajo con `menuPosition == "top"`.
- Lógica en ContentView:
  - `!isRaskmapPro` → `BannerAdView()` visible siempre
  - `isRaskmapPro && showCountdown && cachedNextBanner != nil` → contador
  - `isRaskmapPro && !showCountdown` → nada
- `kAdUnitID` en `BannerAdView.swift` línea 16: contiene el ID de prueba de Google. **Sustituir por el ID real antes de publicar.**
- Requiere `GADApplicationIdentifier` en `Info.plist` (App ID de AdMob, distinto del Ad Unit ID).

**Raskmap Pro — features bloqueadas**
- `@AppStorage("isRaskmapPro") var isRaskmapPro: Bool = false` presente en cada struct que lo necesita.
- Patrón de bloqueo: `View.blur(radius: isRaskmapPro ? 0 : N).allowsHitTesting(isRaskmapPro)` + `Image(systemName: "lock.fill")` en ZStack overlay.
- Features Pro activas:
  - Toggle "Mostrar contador" en Ajustes (solo el toggle blur, el label queda legible)
  - Banner countdown "Quedan X días para" en pantalla principal — solo visible con Pro (sin Pro se muestra el banner de AdMob)
  - Toasts de logros: si no es Pro, no se muestran (sin toasts en absoluto)
  - Toggle "Live Activities" en Ajustes → Widgets (blur + candado morado) — además `startOrUpdateLiveActivity()` guarda internamente `isRaskmapPro` en el guard, así que sin Pro no se lanza aunque el toggle esté activo
  - Widgets de pantalla de bloqueo (`LockPctWidget`, `LockNextWidget`, `WatchFlagsWidget`) — muestran `lock.fill` si `widget_is_pro == false` en App Group
- **MedalleroSheet ("Premios personales") ya NO requiere Pro** — acceso libre
- Si se revoca el Pro y `liveActivityEnabled` estaba activo, `onChange(of: isRaskmapPro)` termina todas las Live Activities activas
- `WidgetDataWriter.syncPro(_ isPro: Bool)` escribe `widget_is_pro` al App Group — se llama al arrancar y en `onChange(of: isRaskmapPro)`

**Toasts de logros (achievements)**
- Implementados via `AchievementToastController.shared.show(...)` → crea un `UIWindow` con `windowLevel = .alert + 1` para aparecer sobre cualquier modal/sheet.
- Posición: arriba-derecha si menú está abajo (default), abajo-derecha si menú está arriba.
- Se disparan en `ContentView.checkAndShowAchievementToasts()`, llamada en 3 `onChange`: `multiContinentRaw`, `trips.count`, `mapQuadrantsData`. También en `autoMarkIfNeeded` (auto-marca por ubicación, sin trip).
- **NO** hay `onChange(of: visitedIsoSet)` — los toasts se disparan al guardar el viaje (cuando `trips.count` cambia), no al marcar el país visitado. Esto evita que salten al tocar "Añadir viaje pasado".
- `prevAchieved: Set<AchievementKind>?` (state en ContentView) guarda el estado anterior para detectar nuevos logros desbloqueados.
- Si se consiguen varios a la vez se apilan verticalmente (ForEach en `AchievementToastView`).
- Duración: 4 segundos, luego la UIWindow se oculta y se libera.

**Widget (pantalla principal)**
- `WidgetDataWriter` sincroniza datos al App Group `group.com.jaime.raskmap` via `UserDefaults(suiteName:)` — **NO** usar `NSUbiquitousKeyValueStore` (no está configurado, produce error de sandbox)
- Keys en App Group UserDefaults:
  - `"widget_visited_un"`, `"widget_visited_unPlus"`, `"widget_visited_all"` — conteos por modo
  - `"widget_bg_color"` (hex) — color fondo widget home
  - `"appFontFamily"` — fuente (no usada en widget, se mantiene por compatibilidad)
  - `"widget_next_flag"` — emoji bandera del próximo viaje
  - `"widget_next_days"` — días hasta el próximo viaje (-1 = sin viaje)
  - `"widget_next_name"` — nombre localizado del país del próximo viaje
  - `"widget_next_title"` — título personalizado del viaje (`Trip.title` / `country.plannedTitle`); vacío = usar `widget_next_name`
  - `"widget_next_transport"` — emoji del medio de transporte del próximo viaje
  - `"widget_next_date"` — timestamp del próximo viaje (Double, TimeInterval)
  - `"widget_is_pro"` — Bool; escrito por `WidgetDataWriter.syncPro(_:)`
  - `"widget_all_flags"` — String concatenando emojis de todos los próximos viajes en orden de fecha; escrito por `WidgetDataWriter.syncAllFlags(_:)`
- `WidgetDataWriter.syncColor(hex:)`, `.syncFontFamily(_:)`, `.syncNextTrip(flag:days:name:transport:dateFrom:bookingRef:title:)`, `.syncPro(_:)`, `.syncAllFlags(_:)`, `.syncCountingMode(_:)` — todos llaman a `WidgetCenter.shared.reloadAllTimelines()` (excepto `syncFontFamily` y `syncCountingMode`)
- `widget_next_booking` — código de reserva del próximo viaje (String, "" = sin reserva)
- `widget_counting_mode` — modo de conteo ("un" | "unPlus" | "all"); leído en `makeEntry()` para seleccionar la key `widget_visited_*` correcta
- `onChange(of: countingModeRaw)` en SettingsSheet → `WidgetDataWriter.syncCountingMode(_:)`
- Color se configura en Ajustes → Widgets → Pantalla principal (`WidgetHomeColorSheet`): paleta de 10 colores con preview del widget. Default: `#EE6E7D`
- Fuente en el widget: SF Pro (Satoshi no está en el bundle del widget extension)
- `Color(hex:)` extension en `ContentView.swift` convierte hex string a SwiftUI Color

**Tamaños de `RaskmapWidget` (`.systemSmall`, `.systemMedium`, `.systemLarge`)**

`RaskmapEntry` incluye:
- `transport, tripFlag, tripName, tripTitle, daysRemaining, tripDateFrom, bgColor` — info próximo viaje
- `tripTitle: String` — título personalizado del viaje; vacío = usar `tripName` (nombre del país)
- `visitedCount: Int` — leído de `widget_visited_*` según modo
- `upcomingFlags: String` — leído de `widget_all_flags`
- `bookingRef: String` — leído de `widget_next_booking`
- `countingMode: WCountingMode` — leído de `widget_counting_mode`

`widgetDateFormatter`: locale `es_ES`, formato `"EEE, d MMM yyyy"` → "lun., 4 jul. 2026"

Lógica de nombre mostrado en las vistas: `let displayName = entry.tripTitle.isEmpty ? entry.tripName : entry.tripTitle`

`RaskmapWidgetView` despacha vía `@Environment(\.widgetFamily)`:
- **Small** (`RaskmapSmallView`): `ZStack(alignment:.topLeading)` — transporte arriba-izquierda, si hay `bookingRef` muestra `#CODIGO` arriba-derecha (monospaced **13pt**, igual que el nombre del país), bandera+displayName(13pt semibold azul)+días(22pt medium)+fecha(12pt) abajo-izquierda. `.padding(15)`.
- **Medium** (`RaskmapMediumView`): `ZStack(alignment:.topTrailing)` externo — interior `HStack`: columna izquierda 70pt con icono de transporte, divisor vertical, columna derecha con bandera+displayName(16pt)+días(32pt medium)+fecha(13pt). Si hay `bookingRef` aparece arriba-derecha (13pt monospaced) con `.padding(.trailing, 15)`. `.padding(5)`.
- **Large** (`RaskmapLargeView`): `ZStack(alignment:.topTrailing)` externo — interior `VStack`: próximo viaje (transporte 32pt, gap `.padding(.top, 48)`, displayName 17pt, días 36pt medium, fecha 14pt) → divisor → progress bar países visitados con conteo dinámico → divisor → "Próximos destinos" con `upcomingFlags`. Si hay `bookingRef` aparece arriba-derecha. `.padding(16)`.

**Widgets disponibles**
| Widget | Kind | Familia | Target | Libre/Pro |
|---|---|---|---|---|
| `RaskmapWidget` | `"RaskmapWidget"` | `.systemSmall, .systemMedium, .systemLarge` | RaskmapWidget | Libre |
| `RaskmapLockPctWidget` | `"RaskmapLockPct"` | `.accessoryCircular` | RaskmapWidget | Pro |
| `RaskmapLockNextWidget` | `"RaskmapLockNext"` | `.accessoryRectangular` | RaskmapWidget | Pro |
| `RaskmapLockInlineWidget` | `"RaskmapLockInline"` | `.accessoryInline` | RaskmapWidget | Pro |
| `RaskmapWatchFlagsWidget` | `"RaskmapWatchFlags"` | `.accessoryRectangular` | RaskmapWidget | Pro |
| `RaskmapWatchNextWidget` | `"RaskmapWatchNext"` | `.accessoryCircular` | RaskmapWatchWidgets | Pro |
| `RaskmapWatchNextRectWidget` | `"RaskmapWatchNextRect"` | `.accessoryRectangular` | RaskmapWatchWidgets | Pro |
| `RaskmapWatchCounterWidget` | `"RaskmapWatchCounter"` | `.accessoryCircular` | RaskmapWatchWidgets | Libre |

- `RaskmapLockInlineWidget`: aparece encima del reloj en la pantalla de bloqueo. Muestra "Quedan X días · Tokio" (solo nombre de destino, sin bandera). Sin Pro → `lock.fill`. Sin viaje → `Sin próximo viaje ✈️`. Reutiliza `LockNextProvider` (lee `widget_next_flag`, `widget_next_days`, `widget_next_name`, `widget_is_pro`).
- `RaskmapWatchFlagsWidget`: muestra `widget_all_flags` (emojis concatenados de todos los próximos viajes) en una línea con `minimumScaleFactor(0.4)`. Funciona en Apple Watch y pantalla de bloqueo. Si no hay Pro → `lock.fill`. Si no hay viajes → `✈️ Sin próximos viajes`.
- `allProximosFlagsString` en ContentView computa las banderas de wantToVisit + visited con trip futuro, ordenadas por fecha.
- Complicaciones watchOS (`RaskmapWatchWidgets`): leen del App Group `group.com.jaime.raskmap`. `RaskmapWatchNextWidget` (circular, bandera), `RaskmapWatchNextRectWidget` (rectangular, bandera+días+nombre), `RaskmapWatchCounterWidget` (circular gauge, países ONU visitados). Requieren que el target tenga el App Group entitlement configurado en Xcode.

**Live Activities**
- `RaskmapTripAttributes: ActivityAttributes` definido en `RaskmapActivityAttributes.swift`, incluido en **ambos targets** (app + widget) gracias a `fileSystemSynchronizedGroups` — hay una copia en `Raskmap/` y otra en `RaskmapWidget/`
- `NSSupportsLiveActivities = true` en los `Info.plist` de ambos targets
- Toggle en Ajustes → Widgets → Live Activities (bloqueado con Pro)
- `startOrUpdateLiveActivity()` en ContentView: guard `liveActivityEnabled && isRaskmapPro` — **sin Pro nunca lanza** aunque el toggle esté activo. También comprueba `ActivityAuthorizationInfo().areActivitiesEnabled`. Se llama tras cargar el GeoJSON, en `scenePhase == .active` y en `onChange(of: liveActivityEnabled/liveActivityKey)`
- `liveActivityKey: String` = `"\(isoCode)_\(days)"` — `onChange` de esta clave actualiza la LA cuando cambia el próximo viaje
- Lock Screen: bandera + "Quedan X días" centrados, `containerBackground(.clear, for: .widget)` para dejar el fondo por defecto del sistema
- Dynamic Island compact trailing: si `daysRemaining > 99` muestra `"+Xm"` (meses); si no, `"Xd"`
- Dynamic Island compact: bandera izquierda · días derecha. Expanded: bandera leading · días trailing · nombre país center
- Fuente en la LA: `.system(size:weight:)` (SF Pro) — Satoshi no disponible en widget extension

---

## TODOs / Bugs conocidos
- Los viajes antiguos (pre-`returnAirports`) solo tienen `airports` (ruta ida). La UI hace fallback legacy correctamente.
- Los trips hijos (`isSegmentChild = true`) se resuelven al padre en `CountryTripsSheet.tripRow` via `resolvedParent(for:)` — la UI siempre muestra y edita el padre. Editar desde cualquier país del grupo modifica el padre y regenera los hijos en `performEditSave`.
- `PersonalAwardModel` existe en SwiftData pero su gestión UI está en `ContentView.swift`.

---

## 🚀 Pendiente antes de subir a la App Store

### Paso 1 — Pagar la licencia Apple Developer ($99/año)
Sin licencia activa no se puede subir nada ni activar iCloud/CloudKit.

### Paso 2 — Tras activar la licencia (en Xcode → Signing & Capabilities)
- [ ] Activar **iCloud** → CloudKit → container `iCloud.com.jaime.raskmap`
- [ ] Activar **App Groups** → `group.com.jaime.raskmap` (necesario para widget y Live Activities)
- [ ] Activar **Push Notifications** (necesario para sync CloudKit en background)
- [ ] Activar **In-App Purchase** (necesario para Raskmap Pro)

### Paso 3 — Crear los productos In-App Purchase en App Store Connect
- [ ] **Non-Consumable** → ID: `com.raskmap.pro.lifetime` → precio: **4,99 €** → Pago único vitalicio
- [x] ID hardcoded en `ContentView.swift` como `raskmapProLifetimeID` (suscripción mensual eliminada)
- ⚠️ **Crítico:** elegir **Non-Consumable**, NO «Auto-Renewable Subscription» — los términos de uso ya declaran «pago único, no suscripción». Si se configura mal en App Store Connect, App Review lo rechazará por inconsistencia.

### Paso 4 — Hostear Política de Privacidad en URL pública (obligatorio App Store Connect)
- [x] Textos legales reescritos para cumplir Apple + AEPD (`ContentView.swift:4631-4659`)
- [x] Carpeta `docs/` creada en raíz del repo con los 5 documentos en Markdown listos
- [ ] Crear repo público en GitHub (p. ej. `raskmap-legal`) y subir `docs/`
- [ ] Settings → Pages → Source: rama `main`, carpeta `/docs` → activar
- [ ] Esperar ~1 min y copiar la URL final (`https://<usuario>.github.io/<repo>/privacy`)
- [ ] Pegar en App Store Connect → App Information → **Privacy Policy URL**
- [ ] Pegar también en **Support URL** (puede ser el `index.md`)
- [ ] (Opcional) Configurar dominio propio `raskmap.app` añadiendo `CNAME` en `docs/`

### Paso 5 — Monetización (decidir antes de subir v1.0)

**Estado actual:** la Política de Privacidad declara explícitamente que **NO hay publicidad ni terceros**. Coherente con el código: no hay AdMob integrado, solo IAP de Raskmap Pro.

⚠️ **Si se decide añadir AdMob después** habrá que actualizar **simultáneamente**:
1. Política de privacidad in-app (`ContentView.swift:4631`)
2. Política de privacidad pública (`docs/privacy.md`)
3. App Privacy questionnaire en App Store Connect (declarar tracking + ad ID)
4. Atribuciones (`ContentView.swift:4659` + `docs/credits.md`)

Pasos AdMob (si se hace):
- [ ] Crear cuenta en [admob.google.com](https://admob.google.com)
- [ ] Registrar la app → obtener **App ID** (`ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX`)
- [ ] Crear unidad de anuncio tipo **Banner** → obtener **Ad Unit ID** (`ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX`)
- [ ] Añadir SDK en Xcode: `File → Add Package Dependencies` → `https://github.com/googleads/swift-package-manager-google-mobile-ads` → target `Raskmap`
- [ ] Añadir en `Info.plist`: `GADApplicationIdentifier = <App ID>`
- [ ] En `BannerAdView.swift` línea 16: sustituir el test ID por el **Ad Unit ID** real

### Paso 6 — App Store Connect: ficha de la app
- [ ] Rellenar **App Privacy questionnaire** → declarar **«Data Not Collected»** (consistente con la política)
- [ ] **Privacy Policy URL** ← del Paso 4
- [ ] **Support URL** ← del Paso 4
- [ ] **App Review Contact** → poner `raskmap_soporte@icloud.com`
- [ ] **Age Rating**: 4+ (sin contenido cuestionable, no UGC compartido)
- [ ] Nombre, subtítulo, descripción localizada (ES + EN)
- [ ] Capturas de pantalla (6.9" para iPhone 16 Pro Max es el tamaño actual obligatorio; 6.5" si soporte iPhone 8 Plus)
- [ ] Icono definitivo 1024×1024 sin transparencia, sin esquinas redondeadas
- [ ] Categoría: Travel o Lifestyle
- [ ] Precio: Gratis (el Pro es In-App Purchase)

### Paso 7 — Probar con TestFlight antes del lanzamiento público
- [ ] Archivar en Xcode → Product → Archive → Distribute App → TestFlight
- [ ] Revisar que `v.1.0` en SplashView coincide con el Build/Version de Xcode
- [ ] Probar en al menos 2 dispositivos físicos: pago IAP en sandbox, sync iCloud entre dispositivos, widgets en pantalla de bloqueo y Home, Live Activities

---

## Cambios relevantes recientes (sesión 2026-04-15, parte 2) — Remodelación UI/UX

### Paleta de colores

Colores por defecto actualizados en `ColorThemeManager.swift`:
- **visited**: `#C9503E` (terracota profunda — antes coral #EE6E7D)
- **wantToVisit**: `#4072D4` (cobalto — antes azul brillante #53A3FE)
- **lived**: `#3E9068` (esmeralda — antes verde neón #71EB71)
- **bucketList**: `#E08B35` (ámbar cálido — antes naranja #FF9933)

Nota: el cambio solo afecta a instalaciones nuevas. Usuarios existentes con defaults guardados en UserDefaults ven los suyos; pueden resetear en Ajustes → Colores del mapa.

### Acento de UI en sheets

Color de acento unificado en todos los sheets: `Color(red: 64/255, green: 114/255, blue: 212/255)` (`#4072D4`, mismo que el nuevo wantToVisit). Definido como `private let accent` en cada struct que lo necesita.

### Redesign de AddSegmentSheet

- **Step 1 (Transporte)**: Grid 2×3 con tarjetas grandes (56pt emoji en círculo, 22pt padding vertical). Tarjeta seleccionada: fondo `accent.opacity(0.08)` + borde `accent.opacity(0.35)`.
- **Step 2 (Países)**: Campo de búsqueda con fondo `systemGray6` 12pt radius; chips de países seleccionados con borde `accent.opacity(0.2)` en Capsule.
- **Step 3 (Fechas)**: Header con emoji de transporte; tarjeta de ruta de vuelo con fondo `accent.opacity(0.06)`; layover choices con círculo `accent` relleno cuando checked; date tabs como cards independientes con borde al activarse.
- **Botón de acción**: `Satoshi-Bold 16pt`, corner 14pt, sombra `accent.opacity(0.3)`.
- **NavigationTitle**: simplificado a "Nuevo tramo" / "Países" / "Fechas".

### Redesign de FlightInfoSection

- Sección header "DETALLES DEL VUELO" con tracking 1.0.
- Iconos `ticket.fill` y `seat.fill` en accent color a la izquierda.
- Input de reserva en `Satoshi-Bold` accent; separadores 0.5pt gris en lugar de Divider.
- Corner radius: 16pt (antes 12pt).

### Redesign de PlannedDatePickerSheet

- Header visual: emoji de país grande (52pt) + nombre (`Satoshi-Bold 24pt`) + subtítulo secondary.
- Eliminado el emoji 📅 del navigationTitle; title vacío (header está en contenido).
- Sección "TÍTULO DEL VIAJE" (si isEditing) con tracking.
- Sección "TRANSPORTE": pills con borde accent cuando seleccionado.
- Sección "RUTA DE VUELO": botón con círculo accent a la izquierda (patrón consistente).
- Sección "FECHAS": date tabs como cards independientes (mismo patrón que AddSegmentSheet).
- Corner radius de cards: 14pt.

### Redesign de EditTripSheet

- Sección "TÍTULO DEL VIAJE" al top con card 14pt radius.
- Sección "TRANSPORTE": pills con estilo consistente con PlannedDatePickerSheet.
- Sección "FECHAS": separador 0.5pt entre rows, card radius 14pt.
- Sección "RUTA DE VUELO": botón con círculo accent.
- Sección "TRAMOS": círculo gris 40pt con emoji de transporte; botones de editar/eliminar más grandes (22pt); botón "Añadir transporte" con círculo accent.
- Rango calculado desde segmentos: dos cards independientes DESDE/HASTA lado a lado.
- navigationTitle: "Editar viaje" (antes "✏️ Editar viaje").

### Redesign de confirm cards (visitConfirmCard / editVisitConfirmCard)

Ambas tarjetas ahora usan el struct compartido `confirmCardContent` (struct privado al final de PlannedDatePickerSheet en ContentView.swift). Patrón DRY.

Nuevo diseño:
- Overlay: `Color.black.opacity(0.55)`.
- Card: `RoundedRectangle(cornerRadius: 24)` con sombra `black.opacity(0.25), radius:30, y:10`.
- Header: círculo accent con checkmark + título `Satoshi-Bold 18pt` + subtítulo secondary.
- Separadores: `Rectangle 1pt systemGray5` en lugar de `Divider`.
- Sección headers: tracking 0.8.
- Stepper: botón `−` (fondo `systemGray5`) + contador `Satoshi-Bold 16pt` + botón `+` (fondo accent). Tamaño 34pt.
- Botones footer: "Cancelar" `Satoshi-Medium 15pt` fondo gray5, "Guardar" `Satoshi-Bold 15pt` fondo accent. Corner 12pt.

### Redesign de RaskmapMediumView (widget mediano)

- Eliminado el layout con columna izquierda (70pt) + divisor vertical.
- Nuevo layout full-bleed vertical: transporte emoji top-left (20pt, `.white.opacity(0.65)`); `Spacer`; flag+nombre+días+fecha bottom-left.
- Días: 34pt medium (antes 32pt).
- `bookingRef`: 11pt monospaced, `.white.opacity(0.55)` (antes 13pt, 0.75 opacity).
- Padding: 16pt (antes 5pt).

### Redesign de RaskmapLargeView (widget grande)

- Sección próximo viaje: layout `HStack(alignment:.bottom)` — izquierda: transporte+flag+nombre en una línea + días 44pt; derecha: fecha alineada al bottom.
- Sección países visitados: `HStack` con 🌍 + número 22pt semibold + barra de progreso 5pt height. Separadores: `white.opacity(0.18)` (antes 0.25).
- Sección próximos: label "PRÓXIMOS" en tracking 1.0 uppercase (antes "Próximos destinos").
- `bookingRef`: 11pt, 0.50 opacity (antes 13pt, 0.75).

### raskmapBlue (widget)

Color actualizado a `Color(red: 0x8B/255.0, green: 0xB8/255.0, blue: 1.0)` — azul pastel más legible sobre fondos de color saturado.

---

## Cambios relevantes recientes (sesión 2026-04-15)

### Widget pantalla principal — mejoras visuales y de datos

**`RaskmapEntry` — nuevo campo `tripTitle: String`**
- Fuente: `ProximoRow.rowTitle` = `trip?.title ?? country.plannedTitle` para países wantToVisit; `trip.title` para visited con trip futuro.
- `nextProximosBanner` devuelve ahora `title: String?` (campo añadido a la tupla). `cachedNextBanner` también actualizado.
- `WidgetDataWriter.syncNextTrip(flag:days:name:transport:dateFrom:bookingRef:title:)` — nuevo parámetro `title`; escribe `widget_next_title`.
- En todas las vistas del widget: `let displayName = entry.tripTitle.isEmpty ? entry.tripName : entry.tripTitle` — muestra el título del viaje si existe, si no el nombre del país.

**Formato de fecha — día de la semana**
- `widgetDateFormatter` usa formato `"EEE, d MMM yyyy"` con locale `es_ES` → "lun., 4 jul. 2026".
- Anteriormente usaba `dateStyle: .medium` (sin día de la semana).

**Número de reserva — tamaño unificado**
- En Small, Medium y Large: `bookingRef` se muestra con font size **13** (monospaced semibold), igual que el nombre del país. Antes era 10pt solo en small.
- Medium y Large: `bookingRef` añadido arriba-derecha usando `ZStack(alignment: .topTrailing)` externo.

**Tamaños de fecha actualizados:** Small 11→12, Medium 12→13, Large 13→14.

**Widget Large — más padding y espacio bajo el transporte**
- `.padding` general: 10→16.
- Gap entre emoji de transporte y la info del viaje: `.padding(.top, 36)` → `.padding(.top, 48)`.

**Preview `WidgetHomeColorSheet`**
- Sincronizada con `RaskmapSmallView` real: `.padding(15)`, `bookingRef` arriba-derecha (13pt), fecha con día de semana, `weight: .medium` en días, `font(.system(size: 13))` para nombre.

**Íconos en `WidgetLockScreenSheet` y `WidgetWatchSheet`**
- Unificados con `WidgetHomeColorSheet`: `.font(.system(size: 16)).frame(width: 24)`, `HStack(spacing: 12)`, `.padding(.horizontal, 24)`, `Divider().padding(.leading, 60)`. `Spacer()` en cada fila.

---

### Rendimiento del mapa — color change FPS fix (`RaskMapView.swift`)

**`Coordinator.refreshRendererColors()`** — optimización crítica:
- Antes: llamaba `renderer.setNeedsDisplay()` en TODOS los renderers cacheados (potencialmente 100s de polígonos), bloqueando el main thread y causando freeze al hacer pan.
- Ahora: calcula `visibleISOs` via `mv.visibleMapRect` + `boundingMapRect.intersects`. Solo llama `setNeedsDisplay()` en polígonos visibles. Todos los demás reciben `applyStyle` (color actualizado en `fillColor`/`strokeColor`) sin forzar redibujado inmediato — MapKit los renderiza con el color nuevo cuando el usuario hace pan.

**`mapView(_:rendererFor:)` fallback** — eliminada búsqueda O(n):
- Antes: `lastKnownStatus[polygon.isoCode] ?? parent.countries.first { $0.isoCode == polygon.isoCode }?.status ?? .none`
- Ahora: `lastKnownStatus[polygon.isoCode] ?? .none` — O(1), evita bloqueo del main thread al renderizar polígonos sin caché durante el pan.

---

### Botones de info en ajustes pluricontinentales/hemisféricos

**`MultiContinentSheet`**
- Botón `info.circle` en `.navigationBarTrailing`.
- Overlay (mismo patrón que AllCountriesSheet): fondo semitransparente, tarjeta `.regularMaterial`, icono `info.circle.fill` azul, texto explicativo, botón "Entendido". Animado con `.spring(duration: 0.3)`.
- Texto: explica que la elección afecta a estadísticas por regiones y logros de continentes completos.

**`MultiHemisphereSheet`**
- Mismo patrón.
- Texto: explica que afecta al logro «Ambos hemisferios» y a los porcentajes de hemisferio en la pantalla de logros.

---

## Cambios relevantes recientes (sesión 2026-04-14, continuación)

### Swift 6 — FlightInfo Sendable
- Eliminado `Sendable` explícito de `FlightInfo`. Con `@Model` en el mismo fichero, Swift 6 infería `@MainActor` sobre la conformancia `Codable` sintetizada, causando error. `TripAirport`, `TripAirline`, `TripSegment` mantienen `Sendable` explícito porque se decodifican siempre como arrays (stdlib nonisolated), no directamente.

### Widget pequeño — padding y márgenes
- `RaskmapWidget` ahora usa `.contentMarginsDisabled()` (elimina los ~11pt de margen del sistema que añade `containerBackground` automáticamente).
- Small view: `.padding(15)` explícito, dando control total sobre el espacio con el borde.

### Widget días — sin negrita
- Días restantes cambiados de `.bold` a `.medium` en los tres tamaños (small 22pt, medium 32pt, large 36pt).

### Widget pequeño — código de reserva con `#`
- `Text("#\(entry.bookingRef)")` arriba-derecha cuando no está vacío.

### Widget grande — conteo dinámico por modo
- `RaskmapEntry` incluye `countingMode: WCountingMode` leído de `widget_counting_mode`.
- `RaskmapLargeView` muestra el conteo y denominador según el modo activo en Ajustes (no hardcodeado a ONU/193).
- `WidgetDataWriter.syncCountingMode(_:)` escrito en `onChange(of: countingModeRaw)` de SettingsSheet.

### Legal — pantalla completa
- Las 5 secciones legales (Política de privacidad, Términos de uso, Aviso legal, RGPD, Atribuciones) ahora usan `.fullScreenCover` en lugar de `.sheet`.
- Nuevo struct `LegalInfoSheet`: sin `presentationDetents`, título grande (`.navigationBarTitleDisplayMode(.large)`), texto alineado a la izquierda (`.multilineTextAlignment(.leading)`).
- Contenido actualizado: fecha de última actualización (abril 2026), mención a compras integradas en Términos, dirección Apple en Aviso legal, instrucciones detalladas de borrado iCloud en RGPD, SF Symbols + SwiftData/CloudKit en Atribuciones.

### Widget sheets — alineación de iconos (obsoleto, ver sesión 2026-04-15)
- Se intentó `.resizable().aspectRatio(contentMode: .fit).frame(width: 24, height: 24).frame(width: 32)` — reemplazado en sesión posterior por el mismo patrón de `WidgetHomeColorSheet`.

### Confirm cards — bug pantalla vacía primera vez
- **Causa raíz**: `fullScreenCover` en iOS evalúa su clausura de contenido con el snapshot de estado anterior al render, especialmente al presentarse desde dentro de otro modal. En la primera presentación, `confirmVisits` aparecía vacío aunque se hubiera asignado en el mismo call.
- **Fix**: los tres sheets (`AddTripSheet`, `PlannedDatePickerSheet`, `EditTripSheet`) envuelven su `NavigationStack` en un `ZStack`. La tarjeta de confirmación se muestra como `if showXxx { confirmCard(...) }` directamente en el ZStack, sin `fullScreenCover`.
- `resignFirstResponder` movido al **inicio** de cada función `prepareXxxConfirmation()`, antes de cualquier asignación de estado.

### SettingsSheet — showCountdown reactivo al revocar Pro
- `showCountdown` en `SettingsSheet` cambiado de `@Binding` a `@AppStorage("showCountdown")`. `@Binding` no reacciona a escrituras externas (`onChange(of: isRaskmapPro)` en ContentView); `@AppStorage` sí.

### TransportStatsSheet — estadísticas de asientos
- Nuevos cuadrantes "Asiento favorito" y "Tipo de asiento" en `TransportStatsSheet`.
- Computed vars `topSeats` y `topSeatPositions` iteran `trip.flightDetails` y `seg.flightInfo`.
- `SeatStatsSheet` y `SeatPositionStatsSheet` con estado vacío ("Sin datos registrados") cuando no hay datos.

---

## Cambios relevantes recientes (sesión 2026-04-14)

### Widgets pantalla principal — tamaños Mediano y Grande

**`RaskmapEntry`** ampliado con dos nuevos campos:
- `visitedCount: Int` — leído de `widget_visited_un` (modo ONU)
- `upcomingFlags: String` — leído de `widget_all_flags`

**`RaskmapProvider`**: `placeholder` y `makeEntry` actualizados para poblar los nuevos campos.

**`RaskmapWidget.supportedFamilies`** → `[.systemSmall, .systemMedium, .systemLarge]`

**Vistas** — el antiguo `RaskmapWidgetView` se divide en tres vistas privadas:
- `RaskmapSmallView` — mismo layout de antes (transporte + bandera + días + fecha)
- `RaskmapMediumView` — horizontal: icono transporte (70pt) | divisor | flag+nombre+días(32pt)+fecha
- `RaskmapLargeView` — próximo viaje arriba + divisor + barra progreso países visitados + sección "Próximos destinos" con `upcomingFlags`

`RaskmapWidgetView` ahora despacha con `@Environment(\.widgetFamily)`.

Previews para los tres tamaños añadidas al final de `RaskmapWidget.swift`.

**`WidgetHomeColorSheet`** actualizada: sección "Tamaños disponibles" debajo de la paleta de colores describe los tres tamaños (Pequeño / Mediano / Grande) con su contenido.

---

## Cambios relevantes recientes (sesión 2026-04-09, parte 2)

### Rendimiento — eliminación de FPS drops al cerrar sheets

**Problema**: al cerrar sheets con swipe, SwiftUI re-renderiza el padre a 60fps. Computed vars costosas en body causaban bajones de frames.

**ContentView** — `nextProximosBanner` (O(n×m): itera `countries × trips × features`) movido a `@State private var cachedNextBanner`. Se actualiza en:
- `.task` tras cargar el GeoJSON (ambos branches: features nuevas y ya en memoria)
- `onChange(of: trips.count)`
- `onChange(of: visitedCountAll)` (también actualiza widget)
El body usa `cachedNextBanner` en lugar de llamar al computed var.

**ProfileSheet** — 4 computed vars con `JSONDecoder().decode(...)` (llamadas ~40 veces por render al iterar `AchievementKind.allCases`) convertidas a `@State`:
- `multiContinentAssignments: [String: String]`
- `multiHemisphereAssignments: [String: String]`
- `allPassportQuadrants: [String: [MapQuadrant]]`
- `earnedPassportZones: Set<String>`
- `cachedPastTrips: [Trip]` (reemplaza `private var pastTrips` que filtraba `trips` cada render)

Inicializados en `refreshProfileCaches()` llamado en `.onAppear`. Cada uno se actualiza individualmente en su `onChange` correspondiente (`multiContinentRaw`, `multiHemisphereRaw`, `mapQuadrantsData`, `earnedPassportRaw`, `trips.count`).

Funciones `isAchieved()`, `isPassportAchieved()`, `profileLastTripDate()`, el `visitedCount` inline del body y la llamada a `LogrosSheet` usan ya los `@State` cacheados.

### Banderas centradas en complicaciones watch/lockscreen
- `WatchRectangularView` (RaskmapWatchWidgets): `.frame(maxWidth: .infinity, alignment: .center)`
- `WatchFlagsView` (RaskmapWidget): `.frame(maxWidth: .infinity, alignment: .center)`

### Widget inline sin bandera
- `LockInlineView`: muestra solo nombre de destino (`entry.name`), sin emoji de bandera del país.

### ProfileSheet — sin detent pantalla completa
- `presentationDetents` reducido a `[.fraction(0.70)]` — eliminado `.large`.

### Pro activa toggle Cuenta atrás
- `onChange(of: isRaskmapPro)` con `isPro == true` → `showCountdown = true` automáticamente.

---

## Cambios relevantes recientes (sesión 2026-04-09)

### MapExportSheet — opción Mundo
- Nuevo `ExportZone.mundo` (7º caso del enum). Propiedad `isWorld: Bool` para manejo especial.
- `region`: centro (20°N, 10°E), span (160°lat, 350°lon) — muestra el mundo completo.
- Botón "🌍  Mundo" como tercera fila de selectores (ancho completo) debajo de las dos filas existentes.
- Al seleccionar Mundo: preview 16:9 horizontal (800×450 en pantalla), cuadrantGrid oculto.
- Al guardar: directo a 1600×900 (sin confirmationDialog de formato). Pinta todos los países visitados (sin filtro de zona).
- `zoneCounter` para mundo: `visitados / mode.denominator` (usa `CountingMode.denominator`).
- En `saveImage` y `renderMap`: cuando `isWorld`, `visitedFeatures = features.filter { visitedIsoCodes.contains($0.isoCode) }` (sin `AchievementKind.adjustSet`).

### Widget inline sobre el reloj (`accessoryInline`)
- Nuevo `RaskmapLockInlineWidget` (kind `"RaskmapLockInline"`, `.accessoryInline`) en `RaskmapWidget.swift` y `RaskmapWidgetBundle.swift`.
- Muestra: `"Quedan X días · 🇯🇵 Tokio"`. Sin Pro → `lock.fill + "Pro"`. Sin viaje → `"Sin próximo viaje ✈️"`.
- Reutiliza `LockNextProvider`. `LockNextEntry` ahora incluye campo `name: String` (leído de `widget_next_name`).
- `WidgetDataWriter.syncNextTrip(flag:days:name:)` — parámetro `name` añadido (default nil). Escribe `widget_next_name`. Llamado con `b?.name` en los dos sitios del ContentView.

### Complicaciones watchOS (`RaskmapWatchWidgets`)
- Directorio `RaskmapWatchWidgets/` con `RaskmapWatchWidget.swift` y `RaskmapWatchWidgetBundle.swift`.
- Tres widgets: circular (bandera próximo viaje), rectangular (bandera+días+nombre), circular gauge (países ONU).
- Para activar: añadir archivos al target watchOS Widget Extension en Xcode + App Group `group.com.jaime.raskmap`.

### Beneficios Pro actualizados
- Eliminado: iCloud
- Añadidos: Sistema de logros · Porcentaje del mundo visitado · Cuentas atrás y Live Activities · Personaliza tu mapa con colores

---

## Cambios relevantes recientes (sesión 2026-04-08, parte 4)

### Sheets pluricontinentales/hemisféricas
- `MultiContinentSheet` y `MultiHemisphereSheet`: `presentationDetents` → `.large` (pantalla entera siempre)

### Perfil — "Próximos"
- Texto "Próximos" en YearTravelView: `foregroundStyle(.primary)` — sin color, mantiene tap

### Toggles Pro al revocar / activar
- `onChange(of: isRaskmapPro)`: si `!isPro` → `showCountdown = false` y `liveActivityEnabled = false` además de `stopLiveActivity()`. Si `isPro` → `showCountdown = true` automáticamente.

### Raskmap Pro — solo pago único
- Eliminada la suscripción mensual (`raskmapProMonthlyID` eliminado)
- Solo queda `raskmapProLifetimeID = "com.raskmap.pro.lifetime"` a **4,99 €**
- `raskmapProAllIDs = [raskmapProLifetimeID]`
- `SubscriptionSheet`: un único botón de compra, sin badge, sin sección upgrade mensual→vitalicio
- `checkProStatus()` solo verifica lifetime
- Debug toggle mensual eliminado, queda solo el de vitalicio
- `proRowLabel` ya no muestra "Mensual"

### Perfil — Pasaporte Pro + reordenación menú
- Menú accesos rápidos: **Premios personales** (1º, libre) → **Pasaporte** (2º, Pro) → **Transporte** (3º)
- "Pasaporte" es función Pro: blur 4 + `lock.fill` morado + "Función Pro" cuando `!isRaskmapPro`; tap → `showSubscriptionFromProfile`
- Cuando Pro activo, "Pasaporte" abre `showMapExport` con normalidad

### Ajustes
- Sección "Selección de colores" renombrada a **"Colores del mapa:"**

---

## Cambios relevantes recientes (sesión 2026-04-08, parte 3)

### Premios personales (ex-Premios)
- "Premios" renombrado a **"Premios personales"** en el botón del perfil y en el `.navigationTitle` de `MedalleroSheet`
- **MedalleroSheet ya no requiere Pro**: eliminados `.blur`, `.allowsHitTesting` y overlay de candado del cuadrante de premios

### Live Activities — guard Pro
- `startOrUpdateLiveActivity()` ahora requiere `liveActivityEnabled && isRaskmapPro` — sin Pro no se lanza aunque el toggle esté activo

### Widgets de pantalla de bloqueo — Pro
- `LockPctEntry` y `LockNextEntry` tienen campo `isPro: Bool` leído de `widget_is_pro` en App Group
- Si `!isPro` → muestran `lock.fill` en lugar del contenido
- `WidgetDataWriter.syncPro(_ isPro: Bool)` escribe `widget_is_pro`; se llama al arrancar la app y en `onChange(of: isRaskmapPro)`

### Complicación Apple Watch — todas las banderas próximas
- `RaskmapWatchFlagsWidget` (kind `"RaskmapWatchFlags"`, `.accessoryRectangular`) — muestra emojis de todos los próximos viajes en una sola línea escalada
- `allProximosFlagsString: String` en ContentView — genera el string de emojis ordenados por fecha de viaje
- `WidgetDataWriter.syncAllFlags(_ flags: String)` escribe `widget_all_flags`; se llama junto con `syncNextTrip` en `.task` y `onChange(of: trips.count)`
- Requiere Pro; sin Pro muestra `lock.fill`; sin viajes próximos muestra "✈️ Sin próximos viajes"

### Alert de valoración App Store
- Al llegar a `visitedCountAll == 5` por primera vez se muestra un alert (una sola vez)
- Opciones: "Valorar ahora" → llama `requestReview()`, "Ahora no" → descarta, "No mostrar más" → guarda `@AppStorage("neverShowReview") = true`
- Usa `@Environment(\.requestReview)` de StoreKit

---

## Cambios relevantes recientes (sesión 2026-04-08, continuación)

### Ajustes
- Sección **Legal** añadida con 5 entradas: Política de privacidad, Términos de uso, Aviso legal, Tus derechos (RGPD), Atribuciones
- Sección **Widgets** reordenada: Live Activities → Pantalla principal → Pantalla de bloqueo → Apple Watch
- Separadores del bloque Widgets cambiados a `Rectangle().fill(Color(.separator))` (fix visual iOS 26)
- Instagram (`@jaimeviajando`) añadido en Ayuda — abre app o web
- "Países en más de un continente" y "Países en más de un hemisferio" sin bloqueo Pro

### Conteo y territorios
- Denominador `all` actualizado de 244 → **249** (total real del GeoJSON)
- `@AppStorage("multiHemisphereRaw")` — nuevo ajuste para países que cruzan el ecuador
- `AchievementKind.multiHemisphereData` — 12 países ecuatoriales con defaults precisos
- `AchievementKind.adjustedHemispheres(assignments:)` — ajusta el set sur + set ambos
- Logro `ambosHemisferios` usa los ajustes de hemisferio en todos los puntos de cálculo
- `onChange(of: multiHemisphereRaw)` dispara recheck de logros
- `MultiHemisphereSheet` — sheet idéntico visualmente a `MultiContinentSheet`

### Lista de visitados (AllCountriesSheet)
- Ya no filtra por `countingMode` — muestra **todos** los territorios visitados independientemente del modo de conteo

### Perfil
- **Total de vuelos por año** en `YearTravelView` (debajo del selector de año, encima de banderas) — cuenta tramos ida + vuelta + escalas; año actual solo finalizados; trips hijos excluidos
- Color de "Próximos" usa `colorTheme.wantToVisitColor` en lugar de `.blue` hardcodeado
- Layout del perfil: ScrollView ocupa toda la pantalla con overlay de versión eliminado
- Versión (`v.1.0`) movida a `SplashView` junto con año y "Todos los derechos reservados"

### SplashView
- Pie: año · `v.1.0` · "Todos los derechos reservados"

### Raskmap Pro — compras integradas
- Añadido segundo producto: **pago único vitalicio** `com.raskmap.pro.lifetime` (9,99 €)
- `SubscriptionSheet` rediseñada con dos botones: pago único (destacado, badge "Mejor valor") + suscripción mensual
- `raskmapProProductID` reemplazado por `raskmapProMonthlyID` + `raskmapProLifetimeID` + `raskmapProAllIDs`
- `checkProStatus()` verifica ambos IDs — cualquiera de los dos activa el Pro; lifetime tiene prioridad sobre mensual
- `purchasingID: String?` reemplaza `isPurchasing: Bool` para gestionar estado por producto independientemente
- `@AppStorage("raskmapProPlanID")` — guarda el ID del plan activo (`raskmapProMonthlyID`, `raskmapProLifetimeID` o `""`)
- Texto legal actualizado para reflejar ambas modalidades
- Cuando Pro está activo, `SubscriptionSheet` muestra el plan actual ("Vitalicio" o "Suscripción mensual") y, si es mensual, ofrece botón de upgrade a vitalicio
- Botón Pro en Ajustes: muestra `crown.fill` + "Vitalicio" / "Mensual" a la derecha cuando Pro está activo
- Debug toggle (solo `#if DEBUG`) simula plan mensual: activa `isRaskmapPro = true` y `raskmapProPlanID = raskmapProMonthlyID`

### Perfil — insignia Pro
- La barra de título del perfil usa `ToolbarItem(placement: .principal)` con `crown.fill` (morado) inmediatamente a la izquierda del nombre de usuario, solo visible cuando `isRaskmapPro == true`
- Se eliminó `.navigationTitle(username)` estándar; reemplazado por toolbar `.principal` con HStack corona + nombre

### Sheets pluricontinentales/hemisféricas
- `MultiContinentSheet` y `MultiHemisphereSheet`: `VStack` exterior → `ScrollView` para soporte en pantallas pequeñas y detents contraídos. `padding(.bottom, 20)` evita que el último elemento quede pegado al borde.

---

## ❌ NO hacer

- **No filtrar `iso != isoCode`** al crear trips hijos — ese era el bug que impedía contar visitas múltiples del mismo país en un viaje.
- **No abrir EditTripSheet directamente con un trip hijo** — usar siempre `resolvedParent(for:) ?? trip` para garantizar que se edita el padre y los cambios se propagan a todos los países del viaje.
- **No mezclar `isoA2` e `isoCode` (A3)** al buscar países — las búsquedas en `features` usan A3, los emojis y Locale usan A2.
- **No simplificar a tolerance `0.005°` o más** polígonos pequeños (Andorra quedaba con solo 17 puntos); el mínimo actual es `0.002°`.
- **No usar `Set<[String]>` directo** para inicializar `seen` en `deriveFlightCountries` — hay que hacer `.compactMap { $0 }` antes.
- **No crear `FileManager` ni `mkdir`** para el directorio de memoria — ya existe.
- **No guardar Musandam desde el GeoJSON** — no está incluido en Natural Earth; el polígono es hardcoded.
- **No cambiar la fuente a `.fontDesign(.serif)` ni a `.custom("Palatino...")`** — la app usa siempre la extensión `.palatino()` que devuelve Satoshi.
- **No dividir `ContentView.swift`** en múltiples archivos — genera problemas de compilación por el tamaño y las referencias cruzadas.
- **No usar `UUID()` como `id` en structs Identifiable** usados en `Binding<Optional>` para `.sheet(item:)` — SwiftUI re-evalúa el binding en cada render y un nuevo UUID causa bucle infinito de presentación/cierre.
- **No poner `.toolbarBackground(.visible)` en ProfileSheet** — elimina el efecto liquid glass de iOS 26 en sheets parciales. Usar `.hidden` en su lugar.
- **No resetear `hasLived` solo en `.visited`** — también hay que resetearlo en `default` (bucketList/lived/etc) al eliminar el país de la lista.
- **No usar `polyArea > 1e12` para el lineWidth** — se eliminó esa distinción; ahora siempre `highlighted ? 1.0 : 0.5` para garantizar borde uniforme en todos los países y exclaves.
- **No hardcodear polígonos aproximados** para MCO/AND/MAR/ESH/VAT — usar los anillos de alta precisión ya en `GeoJSONLoader` (OSM + geo-countries + GeoJSON exacto).
- **No añadir `vaticanRing` como polígono exterior de VAT** — ya existe como polígono propio de Vaticano en el GeoJSON. El ring solo se usa como interior hole de ITA en `loadCountries()`.
- **No usar `.sheet` para confirm cards** (visitConfirmCard, plannedConfirmCard, editVisitConfirmCard) — usar `.fullScreenCover` para evitar flickering al estar dentro de sheets parciales.
- **No usar `achievementToasts` como `@State` en ContentView** — los toasts de logros van via `AchievementToastController.shared` (UIWindow). No recuperar el overlay inline en ContentView.
- **No añadir `onChange(of: visitedIsoSet)`** para disparar toasts de logros — los toasts deben saltar al guardar el viaje (`trips.count`), no al marcar el país visitado.
- **No poner computed vars O(n×m) o JSON decode directamente en el body de una View** — SwiftUI las re-evalúa a 60fps durante animaciones (apertura/cierre de sheets). Cachear en `@State` e invalidar con `onChange` o `onAppear`.
- **No llamar `startOrUpdateLiveActivity()` en el bloque síncrono del `.task`** — `features` no está cargado aún y la bandera saldrá 🌐. Llamarlo siempre dentro del callback de `GeoJSONLoader.loadCountriesAsync` o en el branch `else` (features ya en memoria).
- **No usar `NSUbiquitousKeyValueStore`** para compartir datos con el widget — no está configurado. Usar siempre `UserDefaults(suiteName: "group.com.jaime.raskmap")`.
- **No definir `RaskmapTripAttributes` solo en un target** — necesita existir en `Raskmap/RaskmapActivityAttributes.swift` Y en `RaskmapWidget/RaskmapActivityAttributes.swift` para que ActivityKit las relacione correctamente.
- **No hardcodear `"🌍"` en `performEditSave` para trips sin segmentos** — usar `selectedTransport` del estado local del `EditTripSheet`.
- **No usar `#Predicate { $0.isoCode == country.isoCode }` directamente** — SwiftData no puede usar keypaths de otro modelo en el predicado. Capturar primero en `let iso = country.isoCode` y luego `#Predicate { $0.isoCode == iso }`.
- **No registrar dos `.sheet(item: $selectedCountry)` a la vez** — uno en `mapCore()` y otro en `mapWithSheets()` causa el warning "Currently, only presenting a single sheet is supported". El único autorizado es el de `mapWithSheets()`.
- **No usar `.fontWeight()` sobre fuentes custom Satoshi** — el entorno global tiene Satoshi-Regular size 16; `.fontWeight()` intenta actualizar el descriptor de UIFont y falla silenciosamente con warning. Usar siempre `.font(.palatino(.body, weight: .bold))` etc.

---

## Cambios relevantes recientes (sesión 2026-04-13)

### Próximos — múltiples viajes por país (`ProximoRow`)
- `ProximoRow` struct (al final de ContentView, después de `VisitEntry`):
  ```swift
  struct ProximoRow: Identifiable {
      let id: String          // "c_{iso}" sin trip, "{iso}_{createdAt}" con trip, "v_{iso}" visited
      let country: Country
      let trip: Trip?
      var isoCode: String     { country.isoCode }
      var dateFrom: Date?     { trip?.dateFrom ?? country.plannedDate }
      var dateTo: Date?       { trip?.dateTo ?? country.plannedDateTo }
      var transport: String?  { trip?.transport ?? country.transport }
      var rowTitle: String?   { trip?.title ?? country.plannedTitle }
  }
  ```
- `allProximoRows: [ProximoRow]` (computed en ContentView) reemplaza el antiguo `allProximos: [Country]`. Construye una fila por cada trip futuro de cada país `wantToVisit`; si no tiene trips futuros, una fila sin trip.
- Al guardar un próximo, **siempre se inserta un `Trip`** con el transporte elegido. `country.plannedDate` apunta al más próximo.
- `StatusListSheet` recibe `proximoRows: [ProximoRow]` y para el filtro `.wantToVisit` muestra filas agrupadas por mes/año con botón xmark por fila. Alert "¿Eliminar este próximo?" al borrar.
- Al borrar una fila de próximo: si tenía trip, se borra el trip y se recalcula `country.plannedDate`/`transport` al siguiente más próximo; si no quedan, `country.status = .none`.

### Próximos — sincronización de transporte
- `performEditSave` en `EditTripSheet`: cuando `tripSegments.isEmpty`, `trip.transport = selectedTransport` (antes era `"🌍"` hardcodeado — bug que sobreescribía el transporte registrado).
- `CountryTripsSheet.editingTrip` sheet tiene `onDismiss` que hace fetch de los trips futuros del país y sincroniza `country.transport`, `plannedDate`, `plannedDateTo`, `plannedTitle` al más próximo.
- `editingFutureTrip` sheet (desde lista Próximos) tiene `onDismiss` idéntico + actualiza `cachedNextBanner` y llama `WidgetDataWriter.syncNextTrip`.
- `bannerTappedCountry` sheet tiene `onDismiss` que recalcula `cachedNextBanner` y sincroniza widget.
- `lastEditedFutureTripIso: String?` (`@State` en ContentView) captura el `isoCode` del trip que se abre en `editingFutureTrip` via `.onAppear`, para poder usarlo en `onDismiss` (que no recibe el item).

### EditTripSheet — fecha y transporte editables
- Para viajes **sin segmentos** (`tripSegments.isEmpty`), `EditTripSheet` ahora muestra:
  - Sección **TRANSPORTE**: 6 botones (✈️🚗🚂🚌🚢🚶🏻), igual que `PlannedDatePickerSheet`
  - Sección **FECHAS**: `DatePicker` compacto para "Desde" y "Hasta (opcional)"; "Hasta" se puede añadir/quitar; si se cambia "Desde" a posterior de "Hasta", "Hasta" se borra
- `@State private var localDateFrom: Date` y `localDateTo: Date?` inicializados desde `trip.dateFrom`/`trip.dateTo` en `init`
- `calculatedDateFrom`/`calculatedDateTo` usan los valores locales cuando no hay segmentos; cuando hay segmentos, siguen usando las fechas de los segmentos (sin cambio)
- Presentación cambiada a `.presentationDetents([.large])` — pantalla completa siempre

### Widget pantalla principal (`RaskmapWidget`) — rediseño
- `RaskmapProvider` cambiado de `AppIntentTimelineProvider` a `TimelineProvider` (sin intent — configuración estática)
- `RaskmapEntry` añade: `transport: String`, `tripDateFrom: Date?`; mantiene `tripFlag`, `tripName`, `daysRemaining`, `bgColor`
- Keys nuevas en App Group: `widget_next_transport` (emoji transporte), `widget_next_date` (TimeInterval de la fecha de inicio del viaje)
- `WidgetDataWriter.syncNextTrip` extendido con `transport: String?` y `dateFrom: Date?`; todos los callsites actualizados con `b?.transport` y `b?.dateFrom`
- `nextProximosBanner` y `cachedNextBanner` extendidos a tupla `(days, flag, name, isoCode, transport, dateFrom)`
- `daysLabel(_ days: Int) -> String`: "1 día", "X días" si ≤99, "+X meses" si >99 (X = days/30, mínimo 1)
- Layout del widget: `ZStack(alignment: .topLeading)` — emoji transporte en esquina top-left; `VStack(alignment: .leading)` con `frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)` para flag+nombre azul, días grande, fecha gris — todo pegado a la esquina inferior izquierda
- Fallback: si `transport` vacío → "✈️"; si `flag` vacío → "🌍"; si `daysRemaining < 0` → vista "Sin próximo viaje"

### Pantalla de carga al arrancar
- `ContentView.body` tiene overlay que muestra mientras `isLoadingFeatures == true`: fondo `Color(.systemBackground)`, emoji 🌍 (64pt), texto "Raskmap" bold, spinner. Transición `.opacity` con `.easeOut(0.4s)`.

### Ajustes — Colores del mapa: estado pendiente + animación
- Los tres `ColorPickerRow` ahora usan estado local pendiente (`pendingVisitedColor`, `pendingWantToVisitColor`, `pendingBucketListColor`) inicializado desde `colorTheme` en `.onAppear`. Los colores **no** se aplican al mapa hasta pulsar un botón.
- Botón **"Cambiar colores"** (azul): aplica los pendientes a `colorTheme` + activa overlay de carga 5 s.
- Botón **"Restablecer colores predeterminados"** (rojo): resetea pendientes y `colorTheme` a defaults + activa overlay de carga 5 s.
- Ambos botones se deshabilitan durante `isApplyingColors`.
- Overlay de carga: fondo semitransparente negro 45% sobre toda la pantalla + recuadro negro 75% redondeado (padding 40×32) con spinner blanco y texto "Actualizando colores…"

### Corrección warning "multiple sheets"
- Eliminado el bloque `// MARK: - Sheet país` dentro de `mapCore()` (líneas ~1027-1078 en la versión anterior). Era un `.sheet(item: $selectedCountry)` duplicado que coexistía con el de `mapWithSheets()`. Solo debe existir el de `mapWithSheets()`.

### Búsqueda con tildes
- `AddSegmentSheet.filteredFeatures`: búsqueda con `.folding(options: [.caseInsensitive, .diacriticInsensitive])` — insensible a tildes y mayúsculas.

### Fix congelación scroll / borde país tras cerrar sheet
- `highlightedIsoCode = nil` se ejecuta **inmediatamente** en `onDismiss` (sin delay) para que el borde negro desaparezca al instante al cerrar el sheet.
- `recheckLocationIfNeeded()` sigue con delay de 0.1 s (sin cambios).

### Fix mapa no actualiza color al cambiar status
- `refreshTrigger: Bool` (`@State` en ContentView) se lee explícitamente en `mapCore()` con `let _ = refreshTrigger` dentro del ZStack. Sin esta lectura, el toggle no forzaba re-render de `RaskMapView`.

### Fix "Revisa los datos" vacío al abrir por primera vez
- Causa: SwiftUI batchea los cambios de estado; al asignar `confirmVisits`/`confirmAirports`/`confirmAirlines` y luego `showSaveConfirmation = true` de forma síncrona, el `fullScreenCover` se abre antes de que los arrays estén committed → pantalla vacía en la primera apertura.
- Fix aplicado a **todos** los puntos donde se activa el confirm card: `AddTripSheet.prepareConfirmation()`, `EditTripSheet.prepareEditSaveConfirmation()` (dos paths: con y sin segmentos), y `PlannedDatePickerSheet.prepareConfirmation()`. En todos: `DispatchQueue.main.async { self.showSaveConfirmation = true }` (sin `withAnimation`).
- **No usar `withAnimation { showSaveConfirmation = true }`** en estos puntos — no resuelve la race condition. Siempre `DispatchQueue.main.async`.

---

## Remodelación UI/UX completa (sesión 2026-04-15)

Rediseño visual integral de la app sin tocar ninguna funcionalidad ni lógica de datos. Lenguaje de diseño: limpio, amplio, premium.

### Dock principal (`menuOverlay`)
- Antes: dos filas separadas (card con avatar+badges, y fila con denominador+búsqueda).
- Ahora: **un único card flotante** (`height: 70`, `cornerRadius: 24`, `.regularMaterial`, `shadow(radius:20, y:6)`).
  - Izquierda: avatar 40pt + `@username` en 9pt debajo.
  - Divisor vertical fino (`Color(.separator)`, 0.5pt × 34pt).
  - Centro: badges `StatBadge`.
  - Derecha: botón circular `Color(.systemGray5)` con lupa 15pt y denominador (249/195/193) en 9pt bold debajo.
- Top/Bottom position: solo cambia si el padding es `.top` o `.bottom` (28pt); el card es idéntico.
- `badgesRow()` y `counterRow()` se mantienen como funciones auxiliares; `counterRow()` ya no se llama (obsoleta pero inofensiva).

### `StatBadge`
- Número: `Satoshi-Bold` 20pt en color semántico.
- Label: `Satoshi-Regular` 9pt, `.uppercased()`, `tracking: 0.4`, `.secondary`.
- Fondo: `color.opacity(0.10)`, `cornerRadius: 11`, `style: .continuous`.
- Sin `frame(width:)` fijo — se ajusta al contenido con padding `.horizontal(10) .vertical(9)`.

### `CountryBottomSheet`
- Header completamente rediseñado:
  - Flag emoji como hero: `font(.system(size: 64))`, centrado.
  - Nombre del país debajo, `multilineTextAlignment: .center`, `lineLimit: 2`.
  - Pill de estado (`country.status.label`) en `Satoshi-Regular` 11pt sobre `Color(.systemGray5)` capsule — solo visible si `status != .none`.
  - `Divider` limpio separando header de botones.
- Botones: `VStack(spacing: 8)` en lugar de 10, `.padding(.horizontal, 20)`.
- Botón Cerrar: texto `"Cerrar"` en `.subheadline .secondary`, `frame(maxWidth: .infinity)`, sin ✕ ni Divider encima.
- `padding(.top, 40)` eliminado → sustituido por `padding(.top, 28)` en el VStack del header.

### `ActionButton`
- Padding: `.horizontal(18) .vertical(15)` (antes `.padding()` genérico).
- Fondo: `color.opacity(0.12)` seleccionado / `Color(.systemGray6)` no seleccionado.
- Border: `color.opacity(0.35)` cuando seleccionado (antes `color` puro, más agresivo).
- `cornerRadius: 14`, `style: .continuous`.
- Checkmark: `foregroundStyle(color)` explícito, `font(.body)`.

### `ProfileAvatarView`
- Placeholder: `Color(.systemGray3)` en lugar de `.secondary`.
- Stroke: `Color(.systemGray5)` en lugar de `Color(.systemGray4)`.
- Añadida `shadow(color: .black.opacity(0.1), radius: 4, y: 2)`.

### `LegendItem`
- Swatch cuadrado → `Circle()` de 9pt con `fill(color.opacity(0.8))` y stroke 0.5pt.
- Font: `Satoshi-Regular` 10pt (antes `palatino(.caption2)`).

### `ProfileSheet` — bloque porcentaje + logros
- Antes: dos columnas separadas (`HStack`) — logros izquierda, porcentaje derecha.
- Ahora: **card unificada** `Color(.systemGray6)` con radius 16pt:
  - Izquierda: porcentaje grande `Satoshi-Bold` 48pt + `%` como superíndice 22pt + label "del mundo visitado".
  - Divisor vertical 0.5pt × 60pt.
  - Derecha: sección "LOGROS" con label en 11pt uppercase tracking, medallas en `caption`.
- Card es tappable → `showVisitedFlags` / `showSubscriptionFromProfile`.

### `ProfileSheet` — menú de accesos rápidos
- Nuevo helper `profileMenuRow(icon:iconColor:label:action:)`:
  - Icono SF Symbol sobre RoundedRect 32×32 con color de fondo sólido (naranja / azul / azulApp).
  - Padding `.horizontal(16) .vertical(13)`.
  - Chevron: `Color(.systemGray3)`.
- Fondo del grupo: `cornerRadius: 16`, `style: .continuous`.
- Padding: `.horizontal(20)` en lugar de 24.

### `SettingsSheet` — sección Pro
- Si tiene Pro vitalicio: card `Color.purple.opacity(0.07)` con icono crown en RoundedRect púrpura translúcido, texto "Vitalicio ✓". Reemplaza los dos `Color.purple` separadores.
- Si no tiene Pro: el bloque anterior se mantiene pero con `VStack(spacing: 10)` entre el proRowLabel y proCodeRow.

### Selector de modo de conteo (`SettingsSheet`)
- `HStack(spacing: 6)`, radio 11pt continuo, color `Color(red: 0x53/255, green: 0xA3/255, blue: 0xFE/255)` en lugar de `.blue` genérico.
- Font: `Satoshi-Bold/Regular` 13pt según seleccionado.
- `animation(.spring(response: 0.3, dampingFraction: 0.7))` en cada botón.

### `YearTravelView` — selector de años
- Separación: `HStack(spacing: 6)` (antes 8).
- Color seleccionado: azul de la app (`0x53A3FE`) en lugar de `.blue` genérico.
- Font: `Satoshi-Bold/Regular` 14pt.

### `AllCountriesRowView`
- Separación: `HStack(spacing: 12)` (antes 10).
- Contador de visitas: `Satoshi-Bold` 13pt con `×` en lugar de `x`.
- Iconos de acción: `Color(.systemGray3)` para añadir viaje, `red.opacity(0.5)` para papelera.

### Toast de visita
- Antes: fondo `Color.black.opacity(0.75)`, checkmark blanco.
- Ahora: `.regularMaterial` con sombra, checkmark en `colorTheme.visitedColor`, texto `.primary`.
- Spring: `response: 0.4, dampingFraction: 0.75`.

### Banner countdown
- Antes: `Text(bannerText)` en una sola línea dentro del pill.
- Ahora: `HStack` con bandera, días bold, `· nombre` en secondary — mismo pill.
- Añadida `shadow(color: .black.opacity(0.08), radius: 10, y: 4)`.

### Toast de ubicación
- Icono: `location.circle.fill` tamaño 40pt (antes `location.fill` title2).
- Título: "Ubicación detectada" en `.headline .bold`.
- Botón: "Entendido" en lugar de "Cerrar", `padding(.vertical, 14)`, radius 14pt.
- Card: `cornerRadius: 22`, `padding(28)`, `padding(.horizontal, 28)`.
- Spring: `response: 0.4, dampingFraction: 0.8`.

### Loading overlay
- Globo: 80pt (antes 64pt).
- Subtítulo: "Cargando el mundo…" en `.palatino(.footnote)` `.tertiary`.
- Spinner: `.tint(Color(0x53A3FE))`.
- Transition duration: 0.5s (antes 0.4s).

### Onboarding
- Estructura: globo 72pt + título `Satoshi-Bold` 26pt + subtítulo.
- TextField: padding `.horizontal(18) .vertical(14)`, `cornerRadius: 14`, sin `.roundedBorder`.
- Botón: "Empezar a explorar", desactivado si campo vacío (`.disabled`), color gris cuando vacío.

### `SplashView`
- Fondo: `LinearGradient` de `#3A91F0` a `#53A3FE` (antes color plano).
- Animación: `.spring(response: 0.6, dampingFraction: 0.75)` — globo cae desde offset 12pt + fade in junto con el texto.
- Footer: `"v.1.0 · 2026"` en una sola línea + copyright debajo. Sin año "–año+1".

---

# 🔍 AUDITORÍA PROFUNDA (mayo 2026) — TO-DO MAÑANA

Snapshot del estado de la app tras 4 auditorías paralelas (bugs / performance /
UX / tests). Pendiente de abordar — orden recomendado: Sprint 1 → 2 → 3.

## 🐛 BUGS REALES

### 🔴 Bloqueantes

1. **Trip primary == ISO de segmento → días duplicados**
   - File: `Raskmap/Trip.swift:364`
   - Si trip "España" tiene segmento `bus a España` (tour interno), España
     cuenta los días 2 veces. `destPick` fallback termina staking primary +
     destino segmento al mismo prio 100.
   - Fix: cuando `destPick == t.isoCode`, no stake (el ambient ya lo cubre).

2. **Children huérfanos doble-cuentan antes del cleanup**
   - File: `Raskmap/Trip.swift:306-316`, `ContentView.swift:1152`
   - Entre el borrado del primary y el `cleanupOrphanChildTrips()` deferido
     0.3s, `daysPerCountry` ve children + primary fantasma → conteos erróneos
     durante esa ventana.
   - Fix: filtrar children huérfanos en `daysPerCountry` antes del cleanup,
     o invertir el orden (cleanup primero).

3. **Segmento sin `isoCodes` permitido al guardar**
   - File: `Raskmap/AddSegmentSheet.swift:591`
   - User selecciona ✈️, abre RouteWizardSheet, no añade aeropuertos →
     segmento con `isoCodes=[]` se guarda. Causa undefined behavior aguas
     abajo.
   - Fix: `guard !finalIsoCodes.isEmpty else { return }` antes de save.

### 🟡 Molestos

4. **Layovers de vuelta perdidos si `airports` está vacío**
   - File: `Raskmap/AddSegmentSheet.swift:585`
   - `realLayoverISOs` solo lee `outboundLayoverChoices`. Si user borra los
     aeropuertos de ida pero marca escala visitada en vuelta → se pierde
     silenciosamente.
   - Fix: incluir `returnLayoverChoices` en `realLayoverISOs`.

5. **`dateFrom > dateTo` posible vía quickDateChips**
   - File: `Raskmap/AddSegmentSheet.swift:689`
   - El branch para "HASTA" desactiva la corrección. Resultado: rango
     invertido, `daysPerCountry` lo skip silenciosamente (guard `t >= f`).
   - Fix: en el branch HASTA, si `chip.value < dateFrom` → ajustar dateFrom
     o avisar al user.

6. **Race condition en `handleTripsCountChange` deferido + `cachedNextBanner`**
   - File: `Raskmap/ContentView.swift:1125-1135`
   - Dos guardados seguidos a 200ms con tasks deferidos 0.3s pueden
     sobrescribir el cache con datos stale.
   - Fix: cancelar la task previa cuando llega una nueva (token UUID).

7. **`WidgetDataWriter` falla silenciosamente sin AppGroup**
   - File: `Raskmap/WidgetDataWriter.swift:15-38`
   - `guard let store else { return }` pero `WidgetCenter.reloadAllTimelines()`
     se ejecuta igual → widget queda con datos stale, sin log.
   - Fix: log + skip reloadAllTimelines si store es nil.

### 🔘 Cosmético

8. **`visitCount` divergente tras delete masivo parcial**
   - File: `Raskmap/ContentView.swift:1318-1332`
   - Cleanup de status corre antes que cleanup de children huérfanos →
     `visitCount > 0` con `status = .none` brevemente.

---

## ⚡ PERFORMANCE

### 🔴 Alta

9. **`multiContAchievedNow` decodifica 3 JSON × 98 cases en cada render**
   - File: `Raskmap/ContentView.swift:139,143,196`
   - Cualquier scroll/tap que re-renderice ContentView dispara ~294 ops de
     JSON parsing.
   - Fix: cache decoded como `@State`, refresh via `.onChange` en AppStorage
     raws (`multiContinentRaw`, `multiHemisphereRaw`, `mapQuadrantsData`).

10. **`@Query private var countries/trips` sin predicado**
    - File: `Raskmap/ContentView.swift:26-27`
    - SwiftData carga TODAS las filas en memoria al lanzar la app.
    - Fix: predicados + índices SwiftData en `Trip.isoCode`, `Trip.dateFrom`,
      `Country.status`. Considerar lazy-load de trips históricos.

### 🟡 Media

11. **`tripAirports`/`tripAirlines`/`tripSegments` decodifican JSON en cada acceso**
    - File: `Raskmap/Trip.swift:76-144`
    - Acceder `trip.tripSegments` 3 veces seguidas decodifica 3 veces.
    - Fix: `@Transient` cache interno que se llena en get + se invalida en
      set; o usar un decoder estático compartido.

12. **`_routeContainsIsoA3` con búsqueda lineal por layover**
    - File: `Raskmap/Trip.swift:253-258`
    - Vuelo con 4 escalas × 8 aeropuertos = 32 iteraciones.
    - Fix: pre-compute `Set<String>` de ISOs por ruta una vez por segment.

13. **`visitedFlagEmojis`/`firstLayoverTrip` ordenan en cada render**
    - File: `Raskmap/Sheets/ProfileSheet.swift:106,130-136`
    - `localizedCompare` O(n log n) por acceso.
    - Fix: `@State` cacheado, invalidado por `.onChange(of: visitedIsoCodes)`.

14. **`GeoJSONLoader.loadCountries()` sin memoización**
    - File: `Raskmap/GeoJSONLoader.swift`
    - Se llama desde Trip.swift static init y posiblemente otros sitios.
      Si concurrente, puede parsear el GeoJSON varias veces.
    - Fix: `lazy static let` con cache, o `dispatch_once`.

15. **`JSONDecoder()` instanciado por línea (Trip.swift:79,109,114,159,238,242)**
    - Crear `nonisolated static let decoder = JSONDecoder()` compartido.

---

## 🎨 UX / UI

### 🔴 Alta

16. **Accesibilidad — `accessibilityLabel` ausente en botones icon-only**
    - 28 ocurrencias en 51 archivos (muy bajo).
    - Botones X de cerrar sheet, controles de mapa, etc. no son VoiceOver-friendly.
    - Fix: pass de añadir labels a todos los botones icon-only.

17. **Dynamic Type no soportado en fonts custom**
    - File: `Raskmap/DesignTokens.swift:91-118`
    - `Font.custom("Satoshi-Bold", size: 22)` sin `relativeTo:`.
    - Fix: usar `Font.custom(_:size:relativeTo:)` en Typography enum.

18. **i18n — `Locale(identifier: "es_ES")` hardcoded en 10+ sitios**
    - Fechas en español aunque iOS esté en inglés.
    - Files: ContentView, AddSegmentSheet, YearWrappedSheet, IPadRootView,
      ListSheets, SmallWidgets.
    - Fix: `Locale.current` + Localizable.strings (ES + EN) + .stringsdict
      para plurales.

### 🟡 Media

19. **DesignTokens existen pero no se usan uniformemente**
    - 11 valores distintos de `cornerRadius` hardcoded, 15+ tamaños de font.
    - Fix: refactor progresivo de Sheets/ usando `Radius.cell/card`,
      `Typography.body`, `Spacing.l/xl`.

20. **`.presentationDragIndicator` inconsistente**
    - Solo `AddTripSheet` oculta, el resto visible. Criterio no claro.

21. **Empty states incompletos**
    - `IPadRootView` tiene, pero ListSheets/StatsBreakdownSheets podrían no.

22. **Confirmación destructive faltante en swipe-to-delete**
    - File: `Raskmap/Sheets/ListSheets.swift` (swipeActions delete)
    - El delete de Settings sí confirma, los swipeActions no.

23. **`Color.black`/`Color.white` hardcoded en 64 sitios** sin adaptación
    a dark mode (RaskMapViewV2, SplashView, etc.).
    - Fix: helpers tipo `Color.surfaceOverlay` con
      `Color(UIColor { traitCollection in ... })`.

24. **Tap targets < 44pt HIG**
    - Solo 3 hits de `TapTarget.min`. Muchos botones podrían estar por debajo.

25. **Spacing hardcodeado** — `Spacing` enum existe pero no se usa
    uniformemente (`.padding(20)` vs `Spacing.xl = 20`).

---

## 🛡️ TESTS / ROBUSTEZ

### 🔴 Alta

26. **`sorted.last!` en AddSegmentSheet:116** — crash risk si la lista
    queda vacía tras filter. Fix: `guard let last = sorted.last else { return }`.

27. **Logros sin tests** — `multiContAchievedNow`, `adjustSet`,
    `adjustedHemispheres`, `filterCandidatesForZone`, `nextProximosBanner`
    no tienen cobertura. Solo `daysPerCountry` tiene 11 tests.
    - Fix: añadir 10-15 tests para escenarios de achievements críticos.

28. **122 ocurrencias de `try?` sin logging**
    - Files: Trip.swift, GeoJSONLoader, WidgetDataWriter.
    - Decodings/migrations fallan silenciosamente.
    - Fix: audit + añadir logging a decodifications críticas. Considerar
      `#if DEBUG print(...)` para no contaminar release.

### 🟡 Media

29. **No hay tests de migraciones de Trip/TripSegment**
    - FlightInfo legacy → outboundLegs[], TripSegment con/sin airports.
    - Fix: tests JSON corruption + legacy format round-trips.

30. **Live Activities huérfanas tras crash**
    - Si la app crashea con una Activity activa, nadie la cierra.
    - Fix: al lanzar la app, listar Activities activas y cerrar las stale.

31. **No recovery path para CloudKit failure**
    - Sin retry, sin UI de "Reintentar sync".
    - Fix: botón "Reintentar sincronización" en Settings (visible si stale).

32. **`Trip.isoCode = ""` permitido** sin validación
    - Fix: `precondition(!isoCode.isEmpty)` en init.

---

## 🌟 NICE-TO-HAVES

### Alto valor, esfuerzo S/M

33. **Búsqueda en LogrosSheet** — `.searchable` para filtrar entre 98 logros.

34. **Notas largas por viaje** — añadir `trip.notes: String?`. Simple y valioso.

35. **Compartir viaje individual** — share image estilo Wrapped pero por trip
    (no solo el resumen anual).

36. **Mapa con filtros** — visitados/próximos/buckets/transporte. El mapa
    muestra todo siempre.

37. **Reset/retry sync del widget** desde Settings — botón "Reintentar
    sincronización" cuando el widget muestra stale data.

### Alto valor, esfuerzo L

38. **Etiquetas/tags por viaje** — "luna de miel", "negocios", etc.
    Requiere modelo nuevo.

39. **Fotos por viaje** — `PhotosPicker` + thumbnail storage. Habilita
    mucho UX downstream.

40. **iPad optimization real** — `IPadRootView` existe pero es scaffold;
    split-view + landscape merece pulido.

41. **Companions (con quién viajaste)** — modelo nuevo + relacionar con
    achievements ("viajé con 5 personas distintas").

42. **Importar datos desde JSON exportado** — el export ya existe, falta
    el import.

### Medio valor

43. **Currency / presupuesto por viaje** — opcional, monetario.

44. **Idioma del país visitado** + países hispanohablantes etc. expuestos
    en stats (achievement ya existe, falta UI).

45. **Apple Watch app más rica** — `RaskmapWatch` existe pero placeholder.

46. **Shortcuts integration** — "Hey Siri, add trip" / widgets de configuración.

---

## 📋 ROADMAP SUGERIDO

### Sprint 1 — Correctitud (1-2 días)
- Bugs #1, #2, #3, #6 (bloqueantes)
- Bug #26 (force unwrap crash risk)
- Validación `Trip.isoCode != ""` y `dateFrom <= dateTo` en init
- Tests para 5 escenarios de achievements críticos (#27)

### Sprint 2 — Performance percibida (2-3 días)
- Cache `multiContAchievedNow` con invalidación por @AppStorage onChange (#9)
- `@Transient` cache de JSON-encoded properties en Trip (#11)
- Pre-compute `Set<String>` ISOs por ruta en `_routeContainsIsoA3` (#12)
- Cache `visitedFlagEmojis` con @State (#13)
- `lazy static let` en GeoJSONLoader (#14)

### Sprint 3 — UX polish (3-5 días)
- Accesibilidad: `accessibilityLabel` + Dynamic Type en Typography (#16, #17)
- Confirm dialogs en swipe-to-delete (#22)
- Migrar `Color.black/.white` hardcoded a tokens adaptativos (#23)
- DesignTokens: ronda de migración progresiva (#19)
- Tap targets ≥ 44pt (#24)

### Sprint 4 — Features ganadores (variable)
- Notas por viaje (#34) — fácil, muy útil
- Búsqueda en logros (#33) — barato y notable
- Share por viaje individual (#35) — pieza media
- Filtros en mapa (#36) — pieza media

### Sprint 5 — i18n (1-2 días)
- Reemplazar `Locale(identifier: "es_ES")` por `Locale.current` (#18)
- Strings catalogs ya existen — activar pluralización (.stringsdict)

---

## ⚠️ Salud general

- ✅ **Sólido**: arquitectura SwiftData + CloudKit, DesignTokens existen,
  AppStorage bien usado, `daysPerCountry` bien testeada (11 tests pasan).
- ⚠️ **Riesgos**: ContentView.swift (~2877 líneas) sigue siendo monolito,
  achievements sin cobertura de tests, errores silenciosos en JSON decoding.
- 🟢 **No urgente**: la app está lista para TestFlight tras fixes Sprint 1.
  Sprints 2-5 son refinamiento progresivo.

---

**Última auditoría**: 2026-05-15. Si vuelves a auditar y los hallazgos
cambian materialmente, actualiza este bloque o crea uno nuevo con la
fecha — no edites el histórico para preservar el track de progreso.
