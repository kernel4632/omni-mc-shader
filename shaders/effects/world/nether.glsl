/*
效果文件 `effects/world/nether.glsl`：玩家选项、宿主参数换算、阶段组合与说明集中在这里，菜单由 options.py 扫描本文件生成。
调用位置：`rendering/` 下的绘制主体按需引用本文件；同目录的其它效果文件补充分阶段实现。
可复制示例：`#include "/effects/world/nether.glsl"`，随后调用下方保留原名的效果入口。
设计原因与取舍：选项、参数换算与阶段组合同属一个效果，放在一处才找得到、改得动；算式在生成的 `omni-gfx` 库，本文件不复制。
*/
#ifndef OMNI_EFFECT_WORLD_NETHER_INCLUDED
#define OMNI_EFFECT_WORLD_NETHER_INCLUDED
// @effect {"label":{"zh_cn":"下界","en_us":"Nether"}}
// @option {"label":{"zh_cn":"环境亮度","en_us":"Nether Ambient Brightness"},"description":{"zh_cn":"下界不等于无光，这里的整体亮度。","en_us":"Overall ambient brightness in the Nether, which is never fully dark."},"slider":true}
#define OMNI_NETHER_BRIGHTNESS 1.0 // [0.1 0.15 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]
// @option {"label":{"zh_cn":"空气雾","en_us":"Nether volumetric fog"},"description":{"zh_cn":"在原有解析下界雾之上，叠加 Eclipse 的羽流烟柱、顶部烟与雾霭三段体积雾；关闭时画面与原来完全一致。","en_us":"Adds Eclipse's three volumetric layers (plumes, ceiling smoke, haze) on top of the existing analytic Nether fog; off leaves the original picture unchanged."}}
#define OMNI_NETHER_VOLUMETRIC_FOG 0 // [0 1]
// @option {"label":{"zh_cn":"羽流密度","en_us":"Nether plume density"},"description":{"zh_cn":"下界低空发光烟柱的浓淡，越大烟柱越明显。","en_us":"Thickness of the glowing low plumes; larger makes them more visible."},"slider":true}
#define OMNI_NETHER_PLUME_DENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.25 1.5 2.0 3.0 5.0 7.0 10.0]
// @option {"label":{"zh_cn":"顶部烟密度","en_us":"Nether ceiling smoke density"},"description":{"zh_cn":"贴近下界天花板出现的灰烟浓淡。","en_us":"Thickness of the grey smoke near the Nether ceiling."},"slider":true}
#define OMNI_NETHER_CEILING_SMOKE_DENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.25 1.5 2.0 3.0 5.0 7.0 10.0]
// @option {"label":{"zh_cn":"雾霭密度","en_us":"Nether haze density"},"description":{"zh_cn":"整片下界空气的均匀雾霭浓淡。","en_us":"Thickness of the uniform haze filling the Nether air."},"slider":true}
#define OMNI_NETHER_HAZE_DENSITY 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.25 1.5 2.0 3.0 5.0 7.0 10.0]
// @option {"label":{"zh_cn":"空气雾采样质量","en_us":"Nether volumetric fog quality"},"description":{"zh_cn":"下界体积雾沿视线的采样次数，越高越干净也越慢，默认十六与 Eclipse 相同。","en_us":"View samples for the Nether volumetric fog; higher is cleaner and slower, default 16 matches Eclipse."},"slider":true}
#define OMNI_NETHER_VFOG_QUALITY 16 // [4 6 8 10 12 16 20 24 32 48]

