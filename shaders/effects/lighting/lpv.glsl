/*
效果文件 `effects/lighting/lpv.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/lighting/lpv.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_EFFECT_LIGHTING_LPV_INCLUDED
#define OMNI_EFFECT_LIGHTING_LPV_INCLUDED
// @effect {"label":{"zh_cn":"光传播体积","en_us":"Light propagation"}}
// @option {"label":{"zh_cn":"光传播体积","en_us":"Light propagation"},"description":{"zh_cn":"在相机周围的三维格子里让彩色方块光扩散，再混回表面；缺计算能力或自定义图像时退回屏幕空间间接光。","en_us":"Diffuses colored block light in a grid around the camera and blends it into surfaces; falls back to screen space without compute or custom images."}}
#define OMNI_LPV_ENABLED 0 // [0 1]
// @option {"label":{"zh_cn":"体积大小","en_us":"Volume size"},"description":{"zh_cn":"体积格每边的方块数，越大覆盖越广、占用显存越多。","en_us":"Blocks per side of the volume; larger covers more and uses more VRAM."},"values":{"6":{"zh_cn":"小","en_us":"Small"},"7":{"zh_cn":"中","en_us":"Medium"},"8":{"zh_cn":"大","en_us":"Large"}}}
#define OMNI_LPV_SIZE 7 // [6 7 8]
// @option {"label":{"zh_cn":"光饱和度","en_us":"Light saturation"},"slider":true,"description":{"zh_cn":"传播中的颜色有多鲜艳，一百为原色。","en_us":"How vivid the propagated colors are; 100 keeps the source color."}}
#define OMNI_LPV_SATURATION 50 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// @option {"label":{"zh_cn":"透光染色","en_us":"Tint saturation"},"slider":true,"description":{"zh_cn":"玻璃等半透明方块给穿过的光染色的强度，一百为原色。","en_us":"How strongly translucent blocks tint light passing through; 100 keeps the source color."}}
#define OMNI_LPV_TINT_SATURATION 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// @option {"label":{"zh_cn":"法线偏移","en_us":"Normal offset"},"slider":true,"description":{"zh_cn":"表面法线让取样点沿法线偏移的程度，减少贴面漏光，零为关闭。","en_us":"How far the sample point moves along the surface normal; zero disables it."}}
#define OMNI_LPV_NORMAL_STRENGTH 50 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
// @option {"label":{"zh_cn":"红石光源","en_us":"Redstone lights"},"description":{"zh_cn":"让红石线、红石火把贡献彩色光。","en_us":"Lets redstone wire and torches contribute colored light."}}
#define OMNI_LPV_REDSTONE_LIGHTS
// @option {"label":{"zh_cn":"体积光强度","en_us":"LPV strength"},"slider":true,"description":{"zh_cn":"体积光混回表面的比例，一为原样。","en_us":"How much of the volume light is blended into surfaces; one is neutral."}}
#define OMNI_LPV_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0 3.0]
// @option {"label":{"zh_cn":"彩色蜡烛","en_us":"Colored candles"},"description":{"zh_cn":"让点亮的彩色蜡烛按自身颜色在体积光里发光；默认关闭，打开后蜡烛周围会带上对应颜色。","en_us":"Lets lit colored candles emit light in their own colour into the volume; off by default."}}
//#define OMNI_LPV_COLORED_CANDLES
// @option {"label":{"zh_cn":"实体光源","en_us":"Entity lights"},"description":{"zh_cn":"让烈焰人、发光鱿鱼、岩浆怪、点燃的炸药、末地水晶与光灵箭，以及信标、潮涌核心、附魔台、酿造台这些发光方块实体，还有掉在地上的火把、荧石等发光物品，在体积光里发光；只在体积光开启时生效，默认开、等于 Eclipse。","en_us":"Lets blazes, glow squid, magma cubes, primed TNT, end crystals and spectral arrows, glowing block entities (beacon, conduit, enchanting table, brewing stand) and dropped glowing items (torches, glowstone) add light to the volume; only used when the volume is on; on by default to match Eclipse."}}
#define OMNI_LPV_ENTITY_LIGHTS
// @option {"label":{"zh_cn":"雾照明","en_us":"Fog illumination"},"description":{"zh_cn":"让体积里的彩色光照亮周围的空气，洞穴里能看到带颜色的光晕；默认关闭，开启后雾会带上颜色。","en_us":"Lets the volume's colored light illuminate the surrounding air so caves show colored glow; off by default."}}
#define OMNI_LPV_VL_FOG_ILLUMINATION 0 // [0 1]
// @option {"label":{"zh_cn":"雾照明亮度","en_us":"Fog illumination brightness"},"description":{"zh_cn":"被照亮的雾的亮度，一百为基准；只在雾照明开启时生效。","en_us":"Brightness of the lit fog, 100 is the baseline; only used when Fog illumination is on."},"slider":true}
#define OMNI_LPV_VL_FOG_ILLUMINATION_BRIGHTNESS 50 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 110 120 130 140 150 160 180 200 250 300]
// @option {"label":{"zh_cn":"雾照明-手持光","en_us":"Fog illumination - handheld"},"description":{"zh_cn":"让手里的火把、荧石等手持光源也照亮空气，光色取自手持物品；只在雾照明开启时生效，默认关闭、等于 Eclipse。","en_us":"Lets held light sources such as a torch or glowstone also light up the air, using the held item's own colour; only used when Fog illumination is on; off by default to match Eclipse."}}
#define OMNI_LPV_VL_FOG_ILLUMINATION_HANDHELD 0 // [0 1]
// @option {"label":{"zh_cn":"雾照明-水下手持光","en_us":"Fog illumination - water handheld"},"description":{"zh_cn":"在水下让手持光源照亮水体，靠近火把的水先亮暖色、远处只剩青蓝；只在雾照明开启时生效，默认开、等于 Eclipse。","en_us":"Underwater, lets held light sources light up the water, warm near the torch and blue-green farther out; only used when Fog illumination is on; on by default to match Eclipse."}}
#define OMNI_LPV_VL_FOG_ILLUMINATION_HANDHELD_WATER

// --- 效果实现：宿主输入、参数换算与阶段入口 ---
/*
光传播体积（LPV）：在相机周围一圈三维格子里，让有颜色的方块光沿空气扩散，再把这份彩色间接光加回表面。
来源：Eclipse 的 floodfill 彩色光照（`lib/lpv_common.glsl`、`lib/lpv_render.glsl`、`lib/voxel_common.glsl`、
  `lib/voxel_write.glsl`、`dimensions/setup.csh` 的方块光表、`dimensions/shadowcomp.csh` 的传播、
  `lib/diffuse_lighting.glsl` 的取样），按本项目结构改写成“一个效果文件”：
  坐标映射、方块光表、传播算法、片元取样都放在本文件里。
调用位置：
  `rendering/lpv.glsl` 的计算阶段引入本文件：`setup` 阶段用 `omniLpvBlockData` 填方块光表，
  `shadowcomp` 阶段每帧推进一拍传播；
  `rendering/shadow.glsl` 的顶点阶段用 `omniVoxelBlockId` 取编号写进体素图；
  `rendering/composite.glsl` 的合成零号用 `omniLpvApply` 把体积光混进不透明表面的方块光。
可复制示例：
  `vec3 light = omniLpvApply(vanillaBlockLight, worldPos, worldNormal, lightmap);`  片元混体积光
  `uint id = omniVoxelBlockId(mc_Entity.x, at_midBlock);`                            顶点取体素编号
设计原因与取舍：
  一、体积格以相机所在格为中心、边长由 `OMNI_LPV_SIZE` 决定（六十四、一百二十八或二百五十六格），
     随玩家移动；比原来 Omni 的八格立方大得多，能覆盖一片建筑或洞穴。
  二、传播走“每帧一步、双缓冲交替”的 floodfill（来自 Eclipse shadowcomp），比一次跑固定步数更省，
     代价是首次进入新区域要几帧才填满，画面里表现为光慢慢漫开。
  三、体素编号由阴影顶点阶段写入（来自 Eclipse `voxel_write.glsl` 的 `PopulateShadowVoxel`）：
     阴影阶段本来就按阴影距离画一遍近处方块，正好用来给体素格填编号。
  四、方块光表把每个编号映射到“光色、光强、透光率、可透方向掩码”，只在计算阶段生成，片元只读。
  五、默认关闭、缺自定义图像能力时整段退回屏幕空间间接光，画面与原来完全一致。
  六、已合并的 Eclipse 细项：彩色蜡烛（`OMNI_LPV_COLORED_CANDLES`）；实体光源、方块实体光与掉落物光
     （`OMNI_LPV_ENTITY_LIGHTS` 一个开关同时管发光实体、发光方块实体与掉落的发光物品，照 Eclipse
     把它们放在同一个 `LPV_ENTITY_LIGHTS` 里）；雾照明（`OMNI_LPV_VL_FOG_ILLUMINATION`）；手持光阴影
     对应本项目的 `OMNI_HELDLIGHT_SHADOW`（见 `effects/lighting/blocklight.glsl`），对照记在
     docs/eclipse-parity.md 的「LPV/间接光」行。彩色灯（Eclipse 的独立灯具分类）未接入，见该文档。
*/


