## v0.9.0
* New prompt pattern setting used when waiting for the right moment to run a command
* More robust resumption of interactive commands after interrupting a continuous command
* Wait to run commands when restarting the terminal (issue 3)

## v0.8.0
* Move from terminal-plus to platformio-ide-terminal

## v0.7.0
* Add project path to terminal title
* Fix bug in recognition of more than one test failure in a single test suite
* Clear messages after a pause during continuous execution of a command
* Add setting to control whether to show the sbt terminal automatically
* More robust solution for when we can't run sbt script

## v0.6.0
* Clear messages after entering an interactive command

## v0.5.0
* Change ScalaTest support to use suite path, document it

## v0.4.0
* Added error dialog when we can't run the sbt script (Unix).

## v0.3.0
* Much better handling of package dependencies.
* Added option to specify the filename of the sbt script.

## v0.2.0
* A failed attempt to improve handling of package dependencies.

## v0.1.0
* Initial release
