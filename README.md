# 🌍 Raskmap

App de iOS para registrar tus viajes, llevar el conteo de países visitados y planear los próximos.
Mapa interactivo, segmentos de vuelo con escalas, widgets de Home Screen, Live Activities y
estadísticas de transporte (km volados, aerolíneas, asientos, etc.).

---

## ✨ Features principales

### Mapa
- Polígonos de los ~250 países / territorios coloreados según estado:
  visitado, vivido, próximo viaje, bucket-list.
- Detección de ubicación: marca automáticamente como visitado el país donde estás.
- **Modo vuelo**: oculta los rellenos de país y dibuja líneas geodésicas entre
  aeropuertos. Filtro pasado / próximo.
- Pre-warm de renderers + caching de paths → sin flicker al hacer pan.

### Viajes (`Trip`) y segmentos (`TripSegment`)
- Cada viaje pertenece a un país base, con título opcional, fechas y transporte.
- Multi-segmento: un viaje puede tener varios tramos (MAD→DXB en avión, DXB→NRT en avión, etc.).
- Para ✈️: aeropuertos por tramo (ida + vuelta), aerolíneas, escalas, asiento, clase de cabina.
- Algoritmo `daysPerCountry` que reparte días entre escalas y destinos según prioridades.

### Estadísticas
- Heatmap anual + comparativa vs año anterior.
- Conteo de tramos por transporte (✈️ cuenta legs por aeropuertos, no viajes).
- Km volados (haversine entre coords de aeropuertos).
- Aeropuertos / aerolíneas / asientos top.
- "Lugares por descubrir": una sugerencia por región (Europa, Asia, África, etc.)
  priorizada por proximidad geográfica a tu cluster de visitados.

### Year Wrapped (style Spotify Wrapped)
- Reel animado con países, días viajados, vuelos, aeropuertos top, etc.
- Compartible como imagen / texto con hashtags.

### Widgets & Live Activities
- Widget Small / Medium / Large + accessoryCircular (Lock Screen).
- Live Activity con countdown real-time al próximo viaje (`Text(timerInterval:)`).
- Sincronización iCloud (CloudKit) entre dispositivos.

### Compliance
- GDPR Art. 17 (right to erasure): "Borrar todos mis datos" con doble confirmación.
- GDPR Art. 20 (portability): exportar todos los datos en JSON o CSV.
- Sin tracking, sin analytics, sin SDKs externos.
- StoreKit "Restore Purchases" obligatorio para Non-Consumable IAP.

---

## 🛠 Stack técnico

| Capa                    | Tecnología                                         |
| ----------------------- | -------------------------------------------------- |
| UI                      | SwiftUI (iOS 17+, Swift 6 strict concurrency)      |
| Persistencia            | SwiftData + CloudKit (sync iCloud privado)         |
| Mapa                    | MapKit (MKMapView + MKPolygonRenderer, vector)     |
| Widgets                 | WidgetKit + ActivityKit (Live Activities)          |
| Notificaciones          | UserNotifications (recordatorios de viaje)         |
| Compras                 | StoreKit 2 (suscripción Raskmap Pro)               |
| Tests                   | Swift Testing (`@Test`) — unit + render smoke      |
| Aislamiento por default | `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`        |

---

## 📁 Estructura

```
Raskmap/
├── RaskmapApp.swift              ← entry point, schema SwiftData
├── ContentView.swift             ← root view (~13k líneas — pendiente modularizar)
├── Country.swift                 ← @Model Country + CountryStatus
├── Trip.swift                    ← @Model Trip + TripSegment + daysPerCountry
├── FlightInfo.swift              ← struct FlightInfo (Codable nonisolated)
├── AddSegmentSheet.swift         ← wizard 3 pasos para añadir tramo
├── GeoJSONLoader.swift           ← parser de countries.geojson
├── RaskMapView.swift             ← UIViewRepresentable wrapping MKMapView
├── FlightMap.swift               ← overlays de rutas de vuelo
├── YearWrappedSheet.swift        ← reel de wrapped anual
├── TwemojiFlag.swift             ← banderas con fallback Twemoji
├── ColorThemeManager.swift       ← tema de colores configurable
├── LocationManager.swift         ← CoreLocation
├── WidgetDataWriter.swift        ← shared defaults para widgets
├── countries.geojson             ← polígonos de ~250 países

RaskmapWidget/
├── RaskmapWidget.swift           ← Small / Medium / Large views
├── RaskmapLiveActivity.swift     ← Lock screen + Dynamic Island
├── RaskmapActivityAttributes.swift ← shared con la app

RaskmapTests/
├── DaysPerCountryTests.swift     ← 9 casos del algoritmo de días
├── RenderSmokeTests.swift        ← 7 tests "no crash" de vistas críticas

docs/                              ← textos legales (GitHub Pages)
├── privacy.md, terms.md, gdpr.md, imprint.md, credits.md
```

---

## 🌿 Estado del desarrollo

Rama activa: **`remodelacion_integral_v2`** — iteración 2026-05 con commits
incrementales sobre App Store readiness, performance, UX y nice-to-have.

Historial detallado en [`Raskmap/CONTEXT.md`](Raskmap/CONTEXT.md) (changelog
chronological con cada commit, problema resuelto y rationale).

---

## 🚀 Setup (desarrollo)

```bash
git clone https://github.com/jamesfdeza/Raskmap.git
cd Raskmap
open Raskmap.xcodeproj
```

Requiere Xcode 16+ y un Apple Developer Account para signing.
Targets: **Raskmap** (app), **RaskmapWidget** (extensión).

CloudKit container: `iCloud.RealDev.Raskmap` (cambiar al fork-ear).

Para correr tests:
```bash
xcodebuild test -scheme Raskmap -destination 'platform=iOS Simulator,name=iPhone 15'
```

---

## 📜 Legal

- App: 100% offline (datos en SwiftData + tu iCloud).
- Sin recopilación de datos personales.
- Política completa: [`docs/privacy.md`](docs/privacy.md) (también dentro de
  la app: Ajustes → Política de Privacidad).
- Twemoji bajo CC-BY 4.0 (jdecked/twemoji) — atribución en Ajustes → Créditos.

---

## ✍️ Autor

Jaime Fernández Arenas · raskmap_soporte@icloud.com
