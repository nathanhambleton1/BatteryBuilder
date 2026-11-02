# MATLAB License Hunter

Keeps trying to get a MATLAB license until it gets one, then grabs the toolbox licenses inside MATLAB. Every attempt by everyone is logged to a shared folder, and the PowerShell window becomes a live dashboard that shows when during the day and week you can actually get MATLAB.

## Setup (once, by whoever owns the share)

Copy these files into one folder on the network drive:

| File | What it is |
|---|---|
| `GrabMatlabLicense.ps1` | The hunter and live dashboard |
| `GrabMatlabLicense.cmd` | Double-click launcher (works around execution policy) |
| `MATLABLicenseAcquisition.m` | Runs inside MATLAB and grabs the toolbox licenses |
| `LicenseAnalytics.m` | MATLAB charts of the shared data (📈 button in the app) |

The first run creates `LicenseData\` next to the scripts. Everyone writes their own file in it (`attempts\<user>@<pc>.csv`), so people never fight over a file lock.

**Recommended:** find your license server (`port@host`, e.g. `27000@flexlm01`; IT knows it, or look in `C:\Program Files\MATLAB\R20xx\licenses\network.lic`). If the script can query it with `lmutil.exe`, it watches the seat count and only launches MATLAB when a seat is free, instead of opening and killing MATLAB over and over. It tries to find the server automatically. If it can't, edit the `$LicenseServer` default at the top of the script.

## Use

Right-click `GrabMatlabLicense.ps1`, then **Run with PowerShell** (on Windows 11, click **Show more options** first). You can also double-click `GrabMatlabLicense.cmd`.

| Key | Action |
|---|---|
| `H` | Start hunting (when idle) |
| `P` | Pause or resume the hunt |
| `R` `R` | Release: closes MATLAB, which returns all of its licenses |
| `K` `K` | Force-kill MATLAB (unsaved work is lost) |
| `Q` | Quit the dashboard (MATLAB stays open if you have it) |

Options: `-DashboardOnly` (just watch the stats), `-LicenseServer 27000@host`, `-MatlabPath ...`, `-NoAutoRun`, `-RetryDelaySeconds 5`.

## About releasing licenses

MATLAB has no command that returns a single toolbox license once it's checked out. Licenses go back to the server only when MATLAB exits. So "release" means closing MATLAB, either with the **Release All & Exit** button in the app or with `R` in the dashboard.

A license admin has two more options:

- `lmutil lmremove` kicks a specific user's seat. This usually needs admin rights on the license server.
- A `TIMEOUTALL` line in the MLM options file makes idle seats return automatically.
