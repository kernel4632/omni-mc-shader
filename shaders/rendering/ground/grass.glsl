/*
程序化草的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/ground/grass.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_RENDER_GROUND_GRASS_INCLUDED
#define OMNI_RENDER_GROUND_GRASS_INCLUDED
#include "/effects/ground/grass.glsl"
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
  `vec3 weights = omniGrassBladeBarycentric(blade, count);`                          取一片草在顶面三角形内的重心位置
设计原因与取舍：
  与 Eclipse 不同，本项目没有细分着色器（入口生成器不产出 `.tcs`/`.tes`），改用「同一顶面按密度多长几片草」来近似细分等级，
  每个草方块顶面能长的草叶比 Eclipse 少，这是硬约束下的精简，不是效果参数。
  Eclipse 的「替换原版矮草」在这里靠一个八位内的矮草编号识别：九号画面是八位画面，只有零到 255 之间的编号存进再读回不丢，
  所以矮草编号取 Eclipse 同款的 12，而不是植物用的 7000 以上编号段。
  草叶只在主世界编译，且只在 `OMNI_SHADER_GRASS` 打开时参与；关闭时本文件不产生任何代码与采样。
  隔壁方块查询走九号画面（上一帧内容）：几何阶段拿不到邻接关系，只能按世界坐标投影到屏幕再取记录。
  照 Eclipse 补齐三处：替换原版矮草的「仅矮草」第三档（只把矮草换成草，草方块顶面不长）、
  两套高度 `OMNI_GRASS_BASE_HEIGHT`/`OMNI_GRASS_SHORT_HEIGHT`（普通草与矮草处分开调），
  以及邻接压低 `OMNI_GRASS_DETECT_FALLOFF`/`OMNI_GRASS_DETECT_INV_FALLOFF`（临台阶压低、旁边有草抬高）。
*/

// 草方块编号：本项目的 `block.properties` 把草方块编号定为八十五，与 Eclipse 一致。
// 为什么用八十五：Eclipse 的草方块就是八十五，沿用同一个数字便于和参考对照。
#define OMNI_GRASS_BLOCK_ID 85.0 // 草方块编号，几何阶段按它挑出草方块顶面。
// 矮草编号：本项目 `block.properties` 把 `grass` 与 `short_grass` 单独登记成十二，与 Eclipse 一致。
// 为什么单独编号：原版矮草与蕨、花共用一个植物编号，无法区分，替换时要单独认出矮草只能给它自己的编号。
#define OMNI_SHORT_GRASS_BLOCK_ID 12.0 // 矮草编号，顶点阶段按它隐藏原版矮草模型。
// 内部常数：草叶横向宽度与逐段收窄比例，只影响外形，不开放给玩家。
#define OMNI_GRASS_BASE_THICKNESS 0.06 // 草叶根部的横向宽度。
#define OMNI_GRASS_THICKNESS_FALLOFF 0.7 // 每升一段草叶收窄到多少，越小尖越细。
// 质量换算成一片草叶的最大段数：低三段、中五段、高七段；几何阶段按距离在它以下取段数。
#if OMNI_GRASS_QUALITY == 2
#define OMNI_GRASS_SEGMENTS 7 // 高：一片最多七段。
#elif OMNI_GRASS_QUALITY == 1
#define OMNI_GRASS_SEGMENTS 5 // 中：一片最多五段。
#else
#define OMNI_GRASS_SEGMENTS 3 // 低：一片最多三段。
#endif
// 密度换算成一个顶面长几片草：低一片、中两片、高三片、非常高四片。
// 为什么这样取：一个顶面由两个三角形各长一遍，实际每方块片数是这里的两倍，四片已能填满大半个顶面。
#if OMNI_GRASS_DENSITY == 3
#define OMNI_GRASS_BLADES 4 // 非常高：每个三角形四片。
#elif OMNI_GRASS_DENSITY == 2
#define OMNI_GRASS_BLADES 3 // 高：每个三角形三片。
#elif OMNI_GRASS_DENSITY == 1
#define OMNI_GRASS_BLADES 2 // 中：每个三角形两片。
#else
#define OMNI_GRASS_BLADES 1 // 低：每个三角形一片，与旧版一致。
#endif
// 几何阶段顶点上限：三个基准顶点，加每片草（密度）乘每片段数乘每段三点。
// 为什么逐个列出：几何阶段的布局只接受字面量，预处理器的算术表达式会被判成非字面量而报错。
#if OMNI_GRASS_DENSITY == 3
	#if OMNI_GRASS_QUALITY == 2
	#define OMNI_GRASS_MAX_VERTICES 87 // 非常高密度、高质量：四片乘七段。
	#elif OMNI_GRASS_QUALITY == 1
	#define OMNI_GRASS_MAX_VERTICES 63 // 非常高密度、中质量：四片乘五段。
	#else
	#define OMNI_GRASS_MAX_VERTICES 39 // 非常高密度、低质量：四片乘三段。
	#endif
#elif OMNI_GRASS_DENSITY == 2
	#if OMNI_GRASS_QUALITY == 2
	#define OMNI_GRASS_MAX_VERTICES 66 // 高密度、高质量：三片乘七段。
	#elif OMNI_GRASS_QUALITY == 1
	#define OMNI_GRASS_MAX_VERTICES 48 // 高密度、中质量：三片乘五段。
	#else
	#define OMNI_GRASS_MAX_VERTICES 30 // 高密度、低质量：三片乘三段。
	#endif
#elif OMNI_GRASS_DENSITY == 1
	#if OMNI_GRASS_QUALITY == 2
	#define OMNI_GRASS_MAX_VERTICES 45 // 中密度、高质量：两片乘七段。
	#elif OMNI_GRASS_QUALITY == 1
	#define OMNI_GRASS_MAX_VERTICES 33 // 中密度、中质量：两片乘五段。
	#else
	#define OMNI_GRASS_MAX_VERTICES 21 // 中密度、低质量：两片乘三段。
	#endif
#else
	#if OMNI_GRASS_QUALITY == 2
	#define OMNI_GRASS_MAX_VERTICES 24 // 低密度、高质量：一片乘七段。
	#elif OMNI_GRASS_QUALITY == 1
	#define OMNI_GRASS_MAX_VERTICES 18 // 低密度、中质量：一片乘五段。
	#else
	#define OMNI_GRASS_MAX_VERTICES 12 // 低密度、低质量：一片乘三段。
	#endif
#endif
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

// 一片草在顶面三角形内的重心位置：三角形三个角各配一个权重，加起来是一，用来把同一顶面的几片草摊开。
// 为什么要摊开：一个顶面多长几片草时，若都放到面中心会重叠成一丛，摊到边中点与中心才填得均匀。
// `blade` 是这一片草的序号，`count` 是本顶面一共几片；取值都来自 `OMNI_GRASS_BLADES`，是编译期常数。
vec3 omniGrassBladeBarycentric(int blade, int count){
	if (count <= 1 || blade >= 3) return vec3(1.0 / 3.0); // 只有一片、或第四片时放面中心。
	if (blade == 0) return vec3(0.5, 0.5, 0.0); // 第一片压向第一条边中点。
	if (blade == 1) return vec3(0.0, 0.5, 0.5); // 第二片压向第二条边中点。
	return vec3(0.5, 0.0, 0.5); // 第三片压向第三条边中点。
}
#endif // OMNI_RENDER_GROUND_GRASS_INCLUDED
