--[[
    4G-Tracker
    （一款使用 4G DTU 制作的 APRS Tracker，by BG4UVR 2022.6.2）
    开源网址：
    https://gitee.com/bg4uvr/LTE-Tracker
    https://github.com/bg4uvr/4G-Tracker
]] -- 4G-Tracker
MIN_COURSE = 20
MIN_RUNSPD = 3
MIN_INTERVAL = 15
MAX_INTERVAL = 60
STOP_INTERVAL = 30
local imei, sourceCall, beaconMsg, gps, agps, timezone, gpsDataOld
local beaconTime, reason, noNetCnt = 0, 0, 0
local pointTab = {}
local cfg = {
    ["CALLSIGN"] = nil,
    ["PASSCODE"] = nil,
    ["SSID"] = "4G",
    ["SERVER"] = "china.aprs2.net",
    ["PORT"] = 14580,
    ["TABLE"] = "/",
    ["SYMBOL"] = ">",
    ["BEACON"] = string.format("4G-Tracker ver%s https://github.com/bg4uvr/4G-Tracker", VERSION),
    ["BEACON_INTERVAL"] = 60,
    ["UDPMODE"] = 0
}

local function courseDiff(new, old)
    if not new or not old or new > 359 or new < 0 or old > 359 or old < 0 then
        return 0
    end
    local diff = math.abs(new - old)
    if diff > 180 then
        diff = 360 - diff
    end
    return diff
end

local function gpsProcess()
    if not gps.isFix() then
        return
    else
        local gpsData, tLocation = {}, gps.getLocation("DEGREE_MINUTE")
        gpsData.time = os.time() - timezone * 15 * 60
        gpsData.lat = tonumber(tLocation.lat)
        gpsData.lng = tonumber(tLocation.lng)
        gpsData.spd = tonumber(gps.getOrgSpeed())
        gpsData.cour = gps.getCourse()
        gpsData.alt = gps.getAltitude() * 3.2808399
        gpsData.satuse = gps.getUsedSateCnt()
        gpsData.satview = gps.getViewedSateCnt()
        if tLocation.latType == 'S' then
            gpsData.lat = -gpsData.lat
        end
        if tLocation.lngType == 'W' then
            gpsData.lng = -gpsData.lng
        end
        if not gpsDataOld then
            table.insert(pointTab, gpsData)
            gpsDataOld = gpsData
        else
            if gpsData.spd >= MIN_RUNSPD then
                if courseDiff(gpsData.cour, gpsDataOld.cour) >= MIN_COURSE then
                    reason = bit.bor(reason, 1)
                end
                if gpsData.time - gpsDataOld.time >= MAX_INTERVAL then
                    reason = bit.bor(reason, 2)
                end
            elseif gpsData.time - gpsDataOld.time >= 60 * STOP_INTERVAL then
                reason = bit.bor(reason, 4)
            end
            if reason > 0 and gpsData.time - gpsDataOld.time >= MIN_INTERVAL then
                table.insert(pointTab, gpsData)
                gpsDataOld = gpsData
                reason = 0
            end
        end
    end
end

local function socketSend(socketClient)
    if cfg.BEACON_INTERVAL ~= 0 and os.time() - beaconTime > cfg.BEACON_INTERVAL * 60 then
        if not socketClient:send(beaconMsg, 10) then
            log.warn("服务器", "信标发送超时")
            return false
        end
        beaconTime = os.time()
        log.info("标信已发送", beaconMsg)
    end
    while #pointTab > 0 do
        local pointData = pointTab[1]
        local pointTime, latT, lngT = os.date("*t", pointData.time), 'N', 'E'
        if pointData.lat < 0 then
            latT = 'S'
            pointData.lat = -pointData.lat
        end
        if pointData.lng < 0 then
            lngT = 'W'
            pointData.lng = -pointData.lng
        end
        local pointMsg = string.format(
            "%s>APUVR:/%02d%02d%02dh%07.2f%s%s%08.2f%s%s%03d/%03d/A=%06d imei:*%s rssi:%s sat:%d/%d\r\n", sourceCall,
            pointTime.hour, pointTime.min, pointTime.sec, pointData.lat, latT, cfg.TABLE, pointData.lng, lngT,
            cfg.SYMBOL, pointData.cour, pointData.spd, pointData.alt, imei, net.getRssi(), pointData.satuse,
            pointData.satview)
        if socketClient:send(pointMsg, 10) then
            log.info("位置已发送", pointMsg)
            table.remove(pointTab, 1)
            if #pointTab > 0 then
                sys.wait(5000)
            end
        else
            log.warn("服务器", "位置数据发送超时")
            socketClient:close()
            return false
        end
    end
    socketClient:close()
    log.info("服务器", "发送完成，连接已关闭")
    return true