// 雾照明是否具备条件：要同时开启雾照明与体积光，并具备自定义图像能力，三者齐备才让雾去采样体积图；缺少任一项就整段退回原样。
#if OMNI_LPV_VL_FOG_ILLUMINATION && OMNI_LPV_ENABLED && defined IRIS_FEATURE_CUSTOM_IMAGES
	#define OMNI_LPV_FOG_LIGHT // 置上标记，供雾的算法体判断是否可以采样体积图。
#endif

// 相机位置、帧计数、屏幕尺寸等加载器输入先声明。
#include "/common/uniforms.glsl"
// 共用纯计算：夹取、法线工具。
#include "/common/math.glsl"
// 颜色转换与饱和度矩阵放在通用库。
#include "/omni-gfx/color.glsl"
// 手持光的三次方衰减在表面模块，供雾照明复用。
#include "/omni-gfx/surface.glsl"
// 体积光的取样、编码、坐标映射与边缘淡出都在通用库，本文件只保留纹理与体素接线。
#include "/omni-gfx/lpv.glsl"

// --- 体积常量：边长、半边、编码范围 ---
const uint omniLpvSide = uint(exp2(float(OMNI_LPV_SIZE))); // 每边单元数，六十四、一百二十八或二百五十六。
const vec3 omniLpvHalf = vec3(float(omniLpvSide)) * 0.5; // 半边长度，用来把相机放到体积中心。
const vec2 omniLpvBlockSkyRange = vec2(15.0, 24.0); // 方块光与天光的对数编码范围，照 Eclipse `lpv_common.glsl:2`。
const float omniLpvFadeLength = 10.0; // 体积边缘的淡出长度（米），照 Eclipse `diffuse_lighting.glsl:131`。
// 方块光表容量：本项目方块编号最大到七千一百零二，取八千一百九十二足够放下，比 Eclipse 的两千零四十八大。
// 放在公共区，计算阶段填表与合成阶段按编号取手持光都要用它判越界。
const uint omniLpvBlockTableSize = 8192u;

