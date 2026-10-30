# Servidor de imágenes de cartas (GitHub Pages)

Las imágenes de las cartas se publican desde un repositorio **público** aparte,
`garaje-tcg-cartas`, para que el código de la app siga privado. Todo se hace
desde el navegador, una sola vez.

## 1. Crear el repositorio
GitHub → **+** (arriba a la derecha) → **New repository**
- Nombre: `garaje-tcg-cartas`
- **Public**
- Marca "Add a README file"
- **Create repository**

## 2. Subir los dos archivos
En el repositorio nuevo → **Add file → Upload files** → arrastra desde
`tools/cards/` de la app:
- `build_card_db.py`
- `banlist_edison.txt`

→ **Commit changes**.

## 3. Crear el workflow
**Add file → Create new file**
- Nombre: `.github/workflows/cartas.yml` (al escribir las barras se crean las carpetas)
- Contenido: copia y pega todo `tools/cards/cartas.yml`

→ **Commit changes**.

## 4. Activar GitHub Pages
**Settings → Pages → Build and deployment → Source: GitHub Actions**.

## 5. Ejecutarlo
**Actions → Cartas Edison → Run workflow**. La primera vez tarda unos 15–20
minutos (baja unas 8000 imágenes). Al terminar, el paso "publicar" muestra la
dirección de la página.

## 6. Comprobar desde Cuba
En el navegador del teléfono:
- https://lachy97.github.io/garaje-tcg-cartas/ → debe salir "Garage TCG" y una carta.
- En la app (versión nueva): **Ajustes → Cartas → Probar descarga de imágenes**.

## 7. Poner la base de cartas en la app
Descarga https://lachy97.github.io/garaje-tcg-cartas/edison_cards.json y
guárdalo en la app en `assets/cards/edison_cards.json` (reemplaza el que hay).
Luego `git add -A`, `git commit`, `git push` como siempre.

## Actualizar (si cambia algo en YGOPRODeck)
Vuelve a ejecutar el workflow (paso 5) y repite el paso 7.
