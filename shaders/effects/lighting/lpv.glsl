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
  六、未合并：彩色蜡烛、彩色灯、实体光、雾照明、手持阴影这些 Eclipse 细项，逐条记在 docs/eclipse-parity.md。
*/
#ifndef OMNI_LPV // 只引入一次，重复引用会让选项与函数重复定义。
#define OMNI_LPV // 置上标记。

// @effect {"label":{"zh_cn":"光传播体积","en_us":"Light propagation"}}
// @option {"label":{"zh_cn":"光传播体积","en_us":"Light propagation"},"description":{"zh_cn":"在相机周围的三维格子里让彩色方块光扩散，再混回表面；缺计算能力或自定义图像时退回屏幕空间间接光。","en_us":"Diffuses colored block light in a grid around the camera and blends it into surfaces; falls back to screen space without compute or custom images."}}
//#define OMNI_LPV_ENABLED
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

// 相机位置、帧计数、屏幕尺寸等加载器输入先声明。
#include "/common/uniforms.glsl"
// 共用纯计算：夹取、法线工具。
#include "/common/math.glsl"

// --- 体积常量：边长、半边、编码范围 ---
const uint omniLpvSide = uint(exp2(float(OMNI_LPV_SIZE))); // 每边单元数，六十四、一百二十八或二百五十六。
const vec3 omniLpvHalf = vec3(float(omniLpvSide)) * 0.5; // 半边长度，用来把相机放到体积中心。
const vec2 omniLpvBlockSkyRange = vec2(15.0, 24.0); // 方块光与天光的对数编码范围，照 Eclipse `lpv_common.glsl:2`。
const float omniLpvFadeLength = 10.0; // 体积边缘的淡出长度（米），照 Eclipse `diffuse_lighting.glsl:131`。

// --- 颜色编码：HSV 与线性化，照 Eclipse `lib/hsv.glsl` 与 `util.glsl` ---
vec3 omniRgbToHsv(vec3 c){ // 颜色转色相、饱和度、明度。
	const vec4 K = vec4(0.0, -1.0, 2.0, -3.0) / 3.0; // 极值组合的基向量。
	const float e = 1.0e-10; // 防止除零的极小量。
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g)); // 按蓝绿大小选中间通道。
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r)); // 再按红与最大值选主通道。
	float d = q.x - min(q.w, q.y); // 最大值与最小值之差就是饱和度分子。
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x); // 交回色相、饱和度、明度。
}
vec3 omniHsvToRgb(vec3 c){ // 色相、饱和度、明度转回颜色。
	const vec4 K = vec4(3.0, 2.0, 1.0, 9.0) / 3.0; // 六个扇区的折叠常数。
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www); // 把色相折成三角波。
	return c.z * mix(K.xxx, saturate(p - K.xxx), c.y); // 明度与饱和度还原到通道。
}
vec3 omniSrgbToLinear(vec3 s){ // sRGB 到线性，照 Eclipse 的近似多项式，供方块光表复原颜色。
	return s * (s * (s * 0.305306011 + 0.682171111) + 0.012522878);
}
float omniLpvCurve(float v){ return v * v; } // 体积光的曲线，照 Eclipse `lpv_render.glsl:5` 的非蒙版分支。

// --- 坐标映射：相机相对位置到体积坐标与体素下标 ---
// 体积格对齐到整数世界格：相机相对位置加 `fract(cameraPosition)` 得到“去掉相机所在格后的世界坐标”，
// 再加半边把它放到体积中心；这样玩家走动时体积按整格平移，不会拖影。
vec3 omniLpvPosition(vec3 playerPos){ return playerPos + fract(cameraPosition) + omniLpvHalf; }
// 体素下标：顶点阶段写入用，和 `omniLpvPosition` 同一套对齐，取整后就是单元编号。
ivec3 omniVoxelIndex(vec3 playerPos){ return ivec3(floor(omniLpvPosition(playerPos))); }
// 归一化坐标：片元采样用，单元中心落在零到一之间，硬件做三线性插值。
vec3 omniLpvUvw(vec3 lpvPos){ return lpvPos / float(omniLpvSide); }
// 体素下标是否在体积内；越界写会被丢弃，与 Eclipse `SetVoxelBlock` 一致。
bool omniVoxelInside(ivec3 cell){ return all(greaterThanEqual(cell, ivec3(0))) && all(lessThan(cell, ivec3(int(omniLpvSide)))); }

