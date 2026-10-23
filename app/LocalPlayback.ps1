function Resolve-LocalPlayback($State,[string]$Source,[bool]$MediaPlaying,[int]$AudioState,[double]$Now,[bool]$PreferMediaEdges=$false){
 if($PreferMediaEdges){
  if(-not $State -or $State.Source -ne $Source -or -not $State.ContainsKey('LastMedia')){
   $initial=$MediaPlaying -and $AudioState -ne 0
   $State=@{Source=$Source;Value=$initial;Target=$initial;Pending=-1;Since=$Now;LastMedia=$MediaPlaying;LastAudio=$AudioState}
  }
  $pauseEdge=$State.LastMedia -and -not $MediaPlaying
  $playEdge=-not $State.LastMedia -and $MediaPlaying
  $audioStart=$State.LastAudio -eq 0 -and $AudioState -eq 1
  if($AudioState -lt 0){$State.Value=$MediaPlaying;$State.Target=$MediaPlaying;$State.Pending=-1}
  elseif($pauseEdge){
   # NetEase can keep its DirectSound stream active after pausing. Latch the
   # new pause notification until a media resume or actual audio-start edge.
   $State.Value=$false;$State.Target=$false;$State.Pending=-1
  }else{
   if($AudioState -eq 0){$State.Target=$false}
   elseif($playEdge -or ($audioStart -and $MediaPlaying)){$State.Target=$true}
   if($State.Target -eq $State.Value){$State.Pending=-1}
   elseif($playEdge -and $AudioState -eq 1){$State.Value=$true;$State.Pending=-1}
   elseif($State.Pending -eq -1){$State.Pending=1;$State.Since=$Now}
   elseif($Now-$State.Since -ge .08){$State.Value=$State.Target;$State.Pending=-1}
  }
  $State.LastMedia=$MediaPlaying;$State.LastAudio=$AudioState
  return @{State=$State;Playing=[bool]$State.Value;Local=($AudioState -ge 0);Disagrees=($AudioState -ge 0 -and $State.Value -ne $MediaPlaying)}
 }
 if(-not $State -or $State.Source -ne $Source){$State=@{Source=$Source;Value=$MediaPlaying;Pending=-1;Since=$Now}}
 $local=$AudioState -ge 0
 if($local){
  $target=$AudioState -eq 1
  if($target -eq $State.Value){$State.Pending=-1}
  elseif($State.Pending -ne $AudioState){$State.Pending=$AudioState;$State.Since=$Now}
  elseif($Now-$State.Since -ge .08){$State.Value=$target;$State.Pending=-1}
 }else{$State.Value=$MediaPlaying;$State.Pending=-1}
 return @{State=$State;Playing=[bool]$State.Value;Local=$local;Disagrees=($local -and $State.Value -ne $MediaPlaying)}
}
function Resolve-NeteaseAudioPlayback($State,[string]$Source,[bool]$MediaPlaying,[int]$AudioState,[double]$Peak,[double]$Raw,[double]$Age,[double]$Now){
 if(-not $State -or $State.Source -ne $Source -or -not $State.ContainsKey('MeterMode')){
  $State=@{Source=$Source;MeterMode=$true;Value=$MediaPlaying;LastMedia=$MediaPlaying;SilenceAt=-1.0;SoundAt=$(if($Peak -gt .000001){$Now}else{-1.0});Override=$false;ResumeAt=-100.0;Raw=$Raw;MotionAt=-100.0;Fallback=$null}
 }
 if($Peak -lt 0 -or $AudioState -lt 0){
  $fallback=Resolve-LocalPlayback $State.Fallback $Source $MediaPlaying $AudioState $Now $true
  $State.Fallback=$fallback.State;$State.Value=$fallback.Playing;$State.LastMedia=$MediaPlaying
  return @{State=$State;Playing=$fallback.Playing;Local=$fallback.Local;Disagrees=$fallback.Disagrees;HoldPosition=$false;SoftResumeGap=0.0}
 }
 if($Raw-$State.Raw -gt .02 -and $Age -ge 0 -and $Age -lt .5){$State.MotionAt=$Now}
 $State.Raw=$Raw
 $pauseEdge=$State.LastMedia -and -not $MediaPlaying
 $playEdge=-not $State.LastMedia -and $MediaPlaying
 $audible=$Peak -gt .000001 -and $AudioState -eq 1
 $gap=0.0;$hold=$false
 if($audible){
  if($State.SilenceAt -ge 0){
   $silentFor=$Now-$State.SilenceAt
   if($silentFor -lt .3 -and $State.Value){$gap=$silentFor}
   if($silentFor -ge .3 -or -not $State.Value){$State.ResumeAt=$Now}
   $State.SoundAt=$Now;$State.SilenceAt=-1.0
  }
  if($pauseEdge -and -not $State.Override){$State.Value=$false;$State.SoundAt=-1.0}
  elseif($playEdge){$State.Value=$true;$State.Override=$false}
  elseif(-not $State.Value -and $State.SoundAt -ge 0 -and $Now-$State.SoundAt -ge .08){$State.Value=$true;$State.Override=$true}
  if($MediaPlaying -and $State.Override -and $Now-$State.ResumeAt -gt 12){$State.Override=$false}
 }else{
  if($State.SilenceAt -lt 0){$State.SilenceAt=$Now}
  $State.SoundAt=-1.0
  $quietStale=$Age -gt .5 -and $Now-$State.MotionAt -gt .4
  if(-not $MediaPlaying -or $AudioState -eq 0 -or ($quietStale -and $Now-$State.SilenceAt -ge .3)){
   $State.Value=$false;$State.Override=$false
  }elseif($quietStale -and $State.Value){$hold=$true}
  elseif($MediaPlaying -and $Now-$State.MotionAt -le .4){$State.Value=$true}
 }
 $State.LastMedia=$MediaPlaying
 return @{State=$State;Playing=[bool]$State.Value;Local=$true;Disagrees=($State.Value -ne $MediaPlaying);HoldPosition=$hold;SoftResumeGap=$gap}
}
function Resolve-NeteasePlaybackClock($Clock,[string]$Key,[double]$Raw,[long]$Stamp,[double]$Age,[bool]$Playing,[double]$Rate,[double]$Now,[double]$Duration){
 $same=$Clock -and $Clock.Track -eq $Key
 $sync=if($same -and $Clock.NeteaseResume){$Clock.NeteaseResume}else{@{Waiting=$false;LastRaw=$Raw;LastStamp=$Stamp;LastAt=$Now;Anchor=$null}}
 $resuming=$same -and -not $Clock.Playing -and $Playing
 if($resuming){$sync.Waiting=$true;$sync.ResumeAt=$Now;$sync.ResumeStamp=$sync.LastStamp;$sync.Anchor=$null}
 if(-not $Playing){$sync.Waiting=$false;$sync.Anchor=$null}
 $anchor=$null
 if($sync.Waiting -and $Playing){
  $elapsed=$Now-$sync.LastAt
  $dynamic=$elapsed -gt 0 -and $elapsed -le 1 -and $Stamp -eq $sync.LastStamp -and $Raw-$sync.LastRaw -gt .02 -and [Math]::Abs(($Raw-$sync.LastRaw)-$elapsed*$Rate) -le .08
  $fresh=$dynamic -or ($Stamp -ne $sync.ResumeStamp -and $Age -ge 0 -and $Age -le 1.5 -and $Age -le $Now-$sync.ResumeAt+.15)
  if($fresh){
   $candidate=$Raw+$(if($dynamic){0.0}else{$Age*$Rate})
   if($sync.Anchor -and $Now -gt $sync.Anchor.At -and [Math]::Abs($candidate-($sync.Anchor.Position+($Now-$sync.Anchor.At)*$Rate)) -le .25){
    $anchor=@{Position=$candidate;Dynamic=$dynamic};$sync.Waiting=$false;$sync.Anchor=$null
   }else{$sync.Anchor=@{Position=$candidate;At=$Now}}
  }else{$sync.Anchor=$null}
 }
 $sync.LastRaw=$Raw;$sync.LastStamp=$Stamp;$sync.LastAt=$Now
 if($same -and ($sync.Waiting -or $anchor)){
  # Pause snapshots may keep advancing. Keep the frozen origin until two fresh
  # post-resume observations agree, then allow an explicit correction both ways.
  if($resuming){$Clock.Raw=$Clock.Position;$Clock.PauseRaw=$Clock.Position}
  $next=Resolve-PlaybackClock $Clock $Key $Clock.Raw $Clock.Stamp 0 $Playing $Rate $Now $Duration
 }else{$next=Resolve-PlaybackClock $Clock $Key $Raw $Stamp $Age $Playing $Rate $Now $Duration}
 if($anchor){
  if([Math]::Abs($next.Position-$anchor.Position) -gt .05){$next.SeekSerial++}
  $next.Position=[Math]::Max(0.0,$anchor.Position)
  if($Duration -gt 0){$next.Position=[Math]::Min($Duration,$next.Position)}
  $next.Raw=$Raw;$next.Stamp=$Stamp;$next.Dynamic=$anchor.Dynamic;$next.HadPause=$false;$next.Pending=$null
 }
 $next.NeteaseResume=$sync
 return $next
}
function Resolve-LocalPlaybackClock($Clock,[string]$Key,[double]$Raw,[long]$Stamp,[double]$Age,$Local,[double]$Rate,[double]$Now,[double]$Duration,[bool]$PreferMediaTimeline=$false){
 if($PreferMediaTimeline){
  if($Clock -and $Clock.Track -eq $Key -and -not $Clock.Playing -and $Local.SoftResumeGap -gt 0){$Clock.Position+=$Local.SoftResumeGap}
  return Resolve-NeteasePlaybackClock $Clock $Key $Raw $Stamp $Age ($Local.Playing -and -not $Local.HoldPosition) $Rate $Now $Duration
 }
 # Ignore delayed media progress while the actual local stream disagrees.
 if($Local.Disagrees){
  $Age=0.0
  if($Clock -and $Clock.Track -eq $Key){$Raw=$Clock.Raw;$Stamp=$Clock.Stamp}
 }
 return Resolve-PlaybackClock $Clock $Key $Raw $Stamp $Age $Local.Playing $Rate $Now $Duration
}
