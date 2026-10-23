function Get-LumaProviderIdentity($Genres){
 foreach($genre in $Genres){
  if([string]$genre -match '^NCM-([0-9]{1,20})$'){return @{Provider='Netease';Id=$matches[1]}}
  if([string]$genre -match '^QQ-([A-Za-z0-9]{1,40})$'){return @{Provider='QQMusic';Id=$matches[1]}}
 }
 return $null
}