// --- 体素编号：顶点阶段把地形方块编号算成一个可写进体素图的值 ---
// 参数 `entityId` 是原版方块编号；没有编号的固体当不透光方块一，与 Eclipse `voxel_write.glsl:114` 一致。
uint omniVoxelBlockId(float entityId){
	uint voxelId = uint(entityId + 0.5); // 转成无符号整数编号。
	if (voxelId == 0u) voxelId = 1u; // 没编号的固体按不透光处理。
	return voxelId; // 交回可写进体素图的编号。
}

// ========================= 片元取样：读体积图并混回表面 =========================
// 只在非计算阶段、开启功能且具备自定义图像能力时编译，否则整段不参与。
#if !defined(OMNI_COMPUTE) && defined(OMNI_LPV_ENABLED) && defined(IRIS_FEATURE_CUSTOM_IMAGES)
uniform sampler3D omniLpvTex1; // 偶数帧写入的一张体积图，片元只读。
uniform sampler3D omniLpvTex2; // 奇数帧写入的另一张，交替读取。
// 读一个体积样本并解码：先把存下的 RGB 当 HSV 还原，再按 Eclipse 的编码曲线缩放。
vec4 omniLpvSample(vec3 lpvPos){
	vec3 uvw = omniLpvUvw(lpvPos); // 归一化坐标。
	vec4 sample = (frameCounter % 2) == 0
		? textureLod(omniLpvTex1, uvw, 0.0) // 偶数帧读偶数帧写的那张。
		: textureLod(omniLpvTex2, uvw, 0.0); // 奇数帧反过来，保证读到完整结果。
	vec3 hsv = omniRgbToHsv(sample.rgb); // 把存储值当颜色再转 HSV，是 Eclipse 的既有解码方式。
	hsv.z = omniLpvCurve(hsv.b) * omniLpvBlockSkyRange.x; // 按亮度的平方放大，得到最终能量。
	sample.rgb = omniHsvToRgb(hsv); // 还原成颜色。
	sample.rgb = clamp(sample.rgb / 15.0, 0.0, 1.0); // 归一到零到一，照 Eclipse。
	return sample; // 交回彩色方块光与天光。
}
// 体积边缘淡出：越靠边越把体积光压回去，避免体积边界出现硬边。
float omniLpvRangeFalloff(vec3 lpvPos){
	vec3 cubicRadius = clamp(min((vec3(float(omniLpvSide)) - 1.0 - lpvPos) / omniLpvFadeLength, lpvPos / omniLpvFadeLength), 0.0, 1.0); // 到六个面的距离比。
	float falloff = cubicRadius.x * cubicRadius.y * cubicRadius.z; // 三轴相乘，角上最小。
	return 1.0 - pow(1.0 - pow(falloff, 1.5), 3.0); // 再压一次曲线，中心满值、边缘平滑归零。
}
// 把体积光混回表面的方块光：返回替换后的方块光，供合成零号使用。
// 参数 `blockLight` 是原版方块光算出的颜色，`playerPos` 是相机相对世界位置，`worldNormal` 是世界法线。
vec3 omniLpvApply(vec3 blockLight, vec3 playerPos, vec3 worldNormal){
	vec3 normalOffset = worldNormal * (OMNI_LPV_NORMAL_STRENGTH / 100.0); // 沿法线偏移取样点，减少贴面漏光。
	vec3 lpvPos = omniLpvPosition(playerPos) + normalOffset; // 偏移后的体积坐标。
	vec4 sample = omniLpvSample(lpvPos); // 读出彩色方块光与天光。
	float falloff = omniLpvRangeFalloff(lpvPos); // 体积边缘淡出。
	return mix(blockLight, sample.rgb, saturate(falloff * OMNI_LPV_STRENGTH)); // 用淡出把原版方块光换成体积光。
}
#endif // 片元取样结束。

