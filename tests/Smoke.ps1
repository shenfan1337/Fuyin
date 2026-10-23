param([string]$AppRoot=(Join-Path $PSScriptRoot '..\app'))
$ErrorActionPreference='Stop'
function Assert($ok,[string]$message){if(-not $ok){throw $message}}
foreach($file in (Get-ChildItem -LiteralPath $AppRoot -Filter '*.ps1')){
 $errors=$null;$tokens=$null
 $null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
 Assert (-not $errors.Count) ('PowerShell syntax error: '+$file.Name)
}
. (Join-Path $AppRoot 'Lyrics.ps1')
. (Join-Path $AppRoot 'Karaoke.ps1')
$rows=@(ConvertFrom-Lrc "[offset:100]`n[00:01.500][00:03.000]原创示例`n[00:02.125]第二句")
Assert ($rows.Count -eq 3 -and [Math]::Abs($rows[0].Time-1.4) -lt .0001) 'LRC parsing failed'
Assert ((Get-LyricIndex $rows 2.1) -eq 1) 'Lyric index failed'
$real=@(ConvertFrom-Lrc '[1000,2600](1000,2000,0)长(3200,200,0)音')
$data=Get-LumaKaraokeData $real[0] 4 'Word'
Assert ($data.Exact -and (Get-KaraokeFrame $data.Words 2.9).Active -eq 0) 'Held syllable failed'
Assert ((Get-KaraokeFrame $data.Words 3.1).Active -eq -1) 'Silent gap failed'
Assert ((Get-KaraokeFrame $data.Words 3.25).Active -eq 1) 'Next word failed'
foreach($text in @('原创文字与停顿',"Hold on, don't go!",'Love你，2026')){
 $row=[pscustomobject]@{Time=10.;Text=$text;Offset=0.}
 $data=Get-LumaKaraokeData $row 16 'Word'
 Assert ($data.Estimated -and (($data.Words | ForEach-Object {$_.Text}) -join '') -ceq $text) 'Prediction changed text'
 Assert ($data.Words[0].Time -eq 10 -and $data.Words[-1].End -eq 16) 'Prediction crossed line boundary'
}
Add-Type -AssemblyName PresentationFramework
$null=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $AppRoot 'MenuTheme.xaml')))
Write-Output 'PASS: all PowerShell syntax, LRC index, true-word priority, held note/rest, prediction text/bounds and menu XAML.'
