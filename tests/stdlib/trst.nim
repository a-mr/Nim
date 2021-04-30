discard """
  output: '''

[Suite] RST indentation

[Suite] RST include directive

[Suite] RST escaping

[Suite] RST inline markup
'''
"""

# tests for rst module

import ../../lib/packages/docutils/rstgen
import ../../lib/packages/docutils/rst
import ../../lib/packages/docutils/rstast
import unittest, strutils
import std/private/miscdollars
import os

proc toAst(input: string,
            rstOptions: RstParseOptions = {roSupportMarkdown, roNimFile},
            error: ref string = nil,
            warnings: ref seq[string] = nil): string =
  ## If `error` is nil then no errors should be generated.
  ## The same goes for `warnings`.
  proc testMsgHandler(filename: string, line, col: int, msgkind: MsgKind,
                      arg: string) =
    let mc = msgkind.whichMsgClass
    let a = $msgkind % arg
    var message: string
    toLocation(message, filename, line, col + ColRstOffset)
    message.add " $1: $2" % [$mc, a]
    if mc == mcError:
      doAssert error != nil, "unexpected RST error '" & message & "'"
      error[] = message
      # we check only first error because subsequent ones may be meaningless
      raise newException(EParseError, message)
    else:
      doAssert warnings != nil, "unexpected RST warning '" & message & "'"
      warnings[].add message
  try:
    const filen = "input"

    proc myFindFile(filename: string): string =
      # we don't find any files in online mode:
      result = ""

    var dummyHasToc = false
    var rst = rstParse(input, filen, line=LineRstInit, column=ColRstInit,
                       dummyHasToc, rstOptions, myFindFile, testMsgHandler)
    result = renderRstToStr(rst)
  except EParseError:
    discard

suite "RST indentation":
  test "nested bullet lists":
    let input = dedent """
      * - bullet1
        - bullet2
      * - bullet3
        - bullet4
      """
    let output = input.toAst
    check(output == dedent"""
      rnBulletList
        rnBulletItem
          rnBulletList
            rnBulletItem
              rnInner
                rnLeaf  'bullet1'
            rnBulletItem
              rnInner
                rnLeaf  'bullet2'
        rnBulletItem
          rnBulletList
            rnBulletItem
              rnInner
                rnLeaf  'bullet3'
            rnBulletItem
              rnInner
                rnLeaf  'bullet4'
      """)

  test "nested markup blocks":
    let input = dedent"""
      #) .. Hint:: .. Error:: none
      #) .. Warning:: term0
                        Definition0
      #) some
         paragraph1
      #) term1
           Definition1
         term2
           Definition2
    """
    check(input.toAst == dedent"""
      rnEnumList  labelFmt=1)
        rnEnumItem
          rnAdmonition  adType=hint
            [nil]
            [nil]
            rnAdmonition  adType=error
              [nil]
              [nil]
              rnLeaf  'none'
        rnEnumItem
          rnAdmonition  adType=warning
            [nil]
            [nil]
            rnDefList
              rnDefItem
                rnDefName
                  rnLeaf  'term0'
                rnDefBody
                  rnInner
                    rnLeaf  'Definition0'
        rnEnumItem
          rnInner
            rnLeaf  'some'
            rnLeaf  ' '
            rnLeaf  'paragraph1'
        rnEnumItem
          rnDefList
            rnDefItem
              rnDefName
                rnLeaf  'term1'
              rnDefBody
                rnInner
                  rnLeaf  'Definition1'
            rnDefItem
              rnDefName
                rnLeaf  'term2'
              rnDefBody
                rnInner
                  rnLeaf  'Definition2'
      """)

  test "code-block parsing":
    let input1 = dedent"""
      .. code-block:: nim
          :test: "nim c $1"
      
        template additive(typ: typedesc) =
          discard
      """
    let input2 = dedent"""
      .. code-block:: nim
        :test: "nim c $1"
      
        template additive(typ: typedesc) =
          discard
      """
    let input3 = dedent"""
      .. code-block:: nim
         :test: "nim c $1"
         template additive(typ: typedesc) =
           discard
      """
    let inputWrong = dedent"""
      .. code-block:: nim
       :test: "nim c $1"
      
         template additive(typ: typedesc) =
           discard
      """
    let ast = dedent"""
      rnCodeBlock
        rnDirArg
          rnLeaf  'nim'
        rnFieldList
          rnField
            rnFieldName
              rnLeaf  'test'
            rnFieldBody
              rnInner
                rnLeaf  '"'
                rnLeaf  'nim'
                rnLeaf  ' '
                rnLeaf  'c'
                rnLeaf  ' '
                rnLeaf  '$'
                rnLeaf  '1'
                rnLeaf  '"'
          rnField
            rnFieldName
              rnLeaf  'default-language'
            rnFieldBody
              rnLeaf  'Nim'
        rnLiteralBlock
          rnLeaf  'template additive(typ: typedesc) =
        discard'
      """
    check input1.toAst == ast
    check input2.toAst == ast
    check input3.toAst == ast
    # "template..." should be parsed as a definition list attached to ":test:":
    check inputWrong.toAst != ast

