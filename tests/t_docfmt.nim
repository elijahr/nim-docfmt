import std/[unittest, strutils]
import ../src/nim_docfmt

suite "nim-docfmt Test Suite":

  test "Scanner reproduces original source byte-identical":
    let original = """
import std/strutils

# This is a regular comment
proc add(a, b: int): int =
  ## Adds two integers together.
  ## Returns their arithmetic sum.
  result = a + b # inline comment

const Str = "hello # not a comment"
const Triple = """ & "\"\"\"\nmulti # line\n\"\"\"" & """
const Raw = r"raw # string"

#[
  Arbitrary newlines
  and block text here.
]#

proc hello() =
  ##[
    Doc block comment
    with multiple lines
  ]##
  discard
"""
    let spans = scanSource(original)
    var reconstructed = ""
    for s in spans:
      reconstructed.add(s.text)

    check reconstructed == original

  test "Nested block comments are scanned correctly":
    let src = """
#[ Outer block comment
  #[ Inner nested comment ]#
  Back to outer
]#
var x = 42
"""
    let spans = scanSource(src)
    var foundBlock = false
    for s in spans:
      if s.commentKind == ckBlock:
        foundBlock = true
        check s.text.startsWith("#[")
        check s.text.endsWith("]#")
        check "Inner nested comment" in s.text
    check foundBlock

  test "Code formatting is 100% untouched outside comments":
    let uglyCode = """
proc   ugly_spacing  (  x  :int,y:  int   )   :int=
    let   z=x+y
    return    z
"""
    let config = FormatConfig(
      maxWidth: 80,
      formatRegularComments: true,
      formatDocComments: true
    )
    let formatted = formatSource(uglyCode, config)
    check formatted == uglyCode

  test "Block comment markdown formatting":
    let src = """
#[
This is a long block comment that contains a sentence that definitely exceeds fifty characters and needs to be wrapped.
]#
"""
    let config = FormatConfig(
      maxWidth: 50,
      formatRegularComments: true,
      formatDocComments: true
    )
    let formatted = formatSource(src, config)
    check "#[" in formatted
    check "]#" in formatted
    # Check that lines inside are wrapped
    for line in formatted.splitLines():
      check line.len <= 55

  test "Fenced code blocks inside comments are preserved verbatim":
    let src = """
## Here is an example of code:
## ```nim
## let a = 12345678901234567890123456789012345678901234567890
## let b = "do not wrap this line inside code fence"
## ```
## And text resumes here.
"""
    let config = FormatConfig(
      maxWidth: 40,
      formatRegularComments: true,
      formatDocComments: true
    )
    let formatted = formatSource(src, config)
    check "let a = 12345678901234567890123456789012345678901234567890" in formatted

  test "Markdown lists preserve bullets and structure":
    let src = """
## Features:
## - Item one with some description text
## - Item two with another description
## 1. Numbered step first
## 2. Numbered step second
"""
    let config = FormatConfig(
      maxWidth: 80,
      formatRegularComments: true,
      formatDocComments: true
    )
    let formatted = formatSource(src, config)
    check "- Item one with some description text" in formatted
    check "1. Numbered step first" in formatted
