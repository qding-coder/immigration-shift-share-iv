/*===========================================================================
  Immigration Shift-Share (Bartik) IV
  Author: [Your Name]
  Date:   May 2026

  Description:
    Constructs an immigration shift-share instrumental variable across
    U.S. commuting zones (1970-2010) following Kim, Merritt & Peri (2024).
    Single IPUMS extract (usa_00002.dat) covers all five Census decades.

  Required packages (auto-installed below):
    ivreg2, estout, reghdfe, ivreghdfe

  Directory structure:
    project/
      data/raw/       <- usa_00002.dat, usa_00002.do, all crosswalk .dta files
      data/clean/     <- intermediate datasets saved here
      code/           <- THIS FILE
      output/figures/
      output/tables/
      docs/
===========================================================================*/

clear all
set more off
set varabbrev off
cap log close

*--- !! 唯一需要修改的地方：项目根目录的绝对路径 -------------------------
global project "C:\Users\dingq\Desktop\immigration_project"
* -------------------------------------------------------------------------

global raw   "$project\data\raw"
global clean "$project\data\clean"
global fig   "$project\output\figures"
global tab   "$project\output\tables"

log using "$project\output\bartik_iv_main.log", replace text

*--- Install packages if needed ----------------------------------------------
foreach pkg in ivreg2 estout reghdfe ivreghdfe {
    cap which `pkg'
    if _rc ssc install `pkg', replace
}

/*===========================================================================
  STEP 0: Load raw IPUMS data and save as .dta
  
  usa_00005: 1970 1980 1990 2010 (fixed-width .dat)
  usa_00006_2000.dta: 2000 only (.dta format, separate download)
===========================================================================*/
di "===== STEP 0: Reading raw IPUMS data ====="

* Load main extract (1970, 1980, 1990, 2010)
cd "$raw"
quietly do "usa_00005.do"
cd "$project\code"

* Drop the bad 2000 obs from main extract
drop if year == 2000
save "$clean/ipums_raw_main.dta", replace

* Load 2000 separately
use "$raw\usa_00006_2000.dta", clear

* Rename bpl->bpld if needed (2000 extract may only have bpl)
cap confirm variable bpld
if _rc rename bpl bpld

* Rename educ->educd if needed
cap confirm variable educd
if _rc rename educ educd

save "$clean/ipums_raw_2000.dta", replace

* Combine all years
use "$clean/ipums_raw_main.dta", clear
append using "$clean/ipums_raw_2000.dta"
tab year   // should show 1970 1980 1990 2000 2010
save "$clean/ipums_raw_all.dta", replace

/*===========================================================================
  STEP 1: Process each decade → CZ x origin intermediates
  Output per decade: cz_o_YEAR.dta
  Unit: commuting zone x origin-country group
  Variables: czone, kmp_ctry, year, pop (adj. pop sum), wage (mean hourly)
===========================================================================*/
di "===== STEP 1: Decade processing ====="