suite "RST include directive":
  test "Include whole":
    "other.rst".writeFile("**test1**")
    let input = ".. include:: other.rst"
    doAssert "<strong>test1</strong>" == rstTohtml(input, {}, defaultConfig())
    removeFile("other.rst")

  test "Include starting from":
    "other.rst".writeFile("""
And this should **NOT** be visible in `docs.html`
OtherStart
*Visible*
""")

    let input = """
.. include:: other.rst
             :start-after: OtherStart
"""
    doAssert "<em>Visible</em>" == rstTohtml(input, {}, defaultConfig())
    removeFile("other.rst")

  test "Include everything before":
    "other.rst".writeFile("""
*Visible*
OtherEnd
And this should **NOT** be visible in `docs.html`
""")

    let input = """
.. include:: other.rst
             :end-before: OtherEnd
"""
    doAssert "<em>Visible</em>" == rstTohtml(input, {}, defaultConfig())
    removeFile("other.rst")


  test "Include everything between":
    "other.rst".writeFile("""
And this should **NOT** be visible in `docs.html`
OtherStart
*Visible*
OtherEnd
And this should **NOT** be visible in `docs.html`
""")

    let input = """
.. include:: other.rst
             :start-after: OtherStart
             :end-before: OtherEnd
"""
    doAssert "<em>Visible</em>" == rstTohtml(input, {}, defaultConfig())
    removeFile("other.rst")


  test "Ignore premature ending string":
    "other.rst".writeFile("""

OtherEnd
And this should **NOT** be visible in `docs.html`
OtherStart
*Visible*
OtherEnd
And this should **NOT** be visible in `docs.html`
""")

    let input = """
.. include:: other.rst
             :start-after: OtherStart
             :end-before: OtherEnd
"""
    doAssert "<em>Visible</em>" == rstTohtml(input, {}, defaultConfig())
    removeFile("other.rst")

suite "RST escaping":
  test "backspaces":
    check("""\ this""".toAst == dedent"""
      rnLeaf  'this'
      """)

    check("""\\ this""".toAst == dedent"""
      rnInner
        rnLeaf  '\'
        rnLeaf  ' '
        rnLeaf  'this'
      """)

    check("""\\\ this""".toAst == dedent"""
      rnInner
        rnLeaf  '\'
        rnLeaf  'this'
      """)

    check("""\\\\ this""".toAst == dedent"""
      rnInner
        rnLeaf  '\'
        rnLeaf  '\'
        rnLeaf  ' '
        rnLeaf  'this'
      """)

