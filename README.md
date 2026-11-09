# Battery Test Viewer & Model Builder (`plotBatteryData.m`)

One MATLAB file that turns cycler test data for a lithium-ion cell into a
**digital twin**: a parameterised Simscape **Battery (Table-Based)** block,
with the thermal port and SOC port enabled, that reproduces the measured test
when you drive it with the measured current.

```
CSV per temperature ──► Viewer (cursor, fit, drag-zoom)
        │
        ├─► Parameter extraction ──► OCV(SOC,T)  R0(SOC,T)  Rk/tauk(SOC,T)
        │                            AH  thermal mass  h*A   (+ provenance)
        │                                   │
        │                                   ├─► workspace variables / .mat
        │                                   └─► "Apply to block" (gcb)
        ├─► Load profile ──► [t I] for a Controlled Current Source
        │                    [t T] for the chamber temperature
        └─► Digital twin  ──► generated Simscape model, simulated and
                              overlaid on the measurement (RMSE)
```

This is the first iteration. It sets up the data path, the extraction method
and the validation loop so later work (more tests, better fits, aging) has a
solid base.

---

## Contents

1. [Quick start](#1-quick-start)
2. [Requirements](#2-requirements)
3. [Input data](#3-input-data)
4. [Using the app](#4-using-the-app)
5. [What is calculated and how](#5-what-is-calculated-and-how)
6. [Exported variables and setting up the Simscape model](#6-exported-variables-and-setting-up-the-simscape-model)
7. [Load profile → Controlled Current Source](#7-load-profile--controlled-current-source)
8. [The digital-twin model](#8-the-digital-twin-model)
9. [Scripting (no GUI)](#9-scripting-no-gui)
10. [Validation](#10-validation)
11. [Code walkthrough](#11-code-walkthrough)
12. [Limitations and roadmap](#12-limitations-and-roadmap)
13. [Troubleshooting](#13-troubleshooting)

---

## 1. Quick start

```matlab
plotBatteryData                 % opens the app
```

1. **Add CSV…** and pick one file per test temperature (multi-select works).
2. **Plot** tab: look at the data. Turn the **Cursor** on, drag to zoom, double-click to fit.
3. **Model extraction** tab: type in any datasheet values you have (all optional), then **Run extraction**.
4. **Load profile & digital twin** tab:
   * **To workspace** puts every table in the base workspace as `batt_*`.
   * **Export load profile to workspace** creates `batt_load` (`[t I]`) for a Controlled Current Source.
   * **Build & run twin** generates `batteryTwin.slx`, simulates it and shows measured vs simulated voltage.

To try it without real data, generate a synthetic test set with a known answer:

```matlab
addpath tests
files = makeSyntheticCellData(fullfile(tempdir,'synth'));   % 0 / 25 / 45 °C
plotBatteryData('gui', files)
```

---

## 2. Requirements

| Feature | Needs |
|---|---|
| Viewer, extraction, workspace export, load profile | MATLAB R2021a or newer (developed and tested on **R2025b**). No toolboxes. |
| *Apply to selected block*, *Build & run twin* | Simulink + Simscape + **Simscape Battery** (the block lives in `batt_lib/Cells`). The app also finds the same block in Simscape Electrical's `ee_lib/Sources`. |

No Statistics or Optimization Toolbox is needed. Fits use `fminsearch` and plain linear algebra.

---

## 3. Input data

### 3.1 Columns

The importer matches headers loosely: it ignores case, spaces and punctuation, so `TestTime (s)`, `Test Time(s)` and `testtime_s` all match. The expected export is:

| Column | Used for | Required |
|---|---|---|
| `Record#` | – | no |
| `Step` | – | no |
| `TestTime (s)` | time axis. Numbers, or `hh:mm:ss` / `1d 02:03:04` strings | **yes** (or `DateTime`) |
| `StepTime (s)` | exact switch instant at the start of each rest (better RC fits) | no |
| `Capacity (Ah)`, `Energy (Wh)` | plotted only; Ah is integrated from the current | no |
| `Current (A)` | everything | **yes** |
| `Voltage (V)` | everything | **yes** |
| `State` | current sign: `C` charge, `D` discharge, `R` rest (first letter used) | recommended |
| `ES` | – | no |
| `DateTime` | time axis fallback | no |
| `Temp 1` | cell temperature, used for the thermal fit | recommended |
| `Chamber Temperature (C)` | test temperature label and twin ambient | recommended |

### 3.2 One file per temperature

Load every file for the same cell together. Each file is labelled with the
median chamber temperature. You can edit the **T (°C)** column in the file
table. Files within 1 °C of each other are merged into one column of the tables.

### 3.3 Current sign

Internally, **positive current = discharge**. The sign is resolved per file
(*Current sign in file* = `auto`):

* With a `State` column, current is taken as a magnitude and signed by `C`/`D`.
  If the file already has signed current, the State column is used to tell
  which convention the file uses.
* Without a `State` column, the convention is inferred from physics: positive
  charge current must raise the voltage.
* You can force `charge+` or `discharge+`.

The file info box (bottom left) shows the decision for every file.

### 3.4 What a good test contains

The more of these a test contains, the more is **measured** rather than taken from the datasheet:

| Test element | Gives |
|---|---|
| CC-CV charge (current tapers at constant voltage) | SOC = 1 anchor, Vmax |
| Full CC discharge to the cut-off | capacity, SOC = 0 anchor, dense OCV curve |
| Rests of ≥ 5 min (better 30–60 min) after charge/discharge | OCV points, R1/τ1, R2/τ2 |
| Current steps (pulses, step starts) sampled at ≤ 1–5 s | R0 |
| HPPC (pulses at 10 % SOC steps with long rests) | R0, Rk, τk across the whole SOC range |
| Cell temperature + chamber temperature | thermal mass and h·A |
| The same test at several chamber temperatures | the T axis of every table |

---

## 4. Using the app

### 4.1 Plot tab

| Action | How |
|---|---|
| Choose data | *Datasets* (several = overlay), *X axis*, *Left Y* / *Right Y* (Ctrl/Shift-click for several) |
| **Cursor** | Toggle **Cursor: on**. A vertical line follows the mouse. Every curve gets a marker where it crosses the line and a label **next to that point** with its value, so labels move both horizontally and vertically. The X value is shown at the bottom of the line. Labels that would overlap are pushed apart, and they flip to the left of the line near the right edge. If X is not monotonic (e.g. Voltage vs SOC), the cursor snaps to the nearest point of each curve. |
| **Fit all** | whole data set, both axes |
| **Fit horizontal** | full X range, Y unchanged |
| **Fit vertical** | Y range of the data *inside the current X window* (both Y axes) |
| **Drag to zoom** | left-drag a box. The *Drag* menu chooses box, horizontal-only or vertical-only zoom (or off). |
| Scroll wheel | zoom around the mouse (X in box/horizontal mode, Y in vertical mode, both in box mode) |
| Double-click | fit all |
| Right-click or **Zoom back** | undo the last zoom (50 levels) |
| Keys | `f` fit all, `Backspace` zoom back, `Esc` cancel a drag |
| **Copy plot to figure** | copies the current view into a normal MATLAB figure for saving or printing |

Extra columns are added to every file:

* At load: `Test Time (h)`, `Current, +discharge (A)`, `Power, +discharge (W)`, `State code (C=1 R=0 D=-1)`, `Ah discharged, cumulative`.
* After extraction: `SOC (-)`.
* After a twin run: `V twin (V)`, `V error (mV)`, `SOC twin (-)`, `Temp twin (C)`.

### 4.2 Model extraction tab

**Settings**

| Setting | Meaning | Default |
|---|---|---|
| SOC breakpoints | rows of every table (any MATLAB vector expression) | `[0 0.02 0.05 0.1:0.1:0.9 0.95 1]` |
| RC pairs | number of RC branches (block *Charge dynamics*) | 2 |
| tau bounds | search range of every time constant | `[1 3000]` s |
| Min rest for RC/OCV fit | shorter rests are ignored for relaxation fits | 300 s |
| Max sample gap at step | current steps sampled coarser than this are not used for R0 | 5 s |
| Dense OCV max C-rate | only CC data at or below this rate builds the dense OCV curve | 0.5 C |
| SOC basis | `common`: one capacity (the block's AH) for every temperature, which matches what the block does. `perTemperature`: each file uses its own capacity. | common |
| AH reference temp | the block takes one AH; it is taken from the file nearest this temperature | 25 °C |
| Full/empty voltage tol | tolerance for detecting Vmax / Vmin | 0.02 V |

**Datasheet values.** Leave blank what you do not know. They are used only
where the data cannot provide a value, unless you tick *Prefer datasheet …*.

| Field | Used when |
|---|---|
| Capacity (Ah) | no full charge → full discharge in any file |
| Vmax / Vmin | override the detected cut-offs |
| Cell mass × specific heat | thermal mass, if the thermal fit is not possible |
| Convection h·A | if the thermal fit is not possible |
| Internal resistance | R0, if no usable current step was found |
| Self-discharge R | enables the block's self-discharge (never measured from these tests) |
| Datasheet OCV table | a 2-column CSV `SOC,OCV` (SOC as 0–1 or %), used only where data gives no OCV |

**Diagnostics.** The plot shows every individual measurement as a dot and the
exported table as a line, per temperature: OCV, R0, R1…R3, τ1…τ3, SOC vs time,
thermal fit, and capacity vs temperature. The **report** lists capacities, how
many steps and rests were used, the thermal fit, and every table cell with its
**provenance**:

| Code | Meaning |
|---|---|
| `M` | measured at (or very near) this SOC |
| `I` | interpolated between measured SOCs |
| `E` | extrapolated (held) beyond the measured SOC range |
| `T` | nothing measured at this temperature, copied from the nearest temperature |
| `D` | datasheet |
| `A` | assumed default (enter a datasheet value) |

### 4.3 Load profile & digital twin tab

1. **Model parameters**: *To workspace*, *Save .mat…*, or *Apply to selected
   Simulink block*. For the last one, click your Battery (Table-Based) block in
   Simulink first; it becomes `gcb`.
2. **Load profile**: choose the dataset and the sign convention. Optionally
   export only the time window currently shown on the Plot tab (X must be a
   time column).
3. **Digital twin**: builds and runs the model (section 8). The top plot shows
   measured vs twin voltage. The bottom plot shows the error in mV and
   measured vs twin cell temperature.

---

## 5. What is calculated and how

All of this is in **Section 8** of the file (`extractParameters`) and the
helpers it calls. Units: V, A, Ω, s, Ah, K (°C only for labels).

### 5.1 Phases

Each sample is classified as charge (`I<0`), discharge (`I>0`) or rest
(`|I|` below 0.2 % of max |I|, at least 2 mA). Consecutive samples of the same
kind form a **phase**, so a cycler's separate CC and CV steps become one charge
phase (`findPhases`).

### 5.2 Vmax, Vmin, full and empty

* A charge phase **ends in CV** when its current has tapered to < 35 % of its
  maximum while the voltage over the taper stayed within 15 mV (`cvPhases`).
  The CV hold voltage is **Vmax**. This deliberately ignores short
  over-voltages, such as a charge pulse at 100 % SOC.
* **Full** = end of a CV phase at Vmax. **Empty** = a discharge phase reaching
  Vmin, which is the lowest measured voltage unless the datasheet gives one.

### 5.3 Capacity and SOC

* Ah is integrated with a **zero-order hold**: a sample's current applies until
  the next sample. This is how cyclers log step starts, and it is exactly how
  the exported profile replays them. The extracted SOC and the twin's SOC
  therefore agree; in validation they match to 4 decimals over 30 h.
* **Capacity** = Ah discharged from a *full* point to the next *empty* point.
  If a file has several, the lowest-rate discharge wins (`capacityFromData`).
* **Block AH** = capacity of the file nearest the reference temperature, or the
  datasheet value if preferred or if nothing was measured. The R2025b
  Table-Based block has **one** AH (no AH(T)). Cold-temperature "capacity loss"
  is reproduced by the higher resistance reaching Vmin sooner, which is why
  `common` SOC basis is the default.
* **SOC** = coulomb counting, **re-anchored to 1 at every full charge**
  (`socFromAnchors`). Without a full charge it is anchored to 0 at the first
  empty point, or to *initial SOC*.

### 5.4 R0: instantaneous resistance

At every current step larger than 5 % of max |I| whose two bracketing samples
are ≤ *Max sample gap* apart:

```
R0 = -ΔV / ΔI          (both directions, charge and discharge)
```

placed at the SOC of the step (`r0FromEdges`). With slow logging, R0 includes a
little RC relaxation; the report warns when the median sample interval is
> 2 s.

### 5.5 R1..Rn and τ1..τn: relaxation fits

Every rest of at least *Min rest* seconds that follows a real current phase is
fitted with (`fitRelaxations`, `fitOneRelaxation`):

```
V(t) = V∞ − Σk Rk · xk(tsw) · exp(−(t − tsw)/τk)
```

* `tsw` is the switch instant, taken from `StepTime` when available.
* `xk(tsw)` is the current in RC branch *k* at that instant. It is computed by
  passing the **actual current history** through a first-order filter with
  time constant τk. This is exact for any history (pulse, CC, CV or a partial
  rest) and is the key difference from the textbook "assume the RC was fully
  charged" method.
* For given τ the model is **linear** in `[V∞, R1..Rn]`. These are solved by
  least squares with `Rk ≥ 0` (`lsqNonnegTail`). Only the τ's are searched: a
  coarse grid first, then Nelder–Mead in a bounded log-τ space. This variable
  projection is robust and needs no toolbox.
* τ's are sorted so `τ1 < τ2 < …`. Fits with RMSE > 8 mV are rejected. A pair
  pinned at R = 0 is marked not identifiable and dropped.
* **V∞ is the relaxed voltage, i.e. an OCV point** at that SOC.

### 5.6 OCV(SOC)

Two sources are combined (`buildOcv`, `denseOcvPoints`):

1. **Rest points** (V∞ above). These are the most trusted. Charge-side and
   discharge-side points at the same SOC are averaged, which cancels most of
   the hysteresis.
2. **Dense curve** from low-rate CC data:
   `OCV ≈ V + I·R0(SOC) + Σ Rk(SOC)·xk(t)`, using the R/τ just identified. It
   is averaged per 1 % SOC bin over charge and discharge.

The final curve takes its **shape from the dense curve and its level from the
rests**. The offset between them is interpolated linearly from rest to rest.
That keeps the steep low-SOC region right even when rests are 10 % apart.
Without a dense curve, the rest points are interpolated with pchip; without
either, the datasheet table is used. OCV is forced to rise monotonically with
SOC.

### 5.7 Gridding onto the SOC breakpoints

Scattered points (R0, Rk, τk) go onto the breakpoints by taking the **median**
of the points in each breakpoint's neighbourhood (`gridPoints`). Gaps are filled
by interpolation, ends are held, and every cell's provenance is recorded. A
parameter with no points at some temperature is copied from the nearest
temperature (`fillAcrossT`). Anything still missing gets a flagged assumption.

### 5.8 Thermal mass and h·A

The block's lumped thermal model is:

```
m·cp · dT/dt = Q − h·A · (T − T_chamber)
Q = I²·R0(SOC,T) + Σ Rk(SOC,T) · xk²        (the Joule heat the block itself generates)
```

`fitThermal` does two things:

1. Resamples to 10 s and regresses `dT/dt` on `[Q, −(T − T_ch)]`. This is
   linear in `1/(m·cp)` and `h·A/(m·cp)`.
2. Refines both values by fitting the **simulated temperature trajectory**
   (output error, `fminsearch`). This removes the bias the derivative needs
   for smoothing.

Values are taken as the median over files. `h·A` represents the chamber
convection seen during the test. For the real application, replace it with
your pack's value.

### 5.9 What cannot come from these tests

| Parameter | Why | Source |
|---|---|---|
| Self-discharge resistance | needs days of open-circuit storage | datasheet / storage test |
| Cycle and calendar aging | needs aging campaigns | not modelled (block aging disabled) |
| Current-direction-dependent R0 | possible from the data, not implemented yet | roadmap |
| Entropic (reversible) heat | needs dOCV/dT tests | not in the Table-Based block |

---

## 6. Exported variables and setting up the Simscape model

**To workspace** writes these variables. The prefix is `batt_` by default and
can be changed on the tab.

| Variable | Size / unit | Block parameter |
|---|---|---|
| `batt_SOC_vec` | 1×nS | Vector of state-of-charge values, SOC |
| `batt_T_vec` | 1×nT, **K** | Vector of temperatures, T |
| `batt_V0_mat` | nS×nT, V | Open-circuit voltage, V0(SOC,T) |
| `batt_R0_mat` | nS×nT, Ω | Terminal resistance, R0(SOC,T) |
| `batt_R1_mat`, `batt_tau1_mat`, … | nS×nT, Ω / s | First polarization resistance / time constant, … |
| `batt_V0_vec`, `batt_R0_vec`, `batt_R1_vec`, … | 1×nS | same, at the reference temperature (for *Tabulate over temperature = No*) |
| `batt_AH` | A·hr | Cell capacity, AH |
| `batt_thermal_mass` | J/K | Thermal mass |
| `batt_hA` | W/K | Convective Heat Transfer coefficient, with area = 1 m² |
| `batt_Rleak` | Ω | Self-discharge resistance (only if given) |
| `batt_SOC0`, `batt_T0` | –, K | initial SOC / cell temperature (from the load profile) |
| `batt_Vmin`, `batt_Vmax` | V | detected cut-offs (for your own protection logic) |
| `batt_params` | struct | everything above + provenance + options |

**Block settings** (Simscape Battery › Cells › Battery (Table-Based)). *Apply to
selected block* sets all of these:

* Charge dynamics: *n* time-constant dynamics → `R1_mat … tau_n_mat`
* Tabulate parameters over temperature: Yes (No if only one file)
* Thermal port: **Model** → connect port H to a Convective Heat Transfer element whose other side is the ambient
* Expose SOC measurement port: **Yes**
* Extrapolation: nearest
* Variables › State of charge: `batt_SOC0` (priority High); Cell temperature: `batt_T0` (High)

**Block ports** (verified in R2025b with thermal and SOC enabled):

| Port handle | Port |
|---|---|
| `LConn(1)` | + |
| `LConn(2)` | SOC (physical signal) |
| `RConn(1)` | − |
| `RConn(2)` | H (thermal) |

---

## 7. Load profile → Controlled Current Source

**Export load profile to workspace** creates:

| Variable | Content |
|---|---|
| `batt_load` | `[t I]` – time from 0 s, current in the chosen sign |
| `batt_load_ts` | the same as a `timeseries` |
| `batt_ambient`, `batt_ambient_ts` | `[t T]` chamber temperature in **K** |
| `batt_vmeas` | `[t V]` measured terminal voltage, for comparison |
| `batt_SOC0`, `batt_T0` | SOC and cell temperature at the start of the profile |
| `batt_stopTime` | profile length (s) |

**Sign convention.** The default is `charge+`, which means a positive signal
**charges** the cell. This matches the Simscape Foundation **Controlled Current
Source** wired like this:

```
From Workspace (batt_load) ─► Simulink-PS Converter (unit A) ─► Controlled Current Source
Controlled Current Source  + (head)  ──► battery +
Controlled Current Source  − (tail)  ──► battery −
```

This was verified by simulation: a +1 A signal raises the block's SOC. If you
wire the source the other way round, export with `discharge+`.

**Steps stay sharp.** A cycler logs the *new* current on the first sample of a
step. The exporter inserts a point 1 ms earlier that carries the *old* current,
so **From Workspace with *Interpolate data* ON** reproduces every step exactly.
Set *Form output after final data value* to *Holding final value*.

**Solver step.** With a variable-step solver, cap *Max step size* at about the
data's sample interval. Otherwise the solver can step right over a 10 s pulse
after a long rest. The generated twin does this automatically.

---

## 8. The digital-twin model

**Build & run twin** (`runTwin`, `buildTwinModel`) generates
`<modelName>.slx`, default `batteryTwin`, in the current folder:

```
From Workspace batt_load ─► S-PS [A] ─► Controlled Current Source ─┬─ Battery (Table-Based) +
                                                                     └─ Battery −  ── Electrical Ref, Solver Config
From Workspace batt_ambient ─► S-PS [K] ─► Controlled Temperature Source ─► Convective Heat Transfer (h=batt_hA, A=1 m²) ─► Battery H
Voltage Sensor ─► twin_V        Battery SOC port ─► twin_SOC        Temperature Sensor(H) ─► twin_T
```

* Solver `daessc`, RelTol 1e-4, MaxStep = sample interval (clamped to 0.5–10 s).
* Output is also produced exactly at the measured timestamps, so the error is
  computed sample by sample.
* The block's SOC-range assertion is silenced during the run. If the twin's
  SOC leaves 0..1 (e.g. a charge pulse at 100 %), the summary says so once.
* The model reads everything from base-workspace variables, so you can open
  it, inspect it, rerun it, or copy the battery block into your own system.
* **The model file is overwritten on every build.** Rename it if you edit it.

Reported: voltage RMSE and max |error| (with time and SOC of the max), cell
temperature RMSE, final SOC, and wall time.

---

## 9. Scripting (no GUI)

The GUI and the commands use the same engine:

```matlab
o = plotBatteryData('defaults');          % all options (Section 1 of the file)
o.nRC = 2;
o.ds.massKg = 0.07;  o.ds.cpJkgK = 1000;  % datasheet fallbacks

files = {'cell_0C.csv','cell_25C.csv','cell_45C.csv'};
[P, ds] = plotBatteryData('extract', files, o);   % P = tables, ds = data + SOC
disp(char(P.report))

o.profileWindow = [0 36000];              % optional: first 10 h only (s from file start)
prof = plotBatteryData('profile', ds(2), o);
plotBatteryData('export', P, prof, o);    % -> batt_* in the base workspace
res  = plotBatteryData('twin', P, prof, o);
fprintf('RMSE %.1f mV\n', res.rmse_mV);
```

`fig = plotBatteryData('gui', files)` opens the app pre-loaded.
`fig.UserData.api` exposes `loadFiles`, `setColumns`, `setCursor`, `cursorAt`,
`zoomBox`, `fit`, `zoomBack`, `runExtraction`, `exportProfile`, `runTwin`,
`selectTab`, `setDiag`, `drawDiag` and `getState`. These are used by the tests
and are handy for batch reports.

---

## 10. Validation

`tests/` holds an end-to-end check against a cell whose parameters are known:

```matlab
cd tests
results = runValidation;      % ~1 min
```

`makeSyntheticCellData` simulates a 2-RC cell with Arrhenius-like temperature
dependence, a steep low-SOC OCV, thermal mass and convection. It runs a
realistic test at 0 / 25 / 45 °C:

* rest, then CC-CV charge
* C/5 discharge to 2.75 V
* HPPC at 10 % steps with 1 h rests, then CC-CV
* 1 h random dynamic load

The output uses the same column layout as the real exports: magnitude-only
current, `State` C/D/R, 1 s logging, and 10 s logging late in rests. Noise is
0.5 mV on voltage and 0.03 K on temperature.

Results (R2025b):

| Quantity | Extracted vs truth |
|---|---|
| Capacity (CC-CV to C/20, C/5 to 2.75 V) | −1.3 % (the cell is not at 100 % true SOC at the C/20 cut-off; this is the definition, not an error) |
| OCV, SOC 0.1–0.95, all T | max error ≤ 3.4 mV |
| R0 | median error 2.0–2.8 % |
| R1, R2 | median error 1.5–3.7 % |
| τ1 (12 s), τ2 (350 s) | median error 1.7–4.6 % |
| Thermal mass (45 J/K) | 45.2 J/K |
| h·A (0.080 W/K) | 0.081 W/K |
| **Twin voltage, 30 h test, 25 °C** | **RMSE ≈ 6 mV**, max ≈ 34 mV (near empty) |
| **Twin voltage, 30 h test, 0 °C** | **RMSE ≈ 5 mV**, max ≈ 30 mV |
| Twin cell temperature | RMSE ≤ 0.05 K |

The truth SOC differs from the extracted SOC by the anchoring definition
(SOC = 1 at the end of CC-CV). `runValidation` maps one onto the other before
comparing tables.

---

## 11. Code walkthrough

`plotBatteryData.m` is split into numbered sections. Line numbers are
approximate.

| § | Lines | Functions | Purpose |
|---|---|---|---|
| 0 | 1–75 | `plotBatteryData` | Help text and command dispatcher: `gui`, `defaults`, `load`, `extract`, `profile`, `export`, `twin`. |
| 1 | 77–142 | `defaultOptions`, `optsFromArgs`, `mergeStruct` | Every tunable number in one struct. The `ds` sub-struct holds the datasheet values. |
| 2 | 144–1340 | `launchGui` + nested callbacks; `styleAxes`, `fmtNum`, `interpMono`, … | The app (see below). |
| 3 | 1344–1548 | `loadDataset`, `applyCurrentSign`, `findCol`, `toSeconds` | CSV import, loose header matching, time parsing, current-sign resolution, derived columns. |
| 4 | 1550–1575 | `findPhases` | Charge / discharge / rest phases. |
| 5 | 1577–1650 | `cvPhases`, `capacityFromData`, `socFromAnchors` | CV detection, full/empty points, capacity, coulomb-counted SOC. |
| 6 | 1651–1787 | `r0FromEdges`, `fitRelaxations`, `fitOneRelaxation`, `lsqNonnegTail`, `zohSample` | R0 from current steps; RC relaxation fits with the exact current history. |
| 7 | 1789–1906 | `gridPoints`, `buildOcv` | Scattered points → SOC breakpoints, with provenance; OCV assembly. |
| 8 | 1908–2246 | `extractParameters`, `fillAcrossT`, `denseOcvPoints`, `rcCurrent`, `tableText` | The pipeline: limits → capacity → SOC → temperature groups → R0/RC → OCV → thermal → assembly + report. |
| 9 | 2248–2316 | `fitThermal`, `simulateThermal` | Lumped thermal identification. |
| 10 | 2318–2380 | `extractProfile` | Load / ambient profile with exact steps. |
| 11 | 2382–2495 | `workspaceVariables`, `exportToWorkspace`, `applyToBlock`, `blockHelpText` | Variables, .mat contents, block parameterisation. |
| 12 | 2497–end | `runTwin`, `buildTwinModel`, `sampleTs`, `attachTwin`, `findLibBlock` | Generate, wire, simulate and score the Simscape twin. |

### GUI structure (Section 2)

`launchGui` creates the figure and keeps all app state in variables shared by
its **nested functions**:

| State | Content |
|---|---|
| `datasets` | struct array, one per file (see `emptyDatasets` for the fields) |
| `opts` | the options |
| `P` | extraction result |
| `prof` | last exported profile |
| `twinRes` | last twin result |
| `series` | one entry per plotted curve: handle, side, x/y, monotonic flag, cursor marker and label |
| `zoomStack`, `drag`, `cursorOn` | interaction state |

| Group | Nested functions |
|---|---|
| Layout helpers | `lbl`, `place`, `addEdit`, `addNum`, `addDrop`, `setStatus` |
| Files | `onAddFiles`, `addFiles`, `onRemoveFile`, `onClearFiles`, `onFileTableEdit`, `refreshFileTable` |
| Plotting | `createAxes` (fresh axes on every redraw; built-in interactions are disabled so they cannot fight the custom ones), `refreshPlot`, `addSeries`, `currentLimits`/`setLimits` (keep left and right Y in step), `extentOf`, `fitView`, `pushZoom`, `zoomBack`, `applyZoom` |
| Mouse | figure-level `WindowButtonDown/Motion/Up` and `WindowScrollWheel` handlers → `onMouseDown` (start box / double-click fit / right-click back), `onMouseMove` (update box or cursor), `onMouseUp` (apply zoom), `onScroll`, `onKey` |
| Cursor | `setCursor`, `buildCursor` (one `xline` plus a marker and text per series, created on the series' own Y side), `updateCursor`. It interpolates monotonic curves at the cursor X, or takes the nearest point on screen otherwise, then de-overlaps the labels and places each label beside its point. |
| Extraction tab | `readSettings`, `onLoadOcvTable`, `onRunExtraction`, `drawDiag`, `diagTable` |
| Export / twin tab | `onExportParams`, `onSaveMat`, `onApplyToBlock`, `onExportProfile`, `onRunTwin`, `drawTwin`, `onOpenModel` |

The previous version's cursor used a draggable `drawline` ROI and one text box
pinned at the top of the axes. It was replaced by a mouse-following `xline`
with per-curve markers and labels at the intersection points.

---

## 12. Limitations and roadmap

First-iteration scope, roughly in order of value:

1. **Temperature axis from the cell sensor**: tables are currently binned by
   *chamber* temperature. Using the measured cell temperature at each point
   would sharpen R(T) when self-heating is large.
2. **Direction-dependent R0** (block *Current directionality*): the points
   already carry their sign; this needs gridding per direction.
3. **OCV hysteresis**: charge and discharge rest points are averaged. A
   hysteresis model is not part of the Table-Based block.
4. **Parameter optimisation on the full profile**: refine all tables by
   minimising twin voltage error (Simulink Design Optimization or `fminsearch`
   on a downsampled run), starting from the extracted values.
5. **Multiple cells / aging**: compare extractions across cells or check-ups.
   The block's fade parameters could be fitted from repeated tests.
6. **Cycler-reported capacity**: use the `Capacity (Ah)` column directly when
   its reset/sign convention is known.
7. **Report export**: one-click PDF/HTML of the diagnostics.

Known simplifications:

* The block's AH is a scalar; cold capacity loss comes only from resistance.
* With slow logging (> 2 s), R0 includes some RC relaxation.
* h·A reflects the test chamber, not your application.

---

## 13. Troubleshooting

| Symptom | Fix |
|---|---|
| "Could not find Current and Voltage columns" | Check the header row. The error lists the columns it saw. |
| Current looks inverted | Set *Current sign in file* to `charge+` or `discharge+` and rerun. Check the file info box. |
| "no complete full->empty discharge found" | The test has no CC-CV charge followed by a discharge to Vmin. Enter a datasheet capacity. |
| Many `A`/`E` cells in the tables | Not enough rests ≥ *Min rest*, or rests only at a few SOCs. Lower *Min rest*, add an HPPC test, or accept the extrapolation. |
| Very few R0 points | Sampling at the steps is coarser than *Max sample gap*. Raise it (R0 then includes some RC). |
| Thermal "not fitted" | Cell temperature barely changes (< 0.5 K) or is missing. Enter mass, cp and h·A. |
| Twin error large only near empty / full | The steep ends of the OCV curve. Add breakpoints there (e.g. 0.01, 0.03, 0.98). |
| Twin drifts in SOC | Check the current sign and that the profile is from the same file as SOC0. |
| *Apply to block* error | Click the Battery (Table-Based) block first, so `gcb` points at it. |
