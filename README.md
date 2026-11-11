# Battery Builder

A MATLAB app for lithium-ion cell test data. It has three tabs:

| Tab | What it does |
|---|---|
| **Plot** | Look at the test: cursor read-out, fit buttons, drag-to-zoom, middle-mouse pan. |
| **Load profile** | Shows the test's current profile and saves it to the workspace for a Simulink *Controlled Current Source*. |
| **Modeling** | One button pulls every parameter it can out of the test and fills in the boxes for the Simscape **Battery (Table-Based)** block. Empty boxes tell you what you still need from the datasheet. A second button saves everything to the workspace. |

Building and running the Simulink model is up to you. This app only produces the workspace variables the model needs.

**Presentation + video:** [`Modeling_Tab_Presentation.pptx`](Modeling_Tab_Presentation.pptx) (57 slides, Century Gothic, MATLAB charts as movable pictures, speaker notes) and [`Modeling_Tab_Presentation.mp4`](Modeling_Tab_Presentation.mp4) (the same deck presented with a voice-over, about an hour) explain how every Modeling-tab value is calculated from the charge and discharge cycles, why each method was chosen, and how to set up the thermal mass and h·A for the Simulink convection block. See §13.

---

## 1. Quick start

```matlab
cd 'C:\App Projects\BatteryBuilder'
BatteryDataBuilder                    % opens the app
BatteryDataBuilder('cell_25C.csv')    % opens it with a file already loaded
```

1. **Open CSV...** → pick one test file (one cell; charges at 25 °C, discharges at the test temperature).
2. **Plot** tab: look at the data.
3. **Load profile** tab: **Save load profile to workspace** → `batt_load`, `batt_stopTime`, `batt_Ts`, `batt_ambient`.
4. **Modeling** tab: **1. Extract data from test**. Fill in any orange *Required* boxes from the datasheet, then **2. Save to workspace** → `batt_*`.
5. In Simulink, type the `batt_*` names into the Battery (Table-Based) block (hover over any box to see where each one goes).

Requirements: MATLAB R2021a or newer. No toolboxes are needed for the app itself. Simscape Battery (or Simscape Electrical) is only needed for the Simulink model you build afterwards.

---

## 2. Files

```
BatteryDataBuilder.m              <- the ONLY file you run. Builds the window and the three tabs.
src/
  plotTab.m                   Tab 1 - interactive plot
  loadProfileTab.m            Tab 2 - current profile -> workspace
  modelingTab.m               Tab 3 - parameter boxes, Extract / Save buttons
  blockParameterList.m        the list of boxes on Tab 3 (variable names, where they go, datasheet hints)
  extractCellParameters.m     all the calculations (capacity, SOC, OCV, R0, RC pairs, thermal)
  explainParameter.m          the "How?" pop-up windows
  batterySources.m            the published sources behind each method (links shown in the "How?" windows)
  loadBatteryCsv.m            reads a cycler CSV
Modeling_Tab_Presentation.pptx   the presentation (§13)
Modeling_Tab_Presentation.mp4    the presentation, narrated (§13)
```

`BatteryDataBuilder.m` adds `src/` to the path itself, so you never need to touch the other files to use the app.

How the pieces talk to each other:

```
BatteryDataBuilder.m
   | Open CSV  -> loadBatteryCsv(file) -> d (dataset)
   |              d is handed to every tab: plotTab.setData(d), loadProfileTab.setData(d), modelingTab.setData(d)
   |
   +-- plotTab          (only displays d)
   +-- loadProfileTab   (d.t, d.I, d.Tch -> batt_load, batt_stopTime, batt_Ts, batt_ambient)
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
| StepTime (s) | the exact moment the current switched, for R0 and the RC fits |
| Temp 1 | cell temperature: thermal fit and initial temperature |
| Chamber Temperature (C) | ambient for the thermal fit (and `batt_ambient`), and the test temperature label: the median chamber temperature **during the discharges** (§7.0) |

### Current sign: positive = charge

Everywhere in the app, and in every saved variable, **positive current = charge (into the cell) and negative = discharge**. The loader works out which way round your file is:

* If there is a State column, it compares the sign of the current in C and D rows, or uses State to give a sign to a magnitude-only current.
* If there is no State column, charging current must make the voltage rise (checked with dV/dt).

The top bar of the app shows which case was found (e.g. *"magnitude in file, sign taken from the State column"*).

---

## 4. Tab 1: Plot

| Control | Action |
|---|---|
| X axis / Left Y / Right Y | Pick columns. Ctrl+click picks several. A right axis is shown when something is selected there. Changing any of them redraws and fits the view to every curve straight away. **(none)** at the top of a Y list leaves that axis empty. |
| **Load twin from workspace** | Adds the digital-twin signals at the bottom of both Y lists, under a separator (see below). Press again after a new simulation run. |
| **Same units -> same Y scale** | On by default. When every curve on the left **and** the right has the same unit, both Y axes get the same limits, so e.g. measured voltage (left) and twin voltage (right) lie on top of each other. The lock holds through every zoom, pan and fit. The box shows `(locked: V)`, or `(units differ)` when it cannot apply. Untick it to give each side its own scale again. |
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
| **Copy plot to a figure** | A normal MATLAB figure of the current view, for saving or printing (legend bottom-left). |
| Keys | `f` = fit all, `Backspace` = zoom back, `Esc` = cancel a drag. |

### Twin vs measured

Log the twin with To Workspace blocks named `twin_soc`, `twin_current`, `twin_voltage` and `twin_temp` (format **Timeseries** or **Structure With Time**; *Array* also works together with `tout`). They are read from the base workspace, or from `out` when the model uses "Single simulation output". They show up as `Twin: SOC (-)`, `Twin: Current (A)`, `Twin: Voltage (V)`, `Twin: Temp (°C)`, drawn dashed. The twin's time starts at 0 like `batt_load`, so it lines up with the test on any X column (time columns are extended past the end of the test). A temperature above 150 is taken to be kelvin and converted to °C; an SOC above 1.5 is taken to be percent.

Each twin signal has a measured partner: SOC ↔ `SOC (-)` (after Extract), current ↔ `Current, +charge (A)`, voltage ↔ the file's voltage column, temperature ↔ the cell temperature column (`Temp 1`). With both shown and the **Cursor** on, a yellow label on the other side of the cursor line shows `Δ = twin − measured` at the cursor position. When there is no room on that side (the cursor is near an edge), the label moves below the value labels instead.

**Comparing twin and measured.** Two ways, both on one scale:
* Put both in the **same** list (Ctrl+click), e.g. `Voltage (V)` and `Twin: Voltage (V)` on the left. That leaves the right axis free for something else, such as current.
* Or put one on each side, e.g. `Voltage (V)` left and `Twin: Voltage (V)` right. With **Same units -> same Y scale** ticked, the right axis copies the left one.

The unit is the text in the last brackets of the name (`Voltage (V)` → V); the temperature columns count as °C. A twin signal counts as having its measured partner's unit, so `Temp 1` and `Twin: Temp (°C)` lock together too (`unitKey`, `updateLock` in `plotTab.m`).


Extra columns added for plotting: `Test Time (h)`, `Current, +charge (A)`, `Power, +charge (W)`, `Net Ah in (Ah)`, and after an extraction `SOC (-)`.

The tab keeps **one** axes for its whole life, with both Y axes created up front; the right ruler is only hidden when nothing is picked for it. On every change the old lines are deleted, the new ones drawn, the view fitted, and ~0.25 s later the limits are applied once more and the axes repainted (`refreshPlot`, `repaintSoon`). Earlier versions deleted and re-created the axes on each change, which sometimes left the right-axis curves undrawn until a click or **Fit all** forced a repaint.

Pan is implemented in `plotTab.m` → `onMouseDown` (`SelectionType == 'extend'`, which is what MATLAB reports for the middle button) and `onMouseMove`, which turns the mouse movement in pixels into data units using the axes' size in pixels.

---

## 5. Tab 2: Load profile

The plot shows the current over the whole test: green = charge (+), orange = discharge (−).

**Save load profile to workspace** writes:

| Variable | Contents |
|---|---|
| `batt_load` | `[t I]`, N×2. Time in seconds from 0, current in A, **+ = charge**. |
| `batt_load_ts` | the same data as a `timeseries` |
| `batt_stopTime` | length of the test (s): set the model **Stop time** to `batt_stopTime` |
| `batt_Ts` | the test's sampling interval (s, the median spacing of the time stamps): use it as the To Workspace **Sample time** (or a fixed-step solver's step size) so the twin is logged like the real test |
| `batt_ambient` | `[t T]`, N×2: the **chamber temperature in kelvin** on the same time points as `batt_load`, for the battery's thermal port. Missing readings are bridged linearly. Not written (and the list says why) if the file has no chamber temperature column. |
| `batt_ambient_ts` | the same as a `timeseries` |

The list under the button shows these values, plus the test's shortest and longest logging interval (cyclers often log faster during pulses than during rests, which is why the median is used).

### Pulse labels

Every charge and discharge pulse (a run of current with one sign) is labelled with:

* its **C-rate**, `|I| / AH`: the level it spends most of its time at (`CC`), the CC current of a tapering charge (`CC-CV`), or the average and peak for a varying load (`avg …C, max …C`);
* the **Ah** that went in (`+`) or came out (`−`) during that pulse: `Σ I·Δt / 3600`.

The C-rate needs the capacity: press **Extract** on the Modeling tab (or type an AH there) and the labels update. Until then the labels show amps. Labels that would overlap are hidden, biggest pulses first; zoom in to see the rest (`findPulses`, `layoutLabels` in `loadProfileTab.m`).

### Using it in Simulink

```
From Workspace  ->  Simulink-PS Converter  ->  Controlled Current Source  ->  Battery (Table-Based)
 Data: batt_load       output unit: A           + (arrow head) -> battery +
 Interpolate: on                                -               -> battery -
 Final value: Holding final value
