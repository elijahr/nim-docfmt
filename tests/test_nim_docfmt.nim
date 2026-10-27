import unittest
import nim_docfmt

suite "nim_docfmt":
  test "hello returns expected greeting":
    check hello() == "hello from nim_docfmt"

  test "version present":
    check projectVersion == "0.0.1"
