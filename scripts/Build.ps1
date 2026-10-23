param([switch]$Test,[string]$Version='1.31',[string]$OutputRoot)
$ErrorActionPreference='Stop'
if($Version -notmatch '^\d+\.\d+(?:\.\d+)?$'){throw 'Invalid version'}
$repo=Split-Path $PSScriptRoot -Parent
if(-not $OutputRoot){$OutputRoot=Join-Path $repo 'dist'}
$OutputRoot=[IO.Path]::GetFullPath($OutputRoot)
$app=Join-Path $repo 'app'
$framework=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
if(-not (Test-Path (Join-Path $framework 'csc.exe'))){$framework=Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319'}
$compiler=Join-Path $framework 'csc.exe'
$winMeta=Join-Path $env:WINDIR 'System32\WinMetadata'
foreach($required in @($compiler,(Join-Path $framework 'System.Runtime.dll'),(Join-Path $framework 'System.Runtime.WindowsRuntime.dll'),(Join-Path $winMeta 'Windows.Foundation.winmd'),(Join-Path $winMeta 'Windows.Storage.winmd'))){
 if(-not (Test-Path -LiteralPath $required)){throw "Missing Windows build component: $required"}
}
$target=Join-Path $OutputRoot ('Fuyin-Windows-v'+$Version)
$null=New-Item -ItemType Directory -Path $target -Force
# Explicit allowlist: never package local settings, playback logs or downloaded adapters.
foreach($file in (Get-ChildItem -LiteralPath $app -File)){
 if($file.Extension -in @('.ps1','.cs','.xaml','.ico') -or $file.Name -in @('Fuyin.png','DESIGN.md','BRAND.md')){
  $destination=Join-Path $target $file.Name
  if($file.Extension -eq '.ps1'){[IO.File]::WriteAllText($destination,[IO.File]::ReadAllText($file.FullName),[Text.UTF8Encoding]::new($true))}
  else{Copy-Item -LiteralPath $file.FullName -Destination $destination -Force}
 }
}
Copy-Item -LiteralPath (Join-Path $app 'third-party') -Destination $target -Recurse -Force
foreach($name in @('README.md','LICENSE','NOTICE','CHANGELOG.md')){Copy-Item -LiteralPath (Join-Path $repo $name) -Destination $target -Force}
Copy-Item -LiteralPath (Join-Path $repo 'docs') -Destination $target -Recurse -Force
Copy-Item -LiteralPath (Join-Path $repo 'docs\使用指南.md') -Destination (Join-Path $target '使用说明.md') -Force
Push-Location $target
try{
 & $compiler '/nologo' '/target:library' '/out:CoverReader.dll' ('/reference:'+(Join-Path $winMeta 'Windows.Foundation.winmd')) ('/reference:'+(Join-Path $winMeta 'Windows.Storage.winmd')) ('/reference:'+(Join-Path $framework 'System.Runtime.WindowsRuntime.dll')) ('/reference:'+(Join-Path $framework 'System.Runtime.dll')) 'CoverReader.cs'
 if($LASTEXITCODE -ne 0){throw 'CoverReader compilation failed'}
 & $compiler '/nologo' '/target:winexe' '/out:Luma.exe' '/win32icon:Fuyin.ico' '/reference:System.Windows.Forms.dll' 'Launcher.cs'
 if($LASTEXITCODE -ne 0){throw 'Launcher compilation failed'}
}finally{Pop-Location}
if($Test){& (Join-Path $repo 'tests\Smoke.ps1') -AppRoot $target}
$archive=Join-Path $OutputRoot ('Fuyin-Windows-v'+$Version+'.zip')
Compress-Archive -LiteralPath (Get-ChildItem -LiteralPath $target).FullName -DestinationPath $archive -Force
$hash=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText(($archive+'.sha256'),$hash+'  '+[IO.Path]::GetFileName($archive)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
Write-Output "Built: $archive"
Write-Output "SHA256: $hash"
