######################################################
# Arturo
# Programming Language + Bytecode VM compiler
# (c) 2019-2020 Yanis Zafirópulos
#
# @file: translator/parse.nim
######################################################

#=======================================
# Libraries
#=======================================

import lexbase, streams, strformat, strutils, unicode

import vm/value

when defined(BENCHMARK) or defined(VERBOSE):
    import utils

#=======================================
# Types
#=======================================

type
    ParserStatus* = enum
        allOK
        invalidTokenError
        missingClosingBracketError
        unterminatedStringError
        unrecognizedEscapeSequence
        newlineInQuotedString
        emptyLiteralError
        emptyDatatypeError

    Parser* = object of BaseLexer
        value*: string
        values*: ValueArray
        symbol*: SymbolKind
        status*: ParserStatus

#=======================================
# Constants
#=======================================

const
    LBracket                    = '['
    RBracket                    = ']'
    LParen                      = '('
    RParen                      = ')'

    Quote                       = '"'
    Colon                       = ':'
    Semicolon                   = ';'
    Dot                         = '.'
    Tick                        = '\''
    BackTick                    = '`'

    Backslash                   = '\\'
    Dash                        = '-'

    CR                          = '\c'
    LF                          = '\L'
    EOF                         = '\0'
    
    Tab                         = '\t'
    Whitespace                  = {' ', Tab}

    PermittedNumbers_Start      = {'0'..'9'}
    Symbols                     = {'~', '!', '@', '#', '$', '%', '^', '&', '*', '-', '_', '=', '+', '<', '>', '/', '\\', '|', '{', '}'}
    Letters                     = {'a'..'z', 'A'..'Z'}
    PermittedIdentifiers_Start  = Letters
    PermittedIdentifiers_In     = Letters + {'0'..'9', '?'}

    Empty                       = ""

    ParserStatusString: array[ParserStatus, string] = [
        "No error.",
        "Invalid token found.",
        "Missing closing bracket.",
        "Unterminated string.",
        "Unrecognized escape sequence.",
        "Newline in quoted string.",
        "Empty literal.",
        "Empty datatype."
    ]

#=======================================
# Helpers
#=======================================

template skip(p: var Parser) =
  var pos = p.bufpos
  while true:
    case p.buf[pos]
    of Semicolon:
        inc(pos)
        while true:
            case p.buf[pos]:
                of EOF:
                    break
                of CR:
                    pos = lexbase.handleCR(p, pos)
                    break
                of LF:
                    pos = lexbase.handleLF(p, pos)
                    break
                else:
                    inc(pos)
    of Whitespace:
        inc(pos)
    of CR:
        pos = lexbase.handleCR(p, pos)
    of LF:
        pos = lexbase.handleLF(p, pos)
        # if p.buf[pos] == Tab:
        #     echo "next one is tab!"
    else:
        break
    
    p.bufpos = pos

template parseString(p: var Parser, stopper: char = Quote) =
    var pos = p.bufpos + 1
    var inCode = false

    while true:
        case p.buf[pos]:
            of EOF: 
                p.status = unterminatedStringError
                break
            of stopper:
                inc(pos)
                break
            of '|':
                add(p.value, '|')
                inc(pos)
                inCode = not inCode
            of '\\':
                if not inCode:
                    case p.buf[pos+1]
                        of '\\', '"', '\'', '/':
                            add(p.value, p.buf[pos+1])
                            inc(pos, 2)
                        of 'a':
                            add(p.value, '\a')
                            inc(pos, 2)
                        of 'b':
                            add(p.value, '\b')
                            inc(pos, 2)
                        of 'e':
                            add(p.value, '\e')
                            inc(pos, 2)
                        of 'f':
                            add(p.value, '\f')
                            inc(pos, 2)
                        of 'n':
                            add(p.value, '\L')
                            inc(pos, 2)
                        of 'r':
                            add(p.value, '\C')
                            inc(pos, 2)
                        of 't':
                            add(p.value, '\t')
                            inc(pos, 2)
                        of 'v':
                            add(p.value, '\v')
                            inc(pos, 2)
                        else:
                            p.status = unrecognizedEscapeSequence
                            return
                else:
                    add(p.value, p.buf[pos])
                    inc(pos)
            of CR:
                p.status = newlineInQuotedString
                return
            of LF:
                p.status = newlineInQuotedString
                return
            else:
                add(p.value, p.buf[pos])
                inc(pos)

    p.bufpos = pos

