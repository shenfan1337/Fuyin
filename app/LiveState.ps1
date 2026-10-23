function Get-LumaLiveSnapshot($Snapshot,$Transport,[long]$Now,[double]$Frequency){
 if(-not $Snapshot){return $null}
 $result=$Snapshot.Clone()
 $fresh=$Transport -and $Transport.Source -eq $Snapshot.Source -and $Transport.Key -eq $Snapshot.Key -and ($Now-$Transport.Tick)/$Frequency -le 1.0
 if($fresh){
  foreach($name in @('Playing','Position','Rate','SeekSerial','Tick','LocalAudio')){$result[$name]=$Transport[$name]}
  if($Transport.ContainsKey('TimelineUnavailable')){$result.TimelineUnavailable=$Transport.TimelineUnavailable}
  $result.TransportFresh=$true
 }else{
  $age=if($Snapshot.Tick){[Math]::Max(0.0,($Now-$Snapshot.Tick)/$Frequency)}else{0.0}
  if($Snapshot.Playing){$result.Position=[double]$Snapshot.Position+[Math]::Min(1.0,$age)*[double]$Snapshot.Rate}
  $result.Playing=$false; $result.Tick=$Now; $result.TransportFresh=$false
 }
 return $result
}
