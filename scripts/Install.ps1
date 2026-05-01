#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Yangın Tesisat Platformu — AutoCAD eklentisi kurulumu
.DESCRIPTION
    GitHub'dan son sürümü indirir ve AutoCAD'e kurar.
    AutoCAD'i yeniden başlattığınızda eklenti otomatik yüklenir.
.EXAMPLE
    # İnternet üzerinden (tek komut):
    irm https://raw.githubusercontent.com/celikfrkn/mekaniktesisatapp_public/main/scripts/Install.ps1 | iex

    # Yerel klasörden (ZIP yanına koyup):
    .\Install.ps1

    # Belirli bir DLL ile:
    .\Install.ps1 -DllYolu "C:\Downloads\YanginTesisat.dll"
#>
param(
    [string]$DllYolu = "",
    [string]$GitHubKullanici = "celikfrkn",
    [string]$GitHubRepo = "mekaniktesisatapp_public"
)

$ErrorActionPreference = "Stop"
$bundleKok = "$env:APPDATA\Autodesk\ApplicationPlugins\YanginTesisat.bundle"
$hedefDizin = "$bundleKok\Contents\Win64"

function Yaz($mesaj, $renk = "White") {
    Write-Host $mesaj -ForegroundColor $renk
}

Yaz ""
Yaz "=================================================" "Cyan"
Yaz "  Yangın Tesisat Platformu — Kurulum v1.0" "Cyan"
Yaz "=================================================" "Cyan"
Yaz ""

# ─── AutoCAD kurulu mu? ────────────────────────────────────────────────────
$acadExe = Get-ItemProperty "HKLM:\SOFTWARE\Autodesk\AutoCAD" -ErrorAction SilentlyContinue
if (-not $acadExe) {
    Yaz "UYARI: AutoCAD kayıt defterinde bulunamadı." "Yellow"
    Yaz "         Kuruluma devam ediliyor..." "Yellow"
}

# ─── Hedef klasörü oluştur ────────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path $hedefDizin | Out-Null
Yaz "✓ Kurulum klasörü hazır: $bundleKok" "Green"

# ─── DLL'yi kur ──────────────────────────────────────────────────────────
if ($DllYolu -ne "" -and (Test-Path $DllYolu)) {
    # Yerel DLL ile kurulum
    Yaz "Yerel DLL kopyalanıyor..." "Yellow"
    Copy-Item $DllYolu "$hedefDizin\YanginTesisat.dll" -Force

} elseif (Test-Path ".\YanginTesisat.dll") {
    # Aynı klasörde DLL varsa
    Yaz "Mevcut DLL kopyalanıyor..." "Yellow"
    Copy-Item ".\YanginTesisat.dll" "$hedefDizin\YanginTesisat.dll" -Force

} else {
    # GitHub'dan indir
    Yaz "GitHub'dan son sürüm indiriliyor..." "Yellow"
    $apiUrl = "https://api.github.com/repos/$GitHubKullanici/$GitHubRepo/releases/latest"

    try {
        $release = Invoke-RestMethod -Uri $apiUrl -Headers @{ "User-Agent" = "YanginTesisatInstaller" }
        $zipUrl = ($release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1).browser_download_url

        if (-not $zipUrl) {
            throw "Release ZIP bulunamadı. GitHub Actions ile önce bir release oluşturun."
        }

        $geciciZip = "$env:TEMP\YanginTesisat_$($release.tag_name).zip"
        $geciciDizin = "$env:TEMP\YanginTesisat_kurulum"

        Yaz "İndiriliyor: $($release.tag_name)..." "Yellow"
        Invoke-WebRequest -Uri $zipUrl -OutFile $geciciZip -UseBasicParsing

        Yaz "Ayıklanıyor..." "Yellow"
        Remove-Item $geciciDizin -Recurse -Force -ErrorAction SilentlyContinue
        Expand-Archive -Path $geciciZip -DestinationPath $geciciDizin

        # Bundle içeriğini kopyala
        $bundleKaynak = Get-ChildItem $geciciDizin -Filter "*.bundle" -Recurse | Select-Object -First 1
        if ($bundleKaynak) {
            Copy-Item "$($bundleKaynak.FullName)\*" $bundleKok -Recurse -Force
        } else {
            # Eski format: sadece DLL
            Copy-Item "$geciciDizin\YanginTesisat.dll" "$hedefDizin\YanginTesisat.dll" -Force
        }

        # MotW (İnternet güvenlik kilidi) kaldır - AutoCAD'in donmasını engeller
        Get-ChildItem -Path $bundleKok -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

        Remove-Item $geciciZip -Force -ErrorAction SilentlyContinue
        Remove-Item $geciciDizin -Recurse -Force -ErrorAction SilentlyContinue

    } catch {
        Yaz "HATA: $_" "Red"
        Yaz ""
        Yaz "Manuel kurulum için:" "Yellow"
        Yaz "  1. GitHub'dan YanginTesisat.zip dosyasını indirin" "White"
        Yaz "  2. ZIP'i açın, YanginTesisat.dll dosyasını bu klasöre kopyalayın:" "White"
        Yaz "     $hedefDizin" "White"
        exit 1
    }
}

# ─── PackageContents.xml yoksa oluştur ───────────────────────────────────
$xmlYol = "$bundleKok\PackageContents.xml"
if (-not (Test-Path $xmlYol)) {
    $xml = @'
<?xml version="1.0" encoding="utf-8"?>
<ApplicationPackage SchemaVersion="1.0" Version="1.0.0"
    ProductCode="{B4F2A1C3-D8E5-4F90-A2BC-EF1234567891}"
    Name="Yangın Tesisat Platformu"
    Description="AutoCAD Yangın Tesisatı Çizim ve Hesap Eklentisi"
    Author="Mekanik Tesisat Platformu">
  <CompanyDetails Name="Mekanik Tesisat Platformu" />
  <RuntimeRequirements OS="Win64" Platform="AutoCAD" SeriesMin="R24.0" SeriesMax="*" />
  <Components>
    <RuntimeRequirements OS="Win64" Platform="AutoCAD" SeriesMin="R24.0" />
    <ComponentEntry AppName="YanginTesisat" Version="1.0.0"
                    ModuleName="./Contents/Win64/YanginTesisat.dll" />
  </Components>
</ApplicationPackage>
'@
    Set-Content -Path $xmlYol -Value $xml -Encoding UTF8
}

# ─── DLL kopyalandı mı? kontrol ──────────────────────────────────────────
if (-not (Test-Path "$hedefDizin\YanginTesisat.dll")) {
    Yaz "HATA: DLL kopyalanamadı!" "Red"
    exit 1
}

$dllBilgi = Get-Item "$hedefDizin\YanginTesisat.dll"

Yaz ""
Yaz "=================================================" "Green"
Yaz "  Kurulum Tamamlandı!" "Green"
Yaz "=================================================" "Green"
Yaz ""
Yaz "  DLL Boyutu : $([math]::Round($dllBilgi.Length / 1KB, 1)) KB" "White"
Yaz "  Konum      : $hedefDizin" "White"
Yaz ""
Yaz "  AutoCAD'i yeniden başlatın." "Yellow"
Yaz "  'YANGIN TESİSATI' sekmesi otomatik görünecektir." "Yellow"
Yaz ""
Yaz "  Komutlar: YTSPRINKLER  YTOTOBAG  YTCAPLA" "Cyan"
Yaz "            YTSISTEM     YTMETRAJ  YTMEKANIK" "Cyan"
Yaz ""