// --- 颜色编码：HSV 与线性化，照 Eclipse `lib/hsv.glsl` 与 `util.glsl` ---
// `omniRgbToHsv` 已移到 `common/math.glsl`（自发光矿石/纹饰也要用），本文件在上面已引入它。
vec3 omniHsvToRgb(vec3 c){ // 色相、饱和度、明度转回颜色。
	return ogxHsvToRgb(c); // 转换公式在通用库。
}
vec3 omniSrgbToLinear(vec3 s){ // sRGB 到线性，照 Eclipse 的近似多项式，供方块光表复原颜色。
	return ogxSrgbToLinear(s); // 多项式在通用库。
}

// --- 坐标映射：相机相对位置到体积坐标与体素下标 ---
// 体积格对齐到整数世界格：相机相对位置加 `fract(cameraPosition)` 得到“去掉相机所在格后的世界坐标”，
// 再加半边把它放到体积中心；这样玩家走动时体积按整格平移，不会拖影。
vec3 omniLpvPosition(vec3 playerPos){ return ogxLpvPosition(playerPos, fract(cameraPosition), omniLpvHalf.x); }
// 体素下标：顶点阶段写入用，和 `omniLpvPosition` 同一套对齐，取整后就是单元编号。
ivec3 omniVoxelIndex(vec3 playerPos){ return ivec3(floor(omniLpvPosition(playerPos))); }
// 归一化坐标：片元采样用，单元中心落在零到一之间，硬件做三线性插值。
vec3 omniLpvUvw(vec3 lpvPos){ return ogxLpvUvw(lpvPos, float(omniLpvSide)); }
// 体素下标是否在体积内；越界写会被丢弃，与 Eclipse `SetVoxelBlock` 一致。
bool omniVoxelInside(ivec3 cell){ return all(greaterThanEqual(cell, ivec3(0))) && all(lessThan(cell, ivec3(int(omniLpvSide)))); }

// --- 体素编号：顶点阶段把地形方块编号算成一个可写进体素图的值 ---
// 参数 `entityId` 是原版方块编号；没有编号的固体当不透光方块一，与 Eclipse `voxel_write.glsl:114` 一致。
uint omniVoxelBlockId(float entityId){
	uint voxelId = uint(entityId + 0.5); // 转成无符号整数编号。
	if (voxelId == 0u) voxelId = 1u; // 没编号的固体按不透光处理。
	return voxelId; // 交回可写进体素图的编号。
}

// --- 实体光源编号：与 `shaders/entity.properties` 给这些实体分配的编号一一对应，照 Eclipse `lib/entities.glsl` 的实体光源清单 ---
// 为什么在这里再写一遍数字：GLSL 读不到 properties 文件，阴影顶点要靠同一组常数判断“这是不是发光实体”；
// 改 `entity.properties` 的编号时必须同步改这里，否则实体光会丢失或写到错误的格子上。
const int omniLpvEntityBlaze = 7300; // 烈焰人。
const int omniLpvEntityGlowSquid = 7301; // 发光鱿鱼。
const int omniLpvEntityMagmaCube = 7302; // 岩浆怪。
const int omniLpvEntityTnt = 7303; // 点燃的炸药。
const int omniLpvEntityFireball = 7304; // 小火球。
const int omniLpvEntityEndCrystal = 200; // 末地水晶，沿用本项目已有编号。
const int omniLpvEntitySpectralArrow = 24; // 光灵箭，沿用本项目已有编号。
// 把一个实体编号映射成写进体素图的编号；不是发光实体就返回零，阴影顶点据此跳过写图。
uint omniLpvEntityVoxelId(int entity){
	if (entity == omniLpvEntityBlaze || entity == omniLpvEntityGlowSquid
		|| entity == omniLpvEntityMagmaCube || entity == omniLpvEntityTnt
		|| entity == omniLpvEntityFireball || entity == omniLpvEntityEndCrystal
		|| entity == omniLpvEntitySpectralArrow) return uint(entity); // 是发光实体就交回自身编号。
	return 0u; // 其它实体不发光，不写体素。
}

