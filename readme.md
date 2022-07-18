# 4G-Tracker

#### 简介

这是一款通过使用商品化DTU进行二次开发，来制作的专门用于业余无线电爱好者发送APRS消息的装置，简单命名为 **4G-Tracker**。

本制作的特点：

- 使用商品DTU，硬件完全无改动
- 价格便宜（这个DTU网上只卖1百多块）
- 流量消耗很少，买DTU时赠送物联网SIM卡已经足够使用（360MB/年，首年免费，次年6元/年）
- DTU是4G的“全网通”，不使用清退中的2G网络，可以随意选择三大运营商
- 固件支持空中升级

这个DTU的样子如下图，体积还算小巧

![](./doc/001.jpg)

再来正面原图，方便大家确定准确的型号

![](./doc/008.jpg)

本资料在 Gitee 和 github 两个网站同步更新，网址如下：

https://gitee.com/bg4uvr/LTE-Tracker （国内建议使用）

https://github.com/bg4uvr/4G-Tracker （国内有时可能无法打开，或图片无法显示）

#### 声明

如按本文的介绍进行制作，默认您已明确知晓并同意以下各项内容：

1. 本制作只适合有合法手续的业余无线电爱好者，在遵守相关法律法规的前提下使用，不符合本条件的制作需要自行承担一切后果。
2. 使用或通过修改代码使用本装置时，配置的相关参数需要严格遵守APRS系统相关规则。
3. 本装置如用于车载将涉及到机动车电源线改接，制作者需要自行对可能产生各种危险情况（包括但不限于短路起火等）自行负责。
4. 本人不对的代码可能存在在各种错误造成的结果负责（包括但不限于因BUG造成使用过多流量等）。
5. 本人与文中涉及到的商品DTU，以及使用到的物联网SIM卡的生产商、销售商无任何关系，文中的相关品牌与型号，均为介绍不构成任何推荐，本人也不承担任何负责。

废话少说，下面进入正题~

#### 制作步骤

1. 我使用的DTU型号为 **深圳银尔达** 生产的 **YED-D820W1** 型4G DTU（内部核心为上海合宙生产的 **Air820UG** 模块），该DTU内置了定位功能（支持接收GPS、北斗卫星）。理论上，本资料也适合在其他各种使用Air820UG模块制作的DTU或开发板上来实现。

2. 硬件部分无任何改动，只要分别接好4G和GPS天线，再将SIM卡装入DTU的卡槽，外接5-36V直流电源（正负极分别连接到模块的VIN和GND端口）即可。 **如果是车载使用，强烈电源建议接在ACC端（通俗地说就是指钥匙打开后才有电的那组电源线），以免长期停车时耗尽蓄电池电量** 。

3. 下载本代码，共有两种方式。第一种是使用git命令进行克隆，这种方式略复杂就不介绍了。第二种是点击“克隆/下载”，选择“下载ZIP”来下载文件，下图是Gitee网站的，github网站也是类似操作。

   ![](./doc/002.jpg)

   下载好ZIP文件后，解压缩好。**然后修改“cfg.ini”文件，其中呼号和验证码是必设选项，不设置将无法工作**。其他项目暂时不修改也可以，待熟悉后可以再慢慢细研究其中含义。

   ![](./doc/009.jpg)

