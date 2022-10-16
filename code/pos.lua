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

pointTab = {}
local gps, agps, timezone, gpsDataOld
local reason = 0

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
            if gpsData.spd >= MIN_RUNSPD and not (mycfg.TRACKERMODE == 2 and btIsConnect) then
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

sys.taskInit(function()
    sys.waitUntil("CFGLOADED")
    if mycfg.TRACKERMODE ~= 3 then
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
        while true do
            gpsProcess()
            sys.wait(1000)
        end
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