```

With the source wired head-to-battery-plus, a positive signal pushes current **into** the battery, which is charging. That matches the sign of `batt_load`.

Thermal port (block option *Thermal model* = lumped thermal mass):

```
From Workspace  ->  Simulink-PS Converter  ->  Controlled Temperature Source  ->  Convective Heat Transfer  ->  Battery port H
 Data: batt_ambient    output unit: K           port A -> Thermal Reference        Area = 1 m^2
 Interpolate: on                                port B -> Convective block A       coefficient = batt_hA
```

Kelvin is used so the Simulink-PS Converter needs no affine (°C) conversion. A chamber that holds one temperature makes `batt_ambient` almost flat, but it still carries the real drift of the test, which the thermal fit (§7.7) used too.

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
4. **How?** (on green boxes) opens a window that walks through the calculation step by step: what the parameter means in the block, the equations (rendered in LaTeX), the actual numbers from your file plugged into them (a worked example), the final table, and plots of the data it came from.
   A box whose cross-check failed shows **⚠ Check** instead of ✓ (e.g. AH vs the cycler's own Capacity column, or SOC0 vs the voltage).
5. **2. Save to workspace** writes every filled box as its `batt_*` variable and tells you which required boxes are still empty.

**Hover over any box** to see its workspace variable name and exactly where it goes in the block dialog.

### Block set-up this app assumes

These options stay the same as before; set them once in the block dialog:

| Block option | Setting |
|---|---|
| Charge dynamics | the **Charge dynamics (RC pairs)** drop-down on the tab (1, 2 or 3; default 2). Saved as `batt_nRC`. |
| Tabulate parameters over temperature | **Yes** when the file has two temperatures (charges at 25 °C, discharges at T ≠ 25 °C): Vector of temperatures T = `batt_T_vec` (K), and V0, R0, R1.., tau1.. are SOC × T matrices. **No** for the 25 °C file (one temperature, the tables are vectors). The tab shows which one. |
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
| Temperature breakpoints T | `batt_T_vec` | Main › Vector of temperatures, T (K) | the chamber during the discharges and during the charges, when they differ by > 3 K (§7.0) | n/a (empty = one temperature) |
| Open-circuit voltage V0(SOC,T) | `batt_V0_vec` | Main › Open-circuit voltage, V0(SOC,T) | zero-current line through the discharges at several rates; long rests at the two ends | OCV-vs-SOC curve. **Required.** |
| Terminal voltage range | `batt_V_range` | Main › Terminal voltage operating range [Min Max] | min / max measured | cut-off voltages. Optional. |
| Terminal resistance R0(SOC,T) | `batt_R0_vec` | Main › Terminal resistance, R0(SOC,T) | first sample after each step from a rest | DC internal resistance. **Required.** |
| Cell capacity AH | `batt_AH` | Main › Cell capacity, AH (A*hr) | full CC-CV → discharge to cut-off | rated capacity. **Required.** |
| Self-discharge resistance | `batt_Rleak` | Main › Self-discharge resistance, Rleak | never (needs weeks of storage) | Optional |
| R1..R3(SOC,T), tau1..tau3(SOC,T) | `batt_R1_vec`, `batt_tau1_vec`, ... | Dynamics › polarization resistance / time constant | the first minutes after each step from a rest; R scaled to the measured R_dc at the other SOCs | rarely published. **Required** for the pairs in use. |
| Thermal mass | `batt_thermal_mass` | Thermal › Thermal mass (J/K) | cell temperature self-heating | mass × specific heat. **Required.** |
| Convection h·A | `batt_hA` | *not a battery parameter*: Convective Heat Transfer block, Area = 1 m², coefficient = `batt_hA` | cell temperature self-heating | depends on your fixture. Optional. |
| Initial SOC | `batt_SOC0` | Initial Targets › State of charge | SOC at the first sample | Optional |
| Initial cell temperature | `batt_T0` | Initial Targets › Cell temperature (K) | first cell-temperature reading | Optional |

A single number typed into an SOC-table box (e.g. one datasheet resistance) is copied to every SOC point when saved.

### What "no guessing" means here

* A box is only filled from the data if the data really contains what that value needs. Otherwise it stays empty and says why.
* There are **no** built-in default values. The old version's "assumed" fallbacks are gone.
* A capacity you type in is only used to build the SOC axis when the test has no complete full-to-empty discharge. The AH box then still shows **Entered by you**, not "From data".
* Between two measured SOC points a table is linearly interpolated. Beyond the measured SOC range the end value is held, which is what the block's *Nearest* extrapolation would do anyway. Every table entry is labelled in its **How?** window: `M` measured near that SOC, `I` interpolated, `E` end value held, `S` R1..R3 scaled so R0 + ΣR_k equals the R_dc measured at that SOC (§7.5). R0 itself is never scaled.
* Points taken while the cell was more than 3 K away from the chamber temperature (e.g. right after the 5.8C discharge) are left out of the tables: they belong to a different temperature.
* The OCV table is only filled if the data covers the whole SOC range. Past the data it extends at most 0.01 SOC.

---

## 7. How each value is calculated

All of this is in `src/extractCellParameters.m`, in the same order as below. Every method is tied to published work or MathWorks documentation; the tags in square brackets, such as [INL15], point to the reference list in §12. The same sources are listed, with links, at the bottom of every **How?** window (`src/batterySources.m`).

### 7.0 The model, and what your test can measure

The Battery (Table-Based) block [MW-TB], built on [Huria12], is an equivalent circuit: an OCV source, a series resistance R0 and up to three RC pairs, all as tables over SOC. Written with *i* = discharge current (positive):

```
V        = V0(SOC) − i·R0(SOC) − Σ_k R_k(SOC)·x_k        terminal voltage
dx_k/dt  = (i − x_k) / tau_k(SOC)                         current through RC pair k's resistor
SOC      = SOC0 − ∫ i dt / (3600·AH)                       coulomb counting
m·cp · dT/dt = i²·R0 + Σ_k R_k·x_k² − h·A·(T − T_amb)      lumped thermal mass + convection
```

**Your test** is a rate test of about 70 h: 5 CC-CV charges and 5 discharges to the cut-off, with rests in between. Most files use 0.1C, 0.2C, 0.5C and 1C, then one fast discharge that varies from about 3C to 7C:

```
0.34C CC-CV charge → 0.1C discharge to cut-off → 0.34C CC-CV → 0.2C → 0.34C CC-CV → ~0.5C
                   → 0.34C CC-CV → 1C → 0.34C CC-CV → ~3-7C          (with rests in between)
