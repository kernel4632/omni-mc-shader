/*
波浪模拟的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/water/wavesim.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/water/wavesim.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_WATER_WAVESIM_INCLUDED
#define OMNI_EFFECT_WATER_WAVESIM_INCLUDED
// @effect {"label":{"zh_cn":"波浪模拟","en_us":"Wave simulation"}}
// @option {"label":{"zh_cn":"波浪模拟","en_us":"Wave simulation"},"description":{"zh_cn":"玩家在水面移动时，水面被推出一圈会自己传播和衰减的波纹（Eclipse 的波浪模拟）。默认关闭；需要计算着色器与自定义图像能力，缺少时自动跳过、画面不变。","en_us":"Waves that spread and fade as the player moves on water (Eclipse's Wave Simulation). Off by default; needs compute shaders and custom images, and is skipped when they are missing."}}
#define OMNI_WAVE_SIMULATION 0 // [0 1]
// @option {"label":{"zh_cn":"模拟波纹强度","en_us":"Simulation strength"},"description":{"zh_cn":"模拟波纹盖过基础波法线的程度；调大波纹更明显。上一项关闭时不生效。","en_us":"How strongly the simulated ripples override the base wave normals; larger is more visible. Has no effect while the option above is off."},"slider":true}
#define OMNI_WAVE_SIM_STRENGTH 1.0 // [0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.4 1.6 1.8 2.0]
#endif // 选项层结束
