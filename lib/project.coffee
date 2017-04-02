# atom-sbt Atom plugin for Scala Build Tool (sbt)
# Copyright (C) 2016-2017 Anthony M. Sloane
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
os = require 'os'
path = require 'path'

module.exports =
class Project
  cmdcount: 0
  cmds: null
  history: null
  info: []
  lastCommand: null
  lineno: null
  message: null
  messages: []
  needsEOL: false
  pendingClear: false
  pendingInput: false
  pkgPath: null
  saved: ''
  term: null
  waiting: false

  constructor: (@projectPath, @tpluspkg, @linter) ->
    @history = new CompositeDisposable
    @id = path.basename(@projectPath)
    baseTitle =
      if atom.config.get('sbt.titleShowsFullPath')
        @projectPath
      else
        @id
    @title = "sbt #{baseTitle}"

  # Terminal panel management

  isRunning: ->
    @tpluspkg.statusBarTile.indexOf(@term) != -1

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
    @setTitle()
    @term.onTransitionEnd =>
      @term.ptyProcess.on 'platformio-ide-terminal:data', (data) =>
        @processData(data)
      @term.ptyProcess.on 'platformio-ide-terminal:exit', =>
        @clearHistory()
        @clearMessages()
        @term = null
    @showPanel()

  setTitle: ->
    @term.title = @title
    @term.statusIcon.updateName(@title)

  showPanel: ->
    if @term?
      if atom.config.get('sbt.showTermAuto') and not(@term.panel.isVisible())
        @togglePanel()
    else
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

  # Command execution

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

  # Output processing

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

  clearMessages: ->
    @messages = []
    @linter.setAllMessages([])

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
            @linter.setAllMessages(@messages)
            @pkgPath = null
          when match = @errorRE.exec(line)
            # console.log('errorRE')
            @lineno = @parseLineNo(match[2])
            @message = {
              severity: 'error',
              location: {file: match[1]},
              excerpt: match[3]
            }
          when match = @warnRE.exec(line)
            # console.log('warnRE')
            @lineno = @parseLineNo(match[2])
            @message = {
              severity: 'warning',
              location: {file: match[1]},
              excerpt: match[3]
            }
          when match = @testnameRE.exec(line)
            # console.log('testnameRE')
            projpath = atom.project.getPaths()[0]
            @pkgPath = path.join(projpath, match[1])
            @info = []
          when match = @failRE.exec(line)
            # console.log('failRE')
            @message = {
              severity: 'error',
              excerpt: match[1]
            }
          when match = @testRE.exec(line)
            # console.log('testRE')
            if @message? and @pkgPath?
              # Needs testnameRE and failRE to have matched earlier
              @lineno = @parseLineNo(match[3])
              @extra = @info.join('\n')
              @message.excerpt = "#{@message.excerpt}\n#{@extra}\n#{match[1]}"
              @message.location = {
                file: "#{@pkgPath}/#{match[2]}",
                position: [[@lineno, 1], [@lineno + 1, 1]]
              }
              # console.log(@message)
              @messages.push(@message)
              @message = null
          when match = @pointerRE.exec(line)
            # console.log('pointerRE')
            if @message? and not(@pkgPath)
              # Needs errorRE or warnRE to have matched earlier
              # Avoid matching pointer lines in test output
              colno = match[1].length
              @message.location.position = [[@lineno, colno], [@lineno, colno]]
              # console.log(@message)
              @messages.push(@message)
              @message = null
          when match = @errorContRE.exec(line)
            # console.log('errorContRE')
            if @message?
              # Need errorRE matched earlier
              @message.excerpt = "#{@message.excerpt}\n#{match[1]}"
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
            cmd = @outputToCmd(match[match.length - 1])
            @addToHistory(cmd)
            @clearMessages()

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

  # History

  addToHistory: (cmd) ->
    @cmds ?= new Set([])
    @lastCommand = cmd
    if atom.config.get('sbt.createHistoryCommands') and not(@cmds.has(cmd))
      @cmds.add(cmd)
      @history.add atom.commands.add 'atom-workspace',
        @commandEventName(cmd), => @runCommand(cmd)

  clearHistory: ->
    @lastCommand = null
    @cmdcount = 0
    @cmds = new Set([])
    @history?.dispose()

  commandEventName: (cmd) ->
    @cmdcount = @cmdcount + 1
    "sbt:history-#{@cmdcount} #{@id} #{@encodeEventName(cmd)}"

  # from Open Recent package
  encodeEventName: (s) ->
    s = s.replace('-', '\u2010') # HYPHEN
    s = s.replace(':', '\u02D0') # MO­DI­FI­ER LET­TER TRIANGULAR COLON
    s
