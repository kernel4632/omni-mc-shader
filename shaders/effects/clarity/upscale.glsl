/*
放大与锐化的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/clarity/upscale.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/clarity/upscale.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_CLARITY_UPSCALE_INCLUDED
#define OMNI_EFFECT_CLARITY_UPSCALE_INCLUDED
// @effect {"label":{"zh_cn":"放大与锐化","en_us":"Upscale & sharpen"}}
// @option {"label":{"zh_cn":"对比度自适应锐化强度","en_us":"CAS Sharpness"},"description":{"zh_cn":"零为不锐化，越大边缘越锐；太高会在高对比边缘产生振铃。","en_us":"Zero is off, higher sharpens more; too high causes ringing on high-contrast edges."},"slider":true}
#define OMNI_CAS_SHARPNESS 2 // [0 1 2 3 4 5 6 7 8 9 10]
// @option {"label":{"zh_cn":"锐化降噪","en_us":"CAS Reduce Noise Sharpening"},"description":{"zh_cn":"按邻域噪声压低锐化，避免把噪点一起放大。","en_us":"Reduces sharpening where the neighbourhood is noisy."}}
#define OMNI_CAS_DENOISE 1 // [0 1]
// @option {"label":{"zh_cn":"放大开关","en_us":"FSR 1.0"},"description":{"zh_cn":"内部分辨率低于屏幕时用边缘方向重采样放大；需要一点一八以上版本。","en_us":"Edge-directed upscale when rendering below screen size; needs 1.18 or newer."}}
#define OMNI_FSR 0 // [0 1]
// @option {"label":{"zh_cn":"放大锐化强度","en_us":"FSR Sharpness"},"description":{"zh_cn":"放大后附加锐化的强度。","en_us":"Strength of the sharpening applied after upscaling."},"slider":true}
#define OMNI_FSR_SHARPNESS 5 // [1 2 3 4 5 6 7 8 9 10]
// @option {"label":{"zh_cn":"放大降噪","en_us":"FSR Reduce Noise Sharpening"},"description":{"zh_cn":"按邻域噪声压低放大后的锐化。","en_us":"Reduces post-upscale sharpening where the neighbourhood is noisy."}}
#define OMNI_FSR_DENOISE 1 // [0 1]
#endif // 选项层结束
