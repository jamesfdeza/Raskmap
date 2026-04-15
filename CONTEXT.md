# CONTEXT.md — Raskmap

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
- [ ] ID hardcoded en `ContentView.swift` como `raskmapProLifetimeID` (suscripción mensual eliminada)

### Paso 4 — Hostear Política de Privacidad en URL pública (obligatorio App Store Connect)
- [ ] Opción fácil: Notion con "Share to web"
- [ ] Opción profesional: GitHub Pages (`tuusuario.github.io/raskmap-legal`)
- [ ] El texto ya está escrito en Ajustes → Legal → Política de privacidad
- [ ] Pegar la URL en Xcode → Info y en App Store Connect (campo "Privacy Policy URL")

### Paso 5 — Configurar AdMob (monetización con banner)
- [ ] Crear cuenta en [admob.google.com](https://admob.google.com)
- [ ] Registrar la app → obtener **App ID** (`ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX`)
- [ ] Crear unidad de anuncio tipo **Banner** → obtener **Ad Unit ID** (`ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX`)
- [ ] Añadir SDK en Xcode: `File → Add Package Dependencies` → `https://github.com/googleads/swift-package-manager-google-mobile-ads` → target `Raskmap`
- [ ] Añadir en `Info.plist`: `GADApplicationIdentifier = <App ID>`
- [ ] En `BannerAdView.swift` línea 16: sustituir el test ID por el **Ad Unit ID** real
- [ ] Actualizar Política de Privacidad para mencionar el uso de publicidad y datos de AdMob (obligatorio tanto para Google como para Apple)

### Paso 5 — App Store Connect: ficha de la app
- [ ] Rellenar cuestionario de privacidad (datos en iCloud del usuario, sin terceros, sin analíticas)
- [ ] Nombre, subtítulo, descripción localizada
- [ ] Capturas de pantalla (6.7", 6.5", iPad si aplica)
- [ ] Icono definitivo 1024×1024 sin transparencia
- [ ] Categoría: Travel o Lifestyle
- [ ] Precio: Gratis (el Pro es In-App Purchase)

### Paso 6 — Probar con TestFlight antes del lanzamiento público
- [ ] Archivar en Xcode → Product → Archive → Distribute App → TestFlight
- [ ] Revisar que `v.1.0` en SplashView coincide con el Build/Version de Xcode

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
