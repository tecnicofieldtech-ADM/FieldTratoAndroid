# Field Trato — release Google Play

## Identificação do app

| Campo | Valor |
|--------|--------|
| Nome na loja | Field Trato |
| `applicationId` | `com.rfeed.fieldtrato` |
| Versão | `pubspec.yaml` → `version: X.Y.Z+NN` (`NN` = `versionCode`) |

## 1) Assinatura (upload keystore)

O Play Console exige o **mesmo certificado** em todas as atualizações.

1. Copie `android/key.properties.example` → `android/key.properties`
2. Preencha senhas, alias e caminho do `.jks`
3. Keystore atual do projeto: `android/app/upload-keystore.jks` (não versionar)

Gerar keystore novo (somente se for app **novo** na loja):

```powershell
keytool -genkey -v -keystore android/app/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

## 2) Incrementar versão

Em `pubspec.yaml`:

```yaml
version: 1.0.17+90
```

- Número após `+` (**versionCode**) deve ser **maior** que o último enviado ao Play Console.
- APKs em `releases/` usam o mesmo esquema (`FieldTrato-1.0.16-build89.apk` → build 89).

## 3) Gerar AAB (obrigatório na Play Store)

```powershell
cd c:\RSistemas\Git\FieldTrato
.\scripts\Build-ReleaseBundle.ps1
```

Saída:

- `build/app/outputs/bundle/release/app-release.aab`
- `releases/FieldTrato-<versao>-build<codigo>.aab`

APK (distribuição direta / tablet):

```powershell
.\scripts\Build-ReleaseApk.ps1
```

## 4) Play Console — checklist

1. Criar app com `applicationId` **com.rfeed.fieldtrato**
2. Enviar o `.aab` (teste interno → produção)
3. **Ficha da loja**: ícone 512×512, feature graphic, screenshots (tablet recomendado)
4. **Classificação de conteúdo** e **público-alvo**
5. **Data safety** — declarar uso de:
   - Internet, Wi‑Fi, Bluetooth, localização (SSID em Android)
   - Dados operacionais locais (SQLite) e sync com API do cliente
6. **Política de privacidade** (URL pública)
7. Notas da versão (ex.: correção previsto último trato após sync)

## 5) Permissões (AndroidManifest)

O app solicita: `INTERNET`, Wi‑Fi, `BLUETOOTH` / `BLUETOOTH_CONNECT` / `BLUETOOTH_SCAN`, localização (SSID). Justifique no formulário Data safety conforme uso em campo (balança BT, rede da fazenda).

## 6) Primeira publicação vs atualização

| Cenário | Ação |
|---------|------|
| **Primeiro upload** | Qualquer `versionCode` ≥ 1 com keystore de upload |
| **Atualização** | Mesmo keystore; `versionCode` estritamente maior |
| **APK já instalado no cliente** | Mesmo certificado; `versionCode` maior que o APK em uso |

## 7) Verificação antes de enviar

```powershell
# Versão embutida no AAB (requer bundletool ou Play Console após upload)
flutter build appbundle --release --verbose
```

Confirme no dispositivo de teste (teste interno):

- Login e sync com API
- Fornecimento / fabricação
- Bluetooth e Wi‑Fi (se usados no cliente)
