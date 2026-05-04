* Fix 2010 processing - wkswork2 instead of wkswork1
use "$clean\ipums_raw_all.dta", clear
keep if year == 2010

drop if statefip == 2 | statefip == 15
drop if inlist(gq, 0, 3, 4)
drop if age < 16

gen puma2000 = 10000 * statefip + puma
joinby puma2000 using "$raw\cw_puma2000_czone.dta"
gen aperwt = afactor * perwt

merge m:1 bpld using "$raw\cw_bpld_kmp.dta", keep(match) nogen
drop if kmp_ctry == 82

* 2010 ACS uses wkswork2 (intervalled)
gen weeks = .
replace weeks = 7    if wkswork2 == 1
replace weeks = 20   if wkswork2 == 2
replace weeks = 33   if wkswork2 == 3
replace weeks = 43.5 if wkswork2 == 4
replace weeks = 48.5 if wkswork2 == 5
replace weeks = 51   if wkswork2 == 6

gen hours = uhrswork
replace hours = . if uhrswork == 0 | uhrswork >= 99

replace incwage = . if incwage >= 999998
replace incwage = . if incwage <= 0

gen wage = incwage / (weeks * hours)
replace wage = . if missing(weeks) | missing(hours)
replace wage = . if wage <= 0
qui sum wage [aw=aperwt], detail
replace wage = . if wage > r(p99)

collapse (rawsum) pop = aperwt (mean) wage [pw=aperwt], by(czone kmp_ctry year)

save "$clean\cz_o_2010.dta", replace
di "Done! N=`=_N'"
sum wage
