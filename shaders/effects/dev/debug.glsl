/*
开发调试的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/dev/debug.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/dev/debug.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_DEV_DEBUG_INCLUDED
#define OMNI_EFFECT_DEV_DEBUG_INCLUDED
// @effect {"label":{"zh_cn":"开发调试","en_us":"Development"}}
// @option {"label": {"zh_cn": "调试显示", "en_us": "Debug view"}, "description": {"zh_cn": "0：正常画面；1：几何法线；2：深度；3：光照图。用现有中间画面直接观察，关闭时画面不变。", "en_us": "0: scene; 1: geometry normals; 2: depth; 3: lightmap. Reads existing buffers directly; off keeps the scene."}, "values": {"0": {"zh_cn": "正常画面", "en_us": "Scene"}, "1": {"zh_cn": "几何法线", "en_us": "Normals"}, "2": {"zh_cn": "深度", "en_us": "Depth"}, "3": {"zh_cn": "光照图", "en_us": "Lightmap"}}}
#define OMNI_DEBUG_VIEW 0 // [0 1 2 3]
// @option {"label":{"zh_cn":"性能计时","en_us":"Frame-time bar"},"description":{"zh_cn":"在屏幕左下角画一条横条显示每帧耗时，越长越慢；这是整帧时间，不是逐效果耗时。","en_us":"Draws a bar in the bottom-left showing per-frame time; this is total frame time, not per-effect."}}
#define OMNI_PROFILER 0 // [0 1]
#endif // 选项层结束
