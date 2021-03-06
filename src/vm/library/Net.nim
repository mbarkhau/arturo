######################################################
# Arturo
# Programming Language + Bytecode VM compiler
# (c) 2019-2020 Yanis Zafirópulos
#
# @file: library/Net.nim
######################################################

#=======================================
# Libraries
#=======================================

import vm/env, vm/stack, vm/value
import utils

#=======================================
# Methods
#=======================================

template Mail*():untyped =
    require(opMail)

    let recipient = x.s
    let message = y.d
    let config = z.d

    var mesg = createMessage(message["title"].s,
                        message["content"].s,
                        @[recipient])
    let smtpConn = newSmtp(useSsl = true, debug=true)
    smtpConn.connect(config["server"].s, Port 465)
    smtpConn.auth(config["username"].s, config["password"].s)
    smtpConn.sendmail(config["username"].s, @[recipient], $mesg)

template Download*():untyped =
    require(opDownload)

    let path = x.s

    var target: string

    if (let aAs = popAttr("as"); aAs!=VNULL):
        target = aAs.s
    else:
        target = extractFilename(path)

    var client = newHttpClient()
    client.downloadFile(path,target)


template Serve*():untyped =
    when not defined(VERBOSE):
        require(opServe)

        let routes = x

        var port = 18966
        var verbose = (popAttr("verbose") != VNULL)
        if (let aPort = popAttr("port"); aPort != VNULL):
            port = aPort.i

        var server = newAsyncHttpServer()

        proc handler(req: Request) {.async,gcsafe.} =
            if verbose:
                stdout.write fgMagenta & "<< [" & req.protocol[0] & "] " & req.hostname & ": " & fgWhite & ($(req.reqMethod)).replace("Http").toUpperAscii() & " " & req.url.path
                if req.url.query!="":
                    stdout.write "?" & req.url.query

                stdout.write "\n"
                stdout.flushFile()

            # echo "body: " & req.body

            # echo "========"
            # for k,v in pairs(req.headers):
            #     echo k & " => " & v
            # echo "========"

            var status = 200
            var headers = newHttpHeaders()

            var body: string

            var routeFound = ""
            for k in routes.d.keys:
                let route = req.url.path.match(nre.re(k & "$"))

                if not route.isNone:

                    var args: ValueArray = @[]

                    let captures = route.get.captures.toTable

                    for group,capture in captures:
                        args.add(newString(group))

                    if req.reqMethod==HttpPost:
                        for d in decodeData(req.body):
                            args.add(newString(d[0]))

                        for d in (toSeq(decodeData(req.body))).reversed:
                            stack.push(newString(d[1]))

                    for capture in (toSeq(pairs(captures))).reversed:
                        stack.push(newString(capture[1]))

                    try:
                        discard execBlock(routes.d[k], execInParent=true, useArgs=true, args=args)
                    except:
                        let e = getCurrentException()
                        echo "Something went wrong." & e.msg
                    body = stack.pop().s
                    routeFound = k
                    break

            if routeFound=="":
                let subpath = joinPath(env.currentPath(),req.url.path)
                if fileExists(subpath):
                    body = readFile(subpath)
                else:
                    status = 404
                    body = "page not found!"

            if verbose:
                echo fgGreen & ">> [" & $(status) & "] " & routeFound & fgWhite

            await req.respond(status.HttpCode, body, headers)

        try:
            echo ":: Starting server on port " & $(port) & "...\n"
            waitFor server.serve(port = port.Port, callback = handler, address = "")
        except:
            let e = getCurrentException()
            echo "Something went wrong." & e.msg
            server.close()
