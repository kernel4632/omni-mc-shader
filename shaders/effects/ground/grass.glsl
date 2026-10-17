/*
程序化草：在草方块顶面长出会随风摆动的立体草丛，来源是 Eclipse 的着色器草地（`SHADER_GRASS`）。
调用位置：
  地形绘制主体 `rendering/terrain.glsl` 的顶点阶段准备方块编号、方块中心与“这个面是否朝上”；
  几何阶段对草方块顶面调用本文件的 `omniGrassWindOffset`、`omniGrassBladeVertex` 与 `omniGrassBlockAt` 生成草叶；
  片元阶段把方块编号与生物群系写进九号画面，供下一帧几何阶段查询隔壁方块。
可复制示例：
  `vec2 wind = omniGrassWindOffset(worldPos);`                                      取某处风在水平方向上的位移
  `float id = omniGrassBlockAt(colortex9, viewPos, gbufferProjection, screenSize);`  按视空间位置查九号画面里的方块编号
  `vec3 offset = omniGrassBladeVertex(up, side, heightMult, segment, segments, corner);` 取草叶某个角相对底部的偏移
设计原因与取舍：
  与 Eclipse 不同，本项目没有细分着色器（入口生成器不产出 `.tcs`/`.tes`），所以在几何阶段直接长出草叶，
  每个草方块顶面能长的草叶比 Eclipse 少，这是硬约束下的精简，不是效果参数。
  草叶只在主世界编译，且只在 `OMNI_SHADER_GRASS` 打开时参与；关闭时本文件不产生任何代码与采样。
  隔壁方块查询走九号画面（上一帧内容）：几何阶段拿不到邻接关系，只能按世界坐标投影到屏幕再取记录。
*/

#ifndef OMNI_GRASS_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_GRASS_INCLUDED // 置上标记。
// @effect {"label":{"zh_cn":"程序化草","en_us":"Shader grass"}}
// @option {"label":{"zh_cn":"程序化草","en_us":"Shader grass"},"description":{"zh_cn":"在草方块顶面长出会随风摆动的立体草丛。关闭时整条通路不参与编译。","en_us":"Grows wind-swept blades on grass blocks. Nothing compiles while off."}}
//#define OMNI_SHADER_GRASS
// @option {"label":{"zh_cn":"草丛密度","en_us":"Grass density"},"description":{"zh_cn":"每个草方块长几片叶子，越高越密也越慢。","en_us":"Blades per grass block; higher is denser and slower."},"values":{"0":{"zh_cn":"低","en_us":"Low"},"1":{"zh_cn":"中","en_us":"Medium"},"2":{"zh_cn":"高","en_us":"High"}}}
#define OMNI_GRASS_QUALITY 1 // [0 1 2]
// @option {"label":{"zh_cn":"草丛范围","en_us":"Grass range"},"slider":true,"description":{"zh_cn":"草丛在玩家周围多大范围内出现，越大越耗性能。","en_us":"How far around the player blades appear; larger costs more."}}
#define OMNI_GRASS_RANGE 12.0 // [6.0 8.0 10.0 12.0 16.0 24.0]
// @option {"label":{"zh_cn":"草丛高度","en_us":"Grass height"},"slider":true,"description":{"zh_cn":"草叶长多高，一为默认高度。","en_us":"How tall the blades grow; one is the default."}}
#define OMNI_GRASS_HEIGHT 1.0 // [0.5 0.75 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"草丛摆动速度","en_us":"Grass sway speed"},"slider":true,"description":{"zh_cn":"风把草丛吹得多快。","en_us":"How fast the wind moves the blades."}}
#define OMNI_GRASS_WAVY_SPEED 1.0 // [0.5 1.0 1.5 2.0]
// @option {"label":{"zh_cn":"草丛摆动幅度","en_us":"Grass sway amount"},"slider":true,"description":{"zh_cn":"草叶被风吹弯多少，零为完全不动。","en_us":"How far the blades bend in the wind; zero is still."}}
#define OMNI_GRASS_WAVY_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
// 草方块编号：本项目的 `block.properties` 把草方块编号定为八十五，与 Eclipse 一致。
// 为什么用八十五：Eclipse 的草方块就是八十五，沿用同一个数字便于和参考对照。
#define OMNI_GRASS_BLOCK_ID 85.0 // 草方块编号，几何阶段按它挑出草方块顶面。
// 内部常数：草叶横向宽度与逐段收窄比例，只影响外形，不开放给玩家。
#define OMNI_GRASS_BASE_THICKNESS 0.06 // 草叶根部的横向宽度。
#define OMNI_GRASS_THICKNESS_FALLOFF 0.7 // 每升一段草叶收窄到多少，越小尖越细。
#define OMNI_GRASS_RANDOMNESS 0.22 // 每片草叶随机弯折的幅度。
// 加载器输入与共用计算：风的时间、投影与屏幕尺寸都在这里。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"