// --- 方块实体光源编号：与 `shaders/block.properties` 给这些方块实体分配的编号一一对应 ---
// 为什么单独列一份：方块实体用 `blockEntityId`（`block.properties` 编号）而不是顶点属性 `mc_Entity`，
// 阴影顶点要靠这组常数判断“这是不是发光方块实体”；改 `block.properties` 的编号时要同步改这里。
// 为什么只列发光方块实体：不发光的不写体素，光正常穿过它们，也不会误把信标光束这类大体积几何写成挡光格子。
const int omniLpvBlockBeacon = 89; // 信标，沿用本项目已有的荧石一族编号。
const int omniLpvBlockEndPortal = 119; // 末地传送门与末地折跃门，沿用本项目已有编号。
const int omniLpvBlockConduit = 7310; // 潮涌核心，新编号。
const int omniLpvBlockEnchantingTable = 7311; // 附魔台，新编号。
const int omniLpvBlockBrewingStand = 7312; // 酿造台，新编号。
// 把一个方块实体编号映射成写进体素图的编号；不是发光方块实体就返回零，阴影顶点据此跳过写图。
uint omniLpvBlockEntityVoxelId(int blockEntity){
	if (blockEntity == omniLpvBlockBeacon || blockEntity == omniLpvBlockEndPortal
		|| blockEntity == omniLpvBlockConduit || blockEntity == omniLpvBlockEnchantingTable
		|| blockEntity == omniLpvBlockBrewingStand) return uint(blockEntity); // 是发光方块实体就交回自身编号。
	return 0u; // 其它方块实体不发光，不写体素。
}

// --- 掉落物光源编号：`currentRenderedItemId` 对方块物品给 `block.properties` 编号，对其它物品给 `item.properties` 编号 ---
// 为什么在这里再列一遍编号：顶点阶段读不到只在计算阶段生成的方块光表，只能就地判断哪些编号会发光；
// 改 `omniLpvBlockData` 的光源编号时要同步改这里，否则掉落物光会丢失或写到错误编号。
// 为什么只写已知会发光的编号：普通掉落方块（石头、泥土等）不写体素，光正常穿过，避免掉在地上的普通方块挡光。
const int omniLpvItemLavaBucket = 7400; // 岩浆桶，见 `item.properties`。
const int omniLpvItemGlowstoneDust = 7401; // 荧石粉，见 `item.properties`。
uint omniLpvDroppedItemVoxelId(int item){
	if (item == omniLpvItemLavaBucket || item == omniLpvItemGlowstoneDust) return uint(item); // 非方块物品：岩浆桶、荧石粉。
	if (item == 10 || item == 50 || item == 51 || item == 89 || item == 119 || item == 213
		|| item == 7100 || item == 7101 || item == 7102) return uint(item); // 方块物品：与 `omniLpvBlockData` 的方块光源编号一致。
	#ifdef OMNI_LPV_REDSTONE_LIGHTS
	if (item == 55 || item == 76) return uint(item); // 红石线、红石火把。
	#endif
	#ifdef OMNI_LPV_COLORED_CANDLES
	if (item >= 7200 && item <= 7267) return uint(item); // 彩色蜡烛。
	#endif
	return 0u; // 其它物品不发光，不写体素。
}

