import std/[os, strutils, parseopt]

const
  Version* = "0.1.0"
  DefaultMaxWidth* = 80

type
  CommentKind* = enum
    ckLine        ## Regular line comment: `# ...`
    ckDocLine     ## Doc line comment: `## ...`
    ckBlock       ## Block comment: `#[ ... ]#`
    ckDocBlock    ## Doc block comment: `##[ ... ]##`

  SpanKind* = enum
    skCode        ## Raw Nim source code (untouched)
    skComment     ## Comment span to be formatted

  SourceSpan* = object
    kind*: SpanKind
    text*: string
    commentKind*: CommentKind
    indent*: string       ## Leading indentation for line comments
    prefix*: string       ## e.g. "#", "##", "#[", "##["

  FormatConfig* = object
    maxWidth*: int
    formatRegularComments*: bool
    formatDocComments*: bool
    checkOnly*: bool
    diffOnly*: bool
    writeInPlace*: bool

proc scanSource*(src: string): seq[SourceSpan] =
  ## Scans Nim source code into alternating Code and Comment spans.
  ## Guarantee: Concatenating all `span.text` reproduces `src` 100% byte-identical.
  result = @[]
  var i = 0
  let n = src.len
  var codeBuf = ""

  template flushCode() =
    if codeBuf.len > 0:
      result.add(SourceSpan(kind: skCode, text: codeBuf))
      codeBuf = ""

  while i < n:
    # 1. Triple-quoted string: """..."""
    if i + 2 < n and src[i] == '"' and src[i+1] == '"' and src[i+2] == '"':
      codeBuf.add(src[i .. i+2])
      i += 3
      while i < n:
        if i + 2 < n and src[i] == '"' and src[i+1] == '"' and src[i+2] == '"':
          codeBuf.add(src[i .. i+2])
          i += 3
          break
        else:
          codeBuf.add(src[i])
          i += 1
      continue

    # 2. Raw or generalized string literal: e.g. r"...", identifier"..."
    # Check if we just matched an identifier followed immediately by '"'
    if i < n and src[i] == '"':
      # Standard double-quoted string
      codeBuf.add(src[i])
      i += 1
      while i < n:
        if src[i] == '\\' and i + 1 < n:
          codeBuf.add(src[i .. i+1])
          i += 2
        elif src[i] == '"':
          codeBuf.add(src[i])
          i += 1
          break
        elif src[i] in {'\r', '\n'}:
          # Unterminated string on current line
          break
        else:
          codeBuf.add(src[i])
          i += 1
      continue

    # 3. Character literal: 'a', '\'', '\\'
    if src[i] == '\'':
      codeBuf.add(src[i])
      i += 1
      while i < n:
        if src[i] == '\\' and i + 1 < n:
          codeBuf.add(src[i .. i+1])
          i += 2
        elif src[i] == '\'':
          codeBuf.add(src[i])
          i += 1
          break
        elif src[i] in {'\r', '\n'}:
          break
        else:
          codeBuf.add(src[i])
          i += 1
      continue

    # 4. Block comments: #[ ... ]# or ##[ ... ]##
    if i + 2 < n and src[i] == '#' and src[i+1] == '#' and src[i+2] == '[':
      # Doc block comment: ##[
      flushCode()
      let start = i
      var depth = 1
      i += 3
      while i < n and depth > 0:
        if i + 2 < n and src[i] == '#' and src[i+1] == '#' and src[i+2] == '[':
          depth += 1
          i += 3
        elif i + 2 < n and src[i] == ']' and src[i+1] == '#' and src[i+2] == '#':
          depth -= 1
          i += 3
        else:
          i += 1
      let rawText = src[start ..< i]
      result.add(SourceSpan(kind: skComment, text: rawText, commentKind: ckDocBlock, prefix: "##["))
      continue

    if i + 1 < n and src[i] == '#' and src[i+1] == '[':
      # Regular block comment: #[
      flushCode()
      let start = i
      var depth = 1
      i += 2
      while i < n and depth > 0:
        if i + 1 < n and src[i] == '#' and src[i+1] == '[':
          depth += 1
          i += 2
        elif i + 1 < n and src[i] == ']' and src[i+1] == '#':
          depth -= 1
          i += 2
        else:
          i += 1
      let rawText = src[start ..< i]
      result.add(SourceSpan(kind: skComment, text: rawText, commentKind: ckBlock, prefix: "#["))
      continue

    # 5. Line comments: ## ... or # ...
    if src[i] == '#':
      flushCode()
      let isDoc = (i + 1 < n and src[i+1] == '#')
      let prefix = if isDoc: "##" else: "#"
      let start = i
      # Determine leading indentation on current line
      var lineStart = start
      while lineStart > 0 and src[lineStart - 1] notin {'\r', '\n'}:
        lineStart -= 1
      let linePrefix = src[lineStart ..< start]
      var isOnlyWhitespace = true
      for c in linePrefix:
        if c notin {' ', '\t'}:
          isOnlyWhitespace = false
          break

      # Advance until end of line
      while i < n and src[i] notin {'\r', '\n'}:
        i += 1
      let rawText = src[start ..< i]
      result.add(SourceSpan(
        kind: skComment,
        text: rawText,
        commentKind: if isDoc: ckDocLine else: ckLine,
        prefix: prefix,
        indent: if isOnlyWhitespace: linePrefix else: ""
      ))
      continue

    # Standard code character
    codeBuf.add(src[i])
    i += 1

  flushCode()

