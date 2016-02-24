An Atom interface to the Scala Build Tool (sbt).

This package provides support for interactive use of sbt within the Atom editor.
It uses the [terminal-plus](https://atom.io/packages/terminal-plus) package to provide the terminal support and uses the [linter](https://atom.io/packages/linter) package to annotate source code with error messages.

## Author

inkytonik, Anthony Sloane ([inkytonik@gmail.com](mailto:inkytonik@gmail.com))

## Usage

Open the top-level directory of an sbt project in Atom.
An interactive sbt session can then be started within Atom using the "Sbt: Toggle Panel" command (`alt-shift-O`).
This command will open a new terminal panel using terminal-plus and run sbt in it.

By default, the sbt package assumes that the sbt script can be invoked as `/usr/local/bin/sbt`.
Use the "sbt Script" setting to specify a different location.

Once the terminal panel has been created, you can interactively invoke sbt commands by typing into the panel.
All interactive sbt commands should work, including cursor movement to access history and TAB to invoke completion.

## History

As well as supporting interactive use, the sbt package has a number of Atom commands to make it easier to send commands to sbt more than once.
The simplest Atom command allows the most recent sbt command to be submitted again.

"Sbt: Run Last Command" (`alt-shift-V`): submit the most recent sbt command again.

For more control over history, the sbt package creates a new Atom command each time a command is submitted to sbt.
E.g., suppose that the first command that you enter to sbt is "test:compile".
After you have interactively entered this command, you will find that a new Atom command "Sbt: History 1 test:compile" has been created.
Thus, you can easily re-send this sbt command using the Atom command palette.
Each subsequent sbt command entered will get an Atom history command with an incremented count.

If you don't want the history commands to be created, you can turn off the "Create History Commands" package setting.

If you accumulate too much history and want to start again, use this command to start again:

"Sbt: Clear History": clear the history commands.

## Adding new commands

The sbt package also supports automatically adding Atom commands that send particular strings to sbt.
The "Command List" package setting is a comma-separated list of sbt commands that you want to have quick access to.
The default setting is "clean, compile, exit, run, test".

When it is first loaded, the sbt package will create one Atom command for each sbt command in the "Command List" setting.
The Atom command will be given a name based on the sbt command.
For example, if the sbt command is "test" then the Atom command will be  `sbt:test` and it will appear in the command palette as "Sbt: Test".
Thus, you can invoke the command via the palette, or more usefully, map a key to it.

Some name mangling is performed when the Atom command is created for the history commands or for new user commands.
Specifically, colons are replaced with hyphens in Atom command names since colon has a special meaning to Atom.
Colons will be replaced by spaces in the palette string for the command.
E.g., if the sbt command is "test:compile" then the corresponding Atom command name will be `sbt:test-compile` and it will appear in the palette as "Sbt: Test Compile".

See the Key Bindings section of the package settings for the bindings that invoke the default sbt command list.

## Error handling

If you issue an sbt command that compiles your code and it generates compiler errors, the sbt package should notice the errors and use the linter package to annotate your code with the messages in the right places.

If you have the linter package set to show linter information in the status bar, you should see something like "n issues" where n is the number of compiler errors.

If you have the linter set to show inline error tooltips and/or highlights for error lines in the gutter, you should see those for your errors too.

Most usefully, you should be able to use the "Linter: Next Error" Atom command (`alt-shift-.` or `alt->`) to cycle through the errors and to go to their locations in your code.

## ScalaTest support

The sbt package also has support for telling the linter about the location of ScalaTest test failures, under some assumptions.
It assumes that test failures look like this:

    [info] MySuite in src/foo/bar:
    [info] - something important works *** FAILED ***
    [info]   99 was not equal to 100 (MyFile.scala:159)

`MySuite` is the name of the ScalaTest suite.
`src/foo/bar` is the path of the suite relative to the top of the project.
The test failed at line 159 of `src/foo/bar/MyFile.scala`.
There may be other lines between the `FAILED` line and the final one.

This is the default output format produced by ScalaTest suites, except for one detail.
ScalaTest does not report the suite path.

The sbt package needs the path so that it can map the failure to the correct file even if more than one file has that name.
We assume that the suite and the file with the failing test live in the same directory.

If you want to use this facility you need to augment your suites so that their names include the path information.
E.g., placing the following code in the suite will produce the output above, assuming that the file is located in the directory given by its package.

    override def suiteName = {
        val pkgName = Option(getClass.getPackage).map(_.getName).getOrElse("")
        val path = s"src/${pkgName.replaceAllLiterally(".", "/")}"
        s"${super.suiteName} in $path"
    }

We're aware that this solution is less than ideal.
If we can convince the ScalaTest maintainers to include this implementation of `suiteName` by default, then we will.
However, the situation is tricky so we are not confident.
E.g., the file in which the failure occurs may not actually be in the same directory as the suite, which is assumed above.
ScalaTest gets the filename from an exception stack trace but Java doesn't provide full paths to files in stack traces, so there is nothing ScalaTest can do.
