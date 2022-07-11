--[[
    4G-Tracker
    （一款使用 4G DTU 制作的 APRS Tracker，by BG4UVR 2022.6.2）
    开源网址：
    https://gitee.com/bg4uvr/LTE-Tracker
    https://github.com/bg4uvr/4G-Tracker
]] -- 4G-Tracker
local GPS_KIND_INFO_FILE = "/GPSKINDINFO.txt"
local UART_ID = 3
local rdBuf = ""
local gpsKind = ""
local gpsLib, agpsLib = "", ""
local uartBaudrate = 115200
local uartDatabits, uartParity, uartStopbits = 8, uart.PAR_NONE, uart.STOP_1

function writeCmd(cmd, isFull)
    local tmp = cmd
    if not isFull then
        tmp = 0
        for i = 2, cmd:len() - 1 do
            tmp = bit.bxor(tmp, cmd:byte(i))
        end
        tmp = cmd .. (string.format("%02X", tmp)):upper() .. "\r\n"
    end
    uart.write(UART_ID, tmp)
    log.info("autoGPS.writeCmd", tmp)
end

local function parse(data)
    if not data then
        return
    end
    local tInfo = {{
        keyWord = "UC6226",
        kind = "530H"
    }, {
        keyWord = "GOKE",
        kind = "530"
    }, {
        keyWord = "GK",
        kind = "530"
    }, {
        keyWord = "URANUS5",
        kind = "530Z"
    }, {
        keyWord = "ANTENNA",
        kind = "530Z"
    }}

    for i = 1, #tInfo do
        if data:match(tInfo[i].keyWord) then
            gpsKind = tInfo[i].kind
            log.info("autoGPS.parse", gpsKind)
            uart.close(UART_ID)
            sys.publish("GPS_KIND", gpsKind)
            return true, ""
        end
    end
    return false, data
end

local function proc(data)
    if not data or string.len(data) == 0 then
        return
    end
    rdBuf = rdBuf .. data
    local result, unproc
    unproc = rdBuf
    while true do
        result, unproc = parse(unproc)
        if not unproc or unproc == "" or not result then
            break
        end
    end
    rdBuf = unproc or ""
end

local function read()
    local data = ""
    while true do
        data = uart.read(UART_ID, "*l")
        if not data or string.len(data) == 0 then
            break
        end
        proc(data)
    end
end

local function writeOk()
    log.info("autoGPS.writeOk")
end

local function writeKindCmd()
    if string.len(gpsKind) == 0 then
        writeCmd("$PDTINFO\r\n", true) -- 530H
        writeCmd("$PGKC462*") -- 530
        writeCmd("$PCAS06,0*") -- 530Z
    elseif gpsKind == "530Z" then
        writeCmd("$PCAS06,0*")
    elseif gpsKind == "530H" then
        writeCmd("$PDTINFO\r\n", true)
    elseif gpsKind == "530" then
        writeCmd("$PGKC462*")
    end
end

local function uartBaudrateTest()
    if string.len(gpsKind) == 0 then
        uartBaudrate = uartBaudrate == 115200 and 9600 or 115200
        uart.close(UART_ID)
        rdBuf = ""
        uart.setup(UART_ID, uartBaudrate, uartDatabits, uartParity, uartStopbits)
        log.info("autoGPS.uartBaudrateTest", uartBaudrate)
    end
end

local function init()
    if string.find(rtos.get_version(), "RDA8910") then
        pmd.ldoset(15, pmd.LDO_VIBR)
    else
        pmd.ldoset(7, pmd.LDO_VCAM)
    end
    rtos.sys32k_clk_out(1)
    uart.on(UART_ID, "sent", writeOk)
    uart.on(UART_ID, "receive", read)
    uart.setup(UART_ID, uartBaudrate, uartDatabits, uartParity, uartStopbits)
end

local function loadLib(keyword)
    if keyword == "530" then
        gpsLib = require "gps"
        agpsLib = require "agps"
    elseif keyword == "530Z" then
        gpsLib = require "gpsZkw"
        agpsLib = require "agpsZkw"
    elseif keyword == "530H" then
        gpsLib = require "gpsHxxt"
        agpsLib = require "agpsHxxt"
    end
    if type(gpsLib) == "table" and type(gpsLib.init) == "fucntion" then
        gpsLib.init()
    end
    if type(agpsLib) == "table" and type(agpsLib.init) == "fucntion" then
        agpsLib.init()
    end
end

local function autoClose()
    uart.close(UART_ID)
    if string.find(rtos.get_version(), "RDA8910") then
        pmd.ldoset(0, pmd.LDO_VIBR)
    else
        pmd.ldoset(0, pmd.LDO_VCAM)
    end
    rtos.sys32k_clk_out(0)
end

local function selfAdapt()
    if io.exists(GPS_KIND_INFO_FILE) then
        local gpsKindInfo = io.readFile(GPS_KIND_INFO_FILE)
        log.info("autoGPS.task", "gps kind info", gpsKindInfo)

        if string.find(gpsKindInfo, "530Z") then
            gpsKind = "530Z"
        elseif string.find(gpsKindInfo, "530H") then
            gpsKind = "530H"
        else
            gpsKind = "530"
        end
        if string.find(gpsKindInfo, "9600") then
            uartBaudrate = 9600
        elseif string.find(gpsKindInfo, "115200") then
            uartBaudrate = 115200
        else
            log.warn("autoGPS.task", "invalid uartBaudrate")
        end
        init()
        writeKindCmd()
        local result, data = sys.waitUntil("GPS_KIND", 2000)
        if result then
            autoClose()
            loadLib(gpsKind)
            sys.publish("AUTOGPS_READY", gpsLib, agpsLib, gpsKind, uartBaudrate)
            rdBuf = ""
        else
            log.warn("autoGPS.task", "gps kind of history data err")
            sys.publish("GPS_WORK_ABNORMAL_IND")
            autoClose()
            return false
        end
    else
        rdBuf = ""
        init()
        while true do
            writeKindCmd()
            local result, data = sys.waitUntil("GPS_KIND", 2000)
            if result then
                autoClose()
                loadLib(data)
                io.writeFile(GPS_KIND_INFO_FILE, gpsKind .. tostring(uartBaudrate))
                sys.publish("AUTOGPS_READY", gpsLib, agpsLib, gpsKind, uartBaudrate)
                rdBuf = nil
                break
            else
                uartBaudrateTest()
            end
            sys.wait(100)
        end
    end
end

local coSelfAdapt = sys.taskInit(selfAdapt)

sys.subscribe("GPS_WORK_ABNORMAL_IND", function()
    log.info("autoGPS.GPS_WORK_ABNORMAL_IND", not coSelfAdapt or coroutine.status(coSelfAdapt) == "dead")
    if not coSelfAdapt or coroutine.status(coSelfAdapt) == "dead" then
        os.remove(GPS_KIND_INFO_FILE)
        if type(gpsLib) == "table" and type(gpsLib.unInit) == "function" then
            gpsLib.unInit()
        end
        if type(agpsLib) == "table" and type(agpsLib.unInit) == "function" then
            agpsLib.unInit()
        end
        gpsKind, gpsLib, agpsLib = "", "", ""
        coSelfAdapt = sys.taskInit(selfAdapt)
    end
end)