# ------------------------------------------------------------------------------
# Markdown Comment Formatter
# ------------------------------------------------------------------------------

proc isCodeFence(line: string): bool =
  let trimmed = line.strip()
  trimmed.startsWith("```") or trimmed.startsWith("~~~")

proc isHeading(line: string): bool =
  let trimmed = line.strip()
  trimmed.startsWith("# ") or trimmed.startsWith("## ") or
  trimmed.startsWith("### ") or trimmed.startsWith("#### ") or
  trimmed.startsWith("##### ") or trimmed.startsWith("###### ")

proc isBanner(line: string): bool =
  let trimmed = line.strip()
  if trimmed.len >= 3 and (
    trimmed.startsWith("===") or trimmed.startsWith("---") or
    trimmed.startsWith("***") or trimmed.startsWith("___")
  ):
    return true
  if trimmed.startsWith("<!--") or trimmed.endsWith("-->"):
    return true
  false

proc isListItem(line: string, markerLen: var int, isOrdered: var bool): bool =
  let trimmed = line.strip()
  if trimmed.startsWith("- ") or trimmed.startsWith("* ") or trimmed.startsWith("+ "):
    markerLen = 2
    isOrdered = false
    return true
  # Check ordered list: "1. ", "10. "
  var idx = 0
  while idx < trimmed.len and trimmed[idx] in {'0'..'9'}:
    idx += 1
  if idx > 0 and idx + 1 < trimmed.len and trimmed[idx] == '.' and trimmed[idx+1] == ' ':
    markerLen = idx + 2
    isOrdered = true
    return true
  false

proc isBlockquote(line: string): bool =
  line.strip().startsWith("> ") or line.strip() == ">"

proc isTable(line: string): bool =
  let trimmed = line.strip()
  trimmed.startsWith("|") and trimmed.endsWith("|")

proc formatMarkdownParagraph(
    para: string,
    maxWidth: int,
    baseIndent: string,
    hangingIndent: string = ""
): seq[string] =
  ## Reflows an ordinary markdown prose paragraph into lines of maximum `maxWidth`.
  result = @[]
  let words = para.splitWhitespace()
  if words.len == 0:
    return @[""]

  var curLine = baseIndent
  var isFirst = true

  for word in words:
    let spaceNeeded = if isFirst: 0 else: 1
    if not isFirst and curLine.len + spaceNeeded + word.len > maxWidth:
      result.add(curLine.strip(leading = false, trailing = true))
      curLine = if hangingIndent.len > 0: hangingIndent & word else: baseIndent & word
      isFirst = false
    else:
      if not isFirst:
        curLine.add(" ")
      curLine.add(word)
      isFirst = false

  if curLine.strip().len > 0:
    result.add(curLine.strip(leading = false, trailing = true))

