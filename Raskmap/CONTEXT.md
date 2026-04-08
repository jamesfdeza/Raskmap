# CONTEXT.md — Raskmap

## Estructura de carpetas
```
Raskmap/
├── Raskmap/              ← código fuente principal
│   └── Assets.xcassets/
├── RaskmapWidget/        ← widget extension
│   └── Assets.xcassets/
├── RaskmapTests/
├── RaskmapUITests/
└── Raskmap.xcodeproj/
```

Archivos Swift en `Raskmap/`:
`AddSegmentSheet`, `ColorThemeManager`, `ContentView`, `Country`, `CountingMode`,
`GeoJSONLoader`, `LocationManager`, `RaskMapView`, `RaskmapApp`, `RaskmapActivityAttributes`, `SplashView`, `Trip`, `WidgetDataWriter`

Archivos Swift en `RaskmapWidget/`:
`RaskmapActivityAttributes`, `RaskmapLiveActivity`, `RaskmapWidget`, `RaskmapWidgetBundle`, `RaskmapWidgetControl`

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
```

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
```

### `CountryStatus` (enum)
`none` | `visited` (rojo) | `wantToVisit` (azul) | `lived` (verde) | `bucketList` (naranja)

### `CountingMode` (enum)
`un` (193) | `unPlus` (195) | `all` (244 territorios)

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
- La extensión lee `UserDefaults.standard.string(forKey: "appFontFamily")` en tiempo de render → el cambio de fuente es live (sin restart). Default: `"satoshi"`.
- `ContentView` tiene `@AppStorage("appFontFamily") private var _appFontFamily: String` para forzar re-render al cambiar.

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
@AppStorage("appFontFamily")      // "satoshi" (default) | "palatino"
@AppStorage("widgetBgColorHex")   // String hex — color de fondo del widget (default "#EE6E7D")
@AppStorage("liveActivityEnabled") // Bool — Live Activity del próximo viaje activa
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
- `ProfileSheet` usa `.presentationDetents([.fraction(0.70), .large])` + `.presentationDragIndicator(.visible)`. Dos detents → se puede deslizar a pantalla completa. Sin ScrollView interno. `.toolbarBackground(.hidden)` para preservar liquid glass de iOS 26.
- Bug bucle infinito en `TransportStatsSheet`: `TransportFilter.id` debe ser determinístico (`emoji + label`), nunca `UUID()`.
- `CountryTripsSheet` tiene botón de ordenación (↑/↓ por `dateFrom`) y toggle "He vivido aquí" (`country.hasLived`).

**Rutas de vuelo**
- `TripSegment.airports` = ruta ida (ordenada)
- `TripSegment.returnAirports` = ruta vuelta (ordenada, nil = solo ida)
- Destino = `airports.last`, escalas = intermedios de cada ruta por separado
- Estadísticas globales combinan ida + vuelta en `Trip.airportsRaw`
- En `AddSegmentSheet` paso 3, el resumen de ruta (códigos IATA + aerolínea) está alineado al **centro** (`VStack(alignment: .center)` + `.frame(maxWidth: .infinity, alignment: .center)`)
- En `AddSegmentSheet`, el paso de escala muestra primero "✈️ Vuelo directo" (azul, acción primaria) y luego "🔄 Con escala(s)" (gris). Aplica tanto al vuelo de ida como al de vuelta.

**Confirm cards (visitConfirmCard / plannedConfirmCard / editVisitConfirmCard)**
- Presentadas como `.fullScreenCover` (no `.sheet`) para evitar flickering al estar dentro de sheets parciales.
- Tienen `.presentationBackground(.clear)` + `.interactiveDismissDisabled(true)`.
- Estructura de secciones: PAÍSES → (Divider) → AEROPUERTOS → AEROLÍNEAS. La última aerolínea NO lleva divider inferior (verificado con `al.id != confirmAirlines.last?.id`).
- `EditTripSheet` tiene fallback a `trip.tripAirports`/`trip.tripAirlines` para viajes pre-segmentos.

**Raskmap Pro — features bloqueadas**
- `@AppStorage("isRaskmapPro") var isRaskmapPro: Bool = false` presente en cada struct que lo necesita.
- Patrón de bloqueo: `View.blur(radius: isRaskmapPro ? 0 : N).allowsHitTesting(isRaskmapPro)` + `Image(systemName: "lock.fill")` en ZStack overlay.
- Features Pro activas:
  - Toggle "Mostrar contador" en Ajustes (solo el toggle blur, el label queda legible)
  - Banner countdown "Quedan X días para" en pantalla principal (blur + lock capsule)
  - Toasts de logros: si no es Pro, no se muestran (sin toasts en absoluto)
  - Toggle "Live Activities" en Ajustes → Widgets (blur + candado morado)
- Si se revoca el Pro y `liveActivityEnabled` estaba activo, `onChange(of: isRaskmapPro)` termina todas las Live Activities activas

