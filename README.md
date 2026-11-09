# Battery Builder

A MATLAB app for lithium-ion cell test data. It has three tabs:

| Tab | What it does |
|---|---|
| **Plot** | Look at the test: cursor read-out, fit buttons, drag-to-zoom, middle-mouse pan. |
| **Load profile** | Shows the test's current profile and saves it to the workspace for a Simulink *Controlled Current Source*. |
| **Modeling** | One button pulls every parameter it can out of the test and fills in the boxes for the Simscape **Battery (Table-Based)** block. Empty boxes tell you what you still need from the datasheet. A second button saves everything to the workspace. |

Building and running the Simulink model is up to you. This app only produces the workspace variables the model needs.

---

## 1. Quick start

```matlab
cd 'C:\App Projects\BatteryBuilder'
BatteryBuilder                    % opens the app
BatteryBuilder('cell_25C.csv')    % opens it with a file already loaded
```

1. **Open CSV...** → pick one test file (one cell, one temperature).
2. **Plot** tab: look at the data.
3. **Load profile** tab: **Save load profile to workspace** → `batt_load`.
4. **Modeling** tab: **1. Extract data from test**. Fill in any orange *Required* boxes from the datasheet, then **2. Save to workspace** → `batt_*`.
5. In Simulink, type the `batt_*` names into the Battery (Table-Based) block (hover over any box to see where each one goes).

Requirements: MATLAB R2021a or newer. No toolboxes are needed for the app itself. Simscape Battery (or Simscape Electrical) is only needed for the Simulink model you build afterwards.

---

## 2. Files

```
BatteryBuilder.m              <- the ONLY file you run. Builds the window and the three tabs.
src/
  plotTab.m                   Tab 1 - interactive plot
  loadProfileTab.m            Tab 2 - current profile -> workspace
  modelingTab.m               Tab 3 - parameter boxes, Extract / Save buttons
  blockParameterList.m        the list of boxes on Tab 3 (variable names, where they go, datasheet hints)
  extractCellParameters.m     all the calculations (capacity, SOC, OCV, R0, RC pairs, thermal)
  explainParameter.m          the "How?" pop-up windows
  loadBatteryCsv.m            reads a cycler CSV
tests/
  makeSyntheticCellData.m     writes test CSVs from a cell whose parameters are KNOWN
  runValidation.m             checks the calculations against that known cell (PASS / FAIL)
```

`BatteryBuilder.m` adds `src/` to the path itself, so you never need to touch the other files to use the app.

How the pieces talk to each other:

```
BatteryBuilder.m
   | Open CSV  -> loadBatteryCsv(file) -> d (dataset)
   |              d is handed to every tab: plotTab.setData(d), loadProfileTab.setData(d), modelingTab.setData(d)
   |
   +-- plotTab          (only displays d)
   +-- loadProfileTab   (d.t, d.I -> batt_load)
   +-- modelingTab      Extract -> extractCellParameters(d, nRC, SOC_vec) -> R
                        R fills the boxes; "How?" -> explainParameter(key, R)
                        after Extract, d gains a 'SOC (-)' column which is sent back to the Plot tab
```

---

## 3. Test data format

One CSV per test. Column names are matched loosely (case, spaces and punctuation are ignored) and their order does not matter:

```
Record#  Step  TestTime (s)  StepTime (s)  Capacity (Ah)  Energy (Wh)
Current (A)  Voltage (V)  State  ES  DateTime  Temp 1  Chamber Temperature (C)
```

| Column | Used for |
|---|---|
| TestTime (s) | time axis (`DateTime` is the fallback). `hh:mm:ss` and `1d 02:03:04` strings are accepted. |
| Current (A), Voltage (V) | everything |
| State (C / D / R) | sign of the current when the cycler logs a positive magnitude, and rest detection |
| StepTime (s) | the exact moment the current switched off, for the relaxation fits |
| Temp 1 | cell temperature: thermal fit and initial temperature |
| Chamber Temperature (C) | ambient for the thermal fit, and the test temperature label |

### Current sign: positive = charge

Everywhere in the app, and in every saved variable, **positive current = charge (into the cell) and negative = discharge**. The loader works out which way round your file is:

* If there is a State column, it compares the sign of the current in C and D rows, or uses State to give a sign to a magnitude-only current.
* If there is no State column, charging current must make the voltage rise (checked with dV/dt).

The top bar of the app shows which case was found (e.g. *"magnitude in file, sign taken from the State column"*).

---

## 4. Tab 1: Plot

