#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Yangın Tesisat Platformu — AutoCAD eklentisi kurulumu
.EXAMPLE
    irm https://raw.githubusercontent.com/celikfrkn/mekaniktesisatapp_public/main/scripts/Install.ps1 | iex
#>
param(
    [string]$DllYolu = "",
    [string]$GitHubKullanici = "celikfrkn",
    [string]$GitHubRepo = "mekaniktesisatapp_public"
)

$ErrorActionPreference = "Stop"
$bundleKok  = "$env:APPDATA\Autodesk\ApplicationPlugins\YanginTesisat.bundle"
$hedefDizin = "$bundleKok\Contents\Win64"

function Yaz($mesaj, $renk = "White") { Write-Host $mesaj -ForegroundColor $renk }

Yaz ""
Yaz "=================================================" "Cyan"
Yaz "  Yangin Tesisat Platformu — Kurulum"            "Cyan"
Yaz "=================================================" "Cyan"
Yaz ""

# ─── Hedef klasörü oluştur ────────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path $hedefDizin | Out-Null
Yaz "Klasor hazir: $bundleKok" "Green"

# ─── DLL'yi kur ──────────────────────────────────────────────────────────
if ($DllYolu -ne "" -and (Test-Path $DllYolu)) {
    Copy-Item $DllYolu "$hedefDizin\YanginTesisat.dll" -Force
    Yaz "Yerel DLL kopyalandi." "Green"

} elseif (Test-Path ".\YanginTesisat.dll") {
    Copy-Item ".\YanginTesisat.dll" "$hedefDizin\YanginTesisat.dll" -Force
    Yaz "Mevcut DLL kopyalandi." "Green"

} else {
    Yaz "GitHub'dan indiriliyor..." "Yellow"
    $apiUrl = "https://api.github.com/repos/$GitHubKullanici/$GitHubRepo/releases/latest"
    try {
        $release = Invoke-RestMethod -Uri $apiUrl -Headers @{ "User-Agent" = "YanginTesisatInstaller" }
        $zipUrl  = ($release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1).browser_download_url
        if (-not $zipUrl) { throw "Release ZIP bulunamadi." }

        $geciciZip  = "$env:TEMP\YanginTesisat.zip"
        $geciciDizin = "$env:TEMP\YanginTesisat_kur"

        Invoke-WebRequest -Uri $zipUrl -OutFile $geciciZip -UseBasicParsing
        Yaz "Indirme tamam, aciliyor..." "Yellow"

        Remove-Item $geciciDizin -Recurse -Force -ErrorAction SilentlyContinue
        Expand-Archive -Path $geciciZip -DestinationPath $geciciDizin

        $bundleKaynak = Get-ChildItem $geciciDizin -Filter "*.bundle" -Recurse | Select-Object -First 1
        if ($bundleKaynak) {
            Copy-Item "$($bundleKaynak.FullName)\*" $bundleKok -Recurse -Force
        } else {
            Copy-Item "$geciciDizin\YanginTesisat.dll" "$hedefDizin\YanginTesisat.dll" -Force
        }

        Remove-Item $geciciZip, $geciciDizin -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        Yaz "HATA: $_" "Red"
        exit 1
    }
}

# ─── Windows güvenlik kilidini kaldır (MotW) ─────────────────────────────
Yaz "Guvenlik kilitleri kaldiriliyor..." "Yellow"
Get-ChildItem -Path $bundleKok -Recurse -File | ForEach-Object {
    Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue
    # Stream:Zone.Identifier'ı da doğrudan sil
    $zoneFile = "$($_.FullName):Zone.Identifier"
    Remove-Item $zoneFile -ErrorAction SilentlyContinue
}
Yaz "Guvenlik kilitleri kaldirildi." "Green"

# ─── PackageContents.xml'i her zaman taze yaz ───────────────────────────
$xml = @'
<?xml version="1.0" encoding="utf-8"?>
<ApplicationPackage SchemaVersion="1.0" Version="1.0.0"
    ProductCode="{B4F2A1C3-D8E5-4F90-A2BC-EF1234567891}"
    Name="Yangin Tesisat Platformu"
    Description="AutoCAD Yangin Tesisati Eklentisi"
    Author="Mekanik Tesisat">
  <CompanyDetails Name="Mekanik Tesisat" />
  <Components>
    <RuntimeRequirements OS="Win64" Platform="AutoCAD" SeriesMin="R24.0" SeriesMax="*" />
    <ComponentEntry AppName="YanginTesisat" Version="1.0.0"
                    ModuleName="./Contents/Win64/YanginTesisat.dll" />
  </Components>
</ApplicationPackage>
'@
Set-Content -Path "$bundleKok\PackageContents.xml" -Value $xml -Encoding UTF8 -NoNewline

# ─── AutoCAD Güvenlik Ayarları (SECURELOAD + TrustedPaths) ──────────────
Yaz "AutoCAD guvenlik ayarlari yapilandiriliyor..." "Yellow"

# SECURELOAD = 0 → tüm eklentilere izin ver (AutoCAD kayıt yollarında)
$acadRegKokler = @(
    "HKCU:\Software\Autodesk\AutoCAD",
    "HKLM:\SOFTWARE\Autodesk\AutoCAD"
)
foreach ($kok in $acadRegKokler) {
    if (Test-Path $kok) {
        Get-ChildItem $kok -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $yol = $_.PSPath
            # General2 key'ini bul - SECURELOAD ve TRUSTEDPATHS burada
            if ($yol -like "*General2*") {
                try {
                    Set-ItemProperty -Path $yol -Name "SECURELOAD" -Value 0 -Type DWord -ErrorAction SilentlyContinue
                    $mevcutTrusted = (Get-ItemProperty -Path $yol -Name "TRUSTEDPATHS" -ErrorAction SilentlyContinue).TRUSTEDPATHS
                    if ($mevcutTrusted -notlike "*YanginTesisat*") {
                        $yeniTrusted = "$bundleKok\Contents\Win64;$mevcutTrusted"
                        Set-ItemProperty -Path $yol -Name "TRUSTEDPATHS" -Value $yeniTrusted -ErrorAction SilentlyContinue
                    }
                } catch {}
            }
        }
    }
}
Yaz "AutoCAD guvenlik ayarlari tamamlandi." "Green"

# ─── Doğrulama ───────────────────────────────────────────────────────────
if (-not (Test-Path "$hedefDizin\YanginTesisat.dll")) {
    Yaz "HATA: DLL bulunamadi!" "Red"
    exit 1
}

$dllBilgi = Get-Item "$hedefDizin\YanginTesisat.dll"
Yaz ""
Yaz "=================================================" "Green"
Yaz "  KURULUM TAMAMLANDI!" "Green"
Yaz "=================================================" "Green"
Yaz ""
Yaz "  DLL Boyutu : $([math]::Round($dllBilgi.Length / 1KB, 1)) KB" "White"
Yaz "  Konum      : $hedefDizin" "White"
Yaz ""
Yaz "  AutoCAD'i yeniden baslatın." "Yellow"
Yaz "  Komutlar: YTSPRINKLER  YTCAPLA  YTSISTEM  YTMETRAJ" "Cyan"
Yaz ""