```

**The chamber schedule.** One file = one test temperature T, but the chamber is not at T all the time:

```
25 °C : rest → CC-CV charge
   T  : (right after the charge) rest → discharge
25 °C : (right after the discharge) rest → next charge ...            and so on, 5 times
```

So every **discharge** runs at the file's temperature T and every **charge** runs at 25 °C. What that means for the extraction:

* **Test temperature label** (`d.T_C`, what the tables are "for") = the median chamber temperature over the *discharge* samples. The median over the whole file can land on 25 °C for a cold test, because about half the test is at 25 °C (`loadBatteryCsv.m`). The top bar says so when the chamber moves by more than 3 K.
* **Two table temperatures.** In a file that is not at 25 °C the tables are built at **both** chamber temperatures (`d.T_C` for the discharges, `d.T_chg_C` for the charges), each from the data taken with the cell within ±3 K of it (§7.10 `maxDT`). They are saved as SOC × T matrices with `batt_T_vec = [T_low T_high] + 273.15` K, for the block option *Tabulate parameters over temperature = Yes*. `extractCellParameters` runs the table part once per temperature; `R.byT{j}` is the full result for `T_vec(j)`, and every **How?** window for a table opens once per temperature.
  * **Test temperature (discharges):** R0 and the RC pairs from the start of each discharge (SOC 1, after the 3 h rest at T), OCV and R_dc from the discharges at several rates. AH, SOC, SOC0 and the thermal values come from here too (AH is one number in the block).
  * **25 °C (charges):** R0 and the RC pairs from the start of each charge (near SOC 0, after the rest back at 25 °C), R_dc from the CC part of the charges (§7.5). There are no discharges at 25 °C, so V0 at 25 °C is the test temperature's V0 (the OCV changes only a few mV over 25 K). A table that cannot be measured at one temperature is copied from the other one so the block gets a full matrix, and its note says **COPIED**.
* **In the 25 °C file** everything is at 25 °C: one temperature, and the steps from rest at SOC 1 (discharges) and near SOC 0 (charges) both count.
* **What is NOT used: the rests after a step.** After a discharge the chamber goes back to 25 °C straight away, so the cell warms by ~25 K during that rest; after a charge it cools to T. The relaxation there is mixed with the temperature change, and fitting RC pairs to it gave nonsense (R1 of ~900 mΩ, tau at its 3000 s limit, worse with every extra pair). The start of each step is taken after a 3 h rest at a steady temperature, sampled from 0.05 s on, so that is where the dynamics are measured.
* **Thermal fit and `batt_ambient`** use the chamber column as it is, steps and all, so the 25 ↔ T switching is in the heat balance and in the Simulink ambient. `batt_T0` is the first cell reading (≈ 25 °C, because the chamber starts at 25 °C), which is the right start for a simulation driven by `batt_ambient`.

That decides what can be measured, and where:

| Quantity | Where this test shows it | How (section) |
|---|---|---|
| AH | every discharge from FULL to the cut-off; the slowest one (0.1C) is used | 7.2 |
| SOC | everywhere, by coulomb counting from FULL | 7.3 |
| OCV | **the whole SOC range**: the same discharge at 4 rates is extrapolated to zero current | 7.6 |
| R_dc = R0 + R1 + R2 | **the whole SOC range**: the slope of the same fit | 7.6 |
| R0 on its own | only where the current **starts from a rest**: each discharge (SOC 1, at T), each charge (SOC ≈ 0 … 0.03, at 25 °C) | 7.4 |
| R1, R2, tau1, tau2 on their own | the first minutes after those same steps | 7.5 |
| m·cp, h·A | the 5.8C discharge heats the cell, which then cools in the rest | 7.7 |

So in the middle of the SOC range the **sum** R0 + R1 + R2 is measured, but not how it splits between them: the current never starts from a rest there. The tables are built to respect that (§7.5, the `S` flag), and nothing is filled in from outside the file.

### 7.1 Phases
The current is split into runs of **charge** (I > 0), **discharge** (I < 0) and **rest** (I = 0). Back-to-back steps of the same kind merge, so a CC step plus a CV step is one charge phase (`findPhases`).

A charge phase is a **CC-CV charge** when its current has tapered below 35 % of its maximum while the voltage over the taper stayed within 15 mV. That flat voltage is the CV voltage (`cvPhases`).

### 7.2 Capacity `batt_AH`
* **FULL** = the end of a CC-CV charge at the highest CV voltage.
* **EMPTY** = the end of a discharge that is at least 5 minutes long, stopped at the cut-off, *and* ended on the end-of-discharge knee: over its last 3 % the voltage falls more than 3× faster per Ah than over its middle half (`endsAtKnee`). The cut-off is the lowest **end** voltage of all long discharges, so a short pulse that dips below the cut-off cannot move it. The knee check stops a partial discharge, like one HPPC step, from being mistaken for empty.
* `AH = Ah_in(FULL) − Ah_in(EMPTY)` with `Ah_in = Σ I·dt / 3600` (zero-order hold).
* **Which discharge:** your test has five FULL→EMPTY discharges. A faster discharge reaches the cut-off sooner because more voltage is lost over the resistance, so it delivers fewer Ah. The **slowest (0.1C)** comes closest to the charge actually stored and is the one used. The AH **How?** window lists all five as a rate-capability table.
* **Cross-check:** if the file has its own `Capacity (Ah)` column, the same discharge is added up from it too (`fileCapacity`; the column restarts at 0 on every step). The two should agree within ~1 %; more than 2 % apart marks the box **⚠ Check**.

*Sources:*
* [INL15] §3.2: the static capacity test is a constant-current discharge from fully charged to the minimum voltage, after a rest.
* [Barai19] §2: the capacity tests in the standards, and the fact that the measured capacity depends on the C-rate (impedance and heating).
* [Lin14]: capacity is the charge between 100 % (end of the CV charge) and 0 % (end of discharge).

### 7.3 SOC and `batt_SOC0`
Coulomb counting that resets to SOC = 1 at every FULL point: `SOC = 1 + (Ah_in − Ah_in(FULL)) / AH`. This is the same SOC definition the block uses [MW-TB]. Before the first full charge the same line is run backwards, so

```
SOC0 = 1 − (Ah put in between the first sample and the first FULL point) / AH
```

If it took almost a whole AH to fill the cell, the file started almost empty, and SOC0 is close to 0. That is normal when a test starts on a cell left at its cut-off: once the current stops, the voltage of a lithium-ion cell recovers to ~3.1–3.3 V even though it is empty.

After a fast discharge (1C, 5.8C) the cell hits the cut-off with charge still in it. SOC keeps counting with the 0.1C AH, so it correctly shows e.g. SOC 0.1 there, not 0.

**Cross-check against the voltage** (`socVoltageCheck`):
* The relaxed voltage of the first rest (the rest the file starts in, or else the first ≥ 10 min rest) is read backwards through the OCV table and compared with the coulomb-counted SOC at that moment.
* For comparison, the window also shows the voltage the cell relaxed to after the discharge to cut-off (SOC 0 by definition).
* A difference of more than 0.08 marks the box **⚠ Check**. So does a difference larger than the check's own uncertainty: 5 mV divided by the local OCV slope, which is large on flat curves such as LFP.

*Sources:*
* [Chang13]: coulomb counting ("book-keeping") and its error sources. It needs a known starting point (here FULL) and an accurate capacity (here §7.2).
* [Lin14]: the same 100 % / 0 % definition.

### 7.4 R0 `batt_R0_vec`
At every charge or discharge that starts after a rest of at least 10 min (`findOnsets`):

```
R0 = (V_first − V_rest) / I
```

* **V_rest** is the last rest sample. After a rest the voltage is steady and every RC pair is empty, so nothing but R0 explains the jump.
* **V_first** is the first sample after the switch. The cycler logs it 0.03–0.05 s after the switch (the `StepTime` column says exactly when); an RC pair's capacitor has no time to charge in that. Steps whose first sample is more than 1 s after the switch are not used.
* **I** is the step's constant current (median of its first samples), not the first reading: the first reading can spike. In the sample cycle the 0.1C step logs 0.343 A for one sample of a 0.265 A step, while its voltage drop (12.4 mV) matches 0.265 A. With the set current every rate gives 44–47 mΩ; with the spike the 0.1C step would give 36 mΩ.
* **Temperature.** A step is used for the table of the temperature the cell was at (within 3 K).
* **To the table.** The median of the steps at each SOC (`gridPoints`), straight line between SOCs, end values held. A rate test only starts from rest at one SOC per temperature, so in practice R0 is one number per temperature, held over SOC. R0 is **not** scaled anywhere: the extra resistance a constant current feels (R_dc − R0) goes to the RC pairs (§7.5).
* **Check by hand** (sample cycle, 0 °C, 0.5C): 4.18296 → 4.12360 V at 1.325 A → R0 = 44.8 mΩ. At 25 °C (charge from rest): 3.0962 → 3.1164 V at 0.8835 A → 22.9 mΩ.
* **Current dependence.** At 0 °C the 15 A (5.8C) step gives 35 mΩ against 44–47 mΩ for 0.1–1C: the cell's resistance falls as the current rises. The block has one R0, so the median is used, and the R0 **How?** window lists every step so you can see it.

*Sources:*
* [INL15] §4.4.2, eq. 4: R = ΔV/ΔI across the pulse edge.
* [MW-Char]: R0 from the sudden voltage change at a pulse.
* [Schweiger10]: the current-step method compared with AC and EIS methods.
* [Lin14]: R_s from the initial voltage jump.

### 7.5 RC pairs `batt_R1_vec`, `batt_tau1_vec`, ...
Measured on the **same steps from rest** as R0 (`fitDynamics`, `fitCluster`). The current is constant and every RC pair starts empty, so the block's voltage after the step is

```
V(t) = V_rest + I·[ R0 + Σ_k R_k·(1 − exp(−t/tau_k)) ] + s·I·t/3600
```

with `s` the OCV slope (V per Ah: the OCV moves as charge goes in or out). Divided by I this is the resistance the cell shows t seconds after the step, `(V − V_rest)/I`, which the R1 **How?** window plots straight from the data (log time axis) with the fit on top.

* **Window.** The first 600 s after each step, at most 1 % of SOC (so the OCV is close to a straight line), constant current, cell within 3 K of its temperature at the step, rates up to 2C.
* **Fit.** All steps at the same SOC (within 0.03) are fitted together. They share the time constants tau_k and the OCV slope s (same cell, same SOC); **each step gets its own R_k**. For given tau_k everything else is linear (R_k, s ≥ 0, `lsqnonneg`). The tau_k are searched on a log grid (0.5 s up to half the longest window, at least 2× apart), then refined with `fminsearch`. Each step gets the same weight, in ohms.
* **Why R_k per step.** At 0 °C the steps from the sample cycle do not agree: 100 s after the step the cell shows ~180 mΩ at 0.1C but ~115 mΩ at 1C. The cell's resistance falls with current; a linear block cannot do that. Forcing one R_k on every rate left 5–34 mV of error per step; sharing only the tau_k and letting R_k follow each step leaves 0.4–6 mV. The table takes the **median** R_k of the steps.
* **How many pairs.** The fit is always run with 1, 2 and 3 pairs and the RC **How?** window lists the rms error of each. More pairs can only lower it, and the window says so when a pair hardly helps. Sample cycle, 0 °C: 9.0 / 4.0 / 3.5 mV; 25 °C: 2.6 / 0.65 / 0.36 mV. A pair the fit leaves empty (R = 0 at every step) is reported as *not resolved – use fewer RC pairs*, never filled in.
* **From one SOC to the whole table: R_dc.** The steps are at one SOC, but the total resistance a constant current feels once the pairs are full,

  ```
  R_dc(SOC) = R0 + Σ_k R_k
  ```

  is measured at almost every SOC: at the test temperature from the discharges at several rates (§7.6), at 25 °C from the CC part of the charges, `R_dc = (V_charge − V0(SOC)) / I` (`chargeRdc`; V0 is the table itself, linear between breakpoints as the block uses it). At every breakpoint with an R_dc, all R_k are scaled by **one** factor `f = (R_dc − R0) / Σ R_k,step` (flag `S`); tau_k and the split between the pairs stay as the step fit found them. Between the step SOC (f = 1) and the R_dc points, f goes in a straight line. R_dc at a breakpoint = the median of the 1 % SOC points nearest it (`gridMedian`).
* **25 °C R_dc and hysteresis.** The charge-side R_dc also holds the gap between the charge and discharge OCV, which the block does not model. With it the model charges at the measured voltage (the twin's charge voltage error in §9). It is the right resistance for charging at 25 °C, not for a 25 °C discharge, which this file does not contain.

*Sources:*
* [Lin14]: the voltage response fitted by least squares as a sum of exponentials; 1, 2 and 3 RC pairs compared.
* [MW-Char], [MW-HPPC]: MathWorks fits R_i, tau_i to the voltage segments around each pulse.
* [Hu12]: a comparison of 12 equivalent-circuit structures.
* [Jackey13]: fitting large lookup tables in layers.

### 7.6 OCV `batt_V0_vec` and R_dc: the multi-rate fit (`multiRate`)
1. **Wait until the RC pairs have filled up.** Once every RC branch current equals the discharge current, the block's equation (§7.0) becomes a straight line in *i*:
   ```
   V(SOC, i) = V0(SOC) − i · R_dc(SOC),     R_dc = R0 + R1 + R2
   ```
   A sample is used once what is left of each RC transient, `R_k·i·exp(−t/tau_k)`, is below 1 mV. R_k and tau_k come from the **3-pair** fit of the steps at SOC 1 (§7.5), whatever number of pairs you pick, so the OCV and R_dc do not change with the RC pair count. Sample cycle: 6, 8 and 10 min for 0.1, 0.2 and 0.5C.
2. **Line the discharges up on one SOC axis.** Each discharge starts from FULL, so its SOC is exact (§7.3). Its voltage is averaged in 1 % SOC bins; bins the data only partly covers are skipped.
3. **Fit a straight line per bin.** At each 1 % of SOC: voltage against current over the discharges at ≤ 2C, using only samples with the cell within 3 K of the chamber. **intercept** (i = 0) = V0 (discharge side); **slope** = R_dc. With 3 or more rates the scatter around the line is reported. In the sample cycle the 1C discharge warms the cell past 3 K (left out) and a third of the 0.5C one does; the 5.8C one is past 2C.
4. **Discharge side only.** The block has one OCV; the discharge-side one makes the discharges come out right. The charges at 25 °C get their own R_dc (§7.5), which takes up the hysteresis.
5. **The two ends.** The very top (still settling) and the very bottom have no line. There the voltage at the **end of every rest of at least 1 h** is used (`restOcvPoints`): after a full charge the cell rests at its SOC-1 OCV, after a discharge at the OCV of the SOC it stopped at. A smooth (pchip) curve joins them to the line (`ocvFromMultiRate`). The table is forced to rise with SOC. The rests after a discharge end at 25 °C (the chamber has gone back); the OCV changes only a few mV with temperature.

With fewer than two discharge rates from FULL there is no OCV from the data (the note says why): enter the datasheet curve.

*Sources:*
* [Petzl13]: low-current curves still carry overpotential; the true OCV is the zero-current value.
* [Yao18]: U = U_ocv(SOC) − I·R(SOC) over several discharge rates, giving R from their voltage difference.
* [Bussios24]: pseudo-OCV curves at several C-rates extrapolated to zero current.
* [Barai19] §3: pseudo-OCV from slow cycling.
* [INL15] §4.4.2: OCV from rest points.

**Honest note:** no single paper found does exactly this combination: a straight-line fit at each SOC over full discharges at several C-rates, intercept = OCV and slope = R_dc. Its pieces are all in the sources above, and the straight line itself is just the block's own voltage equation once the RC pairs have settled.

### 7.7 Thermal `batt_thermal_mass`, `batt_hA`
Lumped model of the cell in the chamber:

```
m·cp · dT/dt = Q − h·A · (T − T_chamber)
Q = I·(V − V0(SOC)) − Σ_k R_k·x_k·(I − x_k)          (I + = charge)
```

* **The first term** is the electrical power lost inside the cell: current times the gap between terminal voltage and OCV. This is the irreversible heat of Bernardi's energy balance [Bernardi85], used the same way in [Lin14]. It comes from the **measured** voltage, so it stays right when the 5.8C discharge has warmed the cell and its real resistance has dropped. I²R from the 25 °C tables would invent heat there.
* **The second term** takes out the power that is only being stored in the RC capacitors; it comes back as heat in the following rest. With the block's voltage equation, Q is then exactly the block's own heat `I²·R0 + Σ R_k·x_k²`, in the right moments.
* **Left out:** the reversible (entropic) heat I·T·dV0/dT. It needs the OCV at several temperatures, and the block leaves it out too.

**Fitting.** A least-squares fit on dT/dt (10 s grid, smoothed) gives a starting point. Then `m·cp` and `h·A` are refined so that the *simulated* temperature matches the measured one, which removes the bias from the smoothing (`fitThermal`, `simulateThermal`). This needs a cell temperature column, a chamber temperature column and at least 0.5 K of self-heating.

**Sanity checks:**
* m·cp ≈ cell mass × ~1 J/(g·K). [Maleki99] measured 0.96–1.04 J/(g·K) on an 18650.
* h = h·A / (cell surface area) should land in 2–25 W/(m²·K) for still air [Incropera]. More than that means the fixture (clamps, cables, tray) carries heat away too, which is fine: h·A describes *your* set-up.

*Sources:* [Bernardi85], [Lin14], [Forgez10] (lumped thermal model, heat capacity and h identified from measured temperatures), [Maleki99], [Incropera]. For the Simulink side: [MW-Conv] and [MW-CTS].

### 7.8 `batt_V_range`, `batt_T0`
Lowest and highest measured voltage; first cell-temperature reading in kelvin.

### 7.9 What your test needs for each value

| Value | Test must contain |
|---|---|
| AH, SOC0 | a CC-CV charge followed (later) by a discharge to the cut-off voltage |
| OCV + R_dc over the whole SOC range | **2 or more** CC discharges from FULL at different rates (≤ 2C), with the cell near the chamber temperature (your rate test) |
| R0 | a charge or discharge that starts after a rest ≥ 10 min, first sample ≤ 1 s after the switch |
| R_k, tau_k | the same steps, ≤ 2C. At other SOCs scaled to R_dc; at several SOCs on their own only with pulses from rest there (HPPC / GITT) |
| OCV ends | rests ≥ 1 h after the full charge and after the discharge to cut-off |
| thermal mass, h·A | `Temp 1` and chamber temperature columns, and visible self-heating (your 5.8C step) |

### 7.10 Fixed analysis settings
These were "Extraction settings" boxes in the old version. They are now fixed in `constants()` at the top of `extractCellParameters.m`:

| Constant | Value | Meaning |
|---|---|---|
| `vTol` | 0.02 V | tolerance when matching the CV / cut-off voltage |
| `minRestS` | 600 s | a step counts as "from rest" when the rest before it lasted this long |
| `maxEdgeDt` | 1 s | the first sample after the switch must be this close to it (R0) |
| `minStepC` | 0.08 C | smaller steps are not used |
| `onsetMaxS`, `onsetMaxDSOC` | 600 s, 0.01 | RC fit window after each step |
| `tauMin` | 0.5 s | shortest time constant (longest: half the window) |
| `clusterSOC` | 0.03 | steps closer than this in SOC are fitted together |
| `maxDT` | 3 K | data with the cell further than this from a table's temperature is not used for it |
| `mrMaxCrate` | 2 C | fastest step / discharge used in the RC and multi-rate fits |
| `settleV` | 1 mV | multi-rate fit: RC transient left over before a sample is used |
| `settleNoFit` | 1800 s | ... the wait instead, when there are no RC pairs |
| `ocvRestS` | 3600 s | rests at least this long give an OCV point (the ends of the curve) |

---


## 8. Code walk-through

### `BatteryDataBuilder.m`
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
`setData` draws the profile and the summary. `buildProfile` adds the step points. `findPulses` splits the current into charge / discharge pulses and `makeLabels` / `layoutLabels` put their C-rate and Ah labels on the plot. `onSave` writes `batt_load`, `batt_load_ts`, `batt_stopTime` and `batt_Ts`.

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
The calculations, described in §7. `findOnsets` / `fitDynamics` / `fitCluster` (R0 and the RC pairs from the steps from rest), `multiRate` (the zero-current fit over the discharge rates), `chargeRdc` (R_dc from the charges), `buildTables` (onto the SOC breakpoints, scaled to R_dc) and `ocvFromMultiRate`. Returns `R.value`, `R.found`, `R.note`, `R.diag` (data for the pop-ups), `R.d` (dataset with SOC) and `R.report` (text summary).

### `src/batterySources.m`
The reference list (§12) and, per parameter, what each source supports. The **How?** windows show it as clickable links (`uihyperlink`).

### `src/explainParameter.m`
One `case` per parameter. The left side is a scrolling list of blocks built with four small helpers: `H` (heading), `P` (paragraph), `EQ` (an equation, shown with a LaTeX `uilabel`) and `M` (a monospaced table with the M/I/E flags). Each window explains what the parameter means, the model equations, the method step by step, and a worked example with this file's own numbers (e.g. `AH = Q_in(full) − Q_in(empty) = …`, an example step's (V_first − V_rest)/I, the R_k of every step and the rms error with 1, 2 and 3 pairs). The right side has one or two plots of the data itself: the raw samples around a step, `(V − V_rest)/I` after every step with the fit on top, every discharge on one SOC axis, V against current at one SOC.

---

## 9. Validation

**0. The sample cycle (`task.txt`).** A made-up file shaped exactly like the real 0 °C tests: 25 °C CC-CV charges, 3 h rests while the chamber moves, discharges at 0.1 / 0.2 / 0.5 / 1C and 15 A (5.8C) at 0 °C. The extracted tables were put through the block's own equations (`V = V0 + I·R0 + Σ R_k·x_k`, SOC from the coulomb count, the measured cell temperature to pick between the 0 °C and 25 °C columns) over the whole test, and compared with the measured voltage:

rms of twin − measured over SOC 0.05–0.95 (the knee and the very top are discussed below):

| RC pairs | 0.1C | 0.2C | 0.5C | 1C | 25 °C charges |
|---|---|---|---|---|---|
| **this version**, 1 / 2 / 3 | 6.8 / 6.8 / 6.8 mV | 9.1 / 9.1 / 9.1 mV | 26 / 26 / 26 mV | 135 / 135 / 135 mV | 5–9 mV |
| previous version, 1 | 12 mV | 34 mV | 94 mV | 85 mV | 51–52 mV |
| previous version, 2 | 237 mV | 435 mV | 841 mV | 1259 mV | 30–32 mV |
| previous version, 3 | 473 mV | 758 mV | 1463 mV | 2227 mV | 114–115 mV |

Over the middle of the SOC range the result hardly depends on the number of pairs: R_dc fixes what a constant current feels there, and the pairs only shape the first minutes after a step (where 1 / 2 / 3 pairs give 9.0 / 4.0 / 3.5 mV, §7.5). The previous version got **worse with every RC pair** (whole test 116 → 780 → 1126 mV rms), because it fitted the pairs to the rests in which the chamber was warming the cell by 25 K. What is left now:
* **1C**: the cell's resistance falls with current, and the cell warms to 11 °C; a linear block with one table cannot match every rate (§7.5).
* **Last few % of SOC**: the knee falls between the breakpoints 0 and 0.05. More breakpoints there (e.g. 0.02, 0.03) follow it more closely.
* **SOC 0.95–1**: the OCV curves sharply there; a breakpoint at 0.98 or 0.99 helps.
* **15 A**: the cell heats to 60 °C, far outside the 0–25 °C tables, so the twin is far off there. Only a test at that temperature can fix that.

Sections 1–3 were run on the **previous** version (RC pairs from the rests); they have not been re-run on this one. The extraction was validated on test files written from a cell with **known** parameters (a 2-RC cell with a lumped thermal mass, the same structure as the block). Each file is run through the extraction and compared with the truth. The validation scripts (`tests/runValidation.m`, `tests/makeSyntheticCellData.m`) are no longer in the repository; they are in the git history (commit `0cd3cc2`) if you want to re-run them.

**1. Your profile (the rate test).** `makeSyntheticCellData(dir, 25, 'rate')`:
* the cell starts nearly empty;
* 0.34C CC-CV charges alternate with 0.1 / 0.2 / 0.51 / 1 / 5.8C discharges to the cut-off, with 2 h rests (~53 h);
* there are no pulses at mid SOC;
* the 5.8C step heats the cell by ~25 K.

| AH | SOC0 error | OCV max error (all SOC) | R0+R1+R2 (SOC 0.05–0.95) | R0 | tau2 | m·cp | h·A |
|---|---|---|---|---|---|---|---|
| −0.8 % | 0.000 | 0.9 mV | 4.6 % | 9.5 % | 5.5 % | −2.8 % | +2.8 % |

The multi-rate fit used the 0.1–1C discharges. One step and one rest at the end of the 5.8C discharge were left out as too hot. Before the rate-test changes, the same file gave R0 about 50 % low at mid SOC (only interpolated, with a hot end point), so this is the change that matters for your data.

**1b. Your profile with the real chamber schedule.** `makeSyntheticCellData(dir, [25 10], 'chamber')`: charges at 25 °C, rest + discharge at T, 0.1 / 0.2 / 0.5 / 1 / 5C, 3.6 h rests, 69 h, the chamber following its set-point with a 10 min lag:

| file | label | OCV found | OCV max error | R0+R1+R2 (SOC 0.05–0.95) | AH | OCV charge side |
|---|---|---|---|---|---|---|
| 25 °C | 25.0 °C | yes | 1.0 mV | 4.6 % | −0.8 % | 0.34C charge |
| 10 °C | 10.0 °C | yes | 2.8 mV | 7.5 % | −0.8 % | none (charges at 25 °C) |

The synthetic cell does not reproduce the poorly defined post-CV rest fits that real data gives, so it cannot show the old 25 °C failure itself; it checks that the schedule is handled and that nothing else changed.

**2. An HPPC test** (rest, CC-CV, C/5 discharge, HPPC, dynamic load) at 25 °C and 0 °C, compared over SOC 0.1–0.95:

| | AH | SOC0 | OCV max error | R0 | R1 | R2 | tau1 | tau2 | m·cp | h·A |
|---|---|---|---|---|---|---|---|---|---|---|
| 25 °C | −1.3 % | 0.501 (error 0.000) | 3.1 mV | 1.2 % | 2.8 % | 1.7 % | 1.5 % | 0.5 % | +9.2 % | +0.7 % |
| 0 °C | −1.5 % | 0.500 (error 0.000) | 2.0 mV | 1.8 % | 3.4 % | 3.3 % | 1.3 % | 1.7 % | +2.6 % | +0.2 % |

This file has only one full discharge, so it uses the older OCV method. Its few-mV OCV error ends up in the heat estimate I·(V − OCV) over many hours, hence m·cp +9 %. The AH difference is because the capacity is measured down to the test's cut-off voltage at C/5, as defined in §7.2.

**3. No guessing.** A file cut down to 11 hours with no full discharge and no temperature columns must give AH, SOC, OCV, R, tau and the thermal values all **empty**. Typing in a datasheet AH then lets R0 and the RC pairs be calculated.

Synthetic data only proves the method recovers values that are really there. On real data the remaining differences come from things the synthetic cell does not have, such as hysteresis and a resistance that changes with rate. Each **How?** window shows the cross-checks:
* AH against the cycler's capacity column;
* SOC0 against the voltage;
* the scatter of the multi-rate straight-line fit;
* R0+R1+R2 against R_dc.

---

## 10. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| "Could not find Current and Voltage columns" | Header names too different. Add your names to the `findCol` patterns in `loadBatteryCsv.m`. |
| Current sign looks wrong | Check the sign note in the top bar. With no State column the sign comes from dV/dt. |
| AH stays empty | No CC-CV charge followed by a full discharge to cut-off. Type the datasheet capacity into the AH box and press Extract again: SOC, R0 and the RC pairs can then be calculated. |
| R1/tau1 empty | No charge / discharge starts after a rest ≥ 10 min with its first sample ≤ 1 s after the switch, at ≤ 2C. |
| R2 / R3 says *not resolved* | The steps cannot carry that many pairs: the fit leaves the extra pair empty. Choose fewer RC pairs. |
| OCV empty | The multi-rate fit and the long rests do not cover SOC 0..1. The OCV window's note says which part is missing. Use the datasheet OCV curve. |
| OCV empty in the 25 °C file only | Fixed: the multi-rate wait comes from the steps at SOC 1, not from the rests (§7.6 step 1). If it still happens, the OCV window names the discharge rate that never settled. |
| OCV note says "no multi-rate fit" | Fewer than 2 different CC discharge rates start from a full CC-CV charge, so there is no OCV from the data. Use the datasheet OCV curve. |
| `batt_ambient` not saved | The file has no chamber temperature column. Use a Constant block with the chamber temperature (K). |
| Thermal mass empty | No `Temp 1` / chamber column, or the cell heats by less than 0.5 K. Enter mass × specific heat. |
| Save warns about a length mismatch | You changed the SOC breakpoints after extracting. Press Extract again. |

---

## 11. Next steps (not in this version)

* More temperatures: combine several files (each already gives its test temperature + 25 °C) into one SOC × T table set.
* Separate charge / discharge R0 (Current directionality = Yes).
* Save / load a parameter set (.mat) from the Modeling tab.
* Optional automatic build of a test-bench Simulink model.

---

## 12. References

Each source was opened and checked in November 2026. **(free)** means readable without a subscription. For each one: what it is, and what this tool takes from it. The same list, with clickable links, is at the bottom of every **How?** window (`src/batterySources.m`).

**The block and MathWorks' own workflows**

* **[MW-TB]** MathWorks, *Battery (Table-Based)*, Simscape Battery block reference. <https://www.mathworks.com/help/simscape-battery/ref/batterytablebased.html> (free)
  It defines the model these tables go into: V0(SOC,T) lookup, R0(SOC,T), up to five RC pairs (R_k, tau_k), SOC by coulomb counting over the capacity, and a thermal mass heated by the resistive losses. It is the "what goes where" for every box.
* **[Huria12]** T. Huria, M. Ceraolo, J. Gazzarri, R. Jackey, "High fidelity electrical model with thermal dependence for characterization and simulation of high power lithium battery cells", IEEE IEVC 2012, doi:10.1109/IEVC.2012.6183271. [MathWorks PDF](https://jp.mathworks.com/content/dam/mathworks/tag-team/Objects/i/71900-ieee-2012-high-fidelity-lithium-battery-model-with-thermal-effect.pdf) (free)
  The MathWorks paper the Table-Based block is built on: an RC-ladder model with SOC- and temperature-dependent tables, identified from pulse-discharge tests.
* **[Jackey13]** R. Jackey, M. Saginaw, P. Sanghvi, J. Gazzarri, T. Huria, M. Ceraolo, "Battery Model Parameter Estimation Using a Layered Technique: An Example Using a Lithium Iron Phosphate Cell", SAE 2013-01-1547. [MathWorks PDF](https://it.mathworks.com/content/dam/mathworks/tag-team/Objects/s/76117-sae-2013-battery-estimation-layered-technique.pdf) (free)
  It fits large lookup tables in smaller pieces, as this tool does: one quantity at a time, at the SOC points where the data shows it.
* **[MW-Char]** MathWorks, *Characterize Battery Cell for Electric Vehicles* (example). <https://www.mathworks.com/help/simscape-battery/ug/battery-cell-characterization-for-ev.html> (free)
  R0 from the sudden voltage change at a pulse, and R_i / tau_i from fitting the relaxation segments. These are the R0 and RC methods here (§7.4, §7.5).
* **[MW-HPPC]** MathWorks, *Estimate Battery Model Parameters from HPPC Data* (example). <https://www.mathworks.com/help/simscape-battery/ug/estimate-battery-model-parameters-from-hppc-data.html> (free)
  MathWorks' HPPC workflow fits the relaxation after each pulse by default (§7.5).
* **[MW-Conv]** MathWorks, *Convective Heat Transfer*, Simscape block reference. <https://www.mathworks.com/help/simscape/ref/convectiveheattransfer.html> (free)
  Q = k·A·(T_A − T_B). With Area = 1 m² the coefficient is h·A directly, which is why `batt_hA` goes in that way.
* **[MW-CTS]** MathWorks, *Controlled Temperature Source*, Simscape block reference. <https://www.mathworks.com/help/simscape/ref/controlledtemperaturesource.html> (free)
  Sets a temperature from a physical signal. It is driven with `batt_ambient`, the chamber temperature (§5).

**Test methods**

* **[INL15]** J. P. Christopherson, *Battery Test Manual for Electric Vehicles, Rev. 3*, Idaho National Laboratory, INL/EXT-15-34184, 2015. <https://inldigitallibrary.inl.gov/sites/STI/STI/6492291.pdf> (free)
  * §3.2, static capacity test: a constant-current discharge from fully charged to the minimum voltage, after a rest (§7.2).
  * §4.4.2: resistance = ΔV/ΔI across a pulse edge (eq. 4) (§7.4), and OCV from the rest points (§7.6, the two ends).
* **[Barai19]** A. Barai, K. Uddin, M. Dubarry et al., "A comparison of methodologies for the non-invasive characterisation of commercial Li-ion cells", *Progress in Energy and Combustion Science* 72 (2019), doi:10.1016/j.pecs.2019.01.001. <https://www.osti.gov/pages/servlets/purl/1530390> (free)
  A review of the whole field:
  * §2: capacity tests, and capacity depending on the C-rate (§7.2);
  * §3: pseudo-OCV from slow cycling, with the charge/discharge average as the recommended compromise (§7.6);
  * §5: the instantaneous step is ohmic, and isolating it needs very fast sampling, so 1 s data also catches a little charge transfer (§7.4).
* **[Lin14]** X. Lin, H. Perez, S. Mohan, J. Siegel, A. Stefanopoulou, Y. Ding, M. Castanier, "A lumped-parameter electro-thermal model for cylindrical batteries", *J. Power Sources* 257 (2014) 1–11, doi:10.1016/j.jpowsour.2014.01.097. [Author PDF](https://public.websites.umich.edu/~annastef/papers_battery/Xinfan_JPS.pdf) (free)
  The closest single paper to this tool:
  * SOC by coulomb counting between the end of the CV charge and the end of discharge;
  * OCV as the average of a slow charge and discharge;
  * R_s from the voltage jump, and RC pairs from least-squares fits of the relaxation (1, 2 and 3 pairs compared);
  * a lumped thermal model with Q = I·(V_T − V_OCV), identified from measured current, surface and ambient temperature.
* **[Chang13]** W.-Y. Chang, "The State of Charge Estimating Methods for Battery: A Review", *ISRN Applied Mathematics* 2013, 953792, doi:[10.1155/2013/953792](https://doi.org/10.1155/2013/953792) (free)
  Coulomb counting and its error sources: a known starting point and an accurate capacity are needed (§7.3).
* **[Petzl13]** M. Petzl, M. A. Danzer, "Advancements in OCV Measurement and Analysis for Lithium-Ion Batteries", *IEEE Trans. Energy Conversion* 28(3), 2013, doi:[10.1109/TEC.2013.2259490](https://doi.org/10.1109/TEC.2013.2259490) (paywalled)
  Low-current OCV curves still carry overpotential; the true OCV is the zero-current value. This is the reason for extrapolating to i = 0 (§7.6).
* **[Yao18]** Q. Yao, D. Lu, G. Lei, "A Simple Internal Resistance Estimation Method Based on Open Circuit Voltage Test under Different Temperature Conditions", IEEE PEAC 2018, doi:10.1109/PEAC.2018.8590350. [Accepted manuscript](https://opus.lib.uts.edu.au/bitstream/10453/132782/5/A%20Simple%20Internal%20Resistance%20Estimation%20Method%20Based%20on%20Open%20Circuit%20am.pdf) (free)
  Discharges at several rates follow U = U_ocv(SOC) − I·R(SOC), so R comes from the voltage difference between the rates. This is the slope half of the multi-rate fit (§7.6).
* **[Bussios24]** M. Bussios, A. Goldar, E. Garone, M. Kinnaert, "Fast Determination of OCV Curve for Lithium-ion Batteries", European Control Conference 2024, doi:[10.23919/ECC64448.2024.10591299](https://doi.org/10.23919/ECC64448.2024.10591299) (paywalled; checked from the abstract)
  Pseudo-OCV curves at several C-rates (C/50 … C/5), extrapolated to zero current. They use a statistical fit; this tool uses a straight line in I, the block's own equation (§7.6).
* **[Schweiger10]** H.-G. Schweiger et al., "Comparison of Several Methods for Determining the Internal Resistance of Lithium Ion Cells", *Sensors* 10(6) (2010) 5604–5625, doi:10.3390/s100605604. <https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3247723/> (free)
  The current-step method compared with AC, EIS and energy-loss methods (§7.4).
* **[Hu12]** X. Hu, S. Li, H. Peng, "A comparative study of equivalent circuit models for Li-ion batteries", *J. Power Sources* 198 (2012) 359–367, doi:[10.1016/j.jpowsour.2011.10.013](https://doi.org/10.1016/j.jpowsour.2011.10.013) (paywalled)
  Twelve equivalent-circuit structures compared: how many RC pairs are worth having (the Charge dynamics drop-down).

**Heat**

* **[Bernardi85]** D. Bernardi, E. Pawlikowski, J. Newman, "A General Energy Balance for Battery Systems", *J. Electrochem. Soc.* 132(1) (1985) 5–12, doi:[10.1149/1.2113792](https://doi.org/10.1149/1.2113792) (paywalled)
  The energy balance behind every battery thermal model. Its irreversible heat, I·(V − OCV), is the heat source in §7.7.
* **[Forgez10]** C. Forgez, D. V. Do, G. Friedrich, M. Morcrette, C. Delacourt, "Thermal modeling of a cylindrical LiFePO4/graphite lithium-ion battery", *J. Power Sources* 195(9) (2010) 2961–2968, doi:[10.1016/j.jpowsour.2009.10.105](https://doi.org/10.1016/j.jpowsour.2009.10.105) (paywalled)
  A lumped thermal model whose heat capacity and heat-transfer coefficient are identified from measured temperatures, as in §7.7.
* **[Maleki99]** H. Maleki, S. Al Hallaj, J. R. Selman, R. B. Dinwiddie, H. Wang, "Thermal properties of lithium-ion battery and components", *J. Electrochem. Soc.* 146(3) (1999), doi:10.1149/1.1391704. <https://www.osti.gov/biblio/345380> (free record)
  The measured specific heat of an 18650 cell is about 0.96–1.04 J/(g·K). Use it to sanity-check `batt_thermal_mass` against cell mass × cp.
* **[Incropera]** F. Incropera et al., *Fundamentals of Heat and Mass Transfer*, 6th ed., Wiley 2007, Table 1.1. [Course handout](https://pages.mtu.edu/~fmorriso/cm3120/typical_values_heat_transfer_coefficient.pdf) (free)
  Typical convection coefficients: free convection in gases 2–25 W/(m²·K), forced 25–250. A sanity check for h = `batt_hA` / cell area.

Also useful, but not checked online: G. Plett, *Battery Management Systems, Vol. I: Battery Modeling*, Artech House 2015 (ISBN 9781630810238). It is the standard textbook for equivalent-circuit models, OCV tests and coulomb counting.

---

## 13. The presentation and the video

* [`Modeling_Tab_Presentation.pptx`](Modeling_Tab_Presentation.pptx): 57 slides, all text in Century Gothic. Every chart is a MATLAB figure inserted as a picture you can copy, move or resize. The arrows and labels on the charts are separate PowerPoint shapes (grouped per callout) that fade in on click, so they can be edited too. Slides use fade / push transitions. The speaker notes hold the full talk.
* [`Modeling_Tab_Presentation.mp4`](Modeling_Tab_Presentation.mp4): the same deck presented, about an hour, with a natural-sounding voice-over (Kokoro, an open-source neural text-to-speech model run locally). The callouts appear as the talk reaches them.

What it covers, in the order the extraction runs: the model and what a test can show; the CSV and the chamber schedule (charges at 25 °C, discharges at T) with the ±3 K window; phases, FULL and EMPTY (knee check); AH and the rate table; SOC, SOC0 and its voltage check; R0 at the current steps; the RC pairs from the rests (branch currents from the real history, how the fit is solved); the multi-rate fit (settle wait, the 25 °C OCV problem, the straight line per SOC, charge side and hysteresis, the two ends); how the tables are built (M / I / E / S); and the thermal side: the heat source, the m·cp / h·A fit, two checks you can do by hand (the first minute of the fast discharge gives m·cp; every chamber step gives τ_th = m·cp / h·A), the Simulink wiring of the battery thermal port and the Convective Heat Transfer block, and what to use when the thermal boxes are empty.

Every chart and number comes from a run of `extractCellParameters` on synthetic 10 °C and 25 °C files that follow the real profile and chamber schedule (~70 h, 0.1 / 0.2 / 0.5 / 1 / 5C). Because the synthetic cell's values are known, the deck also shows how close each result is.
