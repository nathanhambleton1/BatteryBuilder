function [S, use] = batterySources(key)
%BATTERYSOURCES  The references behind each extraction method.
%
%   S = batterySources()        all sources (struct array: tag, cite, url, free)
%   [S, use] = batterySources(key)
%       S    the sources for one parameter key (e.g. 'V0_vec')
%       use  matching cell array: what that source says that this tool uses
%
%   Every URL was opened when this list was written (November 2026). "free"
%   = readable without a subscription. The same list is in README section 9.

A = {
 'MW-TB',     'MathWorks, "Battery (Table-Based)" block reference, Simscape Battery.', ...
              'https://www.mathworks.com/help/simscape-battery/ref/batterytablebased.html', true
 'Huria12',   'T. Huria, M. Ceraolo, J. Gazzarri, R. Jackey, "High fidelity electrical model with thermal dependence for characterization and simulation of high power lithium battery cells", IEEE IEVC 2012, doi:10.1109/IEVC.2012.6183271.', ...
              'https://jp.mathworks.com/content/dam/mathworks/tag-team/Objects/i/71900-ieee-2012-high-fidelity-lithium-battery-model-with-thermal-effect.pdf', true
 'Jackey13',  'R. Jackey et al., "Battery Model Parameter Estimation Using a Layered Technique: An Example Using a Lithium Iron Phosphate Cell", SAE 2013-01-1547.', ...
              'https://it.mathworks.com/content/dam/mathworks/tag-team/Objects/s/76117-sae-2013-battery-estimation-layered-technique.pdf', true
 'MW-Char',   'MathWorks, "Characterize Battery Cell for Electric Vehicles" (example).', ...
              'https://www.mathworks.com/help/simscape-battery/ug/battery-cell-characterization-for-ev.html', true
 'MW-HPPC',   'MathWorks, "Estimate Battery Model Parameters from HPPC Data" (example).', ...
              'https://www.mathworks.com/help/simscape-battery/ug/estimate-battery-model-parameters-from-hppc-data.html', true
 'MW-Conv',   'MathWorks, "Convective Heat Transfer" block reference, Simscape.', ...
              'https://www.mathworks.com/help/simscape/ref/convectiveheattransfer.html', true
 'MW-CTS',    'MathWorks, "Controlled Temperature Source" block reference, Simscape.', ...
              'https://www.mathworks.com/help/simscape/ref/controlledtemperaturesource.html', true
 'INL15',     'J. P. Christopherson, "Battery Test Manual for Electric Vehicles, Rev. 3", Idaho National Laboratory, INL/EXT-15-34184, 2015.', ...
              'https://inldigitallibrary.inl.gov/sites/STI/STI/6492291.pdf', true
 'Barai19',   'A. Barai, K. Uddin, M. Dubarry et al., "A comparison of methodologies for the non-invasive characterisation of commercial Li-ion cells", Progress in Energy and Combustion Science 72 (2019), doi:10.1016/j.pecs.2019.01.001.', ...
              'https://www.osti.gov/pages/servlets/purl/1530390', true
 'Lin14',     'X. Lin, H. Perez, S. Mohan, J. Siegel, A. Stefanopoulou, Y. Ding, M. Castanier, "A lumped-parameter electro-thermal model for cylindrical batteries", J. Power Sources 257 (2014) 1-11, doi:10.1016/j.jpowsour.2014.01.097.', ...
              'https://public.websites.umich.edu/~annastef/papers_battery/Xinfan_JPS.pdf', true
 'Chang13',   'W.-Y. Chang, "The State of Charge Estimating Methods for Battery: A Review", ISRN Applied Mathematics 2013, 953792, doi:10.1155/2013/953792.', ...
              'https://doi.org/10.1155/2013/953792', true
 'Petzl13',   'M. Petzl, M. A. Danzer, "Advancements in OCV Measurement and Analysis for Lithium-Ion Batteries", IEEE Trans. Energy Conversion 28(3), 2013, doi:10.1109/TEC.2013.2259490.', ...
              'https://doi.org/10.1109/TEC.2013.2259490', false
 'Yao18',     'Q. Yao, D. Lu, G. Lei, "A Simple Internal Resistance Estimation Method Based on Open Circuit Voltage Test under Different Temperature Conditions", IEEE PEAC 2018, doi:10.1109/PEAC.2018.8590350.', ...
              'https://opus.lib.uts.edu.au/bitstream/10453/132782/5/A%20Simple%20Internal%20Resistance%20Estimation%20Method%20Based%20on%20Open%20Circuit%20am.pdf', true
 'Bussios24', 'M. Bussios, A. Goldar, E. Garone, M. Kinnaert, "Fast Determination of OCV Curve for Lithium-ion Batteries", European Control Conference 2024, doi:10.23919/ECC64448.2024.10591299.', ...
              'https://doi.org/10.23919/ECC64448.2024.10591299', false
 'Schweiger10','H.-G. Schweiger et al., "Comparison of Several Methods for Determining the Internal Resistance of Lithium Ion Cells", Sensors 10(6) (2010) 5604-5625, doi:10.3390/s100605604.', ...
              'https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3247723/', true
 'Hu12',      'X. Hu, S. Li, H. Peng, "A comparative study of equivalent circuit models for Li-ion batteries", J. Power Sources 198 (2012) 359-367, doi:10.1016/j.jpowsour.2011.10.013.', ...
              'https://doi.org/10.1016/j.jpowsour.2011.10.013', false
 'Bernardi85','D. Bernardi, E. Pawlikowski, J. Newman, "A General Energy Balance for Battery Systems", J. Electrochem. Soc. 132(1) (1985) 5-12, doi:10.1149/1.2113792.', ...
              'https://doi.org/10.1149/1.2113792', false
 'Forgez10',  'C. Forgez, D. V. Do, G. Friedrich, M. Morcrette, C. Delacourt, "Thermal modeling of a cylindrical LiFePO4/graphite lithium-ion battery", J. Power Sources 195(9) (2010) 2961-2968, doi:10.1016/j.jpowsour.2009.10.105.', ...
              'https://doi.org/10.1016/j.jpowsour.2009.10.105', false
 'Incropera', 'F. Incropera et al., Fundamentals of Heat and Mass Transfer, 6th ed., Wiley 2007, Table 1.1 (typical h values; course handout copy).', ...
              'https://pages.mtu.edu/~fmorriso/cm3120/typical_values_heat_transfer_coefficient.pdf', true
 'Maleki99',  'H. Maleki, S. Al Hallaj, J. R. Selman, R. B. Dinwiddie, H. Wang, "Thermal properties of lithium-ion battery and components", J. Electrochem. Soc. 146(3) (1999), doi:10.1149/1.1391704.', ...
              'https://www.osti.gov/biblio/345380', true
};
S = struct('tag', A(:,1), 'cite', A(:,2), 'url', A(:,3), 'free', A(:,4));
use = {};
if nargin < 1, return; end

