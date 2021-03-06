## [3.0.1+1] - June 22nd, 2021

* Updated with the latest framework.


## [3.0.1] - June 21th, 2021

* Added logging to the image loading.
* Fixed to properly throw an exception when an image fails to download (as the docs already claimed it would).


## [3.0.0+2] - May 9th, 2021

* Dependency updates


## [3.0.0] - March 8th, 2021

* Null Safety


## [2.0.0] - February 21st, 2021

* Updating to latest framework version


## [1.0.11] - February 17th, 2021

* Updated to not repeatedly upload images that have the same hash in the same report.


## [1.0.10+1] - January 17th, 2021

* Updated dependencies.


## [1.0.9] - October 14th, 2020

* Added timestamp to `testWriter`.


## [1.0.8] - September 29th, 2020

* Fix to properly set test suite name when reading tests from Cloud Storage.


## [1.0.7+1] - September 28th, 2020

* Changed format to dedupe test names / suites.


## [1.0.7] - September 28th, 2020

* Minor update to the test store to allow for duplicate test names across test suites.


## [1.0.6] - September 24th, 2020

* Fixed test reports to be properly encoded in UTF8
* Applied GZIP compression to JSON to reduce storage and transfer size
* Updated to latest framework version


## [1.0.5] - September 21st, 2020

* Updated with golden image capabilities


## [1.0.4] - September 19th, 2020

* Updated with test suite capabilities


## [1.0.3] - September 15th, 2020

* Fix for android's int vs long issue


## [1.0.2] - September 14th, 2020

* Externalized the `uploadImages` function so it can be used by other plugins.


## [1.0.1] - September 14th, 2020

* Added logs to `TestReport`


## [1.0.0+1] - September 13th, 2020

* Switched to verified publisher and GH actions


## [1.0.0] - September 13th, 2020

* Initial release
