function ConvertTo-KaraokeWords($Row,[double]$End) {
 if($Row.Words -and $Row.Words.Count){return @{Words=@($Row.Words);Exact=$true}}
 $raw=$Row.Text;$estimated=$false
 $matches=[regex]::Matches($raw,'<(\d+):(\d{2})(?:\.(\d{1,3}))?>([^<]*)')
 $exact=$matches.Count -gt 0
 $words=New-Object 'System.Collections.Generic.List[object]'
 if($matches.Count){
  foreach($m in $matches){
   $fraction=0.0; if($m.Groups[3].Success){$fraction=[double]::Parse('0.'+$m.Groups[3].Value,[Globalization.CultureInfo]::InvariantCulture)}
   $words.Add([pscustomobject]@{Text=$m.Groups[4].Value;Time=([int]$m.Groups[1].Value*60+[int]$m.Groups[2].Value+$fraction-$Row.Offset)})
  }
 } else {
  # English line-only lyrics keep separate words, but expose their estimated
  # timing explicitly. Real YRC/enhanced LRC always takes precedence above.
  $tokens=[regex]::Matches($raw,'\S+\s*')
  if($tokens.Count -gt 1 -and $raw -match '[A-Za-z]' -and $raw -notmatch '[\p{IsCJKUnifiedIdeographs}]'){
   $weights=@(foreach($token in $tokens){[double][Math]::Max(1,[Math]::Min(4,[regex]::Matches($token.Value,'[aeiouy]+','IgnoreCase').Count))})
   $total=($weights | Measure-Object -Sum).Sum;$cursor=[double]$Row.Time
   $span=[Math]::Max(.001,$End-$cursor)
   for($i=0;$i -lt $tokens.Count;$i++){
    $next=if($i -eq $tokens.Count-1){$End}else{$cursor+$span*$weights[$i]/$total}
    $words.Add([pscustomobject]@{Text=$tokens[$i].Value;Time=$cursor;End=$next});$cursor=$next
   }
   $estimated=$true
  }else{$words.Add([pscustomobject]@{Text=$raw;Time=[double]$Row.Time;End=$End})}
 }
 return @{Words=@($words.ToArray());Exact=$exact;Estimated=$estimated}
}
function ConvertTo-EstimatedKaraokeWords($Row,[double]$End,[double]$Cadence=0){
 $text=Get-PlainLyric $Row.Text
 $parts=[regex]::Matches($text,"[\p{IsCJKUnifiedIdeographs}]|[\p{L}\p{M}\p{N}-[\p{IsCJKUnifiedIdeographs}]]+(?:['’\-][\p{L}\p{M}\p{N}-[\p{IsCJKUnifiedIdeographs}]]+)*|[^\p{L}\p{M}\p{N}]+")
 $units=New-Object 'System.Collections.Generic.List[object]';$prefix=''
 foreach($part in $parts){
  if($part.Value -notmatch '[\p{L}\p{N}]'){
   if($units.Count){$units[$units.Count-1].Text+=$part.Value;if($part.Value -match '[,，、;；:：]'){$units[$units.Count-1].Weight+=.2}}
   else{$prefix+=$part.Value}
   continue
  }
  $weight=if($part.Value -match '[\p{IsCJKUnifiedIdeographs}]'){1.0}else{[double][Math]::Max(1,[Math]::Min(4,[regex]::Matches($part.Value,'[aeiouy]+','IgnoreCase').Count))}
  $units.Add([pscustomobject]@{Text=$prefix+$part.Value;Weight=$weight});$prefix=''
 }
 if(-not $units.Count){$units.Add([pscustomobject]@{Text=$text;Weight=1.0})}
 # Each line is anchored independently. A modest final-word weight leaves room
 # for a held ending without delaying every earlier word in a sparse LRC line.
 $span=[Math]::Max(.001,$End-[double]$Row.Time)
 if($units.Count -gt 1 -and $span/$units.Count -gt .4){$units[$units.Count-1].Weight*=1.3}
 $total=($units | Measure-Object Weight -Sum).Sum;$cursor=[double]$Row.Time
 $step=$span/$total
 if($Cadence -gt 0 -and $units.Count -gt 1 -and $span -gt $Cadence*$total*1.25){
  $earlierWeight=$total-$units[$units.Count-1].Weight
  $step=[Math]::Min($Cadence,$span*.85/[Math]::Max(.01,$earlierWeight))
 }
 $words=New-Object 'System.Collections.Generic.List[object]'
 for($i=0;$i -lt $units.Count;$i++){
  $next=if($i -eq $units.Count-1){[Math]::Max($cursor,$End)}else{$cursor+$step*$units[$i].Weight}
  $words.Add([pscustomobject]@{Text=$units[$i].Text;Time=$cursor;End=$next;Weight=$units[$i].Weight});$cursor=$next
 }
 return @($words.ToArray())
}
function Get-LumaPredictionCadence($Rows,[int]$Index,[double]$Duration){
 $samples=New-Object 'System.Collections.Generic.List[double]'
 for($i=[Math]::Max(0,$Index-4);$i -le [Math]::Min($Rows.Count-1,$Index+4);$i++){
  if($i -eq $Index -or -not $Rows[$i].Text -or $Rows[$i].Text -match '作词|作曲|编曲|制作人|混音|母带|录音|键盘|吉他|贝斯|\b[OS]P\s*[:：]'){continue}
  $end=if($i+1 -lt $Rows.Count){[double]$Rows[$i+1].Time}else{$Duration}
  $span=$end-[double]$Rows[$i].Time
  if($span -lt .5 -or $span -gt 12){continue}
  $units=@(ConvertTo-EstimatedKaraokeWords $Rows[$i] ($Rows[$i].Time+.1))
  if($units.Count -lt 4){continue}
  $weight=($units | Measure-Object Weight -Sum).Sum
  $samples.Add($span/[Math]::Max(1,$weight))
 }
 if($samples.Count -lt 3){return 0.0}
 $sorted=@($samples | Sort-Object)
 return [Math]::Max(.06,[Math]::Min(.8,$sorted[[int][Math]::Floor(($sorted.Count-1)/2)]))
}
function Get-LumaKaraokeData($Row,[double]$End,[string]$Mode,[double]$Cadence=0){
 if($Mode -in @('Line','White')){
  return @{Words=@([pscustomobject]@{Text=(Get-PlainLyric $Row.Text);Time=[double]$Row.Time;End=$End});Exact=$false;Estimated=$false;Unavailable=$false}
 }
 $data=ConvertTo-KaraokeWords $Row $End
 if($data.Exact){$data.Unavailable=$false;return $data}
 return @{Words=@(ConvertTo-EstimatedKaraokeWords $Row $End $Cadence);Exact=$false;Estimated=$true;Unavailable=$false}
}
function Get-LumaLyricAccent([string]$Choice,[string]$Theme,[string]$Default){
 $colors=@{
  Mint=@('#087D69','#7DE3BE');Blue=@('#235DCA','#8DBBFF');Violet=@('#7943B5','#CFABFF')
  Rose=@('#AF3766','#FFACCA');Amber=@('#966000','#FFD27B')
 }
 if(-not $colors.ContainsKey($Choice)){return $Default}
 return $colors[$Choice][[int]($Theme -eq 'Night')]
}
function Get-KaraokeFrame($Words,[double]$Position){
 $active=-1;$completed=0
 for($i=0;$i -lt $Words.Count;$i++){
  if($Position -lt $Words[$i].Time){continue}
  $end=if($null -ne $Words[$i].End){[double]$Words[$i].End}elseif($i+1 -lt $Words.Count){[double]$Words[$i+1].Time}else{[double]::PositiveInfinity}
  if($Position -lt $end){$active=$i}else{$completed=$i+1}
 }
 return @{Active=$active;Completed=$completed}
}
function Get-KaraokePrediction($Words,[double]$Position,[double]$End){
 $result=@{Index=-1;Amount=0.0;Lead=0.0}
 for($i=0;$i -lt $Words.Count;$i++){
  $start=[double]$Words[$i].Time
  if($start -le $Position){continue}
  if($start -ge $End){return $result}
  if(-not ([string]$Words[$i].Text).Trim()){return $result}
  $stop=if($null -ne $Words[$i].End){[double]$Words[$i].End}elseif($i+1 -lt $Words.Count){[double]$Words[$i+1].Time}else{$End}
  $span=[Math]::Max(0.0,$stop-$start)
  if($i -gt 0){
   $previous=$Words[$i-1]
   $previousEnd=if($null -ne $previous.End){[double]$previous.End}else{$start}
   # Never predict across a rest, overlap, or a provider's blank pause token.
   if($start-$previousEnd -gt .12 -or $previousEnd-$start -gt .001 -or -not ([string]$previous.Text).Trim()){return $result}
   $span=[Math]::Min($span,[Math]::Max(0.0,$start-[double]$previous.Time))
  }
  $lead=[Math]::Min(.045,$span*.18)
  if($lead -gt 0 -and $Position -ge $start-$lead){
   $p=[Math]::Max(0.0,[Math]::Min(1.0,($Position-($start-$lead))/$lead))
   $result=@{Index=$i;Amount=(.45*$p*$p*(3-2*$p));Lead=$lead}
  }
  return $result
 }
 return $result
}
function Get-PlainLyric([string]$Text){return [regex]::Replace($Text,'<\d+:\d{2}(?:\.\d{1,3})?>','')}
function Get-KaraokeFadeMilliseconds($Words,[int]$Active,[double]$End){
 if($Active -lt 0 -or $Active -ge $Words.Count){return 100.0}
 $next=if($Active+1 -lt $Words.Count){[double]$Words[$Active+1].Time}else{$End}
 # Finish the transition within this syllable, even in a fast rap passage.
 if($null -ne $Words[$Active].End){$next=[Math]::Min($next,[double]$Words[$Active].End)}
 return [Math]::Max(16.0,[Math]::Min(60.0,($next-[double]$Words[$Active].Time)*250.0))
}
