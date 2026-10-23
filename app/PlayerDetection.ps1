function Get-LumaPlayerKind([string]$Source){
 if($Source -match 'spotify'){return 'spotify'}
 if($Source -match 'cloudmusic|netease|inflink'){return 'cloudmusic'}
 if($Source -match 'qqmusic'){return 'qqmusic'}
 return ''
}
function ConvertFrom-LumaWindowTitle([string]$Text){
 $text=$Text -replace '\s*[-|]\s*(网易云音乐|QQ音乐|QQ Music)\s*$',''
 if($text -match '^(.+?)\s+-\s+(.+)$'){
  return @{Title=$matches[1].Trim();Artist=$matches[2].Trim()}
 }
 return @{Title='';Artist=''}
}
function Get-LumaLocalPlayers($Processes,$Audio,[long]$Tick){
 return @(foreach($kind in @('spotify','cloudmusic','qqmusic')){
  $group=@($Processes | Where-Object {$_.ProcessName -ieq $kind})
  if(-not $group.Count){continue}
  $sessions=@($Audio | Where-Object {$group.Id -contains $_.Pid})
  $state=if(@($sessions | Where-Object {$_.State -eq 1}).Count){1}elseif(@($sessions | Where-Object {$_.State -eq 0}).Count){0}else{-1}
  $title=($group | Where-Object {$_.MainWindowTitle} | Select-Object -First 1).MainWindowTitle
  $metadata=ConvertFrom-LumaWindowTitle $title
  $peaks=@($sessions | Where-Object {$null -ne $_.Peak -and $_.Peak -ge 0})
  $peak=if($peaks.Count){[double]($peaks.Peak | Measure-Object -Maximum).Maximum}else{-1.0}
  @{Kind=$kind;Source=('native:'+$kind);AudioState=$state;Peak=$peak;Title=$metadata.Title;Artist=$metadata.Artist;Tick=$Tick}
 })
}
function Select-LumaActivePlayer($Players,[string]$Previous){
 $active=@($Players | Where-Object {$_.AudioState -eq 1})
 $same=$active | Where-Object {$_.Kind -eq (Get-LumaPlayerKind $Previous)} | Select-Object -First 1
 if($same){return $same}
 return $active | Select-Object -First 1
}
