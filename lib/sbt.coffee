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
    cmdbuf : ''
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
    saved: ''
    special: ''
    subscriptions: null
    term: null
    tpluspkg: null

    finalRE: /\[.*\] Total time/

    errorRE: /\[error\] ([^:]+):([0-9]+): (.*)/
    errorContRE: /\[error\] ([^\^]*)/
    warnRE: /\[warn\] ([^:]+):([0-9]+): (.*)/
    pointerRE: /\[.*\] ( *)\^/

    contRE: /[0-9]+\. Waiting for source changes\.\.\. \(press enter to interrupt\)/

    testnameRE: /\[info\] \w+ in (.*):/
    failRE: /\[info\] - (.*) \*\*\* FAILED \*\*\*/
    infoRE: /\[info\]   (.*)/
    testRE: /\[info\]   (.*) \(([^:]+):([0-9]+)\)/

    activate: (state) ->
      @subscriptions = new CompositeDisposable
      apd = require('atom-package-deps')
      apd.install().then =>
        @activateProperly()

    activateProperly: ->
      @linterpkg = @activatePackage('linter')
      @tpluspkg = @activatePackage('terminal-plus')
      @history = new CompositeDisposable
      @subscriptions.add atom.commands.add 'atom-workspace', 'sbt:run-last-command': => @runLastCommand()
      @subscriptions.add atom.commands.add 'atom-workspace', 'sbt:clear-history': => @clearHistory()
      @subscriptions.add atom.commands.add 'atom-workspace', 'sbt:toggle-panel': => @togglePanel()
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
        console.log('sbt error: cannot find Atom package ' + pack);

    addCommand: (name, cmd) ->
      @subscriptions.add atom.commands.add 'atom-workspace', name, => @runCommand(cmd)

    addToHistory: (cmd) ->
      @lastCommand = cmd
      if atom.config.get('sbt.createHistoryCommands') and not(@cmds.has(cmd))
        @cmds.add(cmd)
        @history.add atom.commands.add 'atom-workspace', @commandEventName(cmd), => @runCommand(cmd)

    config:
      commandList:
        title: 'Command List'
        type: 'array'
        description: 'This setting is consulted when the package is activated. For each string cmd in the list an Atom workspace command "sbt:cmd" will be defined (with colons in cmd being replaced by hyphens). Thus, test:compile becomes command "sbt:test-compile" and will send the input "test:compile" to sbt when invoked.'
        default: ["clean", "compile", "exit", "run", "test"]
        items:
          type: 'string'
      createHistoryCommands:
        type: 'boolean'
        default: true
        description: 'When checked, each command that is sent to sbt will be added to the command palette as "sbt: History n cmd" where "n" is the command count and "cmd" is the command string. Previously submitted commands can then easily be invoked via the command palette.'
      script:
        title: 'sbt Script'
        type: 'string'
        description: 'The filename of the sbt script.'
        default: '/usr/local/bin/sbt'
      showTermAutomatically:
        title: 'Show the sbt terminal automatically'
        type: 'boolean'
        default: true
        description: 'When checked, the sbt terminal will be made visible each time an sbt command is executed.'

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
      return "sbt:history-#{@cmdcount} #{@encodeEventName(cmd)}"

    deactivate: ->
      @subscriptions?.dispose()
      @history = @subscriptions = @term = null

    # from Open Recent package
    encodeEventName: (s) ->
      s = s.replace('-', '\u2010') # HYPHEN
      s = s.replace(':', '\u02D0') # MO­DI­FI­ER LET­TER TRIANGULAR COLON
      return s

    isRunning: (term) ->
      @tpluspkg.statusBar.indexOf(term) != -1

    parseLineNo: (str) ->
      parseInt(str, 10) - 1

    processData: (data) ->
      if @pendingClear
        @clearMessages()
        @pendingClear = false
      data = @saved + data
      isfull = data.endsWith('\n')
      lines = data.replace(/\x1b\[[0-9]+m/g, '').trim().split('\n')
      if isfull
        @saved = ''
      else
        @saved = lines.pop()
      for line in lines
        do (line) =>
          # console.log(line)
          match = @finalRE.exec(line)
          if match?
            # console.log('finalRE')
            @linter.setMessages(@messages)
            @pkgPath = null
          else
            match = @errorRE.exec(line)
            if match?
              # console.log('errorRE')
              @lineno = @parseLineNo(match[2])
              @message = {type: 'Error', text: match[3], filePath: match[1]}
            else
              match = @warnRE.exec(line)
              if match?
                # console.log('warnRE')
                @lineno = @parseLineNo(match[2])
                @message = {type: 'Warning', text: match[3], filePath: match[1]}
              else
                match = @testnameRE.exec(line)
                if match?
                  # console.log('testnameRE')
                  projpath = atom.project.getPaths()[0]
                  @pkgPath = path.join(projpath, match[1])
                  @info = []
                else
                  match = @failRE.exec(line)
                  if match?
                    # console.log('failRE')
                    @message = {type: 'Error', text: match[1]}
                  else
                    match = @testRE.exec(line)
                    if match?
                      # console.log('testRE')
                      if @message? and @pkgPath?
                        # Needs testnameRE and failRE to have matched earlier
                        @lineno = @parseLineNo(match[3])
                        @message.text = "#{@message.text}\n#{@info.join('\n')}\n#{match[1]}"
                        @message.range = [[@lineno, 1], [@lineno + 1, 1]]
                        @message.filePath = "#{@pkgPath}/#{match[2]}"
                        # console.log(@message)
                        @messages.push(@message)
                        @message = null
                      else
                        # do nothing
                    else
                      match = @pointerRE.exec(line)
                      if match?
                        # console.log('pointerRE')
                        if @message? and not(@pkgPath)
                          # Needs errorRE or warnRE to have matched earlier
                          # Avoid matching pointer lines in test output
                          colno = match[1].length
                          @message.range = [[@lineno, colno], [@lineno, colno]]
                          # console.log(@message)
                          @messages.push(@message)
                          @message = null
                        else
                          # do nothing
                      else
                        match = @errorContRE.exec(line)
                        if match?
                          # console.log('errorContRE')
                          # assume errorRE matched earlier
                          if @message?
                            @message.text = "#{@message.text}\n#{match[1]}"
                          else
                            # do nothing
                        else
                          match = @infoRE.exec(line)
                          if match?
                            # console.log('infoRE')
                            @info.push(match[1])
                          else
                            match = @contRE.exec(line)
                            if match?
                              # console.log('contRE')
                              @pendingClear = true

    runLastCommand: ->
      if @lastCommand != null
        @runCommand(@lastCommand)

    runCommand: (cmd) ->
      @clearMessages()
      @showPanel()
      @addToHistory(cmd)
      @term.input("#{cmd}#{os.EOL}")

    userInput: (data) ->
      if data == "\r"
        @clearMessages()
        @addToHistory(@cmdbuf)
        @cmdbuf = ''
      else
        @cmdbuf = @cmdbuf + data

    setTitle: (term, title) ->
      term.title = title
      term.statusIcon.updateName(title)

    startTerm: ->
      shell = atom.config.get('terminal-plus.core.shell')
      shellArgs = atom.config.get('terminal-plus.core.shellArguments')
      sbt = atom.config.get('sbt.script')
      atom.config.set('terminal-plus.core.shell', sbt)
      atom.config.set('terminal-plus.core.shellArguments', '')
      @tpluspkg.statusBar.newTerminalView()
      @term = @tpluspkg.statusBar.activeTerminal
      atom.config.set('terminal-plus.core.shell', shell)
      atom.config.set('terminal-plus.core.shellArguments', shellArgs)
      @setTitle(@term, 'sbt')
      @term.onTransitionEnd =>
        @term.ptyProcess.on 'terminal-plus:data', (data) =>
          @processData(data)
        @term.ptyProcess.on 'terminal-plus:exit', =>
          @clearMessages()
        @term.terminal.on 'data', (data) =>
          @userInput(data)
      if atom.config.get('sbt.showTermAutomatically') and not(@term.panel.isVisible())
        @term.open()

    showPanel: ->
      if atom.config.get('sbt.showTermAutomatically') and not(@term.panel.isVisible())
        @togglePanel()

    togglePanel: ->
      if @isRunning(@term)
        @term.toggle()
      else
        sbt = atom.config.get('sbt.script')
        fs.access sbt, fs.X_OK, (err) =>
          if err
            atom.confirm
              message: "sbt script can't be executed"
              detailedMessage: "#{sbt}\n\ncan't be executed by Atom.\n\nPlease adjust the sbt Script setting in the sbt package."
          else
            @startTerm()
