param(
    [Parameter(Mandatory = $true)]
    [string]$SourceImage
)

Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"
$appRoot = Split-Path -Parent $PSScriptRoot
$source = [System.Drawing.Image]::FromFile((Resolve-Path $SourceImage))

function New-AppIcon {
    param(
        [int]$Size,
        [string]$OutputPath,
        [double]$CatWidth = 0.80
    )

    $bitmap = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

    $rect = New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)
    $top = [System.Drawing.Color]::FromArgb(11, 9, 23)
    $bottom = [System.Drawing.Color]::FromArgb(52, 28, 91)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $top, $bottom, 135.0)
    $graphics.FillRectangle($brush, $rect)

    $targetWidth = [int]($Size * $CatWidth)
    $targetHeight = [int]($targetWidth * $source.Height / $source.Width)
    $x = [int](($Size - $targetWidth) / 2)
    $y = [int](($Size - $targetHeight) / 2 + $Size * 0.02)
    $graphics.DrawImage($source, $x, $y, $targetWidth, $targetHeight)

    $directory = Split-Path -Parent $OutputPath
    if (-not (Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)

    $brush.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
}

$master = Join-Path $appRoot "assets\branding\pusheen_app_icon.png"
New-AppIcon -Size 1024 -OutputPath $master -CatWidth 0.80

$iosRoot = Join-Path $appRoot "ios\Runner\Assets.xcassets\AppIcon.appiconset"
$iosIcons = @{
    "Icon-App-20x20@1x.png" = 20; "Icon-App-20x20@2x.png" = 40; "Icon-App-20x20@3x.png" = 60
    "Icon-App-29x29@1x.png" = 29; "Icon-App-29x29@2x.png" = 58; "Icon-App-29x29@3x.png" = 87
    "Icon-App-40x40@1x.png" = 40; "Icon-App-40x40@2x.png" = 80; "Icon-App-40x40@3x.png" = 120
    "Icon-App-60x60@2x.png" = 120; "Icon-App-60x60@3x.png" = 180
    "Icon-App-76x76@1x.png" = 76; "Icon-App-76x76@2x.png" = 152
    "Icon-App-83.5x83.5@2x.png" = 167; "Icon-App-1024x1024@1x.png" = 1024
}
foreach ($item in $iosIcons.GetEnumerator()) {
    New-AppIcon -Size $item.Value -OutputPath (Join-Path $iosRoot $item.Key) -CatWidth 0.80
}

$androidIcons = @{
    "mipmap-mdpi\ic_launcher.png" = 48; "mipmap-hdpi\ic_launcher.png" = 72
    "mipmap-xhdpi\ic_launcher.png" = 96; "mipmap-xxhdpi\ic_launcher.png" = 144
    "mipmap-xxxhdpi\ic_launcher.png" = 192
}
$androidRoot = Join-Path $appRoot "android\app\src\main\res"
foreach ($item in $androidIcons.GetEnumerator()) {
    New-AppIcon -Size $item.Value -OutputPath (Join-Path $androidRoot $item.Key) -CatWidth 0.70
}

$webRoot = Join-Path $appRoot "web"
New-AppIcon -Size 32 -OutputPath (Join-Path $webRoot "favicon.png") -CatWidth 0.72
New-AppIcon -Size 192 -OutputPath (Join-Path $webRoot "icons\Icon-192.png") -CatWidth 0.80
New-AppIcon -Size 512 -OutputPath (Join-Path $webRoot "icons\Icon-512.png") -CatWidth 0.80
New-AppIcon -Size 192 -OutputPath (Join-Path $webRoot "icons\Icon-maskable-192.png") -CatWidth 0.66
New-AppIcon -Size 512 -OutputPath (Join-Path $webRoot "icons\Icon-maskable-512.png") -CatWidth 0.66

$source.Dispose()
Write-Host "Generated Pusheen app icons for iOS, Android and Web."
