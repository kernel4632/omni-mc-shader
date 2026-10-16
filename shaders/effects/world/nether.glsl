/*
下界配色与光照：给下界的不透明表面算一套不靠太阳光的自发光配色，并按群系在五个颜色之间过渡。
来源：iterationT `Lib/BasicFounctions/NetherColor.glsl` 一比一移植（`NetherLighting`、`NetherFogColor`），
  群系平滑量与亮度、雾密度常数照原程序，不简化也不合并。
调用位置：`rendering/composite.glsl` 的合成零号在下界分支里算不透明表面光照时调用本文件。
可复制示例：
  `finalComposite += NetherLighting() * (worldNormal.y * 0.25 + 1.0);`
  `finalComposite *= mix(vec3(1.0), NetherFogColor().rgb, gbuffer.material.metalness * 0.7);`
调用前提（按 iterationT 原程序的引用顺序，由绘制主体先声明或先引入）：
  五个群系平滑量 `BiomeNetherWastesSmooth`、`BiomeSoulSandValleySmooth`、`BiomeCrimsonForestSmooth`、
  `BiomeWarpedForestSmooth`、`BiomeBasaltDeltasSmooth` 由本文件声明，加载器按 `rendering/pipeline.properties` 每帧填好；
  `OMNI_NETHERFOG_DENSITY` 由 `effects/fog/fog.glsl` 提供，绘制主体必须先引入它，本文件不重复定义。
关键设计原因与取舍：
  原程序把下界光照与雾色写成两个函数，都返回「当前群系混合后的颜色」，本文件保持同样的形状；
  `NetherFogColor` 的第四分量是雾密度，`NetherFog` 用它把远处压成雾色，所以它返回 `vec4` 而不是 `vec3`。
*/
#ifndef OMNI_NETHER_INCLUDED // 只引入一次，避免选项与群系量重复定义。
#define OMNI_NETHER_INCLUDED // 置上标记，后续再次引用直接跳过。
// @effect {"label":{"zh_cn":"下界","en_us":"Nether"}}
// @option {"label":{"zh_cn":"下界环境亮度","en_us":"Nether Ambient Brightness"},"description":{"zh_cn":"下界不等于无光，这里的整体亮度。","en_us":"Overall ambient brightness in the Nether, which is never fully dark."},"slider":true}
#define OMNI_NETHER_BRIGHTNESS 1.0 // [0.1 0.15 0.2 0.3 0.5 0.7 1.0 1.5 2.0 3.0 5.0 7.0 10.0 15.0 20.0 30.0 50.0 70.0 100.0]

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
	return fog * vec4(vec3(OMNI_NETHER_BRIGHTNESS), OMNI_NETHERFOG_DENSITY); // 颜色乘亮度、密度乘雾浓度选项。
}

// --- 下界雾：两种调用形状 ---
// 为什么两个重载：合成二号只关心反射射线的一段（起点到命中点），传两个距离；合成五号要整条视线的雾，传一个距离。
// 名称保持原程序，两个文件里各有一份，这里按合同集中到一个文件，两处调用点都能用。
vec3 NetherFog(vec2 dist){
	dist = min(dist, vec2(far * 1.2)); // 距离封顶，远处不再变浓。

	float fogDensity = NetherFogColor().w; // 雾密度来自下界雾色。
	vec2 fogFactor = 1.0 - exp2(-dist * fogDensity); // 两段距离各自的衰减。
	fogFactor *= fogFactor; // 平方增强。

	vec3 fogColor = NetherFogColor().xyz * 0.0125; // 雾色缩到合理量级。

	return max(fogFactor.x - fogFactor.y, 0.0) * fogColor; // 两段之差就是反射射线那一段的雾。
}

vec3 NetherFog(float dist){
	float fogDensity = NetherFogColor().w; // 雾密度来自下界雾色。
	float fogFactor = 1.0 - exp2(-dist * fogDensity); // 视线距离的衰减。
	fogFactor *= fogFactor; // 平方增强。

	vec3 fogColor = NetherFogColor().xyz * 0.0125; // 雾色缩到合理量级。

	return fogFactor * fogColor; // 整条视线的雾。
}

// --- 下界水面折射：与主世界同名函数形状不同，加 `Nether` 后缀区分 ---
// 与主世界版的差别：下界用 `NetherFog` 补雾，不再走体积雾与地表散射，也不带时间因子与云影参数。
void WaterRefractionLiteNether(inout vec3 color, MaterialMask mask, vec3 normal, vec3 worldPos, vec3 viewPos, float waterDist, float opaqueDist){
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

	color += NetherFog(rDist) / MAIN_OUTPUT_FACTOR; // 补一段下界雾。
}

// --- 下界彩色玻璃吸收：与主世界同名函数多一个参数不同，加 `Nether` 后缀区分 ---
void TransparentAbsorptionNether(inout vec3 color, vec4 stainedGlassAlbedo){
	vec3 stainedGlassColor = normalize(stainedGlassAlbedo.rgb + 0.0001) * fsqrt(length(stainedGlassAlbedo.rgb)); // 归一化方向乘近似亮度。
	color *= GammaToLinear(mix(vec3(1.0), stainedGlassColor, vec3(pow(stainedGlassAlbedo.a, 0.2)))); // 按不透明度吸收。
}
#endif // 文件守卫结束。
