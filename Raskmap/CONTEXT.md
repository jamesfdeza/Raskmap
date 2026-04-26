# CONTEXT.md — Raskmap

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