4. 下载

   [合宙Cat.1模块PC 端 USB 驱动](https://cdn.openluat-luatcommunity.openluat.com/attachment/20200808183454135_sw_file_20200303181718_8910_module_usb_driver_signed%20_20200303_hezhou.7z)

   并安装完成，插入USB线连接DTU模块（**注意：模块的USB接口只有数据通信功能，并不能用来给模块供电，供电需要在VIN和GND端口外接**），观察设备管理器中没有无法识别的硬件就说明驱动已经正常工作了。

5. 下载

   [Luat下载调试工具v2](https://luatos.com/luatools/download/last)

   安装步骤介绍一下：

   软件可能是因为没有数字证书的关系，在我的win10系统下EDGE浏览器会提示不安全，点击右侧的三个小点后选择“保留”即可

   ![](./doc/003.jpg)

   ![](./doc/004.jpg)

   双击文件点运行，仍然会有个提示，选择“仍然运行”（只有第一次需要，后面再打开就没有这个提示了）

   ![](./doc/005.jpg)

   此时软件会提示有更新，点击“开始”来更新资源文件，更新完成后，需要手动点击“取消”来关闭更新窗口。注意：**这个软件第一次运行时，因为需要在线更新最新的资源文件，所以电脑必须连接互联网**，否则会因为没有资源文件而不能正常工作。

   ![](./doc/006.jpg)


6. 烧写luat脚本：

   - 打开Luatools，点击右侧的“项目管理测试”

   - 在新弹出的窗口中，点击左下角的“新建项目”，项目名称可以输入“4G-Tracker”(其他名称也可以)

   - “选择底层CORE”，右侧点击“选择文件”，选择Luatools目录下的“resource\8910_lua_lod\core_V4003\LuatOS-Air_V4003_RDA8910_BT_FLOAT.pac”文件（**文件名中的“4003”是厂家的版本号，因为一些已知的原因，不建议使用其他版本。如果厂家更新了资源文件，找不到此版本的文件，可以直接把本代码pac目录下的压缩包解压后使用**），点击“打开”

   - “脚本列表”右侧，点击“增加脚本和资源文件”，选择好第2步解压文件夹下的3个“.lua”文件和1个“cfg.ini”文件。注意：不要多选和少选，一共选4个文件

   - 勾选“USB BOOT下载”，按住DTU主板上的BOOT按键，给DTU上电，然后点击右侧的“下载底层和脚本”

     ![](./doc/007.jpg)

     烧写过程大约不到一分钟即可结束，至此DIY工作全部完成。

#### 错误排查

脚本和配置文件写入后，无需再进行其他任何设置和操作，装置即可自动开始运行。如果没有拨掉连接电脑和DTU的USB电缆，那么Luatools软件的调试窗口中会输出相关运行状态信息，可以用来确认当前的工作状况，判断装置是否已经正常工作。

第一次使用lua语言编程，水平有限加上代码也未经长期详细测试，可能仍存在诸多不足甚至错误，如发现问题或有意见建议，欢迎留言交流和指导~

#### 常见问题
1. Q：cfg.ini 文件打开后，显示格式混乱怎么办？

   A：由于Git的关系，代码中采用的是linux系统下的LF换行符，而不是Windows系统的CRLF换行符，在旧版Windows系统中会因此无法正确显示换行。较简单的解决办法是下载一个 notepad++ 文本编辑软件，此软件支持LF、CRLF、CR换行符文件的正常显示及编辑。

2. Q：固件空中自动更新怎么用？

   A：当原有固件被发现存在重大错误而必须要进行修正，或是软件进行了重要的功能更新时，我会发布远程更新固件。

   更新过程对用户来讲是完全无感的，不需要用户做任何设置与操作，远程更新不会覆盖您的个人配置，如果你开启了默认信标语句，那么更新后你将可以看到固件版本号发生了变化。一次远程固件更新，消耗流量约40KB左右。为了减少不必要的流量消耗，我会极尽可能减少发布远程更新的次数。

   **此处我以人格保证本功能不会被滥用，不会用于增加与APRS无关的功能** 。如果您对此不放心，可以把 aprs.lua 文件中第467行（随着代码版本更新，行号可能会发生变化）
   ```
   update.request()
   ```
   注释掉，即更改为
   ```
   -- update.request()
   ```
   即可禁用此功能。

   需要说明的是，**远程固件更新功能的正常工作，需要一个必要的条件，就是你的DTU没有刷写过其他项目的代码** （全新购买的DTU，一般不需要考虑本问题）。这涉及到了模块硬件序列号的注册项目问题，如果硬件已经注册到了其他项目中，则需要在上海合宙平台上做相关硬件转移操作后才能正常使用本功能，相关说明可以参看合宙官网：https://doc.openluat.com/wiki/21?wiki_page_id=2432 ，有此需求的朋友可以与我联系获取转移时需要填写相关的数据。

3. Q：配置文件中各种间隔时间怎样设置才合适？

   A：没有最好的设置，只能根据自己的需求来尽量调整。为了能让大家理解各参数的实际意义，此处简单介绍一下代码中发点时机的选择原理。

   首先明确一下我们的目标：就是让所发的点形成的连线，尽量准确地匹配到我们实际行驶的路线上。但在实际中我们会受到一个限制，就是我们不能无节制地缩短发点时间间隔，这一方面是因为APRS网络规则，另一方面也是出于道德和环保（我们不能为了使自己的线路信息精确，而把大量低信息含量数据不受限制地发送到公众的网络中，浪费他人的带宽、流量和时间，这是对他人的不尊重，毕竟APRS网络不是只为我们某一个人服务的）。所以我们目标现在变成了：用尽量少的点，来尽量准确地匹配到我们实际的行驶线路。为了达到这种效果，**我们把发点的时机选择在行驶方向发生变化时，同时因为存在发点最短时间的限制，所以我们还要在行驶方向没有发生变化时尽量不发点**（因为这样才能尽量在发生转弯时，不会因为与上一点间隔时间太短而无法发点）。

   所以，几个时间间隔选择的原则就是：
   1. 运动中最短发点间隔不要太小（太小了会产生过多的数据，不环保）
   2. 运动中最大发点间隔尽量大一些（这样转弯时才尽量有机会能发点，但注意过大会造成直线路段发点稀疏）
   3. 发点需要变化的方位角度数要适中（过小会造成小弯发点而大弯失去机会，过大会造成转小弯不发点）
   4. 运动与静止区分速度值，不是太重要，如果你的GPS漂移大，可以设置大一点（现在GPS和北斗同时接收的定位模块，漂移一般已经很小了）
   5. 静止状态发点间隔不用太严格，在要求的范围内都行（设置静止状态判断，目的是为了不发送大量重复的坐标）

   最后还是再说一下，配置的默认值已经是经过实验优化得出的，一般不建议更改。

4. Q：待补充~

   A：