% ---- what each source supports, per parameter ---------------------------
switch key
    case 'SOC_vec'
        U = {'MW-TB', 'The block takes every table on these SOC breakpoints and interpolates linearly between them.'};
    case 'AH'
        U = {'INL15',   'Static capacity test (sect. 3.2): constant-current discharge from fully charged down to the minimum voltage, after a rest.'
             'Barai19', 'Sect. 2: the standards'' capacity tests; the measured capacity depends on the C-rate (impedance and heating) - so the slowest discharge is used and the others are shown as rate capability.'
             'Lin14',   'Capacity = the charge between 100 % (end of the CV charge) and 0 % (end of discharge at the cut-off).'};
    case 'SOC0'
        U = {'MW-TB',   'The block''s SOC is coulomb counting: charge in or out divided by the capacity.'
             'Chang13', 'Coulomb counting ("book-keeping") and its error sources: needs a known start point and an accurate capacity.'
             'Lin14',   '100 % SOC defined at the end of the CV charge, 0 % at the end of discharge.'};
    case 'V0_vec'
        U = {'Barai19',  'Sect. 3: pseudo-OCV from low-rate cycling; averaging the charge and discharge curves is "the best compromise" between test time and accuracy (the charge/discharge averaging used here).'
             'Lin14',    'OCV taken as the average of a slow (C/20) CC-CV charge and CC discharge, because of hysteresis.'
             'Petzl13',  'Low-current curves still carry a voltage drop; the true OCV needs zero current - which is what the multi-rate extrapolation reaches.'
             'Yao18',    'Discharges at several rates obey U = U_ocv(SOC) - I*R(SOC); R follows from the voltage difference between rates (the slope half of the multi-rate fit).'
             'Bussios24','Pseudo-OCV curves at several C-rates (C/50..C/5) extrapolated to zero current (they use a statistical fit; here a straight line in I, the block''s own equation).'
             'INL15',    'Sect. 4.4.2: OCV from the rest points, interpolated in between (used here only at the ends).'
             'MW-TB',    'V = V0(SOC) - I*R0 - sum of the RC voltages (with + = discharge): the equation that is solved for V0.'};
    case 'V_range'
        U = {'MW-TB', 'Terminal voltage operating range: the block warns when a simulation leaves it.'};
    case 'R0_vec'
        U = {'INL15',      'Sect. 4.4.2, eq. 4: resistance = change in voltage / change in current across a current step.'
             'MW-Char',    'R0 from the sudden voltage change at a pulse.'
             'Barai19',    'Sect. 5: the instantaneous step is ohmic; sampling faster than ~100 Hz is needed to isolate it, so a 1 s sample includes a little of the fast charge-transfer response.'
             'Schweiger10','Current-step resistance compared with AC / EIS / energy-loss methods; the current-step and energy-loss methods agree.'
             'Yao18',      'DC resistance from discharges at several rates (the R_dc used to fill the SOC range between the steps).'};
    case {'R1_vec','R2_vec','R3_vec','tau1_vec','tau2_vec','tau3_vec'}
        U = {'Lin14',   'The voltage response to a current step fitted by least squares with a sum of exponentials; 1, 2 and 3 RC pairs compared.'
             'MW-Char', 'Ri, taui fitted to the voltage segments around each current pulse.'
             'MW-HPPC', 'MathWorks'' own HPPC workflow: RC pairs fitted to the voltage around each pulse.'
             'Hu12',    'Comparison of 12 equivalent-circuit structures for Li-ion cells (how many RC pairs are worth it).'
             'Huria12', 'The RC-ladder model with SOC/temperature tables that the Table-Based block implements.'};
    case {'thermal_mass','hA'}
        U = {'Bernardi85','The general energy balance; the irreversible heat is I*(V - OCV) - the heat source used here.'
             'Lin14',     'Lumped electro-thermal model; Q = I*(V_T - V_OCV), the same as I^2*R over R0 + RC pairs; thermal parameters identified from current, surface temperature and ambient.'
             'Forgez10',  'Lumped thermal model of a cylindrical cell; heat capacity and heat-transfer coefficient identified from temperature measurements.'
             'Maleki99',  'Measured specific heat of an 18650 Li-ion cell: about 0.96-1.04 J/(g K) - a sanity check for m*cp = mass * cp.'
             'Incropera', 'Free convection in air: h = 2-25 W/(m^2 K); forced: 25-250 - a sanity check for h = hA / area.'
             'MW-Conv',   'Q = k*A*(T_A - T_B): with A = 1 m^2 the coefficient k is h*A directly.'
             'MW-CTS',    'Drives the ambient side with batt_ambient (chamber temperature).'};
    case 'T0'
        U = {'MW-TB', 'Initial cell temperature (K) of the thermal mass.'};
    otherwise
        U = cell(0,2);
end
[~, ia] = ismember(U(:,1), {S.tag});
S = S(ia);
use = U(:,2);
end