proc formatLinesMarkdown*(lines: seq[string], maxWidth: int, prefix: string): seq[string] =
  ## Formats a sequence of raw comment interior lines into cleanly formatted markdown lines.
  result = @[]
  var i = 0
  var inCodeFence = false

  while i < lines.len:
    let rawLine = lines[i]
    let trimmed = rawLine.strip()

    # Code fence detection
    if isCodeFence(trimmed):
      inCodeFence = not inCodeFence
      result.add(rawLine.strip(leading = false, trailing = true))
      i += 1
      continue

    if inCodeFence:
      # Code block contents: preserve exactly
      result.add(rawLine.strip(leading = false, trailing = true))
      i += 1
      continue

    # Blank line
    if trimmed.len == 0:
      result.add("")
      i += 1
      continue

    # Markdown elements that must NOT be wrapped
    var markerLen = 0
    var isOrdered = false
    if isHeading(trimmed) or isBanner(trimmed) or isTable(trimmed) or isBlockquote(trimmed):
      result.add(rawLine.strip(leading = false, trailing = true))
      i += 1
      continue

    # List item
    if isListItem(trimmed, markerLen, isOrdered):
      # Extract bullet and prose
      let leadSpaces = rawLine.len - rawLine.strip(leading = true).len
      let indentStr = repeat(' ', leadSpaces)
      let hangStr = indentStr & repeat(' ', markerLen)
      var listPara = trimmed
      i += 1
      # Gobble continuation lines that belong to this list item
      while i < lines.len:
        let nextTrimmed = lines[i].strip()
        var dummyLen = 0
        var dummyOrd = false
        if nextTrimmed.len == 0 or isListItem(nextTrimmed, dummyLen, dummyOrd) or
           isHeading(nextTrimmed) or isBanner(nextTrimmed) or isCodeFence(nextTrimmed):
          break
        listPara.add(" " & nextTrimmed)
        i += 1

      let formattedList = formatMarkdownParagraph(listPara, maxWidth, indentStr, hangStr)
      for fl in formattedList:
        result.add(fl)
      continue

    # Ordinary paragraph: collect consecutive non-empty lines that aren't special
    var para = trimmed
    let leadSpaces = rawLine.len - rawLine.strip(leading = true).len
    let indentStr = repeat(' ', leadSpaces)
    i += 1
    while i < lines.len:
      let nextTrimmed = lines[i].strip()
      var dummyLen = 0
      var dummyOrd = false
      if nextTrimmed.len == 0 or isListItem(nextTrimmed, dummyLen, dummyOrd) or
         isHeading(nextTrimmed) or isBanner(nextTrimmed) or isCodeFence(nextTrimmed) or
         isTable(nextTrimmed) or isBlockquote(nextTrimmed):
        break
      para.add(" " & nextTrimmed)
      i += 1

    let formattedPara = formatMarkdownParagraph(para, maxWidth, indentStr)
    for fp in formattedPara:
      result.add(fp)

# ------------------------------------------------------------------------------
# Formatting Operations for Spans
# ------------------------------------------------------------------------------

