/*
程序化草的菜单选项：只声明玩家可调的选项与默认值，菜单由 options.py 扫描本文件生成。
调用位置：由 `bind/ground/grass.glsl` 引入；渲染程序通过绑定文件间接取得这些宏。
可复制示例：引用 `effects/ground/grass.glsl` 只取选项；需要算法时引用绑定文件。
设计原因与取舍：效果层只保留选项，选项名、默认值与配置格式不变；算法与宿主接线已迁到绑定层和通用库。
*/
#ifndef OMNI_EFFECT_GROUND_GRASS_INCLUDED
#define OMNI_EFFECT_GROUND_GRASS_INCLUDED
// @effect {"label":{"zh_cn":"程序化草","en_us":"Shader grass"}}
// @option {"label":{"zh_cn":"程序化草","en_us":"Shader grass"},"description":{"zh_cn":"在草方块顶面长出会随风摆动的立体草丛。关闭时整条通路不参与编译。","en_us":"Grows wind-swept blades on grass blocks. Nothing compiles while off."}}
#define OMNI_SHADER_GRASS 0 // [0 1]
// @option {"label":{"zh_cn":"草叶质量","en_us":"Grass quality"},"description":{"zh_cn":"一片草叶最多几段：低三段、中五段、高七段；越高越圆润也越慢。","en_us":"Segments per blade: Low 3, Medium 5, High 7; higher is smoother and slower."},"values":{"0":{"zh_cn":"低","en_us":"Low"},"1":{"zh_cn":"中","en_us":"Medium"},"2":{"zh_cn":"高","en_us":"High"}}}
#define OMNI_GRASS_QUALITY 1 // [0 1 2]
// @option {"label":{"zh_cn":"细分等级","en_us":"Grass density"},"description":{"zh_cn":"每个草方块顶面长几片草，越高越密也越慢；本项目没有细分着色器，用多长几片草来近似 Eclipse 的细分等级。","en_us":"Blades per grass block top; higher is denser and slower. Without tessellation shaders this approximates Eclipse's subdivision level."},"values":{"0":{"zh_cn":"低","en_us":"Low"},"1":{"zh_cn":"中","en_us":"Medium"},"2":{"zh_cn":"高","en_us":"High"},"3":{"zh_cn":"非常高","en_us":"Very high"}}}
#define OMNI_GRASS_DENSITY 1 // [0 1 2 3]
// @option {"label":{"zh_cn":"草丛范围","en_us":"Grass range"},"slider":true,"description":{"zh_cn":"草丛在玩家周围多大范围内出现，越大越耗性能。","en_us":"How far around the player blades appear; larger costs more."}}
#define OMNI_GRASS_RANGE 12.0 // [6.0 8.0 10.0 12.0 16.0 24.0]
// @option {"label":{"zh_cn":"普通草高度","en_us":"Grass base height"},"slider":true,"description":{"zh_cn":"长在草方块上的草丛高度，一为默认；草场中央会被抬高、临台阶的一侧会压低，见下面的邻接检测。来源 Eclipse `BASE_GRASS_HEIGHT`。","en_us":"Height of grass on grass blocks; one is default. Blades get taller in the middle of a field and shorter by steps, see the neighbour detection below. From Eclipse `BASE_GRASS_HEIGHT`."}}
#define OMNI_GRASS_BASE_HEIGHT 1.0 // [0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
// @option {"label":{"zh_cn":"矮草高度","en_us":"Short grass height"},"slider":true,"description":{"zh_cn":"被替换的原版矮草处长出的草丛高度，一为默认。来源 Eclipse `SHORT_GRASS_HEIGHT`。","en_us":"Height of the grass that stands in for the replaced vanilla short grass; one is default. From Eclipse `SHORT_GRASS_HEIGHT`."}}
#define OMNI_GRASS_SHORT_HEIGHT 1.0 // [0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
// @option {"label":{"zh_cn":"草丛摆动速度","en_us":"Grass sway speed"},"slider":true,"description":{"zh_cn":"风把草丛吹得多快。","en_us":"How fast the wind moves the blades."}}
#define OMNI_GRASS_WAVY_SPEED 1.0 // [0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"草丛摆动幅度","en_us":"Grass sway amount"},"slider":true,"description":{"zh_cn":"草叶被风吹弯多少，零为完全不动。","en_us":"How far the blades bend in the wind; zero is still."}}
#define OMNI_GRASS_WAVY_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"草丛随机弯曲","en_us":"Grass randomness"},"slider":true,"description":{"zh_cn":"每片草叶各自弯折的幅度，越大越杂乱，零为整齐笔直；旧版内部常数为零点二二，这里取最近的零点二。","en_us":"How much each blade bends on its own; larger is messier, zero is straight."}}
#define OMNI_GRASS_RANDOMNESS 0.2 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0]
// @option {"label":{"zh_cn":"替换原版矮草","en_us":"Replace vanilla short grass"},"description":{"zh_cn":"否：原版矮草照旧；是：隐藏范围内的原版矮草，草方块顶面照常长草；仅矮草：只把原版矮草换成程序化草，草方块顶面不长。","en_us":"Off keeps vanilla short grass; On hides it within range and grows grass on grass blocks; Short grass only replaces just the vanilla short grass with blades and leaves grass blocks bare."},"values":{"0":{"zh_cn":"否","en_us":"Off"},"1":{"zh_cn":"是","en_us":"On"},"2":{"zh_cn":"仅矮草","en_us":"Short grass only"}}}
#define OMNI_REPLACE_SHORT_GRASS 0 // [0 1 2]
// @option {"label":{"zh_cn":"草底部检测","en_us":"Grass edge detection"},"description":{"zh_cn":"草丛紧挨台阶或落差的一侧会压低草叶，避免越过隔壁地面；关时四周一样高。来源 Eclipse `GRASS_DETECT_FALLOFF`。","en_us":"Lowers blades on the side of a step or drop-off so they do not spill over the edge; off keeps all sides equal. From Eclipse `GRASS_DETECT_FALLOFF`."}}
#define OMNI_GRASS_DETECT_FALLOFF 1 // [0 1]
// @option {"label":{"zh_cn":"草侧向检测","en_us":"Grass side detection"},"description":{"zh_cn":"草丛旁边也是草或矮草时把草叶抬高，草场中央因此更高；关时只保留底部检测的压低。来源 Eclipse `GRASS_DETECT_INV_FALLOFF`。","en_us":"Raises blades when a neighbour is grass or short grass, so the middle of a field is taller; off keeps only the edge lowering. From Eclipse `GRASS_DETECT_INV_FALLOFF`."}}
#define OMNI_GRASS_DETECT_INV_FALLOFF 1 // [0 1]
#endif // 选项层结束
