/*
远景的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/world/world.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/world/world.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_WORLD_WORLD_INCLUDED
#define OMNI_EFFECT_WORLD_WORLD_INCLUDED
// @effect {"label":{"zh_cn":"远景","en_us":"Distance"}}
// @option {"label":{"zh_cn":"地形剔除","en_us":"Terrain Culling"},"description":{"zh_cn":"剔除靠近玩家的远景区块，减少和正常区块的混叠；可能让地形出现空缺。","en_us":"Culls distant chunks near the player to reduce overlap with normal chunks; may leave gaps."}}
#define OMNI_DH_TERRAIN_CULLING 1 // [0 1]
// @option {"label":{"zh_cn":"纹理噪声","en_us":"Apply Texture Noise"},"description":{"zh_cn":"给远景表面加逐块噪声，打散纹理感。","en_us":"Adds per-block noise to distant surfaces to break up the texture."}}
#define OMNI_DH_TEXTURE_NOISE
// @option {"label":{"zh_cn":"噪声缩放","en_us":"Noise Scale"},"description":{"zh_cn":"噪声网格的密度，越大噪声越细。","en_us":"Density of the noise grid; higher is finer."},"slider":true}
#define OMNI_DH_TEXTURE_NOISE_STEPS 4.0 // [2.0 4.0 8.0 16.0 32.0]
// @option {"label":{"zh_cn":"噪声强度","en_us":"Noise Strength"},"description":{"zh_cn":"噪声压暗表面的强度。","en_us":"How strongly the noise darkens the surface."},"slider":true}
#define OMNI_DH_TEXTURE_NOISE_STRENGTH 0.07 // [0.01 0.015 0.02 0.03 0.05 0.07 0.1 0.15 0.2 0.3 0.5 0.7 1.0]
// @option {"label":{"zh_cn":"区块淡入","en_us":"Distant Chunk Fading"},"description":{"zh_cn":"在远景与近景交界处按距离随机淡出远景区块，减少硬边。零为关闭，一淡出地形与水，二连远景阴影也淡出。默认关闭，画面与不加这项时一致。","en_us":"Randomly fades distant chunks near the boundary to soften hard edges. 0 off, 1 terrain and water, 2 also distant shadows. Off by default."},"values":{"0":{"zh_cn":"关闭","en_us":"Off"},"1":{"zh_cn":"地形与水","en_us":"Terrain & Water"},"2":{"zh_cn":"含阴影","en_us":"With Shadows"}}}
#define OMNI_DH_CHUNK_FADING 0 // [0 1 2]
#endif // 选项层结束