proc formatSingleLineCommentSpan(span: SourceSpan, config: FormatConfig): string =
  ## Formats a single line comment: e.g. "## hello world"
  let pLen = span.prefix.len
  if span.text.len <= pLen:
    return span.text

  let afterPrefix = span.text[pLen .. ^1]
  if afterPrefix.len == 0 or afterPrefix.strip().len == 0:
    return span.prefix

  let space = if afterPrefix.startsWith(" "): " " else: " "
  let trimmedContent = afterPrefix.strip()
  # Only reflow if it exceeds max width
  let totalLen = span.indent.len + span.prefix.len + 1 + trimmedContent.len
  if totalLen <= config.maxWidth:
    return span.prefix & space & trimmedContent

  # Wrap single-line comment paragraph
  let targetWidth = config.maxWidth - span.indent.len - span.prefix.len - 1
  let wrapped = formatMarkdownParagraph(trimmedContent, targetWidth, "")
  if wrapped.len == 0:
    return span.prefix
  var res = ""
  for idx, line in wrapped:
    if idx > 0:
      res.add("\n" & span.indent)
    res.add(span.prefix & (if line.len > 0: " " & line else: ""))
  res

proc formatBlockCommentSpan(span: SourceSpan, config: FormatConfig): string =
  ## Formats block comments: #[ ... ]# or ##[ ... ]##
  let isDoc = span.commentKind == ckDocBlock
  let openTag = if isDoc: "##[" else: "#["
  let closeTag = if isDoc: "]##" else: "]#"

  if not span.text.startsWith(openTag) or not span.text.endsWith(closeTag):
    return span.text

  let inner = span.text[openTag.len ..< span.text.len - closeTag.len]
  let lines = inner.splitLines()
  let formattedInner = formatLinesMarkdown(lines, config.maxWidth, "")
  var res = openTag
  for idx, l in formattedInner:
    if idx == 0 and not inner.startsWith("\n") and not inner.startsWith("\r\n"):
      if l.len > 0:
        res.add(l)
    else:
      res.add("\n" & l)
  if not res.endsWith("\n") and inner.endsWith("\n"):
    res.add("\n")
  res.add(closeTag)
  res

proc isNewlineWithIndent(codeText: string, expectedIndent: string): bool =
  ## Returns true if codeText is exactly a single newline optionally followed by expectedIndent
  if codeText == "\n" or codeText == "\r\n":
    return expectedIndent.len == 0
  if codeText == "\n" & expectedIndent or codeText == "\r\n" & expectedIndent:
    return true
  false

proc formatContiguousLineComments(
    spans: seq[SourceSpan],
    startIdx: int,
    consumedCount: var int,
    config: FormatConfig
): string =
  let targetSpan = spans[startIdx]
  let prefix = targetSpan.prefix
  let indent = targetSpan.indent

  var rawLines: seq[string] = @[]
  var j = startIdx

  while j < spans.len:
    if spans[j].kind == skComment and spans[j].commentKind == targetSpan.commentKind and spans[j].indent == indent:
      let pLen = prefix.len
      let text = spans[j].text
      let after = if text.len > pLen: text[pLen .. ^1] else: ""
      rawLines.add(if after.startsWith(" "): after[1 .. ^1] else: after)

      # Check if next span is newline + indent followed by another matching comment
      if j + 2 < spans.len and spans[j+1].kind == skCode and
         isNewlineWithIndent(spans[j+1].text, indent) and
         spans[j+2].kind == skComment and
         spans[j+2].commentKind == targetSpan.commentKind and
         spans[j+2].indent == indent:
        j += 2
      else:
        break
    else:
      break

  consumedCount = (j - startIdx) + 1

  # If only 1 line, format simply
  if rawLines.len == 1:
    return formatSingleLineCommentSpan(targetSpan, config)

  # Multi-line comment block: format with markdown rules
  let contentWidth = max(20, config.maxWidth - indent.len - prefix.len - 1)
  let formattedLines = formatLinesMarkdown(rawLines, contentWidth, prefix)

  var res = ""
  for idx, fl in formattedLines:
    if idx > 0:
      res.add("\n" & indent)
    res.add(prefix & (if fl.len > 0: " " & fl else: ""))
  res

