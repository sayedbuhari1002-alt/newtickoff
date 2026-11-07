$ErrorActionPreference = 'Stop'

$KeytoolCommand = Get-Command keytool -ErrorAction SilentlyContinue
if (-not $KeytoolCommand) {
    throw "keytool was not found. Install a JDK (Java 17 is suitable); Flutter is NOT required."
}

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$KeystorePath = Join-Path $ProjectRoot 'tazkiyane-release.jks'
$Base64Path = Join-Path $ProjectRoot 'tazkiyane-release-keystore.base64.txt'
$Alias = 'tazkiyane'

if (Test-Path $KeystorePath) {
    throw "Keystore already exists at '$KeystorePath'. Refusing to overwrite your signing identity. Back it up before doing anything else."
}
if (Test-Path $Base64Path) {
    throw "Base64 file already exists at '$Base64Path'. Move or securely inspect it before generating another key."
}

Write-Host 'Creating the permanent Tazkiyane Android release key.' -ForegroundColor Cyan
Write-Host 'Choose a strong keystore password and save it in a password manager.'
Write-Host 'When keytool asks for the key password, press ENTER to use the same password.'
Write-Host 'Do not upload the .jks file to chats or commit it to Git.'

& $KeytoolCommand.Source -genkeypair -v `
    -keystore $KeystorePath `
    -alias $Alias `
    -keyalg RSA `
    -keysize 4096 `
    -validity 10000 `
    -dname 'CN=Tazkiyane Release, OU=Android, O=Tazkiyane, C=IN'

if ($LASTEXITCODE -ne 0 -or -not (Test-Path $KeystorePath)) {
    throw 'keytool failed to create the release keystore.'
}

$Bytes = [System.IO.File]::ReadAllBytes($KeystorePath)
$Encoded = [Convert]::ToBase64String($Bytes)
[System.IO.File]::WriteAllText($Base64Path, $Encoded, [System.Text.Encoding]::ASCII)

Write-Host ''
Write-Host 'Keystore created. Certificate details:' -ForegroundColor Green
& $KeytoolCommand.Source -list -v -keystore $KeystorePath -alias $Alias
if ($LASTEXITCODE -ne 0) {
    throw 'The new keystore could not be read back.'
}

Write-Host ''
Write-Host "Keystore: $KeystorePath"
Write-Host "GitHub secret value file: $Base64Path"
Write-Host 'Create these GitHub repository Actions secrets:' -ForegroundColor Yellow
Write-Host '  ANDROID_KEYSTORE_BASE64  = contents of the .base64.txt file'
Write-Host '  ANDROID_KEYSTORE_PASSWORD = the keystore password you entered'
Write-Host '  ANDROID_KEY_ALIAS = tazkiyane'
Write-Host '  ANDROID_KEY_PASSWORD = the key password (pressing ENTER above means same as keystore password)'
Write-Host ''
Write-Host 'Keep an encrypted offline backup of the .jks file. Do not commit either generated file.'
