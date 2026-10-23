# Only Toggle-Startup (the UI) requests consent. These functions never run at import.
function Get-LumaStartupPath([string]$StartupDirectory) {
 if (-not $StartupDirectory) { $StartupDirectory=[Environment]::GetFolderPath('Startup') }
 if (-not $StartupDirectory -or -not [IO.Directory]::Exists($StartupDirectory)) { throw '找不到当前用户的 Windows 启动目录。' }
 return Join-Path $StartupDirectory 'LumaLyrics.lnk'
}
function Get-LumaStartup([string]$StartupDirectory) {
 $path=Get-LumaStartupPath $StartupDirectory
 if (-not [IO.File]::Exists($path)) { return @{Installed=$false;Owned=$false;Path=$path;Target=''} }
 $shell=New-Object -ComObject WScript.Shell
 try {
  $link=$shell.CreateShortcut($path)
  try { return @{Installed=$true;Owned=($link.Description -eq 'LumaLyrics: consented user logon startup');Path=$path;Target=$link.TargetPath} }
  finally { $null=[Runtime.InteropServices.Marshal]::FinalReleaseComObject($link) }
 } finally { $null=[Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
}
function Enable-LumaStartup([string]$ProgramRoot,[string]$StartupDirectory) {
 $target=Join-Path $ProgramRoot 'Luma.exe'
 if (-not [IO.File]::Exists($target)) { throw '找不到 Luma.exe，请把软件完整解压到固定文件夹后再开启自启动。' }
 $state=Get-LumaStartup $StartupDirectory
 if ($state.Installed -and -not $state.Owned) { throw '启动目录已有同名的其他快捷方式。为避免覆盖，未进行修改。' }
 $shell=New-Object -ComObject WScript.Shell
 try {
  $link=$shell.CreateShortcut($state.Path)
  try {
   $link.TargetPath=[IO.Path]::GetFullPath($target)
   $link.Arguments='--startup'
   $link.WorkingDirectory=[IO.Path]::GetFullPath($ProgramRoot)
   $link.Description='LumaLyrics: consented user logon startup'
   $link.WindowStyle=7
   $link.IconLocation=(Join-Path $ProgramRoot 'Fuyin.ico')+',0'
   $link.Save()
  } finally { $null=[Runtime.InteropServices.Marshal]::FinalReleaseComObject($link) }
 } finally { $null=[Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
 $state=Get-LumaStartup $StartupDirectory
 if (-not $state.Owned -or $state.Target -ne [IO.Path]::GetFullPath($target)) { throw '自启动快捷方式未能正确保存。' }
}
function Disable-LumaStartup([string]$StartupDirectory) {
 $state=Get-LumaStartup $StartupDirectory
 if ($state.Installed) {
  if (-not $state.Owned) { throw '同名快捷方式不属于浮光歌词，未进行删除。' }
  [IO.File]::Delete($state.Path)
 }
}
