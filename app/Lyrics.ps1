function ConvertFrom-Yrc([string]$Text) {
 $rows=New-Object 'System.Collections.Generic.List[object]'
 foreach($line in ($Text -split "`r?`n")){
  $header=[regex]::Match($line,'^\s*\[(\d+),(\d+)\]')
  if(-not $header.Success){
   # Precision upgrades may retain unmatched LRC lines and explicit blank rests.
   if($line -match '^\s*\[\d+:\d{2}') {foreach($plainRow in @(ConvertFrom-Lrc $line)){$rows.Add($plainRow)}}
   continue
  }
  $tokens=[regex]::Matches($line.Substring($header.Length),'\((\d+),(\d+),\d+\)(.*?)(?=\(\d+,\d+,\d+\)|$)')
  $words=New-Object 'System.Collections.Generic.List[object]';$previous=-1.0;$valid=$true
  foreach($token in $tokens){
   $start=[double]$token.Groups[1].Value/1000;$end=$start+[double]$token.Groups[2].Value/1000
   if($start -lt $previous){$valid=$false;break}
   $previous=$start
   $words.Add([pscustomobject]@{Text=$token.Groups[3].Value;Time=$start;End=$end})
  }
  if(-not $valid -or -not $words.Count){continue}
  $plain=($words | ForEach-Object {$_.Text}) -join ''
  if(-not $plain.Trim()){continue}
  # Some provider line durations are incorrect. Use individual word endpoints.
  $end=($words | Measure-Object End -Maximum).Maximum
  $rows.Add([pscustomobject]@{Time=[Math]::Min([double]$header.Groups[1].Value/1000,$words[0].Time);Text=$plain;Offset=0.0;Words=@($words.ToArray());End=[double]$end})
 }
 return @($rows.ToArray() | Sort-Object Time)
}
function ConvertFrom-Lrc([string]$Text) {
    if($Text -match '(?m)^\s*\[\d+,\d+\]\s*\(\d+,\d+,\d+\)'){
        return ConvertFrom-Yrc $Text
    }
    $rows = New-Object System.Collections.Generic.List[object]
    $offset = 0.0
    $om = [regex]::Match($Text, '\[offset:([+-]?\d+)\]', 'IgnoreCase')
    if ($om.Success) { $offset = [double]$om.Groups[1].Value / 1000 }
    foreach ($line in ($Text -split "`r?`n")) {
        $tags = [regex]::Matches($line, '\[(\d+):(\d{2})(?:[.:](\d{1,3}))?\]')
        $words = [regex]::Replace($line, '\[[^\]]*\]', '').Trim()
        foreach ($tag in $tags) {
            $fraction = 0.0
            if ($tag.Groups[3].Success) { $fraction = [double]::Parse('0.' + $tag.Groups[3].Value, [Globalization.CultureInfo]::InvariantCulture) }
            $rows.Add([pscustomobject]@{ Time = ([int]$tag.Groups[1].Value * 60 + [int]$tag.Groups[2].Value + $fraction - $offset); Text = $words; Offset=$offset })
        }
    }
    $unique=New-Object 'System.Collections.Generic.List[object]'
    foreach($group in ($rows | Group-Object Time | Sort-Object {[double]$_.Name})){
        $items=@($group.Group | Where-Object {$_.Text})
        if(-not $items.Count){$items=@($group.Group)}
        $unique.Add($items[0])
    }
    return @($unique.ToArray())
}
function Read-LrcFile([string]$Path){
 $bytes=[IO.File]::ReadAllBytes($Path)
 if($bytes.Length -ge 2 -and (($bytes[0] -eq 255 -and $bytes[1] -eq 254) -or ($bytes[0] -eq 254 -and $bytes[1] -eq 255))){return [IO.File]::ReadAllText($Path)}
 try{return [Text.UTF8Encoding]::new($false,$true).GetString($bytes).TrimStart([char]0xFEFF)}catch{return [Text.Encoding]::GetEncoding(54936).GetString($bytes)}
}
function Get-LyricIndex($Rows, [double]$Seconds) {
    $lo=0; $hi=$Rows.Count-1; $found=-1
    while ($lo -le $hi) { $mid=[int][Math]::Floor(($lo+$hi)/2); if ($Rows[$mid].Time -le $Seconds) { $found=$mid; $lo=$mid+1 } else { $hi=$mid-1 } }
    return $found
}
