CollabGroupProtocol = require '../atox-collabGroupProtocol'
{Range, Point} = require 'atom'
SpanSkipList = require 'span-skip-list'

module.exports =
class Collab extends CollabGroupProtocol
  constructor: (params) ->
    @aTox   = params.aTox
    @editor = params.editor
    @name   = params.name
    @disposables = []
    @internalchanges = []
    @externalchanges = []
    @pmutex = true
    @icb = []
    @diffs = []

    @disposables.push @editor.getBuffer().onDidChange (e) => @internalChange e
    @disposables.push @editor.onDidChangeSelectionRange (e) =>
      @changedSelection e

    @sLines = @editor.getBuffer().getLines().slice()
    @sLineEndings = @editor.getBuffer().lineEndings.slice()

    @offsetIndex = new SpanSkipList('rows', 'characters')
    offsets = @sLines.map (line, index) =>
      {rows: 1, characters: line.length + @sLineEndings[index].length}
    @offsetIndex.spliceArray('rows', 0, @sLines.length, offsets)

    try
      super params
    catch error
      console.log error

  destructor: ->
    for d in @disposables
      d.dispose()

    super()

  getName: -> @name

  internalChange: (e) ->
    if @pmutex and @icb.length > 0
      @internalchanges = @icb.concat(@internalchanges)
      @icb = []

    if e.originFlag? and e.originFlag
      console.log "ignore change"
      return

    if @pmutex
      @internalchanges.push e
    else
      @icb.push e

  externalChange: (e) ->
    return unless e?
    @externalchanges.push e

  generateDiff: ->
    #TODO: implement this
    console.log "Generate Diff"
    @diffs = []

    positionForCharacterIndex = (offset) =>
      offset = Math.max(0, offset)
      offset = Math.min(@offsetIndex.totalTo(Infinity, 'rows').characters, offset)

      {rows, characters} = @offsetIndex.totalTo(offset, 'characters')
      if rows > @sLines.length - 1
        lastRow = @sLines.length - 1
        new Point(lastRow, @sLines[lastRow].length)
      else
        new Point(rows, offset - characters)

    computeTable = (x, y)->
      c = []
      for i in [0 .. x.length - 1]
        c[i] = []
      for i in [0 .. x.length - 1]
        c[i][0] = 0
      for j in [0 .. y.length - 1]
        c[0][j] = 0
      for i in [1 .. x.length - 1]
        for j in [1 .. y.length - 1]
          if x[i] == y[j]
            c[i][j] = c[i-1][j-1] + 1
          else
            c[i][j] = if c[i][j-1] > c[i-1][j] then c[i][j-1] else c[i-1][j]
      return c

    genDiff = (c, x, y, i, j) =>
      if i > 0 and j > 0 and x[i] == y[j]
        genDiff(c, x, y, i-1, j-1)
        #console.log " " + x[i]
      else if j > 0 and (i == 0 or c[i][j-1] >= c[i-1][j])
        console.log "-" + y[j]
        console.log "Update j - 1:" + (j - 1) + " i - 1:" + (i - 1)
        console.log "Values y[j]:" + y[j] + " y[i]:" + y[i]
        oldText = y[j]
        newText = ""
        console.log @editor.getBuffer().positionForCharacterIndex(j - 1)
        console.log positionForCharacterIndex(j - 1)
        console.log @editor.getBuffer().positionForCharacterIndex(j)
        console.log positionForCharacterIndex(j)
        console.log @offsetIndex
        console.log @editor.getBuffer().offsetIndex
        console.log @offsetIndex == @editor.getBuffer().offsetIndex
        oldRange = Range(@editor.getBuffer().positionForCharacterIndex(j - 1), @editor.getBuffer().positionForCharacterIndex(j))
        newRange = Range(@editor.getBuffer().positionForCharacterIndex(j - 1), @editor.getBuffer().positionForCharacterIndex(j - 1))
        originFlag = true
        diff = {oldRange, newRange, oldText, newText, originFlag}
        console.log diff
        @diffs.push diff
        genDiff(c, x, y, i, j - 1)
      else if i > 0 and (j == 0 or c[i][j-1] < c[i-1][j])
        genDiff(c, x, y, i-1, j)
        console.log "+" + x[i]
        console.log "Update line :" + (i - 1)
        oldText = ""
        newText = x[i]
        oldRange = Range(positionForCharacterIndex(i - 1), positionForCharacterIndex(i - 1))
        newRange = Range(positionForCharacterIndex(i - 1), positionForCharacterIndex(i))
        originFlag = true
        diff = {oldRange, newRange, oldText, newText, originFlag}
        console.log diff
        @diffs.push diff
      else
        console.log " "

    xText = ''
    for row in [0 .. @sLines.length - 1]
      xText += (@sLines[row] + @sLineEndings[row])

    yText = ''
    for row in [0 .. @editor.getBuffer().getLines().length - 1]
      yText += (@editor.getBuffer().getLines()[row] + @editor.getBuffer().lineEndings[row])

    x = xText.split("")
    y = yText.split("")
    x.unshift("")
    y.unshift("")
    genDiff(computeTable(x, y), x, y, x.length - 1, y.length - 1)


    #diff = {oldRange, newRange, oldText, newText}
    #@diffs.push diff


  changedSelection: (e) ->

  patchLines: ->
    #Fix pos of internal changes
    for ec, i in @externalchanges
      for ic, j in @internalchanges
        if ic.oldRange.start.row > ec.oldRange.start.row
          @internalchanges[j].newRange.translate([ec.newRange.row - ec.oldRange.row, 0])
          @internalchanges[j].oldRange.translate([ec.newRange.row - ec.oldRange.row, 0]) #Shift row by 1
        else if ic.oldRange.start.row is ec.oldRange.start.row and ic.oldRange.start.column > ec.oldRange.start.column
          @internalchanges[j].newRange.translate([ec.newRange.row - ec.oldRange.row, ec.newRange.end.column - ec.oldRange.end.column])
          @internalchanges[j].oldRange.translate([ec.newRange.row - ec.oldRange.row, ec.newRange.end.column - ec.oldRange.end.column])

  applyExternal: ->
    for ec in @externalchanges
      @applyChange(ec, false)

  applyInternal: ->
    for ic in @internalchanges
      @applyChange(ic, true)

  setBuffer: ->
    for change in @diffs
      @editor.getBuffer().emitter.emit 'will-change', change

    @editor.getBuffer().lines = @sLines.slice()
    @editor.getBuffer().lineEndings = @sLineEndings.slice()

    offsets = @sLines.map (line, index) =>
      {rows: 1, characters: line.length + @sLineEndings[index].length}
    @editor.getBuffer().offsetIndex.spliceArray('rows', 0, @sLines.length, offsets)

    for change in @diffs
      @editor.getBuffer().emitter.emit 'did-change', change

  applyChange: (change, skipUndo) ->
    newlineRegex = /\r\n|\n|\r/g
    spliceArray = (originalArray, start, length, insertedArray=[]) ->
      SpliceArrayChunkSize = 100000
      if insertedArray.length < SpliceArrayChunkSize
        originalArray.splice(start, length, insertedArray...)
      else
        removedValues = originalArray.splice(start, length)
        for chunkStart in [0..insertedArray.length] by SpliceArrayChunkSize
          chunkEnd = chunkStart + SpliceArrayChunkSize
          chunk = insertedArray.slice(chunkStart, chunkEnd)
          originalArray.splice(start + chunkStart, 0, chunk...)
        removedValues

    {oldRange, newRange, oldText, newText, normalizeLineEndings} = change
    oldRange.freeze() if oldRange.freeze? and typeof oldRange.freeze is 'function'
    newRange.freeze() if newRange.freeze? and typeof newRange.freeze is 'function'
    @cachedText = null

    startRow = oldRange.start.row
    endRow = oldRange.end.row
    rowCount = endRow - startRow + 1
    #oldExtent = oldRange.getExtent()
    #newExtent = newRange.getExtent()

    # Determine how to normalize the line endings of inserted text if enabled
    if normalizeLineEndings
      preferredLineEnding = @editor.getBuffer().getPreferredLineEnding()
      normalizedEnding = @preferredLineEnding ? @sLineEndings[startRow]
      unless normalizedEnding
        if startRow > 0
          normalizedEnding = @sLineEndings[startRow - 1]
        else
          normalizedEnding = null

    # Split inserted text into lines and line endings
    lines = []
    lineEndings = []
    lineStartIndex = 0
    normalizedNewText = ""
    while result = newlineRegex.exec(newText)
      line = newText[lineStartIndex...result.index]
      ending = normalizedEnding ? result[0]
      lines.push(line)
      lineEndings.push(ending)
      normalizedNewText += line + ending
      lineStartIndex = newlineRegex.lastIndex

    lastLine = newText[lineStartIndex..]
    lines.push(lastLine)
    lineEndings.push('')
    normalizedNewText += lastLine

    newText = normalizedNewText
    #Deactivated change event
    #changeEvent = Object.freeze({oldRange, newRange, oldText, newText})
    #@emitter.emit 'will-change', changeEvent

    # Update first and last line so replacement preserves existing prefix and suffix of oldRange
    prefix = @sLines[startRow][0...oldRange.start.column]
    lines[0] = prefix + lines[0]
    suffix = @sLines[endRow][oldRange.end.column...]
    lastIndex = lines.length - 1
    lines[lastIndex] += suffix
    lastLineEnding = @sLineEndings[endRow]
    lastLineEnding = normalizedEnding if lastLineEnding isnt '' and normalizedEnding?
    lineEndings[lastIndex] = lastLineEnding

    # Replace lines in oldRange with new lines
    spliceArray(@sLines, startRow, rowCount, lines)
    spliceArray(@sLineEndings, startRow, rowCount, lineEndings)

    # Update the offset index for position <-> character offset translation
    offsets = lines.map (line, index) ->
      {rows: 1, characters: line.length + lineEndings[index].length}
    @offsetIndex.spliceArray('rows', startRow, rowCount, offsets)

    #@markerStore?.splice(oldRange.start, oldRange.getExtent(), newRange.getExtent())
    #@history?.pushChange(change) unless skipUndo

    #@conflict = false if @conflict and !@isModified()
    #@scheduleModifiedEvents()

    #@changeCount++
    #Deactivated emit of change event
    #@emitter.emit 'did-change', changeEvent
    #@emit 'changed', changeEvent if Grim.includeDeprecatedAPIs

  process: ->
    console.log "1"
    @pmutex = false

    @patchLines()
    @applyExternal()
    @applyInternal()
    @generateDiff()
    @setBuffer()

    changes = @internalchanges.slice(0)
    @internalchanges = []
    @externalchanges = []

    #Save state for next round
    #@sLines = @editor.getBuffer().getLines()
    #@sLineEndings = @editor.getBuffer().lineEndings

    @pmutex = true

    return changes

  CMD_startSyncing: (changes) ->
    return
    if changes?
      for c in changes
        @externalChange c if c?
    @patchLines()
    @applyExternal()

  CMD_stopSyncing: (data) ->
    return
    if not data?
      return
    @sLines = data.lines if data.lines?
    @sLineEndings = data.lineEndings if data.lineEndings?
    @offsetIndex = data.offsetIndex if data.offsetIndex?
    @externalchanges = []

  CMD_getSyncData: ->
    return {}
    return {"lines": @sLines, "lineEndings": @sLineEndings, "offsetIndex": @offsetIndex}

  CMD_process: (changes) ->
    @externalchanges = []
    console.log "External Changes:"
    console.log changes
    if changes?
      for pchanges in changes
        @externalChange(c) for c in pchanges
    @process()
