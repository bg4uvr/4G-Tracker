--[[
    4G-Tracker
    （一款使用 4G DTU 制作的 APRS Tracker，by BG4UVR 2022.6.2）
    开源网址：
    https://gitee.com/bg4uvr/LTE-Tracker
    https://github.com/bg4uvr/4G-Tracker
]] -- 4G-Tracker
require "autoGPS"
require "socket"
local uartId = 3
local gpsFlag = false
local gpsData, gpsDataOld
local pointTime, beaconTime = 0, 0
local reason = 0
local cfg = {
    ["CALLSIGN"] = nil,
    ["PASSCODE"] = nil,
    ["SSID"] = "4G",
    ["SERVER"] = "china.aprs2.net",
    ["PORT"] = 14580,
    ["MICE"] = 0,
    ["TABLE"] = "/",
    ["SYMBOL"] = ">",
    ["BEACON"] = string.format("4G-Tracker ver%s https://github.com/bg4uvr/4G-Tracker", VERSION),
    ["BEACON_INTERVAL"] = 60,
    ["MIN_INTERVAL"] = 60,
    ["MIN_COURSE"] = 20,
    ["MIN_RUNSPD"] = 5,
    ["MAX_INTERVAL"] = 120,
    ["STOP_INTERVAL"] = 30,
    ["SMART_POINT"] = 1,
    ["POINT_INTERVAL"] = 60
}

local function gpsProcess()
    if not gps.isOpen() then
        gps.open(gps.DEFAULT, {
            tag = "4G-Tracker"
        })
        return
    elseif not gps.isFix() then
        return
    else
        local tLocation = gps.getLocation("DEGREE_MINUTE")
        local speedkm, speedknot = gps.getSpeed()
        gpsData = {
            ["lat"] = string.match(tLocation.lat, "(%d+%.%d%d)"),
            ["latType"] = tLocation.latType,
            ["lng"] = string.match(tLocation.lng, "(%d+%.%d%d)"),
            ["lngType"] = tLocation.lngType,
            ["course"] = gps.getCourse(),
            ["spd"] = speedknot,
            ["altM"] = gps.getAltitude(),
            ["altFeet"] = string.match(gps.getAltitude() * 3.2808399, "(%d+)")
        }
    end
end

local function courseDiff(new, old)
    if not new or not old or new > 359 or new < 0 or old >= 359 or old < 0 then
        return 0
    end
    local diff = math.abs(new - old)
    if diff > 180 then
        diff = 360 - diff
    end
    return diff
end

local function miceEncode(gpsPoint)
    local hexP = string.byte('P')
    local hex0 = string.byte('0')
    local lat = tonumber(gpsPoint.lat) * 100
    local micEbuf = string.char(lat / 100000 + hexP)
    micEbuf = micEbuf .. string.char(lat % 100000 / 10000 + hexP)
    micEbuf = micEbuf .. string.char(lat % 10000 / 1000 + hexP)
    if gpsPoint.latType == 'N' then
        micEbuf = micEbuf .. string.char(lat % 1000 / 100 + hexP)
    else
        micEbuf = micEbuf .. string.char(lat % 1000 / 100 + hex0)
    end
    if tonumber(gpsPoint.lng) >= 100 then
        micEbuf = micEbuf .. string.char(lat % 100 / 10 + hexP)
    else
        micEbuf = micEbuf .. string.char(lat % 100 / 10 + hex0)
    end
    if gpsPoint.lngType == 'W' then
        micEbuf = micEbuf .. string.char(lat % 10 + hexP)
    else
        micEbuf = micEbuf .. string.char(lat % 10 + hex0)
    end
    micEbuf = micEbuf .. ':`'
    local lng = gpsPoint.lng * 100
    local tmp = lng / 10000
    if tmp < 10 then
        micEbuf = micEbuf .. string.char(tmp + 88)
    elseif tmp < 100 then
        micEbuf = micEbuf .. string.char(tmp + 28)
    elseif tmp < 110 then
        micEbuf = micEbuf .. string.char(tmp + 8)
    else
        micEbuf = micEbuf .. string.char(tmp - 72)
    end
    tmp = lng % 10000 / 100
    if tmp < 10 then
        micEbuf = micEbuf .. string.char(tmp + 88)
    else
        micEbuf = micEbuf .. string.char(tmp + 28)
    end
    tmp = lng % 100
    micEbuf = micEbuf .. string.char(tmp + 28)
    tmp = gpsPoint.spd / 10
    if tmp < 20 then
        micEbuf = micEbuf .. string.char(tmp + 108)
    else
        micEbuf = micEbuf .. string.char(tmp + 28)
    end
    micEbuf = micEbuf .. string.char((gpsPoint.spd % 10 * 10 + gpsPoint.course / 100) + 32)
    micEbuf = micEbuf .. string.char(gpsPoint.course % 100 + 28)
    micEbuf = micEbuf .. cfg.SYMBOL
    micEbuf = micEbuf .. cfg.TABLE
    local alt = gpsPoint.altM + 10000
    micEbuf = micEbuf .. string.char(alt / (91 * 91) + 33)
    micEbuf = micEbuf .. string.char(alt % (91 * 91) / 91 + 33)
    micEbuf = micEbuf .. string.char(alt % 91 + 33)
    micEbuf = micEbuf .. '}'
    return micEbuf
