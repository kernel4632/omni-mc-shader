/*
下界的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/world/nether.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_RENDER_WORLD_NETHER_INCLUDED
#define OMNI_RENDER_WORLD_NETHER_INCLUDED
#include "/effects/world/nether.glsl"
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
#include "/gfx/fog.glsl"
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
vec3 NetherLighting(){
	vec3 netherLighting =	 BiomeNetherWastesSmooth *   vec3(0.99, 0.34, 0.10) * 4.5e-4; // 荒地偏橙红，最弱。
	netherLighting +=		 BiomeSoulSandValleySmooth * vec3(0.60, 0.77, 1.00) * 2e-4; // 灵魂沙峡谷偏青蓝，更暗。
	netherLighting +=		 BiomeCrimsonForestSmooth *  vec3(1.00, 0.80, 0.57) * 4e-4; // 绯红森林偏暖白。
	netherLighting +=		 BiomeWarpedForestSmooth *   vec3(0.79, 0.82, 1.00) * 2.5e-4; // 诡异森林偏冷蓝。
	netherLighting +=		 BiomeBasaltDeltasSmooth *   vec3(1.00, 0.78, 0.62) * 1e-3; // 玄武岩三角洲最亮。
	return netherLighting * OMNI_NETHER_BRIGHTNESS; // 按整体亮度缩放。
}

// --- 下界雾色：三通道是雾的颜色，第四分量是雾密度 ---
// 为什么密度也按群系混合：玄武岩三角洲的灰雾最浓，诡异森林最淡，同一份权重同时决定颜色和浓度。
vec4 NetherFogColor(){
	vec4 fog =	 vec4(0.990, 0.170, 0.005, 0.010) * BiomeNetherWastesSmooth; // 荒地橙红、中等密度。
	fog +=		 vec4(0.010, 0.035, 0.060, 0.007) * BiomeSoulSandValleySmooth; // 灵魂沙峡谷近乎黑青。
	fog +=		 vec4(0.200, 0.020, 0.000, 0.010) * BiomeCrimsonForestSmooth; // 绯红森林暗红。
	fog +=		 vec4(0.030, 0.100, 0.130, 0.007) * BiomeWarpedForestSmooth; // 诡异森林暗青。
	fog +=		 vec4(0.400, 0.400, 0.400, 0.014) * BiomeBasaltDeltasSmooth; // 玄武岩三角洲灰色、最浓。
	return fog * vec4(vec3(OMNI_NETHER_BRIGHTNESS), OMNI_NETHER_FOG_DENSITY); // 颜色乘亮度、密度乘雾浓度选项。
}

// --- 下界三段体积雾：Eclipse `lib/nether_fog.glsl` 的搬运，默认关闭 ---
// 为什么单独一套：Eclipse 把下界空气拆成羽流、顶部烟、雾霭三层分开步进，与解析雾不同；
// 三段各自的密度选项默认都为一，只有打开总开关后才参与计算，关闭时整段不产生任何采样。
// 单位换算：Eclipse 的体积雾加在它自己的管线线性颜色上，量级与 Omni 不同；
// 结尾按 Omni 下界雾色使用的同一常数换算到管线单位，这是唯一与原程序不同的地方，需要实机再微调。

// 一格噪声密度：把世界坐标折成三维格子再查二维噪声图，得到零到一的基础密度。
// 为什么用二维图模拟三维：噪声图已烘好一层分布，采样代价低，也保证全屏可重复。
float NetherFogDensityAt(vec3 pos){
	return gfx_nether_fog_density_at(pos, noisetex); // 转发到通用库。
}

// 体积雾原始密度：叠上被时间侵蚀的羽流形状、贴地烟与高度衰减，返回零附近的密度。
// 为什么随高度变化：下界烟从地面升起、被天花板压住，越高越稀，密度必须带高度包络。
float NetherFogCloudVolume(vec3 pos){
	return gfx_nether_fog_cloud_volume(pos, bind_time().seconds, noisetex); // 时间与噪声纹理交给库。
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
	float rayLength = endDist - startDist; // 这一段视线的长度。
	if (rayLength <= 0.0) return vec4(0.0, 0.0, 0.0, 1.0); // 空段或反向段直接返回，避免除零。

	vec3 segment = worldRay * rayLength; // 整段的相机相对世界向量。
	float dL = rayLength; // 光学厚度的段长，照 Eclipse。

	vec3 base = gbufferModelViewInverse[3].xyz + worldRay * startDist; // 相机相对世界里的起点。

	vec3 color = vec3(0.0); // 累加的散射色。
	float absorbance = 1.0; // 剩余透射率，从全透开始。
	vec3 hazeColor = normalize(NetherFogColor().xyz + 1e-6) * 0.25; // 雾霭颜色取当前下界雾色的方向，代替 Eclipse 的原版雾色。

	for (int i = 0; i < samples; i++){ // 沿这一段逐步前进。
		float d = (pow(expFactor, float(i + ditherB) / float(samples)) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor); // 指数步长在段上的归一化位置。
		float dd = pow(expFactor, float(i + ditherA) / float(samples)) * log(expFactor) / float(samples) / (expFactor - 1.0); // 这一步厚度权重，照原程序。

		vec3 relPos = base + d * segment; // 采样点的相机相对世界位置。
		float dist = length(relPos); // 到相机的距离，近处淡出与羽流距离窗都用它。
		vec3 worldPos = relPos + cameraPosition; // 绝对世界位置，体积噪声要它。

		float densityVol = NetherFogCloudVolume(worldPos); // 这一点的原始体积密度。
		float clearArea = 1.0 - min(max(1.0 - dist / 24.0, 0.0), 1.0); // 相机二十四米内淡出，避免贴脸起雾。

		// --- 羽流：从低空升起、随时间侵蚀的发光烟柱 ---
		float plumeDensity = min(densityVol * pow(min(max(100.0 - worldPos.y, 0.0) / 30.0, 1.0), 4.0), pow(clamp(1.0 - dist / far, 0.0, 1.0), 5.0)); // 越低越浓、越远越淡。
		plumeDensity *= OMNI_NETHER_PLUME_DENSITY; // 乘玩家密度选项。
		float plumeCoeff = exp(-plumeDensity * dd * dL); // 这一段羽流按比尔定律吸收掉的光。
		vec3 plumeLight = vec3(1.0, 0.4, 0.2) * 0.25 * exp(-15.0 * densityVol) * (clearArea * clearArea * 0.9 + 0.1); // 暖橙色，密度高处压暗。
		color += (plumeLight - plumeLight * plumeCoeff) * absorbance; // 叠上这一段羽流的散射。
		absorbance *= plumeCoeff; // 透射率随之下降。

		// --- 雾霭：极薄的均匀底色，照原程序不吸场景 ---
		float hazeDensity = 0.001 * OMNI_NETHER_HAZE_DENSITY; // 很低的均匀密度，乘选项。
		float hazeCoeff = exp(-hazeDensity * dd * dL); // 雾霭的吸收。
		color += (hazeColor - hazeColor * hazeCoeff) * absorbance; // 只加散射，不回乘透射率。

		// --- 顶部烟：贴近下界天花板（基岩层）才出现的灰烟 ---
		float ceilingDensity = 0.001 * pow(min(max(worldPos.y - 40.0, 0.0) / 50.0, 1.0), 3.0) * OMNI_NETHER_CEILING_SMOKE_DENSITY; // 越高越浓，乘选项。
		float ceilingCoeff = exp(-ceilingDensity * dd * dL); // 这一段灰烟的吸收。
		vec3 ceilingSmoke = vec3(0.1); // 固定的灰烟颜色。
		color += (ceilingSmoke - ceilingSmoke * ceilingCoeff) * (absorbance * 0.5 + 0.5); // 半强度叠加，照原程序。
		absorbance *= ceilingCoeff; // 透射率继续下降。
	}

	return vec4(color * 0.0125, absorbance); // 散色换算到 Omni 管线单位，与解析雾同量级，再返回透射率。
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
	vec2 refractCoord = texCoord; // 默认不折射，用原屏幕坐标。

	float waterDeep = opaqueDist - waterDist; // 水面到水底的厚度。

	if (mask.water > 0.5){ // 水面本身：用波法线偏移。
		float NdotU = dot(normal, gbufferModelView[1].xyz) + float(isEyeInWater == 1) * 2.0; // 法线朝向与水下判断。
		vec3 wavesNormal = GetWavesNormal(worldPos + cameraPosition, step(0.05, NdotU) * 18.0).xzy; // 求波法线并换到竖直轴朝上的坐标。
		vec4 wnv = gbufferModelView * vec4(wavesNormal.xyz, 0.0); // 波法线转到视空间。
		vec3 wavesNormalView = normalize(wnv.xyz); // 归一化。

		vec4 nv = gbufferModelView * vec4(0.0, 1.0, 0.0, 0.0); // 平水面法线转到视空间。
		nv.xyz = normalize(nv.xyz); // 归一化。

		refractCoord = nv.xy - wavesNormalView.xy; // 两种法线的差就是折射偏移方向。
		refractCoord *= saturate(waterDeep) * 0.5 / (waterDist + 0.0001); // 越深折射越强。
		refractCoord += texCoord; // 加到原坐标上。
	}else{ // 玻璃等透明面：用整段折射方向。
		vec3 refractDir = refract(normalize(viewPos), normal, 0.66); // 视空间折射方向。
		refractDir = refractDir / saturate(dot(refractDir, -normal)); // 归一化到视线方向。
		refractDir *= saturate(waterDeep * 2.0) * 0.125; // 按厚度缩放。

		vec4 refractPos = vec4(viewPos + refractDir, 0.0); // 折射后的视空间位置。
		refractPos = gbufferProjection * refractPos; // 投影到裁剪空间。

		refractCoord = refractPos.xy / refractPos.w * 0.5 + 0.5; // 转成屏幕坐标。
	}

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
#endif // OMNI_RENDER_WORLD_NETHER_INCLUDED