// ========================= 片元取样：读体积图并混回表面 =========================
// 只在非计算阶段、开启功能且具备自定义图像能力时编译，否则整段不参与。
#if !defined(OMNI_COMPUTE) && OMNI_LPV_ENABLED && defined(IRIS_FEATURE_CUSTOM_IMAGES)
uniform sampler3D omniLpvTex1; // 偶数帧写入的一张体积图，片元只读。
uniform sampler3D omniLpvTex2; // 奇数帧写入的另一张，交替读取。
// 读一个体积样本并解码：先把存下的 RGB 当 HSV 还原，再按编码曲线缩放。
vec4 omniLpvSample(vec3 lpvPos){
	vec3 uvw = omniLpvUvw(lpvPos); // 归一化坐标。
	vec4 sample = (frameCounter % 2) == 0
		? textureLod(omniLpvTex1, uvw, 0.0) // 偶数帧读偶数帧写的那张。
		: textureLod(omniLpvTex2, uvw, 0.0); // 奇数帧反过来，保证读到完整结果。
	return ogxLpvDecodeSample(sample, omniLpvBlockSkyRange); // 解码算式在通用库，本文件只选纹理。
}
// 体积边缘淡出：越靠边越把体积光压回去，避免体积边界出现硬边。
float omniLpvRangeFalloff(vec3 lpvPos){
	return ogxLpvRangeFalloff(lpvPos, float(omniLpvSide), omniLpvFadeLength); // 三轴距离比与曲线都在通用库。
}
// 把体积光混回表面的方块光：返回替换后的方块光，供合成零号使用。
// 参数 `blockLight` 是原版方块光算出的颜色，`playerPos` 是相机相对世界位置，`worldNormal` 是世界法线。
vec3 omniLpvApply(vec3 blockLight, vec3 playerPos, vec3 worldNormal){
	vec3 normalOffset = worldNormal * (OMNI_LPV_NORMAL_STRENGTH / 100.0); // 沿法线偏移取样点，减少贴面漏光。
	vec3 lpvPos = omniLpvPosition(playerPos) + normalOffset; // 偏移后的体积坐标。
	vec4 sample = omniLpvSample(lpvPos); // 读出彩色方块光与天光。
	float falloff = omniLpvRangeFalloff(lpvPos); // 体积边缘淡出。
	return ogxLpvApply(blockLight, sample, falloff, OMNI_LPV_STRENGTH); // 混合权重在通用库。
}

// --- 手持灯光：把手中光源的颜色与范围从光表取出来，照亮空气与水下雾 ---
// 只在雾照明与对应手持选项同时开启时才定义，避免默认配置里出现无人调用的函数。
// 为什么不用体积图：手持光源跟着玩家走、也不会被阴影阶段写进体素，而光表里本来就存着每个物品的光色与范围，
// 直接按手持物品编号读表最省，也与 Eclipse `diffuse_lighting.glsl:74` 的 `GetHandLight` 同一套做法。
#if defined OMNI_LPV_FOG_LIGHT && (OMNI_LPV_VL_FOG_ILLUMINATION_HANDHELD || defined OMNI_LPV_VL_FOG_ILLUMINATION_HANDHELD_WATER)
uniform usampler1D omniLpvBlocksTex; // 方块光表按整数采样器读，与计算阶段写的图像 `omniLpvBlocks` 是同一张纹理。
// 把打包在低字里的光色与范围拆出来：按字节顺序还原四个零到一分量，避免依赖打包扩展。
vec4 omniLpvUnpackColorRange(uint packed){
	return vec4(float(packed & 0xFFu), float((packed >> 8u) & 0xFFu), float((packed >> 16u) & 0xFFu), float(packed >> 24u)) / 255.0;
}
// 求一个手持物品在某点留下的光：读光表得到颜色与范围，再按离玩家的距离三次方衰减，返回零到一的颜色。
// 为什么按距离三次方：照 Eclipse，光源范围外直接归零，越靠近玩家越亮。
vec3 omniLpvHandLight(int itemId, vec3 playerPos){
	if (itemId <= 0) return vec3(0.0); // 手上没有物品就不发光。
	uvec2 row = (uint(itemId) >= omniLpvBlockTableSize) ? uvec2(0u) : texelFetch(omniLpvBlocksTex, itemId, 0).rg; // 越界按零光处理，否则精确取表项。
	vec4 colorRange = omniLpvUnpackColorRange(row.x); // 低字：光色三相与光照范围。
	float lightRange = colorRange.a * 255.0; // 范围还原成格数。
	if (lightRange <= 0.0) return vec3(0.0); // 不发光物品直接返回。
	return ogxHandLight(omniSrgbToLinear(colorRange.rgb), lightRange, playerPos, vec3(0.0)); // 衰减在通用库，相机偏移为零。
}
#endif // 手持灯光结束。
#endif // 片元取样结束。

// ========================= 顶点写体素：阴影顶点阶段把方块编号写进体素图 =========================
// 只在阴影顶点阶段编译；远景阴影不写，因为它的几何和近景阴影不同源。
// 为什么同时接受体积光与体素反射两个开关：编号图是两者共用的，谁打开都要有这张图，缺一就补不了。
#if !defined(OMNI_COMPUTE) && defined(OMNI_VERTEX) && defined(OMNI_SHADOW_PASS) && !defined(OMNI_DH_SHADOW_PASS) && (OMNI_LPV_ENABLED || OMNI_VOXEL_REFLECTION) && defined(IRIS_FEATURE_CUSTOM_IMAGES)
layout(r16ui) uniform restrict uimage3D omniLpvVoxel; // 体素编号图，阴影顶点写、计算只读。
// 把方块编号写进对应体素格，越界丢弃；照 Eclipse `SetVoxelBlock`。
void omniVoxelStore(ivec3 coord, uint blockId){
	if (!omniVoxelInside(coord)) return; // 越界不写，体积外的几何不参与。
	imageStore(omniLpvVoxel, coord, uvec4(blockId)); // 写入编号。
}
#endif // 顶点写体素结束。

