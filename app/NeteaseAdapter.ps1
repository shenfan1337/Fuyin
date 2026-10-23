param([switch]$Install,[switch]$Uninstall,[string]$ProgramRoot,[string]$DataRoot,[string]$StageRoot)
$ErrorActionPreference='Stop'
function Get-FuyinAdapterDataRoot {
 $custom=[Environment]::GetEnvironmentVariable('BETTERNCM_PROFILE','User')
 if(-not $custom){$custom=[Environment]::GetEnvironmentVariable('BETTERNCM_PROFILE','Process')}
 if($custom){return $custom}
 if([IO.Directory]::Exists('C:\betterncm')){return 'C:\betterncm'}
 return Join-Path $PSScriptRoot 'adapter-data'
}
function Get-FuyinAdapterManifest {
 return @(
  @{Name='BetterNCMII.dll';Url='https://github.com/std-microblock/chromatic/releases/download/1.3.4/BetterNCMII.dll';Hash='A7C77AF418D7940E63FAA58EA036FBA1F4BAAD497947109EA52ED78C8E86608F';Target='msimg32.dll'},
  @{Name='InfLink-rs.plugin';Url='https://github.com/apoint123/inflink-rs/releases/download/v3.4.0/InfLink-rs.plugin';Hash='7D0B7B863B072A99B88EB614C788099315E690920889AACA22685D3663661468';Target='InfLink-rs.plugin'}
 )
}
function Send-FuyinEnvironmentChanged {
 if(-not ('FuyinEnvironmentNotify' -as [type])){
  Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class FuyinEnvironmentNotify {[DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern IntPtr SendMessageTimeout(IntPtr h,uint m,IntPtr w,string l,uint f,uint t,out IntPtr r);public static void Broadcast(){IntPtr r;SendMessageTimeout(new IntPtr(0xffff),0x1a,IntPtr.Zero,"Environment",2,1000,out r);}}'
 }
 [FuyinEnvironmentNotify]::Broadcast()
}
function Install-FuyinNeteaseAdapter([string]$ProgramRoot,[string]$DataRoot,[string]$StageRoot,[switch]$ConfigureUserProfile){
 if(-not $DataRoot){$DataRoot=Get-FuyinAdapterDataRoot}
 if(-not [IO.File]::Exists((Join-Path $ProgramRoot 'cloudmusic.exe'))){throw '所选文件夹中找不到 cloudmusic.exe。'}
 $reader=[IO.BinaryReader]::new([IO.File]::OpenRead((Join-Path $ProgramRoot 'cloudmusic.exe')))
 try{$reader.BaseStream.Position=0x3c;$pe=$reader.ReadInt32();$reader.BaseStream.Position=$pe+4;if($reader.ReadUInt16() -ne 0x8664){throw '此助手仅支持 64 位网易云；32 位旧版请使用上游安装器。'}}finally{$reader.Dispose()}
 if(-not $StageRoot){$StageRoot=Join-Path $env:LOCALAPPDATA 'LumaLyrics\adapter-downloads'}
 $null=New-Item -ItemType Directory -Path $StageRoot -Force
 $items=@(Get-FuyinAdapterManifest)
 foreach($item in $items){
  $package=Join-Path $StageRoot $item.Name
  if(-not (Test-Path -LiteralPath $package)){
   [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
   Invoke-WebRequest -Uri $item.Url -OutFile $package -UseBasicParsing -TimeoutSec 90
  }
  if((Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash -ne $item.Hash){throw ('组件校验失败：'+$item.Name)}
  $item.Path=if($item.Target -eq 'msimg32.dll'){Join-Path $ProgramRoot $item.Target}else{Join-Path $DataRoot ('plugins\'+$item.Target)}
  $item.Owned=-not (Test-Path -LiteralPath $item.Path)
  if(-not $item.Owned -and (Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash -ne $item.Hash){throw ('已有其他版本或同名文件，未覆盖：'+$item.Path)}
 }
 $marker=Join-Path $DataRoot 'FuyinAdapter.json'
 $old=if(Test-Path -LiteralPath $marker){Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json}else{$null}
 $previousProfile=[Environment]::GetEnvironmentVariable('BETTERNCM_PROFILE','User')
 $profileChanged=$false
 $created=@()
 try{
  $null=New-Item -ItemType Directory -Path (Join-Path $DataRoot 'plugins') -Force
  foreach($item in $items){
   if($item.Owned){Copy-Item -LiteralPath (Join-Path $StageRoot $item.Name) -Destination $item.Path;$created+=,$item}
   if($old){$previous=$old | Where-Object {$_.Path -eq $item.Path -and $_.Hash -eq $item.Hash};if($previous){$item.Owned=[bool]$previous.Owned}}
  }
  if($ConfigureUserProfile -and $DataRoot -ne 'C:\betterncm'){
   [Environment]::SetEnvironmentVariable('BETTERNCM_PROFILE',$DataRoot,'User');$profileChanged=$true
   Send-FuyinEnvironmentChanged
   $items[0].ProfileChanged=$true;$items[0].PreviousProfile=$previousProfile
   if($old -and $old[0].ProfileChanged){$items[0].PreviousProfile=$old[0].PreviousProfile}
  }
  [IO.File]::WriteAllText($marker,($items | ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($true))
 }catch{
  if($profileChanged){[Environment]::SetEnvironmentVariable('BETTERNCM_PROFILE',$previousProfile,'User');Send-FuyinEnvironmentChanged}
  foreach($item in $created){if((Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash -eq $item.Hash){[IO.File]::Delete($item.Path)}}
  throw
 }
 return $marker
}
function Uninstall-FuyinNeteaseAdapter([string]$ProgramRoot,[string]$DataRoot){
 if(@(Get-Process cloudmusic -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq (Join-Path $ProgramRoot 'cloudmusic.exe')}).Count){throw '请先从托盘完全退出网易云，再卸载适配组件。'}
 if(-not $DataRoot){$DataRoot=Get-FuyinAdapterDataRoot}
 $marker=Join-Path $DataRoot 'FuyinAdapter.json'
 if(-not (Test-Path -LiteralPath $marker)){throw '没有找到由浮音安装的组件记录。'}
 $owned=Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
 $expected=@((Join-Path $ProgramRoot 'msimg32.dll'),(Join-Path $DataRoot 'plugins\InfLink-rs.plugin'))
 foreach($item in $owned){
  if($item.Path -notin $expected){throw '安装记录的路径不匹配，未执行卸载。'}
  if($item.Owned -and (Test-Path -LiteralPath $item.Path) -and (Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash -ne $item.Hash){throw ('组件已被其他版本替换，未删除：'+$item.Path)}
 }
 foreach($item in $owned){if($item.Owned -and (Test-Path -LiteralPath $item.Path)){[IO.File]::Delete($item.Path)}}
 if($owned[0].ProfileChanged -and [Environment]::GetEnvironmentVariable('BETTERNCM_PROFILE','User') -eq $DataRoot){[Environment]::SetEnvironmentVariable('BETTERNCM_PROFILE',$owned[0].PreviousProfile,'User');Send-FuyinEnvironmentChanged}
 [IO.File]::Delete($marker)
}
if($Install -or $Uninstall){
 Add-Type -AssemblyName PresentationFramework
 try{
  if($Install){$null=Install-FuyinNeteaseAdapter $ProgramRoot $DataRoot $StageRoot -ConfigureUserProfile;[Windows.MessageBox]::Show('组件已安装。请从网易云托盘菜单完全退出，再重新打开网易云。','浮音 · 播放器适配') | Out-Null}
  else{Uninstall-FuyinNeteaseAdapter $ProgramRoot $DataRoot;[Windows.MessageBox]::Show('浮音安装的组件已移除。请重新打开网易云。','浮音 · 播放器适配') | Out-Null}
 }catch{[Windows.MessageBox]::Show($_.Exception.Message,'浮音 · 适配未完成') | Out-Null;exit 1}
}
