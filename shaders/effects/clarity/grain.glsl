/*
胶片颗粒的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/clarity/grain.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/clarity/grain.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_CLARITY_GRAIN_INCLUDED
#define OMNI_EFFECT_CLARITY_GRAIN_INCLUDED
// @effect {"label":{"zh_cn":"胶片颗粒","en_us":"Film Grain"}}
// @option {"label":{"zh_cn":"胶片颗粒","en_us":"Film Grain"},"description":{"zh_cn":"给画面叠加随时间变化的细噪点，模拟胶片感光颗粒；默认关闭。","en_us":"Adds animated fine noise to mimic film grain; off by default."}}
#define OMNI_FILM_GRAIN 0 // [0 1]
// @option {"label":{"zh_cn":"颗粒强度","en_us":"Grain Strength"},"slider":true,"description":{"zh_cn":"颗粒的幅度，越大噪点越明显；参考值约二点五。","en_us":"Amplitude of the grain; about 2.5 is a moderate amount."}}
#define OMNI_FILM_GRAIN_STRENGTH 2.5 // [0.5 1.0 1.5 2.0 2.5 3.0 3.5 4.0 4.5 5.0 5.5 6.0 6.5 7.0 7.5 8.0 8.5 9.0 9.5 10.0]
#endif // 选项层结束
