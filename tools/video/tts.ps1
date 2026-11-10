# Text-to-speech for the explainer video (Windows built-in voices, offline).
#   powershell -ExecutionPolicy Bypass -File tts.ps1 <folder>
# Reads every <folder>\*.txt and writes <folder>\<same name>.wav next to it.
param([Parameter(Mandatory = $true)][string]$Folder,
      [string]$Voice = 'Microsoft Zira Desktop',
      [int]$Rate = 0)
Add-Type -AssemblyName System.Speech
$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
try { $s.SelectVoice($Voice) } catch { Write-Warning "voice '$Voice' not found, using the default" }
$s.Rate = $Rate
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(22050, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
Get-ChildItem -Path $Folder -Filter *.txt | Sort-Object Name | ForEach-Object {
    $wav = [IO.Path]::ChangeExtension($_.FullName, '.wav')
    $s.SetOutputToWaveFile($wav, $fmt)
    $s.Speak([IO.File]::ReadAllText($_.FullName))
    $s.SetOutputToNull()
    Write-Output "  voice $($_.BaseName)"
}
$s.Dispose()