end

local function netProcess()
    if not socket.isReady() then
        noNetCnt = noNetCnt + 1
        if noNetCnt >= 5 then
            noNetCnt = 0
            log.warn("网络", "长时间未就绪，尝试重启网络")
            net.switchFly(true)
            sys.wait(10000)
            net.switchFly(false)
        else
            log.warn("网络", "网络未就绪，将自动重试")
            sys.waitUntil("IP_READY_IND", 60000)
        end
        return false
    end
    noNetCnt = 0
    local socketClient
    if cfg.UDPMODE == 1 then
        socketClient = socket.udp()
        if not socketClient:connect(cfg.SERVER, cfg.PORT, 10) then
            log.warn("服务器", "连接UDP服务器失败，稍后自动重试")
            return false
        else
            return socketSend(socketClient)
        end
    else
        local loginCmd, recvCnt = false, 0
        socketClient = socket.tcp()
        if not socketClient:connect(cfg.SERVER, cfg.PORT, 10) then
            log.warn("服务器", "连接TCP服务器失败，稍后自动重试")
            return false
        end
        while true do
            local result, data = socketClient:recv(10000)
            if result then
                if not loginCmd then
                    if (string.find(data, "aprsc") or string.find(data, "javAPRSSrvr")) then
                        log.info("服务器", "正在登录...")
                        if socketClient:send(string.format("user %s pass %d vers 4G-Tracker %s\r\n", sourceCall,
                            cfg.PASSCODE, VERSION), 10) then
                            loginCmd = true
                            recvCnt = 0
                        else
                            log.warn("服务器", "登录超时")
                            break
                        end
                    end
                else
                    if string.find(data, " verified") then
                        log.info("服务器", "登录已成功")
                        return socketSend(socketClient)
                    else
                        if string.find(data, "unverified") then
                            log.warn("服务器", "服务器登录验证失败，请重新确认呼号和验证码")
                            break
                        elseif string.find(data, "full") then
                            log.warn("服务器", "服务器已满")
                            break
                        end
                    end
                end
                recvCnt = recvCnt + 1
                if recvCnt >= 5 then
                    log.warn("服务器", "未收到期望数据")
                    break
                end
            else
                log.warn("服务器", "服务器接收超时")
                break
            end
        end
        socketClient:close()
        return false
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
    if iniFile.UDPMODE then
        if iniFile.UDPMODE ~= '0' and iniFile.UDPMODE ~= '1' then
            log.error("配置校验", "UDPMODE 错误，只能配置为 0 或 1 ")
            return false
        end
        iniFile.UDPMODE = tonumber(iniFile.UDPMODE)
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
            log.error("读取配置", '读取"/lua/cfg.ini"失败')
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
    return true
end

sys.taskInit(function()
    sys.wait(3000)
    if cfgRead() == false then
        log.error("加载配置文件", "加载失败，系统已停止！")
        while true do
            sys.wait(1000)
        end
    else
        log.info("加载配置文件", "加载已完成")
    end
    update.request()
    while not gps or not gps.isFix() do
        sys.wait(100)
    end
    log.info("GPS模块", "已经定位")
    while true do
        local timeLocal, timeGPS = os.time(), os.time(gps.getUtcTime())
        timezone = math.floor((math.abs(timeLocal - timeGPS) / (15 * 60)) + 0.5)
        if timezone <= 48 then
            if (timeLocal < timeGPS + 7.5 * 60) then
                timezone = -timezone
            end
            log.info("GPS模块", string.format("当前时区: %0.2f", timezone / 4))
            break
        else
            sys.wait(1000)
        end
    end
    sourceCall = cfg.CALLSIGN
    if cfg.SSID ~= '0' then
        sourceCall = sourceCall .. '-' .. cfg.SSID
    end
    beaconMsg = string.format("%s>APUVR:>%s\r\n", sourceCall, cfg.BEACON)
    imei = string.sub(misc.getImei(), -4, -1)
    sys.timerLoopStart(gpsProcess, 1000)
    while true do
        if #pointTab > 0 and not netProcess() then
            sys.wait(10000)
        end
        sys.wait(100)
    end
end)

sys.subscribe("AUTOGPS_READY", function(gpsLib, agpsLib, kind, baudrate)
    gps = gpsLib
    agps = agpsLib
    gps.setUart(3, baudrate, 8, uart.PAR_NONE, uart.STOP_1)
    gps.setParseItem(1)
    gps.open(gps.DEFAULT, {
        tag = "4G-Tracker"
    })
    log.info("GPS模块", "型号", kind, "速率", baudrate, "已经打开，等待定位")
end)