// --- 效果实现：宿主输入、参数换算与阶段入口 ---
/*
下界配色与光照与三段体积雾：给下界的不透明表面算一套不靠太阳光的自发光配色，并按群系在五个颜色之间过渡；
  另附一套可选的下界体积雾，把 Eclipse 的羽流烟柱、顶部烟与雾霭三段分开步进。
来源：
  配色与解析雾是 iterationT `Lib/BasicFounctions/NetherColor.glsl` 一比一移植（`NetherLighting`、`NetherFogColor`），
  群系平滑量与亮度、雾密度常数照原程序，不简化也不合并；
  三段体积雾照 Eclipse `lib/nether_fog.glsl` 搬运（`NetherFogDensityAt`、`NetherFogCloudVolume`、`NetherVolumetricFog`），
  内部步进、噪声与三个密度完全照原实现，只在结尾按 Omni 的管线单位做了换算。
调用位置：`rendering/composite.glsl` 的合成零号、二号与五号在下界分支里引入本文件。
  合成零号用 `NetherLighting`、`NetherFogColor`；合成二号经屏幕空间反射调用 `NetherFog(vec2)`；
  合成五号整幅场景调用 `NetherFog(float)` 与 `RefractSampleOnceNether`。
可复制示例：
  `finalComposite += NetherLighting() * (worldNormal.y * 0.25 + 1.0);`
  `finalComposite *= mix(vec3(1.0), NetherFogColor().rgb, gbuffer.material.metalness * 0.7);`
  `vec4 netherFog = NetherFog(waterDist); color = color * netherFog.a + netherFog.rgb;`  取回的 `a` 是透射率，先压暗背景再叠散射
调用前提（按 iterationT 原程序的引用顺序，由绘制主体先声明或先引入）：
  五个群系平滑量 `BiomeNetherWastesSmooth`、`BiomeSoulSandValleySmooth`、`BiomeCrimsonForestSmooth`、
  `BiomeWarpedForestSmooth`、`BiomeBasaltDeltasSmooth` 由本文件声明，加载器按 `rendering/pipeline.properties` 每帧填好；
  `OMNI_NETHER_FOG_DENSITY` 由 `effects/fog/fog.glsl` 提供，绘制主体必须先引入它，本文件不重复定义；
  体积雾需要 `texCoord`、`gbufferModelViewInverse`、`cameraPosition`、`far`、`frameTimeCounter`、`noisetex`
  与 `ViewPos_From_ScreenPos`，它们来自合成共享声明 `rendering/composite_shared.glsl` 与共用数学，只有片元阶段存在；
  打开时间抗锯齿时体积雾还会用到 `BlueNoiseTemporal`，由 `common/noise.glsl` 提供。
关键设计原因与取舍：
  原程序把下界光照与雾色写成两个函数，都返回「当前群系混合后的颜色」，本文件保持同样的形状；
  `NetherFogColor` 的第四分量是雾密度，`NetherFog` 用它把远处压成雾色，所以它返回 `vec4` 而不是 `vec3`；
  体积雾默认关闭，`NetherFog(float)` 原有的解析雾公式在关闭时逐字不变，透射率记为一，所以默认画面与原来完全一致；
  Eclipse 的体积雾结果带透射率，要把被雾挡住的背景乘暗；本项目没有它那张独立雾缓冲，改为把透射率沿函数返回值带回，
  `NetherFog(float)` 因此返回 `vec4`：`rgb` 是散射色、`a` 是剩余透射率，调用方按 `color = color * a + rgb` 合成；
  `NetherFog(vec2)` 取的是反射射线的一段，唯一调用点在 `effects/reflection/reflection.glsl`（不在本次改动范围），
  所以它仍返回 `vec3` 只叠加散射，透射率未接，见两个重载各自的说明。
*/
// 下界单格雾密度放在通用库，这里只传噪声纹理。
#include "/omni-gfx/fog.glsl"
// 动画时间由绑定层提供，效果文件不直接读宿主时间。
#include "/bind/time.glsl"

// 五个下界群系的平滑权重：任一时刻它们之和为一，按权重混合出当前群系的配色。
uniform float BiomeNetherWastesSmooth; // 下界荒地的权重。
uniform float BiomeSoulSandValleySmooth; // 灵魂沙峡谷的权重。
uniform float BiomeCrimsonForestSmooth; // 绯红森林的权重。
uniform float BiomeWarpedForestSmooth; // 诡异森林的权重。
uniform float BiomeBasaltDeltasSmooth; // 玄武岩三角洲的权重。

// --- 下界光照：每个群系一种基色和强度，叠加后乘整体亮度 ---
// 为什么每个群系单独一项：下界没有太阳，画面亮度全靠这些写死的基色撑着，群系之间差别很大。
// 五个群系的基色与强度在通用库，本函数只把平滑权重与亮度选项传进去。
vec3 NetherLighting(){
	return ogxNetherBiomeLighting(BiomeNetherWastesSmooth, BiomeSoulSandValleySmooth, BiomeCrimsonForestSmooth,
		BiomeWarpedForestSmooth, BiomeBasaltDeltasSmooth, OMNI_NETHER_BRIGHTNESS); // 群系混合在通用库。
}

// --- 下界雾色：三通道是雾的颜色，第四分量是雾密度 ---
// 为什么密度也按群系混合：玄武岩三角洲的灰雾最浓，诡异森林最淡，同一份权重同时决定颜色和浓度。
vec4 NetherFogColor(){
	return ogxNetherBiomeFogColor(BiomeNetherWastesSmooth, BiomeSoulSandValleySmooth, BiomeCrimsonForestSmooth,
		BiomeWarpedForestSmooth, BiomeBasaltDeltasSmooth, OMNI_NETHER_BRIGHTNESS, OMNI_NETHER_FOG_DENSITY); // 颜色与密度一起混合。
}

