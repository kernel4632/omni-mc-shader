/*
末地主岛光源：把悬在主岛上方的点光源按距离与视野角解析照亮附近表面并给高光。
来源：位置与视野角取 Eclipse `lib/settings.glsl:419-421`，按 `docs/eclipse-parity.md` 第 37 行合并，默认关闭。
职责：只提供 `EndIslandLighting`。
调用位置：由 `effects/world/end.glsl` 引入；合成零号在末地有几何的像素上、开启 `OMNI_END_ISLAND_LIGHT` 时调用。
可复制示例：
  `finalComposite += EndIslandLighting(worldPos, worldNormal, worldDir, gbuffer.albedo, gbuffer.material.roughness, gbuffer.material.f0, gbuffer.material.metalness);`
调用前提：由 `effects/world/end.glsl` 引入；`cameraPosition`、内部常数 `END_LIGHT_POS` 与 `Blackbody`、`Fd_Burley`、
  `SpecularGGX` 由绘制主体、本效果入口与 `common/math.glsl` 提供。
关键设计原因与取舍：Eclipse 另建一盏阴影相机（近十五远二百五十六、视野角七十七），需要计算着色器与附加缓冲；
  这里在合成零号按点光源解析照亮，距离窗与视野角照 Eclipse，衰减形状是本项目的近似。
*/
#ifndef OMNI_END_ISLAND_LIGHT_INCLUDED // 只引入一次，避免选项与函数重复定义。
#define OMNI_END_ISLAND_LIGHT_INCLUDED // 置上标记，后续再次引用直接跳过。

// --- 末地主岛光源：把 END_LIGHT_POS 当成悬在主岛上方的点光源，按距离与夹角照亮表面并给高光 ---
// 出处：位置 `lib/settings.glsl:419`、视野角 `:420`、开关 `:421`；Eclipse 在 `dimensions/composite.fsh:509` 按
//   像素到光源重算光方向（`normalize(END_LIGHT_POS-(feetPlayerPos+cameraPosition))`），近处表面受光方向各不相同。
// 与 Eclipse 的取舍：Eclipse 另建一盏阴影相机（`dimensions/begin.csh:100-111`，近十五远二百五十六、视野角七十七），
//   需要计算着色器与附加缓冲；这里在合成零号按点光源解析照亮，距离窗与视野角照 Eclipse，衰减形状是本项目的近似。
// 调用前提：`cameraPosition`、`END_LIGHT_POS` 已可用，`Blackbody`、`Fd_Burley`、`SpecularGGX` 已由 `common/math.glsl` 提供。
vec3 EndIslandLighting(vec3 worldPos, vec3 normal, vec3 viewDir, vec3 albedo, float roughness, float f0, float metalness){
	vec3 lightVec = END_LIGHT_POS - (worldPos + cameraPosition); // 表面指向光源的向量，`worldPos` 是相机相对世界坐标。
	float lightDist = length(lightVec); // 到光源的距离。
	vec3 lightDir = lightVec / max(lightDist, 1e-4); // 单位光方向，防除零。

	// 距离窗：近十五远二百五十六照 Eclipse 的灯（`begin.csh:100-101`），两端各淡出一段，避免出现硬边。
	float distFade = smoothstep(15.0, 40.0, lightDist) * (1.0 - smoothstep(200.0, 256.0, lightDist)); // 距离窗。
	// 锥形窗：光轴竖直向下，方向与轴夹角超过 `OMNI_END_LIGHT_FOV` 一半就淡出；Eclipse 用这个角度构造透视灯。
	float cosAxis = dot(normalize((worldPos + cameraPosition) - END_LIGHT_POS), normalize(-END_LIGHT_POS)); // 表面相对光轴的余弦。
	float cosFov = cos(radians(OMNI_END_LIGHT_FOV * 0.5)); // 视野角一半的余弦，就是锥边的阈值。
	float cone = smoothstep(cosFov, min(cosFov * 1.05 + 0.01, 0.999), cosAxis); // 锥内为一，锥外为零。
	// 距离衰减：Eclipse 用阴影图而不是解析衰减，这里用平方反比近似，参考距离取灯的悬挂高度，让主岛附近接近一。
	float falloff = distFade * cone * OMNI_END_LIGHT_BRIGHTNESS / (1.0 + lightDist * lightDist / 36000.0); // 总衰减。

	vec3 lightColor = Blackbody(6000.0) * 0.3; // 与末地太阳同色温、同强度尺度（合成里用 `Blackbody(6000)` 与系数零点三）。
	vec3 result = albedo * lightColor * falloff * Fd_Burley(normal, -viewDir, lightDir, roughness); // 漫反射乘底色。

	float highlightGGX = SpecularGGX(normal, -viewDir, lightDir, clamp(roughness, 0.0015, 0.9), f0); // 与阳光同一套 GGX 高光。
	highlightGGX *= saturate(4.0 - roughness * 3.5); // 光滑面高光更强。
	highlightGGX *= 0.07; // 与阳光高光同一强度尺度。
	result += mix(vec3(1.0), albedo, vec3(metalness)) * lightColor * falloff * highlightGGX; // 金属面高光带底色。

	return result; // 交回可直接叠加到线性光照的颜色。
}
#endif // OMNI_END_ISLAND_LIGHT_INCLUDED 结束。