proc formatSource*(src: string, config: FormatConfig): string =
  ## Main entrypoint: Formats comments in `src` while leaving code 100% untouched.
  let spans = scanSource(src)
  result = ""

  var i = 0
  while i < spans.len:
    let span = spans[i]
    if span.kind == skCode:
      result.add(span.text)
      i += 1
      continue

    # Comment span handling
    let isDoc = span.commentKind in {ckDocLine, ckDocBlock}
    let shouldFormat = (isDoc and config.formatDocComments) or (not isDoc and config.formatRegularComments)

    if not shouldFormat:
      result.add(span.text)
      i += 1
      continue

    if span.commentKind in {ckBlock, ckDocBlock}:
      result.add(formatBlockCommentSpan(span, config))
      i += 1
      continue

    # Single line comments: check if consecutive lines form a block
    var consumed = 1
    result.add(formatContiguousLineComments(spans, i, consumed, config))
    i += consumed

# ------------------------------------------------------------------------------
# CLI Driver
# ------------------------------------------------------------------------------

proc printHelp() =
  echo "nim-docfmt " & Version & " - Markdown Formatter & Linter for Nim Comments"
  echo "Usage: nim-docfmt [options] <files/directories...>"
  echo ""
  echo "Options:"
  echo "  -c, --check          Check if files are formatted (exit 1 if changes needed)"
  echo "  -w, --write          Write formatted changes in-place to source files"
  echo "  -d, --diff           Display unified diffs of formatted comments"
  echo "  --max-width:N        Target column width for comment wrapping (default: 80)"
  echo "  --comments:on|off    Format regular comments (# and #[...]#) (default: on)"
  echo "  --doc:on|off         Format doc comments (## and ##[...]#) (default: on)"
  echo "  -v, --version        Show version and exit"
  echo "  -h, --help           Show this help message and exit"

proc main*() =
  var config = FormatConfig(
    maxWidth: DefaultMaxWidth,
    formatRegularComments: true,
    formatDocComments: true,
    checkOnly: false,
    diffOnly: false,
    writeInPlace: false
  )

  var targetPaths: seq[string] = @[]
  var p = initOptParser()

  for kind, key, val in p.getopt():
    case kind
    of cmdArgument:
      targetPaths.add(key)
    of cmdLongOption, cmdShortOption:
      case key.normalize()
      of "c", "check":
        config.checkOnly = true
      of "w", "write":
        config.writeInPlace = true
      of "d", "diff":
        config.diffOnly = true
      of "max-width", "width":
        config.maxWidth = parseInt(val)
      of "comments":
        config.formatRegularComments = (val.normalize() != "off")
      of "doc":
        config.formatDocComments = (val.normalize() != "off")
      of "v", "version":
        echo "nim-docfmt " & Version
        quit(0)
      of "h", "help":
        printHelp()
        quit(0)
      else:
        stderr.writeLine("Error: Unknown option '--" & key & "'")
        quit(1)
    of cmdEnd:
      discard

  if targetPaths.len == 0:
    printHelp()
    quit(0)

  # Collect all .nim and .nims files
  var filesToProcess: seq[string] = @[]
  for path in targetPaths:
    if fileExists(path):
      filesToProcess.add(path)
    elif dirExists(path):
      for f in walkDirRec(path):
        if f.endsWith(".nim") or f.endsWith(".nims") or f.endsWith(".nimble"):
          filesToProcess.add(f)
    else:
      stderr.writeLine("Warning: Path not found: " & path)

  var hasUnformattedFiles = false

  for file in filesToProcess:
    let orig = readFile(file)
    let formatted = formatSource(orig, config)

    if orig != formatted:
      hasUnformattedFiles = true
      if config.checkOnly:
        echo "Needs formatting: " & file
      elif config.writeInPlace:
        writeFile(file, formatted)
        echo "Formatted: " & file
      elif config.diffOnly:
        echo "--- " & file & " (original)"
        echo "+++ " & file & " (formatted)"
        echo "Diff detected in comments."
      else:
        # Default stdout mode when single file
        if filesToProcess.len == 1:
          stdout.write(formatted)
        else:
          echo "Needs formatting: " & file

  if config.checkOnly and hasUnformattedFiles:
    quit(1)

when isMainModule:
  main()