// --- 下界三段体积雾：Eclipse `lib/nether_fog.glsl` 的搬运，默认关闭 ---
// 为什么单独一套：Eclipse 把下界空气拆成羽流、顶部烟、雾霭三层分开步进，与解析雾不同；
// 三段各自的密度选项默认都为一，只有打开总开关后才参与计算，关闭时整段不产生任何采样。
// 单位换算：Eclipse 的体积雾加在它自己的管线线性颜色上，量级与 Omni 不同；
// 结尾按 Omni 下界雾色使用的同一常数换算到管线单位，这是唯一与原程序不同的地方，需要实机再微调。

// 一格噪声密度：把世界坐标折成三维格子再查二维噪声图，得到零到一的基础密度。
// 为什么用二维图模拟三维：噪声图已烘好一层分布，采样代价低，也保证全屏可重复。
float NetherFogDensityAt(vec3 pos){
	return ogxNetherFogDensityAt(pos, noisetex); // 转发到通用库。
}

// 体积雾原始密度：叠上被时间侵蚀的羽流形状、贴地烟与高度衰减，返回零附近的密度。
// 为什么随高度变化：下界烟从地面升起、被天花板压住，越高越稀，密度必须带高度包络。
float NetherFogCloudVolume(vec3 pos){
	return ogxNetherFogCloudVolume(pos, bind_time().seconds, noisetex); // 时间与噪声纹理交给库。
}

// 当前像素的视空间射线方向：屏幕上任意深度的点都在同一条从相机出发的射线上，归一后就是方向。
// 为什么自己算而不是要调用方传：`NetherFog` 只拿到距离，体积雾要方向，这里从屏幕坐标还原。
vec3 NetherFogViewRay(){
	return normalize(ViewPos_From_ScreenPos(texCoord, 0.5)); // 取任意深度的一点，归一得到方向。
}

// 体积雾步进抖动：开时间抗锯齿时逐帧变化，靠帧平均把噪点抹掉；否则用固定拜尔抖动。
float NetherFogDither(){
	#ifdef OMNI_TAA
		return BlueNoiseTemporal().x; // 每帧变化的蓝噪声。
	#else
		return bayer64(gl_FragCoord.xy); // 固定拜尔抖动。
	#endif
}

// 三段体积雾主体：沿一段视线指数步进，分别累加羽流、雾霭、顶部烟的散射与吸收。
// 输入是这一段视线的起止距离与两个抖动值，返回散射色与剩余透射率。
// 为什么按段：合成五号补相机到表面的整段，合成二号补反射命中前后的一小段，起点不为零时就是那一小段。
vec4 NetherVolumetricFog(float startDist, float endDist, float ditherA, float ditherB){
	const int samples = OMNI_NETHER_VFOG_QUALITY; // 沿视线的采样次数，默认十六。
	const float expFactor = 11.0; // 步长指数底数，照 Eclipse，采样集中在前段。

	vec3 worldRay = mat3(gbufferModelViewInverse) * NetherFogViewRay(); // 视空间射线方向换到相机相对世界方向。

	endDist = min(endDist, min(far, 16.0 * 12.0)); // 最远只步进一百九十二米，照 Eclipse 的距离上限。

	vec3 hazeColor = normalize(NetherFogColor().xyz + 1e-6) * 0.25; // 雾霭颜色取当前下界雾色的方向，代替 Eclipse 的原版雾色。

	// 三段步进与混合在通用库，这里只把相机、距离、三个密度选项与噪声纹理传进去。
	return ogxNetherVolumetricFog(worldRay, gbufferModelViewInverse[3].xyz, cameraPosition, startDist, endDist,
		ditherA, ditherB, samples, expFactor, 16.0 * 12.0, far, OMNI_NETHER_PLUME_DENSITY, OMNI_NETHER_HAZE_DENSITY,
		OMNI_NETHER_CEILING_SMOKE_DENSITY, hazeColor, 0.0125, bind_time().seconds, noisetex);
}

