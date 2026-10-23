/*
光照的宿主接线：读取 Minecraft 输入、调用通用库并写出结果。
调用位置：原引用 `effects/lighting/sunlight.glsl` 的程序改为引用本文件。
可复制示例：下方函数保留原有效果入口的签名，调用方式不变。
设计原因与取舍：选项留在效果层，算法在通用库，本文件只做宿主数据与算法之间的转换。
*/
#ifndef OMNI_BIND_LIGHTING_SUNLIGHT_INCLUDED
#define OMNI_BIND_LIGHTING_SUNLIGHT_INCLUDED
#include "/effects/lighting/sunlight.glsl"
/*
光照颜色与天光：算出天光照明需要的四种光色口径，并按表面朝向给表面加上天光照明。
调用位置：四种光色的实际计算内联在 `rendering/lights.glsl:141-153`（那里还要用 `timeNoon` 控制太阳可见度、
  并乘月相亮度，所以没有抽成函数）；本文件只保留 `SkyLighting`，供合成主体给不透明表面算天光与天光云影。
可复制示例：
    `vec3 skylight = SkyLighting(worldNormal, gbuffer.lightmapL.g, cloudShadow);`
设计原因与取舍：
    四种光色都从预计算大气查表得到，光照强度与天光强度用各自的选项分开控制，互不影响。
    火把光色单独用黑体色温算出，与方块光强度解耦，色温只改颜色不改强弱。
    调用前提（iterationT 原样保留）：`SkyLighting` 依赖 `colorSunSkylight`、`colorMoonSkylight`、
    `colorShadowlight`、`worldShadowVector` 等全局量，由绘制主体在引入本文件前声明。
*/
// 四种光色依赖大气查表、云选项、全局光开关与火把色温，按下述顺序引入。
#include "/common/uniforms.glsl"
#include "/common/math.glsl"
#include "/bind/sky/sky.glsl"
#include "/bind/cloud/cloud.glsl"
#include "/bind/lighting/ambient.glsl"
#include "/bind/lighting/blocklight.glsl"
// 说明：原程序里抽出的 `CalculateSunlightColors` 在本项目被内联进 `rendering/lights.glsl`，
// 因为它要配合那里先算好的 `timeNoon`、`timeMidnight` 与月相亮度；留下的重复函数属于死代码，
// 按规范删除，行为与原来一致，记录见 `docs/parity.md` 的偏离清单。
// 天光照明：按表面法线朝向与天光等级，把太阳与月亮的环境光和直射光分配到表面上。
// 调用前提：`colorSunSkylight`、`colorMoonSkylight`、`colorShadowlight`、`worldShadowVector`、`wetness`、
//     `isEyeInWater` 已由绘制主体声明；`cloudShadow` 是云影透过率。
vec3 SkyLighting(vec3 worldNormal, float lightmap, float cloudShadow){
	float lightmapFalloff = saturate(lightmap * 2.5 - 0.2); // 天光等级的非线性映射。
	lightmapFalloff = curve(lightmapFalloff) * 0.6 + 0.4; // 再压一段，保留一点底光。
	float SdotN = dot(worldNormal, normalize(worldSunVector + vec3(0.0, 1.0, 0.0))) * lightmapFalloff; // 太阳侧方向性与天光等级。
	float MdotN = dot(worldNormal, normalize(worldMoonVector + vec3(0.0, 1.0, 0.0))) * lightmapFalloff; // 月亮侧方向性与天光等级。
	vec3 skylight = colorSunSkylight * (SdotN * 0.35 + 0.65); // 太阳侧环境光按朝向分一点。
	skylight += colorMoonSkylight * (MdotN * 0.35 + 0.65); // 月亮侧同理。
	vec3 skySunLight = (worldNormal.y * 0.4 * lightmapFalloff + 0.6) * colorShadowlight * 0.025; // 朝上的面额外接一份直射方向的天光。
	#if OMNI_GI_RSM // 有全局光时这份天光已经算过，不再加倍。
		skylight += skySunLight; // 直接加上。
	#else // 没有全局光时补一份替代。
		skylight += skySunLight * 1.5; // 放大补偿。
	#endif
	#ifdef OMNI_VOLUMETRIC_CLOUDS // 有体积云时云也会影响天光。
		float coverage = mix(OMNI_CLOUD_CLEAR_COVERAGE, OMNI_CLOUD_RAIN_COVERAGE, wetness); // 晴雨两档云量。
		skylight += skySunLight * ((1.0 - wetness) * saturate(coverage * 4.0 - 0.6)); // 晴天云多的地方补一份散射。
		#ifdef OMNI_CLOUD_SHADOW // 有云影时云影也压天光。
			float LdotN = dot(worldNormal, worldShadowVector) * lightmapFalloff * 0.4 + 0.6; // 光方向与法线的方向性。
			skylight += colorShadowlight * (LdotN * (0.05 - 0.05 * cloudShadow) * (1.0 - wetness)); // 云影越深补得越少。
		#endif
	#endif
	skylight = mix(skylight, colorShadowlight * (SdotN * 0.012 + 0.015), wetness * 0.8); // 雨天换成一组阴天环境光。
	return skylight * max(float(isEyeInWater == 1) * 0.003, lightmap * 0.2 * OMNI_SKYLIGHT_INTENSITY); // 水下与天光等级共同缩放。
}
#endif // OMNI_BIND_LIGHTING_SUNLIGHT_INCLUDED
