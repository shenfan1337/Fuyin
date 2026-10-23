param($Shared,[string]$Root)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
. "$Root\PlaybackClock.ps1"
. "$Root\LocalPlayback.ps1"
. "$Root\PlayerDetection.ps1"
$audioAvailable=$false
try{Add-Type -Path "$Root\AudioSessionReader.cs"; $audioAvailable=$true}catch{$Shared.AudioError=$_.Exception.Message}
$localState=$null; $playerProcesses=@(); $nextProcessRefresh=0.0
$null=[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager,Windows.Media.Control,ContentType=WindowsRuntime]
$asTask=[System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {$_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'} | Select-Object -First 1
$clock=$null; $watch=[Diagnostics.Stopwatch]::StartNew()
try{
 $op=[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()
 $task=$asTask.MakeGenericMethod([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]).Invoke($null,@($op))
 if(-not $task.Wait(5000)){throw '播放状态连接超时'}
 $manager=$task.Result
 while(-not $Shared.Stop){
  try{
   $snapshot=$Shared.Snapshot
   if($watch.Elapsed.TotalSeconds -ge $nextProcessRefresh){$playerProcesses=@(Get-Process Spotify,cloudmusic,qqmusic -ErrorAction SilentlyContinue);$nextProcessRefresh=$watch.Elapsed.TotalSeconds+1}
   try{
    if($audioAvailable){$readPeak=(Get-LumaPlayerKind $snapshot.Source) -eq 'cloudmusic';$allAudio=[AudioSessionReader]::Read($readPeak);$Shared.LocalPlayers=@(Get-LumaLocalPlayers $playerProcesses $allAudio ([Diagnostics.Stopwatch]::GetTimestamp()));$Shared.AudioError=''}
   }catch{$Shared.AudioError=$_.Exception.Message;$Shared.LocalPlayers=@()}
   $source=if($snapshot.Source){$snapshot.Source}elseif($Shared.Source){$Shared.Source}else{''}
   $localPlayer=$Shared.LocalPlayers | Where-Object {$_.Kind -eq (Get-LumaPlayerKind $source)} | Select-Object -First 1
   if($source -like 'native:*'){
    $nativeAudio=if($localPlayer){[int]$localPlayer.AudioState}else{-1}
    $local=Resolve-LocalPlayback $localState $source $false $nativeAudio $watch.Elapsed.TotalSeconds
    $localState=$local.State
    $Shared.Transport=@{Key=$snapshot.Key;Source=$source;Playing=$local.Playing;Position=0.0;Rate=0.0;SeekSerial=0;Tick=[Diagnostics.Stopwatch]::GetTimestamp();LocalAudio=$local.Local}
    Start-Sleep -Milliseconds 100
    continue
   }
   $session=$null
   if($source){$session=@($manager.GetSessions()) | Where-Object {$_.SourceAppUserModelId -eq $source} | Select-Object -First 1}
   if(-not $session -and -not $source){$session=$manager.GetCurrentSession()}
   if($session){
    $info=$session.GetPlaybackInfo(); $timeline=$session.GetTimelineProperties()
    $mediaPlaying=$info.PlaybackStatus.ToString() -eq 'Playing'
    $audioState=-1
    if($audioAvailable -and ($session.SourceAppUserModelId -notmatch 'spotify' -or $Shared.SpotifyLocal)){
     try{
      if($localPlayer){$audioState=[int]$localPlayer.AudioState}
     }catch{$Shared.AudioError=$_.Exception.Message}
    }
    $preferMediaEdges=(Get-LumaPlayerKind $session.SourceAppUserModelId) -eq 'cloudmusic'
    $age=([DateTimeOffset]::Now-$timeline.LastUpdatedTime).TotalSeconds
    if($preferMediaEdges){
     $peak=if($localPlayer -and $null -ne $localPlayer.Peak){[double]$localPlayer.Peak}else{-1.0}
     $local=Resolve-NeteaseAudioPlayback $localState $session.SourceAppUserModelId $mediaPlaying $audioState $peak $timeline.Position.TotalSeconds $age $watch.Elapsed.TotalSeconds
    }else{$local=Resolve-LocalPlayback $localState $session.SourceAppUserModelId $mediaPlaying $audioState $watch.Elapsed.TotalSeconds}
    $localState=$local.State; $playing=$local.Playing
    $rate=1.0; if($null -ne $info.PlaybackRate){$rate=[double]$info.PlaybackRate}
    if($local.Local -and $playing -and $rate -le 0){$rate=1.0}
    $key=if($snapshot){$snapshot.Key}else{''}
    $age=([DateTimeOffset]::Now-$timeline.LastUpdatedTime).TotalSeconds
    $missingTimeline=$timeline.EndTime.TotalSeconds -le 0 -or $timeline.LastUpdatedTime.UtcTicks -le 0
    if($missingTimeline){$clock=$null}
    else{$clock=Resolve-LocalPlaybackClock $clock $key $timeline.Position.TotalSeconds $timeline.LastUpdatedTime.UtcTicks $age $local $rate $watch.Elapsed.TotalSeconds $timeline.EndTime.TotalSeconds $preferMediaEdges}
    $Shared.Transport=@{Key=$key;Source=$session.SourceAppUserModelId;Playing=$playing;Position=$(if($missingTimeline){0.0}else{$clock.Position});Rate=$(if($missingTimeline -or $local.HoldPosition){0.0}else{$rate});SeekSerial=$(if($clock){$clock.SeekSerial}else{0});Tick=[Diagnostics.Stopwatch]::GetTimestamp();LocalAudio=$local.Local;TimelineUnavailable=$missingTimeline}
   }else{$Shared.Transport=@{Key=$(if($snapshot){$snapshot.Key}else{''});Source=$source;Playing=$false;Position=$(if($snapshot){$snapshot.Position}else{0.0});Rate=0.0;SeekSerial=0;Tick=[Diagnostics.Stopwatch]::GetTimestamp()}}
  }catch{$Shared.TransportError=$_.Exception.Message; $Shared.Transport=$null}
  Start-Sleep -Milliseconds 100
 }
}catch{$Shared.TransportError=$_.Exception.Message; $Shared.Transport=$null}