end

local function aprsSend()
    if socket.isReady() then
        local socketClient = socket.tcp()
        for i = 0, 3 do
            if socketClient:connect(cfg.SERVER, cfg.PORT) then
                log.info("服务器", "APRS服务器已连接")
                local loginCmd = false
                local sourceCall
                if cfg.SSID == '0' then
                    sourceCall = cfg.CALLSIGN
                else
                    sourceCall = cfg.CALLSIGN .. '-' .. cfg.SSID
                end
                for timeout = 0, 3 do
                    local result, data = socketClient:recv(10000)
                    if result then
                        log.info("服务器消息", data)
                        if not loginCmd then
                            if (string.find(data, "aprsc") or string.find(data, "javAPRSSrvr")) then
                                socketClient:send(string.format("user %s pass %d vers 4G-Tracker %s\r\n", sourceCall,
                                    cfg.PASSCODE, VERSION))
                                loginCmd = true
                                log.info("服务器", "正在登录...")
                            end
                        else
                            if string.find(data, " verified") then
                                log.info("服务器", "登录已成功")
                                local beaconMsg, pointMsg
                                if cfg.MICE == 1 then
                                    pointMsg = string.format("%s>%s\r\n", sourceCall, miceEncode(gpsData))
                                    beaconMsg = string.format("%s>%s\r\n", string.match(pointMsg, "^(.-:).+"),
                                        cfg.BEACON)
                                else
                                    pointMsg = string.format("%s>APUVR:=%s%s%s%s%s%s%03d/%03d/A=%06d\r\n", sourceCall,
                                        gpsData.lat, gpsData.latType, cfg.TABLE, gpsData.lng, gpsData.lngType,
                                        cfg.SYMBOL, gpsData.course, gpsData.spd, gpsData.altFeet)
                                    beaconMsg = string.format("%s>APUVR:>%s\r\n", sourceCall, cfg.BEACON)
                                end
                                if cfg.BEACON_INTERVAL ~= 0 and os.time() - beaconTime > cfg.BEACON_INTERVAL * 60 then
                                    socketClient:send(beaconMsg)
                                    beaconTime = os.time()
                                    log.info("标信已发送", beaconMsg)
                                end
                                socketClient:send(pointMsg)
                                socketClient:close()
                                gpsDataOld = gpsData
                                pointTime = os.time()
                                log.info("位置已发送", pointMsg)
                                return true
                            elseif string.find(data, "unverified") then
                                log.warn("服务器", "服务器登录验证失败，请重新确认呼号和验证码")
                                return false
                            elseif string.find(data, "full") then
                                log.warn("服务器", "服务器已满，将自动重试")
                                return false
                            end
                        end
                    end
                end
                log.warn("服务器", "APRS服务器数据接收超时，已退出")
            else
                sys.wait(10000)
            end
        end
        log.warn("发送失败", "APRS服务器无法连接")
    else
        log.warn("发送失败", "网络未就绪")
        net.switchFly(true)
        sys.wait(10000)
        net.switchFly(false)
        return false
    end
end

local function pointSend()
    if (gps.isFix()) then
        if not gpsDataOld then
            reason = bit.bor(reason, 1)
        else
            if cfg.SMART_POINT == 1 then
                if gpsData.spd >= cfg.MIN_RUNSPD then
                    if courseDiff(gpsData.course, gpsDataOld.course) >= cfg.MIN_COURSE then
                        reason = bit.bor(reason, 2)
                    end
                    if os.time() - pointTime >= cfg.MAX_INTERVAL then
                        reason = bit.bor(reason, 4)
                    end
                elseif os.time() - pointTime >= 60 * cfg.STOP_INTERVAL then
                    reason = bit.bor(reason, 8)
                end
            else
                if gpsData.spd >= cfg.MIN_RUNSPD then
                    if os.time() - pointTime >= cfg.POINT_INTERVAL then
                        reason = bit.bor(reason, 16)
                    end
                elseif os.time() - pointTime >= 60 * cfg.STOP_INTERVAL then
                    reason = bit.bor(reason, 32)
                end
            end
        end

        if reason > 0 then
            if cfg.SMART_POINT == 0 or cfg.SMART_POINT == 1 and os.time() - pointTime >= cfg.MIN_INTERVAL then
                if aprsSend() then
                    reason = 0
                end
            end
        end
    end
