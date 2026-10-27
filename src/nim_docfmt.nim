# nim_docfmt - Markdown formatter and linter for Nim comments and docstrings

const projectVersion* = "0.0.1"

const greetingMsg* = "hello from nim_docfmt"

proc hello*(): string =
  ## Returns standard project greeting string.
  greetingMsg

proc add*(a, b: int): int =
  ## Adds two integers.
  a + b
