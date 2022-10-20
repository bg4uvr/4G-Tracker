--[[
    4G-Tracker
    （一款使用 4G DTU 制作的 APRS Tracker，by BG4UVR 2022.6.2）
    开源网址：
    https://gitee.com/bg4uvr/LTE-Tracker
    https://github.com/bg4uvr/4G-Tracker
]] -- 4G-Tracker
local noNetCnt = 0

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
    local loginCmd, recvCnt = false, 0
    socketClient = socket.tcp()
    if not socketClient:connect(mycfg.SERVER, mycfg.PORT, 10) then
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
                        mycfg.PASSCODE, VERSION), 10) then
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
                    local lastTime, lastCall = os.time(), " "
                    while os.time() - lastTime <= 18 do
                        if #msgTab > 0 then
                            local msgCall = string.sub(msgTab[1], 1, string.find(msgTab[1], '>') - 1)
                            while lastCall == msgCall and os.time() - lastTime <= 5 do
                                sys.wait(100)
                            end
                            if socketClient:send(msgTab[1], 10) then
                                lastTime = os.time()
                                lastCall = msgCall
                                log.info("消息已发送", msgTab[1])
                                table.remove(msgTab, 1)
                            else
                                socketClient:close()
                                return false
                            end
                        end
                        result, data = socketClient:recv(100)
                    end
                    socketClient:close()
                    return true
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

sys.taskInit(function()
    sys.waitUntil("CFGLOADED")
    while true do
        if msgTab and #msgTab > 0 and not netProcess() then
            sys.wait(10000)
        end
        sys.wait(100)
    end
end)
