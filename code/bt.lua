--[[
    4G-Tracker
    （一款使用 4G DTU 制作的 APRS Tracker，by BG4UVR 2022.6.2）
    开源网址：
    https://gitee.com/bg4uvr/LTE-Tracker
    https://github.com/bg4uvr/4G-Tracker
]] -- 4G-Tracker
btmsgTab = {}
local function init()
    rtos.on(rtos.MSG_BLUETOOTH, function(msg)
        if msg.event == btcore.MSG_OPEN_CNF then
            sys.publish("BT_OPEN", msg.result)
        elseif msg.event == btcore.MSG_BLE_CONNECT_CNF then
            sys.publish("BT_CONNECT_IND", {
                ["handle"] = msg.handle,
                ["result"] = msg.result,
                ["addr"] = msg.addr
            })
            btIsConnect = true
        elseif msg.event == btcore.MSG_BLE_DISCONNECT_CNF then
            btIsConnect = false
            log.info("蓝牙", "HG-UV98 连接已断开")
        elseif msg.event == btcore.MSG_BLE_DATA_IND then
            sys.publish("BT_DATA_IND", {
                ["data"] = msg.data,
                ["len"] = msg.len
            })
        elseif msg.event == btcore.MSG_BLE_SCAN_CNF then
            if (msg.enable == 1) then
                sys.publish("BT_SCAN_OPEN_CNF", msg.result)
            else
                sys.publish("BT_SCAN_CLOSE_CNF", msg.result)
            end
        elseif msg.event == btcore.MSG_BLE_SCAN_IND then
            sys.publish("BT_SCAN_IND", {
                ["name"] = msg.name,
                ["addr_type"] = msg.addr_type,
                ["addr"] = msg.addr
            })
        elseif msg.event == btcore.MSG_BLE_FIND_CHARACTERISTIC_IND then
            sys.publish("BT_FIND_CHARACTERISTIC_IND", msg.result)
        end
    end)
end

local function poweron()
    btcore.open(1)
    _, result = sys.waitUntil("BT_OPEN", 5000)
end

local function scan()
    btcore.scan(1)
    _, result = sys.waitUntil("BT_SCAN_OPEN_CNF", 5000)
    if result ~= 0 then
        return false
    end
    sys.timerStart(function()
        sys.publish("BT_SCAN_IND", nil)
    end, 10000)
    while true do
        _, bt_device = sys.waitUntil("BT_SCAN_IND")
        if not bt_device then
            btcore.scan(0)
            return false
        else
            if (string.sub(bt_device.name, 1, string.len(mycfg.BTNAME)) == mycfg.BTNAME) then
                name = bt_device.name
                addr_type = bt_device.addr_type
                addr = bt_device.addr
                btcore.scan(0)
                btcore.connect(addr, addr_type)
                log.info("找到蓝牙设备", "名称", name, "地址", addr)
                return true
            end
        end
    end
end

local function data_trans()
    _, bt_connect = sys.waitUntil("BT_CONNECT_IND", 5000)
    if bt_connect.result ~= 0 then
        return false
    end
    btcore.findcharacteristic("55e405d2af9fa98fe54a7dfe43535349")
    _, result = sys.waitUntil("BT_FIND_CHARACTERISTIC_IND", 5000)
    if not result then
        return false
    end
    btcore.opennotification("16962447c62361bad94b4d1e43535349");
    log.info("蓝牙", "已连接到 HG-UV98 对讲机")
    sys.wait(1000)
    local data = 0
    while btIsConnect do
        _, bt_recv = sys.waitUntil("BT_DATA_IND", 5000)
        if bt_recv then
            while true do
                local _, recvdata, recvlen = btcore.recv(3)
                if recvlen == 0 then
                    break
                end
                data = data .. recvdata
            end
            if string.find(data, '.-\r\n$') then
                log.info("蓝牙收到数据", data)
                if (data:match('^[1-9]%u%u?%d%u%u?%u?%u?') or data:match('^%u[2-9A-Z]?%d%u%u?%u?%u?')) and
                    socket.isReady() then
                    table.insert(btmsgTab, data)
                end
                data = ""
            end
        else
            data = ""
        end
    end
end

sys.taskInit(function()
    init()
    poweron()
    sys.waitUntil("CFGLOADED")
    while true do
        if scan() then
            data_trans()
        else
            sys.wait(5000)
        end
    end
end)
