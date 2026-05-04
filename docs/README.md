# Raskmap — Legal pages (GitHub Pages)

Esta carpeta contiene los textos legales de Raskmap listos para publicar como sitio web estático.
Es lo que pide App Store Connect cuando subes la app: una **URL pública de Política de privacidad**
(y opcionalmente de Términos, Soporte, etc.).

## Archivos

| Archivo          | Finalidad                                | URL sugerida                |
| ---------------- | ---------------------------------------- | --------------------------- |
| `index.md`       | Landing con enlaces a todas las páginas  | `/`                         |
| `privacy.md`     | Política de privacidad (**requerida**)   | `/privacy`                  |
| `terms.md`       | Términos de uso                          | `/terms`                    |
| `imprint.md`     | Aviso legal                              | `/imprint`                  |
| `gdpr.md`        | Derechos RGPD                            | `/gdpr`                     |
| `credits.md`     | Atribuciones / créditos de terceros      | `/credits`                  |

Los textos son idénticos a los mostrados dentro de la app (Ajustes → Legal).

## Cómo publicar en GitHub Pages (5 minutos)

1. **Crear un repo público** en GitHub (p. ej. `raskmap-legal` o usar el del código si ya es público).
2. **Copiar esta carpeta `docs/`** a la raíz del repo y hacer push.
3. Entrar en **Settings → Pages** del repo.
4. En «Source» elegir **Deploy from a branch**.
5. Seleccionar la rama `main` y la carpeta `/docs`. Guardar.
6. Esperar ~1 minuto. GitHub muestra la URL, que será algo como:
   `https://<tu-usuario>.github.io/<nombre-del-repo>/`

### URLs finales esperadas

Si el repo se llama `raskmap-legal` y tu usuario es `jaimocho42`:

```
https://jaimocho42.github.io/raskmap-legal/
https://jaimocho42.github.io/raskmap-legal/privacy
https://jaimocho42.github.io/raskmap-legal/terms
...
```

## Qué pegar en App Store Connect

Al crear la ficha de la app en App Store Connect necesitas:

| Campo                         | Valor                                             |
| ----------------------------- | ------------------------------------------------- |
| **Privacy Policy URL**        | `https://<tu-usuario>.github.io/<repo>/privacy`   |
| **Support URL**               | `https://<tu-usuario>.github.io/<repo>/` (index)  |
| **Marketing URL** (opcional)  | `https://<tu-usuario>.github.io/<repo>/`          |

## Dominio propio (opcional)

Si prefieres `https://raskmap.app/privacy` en vez del dominio `.github.io`:

1. Compra el dominio.
2. Añade un fichero `CNAME` en `docs/` con el dominio (una línea, sin `https://`).
3. En el DNS del dominio añade un registro `CNAME` apuntando a `<tu-usuario>.github.io`.
4. En Settings → Pages → Custom domain, introducir el dominio y marcar «Enforce HTTPS».

## Mantenimiento

Cada vez que cambies los textos in-app (`LegalInfoSheet` en `ContentView.swift`), actualiza
también estos `.md` y haz push. Los dos deben decir lo mismo o Apple podría rechazarlo en revisión.
