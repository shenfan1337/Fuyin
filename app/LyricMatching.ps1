Add-Type -AssemblyName Microsoft.VisualBasic
function ConvertTo-LyricSimplified([string]$Text){
 try{return [Microsoft.VisualBasic.Strings]::StrConv($Text,[Microsoft.VisualBasic.VbStrConv]::SimplifiedChinese,2052)}catch{return $Text}
}
function Get-LyricNameKey([string]$Text){
 $text=ConvertTo-LyricSimplified $Text
 return [regex]::Replace($text.Normalize([Text.NormalizationForm]::FormKC).ToLowerInvariant(),'[\p{P}\p{Z}\s]','')
}
function Get-ArtistKeys([string]$Text){
 $aliases=@(
  @('Jay Chou','周杰伦'),@('Eason Chan','陈奕迅'),@('JJ Lin','林俊杰'),@('G.E.M.','邓紫棋'),
  @('Jolin Tsai','蔡依林'),@('Mayday','五月天'),@('Stefanie Sun','孙燕姿'),@('Hebe Tien','田馥甄'),
  @('Ronghao Li','李荣浩'),@('Li Ronghao','李荣浩'),@('Joker Xue','薛之谦'),@('Eric Chou','周兴哲'),
  @('David Tao','陶喆'),@('Leehom Wang','王力宏'),@('Khalil Fong','方大同'),@('Fish Leong','梁静茹'),
  @('Faye Wong','王菲'),@('Jacky Cheung','张学友'),@('Andy Lau','刘德华'),@('Leslie Cheung','张国荣'),
  @('Wakin Chau','周华健'),@('Sodagreen','苏打绿'),@('Elva Hsiao','萧亚轩'),@('Hsiao Elva','萧亚轩')
 )
 $keys=foreach($part in [regex]::Split($Text,'\s*(?:,|，|、|;|；|&| feat\.? | featuring | / )\s*')){
  $key=Get-LyricNameKey $part
  foreach($pair in $aliases){if($key -eq (Get-LyricNameKey $pair[0])){$key=Get-LyricNameKey $pair[1];break}}
  if($key){$key}
 }
 return @($keys | Select-Object -Unique)
}
function Select-LumaLyricCandidate($Candidates,[string]$Title,[string]$Artist,[double]$Duration){
 $titleKey=Get-LyricNameKey $Title; $artists=@(Get-ArtistKeys $Artist)
 $valid=@(foreach($candidate in $Candidates){
  if(-not $candidate.syncedLyrics){continue}
  if((Get-LyricNameKey $candidate.trackName) -ne $titleKey){continue}
  $other=@(Get-ArtistKeys $candidate.artistName)
  if(-not @($artists | Where-Object {$other -contains $_}).Count){continue}
  if($Duration -gt 0 -and ([double]$candidate.duration -le 0 -or [Math]::Abs([double]$candidate.duration-$Duration) -gt 3)){continue}
  $candidate
 })
 if($valid.Count -eq 0){return $null}
 # Without a known duration, do not guess between different recordings.
 if($Duration -le 0 -and $valid.Count -gt 1){return $null}
 return $valid | Sort-Object @{Expression={[Math]::Abs([double]$_.duration-$Duration)}} | Select-Object -First 1
}
function Get-LumaSearchFallback($Client,[string]$Title,[string]$Artist,[double]$Duration){
 $variants=@($Title,(ConvertTo-LyricSimplified $Title)) | Select-Object -Unique
 foreach($query in $variants){
  $url='https://lrclib.net/api/search?track_name='+[Uri]::EscapeDataString($query)
  $response=$Client.GetAsync($url).GetAwaiter().GetResult()
  try{
   if(-not $response.IsSuccessStatusCode){return $null}
   $candidates=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
   $match=Select-LumaLyricCandidate $candidates $Title $Artist $Duration
   if($match){return $match}
  }finally{$response.Dispose()}
 }
 return $null
}
