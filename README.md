# agency-level-fatal-OIS

## 11.20.2025 Update

One of our [VIPR Lab](https://www.viprlab.org/) students, [Ash Bruha](https://www.viprlab.org/author/ash-bruha/), has been hard at work digging up more historical data. She found fOIS data for **Seattle PD** for 1980 through mid-2001 in [this report by SPD](https://s3-us-west-2.amazonaws.com/docs.puppycidedb.com/seattlepd/UseofForce2000.PDF), and for **Denver PD** for 1996-2006 in this [independent monitor's report](https://s3-us-west-2.amazonaws.com/docs.puppycidedb.com/denverpd/OIM/Annual+Reports/2006_Annual+Report.pdf). 

## 1.4.2025 Update

I've added the `wapo_historical_merge` folder, which includes `ori_codes.csv` and `merge_script.R`. This will merge the data I've collected with WAPO's [Fatal Force](https://github.com/washingtonpost/data-police-shootings) data, and reshape into agency-year format (i.e., where each agency has a row for every year from 1970 to the present year). Read more about it in this [blog post](https://jnix.netlify.app/post/post27-historical-ois-update/).

At the time of this update, the merged dataset will include at least some years of data for **~3200 agencies** (albeit mostly from 2015 to present).

## Background

I'm building a database of fatal officer-involved shootings at the agency-year level, going back in time as far as possible. [This recent article in *The Lancet*](https://t.co/zDLTHrysAv) suggests police are killing more people today than they did in the 1980s, but [I remain skeptical](https://twitter.com/jnixy/status/1635677916762886149). Thus, I'm trying to compile annual counts of people shot and killed by on-duty officers for as many agencies as I can. 

...So far, I've got at least a few years of data for **417** agencies.

## Methods and Sources

I started with this excellent book: 

- William A. Geller & Michael S. Scott (1992). *Deadly Force: What We Know.* Police Executive Research Forum. 

It contains yearly counts of fatal and nonfatal police shootings for the following agencies, for the following periods:

| Agency          	| Years Included 	|
|-----------------	|:--------------:	|
| Chicago         	|     1974-91    	|
| Dallas          	|     1970-91    	|
| Philadelphia    	|     1986-91    	|
| NYPD            	|     1970-91    	|
| LAPD            	|     1980-91    	|
| Houston         	|     1980-91    	|
| Atlanta         	|     1980-91    	|
| St. Louis       	|     1984-91    	|
| San Diego       	|     1980-91    	|
| Indianapolis    	|     1970-91    	|
| Kansas City, MO 	|     1972-91    	|

I decided, for now at least, to focus on fatal shootings, since they're more reliably reported. 

From there, I gathered more recent data from the sources below. I started with the largest 100 or so agencies, but added others, regardless of size, as I came across them. Next up is to draw a random sample of smaller agencies from WAPO (see below) and see if I can dig up older data for them as well. 

| Source                                                                                                                                                                                                              	| Years Included 	| Coverage                                                           	|
|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------	|:--------------:	|--------------------------------------------------------------------	|
| [Washington Post](https://github.com/washingtonpost/data-police-shootings)                                                                                                                                          	|    2015-2024   	| Nationwide                                                         	|
| [Tampa Bay Times](https://projects.tampabay.com/projects/2017/investigations/florida-police-shootings/database/)                                                                                                    	|    2009-2014   	| Florida                                                            	|
| [Honolulu Civil Beat](https://cbmultimedia.pythonanywhere.com/)                                                                                                                                                     	|    2010-2022   	| Hawaii                                                             	|
| [Salt Lake Tribune](http://local.sltrib.com/charts/shootings/policeshootings.html)                                                                                                                                  	|    2005-2014   	| Utah                                                               	|
| [Maine Attorney General's Office](https://www.pressherald.com/interactive/maine-police-deadly-force-lethal-database/)                                                                                               	|    1990-2012   	| Maine                                                              	|
| [Atlanta Journal-Constitution](https://investigations.ajc.com/overtheline/database/)                                                                                                                                	|    2010-2020   	| Georgia                                                            	|
| [Star Tribune](https://www.startribune.com/every-police-involved-death-in-minnesota-since-2000/502088871/)                                                                                                          	|    2000-2022   	| Minnesota                                                          	|
| [Vice News](https://news.vice.com/en_us/article/a3jjpa/nonfatal-police-shootings-data)                                                                                                                              	|    2010-2016   	| 50 largest local police departments                                	|
| *The Texas Tribune's* ["Unholstered" Data](https://apps.texastribune.org/unholstered/)                                                                                                                              	|    2010-2015   	| 36 largest cities in Texas                                         	|
| [Binder, Scharf, & Galvin (1983)](https://nij.ojp.gov/library/publications/use-deadly-force-police-officers-final-report)                                                                                           	|    1976-1979   	| Detroit, Honolulu, Newark, Oakland, San Diego, San Jose, St. Louis 	|
| This *Washington Post* [story from 1998](https://www.washingtonpost.com/wp-srv/local/longterm/dcpolice/deadlyforce/police1page1.htm)                                                                                	|    1989-1997   	| DC Metro PD                                                        	|
| [NYPD](https://www.nyc.gov/site/nypd/stats/reports-analysis/use-of-force.page)                                                                                                                                        |    1971-2022    | NYPD                                                                |
| [San Francisco PD](https://www.sanfranciscopolice.org/sites/default/files/2022-02/SFPDOISInvestigationsSheet20220215.pdf)                                                                                           	|    2000-2022   	| San Francisco PD                                                   	|
| [Houston PD](https://www.houstontx.gov/police/ois/)                                                                                                                                                                 	|    2005-2022   	| Houston PD                                                         	|
| [Springfield (MO) PD](https://www.springfieldmo.gov/3755/Officer-Involved-Shootings)                                                                                                                                	|    2008-2022   	| Springfield (MO) PD                                                	|
| [Austin's open data portal](https://data.austintexas.gov/Public-Safety/Officer-Involved-Shooting-2000-2014/63p6-iegi)                                                                                               	|    2000-2014   	| Austin PD                                                          	|
| [Dallas' open data portal](https://www.dallasopendata.com/Public-Safety/Dallas-Police-Officer-Involved-Shootings/4gmt-jyx2)                                                                                         	|    2003-2022   	| Dallas PD                                                          	|
| [Cincinnati's open data portal](https://data.cincinnati-oh.gov/Safety/PDI-Police-Data-Initiative-Officer-Involved-Shooti/r6q4-muts)                                                                                 	|    1996-2019   	| Cincinnati PD                                                      	|
| [Vermont open data portal](https://data.vermont.gov/Public-Safety/Vermont-State-Police-Officer-Involved-Shootings-19/du86-kfnp?category=Public-Safety&view_name=Vermont-State-Police-Officer-Involved-Shootings-19) 	|    1977-2022   	| Vermont State Police                                               	|
| [This report on LVMPD](https://cops.usdoj.gov/RIC/Publications/cops-p273-pub.pdf) by the COPS Office                                                                                                                	|    1990-2011   	| Las Vegas Metro PD                                                 	|
| This [ACLU report](https://www.aclusocal.org/sites/default/files/aclu_socal_report_on_apd_use_of_force_nov_2017.pdf) from November 2017                                                                             	|    2003-2016   	| Anaheim PD                                                         	|
| This [article by Mike White](https://cvpcs.asu.edu/sites/default/files/content/projects/ER%20-%20external%20DF.pdf)                                                                                                 	|    1970-1992   	| Philadelphia PD                                                    	|
| This [article by David Klinger](https://journals.sagepub.com/doi/10.1177/1088767911430861)                                                                                                                          	|    1996-2008   	| LAPD, LASD                                                         	|
| This [report](https://scholarworks.alaska.edu/handle/11122/11933) on police shootings in Alaska                                                                                                                       |    2010-2020    | Anchorage PD                                                        |

\* Note that the pre-2015 numbers for Cincinnati include fatal and nonfatal shootings (animal shootings are excluded). Unfortunately, I can't yet determine how many were fatal or nonfatal. Same goes for LVMPD. 

## Three final thoughts (for now)

1. **Any mistakes are mine**. I did my best to make sure the data permit apples to apples comparisons. That is, each number in the data *should* represent a person fatally shot by an on-duty police officer. In some cases, however, I'm  not 100% confident an agency's data are subject-level, as opposed to incident-level (e.g., Austin from 2000 to 2007). Like I said, this is a work in progress.

2. **I'm still digging, and will continue to update this dataset as I go**. For example, I found broken links to datasets purporting to include data for Oklahoma, Idaho, and San Diego County. I also found a report on police shootings in Alaska that unfortunately didn't enable me to break out fatal police shootings. I sent emails to the various authors, with some luck (e.g., Alaska). Here's hoping I can track those other databases down eventually.

3. I'm aware that [Mapping Police Violence](https://mappingpoliceviolence.us/) goes back to 2013 and [Fatal Encounters](https://fatalencounters.org/) goes back to 2000. I started with WAPO as that's the dataset I've worked with the most in the past, and am therefore most comfortable using. Eventually, I'll sort through Fatal Encounters and fill in more of the empty cells in my dataset, but just eyeballing the data, I'm almost certain everything before ~2013 is less reliable.