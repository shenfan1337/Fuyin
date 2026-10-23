function Get-LyricRetryDelay([int]$Attempt){
 $delays=@(5,15,30,60,120)
 return $delays[[Math]::Max(0,[Math]::Min($Attempt-1,$delays.Count-1))]
}
. "$PSScriptRoot\LyricMatching.ps1"
. "$PSScriptRoot\ChineseLyrics.ps1"
. "$PSScriptRoot\QQMusicLyrics.ps1"
. "$PSScriptRoot\KugouLyrics.ps1"
function Request-LumaLyrics($Client,[string]$Title,[string]$Artist,[string]$Album,[double]$Duration,[string]$CachePath,[int]$Attempt,$ProviderIdentity,[scriptblock]$OnReady) {
 $result=@{Rows=@();Status='等待歌曲信息补齐 · 自动重试';Instrumental=$false}
 if(Test-Path -LiteralPath $CachePath){
  try{$result.Rows=@(ConvertFrom-Lrc (Read-LrcFile $CachePath))}catch{}
  if($result.Rows.Count){
   $result.Status='同步歌词已就绪'
   $precise=$result.Rows | Where-Object {$_.Words.Count -gt 1 -or $_.Text -match '<\d+:\d{2}'} | Select-Object -First 1
   $checkPath=$CachePath+'.word-check'
   $recent=(Test-Path -LiteralPath $checkPath) -and ([DateTime]::UtcNow-(Get-Item -LiteralPath $checkPath).LastWriteTimeUtc).TotalMinutes -lt 15
   $canUpgrade=$ProviderIdentity.Provider -eq 'Netease' -or (($Title+$Artist) -match '[A-Za-z]' -and ($Title+$Artist) -notmatch '[\p{IsCJKUnifiedIdeographs}]')
   if(-not $precise -and -not $recent -and $Title -and $Artist -and $canUpgrade){
    try{
     $upgrade=if($ProviderIdentity.Provider -eq 'Netease'){Get-LumaNeteaseLyricsById $Client $ProviderIdentity.Id}else{Get-LumaChineseLyrics $Client $Title $Artist $Duration}
     $upgraded=@(ConvertFrom-Lrc $upgrade)
     if($upgraded | Where-Object {$_.Words.Count -gt 1 -or $_.Text -match '<\d+:\d{2}'} | Select-Object -First 1){
      [IO.File]::WriteAllText($CachePath,$upgrade);$result.Rows=$upgraded;$result.Status='已升级为真实逐词歌词'
     }
    }catch{} # Keep usable cached lyrics even if the precision lookup fails.
    try{[IO.File]::WriteAllText($checkPath,[DateTime]::UtcNow.ToString('o'))}catch{}
   }
   Update-LumaCachedWords $Client $result $Title $Artist $Duration $CachePath $OnReady
   return $result
  }
 }
 if($ProviderIdentity){
  try{
   $exact=if($ProviderIdentity.Provider -eq 'Netease'){Get-LumaNeteaseLyricsById $Client $ProviderIdentity.Id}elseif($ProviderIdentity.Provider -eq 'QQMusic'){Get-LumaQqLyricsById $Client $ProviderIdentity.Id}
   if($exact){$result.Rows=@(ConvertFrom-Lrc $exact);[IO.File]::WriteAllText($CachePath,$exact);[IO.File]::WriteAllText(($CachePath+'.word-check'),[DateTime]::UtcNow.ToString('o'));$result.Status='同步歌词已就绪（播放器歌曲 ID）';Update-LumaCachedWords $Client $result $Title $Artist $Duration $CachePath $OnReady;return $result}
  }catch{}
 }
 if(-not $Title -or -not $Artist){return $result}
 # This catalog also has precise English words. Do not gate it on CJK metadata.
 # Keep strict singer/version/duration checks for every language.
 try{
  $catalog=Get-LumaChineseLyrics $Client $Title $Artist $Duration
  if($catalog){$result.Rows=@(ConvertFrom-Lrc $catalog);[IO.File]::WriteAllText($CachePath,$catalog);$result.Status='同步歌词已就绪（网易云歌词）';Update-LumaCachedWords $Client $result $Title $Artist $Duration $CachePath $OnReady;return $result}
 }catch{}
 if(($Title+$Artist) -match '[\p{IsCJKUnifiedIdeographs}]'){
  try{
   $qq=Get-LumaQqLyrics $Client $Title $Artist $Duration
   if($qq){$result.Rows=@(ConvertFrom-Lrc $qq);[IO.File]::WriteAllText($CachePath,$qq);$result.Status='同步歌词已就绪（QQ 音乐歌词）';Update-LumaCachedWords $Client $result $Title $Artist $Duration $CachePath $OnReady;return $result}
  }catch{}
 }
 $url='https://lrclib.net/api/get?track_name='+[Uri]::EscapeDataString($Title)+'&artist_name='+[Uri]::EscapeDataString($Artist)
 # Album metadata is sometimes incomplete or differs from the lyric provider.
 # On subsequent attempts, keep title/artist/duration while relaxing album only.
 if($Album -and $Attempt -le 1){$url+='&album_name='+[Uri]::EscapeDataString($Album)}
 if($Duration -gt 0){$url+='&duration='+[Math]::Round($Duration)}
 try {
  $response=$Client.GetAsync($url).GetAwaiter().GetResult()
  try {
   if($response.IsSuccessStatusCode){
    $data=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
    if($data.syncedLyrics){
     $result.Rows=@(ConvertFrom-Lrc $data.syncedLyrics)
     if($result.Rows.Count){[IO.File]::WriteAllText($CachePath,$data.syncedLyrics); $result.Status='同步歌词已就绪'}
     else{$result.Status='歌词时间标签无效 · 自动重试'}
    }elseif($data.instrumental){$result.Status='纯音乐 · 享受此刻'; $result.Instrumental=$true}
    else{$result.Status='暂无同步歌词 · 将自动重试，也可导入 LRC'}
   }elseif([int]$response.StatusCode -eq 404){$result.Status='暂未匹配到歌词 · 自动重试'}
   else{$result.Status='歌词服务暂不可用 · 自动重试'}
  }finally{$response.Dispose()}
 }catch{$result.Status='网络连接失败 · 自动重试'}
 if(-not $result.Rows.Count -and -not $result.Instrumental -and $result.Status -notmatch '网络连接失败|服务暂不可用'){
  try{
   $candidate=Get-LumaSearchFallback $Client $Title $Artist $Duration
   if($candidate){
    $result.Rows=@(ConvertFrom-Lrc $candidate.syncedLyrics)
    if($result.Rows.Count){[IO.File]::WriteAllText($CachePath,$candidate.syncedLyrics); $result.Status='同步歌词已就绪（搜索匹配）'}
   }
  }catch{$result.Status='歌词搜索暂不可用 · 自动重试'}
 }
 Update-LumaCachedWords $Client $result $Title $Artist $Duration $CachePath $OnReady
 return $result
}
