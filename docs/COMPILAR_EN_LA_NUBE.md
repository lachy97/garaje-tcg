# Compilar la APK en la nube (sin VPN)

La PC solo **sube el código** (≈1 MB) a GitHub; GitHub compila en sus servidores
y tú **bajas la APK** (≈10 MB). Nada de Gradle, Android SDK ni repositorios de
Google en tu conexión.

> GitHub está disponible para cuentas personales en Cuba (repositorios públicos,
> privados y GitHub Actions). Plan gratis: 2000 min/mes en repos privados;
> cada compilación tarda ~8-12 min.

---

## 1. Crear la clave de firma (una sola vez, sin internet)

Todas las APK deben firmarse **siempre con la misma clave**; si no, Android no deja
actualizar la app encima de la anterior y habría que desinstalar (se pierden los datos).

En `cmd`, usando el `keytool` que trae Android Studio:

```
"C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkey -v ^
  -keystore D:\Work\Movil\garaje-release.jks ^
  -keyalg RSA -keysize 2048 -validity 10000 -alias garaje
```

(Si no está en esa ruta, `flutter doctor -v` muestra dónde está Java: "Java binary at".)

Te pedirá una contraseña y unos datos (nombre, ciudad…). **Apunta la contraseña.**

⚠️ **Guarda copias de `garaje-release.jks` y su contraseña** (memoria USB, correo).
Si se pierden, nunca más se podrá actualizar la app instalada en los teléfonos.
El archivo queda **fuera** de la carpeta del proyecto a propósito: no debe subirse a GitHub.

Convierte la clave a texto (PowerShell):

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("D:\Work\Movil\garaje-release.jks")) | Set-Content D:\Work\Movil\keystore-base64.txt
```

## 2. Crear el repositorio en GitHub

1. Cuenta en <https://github.com> (personal).
2. **New repository** → nombre `garaje-tcg` → **Private** → sin README → *Create*.

## 3. Guardar los secretos de firma

En el repositorio: **Settings → Secrets and variables → Actions → New repository secret**.
Crea estos cuatro:

| Nombre | Valor |
|---|---|
| `KEYSTORE_BASE64` | todo el contenido de `keystore-base64.txt` |
| `KEYSTORE_PASSWORD` | la contraseña de la clave |
| `KEY_PASSWORD` | la misma contraseña (salvo que pusieras otra para el alias) |
| `KEY_ALIAS` | `garaje` |

Después puedes borrar `keystore-base64.txt`.

## 4. Subir el código

Necesitas [Git para Windows](https://git-scm.com/download/win) (o GitHub Desktop).
En `cmd`, dentro de `D:\Work\Movil\Yu-Gi-OH`:

```
mkdir .github\workflows
move ci\build-apk.yml .github\workflows\
rmdir ci
git init
git add .
git commit -m "Garaje TCG - fase 1"
git branch -M main
git remote add origin https://github.com/TU_USUARIO/garaje-tcg.git
git push -u origin main
```

La primera vez pedirá iniciar sesión en GitHub (se abre el navegador).

## 5. Descargar la APK

1. En el repositorio, pestaña **Actions** → ejecución **Build APK** (círculo amarillo =
   compilando, ✓ verde = lista).
2. Abajo, en **Artifacts**, descarga **garaje-tcg-arm64** (casi todos los teléfonos).
   Solo si el teléfono es muy antiguo y no instala, usa **garaje-tcg-arm32**.
3. Descomprime el `.zip`, pasa el `.apk` al teléfono (cable, Bluetooth, ShareIt…)
   e instálalo permitiendo "instalar apps de fuentes desconocidas".

## 6. Siguientes versiones

Cada vez que cambie el código:

```
git add .
git commit -m "Descripción del cambio"
git push
```

GitHub compila solo. El número de compilación sube automáticamente, así que la APK
nueva **se instala encima** de la anterior y se conservan los datos.

### Enlace directo para otros teléfonos (opcional)

```
git tag v0.1.0
git push origin v0.1.0
```

Crea una **Release** en GitHub con las APK; su enlace se puede abrir directamente
desde el navegador de un teléfono, sin iniciar sesión si el repo es público.

## Si falla una compilación

Entra en la ejecución roja en **Actions**, abre el paso que falló y copia las
últimas líneas del error para corregirlo.

## Alternativa: Codemagic

El archivo `codemagic.yaml` permite compilar lo mismo en <https://codemagic.io>
(500 min/mes gratis, conectando el mismo repo de GitHub). Los cuatro secretos van en
un grupo de variables llamado `firma`.
