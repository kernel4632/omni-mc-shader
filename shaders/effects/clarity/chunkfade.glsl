/*
区块淡入的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/clarity/chunkfade.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/clarity/chunkfade.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_CLARITY_CHUNKFADE_INCLUDED
#define OMNI_EFFECT_CLARITY_CHUNKFADE_INCLUDED
// @effect {"label":{"zh_cn":"区块淡入","en_us":"Chunk fade in"}}
// @option {"label":{"zh_cn":"区块淡入","en_us":"Chunk fade in"},"values":{"0":{"zh_cn":"关闭","en_us":"Off"},"1":{"zh_cn":"淡入","en_us":"Fade in"},"2":{"zh_cn":"淡入加滑动","en_us":"Fade in + slide in"}},"description":{"zh_cn":"新加载的区块逐渐显现，而不是整块突然跳出；默认关闭。来源 Eclipse `VANILLA_CHUNK_FADING`，需要 Iris 的区块淡入特性。","en_us":"Newly loaded chunks fade in instead of popping in; off by default. From Eclipse `VANILLA_CHUNK_FADING`; needs the Iris chunk fade feature."}}
#define OMNI_CHUNK_FADE 0 // [0 1 2]
#endif // 选项层结束
