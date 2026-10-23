/*
末地的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/world/end.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/world/end.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_WORLD_END_INCLUDED
#define OMNI_EFFECT_WORLD_END_INCLUDED
// @effect {"label":{"zh_cn":"末地","en_us":"End"}}
// @option {"label":{"zh_cn":"公转周期","en_us":"End Revolution Period"},"description":{"zh_cn":"行星绕末地转一圈的时间。","en_us":"Time for the planet to orbit once."},"slider":true}
#define OMNI_END_PLANET_CYCLE 15.0 // [0.25 0.5 0.75 1.0 1.5 2.0 3.0 5.0 7.5 10.0 15.0 20.0 30.0 60.0]
// @option {"label":{"zh_cn":"手动相位控制","en_us":"Manual Phase Control"},"description":{"zh_cn":"手动指定末地行星的位置。","en_us":"Manually sets the planet's phase."}}
//#define OMNI_END_MANUAL_PLANET_CYCLE
// @option {"label":{"zh_cn":"相位角","en_us":"Phase Angle"},"description":{"zh_cn":"“手动相位控制”的相位值，单位度。","en_us":"Phase value in degrees used by Manual Phase Control."},"slider":true}
#define OMNI_END_MANUAL_PLANET_ANGLE 0.0 // [0.0 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0 10.0 11.0 12.0 13.0 14.0 15.0 16.0 17.0 18.0 19.0 20.0 21.0 22.0 23.0 24.0 25.0 26.0 27.0 28.0 29.0 30.0 31.0 32.0 33.0 34.0 35.0 36.0 37.0 38.0 39.0 40.0 41.0 42.0 43.0 44.0 45.0 46.0 47.0 48.0 49.0 50.0 51.0 52.0 53.0 54.0 55.0 56.0 57.0 58.0 59.0 60.0 61.0 62.0 63.0 64.0 65.0 66.0 67.0 68.0 69.0 70.0 71.0 72.0 73.0 74.0 75.0 76.0 77.0 78.0 79.0 80.0 81.0 82.0 83.0 84.0 85.0 86.0 87.0 88.0 89.0 90.0 91.0 92.0 93.0 94.0 95.0 96.0 97.0 98.0 99.0 100.0 101.0 102.0 103.0 104.0 105.0 106.0 107.0 108.0 109.0 110.0 111.0 112.0 113.0 114.0 115.0 116.0 117.0 118.0 119.0 120.0 121.0 122.0 123.0 124.0 125.0 126.0 127.0 128.0 129.0 130.0 131.0 132.0 133.0 134.0 135.0 136.0 137.0 138.0 139.0 140.0 141.0 142.0 143.0 144.0 145.0 146.0 147.0 148.0 149.0 150.0 151.0 152.0 153.0 154.0 155.0 156.0 157.0 158.0 159.0 160.0 161.0 162.0 163.0 164.0 165.0 166.0 167.0 168.0 169.0 170.0 171.0 172.0 173.0 174.0 175.0 176.0 177.0 178.0 179.0 180.0 181.0 182.0 183.0 184.0 185.0 186.0 187.0 188.0 189.0 190.0 191.0 192.0 193.0 194.0 195.0 196.0 197.0 198.0 199.0 200.0 201.0 202.0 203.0 204.0 205.0 206.0 207.0 208.0 209.0 210.0 211.0 212.0 213.0 214.0 215.0 216.0 217.0 218.0 219.0 220.0 221.0 222.0 223.0 224.0 225.0 226.0 227.0 228.0 229.0 230.0 231.0 232.0 233.0 234.0 235.0 236.0 237.0 238.0 239.0 240.0 241.0 242.0 243.0 244.0 245.0 246.0 247.0 248.0 249.0 250.0 251.0 252.0 253.0 254.0 255.0 256.0 257.0 258.0 259.0 260.0 261.0 262.0 263.0 264.0 265.0 266.0 267.0 268.0 269.0 270.0 271.0 272.0 273.0 274.0 275.0 276.0 277.0 278.0 279.0 280.0 281.0 282.0 283.0 284.0 285.0 286.0 287.0 288.0 289.0 290.0 291.0 292.0 293.0 294.0 295.0 296.0 297.0 298.0 299.0 300.0 301.0 302.0 303.0 304.0 305.0 306.0 307.0 308.0 309.0 310.0 311.0 312.0 313.0 314.0 315.0 316.0 317.0 318.0 319.0 320.0 321.0 322.0 323.0 324.0 325.0 326.0 327.0 328.0 329.0 330.0 331.0 332.0 333.0 334.0 335.0 336.0 337.0 338.0 339.0 340.0 341.0 342.0 343.0 344.0 345.0 346.0 347.0 348.0 349.0 350.0 351.0 352.0 353.0 354.0 355.0 356.0 357.0 358.0 359.0]
// @option {"label":{"zh_cn":"环带纬度细节","en_us":"Dusty Accretion Disc"},"description":{"zh_cn":"环带的细节沿纬度方向分布。","en_us":"Spreads the disc detail along its latitude."}}
#define OMNI_ACCRETIONDISC_DETAIL_ALONG_LONGITUDE 0 // [0 1]
// @option {"label":{"zh_cn":"吸积盘多普勒效应","en_us":"Accretion Disc Doppler Effect"},"description":{"zh_cn":"模拟黑洞吸积盘旋转的多普勒效应，一边更亮、一边更暗。","en_us":"Simulates the doppler shift of the rotating accretion disc, brightening one side."}}
#define OMNI_ACCRETIONDISC_DOPPLER_EFFECT 1 // [0 1]
// 主岛光源的选项、常数与阴影相机都在 `effects/world/end_island_light.glsl`，本文件只负责引入它。
// @option {"label":{"zh_cn":"风暴密度","en_us":"End Storm Density"},"description":{"zh_cn":"末地雾里带方向性的风暴部分浓度，一为现在的强度，零去掉这一层。取自 Eclipse 的同名密度。","en_us":"Density of the directional storm part of the End fog; 1 is the current strength, 0 removes it. Matches Eclipse's storm density."},"slider":true}
#define OMNI_END_FOG_STORM_DENSITY 1.0 // [0.0 0.1 0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0 5.0]
// @option {"label":{"zh_cn":"雾霭密度","en_us":"End Haze Density"},"description":{"zh_cn":"末地雾里不带方向性的雾霭部分浓度，一为现在的强度，零去掉这一层。取自 Eclipse 的同名密度。","en_us":"Density of the direction-less haze part of the End fog; 1 is the current strength, 0 removes it. Matches Eclipse's haze density."},"slider":true}
#define OMNI_END_FOG_HAZE_DENSITY 1.0 // [0.0 0.1 0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0 5.0]
// @option {"label":{"zh_cn":"涡旋空气雾","en_us":"End Vortex Volumetric Fog"},"description":{"zh_cn":"把末地雾换成一层会旋转的浓雾云：绕主岛上空旋转、越靠中心越亮，雾里还叠出光柱与雾霭。取自 Eclipse 的体积末地雾；默认关闭，关闭时画面与只有解析雾时一致。","en_us":"Turns the End fog into a rotating dense cloud that swirls around above the main island, brightest near its centre, with light columns and haze. Ported from Eclipse; off by default."}}
#define OMNI_END_VORTEX_FOG 0 // [0 1]
// @option {"label":{"zh_cn":"涡旋风暴密度","en_us":"Vortex Storm Density"},"description":{"zh_cn":"涡旋雾里带形状的风暴部分浓度，一为原程序设定值，零去掉这一层。取自 Eclipse 的末地风暴密度，与上面的解析雾密度各自独立。","en_us":"Density of the shaped storm part of the vortex; 1 is Eclipse's value, 0 removes it. Independent from the analytic fog density above."},"slider":true}
#define OMNI_END_VORTEX_STORM_DENSITY 1.0 // [0.0 0.1 0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0 5.0 10.0]
// @option {"label":{"zh_cn":"涡旋雾霭密度","en_us":"Vortex Haze Density"},"description":{"zh_cn":"涡旋雾里不带形状的雾霭部分浓度，一为原程序设定值，零去掉这一层。取自 Eclipse 的末地雾霾密度。","en_us":"Density of the shapeless haze part of the vortex; 1 is Eclipse's value, 0 removes it. Matches Eclipse's End haze density."},"slider":true}
#define OMNI_END_VORTEX_HAZE_DENSITY 1.0 // [0.0 0.1 0.5 1.0 2.0 5.0 10.0 20.0 50.0]
// @option {"label":{"zh_cn":"涡旋光柱红色","en_us":"Vortex Light Red"},"description":{"zh_cn":"雾中光柱的红色分量，取自 Eclipse 的末地主岛雾光色。","en_us":"Red channel of the fog light column; matches Eclipse's End vortex light colour."},"slider":true}
#define OMNI_END_VORTEX_LIGHT_R 0.5 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"涡旋光柱绿色","en_us":"Vortex Light Green"},"description":{"zh_cn":"雾中光柱的绿色分量，取自 Eclipse 的末地主岛雾光色。","en_us":"Green channel of the fog light column; matches Eclipse's End vortex light colour."},"slider":true}
#define OMNI_END_VORTEX_LIGHT_G 0.4 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"涡旋光柱蓝色","en_us":"Vortex Light Blue"},"description":{"zh_cn":"雾中光柱的蓝色分量，取自 Eclipse 的末地主岛雾光色。","en_us":"Blue channel of the fog light column; matches Eclipse's End vortex light colour."},"slider":true}
#define OMNI_END_VORTEX_LIGHT_B 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
// @option {"label":{"zh_cn":"涡旋环境光红色","en_us":"Vortex Ambient Red"},"description":{"zh_cn":"涡旋雾内环境光的红色分量，取自 Eclipse 的末地环境光。","en_us":"Red channel of the vortex ambient light; matches Eclipse's End ambient light."},"slider":true}
#define OMNI_END_VORTEX_AMBIENT_R 0.3 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.5 2.0]
// @option {"label":{"zh_cn":"涡旋环境光绿色","en_us":"Vortex Ambient Green"},"description":{"zh_cn":"涡旋雾内环境光的绿色分量，取自 Eclipse 的末地环境光。","en_us":"Green channel of the vortex ambient light; matches Eclipse's End ambient light."},"slider":true}
#define OMNI_END_VORTEX_AMBIENT_G 0.35 // [0.0 0.1 0.2 0.3 0.35 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.5 2.0]
// @option {"label":{"zh_cn":"涡旋环境光蓝色","en_us":"Vortex Ambient Blue"},"description":{"zh_cn":"涡旋雾内环境光的蓝色分量，取自 Eclipse 的末地环境光。","en_us":"Blue channel of the vortex ambient light; matches Eclipse's End ambient light."},"slider":true}
#define OMNI_END_VORTEX_AMBIENT_B 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.2 1.5 2.0]
#endif // 选项层结束