template parseMultilineString(p: var Parser) =
    var pos = p.bufpos + 1
    while true:
        case p.buf[pos]:
            of EOF: 
                p.status = unterminatedStringError
                break
            of Dash:
                if p.buf[pos+1]==Dash and p.buf[pos+2]==Dash:
                    inc(pos,3)
                    break
                else:
                    inc(pos)
                    add(p.value, '-')
            of CR:
                pos = lexbase.handleCR(p, pos)
                add(p.value, CR)
            of LF:
                pos = lexbase.handleLF(p, pos)
                add(p.value, LF)
            else:
                add(p.value, p.buf[pos])
                inc(pos)

    p.bufpos = pos

template parseFullLineString(p: var Parser) =
    var pos = p.bufpos + 2
    while true:
        case p.buf[pos]:
            of EOF: 
                break
            of CR:
                pos = lexbase.handleCR(p, pos)
                break
            of LF:
                pos = lexbase.handleLF(p, pos)
                break
            else:
                add(p.value, p.buf[pos])
                inc(pos)

    p.bufpos = pos

template parseIdentifier(p: var Parser) =
    var pos = p.bufpos
    add(p.value, p.buf[pos])
    inc(pos)
    while p.buf[pos] in PermittedIdentifiers_In:
        add(p.value, p.buf[pos])
        inc(pos)
    p.bufpos = pos

template parseNumber(p: var Parser) =
    var pos = p.bufpos
    # if p.buf[pos] == Minus:
    #     add(p.value, Minus)
    #     inc(pos)
    while p.buf[pos] in Digits:
        add(p.value, p.buf[pos])
        inc(pos)

    if p.buf[pos] == Dot:
        if p.buf[pos+1] == Dot:
            p.bufpos = pos
        else:
            add(p.value, Dot)
            inc(pos)
    
            while p.buf[pos] in Digits:
                add(p.value, p.buf[pos])
                inc(pos)
            p.bufpos = pos
    else:
        p.bufpos = pos

template parseAndAddSymbol(p: var Parser, topBlock: var Value) =
    var pos = p.bufpos
    var isSymbol = true
    case p.buf[pos]:
        of '~'  : p.symbol = tilde
        of '!'  : p.symbol = exclamation
        of '@'  : p.symbol = at
        of '#'  : p.symbol = sharp
        of '$'  : p.symbol = dollar
        of '%'  : p.symbol = percent
        of '^'  : p.symbol = caret
        of '&'  : p.symbol = ampersand
        of '*'  : p.symbol = asterisk
        of '_'  : p.symbol = underscore
        of '|'  : p.symbol = pipe
        of '{'  : p.symbol = leftcurly
        of '}'  : p.symbol = rightcurly
        of '/'  : 
            if p.buf[pos+1]=='/': inc(pos); p.symbol = doubleslash
            else: p.symbol = slash
        of '\\' : 
            if p.buf[pos+1]=='\\': inc(pos); p.symbol = doublebackslash
            else: p.symbol = backslash
        of '+'  : 
            if p.buf[pos+1]=='+': inc(pos); p.symbol = doubleplus
            else: p.symbol = plus
        of '-'  : 
            if p.buf[pos+1]=='>': inc(pos); p.symbol = arrowright
            elif p.buf[pos+1]=='-': 
                inc(pos)
                if p.buf[pos+1]=='-':
                    isSymbol = false
                    p.bufpos = pos+1
                    parseMultilineString(p)
                    if p.status != allOK: return nil
                    addChild(topBlock, newString(p.value,strip=true))
                else:
                    p.symbol = doubleminus
            else: p.symbol = minus
        of '=': 
            if p.buf[pos+1]=='>': inc(pos); p.symbol = thickarrowright
            elif p.buf[pos+1]=='<': inc(pos); p.symbol = equalless
            else: p.symbol = equal
        of '<':
            case p.buf[pos+1]:
                of '=': inc(pos); p.symbol = thickarrowleft
                of '-': inc(pos); p.symbol = arrowleft
                of '>': inc(pos); p.symbol = lessgreater
                of '<': inc(pos); p.symbol = doublearrowleft
                else: p.symbol = lessthan
        of '>':
            case p.buf[pos+1]:
                of '=': inc(pos); p.symbol = greaterequal
                of '>': inc(pos); p.symbol = doublearrowright
                else: p.symbol = greaterthan
        else: 
            discard # shouldn't reach here

    if isSymbol:
        inc(pos)
        p.bufpos = pos
        addChild(topBlock, newSymbol(p.symbol))

template parsePath(p: var Parser, root: Value) =
    p.values = @[root]

    while p.buf[p.bufpos]==Backslash:
        inc(p.bufpos)
        case p.buf[p.bufpos]:
            of PermittedIdentifiers_Start:
                setLen(p.value, 0)
                parseIdentifier(p)
                p.values.add(newLiteral(p.value))
            of PermittedNumbers_Start:
                setLen(p.value, 0)
                parseNumber(p)
                if Dot in p.value: p.values.add(newFloating(p.value))
                else: p.values.add(newInteger(p.value))
            else:
                break

