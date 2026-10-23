/*
体素反射的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/reflection/voxel.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/reflection/voxel.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_REFLECTION_VOXEL_INCLUDED
#define OMNI_EFFECT_REFLECTION_VOXEL_INCLUDED
// @effect {"label":{"zh_cn":"体素反射","en_us":"Voxel reflections"}}
// @option {"label":{"zh_cn":"体素反射","en_us":"Voxel reflections"},"description":{"zh_cn":"在体素图上追踪反射，屏幕空间反射没命中的地方用体素里的方块颜色补上；只在主世界生效，缺自定义图像能力时不参与编译，关闭时画面不变。","en_us":"Traces reflections through the voxel grid and fills screen-space misses with stored block colours; overworld only, off keeps the picture unchanged."}}
#define OMNI_VOXEL_REFLECTION 0 // [0 1]
// @option {"label":{"zh_cn":"追踪距离","en_us":"Trace distance"},"description":{"zh_cn":"体素反射最远能打多远，越大越能反射远处地形，也更慢。","en_us":"How far voxel reflections reach; larger reflects more distant terrain but is slower."},"slider":true}
#define OMNI_VOXEL_REFLECTION_DISTANCE 64 // [32 48 64 96]
// @option {"label":{"zh_cn":"反射强度","en_us":"Reflection strength"},"description":{"zh_cn":"体素反射混进画面的比例，一为原样。","en_us":"How much of the voxel reflection is blended in; one is neutral."},"slider":true}
#define OMNI_VOXEL_REFLECTION_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]
#endif // 选项层结束
