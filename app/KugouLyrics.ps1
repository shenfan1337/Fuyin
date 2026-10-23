# KRC lyric provider. Text-only decoding lives in KrcReader.cs.
function Read-LumaLyricJson($Client,[string]$Url){
 $r=$Client.GetAsync($Url).GetAwaiter().GetResult()
 try{if($r.IsSuccessStatusCode){return ($r.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json)}}finally{$r.Dispose()}
}
function ConvertFrom-LumaKrc([string]$Content){
 if(-not ('KrcReader' -as [type])){Add-Type -Path "$PSScriptRoot\KrcReader.cs"}
 $text=[KrcReader]::Read($Content)
 $lines=foreach($line in ($text -split "`r?`n")){
  $h=[regex]::Match($line,'^\[(\d+),(\d+)\]');if(-not $h.Success){continue}
  $start=[long]$h.Groups[1].Value;$s=$h.Value
  foreach($m in [regex]::Matches($line.Substring($h.Length),'<(\d+),(\d+),\d+>(.*?)(?=<\d+,\d+,\d+>|$)')){$s+='('+($start+[long]$m.Groups[1].Value)+','+$m.Groups[2].Value+',0)'+$m.Groups[3].Value}
  $s
 }
 return ConvertFrom-Yrc ($lines -join "`n")
}
function Merge-LumaWordTiming($Reference,$Precise){
 # Preserve line anchors. Match repeated choruses by both text and time.
 $lastEnd=($Precise | Measure-Object End -Maximum).Maximum
 $eligible=@($Reference | Where-Object {$_.Time -gt 10 -and $_.Time -le $lastEnd+2 -and (Get-LyricNameKey $_.Text).Length -ge 3})
 if($eligible.Count -lt 5){return $null}
 $pairs=@(foreach($row in $eligible){
  $key=Get-LyricNameKey $row.Text
  $options=@(foreach($line in $Precise){
   if([Math]::Abs($line.Time-$row.Time) -gt 15){continue}
   $lineKey=Get-LyricNameKey $line.Text
   if($lineKey -eq $key){$line;continue}
   # A provider may join two player lines. Split only at real word boundaries.
   $at=$lineKey.IndexOf($key,[StringComparison]::Ordinal)
   if($at -lt 0){continue}
   $position=0;$selected=New-Object 'System.Collections.Generic.List[object]'
   foreach($w in $line.Words){
    $length=(Get-LyricNameKey $w.Text).Length
    if($position -ge $at -and $position+$length -le $at+$key.Length){$selected.Add($w)}
    $position+=$length
   }
   if($selected.Count -and (Get-LyricNameKey (($selected | ForEach-Object {$_.Text}) -join '')) -eq $key){[pscustomobject]@{Time=$selected[0].Time;End=$selected[$selected.Count-1].End;Words=@($selected.ToArray());Text=$row.Text}}
  })
  $match=$options | Where-Object {[Math]::Abs($_.Time-$row.Time) -le 3} | Sort-Object @{Expression={[Math]::Abs($_.Time-$row.Time)}} | Select-Object -First 1
  if($match){[pscustomobject]@{Row=$row;Match=$match}}
 })
 if($pairs.Count -lt 5 -or $pairs.Count -lt $eligible.Count*.8){return $null}
 $byTime=@{};$previous=-1.0
 for($i=0;$i -lt $pairs.Count;$i++){
  $p=$pairs[$i];if($p.Match.Time -le $previous){return $null};$previous=$p.Match.Time
  $scale=1.0
  if($i+1 -lt $pairs.Count){$span=$pairs[$i+1].Match.Time-$p.Match.Time;if($span -gt 0){$scale=($pairs[$i+1].Row.Time-$p.Row.Time)/$span}}
  if($scale -lt .8 -or $scale -gt 1.2){continue}
  $original=$p.Row.Text;$cursor=0;$tokens=New-Object 'System.Collections.Generic.List[string]'
  foreach($w in $p.Match.Words){
   $count=(Get-LyricNameKey $w.Text).Length;$begin=$cursor
   while($cursor -lt $original.Length -and (Get-LyricNameKey $original.Substring($begin,$cursor-$begin)).Length -lt $count){$cursor++}
   while($cursor -lt $original.Length -and (Get-LyricNameKey $original.Substring($cursor,1)).Length -eq 0){$cursor++}
   $part=$original.Substring($begin,$cursor-$begin)
   $time=[long][Math]::Round(($p.Row.Time+($w.Time-$p.Match.Time)*$scale)*1000)
   $duration=[long][Math]::Round(($w.End-$w.Time)*$scale*1000)
   $tokens.Add(('('+ $time+','+$duration+',0)'+$part))
  }
  if($cursor -ne $original.Length){return $null}
  $byTime[[string]$p.Row.Time]='['+([long][Math]::Round($p.Row.Time*1000))+','+([long][Math]::Round(($p.Match.End-$p.Match.Time)*$scale*1000))+']'+($tokens -join '')
 }
 if($byTime.Count -lt $eligible.Count*.8){return $null}
 $output=foreach($row in $Reference){
  if($byTime.ContainsKey([string]$row.Time)){$byTime[[string]$row.Time]}else{
   $minutes=[Math]::Floor($row.Time/60);$seconds=$row.Time-$minutes*60
   '['+$minutes.ToString('00')+':'+$seconds.ToString('00.000',[Globalization.CultureInfo]::InvariantCulture)+']'+$row.Text
  }
 }
 return $output -join "`n"
}
function Get-LumaKugouWords($Client,[string]$Title,[string]$Artist,[double]$Duration,$Reference){
 if($Duration -le 0 -or -not $Title -or -not $Artist){return $null}
 $query=[Uri]::EscapeDataString((ConvertTo-LyricSimplified $Title)+' '+$Artist)
 $data=Read-LumaLyricJson $Client ('https://mobileservice.kugou.com/api/v3/search/song?format=json&keyword='+$query+'&page=1&pagesize=20')
 $candidates=@(foreach($s in $data.data.info){[pscustomobject]@{trackName=$s.songname;artistName=$s.singername;duration=[double]$s.duration;syncedLyrics='candidate';Hash=$s.hash}})
 $song=Select-LumaLyricCandidate $candidates $Title $Artist $Duration
 if(-not $song -or $song.Hash -notmatch '^[a-fA-F0-9]{32}$'){return $null}
 $lyrics=Read-LumaLyricJson $Client ('https://lyrics.kugou.com/search?ver=1&man=yes&client=pc&keyword='+[Uri]::EscapeDataString($Title)+'&duration='+([long]($song.duration*1000))+'&hash='+$song.Hash)
 foreach($c in @($lyrics.candidates | Sort-Object score -Descending | Select-Object -First 2)){
  $singers=@(Get-ArtistKeys $c.singer)
  if(-not @((Get-ArtistKeys $Artist) | Where-Object {$singers -contains $_}).Count){continue}
  if($c.id -notmatch '^\d+$' -or $c.accesskey -notmatch '^[a-fA-F0-9]+$' -or [Math]::Abs([double]$c.duration/1000-$song.duration) -gt 1){continue}
  $d=Read-LumaLyricJson $Client ('https://lyrics.kugou.com/download?ver=1&client=pc&id='+$c.id+'&accesskey='+$c.accesskey+'&fmt=krc&charset=utf8')
  if($d.content){$precise=@(ConvertFrom-LumaKrc $d.content);$merged=Merge-LumaWordTiming $Reference $precise;if($merged){return $merged}}
 }
 return $null
}
function Update-LumaCachedWords($Client,$Result,[string]$Title,[string]$Artist,[double]$Duration,[string]$CachePath,[scriptblock]$OnReady){
 if($OnReady -and $Result.Rows.Count){& $OnReady $Result}
 if(-not $Result.Rows.Count -or ($Result.Rows | Where-Object {$_.Words.Count -gt 1 -or $_.Text -match '<\d+:\d{2}'} | Select-Object -First 1)){return}
 $marker=$CachePath+'.krc-check'
 if((Test-Path -LiteralPath $marker) -and ([DateTime]::UtcNow-(Get-Item -LiteralPath $marker).LastWriteTimeUtc).TotalMinutes -lt 15){return}
 try{
  $raw=Get-LumaKugouWords $Client $Title $Artist $Duration $Result.Rows
  if($raw){$rows=@(ConvertFrom-Lrc $raw);if($rows.Count){[IO.File]::WriteAllText($CachePath,$raw);$Result.Rows=$rows;$Result.Status='同步歌词已就绪'}}
 }catch{}finally{try{[IO.File]::WriteAllText($marker,[DateTime]::UtcNow.ToString('o'))}catch{}}
}
