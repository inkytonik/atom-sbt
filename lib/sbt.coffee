# atom-sbt Atom plugin for Scala Build Tool (sbt)
# Copyright (C) 2016 Anthony M. Sloane
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

{CompositeDisposable} = require 'atom'
fs = require 'fs'
path = require 'path'
os = require 'os'

module.exports =
  Sbt =
    cmdcount: 0
    cmds: new Set([])
    history: null
    info: []
    message: null
    messages: []
    pendingClear: false
    pkgPath: null
    lastCommand: null
    lineno: null
    linterpkg: null
    needsEOL: false
    saved: ''
    special: ''
    subscriptions: null
    term: null
    tpluspkg: null
    waiting: false

    finalRE: /^\[.*\] Total time/

    errorRE: /^\[error\] ([^:]+):([0-9]+): (.*)/
    errorContRE: /^\[error\] ([^\^]*)/
    warnRE: /^\[warn\] ([^:]+):([0-9]+): (.*)/
    pointerRE: /^\[.*\] ( *)\^/

    contRE:
      /^[0-9]+\. Waiting for source changes\.\.\. \(press enter to interrupt\)/

    testnameRE: /^\[info\] \w+ in (.*):/
    failRE: /^\[info\] - (.*) \*\*\* FAILED \*\*\*/
    infoRE: /^\[info\]   (.*)/
    testRE: /^\[info\]   (.*) \(([^:]+):([0-9]+)\)/

    activate: (state) ->
      @subscriptions = new CompositeDisposable
      apd = require('atom-package-deps')
      apd.install().then =>
        @activateProperly()

    activateProperly: ->
      @linterpkg = @activatePackage('linter')
      @tpluspkg = @activatePackage('platformio-ide-terminal')
      @history = new CompositeDisposable
      @subscriptions.add atom.commands.add 'atom-workspace',
        'sbt:run-last-command': => @runLastCommand()
      @subscriptions.add atom.commands.add 'atom-workspace',
        'sbt:clear-history': => @clearHistory()
      @subscriptions.add atom.commands.add 'atom-workspace',
        'sbt:toggle-panel': => @togglePanel()
      for cmd in atom.config.get('sbt.commandList')
        name = "sbt:#{cmd.replace(':', '-')}"
        @addCommand(name, cmd)
      @togglePanel()

    activatePackage: (name) ->
      if not atom.packages.isPackageActive(name)
        atom.packages.activatePackage(name)
      pack = atom.packages.getLoadedPackage(name)
      if (pack && pack.mainModulePath)
        require(pack.mainModulePath)
      else
        console.log('sbt error: cannot find Atom package ' + pack)

    addCommand: (name, cmd) ->
      @subscriptions.add atom.commands.add 'atom-workspace',
        name, => @runCommand(cmd)

    addToHistory: (cmd) ->
      @lastCommand = cmd
      if atom.config.get('sbt.createHistoryCommands') and not(@cmds.has(cmd))
        @cmds.add(cmd)
        @history.add atom.commands.add 'atom-workspace',
          @commandEventName(cmd), => @runCommand(cmd)

    config:
      commandList:
        title: 'Command List'
        type: 'array'
        description: 'This setting is consulted when the package is activated.
          For each string cmd in the list an Atom workspace command "sbt:cmd"
          will be defined (with colons in cmd being replaced by hyphens).
          Thus, test:compile becomes command "sbt:test-compile" and will send
          the input "test:compile" to sbt when invoked.'
        default: ["clean", "compile", "exit", "run", "test"]
        items:
          type: 'string'
      createHistoryCommands:
        type: 'boolean'
        default: true
        description: 'When checked, each command that is sent to sbt will be
          added to the command palette as "sbt: History n cmd" where "n" is
          the command count and "cmd" is the command string. Previously
          submitted commands can then easily be invoked via the command
          palette.'
      promptPattern:
        type: 'string'
        default: '^> '
        description: 'A regular expression matching a line that starts with
          your sbt prompt. The regular expression should not contain any
          grouping commands (parentheses). Avoid patterns that match other
          useful sbt output lines, such as log lines that start with a left
          square bracket.'
      script:
        title: 'sbt Script'
        type: 'string'
        description: 'The filename of the sbt script.'
        default: '/usr/local/bin/sbt'
      showTermAuto:
        title: 'Show the sbt terminal automatically'
        type: 'boolean'
        default: true
        description: 'When checked, the sbt terminal will be made visible
          each time an sbt command is executed.'
      titleShowsFullPath:
        title: 'Terminal title should show full project path'
        type: 'boolean'
        default: false
        description: 'Normally the sbt terminal title includes only the
          basename of the project path. When this is checked, the title
          will show the full project path.'

    consumeLinter: (indieRegistry) ->
      @linter = indieRegistry.register({name: 'sbt'})
      @subscriptions.add(@linter)

    clearHistory: ->
      @cmdcount = 0
      @cmds = new Set([])
      @history?.dispose()

    clearMessages: ->
      @messages = []
      @linter.setMessages(@messages)

    commandEventName: (cmd) ->
      @cmdcount = @cmdcount + 1
      "sbt:history-#{@cmdcount} #{@encodeEventName(cmd)}"

    deactivate: ->
      @subscriptions?.dispose()
      @history = @subscriptions = @term = null

    # from Open Recent package
    encodeEventName: (s) ->
      s = s.replace('-', '\u2010') # HYPHEN
      s = s.replace(':', '\u02D0') # MO­DI­FI­ER LET­TER TRIANGULAR COLON
      s

    isRunning: (term) ->
      @tpluspkg.statusBarTile.indexOf(term) != -1

    parseLineNo: (str) ->
      parseInt(str, 10) - 1

    processData: (data) ->
      if @pendingClear
        @clearMessages()
        @pendingClear = false
      data = @saved + data
      # console.log("data: |#{data}|")
      isfull = data.endsWith('\n')
      lines = data.replace(/\x1b\[[0-9]+m/g, '').split('\n')
      if isfull
        @saved = ''
      else
        @saved = lines.pop()
      promptRE = new RegExp("#{atom.config.get('sbt.promptPattern')}(.*)")
      if @waiting and promptRE.exec(data)
        @waiting = false
        if @pendingInput
          @term.input(@pendingInput)
          @pendingInput = null
      for line in lines
        do (line) =>
          # console.log(line)
          switch
            when @finalRE.exec(line)
              # console.log('finalRE')
              @linter.setMessages(@messages)
              @pkgPath = null
            when match = @errorRE.exec(line)
              # console.log('errorRE')
              @lineno = @parseLineNo(match[2])
              @message = {type: 'Error', text: match[3], filePath: match[1]}
            when match = @warnRE.exec(line)
              # console.log('warnRE')
              @lineno = @parseLineNo(match[2])
              @message = {type: 'Warning', text: match[3], filePath: match[1]}
            when match = @testnameRE.exec(line)
              # console.log('testnameRE')
              projpath = atom.project.getPaths()[0]
              @pkgPath = path.join(projpath, match[1])
              @info = []
            when match = @failRE.exec(line)
              # console.log('failRE')
              @message = {type: 'Error', text: match[1]}
            when match = @testRE.exec(line)
              # console.log('testRE')
              if @message? and @pkgPath?
                # Needs testnameRE and failRE to have matched earlier
                @lineno = @parseLineNo(match[3])
                @infolines = @info.join('\n')
                @message.text = "#{@message.text}\n#{@infolines}\n#{match[1]}"
                @message.range = [[@lineno, 1], [@lineno + 1, 1]]
                @message.filePath = "#{@pkgPath}/#{match[2]}"
                # console.log(@message)
                @messages.push(@message)
                @message = null
            when match = @pointerRE.exec(line)
              # console.log('pointerRE')
              if @message? and not(@pkgPath)
                # Needs errorRE or warnRE to have matched earlier
                # Avoid matching pointer lines in test output
                colno = match[1].length
                @message.range = [[@lineno, colno], [@lineno, colno]]
                # console.log(@message)
                @messages.push(@message)
                @message = null
            when match = @errorContRE.exec(line)
              # console.log('errorContRE')
              if @message?
                # Need errorRE matched earlier
                @message.text = "#{@message.text}\n#{match[1]}"
            when match = @infoRE.exec(line)
              # console.log('infoRE')
              @info.push(match[1])
            when match = @contRE.exec(line)
              # console.log('contRE')
              @pendingClear = true
              @needsEOL = true
              @waiting = true
            when match = promptRE.exec(line)
              # console.log("promptRE #{line}")
              cmd = @outputToCmd(match[1])
              @addToHistory(cmd)
              @clearMessages()

    runLastCommand: ->
      if @lastCommand != null
        @runCommand(@lastCommand)

    runCommand: (cmd) ->
      @clearMessages()
      @showPanel()
      input = "#{cmd}#{os.EOL}"
      if @needsEOL
        @term.input(os.EOL)
        @needsEOL = false
      if @waiting
        @pendingInput = input
      else
        @term.input(input)

    startTerm: ->
      shell = atom.config.get('platformio-ide-terminal.core.shell')
      shellArgs = atom.config.get('platformio-ide-terminal.core.shellArguments')
      sbt = atom.config.get('sbt.script')
      atom.config.set('platformio-ide-terminal.core.shell', sbt)
      atom.config.set('platformio-ide-terminal.core.shellArguments', '')
      @tpluspkg.statusBarTile.newTerminalView()
      @term = @tpluspkg.statusBarTile.activeTerminal
      atom.config.set('platformio-ide-terminal.core.shell', shell)
      atom.config.set('platformio-ide-terminal.core.shellArguments', shellArgs)
      @setTitle(@term)
      @term.onTransitionEnd =>
        @term.ptyProcess.on 'platformio-ide-terminal:data', (data) =>
          @processData(data)
        @term.ptyProcess.on 'platformio-ide-terminal:exit', =>
          @clearMessages()
      if atom.config.get('sbt.showTermAuto') and not(@term.panel.isVisible())
        @term.open()

    showPanel: ->
      if atom.config.get('sbt.showTermAuto') and not(@term.panel.isVisible())
        @togglePanel()

    togglePanel: ->
      if @isRunning(@term)
        @term.toggle()
      else
        @waiting = true
        sbt = atom.config.get('sbt.script')
        fs.access sbt, fs.X_OK, (err) =>
          if err
            atom.confirm
              message: "sbt script can't be executed"
              detailedMessage: "#{sbt}\n\ncan't be executed by Atom.\n\nPlease
                adjust the sbt Script setting in the sbt package."
          else
            @startTerm()

    # Titles

    changeTitle: (term, title) ->
      term.title = title
      term.statusIcon.updateName(title)

    setTitle: (term) ->
      @changeTitle(term, "sbt")
      editor = atom.workspace.getActiveTextEditor()
      filePath = if editor?
                   editor.getPath()
                 else
                   atom.project.getPaths()[0]
      for dir in atom.workspace.project.getDirectories()
        dirPath = dir.getPath()
        if dirPath = filePath or dir.contains(filePath)
          id =
            if atom.config.get('sbt.titleShowsFullPath')
              dirPath
            else
              dir.getBaseName()
          @changeTitle(term, "sbt #{id}")

    # Output sequence handling. Horrible but there appears to be
    # no other way to capture the actual commands executed by sbt.

    cursorBwdRE: /^\x1b\[([0-9]*)D/
    cursorFwdRE: /^\x1b\[([0-9]*)C/
    lineEraseRE: /^\x1b\[K/

    argToNum: (arg) ->
      if arg == '' then 0 else parseInt(arg, 10)

    outputToCmd: (output) ->
      result = ''
      respos = 0
      outpos = 0
      while outpos < output.length
        ch = output[outpos]
        switch
          when ch == '\x1b'
            rest = output[outpos..]
            switch
              when match = @cursorBwdRE.exec(rest)
                # console.log("saw backward #{match[1]}")
                respos = respos - @argToNum(match[1])
                outpos = outpos + match[0].length
              when match = @cursorFwdRE.exec(rest)
                # console.log("saw forward #{match[1]}")
                respos = respos + @argToNum(match[1])
                outpos = outpos + match[0].length
              when match = @lineEraseRE.exec(rest)
                # console.log("saw line erase of len #{match[0].length}")
                result = result[0...respos]
                outpos = outpos + match[0].length
              else
                console.log("sbt: unknown esc seq at #{rest}")
                result = output
                outpos = output.length
          when ch == '\b'
            respos = respos - 1
            outpos = outpos + 1
          else
            result = result[0...respos] + ch
            respos = respos + 1
            outpos = outpos + 1
      result