end

local function pwdCal(callin)
    local call = string.upper(callin)
    local hash = 0x73e2
    local i = 1
    while i <= string.len(call) do
        hash = bit.bxor(hash, string.byte(call, i) * 0x100)
        i = i + 1
        if i <= string.len(call) then
            hash = bit.bxor(hash, string.byte(call, i))
            i = i + 1
        end
    end
    hash = bit.band(hash, 0x7fff)
    return hash
end

local function JudgeIPString(ipStr)
    if type(ipStr) ~= "string" then
        return false;
    end
    local len = string.len(ipStr);
    if len < 7 or len > 15 then
        return false;
    end
    local point = string.find(ipStr, "%p", 1);
    local pointNum = 0;
    while point ~= nil do
        if string.sub(ipStr, point, point) ~= "." then
            return false;
        end
        pointNum = pointNum + 1;
        point = string.find(ipStr, "%p", point + 1);
        if pointNum > 3 then
            return false;
        end
    end
    if pointNum ~= 3 then
        return false;
    end
    local num = {};
    for w in string.gmatch(ipStr, "%d+") do
        num[#num + 1] = w;
        local kk = tonumber(w);
        if kk == nil or kk > 255 then
            return false;
        end
    end
    if #num ~= 4 then
        return false;
    end
    return ipStr;
end

local function iniChk(cfgfile)
    local file = io.open(cfgfile)
    if file == nil then
        log.warn("配置校验", "校检失败：文件" .. cfgfile .. "不存在")
        return false
    end
    local iniFile = {}
    for line in file:lines() do
        if not line:match('^%s*;') then
            local param, value = line:match('^([%w|_]+)%s*=%s*(.+)%c*$');
            if (param and value ~= nil) then
                iniFile[param] = value;
                log.info("读取配置", param .. ": " .. value)
            end
        end
    end
    file:close()
    if not iniFile.CALLSIGN then
        log.error("配置校验", "呼号未设置")
        return false
    else
        iniFile.CALLSIGN = string.upper(iniFile.CALLSIGN)
        if not (iniFile.CALLSIGN:match('^[1-9]%u%u?%d%u%u?%u?%u?$') or
            iniFile.CALLSIGN:match('^%u[2-9A-Z]?%d%u%u?%u?%u?$')) then
            log.error("配置校验", "呼号不合法")
            return false
        end
        if string.len(iniFile.CALLSIGN) < 3 or string.len(iniFile.CALLSIGN) > 7 then
            log.error("配置校验", "呼号长度需要在 3-7 个字符")
            return false
        end
    end
    if not iniFile.PASSCODE then
        log.error("配置校验", "验证码未设置")
        return false
    else
        local pscode = pwdCal(iniFile.CALLSIGN)
        if not tonumber(iniFile.PASSCODE) or tonumber(iniFile.PASSCODE) ~= pscode then
            log.error("配置校验", "验证码错误")
            return false
        end
        iniFile.PASSCODE = pscode
    end
    if iniFile.SSID then
        iniFile.SSID = string.upper(iniFile.SSID)
        if not (iniFile.SSID:match('^%d%u?$') or iniFile.SSID:match('^[1][0-5]$') or iniFile.SSID:match('^%u%w?$')) then
            log.error("配置校验",
                "SSID不合法，只能是1-2个字母、数字；如果是2位数字，则不可以大于15")
            return false
        end
        if string.len(iniFile.CALLSIGN) + string.len(iniFile.SSID) > 8 then
            log.error("配置校验", "呼号+SSID的总长度不能超过8个字符")
            return false
        end
    end
    if iniFile.SERVER then
        if not (iniFile.SERVER:match('%.*%w[%w%-]*%.%a%a%a?%a?%a?%a?$') or JudgeIPString(iniFile.SERVER)) then
            log.error("配置校验", "服务器地址非法")
            return false
        end
    end
    if iniFile.PORT then
        local portTmp = tonumber(iniFile.PORT)
        if not portTmp or portTmp < 1024 or portTmp > 49151 then
            log.error("配置校验", "端口号非法，需要1024-49151之间")
            return false
        end
        iniFile.PORT = portTmp
    end
    if iniFile.MICE then
        if iniFile.MICE ~= '1' and iniFile.MICE ~= '0' then
            log.error("配置校验", "MICE错误，只能配置为 0 或 1 ")
            return false
        end
        iniFile.MICE = tonumber(iniFile.MICE)
    end
    if iniFile.TABLE then
        iniFile.TABLE = string.upper(iniFile.TABLE)
        if not iniFile.TABLE:match('^[/\\2DEGIRY]$') then
            log.error("配置校验", "TABLE设置错误")
            return false
        end
    end
    if iniFile.SYMBOL then
        if not iniFile.SYMBOL:match('^[%w%p]$') then
            log.error("配置校验", "SYMBOL设置错误")
            return false
        end
    end
    if iniFile.BEACON then
        if iniFile.BEACON:len() > 62 then
            log.error("配置校验", "BEACON长度过长，最大62个字符")
            return false
        end
    end
    if iniFile.BEACON_INTERVAL then
        local v = tonumber(iniFile.BEACON_INTERVAL)
        if not v or ((v < 10 or v > 600) and v ~= 0) then
            log.error("配置校验", "BEACON_INTERVAL错误，正确范围为10-600分钟")
            return false
        end
        iniFile.BEACON_INTERVAL = v
    end
    if iniFile.MIN_INTERVAL then
        local minI = tonumber(iniFile.MIN_INTERVAL)
        if not minI or minI < 30 or minI > 90 then
            log.error("配置校验", "MIN_INTERVAL错误，正确范围为30-90秒")
            return false
        end
        iniFile.MIN_INTERVAL = minI
    end
    if iniFile.MIN_COURSE then
        local minC = tonumber(iniFile.MIN_COURSE)
        if not minC or minC < 10 or minC > 45 then
            log.error("配置校验", "MIN_COURSE错误，正确范围为10-45度")
            return false
        end
        iniFile.MIN_COURSE = minC
    end
    if iniFile.MIN_RUNSPD then
        local minS = tonumber(iniFile.MIN_RUNSPD)
        if not minS or minS < 2 or minS > 10 then
            log.error("配置校验", "MIN_RUNSPD错误，正确范围为2-10")
            return false
        end
        iniFile.MIN_RUNSPD = minS
    end
    if iniFile.MAX_INTERVAL then
        local maxI = tonumber(iniFile.MAX_INTERVAL)
        if not maxI or maxI < 90 or maxI > 300 then
            log.error("配置校验", "MAX_INTERVAL错误，正确范围为90-300")
            return false
        end
        iniFile.MAX_INTERVAL = maxI
    end
    if iniFile.STOP_INTERVAL then
        local stopI = tonumber(iniFile.STOP_INTERVAL)
        if not stopI or stopI < 10 or stopI > 120 then
            log.error("配置校验", "STOP_INTERVAL错误，正确范围为10 - 120")
            return false
        end
        iniFile.STOP_INTERVAL = stopI
    end
    if iniFile.SMART_POINT then
        if iniFile.SMART_POINT ~= '0' and iniFile.SMART_POINT ~= '1' then
            log.error("配置校验", "SMART_POINT错误，只能配置为 0 或 1 ")
            return false
        end
        iniFile.SMART_POINT = tonumber(iniFile.SMART_POINT)
    end
    if iniFile.POINT_INTERVAL then
        local pointInterval = tonumber(iniFile.POINT_INTERVAL)
        if not pointInterval or pointInterval < 30 or pointInterval > 300 then
            log.error("配置校验", "POINT_INTERVAL错误，正确范围为30 - 300")
            return false
        end
        iniFile.POINT_INTERVAL = pointInterval
    end
    log.info("配置校验", "配置校验已通过")
    return true, iniFile
end

local function cfgRead()
    local res, ini = iniChk("cfgsave.ini")
    if not res then
        log.warn("读取配置", '读取"cfgsave.ini"失败，将读取"/lua/cfg.ini"')
        res, ini = iniChk("/lua/cfg.ini")
        if not res then
            log.error("读取配置", '读取"/lua/cfg.ini"失败，系统已停止！')
            return false
        else
            log.info("读取配置", '读取"/lua/cfg.ini"成功')
            local file = io.open("cfgsave.ini", "w")
            for key, val in pairs(ini) do
                cfg[key] = val
                file:write(key .. "=" .. val .. "\n")
            end
            file:close()
            log.info("读取配置", '保存到副本文件已完成')
        end
    else
        log.info("读取配置", '读取"cfgsave.ini"成功')
        for key, val in pairs(ini) do
            cfg[key] = val
        end
    end
end

sys.taskInit(function()
    sys.wait(5000)
    while not gpsFlag do
        sys.wait(100)
    end
    if cfgRead() == false then
        log.error("加载配置文件", "加载失败，系统已停止！")
        while true do
            sys.wait(1000)
        end
    else
        log.info("加载配置文件", "加载已完成")
    end
    require "update"
    update.request()
    while true do
        gpsProcess()
        pointSend()
        sys.wait(1000)
    end
end)

sys.subscribe("AUTOGPS_READY", function(gpsLib, agpsLib, kind, baudrate)
    gps = gpsLib
    agps = agpsLib
    log.info("testGps.AUTOGPS_READY", baudrate, kind)
    gps.setUart(uartId, baudrate, 8, uart.PAR_NONE, uart.STOP_1)
    gpsFlag = true
end)
