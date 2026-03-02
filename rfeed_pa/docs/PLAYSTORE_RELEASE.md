# Play Store Release (Android)

## 1) Definir package id final
- Arquivo: `android/app/build.gradle.kts`
- Campos:
  - `namespace`
  - `defaultConfig.applicationId`
- Use um id definitivo, por exemplo: `com.rsistemas.rfeedmirror`.

## 2) Criar upload keystore (uma vez)
```powershell
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

## 3) Configurar assinatura
- Copie `android/key.properties.example` para `android/key.properties`.
- Preencha:
  - `storePassword`
  - `keyPassword`
  - `keyAlias`
  - `storeFile` (ex.: `../upload-keystore.jks`)

## 4) Gerar AAB de release
```powershell
flutter clean
flutter pub get
flutter build appbundle --release
```

Saida esperada:
- `build/app/outputs/bundle/release/app-release.aab`

## 5) Publicar no Play Console
- Crie o app no Play Console com o mesmo `applicationId`.
- Envie o `app-release.aab`.
- Complete:
  - Data Safety
  - Content Rating
  - Target audience
  - Politicas e permissões
  - Ficha da loja (icone 512x512, feature graphic, screenshots)

## 6) Proximas versoes
- Sempre incrementar `version` no `pubspec.yaml` (`build number` apos `+`).
