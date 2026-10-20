# BatteryBuilder: BQ76952 BMS + Molicel P45B pack simulation (KiCad / ngspice)

This KiCad project recreates the TI BQ76952 reference design (datasheet Fig. 16-1/16-2) for a **16S1P Molicel INR-21700-P45B pack**. It also adds SPICE models for the BMS, the cells and a programmable load, so the whole thing runs in KiCad's built-in simulator (ngspice).

> **Quick start:** open `BMS_Testing.kicad_sch` → **Inspect → Simulator** → press **Run** on the TRAN tab. About 3–4 minutes later you get a full discharge / fault / charge / balance cycle, already plotted.

---

## Contents

1. [Files](#1-files)
2. [The default simulation](#2-the-default-simulation)
3. [Reading the plots](#3-reading-the-plots)
4. [BMS protections explained](#4-bms-protections-explained)
5. [Overcurrent tiers](#5-overcurrent-tiers)
6. [Cell balancing and coulomb counting](#6-cell-balancing-and-coulomb-counting)
7. [Changing the load profile](#7-changing-the-load-profile)
8. [Cell model and cell-to-cell deviation](#8-cell-model-and-cell-to-cell-deviation)
9. [BMS model parameters](#9-bms-model-parameters)
10. [Schematic changes made for simulation](#10-schematic-changes-made-for-simulation)
11. [Limitations](#11-limitations)
12. [Troubleshooting](#12-troubleshooting)
13. [Before building real hardware](#13-before-building-real-hardware)
14. [Sources](#14-sources)

---

## 1. Files

| File | What it is |
|---|---|
| `BMS_Testing.kicad_sch` | Schematic: the BQ76952 reference circuit, 16 × P45B, power FETs, load, probes |
| `BMS_Testing.wbk` | Simulator workbook. TRAN tab (`.tran 100m 1700`) with 15 traces and 12 measurements preloaded; OP tab |
| `bq76952.lib` | Behavioral model of the TI BQ76952, subckt `BQ76952`, 48 pins in datasheet order. Defaults are tuned for the P45B |
| `molicel_p45b.lib` | P45B cell: `MOLICEL_P45B` (2-pin) and `MOLICEL_P45B_SOC` (3-pin). Includes a thermal model |
| `sim_loads.lib` | `LOAD_PROFILE` (programmable load/charger), `LOAD_CC` (legacy), `SIM_PROBE` (test-point probe) |
| `csd19532q5b.lib` | Generic Level-1 NMOS + body diode standing in for the CSD19532Q5B power FETs |
| `default_cycle_preview.png` | What the TRAN plot should look like after a run |
| `sim_result*.png` | Earlier verification plots (45 A discharge, load profiles) |

All models are plain SPICE plus B-sources, with no XSPICE code models. They were tested in ngspice-42 in the `psa`, `ltpsa` and `kipsa` compatibility modes (KiCad 7–10).

---

## 2. The default simulation

At t = 0 the pack is at **~30 % SOC**. Each cell has a slightly different capacity, resistance, starting SOC, self-discharge and cooling (see section 8). Source **I2** plays a PWL "demo cycle" into the load **I1** (`LOAD_PROFILE`, `MODE=0 PROF=2 INTERLOCK=1`). Positive current means discharge; negative means charge.

| Time | Load | What happens |
|---|---|---|
| 0.28 s | – | BQ76952 wakes and turns on the CHG and DSG FETs |
| 0.5–300 s | Repeating 15 A (10 s) / 45 A (8 s) / 5 A (12 s) | Voltage sag, SOC falls, cells spread apart, cells heat up |
| **≈ 223 s** | – | Weakest cell < 2.53 V for 1 s → **CUV** → DSG FET off. The load interlock stops discharging |
| 300–320 s | 0 A | Rest; the cells recover and CUV clears |
| 320 s | −13 A charge | Charging starts |
| **600 s** | +110 A for 100 ms | **OCD1** trips (100 A, 20 ms) → DSG off. Recovers about 3 s later |
| **900 s** | +220 A for 2 ms | **SCD** trips within about 90 µs. Recovers after 5 s |
| **≈ 1030 s** | – | **Cell balancing** starts on the highest cells (up to 3 at a time) |
| **≈ 1430 s** | – | Highest cell reaches 4.25 V → **COV** → CHG FET off. The charger interlock stops |
| 1430–1700 s | 0 A | Rest; the cells relax and cool |

Results from the verification run (KiCad-equivalent netlist in ngspice-42):

| Quantity | True (cells) | BMS coulomb count |
|---|---|---|
| Ah discharged | 1.1765 | 1.1761 |
| Ah charged | 4.0061 | 4.0060 |
| SOC at end | 92.6 % | 92.9 % |
| Lowest SOC | 3.3 % | – |
| Peak cell temperature | 43.5 °C | – |
| Highest cell voltage | 4.250 V | – |

---

## 3. Reading the plots

Every probe is a **global net**. In the schematic each one is a `SIM_PROBE` test point with a global label; these are sim-only (not in the BOM, not on the PCB). Click the wire in the simulator to plot any of them. Values are scaled so they share one 0–100 axis.

| Net | Meaning | Scale |
|---|---|---|
| `PACK_V` | Pack voltage at the load | 1 V = 1 V |
| `LOAD_I` / `LOAD_P` / `LOAD_WH` | Load current / power / energy (+ = out of the pack) | 1 V = 1 A / 1 W / 1 Wh |
| `PACK_SOC` | **True** average SOC from the cell models | 1 V = 1 % |
| `BMS_SOC` | SOC as the **BMS** counts it (`BMS_SOC0 + Ah/BMS_CAP_AH`) | 1 V = 1 % |
| `PACK_AH_OUT` / `BMS_AH_OUT` | Net Ah out of the pack: true / BMS | 1 V = 1 Ah |
| `AH_DIS_X10` / `BMS_AH_DIS_X10` | Total Ah discharged (counts up only): true / BMS | ×10 (12 = 1.2 Ah) |
| `AH_CHG_X10` / `BMS_AH_CHG_X10` | Total Ah charged (counts up only): true / BMS | ×10 |
| `CELL_MAX_X10` / `CELL_MIN_X10` | Highest / lowest cell voltage the BMS sees | ×10 (42.5 = 4.25 V) |
| `CELL_SPREAD_MV` | Highest minus lowest cell | mV |
| `PACK_TEMP` | Average cell temperature | 1 V = 1 °C |
| `BMS_FAULT` | Highest active fault (see below) | code |
| `BMS_FETS` | FET driver state | code |
| `BMS_BALANCING` | Number of cells being balanced | count |
| `BMS_DSG_OK` / `BMS_CHG_OK` | 1 = discharge / charge allowed (used by the load interlock) | 0/1 |

**`BMS_FAULT` codes** (the highest active one is shown):

| Code | Fault |
|---|---|
| 0 | none |
| 10 | COV, cell overvoltage |
| 20 | CUV, cell undervoltage |
| 30 | OCC, overcurrent in charge |
| 40 | OCD1/2/3, overcurrent in discharge |
| 50 | SCD, short circuit in discharge |
| 60 | OTC/OTD/UTC/UTD, temperature |
| 70 | PF, permanent fail |

**`BMS_FETS`:** 15 = both FETs on, 10 = CHG only, 5 = DSG only, 0 = both off.

**Only the signals in the `.save` line are stored**, which keeps the run fast and the file small. To probe any other net (cell voltages, gate drive, FET currents), delete or edit the `.save` text on the schematic, or tick **Save all voltages/currents** in the simulation command settings. Expect a slower run and a much larger result.

Internal model nodes can also be plotted by name, e.g. `v(xu1.f_ocd1)`, `v(xu1.vmin)`, `v(xbt7.x1.soc)`, `v(xbt7.x1.tc)`. The pattern is lower-case, `x` + reference designator.

---

## 4. BMS protections explained

Each protection compares a measurement against a threshold. It must stay past the threshold for a delay before it trips, and it recovers on its own rules. The values below are the **P45B defaults** in `bq76952.lib`; the TI example values are in brackets.

| Protection | Watches | Trip (P45B default) | Action | Recovery |
|---|---|---|---|---|
| **COV**: cell overvoltage | Any cell too high | 4.25 V for 0.5 s [TI 4.30 V] | CHG FET off; discharge still allowed | Cell < 4.15 V (OV_HYS 0.1 V) for 3 s |
| **CUV**: cell undervoltage | Any cell too low | 2.53 V for 1 s [TI 2.50 V / 20 ms] | DSG FET off; charge still allowed | Cell > 2.63 V for 3 s |
| **OCC**: overcurrent in charge | Charge current | 14 A for 160 ms [TI 8 A] | CHG FET off | Charge current stops (I < −0.2 A, i.e. discharging or idle, per model convention) for 3 s |
| **OCD1/2/3**: overcurrent in discharge | Discharge current | See section 5 | DSG FET off | > 0.2 A charge current for 3 s (`OCD_REC`; see note) |
| **SCD**: short circuit | Discharge current | 150 A for 90 µs [TI 80 A / 50 µs] | DSG FET off (hardware-fast) | After 5 s (`SCD_REC`) |
| **OTC / OTD**: over-temperature | Thermistors TS1–3 | 55 °C charge / 60 °C discharge | CHG / DSG off | 5 °C hysteresis |
| **UTC / UTD**: under-temperature | Thermistors TS1–3 | 0 °C charge / −20 °C discharge | CHG / DSG off | 5 °C hysteresis |
| **SOV / SUV**: safety OV/UV (PF) | Cell far out of range | disabled (0) | Permanent fail; optionally blows a fuse | none (latched) |

Why the P45B values differ from TI's example:

- **COV 4.25 V:** the P45B's maximum charge voltage is 4.20 V. 4.25 V is the nearest 50.6 mV step above it, so normal CC/CV charging never trips it, but a runaway charger does.
- **CUV 2.53 V with a 1 s delay:** the P45B cut-off is 2.50 V. The 1 s delay rides through the deep voltage sag of 45 A pulses at low SOC, so CUV trips on real depletion, not on a 10 ms dip.
- **OCC 14 A:** the P45B's maximum charge current is 13.5 A (3C).

> **Note on OCD recovery.** The model follows the TI default: OCD clears only after it sees **charge current** (> 0.2 A) for `REC_TIME`. With a discharge-only load and no charger, an OCD trip **stays latched**. Set `OCD_REC=-1` on U1 to make OCD recover on time alone. The real chip also has latch counters (OCDL/SCDL) and load-removal recovery, which this model does not include. Decide what you want and program the real chip to match in BQStudio.

---

## 5. Overcurrent tiers

Real loads have short, high peaks: motor inrush, capacitor precharge, hard acceleration. A single low limit trips on every normal peak. A single high limit lets a moderate overload run until something overheats. The BQ76952 therefore uses a stack of limits: **the higher the current, the less time it is allowed**.

| Tier | Limit (1 mΩ sense) | Delay | Use |
|---|---|---|---|
| **SCD** | 150 A (150 mV) | ~90 µs | Dead shorts: crushed cable, failed motor controller, tool across the terminals. Must act before the FETs, fuse and wiring are damaged |
| **OCD1** | 100 A (100 mV) | 20 ms | Severe overloads: stalled motor, jammed drivetrain |
| **OCD2** | 70 A (70 mV) | 200 ms | Heavy loads lasting longer than a normal acceleration burst |
| **OCD3** | 50 A (50 mV) | 2 s | Sustained overload above the cell's 45 A continuous rating |
| **OCC** | 14 A (14 mV) | 160 ms | Charger or regen pushing more current than the cell can accept |

```
Current
 150 A ┤█ SCD (µs)
 100 A ┤███ OCD1 (20 ms)
  70 A ┤████████ OCD2 (200 ms)
  50 A ┤████████████████ OCD3 (2 s)
  45 A ┤──────────────────────────── allowed continuously (P45B rating)
       └──────────────────────────── time
```

Together the tiers form a current-versus-time boundary that should follow the heating limits of the **weakest part** in the current path (cells, FETs, fuse, wire, connectors).

**How the real chip implements them:**

- **SCD, OCD1, OCD2 and OCC** are hardware comparators on the sense-resistor voltage. Thresholds are set in mV; with the 1 mΩ sense resistor, 1 mV = 1 A. They are fast and independent of firmware.
- **OCD3** is firmware-based and uses the coulomb counter's current readings. It is slower but more accurate, which suits the multi-second tier.
- Silicon step sizes: OCD thresholds in 2 mV steps (4–200 mV), OCD2 delay up to about 425 ms, SCD threshold from a fixed list (10–500 mV), SCD delay in 15 µs steps.

In the model all tiers are threshold + delay blocks with the parameters above.

---

## 6. Cell balancing and coulomb counting

**Balancing** (enabled here with `CB_EN=1 CB_START=20m CB_STOP=10m`):

- A cell is selected when it is more than `CB_START` (20 mV) above the lowest cell and above `CB_MINV` (3.9 V), and the pack is not discharging above `CB_IDSG` (50 mA).
- Selected cells are bled through the internal 28 Ω FET plus the 2 × 20 Ω input resistors.
- Balancing stops when the cell is within `CB_STOP` (10 mV) of the lowest cell.
- Like the real part, balancing pauses periodically to measure the cells unloaded. In the model this is a 50 ms pause every `CB_TS` = 5 s.
- Adjacent cells are not balanced at the same time; the model alternates odd and even cells.
- Bleed current is only about 60 mA. On a 4.5 Ah cell, balancing corrects mV-level differences over hours, not minutes. In the 1700 s demo you see it start and pick cells, not finish.

**Coulomb counting:**

- The BMS integrates the sense-resistor voltage, the same way the chip's CC1/CC2 do.
- `BMS_SOC` = `BMS_SOC0` + counted Ah ÷ `BMS_CAP_AH`. This is what a host MCU would compute from the chip's passed-charge register.
- `BMS_SOC0` is set to 30 on U1 to match the cells. If you change the cells' `SOC0`, change `BMS_SOC0` too, or the BMS estimate starts wrong (just as a real BMS would).
- Use `CC_GAIN` (e.g. 1.01 = +1 % gain error) and `CC_OFFSET` (V) to see how calibration error makes the BMS estimate drift from the true SOC.
- The small difference between `PACK_SOC` and `BMS_SOC` in the demo comes from self-discharge (`ISD`) and the fact that the true value is a cell average. The BMS can't see either.

---

## 7. Changing the load profile

The load **I1** is a `LOAD_PROFILE` from `sim_loads.lib`. Edit it in **Symbol Properties → Simulation Model → Parameters**.

**`MODE`** sets what the set-point means. Positive means discharge.

| MODE | Behavior |
|---|---|
| 0 | Constant current, A (negative = charge) |
| 1 | Constant power, W (negative = regen) |
| 2 | Constant resistance, Ω |
| 3 | Constant voltage, V. A CC/CV charger when `VAL` is above the pack voltage and `ILIM` is the charge current |

**`PROF`** sets how the set-point changes over time.

| PROF | Behavior |
|---|---|
| 0 | DC: `VAL` |
| 1 | PULSE: `VAL` base, `VAL2` pulse, `TD TR TF PW PER` like a SPICE PULSE |
| 2 | EXT: `K × V(LOAD_CTRL)`, driven by source I2. **This is the default** |
| 3 | SINE: `VAL` offset, `VAL2` amplitude, `FREQ`, `TD` |

**Other parameters:**

| Parameter | Meaning |
|---|---|
| `TON`, `TRISE` | Enable time and ramp |
| `VMIN` | CC/CP sink folds back below this voltage (V) |
| `VMAX` | Charge/regen fades out near this voltage (V) |
| `ILIM` | Current limit both ways (A) |
| `CIN`, `RESR` | Load input capacitance and its series resistance |
| `INTERLOCK=1` | Load obeys `BMS_DSG_OK` / `BMS_CHG_OK`: it stops when the BMS faults and stays off until its set-point returns to 0. With `INTERLOCK=0` the load keeps pushing, so after a CUV/OCD trip you'll see the BMS hiccup (recover → re-trip) |

**Examples:**

| Parameters | Load |
|---|---|
| `MODE=0 PROF=0 VAL=45 TON=0.4` | 45 A DC |
| `MODE=0 PROF=1 VAL=10 VAL2=60 TD=1 PW=5 PER=20` | 10 A base, 60 A for 5 s every 20 s |
| `MODE=1 PROF=0 VAL=2500` | 2.5 kW constant power |
| `MODE=2 PROF=0 VAL=1.5` | 1.5 Ω resistor |
| `MODE=3 PROF=0 VAL=67.2 ILIM=10` | 67.2 V / 10 A CC/CV charger |
| `MODE=1 PROF=2` + a PWL in I2 | Drive cycle in watts |

**Using your own drive cycle:** edit **I2** → Simulation Model → keep type PWL and paste `time value time value …` pairs. Or switch I2 to any other KiCad source type. I2 drives the `LOAD_CTRL` net into 1 Ω, so 1 A from I2 equals a set-point of 1. Change the `.tran` stop time on the TRAN tab to match your profile length.

**Runtime:** long, high-rate profiles take longer to compute. The demo uses `.tran 100m 1700`, where 100 ms is the maximum step. For short events (fault timing, FET switching), use a shorter window and smaller step, e.g. `.tran 10u 0.5`.

---

## 8. Cell model and cell-to-cell deviation

```
POS ─ R0(T,SOC) ─ [R1(T,SOC) ∥ C1] ─ OCV(SOC) ─ NEG
```

The cell is a first-order (one RC pair) Thevenin model:

- SOC is coulomb-counted from the terminal current.
- Resistance follows SOC (a knee below about 20 % SOC) and temperature (Arrhenius).
- A lumped thermal node handles self-heating: `CTH·dT/dt = I²R − (T−TAMB)/RTH`.

| Param | Default | Meaning / source |
|---|---|---|
| `QAH` | 4.5 | Capacity, Ah (Molicel typ.; 4.3 min) |
| `RS` | 7 mΩ | R0 at 25 °C / 50 % SOC (spec: 7 mΩ AC impedance) |
| `RP` | 8 mΩ | R1; RS + RP gives about 14–15 mΩ 10 s DCIR (spec: 15 mΩ DC impedance) |
| `TAU1` | 5 s | R1·C1 time constant (estimate) |
| `SOC0` | 1 | Initial SOC, 0–1 |
| `NP` | 1 | Cells in parallel (capacity ×NP, resistance ÷NP) |
| `KOCV` | 0 | OCV offset, V |
| `KR` | 1 | Resistance multiplier |
| `ISD` | 0 | Self-discharge current, A |
| `THERMAL` | 1 | Self-heating on/off |
| `T0`, `TAMB` | 25, 25 | Starting and ambient temperature, °C |
| `CTH`, `RTH` | 75 J/K, 10 K/W | Heat capacity and cell-to-ambient thermal resistance |
| `EA` | 2260 K | Resistance temperature coefficient (about 0.5× resistance at 55 °C) |

Checks against the datasheet:

- 1C discharge gives about 4.48 Ah.
- 10 s DCIR is about 14.2 mΩ.
- A 45 A continuous discharge delivers about 4.45 Ah and ends near 80 °C, consistent with the 80 °C cut-off condition in Molicel's 45 A rating.

**The deviations used in this schematic** (BT1–BT16 `Sim.Params`):

| Parameter | Spread across the 16 cells | Represents |
|---|---|---|
| `SOC0` | 28.8 – 30.0 % | Pack assembled unbalanced |
| `QAH` | 4.450 – 4.511 Ah | Capacity tolerance (about ±0.7 %) |
| `KR` | 0.946 – 1.024 | Internal resistance spread (about ±4 %) |
| `ISD` | 27 – 174 µA | Self-discharge spread |
| `RTH` | 8.4 – 12.3 K/W | Edge cells cool better than centre cells |

The weakest cell (lowest capacity and SOC, highest resistance) is the one that trips CUV first. The strongest trips COV first; that is what balancing corrects over time. For a different spread, edit any cell's Sim.Params.

> The **OCV curve** and the **R(SOC) shape** are estimates for a high-Ni 21700 cell, because Molicel does not publish them. If you have HPPC or OCV test data (for example from your Simscape/MATLAB pack model), replace the `pwl(...)` tables in `molicel_p45b.lib` and refit `RS`, `RP`, `TAU1`.

---

## 9. BMS model parameters

Set these on **U1 → Simulation Model → Parameters**. The full list, with comments, is in the header of `bq76952.lib`. U1 currently has `REG2_V=5 CB_EN=1 CB_START=20m CB_STOP=10m BMS_SOC0=30`.

Units are SI (V, A, s, °C). **Current thresholds are sense-resistor voltages**, as in the IC. With `RSENSE=1m`, `OCD1_TH=100m` means 100 A.

| Group | Parameters (default) |
|---|---|
| Cells / sense | `CE1..CE16` (1), `RSENSE` (1m) |
| COV / CUV | `OV_TH` 4.25, `OV_DLY` 0.5, `OV_HYS` 0.1 · `UV_TH` 2.53, `UV_DLY` 1, `UV_HYS` 0.1 |
| OCC | `OCC_TH` 14m, `OCC_DLY` 160m, `OCC_REC` −0.2 |
| OCD | `OCD1` 100m/20m · `OCD2` 70m/200m · `OCD3` 50m/2 · `OCD_REC` 0.2 |
| SCD | `SCD_TH` 150m, `SCD_DLY` 90u, `SCD_REC` 5 |
| Recovery | `REC_TIME` 3 |
| Temperature | `TS1_EN/TS2_EN/TS3_EN` (0), `TS_R25` 10k, `TS_BETA` 3435 · OTC 55 / OTD 60 / UTC 0 / UTD −20 °C · `T_HYS` 5 |
| Permanent fail | `SOV_TH` / `SUV_TH` (0 = off), `FUSE_BLOW`, `FUSE_PF_EN` |
| FETs | `FET_EN` 1, `SERIES` 1, `BD_TH` 50m, `VCP` 11, `CFETOFF_MODE` / `DFETOFF_MODE` (0 = ignored) |
| Pre-charge / pre-discharge | `PCHG_EN` 0, `PCHG_START/STOP` 3.0/3.2 · `PDSG_EN` 0, `PDSG_TO`, `PDSG_DELTA` |
| Regulators | `REG0_EN` 1, `REG1_V` 3.3, `REG2_V` 0 (0 = off) |
| Balancing | `CB_EN` 0, `CB_START` 40m, `CB_STOP` 20m, `CB_MINV` 3.9, `CB_IDSG` 50m, `RCB` 28, `CB_TS` 5 |
| Coulomb counter / SOC | `CC_GAIN` 1, `CC_OFFSET` 0, `BMS_SOC0` 100, `BMS_CAP_AH` 4.5 |
| Start-up | `TSTART` 0.28 s (wake → FETs on), `VPOR` 3.5 V |

---

## 10. Schematic changes made for simulation

These were needed to make the reference layout simulate. **Check them before you send the board out.**

| Change | Why |
|---|---|
| The two GND symbols at the pack-minus side were renamed to the net **`BUS-`** | Both were named `0`, which merged PACK− with VSS/BAT− and shorted the 1 mΩ sense resistor. The BMS could not see current |
| Net tie **NT1** (BAT− ↔ VSS) given a 10 µΩ resistor model | Otherwise VSS floats in the sim |
| **D1–D4** pin mapping fixed to `1=K 2=A` | The anode and cathode were swapped |
| **Q2/Q3** mapped to `csd19532q5b.lib` with `1=S 4=G 5=D` | The pin map was wrong, and vendor/VDMOS models with breakdown didn't converge |
| D1 feed wire split and re-routed with the `CD` label | D1 was hanging off the DSG gate net |
| **I1** replaced with `LOAD_PROFILE`; **I2** added as the profile source | An ideal 50 A current source has nowhere to go when the FETs are off, so the solver fails |
| J1–J4, TP1–TP3, D5 marked *exclude from simulation* | No meaningful SPICE model |
| TP12–TP22 + the other probe test points | Sim-only probes; excluded from BOM and board |
| `.options rshunt=1e12 method=gear reltol=1e-3` | Robust convergence for the long run |
| `.save …` text | Stores only the plotted signals |

---

## 11. Limitations

**Not in the BMS model:**

- I²C/SPI/HDQ communication, registers and OTP. All configuration is through parameters; to emulate host control, drive the CFETOFF/DFETOFF pins.
- ADC quantization and accuracy spreads. Use real step values yourself: OV/UV in 50.6 mV steps, OC in 2 mV steps, delays in 3.3 ms steps.
- SLEEP/DEEPSLEEP, open-wire detection, the OCDL/SCDL latches, load-detect recovery, the watchdog and DSG source-follower mode.
- The exact pulsed shape of the DSG turn-off waveform.

**Thermistors:**

- The TS1–TS3 thermistors are not connected in the simulation (`TS*_EN=0`), so **OT/UT protections don't fire** in the demo. The cell temperature is still modeled (`PACK_TEMP`).
- To test OT/UT, put an NTC on a TS pin (or a voltage source standing in for one) and set `TS1_EN=1`. An enabled TS pin with nothing on it reads as very cold and trips UTC/UTD.

**FETs:** the generic FET model is fine for timing and logic. Don't use it for switching losses or SOA.

**Cell model:**

- The cell is first-order, with no hysteresis and no ageing.
- The OCV and R(SOC) curves are estimates.

---

## 12. Troubleshooting

| Problem | Fix |
|---|---|
| KiCad: "unterminated delimited string at line N" when opening the schematic | A text field has a raw line break inside quotes. KiCad strings must use `\n`. Fixed in the current file. If you edit the `.kicad_sch` by hand, keep each string on one line |
| Git shows no changes after files were updated | A discard, pull or branch switch restored the committed version. Commit new files before switching branches or pulling |
| Simulator says a signal doesn't exist / can't probe a net | It isn't in the `.save` list. Add it, or tick *Save all voltages* |
| "Timestep too small" / no convergence | Make sure the load has `CIN` and isn't an ideal source; avoid zero-time steps in PWL lists (use 1 ms edges); try `.tran` with a smaller max step |
| BMS_SOC sits at 100 or doesn't match PACK_SOC | Set `BMS_SOC0` on U1 to the cells' starting SOC (in %) |
| BMS keeps tripping and recovering (hiccup) | That's the real behavior with a load that ignores the BMS. Use `INTERLOCK=1` on the load |
| OCD never clears | It needs charge current to recover (TI default). Set `OCD_REC=-1` for time-based recovery |
| Run is very slow | Shorten `.tran`, raise the max step for long cycles, or set `CB_EN=0` when you don't need balancing |
| Plots look wrong after opening | Close and reopen KiCad so it reloads `BMS_Testing.wbk` |

---

## 13. Before building real hardware

- **The model is not the chip.** Program the real BQ76952 in **BQStudio** with the same thresholds and delays. The model defaults are only a starting point, and the silicon rounds them to its step sizes.
- **Set the overcurrent tiers from your system,** not from the cell alone. Use your motor controller's current profile (peak, burst duration, continuous) and the ratings of the FETs (SOA, RDS(on) heating), fuse, busbars/wire gauge and connectors. The weakest part sets the limits.
- **SCD must be faster than everything else in the path can fail.** Check the FET SOA at your SCD current × SCD delay, and pick the fuse so it does not open before the SCD trips.
- **Connect the thermistors:** at least one on the hottest cell group, plus one on the FETs if you can. The P45B is limited to 60 °C on charge and 80 °C at its 45 A rating, so OT protection matters.
- **For a 16S pack** (67.2 V max), check that the FETs, the TVS (D1/D2) and the pre-regulator NPN are all rated for the full pack voltage plus inductive spikes.
- **Calibrate the coulomb counter** (CC gain/offset) on the real board; the sense resistor tolerance directly sets SOC accuracy.

---

## 14. Sources

- TI **BQ76952** datasheet, SLUSE13B (Rev. B, Nov 2021), and the BQ76952 Technical Reference Manual.
- E-One Moli Energy **INR-21700-P45B** product specification: 4500 mAh typ., 4.20 V / 2.50 V, 45 A continuous, 13.5 A max charge, 7 mΩ AC / 15 mΩ DC impedance.
- Independent P45B bench tests (e.g. Mooch's 21700 tests) for high-rate voltage and temperature behavior.

*This is a behavioral model built from public datasheets. It is not a TI or Molicel model. Use it to check design behavior and protection logic, not for exact timing or accuracy margins.*
