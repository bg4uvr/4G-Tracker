--[[
    4G-Tracker
    （一款使用 4G DTU 制作的 APRS Tracker，by BG4UVR 2022.6.2）
    开源网址：
    https://gitee.com/bg4uvr/LTE-Tracker
    https://github.com/bg4uvr/4G-Tracker
]] -- 4G-Tracker
msgTab = {}
local imei, beaconTime

local function point2msg(pointData)
    local pointTime, latT, lngT = os.date("*t", pointData.time), 'N', 'E'
    if pointData.lat < 0 then
        latT = 'S'
        pointData.lat = -pointData.lat
    end
    if pointData.lng < 0 then
        lngT = 'W'
        pointData.lng = -pointData.lng
    end
    return string.format("%s>APUVR:/%02d%02d%02dh%07.2f%s%s%08.2f%s%s%03d/%03d/A=%06d imei:*%s rssi:%s sat:%d/%d\r\n",
        sourceCall, pointTime.hour, pointTime.min, pointTime.sec, pointData.lat, latT, mycfg.TABLE, pointData.lng, lngT,
        mycfg.SYMBOL, pointData.cour, pointData.spd, pointData.alt, imei, net.getRssi(), pointData.satuse,
        pointData.satview)
end

sys.taskInit(function()
    sys.waitUntil("CFGLOADED")
    imei = string.sub(misc.getImei(), -4, -1)
    beaconTime = 0
    local beaconMsg = string.format("%s>APUVR:>%s\r\n", sourceCall, mycfg.BEACON)
    while true do
        if mycfg.BEACON_INTERVAL ~= 0 and os.time() - beaconTime >= mycfg.BEACON_INTERVAL * 60 then
            beaconTime = os.time()
            table.insert(msgTab, beaconMsg)
        end
        if pointTab and #pointTab > 0 then
            table.insert(msgTab, point2msg(pointTab[1]))
            table.remove(pointTab, 1)
        end
        if btmsgTab and #btmsgTab > 0 then
            table.insert(msgTab, btmsgTab[1])
            table.remove(btmsgTab, 1)
        end
        sys.wait(100)
    end
end)
