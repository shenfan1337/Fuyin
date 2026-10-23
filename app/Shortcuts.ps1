function New-FuyinDesktopShortcut([string]$ProgramRoot,[string]$DesktopDirectory){
 $ErrorActionPreference='Stop'
 if(-not $DesktopDirectory){$DesktopDirectory=[Environment]::GetFolderPath('Desktop')}
 $target=[IO.Path]::GetFullPath((Join-Path $ProgramRoot 'Luma.exe'))
 if(-not [IO.File]::Exists($target)){throw '请先将软件完整解压到固定文件夹。'}
 $path=Join-Path $DesktopDirectory '浮音.lnk'
 $shell=New-Object -ComObject WScript.Shell
 try{
  $link=$shell.CreateShortcut($path)
  try{
   if([IO.File]::Exists($path) -and $link.Description -ne 'Fuyin Luma desktop shortcut'){throw '桌面已有同名快捷方式，未覆盖。'}
   $link.TargetPath=$target;$link.WorkingDirectory=[IO.Path]::GetFullPath($ProgramRoot)
   $link.IconLocation=(Join-Path $ProgramRoot 'Fuyin.ico')+',0'
   $link.Description='Fuyin Luma desktop shortcut';$link.Save()
  }finally{$null=[Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)}
 }finally{$null=[Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)}
 return $path
}
