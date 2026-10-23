/*
太阳色与辐照的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/sky/suncolor.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/sky/suncolor.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_SKY_SUNCOLOR_INCLUDED
#define OMNI_EFFECT_SKY_SUNCOLOR_INCLUDED
// @effect {"label":{"zh_cn":"太阳色与辐照","en_us":"Sun Color & Irradiance"}}
// @option {"label":{"zh_cn":"着色模式","en_us":"Color Mode"},"description":{"zh_cn":"保持现状不动画面；色温按开尔文染色；RGB 直接给三个分量。","en_us":"Keep Current leaves the sun unchanged; Temperature tints by Kelvin; RGB sets the three channels."},"values":{"0":{"zh_cn":"保持现状","en_us":"Keep Current"},"1":{"zh_cn":"色温","en_us":"Temperature"},"2":{"zh_cn":"RGB","en_us":"RGB"}}}
#define OMNI_SUN_COLOR_TYPE 0 // [0 1 2]
// @option {"label":{"zh_cn":"太阳色温","en_us":"Sun Temperature"},"description":{"zh_cn":"以 6300K 为中性基准的太阳色温，越低越暖、越高越冷；只在着色模式为色温时生效。","en_us":"Sun temperature with 6300K as the neutral reference; lower is warmer, higher is cooler; only used in Temperature mode."},"slider":true}
#define OMNI_SUN_TEMP 6300.0 // [1000.0 1100.0 1200.0 1300.0 1400.0 1500.0 1600.0 1700.0 1800.0 1900.0 2000.0 2100.0 2200.0 2300.0 2400.0 2500.0 2600.0 2700.0 2800.0 2900.0 3000.0 3100.0 3200.0 3300.0 3400.0 3500.0 3600.0 3700.0 3800.0 3900.0 4000.0 4100.0 4200.0 4300.0 4400.0 4500.0 4600.0 4700.0 4800.0 4900.0 5000.0 5100.0 5200.0 5300.0 5400.0 5600.0 5700.0 5800.0 5900.0 6000.0 6100.0 6200.0 6300.0 6400.0 6500.0 6600.0 6700.0 6800.0 6900.0 7000.0 7100.0 7200.0 7300.0 7400.0 7500.0 7600.0 7700.0 7800.0 7900.0 8000.0 8100.0 8200.0 8300.0 8400.0 8500.0 8600.0 8700.0 8800.0 8900.0 9000.0 9100.0 9200.0 9300.0 9400.0 9500.0 9600.0 9700.0 9800.0 9900.0 10000.0 15000.0 20000.0 25000.0 50000.0]
// @option {"label":{"zh_cn":"太阳颜色红","en_us":"Sun Color R"},"description":{"zh_cn":"太阳色的红色分量；只在着色模式为 RGB 时生效。","en_us":"Red channel of the sun colour; only used in RGB mode."},"slider":true}
#define OMNI_SUN_COLOR_R 1.0 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.3 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.4 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.5 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.6 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.7 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.8 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.9 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 1.0]
// @option {"label":{"zh_cn":"太阳颜色绿","en_us":"Sun Color G"},"description":{"zh_cn":"太阳色的绿色分量；只在着色模式为 RGB 时生效。","en_us":"Green channel of the sun colour; only used in RGB mode."},"slider":true}
#define OMNI_SUN_COLOR_G 0.91 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.3 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.4 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.5 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.6 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.7 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.8 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.9 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 1.0]
// @option {"label":{"zh_cn":"太阳颜色蓝","en_us":"Sun Color B"},"description":{"zh_cn":"太阳色的蓝色分量；只在着色模式为 RGB 时生效。","en_us":"Blue channel of the sun colour; only used in RGB mode."},"slider":true}
#define OMNI_SUN_COLOR_B 0.81 // [0.0 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.3 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.4 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.5 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.6 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.7 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.8 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.9 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 1.0]
// @option {"label":{"zh_cn":"太阳辐照度倍率","en_us":"Sun Illuminance"},"description":{"zh_cn":"太阳直射与太阳圆盘的亮度倍率，默认一倍与现在一致；Eclipse 的绝对辐照度不适用于本管线，这里用相对倍率。","en_us":"Brightness multiplier for direct sunlight and the sun disc; default 1 matches the current look; Eclipse's absolute value does not fit this pipeline, so this is relative."},"slider":true}
#define OMNI_SUN_ILLUMINANCE 1.0 // [0.0 0.1 0.25 0.5 0.75 1.0 1.25 1.5 2.0 2.5 3.0 4.0 5.0 7.5 10.0]
#endif // 选项层结束