foreach yr in 1970 1980 1990 2000 2010 {

    di "--- Processing `yr' ---"
    use "$clean/ipums_raw_all.dta", clear
    keep if year == `yr'

    *-- (a) Sample restrictions
    drop if statefip == 2 | statefip == 15   // AK, HI
    drop if inlist(gq, 0, 3, 4)             // group quarters
    drop if age < 16

    *-- (b) Geography merge → commuting zones
    if `yr' == 1970 {
        rename cntygp97 cty_grp70
        joinby cty_grp70 using "$raw/cw_ctygrp1970_czone_corr.dta"
        gen aperwt = afact * perwt
    }
    else if `yr' == 1980 {
        gen ctygrp1980 = 1000 * statefip + cntygp98
        joinby ctygrp1980 using "$raw/cw_ctygrp1980_czone_corr.dta"
        gen aperwt = afactor * perwt
    }
    else if `yr' == 1990 {
        gen puma1990 = 10000 * statefip + puma
        joinby puma1990 using "$raw/cw_puma1990_czone.dta"
        gen aperwt = afactor * perwt
    }
    else {
        // 2000 and 2010 both use the 2000 PUMA crosswalk
        gen puma2000 = 10000 * statefip + puma
        joinby puma2000 using "$raw/cw_puma2000_czone.dta"
        gen aperwt = afactor * perwt
    }

    *-- (c) Origin classification
    merge m:1 bpld using "$raw/cw_bpld_kmp.dta", keep(match) nogen
    drop if kmp_ctry == 82   // drop "other/unspecified"

    *-- (d) Hourly wage construction
    // Weeks worked
    if `yr' >= 1990 {
        gen weeks = wkswork1
        replace weeks = . if weeks == 0
    }
    else {
        // Intervalled wkswork2 → midpoints
        gen weeks = .
        replace weeks = 7    if wkswork2 == 1   // 1-13
        replace weeks = 20   if wkswork2 == 2   // 14-26
        replace weeks = 33   if wkswork2 == 3   // 27-39
        replace weeks = 43.5 if wkswork2 == 4   // 40-47
        replace weeks = 48.5 if wkswork2 == 5   // 48-49
        replace weeks = 51   if wkswork2 == 6   // 50-52
    }

    // Usual hours per week (continuous in this extract for all years)
    gen hours = uhrswork
    replace hours = . if uhrswork == 0 | uhrswork >= 99

    // Annual wage income
    replace incwage = . if incwage >= 999998
    replace incwage = . if incwage <= 0

    // Hourly wage; drop top 1%
    gen wage = incwage / (weeks * hours)
    replace wage = . if missing(weeks) | missing(hours)
    replace wage = . if wage <= 0
    qui sum wage [aw=aperwt], detail
    replace wage = . if wage > r(p99)

    *-- (e) Collapse to CZ x origin
    collapse (rawsum) pop  = aperwt ///
             (mean)   wage [pw=aperwt], ///
             by(czone kmp_ctry year)

    label var pop  "Adjusted population"
    label var wage "Mean hourly wage"

    save "$clean/cz_o_`yr'.dta", replace
    di "  cz_o_`yr'.dta: N=`=_N'"
}

/*===========================================================================
  STEP 2: National immigration flows (shifts)
  Output: origin_shifts.dta
  Unit: one row per origin (~82 immigrant origins)
  Variables: natl_imm1970-2010, shift_1980-2010
===========================================================================*/
di "===== STEP 2: National shifts ====="

use "$clean/cz_o_1970.dta", clear
foreach yr in 1980 1990 2000 2010 {
    append using "$clean/cz_o_`yr'.dta"
}

drop if kmp_ctry == 78   // US-born excluded from immigrant flows

collapse (rawsum) natl_imm = pop, by(kmp_ctry year)
reshape wide natl_imm, i(kmp_ctry) j(year)

gen shift_1980 = natl_imm1980 - natl_imm1970
gen shift_1990 = natl_imm1990 - natl_imm1980
gen shift_2000 = natl_imm2000 - natl_imm1990
gen shift_2010 = natl_imm2010 - natl_imm2000

save "$clean/origin_shifts.dta", replace
di "origin_shifts.dta: N=`=_N' (expect 82)"

/*===========================================================================
  STEP 3: CZ-level actual statistics
  Output: cz_actual_panel.dta
  Unit: CZ x year (722 x 5 = 3,610 obs)
  Variables: czone, year, pop (total), imm (immigrants), wage (mean)
===========================================================================*/
di "===== STEP 3: CZ actual panel ====="

// 3a. Total population (all origins)
use "$clean/cz_o_1970.dta", clear
foreach yr in 1980 1990 2000 2010 {
    append using "$clean/cz_o_`yr'.dta"
}
collapse (rawsum) pop, by(czone year)
save "$clean/temp_cz_pop.dta", replace

// 3b. Immigrant count and wage
use "$clean/cz_o_1970.dta", clear
foreach yr in 1980 1990 2000 2010 {
    append using "$clean/cz_o_`yr'.dta"
}
keep if kmp_ctry != 78
collapse (rawsum) imm = pop ///
         (mean)   wage [pw=pop], ///
         by(czone year)

// 3c. Merge
merge 1:1 czone year using "$clean/temp_cz_pop.dta", nogen
sort czone year

label var pop  "Total CZ population"
label var imm  "Immigrant population"
label var wage "Mean hourly wage (immigrants)"

save "$clean/cz_actual_panel.dta", replace
di "cz_actual_panel.dta: N=`=_N' (expect 3610)"