// 草叶随风摆动：返回世界空间的水平位移；相位随世界位置变化，让整片草不同步。
// 为什么要按世界位置取相位：位置固定在世界里，镜头移动时草叶的摆法不会跟着镜头漂。
vec2 omniGrassWindOffset(vec3 worldPos){
	float time = frameTimeCounter * OMNI_GRASS_WAVY_SPEED; // 动画时间按速度选项推进。
	float gust = abs(sin(dot(vec4(frameTimeCounter, worldPos), vec4(1.0, 0.005, 0.005, 0.005))) * 0.5 + 0.72) * 0.013; // 一阵阵的风强起伏。
	vec2 wave = (sin(time * vec2(0.0063, 0.0015) * 4.0 - worldPos.xz + worldPos.y * 0.05) + 0.1) * gust; // 两个方向的波按位置错开。
	return wave * 5.0 * OMNI_GRASS_WAVY_STRENGTH; // 按摆动幅度选项放大成实际位移。
}

// 按视空间位置查九号画面里的方块编号：把位置投影到屏幕，再取那一像素红通道记录的值。
// 为什么要查画面：草阶段在几何阶段运行，拿不到隔壁方块，只能靠上一帧记下的方块编号。
// 为什么用 `texelFetch`：编号是离散标记，线性插值会把两个方块编号混出一个不存在的值。
float omniGrassBlockAt(sampler2D blockTex, vec3 viewPos, mat4 projection, vec2 screenSizeArg){
	vec4 clip = projection * vec4(viewPos, 1.0); // 视空间位置到裁剪空间。
	if (clip.w <= 0.0) return 0.0; // 相机背后没有对应像素，当作没有记录。
	vec2 uv = clip.xy / clip.w * 0.5 + 0.5; // 裁剪空间归一化到零到一。
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) return 0.0; // 出屏当作没有记录。
	return texelFetch(blockTex, ivec2(uv * screenSizeArg), 0).r * 255.0; // 红通道存的就是方块编号。
}

// 草叶某个角相对底部的偏移：草叶由几段三角带拼成，逐段升高并逐段收窄，尖端收成一点。
// `up` 是视空间里的世界竖直方向，`side` 是这一片草叶的横向宽度方向，`heightMult` 是本层高度。
// `segment` 是当前段号，`segments` 是总段数，`corner` 是这一段三角形的三个角（零底、一顶、二侧）。
vec3 omniGrassBladeVertex(vec3 up, vec3 side, float heightMult, int segment, int segments, int corner){
	float low = 0.5 * float(segment - segment % 2) * heightMult; // 本段底面的竖直高度，奇偶段共用同一层底。
	vec3 narrow = side * pow(OMNI_GRASS_THICKNESS_FALLOFF, float(segment / 2)); // 本段已经收窄到多宽。
	vec3 bottom = up * low; // 底角位置。
	vec3 top = bottom + up * heightMult; // 顶角位置。
	if (segment % 2 == 1){ bottom += narrow; top = bottom + up * heightMult; } // 奇数段从收窄处接续，形成折线。
	if (segment == segments - 1){ top = bottom + 0.5 * narrow + up * heightMult; } // 末段顶端收成尖。
	if (corner == 0) return bottom; // 底角。
	if (corner == 1) return top; // 顶角。
	return bottom + narrow; // 侧角，撑开草叶宽度。
}
#endif // 文件守卫结束。