| Control | Action |
|---|---|
| X axis / Left Y / Right Y | Pick columns. Ctrl+click picks several. A right axis is added when something is selected there. |
| **Fit all** | Show all the data. |
| **Fit horizontal** | Full X range, keep the Y zoom. |
| **Fit vertical** | Fit Y to the data inside the X range you are looking at. |
| Drag drop-down | Left-drag zooms to a box, X only, Y only, or is off. |
| **Left-drag** | Zoom into the dragged box. |
| **Middle-drag** (or Shift+left-drag) | Pan (move the view around). |
| Scroll wheel | Zoom in / out around the mouse. |
| Double-click | Fit all. |
| Right-click / **Zoom back** | Undo the last zoom or pan. |
| **Cursor** | A vertical line follows the mouse. Every curve gets a marker where the line crosses it, with its value in a label right next to the crossing. Labels move up and down with the curves, are pushed apart when they would overlap, and flip to the left side near the right edge. If the X column goes back and forth (e.g. Voltage vs SOC), the nearest point on screen is used instead. |
| **Copy plot to a figure** | A normal MATLAB figure of the current view, for saving or printing. |
| Keys | `f` = fit all, `Backspace` = zoom back, `Esc` = cancel a drag. |

Extra columns added for plotting: `Test Time (h)`, `Current, +charge (A)`, `Power, +charge (W)`, `Net Ah in (Ah)`, and after an extraction `SOC (-)`.

Pan is implemented in `plotTab.m` → `onMouseDown` (`SelectionType == 'extend'`, which is what MATLAB reports for the middle button) and `onMouseMove`, which turns the mouse movement in pixels into data units using the axes' size in pixels.

---

## 5. Tab 2: Load profile

The plot shows the current over the whole test: green = charge (+), orange = discharge (−).

**Save load profile to workspace** writes:

| Variable | Contents |
|---|---|
| `batt_load` | `[t I]`, N×2. Time in seconds from 0, current in A, **+ = charge**. |
| `batt_load_ts` | the same data as a `timeseries` |
| `batt_load_tEnd` | last time (s); use it as the model Stop time |

### Using it in Simulink

```
From Workspace  ->  Simulink-PS Converter  ->  Controlled Current Source  ->  Battery (Table-Based)
 Data: batt_load       output unit: A           + (arrow head) -> battery +
 Interpolate: on                                -               -> battery -
 Final value: Holding final value
```

With the source wired head-to-battery-plus, a positive signal pushes current **into** the battery, which is charging. That matches the sign of `batt_load`.

Cyclers log the *new* current on the first sample of a step. `buildProfile` (in `loadProfileTab.m`) therefore inserts one extra point 1 ms before every current step, carrying the *old* current. With *Interpolate data = on*, the signal then steps exactly like the real test instead of ramping between two samples.

---

## 6. Tab 3: Modeling

### The walk-through

1. **1. Extract data from test**: runs `extractCellParameters` on the loaded file. Every box it can calculate turns green (**✓ From data**).
2. Boxes it could not calculate stay empty:
   * **Required** (orange): the block needs it. Type it in from the datasheet.
   * **Optional** (grey): leave it empty if you don't have it.
   * Hover over the status to see *why* it could not be found (e.g. *"no cell temperature column in the file"*) and what to look for on the datasheet.
3. Any box can be typed into: a number, a vector like `[0.02 0.021 0.022]`, or `0:0.1:1`. Typed values show as **Entered by you** (blue) and are never overwritten by Extract.
4. **How?** (on green boxes) opens a window with the method, the equation, the table of numbers and plots of the data it came from.
5. **2. Save to workspace** writes every filled box as its `batt_*` variable and tells you which required boxes are still empty.

**Hover over any box** to see its workspace variable name and exactly where it goes in the block dialog.

### Block set-up this app assumes

These options stay the same as before; set them once in the block dialog:

| Block option | Setting |
|---|---|
| Charge dynamics | the **Charge dynamics (RC pairs)** drop-down on the tab (1, 2 or 3; default 2). Saved as `batt_nRC`. |
| Tabulate over temperature | **No** (one test file = one temperature, so the `..._vec` parameters are used) |
| Current directionality | **No** |
| Thermal port | **Model** |
| Expose SOC port | **Yes** |
| Self-discharge | Disabled. Enable it only if you fill in `batt_Rleak`. |
| Fade / calendar aging | Disabled |
| Extrapolation method | Nearest |

### The boxes

