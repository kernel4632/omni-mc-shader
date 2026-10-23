/*
氛围的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/sky/atmosphere.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/sky/atmosphere.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_SKY_ATMOSPHERE_INCLUDED
#define OMNI_EFFECT_SKY_ATMOSPHERE_INCLUDED
// @effect {"label":{"zh_cn":"氛围","en_us":"Atmosphere"}}
// @option {"label":{"zh_cn":"极光","en_us":"Aurora"},"description":{"zh_cn":"夜里高空出现极光帘幕；默认关闭，打开后才计算。","en_us":"Shows aurora curtains high in the night sky; off by default."}}
#define OMNI_AURORA 0 // [0 1]
// @option {"label":{"zh_cn":"彩虹","en_us":"Rainbow"},"description":{"zh_cn":"雨后晴天出现彩虹；默认关闭，打开后才计算。","en_us":"Shows a rainbow after rain; off by default."}}
#define OMNI_RAINBOW 0 // [0 1]
// @option {"label":{"zh_cn":"闪电照明","en_us":"Lightning Illumination"},"description":{"zh_cn":"读取加载器实际闪电强度，在雷暴闪电瞬间给附近表面、体积云和体积雾叠一层冷色闪光；这是额外功能，默认关闭，关闭时默认画面与 iterationT 一致。","en_us":"Uses the loader lightning strength to flash nearby surfaces, volumetric clouds and volumetric fog during a strike; an extra feature, off by default so the default scene matches iterationT."}}
#define OMNI_LIGHTNING 0 // [0 1]
// @option {"label":{"zh_cn":"极光强度","en_us":"Aurora Strength"},"description":{"zh_cn":"极光多亮。","en_us":"How bright the aurora is."},"slider":true}
#define OMNI_AURORA_STRENGTH 1.0 // [0.0 0.5 1.0 2.0]
// @option {"label":{"zh_cn":"极光颜色","en_us":"Aurora Colour"},"description":{"zh_cn":"正值偏绿、负值偏蓝紫。","en_us":"Positive leans green, negative leans blue-purple."},"slider":true}
#define OMNI_AURORA_TINT 0.0 // [-1.0 -0.5 0.0 0.5 1.0]
// @option {"label":{"zh_cn":"彩虹强度","en_us":"Rainbow Strength"},"description":{"zh_cn":"彩虹多清楚。","en_us":"How clear the rainbow is."},"slider":true}
#define OMNI_RAINBOW_STRENGTH 1.0 // [0.0 0.5 1.0 2.0]
// @option {"label":{"zh_cn":"闪电强度","en_us":"Lightning Strength"},"description":{"zh_cn":"打雷时闪亮多强。","en_us":"How bright the lightning flash is."},"slider":true}
#define OMNI_LIGHTNING_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
#endif // 选项层结束