template parseLiteral(p: var Parser) =
    var pos = p.bufpos
    inc(pos)
    while p.buf[pos] in PermittedIdentifiers_In:
        add(p.value, p.buf[pos])
        inc(pos)
    p.bufpos = pos

proc parseBlock*(p: var Parser, level: int, isDeferred: bool = true): Value {.inline.} =
    var topBlock: Value
    if isDeferred: topBlock = newBlock()
    else: topBlock = newInline()

    while true:
        setLen(p.value, 0)
        skip(p)

        case p.buf[p.bufpos]
            of EOF:
                if level!=0:
                    p.status = missingClosingBracketError
                    return nil
                else:
                    break
            of Quote:
                parseString(p)
                if p.status != allOK: return nil

                addChild(topBlock, newString(p.value))
            of BackTick:
                parseString(p, stopper=BackTick)
                if p.status != allOK: return nil

                addChild(topBlock, newChar(p.value))
            of Colon:
                parseLiteral(p)
                if p.value == Empty: 
                    addChild(topBlock,newSymbol(colon))
                else:
                    addChild(topBlock, newType(p.value))
            of PermittedNumbers_Start:
                parseNumber(p)
                if Dot in p.value: addChild(topBlock, newFloating(p.value))
                else: addChild(topBlock, newInteger(p.value))
            of Symbols:
                parseAndAddSymbol(p,topBlock)
            of PermittedIdentifiers_Start:
                parseIdentifier(p)
                if p.buf[p.bufpos] == Colon:
                    inc(p.bufpos)
                    addChild(topBlock, newLabel(p.value))
                elif p.buf[p.bufpos] == Backslash:
                    if (p.buf[p.bufpos+1] in PermittedIdentifiers_Start) or 
                       (p.buf[p.bufpos+1] in PermittedNumbers_Start):
                        parsePath(p, newWord(p.value))
                        if p.buf[p.bufpos]==Colon:
                            inc(p.bufpos)
                            addChild(topBlock, newPathLabel(p.values))
                        else:
                            addChild(topBlock, newPath(p.values))
                    else:
                        inc(p.bufpos)
                        addChild(topBlock,newSymbol(backslash))
                else:
                    addChild(topBlock, newWord(p.value))
            of Tick:
                parseLiteral(p)
                if p.value == Empty: 
                    p.status = emptyLiteralError
                    return nil
                else:
                    addChild(topBlock, newLiteral(p.value))
            of Dot:
                if p.buf[p.bufpos+1] == Dot:
                    inc(p.bufpos)
                    inc(p.bufpos)
                    addChild(topBlock, newSymbol(ellipsis))
                else:
                    parseLiteral(p)
                    if p.buf[p.bufpos] == Colon:
                        inc(p.bufpos)
                        addChild(topBlock, newAttrLabel(p.value))
                    else:
                        addChild(topBlock, newAttr(p.value))
            of LBracket:
                inc(p.bufpos)
                var subblock = parseBlock(p,level+1)

                if p.status!=allOK: return nil
                else: addChild(topBlock, subblock)
            of RBracket:
                inc(p.bufpos)
                break
            of LParen:
                inc(p.bufpos)
                var subblock = parseBlock(p, level+1, isDeferred=false)
                
                if p.status!=allOK: return nil
                else: addChild(topBlock, subblock)
            of RParen:
                inc(p.bufpos)
                break
            of chr(194):
                if p.buf[p.bufpos+1]==chr(171): # got «
                    parseFullLineString(p)
                    if p.status != allOK: return nil
                    addChild(topBlock, newString(unicode.strip(p.value)))
                else:
                    inc(p.bufpos)
            else:
                inc(p.bufpos)

    return topBlock

#=======================================
# Methods
#=======================================

proc doParse*(input: string, isFile: bool = true): Value =
    var p: Parser

    # open stream

    if isFile:
        var stream = newFileStream(input)
        lexbase.open(p, stream)
    else:
        var stream = newStringStream(input)
        lexbase.open(p, stream)

    # initialize

    p.value = ""
    p.status = allOK

    # do parse
    
    let rootBlock = parseBlock(p, 0)

    # if everything went fine, return result

    if p.status==allOK:
        when defined(VERBOSE):
            showDebugHeader("Parse")
            rootBlock.dump(0,false)
            
        return rootBlock
    else:
        echo fmt("Error: {ParserStatusString[p.status]}")
        return nil
