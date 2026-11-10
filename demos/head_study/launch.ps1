$ErrorActionPreference = 'Stop'
$godotCommand = Get-Command godot -ErrorAction SilentlyContinue
$godotPath = if ($godotCommand) { $godotCommand.Source } else { $null }
if (-not $godotPath) {
    $downloadRoot = Join-Path $env:USERPROFILE 'Downloads'
    $godotFolders = Get-ChildItem -LiteralPath $downloadRoot -Directory -Filter 'Godot*' -ErrorAction SilentlyContinue
    $godotPath = $godotFolders | Get-ChildItem -Recurse -File -Filter 'Godot*.exe' |
        Where-Object { $_.Name -notlike '*console*' } |
        Sort-Object @{ Expression = { $_.FullName -like '*mono*' } }, FullName |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $godotPath) {
    throw 'Godot 4 was not found. Import the project.godot in this folder with Godot 4 and press F5.'
}
& $godotPath --path $PSScriptRoot
