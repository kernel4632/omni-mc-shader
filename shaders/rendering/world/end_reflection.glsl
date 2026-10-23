/*
末地反射与折射：屏幕反射没命中时用末地天空兜底，并处理末地的水面折射与彩色玻璃吸收。
来源：iterationT `Lib/IndividualFounctions/EndSky.glsl` 与折射段一比一移植。
职责：`ComputeFakeSkyReflectionEnd` 兜底反射天空，`RefractSampleOnceEnd` 处理末地水面折射并补雾，
  `TransparentAbsorptionEnd` 处理彩色玻璃吸收。
调用位置：由 `effects/world/end.glsl` 引入；合成一号、二号与五号按需调用。
可复制示例：`vec3 sky = ComputeFakeSkyReflectionEnd(reflectWorldDir, isSmooth);`
调用前提：由 `effects/world/end.glsl` 在所有末地算法之后引入；`texCoord`、`texelCoord`、波法线与坐标换算由绘制主体提供。
关键设计原因与取舍：三个函数都带 `End` 后缀与主世界同名函数区分（形状或参数不同）；
  末地折射用 `EndFog` 补雾，不走体积雾与地表散射，也不带时间因子与云影参数。
*/
#ifndef OMNI_END_REFLECTION_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_END_REFLECTION_INCLUDED // 置上标记，后续再次引用直接跳过。

// --- 末地假天空反射：屏幕反射没命中时用末地天空兜底 ---
// 为什么加 `End` 后缀：主世界 `effects/reflection/reflection.glsl` 另有一份形状不同的 `ComputeFakeSkyReflection`，按合同区分开。
// 调用前提：`worldShadowVector` 已由绘制主体声明。
vec3 ComputeFakeSkyReflectionEnd(vec3 reflectWorldDir, bool isSmooth){
	vec3 sky = vec3(0.0); // 累积的反射天空颜色。

	BlackHole_AccretionDisc_Reflection(sky, reflectWorldDir, worldShadowVector); // 吸积盘反射版。

	PlanetEnd2(sky, vec3(0.0), reflectWorldDir, worldShadowVector); // 行星与光环。

	return sky / MAIN_OUTPUT_FACTOR; // 换算到管线存储单位。
}

// --- 末地水面折射：与主世界 `RefractSampleOnce` 形状不同，加 `End` 后缀区分 ---
// 与主世界版的差别：末地用 `EndFog` 补雾，不再走体积雾与地表散射，也不带时间因子与云影参数。
// 调用前提：`texCoord`、`texelCoord`、水面波法线与坐标换算已由绘制主体引入。
void RefractSampleOnceEnd(inout vec3 color, MaterialMask mask, vec3 normal, vec3 worldPos, vec3 viewPos, float waterDist, float opaqueDist){
	vec2 refractCoord = RefractionScreenCoord(mask, normal, worldPos, viewPos, waterDist, opaqueDist, texCoord); // 与主世界共用折射坐标。

	float currentDepth = texelFetch(depthtex0, texelCoord, 0).x; // 当前像素深度。
	float refractDepth = textureLod(depthtex1, refractCoord, 0.0).x; // 折射采样点深度。
	if(refractDepth < currentDepth) refractCoord = texCoord; // 采样点更近就是前景，退回原位防泄漏。

	refractCoord = mix(texCoord, refractCoord, float(saturate(refractCoord) == refractCoord)); // 屏幕外的采样点也退回原位。

	color = CurveToLinear(textureLod(colortex1, refractCoord, 0.0).rgb); // 读回折射后的场景颜色。

	vec3 rViewPos = ViewPos_From_ScreenPos(refractCoord, textureLod(depthtex1, refractCoord, 0.0).x); // 折射点视空间位置。
	vec3 rWorldDir = normalize(mat3(gbufferModelViewInverse) * rViewPos); // 折射点世界方向。

	color += EndFog(max(length(rViewPos) - waterDist, 0.0), rWorldDir) / MAIN_OUTPUT_FACTOR; // 补一段末地雾。
}

// --- 末地彩色玻璃吸收：与主世界同名函数多一个参数不同，加 `End` 后缀区分 ---
void TransparentAbsorptionEnd(inout vec3 color, vec4 stainedGlassAlbedo){
	vec3 stainedGlassColor = normalize(stainedGlassAlbedo.rgb + 0.0001) * fsqrt(length(stainedGlassAlbedo.rgb)); // 归一化方向乘近似亮度。
	color *= GammaToLinear(mix(vec3(1.0), stainedGlassColor, vec3(pow(stainedGlassAlbedo.a, 0.2)))); // 按不透明度吸收。
}
#endif // OMNI_END_REFLECTION_INCLUDED 结束。
