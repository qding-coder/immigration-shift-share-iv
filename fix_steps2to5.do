* Re-run Steps 2-5 with corrected 2010 data
* Run from code/ folder after fix_2010.do has been run

global project "C:\Users\dingq\Desktop\immigration_project"
global raw   "$project\data\raw"
global clean "$project\data\clean"
global fig   "$project\output\figures"
global tab   "$project\output\tables"

/*==== STEP 2: National shifts ====*/
di "===== STEP 2 ====="

use "$clean\cz_o_1970.dta", clear
foreach yr in 1980 1990 2000 2010 {
    append using "$clean\cz_o_`yr'.dta"
}

drop if kmp_ctry == 78
collapse (rawsum) natl_imm = pop, by(kmp_ctry year)
reshape wide natl_imm, i(kmp_ctry) j(year)

gen shift_1980 = natl_imm1980 - natl_imm1970
gen shift_1990 = natl_imm1990 - natl_imm1980
gen shift_2000 = natl_imm2000 - natl_imm1990
gen shift_2010 = natl_imm2010 - natl_imm2000

save "$clean\origin_shifts.dta", replace
di "origin_shifts.dta: N=`=_N' (expect 82)"

/*==== STEP 3: CZ actual panel ====*/
di "===== STEP 3 ====="

* Total population
use "$clean\cz_o_1970.dta", clear
foreach yr in 1980 1990 2000 2010 {
    append using "$clean\cz_o_`yr'.dta"
}
collapse (rawsum) pop, by(czone year)
save "$clean\temp_cz_pop.dta", replace

* Immigrants only
use "$clean\cz_o_1970.dta", clear
foreach yr in 1980 1990 2000 2010 {
    append using "$clean\cz_o_`yr'.dta"
}
keep if kmp_ctry != 78
collapse (rawsum) imm = pop (mean) wage [pw=pop], by(czone year)

merge 1:1 czone year using "$clean\temp_cz_pop.dta", nogen
sort czone year
save "$clean\cz_actual_panel.dta", replace
di "cz_actual_panel.dta: N=`=_N' (expect 3610)"

/*==== STEP 4: Shift-share instrument ====*/
di "===== STEP 4 ====="

use "$clean\cz_o_1970.dta", clear
bysort czone: egen pop1970 = total(pop)
drop if kmp_ctry == 78
merge m:1 kmp_ctry using "$clean\origin_shifts.dta", keep(match) nogen

gen share = pop / natl_imm1970
foreach yr in 1980 1990 2000 2010 {
    gen predicted`yr' = share * shift_`yr'
}

collapse (sum) predicted1980 predicted1990 predicted2000 predicted2010 ///
         (first) pop1970, by(czone)

foreach yr in 1980 1990 2000 2010 {
    replace predicted`yr' = predicted`yr' / pop1970
}

reshape long predicted, i(czone pop1970) j(year)
rename predicted imm_shift

tabstat imm_shift, by(year) stats(mean sd)
save "$clean\cz_predicted_panel.dta", replace
di "cz_predicted_panel.dta: N=`=_N' (expect 2888)"

/*==== STEP 5: Analytic dataset ====*/
di "===== STEP 5 ====="

use "$clean\cz_actual_panel.dta", clear
merge 1:1 czone year using "$clean\cz_predicted_panel.dta", nogen

cap drop pop1970
bysort czone: egen pop1970 = max(cond(year == 1970, pop, .))

sort czone year
bysort czone (year): gen imm_lag  = imm[_n-1]
bysort czone (year): gen wage_lag = wage[_n-1]

gen imm_actch = (imm - imm_lag) / pop1970
label var imm_actch "Actual immigration change / pop1970"

gen wage_ch = wage - wage_lag
label var wage_ch "Decade change in mean hourly wage"

drop if year == 1970
drop imm_lag wage_lag
sort czone year

di "--- Checkpoint ---"
tabstat imm_shift imm_actch wage wage_ch, by(year) stats(mean sd)

save "$clean\cz_analytic_panel.dta", replace
di "cz_analytic_panel.dta: N=`=_N' (expect 2888)"
di "===== STEPS 2-5 COMPLETE ====="
