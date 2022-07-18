--[[
    4G-Tracker
    （一款使用 4G DTU 制作的 APRS Tracker，by BG4UVR 2022.6.2）
    开源网址：
    https://gitee.com/bg4uvr/LTE-Tracker
    https://github.com/bg4uvr/4G-Tracker
]] -- 4G-Tracker
PROJECT = "4G-Tracker"
VERSION = "0.0.14"
PRODUCT_KEY = "kSgyVmAwL5cLwNzzx9xA9Z5btFlXAb9E"

require "log"
LOG_LEVEL = log.LOGLEVEL_INFO

require "sys"
require "net"

ril.request("AT+RNDISCALL=0,1")

require "netLed"
pmd.ldoset(2, pmd.LDO_VLCD)
netLed.setup(true, pio.P0_1, pio.P0_4)

require "aprs"

sys.init(0, 0)
sys.run()