// ========================= 计算阶段：方块光表与传播 =========================
// 只有计算阶段、开启功能且具备自定义图像能力时才编译下面的图像、光表与传播函数。
#if defined(OMNI_COMPUTE) && OMNI_LPV_ENABLED && defined(IRIS_FEATURE_CUSTOM_IMAGES)
layout(rgba8) uniform restrict image3D omniLpv1; // 传播缓冲之一（偶数帧写）。
layout(rgba8) uniform restrict image3D omniLpv2; // 另一个缓冲（奇数帧写）。
layout(r16ui) uniform restrict uimage3D omniLpvVoxel; // 体素编号，阴影顶点阶段写入。
layout(rg32ui) uniform uimage1D omniLpvBlocks; // 方块光表，`setup` 阶段一次填好，传播阶段只读。

// --- 饱和度矩阵：让光色按玩家设置变鲜艳或变灰，照 Eclipse `setup.csh:39` ---
mat4 omniLpvSaturationMatrix(float saturation){
	return ogxSaturationMatrix(saturation); // 矩阵在通用库。
}

// --- 蜡烛颜色：照 Eclipse `dimensions/setup.csh:12-33` 的 `LightColor_Candles_*` ---
// 为什么按下标查颜色：蜡烛共十七种颜色，方块编号在光表里按颜色连续排布，减去起始编号再除以四就是颜色下标。
vec3 omniLpvCandleColor(uint index){
	if (index == 0u)  return vec3(1.000, 0.400, 0.100); // 普通蜡烛。
	if (index == 1u)  return vec3(0.200); // 黑色。
	if (index == 2u)  return vec3(0.000, 0.259, 1.000); // 蓝色。
	if (index == 3u)  return vec3(0.459, 0.263, 0.149); // 棕色。
	if (index == 4u)  return vec3(0.000, 0.839, 0.839); // 青色。
	if (index == 5u)  return vec3(0.329, 0.357, 0.388); // 灰色。
	if (index == 6u)  return vec3(0.263, 0.451, 0.000); // 绿色。
	if (index == 7u)  return vec3(0.153, 0.686, 1.000); // 淡蓝色。
	if (index == 8u)  return vec3(0.631, 0.627, 0.624); // 淡灰色。
	if (index == 9u)  return vec3(0.439, 0.890, 0.000); // 黄绿色。
	if (index == 10u) return vec3(0.757, 0.098, 0.812); // 品红色。
	if (index == 11u) return vec3(1.000, 0.459, 0.000); // 橙色。
	if (index == 12u) return vec3(1.000, 0.553, 0.718); // 粉色。
	if (index == 13u) return vec3(0.569, 0.000, 1.000); // 紫色。
	if (index == 14u) return vec3(0.859, 0.000, 0.000); // 红色。
	if (index == 15u) return vec3(1.000); // 白色。
	if (index == 16u) return vec3(1.000, 0.878, 0.000); // 黄色。
	return vec3(1.000, 0.400, 0.100); // 表外编号退回普通蜡烛色，正常不会走到。
}