// ========================= 顶点写体素：阴影顶点阶段把方块编号写进体素图 =========================
// 只在阴影顶点阶段编译；远景阴影不写，因为它的几何和近景阴影不同源。
#if !defined(OMNI_COMPUTE) && defined(OMNI_VERTEX) && defined(OMNI_SHADOW_PASS) && !defined(OMNI_DH_SHADOW_PASS) && defined(OMNI_LPV_ENABLED) && defined(IRIS_FEATURE_CUSTOM_IMAGES)
layout(r16ui) uniform restrict uimage3D omniLpvVoxel; // 体素编号图，阴影顶点写、计算只读。
// 把方块编号写进对应体素格，越界丢弃；照 Eclipse `SetVoxelBlock`。
void omniVoxelStore(ivec3 coord, uint blockId){
	if (!omniVoxelInside(coord)) return; // 越界不写，体积外的几何不参与。
	imageStore(omniLpvVoxel, coord, uvec4(blockId)); // 写入编号。
}
#endif // 顶点写体素结束。

// ========================= 计算阶段：方块光表与传播 =========================
// 只有计算阶段、开启功能且具备自定义图像能力时才编译下面的图像、光表与传播函数。
#if defined(OMNI_COMPUTE) && defined(OMNI_LPV_ENABLED) && defined(IRIS_FEATURE_CUSTOM_IMAGES)
layout(rgba8) uniform restrict image3D omniLpv1; // 传播缓冲之一（偶数帧写）。
layout(rgba8) uniform restrict image3D omniLpv2; // 另一个缓冲（奇数帧写）。
layout(r16ui) uniform restrict uimage3D omniLpvVoxel; // 体素编号，阴影顶点阶段写入。
layout(rg32ui) uniform uimage1D omniLpvBlocks; // 方块光表，`setup` 阶段一次填好，传播阶段只读。

// 方块光表容量：本项目方块编号最大到七千一百零二，取八千一百九十二足够放下，比 Eclipse 的两千零四十八大。
const uint omniLpvBlockTableSize = 8192u;

// --- 饱和度矩阵：让光色按玩家设置变鲜艳或变灰，照 Eclipse `setup.csh:39` ---
mat4 omniLpvSaturationMatrix(float saturation){
	const vec3 luminance = vec3(0.3086, 0.6094, 0.0820); // 亮度权重。
	vec3 lumSat = luminance * (1.0 - saturation); // 去饱和时保留的灰分量。
	vec2 satZero = vec2(saturation, 0.0); // 原色分量。
	return mat4(
		vec4(lumSat.r + satZero.xyy, 0.0),
		vec4(lumSat.g + satZero.yxy, 0.0),
		vec4(lumSat.b + satZero.yyx, 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
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
	else if (id == 7000u || id == 7010u || id == 7011u || id == 7020u || id == 7021u || id == 7040u) mixWeight = 0.9; // 植物：几乎全透。
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
	vec4 sample = (frameCounter % 2) == 0 ? imageLoad(omniLpv2, coord) : imageLoad(omniLpv1, coord); // 读上一帧写的那张。
	vec4 hsvSky = vec4(omniRgbToHsv(sample.rgb), sample.a); // 拆出颜色与天光。
	hsvSky.zw = exp2(hsvSky.zw * omniLpvBlockSkyRange) - 1.0; // 反解对数编码，得到饱和度与天光。
	return vec4(omniHsvToRgb(hsvSky.xyz), hsvSky.w); // 还原成颜色加天光。
}
// 把传播结果按同一套编码写回本帧的一张体积图，照 Eclipse `shadowcomp.csh:164`。
vec4 omniLpvEncode(vec4 value){
	vec4 hsvSky = vec4(omniRgbToHsv(value.rgb), value.a); // 拆出颜色与天光。
	hsvSky.zw = log2(hsvSky.zw + 1.0) / omniLpvBlockSkyRange; // 对数编码，压住动态范围。
	return vec4(omniHsvToRgb(hsvSky.xyz), hsvSky.w); // 交回可存进八位图的值。
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
#endif // 文件守卫结束。
