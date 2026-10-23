param($Shared, [string]$Root, [string]$Cache, [switch]$Probe)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -AssemblyName System.Net.Http
Add-Type -Path "$Root\CoverReader.dll"
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
. "$Root\Lyrics.ps1"
. "$Root\LyricFetch.ps1"
. "$Root\PlaybackClock.ps1"
. "$Root\PlayerDetection.ps1"
. "$Root\ProviderIdentity.ps1"
$clockState=$null; $monotonic=[Diagnostics.Stopwatch]::StartNew()
$null=[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager,Windows.Media.Control,ContentType=WindowsRuntime]
$null=[Windows.Storage.Streams.DataReader,Windows.Storage.Streams,ContentType=WindowsRuntime]
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
function Await($Operation, [type]$Type) {
    $task=$asTask.MakeGenericMethod($Type).Invoke($null,@($Operation))
    if (-not $task.Wait(5000)) { throw 'Windows 媒体接口响应超时' }
    return $task.Result
}
$client=New-Object System.Net.Http.HttpClient
$client.Timeout=[TimeSpan]::FromSeconds(8)
$client.DefaultRequestHeaders.UserAgent.ParseAdd('LumaLyrics/1.0 (Windows desktop lyrics)')
$lyricAttempt=0; $retryAt=[DateTime]::MinValue; $instrumental=$false; $upgradePending=$false; $requestDuration=0.0; $key=''; $rows=@(); $cover=$null; $lyricStatus=''; $lastRefresh=[DateTime]::MinValue; $coverRetryAt=[DateTime]::MinValue
try {
 $manager=Await ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
 while (-not $Shared.Stop) {
  try {
   $sessions=@($manager.GetSessions())
   $choices=@($sessions | ForEach-Object { $_.SourceAppUserModelId })
   $players=@($Shared.LocalPlayers | Where-Object {([Diagnostics.Stopwatch]::GetTimestamp()-$_.Tick)/[double][Diagnostics.Stopwatch]::Frequency -lt 1.5})
   $sessionKinds=@($choices | ForEach-Object {Get-LumaPlayerKind $_})
   $nativePlayers=@($players | Where-Object {$_.Kind -ne 'spotify' -and $sessionKinds -notcontains $_.Kind})
   $choices+=@($nativePlayers | ForEach-Object {$_.Source})
   $native=$null
   $session=$null
   if ($Shared.Source) {
    $session=$sessions | Where-Object { $_.SourceAppUserModelId -eq $Shared.Source } | Select-Object -First 1
    if(-not $session){$native=$nativePlayers | Where-Object {$_.Kind -eq (Get-LumaPlayerKind $Shared.Source)} | Select-Object -First 1}
   }
   else {
    $active=Select-LumaActivePlayer $players $Shared.Snapshot.Source
    if(-not $active){$native=$nativePlayers | Where-Object {$_.Source -eq $Shared.Snapshot.Source} | Select-Object -First 1}
    if($active){
     $session=$sessions | Where-Object {(Get-LumaPlayerKind $_.SourceAppUserModelId) -eq $active.Kind} | Select-Object -First 1
     if(-not $session){$native=$nativePlayers | Where-Object {$_.Kind -eq $active.Kind} | Select-Object -First 1}
    }
    if(-not $session -and -not $native){$session=$sessions | Where-Object { $_.SourceAppUserModelId -match 'spotify|qqmusic|cloudmusic|netease' -and $_.GetPlaybackInfo().PlaybackStatus.ToString() -eq 'Playing' } | Select-Object -First 1}
    if (-not $session) { $session=$sessions | Where-Object { $_.GetPlaybackInfo().PlaybackStatus.ToString() -eq 'Playing' } | Select-Object -First 1 }
    if (-not $session) { $session=$manager.GetCurrentSession() }
   }
   if($native){
    $title=if($native.Title){$native.Title}elseif($native.Kind -eq 'cloudmusic'){'网易云音乐'}else{'QQ 音乐'}
    $Shared.Snapshot=@{Key=($native.Source+'|'+$native.Title+'|'+$native.Artist);Source=$native.Source;Title=$title;Artist=$native.Artist;Sources=$choices;Rows=@();Cover=$null;Position=0.0;Duration=0.0;Playing=($native.AudioState -eq 1);Rate=0.0;SeekSerial=0;Tick=[Diagnostics.Stopwatch]::GetTimestamp();TimelineUnavailable=$true;Status='已识别本机音频；播放器未提供同步进度'}
    $key='';$Shared.Error=''
    if($Probe){break}
    Start-Sleep -Milliseconds 650
    continue
   }
   if (-not $session) {
    $processes=@(Get-Process -Name cloudmusic,qqmusic,spotify -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProcessName -Unique)
    $Shared.Snapshot=@{ Key=''; Title='等待音乐响起'; Artist='打开网易云、QQ 音乐或 Spotify'; Status=$(if ($processes.Count) {'播放器已运行，但未提供系统媒体信息'} else {'尚未发现正在播放的音乐'}); Sources=$choices; Rows=@(); Position=0; Duration=0; Playing=$false; Cover=$null }
    $key=''
   } else {
    $props=Await ($session.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
    $timeline=$session.GetTimelineProperties(); $playback=$session.GetPlaybackInfo()
    $newKey=$session.SourceAppUserModelId+'|'+$props.Title+'|'+$props.Artist+'|'+$props.AlbumTitle
    $providerIdentity=Get-LumaProviderIdentity $props.Genres
    if($providerIdentity){$newKey+='|'+$providerIdentity.Provider+':'+$providerIdentity.Id}
    $playing=$playback.PlaybackStatus.ToString() -eq 'Playing'
    $duration=$timeline.EndTime.TotalSeconds
    $rate=1.0; if($null -ne $playback.PlaybackRate){$rate=[double]$playback.PlaybackRate}
    $age=([DateTimeOffset]::Now-$timeline.LastUpdatedTime).TotalSeconds
    $clockState=Resolve-PlaybackClock $clockState $newKey $timeline.Position.TotalSeconds $timeline.LastUpdatedTime.UtcTicks $age $playing $rate $monotonic.Elapsed.TotalSeconds $duration
    $position=$clockState.Position
    $sampleTick=[Diagnostics.Stopwatch]::GetTimestamp(); $sampleUtc=[DateTime]::UtcNow
    $newTrack=$key -ne $newKey
    $durationArrived=$duration -gt 0 -and $requestDuration -le 0
    $retryDue=(-not $rows.Count -or $upgradePending) -and -not $instrumental -and ([DateTime]::UtcNow -ge $retryAt -or $durationArrived)
    if ($newTrack -or $Shared.Reload -or $retryDue) {
     if($newTrack){$key=$newKey; $rows=@(); $cover=$null; $Shared.CoverError=''; $lyricAttempt=0; $instrumental=$false; $upgradePending=$false}
     if($Shared.Reload){$rows=@(); $lyricAttempt=0; $instrumental=$false}
     $Shared.Reload=$false; $lyricStatus='正在自动获取同步歌词…'; $coverRetryAt=[DateTime]::UtcNow
     $sha=[Security.Cryptography.SHA256]::Create()
     $legacyHash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($key))).Replace('-','')
     $legacyPath=Join-Path $Cache ($legacyHash+'.lrc')
     # Upgrade line-only caches once; retain user files and cache future YRC data.
     $hash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($key+'|word-timing-v2'))).Replace('-',''); $sha.Dispose()
     $lrcPath=Join-Path $Cache ($hash+'.lrc')
     # Show cached words while a precision upgrade runs in the background.
     if(-not $rows.Count -and (Test-Path -LiteralPath $lrcPath)){
      try{$rows=@(ConvertFrom-Lrc (Read-LrcFile $lrcPath))}catch{}
     }
     if($lyricAttempt -eq 0 -and -not $newTrack){Remove-Item -LiteralPath ($lrcPath+'.word-check'),($lrcPath+'.krc-check') -ErrorAction SilentlyContinue}
     $Shared.Snapshot=@{Key=$key;Title=$props.Title;Artist=$props.Artist;Source=$session.SourceAppUserModelId;Sources=$choices;Rows=$rows;Cover=$cover;Position=$position;Duration=$duration;Playing=$playing;Status=$lyricStatus;At=$sampleUtc;Tick=$sampleTick;Rate=$rate;SeekSerial=$clockState.SeekSerial; LrcPath=$lrcPath}
     try {
      if (-not $cover -and $props.Thumbnail) {
       $coverTask=[CoverReader]::ReadAsync($props.Thumbnail)
       if(-not $coverTask.Wait(5000)){throw '封面读取超时'}
       $cover=$coverTask.Result
      }
     } catch { $cover=$null; $Shared.CoverError=$_.Exception.ToString() }
     if($cover){$ready=$Shared.Snapshot.Clone(); $ready.Cover=$cover; $Shared.Snapshot=$ready}
     $lyricAttempt++; $requestDuration=$duration
     # Display usable line lyrics before a secondary word lookup can wait on HTTP.
     $publishPlain={param($available)
      if($Shared.Snapshot.Key -eq $key){$ready=$Shared.Snapshot.Clone();$ready.Rows=$available.Rows;$ready.Status=$available.Status;$Shared.Snapshot=$ready}
     }
     $result=Request-LumaLyrics $client $props.Title $props.Artist $props.AlbumTitle $duration $lrcPath $lyricAttempt $providerIdentity $publishPlain
     $rows=$result.Rows; $instrumental=$result.Instrumental; $lyricStatus=$result.Status
     $upgradePending=$false
     if(-not $rows.Count -and -not $instrumental -and (Test-Path -LiteralPath $legacyPath)){
      try{$rows=@(ConvertFrom-Lrc (Read-LrcFile $legacyPath))}catch{}
      if($rows.Count){$upgradePending=$true;$lyricStatus='使用已缓存歌词 · 逐字歌词获取失败，将自动重试'}
     }
     # Publish completed lyrics immediately. A second metadata request must not
     # hide a successful fetch or its error; the independent transport owns time.
     if($Shared.Snapshot.Key -eq $key){
      $ready=$Shared.Snapshot.Clone();$ready.Rows=$rows;$ready.Status=$lyricStatus
      $Shared.Snapshot=$ready
     }
     $retryAt=[DateTime]::UtcNow.AddSeconds((Get-LyricRetryDelay $lyricAttempt))
     # Network work may take seconds; re-read timing on the next poll, never extrapolate a stale timestamp.
     $lastRefresh=[DateTime]::UtcNow
     continue
    }
    if(-not $cover -and $props.Thumbnail -and ([DateTime]::UtcNow-$coverRetryAt).TotalSeconds -ge 3){
     $coverRetryAt=[DateTime]::UtcNow
     try{$coverTask=[CoverReader]::ReadAsync($props.Thumbnail); if(-not $coverTask.Wait(5000)){throw '封面读取超时'}; $cover=$coverTask.Result; $Shared.CoverError=''}catch{$Shared.CoverError=$_.Exception.Message}
    }
    $Shared.Snapshot=@{Key=$key;Title=$props.Title;Artist=$props.Artist;Source=$session.SourceAppUserModelId;Sources=$choices;Rows=$rows;Cover=$cover;Position=$position;Duration=$duration;Playing=$playing;Status=$lyricStatus;At=$sampleUtc;Tick=$sampleTick;Rate=$rate;SeekSerial=$clockState.SeekSerial;LrcPath=$lrcPath}
   }
   $Shared.Error=''
  } catch {
   $Shared.Error=$_.Exception.Message
   $Shared.Snapshot=@{Key='';Title='等待播放器重新连接';Artist='';Status='媒体会话暂时不可用';Sources=@();Rows=@();Position=0;Duration=0;Playing=$false;Cover=$null}
  }
  if ($Probe) { break }
  Start-Sleep -Milliseconds 650
 }
} catch { $Shared.Error=$_.Exception.Message } finally { $client.Dispose(); $Shared.Done=$true }
