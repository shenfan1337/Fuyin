# Adapted from WXRIW/Lyricify-Lyrics-Helper (Apache-2.0),
# Providers/Web/QQMusic/Api.cs: Search, GetSong and GetLyric.
# Changes: ported request construction/decoding to PowerShell 5.1; strict match
# selection uses Fuyin's existing title/artist/duration validation.
function Invoke-LumaQqForm($Client,[string]$Url,$Fields){
 $map=[Collections.Generic.Dictionary[string,string]]::new()
 foreach($key in $Fields.Keys){$map.Add([string]$key,[string]$Fields[$key])}
 $request=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post,$Url)
 $request.Headers.Referrer=[Uri]'https://c.y.qq.com/'
 $request.Content=[Net.Http.FormUrlEncodedContent]::new($map)
 try{
  $response=$Client.SendAsync($request).GetAwaiter().GetResult()
  try{
   if(-not $response.IsSuccessStatusCode){return $null}
   $text=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
   # Parse a known JSONP envelope as data, never execute JavaScript.
   $text=$text -replace '^\s*[A-Za-z_$][\w.$]*\s*\(',' ' -replace '\)\s*;?\s*$',''
   return $text | ConvertFrom-Json
  }finally{$response.Dispose()}
 }finally{$request.Dispose()}
}
function Get-LumaQqLyricsById($Client,[string]$Id){
 if($Id -notmatch '^[A-Za-z0-9]{1,40}$'){return $null}
 $mid=$Id
 if($Id -match '^\d+$'){
  $song=Invoke-LumaQqForm $Client 'https://c.y.qq.com/v8/fcg-bin/fcg_play_single_song.fcg' @{songid=$Id;tpl='yqq_song_detail';format='jsonp';callback='getOneSongInfoCallback';g_tk='5381';jsonpCallback='getOneSongInfoCallback';loginUin=0;hostUin=0;outCharset='utf8';notice=0;platform='yqq';needNewCode=0}
  $mid=($song.data | Select-Object -First 1).mid
  if(-not $mid){return $null}
 }
 $data=Invoke-LumaQqForm $Client 'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg' @{songmid=$mid;callback='MusicJsonCallback_lrc';pcachetime=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();g_tk='5381';jsonpCallback='MusicJsonCallback_lrc';loginUin=0;hostUin=0;format='jsonp';inCharset='utf8';outCharset='utf8';notice=0;platform='yqq';needNewCode=0}
 if(-not $data -or $data.code -ne 0 -or -not $data.lyric){return $null}
 $lyric=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($data.lyric))
 $lyric=[Net.WebUtility]::HtmlDecode($lyric)
 if(@(ConvertFrom-Lrc $lyric).Count){return $lyric}
 return $null
}
function Get-LumaQqLyrics($Client,[string]$Title,[string]$Artist,[double]$Duration){
 $body=@{req_1=@{method='DoSearchForQQMusicDesktop';module='music.search.SearchCgiService';param=@{num_per_page='20';page_num='1';query=((ConvertTo-LyricSimplified $Title)+' '+((Get-ArtistKeys $Artist) -join ' '));search_type=0}}} | ConvertTo-Json -Depth 8 -Compress
 $request=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post,'https://u6.y.qq.com/cgi-bin/musicu.fcg')
 $request.Headers.Referrer=[Uri]'https://c.y.qq.com/'
 $request.Content=[Net.Http.StringContent]::new($body,[Text.Encoding]::UTF8,'application/json')
 try{
  $response=$Client.SendAsync($request).GetAwaiter().GetResult()
  try{
   if(-not $response.IsSuccessStatusCode){return $null}
   $result=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
  }finally{$response.Dispose()}
 }finally{$request.Dispose()}
 $candidates=@(foreach($song in $result.req_1.data.body.song.list){
  [pscustomobject]@{trackName=($song.title -replace '</?em>','');artistName=(($song.singer.name -join ',') -replace '</?em>','');duration=[double]$song.interval;syncedLyrics='candidate';Mid=$song.mid}
 })
 $match=Select-LumaLyricCandidate $candidates $Title $Artist $Duration
 if($match){return Get-LumaQqLyricsById $Client $match.Mid}
 return $null
}