| Box | Variable | Block dialog | From the data? | If not: datasheet |
|---|---|---|---|---|
| SOC breakpoints | `batt_SOC_vec` | Main › Vector of state-of-charge values | your choice (default `[0 .02 .05 .1 … .9 .95 1]`) | n/a |
| Open-circuit voltage V0(SOC) | `batt_V0_vec` | Main › Open-circuit voltage, V0(SOC) | rests + low-rate CC data | OCV-vs-SOC curve. **Required.** |
| Terminal voltage range | `batt_V_range` | Main › Terminal voltage operating range [Min Max] | min / max measured | cut-off voltages. Optional. |
| Terminal resistance R0(SOC) | `batt_R0_vec` | Main › Terminal resistance, R0(SOC) | current steps | DC internal resistance. **Required.** |
| Cell capacity AH | `batt_AH` | Main › Cell capacity, AH (A*hr) | full CC-CV → discharge to cut-off | rated capacity. **Required.** |
| Self-discharge resistance | `batt_Rleak` | Main › Self-discharge resistance, Rleak | never (needs weeks of storage) | Optional |
| R1..R3(SOC), tau1..tau3(SOC) | `batt_R1_vec`, `batt_tau1_vec`, ... | Dynamics › polarization resistance / time constant | rests after current pulses | rarely published. **Required** for the pairs in use. |
| Thermal mass | `batt_thermal_mass` | Thermal › Thermal mass (J/K) | cell temperature self-heating | mass × specific heat. **Required.** |
| Convection h·A | `batt_hA` | *not a battery parameter*: Convective Heat Transfer block, Area = 1 m², coefficient = `batt_hA` | cell temperature self-heating | depends on your fixture. Optional. |
| Initial SOC | `batt_SOC0` | Initial Targets › State of charge | SOC at the first sample | Optional |
| Initial cell temperature | `batt_T0` | Initial Targets › Cell temperature (K) | first cell-temperature reading | Optional |

A single number typed into an SOC-table box (e.g. one datasheet resistance) is copied to every SOC point when saved.

### What "no guessing" means here

* A box is only filled from the data if the data really contains what that value needs. Otherwise it stays empty and says why.
* There are **no** built-in default values. The old version's "assumed" fallbacks are gone.
* A capacity you type in is only used to build the SOC axis when the test has no complete full-to-empty discharge. The AH box then still shows **Entered by you**, not "From data".
* Between two measured SOC points a table is linearly interpolated. Beyond the measured SOC range the end value is held, which is what the block's *Nearest* extrapolation would do anyway. Every table entry is labelled in its **How?** window: `M` measured near that SOC, `I` interpolated, `E` end value held.
* The OCV table is only filled if the data covers the whole SOC range, plus at most one breakpoint (≤ 0.06 SOC) past the data at either end.

---

## 7. How each value is calculated

All of this is in `src/extractCellParameters.m`, in the same order as below.

### 7.1 Phases
The current is split into runs of **charge** (I > 0), **discharge** (I < 0) and **rest** (I = 0). Back-to-back steps of the same kind merge, so a CC step plus a CV step is one charge phase (`findPhases`).

A charge phase is a **CC-CV charge** when its current has tapered below 35 % of its maximum while the voltage over the taper stayed within 15 mV. That flat voltage is the CV voltage (`cvPhases`).

### 7.2 Capacity `batt_AH`
* **FULL** = the end of a CC-CV charge at the highest CV voltage.
* **EMPTY** = the end of a discharge that is at least 5 minutes long, stopped at the lowest voltage in the test, *and* ended on the end-of-discharge knee: over its last 3 % the voltage falls more than 3× faster per Ah than over its middle half (`endsAtKnee`). This stops a partial discharge, like one HPPC step, from being mistaken for empty.
* `AH = Ah_in(FULL) − Ah_in(EMPTY)` with `Ah_in = Σ I·dt / 3600` (zero-order hold). If there are several full→empty discharges, the slowest one wins.

### 7.3 SOC and `batt_SOC0`
Coulomb counting that resets to SOC = 1 at every FULL point: `SOC = 1 + (Ah_in − Ah_in(FULL)) / AH`. Before the first full charge the same line is run backwards. `batt_SOC0` is the SOC of the first sample.

### 7.4 R0 `batt_R0_vec`
At every sharp current step (|ΔI| > 5 % of the maximum current, sampled at ≤ 5 s): `R0 = ΔV / ΔI`. The RC branches cannot change instantly, so the instant jump is purely resistive. Each SOC breakpoint takes the median of the steps closest to it (`r0FromEdges`, `gridPoints`).