**Toasts de logros (achievements)**
- Implementados via `AchievementToastController.shared.show(...)` → crea un `UIWindow` con `windowLevel = .alert + 1` para aparecer sobre cualquier modal/sheet.
- Posición: arriba-derecha si menú está abajo (default), abajo-derecha si menú está arriba.
- Se disparan en `ContentView.checkAndShowAchievementToasts()`, llamada en 3 `onChange`: `multiContinentRaw`, `trips.count`, `mapQuadrantsData`. También en `autoMarkIfNeeded` (auto-marca por ubicación, sin trip).
- **NO** hay `onChange(of: visitedIsoSet)` — los toasts se disparan al guardar el viaje (cuando `trips.count` cambia), no al marcar el país visitado. Esto evita que salten al tocar "Añadir viaje pasado".
- `prevAchieved: Set<AchievementKind>?` (state en ContentView) guarda el estado anterior para detectar nuevos logros desbloqueados.
- Si se consiguen varios a la vez se apilan verticalmente (ForEach en `AchievementToastView`).
- Duración: 4 segundos, luego la UIWindow se oculta y se libera.

**Widget**
- `WidgetDataWriter` sincroniza conteos a `NSUbiquitousKeyValueStore` (iCloud KV)
- Keys: `"widget_visited_un"`, `"widget_visited_unPlus"`, `"widget_visited_all"`

---

## TODOs / Bugs conocidos
- Los viajes antiguos (pre-`returnAirports`) solo tienen `airports` (ruta ida). La UI hace fallback legacy correctamente.
- Los trips hijos (`isSegmentChild = true`) se resuelven al padre en `CountryTripsSheet.tripRow` via `resolvedParent(for:)` — la UI siempre muestra y edita el padre. Editar desde cualquier país del grupo modifica el padre y regenera los hijos en `performEditSave`.
- `PersonalAwardModel` existe en SwiftData pero su gestión UI está en `ContentView.swift`.

---

## ❌ NO hacer

- **No filtrar `iso != isoCode`** al crear trips hijos — ese era el bug que impedía contar visitas múltiples del mismo país en un viaje.
- **No abrir EditTripSheet directamente con un trip hijo** — usar siempre `resolvedParent(for:) ?? trip` para garantizar que se edita el padre y los cambios se propagan a todos los países del viaje.
- **No mezclar `isoA2` e `isoCode` (A3)** al buscar países — las búsquedas en `features` usan A3, los emojis y Locale usan A2.
- **No simplificar a tolerance `0.005°` o más** polígonos pequeños (Andorra quedaba con solo 17 puntos); el mínimo actual es `0.002°`.
- **No usar `Set<[String]>` directo** para inicializar `seen` en `deriveFlightCountries` — hay que hacer `.compactMap { $0 }` antes.
- **No crear `FileManager` ni `mkdir`** para el directorio de memoria — ya existe.
- **No guardar Musandam desde el GeoJSON** — no está incluido en Natural Earth; el polígono es hardcoded.
- **No cambiar la fuente a `.fontDesign(.serif)`** — la app usa siempre la extensión `.palatino()`.
- **No dividir `ContentView.swift`** en múltiples archivos — genera problemas de compilación por el tamaño y las referencias cruzadas.
- **No usar `UUID()` como `id` en structs Identifiable** usados en `Binding<Optional>` para `.sheet(item:)` — SwiftUI re-evalúa el binding en cada render y un nuevo UUID causa bucle infinito de presentación/cierre.
- **No poner `.toolbarBackground(.visible)` en ProfileSheet** — elimina el efecto liquid glass de iOS 26 en sheets parciales. Usar `.hidden` en su lugar.
- **No resetear `hasLived` solo en `.visited`** — también hay que resetearlo en `default` (bucketList/lived/etc) al eliminar el país de la lista.
- **No usar `polyArea > 1e12` para el lineWidth** — se eliminó esa distinción; ahora siempre `highlighted ? 1.0 : 0.5` para garantizar borde uniforme en todos los países y exclaves.
- **No hardcodear polígonos aproximados** para MCO/AND/MAR/ESH/VAT — usar los anillos de alta precisión ya en `GeoJSONLoader` (OSM + geo-countries + GeoJSON exacto).
- **No añadir `vaticanRing` como polígono exterior de VAT** — ya existe como polígono propio de Vaticano en el GeoJSON. El ring solo se usa como interior hole de ITA en `loadCountries()`.
- **No usar `.sheet` para confirm cards** (visitConfirmCard, plannedConfirmCard, editVisitConfirmCard) — usar `.fullScreenCover` para evitar flickering al estar dentro de sheets parciales.
- **No usar `achievementToasts` como `@State` en ContentView** — los toasts de logros van via `AchievementToastController.shared` (UIWindow). No recuperar el overlay inline en ContentView.
- **No olvidar disparar `checkAndShowAchievementToasts()` en los 3 onChange** — `multiContinentRaw`, `visitedIsoSet`, `trips.count`.
