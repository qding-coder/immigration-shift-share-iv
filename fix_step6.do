* Step 6: Estimation and Visualization

global project "C:\Users\dingq\Desktop\immigration_project"
global raw   "$project\data\raw"
global clean "$project\data\clean"
global fig   "$project\output\figures"
global tab   "$project\output\tables"

* Install packages if needed
foreach pkg in ivreg2 estout reghdfe ivreghdfe {
    cap which `pkg'
    if _rc ssc install `pkg', replace
}

use "$clean\cz_analytic_panel.dta", clear

* Drop 1980 for wage regressions (no wage_ch due to missing 1970 wage)
* But keep for immigration regressions

*--- Summary table -----------------------------------------------------------
di "--- Summary statistics ---"
tabstat imm_shift imm_actch wage wage_ch, ///
    by(year) stats(mean sd min max) columns(statistics) longstub

*--- First-stage scatterplots ------------------------------------------------
foreach yr in 1980 1990 2000 2010 {
    twoway ///
        (scatter imm_actch imm_shift if year==`yr', msize(vtiny) mcolor(navy%40)) ///
        (lfit imm_actch imm_shift if year==`yr', lcolor(navy) lwidth(medthick)), ///
        title("`yr'") xtitle("Shift-Share IV") ytitle("Actual Imm Change") ///
        legend(off) saving("$fig\fs`yr'.gph", replace)
}

graph combine "$fig\fs1980.gph" "$fig\fs1990.gph" ///
              "$fig\fs2000.gph" "$fig\fs2010.gph", ///
    rows(2) title("First Stage: Shift-Share IV vs. Actual Immigration Change") ///
    note("Each panel shows one decade. Fitted line from OLS.")
graph export "$fig\first_stage_scatter.png", replace width(1400)
di "Figure saved!"

*--- First-stage regressions -------------------------------------------------
di "--- First-stage regressions ---"
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
    title("First Stage: IV to Actual Immigration Change")

esttab fs1 fs2 using "$tab\first_stage.tex", ///
    b(3) se(3) star(* 0.1 ** 0.05 *** 0.01) ///
    scalars("cz_fe CZ FE" "yr_fe Year FE") ///
    keep(imm_shift) mtitles("(1) Year FE" "(2) Year+CZ FE") ///
    title("First Stage: IV to Actual Immigration Change") replace

*--- Wage regressions --------------------------------------------------------
di "--- Wage regressions ---"
* Drop obs with missing wage_ch (i.e. 1980)
preserve
drop if missing(wage_ch) | missing(imm_actch) | missing(imm_shift)

eststo clear

* OLS
eststo ols1: reg wage_ch imm_actch i.year, vce(cluster czone)
estadd local cz_fe "No"
estadd local yr_fe "Yes"
estadd scalar fstat = .

* IV
eststo iv1: ivreg2 wage_ch (imm_actch = imm_shift) i.year, cluster(czone) first
estadd local cz_fe "No"
estadd local yr_fe "Yes"
estadd scalar fstat = e(widstat)

* OLS + CZ FE
eststo ols2: reghdfe wage_ch imm_actch, absorb(czone year) vce(cluster czone)
estadd local cz_fe "Yes"
estadd local yr_fe "Yes"
estadd scalar fstat = .

* IV + CZ FE (FWL method)
qui reghdfe wage_ch,   absorb(czone year) resid(wage_r)
qui reghdfe imm_actch, absorb(czone year) resid(imm_r)
qui reghdfe imm_shift, absorb(czone year) resid(iv_r)
eststo iv2: ivreg2 wage_r (imm_r = iv_r), cluster(czone) first
estadd local cz_fe "Yes"
estadd local yr_fe "Yes"
estadd scalar fstat = e(widstat)

esttab ols1 iv1 ols2 iv2, ///
    b(3) se(3) star(* 0.1 ** 0.05 *** 0.01) ///
    scalars("cz_fe CZ FE" "yr_fe Year FE" "fstat First-stage F") ///
    sfmt(%9.0g %9.0g %9.2f) ///
    keep(imm_actch imm_r) ///
    mtitles("(1) OLS" "(2) IV" "(3) OLS+FE" "(4) IV+FE") ///
    title("Effect of Immigration on Wages") ///
    note("Clustered SEs at CZ level. *** p<0.01 ** p<0.05 * p<0.1")

esttab ols1 iv1 ols2 iv2 using "$tab\wage_regressions.tex", ///
    b(3) se(3) star(* 0.1 ** 0.05 *** 0.01) ///
    scalars("cz_fe CZ FE" "yr_fe Year FE" "fstat First-stage F") ///
    sfmt(%9.0g %9.0g %9.2f) ///
    keep(imm_actch imm_r) ///
    mtitles("(1) OLS" "(2) IV" "(3) OLS+FE" "(4) IV+FE") ///
    title("Effect of Immigration on Wages") ///
    note("Clustered SEs at CZ level. *** p<0.01 ** p<0.05 * p<0.1") replace

restore
di "===== STEP 6 COMPLETE ====="