suite "RST inline markup":
  test "end-string has repeating symbols":
    check("*emphasis content****".toAst == dedent"""
      rnEmphasis
        rnLeaf  'emphasis'
        rnLeaf  ' '
        rnLeaf  'content'
        rnLeaf  '***'
      """)

    check("""*emphasis content\****""".toAst == dedent"""
      rnEmphasis
        rnLeaf  'emphasis'
        rnLeaf  ' '
        rnLeaf  'content'
        rnLeaf  '*'
        rnLeaf  '**'
      """)  # exact configuration of leafs with * is not really essential,
            # only total number of * is essential

    check("**strong content****".toAst == dedent"""
      rnStrongEmphasis
        rnLeaf  'strong'
        rnLeaf  ' '
        rnLeaf  'content'
        rnLeaf  '**'
      """)

    check("""**strong content*\****""".toAst == dedent"""
      rnStrongEmphasis
        rnLeaf  'strong'
        rnLeaf  ' '
        rnLeaf  'content'
        rnLeaf  '*'
        rnLeaf  '*'
        rnLeaf  '*'
      """)

    check("``lit content`````".toAst == dedent"""
      rnInlineLiteral
        rnLeaf  'lit'
        rnLeaf  ' '
        rnLeaf  'content'
        rnLeaf  '```'
      """)


  test """interpreted text can be ended with \` """:
    let output = (".. default-role:: literal\n" & """`\``""").toAst
    check(output.endsWith """
  rnParagraph
    rnInlineLiteral
      rnLeaf  '`'""" & "\n")

    let output2 = """`\``""".toAst
    check(output2 == dedent"""
      rnInlineCode
        rnDirArg
          rnLeaf  'nim'
        [nil]
        rnLiteralBlock
          rnLeaf  '`'
      """)

    let output3 = """`proc \`+\``""".toAst
    check(output3 == dedent"""
      rnInlineCode
        rnDirArg
          rnLeaf  'nim'
        [nil]
        rnLiteralBlock
          rnLeaf  'proc `+`'
      """)

  test """inline literals can contain \ anywhere""":
    check("""``\``""".toAst == dedent"""
      rnInlineLiteral
        rnLeaf  '\'
      """)

    check("""``\\``""".toAst == dedent"""
      rnInlineLiteral
        rnLeaf  '\'
        rnLeaf  '\'
      """)

    check("""``\```""".toAst == dedent"""
      rnInlineLiteral
        rnLeaf  '\'
        rnLeaf  '`'
      """)

    check("""``\\```""".toAst == dedent"""
      rnInlineLiteral
        rnLeaf  '\'
        rnLeaf  '\'
        rnLeaf  '`'
      """)

    check("""``\````""".toAst == dedent"""
      rnInlineLiteral
        rnLeaf  '\'
        rnLeaf  '`'
        rnLeaf  '`'
      """)

  test "references with _ at the end":
    check(dedent"""
      .. _lnk: https

      lnk_""".toAst ==
      dedent"""
        rnHyperlink
          rnInner
            rnLeaf  'lnk'
          rnInner
            rnLeaf  'https'
      """)

  test "not a hyper link":
    check(dedent"""
      .. _lnk: https

      lnk___""".toAst ==
      dedent"""
        rnInner
          rnLeaf  'lnk'
          rnLeaf  '___'
      """)

  test "no punctuation in the end of a standalone URI is allowed":
    check(dedent"""
        [see (http://no.org)], end""".toAst ==
      dedent"""
        rnInner
          rnLeaf  '['
          rnLeaf  'see'
          rnLeaf  ' '
          rnLeaf  '('
          rnStandaloneHyperlink
            rnLeaf  'http'
            rnLeaf  ':'
            rnLeaf  '//'
            rnLeaf  'no'
            rnLeaf  '.'
            rnLeaf  'org'
          rnLeaf  ')'
          rnLeaf  ']'
          rnLeaf  ','
          rnLeaf  ' '
          rnLeaf  'end'
        """)

    # but `/` at the end is OK
    check(
      dedent"""
        See http://no.org/ end""".toAst ==
      dedent"""
        rnInner
          rnLeaf  'See'
          rnLeaf  ' '
          rnStandaloneHyperlink
            rnLeaf  'http'
            rnLeaf  ':'
            rnLeaf  '//'
            rnLeaf  'no'
            rnLeaf  '.'
            rnLeaf  'org'
            rnLeaf  '/'
          rnLeaf  ' '
          rnLeaf  'end'
        """)
