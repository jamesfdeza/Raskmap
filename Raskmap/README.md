# 🌍 Raskmap — Guía de Configuración

## Archivos del proyecto

```
Raskmap/
├── RaskmapApp.swift       ← Punto de entrada (reemplaza el tuyo)
├── Country.swift          ← Modelo de datos (reemplaza Item.swift)
├── GeoJSONLoader.swift    ← Parser del mapa mundial
├── RaskMapView.swift      ← Vista del mapa con overlays
├── ContentView.swift      ← Vista principal con UI
└── countries.geojson      ← ⭐ DEBES AÑADIR ESTE ARCHIVO (ver paso 2)
```

---

## Paso 1 — Añadir los archivos Swift al proyecto

1. En Xcode, haz clic derecho sobre tu carpeta `Raskmap` en el panel izquierdo
2. Selecciona **"Add Files to Raskmap..."**
3. Añade los 5 archivos `.swift`
4. **Importante**: Borra `Item.swift` — ya no lo necesitas (lo reemplaza `Country.swift`)

---

## Paso 2 — Descargar el GeoJSON de países ⭐

Este archivo contiene los polígonos de todos los países del mundo (~4 MB).

### Descarga directa:
👉 https://datahub.io/core/geo-countries/r/countries.geojson

O desde Natural Earth (más preciso):
👉 https://github.com/nvkelso/natural-earth-vector/blob/master/geojson/ne_110m_admin_0_countries.geojson

### Añadirlo a Xcode:
1. Descarga el archivo y renómbralo exactamente: **`countries.geojson`**
2. En Xcode, arrastra el archivo a la carpeta de tu proyecto
3. En el diálogo que aparece:
   - ✅ Marca **"Copy items if needed"**
   - ✅ Asegúrate de que tu target **"Raskmap"** esté seleccionado
4. Haz clic en **Add**

### Verificar que está en el bundle:
- Selecciona tu target en Xcode → **Build Phases** → **Copy Bundle Resources**
- `countries.geojson` debe aparecer en la lista

---

## Paso 3 — Eliminar referencias a Item.swift

Si Xcode da errores por `Item`, simplemente:
1. Busca y borra `Item.swift` del proyecto
2. El nuevo `Country.swift` lo reemplaza completamente

---

## Paso 4 — Ejecutar

Presiona **▶** o `Cmd+R`. La primera vez tardará un poco en cargar el GeoJSON.

---

## Cómo funciona la app

| Acción | Resultado |
|--------|-----------|
| Tocar un país | Abre panel de opciones |
| Seleccionar "Visitado" | País se pinta de 🟢 verde |
| Seleccionar "Quiero ir" | País se pinta de 🔴 rojo |
| Seleccionar "Desmarcar" | País vuelve a transparente |

Los datos se guardan automáticamente en el dispositivo (SQLite gestionado por SwiftData).

---

## Paralelos Java → Swift para entender el código

| Java/Spring | Swift/SwiftData |
|-------------|-----------------|
| `@Entity` | `@Model` |
| `EntityManager` | `ModelContext` |
| `@Autowired` | `@Environment` |
| `JpaRepository.findAll()` | `@Query` |
| `entityManager.persist()` | `modelContext.insert()` |
| `@Transactional` | Automático en SwiftData |
| `CompletableFuture.supplyAsync()` | `Task.detached` |
| Interfaz/Listener | Coordinator (delegate) |

---

## Posibles errores

**"countries.geojson not found"**
→ El archivo no está en el bundle. Repite el Paso 2.

**Los países no se colorean al tocar**
→ Asegúrate de que `Country.self` está en el Schema de `RaskmapApp.swift`.

**Xcode dice "Cannot find Item in scope"**
→ Borra `Item.swift` del proyecto.