// --- 方块光表：编号到光色、光强、透光率与可透方向，来源 Eclipse `dimensions/setup.csh:73-1220` ---
// 本表用本项目 `block.properties` 的编号；Eclipse 用另一套编号，这里逐类对照其颜色与光强搬过来。
uvec2 omniLpvBlockData(uint id){
	vec3 lightColor = vec3(0.0); // 该方块发出的光色，零表示不发光。
	float lightRange = 0.0; // 发光强度，换算成格数。
	float mixWeight = 0.0; // 透光率：零为不透光（挡光），一为全透。
	uint mixMask = 0xFFFFu; // 六个方向的可透掩码，默认全通，由不透光率把它压到零。
	vec3 tintColor = vec3(1.0); // 给穿过的光染的色。

	// --- 透光方块：让光按比例或颜色穿过，编号见本项目 `block.properties` ---
	if (id == 8u) mixWeight = 0.8; // 水：大部分透过，颜色基本不染。
	else if (id == 79u) mixWeight = 0.5; // 冰：透过一半。
	else if (id == 95u) mixWeight = 1.0; // 染色玻璃：本项目把所有颜色合成一个编号，统一按全透处理（近似，未逐色染光）。
	else if (id == 12u || id == 7000u || id == 7010u || id == 7011u || id == 7020u || id == 7021u || id == 7040u) mixWeight = 0.9; // 植物：几乎全透（十二是单独的矮草）。
	else if (id == 7030u) mixWeight = 0.5; // 树叶：透一半，光穿过会变柔。

	// --- 方块光源：颜色与光强照 Eclipse 同名条目 ---
	if (id == 10u) { lightColor = vec3(0.959, 0.302, 0.106); lightRange = 15.0; } // 岩浆（Eclipse `setup.csh:568`）。
	if (id == 50u) { lightColor = vec3(0.839, 0.541, 0.200); lightRange = 14.0; mixWeight = 0.8; } // 火把一族与点燃的营火（`setup.csh:562-814`）。
	if (id == 51u) { lightColor = vec3(0.864, 0.598, 0.348); lightRange = 15.0; mixWeight = 1.0; } // 火与被点亮的铜灯（`setup.csh:510`）。
	if (id == 89u) { lightColor = vec3(0.747, 0.594, 0.326); lightRange = 15.0; } // 荧石一族：荧石、红石灯、信标、海晶灯、灯笼、蘑菇灯、蛙鸣灯（合并编号，取荧石色为近似）。
	if (id == 119u) { lightColor = vec3(0.502, 0.165, 0.831); lightRange = 11.0; mixWeight = 1.0; } // 末地传送门与末地折跃门（`setup.csh:499,957`）。
	if (id == 213u) { lightColor = vec3(0.747, 0.323, 0.110); lightRange = 3.0; } // 岩浆块（`setup.csh:630`）。
	if (id == 7100u) { lightColor = vec3(0.100, 0.600, 1.000); lightRange = 10.0; mixWeight = 0.8; } // 灵魂火一族（`setup.csh:785-798`）。
	if (id == 7101u) { lightColor = vec3(0.464, 0.227, 0.788); lightRange = 5.0; mixWeight = 0.4; } // 紫水晶（`setup.csh:101-117`）。
	if (id == 7102u) { lightColor = vec3(1.000, 0.700, 0.600); lightRange = 4.0; } // 氧化铜灯（`setup.csh:480`）。

	// --- 红石光源：只有开关打开时才发光，照 Eclipse `LPV_REDSTONE_LIGHTS` ---
	#ifdef OMNI_LPV_REDSTONE_LIGHTS
	if (id == 55u) { lightColor = vec3(0.939, 0.305, 0.164); lightRange = 7.0; mixWeight = 1.0; } // 红石线（`setup.csh:662-736` 取最高档）。
	if (id == 76u) { lightColor = vec3(0.939, 0.305, 0.164); lightRange = 7.0; mixWeight = 0.9; } // 红石火把（`setup.csh:654`）。
	#endif

	// --- 彩色蜡烛：颜色照 Eclipse `setup.csh:136-446`，光强按蜡烛数量一支三格、四支十二格；编号见 `block.properties` ---
	// 为什么按下标算颜色与数量：七十二个编号按颜色四连排，减起始编号后除以四得颜色下标、取余得数量。
	#ifdef OMNI_LPV_COLORED_CANDLES
	if (id >= 7200u && id <= 7267u){
		uint candleIndex = (id - 7200u) / 4u; // 颜色下标，零到十六。
		uint candleCount = (id - 7200u) % 4u; // 蜡烛数量，零到三对应一至四支。
		lightColor = omniLpvCandleColor(candleIndex); // 取该颜色。
		lightRange = 3.0 * float(candleCount + 1u); // 一支三格、四支十二格。
	}
	#endif

	// --- 实体光源：颜色与光强照 Eclipse `setup.csh:1161-1197`，编号来自 `entity.properties` ---
	#ifdef OMNI_LPV_ENTITY_LIGHTS
	if (id == uint(omniLpvEntityBlaze)) { lightColor = vec3(1.000, 0.592, 0.000); lightRange = 8.0; } // 烈焰人。
	if (id == uint(omniLpvEntityGlowSquid)) { lightColor = vec3(0.180, 0.675, 0.761); lightRange = 6.0; mixWeight = 0.5; } // 发光鱿鱼。
	if (id == uint(omniLpvEntityMagmaCube)) { lightColor = vec3(0.747, 0.323, 0.110); lightRange = 9.0; } // 岩浆怪。
	if (id == uint(omniLpvEntityTnt)) { lightColor = vec3(1.0); lightRange = 8.0; } // 点燃的炸药。
	if (id == uint(omniLpvEntityFireball)) { lightColor = vec3(0.000, 1.000, 0.000); lightRange = 8.0; mixWeight = 1.0; } // 小火球。
	if (id == uint(omniLpvEntityEndCrystal)) { lightColor = vec3(1.0, 0.0, 1.0); lightRange = 10.0; } // 末地水晶。
	if (id == uint(omniLpvEntitySpectralArrow)) { lightColor = vec3(0.839, 0.541, 0.2); lightRange = 8.0; mixWeight = 1.0; } // 光灵箭。
	#endif

	// --- 方块实体光源：颜色与光强照 Eclipse `setup.csh`，编号来自 `block.properties` 的方块实体编号与 `omniLpvBlockEntityVoxelId` ---
	// 信标与末地传送门已在上面按荧石与末地传送门编号发光；这里补上潮涌核心、附魔台与酿造台。
	#ifdef OMNI_LPV_ENTITY_LIGHTS
	if (id == uint(omniLpvBlockConduit)) { lightColor = vec3(1.0); lightRange = 15.0; } // 潮涌核心（`setup.csh:488`）。
	if (id == uint(omniLpvBlockEnchantingTable)) { lightColor = vec3(0.416, 0.509, 0.979); lightRange = 10.0; mixWeight = 0.1; } // 附魔台（`setup.csh:130`）。
	if (id == uint(omniLpvBlockBrewingStand)) { lightColor = vec3(0.636, 0.509, 0.179); lightRange = 1.0; mixWeight = 0.8; } // 酿造台（`setup.csh:124`）。

	// --- 掉落物光源：只处理非方块物品（方块物品在 `omniLpvBlockData` 里已按方块编号发光），颜色与光强照 Eclipse `setup.csh` ---
	if (id == uint(omniLpvItemLavaBucket)) { lightColor = vec3(0.759, 0.302, 0.106); lightRange = 8.0; } // 岩浆桶（`setup.csh:572`）。
	if (id == uint(omniLpvItemGlowstoneDust)) { lightColor = vec3(0.747, 0.594, 0.326); lightRange = 8.0; } // 荧石粉（`setup.csh:552`）。
	#endif

	// --- 打包：光色与光强打进低字，染色与掩码打进高字，照 Eclipse `setup.csh:1216` ---
	const float saturationF = OMNI_LPV_SATURATION / 100.0; // 玩家设置的光饱和。
	mat4 matSaturation = omniLpvSaturationMatrix(saturationF); // 光色饱和度矩阵。
	lightColor = (matSaturation * vec4(lightColor, 1.0)).rgb; // 应用光饱和。
	const float tintSaturationF = OMNI_LPV_TINT_SATURATION / 100.0; // 玩家设置的染色饱和。
	mat4 matTintSaturation = omniLpvSaturationMatrix(tintSaturationF); // 染色饱和度矩阵。
	tintColor = (matTintSaturation * vec4(tintColor, 1.0)).rgb; // 应用染色饱和。
	tintColor *= mixWeight; // 透光率折进染色：不透光方块染色归零，等于把光挡死。

	if (lightRange > 0.0) lightRange += 1.0; // 和 Eclipse 一样给发光方块补一格，光晕更自然。
	uint lightColorRange = packUnorm4x8(vec4(lightColor, lightRange / 255.0)); // 光色三相 + 光强。
	uint tintColorMask = packUnorm4x8(vec4(tintColor, 0.0)) | (mixMask << 24); // 染色三相 + 方向掩码。
	return uvec2(lightColorRange, tintColorMask); // 交回一个表项。
}

