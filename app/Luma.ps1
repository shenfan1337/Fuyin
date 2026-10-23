param([switch]$InspectUI, [switch]$LiveMedia, [switch]$Demo, [switch]$Startup, [switch]$SelfTest, [string]$Preview, [string]$MenuPreview, [ValidateSet("Pearl","Mist","Night")][string]$Theme)
$ErrorActionPreference='Stop'
trap { if ($SelfTest) { Write-Error $_.Exception.Message -ErrorAction Continue; exit 1 }; [Windows.MessageBox]::Show($_.Exception.Message,'Luma 启动或运行失败') | Out-Null; exit 1 }
$root=$PSScriptRoot
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms,System.Drawing
Add-Type -Path "$root\Native.cs"
. "$root\Lyrics.ps1"
. "$root\Karaoke.ps1"
. "$root\LiveState.ps1"
. "$root\Startup.ps1"
. "$root\Shortcuts.ps1"
if (-not $SelfTest -and -not $InspectUI) {
 $created=$false
 $script:instance=New-Object Threading.Mutex($true,'Local\LumaLyrics.Desktop',[ref]$created)
 if (-not $created) { if ($Startup) { exit }; [Windows.MessageBox]::Show('浮音已经运行。请双击系统托盘中的图标显示面板。','Luma') | Out-Null; exit }
}
$dataDir=Join-Path $env:LOCALAPPDATA 'LumaLyrics'
if ($SelfTest -or $InspectUI) { $dataDir=Join-Path $root '..\..\work\self-test' }
$null=New-Item -ItemType Directory -Force (Join-Path $dataDir 'lyrics')
$configPath=Join-Path $dataDir 'settings.json'
$settings=@{Left=$null;Top=$null;Locked=$false;Acrylic=$true;Offset=0.0;Width=620;Theme='Pearl';Tint=28;AppearanceVersion=1;GameMode=$false;SpotifyLocal=$true;LyricMode='White';LyricColor='Theme';LyricCustom='#8DBBFF';LyricAppearanceVersion=0;ProgressColor='Theme';ProgressCustom='#8DBBFF'}
if (Test-Path $configPath) { try { $saved=Get-Content $configPath -Raw | ConvertFrom-Json; foreach ($p in $saved.PSObject.Properties) { if ($settings.ContainsKey($p.Name)) { $settings[$p.Name]=$p.Value } } } catch {} }
if ($settings.Theme -notin @('Pearl','Mist','Night')) { $settings.Theme='Pearl' }
if($settings.LyricAppearanceVersion -lt 1){$settings.LyricMode='White';$settings.LyricAppearanceVersion=1}
if($settings.LyricMode -notin @('Word','Line','White')){$settings.LyricMode='White'}
if($settings.LyricColor -notin @('Theme','Mint','Blue','Violet','Rose','Amber','Custom')){$settings.LyricColor='Theme'}
if($settings.LyricCustom -notmatch '^#[0-9a-fA-F]{6}$'){$settings.LyricCustom='#8DBBFF'}
if($settings.ProgressColor -notin @('Theme','Mint','Blue','Violet','Rose','Amber','White','Custom')){$settings.ProgressColor='Theme'}
if($settings.ProgressCustom -notmatch '^#[0-9a-fA-F]{6}$'){$settings.ProgressCustom='#8DBBFF'}
if($settings.AppearanceVersion -lt 2){switch([int]$settings.Tint){24{$settings.Tint=12}42{$settings.Tint=28}72{$settings.Tint=55}}; $settings.AppearanceVersion=2}
$settings.Tint=[Math]::Max(12,[Math]::Min(72,[int]$settings.Tint))
if ($Theme) { $settings.Theme=$Theme }
$shared=[hashtable]::Synchronized(@{Stop=$false;Snapshot=$null;Source='';Reload=$false;Error='';Done=$false;SpotifyLocal=[bool]$settings.SpotifyLocal})
$script:demoMode=[bool]$Demo
$script:demoStart=[DateTime]::UtcNow
$script:lastText=''; $script:lastCoverKey=''; $script:lastCover=$null; $script:current=$null
$script:worker=$null; $script:job=$null
$script:transportWorker=$null; $script:manualHidden=$false; $script:gamePeek=$false; $script:wantVisible=$true; $script:lastGamePlaying=$null
$script:discAngle=0.0; $script:lastFrame=[DateTime]::UtcNow; $script:ambientSeconds=0.0
$script:artColor=[Windows.Media.Color]::FromRgb(95,158,166)
$script:karaokeKey=''; $script:wordRuns=@(); $script:words=@(); $script:karaokeExact=$false
[xml]$xaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Luma · 浮音" Width="620" Height="154" WindowStyle="None" ResizeMode="NoResize" Background="#18202C" Topmost="True" ShowInTaskbar="False" FontFamily="Microsoft YaHei UI" UseLayoutRounding="True">
 <Window.Resources>
  <Style TargetType="Button"><Setter Property="Foreground" Value="{DynamicResource ButtonInk}"/><Setter Property="Background" Value="Transparent"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Width" Value="30"/><Setter Property="Height" Value="30"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="bg" Background="{TemplateBinding Background}" CornerRadius="7" BorderThickness="1" BorderBrush="Transparent"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bg" Property="Background" Value="{DynamicResource HoverFill}"/></Trigger><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="bg" Property="BorderBrush" Value="{DynamicResource FocusStroke}"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="bg" Property="Background" Value="{DynamicResource PressFill}"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
 </Window.Resources>
 <Border x:Name="Shell" CornerRadius="8" BorderThickness="0" BorderBrush="Transparent">
  <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#A3344359" Offset="0"/><GradientStop Color="#C018202C" Offset="0.7"/><GradientStop Color="#B1283440" Offset="1"/></LinearGradientBrush></Border.Background>
  <Grid Margin="20,14,16,14">
   <Grid.ColumnDefinitions><ColumnDefinition Width="120"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
   <Border x:Name="CoverFrame" Width="100" Height="100" HorizontalAlignment="Left" VerticalAlignment="Center" CornerRadius="50" Background="Transparent" BorderThickness="0">
    <Grid x:Name="CoverViewport" SnapsToDevicePixels="True" RenderOptions.EdgeMode="Unspecified"><Grid.Clip><EllipseGeometry Center="50,50" RadiusX="50" RadiusY="50"/></Grid.Clip>
     <Grid x:Name="Disc" RenderTransformOrigin="0.5,0.5" SnapsToDevicePixels="False" UseLayoutRounding="False" RenderOptions.BitmapScalingMode="HighQuality"><Grid.RenderTransform><RotateTransform/></Grid.RenderTransform>
     <Grid x:Name="Fallback"><Grid.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#568D9C" Offset="0"/><GradientStop Color="#24334A" Offset="0.55"/><GradientStop Color="#A27B70" Offset="1"/></LinearGradientBrush></Grid.Background></Grid>
     <Image x:Name="Cover" Stretch="UniformToFill" SnapsToDevicePixels="False" UseLayoutRounding="False" RenderOptions.BitmapScalingMode="HighQuality"/>
     </Grid>
     <Border x:Name="CoverCaption" Visibility="Collapsed"><TextBlock x:Name="CoverLabel"/></Border>
    </Grid>
   </Border>
   <Grid Grid.Column="1">
    <Grid.RowDefinitions><RowDefinition Height="30"/><RowDefinition Height="*"/><RowDefinition Height="25"/></Grid.RowDefinitions>
    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="90"/></Grid.ColumnDefinitions>
     <Grid VerticalAlignment="Center" Margin="0,0,8,0"><Grid.ColumnDefinitions><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Ellipse x:Name="Dot" Width="4" Height="4" Fill="#95D9C5" HorizontalAlignment="Left" VerticalAlignment="Center"/><TextBlock Grid.Column="1" x:Name="Track" Text="浮音" FontSize="12" Foreground="#D0DFED" TextTrimming="CharacterEllipsis"/></Grid>
     <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="Lock" ToolTip="锁定 / 解锁位置" AutomationProperties.Name="固定歌词位置"><Path x:Name="LockGlyph" Width="14" Height="14" Stretch="Uniform" Stroke="{Binding Foreground,RelativeSource={RelativeSource AncestorType=Button}}" StrokeThickness="1.4" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Data="M 4,6 V 4 A 3,3 0 0 1 10,4 M 3,6 H 11 V 13 H 3 Z M 7,9 V 10.5"/></Button>
      <Button x:Name="Menu" ToolTip="设置与歌词" AutomationProperties.Name="打开设置"><Path Width="14" Height="14" Stretch="Uniform" Fill="{Binding Foreground,RelativeSource={RelativeSource AncestorType=Button}}" Data="M 2,6 A 1,1 0 1 1 2,8 A 1,1 0 1 1 2,6 M 7,6 A 1,1 0 1 1 7,8 A 1,1 0 1 1 7,6 M 12,6 A 1,1 0 1 1 12,8 A 1,1 0 1 1 12,6"/></Button>
      <Button x:Name="Hide" ToolTip="隐藏到系统托盘" AutomationProperties.Name="隐藏歌词面板"><Path Width="11" Height="11" Stretch="Uniform" Stroke="{Binding Foreground,RelativeSource={RelativeSource AncestorType=Button}}" StrokeThickness="1.4" StrokeStartLineCap="Round" Data="M 2,2 L 12,12 M 12,2 L 2,12"/></Button>
     </StackPanel>
    </Grid>
    <Grid Grid.Row="1" ClipToBounds="True" Margin="0,2,6,0">
     <StackPanel x:Name="LyricGroup" VerticalAlignment="Center"><StackPanel.RenderTransform><TranslateTransform/></StackPanel.RenderTransform><TextBlock x:Name="Lyric" Text="让音乐，浮在此刻。" Foreground="#FFF4F7FC" FontSize="22" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/><TextBlock x:Name="Next" Text="等待正在播放的歌曲" Foreground="#91B8C8DB" FontSize="13" Margin="0,6,0,0" TextTrimming="CharacterEllipsis"/></StackPanel>
    </Grid>
    <Grid Grid.Row="2" Margin="0,5,6,0"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="90"/></Grid.ColumnDefinitions><TextBlock x:Name="Source" FontSize="11" FontWeight="SemiBold" Foreground="#192738" Text="LUMA / DESKTOP LYRICS" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/><TextBlock Grid.Column="1" x:Name="Time" FontSize="10.5" Typography.NumeralAlignment="Tabular" Foreground="#9EAFC2" Text="--:--" HorizontalAlignment="Right" VerticalAlignment="Center"/></Grid>
   </Grid>
   <Border x:Name="ProgressTrack" Grid.ColumnSpan="2" Height="2" VerticalAlignment="Bottom" Margin="120,0,6,-7" Background="#15FFFFFF" CornerRadius="1" ClipToBounds="True"><Grid><Border x:Name="Progress" HorizontalAlignment="Left" Width="0" Background="#A6C8E4DC" CornerRadius="1"/></Grid></Border>
  </Grid>
 </Border>
