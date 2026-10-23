/*
光照的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/lighting/sunlight.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/lighting/sunlight.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_LIGHTING_SUNLIGHT_INCLUDED
#define OMNI_EFFECT_LIGHTING_SUNLIGHT_INCLUDED
// @effect {"label":{"zh_cn":"光照","en_us":"Lighting"}}
// @option {"label":{"zh_cn":"阳光强度","en_us":"Sunlight Intensity"},"description":{"zh_cn":"直射阳光的整体强度，乘在日月直射光上。","en_us":"Overall direct sunlight strength applied to the sun and moon."},"slider":true}
#define OMNI_SUNLIGHT_INTENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label":{"zh_cn":"天光强度","en_us":"Skylight Intensity"},"description":{"zh_cn":"地表接到的天空环境光强度，主要决定阴影里的亮度。","en_us":"Strength of the sky ambient light on the ground; mainly the brightness of shadows."},"slider":true}
#define OMNI_SKYLIGHT_INTENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
// @option {"label":{"zh_cn":"无光亮度","en_us":"No-light Brightness"},"description":{"zh_cn":"洞穴深处的最低环境亮度，取零会完全变黑。","en_us":"Floor ambient brightness in deep caves; zero goes fully black."},"slider":true}
#define OMNI_NOLIGHT_BRIGHTNESS 0.000005 // [0.0 0.000001 0.000002 0.000003 0.000005 0.000007 0.00001 0.000015 0.00002 0.00003 0.00005 0.00007 0.0001 0.00015 0.0002 0.0003 0.0005 0.0007 0.001]
// @option {"label":{"zh_cn":"冷色月光","en_us":"Cold Moonlight"},"description":{"zh_cn":"月光偏冷蓝，给夜晚更安静的氛围。","en_us":"Cools the moonlight toward blue for a calmer night."}}
#define OMNI_COLD_MOONLIGHT
// @option {"label":{"zh_cn":"洞穴模式","en_us":"Cave Mode"},"description":{"zh_cn":"完全看不到天空时改用一套极暗的配色，营造洞穴感。","en_us":"Uses a very dark palette when no sky is visible, for a caving look."}}
//#define OMNI_CAVE_MODE
// @option {"label":{"zh_cn":"阳光泄漏修正","en_us":"Sunlight Leak Fix"},"description":{"zh_cn":"把天光与全局光限制在天光等级较高的像素上，减少光透过方块泄漏。","en_us":"Limits sky and GI to well-lit pixels to reduce light leaking through blocks."}}
#define OMNI_SUNLIGHT_LEAK_FIX
#endif // 选项层结束