// --- 传播：读相邻体积值，按掩码与染色混合，再叠本格自发光的 floodfill 一步 ---
// 读上一帧写的一张体积图并解码成与写入端同口径的线性值，照 Eclipse `shadowcomp.csh:39`。
vec4 omniLpvReadAt(ivec3 coord){
	if (any(lessThan(coord, ivec3(0))) || any(greaterThanEqual(coord, ivec3(int(omniLpvSide))))) return vec4(0.0); // 越界当没有光。
	vec4 texel = (frameCounter % 2) == 0 ? imageLoad(omniLpv2, coord) : imageLoad(omniLpv1, coord); // 读上一帧写的那张。
	return ogxLpvDecode(texel, omniLpvBlockSkyRange); // 对数反解与颜色还原在通用库。
}
// 把传播结果按同一套编码写回本帧的一张体积图，照 Eclipse `shadowcomp.csh:164`。
vec4 omniLpvEncode(vec4 value){
	return ogxLpvEncode(value, omniLpvBlockSkyRange); // 对数编码在通用库，本文件不重复算式。
}
// 读一个方块编号的光表项；越界或没登记时按不透光的空项处理。
uvec2 omniLpvBlockRow(uint blockId){
	if (blockId == 0u || blockId >= omniLpvBlockTableSize) return uvec2(0u, 0xFFFF0000u); // 空编号与表外编号按不透光。
	return imageLoad(omniLpvBlocks, int(blockId)).rg; // 读光表。
}
// 读体素图里的一个方块编号，越界返回空气零，照 Eclipse `shadowcomp.csh:53`。
uint omniVoxelRead(ivec3 coord){
	if (!omniVoxelInside(coord)) return 0u; // 越界当空气。
	return imageLoad(omniLpvVoxel, coord).r; // 读编号。
}
#endif // 计算阶段结束。
// --- Eclipse LPV 兼容层：参考直接读固定体积边长的半格偏移 ---
vec3 GetLpvPosition(vec3 playerPos){
	return playerPos + vec3(float(omniLpvSide)) / 2.0; // omniLpvSide 是当前 LPV 的每边格数。
}
float GetLpvSkyLight(vec4 lpvSample){ return ogxLpvSkyLight(lpvSample); }
#endif // OMNI_EFFECT_LIGHTING_LPV_INCLUDED
