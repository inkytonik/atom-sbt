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
Project = require './project'
path = require 'path'

module.exports =
  Sbt =
    busyProvider: null
    linterpkg: null
    projects: {}
    registerIndie: null
    startupMessage: 'The sbt package looks for the interactive
      sbt prompt to identify commands in the output. Out of the
      box the package assumes the default prompt is being used.
      If you have changed the prompt from the default, you should
      check that the package\'s prompt pattern setting is
      correct.'
    subscriptions: null
    tpluspkg: null

    # Package lifecycle

    activate: (state) ->
      @subscriptions = new CompositeDisposable
      apd = require('atom-package-deps')
      apd.install('sbt').then =>
        @activateProperly()
      if atom.config.get('sbt.showStartupMessage')
        @startupNotification =
          atom.notifications.addInfo 'sbt package startup message', {
            buttons: [
              {
                text: 'Open sbt package settings'
                onDidClick: ->
                  atom.workspace.open('atom://config/packages/sbt')
              }
              {
                text: 'Don\'t show this message again'
                onDidClick: =>
                  atom.config.set('sbt.showStartupMessage', false)
                  @startupNotification.dismiss()
              }
            ]
            detail: @startupMessage
            dismissable: true
          }

    activateProperly: ->
      @linterpkg = @activatePackage('linter')
      @tpluspkg = @activatePackage('platformio-ide-terminal')
      @projects = new CompositeDisposable
      @subscriptions.add atom.commands.add 'atom-workspace',
        'sbt:run-last-command': =>
          project = @getOrMakeCurrentProject()
          project.runLastCommand()
      @subscriptions.add atom.commands.add 'atom-workspace',
        'sbt:clear-history': =>
          project = @getOrMakeCurrentProject()
          project.clearHistory()
      @subscriptions.add atom.commands.add 'atom-workspace',
        'sbt:toggle-panel': =>
          project = @getOrMakeCurrentProject()
          project.togglePanel()
      for cmd in atom.config.get('sbt.commandList')
        name = "sbt:#{cmd.replace(':', '-')}"
        @addCommand(name, cmd)
      project = @getOrMakeCurrentProject()
      project.togglePanel()

    addCommand: (name, cmd) ->
      @subscriptions.add atom.commands.add 'atom-workspace',
        name, =>
          project = @getOrMakeCurrentProject()
          project.runCommand(cmd)

    activatePackage: (name) ->
      if not atom.packages.isPackageActive(name)
        atom.packages.activatePackage(name)
      pack = atom.packages.getLoadedPackage(name)
      if (pack && pack.mainModulePath)
        require(pack.mainModulePath)
      else
        console.log('sbt error: cannot find Atom package ' + pack)

    deactivate: ->
      @subscriptions?.dispose()
      @projects?.dispose()
      @subscriptions = @projects = null

    consumeIndie: (registerIndie) ->
      @registerIndie = registerIndie

    consumeSignal: (registry) ->
      @busyProvider = registry.create()
      @subscriptions.add(@busyProvider)

    # Projects

    getProjectPathOfCurrentFile: ->
      editor = atom.workspace.getActiveTextEditor()
      filePath = if editor?
                   editor.getPath()
                 else
                   atom.project.getPaths()[0]
      for dir in atom.workspace.project.getDirectories()
        dirPath = dir.getPath()
        if dirPath == filePath or dir.contains(filePath)
          return dirPath
      'unknown'

    getCurrentProject: ->
      projectPath = @getProjectPathOfCurrentFile()
      @projects[projectPath]

    getOrMakeCurrentProject: ->
      projectPath = @getProjectPathOfCurrentFile()
      if not @projects[projectPath]
        id = path.basename(projectPath)
        baseTitle =
          if atom.config.get('sbt.titleShowsFullPath')
            projectPath
          else
            id
        title = "sbt #{baseTitle}"
        linter = @registerIndie({name: title})
        @subscriptions.add(linter)
        @projects[projectPath] =
          new Project(id, title, linter, @busyProvider, @tpluspkg)
      @projects[projectPath]

    # Configuration

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
          your sbt prompt. Avoid patterns that match other useful sbt output
          lines, such as log lines that start with a left square bracket.
          E.g., `^(?!\\[)[^>]*> ` avoids lines starting with left bracket and
          matches prompts that end in `> `.'
      script:
        title: 'sbt Script'
        type: 'string'
        description: 'The filename of the sbt script.'
        default: '/usr/local/bin/sbt'
      showStartupMessage:
        title: 'Show the sbt package startup message when activated'
        type: 'boolean'
        default: true
        description: 'The startup message displays important information
          that helps you to get the sbt package working when you first
          start using it. Normally you will not need to see the message
          more than once.'
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
