# atom-sbt

An Atom interface to the Scala Build Tool (sbt).

This package provides support for interactive use of sbt within the Atom editor.
It uses the [terminal-plus](https://atom.io/packages/terminal-plus) package to provide the terminal support and uses the [linter](https://atom.io/packages/linter) package to annotate source code with error messages.

## Author

inkytonik, Anthony Sloane ([inkytonik@gmail.com](mailto:inkytonik@gmail.com))

## Usage

Open the top-level directory of an sbt project in Atom.
An interactive sbt session can then be started within Atom using the "Sbt: Toggle Panel" command (`alt-shift-O`).
This command will open a new terminal panel using terminal-plus and run sbt in it.

The sbt package currently assumes that the sbt script can be invoked as "sbt" so you will need to ensure that the Atom process has the appropriate environment variables set to enable it to be found.

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

See the Key Bindings section of the package settings for the bindings that invoke the default sbt command list.

## Error handling

If you issue an sbt command that compiles your code and it generates compiler errors, the sbt package should notice the errors and use the linter package to annotate your code with the messages in the right places.

If you have the linter package set to show linter information in the status bar, you should see something like "n issues" where n is the number of compiler errors.

If you have the linter set to show inline error tooltips and/or highlights for error lines in the gutter, you should see those for your errors too.

Most usefully, you should be able to use the "Linter: Next Error" Atom command (`alt-shift-.` or `alt->`) to cycle through the errors and to go to their locations in your code.
