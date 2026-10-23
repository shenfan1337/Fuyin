function Get-LumaChineseLyrics($Client,[string]$Title,[string]$Artist,[double]$Duration){
 # Public metadata/lyric endpoints only; no account cookies or audio downloads.
 $query=(ConvertTo-LyricSimplified $Title)+' '+((Get-ArtistKeys $Artist) -join ' ')
 $url='https://music.163.com/api/search/get/web?s='+[Uri]::EscapeDataString($query)+'&type=1&offset=0&limit=12'
 $response=$Client.GetAsync($url).GetAwaiter().GetResult()
 try{
  if(-not $response.IsSuccessStatusCode){return $null}
  $data=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
 }finally{$response.Dispose()}
 $candidates=@(foreach($song in $data.result.songs){
  [pscustomobject]@{trackName=$song.name;artistName=($song.artists.name -join ',');duration=([double]$song.duration/1000);syncedLyrics='candidate';SongId=$song.id}
 })
 $match=Select-LumaLyricCandidate $candidates $Title $Artist $Duration
 if(-not $match){return $null}
 return Get-LumaNeteaseLyricsById $Client ([string]$match.SongId)
}
function Get-LumaNeteaseLyricsById($Client,[string]$Id){
 if($Id -notmatch '^\d{1,20}$'){return $null}
 $response=$Client.GetAsync(('https://music.163.com/api/song/lyric?id='+$Id+'&lv=-1&kv=-1&tv=-1&yv=-1')).GetAwaiter().GetResult()
 try{
  if(-not $response.IsSuccessStatusCode){return $null}
  $data=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
  if($data.yrc.lyric){
   $precise=@(ConvertFrom-Yrc $data.yrc.lyric)
   if($precise.Count -and ($precise | Where-Object {$_.Words.Count -gt 1} | Select-Object -First 1)){return [string]$data.yrc.lyric}
  }
  if($data.lrc.lyric -and @(ConvertFrom-Lrc $data.lrc.lyric).Count){return [string]$data.lrc.lyric}
 }finally{$response.Dispose()}
 return $null
}