// --- 下界雾：两种调用形状 ---
// 为什么两个重载：合成二号只关心反射射线的一段（起点到命中点），传两个距离；合成五号要整条视线的雾，传一个距离。
// 名称保持原程序，两个文件里各有一份，这里按合同集中到一个文件，两处调用点都能用。
// 为什么返回类型不同：`float` 重载要交回体积雾透射率给合成五号乘暗背景，所以返回 `vec4`；
// `vec2` 重载的调用方在反射文件里只做 `reflection += ...`，本次不改那个文件，所以它保持 `vec3` 只叠加散射。
vec3 NetherFog(vec2 dist){
	dist = min(dist, vec2(far * 1.2)); // 距离封顶，远处不再变浓。

	float fogDensity = NetherFogColor().w; // 雾密度来自下界雾色。
	vec2 fogFactor = 1.0 - exp2(-dist * fogDensity); // 两段距离各自的衰减。
	fogFactor *= fogFactor; // 平方增强。

	vec3 fogColor = NetherFogColor().xyz * 0.0125; // 雾色缩到合理量级。

	vec3 fog = max(fogFactor.x - fogFactor.y, 0.0) * fogColor; // 两段之差就是反射射线那一段的雾。

	#if OMNI_NETHER_VOLUMETRIC_FOG // 打开体积雾时，叠上这一段的三段体积雾散射。
		float fogDither = NetherFogDither(); // 这一次的步进抖动。
		fog += NetherVolumetricFog(dist.x, dist.y, fogDither, fogDither).rgb; // 反射通道只叠加散射色，透射率由整条视线的重载接回，见文件头。
	#endif

	return fog; // 解析雾加可选体积雾。
}

vec4 NetherFog(float dist){
	float fogDensity = NetherFogColor().w; // 雾密度来自下界雾色。
	float fogFactor = 1.0 - exp2(-dist * fogDensity); // 视线距离的衰减。
	fogFactor *= fogFactor; // 平方增强。

	vec3 fogColor = NetherFogColor().xyz * 0.0125; // 雾色缩到合理量级。

	vec3 fog = fogFactor * fogColor; // 整条视线的解析雾，只加色不遮挡背景。
	float transmittance = 1.0; // 剩余透射率，解析雾不遮挡，所以默认是一。

	#if OMNI_NETHER_VOLUMETRIC_FOG // 打开体积雾时，叠上整条视线的三段体积雾，并取回它的透射率。
		float fogDither = NetherFogDither(); // 这一次的步进抖动。
		vec4 volumetric = NetherVolumetricFog(0.0, dist, fogDither, fogDither); // 三段体积雾的散射色与剩余透射率。
		fog += volumetric.rgb; // 散射色照旧叠加。
		transmittance = volumetric.a; // 透射率交回合成阶段，让被雾挡住的远处背景真正变暗。
	#endif

	return vec4(fog, transmittance); // rgb 是散射色、a 是剩余透射率，调用方按 `color * a + rgb` 使用。
}

// --- 下界水面折射：与主世界 `RefractSampleOnce` 形状不同，加 `Nether` 后缀区分 ---
// 与主世界版的差别：下界用 `NetherFog` 补雾，不再走体积雾与地表散射，也不带时间因子与云影参数。
void RefractSampleOnceNether(inout vec3 color, MaterialMask mask, vec3 normal, vec3 worldPos, vec3 viewPos, float waterDist, float opaqueDist){
	vec2 refractCoord = RefractionScreenCoord(mask, normal, worldPos, viewPos, waterDist, opaqueDist, texCoord); // 三个维度共用折射坐标。

	float currentDepth = texelFetch(depthtex0, texelCoord, 0).x; // 当前像素深度。
	float refractDepth = textureLod(depthtex1, refractCoord, 0.0).x; // 折射采样点深度。
	if(refractDepth < currentDepth) refractCoord = texCoord.st; // 采样点更近就是前景，退回原位防泄漏。

	refractCoord = mix(texCoord, refractCoord, float(saturate(refractCoord) == refractCoord)); // 屏幕外的采样点也退回原位。

	color = CurveToLinear(textureLod(colortex1, refractCoord.xy, 0.0).rgb); // 读回折射后的场景颜色。

	float rDist = max(length(ViewPos_From_ScreenPos(refractCoord, textureLod(depthtex1, refractCoord, 0.0).x)) - waterDist, 0.0); // 折射点到相机距离减去水面距离。

	vec4 refractFog = NetherFog(rDist); // 折射点到相机之间那一段的下界雾散射与透射率。
	color = color * refractFog.a + refractFog.rgb / MAIN_OUTPUT_FACTOR; // 先按透射率压暗折射背景，再叠雾散射，量级照旧换算。
}

// --- 下界彩色玻璃吸收：与主世界同名函数多一个参数不同，加 `Nether` 后缀区分 ---
void TransparentAbsorptionNether(inout vec3 color, vec4 stainedGlassAlbedo){
	vec3 stainedGlassColor = normalize(stainedGlassAlbedo.rgb + 0.0001) * fsqrt(length(stainedGlassAlbedo.rgb)); // 归一化方向乘近似亮度。
	color *= GammaToLinear(mix(vec3(1.0), stainedGlassColor, vec3(pow(stainedGlassAlbedo.a, 0.2)))); // 按不透明度吸收。
}
#endif // OMNI_EFFECT_WORLD_NETHER_INCLUDED
