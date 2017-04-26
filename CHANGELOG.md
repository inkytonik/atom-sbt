## v0.10.0
- Update busy signal for each separate command run by a continuous command
- Fixed bad example of prompt pattern regular expression (missing escape)

## v0.9.0
* New prompt pattern setting is used when waiting for the right moment to run a command. You will almost certainly need to set this if you use a non-standard sbt prompt.
* Move to Linter package V2 (issue 16)
* Support more than one sbt project panel in a single Atom window (issue 10)
* User per-project linters instead one linter per window (issue 10)
* Properly capture last command when an interactive command comes from history (issue 14)
* More robust resumption of interactive commands after interrupting a continuous command
* Wait to run commands when restarting the terminal (issue 3)
* Do limited processing of ANSI escape sequences when capturing interactive commands for history (issue 1)
* Add support for Busy Signal to show when sbt commands are running

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
