--[[
    4G-Tracker
    （一款使用 4G DTU 制作的 APRS Tracker，by BG4UVR 2022.6.2）
    开源网址：
    https://gitee.com/bg4uvr/LTE-Tracker
    https://github.com/bg4uvr/4G-Tracker
]] -- 4G-Tracker
mycfg = {
    ["CALLSIGN"] = nil,
    ["PASSCODE"] = nil,
    ["SSID"] = "4G",
    ["SERVER"] = "china.aprs2.net",
    ["PORT"] = 14580,
    ["TABLE"] = "/",
    ["SYMBOL"] = ">",
    ["BEACON"] = string.format("4G-Tracker ver%s https://github.com/bg4uvr/4G-Tracker", VERSION),
    ["BEACON_INTERVAL"] = 60,
    ["TRACKERMODE"] = 1,
    ["BTNAME"] = nil
}

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
            local n = string.find(line, '%s*;')
            if not n then
                n = string.find(line, '%s*%c*$')
            end
            if n then
                line = string.sub(line, 1, n - 1)
            end
            local param, value = line:match('^%s*([^%s]+)%s*=%s*(.-)$');
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
    if iniFile.TRACKERMODE then
        if iniFile.TRACKERMODE < '1' or iniFile.TRACKERMODE > '3' then
            log.error("配置校验", "TRACKERMODE 错误，只能配置为 1 至 3 ")
            return false
        end
        iniFile.TRACKERMODE = tonumber(iniFile.TRACKERMODE)
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
                mycfg[key] = val
                file:write(key .. "=" .. val .. "\n")
            end
            file:close()
            log.info("读取配置", '保存到副本文件已完成')
        end
    else
        log.info("读取配置", '读取"cfgsave.ini"成功')
        for key, val in pairs(ini) do
            mycfg[key] = val
        end
    end
    return true
end

sys.taskInit(function()
    sys.wait(5000)
    if cfgRead() == false then
        log.error("加载配置文件", "加载失败，系统已停止！")
        while true do
            sys.wait(1000)
        end
    else
        if not mycfg.BTNAME then
            mycfg.BTNAME = mycfg.CALLSIGN .. '-7'
        end
        log.info("加载配置文件", "加载已完成")
        if mycfg.SSID == '0' then
            sourceCall = mycfg.CALLSIGN
        else
            sourceCall = mycfg.CALLSIGN .. '-' .. mycfg.SSID
        end
        sys.publish("CFGLOADED")
        update.request()
    end
end)