### 7.5 RC pairs `batt_R1_vec`, `batt_tau1_vec`, ...
Every rest of at least 5 min that follows a current pulse is fitted with

```
V(t) = Vinf + Σ_k R_k · x_k(0) · exp(−t / tau_k)
x_k(n) = a·x_k(n−1) + (1−a)·I(n−1),   a = exp(−dt / tau_k)
```

`x_k(0)` is the current in RC branch *k* when the current stopped, computed from the **real** current history, so a 10 s pulse and a 2 h charge are both handled exactly. For a given set of taus the `R_k` (and `Vinf`) are a linear least-squares problem with `R_k ≥ 0`. The taus are found by a grid search over 1–3000 s and then refined with `fminsearch`. The pairs are sorted so that tau1 < tau2 < tau3 (`fitRelaxations`, `fitOneRelaxation`, `lsqNonnegTail`). Fits with an rms error above 8 mV are discarded.

### 7.6 OCV `batt_V0_vec`
1. Each relaxation's `Vinf` is an OCV point.
2. Low-rate (≤ 0.5 C) CC data, corrected with the tables found above, gives a dense curve: `OCV ≈ V − I·R0 − Σ R_k·x_k`. Charge and discharge are averaged per 1 % SOC bin, which cancels hysteresis (`denseOcvPoints`).
3. The dense curve gives the **shape** between rests and the rest points give its **level** (`buildOcv`). The table is forced to rise with SOC.

### 7.7 Thermal `batt_thermal_mass`, `batt_hA`
Lumped model of the cell in the chamber, with exactly the heat the Simscape block generates:

```
m·cp · dT/dt = Q − h·A · (T − T_chamber)
Q = I²·R0(SOC) + Σ_k R_k(SOC) · x_k²
```

First a least-squares fit on dT/dt (10 s grid, smoothed) gives a starting point. Then `m·cp` and `h·A` are refined so that the *simulated* temperature matches the measured one, which removes the bias from the smoothing (`fitThermal`, `simulateThermal`). This needs a cell temperature column, a chamber temperature column and at least 0.5 K of self-heating.

### 7.8 `batt_V_range`, `batt_T0`
Lowest and highest measured voltage; first cell-temperature reading in kelvin.

### 7.9 What your test needs for each value

| Value | Test must contain |
|---|---|
| AH, SOC0 | a CC-CV charge followed (later) by a discharge to the cut-off voltage |
| R0 | current steps logged at ≤ 5 s (pulses, step changes) |
| R_k, tau_k, OCV points | rests ≥ 5 min after charge/discharge pulses, spread over the SOC range (HPPC / GITT style) |
| OCV shape | low-rate (≤ 0.5 C) charge and/or discharge |
| thermal mass, h·A | `Temp 1` and chamber temperature columns, and visible self-heating |

### 7.10 Fixed analysis settings
These were "Extraction settings" boxes in the old version. They are now fixed in `constants()` at the top of `extractCellParameters.m`:

| Constant | Value | Meaning |
|---|---|---|
| `vTol` | 0.02 V | tolerance when matching the CV / cut-off voltage |
| `tauMin`, `tauMax` | 1 s, 3000 s | range searched for time constants |
| `minRestS` | 300 s | shortest rest used for RC / OCV fits |
| `maxFitRmse` | 8 mV | relaxation fits worse than this are dropped |
| `maxEdgeDt` | 5 s | current steps sampled coarser than this are not used for R0 |
| `ocvMaxCrate` | 0.5 C | fastest CC data used for the dense OCV curve |

---

## 8. Code walk-through

### `BatteryBuilder.m`
Builds the window: title, **Open CSV...**, file info, and a tab group. It calls `plotTab`, `loadProfileTab` and `modelingTab` to fill the three tabs. Each returns a small `api` struct (`setData`, ...). `openFile` reads the CSV with `loadBatteryCsv` and hands the dataset to all three tabs. `onDataChanged` passes the SOC column from the Modeling tab back to the Plot tab. `fig.UserData.api` exposes the tab APIs for scripting and tests.

### `src/loadBatteryCsv.m`
`findCol` matches column names loosely. `toSeconds` / `toNum` handle numbers, durations and time strings. The function drops rows missing time/V/I, sorts by time, sets the test temperature label, fixes the current sign (positive = charge) and adds the plot columns.

### `src/plotTab.m`
All state (`series`, zoom stack, drag/pan state, cursor handles) lives in variables shared by nested functions.

