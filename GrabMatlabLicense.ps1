Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$matlabPath = "C:\Program Files\MATLAB\R2026A\bin\win64\MATLAB.exe"
$initialWait = 5
$maxScanDuration = 5
$checkInterval = 2
$attempt = 1
while ($true) {
    try {
        Write-Host "[$(Get-Date)] [Attempt $attempt] Launching process..." -ForegroundColor White
        Start-Process -FilePath $matlabPath -ErrorAction Stop
        Write-Host "[$(Get-Date)] Initial wait $initialWait s..." -ForegroundColor Gray
        Start-Sleep -Seconds $initialWait
        $root = [System.Windows.Automation.AutomationElement]::RootElement
        $matlabWindowCondition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, "MATLAB R2026a")
        $matlabWindow = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $matlabWindowCondition)
        if ($matlabWindow) {
            $errorDetected = $false
            $foundErrorText = ""
            $elapsedScan = 0
            while ($elapsedScan -lt $maxScanDuration) {
                $allDescendants = $matlabWindow.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
                foreach ($element in $allDescendants) {
                    if ($element.Current.Name -like "*Licensing Error*") {
                        $errorDetected = $true
                        $foundErrorText = $element.Current.Name
                        break
                    }
                }
                if ($errorDetected) { break }
                Write-Host "[$(Get-Date)] Scanning for error text..." -ForegroundColor Gray
                Start-Sleep -Seconds $checkInterval
                $elapsedScan += $checkInterval
            }
            if ($errorDetected) {
                Write-Host "[$(Get-Date)] RESULT: $foundErrorText detected. Restarting..." -ForegroundColor Yellow
                Get-Process -Name "matlab" -ErrorAction SilentlyContinue | Stop-Process -Force
            } else {
                Write-Host "[$(Get-Date)] RESULT: SUCCESS. No error detected after $maxScanDuration s." -ForegroundColor Green
                break
            }
        } else {
            Write-Host "[$(Get-Date)] RESULT: TIMEOUT. MATLAB window not found. Restarting..." -ForegroundColor Red
            Get-Process -Name "matlab" -ErrorAction SilentlyContinue | Stop-Process -Force
        }
    }
    catch {
        Write-Host "[$(Get-Date)] CRITICAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
    $attempt++
}