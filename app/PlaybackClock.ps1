function Resolve-PlaybackClock($State,[string]$Track,[double]$Raw,[long]$Stamp,[double]$Age,[bool]$Playing,[double]$Rate,[double]$Now,[double]$Duration) {
 if($null -eq $State -or $State.Track -ne $Track){
  $position=$Raw
  if($Playing -and $Age -ge 0 -and $Age -le 10){$position+=$Age*$Rate}
  $State=@{Track=$Track;Raw=$Raw;Stamp=$Stamp;Position=$position;At=$Now;Playing=$Playing;Rate=$Rate;Dynamic=$false;SeekSerial=0;Pending=$null;PauseRaw=$Raw;HadPause=(-not $Playing)}
 }else{
  $expected=[double]$State.Position
  if($State.Playing){$expected+=[Math]::Max(0.0,$Now-$State.At)*$State.Rate}
  $changed=[Math]::Abs($Raw-$State.Raw) -gt .02
  $stampChanged=$Stamp -ne $State.Stamp
  # Only continuously advancing positions are live positions. A delayed batch
  # update with an unchanged timestamp must not disable timestamp compensation.
  $elapsed=$Now-$State.At
  $rawStep=$Raw-$State.Raw
  $continuous=$changed -and -not $stampChanged -and $elapsed -gt 0 -and $elapsed -le 1.0 -and $rawStep -gt 0 -and [Math]::Abs($rawStep-$elapsed*$Rate) -le .08
  $newDynamic=$continuous -and -not $State.Dynamic
  if($stampChanged){$State.Dynamic=$false}
  if($newDynamic){$State.Dynamic=$true}
  $candidate=$expected
  if(-not $Playing){
   # Paused is authoritative even when Spotify publishes advancing raw positions.
   if($State.Playing){$State.PauseRaw=$Raw; $State.HadPause=$true}
   $State.Pending=$null
  }elseif(-not $State.Playing){
   # The timestamp age may contain the entire pause. Never add it on resume.
   if($Raw -lt $State.PauseRaw-1.2){$candidate=$Raw; $State.SeekSerial++}
   else{$candidate=[Math]::Max([double]$State.Position,$Raw)}
   $State.Pending=$null
  }elseif($newDynamic){
   if($Raw -lt $State.Raw-1.2){$State.Pending=@{Position=$Raw;At=$Now}}
   else{
    $candidate=if($State.HadPause){[Math]::Max($expected,$Raw)}else{$Raw}
    if([Math]::Abs($candidate-$expected) -ge 1.2){$State.SeekSerial++}
    $State.Pending=$null
   }
  }elseif($changed -or $stampChanged){
   $reported=$Raw
   if($stampChanged -and -not $State.Dynamic -and $Age -ge 0 -and $Age -le 10){$reported+=$Age*$Rate}
   if($null -ne $State.Pending -and [Math]::Abs($reported-($State.Pending.Position+($Now-$State.Pending.At)*$Rate)) -lt 1.2){
    $candidate=$reported; $State.SeekSerial++; $State.Pending=$null
   }elseif($Raw -lt $State.Raw-1.2){
    # A backwards seek requires backwards RAW movement, not an aging snapshot.
    $State.Pending=@{Position=$reported;At=$Now}
   }else{$candidate=[Math]::Max($expected,$reported); $State.Pending=$null}
  }elseif($null -ne $State.Pending){
   $candidate=$State.Pending.Position+[Math]::Max(0.0,$Now-$State.Pending.At)*$Rate
   $State.SeekSerial++; $State.Pending=$null
  }
  $State.Position=$candidate; $State.Raw=$Raw; $State.Stamp=$Stamp; $State.At=$Now; $State.Playing=$Playing; $State.Rate=$Rate
 }
 $State.Position=[Math]::Max(0.0,[double]$State.Position)
 if($Duration -gt 0){$State.Position=[Math]::Min($Duration,[double]$State.Position)}
 return $State
}