| Function | Job |
|---|---|
| `refreshPlot`, `addSeries` | draw the chosen columns (left / right axes) |
| `fitView`, `extentOf` | Fit all / horizontal / vertical |
| `applyZoom`, `pushZoom`, `zoomBack` | zoom and its undo stack |
| `onMouseDown/Move/Up` | box zoom, middle-drag pan, cursor |
| `onScroll`, `onKey` | wheel zoom, keys |
| `buildCursor`, `updateCursor`, `interpMono` | cursor line, markers and labels |

The figure-level mouse callbacks only act while the Plot tab is the visible tab (`tabVisible`).

### `src/loadProfileTab.m`
`setData` draws the profile and the summary. `buildProfile` adds the step points. `onSave` writes `batt_load`, `batt_load_ts` and `batt_load_tEnd`.

### `src/blockParameterList.m`
One entry per box: key, label, variable, block location, unit, group, required / optional, datasheet hint, RC pair number, and whether it is a per-SOC vector. **To add a box, add a row here** (and, if the data can give it, a key in `extractCellParameters`).

### `src/modelingTab.m`
`vals` holds each box's number and `src` says where it came from (`''`, `'calc'` or `'user'`).

| Function | Job |
|---|---|
| `onExtract` | run the extraction, then fill the green boxes and clear stale ones (user entries are kept) |
| `onEdit` | parse what you type |
| `refreshRows` | status text, colours and tooltips |
| `onSave` | write to the workspace; expand scalars; warn about missing boxes or length mismatches |
| `drawOverview` | the test overview and table plots on the right |

### `src/extractCellParameters.m`
The calculations, described in §7. Returns `R.value`, `R.found`, `R.note`, `R.diag` (data for the pop-ups), `R.d` (dataset with SOC) and `R.report` (text summary).

### `src/explainParameter.m`
One `case` per parameter: text (method, equation, table with M/I/E flags) plus one or two plots, e.g. an example relaxation with its fit, or an example current step with its ΔV/ΔI.

---

## 9. Validation

`tests/runValidation.m` writes 0 °C and 25 °C test files from a cell with known parameters (`makeSyntheticCellData.m`). The tests contain rest, CC-CV, a C/5 discharge, HPPC, a dynamic load and a logged cell temperature. Each file is run through the extraction and compared with the truth (SOC 0.1–0.95):

| | AH | OCV max error | R0 | R1 | R2 | tau1 | tau2 | m·cp | h·A |
|---|---|---|---|---|---|---|---|---|---|
| 25 °C | −1.3 % | 3.1 mV | 1.7 % | 2.8 % | 1.7 % | 1.5 % | 0.5 % | +0.4 % | +0.9 % |
| 0 °C | −1.5 % | 2.0 mV | 2.4 % | 3.4 % | 3.3 % | 1.3 % | 1.7 % | +1.3 % | +2.3 % |

(The AH difference is because the capacity is measured down to the test's cut-off voltage at C/5, as defined in §7.2.)

It also cuts a file down to 11 hours with no full discharge and no temperature columns. It checks that AH, SOC, OCV, R, tau and the thermal values all come back **empty**, and that typing in a datasheet AH then lets R0 and the RC pairs be calculated.

```matlab
cd tests
runValidation      % prints PASS / FAIL
```

---

## 10. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| "Could not find Current and Voltage columns" | Header names too different. Add your names to the `findCol` patterns in `loadBatteryCsv.m`. |
| Current sign looks wrong | Check the sign note in the top bar. With no State column the sign comes from dV/dt. |
| AH stays empty | No CC-CV charge followed by a full discharge to cut-off. Type the datasheet capacity into the AH box and press Extract again: SOC, R0 and the RC pairs can then be calculated. |
| R1/tau1 empty | No rests ≥ 5 min after current pulses. |
| OCV empty | The rests / low-rate data do not cover SOC 0..1. Use the datasheet OCV curve. |
| Thermal mass empty | No `Temp 1` / chamber column, or the cell heats by less than 0.5 K. Enter mass × specific heat. |
| Save warns about a length mismatch | You changed the SOC breakpoints after extracting. Press Extract again. |

---

## 11. Next steps (not in this version)

* Several temperatures: combine one file per temperature into `..._mat` tables (Tabulate over temperature = Yes).
* Separate charge / discharge R0 (Current directionality = Yes).
* Save / load a parameter set (.mat) from the Modeling tab.
* Optional automatic build of a test-bench Simulink model.