</Window>
'@
$window=[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$window.Resources.MergedDictionaries.Add([Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $root 'MenuTheme.xaml'))))
if($InspectUI){$window.ShowInTaskbar=$true; $window.Title='Luma visual verification'}
$window.Icon=[Windows.Media.Imaging.BitmapFrame]::Create([Uri](Join-Path $root 'Fuyin.ico'))
$chrome=[Windows.Shell.WindowChrome]::new(); $chrome.CaptionHeight=0; $chrome.ResizeBorderThickness=[Windows.Thickness]::new(0); $chrome.GlassFrameThickness=[Windows.Thickness]::new(-1); $chrome.UseAeroCaptionButtons=$false
[Windows.Shell.WindowChrome]::SetWindowChrome($window,$chrome)
$ui=@{}; foreach ($name in @('CoverViewport','Disc','CoverFrame','CoverCaption','ProgressTrack','Shell','Fallback','Cover','CoverLabel','Dot','Track','Lock','LockGlyph','Menu','Hide','LyricGroup','Lyric','Next','Source','Time','Progress')) { $ui[$name]=$window.FindName($name) }
$window.Width=[Math]::Max(480,[Math]::Min(860,[double]$settings.Width))
function Save-Settings { $settings.Left=$window.Left; $settings.Top=$window.Top; $settings.Width=$window.Width; $settings | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8 }
function Apply-Glass {
 $handle=(New-Object Windows.Interop.WindowInteropHelper $window).Handle
 if ($handle -eq [IntPtr]::Zero) { return }
 $src=[Windows.Interop.HwndSource]::FromHwnd($handle)
 $src.CompositionTarget.BackgroundColor=[Windows.Media.Colors]::Transparent
 $scale=$src.CompositionTarget.TransformToDevice.M11
 $script:glassStatus=[GlassNative]::Apply($handle,[int]($window.ActualWidth*$scale),[int]($window.ActualHeight*$scale),[int](16*$scale),[bool]$settings.Acrylic,[uint32]$script:glassTint)
 if($settings.Acrylic -and $script:glassStatus -eq 'Unavailable'){$window.Background=[Windows.Media.BrushConverter]::new().ConvertFromString($script:palette.Solid); return}
 $window.Background=if($settings.Acrylic){[Windows.Media.Brushes]::Transparent}else{[Windows.Media.BrushConverter]::new().ConvertFromString($script:palette.Solid)}
}
function Apply-Theme {
 $palettes=@{
  Pearl=@{Solid='#F3F5F7';TintRGB='FAF8F5';Ink='#243246';Muted='#526174';Accent='#297C73';Edge='#B8FFFFFF';Top='#66FFFFFF';Middle='#32F7F9FC';Bottom='#48E5EDF5';CoverTop='#E6EDEB';CoverBottom='#ADBCCD';Menu='#FFF5F7FA';Hover='#407C97AC'}
  Mist=@{Solid='#E4EFF1';TintRGB='F1ECE4';Ink='#203B48';Muted='#486B76';Accent='#217C86';Edge='#B3F0FFFF';Top='#66EDFFFF';Middle='#32DDEDF2';Bottom='#48BCD4E0';CoverTop='#D2E8E5';CoverBottom='#829FB9';Menu='#FFF0F7F8';Hover='#407BA6B2'}
  Night=@{Solid='#18202C';TintRGB='2B211C';Ink='#F4F7FC';Muted='#B2C3D5';Accent='#95D9C5';Edge='#507D9BB3';Top='#66344359';Middle='#3218202C';Bottom='#48283440';CoverTop='#568D9C';CoverBottom='#24334A';Menu='#FF222C3B';Hover='#25FFFFFF'}
 }
 $script:palette=$palettes[$settings.Theme]; $p=$script:palette
 $convert=[Windows.Media.BrushConverter]::new()
 $alpha=[int][Math]::Round(255*[double]$settings.Tint/100)
 $script:glassTint=[Convert]::ToUInt32(('{0:X2}' -f $alpha)+$p.TintRGB,16)
 $gradient=New-Object Windows.Media.LinearGradientBrush
 $gradient.StartPoint=[Windows.Point]::new(0,0); $gradient.EndPoint=[Windows.Point]::new(1,1)
 $gradient.GradientStops.Add([Windows.Media.GradientStop]::new([Windows.Media.ColorConverter]::ConvertFromString($p.Top),0))
 $gradient.GradientStops.Add([Windows.Media.GradientStop]::new([Windows.Media.ColorConverter]::ConvertFromString($p.Middle),0.6))
 $gradient.GradientStops.Add([Windows.Media.GradientStop]::new([Windows.Media.ColorConverter]::ConvertFromString($p.Bottom),1))
 foreach($stop in $gradient.GradientStops){$c=$stop.Color; $c.A=[byte][Math]::Round(255*$settings.Tint/100); $stop.Color=$c}
 $ui.Shell.Background=$gradient; $ui.Shell.BorderBrush=$convert.ConvertFromString($p.Edge)
 foreach($name in @('Lyric','Track')){$ui[$name].Foreground=$convert.ConvertFromString($p.Ink)}
 foreach($name in @('Next','Source','Time')){$ui[$name].Foreground=$convert.ConvertFromString($p.Muted)}
 $ui.Source.Foreground=$convert.ConvertFromString($(if($settings.Theme -eq 'Night'){'#F4F7FC'}elseif($settings.Theme -eq 'Mist'){'#102E3B'}else{'#192738'}))
 if($settings.LyricMode -eq 'White'){$ui.Lyric.Foreground=[Windows.Media.Brushes]::White;$ui.Next.Foreground=[Windows.Media.Brushes]::White}
 $ui.Next.Opacity=if($settings.LyricMode -eq 'White'){0.58}else{1.0}
 # A text-only shadow preserves white lyrics over a bright desktop without a backing plate.
 foreach($label in @($ui.Lyric,$ui.Next)){
  if($settings.LyricMode -eq 'White'){
   $shadow=[Windows.Media.Effects.DropShadowEffect]::new();$shadow.Color=[Windows.Media.Colors]::Black
   $shadow.BlurRadius=5;$shadow.ShadowDepth=1;$shadow.Direction=270;$shadow.Opacity=.5;$label.Effect=$shadow
  }else{$label.Effect=$null}
 }
 $ui.Dot.Fill=$convert.ConvertFromString($p.Accent)
 $progressInk=if($settings.ProgressColor -eq 'Custom'){$settings.ProgressCustom}elseif($settings.ProgressColor -eq 'White'){'#FFFFFF'}else{Get-LumaLyricAccent $settings.ProgressColor $settings.Theme $p.Accent}
 $ui.Progress.Background=$convert.ConvertFromString($progressInk)
 $ui.ProgressTrack.Background=$convert.ConvertFromString($p.Hover)
 $ui.CoverFrame.BorderBrush=$convert.ConvertFromString($p.Edge)
 $ui.CoverCaption.Background=$convert.ConvertFromString($p.Menu); $ui.CoverLabel.Foreground=$convert.ConvertFromString($p.Muted)
 $ui.Fallback.Background=[Windows.Media.LinearGradientBrush]::new([Windows.Media.ColorConverter]::ConvertFromString($p.CoverTop),[Windows.Media.ColorConverter]::ConvertFromString($p.CoverBottom),45)
 $window.Resources['ButtonInk']=$convert.ConvertFromString($p.Ink)
 $window.Resources['HoverFill']=$convert.ConvertFromString($p.Hover)
 $window.Resources['MenuFill']=$convert.ConvertFromString($p.Menu)
 $window.Resources['FrameStroke']=$convert.ConvertFromString($p.Edge)
 $window.Resources['MenuDisabled']=$convert.ConvertFromString($p.Muted)
 $window.Resources['FocusStroke']=$convert.ConvertFromString($p.Accent)
 $window.Resources['PressFill']=$convert.ConvertFromString($(if($settings.Theme -eq 'Night'){'#38FFFFFF'}else{'#337289A0'}))
 $window.Resources['MenuStroke']=$convert.ConvertFromString($(if($settings.Theme -eq 'Night'){'#FF465267'}else{'#FFD0D9E2'}))
 $window.Resources['MenuMaxHeight']=[double][Math]::Max(200,[Math]::Min(640,[Windows.SystemParameters]::WorkArea.Height-32))
 if($script:activeMenu){foreach($resource in @('ButtonInk','HoverFill','MenuFill','FrameStroke','MenuDisabled','MenuStroke','MenuMaxHeight','FocusStroke','PressFill')){$script:activeMenu.Resources[$resource]=$window.Resources[$resource]}}
 Apply-Glass
}
Apply-Theme
function Update-LockIcon {
 $ui.LockGlyph.Data=[Windows.Media.Geometry]::Parse($(if($settings.Locked){'M 4,6 V 4 A 3,3 0 0 1 10,4 V 6 M 3,6 H 11 V 13 H 3 Z M 7,9 V 10.5'}else{'M 4,6 V 4 A 3,3 0 0 1 10,4 M 3,6 H 11 V 13 H 3 Z M 7,9 V 10.5'}))
 $ui.Lock.ToolTip=if($settings.Locked){'位置已固定 · 点击解锁'}else{'拖动面板调整位置'}
 [Windows.Automation.AutomationProperties]::SetName($ui.Lock,$(if($settings.Locked){'解锁歌词位置'}else{'固定歌词位置'}))
}
function Toggle-Lock { $settings.Locked=-not $settings.Locked;Update-LockIcon;Save-Settings }
function Set-PanelVisibility([bool]$Visible){
 if($script:wantVisible -eq $Visible){return}
 $script:wantVisible=$Visible
 $from=$window.Opacity
 $window.BeginAnimation([Windows.UIElement]::OpacityProperty,$null)
 $window.Opacity=$from
 if($Visible -and -not $window.IsVisible){$window.Opacity=0; $from=0; $window.Show()}
 $fade=[Windows.Media.Animation.DoubleAnimation]::new()
 $fade.From=$from; $fade.To=$(if($Visible){1.0}else{0.0}); $fade.Duration=[TimeSpan]::FromMilliseconds(260)
 $ease=[Windows.Media.Animation.SineEase]::new(); $ease.EasingMode='EaseInOut'; $fade.EasingFunction=$ease
 if($Visible){$fade.Add_Completed({if($script:wantVisible){$window.BeginAnimation([Windows.UIElement]::OpacityProperty,$null);$window.Opacity=1;Apply-Glass}})}
 else{$fade.Add_Completed({if(-not $script:wantVisible){$window.Hide();$window.BeginAnimation([Windows.UIElement]::OpacityProperty,$null);$window.Opacity=1}})}
 $window.BeginAnimation([Windows.UIElement]::OpacityProperty,$fade)
}
function Update-GameVisibility([bool]$Playing){
 if($null -ne $script:lastGamePlaying -and $Playing -ne $script:lastGamePlaying){$script:gamePeek=$false}
 $script:lastGamePlaying=$Playing
 $visible=-not $script:manualHidden -and (-not $settings.GameMode -or $Playing -or $script:gamePeek)
 Set-PanelVisibility $visible
}
function Show-PanelFromTray {
 $script:manualHidden=$false; $script:gamePeek=$true
 Set-PanelVisibility $true
}
function Toggle-GameMode {
 $settings.GameMode=-not $settings.GameMode; $script:gamePeek=$false; $script:manualHidden=$false
 Save-Settings
 Update-GameVisibility ([bool]$script:lastGamePlaying)
}
function Show-Lyric([string]$Text,[string]$Next) {
 $ui.Next.Text=(Get-PlainLyric $Next)
 if ($script:lastText -eq $Text) { return }
 $script:lastText=$Text; $ui.Lyric.Text=(Get-PlainLyric $Text); $ui.Lyric.ToolTip=$ui.Lyric.Text; $script:karaokeKey=''
 $ease=New-Object Windows.Media.Animation.CubicEase; $ease.EasingMode='EaseOut'
 $ui.LyricGroup.RenderTransform.BeginAnimation([Windows.Media.TranslateTransform]::YProperty,$null)
 $ui.LyricGroup.RenderTransform.Y=0
 $fade=New-Object Windows.Media.Animation.DoubleAnimation; $fade.From=0.7; $fade.To=1; $fade.Duration=[TimeSpan]::FromMilliseconds(180)
 $ui.Lyric.BeginAnimation([Windows.UIElement]::OpacityProperty,$fade)
}
function Friendly-Source([string]$Name) { if ($Name -match 'spotify') {'SPOTIFY'} elseif ($Name -match 'cloudmusic|netease') {'网易云音乐'} elseif ($Name -match 'qqmusic') {'QQ 音乐'} else {$Name} }
function Update-Karaoke($Row,[double]$End,[double]$Position) {
 $key=$script:current.Key+'|'+$Row.Time+'|'+$Row.Text+'|'+$End+'|'+$Row.Words.Count+'|'+$Row.End+'|'+$settings.LyricMode+'|'+$settings.LyricColor+'|'+$settings.LyricCustom
 if($key -ne $script:karaokeKey){
  $cadence=0.0
  if($settings.LyricMode -eq 'Word' -and -not $Row.Words.Count){
   $rowIndex=Get-LyricIndex $script:current.Rows ($Row.Time+.0001)
   if($rowIndex -ge 0 -and $script:current.Rows[$rowIndex].Time -eq $Row.Time -and $script:current.Rows[$rowIndex].Text -eq $Row.Text){$cadence=Get-LumaPredictionCadence $script:current.Rows $rowIndex $script:current.Duration}
  }
  $script:karaokeKey=$key; $data=Get-LumaKaraokeData $Row $End $settings.LyricMode $cadence; $script:words=$data.Words; $script:karaokeExact=$data.Exact;$script:karaokeEstimated=[bool]$data.Estimated;$script:karaokeUnavailable=$false
  $script:lastHighlight=-99
  $ui.Lyric.Inlines.Clear(); $script:wordRuns=@()
  foreach($word in $script:words){$run=[Windows.Documents.Run]::new([string]$word.Text); $run.Foreground=[Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString($script:palette.Muted)); $ui.Lyric.Inlines.Add($run); $script:wordRuns+=,$run}
  $ui.Next.Foreground=if($settings.LyricMode -eq 'White'){[Windows.Media.Brushes]::White}else{[Windows.Media.BrushConverter]::new().ConvertFromString($script:palette.Muted)}
  $ui.Next.Opacity=if($settings.LyricMode -eq 'White'){0.58}else{1.0}
 }
 if($settings.LyricMode -eq 'White'){
  foreach($run in $script:wordRuns){$run.Foreground.BeginAnimation([Windows.Media.SolidColorBrush]::ColorProperty,$null);$run.Foreground.Color=[Windows.Media.Colors]::White;$run.TextDecorations=$null}
  $ui.Lyric.ToolTip='当前句明亮纯白 · 下一句柔和淡白 · 不随演唱进度变色'
  return
 }
 $frame=Get-KaraokeFrame $script:words $Position;$active=$frame.Active
 if($script:karaokeUnavailable){$active=-1;$frame.Completed=0}
 $highlightKey=[string]$active+':'+$frame.Completed
 $predictive=$settings.LyricMode -eq 'Word' -and $script:karaokeEstimated
 if(-not $predictive -and $script:lastHighlight -eq $highlightKey -and $script:highlightTheme -eq $settings.Theme){return}
 $script:lastHighlight=$highlightKey; $script:highlightTheme=$settings.Theme
 $prediction=if($predictive){Get-KaraokePrediction $script:words $Position $End}else{@{Index=-1;Amount=0.0}}
 $accentColor=[Windows.Media.ColorConverter]::ConvertFromString($(if($settings.LyricColor -eq 'Custom'){$settings.LyricCustom}else{Get-LumaLyricAccent $settings.LyricColor $settings.Theme $script:palette.Accent}))
 $mutedColor=[Windows.Media.ColorConverter]::ConvertFromString($script:palette.Muted)
 for($i=0;$i -lt $script:wordRuns.Count;$i++){
  $brush=if($script:karaokeUnavailable){$script:palette.Ink}elseif($i -eq $active){if($settings.LyricColor -eq 'Custom'){$settings.LyricCustom}else{Get-LumaLyricAccent $settings.LyricColor $settings.Theme $script:palette.Accent}}elseif($i -lt $frame.Completed -or ($active -ge 0 -and $i -lt $active)){$script:palette.Ink}else{$script:palette.Muted}
  $ink=$script:wordRuns[$i].Foreground
  if($predictive){
   $color=[Windows.Media.ColorConverter]::ConvertFromString($brush)
   $mix=if($i -eq $prediction.Index){$prediction.Amount}elseif($i -eq $active){
    $wordStop=if($null -ne $script:words[$i].End){[double]$script:words[$i].End}elseif($i+1 -lt $script:words.Count){[double]$script:words[$i+1].Time}else{$End}
    $onset=[Math]::Max(.001,[Math]::Min(.025,($wordStop-$script:words[$i].Time)*.2))
    .45+.55*[Math]::Min(1.0,[Math]::Max(0.0,($Position-$script:words[$i].Time)/$onset))
   }else{-1.0}
   if($mix -ge 0){$color=[Windows.Media.Color]::FromArgb(255,[byte][Math]::Round($mutedColor.R+($accentColor.R-$mutedColor.R)*$mix),[byte][Math]::Round($mutedColor.G+($accentColor.G-$mutedColor.G)*$mix),[byte][Math]::Round($mutedColor.B+($accentColor.B-$mutedColor.B)*$mix))}
   $ink.BeginAnimation([Windows.Media.SolidColorBrush]::ColorProperty,$null);$ink.Color=$color;$script:wordRuns[$i].TextDecorations=$null
   continue
  }
  $fade=[Windows.Media.Animation.ColorAnimation]::new()
  $fade.From=$ink.Color; $fade.To=[Windows.Media.ColorConverter]::ConvertFromString($brush); $fade.Duration=[TimeSpan]::FromMilliseconds((Get-KaraokeFadeMilliseconds $script:words $active $End))
  $fade.EasingFunction=[Windows.Media.Animation.SineEase]::new()
  $ink.BeginAnimation([Windows.Media.SolidColorBrush]::ColorProperty,$fade)
  $script:wordRuns[$i].TextDecorations=$null
 }
 $ui.Lyric.ToolTip=if($settings.LyricMode -eq 'Line'){'整句变色 · 按句时间同步'}elseif($script:karaokeEstimated){'自动逐字 · 当前为预测时间，按每句重新对齐；长音和停顿可能有偏差'}else{'自动逐字 · 当前使用真实逐字时间'}
}
function Update-Ambience([double]$Delta,[bool]$Playing) {
 if(-not $script:rotationClock){
  $rotation=[Windows.Media.Animation.DoubleAnimation]::new(0,360,[Windows.Duration]::new([TimeSpan]::FromSeconds(30)))
  $rotation.RepeatBehavior=[Windows.Media.Animation.RepeatBehavior]::Forever
  $script:rotationClock=$rotation.CreateClock($true)
  $ui.Disc.RenderTransform.ApplyAnimationClock([Windows.Media.RotateTransform]::AngleProperty,$script:rotationClock)
  $script:rotationClock.Controller.Pause(); $script:discPlaying=$false
 }
 if($Playing -ne $script:discPlaying){if($Playing){$script:rotationClock.Controller.Resume()}else{$script:rotationClock.Controller.Pause()}; $script:discPlaying=$Playing}
 if($Playing){$script:ambientSeconds+=$Delta}
 $mix=0.035+0.095*(0.5+0.5*[Math]::Sin($script:ambientSeconds*2*[Math]::PI/24))
 $base=[Windows.Media.ColorConverter]::ConvertFromString($script:palette.Solid)
 $alpha=if($settings.Acrylic){[byte][Math]::Round(255*$settings.Tint/100)}else{[byte]255}
 foreach($stop in $ui.Shell.Background.GradientStops){
  $factor=$mix*(0.5+$stop.Offset)
  $stop.Color=[Windows.Media.Color]::FromArgb($alpha,[byte]($base.R*(1-$factor)+$script:artColor.R*$factor),[byte]($base.G*(1-$factor)+$script:artColor.G*$factor),[byte]($base.B*(1-$factor)+$script:artColor.B*$factor))
 }
}
function Import-Lrc {
 if (-not $script:current -or -not $script:current.LrcPath -or $script:demoMode) { [Windows.MessageBox]::Show('请先退出演示并播放一首能被识别的歌曲，再导入对应的 LRC。','导入歌词') | Out-Null; return }
 $dialog=New-Object Microsoft.Win32.OpenFileDialog; $dialog.Filter='LRC 歌词 (*.lrc)|*.lrc'; $dialog.Title='为当前歌曲导入同步歌词'
 if ($dialog.ShowDialog($window)) {
  $text=Read-LrcFile $dialog.FileName
  if (@(ConvertFrom-Lrc $text).Count -eq 0) { [Windows.MessageBox]::Show('没有找到时间标签。请使用 UTF-8 编码的标准 LRC 文件。','无法导入') | Out-Null; return }
  [IO.File]::WriteAllText($script:current.LrcPath,$text); $shared.Reload=$true
 }
}
function Add-MenuItem($Parent,[string]$Text,[scriptblock]$Action) { $item=New-Object Windows.Controls.MenuItem; $item.Header=$Text; $item.Add_Click($Action); $null=$Parent.Items.Add($item); return $item }
function Toggle-Startup {
 try {
  $state=Get-LumaStartup
  if ($state.Installed -and $state.Owned) {
   Disable-LumaStartup
   [Windows.MessageBox]::Show($window,'已关闭开机自动启动。当前窗口仍可继续使用。','浮音') | Out-Null
   return
  }
  $message="是否允许浮音在你登录 Windows、进入桌面后自动打开？`n`n只为当前用户添加启动快捷方式，不需要管理员权限。会显示歌词面板并恢复位置和风格，可随时在此菜单关闭。`n`n请将软件保留在下面的固定位置：`n$root`n`nWindows 可能会延迟启动，无法保证桌面出现的同一瞬间打开。"
  $answer=[Windows.MessageBox]::Show($window,$message,'允许开机自动启动？',[Windows.MessageBoxButton]::YesNo,[Windows.MessageBoxImage]::Question,[Windows.MessageBoxResult]::No)
  if ($answer -ne [Windows.MessageBoxResult]::Yes) { return }
  Enable-LumaStartup -ProgramRoot $root
  [Windows.MessageBox]::Show($window,'已开启，下次登录 Windows 后自动显示。若系统禁用了此启动项，请在 Windows 设置 → 应用 → 启动 中允许它。','浮音') | Out-Null
 } catch { [Windows.MessageBox]::Show($window,$_.Exception.Message,'无法更改自启动设置') | Out-Null }
}
function Start-NeteaseAdapter([bool]$Remove){
 $dialog=[Microsoft.Win32.OpenFileDialog]::new();$dialog.Filter='网易云音乐 (cloudmusic.exe)|cloudmusic.exe';$dialog.Title='选择网易云安装目录中的 cloudmusic.exe'
 $running=Get-Process cloudmusic -ErrorAction SilentlyContinue | Select-Object -First 1
 if($running.Path){$dialog.InitialDirectory=[IO.Path]::GetDirectoryName($running.Path)}
 if(-not $dialog.ShowDialog($window)){return}
 $prompt=if($Remove){'移除由浮音安装的网易云适配组件？请先完全退出网易云。'}else{'将安装 BetterNCM 1.3.4 与 InfLink-rs 3.4.0，补齐网易云播放进度和歌曲编号。需要从 GitHub 下载组件，安装后重启网易云。已有其他版本时不会覆盖。是否继续？'}
 if([Windows.MessageBox]::Show($window,$prompt,'浮音 · 网易云适配','YesNo','Question','No') -ne 'Yes'){return}
 $shell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $action=if($Remove){'-Uninstall'}else{'-Install'}
 $arguments='-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+(Join-Path $root 'NeteaseAdapter.ps1')+'" '+$action+' -ProgramRoot "'+[IO.Path]::GetDirectoryName($dialog.FileName)+'"'
 Start-Process -FilePath $shell -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden
}
function Refresh-MenuState($Parent){
 foreach($item in $Parent.Items){
  if($item -isnot [Windows.Controls.MenuItem]){continue}
  switch([string]$Parent.Header){
   '界面风格' {$item.IsChecked=$item.Tag -eq $settings.Theme}
   '字体变色' {if($item.Tag -in @('White','Word','Line')){$item.IsChecked=$item.Tag -eq $settings.LyricMode}elseif($item.IsCheckable){$item.IsChecked=$item.Tag -eq $settings.LyricColor}}
   '进度条颜色' {$item.IsChecked=$item.Tag -eq $settings.ProgressColor}
   '背景通透度' {$item.IsChecked=$item.Tag -eq $settings.Tint}
  }
  if($item.Header -eq '游戏模式'){$item.IsChecked=[bool]$settings.GameMode}
  elseif($item.Header -eq 'Spotify 本机播放快速响应'){$item.IsChecked=[bool]$settings.SpotifyLocal}
  elseif($item.Header -eq '背景通透度'){$item.IsEnabled=[bool]$settings.Acrylic}
  elseif($item.Header -eq '固定位置'){$item.IsChecked=[bool]$settings.Locked}
  elseif($item.Header -eq '亚克力模糊'){$item.IsChecked=[bool]$settings.Acrylic}
  elseif($item.Header -like '歌词时间微调*'){$item.Header=('歌词时间微调  {0:+0.0;-0.0;0.0}s' -f $settings.Offset)}
  Refresh-MenuState $item
 }
}
function Open-Menu {
 if($script:activeMenu -and $script:activeMenu.IsOpen){$script:activeMenu.IsOpen=$false;return}
 $menu=New-Object Windows.Controls.ContextMenu
 $menu.StaysOpen=$false
 $menu.AddHandler([Windows.Controls.MenuItem]::ClickEvent,[Windows.RoutedEventHandler]{param($sender,$eventArgs)
  Refresh-MenuState $sender
  if($eventArgs.OriginalSource.Header -notin @('关闭设置','退出浮音') -and $window.IsVisible -and -not $sender.IsOpen){$sender.IsOpen=$true}
 },$true)
 $menu.Add_PreviewMouseDown({param($sender,$eventArgs)
  $node=$eventArgs.OriginalSource
  while($node -and $node -ne $sender){
   if($node -is [Windows.Controls.MenuItem]){return}
   $parent=$null
   if($node -is [Windows.Media.Visual]){$parent=[Windows.Media.VisualTreeHelper]::GetParent($node)}
   if(-not $parent){$parent=[Windows.LogicalTreeHelper]::GetParent($node)}
   $node=$parent
  }
  $sender.IsOpen=$false
 })
 $more=New-Object Windows.Controls.MenuItem;$more.Header='更多设置'
 $null=Add-MenuItem $more '创建桌面快捷方式' {try{$path=New-FuyinDesktopShortcut $root;[Windows.MessageBox]::Show($window,('已创建：'+$path),'浮音') | Out-Null}catch{[Windows.MessageBox]::Show($window,$_.Exception.Message,'浮音') | Out-Null}}
 $versionItem=Add-MenuItem $menu 'v1.31' {}; $versionItem.IsEnabled=$false
 $gameItem=Add-MenuItem $menu '游戏模式' {Toggle-GameMode}; $gameItem.IsCheckable=$true; $gameItem.IsChecked=[bool]$settings.GameMode
 $gameItem.ToolTip='暂停音乐时渐出隐藏，恢复播放后渐入显示。'
 $localItem=Add-MenuItem $more 'Spotify 本机播放快速响应' {$settings.SpotifyLocal=-not $settings.SpotifyLocal;$shared.SpotifyLocal=[bool]$settings.SpotifyLocal;Save-Settings}; $localItem.IsCheckable=$true; $localItem.IsChecked=[bool]$settings.SpotifyLocal
 $localItem.ToolTip='本机播放时跟随音频流开关；Spotify Connect 播放到其他设备时请关闭。'
 foreach($resource in @('ButtonInk','HoverFill','MenuFill','FrameStroke','MenuDisabled','MenuStroke','MenuMaxHeight','FocusStroke','PressFill')){$menu.Resources[$resource]=$window.Resources[$resource]}
 foreach($controlType in @([type][Windows.Controls.ContextMenu],[type][Windows.Controls.MenuItem],[type][Windows.Controls.Separator],[type][Windows.Controls.ToolTip])){$menu.Resources[$controlType]=$window.FindResource($controlType)}
 $menu.Style=$window.FindResource([type][Windows.Controls.ContextMenu])
 $styles=New-Object Windows.Controls.MenuItem; $styles.Header='界面风格'; $null=$menu.Items.Add($styles)
 foreach($choice in @(@{Id='Pearl';Name='月白 · 通透亚克力'},@{Id='Mist';Name='雾蓝 · 清冷玻璃'},@{Id='Night';Name='深夜 · 深色亚克力'})) {
  $item=New-Object Windows.Controls.MenuItem; $item.Header=$choice.Name; $item.Tag=$choice.Id; $item.IsCheckable=$true; $item.IsChecked=$settings.Theme -eq $choice.Id
  $item.Add_Click({param($sender,$eventArgs) $settings.Theme=$sender.Tag; Apply-Theme; Save-Settings})
  $null=$styles.Items.Add($item)
 }
 $lyricSettings=New-Object Windows.Controls.MenuItem;$lyricSettings.Header='字体变色';$null=$menu.Items.Add($lyricSettings)
 foreach($choice in @(@{Id='White';Name='纯白不变色（默认）'},@{Id='Word';Name='逐字变色（自动）'},@{Id='Line';Name='整句变色'})){
  $item=New-Object Windows.Controls.MenuItem;$item.Header=$choice.Name;$item.Tag=$choice.Id;$item.IsCheckable=$true;$item.IsChecked=$settings.LyricMode -eq $choice.Id
  $item.Add_Click({param($sender,$eventArgs) $settings.LyricMode=$sender.Tag;Apply-Theme;Save-Settings});$null=$lyricSettings.Items.Add($item)
 }
 $null=$lyricSettings.Items.Add((New-Object Windows.Controls.Separator))
 foreach($choice in @(@{Id='Theme';Name='跟随界面风格'},@{Id='Mint';Name='薄荷绿'},@{Id='Blue';Name='晴空蓝'},@{Id='Violet';Name='鸢尾紫'},@{Id='Rose';Name='玫瑰粉'},@{Id='Amber';Name='琥珀金'})){
  $item=New-Object Windows.Controls.MenuItem;$item.Header=$choice.Name;$item.Tag=$choice.Id;$item.IsCheckable=$true;$item.IsChecked=$settings.LyricColor -eq $choice.Id
  $item.Add_Click({param($sender,$eventArgs) $settings.LyricColor=$sender.Tag;Save-Settings});$null=$lyricSettings.Items.Add($item)
 }
 $customLyric=Add-MenuItem $lyricSettings '自定义颜色…' {
  $dialog=[Windows.Forms.ColorDialog]::new();$dialog.FullOpen=$true;$dialog.Color=[Drawing.ColorTranslator]::FromHtml($settings.LyricCustom)
  try{
   if($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK){
    $settings.LyricCustom=('#{0:X2}{1:X2}{2:X2}' -f $dialog.Color.R,$dialog.Color.G,$dialog.Color.B);$settings.LyricColor='Custom'
    if($settings.LyricMode -eq 'White'){$settings.LyricMode='Line'}
    Save-Settings
   }
  }finally{$dialog.Dispose()}
 }
 $customLyric.IsCheckable=$true;$customLyric.IsChecked=$settings.LyricColor -eq 'Custom'
 $customLyric.Tag='Custom'
 $lyricSettings.ToolTip='自动逐字优先真实时间，无真实时间时整句持续预测；保留歌词原文与句时间。'
 $progressSettings=New-Object Windows.Controls.MenuItem;$progressSettings.Header='进度条颜色';$null=$menu.Items.Add($progressSettings)
 foreach($choice in @(@{Id='Theme';Name='跟随界面风格（默认）'},@{Id='White';Name='纯白'},@{Id='Mint';Name='薄荷绿'},@{Id='Blue';Name='晴空蓝'},@{Id='Violet';Name='鸢尾紫'},@{Id='Rose';Name='玫瑰粉'},@{Id='Amber';Name='琥珀金'})){
  $item=New-Object Windows.Controls.MenuItem;$item.Header=$choice.Name;$item.Tag=$choice.Id;$item.IsCheckable=$true;$item.IsChecked=$settings.ProgressColor -eq $choice.Id
  $item.Add_Click({param($sender,$eventArgs) $settings.ProgressColor=$sender.Tag;Apply-Theme;Save-Settings});$null=$progressSettings.Items.Add($item)
 }
 $customProgress=Add-MenuItem $progressSettings '自定义颜色…' {
  $dialog=[Windows.Forms.ColorDialog]::new();$dialog.FullOpen=$true;$dialog.Color=[Drawing.ColorTranslator]::FromHtml($settings.ProgressCustom)
  try{
   if($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK){
    $settings.ProgressCustom=('#{0:X2}{1:X2}{2:X2}' -f $dialog.Color.R,$dialog.Color.G,$dialog.Color.B)
    $settings.ProgressColor='Custom';Apply-Theme;Save-Settings
   }
  }finally{$dialog.Dispose()}
 }
 $customProgress.IsCheckable=$true;$customProgress.IsChecked=$settings.ProgressColor -eq 'Custom'
 $customProgress.Tag='Custom'
 $transparency=New-Object Windows.Controls.MenuItem; $transparency.Header='背景通透度'; $transparency.IsEnabled=[bool]$settings.Acrylic; $null=$menu.Items.Add($transparency)
 foreach($choice in @(@{Value=12;Name='更透明'},@{Value=28;Name='均衡（默认）'},@{Value=55;Name='更浓的磨砂'})) {
  $item=New-Object Windows.Controls.MenuItem; $item.Header=$choice.Name; $item.Tag=$choice.Value; $item.IsCheckable=$true; $item.IsChecked=$settings.Tint -eq $choice.Value
  $item.Add_Click({param($sender,$eventArgs) $settings.Tint=[int]$sender.Tag; Apply-Theme; Save-Settings})
  $null=$transparency.Items.Add($item)
 }
 $positionItem=Add-MenuItem $menu '固定位置' {Toggle-Lock};$positionItem.IsCheckable=$true;$positionItem.IsChecked=[bool]$settings.Locked
 $acrylicItem=Add-MenuItem $menu '亚克力模糊' {$settings.Acrylic=-not $settings.Acrylic; Apply-Glass; Save-Settings};$acrylicItem.IsCheckable=$true;$acrylicItem.IsChecked=[bool]$settings.Acrylic
 $glassInfo=Add-MenuItem $more ('背景引擎：'+$script:glassStatus) {}; $glassInfo.IsEnabled=$false
 $sources=New-Object Windows.Controls.MenuItem; $sources.Header='音乐来源'; $null=$menu.Items.Add($sources)
 $adapters=New-Object Windows.Controls.MenuItem;$adapters.Header='播放器适配';$null=$more.Items.Add($adapters)
 $null=Add-MenuItem $adapters '网易云：播放进度增强（64 位）…' {Start-NeteaseAdapter $false}
 $null=Add-MenuItem $adapters '卸载浮音安装的网易云适配…' {Start-NeteaseAdapter $true}
 $null=Add-MenuItem $adapters 'QQ 音乐：连接设置说明' {[Windows.MessageBox]::Show($window,'QQ 音乐需开启：设置 → 常规设置 → 通知 → 显示系统媒体传输控件（SMTC）。完整时间轴建议使用 21.10.2962 及以上版本。开启后完全退出并重开 QQ 音乐。','浮音 · QQ 音乐适配') | Out-Null}
 $null=Add-MenuItem $sources '自动选择正在播放的应用' {$shared.Source=''; $shared.Reload=$true; $script:demoMode=$false}
 if ($script:current) { foreach ($source in $script:current.Sources) { $item=New-Object Windows.Controls.MenuItem; $item.Header=(Friendly-Source $source)+$(if($source -like 'native:*'){'（仅音频，缺少进度）'}else{''}); $item.Tag=$source; $item.Add_Click({param($sender,$eventArgs) $shared.Source=$sender.Tag; $shared.Reload=$true; $script:demoMode=$false}); $null=$sources.Items.Add($item) } }
 $null=$menu.Items.Add((New-Object Windows.Controls.Separator))
 $null=Add-MenuItem $menu '导入当前歌曲的 LRC…' {Import-Lrc}
 $null=Add-MenuItem $menu '重新获取歌词' {$shared.Reload=$true}
 $offsetMenu=New-Object Windows.Controls.MenuItem; $offsetMenu.Header=('歌词时间微调  {0:+0.0;-0.0;0.0}s' -f $settings.Offset); $null=$menu.Items.Add($offsetMenu)
 $null=Add-MenuItem $offsetMenu '歌词提前 0.5 秒' {$settings.Offset=[Math]::Round($settings.Offset+0.5,1); Save-Settings}
 $null=Add-MenuItem $offsetMenu '歌词提前 0.1 秒' {$settings.Offset=[Math]::Round($settings.Offset+0.1,1); Save-Settings}
 $null=Add-MenuItem $offsetMenu '歌词延后 0.1 秒' {$settings.Offset=[Math]::Round($settings.Offset-0.1,1); Save-Settings}
 $null=Add-MenuItem $offsetMenu '歌词延后 0.5 秒' {$settings.Offset=[Math]::Round($settings.Offset-0.5,1); Save-Settings}
 $null=Add-MenuItem $offsetMenu '重置微调' {$settings.Offset=0.0; Save-Settings}
 $sizeMenu=New-Object Windows.Controls.MenuItem; $sizeMenu.Header='面板宽度'; $null=$menu.Items.Add($sizeMenu)
 foreach ($size in @(520,620,760)) { $item=New-Object Windows.Controls.MenuItem; $item.Header="$size px"; $item.Tag=$size; $item.Add_Click({param($sender,$eventArgs) $window.Width=[double]$sender.Tag; Save-Settings}); $null=$sizeMenu.Items.Add($item) }
 $null=Add-MenuItem $more $(if($script:demoMode){'退出演示，连接播放器'}else{'预览动画与界面（演示）'}) {$script:demoMode=-not $script:demoMode; $script:demoStart=[DateTime]::UtcNow}
 $null=$menu.Items.Add((New-Object Windows.Controls.Separator))
 $null=Add-MenuItem $menu '退出浮音' {$window.Close()}
 $startupItem=Add-MenuItem $menu '开机自动启动…' {Toggle-Startup}
 $startupItem.IsCheckable=$true
 try {
  $startupState=Get-LumaStartup
  $startupItem.IsChecked=$startupState.Owned
  $startupItem.ToolTip='需确认后开启；登录 Windows 后自动显示面板。系统可能延迟启动。'
  if($startupState.Owned -and $startupState.Target -ne (Join-Path $root 'Luma.exe')){$startupItem.ToolTip+=' 当前启动项指向旧路径，请关闭后重新开启。'}
 } catch { $startupItem.IsEnabled=$false; $startupItem.ToolTip=$_.Exception.Message }
 $closeItem=Add-MenuItem $menu '关闭设置' {$script:activeMenu.IsOpen=$false}
 # Keep everyday appearance and lyric controls visible; secondary setup lives one level down.
 $importItem=$menu.Items | Where-Object {$_.Header -eq '导入当前歌曲的 LRC…'} | Select-Object -First 1
 $reloadItem=$menu.Items | Where-Object {$_.Header -eq '重新获取歌词'} | Select-Object -First 1
 $exitItem=$menu.Items | Where-Object {$_.Header -eq '退出浮音'} | Select-Object -First 1
 $menu.Items.Clear()
 foreach($entry in @($versionItem,$styles,$lyricSettings,$progressSettings,$transparency,$acrylicItem,$sizeMenu,$null,$gameItem,$positionItem,$sources,$null,$importItem,$reloadItem,$offsetMenu,$null,$startupItem,$more,$null,$closeItem,$exitItem)){
  if($null -eq $entry){$null=$menu.Items.Add((New-Object Windows.Controls.Separator))}else{$null=$menu.Items.Add($entry)}
 }
 $menu.PlacementTarget=$ui.Menu; $menu.IsOpen=$true; $script:activeMenu=$menu
}
$ui.Lock.Add_Click({Toggle-Lock})
$ui.Menu.Add_Click({Open-Menu})
$ui.Hide.Add_Click({$script:manualHidden=$true; Set-PanelVisibility $false})
$window.Add_MouseRightButtonUp({Open-Menu})
$window.Add_MouseLeftButtonDown({param($sender,$eventArgs) if (-not $settings.Locked -and $eventArgs.ChangedButton -eq 'Left') { try {$window.DragMove(); Save-Settings} catch {} }})
$window.Add_SourceInitialized({Apply-Glass})
$window.Add_SizeChanged({Apply-Glass})
$window.Add_Loaded({
 $area=[Windows.SystemParameters]::WorkArea
 $window.Left=if($null -ne $settings.Left){[double]$settings.Left}else{$area.Left+($area.Width-$window.Width)/2}
 $window.Top=if($null -ne $settings.Top){[double]$settings.Top}else{$area.Bottom-$window.Height-44}
 # Restore safely after monitors are disconnected; preserve negative coordinates on existing monitors.
 $screens=[Windows.Forms.Screen]::AllScreens
 $visible=$false
 $dpi=[Windows.PresentationSource]::FromVisual($window).CompositionTarget.TransformToDevice.M11
 foreach($screen in $screens) { $r=$screen.WorkingArea; if(($window.Left+$window.Width)*$dpi -gt $r.Left+50 -and $window.Left*$dpi -lt $r.Right-50 -and ($window.Top+50)*$dpi -gt $r.Top -and $window.Top*$dpi -lt $r.Bottom-30){$visible=$true} }
 if(-not $visible){$window.Left=$area.Left+($area.Width-$window.Width)/2; $window.Top=$area.Bottom-$window.Height-44}
 Update-LockIcon
 Apply-Glass
})
$tray=New-Object Windows.Forms.NotifyIcon
$script:brandIcon=[Drawing.Icon]::new((Join-Path $root 'Fuyin.ico'),[Drawing.Size]::new(32,32))
$tray.Icon=$script:brandIcon; $tray.Text='浮音 · Luma'; $tray.Visible=-not $SelfTest
$trayMenu=New-Object Windows.Forms.ContextMenuStrip
$showItem=$trayMenu.Items.Add('显示浮音'); $showItem.Add_Click({Show-PanelFromTray})
$unlockItem=$trayMenu.Items.Add('解锁并显示'); $unlockItem.Add_Click({$settings.Locked=$true; Toggle-Lock; Show-PanelFromTray})
$trayGame=$trayMenu.Items.Add('游戏模式'); $trayGame.CheckOnClick=$false; $trayGame.Add_Click({Toggle-GameMode})
$trayMenu.Add_Opening({$trayGame.Checked=[bool]$settings.GameMode})
$exitItem=$trayMenu.Items.Add('退出'); $exitItem.Add_Click({$window.Close()})
$tray.ContextMenuStrip=$trayMenu; $tray.Add_DoubleClick({Show-PanelFromTray})
if (-not $SelfTest -or $LiveMedia) {
 if($InspectUI){Write-Output 'Starting media worker'}
 $script:worker=[PowerShell]::Create()
 $null=$script:worker.AddScript([IO.File]::ReadAllText("$root\MediaWorker.ps1")).AddArgument($shared).AddArgument($root).AddArgument((Join-Path $dataDir 'lyrics'))
 $script:job=$script:worker.BeginInvoke()
 $script:transportWorker=[PowerShell]::Create()
 $null=$script:transportWorker.AddScript([IO.File]::ReadAllText("$root\TransportWorker.ps1")).AddArgument($shared).AddArgument($root)
 $script:transportJob=$script:transportWorker.BeginInvoke()
 if($InspectUI){Write-Output 'Media worker started'}
}
$demoRows=@(ConvertFrom-Lrc "[00:00.00]让音乐，浮在此刻。`n[00:04.00]把日常调成喜欢的频率`n[00:08.00]光落在音符之间`n[00:12.00]下一句，与你相遇`n[00:16.00]每一刻，都有自己的旋律")
$timer=New-Object Windows.Threading.DispatcherTimer; $timer.Interval=[TimeSpan]::FromMilliseconds(33)
$timer.Add_Tick({
 try {
  $now=[DateTime]::UtcNow; $delta=[Math]::Min(.25,($now-$script:lastFrame).TotalSeconds); $script:lastFrame=$now
  if($script:demoMode){$s=@{Key='demo';Title='浮音 · 原创界面演示';Artist='Luma';Source='DEMO / 演示模式';Sources=@();Rows=$demoRows;Cover=$null;Position=(([DateTime]::UtcNow-$script:demoStart).TotalSeconds%20);Duration=20;Playing=$true;Status='演示';At=[DateTime]::UtcNow}}
  else {$s=Get-LumaLiveSnapshot $shared.Snapshot $shared.Transport ([Diagnostics.Stopwatch]::GetTimestamp()) ([double][Diagnostics.Stopwatch]::Frequency)}
  if (-not $s) { Update-GameVisibility $false; $ui.Source.Text=if($shared.Error){'连接失败 · '+$shared.Error}else{'正在连接 Windows 媒体会话…'}; return }
  if(-not $script:demoMode -and -not $s.TransportFresh -and $script:presentedKey -eq $s.Key){$s.Position=$script:presentedPosition}
  $gamePlaying=[bool]$s.Playing
  if($SelfTest -and -not $LiveMedia -and $null -ne $script:gameTestPlaying){$gamePlaying=$script:gameTestPlaying}
  Update-GameVisibility $gamePlaying
  $script:current=$s
  Update-Ambience $delta ([bool]$s.Playing)
  $ui.Track.Text=$s.Title+$(if($s.Artist){'  ·  '+$s.Artist}else{''}); $ui.Track.ToolTip=$ui.Track.Text
  $position=[double]$s.Position
  if($s.Playing -and $s.Tick){$position+=[Math]::Max(0.0,([Diagnostics.Stopwatch]::GetTimestamp()-$s.Tick)/[double][Diagnostics.Stopwatch]::Frequency)*[double]$s.Rate}
  if($s.Duration -gt 0){$position=[Math]::Min($s.Duration,$position)}
  if($s.Tick -and $s.Playing -and $script:presentedPlaying -and $script:presentedKey -eq $s.Key -and $script:presentedSeek -eq $s.SeekSerial){$position=[Math]::Max([double]$script:presentedPosition,$position)}
  $script:presentedKey=$s.Key; $script:presentedSeek=$s.SeekSerial; $script:presentedPosition=$position; $script:presentedPlaying=[bool]$s.Playing
  $index=Get-LyricIndex $s.Rows ($position+[double]$settings.Offset)
  if($s.TimelineUnavailable){
   $timelineHint=if($s.Source -like 'native:*'){'播放器未提供系统媒体进度 · 请查看播放器适配'}else{'已连接 SMTC，但播放器未提供同步进度 · 请查看播放器适配'}
   if($s.Status -match '网络|获取|重试'){$timelineHint=$s.Status+'；等待播放器进度'}
   Show-Lyric $(if($s.Rows.Count){'歌词已获取 · 等待播放器进度'}else{'等待同步歌词和进度'}) $timelineHint
  }
  elseif($index -ge 0){$next=if($index+1 -lt $s.Rows.Count){$s.Rows[$index+1].Text}else{'♪'}; Show-Lyric $s.Rows[$index].Text $next; $lineEnd=if($index+1 -lt $s.Rows.Count){$s.Rows[$index+1].Time}elseif($s.Duration -gt $s.Rows[$index].Time){$s.Duration}else{$s.Rows[$index].Time+5}; Update-Karaoke $s.Rows[$index] $lineEnd ($position+[double]$settings.Offset)}
  elseif($s.Rows.Count){Show-Lyric '♪  前奏' $s.Rows[0].Text}
  elseif($s.Key){Show-Lyric '听见每一刻' $s.Status}
  else {Show-Lyric '让音乐，浮在此刻。' $s.Status}
  $ui.Dot.Opacity=if($s.Playing){1}else{0.35}
  $ui.Source.Text=if($s.Source){(Friendly-Source $s.Source)+$(if($s.Playing){'  /  正在播放'}else{'  /  已暂停'})}else{'LUMA / 等待播放器'}
  if($shared.Error -and -not $script:demoMode){$ui.Source.Text='媒体连接异常 · '+$shared.Error}
  $ui.Source.ToolTip=if($s.LocalAudio){$ui.Source.Text+' · 本机音频流快速响应'}elseif($shared.AudioError){$ui.Source.Text+' · 本机检测不可用，已回退系统媒体状态'}else{$ui.Source.Text}
  $ui.Time.Text=if($s.Duration -gt 0){'{0:mm\:ss} / {1:mm\:ss}' -f [TimeSpan]::FromSeconds([Math]::Max(0.0,$position)),[TimeSpan]::FromSeconds($s.Duration)}else{'--:--'}
  $ui.Progress.Width=if($s.Duration -gt 0){[Math]::Max(0.0,$ui.ProgressTrack.ActualWidth*[Math]::Min(1.0,$position/$s.Duration))}else{0}
  if($script:lastCoverKey -ne $s.Key -or -not [object]::ReferenceEquals($script:lastCover,$s.Cover)){
   $script:lastCoverKey=$s.Key; $script:lastCover=$s.Cover; $ui.Cover.Source=$null
   if($s.Cover){try{$stream=[IO.MemoryStream]::new([byte[]]$s.Cover); $bitmap=New-Object Windows.Media.Imaging.BitmapImage; $bitmap.BeginInit(); $bitmap.CacheOption='OnLoad'; $bitmap.StreamSource=$stream; $bitmap.EndInit(); $bitmap.Freeze(); $ui.Cover.Source=$bitmap; $stream.Dispose(); $ui.CoverFrame.ToolTip='播放器原始专辑封面'; $pixel=[Windows.Media.Imaging.FormatConvertedBitmap]::new([Windows.Media.Imaging.TransformedBitmap]::new($bitmap,[Windows.Media.ScaleTransform]::new(1.0/$bitmap.PixelWidth,1.0/$bitmap.PixelHeight)),[Windows.Media.PixelFormats]::Bgra32,$null,0); $bytes=[byte[]]::new(4); $pixel.CopyPixels($bytes,4,0); $script:artColor=[Windows.Media.Color]::FromRgb($bytes[2],$bytes[1],$bytes[0])}catch{$ui.CoverFrame.ToolTip='封面解码失败：'+$_.Exception.Message}}
   else{$ui.CoverFrame.ToolTip=if($shared.CoverError){'封面读取失败：'+$shared.CoverError}else{'播放器尚未提供专辑封面'}}
   $ui.CoverLabel.Text=if($s.Cover){'N O W   P L A Y I N G'}else{'L U M A'}
  }
 } catch { $ui.Source.Text='界面更新异常'; $shared.Error=$_.Exception.Message }
})
$window.Add_Closed({$timer.Stop(); $shared.Stop=$true; $tray.Visible=$false; $tray.Dispose(); $script:brandIcon.Dispose(); Save-Settings; $app.Shutdown()})
if($SelfTest){
 if(-not $LiveMedia){
  $script:testOriginalGameMode=$settings.GameMode; $settings.GameMode=$true; $script:gameTestPlaying=$false; $script:gameTestStage=0
  $gameTestTimer=[Windows.Threading.DispatcherTimer]::new(); $gameTestTimer.Interval=[TimeSpan]::FromMilliseconds(800)
  $gameTestTimer.Add_Tick({
   if($script:gameTestStage -eq 0){
    if($window.IsVisible){throw 'Game mode failed to hide after pause fade'}
    $script:gameTestPlaying=$true
   }elseif($script:gameTestStage -eq 1){
    if(-not $window.IsVisible -or $window.Opacity -lt .99){throw 'Game mode failed to fade back in'}
    Update-GameVisibility $false; Update-GameVisibility $true
   }else{
    if(-not $window.IsVisible -or -not $script:wantVisible){throw 'Rapid reversal left panel hidden'}
    $gameTestTimer.Stop(); $settings.GameMode=$script:testOriginalGameMode; $script:gameTestPlaying=$null; $script:gameTestPassed=$true
   }
   $script:gameTestStage++
  }); $window.Add_Loaded({$gameTestTimer.Start()})
 }
 $testRows=@(ConvertFrom-Lrc "[offset:100]`n[00:01.50][00:03.00]A`n[00:02.125]B")
 if($testRows.Count -ne 3 -or [Math]::Abs($testRows[0].Time-1.4) -gt .0001 -or (Get-LyricIndex $testRows 2.1) -ne 1 -or (Get-LyricIndex $testRows 0) -ne -1){throw 'LRC parser test failed'}
 $script:demoMode=-not $LiveMedia
 $testTimer=New-Object Windows.Threading.DispatcherTimer; $testTimer.Interval=[TimeSpan]::FromSeconds($(if($LiveMedia){12}else{4}))
 $testTimer.Add_Tick({
  $testTimer.Stop()
  if(-not $LiveMedia -and -not $script:gameTestPassed){throw 'Game visibility lifecycle test did not finish'}
  $precise=@(ConvertFrom-Lrc '[00:01.00]<00:01.00>你<00:02.00>好')
  $wordData=ConvertTo-KaraokeWords $precise[0] 3
  if(-not $wordData.Exact -or $wordData.Words.Count -ne 2 -or $wordData.Words[1].Time -ne 2){throw 'Enhanced LRC word timing failed'}
  if(-not $LiveMedia){
   $savedLyricMode=$settings.LyricMode;$savedLyricColor=$settings.LyricColor;$settings.LyricMode='Word'
   $held=@(ConvertFrom-Lrc '[1000,2600](1000,2000,0)长(3200,200,0)音')
   Show-Lyric $held[0].Text ''
   Update-Karaoke $held[0] 4 2.9
   if(-not $script:karaokeExact -or $script:wordRuns.Count -ne 2 -or $script:lastHighlight -ne '0:0'){throw 'YRC long syllable did not reach the WPF highlighter'}
   Update-Karaoke $held[0] 4 3.1
   if($script:lastHighlight -ne '-1:1'){throw 'YRC rest did not clear active word'}
   Update-Karaoke $held[0] 4 3.25
   if($script:lastHighlight -ne '1:1'){throw 'YRC next word did not highlight on time'}
   $previewWords=@(ConvertFrom-Lrc '[1000,2000](1000,1000,0)音(2000,1000,0)符')
   Update-Karaoke $previewWords[0] 3 1.5
   $ui.Lyric.Measure([Windows.Size]::new(10000,10000));$originalTextWidth=$ui.Lyric.DesiredSize.Width
   Update-Karaoke $previewWords[0] 3 1.98
   $ui.Lyric.Measure([Windows.Size]::new(10000,10000))
   if($script:wordRuns[1].Foreground.Color -ne [Windows.Media.ColorConverter]::ConvertFromString($script:palette.Muted)){throw 'Exact timing was changed by prediction'}
   if([Math]::Abs($originalTextWidth-$ui.Lyric.DesiredSize.Width) -gt .001 -or (($script:wordRuns | ForEach-Object {$_.Text}) -join '') -ne '音符'){throw 'Prediction changed lyric width or text'}
   $english=@(ConvertFrom-Lrc '[00:01.00]Hold on tonight')
   Show-Lyric $english[0].Text ''
   Update-Karaoke $english[0] 5 1.1
   if($script:karaokeUnavailable -or $script:karaokeExact -or -not $script:karaokeEstimated -or $script:wordRuns.Count -ne 3 -or $script:lastHighlight -ne '0:0'){throw 'Automatic word mode did not predict missing English timing'}
   Update-Karaoke $english[0] 5 4.99
   if($script:lastHighlight -ne '2:2'){throw 'English prediction did not reach the last word'}
   $plainChinese=@(ConvertFrom-Lrc '[00:01.00]音符')
   $predictedData=Get-LumaKaraokeData $plainChinese[0] 3 'Word'
   Update-Karaoke $plainChinese[0] 3 ($predictedData.Words[1].Time-.02)
   if($script:wordRuns.Count -ne 2 -or $script:wordRuns[1].Foreground.Color -eq [Windows.Media.ColorConverter]::ConvertFromString($script:palette.Muted)){throw 'Missing Chinese timing did not receive predicted color'}
   $settings.LyricMode='Line';$settings.LyricColor='Rose'
   Update-Karaoke $held[0] 4 2.9
   if($script:wordRuns.Count -ne 1 -or $script:karaokeUnavailable -or $script:lastHighlight -ne '0:0'){throw 'Whole-line mode did not override precise words'}
   $settings.LyricMode='Word';$settings.LyricColor='Blue'
   Update-Karaoke $held[0] 4 2.9
   if($script:wordRuns.Count -ne 2 -or -not $script:karaokeExact){throw 'Switching back did not restore exact words'}
   $settings.LyricMode='White'
   foreach($whitePosition in @(1.1,2.9,3.3)){
    Update-Karaoke $held[0] 4 $whitePosition
    if($script:wordRuns.Count -ne 1 -or $script:wordRuns[0].Foreground.Color -ne [Windows.Media.Colors]::White -or $script:wordRuns[0].Foreground.HasAnimatedProperties){throw 'White mode changed color with playback'}
    if($ui.Next.Opacity -ne 0.58 -or $ui.Next.Foreground.Color -ne [Windows.Media.Colors]::White){throw 'Next line should remain dimmer than current line in white mode'}
   }
   $settings.LyricMode=$savedLyricMode;$settings.LyricColor=$savedLyricColor;$script:karaokeKey=''
  }
  Update-Ambience 1 $true
  if(-not $script:discPlaying -or -not $script:rotationClock){throw 'Rotation clock not running'}
  if(-not $ui.Disc.RenderTransform.HasAnimatedProperties){throw 'Record must use a WPF animation clock'}
  if($ui.CoverFrame.BorderThickness.Left -ne 0 -or $ui.CoverViewport.Clip.RadiusX -ne 50 -or $ui.Disc.Clip){throw 'Cover circle must stay stationary while album image rotates'}
  if([Windows.Media.RenderOptions]::GetBitmapScalingMode($ui.Cover) -ne [Windows.Media.BitmapScalingMode]::HighQuality -or $ui.Cover.UseLayoutRounding){throw 'Cover must use high-quality scaling without snapping the rotating image'}
  foreach($run in $script:wordRuns){if($run.TextDecorations.Count){throw 'Karaoke must not have underlines'}}
  Update-Ambience 1 $false
  if($script:discPlaying){throw 'Paused record must stay still'}
  $originalTheme=$settings.Theme; $originalTint=$settings.Tint
  foreach($themeId in @('Pearl','Mist','Night')){
   $settings.Theme=$themeId; Apply-Theme
   $expectedInk=if($settings.LyricMode -eq 'White'){[Windows.Media.Colors]::White}else{[Windows.Media.ColorConverter]::ConvertFromString($script:palette.Ink)}
   if($ui.Lyric.Foreground.Color -ne $expectedInk){throw 'Theme foreground mismatch'}
  }
  $settings.Tint=24; Apply-Theme; $lowTint=$script:glassTint
  Update-Ambience 0 $false; $lowAlpha=$ui.Shell.Background.GradientStops[0].Color.A
  $settings.Tint=72; Apply-Theme
  Update-Ambience 0 $false
  if($ui.Shell.Background.GradientStops[0].Color.A -le $lowAlpha){throw 'Visible background opacity did not change'}
  if($script:glassTint -eq $lowTint){throw 'Native tint did not change'}
  $settings.Theme=$originalTheme; $settings.Tint=$originalTint; Apply-Theme
  Save-Settings; $roundTrip=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
  if($roundTrip.Theme -ne $originalTheme -or $roundTrip.Tint -ne $originalTint){throw 'Theme settings did not persist'}
  if($roundTrip.LyricMode -ne $settings.LyricMode -or $roundTrip.LyricColor -ne $settings.LyricColor){throw 'Lyric appearance settings did not persist'}
  foreach($sourceTheme in @('Pearl','Mist','Night')){
   $settings.Theme=$sourceTheme;Apply-Theme
   $expectedSource=if($sourceTheme -eq 'Night'){'#F4F7FC'}elseif($sourceTheme -eq 'Mist'){'#102E3B'}else{'#192738'}
   if($ui.Source.Foreground.Color -ne [Windows.Media.ColorConverter]::ConvertFromString($expectedSource) -or $ui.Source.FontSize -lt 10.5 -or $ui.Source.FontWeight -ne [Windows.FontWeights]::SemiBold){throw 'Player source label is not legible'}
  }
  $settings.Theme=$originalTheme
  $oldFontColor=$settings.LyricColor;$oldFontCustom=$settings.LyricCustom
  $settings.LyricColor='Custom';$settings.LyricCustom='#E46C99';Save-Settings
  $fontSaved=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
  if($fontSaved.LyricColor -ne 'Custom' -or $fontSaved.LyricCustom -ne '#E46C99' -or $fontSaved.ProgressColor -ne $settings.ProgressColor){throw 'Custom font color was not saved independently'}
  $settings.LyricColor=$oldFontColor;$settings.LyricCustom=$oldFontCustom;Apply-Theme;Save-Settings
  $originalProgress=$settings.ProgressColor;$originalCustom=$settings.ProgressCustom
  foreach($preset in @('Theme','White','Mint','Blue','Violet','Rose','Amber','Custom')){
   $settings.ProgressColor=$preset;$settings.ProgressCustom='#12ABEF';Apply-Theme
   $expected=if($preset -eq 'Custom'){'#12ABEF'}elseif($preset -eq 'White'){'#FFFFFF'}else{Get-LumaLyricAccent $preset $settings.Theme $script:palette.Accent}
   if($ui.Progress.Background.Color -ne [Windows.Media.ColorConverter]::ConvertFromString($expected)){throw 'Progress color did not reach rendered bar'}
  }
  Save-Settings;$savedProgress=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
  if($savedProgress.ProgressColor -ne 'Custom' -or $savedProgress.ProgressCustom -ne '#12ABEF' -or $savedProgress.LyricColor -ne $settings.LyricColor){throw 'Independent progress color did not persist'}
  $settings.ProgressColor=$originalProgress;$settings.ProgressCustom=$originalCustom;Apply-Theme;Save-Settings
  $layoutWidth=$window.Width;$layoutTitle=$ui.Track.Text;$layoutMode=$settings.LyricMode
  $ui.Track.Text='很长的中文歌曲名称 / A long English recording title · 演唱者与合作歌手'
  foreach($testWidth in @(480,520,620,760,860)){
   $window.Width=$testWidth;$window.UpdateLayout()
   $titleEdge=$ui.Track.TranslatePoint([Windows.Point]::new($ui.Track.ActualWidth,0),$window).X
   $buttonsEdge=$ui.Lock.TranslatePoint([Windows.Point]::new(0,0),$window).X
   if($titleEdge -gt $buttonsEdge-7 -or $ui.Track.ActualWidth -lt 60){throw 'Long title overlaps toolbar or loses its usable width'}
   if($ui.ProgressTrack.ActualWidth -le 0 -or $ui.Source.ActualWidth -lt 100){throw 'Narrow panel clips metadata or progress track'}
  }
  $window.Width=$layoutWidth;$ui.Track.Text=$layoutTitle
  $settings.LyricMode='White';Apply-Theme
  if(-not $ui.Lyric.Effect -or $ui.Next.Opacity -ne .58){throw 'White lyric readability treatment missing'}
  $settings.LyricMode='Word';Apply-Theme
  if($ui.Lyric.Effect){throw 'White-only readability treatment changed word colors'}
  $settings.LyricMode=$layoutMode;Apply-Theme;$window.UpdateLayout()
  if($LiveMedia){
   if($shared.Error){throw $shared.Error}
   if($script:current.Key -and -not $script:current.TransportFresh){throw ('Independent playback monitor is not fresh: '+$shared.TransportError)}
   if($script:current.Cover -and -not $ui.Cover.Source){throw 'Live cover received but not rendered'}
   if($settings.SpotifyLocal -and $shared.AudioError){throw ('Local audio monitor failed: '+$shared.AudioError)}
   $script:testReport='Live media: cover bytes='+$script:current.Cover.Length+'; decoded='+[bool]$ui.Cover.Source+'; engine='+$script:glassStatus+'; transport fresh='+$script:current.TransportFresh+'; local audio='+[bool]$script:current.LocalAudio
  }
  if($Preview){
   if(-not $LiveMedia){
    $previewPosition=([DateTime]::UtcNow-$script:demoStart).TotalSeconds%20
    $previewIndex=Get-LyricIndex $demoRows $previewPosition
    if($previewIndex -ge 0){
     $previewEnd=if($previewIndex+1 -lt $demoRows.Count){$demoRows[$previewIndex+1].Time}else{20}
     $previewNext=if($previewIndex+1 -lt $demoRows.Count){$demoRows[$previewIndex+1].Text}else{''}
     Show-Lyric $demoRows[$previewIndex].Text $previewNext
     Update-Karaoke $demoRows[$previewIndex] $previewEnd $previewPosition
    }
   }
   $window.UpdateLayout()
   $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32); $bitmap.Render($window); $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder; $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap)); $file=[IO.File]::Create($Preview); $encoder.Save($file); $file.Dispose()
  }
  if($MenuPreview){
   function script:Save-MenuPreview($Element,[string]$Path){
    $Element.UpdateLayout()
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$Element.ActualWidth,[int]$Element.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($Element);$encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream=[IO.File]::Create($Path);try{$encoder.Save($stream)}finally{$stream.Dispose()}
   }
   $script:menuPreviewStage=0;$settings.Theme='Night';Apply-Theme;Open-Menu
   $script:menuRenderTimer=[Windows.Threading.DispatcherTimer]::new();$script:menuRenderTimer.Interval=[TimeSpan]::FromMilliseconds(350)
   $script:menuRenderTimer.Add_Tick({
    if($script:menuPreviewStage -eq 0){
     if(-not $script:activeMenu.Template -or $script:activeMenu.Background.Color.ToString() -ne '#FF222C3B'){throw 'Night menu template/background incorrect'}
     $enabled=$script:activeMenu.Items | Where-Object {$_ -is [Windows.Controls.MenuItem] -and $_.IsEnabled} | Select-Object -First 1
     if($enabled.Foreground.Color.ToString() -ne '#FFF4F7FC'){throw 'Night item foreground is not legible'}
     Save-MenuPreview $script:activeMenu ($MenuPreview+'-night.png')
     $script:previewSubmenu=$script:activeMenu.Items | Where-Object {$_.Header -eq '界面风格'} | Select-Object -First 1
     $script:previewSubmenu.IsSubmenuOpen=$true
    }elseif($script:menuPreviewStage -eq 1){
     $popup=$script:previewSubmenu.Template.FindName('PART_Popup',$script:previewSubmenu)
     if(-not $popup.IsOpen -or $script:previewSubmenu.Items[0].Foreground.Color.ToString() -ne '#FFF4F7FC'){throw 'Night submenu foreground/template incorrect'}
     if(-not @($script:activeMenu.Items | Where-Object {$_.Header -eq '更多设置'}).Count -or @($script:activeMenu.Items | Where-Object {$_.Header -like '背景引擎*'}).Count){throw 'Secondary settings were not grouped'}
     Save-MenuPreview $popup.Child ($MenuPreview+'-submenu.png')
     $styleClick=[Windows.Controls.MenuItem].GetMethod('OnClick',[Reflection.BindingFlags]'Instance,NonPublic')
     $null=$styleClick.Invoke($script:previewSubmenu.Items[0],@())
     $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background)
     if(-not $script:activeMenu.IsOpen -or $script:activeMenu.Resources['ButtonInk'].Color.ToString() -ne '#FF243246'){throw 'Open settings did not follow theme change'}
     $null=$styleClick.Invoke($script:previewSubmenu.Items[2],@())
     $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background)
     $script:previewSubmenu.IsSubmenuOpen=$false
     $script:previewSubmenu=$script:activeMenu.Items | Where-Object {$_.Header -eq '字体变色'} | Select-Object -First 1
     $script:previewSubmenu.IsSubmenuOpen=$true
    }elseif($script:menuPreviewStage -eq 2){
     $popup=$script:previewSubmenu.Template.FindName('PART_Popup',$script:previewSubmenu)
     if(-not $popup.IsOpen -or $script:previewSubmenu.Items.Count -ne 11){throw 'Lyric appearance submenu is missing mode/color entries'}
     Save-MenuPreview $popup.Child ($MenuPreview+'-lyrics.png')
     $lineChoice=$script:previewSubmenu.Items | Where-Object {$_.Tag -eq 'Line'} | Select-Object -First 1
     $blueChoice=$script:previewSubmenu.Items | Where-Object {$_.Tag -eq 'Blue'} | Select-Object -First 1
     $onClick=[Windows.Controls.MenuItem].GetMethod('OnClick',[Reflection.BindingFlags]'Instance,NonPublic')
     $null=$onClick.Invoke($lineChoice,@());$null=$onClick.Invoke($blueChoice,@())
     $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background)
     if(-not $script:activeMenu.IsOpen -or -not $lineChoice.StaysOpenOnClick -or -not $lineChoice.IsChecked -or -not $blueChoice.IsChecked){throw ('Setting click: open='+$script:activeMenu.IsOpen+'; stays='+$lineChoice.StaysOpenOnClick+'; line='+$lineChoice.IsChecked+'; blue='+$blueChoice.IsChecked)}
     $saved=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
     if($settings.LyricMode -ne 'Line' -or $settings.LyricColor -ne 'Blue' -or $saved.LyricMode -ne 'Line' -or $saved.LyricColor -ne 'Blue'){throw 'Menu mode/color actions failed to persist'}
     $script:previewSubmenu.IsSubmenuOpen=$false
     $script:previewSubmenu=$script:activeMenu.Items | Where-Object {$_.Header -eq '进度条颜色'} | Select-Object -First 1
     $script:previewSubmenu.IsSubmenuOpen=$true
    }elseif($script:menuPreviewStage -eq 3){
     $popup=$script:previewSubmenu.Template.FindName('PART_Popup',$script:previewSubmenu)
     if(-not $popup.IsOpen -or $script:previewSubmenu.Items.Count -ne 8){throw 'Progress color menu is missing choices'}
     Save-MenuPreview $popup.Child ($MenuPreview+'-progress.png')
     $rose=$script:previewSubmenu.Items | Where-Object {$_.Tag -eq 'Rose'} | Select-Object -First 1
     $onClick=[Windows.Controls.MenuItem].GetMethod('OnClick',[Reflection.BindingFlags]'Instance,NonPublic');$null=$onClick.Invoke($rose,@())
     $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background)
     if(-not $script:activeMenu.IsOpen -or -not $rose.IsChecked){throw 'Progress color click closed the menu'}
     $saved=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
     if($saved.ProgressColor -ne 'Rose' -or $saved.LyricColor -ne 'Blue'){throw 'Progress menu changed font color or failed to save'}
     $script:activeMenu.IsOpen=$false;$settings.Theme='Pearl';Apply-Theme;Open-Menu
    }else{
     Save-MenuPreview $script:activeMenu ($MenuPreview+'-pearl.png')
     $closeChoice=$script:activeMenu.Items | Where-Object {$_.Header -eq '关闭设置'} | Select-Object -First 1
     $onClick=[Windows.Controls.MenuItem].GetMethod('OnClick',[Reflection.BindingFlags]'Instance,NonPublic');$null=$onClick.Invoke($closeChoice,@())
     $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background)
     if($script:activeMenu.IsOpen){throw 'Explicit close-settings action did not close menu'}
     Open-Menu
     if($script:activeMenu.StaysOpen){throw 'Outside click must still dismiss settings'}
     $blank=[Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,0,[Windows.Input.MouseButton]::Left)
     $blank.RoutedEvent=[Windows.Input.Mouse]::PreviewMouseDownEvent;$blank.Source=$script:activeMenu;$script:activeMenu.RaiseEvent($blank)
     if($script:activeMenu.IsOpen){throw 'Blank menu area did not dismiss settings'}
     $script:menuRenderTimer.Stop();$window.Close()
    }
    $script:menuPreviewStage++
   });$script:menuRenderTimer.Start();return
  }
  $window.Close()
 }); $window.Add_Loaded({$testTimer.Start()})
}
$timer.Start()
if($InspectUI){Write-Output 'Opening WPF panel'}
$window.ShowActivated=$false
$app=[Windows.Application]::new(); $app.ShutdownMode='OnExplicitShutdown'
try {$null=$app.Run($window)} finally { $shared.Stop=$true; if($script:worker){$null=$script:worker.BeginStop($null,$null)}; if($script:transportWorker){$null=$script:transportWorker.BeginStop($null,$null)} }
if($SelfTest){if($shared.Error){throw $shared.Error}; Write-Output $script:testReport; if(-not $LiveMedia){Write-Output ('Game fade lifecycle verified: '+[bool]$script:gameTestPassed)}; Write-Output 'PASS: theme, tint, settings, word timing, rotation, pause, UI timer.'}
