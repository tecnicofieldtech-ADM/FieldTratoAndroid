# Release APK RFeedX (atualização sem desinstalar)

## Requisitos para instalar por cima do app antigo

1. **Mesmo `applicationId`**: `com.rfeed.rfeedx` (já definido em `android/app/build.gradle.kts`).
2. **Mesmo certificado de assinatura**: use o arquivo `android/key.properties` apontando para o **mesmo** `.jks` / keystore do APK que o cliente já tem.
3. **`versionCode` maior**: incremente o número após `+` em `pubspec.yaml` (ex.: cliente em `2017` → use `1.0.12+2018`).

## Gerar o APK

```powershell
cd c:\RSistemas\Git\RFeedFlutter
.\scripts\Build-ReleaseApk.ps1
```

APK único (recomendado para envio):

`build\app\outputs\flutter-apk\app-release.apk`

## Instalar no tablet

```text
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

Ou envie o APK por WhatsApp/e-mail e abra no dispositivo (permitir fontes desconhecidas).

## Backup de configuração em disco

A partir desta versão, ao **Confirmar** na tela de configuração, o app grava:

`Downloads/RFeed/rfeed_config_backup.json`

- **Atualização do APK** (sem desinstalar): SQLite e prefs permanecem; o backup é atualizado ao salvar config.
- **Reinstalação** (desinstalar e instalar de novo): na abertura, se não houver CONFIG no app, o backup em Downloads é restaurado automaticamente.

Na tela **Configuração** há o botão **Restaurar do disco** para importar manualmente.

**Importante:** o backup não inclui senha de usuário do login (apenas último usuário logado, se existir). Dados operacionais (fabricação/fornecimento) ficam no SQLite do app e **não** vão para esse arquivo — só a CONFIG.