/*===========================================================================
  STEP 4: Shift-share instrument
  Output: cz_predicted_panel.dta
  Unit: CZ x decade (722 x 4 = 2,888 obs)
  Variables: czone, year, imm_shift, pop1970
===========================================================================*/
di "===== STEP 4: Shift-share instrument ====="

use "$clean/cz_o_1970.dta", clear

// 1970 total CZ population (ALL origins, including US-born)
bysort czone: egen pop1970 = total(pop)

// Keep immigrants for shares
drop if kmp_ctry == 78

// Merge shifts
merge m:1 kmp_ctry using "$clean/origin_shifts.dta", keep(match) nogen

// Location shares: fraction of origin o's US immigrants in CZ c
gen share = pop / natl_imm1970

// Predicted inflows
foreach yr in 1980 1990 2000 2010 {
    gen predicted`yr' = share * shift_`yr'
}

// Sum across origins and normalize
collapse (sum)   predicted1980 predicted1990 predicted2000 predicted2010 ///
         (first) pop1970, ///
         by(czone)

foreach yr in 1980 1990 2000 2010 {
    replace predicted`yr' = predicted`yr' / pop1970
}

// Reshape to long
reshape long predicted, i(czone pop1970) j(year)
rename predicted imm_shift

label var imm_shift "Shift-share IV (normalized)"
label var pop1970   "1970 CZ total population"

tabstat imm_shift, by(year) stats(mean sd)   // quick sanity check

save "$clean/cz_predicted_panel.dta", replace
di "cz_predicted_panel.dta: N=`=_N' (expect 2888)"

/*===========================================================================
  STEP 5: Assemble analytic dataset
  Output: cz_analytic_panel.dta
  Unit: CZ x decade (2,888 obs; years 1980 1990 2000 2010)
  Variables: czone, year, imm_shift, imm_actch, wage, wage_ch
===========================================================================*/
di "===== STEP 5: Analytic dataset ====="

use "$clean/cz_actual_panel.dta", clear
merge 1:1 czone year using "$clean/cz_predicted_panel.dta", nogen

// pop1970: fill from 1970 obs to all years
bysort czone: egen pop1970 = max(cond(year == 1970, pop, .))

// Lags (1970 serves as lag for 1980)
sort czone year
bysort czone (year): gen imm_lag  = imm[_n-1]
bysort czone (year): gen wage_lag = wage[_n-1]

// Actual immigration change (normalized)
gen imm_actch = (imm - imm_lag) / pop1970
label var imm_actch "Actual immigration change / pop1970"

// Wage change
gen wage_ch = wage - wage_lag
label var wage_ch "Decade change in mean hourly wage"

// Drop 1970 baseline
drop if year == 1970
drop imm_lag wage_lag

sort czone year

di "--- Checkpoint: means by decade ---"
tabstat imm_shift imm_actch wage wage_ch, by(year) stats(mean sd)

save "$clean/cz_analytic_panel.dta", replace
di "cz_analytic_panel.dta: N=`=_N' (expect 2888)"

/*===========================================================================
  STEP 6: Estimation and Visualization
===========================================================================*/
di "===== STEP 6: Results ====="

use "$clean/cz_analytic_panel.dta", clear

*--- Summary table -----------------------------------------------------------
tabstat imm_shift imm_actch wage wage_ch, ///
    by(year) stats(mean sd min max) columns(statistics) longstub

