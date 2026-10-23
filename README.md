# Ventas CROC — Abarrotes El Maná (Proyecto Flutter)

Aplicación Flutter completa lista para compilar a APK de Android.

## Cómo generar el archivo APK:

### Método 1: GitHub Actions (En la Nube, 100% Automático y Gratis)
1. Sube este proyecto descomprimido a un repositorio nuevo en GitHub (privado o público).
2. Ve a la pestaña **Actions** en tu repositorio de GitHub.
3. El workflow **"Build Release APK"** se ejecutará automáticamente (o haz clic en "Run workflow").
4. En 3 minutos, haz clic en la ejecución completada y descarga el archivo **app-release.apk** en la sección "Artifacts". ¡Instálalo directo en tu teléfono Android!

### Método 2: En tu PC con Flutter instalado
1. Abre la terminal en la carpeta del proyecto.
2. Ejecuta:
   ```bash
   flutter pub get
   flutter build apk --release
   ```
3. Tu archivo APK listo para instalar estará en:
   `build/app/outputs/flutter-apk/app-release.apk`
