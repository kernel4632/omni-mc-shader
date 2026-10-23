/*
反射的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/reflection/reflection.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/reflection/reflection.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_REFLECTION_REFLECTION_INCLUDED
#define OMNI_EFFECT_REFLECTION_REFLECTION_INCLUDED
// @effect {"label":{"zh_cn":"反射","en_us":"Reflections"}}
// @option {"label":{"zh_cn":"光线步进质量","en_us":"Ray steps"},"description":{"zh_cn":"一次反射最多走多少步，越大越不容易漏掉远处几何，也更慢。","en_us":"Maximum steps per reflection ray; higher misses less distant geometry but is slower."},"slider":true}
#define OMNI_RAYTRACE_QUALITY 16 //[8 12 16 24 32 64 128 256 512]
// @option {"label":{"zh_cn":"细化步数","en_us":"Refinement steps"},"description":{"zh_cn":"命中后二分细化的次数，越大交点越准。原程序的范围注释缺右括号，这里补全。","en_us":"Bisection steps after a hit; higher is more accurate. The original range comment was missing its closing bracket, fixed here."},"slider":true}
#define OMNI_RAYTRACE_REFINEMENT_STEPS 5 //[2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32]
// @option {"label":{"zh_cn":"深度差阈值","en_us":"Depth difference"},"description":{"zh_cn":"命中判定的相对深度差阈值，越小越严格。","en_us":"Relative depth-difference threshold for a hit; smaller is stricter."},"slider":true}
#define OMNI_RAYTRACE_ZDIFF_THRESHOLD 0.2 //[0.05 0.1 0.15 0.2 0.3 0.4 0.5]
// @option {"label":{"zh_cn":"远景反射","en_us":"Distant reflections"},"description":{"zh_cn":"让屏幕空间反射也能命中远景地形；关闭后反射只打到近景几何，远景处反射天空。默认开启，与原来一致。来源 Eclipse 的 DH_SCREENSPACE_REFLECTIONS。","en_us":"Lets screen-space reflections hit distant terrain; when off, rays only hit near geometry and reflect the sky over distant chunks. On by default. Ports Eclipse's DH_SCREENSPACE_REFLECTIONS."}}
#define OMNI_DH_SSR 1 // [0 1]
#endif // 选项层结束