*--- First-stage scatterplots ------------------------------------------------
local colors navy maroon forest_green dkorange
local i 1
foreach yr in 1980 1990 2000 2010 {
    local col: word `i' of `colors'
    twoway ///
        (scatter imm_actch imm_shift if year==`yr', ///
             msize(vtiny) mcolor(`col'%40)) ///
        (lfit imm_actch imm_shift if year==`yr', ///
             lcolor(`col') lwidth(medthick)), ///
        title("`yr'") xtitle("Shift-Share IV") ytitle("Δ Immigration") ///
        legend(off) saving("$fig/fs`yr'.gph", replace)
    local ++i
}
graph combine "$fig/fs1980.gph" "$fig/fs1990.gph" ///
              "$fig/fs2000.gph" "$fig/fs2010.gph", ///
    rows(2) title("First Stage by Decade") ///
    note("Shift-share instrument vs. actual immigration change (normalized by 1970 CZ population).")
graph export "$fig/first_stage_scatter.png", replace width(1400)

*--- First-stage regressions -------------------------------------------------
eststo clear

eststo fs1: reg imm_actch imm_shift i.year, vce(cluster czone)
estadd local cz_fe "No"
estadd local yr_fe "Yes"

eststo fs2: reghdfe imm_actch imm_shift, absorb(czone year) vce(cluster czone)
estadd local cz_fe "Yes"
estadd local yr_fe "Yes"

esttab fs1 fs2, b(3) se(3) star(* 0.1 ** 0.05 *** 0.01) ///
    scalars("cz_fe CZ FE" "yr_fe Year FE") ///
    keep(imm_shift) mtitles("(1) Year FE" "(2) Year+CZ FE") ///
    title("First Stage: IV → Actual Immigration Change")

esttab fs1 fs2 using "$tab/first_stage.tex", ///
    b(3) se(3) star(* 0.1 ** 0.05 *** 0.01) ///
    scalars("cz_fe CZ FE" "yr_fe Year FE") ///
    keep(imm_shift) mtitles("(1) Year FE" "(2) Year+CZ FE") ///
    title("First Stage: IV → Actual Immigration Change") replace

*--- Wage regressions: OLS and IV --------------------------------------------
eststo clear

// (1) OLS, year FE
eststo ols1: reg wage_ch imm_actch i.year, vce(cluster czone)
estadd local cz_fe "No"
estadd local yr_fe "Yes"
estadd scalar fstat = .

// (2) IV, year FE
eststo iv1: ivreg2 wage_ch (imm_actch = imm_shift) i.year, cluster(czone) first
estadd local cz_fe "No"
estadd local yr_fe "Yes"
estadd scalar fstat = e(widstat)

// (3) OLS, year + CZ FE
eststo ols2: reghdfe wage_ch imm_actch, absorb(czone year) vce(cluster czone)
estadd local cz_fe "Yes"
estadd local yr_fe "Yes"
estadd scalar fstat = .

// (4) IV, year + CZ FE
cap ivreghdfe wage_ch (imm_actch = imm_shift), absorb(czone year) cluster(czone) first
if _rc == 0 {
    eststo iv2: ivreghdfe wage_ch (imm_actch = imm_shift), ///
        absorb(czone year) cluster(czone) first
    estadd scalar fstat = e(widstat): iv2
}
else {
    // Fallback: partial out FEs manually (FWL theorem)
    qui reghdfe wage_ch,   absorb(czone year) resid(wage_r)
    qui reghdfe imm_actch, absorb(czone year) resid(imm_r)
    qui reghdfe imm_shift, absorb(czone year) resid(iv_r)
    eststo iv2: ivreg2 wage_r (imm_r = iv_r), cluster(czone) first
    estadd scalar fstat = e(widstat): iv2
}
estadd local cz_fe "Yes": iv2
estadd local yr_fe "Yes": iv2

esttab ols1 iv1 ols2 iv2, ///
    b(3) se(3) star(* 0.1 ** 0.05 *** 0.01) ///
    scalars("cz_fe CZ FE" "yr_fe Year FE" "fstat First-stage F") ///
    sfmt(%9.0g %9.0g %9.2f) ///
    keep(imm_actch) ///
    mtitles("(1) OLS" "(2) IV" "(3) OLS+FE" "(4) IV+FE") ///
    title("Effect of Immigration on Wages") ///
    note("Clustered SEs at CZ level. *** p<0.01 ** p<0.05 * p<0.1")

esttab ols1 iv1 ols2 iv2 using "$tab/wage_regressions.tex", ///
    b(3) se(3) star(* 0.1 ** 0.05 *** 0.01) ///
    scalars("cz_fe CZ FE" "yr_fe Year FE" "fstat First-stage F") ///
    sfmt(%9.0g %9.0g %9.2f) ///
    keep(imm_actch) ///
    mtitles("(1) OLS" "(2) IV" "(3) OLS+FE" "(4) IV+FE") ///
    title("Effect of Immigration on Wages") ///
    note("Clustered SEs at CZ level. *** p<0.01 ** p<0.05 * p<0.1") replace

di "===== ALL STEPS COMPLETE ====="
log close
